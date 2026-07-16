import Foundation

actor LocalPlayerProfileRepository {
    private let fileStore: AtomicProfileFileStore
    private let catalog: LaunchCatalog
    private let deviceID: String
    private let accountIdentity: PlayerAccountIdentity
    private let economyMutationPolicy: EconomyMutationPolicy

    private var document: LocalPlayerDocumentV1?
    private let sessionNonce: UUID
    private var sessionIsActive = false
    private(set) var lastLoadReport: ProfileLoadReport?

    init(
        directoryURL: URL,
        deviceID: String,
        accountIdentity: PlayerAccountIdentity,
        sessionNonce: UUID = UUID(),
        catalog: LaunchCatalog = .approved,
        economyMutationPolicy: EconomyMutationPolicy = .requireDurablePrivateCloud,
        migrator: any PlayerProfileMigrating = PlayerProfileMigrator()
    ) {
        precondition(
            ProfileStampDeviceIDRuleV1.isValid(deviceID),
            "A valid stable profile-stamp device ID is required"
        )
        fileStore = AtomicProfileFileStore(
            directoryURL: directoryURL,
            migrator: migrator
        )
        self.catalog = catalog
        self.deviceID = deviceID
        self.accountIdentity = accountIdentity
        self.sessionNonce = sessionNonce
        self.economyMutationPolicy = economyMutationPolicy
    }

    @discardableResult
    func load(
        at date: Date = Date(),
        newProfileID: UUID = UUID()
    ) throws -> LocalPlayerProfileSnapshot {
        if let document {
            guard sessionIsActive else {
                throw LocalPlayerRepositoryError.sessionInvalidated
            }
            return try makeSnapshot(for: document)
        }

        let loaded = try fileStore.loadOrCreate(
            defaultDocument: PlayerProfileFactory.makeDefault(
                profileID: newProfileID,
                accountIdentity: accountIdentity,
                deviceID: deviceID,
                createdAt: date,
                catalog: catalog
            ),
            at: date,
            catalog: catalog
        )
        guard loaded.document.accountIdentity == accountIdentity else {
            throw LocalPlayerRepositoryError.accountIdentityMismatch(
                expected: accountIdentity,
                actual: loaded.document.accountIdentity
            )
        }
        document = loaded.document
        sessionIsActive = true
        lastLoadReport = loaded.report
        return try makeSnapshot(for: loaded.document)
    }

    func snapshot() throws -> LocalPlayerProfileSnapshot {
        try makeSnapshot(for: requireActiveDocument())
    }

    func settlementReceipt(
        for runID: RunID,
        session: ProfileSessionToken
    ) throws -> RunSettlementOutcome? {
        let document = try requireActiveDocument()
        try validateSession(session, against: document)
        return document.settlementReceipts[runID]
    }

    /// Must be called by the account coordinator before it publishes a new
    /// account. Every in-flight operation holding the prior token is rejected.
    func invalidateForAccountSwitch() {
        guard sessionIsActive else { return }
        sessionIsActive = false
    }

    @discardableResult
    func settle(
        _ run: CompletedRun,
        session: ProfileSessionToken,
        recordedAt: Date = Date()
    ) throws -> RunSettlementResult {
        let current = try requireActiveDocument()
        try validateSession(session, against: current)
        do {
            try CompletedRunValidator.validate(
                run,
                recordedAt: recordedAt,
                inventory: current.player.inventory,
                catalog: catalog
            )
        } catch let error as CompletedRunValidationError {
            throw LocalPlayerRepositoryError.invalidRun(error)
        }
        if let receipt = current.settlementReceipts[run.runID] {
            guard receipt.record.run == run else {
                throw LocalPlayerRepositoryError.runIDConflict(run.runID)
            }
            return RunSettlementResult(
                outcome: receipt,
                wasAlreadySettled: true
            )
        }
        if current.player.completedRuns[run.runID] != nil {
            throw LocalPlayerRepositoryError.runIDConflict(run.runID)
        }

        var next = current
        let rewardCoins = try CompletedRunValidator.rewardCoins(for: run)
        let isRewardEligible = CompletedRunValidator.isRewardEligible(run)
        var gameplayRewardEntryID: LedgerEntryID?
        if rewardCoins > 0 {
            let entryID = CoinLedgerID.gameplay(runID: run.runID)
            guard next.player.ledger[entryID] == nil else {
                throw LocalPlayerRepositoryError.ledgerIDConflict(entryID)
            }
            next.player.ledger[entryID] = CoinLedgerEntry(
                id: entryID,
                delta: rewardCoins,
                reason: .gameplay(
                    runID: run.runID,
                    economyVersion: run.configuration.economyVersion
                ),
                createdAt: recordedAt
            )
            next.pendingLedgerEntryIDs.insert(entryID)
            gameplayRewardEntryID = entryID
        }

        var signingBonusEntryID: LedgerEntryID?
        if isRewardEligible {
            let entryID = CoinLedgerID.signingBonus(
                version: PersistedEconomyRulesV1.signingBonusVersion
            )
            if next.player.ledger[entryID] == nil {
                next.player.ledger[entryID] = CoinLedgerEntry(
                    id: entryID,
                    delta: PersistedEconomyRulesV1.signingBonusCoins,
                    reason: .signingBonus(
                        version: PersistedEconomyRulesV1.signingBonusVersion
                    ),
                    createdAt: PersistedEconomyRulesV1.signingBonusLedgerCreatedAt
                )
                next.pendingLedgerEntryIDs.insert(entryID)
                signingBonusEntryID = entryID
            }
        }

        next.player.career = try PersistedCareerAccumulatorV1.applying(
            run,
            to: next.player.career
        )
        let achievementUpdates = AchievementEvaluator.evaluate(
            run: run,
            careerAfter: next.player.career,
            existing: next.player.achievementProgress,
            evaluatedAt: recordedAt
        )
        for update in achievementUpdates {
            next.player.achievementProgress[update.current.id] = update.current
            next.player.pendingGameCenter.enqueueAchievement(update.current)
        }
        if CompletedRunValidator.isNaturallyCompleted(run) {
            next.player.pendingGameCenter.enqueueHighScore(run.score)
        }

        var rewardedOfferUnlocked: RewardOfferID?
        if isRewardEligible {
            let observation = RewardedRunObservation(
                observedCycle: next.player.rewardedAdState.cycle,
                disposition: next.player.rewardedAdState.eligibleOfferID == nil
                    ? .candidate
                    : .ignoredWhileOfferPending
            )
            if next.rewardedRunObservations == nil {
                next.rewardedRunObservations = [:]
            }
            next.rewardedRunObservations?[run.runID] = observation
            if next.player.rewardedAdState.recordValidRun(run.runID) {
                rewardedOfferUnlocked = next.player.rewardedAdState.eligibleOfferID
            }
        }

        let record = CompletedRunRecord(
            run: run,
            recordedAt: recordedAt,
            rewardCoins: rewardCoins
        )
        let outcome = RunSettlementOutcome(
            record: record,
            gameplayRewardEntryID: gameplayRewardEntryID,
            signingBonusEntryID: signingBonusEntryID,
            achievementUpdates: achievementUpdates,
            rewardedOfferUnlocked: rewardedOfferUnlocked,
            resultingPersonalBest: next.player.career.highestScore
        )
        next.player.completedRuns[run.runID] = record
        next.settlementReceipts[run.runID] = outcome

        try incrementRevisions(of: &next, economyChanged: true)
        try persist(next, at: recordedAt)
        return RunSettlementResult(
            outcome: outcome,
            wasAlreadySettled: false
        )
    }

    /// Marks already-recorded pending credits as durable. Repeating the same
    /// confirmation is a no-op, which makes reconnect retries safe.
    @discardableResult
    func confirmPendingCredits(
        _ entryIDs: Set<LedgerEntryID>,
        session: ProfileSessionToken,
        confirmation: DurableEconomyConfirmation,
        savedAt: Date = Date()
    ) throws -> LocalPlayerProfileSnapshot {
        var next = try requireActiveDocument()
        try validateSession(session, against: next)
        let balances = try PlayerProfileProjection.coinBalances(for: next)
        var expectedEntries: [LedgerEntryID: CoinLedgerEntry] = [:]

        for entryID in entryIDs {
            guard let entry = next.player.ledger[entryID] else {
                throw LocalPlayerRepositoryError.pendingCreditNotFound(entryID)
            }
            guard entry.delta > 0 else {
                throw LocalPlayerRepositoryError.invalidCredit(entryID)
            }
            expectedEntries[entryID] = entry
        }
        try validateConfirmationBinding(
            confirmation,
            expectedEntries: expectedEntries,
            session: session
        )

        guard entryIDs.contains(where: { next.pendingLedgerEntryIDs.contains($0) }) else {
            return try makeSnapshot(for: next)
        }
        try validateConfirmationFreshness(
            confirmation,
            document: next,
            balances: balances
        )
        next.pendingLedgerEntryIDs.subtract(entryIDs)
        try incrementRevisions(of: &next, economyChanged: true)
        try persist(next, at: savedAt)
        return try makeSnapshot(for: next)
    }

    /// Records a credit that an external service has already made durable.
    /// Deterministic ledger IDs turn repeated delivery into an idempotent read.
    @discardableResult
    func recordConfirmedCredit(
        _ entry: CoinLedgerEntry,
        session: ProfileSessionToken,
        confirmation: DurableEconomyConfirmation,
        savedAt: Date = Date()
    ) throws -> LocalPlayerProfileSnapshot {
        guard entry.delta > 0 else {
            throw LocalPlayerRepositoryError.invalidCredit(entry.id)
        }

        var next = try requireActiveDocument()
        try validateSession(session, against: next)
        let balances = try PlayerProfileProjection.coinBalances(for: next)
        try validateConfirmationBinding(
            confirmation,
            expectedEntries: [entry.id: entry],
            session: session
        )
        if let existing = next.player.ledger[entry.id] {
            guard existing == entry else {
                throw LocalPlayerRepositoryError.ledgerIDConflict(entry.id)
            }
            guard !next.pendingLedgerEntryIDs.contains(entry.id) else {
                throw LocalPlayerRepositoryError.ledgerIDConflict(entry.id)
            }
            return try makeSnapshot(for: next)
        }

        try validateConfirmationFreshness(
            confirmation,
            document: next,
            balances: balances
        )
        next.player.ledger[entry.id] = entry
        do {
            _ = try CoinLedger.balance(entries: [entry])
        } catch {
            throw LocalPlayerRepositoryError.invalidCredit(entry.id)
        }
        try incrementRevisions(of: &next, economyChanged: true)
        try persist(next, at: savedAt)
        return try makeSnapshot(for: next)
    }

    /// Produces the exact compare-and-swap payload for the private-cloud
    /// transaction. This is read-only; ownership and the debit remain local-
    /// state unchanged until `unlock(using:session:at:)` receives its receipt.
    func prepareUnlock(
        itemID: CatalogItemID,
        operationID: OperationID,
        session: ProfileSessionToken
    ) throws -> DurableCatalogUnlockRequest {
        let current = try requireActiveDocument()
        try validateSession(session, against: current)
        guard let item = catalog.item(id: itemID) else {
            throw LocalPlayerRepositoryError.inventory(.unknownCatalogItem(itemID))
        }
        guard !itemIsOwned(item, inventory: current.player.inventory) else {
            throw LocalPlayerRepositoryError.inventory(.alreadyOwned(itemID))
        }
        let balances = try PlayerProfileProjection.coinBalances(for: current)
        let price = PersistedEconomyRulesV1.catalogPrice(for: item)
        guard balances.confirmed >= price else {
            throw LocalPlayerRepositoryError.insufficientConfirmedCoins(
                required: price,
                available: balances.confirmed
            )
        }
        return DurableCatalogUnlockRequest(
            operationID: operationID,
            session: session,
            itemID: itemID,
            ledgerEntryID: CoinLedgerID.catalogUnlock(itemID: itemID),
            price: price,
            expectedEconomyRevision: current.economyRevision,
            confirmedBalanceBefore: balances.confirmed
        )
    }

    @discardableResult
    func unlock(
        using receipt: DurableCatalogUnlockReceipt,
        session: ProfileSessionToken,
        at date: Date = Date()
    ) throws -> CatalogUnlockOutcome {
        try validateAuthority(receipt.authority)
        let current = try requireActiveDocument()
        try validateSession(session, against: current)
        guard receipt.session == session,
              !receipt.requestOperationID.rawValue.isEmpty,
              receipt.confirmedAt.timeIntervalSince1970.isFinite else {
            throw LocalPlayerRepositoryError.durableUnlockReceiptMismatch
        }

        let itemID = receipt.itemID
        guard let item = catalog.item(id: itemID) else {
            throw LocalPlayerRepositoryError.inventory(.unknownCatalogItem(itemID))
        }
        let ledgerID = CoinLedgerID.catalogUnlock(itemID: itemID)
        let persistedPrice = PersistedEconomyRulesV1.catalogPrice(for: item)
        guard receipt.ledgerEntryID == ledgerID,
              receipt.price == persistedPrice else {
            throw LocalPlayerRepositoryError.durableUnlockReceiptMismatch
        }
        let currentBalances = try PlayerProfileProjection.coinBalances(for: current)
        let expectedAfter = receipt.confirmedBalanceBefore.subtractingReportingOverflow(
            receipt.price
        )
        guard !expectedAfter.overflow,
              receipt.confirmedBalanceBefore >= receipt.price,
              receipt.confirmedBalanceAfter == expectedAfter.partialValue else {
            throw LocalPlayerRepositoryError.durableUnlockReceiptMismatch
        }

        let expectedEntry = CoinLedgerEntry(
            id: ledgerID,
            delta: -persistedPrice,
            reason: .catalogUnlock(itemID: itemID),
            createdAt: receipt.confirmedAt
        )
        if itemIsOwned(item, inventory: current.player.inventory),
           current.player.ledger[ledgerID] == expectedEntry {
            return CatalogUnlockOutcome(
                itemID: itemID,
                price: persistedPrice,
                wasAlreadyUnlocked: true,
                confirmedBalanceAfter: currentBalances.confirmed
            )
        }

        guard !itemIsOwned(item, inventory: current.player.inventory),
              current.player.ledger[ledgerID] == nil else {
            throw LocalPlayerRepositoryError.durableUnlockReceiptMismatch
        }
        guard receipt.expectedEconomyRevision == current.economyRevision else {
            throw LocalPlayerRepositoryError.economyStateStale(
                expected: receipt.expectedEconomyRevision,
                actual: current.economyRevision
            )
        }
        guard receipt.confirmedBalanceBefore == currentBalances.confirmed else {
            throw LocalPlayerRepositoryError.economyBalanceStale(
                expected: receipt.confirmedBalanceBefore,
                actual: currentBalances.confirmed
            )
        }
        guard currentBalances.confirmed >= receipt.price else {
            throw LocalPlayerRepositoryError.insufficientConfirmedCoins(
                required: receipt.price,
                available: currentBalances.confirmed
            )
        }

        var next = current
        do {
            _ = try InventoryRules.applyUnlock(
                itemID: itemID,
                to: &next.player.inventory,
                catalog: catalog
            )
        } catch let error as InventoryRuleError {
            throw LocalPlayerRepositoryError.inventory(error)
        }

        let rememberedJerseyInsertion: (teamID: TeamID, jerseyID: JerseyID)?
        if case let .team(teamID) = item.kind,
           next.player.selection.value.selectedJerseyByTeam[teamID] == nil,
           let team = catalog.team(id: teamID) {
            rememberedJerseyInsertion = (teamID, team.primaryJersey.id)
        } else {
            rememberedJerseyInsertion = nil
        }

        next.player.ledger[ledgerID] = expectedEntry

        if let rememberedJerseyInsertion {
            try applySelectionMutation(
                to: &next,
                economyChanged: true,
                at: date
            ) { selection in
                selection.selectedJerseyByTeam[rememberedJerseyInsertion.teamID]
                    = rememberedJerseyInsertion.jerseyID
            }
        } else {
            try incrementRevisions(of: &next, economyChanged: true)
        }
        try persist(next, at: date)
        let balanceAfter = try PlayerProfileProjection.coinBalances(for: next).confirmed
        return CatalogUnlockOutcome(
            itemID: itemID,
            price: persistedPrice,
            wasAlreadyUnlocked: false,
            confirmedBalanceAfter: balanceAfter
        )
    }

    /// Applies a server-verified rewarded-ad grant and consumes its five-run
    /// offer in one local transaction. The provider transaction ID is the
    /// idempotency key across callback retries, process restarts, and SSV replay.
    @discardableResult
    func settleRewardedAd(
        using receipt: DurableRewardedAdReceipt,
        session: ProfileSessionToken,
        savedAt: Date = Date()
    ) throws -> RewardedAdSettlementOutcome {
        let current = try requireActiveDocument()
        try validateSession(session, against: current)
        try validateAuthority(receipt.authority)
        guard receipt.session == session,
              receipt.rewardedAt.timeIntervalSince1970.isFinite else {
            throw LocalPlayerRepositoryError.rewardedAdReceiptMismatch
        }

        let ledgerID = CoinLedgerID.rewardedAd(
            providerTransactionID: receipt.providerTransactionID
        )
        let expectedEntry = CoinLedgerEntry(
            id: ledgerID,
            delta: PersistedEconomyRulesV1.rewardedAdCoins,
            reason: .rewardedAd(
                offerID: receipt.offerID,
                providerTransactionID: receipt.providerTransactionID
            ),
            createdAt: receipt.rewardedAt
        )
        let balances = try PlayerProfileProjection.coinBalances(for: current)

        if let existing = current.player.ledger[ledgerID] {
            guard existing == expectedEntry,
                  current.player.rewardedAdState.eligibleOfferID != receipt.offerID else {
                throw LocalPlayerRepositoryError.ledgerIDConflict(ledgerID)
            }
            return RewardedAdSettlementOutcome(
                offerID: receipt.offerID,
                providerTransactionID: receipt.providerTransactionID,
                ledgerEntryID: ledgerID,
                coins: PersistedEconomyRulesV1.rewardedAdCoins,
                wasAlreadySettled: true,
                confirmedBalanceAfter: balances.confirmed
            )
        }

        guard receipt.expectedEconomyRevision == current.economyRevision else {
            throw LocalPlayerRepositoryError.economyStateStale(
                expected: receipt.expectedEconomyRevision,
                actual: current.economyRevision
            )
        }
        guard receipt.confirmedBalanceBefore == balances.confirmed else {
            throw LocalPlayerRepositoryError.economyBalanceStale(
                expected: receipt.confirmedBalanceBefore,
                actual: balances.confirmed
            )
        }
        guard current.player.rewardedAdState.eligibleOfferID == receipt.offerID else {
            throw LocalPlayerRepositoryError.rewardedOfferNotEligible(receipt.offerID)
        }
        let expectedBalance = balances.confirmed.addingReportingOverflow(
            PersistedEconomyRulesV1.rewardedAdCoins
        )
        guard !expectedBalance.overflow else {
            throw LocalPlayerRepositoryError.validation(.arithmeticOverflow)
        }

        var next = current
        next.player.ledger[ledgerID] = expectedEntry
        guard next.player.rewardedAdState.redeem(receipt.offerID) else {
            throw LocalPlayerRepositoryError.rewardedOfferNotEligible(receipt.offerID)
        }
        try incrementRevisions(of: &next, economyChanged: true)
        try persist(next, at: savedAt)
        let balanceAfter = try PlayerProfileProjection.coinBalances(for: next).confirmed
        guard balanceAfter == expectedBalance.partialValue else {
            throw LocalPlayerRepositoryError.rewardedAdReceiptMismatch
        }
        return RewardedAdSettlementOutcome(
            offerID: receipt.offerID,
            providerTransactionID: receipt.providerTransactionID,
            ledgerEntryID: ledgerID,
            coins: PersistedEconomyRulesV1.rewardedAdCoins,
            wasAlreadySettled: false,
            confirmedBalanceAfter: balanceAfter
        )
    }

    @discardableResult
    func selectTeam(
        _ teamID: TeamID,
        session: ProfileSessionToken,
        at date: Date = Date()
    ) throws -> LocalPlayerProfileSnapshot {
        var next = try requireActiveDocument()
        try validateSession(session, against: next)
        guard let team = catalog.team(id: teamID) else {
            throw LocalPlayerRepositoryError.inventory(.unknownTeam(teamID))
        }
        guard next.player.inventory.ownedTeamIDs.contains(teamID) else {
            throw LocalPlayerRepositoryError.inventory(.teamNotOwned(teamID))
        }
        if next.player.selection.value.selectedTeamID == teamID {
            return try makeSnapshot(for: next)
        }

        let ownedJerseyIDs = next.player.inventory.ownedJerseyIDs
        try applySelectionMutation(to: &next, economyChanged: false, at: date) { selection in
            let rememberedJersey = selection.selectedJerseyByTeam[teamID]
            if rememberedJersey.map(ownedJerseyIDs.contains) != true {
                selection.selectedJerseyByTeam[teamID] = team.primaryJersey.id
            }
            selection.selectedTeamID = teamID
        }
        try persist(next, at: date)
        return try makeSnapshot(for: next)
    }

    @discardableResult
    func equipJersey(
        _ jerseyID: JerseyID,
        for teamID: TeamID,
        session: ProfileSessionToken,
        at date: Date = Date()
    ) throws -> LocalPlayerProfileSnapshot {
        var next = try requireActiveDocument()
        try validateSession(session, against: next)
        guard next.player.inventory.ownedTeamIDs.contains(teamID) else {
            throw LocalPlayerRepositoryError.inventory(.teamNotOwned(teamID))
        }
        guard let jersey = catalog.jersey(id: jerseyID) else {
            throw LocalPlayerRepositoryError.inventory(.unknownJersey(jerseyID))
        }
        guard jersey.teamID == teamID else {
            throw LocalPlayerRepositoryError.inventory(
                .jerseyDoesNotBelongToTeam(jerseyID: jerseyID, teamID: teamID)
            )
        }
        guard next.player.inventory.ownedJerseyIDs.contains(jerseyID) else {
            throw LocalPlayerRepositoryError.inventory(.jerseyNotOwned(jerseyID))
        }
        if next.player.selection.value.selectedJerseyByTeam[teamID] == jerseyID {
            return try makeSnapshot(for: next)
        }

        try applySelectionMutation(to: &next, economyChanged: false, at: date) {
            $0.selectedJerseyByTeam[teamID] = jerseyID
        }
        try persist(next, at: date)
        return try makeSnapshot(for: next)
    }

    @discardableResult
    func equipFootball(
        _ footballID: FootballID,
        session: ProfileSessionToken,
        at date: Date = Date()
    ) throws -> LocalPlayerProfileSnapshot {
        var next = try requireActiveDocument()
        try validateSession(session, against: next)
        guard catalog.football(id: footballID) != nil else {
            throw LocalPlayerRepositoryError.inventory(.unknownFootball(footballID))
        }
        guard next.player.inventory.ownedFootballIDs.contains(footballID) else {
            throw LocalPlayerRepositoryError.inventory(.footballNotOwned(footballID))
        }
        if next.player.selection.value.selectedFootballID == footballID {
            return try makeSnapshot(for: next)
        }

        try applySelectionMutation(to: &next, economyChanged: false, at: date) {
            $0.selectedFootballID = footballID
        }
        try persist(next, at: date)
        return try makeSnapshot(for: next)
    }

    @discardableResult
    func updateSettings(
        _ settings: PlayerSettings,
        session: ProfileSessionToken,
        at date: Date = Date()
    ) throws -> LocalPlayerProfileSnapshot {
        var next = try requireActiveDocument()
        try validateSession(session, against: next)
        let sanitized = PlayerSettings(
            musicVolume: settings.musicVolume,
            sfxVolume: settings.sfxVolume,
            isMuted: settings.isMuted,
            reducedMotion: settings.reducedMotion,
            tutorialCompleted: settings.tutorialCompleted
        )
        if next.player.settings.value == sanitized {
            return try makeSnapshot(for: next)
        }

        try applySettingsMutation(sanitized, to: &next, at: date)
        try persist(next, at: date)
        return try makeSnapshot(for: next)
    }

    private func requireActiveDocument() throws -> LocalPlayerDocumentV1 {
        guard sessionIsActive else {
            throw document == nil
                ? LocalPlayerRepositoryError.notLoaded
                : LocalPlayerRepositoryError.sessionInvalidated
        }
        guard let document else {
            throw LocalPlayerRepositoryError.notLoaded
        }
        return document
    }

    private func makeSnapshot(
        for document: LocalPlayerDocumentV1
    ) throws -> LocalPlayerProfileSnapshot {
        try PlayerProfileProjection.snapshot(
            for: document,
            session: ProfileSessionToken(
                accountIdentity: accountIdentity,
                nonce: sessionNonce,
                profileID: document.player.profileID
            )
        )
    }

    private func validateSession(
        _ session: ProfileSessionToken,
        against document: LocalPlayerDocumentV1
    ) throws {
        guard sessionIsActive else {
            throw LocalPlayerRepositoryError.sessionInvalidated
        }
        let active = ProfileSessionToken(
            accountIdentity: accountIdentity,
            nonce: sessionNonce,
            profileID: document.player.profileID
        )
        guard session == active else {
            throw LocalPlayerRepositoryError.sessionMismatch
        }
    }

    private func persist(_ next: LocalPlayerDocumentV1, at date: Date) throws {
        guard next.accountIdentity == accountIdentity else {
            throw LocalPlayerRepositoryError.accountIdentityMismatch(
                expected: accountIdentity,
                actual: next.accountIdentity
            )
        }
        do {
            try PlayerProfileValidator.validate(next, catalog: catalog)
        } catch let error as ProfileValidationError {
            throw LocalPlayerRepositoryError.validation(error)
        }
        try fileStore.save(next, at: date, catalog: catalog)
        document = next
    }

    private func incrementRevisions(
        of document: inout LocalPlayerDocumentV1,
        economyChanged: Bool
    ) throws {
        let advance = try makeRevisionAdvance(
            for: document,
            economyChanged: economyChanged,
            logicalCounter: nil
        )
        apply(advance, to: &document)
    }

    private struct RevisionAdvance {
        let playerRevision: UInt64
        let economyRevision: UInt64?
        let logicalCounter: UInt64?
    }

    private func makeRevisionAdvance(
        for document: LocalPlayerDocumentV1,
        economyChanged: Bool,
        logicalCounter: UInt64?
    ) throws -> RevisionAdvance {
        let nextPlayerRevision = document.player.revision.addingReportingOverflow(1)
        guard !nextPlayerRevision.overflow else {
            throw LocalPlayerRepositoryError.validation(.arithmeticOverflow)
        }

        let nextEconomyRevision: UInt64?
        if economyChanged {
            let result = document.economyRevision.addingReportingOverflow(1)
            guard !result.overflow else {
                throw LocalPlayerRepositoryError.validation(.arithmeticOverflow)
            }
            nextEconomyRevision = result.partialValue
        } else {
            nextEconomyRevision = nil
        }

        let nextLogicalCounter: UInt64?
        if let logicalCounter {
            let result = logicalCounter.addingReportingOverflow(1)
            guard !result.overflow else {
                throw LocalPlayerRepositoryError.validation(.arithmeticOverflow)
            }
            nextLogicalCounter = result.partialValue
        } else {
            nextLogicalCounter = nil
        }

        return RevisionAdvance(
            playerRevision: nextPlayerRevision.partialValue,
            economyRevision: nextEconomyRevision,
            logicalCounter: nextLogicalCounter
        )
    }

    private func apply(
        _ advance: RevisionAdvance,
        to document: inout LocalPlayerDocumentV1
    ) {
        document.player.revision = advance.playerRevision
        if let economyRevision = advance.economyRevision {
            document.economyRevision = economyRevision
        }
    }

    private func applySettingsMutation(
        _ settings: PlayerSettings,
        to document: inout LocalPlayerDocumentV1,
        at date: Date
    ) throws {
        let advance = try makeRevisionAdvance(
            for: document,
            economyChanged: false,
            logicalCounter: document.player.settings.logicalCounter
        )
        guard let logicalCounter = advance.logicalCounter else {
            throw LocalPlayerRepositoryError.validation(.arithmeticOverflow)
        }
        document.player.settings = Stamped(
            value: settings,
            modifiedAt: date,
            deviceID: deviceID,
            logicalCounter: logicalCounter
        )
        apply(advance, to: &document)
    }

    private func applySelectionMutation(
        to document: inout LocalPlayerDocumentV1,
        economyChanged: Bool,
        at date: Date,
        mutation: (inout PlayerSelection) -> Void
    ) throws {
        let advance = try makeRevisionAdvance(
            for: document,
            economyChanged: economyChanged,
            logicalCounter: document.player.selection.logicalCounter
        )
        guard let logicalCounter = advance.logicalCounter else {
            throw LocalPlayerRepositoryError.validation(.arithmeticOverflow)
        }
        var selection = document.player.selection.value
        mutation(&selection)
        document.player.selection = Stamped(
            value: selection,
            modifiedAt: date,
            deviceID: deviceID,
            logicalCounter: logicalCounter
        )
        apply(advance, to: &document)
    }

    private func validateAuthority(_ authority: EconomyStateAuthority) throws {
        guard economyMutationPolicy.permits(authority) else {
            throw LocalPlayerRepositoryError.economyAuthorityRejected(authority)
        }
    }

    private func validateConfirmationBinding(
        _ confirmation: DurableEconomyConfirmation,
        expectedEntries: [LedgerEntryID: CoinLedgerEntry],
        session: ProfileSessionToken
    ) throws {
        try validateAuthority(confirmation.authority)
        guard !expectedEntries.isEmpty,
              confirmation.session == session,
              confirmation.entries == expectedEntries,
              confirmation.confirmedAt.timeIntervalSince1970.isFinite else {
            throw LocalPlayerRepositoryError.economyConfirmationBindingMismatch
        }
    }

    private func validateConfirmationFreshness(
        _ confirmation: DurableEconomyConfirmation,
        document: LocalPlayerDocumentV1,
        balances: CoinBalanceSummary
    ) throws {
        guard confirmation.expectedEconomyRevision == document.economyRevision else {
            throw LocalPlayerRepositoryError.economyStateStale(
                expected: confirmation.expectedEconomyRevision,
                actual: document.economyRevision
            )
        }
        guard confirmation.confirmedBalanceBefore == balances.confirmed else {
            throw LocalPlayerRepositoryError.economyBalanceStale(
                expected: confirmation.confirmedBalanceBefore,
                actual: balances.confirmed
            )
        }
    }

    private func itemIsOwned(
        _ item: CatalogItemDescriptor,
        inventory: PlayerInventory
    ) -> Bool {
        switch item.kind {
        case let .team(teamID):
            inventory.ownedTeamIDs.contains(teamID)
        case let .alternateJersey(jerseyID):
            inventory.ownedJerseyIDs.contains(jerseyID)
        case let .football(footballID):
            inventory.ownedFootballIDs.contains(footballID)
        }
    }
}

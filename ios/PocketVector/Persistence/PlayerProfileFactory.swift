import Foundation

enum PlayerProfileFactory {
    static func makeDefault(
        profileID: UUID = UUID(),
        accountIdentity: PlayerAccountIdentity,
        deviceID: String,
        createdAt: Date,
        catalog: LaunchCatalog = .approved
    ) -> LocalPlayerDocumentV1 {
        let settings = PlayerSettings(
            musicVolume: 0.38,
            sfxVolume: 0.72,
            isMuted: false,
            reducedMotion: false,
            tutorialCompleted: false
        )
        let selection = InventoryRules.initialSelection(catalog: catalog)
        let achievements = Dictionary(
            uniqueKeysWithValues: AchievementCatalog.launch.map {
                ($0.id, AchievementProgress(id: $0.id))
            }
        )

        return LocalPlayerDocumentV1(
            accountIdentity: accountIdentity,
            player: PlayerDocumentV1(
                profileID: profileID,
                revision: 0,
                createdAt: createdAt,
                settings: Stamped(
                    value: settings,
                    modifiedAt: createdAt,
                    deviceID: deviceID,
                    logicalCounter: 0
                ),
                selection: Stamped(
                    value: selection,
                    modifiedAt: createdAt,
                    deviceID: deviceID,
                    logicalCounter: 0
                ),
                inventory: InventoryRules.initialInventory(catalog: catalog),
                completedRuns: [:],
                ledger: [:],
                career: CareerStatistics(),
                achievementProgress: achievements,
                rewardedAdState: RewardedAdState(),
                pendingGameCenter: PlayerScopedGameCenterQueueV1()
            ),
            economyRevision: 0,
            pendingLedgerEntryIDs: [],
            settlementReceipts: [:],
            rewardedRunObservations: [:]
        )
    }
}

enum PlayerProfileProjection {
    static func coinBalances(for document: LocalPlayerDocumentV1) throws -> CoinBalanceSummary {
        let allEntries = Array(document.player.ledger.values)
        let confirmedEntries = allEntries.filter {
            !document.pendingLedgerEntryIDs.contains($0.id)
        }

        let total: Int64
        let confirmed: Int64
        do {
            total = try CoinLedger.balance(entries: allEntries)
            confirmed = try CoinLedger.balance(entries: confirmedEntries)
        } catch let error as CoinLedgerValidationError {
            throw ProfileValidationError.invalidLedger(error)
        }

        let subtraction = total.subtractingReportingOverflow(confirmed)
        guard !subtraction.overflow else {
            throw ProfileValidationError.arithmeticOverflow
        }
        return CoinBalanceSummary(
            confirmed: confirmed,
            pending: subtraction.partialValue
        )
    }

    static func snapshot(
        for document: LocalPlayerDocumentV1,
        session: ProfileSessionToken,
        syncStatus: ProfileSyncStatus = .localOnly
    ) throws -> LocalPlayerProfileSnapshot {
        let balances = try coinBalances(for: document)
        let player = document.player
        return LocalPlayerProfileSnapshot(
            session: session,
            player: PlayerSnapshot(
                profileID: player.profileID,
                revision: player.revision,
                settings: player.settings.value,
                selection: player.selection.value,
                inventory: player.inventory,
                career: player.career,
                coinBalance: balances.total,
                achievementProgress: player.achievementProgress,
                rewardedAdState: player.rewardedAdState,
                syncStatus: syncStatus
            ),
            economyRevision: document.economyRevision,
            coinBalances: balances,
            completedRuns: player.completedRuns,
            ledger: player.ledger,
            pendingLedgerEntryIDs: document.pendingLedgerEntryIDs,
            rewardedRunObservations: document.rewardedRunObservations ?? [:]
        )
    }
}

enum PlayerProfileValidator {
    static func validate(
        _ document: LocalPlayerDocumentV1,
        catalog: LaunchCatalog = .approved
    ) throws {
        guard !document.accountIdentity.rawValue.isEmpty else {
            throw ProfileValidationError.invalidAccountIdentity
        }
        try validateFieldStamps(document.player)
        try validateKeys(document)
        try validateInventory(document.player, catalog: catalog)
        try validateSettingsAndProgress(document.player)
        try validateLedger(document, catalog: catalog)
        try validateRuns(document, catalog: catalog)
        try validateRewardedAdState(document.player)
        try validateRewardedRunObservations(document)
        try validateCareer(document.player)
    }

    private static func validateFieldStamps(_ player: PlayerDocumentV1) throws {
        guard player.settings.modifiedAt.timeIntervalSince1970.isFinite,
              ProfileStampDeviceIDRuleV1.isValid(player.settings.deviceID) else {
            throw ProfileValidationError.invalidSettingsStamp
        }
        guard player.selection.modifiedAt.timeIntervalSince1970.isFinite,
              ProfileStampDeviceIDRuleV1.isValid(player.selection.deviceID) else {
            throw ProfileValidationError.invalidSelectionStamp
        }
    }

    private static func validateKeys(_ document: LocalPlayerDocumentV1) throws {
        for (key, entry) in document.player.ledger where key != entry.id {
            throw ProfileValidationError.ledgerKeyMismatch(key)
        }
        for (key, record) in document.player.completedRuns where key != record.run.runID {
            throw ProfileValidationError.runKeyMismatch(key)
        }
        for (key, receipt) in document.settlementReceipts
            where key != receipt.record.run.runID {
            throw ProfileValidationError.receiptKeyMismatch(key)
        }
    }

    private static func validateInventory(
        _ player: PlayerDocumentV1,
        catalog: LaunchCatalog
    ) throws {
        for teamID in player.inventory.ownedTeamIDs {
            guard let team = catalog.team(id: teamID) else {
                throw ProfileValidationError.unknownOwnedTeam(teamID)
            }
            guard player.inventory.ownedJerseyIDs.contains(team.primaryJersey.id) else {
                throw ProfileValidationError.missingOwnedPrimaryJersey(teamID)
            }
        }
        for jerseyID in player.inventory.ownedJerseyIDs {
            guard let jersey = catalog.jersey(id: jerseyID) else {
                throw ProfileValidationError.unknownOwnedJersey(jerseyID)
            }
            if !player.inventory.ownedTeamIDs.contains(jersey.teamID) {
                if jersey.kind == .alternate {
                    throw ProfileValidationError.alternateOwnedWithoutTeam(jerseyID)
                }
                throw ProfileValidationError.jerseyOwnedWithoutTeam(jerseyID)
            }
        }
        for footballID in player.inventory.ownedFootballIDs
            where catalog.football(id: footballID) == nil {
            throw ProfileValidationError.unknownOwnedFootball(footballID)
        }
        for (teamID, jerseyID) in player.selection.value.selectedJerseyByTeam {
            guard let jersey = catalog.jersey(id: jerseyID), jersey.teamID == teamID else {
                throw ProfileValidationError.invalidRememberedJersey(
                    teamID: teamID,
                    jerseyID: jerseyID
                )
            }
        }
        for teamID in player.inventory.ownedTeamIDs {
            guard let rememberedJerseyID = player.selection.value.selectedJerseyByTeam[teamID],
                  let jersey = catalog.jersey(id: rememberedJerseyID),
                  jersey.teamID == teamID,
                  player.inventory.ownedJerseyIDs.contains(rememberedJerseyID) else {
                throw ProfileValidationError.invalidRememberedJersey(
                    teamID: teamID,
                    jerseyID: player.selection.value.selectedJerseyByTeam[teamID]
                        ?? JerseyID("missing-remembered-jersey.\(teamID.rawValue)")
                )
            }
        }

        do {
            try InventoryRules.validate(
                selection: player.selection.value,
                inventory: player.inventory,
                catalog: catalog
            )
        } catch let error as InventoryRuleError {
            throw ProfileValidationError.invalidSelection(error)
        }
    }

    private static func validateSettingsAndProgress(_ player: PlayerDocumentV1) throws {
        let settings = player.settings.value
        guard settings.musicVolume.isFinite,
              settings.sfxVolume.isFinite,
              (0 ... 1).contains(settings.musicVolume),
              (0 ... 1).contains(settings.sfxVolume) else {
            throw ProfileValidationError.invalidSettings
        }

        let launchIDs = Set(AchievementCatalog.launch.map(\.id))
        guard player.pendingGameCenter.pendingByPlayerID.count
                <= PlayerScopedGameCenterQueueV1.maximumPlayerBucketCount else {
            throw ProfileValidationError.tooManyPendingGameCenterPlayers(
                player.pendingGameCenter.pendingByPlayerID.count
            )
        }
        for (key, progress) in player.achievementProgress {
            guard key == progress.id,
                  launchIDs.contains(key),
                  (0 ... 100).contains(progress.percentComplete),
                  (progress.percentComplete == 100) == (progress.completedAt != nil) else {
                throw ProfileValidationError.invalidAchievementProgress(key)
            }
        }
        func validatePending(_ pending: GameCenterPendingMaximaV1) throws {
            guard pending.pendingHighScore >= 0 else {
                throw ProfileValidationError.invalidPendingGameCenterHighScore(
                    pending.pendingHighScore
                )
            }
            for (achievementID, percent) in pending.pendingAchievementPercents {
                guard launchIDs.contains(achievementID), (0 ... 100).contains(percent) else {
                    throw ProfileValidationError.invalidAchievementProgress(achievementID)
                }
            }
        }
        try validatePending(player.pendingGameCenter.unboundPending)
        for (playerID, pending) in player.pendingGameCenter.pendingByPlayerID {
            guard GameCenterPlayerIDRuleV1.isValid(playerID) else {
                throw ProfileValidationError.invalidPendingGameCenterPlayerID(playerID)
            }
            guard !pending.isEmpty else {
                throw ProfileValidationError.emptyPendingGameCenterPlayerBucket(playerID)
            }
            try validatePending(pending)
            guard pending.pendingHighScore <= player.career.highestScore else {
                throw ProfileValidationError
                    .pendingGameCenterHighScoreExceedsCareer(
                        playerID: playerID,
                        pendingHighScore: pending.pendingHighScore,
                        earnedHighScore: player.career.highestScore
                    )
            }
            for (achievementID, pendingPercent) in
                pending.pendingAchievementPercents {
                let earnedPercent = player.achievementProgress[achievementID]?
                    .percentComplete ?? 0
                guard pendingPercent <= earnedPercent else {
                    throw ProfileValidationError
                        .pendingGameCenterAchievementExceedsProgress(
                            playerID: playerID,
                            achievementID: achievementID,
                            pendingPercent: pendingPercent,
                            earnedPercent: earnedPercent
                        )
                }
            }
        }
    }

    private static func validateLedger(
        _ document: LocalPlayerDocumentV1,
        catalog: LaunchCatalog
    ) throws {
        for pendingID in document.pendingLedgerEntryIDs {
            guard let entry = document.player.ledger[pendingID] else {
                throw ProfileValidationError.pendingEntryMissing(pendingID)
            }
            guard entry.delta > 0 else {
                throw ProfileValidationError.pendingEntryMustBePositive(pendingID)
            }
        }

        let signingEntries = document.player.ledger.values.filter { entry in
            if case .signingBonus = entry.reason { return true }
            return false
        }
        guard signingEntries.count <= 1 else {
            throw ProfileValidationError.multipleSigningBonuses
        }
        if let signingEntry = signingEntries.first {
            let expectedID = CoinLedgerID.signingBonus(
                version: PersistedEconomyRulesV1.signingBonusVersion
            )
            guard signingEntry.id == expectedID,
                  signingEntry.delta == PersistedEconomyRulesV1.signingBonusCoins,
                  signingEntry.createdAt
                    == PersistedEconomyRulesV1.signingBonusLedgerCreatedAt,
                  case .signingBonus(PersistedEconomyRulesV1.signingBonusVersion) = signingEntry.reason else {
                throw ProfileValidationError.invalidSigningBonus(signingEntry.id)
            }
        }

        for entry in document.player.ledger.values {
            switch entry.reason {
            case let .gameplay(runID, _):
                guard document.player.completedRuns[runID] != nil else {
                    throw ProfileValidationError.orphanGameplayLedger(runID)
                }

            case .signingBonus:
                break

            case let .rewardedAd(_, providerTransactionID):
                guard entry.id == CoinLedgerID.rewardedAd(
                    providerTransactionID: providerTransactionID
                ),
                      entry.delta == PersistedEconomyRulesV1.rewardedAdCoins,
                      !document.pendingLedgerEntryIDs.contains(entry.id) else {
                    throw ProfileValidationError.invalidRewardedAdCredit(entry.id)
                }

            case let .storeKit(transactionID, packID):
                guard entry.id == CoinLedgerID.storeKit(transactionID: transactionID),
                      let packCoins = PersistedEconomyRulesV1.coinPackCoins[packID],
                      entry.delta == packCoins else {
                    throw ProfileValidationError.invalidStoreKitCredit(entry.id)
                }

            case let .catalogUnlock(itemID):
                guard entry.id == CoinLedgerID.catalogUnlock(itemID: itemID),
                      let item = catalog.item(id: itemID),
                      entry.delta == -PersistedEconomyRulesV1.catalogPrice(for: item),
                      itemIsOwned(item, inventory: document.player.inventory) else {
                    throw ProfileValidationError.invalidCatalogUnlock(itemID)
                }
            }
        }

        for item in catalog.unlockableItems
            where itemIsOwned(item, inventory: document.player.inventory) {
            let ledgerID = CoinLedgerID.catalogUnlock(itemID: item.id)
            guard let entry = document.player.ledger[ledgerID],
                  entry.delta == -PersistedEconomyRulesV1.catalogPrice(for: item),
                  case .catalogUnlock(item.id) = entry.reason else {
                throw ProfileValidationError.invalidCatalogUnlock(item.id)
            }
        }

        _ = try PlayerProfileProjection.coinBalances(for: document)
    }

    private static func validateRuns(
        _ document: LocalPlayerDocumentV1,
        catalog: LaunchCatalog
    ) throws {
        for runID in document.settlementReceipts.keys
            where document.player.completedRuns[runID] == nil {
            throw ProfileValidationError.orphanSettlementReceipt(runID)
        }
        for (runID, record) in document.player.completedRuns {
            guard let receipt = document.settlementReceipts[runID] else {
                throw ProfileValidationError.missingRunRecord(runID)
            }
            guard receipt.record == record else {
                throw ProfileValidationError.receiptDoesNotMatchRun(runID)
            }

            do {
                try CompletedRunValidator.validate(
                    record.run,
                    recordedAt: record.recordedAt,
                    inventory: document.player.inventory,
                    catalog: catalog
                )
            } catch let error as CompletedRunValidationError {
                throw ProfileValidationError.invalidCompletedRun(runID, error)
            }

            let expectedReward: Int64
            do {
                expectedReward = try CompletedRunValidator.rewardCoins(for: record.run)
            } catch let error as CompletedRunValidationError {
                throw ProfileValidationError.invalidCompletedRun(runID, error)
            }
            guard record.rewardCoins == expectedReward else {
                throw ProfileValidationError.rewardCalculationMismatch(runID)
            }

            let expectedRewardID = CoinLedgerID.gameplay(runID: runID)
            if record.rewardCoins > 0 {
                guard receipt.gameplayRewardEntryID == expectedRewardID,
                      let entry = document.player.ledger[expectedRewardID],
                      entry.delta == record.rewardCoins,
                      case let .gameplay(entryRunID, economyVersion) = entry.reason,
                      entryRunID == runID,
                      economyVersion == record.run.configuration.economyVersion else {
                    throw ProfileValidationError.rewardLedgerMismatch(runID)
                }
            } else if receipt.gameplayRewardEntryID != nil
                        || document.player.ledger[expectedRewardID] != nil {
                throw ProfileValidationError.rewardLedgerMismatch(runID)
            }
        }

        let signingReceiptCount = document.settlementReceipts.values.filter {
            $0.signingBonusEntryID != nil
        }.count
        let signingLedgerCount = document.player.ledger.values.filter {
            if case .signingBonus = $0.reason { return true }
            return false
        }.count
        guard signingReceiptCount == signingLedgerCount else {
            throw ProfileValidationError.multipleSigningBonuses
        }
        if signingReceiptCount == 1 {
            let expectedID = CoinLedgerID.signingBonus(
                version: PersistedEconomyRulesV1.signingBonusVersion
            )
            guard let receipt = document.settlementReceipts.values.first(where: {
                $0.signingBonusEntryID != nil
            }),
            receipt.signingBonusEntryID == expectedID,
            CompletedRunValidator.isRewardEligible(receipt.record.run) else {
                throw ProfileValidationError.invalidSigningBonus(expectedID)
            }
        }
    }

    private static func validateRewardedAdState(_ player: PlayerDocumentV1) throws {
        let state = player.rewardedAdState
        guard (0 ... PersistedEconomyRulesV1.rewardedAdRunThreshold)
            .contains(state.validRunsSinceReward) else {
            throw ProfileValidationError.invalidRewardedAdState
        }
        if state.validRunsSinceReward == PersistedEconomyRulesV1.rewardedAdRunThreshold {
            guard state.eligibleOfferID == RewardedAdState.offerID(for: state.cycle) else {
                throw ProfileValidationError.invalidRewardedAdState
            }
        } else if state.eligibleOfferID != nil {
            throw ProfileValidationError.invalidRewardedAdState
        }

        let rewardEligibleRunIDs = Set(
            player.completedRuns.values.compactMap { record in
                CompletedRunValidator.isRewardEligible(record.run)
                    ? record.run.runID
                    : nil
            }
        )
        guard state.accountedRunIDs == rewardEligibleRunIDs else {
            throw ProfileValidationError.invalidRewardedAdState
        }

        let offerPrefix = "reward-cycle/"
        var settledOfferIDs = Set<RewardOfferID>()
        for entry in player.ledger.values {
            guard case let .rewardedAd(offerID, _) = entry.reason else { continue }
            guard offerID.rawValue.hasPrefix(offerPrefix),
                  let offerCycle = UInt64(offerID.rawValue.dropFirst(offerPrefix.count)),
                  RewardedAdState.offerID(for: offerCycle) == offerID,
                  offerCycle < state.cycle,
                  settledOfferIDs.insert(offerID).inserted else {
                throw ProfileValidationError.invalidRewardedAdState
            }
        }
        guard UInt64(settledOfferIDs.count) == state.cycle else {
            throw ProfileValidationError.invalidRewardedAdState
        }
    }

    private static func validateRewardedRunObservations(
        _ document: LocalPlayerDocumentV1
    ) throws {
        guard let observations = document.rewardedRunObservations else {
            throw ProfileValidationError.missingRewardedRunObservations
        }

        let eligibleRunIDs = Set(document.player.completedRuns.values.compactMap {
            CompletedRunValidator.isRewardEligible($0.run) ? $0.run.runID : nil
        })
        guard Set(observations.keys) == eligibleRunIDs else {
            throw ProfileValidationError.missingRewardedRunObservations
        }

        for (runID, observation) in observations {
            guard let record = document.player.completedRuns[runID],
                  CompletedRunValidator.isRewardEligible(record.run),
                  (observation.disposition == .legacyNonCounting
                      ? observation.observedCycle == 0
                      : observation.observedCycle
                          <= document.player.rewardedAdState.cycle)
            else {
                throw ProfileValidationError.invalidRewardedRunObservation(runID)
            }
        }
    }

    private static func validateCareer(_ player: PlayerDocumentV1) throws {
        let recomputed = try PersistedCareerAccumulatorV1.recompute(
            from: player.completedRuns.values
        )
        guard recomputed == player.career else {
            throw ProfileValidationError.careerAggregateMismatch
        }
    }

    private static func itemIsOwned(
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

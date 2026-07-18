import Foundation
import XCTest
@testable import PocketVector

final class CloudInitialProfileSeedTests: XCTestCase {
    private let baseDate = Date(timeIntervalSince1970: 1_760_000_000)
    private let profileID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private let accountIdentity = PlayerAccountIdentity.local

    func testEmptyEconomyProducesAccountNeutralPublishableSeed() throws {
        let artifact = try makeArtifact(makeDefaultDocument())
        XCTAssertEqual(
            artifact.envelope.schemaVersion,
            PlayerProfileEnvelopeV4.schemaVersion
        )

        let seed = try CloudInitialProfileSeedBuilderV1().makeSeed(from: artifact)

        XCTAssertEqual(seed.schemaVersion, 1)
        XCTAssertEqual(seed.sourceSavedAt, artifact.savedAt)
        XCTAssertEqual(seed.sourceProfileEnvelopeDigest, artifact.digest)
        XCTAssertEqual(seed.playerRevision, artifact.document.player.revision)
        XCTAssertEqual(seed.economyRevision, artifact.document.economyRevision)
        XCTAssertEqual(seed.settings, artifact.document.player.settings)
        XCTAssertEqual(seed.selection, artifact.document.player.selection)
        XCTAssertEqual(seed.debugRunFacts, [])
        XCTAssertEqual(seed.debugLedgerFacts, [])
        XCTAssertEqual(seed.debugEligibility, .emptyEconomyPublishable)

        let encoded = try seed.canonicalEncodedData()
        let text = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        XCTAssertFalse(text.contains(accountIdentity.rawValue))
        XCTAssertFalse(text.contains(profileID.uuidString.lowercased()))
        XCTAssertFalse(text.contains(profileID.uuidString.uppercased()))
        XCTAssertFalse(text.contains("cloudAccountID"))
        XCTAssertFalse(text.contains("playerAccountIdentity"))
        XCTAssertFalse(text.contains("profileID"))
        XCTAssertFalse(text.contains("sessionNonce"))
        XCTAssertFalse(text.contains("transport"))
        XCTAssertFalse(text.contains("writes"))
    }

    func testExactV4ScopedQueueIsValidatedWithoutClaimingOrEncodingIdentity() throws {
        let playerID = GameCenterPlayerID("seed-player-a")
        let achievementID = try XCTUnwrap(AchievementCatalog.launch.first?.id)
        var document = makeDefaultDocument()
        document.player.achievementProgress[achievementID] = AchievementProgress(
            id: achievementID,
            percentComplete: 25
        )
        let originalQueue = PlayerScopedGameCenterQueueV1(
            pendingByPlayerID: [
                playerID: GameCenterPendingMaximaV1(
                    pendingAchievementPercents: [achievementID: 25]
                ),
            ],
            unboundPending: GameCenterPendingMaximaV1(
                pendingHighScore: 999,
                pendingAchievementPercents: [achievementID: 10]
            )
        )
        document.player.pendingGameCenter = originalQueue
        let artifact = try makeArtifact(document)

        let seed = try CloudInitialProfileSeedBuilderV1().makeSeed(from: artifact)

        XCTAssertEqual(artifact.envelope.schemaVersion, 4)
        XCTAssertEqual(artifact.document.player.pendingGameCenter, originalQueue)
        XCTAssertEqual(seed.debugEligibility, .emptyEconomyPublishable)
        let text = try XCTUnwrap(
            String(data: seed.canonicalEncodedData(), encoding: .utf8)
        )
        XCTAssertFalse(text.contains(playerID.rawValue))
        XCTAssertFalse(text.contains(achievementID.rawValue))
        XCTAssertFalse(text.contains("pendingGameCenter"))
        XCTAssertFalse(text.contains("pendingByPlayerID"))
        XCTAssertFalse(text.contains("unboundPending"))
        XCTAssertFalse(text.contains("gamePlayerID"))
    }

    func testPendingGameplayAndSigningCreditsRequireProjectionAndPreserveFacts() throws {
        let runIDs = [
            RunID(UUID(uuidString: "00000000-0000-0000-0000-000000000002")!),
            RunID(UUID(uuidString: "00000000-0000-0000-0000-000000000001")!),
        ]
        let document = try makePendingGameplayDocument(runIDs: runIDs)
        let artifact = try makeArtifact(document)
        let seed = try CloudInitialProfileSeedBuilderV1().makeSeed(
            from: artifact
        )

        XCTAssertEqual(seed.debugRunFacts.map(\.runID), runIDs.reversed())
        XCTAssertEqual(
            seed.debugRunFacts.map(\.rewardedRunObservation),
            [
                RewardedRunObservation(observedCycle: 0, disposition: .candidate),
                RewardedRunObservation(observedCycle: 0, disposition: .candidate),
            ]
        )
        XCTAssertEqual(
            seed.debugLedgerFacts.map(\.entryID),
            seed.debugLedgerFacts.map(\.entryID).sorted {
                $0.rawValue.utf8.lexicographicallyPrecedes($1.rawValue.utf8)
            }
        )
        XCTAssertTrue(seed.debugLedgerFacts.allSatisfy(\.isPending))
        XCTAssertEqual(seed.playerRevision, 2)
        XCTAssertEqual(seed.economyRevision, 3)
        XCTAssertEqual(
            seed.debugEligibility,
            .pendingCreditProjectionRequired(entryIDs: seed.debugLedgerFacts.map(\.entryID))
        )
    }

    func testConfirmedGameplayCreditsRequireOwnerPolicy() throws {
        var document = try makePendingGameplayDocument(runIDs: [RunID()])
        document.pendingLedgerEntryIDs = []
        let artifact = try makeArtifact(document)
        let seed = try CloudInitialProfileSeedBuilderV1().makeSeed(
            from: artifact
        )

        guard case let .requiresOwnerPolicy(reasons) = seed.debugEligibility else {
            return XCTFail("Expected owner policy")
        }
        XCTAssertEqual(
            Set(reasons.compactMap { reason -> LedgerEntryID? in
                if case let .confirmedLedgerEntry(id) = reason { return id }
                return nil
            }),
            Set(document.player.ledger.keys)
        )
    }

    func testTwoDirectoryAssociationNormalizesOlderBackupAndReloadsTarget()
        async throws
    {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "association-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceDirectory = root.appendingPathComponent("local", isDirectory: true)
        let targetDirectory = root.appendingPathComponent("cloud", isDirectory: true)
        let cloudAccountID = CloudAccountID("cloud-account-a")
        let derived = CloudAccountDerivedBindings.derive(from: cloudAccountID)

        let sourceRepository = LocalPlayerProfileRepository(
            directoryURL: sourceDirectory,
            deviceID: "device-a",
            accountIdentity: .local,
            economyMutationPolicy: .allowLocalTesting
        )
        let loaded = try await sourceRepository.load(at: baseDate)
        var settings = loaded.player.settings
        settings.isMuted.toggle()
        let advanced = try await sourceRepository.updateSettings(
            settings,
            session: loaded.session,
            at: baseDate.addingTimeInterval(1)
        )
        let exactSource = try await sourceRepository.hydrationSource(
            session: advanced.session
        )
        let sourceDecoded = try PlayerProfileMigrator().decodeArtifact(
            exactSource.exactEnvelopeBytes
        )
        let sourceArtifact = try PlayerProfileMigrator().canonicalArtifact(
            for: sourceDecoded.document,
            savedAt: sourceDecoded.savedAt
        )
        let sourceLocations = ProfileStorageLocations(
            directoryURL: sourceDirectory
        )
        XCTAssertNotEqual(
            try Data(contentsOf: sourceLocations.backupURL),
            sourceArtifact.exactBytes,
            "A normal evolved profile starts with an older backup predecessor"
        )

        let capability = try await sourceRepository.beginInitialAssociation(
            targetCloudAccountID: cloudAccountID,
            targetDirectoryURL: targetDirectory,
            transactionID: UUID(
                uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
            )!
        )
        var candidate = sourceArtifact.document
        candidate.accountIdentity = derived.playerAccountIdentity
        candidate.player.profileID = derived.durableAccountBinding.profileID
        candidate.player.revision += 1
        candidate.economyRevision += 1
        let candidateArtifact = try PlayerProfileMigrator().canonicalArtifact(
            for: candidate,
            savedAt: baseDate.addingTimeInterval(2)
        )
        let checkpoint = try makeEmptyCheckpoint(
            accountID: cloudAccountID
        )
        let journal = try ProfileInitialAssociationJournalV1.make(
            createdAt: baseDate.addingTimeInterval(2),
            capability: capability,
            candidateEnvelope: candidateArtifact.exactBytes,
            targetCheckpoint: checkpoint
        )
        let targetRepository = LocalPlayerProfileRepository(
            directoryURL: targetDirectory,
            deviceID: "device-a",
            accountIdentity: derived.playerAccountIdentity,
            economyMutationPolicy: .allowLocalTesting
        )
        let store = ProfileInitialAssociationStoreV1()

        let result = try await store.associate(
            journal: journal,
            capability: capability,
            sourceRepository: sourceRepository,
            targetRepository: targetRepository,
            now: baseDate.addingTimeInterval(3)
        )

        XCTAssertEqual(result.installedArtifact, candidateArtifact)
        XCTAssertEqual(result.targetSnapshot.session.accountIdentity,
                       derived.playerAccountIdentity)
        XCTAssertEqual(result.targetSnapshot.session.profileID,
                       derived.durableAccountBinding.profileID)
        XCTAssertEqual(
            try Data(contentsOf: sourceLocations.primaryURL),
            sourceArtifact.exactBytes
        )
        XCTAssertEqual(
            try Data(contentsOf: sourceLocations.backupURL),
            sourceArtifact.exactBytes
        )
        let remainingJournal = try await store.recoverableJournal(
            sourceDirectoryURL: sourceDirectory,
            targetDirectoryURL: targetDirectory
        )
        XCTAssertNil(remainingJournal)
        let committedLookup = try await store.committedAssociation(
            sourceDirectoryURL: sourceDirectory
        )
        let committed = try XCTUnwrap(committedLookup)
        XCTAssertEqual(committed.cloudAccountID, cloudAccountID)
        XCTAssertEqual(committed.sourceEnvelopeDigest, sourceArtifact.digest)
        XCTAssertEqual(committed.targetEnvelopeDigest, candidateArtifact.digest)

        var evolvedSettings = result.targetSnapshot.player.settings
        evolvedSettings.reducedMotion.toggle()
        let evolved = try await targetRepository.updateSettings(
            evolvedSettings,
            session: result.targetSnapshot.session,
            at: baseDate.addingTimeInterval(4)
        )
        let evolvedSource = try await targetRepository.hydrationSource(
            session: evolved.session
        )
        let evolvedEnvelope = evolvedSource.exactEnvelopeBytes
        let relaunchedSource = LocalPlayerProfileRepository(
            directoryURL: sourceDirectory,
            deviceID: "device-a",
            accountIdentity: .local,
            economyMutationPolicy: .allowLocalTesting
        )
        _ = try await relaunchedSource.load(at: baseDate.addingTimeInterval(5))
        let relaunchedTarget = LocalPlayerProfileRepository(
            directoryURL: targetDirectory,
            deviceID: "device-a",
            accountIdentity: derived.playerAccountIdentity,
            economyMutationPolicy: .allowLocalTesting
        )
        let targetLocations = ProfileStorageLocations(
            directoryURL: targetDirectory
        )
        try Data("damaged-target-primary".utf8).write(
            to: targetLocations.primaryURL
        )
        try Data("damaged-source-primary".utf8).write(
            to: sourceLocations.primaryURL
        )
        _ = try await store.committedAssociation(
            sourceDirectoryURL: sourceDirectory
        )
        XCTAssertEqual(
            try Data(contentsOf: sourceLocations.primaryURL),
            sourceArtifact.exactBytes
        )
        let journalEncoder = JSONEncoder()
        journalEncoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let recoveredEvidence = try journalEncoder.encode(journal)
        for directory in [sourceDirectory, targetDirectory] {
            let evidenceDirectory = directory.appendingPathComponent(
                "ProfileInitialAssociationTransaction",
                isDirectory: true
            )
            try FileManager.default.createDirectory(
                at: evidenceDirectory,
                withIntermediateDirectories: true
            )
            try recoveredEvidence.write(
                to: evidenceDirectory.appendingPathComponent(
                    "association-journal.json"
                )
            )
            try recoveredEvidence.write(
                to: evidenceDirectory.appendingPathComponent(
                    "association-journal.backup.json"
                )
            )
        }
        let reopened = try await store.reopenCommittedAssociation(
            committed,
            expectedAccountID: cloudAccountID,
            sourceRepository: relaunchedSource,
            targetRepository: relaunchedTarget,
            at: baseDate.addingTimeInterval(5)
        )
        XCTAssertEqual(reopened.targetSnapshot.player.settings,
                       evolved.player.settings)
        XCTAssertNotEqual(reopened.installedArtifact.digest,
                          committed.targetEnvelopeDigest)
        XCTAssertEqual(
            try Data(contentsOf: targetLocations.primaryURL),
            try Data(contentsOf: targetLocations.backupURL)
        )

        for url in [targetLocations.primaryURL, targetLocations.backupURL] {
            try candidateArtifact.exactBytes.write(to: url)
        }
        _ = try await store.committedAssociation(
            sourceDirectoryURL: sourceDirectory
        )
        let rollbackRecovery = try AtomicProfileFileStore(
            directoryURL: targetDirectory
        ).loadOrCreate(
            defaultDocument: candidateArtifact.document,
            at: baseDate.addingTimeInterval(5),
            catalog: .approved
        )
        XCTAssertEqual(rollbackRecovery.artifact.exactBytes, evolvedEnvelope)
        XCTAssertEqual(
            try Data(contentsOf: targetLocations.primaryURL),
            evolvedEnvelope
        )
        XCTAssertEqual(
            try Data(contentsOf: targetLocations.backupURL),
            evolvedEnvelope
        )

        var rolledBack = candidateArtifact.document
        rolledBack.player.revision = committed.seedPlayerRevision - 1
        let rolledBackArtifact = try PlayerProfileMigrator().canonicalArtifact(
            for: rolledBack,
            savedAt: baseDate.addingTimeInterval(5)
        )
        for url in [targetLocations.primaryURL, targetLocations.backupURL] {
            try rolledBackArtifact.exactBytes.write(to: url)
        }
        do {
            _ = try await store.committedAssociation(
                sourceDirectoryURL: sourceDirectory
            )
            XCTFail("A validator-clean target rollback must fail lineage")
        } catch {
            XCTAssertEqual(
                error as? ProfileInitialAssociationStoreError,
                .targetVerificationFailed
            )
        }

        var replacement = candidateArtifact.document
        replacement.player.createdAt = baseDate.addingTimeInterval(-123)
        replacement.player.revision = committed.seedPlayerRevision
        replacement.economyRevision = committed.seedEconomyRevision
        let replacementArtifact = try PlayerProfileMigrator().canonicalArtifact(
            for: replacement,
            savedAt: baseDate.addingTimeInterval(5)
        )
        for url in [targetLocations.primaryURL, targetLocations.backupURL] {
            try replacementArtifact.exactBytes.write(to: url)
        }
        do {
            _ = try await store.committedAssociation(
                sourceDirectoryURL: sourceDirectory
            )
            XCTFail("A fresh same-ID target must fail seed lineage")
        } catch {
            XCTAssertEqual(
                error as? ProfileInitialAssociationStoreError,
                .targetVerificationFailed
            )
        }
        for url in [targetLocations.primaryURL, targetLocations.backupURL] {
            try evolvedEnvelope.write(to: url)
        }
        let evidenceAfterRecovery = try await store.recoverableJournal(
            sourceDirectoryURL: sourceDirectory,
            targetDirectoryURL: targetDirectory
        )
        XCTAssertNil(evidenceAfterRecovery)

        try Data("damaged-target-backup".utf8).write(
            to: targetLocations.backupURL
        )
        let secondRelaunchedSource = LocalPlayerProfileRepository(
            directoryURL: sourceDirectory,
            deviceID: "device-a",
            accountIdentity: .local,
            economyMutationPolicy: .allowLocalTesting
        )
        _ = try await secondRelaunchedSource.load(
            at: baseDate.addingTimeInterval(5)
        )
        let secondRelaunchedTarget = LocalPlayerProfileRepository(
            directoryURL: targetDirectory,
            deviceID: "device-a",
            accountIdentity: derived.playerAccountIdentity,
            economyMutationPolicy: .allowLocalTesting
        )
        _ = try await store.reopenCommittedAssociation(
            committed,
            expectedAccountID: cloudAccountID,
            sourceRepository: secondRelaunchedSource,
            targetRepository: secondRelaunchedTarget,
            at: baseDate.addingTimeInterval(5)
        )
        XCTAssertEqual(
            try Data(contentsOf: targetLocations.primaryURL),
            try Data(contentsOf: targetLocations.backupURL)
        )
        do {
            _ = try await store.reopenCommittedAssociation(
                committed,
                expectedAccountID: CloudAccountID("cloud-account-b"),
                sourceRepository: relaunchedSource,
                targetRepository: relaunchedTarget
            )
            XCTFail("A committed local source cannot bind to another account")
        } catch {
            XCTAssertEqual(
                error as? ProfileInitialAssociationStoreError,
                .accountChanged
            )
        }

        let lineageURL = targetDirectory
            .appendingPathComponent("ProfileLineage", isDirectory: true)
            .appendingPathComponent("latest-envelope.json")
        let lineageBytes = try Data(contentsOf: lineageURL)
        try Data("corrupt-lineage".utf8).write(to: lineageURL)
        do {
            _ = try await store.committedAssociation(
                sourceDirectoryURL: sourceDirectory
            )
            XCTFail("A corrupt latest-lineage authority must fail closed")
        } catch {
            XCTAssertEqual(
                error as? ProfileInitialAssociationStoreError,
                .targetVerificationFailed
            )
        }
        try lineageBytes.write(to: lineageURL)

        var changedArchive = sourceArtifact.document
        changedArchive.player.settings.value.isMuted.toggle()
        changedArchive.player.settings.logicalCounter += 1
        changedArchive.player.revision += 1
        let changedArchiveArtifact = try PlayerProfileMigrator()
            .canonicalArtifact(
                for: changedArchive,
                savedAt: baseDate.addingTimeInterval(6)
            )
        try changedArchiveArtifact.exactBytes.write(
            to: sourceLocations.primaryURL
        )
        try changedArchiveArtifact.exactBytes.write(
            to: sourceLocations.backupURL
        )
        do {
            _ = try await store.committedAssociation(
                sourceDirectoryURL: sourceDirectory
            )
            XCTFail("A changed source archive must fail closed")
        } catch {
            XCTAssertEqual(
                error as? ProfileInitialAssociationStoreError,
                .sourceCASMismatch
            )
        }
        try sourceArtifact.exactBytes.write(to: sourceLocations.primaryURL)
        try sourceArtifact.exactBytes.write(to: sourceLocations.backupURL)

        let markerURL = sourceDirectory
            .appendingPathComponent(
                "ProfileCommittedAssociation",
                isDirectory: true
            )
            .appendingPathComponent("association.json")
        try Data("corrupt".utf8).write(to: markerURL)
        do {
            _ = try await store.committedAssociation(
                sourceDirectoryURL: sourceDirectory
            )
            XCTFail("A corrupt committed marker must fail closed")
        } catch {
            XCTAssertEqual(
                error as? ProfileInitialAssociationStoreError,
                .invalidJournal
            )
        }
        do {
            _ = try await sourceRepository.snapshot()
            XCTFail("The local repository must be invalidated after adoption")
        } catch {
            XCTAssertEqual(error as? LocalPlayerRepositoryError, .notLoaded)
        }
    }

    func testPublisherRejectsDifferentCurrentAccountWithoutWriting() async throws {
        let expected = CloudAccountID("cloud-account-a")
        let actual = CloudAccountID("cloud-account-b")
        let transport = InMemoryCloudSyncTransport(accountState: .available(actual))
        let planner = try makePublicationPlanner()
        let artifact = try makeArtifact(makeDefaultDocument())
        let session = ProfileSessionToken(
            accountIdentity: .local,
            nonce: UUID(),
            profileID: artifact.document.player.profileID
        )
        let plan = try planner.makePlan(
            sourceArtifact: artifact,
            sourceSession: session,
            cloudAccountID: expected
        )

        do {
            _ = try await CloudInitialProfilePublisherV1(cloud: transport)
                .publish(plan)
            XCTFail("A different current account must fail before any write")
        } catch {
            XCTAssertEqual(
                error as? CloudInitialProfilePublicationError,
                .accountChanged
            )
        }
        let expectedRecords = await transport.allRecords(for: expected)
        let actualRecords = await transport.allRecords(for: actual)
        XCTAssertEqual(expectedRecords, [])
        XCTAssertEqual(actualRecords, [])
    }

    func testStoreKitAndRewardedAdHistoryRequireOwnerPolicy() throws {
        var document = makeDefaultDocument()
        let storeKitID = CoinLedgerID.storeKit(transactionID: 42)
        let rewardedID = CoinLedgerID.rewardedAd(
            providerTransactionID: AdProviderTransactionID("reward-tx-0")
        )
        document.player.ledger[storeKitID] = CoinLedgerEntry(
            id: storeKitID,
            delta: try XCTUnwrap(PersistedEconomyRulesV1.coinPackCoins[CoinPackID("pocket")]),
            reason: .storeKit(transactionID: 42, packID: CoinPackID("pocket")),
            createdAt: baseDate
        )
        document.player.ledger[rewardedID] = CoinLedgerEntry(
            id: rewardedID,
            delta: PersistedEconomyRulesV1.rewardedAdCoins,
            reason: .rewardedAd(
                offerID: RewardedAdState.offerID(for: 0),
                providerTransactionID: AdProviderTransactionID("reward-tx-0")
            ),
            createdAt: baseDate.addingTimeInterval(1)
        )
        document.player.rewardedAdState = RewardedAdState(cycle: 1)

        let artifact = try makeArtifact(document)
        let seed = try CloudInitialProfileSeedBuilderV1().makeSeed(
            from: artifact
        )
        guard case let .requiresOwnerPolicy(reasons) = seed.debugEligibility else {
            return XCTFail("Expected owner policy")
        }
        XCTAssertTrue(reasons.contains(.storeKitHistory(storeKitID)))
        XCTAssertTrue(reasons.contains(.rewardedAdHistory(rewardedID)))
        XCTAssertTrue(reasons.contains(.confirmedLedgerEntry(storeKitID)))
        XCTAssertTrue(reasons.contains(.confirmedLedgerEntry(rewardedID)))
        XCTAssertThrowsError(try makePublicationPlanner().makePlan(
            sourceArtifact: artifact,
            sourceSession: ProfileSessionToken(
                accountIdentity: .local,
                nonce: UUID(),
                profileID: artifact.document.player.profileID
            ),
            cloudAccountID: CloudAccountID("cloud-account-a")
        )) { error in
            XCTAssertEqual(
                error as? CloudInitialProfilePublicationError,
                .ownerPolicyRequired
            )
        }
    }

    func testUnlockedInventoryDebitAndPaidHistoryRequireOwnerPolicy() throws {
        var document = makeDefaultDocument()
        let item = try XCTUnwrap(LaunchCatalog.approved.unlockableItems.first {
            if case .team = $0.kind { return true }
            return false
        })
        let packID = CoinPackID("team")
        let storeKitID = CoinLedgerID.storeKit(transactionID: 7)
        document.player.ledger[storeKitID] = CoinLedgerEntry(
            id: storeKitID,
            delta: try XCTUnwrap(PersistedEconomyRulesV1.coinPackCoins[packID]),
            reason: .storeKit(transactionID: 7, packID: packID),
            createdAt: baseDate
        )
        _ = try InventoryRules.applyUnlock(
            itemID: item.id,
            to: &document.player.inventory
        )
        let unlockID = CoinLedgerID.catalogUnlock(itemID: item.id)
        document.player.ledger[unlockID] = CoinLedgerEntry(
            id: unlockID,
            delta: -PersistedEconomyRulesV1.catalogPrice(for: item),
            reason: .catalogUnlock(itemID: item.id),
            createdAt: baseDate.addingTimeInterval(1)
        )

        let seed = try CloudInitialProfileSeedBuilderV1().makeSeed(
            from: makeArtifact(document)
        )
        guard case let .requiresOwnerPolicy(reasons) = seed.debugEligibility else {
            return XCTFail("Expected owner policy")
        }
        XCTAssertTrue(reasons.contains(.catalogUnlockHistory(unlockID)))
        XCTAssertTrue(reasons.contains(.debitHistory(unlockID)))
        switch item.kind {
        case let .team(teamID):
            XCTAssertTrue(reasons.contains(.additionalTeamOwnership(teamID)))
            XCTAssertTrue(reasons.contains(.additionalJerseyOwnership(
                try XCTUnwrap(LaunchCatalog.approved.team(id: teamID)?.primaryJersey.id)
            )))
        case .alternateJersey, .football:
            XCTFail("Test fixture must use a team unlock")
        }
    }

    func testMissingInitialOwnershipFailsClosedPrecisely() throws {
        var document = makeDefaultDocument()
        let team = try XCTUnwrap(LaunchCatalog.approved.team(id: LaunchTeamID.highMesaHelions))
        document.player.inventory.ownedTeamIDs.remove(team.id)
        document.player.inventory.ownedJerseyIDs.remove(team.primaryJersey.id)

        XCTAssertThrowsError(
            try CloudInitialProfileSeedBuilderV1().makeSeed(from: makeArtifact(document))
        ) { error in
            XCTAssertEqual(error as? CloudInitialProfileSeedError, .initialInventoryMissing)
        }
    }

    func testNonLocalSourceIdentityFailsClosedWithoutEnteringSeed() throws {
        let actual = PlayerAccountIdentity("already-account-derived")
        let document = PlayerProfileFactory.makeDefault(
            profileID: profileID,
            accountIdentity: actual,
            deviceID: "device-a",
            createdAt: baseDate
        )

        XCTAssertThrowsError(
            try CloudInitialProfileSeedBuilderV1().makeSeed(from: makeArtifact(document))
        ) { error in
            XCTAssertEqual(
                error as? CloudInitialProfileSeedError,
                .sourceAccountClaimAlreadyRequired
            )
        }
    }

    func testMalformedPendingSetGetsPreciseErrorsBeforeGeneralValidation() throws {
        var missing = makeDefaultDocument()
        let missingID = LedgerEntryID("missing-credit")
        missing.pendingLedgerEntryIDs.insert(missingID)
        XCTAssertThrowsError(
            try CloudInitialProfileSeedBuilderV1().makeSeed(from: makeArtifact(missing))
        ) { error in
            XCTAssertEqual(
                error as? CloudInitialProfileSeedError,
                .pendingEntryMissing(missingID)
            )
        }

        var nonpositive = makeDefaultDocument()
        let nonpositiveID = LedgerEntryID("nonpositive-credit")
        nonpositive.player.ledger[nonpositiveID] = CoinLedgerEntry(
            id: nonpositiveID,
            delta: -1,
            reason: .catalogUnlock(itemID: CatalogItemID("not-needed-for-precheck")),
            createdAt: baseDate
        )
        nonpositive.pendingLedgerEntryIDs.insert(nonpositiveID)
        XCTAssertThrowsError(
            try CloudInitialProfileSeedBuilderV1().makeSeed(from: makeArtifact(nonpositive))
        ) { error in
            XCTAssertEqual(
                error as? CloudInitialProfileSeedError,
                .pendingEntryNotPositive(nonpositiveID)
            )
        }
    }

    func testMismatchedDictionaryKeysGetPreciseErrors() throws {
        var ledgerMismatch = makeDefaultDocument()
        let entryID = LedgerEntryID("entry-id")
        let wrongKey = LedgerEntryID("wrong-key")
        ledgerMismatch.player.ledger[wrongKey] = CoinLedgerEntry(
            id: entryID,
            delta: 1,
            reason: .storeKit(transactionID: 1, packID: CoinPackID("pocket")),
            createdAt: baseDate
        )
        XCTAssertThrowsError(
            try CloudInitialProfileSeedBuilderV1().makeSeed(
                from: makeArtifact(ledgerMismatch)
            )
        ) { error in
            XCTAssertEqual(
                error as? CloudInitialProfileSeedError,
                .ledgerKeyMismatch(wrongKey)
            )
        }

        var runMismatch = makeDefaultDocument()
        let record = try makeRunRecord(runID: RunID())
        let wrongRunID = RunID()
        runMismatch.player.completedRuns[wrongRunID] = record
        XCTAssertThrowsError(
            try CloudInitialProfileSeedBuilderV1().makeSeed(from: makeArtifact(runMismatch))
        ) { error in
            XCTAssertEqual(
                error as? CloudInitialProfileSeedError,
                .runKeyMismatch(wrongRunID)
            )
        }
    }

    func testObservationAndOtherProfileInvariantFailuresAreRejected() throws {
        var document = try makePendingGameplayDocument(runIDs: [RunID()])
        document.rewardedRunObservations = [:]

        XCTAssertThrowsError(
            try CloudInitialProfileSeedBuilderV1().makeSeed(from: makeArtifact(document))
        ) { error in
            XCTAssertEqual(error as? CloudInitialProfileSeedError, .invalidSourceProfile)
        }
    }

    func testRejectsArtifactDigestAndEnvelopeFieldTampering() throws {
        let artifact = try makeArtifact(makeDefaultDocument())
        let wrongDigest = CanonicalProfileEnvelopeArtifactV1(
            envelope: artifact.envelope,
            exactBytes: artifact.exactBytes,
            digest: .envelopeBytes(Data("different".utf8))
        )
        XCTAssertThrowsError(
            try CloudInitialProfileSeedBuilderV1().makeSeed(from: wrongDigest)
        ) { error in
            XCTAssertEqual(
                error as? CloudInitialProfileSeedError,
                .sourceArtifactDigestMismatch
            )
        }

        var otherDocument = makeDefaultDocument()
        otherDocument.player.settings.value.isMuted = true
        let wrongEnvelope = PlayerProfileEnvelopeV4(
            document: otherDocument,
            savedAt: artifact.savedAt
        )
        let mismatchedEnvelope = CanonicalProfileEnvelopeArtifactV1(
            envelope: wrongEnvelope,
            exactBytes: artifact.exactBytes,
            digest: artifact.digest
        )
        XCTAssertThrowsError(
            try CloudInitialProfileSeedBuilderV1().makeSeed(from: mismatchedEnvelope)
        ) { error in
            XCTAssertEqual(
                error as? CloudInitialProfileSeedError,
                .sourceArtifactEnvelopeMismatch
            )
        }
    }

    func testRejectsNoncanonicalLegacyAndMalformedExactBytes() throws {
        let artifact = try makeArtifact(makeDefaultDocument())
        let object = try JSONSerialization.jsonObject(with: artifact.exactBytes)
        let noncanonicalBytes = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys]
        )
        let noncanonical = CanonicalProfileEnvelopeArtifactV1(
            envelope: artifact.envelope,
            exactBytes: noncanonicalBytes,
            digest: .envelopeBytes(noncanonicalBytes)
        )
        XCTAssertThrowsError(
            try CloudInitialProfileSeedBuilderV1().makeSeed(from: noncanonical)
        ) { error in
            XCTAssertEqual(
                error as? CloudInitialProfileSeedError,
                .noncanonicalSourceEnvelope
            )
        }

        var legacyObject = try XCTUnwrap(object as? [String: Any])
        var legacyDocument = try XCTUnwrap(
            legacyObject["document"] as? [String: Any]
        )
        var legacyPlayer = try XCTUnwrap(
            legacyDocument["player"] as? [String: Any]
        )
        let scopedQueue = try XCTUnwrap(
            legacyPlayer["pendingGameCenter"] as? [String: Any]
        )
        legacyPlayer["pendingGameCenter"] = try XCTUnwrap(
            scopedQueue["unboundPending"]
        )
        legacyDocument["player"] = legacyPlayer
        legacyObject["document"] = legacyDocument
        legacyObject["schemaVersion"] = PlayerProfileEnvelopeV3.schemaVersion
        let legacyBytes = try JSONSerialization.data(
            withJSONObject: legacyObject,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        let legacy = CanonicalProfileEnvelopeArtifactV1(
            envelope: artifact.envelope,
            exactBytes: legacyBytes,
            digest: .envelopeBytes(legacyBytes)
        )
        XCTAssertThrowsError(
            try CloudInitialProfileSeedBuilderV1().makeSeed(from: legacy)
        ) { error in
            XCTAssertEqual(
                error as? CloudInitialProfileSeedError,
                .unsupportedSourceSchemaVersion(PlayerProfileEnvelopeV3.schemaVersion)
            )
        }

        let malformedBytes = Data("not-json".utf8)
        let malformed = CanonicalProfileEnvelopeArtifactV1(
            envelope: artifact.envelope,
            exactBytes: malformedBytes,
            digest: .envelopeBytes(malformedBytes)
        )
        XCTAssertThrowsError(
            try CloudInitialProfileSeedBuilderV1().makeSeed(from: malformed)
        ) { error in
            XCTAssertEqual(
                error as? CloudInitialProfileSeedError,
                .malformedSourceEnvelope
            )
        }
    }

    func testProductionBoundsAreEnforced() throws {
        let artifact = try makeArtifact(makeDefaultDocument())
        let sourceLimit = makeLimits(
            maximumProfileEnvelopeBytes: artifact.exactBytes.count - 1
        )
        XCTAssertThrowsError(
            try CloudInitialProfileSeedBuilderV1(limits: sourceLimit).makeSeed(
                from: artifact
            )
        ) { error in
            XCTAssertEqual(
                error as? CloudInitialProfileSeedError,
                .sourceEnvelopeLimitExceeded(
                    actual: artifact.exactBytes.count,
                    maximum: artifact.exactBytes.count - 1
                )
            )
        }

        XCTAssertThrowsError(
            try CloudInitialProfileSeedBuilderV1(
                limits: makeLimits(maximumIdentifierBytes: 3)
            ).makeSeed(from: artifact)
        ) { error in
            XCTAssertEqual(error as? CloudInitialProfileSeedError, .identifierLimitExceeded)
        }

        XCTAssertThrowsError(
            try CloudInitialProfileSeedBuilderV1(
                limits: makeLimits(maximumProfileCollectionEntries: 1)
            ).makeSeed(from: artifact)
        ) { error in
            XCTAssertEqual(
                error as? CloudInitialProfileSeedError,
                .profileCollectionLimitExceeded
            )
        }

        XCTAssertThrowsError(
            try CloudInitialProfileSeedBuilderV1(
                limits: makeLimits(maximumEncodedJournalBytes: 1)
            ).makeSeed(from: artifact)
        ) { error in
            guard case let .seedLimitExceeded(actual, maximum) =
                error as? CloudInitialProfileSeedError else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertGreaterThan(actual, maximum)
            XCTAssertEqual(maximum, 1)
        }
    }

    func testScopedQueuePlayerAndNestedCollectionCapsFailClosed() throws {
        var tooManyPlayers = makeDefaultDocument()
        tooManyPlayers.player.pendingGameCenter = PlayerScopedGameCenterQueueV1(
            pendingByPlayerID: Dictionary(uniqueKeysWithValues:
                (0 ... PlayerScopedGameCenterQueueV1.maximumPlayerBucketCount).map {
                    (
                        GameCenterPlayerID("seed-player-\($0)"),
                        GameCenterPendingMaximaV1(pendingHighScore: 1)
                    )
                }
            )
        )
        try assertSeedError(
            .profileCollectionLimitExceeded,
            document: tooManyPlayers
        )

        let tooManyAchievements = Dictionary(uniqueKeysWithValues:
            (0 ... AchievementCatalog.launch.count).map {
                (AchievementID("seed-overflow-\($0)"), 1)
            }
        )
        var unboundOverflow = makeDefaultDocument()
        unboundOverflow.player.pendingGameCenter = PlayerScopedGameCenterQueueV1(
            unboundPending: GameCenterPendingMaximaV1(
                pendingAchievementPercents: tooManyAchievements
            )
        )
        try assertSeedError(
            .profileCollectionLimitExceeded,
            document: unboundOverflow
        )

        var boundOverflow = makeDefaultDocument()
        boundOverflow.player.pendingGameCenter = PlayerScopedGameCenterQueueV1(
            pendingByPlayerID: [
                GameCenterPlayerID("seed-player-bound-overflow"):
                    GameCenterPendingMaximaV1(
                        pendingAchievementPercents: tooManyAchievements
                    ),
            ]
        )
        try assertSeedError(
            .profileCollectionLimitExceeded,
            document: boundOverflow
        )
    }

    func testScopedQueueIdentifiersAndValuesUseSeedBounds() throws {
        let achievementID = try XCTUnwrap(AchievementCatalog.launch.first?.id)
        var oversizedPlayer = makeDefaultDocument()
        oversizedPlayer.player.achievementProgress[achievementID] = AchievementProgress(
            id: achievementID,
            percentComplete: 1
        )
        oversizedPlayer.player.pendingGameCenter = PlayerScopedGameCenterQueueV1(
            pendingByPlayerID: [
                GameCenterPlayerID(String(repeating: "p", count: 65)):
                    GameCenterPendingMaximaV1(
                        pendingAchievementPercents: [achievementID: 1]
                    ),
            ]
        )
        try assertSeedError(
            .identifierLimitExceeded,
            document: oversizedPlayer,
            limits: makeLimits(maximumIdentifierBytes: 64)
        )

        var oversizedAchievement = makeDefaultDocument()
        oversizedAchievement.player.pendingGameCenter = PlayerScopedGameCenterQueueV1(
            unboundPending: GameCenterPendingMaximaV1(
                pendingAchievementPercents: [
                    AchievementID(String(repeating: "a", count: 65)): 1,
                ]
            )
        )
        try assertSeedError(
            .identifierLimitExceeded,
            document: oversizedAchievement,
            limits: makeLimits(maximumIdentifierBytes: 64)
        )

        var invalidPercent = makeDefaultDocument()
        invalidPercent.player.pendingGameCenter = PlayerScopedGameCenterQueueV1(
            unboundPending: GameCenterPendingMaximaV1(
                pendingAchievementPercents: [achievementID: 101]
            )
        )
        try assertSeedError(.invalidSourceProfile, document: invalidPercent)

        var negativeScore = makeDefaultDocument()
        negativeScore.player.pendingGameCenter = PlayerScopedGameCenterQueueV1(
            unboundPending: GameCenterPendingMaximaV1(pendingHighScore: -1)
        )
        try assertSeedError(.invalidSourceProfile, document: negativeScore)
    }

    func testScopedQueueDictionaryOrderDoesNotChangeArtifactOrSeed() throws {
        let achievementIDs = Array(AchievementCatalog.launch.prefix(2).map(\.id))
        XCTAssertEqual(achievementIDs.count, 2)
        let playerIDs = [
            GameCenterPlayerID("seed-player-b"),
            GameCenterPlayerID("seed-player-a"),
        ]

        var first = makeDefaultDocument()
        for (offset, achievementID) in achievementIDs.enumerated() {
            first.player.achievementProgress[achievementID] = AchievementProgress(
                id: achievementID,
                percentComplete: 20 + offset
            )
        }
        let forwardAchievements = Dictionary(uniqueKeysWithValues:
            zip(achievementIDs, [20, 21])
        )
        let reverseAchievements = Dictionary(uniqueKeysWithValues:
            zip(achievementIDs.reversed(), [21, 20])
        )
        first.player.pendingGameCenter = PlayerScopedGameCenterQueueV1(
            pendingByPlayerID: Dictionary(uniqueKeysWithValues: [
                (
                    playerIDs[0],
                    GameCenterPendingMaximaV1(
                        pendingAchievementPercents: forwardAchievements
                    )
                ),
                (
                    playerIDs[1],
                    GameCenterPendingMaximaV1(
                        pendingAchievementPercents: [achievementIDs[0]: 20]
                    )
                ),
            ]),
            unboundPending: GameCenterPendingMaximaV1(
                pendingAchievementPercents: forwardAchievements
            )
        )

        var reversed = first
        reversed.player.pendingGameCenter = PlayerScopedGameCenterQueueV1(
            pendingByPlayerID: Dictionary(uniqueKeysWithValues: [
                (
                    playerIDs[1],
                    GameCenterPendingMaximaV1(
                        pendingAchievementPercents: [achievementIDs[0]: 20]
                    )
                ),
                (
                    playerIDs[0],
                    GameCenterPendingMaximaV1(
                        pendingAchievementPercents: reverseAchievements
                    )
                ),
            ]),
            unboundPending: GameCenterPendingMaximaV1(
                pendingAchievementPercents: reverseAchievements
            )
        )

        let firstArtifact = try makeArtifact(first)
        let reversedArtifact = try makeArtifact(reversed)
        XCTAssertEqual(firstArtifact.exactBytes, reversedArtifact.exactBytes)
        XCTAssertEqual(firstArtifact.digest, reversedArtifact.digest)

        let builder = CloudInitialProfileSeedBuilderV1()
        let firstSeed = try builder.makeSeed(from: firstArtifact)
        let reversedSeed = try builder.makeSeed(from: reversedArtifact)
        XCTAssertEqual(
            firstSeed.debugSeedDigestRawValue,
            reversedSeed.debugSeedDigestRawValue
        )
        XCTAssertEqual(
            try firstSeed.canonicalEncodedData(),
            try reversedSeed.canonicalEncodedData()
        )
    }

    func testDigestAndCanonicalBytesIgnoreDictionaryAndSetInsertionOrder() throws {
        let runIDs = [
            RunID(UUID(uuidString: "aaaaaaaa-0000-0000-0000-000000000001")!),
            RunID(UUID(uuidString: "aaaaaaaa-0000-0000-0000-000000000002")!),
        ]
        let first = try makePendingGameplayDocument(runIDs: runIDs)
        var reordered = first
        reordered.player.completedRuns = Dictionary(
            uniqueKeysWithValues: first.player.completedRuns.sorted {
                $0.key.description > $1.key.description
            }
        )
        reordered.player.ledger = Dictionary(
            uniqueKeysWithValues: first.player.ledger.sorted {
                $0.key.rawValue > $1.key.rawValue
            }
        )
        reordered.pendingLedgerEntryIDs = Set(
            first.pendingLedgerEntryIDs.sorted { $0.rawValue > $1.rawValue }
        )
        reordered.player.selection.value.selectedJerseyByTeam = Dictionary(
            uniqueKeysWithValues:
                first.player.selection.value.selectedJerseyByTeam.sorted {
                    $0.key.rawValue > $1.key.rawValue
                }
        )

        let firstArtifact = try makeArtifact(first)
        let reorderedArtifact = try makeArtifact(reordered)
        XCTAssertEqual(firstArtifact.exactBytes, reorderedArtifact.exactBytes)
        XCTAssertEqual(firstArtifact.digest, reorderedArtifact.digest)

        let builder = CloudInitialProfileSeedBuilderV1()
        let firstSeed = try builder.makeSeed(from: firstArtifact)
        let reorderedSeed = try builder.makeSeed(from: reorderedArtifact)
        XCTAssertEqual(
            firstSeed.debugSeedDigestRawValue,
            reorderedSeed.debugSeedDigestRawValue
        )
        XCTAssertEqual(
            try firstSeed.canonicalEncodedData(),
            try reorderedSeed.canonicalEncodedData()
        )
    }

    func testSeedIsOneWayEncodableAndDigestChangesWithNeutralFacts() throws {
        func requireEncodable<T: Encodable>(_: T) {}

        let first = makeDefaultDocument()
        var changed = first
        changed.player.settings.value.isMuted = true
        changed.player.settings.logicalCounter += 1
        changed.player.settings.modifiedAt = baseDate.addingTimeInterval(1)

        let builder = CloudInitialProfileSeedBuilderV1()
        let firstSeed = try builder.makeSeed(from: makeArtifact(first))
        let changedSeed = try builder.makeSeed(from: makeArtifact(changed))
        requireEncodable(firstSeed)

        XCTAssertNotEqual(
            firstSeed.debugSeedDigestRawValue,
            changedSeed.debugSeedDigestRawValue
        )
        XCTAssertNotEqual(
            try firstSeed.canonicalEncodedData(),
            try changedSeed.canonicalEncodedData()
        )
    }

    private func makeDefaultDocument() -> LocalPlayerDocumentV1 {
        PlayerProfileFactory.makeDefault(
            profileID: profileID,
            accountIdentity: accountIdentity,
            deviceID: "device-a",
            createdAt: baseDate
        )
    }

    private func makeEmptyCheckpoint(
        accountID: CloudAccountID
    ) throws -> CloudReplicaCheckpointV1 {
        try CloudReplicaCheckpointV1(
            accountID: accountID,
            configurationScopeFingerprint:
                CloudReplicaScopeFingerprint(
                    rawValue: String(repeating: "a", count: 64)
                ),
            generation: 1,
            finalCursor: CloudChangeCursor(Data([1])),
            recordsByLogicalID: [:],
            providerLocatorByLogicalID: [:],
            logicalIDByProviderLocator: [:],
            tombstonesByProviderLocator: [:],
            replicaEpoch: UUID()
        )
    }

    private func makePublicationPlanner() throws
        -> CloudInitialProfilePublicationPlannerV1
    {
        CloudInitialProfilePublicationPlannerV1(
            profileConfiguration: try CloudProfileSchemaConfiguration(
                rootRecordType: "ProfileRoot",
                settingsRecordType: "ProfileSettings",
                selectionRecordType: "ProfileSelection",
                runRecordType: "ProfileRun",
                payloadFieldName: "payload"
            ),
            economyConfiguration: try DurableEconomyCloudConfiguration(
                recordID: CloudRecordID("economy-head"),
                recordType: "EconomyRecord",
                payloadFieldName: "payload"
            )
        )
    }

    private func makeArtifact(
        _ document: LocalPlayerDocumentV1,
        savedAt: Date? = nil
    ) throws -> CanonicalProfileEnvelopeArtifactV1 {
        try PlayerProfileMigrator().canonicalArtifact(
            for: document,
            savedAt: savedAt ?? baseDate.addingTimeInterval(600)
        )
    }

    private func makePendingGameplayDocument(
        runIDs: [RunID]
    ) throws -> LocalPlayerDocumentV1 {
        var document = makeDefaultDocument()
        var records: [RunID: CompletedRunRecord] = [:]
        var ledger: [LedgerEntryID: CoinLedgerEntry] = [:]
        var receipts: [RunID: RunSettlementOutcome] = [:]
        var observations: [RunID: RewardedRunObservation] = [:]
        var pending: Set<LedgerEntryID> = []

        for (index, runID) in runIDs.enumerated() {
            let record = try makeRunRecord(runID: runID, offset: TimeInterval(index * 120))
            let gameplayID = CoinLedgerID.gameplay(runID: runID)
            records[runID] = record
            ledger[gameplayID] = CoinLedgerEntry(
                id: gameplayID,
                delta: record.rewardCoins,
                reason: .gameplay(
                    runID: runID,
                    economyVersion: record.run.configuration.economyVersion
                ),
                createdAt: record.recordedAt
            )
            pending.insert(gameplayID)
            observations[runID] = RewardedRunObservation(
                observedCycle: 0,
                disposition: .candidate
            )

            let signingID: LedgerEntryID?
            if index == 0 {
                let id = CoinLedgerID.signingBonus(
                    version: PersistedEconomyRulesV1.signingBonusVersion
                )
                ledger[id] = CoinLedgerEntry(
                    id: id,
                    delta: PersistedEconomyRulesV1.signingBonusCoins,
                    reason: .signingBonus(
                        version: PersistedEconomyRulesV1.signingBonusVersion
                    ),
                    createdAt: PersistedEconomyRulesV1.signingBonusLedgerCreatedAt
                )
                pending.insert(id)
                signingID = id
            } else {
                signingID = nil
            }
            receipts[runID] = RunSettlementOutcome(
                record: record,
                gameplayRewardEntryID: gameplayID,
                signingBonusEntryID: signingID,
                achievementUpdates: [],
                rewardedOfferUnlocked: nil,
                resultingPersonalBest: record.run.score
            )
        }

        document.player.revision = 2
        document.economyRevision = 3
        document.player.completedRuns = records
        document.player.ledger = ledger
        document.pendingLedgerEntryIDs = pending
        document.settlementReceipts = receipts
        document.rewardedRunObservations = observations
        document.player.career = try PersistedCareerAccumulatorV1.recompute(
            from: records.values
        )
        document.player.rewardedAdState = RewardedAdState(
            cycle: 0,
            validRunsSinceReward: runIDs.count,
            eligibleOfferID: runIDs.count == PersistedEconomyRulesV1.rewardedAdRunThreshold
                ? RewardedAdState.offerID(for: 0)
                : nil,
            accountedRunIDs: Set(runIDs)
        )
        return document
    }

    private func makeRunRecord(
        runID: RunID,
        offset: TimeInterval = 0
    ) throws -> CompletedRunRecord {
        let offense = try XCTUnwrap(
            LaunchCatalog.approved.team(id: LaunchTeamID.novaCityComets)
        )
        let defense = try XCTUnwrap(
            LaunchCatalog.approved.team(id: LaunchTeamID.lumaCoastPrisms)
        )
        let startedAt = baseDate.addingTimeInterval(offset)
        let endedAt = startedAt.addingTimeInterval(60)
        let run = CompletedRun(
            configuration: RunConfiguration(
                runID: runID,
                randomSeed: UInt32(offset) + 7,
                offenseTeamID: offense.id,
                offenseJerseyID: offense.primaryJersey.id,
                defenseTeamID: defense.id,
                defenseJerseyID: defense.primaryJersey.id,
                footballID: LaunchFootballID.standard,
                economyVersion: PersistedEconomyRulesV1.run.economyVersion,
                startedAt: startedAt
            ),
            endedAt: endedAt,
            elapsedGameplayMilliseconds: PersistedEconomyRulesV1.run.naturalRunMilliseconds,
            finishReason: .timerExpired,
            score: 2_500,
            statistics: RunStatisticsSnapshot(
                attempts: 10,
                completions: 5,
                touchdowns: 2,
                incompletions: 2,
                interceptions: 1,
                longestTouchdownStreak: 2
            ),
            completedLaneIDs: Set(LaneID.allCases.prefix(2)),
            bonusTouchdownCount: 1
        )
        return CompletedRunRecord(
            run: run,
            recordedAt: endedAt.addingTimeInterval(1),
            rewardCoins: try CompletedRunValidator.rewardCoins(for: run)
        )
    }

    private func assertSeedError(
        _ expected: CloudInitialProfileSeedError,
        document: LocalPlayerDocumentV1,
        limits: ProfileHydrationLimits = .production,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertThrowsError(
            try CloudInitialProfileSeedBuilderV1(limits: limits).makeSeed(
                from: makeArtifact(document)
            ),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(
                error as? CloudInitialProfileSeedError,
                expected,
                file: file,
                line: line
            )
        }
    }

    private func makeLimits(
        maximumEncodedJournalBytes: Int = ProfileHydrationLimits.production
            .maximumEncodedJournalBytes,
        maximumProfileEnvelopeBytes: Int = ProfileHydrationLimits.production
            .maximumProfileEnvelopeBytes,
        maximumIdentifierBytes: Int = ProfileHydrationLimits.production.maximumIdentifierBytes,
        maximumProfileCollectionEntries: Int = ProfileHydrationLimits.production
            .maximumProfileCollectionEntries
    ) -> ProfileHydrationLimits {
        let production = ProfileHydrationLimits.production
        return ProfileHydrationLimits(
            maximumEncodedJournalBytes: maximumEncodedJournalBytes,
            maximumProfileEnvelopeBytes: maximumProfileEnvelopeBytes,
            maximumEncodedCheckpointBytes: production.maximumEncodedCheckpointBytes,
            maximumIdentifierBytes: maximumIdentifierBytes,
            maximumProfileCollectionEntries: maximumProfileCollectionEntries,
            maximumQuarantineFiles: production.maximumQuarantineFiles,
            maximumQuarantineBytes: production.maximumQuarantineBytes
        )
    }
}

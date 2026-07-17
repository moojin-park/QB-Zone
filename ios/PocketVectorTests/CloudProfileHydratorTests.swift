import CryptoKit
import XCTest
@testable import PocketVector

final class CloudProfileHydratorTests: XCTestCase, @unchecked Sendable {
    func testNoOpKeepsBothRevisionsDespiteDifferentCandidateSavedAt() async throws {
        let fixture = try await makeFixture()
        let result = try hydrate(fixture)

        XCTAssertTrue(result.isNoOp)
        XCTAssertEqual(result.candidateDocument, fixture.source.envelope.document)
        XCTAssertEqual(result.revisionPlan.candidatePlayerRevision, 7)
        XCTAssertEqual(result.revisionPlan.candidateEconomyRevision, 3)
        XCTAssertNotEqual(
            result.sourceEnvelope.canonicalBytes,
            result.candidateEnvelope.canonicalBytes,
            "savedAt belongs to the exact artifact, not semantic no-op detection"
        )
        XCTAssertEqual(result.sourceEnvelope.sha256Digest.count, 32)
        XCTAssertEqual(result.candidateEnvelope.sha256Digest.count, 32)
        XCTAssertEqual(
            result.sourceEnvelope.canonicalBytes,
            fixture.source.exactEnvelopeBytes
        )
        XCTAssertEqual(
            try PlayerProfileMigrator().decode(
                result.candidateEnvelope.canonicalBytes
            ),
            result.candidateDocument
        )
    }

    func testNoOpPreservesEveryPlayerBucketWithoutManufacturingUnboundWork()
        async throws
    {
        var fixture = try await makeFixture()
        let playerA = GameCenterPlayerID("hydration-player-a")
        let playerB = GameCenterPlayerID("hydration-player-b")
        let record = makeRecord(uuid: 31, offset: 0)
        var document = try settledDocument(
            base: fixture.source.envelope.document,
            records: [record],
            confirmedGameplayRunIDs: []
        )
        document.player.pendingGameCenter = PlayerScopedGameCenterQueueV1(
            pendingByPlayerID: [
                playerA: GameCenterPendingMaximaV1(
                    pendingHighScore: record.run.score
                ),
                playerB: GameCenterPendingMaximaV1(
                    pendingAchievementPercents: [
                        LaunchAchievementID.firstRead: 60,
                    ]
                ),
            ]
        )
        fixture.source = source(
            document: document,
            metadata: metadata(for: document, counter: 2),
            savedAt: date(2_000),
            nonce: fixture.source.activeSession.nonce
        )
        fixture.replica = try await makeReplica(
            context: fixture.context,
            sourceDocument: document
        )

        let result = try hydrate(fixture)

        XCTAssertTrue(result.isNoOp)
        XCTAssertEqual(
            result.candidateDocument.player.pendingGameCenter,
            document.player.pendingGameCenter
        )
        XCTAssertTrue(
            result.candidateDocument.player.pendingGameCenter.unboundPending
                .isEmpty
        )
    }

    func testSemanticallyDecodableNoncanonicalSourceBytesReject() async throws {
        var fixture = try await makeFixture()
        let object = try JSONSerialization.jsonObject(
            with: fixture.source.exactEnvelopeBytes
        )
        let noncanonical = try JSONSerialization.data(
            withJSONObject: object,
            options: []
        )
        XCTAssertNotEqual(noncanonical, fixture.source.exactEnvelopeBytes)
        XCTAssertNoThrow(try PlayerProfileMigrator().decode(noncanonical))
        fixture.source = CloudProfileHydrationSourceV1(
            exactEnvelopeBytes: noncanonical,
            activeSession: fixture.source.activeSession
        )

        assertHydrationError(.noncanonicalSourceEnvelope, fixture: fixture)
    }

    func testFreshLocalProfileAcceptsIndependentRemoteCounterOneHundred() async throws {
        var fixture = try await makeFixture(playerRevision: 0)
        var remoteSettings = fixture.source.envelope.document.player.settings.value
        remoteSettings.isMuted = true
        fixture.replica = try await makeReplica(
            context: fixture.context,
            sourceDocument: fixture.source.envelope.document,
            settings: remoteSettings,
            settingsStamp: try stamp(100, "remote-device", date(1_500))
        )

        let result = try hydrate(fixture)
        XCTAssertTrue(result.candidateDocument.player.settings.value.isMuted)
        XCTAssertEqual(result.candidateDocument.player.settings.logicalCounter, 100)
        XCTAssertEqual(result.candidateDocument.player.revision, 1)
        XCTAssertEqual(result.candidateDocument.economyRevision, 4)

        var invalid = fixture.source.envelope.document
        invalid.player.settings.deviceID = "invalid device id"
        fixture.source = source(
            document: invalid,
            metadata: nil,
            savedAt: fixture.source.envelope.savedAt,
            nonce: fixture.source.activeSession.nonce
        )
        assertHydrationError(.invalidSourceProfile, fixture: fixture)
    }

    func testNewerRemoteSettingsArePlayerOnlyMaterial() async throws {
        var fixture = try await makeFixture()
        var remoteSettings = fixture.source.envelope.document.player.settings.value
        remoteSettings.isMuted = true
        fixture.replica = try await makeReplica(
            context: fixture.context,
            sourceDocument: fixture.source.envelope.document,
            settings: remoteSettings,
            settingsStamp: try stamp(5, "remote-device", date(1_500))
        )

        let result = try hydrate(fixture)
        XCTAssertTrue(result.candidateDocument.player.settings.value.isMuted)
        XCTAssertTrue(result.revisionPlan.playerMaterialChanged)
        XCTAssertFalse(result.revisionPlan.economyMaterialChanged)
        XCTAssertEqual(result.revisionPlan.candidatePlayerRevision, 8)
        XCTAssertEqual(result.revisionPlan.candidateEconomyRevision, 4)
    }

    func testNewerLocalSettingsWinAndLogicalTieDivergenceRejects() async throws {
        var fixture = try await makeFixture()
        var staleRemote = fixture.source.envelope.document.player.settings.value
        staleRemote.isMuted = true
        fixture.replica = try await makeReplica(
            context: fixture.context,
            sourceDocument: fixture.source.envelope.document,
            settings: staleRemote,
            settingsStamp: try stamp(1, "remote-device", date(1_500))
        )
        XCTAssertFalse(try hydrate(fixture).candidateDocument.player.settings.value.isMuted)

        let localStamp = try settingsStamp(
            of: fixture.source.envelope.document
        )
        fixture.replica = try await makeReplica(
            context: fixture.context,
            sourceDocument: fixture.source.envelope.document,
            settings: staleRemote,
            settingsStamp: try stamp(
                localStamp.logicalCounter,
                localStamp.deviceID,
                date(1_900)
            )
        )
        assertHydrationError(.settingsEqualStampDivergence, fixture: fixture)
    }

    func testSettingsStampDeviceIDProvidesStableTotalOrder() async throws {
        var fixture = try await makeFixture()
        var remote = fixture.source.envelope.document.player.settings.value
        remote.reducedMotion = true
        let local = try settingsStamp(of: fixture.source.envelope.document)
        fixture.replica = try await makeReplica(
            context: fixture.context,
            sourceDocument: fixture.source.envelope.document,
            settings: remote,
            settingsStamp: try stamp(
                local.logicalCounter,
                "zz-remote",
                date(1_600)
            )
        )

        let result = try hydrate(fixture)
        XCTAssertTrue(result.candidateDocument.player.settings.value.reducedMotion)
        XCTAssertEqual(
            result.candidateMergeMetadata.settingsStamp.deviceID,
            "zz-remote"
        )
    }

    func testSelectionStampOrderingAndEqualStampConflict() async throws {
        var fixture = try await makeFixture()
        let catalog = LaunchCatalog.approved
        var selection = InventoryRules.initialSelection(catalog: catalog)
        selection.selectedTeamID = LaunchTeamID.highMesaHelions
        selection.selectedJerseyByTeam[LaunchTeamID.highMesaHelions]
            = catalog.team(id: LaunchTeamID.highMesaHelions)!.primaryJersey.id
        let newer = try stamp(4, "remote-device", date(1_700))
        fixture.replica = try await makeReplica(
            context: fixture.context,
            sourceDocument: fixture.source.envelope.document,
            selection: selection,
            selectionStamp: newer
        )
        let result = try hydrate(fixture)
        XCTAssertEqual(
            result.candidateDocument.player.selection.value.selectedTeamID,
            LaunchTeamID.highMesaHelions
        )
        XCTAssertEqual(result.candidateMergeMetadata.selectionStamp, newer)

        let local = try selectionStamp(of: fixture.source.envelope.document)
        fixture.replica = try await makeReplica(
            context: fixture.context,
            sourceDocument: fixture.source.envelope.document,
            selection: selection,
            selectionStamp: try stamp(
                local.logicalCounter,
                local.deviceID,
                date(1_800)
            )
        )
        assertHydrationError(.selectionEqualStampDivergence, fixture: fixture)
    }

    func testRemoteSelectionMissingRememberedOwnedJerseyUsesSafeFallback() async throws {
        var fixture = try await makeFixture()
        var selection = InventoryRules.initialSelection()
        selection.selectedJerseyByTeam.removeValue(
            forKey: LaunchTeamID.highMesaHelions
        )
        fixture.replica = try await makeReplica(
            context: fixture.context,
            sourceDocument: fixture.source.envelope.document,
            selection: selection,
            selectionStamp: try stamp(9, "remote-device", date(1_700))
        )

        let result = try hydrate(fixture)
        let primary = LaunchCatalog.approved
            .team(id: LaunchTeamID.highMesaHelions)!.primaryJersey.id
        XCTAssertEqual(
            result.candidateDocument.player.selection.value
                .selectedJerseyByTeam[LaunchTeamID.highMesaHelions],
            primary
        )
        XCTAssertEqual(
            result.candidateMergeMetadata.selectionStamp.logicalCounter,
            10
        )
        XCTAssertEqual(
            result.candidateMergeMetadata.selectionStamp.deviceID,
            fixture.context.installingDeviceID
        )
    }

    func testLocalOnlyRunIsPreserved() async throws {
        var fixture = try await makeFixture()
        let record = makeRecord(uuid: 1, offset: 0)
        let document = try settledDocument(
            base: fixture.source.envelope.document,
            records: [record],
            confirmedGameplayRunIDs: []
        )
        fixture.source = source(
            document: document,
            metadata: metadata(for: document, counter: 2),
            savedAt: date(2_000),
            nonce: fixture.source.activeSession.nonce
        )
        fixture.replica = try await makeReplica(
            context: fixture.context,
            sourceDocument: document
        )

        let result = try hydrate(fixture)
        XCTAssertEqual(result.candidateDocument.player.completedRuns[record.run.runID], record)
        XCTAssertTrue(
            result.candidateDocument.pendingLedgerEntryIDs.contains(
                CoinLedgerID.gameplay(runID: record.run.runID)
            )
        )
    }

    func testRemoteOnlyRunIsInstalledWithPendingGameplayAndSigningBonus() async throws {
        var fixture = try await makeFixture()
        let playerID = GameCenterPlayerID("existing-hydration-player")
        var sourceDocument = fixture.source.envelope.document
        sourceDocument.player.achievementProgress[LaunchAchievementID.firstRead] =
            AchievementProgress(
                id: LaunchAchievementID.firstRead,
                percentComplete: 50
            )
        sourceDocument.player.pendingGameCenter = PlayerScopedGameCenterQueueV1(
            pendingByPlayerID: [
                playerID: GameCenterPendingMaximaV1(
                    pendingAchievementPercents: [
                        LaunchAchievementID.firstRead: 50,
                    ]
                ),
            ],
            unboundPending: GameCenterPendingMaximaV1(pendingHighScore: 50)
        )
        fixture.source = source(
            document: sourceDocument,
            metadata: metadata(for: sourceDocument, counter: 2),
            savedAt: date(2_000),
            nonce: fixture.source.activeSession.nonce
        )
        let record = makeRecord(uuid: 2, offset: 0)
        let payload = cloudRun(
            record,
            binding: binding(for: fixture.context),
            observation: candidateObservation()
        )
        fixture.replica = try await makeReplica(
            context: fixture.context,
            sourceDocument: sourceDocument,
            remoteRuns: [record.run.runID: payload]
        )

        let result = try hydrate(fixture)
        let gameplayID = CoinLedgerID.gameplay(runID: record.run.runID)
        let signingID = CoinLedgerID.signingBonus(version: 1)
        XCTAssertEqual(result.candidateDocument.player.completedRuns.count, 1)
        XCTAssertTrue(result.candidateDocument.pendingLedgerEntryIDs.contains(gameplayID))
        XCTAssertTrue(result.candidateDocument.pendingLedgerEntryIDs.contains(signingID))
        XCTAssertEqual(result.candidateDocument.player.career.completedRuns, 1)
        XCTAssertEqual(result.candidateDocument.player.rewardedAdState.validRunsSinceReward, 1)
        XCTAssertEqual(
            result.candidateDocument.player.pendingGameCenter
                .pending(for: playerID)?
                .pendingAchievementPercents[LaunchAchievementID.firstRead],
            50
        )
        XCTAssertEqual(
            result.candidateDocument.player.pendingGameCenter.unboundPending
                .pendingHighScore,
            record.run.score
        )
        XCTAssertEqual(
            result.candidateDocument.player.pendingGameCenter.unboundPending
                .pendingAchievementPercents[LaunchAchievementID.firstRead],
            100
        )
        XCTAssertEqual(
            result.candidateDocument.player.pendingGameCenter.unboundPending
                .pendingAchievementPercents[LaunchAchievementID.paydirt],
            100
        )
        XCTAssertTrue(result.revisionPlan.playerMaterialChanged)
        XCTAssertTrue(result.revisionPlan.economyMaterialChanged)
    }

    func testDisjointLocalAndRemoteRunsUnionDeterministically() async throws {
        var fixture = try await makeFixture()
        let localRecord = makeRecord(uuid: 3, offset: 0)
        let remoteRecord = makeRecord(uuid: 4, offset: 100)
        let localDocument = try settledDocument(
            base: fixture.source.envelope.document,
            records: [localRecord],
            confirmedGameplayRunIDs: []
        )
        fixture.source = source(
            document: localDocument,
            metadata: metadata(for: localDocument, counter: 2),
            savedAt: date(2_000),
            nonce: fixture.source.activeSession.nonce
        )
        let remotePayload = cloudRun(
            remoteRecord,
            binding: binding(for: fixture.context),
            observation: candidateObservation()
        )
        let remoteGameplay = gameplayEntry(remoteRecord)
        let signing = signingEntry()
        fixture.replica = try await makeReplica(
            context: fixture.context,
            sourceDocument: localDocument,
            remoteRuns: [remoteRecord.run.runID: remotePayload],
            confirmedEntriesInOrder: [remoteGameplay, signing]
        )

        let result = try hydrate(fixture)
        XCTAssertEqual(Set(result.candidateDocument.player.completedRuns.keys), [
            localRecord.run.runID, remoteRecord.run.runID,
        ])
        XCTAssertTrue(
            result.candidateDocument.pendingLedgerEntryIDs.contains(
                CoinLedgerID.gameplay(runID: localRecord.run.runID)
            )
        )
        XCTAssertFalse(
            result.candidateDocument.pendingLedgerEntryIDs.contains(
                CoinLedgerID.gameplay(runID: remoteRecord.run.runID)
            )
        )
        XCTAssertEqual(result.candidateDocument.player.rewardedAdState.validRunsSinceReward, 2)
    }

    func testEqualRunPromotesMatchingPendingCreditsExactlyOnce() async throws {
        var fixture = try await makeFixture()
        let record = makeRecord(uuid: 5, offset: 0)
        let local = try settledDocument(
            base: fixture.source.envelope.document,
            records: [record],
            confirmedGameplayRunIDs: []
        )
        let localMetadata = metadata(for: local, counter: 2)
        fixture.source = source(
            document: local,
            metadata: localMetadata,
            savedAt: date(2_000),
            nonce: fixture.source.activeSession.nonce
        )
        fixture.replica = try await makeReplica(
            context: fixture.context,
            sourceDocument: local,
            remoteRuns: [
                record.run.runID: cloudRun(
                    record,
                    binding: binding(for: fixture.context),
                    observation: candidateObservation()
                ),
            ],
            confirmedEntriesInOrder: [gameplayEntry(record), signingEntry()]
        )

        let promoted = try hydrate(fixture)
        XCTAssertTrue(promoted.candidateDocument.pendingLedgerEntryIDs.isEmpty)
        XCTAssertEqual(promoted.candidateDocument.player.ledger.count, 2)
        XCTAssertEqual(promoted.revisionPlan.candidatePlayerRevision, 8)
        XCTAssertEqual(promoted.revisionPlan.candidateEconomyRevision, 4)

        fixture.source = source(
            document: promoted.candidateDocument,
            metadata: promoted.candidateMergeMetadata,
            savedAt: fixture.context.candidateSavedAt,
            nonce: fixture.source.activeSession.nonce
        )
        let repeated = try hydrate(fixture)
        XCTAssertTrue(repeated.isNoOp)
        XCTAssertEqual(repeated.candidateDocument.player.ledger.count, 2)
    }

    func testEqualRunWithDifferentCanonicalContentRejects() async throws {
        var fixture = try await makeFixture()
        let localRecord = makeRecord(uuid: 6, offset: 0, score: 5_000)
        let remoteRecord = makeRecord(uuid: 6, offset: 0, score: 6_000)
        let local = try settledDocument(
            base: fixture.source.envelope.document,
            records: [localRecord],
            confirmedGameplayRunIDs: []
        )
        fixture.source = source(
            document: local,
            metadata: metadata(for: local, counter: 2),
            savedAt: date(2_000),
            nonce: fixture.source.activeSession.nonce
        )
        fixture.replica = try await makeReplica(
            context: fixture.context,
            sourceDocument: local,
            remoteRuns: [
                remoteRecord.run.runID: cloudRun(
                    remoteRecord,
                    binding: binding(for: fixture.context),
                    observation: candidateObservation()
                ),
            ]
        )
        assertHydrationError(
            .completedRunConflict(localRecord.run.runID),
            fixture: fixture
        )
    }

    func testEqualRunWithDifferentRewardObservationRejects() async throws {
        var fixture = try await makeFixture()
        let record = makeRecord(uuid: 7, offset: 0)
        let local = try settledDocument(
            base: fixture.source.envelope.document,
            records: [record],
            confirmedGameplayRunIDs: []
        )
        fixture.source = source(
            document: local,
            metadata: metadata(for: local, counter: 2),
            savedAt: date(2_000),
            nonce: fixture.source.activeSession.nonce
        )
        fixture.replica = try await makeReplica(
            context: fixture.context,
            sourceDocument: local,
            remoteRuns: [
                record.run.runID: cloudRun(
                    record,
                    binding: binding(for: fixture.context),
                    observation: RewardedRunObservation(
                        observedCycle: 0,
                        disposition: .legacyNonCounting
                    )
                ),
            ]
        )
        assertHydrationError(
            .rewardedRunObservationConflict(record.run.runID),
            fixture: fixture
        )
    }

    func testRemoteUnlockInstallsDebitOwnershipAndValidSelectionTogether() async throws {
        var fixture = try await makeFixture()
        let catalog = LaunchCatalog.approved
        let teamItem = catalog.unlockableItems.first {
            if case .team(LaunchTeamID.lumaCoastPrisms) = $0.kind { return true }
            return false
        }!
        let storeCredit = CoinLedgerEntry(
            id: CoinLedgerID.storeKit(transactionID: 42),
            delta: 1_650,
            reason: .storeKit(transactionID: 42, packID: CoinPackID("team")),
            createdAt: date(2_100)
        )
        let unlock = CoinLedgerEntry(
            id: CoinLedgerID.catalogUnlock(itemID: teamItem.id),
            delta: -1_500,
            reason: .catalogUnlock(itemID: teamItem.id),
            createdAt: date(2_200)
        )
        var selection = InventoryRules.initialSelection()
        selection.selectedTeamID = LaunchTeamID.lumaCoastPrisms
        fixture.replica = try await makeReplica(
            context: fixture.context,
            sourceDocument: fixture.source.envelope.document,
            selection: selection,
            selectionStamp: try stamp(8, "remote-device", date(2_300)),
            confirmedEntriesInOrder: [storeCredit, unlock],
            unlockedItemIDs: [teamItem.id]
        )

        let result = try hydrate(fixture)
        XCTAssertTrue(
            result.candidateDocument.player.inventory.ownedTeamIDs.contains(
                LaunchTeamID.lumaCoastPrisms
            )
        )
        XCTAssertEqual(
            result.candidateDocument.player.selection.value.selectedTeamID,
            LaunchTeamID.lumaCoastPrisms
        )
        XCTAssertEqual(
            try PlayerProfileProjection.coinBalances(
                for: result.candidateDocument
            ).confirmed,
            150
        )
        XCTAssertNotNil(result.candidateDocument.player.ledger[unlock.id])
        XCTAssertTrue(result.revisionPlan.economyMaterialChanged)
    }

    func testSourceOnlyDurableOwnershipAbsentCloudRejectsRatherThanErases() async throws {
        var fixture = try await makeFixture()
        let catalog = LaunchCatalog.approved
        let item = catalog.unlockableItems.first {
            if case .football = $0.kind { return true }
            return false
        }!
        var document = fixture.source.envelope.document
        let credit = CoinLedgerEntry(
            id: CoinLedgerID.storeKit(transactionID: 99),
            delta: 1_650,
            reason: .storeKit(transactionID: 99, packID: CoinPackID("team")),
            createdAt: date(2_000)
        )
        let debit = CoinLedgerEntry(
            id: CoinLedgerID.catalogUnlock(itemID: item.id),
            delta: -750,
            reason: .catalogUnlock(itemID: item.id),
            createdAt: date(2_100)
        )
        document.player.ledger[credit.id] = credit
        document.player.ledger[debit.id] = debit
        _ = try InventoryRules.applyUnlock(
            itemID: item.id,
            to: &document.player.inventory,
            catalog: catalog
        )
        try PlayerProfileValidator.validate(document)
        fixture.source = source(
            document: document,
            metadata: metadata(for: document, counter: 2),
            savedAt: date(2_200),
            nonce: fixture.source.activeSession.nonce
        )
        fixture.replica = try await makeReplica(
            context: fixture.context,
            sourceDocument: fixture.source.envelope.document
        )

        assertHydrationError(
            .sourceOwnedFootballMissingFromCloud(LaunchFootballID.alternate),
            fixture: fixture
        )
    }

    func testConfirmedLocalLedgerAbsentCloudAndUnsupportedPendingStoreCreditReject() async throws {
        var fixture = try await makeFixture()
        var document = fixture.source.envelope.document
        let credit = CoinLedgerEntry(
            id: CoinLedgerID.storeKit(transactionID: 100),
            delta: 500,
            reason: .storeKit(transactionID: 100, packID: CoinPackID("pocket")),
            createdAt: date(2_000)
        )
        document.player.ledger[credit.id] = credit
        fixture.source = source(
            document: document,
            metadata: metadata(for: document, counter: 2),
            savedAt: date(2_100),
            nonce: fixture.source.activeSession.nonce
        )
        fixture.replica = try await makeReplica(
            context: fixture.context,
            sourceDocument: document
        )
        assertHydrationError(
            .confirmedLedgerEntryMissingFromCloud(credit.id),
            fixture: fixture
        )

        document.pendingLedgerEntryIDs.insert(credit.id)
        fixture.source = source(
            document: document,
            metadata: metadata(for: document, counter: 2),
            savedAt: date(2_100),
            nonce: fixture.source.activeSession.nonce
        )
        assertHydrationError(
            .unsupportedPendingLedgerEntry(credit.id),
            fixture: fixture
        )
    }

    func testSigningBonusWithoutEligibleRunRejects() async throws {
        var fixture = try await makeFixture()
        fixture.replica = try await makeReplica(
            context: fixture.context,
            sourceDocument: fixture.source.envelope.document,
            confirmedEntriesInOrder: [signingEntry()]
        )
        assertHydrationError(.impossibleSigningBonus, fixture: fixture)
    }

    func testPlayerAndEconomyRevisionOverflowAreTypedAndNoOpAtMaxIsAllowed() async throws {
        var fixture = try await makeFixture(playerRevision: .max, economyRevision: .max)
        let noOp = try hydrate(fixture)
        XCTAssertTrue(noOp.isNoOp)
        XCTAssertEqual(noOp.candidateDocument.player.revision, .max)
        XCTAssertEqual(noOp.candidateDocument.economyRevision, .max)

        var remoteSettings = fixture.source.envelope.document.player.settings.value
        remoteSettings.isMuted = true
        fixture.replica = try await makeReplica(
            context: fixture.context,
            sourceDocument: fixture.source.envelope.document,
            settings: remoteSettings,
            settingsStamp: try stamp(9, "remote-device", date(3_000))
        )
        assertHydrationError(.revisionOverflow(.player), fixture: fixture)

        fixture = try await makeFixture(playerRevision: 7, economyRevision: .max)
        let record = makeRecord(uuid: 8, offset: 0)
        let local = try settledDocument(
            base: fixture.source.envelope.document,
            records: [record],
            confirmedGameplayRunIDs: []
        )
        fixture.source = source(
            document: local,
            metadata: metadata(for: local, counter: 2),
            savedAt: date(2_000),
            nonce: fixture.source.activeSession.nonce
        )
        fixture.replica = try await makeReplica(
            context: fixture.context,
            sourceDocument: local,
            remoteRuns: [
                record.run.runID: cloudRun(
                    record,
                    binding: binding(for: fixture.context),
                    observation: candidateObservation()
                ),
            ],
            confirmedEntriesInOrder: [gameplayEntry(record), signingEntry()]
        )
        assertHydrationError(.revisionOverflow(.economy), fixture: fixture)
    }

    func testAccountProfileSessionAndReplicaBindingMismatchesAreTyped() async throws {
        var fixture = try await makeFixture()
        var document = fixture.source.envelope.document
        document.accountIdentity = .local
        fixture.source = source(
            document: document,
            metadata: metadata(for: document, counter: 2),
            savedAt: date(2_000),
            nonce: fixture.source.activeSession.nonce
        )
        assertHydrationError(
            .sourceAccountMigrationRequired(
                expected: fixture.context.derivedBindings.playerAccountIdentity,
                actual: .local
            ),
            fixture: fixture
        )

        fixture = try await makeFixture()
        document = fixture.source.envelope.document
        let wrongProfile = uuid(999)
        document.player.profileID = wrongProfile
        fixture.source = source(
            document: document,
            metadata: metadata(for: document, counter: 2),
            savedAt: date(2_000),
            nonce: fixture.source.activeSession.nonce
        )
        assertHydrationError(
            .sourceProfileMigrationRequired(
                expected: fixture.context.derivedBindings
                    .durableAccountBinding.profileID,
                actual: wrongProfile
            ),
            fixture: fixture
        )

        fixture = try await makeFixture()
        fixture.source = CloudProfileHydrationSourceV1(
            exactEnvelopeBytes: fixture.source.exactEnvelopeBytes,
            activeSession: ProfileSessionToken(
                accountIdentity: fixture.context.derivedBindings
                    .playerAccountIdentity,
                nonce: uuid(998),
                profileID: uuid(997)
            )
        )
        assertHydrationError(.activeSessionMismatch, fixture: fixture)

        fixture = try await makeFixture()
        let otherContext = CloudProfileHydrationContextV1(
            cloudAccountID: CloudAccountID("other-cloud"),
            installingDeviceID: "install-device",
            candidateSavedAt: date(4_000)
        )
        fixture.replica = try await makeReplica(
            context: otherContext,
            sourceDocument: fixture.source.envelope.document
        )
        assertHydrationError(.replicaBindingMismatch, fixture: fixture)
    }

    func testInvalidInstallingDeviceIDIsRejectedWithoutSelectionFallback() async throws {
        let fixture = try await makeFixture(installingDeviceID: "")

        assertHydrationError(.invalidInstallingDeviceID, fixture: fixture)
    }

    func testCanonicalArtifactsAndCandidateAreIndependentOfDictionaryOrder() async throws {
        var fixtureA = try await makeFixture()
        let first = makeRecord(uuid: 20, offset: 0)
        let second = makeRecord(uuid: 21, offset: 100)
        let documentA = try settledDocument(
            base: fixtureA.source.envelope.document,
            records: [first, second],
            confirmedGameplayRunIDs: []
        )
        var documentB = documentA
        documentB.player.completedRuns = Dictionary(
            uniqueKeysWithValues: documentA.player.completedRuns
                .sorted(by: { $0.key.description > $1.key.description })
        )
        documentB.player.ledger = Dictionary(
            uniqueKeysWithValues: documentA.player.ledger
                .sorted(by: { $0.key.rawValue > $1.key.rawValue })
        )
        documentB.settlementReceipts = Dictionary(
            uniqueKeysWithValues: documentA.settlementReceipts
                .sorted(by: { $0.key.description > $1.key.description })
        )
        documentB.rewardedRunObservations = Dictionary(
            uniqueKeysWithValues: documentA.rewardedRunObservations!
                .sorted(by: { $0.key.description > $1.key.description })
        )

        fixtureA.source = source(
            document: documentA,
            metadata: metadata(for: documentA, counter: 2),
            savedAt: date(2_000),
            nonce: fixtureA.source.activeSession.nonce
        )
        fixtureA.replica = try await makeReplica(
            context: fixtureA.context,
            sourceDocument: documentA
        )
        var fixtureB = fixtureA
        fixtureB.source = source(
            document: documentB,
            metadata: metadata(for: documentB, counter: 2),
            savedAt: date(2_000),
            nonce: fixtureA.source.activeSession.nonce
        )

        let left = try hydrate(fixtureA)
        let right = try hydrate(fixtureB)
        XCTAssertEqual(left.candidateDocument, right.candidateDocument)
        XCTAssertEqual(left.sourceEnvelope, right.sourceEnvelope)
        XCTAssertEqual(left.candidateEnvelope, right.candidateEnvelope)
    }

    func testRecomputesDerivedStateAndPreservesSourceOnlyProfileFields() async throws {
        var fixture = try await makeFixture()
        let abandoned = makeRecord(
            uuid: 30,
            offset: 0,
            score: 777,
            naturallyCompleted: true
        )
        var document = try settledDocument(
            base: fixture.source.envelope.document,
            records: [abandoned],
            confirmedGameplayRunIDs: []
        )
        document.player.settings.value.tutorialCompleted = true
        document.player.settings.modifiedAt = date(1_400)
        let playerID = GameCenterPlayerID("hydration-source-player")
        document.player.pendingGameCenter = PlayerScopedGameCenterQueueV1(
            pendingByPlayerID: [
                playerID: GameCenterPendingMaximaV1(
                    pendingHighScore: 777,
                    pendingAchievementPercents: [
                        LaunchAchievementID.firstRead: 100,
                    ]
                ),
            ],
            unboundPending: GameCenterPendingMaximaV1(
                pendingHighScore: 123
            )
        )
        fixture.source = source(
            document: document,
            metadata: metadata(for: document, counter: 20),
            savedAt: date(2_000),
            nonce: fixture.source.activeSession.nonce
        )
        fixture.replica = try await makeReplica(
            context: fixture.context,
            sourceDocument: document,
            settingsStamp: try stamp(1, "remote-device", date(1_000)),
            selectionStamp: try stamp(1, "remote-device", date(1_000))
        )

        let result = try hydrate(fixture)
        XCTAssertEqual(
            result.candidateDocument.player.createdAt,
            document.player.createdAt
        )
        XCTAssertTrue(
            result.candidateDocument.player.settings.value.tutorialCompleted
        )
        XCTAssertEqual(
            result.candidateDocument.player.completedRuns[abandoned.run.runID],
            abandoned
        )
        XCTAssertEqual(
            result.candidateDocument.player.pendingGameCenter
                .pending(for: playerID)?.pendingHighScore,
            777
        )
        XCTAssertEqual(
            result.candidateDocument.player.pendingGameCenter
                .pending(for: playerID)?
                .pendingAchievementPercents[LaunchAchievementID.firstRead],
            100
        )
        XCTAssertEqual(
            result.candidateDocument.player.pendingGameCenter.unboundPending
                .pendingHighScore,
            123
        )
        XCTAssertEqual(result.candidateDocument.player.career.completedRuns, 1)
        XCTAssertEqual(result.candidateDocument.player.career.highestScore, 777)
    }

    func testAchievementSeedRejectsDuplicateIDWithoutTrapping() throws {
        let duplicate = AchievementCatalog.launch[0]

        XCTAssertThrowsError(
            try CloudProfileAchievementSeed.progress(
                definitions: [duplicate, duplicate]
            )
        ) { error in
            XCTAssertEqual(
                error as? CloudProfileHydrationError,
                .duplicateAchievementDefinition(duplicate.id)
            )
        }
    }

    func testAchievementSeedContainsAllEightLaunchIDs() throws {
        let progress = try CloudProfileAchievementSeed.progress(
            definitions: AchievementCatalog.launch
        )

        XCTAssertEqual(progress.count, 8)
        XCTAssertEqual(Set(progress.keys), Set(AchievementCatalog.launch.map(\.id)))
        for definition in AchievementCatalog.launch {
            XCTAssertEqual(
                progress[definition.id],
                AchievementProgress(id: definition.id)
            )
        }
    }

    func testRealValidatorHydratesRedeemedRewardCycleAndAccountedRuns()
        async throws
    {
        var fixture = try await makeFixture()
        let records = (0 ..< PersistedEconomyRulesV1.rewardedAdRunThreshold)
            .map {
                makeRecord(
                    uuid: 300 + $0,
                    offset: TimeInterval($0 * 100)
                )
            }
        let remoteRuns = Dictionary(uniqueKeysWithValues: records.map {
            (
                $0.run.runID,
                cloudRun(
                    $0,
                    binding: binding(for: fixture.context),
                    observation: candidateObservation()
                )
            )
        })
        let offerID = RewardedAdState.offerID(for: 0)
        let providerTransactionID = AdProviderTransactionID(
            "hydration-redeemed-offer"
        )
        let rewardEntry = rewardedAdEntry(
            offerID: offerID,
            providerTransactionID: providerTransactionID
        )
        fixture.replica = try await makeReplica(
            context: fixture.context,
            sourceDocument: fixture.source.envelope.document,
            remoteRuns: remoteRuns,
            confirmedEntriesInOrder: [signingEntry()]
                + records.map(gameplayEntry)
                + [rewardEntry]
        )

        let result = try hydrate(fixture)
        let state = result.candidateDocument.player.rewardedAdState

        XCTAssertEqual(state.cycle, 1)
        XCTAssertEqual(state.validRunsSinceReward, 0)
        XCTAssertNil(state.eligibleOfferID)
        XCTAssertEqual(state.accountedRunIDs, Set(records.map(\.run.runID)))
        XCTAssertEqual(
            result.candidateDocument.player.ledger[rewardEntry.id],
            rewardEntry
        )
        XCTAssertFalse(
            result.candidateDocument.pendingLedgerEntryIDs
                .contains(rewardEntry.id)
        )
    }

    func testValidatedLedgerIndexRejectsDuplicateEmbeddedEntryIDWithoutTrapping()
        throws
    {
        let context = CloudProfileHydrationContextV1(
            cloudAccountID: CloudAccountID("fixture-cloud-account"),
            installingDeviceID: "install-device",
            candidateSavedAt: date(5_000)
        )
        let entry = signingEntry()
        let headID = CloudRecordID("economy-head-v3")

        func marker(
            operationID: String,
            revision: UInt64
        ) -> DurableEconomyCoordinator.CloudLedgerMarkerV2 {
            let mutation = DurableEconomyCoordinator.MutationBinding(
                cloudAccountID: context.cloudAccountID,
                accountBinding: context.derivedBindings.durableAccountBinding,
                profileAccountIdentity: context.derivedBindings
                    .playerAccountIdentity,
                profileSessionNonce: uuid(Int(revision)),
                sourceEconomyRevision: revision - 1,
                operationID: OperationID(operationID),
                kind: .pendingCredits
            )
            return DurableEconomyCoordinator.CloudLedgerMarkerV2(
                schemaVersion: DurableEconomyCoordinator.CloudLedgerMarkerV2
                    .schemaVersion,
                headRecordID: headID,
                record: DurableEconomyCoordinator.CloudLedgerRecord(
                    entry: entry,
                    binding: mutation
                ),
                eventPosition: DurableEconomyCoordinator
                    .CloudEconomyEventPosition(
                        cloudHeadRevision: revision,
                        batchIndex: 0
                    ),
                gameplayRewardObservation: nil,
                gameplayRewardResolution: nil
            )
        }

        XCTAssertThrowsError(
            try CloudProfileValidatedLedgerIndex.entries(
                from: [
                    marker(operationID: "duplicate-first", revision: 1),
                    marker(operationID: "duplicate-second", revision: 2),
                ]
            )
        ) { error in
            XCTAssertEqual(
                error as? CloudProfileHydrationError,
                .invalidValidatedReplica
            )
        }
    }
}

private extension CloudProfileHydratorTests {
    struct Fixture {
        var source: CloudProfileHydrationSourceV1
        var replica: ValidatedCloudProfileReplicaV1
        let context: CloudProfileHydrationContextV1
    }

    func makeFixture(
        playerRevision: UInt64 = 7,
        economyRevision: UInt64 = 3,
        installingDeviceID: String = "install-device"
    ) async throws -> Fixture {
        let context = CloudProfileHydrationContextV1(
            cloudAccountID: CloudAccountID("fixture-cloud-account"),
            installingDeviceID: installingDeviceID,
            candidateSavedAt: date(5_000)
        )
        var document = PlayerProfileFactory.makeDefault(
            profileID: context.derivedBindings.durableAccountBinding.profileID,
            accountIdentity: context.derivedBindings.playerAccountIdentity,
            deviceID: "local-device",
            createdAt: date(1_000)
        )
        document.player.revision = playerRevision
        document.economyRevision = economyRevision
        let metadata = metadata(for: document, counter: min(2, playerRevision))
        let source = source(
            document: document,
            metadata: metadata,
            savedAt: date(2_000),
            nonce: uuid(900)
        )
        return Fixture(
            source: source,
            replica: try await makeReplica(
                context: context,
                sourceDocument: document,
                settingsStamp: metadata.settingsStamp,
                selectionStamp: metadata.selectionStamp
            ),
            context: context
        )
    }

    func hydrate(_ fixture: Fixture) throws -> CloudProfileHydrationPlanV1 {
        try CloudProfileHydrator().hydrate(
            source: fixture.source,
            replica: fixture.replica,
            context: fixture.context
        )
    }

    func assertHydrationError(
        _ expected: CloudProfileHydrationError,
        fixture: Fixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try hydrate(fixture), file: file, line: line) {
            XCTAssertEqual(
                $0 as? CloudProfileHydrationError,
                expected,
                file: file,
                line: line
            )
        }
    }

    func source(
        document: LocalPlayerDocumentV1,
        metadata: CloudProfileLocalMergeMetadataV1?,
        savedAt: Date,
        nonce: UUID
    ) -> CloudProfileHydrationSourceV1 {
        var document = document
        if let metadata {
            document.player.settings.logicalCounter
                = metadata.settingsStamp.logicalCounter
            document.player.settings.modifiedAt
                = metadata.settingsStamp.modifiedAt
            document.player.settings.deviceID = metadata.settingsStamp.deviceID
            document.player.selection.logicalCounter
                = metadata.selectionStamp.logicalCounter
            document.player.selection.modifiedAt
                = metadata.selectionStamp.modifiedAt
            document.player.selection.deviceID = metadata.selectionStamp.deviceID
        }
        let exactEnvelopeBytes = try! PlayerProfileMigrator().encode(
            document,
            savedAt: savedAt
        )
        return CloudProfileHydrationSourceV1(
            exactEnvelopeBytes: exactEnvelopeBytes,
            activeSession: ProfileSessionToken(
                accountIdentity: document.accountIdentity,
                nonce: nonce,
                profileID: document.player.profileID
            )
        )
    }

    func settingsStamp(
        of document: LocalPlayerDocumentV1
    ) throws -> CloudProfileMergeStampV1 {
        try stamp(
            document.player.settings.logicalCounter,
            document.player.settings.deviceID,
            document.player.settings.modifiedAt
        )
    }

    func selectionStamp(
        of document: LocalPlayerDocumentV1
    ) throws -> CloudProfileMergeStampV1 {
        try stamp(
            document.player.selection.logicalCounter,
            document.player.selection.deviceID,
            document.player.selection.modifiedAt
        )
    }

    func metadata(
        for document: LocalPlayerDocumentV1,
        counter: UInt64
    ) -> CloudProfileLocalMergeMetadataV1 {
        CloudProfileLocalMergeMetadataV1(
            settingsStamp: try! stamp(
                counter,
                document.player.settings.deviceID,
                document.player.settings.modifiedAt
            ),
            selectionStamp: try! stamp(
                counter,
                document.player.selection.deviceID,
                document.player.selection.modifiedAt
            )
        )
    }

    func makeReplica(
        context: CloudProfileHydrationContextV1,
        sourceDocument: LocalPlayerDocumentV1,
        remoteRuns: [RunID: CloudProfileCompletedRunV1] = [:],
        settings: PlayerSettings? = nil,
        settingsStamp: CloudProfileMergeStampV1? = nil,
        selection: PlayerSelection? = nil,
        selectionStamp: CloudProfileMergeStampV1? = nil,
        confirmedEntriesInOrder: [CoinLedgerEntry] = [],
        unlockedItemIDs: [CatalogItemID] = []
    ) async throws -> ValidatedCloudProfileReplicaV1 {
        let profileConfiguration = try profileSchema()
        let economyConfiguration = try economySchema()
        let binding = binding(for: context)
        let resolvedSettingsStamp = try settingsStamp ?? stamp(
            2,
            sourceDocument.player.settings.deviceID,
            sourceDocument.player.settings.modifiedAt
        )
        let resolvedSelectionStamp = try selectionStamp ?? stamp(
            2,
            sourceDocument.player.selection.deviceID,
            sourceDocument.player.selection.modifiedAt
        )
        let headID = economyConfiguration.recordID
        let coordinator = try completeHistoryCoordinator(
            context: context,
            configuration: economyConfiguration
        )
        var rewarded = DurableEconomyCoordinator.CloudRewardedAdHeadV1.initial
        var markers: [
            LedgerEntryID: DurableEconomyCoordinator.CloudLedgerMarkerV2
        ] = [:]
        var offerMarkers: [
            RewardOfferID: DurableEconomyCoordinator.CloudRewardOfferMarkerV2
        ] = [:]

        for (offset, entry) in confirmedEntriesInOrder.enumerated() {
            let position = DurableEconomyCoordinator.CloudEconomyEventPosition(
                cloudHeadRevision: UInt64(offset + 1),
                batchIndex: 0
            )
            let kind: DurableEconomyCoordinator.MutationKind
            switch entry.reason {
            case .gameplay, .signingBonus: kind = .pendingCredits
            case .storeKit: kind = .storeKit
            case .catalogUnlock: kind = .catalogUnlock
            case .rewardedAd: kind = .rewardedAd
            }
            let mutation = DurableEconomyCoordinator.MutationBinding(
                cloudAccountID: context.cloudAccountID,
                accountBinding: context.derivedBindings.durableAccountBinding,
                profileAccountIdentity: context.derivedBindings
                    .playerAccountIdentity,
                profileSessionNonce: uuid(700 + offset),
                sourceEconomyRevision: UInt64(offset),
                operationID: OperationID("fixture-operation-\(offset)"),
                kind: kind
            )
            let observation: RewardedRunObservation?
            let resolution: DurableEconomyCoordinator.GameplayRewardResolution?
            if case let .gameplay(runID, _) = entry.reason {
                observation = remoteRuns[runID]?.rewardedRunObservation
                resolution = try observation.map {
                    try rewarded.resolveGameplay(observation: $0)
                }
            } else {
                observation = nil
                resolution = nil
            }
            let marker = DurableEconomyCoordinator.CloudLedgerMarkerV2(
                schemaVersion: DurableEconomyCoordinator.CloudLedgerMarkerV2
                    .schemaVersion,
                headRecordID: headID,
                record: DurableEconomyCoordinator.CloudLedgerRecord(
                    entry: entry,
                    binding: mutation
                ),
                eventPosition: position,
                gameplayRewardObservation: observation,
                gameplayRewardResolution: resolution
            )
            guard markers.updateValue(marker, forKey: entry.id) == nil else {
                throw CloudProfileHydratorFixtureError.duplicateLedgerEntry(
                    entry.id
                )
            }
            if case let .rewardedAd(offerID, providerTransactionID)
                = entry.reason {
                let redemption = DurableEconomyCoordinator.RewardRedemption(
                    offerID: offerID,
                    providerTransactionID: providerTransactionID,
                    ledgerEntryID: entry.id
                )
                try rewarded.redeem(offerID)
                let offerMarker = DurableEconomyCoordinator
                    .CloudRewardOfferMarkerV2(
                        schemaVersion: DurableEconomyCoordinator
                            .CloudRewardOfferMarkerV2.schemaVersion,
                        headRecordID: headID,
                        redemption: redemption,
                        binding: mutation,
                        eventPosition: position
                    )
                guard offerMarkers.updateValue(
                    offerMarker,
                    forKey: offerID
                ) == nil else {
                    throw CloudProfileHydratorFixtureError
                        .duplicateRewardOffer(offerID)
                }
            }
        }

        let ledgerAccumulator = try await coordinator.ledgerAccumulator(
            for: confirmedEntriesInOrder
        )
        let head = DurableEconomyCoordinator.CloudAccountHeadV3(
            schemaVersion: DurableEconomyCoordinator.CloudAccountHeadV3
                .schemaVersion,
            cloudAccountID: context.cloudAccountID,
            accountBinding: context.derivedBindings.durableAccountBinding,
            profileAccountIdentity: context.derivedBindings
                .playerAccountIdentity,
            revision: UInt64(confirmedEntriesInOrder.count),
            ledgerAccumulator: ledgerAccumulator,
            unlockedItemIDs: unlockedItemIDs.sorted {
                $0.rawValue < $1.rawValue
            },
            rewardedAd: rewarded
        )

        let runAccumulatorEntries = try remoteRuns.values.map { payload in
            CloudProfileRunAccumulatorEntryV1(
                logicalRecordID: profileConfiguration.runRecordID(
                    for: payload.runID
                ),
                canonicalPayload: try CloudProfileCanonicalPayload.encode(
                    payload
                )
            )
        }
        let runAccumulator = try CloudProfileRunAccumulatorV1.make(
            for: runAccumulatorEntries
        )
        let root = CloudProfileRootV1(
            binding: binding,
            economyHeadRecordID: headID,
            rootRevision: max(
                UInt64(1),
                runAccumulator.runCount,
                resolvedSettingsStamp.logicalCounter,
                resolvedSelectionStamp.logicalCounter
            ),
            runAccumulator: runAccumulator
        )
        let remoteSettings = CloudProfileSettingsV1(
            binding: binding,
            stamp: resolvedSettingsStamp,
            settings: settings ?? sourceDocument.player.settings.value
        )
        let remoteSelection = CloudProfileSelectionV1(
            binding: binding,
            stamp: resolvedSelectionStamp,
            selection: selection ?? sourceDocument.player.selection.value
        )

        var records: [CloudRecordID: CloudRecord] = [
            profileConfiguration.rootRecordID: try profileRecord(
                id: profileConfiguration.rootRecordID,
                type: profileConfiguration.rootRecordType,
                payload: root,
                configuration: profileConfiguration
            ),
            profileConfiguration.settingsRecordID: try profileRecord(
                id: profileConfiguration.settingsRecordID,
                type: profileConfiguration.settingsRecordType,
                payload: remoteSettings,
                configuration: profileConfiguration
            ),
            profileConfiguration.selectionRecordID: try profileRecord(
                id: profileConfiguration.selectionRecordID,
                type: profileConfiguration.selectionRecordType,
                payload: remoteSelection,
                configuration: profileConfiguration
            ),
            headID: try economyRecord(
                id: headID,
                payload: head,
                configuration: economyConfiguration
            ),
        ]
        for payload in remoteRuns.values {
            let recordID = profileConfiguration.runRecordID(for: payload.runID)
            records[recordID] = try profileRecord(
                id: recordID,
                type: profileConfiguration.runRecordType,
                payload: payload,
                configuration: profileConfiguration
            )
        }
        for marker in markers.values {
            let recordID = DurableEconomyCloudSchema.ledgerMarkerRecordID(
                for: marker.record.entry.id,
                headRecordID: headID
            )
            records[recordID] = try economyRecord(
                id: recordID,
                payload: marker,
                configuration: economyConfiguration
            )
        }
        for marker in offerMarkers.values {
            let recordID = DurableEconomyCloudSchema.rewardOfferMarkerRecordID(
                for: marker.redemption.offerID,
                headRecordID: headID
            )
            records[recordID] = try economyRecord(
                id: recordID,
                payload: marker,
                configuration: economyConfiguration
            )
        }

        let orderedRecordIDs = records.keys.sorted {
            $0.rawValue < $1.rawValue
        }
        let locators = Dictionary(uniqueKeysWithValues:
            orderedRecordIDs.enumerated().map { offset, recordID in
                (
                    recordID,
                    CloudProviderRecordLocator("fixture-provider-\(offset)")
                )
            }
        )
        let logicalIDs = Dictionary(uniqueKeysWithValues:
            locators.map { recordID, locator in (locator, recordID) }
        )
        let scope = CloudReplicaScopeFingerprint(
            rawValue: String(repeating: "a", count: 64)
        )
        let checkpoint = try CloudReplicaCheckpointV1(
            accountID: context.cloudAccountID,
            configurationScopeFingerprint: scope,
            generation: 1,
            finalCursor: CloudChangeCursor(Data("fixture-cursor".utf8)),
            recordsByLogicalID: records,
            providerLocatorByLogicalID: locators,
            logicalIDByProviderLocator: logicalIDs,
            tombstonesByProviderLocator: [:],
            replicaEpoch: uuid(699)
        )
        let validator = try CloudProfileReplicaValidator(
            configuration: profileConfiguration,
            economyConfiguration: economyConfiguration,
            expectedAccountID: context.cloudAccountID,
            expectedScopeFingerprint: scope,
            expectedBinding: binding,
            economyVerifier: CloudProfileCompleteEconomyHistoryVerifier(
                coordinator: coordinator
            )
        )
        switch try await validator.validate(checkpoint) {
        case let .initialized(replica):
            return replica
        case .uninitialized:
            throw CloudProfileHydratorFixtureError.uninitializedReplica
        }
    }

    func profileRecord<T: Encodable>(
        id: CloudRecordID,
        type: String,
        payload: T,
        configuration: CloudProfileSchemaConfiguration
    ) throws -> CloudRecord {
        CloudRecord(
            id: id,
            recordType: type,
            fields: [
                configuration.payloadFieldName:
                    try CloudProfileCanonicalPayload.encode(payload),
            ],
            changeTag: CloudChangeTag("fixture-tag-\(id.rawValue)")
        )
    }

    func economyRecord<T: Encodable>(
        id: CloudRecordID,
        payload: T,
        configuration: DurableEconomyCloudConfiguration
    ) throws -> CloudRecord {
        CloudRecord(
            id: id,
            recordType: configuration.recordType,
            fields: [
                configuration.payloadFieldName:
                    try DurableEconomyCloudSchema.makePayloadEncoder().encode(
                        payload
                    ),
            ],
            changeTag: CloudChangeTag("fixture-tag-\(id.rawValue)")
        )
    }

    func completeHistoryCoordinator(
        context: CloudProfileHydrationContextV1,
        configuration: DurableEconomyCloudConfiguration
    ) throws -> DurableEconomyCoordinator {
        let nonce = uuid(698)
        let profileSession = ProfileSessionToken(
            accountIdentity: context.derivedBindings.playerAccountIdentity,
            nonce: nonce,
            profileID: context.derivedBindings.durableAccountBinding.profileID
        )
        let sessionContext = try DurableEconomySessionContext(
            cloudAccountID: context.cloudAccountID,
            accountBinding: context.derivedBindings.durableAccountBinding,
            profileSession: profileSession,
            storeSession: StoreActiveSession(
                binding: context.derivedBindings.storeAccountBinding,
                nonce: nonce
            )
        )
        return DurableEconomyCoordinator(
            testingContext: sessionContext,
            sessionAuthority: DurableEconomySessionAuthority(
                context: sessionContext
            ),
            repository: CloudProfileHydratorUnusedRepository(),
            cloud: CloudProfileHydratorUnusedCloud(),
            configuration: configuration
        )
    }

    func economySchema() throws -> DurableEconomyCloudConfiguration {
        try DurableEconomyCloudConfiguration(
            recordID: CloudRecordID("economy-head-v3"),
            recordType: "EconomyV1",
            payloadFieldName: "payload"
        )
    }

    func settledDocument(
        base: LocalPlayerDocumentV1,
        records: [CompletedRunRecord],
        confirmedGameplayRunIDs: Set<RunID>
    ) throws -> LocalPlayerDocumentV1 {
        var document = base
        document.player.completedRuns = [:]
        document.player.ledger = [:]
        document.player.career = CareerStatistics()
        document.player.achievementProgress = Dictionary(
            uniqueKeysWithValues: AchievementCatalog.launch.map {
                ($0.id, AchievementProgress(id: $0.id))
            }
        )
        document.player.rewardedAdState = RewardedAdState()
        document.player.pendingGameCenter = PlayerScopedGameCenterQueueV1()
        document.pendingLedgerEntryIDs = []
        document.settlementReceipts = [:]
        document.rewardedRunObservations = [:]

        for record in records.sorted(by: {
            $0.recordedAt == $1.recordedAt
                ? $0.run.runID.description < $1.run.runID.description
                : $0.recordedAt < $1.recordedAt
        }) {
            let runID = record.run.runID
            let gameplayID = CoinLedgerID.gameplay(runID: runID)
            if record.rewardCoins > 0 {
                document.player.ledger[gameplayID] = gameplayEntry(record)
                if !confirmedGameplayRunIDs.contains(runID) {
                    document.pendingLedgerEntryIDs.insert(gameplayID)
                }
            }
            var signingID: LedgerEntryID?
            if CompletedRunValidator.isRewardEligible(record.run) {
                let id = CoinLedgerID.signingBonus(version: 1)
                if document.player.ledger[id] == nil {
                    document.player.ledger[id] = signingEntry()
                    if confirmedGameplayRunIDs.count != records.count {
                        document.pendingLedgerEntryIDs.insert(id)
                    }
                    signingID = id
                }
                let observation = candidateObservation()
                document.rewardedRunObservations?[runID] = observation
                _ = document.player.rewardedAdState.recordValidRun(runID)
            }
            document.player.career = try PersistedCareerAccumulatorV1.applying(
                record.run,
                to: document.player.career
            )
            let updates = AchievementEvaluator.evaluate(
                run: record.run,
                careerAfter: document.player.career,
                existing: document.player.achievementProgress,
                evaluatedAt: record.recordedAt
            )
            for update in updates {
                document.player.achievementProgress[update.current.id]
                    = update.current
                document.player.pendingGameCenter.enqueueUnboundAchievement(
                    update.current
                )
            }
            if CompletedRunValidator.isNaturallyCompleted(record.run) {
                document.player.pendingGameCenter.enqueueUnboundHighScore(
                    record.run.score
                )
            }
            document.player.completedRuns[runID] = record
            document.settlementReceipts[runID] = RunSettlementOutcome(
                record: record,
                gameplayRewardEntryID: record.rewardCoins > 0 ? gameplayID : nil,
                signingBonusEntryID: signingID,
                achievementUpdates: updates,
                rewardedOfferUnlocked: document.player.rewardedAdState
                    .eligibleOfferID,
                resultingPersonalBest: document.player.career.highestScore
            )
        }
        try PlayerProfileValidator.validate(document)
        return document
    }

    func makeRecord(
        uuid number: Int,
        offset: TimeInterval,
        score: Int = 5_000,
        naturallyCompleted: Bool = true
    ) -> CompletedRunRecord {
        let startedAt = date(10_000 + offset)
        let elapsed = naturallyCompleted ? 60_000 : 10_000
        let endedAt = startedAt.addingTimeInterval(
            TimeInterval(elapsed) / 1_000
        )
        let attempts = naturallyCompleted ? 3 : 1
        let touchdowns = naturallyCompleted ? 1 : 0
        let completions = 1
        let incompletions = attempts - touchdowns - completions
        let run = CompletedRun(
            configuration: RunConfiguration(
                runID: RunID(uuid(number)),
                randomSeed: UInt32(number),
                offenseTeamID: LaunchTeamID.novaCityComets,
                offenseJerseyID: LaunchCatalog.approved
                    .team(id: LaunchTeamID.novaCityComets)!.primaryJersey.id,
                defenseTeamID: LaunchTeamID.lumaCoastPrisms,
                defenseJerseyID: LaunchCatalog.approved
                    .team(id: LaunchTeamID.lumaCoastPrisms)!.primaryJersey.id,
                footballID: LaunchFootballID.standard,
                economyVersion: 1,
                startedAt: startedAt
            ),
            endedAt: endedAt,
            elapsedGameplayMilliseconds: elapsed,
            finishReason: naturallyCompleted ? .timerExpired : .abandoned,
            score: score,
            statistics: RunStatisticsSnapshot(
                attempts: attempts,
                completions: completions,
                touchdowns: touchdowns,
                incompletions: incompletions,
                interceptions: 0,
                longestTouchdownStreak: touchdowns
            ),
            completedLaneIDs: [.short],
            bonusTouchdownCount: 0
        )
        return CompletedRunRecord(
            run: run,
            recordedAt: endedAt.addingTimeInterval(1),
            rewardCoins: try! CompletedRunValidator.rewardCoins(for: run)
        )
    }

    func cloudRun(
        _ record: CompletedRunRecord,
        binding: CloudProfileBindingV1,
        observation: RewardedRunObservation?
    ) -> CloudProfileCompletedRunV1 {
        CloudProfileCompletedRunV1(
            binding: binding,
            record: record,
            rewardedRunObservation: observation
        )
    }

    func gameplayEntry(_ record: CompletedRunRecord) -> CoinLedgerEntry {
        CoinLedgerEntry(
            id: CoinLedgerID.gameplay(runID: record.run.runID),
            delta: record.rewardCoins,
            reason: .gameplay(
                runID: record.run.runID,
                economyVersion: record.run.configuration.economyVersion
            ),
            createdAt: record.recordedAt
        )
    }

    func signingEntry() -> CoinLedgerEntry {
        CoinLedgerEntry(
            id: CoinLedgerID.signingBonus(version: 1),
            delta: PersistedEconomyRulesV1.signingBonusCoins,
            reason: .signingBonus(version: 1),
            createdAt: PersistedEconomyRulesV1.signingBonusLedgerCreatedAt
        )
    }

    func rewardedAdEntry(
        offerID: RewardOfferID,
        providerTransactionID: AdProviderTransactionID
    ) -> CoinLedgerEntry {
        CoinLedgerEntry(
            id: CoinLedgerID.rewardedAd(
                providerTransactionID: providerTransactionID
            ),
            delta: PersistedEconomyRulesV1.rewardedAdCoins,
            reason: .rewardedAd(
                offerID: offerID,
                providerTransactionID: providerTransactionID
            ),
            createdAt: date(20_000)
        )
    }

    func candidateObservation() -> RewardedRunObservation {
        RewardedRunObservation(observedCycle: 0, disposition: .candidate)
    }

    func binding(
        for context: CloudProfileHydrationContextV1
    ) -> CloudProfileBindingV1 {
        CloudProfileBindingV1(
            cloudAccountID: context.cloudAccountID,
            accountBinding: context.derivedBindings.durableAccountBinding,
            profileAccountIdentity: context.derivedBindings.playerAccountIdentity
        )
    }

    func profileSchema() throws -> CloudProfileSchemaConfiguration {
        try CloudProfileSchemaConfiguration(
            rootRecordType: "ProfileRootV1",
            settingsRecordType: "ProfileSettingsV1",
            selectionRecordType: "ProfileSelectionV1",
            runRecordType: "ProfileRunV1",
            payloadFieldName: "payload"
        )
    }

    func stamp(
        _ counter: UInt64,
        _ deviceID: String,
        _ modifiedAt: Date
    ) throws -> CloudProfileMergeStampV1 {
        try CloudProfileMergeStampV1(
            logicalCounter: counter,
            deviceID: deviceID,
            modifiedAt: modifiedAt
        )
    }

    func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    func uuid(_ number: Int) -> UUID {
        UUID(
            uuidString: String(
                format: "00000000-0000-0000-0000-%012d",
                number
            )
        )!
    }
}

private enum CloudProfileHydratorFixtureError: Error, Equatable, Sendable {
    case duplicateLedgerEntry(LedgerEntryID)
    case duplicateRewardOffer(RewardOfferID)
    case uninitializedReplica
    case unusedDependency
}

private struct CloudProfileHydratorUnusedRepository:
    DurableEconomyLocalPersisting
{
    func durableEconomySnapshot() async throws -> LocalPlayerProfileSnapshot {
        throw CloudProfileHydratorFixtureError.unusedDependency
    }

    func durableConfirmPendingCredits(
        _: Set<LedgerEntryID>,
        session _: ProfileSessionToken,
        confirmation _: DurableEconomyConfirmation,
        savedAt _: Date
    ) async throws -> LocalPlayerProfileSnapshot {
        throw CloudProfileHydratorFixtureError.unusedDependency
    }

    func durableRecordConfirmedCredit(
        _: CoinLedgerEntry,
        session _: ProfileSessionToken,
        confirmation _: DurableEconomyConfirmation,
        savedAt _: Date
    ) async throws -> LocalPlayerProfileSnapshot {
        throw CloudProfileHydratorFixtureError.unusedDependency
    }

    func durablePrepareUnlock(
        itemID _: CatalogItemID,
        operationID _: OperationID,
        session _: ProfileSessionToken
    ) async throws -> DurableCatalogUnlockRequest {
        throw CloudProfileHydratorFixtureError.unusedDependency
    }

    func durableApplyUnlock(
        using _: DurableCatalogUnlockReceipt,
        session _: ProfileSessionToken,
        at _: Date
    ) async throws -> CatalogUnlockOutcome {
        throw CloudProfileHydratorFixtureError.unusedDependency
    }

    func durableSettleRewardedAd(
        using _: DurableRewardedAdReceipt,
        session _: ProfileSessionToken,
        savedAt _: Date
    ) async throws -> RewardedAdSettlementOutcome {
        throw CloudProfileHydratorFixtureError.unusedDependency
    }
}

private struct CloudProfileHydratorUnusedCloud: CloudSyncTransport {
    func accountState() async -> CloudAccountState { .unknown }

    func records(
        accountID _: CloudAccountID,
        ids _: [CloudRecordID]
    ) async throws -> [CloudRecord] {
        throw CloudProfileHydratorFixtureError.unusedDependency
    }

    func commitAtomically(
        _: CloudAtomicWriteRequest
    ) async throws -> CloudAtomicWriteReceipt {
        throw CloudProfileHydratorFixtureError.unusedDependency
    }
}

private extension CloudProfileHydrationSourceV1 {
    var envelope: PlayerProfileEnvelopeV4 {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try! decoder.decode(
            PlayerProfileEnvelopeV4.self,
            from: exactEnvelopeBytes
        )
    }
}

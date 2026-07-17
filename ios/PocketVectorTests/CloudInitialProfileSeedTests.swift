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
        let seed = try CloudInitialProfileSeedBuilderV1().makeSeed(
            from: makeArtifact(document)
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
        let seed = try CloudInitialProfileSeedBuilderV1().makeSeed(
            from: makeArtifact(document)
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

        let seed = try CloudInitialProfileSeedBuilderV1().makeSeed(
            from: makeArtifact(document)
        )
        guard case let .requiresOwnerPolicy(reasons) = seed.debugEligibility else {
            return XCTFail("Expected owner policy")
        }
        XCTAssertTrue(reasons.contains(.storeKitHistory(storeKitID)))
        XCTAssertTrue(reasons.contains(.rewardedAdHistory(rewardedID)))
        XCTAssertTrue(reasons.contains(.confirmedLedgerEntry(storeKitID)))
        XCTAssertTrue(reasons.contains(.confirmedLedgerEntry(rewardedID)))
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

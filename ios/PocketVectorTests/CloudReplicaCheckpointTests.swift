import CryptoKit
import Foundation
import XCTest

@testable import PocketVector

final class CloudReplicaCheckpointTests: XCTestCase, @unchecked Sendable {
    private let accountA = CloudAccountID("opaque-account-a")
    private let accountB = CloudAccountID("opaque-account-b")
    private let epoch = UUID(uuidString: "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee")!

    func testMultiPageCompletionIsTheOnlyCheckpointBoundary() throws {
        let fingerprint = scopeFingerprint()
        var accumulator = CloudReplicaStagedAccumulator(
            accountID: accountA,
            configurationScopeFingerprint: fingerprint,
            replicaEpoch: epoch
        )
        let first = page(
            accountID: accountA,
            modifications: [discovered(id: "profile", locator: "provider-profile", value: "one")],
            cursor: "cursor-1",
            moreComing: true
        )
        let final = page(
            accountID: accountA,
            modifications: [discovered(id: "ledger", locator: "provider-ledger", value: "two")],
            requestedAfter: "cursor-1",
            cursor: "cursor-2",
            moreComing: false
        )

        XCTAssertNil(try accumulator.apply(first))
        XCTAssertNil(try accumulator.apply(first), "Exact intermediate replay must be idempotent")
        let checkpoint = try XCTUnwrap(accumulator.apply(final))

        XCTAssertEqual(checkpoint.accountID, accountA)
        XCTAssertEqual(checkpoint.configurationScopeFingerprint, fingerprint)
        XCTAssertEqual(checkpoint.generation, 1)
        XCTAssertEqual(checkpoint.finalCursor, cursor("cursor-2"))
        XCTAssertEqual(checkpoint.replicaEpoch, epoch)
        XCTAssertEqual(Set(checkpoint.recordsByLogicalID.keys), ["profile", "ledger"].cloudIDs)
        XCTAssertEqual(
            checkpoint.providerLocatorByLogicalID[CloudRecordID("profile")],
            CloudProviderRecordLocator("provider-profile")
        )
        XCTAssertEqual(
            checkpoint.logicalIDByProviderLocator[
                CloudProviderRecordLocator("provider-ledger")
            ],
            CloudRecordID("ledger")
        )

        let encoded = try JSONEncoder().encode(checkpoint)
        XCTAssertEqual(try JSONDecoder().decode(CloudReplicaCheckpointV1.self, from: encoded), checkpoint)
    }

    func testFinalReplayIsIdempotentAndCursorContentCollisionIsRejected() throws {
        var accumulator = emptyAccumulator()
        let final = page(
            accountID: accountA,
            modifications: [discovered(id: "profile", locator: "provider-profile")],
            cursor: "final-cursor",
            moreComing: false
        )

        let firstResult = try XCTUnwrap(accumulator.apply(final))
        XCTAssertEqual(try accumulator.apply(final), firstResult)

        let collision = page(
            accountID: accountA,
            modifications: [discovered(id: "ledger", locator: "provider-ledger")],
            cursor: "final-cursor",
            moreComing: false
        )
        XCTAssertThrowsError(try accumulator.apply(collision)) { error in
            XCTAssertEqual(error as? CloudReplicaAccumulatorError, .cursorCollision)
        }

        let later = page(
            accountID: accountA,
            cursor: "later-cursor",
            moreComing: false
        )
        XCTAssertThrowsError(try accumulator.apply(later)) { error in
            XCTAssertEqual(error as? CloudReplicaAccumulatorError, .alreadyFinalized)
        }
    }

    func testRejectedPageNeverPartiallyAdvancesCandidateOrCursor() throws {
        var accumulator = emptyAccumulator()
        XCTAssertNil(
            try accumulator.apply(
                page(
                    accountID: accountA,
                    modifications: [discovered(id: "profile", locator: "provider-profile")],
                    cursor: "cursor-1",
                    moreComing: true
                )
            )
        )

        let invalid = page(
            accountID: accountA,
            modifications: [
                discovered(id: "ledger", locator: "provider-ledger-1"),
                discovered(id: "ledger", locator: "provider-ledger-2"),
            ],
            requestedAfter: "cursor-1",
            cursor: "cursor-2",
            moreComing: false
        )
        XCTAssertThrowsError(try accumulator.apply(invalid)) { error in
            XCTAssertEqual(error as? CloudReplicaAccumulatorError, .duplicateLogicalRecord)
        }

        let repaired = page(
            accountID: accountA,
            modifications: [discovered(id: "ledger", locator: "provider-ledger-1")],
            requestedAfter: "cursor-1",
            cursor: "cursor-2",
            moreComing: false
        )
        let checkpoint = try XCTUnwrap(accumulator.apply(repaired))
        XCTAssertEqual(Set(checkpoint.recordsByLogicalID.keys), ["profile", "ledger"].cloudIDs)
    }

    func testDeletionRemovesIndexesAndRetainsMappedAndUnmappedTombstones() throws {
        let seeded = try checkpoint(
            modifications: [discovered(id: "profile", locator: "provider-profile")]
        )
        var accumulator = try CloudReplicaStagedAccumulator(
            accountID: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            checkpoint: seeded
        )
        let deleted = try XCTUnwrap(
            accumulator.apply(
                page(
                    accountID: accountA,
                    deletions: [
                        CloudDeletedRecord(
                            locator: CloudProviderRecordLocator("provider-profile"),
                            recordType: "PlayerRecord"
                        ),
                        CloudDeletedRecord(
                            locator: CloudProviderRecordLocator("provider-unknown"),
                            recordType: "OperationMarker"
                        ),
                    ],
                    requestedAfter: "seed-cursor",
                    cursor: "delete-cursor",
                    moreComing: false
                )
            )
        )

        XCTAssertTrue(deleted.recordsByLogicalID.isEmpty)
        XCTAssertTrue(deleted.providerLocatorByLogicalID.isEmpty)
        XCTAssertTrue(deleted.logicalIDByProviderLocator.isEmpty)
        XCTAssertEqual(
            deleted.tombstonesByProviderLocator[
                CloudProviderRecordLocator("provider-profile")
            ]?.logicalRecordID,
            CloudRecordID("profile")
        )
        XCTAssertNil(
            deleted.tombstonesByProviderLocator[
                CloudProviderRecordLocator("provider-unknown")
            ]?.logicalRecordID
        )

        var recreation = try CloudReplicaStagedAccumulator(
            accountID: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            checkpoint: deleted
        )
        let recreated = try XCTUnwrap(
            recreation.apply(
                page(
                    accountID: accountA,
                    modifications: [discovered(id: "profile", locator: "provider-profile")],
                    requestedAfter: "delete-cursor",
                    cursor: "recreate-cursor",
                    moreComing: false
                )
            )
        )
        XCTAssertNotNil(recreated.recordsByLogicalID[CloudRecordID("profile")])
        XCTAssertNil(
            recreated.tombstonesByProviderLocator[
                CloudProviderRecordLocator("provider-profile")
            ]
        )
    }

    func testDuplicateOverlapAndRemapPagesAreRejected() throws {
        try assertPageError(
            page(
                accountID: accountA,
                modifications: [
                    discovered(id: "one", locator: "locator-one"),
                    discovered(id: "one", locator: "locator-two"),
                ],
                cursor: "duplicate-logical",
                moreComing: false
            ),
            equals: .duplicateLogicalRecord
        )
        try assertPageError(
            page(
                accountID: accountA,
                modifications: [
                    discovered(id: "one", locator: "shared-locator"),
                    discovered(id: "two", locator: "shared-locator"),
                ],
                cursor: "duplicate-locator",
                moreComing: false
            ),
            equals: .duplicateProviderLocator
        )
        try assertPageError(
            page(
                accountID: accountA,
                deletions: [
                    CloudDeletedRecord(
                        locator: CloudProviderRecordLocator("shared-locator"),
                        recordType: "PlayerRecord"
                    ),
                    CloudDeletedRecord(
                        locator: CloudProviderRecordLocator("shared-locator"),
                        recordType: "PlayerRecord"
                    ),
                ],
                cursor: "duplicate-deletion",
                moreComing: false
            ),
            equals: .duplicateDeletion
        )
        try assertPageError(
            page(
                accountID: accountA,
                modifications: [discovered(id: "one", locator: "shared-locator")],
                deletions: [
                    CloudDeletedRecord(
                        locator: CloudProviderRecordLocator("shared-locator"),
                        recordType: "PlayerRecord"
                    ),
                ],
                cursor: "overlap",
                moreComing: false
            ),
            equals: .modificationDeletionOverlap
        )

        let seeded = try checkpoint(
            modifications: [discovered(id: "one", locator: "locator-one")]
        )
        var logicalRemap = try accumulator(from: seeded)
        XCTAssertThrowsError(
            try logicalRemap.apply(
                page(
                    accountID: accountA,
                    modifications: [discovered(id: "one", locator: "locator-two")],
                    requestedAfter: "seed-cursor",
                    cursor: "logical-remap",
                    moreComing: false
                )
            )
        ) { error in
            XCTAssertEqual(error as? CloudReplicaAccumulatorError, .logicalRecordRemap)
        }

        var locatorRemap = try accumulator(from: seeded)
        XCTAssertThrowsError(
            try locatorRemap.apply(
                page(
                    accountID: accountA,
                    modifications: [discovered(id: "two", locator: "locator-one")],
                    requestedAfter: "seed-cursor",
                    cursor: "locator-remap",
                    moreComing: false
                )
            )
        ) { error in
            XCTAssertEqual(error as? CloudReplicaAccumulatorError, .providerLocatorRemap)
        }
    }

    func testWrongAccountAndScopeCannotSeedOrAdvanceAccumulator() throws {
        let seeded = try checkpoint(
            modifications: [discovered(id: "profile", locator: "provider-profile")]
        )
        XCTAssertThrowsError(
            try CloudReplicaStagedAccumulator(
                accountID: accountB,
                configurationScopeFingerprint: scopeFingerprint(),
                checkpoint: seeded
            )
        ) { error in
            XCTAssertEqual(error as? CloudReplicaAccumulatorError, .accountMismatch)
        }

        XCTAssertThrowsError(
            try CloudReplicaStagedAccumulator(
                accountID: accountA,
                configurationScopeFingerprint: alternateScopeFingerprint(),
                checkpoint: seeded
            )
        ) { error in
            XCTAssertEqual(error as? CloudReplicaAccumulatorError, .scopeMismatch)
        }

        var accumulator = emptyAccumulator()
        XCTAssertThrowsError(
            try accumulator.apply(
                page(accountID: accountB, cursor: "wrong-account", moreComing: false)
            )
        ) { error in
            XCTAssertEqual(error as? CloudReplicaAccumulatorError, .accountMismatch)
        }
    }

    func testFetchedPagesRequireExactPredecessorAndFullScope() throws {
        var skippedBootstrap = emptyAccumulator()
        XCTAssertThrowsError(
            try skippedBootstrap.apply(
                page(
                    accountID: accountA,
                    requestedAfter: "unseen-cursor",
                    cursor: "page-two",
                    moreComing: false
                )
            )
        ) { error in
            XCTAssertEqual(error as? CloudReplicaAccumulatorError, .predecessorCursorMismatch)
        }

        var crossScope = emptyAccumulator()
        XCTAssertThrowsError(
            try crossScope.apply(
                page(
                    accountID: accountA,
                    scope: alternateScopeFingerprint(),
                    cursor: "wrong-scope",
                    moreComing: false
                )
            )
        ) { error in
            XCTAssertEqual(error as? CloudReplicaAccumulatorError, .scopeMismatch)
        }

        var incremental = emptyAccumulator()
        XCTAssertNil(
            try incremental.apply(
                page(accountID: accountA, cursor: "cursor-1", moreComing: true)
            )
        )
        for stalePredecessor in [nil, "older-cursor"] as [String?] {
            XCTAssertThrowsError(
                try incremental.apply(
                    page(
                        accountID: accountA,
                        requestedAfter: stalePredecessor,
                        cursor: "cursor-2",
                        moreComing: false
                    )
                )
            ) { error in
                XCTAssertEqual(
                    error as? CloudReplicaAccumulatorError,
                    .predecessorCursorMismatch
                )
            }
        }
        XCTAssertNotNil(
            try incremental.apply(
                page(
                    accountID: accountA,
                    requestedAfter: "cursor-1",
                    cursor: "cursor-2",
                    moreComing: false
                )
            )
        )
    }

    func testCheckpointGenerationAdvancesAndOverflowIsRejected() throws {
        let first = try checkpoint(modifications: [])
        var incremental = try accumulator(from: first)
        let second = try XCTUnwrap(
            incremental.apply(
                page(
                    accountID: accountA,
                    requestedAfter: "seed-cursor",
                    cursor: "next-cursor",
                    moreComing: false
                )
            )
        )
        XCTAssertEqual(first.generation, 1)
        XCTAssertEqual(second.generation, 2)

        let maximum = try CloudReplicaCheckpointV1(
            accountID: first.accountID,
            configurationScopeFingerprint: first.configurationScopeFingerprint,
            generation: UInt64.max,
            finalCursor: first.finalCursor,
            recordsByLogicalID: first.recordsByLogicalID,
            providerLocatorByLogicalID: first.providerLocatorByLogicalID,
            logicalIDByProviderLocator: first.logicalIDByProviderLocator,
            tombstonesByProviderLocator: first.tombstonesByProviderLocator,
            replicaEpoch: first.replicaEpoch
        )
        var overflow = try accumulator(from: maximum)
        XCTAssertThrowsError(
            try overflow.apply(
                page(
                    accountID: accountA,
                    requestedAfter: "seed-cursor",
                    cursor: "overflow-cursor",
                    moreComing: false
                )
            )
        ) { error in
            XCTAssertEqual(error as? CloudReplicaAccumulatorError, .generationOverflow)
        }
    }

    func testLiveRecordTypeChangeIsRejected() throws {
        let seeded = try checkpoint(
            modifications: [discovered(id: "profile", locator: "provider-profile")]
        )
        var accumulator = try self.accumulator(from: seeded)
        XCTAssertThrowsError(
            try accumulator.apply(
                page(
                    accountID: accountA,
                    modifications: [
                        discovered(
                            id: "profile",
                            locator: "provider-profile",
                            recordType: "DifferentRecordType"
                        ),
                    ],
                    requestedAfter: "seed-cursor",
                    cursor: "type-change",
                    moreComing: false
                )
            )
        ) { error in
            XCTAssertEqual(error as? CloudReplicaAccumulatorError, .recordTypeConflict)
        }
    }

    func testAccumulatorResourceLimitsFailBeforeCandidateCommit() throws {
        var pageCount = emptyAccumulator(limits: testLimits(maxPageChangeCount: 1))
        XCTAssertThrowsError(
            try pageCount.apply(
                page(
                    accountID: accountA,
                    modifications: [
                        discovered(id: "one", locator: "one"),
                        discovered(id: "two", locator: "two"),
                    ],
                    cursor: "page-limit",
                    moreComing: false
                )
            )
        ) { error in
            XCTAssertEqual(error as? CloudReplicaAccumulatorError, .pageLimitExceeded)
        }

        var records = emptyAccumulator(limits: testLimits(maxRecordCount: 1))
        XCTAssertThrowsError(
            try records.apply(
                page(
                    accountID: accountA,
                    modifications: [
                        discovered(id: "one", locator: "one"),
                        discovered(id: "two", locator: "two"),
                    ],
                    cursor: "record-limit",
                    moreComing: false
                )
            )
        ) { error in
            XCTAssertEqual(error as? CloudReplicaAccumulatorError, .recordLimitExceeded)
        }

        var tombstones = emptyAccumulator(limits: testLimits(maxTombstoneCount: 1))
        XCTAssertThrowsError(
            try tombstones.apply(
                page(
                    accountID: accountA,
                    deletions: [
                        CloudDeletedRecord(
                            locator: CloudProviderRecordLocator("one"),
                            recordType: "PlayerRecord"
                        ),
                        CloudDeletedRecord(
                            locator: CloudProviderRecordLocator("two"),
                            recordType: "PlayerRecord"
                        ),
                    ],
                    cursor: "tombstone-limit",
                    moreComing: false
                )
            )
        ) { error in
            XCTAssertEqual(error as? CloudReplicaAccumulatorError, .tombstoneLimitExceeded)
        }

        var recordBytes = emptyAccumulator(limits: testLimits(maxBytesPerRecord: 8))
        XCTAssertThrowsError(
            try recordBytes.apply(
                page(
                    accountID: accountA,
                    modifications: [
                        discovered(id: "one", locator: "one", value: "too-large"),
                    ],
                    cursor: "record-bytes",
                    moreComing: false
                )
            )
        ) { error in
            XCTAssertEqual(error as? CloudReplicaAccumulatorError, .recordByteLimitExceeded)
        }

        var totalBytes = emptyAccumulator(limits: testLimits(maxTotalBytes: 32))
        XCTAssertThrowsError(
            try totalBytes.apply(
                page(
                    accountID: accountA,
                    modifications: [discovered(id: "one", locator: "one")],
                    cursor: "total-bytes",
                    moreComing: false
                )
            )
        ) { error in
            XCTAssertEqual(error as? CloudReplicaAccumulatorError, .totalByteLimitExceeded)
        }

        var pages = emptyAccumulator(limits: testLimits(maxPagesPerSync: 1))
        let firstLimitedPage = page(accountID: accountA, cursor: "one", moreComing: true)
        XCTAssertNil(try pages.apply(firstLimitedPage))
        XCTAssertNil(try pages.apply(firstLimitedPage), "Exact replay must not consume another page")
        XCTAssertThrowsError(
            try pages.apply(
                page(
                    accountID: accountA,
                    requestedAfter: "one",
                    cursor: "two",
                    moreComing: false
                )
            )
        ) { error in
            XCTAssertEqual(error as? CloudReplicaAccumulatorError, .pageLimitExceeded)
        }
    }

    func testCumulativePageDigestMetadataSharesTheTotalByteBudget() throws {
        let limits = testLimits(
            maxPagesPerSync: 10,
            maxTotalBytes: 80,
            maxCursorBytes: 80
        )
        var accumulator = emptyAccumulator(limits: limits)
        let first = page(
            accountID: accountA,
            cursor: "1234567890",
            moreComing: true
        )
        XCTAssertNil(try accumulator.apply(first))
        XCTAssertNil(
            try accumulator.apply(first),
            "Exact replay must not retain or charge a second digest entry"
        )

        XCTAssertThrowsError(
            try accumulator.apply(
                page(
                    accountID: accountA,
                    requestedAfter: "1234567890",
                    cursor: "abcdefghij",
                    moreComing: true
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? CloudReplicaAccumulatorError,
                .totalByteLimitExceeded
            )
        }

        XCTAssertNil(
            try accumulator.apply(first),
            "A rejected page must not consume retained metadata budget"
        )
        let completed = try accumulator.apply(
            page(
                accountID: accountA,
                requestedAfter: "1234567890",
                cursor: "z",
                moreComing: false
            )
        )
        XCTAssertNotNil(completed)
    }

    func testCheckpointStrictlyValidatesIndexesTombstonesAndFingerprintDecoding() throws {
        let record = cloudRecord(id: "profile")
        XCTAssertThrowsError(
            try CloudReplicaCheckpointV1(
                accountID: accountA,
                configurationScopeFingerprint: scopeFingerprint(),
                generation: 1,
                finalCursor: cursor("cursor"),
                recordsByLogicalID: [CloudRecordID("wrong-key"): record],
                providerLocatorByLogicalID: [
                    CloudRecordID("wrong-key"): CloudProviderRecordLocator("locator")
                ],
                logicalIDByProviderLocator: [
                    CloudProviderRecordLocator("locator"): CloudRecordID("wrong-key")
                ],
                tombstonesByProviderLocator: [:],
                replicaEpoch: epoch
            )
        ) { error in
            XCTAssertEqual(
                error as? CloudReplicaCheckpointValidationError,
                .recordKeyMismatch
            )
        }

        XCTAssertThrowsError(
            try CloudReplicaCheckpointV1(
                accountID: accountA,
                configurationScopeFingerprint: scopeFingerprint(),
                generation: 1,
                finalCursor: cursor("cursor"),
                recordsByLogicalID: [record.id: record],
                providerLocatorByLogicalID: [:],
                logicalIDByProviderLocator: [:],
                tombstonesByProviderLocator: [:],
                replicaEpoch: epoch
            )
        ) { error in
            XCTAssertEqual(
                error as? CloudReplicaCheckpointValidationError,
                .incompleteLocatorIndex
            )
        }

        XCTAssertThrowsError(
            try JSONDecoder().decode(
                CloudReplicaScopeFingerprint.self,
                from: Data("\"\"".utf8)
            )
        )
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                CloudReplicaScopeFingerprint.self,
                from: Data("\"ABCDEF\"".utf8)
            )
        )
    }

    func testScopeFingerprintIsStableAndSensitiveToEveryConfigurationInput() throws {
        let base = try productionConfiguration()
        let fingerprint = CloudReplicaScopeFingerprint.make(for: base)

        XCTAssertEqual(fingerprint, CloudReplicaScopeFingerprint.make(for: base))
        XCTAssertEqual(
            fingerprint.rawValue,
            "75ab98aa0642a71968b2e793e5acbf466b72db447a8e80e92b5566fd592eb95c"
        )
        XCTAssertEqual(fingerprint.rawValue.count, 64)
        XCTAssertEqual(
            CloudReplicaScopeFingerprint.orderedMaterial(for: base),
            [
                CloudReplicaScopeFingerprint.scopeDomain,
                "transport", String(base.transport.fingerprintMaterial.count),
            ]
                + base.transport.fingerprintMaterial
                + ["economy", String(base.economy.fingerprintMaterial.count)]
                + base.economy.fingerprintMaterial
                + ["profile", String(base.profile.fingerprintMaterial.count)]
                + base.profile.fingerprintMaterial
        )

        let variants = [
            try productionConfiguration(containerIdentifier: "iCloud.com.pocketvector.other"),
            try productionConfiguration(zoneName: "PlayerDataOther"),
            try productionConfiguration(payloadFieldName: "payloadOther"),
            try productionConfiguration(operationRecordType: "OperationMarkerOther"),
            try productionConfiguration(accountIdentifierNamespace: "account-v2"),
            try productionConfiguration(recordNameNamespace: "record-v2"),
            try productionConfiguration(economyRecordID: "economy-head-other"),
            try productionConfiguration(economyRecordType: "EconomyRecordOther"),
            try productionConfiguration(economyPayloadFieldName: "economyPayloadOther"),
            try productionConfiguration(profileRootRecordType: "ProfileRootOther"),
            try productionConfiguration(
                profileSettingsRecordType: "ProfileSettingsOther"
            ),
            try productionConfiguration(
                profileSelectionRecordType: "ProfileSelectionOther"
            ),
            try productionConfiguration(profileRunRecordType: "ProfileRunOther"),
            try productionConfiguration(profilePayloadFieldName: "profilePayloadOther"),
        ]
        let variantFingerprints = variants.map(CloudReplicaScopeFingerprint.make(for:))
        XCTAssertEqual(Set(variantFingerprints).count, variants.count)
        XCTAssertTrue(variantFingerprints.allSatisfy { $0 != fingerprint })

        let operationalVariant = try productionConfiguration(conflictRetryLimit: 99)
        XCTAssertNotEqual(base.economy, operationalVariant.economy)
        XCTAssertEqual(
            fingerprint,
            CloudReplicaScopeFingerprint.make(for: operationalVariant)
        )
    }

    func testCatalogAndAchievementSemanticMaterialIsNormalizedAndSensitive()
        throws
    {
        let catalog = LaunchCatalog.approved
        let reorderedCatalog = LaunchCatalog(
            teams: Array(catalog.teams.reversed()),
            footballs: Array(catalog.footballs.reversed()),
            unlockableItems: Array(catalog.unlockableItems.reversed())
        )
        XCTAssertEqual(
            catalog.persistedFingerprintMaterial,
            reorderedCatalog.persistedFingerprintMaterial
        )

        var repricedItems = catalog.unlockableItems
        let originalItem = try XCTUnwrap(repricedItems.first)
        repricedItems[0] = CatalogItemDescriptor(
            id: originalItem.id,
            displayName: originalItem.displayName,
            kind: originalItem.kind,
            price: originalItem.price + 1
        )
        XCTAssertNotEqual(
            catalog.persistedFingerprintMaterial,
            LaunchCatalog(
                teams: catalog.teams,
                footballs: catalog.footballs,
                unlockableItems: repricedItems
            ).persistedFingerprintMaterial
        )

        let achievements = AchievementCatalog.launch
        XCTAssertEqual(
            AchievementCatalog.persistedFingerprintMaterial(for: achievements),
            AchievementCatalog.persistedFingerprintMaterial(
                for: Array(achievements.reversed())
            )
        )
        var changedPoints = achievements
        let first = try XCTUnwrap(changedPoints.first)
        changedPoints[0] = AchievementDefinition(
            id: first.id,
            displayName: first.displayName,
            detail: first.detail,
            points: first.points + 1,
            rule: first.rule
        )
        XCTAssertNotEqual(
            AchievementCatalog.persistedFingerprintMaterial(for: achievements),
            AchievementCatalog.persistedFingerprintMaterial(for: changedPoints)
        )

        var changedRule = achievements
        changedRule[0] = AchievementDefinition(
            id: first.id,
            displayName: first.displayName,
            detail: first.detail,
            points: first.points,
            rule: .careerSuccessfulPasses(2)
        )
        XCTAssertNotEqual(
            AchievementCatalog.persistedFingerprintMaterial(for: achievements),
            AchievementCatalog.persistedFingerprintMaterial(for: changedRule)
        )

        XCTAssertEqual(
            CloudProfileDigest.hex(
                CloudProfileDigest.sha256(
                    components: catalog.persistedFingerprintMaterial
                )
            ),
            "74420bf94ecb3707676b6a784a9a1df36f784faac8b83f792b8cabee786d024b"
        )
        XCTAssertEqual(
            CloudProfileDigest.hex(
                CloudProfileDigest.sha256(
                    components: AchievementCatalog.persistedFingerprintMaterial()
                )
            ),
            "2a0067b16b3a62d9ef99e1ca215efdc1aabae38b474eac52eebf2669c62ce057"
        )
    }

    func testAchievementScopeBindsExactProductionDependencySemantics() {
        let completedRun = [
            "pocket-vector-completed-run-achievement-eligibility-v1",
            "requiredFinishReason", "timerExpired",
            "minimumElapsedGameplayMilliseconds", "60000",
            "elapsedComparison", "greater-than-or-equal-v1",
        ]
        let runStatistics = [
            "pocket-vector-run-statistics-achievement-dependencies-v1",
            "successfulPassesPolicy",
            "completions-plus-touchdowns-native-int-v1",
            "accuracyPolicy",
            "attempts-gte-minimum-and-positive-then-successful-passes-times-100-gte-attempts-times-percent-native-int-v1",
        ]
        let career = [
            "pocket-vector-career-statistics-achievement-dependencies-v1",
            "successfulPassesPolicy",
            "completions-plus-touchdowns-native-int-v1",
        ]
        let accumulator = [
            "pocket-vector-persisted-career-accumulator-v1",
            "supportedEconomyVersion", "1",
            "naturalCompletionPolicy",
            "supported-economy-version-and-timer-expired-with-exact-persisted-run-duration-v1",
            "naturalCompletionFinishReason", "timerExpired",
            "naturalCompletionMilliseconds", "60000",
            "rewardEligibilityMinimumAttempts", "3",
            "nonNaturalRunPolicy", "return-input-career-unchanged-v1",
            "fieldUpdates",
            "attempts+=run.attempts,bonusTouchdowns+=run.bonusTouchdownCount,completedRuns+=1,completions+=run.completions,incompletions+=run.incompletions,interceptions+=run.interceptions,rewardEligibleRuns+=1-if-eligible,touchdowns+=run.touchdowns",
            "integerAdditionPolicy",
            "native-int-adding-reporting-overflow-throws-arithmetic-overflow-v1",
            "successfulPassesOverflowCheck",
            "checked-completions-plus-touchdowns-v1",
            "highestScorePolicy", "maximum-existing-and-run-score-v1",
            "totalScoreUpdate",
            "existing-totalScore-plus-int64-run-score-v1",
            "totalScoreAdditionPolicy",
            "int64-adding-reporting-overflow-throws-arithmetic-overflow-v1",
            "recomputePolicy",
            "input-sequence-left-fold-from-zero-career-v1",
        ]

        XCTAssertEqual(
            CompletedRun.achievementEligibilityFingerprintMaterial,
            completedRun
        )
        XCTAssertEqual(
            RunStatisticsSnapshot.achievementDependencyFingerprintMaterial,
            runStatistics
        )
        XCTAssertEqual(
            CareerStatistics.achievementDependencyFingerprintMaterial,
            career
        )
        XCTAssertEqual(
            PersistedCareerAccumulatorV1.persistedFingerprintMaterial,
            accumulator
        )
        XCTAssertEqual(
            AchievementEvaluator.persistedFingerprintMaterial,
            [
                "pocket-vector-achievement-evaluator-semantics-v1",
                "eligibleRunPolicy", "naturally-completed-runs-only-v1",
                "evaluationOrderPolicy",
                "achievement-id-utf8-ascending-v1",
                "progressPolicy",
                "monotonic-max-percent-and-first-completion-date-v1",
                "binaryProgressPolicy",
                "value-greater-than-or-equal-target-yields-100-else-0-v1",
                "scaledProgressPolicy",
                "target-nonpositive-100-else-clamped-integer-floor-percent-v1",
                "allLanesPolicy", "set-intersection-with-all-lane-ids-v1",
                "completedRunDependencyMaterialCount",
                String(completedRun.count),
            ] + completedRun + [
                "runStatisticsDependencyMaterialCount",
                String(runStatistics.count),
            ] + runStatistics + [
                "careerDependencyMaterialCount", String(career.count),
            ] + career + [
                "careerAccumulatorDependencyMaterialCount",
                String(accumulator.count),
            ] + accumulator
        )

        XCTAssertTrue(
            RunStatisticsSnapshot(
                attempts: 12,
                completions: 6,
                touchdowns: 4
            ).meetsAccuracy(percent: 80, minimumAttempts: 12)
        )
        XCTAssertFalse(
            RunStatisticsSnapshot(
                attempts: 11,
                completions: 7,
                touchdowns: 3,
                incompletions: 1
            ).meetsAccuracy(percent: 80, minimumAttempts: 12)
        )
        var careerFixture = CareerStatistics()
        careerFixture.completions = 7
        careerFixture.touchdowns = 3
        XCTAssertEqual(careerFixture.successfulPasses, 10)
    }

    func testScopeResetRequiresExplicitEpochRevocationAndFreshBootstrap()
        async throws
    {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let oldEpoch = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!
        let freshEpoch = UUID(uuidString: "20000000-0000-4000-8000-000000000002")!
        // Frozen pre-release transport/economy-only scope digest.
        let oldScope = CloudReplicaScopeFingerprint(
            rawValue:
                "3cf897580315794f23fa98294a6da0aa541cde3168a9b271497abd366ab21380"
        )
        let newScope = scopeFingerprint()
        let store = AtomicCloudReplicaCheckpointDiskStore(rootDirectoryURL: root)
        let oldCheckpoint = try CloudReplicaCheckpointV1(
            accountID: accountA,
            configurationScopeFingerprint: oldScope,
            generation: 1,
            finalCursor: cursor("pre-release-v2-cursor"),
            recordsByLogicalID: [:],
            providerLocatorByLogicalID: [:],
            logicalIDByProviderLocator: [:],
            tombstonesByProviderLocator: [:],
            replicaEpoch: oldEpoch
        )
        try await store.activate(
            replicaEpoch: oldEpoch,
            configurationScopeFingerprint: oldScope,
            for: accountA
        )
        try await store.save(oldCheckpoint, at: Date(timeIntervalSince1970: 5_000))

        do {
            _ = try await store.load(
                for: accountA,
                configurationScopeFingerprint: newScope,
                at: Date(timeIntervalSince1970: 5_001)
            )
            XCTFail("An active epoch must reject a different scope")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .configurationScopeMismatch
            )
        }
        do {
            try await store.activate(replicaEpoch: freshEpoch, configurationScopeFingerprint: scopeFingerprint(), for: accountA)
            XCTFail("A schema reset must not rotate an active epoch implicitly")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .replicaEpochMismatch
            )
        }

        try await store.remove(for: accountA, revoking: oldEpoch)
        try await store.activate(
            replicaEpoch: freshEpoch,
            configurationScopeFingerprint: newScope,
            for: accountA
        )
        var accumulator = CloudReplicaStagedAccumulator(
            accountID: accountA,
            configurationScopeFingerprint: newScope,
            replicaEpoch: freshEpoch
        )
        let firstFetch = page(
            accountID: accountA,
            requestedAfter: nil,
            scope: newScope,
            cursor: "fresh-v2-cursor",
            moreComing: false
        )
        XCTAssertNil(firstFetch.requestedAfterCursor)
        let freshCheckpoint = try XCTUnwrap(accumulator.apply(firstFetch))
        XCTAssertEqual(freshCheckpoint.generation, 1)
        try await store.save(
            freshCheckpoint,
            at: Date(timeIntervalSince1970: 5_002)
        )
        let loaded = try await store.load(
            for: accountA,
            configurationScopeFingerprint: newScope,
            at: Date(timeIntervalSince1970: 5_003)
        )
        XCTAssertEqual(loaded.checkpoint, freshCheckpoint)
    }

    func testDiskStoreRecoversPrimaryFromBackupAndRepairsCorruptBackup() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AtomicCloudReplicaCheckpointDiskStore(rootDirectoryURL: root)
        let expected = try checkpoint(
            modifications: [discovered(id: "profile", locator: "provider-profile")]
        )
        try await store.activate(replicaEpoch: expected.replicaEpoch, configurationScopeFingerprint: scopeFingerprint(), for: accountA)
        try await store.save(expected, at: Date(timeIntervalSince1970: 1_000))
        let locations = storageLocations(root: root, accountID: accountA)

        try Data("not-json".utf8).write(to: locations.primary, options: .atomic)
        let recovered = try await store.load(
            for: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            at: Date(timeIntervalSince1970: 1_001)
        )
        XCTAssertEqual(recovered.checkpoint, expected)
        XCTAssertEqual(recovered.source, .backup)
        XCTAssertEqual(recovered.quarantinedFileCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: locations.primary.path))

        try Data("still-not-json".utf8).write(to: locations.backup, options: .atomic)
        let repaired = try await store.load(
            for: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            at: Date(timeIntervalSince1970: 1_002)
        )
        XCTAssertEqual(repaired.checkpoint, expected)
        XCTAssertEqual(repaired.source, .primary)
        XCTAssertEqual(repaired.quarantinedFileCount, 1)
        XCTAssertEqual(
            try Data(contentsOf: locations.primary),
            try Data(contentsOf: locations.backup)
        )

        let quarantined = try FileManager.default.contentsOfDirectory(
            at: locations.quarantine,
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(quarantined.count, 2)
        XCTAssertTrue(quarantined.allSatisfy { $0.lastPathComponent.hasPrefix("checkpoint-") })
    }

    func testUnknownQuarantineMoveIsReconciledBeforeRecoveryContinues()
        async throws
    {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fileSystem = FaultInjectingCheckpointFileSystem()
        let store = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root,
            fileSystem: fileSystem
        )
        let expected = try checkpoint(modifications: [])
        try await store.activate(
            replicaEpoch: epoch,
            configurationScopeFingerprint: scopeFingerprint(),
            for: accountA
        )
        try await store.save(expected, at: Date(timeIntervalSince1970: 1_010))
        let locations = storageLocations(root: root, accountID: accountA)
        try Data("corrupt".utf8).write(to: locations.primary, options: .atomic)
        fileSystem.failAfterNextMove()

        let recovered = try await store.load(
            for: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            at: Date(timeIntervalSince1970: 1_011)
        )
        XCTAssertEqual(recovered.checkpoint, expected)
        XCTAssertEqual(recovered.source, .backup)
        XCTAssertGreaterThan(
            fileSystem.durableReconciliationCount(named: "checkpoint.json"),
            0
        )
        XCTAssertGreaterThan(
            fileSystem.durableReconciliationCount(
                named: "checkpoint-primary-corrupt.json"
            ),
            0
        )
        XCTAssertEqual(fileSystem.unresolvedDurabilityPathCount(), 0)
    }

    func testCorruptAndMismatchedEnvelopesNeverBecomeCurrent() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AtomicCloudReplicaCheckpointDiskStore(rootDirectoryURL: root)
        let expected = try checkpoint(
            modifications: [discovered(id: "profile", locator: "provider-profile")]
        )
        try await store.activate(replicaEpoch: expected.replicaEpoch, configurationScopeFingerprint: scopeFingerprint(), for: accountA)
        try await store.save(expected, at: Date(timeIntervalSince1970: 2_000))

        do {
            _ = try await store.load(
                for: accountA,
                configurationScopeFingerprint: alternateScopeFingerprint(),
                at: Date(timeIntervalSince1970: 2_001)
            )
            XCTFail("The active authority must reject a mismatched scope")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .configurationScopeMismatch
            )
        }

        try await store.save(expected, at: Date(timeIntervalSince1970: 2_002))
        let accountALocations = storageLocations(root: root, accountID: accountA)
        let accountBLocations = storageLocations(root: root, accountID: accountB)
        try FileManager.default.createDirectory(
            at: accountBLocations.directory,
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(
            at: accountALocations.primary,
            to: accountBLocations.primary
        )
        let wrongAccount = try await store.load(
            for: accountB,
            configurationScopeFingerprint: scopeFingerprint(),
            at: Date(timeIntervalSince1970: 2_003)
        )
        XCTAssertNil(wrongAccount.checkpoint)
        XCTAssertEqual(wrongAccount.source, .none)
        XCTAssertEqual(wrongAccount.quarantinedFileCount, 1)
    }

    func testDiskStoreIsolatesAccountsBehindOpaqueHashedDirectories() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AtomicCloudReplicaCheckpointDiskStore(rootDirectoryURL: root)
        let checkpointA = try checkpoint(
            modifications: [discovered(id: "profile-a", locator: "provider-a")]
        )
        let checkpointB = try checkpoint(
            accountID: accountB,
            modifications: [discovered(id: "profile-b", locator: "provider-b")]
        )
        try await store.activate(replicaEpoch: checkpointA.replicaEpoch, configurationScopeFingerprint: scopeFingerprint(), for: accountA)
        try await store.activate(replicaEpoch: checkpointB.replicaEpoch, configurationScopeFingerprint: scopeFingerprint(), for: accountB)
        try await store.save(checkpointA, at: Date(timeIntervalSince1970: 3_000))
        try await store.save(checkpointB, at: Date(timeIntervalSince1970: 3_001))

        let loadedA = try await store.load(
            for: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            at: Date(timeIntervalSince1970: 3_002)
        )
        let loadedB = try await store.load(
            for: accountB,
            configurationScopeFingerprint: scopeFingerprint(),
            at: Date(timeIntervalSince1970: 3_003)
        )
        XCTAssertEqual(loadedA.checkpoint, checkpointA)
        XCTAssertEqual(loadedB.checkpoint, checkpointB)

        let nameA = AtomicCloudReplicaCheckpointDiskStore.accountDirectoryName(for: accountA)
        let nameB = AtomicCloudReplicaCheckpointDiskStore.accountDirectoryName(for: accountB)
        XCTAssertEqual(nameA.count, 64)
        XCTAssertEqual(nameB.count, 64)
        XCTAssertNotEqual(nameA, nameB)
        XCTAssertFalse(nameA.contains(accountA.rawValue))
        XCTAssertFalse(nameB.contains(accountB.rawValue))
        XCTAssertFalse(root.path.contains(accountA.rawValue))
        XCTAssertFalse(root.path.contains(accountB.rawValue))
    }

    func testLoadCanDiscoverPersistedEpochBeforeActivation() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = AtomicCloudReplicaCheckpointDiskStore(rootDirectoryURL: root)
        let expected = try checkpoint(modifications: [])
        try await writer.activate(replicaEpoch: expected.replicaEpoch, configurationScopeFingerprint: scopeFingerprint(), for: accountA)
        try await writer.save(expected, at: Date(timeIntervalSince1970: 3_100))

        let relaunched = AtomicCloudReplicaCheckpointDiskStore(rootDirectoryURL: root)
        let loaded = try await relaunched.load(
            for: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            at: Date(timeIntervalSince1970: 3_101)
        )
        XCTAssertEqual(loaded.checkpoint, expected)
        try await relaunched.activate(replicaEpoch: expected.replicaEpoch, configurationScopeFingerprint: scopeFingerprint(), for: accountA)
    }

    func testRelaunchResumesActiveEpochBeforeGenerationOneAndCanSave()
        async throws
    {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = AtomicCloudReplicaCheckpointDiskStore(rootDirectoryURL: root)
        try await writer.activate(replicaEpoch: epoch, configurationScopeFingerprint: scopeFingerprint(), for: accountA)

        let relaunched = AtomicCloudReplicaCheckpointDiskStore(rootDirectoryURL: root)
        let resumedValue = try await relaunched.resumeActiveReplicaEpoch(for: accountA, configurationScopeFingerprint: scopeFingerprint())
        let resumed = try XCTUnwrap(resumedValue)
        XCTAssertEqual(
            resumed,
            CloudReplicaEpochResumeResult(
                replicaEpoch: epoch,
                acceptedHistory: nil,
                hasDurableCheckpointIntent: false
            )
        )

        let first = try checkpoint(modifications: [])
        try await relaunched.save(first, at: Date(timeIntervalSince1970: 3_102))
        let loaded = try await relaunched.load(
            for: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            at: Date(timeIntervalSince1970: 3_103)
        )
        XCTAssertEqual(loaded.checkpoint, first)
    }

    func testResumeReturnsNilForMissingAndFreshRevokedAuthority() async throws {
        let missingRoot = temporaryDirectory()
        let revokedRoot = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: missingRoot)
            try? FileManager.default.removeItem(at: revokedRoot)
        }
        let missingResume = try await AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: missingRoot
        ).resumeActiveReplicaEpoch(for: accountA, configurationScopeFingerprint: scopeFingerprint())
        XCTAssertNil(missingResume)

        let owner = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: revokedRoot
        )
        try await owner.activate(replicaEpoch: epoch, configurationScopeFingerprint: scopeFingerprint(), for: accountA)
        let revoker = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: revokedRoot
        )
        try await revoker.remove(for: accountA, revoking: epoch)
        let revokedResume = try await AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: revokedRoot
        ).resumeActiveReplicaEpoch(for: accountA, configurationScopeFingerprint: scopeFingerprint())
        XCTAssertNil(revokedResume)
    }

    func testPreGenerationRelaunchRejectsScopeMismatch() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try await AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root
        ).activate(
            replicaEpoch: epoch,
            configurationScopeFingerprint: scopeFingerprint(),
            for: accountA
        )

        let relaunched = AtomicCloudReplicaCheckpointDiskStore(rootDirectoryURL: root)
        do {
            _ = try await relaunched.resumeActiveReplicaEpoch(
                for: accountA,
                configurationScopeFingerprint: alternateScopeFingerprint()
            )
            XCTFail("Scope ownership must survive a pre-generation-one relaunch")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .configurationScopeMismatch
            )
        }
        let resumed = try await relaunched.resumeActiveReplicaEpoch(
            for: accountA,
            configurationScopeFingerprint: scopeFingerprint()
        )
        XCTAssertEqual(resumed?.replicaEpoch, epoch)
    }

    func testCheckpointObservationMintsOnlyLockedAcceptedState() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AtomicCloudReplicaCheckpointDiskStore(rootDirectoryURL: root)
        try await store.activate(
            replicaEpoch: epoch,
            configurationScopeFingerprint: scopeFingerprint(),
            for: accountA
        )

        let absent = try await store.observeCurrentCheckpoint(
            for: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            replicaEpoch: epoch,
            at: Date(timeIntervalSince1970: 3_110)
        )
        XCTAssertEqual(absent.accountID, accountA)
        XCTAssertEqual(absent.configurationScopeFingerprint, scopeFingerprint())
        XCTAssertEqual(absent.replicaEpoch, epoch)
        XCTAssertEqual(absent.state, .absent)

        let first = try checkpoint(modifications: [])
        try await store.save(first, at: Date(timeIntervalSince1970: 3_111))
        let accepted = try await store.observeCurrentCheckpoint(
            for: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            replicaEpoch: epoch,
            at: Date(timeIntervalSince1970: 3_112)
        )
        XCTAssertEqual(
            accepted.state,
            .checkpoint(ProfileHydrationCheckpointIdentityV1(checkpoint: first))
        )
    }

    func testCheckpointObservationRejectsWrongBindingsAndRevocation()
        async throws
    {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let stale = AtomicCloudReplicaCheckpointDiskStore(rootDirectoryURL: root)
        try await stale.activate(
            replicaEpoch: epoch,
            configurationScopeFingerprint: scopeFingerprint(),
            for: accountA
        )
        let first = try checkpoint(modifications: [])
        try await stale.save(first, at: Date(timeIntervalSince1970: 3_137))

        do {
            _ = try await stale.observeCurrentCheckpoint(
                for: accountA,
                configurationScopeFingerprint: alternateScopeFingerprint(),
                replicaEpoch: epoch,
                at: Date(timeIntervalSince1970: 3_138)
            )
            XCTFail("A receipt cannot cross configuration scopes")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .configurationScopeMismatch
            )
        }
        do {
            _ = try await stale.observeCurrentCheckpoint(
                for: accountA,
                configurationScopeFingerprint: scopeFingerprint(),
                replicaEpoch: UUID(),
                at: Date(timeIntervalSince1970: 3_139)
            )
            XCTFail("A receipt cannot cross replica epochs")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .replicaEpochMismatch
            )
        }

        try await AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root
        ).remove(for: accountA, revoking: epoch)
        do {
            _ = try await stale.observeCurrentCheckpoint(
                for: accountA,
                configurationScopeFingerprint: scopeFingerprint(),
                replicaEpoch: epoch,
                at: Date(timeIntervalSince1970: 3_140)
            )
            XCTFail("A revoked authority cannot mint a receipt")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .replicaEpochRevoked
            )
        }
    }

    func testCheckpointObservationRecoversPreexistingPendingPublication()
        async throws
    {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fileSystem = FaultInjectingCheckpointFileSystem()
        let store = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root,
            fileSystem: fileSystem
        )
        let first = try checkpoint(modifications: [])
        try await store.activate(
            replicaEpoch: epoch,
            configurationScopeFingerprint: scopeFingerprint(),
            for: accountA
        )
        try await store.save(first, at: Date(timeIntervalSince1970: 3_141))
        var accumulator = try self.accumulator(from: first)
        let second = try XCTUnwrap(
            accumulator.apply(
                page(
                    accountID: accountA,
                    requestedAfter: "seed-cursor",
                    cursor: "pending-observation",
                    moreComing: false
                )
            )
        )
        fileSystem.failNextWrite(named: "checkpoint.watermark.json")
        do {
            try await store.save(second, at: Date(timeIntervalSince1970: 3_142))
            XCTFail("The injected publication must remain pending")
        } catch {
            XCTAssertEqual(error as? CloudReplicaCheckpointStoreError, .ioFailure)
        }

        let recovered = try await store.observeCurrentCheckpoint(
            for: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            replicaEpoch: epoch,
            at: Date(timeIntervalSince1970: 3_143)
        )
        XCTAssertEqual(
            recovered.state,
            .checkpoint(ProfileHydrationCheckpointIdentityV1(checkpoint: first))
        )
        let resume = try await store.resumeActiveReplicaEpoch(
            for: accountA,
            configurationScopeFingerprint: scopeFingerprint()
        )
        XCTAssertFalse(resume?.hasDurableCheckpointIntent == true)
    }

    func testCheckpointObservationRevalidatesAuthorityAfterLoad() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fileSystem = FaultInjectingCheckpointFileSystem()
        let writer = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root,
            fileSystem: fileSystem
        )
        let observer = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root,
            fileSystem: fileSystem
        )
        let first = try checkpoint(modifications: [])
        try await writer.activate(
            replicaEpoch: epoch,
            configurationScopeFingerprint: scopeFingerprint(),
            for: accountA
        )
        try await writer.save(first, at: Date(timeIntervalSince1970: 3_144))
        var accumulator = try self.accumulator(from: first)
        let second = try XCTUnwrap(
            accumulator.apply(
                page(
                    accountID: accountA,
                    requestedAfter: "seed-cursor",
                    cursor: "raced-observation",
                    moreComing: false
                )
            )
        )
        let blockedAttempt = fileSystem.exclusiveLockAttemptCount() + 3
        fileSystem.blockExclusiveLockAttempt(blockedAttempt)
        defer { fileSystem.releaseExclusiveLockAttempt() }
        let observationTask = Task { () -> CloudReplicaCheckpointStoreError? in
            do {
                _ = try await observer.observeCurrentCheckpoint(
                    for: self.accountA,
                    configurationScopeFingerprint: self.scopeFingerprint(),
                    replicaEpoch: self.epoch,
                    at: Date(timeIntervalSince1970: 3_145)
                )
                return nil
            } catch {
                return error as? CloudReplicaCheckpointStoreError
            }
        }
        let reachedSecondAuthorityCheck = await waitUntil {
            fileSystem.isExclusiveLockAttemptBlocked()
        }
        guard reachedSecondAuthorityCheck else {
            fileSystem.releaseExclusiveLockAttempt()
            _ = await observationTask.value
            XCTFail("The observation never reached its second authority check")
            return
        }

        fileSystem.failNextWrite(named: "checkpoint.watermark.json")
        do {
            try await writer.save(second, at: Date(timeIntervalSince1970: 3_146))
            XCTFail("The raced publication must retain pending authority")
        } catch {
            XCTAssertEqual(error as? CloudReplicaCheckpointStoreError, .ioFailure)
        }
        fileSystem.releaseExclusiveLockAttempt()
        let observationError = await observationTask.value
        XCTAssertEqual(
            observationError,
            .checkpointPublicationPending
        )
    }

    func testCurrentCheckpointLeaseBlocksSuccessorPublicationUntilBodyReturns()
        async throws
    {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fileSystem = FaultInjectingCheckpointFileSystem()
        let accountAuthority = CloudAccountGenerationAuthority()
        let leaseStore = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root,
            fileSystem: fileSystem,
            accountGenerationAuthority: accountAuthority
        )
        let writer = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root,
            fileSystem: fileSystem
        )
        let first = try checkpoint(modifications: [])
        try await leaseStore.activate(
            replicaEpoch: epoch,
            configurationScopeFingerprint: scopeFingerprint(),
            for: accountA
        )
        try await writer.activate(
            replicaEpoch: epoch,
            configurationScopeFingerprint: scopeFingerprint(),
            for: accountA
        )
        try await leaseStore.save(first, at: Date(timeIntervalSince1970: 3_147))
        var accumulator = try self.accumulator(from: first)
        let second = try XCTUnwrap(
            accumulator.apply(
                page(
                    accountID: accountA,
                    requestedAfter: "seed-cursor",
                    cursor: "lease-successor",
                    moreComing: false
                )
            )
        )
        let generation = try await accountAuthority.activate(
            accountID: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            replicaEpoch: epoch
        )
        let bodyGate = CheckpointLeaseBodyGate()
        let bodyRecorder = CheckpointLeaseInvocationRecorder()
        let leaseTask = Task {
            try await accountAuthority.withCurrentGeneration(generation) {
                accountLease in
                try await leaseStore.withCurrentCheckpointLease(
                    generationLease: accountLease,
                    at: Date(timeIntervalSince1970: 3_148)
                ) { _ in
                    bodyRecorder.recordInvocation()
                    bodyGate.enterAndWait()
                    return 17
                }
            }
        }
        let bodyEntered = bodyGate.waitUntilEntered()
        guard bodyEntered else {
            bodyGate.release()
            _ = try? await leaseTask.value
            XCTFail("The checkpoint lease body never started")
            return
        }

        let saveCompletion = CheckpointLeaseCompletionProbe()
        let attemptsBeforeSave = fileSystem.exclusiveLockAttemptCount()
        let saveTask = Task {
            let outcome: CheckpointLeaseAsyncOutcome
            do {
                try await writer.save(
                    second,
                    at: Date(timeIntervalSince1970: 3_149)
                )
                outcome = .success
            } catch let error as CloudReplicaCheckpointStoreError {
                outcome = .storeError(error)
            } catch {
                outcome = .unexpectedError(String(describing: error))
            }
            saveCompletion.recordCompletion()
            return outcome
        }
        let saveReachedLock = await waitUntil {
            fileSystem.exclusiveLockAttemptCount() > attemptsBeforeSave
        }
        XCTAssertTrue(saveReachedLock)
        let completedWhileLeased = saveCompletion.isComplete
        XCTAssertFalse(completedWhileLeased)

        bodyGate.release()
        let leasedValue = try await leaseTask.value
        XCTAssertEqual(leasedValue, 17)
        let saveOutcome = await saveTask.value
        XCTAssertEqual(saveOutcome, .success)
        let invocationCount = bodyRecorder.invocationCount
        XCTAssertEqual(invocationCount, 1)
    }

    func testCurrentCheckpointLeaseRejectsRevocationBeforeBodyAdmission()
        async throws
    {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let accountAuthority = CloudAccountGenerationAuthority()
        let leaseStore = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root,
            accountGenerationAuthority: accountAuthority
        )
        let revoker = AtomicCloudReplicaCheckpointDiskStore(rootDirectoryURL: root)
        let first = try checkpoint(modifications: [])
        try await leaseStore.activate(
            replicaEpoch: epoch,
            configurationScopeFingerprint: scopeFingerprint(),
            for: accountA
        )
        try await leaseStore.save(first, at: Date(timeIntervalSince1970: 3_150))
        let generation = try await accountAuthority.activate(
            accountID: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            replicaEpoch: epoch
        )
        try await revoker.remove(for: accountA, revoking: epoch)
        let bodyRecorder = CheckpointLeaseInvocationRecorder()

        do {
            _ = try await accountAuthority.withCurrentGeneration(generation) {
                accountLease in
                try await leaseStore.withCurrentCheckpointLease(
                    generationLease: accountLease,
                    at: Date(timeIntervalSince1970: 3_151)
                ) { _ in
                    bodyRecorder.recordInvocation()
                    return true
                }
            }
            XCTFail("Revocation must reject the lease before its body starts")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .replicaEpochRevoked
            )
        }
        let invocationCount = bodyRecorder.invocationCount
        XCTAssertEqual(invocationCount, 0)
    }

    func testRevocationRacingHeldCheckpointLeaseLinearizesAfterBody()
        async throws
    {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fileSystem = FaultInjectingCheckpointFileSystem()
        let accountAuthority = CloudAccountGenerationAuthority()
        let leaseStore = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root,
            fileSystem: fileSystem,
            accountGenerationAuthority: accountAuthority
        )
        let revoker = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root,
            fileSystem: fileSystem
        )
        let first = try checkpoint(modifications: [])
        try await leaseStore.activate(
            replicaEpoch: epoch,
            configurationScopeFingerprint: scopeFingerprint(),
            for: accountA
        )
        try await leaseStore.save(first, at: Date(timeIntervalSince1970: 3_152))
        let generation = try await accountAuthority.activate(
            accountID: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            replicaEpoch: epoch
        )
        let bodyGate = CheckpointLeaseBodyGate()
        let bodyRecorder = CheckpointLeaseInvocationRecorder()
        let leaseTask = Task {
            try await accountAuthority.withCurrentGeneration(generation) {
                accountLease in
                try await leaseStore.withCurrentCheckpointLease(
                    generationLease: accountLease,
                    at: Date(timeIntervalSince1970: 3_153)
                ) { _ in
                    bodyRecorder.recordInvocation()
                    bodyGate.enterAndWait()
                    return 19
                }
            }
        }
        let bodyEntered = bodyGate.waitUntilEntered()
        guard bodyEntered else {
            bodyGate.release()
            _ = try? await leaseTask.value
            XCTFail("The checkpoint lease body never started")
            return
        }

        let revocationCompletion = CheckpointLeaseCompletionProbe()
        let attemptsBeforeRevocation = fileSystem.exclusiveLockAttemptCount()
        let revocationTask = Task {
            let outcome: CheckpointLeaseAsyncOutcome
            do {
                try await revoker.remove(for: self.accountA, revoking: self.epoch)
                outcome = .success
            } catch let error as CloudReplicaCheckpointStoreError {
                outcome = .storeError(error)
            } catch {
                outcome = .unexpectedError(String(describing: error))
            }
            revocationCompletion.recordCompletion()
            return outcome
        }
        let revocationReachedLock = await waitUntil {
            fileSystem.exclusiveLockAttemptCount() > attemptsBeforeRevocation
        }
        XCTAssertTrue(revocationReachedLock)
        let revokedWhileLeased = revocationCompletion.isComplete
        XCTAssertFalse(revokedWhileLeased)

        bodyGate.release()
        let leasedValue = try await leaseTask.value
        XCTAssertEqual(leasedValue, 19)
        let revocationOutcome = await revocationTask.value
        XCTAssertEqual(revocationOutcome, .success)

        do {
            _ = try await accountAuthority.withCurrentGeneration(generation) {
                accountLease in
                try await leaseStore.withCurrentCheckpointLease(
                    generationLease: accountLease,
                    at: Date(timeIntervalSince1970: 3_154)
                ) { _ in
                    bodyRecorder.recordInvocation()
                    return true
                }
            }
            XCTFail("A lease after durable revocation must fail closed")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .replicaEpochRevoked
            )
        }
        let invocationCount = bodyRecorder.invocationCount
        XCTAssertEqual(invocationCount, 1)
    }

    func testCurrentCheckpointLeaseRejectsPublicationPendingAtFinalRevalidation()
        async throws
    {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fileSystem = FaultInjectingCheckpointFileSystem()
        let accountAuthority = CloudAccountGenerationAuthority()
        let writer = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root,
            fileSystem: fileSystem
        )
        let leaseStore = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root,
            fileSystem: fileSystem,
            accountGenerationAuthority: accountAuthority
        )
        let first = try checkpoint(modifications: [])
        try await writer.activate(
            replicaEpoch: epoch,
            configurationScopeFingerprint: scopeFingerprint(),
            for: accountA
        )
        try await leaseStore.activate(
            replicaEpoch: epoch,
            configurationScopeFingerprint: scopeFingerprint(),
            for: accountA
        )
        try await writer.save(first, at: Date(timeIntervalSince1970: 3_155))
        var accumulator = try self.accumulator(from: first)
        let second = try XCTUnwrap(
            accumulator.apply(
                page(
                    accountID: accountA,
                    requestedAfter: "seed-cursor",
                    cursor: "lease-pending-race",
                    moreComing: false
                )
            )
        )
        let generation = try await accountAuthority.activate(
            accountID: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            replicaEpoch: epoch
        )
        let bodyRecorder = CheckpointLeaseInvocationRecorder()
        let blockedAttempt = fileSystem.exclusiveLockAttemptCount() + 3
        fileSystem.blockExclusiveLockAttempt(blockedAttempt)
        defer { fileSystem.releaseExclusiveLockAttempt() }
        let leaseTask = Task { () -> CloudReplicaCheckpointStoreError? in
            do {
                _ = try await accountAuthority.withCurrentGeneration(generation) {
                    accountLease in
                    try await leaseStore.withCurrentCheckpointLease(
                        generationLease: accountLease,
                        at: Date(timeIntervalSince1970: 3_156)
                    ) { _ in
                        bodyRecorder.recordInvocation()
                        return true
                    }
                }
                return nil
            } catch {
                return error as? CloudReplicaCheckpointStoreError
            }
        }
        let reachedFinalRevalidation = await waitUntil {
            fileSystem.isExclusiveLockAttemptBlocked()
        }
        guard reachedFinalRevalidation else {
            fileSystem.releaseExclusiveLockAttempt()
            _ = await leaseTask.value
            XCTFail("The lease never reached its final locked revalidation")
            return
        }

        fileSystem.failNextWrite(named: "checkpoint.watermark.json")
        do {
            try await writer.save(second, at: Date(timeIntervalSince1970: 3_157))
            XCTFail("The injected successor publication must remain pending")
        } catch {
            XCTAssertEqual(error as? CloudReplicaCheckpointStoreError, .ioFailure)
        }
        fileSystem.releaseExclusiveLockAttempt()
        let leaseError = await leaseTask.value
        XCTAssertEqual(leaseError, .checkpointPublicationPending)
        let invocationCount = bodyRecorder.invocationCount
        XCTAssertEqual(invocationCount, 0)
    }

    func testCurrentCheckpointLeasePreservesBodyErrorAndReleasesLock()
        async throws
    {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let accountAuthority = CloudAccountGenerationAuthority()
        let store = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root,
            accountGenerationAuthority: accountAuthority
        )
        let first = try checkpoint(modifications: [])
        try await store.activate(
            replicaEpoch: epoch,
            configurationScopeFingerprint: scopeFingerprint(),
            for: accountA
        )
        try await store.save(first, at: Date(timeIntervalSince1970: 3_158))
        let generation = try await accountAuthority.activate(
            accountID: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            replicaEpoch: epoch
        )

        do {
            let _: Int = try await accountAuthority
                .withCurrentGeneration(generation) { accountLease in
                    try await store.withCurrentCheckpointLease(
                        generationLease: accountLease,
                        at: Date(timeIntervalSince1970: 3_159)
                    ) { _ in
                        throw CheckpointLeaseSentinelError.expected
                    }
                }
            XCTFail("The lease body sentinel must escape unchanged")
        } catch {
            XCTAssertEqual(error as? CheckpointLeaseSentinelError, .expected)
            XCTAssertNil(error as? CloudReplicaCheckpointStoreError)
        }

        let accepted = try await accountAuthority.withCurrentGeneration(generation) {
            accountLease in
            try await store.withCurrentCheckpointLease(
                generationLease: accountLease,
                at: Date(timeIntervalSince1970: 3_160)
            ) { _ in
                23
            }
        }
        XCTAssertEqual(accepted, 23)
    }

    func testCurrentCheckpointLeaseRejectsWrongAndUnrememberedGenerationBindings()
        async throws
    {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let canonicalAuthority = CloudAccountGenerationAuthority()
        let rememberedStore = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root,
            accountGenerationAuthority: canonicalAuthority
        )
        let first = try checkpoint(modifications: [])
        try await rememberedStore.activate(
            replicaEpoch: epoch,
            configurationScopeFingerprint: scopeFingerprint(),
            for: accountA
        )
        try await rememberedStore.save(
            first,
            at: Date(timeIntervalSince1970: 3_161)
        )
        let bodyRecorder = CheckpointLeaseInvocationRecorder()

        let canonicalGeneration = try await canonicalAuthority.activate(
            accountID: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            replicaEpoch: epoch
        )
        let foreignAuthority = CloudAccountGenerationAuthority()
        let foreignGeneration = try await foreignAuthority.activate(
            accountID: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            replicaEpoch: epoch
        )
        do {
            _ = try await foreignAuthority.withCurrentGeneration(
                foreignGeneration
            ) { accountLease in
                try await rememberedStore.withCurrentCheckpointLease(
                    generationLease: accountLease,
                    at: Date(timeIntervalSince1970: 3_162)
                ) { _ in
                    bodyRecorder.recordInvocation()
                    return true
                }
            }
            XCTFail("A permit from another authority must be rejected")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .accountGenerationAuthorityMismatch
            )
        }

        let unboundStore = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root
        )
        do {
            _ = try await canonicalAuthority.withCurrentGeneration(
                canonicalGeneration
            ) { accountLease in
                try await unboundStore.withCurrentCheckpointLease(
                    generationLease: accountLease,
                    at: Date(timeIntervalSince1970: 3_163)
                ) { _ in
                    bodyRecorder.recordInvocation()
                    return true
                }
            }
            XCTFail("A store without a canonical authority must reject permits")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .accountGenerationAuthorityNotBound
            )
        }

        let wrongAccountAuthority = CloudAccountGenerationAuthority()
        let wrongAccountStore = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root,
            accountGenerationAuthority: wrongAccountAuthority
        )
        try await wrongAccountStore.activate(
            replicaEpoch: epoch,
            configurationScopeFingerprint: scopeFingerprint(),
            for: accountA
        )
        let wrongAccountGeneration = try await wrongAccountAuthority.activate(
            accountID: accountB,
            configurationScopeFingerprint: scopeFingerprint(),
            replicaEpoch: epoch
        )
        do {
            _ = try await wrongAccountAuthority.withCurrentGeneration(
                wrongAccountGeneration
            ) { accountLease in
                try await wrongAccountStore.withCurrentCheckpointLease(
                    generationLease: accountLease,
                    at: Date(timeIntervalSince1970: 3_164)
                ) { _ in
                    bodyRecorder.recordInvocation()
                    return true
                }
            }
            XCTFail("A generation for another account must be rejected")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .replicaEpochNotActive
            )
        }

        let wrongScopeAuthority = CloudAccountGenerationAuthority()
        let wrongScopeStore = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root,
            accountGenerationAuthority: wrongScopeAuthority
        )
        try await wrongScopeStore.activate(
            replicaEpoch: epoch,
            configurationScopeFingerprint: scopeFingerprint(),
            for: accountA
        )
        let wrongScopeGeneration = try await wrongScopeAuthority.activate(
            accountID: accountA,
            configurationScopeFingerprint: alternateScopeFingerprint(),
            replicaEpoch: epoch
        )
        do {
            _ = try await wrongScopeAuthority.withCurrentGeneration(
                wrongScopeGeneration
            ) { accountLease in
                try await wrongScopeStore.withCurrentCheckpointLease(
                    generationLease: accountLease,
                    at: Date(timeIntervalSince1970: 3_165)
                ) { _ in
                    bodyRecorder.recordInvocation()
                    return true
                }
            }
            XCTFail("A generation for another scope must be rejected")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .configurationScopeMismatch
            )
        }

        let wrongEpochAuthority = CloudAccountGenerationAuthority()
        let wrongEpochStore = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root,
            accountGenerationAuthority: wrongEpochAuthority
        )
        try await wrongEpochStore.activate(
            replicaEpoch: epoch,
            configurationScopeFingerprint: scopeFingerprint(),
            for: accountA
        )
        let wrongEpochGeneration = try await wrongEpochAuthority.activate(
            accountID: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            replicaEpoch: UUID(uuidString: "30000000-0000-4000-8000-000000000003")!
        )
        do {
            _ = try await wrongEpochAuthority.withCurrentGeneration(
                wrongEpochGeneration
            ) { accountLease in
                try await wrongEpochStore.withCurrentCheckpointLease(
                    generationLease: accountLease,
                    at: Date(timeIntervalSince1970: 3_166)
                ) { _ in
                    bodyRecorder.recordInvocation()
                    return true
                }
            }
            XCTFail("A generation for another replica epoch must be rejected")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .replicaEpochMismatch
            )
        }

        let correctAuthority = CloudAccountGenerationAuthority()
        let correctGeneration = try await correctAuthority.activate(
            accountID: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            replicaEpoch: epoch
        )
        let unrememberedStore = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root,
            accountGenerationAuthority: correctAuthority
        )
        do {
            _ = try await correctAuthority.withCurrentGeneration(correctGeneration) {
                accountLease in
                try await unrememberedStore.withCurrentCheckpointLease(
                    generationLease: accountLease,
                    at: Date(timeIntervalSince1970: 3_167)
                ) { _ in
                    bodyRecorder.recordInvocation()
                    return true
                }
            }
            XCTFail("A store that never remembered the generation must reject it")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .replicaEpochNotActive
            )
        }
        let invocationCount = bodyRecorder.invocationCount
        XCTAssertEqual(invocationCount, 0)
    }

    func testCurrentCheckpointLeaseRejectsStaleSameBindingGenerationBeforeAdmission()
        async throws
    {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let authority = CloudAccountGenerationAuthority()
        let store = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root,
            accountGenerationAuthority: authority
        )
        try await store.activate(
            replicaEpoch: epoch,
            configurationScopeFingerprint: scopeFingerprint(),
            for: accountA
        )
        let first = try checkpoint(modifications: [])
        try await store.save(first, at: Date(timeIntervalSince1970: 3_168))
        let stale = try await authority.activate(
            accountID: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            replicaEpoch: epoch
        )
        try await authority.invalidate(stale)
        let current = try await authority.activate(
            accountID: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            replicaEpoch: epoch
        )
        let bodyRecorder = CheckpointLeaseInvocationRecorder()

        do {
            _ = try await authority.withCurrentGeneration(stale) {
                accountLease in
                try await store.withCurrentCheckpointLease(
                    generationLease: accountLease,
                    at: Date(timeIntervalSince1970: 3_169)
                ) { _ in
                    bodyRecorder.recordInvocation()
                    return true
                }
            }
            XCTFail("A stale same-binding generation must not mint a permit")
        } catch {
            XCTAssertEqual(
                error as? CloudAccountGenerationAuthorityError,
                .generationNotCurrent
            )
        }

        let accepted = try await authority.withCurrentGeneration(current) {
            accountLease in
            try await store.withCurrentCheckpointLease(
                generationLease: accountLease,
                at: Date(timeIntervalSince1970: 3_170)
            ) { _ in
                bodyRecorder.recordInvocation()
                return 29
            }
        }
        XCTAssertEqual(accepted, 29)
        XCTAssertEqual(bodyRecorder.invocationCount, 1)
    }

    func testResumeRejectsRevokedRememberedEpochWithoutMutation() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let stale = AtomicCloudReplicaCheckpointDiskStore(rootDirectoryURL: root)
        try await stale.activate(replicaEpoch: epoch, configurationScopeFingerprint: scopeFingerprint(), for: accountA)
        try await AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root
        ).remove(for: accountA, revoking: epoch)
        let locations = storageLocations(root: root, accountID: accountA)
        let authorityBefore = try Data(contentsOf: locations.authority)

        do {
            _ = try await stale.resumeActiveReplicaEpoch(for: accountA, configurationScopeFingerprint: scopeFingerprint())
            XCTFail("A remembered revoked epoch must fail closed")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .replicaEpochRevoked
            )
        }
        XCTAssertEqual(try Data(contentsOf: locations.authority), authorityBefore)
    }

    func testResumeRejectsStaleMemoryWhenDurableActiveEpochMismatches()
        async throws
    {
        let root = temporaryDirectory()
        let donorRoot = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: donorRoot)
        }
        let stale = AtomicCloudReplicaCheckpointDiskStore(rootDirectoryURL: root)
        try await stale.activate(replicaEpoch: epoch, configurationScopeFingerprint: scopeFingerprint(), for: accountA)

        let replacementEpoch = UUID(
            uuidString: "BBBBBBBB-CCCC-4DDD-8EEE-FFFFFFFFFFFF"
        )!
        let donor = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: donorRoot
        )
        try await donor.activate(replicaEpoch: replacementEpoch, configurationScopeFingerprint: scopeFingerprint(), for: accountA)
        let locations = storageLocations(root: root, accountID: accountA)
        let donorLocations = storageLocations(root: donorRoot, accountID: accountA)
        try Data(contentsOf: donorLocations.authority).write(
            to: locations.authority,
            options: .atomic
        )
        let authorityBefore = try Data(contentsOf: locations.authority)

        do {
            _ = try await stale.resumeActiveReplicaEpoch(for: accountA, configurationScopeFingerprint: scopeFingerprint())
            XCTFail("Stale in-memory ownership must not adopt a different epoch")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .replicaEpochMismatch
            )
        }
        XCTAssertEqual(try Data(contentsOf: locations.authority), authorityBefore)
    }

    func testResumeReportsDurablePendingCheckpointIntent() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fileSystem = FaultInjectingCheckpointFileSystem()
        let writer = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root,
            fileSystem: fileSystem
        )
        let first = try checkpoint(modifications: [])
        try await writer.activate(replicaEpoch: epoch, configurationScopeFingerprint: scopeFingerprint(), for: accountA)
        fileSystem.failNextWrite(named: "checkpoint.watermark.json")
        do {
            try await writer.save(first, at: Date(timeIntervalSince1970: 3_104))
            XCTFail("The injected checkpoint publication must fail")
        } catch {
            XCTAssertEqual(error as? CloudReplicaCheckpointStoreError, .ioFailure)
        }

        let resumedValue = try await AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root
        ).resumeActiveReplicaEpoch(for: accountA, configurationScopeFingerprint: scopeFingerprint())
        let resumed = try XCTUnwrap(resumedValue)
        XCTAssertEqual(resumed.replicaEpoch, epoch)
        XCTAssertFalse(resumed.hasAcceptedCheckpoint)
        XCTAssertTrue(resumed.hasDurableCheckpointIntent)
    }

    func testResumeDistinguishesAcceptedHistoryWithPendingSuccessor()
        async throws
    {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fileSystem = FaultInjectingCheckpointFileSystem()
        let writer = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root,
            fileSystem: fileSystem
        )
        let first = try checkpoint(modifications: [])
        try await writer.activate(
            replicaEpoch: epoch,
            configurationScopeFingerprint: scopeFingerprint(),
            for: accountA
        )
        try await writer.save(first, at: Date(timeIntervalSince1970: 3_114))
        var accumulator = try self.accumulator(from: first)
        let second = try XCTUnwrap(
            accumulator.apply(
                page(
                    accountID: accountA,
                    requestedAfter: "seed-cursor",
                    cursor: "successor-cursor",
                    moreComing: false
                )
            )
        )
        fileSystem.failNextWrite(named: "checkpoint.watermark.json")
        do {
            try await writer.save(second, at: Date(timeIntervalSince1970: 3_115))
            XCTFail("The successor publication fault must retain its intent")
        } catch {
            XCTAssertEqual(error as? CloudReplicaCheckpointStoreError, .ioFailure)
        }

        let resumeValue = try await AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root
        ).resumeActiveReplicaEpoch(
            for: accountA,
            configurationScopeFingerprint: scopeFingerprint()
        )
        let resumed = try XCTUnwrap(resumeValue)
        XCTAssertTrue(resumed.hasAcceptedCheckpoint)
        XCTAssertTrue(resumed.hasDurableCheckpointIntent)
    }

    func testResumeRetainsAcceptedHistoryWhenLocalCopiesAreLost() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = AtomicCloudReplicaCheckpointDiskStore(rootDirectoryURL: root)
        let first = try checkpoint(modifications: [])
        try await writer.activate(
            replicaEpoch: epoch,
            configurationScopeFingerprint: scopeFingerprint(),
            for: accountA
        )
        try await writer.save(first, at: Date(timeIntervalSince1970: 3_116))
        let locations = storageLocations(root: root, accountID: accountA)
        try FoundationCloudReplicaCheckpointFileSystem().removeItem(
            at: locations.directory
        )

        let relaunched = AtomicCloudReplicaCheckpointDiskStore(rootDirectoryURL: root)
        let resumeValue = try await relaunched.resumeActiveReplicaEpoch(
            for: accountA,
            configurationScopeFingerprint: scopeFingerprint()
        )
        let resumed = try XCTUnwrap(resumeValue)
        XCTAssertTrue(resumed.hasAcceptedCheckpoint)
        XCTAssertFalse(resumed.hasDurableCheckpointIntent)
        let acceptedHistory = try XCTUnwrap(resumed.acceptedHistory)
        XCTAssertEqual(acceptedHistory.generation, first.generation)
        let missing = try await relaunched.load(
            for: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            at: Date(timeIntervalSince1970: 3_117)
        )
        XCTAssertNil(missing.checkpoint)

        do {
            _ = try await relaunched.observeCurrentCheckpoint(
                for: accountA,
                configurationScopeFingerprint: scopeFingerprint(),
                replicaEpoch: epoch,
                at: Date(timeIntervalSince1970: 3_118)
            )
            XCTFail("Accepted history without exact copies must not mint a receipt")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .invalidCheckpoint
            )
        }

        var reconstruction = CloudReplicaStagedAccumulator(
            reconstructingFullSnapshotFrom: acceptedHistory
        )
        let reconstructed = try XCTUnwrap(
            reconstruction.apply(
                page(
                    accountID: accountA,
                    modifications: [
                        discovered(
                            id: "reconstructed-profile",
                            locator: "provider-reconstructed-profile"
                        ),
                    ],
                    requestedAfter: nil,
                    cursor: "reconstructed-full-snapshot",
                    moreComing: false
                )
            )
        )
        XCTAssertEqual(reconstructed.generation, first.generation + 1)

        do {
            try await relaunched.save(
                reconstructed,
                at: Date(timeIntervalSince1970: 3_119)
            )
            XCTFail("Ordinary save must reject a successor without current cache")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .invalidCheckpoint
            )
        }
        try await relaunched.saveReconstructedFullSnapshot(
            reconstructed,
            replacing: acceptedHistory,
            at: Date(timeIntervalSince1970: 3_120)
        )
        do {
            try await relaunched.saveReconstructedFullSnapshot(
                reconstructed,
                replacing: acceptedHistory,
                at: Date(timeIntervalSince1970: 3_120.5)
            )
            XCTFail("An accepted-history token must become stale after recovery")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .acceptedHistoryMismatch
            )
        }

        let verifiedStore = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root
        )
        let verified = try await verifiedStore.load(
            for: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            at: Date(timeIntervalSince1970: 3_121)
        )
        XCTAssertEqual(verified.checkpoint, reconstructed)
        let verifiedResume = try await verifiedStore.resumeActiveReplicaEpoch(
            for: accountA,
            configurationScopeFingerprint: scopeFingerprint()
        )
        XCTAssertEqual(
            verifiedResume?.acceptedHistory?.generation,
            reconstructed.generation
        )
    }

    func testFullSnapshotRecoveryRejectsWhenAcceptedCacheStillExists()
        async throws
    {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AtomicCloudReplicaCheckpointDiskStore(rootDirectoryURL: root)
        let first = try checkpoint(modifications: [])
        try await store.activate(
            replicaEpoch: epoch,
            configurationScopeFingerprint: scopeFingerprint(),
            for: accountA
        )
        try await store.save(first, at: Date(timeIntervalSince1970: 3_122))
        let resume = try await store.resumeActiveReplicaEpoch(
            for: accountA,
            configurationScopeFingerprint: scopeFingerprint()
        )
        let acceptedHistory = try XCTUnwrap(resume?.acceptedHistory)
        var reconstruction = CloudReplicaStagedAccumulator(
            reconstructingFullSnapshotFrom: acceptedHistory
        )
        let candidate = try XCTUnwrap(
            reconstruction.apply(
                page(
                    accountID: accountA,
                    requestedAfter: nil,
                    cursor: "unneeded-full-snapshot",
                    moreComing: false
                )
            )
        )

        do {
            try await store.saveReconstructedFullSnapshot(
                candidate,
                replacing: acceptedHistory,
                at: Date(timeIntervalSince1970: 3_123)
            )
            XCTFail("Recovery must not replace a usable accepted checkpoint")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .acceptedCheckpointStillAvailable
            )
        }
    }

    func testFullSnapshotRecoveryRejectsIncompatiblePendingPublication()
        async throws
    {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fileSystem = FaultInjectingCheckpointFileSystem()
        let store = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root,
            fileSystem: fileSystem
        )
        let first = try checkpoint(modifications: [])
        try await store.activate(
            replicaEpoch: epoch,
            configurationScopeFingerprint: scopeFingerprint(),
            for: accountA
        )
        try await store.save(first, at: Date(timeIntervalSince1970: 3_124))
        let resume = try await store.resumeActiveReplicaEpoch(
            for: accountA,
            configurationScopeFingerprint: scopeFingerprint()
        )
        let acceptedHistory = try XCTUnwrap(resume?.acceptedHistory)
        var firstRecovery = CloudReplicaStagedAccumulator(
            reconstructingFullSnapshotFrom: acceptedHistory
        )
        let pendingCandidate = try XCTUnwrap(
            firstRecovery.apply(
                page(
                    accountID: accountA,
                    modifications: [
                        discovered(id: "pending", locator: "provider-pending"),
                    ],
                    requestedAfter: nil,
                    cursor: "pending-full-snapshot",
                    moreComing: false
                )
            )
        )
        var divergentRecovery = CloudReplicaStagedAccumulator(
            reconstructingFullSnapshotFrom: acceptedHistory
        )
        let divergentCandidate = try XCTUnwrap(
            divergentRecovery.apply(
                page(
                    accountID: accountA,
                    modifications: [
                        discovered(id: "divergent", locator: "provider-divergent"),
                    ],
                    requestedAfter: nil,
                    cursor: "divergent-full-snapshot",
                    moreComing: false
                )
            )
        )
        fileSystem.failNextWrite(named: "checkpoint.watermark.json")
        do {
            try await store.save(
                pendingCandidate,
                at: Date(timeIntervalSince1970: 3_125)
            )
            XCTFail("The injected pending publication must fail")
        } catch {
            XCTAssertEqual(error as? CloudReplicaCheckpointStoreError, .ioFailure)
        }
        let locations = storageLocations(root: root, accountID: accountA)
        try FoundationCloudReplicaCheckpointFileSystem().removeItem(
            at: locations.directory
        )

        do {
            try await store.saveReconstructedFullSnapshot(
                divergentCandidate,
                replacing: acceptedHistory,
                at: Date(timeIntervalSince1970: 3_126)
            )
            XCTFail("An incompatible durable pending intent must fail closed")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .checkpointPublicationPending
            )
        }
        try await store.saveReconstructedFullSnapshot(
            pendingCandidate,
            replacing: acceptedHistory,
            at: Date(timeIntervalSince1970: 3_127)
        )
        let loaded = try await store.load(
            for: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            at: Date(timeIntervalSince1970: 3_128)
        )
        XCTAssertEqual(loaded.checkpoint, pendingCandidate)
    }

    func testFullSnapshotRecoveryRejectsWrongBindingsAndRevokedAuthority()
        async throws
    {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let staleStore = AtomicCloudReplicaCheckpointDiskStore(rootDirectoryURL: root)
        let first = try checkpoint(modifications: [])
        try await staleStore.activate(
            replicaEpoch: epoch,
            configurationScopeFingerprint: scopeFingerprint(),
            for: accountA
        )
        try await staleStore.save(first, at: Date(timeIntervalSince1970: 3_133))
        let resume = try await staleStore.resumeActiveReplicaEpoch(
            for: accountA,
            configurationScopeFingerprint: scopeFingerprint()
        )
        let acceptedHistory = try XCTUnwrap(resume?.acceptedHistory)
        var reconstruction = CloudReplicaStagedAccumulator(
            reconstructingFullSnapshotFrom: acceptedHistory
        )
        let candidate = try XCTUnwrap(
            reconstruction.apply(
                page(
                    accountID: accountA,
                    requestedAfter: nil,
                    cursor: "binding-full-snapshot",
                    moreComing: false
                )
            )
        )
        let wrongScope = try CloudReplicaCheckpointV1(
            accountID: accountA,
            configurationScopeFingerprint: alternateScopeFingerprint(),
            generation: candidate.generation,
            finalCursor: candidate.finalCursor,
            recordsByLogicalID: candidate.recordsByLogicalID,
            providerLocatorByLogicalID: candidate.providerLocatorByLogicalID,
            logicalIDByProviderLocator: candidate.logicalIDByProviderLocator,
            tombstonesByProviderLocator: candidate.tombstonesByProviderLocator,
            replicaEpoch: epoch
        )
        do {
            try await staleStore.saveReconstructedFullSnapshot(
                wrongScope,
                replacing: acceptedHistory,
                at: Date(timeIntervalSince1970: 3_134)
            )
            XCTFail("A recovery token cannot authorize another scope")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .acceptedHistoryMismatch
            )
        }
        let wrongEpoch = try CloudReplicaCheckpointV1(
            accountID: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            generation: candidate.generation,
            finalCursor: candidate.finalCursor,
            recordsByLogicalID: candidate.recordsByLogicalID,
            providerLocatorByLogicalID: candidate.providerLocatorByLogicalID,
            logicalIDByProviderLocator: candidate.logicalIDByProviderLocator,
            tombstonesByProviderLocator: candidate.tombstonesByProviderLocator,
            replicaEpoch: UUID()
        )
        do {
            try await staleStore.saveReconstructedFullSnapshot(
                wrongEpoch,
                replacing: acceptedHistory,
                at: Date(timeIntervalSince1970: 3_135)
            )
            XCTFail("A recovery token cannot authorize another epoch")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .acceptedHistoryMismatch
            )
        }

        try await AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root
        ).remove(for: accountA, revoking: epoch)
        do {
            try await staleStore.saveReconstructedFullSnapshot(
                candidate,
                replacing: acceptedHistory,
                at: Date(timeIntervalSince1970: 3_136)
            )
            XCTFail("A revoked authority must reject recovery")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .replicaEpochRevoked
            )
        }
    }

    func testResumeItemStatusFailureFailsClosedWithoutMutation() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fileSystem = FaultInjectingCheckpointFileSystem()
        let store = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root,
            fileSystem: fileSystem
        )
        try await store.activate(replicaEpoch: epoch, configurationScopeFingerprint: scopeFingerprint(), for: accountA)
        let locations = storageLocations(root: root, accountID: accountA)
        let authorityBefore = try Data(contentsOf: locations.authority)
        fileSystem.failNextItemStatus(named: "replica-authority.json")

        do {
            _ = try await store.resumeActiveReplicaEpoch(for: accountA, configurationScopeFingerprint: scopeFingerprint())
            XCTFail("An indeterminate authority status must not become absence")
        } catch {
            XCTAssertEqual(error as? CloudReplicaCheckpointStoreError, .ioFailure)
        }
        XCTAssertEqual(try Data(contentsOf: locations.authority), authorityBefore)
        XCTAssertFalse(FileManager.default.fileExists(atPath: locations.directory.path))
    }

    func testLoadItemStatusFailureFailsClosedWithoutMutatingReplicaEvidence()
        async throws
    {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fileSystem = FaultInjectingCheckpointFileSystem()
        let store = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root,
            fileSystem: fileSystem
        )
        let expected = try checkpoint(modifications: [])
        try await store.activate(replicaEpoch: epoch, configurationScopeFingerprint: scopeFingerprint(), for: accountA)
        try await store.save(expected, at: Date(timeIntervalSince1970: 3_105))
        let locations = storageLocations(root: root, accountID: accountA)
        let primaryBefore = try Data(contentsOf: locations.primary)
        let backupBefore = try Data(contentsOf: locations.backup)
        let watermarkBefore = try Data(contentsOf: locations.watermark)
        let authorityBefore = try Data(contentsOf: locations.authority)
        fileSystem.failNextItemStatus(named: "checkpoint.json")

        do {
            _ = try await store.load(
                for: accountA,
                configurationScopeFingerprint: scopeFingerprint(),
                at: Date(timeIntervalSince1970: 3_106)
            )
            XCTFail("An indeterminate primary status must fail closed")
        } catch {
            XCTAssertEqual(error as? CloudReplicaCheckpointStoreError, .ioFailure)
        }
        XCTAssertEqual(try Data(contentsOf: locations.primary), primaryBefore)
        XCTAssertEqual(try Data(contentsOf: locations.backup), backupBefore)
        XCTAssertEqual(try Data(contentsOf: locations.watermark), watermarkBefore)
        XCTAssertEqual(try Data(contentsOf: locations.authority), authorityBefore)
        XCTAssertFalse(FileManager.default.fileExists(atPath: locations.quarantine.path))
    }

    func testDurabilityOutcomeUnknownIsReconciledBeforePublicationAdvances()
        async throws
    {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fileSystem = FaultInjectingCheckpointFileSystem()
        let writer = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root,
            fileSystem: fileSystem
        )
        let first = try checkpoint(modifications: [])
        try await writer.activate(
            replicaEpoch: epoch,
            configurationScopeFingerprint: scopeFingerprint(),
            for: accountA
        )
        let reconciliationsBefore = fileSystem.durableReconciliationCount(
            named: "checkpoint.watermark.json"
        )
        fileSystem.failAfterNextWrite(named: "checkpoint.watermark.json")
        try await writer.save(first, at: Date(timeIntervalSince1970: 3_107))
        XCTAssertGreaterThan(
            fileSystem.durableReconciliationCount(
                named: "checkpoint.watermark.json"
            ),
            reconciliationsBefore
        )
        XCTAssertEqual(fileSystem.unresolvedDurabilityPathCount(), 0)

        let relaunched = AtomicCloudReplicaCheckpointDiskStore(rootDirectoryURL: root)
        let resumedValue = try await relaunched.resumeActiveReplicaEpoch(
            for: accountA,
            configurationScopeFingerprint: scopeFingerprint()
        )
        let resumed = try XCTUnwrap(resumedValue)
        XCTAssertTrue(resumed.hasAcceptedCheckpoint)
        XCTAssertFalse(resumed.hasDurableCheckpointIntent)
        let recovered = try await relaunched.load(
            for: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            at: Date(timeIntervalSince1970: 3_108)
        )
        XCTAssertEqual(recovered.checkpoint, first)
    }

    func testAuthorityActivationPromotionAndRevocationReconcileUnknownWrites()
        async throws
    {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fileSystem = FaultInjectingCheckpointFileSystem()
        let store = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root,
            fileSystem: fileSystem
        )
        var reconciliationCount = fileSystem.durableReconciliationCount(
            named: "replica-authority.json"
        )

        fileSystem.failAfterNextWrite(named: "replica-authority.json")
        try await store.activate(
            replicaEpoch: epoch,
            configurationScopeFingerprint: scopeFingerprint(),
            for: accountA
        )
        XCTAssertGreaterThan(
            fileSystem.durableReconciliationCount(
                named: "replica-authority.json"
            ),
            reconciliationCount
        )
        XCTAssertEqual(fileSystem.unresolvedDurabilityPathCount(), 0)

        let first = try checkpoint(modifications: [])
        reconciliationCount = fileSystem.durableReconciliationCount(
            named: "replica-authority.json"
        )
        fileSystem.failAfterWrite(
            named: "replica-authority.json",
            afterSuccessfulMatchingWrites: 1
        )
        try await store.save(first, at: Date(timeIntervalSince1970: 3_113))
        XCTAssertGreaterThan(
            fileSystem.durableReconciliationCount(
                named: "replica-authority.json"
            ),
            reconciliationCount
        )
        XCTAssertEqual(fileSystem.unresolvedDurabilityPathCount(), 0)

        reconciliationCount = fileSystem.durableReconciliationCount(
            named: "replica-authority.json"
        )
        let locations = storageLocations(root: root, accountID: accountA)
        let directoryReconciliationsBefore = fileSystem.durableReconciliationCount(
            named: locations.directory.lastPathComponent
        )
        fileSystem.failAfterNextWrite(named: "replica-authority.json")
        fileSystem.failAfterNextRemove(named: locations.directory.lastPathComponent)
        try await store.remove(for: accountA, revoking: epoch)
        XCTAssertGreaterThan(
            fileSystem.durableReconciliationCount(
                named: "replica-authority.json"
            ),
            reconciliationCount
        )
        XCTAssertGreaterThan(
            fileSystem.durableReconciliationCount(
                named: locations.directory.lastPathComponent
            ),
            directoryReconciliationsBefore
        )
        XCTAssertEqual(fileSystem.unresolvedDurabilityPathCount(), 0)
        let resumed = try await AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root
        ).resumeActiveReplicaEpoch(
            for: accountA,
            configurationScopeFingerprint: scopeFingerprint()
        )
        XCTAssertNil(resumed)
    }

    func testAncestorDirectoryCreationRetryReconcilesExistingChain()
        async throws
    {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fileSystem = FaultInjectingCheckpointFileSystem()
        let store = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root,
            fileSystem: fileSystem
        )
        let locations = storageLocations(root: root, accountID: accountA)
        let directoryName = locations.authorityDirectory.lastPathComponent
        fileSystem.failAfterNextCreate(named: directoryName)
        do {
            try await store.activate(
                replicaEpoch: epoch,
                configurationScopeFingerprint: scopeFingerprint(),
                for: accountA
            )
            XCTFail("The modeled post-create durability fault must surface")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .durabilityOutcomeUnknown
            )
        }
        XCTAssertGreaterThan(fileSystem.unresolvedDurabilityPathCount(), 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: locations.authority.path))
        let reconciliationsBefore = fileSystem.durableReconciliationCount(
            named: directoryName
        )

        try await store.activate(
            replicaEpoch: epoch,
            configurationScopeFingerprint: scopeFingerprint(),
            for: accountA
        )
        XCTAssertGreaterThan(
            fileSystem.durableReconciliationCount(named: directoryName),
            reconciliationsBefore
        )
        XCTAssertEqual(fileSystem.unresolvedDurabilityPathCount(), 0)
    }

    func testRememberedEpochRejectsDurablyMissingAuthority() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AtomicCloudReplicaCheckpointDiskStore(rootDirectoryURL: root)
        try await store.activate(
            replicaEpoch: epoch,
            configurationScopeFingerprint: scopeFingerprint(),
            for: accountA
        )
        let locations = storageLocations(root: root, accountID: accountA)
        try FoundationCloudReplicaCheckpointFileSystem().removeItem(
            at: locations.authority
        )

        do {
            _ = try await store.resumeActiveReplicaEpoch(
                for: accountA,
                configurationScopeFingerprint: scopeFingerprint()
            )
            XCTFail("Remembered ownership must not turn missing authority into genesis")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .replicaEpochNotActive
            )
        }
    }

    func testResumeSerializesBehindConcurrentRevocation() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fileSystem = FaultInjectingCheckpointFileSystem()
        let owner = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root,
            fileSystem: fileSystem
        )
        let revoker = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root,
            fileSystem: fileSystem
        )
        let observer = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root,
            fileSystem: fileSystem
        )
        try await owner.activate(
            replicaEpoch: epoch,
            configurationScopeFingerprint: scopeFingerprint(),
            for: accountA
        )
        let attemptsBefore = fileSystem.exclusiveLockAttemptCount()
        fileSystem.blockNextWrite(named: "replica-authority.json")
        defer { fileSystem.releaseBlockedWrite() }
        let revokeTask = Task {
            try await revoker.remove(for: self.accountA, revoking: self.epoch)
        }
        let revocationReachedAuthorityWrite = await waitUntil {
            fileSystem.isBlockedWriteWaiting()
        }
        XCTAssertTrue(revocationReachedAuthorityWrite)
        let resumeTask = Task {
            try await observer.resumeActiveReplicaEpoch(
                for: self.accountA,
                configurationScopeFingerprint: self.scopeFingerprint()
            )
        }
        let resumeAttemptedLock = await waitUntil {
            fileSystem.exclusiveLockAttemptCount() >= attemptsBefore + 2
        }
        XCTAssertTrue(resumeAttemptedLock)

        fileSystem.releaseBlockedWrite()
        try await revokeTask.value
        let resumed = try await resumeTask.value
        XCTAssertNil(resumed)
    }

    func testFoundationCheckpointFileSystemDurableFileLifecycle() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fileSystem = FoundationCloudReplicaCheckpointFileSystem()
        let source = root
            .appendingPathComponent("nested", isDirectory: true)
            .appendingPathComponent("authority.json")
        let destination = source.deletingLastPathComponent()
            .appendingPathComponent("authority.previous.json")

        try fileSystem.writeAtomically(Data("first".utf8), to: source)
        let boundedTemporary = source.deletingLastPathComponent()
            .appendingPathComponent(".pocket-vector-checkpoint-write.tmp")
        try Data("stale".utf8).write(to: boundedTemporary)
        try fileSystem.writeAtomically(Data("second".utf8), to: source)
        XCTAssertEqual(try fileSystem.read(from: source), Data("second".utf8))
        try fileSystem.moveItem(at: source, to: destination)
        XCTAssertEqual(try fileSystem.itemStatus(at: source), .missing)
        XCTAssertEqual(try fileSystem.itemStatus(at: destination), .present)
        XCTAssertEqual(try fileSystem.read(from: destination), Data("second".utf8))
        try fileSystem.removeItem(at: destination)
        XCTAssertEqual(try fileSystem.itemStatus(at: destination), .missing)
        XCTAssertTrue(
            try FileManager.default.contentsOfDirectory(
                at: source.deletingLastPathComponent(),
                includingPropertiesForKeys: nil
            ).isEmpty,
            "Durable atomic writes must not leave temporary artifacts"
        )
    }

    func testFoundationCheckpointFileSystemRejectsOutsideDurabilityBoundaryBeforeMutation()
        throws
    {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let boundary = root.appendingPathComponent("durable-root", isDirectory: true)
        try FileManager.default.createDirectory(
            at: boundary,
            withIntermediateDirectories: true
        )
        let fileSystem = FoundationCloudReplicaCheckpointFileSystem(
            durabilityBoundaryURL: boundary
        )

        XCTAssertEqual(try fileSystem.reconcileDurableItem(at: boundary), .present)
        let inside = boundary.appendingPathComponent("nested", isDirectory: true)
            .appendingPathComponent("checkpoint.json")
        try fileSystem.writeAtomically(Data("checkpoint".utf8), to: inside)
        XCTAssertEqual(try fileSystem.reconcileDurableItem(at: inside), .present)

        let outside = root.appendingPathComponent("durable-root-sibling", isDirectory: true)
            .appendingPathComponent("must-not-exist", isDirectory: true)
        XCTAssertThrowsError(try fileSystem.createDirectory(at: outside)) { error in
            XCTAssertEqual(error as? CloudReplicaCheckpointStoreError, .ioFailure)
        }
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent("durable-root-sibling").path
            )
        )
    }

    func testFoundationCheckpointFileSystemRequiresPreexistingDurabilityBoundary() {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let missingBoundary = root
            .appendingPathComponent("missing", isDirectory: true)
            .appendingPathComponent("durable-root", isDirectory: true)
        let fileSystem = FoundationCloudReplicaCheckpointFileSystem(
            durabilityBoundaryURL: missingBoundary
        )
        let target = missingBoundary
            .appendingPathComponent("nested", isDirectory: true)
            .appendingPathComponent("checkpoint.json")

        XCTAssertThrowsError(try fileSystem.writeAtomically(Data(), to: target)) { error in
            XCTAssertEqual(error as? CloudReplicaCheckpointStoreError, .ioFailure)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    func testFoundationCheckpointFileSystemSynchronizesTwoParentRename() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fileSystem = FoundationCloudReplicaCheckpointFileSystem()
        let source = root.appendingPathComponent("source", isDirectory: true)
            .appendingPathComponent("checkpoint.json")
        let destination = root.appendingPathComponent("destination", isDirectory: true)
            .appendingPathComponent("checkpoint.json")
        try fileSystem.writeAtomically(Data("checkpoint".utf8), to: source)
        try fileSystem.createDirectory(at: destination.deletingLastPathComponent())

        try fileSystem.moveItem(at: source, to: destination)

        XCTAssertEqual(try fileSystem.reconcileDurableItem(at: source), .missing)
        XCTAssertEqual(
            try fileSystem.reconcileDurableItem(at: destination),
            .present
        )
        XCTAssertEqual(try fileSystem.read(from: destination), Data("checkpoint".utf8))
    }

    func testFoundationDirectoryRemovalTombstonesAreTargetBound() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fileSystem = FoundationCloudReplicaCheckpointFileSystem()
        let left = root.appendingPathComponent("account-left", isDirectory: true)
        let right = root.appendingPathComponent("account-right", isDirectory: true)
        try fileSystem.writeAtomically(
            Data("left".utf8),
            to: left.appendingPathComponent("checkpoint.json")
        )
        try fileSystem.writeAtomically(
            Data("right".utf8),
            to: right.appendingPathComponent("checkpoint.json")
        )

        let leftRemoval = Task { try fileSystem.removeItem(at: left) }
        let rightRemoval = Task { try fileSystem.removeItem(at: right) }
        try await leftRemoval.value
        try await rightRemoval.value

        XCTAssertEqual(try fileSystem.reconcileDurableItem(at: left), .missing)
        XCTAssertEqual(try fileSystem.reconcileDurableItem(at: right), .missing)
        let residue = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        )
        XCTAssertFalse(
            residue.contains {
                $0.lastPathComponent.hasPrefix(
                    ".pocket-vector-checkpoint-remove-"
                )
            }
        )
    }

    func testMissingAccountDirectoryRetryClearsOnlyItsTargetBoundTombstone()
        async throws
    {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let recursiveRemoval = FailNextRecursiveDirectoryRemovals(count: 0)
        let fileSystem = FoundationCloudReplicaCheckpointFileSystem(
            recursivelyRemoveDirectory: { url in
                try recursiveRemoval.removeItem(at: url)
            }
        )
        let store = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root,
            fileSystem: fileSystem
        )
        let checkpointA = try checkpoint(modifications: [])
        let checkpointB = try checkpoint(accountID: accountB, modifications: [])
        try await store.activate(
            replicaEpoch: checkpointA.replicaEpoch,
            configurationScopeFingerprint: scopeFingerprint(),
            for: accountA
        )
        try await store.activate(
            replicaEpoch: checkpointB.replicaEpoch,
            configurationScopeFingerprint: scopeFingerprint(),
            for: accountB
        )
        try await store.save(checkpointA, at: Date(timeIntervalSince1970: 3_130))
        try await store.save(checkpointB, at: Date(timeIntervalSince1970: 3_131))
        let locationsA = storageLocations(root: root, accountID: accountA)
        let locationsB = storageLocations(root: root, accountID: accountB)
        let tombstoneA = directoryRemovalTombstone(for: locationsA.directory)
        let tombstoneB = directoryRemovalTombstone(for: locationsB.directory)

        recursiveRemoval.failNext(count: 2)
        try await store.remove(for: accountA, revoking: checkpointA.replicaEpoch)
        try await store.remove(for: accountB, revoking: checkpointB.replicaEpoch)
        XCTAssertEqual(
            recursiveRemoval.attemptedPaths(),
            [tombstoneA.path, tombstoneB.path]
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: locationsA.directory.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: locationsB.directory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: tombstoneA.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: tombstoneB.path))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: tombstoneA.appendingPathComponent("checkpoint.json").path
            ),
            "A completed rename must hide the whole account while retaining bounded cleanup residue"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: tombstoneB.appendingPathComponent("checkpoint.json").path
            )
        )
        let accountsDirectory = locationsA.directory.deletingLastPathComponent()
        let boundedResidue = try FileManager.default.contentsOfDirectory(
            at: accountsDirectory,
            includingPropertiesForKeys: nil
        ).filter {
            $0.lastPathComponent.hasPrefix(
                ".pocket-vector-checkpoint-remove-"
            )
        }
        XCTAssertEqual(Set(boundedResidue), Set([tombstoneA, tombstoneB]))

        let replacementEpochA = UUID(
            uuidString: "A0000000-0000-4000-8000-000000000001"
        )!
        try await store.activate(
            replicaEpoch: replacementEpochA,
            configurationScopeFingerprint: scopeFingerprint(),
            for: accountA
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: tombstoneA.path))
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: tombstoneB.path),
            "Account A cleanup must not consume account B's bounded tombstone"
        )

        let replacementA = try checkpoint(
            replicaEpoch: replacementEpochA,
            modifications: []
        )
        try await store.save(
            replacementA,
            at: Date(timeIntervalSince1970: 3_132)
        )
        try await store.remove(for: accountA, revoking: replacementEpochA)
        XCTAssertFalse(FileManager.default.fileExists(atPath: locationsA.directory.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: tombstoneA.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: tombstoneB.path))
    }

    func testMissingWatermarkChoosesNewestOfTwoValidGenerations() async throws {
        let root = temporaryDirectory()
        let oldRoot = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: oldRoot)
        }
        let first = try checkpoint(modifications: [])
        var accumulator = try self.accumulator(from: first)
        let second = try XCTUnwrap(
            accumulator.apply(
                page(
                    accountID: accountA,
                    requestedAfter: "seed-cursor",
                    cursor: "newer-cursor",
                    moreComing: false
                )
            )
        )

        let currentStore = AtomicCloudReplicaCheckpointDiskStore(rootDirectoryURL: root)
        try await currentStore.activate(replicaEpoch: first.replicaEpoch, configurationScopeFingerprint: scopeFingerprint(), for: accountA)
        try await currentStore.save(first, at: Date(timeIntervalSince1970: 3_150))
        try await currentStore.save(second, at: Date(timeIntervalSince1970: 3_151))

        let oldStore = AtomicCloudReplicaCheckpointDiskStore(rootDirectoryURL: oldRoot)
        try await oldStore.activate(replicaEpoch: first.replicaEpoch, configurationScopeFingerprint: scopeFingerprint(), for: accountA)
        try await oldStore.save(first, at: Date(timeIntervalSince1970: 3_149))

        let currentLocations = storageLocations(root: root, accountID: accountA)
        let oldLocations = storageLocations(root: oldRoot, accountID: accountA)
        try FileManager.default.removeItem(at: currentLocations.watermark)
        try FileManager.default.removeItem(at: currentLocations.authority)
        try FileManager.default.removeItem(at: currentLocations.primary)
        try FileManager.default.copyItem(
            at: oldLocations.primary,
            to: currentLocations.primary
        )

        let relaunched = AtomicCloudReplicaCheckpointDiskStore(rootDirectoryURL: root)
        let loaded = try await relaunched.load(
            for: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            at: Date(timeIntervalSince1970: 3_152)
        )
        XCTAssertEqual(loaded.checkpoint, second)
        XCTAssertEqual(loaded.source, .backup)
        XCTAssertEqual(loaded.quarantinedFileCount, 1)
        XCTAssertEqual(
            try Data(contentsOf: currentLocations.primary),
            try Data(contentsOf: currentLocations.backup)
        )
    }

    func testFreshAuthorityDiscardsOrphanWatermarkWithoutMatchingCopy()
        async throws
    {
        let root = temporaryDirectory()
        let orphanRoot = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: orphanRoot)
        }
        let orphan = try checkpoint(
            modifications: [discovered(id: "orphan", locator: "provider-orphan")]
        )
        let replacement = try checkpoint(
            modifications: [
                discovered(id: "replacement", locator: "provider-replacement"),
            ]
        )
        let orphanStore = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: orphanRoot
        )
        try await orphanStore.activate(
            replicaEpoch: orphan.replicaEpoch,
            configurationScopeFingerprint: scopeFingerprint(),
            for: accountA
        )
        try await orphanStore.save(orphan, at: Date(timeIntervalSince1970: 3_160))

        let freshStore = AtomicCloudReplicaCheckpointDiskStore(rootDirectoryURL: root)
        try await freshStore.activate(
            replicaEpoch: replacement.replicaEpoch,
            configurationScopeFingerprint: scopeFingerprint(),
            for: accountA
        )
        let locations = storageLocations(root: root, accountID: accountA)
        let orphanLocations = storageLocations(root: orphanRoot, accountID: accountA)
        try FileManager.default.createDirectory(
            at: locations.directory,
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(
            at: orphanLocations.watermark,
            to: locations.watermark
        )

        let relaunched = AtomicCloudReplicaCheckpointDiskStore(rootDirectoryURL: root)
        let empty = try await relaunched.load(
            for: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            at: Date(timeIntervalSince1970: 3_161)
        )
        XCTAssertNil(empty.checkpoint)
        XCTAssertFalse(FileManager.default.fileExists(atPath: locations.directory.path))

        try await relaunched.activate(
            replicaEpoch: replacement.replicaEpoch,
            configurationScopeFingerprint: scopeFingerprint(),
            for: accountA
        )
        try await relaunched.save(
            replacement,
            at: Date(timeIntervalSince1970: 3_162)
        )
        let loaded = try await relaunched.load(
            for: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            at: Date(timeIntervalSince1970: 3_163)
        )
        XCTAssertEqual(loaded.checkpoint, replacement)
    }

    func testFreshAuthorityDiscardsCorruptWatermarkAndOrphanCopiesBeforeSave()
        async throws
    {
        let root = temporaryDirectory()
        let orphanRoot = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: orphanRoot)
        }
        let orphan = try checkpoint(
            modifications: [discovered(id: "orphan", locator: "provider-orphan")]
        )
        let replacement = try checkpoint(
            modifications: [
                discovered(id: "replacement", locator: "provider-replacement"),
            ]
        )
        let orphanStore = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: orphanRoot
        )
        try await orphanStore.activate(
            replicaEpoch: orphan.replicaEpoch,
            configurationScopeFingerprint: scopeFingerprint(),
            for: accountA
        )
        try await orphanStore.save(orphan, at: Date(timeIntervalSince1970: 3_170))

        let freshStore = AtomicCloudReplicaCheckpointDiskStore(rootDirectoryURL: root)
        try await freshStore.activate(
            replicaEpoch: replacement.replicaEpoch,
            configurationScopeFingerprint: scopeFingerprint(),
            for: accountA
        )
        let locations = storageLocations(root: root, accountID: accountA)
        let orphanLocations = storageLocations(root: orphanRoot, accountID: accountA)
        try FileManager.default.createDirectory(
            at: locations.directory,
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(
            at: orphanLocations.primary,
            to: locations.primary
        )
        try FileManager.default.copyItem(
            at: orphanLocations.backup,
            to: locations.backup
        )
        try Data("corrupt-orphan-watermark".utf8).write(
            to: locations.watermark,
            options: .atomic
        )

        try await freshStore.save(
            replacement,
            at: Date(timeIntervalSince1970: 3_171)
        )
        let loaded = try await freshStore.load(
            for: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            at: Date(timeIntervalSince1970: 3_172)
        )
        XCTAssertEqual(loaded.checkpoint, replacement)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: locations.quarantine
                    .appendingPathComponent("checkpoint-watermark-corrupt.json").path
            )
        )
    }

    func testMissingAuthorityClearsUnownedCacheBeforePublishingNewEpoch()
        async throws
    {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let oldCheckpoint = try checkpoint(modifications: [])
        let writer = AtomicCloudReplicaCheckpointDiskStore(rootDirectoryURL: root)
        try await writer.activate(
            replicaEpoch: oldCheckpoint.replicaEpoch,
            configurationScopeFingerprint: scopeFingerprint(),
            for: accountA
        )
        try await writer.save(
            oldCheckpoint,
            at: Date(timeIntervalSince1970: 3_180)
        )
        let locations = storageLocations(root: root, accountID: accountA)
        try FileManager.default.removeItem(at: locations.authority)

        let newEpoch = UUID(uuidString: "BBBBBBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF")!
        let replacement = try checkpoint(
            replicaEpoch: newEpoch,
            modifications: [
                discovered(id: "new-epoch", locator: "provider-new-epoch"),
            ]
        )
        let fileSystem = FaultInjectingCheckpointFileSystem()
        let rotator = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root,
            fileSystem: fileSystem
        )
        fileSystem.failNextWrite(named: "replica-authority.json")
        do {
            try await rotator.activate(replicaEpoch: newEpoch, configurationScopeFingerprint: scopeFingerprint(), for: accountA)
            XCTFail("The injected authority publication must fail")
        } catch {
            XCTAssertEqual(error as? CloudReplicaCheckpointStoreError, .ioFailure)
        }
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: locations.directory.path),
            "Unowned cache must be cleared before new authority is published"
        )

        try await rotator.activate(replicaEpoch: newEpoch, configurationScopeFingerprint: scopeFingerprint(), for: accountA)
        try await rotator.save(
            replacement,
            at: Date(timeIntervalSince1970: 3_181)
        )
        let loaded = try await rotator.load(
            for: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            at: Date(timeIntervalSince1970: 3_182)
        )
        XCTAssertEqual(loaded.checkpoint, replacement)
    }

    func testStaleActivatedStoreCannotMutateCheckpointAfterEpochRotation()
        async throws
    {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let oldCheckpoint = try checkpoint(modifications: [])
        let staleStore = AtomicCloudReplicaCheckpointDiskStore(rootDirectoryURL: root)
        try await staleStore.activate(
            replicaEpoch: oldCheckpoint.replicaEpoch,
            configurationScopeFingerprint: scopeFingerprint(),
            for: accountA
        )
        try await staleStore.save(
            oldCheckpoint,
            at: Date(timeIntervalSince1970: 3_190)
        )

        let newEpoch = UUID(uuidString: "CCCCCCCC-DDDD-EEEE-FFFF-AAAAAAAAAAAA")!
        let replacement = try checkpoint(
            replicaEpoch: newEpoch,
            modifications: [
                discovered(id: "rotated", locator: "provider-rotated"),
            ]
        )
        let rotator = AtomicCloudReplicaCheckpointDiskStore(rootDirectoryURL: root)
        try await rotator.remove(
            for: accountA,
            revoking: oldCheckpoint.replicaEpoch
        )
        try await rotator.activate(replicaEpoch: newEpoch, configurationScopeFingerprint: scopeFingerprint(), for: accountA)
        try await rotator.save(
            replacement,
            at: Date(timeIntervalSince1970: 3_191)
        )
        let locations = storageLocations(root: root, accountID: accountA)
        let primaryBefore = try Data(contentsOf: locations.primary)
        let backupBefore = try Data(contentsOf: locations.backup)
        let watermarkBefore = try Data(contentsOf: locations.watermark)

        do {
            _ = try await staleStore.load(
                for: accountA,
                configurationScopeFingerprint: scopeFingerprint(),
                at: Date(timeIntervalSince1970: 3_192)
            )
            XCTFail("A stale activated store must reject the rotated authority")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .replicaEpochRevoked
            )
        }
        XCTAssertEqual(try Data(contentsOf: locations.primary), primaryBefore)
        XCTAssertEqual(try Data(contentsOf: locations.backup), backupBefore)
        XCTAssertEqual(try Data(contentsOf: locations.watermark), watermarkBefore)

        let loaded = try await AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root
        ).load(
            for: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            at: Date(timeIntervalSince1970: 3_193)
        )
        XCTAssertEqual(loaded.checkpoint, replacement)
    }

    func testPendingGenerationFallsBackWhenItsOnlyPublishedCopyIsCorrupt() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fileSystem = FaultInjectingCheckpointFileSystem()
        let store = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root,
            fileSystem: fileSystem
        )
        let first = try checkpoint(
            modifications: [discovered(id: "profile", locator: "provider-profile")]
        )
        try await store.activate(replicaEpoch: first.replicaEpoch, configurationScopeFingerprint: scopeFingerprint(), for: accountA)
        try await store.save(first, at: Date(timeIntervalSince1970: 3_200))

        var accumulator = try self.accumulator(from: first)
        let second = try XCTUnwrap(
            accumulator.apply(
                page(
                    accountID: accountA,
                    modifications: [
                        discovered(
                            id: "profile",
                            locator: "provider-profile",
                            value: "generation-two"
                        ),
                    ],
                    requestedAfter: "seed-cursor",
                    cursor: "generation-two-cursor",
                    moreComing: false
                )
            )
        )
        fileSystem.failNextWrite(named: "checkpoint.backup.json")
        do {
            try await store.save(second, at: Date(timeIntervalSince1970: 3_201))
            XCTFail("The injected backup write must fail")
        } catch {
            XCTAssertEqual(error as? CloudReplicaCheckpointStoreError, .ioFailure)
        }

        let locations = storageLocations(root: root, accountID: accountA)
        try Data("corrupt-newer-primary".utf8).write(to: locations.primary, options: .atomic)
        let recovered = try await store.load(
            for: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            at: Date(timeIntervalSince1970: 3_202)
        )
        XCTAssertEqual(recovered.checkpoint, first)
        XCTAssertEqual(recovered.source, .backup)
        XCTAssertEqual(recovered.quarantinedFileCount, 1)
        XCTAssertEqual(
            try Data(contentsOf: locations.primary),
            try Data(contentsOf: locations.backup)
        )
    }

    func testPendingGenerationRollsForwardFromOneMatchingCopyAfterCrash() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fileSystem = FaultInjectingCheckpointFileSystem()
        let store = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root,
            fileSystem: fileSystem
        )
        let first = try checkpoint(modifications: [])
        try await store.activate(replicaEpoch: first.replicaEpoch, configurationScopeFingerprint: scopeFingerprint(), for: accountA)
        try await store.save(first, at: Date(timeIntervalSince1970: 3_225))

        var accumulator = try self.accumulator(from: first)
        let second = try XCTUnwrap(
            accumulator.apply(
                page(
                    accountID: accountA,
                    requestedAfter: "seed-cursor",
                    cursor: "generation-two-primary-only",
                    moreComing: false
                )
            )
        )
        fileSystem.failNextWrite(named: "checkpoint.backup.json")
        do {
            try await store.save(second, at: Date(timeIntervalSince1970: 3_226))
            XCTFail("The injected backup write must interrupt publication")
        } catch {
            XCTAssertEqual(error as? CloudReplicaCheckpointStoreError, .ioFailure)
        }

        let relaunched = AtomicCloudReplicaCheckpointDiskStore(rootDirectoryURL: root)
        let recovered = try await relaunched.load(
            for: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            at: Date(timeIntervalSince1970: 3_227)
        )
        XCTAssertEqual(recovered.checkpoint, second)
        XCTAssertEqual(recovered.source, .primary)
        XCTAssertEqual(recovered.quarantinedFileCount, 0)

        let locations = storageLocations(root: root, accountID: accountA)
        XCTAssertEqual(
            try Data(contentsOf: locations.primary),
            try Data(contentsOf: locations.backup)
        )
        let verified = try await AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root
        ).load(
            for: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            at: Date(timeIntervalSince1970: 3_228)
        )
        XCTAssertEqual(verified.checkpoint, second)
    }

    func testPendingGenerationRollsForwardAfterBothCopiesPrecedePromotion()
        async throws
    {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fileSystem = FaultInjectingCheckpointFileSystem()
        let store = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root,
            fileSystem: fileSystem
        )
        let first = try checkpoint(modifications: [])
        try await store.activate(replicaEpoch: first.replicaEpoch, configurationScopeFingerprint: scopeFingerprint(), for: accountA)
        try await store.save(first, at: Date(timeIntervalSince1970: 3_230))

        var accumulator = try self.accumulator(from: first)
        let second = try XCTUnwrap(
            accumulator.apply(
                page(
                    accountID: accountA,
                    requestedAfter: "seed-cursor",
                    cursor: "generation-two-before-promotion",
                    moreComing: false
                )
            )
        )
        fileSystem.failWrite(
            named: "replica-authority.json",
            afterSuccessfulMatchingWrites: 1
        )
        do {
            try await store.save(second, at: Date(timeIntervalSince1970: 3_231))
            XCTFail("The final authority promotion must be interrupted")
        } catch {
            XCTAssertEqual(error as? CloudReplicaCheckpointStoreError, .ioFailure)
        }

        let relaunched = AtomicCloudReplicaCheckpointDiskStore(rootDirectoryURL: root)
        let recovered = try await relaunched.load(
            for: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            at: Date(timeIntervalSince1970: 3_232)
        )
        XCTAssertEqual(recovered.checkpoint, second)
        XCTAssertEqual(recovered.source, .primary)
        XCTAssertEqual(recovered.quarantinedFileCount, 0)
        let verified = try await AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root
        ).load(
            for: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            at: Date(timeIntervalSince1970: 3_233)
        )
        XCTAssertEqual(verified.checkpoint, second)
    }

    func testPendingGenerationAllowsExactRetryButRejectsDivergentRetry() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fileSystem = FaultInjectingCheckpointFileSystem()
        let store = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root,
            fileSystem: fileSystem
        )
        let first = try checkpoint(modifications: [])
        try await store.activate(replicaEpoch: first.replicaEpoch, configurationScopeFingerprint: scopeFingerprint(), for: accountA)
        try await store.save(first, at: Date(timeIntervalSince1970: 3_235))

        var accumulator = try self.accumulator(from: first)
        let second = try XCTUnwrap(
            accumulator.apply(
                page(
                    accountID: accountA,
                    requestedAfter: "seed-cursor",
                    cursor: "retry-generation-two",
                    moreComing: false
                )
            )
        )
        var divergentAccumulator = try self.accumulator(from: first)
        let divergentSecond = try XCTUnwrap(
            divergentAccumulator.apply(
                page(
                    accountID: accountA,
                    requestedAfter: "seed-cursor",
                    cursor: "divergent-generation-two",
                    moreComing: false
                )
            )
        )

        fileSystem.failNextWrite(named: "checkpoint.json")
        do {
            try await store.save(second, at: Date(timeIntervalSince1970: 3_236))
            XCTFail("The injected primary write must interrupt publication")
        } catch {
            XCTAssertEqual(error as? CloudReplicaCheckpointStoreError, .ioFailure)
        }
        do {
            try await store.save(
                divergentSecond,
                at: Date(timeIntervalSince1970: 3_237)
            )
            XCTFail("A divergent retry of the pending generation must fail")
        } catch {
            XCTAssertEqual(error as? CloudReplicaCheckpointStoreError, .generationCollision)
        }

        try await store.save(second, at: Date(timeIntervalSince1970: 3_238))
        let recovered = try await store.load(
            for: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            at: Date(timeIntervalSince1970: 3_239)
        )
        XCTAssertEqual(recovered.checkpoint, second)
    }

    func testDivergentValidCopiesAtSameEpochAndGenerationAreBothRejected()
        async throws
    {
        let root = temporaryDirectory()
        let divergentRoot = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: divergentRoot)
        }
        let expected = try checkpoint(
            modifications: [discovered(id: "expected", locator: "provider-expected")]
        )
        let divergent = try checkpoint(
            modifications: [
                discovered(id: "divergent", locator: "provider-divergent"),
            ]
        )
        let store = AtomicCloudReplicaCheckpointDiskStore(rootDirectoryURL: root)
        try await store.activate(replicaEpoch: expected.replicaEpoch, configurationScopeFingerprint: scopeFingerprint(), for: accountA)
        try await store.save(expected, at: Date(timeIntervalSince1970: 3_240))
        let divergentStore = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: divergentRoot
        )
        try await divergentStore.activate(
            replicaEpoch: divergent.replicaEpoch,
            configurationScopeFingerprint: scopeFingerprint(),
            for: accountA
        )
        try await divergentStore.save(
            divergent,
            at: Date(timeIntervalSince1970: 3_241)
        )

        let locations = storageLocations(root: root, accountID: accountA)
        let divergentLocations = storageLocations(
            root: divergentRoot,
            accountID: accountA
        )
        try FileManager.default.removeItem(at: locations.backup)
        try FileManager.default.copyItem(
            at: divergentLocations.primary,
            to: locations.backup
        )
        let rejected = try await store.load(
            for: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            at: Date(timeIntervalSince1970: 3_242)
        )
        XCTAssertNil(rejected.checkpoint)
        XCTAssertEqual(rejected.source, .none)
        XCTAssertEqual(rejected.quarantinedFileCount, 2)
    }

    func testAccountWatermarkWriteFailureRecoversAcceptedAndAllowsReplacement()
        async throws
    {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fileSystem = FaultInjectingCheckpointFileSystem()
        let store = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root,
            fileSystem: fileSystem
        )
        let first = try checkpoint(modifications: [])
        try await store.activate(replicaEpoch: first.replicaEpoch, configurationScopeFingerprint: scopeFingerprint(), for: accountA)
        try await store.save(first, at: Date(timeIntervalSince1970: 3_243))

        var interruptedAccumulator = try self.accumulator(from: first)
        let interruptedSecond = try XCTUnwrap(
            interruptedAccumulator.apply(
                page(
                    accountID: accountA,
                    requestedAfter: "seed-cursor",
                    cursor: "interrupted-watermark-write",
                    moreComing: false
                )
            )
        )
        fileSystem.failNextWrite(named: "checkpoint.watermark.json")
        do {
            try await store.save(
                interruptedSecond,
                at: Date(timeIntervalSince1970: 3_244)
            )
            XCTFail("The injected account watermark write must fail")
        } catch {
            XCTAssertEqual(error as? CloudReplicaCheckpointStoreError, .ioFailure)
        }

        let relaunched = AtomicCloudReplicaCheckpointDiskStore(rootDirectoryURL: root)
        let recovered = try await relaunched.load(
            for: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            at: Date(timeIntervalSince1970: 3_245)
        )
        XCTAssertEqual(recovered.checkpoint, first)
        XCTAssertEqual(recovered.quarantinedFileCount, 1)

        var replacementAccumulator = try self.accumulator(from: first)
        let replacementSecond = try XCTUnwrap(
            replacementAccumulator.apply(
                page(
                    accountID: accountA,
                    requestedAfter: "seed-cursor",
                    cursor: "replacement-after-watermark-failure",
                    moreComing: false
                )
            )
        )
        try await relaunched.activate(replicaEpoch: first.replicaEpoch, configurationScopeFingerprint: scopeFingerprint(), for: accountA)
        try await relaunched.save(
            replacementSecond,
            at: Date(timeIntervalSince1970: 3_246)
        )
        let verified = try await relaunched.load(
            for: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            at: Date(timeIntervalSince1970: 3_247)
        )
        XCTAssertEqual(verified.checkpoint, replacementSecond)
    }

    func testInterruptedLoadRepairAfterPromotionRecoversOnNextRelaunch()
        async throws
    {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fileSystem = FaultInjectingCheckpointFileSystem()
        let store = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root,
            fileSystem: fileSystem
        )
        let first = try checkpoint(modifications: [])
        try await store.activate(replicaEpoch: first.replicaEpoch, configurationScopeFingerprint: scopeFingerprint(), for: accountA)
        try await store.save(first, at: Date(timeIntervalSince1970: 3_248))
        var accumulator = try self.accumulator(from: first)
        let second = try XCTUnwrap(
            accumulator.apply(
                page(
                    accountID: accountA,
                    requestedAfter: "seed-cursor",
                    cursor: "repair-after-promotion",
                    moreComing: false
                )
            )
        )
        fileSystem.failNextWrite(named: "checkpoint.backup.json")
        do {
            try await store.save(second, at: Date(timeIntervalSince1970: 3_249))
            XCTFail("The first backup publication must fail")
        } catch {
            XCTAssertEqual(error as? CloudReplicaCheckpointStoreError, .ioFailure)
        }

        fileSystem.failNextWrite(named: "checkpoint.backup.json")
        do {
            _ = try await store.load(
                for: accountA,
                configurationScopeFingerprint: scopeFingerprint(),
                at: Date(timeIntervalSince1970: 3_250)
            )
            XCTFail("The repair write after authority promotion must fail")
        } catch {
            XCTAssertEqual(error as? CloudReplicaCheckpointStoreError, .ioFailure)
        }

        let recovered = try await AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root
        ).load(
            for: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            at: Date(timeIntervalSince1970: 3_251)
        )
        XCTAssertEqual(recovered.checkpoint, second)
        XCTAssertEqual(recovered.source, .primary)
    }

    func testInterruptedGenesisAllowsDifferentReconstructedGenerationOne()
        async throws
    {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fileSystem = FaultInjectingCheckpointFileSystem()
        let store = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root,
            fileSystem: fileSystem
        )
        let interrupted = try checkpoint(modifications: [])
        let replacement = try checkpoint(
            modifications: [
                discovered(id: "replacement", locator: "provider-replacement"),
            ]
        )
        try await store.activate(
            replicaEpoch: interrupted.replicaEpoch,
            configurationScopeFingerprint: scopeFingerprint(),
            for: accountA
        )
        fileSystem.failNextWrite(named: "checkpoint.json")
        do {
            try await store.save(
                interrupted,
                at: Date(timeIntervalSince1970: 3_245)
            )
            XCTFail("The first primary write must interrupt genesis publication")
        } catch {
            XCTAssertEqual(error as? CloudReplicaCheckpointStoreError, .ioFailure)
        }

        let relaunched = AtomicCloudReplicaCheckpointDiskStore(rootDirectoryURL: root)
        let empty = try await relaunched.load(
            for: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            at: Date(timeIntervalSince1970: 3_246)
        )
        XCTAssertNil(empty.checkpoint)
        XCTAssertEqual(empty.source, .none)

        try await relaunched.activate(
            replicaEpoch: interrupted.replicaEpoch,
            configurationScopeFingerprint: scopeFingerprint(),
            for: accountA
        )
        try await relaunched.save(
            replacement,
            at: Date(timeIntervalSince1970: 3_247)
        )
        let verified = try await AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root
        ).load(
            for: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            at: Date(timeIntervalSince1970: 3_248)
        )
        XCTAssertEqual(verified.checkpoint, replacement)
    }

    func testPrePrimaryFailureRecoversAcceptedCheckpointAndAllowsNewGeneration()
        async throws
    {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fileSystem = FaultInjectingCheckpointFileSystem()
        let store = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root,
            fileSystem: fileSystem
        )
        let first = try checkpoint(modifications: [])
        try await store.activate(replicaEpoch: first.replicaEpoch, configurationScopeFingerprint: scopeFingerprint(), for: accountA)
        try await store.save(first, at: Date(timeIntervalSince1970: 3_250))
        let locations = storageLocations(root: root, accountID: accountA)
        let generationOnePrimary = try Data(contentsOf: locations.primary)
        let generationOneBackup = try Data(contentsOf: locations.backup)

        var accumulator = try self.accumulator(from: first)
        let second = try XCTUnwrap(
            accumulator.apply(
                page(
                    accountID: accountA,
                    requestedAfter: "seed-cursor",
                    cursor: "generation-two-watermark-only",
                    moreComing: false
                )
            )
        )
        fileSystem.failNextWrite(named: "checkpoint.json")
        do {
            try await store.save(second, at: Date(timeIntervalSince1970: 3_251))
            XCTFail("Generation two must stop before publishing either copy")
        } catch {
            XCTAssertEqual(error as? CloudReplicaCheckpointStoreError, .ioFailure)
        }
        XCTAssertEqual(try Data(contentsOf: locations.primary), generationOnePrimary)
        XCTAssertEqual(try Data(contentsOf: locations.backup), generationOneBackup)

        try Data("truncated-watermark".utf8).write(
            to: locations.watermark,
            options: .atomic
        )
        let relaunched = AtomicCloudReplicaCheckpointDiskStore(rootDirectoryURL: root)
        let recovered = try await relaunched.load(
            for: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            at: Date(timeIntervalSince1970: 3_252)
        )
        XCTAssertEqual(recovered.checkpoint, first)
        XCTAssertEqual(recovered.source, .primary)
        XCTAssertEqual(recovered.quarantinedFileCount, 1)
        XCTAssertEqual(try Data(contentsOf: locations.primary), generationOnePrimary)
        XCTAssertEqual(try Data(contentsOf: locations.backup), generationOnePrimary)

        var replacementAccumulator = try self.accumulator(from: first)
        let replacementSecond = try XCTUnwrap(
            replacementAccumulator.apply(
                page(
                    accountID: accountA,
                    requestedAfter: "seed-cursor",
                    cursor: "replacement-generation-two",
                    moreComing: false
                )
            )
        )
        try await relaunched.activate(replicaEpoch: first.replicaEpoch, configurationScopeFingerprint: scopeFingerprint(), for: accountA)
        try await relaunched.save(
            replacementSecond,
            at: Date(timeIntervalSince1970: 3_253)
        )
        let verified = try await AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root
        ).load(
            for: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            at: Date(timeIntervalSince1970: 3_254)
        )
        XCTAssertEqual(verified.checkpoint, replacementSecond)
    }

    func testAcceptedHighWatermarkRejectsRestoredOlderCopiesAndCorruptWatermark()
        async throws
    {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AtomicCloudReplicaCheckpointDiskStore(rootDirectoryURL: root)
        let first = try checkpoint(modifications: [])
        try await store.activate(replicaEpoch: first.replicaEpoch, configurationScopeFingerprint: scopeFingerprint(), for: accountA)
        try await store.save(first, at: Date(timeIntervalSince1970: 3_260))
        let locations = storageLocations(root: root, accountID: accountA)
        let generationOneData = try Data(contentsOf: locations.primary)

        var accumulator = try self.accumulator(from: first)
        let second = try XCTUnwrap(
            accumulator.apply(
                page(
                    accountID: accountA,
                    requestedAfter: "seed-cursor",
                    cursor: "accepted-generation-two",
                    moreComing: false
                )
            )
        )
        try await store.save(second, at: Date(timeIntervalSince1970: 3_261))

        try generationOneData.write(to: locations.primary, options: .atomic)
        try generationOneData.write(to: locations.backup, options: .atomic)
        try Data("corrupt-accepted-watermark".utf8).write(
            to: locations.watermark,
            options: .atomic
        )
        let relaunched = AtomicCloudReplicaCheckpointDiskStore(rootDirectoryURL: root)
        let rejected = try await relaunched.load(
            for: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            at: Date(timeIntervalSince1970: 3_262)
        )
        XCTAssertNil(rejected.checkpoint)
        XCTAssertEqual(rejected.source, .none)
        XCTAssertEqual(rejected.quarantinedFileCount, 3)

        let stillRejected = try await AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root
        ).load(
            for: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            at: Date(timeIntervalSince1970: 3_263)
        )
        XCTAssertNil(stillRejected.checkpoint)
        XCTAssertEqual(stillRejected.source, .none)
    }

    func testQuarantineMoveFailureDoesNotBlockBackupRecovery() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fileSystem = FaultInjectingCheckpointFileSystem()
        let store = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root,
            fileSystem: fileSystem
        )
        let expected = try checkpoint(modifications: [])
        try await store.activate(replicaEpoch: expected.replicaEpoch, configurationScopeFingerprint: scopeFingerprint(), for: accountA)
        try await store.save(expected, at: Date(timeIntervalSince1970: 3_300))
        let locations = storageLocations(root: root, accountID: accountA)
        try Data("corrupt-primary".utf8).write(to: locations.primary, options: .atomic)
        fileSystem.failNextMove()

        let recovered = try await store.load(
            for: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            at: Date(timeIntervalSince1970: 3_301)
        )
        XCTAssertEqual(recovered.checkpoint, expected)
        XCTAssertEqual(recovered.source, .backup)
        XCTAssertEqual(recovered.quarantinedFileCount, 0)
        XCTAssertEqual(
            try Data(contentsOf: locations.primary),
            try Data(contentsOf: locations.backup)
        )
    }

    func testStoreRejectsGenerationCollisionsStaleWritesAndGaps() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AtomicCloudReplicaCheckpointDiskStore(rootDirectoryURL: root)
        let first = try checkpoint(
            modifications: [discovered(id: "profile", locator: "provider-profile")]
        )
        try await store.activate(replicaEpoch: first.replicaEpoch, configurationScopeFingerprint: scopeFingerprint(), for: accountA)
        try await store.save(first, at: Date(timeIntervalSince1970: 3_400))
        try await store.save(first, at: Date(timeIntervalSince1970: 3_401))

        let collision = try checkpoint(
            modifications: [discovered(id: "different", locator: "provider-different")]
        )
        do {
            try await store.save(collision, at: Date(timeIntervalSince1970: 3_402))
            XCTFail("A divergent generation-one write must be rejected")
        } catch {
            XCTAssertEqual(error as? CloudReplicaCheckpointStoreError, .generationCollision)
        }

        var accumulator = try self.accumulator(from: first)
        let second = try XCTUnwrap(
            accumulator.apply(
                page(
                    accountID: accountA,
                    requestedAfter: "seed-cursor",
                    cursor: "second-generation",
                    moreComing: false
                )
            )
        )
        try await store.save(second, at: Date(timeIntervalSince1970: 3_403))
        do {
            try await store.save(first, at: Date(timeIntervalSince1970: 3_404))
            XCTFail("A stale generation must be rejected")
        } catch {
            XCTAssertEqual(error as? CloudReplicaCheckpointStoreError, .staleGeneration)
        }

        let gap = try checkpointCopy(second, generation: 4)
        do {
            try await store.save(gap, at: Date(timeIntervalSince1970: 3_405))
            XCTFail("A generation gap must be rejected")
        } catch {
            XCTAssertEqual(error as? CloudReplicaCheckpointStoreError, .generationGap)
        }
    }

    func testQuarantineUsesThreeFixedBoundedSlots() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AtomicCloudReplicaCheckpointDiskStore(rootDirectoryURL: root)
        let expected = try checkpoint(modifications: [])
        try await store.activate(replicaEpoch: expected.replicaEpoch, configurationScopeFingerprint: scopeFingerprint(), for: accountA)
        try await store.save(expected, at: Date(timeIntervalSince1970: 3_500))
        let locations = storageLocations(root: root, accountID: accountA)

        for iteration in 0..<4 {
            try Data("bad-primary-\(iteration)".utf8).write(
                to: locations.primary,
                options: .atomic
            )
            _ = try await store.load(
                for: accountA,
                configurationScopeFingerprint: scopeFingerprint(),
                at: Date(timeIntervalSince1970: 3_501 + Double(iteration))
            )
            try Data("bad-backup-\(iteration)".utf8).write(
                to: locations.backup,
                options: .atomic
            )
            _ = try await store.load(
                for: accountA,
                configurationScopeFingerprint: scopeFingerprint(),
                at: Date(timeIntervalSince1970: 3_511 + Double(iteration))
            )
            try Data("bad-watermark-\(iteration)".utf8).write(
                to: locations.watermark,
                options: .atomic
            )
            _ = try await store.load(
                for: accountA,
                configurationScopeFingerprint: scopeFingerprint(),
                at: Date(timeIntervalSince1970: 3_521 + Double(iteration))
            )
        }

        let quarantined = try FileManager.default.contentsOfDirectory(
            at: locations.quarantine,
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(Set(quarantined.map(\.lastPathComponent)), [
            "checkpoint-primary-corrupt.json",
            "checkpoint-backup-corrupt.json",
            "checkpoint-watermark-corrupt.json",
        ])
    }

    func testOversizedReplicaAndWatermarkAreDiscardedInsteadOfQuarantined()
        async throws
    {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let limits = testLimits(
            maxTotalBytes: 1_000,
            maxCursorBytes: 1_000
        )
        let store = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root,
            limits: limits
        )
        let expected = try checkpoint(modifications: [])
        try await store.activate(replicaEpoch: expected.replicaEpoch, configurationScopeFingerprint: scopeFingerprint(), for: accountA)
        try await store.save(expected, at: Date(timeIntervalSince1970: 3_550))
        let locations = storageLocations(root: root, accountID: accountA)
        let oversizedReplica = Data(repeating: 0x41, count: 8_001)
        let oversizedWatermark = Data(repeating: 0x42, count: 64 * 1_024 + 1)

        for (iteration, replicaURL) in [locations.primary, locations.backup].enumerated() {
            try oversizedReplica.write(to: replicaURL, options: .atomic)
            try oversizedWatermark.write(to: locations.watermark, options: .atomic)
            let recovered = try await store.load(
                for: accountA,
                configurationScopeFingerprint: scopeFingerprint(),
                at: Date(timeIntervalSince1970: 3_551 + Double(iteration))
            )
            XCTAssertEqual(recovered.checkpoint, expected)
            XCTAssertEqual(recovered.quarantinedFileCount, 0)
        }

        for slot in [
            "checkpoint-primary-corrupt.json",
            "checkpoint-backup-corrupt.json",
            "checkpoint-watermark-corrupt.json",
        ] {
            XCTAssertFalse(
                FileManager.default.fileExists(
                    atPath: locations.quarantine.appendingPathComponent(slot).path
                ),
                "Oversized input must never be retained in \(slot)"
            )
        }
    }

    func testStoreRevalidatesDecodedCheckpointAgainstInjectedLimits() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let permissive = AtomicCloudReplicaCheckpointDiskStore(rootDirectoryURL: root)
        let expected = try checkpoint(
            modifications: [discovered(id: "profile", locator: "provider-profile")]
        )
        try await permissive.activate(replicaEpoch: expected.replicaEpoch, configurationScopeFingerprint: scopeFingerprint(), for: accountA)
        try await permissive.save(expected, at: Date(timeIntervalSince1970: 3_600))

        let strict = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root,
            limits: testLimits(maxRecordCount: 1, maxBytesPerRecord: 8)
        )
        let rejected = try await strict.load(
            for: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            at: Date(timeIntervalSince1970: 3_601)
        )
        XCTAssertNil(rejected.checkpoint)
        XCTAssertEqual(rejected.source, .none)
        XCTAssertEqual(rejected.quarantinedFileCount, 2)
    }

    func testRemoveAffectsOnlyTheSelectedAccount() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AtomicCloudReplicaCheckpointDiskStore(rootDirectoryURL: root)
        let checkpointA = try checkpoint(modifications: [])
        let checkpointB = try checkpoint(accountID: accountB, modifications: [])
        try await store.activate(replicaEpoch: checkpointA.replicaEpoch, configurationScopeFingerprint: scopeFingerprint(), for: accountA)
        try await store.activate(replicaEpoch: checkpointB.replicaEpoch, configurationScopeFingerprint: scopeFingerprint(), for: accountB)
        try await store.save(checkpointA, at: Date(timeIntervalSince1970: 4_000))
        try await store.save(checkpointB, at: Date(timeIntervalSince1970: 4_001))

        try await store.remove(for: accountA, revoking: checkpointA.replicaEpoch)

        let removed = try await store.load(
            for: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            at: Date(timeIntervalSince1970: 4_002)
        )
        let retained = try await store.load(
            for: accountB,
            configurationScopeFingerprint: scopeFingerprint(),
            at: Date(timeIntervalSince1970: 4_003)
        )
        XCTAssertNil(removed.checkpoint)
        XCTAssertEqual(retained.checkpoint, checkpointB)
    }

    func testDurableRevocationRejectsStaleWriterAcrossStoreInstances() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let staleWriter = AtomicCloudReplicaCheckpointDiskStore(rootDirectoryURL: root)
        let remover = AtomicCloudReplicaCheckpointDiskStore(rootDirectoryURL: root)
        let old = try checkpoint(modifications: [])
        try await staleWriter.activate(replicaEpoch: old.replicaEpoch, configurationScopeFingerprint: scopeFingerprint(), for: accountA)
        try await staleWriter.save(old, at: Date(timeIntervalSince1970: 4_100))

        try await remover.remove(for: accountA, revoking: old.replicaEpoch)
        do {
            try await staleWriter.save(old, at: Date(timeIntervalSince1970: 4_101))
            XCTFail("A second store must observe the durable revocation")
        } catch {
            XCTAssertEqual(error as? CloudReplicaCheckpointStoreError, .replicaEpochRevoked)
        }
        do {
            try await AtomicCloudReplicaCheckpointDiskStore(rootDirectoryURL: root)
                .activate(replicaEpoch: old.replicaEpoch, configurationScopeFingerprint: scopeFingerprint(), for: accountA)
            XCTFail("A relaunched store must not reactivate a revoked epoch")
        } catch {
            XCTAssertEqual(error as? CloudReplicaCheckpointStoreError, .replicaEpochRevoked)
        }

        let newEpoch = UUID(uuidString: "bbbbbbbb-cccc-4ddd-8eee-ffffffffffff")!
        let replacement = try checkpoint(replicaEpoch: newEpoch, modifications: [])
        let relaunched = AtomicCloudReplicaCheckpointDiskStore(rootDirectoryURL: root)
        try await relaunched.activate(replicaEpoch: newEpoch, configurationScopeFingerprint: scopeFingerprint(), for: accountA)
        try await relaunched.save(replacement, at: Date(timeIntervalSince1970: 4_102))
        let loaded = try await relaunched.load(
            for: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            at: Date(timeIntervalSince1970: 4_103)
        )
        XCTAssertEqual(loaded.checkpoint, replacement)
    }

    func testEpochAuthorityStorageRemainsBoundedAcrossRepeatedRotations() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AtomicCloudReplicaCheckpointDiskStore(rootDirectoryURL: root)
        let locations = storageLocations(root: root, accountID: accountA)
        var retiredEpochs: [UUID] = []

        for index in 0 ..< 16 {
            let replicaEpoch = UUID()
            retiredEpochs.append(replicaEpoch)
            let current = try checkpoint(
                replicaEpoch: replicaEpoch,
                modifications: [
                    discovered(
                        id: "profile-\(index)",
                        locator: "provider-profile-\(index)"
                    ),
                ]
            )
            try await store.activate(replicaEpoch: replicaEpoch, configurationScopeFingerprint: scopeFingerprint(), for: accountA)
            try await store.save(
                current,
                at: Date(timeIntervalSince1970: 4_200 + Double(index))
            )
            try await store.remove(for: accountA, revoking: replicaEpoch)

            XCTAssertFalse(FileManager.default.fileExists(atPath: locations.directory.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: locations.authority.path))
        }

        let authorityFiles = try FileManager.default.contentsOfDirectory(
            at: locations.authorityDirectory,
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(
            Set(authorityFiles.map(\.lastPathComponent)),
            ["replica-authority.json", "replica-authority.lock"]
        )
        let authoritySize = try XCTUnwrap(
            try FileManager.default.attributesOfItem(
                atPath: locations.authority.path
            )[.size] as? NSNumber
        ).intValue
        XCTAssertLessThanOrEqual(authoritySize, 64 * 1_024)

        do {
            try await AtomicCloudReplicaCheckpointDiskStore(rootDirectoryURL: root)
                .activate(replicaEpoch: retiredEpochs[0], configurationScopeFingerprint: scopeFingerprint(), for: accountA)
            XCTFail("The bounded authority must retain oldest-epoch revocation")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .replicaEpochRevoked
            )
        }
    }

    func testRemoveSerializesAgainstConcurrentStaleSaveAcrossStoreInstances()
        async throws
    {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fileSystem = FaultInjectingCheckpointFileSystem()
        let staleWriter = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root,
            fileSystem: fileSystem
        )
        let remover = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root,
            fileSystem: fileSystem
        )
        let old = try checkpoint(modifications: [])
        try await staleWriter.activate(replicaEpoch: old.replicaEpoch, configurationScopeFingerprint: scopeFingerprint(), for: accountA)
        try await staleWriter.save(old, at: Date(timeIntervalSince1970: 4_300))

        let lockAttemptsBeforeRace = fileSystem.exclusiveLockAttemptCount()
        fileSystem.blockNextWrite(named: "replica-authority.json")
        defer { fileSystem.releaseBlockedWrite() }
        let removeTask = Task {
            try await remover.remove(for: accountA, revoking: old.replicaEpoch)
        }
        let removeReachedAuthorityWrite = await waitUntil {
            fileSystem.isBlockedWriteWaiting()
        }
        XCTAssertTrue(removeReachedAuthorityWrite)

        let staleSaveTask = Task { () -> CloudReplicaCheckpointStoreError? in
            do {
                try await staleWriter.save(
                    old,
                    at: Date(timeIntervalSince1970: 4_301)
                )
                return nil
            } catch {
                return error as? CloudReplicaCheckpointStoreError
            }
        }
        let staleSaveAttemptedLock = await waitUntil {
            fileSystem.exclusiveLockAttemptCount() >= lockAttemptsBeforeRace + 2
        }
        XCTAssertTrue(staleSaveAttemptedLock)

        fileSystem.releaseBlockedWrite()
        try await removeTask.value
        let staleSaveError = await staleSaveTask.value
        XCTAssertEqual(staleSaveError, .replicaEpochRevoked)

        let locations = storageLocations(root: root, accountID: accountA)
        XCTAssertFalse(FileManager.default.fileExists(atPath: locations.directory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: locations.authority.path))
    }

    private func assertPageError(
        _ page: CloudReplicaFetchedPage,
        equals expected: CloudReplicaAccumulatorError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        var accumulator = emptyAccumulator()
        XCTAssertThrowsError(try accumulator.apply(page), file: file, line: line) { error in
            XCTAssertEqual(error as? CloudReplicaAccumulatorError, expected, file: file, line: line)
        }
    }

    private func waitUntil(
        _ predicate: @escaping @Sendable () -> Bool
    ) async -> Bool {
        for _ in 0 ..< 5_000 {
            if predicate() { return true }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return predicate()
    }

    private func accumulator(
        from checkpoint: CloudReplicaCheckpointV1
    ) throws -> CloudReplicaStagedAccumulator {
        try CloudReplicaStagedAccumulator(
            accountID: checkpoint.accountID,
            configurationScopeFingerprint: checkpoint.configurationScopeFingerprint,
            checkpoint: checkpoint
        )
    }

    private func emptyAccumulator(
        limits: CloudReplicaResourceLimits = .production
    ) -> CloudReplicaStagedAccumulator {
        CloudReplicaStagedAccumulator(
            accountID: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            replicaEpoch: epoch,
            limits: limits
        )
    }

    private func checkpoint(
        accountID: CloudAccountID? = nil,
        replicaEpoch: UUID? = nil,
        modifications: [CloudDiscoveredRecord]
    ) throws -> CloudReplicaCheckpointV1 {
        let resolvedAccountID = accountID ?? accountA
        var accumulator = CloudReplicaStagedAccumulator(
            accountID: resolvedAccountID,
            configurationScopeFingerprint: scopeFingerprint(),
            replicaEpoch: replicaEpoch ?? epoch
        )
        return try XCTUnwrap(
            accumulator.apply(
                page(
                    accountID: resolvedAccountID,
                    modifications: modifications,
                    cursor: "seed-cursor",
                    moreComing: false
                )
            )
        )
    }

    private func checkpointCopy(
        _ checkpoint: CloudReplicaCheckpointV1,
        generation: UInt64
    ) throws -> CloudReplicaCheckpointV1 {
        try CloudReplicaCheckpointV1(
            accountID: checkpoint.accountID,
            configurationScopeFingerprint: checkpoint.configurationScopeFingerprint,
            generation: generation,
            finalCursor: checkpoint.finalCursor,
            recordsByLogicalID: checkpoint.recordsByLogicalID,
            providerLocatorByLogicalID: checkpoint.providerLocatorByLogicalID,
            logicalIDByProviderLocator: checkpoint.logicalIDByProviderLocator,
            tombstonesByProviderLocator: checkpoint.tombstonesByProviderLocator,
            replicaEpoch: checkpoint.replicaEpoch
        )
    }

    private func testLimits(
        maxPagesPerSync: Int = 100,
        maxPageChangeCount: Int = 100,
        maxRecordCount: Int = 100,
        maxTombstoneCount: Int = 100,
        maxBytesPerRecord: Int = 10_000,
        maxTotalBytes: Int = 100_000,
        maxCursorBytes: Int = 1_000
    ) -> CloudReplicaResourceLimits {
        CloudReplicaResourceLimits(
            maxPagesPerSync: maxPagesPerSync,
            maxPageChangeCount: maxPageChangeCount,
            maxRecordCount: maxRecordCount,
            maxTombstoneCount: maxTombstoneCount,
            maxBytesPerRecord: maxBytesPerRecord,
            maxTotalBytes: maxTotalBytes,
            maxCursorBytes: maxCursorBytes
        )
    }

    private func page(
        accountID: CloudAccountID,
        modifications: [CloudDiscoveredRecord] = [],
        deletions: [CloudDeletedRecord] = [],
        requestedAfter: String? = nil,
        scope: CloudReplicaScopeFingerprint? = nil,
        cursor: String,
        moreComing: Bool
    ) -> CloudReplicaFetchedPage {
        CloudReplicaFetchedPage(
            requestedAfterCursor: requestedAfter.map(self.cursor),
            configurationScopeFingerprint: scope ?? scopeFingerprint(),
            page: CloudRecordChangePage(
                accountID: accountID,
                modifications: modifications,
                deletions: deletions,
                nextCursor: self.cursor(cursor),
                moreComing: moreComing
            )
        )
    }

    private func discovered(
        id: String,
        locator: String,
        value: String = "value",
        recordType: String = "PlayerRecord"
    ) -> CloudDiscoveredRecord {
        CloudDiscoveredRecord(
            locator: CloudProviderRecordLocator(locator),
            record: cloudRecord(id: id, value: value, recordType: recordType)
        )
    }

    private func cloudRecord(
        id: String,
        value: String = "value",
        recordType: String = "PlayerRecord"
    ) -> CloudRecord {
        CloudRecord(
            id: CloudRecordID(id),
            recordType: recordType,
            fields: ["payload": Data(value.utf8)],
            changeTag: CloudChangeTag("tag-\(value)")
        )
    }

    private func cursor(_ value: String) -> CloudChangeCursor {
        CloudChangeCursor(Data(value.utf8))
    }

    private func scopeFingerprint() -> CloudReplicaScopeFingerprint {
        CloudReplicaScopeFingerprint.make(for: try! productionConfiguration())
    }

    private func alternateScopeFingerprint() -> CloudReplicaScopeFingerprint {
        CloudReplicaScopeFingerprint.make(
            for: try! productionConfiguration(zoneName: "PlayerDataOther")
        )
    }

    private func productionConfiguration(
        containerIdentifier: String = "iCloud.com.pocketvector.game",
        zoneName: String = "PlayerData",
        payloadFieldName: String = "payload",
        operationRecordType: String = "OperationMarker",
        accountIdentifierNamespace: String = "account-v1",
        recordNameNamespace: String = "record-v1",
        economyRecordID: String = "economy-head",
        economyRecordType: String = "EconomyRecord",
        economyPayloadFieldName: String = "economyPayload",
        conflictRetryLimit: Int = 3,
        profileRootRecordType: String = "ProfileRoot",
        profileSettingsRecordType: String = "ProfileSettings",
        profileSelectionRecordType: String = "ProfileSelection",
        profileRunRecordType: String = "ProfileRun",
        profilePayloadFieldName: String = "profilePayload"
    ) throws -> ProductionCloudWriteConfiguration {
        try ProductionCloudWriteConfiguration(
            transport: try CloudKitCloudSyncConfiguration(
                containerIdentifier: containerIdentifier,
                zoneName: zoneName,
                payloadFieldName: payloadFieldName,
                operationRecordType: operationRecordType,
                accountIdentifierNamespace: accountIdentifierNamespace,
                recordNameNamespace: recordNameNamespace
            ),
            economy: try DurableEconomyCloudConfiguration(
                recordID: CloudRecordID(economyRecordID),
                recordType: economyRecordType,
                payloadFieldName: economyPayloadFieldName,
                conflictRetryLimit: conflictRetryLimit
            ),
            profile: try CloudProfileSchemaConfiguration(
                rootRecordType: profileRootRecordType,
                settingsRecordType: profileSettingsRecordType,
                selectionRecordType: profileSelectionRecordType,
                runRecordType: profileRunRecordType,
                payloadFieldName: profilePayloadFieldName
            )
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "CloudReplicaCheckpointTests-\(UUID().uuidString)",
            isDirectory: true
        )
    }

    private func storageLocations(
        root: URL,
        accountID: CloudAccountID
    ) -> (
        directory: URL,
        primary: URL,
        backup: URL,
        watermark: URL,
        quarantine: URL,
        authorityDirectory: URL,
        authority: URL,
        authorityLock: URL
    ) {
        let checkpointRoot = root.appendingPathComponent(
            "CloudReplicaCheckpoints",
            isDirectory: true
        )
        let opaqueAccountName =
            AtomicCloudReplicaCheckpointDiskStore.accountDirectoryName(for: accountID)
        let directory = root
            .appendingPathComponent("CloudReplicaCheckpoints", isDirectory: true)
            .appendingPathComponent("Accounts", isDirectory: true)
            .appendingPathComponent(opaqueAccountName, isDirectory: true)
        let authorityDirectory = checkpointRoot
            .appendingPathComponent("Authorities", isDirectory: true)
            .appendingPathComponent(opaqueAccountName, isDirectory: true)
        return (
            directory,
            directory.appendingPathComponent("checkpoint.json"),
            directory.appendingPathComponent("checkpoint.backup.json"),
            directory.appendingPathComponent("checkpoint.watermark.json"),
            directory.appendingPathComponent("Quarantine", isDirectory: true),
            authorityDirectory,
            authorityDirectory.appendingPathComponent("replica-authority.json"),
            authorityDirectory.appendingPathComponent("replica-authority.lock")
        )
    }

    private func directoryRemovalTombstone(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.standardizedFileURL.path.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return url.deletingLastPathComponent().appendingPathComponent(
            ".pocket-vector-checkpoint-remove-\(digest).tmp",
            isDirectory: true
        )
    }
}

private enum CheckpointLeaseSentinelError: Error, Equatable, Sendable {
    case expected
}

private enum CheckpointLeaseAsyncOutcome: Equatable, Sendable {
    case success
    case storeError(CloudReplicaCheckpointStoreError)
    case unexpectedError(String)
}

private final class CheckpointLeaseBodyGate: @unchecked Sendable {
    private let condition = NSCondition()
    private var hasEntered = false
    private var isReleased = false

    func enterAndWait() {
        condition.lock()
        hasEntered = true
        condition.broadcast()
        while !isReleased {
            condition.wait()
        }
        condition.unlock()
    }

    func waitUntilEntered(timeout: TimeInterval = 5) -> Bool {
        condition.lock()
        defer { condition.unlock() }
        let deadline = Date(timeIntervalSinceNow: timeout)
        while !hasEntered {
            guard condition.wait(until: deadline) else { return hasEntered }
        }
        return true
    }

    func release() {
        condition.lock()
        isReleased = true
        condition.broadcast()
        condition.unlock()
    }
}

private final class CheckpointLeaseInvocationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var invocationCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func recordInvocation() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}

private final class CheckpointLeaseCompletionProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false

    var isComplete: Bool {
        lock.lock()
        defer { lock.unlock() }
        return completed
    }

    func recordCompletion() {
        lock.lock()
        completed = true
        lock.unlock()
    }
}

private final class FailNextRecursiveDirectoryRemovals: @unchecked Sendable {
    private enum InjectedFailure: Error {
        case requested
    }

    private let lock = NSLock()
    private var remainingFailures: Int
    private var removalAttemptPaths: [String] = []

    init(count: Int) {
        remainingFailures = count
    }

    func failNext(count: Int) {
        lock.lock()
        remainingFailures = count
        removalAttemptPaths.removeAll(keepingCapacity: true)
        lock.unlock()
    }

    func removeItem(at url: URL) throws {
        lock.lock()
        removalAttemptPaths.append(url.standardizedFileURL.path)
        let shouldFail = remainingFailures > 0
        if shouldFail {
            remainingFailures -= 1
        }
        lock.unlock()
        if shouldFail {
            throw InjectedFailure.requested
        }
        try FileManager.default.removeItem(at: url)
    }

    func attemptedPaths() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return removalAttemptPaths
    }
}

private final class FaultInjectingCheckpointFileSystem: CloudReplicaCheckpointFileSystem,
    @unchecked Sendable
{
    private enum InjectedFailure: Error {
        case requested
    }

    private let base = FoundationCloudReplicaCheckpointFileSystem()
    private let lock = NSLock()
    private let blockedWriteGate = NSCondition()
    private let exclusiveLockGate = NSCondition()
    private var nextWriteName: String?
    private var nextPostWriteFailureName: String?
    private var successfulPostWritesBeforeFailure = 0
    private var successfulMatchingWritesBeforeFailure = 0
    private var nextItemStatusName: String?
    private var unresolvedDurabilityPaths: Set<String> = []
    private var durableReconciliationCounts: [String: Int] = [:]
    private var shouldFailNextMove = false
    private var shouldFailAfterNextMove = false
    private var nextPostRemoveFailureName: String?
    private var nextPostCreateFailureName: String?
    private var nextBlockedWriteName: String?
    private var blockedWriteStarted = false
    private var mayReleaseBlockedWrite = false
    private var exclusiveLockAttempts = 0
    private var blockedExclusiveLockAttempt: Int?
    private var blockedExclusiveLockStarted = false
    private var mayReleaseExclusiveLock = false

    func failNextWrite(named name: String) {
        failWrite(named: name, afterSuccessfulMatchingWrites: 0)
    }

    func failAfterNextWrite(named name: String) {
        failAfterWrite(named: name, afterSuccessfulMatchingWrites: 0)
    }

    func failAfterWrite(
        named name: String,
        afterSuccessfulMatchingWrites count: Int
    ) {
        lock.lock()
        nextPostWriteFailureName = name
        successfulPostWritesBeforeFailure = count
        lock.unlock()
    }

    func failNextItemStatus(named name: String) {
        lock.lock()
        nextItemStatusName = name
        lock.unlock()
    }

    func durableReconciliationCount(named name: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return durableReconciliationCounts[name, default: 0]
    }

    func unresolvedDurabilityPathCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return unresolvedDurabilityPaths.count
    }

    func failWrite(named name: String, afterSuccessfulMatchingWrites count: Int) {
        lock.lock()
        nextWriteName = name
        successfulMatchingWritesBeforeFailure = count
        lock.unlock()
    }

    func failNextMove() {
        lock.lock()
        shouldFailNextMove = true
        lock.unlock()
    }

    func failAfterNextMove() {
        lock.lock()
        shouldFailAfterNextMove = true
        lock.unlock()
    }

    func failAfterNextRemove(named name: String) {
        lock.lock()
        nextPostRemoveFailureName = name
        lock.unlock()
    }

    func failAfterNextCreate(named name: String) {
        lock.lock()
        nextPostCreateFailureName = name
        lock.unlock()
    }

    func blockNextWrite(named name: String) {
        blockedWriteGate.lock()
        nextBlockedWriteName = name
        blockedWriteStarted = false
        mayReleaseBlockedWrite = false
        blockedWriteGate.unlock()
    }

    func isBlockedWriteWaiting() -> Bool {
        blockedWriteGate.lock()
        defer { blockedWriteGate.unlock() }
        return blockedWriteStarted
    }

    func releaseBlockedWrite() {
        blockedWriteGate.lock()
        mayReleaseBlockedWrite = true
        blockedWriteGate.broadcast()
        blockedWriteGate.unlock()
    }

    func exclusiveLockAttemptCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return exclusiveLockAttempts
    }

    func blockExclusiveLockAttempt(_ attempt: Int) {
        exclusiveLockGate.lock()
        blockedExclusiveLockAttempt = attempt
        blockedExclusiveLockStarted = false
        mayReleaseExclusiveLock = false
        exclusiveLockGate.unlock()
    }

    func isExclusiveLockAttemptBlocked() -> Bool {
        exclusiveLockGate.lock()
        defer { exclusiveLockGate.unlock() }
        return blockedExclusiveLockStarted
    }

    func releaseExclusiveLockAttempt() {
        exclusiveLockGate.lock()
        mayReleaseExclusiveLock = true
        exclusiveLockGate.broadcast()
        exclusiveLockGate.unlock()
    }

    func createDirectory(at url: URL) throws {
        lock.lock()
        let shouldFailAfter = nextPostCreateFailureName == url.lastPathComponent
        if shouldFailAfter {
            nextPostCreateFailureName = nil
        }
        lock.unlock()
        try base.createDirectory(at: url)
        if shouldFailAfter {
            lock.lock()
            unresolvedDurabilityPaths.formUnion(durabilityPathChain(for: url))
            lock.unlock()
            throw CloudReplicaCheckpointStoreError.durabilityOutcomeUnknown
        }
        _ = try reconcileDurableItem(at: url)
    }

    func itemStatus(at url: URL) throws -> CloudReplicaCheckpointFileItemStatus {
        lock.lock()
        let shouldFail = nextItemStatusName == url.lastPathComponent
        if shouldFail {
            nextItemStatusName = nil
        }
        lock.unlock()
        if shouldFail {
            throw InjectedFailure.requested
        }
        return try base.itemStatus(at: url)
    }

    func reconcileDurableItem(
        at url: URL
    ) throws -> CloudReplicaCheckpointFileItemStatus {
        lock.lock()
        let shouldFail = nextItemStatusName == url.lastPathComponent
        if shouldFail {
            nextItemStatusName = nil
        }
        lock.unlock()
        if shouldFail {
            throw InjectedFailure.requested
        }
        let status = try base.reconcileDurableItem(at: url)
        lock.lock()
        for path in durabilityPathChain(for: url) {
            unresolvedDurabilityPaths.remove(path)
        }
        durableReconciliationCounts[url.lastPathComponent, default: 0] += 1
        lock.unlock()
        return status
    }

    func fileSize(at url: URL) throws -> Int {
        try rejectUnresolvedRead(at: url)
        return try base.fileSize(at: url)
    }

    func read(from url: URL) throws -> Data {
        try rejectUnresolvedRead(at: url)
        return try base.read(from: url)
    }

    func writeAtomically(_ data: Data, to url: URL) throws {
        lock.lock()
        var shouldFail = false
        var shouldFailAfterWrite = false
        if nextWriteName == url.lastPathComponent {
            if successfulMatchingWritesBeforeFailure > 0 {
                successfulMatchingWritesBeforeFailure -= 1
            } else {
                shouldFail = true
                nextWriteName = nil
            }
        }
        if nextPostWriteFailureName == url.lastPathComponent {
            if successfulPostWritesBeforeFailure > 0 {
                successfulPostWritesBeforeFailure -= 1
            } else {
                shouldFailAfterWrite = true
                nextPostWriteFailureName = nil
            }
        }
        lock.unlock()
        if shouldFail {
            throw InjectedFailure.requested
        }
        blockedWriteGate.lock()
        if nextBlockedWriteName == url.lastPathComponent {
            nextBlockedWriteName = nil
            blockedWriteStarted = true
            blockedWriteGate.broadcast()
            while !mayReleaseBlockedWrite {
                blockedWriteGate.wait()
            }
            blockedWriteStarted = false
            mayReleaseBlockedWrite = false
        }
        blockedWriteGate.unlock()
        try base.writeAtomically(data, to: url)
        if shouldFailAfterWrite {
            lock.lock()
            unresolvedDurabilityPaths.formUnion(durabilityPathChain(for: url))
            lock.unlock()
            throw CloudReplicaCheckpointStoreError.durabilityOutcomeUnknown
        }
    }

    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        lock.lock()
        let shouldFail = shouldFailNextMove
        let shouldFailAfter = shouldFailAfterNextMove
        if shouldFail {
            shouldFailNextMove = false
        }
        if shouldFailAfter {
            shouldFailAfterNextMove = false
        }
        lock.unlock()
        if shouldFail {
            throw InjectedFailure.requested
        }
        try base.moveItem(at: sourceURL, to: destinationURL)
        if shouldFailAfter {
            lock.lock()
            unresolvedDurabilityPaths.formUnion(
                durabilityPathChain(for: sourceURL)
            )
            unresolvedDurabilityPaths.formUnion(
                durabilityPathChain(for: destinationURL)
            )
            lock.unlock()
            throw CloudReplicaCheckpointStoreError.durabilityOutcomeUnknown
        }
    }

    func removeItem(at url: URL) throws {
        lock.lock()
        let shouldFailAfter = nextPostRemoveFailureName == url.lastPathComponent
        if shouldFailAfter {
            nextPostRemoveFailureName = nil
        }
        lock.unlock()
        try base.removeItem(at: url)
        if shouldFailAfter {
            lock.lock()
            unresolvedDurabilityPaths.formUnion(durabilityPathChain(for: url))
            lock.unlock()
            throw CloudReplicaCheckpointStoreError.durabilityOutcomeUnknown
        }
    }

    func withExclusiveLock(at url: URL, perform: () throws -> Void) throws {
        lock.lock()
        exclusiveLockAttempts += 1
        let attempt = exclusiveLockAttempts
        lock.unlock()
        exclusiveLockGate.lock()
        if blockedExclusiveLockAttempt == attempt {
            blockedExclusiveLockAttempt = nil
            blockedExclusiveLockStarted = true
            exclusiveLockGate.broadcast()
            while !mayReleaseExclusiveLock {
                exclusiveLockGate.wait()
            }
            blockedExclusiveLockStarted = false
            mayReleaseExclusiveLock = false
        }
        exclusiveLockGate.unlock()
        try base.withExclusiveLock(at: url, perform: perform)
    }

    private func rejectUnresolvedRead(at url: URL) throws {
        lock.lock()
        let isUnresolved = unresolvedDurabilityPaths.contains(
            url.standardizedFileURL.path
        )
        lock.unlock()
        if isUnresolved {
            throw CloudReplicaCheckpointStoreError.durabilityOutcomeUnknown
        }
    }

    private func durabilityPathChain(for url: URL) -> Set<String> {
        let components = url.standardizedFileURL.pathComponents
        return Set(components.indices.map { index in
            NSString.path(
                withComponents: Array(components.prefix(index + 1))
            )
        })
    }
}

private extension Array where Element == String {
    var cloudIDs: Set<CloudRecordID> {
        Set(map { CloudRecordID($0) })
    }
}

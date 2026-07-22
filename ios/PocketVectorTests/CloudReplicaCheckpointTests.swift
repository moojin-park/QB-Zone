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
            "ef0641dcb0ea18a0552d4d360bfaeba4490bc3c16607a75d0ed3a03d8d0a1b98"
        )
        XCTAssertEqual(fingerprint.rawValue.count, 64)
        XCTAssertEqual(
            LaunchAchievementCloudScopeTransitionV1ToV2.sourceScope(
                for: base
            ).rawValue,
            "4d01494c9d6d505014fa7c70120f9b61abdaf6c5e606479faa22af088be5d52f"
        )
        XCTAssertEqual(
            LaunchAchievementCloudScopeTransitionV1ToV2.targetScope(
                for: base
            ),
            fingerprint
        )
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
            try productionConfiguration(containerEnvironment: .development),
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
            "bf81911f2b6012d3af59b5554e1ad589f5f696b07083873897706100e5c22b3a"
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
        let configuration = try productionConfiguration()
        let oldScope = LaunchAchievementCloudScopeTransitionV1ToV2
            .sourceScope(for: configuration)
        let newScope = LaunchAchievementCloudScopeTransitionV1ToV2
            .targetScope(for: configuration)
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
        let oldAuthority = try await store.activeReplicaAuthority(for: accountA)
        XCTAssertEqual(
            oldAuthority,
            CloudReplicaActiveEpochAuthorityV1(
                replicaEpoch: oldEpoch,
                configurationScopeFingerprint: oldScope
            )
        )
        try await store._testOnlySaveRawCheckpoint(oldCheckpoint, at: Date(timeIntervalSince1970: 5_000))

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
        let revokedAuthority = try await store.activeReplicaAuthority(for: accountA)
        XCTAssertNil(revokedAuthority)
        try await store.activate(
            replicaEpoch: freshEpoch,
            configurationScopeFingerprint: newScope,
            for: accountA
        )
        let freshAuthority = try await store.activeReplicaAuthority(for: accountA)
        XCTAssertEqual(
            freshAuthority,
            CloudReplicaActiveEpochAuthorityV1(
                replicaEpoch: freshEpoch,
                configurationScopeFingerprint: newScope
            )
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
        try await store._testOnlySaveRawCheckpoint(
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

    func testProductionPreparerRevokesLaunchV1ScopeAndBootstrapsFreshV2Generation()
        async throws
    {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let configuration = try productionConfiguration()
        let oldScope = LaunchAchievementCloudScopeTransitionV1ToV2
            .sourceScope(for: configuration)
        let currentScope = CloudReplicaScopeFingerprint.make(for: configuration)
        let oldEpoch = UUID(
            uuidString: "30000000-0000-4000-8000-000000000003"
        )!
        let freshEpoch = UUID(
            uuidString: "40000000-0000-4000-8000-000000000004"
        )!
        let oldStore = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root
        )
        try await oldStore.activate(
            replicaEpoch: oldEpoch,
            configurationScopeFingerprint: oldScope,
            for: accountA
        )
        try await oldStore._testOnlySaveRawCheckpoint(
            try CloudReplicaCheckpointV1(
                accountID: accountA,
                configurationScopeFingerprint: oldScope,
                generation: 1,
                finalCursor: cursor("retired-v1-cursor"),
                recordsByLogicalID: [:],
                providerLocatorByLogicalID: [:],
                logicalIDByProviderLocator: [:],
                tombstonesByProviderLocator: [:],
                replicaEpoch: oldEpoch
            ),
            at: Date(timeIntervalSince1970: 5_100)
        )

        let changeFetcher = ScriptedReconstructionChangeFetcher(
            pages: [
                page(
                    accountID: accountA,
                    cursor: "fresh-v2-cursor",
                    moreComing: false
                ).page,
            ]
        )
        let preparer = try ProductionCloudProfileReplicaPreparerV1(
            testingAccountID: accountA,
            checkpointRootDirectoryURL: root,
            configuration: configuration,
            economyVerifier: CloudProfileCompleteEconomyHistoryVerifier {
                $0.head
            },
            installingDeviceID: "scope-transition-device",
            changeFetcher: scopedChangeFetcher(
                changeFetcher,
                configuration: configuration
            ),
            now: { Date(timeIntervalSince1970: 5_101) },
            replicaEpochFactory: { freshEpoch }
        )
        try await preparer.prepareCheckpointedZone(accountID: accountA)

        let requests = await changeFetcher.observedRequests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertNil(requests.first?.cursor)
        XCTAssertEqual(
            requests.first?.zonePreparation,
            .createIfMissingForInitialBootstrap
        )

        let inspectionStore = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root
        )
        let authority = try await inspectionStore.activeReplicaAuthority(
            for: accountA
        )
        XCTAssertEqual(
            authority,
            CloudReplicaActiveEpochAuthorityV1(
                replicaEpoch: freshEpoch,
                configurationScopeFingerprint: currentScope
            )
        )
        let loaded = try await inspectionStore.load(
            for: accountA,
            configurationScopeFingerprint: currentScope,
            at: Date(timeIntervalSince1970: 5_102)
        )
        let checkpoint = try XCTUnwrap(loaded.checkpoint)
        XCTAssertEqual(checkpoint.generation, 1)
        XCTAssertEqual(checkpoint.replicaEpoch, freshEpoch)
        XCTAssertEqual(checkpoint.finalCursor, cursor("fresh-v2-cursor"))
        XCTAssertNotEqual(checkpoint.finalCursor, cursor("retired-v1-cursor"))
        XCTAssertTrue(checkpoint.recordsByLogicalID.isEmpty)
        XCTAssertNotEqual(freshEpoch, oldEpoch)
    }

    func testDiskStoreRecoversPrimaryFromBackupAndRepairsCorruptBackup() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AtomicCloudReplicaCheckpointDiskStore(rootDirectoryURL: root)
        let expected = try checkpoint(
            modifications: [discovered(id: "profile", locator: "provider-profile")]
        )
        try await store.activate(replicaEpoch: expected.replicaEpoch, configurationScopeFingerprint: scopeFingerprint(), for: accountA)
        try await store._testOnlySaveRawCheckpoint(expected, at: Date(timeIntervalSince1970: 1_000))
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
        try await store._testOnlySaveRawCheckpoint(expected, at: Date(timeIntervalSince1970: 1_010))
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
        try await store._testOnlySaveRawCheckpoint(expected, at: Date(timeIntervalSince1970: 2_000))

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

        try await store._testOnlySaveRawCheckpoint(expected, at: Date(timeIntervalSince1970: 2_002))
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
        try await store._testOnlySaveRawCheckpoint(checkpointA, at: Date(timeIntervalSince1970: 3_000))
        try await store._testOnlySaveRawCheckpoint(checkpointB, at: Date(timeIntervalSince1970: 3_001))

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
        try await writer._testOnlySaveRawCheckpoint(expected, at: Date(timeIntervalSince1970: 3_100))

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
        try await relaunched._testOnlySaveRawCheckpoint(first, at: Date(timeIntervalSince1970: 3_102))
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
        try await store._testOnlySaveRawCheckpoint(first, at: Date(timeIntervalSince1970: 3_111))
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
        try await stale._testOnlySaveRawCheckpoint(first, at: Date(timeIntervalSince1970: 3_137))

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
        try await store._testOnlySaveRawCheckpoint(first, at: Date(timeIntervalSince1970: 3_141))
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
            try await store._testOnlySaveRawCheckpoint(second, at: Date(timeIntervalSince1970: 3_142))
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
        try await writer._testOnlySaveRawCheckpoint(first, at: Date(timeIntervalSince1970: 3_144))
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
            try await writer._testOnlySaveRawCheckpoint(second, at: Date(timeIntervalSince1970: 3_146))
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
        try await leaseStore._testOnlySaveRawCheckpoint(first, at: Date(timeIntervalSince1970: 3_147))
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
                try await writer._testOnlySaveRawCheckpoint(
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
        try await leaseStore._testOnlySaveRawCheckpoint(first, at: Date(timeIntervalSince1970: 3_150))
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
        try await leaseStore._testOnlySaveRawCheckpoint(first, at: Date(timeIntervalSince1970: 3_152))
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
        try await writer._testOnlySaveRawCheckpoint(first, at: Date(timeIntervalSince1970: 3_155))
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
            try await writer._testOnlySaveRawCheckpoint(second, at: Date(timeIntervalSince1970: 3_157))
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
        try await store._testOnlySaveRawCheckpoint(first, at: Date(timeIntervalSince1970: 3_158))
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
        try await rememberedStore._testOnlySaveRawCheckpoint(
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
        try await store._testOnlySaveRawCheckpoint(first, at: Date(timeIntervalSince1970: 3_168))
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
            try await writer._testOnlySaveRawCheckpoint(first, at: Date(timeIntervalSince1970: 3_104))
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
        try await writer._testOnlySaveRawCheckpoint(first, at: Date(timeIntervalSince1970: 3_114))
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
            try await writer._testOnlySaveRawCheckpoint(second, at: Date(timeIntervalSince1970: 3_115))
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

    func testInitialBootstrapPublishesEmptyAndInitializedZoneSnapshots()
        async throws
    {
        let emptyRoot = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: emptyRoot) }
        let emptyFixture = try await initialBootstrapFixture(root: emptyRoot)
        let emptyContext = try await beginInitialBootstrap(
            emptyFixture,
            at: Date(timeIntervalSince1970: 3_114.1)
        )
        let emptyFetcher = ScriptedReconstructionChangeFetcher(
            pages: [
                page(
                    accountID: accountA,
                    cursor: "bootstrap-empty",
                    moreComing: false
                ).page,
            ]
        )
        let emptyPublication = try await emptyContext.fetchCompleteSnapshot(
            using: scopedChangeFetcher(emptyFetcher)
        )

        XCTAssertEqual(emptyPublication.checkpoint.generation, 1)
        XCTAssertTrue(emptyPublication.checkpoint.recordsByLogicalID.isEmpty)
        XCTAssertEqual(
            emptyPublication.targetCheckpointIdentity,
            ProfileHydrationCheckpointIdentityV1(
                checkpoint: emptyPublication.checkpoint
            )
        )
        let emptyRequests = await emptyFetcher.observedRequests()
        XCTAssertEqual(emptyRequests.count, 1)
        XCTAssertNil(emptyRequests[0].cursor)
        XCTAssertEqual(
            emptyRequests[0].zonePreparation,
            .createIfMissingForInitialBootstrap
        )

        try await saveInitialBootstrap(
            emptyPublication,
            fixture: emptyFixture,
            at: Date(timeIntervalSince1970: 3_114.2)
        )
        let emptyLoaded = try await emptyFixture.store.load(
            for: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            at: Date(timeIntervalSince1970: 3_114.3)
        )
        XCTAssertEqual(emptyLoaded.checkpoint, emptyPublication.checkpoint)

        let initializedRoot = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: initializedRoot) }
        let initializedFixture = try await initialBootstrapFixture(
            root: initializedRoot
        )
        let initializedContext = try await beginInitialBootstrap(
            initializedFixture,
            at: Date(timeIntervalSince1970: 3_114.4)
        )
        let initializedFetcher = ScriptedReconstructionChangeFetcher(
            pages: [
                page(
                    accountID: accountA,
                    modifications: [
                        discovered(id: "profile", locator: "provider-profile"),
                    ],
                    cursor: "bootstrap-page-one",
                    moreComing: true
                ).page,
                page(
                    accountID: accountA,
                    modifications: [
                        discovered(id: "ledger", locator: "provider-ledger"),
                    ],
                    cursor: "bootstrap-page-two",
                    moreComing: false
                ).page,
            ]
        )
        let initializedPublication = try await initializedContext
            .fetchCompleteSnapshot(
                using: scopedChangeFetcher(initializedFetcher)
            )

        XCTAssertEqual(initializedPublication.checkpoint.generation, 1)
        XCTAssertEqual(
            Set(initializedPublication.checkpoint.recordsByLogicalID.keys),
            Set([CloudRecordID("profile"), CloudRecordID("ledger")])
        )
        let initializedRequests = await initializedFetcher.observedRequests()
        XCTAssertEqual(initializedRequests.count, 2)
        XCTAssertNil(initializedRequests[0].cursor)
        XCTAssertEqual(
            initializedRequests[1].cursor,
            cursor("bootstrap-page-one")
        )
        XCTAssertEqual(
            initializedRequests.map(\.zonePreparation),
            [.createIfMissingForInitialBootstrap, .requireExisting]
        )

        try await saveInitialBootstrap(
            initializedPublication,
            fixture: initializedFixture,
            at: Date(timeIntervalSince1970: 3_114.5)
        )
        let initializedLoaded = try await initializedFixture.store.load(
            for: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            at: Date(timeIntervalSince1970: 3_114.6)
        )
        XCTAssertEqual(
            initializedLoaded.checkpoint,
            initializedPublication.checkpoint
        )
    }

    func testInitialBootstrapContextCannotReplayAfterItsPublicationIsSaved()
        async throws
    {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try await initialBootstrapFixture(root: root)
        let context = try await beginInitialBootstrap(
            fixture,
            at: Date(timeIntervalSince1970: 3_114.61)
        )
        let firstFetcher = ScriptedReconstructionChangeFetcher(
            pages: [
                page(
                    accountID: accountA,
                    cursor: "bootstrap-single-use",
                    moreComing: false
                ).page,
            ]
        )
        let publication = try await context.fetchCompleteSnapshot(
            using: scopedChangeFetcher(firstFetcher)
        )
        try await saveInitialBootstrap(
            publication,
            fixture: fixture,
            at: Date(timeIntervalSince1970: 3_114.62)
        )

        let replayFetcher = ScriptedReconstructionChangeFetcher(
            pages: [
                page(
                    accountID: accountA,
                    cursor: "must-not-fetch",
                    moreComing: false
                ).page,
            ]
        )
        do {
            _ = try await context.fetchCompleteSnapshot(
                using: scopedChangeFetcher(replayFetcher)
            )
            XCTFail("A consumed bootstrap context must never reach transport")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .initialBootstrapUnavailable
            )
        }
        let replayRequests = await replayFetcher.observedRequests()
        XCTAssertTrue(replayRequests.isEmpty)
    }

    func testInitialBootstrapStoreAContextCannotFetchAfterStoreBWins()
        async throws
    {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let authority = CloudAccountGenerationAuthority()
        let storeA = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root,
            accountGenerationAuthority: authority
        )
        let storeB = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root,
            accountGenerationAuthority: authority
        )
        for store in [storeA, storeB] {
            try await store.activate(
                replicaEpoch: epoch,
                configurationScopeFingerprint: scopeFingerprint(),
                for: accountA
            )
        }
        let generation = try await authority.activate(
            accountID: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            replicaEpoch: epoch
        )
        let fixtureA = InitialBootstrapFixture(
            authority: authority,
            store: storeA,
            generation: generation
        )
        let fixtureB = InitialBootstrapFixture(
            authority: authority,
            store: storeB,
            generation: generation
        )
        let contextA = try await beginInitialBootstrap(
            fixtureA,
            at: Date(timeIntervalSince1970: 3_114.63)
        )
        let contextB = try await beginInitialBootstrap(
            fixtureB,
            at: Date(timeIntervalSince1970: 3_114.64)
        )
        let winningFetcher = ScriptedReconstructionChangeFetcher(
            pages: [
                page(
                    accountID: accountA,
                    cursor: "store-b-wins",
                    moreComing: false
                ).page,
            ]
        )
        let winningPublication = try await contextB.fetchCompleteSnapshot(
            using: scopedChangeFetcher(winningFetcher)
        )
        try await saveInitialBootstrap(
            winningPublication,
            fixture: fixtureB,
            at: Date(timeIntervalSince1970: 3_114.65)
        )

        let staleFetcher = ScriptedReconstructionChangeFetcher(
            pages: [
                page(
                    accountID: accountA,
                    cursor: "store-a-must-not-fetch",
                    moreComing: false
                ).page,
            ]
        )
        do {
            _ = try await contextA.fetchCompleteSnapshot(
                using: scopedChangeFetcher(staleFetcher)
            )
            XCTFail("The losing store context must fail before transport")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .initialBootstrapUnavailable
            )
        }
        let staleRequests = await staleFetcher.observedRequests()
        XCTAssertTrue(staleRequests.isEmpty)
    }

    func testInitialBootstrapAmbiguousFailureRecoversRequireExistingOnly()
        async throws
    {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try await initialBootstrapFixture(root: root)
        let context = try await beginInitialBootstrap(
            fixture,
            at: Date(timeIntervalSince1970: 3_114.66)
        )
        let ambiguousFetcher = ScriptedReconstructionChangeFetcher(
            failure: .sentinel
        )
        do {
            _ = try await context.fetchCompleteSnapshot(
                using: scopedChangeFetcher(ambiguousFetcher)
            )
            XCTFail("The scripted transport must fail after admission")
        } catch {
            XCTAssertEqual(error as? ReconstructionFetchSentinelError, .sentinel)
        }
        let ambiguousRequests = await ambiguousFetcher.observedRequests()
        XCTAssertEqual(ambiguousRequests.count, 1)
        XCTAssertEqual(
            ambiguousRequests[0].zonePreparation,
            .createIfMissingForInitialBootstrap
        )

        let sameContextRetry = ScriptedReconstructionChangeFetcher()
        do {
            _ = try await context.fetchCompleteSnapshot(
                using: scopedChangeFetcher(sameContextRetry)
            )
            XCTFail("An ambiguous attempt must consume its process context")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .initialBootstrapUnavailable
            )
        }
        let sameContextRequests = await sameContextRetry.observedRequests()
        XCTAssertTrue(sameContextRequests.isEmpty)

        let recoveryAuthority = CloudAccountGenerationAuthority()
        let recoveryStore = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root,
            accountGenerationAuthority: recoveryAuthority
        )
        try await recoveryStore.activate(
            replicaEpoch: epoch,
            configurationScopeFingerprint: scopeFingerprint(),
            for: accountA
        )
        let recoveryGeneration = try await recoveryAuthority.activate(
            accountID: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            replicaEpoch: epoch
        )
        let recoveryFixture = InitialBootstrapFixture(
            authority: recoveryAuthority,
            store: recoveryStore,
            generation: recoveryGeneration
        )
        let recoveryContext = try await beginInitialBootstrap(
            recoveryFixture,
            at: Date(timeIntervalSince1970: 3_114.67)
        )
        let recoveryFetcher = ScriptedReconstructionChangeFetcher(
            pages: [
                page(
                    accountID: accountA,
                    cursor: "bootstrap-recovered",
                    moreComing: false
                ).page,
            ]
        )
        let recoveredPublication = try await recoveryContext
            .fetchCompleteSnapshot(using: scopedChangeFetcher(recoveryFetcher))
        let recoveryRequests = await recoveryFetcher.observedRequests()
        XCTAssertEqual(recoveryRequests.count, 1)
        XCTAssertEqual(
            recoveryRequests[0].zonePreparation,
            .requireExisting
        )
        try await saveInitialBootstrap(
            recoveredPublication,
            fixture: recoveryFixture,
            at: Date(timeIntervalSince1970: 3_114.68)
        )
        let loaded = try await recoveryFixture.store.load(
            for: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            at: Date(timeIntervalSince1970: 3_114.69)
        )
        XCTAssertEqual(loaded.checkpoint, recoveredPublication.checkpoint)
    }

    func testInitialBootstrapUnstartedReservationIsSafelyReplaced()
        async throws
    {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fileSystem = FaultInjectingCheckpointFileSystem()
        let fixture = try await initialBootstrapFixture(
            root: root,
            fileSystem: fileSystem
        )
        let context = try await beginInitialBootstrap(
            fixture,
            at: Date(timeIntervalSince1970: 3_114.691)
        )
        fileSystem.failWrite(
            named: "replica-authority.json",
            afterSuccessfulMatchingWrites: 1
        )
        let neverReachedFetcher = ScriptedReconstructionChangeFetcher(
            pages: [
                page(
                    accountID: accountA,
                    cursor: "must-not-reach-network",
                    moreComing: false
                ).page,
            ]
        )
        do {
            _ = try await context.fetchCompleteSnapshot(
                using: scopedChangeFetcher(neverReachedFetcher)
            )
            XCTFail("The pre-network authority transition must fail")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .ioFailure
            )
        }
        let neverReachedRequests = await neverReachedFetcher.observedRequests()
        XCTAssertTrue(neverReachedRequests.isEmpty)

        let replacement = try await beginInitialBootstrap(
            fixture,
            at: Date(timeIntervalSince1970: 3_114.692)
        )
        let replacementFetcher = ScriptedReconstructionChangeFetcher(
            pages: [
                page(
                    accountID: accountA,
                    cursor: "replacement-create",
                    moreComing: false
                ).page,
            ]
        )
        let publication = try await replacement.fetchCompleteSnapshot(
            using: scopedChangeFetcher(replacementFetcher)
        )
        let replacementRequests = await replacementFetcher.observedRequests()
        XCTAssertEqual(replacementRequests.count, 1)
        XCTAssertEqual(
            replacementRequests[0].zonePreparation,
            .createIfMissingForInitialBootstrap
        )
        try await saveInitialBootstrap(
            publication,
            fixture: fixture,
            at: Date(timeIntervalSince1970: 3_114.693)
        )
    }

    func testInitialBootstrapRecoveryCASAndLiveLeaseAllowOnlyOneAttempt()
        async throws
    {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let originalFixture = try await initialBootstrapFixture(root: root)
        let originalContext = try await beginInitialBootstrap(
            originalFixture,
            at: Date(timeIntervalSince1970: 3_114.694)
        )
        do {
            _ = try await originalContext.fetchCompleteSnapshot(
                using: scopedChangeFetcher(
                    ScriptedReconstructionChangeFetcher(failure: .sentinel)
                )
            )
            XCTFail("The initial network attempt must become ambiguous")
        } catch {
            XCTAssertEqual(error as? ReconstructionFetchSentinelError, .sentinel)
        }

        let recoveryAuthority = CloudAccountGenerationAuthority()
        let storeA = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root,
            accountGenerationAuthority: recoveryAuthority
        )
        let storeB = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root,
            accountGenerationAuthority: recoveryAuthority
        )
        for store in [storeA, storeB] {
            try await store.activate(
                replicaEpoch: epoch,
                configurationScopeFingerprint: scopeFingerprint(),
                for: accountA
            )
        }
        let generation = try await recoveryAuthority.activate(
            accountID: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            replicaEpoch: epoch
        )
        let fixtureA = InitialBootstrapFixture(
            authority: recoveryAuthority,
            store: storeA,
            generation: generation
        )
        let fixtureB = InitialBootstrapFixture(
            authority: recoveryAuthority,
            store: storeB,
            generation: generation
        )
        let contextA = try await beginInitialBootstrap(
            fixtureA,
            at: Date(timeIntervalSince1970: 3_114.695)
        )
        let contextB = try await beginInitialBootstrap(
            fixtureB,
            at: Date(timeIntervalSince1970: 3_114.696)
        )
        let winnerFetcher = ScriptedReconstructionChangeFetcher(
            pages: [
                page(
                    accountID: accountA,
                    cursor: "recovery-sequence-two",
                    moreComing: false
                ).page,
            ]
        )
        var retainedPublication: CloudReplicaInitialBootstrapPublicationV1? =
            try await contextA.fetchCompleteSnapshot(
                using: scopedChangeFetcher(winnerFetcher)
            )
        XCTAssertNotNil(retainedPublication)
        let loserFetcher = ScriptedReconstructionChangeFetcher(
            pages: [
                page(
                    accountID: accountA,
                    cursor: "cas-loser-must-not-fetch",
                    moreComing: false
                ).page,
            ]
        )
        do {
            _ = try await contextB.fetchCompleteSnapshot(
                using: scopedChangeFetcher(loserFetcher)
            )
            XCTFail("Only one context may claim the same recovery sequence")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .initialBootstrapUnavailable
            )
        }
        let loserRequests = await loserFetcher.observedRequests()
        XCTAssertTrue(loserRequests.isEmpty)

        let locations = storageLocations(root: root, accountID: accountA)
        let blockedAuthority = try replicaAuthorityJSONObject(
            at: locations.authority
        )
        let blockedReservation = try XCTUnwrap(
            blockedAuthority["initialBootstrapReservation"]
                as? [String: Any]
        )
        XCTAssertEqual(
            (blockedReservation["activeAttemptSequence"] as? NSNumber)?
                .uint64Value,
            2
        )

        retainedPublication = nil

        let currentContext = try await beginInitialBootstrap(
            fixtureB,
            at: Date(timeIntervalSince1970: 3_114.697)
        )
        let currentFetcher = ScriptedReconstructionChangeFetcher(
            pages: [
                page(
                    accountID: accountA,
                    cursor: "recovery-sequence-three",
                    moreComing: false
                ).page,
            ]
        )
        let currentPublication = try await currentContext.fetchCompleteSnapshot(
            using: scopedChangeFetcher(currentFetcher)
        )
        try await saveInitialBootstrap(
            currentPublication,
            fixture: fixtureB,
            at: Date(timeIntervalSince1970: 3_114.699)
        )
    }

    func testInitialBootstrapBlockedRecoveryPreventsSequenceAdvanceAndTransport()
        async throws
    {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let originalFixture = try await initialBootstrapFixture(root: root)
        let originalContext = try await beginInitialBootstrap(
            originalFixture,
            at: Date(timeIntervalSince1970: 3_114.69901)
        )
        do {
            _ = try await originalContext.fetchCompleteSnapshot(
                using: scopedChangeFetcher(
                    ScriptedReconstructionChangeFetcher(failure: .sentinel)
                )
            )
            XCTFail("The initial attempt must become ambiguous")
        } catch {
            XCTAssertEqual(error as? ReconstructionFetchSentinelError, .sentinel)
        }

        let recoveryAuthority = CloudAccountGenerationAuthority()
        let storeA = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root,
            accountGenerationAuthority: recoveryAuthority
        )
        let storeB = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root,
            accountGenerationAuthority: recoveryAuthority
        )
        for store in [storeA, storeB] {
            try await store.activate(
                replicaEpoch: epoch,
                configurationScopeFingerprint: scopeFingerprint(),
                for: accountA
            )
        }
        let generation = try await recoveryAuthority.activate(
            accountID: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            replicaEpoch: epoch
        )
        let fixtureA = InitialBootstrapFixture(
            authority: recoveryAuthority,
            store: storeA,
            generation: generation
        )
        let fixtureB = InitialBootstrapFixture(
            authority: recoveryAuthority,
            store: storeB,
            generation: generation
        )
        let contextA = try await beginInitialBootstrap(
            fixtureA,
            at: Date(timeIntervalSince1970: 3_114.69902)
        )
        let blockingFetcher = BlockingReconstructionChangeFetcher()
        let blockedTask = Task {
            try await contextA.fetchCompleteSnapshot(
                using: scopedChangeFetcher(blockingFetcher)
            )
        }
        let blockingFetchStarted = await waitUntilAsync {
            await blockingFetcher.hasStarted()
        }
        XCTAssertTrue(blockingFetchStarted)

        let contextB = try await beginInitialBootstrap(
            fixtureB,
            at: Date(timeIntervalSince1970: 3_114.69903)
        )
        let loserFetcher = ScriptedReconstructionChangeFetcher(
            pages: [
                page(
                    accountID: accountA,
                    cursor: "blocked-loser-must-not-fetch",
                    moreComing: false
                ).page,
            ]
        )
        do {
            _ = try await contextB.fetchCompleteSnapshot(
                using: scopedChangeFetcher(loserFetcher)
            )
            XCTFail("A live recovery fetch must own the reservation slot")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .initialBootstrapUnavailable
            )
        }
        let loserRequests = await loserFetcher.observedRequests()
        XCTAssertTrue(loserRequests.isEmpty)

        let locations = storageLocations(root: root, accountID: accountA)
        let blockedAuthority = try replicaAuthorityJSONObject(
            at: locations.authority
        )
        let blockedReservation = try XCTUnwrap(
            blockedAuthority["initialBootstrapReservation"]
                as? [String: Any]
        )
        XCTAssertEqual(
            (blockedReservation["activeAttemptSequence"] as? NSNumber)?
                .uint64Value,
            2
        )

        blockedTask.cancel()
        do {
            _ = try await blockedTask.value
            XCTFail("The blocked transport must observe cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }

        let recoveredContext = try await beginInitialBootstrap(
            fixtureB,
            at: Date(timeIntervalSince1970: 3_114.69904)
        )
        let recoveredFetcher = ScriptedReconstructionChangeFetcher(
            pages: [
                page(
                    accountID: accountA,
                    cursor: "recovered-after-live-attempt-release",
                    moreComing: false
                ).page,
            ]
        )
        let publication = try await recoveredContext.fetchCompleteSnapshot(
            using: scopedChangeFetcher(recoveredFetcher)
        )
        let recoveredRequests = await recoveredFetcher.observedRequests()
        XCTAssertEqual(
            recoveredRequests.map(\.zonePreparation),
            [.requireExisting]
        )
        try await saveInitialBootstrap(
            publication,
            fixture: fixtureB,
            at: Date(timeIntervalSince1970: 3_114.69905)
        )
    }

    func testReplicaAuthorityV2MigrationAndV3ReservationValidation()
        async throws
    {
        let root = temporaryDirectory()
        let checkpointRoot = temporaryDirectory()
        let pendingRoot = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: checkpointRoot)
            try? FileManager.default.removeItem(at: pendingRoot)
        }

        let fixture = try await initialBootstrapFixture(root: root)
        let locations = storageLocations(root: root, accountID: accountA)
        let baseAuthority = try replicaAuthorityJSONObject(
            at: locations.authority
        )
        XCTAssertEqual(
            (baseAuthority["formatVersion"] as? NSNumber)?.intValue,
            3
        )

        var legacyAuthority = baseAuthority
        legacyAuthority["formatVersion"] = 2
        legacyAuthority["initialBootstrapReservation"] =
            initialBootstrapReservationJSONObject(
                activeAttemptSequence: 41,
                phase: "networkMayHaveBeenInvoked"
            )
        let migratedData = try AtomicCloudReplicaCheckpointDiskStore
            ._testOnlyRoundTripReplicaAuthority(
                try replicaAuthorityData(legacyAuthority)
            )
        let migratedAuthority = try replicaAuthorityJSONObject(
            from: migratedData
        )
        XCTAssertEqual(
            (migratedAuthority["formatVersion"] as? NSNumber)?.intValue,
            3
        )
        XCTAssertNil(migratedAuthority["initialBootstrapReservation"])

        var unsupportedAuthority = baseAuthority
        unsupportedAuthority["formatVersion"] = 4
        let unsupportedData = try replicaAuthorityData(unsupportedAuthority)
        XCTAssertThrowsError(
            try AtomicCloudReplicaCheckpointDiskStore
                ._testOnlyRoundTripReplicaAuthority(unsupportedData)
        ) { error in
            XCTAssertEqual(
                error as? CloudReplicaCheckpointValidationError,
                .unsupportedFormatVersion
            )
        }

        var zeroIdentityAuthority = baseAuthority
        zeroIdentityAuthority["initialBootstrapReservation"] =
            initialBootstrapReservationJSONObject(
                reservationID: UUID(
                    uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
                ),
                activeAttemptSequence: 1,
                phase: "networkMayHaveBeenInvoked"
            )
        try assertInvalidReplicaAuthority(zeroIdentityAuthority)

        var malformedIdentityAuthority = baseAuthority
        var malformedIdentityReservation =
            initialBootstrapReservationJSONObject(
                activeAttemptSequence: 1,
                phase: "networkMayHaveBeenInvoked"
            )
        malformedIdentityReservation["reservationID"] = "not-a-uuid"
        malformedIdentityAuthority["initialBootstrapReservation"] =
            malformedIdentityReservation
        let malformedIdentityData = try replicaAuthorityData(
            malformedIdentityAuthority
        )
        XCTAssertThrowsError(
            try AtomicCloudReplicaCheckpointDiskStore
                ._testOnlyRoundTripReplicaAuthority(malformedIdentityData)
        )

        var missingIdentityAuthority = baseAuthority
        var missingIdentityReservation =
            initialBootstrapReservationJSONObject(
                activeAttemptSequence: 1,
                phase: "networkMayHaveBeenInvoked"
            )
        missingIdentityReservation.removeValue(forKey: "reservationID")
        missingIdentityAuthority["initialBootstrapReservation"] =
            missingIdentityReservation
        let missingIdentityData = try replicaAuthorityData(
            missingIdentityAuthority
        )
        XCTAssertThrowsError(
            try AtomicCloudReplicaCheckpointDiskStore
                ._testOnlyRoundTripReplicaAuthority(missingIdentityData)
        )

        var zeroSequenceAuthority = baseAuthority
        zeroSequenceAuthority["initialBootstrapReservation"] =
            initialBootstrapReservationJSONObject(
                activeAttemptSequence: 0,
                phase: "networkMayHaveBeenInvoked"
            )
        try assertInvalidReplicaAuthority(zeroSequenceAuthority)

        var consumedWithoutCheckpoint = baseAuthority
        consumedWithoutCheckpoint["initialBootstrapReservation"] =
            initialBootstrapReservationJSONObject(
                activeAttemptSequence: 1,
                phase: "consumedByCheckpoint"
            )
        try assertInvalidReplicaAuthority(consumedWithoutCheckpoint)

        let checkpointFixture = try await initialBootstrapFixture(
            root: checkpointRoot
        )
        try await checkpointFixture.store._testOnlySaveRawCheckpoint(
            try checkpoint(modifications: []),
            at: Date(timeIntervalSince1970: 3_114.6991)
        )
        let checkpointLocations = storageLocations(
            root: checkpointRoot,
            accountID: accountA
        )
        var networkPhaseWithCheckpoint = try replicaAuthorityJSONObject(
            at: checkpointLocations.authority
        )
        networkPhaseWithCheckpoint["initialBootstrapReservation"] =
            initialBootstrapReservationJSONObject(
                activeAttemptSequence: 1,
                phase: "networkMayHaveBeenInvoked"
            )
        try assertInvalidReplicaAuthority(networkPhaseWithCheckpoint)

        let pendingFileSystem = FaultInjectingCheckpointFileSystem()
        let pendingFixture = try await initialBootstrapFixture(
            root: pendingRoot,
            fileSystem: pendingFileSystem
        )
        pendingFileSystem.failNextWrite(named: "checkpoint.watermark.json")
        do {
            try await pendingFixture.store._testOnlySaveRawCheckpoint(
                try checkpoint(modifications: []),
                at: Date(timeIntervalSince1970: 3_114.6992)
            )
            XCTFail("The injected write must retain a pending publication")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .ioFailure
            )
        }
        let pendingLocations = storageLocations(
            root: pendingRoot,
            accountID: accountA
        )
        let pendingAuthority = try replicaAuthorityJSONObject(
            at: pendingLocations.authority
        )
        XCTAssertNotNil(pendingAuthority["pendingCheckpointHighWatermark"])

        var reservedPhaseWithPending = pendingAuthority
        reservedPhaseWithPending["initialBootstrapReservation"] =
            initialBootstrapReservationJSONObject(
                activeAttemptSequence: 1,
                phase: "reservedBeforeNetwork"
            )
        try assertInvalidReplicaAuthority(reservedPhaseWithPending)

        var networkPhaseWithPending = pendingAuthority
        networkPhaseWithPending["initialBootstrapReservation"] =
            initialBootstrapReservationJSONObject(
                activeAttemptSequence: 1,
                phase: "networkMayHaveBeenInvoked"
            )
        XCTAssertNoThrow(
            try AtomicCloudReplicaCheckpointDiskStore
                ._testOnlyRoundTripReplicaAuthority(
                    try replicaAuthorityData(networkPhaseWithPending)
                )
        )

        var overflowAuthority = baseAuthority
        overflowAuthority["initialBootstrapReservation"] =
            initialBootstrapReservationJSONObject(
                activeAttemptSequence: UInt64.max,
                phase: "networkMayHaveBeenInvoked"
            )
        let overflowData = try AtomicCloudReplicaCheckpointDiskStore
            ._testOnlyRoundTripReplicaAuthority(
                try replicaAuthorityData(overflowAuthority)
            )
        try overflowData.write(to: locations.authority, options: .atomic)
        do {
            _ = try await beginInitialBootstrap(
                fixture,
                at: Date(timeIntervalSince1970: 3_114.6993)
            )
            XCTFail("An exhausted recovery sequence must fail closed")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .initialBootstrapUnavailable
            )
        }
    }

    func testReplicaAuthorityReservationLifecycleSurvivesRecoveryAndRevocation()
        async throws
    {
        let interruptedRoot = temporaryDirectory()
        let consumedRoot = temporaryDirectory()
        let revokedRoot = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: interruptedRoot)
            try? FileManager.default.removeItem(at: consumedRoot)
            try? FileManager.default.removeItem(at: revokedRoot)
        }

        let interruptedFileSystem = FaultInjectingCheckpointFileSystem()
        let interruptedFixture = try await initialBootstrapFixture(
            root: interruptedRoot,
            fileSystem: interruptedFileSystem
        )
        let interruptedContext = try await beginInitialBootstrap(
            interruptedFixture,
            at: Date(timeIntervalSince1970: 3_114.6994)
        )
        var interruptedPublication: CloudReplicaInitialBootstrapPublicationV1? =
            try await interruptedContext
            .fetchCompleteSnapshot(
                using: scopedChangeFetcher(
                    ScriptedReconstructionChangeFetcher(
                        pages: [
                            page(
                                accountID: accountA,
                                cursor: "interrupted-genesis",
                                moreComing: false
                            ).page,
                        ]
                    )
                )
            )
        interruptedFileSystem.failNextWrite(
            named: "checkpoint.watermark.json"
        )
        do {
            let publication = try XCTUnwrap(interruptedPublication)
            try await saveInitialBootstrap(
                publication,
                fixture: interruptedFixture,
                at: Date(timeIntervalSince1970: 3_114.6995)
            )
            XCTFail("The injected save must retain pending genesis intent")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .ioFailure
            )
        }

        let interruptedLocations = storageLocations(
            root: interruptedRoot,
            accountID: accountA
        )
        let interruptedAuthority = try replicaAuthorityJSONObject(
            at: interruptedLocations.authority
        )
        let interruptedReservation = try XCTUnwrap(
            interruptedAuthority["initialBootstrapReservation"]
                as? [String: Any]
        )
        XCTAssertNotNil(
            interruptedAuthority["pendingCheckpointHighWatermark"]
        )
        XCTAssertEqual(
            interruptedReservation["phase"] as? String,
            "networkMayHaveBeenInvoked"
        )
        XCTAssertEqual(
            (interruptedReservation["activeAttemptSequence"] as? NSNumber)?
                .uint64Value,
            1
        )

        let recoveredLoad = try await interruptedFixture.store.load(
            for: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            at: Date(timeIntervalSince1970: 3_114.6996)
        )
        XCTAssertNil(recoveredLoad.checkpoint)
        let afterAbortAuthority = try replicaAuthorityJSONObject(
            at: interruptedLocations.authority
        )
        XCTAssertNil(afterAbortAuthority["pendingCheckpointHighWatermark"])
        let afterAbortReservation = try XCTUnwrap(
            afterAbortAuthority["initialBootstrapReservation"]
                as? [String: Any]
        )
        XCTAssertEqual(
            (afterAbortReservation["activeAttemptSequence"] as? NSNumber)?
                .uint64Value,
            1
        )
        interruptedPublication = nil

        let recoveryContext = try await beginInitialBootstrap(
            interruptedFixture,
            at: Date(timeIntervalSince1970: 3_114.6997)
        )
        let recoveryFetcher = ScriptedReconstructionChangeFetcher(
            pages: [
                page(
                    accountID: accountA,
                    cursor: "recovered-after-interrupted-save",
                    moreComing: false
                ).page,
            ]
        )
        let recoveredPublication = try await recoveryContext
            .fetchCompleteSnapshot(using: scopedChangeFetcher(recoveryFetcher))
        let recoveryRequests = await recoveryFetcher.observedRequests()
        XCTAssertEqual(
            recoveryRequests.map(\.zonePreparation),
            [.requireExisting]
        )
        try await saveInitialBootstrap(
            recoveredPublication,
            fixture: interruptedFixture,
            at: Date(timeIntervalSince1970: 3_114.6998)
        )
        let recoveredAuthority = try replicaAuthorityJSONObject(
            at: interruptedLocations.authority
        )
        let recoveredReservation = try XCTUnwrap(
            recoveredAuthority["initialBootstrapReservation"]
                as? [String: Any]
        )
        XCTAssertEqual(
            recoveredReservation["phase"] as? String,
            "consumedByCheckpoint"
        )
        XCTAssertEqual(
            (recoveredReservation["activeAttemptSequence"] as? NSNumber)?
                .uint64Value,
            2
        )

        let consumedFixture = try await initialBootstrapFixture(
            root: consumedRoot
        )
        let consumedContext = try await beginInitialBootstrap(
            consumedFixture,
            at: Date(timeIntervalSince1970: 3_114.6999)
        )
        let consumedPublication = try await consumedContext
            .fetchCompleteSnapshot(
                using: scopedChangeFetcher(
                    ScriptedReconstructionChangeFetcher(
                        pages: [
                            page(
                                accountID: accountA,
                                cursor: "consumed-generation-one",
                                moreComing: false
                            ).page,
                        ]
                    )
                )
            )
        try await saveInitialBootstrap(
            consumedPublication,
            fixture: consumedFixture,
            at: Date(timeIntervalSince1970: 3_114.7000)
        )
        let ordinaryFixture = ReconstructionFixture(
            authority: consumedFixture.authority,
            store: consumedFixture.store,
            generation: consumedFixture.generation,
            acceptedCheckpoint: consumedPublication.checkpoint
        )
        let ordinaryContext = try await beginOrdinaryPublication(
            ordinaryFixture,
            at: Date(timeIntervalSince1970: 3_114.7001)
        )
        let ordinaryPublication = try await ordinaryContext
            .fetchCompleteChanges(
                using: scopedChangeFetcher(
                    ScriptedReconstructionChangeFetcher(
                        pages: [
                            page(
                                accountID: accountA,
                                cursor: "consumed-generation-two",
                                moreComing: false
                            ).page,
                        ]
                    )
                )
            )
        try await saveOrdinaryPublication(
            ordinaryPublication,
            fixture: ordinaryFixture,
            at: Date(timeIntervalSince1970: 3_114.7002)
        )
        let consumedLocations = storageLocations(
            root: consumedRoot,
            accountID: accountA
        )
        let consumedAuthority = try replicaAuthorityJSONObject(
            at: consumedLocations.authority
        )
        let consumedReservation = try XCTUnwrap(
            consumedAuthority["initialBootstrapReservation"]
                as? [String: Any]
        )
        XCTAssertEqual(
            consumedReservation["phase"] as? String,
            "consumedByCheckpoint"
        )
        XCTAssertEqual(
            (consumedReservation["activeAttemptSequence"] as? NSNumber)?
                .uint64Value,
            1
        )
        let consumedWatermark = consumedAuthority[
            "checkpointHighWatermark"
        ] as? [String: Any]
        XCTAssertEqual(
            (consumedWatermark?["generation"] as? NSNumber)?.uint64Value,
            2
        )

        let revokedFixture = try await initialBootstrapFixture(
            root: revokedRoot
        )
        let revokedContext = try await beginInitialBootstrap(
            revokedFixture,
            at: Date(timeIntervalSince1970: 3_114.7003)
        )
        do {
            _ = try await revokedContext.fetchCompleteSnapshot(
                using: scopedChangeFetcher(
                    ScriptedReconstructionChangeFetcher(failure: .sentinel)
                )
            )
            XCTFail("The scripted fetch must leave an ambiguous reservation")
        } catch {
            XCTAssertEqual(error as? ReconstructionFetchSentinelError, .sentinel)
        }
        let revokedLocations = storageLocations(
            root: revokedRoot,
            accountID: accountA
        )
        XCTAssertNotNil(
            try replicaAuthorityJSONObject(at: revokedLocations.authority)[
                "initialBootstrapReservation"
            ]
        )
        try await revokedFixture.store.remove(
            for: accountA,
            revoking: epoch
        )
        let revokedAuthority = try replicaAuthorityJSONObject(
            at: revokedLocations.authority
        )
        XCTAssertEqual(revokedAuthority["state"] as? String, "revoked")
        XCTAssertNil(revokedAuthority["initialBootstrapReservation"])
        XCTAssertNoThrow(
            try AtomicCloudReplicaCheckpointDiskStore
                ._testOnlyRoundTripReplicaAuthority(
                    try replicaAuthorityData(revokedAuthority)
                )
        )
    }

    func testInitialBootstrapReservationIssuerRejectsZeroAndHistoryCap()
        async throws
    {
        let zeroRoot = temporaryDirectory()
        let capRoot = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: zeroRoot)
            try? FileManager.default.removeItem(at: capRoot)
        }

        let zeroFixture = try await initialBootstrapFixture(
            root: zeroRoot,
            reservationUUIDFactory: {
                UUID(
                    uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
                )
            }
        )
        let zeroLocations = storageLocations(
            root: zeroRoot,
            accountID: accountA
        )
        let zeroAuthorityBefore = try Data(contentsOf: zeroLocations.authority)
        do {
            _ = try await beginInitialBootstrap(
                zeroFixture,
                at: Date(timeIntervalSince1970: 3_114.7004)
            )
            XCTFail("A zero reservation identity must fail closed")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .initialBootstrapUnavailable
            )
        }
        XCTAssertEqual(
            try Data(contentsOf: zeroLocations.authority),
            zeroAuthorityBefore
        )

        let issuedID = UUID(
            uuidString: "11111111-2222-4333-8444-555555555555"
        )!
        let capFixture = try await initialBootstrapFixture(
            root: capRoot,
            reservationUUIDFactory: { issuedID },
            maximumIssuedReservationCount: 1
        )
        let retainedContext = try await beginInitialBootstrap(
            capFixture,
            at: Date(timeIntervalSince1970: 3_114.7005)
        )
        _ = retainedContext
        let capLocations = storageLocations(root: capRoot, accountID: accountA)
        let capAuthorityBefore = try Data(contentsOf: capLocations.authority)
        do {
            _ = try await beginInitialBootstrap(
                capFixture,
                at: Date(timeIntervalSince1970: 3_114.7006)
            )
            XCTFail("Reservation history exhaustion must fail closed")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .initialBootstrapUnavailable
            )
        }
        XCTAssertEqual(
            try Data(contentsOf: capLocations.authority),
            capAuthorityBefore
        )
    }

    func testInitialBootstrapPhysicalAliasesShareReservationCollisionHistory()
        async throws
    {
        let realRoot = temporaryDirectory()
        let aliasRoot = realRoot.deletingLastPathComponent()
            .appendingPathComponent(
                "CloudReplicaCheckpointAlias-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: realRoot,
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: aliasRoot,
            withDestinationURL: realRoot
        )
        defer {
            try? FileManager.default.removeItem(at: aliasRoot)
            try? FileManager.default.removeItem(at: realRoot)
        }

        let repeatedID = UUID(
            uuidString: "22222222-3333-4444-8555-666666666666"
        )!
        let authority = CloudAccountGenerationAuthority()
        let realStore = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: realRoot,
            accountGenerationAuthority: authority,
            initialBootstrapReservationUUIDFactory: { repeatedID },
            maximumIssuedInitialBootstrapReservationCount: 4
        )
        let aliasStore = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: aliasRoot,
            accountGenerationAuthority: authority,
            initialBootstrapReservationUUIDFactory: { repeatedID },
            maximumIssuedInitialBootstrapReservationCount: 4
        )
        for store in [realStore, aliasStore] {
            try await store.activate(
                replicaEpoch: epoch,
                configurationScopeFingerprint: scopeFingerprint(),
                for: accountA
            )
        }
        let generation = try await authority.activate(
            accountID: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            replicaEpoch: epoch
        )
        let realFixture = InitialBootstrapFixture(
            authority: authority,
            store: realStore,
            generation: generation
        )
        let aliasFixture = InitialBootstrapFixture(
            authority: authority,
            store: aliasStore,
            generation: generation
        )
        let retainedContext = try await beginInitialBootstrap(
            realFixture,
            at: Date(timeIntervalSince1970: 3_114.7007)
        )
        _ = retainedContext
        let locations = storageLocations(root: realRoot, accountID: accountA)
        let authorityBefore = try Data(contentsOf: locations.authority)
        do {
            _ = try await beginInitialBootstrap(
                aliasFixture,
                at: Date(timeIntervalSince1970: 3_114.7008)
            )
            XCTFail("A path alias must not bypass reservation collision history")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .initialBootstrapUnavailable
            )
        }
        XCTAssertEqual(
            try Data(contentsOf: locations.authority),
            authorityBefore
        )
    }

    func testInitialBootstrapAuthorityRecreationRejectsRepeatedReservationABA()
        async throws
    {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repeatedID = UUID(
            uuidString: "33333333-4444-4555-8666-777777777777"
        )!
        let fixture = try await initialBootstrapFixture(
            root: root,
            reservationUUIDFactory: { repeatedID }
        )
        let context = try await beginInitialBootstrap(
            fixture,
            at: Date(timeIntervalSince1970: 3_114.7009)
        )
        let oldPublication = try await context.fetchCompleteSnapshot(
            using: scopedChangeFetcher(
                ScriptedReconstructionChangeFetcher(
                    pages: [
                        page(
                            accountID: accountA,
                            cursor: "old-authority-publication",
                            moreComing: false
                        ).page,
                    ]
                )
            )
        )

        let locations = storageLocations(root: root, accountID: accountA)
        try FileManager.default.removeItem(at: locations.authority)
        let replacementStore = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root,
            accountGenerationAuthority: fixture.authority,
            initialBootstrapReservationUUIDFactory: { repeatedID }
        )
        try await replacementStore.activate(
            replicaEpoch: epoch,
            configurationScopeFingerprint: scopeFingerprint(),
            for: accountA
        )
        let replacementFixture = InitialBootstrapFixture(
            authority: fixture.authority,
            store: replacementStore,
            generation: fixture.generation
        )
        let recreatedAuthority = try Data(contentsOf: locations.authority)
        do {
            _ = try await beginInitialBootstrap(
                replacementFixture,
                at: Date(timeIntervalSince1970: 3_114.7010)
            )
            XCTFail("A recreated authority must not reuse an issued reservation")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .initialBootstrapUnavailable
            )
        }
        XCTAssertEqual(
            try Data(contentsOf: locations.authority),
            recreatedAuthority
        )

        do {
            try await saveInitialBootstrap(
                oldPublication,
                fixture: fixture,
                at: Date(timeIntervalSince1970: 3_114.7011)
            )
            XCTFail("Old publication authority must not survive recreation")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .initialBootstrapUnavailable
            )
        }
    }

    func testInitialBootstrapAuthorityRecreationCannotOverlapWithNewReservation()
        async throws
    {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let uuidFactory = ScriptedReservationUUIDFactory([
            UUID(uuidString: "44444444-5555-4666-8777-888888888888")!,
            UUID(uuidString: "55555555-6666-4777-8888-999999999999")!,
            UUID(uuidString: "66666666-7777-4888-8999-AAAAAAAAAAAA")!,
        ])
        let fixture = try await initialBootstrapFixture(
            root: root,
            reservationUUIDFactory: { uuidFactory.next() }
        )
        let context = try await beginInitialBootstrap(
            fixture,
            at: Date(timeIntervalSince1970: 3_114.7012)
        )
        var retainedPublication: CloudReplicaInitialBootstrapPublicationV1? =
            try await context.fetchCompleteSnapshot(
                using: scopedChangeFetcher(
                    ScriptedReconstructionChangeFetcher(
                        pages: [
                            page(
                                accountID: accountA,
                                cursor: "authority-loss-live-publication",
                                moreComing: false
                            ).page,
                        ]
                    )
                )
            )
        XCTAssertNotNil(retainedPublication)

        let locations = storageLocations(root: root, accountID: accountA)
        try FileManager.default.removeItem(at: locations.authority)
        let replacementStore = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root,
            accountGenerationAuthority: fixture.authority,
            initialBootstrapReservationUUIDFactory: { uuidFactory.next() }
        )
        try await replacementStore.activate(
            replicaEpoch: epoch,
            configurationScopeFingerprint: scopeFingerprint(),
            for: accountA
        )
        let replacementFixture = InitialBootstrapFixture(
            authority: fixture.authority,
            store: replacementStore,
            generation: fixture.generation
        )
        let overlappingContext = try await beginInitialBootstrap(
            replacementFixture,
            at: Date(timeIntervalSince1970: 3_114.7013)
        )
        let blockedFetcher = ScriptedReconstructionChangeFetcher(
            pages: [
                page(
                    accountID: accountA,
                    cursor: "new-reservation-must-not-overlap",
                    moreComing: false
                ).page,
            ]
        )
        let authorityBeforeBlockedFetch = try Data(
            contentsOf: locations.authority
        )
        do {
            _ = try await overlappingContext.fetchCompleteSnapshot(
                using: scopedChangeFetcher(blockedFetcher)
            )
            XCTFail("A live publication must block even a new reservation ID")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .initialBootstrapUnavailable
            )
        }
        let blockedRequests = await blockedFetcher.observedRequests()
        XCTAssertTrue(blockedRequests.isEmpty)
        XCTAssertEqual(
            try Data(contentsOf: locations.authority),
            authorityBeforeBlockedFetch
        )

        retainedPublication = nil
        let recoveredContext = try await beginInitialBootstrap(
            replacementFixture,
            at: Date(timeIntervalSince1970: 3_114.7014)
        )
        let recoveredFetcher = ScriptedReconstructionChangeFetcher(
            pages: [
                page(
                    accountID: accountA,
                    cursor: "new-reservation-after-release",
                    moreComing: false
                ).page,
            ]
        )
        let recoveredPublication = try await recoveredContext
            .fetchCompleteSnapshot(using: scopedChangeFetcher(recoveredFetcher))
        let recoveredRequests = await recoveredFetcher.observedRequests()
        XCTAssertEqual(
            recoveredRequests.map(\.zonePreparation),
            [.createIfMissingForInitialBootstrap]
        )
        try await saveInitialBootstrap(
            recoveredPublication,
            fixture: replacementFixture,
            at: Date(timeIntervalSince1970: 3_114.7015)
        )
    }

    func testInitialBootstrapFetchFailuresAndCancellationDoNotMutateStore()
        async throws
    {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try await initialBootstrapFixture(root: root)
        let context = try await beginInitialBootstrap(
            fixture,
            at: Date(timeIntervalSince1970: 3_114.7)
        )

        let alternateConfiguration = try productionConfiguration(
            zoneName: "OtherZone"
        )
        let mismatchedFetcher = ScriptedReconstructionChangeFetcher()
        do {
            _ = try await context.fetchCompleteSnapshot(
                using: scopedChangeFetcher(
                    mismatchedFetcher,
                    configuration: alternateConfiguration
                )
            )
            XCTFail("A differently configured scope must fail before network")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .configurationScopeMismatch
            )
        }
        let mismatchedRequests = await mismatchedFetcher.observedRequests()
        XCTAssertTrue(mismatchedRequests.isEmpty)

        let missingAfterFirstPage = MissingZoneReconstructionChangeFetcher(
            pages: [
                page(
                    accountID: accountA,
                    cursor: "bootstrap-before-zone-loss",
                    moreComing: true
                ).page,
            ]
        )
        do {
            _ = try await context.fetchCompleteSnapshot(
                using: scopedChangeFetcher(missingAfterFirstPage)
            )
            XCTFail("A zone missing after page one must fail closed")
        } catch {
            XCTAssertEqual(
                error as? CloudKitCloudSyncError,
                .zoneResetRequired
            )
        }
        let missingRequests = await missingAfterFirstPage.observedRequests()
        XCTAssertEqual(missingRequests.count, 2)
        XCTAssertNil(missingRequests[0].cursor)
        XCTAssertEqual(
            missingRequests[1].cursor,
            cursor("bootstrap-before-zone-loss")
        )
        XCTAssertEqual(
            missingRequests.map(\.zonePreparation),
            [.createIfMissingForInitialBootstrap, .requireExisting]
        )
        try await assertNoDurableCheckpoint(
            fixture,
            at: Date(timeIntervalSince1970: 3_114.8)
        )

        let wrongAccountFetcher = ScriptedReconstructionChangeFetcher(
            pages: [
                page(
                    accountID: accountB,
                    cursor: "bootstrap-wrong-account",
                    moreComing: false
                ).page,
            ]
        )
        let wrongAccountContext = try await beginInitialBootstrap(
            fixture,
            at: Date(timeIntervalSince1970: 3_114.85)
        )
        do {
            _ = try await wrongAccountContext.fetchCompleteSnapshot(
                using: scopedChangeFetcher(wrongAccountFetcher)
            )
            XCTFail("A page for another account must fail unchanged")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaAccumulatorError,
                .accountMismatch
            )
        }
        try await assertNoDurableCheckpoint(
            fixture,
            at: Date(timeIntervalSince1970: 3_114.9)
        )

        let blockingFetcher = BlockingReconstructionChangeFetcher()
        let cancellationContext = try await beginInitialBootstrap(
            fixture,
            at: Date(timeIntervalSince1970: 3_114.95)
        )
        let cancelled = Task {
            try await cancellationContext.fetchCompleteSnapshot(
                using: scopedChangeFetcher(blockingFetcher)
            )
        }
        let fetchStarted = await waitUntilAsync {
            await blockingFetcher.hasStarted()
        }
        XCTAssertTrue(fetchStarted)
        cancelled.cancel()
        do {
            _ = try await cancelled.value
            XCTFail("Cancellation must emerge unchanged")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        try await assertNoDurableCheckpoint(
            fixture,
            at: Date(timeIntervalSince1970: 3_115.0)
        )
    }

    func testInitialBootstrapBeginRejectsAcceptedAndPendingHistoryWithoutMutation()
        async throws
    {
        let acceptedRoot = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: acceptedRoot) }
        let acceptedFixture = try await initialBootstrapFixture(
            root: acceptedRoot
        )
        let accepted = try checkpoint(modifications: [])
        try await acceptedFixture.store._testOnlySaveRawCheckpoint(
            accepted,
            at: Date(timeIntervalSince1970: 3_115.01)
        )
        let beforeAcceptedBegin = try directorySnapshot(at: acceptedRoot)
        do {
            _ = try await beginInitialBootstrap(
                acceptedFixture,
                at: Date(timeIntervalSince1970: 3_115.02)
            )
            XCTFail("Accepted history must permanently close genesis")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .initialBootstrapUnavailable
            )
        }
        XCTAssertEqual(
            try directorySnapshot(at: acceptedRoot),
            beforeAcceptedBegin
        )
        let acceptedResumeValue = try await acceptedFixture.store
            .resumeActiveReplicaEpoch(
                for: accountA,
                configurationScopeFingerprint: scopeFingerprint()
            )
        let acceptedResume = try XCTUnwrap(acceptedResumeValue)
        XCTAssertEqual(acceptedResume.acceptedHistory?.generation, 1)
        XCTAssertFalse(acceptedResume.hasDurableCheckpointIntent)

        let pendingRoot = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: pendingRoot) }
        let pendingFileSystem = FaultInjectingCheckpointFileSystem()
        let pendingFixture = try await initialBootstrapFixture(
            root: pendingRoot,
            fileSystem: pendingFileSystem
        )
        pendingFileSystem.failNextWrite(named: "checkpoint.watermark.json")
        do {
            try await pendingFixture.store._testOnlySaveRawCheckpoint(
                try checkpoint(modifications: []),
                at: Date(timeIntervalSince1970: 3_115.04)
            )
            XCTFail("The fault must leave a durable pending genesis")
        } catch {
            XCTAssertEqual(error as? CloudReplicaCheckpointStoreError, .ioFailure)
        }
        let beforePendingBegin = try directorySnapshot(at: pendingRoot)
        do {
            _ = try await beginInitialBootstrap(
                pendingFixture,
                at: Date(timeIntervalSince1970: 3_115.03)
            )
            XCTFail("Pending publication must close genesis")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .checkpointPublicationPending
            )
        }
        XCTAssertEqual(
            try directorySnapshot(at: pendingRoot),
            beforePendingBegin
        )
        let pendingResumeValue = try await pendingFixture.store
            .resumeActiveReplicaEpoch(
                for: accountA,
                configurationScopeFingerprint: scopeFingerprint()
            )
        let pendingResume = try XCTUnwrap(pendingResumeValue)
        XCTAssertNil(pendingResume.acceptedHistory)
        XCTAssertTrue(pendingResume.hasDurableCheckpointIntent)
    }

    func testInitialBootstrapPreflightPreservesEveryPriorEvidenceShape()
        async throws
    {
        let seedARoot = temporaryDirectory()
        let seedBRoot = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: seedARoot)
            try? FileManager.default.removeItem(at: seedBRoot)
        }
        let seedA = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: seedARoot
        )
        let seedB = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: seedBRoot
        )
        for seed in [seedA, seedB] {
            try await seed.activate(
                replicaEpoch: epoch,
                configurationScopeFingerprint: scopeFingerprint(),
                for: accountA
            )
        }
        try await seedA._testOnlySaveRawCheckpoint(
            try checkpoint(
                modifications: [
                    discovered(id: "seed-a", locator: "provider-seed-a"),
                ]
            ),
            at: Date(timeIntervalSince1970: 3_115.05)
        )
        try await seedB._testOnlySaveRawCheckpoint(
            try checkpoint(
                modifications: [
                    discovered(id: "seed-b", locator: "provider-seed-b"),
                ]
            ),
            at: Date(timeIntervalSince1970: 3_115.06)
        )
        let validEnvelopeA = try Data(
            contentsOf: storageLocations(root: seedARoot, accountID: accountA)
                .primary
        )
        let validEnvelopeB = try Data(
            contentsOf: storageLocations(root: seedBRoot, accountID: accountA)
                .primary
        )

        for (index, scenario) in InitialBootstrapEvidenceScenario.allCases
            .enumerated()
        {
            let root = temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: root) }
            let fixture = try await initialBootstrapFixture(root: root)
            try installInitialBootstrapEvidence(
                scenario,
                root: root,
                validEnvelopeA: validEnvelopeA,
                validEnvelopeB: validEnvelopeB
            )
            let before = try directorySnapshot(at: root)

            do {
                _ = try await beginInitialBootstrap(
                    fixture,
                    at: Date(
                        timeIntervalSince1970: 3_115.07 + Double(index) / 100
                    )
                )
                XCTFail("\(scenario) evidence must permanently close genesis")
            } catch {
                XCTAssertEqual(
                    error as? CloudReplicaCheckpointStoreError,
                    .initialBootstrapUnavailable,
                    "Unexpected result for \(scenario)"
                )
            }

            XCTAssertEqual(
                try directorySnapshot(at: root),
                before,
                "Preflight mutated \(scenario) evidence"
            )
            let resumeValue = try await fixture.store.resumeActiveReplicaEpoch(
                for: accountA,
                configurationScopeFingerprint: scopeFingerprint()
            )
            let resume = try XCTUnwrap(resumeValue)
            XCTAssertNil(resume.acceptedHistory)
            XCTAssertFalse(resume.hasDurableCheckpointIntent)
        }
    }

    func testInitialBootstrapRejectsForgedBindingsGenerationAndStaleAuthority()
        async throws
    {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try await initialBootstrapFixture(root: root)
        let context = try await beginInitialBootstrap(
            fixture,
            at: Date(timeIntervalSince1970: 3_115.07)
        )
        let publication = try await context.fetchCompleteSnapshot(
            using: scopedChangeFetcher(
                ScriptedReconstructionChangeFetcher(
                    pages: [
                        page(
                            accountID: accountA,
                            cursor: "bootstrap-branded",
                            moreComing: false
                        ).page,
                    ]
                )
            )
        )

        let wrongAccount = try checkpoint(
            accountID: accountB,
            modifications: []
        )
        let wrongScope = try CloudReplicaCheckpointV1(
            accountID: accountA,
            configurationScopeFingerprint: alternateScopeFingerprint(),
            generation: 1,
            finalCursor: publication.checkpoint.finalCursor,
            recordsByLogicalID: publication.checkpoint.recordsByLogicalID,
            providerLocatorByLogicalID:
                publication.checkpoint.providerLocatorByLogicalID,
            logicalIDByProviderLocator:
                publication.checkpoint.logicalIDByProviderLocator,
            tombstonesByProviderLocator:
                publication.checkpoint.tombstonesByProviderLocator,
            replicaEpoch: epoch
        )
        let wrongEpoch = try checkpoint(
            replicaEpoch: UUID(),
            modifications: []
        )
        for forgedCheckpoint in [wrongAccount, wrongScope, wrongEpoch] {
            let forged = publication._testOnlyReplacingCheckpoint(
                forgedCheckpoint
            )
            do {
                try await saveInitialBootstrap(
                    forged,
                    fixture: fixture,
                    at: Date(timeIntervalSince1970: 3_115.08)
                )
                XCTFail("Cross-bound checkpoint data must be rejected")
            } catch {
                XCTAssertEqual(
                    error as? CloudReplicaCheckpointStoreError,
                    .accountGenerationMismatch
                )
            }
        }
        for invalidGeneration in [UInt64(2), UInt64(3)] {
            let forged = publication._testOnlyReplacingCheckpoint(
                try checkpointCopy(
                    publication.checkpoint,
                    generation: invalidGeneration
                )
            )
            do {
                try await saveInitialBootstrap(
                    forged,
                    fixture: fixture,
                    at: Date(timeIntervalSince1970: 3_115.09)
                )
                XCTFail("Initial bootstrap can publish only generation one")
            } catch {
                XCTAssertEqual(
                    error as? CloudReplicaCheckpointStoreError,
                    .generationGap
                )
            }
        }
        try await assertNoDurableCheckpoint(
            fixture,
            at: Date(timeIntervalSince1970: 3_115.1)
        )

        let blockedByGenuinePublication = try await beginInitialBootstrap(
            fixture,
            at: Date(timeIntervalSince1970: 3_115.101)
        )
        let blockedProbe = ScriptedReconstructionChangeFetcher(
            pages: [
                page(
                    accountID: accountA,
                    cursor: "forged-save-must-retain-live-lease",
                    moreComing: false
                ).page,
            ]
        )
        do {
            _ = try await blockedByGenuinePublication.fetchCompleteSnapshot(
                using: scopedChangeFetcher(blockedProbe)
            )
            XCTFail("A rejected forged save must not release the genuine lease")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .initialBootstrapUnavailable
            )
        }
        let blockedProbeRequests = await blockedProbe.observedRequests()
        XCTAssertTrue(blockedProbeRequests.isEmpty)

        let foreignAuthority = CloudAccountGenerationAuthority()
        let foreignGeneration = try await foreignAuthority.activate(
            accountID: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            replicaEpoch: epoch
        )
        do {
            _ = try await foreignAuthority.withCurrentGeneration(
                foreignGeneration
            ) { lease in
                try await fixture.store.beginInitialBootstrapPublication(
                    generationLease: lease,
                    at: Date(timeIntervalSince1970: 3_115.105)
                )
            }
            XCTFail("A foreign authority cannot mint a genesis context")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .accountGenerationAuthorityMismatch
            )
        }
        do {
            try await foreignAuthority.withCurrentGeneration(foreignGeneration) {
                lease in
                try await fixture.store.saveInitialBootstrapPublication(
                    publication,
                    generationLease: lease,
                    at: Date(timeIntervalSince1970: 3_115.11)
                )
            }
            XCTFail("A foreign authority cannot publish genesis")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .accountGenerationAuthorityMismatch
            )
        }
        try await assertNoDurableCheckpoint(
            fixture,
            at: Date(timeIntervalSince1970: 3_115.12)
        )

        try await fixture.authority.invalidate(fixture.generation)
        let reactivated = try await fixture.authority.activate(
            accountID: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            replicaEpoch: epoch
        )
        do {
            try await fixture.authority.withCurrentGeneration(reactivated) {
                lease in
                try await fixture.store.saveInitialBootstrapPublication(
                    publication,
                    generationLease: lease,
                    at: Date(timeIntervalSince1970: 3_115.13)
                )
            }
            XCTFail("Same-binding reactivation must invalidate fetched work")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .accountGenerationMismatch
            )
        }
        let resumedValue = try await fixture.store.resumeActiveReplicaEpoch(
            for: accountA,
            configurationScopeFingerprint: scopeFingerprint()
        )
        let resumed = try XCTUnwrap(resumedValue)
        XCTAssertNil(resumed.acceptedHistory)
        XCTAssertFalse(resumed.hasDurableCheckpointIntent)
    }

    func testInitialBootstrapSaveRejectsHistoryPendingAndEvidenceWithoutMutation()
        async throws
    {
        let acceptedRoot = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: acceptedRoot) }
        let acceptedFixture = try await initialBootstrapFixture(
            root: acceptedRoot
        )
        let acceptedContext = try await beginInitialBootstrap(
            acceptedFixture,
            at: Date(timeIntervalSince1970: 3_115.14)
        )
        let stalePublication = try await acceptedContext.fetchCompleteSnapshot(
            using: scopedChangeFetcher(
                ScriptedReconstructionChangeFetcher(
                    pages: [
                        page(
                            accountID: accountA,
                            cursor: "bootstrap-stale",
                            moreComing: false
                        ).page,
                    ]
                )
            )
        )
        let acceptedFirst = try checkpoint(
            modifications: [
                discovered(id: "accepted", locator: "provider-accepted"),
            ]
        )
        try await acceptedFixture.store._testOnlySaveRawCheckpoint(
            acceptedFirst,
            at: Date(timeIntervalSince1970: 3_115.15)
        )
        do {
            try await saveInitialBootstrap(
                stalePublication,
                fixture: acceptedFixture,
                at: Date(timeIntervalSince1970: 3_115.16)
            )
            XCTFail("Accepted history must reject a stale genesis result")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .initialBootstrapUnavailable
            )
        }
        let acceptedLoaded = try await acceptedFixture.store.load(
            for: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            at: Date(timeIntervalSince1970: 3_115.17)
        )
        XCTAssertEqual(acceptedLoaded.checkpoint, acceptedFirst)

        let pendingRoot = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: pendingRoot) }
        let pendingFileSystem = FaultInjectingCheckpointFileSystem()
        let pendingFixture = try await initialBootstrapFixture(
            root: pendingRoot,
            fileSystem: pendingFileSystem
        )
        let pendingContext = try await beginInitialBootstrap(
            pendingFixture,
            at: Date(timeIntervalSince1970: 3_115.18)
        )
        let pendingPublication = try await pendingContext.fetchCompleteSnapshot(
            using: scopedChangeFetcher(
                ScriptedReconstructionChangeFetcher(
                    pages: [
                        page(
                            accountID: accountA,
                            cursor: "bootstrap-after-pending",
                            moreComing: false
                        ).page,
                    ]
                )
            )
        )
        pendingFileSystem.failNextWrite(named: "checkpoint.watermark.json")
        do {
            try await pendingFixture.store._testOnlySaveRawCheckpoint(
                try checkpoint(modifications: []),
                at: Date(timeIntervalSince1970: 3_115.19)
            )
            XCTFail("The fault must leave pending intent")
        } catch {
            XCTAssertEqual(error as? CloudReplicaCheckpointStoreError, .ioFailure)
        }
        do {
            try await saveInitialBootstrap(
                pendingPublication,
                fixture: pendingFixture,
                at: Date(timeIntervalSince1970: 3_115.2)
            )
            XCTFail("Typed genesis cannot retry an unrelated pending result")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .checkpointPublicationPending
            )
        }
        let pendingResumeValue = try await pendingFixture.store
            .resumeActiveReplicaEpoch(
                for: accountA,
                configurationScopeFingerprint: scopeFingerprint()
            )
        let pendingResume = try XCTUnwrap(pendingResumeValue)
        XCTAssertNil(pendingResume.acceptedHistory)
        XCTAssertTrue(pendingResume.hasDurableCheckpointIntent)

        let evidenceRoot = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: evidenceRoot) }
        let evidenceFixture = try await initialBootstrapFixture(
            root: evidenceRoot
        )
        let evidenceContext = try await beginInitialBootstrap(
            evidenceFixture,
            at: Date(timeIntervalSince1970: 3_115.21)
        )
        let evidencePublication = try await evidenceContext
            .fetchCompleteSnapshot(
                using: scopedChangeFetcher(
                    ScriptedReconstructionChangeFetcher(
                        pages: [
                            page(
                                accountID: accountA,
                                cursor: "bootstrap-after-evidence",
                                moreComing: false
                            ).page,
                        ]
                    )
                )
            )
        let evidenceLocations = storageLocations(
            root: evidenceRoot,
            accountID: accountA
        )
        try FileManager.default.createDirectory(
            at: evidenceLocations.directory,
            withIntermediateDirectories: true
        )
        try Data("noncooperative-evidence".utf8).write(
            to: evidenceLocations.primary,
            options: .atomic
        )
        let beforeEvidenceSave = try directorySnapshot(at: evidenceRoot)
        do {
            try await saveInitialBootstrap(
                evidencePublication,
                fixture: evidenceFixture,
                at: Date(timeIntervalSince1970: 3_115.22)
            )
            XCTFail("Reappeared evidence must close the typed save gate")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .initialBootstrapUnavailable
            )
        }
        XCTAssertEqual(
            try directorySnapshot(at: evidenceRoot),
            beforeEvidenceSave
        )
        let evidenceResumeValue = try await evidenceFixture.store
            .resumeActiveReplicaEpoch(
                for: accountA,
                configurationScopeFingerprint: scopeFingerprint()
            )
        let evidenceResume = try XCTUnwrap(evidenceResumeValue)
        XCTAssertNil(evidenceResume.acceptedHistory)
        XCTAssertFalse(evidenceResume.hasDurableCheckpointIntent)

        try FileManager.default.removeItem(at: evidenceLocations.primary)
        try FileManager.default.createDirectory(
            at: evidenceLocations.quarantine,
            withIntermediateDirectories: true
        )
        try Data("reappeared-quarantine-evidence".utf8).write(
            to: evidenceLocations.quarantine.appendingPathComponent(
                "checkpoint-primary-corrupt.json"
            ),
            options: .atomic
        )
        let beforeQuarantineSave = try directorySnapshot(at: evidenceRoot)
        do {
            try await saveInitialBootstrap(
                evidencePublication,
                fixture: evidenceFixture,
                at: Date(timeIntervalSince1970: 3_115.23)
            )
            XCTFail("Quarantine evidence must close the typed save gate")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .initialBootstrapUnavailable
            )
        }
        XCTAssertEqual(
            try directorySnapshot(at: evidenceRoot),
            beforeQuarantineSave
        )
    }

    func testOrdinaryPublicationRequiresAcceptedCheckpointAndUsesRequireExisting()
        async throws
    {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try await reconstructionFixture(
            root: root,
            removeAcceptedCache: false,
            acceptedModifications: [
                discovered(
                    id: "existing",
                    locator: "provider-existing",
                    value: "accepted"
                ),
            ]
        )
        let context = try await beginOrdinaryPublication(
            fixture,
            at: Date(timeIntervalSince1970: 3_115.1)
        )
        let rawFetcher = ScriptedReconstructionChangeFetcher(
            pages: [
                page(
                    accountID: accountA,
                    modifications: [
                        discovered(id: "next", locator: "provider-next"),
                    ],
                    cursor: "ordinary-page-one",
                    moreComing: true
                ).page,
                page(
                    accountID: accountA,
                    modifications: [
                        discovered(id: "last", locator: "provider-last"),
                    ],
                    cursor: "ordinary-next",
                    moreComing: false
                ).page,
            ]
        )
        let publication = try await context.fetchCompleteChanges(
            using: scopedChangeFetcher(rawFetcher)
        )

        XCTAssertEqual(
            publication.predecessorCheckpointIdentity,
            ProfileHydrationCheckpointIdentityV1(
                checkpoint: fixture.acceptedCheckpoint
            )
        )
        XCTAssertEqual(
            publication.targetCheckpointIdentity,
            ProfileHydrationCheckpointIdentityV1(
                checkpoint: publication.checkpoint
            )
        )
        XCTAssertEqual(
            publication.checkpoint.generation,
            fixture.acceptedCheckpoint.generation + 1
        )
        XCTAssertEqual(
            Set(publication.checkpoint.recordsByLogicalID.keys),
            Set([
                CloudRecordID("existing"),
                CloudRecordID("next"),
                CloudRecordID("last"),
            ])
        )
        XCTAssertEqual(
            publication.checkpoint.recordsByLogicalID[
                CloudRecordID("existing")
            ],
            fixture.acceptedCheckpoint.recordsByLogicalID[
                CloudRecordID("existing")
            ]
        )
        let requests = await rawFetcher.observedRequests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].cursor, fixture.acceptedCheckpoint.finalCursor)
        XCTAssertEqual(requests[1].cursor, cursor("ordinary-page-one"))
        XCTAssertEqual(
            requests.map(\.zonePreparation),
            [.requireExisting, .requireExisting]
        )

        try await saveOrdinaryPublication(
            publication,
            fixture: fixture,
            at: Date(timeIntervalSince1970: 3_115.2)
        )
        let loaded = try await fixture.store.load(
            for: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            at: Date(timeIntervalSince1970: 3_115.3)
        )
        XCTAssertEqual(loaded.checkpoint, publication.checkpoint)

        let emptyRoot = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: emptyRoot) }
        let emptyAuthority = CloudAccountGenerationAuthority()
        let emptyStore = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: emptyRoot,
            accountGenerationAuthority: emptyAuthority
        )
        try await emptyStore.activate(
            replicaEpoch: epoch,
            configurationScopeFingerprint: scopeFingerprint(),
            for: accountA
        )
        let emptyGeneration = try await emptyAuthority.activate(
            accountID: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            replicaEpoch: epoch
        )
        do {
            _ = try await emptyAuthority.withCurrentGeneration(emptyGeneration) {
                lease in
                try await emptyStore.beginIncrementalOrdinaryPublication(
                    generationLease: lease,
                    at: Date(timeIntervalSince1970: 3_115.4)
                )
            }
            XCTFail("Ordinary publication must not become initial bootstrap")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .acceptedHistoryUnavailable
            )
        }
    }

    func testOrdinaryPublicationPreservesErrorsAfterCursorAdvance() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try await reconstructionFixture(
            root: root,
            removeAcceptedCache: false
        )
        let context = try await beginOrdinaryPublication(
            fixture,
            at: Date(timeIntervalSince1970: 3_115.45)
        )
        let transportFailure = ScriptedReconstructionChangeFetcher(
            pages: [
                page(
                    accountID: accountA,
                    cursor: "ordinary-before-error",
                    moreComing: true
                ).page,
            ],
            failure: .sentinel,
            failureAfterSuccessfulPageCount: 1
        )
        do {
            _ = try await context.fetchCompleteChanges(
                using: scopedChangeFetcher(transportFailure)
            )
            XCTFail("The exact transport error must emerge after cursor advance")
        } catch {
            XCTAssertEqual(error as? ReconstructionFetchSentinelError, .sentinel)
        }
        let failedRequests = await transportFailure.observedRequests()
        XCTAssertEqual(failedRequests.count, 2)
        XCTAssertEqual(
            failedRequests.map(\.cursor),
            [
                fixture.acceptedCheckpoint.finalCursor,
                cursor("ordinary-before-error"),
            ]
        )
        XCTAssertEqual(
            failedRequests.map(\.zonePreparation),
            [.requireExisting, .requireExisting]
        )

        let invalidPage = ScriptedReconstructionChangeFetcher(
            pages: [
                page(
                    accountID: accountB,
                    cursor: "ordinary-wrong-account",
                    moreComing: false
                ).page,
            ]
        )
        do {
            _ = try await context.fetchCompleteChanges(
                using: scopedChangeFetcher(invalidPage)
            )
            XCTFail("An ordinary page for another account must fail unchanged")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaAccumulatorError,
                .accountMismatch
            )
        }
    }

    func testScopedPublicationRejectsConfigurationMismatchBeforeNetworkRequest()
        async throws
    {
        let alternateConfiguration = try productionConfiguration(
            zoneName: "PlayerDataOther"
        )

        let reconstructionRoot = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: reconstructionRoot) }
        let reconstructionState = try await reconstructionFixture(
            root: reconstructionRoot
        )
        let reconstructionContext = try await beginReconstruction(
            reconstructionState,
            at: Date(timeIntervalSince1970: 3_115.5)
        )
        let reconstructionRawFetcher = ScriptedReconstructionChangeFetcher()
        do {
            _ = try await reconstructionContext.fetchCompleteSnapshot(
                using: scopedChangeFetcher(
                    reconstructionRawFetcher,
                    configuration: alternateConfiguration
                )
            )
            XCTFail("A differently configured CloudKit scope must fail")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .configurationScopeMismatch
            )
        }
        let reconstructionRequests =
            await reconstructionRawFetcher.observedRequests()
        XCTAssertTrue(reconstructionRequests.isEmpty)

        let ordinaryRoot = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: ordinaryRoot) }
        let ordinaryFixture = try await reconstructionFixture(
            root: ordinaryRoot,
            removeAcceptedCache: false
        )
        let ordinaryContext = try await beginOrdinaryPublication(
            ordinaryFixture,
            at: Date(timeIntervalSince1970: 3_115.6)
        )
        let ordinaryRawFetcher = ScriptedReconstructionChangeFetcher()
        do {
            _ = try await ordinaryContext.fetchCompleteChanges(
                using: scopedChangeFetcher(
                    ordinaryRawFetcher,
                    configuration: alternateConfiguration
                )
            )
            XCTFail("Ordinary fetch must reject a differently configured scope")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .configurationScopeMismatch
            )
        }
        let ordinaryRequests = await ordinaryRawFetcher.observedRequests()
        XCTAssertTrue(ordinaryRequests.isEmpty)
    }

    func testOrdinaryPublicationRejectsForeignAuthorityAndReactivation()
        async throws
    {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try await reconstructionFixture(
            root: root,
            removeAcceptedCache: false
        )
        let context = try await beginOrdinaryPublication(
            fixture,
            at: Date(timeIntervalSince1970: 3_115.7)
        )
        let publication = try await context.fetchCompleteChanges(
            using: scopedChangeFetcher(
                ScriptedReconstructionChangeFetcher(
                    pages: [
                        page(
                            accountID: accountA,
                            cursor: "ordinary-generation-bound",
                            moreComing: false
                        ).page,
                    ]
                )
            )
        )

        let otherAuthority = CloudAccountGenerationAuthority()
        let otherGeneration = try await otherAuthority.activate(
            accountID: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            replicaEpoch: epoch
        )
        do {
            _ = try await otherAuthority.withCurrentGeneration(
                otherGeneration
            ) { lease in
                try await fixture.store.beginIncrementalOrdinaryPublication(
                    generationLease: lease,
                    at: Date(timeIntervalSince1970: 3_115.75)
                )
            }
            XCTFail("A foreign authority cannot mint an ordinary context")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .accountGenerationAuthorityMismatch
            )
        }
        let afterForeignBeginValue = try await fixture.store
            .resumeActiveReplicaEpoch(
                for: accountA,
                configurationScopeFingerprint: scopeFingerprint()
            )
        let afterForeignBegin = try XCTUnwrap(afterForeignBeginValue)
        XCTAssertFalse(afterForeignBegin.hasDurableCheckpointIntent)
        XCTAssertEqual(
            afterForeignBegin.acceptedHistory?.generation,
            fixture.acceptedCheckpoint.generation
        )
        do {
            try await otherAuthority.withCurrentGeneration(otherGeneration) {
                lease in
                try await fixture.store.saveOrdinaryPublication(
                    publication,
                    generationLease: lease,
                    at: Date(timeIntervalSince1970: 3_115.76)
                )
            }
            XCTFail("A foreign authority cannot save an ordinary publication")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .accountGenerationAuthorityMismatch
            )
        }
        let afterForeignSaveValue = try await fixture.store
            .resumeActiveReplicaEpoch(
                for: accountA,
                configurationScopeFingerprint: scopeFingerprint()
            )
        let afterForeignSave = try XCTUnwrap(afterForeignSaveValue)
        XCTAssertFalse(afterForeignSave.hasDurableCheckpointIntent)
        XCTAssertEqual(
            afterForeignSave.acceptedHistory?.generation,
            fixture.acceptedCheckpoint.generation
        )

        try await fixture.authority.invalidate(fixture.generation)
        let reactivated = try await fixture.authority.activate(
            accountID: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            replicaEpoch: epoch
        )
        do {
            try await fixture.authority.withCurrentGeneration(reactivated) {
                lease in
                try await fixture.store.saveOrdinaryPublication(
                    publication,
                    generationLease: lease,
                    at: Date(timeIntervalSince1970: 3_115.8)
                )
            }
            XCTFail("Same-binding reactivation must not revive old fetch work")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .accountGenerationMismatch
            )
        }
        let resumedValue = try await fixture.store.resumeActiveReplicaEpoch(
            for: accountA,
            configurationScopeFingerprint: scopeFingerprint()
        )
        let resumed = try XCTUnwrap(resumedValue)
        XCTAssertFalse(resumed.hasDurableCheckpointIntent)
        XCTAssertEqual(
            resumed.acceptedHistory?.generation,
            fixture.acceptedCheckpoint.generation
        )
        let unchanged = try await fixture.store.load(
            for: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            at: Date(timeIntervalSince1970: 3_115.85)
        )
        XCTAssertEqual(unchanged.checkpoint, fixture.acceptedCheckpoint)
    }

    func testOrdinaryPublicationRevalidatesPredecessorAndPendingCandidate()
        async throws
    {
        let predecessorRoot = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: predecessorRoot) }
        let predecessorFixture = try await reconstructionFixture(
            root: predecessorRoot,
            removeAcceptedCache: false
        )
        let predecessorContext = try await beginOrdinaryPublication(
            predecessorFixture,
            at: Date(timeIntervalSince1970: 3_115.9)
        )
        let acceptedFirst = try await predecessorContext.fetchCompleteChanges(
            using: scopedChangeFetcher(
                ScriptedReconstructionChangeFetcher(
                    pages: [
                        page(
                            accountID: accountA,
                            cursor: "ordinary-accepted-first",
                            moreComing: false
                        ).page,
                    ]
                )
            )
        )
        let staleSibling = try await predecessorContext.fetchCompleteChanges(
            using: scopedChangeFetcher(
                ScriptedReconstructionChangeFetcher(
                    pages: [
                        page(
                            accountID: accountA,
                            cursor: "ordinary-stale-sibling",
                            moreComing: false
                        ).page,
                    ]
                )
            )
        )
        try await saveOrdinaryPublication(
            acceptedFirst,
            fixture: predecessorFixture,
            at: Date(timeIntervalSince1970: 3_116.0)
        )
        do {
            try await saveOrdinaryPublication(
                staleSibling,
                fixture: predecessorFixture,
                at: Date(timeIntervalSince1970: 3_116.1)
            )
            XCTFail("An advanced predecessor must invalidate sibling work")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .acceptedHistoryMismatch
            )
        }
        let predecessorResumeValue = try await predecessorFixture.store
            .resumeActiveReplicaEpoch(
                for: accountA,
                configurationScopeFingerprint: scopeFingerprint()
            )
        let predecessorResume = try XCTUnwrap(predecessorResumeValue)
        XCTAssertFalse(predecessorResume.hasDurableCheckpointIntent)
        XCTAssertEqual(
            predecessorResume.acceptedHistory?.generation,
            acceptedFirst.checkpoint.generation
        )
        let predecessorUnchanged = try await predecessorFixture.store.load(
            for: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            at: Date(timeIntervalSince1970: 3_116.15)
        )
        XCTAssertEqual(predecessorUnchanged.checkpoint, acceptedFirst.checkpoint)

        let pendingRoot = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: pendingRoot) }
        let fileSystem = FaultInjectingCheckpointFileSystem()
        let pendingFixture = try await reconstructionFixture(
            root: pendingRoot,
            fileSystem: fileSystem,
            removeAcceptedCache: false
        )
        let pendingContext = try await beginOrdinaryPublication(
            pendingFixture,
            at: Date(timeIntervalSince1970: 3_116.2)
        )
        let matching = try await pendingContext.fetchCompleteChanges(
            using: scopedChangeFetcher(
                ScriptedReconstructionChangeFetcher(
                    pages: [
                        page(
                            accountID: accountA,
                            cursor: "ordinary-matching-pending",
                            moreComing: false
                        ).page,
                    ]
                )
            )
        )
        let divergent = try await pendingContext.fetchCompleteChanges(
            using: scopedChangeFetcher(
                ScriptedReconstructionChangeFetcher(
                    pages: [
                        page(
                            accountID: accountA,
                            cursor: "ordinary-divergent-pending",
                            moreComing: false
                        ).page,
                    ]
                )
            )
        )

        fileSystem.failNextWrite(named: "checkpoint.watermark.json")
        do {
            try await saveOrdinaryPublication(
                matching,
                fixture: pendingFixture,
                at: Date(timeIntervalSince1970: 3_116.3)
            )
            XCTFail("The fault must retain the exact pending candidate")
        } catch {
            XCTAssertEqual(error as? CloudReplicaCheckpointStoreError, .ioFailure)
        }
        do {
            try await saveOrdinaryPublication(
                divergent,
                fixture: pendingFixture,
                at: Date(timeIntervalSince1970: 3_116.4)
            )
            XCTFail("A divergent result cannot replace durable pending intent")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .checkpointPublicationPending
            )
        }
        try await saveOrdinaryPublication(
            matching,
            fixture: pendingFixture,
            at: Date(timeIntervalSince1970: 3_116.5)
        )
        let loaded = try await pendingFixture.store.load(
            for: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            at: Date(timeIntervalSince1970: 3_116.6)
        )
        XCTAssertEqual(loaded.checkpoint, matching.checkpoint)
    }

    func testRequireExistingReconstructionChainsNilCursorPagesAndCommitsOnce()
        async throws
    {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try await reconstructionFixture(
            root: root,
            acceptedModifications: [
                discovered(id: "stale", locator: "provider-stale"),
            ]
        )
        let context = try await beginReconstruction(
            fixture,
            at: Date(timeIntervalSince1970: 3_117)
        )
        let fetcher = ScriptedReconstructionChangeFetcher(
            pages: [
                page(
                    accountID: accountA,
                    modifications: [
                        discovered(id: "profile", locator: "provider-profile"),
                    ],
                    cursor: "reconstruction-page-one",
                    moreComing: true
                ).page,
                page(
                    accountID: accountA,
                    modifications: [
                        discovered(id: "ledger", locator: "provider-ledger"),
                    ],
                    cursor: "reconstruction-page-two",
                    moreComing: false
                ).page,
            ]
        )

        let reconstruction = try await context.fetchCompleteSnapshot(
            using: scopedChangeFetcher(fetcher)
        )
        XCTAssertEqual(
            reconstruction.checkpoint.generation,
            fixture.acceptedCheckpoint.generation + 1
        )
        XCTAssertEqual(
            Set(reconstruction.checkpoint.recordsByLogicalID.keys),
            Set([CloudRecordID("profile"), CloudRecordID("ledger")])
        )
        let requests = await fetcher.observedRequests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests.map(\.accountID), [accountA, accountA])
        XCTAssertEqual(requests[0].cursor, nil)
        XCTAssertEqual(requests[1].cursor, cursor("reconstruction-page-one"))
        XCTAssertEqual(
            requests.map(\.zonePreparation),
            [.requireExisting, .requireExisting]
        )

        try await saveReconstruction(
            reconstruction,
            fixture: fixture,
            at: Date(timeIntervalSince1970: 3_119)
        )
        do {
            try await saveReconstruction(
                reconstruction,
                fixture: fixture,
                at: Date(timeIntervalSince1970: 3_120)
            )
            XCTFail("A reconstruction artifact must be single-use")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .acceptedHistoryMismatch
            )
        }
        let verified = try await fixture.store.load(
            for: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            at: Date(timeIntervalSince1970: 3_121)
        )
        XCTAssertEqual(verified.checkpoint, reconstruction.checkpoint)
    }

    func testRequireExistingReconstructionPreservesFetchAndAccumulatorErrors()
        async throws
    {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try await reconstructionFixture(root: root)
        let context = try await beginReconstruction(
            fixture,
            at: Date(timeIntervalSince1970: 3_122)
        )

        let failingFetcher = ScriptedReconstructionChangeFetcher(
            pages: [
                page(
                    accountID: accountA,
                    cursor: "reconstruction-before-error",
                    moreComing: true
                ).page,
            ],
            failure: .sentinel,
            failureAfterSuccessfulPageCount: 1
        )
        do {
            _ = try await context.fetchCompleteSnapshot(
                using: scopedChangeFetcher(failingFetcher)
            )
            XCTFail("The exact transport error must emerge")
        } catch {
            XCTAssertEqual(error as? ReconstructionFetchSentinelError, .sentinel)
        }
        let failedRequests = await failingFetcher.observedRequests()
        XCTAssertEqual(failedRequests.count, 2)
        XCTAssertNil(failedRequests[0].cursor)
        XCTAssertEqual(
            failedRequests[1].cursor,
            cursor("reconstruction-before-error")
        )
        XCTAssertEqual(
            failedRequests.map(\.zonePreparation),
            [.requireExisting, .requireExisting]
        )

        let missingZoneFetcher = MissingZoneReconstructionChangeFetcher()
        do {
            _ = try await context.fetchCompleteSnapshot(
                using: scopedChangeFetcher(missingZoneFetcher)
            )
            XCTFail("A missing existing zone must never become bootstrap")
        } catch {
            XCTAssertEqual(
                error as? CloudKitCloudSyncError,
                .zoneResetRequired
            )
        }
        let missingZoneRequests = await missingZoneFetcher.observedRequests()
        XCTAssertEqual(missingZoneRequests.count, 1)
        XCTAssertNil(missingZoneRequests[0].cursor)
        XCTAssertEqual(
            missingZoneRequests[0].zonePreparation,
            .requireExisting
        )

        let wrongAccountFetcher = ScriptedReconstructionChangeFetcher(
            pages: [
                page(
                    accountID: accountB,
                    cursor: "wrong-account",
                    moreComing: false
                ).page,
            ]
        )
        do {
            _ = try await context.fetchCompleteSnapshot(
                using: scopedChangeFetcher(wrongAccountFetcher)
            )
            XCTFail("A provider page for another account must fail unchanged")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaAccumulatorError,
                .accountMismatch
            )
        }

        let blockingFetcher = BlockingReconstructionChangeFetcher()
        let cancelledFetch = Task {
            try await context.fetchCompleteSnapshot(
                using: scopedChangeFetcher(blockingFetcher)
            )
        }
        var blockingFetchStarted = false
        for _ in 0 ..< 10_000 {
            blockingFetchStarted = await blockingFetcher.hasStarted()
            if blockingFetchStarted { break }
            await Task.yield()
        }
        XCTAssertTrue(blockingFetchStarted)
        cancelledFetch.cancel()
        do {
            _ = try await cancelledFetch.value
            XCTFail("Cancellation must emerge unchanged")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }

        let limitedRoot = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: limitedRoot) }
        let limitedFixture = try await reconstructionFixture(
            root: limitedRoot,
            limits: testLimits(maxPagesPerSync: 1)
        )
        let limitedContext = try await beginReconstruction(
            limitedFixture,
            at: Date(timeIntervalSince1970: 3_123)
        )
        let excessivePages = ScriptedReconstructionChangeFetcher(
            pages: [
                page(
                    accountID: accountA,
                    cursor: "limited-one",
                    moreComing: true
                ).page,
                page(
                    accountID: accountA,
                    cursor: "limited-two",
                    moreComing: false
                ).page,
            ]
        )
        do {
            _ = try await limitedContext.fetchCompleteSnapshot(
                using: scopedChangeFetcher(excessivePages)
            )
            XCTFail("The store's exact resource limits must travel with context")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaAccumulatorError,
                .pageLimitExceeded
            )
        }
    }

    func testReconstructionContextRequiresAcceptedHistoryWithoutUsableCache()
        async throws
    {
        let cachedRoot = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: cachedRoot) }
        let cached = try await reconstructionFixture(
            root: cachedRoot,
            removeAcceptedCache: false
        )
        let unboundStore = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: cachedRoot
        )
        _ = try await unboundStore.resumeActiveReplicaEpoch(
            for: accountA,
            configurationScopeFingerprint: scopeFingerprint()
        )
        do {
            _ = try await cached.authority.withCurrentGeneration(
                cached.generation
            ) { lease in
                try await unboundStore
                    .beginRequireExistingFullSnapshotReconstruction(
                        generationLease: lease,
                        at: Date(timeIntervalSince1970: 3_123.5)
                    )
            }
            XCTFail("A store without canonical generation authority must fail")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .accountGenerationAuthorityNotBound
            )
        }
        do {
            _ = try await beginReconstruction(
                cached,
                at: Date(timeIntervalSince1970: 3_124)
            )
            XCTFail("A usable accepted checkpoint must prevent reconstruction")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .acceptedCheckpointStillAvailable
            )
        }
        let emptyRoot = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: emptyRoot) }
        let authority = CloudAccountGenerationAuthority()
        let store = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: emptyRoot,
            accountGenerationAuthority: authority
        )
        try await store.activate(
            replicaEpoch: epoch,
            configurationScopeFingerprint: scopeFingerprint(),
            for: accountA
        )
        let generation = try await authority.activate(
            accountID: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            replicaEpoch: epoch
        )
        do {
            _ = try await authority.withCurrentGeneration(generation) { lease in
                try await store.beginRequireExistingFullSnapshotReconstruction(
                    generationLease: lease,
                    at: Date(timeIntervalSince1970: 3_125)
                )
            }
            XCTFail("Initial bootstrap has no accepted-history authority")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .acceptedHistoryUnavailable
            )
        }
    }

    func testReconstructionRejectsCrossAuthorityAndReactivatedGeneration()
        async throws
    {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try await reconstructionFixture(root: root)
        let context = try await beginReconstruction(
            fixture,
            at: Date(timeIntervalSince1970: 3_126)
        )
        let reconstruction = try await context.fetchCompleteSnapshot(
            using: scopedChangeFetcher(
                ScriptedReconstructionChangeFetcher(
                    pages: [
                        page(
                            accountID: accountA,
                            cursor: "generation-bound",
                            moreComing: false
                        ).page,
                    ]
                )
            )
        )

        let otherAuthority = CloudAccountGenerationAuthority()
        let otherGeneration = try await otherAuthority.activate(
            accountID: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            replicaEpoch: epoch
        )
        do {
            _ = try await otherAuthority.withCurrentGeneration(
                otherGeneration
            ) { lease in
                try await fixture.store
                    .beginRequireExistingFullSnapshotReconstruction(
                        generationLease: lease,
                        at: Date(timeIntervalSince1970: 3_126.5)
                    )
            }
            XCTFail("A foreign authority cannot mint a reconstruction context")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .accountGenerationAuthorityMismatch
            )
        }
        do {
            try await otherAuthority.withCurrentGeneration(otherGeneration) {
                lease in
                try await fixture.store.saveReconstructedFullSnapshot(
                    reconstruction,
                    generationLease: lease,
                    at: Date(timeIntervalSince1970: 3_127)
                )
            }
            XCTFail("A lease from another authority must fail")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .accountGenerationAuthorityMismatch
            )
        }
        let afterForeignLease = try await fixture.store.load(
            for: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            at: Date(timeIntervalSince1970: 3_127.1)
        )
        XCTAssertNil(afterForeignLease.checkpoint)
        let afterForeignResumeValue = try await fixture.store
            .resumeActiveReplicaEpoch(
                for: accountA,
                configurationScopeFingerprint: scopeFingerprint()
            )
        let afterForeignResume = try XCTUnwrap(afterForeignResumeValue)
        XCTAssertFalse(afterForeignResume.hasDurableCheckpointIntent)
        XCTAssertEqual(
            afterForeignResume.acceptedHistory?.generation,
            fixture.acceptedCheckpoint.generation
        )

        try await fixture.authority.invalidate(fixture.generation)
        let reactivated = try await fixture.authority.activate(
            accountID: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            replicaEpoch: epoch
        )
        XCTAssertNotEqual(reactivated, fixture.generation)
        do {
            try await fixture.authority.withCurrentGeneration(reactivated) {
                lease in
                try await fixture.store.saveReconstructedFullSnapshot(
                    reconstruction,
                    generationLease: lease,
                    at: Date(timeIntervalSince1970: 3_128)
                )
            }
            XCTFail("Same-binding reactivation must not revive an old context")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .accountGenerationMismatch
            )
        }
        let afterReactivation = try await fixture.store.load(
            for: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            at: Date(timeIntervalSince1970: 3_128.05)
        )
        XCTAssertNil(afterReactivation.checkpoint)
        let resumeValue = try await fixture.store.resumeActiveReplicaEpoch(
            for: accountA,
            configurationScopeFingerprint: scopeFingerprint()
        )
        let resumed = try XCTUnwrap(resumeValue)
        XCTAssertEqual(
            resumed.acceptedHistory?.generation,
            fixture.acceptedCheckpoint.generation
        )
        XCTAssertFalse(resumed.hasDurableCheckpointIntent)
    }

    func testReconstructionReactivationCannotUseReappearedCacheOrMatchingPending()
        async throws
    {
        let cacheRoot = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: cacheRoot) }
        let cacheFixture = try await reconstructionFixture(root: cacheRoot)
        let cacheContext = try await beginReconstruction(
            cacheFixture,
            at: Date(timeIntervalSince1970: 3_128.1)
        )
        let cacheResult = try await cacheContext.fetchCompleteSnapshot(
            using: scopedChangeFetcher(
                ScriptedReconstructionChangeFetcher(
                    pages: [
                        page(
                            accountID: accountA,
                            cursor: "reactivated-cache-result",
                            moreComing: false
                        ).page,
                    ]
                )
            )
        )
        try await cacheFixture.authority.invalidate(cacheFixture.generation)
        let cacheReactivated = try await cacheFixture.authority.activate(
            accountID: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            replicaEpoch: epoch
        )
        try await cacheFixture.store._testOnlySaveRawCheckpoint(
            cacheFixture.acceptedCheckpoint,
            at: Date(timeIntervalSince1970: 3_128.2)
        )
        do {
            try await cacheFixture.authority.withCurrentGeneration(
                cacheReactivated
            ) { lease in
                try await cacheFixture.store.saveReconstructedFullSnapshot(
                    cacheResult,
                    generationLease: lease,
                    at: Date(timeIntervalSince1970: 3_128.3)
                )
            }
            XCTFail("Reappeared cache must not revive old-generation work")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .accountGenerationMismatch
            )
        }

        let pendingRoot = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: pendingRoot) }
        let fileSystem = FaultInjectingCheckpointFileSystem()
        let pendingFixture = try await reconstructionFixture(
            root: pendingRoot,
            fileSystem: fileSystem
        )
        let pendingContext = try await beginReconstruction(
            pendingFixture,
            at: Date(timeIntervalSince1970: 3_128.4)
        )
        let pendingResult = try await pendingContext.fetchCompleteSnapshot(
            using: scopedChangeFetcher(
                ScriptedReconstructionChangeFetcher(
                    pages: [
                        page(
                            accountID: accountA,
                            cursor: "reactivated-pending-result",
                            moreComing: false
                        ).page,
                    ]
                )
            )
        )
        fileSystem.failNextWrite(named: "checkpoint.watermark.json")
        do {
            try await saveReconstruction(
                pendingResult,
                fixture: pendingFixture,
                at: Date(timeIntervalSince1970: 3_128.5)
            )
            XCTFail("The fault must leave the matching result pending")
        } catch {
            XCTAssertEqual(error as? CloudReplicaCheckpointStoreError, .ioFailure)
        }
        try await pendingFixture.authority.invalidate(pendingFixture.generation)
        let pendingReactivated = try await pendingFixture.authority.activate(
            accountID: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            replicaEpoch: epoch
        )
        do {
            try await pendingFixture.authority.withCurrentGeneration(
                pendingReactivated
            ) { lease in
                try await pendingFixture.store.saveReconstructedFullSnapshot(
                    pendingResult,
                    generationLease: lease,
                    at: Date(timeIntervalSince1970: 3_128.6)
                )
            }
            XCTFail("Matching pending intent must not revive old-generation work")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .accountGenerationMismatch
            )
        }
    }

    func testReconstructionRejectsWatermarkAdvanceAndCacheReappearance()
        async throws
    {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try await reconstructionFixture(root: root)
        let context = try await beginReconstruction(
            fixture,
            at: Date(timeIntervalSince1970: 3_129)
        )
        let firstResult = try await context.fetchCompleteSnapshot(
            using: scopedChangeFetcher(
                ScriptedReconstructionChangeFetcher(
                    pages: [
                        page(
                            accountID: accountA,
                            modifications: [
                                discovered(id: "first", locator: "provider-first"),
                            ],
                            cursor: "first-result",
                            moreComing: false
                        ).page,
                    ]
                )
            )
        )
        let advancingResult = try await context.fetchCompleteSnapshot(
            using: scopedChangeFetcher(
                ScriptedReconstructionChangeFetcher(
                    pages: [
                        page(
                            accountID: accountA,
                            modifications: [
                                discovered(id: "advance", locator: "provider-advance"),
                            ],
                            cursor: "advancing-result",
                            moreComing: false
                        ).page,
                    ]
                )
            )
        )
        try await saveReconstruction(
            advancingResult,
            fixture: fixture,
            at: Date(timeIntervalSince1970: 3_130)
        )
        do {
            try await saveReconstruction(
                firstResult,
                fixture: fixture,
                at: Date(timeIntervalSince1970: 3_131)
            )
            XCTFail("An advanced accepted watermark must invalidate old results")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .acceptedHistoryMismatch
            )
        }
        let afterAdvanceValue = try await fixture.store.resumeActiveReplicaEpoch(
            for: accountA,
            configurationScopeFingerprint: scopeFingerprint()
        )
        let afterAdvance = try XCTUnwrap(afterAdvanceValue)
        XCTAssertFalse(afterAdvance.hasDurableCheckpointIntent)
        XCTAssertEqual(
            afterAdvance.acceptedHistory?.generation,
            advancingResult.checkpoint.generation
        )

        let cacheRoot = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: cacheRoot) }
        let cacheFixture = try await reconstructionFixture(root: cacheRoot)
        let cacheContext = try await beginReconstruction(
            cacheFixture,
            at: Date(timeIntervalSince1970: 3_132)
        )
        let cacheResult = try await cacheContext.fetchCompleteSnapshot(
            using: scopedChangeFetcher(
                ScriptedReconstructionChangeFetcher(
                    pages: [
                        page(
                            accountID: accountA,
                            cursor: "cache-result",
                            moreComing: false
                        ).page,
                    ]
                )
            )
        )
        try await cacheFixture.store._testOnlySaveRawCheckpoint(
            cacheFixture.acceptedCheckpoint,
            at: Date(timeIntervalSince1970: 3_133)
        )
        do {
            try await saveReconstruction(
                cacheResult,
                fixture: cacheFixture,
                at: Date(timeIntervalSince1970: 3_134)
            )
            XCTFail("A reappeared accepted checkpoint must win over recovery")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .acceptedCheckpointStillAvailable
            )
        }
        let afterCacheValue = try await cacheFixture.store
            .resumeActiveReplicaEpoch(
                for: accountA,
                configurationScopeFingerprint: scopeFingerprint()
            )
        let afterCache = try XCTUnwrap(afterCacheValue)
        XCTAssertFalse(afterCache.hasDurableCheckpointIntent)
        XCTAssertEqual(
            afterCache.acceptedHistory?.generation,
            cacheFixture.acceptedCheckpoint.generation
        )
    }

    func testReconstructionResumesMatchingPendingAndRejectsDivergentPending()
        async throws
    {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fileSystem = FaultInjectingCheckpointFileSystem()
        let fixture = try await reconstructionFixture(
            root: root,
            fileSystem: fileSystem
        )
        let context = try await beginReconstruction(
            fixture,
            at: Date(timeIntervalSince1970: 3_135)
        )
        let matching = try await context.fetchCompleteSnapshot(
            using: scopedChangeFetcher(
                ScriptedReconstructionChangeFetcher(
                    pages: [
                        page(
                            accountID: accountA,
                            modifications: [
                                discovered(
                                    id: "pending",
                                    locator: "provider-pending"
                                ),
                            ],
                            cursor: "pending-result",
                            moreComing: false
                        ).page,
                    ]
                )
            )
        )
        let divergent = try await context.fetchCompleteSnapshot(
            using: scopedChangeFetcher(
                ScriptedReconstructionChangeFetcher(
                    pages: [
                        page(
                            accountID: accountA,
                            modifications: [
                                discovered(
                                    id: "divergent",
                                    locator: "provider-divergent"
                                ),
                            ],
                            cursor: "divergent-result",
                            moreComing: false
                        ).page,
                    ]
                )
            )
        )

        fileSystem.failNextWrite(named: "checkpoint.watermark.json")
        do {
            try await saveReconstruction(
                matching,
                fixture: fixture,
                at: Date(timeIntervalSince1970: 3_136)
            )
            XCTFail("The injected publication must retain pending intent")
        } catch {
            XCTAssertEqual(error as? CloudReplicaCheckpointStoreError, .ioFailure)
        }
        do {
            try await saveReconstruction(
                divergent,
                fixture: fixture,
                at: Date(timeIntervalSince1970: 3_137)
            )
            XCTFail("Divergent recovery cannot replace durable pending intent")
        } catch {
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .checkpointPublicationPending
            )
        }

        try await saveReconstruction(
            matching,
            fixture: fixture,
            at: Date(timeIntervalSince1970: 3_138)
        )
        let loaded = try await fixture.store.load(
            for: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            at: Date(timeIntervalSince1970: 3_139)
        )
        XCTAssertEqual(loaded.checkpoint, matching.checkpoint)
    }

    func testReconstructionRejectsDurablyRevokedEpoch() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try await reconstructionFixture(root: root)
        let context = try await beginReconstruction(
            fixture,
            at: Date(timeIntervalSince1970: 3_140)
        )
        let reconstruction = try await context.fetchCompleteSnapshot(
            using: scopedChangeFetcher(
                ScriptedReconstructionChangeFetcher(
                    pages: [
                        page(
                            accountID: accountA,
                            cursor: "revoked-result",
                            moreComing: false
                        ).page,
                    ]
                )
            )
        )
        try await AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root
        ).remove(for: accountA, revoking: epoch)

        do {
            try await saveReconstruction(
                reconstruction,
                fixture: fixture,
                at: Date(timeIntervalSince1970: 3_141)
            )
            XCTFail("Durable epoch revocation must reject a fetched result")
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
        try await store._testOnlySaveRawCheckpoint(expected, at: Date(timeIntervalSince1970: 3_105))
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
        try await writer._testOnlySaveRawCheckpoint(first, at: Date(timeIntervalSince1970: 3_107))
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
        try await store._testOnlySaveRawCheckpoint(first, at: Date(timeIntervalSince1970: 3_113))
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
        try await store._testOnlySaveRawCheckpoint(checkpointA, at: Date(timeIntervalSince1970: 3_130))
        try await store._testOnlySaveRawCheckpoint(checkpointB, at: Date(timeIntervalSince1970: 3_131))
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
        try await store._testOnlySaveRawCheckpoint(
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
        try await currentStore._testOnlySaveRawCheckpoint(first, at: Date(timeIntervalSince1970: 3_150))
        try await currentStore._testOnlySaveRawCheckpoint(second, at: Date(timeIntervalSince1970: 3_151))

        let oldStore = AtomicCloudReplicaCheckpointDiskStore(rootDirectoryURL: oldRoot)
        try await oldStore.activate(replicaEpoch: first.replicaEpoch, configurationScopeFingerprint: scopeFingerprint(), for: accountA)
        try await oldStore._testOnlySaveRawCheckpoint(first, at: Date(timeIntervalSince1970: 3_149))

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
        try await orphanStore._testOnlySaveRawCheckpoint(orphan, at: Date(timeIntervalSince1970: 3_160))

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
        try await relaunched._testOnlySaveRawCheckpoint(
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
        try await orphanStore._testOnlySaveRawCheckpoint(orphan, at: Date(timeIntervalSince1970: 3_170))

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

        try await freshStore._testOnlySaveRawCheckpoint(
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
        try await writer._testOnlySaveRawCheckpoint(
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
        try await rotator._testOnlySaveRawCheckpoint(
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
        try await staleStore._testOnlySaveRawCheckpoint(
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
        try await rotator._testOnlySaveRawCheckpoint(
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
        try await store._testOnlySaveRawCheckpoint(first, at: Date(timeIntervalSince1970: 3_200))

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
            try await store._testOnlySaveRawCheckpoint(second, at: Date(timeIntervalSince1970: 3_201))
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
        try await store._testOnlySaveRawCheckpoint(first, at: Date(timeIntervalSince1970: 3_225))

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
            try await store._testOnlySaveRawCheckpoint(second, at: Date(timeIntervalSince1970: 3_226))
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
        try await store._testOnlySaveRawCheckpoint(first, at: Date(timeIntervalSince1970: 3_230))

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
            try await store._testOnlySaveRawCheckpoint(second, at: Date(timeIntervalSince1970: 3_231))
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
        try await store._testOnlySaveRawCheckpoint(first, at: Date(timeIntervalSince1970: 3_235))

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
            try await store._testOnlySaveRawCheckpoint(second, at: Date(timeIntervalSince1970: 3_236))
            XCTFail("The injected primary write must interrupt publication")
        } catch {
            XCTAssertEqual(error as? CloudReplicaCheckpointStoreError, .ioFailure)
        }
        do {
            try await store._testOnlySaveRawCheckpoint(
                divergentSecond,
                at: Date(timeIntervalSince1970: 3_237)
            )
            XCTFail("A divergent retry of the pending generation must fail")
        } catch {
            XCTAssertEqual(error as? CloudReplicaCheckpointStoreError, .generationCollision)
        }

        try await store._testOnlySaveRawCheckpoint(second, at: Date(timeIntervalSince1970: 3_238))
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
        try await store._testOnlySaveRawCheckpoint(expected, at: Date(timeIntervalSince1970: 3_240))
        let divergentStore = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: divergentRoot
        )
        try await divergentStore.activate(
            replicaEpoch: divergent.replicaEpoch,
            configurationScopeFingerprint: scopeFingerprint(),
            for: accountA
        )
        try await divergentStore._testOnlySaveRawCheckpoint(
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
        try await store._testOnlySaveRawCheckpoint(first, at: Date(timeIntervalSince1970: 3_243))

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
            try await store._testOnlySaveRawCheckpoint(
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
        try await relaunched._testOnlySaveRawCheckpoint(
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
        try await store._testOnlySaveRawCheckpoint(first, at: Date(timeIntervalSince1970: 3_248))
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
            try await store._testOnlySaveRawCheckpoint(second, at: Date(timeIntervalSince1970: 3_249))
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
            try await store._testOnlySaveRawCheckpoint(
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
        try await relaunched._testOnlySaveRawCheckpoint(
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
        try await store._testOnlySaveRawCheckpoint(first, at: Date(timeIntervalSince1970: 3_250))
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
            try await store._testOnlySaveRawCheckpoint(second, at: Date(timeIntervalSince1970: 3_251))
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
        try await relaunched._testOnlySaveRawCheckpoint(
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
        try await store._testOnlySaveRawCheckpoint(first, at: Date(timeIntervalSince1970: 3_260))
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
        try await store._testOnlySaveRawCheckpoint(second, at: Date(timeIntervalSince1970: 3_261))

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
        try await store._testOnlySaveRawCheckpoint(expected, at: Date(timeIntervalSince1970: 3_300))
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
        try await store._testOnlySaveRawCheckpoint(first, at: Date(timeIntervalSince1970: 3_400))
        try await store._testOnlySaveRawCheckpoint(first, at: Date(timeIntervalSince1970: 3_401))

        let collision = try checkpoint(
            modifications: [discovered(id: "different", locator: "provider-different")]
        )
        do {
            try await store._testOnlySaveRawCheckpoint(collision, at: Date(timeIntervalSince1970: 3_402))
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
        try await store._testOnlySaveRawCheckpoint(second, at: Date(timeIntervalSince1970: 3_403))
        do {
            try await store._testOnlySaveRawCheckpoint(first, at: Date(timeIntervalSince1970: 3_404))
            XCTFail("A stale generation must be rejected")
        } catch {
            XCTAssertEqual(error as? CloudReplicaCheckpointStoreError, .staleGeneration)
        }

        let gap = try checkpointCopy(second, generation: 4)
        do {
            try await store._testOnlySaveRawCheckpoint(gap, at: Date(timeIntervalSince1970: 3_405))
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
        try await store._testOnlySaveRawCheckpoint(expected, at: Date(timeIntervalSince1970: 3_500))
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
        try await store._testOnlySaveRawCheckpoint(expected, at: Date(timeIntervalSince1970: 3_550))
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
        try await permissive._testOnlySaveRawCheckpoint(expected, at: Date(timeIntervalSince1970: 3_600))

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
        try await store._testOnlySaveRawCheckpoint(checkpointA, at: Date(timeIntervalSince1970: 4_000))
        try await store._testOnlySaveRawCheckpoint(checkpointB, at: Date(timeIntervalSince1970: 4_001))

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
        try await staleWriter._testOnlySaveRawCheckpoint(old, at: Date(timeIntervalSince1970: 4_100))

        try await remover.remove(for: accountA, revoking: old.replicaEpoch)
        do {
            try await staleWriter._testOnlySaveRawCheckpoint(old, at: Date(timeIntervalSince1970: 4_101))
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
        try await relaunched._testOnlySaveRawCheckpoint(replacement, at: Date(timeIntervalSince1970: 4_102))
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
            try await store._testOnlySaveRawCheckpoint(
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
        try await staleWriter._testOnlySaveRawCheckpoint(old, at: Date(timeIntervalSince1970: 4_300))

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
                try await staleWriter._testOnlySaveRawCheckpoint(
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

    private enum InitialBootstrapEvidenceScenario: String, CaseIterable {
        case corruptWatermark
        case loneValidPrimary
        case loneInvalidBackup
        case divergentCopies
        case priorQuarantine
    }

    private func installInitialBootstrapEvidence(
        _ scenario: InitialBootstrapEvidenceScenario,
        root: URL,
        validEnvelopeA: Data,
        validEnvelopeB: Data
    ) throws {
        let locations = storageLocations(root: root, accountID: accountA)
        switch scenario {
        case .corruptWatermark:
            try FileManager.default.createDirectory(
                at: locations.directory,
                withIntermediateDirectories: true
            )
            try Data("corrupt-watermark".utf8).write(
                to: locations.watermark,
                options: .atomic
            )
        case .loneValidPrimary:
            try FileManager.default.createDirectory(
                at: locations.directory,
                withIntermediateDirectories: true
            )
            try validEnvelopeA.write(to: locations.primary, options: .atomic)
        case .loneInvalidBackup:
            try FileManager.default.createDirectory(
                at: locations.directory,
                withIntermediateDirectories: true
            )
            try Data("invalid-backup".utf8).write(
                to: locations.backup,
                options: .atomic
            )
        case .divergentCopies:
            try FileManager.default.createDirectory(
                at: locations.directory,
                withIntermediateDirectories: true
            )
            try validEnvelopeA.write(to: locations.primary, options: .atomic)
            try validEnvelopeB.write(to: locations.backup, options: .atomic)
        case .priorQuarantine:
            try FileManager.default.createDirectory(
                at: locations.quarantine,
                withIntermediateDirectories: true
            )
            try Data("prior-corrupt-checkpoint".utf8).write(
                to: locations.quarantine.appendingPathComponent(
                    "checkpoint-primary-corrupt.json"
                ),
                options: .atomic
            )
        }
    }

    private struct InitialBootstrapFixture {
        let authority: CloudAccountGenerationAuthority
        let store: AtomicCloudReplicaCheckpointDiskStore
        let generation: ActiveCloudAccountGeneration
    }

    private func initialBootstrapFixture(
        root: URL,
        fileSystem: any CloudReplicaCheckpointFileSystem =
            FoundationCloudReplicaCheckpointFileSystem(),
        limits: CloudReplicaResourceLimits = .production,
        reservationUUIDFactory: @escaping @Sendable () -> UUID = { UUID() },
        maximumIssuedReservationCount: Int = 4_096
    ) async throws -> InitialBootstrapFixture {
        let authority = CloudAccountGenerationAuthority()
        let store = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root,
            fileSystem: fileSystem,
            limits: limits,
            accountGenerationAuthority: authority,
            initialBootstrapReservationUUIDFactory: reservationUUIDFactory,
            maximumIssuedInitialBootstrapReservationCount:
                maximumIssuedReservationCount
        )
        try await store.activate(
            replicaEpoch: epoch,
            configurationScopeFingerprint: scopeFingerprint(),
            for: accountA
        )
        let generation = try await authority.activate(
            accountID: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            replicaEpoch: epoch
        )
        return InitialBootstrapFixture(
            authority: authority,
            store: store,
            generation: generation
        )
    }

    private func beginInitialBootstrap(
        _ fixture: InitialBootstrapFixture,
        at date: Date
    ) async throws -> CloudReplicaInitialBootstrapPublicationContextV1 {
        try await fixture.authority.withCurrentGeneration(
            fixture.generation
        ) { lease in
            try await fixture.store.beginInitialBootstrapPublication(
                generationLease: lease,
                at: date
            )
        }
    }

    private func saveInitialBootstrap(
        _ publication: CloudReplicaInitialBootstrapPublicationV1,
        fixture: InitialBootstrapFixture,
        at date: Date
    ) async throws {
        try await fixture.authority.withCurrentGeneration(
            fixture.generation
        ) { lease in
            try await fixture.store.saveInitialBootstrapPublication(
                publication,
                generationLease: lease,
                at: date
            )
        }
    }

    private func assertNoDurableCheckpoint(
        _ fixture: InitialBootstrapFixture,
        at date: Date,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let resumedValue = try await fixture.store.resumeActiveReplicaEpoch(
            for: accountA,
            configurationScopeFingerprint: scopeFingerprint()
        )
        let resumed = try XCTUnwrap(resumedValue, file: file, line: line)
        XCTAssertNil(resumed.acceptedHistory, file: file, line: line)
        XCTAssertFalse(
            resumed.hasDurableCheckpointIntent,
            file: file,
            line: line
        )
        let loaded = try await fixture.store.load(
            for: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            at: date
        )
        XCTAssertNil(loaded.checkpoint, file: file, line: line)
    }

    private struct ReconstructionFixture {
        let authority: CloudAccountGenerationAuthority
        let store: AtomicCloudReplicaCheckpointDiskStore
        let generation: ActiveCloudAccountGeneration
        let acceptedCheckpoint: CloudReplicaCheckpointV1
    }

    private func reconstructionFixture(
        root: URL,
        fileSystem: any CloudReplicaCheckpointFileSystem =
            FoundationCloudReplicaCheckpointFileSystem(),
        limits: CloudReplicaResourceLimits = .production,
        removeAcceptedCache: Bool = true,
        acceptedModifications: [CloudDiscoveredRecord] = []
    ) async throws -> ReconstructionFixture {
        let authority = CloudAccountGenerationAuthority()
        let writer = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root,
            fileSystem: fileSystem,
            limits: limits,
            accountGenerationAuthority: authority
        )
        try await writer.activate(
            replicaEpoch: epoch,
            configurationScopeFingerprint: scopeFingerprint(),
            for: accountA
        )
        let generation = try await authority.activate(
            accountID: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            replicaEpoch: epoch
        )
        let acceptedCheckpoint = try checkpoint(
            modifications: acceptedModifications
        )
        try await writer._testOnlySaveRawCheckpoint(
            acceptedCheckpoint,
            at: Date(timeIntervalSince1970: 3_110)
        )
        if removeAcceptedCache {
            let locations = storageLocations(root: root, accountID: accountA)
            try FoundationCloudReplicaCheckpointFileSystem().removeItem(
                at: locations.directory
            )
        }

        let store = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root,
            fileSystem: fileSystem,
            limits: limits,
            accountGenerationAuthority: authority
        )
        let resumeValue = try await store.resumeActiveReplicaEpoch(
            for: accountA,
            configurationScopeFingerprint: scopeFingerprint()
        )
        let resumed = try XCTUnwrap(resumeValue)
        XCTAssertEqual(resumed.replicaEpoch, epoch)
        XCTAssertEqual(
            resumed.acceptedHistory?.generation,
            acceptedCheckpoint.generation
        )
        return ReconstructionFixture(
            authority: authority,
            store: store,
            generation: generation,
            acceptedCheckpoint: acceptedCheckpoint
        )
    }

    private func beginReconstruction(
        _ fixture: ReconstructionFixture,
        at date: Date
    ) async throws -> CloudReplicaRequireExistingReconstructionContextV1 {
        try await fixture.authority.withCurrentGeneration(
            fixture.generation
        ) { lease in
            try await fixture.store
                .beginRequireExistingFullSnapshotReconstruction(
                    generationLease: lease,
                    at: date
                )
        }
    }

    private func beginOrdinaryPublication(
        _ fixture: ReconstructionFixture,
        at date: Date
    ) async throws -> CloudReplicaIncrementalOrdinaryPublicationContextV1 {
        try await fixture.authority.withCurrentGeneration(
            fixture.generation
        ) { lease in
            try await fixture.store.beginIncrementalOrdinaryPublication(
                generationLease: lease,
                at: date
            )
        }
    }

    private func saveOrdinaryPublication(
        _ publication: CloudReplicaOrdinaryPublicationV1,
        fixture: ReconstructionFixture,
        at date: Date
    ) async throws {
        try await fixture.authority.withCurrentGeneration(
            fixture.generation
        ) { lease in
            try await fixture.store.saveOrdinaryPublication(
                publication,
                generationLease: lease,
                at: date
            )
        }
    }

    private func saveReconstruction(
        _ reconstruction: CloudReplicaReconstructedFullSnapshotV1,
        fixture: ReconstructionFixture,
        at date: Date
    ) async throws {
        try await fixture.authority.withCurrentGeneration(
            fixture.generation
        ) { lease in
            try await fixture.store.saveReconstructedFullSnapshot(
                reconstruction,
                generationLease: lease,
                at: date
            )
        }
    }

    private func scopedChangeFetcher(
        _ changeFetcher: any CloudSyncChangeFetching,
        configuration: ProductionCloudWriteConfiguration? = nil
    ) -> CloudReplicaScopedChangeFetcherV1 {
        ._testOnly(
            configuration: configuration ?? (try! productionConfiguration()),
            changeFetcher: changeFetcher
        )
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

    private func waitUntilAsync(
        _ predicate: @escaping @Sendable () async -> Bool
    ) async -> Bool {
        for _ in 0 ..< 5_000 {
            if await predicate() { return true }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return await predicate()
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
        containerEnvironment: CloudKitContainerEnvironment = .production,
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
            transport: try CloudKitCloudSyncConfiguration._testOnly(
                containerIdentifier: containerIdentifier,
                containerEnvironment: containerEnvironment,
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

    private struct DirectorySnapshot: Equatable {
        let directories: Set<String>
        let files: [String: Data]
    }

    private func directorySnapshot(at root: URL) throws -> DirectorySnapshot {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: root.path) else {
            return DirectorySnapshot(directories: [], files: [:])
        }
        let standardizedRoot = root.standardizedFileURL
        let pathPrefix = standardizedRoot.path + "/"
        var directories: Set<String> = [""]
        var files: [String: Data] = [:]
        guard let enumerator = fileManager.enumerator(
            at: standardizedRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else {
            throw CloudReplicaCheckpointStoreError.ioFailure
        }
        for case let url as URL in enumerator {
            let standardizedURL = url.standardizedFileURL
            guard standardizedURL.path.hasPrefix(pathPrefix) else {
                throw CloudReplicaCheckpointStoreError.ioFailure
            }
            let relativePath = String(
                standardizedURL.path.dropFirst(pathPrefix.count)
            )
            let values = try standardizedURL.resourceValues(
                forKeys: [.isDirectoryKey]
            )
            if values.isDirectory == true {
                directories.insert(relativePath)
            } else {
                files[relativePath] = try Data(contentsOf: standardizedURL)
            }
        }
        return DirectorySnapshot(directories: directories, files: files)
    }

    private func replicaAuthorityJSONObject(
        at url: URL
    ) throws -> [String: Any] {
        try replicaAuthorityJSONObject(from: Data(contentsOf: url))
    }

    private func replicaAuthorityJSONObject(
        from data: Data
    ) throws -> [String: Any] {
        try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
    }

    private func replicaAuthorityData(
        _ object: [String: Any]
    ) throws -> Data {
        try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys]
        )
    }

    private func initialBootstrapReservationJSONObject(
        reservationID: UUID = UUID(),
        activeAttemptSequence: UInt64,
        phase: String
    ) -> [String: Any] {
        [
            "formatVersion": 1,
            "reservationID": reservationID.uuidString,
            "activeAttemptSequence": NSNumber(
                value: activeAttemptSequence
            ),
            "phase": phase,
        ]
    }

    private func assertInvalidReplicaAuthority(
        _ object: [String: Any],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let data = try replicaAuthorityData(object)
        XCTAssertThrowsError(
            try AtomicCloudReplicaCheckpointDiskStore
                ._testOnlyRoundTripReplicaAuthority(data),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(
                error as? CloudReplicaCheckpointStoreError,
                .invalidCheckpoint,
                file: file,
                line: line
            )
        }
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

private enum ReconstructionFetchSentinelError: Error, Equatable, Sendable {
    case sentinel
    case scriptExhausted
    case unexpectedReturn
}

private final class ScriptedReservationUUIDFactory: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [UUID]

    init(_ values: [UUID]) {
        self.values = values
    }

    func next() -> UUID {
        lock.lock()
        defer { lock.unlock() }
        precondition(!values.isEmpty, "Reservation UUID script exhausted")
        return values.removeFirst()
    }
}

private actor ScriptedReconstructionChangeFetcher: CloudSyncChangeFetching {
    struct Request: Equatable, Sendable {
        let accountID: CloudAccountID
        let cursor: CloudChangeCursor?
        let zonePreparation: CloudZonePreparationPolicy
    }

    private var pages: [CloudRecordChangePage]
    private var failure: ReconstructionFetchSentinelError?
    private let failureAfterSuccessfulPageCount: Int
    private var successfulPageCount = 0
    private var requests: [Request] = []

    init(
        pages: [CloudRecordChangePage] = [],
        failure: ReconstructionFetchSentinelError? = nil,
        failureAfterSuccessfulPageCount: Int = 0
    ) {
        precondition(failureAfterSuccessfulPageCount >= 0)
        self.pages = pages
        self.failure = failure
        self.failureAfterSuccessfulPageCount = failureAfterSuccessfulPageCount
    }

    func recordChanges(
        accountID: CloudAccountID,
        after cursor: CloudChangeCursor?,
        zonePreparation: CloudZonePreparationPolicy
    ) throws -> CloudRecordChangePage {
        requests.append(
            Request(
                accountID: accountID,
                cursor: cursor,
                zonePreparation: zonePreparation
            )
        )
        if let failure,
           successfulPageCount >= failureAfterSuccessfulPageCount {
            self.failure = nil
            throw failure
        }
        guard !pages.isEmpty else {
            throw ReconstructionFetchSentinelError.scriptExhausted
        }
        successfulPageCount += 1
        return pages.removeFirst()
    }

    func observedRequests() -> [Request] {
        requests
    }
}

private actor MissingZoneReconstructionChangeFetcher: CloudSyncChangeFetching {
    struct Request: Equatable, Sendable {
        let accountID: CloudAccountID
        let cursor: CloudChangeCursor?
        let zonePreparation: CloudZonePreparationPolicy
    }

    private var pages: [CloudRecordChangePage]
    private var requests: [Request] = []

    init(pages: [CloudRecordChangePage] = []) {
        self.pages = pages
    }

    func recordChanges(
        accountID: CloudAccountID,
        after cursor: CloudChangeCursor?,
        zonePreparation: CloudZonePreparationPolicy
    ) throws -> CloudRecordChangePage {
        requests.append(
            Request(
                accountID: accountID,
                cursor: cursor,
                zonePreparation: zonePreparation
            )
        )
        if !pages.isEmpty {
            return pages.removeFirst()
        }
        throw CloudKitCloudSyncError.zoneResetRequired
    }

    func observedRequests() -> [Request] {
        requests
    }
}

private actor BlockingReconstructionChangeFetcher: CloudSyncChangeFetching {
    private var started = false

    func recordChanges(
        accountID: CloudAccountID,
        after cursor: CloudChangeCursor?,
        zonePreparation: CloudZonePreparationPolicy
    ) async throws -> CloudRecordChangePage {
        _ = accountID
        _ = cursor
        _ = zonePreparation
        started = true
        try await Task.sleep(for: .seconds(60))
        throw ReconstructionFetchSentinelError.unexpectedReturn
    }

    func hasStarted() -> Bool {
        started
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

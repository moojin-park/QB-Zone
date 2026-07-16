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
            "3cf897580315794f23fa98294a6da0aa541cde3168a9b271497abd366ab21380"
        )
        XCTAssertEqual(fingerprint.rawValue.count, 64)

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
        ]
        let variantFingerprints = variants.map(CloudReplicaScopeFingerprint.make(for:))
        XCTAssertEqual(Set(variantFingerprints).count, variants.count)
        XCTAssertTrue(variantFingerprints.allSatisfy { $0 != fingerprint })
    }

    func testDiskStoreRecoversPrimaryFromBackupAndRepairsCorruptBackup() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AtomicCloudReplicaCheckpointDiskStore(rootDirectoryURL: root)
        let expected = try checkpoint(
            modifications: [discovered(id: "profile", locator: "provider-profile")]
        )
        try await store.activate(replicaEpoch: expected.replicaEpoch, for: accountA)
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

    func testCorruptAndMismatchedEnvelopesNeverBecomeCurrent() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AtomicCloudReplicaCheckpointDiskStore(rootDirectoryURL: root)
        let expected = try checkpoint(
            modifications: [discovered(id: "profile", locator: "provider-profile")]
        )
        try await store.activate(replicaEpoch: expected.replicaEpoch, for: accountA)
        try await store.save(expected, at: Date(timeIntervalSince1970: 2_000))

        let wrongScope = try await store.load(
            for: accountA,
            configurationScopeFingerprint: alternateScopeFingerprint(),
            at: Date(timeIntervalSince1970: 2_001)
        )
        XCTAssertNil(wrongScope.checkpoint)
        XCTAssertEqual(wrongScope.source, .none)
        XCTAssertEqual(wrongScope.quarantinedFileCount, 3)

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
        try await store.activate(replicaEpoch: checkpointA.replicaEpoch, for: accountA)
        try await store.activate(replicaEpoch: checkpointB.replicaEpoch, for: accountB)
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
        try await writer.activate(replicaEpoch: expected.replicaEpoch, for: accountA)
        try await writer.save(expected, at: Date(timeIntervalSince1970: 3_100))

        let relaunched = AtomicCloudReplicaCheckpointDiskStore(rootDirectoryURL: root)
        let loaded = try await relaunched.load(
            for: accountA,
            configurationScopeFingerprint: scopeFingerprint(),
            at: Date(timeIntervalSince1970: 3_101)
        )
        XCTAssertEqual(loaded.checkpoint, expected)
        try await relaunched.activate(replicaEpoch: expected.replicaEpoch, for: accountA)
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
        try await currentStore.activate(replicaEpoch: first.replicaEpoch, for: accountA)
        try await currentStore.save(first, at: Date(timeIntervalSince1970: 3_150))
        try await currentStore.save(second, at: Date(timeIntervalSince1970: 3_151))

        let oldStore = AtomicCloudReplicaCheckpointDiskStore(rootDirectoryURL: oldRoot)
        try await oldStore.activate(replicaEpoch: first.replicaEpoch, for: accountA)
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
            for: accountA
        )
        try await orphanStore.save(orphan, at: Date(timeIntervalSince1970: 3_160))

        let freshStore = AtomicCloudReplicaCheckpointDiskStore(rootDirectoryURL: root)
        try await freshStore.activate(
            replicaEpoch: replacement.replicaEpoch,
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
            for: accountA
        )
        try await orphanStore.save(orphan, at: Date(timeIntervalSince1970: 3_170))

        let freshStore = AtomicCloudReplicaCheckpointDiskStore(rootDirectoryURL: root)
        try await freshStore.activate(
            replicaEpoch: replacement.replicaEpoch,
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
            try await rotator.activate(replicaEpoch: newEpoch, for: accountA)
            XCTFail("The injected authority publication must fail")
        } catch {
            XCTAssertEqual(error as? CloudReplicaCheckpointStoreError, .ioFailure)
        }
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: locations.directory.path),
            "Unowned cache must be cleared before new authority is published"
        )

        try await rotator.activate(replicaEpoch: newEpoch, for: accountA)
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
        try await rotator.activate(replicaEpoch: newEpoch, for: accountA)
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
        try await store.activate(replicaEpoch: first.replicaEpoch, for: accountA)
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
        try await store.activate(replicaEpoch: first.replicaEpoch, for: accountA)
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
        try await store.activate(replicaEpoch: first.replicaEpoch, for: accountA)
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
        try await store.activate(replicaEpoch: first.replicaEpoch, for: accountA)
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
        try await store.activate(replicaEpoch: expected.replicaEpoch, for: accountA)
        try await store.save(expected, at: Date(timeIntervalSince1970: 3_240))
        let divergentStore = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: divergentRoot
        )
        try await divergentStore.activate(
            replicaEpoch: divergent.replicaEpoch,
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
        try await store.activate(replicaEpoch: first.replicaEpoch, for: accountA)
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
        try await relaunched.activate(replicaEpoch: first.replicaEpoch, for: accountA)
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
        try await store.activate(replicaEpoch: first.replicaEpoch, for: accountA)
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
        try await store.activate(replicaEpoch: first.replicaEpoch, for: accountA)
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
        try await relaunched.activate(replicaEpoch: first.replicaEpoch, for: accountA)
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
        try await store.activate(replicaEpoch: first.replicaEpoch, for: accountA)
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
        try await store.activate(replicaEpoch: expected.replicaEpoch, for: accountA)
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
        try await store.activate(replicaEpoch: first.replicaEpoch, for: accountA)
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
        try await store.activate(replicaEpoch: expected.replicaEpoch, for: accountA)
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
        try await store.activate(replicaEpoch: expected.replicaEpoch, for: accountA)
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
        try await permissive.activate(replicaEpoch: expected.replicaEpoch, for: accountA)
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
        try await store.activate(replicaEpoch: checkpointA.replicaEpoch, for: accountA)
        try await store.activate(replicaEpoch: checkpointB.replicaEpoch, for: accountB)
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
        try await staleWriter.activate(replicaEpoch: old.replicaEpoch, for: accountA)
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
                .activate(replicaEpoch: old.replicaEpoch, for: accountA)
            XCTFail("A relaunched store must not reactivate a revoked epoch")
        } catch {
            XCTAssertEqual(error as? CloudReplicaCheckpointStoreError, .replicaEpochRevoked)
        }

        let newEpoch = UUID(uuidString: "bbbbbbbb-cccc-4ddd-8eee-ffffffffffff")!
        let replacement = try checkpoint(replicaEpoch: newEpoch, modifications: [])
        let relaunched = AtomicCloudReplicaCheckpointDiskStore(rootDirectoryURL: root)
        try await relaunched.activate(replicaEpoch: newEpoch, for: accountA)
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
            try await store.activate(replicaEpoch: replicaEpoch, for: accountA)
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
                .activate(replicaEpoch: retiredEpochs[0], for: accountA)
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
        try await staleWriter.activate(replicaEpoch: old.replicaEpoch, for: accountA)
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
        for _ in 0 ..< 10_000 {
            if predicate() { return true }
            await Task.yield()
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
        economyPayloadFieldName: String = "economyPayload"
    ) throws -> ProductionCloudWriteConfiguration {
        ProductionCloudWriteConfiguration(
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
                payloadFieldName: economyPayloadFieldName
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
    private var nextWriteName: String?
    private var successfulMatchingWritesBeforeFailure = 0
    private var shouldFailNextMove = false
    private var nextBlockedWriteName: String?
    private var blockedWriteStarted = false
    private var mayReleaseBlockedWrite = false
    private var exclusiveLockAttempts = 0

    func failNextWrite(named name: String) {
        failWrite(named: name, afterSuccessfulMatchingWrites: 0)
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

    func createDirectory(at url: URL) throws {
        try base.createDirectory(at: url)
    }

    func fileExists(at url: URL) -> Bool {
        base.fileExists(at: url)
    }

    func fileSize(at url: URL) throws -> Int {
        try base.fileSize(at: url)
    }

    func read(from url: URL) throws -> Data {
        try base.read(from: url)
    }

    func writeAtomically(_ data: Data, to url: URL) throws {
        lock.lock()
        var shouldFail = false
        if nextWriteName == url.lastPathComponent {
            if successfulMatchingWritesBeforeFailure > 0 {
                successfulMatchingWritesBeforeFailure -= 1
            } else {
                shouldFail = true
                nextWriteName = nil
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
    }

    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        lock.lock()
        let shouldFail = shouldFailNextMove
        if shouldFail {
            shouldFailNextMove = false
        }
        lock.unlock()
        if shouldFail {
            throw InjectedFailure.requested
        }
        try base.moveItem(at: sourceURL, to: destinationURL)
    }

    func removeItem(at url: URL) throws {
        try base.removeItem(at: url)
    }

    func withExclusiveLock(at url: URL, perform: () throws -> Void) throws {
        lock.lock()
        exclusiveLockAttempts += 1
        lock.unlock()
        try base.withExclusiveLock(at: url, perform: perform)
    }
}

private extension Array where Element == String {
    var cloudIDs: Set<CloudRecordID> {
        Set(map { CloudRecordID($0) })
    }
}

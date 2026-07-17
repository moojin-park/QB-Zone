import Foundation
import XCTest

@testable import PocketVector

final class ProfileHydrationJournalTests: XCTestCase, @unchecked Sendable {
    func testMakeBindsExactProfilesDerivedTargetAndCompleteCheckpoint() throws {
        let fixture = try ProfileHydrationTestFixture()
        let journal = fixture.journal

        XCTAssertEqual(journal.source.accountIdentity, fixture.sourceAccount)
        XCTAssertEqual(journal.source.sessionNonce, fixture.sourceSession.nonce)
        XCTAssertEqual(journal.source.profileID, fixture.sourceProfileID)
        XCTAssertEqual(journal.source.playerRevision, 4)
        XCTAssertEqual(journal.source.economyRevision, 4)
        XCTAssertEqual(journal.candidatePlayerRevision, 5)
        XCTAssertEqual(journal.candidateEconomyRevision, 5)
        XCTAssertEqual(
            journal.sourceProfileEnvelopeDigest,
            .envelopeBytes(fixture.sourceEnvelope)
        )
        XCTAssertEqual(
            journal.candidateProfileEnvelopeDigest,
            .envelopeBytes(fixture.candidateEnvelope)
        )
        XCTAssertEqual(journal.target.cloudAccountID, fixture.cloudAccountID)
        XCTAssertEqual(journal.target.profileID, fixture.targetBindings.durableAccountBinding.profileID)
        XCTAssertEqual(journal.targetCheckpoint, fixture.targetCheckpoint)
        XCTAssertTrue(journal.targetCheckpointIdentity.matches(fixture.targetCheckpoint))
        XCTAssertNoThrow(try journal.validate())
    }

    func testCanonicalJournalBytesRoundTripExactly() throws {
        let journal = try ProfileHydrationTestFixture().journal
        let first = try ProfileHydrationCanonicalCodec.encode(journal)
        let decoded = try ProfileHydrationCanonicalCodec.decode(
            ProfileHydrationJournalV1.self,
            from: first
        )
        let second = try ProfileHydrationCanonicalCodec.encode(decoded)

        XCTAssertEqual(first, second)
        XCTAssertEqual(decoded, journal)
    }

    func testCanonicalJournalBytesIgnoreEveryCheckpointMapInsertionOrder() throws {
        let fixture = try ProfileHydrationTestFixture()
        let records = [
            fixture.record(id: "b", value: 2),
            fixture.record(id: "a", value: 1),
        ]
        let tombstones = [
            fixture.tombstone(id: "deleted-b"),
            fixture.tombstone(id: "deleted-a"),
        ]
        let firstCheckpoint = try fixture.checkpoint(
            generation: 1,
            cursorByte: 1,
            records: records,
            tombstones: tombstones
        )
        let secondCheckpoint = try fixture.checkpoint(
            generation: 1,
            cursorByte: 1,
            records: Array(records.reversed()),
            tombstones: Array(tombstones.reversed())
        )
        let first = try fixture.makeJournal(
            targetCheckpoint: firstCheckpoint
        )
        let second = try fixture.makeJournal(
            targetCheckpoint: secondCheckpoint
        )

        let firstBytes = try ProfileHydrationCanonicalCodec.encode(first)
        let secondBytes = try ProfileHydrationCanonicalCodec.encode(second)
        XCTAssertEqual(firstBytes, secondBytes)

        let decoded = try ProfileHydrationCanonicalCodec.decode(
            ProfileHydrationJournalV1.self,
            from: firstBytes
        )
        XCTAssertEqual(
            try ProfileHydrationCanonicalCodec.encode(decoded),
            firstBytes
        )
    }

    func testCanonicalCodecDeterministicallySortsEveryCheckpointMapArray()
        throws
    {
        let forward = ProfileHydrationCheckpointMapEncodingProbe(
            pairs: [("b", 2), ("a", 1)]
        )
        let reversed = ProfileHydrationCheckpointMapEncodingProbe(
            pairs: [("a", 1), ("b", 2)]
        )
        let rawEncoder = JSONEncoder()
        rawEncoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

        XCTAssertNotEqual(
            try rawEncoder.encode(forward),
            try rawEncoder.encode(reversed),
            "The probe must present opposite alternating-array orders"
        )
        XCTAssertEqual(
            try ProfileHydrationCanonicalCodec.encode(forward),
            try ProfileHydrationCanonicalCodec.encode(reversed),
            "Every checkpoint map array must be normalized"
        )
    }

    func testCheckpointIdentityIsStableAcrossDictionaryInsertionOrder() throws {
        let fixture = try ProfileHydrationTestFixture()
        let first = try fixture.checkpoint(
            generation: 1,
            cursorByte: 1,
            records: [
                fixture.record(id: "b", value: 2),
                fixture.record(id: "a", value: 1),
            ]
        )
        let second = try fixture.checkpoint(
            generation: 1,
            cursorByte: 1,
            records: [
                fixture.record(id: "a", value: 1),
                fixture.record(id: "b", value: 2),
            ]
        )

        XCTAssertEqual(
            ProfileHydrationCheckpointIdentityV1(checkpoint: first),
            ProfileHydrationCheckpointIdentityV1(checkpoint: second)
        )
    }

    func testCheckpointIdentityChangesForEveryBoundCheckpointSection() throws {
        let fixture = try ProfileHydrationTestFixture()
        let base = try fixture.checkpoint(
            generation: 1,
            cursorByte: 1,
            records: [fixture.record(id: "record", value: 1)]
        )
        let identities = try [
            fixture.checkpoint(
                generation: 1,
                cursorByte: 2,
                records: [fixture.record(id: "record", value: 1)]
            ),
            fixture.checkpoint(
                generation: 2,
                cursorByte: 2,
                records: [fixture.record(id: "record", value: 1)]
            ),
            fixture.checkpoint(
                generation: 1,
                cursorByte: 1,
                records: [fixture.record(id: "record", value: 2)]
            ),
            fixture.checkpoint(
                generation: 1,
                cursorByte: 1,
                records: [fixture.record(id: "different", value: 1)]
            ),
        ].map(ProfileHydrationCheckpointIdentityV1.init(checkpoint:))
        let baseIdentity = ProfileHydrationCheckpointIdentityV1(checkpoint: base)

        XCTAssertTrue(identities.allSatisfy { $0 != baseIdentity })
        XCTAssertEqual(Set(identities.map(\.checkpointDigest)).count, identities.count)
    }

    func testCheckpointIdentityBindsAccountScopeEpochProviderIndexesAndTombstones() throws {
        let fixture = try ProfileHydrationTestFixture()
        let record = fixture.record(id: "record", value: 1)
        let base = try fixture.checkpoint(
            generation: 1,
            cursorByte: 1,
            records: [record]
        )
        let alternateAccount = try fixture.checkpoint(
            accountID: CloudAccountID("alternate-cloud-account"),
            generation: 1,
            cursorByte: 1,
            records: [record]
        )
        let alternateScope = try fixture.checkpoint(
            scope: fixture.alternateScope,
            generation: 1,
            cursorByte: 1,
            records: [record]
        )
        let alternateEpoch = try fixture.checkpoint(
            replicaEpoch: fixture.fixedUUID(810),
            generation: 1,
            cursorByte: 1,
            records: [record]
        )
        let alternateProviderIndex = try fixture.checkpoint(
            generation: 1,
            cursorByte: 1,
            records: [record],
            locatorPrefix: "different-locator"
        )
        let tombstoneLocator = CloudProviderRecordLocator("deleted-locator")
        let withTombstone = try CloudReplicaCheckpointV1(
            accountID: fixture.cloudAccountID,
            configurationScopeFingerprint: fixture.scope,
            generation: 1,
            finalCursor: CloudChangeCursor(Data([1])),
            recordsByLogicalID: [:],
            providerLocatorByLogicalID: [:],
            logicalIDByProviderLocator: [:],
            tombstonesByProviderLocator: [
                tombstoneLocator: CloudReplicaTombstone(
                    locator: tombstoneLocator,
                    logicalRecordID: CloudRecordID("deleted-record"),
                    recordType: "ProfileRecord"
                ),
            ],
            replicaEpoch: fixture.replicaEpoch
        )
        let baseIdentity = ProfileHydrationCheckpointIdentityV1(checkpoint: base)
        let variants = [
            alternateAccount,
            alternateScope,
            alternateEpoch,
            alternateProviderIndex,
            withTombstone,
        ].map(ProfileHydrationCheckpointIdentityV1.init(checkpoint:))

        XCTAssertTrue(variants.allSatisfy { $0 != baseIdentity })
        XCTAssertEqual(Set(variants.map(\.checkpointDigest)).count, variants.count)
    }

    func testCheckpointRelationshipClassifiesOnlyStoreObservedBoundReceipts()
        async throws
    {
        let fixture = try ProfileHydrationTestFixture()
        let unrelatedCheckpoint = try fixture.checkpoint(
            generation: 1,
            cursorByte: 9
        )
        let genesis = fixture.journal
        let genesisTarget = try await checkpointObservation(
            fixture: fixture,
            checkpoints: [fixture.targetCheckpoint]
        )
        let genesisPredecessor = try await checkpointObservation(
            fixture: fixture
        )
        let unrelated = try await checkpointObservation(
            fixture: fixture,
            checkpoints: [unrelatedCheckpoint]
        )
        let wrongAccount = try await checkpointObservation(
            fixture: fixture,
            accountID: CloudAccountID("wrong-cloud-account")
        )
        let wrongScope = try await checkpointObservation(
            fixture: fixture,
            scope: fixture.alternateScope
        )
        let wrongEpoch = try await checkpointObservation(
            fixture: fixture,
            replicaEpoch: fixture.fixedUUID(899)
        )
        let genesisCases: [(
            String,
            CloudReplicaCheckpointObservationV1,
            ProfileHydrationCheckpointRelationshipV1
        )] = [
            ("exact target", genesisTarget, .target),
            ("observed absent genesis predecessor", genesisPredecessor, .predecessor),
            ("unrelated checkpoint", unrelated, .unexpected),
            ("wrong account", wrongAccount, .unexpected),
            ("wrong scope", wrongScope, .unexpected),
            ("wrong epoch", wrongEpoch, .unexpected),
        ]
        for (name, observation, expected) in genesisCases {
            XCTAssertEqual(
                genesis.checkpointRelationship(to: observation),
                expected,
                name
            )
        }

        let predecessorCheckpoint = try fixture.checkpoint(
            generation: 1,
            cursorByte: 1
        )
        let predecessorIdentity = ProfileHydrationCheckpointIdentityV1(
            checkpoint: predecessorCheckpoint
        )
        let targetCheckpoint = try fixture.checkpoint(
            generation: 2,
            cursorByte: 2
        )
        let nonGenesis = try fixture.makeJournal(
            predecessor: predecessorIdentity,
            targetCheckpoint: targetCheckpoint
        )
        let nonGenesisTarget = try await checkpointObservation(
            fixture: fixture,
            checkpoints: [predecessorCheckpoint, targetCheckpoint]
        )
        let nonGenesisPredecessor = try await checkpointObservation(
            fixture: fixture,
            checkpoints: [predecessorCheckpoint]
        )
        let nonGenesisAbsent = try await checkpointObservation(
            fixture: fixture
        )
        let nonGenesisCases: [(
            String,
            CloudReplicaCheckpointObservationV1,
            ProfileHydrationCheckpointRelationshipV1
        )] = [
            ("exact target", nonGenesisTarget, .target),
            ("exact predecessor", nonGenesisPredecessor, .predecessor),
            ("observed absent non-genesis checkpoint", nonGenesisAbsent, .unexpected),
            ("unrelated", unrelated, .unexpected),
        ]
        for (name, observation, expected) in nonGenesisCases {
            XCTAssertEqual(
                nonGenesis.checkpointRelationship(to: observation),
                expected,
                name
            )
        }
    }

    private func checkpointObservation(
        fixture: ProfileHydrationTestFixture,
        accountID: CloudAccountID? = nil,
        scope: CloudReplicaScopeFingerprint? = nil,
        replicaEpoch: UUID? = nil,
        checkpoints: [CloudReplicaCheckpointV1] = []
    ) async throws -> CloudReplicaCheckpointObservationV1 {
        let accountID = accountID ?? fixture.cloudAccountID
        let scope = scope ?? fixture.scope
        let replicaEpoch = replicaEpoch ?? fixture.replicaEpoch
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "PocketVector-CheckpointObservation-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root
        )
        try await store.activate(
            replicaEpoch: replicaEpoch,
            configurationScopeFingerprint: scope,
            for: accountID
        )
        for checkpoint in checkpoints {
            try await store._testOnlySaveRawCheckpoint(
                checkpoint,
                at: fixture.date
            )
        }
        return try await store.observeCurrentCheckpoint(
            for: accountID,
            configurationScopeFingerprint: scope,
            replicaEpoch: replicaEpoch,
            at: fixture.date
        )
    }

    func testEnvelopeDigestTamperingFailsClosed() throws {
        let fixture = try ProfileHydrationTestFixture()
        let mutated = try fixture.mutating(fixture.journal) { object in
            object["sourceProfileEnvelopeDigest"] = String(repeating: "0", count: 64)
        }

        XCTAssertThrowsError(try mutated.validate()) { error in
            XCTAssertEqual(
                error as? ProfileHydrationJournalValidationError,
                .sourceEnvelopeDigestMismatch
            )
        }
    }

    func testNoOpProfileBytesCannotCreateMaterialInstallJournal() throws {
        let fixture = try ProfileHydrationTestFixture()
        XCTAssertThrowsError(
            try ProfileHydrationJournalV1.make(
                transactionID: fixture.transactionID,
                createdAt: fixture.date,
                sourceSession: fixture.sourceSession,
                sourcePlayerRevision: 4,
                sourceEconomyRevision: 4,
                sourceProfileEnvelope: fixture.sourceEnvelope,
                candidateProfileEnvelope: fixture.sourceEnvelope,
                cloudAccountID: fixture.cloudAccountID,
                configurationScopeFingerprint: fixture.scope,
                replicaEpoch: fixture.replicaEpoch,
                predecessorCheckpointIdentity: nil,
                targetCheckpoint: fixture.targetCheckpoint
            )
        ) { error in
            XCTAssertEqual(
                error as? ProfileHydrationJournalValidationError,
                .noMaterialChange
            )
        }
    }

    func testCandidateEnvelopeMustBeCanonicalCurrentPersistedBytes() throws {
        let fixture = try ProfileHydrationTestFixture()
        var noncanonical = fixture.candidateEnvelope
        noncanonical.append(0x0a)

        XCTAssertThrowsError(
            try fixture.makeJournal(candidateEnvelope: noncanonical)
        ) { error in
            XCTAssertEqual(
                error as? ProfileHydrationJournalValidationError,
                .noncanonicalCandidateEnvelope
            )
        }
    }

    func testSourceSessionMustMatchExactSourceEnvelope() throws {
        let fixture = try ProfileHydrationTestFixture()
        let wrongSession = ProfileSessionToken(
            accountIdentity: fixture.sourceAccount,
            nonce: fixture.sourceSession.nonce,
            profileID: fixture.fixedUUID(999)
        )

        XCTAssertThrowsError(
            try fixture.makeJournal(sourceSession: wrongSession)
        ) { error in
            XCTAssertEqual(
                error as? ProfileHydrationJournalValidationError,
                .sourceProfileBindingMismatch
            )
        }
    }

    func testStructurallyConsistentCrossAccountSourceRequiresExplicitMigration()
        throws
    {
        let fixture = try ProfileHydrationTestFixture()
        let otherAccount = PlayerAccountIdentity("migration-source-player")
        let otherProfileID = fixture.fixedUUID(996)
        let cases: [(String, PlayerAccountIdentity, UUID)] = [
            ("account", otherAccount, fixture.sourceProfileID),
            ("profile", fixture.sourceAccount, otherProfileID),
            ("account and profile", otherAccount, otherProfileID),
        ]

        for (name, accountIdentity, profileID) in cases {
            let otherSession = ProfileSessionToken(
                accountIdentity: accountIdentity,
                nonce: fixture.fixedUUID(995),
                profileID: profileID
            )
            var otherSource = PlayerProfileFactory.makeDefault(
                profileID: profileID,
                accountIdentity: accountIdentity,
                deviceID: "migration-source-device",
                createdAt: fixture.date
            )
            otherSource.player.revision = 4
            otherSource.economyRevision = 4
            let otherSourceEnvelope = try PlayerProfileMigrator().encode(
                otherSource,
                savedAt: fixture.date
            )

            XCTAssertThrowsError(
                try ProfileHydrationJournalV1.make(
                    transactionID: fixture.transactionID,
                    createdAt: fixture.date,
                    sourceSession: otherSession,
                    sourcePlayerRevision: otherSource.player.revision,
                    sourceEconomyRevision: otherSource.economyRevision,
                    sourceProfileEnvelope: otherSourceEnvelope,
                    candidateProfileEnvelope: fixture.candidateEnvelope,
                    cloudAccountID: fixture.cloudAccountID,
                    configurationScopeFingerprint: fixture.scope,
                    replicaEpoch: fixture.replicaEpoch,
                    predecessorCheckpointIdentity: nil,
                    targetCheckpoint: fixture.targetCheckpoint
                ),
                name
            ) { error in
                XCTAssertEqual(
                    error as? ProfileHydrationJournalValidationError,
                    .sourceTargetBindingMismatch,
                    name
                )
            }
        }
    }

    func testCandidateMustUseAccountDerivedPlayerAndProfileIDs() throws {
        let fixture = try ProfileHydrationTestFixture()
        var candidate = PlayerProfileFactory.makeDefault(
            profileID: fixture.fixedUUID(998),
            accountIdentity: PlayerAccountIdentity("wrong-target"),
            deviceID: "device-b",
            createdAt: fixture.date
        )
        candidate.player.revision = 5
        candidate.economyRevision = 5
        let bytes = try PlayerProfileMigrator().encode(
            candidate,
            savedAt: fixture.date.addingTimeInterval(1)
        )

        XCTAssertThrowsError(try fixture.makeJournal(candidateEnvelope: bytes)) { error in
            XCTAssertEqual(
                error as? ProfileHydrationJournalValidationError,
                .candidateProfileBindingMismatch
            )
        }
    }

    func testMaterialInstallAdvancesBothRevisionsExactlyOnce() throws {
        let fixture = try ProfileHydrationTestFixture()
        var candidate = fixture.candidateDocument
        candidate.player.revision = 6
        let wrongPlayerRevision = try PlayerProfileMigrator().encode(
            candidate,
            savedAt: fixture.date.addingTimeInterval(1)
        )
        XCTAssertThrowsError(
            try fixture.makeJournal(candidateEnvelope: wrongPlayerRevision)
        ) { error in
            XCTAssertEqual(
                error as? ProfileHydrationJournalValidationError,
                .candidatePlayerRevisionMismatch
            )
        }

        candidate = fixture.candidateDocument
        candidate.economyRevision = 6
        let wrongEconomyRevision = try PlayerProfileMigrator().encode(
            candidate,
            savedAt: fixture.date.addingTimeInterval(1)
        )
        XCTAssertThrowsError(
            try fixture.makeJournal(candidateEnvelope: wrongEconomyRevision)
        ) { error in
            XCTAssertEqual(
                error as? ProfileHydrationJournalValidationError,
                .candidateEconomyRevisionMismatch
            )
        }
    }

    func testDecodedTargetCannotSubstituteNonderivedBinding() throws {
        let fixture = try ProfileHydrationTestFixture()
        let wrongProfileID = fixture.fixedUUID(997)
        var wrongCandidate = fixture.candidateDocument
        wrongCandidate.player.profileID = wrongProfileID
        let wrongCandidateData = try PlayerProfileMigrator().encode(
            wrongCandidate,
            savedAt: fixture.date.addingTimeInterval(1)
        )
        let mutated = try fixture.mutating(fixture.journal) { object in
            var target = try XCTUnwrap(object["target"] as? [String: Any])
            target["profileID"] = wrongProfileID.uuidString.uppercased()
            object["target"] = target
            object["candidateProfileEnvelope"] = wrongCandidateData.base64EncodedString()
            object["candidateProfileEnvelopeDigest"] = ProfileHydrationDigest
                .envelopeBytes(wrongCandidateData).rawValue
        }

        XCTAssertThrowsError(try mutated.validate()) { error in
            XCTAssertEqual(
                error as? ProfileHydrationJournalValidationError,
                .targetAccountBindingMismatch
            )
        }
    }

    func testTargetCheckpointIdentityTamperingFailsClosed() throws {
        let fixture = try ProfileHydrationTestFixture()
        let mutated = try fixture.mutating(fixture.journal) { object in
            var identity = try XCTUnwrap(
                object["targetCheckpointIdentity"] as? [String: Any]
            )
            identity["checkpointDigest"] = String(repeating: "f", count: 64)
            object["targetCheckpointIdentity"] = identity
        }

        XCTAssertThrowsError(try mutated.validate()) { error in
            XCTAssertEqual(
                error as? ProfileHydrationJournalValidationError,
                .targetCheckpointIdentityMismatch
            )
        }
    }

    func testPredecessorMustBindSameScopeEpochNextGenerationAndEarlierCursor() throws {
        let fixture = try ProfileHydrationTestFixture()
        let generationTwo = try fixture.checkpoint(generation: 2, cursorByte: 2)
        XCTAssertThrowsError(
            try fixture.makeJournal(
                predecessor: nil,
                targetCheckpoint: generationTwo
            )
        ) { error in
            XCTAssertEqual(
                error as? ProfileHydrationJournalValidationError,
                .predecessorGenerationMismatch
            )
        }

        let wrongScopePredecessor = try fixture.checkpoint(
            scope: fixture.alternateScope,
            generation: 1,
            cursorByte: 1
        )
        XCTAssertThrowsError(
            try fixture.makeJournal(
                predecessor: ProfileHydrationCheckpointIdentityV1(
                    checkpoint: wrongScopePredecessor
                ),
                targetCheckpoint: generationTwo
            )
        ) { error in
            XCTAssertEqual(
                error as? ProfileHydrationJournalValidationError,
                .predecessorBindingMismatch
            )
        }

        let sameCursorPredecessor = try fixture.checkpoint(
            generation: 1,
            cursorByte: 2
        )
        XCTAssertThrowsError(
            try fixture.makeJournal(
                predecessor: ProfileHydrationCheckpointIdentityV1(
                    checkpoint: sameCursorPredecessor
                ),
                targetCheckpoint: generationTwo
            )
        ) { error in
            XCTAssertEqual(
                error as? ProfileHydrationJournalValidationError,
                .predecessorCursorDidNotAdvance
            )
        }
    }

    func testEnvelopeCheckpointIdentifierAndCollectionLimitsFailBeforePersistence() throws {
        let fixture = try ProfileHydrationTestFixture()
        let sourceLimit = fixture.limits(
            maximumProfileEnvelopeBytes: fixture.sourceEnvelope.count - 1
        )
        XCTAssertThrowsError(try fixture.journal.validate(limits: sourceLimit)) { error in
            XCTAssertEqual(
                error as? ProfileHydrationJournalValidationError,
                .sourceEnvelopeLimitExceeded
            )
        }

        let longRecord = fixture.record(
            id: String(repeating: "r", count: 81),
            value: 1
        )
        let longIdentifierCheckpoint = try fixture.checkpoint(
            generation: 1,
            cursorByte: 1,
            records: [longRecord]
        )
        let longIdentifierJournal = try fixture.makeJournal(
            targetCheckpoint: longIdentifierCheckpoint
        )
        XCTAssertThrowsError(
            try longIdentifierJournal.validate(
                limits: fixture.limits(maximumIdentifierBytes: 80)
            )
        ) { error in
            XCTAssertEqual(
                error as? ProfileHydrationJournalValidationError,
                .identifierLimitExceeded
            )
        }

        XCTAssertThrowsError(
            try fixture.journal.validate(
                limits: fixture.limits(maximumProfileCollectionEntries: 1)
            )
        ) { error in
            XCTAssertEqual(
                error as? ProfileHydrationJournalValidationError,
                .profileCollectionLimitExceeded
            )
        }
    }
}

private struct ProfileHydrationCheckpointMapEncodingProbe: Encodable {
    struct Key: Encodable {
        let rawValue: String
    }

    struct Value: Encodable {
        let value: Int
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case recordsByLogicalID
        case providerLocatorByLogicalID
        case logicalIDByProviderLocator
        case tombstonesByProviderLocator
    }

    let pairs: [(String, Int)]

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        for codingKey in CodingKeys.allCases {
            var alternating = container.nestedUnkeyedContainer(
                forKey: codingKey
            )
            for pair in pairs {
                try alternating.encode(Key(rawValue: pair.0))
                try alternating.encode(Value(value: pair.1))
            }
        }
    }
}

struct ProfileHydrationTestFixture {
    let date = Date(timeIntervalSince1970: 1_750_000_000)
    let transactionID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    let sourceAccount: PlayerAccountIdentity
    let sourceProfileID: UUID
    let cloudAccountID = CloudAccountID("test-cloud-account")
    let scope = CloudReplicaScopeFingerprint(rawValue: String(repeating: "a", count: 64))
    let alternateScope = CloudReplicaScopeFingerprint(
        rawValue: String(repeating: "b", count: 64)
    )
    let replicaEpoch = UUID(uuidString: "30000000-0000-0000-0000-000000000003")!
    let sourceSession: ProfileSessionToken
    let targetBindings: CloudAccountDerivedBindings
    let sourceDocument: LocalPlayerDocumentV1
    let candidateDocument: LocalPlayerDocumentV1
    let sourceEnvelope: Data
    let candidateEnvelope: Data
    let targetCheckpoint: CloudReplicaCheckpointV1
    let journal: ProfileHydrationJournalV1

    init() throws {
        targetBindings = CloudAccountDerivedBindings.derive(from: cloudAccountID)
        sourceAccount = targetBindings.playerAccountIdentity
        sourceProfileID = targetBindings.durableAccountBinding.profileID
        sourceSession = ProfileSessionToken(
            accountIdentity: sourceAccount,
            nonce: UUID(uuidString: "40000000-0000-0000-0000-000000000004")!,
            profileID: sourceProfileID
        )
        var source = PlayerProfileFactory.makeDefault(
            profileID: sourceProfileID,
            accountIdentity: sourceAccount,
            deviceID: "device-a",
            createdAt: date
        )
        source.player.revision = 4
        source.economyRevision = 4
        sourceDocument = source

        var candidate = PlayerProfileFactory.makeDefault(
            profileID: targetBindings.durableAccountBinding.profileID,
            accountIdentity: targetBindings.playerAccountIdentity,
            deviceID: "device-b",
            createdAt: date
        )
        candidate.player.revision = 5
        candidate.economyRevision = 5
        candidateDocument = candidate

        let migrator = PlayerProfileMigrator()
        sourceEnvelope = try migrator.encode(source, savedAt: date)
        candidateEnvelope = try migrator.encode(
            candidate,
            savedAt: date.addingTimeInterval(1)
        )
        targetCheckpoint = try CloudReplicaCheckpointV1(
            accountID: cloudAccountID,
            configurationScopeFingerprint: scope,
            generation: 1,
            finalCursor: CloudChangeCursor(Data([1])),
            recordsByLogicalID: [:],
            providerLocatorByLogicalID: [:],
            logicalIDByProviderLocator: [:],
            tombstonesByProviderLocator: [:],
            replicaEpoch: replicaEpoch
        )
        journal = try ProfileHydrationJournalV1.make(
            transactionID: transactionID,
            createdAt: date,
            sourceSession: sourceSession,
            sourcePlayerRevision: source.player.revision,
            sourceEconomyRevision: source.economyRevision,
            sourceProfileEnvelope: sourceEnvelope,
            candidateProfileEnvelope: candidateEnvelope,
            cloudAccountID: cloudAccountID,
            configurationScopeFingerprint: scope,
            replicaEpoch: replicaEpoch,
            predecessorCheckpointIdentity: nil,
            targetCheckpoint: targetCheckpoint
        )
    }

    var expectedBinding: ProfileHydrationExpectedBinding {
        ProfileHydrationExpectedBinding(
            cloudAccountID: cloudAccountID,
            configurationScopeFingerprint: scope,
            replicaEpoch: replicaEpoch
        )
    }

    func makeJournal(
        sourceSession: ProfileSessionToken? = nil,
        candidateEnvelope: Data? = nil,
        predecessor: ProfileHydrationCheckpointIdentityV1? = nil,
        targetCheckpoint: CloudReplicaCheckpointV1? = nil
    ) throws -> ProfileHydrationJournalV1 {
        try ProfileHydrationJournalV1.make(
            transactionID: transactionID,
            createdAt: date,
            sourceSession: sourceSession ?? self.sourceSession,
            sourcePlayerRevision: sourceDocument.player.revision,
            sourceEconomyRevision: sourceDocument.economyRevision,
            sourceProfileEnvelope: sourceEnvelope,
            candidateProfileEnvelope: candidateEnvelope ?? self.candidateEnvelope,
            cloudAccountID: cloudAccountID,
            configurationScopeFingerprint: scope,
            replicaEpoch: replicaEpoch,
            predecessorCheckpointIdentity: predecessor,
            targetCheckpoint: targetCheckpoint ?? self.targetCheckpoint
        )
    }

    func checkpoint(
        accountID: CloudAccountID? = nil,
        scope: CloudReplicaScopeFingerprint? = nil,
        replicaEpoch: UUID? = nil,
        generation: UInt64,
        cursorByte: UInt8,
        records: [CloudRecord] = [],
        tombstones: [CloudReplicaTombstone] = [],
        locatorPrefix: String = "locator"
    ) throws -> CloudReplicaCheckpointV1 {
        let recordsByID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        let locatorPairs = records.map { record in
            (
                record.id,
                CloudProviderRecordLocator("\(locatorPrefix).\(record.id.rawValue)")
            )
        }
        let providerByLogical = Dictionary(uniqueKeysWithValues: locatorPairs)
        let logicalByProvider = Dictionary(
            uniqueKeysWithValues: locatorPairs.map { ($0.1, $0.0) }
        )
        return try CloudReplicaCheckpointV1(
            accountID: accountID ?? cloudAccountID,
            configurationScopeFingerprint: scope ?? self.scope,
            generation: generation,
            finalCursor: CloudChangeCursor(Data([cursorByte])),
            recordsByLogicalID: recordsByID,
            providerLocatorByLogicalID: providerByLogical,
            logicalIDByProviderLocator: logicalByProvider,
            tombstonesByProviderLocator: Dictionary(
                uniqueKeysWithValues: tombstones.map { ($0.locator, $0) }
            ),
            replicaEpoch: replicaEpoch ?? self.replicaEpoch
        )
    }

    func record(id: String, value: UInt8) -> CloudRecord {
        CloudRecord(
            id: CloudRecordID(id),
            recordType: "ProfileRecord",
            fields: ["payload": Data([value])],
            changeTag: CloudChangeTag("tag.\(value)")
        )
    }

    func tombstone(id: String) -> CloudReplicaTombstone {
        let locator = CloudProviderRecordLocator("locator.\(id)")
        return CloudReplicaTombstone(
            locator: locator,
            logicalRecordID: CloudRecordID(id),
            recordType: "ProfileRecord"
        )
    }

    func mutating(
        _ journal: ProfileHydrationJournalV1,
        mutate: (inout [String: Any]) throws -> Void
    ) throws -> ProfileHydrationJournalV1 {
        let data = try ProfileHydrationCanonicalCodec.encode(journal)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        try mutate(&object)
        let mutatedData = try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys]
        )
        return try ProfileHydrationCanonicalCodec.decode(
            ProfileHydrationJournalV1.self,
            from: mutatedData
        )
    }

    func limits(
        maximumEncodedJournalBytes: Int = ProfileHydrationLimits.production
            .maximumEncodedJournalBytes,
        maximumProfileEnvelopeBytes: Int = ProfileHydrationLimits.production
            .maximumProfileEnvelopeBytes,
        maximumEncodedCheckpointBytes: Int = ProfileHydrationLimits.production
            .maximumEncodedCheckpointBytes,
        maximumIdentifierBytes: Int = ProfileHydrationLimits.production
            .maximumIdentifierBytes,
        maximumProfileCollectionEntries: Int = ProfileHydrationLimits.production
            .maximumProfileCollectionEntries,
        maximumQuarantineFiles: Int = ProfileHydrationLimits.production
            .maximumQuarantineFiles,
        maximumQuarantineBytes: Int = ProfileHydrationLimits.production
            .maximumQuarantineBytes
    ) -> ProfileHydrationLimits {
        ProfileHydrationLimits(
            maximumEncodedJournalBytes: maximumEncodedJournalBytes,
            maximumProfileEnvelopeBytes: maximumProfileEnvelopeBytes,
            maximumEncodedCheckpointBytes: maximumEncodedCheckpointBytes,
            maximumIdentifierBytes: maximumIdentifierBytes,
            maximumProfileCollectionEntries: maximumProfileCollectionEntries,
            maximumQuarantineFiles: maximumQuarantineFiles,
            maximumQuarantineBytes: maximumQuarantineBytes
        )
    }

    func fixedUUID(_ value: Int) -> UUID {
        UUID(
            uuidString: String(
                format: "00000000-0000-0000-0000-%012d",
                value
            )
        )!
    }
}

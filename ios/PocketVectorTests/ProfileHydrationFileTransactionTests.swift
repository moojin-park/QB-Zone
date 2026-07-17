import Foundation
import XCTest

@testable import PocketVector

private enum HydrationProfileMatrixState: String, CaseIterable {
    case source
    case candidate
    case missing
    case unexpected
    case oversized
}

private final class CheckpointLeaseHarness: @unchecked Sendable {
    let rootDirectoryURL: URL
    let store: AtomicCloudReplicaCheckpointDiskStore
    let authority: CloudAccountGenerationAuthority
    let generation: ActiveCloudAccountGeneration
    let observedAt: Date

    init(
        rootDirectoryURL: URL,
        store: AtomicCloudReplicaCheckpointDiskStore,
        authority: CloudAccountGenerationAuthority,
        generation: ActiveCloudAccountGeneration,
        observedAt: Date
    ) {
        self.rootDirectoryURL = rootDirectoryURL
        self.store = store
        self.authority = authority
        self.generation = generation
        self.observedAt = observedAt
    }

    deinit {
        try? FileManager.default.removeItem(at: rootDirectoryURL)
    }
}

private enum ScopedHydrationLockEvent: Equatable {
    case checkpointEntered
    case profileEntered
    case profileExited
    case checkpointExited
}

private final class ScopedHydrationLockRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedEvents: [ScopedHydrationLockEvent] = []

    func record(_ event: ScopedHydrationLockEvent) {
        lock.lock()
        recordedEvents.append(event)
        lock.unlock()
    }

    func reset() {
        lock.lock()
        recordedEvents.removeAll(keepingCapacity: true)
        lock.unlock()
    }

    var events: [ScopedHydrationLockEvent] {
        lock.lock()
        defer { lock.unlock() }
        return recordedEvents
    }
}

final class ProfileHydrationFileTransactionTests: XCTestCase, @unchecked Sendable {
    func testLocationsExposeOneStableLockForJournalAndProfileMutationCoordination() throws {
        let root = try temporaryDirectory()
        defer { remove(root) }
        let first = ProfileHydrationFileTransactionStore(profileDirectoryURL: root)
        let second = ProfileHydrationFileTransactionStore(profileDirectoryURL: root)

        XCTAssertEqual(first.locations.lockURL, second.locations.lockURL)
        XCTAssertEqual(
            first.locations.lockURL.lastPathComponent,
            "player-profile-transaction.lock"
        )
        XCTAssertEqual(
            first.locations.profilePrimaryURL,
            ProfileStorageLocations(directoryURL: root).primaryURL
        )
    }

    func testBeginHydrationNormalizesValidatedStrictlyOlderBackupBeforeIntent() throws {
        let fixture = try ProfileHydrationTestFixture()
        let root = try temporaryDirectory()
        defer { remove(root) }
        let store = makeStore(root: root)
        var older = fixture.sourceDocument
        older.player.revision -= 1
        older.economyRevision -= 1
        let olderBytes = try PlayerProfileMigrator().encode(
            older,
            savedAt: fixture.date.addingTimeInterval(-1)
        )
        try writeProfileCopies(
            primary: fixture.sourceEnvelope,
            backup: olderBytes,
            locations: store.locations
        )

        let result = try store.beginHydration(fixture.journal)

        XCTAssertFalse(result.wasAlreadyPresent)
        XCTAssertEqual(
            try Data(contentsOf: store.locations.profilePrimaryURL),
            fixture.sourceEnvelope
        )
        XCTAssertEqual(
            try Data(contentsOf: store.locations.profileBackupURL),
            fixture.sourceEnvelope
        )
        assertJournalCopiesEqual(store.locations)
    }

    func testBeginHydrationRejectsSourceCASMismatchWithoutPublishingIntent() throws {
        let fixture = try ProfileHydrationTestFixture()
        let root = try temporaryDirectory()
        defer { remove(root) }
        let store = makeStore(root: root)
        var stale = fixture.sourceDocument
        stale.player.revision -= 1
        stale.economyRevision -= 1
        let staleBytes = try PlayerProfileMigrator().encode(
            stale,
            savedAt: fixture.date.addingTimeInterval(-1)
        )
        try writeProfile(staleBytes, locations: store.locations)

        XCTAssertThrowsError(
            try store.beginHydration(fixture.journal)
        ) { error in
            XCTAssertEqual(
                error as? ProfileHydrationTransactionStoreError,
                .sourceProfileCASMismatch(
                    .unexpected(.envelopeBytes(staleBytes))
                )
            )
        }
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: store.locations.journalPrimaryURL.path
            )
        )
        XCTAssertEqual(
            try Data(contentsOf: store.locations.profilePrimaryURL),
            staleBytes
        )
    }

    func testBeginHydrationRejectsSameRevisionDivergentBackupWithoutOverwritingIt() throws {
        let fixture = try ProfileHydrationTestFixture()
        let root = try temporaryDirectory()
        defer { remove(root) }
        let store = makeStore(root: root)
        var divergent = fixture.sourceDocument
        divergent.player.settings.value.isMuted.toggle()
        let divergentBytes = try PlayerProfileMigrator().encode(
            divergent,
            savedAt: fixture.date.addingTimeInterval(-1)
        )
        try writeProfileCopies(
            primary: fixture.sourceEnvelope,
            backup: divergentBytes,
            locations: store.locations
        )

        XCTAssertThrowsError(
            try store.beginHydration(fixture.journal)
        ) { error in
            XCTAssertEqual(
                error as? ProfileHydrationTransactionStoreError,
                .backupNormalizationRejected(
                    .unexpected(.envelopeBytes(divergentBytes))
                )
            )
        }
        XCTAssertEqual(
            try Data(contentsOf: store.locations.profileBackupURL),
            divergentBytes
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: store.locations.journalPrimaryURL.path
            )
        )
    }

    func testBackupNormalizationUsesComponentwiseRevisionAsymmetryMatrix() throws {
        let fixture = try ProfileHydrationTestFixture()
        let cases: [(
            name: String,
            playerDelta: Int,
            economyDelta: Int,
            accepted: Bool
        )] = [
            ("player lower economy equal", -1, 0, true),
            ("player equal economy lower", 0, -1, true),
            ("player higher economy equal", 1, 0, false),
            ("player equal economy higher", 0, 1, false),
        ]

        for testCase in cases {
            let root = try temporaryDirectory()
            defer { remove(root) }
            let store = makeStore(root: root)
            var backup = fixture.sourceDocument
            backup.player.revision = UInt64(
                Int(backup.player.revision) + testCase.playerDelta
            )
            backup.economyRevision = UInt64(
                Int(backup.economyRevision) + testCase.economyDelta
            )
            let backupBytes = try PlayerProfileMigrator().encode(
                backup,
                savedAt: fixture.date.addingTimeInterval(-1)
            )
            try writeProfileCopies(
                primary: fixture.sourceEnvelope,
                backup: backupBytes,
                locations: store.locations
            )

            if testCase.accepted {
                let result = try store.beginHydration(fixture.journal)
                XCTAssertFalse(result.wasAlreadyPresent, testCase.name)
                XCTAssertEqual(
                    try Data(contentsOf: store.locations.profilePrimaryURL),
                    fixture.sourceEnvelope,
                    testCase.name
                )
                XCTAssertEqual(
                    try Data(contentsOf: store.locations.profileBackupURL),
                    fixture.sourceEnvelope,
                    testCase.name
                )
                assertJournalCopiesEqual(store.locations)
            } else {
                XCTAssertThrowsError(
                    try store.beginHydration(fixture.journal),
                    testCase.name
                ) { error in
                    XCTAssertEqual(
                        error as? ProfileHydrationTransactionStoreError,
                        .backupNormalizationRejected(
                            .unexpected(.envelopeBytes(backupBytes))
                        ),
                        testCase.name
                    )
                }
                XCTAssertEqual(
                    try Data(contentsOf: store.locations.profileBackupURL),
                    backupBytes,
                    testCase.name
                )
                XCTAssertFalse(
                    FileManager.default.fileExists(
                        atPath: store.locations.journalPrimaryURL.path
                    ),
                    testCase.name
                )
            }
        }
    }

    func testInterruptedBackupNormalizationPublishesNoIntentAndRetrySucceeds() throws {
        let fixture = try ProfileHydrationTestFixture()
        let root = try temporaryDirectory()
        defer { remove(root) }
        var older = fixture.sourceDocument
        older.player.revision -= 1
        older.economyRevision -= 1
        let olderBytes = try PlayerProfileMigrator().encode(
            older,
            savedAt: fixture.date.addingTimeInterval(-1)
        )
        let fault = FaultInjectingProfileHydrationFileSystem()
        let store = makeStore(root: root, fileSystem: fault)
        try writeProfileCopies(
            primary: fixture.sourceEnvelope,
            backup: olderBytes,
            locations: store.locations
        )
        fault.failNext(.beforeWrite("player-profile.backup.json"))

        XCTAssertThrowsError(try store.beginHydration(fixture.journal))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: store.locations.journalPrimaryURL.path
            )
        )
        XCTAssertEqual(
            try Data(contentsOf: store.locations.profileBackupURL),
            olderBytes
        )

        let recovered = try makeStore(root: root).beginHydration(
            fixture.journal
        )
        XCTAssertFalse(recovered.wasAlreadyPresent)
        XCTAssertEqual(
            try Data(contentsOf: store.locations.profileBackupURL),
            fixture.sourceEnvelope
        )
    }

    func testNonemptyCheckpointJournalSurvivesRedundantRecoveryReencode() throws {
        let fixture = try ProfileHydrationTestFixture()
        let checkpoint = try fixture.checkpoint(
            generation: 1,
            cursorByte: 1,
            records: [
                fixture.record(id: "b", value: 2),
                fixture.record(id: "a", value: 1),
            ],
            tombstones: [
                fixture.tombstone(id: "deleted-b"),
                fixture.tombstone(id: "deleted-a"),
            ]
        )
        let journal = try fixture.makeJournal(targetCheckpoint: checkpoint)
        let root = try temporaryDirectory()
        defer { remove(root) }
        let store = makeStore(root: root)
        try seedSourceProfile(fixture, locations: store.locations)
        _ = try store.beginHydration(journal)

        let inspection = try XCTUnwrap(
            makeStore(root: root).inspectRecovery(
                expected: fixture.expectedBinding
            )
        )
        XCTAssertEqual(inspection.journal, journal)
        XCTAssertEqual(inspection.repairedJournalCopy, .none)
        assertJournalCopiesEqual(store.locations)
    }

    func testCrashAfterFirstJournalCopyRepairsFromExactPrimary() throws {
        let fixture = try ProfileHydrationTestFixture()
        let root = try temporaryDirectory()
        defer { remove(root) }
        let fault = FaultInjectingProfileHydrationFileSystem()
        let store = makeStore(root: root, fileSystem: fault)
        try seedSourceProfile(fixture, locations: store.locations)
        fault.failNext(.beforeWrite("profile-hydration-journal.backup.json"))

        XCTAssertThrowsError(try store.beginHydration(fixture.journal)) { error in
            XCTAssertEqual(error as? ProfileHydrationTransactionStoreError, .ioFailure)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.locations.journalPrimaryURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.locations.journalBackupURL.path))

        let recovered = try makeStore(root: root).beginHydration(fixture.journal)
        XCTAssertTrue(recovered.wasAlreadyPresent)
        XCTAssertEqual(recovered.repairedJournalCopy, .backup)
        assertJournalCopiesEqual(store.locations)
    }

    func testCrashAfterBothJournalCopiesIsIdempotentlyRecognized() throws {
        let fixture = try ProfileHydrationTestFixture()
        let root = try temporaryDirectory()
        defer { remove(root) }
        let fault = FaultInjectingProfileHydrationFileSystem()
        let store = makeStore(root: root, fileSystem: fault)
        try seedSourceProfile(fixture, locations: store.locations)
        fault.failNext(.afterWrite("profile-hydration-journal.backup.json"))

        XCTAssertThrowsError(try store.beginHydration(fixture.journal))
        assertJournalCopiesEqual(store.locations)
        let recovered = try makeStore(root: root).beginHydration(fixture.journal)
        XCTAssertTrue(recovered.wasAlreadyPresent)
        XCTAssertEqual(recovered.repairedJournalCopy, .none)
    }

    func testExistingIdenticalJournalRetryRejectsUnexpectedValidProfileWithoutOverwrite()
        throws
    {
        let fixture = try ProfileHydrationTestFixture()
        let root = try temporaryDirectory()
        defer { remove(root) }
        let store = makeStore(root: root)
        try seedSourceProfile(fixture, locations: store.locations)
        _ = try store.beginHydration(fixture.journal)
        let journalPrimary = try Data(
            contentsOf: store.locations.journalPrimaryURL
        )
        let journalBackup = Data("retained-corrupt-backup".utf8)
        try FoundationProfileHydrationFileSystem().writeAtomicallyDurably(
            journalBackup,
            to: store.locations.journalBackupURL
        )
        var unexpected = fixture.sourceDocument
        unexpected.player.settings.value.isMuted.toggle()
        let unexpectedBytes = try PlayerProfileMigrator().encode(
            unexpected,
            savedAt: fixture.date.addingTimeInterval(50)
        )
        let decodedUnexpected = try PlayerProfileMigrator().decode(
            unexpectedBytes
        )
        XCTAssertNoThrow(
            try PlayerProfileValidator.validate(decodedUnexpected)
        )
        try writeProfile(unexpectedBytes, locations: store.locations)

        XCTAssertThrowsError(
            try store.beginHydration(fixture.journal)
        ) { error in
            XCTAssertEqual(
                error as? ProfileHydrationTransactionStoreError,
                .unexpectedProfileBytes
            )
        }
        XCTAssertEqual(
            try Data(contentsOf: store.locations.profilePrimaryURL),
            unexpectedBytes
        )
        XCTAssertEqual(
            try Data(contentsOf: store.locations.profileBackupURL),
            unexpectedBytes
        )
        XCTAssertEqual(
            try Data(contentsOf: store.locations.journalPrimaryURL),
            journalPrimary
        )
        XCTAssertEqual(
            try Data(contentsOf: store.locations.journalBackupURL),
            journalBackup
        )
        XCTAssertTrue(try store.quarantinedEvidenceURLs().isEmpty)
    }

    func testPreparedJournalIsImmutableAndDifferentTransactionCannotReplaceIt() throws {
        let fixture = try ProfileHydrationTestFixture()
        let root = try temporaryDirectory()
        defer { remove(root) }
        let store = makeStore(root: root)
        try seedSourceProfile(fixture, locations: store.locations)
        _ = try store.beginHydration(fixture.journal)
        let originalPrimary = try Data(contentsOf: store.locations.journalPrimaryURL)
        let corruptBackup = Data("different-intent-corrupt-peer".utf8)
        try FoundationProfileHydrationFileSystem().writeAtomicallyDurably(
            corruptBackup,
            to: store.locations.journalBackupURL
        )
        let alternate = try fixture.mutating(fixture.journal) { object in
            object["transactionID"] = fixture.fixedUUID(803).uuidString.uppercased()
        }

        XCTAssertThrowsError(try store.beginHydration(alternate)) { error in
            XCTAssertEqual(
                error as? ProfileHydrationTransactionStoreError,
                .journalAlreadyExists
            )
        }
        XCTAssertEqual(
            try Data(contentsOf: store.locations.journalPrimaryURL),
            originalPrimary
        )
        XCTAssertEqual(
            try Data(contentsOf: store.locations.journalBackupURL),
            corruptBackup
        )
        XCTAssertTrue(try store.quarantinedEvidenceURLs().isEmpty)
    }

    func testRecoveryInspectionLeavesMissingJournalCopyUntouched() throws {
        let fixture = try ProfileHydrationTestFixture()
        let root = try temporaryDirectory()
        defer { remove(root) }
        let store = makeStore(root: root)
        try seedSourceProfile(fixture, locations: store.locations)
        _ = try store.beginHydration(fixture.journal)
        try FoundationProfileHydrationFileSystem().removeItemDurably(
            at: store.locations.journalPrimaryURL
        )

        let inspection = try XCTUnwrap(
            store.inspectRecovery(expected: fixture.expectedBinding)
        )
        XCTAssertEqual(inspection.repairedJournalCopy, .none)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: store.locations.journalPrimaryURL.path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: store.locations.journalBackupURL.path
            )
        )
    }

    func testRecoveryInspectionLeavesCorruptJournalCopyUntouched() throws {
        let fixture = try ProfileHydrationTestFixture()
        let root = try temporaryDirectory()
        defer { remove(root) }
        let store = makeStore(root: root)
        try seedSourceProfile(fixture, locations: store.locations)
        _ = try store.beginHydration(fixture.journal)
        try FoundationProfileHydrationFileSystem().writeAtomicallyDurably(
            Data("corrupt".utf8),
            to: store.locations.journalBackupURL
        )

        let primaryBefore = try Data(
            contentsOf: store.locations.journalPrimaryURL
        )
        let inspection = try XCTUnwrap(
            store.inspectRecovery(expected: fixture.expectedBinding)
        )
        XCTAssertEqual(inspection.repairedJournalCopy, .none)
        XCTAssertTrue(try store.quarantinedEvidenceURLs().isEmpty)
        XCTAssertEqual(
            try Data(contentsOf: store.locations.journalPrimaryURL),
            primaryBefore
        )
        XCTAssertEqual(
            try Data(contentsOf: store.locations.journalBackupURL),
            Data("corrupt".utf8)
        )
    }

    func testNoncanonicalJournalCopyIsEvidenceAndCannotBecomeAuthority() throws {
        let fixture = try ProfileHydrationTestFixture()
        let root = try temporaryDirectory()
        defer { remove(root) }
        let store = makeStore(root: root)
        try seedSourceProfile(fixture, locations: store.locations)
        _ = try store.beginHydration(fixture.journal)
        let canonical = try Data(contentsOf: store.locations.journalPrimaryURL)
        let object = try JSONSerialization.jsonObject(with: canonical)
        let noncanonical = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys]
        )
        try FoundationProfileHydrationFileSystem().writeAtomicallyDurably(
            noncanonical,
            to: store.locations.journalBackupURL
        )

        let inspection = try XCTUnwrap(
            store.inspectRecovery(expected: fixture.expectedBinding)
        )
        XCTAssertEqual(inspection.repairedJournalCopy, .none)
        XCTAssertTrue(try store.quarantinedEvidenceURLs().isEmpty)
        XCTAssertEqual(
            try Data(contentsOf: store.locations.journalBackupURL),
            noncanonical
        )
    }

    func testTwoValidUnequalJournalsFailWithoutQuarantineOrRepair() throws {
        let fixture = try ProfileHydrationTestFixture()
        let rootA = try temporaryDirectory()
        let rootB = try temporaryDirectory()
        defer {
            remove(rootA)
            remove(rootB)
        }
        let storeA = makeStore(root: rootA)
        let storeB = makeStore(root: rootB)
        try seedSourceProfile(fixture, locations: storeA.locations)
        try seedSourceProfile(fixture, locations: storeB.locations)
        _ = try storeA.beginHydration(fixture.journal)
        let alternate = try fixture.mutating(fixture.journal) { object in
            object["transactionID"] = fixture.fixedUUID(800).uuidString.uppercased()
        }
        _ = try storeB.beginHydration(alternate)
        let alternateData = try Data(contentsOf: storeB.locations.journalBackupURL)
        try FoundationProfileHydrationFileSystem().writeAtomicallyDurably(
            alternateData,
            to: storeA.locations.journalBackupURL
        )
        let primaryBefore = try Data(contentsOf: storeA.locations.journalPrimaryURL)
        let backupBefore = try Data(contentsOf: storeA.locations.journalBackupURL)

        XCTAssertThrowsError(
            try storeA.inspectRecovery(expected: fixture.expectedBinding)
        ) { error in
            XCTAssertEqual(
                error as? ProfileHydrationTransactionStoreError,
                .journalCopiesDisagree
            )
        }
        XCTAssertEqual(try Data(contentsOf: storeA.locations.journalPrimaryURL), primaryBefore)
        XCTAssertEqual(try Data(contentsOf: storeA.locations.journalBackupURL), backupBefore)
        XCTAssertTrue(try storeA.quarantinedEvidenceURLs().isEmpty)
    }

    func testInterruptedCorruptCopyRepairRemainsRecoverable() throws {
        let fixture = try ProfileHydrationTestFixture()
        let root = try temporaryDirectory()
        defer { remove(root) }
        let baseStore = makeStore(root: root)
        try seedSourceProfile(fixture, locations: baseStore.locations)
        _ = try baseStore.beginHydration(fixture.journal)
        try FoundationProfileHydrationFileSystem().writeAtomicallyDurably(
            Data("corrupt".utf8),
            to: baseStore.locations.journalBackupURL
        )
        let fault = FaultInjectingProfileHydrationFileSystem()
        fault.failNext(.beforeWrite("profile-hydration-journal.backup.json"))

        XCTAssertThrowsError(
            try makeStore(root: root, fileSystem: fault)
                .beginHydration(fixture.journal)
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: baseStore.locations.journalBackupURL.path))
        XCTAssertEqual(try baseStore.quarantinedEvidenceURLs().count, 1)

        let recovered = try baseStore.beginHydration(fixture.journal)
        XCTAssertTrue(recovered.wasAlreadyPresent)
        XCTAssertEqual(recovered.repairedJournalCopy, .backup)
        assertJournalCopiesEqual(baseStore.locations)
    }

    func testCrashAfterCandidateBackupLeavesClassifiedPartialInstall() async throws {
        let fixture = try ProfileHydrationTestFixture()
        let targetObservation = try await checkpointLeaseHarness(
            fixture: fixture,
            checkpoints: [fixture.targetCheckpoint]
        )
        let root = try temporaryDirectory()
        defer { remove(root) }
        let fault = FaultInjectingProfileHydrationFileSystem()
        let store = makeStore(root: root, fileSystem: fault)
        try seedSourceProfile(fixture, locations: store.locations)
        _ = try store.beginHydration(fixture.journal)
        fault.failNext(.beforeWrite("player-profile.json"))

        await assertThrowsErrorAsync {
            try await installCandidate(
                store: store,
                transactionID: fixture.transactionID,
                expected: fixture.expectedBinding,
                checkpointHarness: targetObservation
            )
        }
        let inspection = try XCTUnwrap(
            makeStore(root: root).inspectRecovery(expected: fixture.expectedBinding)
        )
        XCTAssertEqual(inspection.primaryProfileState, .source)
        XCTAssertEqual(inspection.backupProfileState, .candidate)
        XCTAssertEqual(inspection.installationState, .partial)

        let recovered = try await installCandidate(
            store: makeStore(root: root),
            transactionID: fixture.transactionID,
            expected: fixture.expectedBinding,
            checkpointHarness: targetObservation
        )
        XCTAssertFalse(recovered.wasAlreadyInstalled)
        XCTAssertEqual(recovered.inspection.installationState, .candidate)
    }

    func testCrashAfterCandidatePrimaryIsRecognizedAsAlreadyInstalled() async throws {
        let fixture = try ProfileHydrationTestFixture()
        let targetObservation = try await checkpointLeaseHarness(
            fixture: fixture,
            checkpoints: [fixture.targetCheckpoint]
        )
        let root = try temporaryDirectory()
        defer { remove(root) }
        let fault = FaultInjectingProfileHydrationFileSystem()
        let store = makeStore(root: root, fileSystem: fault)
        try seedSourceProfile(fixture, locations: store.locations)
        _ = try store.beginHydration(fixture.journal)
        fault.failNext(.afterWrite("player-profile.json"))

        await assertThrowsErrorAsync {
            try await installCandidate(
                store: store,
                transactionID: fixture.transactionID,
                expected: fixture.expectedBinding,
                checkpointHarness: targetObservation
            )
        }
        let recovered = try await installCandidate(
            store: makeStore(root: root),
            transactionID: fixture.transactionID,
            expected: fixture.expectedBinding,
            checkpointHarness: targetObservation
        )
        XCTAssertTrue(recovered.wasAlreadyInstalled)
        XCTAssertEqual(recovered.inspection.installationState, .candidate)
    }

    func testCandidateInstallationIsDeterministicallyIdempotent() async throws {
        let fixture = try ProfileHydrationTestFixture()
        let targetObservation = try await checkpointLeaseHarness(
            fixture: fixture,
            checkpoints: [fixture.targetCheckpoint]
        )
        let root = try temporaryDirectory()
        defer { remove(root) }
        let store = makeStore(root: root)
        try seedSourceProfile(fixture, locations: store.locations)
        _ = try store.beginHydration(fixture.journal)

        let first = try await installCandidate(
            store: store,
            transactionID: fixture.transactionID,
            expected: fixture.expectedBinding,
            checkpointHarness: targetObservation
        )
        let second = try await installCandidate(
            store: store,
            transactionID: fixture.transactionID,
            expected: fixture.expectedBinding,
            checkpointHarness: targetObservation
        )

        XCTAssertFalse(first.wasAlreadyInstalled)
        XCTAssertTrue(second.wasAlreadyInstalled)
        XCTAssertEqual(
            try Data(contentsOf: store.locations.profilePrimaryURL),
            fixture.candidateEnvelope
        )
        XCTAssertEqual(
            try Data(contentsOf: store.locations.profileBackupURL),
            fixture.candidateEnvelope
        )
    }

    func testInstallCandidateFullFiveByFiveProfileStateMatrix() async throws {
        let fixture = try ProfileHydrationTestFixture()
        let targetObservation = try await checkpointLeaseHarness(
            fixture: fixture,
            checkpoints: [fixture.targetCheckpoint]
        )
        let unexpectedBytes = Data("install-matrix-unexpected".utf8)
        let limits = compactMatrixLimits(fixture: fixture)
        let oversizedBytes = Data(
            repeating: 0x69,
            count: limits.maximumProfileEnvelopeBytes + 1
        )
        let fileSystem = FoundationProfileHydrationFileSystem()

        for primaryState in HydrationProfileMatrixState.allCases {
            for backupState in HydrationProfileMatrixState.allCases {
                let name = "\(primaryState.rawValue)/\(backupState.rawValue)"
                let root = try temporaryDirectory()
                let store = makeStore(root: root, limits: limits)
                try seedSourceProfile(fixture, locations: store.locations)
                _ = try store.beginHydration(fixture.journal)
                try applyMatrixState(
                    primaryState,
                    to: store.locations.profilePrimaryURL,
                    fixture: fixture,
                    unexpectedBytes: unexpectedBytes,
                    oversizedBytes: oversizedBytes
                )
                try applyMatrixState(
                    backupState,
                    to: store.locations.profileBackupURL,
                    fixture: fixture,
                    unexpectedBytes: unexpectedBytes,
                    oversizedBytes: oversizedBytes
                )
                let quarantineURL = store.locations.quarantineSlotURL(0)
                try fileSystem.createDirectory(
                    at: store.locations.quarantineDirectoryURL
                )
                try fileSystem.writeAtomicallyDurably(
                    Data("install-matrix-evidence".utf8),
                    to: quarantineURL
                )
                let evidenceURLs = [
                    store.locations.profilePrimaryURL,
                    store.locations.profileBackupURL,
                    store.locations.journalPrimaryURL,
                    store.locations.journalBackupURL,
                    quarantineURL,
                ]
                let evidenceBefore = try evidenceURLs.map {
                    try optionalData(at: $0)
                }
                let hasUnexpectedState = [primaryState, backupState]
                    .contains(.unexpected)
                    || [primaryState, backupState].contains(.oversized)
                let bothMissing = primaryState == .missing
                    && backupState == .missing

                if !hasUnexpectedState, !bothMissing {
                    let result = try await installCandidate(
                        store: store,
                        transactionID: fixture.transactionID,
                        expected: fixture.expectedBinding,
                        checkpointHarness: targetObservation
                    )
                    XCTAssertEqual(
                        result.inspection.installationState,
                        .candidate,
                        name
                    )
                    XCTAssertEqual(
                        result.wasAlreadyInstalled,
                        primaryState == .candidate && backupState == .candidate,
                        name
                    )
                    XCTAssertEqual(
                        try Data(contentsOf: store.locations.profilePrimaryURL),
                        fixture.candidateEnvelope,
                        name
                    )
                    XCTAssertEqual(
                        try Data(contentsOf: store.locations.profileBackupURL),
                        fixture.candidateEnvelope,
                        name
                    )
                    XCTAssertEqual(
                        try optionalData(at: quarantineURL),
                        evidenceBefore[4],
                        name
                    )
                    assertJournalCopiesEqual(store.locations)
                } else {
                    await assertThrowsErrorAsync({
                        try await installCandidate(
                            store: store,
                            transactionID: fixture.transactionID,
                            expected: fixture.expectedBinding,
                            checkpointHarness: targetObservation
                        )
                    },
                        name
                    ) { error in
                        XCTAssertEqual(
                            error as? ProfileHydrationTransactionStoreError,
                            bothMissing
                                ? .profileCopiesMissing
                                : .unexpectedProfileBytes,
                            name
                        )
                    }
                    XCTAssertEqual(
                        try evidenceURLs.map { try optionalData(at: $0) },
                        evidenceBefore,
                        name
                    )
                }
                remove(root)
            }
        }
    }

    func testCandidateInstallRequiresExactTargetBeforeWritesAndIdempotentReturn()
        async throws
    {
        let fixture = try ProfileHydrationTestFixture()
        let targetObservation = try await checkpointLeaseHarness(
            fixture: fixture,
            checkpoints: [fixture.targetCheckpoint]
        )
        let wrongCheckpoint = try fixture.checkpoint(
            generation: 1,
            cursorByte: 9
        )
        let wrongObservation = try await checkpointLeaseHarness(
            fixture: fixture,
            checkpoints: [wrongCheckpoint]
        )
        let root = try temporaryDirectory()
        defer { remove(root) }
        let store = makeStore(root: root)
        try seedSourceProfile(fixture, locations: store.locations)
        _ = try store.beginHydration(fixture.journal)
        let sourceEvidence = try [
            Data(contentsOf: store.locations.profilePrimaryURL),
            Data(contentsOf: store.locations.profileBackupURL),
        ]

        await assertThrowsErrorAsync {
            try await installCandidate(
                store: store,
                transactionID: fixture.transactionID,
                expected: fixture.expectedBinding,
                checkpointHarness: wrongObservation
            )
        } errorHandler: { error in
            XCTAssertEqual(
                error as? ProfileHydrationTransactionStoreError,
                .checkpointConfirmationMismatch
            )
        }
        XCTAssertEqual(
            try [
                Data(contentsOf: store.locations.profilePrimaryURL),
                Data(contentsOf: store.locations.profileBackupURL),
            ],
            sourceEvidence
        )

        _ = try await installCandidate(
            store: store,
            transactionID: fixture.transactionID,
            expected: fixture.expectedBinding,
            checkpointHarness: targetObservation
        )
        let candidateEvidence = try [
            Data(contentsOf: store.locations.profilePrimaryURL),
            Data(contentsOf: store.locations.profileBackupURL),
        ]
        await assertThrowsErrorAsync {
            try await installCandidate(
                store: store,
                transactionID: fixture.transactionID,
                expected: fixture.expectedBinding,
                checkpointHarness: wrongObservation
            )
        } errorHandler: { error in
            XCTAssertEqual(
                error as? ProfileHydrationTransactionStoreError,
                .checkpointConfirmationMismatch
            )
        }
        XCTAssertEqual(
            try [
                Data(contentsOf: store.locations.profilePrimaryURL),
                Data(contentsOf: store.locations.profileBackupURL),
            ],
            candidateEvidence
        )
        assertJournalCopiesEqual(store.locations)
    }

    func testLaterAcceptedCheckpointRejectsStaleJournalBeforeProfileMutation()
        async throws
    {
        let fixture = try ProfileHydrationTestFixture()
        let successor = try fixture.checkpoint(
            generation: 2,
            cursorByte: 2
        )
        let currentCheckpoint = try await checkpointLeaseHarness(
            fixture: fixture,
            checkpoints: [fixture.targetCheckpoint, successor]
        )
        let root = try temporaryDirectory()
        defer { remove(root) }
        let store = makeStore(root: root)
        try seedSourceProfile(fixture, locations: store.locations)
        _ = try store.beginHydration(fixture.journal)
        let evidenceBefore = try [
            Data(contentsOf: store.locations.profilePrimaryURL),
            Data(contentsOf: store.locations.profileBackupURL),
            Data(contentsOf: store.locations.journalPrimaryURL),
            Data(contentsOf: store.locations.journalBackupURL),
        ]

        await assertThrowsErrorAsync {
            try await installCandidate(
                store: store,
                transactionID: fixture.transactionID,
                expected: fixture.expectedBinding,
                checkpointHarness: currentCheckpoint
            )
        } errorHandler: { error in
            XCTAssertEqual(
                error as? ProfileHydrationTransactionStoreError,
                .checkpointConfirmationMismatch
            )
        }

        XCTAssertEqual(
            try [
                Data(contentsOf: store.locations.profilePrimaryURL),
                Data(contentsOf: store.locations.profileBackupURL),
                Data(contentsOf: store.locations.journalPrimaryURL),
                Data(contentsOf: store.locations.journalBackupURL),
            ],
            evidenceBefore
        )
    }

    func testInstallRejectionsNeverRepairOrQuarantineJournalEvidence()
        async throws
    {
        let fixture = try ProfileHydrationTestFixture()
        let targetObservation = try await checkpointLeaseHarness(
            fixture: fixture,
            checkpoints: [fixture.targetCheckpoint]
        )
        let wrongCheckpoint = try fixture.checkpoint(
            generation: 1,
            cursorByte: 9
        )
        let wrongObservation = try await checkpointLeaseHarness(
            fixture: fixture,
            checkpoints: [wrongCheckpoint]
        )
        let corruptJournalBytes = Data("retained-corrupt-journal-copy".utf8)
        let unexpectedProfileBytes = Data("retained-unexpected-profile".utf8)
        let fileSystem = FoundationProfileHydrationFileSystem()

        for rejection in ["transaction", "receipt", "profile"] {
            let root = try temporaryDirectory()
            let store = makeStore(root: root)
            try seedSourceProfile(fixture, locations: store.locations)
            _ = try store.beginHydration(fixture.journal)
            try fileSystem.writeAtomicallyDurably(
                corruptJournalBytes,
                to: store.locations.journalBackupURL
            )
            if rejection == "profile" {
                try writeProfile(
                    unexpectedProfileBytes,
                    locations: store.locations
                )
            }
            let evidenceURLs = [
                store.locations.profilePrimaryURL,
                store.locations.profileBackupURL,
                store.locations.journalPrimaryURL,
                store.locations.journalBackupURL,
            ]
            let evidenceBefore = try evidenceURLs.map {
                try optionalData(at: $0)
            }

            let checkpointHarness = rejection == "receipt"
                ? wrongObservation
                : targetObservation
            await assertThrowsErrorAsync({
                try await installCandidate(
                    store: store,
                    transactionID: rejection == "transaction"
                        ? fixture.fixedUUID(898)
                        : fixture.transactionID,
                    expected: fixture.expectedBinding,
                    checkpointHarness: checkpointHarness
                )
            },
                rejection
            ) { error in
                let expectedError: ProfileHydrationTransactionStoreError
                switch rejection {
                case "transaction":
                    expectedError = .transactionMismatch
                case "receipt":
                    expectedError = .checkpointConfirmationMismatch
                default:
                    expectedError = .unexpectedProfileBytes
                }
                XCTAssertEqual(
                    error as? ProfileHydrationTransactionStoreError,
                    expectedError,
                    rejection
                )
            }
            XCTAssertEqual(
                try evidenceURLs.map { try optionalData(at: $0) },
                evidenceBefore,
                rejection
            )
            XCTAssertTrue(
                try store.quarantinedEvidenceURLs().isEmpty,
                rejection
            )
            remove(root)
        }
    }

    func testAuthorizedInstallRepairsJournalPeerThenExactlyRevalidates()
        async throws
    {
        let fixture = try ProfileHydrationTestFixture()
        let targetObservation = try await checkpointLeaseHarness(
            fixture: fixture,
            checkpoints: [fixture.targetCheckpoint]
        )
        let root = try temporaryDirectory()
        defer { remove(root) }
        let store = makeStore(root: root)
        try seedSourceProfile(fixture, locations: store.locations)
        _ = try store.beginHydration(fixture.journal)
        let corruptPeer = Data("repair-then-revalidate-peer".utf8)
        try FoundationProfileHydrationFileSystem().writeAtomicallyDurably(
            corruptPeer,
            to: store.locations.journalBackupURL
        )

        let result = try await installCandidate(
            store: store,
            transactionID: fixture.transactionID,
            expected: fixture.expectedBinding,
            checkpointHarness: targetObservation
        )

        XCTAssertEqual(result.inspection.repairedJournalCopy, .backup)
        XCTAssertEqual(result.inspection.installationState, .candidate)
        let canonicalJournal = try ProfileHydrationCanonicalCodec.encode(
            fixture.journal
        )
        XCTAssertEqual(
            try Data(contentsOf: store.locations.journalPrimaryURL),
            canonicalJournal
        )
        XCTAssertEqual(
            try Data(contentsOf: store.locations.journalBackupURL),
            canonicalJournal
        )
        XCTAssertEqual(
            try Data(contentsOf: store.locations.profilePrimaryURL),
            fixture.candidateEnvelope
        )
        XCTAssertEqual(
            try Data(contentsOf: store.locations.profileBackupURL),
            fixture.candidateEnvelope
        )
        let evidenceURL = try XCTUnwrap(
            store.quarantinedEvidenceURLs().first
        )
        XCTAssertEqual(try Data(contentsOf: evidenceURL), corruptPeer)
    }

    func testStaleButValidProfileBytesFailWithoutBeingOverwritten() async throws {
        let fixture = try ProfileHydrationTestFixture()
        let targetObservation = try await checkpointLeaseHarness(
            fixture: fixture,
            checkpoints: [fixture.targetCheckpoint]
        )
        let root = try temporaryDirectory()
        defer { remove(root) }
        let store = makeStore(root: root)
        try seedSourceProfile(fixture, locations: store.locations)
        _ = try store.beginHydration(fixture.journal)
        var stale = fixture.sourceDocument
        stale.player.revision = 5
        stale.economyRevision = 5
        let staleBytes = try PlayerProfileMigrator().encode(
            stale,
            savedAt: fixture.date.addingTimeInterval(10)
        )
        try writeProfile(staleBytes, locations: store.locations)

        await assertThrowsErrorAsync {
            try await installCandidate(
                store: store,
                transactionID: fixture.transactionID,
                expected: fixture.expectedBinding,
                checkpointHarness: targetObservation
            )
        } errorHandler: { error in
            XCTAssertEqual(
                error as? ProfileHydrationTransactionStoreError,
                .unexpectedProfileBytes
            )
        }
        XCTAssertEqual(try Data(contentsOf: store.locations.profilePrimaryURL), staleBytes)
        XCTAssertEqual(try Data(contentsOf: store.locations.profileBackupURL), staleBytes)
    }

    func testWrongAccountScopeEpochAndProfileFailBeforeAnyProfileWrite() async throws {
        let fixture = try ProfileHydrationTestFixture()
        let targetObservation = try await checkpointLeaseHarness(
            fixture: fixture,
            checkpoints: [fixture.targetCheckpoint]
        )
        let root = try temporaryDirectory()
        defer { remove(root) }
        let store = makeStore(root: root)
        try seedSourceProfile(fixture, locations: store.locations)
        _ = try store.beginHydration(fixture.journal)
        let originalPrimary = try Data(contentsOf: store.locations.profilePrimaryURL)
        let target = fixture.expectedBinding
        let cases: [(ProfileHydrationExpectedBinding, ProfileHydrationBindingMismatch)] = [
            (
                ProfileHydrationExpectedBinding(
                    cloudAccountID: CloudAccountID("wrong-account"),
                    playerAccountIdentity: target.playerAccountIdentity,
                    accountKey: target.accountKey,
                    profileID: target.profileID,
                    configurationScopeFingerprint: target.configurationScopeFingerprint,
                    replicaEpoch: target.replicaEpoch
                ),
                .cloudAccountID
            ),
            (
                ProfileHydrationExpectedBinding(
                    cloudAccountID: target.cloudAccountID,
                    playerAccountIdentity: PlayerAccountIdentity("wrong-player"),
                    accountKey: target.accountKey,
                    profileID: target.profileID,
                    configurationScopeFingerprint: target.configurationScopeFingerprint,
                    replicaEpoch: target.replicaEpoch
                ),
                .playerAccountIdentity
            ),
            (
                ProfileHydrationExpectedBinding(
                    cloudAccountID: target.cloudAccountID,
                    playerAccountIdentity: target.playerAccountIdentity,
                    accountKey: ServiceAccountKey("wrong-account-key"),
                    profileID: target.profileID,
                    configurationScopeFingerprint: target.configurationScopeFingerprint,
                    replicaEpoch: target.replicaEpoch
                ),
                .accountKey
            ),
            (
                ProfileHydrationExpectedBinding(
                    cloudAccountID: target.cloudAccountID,
                    playerAccountIdentity: target.playerAccountIdentity,
                    accountKey: target.accountKey,
                    profileID: target.profileID,
                    configurationScopeFingerprint: fixture.alternateScope,
                    replicaEpoch: target.replicaEpoch
                ),
                .configurationScopeFingerprint
            ),
            (
                ProfileHydrationExpectedBinding(
                    cloudAccountID: target.cloudAccountID,
                    playerAccountIdentity: target.playerAccountIdentity,
                    accountKey: target.accountKey,
                    profileID: target.profileID,
                    configurationScopeFingerprint: target.configurationScopeFingerprint,
                    replicaEpoch: fixture.fixedUUID(801)
                ),
                .replicaEpoch
            ),
            (
                ProfileHydrationExpectedBinding(
                    cloudAccountID: target.cloudAccountID,
                    playerAccountIdentity: target.playerAccountIdentity,
                    accountKey: target.accountKey,
                    profileID: fixture.fixedUUID(802),
                    configurationScopeFingerprint: target.configurationScopeFingerprint,
                    replicaEpoch: target.replicaEpoch
                ),
                .profileID
            ),
        ]

        for (wrong, mismatch) in cases {
            await assertThrowsErrorAsync {
                try await installCandidate(
                    store: store,
                    transactionID: fixture.transactionID,
                    expected: wrong,
                    checkpointHarness: targetObservation
                )
            } errorHandler: { error in
                XCTAssertEqual(
                    error as? ProfileHydrationTransactionStoreError,
                    .bindingMismatch(mismatch)
                )
            }
            XCTAssertEqual(
                try Data(contentsOf: store.locations.profilePrimaryURL),
                originalPrimary
            )
        }
    }

    func testMissingBothProfileCopiesAreInspectedWithoutDefaultSynthesis() async throws {
        let fixture = try ProfileHydrationTestFixture()
        let targetObservation = try await checkpointLeaseHarness(
            fixture: fixture,
            checkpoints: [fixture.targetCheckpoint]
        )
        let root = try temporaryDirectory()
        defer { remove(root) }
        let store = makeStore(root: root)
        try seedSourceProfile(fixture, locations: store.locations)
        _ = try store.beginHydration(fixture.journal)
        let fileSystem = FoundationProfileHydrationFileSystem()
        try fileSystem.removeItemDurably(at: store.locations.profilePrimaryURL)
        try fileSystem.removeItemDurably(at: store.locations.profileBackupURL)

        let inspection = try XCTUnwrap(
            store.inspectRecovery(expected: fixture.expectedBinding)
        )
        XCTAssertEqual(inspection.primaryProfileState, .missing)
        XCTAssertEqual(inspection.backupProfileState, .missing)
        XCTAssertEqual(inspection.installationState, .incomplete)
        await assertThrowsErrorAsync {
            try await installCandidate(
                store: store,
                transactionID: fixture.transactionID,
                expected: fixture.expectedBinding,
                checkpointHarness: targetObservation
            )
        } errorHandler: { error in
            XCTAssertEqual(
                error as? ProfileHydrationTransactionStoreError,
                .profileCopiesMissing
            )
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.locations.profilePrimaryURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.locations.profileBackupURL.path))
    }

    func testOneExactSourceProfileCopyIsEnoughForJournalBoundRecovery() async throws {
        let fixture = try ProfileHydrationTestFixture()
        let targetObservation = try await checkpointLeaseHarness(
            fixture: fixture,
            checkpoints: [fixture.targetCheckpoint]
        )
        let root = try temporaryDirectory()
        defer { remove(root) }
        let store = makeStore(root: root)
        try seedSourceProfile(fixture, locations: store.locations)
        _ = try store.beginHydration(fixture.journal)
        try FoundationProfileHydrationFileSystem().removeItemDurably(
            at: store.locations.profileBackupURL
        )

        let result = try await installCandidate(
            store: store,
            transactionID: fixture.transactionID,
            expected: fixture.expectedBinding,
            checkpointHarness: targetObservation
        )
        XCTAssertEqual(result.inspection.installationState, .candidate)
        XCTAssertEqual(
            try Data(contentsOf: store.locations.profileBackupURL),
            fixture.candidateEnvelope
        )
    }

    func testCrashAfterRemovingOneJournalCopyDirectlyFinishesCleanup() async throws {
        let fixture = try ProfileHydrationTestFixture()
        let targetObservation = try await checkpointLeaseHarness(
            fixture: fixture,
            checkpoints: [fixture.targetCheckpoint]
        )
        let root = try temporaryDirectory()
        defer { remove(root) }
        let fault = FaultInjectingProfileHydrationFileSystem()
        let store = makeStore(root: root, fileSystem: fault)
        try seedSourceProfile(fixture, locations: store.locations)
        _ = try store.beginHydration(fixture.journal)
        _ = try await installCandidate(
            store: store,
            transactionID: fixture.transactionID,
            expected: fixture.expectedBinding,
            checkpointHarness: targetObservation
        )
        fault.failNext(.beforeRemove("profile-hydration-journal.json"))

        await assertThrowsErrorAsync {
            try await removeJournalAfterCheckpointConfirmation(
                store: store,
                transactionID: fixture.transactionID,
                expected: fixture.expectedBinding,
                checkpointHarness: targetObservation
            )
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.locations.journalPrimaryURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.locations.journalBackupURL.path))

        let noRepairFault = FaultInjectingProfileHydrationFileSystem()
        noRepairFault.failNext(
            .beforeWrite("profile-hydration-journal.backup.json")
        )
        let didFinishCleanup = try await removeJournalAfterCheckpointConfirmation(
            store: makeStore(root: root, fileSystem: noRepairFault),
            transactionID: fixture.transactionID,
            expected: fixture.expectedBinding,
            checkpointHarness: targetObservation
        )
        XCTAssertTrue(didFinishCleanup)
        XCTAssertNil(
            try makeStore(root: root).inspectRecovery(expected: fixture.expectedBinding)
        )
    }

    func testWrongCheckpointConfirmationCannotRemoveJournal() async throws {
        let fixture = try ProfileHydrationTestFixture()
        let targetObservation = try await checkpointLeaseHarness(
            fixture: fixture,
            checkpoints: [fixture.targetCheckpoint]
        )
        let otherCheckpoint = try fixture.checkpoint(
            generation: 1,
            cursorByte: 9
        )
        let wrongObservation = try await checkpointLeaseHarness(
            fixture: fixture,
            checkpoints: [otherCheckpoint]
        )
        let root = try temporaryDirectory()
        defer { remove(root) }
        let store = makeStore(root: root)
        try seedSourceProfile(fixture, locations: store.locations)
        _ = try store.beginHydration(fixture.journal)
        _ = try await installCandidate(
            store: store,
            transactionID: fixture.transactionID,
            expected: fixture.expectedBinding,
            checkpointHarness: targetObservation
        )

        await assertThrowsErrorAsync {
            try await removeJournalAfterCheckpointConfirmation(
                store: store,
                transactionID: fixture.transactionID,
                expected: fixture.expectedBinding,
                checkpointHarness: wrongObservation
            )
        } errorHandler: { error in
            XCTAssertEqual(
                error as? ProfileHydrationTransactionStoreError,
                .checkpointConfirmationMismatch
            )
        }
        assertJournalCopiesEqual(store.locations)
    }

    func testTargetCleanupFullFiveByFiveProfileStateMatrix() async throws {
        let fixture = try ProfileHydrationTestFixture()
        let targetObservation = try await checkpointLeaseHarness(
            fixture: fixture,
            checkpoints: [fixture.targetCheckpoint]
        )
        let unexpectedBytes = Data("cleanup-matrix-unexpected".utf8)
        let limits = compactMatrixLimits(fixture: fixture)
        let oversizedBytes = Data(
            repeating: 0x63,
            count: limits.maximumProfileEnvelopeBytes + 1
        )
        let fileSystem = FoundationProfileHydrationFileSystem()

        for primaryState in HydrationProfileMatrixState.allCases {
            for backupState in HydrationProfileMatrixState.allCases {
                let name = "\(primaryState.rawValue)/\(backupState.rawValue)"
                let root = try temporaryDirectory()
                let store = makeStore(root: root, limits: limits)
                try seedSourceProfile(fixture, locations: store.locations)
                _ = try store.beginHydration(fixture.journal)
                try applyMatrixState(
                    primaryState,
                    to: store.locations.profilePrimaryURL,
                    fixture: fixture,
                    unexpectedBytes: unexpectedBytes,
                    oversizedBytes: oversizedBytes
                )
                try applyMatrixState(
                    backupState,
                    to: store.locations.profileBackupURL,
                    fixture: fixture,
                    unexpectedBytes: unexpectedBytes,
                    oversizedBytes: oversizedBytes
                )
                let quarantineURL = store.locations.quarantineSlotURL(0)
                try fileSystem.createDirectory(
                    at: store.locations.quarantineDirectoryURL
                )
                try fileSystem.writeAtomicallyDurably(
                    Data("cleanup-matrix-evidence".utf8),
                    to: quarantineURL
                )
                let evidenceURLs = [
                    store.locations.profilePrimaryURL,
                    store.locations.profileBackupURL,
                    store.locations.journalPrimaryURL,
                    store.locations.journalBackupURL,
                    quarantineURL,
                ]
                let evidenceBefore = try evidenceURLs.map {
                    try optionalData(at: $0)
                }

                if primaryState == .candidate, backupState == .candidate {
                    let didRemoveJournal = try await
                        removeJournalAfterCheckpointConfirmation(
                            store: store,
                            transactionID: fixture.transactionID,
                            expected: fixture.expectedBinding,
                            checkpointHarness: targetObservation
                        )
                    XCTAssertTrue(
                        didRemoveJournal,
                        name
                    )
                    XCTAssertEqual(
                        try Data(contentsOf: store.locations.profilePrimaryURL),
                        fixture.candidateEnvelope,
                        name
                    )
                    XCTAssertEqual(
                        try Data(contentsOf: store.locations.profileBackupURL),
                        fixture.candidateEnvelope,
                        name
                    )
                    XCTAssertFalse(
                        FileManager.default.fileExists(
                            atPath: store.locations.journalPrimaryURL.path
                        ),
                        name
                    )
                    XCTAssertFalse(
                        FileManager.default.fileExists(
                            atPath: store.locations.journalBackupURL.path
                        ),
                        name
                    )
                    XCTAssertFalse(
                        FileManager.default.fileExists(
                            atPath: quarantineURL.path
                        ),
                        name
                    )
                } else {
                    await assertThrowsErrorAsync({
                        try await removeJournalAfterCheckpointConfirmation(
                            store: store,
                            transactionID: fixture.transactionID,
                            expected: fixture.expectedBinding,
                            checkpointHarness: targetObservation
                        )
                    },
                        name
                    ) { error in
                        XCTAssertEqual(
                            error as? ProfileHydrationTransactionStoreError,
                            .profileVerificationFailed,
                            name
                        )
                    }
                    XCTAssertEqual(
                        try evidenceURLs.map { try optionalData(at: $0) },
                        evidenceBefore,
                        name
                    )
                }
                remove(root)
            }
        }
    }

    func testNoJournalFalseIsUnauthenticatedOnlyWhenNoEvidenceExists()
        async throws
    {
        let fixture = try ProfileHydrationTestFixture()
        let targetObservation = try await checkpointLeaseHarness(
            fixture: fixture,
            checkpoints: [fixture.targetCheckpoint]
        )
        let predecessorObservation = try await checkpointLeaseHarness(
            fixture: fixture
        )
        let target = fixture.expectedBinding
        let wrongBinding = ProfileHydrationExpectedBinding(
            cloudAccountID: target.cloudAccountID,
            playerAccountIdentity: PlayerAccountIdentity("wrong-no-journal-player"),
            accountKey: target.accountKey,
            profileID: target.profileID,
            configurationScopeFingerprint: target.configurationScopeFingerprint,
            replicaEpoch: target.replicaEpoch
        )
        let fileSystem = FoundationProfileHydrationFileSystem()

        for usesTargetCleanup in [false, true] {
            for rejectedInput in ["transaction", "binding", "observation"] {
                for evidenceMode in ["none", "quarantine", "invalid journal"] {
                    let name = "\(usesTargetCleanup ? "target" : "abort") / "
                        + "\(rejectedInput) / evidence=\(evidenceMode)"
                    let root = try temporaryDirectory()
                    let store = makeStore(root: root)
                    try seedSourceProfile(fixture, locations: store.locations)
                    let profileBefore = try [
                        Data(contentsOf: store.locations.profilePrimaryURL),
                        Data(contentsOf: store.locations.profileBackupURL),
                    ]
                    let quarantineURL = store.locations.quarantineSlotURL(0)
                    let quarantineBytes = Data("unresolved-no-journal-evidence".utf8)
                    let invalidJournalBytes = Data(
                        "unresolved-invalid-journal-evidence".utf8
                    )
                    if evidenceMode == "quarantine" {
                        try fileSystem.createDirectory(
                            at: store.locations.quarantineDirectoryURL
                        )
                        try fileSystem.writeAtomicallyDurably(
                            quarantineBytes,
                            to: quarantineURL
                        )
                    } else if evidenceMode == "invalid journal" {
                        try fileSystem.writeAtomicallyDurably(
                            invalidJournalBytes,
                            to: store.locations.journalPrimaryURL
                        )
                    }
                    let transactionID = rejectedInput == "transaction"
                        ? fixture.fixedUUID(994)
                        : fixture.transactionID
                    let expected = rejectedInput == "binding"
                        ? wrongBinding
                        : fixture.expectedBinding
                    let cleanup: () async throws -> Bool = {
                        if usesTargetCleanup {
                            return try await self.removeJournalAfterCheckpointConfirmation(
                                store: store,
                                transactionID: transactionID,
                                expected: expected,
                                checkpointHarness:
                                    rejectedInput == "observation"
                                        ? predecessorObservation
                                        : targetObservation
                            )
                        }
                        return try await self.abortHydrationAfterPredecessorConfirmation(
                            store: store,
                            transactionID: transactionID,
                            expected: expected,
                            checkpointHarness:
                                rejectedInput == "observation"
                                    ? targetObservation
                                    : predecessorObservation
                        )
                    }

                    if evidenceMode == "quarantine" {
                        await assertThrowsErrorAsync({
                            try await cleanup()
                        }, name) { error in
                            XCTAssertEqual(
                                error as? ProfileHydrationTransactionStoreError,
                                .unrecoverableJournalEvidence,
                                name
                            )
                        }
                        XCTAssertEqual(
                            try Data(contentsOf: quarantineURL),
                            quarantineBytes,
                            name
                        )
                    } else if evidenceMode == "invalid journal" {
                        await assertThrowsErrorAsync({
                            try await cleanup()
                        }, name) { error in
                            XCTAssertEqual(
                                error as? ProfileHydrationTransactionStoreError,
                                .noValidJournalCopy,
                                name
                            )
                        }
                        XCTAssertEqual(
                            try Data(contentsOf: store.locations.journalPrimaryURL),
                            invalidJournalBytes,
                            name
                        )
                    } else {
                        let didCleanUp = try await cleanup()
                        XCTAssertFalse(didCleanUp, name)
                        XCTAssertTrue(
                            try store.quarantinedEvidenceURLs().isEmpty,
                            name
                        )
                    }
                    XCTAssertEqual(
                        try [
                            Data(contentsOf: store.locations.profilePrimaryURL),
                            Data(contentsOf: store.locations.profileBackupURL),
                        ],
                        profileBefore,
                        name
                    )
                    XCTAssertEqual(
                        FileManager.default.fileExists(
                            atPath: store.locations.journalPrimaryURL.path
                        ),
                        evidenceMode == "invalid journal",
                        name
                    )
                    XCTAssertFalse(
                        FileManager.default.fileExists(
                            atPath: store.locations.journalBackupURL.path
                        ),
                        name
                    )
                    remove(root)
                }
            }
        }
    }

    func testGenesisSourceOnlyAbortSucceedsAndNoBarrierRetryIsIdempotent()
        async throws
    {
        let fixture = try ProfileHydrationTestFixture()
        let predecessorObservation = try await checkpointLeaseHarness(
            fixture: fixture
        )
        let root = try temporaryDirectory()
        defer { remove(root) }
        let store = makeStore(root: root)
        try seedSourceProfile(fixture, locations: store.locations)
        _ = try store.beginHydration(fixture.journal)

        let didAbort = try await abortHydrationAfterPredecessorConfirmation(
            store: store,
            transactionID: fixture.transactionID,
            expected: fixture.expectedBinding,
            checkpointHarness: predecessorObservation
        )
        XCTAssertTrue(didAbort)
        XCTAssertEqual(
            try Data(contentsOf: store.locations.profilePrimaryURL),
            fixture.sourceEnvelope
        )
        XCTAssertEqual(
            try Data(contentsOf: store.locations.profileBackupURL),
            fixture.sourceEnvelope
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: store.locations.journalPrimaryURL.path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: store.locations.journalBackupURL.path
            )
        )
        let didRetryAbort = try await abortHydrationAfterPredecessorConfirmation(
            store: store,
            transactionID: fixture.transactionID,
            expected: fixture.expectedBinding,
            checkpointHarness: predecessorObservation
        )
        XCTAssertFalse(didRetryAbort)
    }

    func testNonGenesisSourceOnlyAbortRequiresAndAcceptsExactPredecessor()
        async throws
    {
        let fixture = try ProfileHydrationTestFixture()
        let predecessorCheckpoint = try fixture.checkpoint(
            generation: 1,
            cursorByte: 1
        )
        let predecessorIdentity = ProfileHydrationCheckpointIdentityV1(
            checkpoint: predecessorCheckpoint
        )
        let journal = try fixture.makeJournal(
            predecessor: predecessorIdentity,
            targetCheckpoint: try fixture.checkpoint(
                generation: 2,
                cursorByte: 2
            )
        )
        let predecessorObservation = try await checkpointLeaseHarness(
            fixture: fixture,
            checkpoints: [predecessorCheckpoint]
        )
        let root = try temporaryDirectory()
        defer { remove(root) }
        let store = makeStore(root: root)
        try seedSourceProfile(fixture, locations: store.locations)
        _ = try store.beginHydration(journal)

        let didAbort = try await abortHydrationAfterPredecessorConfirmation(
            store: store,
            transactionID: fixture.transactionID,
            expected: fixture.expectedBinding,
            checkpointHarness: predecessorObservation
        )
        XCTAssertTrue(didAbort)
        let didRetryAbort = try await abortHydrationAfterPredecessorConfirmation(
            store: store,
            transactionID: fixture.transactionID,
            expected: fixture.expectedBinding,
            checkpointHarness: predecessorObservation
        )
        XCTAssertFalse(didRetryAbort)
    }

    func testNonGenesisSourceOnlyAbortRejectsTargetUnrelatedAndAbsentObservation()
        async throws
    {
        let fixture = try ProfileHydrationTestFixture()
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
        let journal = try fixture.makeJournal(
            predecessor: predecessorIdentity,
            targetCheckpoint: targetCheckpoint
        )
        let unrelatedCheckpoint = try fixture.checkpoint(
            generation: 1,
            cursorByte: 9
        )
        let targetObservation = try await checkpointLeaseHarness(
            fixture: fixture,
            checkpoints: [predecessorCheckpoint, targetCheckpoint]
        )
        let unrelatedObservation = try await checkpointLeaseHarness(
            fixture: fixture,
            checkpoints: [unrelatedCheckpoint]
        )
        let absentObservation = try await checkpointLeaseHarness(
            fixture: fixture
        )
        let root = try temporaryDirectory()
        defer { remove(root) }
        let store = makeStore(root: root)
        try seedSourceProfile(fixture, locations: store.locations)
        _ = try store.beginHydration(journal)
        let evidenceURLs = [
            store.locations.profilePrimaryURL,
            store.locations.profileBackupURL,
            store.locations.journalPrimaryURL,
            store.locations.journalBackupURL,
        ]
        let evidenceBefore = try evidenceURLs.map { try Data(contentsOf: $0) }
        let confirmations: [(String, CheckpointLeaseHarness)] = [
            ("target", targetObservation),
            ("unrelated", unrelatedObservation),
            ("absent", absentObservation),
        ]

        for (name, confirmation) in confirmations {
            await assertThrowsErrorAsync({
                try await abortHydrationAfterPredecessorConfirmation(
                    store: store,
                    transactionID: fixture.transactionID,
                    expected: fixture.expectedBinding,
                    checkpointHarness: confirmation
                )
            },
                name
            ) { error in
                XCTAssertEqual(
                    error as? ProfileHydrationTransactionStoreError,
                    .checkpointConfirmationMismatch,
                    name
                )
            }
            XCTAssertEqual(
                try evidenceURLs.map { try Data(contentsOf: $0) },
                evidenceBefore,
                name
            )
        }
    }

    func testSourceOnlyAbortRejectsEveryNonSourcePairWithoutChangingEvidence()
        async throws
    {
        let fixture = try ProfileHydrationTestFixture()
        let predecessorObservation = try await checkpointLeaseHarness(
            fixture: fixture
        )
        let unexpectedBytes = Data("unexpected-profile-bytes".utf8)
        let limits = compactMatrixLimits(fixture: fixture)
        let oversizedBytes = Data(
            repeating: 0x6f,
            count: limits.maximumProfileEnvelopeBytes + 1
        )
        let cases: [(
            name: String,
            primaryBytes: Data?,
            backupBytes: Data?,
            primaryState: ProfileHydrationProfileCopyState,
            backupState: ProfileHydrationProfileCopyState
        )] = [
            (
                "source/candidate",
                fixture.sourceEnvelope,
                fixture.candidateEnvelope,
                .source,
                .candidate
            ),
            (
                "candidate/candidate",
                fixture.candidateEnvelope,
                fixture.candidateEnvelope,
                .candidate,
                .candidate
            ),
            (
                "candidate/source",
                fixture.candidateEnvelope,
                fixture.sourceEnvelope,
                .candidate,
                .source
            ),
            (
                "missing/source",
                nil,
                fixture.sourceEnvelope,
                .missing,
                .source
            ),
            (
                "source/missing",
                fixture.sourceEnvelope,
                nil,
                .source,
                .missing
            ),
            (
                "missing/missing",
                nil,
                nil,
                .missing,
                .missing
            ),
            (
                "unexpected/source",
                unexpectedBytes,
                fixture.sourceEnvelope,
                .unexpected(.envelopeBytes(unexpectedBytes)),
                .source
            ),
            (
                "source/unexpected",
                fixture.sourceEnvelope,
                unexpectedBytes,
                .source,
                .unexpected(.envelopeBytes(unexpectedBytes))
            ),
            (
                "oversized/source",
                oversizedBytes,
                fixture.sourceEnvelope,
                .oversized(oversizedBytes.count),
                .source
            ),
            (
                "source/oversized",
                fixture.sourceEnvelope,
                oversizedBytes,
                .source,
                .oversized(oversizedBytes.count)
            ),
        ]
        let fileSystem = FoundationProfileHydrationFileSystem()

        for testCase in cases {
            let root = try temporaryDirectory()
            let store = makeStore(root: root, limits: limits)
            try seedSourceProfile(fixture, locations: store.locations)
            _ = try store.beginHydration(fixture.journal)

            if let primaryBytes = testCase.primaryBytes {
                try fileSystem.writeAtomicallyDurably(
                    primaryBytes,
                    to: store.locations.profilePrimaryURL
                )
            } else {
                try fileSystem.removeItemDurably(
                    at: store.locations.profilePrimaryURL
                )
            }
            if let backupBytes = testCase.backupBytes {
                try fileSystem.writeAtomicallyDurably(
                    backupBytes,
                    to: store.locations.profileBackupURL
                )
            } else {
                try fileSystem.removeItemDurably(
                    at: store.locations.profileBackupURL
                )
            }
            let quarantineURL = store.locations.quarantineSlotURL(0)
            try fileSystem.createDirectory(
                at: store.locations.quarantineDirectoryURL
            )
            try fileSystem.writeAtomicallyDurably(
                Data("retained-\(testCase.name)".utf8),
                to: quarantineURL
            )
            let evidenceURLs = [
                store.locations.profilePrimaryURL,
                store.locations.profileBackupURL,
                store.locations.journalPrimaryURL,
                store.locations.journalBackupURL,
                quarantineURL,
            ]
            let evidenceBefore = try evidenceURLs.map {
                try optionalData(at: $0)
            }

            await assertThrowsErrorAsync({
                try await abortHydrationAfterPredecessorConfirmation(
                    store: store,
                    transactionID: fixture.transactionID,
                    expected: fixture.expectedBinding,
                    checkpointHarness: predecessorObservation
                )
            },
                testCase.name
            ) { error in
                XCTAssertEqual(
                    error as? ProfileHydrationTransactionStoreError,
                    .sourceOnlyAbortRejected(
                        primary: testCase.primaryState,
                        backup: testCase.backupState
                    ),
                    testCase.name
                )
            }
            XCTAssertEqual(
                try evidenceURLs.map { try optionalData(at: $0) },
                evidenceBefore,
                testCase.name
            )
            remove(root)
        }
    }

    func testSourceOnlyAbortFullFiveByFiveRejectionMatrix() async throws {
        let fixture = try ProfileHydrationTestFixture()
        let predecessorObservation = try await checkpointLeaseHarness(
            fixture: fixture
        )
        let unexpectedBytes = Data("abort-matrix-unexpected".utf8)
        let limits = compactMatrixLimits(fixture: fixture)
        let oversizedBytes = Data(
            repeating: 0x61,
            count: limits.maximumProfileEnvelopeBytes + 1
        )
        let fileSystem = FoundationProfileHydrationFileSystem()

        for primaryState in HydrationProfileMatrixState.allCases {
            for backupState in HydrationProfileMatrixState.allCases {
                guard primaryState != .source || backupState != .source else {
                    continue
                }
                let name = "\(primaryState.rawValue)/\(backupState.rawValue)"
                let root = try temporaryDirectory()
                let store = makeStore(root: root, limits: limits)
                try seedSourceProfile(fixture, locations: store.locations)
                _ = try store.beginHydration(fixture.journal)
                try applyMatrixState(
                    primaryState,
                    to: store.locations.profilePrimaryURL,
                    fixture: fixture,
                    unexpectedBytes: unexpectedBytes,
                    oversizedBytes: oversizedBytes
                )
                try applyMatrixState(
                    backupState,
                    to: store.locations.profileBackupURL,
                    fixture: fixture,
                    unexpectedBytes: unexpectedBytes,
                    oversizedBytes: oversizedBytes
                )
                let quarantineURL = store.locations.quarantineSlotURL(0)
                try fileSystem.createDirectory(
                    at: store.locations.quarantineDirectoryURL
                )
                try fileSystem.writeAtomicallyDurably(
                    Data("abort-matrix-evidence".utf8),
                    to: quarantineURL
                )
                let evidenceURLs = [
                    store.locations.profilePrimaryURL,
                    store.locations.profileBackupURL,
                    store.locations.journalPrimaryURL,
                    store.locations.journalBackupURL,
                    quarantineURL,
                ]
                let evidenceBefore = try evidenceURLs.map {
                    try optionalData(at: $0)
                }

                await assertThrowsErrorAsync({
                    try await abortHydrationAfterPredecessorConfirmation(
                        store: store,
                        transactionID: fixture.transactionID,
                        expected: fixture.expectedBinding,
                        checkpointHarness: predecessorObservation
                    )
                },
                    name
                ) { error in
                    XCTAssertEqual(
                        error as? ProfileHydrationTransactionStoreError,
                        .sourceOnlyAbortRejected(
                            primary: expectedCopyState(
                                for: primaryState,
                                unexpectedBytes: unexpectedBytes,
                                oversizedBytes: oversizedBytes
                            ),
                            backup: expectedCopyState(
                                for: backupState,
                                unexpectedBytes: unexpectedBytes,
                                oversizedBytes: oversizedBytes
                            )
                        ),
                        name
                    )
                }
                XCTAssertEqual(
                    try evidenceURLs.map { try optionalData(at: $0) },
                    evidenceBefore,
                    name
                )
                remove(root)
            }
        }
    }

    func testInterruptedSourceOnlyAbortCleanupDirectlyRetriesRemainingBarrier()
        async throws
    {
        let fixture = try ProfileHydrationTestFixture()
        let predecessorObservation = try await checkpointLeaseHarness(
            fixture: fixture
        )
        let root = try temporaryDirectory()
        defer { remove(root) }
        let fault = FaultInjectingProfileHydrationFileSystem()
        let store = makeStore(root: root, fileSystem: fault)
        try seedSourceProfile(fixture, locations: store.locations)
        _ = try store.beginHydration(fixture.journal)
        let fileSystem = FoundationProfileHydrationFileSystem()
        try fileSystem.createDirectory(
            at: store.locations.quarantineDirectoryURL
        )
        try fileSystem.writeAtomicallyDurably(
            Data("obsolete-invalid-copy-evidence".utf8),
            to: store.locations.quarantineSlotURL(0)
        )
        fault.failNext(.beforeRemove("profile-hydration-journal.json"))

        await assertThrowsErrorAsync {
            try await abortHydrationAfterPredecessorConfirmation(
                store: store,
                transactionID: fixture.transactionID,
                expected: fixture.expectedBinding,
                checkpointHarness: predecessorObservation
            )
        }
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: store.locations.quarantineSlotURL(0).path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: store.locations.journalPrimaryURL.path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: store.locations.journalBackupURL.path
            )
        )

        let noRepairFault = FaultInjectingProfileHydrationFileSystem()
        noRepairFault.failNext(
            .beforeWrite("profile-hydration-journal.backup.json")
        )
        let recovered = makeStore(root: root, fileSystem: noRepairFault)
        let didFinishAbort = try await abortHydrationAfterPredecessorConfirmation(
            store: recovered,
            transactionID: fixture.transactionID,
            expected: fixture.expectedBinding,
            checkpointHarness: predecessorObservation
        )
        XCTAssertTrue(didFinishAbort)
        let didRetryAbort = try await abortHydrationAfterPredecessorConfirmation(
            store: recovered,
            transactionID: fixture.transactionID,
            expected: fixture.expectedBinding,
            checkpointHarness: predecessorObservation
        )
        XCTAssertFalse(didRetryAbort)
        XCTAssertEqual(
            try Data(contentsOf: store.locations.profilePrimaryURL),
            fixture.sourceEnvelope
        )
        XCTAssertEqual(
            try Data(contentsOf: store.locations.profileBackupURL),
            fixture.sourceEnvelope
        )
    }

    func testCleanupRemovalFaultMatrixRetainsProfilesAndDurablyRetriesAbsence()
        async throws
    {
        let fixture = try ProfileHydrationTestFixture()
        let targetObservation = try await checkpointLeaseHarness(
            fixture: fixture,
            checkpoints: [fixture.targetCheckpoint]
        )
        let predecessorObservation = try await checkpointLeaseHarness(
            fixture: fixture
        )
        let failures: [(
            name: String,
            failure: FaultInjectingProfileHydrationFileSystem.Failure,
            finalRemovalMayHaveCompleted: Bool
        )] = [
            (
                "before quarantine removal",
                .beforeRemove("journal-evidence-0.json"),
                false
            ),
            (
                "after quarantine removal",
                .afterRemove("journal-evidence-0.json"),
                false
            ),
            (
                "before journal backup removal",
                .beforeRemove("profile-hydration-journal.backup.json"),
                false
            ),
            (
                "after journal backup removal",
                .afterRemove("profile-hydration-journal.backup.json"),
                false
            ),
            (
                "before journal primary removal",
                .beforeRemove("profile-hydration-journal.json"),
                false
            ),
            (
                "after journal primary removal",
                .afterRemove("profile-hydration-journal.json"),
                true
            ),
        ]

        for usesTargetCleanup in [false, true] {
            for testCase in failures {
                let name = usesTargetCleanup
                    ? "target / \(testCase.name)"
                    : "abort / \(testCase.name)"
                let root = try temporaryDirectory()
                let fault = FaultInjectingProfileHydrationFileSystem()
                let store = makeStore(root: root, fileSystem: fault)
                try seedSourceProfile(fixture, locations: store.locations)
                _ = try store.beginHydration(fixture.journal)
                if usesTargetCleanup {
                    _ = try await installCandidate(
                        store: store,
                        transactionID: fixture.transactionID,
                        expected: fixture.expectedBinding,
                        checkpointHarness: targetObservation
                    )
                }
                let fileSystem = FoundationProfileHydrationFileSystem()
                try fileSystem.createDirectory(
                    at: store.locations.quarantineDirectoryURL
                )
                try fileSystem.writeAtomicallyDurably(
                    Data("authorized-obsolete-evidence".utf8),
                    to: store.locations.quarantineSlotURL(0)
                )
                let expectedProfile = usesTargetCleanup
                    ? fixture.candidateEnvelope
                    : fixture.sourceEnvelope
                fault.failNext(testCase.failure)

                await assertThrowsErrorAsync({
                    try await performCleanup(
                        store: store,
                        fixture: fixture,
                        usesTargetCleanup: usesTargetCleanup,
                        targetObservation: targetObservation,
                        predecessorObservation: predecessorObservation
                    )
                },
                    name
                ) { error in
                    XCTAssertEqual(
                        error as? ProfileHydrationTransactionStoreError,
                        .ioFailure,
                        name
                    )
                }
                XCTAssertEqual(
                    try Data(contentsOf: store.locations.profilePrimaryURL),
                    expectedProfile,
                    name
                )
                XCTAssertEqual(
                    try Data(contentsOf: store.locations.profileBackupURL),
                    expectedProfile,
                    name
                )
                let pendingComponent: String?
                switch testCase.failure {
                case let .afterRemove(component):
                    pendingComponent = component
                    XCTAssertTrue(
                        fault.hasPendingRemovalDurability(for: component),
                        name
                    )
                default:
                    pendingComponent = nil
                }

                let retryStore = makeStore(root: root, fileSystem: fault)
                if testCase.finalRemovalMayHaveCompleted {
                    fault.failNext(
                        .beforeRemove("profile-hydration-journal.backup.json")
                    )
                    await assertThrowsErrorAsync({
                        try await performCleanup(
                            store: retryStore,
                            fixture: fixture,
                            usesTargetCleanup: usesTargetCleanup,
                            targetObservation: targetObservation,
                            predecessorObservation: predecessorObservation
                        )
                    },
                        "\(name) must execute the absence barrier"
                    ) { error in
                        XCTAssertEqual(
                            error as? ProfileHydrationTransactionStoreError,
                            .ioFailure,
                            name
                        )
                    }
                    if let pendingComponent {
                        XCTAssertTrue(
                            fault.hasPendingRemovalDurability(
                                for: pendingComponent
                            ),
                            "\(name) returned before reconciling the final removal"
                        )
                    }
                    let didRetryCleanup = try await performCleanup(
                        store: retryStore,
                        fixture: fixture,
                        usesTargetCleanup: usesTargetCleanup,
                        targetObservation: targetObservation,
                        predecessorObservation: predecessorObservation
                    )
                    XCTAssertFalse(didRetryCleanup, name)
                } else {
                    fault.failNext(
                        .beforeWrite("profile-hydration-journal.backup.json")
                    )
                    let didRetryCleanup = try await performCleanup(
                        store: retryStore,
                        fixture: fixture,
                        usesTargetCleanup: usesTargetCleanup,
                        targetObservation: targetObservation,
                        predecessorObservation: predecessorObservation
                    )
                    XCTAssertTrue(didRetryCleanup, name)
                }
                if let pendingComponent {
                    XCTAssertFalse(
                        fault.hasPendingRemovalDurability(for: pendingComponent),
                        "\(name) did not reconcile the missing entry"
                    )
                }
                XCTAssertFalse(
                    FileManager.default.fileExists(
                        atPath: store.locations.journalPrimaryURL.path
                    ),
                    name
                )
                XCTAssertFalse(
                    FileManager.default.fileExists(
                        atPath: store.locations.journalBackupURL.path
                    ),
                    name
                )
                XCTAssertTrue(
                    try retryStore.quarantinedEvidenceURLs().isEmpty,
                    name
                )
                remove(root)
            }
        }
    }

    func testAuthorizedCleanupDirectlyRemovesInvalidOrMissingJournalPeer()
        async throws
    {
        let fixture = try ProfileHydrationTestFixture()
        let targetObservation = try await checkpointLeaseHarness(
            fixture: fixture,
            checkpoints: [fixture.targetCheckpoint]
        )
        let predecessorObservation = try await checkpointLeaseHarness(
            fixture: fixture
        )
        let fileSystem = FoundationProfileHydrationFileSystem()

        let peerCases: [(name: String, isPrimary: Bool, isMissing: Bool)] = [
            ("invalid backup", false, false),
            ("invalid primary", true, false),
            ("missing backup", false, true),
            ("missing primary", true, true),
        ]

        for usesTargetCleanup in [false, true] {
            for peerCase in peerCases {
                let root = try temporaryDirectory()
                let fault = FaultInjectingProfileHydrationFileSystem()
                let store = makeStore(root: root, fileSystem: fault)
                try seedSourceProfile(fixture, locations: store.locations)
                _ = try store.beginHydration(fixture.journal)
                if usesTargetCleanup {
                    _ = try await installCandidate(
                        store: store,
                        transactionID: fixture.transactionID,
                        expected: fixture.expectedBinding,
                        checkpointHarness: targetObservation
                    )
                }
                let peerURL = peerCase.isPrimary
                    ? store.locations.journalPrimaryURL
                    : store.locations.journalBackupURL
                if peerCase.isMissing {
                    try fileSystem.removeItemDurably(at: peerURL)
                } else {
                    try fileSystem.writeAtomicallyDurably(
                        Data("authorized-invalid-journal-peer".utf8),
                        to: peerURL
                    )
                }
                fault.failNext(
                    .beforeWrite(peerURL.lastPathComponent)
                )

                let didCleanUp = try await performCleanup(
                    store: store,
                    fixture: fixture,
                    usesTargetCleanup: usesTargetCleanup,
                    targetObservation: targetObservation,
                    predecessorObservation: predecessorObservation
                )
                XCTAssertTrue(didCleanUp, peerCase.name)
                XCTAssertTrue(
                    try store.quarantinedEvidenceURLs().isEmpty,
                    peerCase.name
                )
                XCTAssertFalse(
                    FileManager.default.fileExists(
                        atPath: store.locations.journalPrimaryURL.path
                    ),
                    peerCase.name
                )
                XCTAssertFalse(
                    FileManager.default.fileExists(
                        atPath: store.locations.journalBackupURL.path
                    ),
                    peerCase.name
                )
                remove(root)
            }
        }
    }

    func testBackupOnlyCleanupInterruptionRetainsValidBarrierAndRetries()
        async throws
    {
        let fixture = try ProfileHydrationTestFixture()
        let targetObservation = try await checkpointLeaseHarness(
            fixture: fixture,
            checkpoints: [fixture.targetCheckpoint]
        )
        let predecessorObservation = try await checkpointLeaseHarness(
            fixture: fixture
        )
        let fileSystem = FoundationProfileHydrationFileSystem()

        for usesTargetCleanup in [false, true] {
            let root = try temporaryDirectory()
            let fault = FaultInjectingProfileHydrationFileSystem()
            let store = makeStore(root: root, fileSystem: fault)
            try seedSourceProfile(fixture, locations: store.locations)
            _ = try store.beginHydration(fixture.journal)
            if usesTargetCleanup {
                _ = try await installCandidate(
                    store: store,
                    transactionID: fixture.transactionID,
                    expected: fixture.expectedBinding,
                    checkpointHarness: targetObservation
                )
            }
            let exactBackup = try Data(
                contentsOf: store.locations.journalBackupURL
            )
            try fileSystem.writeAtomicallyDurably(
                Data("invalid-primary-before-cleanup".utf8),
                to: store.locations.journalPrimaryURL
            )
            fault.failNext(
                .beforeRemove("profile-hydration-journal.backup.json")
            )

            await assertThrowsErrorAsync {
                try await performCleanup(
                    store: store,
                    fixture: fixture,
                    usesTargetCleanup: usesTargetCleanup,
                    targetObservation: targetObservation,
                    predecessorObservation: predecessorObservation
                )
            }
            XCTAssertFalse(
                FileManager.default.fileExists(
                    atPath: store.locations.journalPrimaryURL.path
                )
            )
            XCTAssertEqual(
                try Data(contentsOf: store.locations.journalBackupURL),
                exactBackup
            )

            let noRepairFault = FaultInjectingProfileHydrationFileSystem()
            noRepairFault.failNext(
                .beforeWrite("profile-hydration-journal.json")
            )
            let didRetryCleanup = try await performCleanup(
                store: makeStore(root: root, fileSystem: noRepairFault),
                fixture: fixture,
                usesTargetCleanup: usesTargetCleanup,
                targetObservation: targetObservation,
                predecessorObservation: predecessorObservation
            )
            XCTAssertTrue(didRetryCleanup)
            remove(root)
        }
    }

    func testCleanupReceiptRejectionsDoNotRepairOrQuarantineInvalidPeer()
        async throws
    {
        let fixture = try ProfileHydrationTestFixture()
        let targetObservation = try await checkpointLeaseHarness(
            fixture: fixture,
            checkpoints: [fixture.targetCheckpoint]
        )
        let wrongCheckpoint = try fixture.checkpoint(
            generation: 1,
            cursorByte: 9
        )
        let wrongObservation = try await checkpointLeaseHarness(
            fixture: fixture,
            checkpoints: [wrongCheckpoint]
        )
        let invalidPeer = Data("rejected-invalid-journal-peer".utf8)
        let fileSystem = FoundationProfileHydrationFileSystem()

        for usesTargetCleanup in [false, true] {
            let root = try temporaryDirectory()
            let store = makeStore(root: root)
            try seedSourceProfile(fixture, locations: store.locations)
            _ = try store.beginHydration(fixture.journal)
            if usesTargetCleanup {
                _ = try await installCandidate(
                    store: store,
                    transactionID: fixture.transactionID,
                    expected: fixture.expectedBinding,
                    checkpointHarness: targetObservation
                )
            }
            try fileSystem.writeAtomicallyDurably(
                invalidPeer,
                to: store.locations.journalBackupURL
            )
            let evidenceURLs = [
                store.locations.profilePrimaryURL,
                store.locations.profileBackupURL,
                store.locations.journalPrimaryURL,
                store.locations.journalBackupURL,
            ]
            let evidenceBefore = try evidenceURLs.map {
                try optionalData(at: $0)
            }

            let rejectedCleanup: () async throws -> Bool = {
                if usesTargetCleanup {
                    return try await self.removeJournalAfterCheckpointConfirmation(
                        store: store,
                        transactionID: fixture.transactionID,
                        expected: fixture.expectedBinding,
                        checkpointHarness: wrongObservation
                    )
                }
                return try await self.abortHydrationAfterPredecessorConfirmation(
                    store: store,
                    transactionID: fixture.transactionID,
                    expected: fixture.expectedBinding,
                    checkpointHarness: targetObservation
                )
            }
            await assertThrowsErrorAsync {
                try await rejectedCleanup()
            } errorHandler: { error in
                XCTAssertEqual(
                    error as? ProfileHydrationTransactionStoreError,
                    .checkpointConfirmationMismatch
                )
            }
            XCTAssertEqual(
                try evidenceURLs.map { try optionalData(at: $0) },
                evidenceBefore
            )
            XCTAssertTrue(try store.quarantinedEvidenceURLs().isEmpty)
            remove(root)
        }
    }

    func testCleanupWrongTransactionAndBindingPreserveInvalidPeer()
        async throws
    {
        let fixture = try ProfileHydrationTestFixture()
        let targetObservation = try await checkpointLeaseHarness(
            fixture: fixture,
            checkpoints: [fixture.targetCheckpoint]
        )
        let predecessorObservation = try await checkpointLeaseHarness(
            fixture: fixture
        )
        let target = fixture.expectedBinding
        let wrongBinding = ProfileHydrationExpectedBinding(
            cloudAccountID: target.cloudAccountID,
            playerAccountIdentity: target.playerAccountIdentity,
            accountKey: ServiceAccountKey("cleanup-wrong-account-key"),
            profileID: target.profileID,
            configurationScopeFingerprint: target.configurationScopeFingerprint,
            replicaEpoch: target.replicaEpoch
        )
        let invalidPeer = Data("rejected-invalid-cleanup-peer".utf8)
        let fileSystem = FoundationProfileHydrationFileSystem()

        for usesTargetCleanup in [false, true] {
            for rejection in ["transaction", "binding"] {
                let name = "\(usesTargetCleanup ? "target" : "abort") / \(rejection)"
                let root = try temporaryDirectory()
                let store = makeStore(root: root)
                try seedSourceProfile(fixture, locations: store.locations)
                _ = try store.beginHydration(fixture.journal)
                if usesTargetCleanup {
                    _ = try await installCandidate(
                        store: store,
                        transactionID: fixture.transactionID,
                        expected: fixture.expectedBinding,
                        checkpointHarness: targetObservation
                    )
                }
                try fileSystem.writeAtomicallyDurably(
                    invalidPeer,
                    to: store.locations.journalBackupURL
                )
                let evidenceURLs = [
                    store.locations.profilePrimaryURL,
                    store.locations.profileBackupURL,
                    store.locations.journalPrimaryURL,
                    store.locations.journalBackupURL,
                ]
                let evidenceBefore = try evidenceURLs.map {
                    try optionalData(at: $0)
                }
                let cleanup: () async throws -> Bool = {
                    if usesTargetCleanup {
                        return try await self.removeJournalAfterCheckpointConfirmation(
                            store: store,
                            transactionID: rejection == "transaction"
                                ? fixture.fixedUUID(993)
                                : fixture.transactionID,
                            expected: rejection == "binding"
                                ? wrongBinding
                                : fixture.expectedBinding,
                            checkpointHarness: targetObservation
                        )
                    }
                    return try await self.abortHydrationAfterPredecessorConfirmation(
                        store: store,
                        transactionID: rejection == "transaction"
                            ? fixture.fixedUUID(993)
                            : fixture.transactionID,
                        expected: rejection == "binding"
                            ? wrongBinding
                            : fixture.expectedBinding,
                        checkpointHarness: predecessorObservation
                    )
                }

                await assertThrowsErrorAsync({
                    try await cleanup()
                }, name) { error in
                    XCTAssertEqual(
                        error as? ProfileHydrationTransactionStoreError,
                        rejection == "transaction"
                            ? .transactionMismatch
                            : .bindingMismatch(.accountKey),
                        name
                    )
                }
                XCTAssertEqual(
                    try evidenceURLs.map { try optionalData(at: $0) },
                    evidenceBefore,
                    name
                )
                XCTAssertTrue(
                    try store.quarantinedEvidenceURLs().isEmpty,
                    name
                )
                remove(root)
            }
        }
    }

    func testBothCorruptJournalsRemainInPlaceAcrossReadOnlyInspection() throws {
        let fixture = try ProfileHydrationTestFixture()
        let root = try temporaryDirectory()
        defer { remove(root) }
        let store = makeStore(root: root)
        try seedSourceProfile(fixture, locations: store.locations)
        _ = try store.beginHydration(fixture.journal)
        let fileSystem = FoundationProfileHydrationFileSystem()
        try fileSystem.writeAtomicallyDurably(
            Data("corrupt-primary".utf8),
            to: store.locations.journalPrimaryURL
        )
        try fileSystem.writeAtomicallyDurably(
            Data("corrupt-backup".utf8),
            to: store.locations.journalBackupURL
        )

        XCTAssertThrowsError(
            try store.beginHydration(fixture.journal)
        ) { error in
            XCTAssertEqual(
                error as? ProfileHydrationTransactionStoreError,
                .noValidJournalCopy
            )
        }
        XCTAssertTrue(try store.quarantinedEvidenceURLs().isEmpty)
        XCTAssertThrowsError(
            try store.inspectRecovery(expected: fixture.expectedBinding)
        ) { error in
            XCTAssertEqual(
                error as? ProfileHydrationTransactionStoreError,
                .noValidJournalCopy
            )
        }
        XCTAssertEqual(
            try Data(contentsOf: store.locations.journalPrimaryURL),
            Data("corrupt-primary".utf8)
        )
        XCTAssertEqual(
            try Data(contentsOf: store.locations.journalBackupURL),
            Data("corrupt-backup".utf8)
        )
    }

    func testInspectionNeverMovesOversizedInvalidJournalEvidence() throws {
        let fixture = try ProfileHydrationTestFixture()
        let root = try temporaryDirectory()
        defer { remove(root) }
        let limits = fixture.limits(
            maximumEncodedJournalBytes: 1_024,
            maximumQuarantineFiles: 2,
            maximumQuarantineBytes: 8
        )
        let store = makeStore(root: root, limits: limits)
        let bytes = Data(repeating: 0x78, count: 16)
        let fileSystem = FoundationProfileHydrationFileSystem()
        try fileSystem.writeAtomicallyDurably(bytes, to: store.locations.journalPrimaryURL)
        try fileSystem.writeAtomicallyDurably(bytes, to: store.locations.journalBackupURL)

        XCTAssertThrowsError(
            try store.inspectRecovery(expected: fixture.expectedBinding)
        ) { error in
            XCTAssertEqual(
                error as? ProfileHydrationTransactionStoreError,
                .noValidJournalCopy
            )
        }
        XCTAssertEqual(try Data(contentsOf: store.locations.journalPrimaryURL), bytes)
        XCTAssertEqual(try Data(contentsOf: store.locations.journalBackupURL), bytes)
        XCTAssertTrue(try store.quarantinedEvidenceURLs().isEmpty)
    }

    func testFixedQuarantineSlotBoundPreservesNewCorruptCopyInPlace() throws {
        let fixture = try ProfileHydrationTestFixture()
        let root = try temporaryDirectory()
        defer { remove(root) }
        let limits = fixture.limits(
            maximumQuarantineFiles: 1,
            maximumQuarantineBytes: 1_024 * 1_024
        )
        let store = makeStore(root: root, limits: limits)
        try seedSourceProfile(fixture, locations: store.locations)
        _ = try store.beginHydration(fixture.journal)
        let fileSystem = FoundationProfileHydrationFileSystem()
        try fileSystem.createDirectory(at: store.locations.quarantineDirectoryURL)
        try fileSystem.writeAtomicallyDurably(
            Data("prior-evidence".utf8),
            to: store.locations.quarantineSlotURL(0)
        )
        let corrupt = Data("new-corruption".utf8)
        try fileSystem.writeAtomicallyDurably(corrupt, to: store.locations.journalBackupURL)

        XCTAssertThrowsError(
            try store.beginHydration(fixture.journal)
        ) { error in
            XCTAssertEqual(
                error as? ProfileHydrationTransactionStoreError,
                .quarantineCapacityExceeded
            )
        }
        XCTAssertEqual(try Data(contentsOf: store.locations.journalBackupURL), corrupt)
        XCTAssertEqual(
            try Data(contentsOf: store.locations.quarantineSlotURL(0)),
            Data("prior-evidence".utf8)
        )
    }

    func testThrowingStatusAndReadFailuresFailClosedWithoutChangingEvidence() throws {
        let fixture = try ProfileHydrationTestFixture()
        let liveCopyFailures: [
            (String, FaultInjectingProfileHydrationFileSystem.Failure)
        ] = [
            (
                "journal primary status",
                .beforeStatus("profile-hydration-journal.json")
            ),
            (
                "journal primary read",
                .beforeRead("profile-hydration-journal.json")
            ),
            (
                "journal backup status",
                .beforeStatus("profile-hydration-journal.backup.json")
            ),
            (
                "journal backup read",
                .beforeRead("profile-hydration-journal.backup.json")
            ),
            ("profile primary status", .beforeStatus("player-profile.json")),
            ("profile primary read", .beforeRead("player-profile.json")),
            (
                "profile backup status",
                .beforeStatus("player-profile.backup.json")
            ),
            (
                "profile backup read",
                .beforeRead("player-profile.backup.json")
            )
        ]

        for (name, failure) in liveCopyFailures {
            let root = try temporaryDirectory()
            let baseStore = makeStore(root: root)
            try seedSourceProfile(fixture, locations: baseStore.locations)
            _ = try baseStore.beginHydration(fixture.journal)
            let evidenceURLs = [
                baseStore.locations.profilePrimaryURL,
                baseStore.locations.profileBackupURL,
                baseStore.locations.journalPrimaryURL,
                baseStore.locations.journalBackupURL
            ]
            let evidenceBefore = try evidenceURLs.map { try Data(contentsOf: $0) }
            let fault = FaultInjectingProfileHydrationFileSystem()
            fault.failNext(failure)
            let faultedStore = makeStore(root: root, fileSystem: fault)

            XCTAssertThrowsError(
                try faultedStore.inspectRecovery(expected: fixture.expectedBinding),
                name
            ) { error in
                XCTAssertEqual(
                    error as? ProfileHydrationTransactionStoreError,
                    .ioFailure,
                    name
                )
            }
            XCTAssertEqual(
                try evidenceURLs.map { try Data(contentsOf: $0) },
                evidenceBefore,
                name
            )
            remove(root)
        }

        for (name, failure) in [
            (
                "quarantine status",
                FaultInjectingProfileHydrationFileSystem.Failure.beforeStatus(
                    "journal-evidence-0.json"
                )
            )
        ] {
            let root = try temporaryDirectory()
            let baseStore = makeStore(root: root)
            try seedSourceProfile(fixture, locations: baseStore.locations)
            let fileSystem = FoundationProfileHydrationFileSystem()
            let quarantineURL = baseStore.locations.quarantineSlotURL(0)
            let quarantineBytes = Data("retained-journal-evidence".utf8)
            try fileSystem.createDirectory(
                at: baseStore.locations.quarantineDirectoryURL
            )
            try fileSystem.writeAtomicallyDurably(quarantineBytes, to: quarantineURL)
            let profileBefore = try [
                Data(contentsOf: baseStore.locations.profilePrimaryURL),
                Data(contentsOf: baseStore.locations.profileBackupURL)
            ]
            let fault = FaultInjectingProfileHydrationFileSystem()
            fault.failNext(failure)
            let faultedStore = makeStore(root: root, fileSystem: fault)

            XCTAssertThrowsError(
                try faultedStore.inspectRecovery(expected: fixture.expectedBinding),
                name
            ) { error in
                XCTAssertEqual(
                    error as? ProfileHydrationTransactionStoreError,
                    .ioFailure,
                    name
                )
            }
            XCTAssertEqual(
                try [
                    Data(contentsOf: baseStore.locations.profilePrimaryURL),
                    Data(contentsOf: baseStore.locations.profileBackupURL)
                ],
                profileBefore,
                name
            )
            XCTAssertEqual(try Data(contentsOf: quarantineURL), quarantineBytes, name)
            XCTAssertFalse(
                FileManager.default.fileExists(
                    atPath: baseStore.locations.journalPrimaryURL.path
                ),
                name
            )
            XCTAssertFalse(
                FileManager.default.fileExists(
                    atPath: baseStore.locations.journalBackupURL.path
                ),
                name
            )
            remove(root)
        }
    }

    func testLockContentionFailsFastWithTypedError() throws {
        let fixture = try ProfileHydrationTestFixture()
        let root = try temporaryDirectory()
        defer { remove(root) }
        let fault = FaultInjectingProfileHydrationFileSystem()
        let store = makeStore(root: root, fileSystem: fault)
        try seedSourceProfile(fixture, locations: store.locations)
        fault.failNext(.lock)

        XCTAssertThrowsError(
            try store.beginHydration(fixture.journal)
        ) { error in
            XCTAssertEqual(
                error as? ProfileHydrationTransactionStoreError,
                .lockContended
            )
        }
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: store.locations.journalPrimaryURL.path
            )
        )
    }

    func testProfileLockContentionEscapesScopedCheckpointLeaseUnchanged()
        async throws
    {
        let fixture = try ProfileHydrationTestFixture()
        let targetCheckpoint = try await checkpointLeaseHarness(
            fixture: fixture,
            checkpoints: [fixture.targetCheckpoint]
        )
        let root = try temporaryDirectory()
        defer { remove(root) }
        let fault = FaultInjectingProfileHydrationFileSystem()
        let store = makeStore(root: root, fileSystem: fault)
        try seedSourceProfile(fixture, locations: store.locations)
        _ = try store.beginHydration(fixture.journal)
        fault.failNext(.lock)

        await assertThrowsErrorAsync {
            try await installCandidate(
                store: store,
                transactionID: fixture.transactionID,
                expected: fixture.expectedBinding,
                checkpointHarness: targetCheckpoint
            )
        } errorHandler: { error in
            XCTAssertEqual(
                error as? ProfileHydrationTransactionStoreError,
                .lockContended
            )
        }
        XCTAssertEqual(
            try Data(contentsOf: store.locations.profilePrimaryURL),
            fixture.sourceEnvelope
        )
        assertJournalCopiesEqual(store.locations)
    }

    func testCheckpointLockEnclosesProfileLockForEveryHydrationMutation()
        async throws
    {
        let fixture = try ProfileHydrationTestFixture()
        let expectedSuffix: [ScopedHydrationLockEvent] = [
            .checkpointEntered,
            .profileEntered,
            .profileExited,
            .checkpointExited,
        ]

        for operation in ["install", "abort", "cleanup"] {
            let recorder = ScopedHydrationLockRecorder()
            let checkpointHarness = try await checkpointLeaseHarness(
                fixture: fixture,
                checkpoints: operation == "abort"
                    ? []
                    : [fixture.targetCheckpoint],
                fileSystem: LockRecordingCloudReplicaCheckpointFileSystem(
                    recorder: recorder
                )
            )
            let root = try temporaryDirectory()
            let store = makeStore(
                root: root,
                fileSystem: LockRecordingProfileHydrationFileSystem(
                    recorder: recorder
                )
            )
            try seedSourceProfile(fixture, locations: store.locations)
            _ = try store.beginHydration(fixture.journal)

            if operation == "cleanup" {
                _ = try await installCandidate(
                    store: store,
                    transactionID: fixture.transactionID,
                    expected: fixture.expectedBinding,
                    checkpointHarness: checkpointHarness
                )
            }
            recorder.reset()

            switch operation {
            case "install":
                _ = try await installCandidate(
                    store: store,
                    transactionID: fixture.transactionID,
                    expected: fixture.expectedBinding,
                    checkpointHarness: checkpointHarness
                )
            case "abort":
                let didAbort = try await
                    abortHydrationAfterPredecessorConfirmation(
                        store: store,
                        transactionID: fixture.transactionID,
                        expected: fixture.expectedBinding,
                        checkpointHarness: checkpointHarness
                    )
                XCTAssertTrue(didAbort, operation)
            default:
                let didCleanUp = try await
                    removeJournalAfterCheckpointConfirmation(
                        store: store,
                        transactionID: fixture.transactionID,
                        expected: fixture.expectedBinding,
                        checkpointHarness: checkpointHarness
                    )
                XCTAssertTrue(didCleanUp, operation)
            }

            XCTAssertEqual(
                Array(recorder.events.suffix(expectedSuffix.count)),
                expectedSuffix,
                operation
            )
            remove(root)
        }
    }

    func testFoundationFileSystemTwoDescriptorFlockContentionAndRelease()
        throws
    {
        let root = try temporaryDirectory()
        defer { remove(root) }
        let lockURL = root.appendingPathComponent("real-flock.lock")
        let first = FoundationProfileHydrationFileSystem()
        let second = FoundationProfileHydrationFileSystem()
        var secondEnteredWhileContended = false

        try first.withExclusiveLock(at: lockURL) {
            XCTAssertThrowsError(
                try second.withExclusiveLock(at: lockURL) {
                    secondEnteredWhileContended = true
                }
            ) { error in
                XCTAssertEqual(
                    error as? ProfileHydrationFileSystemError,
                    .lockContended
                )
            }
        }
        XCTAssertFalse(secondEnteredWhileContended)

        var secondEnteredAfterRelease = false
        try second.withExclusiveLock(at: lockURL) {
            secondEnteredAfterRelease = true
        }
        XCTAssertTrue(secondEnteredAfterRelease)
    }

    private func makeStore(
        root: URL,
        limits: ProfileHydrationLimits = .production,
        fileSystem: any ProfileHydrationFileSystem = FoundationProfileHydrationFileSystem()
    ) -> ProfileHydrationFileTransactionStore {
        ProfileHydrationFileTransactionStore(
            profileDirectoryURL: root,
            limits: limits,
            fileSystem: fileSystem
        )
    }

    private func checkpointLeaseHarness(
        fixture: ProfileHydrationTestFixture,
        accountID: CloudAccountID? = nil,
        scope: CloudReplicaScopeFingerprint? = nil,
        replicaEpoch: UUID? = nil,
        checkpoints: [CloudReplicaCheckpointV1] = [],
        fileSystem: any CloudReplicaCheckpointFileSystem =
            FoundationCloudReplicaCheckpointFileSystem()
    ) async throws -> CheckpointLeaseHarness {
        let accountID = accountID ?? fixture.cloudAccountID
        let scope = scope ?? fixture.scope
        let replicaEpoch = replicaEpoch ?? fixture.replicaEpoch
        let root = try temporaryDirectory()
        let authority = CloudAccountGenerationAuthority()
        let store = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: root,
            fileSystem: fileSystem,
            accountGenerationAuthority: authority
        )
        do {
            let generation = try await authority.activate(
                accountID: accountID,
                configurationScopeFingerprint: scope,
                replicaEpoch: replicaEpoch
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
            return CheckpointLeaseHarness(
                rootDirectoryURL: root,
                store: store,
                authority: authority,
                generation: generation,
                observedAt: fixture.date
            )
        } catch {
            remove(root)
            throw error
        }
    }

    private func installCandidate(
        store: ProfileHydrationFileTransactionStore,
        transactionID: UUID,
        expected: ProfileHydrationExpectedBinding,
        checkpointHarness: CheckpointLeaseHarness
    ) async throws -> ProfileHydrationCandidateInstallResult {
        try await checkpointHarness.authority.withCurrentGeneration(
            checkpointHarness.generation
        ) { accountLease in
            try await checkpointHarness.store.withCurrentCheckpointLease(
                generationLease: accountLease,
                at: checkpointHarness.observedAt
            ) { lease in
                try store.installCandidate(
                    transactionID: transactionID,
                    expected: expected,
                    checkpointLease: lease
                )
            }
        }
    }

    private func removeJournalAfterCheckpointConfirmation(
        store: ProfileHydrationFileTransactionStore,
        transactionID: UUID,
        expected: ProfileHydrationExpectedBinding,
        checkpointHarness: CheckpointLeaseHarness
    ) async throws -> Bool {
        try await checkpointHarness.authority.withCurrentGeneration(
            checkpointHarness.generation
        ) { accountLease in
            try await checkpointHarness.store.withCurrentCheckpointLease(
                generationLease: accountLease,
                at: checkpointHarness.observedAt
            ) { lease in
                try store.removeJournalAfterCheckpointConfirmation(
                    transactionID: transactionID,
                    expected: expected,
                    checkpointLease: lease
                )
            }
        }
    }

    private func abortHydrationAfterPredecessorConfirmation(
        store: ProfileHydrationFileTransactionStore,
        transactionID: UUID,
        expected: ProfileHydrationExpectedBinding,
        checkpointHarness: CheckpointLeaseHarness
    ) async throws -> Bool {
        try await checkpointHarness.authority.withCurrentGeneration(
            checkpointHarness.generation
        ) { accountLease in
            try await checkpointHarness.store.withCurrentCheckpointLease(
                generationLease: accountLease,
                at: checkpointHarness.observedAt
            ) { lease in
                try store.abortHydrationAfterPredecessorConfirmation(
                    transactionID: transactionID,
                    expected: expected,
                    checkpointLease: lease
                )
            }
        }
    }

    private func performCleanup(
        store: ProfileHydrationFileTransactionStore,
        fixture: ProfileHydrationTestFixture,
        usesTargetCleanup: Bool,
        targetObservation: CheckpointLeaseHarness,
        predecessorObservation: CheckpointLeaseHarness
    ) async throws -> Bool {
        if usesTargetCleanup {
            return try await removeJournalAfterCheckpointConfirmation(
                store: store,
                transactionID: fixture.transactionID,
                expected: fixture.expectedBinding,
                checkpointHarness: targetObservation
            )
        }
        return try await abortHydrationAfterPredecessorConfirmation(
            store: store,
            transactionID: fixture.transactionID,
            expected: fixture.expectedBinding,
            checkpointHarness: predecessorObservation
        )
    }

    private func assertThrowsErrorAsync<Result>(
        _ operation: () async throws -> Result,
        _ message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line,
        errorHandler: (Error) -> Void = { _ in }
    ) async {
        do {
            _ = try await operation()
            let failure = message.isEmpty
                ? "Expected error to be thrown"
                : "Expected error to be thrown: \(message)"
            XCTFail(failure, file: file, line: line)
        } catch {
            errorHandler(error)
        }
    }

    private func seedSourceProfile(
        _ fixture: ProfileHydrationTestFixture,
        locations: ProfileHydrationTransactionLocations
    ) throws {
        try writeProfile(fixture.sourceEnvelope, locations: locations)
    }

    private func writeProfile(
        _ data: Data,
        locations: ProfileHydrationTransactionLocations
    ) throws {
        try writeProfileCopies(
            primary: data,
            backup: data,
            locations: locations
        )
    }

    private func writeProfileCopies(
        primary: Data,
        backup: Data,
        locations: ProfileHydrationTransactionLocations
    ) throws {
        let fileSystem = FoundationProfileHydrationFileSystem()
        try fileSystem.writeAtomicallyDurably(
            primary,
            to: locations.profilePrimaryURL
        )
        try fileSystem.writeAtomicallyDurably(
            backup,
            to: locations.profileBackupURL
        )
    }

    private func applyMatrixState(
        _ state: HydrationProfileMatrixState,
        to url: URL,
        fixture: ProfileHydrationTestFixture,
        unexpectedBytes: Data,
        oversizedBytes: Data
    ) throws {
        let fileSystem = FoundationProfileHydrationFileSystem()
        guard let bytes = matrixBytes(
            for: state,
            fixture: fixture,
            unexpectedBytes: unexpectedBytes,
            oversizedBytes: oversizedBytes
        ) else {
            try fileSystem.removeItemDurably(at: url)
            return
        }
        try fileSystem.writeAtomicallyDurably(bytes, to: url)
    }

    private func compactMatrixLimits(
        fixture: ProfileHydrationTestFixture
    ) -> ProfileHydrationLimits {
        fixture.limits(
            maximumProfileEnvelopeBytes: max(
                fixture.sourceEnvelope.count,
                fixture.candidateEnvelope.count
            ) + 64
        )
    }

    private func matrixBytes(
        for state: HydrationProfileMatrixState,
        fixture: ProfileHydrationTestFixture,
        unexpectedBytes: Data,
        oversizedBytes: Data
    ) -> Data? {
        switch state {
        case .source:
            return fixture.sourceEnvelope
        case .candidate:
            return fixture.candidateEnvelope
        case .missing:
            return nil
        case .unexpected:
            return unexpectedBytes
        case .oversized:
            return oversizedBytes
        }
    }

    private func expectedCopyState(
        for state: HydrationProfileMatrixState,
        unexpectedBytes: Data,
        oversizedBytes: Data
    ) -> ProfileHydrationProfileCopyState {
        switch state {
        case .source:
            return .source
        case .candidate:
            return .candidate
        case .missing:
            return .missing
        case .unexpected:
            return .unexpected(.envelopeBytes(unexpectedBytes))
        case .oversized:
            return .oversized(oversizedBytes.count)
        }
    }

    private func optionalData(at url: URL) throws -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return try Data(contentsOf: url)
    }

    private func assertJournalCopiesEqual(
        _ locations: ProfileHydrationTransactionLocations,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        do {
            let primary = try Data(contentsOf: locations.journalPrimaryURL)
            let backup = try Data(contentsOf: locations.journalBackupURL)
            XCTAssertEqual(primary, backup, file: file, line: line)
        } catch {
            XCTFail("Could not read journal copies: \(error)", file: file, line: line)
        }
    }

    private func temporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "PocketVector-ProfileHydration-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        return root
    }

    private func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}

private struct LockRecordingCloudReplicaCheckpointFileSystem:
    CloudReplicaCheckpointFileSystem
{
    private let base = FoundationCloudReplicaCheckpointFileSystem()
    let recorder: ScopedHydrationLockRecorder

    func createDirectory(at url: URL) throws {
        try base.createDirectory(at: url)
    }

    func itemStatus(at url: URL) throws -> CloudReplicaCheckpointFileItemStatus {
        try base.itemStatus(at: url)
    }

    func reconcileDurableItem(
        at url: URL
    ) throws -> CloudReplicaCheckpointFileItemStatus {
        try base.reconcileDurableItem(at: url)
    }

    func fileSize(at url: URL) throws -> Int {
        try base.fileSize(at: url)
    }

    func read(from url: URL) throws -> Data {
        try base.read(from: url)
    }

    func writeAtomically(_ data: Data, to url: URL) throws {
        try base.writeAtomically(data, to: url)
    }

    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        try base.moveItem(at: sourceURL, to: destinationURL)
    }

    func removeItem(at url: URL) throws {
        try base.removeItem(at: url)
    }

    func withExclusiveLock(at url: URL, perform: () throws -> Void) throws {
        try base.withExclusiveLock(at: url) {
            recorder.record(.checkpointEntered)
            defer { recorder.record(.checkpointExited) }
            try perform()
        }
    }
}

private struct LockRecordingProfileHydrationFileSystem:
    ProfileHydrationFileSystem
{
    private let base = FoundationProfileHydrationFileSystem()
    let recorder: ScopedHydrationLockRecorder

    func createDirectory(at url: URL) throws {
        try base.createDirectory(at: url)
    }

    func itemStatus(at url: URL) throws -> ProfileHydrationFileItemStatus {
        try base.itemStatus(at: url)
    }

    func fileSize(at url: URL) throws -> Int {
        try base.fileSize(at: url)
    }

    func read(from url: URL) throws -> Data {
        try base.read(from: url)
    }

    func writeAtomicallyDurably(_ data: Data, to url: URL) throws {
        try base.writeAtomicallyDurably(data, to: url)
    }

    func moveItemDurably(at sourceURL: URL, to destinationURL: URL) throws {
        try base.moveItemDurably(at: sourceURL, to: destinationURL)
    }

    func removeItemDurably(at url: URL) throws {
        try base.removeItemDurably(at: url)
    }

    func withExclusiveLock(at url: URL, perform: () throws -> Void) throws {
        try base.withExclusiveLock(at: url) {
            recorder.record(.profileEntered)
            defer { recorder.record(.profileExited) }
            try perform()
        }
    }
}

private final class FaultInjectingProfileHydrationFileSystem:
    ProfileHydrationFileSystem,
    @unchecked Sendable
{
    enum Failure: Equatable {
        case beforeWrite(String)
        case afterWrite(String)
        case beforeRead(String)
        case beforeStatus(String)
        case beforeRemove(String)
        case afterRemove(String)
        case lock
    }

    private let base = FoundationProfileHydrationFileSystem()
    private let stateLock = NSLock()
    private var nextFailure: Failure?
    private var pendingRemovalDurability: Set<String> = []

    func failNext(_ failure: Failure) {
        stateLock.lock()
        nextFailure = failure
        stateLock.unlock()
    }

    func hasPendingRemovalDurability(for lastPathComponent: String) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return pendingRemovalDurability.contains(lastPathComponent)
    }

    func createDirectory(at url: URL) throws {
        try base.createDirectory(at: url)
    }

    func itemStatus(at url: URL) throws -> ProfileHydrationFileItemStatus {
        if consume(.beforeStatus(url.lastPathComponent)) {
            throw ProfileHydrationFileSystemError.ioFailure
        }
        return try base.itemStatus(at: url)
    }

    func fileSize(at url: URL) throws -> Int {
        try base.fileSize(at: url)
    }

    func read(from url: URL) throws -> Data {
        if consume(.beforeRead(url.lastPathComponent)) {
            throw ProfileHydrationFileSystemError.ioFailure
        }
        return try base.read(from: url)
    }

    func writeAtomicallyDurably(_ data: Data, to url: URL) throws {
        if consume(.beforeWrite(url.lastPathComponent)) {
            throw ProfileHydrationFileSystemError.ioFailure
        }
        try base.writeAtomicallyDurably(data, to: url)
        if consume(.afterWrite(url.lastPathComponent)) {
            throw ProfileHydrationFileSystemError.atomicWriteOutcomeUnknown
        }
    }

    func moveItemDurably(at sourceURL: URL, to destinationURL: URL) throws {
        try base.moveItemDurably(at: sourceURL, to: destinationURL)
    }

    func removeItemDurably(at url: URL) throws {
        let lastPathComponent = url.lastPathComponent
        if consume(.beforeRemove(lastPathComponent)) {
            throw ProfileHydrationFileSystemError.ioFailure
        }
        let wasAlreadyMissing = try base.itemStatus(at: url) == .missing
        try base.removeItemDurably(at: url)
        if consume(.afterRemove(lastPathComponent)) {
            markPendingRemovalDurability(for: lastPathComponent)
            throw ProfileHydrationFileSystemError.ioFailure
        }
        if wasAlreadyMissing {
            clearPendingRemovalDurability(for: lastPathComponent)
        }
    }

    func withExclusiveLock(at url: URL, perform: () throws -> Void) throws {
        if consume(.lock) {
            throw ProfileHydrationFileSystemError.lockContended
        }
        try base.withExclusiveLock(at: url, perform: perform)
    }

    private func consume(_ candidate: Failure) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard nextFailure == candidate else { return false }
        nextFailure = nil
        return true
    }

    private func markPendingRemovalDurability(for lastPathComponent: String) {
        stateLock.lock()
        pendingRemovalDurability.insert(lastPathComponent)
        stateLock.unlock()
    }

    private func clearPendingRemovalDurability(for lastPathComponent: String) {
        stateLock.lock()
        pendingRemovalDurability.remove(lastPathComponent)
        stateLock.unlock()
    }
}

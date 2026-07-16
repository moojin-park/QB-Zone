import Foundation
import XCTest

@testable import PocketVector

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
        let journalBackup = try Data(
            contentsOf: store.locations.journalBackupURL
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
    }

    func testPreparedJournalIsImmutableAndDifferentTransactionCannotReplaceIt() throws {
        let fixture = try ProfileHydrationTestFixture()
        let root = try temporaryDirectory()
        defer { remove(root) }
        let store = makeStore(root: root)
        try seedSourceProfile(fixture, locations: store.locations)
        _ = try store.beginHydration(fixture.journal)
        let originalPrimary = try Data(contentsOf: store.locations.journalPrimaryURL)
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
        assertJournalCopiesEqual(store.locations)
    }

    func testMissingJournalCopyIsRepairedOnlyInsideStoreLock() throws {
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
        XCTAssertEqual(inspection.repairedJournalCopy, .primary)
        assertJournalCopiesEqual(store.locations)
    }

    func testCorruptJournalCopyIsQuarantinedThenRepairedFromValidPeer() throws {
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

        let inspection = try XCTUnwrap(
            store.inspectRecovery(expected: fixture.expectedBinding)
        )
        XCTAssertEqual(inspection.repairedJournalCopy, .backup)
        XCTAssertEqual(try store.quarantinedEvidenceURLs().count, 1)
        assertJournalCopiesEqual(store.locations)
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
        XCTAssertEqual(inspection.repairedJournalCopy, .backup)
        XCTAssertEqual(try store.quarantinedEvidenceURLs().count, 1)
        assertJournalCopiesEqual(store.locations)
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
                .inspectRecovery(expected: fixture.expectedBinding)
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: baseStore.locations.journalBackupURL.path))
        XCTAssertEqual(try baseStore.quarantinedEvidenceURLs().count, 1)

        let recovered = try XCTUnwrap(
            baseStore.inspectRecovery(expected: fixture.expectedBinding)
        )
        XCTAssertEqual(recovered.repairedJournalCopy, .backup)
        assertJournalCopiesEqual(baseStore.locations)
    }

    func testCrashAfterCandidateBackupLeavesClassifiedPartialInstall() throws {
        let fixture = try ProfileHydrationTestFixture()
        let root = try temporaryDirectory()
        defer { remove(root) }
        let fault = FaultInjectingProfileHydrationFileSystem()
        let store = makeStore(root: root, fileSystem: fault)
        try seedSourceProfile(fixture, locations: store.locations)
        _ = try store.beginHydration(fixture.journal)
        fault.failNext(.beforeWrite("player-profile.json"))

        XCTAssertThrowsError(
            try store.installCandidate(
                transactionID: fixture.transactionID,
                expected: fixture.expectedBinding
            )
        )
        let inspection = try XCTUnwrap(
            makeStore(root: root).inspectRecovery(expected: fixture.expectedBinding)
        )
        XCTAssertEqual(inspection.primaryProfileState, .source)
        XCTAssertEqual(inspection.backupProfileState, .candidate)
        XCTAssertEqual(inspection.installationState, .partial)

        let recovered = try makeStore(root: root).installCandidate(
            transactionID: fixture.transactionID,
            expected: fixture.expectedBinding
        )
        XCTAssertFalse(recovered.wasAlreadyInstalled)
        XCTAssertEqual(recovered.inspection.installationState, .candidate)
    }

    func testCrashAfterCandidatePrimaryIsRecognizedAsAlreadyInstalled() throws {
        let fixture = try ProfileHydrationTestFixture()
        let root = try temporaryDirectory()
        defer { remove(root) }
        let fault = FaultInjectingProfileHydrationFileSystem()
        let store = makeStore(root: root, fileSystem: fault)
        try seedSourceProfile(fixture, locations: store.locations)
        _ = try store.beginHydration(fixture.journal)
        fault.failNext(.afterWrite("player-profile.json"))

        XCTAssertThrowsError(
            try store.installCandidate(
                transactionID: fixture.transactionID,
                expected: fixture.expectedBinding
            )
        )
        let recovered = try makeStore(root: root).installCandidate(
            transactionID: fixture.transactionID,
            expected: fixture.expectedBinding
        )
        XCTAssertTrue(recovered.wasAlreadyInstalled)
        XCTAssertEqual(recovered.inspection.installationState, .candidate)
    }

    func testCandidateInstallationIsDeterministicallyIdempotent() throws {
        let fixture = try ProfileHydrationTestFixture()
        let root = try temporaryDirectory()
        defer { remove(root) }
        let store = makeStore(root: root)
        try seedSourceProfile(fixture, locations: store.locations)
        _ = try store.beginHydration(fixture.journal)

        let first = try store.installCandidate(
            transactionID: fixture.transactionID,
            expected: fixture.expectedBinding
        )
        let second = try store.installCandidate(
            transactionID: fixture.transactionID,
            expected: fixture.expectedBinding
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

    func testStaleButValidProfileBytesFailWithoutBeingOverwritten() throws {
        let fixture = try ProfileHydrationTestFixture()
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

        XCTAssertThrowsError(
            try store.installCandidate(
                transactionID: fixture.transactionID,
                expected: fixture.expectedBinding
            )
        ) { error in
            XCTAssertEqual(
                error as? ProfileHydrationTransactionStoreError,
                .unexpectedProfileBytes
            )
        }
        XCTAssertEqual(try Data(contentsOf: store.locations.profilePrimaryURL), staleBytes)
        XCTAssertEqual(try Data(contentsOf: store.locations.profileBackupURL), staleBytes)
    }

    func testWrongAccountScopeEpochAndProfileFailBeforeAnyProfileWrite() throws {
        let fixture = try ProfileHydrationTestFixture()
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
            XCTAssertThrowsError(
                try store.installCandidate(
                    transactionID: fixture.transactionID,
                    expected: wrong
                )
            ) { error in
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

    func testMissingBothProfileCopiesAreInspectedWithoutDefaultSynthesis() throws {
        let fixture = try ProfileHydrationTestFixture()
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
        XCTAssertThrowsError(
            try store.installCandidate(
                transactionID: fixture.transactionID,
                expected: fixture.expectedBinding
            )
        ) { error in
            XCTAssertEqual(
                error as? ProfileHydrationTransactionStoreError,
                .profileCopiesMissing
            )
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.locations.profilePrimaryURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.locations.profileBackupURL.path))
    }

    func testOneExactSourceProfileCopyIsEnoughForJournalBoundRecovery() throws {
        let fixture = try ProfileHydrationTestFixture()
        let root = try temporaryDirectory()
        defer { remove(root) }
        let store = makeStore(root: root)
        try seedSourceProfile(fixture, locations: store.locations)
        _ = try store.beginHydration(fixture.journal)
        try FoundationProfileHydrationFileSystem().removeItemDurably(
            at: store.locations.profileBackupURL
        )

        let result = try store.installCandidate(
            transactionID: fixture.transactionID,
            expected: fixture.expectedBinding
        )
        XCTAssertEqual(result.inspection.installationState, .candidate)
        XCTAssertEqual(
            try Data(contentsOf: store.locations.profileBackupURL),
            fixture.candidateEnvelope
        )
    }

    func testCrashAfterRemovingOneJournalCopyRepairsThenFinishesCleanup() throws {
        let fixture = try ProfileHydrationTestFixture()
        let root = try temporaryDirectory()
        defer { remove(root) }
        let fault = FaultInjectingProfileHydrationFileSystem()
        let store = makeStore(root: root, fileSystem: fault)
        try seedSourceProfile(fixture, locations: store.locations)
        _ = try store.beginHydration(fixture.journal)
        _ = try store.installCandidate(
            transactionID: fixture.transactionID,
            expected: fixture.expectedBinding
        )
        fault.failNext(.beforeRemove("profile-hydration-journal.json"))

        XCTAssertThrowsError(
            try store.removeJournalAfterCheckpointConfirmation(
                transactionID: fixture.transactionID,
                expected: fixture.expectedBinding,
                committedCheckpointIdentity: fixture.journal.targetCheckpointIdentity
            )
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.locations.journalPrimaryURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.locations.journalBackupURL.path))

        XCTAssertTrue(
            try makeStore(root: root).removeJournalAfterCheckpointConfirmation(
                transactionID: fixture.transactionID,
                expected: fixture.expectedBinding,
                committedCheckpointIdentity: fixture.journal.targetCheckpointIdentity
            )
        )
        XCTAssertNil(
            try makeStore(root: root).inspectRecovery(expected: fixture.expectedBinding)
        )
    }

    func testWrongCheckpointConfirmationCannotRemoveJournal() throws {
        let fixture = try ProfileHydrationTestFixture()
        let root = try temporaryDirectory()
        defer { remove(root) }
        let store = makeStore(root: root)
        try seedSourceProfile(fixture, locations: store.locations)
        _ = try store.beginHydration(fixture.journal)
        _ = try store.installCandidate(
            transactionID: fixture.transactionID,
            expected: fixture.expectedBinding
        )
        let otherCheckpoint = try fixture.checkpoint(generation: 1, cursorByte: 9)

        XCTAssertThrowsError(
            try store.removeJournalAfterCheckpointConfirmation(
                transactionID: fixture.transactionID,
                expected: fixture.expectedBinding,
                committedCheckpointIdentity: ProfileHydrationCheckpointIdentityV1(
                    checkpoint: otherCheckpoint
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? ProfileHydrationTransactionStoreError,
                .checkpointConfirmationMismatch
            )
        }
        assertJournalCopiesEqual(store.locations)
    }

    func testBothCorruptJournalsLeaveBoundedEvidenceAndFailClosedOnRelaunch() throws {
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
            try store.inspectRecovery(expected: fixture.expectedBinding)
        ) { error in
            XCTAssertEqual(
                error as? ProfileHydrationTransactionStoreError,
                .noValidJournalCopy
            )
        }
        XCTAssertEqual(try store.quarantinedEvidenceURLs().count, 2)
        XCTAssertThrowsError(
            try store.inspectRecovery(expected: fixture.expectedBinding)
        ) { error in
            XCTAssertEqual(
                error as? ProfileHydrationTransactionStoreError,
                .unrecoverableJournalEvidence
            )
        }
    }

    func testQuarantineByteBoundNeverOverwritesOrMovesOversizedEvidence() throws {
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
                .quarantineCapacityExceeded
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
            try store.inspectRecovery(expected: fixture.expectedBinding)
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

    func failNext(_ failure: Failure) {
        stateLock.lock()
        nextFailure = failure
        stateLock.unlock()
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
        if consume(.beforeRemove(url.lastPathComponent)) {
            throw ProfileHydrationFileSystemError.ioFailure
        }
        try base.removeItemDurably(at: url)
        if consume(.afterRemove(url.lastPathComponent)) {
            throw ProfileHydrationFileSystemError.ioFailure
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
}

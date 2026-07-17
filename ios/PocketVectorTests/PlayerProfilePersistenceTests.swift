import Foundation
import XCTest

@testable import PocketVector

final class PlayerProfilePersistenceTests: XCTestCase, @unchecked Sendable {
    private let baseDate = Date(timeIntervalSince1970: 1_750_000_000)

    func testProfileStampDeviceIDRuleIsVersionedAndSharedWithCloudStamps() throws {
        XCTAssertEqual(
            ProfileStampDeviceIDRuleV1.fingerprintMaterial,
            [
                "pocket-vector-profile-stamp-device-id-rule-v1",
                "lengthUnit", "utf8-byte",
                "minimumByteCount", "1",
                "maximumByteCount", "64",
                "firstByteClass", "ascii-alphanumeric",
                "remainingByteClass", "ascii-alphanumeric-or-bytes-45-46-95",
            ]
        )

        let valid = [
            "a",
            "9",
            "device-A_9.z",
            String(repeating: "a", count: 64),
        ]
        for deviceID in valid {
            XCTAssertTrue(ProfileStampDeviceIDRuleV1.isValid(deviceID))
            XCTAssertNoThrow(
                try CloudProfileMergeStampV1(
                    logicalCounter: 0,
                    deviceID: deviceID,
                    modifiedAt: baseDate
                )
            )
        }

        let invalid = [
            "",
            "-device",
            "device id",
            "device/id",
            "dévice",
            String(repeating: "a", count: 65),
        ]
        for deviceID in invalid {
            XCTAssertFalse(ProfileStampDeviceIDRuleV1.isValid(deviceID))
            XCTAssertThrowsError(
                try CloudProfileMergeStampV1(
                    logicalCounter: 0,
                    deviceID: deviceID,
                    modifiedAt: baseDate
                )
            ) {
                XCTAssertEqual(
                    $0 as? CloudProfileMergeStampError,
                    .invalidDeviceID(deviceID)
                )
            }
        }
    }

    func testValidatorRejectsInvalidLocalStampDeviceIDs() throws {
        var invalidSettings = PlayerProfileFactory.makeDefault(
            accountIdentity: .local,
            deviceID: "valid-device",
            createdAt: baseDate
        )
        invalidSettings.player.settings.deviceID = "invalid device"
        XCTAssertThrowsError(try PlayerProfileValidator.validate(invalidSettings)) {
            XCTAssertEqual($0 as? ProfileValidationError, .invalidSettingsStamp)
        }

        var invalidSelection = PlayerProfileFactory.makeDefault(
            accountIdentity: .local,
            deviceID: "valid-device",
            createdAt: baseDate
        )
        invalidSelection.player.selection.deviceID = "-invalid-device"
        XCTAssertThrowsError(try PlayerProfileValidator.validate(invalidSelection)) {
            XCTAssertEqual($0 as? ProfileValidationError, .invalidSelectionStamp)
        }
    }

    func testFreshProfileStoreRejectsInvalidDeviceIDWithoutWriting() throws {
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        var invalid = PlayerProfileFactory.makeDefault(
            accountIdentity: .local,
            deviceID: "valid-device",
            createdAt: baseDate
        )
        invalid.player.settings.deviceID = "invalid fresh device"
        invalid.player.selection.deviceID = "invalid fresh device"
        let store = AtomicProfileFileStore(directoryURL: directory)

        XCTAssertThrowsError(
            try store.loadOrCreate(
                defaultDocument: invalid,
                at: baseDate,
                catalog: .approved
            )
        ) {
            XCTAssertEqual($0 as? ProfileValidationError, .invalidSettingsStamp)
        }

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: store.locations.primaryURL.path)
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: store.locations.backupURL.path)
        )
    }

    func testInvalidV3AndLegacyStampDeviceIDsDecodeWithoutTrapThenFailValidation()
        throws
    {
        let migrator = PlayerProfileMigrator()
        let document = PlayerProfileFactory.makeDefault(
            accountIdentity: .local,
            deviceID: "valid-device",
            createdAt: baseDate
        )
        let current = try migrator.encode(document, savedAt: baseDate)

        let invalidV3 = try envelopeData(
            from: current,
            schemaVersion: PlayerProfileEnvelopeV3.schemaVersion,
            deviceIDOverrides: ["settings": "invalid v3 device"]
        )
        let decodedV3 = try migrator.decode(invalidV3)
        XCTAssertThrowsError(try PlayerProfileValidator.validate(decodedV3)) {
            XCTAssertEqual($0 as? ProfileValidationError, .invalidSettingsStamp)
        }

        for schemaVersion in [
            PlayerProfileEnvelopeV1.schemaVersion,
            PlayerProfileEnvelopeV2.schemaVersion,
        ] {
            let legacy = try envelopeData(
                from: current,
                schemaVersion: schemaVersion,
                removingLogicalCounterFrom: ["settings", "selection"],
                deviceIDOverrides: ["selection": "invalid legacy device"],
                removeRewardedRunObservations: schemaVersion
                    == PlayerProfileEnvelopeV1.schemaVersion
            )
            let migrated = try migrator.decode(legacy)
            XCTAssertThrowsError(try PlayerProfileValidator.validate(migrated)) {
                XCTAssertEqual($0 as? ProfileValidationError, .invalidSelectionStamp)
            }
        }
    }

    func testV3CanonicalFixtureIsExactAndIndependentOfCollectionInsertionOrder() throws {
        let migrator = PlayerProfileMigrator()
        let fixture = makeCanonicalFixtureDocument(reverseCollections: false)
        let reordered = makeCanonicalFixtureDocument(reverseCollections: true)

        XCTAssertEqual(fixture, reordered)
        let encoded = try migrator.encode(fixture, savedAt: baseDate.addingTimeInterval(3))
        let reorderedEncoded = try migrator.encode(
            reordered,
            savedAt: baseDate.addingTimeInterval(3)
        )

        XCTAssertEqual(encoded, reorderedEncoded)
        XCTAssertEqual(
            encoded,
            try PlayerProfileCanonicalEnvelopeEncoderV1.encode(
                PlayerProfileEnvelopeV3(
                    document: fixture,
                    savedAt: baseDate.addingTimeInterval(3)
                )
            )
        )
        XCTAssertEqual(try migrator.decode(encoded), fixture)
        XCTAssertEqual(
            try migrator.encode(try migrator.decode(encoded), savedAt: baseDate.addingTimeInterval(3)),
            encoded
        )

        let actual = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        let expected = [
            #"{"document":{"accountIdentity":"fixture-account","economyRevision":4,"pendingLedgerEntryIDs":[],"player":{"achievementProgress":["fixture-achievement-a",{"id":"fixture-achievement-a","percentComplete":25},"fixture-achievement-b",{"id":"fixture-achievement-b","percentComplete":75}],"career":{"attempts":0,"bonusTouchdowns":0,"completedRuns":0,"completions":0,"highestScore":0,"incompletions":0,"#,
            #""interceptions":0,"rewardEligibleRuns":0,"totalScore":0,"touchdowns":0},"completedRuns":[],"createdAt":1750000000000,"inventory":{"ownedFootballIDs":["fixture-football-a","fixture-football-b"],"ownedJerseyIDs":["fixture-jersey-a","fixture-jersey-b"],"ownedTeamIDs":["fixture-team-a","fixture-team-b"]},"ledger":[],"#,
            #""pendingGameCenter":{"pendingAchievementPercents":["fixture-achievement-a",10,"fixture-achievement-b",20],"pendingHighScore":12345},"profileID":"12345678-1234-5678-9ABC-DEF012345678","revision":7,"rewardedAdState":{"accountedRunIDs":[{"rawValue":"00000000-0000-0000-0000-000000000990"},{"rawValue":"00000000-0000-0000-0000-000000000991"}],"cycle":2,"validRunsSinceReward":2},"#,
            #""selection":{"deviceID":"fixture-selection-device","logicalCounter":11,"modifiedAt":1750000002000,"value":{"selectedFootballID":"fixture-football-a","selectedJerseyByTeam":["fixture-team-a","fixture-jersey-a","fixture-team-b","fixture-jersey-b"],"selectedTeamID":"fixture-team-a"}},"settings":{"deviceID":"fixture-settings-device","logicalCounter":9,"modifiedAt":1750000001000,"value":{"isMuted":true,"musicVolume":0.25,"reducedMotion":false,"sfxVolume":0.75,"tutorialCompleted":true}}},"#,
            #""rewardedRunObservations":[{"rawValue":"00000000-0000-0000-0000-000000000990"},{"disposition":"candidate","observedCycle":2},{"rawValue":"00000000-0000-0000-0000-000000000991"},{"disposition":"ignoredWhileOfferPending","observedCycle":3}],"settlementReceipts":[]},"format":"com.pocketvector.player-profile","savedAt":1750000003000,"schemaVersion":3}"#,
        ].joined()
        XCTAssertEqual(actual, expected)
    }

    func testV3CanonicalBytesNormalizeEveryNonemptyTypedCollection() throws {
        let migrator = PlayerProfileMigrator()
        let forward = try makeCanonicalCollectionFixtureDocument(
            reverseCollections: false
        )
        let reversed = try makeCanonicalCollectionFixtureDocument(
            reverseCollections: true
        )

        XCTAssertEqual(forward, reversed)
        XCTAssertNoThrow(try PlayerProfileValidator.validate(forward))
        XCTAssertGreaterThan(forward.player.completedRuns.count, 1)
        XCTAssertGreaterThan(forward.player.ledger.count, 1)
        XCTAssertGreaterThan(forward.settlementReceipts.count, 1)
        XCTAssertGreaterThan(forward.pendingLedgerEntryIDs.count, 1)
        XCTAssertTrue(
            forward.player.completedRuns.values.allSatisfy {
                !$0.run.completedLaneIDs.isEmpty
            }
        )

        let savedAt = baseDate.addingTimeInterval(100)
        let forwardBytes = try migrator.encode(forward, savedAt: savedAt)
        let reversedBytes = try migrator.encode(reversed, savedAt: savedAt)
        XCTAssertEqual(forwardBytes, reversedBytes)
        XCTAssertEqual(try migrator.decode(forwardBytes), forward)
        XCTAssertEqual(
            try migrator.encode(
                try migrator.decode(forwardBytes),
                savedAt: savedAt
            ),
            forwardBytes
        )

        let encodedText = try XCTUnwrap(String(data: forwardBytes, encoding: .utf8))
        for key in [
            "completedRuns",
            "ledger",
            "settlementReceipts",
            "completedLaneIDs",
            "pendingLedgerEntryIDs",
        ] {
            XCTAssertFalse(encodedText.contains("\"\(key)\":[]"))
        }
    }

    func testLegacyV1AndV2MigrateMissingFieldCountersToPlayerRevisionExactlyOnce() throws {
        let migrator = PlayerProfileMigrator()
        var original = PlayerProfileFactory.makeDefault(
            accountIdentity: .local,
            deviceID: "legacy-counter-device",
            createdAt: baseDate
        )
        original.player.revision = 7
        original.player.settings.logicalCounter = 2
        original.player.selection.logicalCounter = 4
        let current = try migrator.encode(original, savedAt: baseDate)

        for schemaVersion in [
            PlayerProfileEnvelopeV1.schemaVersion,
            PlayerProfileEnvelopeV2.schemaVersion,
        ] {
            let legacy = try envelopeData(
                from: current,
                schemaVersion: schemaVersion,
                removingLogicalCounterFrom: ["settings", "selection"],
                removeRewardedRunObservations: schemaVersion
                    == PlayerProfileEnvelopeV1.schemaVersion
            )
            let migrated = try migrator.decode(legacy)

            XCTAssertEqual(migrated.player.settings.logicalCounter, 7)
            XCTAssertEqual(migrated.player.selection.logicalCounter, 7)
            XCTAssertEqual(migrated.player.settings.deviceID, "legacy-counter-device")
            XCTAssertEqual(migrated.player.selection.deviceID, "legacy-counter-device")
            XCTAssertNoThrow(try PlayerProfileValidator.validate(migrated))

            let v3 = try migrator.encode(migrated, savedAt: baseDate)
            let decodedAgain = try migrator.decode(v3)
            XCTAssertEqual(decodedAgain.player.settings.logicalCounter, 7)
            XCTAssertEqual(decodedAgain.player.selection.logicalCounter, 7)
        }
    }

    func testDeclaredV3RequiresValidLogicalCounters() throws {
        let migrator = PlayerProfileMigrator()
        let document = PlayerProfileFactory.makeDefault(
            accountIdentity: .local,
            deviceID: "strict-v3-device",
            createdAt: baseDate
        )
        let encoded = try migrator.encode(document, savedAt: baseDate)

        for field in ["settings", "selection"] {
            let missing = try envelopeData(
                from: encoded,
                schemaVersion: PlayerProfileEnvelopeV3.schemaVersion,
                removingLogicalCounterFrom: [field]
            )
            XCTAssertThrowsError(try migrator.decode(missing)) {
                XCTAssertEqual($0 as? ProfileMigrationError, .malformedEnvelope)
            }
        }

        let negative = try envelopeData(
            from: encoded,
            schemaVersion: PlayerProfileEnvelopeV3.schemaVersion,
            logicalCounterOverrides: ["settings": -1]
        )
        XCTAssertThrowsError(try migrator.decode(negative)) {
            XCTAssertEqual($0 as? ProfileMigrationError, .malformedEnvelope)
        }

        let encodedString = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        let overflowString = encodedString.replacingOccurrences(
            of: #""logicalCounter":0"#,
            with: #""logicalCounter":18446744073709551616"#
        )
        XCTAssertNotEqual(overflowString, encodedString)
        XCTAssertThrowsError(try migrator.decode(Data(overflowString.utf8))) {
            XCTAssertEqual($0 as? ProfileMigrationError, .malformedEnvelope)
        }
    }

    func testValidatorRejectsNonFiniteStampDatesAndAllowsIndependentFieldClocks() throws {
        var invalidSettings = PlayerProfileFactory.makeDefault(
            accountIdentity: .local,
            deviceID: "stamp-validation-device",
            createdAt: baseDate
        )
        invalidSettings.player.settings.modifiedAt = Date(timeIntervalSince1970: .nan)
        XCTAssertThrowsError(try PlayerProfileValidator.validate(invalidSettings)) {
            XCTAssertEqual($0 as? ProfileValidationError, .invalidSettingsStamp)
        }

        var invalidSelection = PlayerProfileFactory.makeDefault(
            accountIdentity: .local,
            deviceID: "stamp-validation-device",
            createdAt: baseDate
        )
        invalidSelection.player.selection.modifiedAt = Date(timeIntervalSince1970: .infinity)
        XCTAssertThrowsError(try PlayerProfileValidator.validate(invalidSelection)) {
            XCTAssertEqual($0 as? ProfileValidationError, .invalidSelectionStamp)
        }

        var remoteClock = PlayerProfileFactory.makeDefault(
            accountIdentity: .local,
            deviceID: "remote-stamp-device",
            createdAt: baseDate
        )
        remoteClock.player.settings.logicalCounter = 100
        remoteClock.player.selection.logicalCounter = 200
        XCTAssertNoThrow(try PlayerProfileValidator.validate(remoteClock))
    }

    func testLegacyAndNoncanonicalLoadsDurablyRewriteExactCanonicalV3PreservingSavedAt()
        throws
    {
        let migrator = PlayerProfileMigrator()
        let savedAt = baseDate.addingTimeInterval(123)
        var document = PlayerProfileFactory.makeDefault(
            profileID: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            accountIdentity: .local,
            deviceID: "canonical-rewrite-device",
            createdAt: baseDate
        )
        document.player.revision = 7
        document.economyRevision = 7
        let canonical = try migrator.encode(document, savedAt: savedAt)
        let object = try JSONSerialization.jsonObject(with: canonical)
        let noncanonicalV3 = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        let fixtures: [(String, Data)] = [
            (
                "v1",
                try envelopeData(
                    from: canonical,
                    schemaVersion: PlayerProfileEnvelopeV1.schemaVersion,
                    removingLogicalCounterFrom: ["settings", "selection"],
                    removeRewardedRunObservations: true
                )
            ),
            (
                "v2",
                try envelopeData(
                    from: canonical,
                    schemaVersion: PlayerProfileEnvelopeV2.schemaVersion,
                    removingLogicalCounterFrom: ["settings", "selection"]
                )
            ),
            ("noncanonical-v3", noncanonicalV3),
        ]

        for (name, sourceBytes) in fixtures {
            let directory = makeTemporaryDirectory().appendingPathComponent(
                name,
                isDirectory: true
            )
            defer { removeTemporaryDirectory(directory) }
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let locations = ProfileStorageLocations(directoryURL: directory)
            try sourceBytes.write(to: locations.primaryURL, options: .atomic)
            try sourceBytes.write(to: locations.backupURL, options: .atomic)
            let store = AtomicProfileFileStore(directoryURL: directory)

            let loaded = try store.loadOrCreate(
                defaultDocument: PlayerProfileFactory.makeDefault(
                    accountIdentity: .local,
                    deviceID: "unused-default-device",
                    createdAt: baseDate.addingTimeInterval(999)
                ),
                at: baseDate.addingTimeInterval(999),
                catalog: .approved
            )
            let primary = try Data(contentsOf: locations.primaryURL)
            let backup = try Data(contentsOf: locations.backupURL)

            XCTAssertEqual(loaded.report.source, .primary, name)
            XCTAssertEqual(loaded.artifact.savedAt, savedAt, name)
            XCTAssertEqual(primary, loaded.artifact.exactBytes, name)
            XCTAssertEqual(backup, loaded.artifact.exactBytes, name)
            XCTAssertNotEqual(sourceBytes, loaded.artifact.exactBytes, name)
            XCTAssertEqual(
                loaded.artifact.digest,
                .envelopeBytes(loaded.artifact.exactBytes),
                name
            )
            XCTAssertEqual(
                try migrator.decodeArtifact(primary).sourceSchemaVersion,
                PlayerProfileEnvelopeV3.schemaVersion,
                name
            )
            XCTAssertEqual(
                try migrator.encode(loaded.document, savedAt: savedAt),
                primary,
                name
            )
        }
    }

    func testHydrationSourceUsesExactCanonicalBytesCurrentlyOnDisk() async throws {
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let repository = makeRepository(directory: directory)
        let loaded = try await repository.load(
            at: baseDate,
            newProfileID: UUID(uuidString: "11111111-2222-3333-4444-666666666666")!
        )

        let source = try await repository.hydrationSource(session: loaded.session)
        let primary = try Data(
            contentsOf: ProfileStorageLocations(directoryURL: directory).primaryURL
        )

        XCTAssertEqual(source.activeSession, loaded.session)
        XCTAssertEqual(source.exactEnvelopeBytes, primary)
        let decoded = try PlayerProfileMigrator().decodeArtifact(
            source.exactEnvelopeBytes
        )
        XCTAssertEqual(decoded.sourceSchemaVersion, PlayerProfileEnvelopeV3.schemaVersion)
        XCTAssertEqual(decoded.savedAt, baseDate)
        XCTAssertEqual(decoded.document.player.profileID, loaded.player.profileID)
    }

    func testCommittedHydrationSeamInstallsCleansAndAdoptsWithoutRotatingSession()
        async throws
    {
        let fixture = try ProfileHydrationTestFixture()
        let directory = makeTemporaryDirectory()
        let checkpointDirectory = makeTemporaryDirectory()
        defer {
            removeTemporaryDirectory(directory)
            removeTemporaryDirectory(checkpointDirectory)
        }
        try writeExactProfileCopies(
            primary: fixture.sourceEnvelope,
            backup: fixture.sourceEnvelope,
            to: directory
        )
        let repository = makeHydrationAdoptionRepository(
            directory: directory,
            fixture: fixture
        )
        let loaded = try await repository.load(at: fixture.date)
        let loadReport = await repository.lastLoadReport
        XCTAssertEqual(loaded.session, fixture.sourceSession)

        let transactionStore = ProfileHydrationFileTransactionStore(
            profileDirectoryURL: directory
        )
        _ = try transactionStore.beginHydration(fixture.journal)
        let accountAuthority = CloudAccountGenerationAuthority()
        let checkpointStore = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: checkpointDirectory,
            accountGenerationAuthority: accountAuthority
        )
        try await checkpointStore.activate(
            replicaEpoch: fixture.replicaEpoch,
            configurationScopeFingerprint: fixture.scope,
            for: fixture.cloudAccountID
        )
        try await checkpointStore._testOnlySaveRawCheckpoint(
            fixture.targetCheckpoint,
            at: fixture.date
        )
        let generation = try await accountAuthority.activate(
            accountID: fixture.cloudAccountID,
            configurationScopeFingerprint: fixture.scope,
            replicaEpoch: fixture.replicaEpoch
        )
        let transactionID = fixture.transactionID
        let expectedBinding = fixture.expectedBinding
        let checkpointDate = fixture.date
        _ = try await accountAuthority.withCurrentGeneration(generation) {
            accountLease in
            try await checkpointStore.withCurrentCheckpointLease(
                generationLease: accountLease,
                at: checkpointDate
            ) { lease in
                try transactionStore.installCandidate(
                    transactionID: transactionID,
                    expected: expectedBinding,
                    checkpointLease: lease
                )
            }
        }

        do {
            _ = try await repository.adoptCommittedHydration(
                fixture.journal,
                session: loaded.session
            )
            XCTFail("The durable journal barrier must block early adoption")
        } catch {
            XCTAssertEqual(
                error as? AtomicProfileFileStoreError,
                .hydrationRecoveryRequired
            )
        }

        let removedJournal = try await accountAuthority.withCurrentGeneration(
            generation
        ) { accountLease in
            try await checkpointStore.withCurrentCheckpointLease(
                generationLease: accountLease,
                at: checkpointDate
            ) { lease in
                try transactionStore.removeJournalAfterCheckpointConfirmation(
                    transactionID: transactionID,
                    expected: expectedBinding,
                    checkpointLease: lease
                )
            }
        }
        XCTAssertTrue(removedJournal)
        let adopted = try await repository.adoptCommittedHydration(
            fixture.journal,
            session: loaded.session
        )
        let expected = try PlayerProfileProjection.snapshot(
            for: fixture.candidateDocument,
            session: loaded.session
        )

        XCTAssertEqual(adopted, expected)
        XCTAssertEqual(adopted.session, loaded.session)
        let adoptedSnapshot = try await repository.snapshot()
        let adoptedLoadReport = await repository.lastLoadReport
        XCTAssertEqual(adoptedSnapshot, expected)
        XCTAssertEqual(adoptedLoadReport, loadReport)
        let adoptedSource = try await repository.hydrationSource(
            session: loaded.session
        )
        XCTAssertEqual(adoptedSource.exactEnvelopeBytes, fixture.candidateEnvelope)
        XCTAssertEqual(
            try Data(contentsOf: transactionStore.locations.profilePrimaryURL),
            fixture.candidateEnvelope
        )
        XCTAssertEqual(
            try Data(contentsOf: transactionStore.locations.profileBackupURL),
            fixture.candidateEnvelope
        )
    }

    func testHydrationAdoptionRequiresCandidateInBothCopiesAcrossFullStateMatrix()
        async throws
    {
        let fixture = try ProfileHydrationTestFixture()
        let maximumEnvelopeBytes = max(
            fixture.sourceEnvelope.count,
            fixture.candidateEnvelope.count
        ) + 64
        let limits = profileLimits(maximumEnvelopeBytes: maximumEnvelopeBytes)
        let unexpected = Data("not-a-profile-envelope".utf8)
        let oversized = Data(
            repeating: 0x7f,
            count: maximumEnvelopeBytes + 1
        )
        let states: [(
            name: String,
            data: Data?,
            state: ProfileHydrationProfileCopyState
        )] = [
            ("source", fixture.sourceEnvelope, .source),
            ("candidate", fixture.candidateEnvelope, .candidate),
            ("missing", nil, .missing),
            ("unexpected", unexpected, .unexpected(.envelopeBytes(unexpected))),
            ("oversized", oversized, .oversized(oversized.count)),
        ]

        for primary in states {
            for backup in states {
                let name = "\(primary.name)/\(backup.name)"
                let directory = makeTemporaryDirectory()
                defer { removeTemporaryDirectory(directory) }
                try writeExactProfileCopies(
                    primary: fixture.sourceEnvelope,
                    backup: fixture.sourceEnvelope,
                    to: directory
                )
                let repository = makeHydrationAdoptionRepository(
                    directory: directory,
                    fixture: fixture,
                    limits: limits
                )
                let loaded = try await repository.load(at: fixture.date)
                try writeExactProfileCopies(
                    primary: primary.data,
                    backup: backup.data,
                    to: directory
                )
                let locations = ProfileStorageLocations(directoryURL: directory)
                let primaryBefore = try optionalProfileData(at: locations.primaryURL)
                let backupBefore = try optionalProfileData(at: locations.backupURL)

                if primary.state == .candidate, backup.state == .candidate {
                    let adopted = try await repository.adoptCommittedHydration(
                        fixture.journal,
                        session: loaded.session
                    )
                    XCTAssertEqual(
                        adopted.player.revision,
                        fixture.candidateDocument.player.revision,
                        name
                    )
                    XCTAssertEqual(
                        adopted.economyRevision,
                        fixture.candidateDocument.economyRevision,
                        name
                    )
                } else {
                    do {
                        _ = try await repository.adoptCommittedHydration(
                            fixture.journal,
                            session: loaded.session
                        )
                        XCTFail("Only candidate/candidate may be adopted: \(name)")
                    } catch {
                        XCTAssertEqual(
                            error as? AtomicProfileFileStoreError,
                            .hydrationCandidateNotExactlyInstalled(
                                primary: primary.state,
                                backup: backup.state
                            ),
                            name
                        )
                    }
                    let unchangedSnapshot = try await repository.snapshot()
                    XCTAssertEqual(unchangedSnapshot, loaded, name)
                }

                XCTAssertEqual(
                    try optionalProfileData(at: locations.primaryURL),
                    primaryBefore,
                    name
                )
                XCTAssertEqual(
                    try optionalProfileData(at: locations.backupURL),
                    backupBefore,
                    name
                )
            }
        }
    }

    func testHydrationAdoptionRejectsEveryDurableRecoveryBarrierWithoutMutation()
        async throws
    {
        let fixture = try ProfileHydrationTestFixture()
        let barrierKinds = [
            "journal-primary",
            "journal-backup",
            "quarantine-first",
            "quarantine-last",
        ]

        for barrierKind in barrierKinds {
            let directory = makeTemporaryDirectory()
            defer { removeTemporaryDirectory(directory) }
            try writeExactProfileCopies(
                primary: fixture.sourceEnvelope,
                backup: fixture.sourceEnvelope,
                to: directory
            )
            let repository = makeHydrationAdoptionRepository(
                directory: directory,
                fixture: fixture
            )
            let loaded = try await repository.load(at: fixture.date)
            try writeExactProfileCopies(
                primary: fixture.candidateEnvelope,
                backup: fixture.candidateEnvelope,
                to: directory
            )
            let transactionLocations = ProfileHydrationTransactionLocations(
                profileDirectoryURL: directory
            )
            let evidenceURL: URL
            switch barrierKind {
            case "journal-primary":
                evidenceURL = transactionLocations.journalPrimaryURL
            case "journal-backup":
                evidenceURL = transactionLocations.journalBackupURL
            case "quarantine-first":
                evidenceURL = transactionLocations.quarantineSlotURL(0)
            default:
                evidenceURL = transactionLocations.quarantineSlotURL(
                    ProfileHydrationLimits.production.maximumQuarantineFiles - 1
                )
            }
            try FileManager.default.createDirectory(
                at: evidenceURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let evidence = Data("durable-recovery-evidence".utf8)
            try evidence.write(to: evidenceURL, options: .atomic)

            do {
                _ = try await repository.adoptCommittedHydration(
                    fixture.journal,
                    session: loaded.session
                )
                XCTFail("Recovery evidence must block adoption: \(barrierKind)")
            } catch {
                XCTAssertEqual(
                    error as? AtomicProfileFileStoreError,
                    .hydrationRecoveryRequired,
                    barrierKind
                )
            }
            XCTAssertEqual(try Data(contentsOf: evidenceURL), evidence, barrierKind)
            let locations = ProfileStorageLocations(directoryURL: directory)
            XCTAssertEqual(
                try Data(contentsOf: locations.primaryURL),
                fixture.candidateEnvelope,
                barrierKind
            )
            XCTAssertEqual(
                try Data(contentsOf: locations.backupURL),
                fixture.candidateEnvelope,
                barrierKind
            )
            let unchangedSnapshot = try await repository.snapshot()
            XCTAssertEqual(unchangedSnapshot, loaded, barrierKind)
        }
    }

    func testHydrationAdoptionChecksSessionBeforeReadingCandidate() async throws {
        let fixture = try ProfileHydrationTestFixture()
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let fileSystem = FaultInjectingProfileStoreFileSystem()
        try writeExactProfileCopies(
            primary: fixture.sourceEnvelope,
            backup: fixture.sourceEnvelope,
            to: directory
        )
        let repository = makeHydrationAdoptionRepository(
            directory: directory,
            fixture: fixture,
            fileSystem: fileSystem
        )
        let loaded = try await repository.load(at: fixture.date)
        try writeExactProfileCopies(
            primary: fixture.candidateEnvelope,
            backup: fixture.candidateEnvelope,
            to: directory
        )
        fileSystem.failNext(.beforeRead("player-profile.json"))
        let staleSession = ProfileSessionToken(
            accountIdentity: loaded.session.accountIdentity,
            nonce: UUID(),
            profileID: loaded.session.profileID
        )

        do {
            _ = try await repository.adoptCommittedHydration(
                fixture.journal,
                session: staleSession
            )
            XCTFail("A stale session must be rejected")
        } catch let error as LocalPlayerRepositoryError {
            XCTAssertEqual(error, .sessionMismatch)
        }
        do {
            _ = try await repository.adoptCommittedHydration(
                fixture.journal,
                session: loaded.session
            )
            XCTFail("The unconsumed read fault must reach the valid caller")
        } catch {
            XCTAssertEqual(error as? AtomicProfileFileStoreError, .ioFailure)
        }
        let unchangedSnapshot = try await repository.snapshot()
        XCTAssertEqual(unchangedSnapshot, loaded)
    }

    func testHydrationAdoptionBindsJournalSourceNonceIndependentlyOfCallerSession()
        async throws
    {
        let fixture = try ProfileHydrationTestFixture()
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        try writeExactProfileCopies(
            primary: fixture.sourceEnvelope,
            backup: fixture.sourceEnvelope,
            to: directory
        )
        let repository = makeHydrationAdoptionRepository(
            directory: directory,
            fixture: fixture
        )
        let loaded = try await repository.load(at: fixture.date)
        let wrongJournal = try fixture.makeJournal(
            sourceSession: ProfileSessionToken(
                accountIdentity: loaded.session.accountIdentity,
                nonce: UUID(),
                profileID: loaded.session.profileID
            )
        )
        try writeExactProfileCopies(
            primary: fixture.candidateEnvelope,
            backup: fixture.candidateEnvelope,
            to: directory
        )
        let locations = ProfileStorageLocations(directoryURL: directory)

        do {
            _ = try await repository.adoptCommittedHydration(
                wrongJournal,
                session: loaded.session
            )
            XCTFail("A journal from another source session must be rejected")
        } catch let error as LocalPlayerRepositoryError {
            XCTAssertEqual(error, .hydrationAdoptionSourceMismatch)
        }
        let unchangedSnapshot = try await repository.snapshot()
        XCTAssertEqual(unchangedSnapshot, loaded)
        XCTAssertEqual(
            try Data(contentsOf: locations.primaryURL),
            fixture.candidateEnvelope
        )
        XCTAssertEqual(
            try Data(contentsOf: locations.backupURL),
            fixture.candidateEnvelope
        )
    }

    func testHydrationAdoptionOrderingRejectsStaleSourceAndAdvancesAfterAdoption()
        async throws
    {
        let fixture = try ProfileHydrationTestFixture()

        do {
            let directory = makeTemporaryDirectory()
            defer { removeTemporaryDirectory(directory) }
            try writeExactProfileCopies(
                primary: fixture.sourceEnvelope,
                backup: fixture.sourceEnvelope,
                to: directory
            )
            let repository = makeHydrationAdoptionRepository(
                directory: directory,
                fixture: fixture
            )
            let loaded = try await repository.load(at: fixture.date)
            let locallyAdvanced = try await repository.updateSettings(
                PlayerSettings(isMuted: true),
                session: loaded.session,
                at: fixture.date.addingTimeInterval(2)
            )
            try writeExactProfileCopies(
                primary: fixture.candidateEnvelope,
                backup: fixture.candidateEnvelope,
                to: directory
            )

            do {
                _ = try await repository.adoptCommittedHydration(
                    fixture.journal,
                    session: loaded.session
                )
                XCTFail("A locally advanced source must make the journal stale")
            } catch let error as LocalPlayerRepositoryError {
                XCTAssertEqual(error, .hydrationAdoptionSourceMismatch)
            }
            let unchangedSnapshot = try await repository.snapshot()
            XCTAssertEqual(unchangedSnapshot, locallyAdvanced)
        }

        do {
            let directory = makeTemporaryDirectory()
            defer { removeTemporaryDirectory(directory) }
            try writeExactProfileCopies(
                primary: fixture.sourceEnvelope,
                backup: fixture.sourceEnvelope,
                to: directory
            )
            let repository = makeHydrationAdoptionRepository(
                directory: directory,
                fixture: fixture
            )
            let loaded = try await repository.load(at: fixture.date)
            try writeExactProfileCopies(
                primary: fixture.candidateEnvelope,
                backup: fixture.candidateEnvelope,
                to: directory
            )
            let adopted = try await repository.adoptCommittedHydration(
                fixture.journal,
                session: loaded.session
            )
            let next = try await repository.updateSettings(
                PlayerSettings(isMuted: true),
                session: loaded.session,
                at: fixture.date.addingTimeInterval(3)
            )

            XCTAssertEqual(next.player.revision, adopted.player.revision + 1)
            XCTAssertEqual(next.economyRevision, adopted.economyRevision)
            XCTAssertTrue(next.player.settings.isMuted)
        }
    }

    func testInvalidatedRepositoryCannotAdoptCommittedHydration() async throws {
        let fixture = try ProfileHydrationTestFixture()
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        try writeExactProfileCopies(
            primary: fixture.sourceEnvelope,
            backup: fixture.sourceEnvelope,
            to: directory
        )
        let repository = makeHydrationAdoptionRepository(
            directory: directory,
            fixture: fixture
        )
        let loaded = try await repository.load(at: fixture.date)
        try writeExactProfileCopies(
            primary: fixture.candidateEnvelope,
            backup: fixture.candidateEnvelope,
            to: directory
        )
        await repository.invalidateForAccountSwitch()

        do {
            _ = try await repository.adoptCommittedHydration(
                fixture.journal,
                session: loaded.session
            )
            XCTFail("An invalidated repository must reject adoption")
        } catch let error as LocalPlayerRepositoryError {
            XCTAssertEqual(error, .sessionInvalidated)
        }
    }

    func testHydrationAdoptionRejectsPendingLocalReplacementBeforeDiskRead()
        async throws
    {
        let fixture = try ProfileHydrationTestFixture()
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let fileSystem = FaultInjectingProfileStoreFileSystem()
        try writeExactProfileCopies(
            primary: fixture.sourceEnvelope,
            backup: fixture.sourceEnvelope,
            to: directory
        )
        let repository = makeHydrationAdoptionRepository(
            directory: directory,
            fixture: fixture,
            fileSystem: fileSystem
        )
        let loaded = try await repository.load(at: fixture.date)
        fileSystem.failNext(.afterWrite("player-profile.json"))
        do {
            _ = try await repository.updateSettings(
                PlayerSettings(isMuted: true),
                session: loaded.session,
                at: fixture.date.addingTimeInterval(2)
            )
            XCTFail("The local replacement must enter exact reconciliation")
        } catch let error as LocalPlayerRepositoryError {
            XCTAssertEqual(error, .profileWriteOutcomeUnknown)
        }
        try writeExactProfileCopies(
            primary: fixture.candidateEnvelope,
            backup: fixture.candidateEnvelope,
            to: directory
        )
        fileSystem.failNext(.beforeRead("player-profile.json"))

        for _ in 0 ..< 2 {
            do {
                _ = try await repository.adoptCommittedHydration(
                    fixture.journal,
                    session: loaded.session
                )
                XCTFail("Hydration must not clear an uncertain local replacement")
            } catch let error as LocalPlayerRepositoryError {
                XCTAssertEqual(error, .profileWriteOutcomeUnknown)
            }
        }

        let store = AtomicProfileFileStore(
            directoryURL: directory,
            fileSystem: fileSystem
        )
        XCTAssertThrowsError(
            try store.readExactInstalledCandidate(
                fixture.journal,
                catalog: .approved
            )
        ) {
            XCTAssertEqual($0 as? AtomicProfileFileStoreError, .ioFailure)
        }
        let locations = ProfileStorageLocations(directoryURL: directory)
        XCTAssertEqual(
            try Data(contentsOf: locations.primaryURL),
            fixture.candidateEnvelope
        )
        XCTAssertEqual(
            try Data(contentsOf: locations.backupURL),
            fixture.candidateEnvelope
        )
    }

    func testNeverLoadedRepositoryCannotAdoptCommittedHydration() async throws {
        let fixture = try ProfileHydrationTestFixture()
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        try writeExactProfileCopies(
            primary: fixture.candidateEnvelope,
            backup: fixture.candidateEnvelope,
            to: directory
        )
        let repository = makeHydrationAdoptionRepository(
            directory: directory,
            fixture: fixture
        )

        do {
            _ = try await repository.adoptCommittedHydration(
                fixture.journal,
                session: fixture.sourceSession
            )
            XCTFail("An unloaded actor has no exact cached source authority")
        } catch let error as LocalPlayerRepositoryError {
            XCTAssertEqual(error, .notLoaded)
        }
        let locations = ProfileStorageLocations(directoryURL: directory)
        XCTAssertEqual(
            try Data(contentsOf: locations.primaryURL),
            fixture.candidateEnvelope
        )
        XCTAssertEqual(
            try Data(contentsOf: locations.backupURL),
            fixture.candidateEnvelope
        )
    }

    func testExactCandidateReadRejectsInvalidJournalBeforeFileSystemIO() throws {
        let fixture = try ProfileHydrationTestFixture()
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        try writeExactProfileCopies(
            primary: fixture.candidateEnvelope,
            backup: fixture.candidateEnvelope,
            to: directory
        )
        let encoded = try ProfileHydrationCanonicalCodec.encode(fixture.journal)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object["mergePolicyVersion"] = 999
        let invalidData = try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        let invalidJournal = try ProfileHydrationCanonicalCodec.decode(
            ProfileHydrationJournalV1.self,
            from: invalidData
        )
        let fileSystem = FaultInjectingProfileStoreFileSystem()
        fileSystem.failNext(.beforeStatus("profile-hydration-journal.json"))
        let store = AtomicProfileFileStore(
            directoryURL: directory,
            fileSystem: fileSystem
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: store.transactionLocations.lockURL.path
            )
        )

        XCTAssertThrowsError(
            try store.readExactInstalledCandidate(
                invalidJournal,
                catalog: .approved
            )
        ) {
            XCTAssertEqual(
                $0 as? AtomicProfileFileStoreError,
                .invalidHydrationJournal(.unsupportedMergePolicyVersion(999))
            )
        }
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: store.transactionLocations.lockURL.path
            )
        )
        XCTAssertThrowsError(
            try store.readExactInstalledCandidate(
                fixture.journal,
                catalog: .approved
            )
        ) {
            XCTAssertEqual($0 as? AtomicProfileFileStoreError, .ioFailure)
        }
    }

    func testExactCandidateReadRejectsContendedSharedLockWithoutMutation() throws {
        let fixture = try ProfileHydrationTestFixture()
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        try writeExactProfileCopies(
            primary: fixture.candidateEnvelope,
            backup: fixture.candidateEnvelope,
            to: directory
        )
        let store = AtomicProfileFileStore(directoryURL: directory)
        let contender = FoundationProfileHydrationFileSystem()

        try contender.withExclusiveLock(at: store.transactionLocations.lockURL) {
            XCTAssertThrowsError(
                try store.readExactInstalledCandidate(
                    fixture.journal,
                    catalog: .approved
                )
            ) {
                XCTAssertEqual(
                    $0 as? AtomicProfileFileStoreError,
                    .lockContended
                )
            }
        }
        let locations = ProfileStorageLocations(directoryURL: directory)
        XCTAssertEqual(
            try Data(contentsOf: locations.primaryURL),
            fixture.candidateEnvelope
        )
        XCTAssertEqual(
            try Data(contentsOf: locations.backupURL),
            fixture.candidateEnvelope
        )
    }

    func testTwoLoadedRepositoriesRejectStaleWriterWithoutChangingActorOrDisk()
        async throws
    {
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let first = makeRepository(directory: directory, deviceID: "cas-device-a")
        let firstLoaded = try await first.load(at: baseDate)
        let second = makeRepository(directory: directory, deviceID: "cas-device-b")
        let secondLoaded = try await second.load(at: baseDate.addingTimeInterval(1))
        let secondSource = try await second.hydrationSource(
            session: secondLoaded.session
        )

        _ = try await first.updateSettings(
            PlayerSettings(
                musicVolume: 0.1,
                sfxVolume: 0.2,
                isMuted: true,
                reducedMotion: false,
                tutorialCompleted: false
            ),
            session: firstLoaded.session,
            at: baseDate.addingTimeInterval(2)
        )
        let locations = ProfileStorageLocations(directoryURL: directory)
        let primaryAfterFirst = try Data(contentsOf: locations.primaryURL)
        let backupAfterFirst = try Data(contentsOf: locations.backupURL)

        do {
            _ = try await second.updateSettings(
                PlayerSettings(
                    musicVolume: 0.9,
                    sfxVolume: 0.8,
                    isMuted: false,
                    reducedMotion: true,
                    tutorialCompleted: true
                ),
                session: secondLoaded.session,
                at: baseDate.addingTimeInterval(3)
            )
            XCTFail("A repository with stale exact bytes must not overwrite a newer writer")
        } catch {
            XCTAssertEqual(
                error as? AtomicProfileFileStoreError,
                .sourceEnvelopeCASMismatch(
                    expected: .envelopeBytes(secondSource.exactEnvelopeBytes),
                    actual: .unexpected(.envelopeBytes(primaryAfterFirst))
                )
            )
        }

        XCTAssertEqual(try Data(contentsOf: locations.primaryURL), primaryAfterFirst)
        XCTAssertEqual(try Data(contentsOf: locations.backupURL), backupAfterFirst)
        let secondAfterRejection = try await second.snapshot()
        XCTAssertEqual(secondAfterRejection, secondLoaded)
    }

    func testSemanticallyEqualDifferentEnvelopeFailsExactCASAndLeavesStateUntouched()
        async throws
    {
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let repository = makeRepository(directory: directory)
        let loaded = try await repository.load(at: baseDate)
        let source = try await repository.hydrationSource(session: loaded.session)
        let locations = ProfileStorageLocations(directoryURL: directory)
        let sourceDocument = try PlayerProfileMigrator().decode(
            source.exactEnvelopeBytes
        )
        let externallyReencoded = try PlayerProfileMigrator().encode(
            sourceDocument,
            savedAt: baseDate.addingTimeInterval(50)
        )
        XCTAssertNotEqual(externallyReencoded, source.exactEnvelopeBytes)
        try externallyReencoded.write(to: locations.primaryURL, options: .atomic)
        let backupBefore = try Data(contentsOf: locations.backupURL)

        do {
            _ = try await repository.updateSettings(
                PlayerSettings(
                    musicVolume: 0.7,
                    sfxVolume: 0.6,
                    isMuted: true,
                    reducedMotion: true,
                    tutorialCompleted: false
                ),
                session: loaded.session,
                at: baseDate.addingTimeInterval(51)
            )
            XCTFail("Semantic equality must not substitute for exact envelope bytes")
        } catch {
            XCTAssertEqual(
                error as? AtomicProfileFileStoreError,
                .sourceEnvelopeCASMismatch(
                    expected: .envelopeBytes(source.exactEnvelopeBytes),
                    actual: .unexpected(.envelopeBytes(externallyReencoded))
                )
            )
        }

        let snapshotAfterRejection = try await repository.snapshot()
        XCTAssertEqual(snapshotAfterRejection, loaded)
        XCTAssertEqual(try Data(contentsOf: locations.primaryURL), externallyReencoded)
        XCTAssertEqual(try Data(contentsOf: locations.backupURL), backupBefore)
    }

    func testExactCASLostResponseRetryRepairsDivergentBackupToPredecessor()
        throws
    {
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let store = AtomicProfileFileStore(directoryURL: directory)
        let expected = try store.loadOrCreate(
            defaultDocument: PlayerProfileFactory.makeDefault(
                accountIdentity: .local,
                deviceID: "idempotent-cas-device",
                createdAt: baseDate
            ),
            at: baseDate,
            catalog: .approved
        ).artifact
        var candidateDocument = expected.document
        candidateDocument.player.settings.value.isMuted = true
        candidateDocument.player.settings.modifiedAt = baseDate.addingTimeInterval(1)
        candidateDocument.player.settings.logicalCounter += 1
        candidateDocument.player.revision += 1
        let candidateDate = baseDate.addingTimeInterval(1)
        let candidate = try PlayerProfileMigrator().canonicalArtifact(
            for: candidateDocument,
            savedAt: candidateDate
        )
        let locations = ProfileStorageLocations(directoryURL: directory)

        // Simulate a committed primary followed by a lost response and a
        // damaged recovery copy before the caller retries the same operation.
        try candidate.exactBytes.write(to: locations.primaryURL, options: .atomic)
        try Data("divergent-backup".utf8).write(
            to: locations.backupURL,
            options: .atomic
        )

        let retried = try store.save(
            candidateDocument,
            at: candidateDate,
            catalog: .approved,
            replacing: expected
        )

        XCTAssertEqual(retried, .committed(candidate))
        XCTAssertEqual(try Data(contentsOf: locations.primaryURL), candidate.exactBytes)
        XCTAssertEqual(try Data(contentsOf: locations.backupURL), expected.exactBytes)
    }

    func testJournalAndQuarantineEvidenceBlockOrdinaryProfileCreation() throws {
        for marker in ["journal-primary", "journal-backup", "quarantine-evidence"] {
            let directory = makeTemporaryDirectory().appendingPathComponent(
                marker,
                isDirectory: true
            )
            defer { removeTemporaryDirectory(directory) }
            let store = AtomicProfileFileStore(directoryURL: directory)
            let markerURL: URL
            switch marker {
            case "journal-primary":
                markerURL = store.transactionLocations.journalPrimaryURL
            case "journal-backup":
                markerURL = store.transactionLocations.journalBackupURL
            default:
                markerURL = store.transactionLocations.quarantineSlotURL(0)
            }
            try FileManager.default.createDirectory(
                at: markerURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("recovery-evidence".utf8).write(to: markerURL, options: .atomic)

            XCTAssertThrowsError(
                try store.loadOrCreate(
                    defaultDocument: PlayerProfileFactory.makeDefault(
                        accountIdentity: .local,
                        deviceID: "barrier-device",
                        createdAt: baseDate
                    ),
                    at: baseDate,
                    catalog: .approved
                )
            ) {
                XCTAssertEqual(
                    $0 as? AtomicProfileFileStoreError,
                    .hydrationRecoveryRequired,
                    marker
                )
            }
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: store.locations.primaryURL.path),
                marker
            )
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: store.locations.backupURL.path),
                marker
            )
        }
    }

    func testJournalAndQuarantineEvidenceBlockMutationWithoutChangingActorOrDisk()
        async throws
    {
        for marker in ["journal", "quarantine-evidence"] {
            let directory = makeTemporaryDirectory().appendingPathComponent(
                marker,
                isDirectory: true
            )
            defer { removeTemporaryDirectory(directory) }
            let repository = makeRepository(directory: directory)
            let loaded = try await repository.load(at: baseDate)
            let locations = ProfileStorageLocations(directoryURL: directory)
            let transactionLocations = ProfileHydrationTransactionLocations(
                profileDirectoryURL: directory
            )
            let primaryBefore = try Data(contentsOf: locations.primaryURL)
            let backupBefore = try Data(contentsOf: locations.backupURL)
            let markerURL = marker == "journal"
                ? transactionLocations.journalPrimaryURL
                : transactionLocations.quarantineSlotURL(0)
            try FileManager.default.createDirectory(
                at: markerURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("recovery-evidence".utf8).write(to: markerURL, options: .atomic)

            do {
                _ = try await repository.updateSettings(
                    PlayerSettings(
                        musicVolume: 0,
                        sfxVolume: 0,
                        isMuted: true,
                        reducedMotion: true,
                        tutorialCompleted: true
                    ),
                    session: loaded.session,
                    at: baseDate.addingTimeInterval(1)
                )
                XCTFail("Recovery evidence must block ordinary mutation")
            } catch {
                XCTAssertEqual(
                    error as? AtomicProfileFileStoreError,
                    .hydrationRecoveryRequired,
                    marker
                )
            }

            let snapshotAfterBarrier = try await repository.snapshot()
            XCTAssertEqual(snapshotAfterBarrier, loaded, marker)
            XCTAssertEqual(try Data(contentsOf: locations.primaryURL), primaryBefore, marker)
            XCTAssertEqual(try Data(contentsOf: locations.backupURL), backupBefore, marker)
        }
    }

    func testAtomicStoreAndHydrationTransactionUseTheSameRealFlock() throws {
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let fileSystem = FoundationProfileHydrationFileSystem()
        let store = AtomicProfileFileStore(
            directoryURL: directory,
            fileSystem: fileSystem
        )
        let hydrationStore = ProfileHydrationFileTransactionStore(
            profileDirectoryURL: directory
        )
        XCTAssertEqual(
            store.transactionLocations.lockURL,
            hydrationStore.locations.lockURL
        )

        try fileSystem.withExclusiveLock(at: hydrationStore.locations.lockURL) {
            XCTAssertThrowsError(
                try store.loadOrCreate(
                    defaultDocument: PlayerProfileFactory.makeDefault(
                        accountIdentity: .local,
                        deviceID: "shared-flock-device",
                        createdAt: baseDate
                    ),
                    at: baseDate,
                    catalog: .approved
                )
            ) {
                XCTAssertEqual(
                    $0 as? AtomicProfileFileStoreError,
                    .lockContended
                )
            }
        }

        let loaded = try store.loadOrCreate(
            defaultDocument: PlayerProfileFactory.makeDefault(
                accountIdentity: .local,
                deviceID: "shared-flock-device",
                createdAt: baseDate
            ),
            at: baseDate,
            catalog: .approved
        )
        var candidate = loaded.document
        candidate.player.settings.value.isMuted.toggle()
        candidate.player.settings.modifiedAt = baseDate.addingTimeInterval(1)
        candidate.player.settings.logicalCounter += 1
        candidate.player.revision += 1
        let primaryBefore = try Data(contentsOf: store.locations.primaryURL)
        let backupBefore = try Data(contentsOf: store.locations.backupURL)

        try fileSystem.withExclusiveLock(at: hydrationStore.locations.lockURL) {
            XCTAssertThrowsError(
                try store.save(
                    candidate,
                    at: baseDate.addingTimeInterval(1),
                    catalog: .approved,
                    replacing: loaded.artifact
                )
            ) {
                XCTAssertEqual(
                    $0 as? AtomicProfileFileStoreError,
                    .lockContended
                )
            }
        }
        XCTAssertEqual(try Data(contentsOf: store.locations.primaryURL), primaryBefore)
        XCTAssertEqual(try Data(contentsOf: store.locations.backupURL), backupBefore)
    }

    func testDefinitivePreRenameFailureLeavesSourceCachedAndRetryAppliesOnce()
        async throws
    {
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let fileSystem = FaultInjectingProfileStoreFileSystem()
        let repository = makeRepository(directory: directory, fileSystem: fileSystem)
        let loaded = try await repository.load(at: baseDate)
        let locations = ProfileStorageLocations(directoryURL: directory)
        let sourceBytes = try Data(contentsOf: locations.primaryURL)
        let settings = PlayerSettings(
            musicVolume: 0.25,
            sfxVolume: 0.5,
            isMuted: true,
            reducedMotion: false,
            tutorialCompleted: false
        )

        fileSystem.failNext(.beforeWrite(locations.primaryURL.lastPathComponent))
        do {
            _ = try await repository.updateSettings(
                settings,
                session: loaded.session,
                at: baseDate.addingTimeInterval(1)
            )
            XCTFail("A pre-rename failure must be definitive")
        } catch {
            XCTAssertEqual(error as? AtomicProfileFileStoreError, .ioFailure)
        }

        let afterDefinitiveFailure = try await repository.snapshot()
        XCTAssertEqual(afterDefinitiveFailure, loaded)
        XCTAssertEqual(try Data(contentsOf: locations.primaryURL), sourceBytes)
        let retried = try await repository.updateSettings(
            settings,
            session: loaded.session,
            at: baseDate.addingTimeInterval(2)
        )
        XCTAssertEqual(retried.player.revision, loaded.player.revision + 1)
        XCTAssertEqual(retried.player.settings, settings)
    }

    func testPostRenameFailureReconcilesExactCandidateBeforeSnapshotPublication()
        async throws
    {
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let fileSystem = FaultInjectingProfileStoreFileSystem()
        let repository = makeRepository(directory: directory, fileSystem: fileSystem)
        let loaded = try await repository.load(at: baseDate)
        let locations = ProfileStorageLocations(directoryURL: directory)
        let sourceBytes = try Data(contentsOf: locations.primaryURL)
        fileSystem.failNext(.afterWrite(locations.primaryURL.lastPathComponent))

        do {
            _ = try await repository.updateSettings(
                PlayerSettings(isMuted: true),
                session: loaded.session,
                at: baseDate.addingTimeInterval(1)
            )
            XCTFail("A post-rename failure must enter reconciliation")
        } catch let error as LocalPlayerRepositoryError {
            XCTAssertEqual(error, .profileWriteOutcomeUnknown)
        }

        let installedBytes = try Data(contentsOf: locations.primaryURL)
        let reconciled = try await repository.snapshot()
        let source = try await repository.hydrationSource(session: loaded.session)
        XCTAssertTrue(reconciled.player.settings.isMuted)
        XCTAssertEqual(reconciled.player.revision, loaded.player.revision + 1)
        XCTAssertEqual(source.exactEnvelopeBytes, installedBytes)
        XCTAssertEqual(try Data(contentsOf: locations.backupURL), sourceBytes)
    }

    func testPersistentReconciliationFailureBlocksReadsUntilExactRecovery()
        async throws
    {
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let fileSystem = FaultInjectingProfileStoreFileSystem()
        let repository = makeRepository(directory: directory, fileSystem: fileSystem)
        let loaded = try await repository.load(at: baseDate)
        let locations = ProfileStorageLocations(directoryURL: directory)
        fileSystem.failNext(.afterWrite(locations.primaryURL.lastPathComponent))
        do {
            _ = try await repository.updateSettings(
                PlayerSettings(isMuted: true),
                session: loaded.session,
                at: baseDate.addingTimeInterval(1)
            )
            XCTFail("Expected an outcome-unknown replacement")
        } catch let error as LocalPlayerRepositoryError {
            XCTAssertEqual(error, .profileWriteOutcomeUnknown)
        }

        fileSystem.failRepeatedly(.beforeWrite(locations.backupURL.lastPathComponent))
        for operation in 0 ..< 2 {
            do {
                if operation == 0 {
                    _ = try await repository.snapshot()
                } else {
                    _ = try await repository.hydrationSource(session: loaded.session)
                }
                XCTFail("Pending durability must block every profile exposure")
            } catch let error as LocalPlayerRepositoryError {
                XCTAssertEqual(error, .profileWriteOutcomeUnknown)
            }
        }

        fileSystem.clearRepeatedFailure()
        let recovered = try await repository.snapshot()
        XCTAssertTrue(recovered.player.settings.isMuted)
        XCTAssertEqual(recovered.player.revision, loaded.player.revision + 1)
    }

    func testPendingReplacementRemainsBlockedByHydrationEvidence() async throws {
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let fileSystem = FaultInjectingProfileStoreFileSystem()
        let repository = makeRepository(directory: directory, fileSystem: fileSystem)
        let loaded = try await repository.load(at: baseDate)
        let locations = ProfileStorageLocations(directoryURL: directory)
        fileSystem.failNext(.afterWrite(locations.primaryURL.lastPathComponent))
        do {
            _ = try await repository.updateSettings(
                PlayerSettings(isMuted: true),
                session: loaded.session,
                at: baseDate.addingTimeInterval(1)
            )
            XCTFail("Expected an outcome-unknown replacement")
        } catch let error as LocalPlayerRepositoryError {
            XCTAssertEqual(error, .profileWriteOutcomeUnknown)
        }

        let transactionLocations = ProfileHydrationTransactionLocations(
            profileDirectoryURL: directory
        )
        try FileManager.default.createDirectory(
            at: transactionLocations.journalDirectoryURL,
            withIntermediateDirectories: true
        )
        try Data("transaction-barrier".utf8).write(
            to: transactionLocations.journalPrimaryURL,
            options: .atomic
        )
        do {
            _ = try await repository.snapshot()
            XCTFail("A pending replacement cannot cross a hydration barrier")
        } catch let error as LocalPlayerRepositoryError {
            XCTAssertEqual(error, .profileWriteOutcomeUnknown)
        }
        try FileManager.default.removeItem(at: transactionLocations.journalPrimaryURL)
        let recovered = try await repository.snapshot()
        XCTAssertTrue(recovered.player.settings.isMuted)
    }

    func testPendingReplacementRejectsUnexpectedPrimaryWithoutPublishingIt()
        async throws
    {
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let fileSystem = FaultInjectingProfileStoreFileSystem()
        let repository = makeRepository(directory: directory, fileSystem: fileSystem)
        let loaded = try await repository.load(at: baseDate)
        let locations = ProfileStorageLocations(directoryURL: directory)
        fileSystem.failNext(.afterWrite(locations.primaryURL.lastPathComponent))
        do {
            _ = try await repository.updateSettings(
                PlayerSettings(isMuted: true),
                session: loaded.session,
                at: baseDate.addingTimeInterval(1)
            )
            XCTFail("Expected an outcome-unknown replacement")
        } catch let error as LocalPlayerRepositoryError {
            XCTAssertEqual(error, .profileWriteOutcomeUnknown)
        }
        let candidateBytes = try Data(contentsOf: locations.primaryURL)
        var unexpectedDocument = try PlayerProfileMigrator().decode(candidateBytes)
        unexpectedDocument.player.settings.value.reducedMotion = true
        let unexpectedBytes = try PlayerProfileMigrator().encode(
            unexpectedDocument,
            savedAt: baseDate.addingTimeInterval(50)
        )
        try unexpectedBytes.write(to: locations.primaryURL, options: .atomic)

        do {
            _ = try await repository.snapshot()
            XCTFail("Unexpected third-party bytes must not be adopted")
        } catch let error as LocalPlayerRepositoryError {
            XCTAssertEqual(error, .profileWriteOutcomeUnknown)
        }
        XCTAssertEqual(try Data(contentsOf: locations.primaryURL), unexpectedBytes)

        try candidateBytes.write(to: locations.primaryURL, options: .atomic)
        let recovered = try await repository.snapshot()
        XCTAssertTrue(recovered.player.settings.isMuted)
        XCTAssertFalse(recovered.player.settings.reducedMotion)
        XCTAssertEqual(recovered.player.revision, loaded.player.revision + 1)
    }

    func testRestartAdoptsEitherExactSourceOrCandidateWithoutDuplicateRevision()
        async throws
    {
        for candidateSurvives in [false, true] {
            let directory = makeTemporaryDirectory().appendingPathComponent(
                candidateSurvives ? "candidate" : "source",
                isDirectory: true
            )
            defer { removeTemporaryDirectory(directory) }
            let fileSystem = FaultInjectingProfileStoreFileSystem()
            let first = makeRepository(directory: directory, fileSystem: fileSystem)
            let loaded = try await first.load(at: baseDate)
            let locations = ProfileStorageLocations(directoryURL: directory)
            let sourceBytes = try Data(contentsOf: locations.primaryURL)
            fileSystem.failNext(.afterWrite(locations.primaryURL.lastPathComponent))
            do {
                _ = try await first.updateSettings(
                    PlayerSettings(isMuted: true),
                    session: loaded.session,
                    at: baseDate.addingTimeInterval(1)
                )
                XCTFail("Expected an outcome-unknown replacement")
            } catch let error as LocalPlayerRepositoryError {
                XCTAssertEqual(error, .profileWriteOutcomeUnknown)
            }
            if !candidateSurvives {
                try sourceBytes.write(to: locations.primaryURL, options: .atomic)
            }

            let relaunched = makeRepository(directory: directory)
            let reloaded = try await relaunched.load(at: baseDate.addingTimeInterval(2))
            XCTAssertEqual(reloaded.player.revision, candidateSurvives ? 1 : 0)
            XCTAssertEqual(reloaded.player.settings.isMuted, candidateSurvives)
        }
    }

    func testRelaunchBlocksCandidatePublicationUntilPredecessorDurabilityBarrierSucceeds()
        async throws
    {
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let initial = makeRepository(directory: directory)
        let loaded = try await initial.load(at: baseDate)
        let locations = ProfileStorageLocations(directoryURL: directory)
        let sourceBytes = try Data(contentsOf: locations.primaryURL)
        var candidateDocument = try PlayerProfileMigrator().decode(sourceBytes)
        candidateDocument.player.settings.value.isMuted = true
        candidateDocument.player.settings.modifiedAt = baseDate.addingTimeInterval(1)
        candidateDocument.player.settings.logicalCounter += 1
        candidateDocument.player.revision += 1
        let candidateBytes = try PlayerProfileMigrator().encode(
            candidateDocument,
            savedAt: baseDate.addingTimeInterval(1)
        )

        // This is the exact visible layout left by a candidate-primary rename
        // whose parent-directory durability result was lost with the process.
        try candidateBytes.write(to: locations.primaryURL, options: .atomic)
        XCTAssertEqual(try Data(contentsOf: locations.backupURL), sourceBytes)

        let fileSystem = FaultInjectingProfileStoreFileSystem()
        fileSystem.failNext(.beforeWrite(locations.backupURL.lastPathComponent))
        let relaunched = makeRepository(
            directory: directory,
            fileSystem: fileSystem
        )
        do {
            _ = try await relaunched.load(at: baseDate.addingTimeInterval(2))
            XCTFail("A visible candidate cannot publish before the durability barrier")
        } catch {
            XCTAssertEqual(error as? AtomicProfileFileStoreError, .ioFailure)
        }
        do {
            _ = try await relaunched.snapshot()
            XCTFail("A failed durability barrier must leave the repository unloaded")
        } catch let error as LocalPlayerRepositoryError {
            XCTAssertEqual(error, .notLoaded)
        }
        XCTAssertEqual(try Data(contentsOf: locations.primaryURL), candidateBytes)
        XCTAssertEqual(try Data(contentsOf: locations.backupURL), sourceBytes)

        let recovered = try await relaunched.load(at: baseDate.addingTimeInterval(3))
        XCTAssertEqual(recovered.player.revision, loaded.player.revision + 1)
        XCTAssertTrue(recovered.player.settings.isMuted)
        XCTAssertEqual(try Data(contentsOf: locations.primaryURL), candidateBytes)
        XCTAssertEqual(try Data(contentsOf: locations.backupURL), sourceBytes)
    }

    func testPendingReplacementInvalidationBlocksOldActorAndReturnRechecksDurability()
        async throws
    {
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let fileSystem = FaultInjectingProfileStoreFileSystem()
        let first = makeRepository(directory: directory, fileSystem: fileSystem)
        let loaded = try await first.load(at: baseDate)
        let locations = ProfileStorageLocations(directoryURL: directory)
        let sourceBytes = try Data(contentsOf: locations.primaryURL)
        fileSystem.failNext(.afterWrite(locations.primaryURL.lastPathComponent))
        do {
            _ = try await first.updateSettings(
                PlayerSettings(isMuted: true),
                session: loaded.session,
                at: baseDate.addingTimeInterval(1)
            )
            XCTFail("Expected an outcome-unknown replacement")
        } catch let error as LocalPlayerRepositoryError {
            XCTAssertEqual(error, .profileWriteOutcomeUnknown)
        }
        let candidateBytes = try Data(contentsOf: locations.primaryURL)
        XCTAssertEqual(try Data(contentsOf: locations.backupURL), sourceBytes)

        // This one-shot fault proves invalidation returns before attempting the
        // old actor's pending reconciliation: the returning account consumes it.
        fileSystem.failNext(.beforeWrite(locations.backupURL.lastPathComponent))
        await first.invalidateForAccountSwitch()
        do {
            _ = try await first.snapshot()
            XCTFail("An invalidated actor must never reconcile or publish")
        } catch let error as LocalPlayerRepositoryError {
            XCTAssertEqual(error, .sessionInvalidated)
        }

        let returning = makeRepository(directory: directory, fileSystem: fileSystem)
        do {
            _ = try await returning.load(at: baseDate.addingTimeInterval(2))
            XCTFail("The returning account must establish its durability barrier")
        } catch {
            XCTAssertEqual(error as? AtomicProfileFileStoreError, .ioFailure)
        }
        XCTAssertEqual(try Data(contentsOf: locations.primaryURL), candidateBytes)
        XCTAssertEqual(try Data(contentsOf: locations.backupURL), sourceBytes)

        let recovered = try await returning.load(at: baseDate.addingTimeInterval(3))
        XCTAssertEqual(recovered.player.revision, loaded.player.revision + 1)
        XCTAssertTrue(recovered.player.settings.isMuted)
        do {
            _ = try await first.snapshot()
            XCTFail("Returning to the account must not reactivate the old actor")
        } catch let error as LocalPlayerRepositoryError {
            XCTAssertEqual(error, .sessionInvalidated)
        }
    }

    func testOversizedFreshArtifactIsRejectedBeforeEitherProfileWrite() throws {
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let store = AtomicProfileFileStore(
            directoryURL: directory,
            limits: profileLimits(maximumEnvelopeBytes: 1)
        )
        XCTAssertThrowsError(
            try store.loadOrCreate(
                defaultDocument: PlayerProfileFactory.makeDefault(
                    accountIdentity: .local,
                    deviceID: "oversized-fresh-device",
                    createdAt: baseDate
                ),
                at: baseDate,
                catalog: .approved
            )
        ) {
            guard case .profileEnvelopeTooLarge = $0 as? AtomicProfileFileStoreError else {
                return XCTFail("Expected a typed preflight size rejection, got \($0)")
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.locations.primaryURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.locations.backupURL.path))
    }

    func testOversizedCanonicalLegacyRewriteLeavesBothSourceCopiesUntouched() throws {
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let migrator = PlayerProfileMigrator()
        let document = PlayerProfileFactory.makeDefault(
            accountIdentity: .local,
            deviceID: "oversized-legacy-device",
            createdAt: baseDate
        )
        let canonical = try migrator.encode(document, savedAt: baseDate)
        let legacy = try envelopeData(
            from: canonical,
            schemaVersion: PlayerProfileEnvelopeV1.schemaVersion,
            removingLogicalCounterFrom: ["settings", "selection"],
            removeRewardedRunObservations: true
        )
        let migrated = try migrator.canonicalArtifact(
            for: migrator.decode(legacy),
            savedAt: baseDate
        )
        XCTAssertGreaterThan(migrated.exactBytes.count, legacy.count)
        let locations = ProfileStorageLocations(directoryURL: directory)
        try legacy.write(to: locations.primaryURL, options: .atomic)
        try legacy.write(to: locations.backupURL, options: .atomic)
        let store = AtomicProfileFileStore(
            directoryURL: directory,
            limits: profileLimits(maximumEnvelopeBytes: legacy.count)
        )

        XCTAssertThrowsError(
            try store.loadOrCreate(
                defaultDocument: document,
                at: baseDate,
                catalog: .approved
            )
        ) {
            XCTAssertEqual(
                $0 as? AtomicProfileFileStoreError,
                .profileEnvelopeTooLarge(
                    actual: migrated.exactBytes.count,
                    maximum: legacy.count
                )
            )
        }
        XCTAssertEqual(try Data(contentsOf: locations.primaryURL), legacy)
        XCTAssertEqual(try Data(contentsOf: locations.backupURL), legacy)
    }

    func testOversizedReplacementCandidateIsRejectedBeforeBackupRotation() throws {
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let initialStore = AtomicProfileFileStore(directoryURL: directory)
        let source = try initialStore.loadOrCreate(
            defaultDocument: PlayerProfileFactory.makeDefault(
                accountIdentity: .local,
                deviceID: "oversized-candidate-device",
                createdAt: baseDate
            ),
            at: baseDate,
            catalog: .approved
        ).artifact
        var candidateDocument = source.document
        candidateDocument.player.settings.value.musicVolume = 0.123456789
        candidateDocument.player.settings.modifiedAt = baseDate.addingTimeInterval(1)
        candidateDocument.player.settings.deviceID = String(repeating: "a", count: 64)
        candidateDocument.player.settings.logicalCounter += 1
        candidateDocument.player.revision += 1
        let candidateDate = baseDate.addingTimeInterval(1)
        let candidate = try PlayerProfileMigrator().canonicalArtifact(
            for: candidateDocument,
            savedAt: candidateDate
        )
        XCTAssertGreaterThan(candidate.exactBytes.count, source.exactBytes.count)
        let locations = ProfileStorageLocations(directoryURL: directory)
        let primaryBefore = try Data(contentsOf: locations.primaryURL)
        let backupBefore = try Data(contentsOf: locations.backupURL)
        let limitedStore = AtomicProfileFileStore(
            directoryURL: directory,
            limits: profileLimits(maximumEnvelopeBytes: source.exactBytes.count)
        )

        XCTAssertThrowsError(
            try limitedStore.save(
                candidateDocument,
                at: candidateDate,
                catalog: .approved,
                replacing: source
            )
        ) {
            XCTAssertEqual(
                $0 as? AtomicProfileFileStoreError,
                .profileEnvelopeTooLarge(
                    actual: candidate.exactBytes.count,
                    maximum: source.exactBytes.count
                )
            )
        }
        XCTAssertEqual(try Data(contentsOf: locations.primaryURL), primaryBefore)
        XCTAssertEqual(try Data(contentsOf: locations.backupURL), backupBefore)
    }

    func testMalformedHydrationDirectoryIsIOFailureNotMissingEvidence() throws {
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = AtomicProfileFileStore(directoryURL: directory)
        try Data("not-a-directory".utf8).write(
            to: store.transactionLocations.journalDirectoryURL,
            options: .atomic
        )

        XCTAssertThrowsError(
            try store.loadOrCreate(
                defaultDocument: PlayerProfileFactory.makeDefault(
                    accountIdentity: .local,
                    deviceID: "status-failure-device",
                    createdAt: baseDate
                ),
                at: baseDate,
                catalog: .approved
            )
        ) {
            XCTAssertEqual($0 as? AtomicProfileFileStoreError, .ioFailure)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.locations.primaryURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.locations.backupURL.path))
    }

    func testThrowingStatusAndProfileReadFailuresFailClosedWithoutMutation() throws {
        let failures: [(String, FaultInjectingProfileStoreFileSystem.Failure)] = [
            (
                "journal primary status",
                .beforeStatus("profile-hydration-journal.json")
            ),
            (
                "journal backup status",
                .beforeStatus("profile-hydration-journal.backup.json")
            ),
            (
                "quarantine status",
                .beforeStatus("journal-evidence-0.json")
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

        for (name, failure) in failures {
            let directory = makeTemporaryDirectory()
            let seedStore = AtomicProfileFileStore(directoryURL: directory)
            let defaultDocument = PlayerProfileFactory.makeDefault(
                accountIdentity: .local,
                deviceID: "throwing-status-device",
                createdAt: baseDate
            )
            _ = try seedStore.loadOrCreate(
                defaultDocument: defaultDocument,
                at: baseDate,
                catalog: .approved
            )
            let primaryBefore = try Data(contentsOf: seedStore.locations.primaryURL)
            let backupBefore = try Data(contentsOf: seedStore.locations.backupURL)
            let fileSystem = FaultInjectingProfileStoreFileSystem()
            fileSystem.failNext(failure)
            let faultedStore = AtomicProfileFileStore(
                directoryURL: directory,
                fileSystem: fileSystem
            )

            XCTAssertThrowsError(
                try faultedStore.loadOrCreate(
                    defaultDocument: defaultDocument,
                    at: baseDate.addingTimeInterval(1),
                    catalog: .approved
                ),
                name
            ) {
                XCTAssertEqual(
                    $0 as? AtomicProfileFileStoreError,
                    .ioFailure,
                    name
                )
            }
            XCTAssertEqual(
                try Data(contentsOf: seedStore.locations.primaryURL),
                primaryBefore,
                name
            )
            XCTAssertEqual(
                try Data(contentsOf: seedStore.locations.backupURL),
                backupBefore,
                name
            )
            XCTAssertFalse(
                FileManager.default.fileExists(
                    atPath: seedStore.transactionLocations.journalPrimaryURL.path
                ),
                name
            )
            XCTAssertFalse(
                FileManager.default.fileExists(
                    atPath: seedStore.transactionLocations.journalBackupURL.path
                ),
                name
            )
            removeTemporaryDirectory(directory)
        }
    }

    func testEqualRevisionDivergentBackupFailsClosedWithoutChangingEvidence() throws {
        try assertDivergentBackupFailsClosed(primaryRevision: 1, backupRevision: 1)
    }

    func testNewerDivergentBackupFailsClosedWithoutChangingEvidence() throws {
        try assertDivergentBackupFailsClosed(primaryRevision: 1, backupRevision: 2)
    }

    func testFirstLaunchCreatesConservativeProfileWithoutSpendableOrPendingCoins() async throws {
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let profileID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let repository = makeRepository(directory: directory)

        let snapshot = try await repository.load(
            at: baseDate,
            newProfileID: profileID
        )
        let report = await repository.lastLoadReport

        XCTAssertEqual(report?.source, .createdFresh)
        XCTAssertEqual(snapshot.player.profileID, profileID)
        XCTAssertEqual(snapshot.player.inventory.ownedTeamIDs.count, 4)
        XCTAssertEqual(snapshot.player.inventory.ownedJerseyIDs.count, 4)
        XCTAssertEqual(snapshot.player.inventory.ownedFootballIDs, [LaunchFootballID.standard])
        XCTAssertEqual(snapshot.player.selection.selectedTeamID, LaunchTeamID.novaCityComets)
        XCTAssertEqual(snapshot.player.settings.musicVolume, 0.38)
        XCTAssertEqual(snapshot.player.settings.sfxVolume, 0.72)
        XCTAssertFalse(snapshot.player.settings.isMuted)
        XCTAssertFalse(snapshot.player.settings.reducedMotion)
        XCTAssertFalse(snapshot.player.settings.tutorialCompleted)
        XCTAssertEqual(snapshot.coinBalances, CoinBalanceSummary(confirmed: 0, pending: 0))
        XCTAssertTrue(snapshot.rewardedRunObservations.isEmpty)
        XCTAssertEqual(snapshot.player.revision, 0)
        XCTAssertEqual(snapshot.economyRevision, 0)

        let locations = ProfileStorageLocations(directoryURL: directory)
        XCTAssertTrue(FileManager.default.fileExists(atPath: locations.primaryURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: locations.backupURL.path))
        let document = try decodePrimary(in: directory)
        XCTAssertTrue(document.player.ledger.isEmpty)
        XCTAssertEqual(document.rewardedRunObservations, [:])
        XCTAssertEqual(document.player.settings.logicalCounter, 0)
        XCTAssertEqual(document.player.selection.logicalCounter, 0)
        let persistedObject = try XCTUnwrap(
            try JSONSerialization.jsonObject(
                with: Data(contentsOf: locations.primaryURL)
            ) as? [String: Any]
        )
        XCTAssertEqual(
            (persistedObject["schemaVersion"] as? NSNumber)?.intValue,
            PlayerProfileEnvelopeV3.schemaVersion
        )
        XCTAssertNil(
            document.player.ledger[
                CoinLedgerID.signingBonus(version: PersistedEconomyRulesV1.signingBonusVersion)
            ]
        )
    }

    func testRelaunchRestoresSavedSettingsAndSelection() async throws {
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let first = makeRepository(directory: directory)
        let initial = try await first.load(at: baseDate)
        _ = try await first.updateSettings(
            PlayerSettings(
                musicVolume: 0.2,
                sfxVolume: 0.9,
                isMuted: true,
                reducedMotion: true,
                tutorialCompleted: true
            ),
            session: initial.session,
            at: baseDate.addingTimeInterval(1)
        )
        let saved = try await first.selectTeam(
            LaunchTeamID.highMesaHelions,
            session: initial.session,
            at: baseDate.addingTimeInterval(2)
        )

        let relaunched = makeRepository(directory: directory, deviceID: "device-b")
        let restored = try await relaunched.load(at: baseDate.addingTimeInterval(10))
        let relaunchSource = await relaunched.lastLoadReport?.source

        XCTAssertNotEqual(restored.session.nonce, saved.session.nonce)
        XCTAssertEqual(restored.player, saved.player)
        XCTAssertEqual(restored.economyRevision, saved.economyRevision)
        XCTAssertEqual(restored.coinBalances, saved.coinBalances)
        XCTAssertEqual(restored.completedRuns, saved.completedRuns)
        XCTAssertEqual(restored.ledger, saved.ledger)
        XCTAssertEqual(relaunchSource, .primary)
        XCTAssertTrue(restored.player.settings.isMuted)
        XCTAssertTrue(restored.player.settings.reducedMotion)
        XCTAssertEqual(restored.player.selection.selectedTeamID, LaunchTeamID.highMesaHelions)
        let persisted = try decodePrimary(in: directory)
        XCTAssertEqual(persisted.player.settings.logicalCounter, 1)
        XCTAssertEqual(persisted.player.settings.deviceID, "test-device")
        XCTAssertEqual(
            persisted.player.settings.modifiedAt,
            baseDate.addingTimeInterval(1)
        )
        XCTAssertEqual(persisted.player.selection.logicalCounter, 1)
        XCTAssertEqual(persisted.player.selection.deviceID, "test-device")
        XCTAssertEqual(
            persisted.player.selection.modifiedAt,
            baseDate.addingTimeInterval(2)
        )
    }

    func testNoOpsAndUnrelatedRunSettlementLeaveBothFieldStampsUnchanged() async throws {
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let repository = makeRepository(directory: directory)
        let initial = try await repository.load(at: baseDate)

        _ = try await repository.settle(
            makeRun(id: fixedRunID(900), score: 12_000),
            session: initial.session,
            recordedAt: baseDate.addingTimeInterval(1)
        )
        let afterRun = try decodePrimary(in: directory)
        XCTAssertEqual(afterRun.player.revision, 1)
        XCTAssertEqual(afterRun.player.settings.logicalCounter, 0)
        XCTAssertEqual(afterRun.player.selection.logicalCounter, 0)
        XCTAssertEqual(afterRun.player.settings.modifiedAt, baseDate)
        XCTAssertEqual(afterRun.player.selection.modifiedAt, baseDate)

        let locations = ProfileStorageLocations(directoryURL: directory)
        let beforeNoOps = try Data(contentsOf: locations.primaryURL)
        let snapshot = try await repository.snapshot()
        _ = try await repository.updateSettings(
            snapshot.player.settings,
            session: initial.session,
            at: baseDate.addingTimeInterval(2)
        )
        _ = try await repository.selectTeam(
            snapshot.player.selection.selectedTeamID,
            session: initial.session,
            at: baseDate.addingTimeInterval(3)
        )
        _ = try await repository.equipJersey(
            try XCTUnwrap(snapshot.player.selection.selectedJerseyID),
            for: snapshot.player.selection.selectedTeamID,
            session: initial.session,
            at: baseDate.addingTimeInterval(4)
        )
        _ = try await repository.equipFootball(
            snapshot.player.selection.selectedFootballID,
            session: initial.session,
            at: baseDate.addingTimeInterval(5)
        )

        XCTAssertEqual(try Data(contentsOf: locations.primaryURL), beforeNoOps)
        XCTAssertEqual(try decodePrimary(in: directory), afterRun)
    }

    func testEachSettingsAndSelectionMutationAdvancesOnlyItsFieldCounterOnce() async throws {
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let repository = makeRepository(directory: directory)
        let initial = try await repository.load(at: baseDate)
        _ = try await addConfirmedCoins(
            3_600,
            transactionID: 9_100,
            to: repository,
            at: baseDate
        )

        let novaAlternate = alternateJerseyItem(for: LaunchTeamID.novaCityComets)
        let jerseyRequest = try await repository.prepareUnlock(
            itemID: novaAlternate.id,
            operationID: OperationID("counter-jersey-unlock"),
            session: initial.session
        )
        _ = try await repository.unlock(
            using: makeUnlockReceipt(
                for: jerseyRequest,
                at: baseDate.addingTimeInterval(1)
            ),
            session: initial.session,
            at: baseDate.addingTimeInterval(1)
        )

        let footballItem = try XCTUnwrap(
            LaunchCatalog.approved.unlockableItems.first { item in
                guard case let .football(footballID) = item.kind else { return false }
                return footballID == LaunchFootballID.alternate
            }
        )
        let footballRequest = try await repository.prepareUnlock(
            itemID: footballItem.id,
            operationID: OperationID("counter-football-unlock"),
            session: initial.session
        )
        _ = try await repository.unlock(
            using: makeUnlockReceipt(
                for: footballRequest,
                at: baseDate.addingTimeInterval(2)
            ),
            session: initial.session,
            at: baseDate.addingTimeInterval(2)
        )

        var persisted = try decodePrimary(in: directory)
        XCTAssertEqual(persisted.player.settings.logicalCounter, 0)
        XCTAssertEqual(persisted.player.selection.logicalCounter, 0)

        _ = try await repository.updateSettings(
            PlayerSettings(isMuted: true, reducedMotion: true),
            session: initial.session,
            at: baseDate.addingTimeInterval(3)
        )
        persisted = try decodePrimary(in: directory)
        XCTAssertEqual(persisted.player.settings.logicalCounter, 1)
        XCTAssertEqual(persisted.player.settings.modifiedAt, baseDate.addingTimeInterval(3))
        XCTAssertEqual(persisted.player.settings.deviceID, "test-device")
        XCTAssertEqual(persisted.player.selection.logicalCounter, 0)

        _ = try await repository.selectTeam(
            LaunchTeamID.highMesaHelions,
            session: initial.session,
            at: baseDate.addingTimeInterval(4)
        )
        persisted = try decodePrimary(in: directory)
        XCTAssertEqual(persisted.player.settings.logicalCounter, 1)
        XCTAssertEqual(persisted.player.selection.logicalCounter, 1)
        XCTAssertEqual(persisted.player.selection.modifiedAt, baseDate.addingTimeInterval(4))

        let nova = try XCTUnwrap(
            LaunchCatalog.approved.team(id: LaunchTeamID.novaCityComets)
        )
        _ = try await repository.equipJersey(
            nova.alternateJersey.id,
            for: nova.id,
            session: initial.session,
            at: baseDate.addingTimeInterval(5)
        )
        persisted = try decodePrimary(in: directory)
        XCTAssertEqual(persisted.player.settings.logicalCounter, 1)
        XCTAssertEqual(persisted.player.selection.logicalCounter, 2)
        XCTAssertEqual(persisted.player.selection.modifiedAt, baseDate.addingTimeInterval(5))

        _ = try await repository.equipFootball(
            LaunchFootballID.alternate,
            session: initial.session,
            at: baseDate.addingTimeInterval(6)
        )
        persisted = try decodePrimary(in: directory)
        XCTAssertEqual(persisted.player.settings.logicalCounter, 1)
        XCTAssertEqual(persisted.player.selection.logicalCounter, 3)
        XCTAssertEqual(persisted.player.selection.modifiedAt, baseDate.addingTimeInterval(6))
        XCTAssertEqual(persisted.player.selection.deviceID, "test-device")
        XCTAssertEqual(persisted.player.revision, 7)
        XCTAssertEqual(persisted.economyRevision, 3)
    }

    func testTeamUnlockAutomaticallyStampsRememberedJerseyExactlyOnce() async throws {
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let teamID = LaunchTeamID.lumaCoastPrisms
        var seed = PlayerProfileFactory.makeDefault(
            accountIdentity: .local,
            deviceID: "test-device",
            createdAt: baseDate
        )
        seed.player.selection.value.selectedJerseyByTeam.removeValue(forKey: teamID)
        try writeProfile(seed, to: directory, savedAt: baseDate)
        let repository = makeRepository(directory: directory)
        let initial = try await repository.load(at: baseDate)
        _ = try await addConfirmedCoins(
            1_650,
            transactionID: 9_101,
            to: repository,
            at: baseDate
        )
        let team = try XCTUnwrap(LaunchCatalog.approved.team(id: teamID))
        let teamItem = try XCTUnwrap(
            LaunchCatalog.approved.unlockableItems.first { item in
                guard case let .team(candidate) = item.kind else { return false }
                return candidate == teamID
            }
        )
        let request = try await repository.prepareUnlock(
            itemID: teamItem.id,
            operationID: OperationID("counter-team-unlock"),
            session: initial.session
        )
        let receipt = makeUnlockReceipt(
            for: request,
            at: baseDate.addingTimeInterval(1)
        )

        _ = try await repository.unlock(
            using: receipt,
            session: initial.session,
            at: baseDate.addingTimeInterval(1)
        )
        let locations = ProfileStorageLocations(directoryURL: directory)
        let afterFirstBytes = try Data(contentsOf: locations.primaryURL)
        let afterFirst = try decodePrimary(in: directory)
        XCTAssertEqual(afterFirst.player.selection.logicalCounter, 1)
        XCTAssertEqual(afterFirst.player.selection.modifiedAt, baseDate.addingTimeInterval(1))
        XCTAssertEqual(afterFirst.player.selection.deviceID, "test-device")
        XCTAssertEqual(afterFirst.player.revision, 2)
        XCTAssertEqual(afterFirst.economyRevision, 2)
        XCTAssertEqual(
            afterFirst.player.selection.value.selectedJerseyByTeam[teamID],
            team.primaryJersey.id
        )

        let duplicate = try await repository.unlock(
            using: receipt,
            session: initial.session,
            at: baseDate.addingTimeInterval(2)
        )
        XCTAssertTrue(duplicate.wasAlreadyUnlocked)
        XCTAssertEqual(try Data(contentsOf: locations.primaryURL), afterFirstBytes)
    }

    func testFieldCounterOverflowLeavesCurrentProfileAndDiskUnchanged() async throws {
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        var document = PlayerProfileFactory.makeDefault(
            accountIdentity: .local,
            deviceID: "overflow-device",
            createdAt: baseDate
        )
        document.player.settings.logicalCounter = .max
        try writeProfile(document, to: directory, savedAt: baseDate)

        let repository = makeRepository(directory: directory, deviceID: "overflow-device")
        let initial = try await repository.load(at: baseDate)
        let locations = ProfileStorageLocations(directoryURL: directory)
        let primaryBefore = try Data(contentsOf: locations.primaryURL)
        let backupBefore = try Data(contentsOf: locations.backupURL)
        let snapshotBefore = try await repository.snapshot()

        do {
            _ = try await repository.updateSettings(
                PlayerSettings(isMuted: true),
                session: initial.session,
                at: baseDate.addingTimeInterval(1)
            )
            XCTFail("A maximum field counter must fail before any mutation")
        } catch let error as LocalPlayerRepositoryError {
            XCTAssertEqual(error, .validation(.arithmeticOverflow))
        }

        let snapshotAfter = try await repository.snapshot()
        XCTAssertEqual(snapshotAfter, snapshotBefore)
        XCTAssertEqual(try Data(contentsOf: locations.primaryURL), primaryBefore)
        XCTAssertEqual(try Data(contentsOf: locations.backupURL), backupBefore)
        XCTAssertEqual(try decodePrimary(in: directory), document)
    }

    func testPlayerRevisionOverflowLeavesFieldStampAndDiskUnchanged() async throws {
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        var document = PlayerProfileFactory.makeDefault(
            accountIdentity: .local,
            deviceID: "revision-overflow-device",
            createdAt: baseDate
        )
        document.player.revision = .max
        document.player.settings.logicalCounter = 12
        try writeProfile(document, to: directory, savedAt: baseDate)

        let repository = makeRepository(
            directory: directory,
            deviceID: "revision-overflow-device"
        )
        let initial = try await repository.load(at: baseDate)
        let locations = ProfileStorageLocations(directoryURL: directory)
        let primaryBefore = try Data(contentsOf: locations.primaryURL)
        let snapshotBefore = try await repository.snapshot()

        do {
            _ = try await repository.updateSettings(
                PlayerSettings(isMuted: true),
                session: initial.session,
                at: baseDate.addingTimeInterval(1)
            )
            XCTFail("A maximum player revision must fail before stamping the field")
        } catch let error as LocalPlayerRepositoryError {
            XCTAssertEqual(error, .validation(.arithmeticOverflow))
        }

        let snapshotAfter = try await repository.snapshot()
        XCTAssertEqual(snapshotAfter, snapshotBefore)
        XCTAssertEqual(try Data(contentsOf: locations.primaryURL), primaryBefore)
        XCTAssertEqual(try decodePrimary(in: directory), document)
    }

    func testSigningBonusAppearsOnceOnFirstRewardEligibleSettlementAndRemainsPending() async throws {
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let repository = makeRepository(directory: directory)
        let initial = try await repository.load(at: baseDate)

        let ineligible = makeRun(
            id: fixedRunID(1),
            score: 2_000,
            attempts: 2,
            completions: 1,
            touchdowns: 0
        )
        let ineligibleResult = try await repository.settle(
            ineligible,
            session: initial.session,
            recordedAt: baseDate.addingTimeInterval(1)
        )
        XCTAssertNil(ineligibleResult.outcome.signingBonusEntryID)
        XCTAssertNil(ineligibleResult.outcome.gameplayRewardEntryID)

        let firstValid = makeRun(id: fixedRunID(2), score: 12_000)
        let firstResult = try await repository.settle(
            firstValid,
            session: initial.session,
            recordedAt: baseDate.addingTimeInterval(2)
        )
        XCTAssertEqual(
            firstResult.outcome.signingBonusEntryID,
            CoinLedgerID.signingBonus(version: PersistedEconomyRulesV1.signingBonusVersion)
        )
        XCTAssertEqual(firstResult.outcome.record.rewardCoins, 27)

        let secondValid = makeRun(id: fixedRunID(3), score: 4_000)
        let secondResult = try await repository.settle(
            secondValid,
            session: initial.session,
            recordedAt: baseDate.addingTimeInterval(3)
        )
        XCTAssertNil(secondResult.outcome.signingBonusEntryID)

        let snapshot = try await repository.snapshot()
        XCTAssertEqual(snapshot.coinBalances.confirmed, 0)
        XCTAssertEqual(snapshot.coinBalances.pending, 250 + 27 + 19)
        let document = try decodePrimary(in: directory)
        let signingEntries = document.player.ledger.values.filter {
            if case .signingBonus = $0.reason { return true }
            return false
        }
        XCTAssertEqual(signingEntries.count, 1)
        XCTAssertEqual(
            signingEntries.first?.createdAt,
            PersistedEconomyRulesV1.signingBonusLedgerCreatedAt
        )
        XCTAssertTrue(
            document.pendingLedgerEntryIDs.contains(
                CoinLedgerID.signingBonus(version: PersistedEconomyRulesV1.signingBonusVersion)
            )
        )
    }

    func testAbandonedRunIsRecordedOnceButNeverChangesRewardsCareerOrAchievements() async throws {
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let repository = makeRepository(directory: directory)
        let launched = try await repository.load(at: baseDate)
        let abandoned = makeRun(
            id: fixedRunID(4),
            score: 7_000,
            finishReason: .abandoned,
            elapsedMilliseconds: 30_000
        )

        let result = try await repository.settle(
            abandoned,
            session: launched.session,
            recordedAt: baseDate.addingTimeInterval(1)
        )
        let snapshot = try await repository.snapshot()

        XCTAssertNil(result.outcome.gameplayRewardEntryID)
        XCTAssertNil(result.outcome.signingBonusEntryID)
        XCTAssertTrue(result.outcome.achievementUpdates.isEmpty)
        XCTAssertEqual(result.outcome.record.rewardCoins, 0)
        XCTAssertEqual(snapshot.completedRuns.count, 1)
        XCTAssertEqual(snapshot.player.career, CareerStatistics())
        XCTAssertEqual(snapshot.coinBalances.total, 0)
        XCTAssertEqual(snapshot.player.rewardedAdState.validRunsSinceReward, 0)
    }

    func testDebugPreviewAndMalformedRunsAreRejectedBeforeAnyProfileMutation() async throws {
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let repository = makeRepository(directory: directory)
        let launched = try await repository.load(at: baseDate)
        let valid = makeRun(id: fixedRunID(5), score: 9_000)
        let nova = LaunchCatalog.approved.team(id: LaunchTeamID.novaCityComets)!
        let highMesa = LaunchCatalog.approved.team(id: LaunchTeamID.highMesaHelions)!
        let luma = LaunchCatalog.approved.team(id: LaunchTeamID.lumaCoastPrisms)!

        let invalidStatistics = RunStatisticsSnapshot(
            attempts: 10,
            completions: 4,
            touchdowns: 3,
            incompletions: 4,
            interceptions: 0,
            longestTouchdownStreak: 3
        )
        let cases: [(CompletedRun, CompletedRunValidationError)] = [
            (
                replacingRun(
                    valid,
                    elapsedMilliseconds: 0,
                    finishReason: .debugPreview
                ),
                .debugPreviewNotPersistable
            ),
            (
                replacingRun(valid, endedAt: baseDate.addingTimeInterval(2)),
                .invalidChronology
            ),
            (
                replacingRun(valid, elapsedMilliseconds: 59_999),
                .invalidElapsedMilliseconds(59_999)
            ),
            (
                replacingRun(valid, score: CompletedRunValidator.maximumAcceptedScore + 1),
                .invalidScore(CompletedRunValidator.maximumAcceptedScore + 1)
            ),
            (
                replacingRun(valid, statistics: invalidStatistics),
                .invalidStatistics
            ),
            (
                replacingRun(
                    valid,
                    configuration: replacingConfiguration(valid.configuration, economyVersion: 2)
                ),
                .unsupportedEconomyVersion(2)
            ),
            (
                replacingRun(
                    valid,
                    configuration: replacingConfiguration(
                        valid.configuration,
                        offenseTeamID: luma.id,
                        offenseJerseyID: luma.primaryJersey.id
                    )
                ),
                .offenseTeamNotOwned(luma.id)
            ),
            (
                replacingRun(
                    valid,
                    configuration: replacingConfiguration(
                        valid.configuration,
                        offenseJerseyID: highMesa.primaryJersey.id
                    )
                ),
                .invalidOffenseJersey(highMesa.primaryJersey.id)
            ),
            (
                replacingRun(
                    valid,
                    configuration: replacingConfiguration(
                        valid.configuration,
                        defenseTeamID: nova.id,
                        defenseJerseyID: nova.primaryJersey.id
                    )
                ),
                .sameTeamMatchup(nova.id)
            ),
            (
                replacingRun(
                    valid,
                    configuration: replacingConfiguration(
                        valid.configuration,
                        defenseJerseyID: luma.primaryJersey.id
                    )
                ),
                .invalidDefenseJersey(luma.primaryJersey.id)
            ),
            (
                replacingRun(
                    valid,
                    configuration: replacingConfiguration(
                        valid.configuration,
                        footballID: LaunchFootballID.alternate
                    )
                ),
                .footballNotOwned(LaunchFootballID.alternate)
            ),
        ]

        let unchanged = try await repository.snapshot()
        for (run, expectedError) in cases {
            do {
                _ = try await repository.settle(
                    run,
                    session: launched.session,
                    recordedAt: baseDate.addingTimeInterval(1)
                )
                XCTFail("Malformed run unexpectedly settled: \(expectedError)")
            } catch let error as LocalPlayerRepositoryError {
                XCTAssertEqual(error, .invalidRun(expectedError))
            }
            let afterRejection = try await repository.snapshot()
            XCTAssertEqual(afterRejection, unchanged)
        }
    }

    func testPersistedV1RunRulesRemainExplicitAndUnknownFutureVersionsFailClosed() throws {
        let rules = try XCTUnwrap(PersistedEconomyRulesV1.runRules(for: 1))
        XCTAssertEqual(rules.naturalRunMilliseconds, 60_000)
        XCTAssertEqual(rules.minimumRewardAttempts, 3)
        XCTAssertEqual(rules.baseRunCoins, 10)
        XCTAssertEqual(rules.maximumScoreCoins, 25)
        XCTAssertNil(PersistedEconomyRulesV1.runRules(for: 2))
    }

    func testDuplicateSettlementReturnsOriginalOutcomeWithoutAnySecondMutation() async throws {
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let repository = makeRepository(directory: directory)
        let initial = try await repository.load(at: baseDate)
        let run = makeRun(id: fixedRunID(10), score: 26_000)

        let first = try await repository.settle(
            run,
            session: initial.session,
            recordedAt: baseDate.addingTimeInterval(1)
        )
        let afterFirst = try await repository.snapshot()
        let duplicate = try await repository.settle(
            run,
            session: initial.session,
            recordedAt: baseDate.addingTimeInterval(99)
        )
        let afterDuplicate = try await repository.snapshot()

        XCTAssertFalse(first.wasAlreadySettled)
        XCTAssertTrue(duplicate.wasAlreadySettled)
        XCTAssertEqual(duplicate.outcome, first.outcome)
        XCTAssertEqual(afterDuplicate, afterFirst)
        XCTAssertEqual(afterDuplicate.player.career.completedRuns, 1)
        XCTAssertEqual(afterDuplicate.player.rewardedAdState.validRunsSinceReward, 1)
        XCTAssertEqual(afterDuplicate.completedRuns.count, 1)
    }

    func testSameRunIDWithDifferentPayloadIsRejected() async throws {
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let repository = makeRepository(directory: directory)
        let initial = try await repository.load(at: baseDate)
        let runID = fixedRunID(11)
        _ = try await repository.settle(
            makeRun(id: runID, score: 5_000),
            session: initial.session
        )

        do {
            _ = try await repository.settle(
                makeRun(id: runID, score: 6_000),
                session: initial.session
            )
            XCTFail("Expected a RunID collision")
        } catch let error as LocalPlayerRepositoryError {
            XCTAssertEqual(error, .runIDConflict(runID))
        }
    }

    func testCorruptPrimaryIsQuarantinedAndRecoveredFromLastValidBackup() async throws {
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let first = makeRepository(directory: directory)
        let initial = try await first.load(at: baseDate)
        _ = try await first.updateSettings(
            PlayerSettings(isMuted: true),
            session: initial.session,
            at: baseDate.addingTimeInterval(1)
        )
        _ = try await first.selectTeam(
            LaunchTeamID.highMesaHelions,
            session: initial.session,
            at: baseDate.addingTimeInterval(2)
        )

        let locations = ProfileStorageLocations(directoryURL: directory)
        try Data("not-json".utf8).write(to: locations.primaryURL)

        let recoveredRepository = makeRepository(directory: directory)
        let recovered = try await recoveredRepository.load(
            at: baseDate.addingTimeInterval(3)
        )
        let report = await recoveredRepository.lastLoadReport

        XCTAssertEqual(report?.source, .backup)
        XCTAssertEqual(report?.quarantinedURLs.count, 1)
        XCTAssertTrue(report?.quarantinedURLs.allSatisfy {
            FileManager.default.fileExists(atPath: $0.path)
        } ?? false)
        XCTAssertTrue(recovered.player.settings.isMuted)
        XCTAssertEqual(recovered.player.selection.selectedTeamID, LaunchTeamID.novaCityComets)
        XCTAssertNoThrow(try decodePrimary(in: directory))
    }

    func testTwoCorruptCopiesAreQuarantinedBeforeAConservativeFreshProfile() async throws {
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let first = makeRepository(directory: directory)
        _ = try await first.load(at: baseDate)
        let locations = ProfileStorageLocations(directoryURL: directory)
        try Data("bad-primary".utf8).write(to: locations.primaryURL)
        try Data("bad-backup".utf8).write(to: locations.backupURL)

        let replacementID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let second = makeRepository(directory: directory)
        let replacement = try await second.load(
            at: baseDate.addingTimeInterval(1),
            newProfileID: replacementID
        )
        let report = await second.lastLoadReport

        XCTAssertEqual(report?.source, .createdFresh)
        XCTAssertEqual(report?.quarantinedURLs.count, 2)
        XCTAssertEqual(replacement.player.profileID, replacementID)
        XCTAssertEqual(replacement.coinBalances.total, 0)
    }

    func testPendingGameplayCreditsCannotFundAnUnlock() async throws {
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let repository = makeRepository(directory: directory)
        let initial = try await repository.load(at: baseDate)
        _ = try await repository.settle(
            makeRun(id: fixedRunID(20), score: 25_000),
            session: initial.session
        )
        let snapshot = try await repository.snapshot()
        XCTAssertGreaterThan(snapshot.coinBalances.pending, 250)
        XCTAssertEqual(snapshot.coinBalances.confirmed, 0)
        let item = alternateJerseyItem(for: LaunchTeamID.novaCityComets)

        do {
            _ = try await repository.prepareUnlock(
                itemID: item.id,
                operationID: OperationID("insufficient-unlock"),
                session: initial.session
            )
            XCTFail("Pending credits must not be spendable")
        } catch let error as LocalPlayerRepositoryError {
            XCTAssertEqual(
                error,
                .insufficientConfirmedCoins(required: 500, available: 0)
            )
        }
    }

    func testUnlockIsIdempotentAndDebitsConfirmedBalanceExactlyOnce() async throws {
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let repository = makeRepository(directory: directory)
        let initial = try await repository.load(at: baseDate)
        let afterCredit = try await addConfirmedCoins(
            1_650,
            transactionID: 9001,
            to: repository,
            at: baseDate
        )
        let item = alternateJerseyItem(for: LaunchTeamID.novaCityComets)
        let request = try await repository.prepareUnlock(
            itemID: item.id,
            operationID: OperationID("unlock-idempotency"),
            session: initial.session
        )
        let receipt = makeUnlockReceipt(
            for: request,
            at: baseDate.addingTimeInterval(1)
        )
        let stagedOnly = try await repository.snapshot()
        XCTAssertEqual(stagedOnly, afterCredit)
        XCTAssertFalse(
            stagedOnly.player.inventory.ownedJerseyIDs.contains(
                LaunchCatalog.approved
                    .team(id: LaunchTeamID.novaCityComets)!.alternateJersey.id
            )
        )
        XCTAssertNil(
            try decodePrimary(in: directory).player.ledger[request.ledgerEntryID]
        )

        let first = try await repository.unlock(
            using: receipt,
            session: initial.session,
            at: baseDate.addingTimeInterval(1)
        )
        let afterFirst = try await repository.snapshot()
        let duplicate = try await repository.unlock(
            using: receipt,
            session: initial.session,
            at: baseDate.addingTimeInterval(2)
        )
        let afterDuplicate = try await repository.snapshot()

        XCTAssertFalse(first.wasAlreadyUnlocked)
        XCTAssertEqual(first.confirmedBalanceAfter, 1_150)
        XCTAssertTrue(duplicate.wasAlreadyUnlocked)
        XCTAssertEqual(duplicate.confirmedBalanceAfter, 1_150)
        XCTAssertEqual(afterDuplicate, afterFirst)
        XCTAssertTrue(afterFirst.player.inventory.ownedJerseyIDs.contains(
            LaunchCatalog.approved.team(id: LaunchTeamID.novaCityComets)!.alternateJersey.id
        ))
        let document = try decodePrimary(in: directory)
        XCTAssertEqual(
            document.player.ledger.values.filter {
                if case .catalogUnlock(item.id) = $0.reason { return true }
                return false
            }.count,
            1
        )
    }

    func testDurableUnlockReceiptCannotCommitAfterAccountSwitch() async throws {
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let repository = makeRepository(directory: directory)
        let launched = try await repository.load(at: baseDate)
        _ = try await addConfirmedCoins(
            1_650,
            transactionID: 9004,
            to: repository,
            at: baseDate
        )
        let item = alternateJerseyItem(for: LaunchTeamID.novaCityComets)
        let request = try await repository.prepareUnlock(
            itemID: item.id,
            operationID: OperationID("account-switch-unlock"),
            session: launched.session
        )
        let receipt = makeUnlockReceipt(
            for: request,
            at: baseDate.addingTimeInterval(1)
        )

        await repository.invalidateForAccountSwitch()
        do {
            _ = try await repository.unlock(
                using: receipt,
                session: launched.session,
                at: baseDate.addingTimeInterval(2)
            )
            XCTFail("An old-account durable receipt must not commit locally")
        } catch let error as LocalPlayerRepositoryError {
            XCTAssertEqual(error, .sessionInvalidated)
        }

        let document = try decodePrimary(in: directory)
        XCTAssertNil(document.player.ledger[request.ledgerEntryID])
        XCTAssertFalse(itemIsOwnedForTest(item, inventory: document.player.inventory))
    }

    func testSelectionRejectsLockedContentAndRemembersJerseyPerTeam() async throws {
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let repository = makeRepository(directory: directory)
        let initial = try await repository.load(at: baseDate)
        let nova = LaunchCatalog.approved.team(id: LaunchTeamID.novaCityComets)!

        do {
            _ = try await repository.equipJersey(
                nova.alternateJersey.id,
                for: nova.id,
                session: initial.session,
                at: baseDate
            )
            XCTFail("Locked jersey should not equip")
        } catch let error as LocalPlayerRepositoryError {
            XCTAssertEqual(error, .inventory(.jerseyNotOwned(nova.alternateJersey.id)))
        }

        do {
            _ = try await repository.selectTeam(
                LaunchTeamID.lumaCoastPrisms,
                session: initial.session,
                at: baseDate
            )
            XCTFail("Locked team should not select")
        } catch let error as LocalPlayerRepositoryError {
            XCTAssertEqual(error, .inventory(.teamNotOwned(LaunchTeamID.lumaCoastPrisms)))
        }

        _ = try await addConfirmedCoins(
            1_650,
            transactionID: 9002,
            to: repository,
            at: baseDate
        )
        let item = alternateJerseyItem(for: nova.id)
        let request = try await repository.prepareUnlock(
            itemID: item.id,
            operationID: OperationID("selection-unlock"),
            session: initial.session
        )
        _ = try await repository.unlock(
            using: makeUnlockReceipt(for: request, at: baseDate),
            session: initial.session,
            at: baseDate
        )
        _ = try await repository.equipJersey(
            nova.alternateJersey.id,
            for: nova.id,
            session: initial.session,
            at: baseDate.addingTimeInterval(1)
        )
        _ = try await repository.selectTeam(
            LaunchTeamID.highMesaHelions,
            session: initial.session,
            at: baseDate.addingTimeInterval(2)
        )
        let returned = try await repository.selectTeam(
            nova.id,
            session: initial.session,
            at: baseDate.addingTimeInterval(3)
        )

        XCTAssertEqual(returned.player.selection.selectedJerseyID, nova.alternateJersey.id)
        XCTAssertEqual(
            returned.player.selection.selectedJerseyByTeam[LaunchTeamID.highMesaHelions],
            LaunchCatalog.approved.team(id: LaunchTeamID.highMesaHelions)!.primaryJersey.id
        )
    }

    func testEconomyFreshnessAndProductionAuthorityAreMandatoryForSpending() async throws {
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let testRepository = makeRepository(directory: directory)
        let initial = try await testRepository.load(at: baseDate)
        _ = try await addConfirmedCoins(
            1_650,
            transactionID: 9003,
            to: testRepository,
            at: baseDate
        )
        let item = alternateJerseyItem(for: LaunchTeamID.novaCityComets)
        let staleRequest = try await testRepository.prepareUnlock(
            itemID: item.id,
            operationID: OperationID("stale-unlock"),
            session: initial.session
        )
        let staleReceipt = makeUnlockReceipt(
            for: staleRequest,
            at: baseDate.addingTimeInterval(1)
        )
        _ = try await testRepository.settle(
            makeRun(id: fixedRunID(30), score: 5_000),
            session: initial.session,
            recordedAt: baseDate.addingTimeInterval(1)
        )

        do {
            _ = try await testRepository.unlock(
                using: staleReceipt,
                session: initial.session,
                at: baseDate.addingTimeInterval(2)
            )
            XCTFail("An intervening ledger mutation must invalidate a token")
        } catch let error as LocalPlayerRepositoryError {
            XCTAssertEqual(
                error,
                .economyStateStale(
                    expected: staleRequest.expectedEconomyRevision,
                    actual: staleRequest.expectedEconomyRevision + 1
                )
            )
        }

        let productionDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(productionDirectory) }
        let production = LocalPlayerProfileRepository(
            directoryURL: productionDirectory,
            deviceID: "production-device",
            accountIdentity: .local
        )
        let productionSnapshot = try await production.load(at: baseDate)
        let unauthorizedRequest = DurableCatalogUnlockRequest(
            operationID: OperationID("unauthorized-unlock"),
            session: productionSnapshot.session,
            itemID: item.id,
            ledgerEntryID: CoinLedgerID.catalogUnlock(itemID: item.id),
            price: item.price,
            expectedEconomyRevision: productionSnapshot.economyRevision,
            confirmedBalanceBefore: productionSnapshot.coinBalances.confirmed
        )
        let unauthorizedReceipt = makeUnlockReceipt(
            for: unauthorizedRequest,
            at: baseDate,
            authority: .localTest
        )
        do {
            _ = try await production.unlock(
                using: unauthorizedReceipt,
                session: productionSnapshot.session,
                at: baseDate
            )
            XCTFail("Production repositories must reject local-test authority")
        } catch let error as LocalPlayerRepositoryError {
            XCTAssertEqual(error, .economyAuthorityRejected(.localTest))
        }
    }

    func testAccountSwitchInvalidationRejectsAnInFlightRunSettlement() async throws {
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let repository = makeRepository(directory: directory)
        let launched = try await repository.load(at: baseDate)
        let run = makeRun(id: fixedRunID(40), score: 9_000)

        await repository.invalidateForAccountSwitch()

        do {
            _ = try await repository.settle(
                run,
                session: launched.session,
                recordedAt: baseDate.addingTimeInterval(60)
            )
            XCTFail("A run launched under the prior account generation must not settle")
        } catch let error as LocalPlayerRepositoryError {
            XCTAssertEqual(error, .sessionInvalidated)
        }

        let persisted = try decodePrimary(in: directory)
        XCTAssertTrue(persisted.player.completedRuns.isEmpty)
        XCTAssertTrue(persisted.player.ledger.isEmpty)
        XCTAssertEqual(persisted.player.revision, 0)
    }

    func testRepositoryRefusesAProfileFileOwnedByAnotherAccountIdentity() async throws {
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let local = makeRepository(directory: directory)
        _ = try await local.load(at: baseDate)
        let cloudAccount = PlayerAccountIdentity("private-cloud-account-a")
        let wrongAccount = LocalPlayerProfileRepository(
            directoryURL: directory,
            deviceID: "other-device",
            accountIdentity: cloudAccount
        )

        do {
            _ = try await wrongAccount.load(at: baseDate.addingTimeInterval(1))
            XCTFail("An account may not adopt a different account's local file")
        } catch let error as LocalPlayerRepositoryError {
            XCTAssertEqual(
                error,
                .accountIdentityMismatch(expected: cloudAccount, actual: .local)
            )
        }
    }

    func testReconstructedSameAccountRepositoryNeverReusesPriorSessionIdentity() async throws {
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let first = makeRepository(directory: directory)
        let firstLaunch = try await first.load(at: baseDate)

        let reconstructed = makeRepository(directory: directory)
        let secondLaunch = try await reconstructed.load(
            at: baseDate.addingTimeInterval(1)
        )
        XCTAssertEqual(firstLaunch.player.profileID, secondLaunch.player.profileID)
        XCTAssertNotEqual(firstLaunch.session.nonce, secondLaunch.session.nonce)

        do {
            _ = try await reconstructed.settle(
                makeRun(id: fixedRunID(41), score: 9_000),
                session: firstLaunch.session,
                recordedAt: baseDate.addingTimeInterval(2)
            )
            XCTFail("A reconstructed A account must reject a stale prior-A callback")
        } catch let error as LocalPlayerRepositoryError {
            XCTAssertEqual(error, .sessionMismatch)
        }
        XCTAssertTrue(try decodePrimary(in: directory).player.completedRuns.isEmpty)
    }

    func testDurableCreditConfirmationBindsExactSessionEntriesAndRetriesIdempotently() async throws {
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let repository = makeRepository(directory: directory)
        let launched = try await repository.load(at: baseDate)
        let settlement = try await repository.settle(
            makeRun(id: fixedRunID(42), score: 12_000),
            session: launched.session,
            recordedAt: baseDate.addingTimeInterval(1)
        )
        let entryIDs = Set([
            try XCTUnwrap(settlement.outcome.gameplayRewardEntryID),
            try XCTUnwrap(settlement.outcome.signingBonusEntryID),
        ])
        let pending = try await repository.snapshot()
        let wrongBinding = makeConfirmation(
            for: pending,
            entryIDs: [try XCTUnwrap(settlement.outcome.gameplayRewardEntryID)],
            at: baseDate.addingTimeInterval(2)
        )

        do {
            _ = try await repository.confirmPendingCredits(
                entryIDs,
                session: launched.session,
                confirmation: wrongBinding,
                savedAt: baseDate.addingTimeInterval(2)
            )
            XCTFail("A confirmation for a different entry set must be rejected")
        } catch let error as LocalPlayerRepositoryError {
            XCTAssertEqual(error, .economyConfirmationBindingMismatch)
        }
        let afterWrongBinding = try await repository.snapshot()
        XCTAssertEqual(afterWrongBinding, pending)

        let confirmation = makeConfirmation(
            for: pending,
            entryIDs: entryIDs,
            at: baseDate.addingTimeInterval(3)
        )
        let confirmed = try await repository.confirmPendingCredits(
            entryIDs,
            session: launched.session,
            confirmation: confirmation,
            savedAt: baseDate.addingTimeInterval(3)
        )
        let retry = try await repository.confirmPendingCredits(
            entryIDs,
            session: launched.session,
            confirmation: confirmation,
            savedAt: baseDate.addingTimeInterval(4)
        )
        XCTAssertEqual(retry, confirmed)
        XCTAssertTrue(confirmed.pendingLedgerEntryIDs.isEmpty)
    }

    func testRewardedRunCounterStopsAtFiveAndDoesNotBankAdditionalRuns() async throws {
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let repository = makeRepository(directory: directory)
        let initial = try await repository.load(at: baseDate)

        for index in 1 ... 5 {
            let result = try await repository.settle(
                makeRun(id: fixedRunID(100 + index), score: 5_000),
                session: initial.session,
                recordedAt: baseDate.addingTimeInterval(TimeInterval(index))
            )
            if index < 5 {
                XCTAssertNil(result.outcome.rewardedOfferUnlocked)
            } else {
                XCTAssertEqual(
                    result.outcome.rewardedOfferUnlocked,
                    RewardedAdState.offerID(for: 0)
                )
            }
        }
        _ = try await repository.settle(
            makeRun(id: fixedRunID(106), score: 5_000),
            session: initial.session,
            recordedAt: baseDate.addingTimeInterval(6)
        )

        let snapshot = try await repository.snapshot()
        XCTAssertEqual(snapshot.player.rewardedAdState.validRunsSinceReward, 5)
        XCTAssertEqual(
            snapshot.player.rewardedAdState.eligibleOfferID,
            RewardedAdState.offerID(for: 0)
        )
        for index in 1 ... 5 {
            XCTAssertEqual(
                snapshot.rewardedRunObservations[fixedRunID(100 + index)],
                RewardedRunObservation(
                    observedCycle: 0,
                    disposition: .candidate
                )
            )
        }
        XCTAssertEqual(
            snapshot.rewardedRunObservations[fixedRunID(106)],
            RewardedRunObservation(
                observedCycle: 0,
                disposition: .ignoredWhileOfferPending
            )
        )
        XCTAssertEqual(snapshot.rewardedRunObservations.count, 6)
        XCTAssertEqual(
            try decodePrimary(in: directory).rewardedRunObservations,
            snapshot.rewardedRunObservations
        )
    }

    func testLegacyV1DecodeWithoutRewardedRunObservationsMigratesToEmptyMap() throws {
        let migrator = PlayerProfileMigrator()
        let original = PlayerProfileFactory.makeDefault(
            accountIdentity: .local,
            deviceID: "legacy-observation-test",
            createdAt: baseDate
        )
        let encoded = try migrator.encode(original, savedAt: baseDate)
        guard var envelope = try JSONSerialization.jsonObject(with: encoded)
            as? [String: Any],
            var document = envelope["document"] as? [String: Any]
        else {
            return XCTFail("Expected a current profile envelope")
        }
        XCTAssertNotNil(document.removeValue(forKey: "rewardedRunObservations"))
        envelope["document"] = document
        envelope["schemaVersion"] = PlayerProfileEnvelopeV1.schemaVersion
        let legacyData = try JSONSerialization.data(
            withJSONObject: envelope,
            options: [.sortedKeys]
        )

        let decoded = try migrator.decode(legacyData)

        XCTAssertEqual(decoded.rewardedRunObservations, [:])
        XCTAssertNoThrow(try PlayerProfileValidator.validate(decoded))
        let projected = try PlayerProfileProjection.snapshot(
            for: decoded,
            session: ProfileSessionToken(
                accountIdentity: decoded.accountIdentity,
                nonce: UUID(uuidString: "00000000-0000-0000-0000-000000000777")!,
                profileID: decoded.player.profileID
            )
        )
        XCTAssertTrue(projected.rewardedRunObservations.isEmpty)
    }

    func testCurrentEnvelopeWithoutRewardedRunObservationsFailsClosed() throws {
        let migrator = PlayerProfileMigrator()
        let original = PlayerProfileFactory.makeDefault(
            accountIdentity: .local,
            deviceID: "current-observation-test",
            createdAt: baseDate
        )
        let encoded = try migrator.encode(original, savedAt: baseDate)
        guard var envelope = try JSONSerialization.jsonObject(with: encoded)
            as? [String: Any],
            var document = envelope["document"] as? [String: Any]
        else {
            return XCTFail("Expected a V3 profile envelope")
        }
        document.removeValue(forKey: "rewardedRunObservations")
        envelope["document"] = document
        let malformed = try JSONSerialization.data(
            withJSONObject: envelope,
            options: [.sortedKeys]
        )

        let decoded = try migrator.decode(malformed)
        XCTAssertThrowsError(try PlayerProfileValidator.validate(decoded)) {
            XCTAssertEqual(
                $0 as? ProfileValidationError,
                .missingRewardedRunObservations
            )
        }
    }

    func testVerifiedRewardedAdSettlementIsAtomicIdempotentAndSessionBoundAcrossRelaunch()
        async throws
    {
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let repository = makeRepository(directory: directory)
        let launched = try await repository.load(at: baseDate)

        for index in 1 ... PersistedEconomyRulesV1.rewardedAdRunThreshold {
            _ = try await repository.settle(
                makeRun(id: fixedRunID(300 + index), score: 5_000),
                session: launched.session,
                recordedAt: baseDate.addingTimeInterval(TimeInterval(index))
            )
        }

        let eligible = try await repository.snapshot()
        let offerID = try XCTUnwrap(eligible.player.rewardedAdState.eligibleOfferID)
        let providerTransactionID = AdProviderTransactionID("provider-reward-0001")
        let rewardedAt = baseDate.addingTimeInterval(10)
        let receipt = makeRewardedAdReceipt(
            for: eligible,
            offerID: offerID,
            providerTransactionID: providerTransactionID,
            rewardedAt: rewardedAt
        )

        let first = try await repository.settleRewardedAd(
            using: receipt,
            session: launched.session,
            savedAt: rewardedAt
        )
        let afterFirst = try await repository.snapshot()

        XCTAssertFalse(first.wasAlreadySettled)
        XCTAssertEqual(first.offerID, offerID)
        XCTAssertEqual(first.providerTransactionID, providerTransactionID)
        XCTAssertEqual(first.coins, PersistedEconomyRulesV1.rewardedAdCoins)
        XCTAssertEqual(
            first.ledgerEntryID,
            CoinLedgerID.rewardedAd(providerTransactionID: providerTransactionID)
        )
        XCTAssertEqual(
            first.confirmedBalanceAfter,
            eligible.coinBalances.confirmed + PersistedEconomyRulesV1.rewardedAdCoins
        )
        XCTAssertEqual(afterFirst.player.rewardedAdState.cycle, 1)
        XCTAssertEqual(afterFirst.player.rewardedAdState.validRunsSinceReward, 0)
        XCTAssertNil(afterFirst.player.rewardedAdState.eligibleOfferID)
        XCTAssertEqual(afterFirst.economyRevision, eligible.economyRevision + 1)
        XCTAssertEqual(
            afterFirst.ledger[first.ledgerEntryID],
            CoinLedgerEntry(
                id: first.ledgerEntryID,
                delta: PersistedEconomyRulesV1.rewardedAdCoins,
                reason: .rewardedAd(
                    offerID: offerID,
                    providerTransactionID: providerTransactionID
                ),
                createdAt: rewardedAt
            )
        )
        XCTAssertFalse(afterFirst.pendingLedgerEntryIDs.contains(first.ledgerEntryID))

        let retry = try await repository.settleRewardedAd(
            using: receipt,
            session: launched.session,
            savedAt: baseDate.addingTimeInterval(11)
        )
        let afterRetry = try await repository.snapshot()
        XCTAssertTrue(retry.wasAlreadySettled)
        XCTAssertEqual(retry.confirmedBalanceAfter, first.confirmedBalanceAfter)
        XCTAssertEqual(afterRetry, afterFirst)

        let relaunchedRepository = makeRepository(
            directory: directory,
            deviceID: "reward-relaunch-device"
        )
        let relaunched = try await relaunchedRepository.load(
            at: baseDate.addingTimeInterval(12)
        )
        XCTAssertNotEqual(relaunched.session.nonce, launched.session.nonce)

        do {
            _ = try await relaunchedRepository.settleRewardedAd(
                using: receipt,
                session: relaunched.session,
                savedAt: baseDate.addingTimeInterval(13)
            )
            XCTFail("A receipt bound to the prior process session must be rejected")
        } catch let error as LocalPlayerRepositoryError {
            XCTAssertEqual(error, .rewardedAdReceiptMismatch)
        }

        let freshSessionProof = makeRewardedAdReceipt(
            for: relaunched,
            offerID: offerID,
            providerTransactionID: providerTransactionID,
            rewardedAt: rewardedAt,
            receiptID: OperationID("reward-receipt-fresh-session")
        )
        let relaunchedRetry = try await relaunchedRepository.settleRewardedAd(
            using: freshSessionProof,
            session: relaunched.session,
            savedAt: baseDate.addingTimeInterval(14)
        )
        let afterRelaunchRetry = try await relaunchedRepository.snapshot()
        XCTAssertTrue(relaunchedRetry.wasAlreadySettled)
        XCTAssertEqual(afterRelaunchRetry, relaunched)

        await relaunchedRepository.invalidateForAccountSwitch()
        do {
            _ = try await relaunchedRepository.settleRewardedAd(
                using: freshSessionProof,
                session: relaunched.session,
                savedAt: baseDate.addingTimeInterval(15)
            )
            XCTFail("A callback must not mutate an invalidated account session")
        } catch let error as LocalPlayerRepositoryError {
            XCTAssertEqual(error, .sessionInvalidated)
        }
        let persisted = try decodePrimary(in: directory)
        XCTAssertEqual(persisted.player.rewardedAdState.cycle, 1)
        XCTAssertEqual(
            persisted.player.ledger.values.filter {
                if case .rewardedAd = $0.reason { return true }
                return false
            }.count,
            1
        )
    }

    func testRewardedAdSettlementRejectsStaleEconomyAndUnrelatedOfferWithoutMutation()
        async throws
    {
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let repository = makeRepository(directory: directory)
        let launched = try await repository.load(at: baseDate)
        for index in 1 ... PersistedEconomyRulesV1.rewardedAdRunThreshold {
            _ = try await repository.settle(
                makeRun(id: fixedRunID(400 + index), score: 5_000),
                session: launched.session,
                recordedAt: baseDate.addingTimeInterval(TimeInterval(index))
            )
        }
        let eligible = try await repository.snapshot()
        let offerID = try XCTUnwrap(eligible.player.rewardedAdState.eligibleOfferID)
        let providerTransactionID = AdProviderTransactionID("provider-reward-0002")

        let staleReceipt = DurableRewardedAdReceipt(
            receiptID: OperationID("reward-receipt-stale"),
            session: eligible.session,
            offerID: offerID,
            providerTransactionID: providerTransactionID,
            expectedEconomyRevision: eligible.economyRevision - 1,
            confirmedBalanceBefore: eligible.coinBalances.confirmed,
            rewardedAt: baseDate.addingTimeInterval(10),
            authority: .localTest
        )
        do {
            _ = try await repository.settleRewardedAd(
                using: staleReceipt,
                session: eligible.session
            )
            XCTFail("A stale economy revision must not consume an offer")
        } catch let error as LocalPlayerRepositoryError {
            XCTAssertEqual(
                error,
                .economyStateStale(
                    expected: staleReceipt.expectedEconomyRevision,
                    actual: eligible.economyRevision
                )
            )
        }

        let unrelatedOffer = RewardedAdState.offerID(for: 1)
        let unrelatedReceipt = makeRewardedAdReceipt(
            for: eligible,
            offerID: unrelatedOffer,
            providerTransactionID: providerTransactionID,
            rewardedAt: baseDate.addingTimeInterval(10)
        )
        do {
            _ = try await repository.settleRewardedAd(
                using: unrelatedReceipt,
                session: eligible.session
            )
            XCTFail("A receipt for a different offer must not consume the active offer")
        } catch let error as LocalPlayerRepositoryError {
            XCTAssertEqual(error, .rewardedOfferNotEligible(unrelatedOffer))
        }

        let afterRejections = try await repository.snapshot()
        XCTAssertEqual(afterRejections, eligible)
    }

    func testValidatorRejectsRewardedAdLedgerAndOfferCycleHalfCommits() throws {
        let providerTransactionID = AdProviderTransactionID("half-commit-provider")
        let ledgerID = CoinLedgerID.rewardedAd(
            providerTransactionID: providerTransactionID
        )
        var ledgerWithoutRedemption = PlayerProfileFactory.makeDefault(
            accountIdentity: .local,
            deviceID: "half-commit-test",
            createdAt: baseDate
        )
        ledgerWithoutRedemption.player.ledger[ledgerID] = CoinLedgerEntry(
            id: ledgerID,
            delta: PersistedEconomyRulesV1.rewardedAdCoins,
            reason: .rewardedAd(
                offerID: RewardedAdState.offerID(for: 0),
                providerTransactionID: providerTransactionID
            ),
            createdAt: baseDate
        )
        XCTAssertThrowsError(try PlayerProfileValidator.validate(ledgerWithoutRedemption)) {
            XCTAssertEqual($0 as? ProfileValidationError, .invalidRewardedAdState)
        }

        var redemptionWithoutLedger = PlayerProfileFactory.makeDefault(
            accountIdentity: .local,
            deviceID: "half-commit-test",
            createdAt: baseDate
        )
        redemptionWithoutLedger.player.rewardedAdState = RewardedAdState(
            cycle: 1,
            validRunsSinceReward: 0,
            eligibleOfferID: nil,
            accountedRunIDs: []
        )
        XCTAssertThrowsError(try PlayerProfileValidator.validate(redemptionWithoutLedger)) {
            XCTAssertEqual($0 as? ProfileValidationError, .invalidRewardedAdState)
        }
    }

    func testFullProfileRoundTripPreservesRunsLedgerInventorySettingsAndAggregates() async throws {
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let first = makeRepository(directory: directory)
        let initial = try await first.load(at: baseDate)
        _ = try await addConfirmedCoins(
            1_650,
            transactionID: 9010,
            to: first,
            at: baseDate
        )
        let item = alternateJerseyItem(for: LaunchTeamID.novaCityComets)
        let unlockRequest = try await first.prepareUnlock(
            itemID: item.id,
            operationID: OperationID("round-trip-unlock"),
            session: initial.session
        )
        _ = try await first.unlock(
            using: makeUnlockReceipt(
                for: unlockRequest,
                at: baseDate.addingTimeInterval(1)
            ),
            session: initial.session,
            at: baseDate.addingTimeInterval(1)
        )
        let novaAlternate = LaunchCatalog.approved
            .team(id: LaunchTeamID.novaCityComets)!.alternateJersey.id
        _ = try await first.equipJersey(
            novaAlternate,
            for: LaunchTeamID.novaCityComets,
            session: initial.session,
            at: baseDate.addingTimeInterval(2)
        )
        _ = try await first.updateSettings(
            PlayerSettings(
                musicVolume: 0.1,
                sfxVolume: 0.6,
                isMuted: false,
                reducedMotion: true,
                tutorialCompleted: true
            ),
            session: initial.session,
            at: baseDate.addingTimeInterval(3)
        )
        let settlement = try await first.settle(
            makeRun(id: fixedRunID(200), score: 30_000),
            session: initial.session,
            recordedAt: baseDate.addingTimeInterval(4)
        )
        let pendingIDs = Set(
            [
                settlement.outcome.gameplayRewardEntryID,
                settlement.outcome.signingBonusEntryID,
            ].compactMap { $0 }
        )
        let pendingSnapshot = try await first.snapshot()
        let beforeRelaunch = try await first.confirmPendingCredits(
            pendingIDs,
            session: initial.session,
            confirmation: makeConfirmation(
                for: pendingSnapshot,
                entryIDs: pendingIDs,
                at: baseDate.addingTimeInterval(5)
            ),
            savedAt: baseDate.addingTimeInterval(5)
        )

        let second = makeRepository(directory: directory, deviceID: "device-c")
        let restored = try await second.load(at: baseDate.addingTimeInterval(6))

        XCTAssertNotEqual(restored.session.nonce, beforeRelaunch.session.nonce)
        XCTAssertEqual(restored.player, beforeRelaunch.player)
        XCTAssertEqual(restored.economyRevision, beforeRelaunch.economyRevision)
        XCTAssertEqual(restored.coinBalances, beforeRelaunch.coinBalances)
        XCTAssertEqual(restored.completedRuns, beforeRelaunch.completedRuns)
        XCTAssertEqual(restored.ledger, beforeRelaunch.ledger)
        XCTAssertEqual(
            restored.pendingLedgerEntryIDs,
            beforeRelaunch.pendingLedgerEntryIDs
        )
        XCTAssertEqual(restored.personalBest, 30_000)
        XCTAssertEqual(restored.player.career.completedRuns, 1)
        XCTAssertEqual(restored.player.career.totalScore, 30_000)
        XCTAssertEqual(restored.coinBalances.pending, 0)
        XCTAssertEqual(restored.coinBalances.confirmed, 1_650 - 500 + 250 + 40)
        XCTAssertEqual(restored.player.selection.selectedJerseyID, novaAlternate)
        XCTAssertTrue(restored.player.settings.reducedMotion)
        XCTAssertTrue(restored.player.settings.tutorialCompleted)
    }

    func testMigratorRejectsUnknownFutureSchemaWithoutGuessing() throws {
        let data = Data(
            "{\"format\":\"com.pocketvector.player-profile\",\"schemaVersion\":99}".utf8
        )
        XCTAssertThrowsError(try PlayerProfileMigrator().decode(data)) { error in
            XCTAssertEqual(
                error as? ProfileMigrationError,
                .unsupportedSchemaVersion(99)
            )
        }
    }

    private func makeCanonicalFixtureDocument(
        reverseCollections: Bool
    ) -> LocalPlayerDocumentV1 {
        let teams = [TeamID("fixture-team-a"), TeamID("fixture-team-b")]
        let jerseys = [JerseyID("fixture-jersey-a"), JerseyID("fixture-jersey-b")]
        let footballs = [FootballID("fixture-football-a"), FootballID("fixture-football-b")]
        let achievements = [AchievementID("fixture-achievement-a"), AchievementID("fixture-achievement-b")]
        let runs = [fixedRunID(990), fixedRunID(991)]
        let order = reverseCollections ? [1, 0] : [0, 1]

        let selectedJerseys = Dictionary(
            uniqueKeysWithValues: order.map { (teams[$0], jerseys[$0]) }
        )
        let achievementProgress = Dictionary(
            uniqueKeysWithValues: order.map { index in
                (
                    achievements[index],
                    AchievementProgress(
                        id: achievements[index],
                        percentComplete: index == 0 ? 25 : 75
                    )
                )
            }
        )
        let pendingAchievements = Dictionary(
            uniqueKeysWithValues: order.map { (achievements[$0], ($0 + 1) * 10) }
        )
        let rewardedObservations = Dictionary(
            uniqueKeysWithValues: order.map { index in
                (
                    runs[index],
                    RewardedRunObservation(
                        observedCycle: UInt64(index + 2),
                        disposition: index == 0 ? .candidate : .ignoredWhileOfferPending
                    )
                )
            }
        )

        return LocalPlayerDocumentV1(
            accountIdentity: PlayerAccountIdentity("fixture-account"),
            player: PlayerDocumentV1(
                profileID: UUID(uuidString: "12345678-1234-5678-9ABC-DEF012345678")!,
                revision: 7,
                createdAt: baseDate,
                settings: Stamped(
                    value: PlayerSettings(
                        musicVolume: 0.25,
                        sfxVolume: 0.75,
                        isMuted: true,
                        reducedMotion: false,
                        tutorialCompleted: true
                    ),
                    modifiedAt: baseDate.addingTimeInterval(1),
                    deviceID: "fixture-settings-device",
                    logicalCounter: 9
                ),
                selection: Stamped(
                    value: PlayerSelection(
                        selectedTeamID: teams[0],
                        selectedJerseyByTeam: selectedJerseys,
                        selectedFootballID: footballs[0]
                    ),
                    modifiedAt: baseDate.addingTimeInterval(2),
                    deviceID: "fixture-selection-device",
                    logicalCounter: 11
                ),
                inventory: PlayerInventory(
                    ownedTeamIDs: Set(order.map { teams[$0] }),
                    ownedJerseyIDs: Set(order.map { jerseys[$0] }),
                    ownedFootballIDs: Set(order.map { footballs[$0] })
                ),
                completedRuns: [:],
                ledger: [:],
                career: CareerStatistics(),
                achievementProgress: achievementProgress,
                rewardedAdState: RewardedAdState(
                    cycle: 2,
                    validRunsSinceReward: 2,
                    accountedRunIDs: Set(order.map { runs[$0] })
                ),
                pendingGameCenter: GameCenterSubmissionQueue(
                    pendingHighScore: 12_345,
                    pendingAchievementPercents: pendingAchievements
                )
            ),
            economyRevision: 4,
            pendingLedgerEntryIDs: [],
            settlementReceipts: [:],
            rewardedRunObservations: rewardedObservations
        )
    }

    private func makeCanonicalCollectionFixtureDocument(
        reverseCollections: Bool
    ) throws -> LocalPlayerDocumentV1 {
        let offense = try XCTUnwrap(
            LaunchCatalog.approved.team(id: LaunchTeamID.novaCityComets)
        )
        let defense = try XCTUnwrap(
            LaunchCatalog.approved.team(id: LaunchTeamID.highMesaHelions)
        )
        let runIDs = [fixedRunID(992), fixedRunID(993)]
        let runOrder = reverseCollections ? [1, 0] : [0, 1]
        let laneValues = Array(LaneID.allCases.prefix(4))
        let runs = runIDs.enumerated().map { index, runID in
            let startedAt = baseDate.addingTimeInterval(TimeInterval(index * 2))
            return CompletedRun(
                configuration: RunConfiguration(
                    runID: runID,
                    randomSeed: UInt32(9_920 + index),
                    offenseTeamID: offense.id,
                    offenseJerseyID: offense.primaryJersey.id,
                    defenseTeamID: defense.id,
                    defenseJerseyID: defense.primaryJersey.id,
                    footballID: LaunchFootballID.standard,
                    economyVersion: PersistedEconomyRulesV1.run.economyVersion,
                    startedAt: startedAt
                ),
                endedAt: startedAt.addingTimeInterval(60),
                elapsedGameplayMilliseconds: 60_000,
                finishReason: .timerExpired,
                score: 5_000 + (index * 2_000),
                statistics: RunStatisticsSnapshot(
                    attempts: 10,
                    completions: 4,
                    touchdowns: 3,
                    incompletions: 3,
                    interceptions: 0,
                    longestTouchdownStreak: 3
                ),
                completedLaneIDs: insertionOrderedSet(
                    laneValues,
                    reversed: reverseCollections
                ),
                bonusTouchdownCount: 1
            )
        }
        let records = try runs.map { run in
            CompletedRunRecord(
                run: run,
                recordedAt: run.endedAt.addingTimeInterval(1),
                rewardCoins: try CompletedRunValidator.rewardCoins(for: run)
            )
        }
        let gameplayEntries = records.map { record in
            let entryID = CoinLedgerID.gameplay(runID: record.run.runID)
            return CoinLedgerEntry(
                id: entryID,
                delta: record.rewardCoins,
                reason: .gameplay(
                    runID: record.run.runID,
                    economyVersion: record.run.configuration.economyVersion
                ),
                createdAt: record.recordedAt
            )
        }
        let signingEntry = CoinLedgerEntry(
            id: CoinLedgerID.signingBonus(
                version: PersistedEconomyRulesV1.signingBonusVersion
            ),
            delta: PersistedEconomyRulesV1.signingBonusCoins,
            reason: .signingBonus(
                version: PersistedEconomyRulesV1.signingBonusVersion
            ),
            createdAt: PersistedEconomyRulesV1.signingBonusLedgerCreatedAt
        )
        let ledgerEntries = gameplayEntries + [signingEntry]
        let ledgerOrder = reverseCollections
            ? Array(ledgerEntries.indices.reversed())
            : Array(ledgerEntries.indices)

        var career = CareerStatistics()
        var personalBestByRunID: [RunID: Int] = [:]
        for run in runs {
            career = try PersistedCareerAccumulatorV1.applying(run, to: career)
            personalBestByRunID[run.runID] = career.highestScore
        }
        let receipts = records.enumerated().map { index, record in
            let outcome = RunSettlementOutcome(
                record: record,
                gameplayRewardEntryID: gameplayEntries[index].id,
                signingBonusEntryID: index == 0 ? signingEntry.id : nil,
                achievementUpdates: [],
                rewardedOfferUnlocked: nil,
                resultingPersonalBest: personalBestByRunID[record.run.runID] ?? 0
            )
            return (record.run.runID, outcome)
        }
        let observations = records.map { record in
            (
                record.run.runID,
                RewardedRunObservation(
                    observedCycle: 0,
                    disposition: .candidate
                )
            )
        }

        var document = PlayerProfileFactory.makeDefault(
            profileID: UUID(
                uuidString: "22345678-1234-5678-9ABC-DEF012345678"
            )!,
            accountIdentity: .local,
            deviceID: "canonical-collection-device",
            createdAt: baseDate
        )
        document.player.revision = 2
        document.player.completedRuns = Dictionary(
            uniqueKeysWithValues: runOrder.map {
                (records[$0].run.runID, records[$0])
            }
        )
        document.player.ledger = Dictionary(
            uniqueKeysWithValues: ledgerOrder.map {
                (ledgerEntries[$0].id, ledgerEntries[$0])
            }
        )
        document.player.career = career
        document.player.rewardedAdState = RewardedAdState(
            cycle: 0,
            validRunsSinceReward: records.count,
            accountedRunIDs: insertionOrderedSet(
                runOrder.map { records[$0].run.runID },
                reversed: false
            )
        )
        document.economyRevision = 2
        document.pendingLedgerEntryIDs = insertionOrderedSet(
            ledgerOrder.map { ledgerEntries[$0].id },
            reversed: false
        )
        document.settlementReceipts = Dictionary(
            uniqueKeysWithValues: runOrder.map { receipts[$0] }
        )
        document.rewardedRunObservations = Dictionary(
            uniqueKeysWithValues: runOrder.map { observations[$0] }
        )
        return document
    }

    private func insertionOrderedSet<Element: Hashable>(
        _ values: [Element],
        reversed: Bool
    ) -> Set<Element> {
        let ordered = reversed ? Array(values.reversed()) : values
        var result: Set<Element> = []
        for value in ordered {
            result.insert(value)
        }
        return result
    }

    private func envelopeData(
        from source: Data,
        schemaVersion: Int,
        removingLogicalCounterFrom fields: [String] = [],
        logicalCounterOverrides: [String: Int] = [:],
        deviceIDOverrides: [String: String] = [:],
        removeRewardedRunObservations: Bool = false
    ) throws -> Data {
        var envelope = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: source) as? [String: Any]
        )
        var document = try XCTUnwrap(envelope["document"] as? [String: Any])
        var player = try XCTUnwrap(document["player"] as? [String: Any])

        for field in fields {
            var stamp = try XCTUnwrap(player[field] as? [String: Any])
            XCTAssertNotNil(stamp.removeValue(forKey: "logicalCounter"))
            player[field] = stamp
        }
        for (field, counter) in logicalCounterOverrides {
            var stamp = try XCTUnwrap(player[field] as? [String: Any])
            stamp["logicalCounter"] = counter
            player[field] = stamp
        }
        for (field, deviceID) in deviceIDOverrides {
            var stamp = try XCTUnwrap(player[field] as? [String: Any])
            stamp["deviceID"] = deviceID
            player[field] = stamp
        }

        document["player"] = player
        if removeRewardedRunObservations {
            XCTAssertNotNil(document.removeValue(forKey: "rewardedRunObservations"))
        }
        envelope["document"] = document
        envelope["schemaVersion"] = schemaVersion
        return try JSONSerialization.data(
            withJSONObject: envelope,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
    }

    private func writeProfile(
        _ document: LocalPlayerDocumentV1,
        to directory: URL,
        savedAt: Date
    ) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let data = try PlayerProfileMigrator().encode(document, savedAt: savedAt)
        let locations = ProfileStorageLocations(directoryURL: directory)
        try data.write(to: locations.primaryURL, options: .atomic)
        try data.write(to: locations.backupURL, options: .atomic)
    }

    private func writeExactProfileCopies(
        primary: Data?,
        backup: Data?,
        to directory: URL
    ) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let locations = ProfileStorageLocations(directoryURL: directory)
        for (data, url) in [
            (primary, locations.primaryURL),
            (backup, locations.backupURL),
        ] {
            if let data {
                try data.write(to: url, options: .atomic)
            } else if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
    }

    private func optionalProfileData(at url: URL) throws -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    private func makeHydrationAdoptionRepository(
        directory: URL,
        fixture: ProfileHydrationTestFixture,
        limits: ProfileHydrationLimits = .production,
        fileSystem: any ProfileHydrationFileSystem = FoundationProfileHydrationFileSystem()
    ) -> LocalPlayerProfileRepository {
        LocalPlayerProfileRepository(
            directoryURL: directory,
            deviceID: "hydration-adoption-device",
            accountIdentity: fixture.sourceAccount,
            sessionNonce: fixture.sourceSession.nonce,
            economyMutationPolicy: .allowLocalTesting,
            limits: limits,
            fileSystem: fileSystem
        )
    }

    private func assertDivergentBackupFailsClosed(
        primaryRevision: UInt64,
        backupRevision: UInt64,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let profileID = UUID(uuidString: "77777777-8888-9999-aaaa-bbbbbbbbbbbb")!
        var primary = PlayerProfileFactory.makeDefault(
            profileID: profileID,
            accountIdentity: .local,
            deviceID: "split-primary-device",
            createdAt: baseDate
        )
        primary.player.revision = primaryRevision
        primary.player.settings = Stamped(
            value: PlayerSettings(musicVolume: 0.2, isMuted: true),
            modifiedAt: baseDate.addingTimeInterval(1),
            deviceID: "split-primary-device",
            logicalCounter: primaryRevision
        )
        var backup = PlayerProfileFactory.makeDefault(
            profileID: profileID,
            accountIdentity: .local,
            deviceID: "split-backup-device",
            createdAt: baseDate
        )
        backup.player.revision = backupRevision
        backup.player.settings = Stamped(
            value: PlayerSettings(musicVolume: 0.8, reducedMotion: true),
            modifiedAt: baseDate.addingTimeInterval(2),
            deviceID: "split-backup-device",
            logicalCounter: backupRevision
        )
        try PlayerProfileValidator.validate(primary)
        try PlayerProfileValidator.validate(backup)
        let migrator = PlayerProfileMigrator()
        let primaryBytes = try migrator.encode(primary, savedAt: baseDate.addingTimeInterval(1))
        let backupBytes = try migrator.encode(backup, savedAt: baseDate.addingTimeInterval(2))
        let locations = ProfileStorageLocations(directoryURL: directory)
        try primaryBytes.write(to: locations.primaryURL, options: .atomic)
        try backupBytes.write(to: locations.backupURL, options: .atomic)
        let primaryDigest = ProfileHydrationDigest.envelopeBytes(primaryBytes)
        let backupDigest = ProfileHydrationDigest.envelopeBytes(backupBytes)
        let store = AtomicProfileFileStore(directoryURL: directory)

        XCTAssertThrowsError(
            try store.loadOrCreate(
                defaultDocument: primary,
                at: baseDate.addingTimeInterval(3),
                catalog: .approved
            ),
            file: file,
            line: line
        ) {
            XCTAssertEqual(
                $0 as? AtomicProfileFileStoreError,
                .backupEnvelopeConflict(
                    primary: primaryDigest,
                    backup: backupDigest
                ),
                file: file,
                line: line
            )
        }
        XCTAssertEqual(
            try Data(contentsOf: locations.primaryURL),
            primaryBytes,
            file: file,
            line: line
        )
        XCTAssertEqual(
            try Data(contentsOf: locations.backupURL),
            backupBytes,
            file: file,
            line: line
        )
    }

    private func profileLimits(
        maximumEnvelopeBytes: Int
    ) -> ProfileHydrationLimits {
        let production = ProfileHydrationLimits.production
        return ProfileHydrationLimits(
            maximumEncodedJournalBytes: production.maximumEncodedJournalBytes,
            maximumProfileEnvelopeBytes: maximumEnvelopeBytes,
            maximumEncodedCheckpointBytes: production.maximumEncodedCheckpointBytes,
            maximumIdentifierBytes: production.maximumIdentifierBytes,
            maximumProfileCollectionEntries: production.maximumProfileCollectionEntries,
            maximumQuarantineFiles: production.maximumQuarantineFiles,
            maximumQuarantineBytes: production.maximumQuarantineBytes
        )
    }

    private func makeRepository(
        directory: URL,
        deviceID: String = "test-device",
        limits: ProfileHydrationLimits = .production,
        fileSystem: any ProfileHydrationFileSystem = FoundationProfileHydrationFileSystem()
    ) -> LocalPlayerProfileRepository {
        LocalPlayerProfileRepository(
            directoryURL: directory,
            deviceID: deviceID,
            accountIdentity: .local,
            economyMutationPolicy: .allowLocalTesting,
            limits: limits,
            fileSystem: fileSystem
        )
    }

    private func makeTemporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "PocketVectorProfileTests-\(UUID().uuidString)",
            isDirectory: true
        )
    }

    private func removeTemporaryDirectory(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }

    private func fixedRunID(_ suffix: Int) -> RunID {
        RunID(
            UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", suffix))!
        )
    }

    private func makeRun(
        id: RunID,
        score: Int,
        attempts: Int = 10,
        completions: Int = 4,
        touchdowns: Int = 3,
        finishReason: RunFinishReason = .timerExpired,
        elapsedMilliseconds: Int = 60_000
    ) -> CompletedRun {
        let offense = LaunchCatalog.approved.team(id: LaunchTeamID.novaCityComets)!
        let defense = LaunchCatalog.approved.team(id: LaunchTeamID.highMesaHelions)!
        return CompletedRun(
            configuration: RunConfiguration(
                runID: id,
                randomSeed: UInt32(truncatingIfNeeded: id.rawValue.hashValue),
                offenseTeamID: offense.id,
                offenseJerseyID: offense.primaryJersey.id,
                defenseTeamID: defense.id,
                defenseJerseyID: defense.primaryJersey.id,
                footballID: LaunchFootballID.standard,
                economyVersion: PersistedEconomyRulesV1.run.economyVersion,
                startedAt: baseDate.addingTimeInterval(-60)
            ),
            endedAt: baseDate,
            elapsedGameplayMilliseconds: elapsedMilliseconds,
            finishReason: finishReason,
            score: score,
            statistics: RunStatisticsSnapshot(
                attempts: attempts,
                completions: completions,
                touchdowns: touchdowns,
                incompletions: max(0, attempts - completions - touchdowns),
                interceptions: 0,
                longestTouchdownStreak: touchdowns
            ),
            completedLaneIDs: Set(
                LaneID.allCases.prefix(min(4, completions + touchdowns))
            ),
            bonusTouchdownCount: min(1, touchdowns)
        )
    }

    private func replacingRun(
        _ run: CompletedRun,
        configuration: RunConfiguration? = nil,
        endedAt: Date? = nil,
        elapsedMilliseconds: Int? = nil,
        finishReason: RunFinishReason? = nil,
        score: Int? = nil,
        statistics: RunStatisticsSnapshot? = nil,
        completedLaneIDs: Set<LaneID>? = nil,
        bonusTouchdownCount: Int? = nil
    ) -> CompletedRun {
        CompletedRun(
            configuration: configuration ?? run.configuration,
            endedAt: endedAt ?? run.endedAt,
            elapsedGameplayMilliseconds: elapsedMilliseconds
                ?? run.elapsedGameplayMilliseconds,
            finishReason: finishReason ?? run.finishReason,
            score: score ?? run.score,
            statistics: statistics ?? run.statistics,
            completedLaneIDs: completedLaneIDs ?? run.completedLaneIDs,
            bonusTouchdownCount: bonusTouchdownCount ?? run.bonusTouchdownCount
        )
    }

    private func replacingConfiguration(
        _ configuration: RunConfiguration,
        offenseTeamID: TeamID? = nil,
        offenseJerseyID: JerseyID? = nil,
        defenseTeamID: TeamID? = nil,
        defenseJerseyID: JerseyID? = nil,
        footballID: FootballID? = nil,
        economyVersion: Int? = nil
    ) -> RunConfiguration {
        RunConfiguration(
            runID: configuration.runID,
            randomSeed: configuration.randomSeed,
            offenseTeamID: offenseTeamID ?? configuration.offenseTeamID,
            offenseJerseyID: offenseJerseyID ?? configuration.offenseJerseyID,
            defenseTeamID: defenseTeamID ?? configuration.defenseTeamID,
            defenseJerseyID: defenseJerseyID ?? configuration.defenseJerseyID,
            footballID: footballID ?? configuration.footballID,
            economyVersion: economyVersion ?? configuration.economyVersion,
            startedAt: configuration.startedAt
        )
    }

    private func alternateJerseyItem(for teamID: TeamID) -> CatalogItemDescriptor {
        let alternateID = LaunchCatalog.approved.team(id: teamID)!.alternateJersey.id
        return LaunchCatalog.approved.unlockableItems.first {
            if case .alternateJersey(alternateID) = $0.kind { return true }
            return false
        }!
    }

    private func itemIsOwnedForTest(
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

    private func makeConfirmation(
        for snapshot: LocalPlayerProfileSnapshot,
        entryIDs: Set<LedgerEntryID>,
        at date: Date,
        authority: EconomyStateAuthority = .localTest
    ) -> DurableEconomyConfirmation {
        DurableEconomyConfirmation(
            confirmationID: OperationID("confirmation-\(date.timeIntervalSince1970)"),
            session: snapshot.session,
            entries: Dictionary(
                uniqueKeysWithValues: entryIDs.map { ($0, snapshot.ledger[$0]!) }
            ),
            expectedEconomyRevision: snapshot.economyRevision,
            confirmedBalanceBefore: snapshot.coinBalances.confirmed,
            confirmedAt: date,
            authority: authority
        )
    }

    private func makeUnlockReceipt(
        for request: DurableCatalogUnlockRequest,
        at date: Date,
        authority: EconomyStateAuthority = .localTest
    ) -> DurableCatalogUnlockReceipt {
        DurableCatalogUnlockReceipt(
            receiptID: OperationID("receipt-\(request.operationID.rawValue)"),
            requestOperationID: request.operationID,
            session: request.session,
            itemID: request.itemID,
            ledgerEntryID: request.ledgerEntryID,
            price: request.price,
            expectedEconomyRevision: request.expectedEconomyRevision,
            confirmedBalanceBefore: request.confirmedBalanceBefore,
            confirmedBalanceAfter: request.confirmedBalanceBefore - request.price,
            confirmedAt: date,
            authority: authority
        )
    }

    private func makeRewardedAdReceipt(
        for snapshot: LocalPlayerProfileSnapshot,
        offerID: RewardOfferID,
        providerTransactionID: AdProviderTransactionID,
        rewardedAt: Date,
        receiptID: OperationID = OperationID("reward-receipt")
    ) -> DurableRewardedAdReceipt {
        DurableRewardedAdReceipt(
            receiptID: receiptID,
            session: snapshot.session,
            offerID: offerID,
            providerTransactionID: providerTransactionID,
            expectedEconomyRevision: snapshot.economyRevision,
            confirmedBalanceBefore: snapshot.coinBalances.confirmed,
            rewardedAt: rewardedAt,
            authority: .localTest
        )
    }

    private func addConfirmedCoins(
        _ amount: Int64,
        transactionID: UInt64,
        to repository: LocalPlayerProfileRepository,
        at date: Date
    ) async throws -> LocalPlayerProfileSnapshot {
        let current = try await repository.snapshot()
        let packID = try XCTUnwrap(
            PersistedEconomyRulesV1.coinPackCoins.first(where: { $0.value == amount })?.key
        )
        let entry = CoinLedgerEntry(
            id: CoinLedgerID.storeKit(transactionID: transactionID),
            delta: amount,
            reason: .storeKit(transactionID: transactionID, packID: packID),
            createdAt: date
        )
        let confirmation = DurableEconomyConfirmation(
            confirmationID: OperationID("storekit-confirmation-\(transactionID)"),
            session: current.session,
            entries: [entry.id: entry],
            expectedEconomyRevision: current.economyRevision,
            confirmedBalanceBefore: current.coinBalances.confirmed,
            confirmedAt: date,
            authority: .localTest
        )
        return try await repository.recordConfirmedCredit(
            entry,
            session: current.session,
            confirmation: confirmation,
            savedAt: date
        )
    }

    private func decodePrimary(in directory: URL) throws -> LocalPlayerDocumentV1 {
        let locations = ProfileStorageLocations(directoryURL: directory)
        return try PlayerProfileMigrator().decode(Data(contentsOf: locations.primaryURL))
    }
}

private final class FaultInjectingProfileStoreFileSystem:
    ProfileHydrationFileSystem,
    @unchecked Sendable
{
    enum Failure: Equatable {
        case beforeWrite(String)
        case afterWrite(String)
        case beforeRead(String)
        case beforeStatus(String)
    }

    private let base = FoundationProfileHydrationFileSystem()
    private let lock = NSLock()
    private var nextFailure: Failure?
    private var repeatedFailure: Failure?

    func failNext(_ failure: Failure) {
        lock.lock()
        nextFailure = failure
        lock.unlock()
    }

    func failRepeatedly(_ failure: Failure) {
        lock.lock()
        repeatedFailure = failure
        lock.unlock()
    }

    func clearRepeatedFailure() {
        lock.lock()
        repeatedFailure = nil
        lock.unlock()
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
        try base.removeItemDurably(at: url)
    }

    func withExclusiveLock(at url: URL, perform: () throws -> Void) throws {
        try base.withExclusiveLock(at: url, perform: perform)
    }

    private func consume(_ failure: Failure) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if nextFailure == failure {
            nextFailure = nil
            return true
        }
        return repeatedFailure == failure
    }
}

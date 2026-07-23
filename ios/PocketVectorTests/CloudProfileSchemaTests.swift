import XCTest

@testable import PocketVector

final class CloudProfileSchemaTests: XCTestCase, @unchecked Sendable {
    func testConfigurationRejectsEmptyAndDuplicateIdentifiers() throws {
        XCTAssertThrowsError(
            try CloudProfileSchemaConfiguration(
                rootRecordType: "",
                settingsRecordType: "Settings",
                selectionRecordType: "Selection",
                runRecordType: "Run",
                payloadFieldName: "payload"
            )
        ) { error in
            XCTAssertEqual(
                error as? CloudProfileSchemaConfigurationError,
                .invalidIdentifier("")
            )
        }

        XCTAssertThrowsError(
            try CloudProfileSchemaConfiguration(
                rootRecordType: "Profile",
                settingsRecordType: "Profile",
                selectionRecordType: "Selection",
                runRecordType: "Run",
                payloadFieldName: "payload"
            )
        ) { error in
            XCTAssertEqual(
                error as? CloudProfileSchemaConfigurationError,
                .duplicateRecordType("Profile")
            )
        }

        for invalid in ["1Profile", "Profile-Root", "Profile Root", "ÄRoot"] {
            XCTAssertThrowsError(
                try CloudProfileSchemaConfiguration(
                    rootRecordType: invalid,
                    settingsRecordType: "Settings",
                    selectionRecordType: "Selection",
                    runRecordType: "Run",
                    payloadFieldName: "payload"
                )
            ) { error in
                XCTAssertEqual(
                    error as? CloudProfileSchemaConfigurationError,
                    .invalidIdentifier(invalid)
                )
            }
        }
    }

    func testDeterministicLogicalIDsAndRunAccumulatorGoldenVectors() throws {
        let configuration = try makeConfiguration()
        XCTAssertEqual(configuration.rootRecordID.rawValue, "profile-root-v1")
        XCTAssertEqual(
            configuration.settingsRecordID.rawValue,
            "profile-settings-v1"
        )
        XCTAssertEqual(
            configuration.selectionRecordID.rawValue,
            "profile-selection-v1"
        )

        let first = RunID(
            UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        )
        let second = RunID(
            UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        )
        XCTAssertEqual(
            configuration.runRecordID(for: first).rawValue,
            "profile-run-v1-204bd9c5cdf7a648160b8dc5d46bc846"
                + "c4cbd2b9b272cdf7cf6ae353f0e4cd4a"
        )
        let firstEntry = CloudProfileRunAccumulatorEntryV1(
            logicalRecordID: configuration.runRecordID(for: first),
            canonicalPayload: Data("payload-one".utf8)
        )
        let secondEntry = CloudProfileRunAccumulatorEntryV1(
            logicalRecordID: configuration.runRecordID(for: second),
            canonicalPayload: Data("payload-two".utf8)
        )
        let accumulator = try CloudProfileRunAccumulatorV1.make(
            for: [firstEntry, secondEntry]
        )
        XCTAssertEqual(accumulator.runCount, 2)
        XCTAssertEqual(
            CloudProfileDigest.hex(accumulator.digest),
            "438afe132c62895e9abda2aaf106f804"
                + "38fd8a2f163691a852cf8a18119a6b6f"
        )
        XCTAssertEqual(
            accumulator,
            try CloudProfileRunAccumulatorV1.make(
                for: [secondEntry, firstEntry]
            )
        )
        XCTAssertThrowsError(
            try CloudProfileRunAccumulatorV1.make(
                for: [firstEntry, firstEntry]
            )
        ) { error in
            XCTAssertEqual(
                error as? CloudProfileRunAccumulatorError,
                .duplicateLogicalRecordID(firstEntry.logicalRecordID)
            )
        }
    }

    func testFingerprintMaterialIncludesEverySchemaAndAddressVersion() throws {
        let configuration = try makeConfiguration()
        let fixedMaterial = [
            "pocket-vector-cloud-profile-schema-v1",
            "rootRecordType", "ProfileRoot",
            "settingsRecordType", "ProfileSettings",
            "selectionRecordType", "ProfileSelection",
            "runRecordType", "CompletedRun",
            "payloadFieldName", "payload",
            "rootLogicalRecordID", "profile-root-v1",
            "settingsLogicalRecordID", "profile-settings-v1",
            "selectionLogicalRecordID", "profile-selection-v1",
            "runRecordIDDomain",
            "pocket-vector-cloud-profile-run-record-id-v1",
            "runRecordAddressPolicy",
            "domain-and-run-id-length-prefixed-sha256-lowercase-hex-v1",
            "runAccumulatorDomain",
            "pocket-vector-cloud-profile-run-accumulator-entry-v1",
            "runAccumulatorPolicy",
            "unique-logical-id-count-and-order-independent-xor-entry-digests-v1",
            "rootSchemaVersion", "1",
            "settingsSchemaVersion", "1",
            "selectionSchemaVersion", "1",
            "completedRunSchemaVersion", "1",
            "runAccumulatorDigestBytes", "32",
            "digestAlgorithm",
            "sha256-uint64-big-endian-length-prefixed-components-v1",
            "digestHexEncoding", "lowercase-two-digit-hex-per-byte-v1",
        ]
        let canonicalPayload = CloudProfileCanonicalPayload.fingerprintMaterial
        let mergePolicy = CloudProfileMergePolicyV1.fingerprintMaterial
        let deviceIDRule = ProfileStampDeviceIDRuleV1.fingerprintMaterial
        let accountDerivation = CloudAccountDerivedBindings.profileFingerprintMaterial
        let catalog = LaunchCatalog.approved.persistedFingerprintMaterial
        let achievements = AchievementCatalog.persistedFingerprintMaterial()
        XCTAssertEqual(
            configuration.fingerprintMaterial,
            fixedMaterial + [
                "canonicalPayloadMaterialCount", String(canonicalPayload.count),
            ] + canonicalPayload + [
                "mergePolicyMaterialCount", String(mergePolicy.count),
            ] + mergePolicy + [
                "deviceIDRuleMaterialCount", String(deviceIDRule.count),
            ] + deviceIDRule + [
                "accountDerivationMaterialCount",
                String(accountDerivation.count),
            ] + accountDerivation + [
                "catalogMaterialCount", String(catalog.count),
            ] + catalog + [
                "achievementMaterialCount", String(achievements.count),
            ] + achievements
        )
    }

    func testCanonicalPayloadManifestAndMergePoliciesAreExact() {
        XCTAssertEqual(
            CloudProfileCanonicalPayload.fingerprintMaterial,
            [
                "pocket-vector-cloud-profile-canonical-payload-v1",
                "payloadEncoding",
                "foundation-sorted-key-json-default-keys-deferred-date-base64-data-nonfinite-float-throw-v1",
                "stringIdentifierEncoding",
                "raw-representable-single-value-string-v1",
                "stringIdentifierTypes",
                "CloudAccountID,CloudRecordID,FootballID,JerseyID,PlayerAccountIdentity,ServiceAccountKey,TeamID",
                "runIDEncoding", "keyed-rawValue-foundation-uuid-v1",
                "runIDType", "RunID",
                "uuidEncoding", "foundation-uuid-string-v1",
                "rawStringEnumEncoding", "single-value-raw-string-v1",
                "rawStringEnumTypes",
                "RewardedRunObservation.Disposition,RunFinishReason",
                "jsonObjectNormalization",
                "jsonserialization-round-trip-sorted-keys-default-writing-options-v1",
                "optionalEncoding", "synthesized-keyed-nil-omitted-v1",
                "completedLaneNormalization",
                "completed-lane-raw-values-utf8-byte-ascending-v1",
                "selectedJerseyNormalization",
                "team-id-jersey-id-alternating-pairs-team-utf8-byte-ascending-v1",
                "bindingFields",
                "accountBinding,cloudAccountID,profileAccountIdentity",
                "durableAccountBindingFields", "accountKey,profileID",
                "runAccumulatorFields", "digest,runCount",
                "rootFields",
                "binding,economyHeadRecordID,rootRevision,runAccumulator,schemaVersion",
                "mergeStampFields", "deviceID,logicalCounter,modifiedAt",
                "settingsEnvelopeFields", "binding,schemaVersion,settings,stamp",
                "playerSettingsFields",
                "isMuted,musicVolume,reducedMotion,sfxVolume,tutorialCompleted",
                "selectionEnvelopeFields",
                "binding,schemaVersion,selection,stamp",
                "playerSelectionFields",
                "selectedFootballID,selectedJerseyByTeam,selectedTeamID",
                "completedRunEnvelopeFields",
                "binding,record,rewardedRunObservation,schemaVersion",
                "completedRunRecordFields", "recordedAt,rewardCoins,run",
                "completedRunFields",
                "bonusTouchdownCount,completedLaneIDs,configuration,deepCompletionCount,elapsedGameplayMilliseconds,endedAt,finishReason,maximumOverdriveTouchdownCount,score,statistics",
                "runConfigurationFields",
                "defenseJerseyID,defenseTeamID,economyVersion,footballID,offenseJerseyID,offenseTeamID,randomSeed,runID,startedAt",
                "runStatisticsFields",
                "attempts,completions,incompletions,interceptions,longestTouchdownStreak,touchdowns",
                "rewardedRunObservationFields", "disposition,observedCycle",
                "rewardedRunObservationDispositionCases",
                "candidate,ignoredWhileOfferPending,legacyNonCounting",
                "runFinishReasonCases", "abandoned,debugPreview,timerExpired",
                "laneIDEncoding", "single-value-raw-string-v1",
                "laneIDCases", "deep,medium,short,touchdown",
            ]
        )
        XCTAssertEqual(
            CloudProfileMergePolicyV1.fingerprintMaterial,
            [
                "pocket-vector-cloud-profile-stamped-merge-policy-v1",
                "orderingPolicy",
                "logical-counter-then-device-id-utf8-byte-lexicographic-v1",
                "equalityPolicy",
                "logical-counter-and-device-id-excluding-modified-at-v1",
                "compatibilityPolicy",
                "exact-schema-version-and-account-binding-v1",
                "equalStampPolicy",
                "equal-value-required-and-maximum-modified-at-canonicalized-v1",
                "divergentStampPolicy",
                "value-from-greater-logical-stamp-v1",
            ]
        )
    }

    func testMergeStampTotalOrderIgnoresInformationalDate() throws {
        let earlyDate = try CloudProfileMergeStampV1(
            logicalCounter: 4,
            deviceID: "device-z",
            modifiedAt: Date(timeIntervalSince1970: 1)
        )
        let laterDateSamePosition = try CloudProfileMergeStampV1(
            logicalCounter: 4,
            deviceID: "device-z",
            modifiedAt: Date(timeIntervalSince1970: 9_999)
        )
        let deviceTieBreak = try CloudProfileMergeStampV1(
            logicalCounter: 4,
            deviceID: "device-zz",
            modifiedAt: Date(timeIntervalSince1970: 0)
        )
        let higherCounter = try CloudProfileMergeStampV1(
            logicalCounter: 5,
            deviceID: "device-a",
            modifiedAt: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(earlyDate, laterDateSamePosition)
        XCTAssertLessThan(earlyDate, deviceTieBreak)
        XCTAssertLessThan(deviceTieBreak, higherCounter)
    }

    func testMergeStampDeviceIDIsRestrictedToByteStableASCIIOrder() throws {
        for invalid in [
            "", " device", "device space", "device/one", "dévice",
            String(repeating: "a", count: 65),
        ] {
            XCTAssertThrowsError(
                try CloudProfileMergeStampV1(
                    logicalCounter: 1,
                    deviceID: invalid,
                    modifiedAt: Date(timeIntervalSince1970: 1)
                )
            ) { error in
                XCTAssertEqual(
                    error as? CloudProfileMergeStampError,
                    .invalidDeviceID(invalid)
                )
            }
        }

        let lower = try CloudProfileMergeStampV1(
            logicalCounter: 1,
            deviceID: "device-9_A.z",
            modifiedAt: Date(timeIntervalSince1970: 1)
        )
        let upper = try CloudProfileMergeStampV1(
            logicalCounter: 1,
            deviceID: "device-A_9.z",
            modifiedAt: Date(timeIntervalSince1970: 1)
        )
        XCTAssertEqual(
            lower < upper,
            lower.deviceID.utf8.lexicographicallyPrecedes(upper.deviceID.utf8)
        )
        XCTAssertEqual(
            upper < lower,
            upper.deviceID.utf8.lexicographicallyPrecedes(lower.deviceID.utf8)
        )
        XCTAssertNotEqual(lower < upper, upper < lower)
    }

    func testEqualStampDifferentSettingsOrSelectionFailsClosed() throws {
        let binding = makeBinding()
        let stamp = try CloudProfileMergeStampV1(
            logicalCounter: 3,
            deviceID: "device-a",
            modifiedAt: Date(timeIntervalSince1970: 100)
        )
        let firstSettings = CloudProfileSettingsV1(
            binding: binding,
            stamp: stamp,
            settings: PlayerSettings(musicVolume: 0.2)
        )
        let secondSettings = CloudProfileSettingsV1(
            binding: binding,
            stamp: stamp,
            settings: PlayerSettings(musicVolume: 0.8)
        )
        XCTAssertThrowsError(try firstSettings.merged(with: secondSettings)) {
            error in
            XCTAssertEqual(
                error as? CloudProfileStampedMergeError,
                .equalStampDivergence
            )
        }

        var otherSelection = InventoryRules.initialSelection()
        otherSelection.selectedTeamID = LaunchTeamID.highMesaHelions
        let firstSelection = CloudProfileSelectionV1(
            binding: binding,
            stamp: stamp,
            selection: InventoryRules.initialSelection()
        )
        let secondSelection = CloudProfileSelectionV1(
            binding: binding,
            stamp: stamp,
            selection: otherSelection
        )
        XCTAssertThrowsError(try firstSelection.merged(with: secondSelection)) {
            error in
            XCTAssertEqual(
                error as? CloudProfileStampedMergeError,
                .equalStampDivergence
            )
        }
    }

    func testEqualOrderingKeyCanonicalizesInformationalDateCommutatively() throws {
        let binding = makeBinding()
        let early = try CloudProfileMergeStampV1(
            logicalCounter: 5,
            deviceID: "device-a",
            modifiedAt: Date(timeIntervalSince1970: 10)
        )
        let late = try CloudProfileMergeStampV1(
            logicalCounter: 5,
            deviceID: "device-a",
            modifiedAt: Date(timeIntervalSince1970: 20)
        )
        let left = CloudProfileSettingsV1(
            binding: binding,
            stamp: early,
            settings: PlayerSettings()
        )
        let right = CloudProfileSettingsV1(
            binding: binding,
            stamp: late,
            settings: PlayerSettings()
        )

        let forward = try left.merged(with: right)
        let reverse = try right.merged(with: left)
        XCTAssertEqual(forward, reverse)
        XCTAssertEqual(
            forward.stamp.modifiedAt,
            Date(timeIntervalSince1970: 20)
        )
        XCTAssertEqual(
            reverse.stamp.modifiedAt,
            Date(timeIntervalSince1970: 20)
        )
    }

    func testHigherLogicalStampWinsAndBindingMismatchFails() throws {
        let binding = makeBinding()
        let low = try CloudProfileMergeStampV1(
            logicalCounter: 1,
            deviceID: "z",
            modifiedAt: Date(timeIntervalSince1970: 999)
        )
        let high = try CloudProfileMergeStampV1(
            logicalCounter: 2,
            deviceID: "a",
            modifiedAt: Date(timeIntervalSince1970: 1)
        )
        let local = CloudProfileSettingsV1(
            binding: binding,
            stamp: low,
            settings: PlayerSettings(musicVolume: 0.1)
        )
        let remote = CloudProfileSettingsV1(
            binding: binding,
            stamp: high,
            settings: PlayerSettings(musicVolume: 0.9)
        )
        XCTAssertEqual(try local.merged(with: remote), remote)

        let otherBinding = CloudProfileBindingV1(
            cloudAccountID: CloudAccountID("other-cloud"),
            accountBinding: binding.accountBinding,
            profileAccountIdentity: binding.profileAccountIdentity
        )
        let mismatched = CloudProfileSettingsV1(
            binding: otherBinding,
            stamp: high,
            settings: remote.settings
        )
        XCTAssertThrowsError(try local.merged(with: mismatched)) { error in
            XCTAssertEqual(
                error as? CloudProfileStampedMergeError,
                .bindingMismatch
            )
        }
    }

    func testAllV1PayloadsRoundTrip() throws {
        let binding = makeBinding()
        let stamp = try CloudProfileMergeStampV1(
            logicalCounter: 7,
            deviceID: "device-a",
            modifiedAt: Date(timeIntervalSince1970: 100)
        )
        let run = try makeRunPayload(binding: binding)
        let configuration = try makeConfiguration()
        let accumulator = try CloudProfileRunAccumulatorV1.make(for: [
            CloudProfileRunAccumulatorEntryV1(
                logicalRecordID: configuration.runRecordID(for: run.runID),
                canonicalPayload: try CloudProfileCanonicalPayload.encode(run)
            ),
        ])
        let values: [any Codable] = [
            CloudProfileRootV1(
                binding: binding,
                economyHeadRecordID: CloudRecordID("economy-head"),
                rootRevision: 7,
                runAccumulator: accumulator
            ),
            CloudProfileSettingsV1(
                binding: binding,
                stamp: stamp,
                settings: PlayerSettings()
            ),
            CloudProfileSelectionV1(
                binding: binding,
                stamp: stamp,
                selection: InventoryRules.initialSelection()
            ),
            run,
        ]

        for value in values {
            XCTAssertFalse(try JSONEncoder().encode(value).isEmpty)
        }
        XCTAssertEqual(
            try roundTrip(run, as: CloudProfileCompletedRunV1.self),
            run
        )

        for value in [
            try CloudProfileCanonicalPayload.encode(
                CloudProfileSelectionV1(
                    binding: binding,
                    stamp: stamp,
                    selection: InventoryRules.initialSelection()
                )
            ),
            try CloudProfileCanonicalPayload.encode(run),
        ] {
            XCTAssertEqual(
                value,
                try JSONSerialization.data(
                    withJSONObject: JSONSerialization.jsonObject(with: value),
                    options: [.sortedKeys]
                )
            )
        }
    }

    func testCanonicalPayloadEncodedKeysAndGoldenBytesCoverEveryV1Payload()
        throws
    {
        let binding = makeBinding()
        let stamp = try CloudProfileMergeStampV1(
            logicalCounter: 7,
            deviceID: "device-a",
            modifiedAt: Date(timeIntervalSince1970: 100)
        )
        let root = CloudProfileRootV1(
            binding: binding,
            economyHeadRecordID: CloudRecordID("economy-head"),
            rootRevision: 7,
            runAccumulator: .empty
        )
        let settings = CloudProfileSettingsV1(
            binding: binding,
            stamp: stamp,
            settings: PlayerSettings()
        )
        let selection = CloudProfileSelectionV1(
            binding: binding,
            stamp: stamp,
            selection: InventoryRules.initialSelection()
        )
        let completedRun = try makeRunPayload(binding: binding)
        let payloads = try [
            CloudProfileCanonicalPayload.encode(root),
            CloudProfileCanonicalPayload.encode(settings),
            CloudProfileCanonicalPayload.encode(selection),
            CloudProfileCanonicalPayload.encode(completedRun),
        ]
        let objects = try payloads.map(jsonDictionary)

        XCTAssertEqual(Set(objects[0].keys), keySet(CloudProfileRootV1.persistedFieldManifest))
        XCTAssertEqual(
            Set(try dictionary(objects[0], key: "binding").keys),
            keySet(CloudProfileBindingV1.persistedFieldManifest)
        )
        let encodedBinding = try dictionary(objects[0], key: "binding")
        XCTAssertEqual(
            encodedBinding["cloudAccountID"] as? String,
            binding.cloudAccountID.rawValue
        )
        XCTAssertEqual(
            encodedBinding["profileAccountIdentity"] as? String,
            binding.profileAccountIdentity.rawValue
        )
        XCTAssertEqual(
            Set(try dictionary(objects[0], key: "runAccumulator").keys),
            keySet(CloudProfileRunAccumulatorV1.persistedFieldManifest)
        )
        XCTAssertEqual(
            Set(try dictionary(encodedBinding, key: "accountBinding").keys),
            keySet(DurableAccountBinding.persistedFieldManifest)
        )
        let encodedAccountBinding = try dictionary(
            encodedBinding,
            key: "accountBinding"
        )
        XCTAssertEqual(
            encodedAccountBinding["accountKey"] as? String,
            binding.accountBinding.accountKey.rawValue
        )
        XCTAssertEqual(
            (encodedAccountBinding["profileID"] as? String)?.lowercased(),
            binding.accountBinding.profileID.uuidString.lowercased()
        )
        XCTAssertEqual(
            objects[0]["economyHeadRecordID"] as? String,
            "economy-head"
        )

        XCTAssertEqual(Set(objects[1].keys), keySet(CloudProfileSettingsV1.persistedFieldManifest))
        XCTAssertEqual(
            Set(try dictionary(objects[1], key: "stamp").keys),
            keySet(CloudProfileMergeStampV1.persistedFieldManifest)
        )
        XCTAssertEqual(
            Set(try dictionary(objects[1], key: "settings").keys),
            keySet(PlayerSettings.persistedFieldManifest)
        )

        XCTAssertEqual(Set(objects[2].keys), keySet(CloudProfileSelectionV1.persistedFieldManifest))
        XCTAssertEqual(
            Set(try dictionary(objects[2], key: "selection").keys),
            keySet(PlayerSelection.persistedFieldManifest)
        )
        let encodedSelection = try dictionary(objects[2], key: "selection")
        XCTAssertEqual(
            encodedSelection["selectedTeamID"] as? String,
            selection.selection.selectedTeamID.rawValue
        )
        XCTAssertEqual(
            encodedSelection["selectedFootballID"] as? String,
            selection.selection.selectedFootballID.rawValue
        )
        let jerseyPairs = try XCTUnwrap(
            encodedSelection["selectedJerseyByTeam"] as? [String]
        )
        XCTAssertEqual(
            jerseyPairs.count,
            selection.selection.selectedJerseyByTeam.count * 2
        )
        XCTAssertEqual(
            Set(stride(from: 0, to: jerseyPairs.count, by: 2).map {
                jerseyPairs[$0]
            }),
            Set(selection.selection.selectedJerseyByTeam.keys.map(\.rawValue))
        )
        XCTAssertEqual(
            Set(stride(from: 1, to: jerseyPairs.count, by: 2).map {
                jerseyPairs[$0]
            }),
            Set(selection.selection.selectedJerseyByTeam.values.map(\.rawValue))
        )

        XCTAssertEqual(
            Set(objects[3].keys),
            keySet(CloudProfileCompletedRunV1.persistedFieldManifest)
        )
        let record = try dictionary(objects[3], key: "record")
        XCTAssertEqual(Set(record.keys), keySet(CompletedRunRecord.persistedFieldManifest))
        let run = try dictionary(record, key: "run")
        XCTAssertEqual(Set(run.keys), keySet(CompletedRun.persistedFieldManifest))
        XCTAssertEqual(
            run["finishReason"] as? String,
            RunFinishReason.timerExpired.rawValue
        )
        _ = try XCTUnwrap(run["completedLaneIDs"] as? [String])
        let encodedRunConfiguration = try dictionary(run, key: "configuration")
        let encodedRunID = try dictionary(
            encodedRunConfiguration,
            key: "runID"
        )
        XCTAssertEqual(Set(encodedRunID.keys), ["rawValue"])
        XCTAssertEqual(
            (encodedRunID["rawValue"] as? String)?.lowercased(),
            completedRun.runID.rawValue.uuidString.lowercased()
        )
        XCTAssertEqual(
            encodedRunConfiguration["offenseTeamID"] as? String,
            completedRun.record.run.configuration.offenseTeamID.rawValue
        )
        XCTAssertEqual(
            encodedRunConfiguration["offenseJerseyID"] as? String,
            completedRun.record.run.configuration.offenseJerseyID.rawValue
        )
        XCTAssertEqual(
            encodedRunConfiguration["defenseTeamID"] as? String,
            completedRun.record.run.configuration.defenseTeamID.rawValue
        )
        XCTAssertEqual(
            encodedRunConfiguration["defenseJerseyID"] as? String,
            completedRun.record.run.configuration.defenseJerseyID.rawValue
        )
        XCTAssertEqual(
            encodedRunConfiguration["footballID"] as? String,
            completedRun.record.run.configuration.footballID.rawValue
        )
        XCTAssertEqual(
            Set(try dictionary(run, key: "configuration").keys),
            keySet(RunConfiguration.persistedFieldManifest)
        )
        XCTAssertEqual(
            Set(try dictionary(run, key: "statistics").keys),
            keySet(RunStatisticsSnapshot.persistedFieldManifest)
        )
        XCTAssertEqual(
            Set(try dictionary(objects[3], key: "rewardedRunObservation").keys),
            keySet(RewardedRunObservation.persistedFieldManifest)
        )
        XCTAssertEqual(
            try dictionary(objects[3], key: "rewardedRunObservation")[
                "disposition"
            ] as? String,
            RewardedRunObservation.Disposition.candidate.rawValue
        )

        XCTAssertEqual(
            payloads.map {
                CloudProfileDigest.hex(
                    CloudProfileDigest.sha256(dataComponents: [$0])
                )
            },
            [
                "43ae9e723718f27a0a5f0c4c3dee93125dd448237b71e0009cb35f6efdcfed22",
                "0285613b029667a14d7b03be9f52009a28710d4c1da958f0bc2ab289f6ee2960",
                "f4ca1eeca6382dcc372a4f4fa881a0cc7956918b2fd34b688eeebd59c335b479",
                "0aec2fb941dd4873f0901d65a6288f558bbc92a3995f76c18db1e3fa978ee2db",
            ]
        )
    }
}

private extension CloudProfileSchemaTests {
    func makeConfiguration() throws -> CloudProfileSchemaConfiguration {
        try CloudProfileSchemaConfiguration(
            rootRecordType: "ProfileRoot",
            settingsRecordType: "ProfileSettings",
            selectionRecordType: "ProfileSelection",
            runRecordType: "CompletedRun",
            payloadFieldName: "payload"
        )
    }

    func makeBinding() -> CloudProfileBindingV1 {
        CloudProfileBindingV1(
            cloudAccountID: CloudAccountID("cloud-account"),
            accountBinding: DurableAccountBinding(
                accountKey: ServiceAccountKey("service-account"),
                profileID: UUID(
                    uuidString: "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
                )!
            ),
            profileAccountIdentity: PlayerAccountIdentity("player-account")
        )
    }

    func makeRunPayload(
        binding: CloudProfileBindingV1
    ) throws -> CloudProfileCompletedRunV1 {
        let catalog = LaunchCatalog.approved
        let offense = try XCTUnwrap(catalog.team(id: LaunchTeamID.novaCityComets))
        let defense = try XCTUnwrap(catalog.team(id: LaunchTeamID.highMesaHelions))
        let startedAt = Date(timeIntervalSince1970: 1_000)
        let run = CompletedRun(
            configuration: RunConfiguration(
                runID: RunID(
                    UUID(
                        uuidString: "33333333-3333-4333-8333-333333333333"
                    )!
                ),
                randomSeed: 42,
                offenseTeamID: offense.id,
                offenseJerseyID: offense.primaryJersey.id,
                defenseTeamID: defense.id,
                defenseJerseyID: defense.primaryJersey.id,
                footballID: LaunchFootballID.standard,
                economyVersion: 1,
                startedAt: startedAt
            ),
            endedAt: startedAt.addingTimeInterval(60),
            elapsedGameplayMilliseconds: 60_000,
            finishReason: .timerExpired,
            score: 1_000,
            statistics: RunStatisticsSnapshot(
                attempts: 3,
                completions: 3,
                touchdowns: 0,
                incompletions: 0,
                interceptions: 0,
                longestTouchdownStreak: 0
            ),
            completedLaneIDs: [],
            bonusTouchdownCount: 0
        )
        return CloudProfileCompletedRunV1(
            binding: binding,
            record: CompletedRunRecord(
                run: run,
                recordedAt: startedAt.addingTimeInterval(61),
                rewardCoins: try CompletedRunValidator.rewardCoins(for: run)
            ),
            rewardedRunObservation: RewardedRunObservation(
                observedCycle: 0,
                disposition: .candidate
            )
        )
    }

    func roundTrip<T: Codable & Equatable>(
        _ value: T,
        as type: T.Type
    ) throws -> T {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(type, from: data)
    }

    func jsonDictionary(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
    }

    func dictionary(
        _ object: [String: Any],
        key: String
    ) throws -> [String: Any] {
        try XCTUnwrap(object[key] as? [String: Any])
    }

    func keySet(_ manifest: String) -> Set<String> {
        Set(manifest.split(separator: ",").map(String.init))
    }
}

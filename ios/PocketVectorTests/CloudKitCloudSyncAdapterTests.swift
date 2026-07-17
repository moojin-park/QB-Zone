import CryptoKit
import Foundation
@preconcurrency import CloudKit
import XCTest

@testable import PocketVector

final class CloudKitCloudSyncAdapterTests: XCTestCase, @unchecked Sendable {
    func testConfigurationRequiresAllProductionSchemaIdentifiers() throws {
        XCTAssertThrowsError(
            try CloudKitCloudSyncConfiguration._testOnly(
                containerIdentifier: "",
                containerEnvironment: .development,
                zoneName: "TestZone",
                payloadFieldName: "payload",
                operationRecordType: "Operation",
                accountIdentifierNamespace: "account-namespace",
                recordNameNamespace: "record-namespace"
            )
        ) { error in
            XCTAssertEqual(
                error as? CloudKitCloudSyncConfigurationError,
                .emptyContainerIdentifier
            )
        }
        XCTAssertThrowsError(
            try CloudKitCloudSyncConfiguration._testOnly(
                containerIdentifier: "iCloud.test.container",
                containerEnvironment: .development,
                zoneName: "TestZone",
                payloadFieldName: "invalid-field-name",
                operationRecordType: "Operation",
                accountIdentifierNamespace: "account-namespace",
                recordNameNamespace: "record-namespace"
            )
        ) { error in
            XCTAssertEqual(
                error as? CloudKitCloudSyncConfigurationError,
                .invalidPayloadFieldName
            )
        }
    }

    func testTransportFingerprintMaterialBindsExactSchemaAndAddressContracts()
        throws
    {
        let configuration = try CloudKitCloudSyncConfiguration._testOnly(
            containerIdentifier: "iCloud.test.container",
            containerEnvironment: .development,
            zoneName: "TestZone",
            payloadFieldName: "payload",
            operationRecordType: "OperationMarker",
            accountIdentifierNamespace: "account-namespace",
            recordNameNamespace: "record-namespace"
        )

        XCTAssertEqual(
            configuration.fingerprintMaterial,
            [
                "pocket-vector-cloudkit-transport-schema-v2",
                "containerIdentifier", "iCloud.test.container",
                "containerEnvironment", "Development",
                "zoneName", "TestZone",
                "payloadFieldName", "payload",
                "operationRecordType", "OperationMarker",
                "accountIdentifierNamespace", "account-namespace",
                "recordNameNamespace", "record-namespace",
                "recordEnvelopeSchemaVersion", "3",
                "recordEnvelopeFields",
                "fields,lastOperationFingerprint,logicalRecordID,schemaVersion",
                "operationMarkerSchemaVersion", "2",
                "operationMarkerFields",
                "requestFingerprint,schemaVersion,targetRecordNames",
                "payloadEncoding",
                "sorted-key-json-default-keys-without-escaped-slashes-deferred-date-base64-data-nonfinite-float-throw-v1",
                "databaseScope", "private",
                "zoneOwner", "current-user-default",
                "opaqueIdentifierDomain",
                "pocket-vector-cloudkit-opaque-id-v1",
                "recordAddressKind", "record-v1",
                "accountAddressKind", "account-v1",
                "operationAddressKind", "operation-v1",
                "operationFingerprintDomain",
                "pocket-vector-cloudkit-request-v2",
                "opaqueAddressPolicy",
                "domain-namespace-kind-value-stable-digest-lowercase-hex-v1",
                "operationFingerprintPolicy",
                "account-operation-count-framed-writes-by-id-count-framed-fields-by-key-precondition-and-bytes-v2",
                "orderingPolicy", "utf8-byte-lexicographic-ascending-v1",
                "preconditionCases", "change-tag(rawValue),must-not-exist,none",
                "digestAlgorithm", "sha256-v1",
                "digestComponentEncoding",
                "uint64-big-endian-length-prefixed-bytes-v1",
                "operationFingerprintCountEncoding",
                "uint64-big-endian-as-length-prefixed-eight-byte-component-v1",
                "digestHexEncoding", "lowercase-two-digit-hex-per-byte-v1",
            ]
        )
    }

    func testScopedCheckpointFetcherBindsCompleteProductionConfiguration()
        throws
    {
        let base = try productionConfiguration()
        let alternateZone = try productionConfiguration(zoneName: "OtherZone")
        let alternateContainer = try productionConfiguration(
            containerIdentifier: "iCloud.test.other-container"
        )
        let alternateEnvironment = try productionConfiguration(
            containerEnvironment: .production
        )
        let alternateProfile = try productionConfiguration(
            profilePayloadFieldName: "otherProfilePayload"
        )

        let fakeChangeFetcher = CloudKitCloudSyncTransport(
            configuration: base.transport,
            client: FakeCloudKitPrivateDatabaseClient(
                userRecordName: "provider-user-a"
            )
        )
        let scopedBase = CloudReplicaScopedChangeFetcherV1._testOnly(
            configuration: base,
            changeFetcher: fakeChangeFetcher
        )
        let scopedZone = CloudReplicaScopedChangeFetcherV1._testOnly(
            configuration: alternateZone,
            changeFetcher: fakeChangeFetcher
        )
        let scopedContainer = CloudReplicaScopedChangeFetcherV1._testOnly(
            configuration: alternateContainer,
            changeFetcher: fakeChangeFetcher
        )
        let scopedEnvironment = CloudReplicaScopedChangeFetcherV1._testOnly(
            configuration: alternateEnvironment,
            changeFetcher: fakeChangeFetcher
        )
        XCTAssertEqual(
            scopedBase.configurationScopeFingerprint,
            CloudReplicaScopeFingerprint.make(for: base)
        )
        XCTAssertEqual(
            scopedZone.configurationScopeFingerprint,
            CloudReplicaScopeFingerprint.make(for: alternateZone)
        )
        XCTAssertEqual(
            scopedContainer.configurationScopeFingerprint,
            CloudReplicaScopeFingerprint.make(for: alternateContainer)
        )
        XCTAssertNotEqual(
            scopedBase.configurationScopeFingerprint,
            scopedZone.configurationScopeFingerprint
        )
        XCTAssertNotEqual(
            scopedBase.configurationScopeFingerprint,
            scopedContainer.configurationScopeFingerprint
        )
        XCTAssertNotEqual(
            scopedBase.configurationScopeFingerprint,
            scopedEnvironment.configurationScopeFingerprint
        )

        let injectedTransport = CloudKitCloudSyncTransport(
            configuration: alternateProfile.transport,
            client: FakeCloudKitPrivateDatabaseClient(
                userRecordName: "provider-user-a"
            )
        )
        let debugFetcher = CloudReplicaScopedChangeFetcherV1._testOnly(
            configuration: alternateProfile,
            changeFetcher: injectedTransport
        )
        XCTAssertEqual(
            debugFetcher.configurationScopeFingerprint,
            CloudReplicaScopeFingerprint.make(for: alternateProfile)
        )
        XCTAssertNotEqual(
            debugFetcher.configurationScopeFingerprint,
            scopedBase.configurationScopeFingerprint
        )
    }

    func testAddressAndPayloadCodecGoldenVectorsBindActualStoredBytes()
        async throws
    {
        let client = FakeCloudKitPrivateDatabaseClient(
            userRecordName: "provider-user-a"
        )
        let transport = try makeTransport(client: client)
        let accountID = try await availableAccountID(transport)
        _ = try await transport.commitAtomically(
            writeRequest(
                accountID: accountID,
                operationID: "operation/golden-v1",
                writes: [
                    write(
                        id: "record/golden-v1",
                        value: "value/with/slashes",
                        precondition: .mustNotExist
                    ),
                ]
            )
        )

        let records = await client.recordsForUser("provider-user-a")
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(
            accountID.rawValue,
            "4ee89b5253341886aed65e94c6255b3f3a4498dae536ba27d3ea7e19c586d895"
        )
        XCTAssertEqual(
            Set(records.map(\.recordName)),
            [
                "cbec03de07a8eaf1976e545e1afe7bcf36bfe3de38b845d6ca5f35509009ea41",
                "a95bc95028abe42cbab1ae4d87d68e9d3ea582157aac6d30c2d98720c3ba7d31",
            ]
        )

        var payloadDigests: [String: String] = [:]
        for record in records {
            let object = try XCTUnwrap(
                JSONSerialization.jsonObject(with: record.payload)
                    as? [String: Any]
            )
            let expectedKeys = record.recordType == "OperationMarker"
                ? Set(["requestFingerprint", "schemaVersion", "targetRecordNames"])
                : Set([
                    "fields", "lastOperationFingerprint", "logicalRecordID",
                    "schemaVersion",
                ])
            XCTAssertEqual(Set(object.keys), expectedKeys)
            payloadDigests[record.recordType] = Data(
                SHA256.hash(data: record.payload)
            ).map { String(format: "%02x", $0) }.joined()
        }
        XCTAssertEqual(
            payloadDigests,
            [
                "OperationMarker":
                    "52aff05fa8eb429cc5f4247c1a33da910b7cbcca635083e13d7b0daddc4ab9d3",
                "TestRecord":
                    "abc1e0c7cbd27c5f9a5229b9159e2bcaec7693ff0bf504abacca155ff10e0ccd",
            ]
        )
    }

    func testAccountIdentityIsStableOpaqueAndChangesWithProviderAccount() async throws {
        let client = FakeCloudKitPrivateDatabaseClient(userRecordName: "provider-user-a")
        let transport = try makeTransport(client: client)

        let first = try await availableAccountID(transport)
        let second = try await availableAccountID(transport)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.rawValue.count, 64)
        XCTAssertFalse(first.rawValue.contains("provider-user-a"))

        await client.setUserRecordName("provider-user-b")
        let switched = try await availableAccountID(transport)
        XCTAssertNotEqual(first, switched)

        await client.setUserRecordName("provider-user-a")
        let restored = try await availableAccountID(transport)
        XCTAssertEqual(restored, first)
    }

    func testAtomicCommitRoundTripsFieldsAndRetryUsesDurableOperationMarker() async throws {
        let client = FakeCloudKitPrivateDatabaseClient(userRecordName: "provider-user-a")
        let transport = try makeTransport(client: client)
        let accountID = try await availableAccountID(transport)
        let request = writeRequest(
            accountID: accountID,
            operationID: "grant/provider-transaction-secret",
            writes: [
                write(
                    id: "ledger/provider-transaction-secret",
                    value: "credited",
                    precondition: .mustNotExist
                ),
            ]
        )

        let first = try await transport.commitAtomically(request)
        let retried = try await transport.commitAtomically(request)
        let saveCount = await client.successfulSaveCount()

        XCTAssertEqual(first, retried)
        XCTAssertEqual(saveCount, 1)
        let fetched = try await transport.records(
            accountID: accountID,
            ids: [CloudRecordID("ledger/provider-transaction-secret")]
        )
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].fields["value"], Data("credited".utf8))

        let observedNames = await client.observedRecordNames()
        XCTAssertEqual(observedNames.count, 2)
        XCTAssertTrue(observedNames.allSatisfy { $0.count == 64 })
        XCTAssertTrue(
            observedNames.allSatisfy {
                !$0.contains("provider") && !$0.contains("transaction")
            }
        )
    }

    func testLostServerResponseRecoversCommittedReceiptWithoutSecondGrant() async throws {
        let client = FakeCloudKitPrivateDatabaseClient(userRecordName: "provider-user-a")
        let transport = try makeTransport(client: client)
        let accountID = try await availableAccountID(transport)
        let request = writeRequest(
            accountID: accountID,
            operationID: "grant-1",
            writes: [write(id: "economy-head", value: "one", precondition: .mustNotExist)]
        )
        await client.loseResponseAfterNextSuccessfulSave()

        let recovered = try await transport.commitAtomically(request)
        let saveCount = await client.successfulSaveCount()
        let stored = try await transport.records(
            accountID: accountID,
            ids: [CloudRecordID("economy-head")]
        )

        XCTAssertEqual(recovered.operationID, request.operationID)
        XCTAssertNotNil(recovered.savedChangeTags[CloudRecordID("economy-head")])
        XCTAssertEqual(saveCount, 1)
        XCTAssertEqual(stored.first?.fields["value"], Data("one".utf8))
    }

    func testOperationIDCollisionCannotReplayDifferentPayload() async throws {
        let client = FakeCloudKitPrivateDatabaseClient(userRecordName: "provider-user-a")
        let transport = try makeTransport(client: client)
        let accountID = try await availableAccountID(transport)
        let first = writeRequest(
            accountID: accountID,
            operationID: "operation-1",
            writes: [write(id: "economy-head", value: "one", precondition: .mustNotExist)]
        )
        _ = try await transport.commitAtomically(first)
        let collision = writeRequest(
            accountID: accountID,
            operationID: "operation-1",
            writes: [write(id: "economy-head", value: "different", precondition: .none)]
        )

        do {
            _ = try await transport.commitAtomically(collision)
            XCTFail("Expected operation ID collision")
        } catch let error as CloudSyncTransportError {
            XCTAssertEqual(error, .operationIDCollision(OperationID("operation-1")))
        }
        let saveCount = await client.successfulSaveCount()
        XCTAssertEqual(saveCount, 1)
    }

    func testWriteCountFramingSeparatesLegacyTwoWriteVersusOneWriteCollision()
        async throws
    {
        let twoWriteClient = FakeCloudKitPrivateDatabaseClient(
            userRecordName: "provider-user-a"
        )
        let oneWriteClient = FakeCloudKitPrivateDatabaseClient(
            userRecordName: "provider-user-a"
        )
        let twoWriteTransport = try makeTransport(client: twoWriteClient)
        let oneWriteTransport = try makeTransport(client: oneWriteClient)
        let accountID = try await availableAccountID(twoWriteTransport)
        let oneWriteAccountID = try await availableAccountID(oneWriteTransport)
        XCTAssertEqual(accountID, oneWriteAccountID)

        let seedWrites = [
            CloudRecordWrite(
                id: CloudRecordID("0"),
                recordType: "R",
                fields: ["seed": Data("zero".utf8)],
                precondition: .mustNotExist
            ),
            CloudRecordWrite(
                id: CloudRecordID("a"),
                recordType: "E",
                fields: ["seed": Data("alpha".utf8)],
                precondition: .mustNotExist
            ),
        ]
        let twoSeed = try await twoWriteTransport.commitAtomically(
            writeRequest(
                accountID: accountID,
                operationID: "seed-boundary-fixture",
                writes: seedWrites
            )
        )
        let oneSeed = try await oneWriteTransport.commitAtomically(
            writeRequest(
                accountID: accountID,
                operationID: "seed-boundary-fixture",
                writes: seedWrites
            )
        )
        XCTAssertEqual(twoSeed.savedChangeTags, oneSeed.savedChangeTags)
        let zeroTag = try XCTUnwrap(twoSeed.savedChangeTags[CloudRecordID("0")])
        let alphaTag = try XCTUnwrap(twoSeed.savedChangeTags[CloudRecordID("a")])

        // Without collection counts, both requests append the same component
        // stream: 0,R,change-tag,zeroTag,a,E,change-tag,alphaTag. The one-write
        // request disguises the second write as two field key/value pairs.
        let operationID = "legacy-flat-boundary-collision"
        let twoWrites = writeRequest(
            accountID: accountID,
            operationID: operationID,
            writes: [
                CloudRecordWrite(
                    id: CloudRecordID("0"),
                    recordType: "R",
                    fields: [:],
                    precondition: .changeTag(zeroTag)
                ),
                CloudRecordWrite(
                    id: CloudRecordID("a"),
                    recordType: "E",
                    fields: [:],
                    precondition: .changeTag(alphaTag)
                ),
            ]
        )
        let oneWrite = writeRequest(
            accountID: accountID,
            operationID: operationID,
            writes: [
                CloudRecordWrite(
                    id: CloudRecordID("0"),
                    recordType: "R",
                    fields: [
                        "a": Data("E".utf8),
                        "change-tag": Data(alphaTag.rawValue.utf8),
                    ],
                    precondition: .changeTag(zeroTag)
                ),
            ]
        )

        let twoPreOperationNames = Set(
            await twoWriteClient.recordsForUser("provider-user-a")
                .map(\.recordName)
        )
        let onePreOperationNames = Set(
            await oneWriteClient.recordsForUser("provider-user-a")
                .map(\.recordName)
        )
        _ = try await twoWriteTransport.commitAtomically(twoWrites)
        _ = try await oneWriteTransport.commitAtomically(oneWrite)

        let twoStoredRecords = await twoWriteClient.recordsForUser(
            "provider-user-a"
        )
        let oneStoredRecords = await oneWriteClient.recordsForUser(
            "provider-user-a"
        )
        let twoMarker = try XCTUnwrap(
            twoStoredRecords
                .filter {
                    $0.recordType == "OperationMarker"
                        && !twoPreOperationNames.contains($0.recordName)
                }
                .compactMap {
                    try? JSONDecoder().decode(
                        TestCloudKitOperationMarkerV2.self,
                        from: $0.payload
                    )
                }
                .first { $0.targetRecordNames.count == 2 }
        )
        let oneMarker = try XCTUnwrap(
            oneStoredRecords
                .filter {
                    $0.recordType == "OperationMarker"
                        && !onePreOperationNames.contains($0.recordName)
                }
                .compactMap {
                    try? JSONDecoder().decode(
                        TestCloudKitOperationMarkerV2.self,
                        from: $0.payload
                    )
                }
                .first { $0.targetRecordNames.count == 1 }
        )
        XCTAssertNotEqual(
            twoMarker.requestFingerprint,
            oneMarker.requestFingerprint
        )

    }

    func testFieldCountFramingRejectsSameTargetLegacyBoundaryShiftReplay()
        async throws
    {
        let firstClient = FakeCloudKitPrivateDatabaseClient(
            userRecordName: "provider-user-a"
        )
        let secondClient = FakeCloudKitPrivateDatabaseClient(
            userRecordName: "provider-user-a"
        )
        let firstTransport = try makeTransport(client: firstClient)
        let secondTransport = try makeTransport(client: secondClient)
        let accountID = try await availableAccountID(firstTransport)
        let secondAccountID = try await availableAccountID(secondTransport)
        XCTAssertEqual(accountID, secondAccountID)

        let seedWrites = [
            CloudRecordWrite(
                id: CloudRecordID("0"),
                recordType: "R",
                fields: ["seed": Data("zero".utf8)],
                precondition: .mustNotExist
            ),
            CloudRecordWrite(
                id: CloudRecordID("a"),
                recordType: "E",
                fields: ["seed": Data("alpha".utf8)],
                precondition: .mustNotExist
            ),
        ]
        let firstSeed = try await firstTransport.commitAtomically(
            writeRequest(
                accountID: accountID,
                operationID: "seed-same-target-boundary-fixture",
                writes: seedWrites
            )
        )
        let secondSeed = try await secondTransport.commitAtomically(
            writeRequest(
                accountID: accountID,
                operationID: "seed-same-target-boundary-fixture",
                writes: seedWrites
            )
        )
        XCTAssertEqual(firstSeed.savedChangeTags, secondSeed.savedChangeTags)
        let zeroTag = try XCTUnwrap(firstSeed.savedChangeTags[CloudRecordID("0")])
        let alphaTag = try XCTUnwrap(firstSeed.savedChangeTags[CloudRecordID("a")])
        let mimicFields = [
            "a": Data("E".utf8),
            "change-tag": Data(alphaTag.rawValue.utf8),
        ]
        let operationID = "same-target-legacy-boundary-shift"

        // Both requests target {0,a}. Without a field count on each write,
        // their sorted legacy component streams are both P_A,P_B,P_B: one
        // assigns the mimic fields to `a`; the other assigns them to `0`.
        let firstRequest = writeRequest(
            accountID: accountID,
            operationID: operationID,
            writes: [
                CloudRecordWrite(
                    id: CloudRecordID("0"),
                    recordType: "R",
                    fields: [:],
                    precondition: .changeTag(zeroTag)
                ),
                CloudRecordWrite(
                    id: CloudRecordID("a"),
                    recordType: "E",
                    fields: mimicFields,
                    precondition: .changeTag(alphaTag)
                ),
            ]
        )
        let secondRequest = writeRequest(
            accountID: accountID,
            operationID: operationID,
            writes: [
                CloudRecordWrite(
                    id: CloudRecordID("0"),
                    recordType: "R",
                    fields: mimicFields,
                    precondition: .changeTag(zeroTag)
                ),
                CloudRecordWrite(
                    id: CloudRecordID("a"),
                    recordType: "E",
                    fields: [:],
                    precondition: .changeTag(alphaTag)
                ),
            ]
        )

        let firstPreOperationNames = Set(
            await firstClient.recordsForUser("provider-user-a")
                .map(\.recordName)
        )
        let secondPreOperationNames = Set(
            await secondClient.recordsForUser("provider-user-a")
                .map(\.recordName)
        )
        _ = try await firstTransport.commitAtomically(firstRequest)
        _ = try await secondTransport.commitAtomically(secondRequest)

        let decodedFirstMarker = await operationMarker(
            in: firstClient,
            excluding: firstPreOperationNames
        )
        let decodedSecondMarker = await operationMarker(
            in: secondClient,
            excluding: secondPreOperationNames
        )
        let firstMarker = try XCTUnwrap(decodedFirstMarker)
        let secondMarker = try XCTUnwrap(decodedSecondMarker)
        XCTAssertEqual(
            firstMarker.targetRecordNames,
            secondMarker.targetRecordNames
        )
        XCTAssertNotEqual(
            firstMarker.requestFingerprint,
            secondMarker.requestFingerprint
        )

        do {
            _ = try await firstTransport.commitAtomically(secondRequest)
            XCTFail("A same-target structural boundary shift must not replay")
        } catch let error as CloudSyncTransportError {
            XCTAssertEqual(
                error,
                .operationIDCollision(OperationID(operationID))
            )
        }
        let successfulSaveCount = await firstClient.successfulSaveCount()
        XCTAssertEqual(successfulSaveCount, 2)
        let stored = try await firstTransport.records(
            accountID: accountID,
            ids: [CloudRecordID("0"), CloudRecordID("a")]
        )
        XCTAssertEqual(stored.first { $0.id == CloudRecordID("0") }?.fields, [:])
        XCTAssertEqual(
            stored.first { $0.id == CloudRecordID("a") }?.fields,
            mimicFields
        )
    }

    func testChangeTagConflictsAreSortedAndNeverOverwriteServerRecords() async throws {
        let client = FakeCloudKitPrivateDatabaseClient(userRecordName: "provider-user-a")
        let transport = try makeTransport(client: client)
        let accountID = try await availableAccountID(transport)
        let seed = writeRequest(
            accountID: accountID,
            operationID: "seed",
            writes: [
                write(id: "record-b", value: "server-b", precondition: .mustNotExist),
                write(id: "record-a", value: "server-a", precondition: .mustNotExist),
            ]
        )
        _ = try await transport.commitAtomically(seed)
        let stale = writeRequest(
            accountID: accountID,
            operationID: "stale",
            writes: [
                write(
                    id: "record-b",
                    value: "stale-b",
                    precondition: .changeTag(CloudChangeTag("stale-tag"))
                ),
                write(
                    id: "record-a",
                    value: "stale-a",
                    precondition: .changeTag(CloudChangeTag("stale-tag"))
                ),
            ]
        )

        do {
            _ = try await transport.commitAtomically(stale)
            XCTFail("Expected deterministic conflict")
        } catch let error as CloudSyncTransportError {
            XCTAssertEqual(
                error,
                .conflict([CloudRecordID("record-a"), CloudRecordID("record-b")])
            )
        }

        let records = try await transport.records(
            accountID: accountID,
            ids: [CloudRecordID("record-a"), CloudRecordID("record-b")]
        )
        XCTAssertEqual(records[0].fields["value"], Data("server-a".utf8))
        XCTAssertEqual(records[1].fields["value"], Data("server-b".utf8))
    }

    func testAccountSwitchBetweenReadAndCommitRejectsOldSessionBeforeMutation() async throws {
        let client = FakeCloudKitPrivateDatabaseClient(userRecordName: "provider-user-a")
        let transport = try makeTransport(client: client)
        let accountA = try await availableAccountID(transport)
        await client.switchUserAfterNextFetch(to: "provider-user-b")
        let request = writeRequest(
            accountID: accountA,
            operationID: "old-account-operation",
            writes: [write(id: "economy-head", value: "one", precondition: .mustNotExist)]
        )

        do {
            _ = try await transport.commitAtomically(request)
            XCTFail("Expected account switch rejection")
        } catch let error as CloudSyncTransportError {
            XCTAssertEqual(error, .accountMismatch)
        }
        let saveCount = await client.successfulSaveCount()
        let switchedAccountRecords = await client.recordsForUser("provider-user-b")
        XCTAssertEqual(saveCount, 0)
        XCTAssertTrue(switchedAccountRecords.isEmpty)
    }

    func testAccountSwitchImmediatelyBeforeSaveCannotWriteOldPayloadIntoNewAccount() async throws {
        let client = FakeCloudKitPrivateDatabaseClient(userRecordName: "provider-user-a")
        let transport = try makeTransport(client: client)
        let accountA = try await availableAccountID(transport)
        await client.switchUserImmediatelyBeforeNextSave(to: "provider-user-b")
        let request = writeRequest(
            accountID: accountA,
            operationID: "old-account-save-race",
            writes: [write(id: "economy-head", value: "secret-a", precondition: .mustNotExist)]
        )

        do {
            _ = try await transport.commitAtomically(request)
            XCTFail("Expected account-bound save rejection")
        } catch let error as CloudSyncTransportError {
            XCTAssertEqual(error, .accountMismatch)
        }

        let saveCount = await client.successfulSaveCount()
        let accountARecords = await client.recordsForUser("provider-user-a")
        let accountBRecords = await client.recordsForUser("provider-user-b")
        XCTAssertEqual(saveCount, 0)
        XCTAssertTrue(accountARecords.isEmpty)
        XCTAssertTrue(accountBRecords.isEmpty)
    }

    func testOrdinaryWriteCannotUseReservedOperationRecordType() async throws {
        let client = FakeCloudKitPrivateDatabaseClient(userRecordName: "provider-user-a")
        let transport = try makeTransport(client: client)
        let accountID = try await availableAccountID(transport)
        let request = writeRequest(
            accountID: accountID,
            operationID: "reserved-record-type",
            writes: [
                CloudRecordWrite(
                    id: CloudRecordID("economy-head"),
                    recordType: "OperationMarker",
                    fields: ["value": Data("one".utf8)],
                    precondition: .mustNotExist
                ),
            ]
        )

        do {
            _ = try await transport.commitAtomically(request)
            XCTFail("Expected reserved record-type rejection")
        } catch let error as CloudKitCloudSyncError {
            XCTAssertEqual(error, .invalidRequest)
        }

        let saveCount = await client.successfulSaveCount()
        let records = await client.recordsForUser("provider-user-a")
        XCTAssertEqual(saveCount, 0)
        XCTAssertTrue(records.isEmpty)
    }

    func testTransientFailuresExposeDeterministicRetryPolicyWithoutSDKDetails() async throws {
        let client = FakeCloudKitPrivateDatabaseClient(userRecordName: "provider-user-a")
        let transport = try makeTransport(client: client)
        let accountID = try await availableAccountID(transport)
        await client.failNextFetch(
            with: .networkUnavailable(retryAfterSeconds: 7)
        )

        do {
            _ = try await transport.records(
                accountID: accountID,
                ids: [CloudRecordID("profile")]
            )
            XCTFail("Expected retryable network failure")
        } catch let error as CloudKitCloudSyncError {
            XCTAssertEqual(error, .networkUnavailable(retryAfterSeconds: 7))
            XCTAssertEqual(error.recovery, .retry(afterSeconds: 7))
            XCTAssertFalse((error.errorDescription ?? "").contains("provider-user-a"))
        }
    }

    func testTemporarilyUnavailableAccountDoesNotLookSignedOutOrDeleteLocalContext() async throws {
        let client = FakeCloudKitPrivateDatabaseClient(userRecordName: "provider-user-a")
        let transport = try makeTransport(client: client)
        let accountID = try await availableAccountID(transport)
        await client.setAccountStatus(.temporarilyUnavailable)
        let accountState = await transport.accountState()

        XCTAssertEqual(accountState, .unknown)
        do {
            _ = try await transport.records(
                accountID: accountID,
                ids: [CloudRecordID("profile")]
            )
            XCTFail("Expected temporary account state")
        } catch let error as CloudKitCloudSyncError {
            XCTAssertEqual(error, .accountTemporarilyUnavailable)
            XCTAssertEqual(error.recovery, .waitForAccountChange)
        }
    }

    func testSupersededLostReceiptReportsCommittedRefreshInsteadOfRegranting() async throws {
        let client = FakeCloudKitPrivateDatabaseClient(userRecordName: "provider-user-a")
        let transport = try makeTransport(client: client)
        let accountID = try await availableAccountID(transport)
        let firstRequest = writeRequest(
            accountID: accountID,
            operationID: "operation-1",
            writes: [write(id: "economy-head", value: "one", precondition: .mustNotExist)]
        )
        let first = try await transport.commitAtomically(firstRequest)
        let firstTag = try XCTUnwrap(first.savedChangeTags[CloudRecordID("economy-head")])
        let secondRequest = writeRequest(
            accountID: accountID,
            operationID: "operation-2",
            writes: [
                write(
                    id: "economy-head",
                    value: "two",
                    precondition: .changeTag(firstTag)
                ),
            ]
        )
        _ = try await transport.commitAtomically(secondRequest)

        do {
            _ = try await transport.commitAtomically(firstRequest)
            XCTFail("Expected committed-operation refresh handoff")
        } catch let error as CloudKitCloudSyncError {
            XCTAssertEqual(
                error,
                .committedOperationRequiresRefresh(
                    operationID: OperationID("operation-1"),
                    recordIDs: [CloudRecordID("economy-head")]
                )
            )
            XCTAssertEqual(
                error.recovery,
                .refreshCommittedOperation(recordIDs: [CloudRecordID("economy-head")])
            )
        }
        let saveCount = await client.successfulSaveCount()
        XCTAssertEqual(saveCount, 2)
    }

    func testSDKClassifierDropsSensitiveDescriptionAndClampsRetryDelay() {
        let sdkError = NSError(
            domain: CKErrorDomain,
            code: CKError.Code.requestRateLimited.rawValue,
            userInfo: [
                CKErrorRetryAfterKey: NSNumber(value: 100_000),
                NSLocalizedDescriptionKey: "provider-user-a@example.com secret record",
            ]
        )

        XCTAssertEqual(
            CloudKitSDKFailureClassifier.classify(sdkError),
            .rateLimited(retryAfterSeconds: 86_400)
        )
    }

    func testSDKFailureAggregationIsOrderIndependent() {
        let failures: [CloudKitClientFailure] = [
            .serviceUnavailable(retryAfterSeconds: 2),
            .rateLimited(retryAfterSeconds: 9),
            .networkUnavailable(retryAfterSeconds: 4),
        ]

        XCTAssertEqual(
            CloudKitSDKFailureClassifier.aggregate(failures),
            .rateLimited(retryAfterSeconds: 9)
        )
        XCTAssertEqual(
            CloudKitSDKFailureClassifier.aggregate(failures.reversed()),
            .rateLimited(retryAfterSeconds: 9)
        )
    }

    func testV3EnvelopeSupportsDiscoveryAndKnownReadsWhileFilteringMarkers() async throws {
        let client = FakeCloudKitPrivateDatabaseClient(userRecordName: "provider-user-a")
        let transport = try makeTransport(client: client)
        let accountID = try await availableAccountID(transport)
        _ = try await transport.commitAtomically(
            writeRequest(
                accountID: accountID,
                operationID: "seed-discovery",
                writes: [
                    write(id: "record-b", value: "two", precondition: .mustNotExist),
                    write(id: "record-a", value: "one", precondition: .mustNotExist),
                ]
            )
        )

        let stored = await client.recordsForUser("provider-user-a")
        let regularRecords = stored.filter { $0.recordType == "TestRecord" }
        let marker = try XCTUnwrap(stored.first { $0.recordType == "OperationMarker" })
        XCTAssertEqual(regularRecords.count, 2)
        for record in regularRecords {
            let envelope = try JSONDecoder().decode(
                TestCloudKitRecordPayloadV3.self,
                from: record.payload
            )
            XCTAssertEqual(envelope.schemaVersion, 3)
            XCTAssertTrue(
                [CloudRecordID("record-a"), CloudRecordID("record-b")]
                    .contains(envelope.logicalRecordID)
            )
        }

        await client.enqueueChangePage(
            changePage(
                modifications: Array(stored.reversed()),
                deletions: [
                    CloudKitClientRecordDeletion(
                        recordName: marker.recordName,
                        recordType: marker.recordType
                    ),
                ],
                cursor: "cursor-discovery"
            )
        )
        let page = try await transport.recordChanges(
            accountID: accountID,
            after: nil,
            zonePreparation: .createIfMissingForInitialBootstrap
        )

        XCTAssertEqual(page.accountID, accountID)
        XCTAssertEqual(page.nextCursor.rawValue, Data("cursor-discovery".utf8))
        XCTAssertFalse(page.moreComing)
        XCTAssertEqual(
            Set(page.modifications.map(\.record.id)),
            Set([CloudRecordID("record-a"), CloudRecordID("record-b")])
        )
        XCTAssertEqual(
            page.modifications.map(\.locator.rawValue),
            page.modifications.map(\.locator.rawValue).sorted()
        )
        XCTAssertTrue(page.deletions.isEmpty)

        let known = try await transport.records(
            accountID: accountID,
            ids: [CloudRecordID("record-a"), CloudRecordID("record-b")]
        )
        XCTAssertEqual(known.map(\.id), [CloudRecordID("record-a"), CloudRecordID("record-b")])
        XCTAssertEqual(known[0].fields["value"], Data("one".utf8))
        XCTAssertEqual(known[1].fields["value"], Data("two".utf8))
    }

    func testChangeFeedPreservesMultiPageCursorsAndPreparationPolicy() async throws {
        let client = FakeCloudKitPrivateDatabaseClient(userRecordName: "provider-user-a")
        let transport = try makeTransport(client: client)
        let accountID = try await availableAccountID(transport)
        _ = try await transport.commitAtomically(
            writeRequest(
                accountID: accountID,
                operationID: "seed-pages",
                writes: [
                    write(id: "page-a", value: "one", precondition: .mustNotExist),
                    write(id: "page-b", value: "two", precondition: .mustNotExist),
                ]
            )
        )
        let regular = await client.recordsForUser("provider-user-a")
            .filter { $0.recordType == "TestRecord" }
        let recordA = try XCTUnwrap(
            regular.first { recordLogicalID($0) == CloudRecordID("page-a") }
        )
        let recordB = try XCTUnwrap(
            regular.first { recordLogicalID($0) == CloudRecordID("page-b") }
        )
        await client.enqueueChangePage(
            changePage(
                modifications: [recordA],
                cursor: "cursor-page-1",
                moreComing: true
            )
        )
        await client.enqueueChangePage(
            changePage(
                modifications: [recordB],
                deletions: [
                    CloudKitClientRecordDeletion(
                        recordName: "opaque-deleted-b",
                        recordType: "TestRecord"
                    ),
                    CloudKitClientRecordDeletion(
                        recordName: "opaque-deleted-a",
                        recordType: "TestRecord"
                    ),
                ],
                cursor: "cursor-page-2"
            )
        )

        let first = try await transport.recordChanges(
            accountID: accountID,
            after: nil,
            zonePreparation: .createIfMissingForInitialBootstrap
        )
        let second = try await transport.recordChanges(
            accountID: accountID,
            after: first.nextCursor,
            zonePreparation: .requireExisting
        )

        XCTAssertEqual(first.modifications.map(\.record.id), [CloudRecordID("page-a")])
        XCTAssertTrue(first.moreComing)
        XCTAssertEqual(second.modifications.map(\.record.id), [CloudRecordID("page-b")])
        XCTAssertFalse(second.moreComing)
        XCTAssertEqual(second.nextCursor.rawValue, Data("cursor-page-2".utf8))
        XCTAssertEqual(
            second.deletions.map(\.locator.rawValue),
            ["opaque-deleted-a", "opaque-deleted-b"]
        )

        let calls = await client.observedChangeFetchCalls()
        XCTAssertEqual(calls.count, 2)
        XCTAssertNil(calls[0].cursor)
        XCTAssertTrue(calls[0].allowZoneCreation)
        XCTAssertEqual(calls[1].cursor, Data("cursor-page-1".utf8))
        XCTAssertFalse(calls[1].allowZoneCreation)
    }

    func testAccountSwitchDuringChangeFetchRejectsReturnedPage() async throws {
        let client = FakeCloudKitPrivateDatabaseClient(userRecordName: "provider-user-a")
        let transport = try makeTransport(client: client)
        let accountA = try await availableAccountID(transport)
        await client.enqueueChangePage(changePage(cursor: "cursor-account-a"))
        await client.switchUserAfterNextChangeFetch(to: "provider-user-b")

        do {
            _ = try await transport.recordChanges(
                accountID: accountA,
                after: nil,
                zonePreparation: .requireExisting
            )
            XCTFail("Expected account switch rejection")
        } catch let error as CloudSyncTransportError {
            XCTAssertEqual(error, .accountMismatch)
        }
    }

    func testProviderNameMismatchAndMalformedV3PayloadFailClosed() async throws {
        let client = FakeCloudKitPrivateDatabaseClient(userRecordName: "provider-user-a")
        let transport = try makeTransport(client: client)
        let accountID = try await availableAccountID(transport)
        _ = try await transport.commitAtomically(
            writeRequest(
                accountID: accountID,
                operationID: "seed-mismatch",
                writes: [write(id: "record-a", value: "one", precondition: .mustNotExist)]
            )
        )
        let storedRecords = await client.recordsForUser("provider-user-a")
        let original = try XCTUnwrap(
            storedRecords.first { $0.recordType == "TestRecord" }
        )
        let mismatchedPayload = try JSONEncoder().encode(
            TestCloudKitRecordPayloadV3(
                schemaVersion: 3,
                logicalRecordID: CloudRecordID("record-b"),
                fields: ["value": Data("tampered".utf8)],
                lastOperationFingerprint: Data("fingerprint".utf8)
            )
        )
        let mismatched = CloudKitClientRecord(
            recordName: original.recordName,
            recordType: original.recordType,
            payload: mismatchedPayload,
            changeTag: original.changeTag
        )
        await client.replaceRecord(mismatched, forUser: "provider-user-a")

        do {
            _ = try await transport.records(
                accountID: accountID,
                ids: [CloudRecordID("record-a")]
            )
            XCTFail("Expected known-read provider-name validation")
        } catch let error as CloudKitCloudSyncError {
            XCTAssertEqual(error, .malformedRecord(CloudRecordID("record-a")))
        }

        await client.enqueueChangePage(
            changePage(modifications: [mismatched], cursor: "cursor-mismatch")
        )
        do {
            _ = try await transport.recordChanges(
                accountID: accountID,
                after: nil,
                zonePreparation: .requireExisting
            )
            XCTFail("Expected discovered-record provider-name validation")
        } catch let error as CloudKitCloudSyncError {
            XCTAssertEqual(error, .malformedDiscoveredRecord)
        }

        let malformed = CloudKitClientRecord(
            recordName: original.recordName,
            recordType: original.recordType,
            payload: Data("not-json".utf8),
            changeTag: original.changeTag
        )
        await client.enqueueChangePage(
            changePage(modifications: [malformed], cursor: "cursor-malformed")
        )
        do {
            _ = try await transport.recordChanges(
                accountID: accountID,
                after: nil,
                zonePreparation: .requireExisting
            )
            XCTFail("Expected malformed discovery rejection")
        } catch let error as CloudKitCloudSyncError {
            XCTAssertEqual(error, .malformedDiscoveredRecord)
        }
    }

    func testChangeFeedRejectsDuplicatesAndModificationDeletionOverlap() async throws {
        let client = FakeCloudKitPrivateDatabaseClient(userRecordName: "provider-user-a")
        let transport = try makeTransport(client: client)
        let accountID = try await availableAccountID(transport)
        _ = try await transport.commitAtomically(
            writeRequest(
                accountID: accountID,
                operationID: "seed-inconsistent-page",
                writes: [write(id: "record-a", value: "one", precondition: .mustNotExist)]
            )
        )
        let storedRecords = await client.recordsForUser("provider-user-a")
        let record = try XCTUnwrap(
            storedRecords.first { $0.recordType == "TestRecord" }
        )
        await client.enqueueChangePage(
            changePage(
                modifications: [record, record],
                cursor: "cursor-duplicate"
            )
        )

        do {
            _ = try await transport.recordChanges(
                accountID: accountID,
                after: nil,
                zonePreparation: .requireExisting
            )
            XCTFail("Expected duplicate rejection")
        } catch let error as CloudKitCloudSyncError {
            XCTAssertEqual(error, .inconsistentChangePage)
        }

        await client.enqueueChangePage(
            changePage(
                modifications: [record],
                deletions: [
                    CloudKitClientRecordDeletion(
                        recordName: record.recordName,
                        recordType: record.recordType
                    ),
                ],
                cursor: "cursor-overlap"
            )
        )
        do {
            _ = try await transport.recordChanges(
                accountID: accountID,
                after: nil,
                zonePreparation: .requireExisting
            )
            XCTFail("Expected modification/deletion overlap rejection")
        } catch let error as CloudKitCloudSyncError {
            XCTAssertEqual(error, .inconsistentChangePage)
        }
    }

    func testExpiredAndMalformedCursorsRequireBootstrapRecovery() async throws {
        let client = FakeCloudKitPrivateDatabaseClient(userRecordName: "provider-user-a")
        let transport = try makeTransport(client: client)
        let accountID = try await availableAccountID(transport)
        let cursor = CloudChangeCursor(Data("stale-cursor".utf8))

        await client.failNextChangeFetch(with: .changeTokenExpired)
        do {
            _ = try await transport.recordChanges(
                accountID: accountID,
                after: cursor,
                zonePreparation: .requireExisting
            )
            XCTFail("Expected expired cursor")
        } catch let error as CloudKitCloudSyncError {
            XCTAssertEqual(error, .changeCursorExpired)
            XCTAssertEqual(error.recovery, .discardCursorAndRestartBootstrap)
        }

        await client.failNextChangeFetch(with: .malformedChangeCursor)
        do {
            _ = try await transport.recordChanges(
                accountID: accountID,
                after: cursor,
                zonePreparation: .requireExisting
            )
            XCTFail("Expected malformed cursor")
        } catch let error as CloudKitCloudSyncError {
            XCTAssertEqual(error, .malformedChangeCursor)
            XCTAssertEqual(error.recovery, .discardCursorAndRestartBootstrap)
        }

        XCTAssertThrowsError(
            try CloudKitServerChangeTokenCodec.decode(Data("not-a-secure-archive".utf8))
        ) { error in
            XCTAssertEqual(error as? CloudKitClientFailure, .malformedChangeCursor)
        }
    }

    func testExistingReplicaNeverSilentlyRecreatesMissingZone() async throws {
        let client = FakeCloudKitPrivateDatabaseClient(userRecordName: "provider-user-a")
        let transport = try makeTransport(client: client)
        let accountID = try await availableAccountID(transport)
        _ = try await transport.recordChanges(
            accountID: accountID,
            after: nil,
            zonePreparation: .createIfMissingForInitialBootstrap
        )
        await client.setZoneExists(false, forUser: "provider-user-a")

        do {
            _ = try await transport.recordChanges(
                accountID: accountID,
                after: nil,
                zonePreparation: .requireExisting
            )
            XCTFail("Expected explicit zone-reset recovery")
        } catch let error as CloudKitCloudSyncError {
            XCTAssertEqual(error, .zoneResetRequired)
            XCTAssertEqual(error.recovery, .requireAccountCloudReset)
        }
        let initialCreationCount = await client.zoneCreationCount(
            forUser: "provider-user-a"
        )
        XCTAssertEqual(initialCreationCount, 0)

        let bootstrapped = try await transport.recordChanges(
            accountID: accountID,
            after: nil,
            zonePreparation: .createIfMissingForInitialBootstrap
        )
        XCTAssertFalse(bootstrapped.moreComing)
        let bootstrapCreationCount = await client.zoneCreationCount(
            forUser: "provider-user-a"
        )
        XCTAssertEqual(bootstrapCreationCount, 1)

        await client.setZoneExists(false, forUser: "provider-user-a")
        do {
            _ = try await transport.recordChanges(
                accountID: accountID,
                after: bootstrapped.nextCursor,
                zonePreparation: .createIfMissingForInitialBootstrap
            )
            XCTFail("Expected invalid cursor/preparation combination")
        } catch let error as CloudKitCloudSyncError {
            XCTAssertEqual(error, .invalidRequest)
        }
        let finalCreationCount = await client.zoneCreationCount(
            forUser: "provider-user-a"
        )
        let fetchCallCount = await client.observedChangeFetchCalls().count
        XCTAssertEqual(finalCreationCount, 1)
        XCTAssertEqual(fetchCallCount, 3)
    }

    func testKnownReadsAndWritesRequireExistingZoneWithoutRecreation() async throws {
        let client = FakeCloudKitPrivateDatabaseClient(userRecordName: "provider-user-a")
        let transport = try makeTransport(client: client)
        let accountID = try await availableAccountID(transport)
        _ = try await transport.recordChanges(
            accountID: accountID,
            after: nil,
            zonePreparation: .createIfMissingForInitialBootstrap
        )
        await client.setZoneExists(false, forUser: "provider-user-a")

        do {
            _ = try await transport.records(
                accountID: accountID,
                ids: [CloudRecordID("economy-head")]
            )
            XCTFail("Expected known-read zone reset")
        } catch let error as CloudKitCloudSyncError {
            XCTAssertEqual(error, .zoneResetRequired)
            XCTAssertEqual(error.recovery, .requireAccountCloudReset)
        }

        do {
            _ = try await transport.commitAtomically(
                writeRequest(
                    accountID: accountID,
                    operationID: "missing-zone-write",
                    writes: [
                        write(
                            id: "economy-head",
                            value: "one",
                            precondition: .mustNotExist
                        ),
                    ]
                )
            )
            XCTFail("Expected write-path zone reset")
        } catch let error as CloudKitCloudSyncError {
            XCTAssertEqual(error, .zoneResetRequired)
            XCTAssertEqual(error.recovery, .requireAccountCloudReset)
        }

        let creationCount = await client.zoneCreationCount(
            forUser: "provider-user-a"
        )
        let saveCount = await client.successfulSaveCount()
        let records = await client.recordsForUser("provider-user-a")
        XCTAssertEqual(creationCount, 0)
        XCTAssertEqual(saveCount, 0)
        XCTAssertTrue(records.isEmpty)
    }

    private func makeTransport(
        client: FakeCloudKitPrivateDatabaseClient
    ) throws -> CloudKitCloudSyncTransport {
        CloudKitCloudSyncTransport(
            configuration: try cloudKitConfiguration(),
            client: client
        )
    }

    private func cloudKitConfiguration(
        containerIdentifier: String = "iCloud.test.container",
        containerEnvironment: CloudKitContainerEnvironment = .development,
        zoneName: String = "TestZone"
    ) throws -> CloudKitCloudSyncConfiguration {
        try CloudKitCloudSyncConfiguration._testOnly(
            containerIdentifier: containerIdentifier,
            containerEnvironment: containerEnvironment,
            zoneName: zoneName,
            payloadFieldName: "payload",
            operationRecordType: "OperationMarker",
            accountIdentifierNamespace: "test-account-namespace",
            recordNameNamespace: "test-record-namespace"
        )
    }

    private func productionConfiguration(
        containerIdentifier: String = "iCloud.test.container",
        containerEnvironment: CloudKitContainerEnvironment = .development,
        zoneName: String = "TestZone",
        profilePayloadFieldName: String = "profilePayload"
    ) throws -> ProductionCloudWriteConfiguration {
        try ProductionCloudWriteConfiguration(
            transport: try cloudKitConfiguration(
                containerIdentifier: containerIdentifier,
                containerEnvironment: containerEnvironment,
                zoneName: zoneName
            ),
            economy: try DurableEconomyCloudConfiguration(
                recordID: CloudRecordID("economy-head"),
                recordType: "EconomyRecord",
                payloadFieldName: "economyPayload",
                conflictRetryLimit: 3
            ),
            profile: try CloudProfileSchemaConfiguration(
                rootRecordType: "ProfileRoot",
                settingsRecordType: "ProfileSettings",
                selectionRecordType: "ProfileSelection",
                runRecordType: "ProfileRun",
                payloadFieldName: profilePayloadFieldName
            )
        )
    }

    private func availableAccountID(
        _ transport: CloudKitCloudSyncTransport
    ) async throws -> CloudAccountID {
        guard case let .available(accountID) = await transport.accountState() else {
            throw TestFailure.accountUnavailable
        }
        return accountID
    }

    private func writeRequest(
        accountID: CloudAccountID,
        operationID: String,
        writes: [CloudRecordWrite]
    ) -> CloudAtomicWriteRequest {
        CloudAtomicWriteRequest(
            accountID: accountID,
            operationID: OperationID(operationID),
            writes: writes
        )
    }

    private func write(
        id: String,
        value: String,
        precondition: CloudRecordPrecondition
    ) -> CloudRecordWrite {
        CloudRecordWrite(
            id: CloudRecordID(id),
            recordType: "TestRecord",
            fields: ["value": Data(value.utf8)],
            precondition: precondition
        )
    }

    private func operationMarker(
        in client: FakeCloudKitPrivateDatabaseClient,
        excluding recordNames: Set<String>
    ) async -> TestCloudKitOperationMarkerV2? {
        await client.recordsForUser("provider-user-a")
            .filter {
                $0.recordType == "OperationMarker"
                    && !recordNames.contains($0.recordName)
            }
            .compactMap {
                try? JSONDecoder().decode(
                    TestCloudKitOperationMarkerV2.self,
                    from: $0.payload
                )
            }
            .first
    }

    private func changePage(
        modifications: [CloudKitClientRecord] = [],
        deletions: [CloudKitClientRecordDeletion] = [],
        cursor: String,
        moreComing: Bool = false
    ) -> CloudKitClientChangePage {
        CloudKitClientChangePage(
            modifications: modifications,
            deletions: deletions,
            nextCursor: Data(cursor.utf8),
            moreComing: moreComing
        )
    }

    private func recordLogicalID(_ record: CloudKitClientRecord) -> CloudRecordID? {
        try? JSONDecoder().decode(
            TestCloudKitRecordPayloadV3.self,
            from: record.payload
        ).logicalRecordID
    }

    private enum TestFailure: Error {
        case accountUnavailable
    }
}

private struct TestCloudKitRecordPayloadV3: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let logicalRecordID: CloudRecordID
    let fields: [String: Data]
    let lastOperationFingerprint: Data
}

private struct TestCloudKitOperationMarkerV2: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let requestFingerprint: Data
    let targetRecordNames: [String]
}

private actor FakeCloudKitPrivateDatabaseClient: CloudKitPrivateDatabaseClient {
    private var status: CloudKitClientAccountStatus
    private var providerUserRecordName: String
    private var recordsByUser: [String: [String: CloudKitClientRecord]] = [:]
    private var nextTag: UInt64 = 1
    private var saveCount = 0
    private var seenRecordNames: Set<String> = []
    private var nextFetchFailure: CloudKitClientFailure?
    private var shouldLoseNextSaveResponse = false
    private var userToActivateAfterNextFetch: String?
    private var queuedChangeResults: [
        Result<CloudKitClientChangePage, CloudKitClientFailure>
    ] = []
    private var changeFetchCalls: [FakeChangeFetchCall] = []
    private var missingZoneUsers: Set<String> = []
    private var zoneCreationCountsByUser: [String: Int] = [:]
    private var userToActivateAfterNextChangeFetch: String?
    private var userToActivateImmediatelyBeforeNextSave: String?

    init(
        status: CloudKitClientAccountStatus = .available,
        userRecordName: String
    ) {
        self.status = status
        providerUserRecordName = userRecordName
    }

    func accountStatus() -> CloudKitClientAccountStatus {
        status
    }

    func currentUserRecordName() -> String {
        providerUserRecordName
    }

    func fetchRecords(named recordNames: [String]) throws -> [CloudKitClientRecord] {
        seenRecordNames.formUnion(recordNames)
        if let nextFetchFailure {
            self.nextFetchFailure = nil
            throw nextFetchFailure
        }
        let activeUser = providerUserRecordName
        guard !missingZoneUsers.contains(activeUser) else {
            throw CloudKitClientFailure.zoneMissing
        }
        let records = recordsByUser[activeUser, default: [:]]
        let result = recordNames.compactMap { records[$0] }
        if let userToActivateAfterNextFetch {
            providerUserRecordName = userToActivateAfterNextFetch
            self.userToActivateAfterNextFetch = nil
        }
        return result
    }

    func saveAtomically(
        _ writes: [CloudKitClientWrite],
        expectedProviderRecordName: String
    ) throws -> [CloudKitClientRecord] {
        if let userToActivateImmediatelyBeforeNextSave {
            providerUserRecordName = userToActivateImmediatelyBeforeNextSave
            self.userToActivateImmediatelyBeforeNextSave = nil
        }
        guard providerUserRecordName == expectedProviderRecordName else {
            throw CloudKitClientFailure.providerAccountMismatch
        }
        seenRecordNames.formUnion(writes.map(\.recordName))
        let activeUser = providerUserRecordName
        guard !missingZoneUsers.contains(activeUser) else {
            throw CloudKitClientFailure.zoneMissing
        }
        var records = recordsByUser[activeUser, default: [:]]
        var conflicts: [String] = []

        for write in writes {
            let existing = records[write.recordName]
            switch write.precondition {
            case .none:
                break
            case .mustNotExist where existing != nil:
                conflicts.append(write.recordName)
            case .mustNotExist:
                break
            case let .changeTag(expected) where existing?.changeTag != expected:
                conflicts.append(write.recordName)
            case .changeTag:
                break
            }
            if let existing, existing.recordType != write.recordType {
                conflicts.append(write.recordName)
            }
        }
        guard conflicts.isEmpty else {
            throw CloudKitClientFailure.conflict(
                recordNames: Array(Set(conflicts)).sorted()
            )
        }

        var saved: [CloudKitClientRecord] = []
        for write in writes {
            let record = CloudKitClientRecord(
                recordName: write.recordName,
                recordType: write.recordType,
                payload: write.payload,
                changeTag: "fake-tag-\(nextTag)"
            )
            nextTag += 1
            records[write.recordName] = record
            saved.append(record)
        }
        recordsByUser[activeUser] = records
        saveCount += 1

        if shouldLoseNextSaveResponse {
            shouldLoseNextSaveResponse = false
            throw CloudKitClientFailure.responseLost
        }
        return saved
    }

    func fetchRecordZoneChanges(
        afterArchivedCursor cursor: Data?,
        allowZoneCreation: Bool
    ) throws -> CloudKitClientChangePage {
        let activeUser = providerUserRecordName
        changeFetchCalls.append(
            FakeChangeFetchCall(
                cursor: cursor,
                allowZoneCreation: allowZoneCreation,
                userRecordName: activeUser
            )
        )

        if missingZoneUsers.contains(activeUser) {
            guard allowZoneCreation else {
                throw CloudKitClientFailure.zoneMissing
            }
            missingZoneUsers.remove(activeUser)
            zoneCreationCountsByUser[activeUser, default: 0] += 1
        }

        let result: Result<CloudKitClientChangePage, CloudKitClientFailure>
        if queuedChangeResults.isEmpty {
            result = .success(
                CloudKitClientChangePage(
                    modifications: [],
                    deletions: [],
                    nextCursor: Data("fake-cursor-\(changeFetchCalls.count)".utf8),
                    moreComing: false
                )
            )
        } else {
            result = queuedChangeResults.removeFirst()
        }

        let page = try result.get()
        if let userToActivateAfterNextChangeFetch {
            providerUserRecordName = userToActivateAfterNextChangeFetch
            self.userToActivateAfterNextChangeFetch = nil
        }
        return page
    }

    func setAccountStatus(_ status: CloudKitClientAccountStatus) {
        self.status = status
    }

    func setUserRecordName(_ recordName: String) {
        providerUserRecordName = recordName
    }

    func failNextFetch(with failure: CloudKitClientFailure) {
        nextFetchFailure = failure
    }

    func loseResponseAfterNextSuccessfulSave() {
        shouldLoseNextSaveResponse = true
    }

    func switchUserAfterNextFetch(to recordName: String) {
        userToActivateAfterNextFetch = recordName
    }

    func switchUserImmediatelyBeforeNextSave(to recordName: String) {
        userToActivateImmediatelyBeforeNextSave = recordName
    }

    func enqueueChangePage(_ page: CloudKitClientChangePage) {
        queuedChangeResults.append(.success(page))
    }

    func failNextChangeFetch(with failure: CloudKitClientFailure) {
        queuedChangeResults.append(.failure(failure))
    }

    func switchUserAfterNextChangeFetch(to recordName: String) {
        userToActivateAfterNextChangeFetch = recordName
    }

    func setZoneExists(_ exists: Bool, forUser recordName: String) {
        if exists {
            missingZoneUsers.remove(recordName)
        } else {
            missingZoneUsers.insert(recordName)
        }
    }

    func zoneCreationCount(forUser recordName: String) -> Int {
        zoneCreationCountsByUser[recordName, default: 0]
    }

    func observedChangeFetchCalls() -> [FakeChangeFetchCall] {
        changeFetchCalls
    }

    func replaceRecord(_ record: CloudKitClientRecord, forUser recordName: String) {
        recordsByUser[recordName, default: [:]][record.recordName] = record
    }

    func successfulSaveCount() -> Int {
        saveCount
    }

    func observedRecordNames() -> Set<String> {
        seenRecordNames
    }

    func recordsForUser(_ recordName: String) -> [CloudKitClientRecord] {
        Array(recordsByUser[recordName, default: [:]].values)
    }
}

private struct FakeChangeFetchCall: Equatable, Sendable {
    let cursor: Data?
    let allowZoneCreation: Bool
    let userRecordName: String
}

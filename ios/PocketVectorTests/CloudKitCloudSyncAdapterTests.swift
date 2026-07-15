import Foundation
@preconcurrency import CloudKit
import XCTest

@testable import PocketVector

final class CloudKitCloudSyncAdapterTests: XCTestCase, @unchecked Sendable {
    func testConfigurationRequiresAllProductionSchemaIdentifiers() throws {
        XCTAssertThrowsError(
            try CloudKitCloudSyncConfiguration(
                containerIdentifier: "",
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
            try CloudKitCloudSyncConfiguration(
                containerIdentifier: "iCloud.test.container",
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

    private func makeTransport(
        client: FakeCloudKitPrivateDatabaseClient
    ) throws -> CloudKitCloudSyncTransport {
        CloudKitCloudSyncTransport(
            configuration: try CloudKitCloudSyncConfiguration(
                containerIdentifier: "iCloud.test.container",
                zoneName: "TestZone",
                payloadFieldName: "payload",
                operationRecordType: "OperationMarker",
                accountIdentifierNamespace: "test-account-namespace",
                recordNameNamespace: "test-record-namespace"
            ),
            client: client
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

    private enum TestFailure: Error {
        case accountUnavailable
    }
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
        let records = recordsByUser[activeUser, default: [:]]
        let result = recordNames.compactMap { records[$0] }
        if let userToActivateAfterNextFetch {
            providerUserRecordName = userToActivateAfterNextFetch
            self.userToActivateAfterNextFetch = nil
        }
        return result
    }

    func saveAtomically(_ writes: [CloudKitClientWrite]) throws -> [CloudKitClientRecord] {
        seenRecordNames.formUnion(writes.map(\.recordName))
        let activeUser = providerUserRecordName
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

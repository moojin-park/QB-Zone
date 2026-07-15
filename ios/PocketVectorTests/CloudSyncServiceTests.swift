import XCTest

@testable import PocketVector

final class CloudSyncServiceTests: XCTestCase {
    func testAccountSwitchIsolatesPendingOperationsAndStaleAcknowledgements() throws {
        let accountA = CloudAccountID("icloud-a")
        let accountB = CloudAccountID("icloud-b")
        var queue = AccountScopedCloudSyncQueue()

        XCTAssertTrue(queue.activate(accountA, epoch: uuid(1)))
        let operationA = operation(id: "operation-a", recordID: "profile-a")
        try queue.enqueue(operationA)
        let batchA = try XCTUnwrap(queue.nextBatch())

        XCTAssertTrue(queue.activate(accountB, epoch: uuid(2)))
        let operationB = operation(id: "operation-b", recordID: "profile-b")
        try queue.enqueue(operationB)
        let batchB = try XCTUnwrap(queue.nextBatch())

        XCTAssertEqual(batchB.accountID, accountB)
        XCTAssertEqual(batchB.operations, [operationB])
        XCTAssertFalse(queue.acknowledge(batchA))
        XCTAssertEqual(queue.pendingCount(for: accountA), 1)
        XCTAssertEqual(queue.pendingCount(for: accountB), 1)

        XCTAssertTrue(queue.acknowledge(batchB))
        XCTAssertEqual(queue.pendingCount(for: accountB), 0)
        XCTAssertTrue(queue.activate(accountA, epoch: uuid(3)))
        XCTAssertEqual(try XCTUnwrap(queue.nextBatch()).operations, [operationA])
    }

    func testSameAccountRelaunchRotatesEpochAndRejectsStaleBatchAcknowledgement() throws {
        let account = CloudAccountID("icloud-a")
        var queue = AccountScopedCloudSyncQueue()
        XCTAssertTrue(queue.activate(account, epoch: uuid(10)))
        try queue.enqueue(operation(id: "operation", recordID: "profile"))
        let staleBatch = try XCTUnwrap(queue.nextBatch())

        let encoded = try JSONEncoder().encode(queue)
        var restored = try JSONDecoder().decode(
            AccountScopedCloudSyncQueue.self,
            from: encoded
        )
        XCTAssertTrue(restored.activate(account, epoch: uuid(11)))
        XCTAssertFalse(restored.acknowledge(staleBatch))
        XCTAssertEqual(restored.pendingCount(for: account), 1)

        let currentBatch = try XCTUnwrap(restored.nextBatch())
        XCTAssertEqual(currentBatch.accountEpoch, uuid(11))
        XCTAssertTrue(restored.acknowledge(currentBatch))
    }

    func testLostAcknowledgementRemainsIdempotentAfterTransportRecreation() async throws {
        let accountID = CloudAccountID("icloud-a")
        let recordID = CloudRecordID("economy-head")
        let database = InMemoryCloudDurableDatabase()
        let firstTransport = InMemoryCloudSyncTransport(
            accountState: .available(accountID),
            database: database
        )
        let request = CloudAtomicWriteRequest(
            accountID: accountID,
            operationID: OperationID("grant-1"),
            writes: [
                CloudRecordWrite(
                    id: recordID,
                    recordType: "EconomyHead",
                    fields: ["state": Data("credited".utf8)],
                    precondition: .mustNotExist
                ),
            ]
        )

        let lostReceipt = try await firstTransport.commitAtomically(request)
        let recreatedTransport = InMemoryCloudSyncTransport(
            accountState: .available(accountID),
            database: database
        )
        let recoveredReceipt = try await recreatedTransport.commitAtomically(request)

        XCTAssertEqual(lostReceipt, recoveredReceipt)
        let storedRecords = await recreatedTransport.allRecords(for: accountID)
        XCTAssertEqual(storedRecords.count, 1)
        XCTAssertEqual(storedRecords.first?.changeTag, lostReceipt.savedChangeTags[recordID])
    }

    func testOpaqueChangeTagConflictDoesNotOverwriteNewerRecord() async throws {
        let accountID = CloudAccountID("icloud-a")
        let recordID = CloudRecordID("economy-head")
        let transport = InMemoryCloudSyncTransport(accountState: .available(accountID))
        let firstRequest = writeRequest(
            accountID: accountID,
            operationID: "write-1",
            recordID: recordID,
            value: "one",
            precondition: .mustNotExist
        )
        let first = try await transport.commitAtomically(firstRequest)
        let firstTag = try XCTUnwrap(first.savedChangeTags[recordID])

        let secondRequest = writeRequest(
            accountID: accountID,
            operationID: "write-2",
            recordID: recordID,
            value: "two",
            precondition: .changeTag(firstTag)
        )
        let second = try await transport.commitAtomically(secondRequest)
        let secondTag = try XCTUnwrap(second.savedChangeTags[recordID])
        XCTAssertNotEqual(firstTag, secondTag)

        let staleRequest = writeRequest(
            accountID: accountID,
            operationID: "write-3",
            recordID: recordID,
            value: "stale",
            precondition: .changeTag(firstTag)
        )
        do {
            _ = try await transport.commitAtomically(staleRequest)
            XCTFail("Expected opaque change-tag conflict")
        } catch let error as CloudSyncTransportError {
            XCTAssertEqual(error, .conflict([recordID]))
        }

        let records = await transport.allRecords(for: accountID)
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(record.fields["value"], Data("two".utf8))
        XCTAssertEqual(record.changeTag, secondTag)
    }

    func testTransportRejectsCrossAccountAccess() async throws {
        let accountA = CloudAccountID("icloud-a")
        let accountB = CloudAccountID("icloud-b")
        let transport = InMemoryCloudSyncTransport(accountState: .available(accountA))

        do {
            _ = try await transport.records(accountID: accountB, ids: [])
            XCTFail("Expected account mismatch")
        } catch let error as CloudSyncTransportError {
            XCTAssertEqual(error, .accountMismatch)
        }
    }

    private func operation(id: String, recordID: String) -> QueuedCloudOperation {
        QueuedCloudOperation(
            id: OperationID(id),
            writes: [
                CloudRecordWrite(
                    id: CloudRecordID(recordID),
                    recordType: "Profile",
                    fields: [:],
                    precondition: .none
                ),
            ]
        )
    }

    private func writeRequest(
        accountID: CloudAccountID,
        operationID: String,
        recordID: CloudRecordID,
        value: String,
        precondition: CloudRecordPrecondition
    ) -> CloudAtomicWriteRequest {
        CloudAtomicWriteRequest(
            accountID: accountID,
            operationID: OperationID(operationID),
            writes: [
                CloudRecordWrite(
                    id: recordID,
                    recordType: "EconomyHead",
                    fields: ["value": Data(value.utf8)],
                    precondition: precondition
                ),
            ]
        )
    }

    private func uuid(_ value: Int) -> UUID {
        UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", value))")!
    }
}

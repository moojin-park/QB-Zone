import Foundation

struct CloudAccountID: RawRepresentable, Codable, Hashable, Sendable, CustomStringConvertible {
    let rawValue: String

    init(rawValue: String) {
        precondition(!rawValue.isEmpty, "CloudAccountID cannot be empty")
        self.rawValue = rawValue
    }

    init(_ rawValue: String) {
        self.init(rawValue: rawValue)
    }

    var description: String { rawValue }
}

struct CloudRecordID: RawRepresentable, Codable, Hashable, Sendable, CustomStringConvertible {
    let rawValue: String

    init(rawValue: String) {
        precondition(!rawValue.isEmpty, "CloudRecordID cannot be empty")
        self.rawValue = rawValue
    }

    init(_ rawValue: String) {
        self.init(rawValue: rawValue)
    }

    var description: String { rawValue }
}

/// An adapter treats this as opaque. The fake uses generated strings, while a
/// CloudKit adapter maps CKRecord.recordChangeTag without numeric assumptions.
struct CloudChangeTag: RawRepresentable, Codable, Hashable, Sendable, CustomStringConvertible {
    let rawValue: String

    init(rawValue: String) {
        precondition(!rawValue.isEmpty, "CloudChangeTag cannot be empty")
        self.rawValue = rawValue
    }

    init(_ rawValue: String) {
        self.init(rawValue: rawValue)
    }

    var description: String { rawValue }
}

enum CloudAccountState: Codable, Equatable, Sendable {
    case unknown
    case signedOut
    case restricted
    case available(CloudAccountID)

    var accountID: CloudAccountID? {
        guard case let .available(accountID) = self else { return nil }
        return accountID
    }
}

struct CloudRecord: Codable, Equatable, Sendable {
    let id: CloudRecordID
    let recordType: String
    let fields: [String: Data]
    let changeTag: CloudChangeTag
}

enum CloudRecordPrecondition: Codable, Equatable, Sendable {
    case none
    case mustNotExist
    case changeTag(CloudChangeTag)
}

struct CloudRecordWrite: Codable, Equatable, Sendable {
    let id: CloudRecordID
    let recordType: String
    let fields: [String: Data]
    let precondition: CloudRecordPrecondition
}

struct CloudAtomicWriteRequest: Codable, Equatable, Sendable {
    let accountID: CloudAccountID
    let operationID: OperationID
    let writes: [CloudRecordWrite]
}

struct CloudAtomicWriteReceipt: Codable, Equatable, Sendable {
    let accountID: CloudAccountID
    let operationID: OperationID
    let savedChangeTags: [CloudRecordID: CloudChangeTag]
}

protocol CloudSyncTransport: Sendable {
    func accountState() async -> CloudAccountState
    func records(accountID: CloudAccountID, ids: [CloudRecordID]) async throws -> [CloudRecord]
    func commitAtomically(_ request: CloudAtomicWriteRequest) async throws -> CloudAtomicWriteReceipt
}

/// An opaque, provider-issued position in one private record zone's change
/// history. Callers persist this only alongside the complete replica to which
/// it applies; advancing a cursor independently can permanently skip records.
struct CloudChangeCursor: RawRepresentable, Codable, Equatable, Sendable {
    let rawValue: Data

    init(rawValue: Data) {
        precondition(!rawValue.isEmpty, "CloudChangeCursor cannot be empty")
        self.rawValue = rawValue
    }

    init(_ rawValue: Data) {
        self.init(rawValue: rawValue)
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let data = try container.decode(Data.self)
        guard !data.isEmpty else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "CloudChangeCursor cannot be empty"
            )
        }
        rawValue = data
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// The adapter's opaque locator for a provider record. It is retained only so
/// a later tombstone can be matched to a previously discovered logical record.
/// It must never be presented as a player-facing or analytics identifier.
struct CloudProviderRecordLocator: RawRepresentable, Codable, Equatable, Hashable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        precondition(!rawValue.isEmpty, "CloudProviderRecordLocator cannot be empty")
        self.rawValue = rawValue
    }

    init(_ rawValue: String) {
        self.init(rawValue: rawValue)
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard !value.isEmpty else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "CloudProviderRecordLocator cannot be empty"
            )
        }
        rawValue = value
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct CloudDiscoveredRecord: Codable, Equatable, Sendable {
    let locator: CloudProviderRecordLocator
    let record: CloudRecord
}

struct CloudDeletedRecord: Codable, Equatable, Sendable {
    let locator: CloudProviderRecordLocator
    let recordType: String
}

struct CloudRecordChangePage: Codable, Equatable, Sendable {
    let accountID: CloudAccountID
    let modifications: [CloudDiscoveredRecord]
    let deletions: [CloudDeletedRecord]
    let nextCursor: CloudChangeCursor
    let moreComing: Bool
}

/// Only a brand-new account replica may create its private custom zone. A
/// caller holding any prior cloud state must require the zone to exist so a
/// user purge or encrypted-data reset cannot silently resurrect stale data.
enum CloudZonePreparationPolicy: Codable, Equatable, Sendable {
    case createIfMissingForInitialBootstrap
    case requireExisting
}

/// Discovery is intentionally separate from the known-ID/atomic-write
/// transport. Production keeps its tested operation-marker transaction path
/// while a bootstrap coordinator consumes these lossless, paged zone changes.
protocol CloudSyncChangeFetching: Sendable {
    func recordChanges(
        accountID: CloudAccountID,
        after cursor: CloudChangeCursor?,
        zonePreparation: CloudZonePreparationPolicy
    ) async throws -> CloudRecordChangePage
}

protocol CloudSyncStateStoring: Sendable {
    func state(for accountID: CloudAccountID) async throws -> Data?
    func saveState(_ state: Data, for accountID: CloudAccountID) async throws
    func removeState(for accountID: CloudAccountID) async throws
}

struct QueuedCloudOperation: Codable, Equatable, Sendable {
    let id: OperationID
    let writes: [CloudRecordWrite]
}

struct CloudSyncBatch: Codable, Equatable, Sendable {
    let accountID: CloudAccountID
    let accountEpoch: UUID
    let operations: [QueuedCloudOperation]
}

enum CloudSyncQueueError: Error, Equatable, Sendable {
    case noActiveAccount
    case operationIDCollision(OperationID)
}

struct AccountScopedCloudSyncQueue: Codable, Equatable, Sendable {
    private(set) var activeAccountID: CloudAccountID?
    private(set) var accountEpoch = UUID()
    private var pendingByAccount: [CloudAccountID: [OperationID: QueuedCloudOperation]] = [:]

    @discardableResult
    mutating func activate(
        _ accountID: CloudAccountID?,
        epoch: UUID = UUID()
    ) -> Bool {
        guard activeAccountID != accountID || accountEpoch != epoch else { return false }
        activeAccountID = accountID
        accountEpoch = epoch
        return true
    }

    mutating func enqueue(_ operation: QueuedCloudOperation) throws {
        guard let activeAccountID else {
            throw CloudSyncQueueError.noActiveAccount
        }

        var pending = pendingByAccount[activeAccountID, default: [:]]
        if let existing = pending[operation.id], existing != operation {
            throw CloudSyncQueueError.operationIDCollision(operation.id)
        }
        pending[operation.id] = operation
        pendingByAccount[activeAccountID] = pending
    }

    func nextBatch(limit: Int = 100) -> CloudSyncBatch? {
        guard limit > 0,
              let activeAccountID,
              let pending = pendingByAccount[activeAccountID],
              !pending.isEmpty else {
            return nil
        }

        let operations = pending.values
            .sorted { $0.id.rawValue < $1.id.rawValue }
            .prefix(limit)

        return CloudSyncBatch(
            accountID: activeAccountID,
            accountEpoch: accountEpoch,
            operations: Array(operations)
        )
    }

    @discardableResult
    mutating func acknowledge(_ batch: CloudSyncBatch) -> Bool {
        guard activeAccountID == batch.accountID,
              accountEpoch == batch.accountEpoch,
              var pending = pendingByAccount[batch.accountID] else {
            return false
        }

        for operation in batch.operations where pending[operation.id] == operation {
            pending.removeValue(forKey: operation.id)
        }

        if pending.isEmpty {
            pendingByAccount.removeValue(forKey: batch.accountID)
        } else {
            pendingByAccount[batch.accountID] = pending
        }
        return true
    }

    func pendingCount(for accountID: CloudAccountID) -> Int {
        pendingByAccount[accountID]?.count ?? 0
    }
}

enum CloudSyncTransportError: Error, Equatable, Sendable {
    case accountUnavailable
    case accountMismatch
    case conflict([CloudRecordID])
    case operationIDCollision(OperationID)
}

/// Shared durable state for fake adapter recreation. It models both records
/// and atomic operation markers surviving a lost client acknowledgement.
actor InMemoryCloudDurableDatabase {
    private struct ProcessedWrite: Equatable, Sendable {
        let request: CloudAtomicWriteRequest
        let receipt: CloudAtomicWriteReceipt
    }

    private var recordsByAccount: [CloudAccountID: [CloudRecordID: CloudRecord]] = [:]
    private var processedByAccount: [CloudAccountID: [OperationID: ProcessedWrite]] = [:]
    private var nextTagValue: UInt64 = 1

    func records(
        accountID: CloudAccountID,
        ids: [CloudRecordID]
    ) -> [CloudRecord] {
        let records = recordsByAccount[accountID, default: [:]]
        return ids.compactMap { records[$0] }
    }

    func commit(
        _ request: CloudAtomicWriteRequest
    ) throws -> CloudAtomicWriteReceipt {
        if let processed = processedByAccount[request.accountID]?[request.operationID] {
            guard processed.request == request else {
                throw CloudSyncTransportError.operationIDCollision(request.operationID)
            }
            return processed.receipt
        }

        let currentRecords = recordsByAccount[request.accountID, default: [:]]
        let conflicts = request.writes.compactMap { write -> CloudRecordID? in
            let existing = currentRecords[write.id]
            switch write.precondition {
            case .none:
                return nil
            case .mustNotExist:
                return existing == nil ? nil : write.id
            case let .changeTag(expected):
                return existing?.changeTag == expected ? nil : write.id
            }
        }.sorted { $0.rawValue < $1.rawValue }

        guard conflicts.isEmpty else {
            throw CloudSyncTransportError.conflict(conflicts)
        }

        var updatedRecords = currentRecords
        var savedChangeTags: [CloudRecordID: CloudChangeTag] = [:]
        for write in request.writes {
            let changeTag = makeChangeTag()
            updatedRecords[write.id] = CloudRecord(
                id: write.id,
                recordType: write.recordType,
                fields: write.fields,
                changeTag: changeTag
            )
            savedChangeTags[write.id] = changeTag
        }

        let receipt = CloudAtomicWriteReceipt(
            accountID: request.accountID,
            operationID: request.operationID,
            savedChangeTags: savedChangeTags
        )
        recordsByAccount[request.accountID] = updatedRecords
        processedByAccount[request.accountID, default: [:]][request.operationID] = ProcessedWrite(
            request: request,
            receipt: receipt
        )
        return receipt
    }

    func seed(_ records: [CloudRecord], for accountID: CloudAccountID) {
        recordsByAccount[accountID] = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
    }

    func allRecords(for accountID: CloudAccountID) -> [CloudRecord] {
        recordsByAccount[accountID, default: [:]].values
            .sorted { $0.id.rawValue < $1.id.rawValue }
    }

    private func makeChangeTag() -> CloudChangeTag {
        let tag = CloudChangeTag("fake-change-tag-\(nextTagValue)")
        nextTagValue &+= 1
        return tag
    }
}

actor InMemoryCloudSyncTransport: CloudSyncTransport {
    private var currentState: CloudAccountState
    private let database: InMemoryCloudDurableDatabase

    init(
        accountState: CloudAccountState = .signedOut,
        database: InMemoryCloudDurableDatabase = InMemoryCloudDurableDatabase()
    ) {
        currentState = accountState
        self.database = database
    }

    func accountState() -> CloudAccountState {
        currentState
    }

    func records(
        accountID: CloudAccountID,
        ids: [CloudRecordID]
    ) async throws -> [CloudRecord] {
        try requireActive(accountID)
        return await database.records(accountID: accountID, ids: ids)
    }

    func commitAtomically(
        _ request: CloudAtomicWriteRequest
    ) async throws -> CloudAtomicWriteReceipt {
        try requireActive(request.accountID)
        return try await database.commit(request)
    }

    func setAccountState(_ state: CloudAccountState) {
        currentState = state
    }

    func seed(_ records: [CloudRecord], for accountID: CloudAccountID) async {
        await database.seed(records, for: accountID)
    }

    func allRecords(for accountID: CloudAccountID) async -> [CloudRecord] {
        await database.allRecords(for: accountID)
    }

    private func requireActive(_ accountID: CloudAccountID) throws {
        guard let activeAccountID = currentState.accountID else {
            throw CloudSyncTransportError.accountUnavailable
        }
        guard activeAccountID == accountID else {
            throw CloudSyncTransportError.accountMismatch
        }
    }
}

actor InMemoryCloudSyncStateStore: CloudSyncStateStoring {
    private var states: [CloudAccountID: Data] = [:]

    func state(for accountID: CloudAccountID) -> Data? {
        states[accountID]
    }

    func saveState(_ state: Data, for accountID: CloudAccountID) {
        states[accountID] = state
    }

    func removeState(for accountID: CloudAccountID) {
        states.removeValue(forKey: accountID)
    }
}

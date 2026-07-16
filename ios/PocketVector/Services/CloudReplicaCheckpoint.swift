import CryptoKit
import Darwin
import Foundation

private struct CloudReplicaDigestBuilder {
    private var hasher = SHA256()

    mutating func append(_ value: String) {
        append(Data(value.utf8))
    }

    mutating func append(_ value: Data) {
        var length = UInt64(value.count).bigEndian
        withUnsafeBytes(of: &length) { hasher.update(data: Data($0)) }
        hasher.update(data: value)
    }

    mutating func append(_ value: UInt64) {
        var encoded = value.bigEndian
        withUnsafeBytes(of: &encoded) { hasher.update(data: Data($0)) }
    }

    mutating func append(_ value: Bool) {
        append(value ? UInt64(1) : UInt64(0))
    }

    mutating func append(_ value: UUID) {
        append(value.uuidString.lowercased())
    }

    mutating func append(_ value: CloudChangeCursor?) {
        append(value != nil)
        if let value {
            append(value.rawValue)
        }
    }

    mutating func append(_ record: CloudRecord) {
        append(record.id.rawValue)
        append(record.recordType)
        append(record.changeTag.rawValue)
        append(UInt64(record.fields.count))
        for key in record.fields.keys.sorted() {
            append(key)
            append(record.fields[key] ?? Data())
        }
    }

    mutating func finalize() -> Data {
        Data(hasher.finalize())
    }
}

struct CloudReplicaResourceLimits: Equatable, Sendable {
    static let production = CloudReplicaResourceLimits(
        maxPagesPerSync: 10_000,
        maxPageChangeCount: 2_000,
        maxRecordCount: 50_000,
        maxTombstoneCount: 10_000,
        maxBytesPerRecord: 2 * 1_024 * 1_024,
        maxTotalBytes: 128 * 1_024 * 1_024,
        maxCursorBytes: 64 * 1_024
    )

    let maxPagesPerSync: Int
    let maxPageChangeCount: Int
    let maxRecordCount: Int
    let maxTombstoneCount: Int
    let maxBytesPerRecord: Int
    let maxTotalBytes: Int
    let maxCursorBytes: Int

    init(
        maxPagesPerSync: Int,
        maxPageChangeCount: Int,
        maxRecordCount: Int,
        maxTombstoneCount: Int,
        maxBytesPerRecord: Int,
        maxTotalBytes: Int,
        maxCursorBytes: Int
    ) {
        precondition(maxPagesPerSync > 0)
        precondition(maxPageChangeCount > 0)
        precondition(maxRecordCount > 0)
        precondition(maxTombstoneCount > 0)
        precondition(maxBytesPerRecord > 0)
        precondition(maxTotalBytes > 0)
        precondition(maxCursorBytes > 0)
        self.maxPagesPerSync = maxPagesPerSync
        self.maxPageChangeCount = maxPageChangeCount
        self.maxRecordCount = maxRecordCount
        self.maxTombstoneCount = maxTombstoneCount
        self.maxBytesPerRecord = maxBytesPerRecord
        self.maxTotalBytes = maxTotalBytes
        self.maxCursorBytes = maxCursorBytes
    }
}

/// A domain-separated digest of every CloudKit address and schema input that
/// gives meaning to a replica. A checkpoint from another scope is never safe
/// to reuse, even when it belongs to the same provider account.
struct CloudReplicaScopeFingerprint: RawRepresentable, Codable, Equatable, Hashable, Sendable {
    static let scopeDomain = "pocket-vector-cloud-replica-scope-v2"

    let rawValue: String

    init(rawValue: String) {
        precondition(
            Self.isValid(rawValue),
            "CloudReplicaScopeFingerprint must be a lowercase SHA-256 digest"
        )
        self.rawValue = rawValue
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard Self.isValid(value) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid cloud replica scope fingerprint"
            )
        }
        rawValue = value
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    /// Transport, economy, and profile contracts form one indivisible scope.
    /// Any schema or address change invalidates the prior cursor and replica.
    static func make(for configuration: ProductionCloudWriteConfiguration) -> Self {
        var hasher = SHA256()
        for value in orderedMaterial(for: configuration) {
            append(value, to: &hasher)
        }
        return Self(
            rawValue: hasher.finalize().map { String(format: "%02x", $0) }.joined()
        )
    }

    static func orderedMaterial(
        for configuration: ProductionCloudWriteConfiguration
    ) -> [String] {
        let transport = configuration.transport.fingerprintMaterial
        let economy = configuration.economy.fingerprintMaterial
        let profile = configuration.profile.fingerprintMaterial
        return [scopeDomain, "transport", String(transport.count)]
            + transport
            + ["economy", String(economy.count)]
            + economy
            + ["profile", String(profile.count)]
            + profile
    }

    private static func append(_ value: String, to hasher: inout SHA256) {
        let data = Data(value.utf8)
        var length = UInt64(data.count).bigEndian
        withUnsafeBytes(of: &length) { hasher.update(data: Data($0)) }
        hasher.update(data: data)
    }

    private static func isValid(_ value: String) -> Bool {
        value.count == 64
            && value.utf8.allSatisfy {
                ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102)
            }
    }
}

/// The page plus the exact request context that produced it. A provider cursor
/// is meaningful only for that predecessor and configuration scope, so the
/// accumulator never accepts a raw page detached from either binding.
struct CloudReplicaFetchedPage: Equatable, Sendable {
    let requestedAfterCursor: CloudChangeCursor?
    let configurationScopeFingerprint: CloudReplicaScopeFingerprint
    let page: CloudRecordChangePage
}

struct CloudReplicaTombstone: Codable, Equatable, Sendable {
    let locator: CloudProviderRecordLocator
    let logicalRecordID: CloudRecordID?
    let recordType: String
}

enum CloudReplicaCheckpointValidationError: Error, Equatable, Sendable {
    case unsupportedFormatVersion
    case invalidGeneration
    case invalidAccountID
    case invalidLogicalRecordID
    case recordKeyMismatch
    case invalidRecordType
    case invalidChangeTag
    case invalidFieldName
    case incompleteLocatorIndex
    case nonBijectiveLocatorIndex
    case tombstoneKeyMismatch
    case liveRecordIsTombstoned
    case tombstoneLogicalRecordIsLive
    case ambiguousTombstoneMapping
    case cursorLimitExceeded
    case recordLimitExceeded
    case tombstoneLimitExceeded
    case recordByteLimitExceeded
    case totalByteLimitExceeded
    case byteCountOverflow
}

/// A cursor is useful only when it is inseparable from the exact complete
/// logical replica it describes. This value is the sole persistable sync
/// checkpoint; an in-progress page sequence cannot manufacture one.
struct CloudReplicaCheckpointV1: Codable, Equatable, Sendable {
    static let formatVersion = 1

    let accountID: CloudAccountID
    let configurationScopeFingerprint: CloudReplicaScopeFingerprint
    let generation: UInt64
    let finalCursor: CloudChangeCursor
    let recordsByLogicalID: [CloudRecordID: CloudRecord]
    let providerLocatorByLogicalID: [CloudRecordID: CloudProviderRecordLocator]
    let logicalIDByProviderLocator: [CloudProviderRecordLocator: CloudRecordID]
    let tombstonesByProviderLocator: [CloudProviderRecordLocator: CloudReplicaTombstone]
    let replicaEpoch: UUID

    init(
        accountID: CloudAccountID,
        configurationScopeFingerprint: CloudReplicaScopeFingerprint,
        generation: UInt64,
        finalCursor: CloudChangeCursor,
        recordsByLogicalID: [CloudRecordID: CloudRecord],
        providerLocatorByLogicalID: [CloudRecordID: CloudProviderRecordLocator],
        logicalIDByProviderLocator: [CloudProviderRecordLocator: CloudRecordID],
        tombstonesByProviderLocator: [CloudProviderRecordLocator: CloudReplicaTombstone],
        replicaEpoch: UUID,
        limits: CloudReplicaResourceLimits = .production
    ) throws {
        self.accountID = accountID
        self.configurationScopeFingerprint = configurationScopeFingerprint
        self.generation = generation
        self.finalCursor = finalCursor
        self.recordsByLogicalID = recordsByLogicalID
        self.providerLocatorByLogicalID = providerLocatorByLogicalID
        self.logicalIDByProviderLocator = logicalIDByProviderLocator
        self.tombstonesByProviderLocator = tombstonesByProviderLocator
        self.replicaEpoch = replicaEpoch
        try validate(limits: limits)
    }

    func validate(limits: CloudReplicaResourceLimits = .production) throws {
        guard generation > 0 else {
            throw CloudReplicaCheckpointValidationError.invalidGeneration
        }
        guard !accountID.rawValue.isEmpty else {
            throw CloudReplicaCheckpointValidationError.invalidAccountID
        }
        guard finalCursor.rawValue.count <= limits.maxCursorBytes else {
            throw CloudReplicaCheckpointValidationError.cursorLimitExceeded
        }
        guard recordsByLogicalID.count <= limits.maxRecordCount else {
            throw CloudReplicaCheckpointValidationError.recordLimitExceeded
        }
        guard tombstonesByProviderLocator.count <= limits.maxTombstoneCount else {
            throw CloudReplicaCheckpointValidationError.tombstoneLimitExceeded
        }
        var totalBytes = 0
        for (logicalID, record) in recordsByLogicalID {
            guard !logicalID.rawValue.isEmpty, !record.id.rawValue.isEmpty else {
                throw CloudReplicaCheckpointValidationError.invalidLogicalRecordID
            }
            guard logicalID == record.id else {
                throw CloudReplicaCheckpointValidationError.recordKeyMismatch
            }
            guard !record.recordType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CloudReplicaCheckpointValidationError.invalidRecordType
            }
            guard !record.changeTag.rawValue.isEmpty else {
                throw CloudReplicaCheckpointValidationError.invalidChangeTag
            }
            guard record.fields.keys.allSatisfy({ !$0.isEmpty }) else {
                throw CloudReplicaCheckpointValidationError.invalidFieldName
            }
            let recordBytes = try Self.byteCount(for: record)
            guard recordBytes <= limits.maxBytesPerRecord else {
                throw CloudReplicaCheckpointValidationError.recordByteLimitExceeded
            }
            totalBytes = try Self.adding(recordBytes, to: totalBytes)
        }

        guard providerLocatorByLogicalID.count == recordsByLogicalID.count,
              logicalIDByProviderLocator.count == recordsByLogicalID.count,
              Set(providerLocatorByLogicalID.keys) == Set(recordsByLogicalID.keys),
              Set(logicalIDByProviderLocator.values) == Set(recordsByLogicalID.keys)
        else {
            throw CloudReplicaCheckpointValidationError.incompleteLocatorIndex
        }

        for (logicalID, locator) in providerLocatorByLogicalID {
            guard logicalIDByProviderLocator[locator] == logicalID else {
                throw CloudReplicaCheckpointValidationError.nonBijectiveLocatorIndex
            }
            totalBytes = try Self.adding(logicalID.rawValue.utf8.count, to: totalBytes)
            totalBytes = try Self.adding(locator.rawValue.utf8.count, to: totalBytes)
        }
        for (locator, logicalID) in logicalIDByProviderLocator {
            guard providerLocatorByLogicalID[logicalID] == locator else {
                throw CloudReplicaCheckpointValidationError.nonBijectiveLocatorIndex
            }
            totalBytes = try Self.adding(locator.rawValue.utf8.count, to: totalBytes)
            totalBytes = try Self.adding(logicalID.rawValue.utf8.count, to: totalBytes)
        }

        var tombstonedLogicalIDs = Set<CloudRecordID>()
        for (locator, tombstone) in tombstonesByProviderLocator {
            guard locator == tombstone.locator else {
                throw CloudReplicaCheckpointValidationError.tombstoneKeyMismatch
            }
            guard !tombstone.recordType
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                throw CloudReplicaCheckpointValidationError.invalidRecordType
            }
            guard logicalIDByProviderLocator[locator] == nil else {
                throw CloudReplicaCheckpointValidationError.liveRecordIsTombstoned
            }
            if let logicalID = tombstone.logicalRecordID {
                guard !logicalID.rawValue.isEmpty else {
                    throw CloudReplicaCheckpointValidationError.invalidLogicalRecordID
                }
                guard recordsByLogicalID[logicalID] == nil,
                      providerLocatorByLogicalID[logicalID] == nil
                else {
                    throw CloudReplicaCheckpointValidationError.tombstoneLogicalRecordIsLive
                }
                guard tombstonedLogicalIDs.insert(logicalID).inserted else {
                    throw CloudReplicaCheckpointValidationError.ambiguousTombstoneMapping
                }
            }
            totalBytes = try Self.adding(locator.rawValue.utf8.count, to: totalBytes)
            totalBytes = try Self.adding(tombstone.recordType.utf8.count, to: totalBytes)
            totalBytes = try Self.adding(
                tombstone.logicalRecordID?.rawValue.utf8.count ?? 0,
                to: totalBytes
            )
        }
        totalBytes = try Self.adding(finalCursor.rawValue.count, to: totalBytes)
        guard totalBytes <= limits.maxTotalBytes else {
            throw CloudReplicaCheckpointValidationError.totalByteLimitExceeded
        }
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion
        case accountID
        case configurationScopeFingerprint
        case generation
        case finalCursor
        case recordsByLogicalID
        case providerLocatorByLogicalID
        case logicalIDByProviderLocator
        case tombstonesByProviderLocator
        case replicaEpoch
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(Int.self, forKey: .formatVersion) == Self.formatVersion else {
            throw CloudReplicaCheckpointValidationError.unsupportedFormatVersion
        }
        try self.init(
            accountID: container.decode(CloudAccountID.self, forKey: .accountID),
            configurationScopeFingerprint: container.decode(
                CloudReplicaScopeFingerprint.self,
                forKey: .configurationScopeFingerprint
            ),
            generation: container.decode(UInt64.self, forKey: .generation),
            finalCursor: container.decode(CloudChangeCursor.self, forKey: .finalCursor),
            recordsByLogicalID: container.decode(
                [CloudRecordID: CloudRecord].self,
                forKey: .recordsByLogicalID
            ),
            providerLocatorByLogicalID: container.decode(
                [CloudRecordID: CloudProviderRecordLocator].self,
                forKey: .providerLocatorByLogicalID
            ),
            logicalIDByProviderLocator: container.decode(
                [CloudProviderRecordLocator: CloudRecordID].self,
                forKey: .logicalIDByProviderLocator
            ),
            tombstonesByProviderLocator: container.decode(
                [CloudProviderRecordLocator: CloudReplicaTombstone].self,
                forKey: .tombstonesByProviderLocator
            ),
            replicaEpoch: container.decode(UUID.self, forKey: .replicaEpoch)
        )
    }

    func encode(to encoder: any Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.formatVersion, forKey: .formatVersion)
        try container.encode(accountID, forKey: .accountID)
        try container.encode(configurationScopeFingerprint, forKey: .configurationScopeFingerprint)
        try container.encode(generation, forKey: .generation)
        try container.encode(finalCursor, forKey: .finalCursor)
        try container.encode(recordsByLogicalID, forKey: .recordsByLogicalID)
        try container.encode(providerLocatorByLogicalID, forKey: .providerLocatorByLogicalID)
        try container.encode(logicalIDByProviderLocator, forKey: .logicalIDByProviderLocator)
        try container.encode(tombstonesByProviderLocator, forKey: .tombstonesByProviderLocator)
        try container.encode(replicaEpoch, forKey: .replicaEpoch)
    }

    private static func byteCount(for record: CloudRecord) throws -> Int {
        var total = 0
        total = try adding(record.id.rawValue.utf8.count, to: total)
        total = try adding(record.recordType.utf8.count, to: total)
        total = try adding(record.changeTag.rawValue.utf8.count, to: total)
        for (key, value) in record.fields {
            total = try adding(key.utf8.count, to: total)
            total = try adding(value.count, to: total)
        }
        return total
    }

    private static func adding(_ value: Int, to total: Int) throws -> Int {
        let (result, overflow) = total.addingReportingOverflow(value)
        guard !overflow else {
            throw CloudReplicaCheckpointValidationError.byteCountOverflow
        }
        return result
    }
}

private enum CloudReplicaCheckpointDigest {
    static func make(_ checkpoint: CloudReplicaCheckpointV1) -> Data {
        var builder = CloudReplicaDigestBuilder()
        builder.append("pocket-vector-cloud-replica-checkpoint-v1")
        builder.append(checkpoint.accountID.rawValue)
        builder.append(checkpoint.configurationScopeFingerprint.rawValue)
        builder.append(checkpoint.generation)
        builder.append(checkpoint.finalCursor.rawValue)
        builder.append(checkpoint.replicaEpoch)

        let recordIDs = checkpoint.recordsByLogicalID.keys.sorted {
            $0.rawValue < $1.rawValue
        }
        builder.append(UInt64(recordIDs.count))
        for recordID in recordIDs {
            if let record = checkpoint.recordsByLogicalID[recordID] {
                builder.append(record)
            }
        }

        let logicalLocatorIDs = checkpoint.providerLocatorByLogicalID.keys.sorted {
            $0.rawValue < $1.rawValue
        }
        builder.append(UInt64(logicalLocatorIDs.count))
        for logicalID in logicalLocatorIDs {
            builder.append(logicalID.rawValue)
            builder.append(checkpoint.providerLocatorByLogicalID[logicalID]?.rawValue ?? "")
        }

        let providerLocators = checkpoint.logicalIDByProviderLocator.keys.sorted {
            $0.rawValue < $1.rawValue
        }
        builder.append(UInt64(providerLocators.count))
        for locator in providerLocators {
            builder.append(locator.rawValue)
            builder.append(checkpoint.logicalIDByProviderLocator[locator]?.rawValue ?? "")
        }

        let tombstoneLocators = checkpoint.tombstonesByProviderLocator.keys.sorted {
            $0.rawValue < $1.rawValue
        }
        builder.append(UInt64(tombstoneLocators.count))
        for locator in tombstoneLocators {
            guard let tombstone = checkpoint.tombstonesByProviderLocator[locator] else { continue }
            builder.append(locator.rawValue)
            builder.append(tombstone.logicalRecordID != nil)
            if let logicalID = tombstone.logicalRecordID {
                builder.append(logicalID.rawValue)
            }
            builder.append(tombstone.recordType)
        }
        return builder.finalize()
    }
}

enum CloudReplicaAccumulatorError: Error, Equatable, Sendable {
    case accountMismatch
    case scopeMismatch
    case predecessorCursorMismatch
    case duplicateLogicalRecord
    case duplicateProviderLocator
    case duplicateDeletion
    case modificationDeletionOverlap
    case invalidRecordType
    case cursorDidNotAdvance
    case cursorCollision
    case logicalRecordRemap
    case providerLocatorRemap
    case recordTypeConflict
    case alreadyFinalized
    case generationOverflow
    case pageLimitExceeded
    case cursorLimitExceeded
    case recordLimitExceeded
    case tombstoneLimitExceeded
    case recordByteLimitExceeded
    case totalByteLimitExceeded
    case byteCountOverflow
}

/// A value-semantic page accumulator. Each page is applied to a local copy and
/// committed to the candidate only after every invariant succeeds. The only
/// externally persistable result is returned by a terminal page.
struct CloudReplicaStagedAccumulator: Sendable {
    private struct Candidate: Sendable {
        var cursor: CloudChangeCursor?
        var recordsByLogicalID: [CloudRecordID: CloudRecord]
        var providerLocatorByLogicalID: [CloudRecordID: CloudProviderRecordLocator]
        var logicalIDByProviderLocator: [CloudProviderRecordLocator: CloudRecordID]
        var tombstonesByProviderLocator: [CloudProviderRecordLocator: CloudReplicaTombstone]
    }

    let accountID: CloudAccountID
    let configurationScopeFingerprint: CloudReplicaScopeFingerprint
    let replicaEpoch: UUID

    private let startingGeneration: UInt64
    private let limits: CloudReplicaResourceLimits
    private var candidate: Candidate
    private var appliedPageDigestsByCursorData: [Data: Data] = [:]
    private var appliedPageMetadataByteCount = 0
    private var finalizedCheckpoint: CloudReplicaCheckpointV1?

    init(
        accountID: CloudAccountID,
        configurationScopeFingerprint: CloudReplicaScopeFingerprint,
        replicaEpoch: UUID,
        limits: CloudReplicaResourceLimits = .production
    ) {
        self.accountID = accountID
        self.configurationScopeFingerprint = configurationScopeFingerprint
        self.replicaEpoch = replicaEpoch
        startingGeneration = 0
        self.limits = limits
        candidate = Candidate(
            cursor: nil,
            recordsByLogicalID: [:],
            providerLocatorByLogicalID: [:],
            logicalIDByProviderLocator: [:],
            tombstonesByProviderLocator: [:]
        )
    }

    init(
        accountID: CloudAccountID,
        configurationScopeFingerprint: CloudReplicaScopeFingerprint,
        checkpoint: CloudReplicaCheckpointV1,
        limits: CloudReplicaResourceLimits = .production
    ) throws {
        try checkpoint.validate(limits: limits)
        guard checkpoint.accountID == accountID else {
            throw CloudReplicaAccumulatorError.accountMismatch
        }
        guard checkpoint.configurationScopeFingerprint == configurationScopeFingerprint else {
            throw CloudReplicaAccumulatorError.scopeMismatch
        }
        self.accountID = accountID
        self.configurationScopeFingerprint = configurationScopeFingerprint
        replicaEpoch = checkpoint.replicaEpoch
        startingGeneration = checkpoint.generation
        self.limits = limits
        candidate = Candidate(
            cursor: checkpoint.finalCursor,
            recordsByLogicalID: checkpoint.recordsByLogicalID,
            providerLocatorByLogicalID: checkpoint.providerLocatorByLogicalID,
            logicalIDByProviderLocator: checkpoint.logicalIDByProviderLocator,
            tombstonesByProviderLocator: checkpoint.tombstonesByProviderLocator
        )
    }

    /// Returns nil while more pages are required. Exact replay within the same
    /// staging session is idempotent; reuse of a cursor for different content
    /// is rejected.
    mutating func apply(_ fetchedPage: CloudReplicaFetchedPage) throws -> CloudReplicaCheckpointV1? {
        let page = fetchedPage.page
        guard page.accountID == accountID else {
            throw CloudReplicaAccumulatorError.accountMismatch
        }
        guard fetchedPage.configurationScopeFingerprint == configurationScopeFingerprint else {
            throw CloudReplicaAccumulatorError.scopeMismatch
        }

        let cursorData = page.nextCursor.rawValue
        let priorDigest = appliedPageDigestsByCursorData[cursorData]
        try Self.validatePageShape(page)
        try Self.validatePageResources(
            page,
            appliedPageCount: appliedPageDigestsByCursorData.count,
            isReplay: priorDigest != nil,
            limits: limits
        )

        let pageDigest = Self.digest(for: fetchedPage)
        if let priorDigest {
            guard priorDigest == pageDigest else {
                throw CloudReplicaAccumulatorError.cursorCollision
            }
            return page.moreComing ? nil : finalizedCheckpoint
        }
        if finalizedCheckpoint != nil {
            throw CloudReplicaAccumulatorError.alreadyFinalized
        }
        guard fetchedPage.requestedAfterCursor == candidate.cursor else {
            throw CloudReplicaAccumulatorError.predecessorCursorMismatch
        }
        if candidate.cursor == page.nextCursor {
            throw CloudReplicaAccumulatorError.cursorDidNotAdvance
        }

        var staged = candidate
        try Self.applyModifications(page.modifications, to: &staged)
        try Self.applyDeletions(page.deletions, to: &staged)
        staged.cursor = page.nextCursor
        let candidateByteCount = try Self.validateCandidateResources(
            staged,
            limits: limits
        )
        let pageMetadataByteCount = try Self.adding(
            pageDigest.count,
            to: cursorData.count
        )
        let stagedPageMetadataByteCount = try Self.adding(
            pageMetadataByteCount,
            to: appliedPageMetadataByteCount
        )
        let stagedTotalByteCount = try Self.adding(
            stagedPageMetadataByteCount,
            to: candidateByteCount
        )
        guard stagedTotalByteCount <= limits.maxTotalBytes else {
            throw CloudReplicaAccumulatorError.totalByteLimitExceeded
        }

        let completed: CloudReplicaCheckpointV1?
        if page.moreComing {
            completed = nil
        } else {
            let (generation, overflow) = startingGeneration.addingReportingOverflow(1)
            guard !overflow else {
                throw CloudReplicaAccumulatorError.generationOverflow
            }
            completed = try CloudReplicaCheckpointV1(
                accountID: accountID,
                configurationScopeFingerprint: configurationScopeFingerprint,
                generation: generation,
                finalCursor: page.nextCursor,
                recordsByLogicalID: staged.recordsByLogicalID,
                providerLocatorByLogicalID: staged.providerLocatorByLogicalID,
                logicalIDByProviderLocator: staged.logicalIDByProviderLocator,
                tombstonesByProviderLocator: staged.tombstonesByProviderLocator,
                replicaEpoch: replicaEpoch,
                limits: limits
            )
        }

        candidate = staged
        appliedPageDigestsByCursorData[cursorData] = pageDigest
        appliedPageMetadataByteCount = stagedPageMetadataByteCount
        finalizedCheckpoint = completed
        return completed
    }

    private static func validatePageShape(_ page: CloudRecordChangePage) throws {
        var logicalIDs = Set<CloudRecordID>()
        var modificationLocators = Set<CloudProviderRecordLocator>()
        for modification in page.modifications {
            guard !modification.record.recordType
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                throw CloudReplicaAccumulatorError.invalidRecordType
            }
            guard logicalIDs.insert(modification.record.id).inserted else {
                throw CloudReplicaAccumulatorError.duplicateLogicalRecord
            }
            guard modificationLocators.insert(modification.locator).inserted else {
                throw CloudReplicaAccumulatorError.duplicateProviderLocator
            }
        }

        var deletionLocators = Set<CloudProviderRecordLocator>()
        for deletion in page.deletions {
            guard !deletion.recordType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CloudReplicaAccumulatorError.invalidRecordType
            }
            guard deletionLocators.insert(deletion.locator).inserted else {
                throw CloudReplicaAccumulatorError.duplicateDeletion
            }
        }
        guard modificationLocators.isDisjoint(with: deletionLocators) else {
            throw CloudReplicaAccumulatorError.modificationDeletionOverlap
        }
    }

    private static func validatePageResources(
        _ page: CloudRecordChangePage,
        appliedPageCount: Int,
        isReplay: Bool,
        limits: CloudReplicaResourceLimits
    ) throws {
        guard isReplay || appliedPageCount < limits.maxPagesPerSync else {
            throw CloudReplicaAccumulatorError.pageLimitExceeded
        }
        let (changeCount, changeCountOverflow) = page.modifications.count.addingReportingOverflow(
            page.deletions.count
        )
        guard !changeCountOverflow, changeCount <= limits.maxPageChangeCount else {
            throw CloudReplicaAccumulatorError.pageLimitExceeded
        }
        guard page.nextCursor.rawValue.count <= limits.maxCursorBytes else {
            throw CloudReplicaAccumulatorError.cursorLimitExceeded
        }

        var pageBytes = page.nextCursor.rawValue.count
        for modification in page.modifications {
            let recordBytes = try recordByteCount(modification.record)
            guard recordBytes <= limits.maxBytesPerRecord else {
                throw CloudReplicaAccumulatorError.recordByteLimitExceeded
            }
            pageBytes = try adding(recordBytes, to: pageBytes)
            pageBytes = try adding(modification.locator.rawValue.utf8.count, to: pageBytes)
        }
        for deletion in page.deletions {
            pageBytes = try adding(deletion.locator.rawValue.utf8.count, to: pageBytes)
            pageBytes = try adding(deletion.recordType.utf8.count, to: pageBytes)
        }
        guard pageBytes <= limits.maxTotalBytes else {
            throw CloudReplicaAccumulatorError.totalByteLimitExceeded
        }
    }

    private static func validateCandidateResources(
        _ candidate: Candidate,
        limits: CloudReplicaResourceLimits
    ) throws -> Int {
        guard candidate.recordsByLogicalID.count <= limits.maxRecordCount else {
            throw CloudReplicaAccumulatorError.recordLimitExceeded
        }
        guard candidate.tombstonesByProviderLocator.count <= limits.maxTombstoneCount else {
            throw CloudReplicaAccumulatorError.tombstoneLimitExceeded
        }

        var totalBytes = candidate.cursor?.rawValue.count ?? 0
        for record in candidate.recordsByLogicalID.values {
            let recordBytes = try recordByteCount(record)
            guard recordBytes <= limits.maxBytesPerRecord else {
                throw CloudReplicaAccumulatorError.recordByteLimitExceeded
            }
            totalBytes = try adding(recordBytes, to: totalBytes)
        }
        for (logicalID, locator) in candidate.providerLocatorByLogicalID {
            totalBytes = try adding(logicalID.rawValue.utf8.count, to: totalBytes)
            totalBytes = try adding(locator.rawValue.utf8.count, to: totalBytes)
        }
        for (locator, logicalID) in candidate.logicalIDByProviderLocator {
            totalBytes = try adding(locator.rawValue.utf8.count, to: totalBytes)
            totalBytes = try adding(logicalID.rawValue.utf8.count, to: totalBytes)
        }
        for tombstone in candidate.tombstonesByProviderLocator.values {
            totalBytes = try adding(tombstone.locator.rawValue.utf8.count, to: totalBytes)
            totalBytes = try adding(tombstone.recordType.utf8.count, to: totalBytes)
            totalBytes = try adding(
                tombstone.logicalRecordID?.rawValue.utf8.count ?? 0,
                to: totalBytes
            )
        }
        guard totalBytes <= limits.maxTotalBytes else {
            throw CloudReplicaAccumulatorError.totalByteLimitExceeded
        }
        return totalBytes
    }

    private static func recordByteCount(_ record: CloudRecord) throws -> Int {
        var total = 0
        total = try adding(record.id.rawValue.utf8.count, to: total)
        total = try adding(record.recordType.utf8.count, to: total)
        total = try adding(record.changeTag.rawValue.utf8.count, to: total)
        for (key, value) in record.fields {
            total = try adding(key.utf8.count, to: total)
            total = try adding(value.count, to: total)
        }
        return total
    }

    private static func adding(_ value: Int, to total: Int) throws -> Int {
        let (result, overflow) = total.addingReportingOverflow(value)
        guard !overflow else {
            throw CloudReplicaAccumulatorError.byteCountOverflow
        }
        return result
    }

    private static func digest(for fetchedPage: CloudReplicaFetchedPage) -> Data {
        var builder = CloudReplicaDigestBuilder()
        builder.append("pocket-vector-cloud-replica-page-v1")
        builder.append(fetchedPage.configurationScopeFingerprint.rawValue)
        builder.append(fetchedPage.requestedAfterCursor)
        builder.append(fetchedPage.page.accountID.rawValue)
        builder.append(fetchedPage.page.nextCursor.rawValue)
        builder.append(fetchedPage.page.moreComing)

        let modifications = fetchedPage.page.modifications.sorted {
            if $0.locator.rawValue != $1.locator.rawValue {
                return $0.locator.rawValue < $1.locator.rawValue
            }
            return $0.record.id.rawValue < $1.record.id.rawValue
        }
        builder.append(UInt64(modifications.count))
        for modification in modifications {
            builder.append(modification.locator.rawValue)
            builder.append(modification.record)
        }

        let deletions = fetchedPage.page.deletions.sorted {
            if $0.locator.rawValue != $1.locator.rawValue {
                return $0.locator.rawValue < $1.locator.rawValue
            }
            return $0.recordType < $1.recordType
        }
        builder.append(UInt64(deletions.count))
        for deletion in deletions {
            builder.append(deletion.locator.rawValue)
            builder.append(deletion.recordType)
        }
        return builder.finalize()
    }

    private static func applyModifications(
        _ modifications: [CloudDiscoveredRecord],
        to candidate: inout Candidate
    ) throws {
        for modification in modifications {
            let logicalID = modification.record.id
            let locator = modification.locator

            if let priorLocator = candidate.providerLocatorByLogicalID[logicalID],
               priorLocator != locator
            {
                throw CloudReplicaAccumulatorError.logicalRecordRemap
            }
            if let priorLogicalID = candidate.logicalIDByProviderLocator[locator],
               priorLogicalID != logicalID
            {
                throw CloudReplicaAccumulatorError.providerLocatorRemap
            }
            if let priorRecord = candidate.recordsByLogicalID[logicalID],
               priorRecord.recordType != modification.record.recordType
            {
                throw CloudReplicaAccumulatorError.recordTypeConflict
            }

            if let tombstone = candidate.tombstonesByProviderLocator[locator] {
                if let priorLogicalID = tombstone.logicalRecordID,
                   priorLogicalID != logicalID
                {
                    throw CloudReplicaAccumulatorError.providerLocatorRemap
                }
                guard tombstone.recordType == modification.record.recordType else {
                    throw CloudReplicaAccumulatorError.recordTypeConflict
                }
            }
            if candidate.tombstonesByProviderLocator.values.contains(where: {
                $0.logicalRecordID == logicalID && $0.locator != locator
            }) {
                throw CloudReplicaAccumulatorError.logicalRecordRemap
            }

            candidate.tombstonesByProviderLocator.removeValue(forKey: locator)
            candidate.recordsByLogicalID[logicalID] = modification.record
            candidate.providerLocatorByLogicalID[logicalID] = locator
            candidate.logicalIDByProviderLocator[locator] = logicalID
        }
    }

    private static func applyDeletions(
        _ deletions: [CloudDeletedRecord],
        to candidate: inout Candidate
    ) throws {
        for deletion in deletions {
            let locator = deletion.locator
            if let logicalID = candidate.logicalIDByProviderLocator[locator] {
                guard let record = candidate.recordsByLogicalID[logicalID],
                      record.recordType == deletion.recordType
                else {
                    throw CloudReplicaAccumulatorError.recordTypeConflict
                }
                candidate.recordsByLogicalID.removeValue(forKey: logicalID)
                candidate.providerLocatorByLogicalID.removeValue(forKey: logicalID)
                candidate.logicalIDByProviderLocator.removeValue(forKey: locator)
                candidate.tombstonesByProviderLocator[locator] = CloudReplicaTombstone(
                    locator: locator,
                    logicalRecordID: logicalID,
                    recordType: deletion.recordType
                )
            } else if let existing = candidate.tombstonesByProviderLocator[locator] {
                guard existing.recordType == deletion.recordType else {
                    throw CloudReplicaAccumulatorError.recordTypeConflict
                }
            } else {
                candidate.tombstonesByProviderLocator[locator] = CloudReplicaTombstone(
                    locator: locator,
                    logicalRecordID: nil,
                    recordType: deletion.recordType
                )
            }
        }
    }
}

enum CloudReplicaCheckpointLoadSource: String, Equatable, Sendable {
    case primary
    case backup
    case none
}

struct CloudReplicaCheckpointLoadResult: Equatable, Sendable {
    let checkpoint: CloudReplicaCheckpointV1?
    let source: CloudReplicaCheckpointLoadSource
    let quarantinedFileCount: Int
}

enum CloudReplicaCheckpointStoreError: Error, Equatable, Sendable {
    case invalidCheckpoint
    case encodingFailure
    case ioFailure
    case replicaEpochNotActive
    case replicaEpochRevoked
    case replicaEpochMismatch
    case staleGeneration
    case generationGap
    case generationCollision
}

protocol CloudReplicaCheckpointStoring: Sendable {
    func activate(replicaEpoch: UUID, for accountID: CloudAccountID) async throws

    func load(
        for accountID: CloudAccountID,
        configurationScopeFingerprint: CloudReplicaScopeFingerprint,
        at date: Date
    ) async throws -> CloudReplicaCheckpointLoadResult

    func save(_ checkpoint: CloudReplicaCheckpointV1, at date: Date) async throws
    func remove(for accountID: CloudAccountID, revoking replicaEpoch: UUID) async throws
}

protocol CloudReplicaCheckpointFileSystem: Sendable {
    func createDirectory(at url: URL) throws
    func fileExists(at url: URL) -> Bool
    func fileSize(at url: URL) throws -> Int
    func read(from url: URL) throws -> Data
    func writeAtomically(_ data: Data, to url: URL) throws
    func moveItem(at sourceURL: URL, to destinationURL: URL) throws
    func removeItem(at url: URL) throws
    func withExclusiveLock(at url: URL, perform: () throws -> Void) throws
}

struct FoundationCloudReplicaCheckpointFileSystem: CloudReplicaCheckpointFileSystem {
    func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    func fileSize(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let size = attributes[.size] as? NSNumber else {
            throw CloudReplicaCheckpointStoreError.ioFailure
        }
        return size.intValue
    }

    func read(from url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    func writeAtomically(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }

    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
    }

    func removeItem(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    func withExclusiveLock(at url: URL, perform: () throws -> Void) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let descriptor = url.path.withCString {
            Darwin.open($0, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        }
        guard descriptor >= 0 else {
            throw CloudReplicaCheckpointStoreError.ioFailure
        }
        let flockOperation: (Int32, Int32) -> Int32 = flock
        defer {
            _ = flockOperation(descriptor, LOCK_UN)
            _ = Darwin.close(descriptor)
        }
        guard flockOperation(descriptor, LOCK_EX) == 0 else {
            throw CloudReplicaCheckpointStoreError.ioFailure
        }
        try perform()
    }
}

/// Account-scoped primary/backup persistence. The external authority retains
/// the last accepted checkpoint watermark plus at most one pending successor.
/// Publication records pending first, writes both replicas, then promotes that
/// exact digest to accepted; account-local files remain recoverable cache.
actor AtomicCloudReplicaCheckpointDiskStore: CloudReplicaCheckpointStoring {
    private struct EnvelopeV1: Codable {
        static let formatVersion = 1

        let savedAt: Date
        let checkpoint: CloudReplicaCheckpointV1

        private enum CodingKeys: String, CodingKey {
            case formatVersion
            case savedAt
            case checkpoint
        }

        init(savedAt: Date, checkpoint: CloudReplicaCheckpointV1) {
            self.savedAt = savedAt
            self.checkpoint = checkpoint
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            guard try container.decode(Int.self, forKey: .formatVersion) == Self.formatVersion else {
                throw CloudReplicaCheckpointValidationError.unsupportedFormatVersion
            }
            savedAt = try container.decode(Date.self, forKey: .savedAt)
            checkpoint = try container.decode(CloudReplicaCheckpointV1.self, forKey: .checkpoint)
            try checkpoint.validate()
        }

        func encode(to encoder: any Encoder) throws {
            try checkpoint.validate()
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(Self.formatVersion, forKey: .formatVersion)
            try container.encode(savedAt, forKey: .savedAt)
            try container.encode(checkpoint, forKey: .checkpoint)
        }
    }

    private struct WatermarkV1: Codable, Equatable {
        static let formatVersion = 1
        static let digestByteCount = SHA256.byteCount

        let accountID: CloudAccountID
        let configurationScopeFingerprint: CloudReplicaScopeFingerprint
        let replicaEpoch: UUID
        let generation: UInt64
        let checkpointDigest: Data

        init(checkpoint: CloudReplicaCheckpointV1) {
            accountID = checkpoint.accountID
            configurationScopeFingerprint = checkpoint.configurationScopeFingerprint
            replicaEpoch = checkpoint.replicaEpoch
            generation = checkpoint.generation
            checkpointDigest = CloudReplicaCheckpointDigest.make(checkpoint)
        }

        private enum CodingKeys: String, CodingKey {
            case formatVersion
            case accountID
            case configurationScopeFingerprint
            case replicaEpoch
            case generation
            case checkpointDigest
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            guard try container.decode(Int.self, forKey: .formatVersion) == Self.formatVersion else {
                throw CloudReplicaCheckpointValidationError.unsupportedFormatVersion
            }
            accountID = try container.decode(CloudAccountID.self, forKey: .accountID)
            configurationScopeFingerprint = try container.decode(
                CloudReplicaScopeFingerprint.self,
                forKey: .configurationScopeFingerprint
            )
            replicaEpoch = try container.decode(UUID.self, forKey: .replicaEpoch)
            generation = try container.decode(UInt64.self, forKey: .generation)
            checkpointDigest = try container.decode(Data.self, forKey: .checkpointDigest)
            guard !accountID.rawValue.isEmpty,
                  generation > 0,
                  checkpointDigest.count == Self.digestByteCount else {
                throw CloudReplicaCheckpointStoreError.invalidCheckpoint
            }
        }

        func encode(to encoder: any Encoder) throws {
            guard generation > 0, checkpointDigest.count == Self.digestByteCount else {
                throw CloudReplicaCheckpointStoreError.invalidCheckpoint
            }
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(Self.formatVersion, forKey: .formatVersion)
            try container.encode(accountID, forKey: .accountID)
            try container.encode(
                configurationScopeFingerprint,
                forKey: .configurationScopeFingerprint
            )
            try container.encode(replicaEpoch, forKey: .replicaEpoch)
            try container.encode(generation, forKey: .generation)
            try container.encode(checkpointDigest, forKey: .checkpointDigest)
        }
    }

    /// A single fixed-size authority record owns the current replica epoch for
    /// an account. The bounded revoked-epoch filter has no false negatives;
    /// saturation can only reject a fresh epoch, never resurrect an old one.
    private struct ReplicaEpochAuthorityV1: Codable, Equatable {
        static let formatVersion = 1
        static let revokedEpochFilterByteCount = 32 * 1_024
        static let revokedEpochHashCount = 7

        enum State: String, Codable {
            case active
            case revoked
        }

        let accountID: CloudAccountID
        let replicaEpoch: UUID
        let revision: UInt64
        let state: State
        let revokedEpochFilter: Data
        let checkpointHighWatermark: WatermarkV1?
        let pendingCheckpointHighWatermark: WatermarkV1?

        init(active replicaEpoch: UUID, for accountID: CloudAccountID) {
            self.accountID = accountID
            self.replicaEpoch = replicaEpoch
            revision = 1
            state = .active
            revokedEpochFilter = Data(
                repeating: 0,
                count: Self.revokedEpochFilterByteCount
            )
            checkpointHighWatermark = nil
            pendingCheckpointHighWatermark = nil
        }

        private init(
            accountID: CloudAccountID,
            replicaEpoch: UUID,
            revision: UInt64,
            state: State,
            revokedEpochFilter: Data,
            checkpointHighWatermark: WatermarkV1?,
            pendingCheckpointHighWatermark: WatermarkV1?
        ) {
            self.accountID = accountID
            self.replicaEpoch = replicaEpoch
            self.revision = revision
            self.state = state
            self.revokedEpochFilter = revokedEpochFilter
            self.checkpointHighWatermark = checkpointHighWatermark
            self.pendingCheckpointHighWatermark = pendingCheckpointHighWatermark
        }

        private enum CodingKeys: String, CodingKey {
            case formatVersion
            case accountID
            case replicaEpoch
            case revision
            case state
            case revokedEpochFilter
            case checkpointHighWatermark
            case pendingCheckpointHighWatermark
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            guard try container.decode(Int.self, forKey: .formatVersion)
                == Self.formatVersion else {
                throw CloudReplicaCheckpointValidationError.unsupportedFormatVersion
            }
            accountID = try container.decode(CloudAccountID.self, forKey: .accountID)
            replicaEpoch = try container.decode(UUID.self, forKey: .replicaEpoch)
            revision = try container.decode(UInt64.self, forKey: .revision)
            state = try container.decode(State.self, forKey: .state)
            revokedEpochFilter = try container.decode(
                Data.self,
                forKey: .revokedEpochFilter
            )
            checkpointHighWatermark = try container.decodeIfPresent(
                WatermarkV1.self,
                forKey: .checkpointHighWatermark
            )
            pendingCheckpointHighWatermark = try container.decodeIfPresent(
                WatermarkV1.self,
                forKey: .pendingCheckpointHighWatermark
            )
            try validate()
        }

        func encode(to encoder: any Encoder) throws {
            try validate()
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(Self.formatVersion, forKey: .formatVersion)
            try container.encode(accountID, forKey: .accountID)
            try container.encode(replicaEpoch, forKey: .replicaEpoch)
            try container.encode(revision, forKey: .revision)
            try container.encode(state, forKey: .state)
            try container.encode(revokedEpochFilter, forKey: .revokedEpochFilter)
            try container.encodeIfPresent(
                checkpointHighWatermark,
                forKey: .checkpointHighWatermark
            )
            try container.encodeIfPresent(
                pendingCheckpointHighWatermark,
                forKey: .pendingCheckpointHighWatermark
            )
        }

        func validate() throws {
            guard !accountID.rawValue.isEmpty,
                  revision > 0,
                  revokedEpochFilter.count == Self.revokedEpochFilterByteCount else {
                throw CloudReplicaCheckpointStoreError.invalidCheckpoint
            }
            if let checkpointHighWatermark {
                guard checkpointHighWatermark.accountID == accountID,
                      checkpointHighWatermark.replicaEpoch == replicaEpoch else {
                    throw CloudReplicaCheckpointStoreError.invalidCheckpoint
                }
            }
            if let pendingCheckpointHighWatermark {
                guard pendingCheckpointHighWatermark.accountID == accountID,
                      pendingCheckpointHighWatermark.replicaEpoch == replicaEpoch else {
                    throw CloudReplicaCheckpointStoreError.invalidCheckpoint
                }
                if let checkpointHighWatermark {
                    let (expected, overflow) = checkpointHighWatermark.generation
                        .addingReportingOverflow(1)
                    guard !overflow,
                          pendingCheckpointHighWatermark.generation == expected else {
                        throw CloudReplicaCheckpointStoreError.invalidCheckpoint
                    }
                } else {
                    guard pendingCheckpointHighWatermark.generation == 1 else {
                        throw CloudReplicaCheckpointStoreError.invalidCheckpoint
                    }
                }
            }
            switch state {
            case .active:
                guard !containsRevoked(replicaEpoch) else {
                    throw CloudReplicaCheckpointStoreError.invalidCheckpoint
                }
            case .revoked:
                guard containsRevoked(replicaEpoch) else {
                    throw CloudReplicaCheckpointStoreError.invalidCheckpoint
                }
            }
        }

        func containsRevoked(_ epoch: UUID) -> Bool {
            Self.filterPositions(accountID: accountID, epoch: epoch).allSatisfy {
                position in
                let byteIndex = revokedEpochFilter.startIndex + position / 8
                let mask = UInt8(1 << (position % 8))
                return revokedEpochFilter[byteIndex] & mask != 0
            }
        }

        func revokingCurrentEpoch() throws -> Self {
            guard state == .active else { return self }
            let nextRevision = try incrementedRevision()
            var filter = revokedEpochFilter
            for position in Self.filterPositions(
                accountID: accountID,
                epoch: replicaEpoch
            ) {
                let byteIndex = filter.startIndex + position / 8
                filter[byteIndex] |= UInt8(1 << (position % 8))
            }
            return Self(
                accountID: accountID,
                replicaEpoch: replicaEpoch,
                revision: nextRevision,
                state: .revoked,
                revokedEpochFilter: filter,
                checkpointHighWatermark: nil,
                pendingCheckpointHighWatermark: nil
            )
        }

        func activating(_ newEpoch: UUID) throws -> Self {
            guard state == .revoked, !containsRevoked(newEpoch) else {
                throw CloudReplicaCheckpointStoreError.replicaEpochRevoked
            }
            return Self(
                accountID: accountID,
                replicaEpoch: newEpoch,
                revision: try incrementedRevision(),
                state: .active,
                revokedEpochFilter: revokedEpochFilter,
                checkpointHighWatermark: nil,
                pendingCheckpointHighWatermark: nil
            )
        }

        func beginningCheckpointPublication(
            _ watermark: WatermarkV1
        ) throws -> Self {
            guard state == .active,
                  watermark.accountID == accountID,
                  watermark.replicaEpoch == replicaEpoch else {
                throw CloudReplicaCheckpointStoreError.replicaEpochMismatch
            }
            if let pendingCheckpointHighWatermark {
                guard pendingCheckpointHighWatermark == watermark else {
                    throw CloudReplicaCheckpointStoreError.generationCollision
                }
                return self
            }
            guard checkpointHighWatermark != watermark else { return self }
            if let checkpointHighWatermark {
                let (expected, overflow) = checkpointHighWatermark.generation
                    .addingReportingOverflow(1)
                guard !overflow, watermark.generation == expected else {
                    throw CloudReplicaCheckpointStoreError.generationGap
                }
            } else {
                guard watermark.generation == 1 else {
                    throw CloudReplicaCheckpointStoreError.generationGap
                }
            }
            return Self(
                accountID: accountID,
                replicaEpoch: replicaEpoch,
                revision: try incrementedRevision(),
                state: state,
                revokedEpochFilter: revokedEpochFilter,
                checkpointHighWatermark: checkpointHighWatermark,
                pendingCheckpointHighWatermark: watermark
            )
        }

        func acceptingPublishedCheckpoint(
            _ watermark: WatermarkV1
        ) throws -> Self {
            guard state == .active,
                  watermark.accountID == accountID,
                  watermark.replicaEpoch == replicaEpoch else {
                throw CloudReplicaCheckpointStoreError.replicaEpochMismatch
            }
            if pendingCheckpointHighWatermark == nil,
               checkpointHighWatermark == watermark {
                return self
            }
            if let pendingCheckpointHighWatermark {
                guard pendingCheckpointHighWatermark == watermark else {
                    throw CloudReplicaCheckpointStoreError.generationCollision
                }
            } else {
                guard checkpointHighWatermark == nil, watermark.generation == 1 else {
                    throw CloudReplicaCheckpointStoreError.generationCollision
                }
            }
            return Self(
                accountID: accountID,
                replicaEpoch: replicaEpoch,
                revision: try incrementedRevision(),
                state: state,
                revokedEpochFilter: revokedEpochFilter,
                checkpointHighWatermark: watermark,
                pendingCheckpointHighWatermark: nil
            )
        }

        func abortingCheckpointPublication(
            _ watermark: WatermarkV1
        ) throws -> Self {
            guard state == .active,
                  pendingCheckpointHighWatermark == watermark else {
                throw CloudReplicaCheckpointStoreError.generationCollision
            }
            return Self(
                accountID: accountID,
                replicaEpoch: replicaEpoch,
                revision: try incrementedRevision(),
                state: state,
                revokedEpochFilter: revokedEpochFilter,
                checkpointHighWatermark: checkpointHighWatermark,
                pendingCheckpointHighWatermark: nil
            )
        }

        /// Adopts a checkpoint discovered through the legacy account-local
        /// watermark or matching replica copies. Only load-time migration may
        /// use this transition; ordinary publication must start at generation
        /// one or advance the durable accepted watermark by exactly one.
        func acceptingResolvedLegacyCheckpoint(
            _ watermark: WatermarkV1
        ) throws -> Self {
            guard state == .active,
                  watermark.accountID == accountID,
                  watermark.replicaEpoch == replicaEpoch else {
                throw CloudReplicaCheckpointStoreError.replicaEpochMismatch
            }
            if let pendingCheckpointHighWatermark {
                guard pendingCheckpointHighWatermark == watermark else {
                    throw CloudReplicaCheckpointStoreError.generationCollision
                }
                return try acceptingPublishedCheckpoint(watermark)
            }
            if let checkpointHighWatermark {
                guard checkpointHighWatermark == watermark else {
                    throw CloudReplicaCheckpointStoreError.generationCollision
                }
                return self
            }
            return Self(
                accountID: accountID,
                replicaEpoch: replicaEpoch,
                revision: try incrementedRevision(),
                state: state,
                revokedEpochFilter: revokedEpochFilter,
                checkpointHighWatermark: watermark,
                pendingCheckpointHighWatermark: nil
            )
        }

        private func incrementedRevision() throws -> UInt64 {
            let (next, overflow) = revision.addingReportingOverflow(1)
            guard !overflow else {
                throw CloudReplicaCheckpointStoreError.invalidCheckpoint
            }
            return next
        }

        private static func filterPositions(
            accountID: CloudAccountID,
            epoch: UUID
        ) -> [Int] {
            var builder = CloudReplicaDigestBuilder()
            builder.append("pocket-vector-cloud-replica-revoked-epoch-filter-v1")
            builder.append(accountID.rawValue)
            builder.append(epoch)
            let digest = builder.finalize()
            let first = digest.prefix(8).reduce(UInt64(0)) {
                ($0 << 8) | UInt64($1)
            }
            let second = digest.dropFirst(8).prefix(8).reduce(UInt64(0)) {
                ($0 << 8) | UInt64($1)
            } | 1
            let bitCount = UInt64(revokedEpochFilterByteCount * 8)
            return (0 ..< revokedEpochHashCount).map { index in
                Int((first &+ UInt64(index) &* second) % bitCount)
            }
        }
    }

    private struct StoredCopy {
        let source: CloudReplicaCheckpointLoadSource
        let url: URL
        let data: Data
        let envelope: EnvelopeV1
        let checkpointDigest: Data
    }

    private enum WatermarkReadState {
        case absent
        case valid(WatermarkV1)
        case invalid
    }

    private struct Locations {
        let accountDirectory: URL
        let primary: URL
        let backup: URL
        let watermark: URL
        let quarantineDirectory: URL
        let authorityDirectory: URL
        let authority: URL
        let authorityLock: URL
    }

    nonisolated let rootDirectoryURL: URL
    private let fileSystem: any CloudReplicaCheckpointFileSystem
    private let limits: CloudReplicaResourceLimits
    private var activeEpochByAccount: [CloudAccountID: UUID] = [:]

    init(
        rootDirectoryURL: URL,
        fileSystem: any CloudReplicaCheckpointFileSystem =
            FoundationCloudReplicaCheckpointFileSystem(),
        limits: CloudReplicaResourceLimits = .production
    ) {
        self.rootDirectoryURL = rootDirectoryURL
        self.fileSystem = fileSystem
        self.limits = limits
    }

    func activate(replicaEpoch: UUID, for accountID: CloudAccountID) throws {
        let locations = locations(for: accountID)
        try withAccountLock(locations: locations) {
            let existing = try readAuthority(
                for: accountID,
                locations: locations
            )
            let activated: ReplicaEpochAuthorityV1
            if let existing {
                if existing.containsRevoked(replicaEpoch) {
                    throw CloudReplicaCheckpointStoreError.replicaEpochRevoked
                }
                if existing.replicaEpoch == replicaEpoch {
                    guard existing.state == .active else {
                        throw CloudReplicaCheckpointStoreError.replicaEpochRevoked
                    }
                    activated = existing
                } else {
                    guard existing.state == .revoked else {
                        throw CloudReplicaCheckpointStoreError.replicaEpochMismatch
                    }
                    // A completed revocation owns the old account directory.
                    // Clear it before publishing authority for the next epoch.
                    try removeAccountDirectoryIfPresent(locations)
                    activated = try existing.activating(replicaEpoch)
                    try writeAuthority(activated, locations: locations)
                }
            } else {
                // Missing authority means the account-local directory has no
                // trusted owner. Clear that recoverable cache before publishing
                // a new epoch, so a crash cannot bind new authority to old data.
                try removeAccountDirectoryIfPresent(locations)
                activated = ReplicaEpochAuthorityV1(
                    active: replicaEpoch,
                    for: accountID
                )
                try writeAuthority(activated, locations: locations)
            }

            guard try readAuthority(for: accountID, locations: locations)
                == activated else {
                throw CloudReplicaCheckpointStoreError.invalidCheckpoint
            }
            activeEpochByAccount[accountID] = replicaEpoch
        }
    }

    func load(
        for accountID: CloudAccountID,
        configurationScopeFingerprint: CloudReplicaScopeFingerprint,
        at date: Date
    ) throws -> CloudReplicaCheckpointLoadResult {
        _ = date
        let locations = locations(for: accountID)
        return try withAccountLock(locations: locations) {
            do {
                let authority = try readAuthority(
                    for: accountID,
                    locations: locations
                )
                if let rememberedEpoch = activeEpochByAccount[accountID] {
                    guard let authority else {
                        throw CloudReplicaCheckpointStoreError.replicaEpochNotActive
                    }
                    if authority.containsRevoked(rememberedEpoch) {
                        throw CloudReplicaCheckpointStoreError.replicaEpochRevoked
                    }
                    guard authority.state == .active,
                          authority.replicaEpoch == rememberedEpoch else {
                        throw CloudReplicaCheckpointStoreError.replicaEpochMismatch
                    }
                }
                // Discovery remains available to a fresh store with no
                // remembered epoch. A stale activated store fails above before
                // it can create, quarantine, or repair account-local files.
                try fileSystem.createDirectory(at: locations.accountDirectory)
                var quarantinedCount = 0
                let watermarkState = validatedWatermark(
                    at: locations.watermark,
                    accountID: accountID,
                    fingerprint: configurationScopeFingerprint,
                    locations: locations,
                    quarantinedCount: &quarantinedCount
                )
                let primary = validatedCopy(
                    at: locations.primary,
                    source: .primary,
                    accountID: accountID,
                    fingerprint: configurationScopeFingerprint,
                    locations: locations,
                    quarantinedCount: &quarantinedCount
                )
                let backup = validatedCopy(
                    at: locations.backup,
                    source: .backup,
                    accountID: accountID,
                    fingerprint: configurationScopeFingerprint,
                    locations: locations,
                    quarantinedCount: &quarantinedCount
                )

                let acceptedHighWatermark = authority?.checkpointHighWatermark
                let pendingHighWatermark = authority?.pendingCheckpointHighWatermark
                let durableHighWatermark = pendingHighWatermark
                    ?? acceptedHighWatermark
                let resolutionWatermark: WatermarkV1?
                switch watermarkState {
                case .absent:
                    resolutionWatermark = durableHighWatermark
                case let .valid(observedWatermark):
                    if let durableHighWatermark,
                       observedWatermark != durableHighWatermark {
                        if quarantine(locations.watermark, locations: locations) {
                            quarantinedCount += 1
                        }
                        resolutionWatermark = durableHighWatermark
                    } else {
                        resolutionWatermark = observedWatermark
                    }
                case .invalid:
                    guard let durableHighWatermark else {
                        // Corrupt account-local evidence has no durable owner.
                        // Reset it fully so a fresh generation one is not pinned
                        // by the fixed quarantine marker on the next save.
                        try removeAccountDirectoryIfPresent(locations)
                        return CloudReplicaCheckpointLoadResult(
                            checkpoint: nil,
                            source: .none,
                            quarantinedFileCount: quarantinedCount
                        )
                    }
                    resolutionWatermark = durableHighWatermark
                }

                var winner = resolve(
                    primary: primary,
                    backup: backup,
                    watermark: resolutionWatermark,
                    preserving: pendingHighWatermark == nil
                        ? nil
                        : acceptedHighWatermark,
                    locations: locations,
                    quarantinedCount: &quarantinedCount
                )
                var resolvedAuthority = authority
                if winner == nil,
                   let authority,
                   let pendingHighWatermark,
                   let acceptedHighWatermark,
                   let acceptedWinner = resolve(
                       primary: primary,
                       backup: backup,
                       watermark: acceptedHighWatermark,
                       locations: locations,
                       quarantinedCount: &quarantinedCount
                   ) {
                    // No replica acknowledges the pending intent. Cancel it
                    // durably before repairing and returning the last accepted
                    // checkpoint so a newly derived next generation can save.
                    let recoveredAuthority = try authority
                        .abortingCheckpointPublication(pendingHighWatermark)
                    try writeAuthority(recoveredAuthority, locations: locations)
                    guard try readAuthority(
                        for: accountID,
                        locations: locations
                    ) == recoveredAuthority else {
                        throw CloudReplicaCheckpointStoreError.invalidCheckpoint
                    }
                    resolvedAuthority = recoveredAuthority
                    winner = acceptedWinner
                }
                if winner == nil,
                   let authority,
                   let pendingHighWatermark,
                   acceptedHighWatermark == nil {
                    // An interrupted genesis has no accepted checkpoint to
                    // restore. Clear account-local evidence first, so a crash
                    // can only leave the durable pending intent in place, then
                    // abort it to permit a reconstructed generation one.
                    try removeWatermarkEvidence(locations)
                    let recoveredAuthority = try authority
                        .abortingCheckpointPublication(pendingHighWatermark)
                    try writeAuthority(recoveredAuthority, locations: locations)
                    guard try readAuthority(
                        for: accountID,
                        locations: locations
                    ) == recoveredAuthority else {
                        throw CloudReplicaCheckpointStoreError.invalidCheckpoint
                    }
                }
                if winner == nil, durableHighWatermark == nil {
                    // A valid legacy checkpoint is adopted only after resolution
                    // yields a usable winner. Everything else is unowned cache.
                    try removeAccountDirectoryIfPresent(locations)
                }
                guard let winner else {
                    return CloudReplicaCheckpointLoadResult(
                        checkpoint: nil,
                        source: .none,
                        quarantinedFileCount: quarantinedCount
                    )
                }

                let checkpoint = winner.envelope.checkpoint
                let authorityRejectsCheckpoint = resolvedAuthority.map {
                    $0.state != .active || $0.replicaEpoch != checkpoint.replicaEpoch
                } ?? false
                let isWrongActiveEpoch = activeEpochByAccount[accountID].map {
                    $0 != checkpoint.replicaEpoch
                } ?? false
                guard !authorityRejectsCheckpoint, !isWrongActiveEpoch else {
                    if durableHighWatermark == nil {
                        try removeAccountDirectoryIfPresent(locations)
                        return CloudReplicaCheckpointLoadResult(
                            checkpoint: nil,
                            source: .none,
                            quarantinedFileCount: quarantinedCount
                        )
                    }
                    quarantineAll(
                        [primary, backup].compactMap { $0 },
                        locations: locations,
                        quarantinedCount: &quarantinedCount
                    )
                    if quarantine(locations.watermark, locations: locations) {
                        quarantinedCount += 1
                    }
                    return CloudReplicaCheckpointLoadResult(
                        checkpoint: nil,
                        source: .none,
                        quarantinedFileCount: quarantinedCount
                    )
                }

                let baseAuthority = resolvedAuthority
                    ?? ReplicaEpochAuthorityV1(
                        active: checkpoint.replicaEpoch,
                        for: accountID
                    )
                let canonicalWatermark = WatermarkV1(checkpoint: checkpoint)
                let committedAuthority = try baseAuthority
                    .acceptingResolvedLegacyCheckpoint(canonicalWatermark)
                if resolvedAuthority != committedAuthority {
                    try writeAuthority(
                        committedAuthority,
                        locations: locations
                    )
                    guard try readAuthority(for: accountID, locations: locations)
                        == committedAuthority else {
                        throw CloudReplicaCheckpointStoreError.invalidCheckpoint
                    }
                }

                let watermarkData = try encode(canonicalWatermark)
                try fileSystem.writeAtomically(watermarkData, to: locations.watermark)
                try fileSystem.writeAtomically(winner.data, to: locations.primary)
                try fileSystem.writeAtomically(winner.data, to: locations.backup)
                return CloudReplicaCheckpointLoadResult(
                    checkpoint: checkpoint,
                    source: winner.source,
                    quarantinedFileCount: quarantinedCount
                )
            } catch let error as CloudReplicaCheckpointStoreError {
                throw error
            } catch {
                throw CloudReplicaCheckpointStoreError.ioFailure
            }
        }
    }

    func save(_ checkpoint: CloudReplicaCheckpointV1, at date: Date) throws {
        do {
            try checkpoint.validate(limits: limits)
        } catch {
            throw CloudReplicaCheckpointStoreError.invalidCheckpoint
        }
        let locations = locations(for: checkpoint.accountID)
        try withAccountLock(locations: locations) {
            do {
                guard let activeEpoch = activeEpochByAccount[checkpoint.accountID] else {
                    throw CloudReplicaCheckpointStoreError.replicaEpochNotActive
                }
                guard activeEpoch == checkpoint.replicaEpoch else {
                    throw CloudReplicaCheckpointStoreError.replicaEpochMismatch
                }
                guard let durableAuthority = try readAuthority(
                    for: checkpoint.accountID,
                    locations: locations
                ) else {
                    throw CloudReplicaCheckpointStoreError.replicaEpochNotActive
                }
                if durableAuthority.containsRevoked(checkpoint.replicaEpoch) {
                    throw CloudReplicaCheckpointStoreError.replicaEpochRevoked
                }
                guard durableAuthority.state == .active,
                      durableAuthority.replicaEpoch == checkpoint.replicaEpoch else {
                    throw CloudReplicaCheckpointStoreError.replicaEpochMismatch
                }

                try fileSystem.createDirectory(at: locations.accountDirectory)
                var quarantinedCount = 0
                var watermarkState = validatedWatermark(
                    at: locations.watermark,
                    accountID: checkpoint.accountID,
                    fingerprint: checkpoint.configurationScopeFingerprint,
                    locations: locations,
                    quarantinedCount: &quarantinedCount
                )
                var primary = validatedCopy(
                    at: locations.primary,
                    source: .primary,
                    accountID: checkpoint.accountID,
                    fingerprint: checkpoint.configurationScopeFingerprint,
                    locations: locations,
                    quarantinedCount: &quarantinedCount
                )
                var backup = validatedCopy(
                    at: locations.backup,
                    source: .backup,
                    accountID: checkpoint.accountID,
                    fingerprint: checkpoint.configurationScopeFingerprint,
                    locations: locations,
                    quarantinedCount: &quarantinedCount
                )

                let acceptedHighWatermark = durableAuthority.checkpointHighWatermark
                let pendingHighWatermark = durableAuthority
                    .pendingCheckpointHighWatermark
                let durableHighWatermark = pendingHighWatermark
                    ?? acceptedHighWatermark

                if sameGenerationDiverges(primary, backup) {
                    if durableHighWatermark != nil {
                        quarantineAll(
                            [primary, backup].compactMap { $0 },
                            locations: locations,
                            quarantinedCount: &quarantinedCount
                        )
                        throw CloudReplicaCheckpointStoreError.generationCollision
                    }
                    try removeAccountDirectoryIfPresent(locations)
                    watermarkState = .absent
                    primary = nil
                    backup = nil
                }

                var resolutionWatermark: WatermarkV1?
                switch watermarkState {
                case .absent:
                    resolutionWatermark = durableHighWatermark
                case let .valid(observedWatermark):
                    if let durableHighWatermark,
                       observedWatermark != durableHighWatermark {
                        _ = quarantine(locations.watermark, locations: locations)
                        resolutionWatermark = durableHighWatermark
                    } else {
                        resolutionWatermark = observedWatermark
                    }
                case .invalid:
                    if let durableHighWatermark {
                        resolutionWatermark = durableHighWatermark
                    } else {
                        try removeAccountDirectoryIfPresent(locations)
                        primary = nil
                        backup = nil
                        resolutionWatermark = nil
                    }
                }

                var current = resolve(
                    primary: primary,
                    backup: backup,
                    watermark: resolutionWatermark,
                    preserving: pendingHighWatermark == nil
                        ? nil
                        : acceptedHighWatermark,
                    locations: locations,
                    quarantinedCount: &quarantinedCount
                )
                if durableHighWatermark == nil {
                    let compatibleLegacyWinner = current.map {
                        $0.envelope.checkpoint.replicaEpoch
                            == durableAuthority.replicaEpoch
                    } ?? false
                    if !compatibleLegacyWinner {
                        try removeAccountDirectoryIfPresent(locations)
                        primary = nil
                        backup = nil
                        resolutionWatermark = nil
                        current = nil
                    }
                }
                let effectiveWatermark = resolutionWatermark
                    ?? current.map { WatermarkV1(checkpoint: $0.envelope.checkpoint) }
                let candidateWatermark = WatermarkV1(checkpoint: checkpoint)

                if let effectiveWatermark {
                    guard effectiveWatermark.replicaEpoch == checkpoint.replicaEpoch else {
                        throw CloudReplicaCheckpointStoreError.replicaEpochMismatch
                    }
                    if checkpoint.generation < effectiveWatermark.generation {
                        throw CloudReplicaCheckpointStoreError.staleGeneration
                    }
                    if checkpoint.generation == effectiveWatermark.generation {
                        guard candidateWatermark.checkpointDigest
                            == effectiveWatermark.checkpointDigest else {
                            throw CloudReplicaCheckpointStoreError.generationCollision
                        }
                    } else {
                        let (expected, overflow) = effectiveWatermark.generation
                            .addingReportingOverflow(1)
                        guard !overflow, checkpoint.generation == expected else {
                            throw CloudReplicaCheckpointStoreError.generationGap
                        }
                        guard current != nil else {
                            throw CloudReplicaCheckpointStoreError.invalidCheckpoint
                        }
                    }
                } else if checkpoint.generation != 1 {
                    throw CloudReplicaCheckpointStoreError.generationGap
                }

                let envelopeData: Data
                do {
                    envelopeData = try encode(
                        EnvelopeV1(savedAt: date, checkpoint: checkpoint)
                    )
                } catch {
                    throw CloudReplicaCheckpointStoreError.encodingFailure
                }
                let watermarkData: Data
                do {
                    watermarkData = try encode(candidateWatermark)
                } catch {
                    throw CloudReplicaCheckpointStoreError.encodingFailure
                }

                var publicationBaseAuthority = durableAuthority
                if publicationBaseAuthority.checkpointHighWatermark == nil,
                   publicationBaseAuthority.pendingCheckpointHighWatermark == nil,
                   let effectiveWatermark {
                    publicationBaseAuthority = try publicationBaseAuthority
                        .acceptingResolvedLegacyCheckpoint(effectiveWatermark)
                    try writeAuthority(
                        publicationBaseAuthority,
                        locations: locations
                    )
                    guard try readAuthority(
                        for: checkpoint.accountID,
                        locations: locations
                    ) == publicationBaseAuthority else {
                        throw CloudReplicaCheckpointStoreError.invalidCheckpoint
                    }
                }

                // Persist intent first while retaining the last accepted
                // watermark. Interrupted publication therefore cannot roll
                // back, but it also cannot erase the accepted generation.
                let publishingAuthority = try publicationBaseAuthority
                    .beginningCheckpointPublication(candidateWatermark)
                if publishingAuthority != publicationBaseAuthority {
                    try writeAuthority(publishingAuthority, locations: locations)
                }
                guard try readAuthority(
                    for: checkpoint.accountID,
                    locations: locations
                ) == publishingAuthority else {
                    throw CloudReplicaCheckpointStoreError.invalidCheckpoint
                }

                try fileSystem.createDirectory(at: locations.accountDirectory)
                try fileSystem.writeAtomically(watermarkData, to: locations.watermark)
                try fileSystem.writeAtomically(envelopeData, to: locations.primary)
                try fileSystem.writeAtomically(envelopeData, to: locations.backup)

                // At least one matching replica has now been durably written;
                // only then may pending become the accepted high watermark.
                let committedAuthority = try publishingAuthority
                    .acceptingPublishedCheckpoint(candidateWatermark)
                if committedAuthority != publishingAuthority {
                    try writeAuthority(committedAuthority, locations: locations)
                }

                // The advisory lock serializes cooperative store instances;
                // this final read also fails closed if a non-cooperative writer
                // replaced authority while the checkpoint was being published.
                guard try readAuthority(
                    for: checkpoint.accountID,
                    locations: locations
                ) == committedAuthority else {
                    throw CloudReplicaCheckpointStoreError.replicaEpochMismatch
                }
            } catch let error as CloudReplicaCheckpointStoreError {
                throw error
            } catch {
                throw CloudReplicaCheckpointStoreError.ioFailure
            }
        }
    }

    func remove(for accountID: CloudAccountID, revoking replicaEpoch: UUID) throws {
        let accountLocations = locations(for: accountID)
        try withAccountLock(locations: accountLocations) {
            let existing = try readAuthority(
                for: accountID,
                locations: accountLocations
            )
            let revoked: ReplicaEpochAuthorityV1
            if let existing {
                guard existing.replicaEpoch == replicaEpoch else {
                    if existing.containsRevoked(replicaEpoch) {
                        throw CloudReplicaCheckpointStoreError.replicaEpochRevoked
                    }
                    throw CloudReplicaCheckpointStoreError.replicaEpochMismatch
                }
                revoked = try existing.revokingCurrentEpoch()
            } else {
                revoked = try ReplicaEpochAuthorityV1(
                    active: replicaEpoch,
                    for: accountID
                ).revokingCurrentEpoch()
            }

            if existing != revoked {
                try writeAuthority(revoked, locations: accountLocations)
            }
            guard try readAuthority(for: accountID, locations: accountLocations)
                == revoked else {
                throw CloudReplicaCheckpointStoreError.invalidCheckpoint
            }

            if activeEpochByAccount[accountID] == replicaEpoch {
                activeEpochByAccount.removeValue(forKey: accountID)
            }
            // The durable authority lives outside this removable directory.
            // Publishing revocation first makes a crash or stale writer fail
            // closed even if directory cleanup is interrupted.
            try removeAccountDirectoryIfPresent(accountLocations)
        }
    }

    nonisolated static func accountDirectoryName(for accountID: CloudAccountID) -> String {
        var builder = CloudReplicaDigestBuilder()
        builder.append("pocket-vector-cloud-replica-account-directory-v1")
        builder.append(accountID.rawValue)
        return builder.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func locations(for accountID: CloudAccountID) -> Locations {
        let checkpointRoot = rootDirectoryURL
            .appendingPathComponent("CloudReplicaCheckpoints", isDirectory: true)
        let opaqueAccountName = Self.accountDirectoryName(for: accountID)
        let accountDirectory = checkpointRoot
            .appendingPathComponent("Accounts", isDirectory: true)
            .appendingPathComponent(opaqueAccountName, isDirectory: true)
        let authorityDirectory = checkpointRoot
            .appendingPathComponent("Authorities", isDirectory: true)
            .appendingPathComponent(opaqueAccountName, isDirectory: true)
        return Locations(
            accountDirectory: accountDirectory,
            primary: accountDirectory.appendingPathComponent("checkpoint.json"),
            backup: accountDirectory.appendingPathComponent("checkpoint.backup.json"),
            watermark: accountDirectory.appendingPathComponent("checkpoint.watermark.json"),
            quarantineDirectory: accountDirectory.appendingPathComponent(
                "Quarantine",
                isDirectory: true
            ),
            authorityDirectory: authorityDirectory,
            authority: authorityDirectory.appendingPathComponent(
                "replica-authority.json"
            ),
            authorityLock: authorityDirectory.appendingPathComponent(
                "replica-authority.lock"
            )
        )
    }

    private func withAccountLock<T>(
        locations: Locations,
        perform: () throws -> T
    ) throws -> T {
        var outcome: Result<T, any Error>?
        do {
            try fileSystem.withExclusiveLock(at: locations.authorityLock) {
                outcome = Result { try perform() }
            }
        } catch let error as CloudReplicaCheckpointStoreError {
            throw error
        } catch {
            throw CloudReplicaCheckpointStoreError.ioFailure
        }
        guard let outcome else {
            throw CloudReplicaCheckpointStoreError.ioFailure
        }
        do {
            return try outcome.get()
        } catch let error as CloudReplicaCheckpointStoreError {
            throw error
        } catch {
            throw CloudReplicaCheckpointStoreError.ioFailure
        }
    }

    private func readAuthority(
        for accountID: CloudAccountID,
        locations: Locations
    ) throws -> ReplicaEpochAuthorityV1? {
        guard fileSystem.fileExists(at: locations.authority) else { return nil }
        do {
            guard try fileSystem.fileSize(at: locations.authority) <= 64 * 1_024 else {
                throw CloudReplicaCheckpointStoreError.invalidCheckpoint
            }
            let authority = try JSONDecoder().decode(
                ReplicaEpochAuthorityV1.self,
                from: fileSystem.read(from: locations.authority)
            )
            guard authority.accountID == accountID else {
                throw CloudReplicaCheckpointStoreError.invalidCheckpoint
            }
            return authority
        } catch let error as CloudReplicaCheckpointStoreError {
            throw error
        } catch {
            throw CloudReplicaCheckpointStoreError.invalidCheckpoint
        }
    }

    private func writeAuthority(
        _ authority: ReplicaEpochAuthorityV1,
        locations: Locations
    ) throws {
        let data: Data
        do {
            data = try encode(authority)
        } catch {
            throw CloudReplicaCheckpointStoreError.encodingFailure
        }
        guard data.count <= 64 * 1_024 else {
            throw CloudReplicaCheckpointStoreError.invalidCheckpoint
        }
        try fileSystem.createDirectory(at: locations.authorityDirectory)
        try fileSystem.writeAtomically(data, to: locations.authority)
    }

    private func removeAccountDirectoryIfPresent(_ locations: Locations) throws {
        guard fileSystem.fileExists(at: locations.accountDirectory) else { return }
        try fileSystem.removeItem(at: locations.accountDirectory)
    }

    private func validatedCopy(
        at url: URL,
        source: CloudReplicaCheckpointLoadSource,
        accountID: CloudAccountID,
        fingerprint: CloudReplicaScopeFingerprint,
        locations: Locations,
        quarantinedCount: inout Int
    ) -> StoredCopy? {
        guard fileSystem.fileExists(at: url) else { return nil }
        do {
            let size = try fileSystem.fileSize(at: url)
            guard size >= 0 else {
                throw CloudReplicaCheckpointStoreError.invalidCheckpoint
            }
            if size > maximumEncodedCheckpointFileSize {
                _ = discard(url)
                return nil
            }
            let data = try fileSystem.read(from: url)
            let envelope = try JSONDecoder().decode(EnvelopeV1.self, from: data)
            try envelope.checkpoint.validate(limits: limits)
            guard envelope.checkpoint.accountID == accountID,
                  envelope.checkpoint.configurationScopeFingerprint == fingerprint else {
                throw CloudReplicaCheckpointStoreError.invalidCheckpoint
            }
            return StoredCopy(
                source: source,
                url: url,
                data: data,
                envelope: envelope,
                checkpointDigest: CloudReplicaCheckpointDigest.make(envelope.checkpoint)
            )
        } catch {
            if quarantine(url, locations: locations) {
                quarantinedCount += 1
            }
            return nil
        }
    }

    private func validatedWatermark(
        at url: URL,
        accountID: CloudAccountID,
        fingerprint: CloudReplicaScopeFingerprint,
        locations: Locations,
        quarantinedCount: inout Int
    ) -> WatermarkReadState {
        guard fileSystem.fileExists(at: url) else {
            let priorInvalidWatermark = locations.quarantineDirectory
                .appendingPathComponent("checkpoint-watermark-corrupt.json")
            return fileSystem.fileExists(at: priorInvalidWatermark)
                ? .invalid
                : .absent
        }
        do {
            let size = try fileSystem.fileSize(at: url)
            guard size >= 0 else {
                throw CloudReplicaCheckpointStoreError.invalidCheckpoint
            }
            if size > 64 * 1_024 {
                _ = discard(url)
                return .invalid
            }
            let watermark = try JSONDecoder().decode(
                WatermarkV1.self,
                from: fileSystem.read(from: url)
            )
            guard watermark.accountID == accountID,
                  watermark.configurationScopeFingerprint == fingerprint else {
                throw CloudReplicaCheckpointStoreError.invalidCheckpoint
            }
            return .valid(watermark)
        } catch {
            if quarantine(url, locations: locations) {
                quarantinedCount += 1
            }
            return .invalid
        }
    }

    private func removeWatermarkEvidence(_ locations: Locations) throws {
        let corruptWatermark = locations.quarantineDirectory
            .appendingPathComponent("checkpoint-watermark-corrupt.json")
        for url in [locations.watermark, corruptWatermark]
            where fileSystem.fileExists(at: url) {
            try fileSystem.removeItem(at: url)
        }
    }

    private func resolve(
        primary: StoredCopy?,
        backup: StoredCopy?,
        watermark: WatermarkV1?,
        preserving preservedWatermark: WatermarkV1? = nil,
        locations: Locations,
        quarantinedCount: inout Int
    ) -> StoredCopy? {
        if sameGenerationDiverges(primary, backup) {
            quarantineAll(
                [primary, backup].compactMap { $0 },
                locations: locations,
                quarantinedCount: &quarantinedCount
            )
            return nil
        }

        guard let watermark else {
            guard let primary, let backup else {
                quarantineAll(
                    [primary, backup].compactMap { $0 },
                    locations: locations,
                    quarantinedCount: &quarantinedCount
                )
                return nil
            }
            let primaryCheckpoint = primary.envelope.checkpoint
            let backupCheckpoint = backup.envelope.checkpoint
            guard primaryCheckpoint.replicaEpoch == backupCheckpoint.replicaEpoch else {
                quarantineAll(
                    [primary, backup],
                    locations: locations,
                    quarantinedCount: &quarantinedCount
                )
                return nil
            }
            if primaryCheckpoint.generation != backupCheckpoint.generation {
                let winner: StoredCopy
                let stale: StoredCopy
                if primaryCheckpoint.generation > backupCheckpoint.generation {
                    winner = primary
                    stale = backup
                } else {
                    winner = backup
                    stale = primary
                }
                if quarantine(stale.url, locations: locations) {
                    quarantinedCount += 1
                }
                return winner
            }
            guard primaryCheckpoint == backupCheckpoint else {
                quarantineAll(
                    [primary, backup],
                    locations: locations,
                    quarantinedCount: &quarantinedCount
                )
                return nil
            }
            return primary
        }

        var eligible: [StoredCopy] = []
        for storedCopy in [primary, backup].compactMap({ $0 }) {
            if matches(storedCopy, watermark: watermark) {
                eligible.append(storedCopy)
            } else if let preservedWatermark,
                      matches(storedCopy, watermark: preservedWatermark) {
                // A pending publication may legitimately leave the previous
                // accepted copies in place. Retain them so an exact retry can
                // complete without destroying the last accepted generation.
                continue
            } else if quarantine(storedCopy.url, locations: locations) {
                quarantinedCount += 1
            }
        }
        if eligible.count == 2,
           eligible[0].envelope.checkpoint != eligible[1].envelope.checkpoint {
            quarantineAll(
                eligible,
                locations: locations,
                quarantinedCount: &quarantinedCount
            )
            return nil
        }
        return eligible.first(where: { $0.source == .primary }) ?? eligible.first
    }

    private func matches(
        _ copy: StoredCopy,
        watermark: WatermarkV1
    ) -> Bool {
        let checkpoint = copy.envelope.checkpoint
        return checkpoint.replicaEpoch == watermark.replicaEpoch
            && checkpoint.generation == watermark.generation
            && copy.checkpointDigest == watermark.checkpointDigest
    }

    private func sameGenerationDiverges(
        _ primary: StoredCopy?,
        _ backup: StoredCopy?
    ) -> Bool {
        guard let primary, let backup else { return false }
        let left = primary.envelope.checkpoint
        let right = backup.envelope.checkpoint
        return left.replicaEpoch == right.replicaEpoch
            && left.generation == right.generation
            && left != right
    }

    private func quarantineAll(
        _ copies: [StoredCopy],
        locations: Locations,
        quarantinedCount: inout Int
    ) {
        for copy in copies where fileSystem.fileExists(at: copy.url) {
            if quarantine(copy.url, locations: locations) {
                quarantinedCount += 1
            }
        }
    }

    /// Quarantine is deliberately best-effort. Fixed source-specific slots cap
    /// retained payloads at primary, backup, and watermark regardless of how
    /// often corruption is encountered.
    private func quarantine(_ url: URL, locations: Locations) -> Bool {
        do {
            try fileSystem.createDirectory(at: locations.quarantineDirectory)
            let slot: String
            if url == locations.primary {
                slot = "checkpoint-primary-corrupt.json"
            } else if url == locations.backup {
                slot = "checkpoint-backup-corrupt.json"
            } else {
                slot = "checkpoint-watermark-corrupt.json"
            }
            let destination = locations.quarantineDirectory.appendingPathComponent(slot)
            if fileSystem.fileExists(at: destination) {
                try fileSystem.removeItem(at: destination)
            }
            try fileSystem.moveItem(at: url, to: destination)
            return true
        } catch {
            return false
        }
    }

    private func discard(_ url: URL) -> Bool {
        do {
            guard fileSystem.fileExists(at: url) else { return false }
            try fileSystem.removeItem(at: url)
            return true
        } catch {
            return false
        }
    }

    private var maximumEncodedCheckpointFileSize: Int {
        let (maximum, overflow) = limits.maxTotalBytes.multipliedReportingOverflow(by: 8)
        return overflow ? Int.max : maximum
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
}

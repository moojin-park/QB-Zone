import CryptoKit
import Foundation

enum CloudProfileSchemaConfigurationError: Error, Equatable, Sendable {
    case invalidIdentifier(String)
    case duplicateRecordType(String)
}

/// The versioned CloudKit surface used by the profile replica. Economy records
/// intentionally remain in `DurableEconomyCloudConfiguration`; the profile
/// validator combines both configurations and rejects any record-type overlap.
struct CloudProfileSchemaConfiguration: Equatable, Sendable {
    static let schemaIdentifier = "pocket-vector-cloud-profile-schema-v1"
    static let rootLogicalRecordID = CloudRecordID("profile-root-v1")
    static let settingsLogicalRecordID = CloudRecordID("profile-settings-v1")
    static let selectionLogicalRecordID = CloudRecordID("profile-selection-v1")
    static let runRecordIDDomain = "pocket-vector-cloud-profile-run-record-id-v1"
    static let runAccumulatorDomain =
        "pocket-vector-cloud-profile-run-accumulator-entry-v1"

    let rootRecordType: String
    let settingsRecordType: String
    let selectionRecordType: String
    let runRecordType: String
    let payloadFieldName: String

    init(
        rootRecordType: String,
        settingsRecordType: String,
        selectionRecordType: String,
        runRecordType: String,
        payloadFieldName: String
    ) throws {
        let identifiers = [
            rootRecordType,
            settingsRecordType,
            selectionRecordType,
            runRecordType,
            payloadFieldName,
        ]
        for identifier in identifiers {
            guard Self.isCloudKitIdentifier(identifier) else {
                throw CloudProfileSchemaConfigurationError.invalidIdentifier(
                    identifier
                )
            }
        }

        let recordTypes = [
            rootRecordType,
            settingsRecordType,
            selectionRecordType,
            runRecordType,
        ]
        guard Set(recordTypes).count == recordTypes.count else {
            let duplicate = recordTypes.first { candidate in
                recordTypes.filter { $0 == candidate }.count > 1
            }!
            throw CloudProfileSchemaConfigurationError.duplicateRecordType(
                duplicate
            )
        }

        self.rootRecordType = rootRecordType
        self.settingsRecordType = settingsRecordType
        self.selectionRecordType = selectionRecordType
        self.runRecordType = runRecordType
        self.payloadFieldName = payloadFieldName
    }

    var rootRecordID: CloudRecordID { Self.rootLogicalRecordID }
    var settingsRecordID: CloudRecordID { Self.settingsLogicalRecordID }
    var selectionRecordID: CloudRecordID { Self.selectionLogicalRecordID }

    func runRecordID(for runID: RunID) -> CloudRecordID {
        let digest = CloudProfileDigest.sha256(
            components: [Self.runRecordIDDomain, runID.description]
        )
        return CloudRecordID(
            "profile-run-v1-\(CloudProfileDigest.hex(digest))"
        )
    }

    /// Ordered, length-delimited material for the transport scope fingerprint.
    /// It includes every profile schema name, version, singleton ID, and digest
    /// domain so changing interpretation necessarily invalidates a checkpoint.
    var fingerprintMaterial: [String] {
        [
            Self.schemaIdentifier,
            "rootRecordType", rootRecordType,
            "settingsRecordType", settingsRecordType,
            "selectionRecordType", selectionRecordType,
            "runRecordType", runRecordType,
            "payloadFieldName", payloadFieldName,
            "rootLogicalRecordID", rootRecordID.rawValue,
            "settingsLogicalRecordID", settingsRecordID.rawValue,
            "selectionLogicalRecordID", selectionRecordID.rawValue,
            "runRecordIDDomain", Self.runRecordIDDomain,
            "runAccumulatorDomain", Self.runAccumulatorDomain,
            "rootSchemaVersion", String(CloudProfileRootV1.schemaVersion),
            "settingsSchemaVersion", String(CloudProfileSettingsV1.schemaVersion),
            "selectionSchemaVersion", String(CloudProfileSelectionV1.schemaVersion),
            "completedRunSchemaVersion",
            String(CloudProfileCompletedRunV1.schemaVersion),
            "runAccumulatorDigestBytes",
            String(CloudProfileRunAccumulatorV1.digestByteCount),
        ]
    }

    private static func isCloudKitIdentifier(_ value: String) -> Bool {
        guard let first = value.utf8.first,
              (first >= 65 && first <= 90) || (first >= 97 && first <= 122)
        else {
            return false
        }
        return value.utf8.dropFirst().allSatisfy { byte in
            (byte >= 65 && byte <= 90)
                || (byte >= 97 && byte <= 122)
                || (byte >= 48 && byte <= 57)
                || byte == 95
        }
    }
}

struct CloudProfileBindingV1: Codable, Equatable, Sendable {
    let cloudAccountID: CloudAccountID
    let accountBinding: DurableAccountBinding
    let profileAccountIdentity: PlayerAccountIdentity
}

struct CloudProfileRunAccumulatorV1: Codable, Equatable, Sendable {
    static let digestByteCount = 32

    let runCount: UInt64
    let digest: Data

    static let empty = try! CloudProfileRunAccumulatorV1(
        runCount: 0,
        digest: Data(repeating: 0, count: digestByteCount)
    )

    init(runCount: UInt64, digest: Data) throws {
        guard digest.count == Self.digestByteCount else {
            throw CloudProfileRunAccumulatorError.invalidDigestLength
        }
        self.runCount = runCount
        self.digest = digest
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let runCount = try container.decode(UInt64.self, forKey: .runCount)
        let digest = try container.decode(Data.self, forKey: .digest)
        try self.init(runCount: runCount, digest: digest)
    }

    /// Commits the exact canonical payload bytes stored in each immutable run
    /// record, as well as its deterministic logical ID. A valid-but-altered
    /// run with the same RunID therefore cannot satisfy the root commitment.
    static func make(
        for entries: some Sequence<CloudProfileRunAccumulatorEntryV1>
    ) throws -> Self {
        var seen = Set<CloudRecordID>()
        var digest = Data(repeating: 0, count: digestByteCount)
        var count: UInt64 = 0

        for entry in entries {
            guard seen.insert(entry.logicalRecordID).inserted else {
                throw CloudProfileRunAccumulatorError.duplicateLogicalRecordID(
                    entry.logicalRecordID
                )
            }
            let increment = count.addingReportingOverflow(1)
            guard !increment.overflow else {
                throw CloudProfileRunAccumulatorError.countOverflow
            }
            count = increment.partialValue
            let entryDigest = CloudProfileDigest.sha256(
                dataComponents: [
                    Data(
                        CloudProfileSchemaConfiguration.runAccumulatorDomain.utf8
                    ),
                    Data(entry.logicalRecordID.rawValue.utf8),
                    entry.canonicalPayload,
                ]
            )
            digest = Data(zip(digest, entryDigest).map { $0 ^ $1 })
        }
        return try Self(runCount: count, digest: digest)
    }
}

struct CloudProfileRunAccumulatorEntryV1: Equatable, Sendable {
    let logicalRecordID: CloudRecordID
    let canonicalPayload: Data
}

enum CloudProfileRunAccumulatorError: Error, Equatable, Sendable {
    case invalidDigestLength
    case duplicateLogicalRecordID(CloudRecordID)
    case countOverflow
}

struct CloudProfileRootV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let binding: CloudProfileBindingV1
    let economyHeadRecordID: CloudRecordID
    /// Monotonic profile-root CAS generation. An initialized root begins at 1
    /// and every committed root/settings/selection/run-set transaction advances
    /// it exactly once. One transaction may update multiple stamped records, so
    /// validation requires this to be nonzero and no lower than the run count
    /// or either stamped logical counter; equality is intentionally not required.
    let rootRevision: UInt64
    let runAccumulator: CloudProfileRunAccumulatorV1

    init(
        schemaVersion: Int = Self.schemaVersion,
        binding: CloudProfileBindingV1,
        economyHeadRecordID: CloudRecordID,
        rootRevision: UInt64,
        runAccumulator: CloudProfileRunAccumulatorV1
    ) {
        self.schemaVersion = schemaVersion
        self.binding = binding
        self.economyHeadRecordID = economyHeadRecordID
        self.rootRevision = rootRevision
        self.runAccumulator = runAccumulator
    }
}

enum CloudProfileMergeStampError: Error, Equatable, Sendable {
    case invalidDeviceID(String)
    case invalidModifiedAt
}

/// Logical ordering never consults wall-clock time. `modifiedAt` exists only
/// for diagnostics and player-facing support data.
struct CloudProfileMergeStampV1: Codable, Equatable, Comparable, Sendable {
    let logicalCounter: UInt64
    let deviceID: String
    let modifiedAt: Date

    init(logicalCounter: UInt64, deviceID: String, modifiedAt: Date) throws {
        guard ProfileStampDeviceIDRuleV1.isValid(deviceID) else {
            throw CloudProfileMergeStampError.invalidDeviceID(deviceID)
        }
        guard modifiedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw CloudProfileMergeStampError.invalidModifiedAt
        }
        self.logicalCounter = logicalCounter
        self.deviceID = deviceID
        self.modifiedAt = modifiedAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            logicalCounter: container.decode(
                UInt64.self,
                forKey: .logicalCounter
            ),
            deviceID: container.decode(String.self, forKey: .deviceID),
            modifiedAt: container.decode(Date.self, forKey: .modifiedAt)
        )
    }

    static func == (
        lhs: CloudProfileMergeStampV1,
        rhs: CloudProfileMergeStampV1
    ) -> Bool {
        lhs.logicalCounter == rhs.logicalCounter && lhs.deviceID == rhs.deviceID
    }

    static func < (
        lhs: CloudProfileMergeStampV1,
        rhs: CloudProfileMergeStampV1
    ) -> Bool {
        if lhs.logicalCounter != rhs.logicalCounter {
            return lhs.logicalCounter < rhs.logicalCounter
        }
        return lhs.deviceID.utf8.lexicographicallyPrecedes(rhs.deviceID.utf8)
    }

}

enum CloudProfileStampedMergeError: Error, Equatable, Sendable {
    case incompatibleSchema
    case bindingMismatch
    case equalStampDivergence
}

struct CloudProfileSettingsV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let binding: CloudProfileBindingV1
    let stamp: CloudProfileMergeStampV1
    let settings: PlayerSettings

    init(
        schemaVersion: Int = Self.schemaVersion,
        binding: CloudProfileBindingV1,
        stamp: CloudProfileMergeStampV1,
        settings: PlayerSettings
    ) {
        self.schemaVersion = schemaVersion
        self.binding = binding
        self.stamp = stamp
        self.settings = settings
    }

    func merged(with other: Self) throws -> Self {
        guard schemaVersion == Self.schemaVersion,
              other.schemaVersion == Self.schemaVersion
        else {
            throw CloudProfileStampedMergeError.incompatibleSchema
        }
        guard binding == other.binding else {
            throw CloudProfileStampedMergeError.bindingMismatch
        }
        if stamp == other.stamp {
            guard settings == other.settings else {
                throw CloudProfileStampedMergeError.equalStampDivergence
            }
            return CloudProfileSettingsV1(
                binding: binding,
                stamp: try stamp.canonicalized(with: other.stamp),
                settings: settings
            )
        }
        return stamp < other.stamp ? other : self
    }
}

struct CloudProfileSelectionV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let binding: CloudProfileBindingV1
    let stamp: CloudProfileMergeStampV1
    let selection: PlayerSelection

    init(
        schemaVersion: Int = Self.schemaVersion,
        binding: CloudProfileBindingV1,
        stamp: CloudProfileMergeStampV1,
        selection: PlayerSelection
    ) {
        self.schemaVersion = schemaVersion
        self.binding = binding
        self.stamp = stamp
        self.selection = selection
    }

    func merged(with other: Self) throws -> Self {
        guard schemaVersion == Self.schemaVersion,
              other.schemaVersion == Self.schemaVersion
        else {
            throw CloudProfileStampedMergeError.incompatibleSchema
        }
        guard binding == other.binding else {
            throw CloudProfileStampedMergeError.bindingMismatch
        }
        if stamp == other.stamp {
            guard selection == other.selection else {
                throw CloudProfileStampedMergeError.equalStampDivergence
            }
            return CloudProfileSelectionV1(
                binding: binding,
                stamp: try stamp.canonicalized(with: other.stamp),
                selection: selection
            )
        }
        return stamp < other.stamp ? other : self
    }
}

struct CloudProfileCompletedRunV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let binding: CloudProfileBindingV1
    let record: CompletedRunRecord
    let rewardedRunObservation: RewardedRunObservation?

    init(
        schemaVersion: Int = Self.schemaVersion,
        binding: CloudProfileBindingV1,
        record: CompletedRunRecord,
        rewardedRunObservation: RewardedRunObservation?
    ) {
        self.schemaVersion = schemaVersion
        self.binding = binding
        self.record = record
        self.rewardedRunObservation = rewardedRunObservation
    }

    var runID: RunID { record.run.runID }
}

enum CloudProfileDigest {
    static func sha256(components: [String]) -> Data {
        sha256(dataComponents: components.map { Data($0.utf8) })
    }

    static func sha256(dataComponents: [Data]) -> Data {
        var hasher = SHA256()
        for data in dataComponents {
            var length = UInt64(data.count).bigEndian
            withUnsafeBytes(of: &length) { hasher.update(data: Data($0)) }
            hasher.update(data: data)
        }
        return Data(hasher.finalize())
    }

    static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}

extension CloudProfileMergeStampV1 {
    fileprivate func canonicalized(
        with other: CloudProfileMergeStampV1
    ) throws -> CloudProfileMergeStampV1 {
        precondition(self == other)
        return try CloudProfileMergeStampV1(
            logicalCounter: logicalCounter,
            deviceID: deviceID,
            modifiedAt: max(modifiedAt, other.modifiedAt)
        )
    }
}

enum CloudProfileCanonicalPayload {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = try encoder.encode(value)
        let object = try JSONSerialization.jsonObject(with: encoded)
        let normalized: Any
        if value is CloudProfileCompletedRunV1 {
            normalized = canonicalCompletedRunObject(object)
        } else if value is CloudProfileSelectionV1 {
            normalized = canonicalSelectionObject(object)
        } else {
            normalized = object
        }
        return try JSONSerialization.data(
            withJSONObject: normalized,
            options: [.sortedKeys]
        )
    }

    private static func canonicalCompletedRunObject(_ object: Any) -> Any {
        guard var payload = object as? [String: Any],
              var record = payload["record"] as? [String: Any],
              var run = record["run"] as? [String: Any],
              let laneIDs = run["completedLaneIDs"] as? [String]
        else {
            return object
        }
        run["completedLaneIDs"] = laneIDs.sorted()
        record["run"] = run
        payload["record"] = record
        return payload
    }

    private static func canonicalSelectionObject(_ object: Any) -> Any {
        guard var payload = object as? [String: Any],
              var selection = payload["selection"] as? [String: Any],
              let flatEntries = selection["selectedJerseyByTeam"] as? [Any],
              flatEntries.count.isMultiple(of: 2)
        else {
            return object
        }
        var pairs: [(key: String, value: Any)] = []
        for index in stride(from: 0, to: flatEntries.count, by: 2) {
            guard let key = flatEntries[index] as? String else {
                return object
            }
            pairs.append((key, flatEntries[index + 1]))
        }
        pairs.sort { $0.key < $1.key }
        selection["selectedJerseyByTeam"] = pairs.flatMap { [$0.key, $0.value] }
        payload["selection"] = selection
        return payload
    }
}

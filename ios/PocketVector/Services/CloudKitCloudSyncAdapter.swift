import Foundation
import CryptoKit
@preconcurrency import CloudKit

enum CloudKitCloudSchema {
    static let schemaIdentifier = "pocket-vector-cloudkit-transport-schema-v2"
    static let recordEnvelopeSchemaVersion = 3
    static let operationMarkerSchemaVersion = 2
    static var recordEnvelopeFields: String {
        CloudKitRecordPayloadV3.persistedFieldManifest
    }
    static var operationMarkerFields: String {
        CloudKitOperationMarkerV2.persistedFieldManifest
    }
    static var payloadEncoding: String {
        CloudKitPayloadCodec.encodingIdentifier
    }
    static let databaseScope = "private"
    static let zoneOwner = "current-user-default"
    static let opaqueIdentifierDomain = "pocket-vector-cloudkit-opaque-id-v1"
    static let recordAddressKind = "record-v1"
    static let accountAddressKind = "account-v1"
    static let operationAddressKind = "operation-v1"
    static let operationFingerprintDomain = "pocket-vector-cloudkit-request-v2"
    static let opaqueAddressPolicyIdentifier =
        "domain-namespace-kind-value-stable-digest-lowercase-hex-v1"
    static let operationFingerprintPolicyIdentifier =
        "account-operation-count-framed-writes-by-id-count-framed-fields-by-key-precondition-and-bytes-v2"
    static let orderingPolicyIdentifier = "utf8-byte-lexicographic-ascending-v1"
    static let preconditionCaseManifest =
        "change-tag(rawValue),must-not-exist,none"
}

enum CloudKitCloudSyncConfigurationError: Error, Equatable, Sendable {
    case emptyContainerIdentifier
    case emptyZoneName
    case invalidPayloadFieldName
    case invalidOperationRecordType
    case emptyAccountIdentifierNamespace
    case emptyRecordNameNamespace
}

/// The CloudKit backend selected by the app's signed
/// `com.apple.developer.icloud-container-environment` entitlement. The build
/// seals the matching value into replica scope so a development cursor can
/// never be interpreted as production history, or vice versa.
enum CloudKitContainerEnvironment: String, Equatable, Sendable {
    case development = "Development"
    case production = "Production"
}

/// The CloudKit environment is a sealed property of the current build. The
/// same configuration-specific build setting expands into both this compiler
/// condition and the signed iCloud container environment entitlement.
enum CloudKitBuildEnvironment {
    #if POCKET_VECTOR_CLOUDKIT_ENVIRONMENT_Development && POCKET_VECTOR_CLOUDKIT_ENVIRONMENT_Production
    #error("Pocket Vector CloudKit build environment is ambiguous")
    static let current = CloudKitContainerEnvironment.development
    #elseif POCKET_VECTOR_CLOUDKIT_ENVIRONMENT_Development
    static let current = CloudKitContainerEnvironment.development
    #elseif POCKET_VECTOR_CLOUDKIT_ENVIRONMENT_Production
    static let current = CloudKitContainerEnvironment.production
    #else
    #error("Pocket Vector CloudKit build environment is missing or invalid")
    static let current = CloudKitContainerEnvironment.development
    #endif
}

/// Every identifier that affects the production CloudKit container or schema
/// is supplied by release composition. This type intentionally has no shipping
/// defaults, test container names, or placeholder identifiers.
struct CloudKitCloudSyncConfiguration: Equatable, Sendable {
    let containerIdentifier: String
    let containerEnvironment: CloudKitContainerEnvironment
    let zoneName: String
    let payloadFieldName: String
    let operationRecordType: String
    let accountIdentifierNamespace: String
    let recordNameNamespace: String

    private init(
        containerIdentifier: String,
        containerEnvironment: CloudKitContainerEnvironment,
        zoneName: String,
        payloadFieldName: String,
        operationRecordType: String,
        accountIdentifierNamespace: String,
        recordNameNamespace: String
    ) throws {
        guard !containerIdentifier.isEmpty else {
            throw CloudKitCloudSyncConfigurationError.emptyContainerIdentifier
        }
        guard !zoneName.isEmpty else {
            throw CloudKitCloudSyncConfigurationError.emptyZoneName
        }
        guard Self.isValidSchemaIdentifier(payloadFieldName) else {
            throw CloudKitCloudSyncConfigurationError.invalidPayloadFieldName
        }
        guard Self.isValidSchemaIdentifier(operationRecordType) else {
            throw CloudKitCloudSyncConfigurationError.invalidOperationRecordType
        }
        guard !accountIdentifierNamespace.isEmpty else {
            throw CloudKitCloudSyncConfigurationError.emptyAccountIdentifierNamespace
        }
        guard !recordNameNamespace.isEmpty else {
            throw CloudKitCloudSyncConfigurationError.emptyRecordNameNamespace
        }

        self.containerIdentifier = containerIdentifier
        self.containerEnvironment = containerEnvironment
        self.zoneName = zoneName
        self.payloadFieldName = payloadFieldName
        self.operationRecordType = operationRecordType
        self.accountIdentifierNamespace = accountIdentifierNamespace
        self.recordNameNamespace = recordNameNamespace
    }

    /// Shipping composition cannot assert a backend environment. It is sealed
    /// to the build value that also supplies the signed entitlement.
    static func buildSealed(
        containerIdentifier: String,
        zoneName: String,
        payloadFieldName: String,
        operationRecordType: String,
        accountIdentifierNamespace: String,
        recordNameNamespace: String
    ) throws -> Self {
        try Self(
            containerIdentifier: containerIdentifier,
            containerEnvironment: CloudKitBuildEnvironment.current,
            zoneName: zoneName,
            payloadFieldName: payloadFieldName,
            operationRecordType: operationRecordType,
            accountIdentifierNamespace: accountIdentifierNamespace,
            recordNameNamespace: recordNameNamespace
        )
    }

    #if DEBUG
    /// Tests may exercise scope separation without opening a live container.
    static func _testOnly(
        containerIdentifier: String,
        containerEnvironment: CloudKitContainerEnvironment,
        zoneName: String,
        payloadFieldName: String,
        operationRecordType: String,
        accountIdentifierNamespace: String,
        recordNameNamespace: String
    ) throws -> Self {
        try Self(
            containerIdentifier: containerIdentifier,
            containerEnvironment: containerEnvironment,
            zoneName: zoneName,
            payloadFieldName: payloadFieldName,
            operationRecordType: operationRecordType,
            accountIdentifierNamespace: accountIdentifierNamespace,
            recordNameNamespace: recordNameNamespace
        )
    }
    #endif

    var fingerprintMaterial: [String] {
        [
            CloudKitCloudSchema.schemaIdentifier,
            "containerIdentifier", containerIdentifier,
            "containerEnvironment", containerEnvironment.rawValue,
            "zoneName", zoneName,
            "payloadFieldName", payloadFieldName,
            "operationRecordType", operationRecordType,
            "accountIdentifierNamespace", accountIdentifierNamespace,
            "recordNameNamespace", recordNameNamespace,
            "recordEnvelopeSchemaVersion",
            String(CloudKitCloudSchema.recordEnvelopeSchemaVersion),
            "recordEnvelopeFields", CloudKitCloudSchema.recordEnvelopeFields,
            "operationMarkerSchemaVersion",
            String(CloudKitCloudSchema.operationMarkerSchemaVersion),
            "operationMarkerFields", CloudKitCloudSchema.operationMarkerFields,
            "payloadEncoding", CloudKitCloudSchema.payloadEncoding,
            "databaseScope", CloudKitCloudSchema.databaseScope,
            "zoneOwner", CloudKitCloudSchema.zoneOwner,
            "opaqueIdentifierDomain", CloudKitCloudSchema.opaqueIdentifierDomain,
            "recordAddressKind", CloudKitCloudSchema.recordAddressKind,
            "accountAddressKind", CloudKitCloudSchema.accountAddressKind,
            "operationAddressKind", CloudKitCloudSchema.operationAddressKind,
            "operationFingerprintDomain",
            CloudKitCloudSchema.operationFingerprintDomain,
            "opaqueAddressPolicy",
            CloudKitCloudSchema.opaqueAddressPolicyIdentifier,
            "operationFingerprintPolicy",
            CloudKitCloudSchema.operationFingerprintPolicyIdentifier,
            "orderingPolicy", CloudKitCloudSchema.orderingPolicyIdentifier,
            "preconditionCases", CloudKitCloudSchema.preconditionCaseManifest,
            "digestAlgorithm", StableDigestBuilder.algorithmIdentifier,
            "digestComponentEncoding",
            StableDigestBuilder.componentEncodingIdentifier,
            "operationFingerprintCountEncoding",
            StableDigestBuilder.countEncodingIdentifier,
            "digestHexEncoding", StableDigestBuilder.hexEncodingIdentifier,
        ]
    }

    /// Derives the same opaque account identifier used by the custom-zone
    /// transport. Separate private-database authorities (for example the
    /// immutable Game Center owner claim in the default zone) use this to
    /// prove they are still operating on the exact routed iCloud account.
    func accountID(forProviderRecordName recordName: String) -> CloudAccountID {
        CloudAccountID(
            CloudKitOpaqueIdentifier.make(
                namespace: accountIdentifierNamespace,
                kind: CloudKitCloudSchema.accountAddressKind,
                value: recordName
            )
        )
    }

    private static func isValidSchemaIdentifier(_ value: String) -> Bool {
        guard let first = value.unicodeScalars.first,
              CharacterSet.letters.union(CharacterSet(charactersIn: "_")).contains(first)
        else {
            return false
        }
        return value.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_")).contains($0)
        }
    }
}

enum CloudKitCloudSyncRecovery: Equatable, Sendable {
    case retry(afterSeconds: TimeInterval?)
    case waitForAccountChange
    case discardCursorAndRestartBootstrap
    case requireAccountCloudReset
    case refreshCommittedOperation(recordIDs: [CloudRecordID])
    case doNotRetry
}

/// These errors contain only app-owned identifiers and coarse provider state.
/// Underlying CKError descriptions and user/provider record identifiers are
/// deliberately discarded.
enum CloudKitCloudSyncError: Error, Equatable, Sendable, LocalizedError {
    case invalidRequest
    case accountRestricted
    case accountTemporarilyUnavailable
    case networkUnavailable(retryAfterSeconds: TimeInterval?)
    case serviceUnavailable(retryAfterSeconds: TimeInterval?)
    case rateLimited(retryAfterSeconds: TimeInterval?)
    case quotaExceeded
    case permissionDenied
    case requestTooLarge
    case malformedRecord(CloudRecordID)
    case malformedDiscoveredRecord
    case malformedOperationMarker
    case malformedChangeCursor
    case changeCursorExpired
    case inconsistentChangePage
    case zoneResetRequired
    case providerConfigurationRejected
    case providerRequestRejected
    case operationCancelled
    case committedOperationRequiresRefresh(
        operationID: OperationID,
        recordIDs: [CloudRecordID]
    )

    var recovery: CloudKitCloudSyncRecovery {
        switch self {
        case let .networkUnavailable(delay),
             let .serviceUnavailable(delay),
             let .rateLimited(delay):
            .retry(afterSeconds: delay)
        case .accountTemporarilyUnavailable:
            .waitForAccountChange
        case .malformedChangeCursor, .changeCursorExpired:
            .discardCursorAndRestartBootstrap
        case .zoneResetRequired:
            .requireAccountCloudReset
        case let .committedOperationRequiresRefresh(_, recordIDs):
            .refreshCommittedOperation(recordIDs: recordIDs)
        case .invalidRequest,
             .accountRestricted,
             .quotaExceeded,
             .permissionDenied,
             .requestTooLarge,
             .malformedRecord,
             .malformedDiscoveredRecord,
             .malformedOperationMarker,
             .inconsistentChangePage,
             .providerConfigurationRejected,
             .providerRequestRejected,
             .operationCancelled:
            .doNotRetry
        }
    }

    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            "The cloud request is invalid."
        case .accountRestricted:
            "iCloud access is restricted on this device."
        case .accountTemporarilyUnavailable:
            "iCloud is temporarily unavailable."
        case .networkUnavailable:
            "A network connection is required to sync."
        case .serviceUnavailable, .rateLimited:
            "iCloud sync is temporarily busy."
        case .quotaExceeded:
            "The iCloud account does not have enough available storage."
        case .permissionDenied:
            "The iCloud account cannot access this private game data."
        case .requestTooLarge:
            "The cloud sync request is too large."
        case .malformedRecord, .malformedDiscoveredRecord, .malformedOperationMarker,
             .inconsistentChangePage:
            "Stored private game data could not be read safely."
        case .malformedChangeCursor, .changeCursorExpired:
            "The saved cloud position must be rebuilt safely."
        case .zoneResetRequired:
            "The private game-data zone was reset and requires recovery."
        case .providerConfigurationRejected:
            "Cloud sync is not configured for this build."
        case .providerRequestRejected:
            "iCloud rejected the sync request."
        case .operationCancelled:
            "The cloud sync request was cancelled."
        case .committedOperationRequiresRefresh:
            "The cloud operation completed and its records must be refreshed."
        }
    }
}

enum CloudKitClientAccountStatus: Equatable, Sendable {
    case couldNotDetermine
    case available
    case restricted
    case signedOut
    case temporarilyUnavailable
}

enum CloudKitClientWritePrecondition: Equatable, Sendable {
    case none
    case mustNotExist
    case changeTag(String)
}

struct CloudKitClientRecord: Equatable, Sendable {
    let recordName: String
    let recordType: String
    let payload: Data
    let changeTag: String
}

struct CloudKitClientWrite: Equatable, Sendable {
    let recordName: String
    let recordType: String
    let payload: Data
    let precondition: CloudKitClientWritePrecondition
}

struct CloudKitClientRecordDeletion: Equatable, Sendable {
    let recordName: String
    let recordType: String
}

struct CloudKitClientChangePage: Equatable, Sendable {
    let modifications: [CloudKitClientRecord]
    let deletions: [CloudKitClientRecordDeletion]
    let nextCursor: Data
    let moreComing: Bool
}

enum CloudKitClientFailure: Error, Equatable, Sendable {
    case conflict(recordNames: [String])
    case missingRecord(recordNames: [String])
    case malformedRecord(recordName: String)
    case networkUnavailable(retryAfterSeconds: TimeInterval?)
    case serviceUnavailable(retryAfterSeconds: TimeInterval?)
    case rateLimited(retryAfterSeconds: TimeInterval?)
    case notAuthenticated
    case accountTemporarilyUnavailable
    case permissionDenied
    case quotaExceeded
    case requestTooLarge
    case zoneMissing
    case providerAccountMismatch
    case changeTokenExpired
    case malformedChangeCursor
    case invalidConfiguration
    case responseLost
    case operationCancelled
    case batchRequestFailed
    case providerRejected
}

protocol CloudKitPrivateDatabaseClient: Sendable {
    func accountStatus() async throws -> CloudKitClientAccountStatus
    func currentUserRecordName() async throws -> String
    func fetchRecords(named recordNames: [String]) async throws -> [CloudKitClientRecord]
    func saveAtomically(
        _ writes: [CloudKitClientWrite],
        expectedProviderRecordName: String
    ) async throws -> [CloudKitClientRecord]
    func fetchRecordZoneChanges(
        afterArchivedCursor cursor: Data?,
        allowZoneCreation: Bool
    ) async throws -> CloudKitClientChangePage
}

enum CloudKitSDKFailureClassifier {
    static func classify(
        _ error: any Error,
        fallbackRecordName: String? = nil
    ) -> CloudKitClientFailure {
        guard let cloudError = error as? CKError else {
            return .providerRejected
        }

        if cloudError.code == .partialFailure,
           let partial = cloudError.partialErrorsByItemID
        {
            let classified = partial.map { key, value in
                let recordName = (key as? CKRecord.ID)?.recordName ?? fallbackRecordName
                return classify(value, fallbackRecordName: recordName)
            }
            return aggregate(classified)
        }

        let retryAfter = sanitizedRetryAfter(cloudError)
        switch cloudError.code {
        case .networkUnavailable, .networkFailure:
            return .networkUnavailable(retryAfterSeconds: retryAfter)
        case .serviceUnavailable, .zoneBusy:
            return .serviceUnavailable(retryAfterSeconds: retryAfter)
        case .requestRateLimited:
            return .rateLimited(retryAfterSeconds: retryAfter)
        case .notAuthenticated:
            return .notAuthenticated
        case .accountTemporarilyUnavailable:
            return .accountTemporarilyUnavailable
        case .permissionFailure, .managedAccountRestricted:
            return .permissionDenied
        case .quotaExceeded:
            return .quotaExceeded
        case .limitExceeded:
            return .requestTooLarge
        case .unknownItem:
            return .missingRecord(recordNames: fallbackRecordName.map { [$0] } ?? [])
        case .zoneNotFound, .userDeletedZone:
            return .zoneMissing
        case .serverRecordChanged:
            return .conflict(recordNames: fallbackRecordName.map { [$0] } ?? [])
        case .changeTokenExpired:
            return .changeTokenExpired
        case .serverResponseLost:
            return .responseLost
        case .operationCancelled:
            return .operationCancelled
        case .batchRequestFailed:
            return .batchRequestFailed
        case .badContainer, .badDatabase, .missingEntitlement:
            return .invalidConfiguration
        case .internalError,
             .invalidArguments,
             .serverRejectedRequest,
             .assetFileNotFound,
             .assetFileModified,
             .incompatibleVersion,
             .constraintViolation,
             .tooManyParticipants,
             .alreadyShared,
             .referenceViolation,
             .participantMayNeedVerification,
             .assetNotAvailable,
             .participantAlreadyInvited,
             .resultsTruncated,
             .partialFailure:
            return .providerRejected
        @unknown default:
            return .providerRejected
        }
    }

    static func aggregate(_ failures: [CloudKitClientFailure]) -> CloudKitClientFailure {
        let meaningful = failures.filter { $0 != .batchRequestFailed }
        let candidates = meaningful.isEmpty ? failures : meaningful

        let conflicts = candidates.flatMap { failure -> [String] in
            if case let .conflict(recordNames) = failure { return recordNames }
            return []
        }
        if !conflicts.isEmpty {
            return .conflict(recordNames: Array(Set(conflicts)).sorted())
        }

        if candidates.contains(.notAuthenticated) { return .notAuthenticated }
        if candidates.contains(.accountTemporarilyUnavailable) {
            return .accountTemporarilyUnavailable
        }
        if candidates.contains(.permissionDenied) { return .permissionDenied }
        if candidates.contains(.quotaExceeded) { return .quotaExceeded }
        if candidates.contains(.requestTooLarge) { return .requestTooLarge }
        if candidates.contains(.providerAccountMismatch) {
            return .providerAccountMismatch
        }
        if candidates.contains(.changeTokenExpired) { return .changeTokenExpired }
        if candidates.contains(.malformedChangeCursor) { return .malformedChangeCursor }
        if candidates.contains(.invalidConfiguration) { return .invalidConfiguration }

        var rateLimited = (wasFound: false, delay: Optional<TimeInterval>.none)
        var network = (wasFound: false, delay: Optional<TimeInterval>.none)
        var service = (wasFound: false, delay: Optional<TimeInterval>.none)
        for failure in candidates {
            switch failure {
            case let .rateLimited(delay):
                rateLimited.wasFound = true
                rateLimited.delay = maximum(rateLimited.delay, delay)
            case let .networkUnavailable(delay):
                network.wasFound = true
                network.delay = maximum(network.delay, delay)
            case let .serviceUnavailable(delay):
                service.wasFound = true
                service.delay = maximum(service.delay, delay)
            default:
                break
            }
        }
        if rateLimited.wasFound {
            return .rateLimited(retryAfterSeconds: rateLimited.delay)
        }
        if network.wasFound {
            return .networkUnavailable(retryAfterSeconds: network.delay)
        }
        if service.wasFound {
            return .serviceUnavailable(retryAfterSeconds: service.delay)
        }

        if candidates.contains(.responseLost) { return .responseLost }
        if candidates.contains(.operationCancelled) { return .operationCancelled }
        if candidates.contains(.zoneMissing) { return .zoneMissing }

        let malformedNames = candidates.compactMap { failure -> String? in
            if case let .malformedRecord(name) = failure { return name }
            return nil
        }.sorted()
        if let firstMalformedName = malformedNames.first {
            return .malformedRecord(recordName: firstMalformedName)
        }

        let missingNames = candidates.flatMap { failure -> [String] in
            if case let .missingRecord(names) = failure { return names }
            return []
        }
        if !missingNames.isEmpty {
            return .missingRecord(recordNames: Array(Set(missingNames)).sorted())
        }
        return .providerRejected
    }

    static func isMissingRecord(_ error: any Error) -> Bool {
        guard let cloudError = error as? CKError else { return false }
        return cloudError.code == .unknownItem
    }

    static func isMissingZone(_ error: any Error) -> Bool {
        guard let cloudError = error as? CKError else { return false }
        return cloudError.code == .unknownItem
            || cloudError.code == .zoneNotFound
            || cloudError.code == .userDeletedZone
    }

    private static func sanitizedRetryAfter(_ error: CKError) -> TimeInterval? {
        guard let value = error.retryAfterSeconds else { return nil }
        guard value.isFinite, value >= 0 else { return nil }
        return min(value, 86_400)
    }

    private static func maximum(
        _ left: TimeInterval?,
        _ right: TimeInterval?
    ) -> TimeInterval? {
        switch (left, right) {
        case let (.some(left), .some(right)):
            max(left, right)
        case let (.some(value), .none), let (.none, .some(value)):
            value
        case (.none, .none):
            nil
        }
    }
}

/// CKServerChangeToken is opaque NSSecureCoding state. Keeping its codec at the
/// SDK boundary prevents domain code from accidentally inspecting or logging
/// provider cursor contents.
enum CloudKitServerChangeTokenCodec {
    static func encode(_ token: CKServerChangeToken) throws -> Data {
        do {
            return try NSKeyedArchiver.archivedData(
                withRootObject: token,
                requiringSecureCoding: true
            )
        } catch {
            throw CloudKitClientFailure.malformedChangeCursor
        }
    }

    static func decode(_ data: Data) throws -> CKServerChangeToken {
        guard !data.isEmpty else {
            throw CloudKitClientFailure.malformedChangeCursor
        }
        do {
            guard let token = try NSKeyedUnarchiver.unarchivedObject(
                ofClass: CKServerChangeToken.self,
                from: data
            ) else {
                throw CloudKitClientFailure.malformedChangeCursor
            }
            return token
        } catch let failure as CloudKitClientFailure {
            throw failure
        } catch {
            throw CloudKitClientFailure.malformedChangeCursor
        }
    }
}

/// The only type in this file that talks to CloudKit. The adapter above it is
/// fully deterministic and tests use a protocol fake, so no test opens or
/// mutates a live container.
fileprivate actor LiveCloudKitPrivateDatabaseClient: CloudKitPrivateDatabaseClient {
    private let container: CKContainer
    private let database: CKDatabase
    private let zoneID: CKRecordZone.ID
    private let payloadFieldName: String
    private var preparedZoneProviderRecordName: String?

    init(configuration: CloudKitCloudSyncConfiguration) {
        let container = CKContainer(identifier: configuration.containerIdentifier)
        self.container = container
        database = container.privateCloudDatabase
        zoneID = CKRecordZone.ID(
            zoneName: configuration.zoneName,
            ownerName: CKCurrentUserDefaultName
        )
        payloadFieldName = configuration.payloadFieldName
    }

    func accountStatus() async throws -> CloudKitClientAccountStatus {
        try await withCheckedThrowingContinuation { continuation in
            container.accountStatus { status, error in
                if let error {
                    continuation.resume(
                        throwing: CloudKitSDKFailureClassifier.classify(error)
                    )
                    return
                }
                let mapped: CloudKitClientAccountStatus
                switch status {
                case .couldNotDetermine:
                    mapped = .couldNotDetermine
                case .available:
                    mapped = .available
                case .restricted:
                    mapped = .restricted
                case .noAccount:
                    mapped = .signedOut
                case .temporarilyUnavailable:
                    mapped = .temporarilyUnavailable
                @unknown default:
                    mapped = .couldNotDetermine
                }
                continuation.resume(returning: mapped)
            }
        }
    }

    func currentUserRecordName() async throws -> String {
        do {
            return try await container.userRecordID().recordName
        } catch {
            throw CloudKitSDKFailureClassifier.classify(error)
        }
    }

    func fetchRecords(named recordNames: [String]) async throws -> [CloudKitClientRecord] {
        try await ensureZoneExists(allowCreation: false)
        let raw = try await fetchRawRecords(named: recordNames)
        return try recordNames.compactMap { name in
            guard let record = raw[name] else { return nil }
            return try makeClientRecord(record)
        }
    }

    func saveAtomically(
        _ writes: [CloudKitClientWrite],
        expectedProviderRecordName: String
    ) async throws -> [CloudKitClientRecord] {
        guard try await currentUserRecordName() == expectedProviderRecordName else {
            throw CloudKitClientFailure.providerAccountMismatch
        }
        try await ensureZoneExists(allowCreation: false)
        let names = writes.map(\.recordName)
        let existing = try await fetchRawRecords(named: names)
        var conflicts: [String] = []
        var recordsToSave: [CKRecord] = []

        for write in writes {
            let current = existing[write.recordName]
            switch write.precondition {
            case .none:
                break
            case .mustNotExist where current != nil:
                conflicts.append(write.recordName)
            case .mustNotExist:
                break
            case let .changeTag(expected):
                if current?.recordChangeTag != expected {
                    conflicts.append(write.recordName)
                }
            }
            if let current, current.recordType != write.recordType {
                conflicts.append(write.recordName)
            }
        }

        if !conflicts.isEmpty {
            throw CloudKitClientFailure.conflict(
                recordNames: Array(Set(conflicts)).sorted()
            )
        }

        for write in writes {
            let record = existing[write.recordName] ?? CKRecord(
                recordType: write.recordType,
                recordID: recordID(named: write.recordName)
            )
            record[payloadFieldName] = write.payload as NSData
            recordsToSave.append(record)
        }

        // Account state can change while existing records are fetched. Bind
        // the mutating SDK call to the exact raw provider identity that the
        // transport validated for this request.
        guard try await currentUserRecordName() == expectedProviderRecordName else {
            throw CloudKitClientFailure.providerAccountMismatch
        }

        let result: (
            saveResults: [CKRecord.ID: Result<CKRecord, any Error>],
            deleteResults: [CKRecord.ID: Result<Void, any Error>]
        )
        do {
            result = try await database.modifyRecords(
                saving: recordsToSave,
                deleting: [],
                savePolicy: .ifServerRecordUnchanged,
                atomically: true
            )
        } catch {
            throw CloudKitSDKFailureClassifier.classify(error)
        }

        var failures: [CloudKitClientFailure] = []
        var savedByName: [String: CKRecord] = [:]
        for write in writes {
            let id = recordID(named: write.recordName)
            guard let itemResult = result.saveResults[id] else {
                failures.append(.providerRejected)
                continue
            }
            switch itemResult {
            case let .success(record):
                savedByName[write.recordName] = record
            case let .failure(error):
                failures.append(
                    CloudKitSDKFailureClassifier.classify(
                        error,
                        fallbackRecordName: write.recordName
                    )
                )
            }
        }
        guard failures.isEmpty else {
            throw CloudKitSDKFailureClassifier.aggregate(failures)
        }
        return try writes.map { write in
            guard let record = savedByName[write.recordName] else {
                throw CloudKitClientFailure.providerRejected
            }
            return try makeClientRecord(record)
        }
    }

    func fetchRecordZoneChanges(
        afterArchivedCursor cursor: Data?,
        allowZoneCreation: Bool
    ) async throws -> CloudKitClientChangePage {
        try await ensureZoneExists(allowCreation: allowZoneCreation)

        let token: CKServerChangeToken?
        if let cursor {
            token = try CloudKitServerChangeTokenCodec.decode(cursor)
        } else {
            token = nil
        }

        let result: (
            modificationResultsByID: [
                CKRecord.ID: Result<CKDatabase.RecordZoneChange.Modification, any Error>
            ],
            deletions: [CKDatabase.RecordZoneChange.Deletion],
            changeToken: CKServerChangeToken,
            moreComing: Bool
        )
        do {
            result = try await database.recordZoneChanges(
                inZoneWith: zoneID,
                since: token,
                desiredKeys: [payloadFieldName],
                resultsLimit: nil
            )
        } catch {
            let classified = CloudKitSDKFailureClassifier.classify(error)
            if classified == .zoneMissing {
                preparedZoneProviderRecordName = nil
            }
            throw classified
        }

        var modifications: [CloudKitClientRecord] = []
        var failures: [CloudKitClientFailure] = []
        for (recordID, recordResult) in result.modificationResultsByID {
            guard recordID.zoneID == zoneID else {
                failures.append(.providerRejected)
                continue
            }
            switch recordResult {
            case let .success(modification):
                let record = modification.record
                guard record.recordID == recordID, record.recordID.zoneID == zoneID else {
                    failures.append(.providerRejected)
                    continue
                }
                do {
                    modifications.append(try makeClientRecord(record))
                } catch let failure as CloudKitClientFailure {
                    failures.append(failure)
                } catch {
                    failures.append(.providerRejected)
                }
            case let .failure(error):
                failures.append(
                    CloudKitSDKFailureClassifier.classify(
                        error,
                        fallbackRecordName: recordID.recordName
                    )
                )
            }
        }

        var deletions: [CloudKitClientRecordDeletion] = []
        for deletion in result.deletions {
            guard deletion.recordID.zoneID == zoneID,
                  !deletion.recordID.recordName.isEmpty,
                  !deletion.recordType.isEmpty else {
                failures.append(.providerRejected)
                continue
            }
            deletions.append(
                CloudKitClientRecordDeletion(
                    recordName: deletion.recordID.recordName,
                    recordType: deletion.recordType
                )
            )
        }

        guard failures.isEmpty else {
            throw CloudKitSDKFailureClassifier.aggregate(failures)
        }
        return CloudKitClientChangePage(
            modifications: modifications.sorted { $0.recordName < $1.recordName },
            deletions: deletions.sorted { $0.recordName < $1.recordName },
            nextCursor: try CloudKitServerChangeTokenCodec.encode(result.changeToken),
            moreComing: result.moreComing
        )
    }

    private func ensureZoneExists(allowCreation: Bool) async throws {
        let providerRecordName = try await currentUserRecordName()
        guard preparedZoneProviderRecordName != providerRecordName else { return }
        do {
            let results = try await database.recordZones(for: [zoneID])
            if let result = results[zoneID] {
                switch result {
                case .success:
                    preparedZoneProviderRecordName = providerRecordName
                    return
                case let .failure(error) where CloudKitSDKFailureClassifier.isMissingZone(error):
                    break
                case let .failure(error):
                    throw CloudKitSDKFailureClassifier.classify(error)
                }
            }
        } catch let failure as CloudKitClientFailure {
            throw failure
        } catch {
            let classified = CloudKitSDKFailureClassifier.classify(error)
            guard classified == .zoneMissing else { throw classified }
        }

        guard allowCreation else {
            preparedZoneProviderRecordName = nil
            throw CloudKitClientFailure.zoneMissing
        }

        guard try await currentUserRecordName() == providerRecordName else {
            preparedZoneProviderRecordName = nil
            throw CloudKitClientFailure.notAuthenticated
        }

        do {
            let result = try await database.modifyRecordZones(
                saving: [CKRecordZone(zoneID: zoneID)],
                deleting: []
            )
            guard let saved = result.saveResults[zoneID] else {
                throw CloudKitClientFailure.providerRejected
            }
            switch saved {
            case .success:
                guard try await currentUserRecordName() == providerRecordName else {
                    preparedZoneProviderRecordName = nil
                    throw CloudKitClientFailure.notAuthenticated
                }
                preparedZoneProviderRecordName = providerRecordName
            case let .failure(error):
                throw CloudKitSDKFailureClassifier.classify(error)
            }
        } catch let failure as CloudKitClientFailure {
            throw failure
        } catch {
            throw CloudKitSDKFailureClassifier.classify(error)
        }
    }

    private func fetchRawRecords(named recordNames: [String]) async throws -> [String: CKRecord] {
        guard !recordNames.isEmpty else { return [:] }
        let ids = recordNames.map(recordID(named:))
        let results: [CKRecord.ID: Result<CKRecord, any Error>]
        do {
            results = try await database.records(for: ids)
        } catch {
            throw CloudKitSDKFailureClassifier.classify(error)
        }

        var found: [String: CKRecord] = [:]
        var failures: [CloudKitClientFailure] = []
        for name in recordNames {
            let id = recordID(named: name)
            guard let result = results[id] else {
                failures.append(.providerRejected)
                continue
            }
            switch result {
            case let .success(record):
                found[name] = record
            case let .failure(error) where CloudKitSDKFailureClassifier.isMissingRecord(error):
                continue
            case let .failure(error):
                failures.append(
                    CloudKitSDKFailureClassifier.classify(
                        error,
                        fallbackRecordName: name
                    )
                )
            }
        }
        guard failures.isEmpty else {
            throw CloudKitSDKFailureClassifier.aggregate(failures)
        }
        return found
    }

    private func makeClientRecord(_ record: CKRecord) throws -> CloudKitClientRecord {
        guard let changeTag = record.recordChangeTag,
              let payload = record[payloadFieldName] as? Data
        else {
            throw CloudKitClientFailure.malformedRecord(
                recordName: record.recordID.recordName
            )
        }
        return CloudKitClientRecord(
            recordName: record.recordID.recordName,
            recordType: record.recordType,
            payload: payload,
            changeTag: changeTag
        )
    }

    private func recordID(named recordName: String) -> CKRecord.ID {
        CKRecord.ID(recordName: recordName, zoneID: zoneID)
    }
}

actor CloudKitCloudSyncTransport: CloudSyncTransport, CloudSyncChangeFetching {
    private let configuration: CloudKitCloudSyncConfiguration
    private let client: any CloudKitPrivateDatabaseClient

    init(
        configuration: CloudKitCloudSyncConfiguration,
        client: any CloudKitPrivateDatabaseClient
    ) {
        self.configuration = configuration
        self.client = client
    }

    static func live(
        configuration: CloudKitCloudSyncConfiguration
    ) -> CloudKitCloudSyncTransport {
        CloudKitCloudSyncTransport(
            configuration: configuration,
            client: LiveCloudKitPrivateDatabaseClient(configuration: configuration)
        )
    }

    func accountState() async -> CloudAccountState {
        do {
            switch try await client.accountStatus() {
            case .available:
                let providerRecordName = try await client.currentUserRecordName()
                return .available(accountID(forProviderRecordName: providerRecordName))
            case .signedOut:
                return .signedOut
            case .restricted:
                return .restricted
            case .couldNotDetermine, .temporarilyUnavailable:
                return .unknown
            }
        } catch {
            return .unknown
        }
    }

    func recordChanges(
        accountID: CloudAccountID,
        after cursor: CloudChangeCursor?,
        zonePreparation: CloudZonePreparationPolicy
    ) async throws -> CloudRecordChangePage {
        guard zonePreparation == .requireExisting else {
            throw CloudKitCloudSyncError.invalidRequest
        }
        return try await recordChanges(
            accountID: accountID,
            after: cursor,
            allowZoneCreation: false
        )
    }

    /// The raw change-fetch protocol cannot create a zone. Release bootstrap
    /// must present the opaque permit retained only by a store-issued context.
    func recordInitialBootstrapChanges(
        accountID: CloudAccountID,
        after cursor: CloudChangeCursor?,
        authorization: CloudReplicaInitialBootstrapReservedFetchV1
    ) async throws -> CloudRecordChangePage {
        let allowZoneCreation: Bool
        switch authorization.networkPolicy {
        case .mayCreateZoneOnFirstRequest:
            allowZoneCreation = cursor == nil
        case .requireExistingZoneRecovery:
            allowZoneCreation = false
        }
        return try await recordChanges(
            accountID: accountID,
            after: cursor,
            allowZoneCreation: allowZoneCreation
        )
    }

    #if DEBUG
    /// Adapter tests exercise both provider policies without exposing a
    /// zone-creating raw protocol path in Release.
    func _testOnlyRecordChanges(
        accountID: CloudAccountID,
        after cursor: CloudChangeCursor?,
        zonePreparation: CloudZonePreparationPolicy
    ) async throws -> CloudRecordChangePage {
        if cursor != nil, zonePreparation == .createIfMissingForInitialBootstrap {
            throw CloudKitCloudSyncError.invalidRequest
        }
        return try await recordChanges(
            accountID: accountID,
            after: cursor,
            allowZoneCreation:
                zonePreparation == .createIfMissingForInitialBootstrap
        )
    }
    #endif

    private func recordChanges(
        accountID: CloudAccountID,
        after cursor: CloudChangeCursor?,
        allowZoneCreation: Bool
    ) async throws -> CloudRecordChangePage {
        _ = try await requireActive(accountID)

        let clientPage: CloudKitClientChangePage
        do {
            clientPage = try await client.fetchRecordZoneChanges(
                afterArchivedCursor: cursor?.rawValue,
                allowZoneCreation: allowZoneCreation
            )
        } catch let failure as CloudKitClientFailure {
            switch failure {
            case .zoneMissing:
                throw CloudKitCloudSyncError.zoneResetRequired
            case .changeTokenExpired:
                throw CloudKitCloudSyncError.changeCursorExpired
            case .malformedChangeCursor:
                throw CloudKitCloudSyncError.malformedChangeCursor
            default:
                throw translated(failure, recordNameToID: [:])
            }
        }
        _ = try await revalidate(accountID)

        guard !clientPage.nextCursor.isEmpty else {
            throw CloudKitCloudSyncError.malformedChangeCursor
        }

        var modifications: [CloudDiscoveredRecord] = []
        var modificationLocators: Set<CloudProviderRecordLocator> = []
        var logicalRecordIDs: Set<CloudRecordID> = []
        for clientRecord in clientPage.modifications {
            if clientRecord.recordType == configuration.operationRecordType {
                continue
            }
            guard !clientRecord.recordName.isEmpty,
                  !clientRecord.recordType.isEmpty,
                  !clientRecord.changeTag.isEmpty else {
                throw CloudKitCloudSyncError.malformedDiscoveredRecord
            }

            let envelope: CloudKitRecordPayloadV3
            do {
                envelope = try CloudKitPayloadCodec.decode(
                    CloudKitRecordPayloadV3.self,
                    from: clientRecord.payload
                )
            } catch {
                throw CloudKitCloudSyncError.malformedDiscoveredRecord
            }
            guard envelope.schemaVersion == CloudKitRecordPayloadV3.currentSchemaVersion,
                  !envelope.logicalRecordID.rawValue.isEmpty,
                  recordName(for: envelope.logicalRecordID) == clientRecord.recordName else {
                throw CloudKitCloudSyncError.malformedDiscoveredRecord
            }

            let locator = CloudProviderRecordLocator(clientRecord.recordName)
            guard modificationLocators.insert(locator).inserted,
                  logicalRecordIDs.insert(envelope.logicalRecordID).inserted else {
                throw CloudKitCloudSyncError.inconsistentChangePage
            }
            modifications.append(
                CloudDiscoveredRecord(
                    locator: locator,
                    record: CloudRecord(
                        id: envelope.logicalRecordID,
                        recordType: clientRecord.recordType,
                        fields: envelope.fields,
                        changeTag: CloudChangeTag(clientRecord.changeTag)
                    )
                )
            )
        }

        var deletions: [CloudDeletedRecord] = []
        var deletionLocators: Set<CloudProviderRecordLocator> = []
        for deletion in clientPage.deletions {
            if deletion.recordType == configuration.operationRecordType {
                continue
            }
            guard !deletion.recordName.isEmpty, !deletion.recordType.isEmpty else {
                throw CloudKitCloudSyncError.inconsistentChangePage
            }
            let locator = CloudProviderRecordLocator(deletion.recordName)
            guard deletionLocators.insert(locator).inserted,
                  !modificationLocators.contains(locator) else {
                throw CloudKitCloudSyncError.inconsistentChangePage
            }
            deletions.append(
                CloudDeletedRecord(locator: locator, recordType: deletion.recordType)
            )
        }

        modifications.sort { $0.locator.rawValue < $1.locator.rawValue }
        deletions.sort { $0.locator.rawValue < $1.locator.rawValue }
        return CloudRecordChangePage(
            accountID: accountID,
            modifications: modifications,
            deletions: deletions,
            nextCursor: CloudChangeCursor(clientPage.nextCursor),
            moreComing: clientPage.moreComing
        )
    }

    func records(
        accountID: CloudAccountID,
        ids: [CloudRecordID]
    ) async throws -> [CloudRecord] {
        _ = try await requireActive(accountID)
        let uniqueIDs = unique(ids)
        let mapping = try recordNameMapping(for: uniqueIDs)
        let names = uniqueIDs.compactMap { id in
            mapping.first(where: { $0.value == id })?.key
        }
        let fetched: [CloudKitClientRecord]
        do {
            fetched = try await client.fetchRecords(named: names)
        } catch let failure as CloudKitClientFailure {
            throw translated(failure, recordNameToID: mapping)
        }
        _ = try await revalidate(accountID)

        var byID: [CloudRecordID: CloudRecord] = [:]
        for record in fetched {
            guard let id = mapping[record.recordName] else {
                throw CloudKitCloudSyncError.providerRequestRejected
            }
            let envelope: CloudKitRecordPayloadV3
            do {
                envelope = try CloudKitPayloadCodec.decode(
                    CloudKitRecordPayloadV3.self,
                    from: record.payload
                )
            } catch {
                throw CloudKitCloudSyncError.malformedRecord(id)
            }
            guard envelope.schemaVersion == CloudKitRecordPayloadV3.currentSchemaVersion,
                  envelope.logicalRecordID == id,
                  recordName(for: id) == record.recordName,
                  !record.recordType.isEmpty,
                  !record.changeTag.isEmpty,
                  byID[id] == nil else {
                throw CloudKitCloudSyncError.malformedRecord(id)
            }
            byID[id] = CloudRecord(
                id: id,
                recordType: record.recordType,
                fields: envelope.fields,
                changeTag: CloudChangeTag(record.changeTag)
            )
        }
        return uniqueIDs.compactMap { byID[$0] }
    }

    func commitAtomically(
        _ request: CloudAtomicWriteRequest
    ) async throws -> CloudAtomicWriteReceipt {
        _ = try await requireActive(request.accountID)
        try validate(request)

        let writeIDs = request.writes.map(\.id)
        let mapping = try recordNameMapping(for: writeIDs)
        let fingerprint = CloudKitOperationFingerprint.make(request)
        let markerName = operationMarkerName(for: request.operationID)
        let targetNames = mapping.keys.sorted(by: CloudKitStableOrdering.precedes)

        if let recovered = try await recoverReceiptIfPresent(
            request: request,
            fingerprint: fingerprint,
            markerName: markerName,
            targetNames: targetNames,
            recordNameToID: mapping
        ) {
            return recovered
        }

        // Account can change while the marker lookup is suspended. Recheck
        // before the only mutating call so the new private database never
        // receives the old account's queued operation.
        let expectedProviderRecordName = try await revalidate(request.accountID)

        let marker = CloudKitOperationMarkerV2(
            schemaVersion: CloudKitOperationMarkerV2.currentSchemaVersion,
            requestFingerprint: fingerprint,
            targetRecordNames: targetNames
        )
        let markerPayload = try CloudKitPayloadCodec.encode(marker)

        var clientWrites: [CloudKitClientWrite] = try request.writes.map { write in
            guard let recordName = mapping.first(where: { $0.value == write.id })?.key else {
                throw CloudKitCloudSyncError.invalidRequest
            }
            let payload = CloudKitRecordPayloadV3(
                schemaVersion: CloudKitRecordPayloadV3.currentSchemaVersion,
                logicalRecordID: write.id,
                fields: write.fields,
                lastOperationFingerprint: fingerprint
            )
            return CloudKitClientWrite(
                recordName: recordName,
                recordType: write.recordType,
                payload: try CloudKitPayloadCodec.encode(payload),
                precondition: clientPrecondition(write.precondition)
            )
        }
        clientWrites.append(
            CloudKitClientWrite(
                recordName: markerName,
                recordType: configuration.operationRecordType,
                payload: markerPayload,
                precondition: .mustNotExist
            )
        )

        let saved: [CloudKitClientRecord]
        do {
            saved = try await client.saveAtomically(
                clientWrites,
                expectedProviderRecordName: expectedProviderRecordName
            )
        } catch let failure as CloudKitClientFailure {
            if shouldAttemptMarkerRecovery(failure, markerName: markerName),
               let recovered = try await recoverReceiptIfPresent(
                   request: request,
                   fingerprint: fingerprint,
                   markerName: markerName,
                   targetNames: targetNames,
                   recordNameToID: mapping
               ) {
                return recovered
            }
            throw translated(failure, recordNameToID: mapping)
        }
        _ = try await revalidate(request.accountID)

        let savedByName = Dictionary(uniqueKeysWithValues: saved.map { ($0.recordName, $0) })
        var tags: [CloudRecordID: CloudChangeTag] = [:]
        for (recordName, id) in mapping {
            guard let savedRecord = savedByName[recordName] else {
                throw CloudKitCloudSyncError.providerRequestRejected
            }
            tags[id] = CloudChangeTag(savedRecord.changeTag)
        }
        return CloudAtomicWriteReceipt(
            accountID: request.accountID,
            operationID: request.operationID,
            savedChangeTags: tags
        )
    }

    private func recoverReceiptIfPresent(
        request: CloudAtomicWriteRequest,
        fingerprint: Data,
        markerName: String,
        targetNames: [String],
        recordNameToID: [String: CloudRecordID]
    ) async throws -> CloudAtomicWriteReceipt? {
        let markerRecords: [CloudKitClientRecord]
        do {
            markerRecords = try await client.fetchRecords(named: [markerName])
        } catch let failure as CloudKitClientFailure {
            throw translated(failure, recordNameToID: recordNameToID)
        }
        guard let markerRecord = markerRecords.first else { return nil }
        guard markerRecord.recordType == configuration.operationRecordType else {
            throw CloudKitCloudSyncError.malformedOperationMarker
        }

        let marker: CloudKitOperationMarkerV2
        do {
            marker = try CloudKitPayloadCodec.decode(
                CloudKitOperationMarkerV2.self,
                from: markerRecord.payload
            )
        } catch {
            throw CloudKitCloudSyncError.malformedOperationMarker
        }
        guard marker.schemaVersion == CloudKitOperationMarkerV2.currentSchemaVersion,
              marker.requestFingerprint == fingerprint,
              marker.targetRecordNames == targetNames
        else {
            if marker.schemaVersion == CloudKitOperationMarkerV2.currentSchemaVersion {
                throw CloudSyncTransportError.operationIDCollision(request.operationID)
            }
            throw CloudKitCloudSyncError.malformedOperationMarker
        }

        let targetRecords: [CloudKitClientRecord]
        do {
            targetRecords = try await client.fetchRecords(named: targetNames)
        } catch let failure as CloudKitClientFailure {
            throw translated(failure, recordNameToID: recordNameToID)
        }
        let targetByName = Dictionary(
            uniqueKeysWithValues: targetRecords.map { ($0.recordName, $0) }
        )
        let refreshIDs = recordNameToID.values.sorted { $0.rawValue < $1.rawValue }
        guard targetRecords.count == targetNames.count else {
            throw CloudKitCloudSyncError.committedOperationRequiresRefresh(
                operationID: request.operationID,
                recordIDs: refreshIDs
            )
        }

        var tags: [CloudRecordID: CloudChangeTag] = [:]
        for name in targetNames {
            guard let record = targetByName[name],
                  let id = recordNameToID[name],
                  let payload = try? CloudKitPayloadCodec.decode(
                      CloudKitRecordPayloadV3.self,
                      from: record.payload
                  ),
                  payload.schemaVersion == CloudKitRecordPayloadV3.currentSchemaVersion,
                  payload.logicalRecordID == id,
                  recordName(for: id) == name,
                  payload.lastOperationFingerprint == fingerprint
            else {
                throw CloudKitCloudSyncError.committedOperationRequiresRefresh(
                    operationID: request.operationID,
                    recordIDs: refreshIDs
                )
            }
            tags[id] = CloudChangeTag(record.changeTag)
        }
        _ = try await revalidate(request.accountID)
        return CloudAtomicWriteReceipt(
            accountID: request.accountID,
            operationID: request.operationID,
            savedChangeTags: tags
        )
    }

    private func validate(_ request: CloudAtomicWriteRequest) throws {
        let ids = request.writes.map(\.id)
        guard Set(ids).count == ids.count,
              request.writes.allSatisfy({
                  !$0.recordType.isEmpty
                      && $0.recordType != configuration.operationRecordType
              })
        else {
            throw CloudKitCloudSyncError.invalidRequest
        }
    }

    private func requireActive(
        _ expectedAccountID: CloudAccountID
    ) async throws -> String {
        let active = try await activeAccount()
        guard active.accountID == expectedAccountID else {
            throw CloudSyncTransportError.accountMismatch
        }
        return active.providerRecordName
    }

    private func revalidate(
        _ expectedAccountID: CloudAccountID
    ) async throws -> String {
        do {
            return try await requireActive(expectedAccountID)
        } catch CloudSyncTransportError.accountUnavailable,
                CloudKitCloudSyncError.accountRestricted {
            throw CloudSyncTransportError.accountMismatch
        }
    }

    private func activeAccount() async throws -> (
        accountID: CloudAccountID,
        providerRecordName: String
    ) {
        let status: CloudKitClientAccountStatus
        do {
            status = try await client.accountStatus()
        } catch let failure as CloudKitClientFailure {
            throw translated(failure, recordNameToID: [:])
        }
        switch status {
        case .available:
            do {
                let providerName = try await client.currentUserRecordName()
                return (
                    accountID(forProviderRecordName: providerName),
                    providerName
                )
            } catch let failure as CloudKitClientFailure {
                throw translated(failure, recordNameToID: [:])
            }
        case .signedOut:
            throw CloudSyncTransportError.accountUnavailable
        case .restricted:
            throw CloudKitCloudSyncError.accountRestricted
        case .couldNotDetermine, .temporarilyUnavailable:
            throw CloudKitCloudSyncError.accountTemporarilyUnavailable
        }
    }

    private func recordNameMapping(
        for ids: [CloudRecordID]
    ) throws -> [String: CloudRecordID] {
        var mapping: [String: CloudRecordID] = [:]
        for id in ids {
            let name = recordName(for: id)
            if let existing = mapping[name], existing != id {
                throw CloudKitCloudSyncError.invalidRequest
            }
            mapping[name] = id
        }
        return mapping
    }

    private func recordName(for id: CloudRecordID) -> String {
        CloudKitOpaqueIdentifier.make(
            namespace: configuration.recordNameNamespace,
            kind: CloudKitCloudSchema.recordAddressKind,
            value: id.rawValue
        )
    }

    private func accountID(forProviderRecordName recordName: String) -> CloudAccountID {
        configuration.accountID(forProviderRecordName: recordName)
    }

    private func operationMarkerName(for operationID: OperationID) -> String {
        CloudKitOpaqueIdentifier.make(
            namespace: configuration.recordNameNamespace,
            kind: CloudKitCloudSchema.operationAddressKind,
            value: operationID.rawValue
        )
    }

    private func clientPrecondition(
        _ precondition: CloudRecordPrecondition
    ) -> CloudKitClientWritePrecondition {
        switch precondition {
        case .none:
            .none
        case .mustNotExist:
            .mustNotExist
        case let .changeTag(tag):
            .changeTag(tag.rawValue)
        }
    }

    private func shouldAttemptMarkerRecovery(
        _ failure: CloudKitClientFailure,
        markerName: String
    ) -> Bool {
        switch failure {
        case let .conflict(names):
            names.contains(markerName)
        case .responseLost:
            true
        default:
            false
        }
    }

    private func translated(
        _ failure: CloudKitClientFailure,
        recordNameToID: [String: CloudRecordID]
    ) -> any Error {
        switch failure {
        case let .conflict(names):
            let ids = names.compactMap { recordNameToID[$0] }
                .sorted { $0.rawValue < $1.rawValue }
            return ids.isEmpty
                ? CloudKitCloudSyncError.providerRequestRejected
                : CloudSyncTransportError.conflict(ids)
        case let .malformedRecord(name):
            if let id = recordNameToID[name] {
                return CloudKitCloudSyncError.malformedRecord(id)
            }
            return CloudKitCloudSyncError.malformedOperationMarker
        case let .networkUnavailable(delay):
            return CloudKitCloudSyncError.networkUnavailable(retryAfterSeconds: delay)
        case let .serviceUnavailable(delay):
            return CloudKitCloudSyncError.serviceUnavailable(retryAfterSeconds: delay)
        case let .rateLimited(delay):
            return CloudKitCloudSyncError.rateLimited(retryAfterSeconds: delay)
        case .notAuthenticated:
            return CloudSyncTransportError.accountUnavailable
        case .accountTemporarilyUnavailable:
            return CloudKitCloudSyncError.accountTemporarilyUnavailable
        case .permissionDenied:
            return CloudKitCloudSyncError.permissionDenied
        case .quotaExceeded:
            return CloudKitCloudSyncError.quotaExceeded
        case .requestTooLarge:
            return CloudKitCloudSyncError.requestTooLarge
        case .zoneMissing:
            return CloudKitCloudSyncError.zoneResetRequired
        case .providerAccountMismatch:
            return CloudSyncTransportError.accountMismatch
        case .changeTokenExpired:
            return CloudKitCloudSyncError.changeCursorExpired
        case .malformedChangeCursor:
            return CloudKitCloudSyncError.malformedChangeCursor
        case .invalidConfiguration:
            return CloudKitCloudSyncError.providerConfigurationRejected
        case .responseLost, .batchRequestFailed:
            return CloudKitCloudSyncError.serviceUnavailable(retryAfterSeconds: nil)
        case .operationCancelled:
            return CloudKitCloudSyncError.operationCancelled
        case .missingRecord, .providerRejected:
            return CloudKitCloudSyncError.providerRequestRejected
        }
    }

    private func unique(_ ids: [CloudRecordID]) -> [CloudRecordID] {
        var seen: Set<CloudRecordID> = []
        return ids.filter { seen.insert($0).inserted }
    }
}

private struct CloudKitRecordPayloadV3: Codable, Equatable, Sendable {
    static let currentSchemaVersion = CloudKitCloudSchema.recordEnvelopeSchemaVersion

    let schemaVersion: Int
    let logicalRecordID: CloudRecordID
    let fields: [String: Data]
    let lastOperationFingerprint: Data

    enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion
        case logicalRecordID
        case fields
        case lastOperationFingerprint
    }

    static var persistedFieldManifest: String {
        CodingKeys.allCases.map(\.rawValue).sorted().joined(separator: ",")
    }
}

private struct CloudKitOperationMarkerV2: Codable, Equatable, Sendable {
    static let currentSchemaVersion = CloudKitCloudSchema.operationMarkerSchemaVersion

    let schemaVersion: Int
    let requestFingerprint: Data
    let targetRecordNames: [String]

    enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion
        case requestFingerprint
        case targetRecordNames
    }

    static var persistedFieldManifest: String {
        CodingKeys.allCases.map(\.rawValue).sorted().joined(separator: ",")
    }
}

private enum CloudKitPayloadCodec {
    static let encodingIdentifier =
        "sorted-key-json-default-keys-without-escaped-slashes-deferred-date-base64-data-nonfinite-float-throw-v1"

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.keyEncodingStrategy = .useDefaultKeys
        encoder.dateEncodingStrategy = .deferredToDate
        encoder.dataEncodingStrategy = .base64
        encoder.nonConformingFloatEncodingStrategy = .throw
        return try encoder.encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        decoder.dateDecodingStrategy = .deferredToDate
        decoder.dataDecodingStrategy = .base64
        decoder.nonConformingFloatDecodingStrategy = .throw
        return try decoder.decode(type, from: data)
    }
}

private enum CloudKitOpaqueIdentifier {
    static func make(namespace: String, kind: String, value: String) -> String {
        var builder = StableDigestBuilder()
        builder.append(CloudKitCloudSchema.opaqueIdentifierDomain)
        builder.append(namespace)
        builder.append(kind)
        builder.append(value)
        return builder.hexDigest()
    }
}

private enum CloudKitOperationFingerprint {
    static func make(_ request: CloudAtomicWriteRequest) -> Data {
        var builder = StableDigestBuilder()
        builder.append(CloudKitCloudSchema.operationFingerprintDomain)
        builder.append(request.accountID.rawValue)
        builder.append(request.operationID.rawValue)

        let writes = request.writes.sorted(by: {
            CloudKitStableOrdering.precedes($0.id.rawValue, $1.id.rawValue)
        })
        builder.appendCount(writes.count)
        for write in writes {
            builder.append(write.id.rawValue)
            builder.append(write.recordType)
            switch write.precondition {
            case .none:
                builder.append("none")
            case .mustNotExist:
                builder.append("must-not-exist")
            case let .changeTag(tag):
                builder.append("change-tag")
                builder.append(tag.rawValue)
            }
            builder.appendCount(write.fields.count)
            for key in write.fields.keys.sorted(by: CloudKitStableOrdering.precedes) {
                builder.append(key)
                builder.append(write.fields[key] ?? Data())
            }
        }
        return builder.digest()
    }
}

private enum CloudKitStableOrdering {
    static func precedes(_ lhs: String, _ rhs: String) -> Bool {
        lhs.utf8.lexicographicallyPrecedes(rhs.utf8)
    }
}

private struct StableDigestBuilder {
    static let algorithmIdentifier = "sha256-v1"
    static let componentEncodingIdentifier =
        "uint64-big-endian-length-prefixed-bytes-v1"
    static let countEncodingIdentifier =
        "uint64-big-endian-as-length-prefixed-eight-byte-component-v1"
    static let hexEncodingIdentifier =
        "lowercase-two-digit-hex-per-byte-v1"

    private var bytes = Data()

    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }

    mutating func append(_ data: Data) {
        var length = UInt64(data.count).bigEndian
        withUnsafeBytes(of: &length) { raw in
            bytes.append(contentsOf: raw)
        }
        bytes.append(data)
    }

    mutating func appendCount(_ count: Int) {
        precondition(count >= 0, "A collection count cannot be negative")
        var value = UInt64(count).bigEndian
        withUnsafeBytes(of: &value) { raw in
            append(Data(raw))
        }
    }

    func digest() -> Data {
        Data(SHA256.hash(data: bytes))
    }

    func hexDigest() -> String {
        digest().map { String(format: "%02x", $0) }.joined()
    }
}

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
        make(
            for: configuration,
            achievementMaterial:
                AchievementCatalog.persistedFingerprintMaterial()
        )
    }

    static func make(
        for configuration: ProductionCloudWriteConfiguration,
        achievementMaterial: [String]
    ) -> Self {
        make(
            for: configuration,
            achievementMaterial: achievementMaterial,
            canonicalPayloadMaterial:
                CloudProfileCanonicalPayload.fingerprintMaterial
        )
    }

    static func make(
        for configuration: ProductionCloudWriteConfiguration,
        achievementMaterial: [String],
        canonicalPayloadMaterial: [String]
    ) -> Self {
        make(
            for: configuration,
            achievementMaterial: achievementMaterial,
            catalogMaterial:
                LaunchCatalog.approved.persistedFingerprintMaterial,
            canonicalPayloadMaterial: canonicalPayloadMaterial
        )
    }

    static func make(
        for configuration: ProductionCloudWriteConfiguration,
        achievementMaterial: [String],
        catalogMaterial: [String],
        canonicalPayloadMaterial: [String]
    ) -> Self {
        var hasher = SHA256()
        for value in orderedMaterial(
            for: configuration,
            achievementMaterial: achievementMaterial,
            catalogMaterial: catalogMaterial,
            canonicalPayloadMaterial: canonicalPayloadMaterial
        ) {
            append(value, to: &hasher)
        }
        return Self(
            rawValue: hasher.finalize().map { String(format: "%02x", $0) }.joined()
        )
    }

    static func orderedMaterial(
        for configuration: ProductionCloudWriteConfiguration
    ) -> [String] {
        orderedMaterial(
            for: configuration,
            achievementMaterial:
                AchievementCatalog.persistedFingerprintMaterial()
        )
    }

    static func orderedMaterial(
        for configuration: ProductionCloudWriteConfiguration,
        achievementMaterial: [String]
    ) -> [String] {
        orderedMaterial(
            for: configuration,
            achievementMaterial: achievementMaterial,
            canonicalPayloadMaterial:
                CloudProfileCanonicalPayload.fingerprintMaterial
        )
    }

    static func orderedMaterial(
        for configuration: ProductionCloudWriteConfiguration,
        achievementMaterial: [String],
        canonicalPayloadMaterial: [String]
    ) -> [String] {
        orderedMaterial(
            for: configuration,
            achievementMaterial: achievementMaterial,
            catalogMaterial:
                LaunchCatalog.approved.persistedFingerprintMaterial,
            canonicalPayloadMaterial: canonicalPayloadMaterial
        )
    }

    static func orderedMaterial(
        for configuration: ProductionCloudWriteConfiguration,
        achievementMaterial: [String],
        catalogMaterial: [String],
        canonicalPayloadMaterial: [String]
    ) -> [String] {
        let transport = configuration.transport.fingerprintMaterial
        let economy = configuration.economy.fingerprintMaterial
        let profile = configuration.profile.fingerprintMaterial(
            achievementMaterial: achievementMaterial,
            catalogMaterial: catalogMaterial,
            canonicalPayloadMaterial: canonicalPayloadMaterial
        )
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

/// Literal evaluator and catalog material for the two shipped launch scopes.
/// Current domain types must never be used to reconstruct these predecessors:
/// doing so would silently rewrite a sealed checkpoint identity whenever the
/// live evaluator gains a dependency.
private enum LaunchAchievementCloudFingerprintHistory {
    static let canonicalPayloadV1 = [
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
        "selectionEnvelopeFields", "binding,schemaVersion,selection,stamp",
        "playerSelectionFields",
        "selectedFootballID,selectedJerseyByTeam,selectedTeamID",
        "completedRunEnvelopeFields",
        "binding,record,rewardedRunObservation,schemaVersion",
        "completedRunRecordFields", "recordedAt,rewardCoins,run",
        "completedRunFields",
        "bonusTouchdownCount,completedLaneIDs,configuration,elapsedGameplayMilliseconds,endedAt,finishReason,score,statistics",
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

    static let evaluatorV1: [String] = {
        let completedRun = CompletedRun.achievementEligibilityFingerprintMaterial
        let runStatistics =
            RunStatisticsSnapshot.achievementDependencyFingerprintMaterial
        let career = [
            "pocket-vector-career-statistics-achievement-dependencies-v1",
            "successfulPassesPolicy",
            "completions-plus-touchdowns-native-int-v1",
        ]
        let accumulator = PersistedCareerAccumulatorV1.persistedFingerprintMaterial
        return [
            "pocket-vector-achievement-evaluator-semantics-v1",
            "eligibleRunPolicy", "naturally-completed-runs-only-v1",
            "evaluationOrderPolicy", "achievement-id-utf8-ascending-v1",
            "progressPolicy",
            "monotonic-max-percent-and-first-completion-date-v1",
            "binaryProgressPolicy",
            "value-greater-than-or-equal-target-yields-100-else-0-v1",
            "scaledProgressPolicy",
            "target-nonpositive-100-else-clamped-integer-floor-percent-v1",
            "allLanesPolicy", "set-intersection-with-all-lane-ids-v1",
            "completedRunDependencyMaterialCount", String(completedRun.count),
        ] + completedRun + [
            "runStatisticsDependencyMaterialCount", String(runStatistics.count),
        ] + runStatistics + [
            "careerDependencyMaterialCount", String(career.count),
        ] + career + [
            "careerAccumulatorDependencyMaterialCount", String(accumulator.count),
        ] + accumulator
    }()

    static let catalogV1: [String] = catalogMaterial(
        semanticIdentifier:
            AchievementCatalogTransitionV1ToV2.sourceCatalogSemanticIdentifier,
        definitions: [
            AchievementDefinition(
                id: LaunchAchievementID.firstRead,
                displayName: "First Read",
                detail: "Complete any successful pass.",
                points: 25,
                rule: .careerSuccessfulPasses(1)
            ),
            AchievementDefinition(
                id: LaunchAchievementID.paydirt,
                displayName: "Paydirt",
                detail: "Score a touchdown.",
                points: 50,
                rule: .careerTouchdowns(1)
            ),
            AchievementDefinition(
                id: LaunchAchievementID.cashTheCharge,
                displayName: "Cash the Charge",
                detail: "Score a touchdown while TD Bonus is active.",
                points: 75,
                rule: .careerBonusTouchdowns(1)
            ),
            AchievementDefinition(
                id: LaunchAchievementID.fullRouteTree,
                displayName: "Full Route Tree",
                detail: "Complete a pass in all four lanes during one run.",
                points: 75,
                rule: .allLanesInSingleRun
            ),
            AchievementDefinition(
                id: LaunchAchievementID.dialedIn,
                displayName: "Dialed In",
                detail: "Finish with at least 80% accuracy over at least 12 attempts.",
                points: 75,
                rule: .singleRunAccuracy(percent: 80, minimumAttempts: 12)
            ),
            AchievementDefinition(
                id: LaunchAchievementID.hotHand,
                displayName: "Hot Hand",
                detail: "Score four consecutive touchdowns during one run.",
                points: 100,
                rule: .singleRunTouchdownStreak(4)
            ),
            AchievementDefinition(
                id: LaunchAchievementID.lightUpTheBoard,
                displayName: "Light Up the Board",
                detail: "Reach 25,000 points during one run.",
                points: 100,
                rule: .singleRunScore(25_000)
            ),
            AchievementDefinition(
                id: AchievementCatalogTransitionV1ToV2
                    .retiredCenturyOfConnections,
                displayName: "Century of Connections",
                detail: "Complete 100 career passes, including touchdowns.",
                points: 100,
                rule: .incrementalCareerSuccessfulPasses(100)
            ),
        ],
        transitionMaterial: nil
    )

    static let catalogV2: [String] = catalogMaterial(
        semanticIdentifier: AchievementCatalog.v2PersistedSemanticIdentifier,
        definitions: [
            AchievementDefinition(
                id: LaunchAchievementID.firstRead,
                displayName: "First Read",
                detail: "Complete any successful pass.",
                points: 25,
                rule: .careerSuccessfulPasses(1)
            ),
            AchievementDefinition(
                id: LaunchAchievementID.paydirt,
                displayName: "Paydirt",
                detail: "Score a touchdown.",
                points: 50,
                rule: .careerTouchdowns(1)
            ),
            AchievementDefinition(
                id: LaunchAchievementID.cashTheCharge,
                displayName: "Cash the Charge",
                detail: "Score a touchdown while TD Bonus is active.",
                points: 75,
                rule: .careerBonusTouchdowns(1)
            ),
            AchievementDefinition(
                id: LaunchAchievementID.fullRouteTree,
                displayName: "Full Route Tree",
                detail: "Complete a pass in all four lanes during one run.",
                points: 75,
                rule: .allLanesInSingleRun
            ),
            AchievementDefinition(
                id: LaunchAchievementID.dialedIn,
                displayName: "Dialed In",
                detail: "Finish with at least 80% accuracy over at least 25 pass attempts.",
                points: 75,
                rule: .singleRunAccuracy(percent: 80, minimumAttempts: 25)
            ),
            AchievementDefinition(
                id: LaunchAchievementID.hotHand,
                displayName: "Hot Hand",
                detail: "Score four consecutive touchdowns during one run.",
                points: 100,
                rule: .singleRunTouchdownStreak(4)
            ),
            AchievementDefinition(
                id: LaunchAchievementID.lightUpTheBoard,
                displayName: "Light Up the Board",
                detail: "Reach 65,000 points during one run.",
                points: 100,
                rule: .singleRunScore(65_000)
            ),
            AchievementDefinition(
                id: LaunchAchievementID.millenniaOfConnections,
                displayName: "Millennia of Connections",
                detail: "Complete 1,000 career passes, including touchdowns.",
                points: 100,
                rule: .incrementalCareerSuccessfulPasses(1_000)
            ),
        ],
        transitionMaterial:
            AchievementCatalogTransitionV1ToV2.persistedFingerprintMaterial
    )

    private static func catalogMaterial(
        semanticIdentifier: String,
        definitions: [AchievementDefinition],
        transitionMaterial: [String]?
    ) -> [String] {
        let ordered = AchievementCatalog.persistedEvaluationOrder(definitions)
        var material = [
            semanticIdentifier,
            "evaluatorMaterialCount", String(evaluatorV1.count),
        ] + evaluatorV1 + [
            "achievementCount", String(ordered.count),
        ]
        for definition in ordered {
            let rule = definition.rule.persistedFingerprintMaterial
            material.append(contentsOf: [
                "achievement", definition.id.rawValue,
                "points", String(definition.points),
                "ruleMaterialCount", String(rule.count),
            ])
            material.append(contentsOf: rule)
        }
        if let transitionMaterial {
            material.append(contentsOf: [
                "transitionMaterialCount", String(transitionMaterial.count),
            ])
            material.append(contentsOf: transitionMaterial)
        }
        return material
    }
}

/// Frozen V1-to-V2 scope transition retained for direct-upgrade and regression
/// coverage. Neither endpoint references the live V3 catalog.
enum LaunchAchievementCloudScopeTransitionV1ToV2 {
    static let sourceAchievementFingerprintMaterial =
        LaunchAchievementCloudFingerprintHistory.catalogV1
    static let targetAchievementFingerprintMaterial =
        LaunchAchievementCloudFingerprintHistory.catalogV2
    static let sourceCanonicalPayloadFingerprintMaterial =
        LaunchAchievementCloudFingerprintHistory.canonicalPayloadV1

    static func sourceScope(
        for configuration: ProductionCloudWriteConfiguration
    ) -> CloudReplicaScopeFingerprint {
        CloudReplicaScopeFingerprint.make(
            for: configuration,
            achievementMaterial: sourceAchievementFingerprintMaterial,
            catalogMaterial:
                LaunchCatalogTransitionV1ToV2
                    .sourcePersistedFingerprintMaterial,
            canonicalPayloadMaterial:
                sourceCanonicalPayloadFingerprintMaterial
        )
    }

    static func targetScope(
        for configuration: ProductionCloudWriteConfiguration
    ) -> CloudReplicaScopeFingerprint {
        CloudReplicaScopeFingerprint.make(
            for: configuration,
            achievementMaterial: targetAchievementFingerprintMaterial,
            catalogMaterial:
                LaunchCatalogTransitionV1ToV2
                    .sourcePersistedFingerprintMaterial,
            canonicalPayloadMaterial:
                sourceCanonicalPayloadFingerprintMaterial
        )
    }
}

/// Active Version 1.1 transition from the frozen Build 160 V2 scope to the
/// live V3 scope. The checkpoint preparer revokes V2 authority and bootstraps a
/// fresh V3 generation; it never merges records across the two meanings.
enum LaunchAchievementCloudScopeTransitionV2ToV3 {
    static let sourceAchievementFingerprintMaterial =
        LaunchAchievementCloudFingerprintHistory.catalogV2
    static let sourceCanonicalPayloadFingerprintMaterial =
        LaunchAchievementCloudScopeTransitionV1ToV2
            .sourceCanonicalPayloadFingerprintMaterial

    static func sourceScope(
        for configuration: ProductionCloudWriteConfiguration
    ) -> CloudReplicaScopeFingerprint {
        CloudReplicaScopeFingerprint.make(
            for: configuration,
            achievementMaterial: sourceAchievementFingerprintMaterial,
            catalogMaterial:
                LaunchCatalogTransitionV1ToV2
                    .sourcePersistedFingerprintMaterial,
            canonicalPayloadMaterial:
                sourceCanonicalPayloadFingerprintMaterial
        )
    }

    static func targetScope(
        for configuration: ProductionCloudWriteConfiguration
    ) -> CloudReplicaScopeFingerprint {
        CloudReplicaScopeFingerprint.make(for: configuration)
    }
}

/// Process-local state is keyed by the physical authority directory and lock
/// file rather than their lexical paths. Symlink and case aliases therefore
/// share issuance history and one live network-attempt slot.
fileprivate struct CloudReplicaPhysicalAuthorityIdentityV1:
    Equatable,
    Hashable,
    Sendable
{
    let directoryDevice: UInt64
    let directoryInode: UInt64
    let lockDevice: UInt64
    let lockInode: UInt64
}

fileprivate final class CloudReplicaInitialBootstrapAttemptTokenV1:
    @unchecked Sendable
{}

fileprivate final class CloudReplicaInitialBootstrapProcessAuthorityV1:
    @unchecked Sendable
{
    typealias ReservationUUIDFactory = @Sendable () -> UUID
    private static let zeroUUID = UUID(
        uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    )

    private struct WeakAttemptToken {
        weak var value: CloudReplicaInitialBootstrapAttemptTokenV1?
    }

    let accountID: CloudAccountID
    let physicalIdentity: CloudReplicaPhysicalAuthorityIdentityV1
    private let reservationUUIDFactory: ReservationUUIDFactory
    private let maximumIssuedReservationCount: Int
    private let lock = NSLock()
    private var issuedReservationIDs: Set<UUID> = []
    private var liveAttempt: WeakAttemptToken?

    init(
        accountID: CloudAccountID,
        physicalIdentity: CloudReplicaPhysicalAuthorityIdentityV1,
        reservationUUIDFactory: @escaping ReservationUUIDFactory,
        maximumIssuedReservationCount: Int
    ) {
        precondition(maximumIssuedReservationCount > 0)
        self.accountID = accountID
        self.physicalIdentity = physicalIdentity
        self.reservationUUIDFactory = reservationUUIDFactory
        self.maximumIssuedReservationCount = maximumIssuedReservationCount
    }

    func issueReservationID() throws -> UUID {
        lock.lock()
        defer { lock.unlock() }
        guard issuedReservationIDs.count < maximumIssuedReservationCount else {
            throw CloudReplicaCheckpointStoreError
                .initialBootstrapUnavailable
        }
        let reservationID = reservationUUIDFactory()
        guard reservationID != Self.zeroUUID,
              !issuedReservationIDs.contains(reservationID) else {
            throw CloudReplicaCheckpointStoreError
                .initialBootstrapUnavailable
        }
        issuedReservationIDs.insert(reservationID)
        return reservationID
    }

    func adoptDurableReservationID(_ reservationID: UUID) throws {
        guard reservationID != Self.zeroUUID else {
            throw CloudReplicaCheckpointStoreError.invalidCheckpoint
        }
        lock.lock()
        defer { lock.unlock() }
        if issuedReservationIDs.contains(reservationID) { return }
        guard issuedReservationIDs.count < maximumIssuedReservationCount else {
            throw CloudReplicaCheckpointStoreError
                .initialBootstrapUnavailable
        }
        issuedReservationIDs.insert(reservationID)
    }

    func claimAttempt(
        reservationID: UUID,
        attemptSequence: UInt64
    ) throws -> CloudReplicaInitialBootstrapNetworkAttemptLeaseV1 {
        lock.lock()
        defer { lock.unlock() }
        pruneReleasedAttempts()
        guard attemptSequence > 0,
              issuedReservationIDs.contains(reservationID),
              liveAttempt?.value == nil else {
            throw CloudReplicaCheckpointStoreError
                .initialBootstrapUnavailable
        }
        let token = CloudReplicaInitialBootstrapAttemptTokenV1()
        liveAttempt = WeakAttemptToken(
            value: token
        )
        return CloudReplicaInitialBootstrapNetworkAttemptLeaseV1(
            processAuthority: self,
            token: token,
            reservationID: reservationID,
            attemptSequence: attemptSequence
        )
    }

    func isCurrent(
        token: CloudReplicaInitialBootstrapAttemptTokenV1,
        reservationID: UUID
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        pruneReleasedAttempts()
        _ = reservationID
        return liveAttempt?.value === token
    }

    func releaseAttempt(
        token: CloudReplicaInitialBootstrapAttemptTokenV1,
        reservationID: UUID
    ) {
        lock.lock()
        defer { lock.unlock() }
        _ = reservationID
        guard liveAttempt?.value === token else {
            pruneReleasedAttempts()
            return
        }
        liveAttempt = nil
    }

    private func pruneReleasedAttempts() {
        if liveAttempt?.value == nil {
            liveAttempt = nil
        }
    }
}

fileprivate final class CloudReplicaInitialBootstrapNetworkAttemptLeaseV1:
    @unchecked Sendable
{
    let reservationID: UUID
    let attemptSequence: UInt64
    private let processAuthority:
        CloudReplicaInitialBootstrapProcessAuthorityV1
    private let token: CloudReplicaInitialBootstrapAttemptTokenV1

    init(
        processAuthority: CloudReplicaInitialBootstrapProcessAuthorityV1,
        token: CloudReplicaInitialBootstrapAttemptTokenV1,
        reservationID: UUID,
        attemptSequence: UInt64
    ) {
        self.processAuthority = processAuthority
        self.token = token
        self.reservationID = reservationID
        self.attemptSequence = attemptSequence
    }

    deinit {
        release()
    }

    func isCurrent() -> Bool {
        processAuthority.isCurrent(
            token: token,
            reservationID: reservationID
        )
    }

    func release() {
        processAuthority.releaseAttempt(
            token: token,
            reservationID: reservationID
        )
    }

    func authorizes(
        reservationID: UUID,
        attemptSequence: UInt64,
        processAuthority: CloudReplicaInitialBootstrapProcessAuthorityV1
    ) -> Bool {
        self.reservationID == reservationID
            && self.attemptSequence == attemptSequence
            && self.processAuthority === processAuthority
            && isCurrent()
    }
}

fileprivate final class CloudReplicaInitialBootstrapProcessAuthorityRegistryV1:
    @unchecked Sendable
{
    static let shared =
        CloudReplicaInitialBootstrapProcessAuthorityRegistryV1()

    private struct WeakProcessAuthority {
        weak var value: CloudReplicaInitialBootstrapProcessAuthorityV1?
    }

    private let lock = NSLock()
    private var authorityByPhysicalDirectory:
        [CloudReplicaPhysicalAuthorityIdentityV1: WeakProcessAuthority] = [:]

    func processAuthority(
        for physicalIdentity: CloudReplicaPhysicalAuthorityIdentityV1,
        accountID: CloudAccountID,
        reservationUUIDFactory: @escaping
            CloudReplicaInitialBootstrapProcessAuthorityV1
                .ReservationUUIDFactory,
        maximumIssuedReservationCount: Int
    ) throws -> CloudReplicaInitialBootstrapProcessAuthorityV1 {
        lock.lock()
        defer { lock.unlock() }
        authorityByPhysicalDirectory = authorityByPhysicalDirectory.filter {
            $0.value.value != nil
        }
        if let existing = authorityByPhysicalDirectory[physicalIdentity]?.value {
            guard existing.accountID == accountID else {
                throw CloudReplicaCheckpointStoreError.invalidCheckpoint
            }
            return existing
        }
        let created = CloudReplicaInitialBootstrapProcessAuthorityV1(
            accountID: accountID,
            physicalIdentity: physicalIdentity,
            reservationUUIDFactory: reservationUUIDFactory,
            maximumIssuedReservationCount: maximumIssuedReservationCount
        )
        authorityByPhysicalDirectory[physicalIdentity] = WeakProcessAuthority(
            value: created
        )
        return created
    }
}

/// A shared, single-use gate retained by every copy of one store-issued
/// context. It marks itself consumed before awaiting the durable reservation,
/// so concurrent calls, cancellation, and ambiguous failures cannot reuse the
/// same context for a second network attempt.
fileprivate actor CloudReplicaInitialBootstrapFetchPermitV1 {
    typealias DurableReservation = @Sendable () async throws
        -> CloudReplicaInitialBootstrapNetworkAttemptLeaseV1

    fileprivate let reservationID: UUID
    fileprivate let attemptSequence: UInt64
    fileprivate let networkPolicy: CloudReplicaInitialBootstrapNetworkPolicyV1
    private let reserveDurably: DurableReservation
    private var isConsumed = false

    fileprivate init(
        reservationID: UUID,
        attemptSequence: UInt64,
        networkPolicy: CloudReplicaInitialBootstrapNetworkPolicyV1,
        reserveDurably: @escaping DurableReservation
    ) {
        self.reservationID = reservationID
        self.attemptSequence = attemptSequence
        self.networkPolicy = networkPolicy
        self.reserveDurably = reserveDurably
    }

    fileprivate func consumeAndReserveBeforeNetwork()
        async throws -> CloudReplicaInitialBootstrapReservedFetchV1
    {
        guard !isConsumed else {
            throw CloudReplicaCheckpointStoreError.initialBootstrapUnavailable
        }
        isConsumed = true
        let attemptLease = try await reserveDurably()
        return CloudReplicaInitialBootstrapReservedFetchV1(
            reservationID: reservationID,
            attemptSequence: attemptSequence,
            networkPolicy: networkPolicy,
            attemptLease: attemptLease
        )
    }
}

enum CloudReplicaInitialBootstrapNetworkPolicyV1: Sendable {
    case mayCreateZoneOnFirstRequest
    case requireExistingZoneRecovery
}

/// Proof that one durable cross-store reservation completed before transport
/// admission. Its initializer is file-scoped and it never escapes the sealed
/// context's internally controlled fetch loop.
struct CloudReplicaInitialBootstrapReservedFetchV1: Sendable {
    let reservationID: UUID
    let attemptSequence: UInt64
    let networkPolicy: CloudReplicaInitialBootstrapNetworkPolicyV1
    fileprivate let attemptLease:
        CloudReplicaInitialBootstrapNetworkAttemptLeaseV1

    fileprivate init(
        reservationID: UUID,
        attemptSequence: UInt64,
        networkPolicy: CloudReplicaInitialBootstrapNetworkPolicyV1,
        attemptLease: CloudReplicaInitialBootstrapNetworkAttemptLeaseV1
    ) {
        self.reservationID = reservationID
        self.attemptSequence = attemptSequence
        self.networkPolicy = networkPolicy
        self.attemptLease = attemptLease
    }
}

/// A configuration-derived change-fetch capability for checkpoint publication.
/// Release callers can obtain one only by supplying the complete validated
/// cloud-write configuration; they cannot pair an asserted replica scope with
/// an unrelated transport. The raw transport rejects zone creation; only the
/// sealed publication context below can present its opaque creation permit.
struct CloudReplicaScopedChangeFetcherV1: Sendable {
    let configurationScopeFingerprint: CloudReplicaScopeFingerprint
    private let changeFetcher: any CloudSyncChangeFetching
    private let initialBootstrapFetch: @Sendable (
        CloudAccountID,
        CloudChangeCursor?,
        CloudReplicaInitialBootstrapReservedFetchV1
    ) async throws -> CloudRecordChangePage

    private init(
        configuration: ProductionCloudWriteConfiguration,
        changeFetcher: any CloudSyncChangeFetching,
        initialBootstrapFetch: @escaping @Sendable (
            CloudAccountID,
            CloudChangeCursor?,
            CloudReplicaInitialBootstrapReservedFetchV1
        ) async throws -> CloudRecordChangePage
    ) {
        configurationScopeFingerprint = CloudReplicaScopeFingerprint.make(
            for: configuration
        )
        self.changeFetcher = changeFetcher
        self.initialBootstrapFetch = initialBootstrapFetch
    }

    static func live(
        configuration: ProductionCloudWriteConfiguration
    ) -> CloudReplicaScopedChangeFetcherV1 {
        let transport = CloudKitCloudSyncTransport.live(
            configuration: configuration.transport
        )
        return CloudReplicaScopedChangeFetcherV1(
            configuration: configuration,
            changeFetcher: transport,
            initialBootstrapFetch: { accountID, cursor, authorization in
                try await transport.recordInitialBootstrapChanges(
                    accountID: accountID,
                    after: cursor,
                    authorization: authorization
                )
            }
        )
    }

    #if DEBUG
    /// Test seams still derive their scope from the complete production
    /// configuration. Only the network behavior may be replaced.
    static func _testOnly(
        configuration: ProductionCloudWriteConfiguration,
        changeFetcher: any CloudSyncChangeFetching
    ) -> CloudReplicaScopedChangeFetcherV1 {
        CloudReplicaScopedChangeFetcherV1(
            configuration: configuration,
            changeFetcher: changeFetcher,
            initialBootstrapFetch: { accountID, cursor, authorization in
                let zonePreparation: CloudZonePreparationPolicy
                switch authorization.networkPolicy {
                case .mayCreateZoneOnFirstRequest where cursor == nil:
                    zonePreparation = .createIfMissingForInitialBootstrap
                case .mayCreateZoneOnFirstRequest,
                     .requireExistingZoneRecovery:
                    zonePreparation = .requireExisting
                }
                return try await changeFetcher.recordChanges(
                    accountID: accountID,
                    after: cursor,
                    zonePreparation: zonePreparation
                )
            }
        )
    }
    #endif

    fileprivate func recordChangesRequiringExistingZone(
        accountID: CloudAccountID,
        after cursor: CloudChangeCursor?
    ) async throws -> CloudRecordChangePage {
        try await changeFetcher.recordChanges(
            accountID: accountID,
            after: cursor,
            zonePreparation: .requireExisting
        )
    }

    /// Initial bootstrap owns the only Release path that may create a zone.
    /// A nil cursor can occur only on its first internally controlled request;
    /// every continuation page must observe an already-existing zone.
    fileprivate func recordChangesForInitialBootstrap(
        accountID: CloudAccountID,
        after cursor: CloudChangeCursor?,
        authorization: CloudReplicaInitialBootstrapReservedFetchV1
    ) async throws -> CloudRecordChangePage {
        try await initialBootstrapFetch(accountID, cursor, authorization)
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

    /// Reconstructs a complete replica from a nil-cursor CloudKit full-snapshot
    /// fetch after the local cache was lost while durable accepted history
    /// remains. The caller must fetch with `.requireExisting`; this is never an
    /// initial-bootstrap create path.
    fileprivate init(
        reconstructingFullSnapshotFrom acceptedHistory: CloudReplicaAcceptedHistoryV1,
        limits: CloudReplicaResourceLimits = .production
    ) {
        accountID = acceptedHistory.accountID
        configurationScopeFingerprint =
            acceptedHistory.configurationScopeFingerprint
        replicaEpoch = acceptedHistory.replicaEpoch
        startingGeneration = acceptedHistory.generation
        self.limits = limits
        candidate = Candidate(
            cursor: nil,
            recordsByLogicalID: [:],
            providerLocatorByLogicalID: [:],
            logicalIDByProviderLocator: [:],
            tombstonesByProviderLocator: [:]
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

/// Durable accepted-watermark evidence minted only by the checkpoint store.
/// Possession can authorize creation of a require-existing fetch context, but
/// does not itself prove that any CloudKit fetch has occurred.
struct CloudReplicaAcceptedHistoryV1: Equatable, Sendable {
    let accountID: CloudAccountID
    let configurationScopeFingerprint: CloudReplicaScopeFingerprint
    let replicaEpoch: UUID
    let generation: UInt64
    let checkpointDigest: Data

    fileprivate init(
        accountID: CloudAccountID,
        configurationScopeFingerprint: CloudReplicaScopeFingerprint,
        replicaEpoch: UUID,
        generation: UInt64,
        checkpointDigest: Data
    ) {
        self.accountID = accountID
        self.configurationScopeFingerprint = configurationScopeFingerprint
        self.replicaEpoch = replicaEpoch
        self.generation = generation
        self.checkpointDigest = checkpointDigest
    }
}

/// A sealed capability for the first complete replica publication in one exact
/// account generation. The checkpoint store issues it only after recovering
/// local state and proving that the active epoch has no accepted checkpoint,
/// pending publication, or remaining checkpoint evidence.
struct CloudReplicaInitialBootstrapPublicationContextV1: Sendable {
    fileprivate let generationToken: AccountGenerationToken
    fileprivate let accountID: CloudAccountID
    fileprivate let configurationScopeFingerprint: CloudReplicaScopeFingerprint
    fileprivate let replicaEpoch: UUID
    fileprivate let limits: CloudReplicaResourceLimits
    fileprivate let reservationID: UUID
    fileprivate let attemptSequence: UInt64
    private let processAuthority:
        CloudReplicaInitialBootstrapProcessAuthorityV1
    private let zoneCreationPermit: CloudReplicaInitialBootstrapFetchPermitV1

    fileprivate init(
        generationToken: AccountGenerationToken,
        accountID: CloudAccountID,
        configurationScopeFingerprint: CloudReplicaScopeFingerprint,
        replicaEpoch: UUID,
        limits: CloudReplicaResourceLimits,
        reservationID: UUID,
        attemptSequence: UInt64,
        processAuthority:
            CloudReplicaInitialBootstrapProcessAuthorityV1,
        zoneCreationPermit: CloudReplicaInitialBootstrapFetchPermitV1
    ) {
        self.generationToken = generationToken
        self.accountID = accountID
        self.configurationScopeFingerprint = configurationScopeFingerprint
        self.replicaEpoch = replicaEpoch
        self.limits = limits
        self.reservationID = reservationID
        self.attemptSequence = attemptSequence
        self.processAuthority = processAuthority
        self.zoneCreationPermit = zoneCreationPermit
    }

    /// Fetches the complete generation-one replica. The first nil-cursor
    /// request may create the private zone; every continuation request requires
    /// that exact zone to keep existing. Neither cursor nor policy is exposed.
    func fetchCompleteSnapshot(
        using changeFetcher: CloudReplicaScopedChangeFetcherV1
    ) async throws -> CloudReplicaInitialBootstrapPublicationV1 {
        guard changeFetcher.configurationScopeFingerprint
            == configurationScopeFingerprint else {
            throw CloudReplicaCheckpointStoreError.configurationScopeMismatch
        }
        try Task.checkCancellation()
        let networkAuthorization = try await zoneCreationPermit
            .consumeAndReserveBeforeNetwork()

        var accumulator = CloudReplicaStagedAccumulator(
            accountID: accountID,
            configurationScopeFingerprint: configurationScopeFingerprint,
            replicaEpoch: replicaEpoch,
            limits: limits
        )
        var requestedAfterCursor: CloudChangeCursor?

        while true {
            if requestedAfterCursor != nil {
                try Task.checkCancellation()
            }
            let page = try await changeFetcher.recordChangesForInitialBootstrap(
                accountID: accountID,
                after: requestedAfterCursor,
                authorization: networkAuthorization
            )
            let fetchedPage = CloudReplicaFetchedPage(
                requestedAfterCursor: requestedAfterCursor,
                configurationScopeFingerprint: configurationScopeFingerprint,
                page: page
            )
            if let checkpoint = try accumulator.apply(fetchedPage) {
                return CloudReplicaInitialBootstrapPublicationV1(
                    checkpoint: checkpoint,
                    generationToken: generationToken,
                    accountID: accountID,
                    configurationScopeFingerprint:
                        configurationScopeFingerprint,
                    replicaEpoch: replicaEpoch,
                    reservationID: networkAuthorization.reservationID,
                    attemptSequence: networkAuthorization.attemptSequence,
                    attemptLease: networkAuthorization.attemptLease
                )
            }
            requestedAfterCursor = page.nextCursor
        }
    }

}

/// The only Release-visible value accepted by generation-one checkpoint
/// publication. Its initializer is sealed to the fixed-policy context above.
struct CloudReplicaInitialBootstrapPublicationV1: Sendable {
    let checkpoint: CloudReplicaCheckpointV1
    fileprivate let generationToken: AccountGenerationToken
    fileprivate let accountID: CloudAccountID
    fileprivate let configurationScopeFingerprint: CloudReplicaScopeFingerprint
    fileprivate let replicaEpoch: UUID
    fileprivate let reservationID: UUID
    fileprivate let attemptSequence: UInt64
    fileprivate let attemptLease:
        CloudReplicaInitialBootstrapNetworkAttemptLeaseV1

    fileprivate init(
        checkpoint: CloudReplicaCheckpointV1,
        generationToken: AccountGenerationToken,
        accountID: CloudAccountID,
        configurationScopeFingerprint: CloudReplicaScopeFingerprint,
        replicaEpoch: UUID,
        reservationID: UUID,
        attemptSequence: UInt64,
        attemptLease: CloudReplicaInitialBootstrapNetworkAttemptLeaseV1
    ) {
        self.checkpoint = checkpoint
        self.generationToken = generationToken
        self.accountID = accountID
        self.configurationScopeFingerprint = configurationScopeFingerprint
        self.replicaEpoch = replicaEpoch
        self.reservationID = reservationID
        self.attemptSequence = attemptSequence
        self.attemptLease = attemptLease
    }

    /// Stable identity for future hydration composition. This is descriptive
    /// transition data, not profile-file mutation authority.
    var targetCheckpointIdentity: ProfileHydrationCheckpointIdentityV1 {
        ProfileHydrationCheckpointIdentityV1(checkpoint: checkpoint)
    }

    #if DEBUG
    /// Lets invariant tests replace only checkpoint bytes while retaining the
    /// genuine post-fetch live attempt lease.
    func _testOnlyReplacingCheckpoint(
        _ checkpoint: CloudReplicaCheckpointV1
    ) -> CloudReplicaInitialBootstrapPublicationV1 {
        CloudReplicaInitialBootstrapPublicationV1(
            checkpoint: checkpoint,
            generationToken: generationToken,
            accountID: accountID,
            configurationScopeFingerprint: configurationScopeFingerprint,
            replicaEpoch: replicaEpoch,
            reservationID: reservationID,
            attemptSequence: attemptSequence,
            attemptLease: attemptLease
        )
    }
    #endif
}

/// A sealed, process-local recovery capability for one exact accepted cloud
/// history and account generation. The checkpoint store is the only issuer.
/// Fetching is intentionally separate from issuance and durable commit. The
/// API is designed for callers to leave their bounded generation-gate callback
/// before fetching; this value cannot observe or enforce callback lifetime.
struct CloudReplicaRequireExistingReconstructionContextV1: Sendable {
    fileprivate let generationToken: AccountGenerationToken
    fileprivate let acceptedHistory: CloudReplicaAcceptedHistoryV1
    fileprivate let limits: CloudReplicaResourceLimits

    fileprivate init(
        generationToken: AccountGenerationToken,
        acceptedHistory: CloudReplicaAcceptedHistoryV1,
        limits: CloudReplicaResourceLimits
    ) {
        self.generationToken = generationToken
        self.acceptedHistory = acceptedHistory
        self.limits = limits
    }

    /// Fetches one complete nil-cursor snapshot without ever granting zone
    /// creation authority. The request cursor is owned by this loop: callers
    /// cannot start from a stale cursor, skip a page, or change preparation
    /// policy between pages. Transport, cancellation, and accumulator errors
    /// intentionally emerge unchanged.
    func fetchCompleteSnapshot(
        using changeFetcher: CloudReplicaScopedChangeFetcherV1
    ) async throws -> CloudReplicaReconstructedFullSnapshotV1 {
        guard changeFetcher.configurationScopeFingerprint
            == acceptedHistory.configurationScopeFingerprint else {
            throw CloudReplicaCheckpointStoreError.configurationScopeMismatch
        }

        var accumulator = CloudReplicaStagedAccumulator(
            reconstructingFullSnapshotFrom: acceptedHistory,
            limits: limits
        )
        var requestedAfterCursor: CloudChangeCursor?

        while true {
            try Task.checkCancellation()
            let page = try await changeFetcher.recordChangesRequiringExistingZone(
                accountID: acceptedHistory.accountID,
                after: requestedAfterCursor
            )
            let fetchedPage = CloudReplicaFetchedPage(
                requestedAfterCursor: requestedAfterCursor,
                configurationScopeFingerprint:
                    acceptedHistory.configurationScopeFingerprint,
                page: page
            )
            if let checkpoint = try accumulator.apply(fetchedPage) {
                return CloudReplicaReconstructedFullSnapshotV1(
                    checkpoint: checkpoint,
                    generationToken: generationToken,
                    acceptedHistory: acceptedHistory
                )
            }
            requestedAfterCursor = page.nextCursor
        }
    }
}

/// The only value accepted by cache-loss reconstruction publication. Its
/// initializer is sealed to the scoped production wrapper above, which requests
/// `.requireExisting`; raw change pages and manually assembled checkpoints
/// cannot be presented through this publication API.
struct CloudReplicaReconstructedFullSnapshotV1: Sendable {
    let checkpoint: CloudReplicaCheckpointV1
    fileprivate let generationToken: AccountGenerationToken
    fileprivate let acceptedHistory: CloudReplicaAcceptedHistoryV1

    fileprivate init(
        checkpoint: CloudReplicaCheckpointV1,
        generationToken: AccountGenerationToken,
        acceptedHistory: CloudReplicaAcceptedHistoryV1
    ) {
        self.checkpoint = checkpoint
        self.generationToken = generationToken
        self.acceptedHistory = acceptedHistory
    }
}

/// A sealed capability for advancing one exact, usable accepted checkpoint.
/// The predecessor and account generation are captured while both durable
/// checkpoint authority and the canonical generation lease are current.
struct CloudReplicaIncrementalOrdinaryPublicationContextV1: Sendable {
    fileprivate let generationToken: AccountGenerationToken
    fileprivate let predecessor: CloudReplicaCheckpointV1
    fileprivate let predecessorHistory: CloudReplicaAcceptedHistoryV1
    fileprivate let limits: CloudReplicaResourceLimits

    fileprivate init(
        generationToken: AccountGenerationToken,
        predecessor: CloudReplicaCheckpointV1,
        predecessorHistory: CloudReplicaAcceptedHistoryV1,
        limits: CloudReplicaResourceLimits
    ) {
        self.generationToken = generationToken
        self.predecessor = predecessor
        self.predecessorHistory = predecessorHistory
        self.limits = limits
    }

    /// Fetches every incremental page after the sealed predecessor. The scoped
    /// wrapper derives its scope from complete production configuration and
    /// always requests an existing zone.
    func fetchCompleteChanges(
        using changeFetcher: CloudReplicaScopedChangeFetcherV1
    ) async throws -> CloudReplicaOrdinaryPublicationV1 {
        guard changeFetcher.configurationScopeFingerprint
            == predecessorHistory.configurationScopeFingerprint else {
            throw CloudReplicaCheckpointStoreError.configurationScopeMismatch
        }

        var accumulator = try CloudReplicaStagedAccumulator(
            accountID: predecessorHistory.accountID,
            configurationScopeFingerprint:
                predecessorHistory.configurationScopeFingerprint,
            checkpoint: predecessor,
            limits: limits
        )
        var requestedAfterCursor: CloudChangeCursor? = predecessor.finalCursor

        while true {
            try Task.checkCancellation()
            let page = try await changeFetcher.recordChangesRequiringExistingZone(
                accountID: predecessorHistory.accountID,
                after: requestedAfterCursor
            )
            let fetchedPage = CloudReplicaFetchedPage(
                requestedAfterCursor: requestedAfterCursor,
                configurationScopeFingerprint:
                    predecessorHistory.configurationScopeFingerprint,
                page: page
            )
            if let checkpoint = try accumulator.apply(fetchedPage) {
                return CloudReplicaOrdinaryPublicationV1(
                    checkpoint: checkpoint,
                    generationToken: generationToken,
                    predecessorHistory: predecessorHistory,
                    predecessorCheckpointIdentity:
                        ProfileHydrationCheckpointIdentityV1(
                            checkpoint: predecessor
                        )
                )
            }
            requestedAfterCursor = page.nextCursor
        }
    }
}

/// The only Release-visible value accepted by ordinary incremental
/// publication. It is branded with the exact generation and predecessor that
/// authorized its fixed-policy fetch.
struct CloudReplicaOrdinaryPublicationV1: Sendable {
    let checkpoint: CloudReplicaCheckpointV1
    let predecessorCheckpointIdentity: ProfileHydrationCheckpointIdentityV1
    fileprivate let generationToken: AccountGenerationToken
    fileprivate let predecessorHistory: CloudReplicaAcceptedHistoryV1

    fileprivate init(
        checkpoint: CloudReplicaCheckpointV1,
        generationToken: AccountGenerationToken,
        predecessorHistory: CloudReplicaAcceptedHistoryV1,
        predecessorCheckpointIdentity: ProfileHydrationCheckpointIdentityV1
    ) {
        self.checkpoint = checkpoint
        self.generationToken = generationToken
        self.predecessorHistory = predecessorHistory
        self.predecessorCheckpointIdentity = predecessorCheckpointIdentity
    }

    /// Stable identity for future hydration composition. Publication still
    /// requires the store's borrowed freshness and generation authorities.
    var targetCheckpointIdentity: ProfileHydrationCheckpointIdentityV1 {
        ProfileHydrationCheckpointIdentityV1(checkpoint: checkpoint)
    }
}

struct CloudReplicaEpochResumeResult: Equatable, Sendable {
    let replicaEpoch: UUID
    let acceptedHistory: CloudReplicaAcceptedHistoryV1?
    let hasDurableCheckpointIntent: Bool

    var hasAcceptedCheckpoint: Bool {
        acceptedHistory != nil
    }
}

struct CloudReplicaActiveEpochAuthorityV1: Equatable, Sendable {
    let replicaEpoch: UUID
    let configurationScopeFingerprint: CloudReplicaScopeFingerprint
}

enum CloudReplicaCheckpointObservationStateV1: Equatable, Sendable {
    case absent
    case checkpoint(ProfileHydrationCheckpointIdentityV1)
}

struct CloudReplicaCheckpointObservationV1: Equatable, Sendable {
    let accountID: CloudAccountID
    let configurationScopeFingerprint: CloudReplicaScopeFingerprint
    let replicaEpoch: UUID
    let state: CloudReplicaCheckpointObservationStateV1

    fileprivate init(
        accountID: CloudAccountID,
        configurationScopeFingerprint: CloudReplicaScopeFingerprint,
        replicaEpoch: UUID,
        state: CloudReplicaCheckpointObservationStateV1
    ) {
        self.accountID = accountID
        self.configurationScopeFingerprint = configurationScopeFingerprint
        self.replicaEpoch = replicaEpoch
        self.state = state
    }
}

/// Scoped mutation authority minted only while the checkpoint store holds the
/// exact account's durable authority lock. The lease cannot be copied, sent,
/// persisted, or returned from its synchronous callback. Raw checkpoint
/// observations remain useful for diagnostics and relationship inspection but
/// are not profile-file mutation authority.
fileprivate final class CloudReplicaCheckpointLeaseNonSendableMarker {}

struct CloudReplicaCheckpointFreshnessLeaseV1: ~Copyable {
    fileprivate let observation: CloudReplicaCheckpointObservationV1
    private let nonSendableMarker: CloudReplicaCheckpointLeaseNonSendableMarker

    fileprivate init(observation: CloudReplicaCheckpointObservationV1) {
        self.observation = observation
        nonSendableMarker = CloudReplicaCheckpointLeaseNonSendableMarker()
    }

    func relationship(
        to journal: ProfileHydrationJournalV1
    ) -> ProfileHydrationCheckpointRelationshipV1 {
        journal.checkpointRelationship(to: observation)
    }
}

enum CloudReplicaCheckpointStoreError: Error, Equatable, Sendable {
    case invalidCheckpoint
    case encodingFailure
    case ioFailure
    /// A rename or removal completed, but synchronizing the affected directory
    /// failed. Durable state must be reread before the caller decides whether
    /// to retry or advance.
    case durabilityOutcomeUnknown
    case replicaEpochNotActive
    case replicaEpochRevoked
    case replicaEpochMismatch
    case configurationScopeMismatch
    case checkpointPublicationPending
    case accountGenerationAuthorityNotBound
    case accountGenerationAuthorityMismatch
    case accountGenerationMismatch
    case initialBootstrapUnavailable
    case acceptedHistoryUnavailable
    case acceptedHistoryMismatch
    case acceptedCheckpointStillAvailable
    case staleGeneration
    case generationGap
    case generationCollision
}

protocol CloudReplicaCheckpointStoring: Sendable {
    func activate(
        replicaEpoch: UUID,
        configurationScopeFingerprint: CloudReplicaScopeFingerprint,
        for accountID: CloudAccountID
    ) async throws
    func resumeActiveReplicaEpoch(
        for accountID: CloudAccountID,
        configurationScopeFingerprint: CloudReplicaScopeFingerprint
    ) async throws -> CloudReplicaEpochResumeResult?
    func activeReplicaAuthority(
        for accountID: CloudAccountID
    ) async throws -> CloudReplicaActiveEpochAuthorityV1?

    func load(
        for accountID: CloudAccountID,
        configurationScopeFingerprint: CloudReplicaScopeFingerprint,
        at date: Date
    ) async throws -> CloudReplicaCheckpointLoadResult

    func observeCurrentCheckpoint(
        for accountID: CloudAccountID,
        configurationScopeFingerprint: CloudReplicaScopeFingerprint,
        replicaEpoch: UUID,
        at date: Date
    ) async throws -> CloudReplicaCheckpointObservationV1

    func withCurrentCheckpointLease<Output: Sendable>(
        generationLease: borrowing AccountGenerationCommitLease,
        at date: Date,
        perform: @Sendable (
            borrowing CloudReplicaCheckpointFreshnessLeaseV1
        ) throws -> Output
    ) async throws -> Output

    func beginInitialBootstrapPublication(
        generationLease: borrowing AccountGenerationCommitLease,
        at date: Date
    ) async throws -> CloudReplicaInitialBootstrapPublicationContextV1

    func saveInitialBootstrapPublication(
        _ publication: CloudReplicaInitialBootstrapPublicationV1,
        generationLease: borrowing AccountGenerationCommitLease,
        at date: Date
    ) async throws

    func beginRequireExistingFullSnapshotReconstruction(
        generationLease: borrowing AccountGenerationCommitLease,
        at date: Date
    ) async throws -> CloudReplicaRequireExistingReconstructionContextV1

    func beginIncrementalOrdinaryPublication(
        generationLease: borrowing AccountGenerationCommitLease,
        at date: Date
    ) async throws -> CloudReplicaIncrementalOrdinaryPublicationContextV1

    func saveOrdinaryPublication(
        _ publication: CloudReplicaOrdinaryPublicationV1,
        generationLease: borrowing AccountGenerationCommitLease,
        at date: Date
    ) async throws
    func saveReconstructedFullSnapshot(
        _ reconstruction: CloudReplicaReconstructedFullSnapshotV1,
        generationLease: borrowing AccountGenerationCommitLease,
        at date: Date
    ) async throws
    func remove(for accountID: CloudAccountID, revoking replicaEpoch: UUID) async throws
}

enum CloudReplicaCheckpointFileItemStatus: Equatable, Sendable {
    case missing
    case present
}

protocol CloudReplicaCheckpointFileSystem: Sendable {
    func createDirectory(at url: URL) throws
    func itemStatus(at url: URL) throws -> CloudReplicaCheckpointFileItemStatus
    func reconcileDurableItem(
        at url: URL
    ) throws -> CloudReplicaCheckpointFileItemStatus
    func fileSize(at url: URL) throws -> Int
    func read(from url: URL) throws -> Data
    func writeAtomically(_ data: Data, to url: URL) throws
    func moveItem(at sourceURL: URL, to destinationURL: URL) throws
    func removeItem(at url: URL) throws
    func withExclusiveLock(at url: URL, perform: () throws -> Void) throws
}

struct FoundationCloudReplicaCheckpointFileSystem: CloudReplicaCheckpointFileSystem {
    typealias RecursiveDirectoryRemoval = @Sendable (URL) throws -> Void

    private let recursivelyRemoveDirectory: RecursiveDirectoryRemoval
    private let durabilityBoundaryURL: URL

    init(
        recursivelyRemoveDirectory: @escaping RecursiveDirectoryRemoval = { url in
            try FileManager.default.removeItem(at: url)
        },
        durabilityBoundaryURL: URL = URL(
            fileURLWithPath: NSHomeDirectory(),
            isDirectory: true
        )
    ) {
        self.recursivelyRemoveDirectory = recursivelyRemoveDirectory
        self.durabilityBoundaryURL = durabilityBoundaryURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
    }

    func createDirectory(at url: URL) throws {
        let standardizedURL = try standardizedURLWithinDurabilityBoundary(url)
        let creationWasNeeded = try itemStatus(at: standardizedURL) == .missing
        do {
            try FileManager.default.createDirectory(
                at: standardizedURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: NSNumber(value: Int16(0o700))]
            )
            guard try reconcileDurableItem(at: standardizedURL) == .present else {
                throw CloudReplicaCheckpointStoreError.durabilityOutcomeUnknown
            }
        } catch let error as CloudReplicaCheckpointStoreError {
            if creationWasNeeded {
                throw CloudReplicaCheckpointStoreError.durabilityOutcomeUnknown
            }
            throw error
        } catch {
            if creationWasNeeded {
                throw CloudReplicaCheckpointStoreError.durabilityOutcomeUnknown
            }
            throw CloudReplicaCheckpointStoreError.ioFailure
        }
    }

    func itemStatus(at url: URL) throws -> CloudReplicaCheckpointFileItemStatus {
        var metadata = stat()
        let result = url.path.withCString { Darwin.lstat($0, &metadata) }
        if result == 0 {
            return .present
        }
        if errno == ENOENT {
            return .missing
        }
        throw CloudReplicaCheckpointStoreError.ioFailure
    }

    func reconcileDurableItem(
        at url: URL
    ) throws -> CloudReplicaCheckpointFileItemStatus {
        let standardizedURL = try standardizedURLWithinDurabilityBoundary(url)
        switch try itemStatus(at: standardizedURL) {
        case .present:
            try synchronizeItem(standardizedURL)
            if standardizedURL != durabilityBoundaryURL {
                try synchronizeExistingDirectoryChain(
                    startingAt: standardizedURL.deletingLastPathComponent()
                )
            }
            guard try itemStatus(at: standardizedURL) == .present else {
                throw CloudReplicaCheckpointStoreError.durabilityOutcomeUnknown
            }
            return .present
        case .missing:
            guard standardizedURL != durabilityBoundaryURL else {
                throw CloudReplicaCheckpointStoreError.ioFailure
            }
            var nearestExistingAncestor = standardizedURL.deletingLastPathComponent()
            while try itemStatus(at: nearestExistingAncestor) == .missing {
                guard nearestExistingAncestor != durabilityBoundaryURL else {
                    throw CloudReplicaCheckpointStoreError.ioFailure
                }
                let parent = nearestExistingAncestor.deletingLastPathComponent()
                guard parent != nearestExistingAncestor else {
                    throw CloudReplicaCheckpointStoreError.ioFailure
                }
                nearestExistingAncestor = parent
            }
            try synchronizeExistingDirectoryChain(
                startingAt: nearestExistingAncestor
            )
            guard try itemStatus(at: standardizedURL) == .missing else {
                throw CloudReplicaCheckpointStoreError.durabilityOutcomeUnknown
            }
            return .missing
        }
    }

    func fileSize(at url: URL) throws -> Int {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard let size = attributes[.size] as? NSNumber,
                  size.int64Value >= 0,
                  UInt64(size.int64Value) <= UInt64(Int.max) else {
                throw CloudReplicaCheckpointStoreError.ioFailure
            }
            return Int(size.int64Value)
        } catch let error as CloudReplicaCheckpointStoreError {
            throw error
        } catch {
            throw CloudReplicaCheckpointStoreError.ioFailure
        }
    }

    func read(from url: URL) throws -> Data {
        do {
            return try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            throw CloudReplicaCheckpointStoreError.ioFailure
        }
    }

    func writeAtomically(_ data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try createDirectory(at: directory)
        let temporaryURL = directory.appendingPathComponent(
            ".pocket-vector-checkpoint-write.tmp",
            isDirectory: false
        )
        try removeItem(at: temporaryURL)
        var temporaryExists = false
        var destinationWasRenamed = false

        let descriptor = temporaryURL.path.withCString {
            Darwin.open($0, O_CREAT | O_EXCL | O_WRONLY, S_IRUSR | S_IWUSR)
        }
        guard descriptor >= 0 else {
            throw CloudReplicaCheckpointStoreError.ioFailure
        }
        temporaryExists = true
        var descriptorIsOpen = true
        defer {
            if descriptorIsOpen {
                _ = Darwin.close(descriptor)
            }
        }

        do {
            try writeAll(data, to: descriptor)
            try synchronizeFile(descriptor)
            guard Darwin.close(descriptor) == 0 else {
                descriptorIsOpen = false
                throw CloudReplicaCheckpointStoreError.ioFailure
            }
            descriptorIsOpen = false
            guard temporaryURL.path.withCString({ source in
                url.path.withCString { destination in
                    Darwin.rename(source, destination)
                }
            }) == 0 else {
                throw CloudReplicaCheckpointStoreError.ioFailure
            }
            temporaryExists = false
            destinationWasRenamed = true
            guard try reconcileDurableItem(at: url) == .present else {
                throw CloudReplicaCheckpointStoreError.durabilityOutcomeUnknown
            }
        } catch let error as CloudReplicaCheckpointStoreError {
            if destinationWasRenamed {
                throw CloudReplicaCheckpointStoreError.durabilityOutcomeUnknown
            }
            if temporaryExists {
                do {
                    try removeItem(at: temporaryURL)
                    temporaryExists = false
                } catch {
                    throw CloudReplicaCheckpointStoreError.durabilityOutcomeUnknown
                }
            }
            throw error
        } catch {
            if destinationWasRenamed {
                throw CloudReplicaCheckpointStoreError.durabilityOutcomeUnknown
            }
            if temporaryExists {
                do {
                    try removeItem(at: temporaryURL)
                    temporaryExists = false
                } catch {
                    throw CloudReplicaCheckpointStoreError.durabilityOutcomeUnknown
                }
            }
            throw CloudReplicaCheckpointStoreError.ioFailure
        }
    }

    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        let destinationDirectory = destinationURL.deletingLastPathComponent()
        try createDirectory(at: destinationDirectory)
        guard try reconcileDurableItem(at: sourceURL) == .present,
              try reconcileDurableItem(at: destinationURL) == .missing else {
            throw CloudReplicaCheckpointStoreError.ioFailure
        }
        var itemWasMoved = false
        do {
            let result = sourceURL.path.withCString { source in
                destinationURL.path.withCString { destination in
                    Darwin.rename(source, destination)
                }
            }
            guard result == 0 else {
                if errno == EXDEV {
                    throw CloudReplicaCheckpointStoreError.ioFailure
                }
                throw CloudReplicaCheckpointStoreError.ioFailure
            }
            itemWasMoved = true
            guard try reconcileDurableItem(at: destinationURL) == .present,
                  try reconcileDurableItem(at: sourceURL) == .missing else {
                throw CloudReplicaCheckpointStoreError.durabilityOutcomeUnknown
            }
        } catch let error as CloudReplicaCheckpointStoreError {
            if itemWasMoved {
                throw CloudReplicaCheckpointStoreError.durabilityOutcomeUnknown
            }
            throw error
        } catch {
            if itemWasMoved {
                throw CloudReplicaCheckpointStoreError.durabilityOutcomeUnknown
            }
            throw CloudReplicaCheckpointStoreError.ioFailure
        }
    }

    func removeItem(at url: URL) throws {
        guard try reconcileDurableItem(at: url) == .present else {
            try removeStaleRemovalTombstone(for: url)
            return
        }
        if try isDirectory(at: url) {
            try removeDirectory(at: url)
            return
        }
        var itemWasRemoved = false
        do {
            guard url.path.withCString({ Darwin.unlink($0) }) == 0 else {
                if errno == ENOENT {
                    guard try reconcileDurableItem(at: url) == .missing else {
                        throw CloudReplicaCheckpointStoreError.durabilityOutcomeUnknown
                    }
                    return
                }
                throw CloudReplicaCheckpointStoreError.ioFailure
            }
            itemWasRemoved = true
            guard try reconcileDurableItem(at: url) == .missing else {
                throw CloudReplicaCheckpointStoreError.durabilityOutcomeUnknown
            }
        } catch let error as CloudReplicaCheckpointStoreError {
            if itemWasRemoved {
                throw CloudReplicaCheckpointStoreError.durabilityOutcomeUnknown
            }
            throw error
        } catch {
            if itemWasRemoved {
                throw CloudReplicaCheckpointStoreError.durabilityOutcomeUnknown
            }
            throw CloudReplicaCheckpointStoreError.ioFailure
        }
    }

    func withExclusiveLock(at url: URL, perform: () throws -> Void) throws {
        try createDirectory(at: url.deletingLastPathComponent())
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

    private func writeAll(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            var offset = 0
            while offset < rawBuffer.count {
                let written = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    rawBuffer.count - offset
                )
                if written < 0, errno == EINTR {
                    continue
                }
                guard written > 0 else {
                    throw CloudReplicaCheckpointStoreError.ioFailure
                }
                offset += written
            }
        }
    }

    private func synchronizeFile(_ descriptor: Int32) throws {
        if Darwin.fcntl(descriptor, F_FULLFSYNC) == 0 {
            return
        }
        guard Darwin.fsync(descriptor) == 0 else {
            throw CloudReplicaCheckpointStoreError.ioFailure
        }
    }

    private func synchronizeItem(_ url: URL) throws {
        let descriptor = url.path.withCString {
            Darwin.open($0, O_RDONLY | O_NOFOLLOW)
        }
        guard descriptor >= 0 else {
            throw CloudReplicaCheckpointStoreError.ioFailure
        }
        defer { _ = Darwin.close(descriptor) }
        try synchronizeFile(descriptor)
    }

    private func standardizedURLWithinDurabilityBoundary(_ url: URL) throws -> URL {
        guard try itemStatus(at: durabilityBoundaryURL) == .present,
              try isDirectory(at: durabilityBoundaryURL) else {
            throw CloudReplicaCheckpointStoreError.ioFailure
        }
        let standardizedURL = url.resolvingSymlinksInPath().standardizedFileURL
        guard standardizedURL.pathComponents.starts(
            with: durabilityBoundaryURL.pathComponents
        ) else {
            throw CloudReplicaCheckpointStoreError.ioFailure
        }
        return standardizedURL
    }

    private func synchronizeExistingDirectoryChain(startingAt directory: URL) throws {
        var current = try standardizedURLWithinDurabilityBoundary(directory)
        while true {
            guard try itemStatus(at: current) == .present else {
                throw CloudReplicaCheckpointStoreError.ioFailure
            }
            try synchronizeItem(current)
            if current == durabilityBoundaryURL {
                return
            }
            let parent = current.deletingLastPathComponent()
            guard parent != current else {
                throw CloudReplicaCheckpointStoreError.ioFailure
            }
            current = parent
        }
    }

    private func isDirectory(at url: URL) throws -> Bool {
        var metadata = stat()
        guard url.path.withCString({ Darwin.lstat($0, &metadata) }) == 0 else {
            if errno == ENOENT { return false }
            throw CloudReplicaCheckpointStoreError.ioFailure
        }
        return metadata.st_mode & S_IFMT == S_IFDIR
    }

    private func removeDirectory(at url: URL) throws {
        let tombstone = removalTombstoneURL(for: url)
        try removeStaleRemovalTombstone(for: url)

        var directoryWasRenamed = false
        do {
            let result = url.path.withCString { source in
                tombstone.path.withCString { destination in
                    Darwin.rename(source, destination)
                }
            }
            guard result == 0 else {
                if errno == ENOENT,
                   try reconcileDurableItem(at: url) == .missing {
                    return
                }
                throw CloudReplicaCheckpointStoreError.ioFailure
            }
            directoryWasRenamed = true
            guard try reconcileDurableItem(at: tombstone) == .present,
                  try reconcileDurableItem(at: url) == .missing else {
                throw CloudReplicaCheckpointStoreError.durabilityOutcomeUnknown
            }
        } catch let error as CloudReplicaCheckpointStoreError {
            if directoryWasRenamed {
                throw CloudReplicaCheckpointStoreError.durabilityOutcomeUnknown
            }
            throw error
        } catch {
            if directoryWasRenamed {
                throw CloudReplicaCheckpointStoreError.durabilityOutcomeUnknown
            }
            throw CloudReplicaCheckpointStoreError.ioFailure
        }

        // The durable tombstone bounds crash residue to one fixed sibling. Its
        // recursive cleanup is opportunistic and never changes target absence.
        do {
            try recursivelyRemoveDirectory(tombstone)
            _ = try reconcileDurableItem(at: tombstone)
        } catch {
            // A later removal, including owner rotation's missing-target retry,
            // retries this fixed slot.
        }
    }

    private func removalTombstoneURL(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.standardizedFileURL.path.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return url.deletingLastPathComponent().appendingPathComponent(
            ".pocket-vector-checkpoint-remove-\(digest).tmp",
            isDirectory: true
        )
    }

    private func removeStaleRemovalTombstone(for url: URL) throws {
        let tombstone = removalTombstoneURL(for: url)
        guard try reconcileDurableItem(at: tombstone) == .present else { return }
        do {
            try recursivelyRemoveDirectory(tombstone)
            guard try reconcileDurableItem(at: tombstone) == .missing else {
                throw CloudReplicaCheckpointStoreError.durabilityOutcomeUnknown
            }
        } catch {
            throw CloudReplicaCheckpointStoreError.durabilityOutcomeUnknown
        }
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

        var acceptedHistory: CloudReplicaAcceptedHistoryV1 {
            CloudReplicaAcceptedHistoryV1(
                accountID: accountID,
                configurationScopeFingerprint: configurationScopeFingerprint,
                replicaEpoch: replicaEpoch,
                generation: generation,
                checkpointDigest: checkpointDigest
            )
        }

        func matches(_ acceptedHistory: CloudReplicaAcceptedHistoryV1) -> Bool {
            accountID == acceptedHistory.accountID
                && configurationScopeFingerprint
                    == acceptedHistory.configurationScopeFingerprint
                && replicaEpoch == acceptedHistory.replicaEpoch
                && generation == acceptedHistory.generation
                && checkpointDigest == acceptedHistory.checkpointDigest
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

    /// Durable single-use admission for generation-one network work. The
    /// before-network phase is safely replaceable because no transport call is
    /// allowed until the second phase is durable. Once network may have been
    /// invoked, recovery can only claim a new require-existing attempt.
    private struct InitialBootstrapReservationV1: Codable, Equatable {
        static let formatVersion = 1
        static let zeroUUID = UUID(
            uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        )

        enum Phase: String, Codable, Equatable {
            case reservedBeforeNetwork
            case networkMayHaveBeenInvoked
            case consumedByCheckpoint
        }

        let reservationID: UUID
        let activeAttemptSequence: UInt64
        let phase: Phase

        init(
            reservationID: UUID,
            activeAttemptSequence: UInt64,
            phase: Phase
        ) throws {
            self.reservationID = reservationID
            self.activeAttemptSequence = activeAttemptSequence
            self.phase = phase
            try validate()
        }

        private enum CodingKeys: String, CodingKey {
            case formatVersion
            case reservationID
            case activeAttemptSequence
            case phase
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            guard try container.decode(Int.self, forKey: .formatVersion)
                == Self.formatVersion else {
                throw CloudReplicaCheckpointValidationError
                    .unsupportedFormatVersion
            }
            reservationID = try container.decode(
                UUID.self,
                forKey: .reservationID
            )
            activeAttemptSequence = try container.decode(
                UInt64.self,
                forKey: .activeAttemptSequence
            )
            phase = try container.decode(Phase.self, forKey: .phase)
            try validate()
        }

        func encode(to encoder: any Encoder) throws {
            try validate()
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(Self.formatVersion, forKey: .formatVersion)
            try container.encode(reservationID, forKey: .reservationID)
            try container.encode(
                activeAttemptSequence,
                forKey: .activeAttemptSequence
            )
            try container.encode(phase, forKey: .phase)
        }

        func validate() throws {
            guard reservationID != Self.zeroUUID,
                  activeAttemptSequence > 0 else {
                throw CloudReplicaCheckpointStoreError.invalidCheckpoint
            }
        }

        func consumingByCheckpoint() throws -> Self {
            guard phase == .networkMayHaveBeenInvoked else {
                throw CloudReplicaCheckpointStoreError
                    .initialBootstrapUnavailable
            }
            return try Self(
                reservationID: reservationID,
                activeAttemptSequence: activeAttemptSequence,
                phase: .consumedByCheckpoint
            )
        }
    }

    /// A single fixed-size authority record owns the current replica epoch for
    /// an account. The bounded revoked-epoch filter has no false negatives;
    /// saturation can only reject a fresh epoch, never resurrect an old one.
    private struct ReplicaEpochAuthorityV2: Codable, Equatable {
        static let formatVersion = 3
        static let legacyFormatVersion = 2
        static let revokedEpochFilterByteCount = 32 * 1_024
        static let revokedEpochHashCount = 7

        enum State: String, Codable {
            case active
            case revoked
        }

        let accountID: CloudAccountID
        let replicaEpoch: UUID
        let configurationScopeFingerprint: CloudReplicaScopeFingerprint?
        let revision: UInt64
        let state: State
        let revokedEpochFilter: Data
        let checkpointHighWatermark: WatermarkV1?
        let pendingCheckpointHighWatermark: WatermarkV1?
        let initialBootstrapReservation: InitialBootstrapReservationV1?

        init(
            active replicaEpoch: UUID,
            configurationScopeFingerprint: CloudReplicaScopeFingerprint,
            for accountID: CloudAccountID
        ) {
            self.accountID = accountID
            self.replicaEpoch = replicaEpoch
            self.configurationScopeFingerprint = configurationScopeFingerprint
            revision = 1
            state = .active
            revokedEpochFilter = Data(
                repeating: 0,
                count: Self.revokedEpochFilterByteCount
            )
            checkpointHighWatermark = nil
            pendingCheckpointHighWatermark = nil
            initialBootstrapReservation = nil
        }

        init(revoked replicaEpoch: UUID, for accountID: CloudAccountID) {
            self.accountID = accountID
            self.replicaEpoch = replicaEpoch
            configurationScopeFingerprint = nil
            revision = 1
            state = .revoked
            var filter = Data(
                repeating: 0,
                count: Self.revokedEpochFilterByteCount
            )
            for position in Self.filterPositions(
                accountID: accountID,
                epoch: replicaEpoch
            ) {
                let byteIndex = filter.startIndex + position / 8
                filter[byteIndex] |= UInt8(1 << (position % 8))
            }
            revokedEpochFilter = filter
            checkpointHighWatermark = nil
            pendingCheckpointHighWatermark = nil
            initialBootstrapReservation = nil
        }

        private init(
            accountID: CloudAccountID,
            replicaEpoch: UUID,
            configurationScopeFingerprint: CloudReplicaScopeFingerprint?,
            revision: UInt64,
            state: State,
            revokedEpochFilter: Data,
            checkpointHighWatermark: WatermarkV1?,
            pendingCheckpointHighWatermark: WatermarkV1?,
            initialBootstrapReservation: InitialBootstrapReservationV1?
        ) {
            self.accountID = accountID
            self.replicaEpoch = replicaEpoch
            self.configurationScopeFingerprint = configurationScopeFingerprint
            self.revision = revision
            self.state = state
            self.revokedEpochFilter = revokedEpochFilter
            self.checkpointHighWatermark = checkpointHighWatermark
            self.pendingCheckpointHighWatermark = pendingCheckpointHighWatermark
            self.initialBootstrapReservation = initialBootstrapReservation
        }

        private enum CodingKeys: String, CodingKey {
            case formatVersion
            case accountID
            case replicaEpoch
            case configurationScopeFingerprint
            case revision
            case state
            case revokedEpochFilter
            case checkpointHighWatermark
            case pendingCheckpointHighWatermark
            case initialBootstrapReservation
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let decodedFormatVersion = try container.decode(
                Int.self,
                forKey: .formatVersion
            )
            guard decodedFormatVersion == Self.formatVersion
                    || decodedFormatVersion == Self.legacyFormatVersion else {
                throw CloudReplicaCheckpointValidationError.unsupportedFormatVersion
            }
            accountID = try container.decode(CloudAccountID.self, forKey: .accountID)
            replicaEpoch = try container.decode(UUID.self, forKey: .replicaEpoch)
            configurationScopeFingerprint = try container.decodeIfPresent(
                CloudReplicaScopeFingerprint.self,
                forKey: .configurationScopeFingerprint
            )
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
            initialBootstrapReservation = decodedFormatVersion
                == Self.legacyFormatVersion
                ? nil
                : try container.decodeIfPresent(
                    InitialBootstrapReservationV1.self,
                    forKey: .initialBootstrapReservation
                )
            try validate()
        }

        func encode(to encoder: any Encoder) throws {
            try validate()
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(Self.formatVersion, forKey: .formatVersion)
            try container.encode(accountID, forKey: .accountID)
            try container.encode(replicaEpoch, forKey: .replicaEpoch)
            try container.encodeIfPresent(
                configurationScopeFingerprint,
                forKey: .configurationScopeFingerprint
            )
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
            try container.encodeIfPresent(
                initialBootstrapReservation,
                forKey: .initialBootstrapReservation
            )
        }

        func validate() throws {
            guard !accountID.rawValue.isEmpty,
                  revision > 0,
                  revokedEpochFilter.count == Self.revokedEpochFilterByteCount else {
                throw CloudReplicaCheckpointStoreError.invalidCheckpoint
            }
            if let checkpointHighWatermark {
                guard let configurationScopeFingerprint,
                      checkpointHighWatermark.accountID == accountID,
                      checkpointHighWatermark.configurationScopeFingerprint
                        == configurationScopeFingerprint,
                      checkpointHighWatermark.replicaEpoch == replicaEpoch else {
                    throw CloudReplicaCheckpointStoreError.invalidCheckpoint
                }
            }
            if let pendingCheckpointHighWatermark {
                guard let configurationScopeFingerprint,
                      pendingCheckpointHighWatermark.accountID == accountID,
                      pendingCheckpointHighWatermark.configurationScopeFingerprint
                        == configurationScopeFingerprint,
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
            if let initialBootstrapReservation {
                try initialBootstrapReservation.validate()
                guard state == .active else {
                    throw CloudReplicaCheckpointStoreError.invalidCheckpoint
                }
                switch initialBootstrapReservation.phase {
                case .reservedBeforeNetwork:
                    guard checkpointHighWatermark == nil,
                          pendingCheckpointHighWatermark == nil else {
                        throw CloudReplicaCheckpointStoreError.invalidCheckpoint
                    }
                case .networkMayHaveBeenInvoked:
                    guard checkpointHighWatermark == nil else {
                        throw CloudReplicaCheckpointStoreError.invalidCheckpoint
                    }
                case .consumedByCheckpoint:
                    guard checkpointHighWatermark != nil else {
                        throw CloudReplicaCheckpointStoreError.invalidCheckpoint
                    }
                }
            }
            switch state {
            case .active:
                guard configurationScopeFingerprint != nil,
                      !containsRevoked(replicaEpoch) else {
                    throw CloudReplicaCheckpointStoreError.invalidCheckpoint
                }
            case .revoked:
                guard configurationScopeFingerprint == nil,
                      checkpointHighWatermark == nil,
                      pendingCheckpointHighWatermark == nil,
                      initialBootstrapReservation == nil,
                      containsRevoked(replicaEpoch) else {
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
                configurationScopeFingerprint: nil,
                revision: nextRevision,
                state: .revoked,
                revokedEpochFilter: filter,
                checkpointHighWatermark: nil,
                pendingCheckpointHighWatermark: nil,
                initialBootstrapReservation: nil
            )
        }

        func activating(
            _ newEpoch: UUID,
            configurationScopeFingerprint: CloudReplicaScopeFingerprint
        ) throws -> Self {
            guard state == .revoked, !containsRevoked(newEpoch) else {
                throw CloudReplicaCheckpointStoreError.replicaEpochRevoked
            }
            return Self(
                accountID: accountID,
                replicaEpoch: newEpoch,
                configurationScopeFingerprint: configurationScopeFingerprint,
                revision: try incrementedRevision(),
                state: .active,
                revokedEpochFilter: revokedEpochFilter,
                checkpointHighWatermark: nil,
                pendingCheckpointHighWatermark: nil,
                initialBootstrapReservation: nil
            )
        }

        func reservingInitialBootstrap(
            reservationID: UUID,
            attemptSequence: UInt64
        ) throws -> Self {
            guard state == .active,
                  checkpointHighWatermark == nil,
                  pendingCheckpointHighWatermark == nil,
                  initialBootstrapReservation == nil else {
                throw CloudReplicaCheckpointStoreError
                    .initialBootstrapUnavailable
            }
            let reservation = try InitialBootstrapReservationV1(
                reservationID: reservationID,
                activeAttemptSequence: attemptSequence,
                phase: .reservedBeforeNetwork
            )
            return Self(
                accountID: accountID,
                replicaEpoch: replicaEpoch,
                configurationScopeFingerprint: configurationScopeFingerprint,
                revision: try incrementedRevision(),
                state: state,
                revokedEpochFilter: revokedEpochFilter,
                checkpointHighWatermark: nil,
                pendingCheckpointHighWatermark: nil,
                initialBootstrapReservation: reservation
            )
        }

        func markingInitialBootstrapNetworkMayHaveBeenInvoked(
            reservationID: UUID,
            attemptSequence: UInt64
        ) throws -> Self {
            guard let reservation = initialBootstrapReservation,
                  reservation.reservationID == reservationID,
                  reservation.activeAttemptSequence == attemptSequence,
                  reservation.phase == .reservedBeforeNetwork else {
                throw CloudReplicaCheckpointStoreError
                    .initialBootstrapUnavailable
            }
            return Self(
                accountID: accountID,
                replicaEpoch: replicaEpoch,
                configurationScopeFingerprint: configurationScopeFingerprint,
                revision: try incrementedRevision(),
                state: state,
                revokedEpochFilter: revokedEpochFilter,
                checkpointHighWatermark: checkpointHighWatermark,
                pendingCheckpointHighWatermark: pendingCheckpointHighWatermark,
                initialBootstrapReservation:
                    try InitialBootstrapReservationV1(
                        reservationID: reservationID,
                        activeAttemptSequence: attemptSequence,
                        phase: .networkMayHaveBeenInvoked
                    )
            )
        }

        func claimingInitialBootstrapRecovery(
            reservationID: UUID,
            expectedAttemptSequence: UInt64,
            candidateAttemptSequence: UInt64
        ) throws -> Self {
            let nextSequence = expectedAttemptSequence
                .addingReportingOverflow(1)
            guard let reservation = initialBootstrapReservation,
                  !nextSequence.overflow,
                  reservation.reservationID == reservationID,
                  reservation.phase == .networkMayHaveBeenInvoked,
                  reservation.activeAttemptSequence
                    == expectedAttemptSequence,
                  candidateAttemptSequence == nextSequence.partialValue,
                  checkpointHighWatermark == nil,
                  pendingCheckpointHighWatermark == nil else {
                throw CloudReplicaCheckpointStoreError
                    .initialBootstrapUnavailable
            }
            return Self(
                accountID: accountID,
                replicaEpoch: replicaEpoch,
                configurationScopeFingerprint: configurationScopeFingerprint,
                revision: try incrementedRevision(),
                state: state,
                revokedEpochFilter: revokedEpochFilter,
                checkpointHighWatermark: nil,
                pendingCheckpointHighWatermark: nil,
                initialBootstrapReservation:
                    try InitialBootstrapReservationV1(
                        reservationID: reservationID,
                        activeAttemptSequence: candidateAttemptSequence,
                        phase: .networkMayHaveBeenInvoked
                    )
            )
        }

        func abortingUnstartedInitialBootstrapReservation() throws -> Self {
            guard let reservation = initialBootstrapReservation,
                  reservation.phase == .reservedBeforeNetwork else {
                return self
            }
            return Self(
                accountID: accountID,
                replicaEpoch: replicaEpoch,
                configurationScopeFingerprint: configurationScopeFingerprint,
                revision: try incrementedRevision(),
                state: state,
                revokedEpochFilter: revokedEpochFilter,
                checkpointHighWatermark: checkpointHighWatermark,
                pendingCheckpointHighWatermark: pendingCheckpointHighWatermark,
                initialBootstrapReservation: nil
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
            guard watermark.configurationScopeFingerprint
                == configurationScopeFingerprint else {
                throw CloudReplicaCheckpointStoreError.configurationScopeMismatch
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
                configurationScopeFingerprint: configurationScopeFingerprint,
                revision: try incrementedRevision(),
                state: state,
                revokedEpochFilter: revokedEpochFilter,
                checkpointHighWatermark: checkpointHighWatermark,
                pendingCheckpointHighWatermark: watermark,
                initialBootstrapReservation: initialBootstrapReservation
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
            guard watermark.configurationScopeFingerprint
                == configurationScopeFingerprint else {
                throw CloudReplicaCheckpointStoreError.configurationScopeMismatch
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
            let acceptedReservation: InitialBootstrapReservationV1?
            if let initialBootstrapReservation,
               watermark.generation == 1,
               initialBootstrapReservation.phase
                == .networkMayHaveBeenInvoked
            {
                acceptedReservation = try initialBootstrapReservation
                    .consumingByCheckpoint()
            } else {
                acceptedReservation = initialBootstrapReservation
            }
            return Self(
                accountID: accountID,
                replicaEpoch: replicaEpoch,
                configurationScopeFingerprint: configurationScopeFingerprint,
                revision: try incrementedRevision(),
                state: state,
                revokedEpochFilter: revokedEpochFilter,
                checkpointHighWatermark: watermark,
                pendingCheckpointHighWatermark: nil,
                initialBootstrapReservation: acceptedReservation
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
                configurationScopeFingerprint: configurationScopeFingerprint,
                revision: try incrementedRevision(),
                state: state,
                revokedEpochFilter: revokedEpochFilter,
                checkpointHighWatermark: checkpointHighWatermark,
                pendingCheckpointHighWatermark: nil,
                initialBootstrapReservation: initialBootstrapReservation
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
            guard watermark.configurationScopeFingerprint
                == configurationScopeFingerprint else {
                throw CloudReplicaCheckpointStoreError.configurationScopeMismatch
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
            let acceptedReservation: InitialBootstrapReservationV1?
            if let initialBootstrapReservation,
               watermark.generation == 1,
               initialBootstrapReservation.phase
                == .networkMayHaveBeenInvoked
            {
                acceptedReservation = try initialBootstrapReservation
                    .consumingByCheckpoint()
            } else {
                acceptedReservation = initialBootstrapReservation
            }
            return Self(
                accountID: accountID,
                replicaEpoch: replicaEpoch,
                configurationScopeFingerprint: configurationScopeFingerprint,
                revision: try incrementedRevision(),
                state: state,
                revokedEpochFilter: revokedEpochFilter,
                checkpointHighWatermark: watermark,
                pendingCheckpointHighWatermark: nil,
                initialBootstrapReservation: acceptedReservation
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
    private let accountGenerationAuthority: CloudAccountGenerationAuthority?
    private let initialBootstrapReservationUUIDFactory:
        CloudReplicaInitialBootstrapProcessAuthorityV1.ReservationUUIDFactory
    private let maximumIssuedInitialBootstrapReservationCount: Int
    private var activeEpochByAccount: [CloudAccountID: UUID] = [:]
    private var initialBootstrapProcessAuthorityByAccount:
        [CloudAccountID: CloudReplicaInitialBootstrapProcessAuthorityV1] = [:]

    init(
        rootDirectoryURL: URL,
        fileSystem: any CloudReplicaCheckpointFileSystem =
            FoundationCloudReplicaCheckpointFileSystem(),
        limits: CloudReplicaResourceLimits = .production,
        accountGenerationAuthority: CloudAccountGenerationAuthority? = nil,
        initialBootstrapReservationUUIDFactory: @escaping @Sendable () -> UUID = {
            UUID()
        },
        maximumIssuedInitialBootstrapReservationCount: Int = 4_096
    ) {
        precondition(maximumIssuedInitialBootstrapReservationCount > 0)
        self.rootDirectoryURL = rootDirectoryURL
        self.fileSystem = fileSystem
        self.limits = limits
        self.accountGenerationAuthority = accountGenerationAuthority
        self.initialBootstrapReservationUUIDFactory =
            initialBootstrapReservationUUIDFactory
        self.maximumIssuedInitialBootstrapReservationCount =
            maximumIssuedInitialBootstrapReservationCount
    }

    func activate(
        replicaEpoch: UUID,
        configurationScopeFingerprint: CloudReplicaScopeFingerprint,
        for accountID: CloudAccountID
    ) throws {
        let locations = locations(for: accountID)
        try withAccountLock(locations: locations) {
            let processAuthority = try initialBootstrapProcessAuthorityLocked(
                accountID: accountID,
                locations: locations
            )
            let existing = try readAuthority(
                for: accountID,
                locations: locations
            )
            let activated: ReplicaEpochAuthorityV2
            if let existing {
                if existing.containsRevoked(replicaEpoch) {
                    throw CloudReplicaCheckpointStoreError.replicaEpochRevoked
                }
                if existing.replicaEpoch == replicaEpoch {
                    guard existing.state == .active else {
                        throw CloudReplicaCheckpointStoreError.replicaEpochRevoked
                    }
                    guard existing.configurationScopeFingerprint
                        == configurationScopeFingerprint else {
                        throw CloudReplicaCheckpointStoreError
                            .configurationScopeMismatch
                    }
                    activated = existing
                } else {
                    guard existing.state == .revoked else {
                        throw CloudReplicaCheckpointStoreError.replicaEpochMismatch
                    }
                    // A completed revocation owns the old account directory.
                    // Clear it before publishing authority for the next epoch.
                    try removeAccountDirectoryIfPresent(locations)
                    activated = try existing.activating(
                        replicaEpoch,
                        configurationScopeFingerprint:
                            configurationScopeFingerprint
                    )
                    try writeAuthority(activated, locations: locations)
                }
            } else {
                // Missing authority means the account-local directory has no
                // trusted owner. Clear that recoverable cache before publishing
                // a new epoch, so a crash cannot bind new authority to old data.
                try removeAccountDirectoryIfPresent(locations)
                activated = ReplicaEpochAuthorityV2(
                    active: replicaEpoch,
                    configurationScopeFingerprint:
                        configurationScopeFingerprint,
                    for: accountID
                )
                try writeAuthority(activated, locations: locations)
            }

            guard try readAuthority(for: accountID, locations: locations)
                == activated else {
                throw CloudReplicaCheckpointStoreError.invalidCheckpoint
            }
            activeEpochByAccount[accountID] = replicaEpoch
            initialBootstrapProcessAuthorityByAccount[accountID] =
                processAuthority
        }
    }

    func resumeActiveReplicaEpoch(
        for accountID: CloudAccountID,
        configurationScopeFingerprint: CloudReplicaScopeFingerprint
    ) throws -> CloudReplicaEpochResumeResult? {
        let locations = locations(for: accountID)
        return try withAccountLock(locations: locations) {
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
                guard authority.configurationScopeFingerprint
                    == configurationScopeFingerprint else {
                    throw CloudReplicaCheckpointStoreError
                        .configurationScopeMismatch
                }
            }
            guard let authority, authority.state == .active else {
                return nil
            }
            guard authority.configurationScopeFingerprint
                == configurationScopeFingerprint else {
                throw CloudReplicaCheckpointStoreError.configurationScopeMismatch
            }
            activeEpochByAccount[accountID] = authority.replicaEpoch
            return CloudReplicaEpochResumeResult(
                replicaEpoch: authority.replicaEpoch,
                acceptedHistory:
                    authority.checkpointHighWatermark?.acceptedHistory,
                hasDurableCheckpointIntent:
                    authority.pendingCheckpointHighWatermark != nil
            )
        }
    }

    func activeReplicaAuthority(
        for accountID: CloudAccountID
    ) throws -> CloudReplicaActiveEpochAuthorityV1? {
        let locations = locations(for: accountID)
        return try withAccountLock(locations: locations) {
            guard let authority = try readAuthority(
                for: accountID,
                locations: locations
            ), authority.state == .active,
            let scope = authority.configurationScopeFingerprint else {
                return nil
            }
            return CloudReplicaActiveEpochAuthorityV1(
                replicaEpoch: authority.replicaEpoch,
                configurationScopeFingerprint: scope
            )
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
                if let authority, authority.state == .active {
                    guard authority.configurationScopeFingerprint
                        == configurationScopeFingerprint else {
                        throw CloudReplicaCheckpointStoreError
                            .configurationScopeMismatch
                    }
                }
                // Discovery remains available to a fresh store with no
                // remembered epoch. A stale activated store fails above before
                // it can create, quarantine, or repair account-local files.
                try fileSystem.createDirectory(at: locations.accountDirectory)
                var quarantinedCount = 0
                let watermarkState = try validatedWatermark(
                    at: locations.watermark,
                    accountID: accountID,
                    fingerprint: configurationScopeFingerprint,
                    locations: locations,
                    quarantinedCount: &quarantinedCount
                )
                let primary = try validatedCopy(
                    at: locations.primary,
                    source: .primary,
                    accountID: accountID,
                    fingerprint: configurationScopeFingerprint,
                    locations: locations,
                    quarantinedCount: &quarantinedCount
                )
                let backup = try validatedCopy(
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
                        if try quarantine(locations.watermark, locations: locations) {
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

                var winner = try resolve(
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
                   let acceptedWinner = try resolve(
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
                    $0.state != .active
                        || $0.replicaEpoch != checkpoint.replicaEpoch
                        || $0.configurationScopeFingerprint
                            != checkpoint.configurationScopeFingerprint
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
                    try quarantineAll(
                        [primary, backup].compactMap { $0 },
                        locations: locations,
                        quarantinedCount: &quarantinedCount
                    )
                    if try quarantine(locations.watermark, locations: locations) {
                        quarantinedCount += 1
                    }
                    return CloudReplicaCheckpointLoadResult(
                        checkpoint: nil,
                        source: .none,
                        quarantinedFileCount: quarantinedCount
                    )
                }

                let baseAuthority = resolvedAuthority
                    ?? ReplicaEpochAuthorityV2(
                        active: checkpoint.replicaEpoch,
                        configurationScopeFingerprint:
                            checkpoint.configurationScopeFingerprint,
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
                try writeExactData(watermarkData, to: locations.watermark)
                try writeExactData(winner.data, to: locations.primary)
                try writeExactData(winner.data, to: locations.backup)
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

    func observeCurrentCheckpoint(
        for accountID: CloudAccountID,
        configurationScopeFingerprint: CloudReplicaScopeFingerprint,
        replicaEpoch: UUID,
        at date: Date
    ) throws -> CloudReplicaCheckpointObservationV1 {
        let locations = locations(for: accountID)
        try withAccountLock(locations: locations) {
            _ = try validatedActiveAuthorityLocked(
                accountID: accountID,
                configurationScopeFingerprint: configurationScopeFingerprint,
                replicaEpoch: replicaEpoch,
                locations: locations,
                requireRememberedEpoch: false
            )
        }
        let loaded = try load(
            for: accountID,
            configurationScopeFingerprint: configurationScopeFingerprint,
            at: date
        )
        return try withAccountLock(locations: locations) {
            try makeCurrentObservationLocked(
                accountID: accountID,
                configurationScopeFingerprint: configurationScopeFingerprint,
                replicaEpoch: replicaEpoch,
                loaded: loaded,
                locations: locations,
                requireRememberedEpoch: false
            )
        }
    }

    /// Executes a bounded synchronous profile-file mutation while the exact
    /// accepted checkpoint and durable account authority remain locked. The
    /// borrowed outer lease proves the caller still holds the matching
    /// process-local account-generation commit gate from the exact authority
    /// configured at initialization. Network work, actor calls, Tasks, and
    /// semaphore bridges are forbidden inside `perform`.
    func withCurrentCheckpointLease<Output: Sendable>(
        generationLease: borrowing AccountGenerationCommitLease,
        at date: Date,
        perform: @Sendable (
            borrowing CloudReplicaCheckpointFreshnessLeaseV1
        ) throws -> Output
    ) throws -> Output {
        guard let accountGenerationAuthority else {
            throw CloudReplicaCheckpointStoreError
                .accountGenerationAuthorityNotBound
        }
        guard generationLease.wasIssued(by: accountGenerationAuthority) else {
            throw CloudReplicaCheckpointStoreError
                .accountGenerationAuthorityMismatch
        }

        let accountID = generationLease.accountID
        let configurationScopeFingerprint =
            generationLease.configurationScopeFingerprint
        let replicaEpoch = generationLease.replicaEpoch
        let locations = locations(for: accountID)
        try withAccountLock(locations: locations) {
            _ = try validatedActiveAuthorityLocked(
                accountID: accountID,
                configurationScopeFingerprint: configurationScopeFingerprint,
                replicaEpoch: replicaEpoch,
                locations: locations,
                requireRememberedEpoch: true
            )
        }

        // Loading may repair an interrupted checkpoint publication, so it must
        // run without an already-held outer account lock.
        let loaded = try load(
            for: accountID,
            configurationScopeFingerprint: configurationScopeFingerprint,
            at: date
        )

        var callbackOutcome: Result<Output, any Error>?
        try withAccountLock(locations: locations) {
            let observation = try makeCurrentObservationLocked(
                accountID: accountID,
                configurationScopeFingerprint: configurationScopeFingerprint,
                replicaEpoch: replicaEpoch,
                loaded: loaded,
                locations: locations,
                requireRememberedEpoch: true
            )
            let lease = CloudReplicaCheckpointFreshnessLeaseV1(
                observation: observation
            )
            do {
                callbackOutcome = .success(try perform(lease))
            } catch {
                callbackOutcome = .failure(error)
            }
        }
        guard let callbackOutcome else {
            throw CloudReplicaCheckpointStoreError.ioFailure
        }
        return try callbackOutcome.get()
    }

    /// Mints the sole zone-creating fetch context only when a read-only,
    /// account-locked preflight proves that this remembered epoch has no
    /// accepted history, publication intent, checkpoint files, or quarantine
    /// evidence. It deliberately does not call `load`, whose recovery behavior
    /// may repair, quarantine, or remove the very evidence that closes genesis.
    func beginInitialBootstrapPublication(
        generationLease: borrowing AccountGenerationCommitLease,
        at date: Date
    ) throws -> CloudReplicaInitialBootstrapPublicationContextV1 {
        _ = date
        guard let accountGenerationAuthority else {
            throw CloudReplicaCheckpointStoreError
                .accountGenerationAuthorityNotBound
        }
        guard generationLease.wasIssued(by: accountGenerationAuthority) else {
            throw CloudReplicaCheckpointStoreError
                .accountGenerationAuthorityMismatch
        }

        let accountID = generationLease.accountID
        let configurationScopeFingerprint =
            generationLease.configurationScopeFingerprint
        let replicaEpoch = generationLease.replicaEpoch
        let generationToken = generationLease.generationToken
        let locations = locations(for: accountID)

        let contextBindings = try withAccountLock(locations: locations) {
            var authority = try validatedActiveAuthorityLocked(
                accountID: accountID,
                configurationScopeFingerprint: configurationScopeFingerprint,
                replicaEpoch: replicaEpoch,
                locations: locations,
                requireRememberedEpoch: true
            )
            let processAuthority = try initialBootstrapProcessAuthorityLocked(
                accountID: accountID,
                locations: locations
            )
            try requireInitialBootstrapAvailabilityLocked(
                authority: authority,
                locations: locations
            )

            var replacementReservationID: UUID?
            if let unstartedReservation =
                authority.initialBootstrapReservation,
               unstartedReservation.phase == .reservedBeforeNetwork {
                try processAuthority.adoptDurableReservationID(
                    unstartedReservation.reservationID
                )
                // Issue before clearing durable state. Zero, collision, and
                // cap failures therefore leave the replaceable reservation
                // byte-for-byte intact.
                replacementReservationID = try processAuthority
                    .issueReservationID()
                let cleared = try authority
                    .abortingUnstartedInitialBootstrapReservation()
                try writeAuthority(cleared, locations: locations)
                guard try readAuthority(
                    for: accountID,
                    locations: locations
                ) == cleared else {
                    throw CloudReplicaCheckpointStoreError.invalidCheckpoint
                }
                authority = cleared
            }

            if let reservation = authority.initialBootstrapReservation {
                guard reservation.phase == .networkMayHaveBeenInvoked else {
                    throw CloudReplicaCheckpointStoreError
                        .initialBootstrapUnavailable
                }
                try processAuthority.adoptDurableReservationID(
                    reservation.reservationID
                )
                let nextSequence = reservation.activeAttemptSequence
                    .addingReportingOverflow(1)
                guard !nextSequence.overflow else {
                    throw CloudReplicaCheckpointStoreError
                        .initialBootstrapUnavailable
                }
                return (
                    reservationID: reservation.reservationID,
                    expectedAttemptSequence:
                        Optional(reservation.activeAttemptSequence),
                    attemptSequence: nextSequence.partialValue,
                    networkPolicy:
                        CloudReplicaInitialBootstrapNetworkPolicyV1
                            .requireExistingZoneRecovery,
                    processAuthority: processAuthority
                )
            }

            let reservationID: UUID
            if let replacementReservationID {
                reservationID = replacementReservationID
            } else {
                reservationID = try processAuthority.issueReservationID()
            }
            return (
                reservationID: reservationID,
                expectedAttemptSequence: Optional<UInt64>.none,
                attemptSequence: UInt64(1),
                networkPolicy:
                    CloudReplicaInitialBootstrapNetworkPolicyV1
                        .mayCreateZoneOnFirstRequest,
                processAuthority: processAuthority
            )
        }

        let permit = CloudReplicaInitialBootstrapFetchPermitV1(
            reservationID: contextBindings.reservationID,
            attemptSequence: contextBindings.attemptSequence,
            networkPolicy: contextBindings.networkPolicy,
            reserveDurably: { [self] in
                do {
                    return try await accountGenerationAuthority
                        .withCurrentGeneration(
                        matching: generationToken
                    ) { lease in
                        try await self.admitInitialBootstrapNetworkAttempt(
                            reservationID: contextBindings.reservationID,
                            expectedAttemptSequence:
                                contextBindings.expectedAttemptSequence,
                            attemptSequence: contextBindings.attemptSequence,
                            networkPolicy: contextBindings.networkPolicy,
                            processAuthority:
                                contextBindings.processAuthority,
                            generationLease: lease
                        )
                    }
                } catch is CloudAccountGenerationAuthorityError {
                    throw CloudReplicaCheckpointStoreError
                        .accountGenerationMismatch
                }
            }
        )
        return CloudReplicaInitialBootstrapPublicationContextV1(
            generationToken: generationToken,
            accountID: accountID,
            configurationScopeFingerprint: configurationScopeFingerprint,
            replicaEpoch: replicaEpoch,
            limits: limits,
            reservationID: contextBindings.reservationID,
            attemptSequence: contextBindings.attemptSequence,
            processAuthority: contextBindings.processAuthority,
            zoneCreationPermit: permit
        )
    }

    /// Claims one durable attempt while the matching process-local generation
    /// gate and cross-store account lock are both held. New bootstrap writes a
    /// before-network reservation and then durably advances it to the
    /// ambiguous-network phase. Recovery can only rotate the active attempt of
    /// an existing ambiguous reservation and never regains zone creation.
    private func admitInitialBootstrapNetworkAttempt(
        reservationID: UUID,
        expectedAttemptSequence: UInt64?,
        attemptSequence: UInt64,
        networkPolicy: CloudReplicaInitialBootstrapNetworkPolicyV1,
        processAuthority:
            CloudReplicaInitialBootstrapProcessAuthorityV1,
        generationLease: borrowing AccountGenerationCommitLease
    ) throws -> CloudReplicaInitialBootstrapNetworkAttemptLeaseV1 {
        guard let accountGenerationAuthority else {
            throw CloudReplicaCheckpointStoreError
                .accountGenerationAuthorityNotBound
        }
        guard generationLease.wasIssued(by: accountGenerationAuthority) else {
            throw CloudReplicaCheckpointStoreError
                .accountGenerationAuthorityMismatch
        }
        let accountID = generationLease.accountID
        let configurationScopeFingerprint =
            generationLease.configurationScopeFingerprint
        let replicaEpoch = generationLease.replicaEpoch
        let locations = locations(for: accountID)

        return try withAccountLock(locations: locations) {
            let authority = try validatedActiveAuthorityLocked(
                accountID: accountID,
                configurationScopeFingerprint: configurationScopeFingerprint,
                replicaEpoch: replicaEpoch,
                locations: locations,
                requireRememberedEpoch: true
            )
            let currentProcessAuthority = try
                initialBootstrapProcessAuthorityLocked(
                    accountID: accountID,
                    locations: locations
                )
            guard currentProcessAuthority === processAuthority else {
                throw CloudReplicaCheckpointStoreError
                    .initialBootstrapUnavailable
            }
            try requireInitialBootstrapAvailabilityLocked(
                authority: authority,
                locations: locations
            )
            let attemptLease = try processAuthority.claimAttempt(
                reservationID: reservationID,
                attemptSequence: attemptSequence
            )

            do {
                switch networkPolicy {
                case .mayCreateZoneOnFirstRequest:
                    guard expectedAttemptSequence == nil,
                          attemptSequence == 1,
                          authority.initialBootstrapReservation == nil else {
                        throw CloudReplicaCheckpointStoreError
                            .initialBootstrapUnavailable
                    }
                    let reserved = try authority.reservingInitialBootstrap(
                        reservationID: reservationID,
                        attemptSequence: attemptSequence
                    )
                    try writeAuthority(reserved, locations: locations)
                    guard try readAuthority(
                        for: accountID,
                        locations: locations
                    ) == reserved else {
                        throw CloudReplicaCheckpointStoreError
                            .invalidCheckpoint
                    }

                    let networkAdmitted = try reserved
                        .markingInitialBootstrapNetworkMayHaveBeenInvoked(
                            reservationID: reservationID,
                            attemptSequence: attemptSequence
                        )
                    try writeAuthority(networkAdmitted, locations: locations)
                    guard try readAuthority(
                        for: accountID,
                        locations: locations
                    ) == networkAdmitted else {
                        throw CloudReplicaCheckpointStoreError
                            .invalidCheckpoint
                    }

                case .requireExistingZoneRecovery:
                    guard let expectedAttemptSequence else {
                        throw CloudReplicaCheckpointStoreError
                            .initialBootstrapUnavailable
                    }
                    let networkAdmitted = try authority
                        .claimingInitialBootstrapRecovery(
                            reservationID: reservationID,
                            expectedAttemptSequence: expectedAttemptSequence,
                            candidateAttemptSequence: attemptSequence
                        )
                    try writeAuthority(networkAdmitted, locations: locations)
                    guard try readAuthority(
                        for: accountID,
                        locations: locations
                    ) == networkAdmitted else {
                        throw CloudReplicaCheckpointStoreError
                            .invalidCheckpoint
                    }
                }
                return attemptLease
            } catch {
                attemptLease.release()
                throw error
            }
        }
    }

    /// Publishes only a generation-one result minted by the matching canonical
    /// account generation. The private disk engine rechecks durable genesis
    /// absence beneath the same account lock that records publication intent.
    func saveInitialBootstrapPublication(
        _ publication: CloudReplicaInitialBootstrapPublicationV1,
        generationLease: borrowing AccountGenerationCommitLease,
        at date: Date
    ) throws {
        guard let accountGenerationAuthority else {
            throw CloudReplicaCheckpointStoreError
                .accountGenerationAuthorityNotBound
        }
        guard generationLease.wasIssued(by: accountGenerationAuthority) else {
            throw CloudReplicaCheckpointStoreError
                .accountGenerationAuthorityMismatch
        }
        guard generationLease.generationToken == publication.generationToken,
              generationLease.accountID == publication.accountID,
              generationLease.configurationScopeFingerprint
                == publication.configurationScopeFingerprint,
              generationLease.replicaEpoch == publication.replicaEpoch,
              publication.checkpoint.accountID == publication.accountID,
              publication.checkpoint.configurationScopeFingerprint
                == publication.configurationScopeFingerprint,
              publication.checkpoint.replicaEpoch == publication.replicaEpoch
        else {
            throw CloudReplicaCheckpointStoreError.accountGenerationMismatch
        }
        guard publication.checkpoint.generation == 1 else {
            throw CloudReplicaCheckpointStoreError.generationGap
        }

        try saveRawCheckpoint(
            publication.checkpoint,
            succeeding: nil,
            requiredInitialBootstrapReservationID: publication.reservationID,
            requiredInitialBootstrapAttemptSequence:
                publication.attemptSequence,
            requiredInitialBootstrapAttemptLease:
                publication.attemptLease,
            at: date
        )
    }

    /// Mints a network-safe recovery context only while the canonical account
    /// generation is current and durable accepted history has lost every
    /// usable local checkpoint copy. The returned value is designed to escape
    /// the bounded caller before network work; this actor cannot enforce when
    /// the caller releases its outer generation gate.
    func beginRequireExistingFullSnapshotReconstruction(
        generationLease: borrowing AccountGenerationCommitLease,
        at date: Date
    ) throws -> CloudReplicaRequireExistingReconstructionContextV1 {
        guard let accountGenerationAuthority else {
            throw CloudReplicaCheckpointStoreError
                .accountGenerationAuthorityNotBound
        }
        guard generationLease.wasIssued(by: accountGenerationAuthority) else {
            throw CloudReplicaCheckpointStoreError
                .accountGenerationAuthorityMismatch
        }

        let accountID = generationLease.accountID
        let configurationScopeFingerprint =
            generationLease.configurationScopeFingerprint
        let replicaEpoch = generationLease.replicaEpoch
        let generationToken = generationLease.generationToken
        let locations = locations(for: accountID)

        try withAccountLock(locations: locations) {
            _ = try validatedActiveAuthorityLocked(
                accountID: accountID,
                configurationScopeFingerprint: configurationScopeFingerprint,
                replicaEpoch: replicaEpoch,
                locations: locations,
                requireRememberedEpoch: true
            )
        }

        // Loading may resolve an interrupted publication or quarantine broken
        // cache evidence, so it cannot run beneath an already-held account
        // lock. A second locked inspection below closes the cross-store race.
        let loaded = try load(
            for: accountID,
            configurationScopeFingerprint: configurationScopeFingerprint,
            at: date
        )

        return try withAccountLock(locations: locations) {
            let authority = try validatedActiveAuthorityLocked(
                accountID: accountID,
                configurationScopeFingerprint: configurationScopeFingerprint,
                replicaEpoch: replicaEpoch,
                locations: locations,
                requireRememberedEpoch: true
            )
            guard loaded.checkpoint == nil else {
                throw CloudReplicaCheckpointStoreError
                    .acceptedCheckpointStillAvailable
            }
            guard let acceptedWatermark = authority.checkpointHighWatermark else {
                throw CloudReplicaCheckpointStoreError
                    .acceptedHistoryUnavailable
            }

            try fileSystem.createDirectory(at: locations.accountDirectory)
            var quarantinedCount = 0
            let primary = try validatedCopy(
                at: locations.primary,
                source: .primary,
                accountID: accountID,
                fingerprint: configurationScopeFingerprint,
                locations: locations,
                quarantinedCount: &quarantinedCount
            )
            let backup = try validatedCopy(
                at: locations.backup,
                source: .backup,
                accountID: accountID,
                fingerprint: configurationScopeFingerprint,
                locations: locations,
                quarantinedCount: &quarantinedCount
            )
            let usableAcceptedCheckpoint = try resolve(
                primary: primary,
                backup: backup,
                watermark: acceptedWatermark,
                preserving: authority.pendingCheckpointHighWatermark,
                locations: locations,
                quarantinedCount: &quarantinedCount
            )
            guard usableAcceptedCheckpoint == nil else {
                throw CloudReplicaCheckpointStoreError
                    .acceptedCheckpointStillAvailable
            }

            return CloudReplicaRequireExistingReconstructionContextV1(
                generationToken: generationToken,
                acceptedHistory: acceptedWatermark.acceptedHistory,
                limits: limits
            )
        }
    }

    /// Mints a fixed-policy incremental fetch context from one exact, usable
    /// accepted checkpoint. This path cannot create a genesis checkpoint or
    /// reconstruct missing accepted cache.
    func beginIncrementalOrdinaryPublication(
        generationLease: borrowing AccountGenerationCommitLease,
        at date: Date
    ) throws -> CloudReplicaIncrementalOrdinaryPublicationContextV1 {
        guard let accountGenerationAuthority else {
            throw CloudReplicaCheckpointStoreError
                .accountGenerationAuthorityNotBound
        }
        guard generationLease.wasIssued(by: accountGenerationAuthority) else {
            throw CloudReplicaCheckpointStoreError
                .accountGenerationAuthorityMismatch
        }

        let accountID = generationLease.accountID
        let configurationScopeFingerprint =
            generationLease.configurationScopeFingerprint
        let replicaEpoch = generationLease.replicaEpoch
        let generationToken = generationLease.generationToken
        let locations = locations(for: accountID)

        try withAccountLock(locations: locations) {
            _ = try validatedActiveAuthorityLocked(
                accountID: accountID,
                configurationScopeFingerprint: configurationScopeFingerprint,
                replicaEpoch: replicaEpoch,
                locations: locations,
                requireRememberedEpoch: true
            )
        }

        // Loading may repair an interrupted publication, so the actor does not
        // nest it beneath another account lock. The second locked inspection
        // rejects any cross-store predecessor change before minting the context.
        let loaded = try load(
            for: accountID,
            configurationScopeFingerprint: configurationScopeFingerprint,
            at: date
        )

        return try withAccountLock(locations: locations) {
            _ = try makeCurrentObservationLocked(
                accountID: accountID,
                configurationScopeFingerprint: configurationScopeFingerprint,
                replicaEpoch: replicaEpoch,
                loaded: loaded,
                locations: locations,
                requireRememberedEpoch: true
            )
            guard let predecessor = loaded.checkpoint else {
                throw CloudReplicaCheckpointStoreError
                    .acceptedHistoryUnavailable
            }
            let predecessorHistory = WatermarkV1(
                checkpoint: predecessor
            ).acceptedHistory
            return CloudReplicaIncrementalOrdinaryPublicationContextV1(
                generationToken: generationToken,
                predecessor: predecessor,
                predecessorHistory: predecessorHistory,
                limits: limits
            )
        }
    }

    /// Publishes only an incremental result branded by the same canonical
    /// account generation and exact accepted predecessor.
    func saveOrdinaryPublication(
        _ publication: CloudReplicaOrdinaryPublicationV1,
        generationLease: borrowing AccountGenerationCommitLease,
        at date: Date
    ) throws {
        guard let accountGenerationAuthority else {
            throw CloudReplicaCheckpointStoreError
                .accountGenerationAuthorityNotBound
        }
        guard generationLease.wasIssued(by: accountGenerationAuthority) else {
            throw CloudReplicaCheckpointStoreError
                .accountGenerationAuthorityMismatch
        }
        guard generationLease.generationToken == publication.generationToken,
              generationLease.accountID
                == publication.predecessorHistory.accountID,
              generationLease.configurationScopeFingerprint
                == publication.predecessorHistory
                    .configurationScopeFingerprint,
              generationLease.replicaEpoch
                == publication.predecessorHistory.replicaEpoch else {
            throw CloudReplicaCheckpointStoreError.accountGenerationMismatch
        }

        try saveRawCheckpoint(
            publication.checkpoint,
            succeeding: publication.predecessorHistory,
            at: date
        )
    }

    #if DEBUG
    /// Fault-injection and migration tests need direct access to the durable
    /// disk engine. This API is not compiled into Release builds.
    func _testOnlySaveRawCheckpoint(
        _ checkpoint: CloudReplicaCheckpointV1,
        at date: Date
    ) throws {
        try saveRawCheckpoint(checkpoint, succeeding: nil, at: date)
    }
    #endif

    /// Private disk engine retained for legacy-cache migration and Debug fault
    /// tests. Release publication reaches it only through a branded result.
    private func saveRawCheckpoint(
        _ checkpoint: CloudReplicaCheckpointV1,
        succeeding predecessorHistory: CloudReplicaAcceptedHistoryV1?,
        requiredInitialBootstrapReservationID: UUID? = nil,
        requiredInitialBootstrapAttemptSequence: UInt64? = nil,
        requiredInitialBootstrapAttemptLease:
            CloudReplicaInitialBootstrapNetworkAttemptLeaseV1? = nil,
        at date: Date
    ) throws {
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
                guard durableAuthority.configurationScopeFingerprint
                    == checkpoint.configurationScopeFingerprint else {
                    throw CloudReplicaCheckpointStoreError
                        .configurationScopeMismatch
                }

                if requiredInitialBootstrapReservationID != nil
                    || requiredInitialBootstrapAttemptSequence != nil
                    || requiredInitialBootstrapAttemptLease != nil
                {
                    guard let requiredInitialBootstrapReservationID,
                          let requiredInitialBootstrapAttemptSequence,
                          let requiredInitialBootstrapAttemptLease else {
                        throw CloudReplicaCheckpointStoreError
                            .initialBootstrapUnavailable
                    }
                    guard predecessorHistory == nil,
                          checkpoint.generation == 1 else {
                        throw CloudReplicaCheckpointStoreError.generationGap
                    }
                    let processAuthority = try
                        initialBootstrapProcessAuthorityLocked(
                            accountID: checkpoint.accountID,
                            locations: locations
                        )
                    guard requiredInitialBootstrapAttemptLease.authorizes(
                        reservationID:
                            requiredInitialBootstrapReservationID,
                        attemptSequence:
                            requiredInitialBootstrapAttemptSequence,
                        processAuthority: processAuthority
                    ) else {
                        throw CloudReplicaCheckpointStoreError
                            .initialBootstrapUnavailable
                    }
                    try requireInitialBootstrapAvailabilityLocked(
                        authority: durableAuthority,
                        locations: locations
                    )
                    guard let reservation = durableAuthority
                        .initialBootstrapReservation,
                          reservation.reservationID
                            == requiredInitialBootstrapReservationID,
                          reservation.activeAttemptSequence
                            == requiredInitialBootstrapAttemptSequence,
                          reservation.phase == .networkMayHaveBeenInvoked else {
                        throw CloudReplicaCheckpointStoreError
                            .initialBootstrapUnavailable
                    }
                }

                let candidateWatermark = WatermarkV1(checkpoint: checkpoint)
                if let predecessorHistory {
                    guard let acceptedWatermark =
                            durableAuthority.checkpointHighWatermark,
                          acceptedWatermark.matches(predecessorHistory) else {
                        throw CloudReplicaCheckpointStoreError
                            .acceptedHistoryMismatch
                    }
                    if let pending =
                            durableAuthority.pendingCheckpointHighWatermark,
                       pending != candidateWatermark {
                        throw CloudReplicaCheckpointStoreError
                            .checkpointPublicationPending
                    }
                }

                try fileSystem.createDirectory(at: locations.accountDirectory)
                var quarantinedCount = 0
                var watermarkState = try validatedWatermark(
                    at: locations.watermark,
                    accountID: checkpoint.accountID,
                    fingerprint: checkpoint.configurationScopeFingerprint,
                    locations: locations,
                    quarantinedCount: &quarantinedCount
                )
                var primary = try validatedCopy(
                    at: locations.primary,
                    source: .primary,
                    accountID: checkpoint.accountID,
                    fingerprint: checkpoint.configurationScopeFingerprint,
                    locations: locations,
                    quarantinedCount: &quarantinedCount
                )
                var backup = try validatedCopy(
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
                        try quarantineAll(
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
                        _ = try quarantine(locations.watermark, locations: locations)
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

                var current = try resolve(
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
                try writeExactData(watermarkData, to: locations.watermark)
                try writeExactData(envelopeData, to: locations.primary)
                try writeExactData(envelopeData, to: locations.backup)

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
                requiredInitialBootstrapAttemptLease?.release()
            } catch let error as CloudReplicaCheckpointStoreError {
                throw error
            } catch {
                throw CloudReplicaCheckpointStoreError.ioFailure
            }
        }
    }

    /// Publishes only a snapshot produced by the sealed fixed-policy fetch
    /// context. A fresh canonical generation lease must match the exact opaque
    /// generation that minted that context, closing stale, cross-authority,
    /// and same-binding reactivation races before durable checkpoint work.
    func saveReconstructedFullSnapshot(
        _ reconstruction: CloudReplicaReconstructedFullSnapshotV1,
        generationLease: borrowing AccountGenerationCommitLease,
        at date: Date
    ) throws {
        guard let accountGenerationAuthority else {
            throw CloudReplicaCheckpointStoreError
                .accountGenerationAuthorityNotBound
        }
        guard generationLease.wasIssued(by: accountGenerationAuthority) else {
            throw CloudReplicaCheckpointStoreError
                .accountGenerationAuthorityMismatch
        }
        guard generationLease.generationToken
                == reconstruction.generationToken,
              generationLease.accountID
                == reconstruction.acceptedHistory.accountID,
              generationLease.configurationScopeFingerprint
                == reconstruction.acceptedHistory
                    .configurationScopeFingerprint,
              generationLease.replicaEpoch
                == reconstruction.acceptedHistory.replicaEpoch else {
            throw CloudReplicaCheckpointStoreError.accountGenerationMismatch
        }

        try saveReconstructedCheckpoint(
            reconstruction.checkpoint,
            replacing: reconstruction.acceptedHistory,
            at: date
        )
    }

    /// The raw accepted-history transition is deliberately private. Only the
    /// sealed reconstruction result above can reach it.
    private func saveReconstructedCheckpoint(
        _ checkpoint: CloudReplicaCheckpointV1,
        replacing acceptedHistory: CloudReplicaAcceptedHistoryV1,
        at date: Date
    ) throws {
        do {
            try checkpoint.validate(limits: limits)
        } catch {
            throw CloudReplicaCheckpointStoreError.invalidCheckpoint
        }
        guard checkpoint.accountID == acceptedHistory.accountID,
              checkpoint.configurationScopeFingerprint
                == acceptedHistory.configurationScopeFingerprint,
              checkpoint.replicaEpoch == acceptedHistory.replicaEpoch else {
            throw CloudReplicaCheckpointStoreError.acceptedHistoryMismatch
        }
        let (expectedGeneration, generationOverflow) = acceptedHistory.generation
            .addingReportingOverflow(1)
        guard !generationOverflow,
              checkpoint.generation == expectedGeneration else {
            throw CloudReplicaCheckpointStoreError.generationGap
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
                guard let authority = try readAuthority(
                    for: checkpoint.accountID,
                    locations: locations
                ) else {
                    throw CloudReplicaCheckpointStoreError.replicaEpochNotActive
                }
                if authority.containsRevoked(checkpoint.replicaEpoch) {
                    throw CloudReplicaCheckpointStoreError.replicaEpochRevoked
                }
                guard authority.state == .active,
                      authority.replicaEpoch == checkpoint.replicaEpoch else {
                    throw CloudReplicaCheckpointStoreError.replicaEpochMismatch
                }
                guard authority.configurationScopeFingerprint
                    == checkpoint.configurationScopeFingerprint else {
                    throw CloudReplicaCheckpointStoreError
                        .configurationScopeMismatch
                }
                guard let acceptedWatermark = authority.checkpointHighWatermark,
                      acceptedWatermark.matches(acceptedHistory) else {
                    throw CloudReplicaCheckpointStoreError.acceptedHistoryMismatch
                }

                let candidateWatermark = WatermarkV1(checkpoint: checkpoint)
                if let pending = authority.pendingCheckpointHighWatermark,
                   pending != candidateWatermark {
                    throw CloudReplicaCheckpointStoreError
                        .checkpointPublicationPending
                }

                try fileSystem.createDirectory(at: locations.accountDirectory)
                var quarantinedCount = 0
                let primary = try validatedCopy(
                    at: locations.primary,
                    source: .primary,
                    accountID: checkpoint.accountID,
                    fingerprint: checkpoint.configurationScopeFingerprint,
                    locations: locations,
                    quarantinedCount: &quarantinedCount
                )
                let backup = try validatedCopy(
                    at: locations.backup,
                    source: .backup,
                    accountID: checkpoint.accountID,
                    fingerprint: checkpoint.configurationScopeFingerprint,
                    locations: locations,
                    quarantinedCount: &quarantinedCount
                )
                let usableAcceptedCheckpoint = try resolve(
                    primary: primary,
                    backup: backup,
                    watermark: acceptedWatermark,
                    preserving: authority.pendingCheckpointHighWatermark,
                    locations: locations,
                    quarantinedCount: &quarantinedCount
                )
                guard usableAcceptedCheckpoint == nil else {
                    throw CloudReplicaCheckpointStoreError
                        .acceptedCheckpointStillAvailable
                }

                let envelopeData: Data
                let watermarkData: Data
                do {
                    envelopeData = try encode(
                        EnvelopeV1(savedAt: date, checkpoint: checkpoint)
                    )
                    watermarkData = try encode(candidateWatermark)
                } catch {
                    throw CloudReplicaCheckpointStoreError.encodingFailure
                }

                let publishingAuthority = try authority
                    .beginningCheckpointPublication(candidateWatermark)
                if publishingAuthority != authority {
                    try writeAuthority(publishingAuthority, locations: locations)
                }
                guard try readAuthority(
                    for: checkpoint.accountID,
                    locations: locations
                ) == publishingAuthority else {
                    throw CloudReplicaCheckpointStoreError.invalidCheckpoint
                }

                try writeExactData(watermarkData, to: locations.watermark)
                try writeExactData(envelopeData, to: locations.primary)
                try writeExactData(envelopeData, to: locations.backup)

                let committedAuthority = try publishingAuthority
                    .acceptingPublishedCheckpoint(candidateWatermark)
                if committedAuthority != publishingAuthority {
                    try writeAuthority(committedAuthority, locations: locations)
                }
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
            let revoked: ReplicaEpochAuthorityV2
            if let existing {
                guard existing.replicaEpoch == replicaEpoch else {
                    if existing.containsRevoked(replicaEpoch) {
                        throw CloudReplicaCheckpointStoreError.replicaEpochRevoked
                    }
                    throw CloudReplicaCheckpointStoreError.replicaEpochMismatch
                }
                revoked = try existing.revokingCurrentEpoch()
            } else {
                revoked = ReplicaEpochAuthorityV2(
                    revoked: replicaEpoch,
                    for: accountID
                )
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

    #if DEBUG
    /// Direct format/migration seam for durable-authority invariant tests.
    /// Release callers cannot decode, construct, or rewrite authority values.
    nonisolated static func _testOnlyRoundTripReplicaAuthority(
        _ data: Data
    ) throws -> Data {
        let authority = try JSONDecoder().decode(
            ReplicaEpochAuthorityV2.self,
            from: data
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(authority)
    }
    #endif

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

    /// Resolves the already-created authority directory and lock file while
    /// the advisory lock is held. `stat` follows path aliases, so symlink and
    /// case aliases converge on the same process authority instead of
    /// bypassing it through distinct standardized URLs.
    private func physicalAuthorityIdentityLocked(
        locations: Locations
    ) throws -> CloudReplicaPhysicalAuthorityIdentityV1 {
        var directoryMetadata = stat()
        let directoryResult = locations.authorityDirectory.path.withCString {
            stat($0, &directoryMetadata)
        }
        var lockMetadata = stat()
        let lockResult = locations.authorityLock.path.withCString {
            stat($0, &lockMetadata)
        }
        guard directoryResult == 0,
              directoryMetadata.st_mode & S_IFMT == S_IFDIR,
              directoryMetadata.st_ino != 0,
              lockResult == 0,
              lockMetadata.st_mode & S_IFMT == S_IFREG,
              lockMetadata.st_ino != 0 else {
            throw CloudReplicaCheckpointStoreError.ioFailure
        }
        return CloudReplicaPhysicalAuthorityIdentityV1(
            directoryDevice: UInt64(directoryMetadata.st_dev),
            directoryInode: UInt64(directoryMetadata.st_ino),
            lockDevice: UInt64(lockMetadata.st_dev),
            lockInode: UInt64(lockMetadata.st_ino)
        )
    }

    /// Called only beneath the account file lock. A store that already
    /// retained an authority identity refuses to follow a replaced physical
    /// directory, while a distinct store can adopt the new physical domain.
    private func initialBootstrapProcessAuthorityLocked(
        accountID: CloudAccountID,
        locations: Locations
    ) throws -> CloudReplicaInitialBootstrapProcessAuthorityV1 {
        let physicalIdentity = try physicalAuthorityIdentityLocked(
            locations: locations
        )
        if let retained = initialBootstrapProcessAuthorityByAccount[accountID] {
            guard retained.physicalIdentity == physicalIdentity else {
                throw CloudReplicaCheckpointStoreError
                    .initialBootstrapUnavailable
            }
            return retained
        }
        let authority = try CloudReplicaInitialBootstrapProcessAuthorityRegistryV1
            .shared.processAuthority(
                for: physicalIdentity,
                accountID: accountID,
                reservationUUIDFactory:
                    initialBootstrapReservationUUIDFactory,
                maximumIssuedReservationCount:
                    maximumIssuedInitialBootstrapReservationCount
            )
        initialBootstrapProcessAuthorityByAccount[accountID] = authority
        return authority
    }

    private func validatedActiveAuthorityLocked(
        accountID: CloudAccountID,
        configurationScopeFingerprint: CloudReplicaScopeFingerprint,
        replicaEpoch: UUID,
        locations: Locations,
        requireRememberedEpoch: Bool
    ) throws -> ReplicaEpochAuthorityV2 {
        if requireRememberedEpoch {
            guard let rememberedEpoch = activeEpochByAccount[accountID] else {
                throw CloudReplicaCheckpointStoreError.replicaEpochNotActive
            }
            guard rememberedEpoch == replicaEpoch else {
                throw CloudReplicaCheckpointStoreError.replicaEpochMismatch
            }
        }
        guard let authority = try readAuthority(
            for: accountID,
            locations: locations
        ) else {
            throw CloudReplicaCheckpointStoreError.replicaEpochNotActive
        }
        if authority.containsRevoked(replicaEpoch) {
            throw CloudReplicaCheckpointStoreError.replicaEpochRevoked
        }
        guard authority.state == .active,
              authority.replicaEpoch == replicaEpoch else {
            throw CloudReplicaCheckpointStoreError.replicaEpochMismatch
        }
        guard authority.configurationScopeFingerprint
            == configurationScopeFingerprint else {
            throw CloudReplicaCheckpointStoreError.configurationScopeMismatch
        }
        return authority
    }

    /// This gate is intentionally metadata-only. In particular it does not
    /// invoke durable reconciliation, decode files, or call `load`, because
    /// genesis must remain permanently closed when any prior replica evidence
    /// exists, regardless of whether that evidence is valid or recoverable.
    private func requireInitialBootstrapAvailabilityLocked(
        authority: ReplicaEpochAuthorityV2,
        locations: Locations
    ) throws {
        guard authority.pendingCheckpointHighWatermark == nil else {
            throw CloudReplicaCheckpointStoreError.checkpointPublicationPending
        }
        guard authority.checkpointHighWatermark == nil else {
            throw CloudReplicaCheckpointStoreError.initialBootstrapUnavailable
        }
        for evidenceURL in [
            locations.watermark,
            locations.primary,
            locations.backup,
            locations.quarantineDirectory,
        ] {
            guard try fileSystem.itemStatus(at: evidenceURL) == .missing else {
                throw CloudReplicaCheckpointStoreError
                    .initialBootstrapUnavailable
            }
        }
    }

    private func makeCurrentObservationLocked(
        accountID: CloudAccountID,
        configurationScopeFingerprint: CloudReplicaScopeFingerprint,
        replicaEpoch: UUID,
        loaded: CloudReplicaCheckpointLoadResult,
        locations: Locations,
        requireRememberedEpoch: Bool
    ) throws -> CloudReplicaCheckpointObservationV1 {
        let authority = try validatedActiveAuthorityLocked(
            accountID: accountID,
            configurationScopeFingerprint: configurationScopeFingerprint,
            replicaEpoch: replicaEpoch,
            locations: locations,
            requireRememberedEpoch: requireRememberedEpoch
        )
        guard authority.pendingCheckpointHighWatermark == nil else {
            throw CloudReplicaCheckpointStoreError.checkpointPublicationPending
        }

        let state: CloudReplicaCheckpointObservationStateV1
        if let checkpoint = loaded.checkpoint {
            guard checkpoint.accountID == accountID,
                  checkpoint.configurationScopeFingerprint
                    == configurationScopeFingerprint,
                  checkpoint.replicaEpoch == replicaEpoch else {
                throw CloudReplicaCheckpointStoreError.invalidCheckpoint
            }
            let exactWatermark = WatermarkV1(checkpoint: checkpoint)
            guard authority.checkpointHighWatermark == exactWatermark else {
                throw CloudReplicaCheckpointStoreError.invalidCheckpoint
            }
            state = .checkpoint(
                ProfileHydrationCheckpointIdentityV1(checkpoint: checkpoint)
            )
        } else {
            guard authority.checkpointHighWatermark == nil,
                  try fileSystem.reconcileDurableItem(at: locations.watermark)
                    == .missing,
                  try fileSystem.reconcileDurableItem(at: locations.primary)
                    == .missing,
                  try fileSystem.reconcileDurableItem(at: locations.backup)
                    == .missing else {
                throw CloudReplicaCheckpointStoreError.invalidCheckpoint
            }
            state = .absent
        }
        return CloudReplicaCheckpointObservationV1(
            accountID: accountID,
            configurationScopeFingerprint: configurationScopeFingerprint,
            replicaEpoch: replicaEpoch,
            state: state
        )
    }

    private func readAuthority(
        for accountID: CloudAccountID,
        locations: Locations
    ) throws -> ReplicaEpochAuthorityV2? {
        guard try fileSystem.reconcileDurableItem(at: locations.authority)
            == .present else {
            return nil
        }
        do {
            guard try fileSystem.fileSize(at: locations.authority) <= 64 * 1_024 else {
                throw CloudReplicaCheckpointStoreError.invalidCheckpoint
            }
            let authority = try JSONDecoder().decode(
                ReplicaEpochAuthorityV2.self,
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
        _ authority: ReplicaEpochAuthorityV2,
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
        try writeExactData(data, to: locations.authority)
    }

    private func removeAccountDirectoryIfPresent(_ locations: Locations) throws {
        // `removeItem` is intentionally called even when the target is absent:
        // its target-bound tombstone retry must clear residue left after a
        // prior durable rename and interrupted recursive cleanup.
        try removeDurablyReconciling(at: locations.accountDirectory)
    }

    private func validatedCopy(
        at url: URL,
        source: CloudReplicaCheckpointLoadSource,
        accountID: CloudAccountID,
        fingerprint: CloudReplicaScopeFingerprint,
        locations: Locations,
        quarantinedCount: inout Int
    ) throws -> StoredCopy? {
        guard try fileSystem.reconcileDurableItem(at: url) == .present else {
            return nil
        }
        do {
            let size = try fileSystem.fileSize(at: url)
            guard size >= 0 else {
                throw CloudReplicaCheckpointStoreError.invalidCheckpoint
            }
            if size > maximumEncodedCheckpointFileSize {
                _ = try discard(url)
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
        } catch let error as CloudReplicaCheckpointStoreError {
            switch error {
            case .ioFailure, .durabilityOutcomeUnknown:
                throw error
            default:
                break
            }
            if try quarantine(url, locations: locations) {
                quarantinedCount += 1
            }
            return nil
        } catch {
            if try quarantine(url, locations: locations) {
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
    ) throws -> WatermarkReadState {
        guard try fileSystem.reconcileDurableItem(at: url) == .present else {
            let priorInvalidWatermark = locations.quarantineDirectory
                .appendingPathComponent("checkpoint-watermark-corrupt.json")
            return try fileSystem.reconcileDurableItem(at: priorInvalidWatermark)
                == .present
                ? .invalid
                : .absent
        }
        do {
            let size = try fileSystem.fileSize(at: url)
            guard size >= 0 else {
                throw CloudReplicaCheckpointStoreError.invalidCheckpoint
            }
            if size > 64 * 1_024 {
                _ = try discard(url)
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
        } catch let error as CloudReplicaCheckpointStoreError {
            switch error {
            case .ioFailure, .durabilityOutcomeUnknown:
                throw error
            default:
                break
            }
            if try quarantine(url, locations: locations) {
                quarantinedCount += 1
            }
            return .invalid
        } catch {
            if try quarantine(url, locations: locations) {
                quarantinedCount += 1
            }
            return .invalid
        }
    }

    private func removeWatermarkEvidence(_ locations: Locations) throws {
        let corruptWatermark = locations.quarantineDirectory
            .appendingPathComponent("checkpoint-watermark-corrupt.json")
        for url in [locations.watermark, corruptWatermark] {
            if try fileSystem.reconcileDurableItem(at: url) == .present {
                try removeDurablyReconciling(at: url)
            }
        }
    }

    private func resolve(
        primary: StoredCopy?,
        backup: StoredCopy?,
        watermark: WatermarkV1?,
        preserving preservedWatermark: WatermarkV1? = nil,
        locations: Locations,
        quarantinedCount: inout Int
    ) throws -> StoredCopy? {
        if sameGenerationDiverges(primary, backup) {
            try quarantineAll(
                [primary, backup].compactMap { $0 },
                locations: locations,
                quarantinedCount: &quarantinedCount
            )
            return nil
        }

        guard let watermark else {
            guard let primary, let backup else {
                try quarantineAll(
                    [primary, backup].compactMap { $0 },
                    locations: locations,
                    quarantinedCount: &quarantinedCount
                )
                return nil
            }
            let primaryCheckpoint = primary.envelope.checkpoint
            let backupCheckpoint = backup.envelope.checkpoint
            guard primaryCheckpoint.replicaEpoch == backupCheckpoint.replicaEpoch else {
                try quarantineAll(
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
                if try quarantine(stale.url, locations: locations) {
                    quarantinedCount += 1
                }
                return winner
            }
            guard primaryCheckpoint == backupCheckpoint else {
                try quarantineAll(
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
            } else if try quarantine(storedCopy.url, locations: locations) {
                quarantinedCount += 1
            }
        }
        if eligible.count == 2,
           eligible[0].envelope.checkpoint != eligible[1].envelope.checkpoint {
            try quarantineAll(
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
    ) throws {
        for copy in copies {
            guard try fileSystem.reconcileDurableItem(at: copy.url) == .present else {
                continue
            }
            if try quarantine(copy.url, locations: locations) {
                quarantinedCount += 1
            }
        }
    }

    /// Quarantine is deliberately best-effort. Fixed source-specific slots cap
    /// retained payloads at primary, backup, and watermark regardless of how
    /// often corruption is encountered.
    private func quarantine(_ url: URL, locations: Locations) throws -> Bool {
        guard try fileSystem.reconcileDurableItem(at: url) == .present else {
            return false
        }
        let slot: String
        if url == locations.primary {
            slot = "checkpoint-primary-corrupt.json"
        } else if url == locations.backup {
            slot = "checkpoint-backup-corrupt.json"
        } else {
            slot = "checkpoint-watermark-corrupt.json"
        }
        let destination = locations.quarantineDirectory.appendingPathComponent(slot)
        let destinationStatus = try fileSystem.reconcileDurableItem(at: destination)
        do {
            try fileSystem.createDirectory(at: locations.quarantineDirectory)
            if destinationStatus == .present {
                try removeDurablyReconciling(at: destination)
            }
            try moveDurablyReconciling(at: url, to: destination)
            return true
        } catch CloudReplicaCheckpointStoreError.durabilityOutcomeUnknown {
            throw CloudReplicaCheckpointStoreError.durabilityOutcomeUnknown
        } catch {
            return false
        }
    }

    private func discard(_ url: URL) throws -> Bool {
        guard try fileSystem.reconcileDurableItem(at: url) == .present else {
            return false
        }
        do {
            try removeDurablyReconciling(at: url)
            return true
        } catch CloudReplicaCheckpointStoreError.durabilityOutcomeUnknown {
            throw CloudReplicaCheckpointStoreError.durabilityOutcomeUnknown
        } catch {
            return false
        }
    }

    private var maximumEncodedCheckpointFileSize: Int {
        let (maximum, overflow) = limits.maxTotalBytes.multipliedReportingOverflow(by: 8)
        return overflow ? Int.max : maximum
    }

    private func writeExactData(_ data: Data, to url: URL) throws {
        do {
            try fileSystem.writeAtomically(data, to: url)
        } catch CloudReplicaCheckpointStoreError.durabilityOutcomeUnknown {
            guard try confirmsExactData(data, at: url) else {
                throw CloudReplicaCheckpointStoreError.durabilityOutcomeUnknown
            }
            return
        }
        guard try confirmsExactData(data, at: url) else {
            throw CloudReplicaCheckpointStoreError.durabilityOutcomeUnknown
        }
    }

    private func confirmsExactData(_ expected: Data, at url: URL) throws -> Bool {
        guard try fileSystem.reconcileDurableItem(at: url) == .present,
              try fileSystem.fileSize(at: url) == expected.count else {
            return false
        }
        return try fileSystem.read(from: url) == expected
    }

    private func removeDurablyReconciling(at url: URL) throws {
        do {
            try fileSystem.removeItem(at: url)
        } catch CloudReplicaCheckpointStoreError.durabilityOutcomeUnknown {
            guard try fileSystem.reconcileDurableItem(at: url) == .missing else {
                throw CloudReplicaCheckpointStoreError.durabilityOutcomeUnknown
            }
            return
        }
        guard try fileSystem.reconcileDurableItem(at: url) == .missing else {
            throw CloudReplicaCheckpointStoreError.durabilityOutcomeUnknown
        }
    }

    private func moveDurablyReconciling(
        at sourceURL: URL,
        to destinationURL: URL
    ) throws {
        do {
            try fileSystem.moveItem(at: sourceURL, to: destinationURL)
        } catch CloudReplicaCheckpointStoreError.durabilityOutcomeUnknown {
            guard try fileSystem.reconcileDurableItem(at: sourceURL) == .missing,
                  try fileSystem.reconcileDurableItem(at: destinationURL)
                    == .present else {
                throw CloudReplicaCheckpointStoreError.durabilityOutcomeUnknown
            }
            return
        }
        guard try fileSystem.reconcileDurableItem(at: sourceURL) == .missing,
              try fileSystem.reconcileDurableItem(at: destinationURL) == .present else {
            throw CloudReplicaCheckpointStoreError.durabilityOutcomeUnknown
        }
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
}

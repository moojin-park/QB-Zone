import Foundation

private struct PersistedGameCenterDynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        return nil
    }
}

private func requireExactPersistedGameCenterKeys(
    _ decoder: Decoder,
    expected: Set<String>
) throws {
    let container = try decoder.container(
        keyedBy: PersistedGameCenterDynamicCodingKey.self
    )
    let actual = Set(container.allKeys.map(\.stringValue))
    guard actual == expected else {
        throw DecodingError.dataCorrupted(
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Unexpected persisted Game Center fields"
            )
        )
    }
}

enum AchievementRule: Codable, Equatable, Hashable, Sendable {
    case careerSuccessfulPasses(Int)
    case incrementalCareerSuccessfulPasses(Int)
    case careerTouchdowns(Int)
    case careerBonusTouchdowns(Int)
    case allLanesInSingleRun
    case singleRunAccuracy(percent: Int, minimumAttempts: Int)
    case singleRunTouchdownStreak(Int)
    case singleRunScore(Int)

    /// Exhaustive, value-bearing rule material used by the cloud scope. This
    /// intentionally describes evaluation semantics rather than Swift's
    /// synthesized enum encoding, because definitions are not themselves
    /// persisted in a player profile.
    var persistedFingerprintMaterial: [String] {
        switch self {
        case let .careerSuccessfulPasses(target):
            ["rule", "careerSuccessfulPasses", "target", String(target)]
        case let .incrementalCareerSuccessfulPasses(target):
            [
                "rule", "incrementalCareerSuccessfulPasses",
                "target", String(target),
            ]
        case let .careerTouchdowns(target):
            ["rule", "careerTouchdowns", "target", String(target)]
        case let .careerBonusTouchdowns(target):
            ["rule", "careerBonusTouchdowns", "target", String(target)]
        case .allLanesInSingleRun:
            ["rule", "allLanesInSingleRun"]
        case let .singleRunAccuracy(percent, minimumAttempts):
            [
                "rule", "singleRunAccuracy",
                "percent", String(percent),
                "minimumAttempts", String(minimumAttempts),
            ]
        case let .singleRunTouchdownStreak(target):
            ["rule", "singleRunTouchdownStreak", "target", String(target)]
        case let .singleRunScore(target):
            ["rule", "singleRunScore", "target", String(target)]
        }
    }
}

struct AchievementDefinition: Codable, Equatable, Hashable, Sendable {
    let id: AchievementID
    let displayName: String
    let detail: String
    let points: Int
    let rule: AchievementRule
}

struct AchievementProgress: Codable, Equatable, Sendable {
    let id: AchievementID
    var percentComplete: Int
    var completedAt: Date?

    init(id: AchievementID, percentComplete: Int = 0, completedAt: Date? = nil) {
        self.id = id
        self.percentComplete = min(100, max(0, percentComplete))
        self.completedAt = completedAt
    }

    var isCompleted: Bool {
        percentComplete == 100
    }
}

struct AchievementProgressUpdate: Codable, Equatable, Sendable {
    let previous: AchievementProgress
    let current: AchievementProgress
}

/// Exact V1-V3 on-disk shape. It remains decodable only so the V4 migrator can
/// quarantine work whose Game Center player provenance was never persisted.
/// New profiles must never store this type.
struct LegacyGameCenterSubmissionQueueV1: Codable, Equatable, Sendable {
    var pendingHighScore: Int
    var pendingAchievementPercents: [AchievementID: Int]

    private enum CodingKeys: String, CodingKey {
        case pendingHighScore
        case pendingAchievementPercents
    }

    init(
        pendingHighScore: Int = 0,
        pendingAchievementPercents: [AchievementID: Int] = [:]
    ) {
        self.pendingHighScore = pendingHighScore
        self.pendingAchievementPercents = pendingAchievementPercents
    }

    /// Legacy envelopes are quarantine inputs, not trusted submission
    /// authority. Even so, duplicate keys must fail closed rather than be
    /// collapsed before V4 migration can preserve the evidence.
    init(from decoder: Decoder) throws {
        try requireExactPersistedGameCenterKeys(
            decoder,
            expected: ["pendingHighScore", "pendingAchievementPercents"]
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pendingHighScore = try container.decode(
            Int.self,
            forKey: .pendingHighScore
        )
        let dictionaryDecoder = try container.superDecoder(
            forKey: .pendingAchievementPercents
        )
        var pairs = try dictionaryDecoder.unkeyedContainer()
        var decoded: [AchievementID: Int] = [:]
        while !pairs.isAtEnd {
            let achievementID = try pairs.decode(AchievementID.self)
            guard !pairs.isAtEnd else {
                throw DecodingError.dataCorruptedError(
                    in: pairs,
                    debugDescription: "Legacy pending achievement dictionary has an unmatched key"
                )
            }
            let percent = try pairs.decode(Int.self)
            guard decoded[achievementID] == nil else {
                throw DecodingError.dataCorruptedError(
                    in: pairs,
                    debugDescription: "Legacy pending achievement dictionary contains a duplicate ID"
                )
            }
            decoded[achievementID] = percent
        }
        pendingAchievementPercents = decoded
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pendingHighScore, forKey: .pendingHighScore)
        try container.encode(
            pendingAchievementPercents,
            forKey: .pendingAchievementPercents
        )
    }
}

/// Durable maxima for exactly one Game Center provenance class. A value is
/// either stored under one verified player ID or in the explicit unbound
/// quarantine; it is never implicitly reassigned between the two.
struct GameCenterPendingMaximaV1: Codable, Equatable, Sendable {
    var pendingHighScore: Int
    var pendingAchievementPercents: [AchievementID: Int]

    private enum CodingKeys: String, CodingKey {
        case pendingHighScore
        case pendingAchievementPercents
    }

    init(
        pendingHighScore: Int = 0,
        pendingAchievementPercents: [AchievementID: Int] = [:]
    ) {
        self.pendingHighScore = pendingHighScore
        self.pendingAchievementPercents = pendingAchievementPercents
    }

    /// Swift's synthesized dictionary decoder accepts duplicate keys in the
    /// alternating-key JSON representation and silently keeps the final value.
    /// Reject duplicates at the persistence boundary so canonicalization can
    /// never erase conflicting Game Center authority.
    init(from decoder: Decoder) throws {
        try requireExactPersistedGameCenterKeys(
            decoder,
            expected: ["pendingHighScore", "pendingAchievementPercents"]
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pendingHighScore = try container.decode(
            Int.self,
            forKey: .pendingHighScore
        )
        let dictionaryDecoder = try container.superDecoder(
            forKey: .pendingAchievementPercents
        )
        var pairs = try dictionaryDecoder.unkeyedContainer()
        var decoded: [AchievementID: Int] = [:]
        while !pairs.isAtEnd {
            let achievementID = try pairs.decode(AchievementID.self)
            guard !pairs.isAtEnd else {
                throw DecodingError.dataCorruptedError(
                    in: pairs,
                    debugDescription: "Pending achievement dictionary has an unmatched key"
                )
            }
            let percent = try pairs.decode(Int.self)
            guard decoded[achievementID] == nil else {
                throw DecodingError.dataCorruptedError(
                    in: pairs,
                    debugDescription: "Pending achievement dictionary contains a duplicate ID"
                )
            }
            decoded[achievementID] = percent
        }
        pendingAchievementPercents = decoded
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pendingHighScore, forKey: .pendingHighScore)
        try container.encode(
            pendingAchievementPercents,
            forKey: .pendingAchievementPercents
        )
    }

    var isEmpty: Bool {
        pendingHighScore == 0
            && pendingAchievementPercents.values.allSatisfy { $0 == 0 }
    }

    mutating func enqueueHighScore(_ score: Int) {
        pendingHighScore = max(pendingHighScore, max(0, score))
    }

    mutating func enqueueAchievement(_ progress: AchievementProgress) {
        enqueueAchievement(
            id: progress.id,
            percentComplete: progress.percentComplete
        )
    }

    mutating func enqueueAchievement(
        id: AchievementID,
        percentComplete: Int
    ) {
        let normalized = min(100, max(0, percentComplete))
        pendingAchievementPercents[id] = max(
            pendingAchievementPercents[id, default: 0],
            normalized
        )
    }

    mutating func mergeMaxima(from other: Self) {
        enqueueHighScore(other.pendingHighScore)
        for (achievementID, percent) in other.pendingAchievementPercents {
            enqueueAchievement(id: achievementID, percentComplete: percent)
        }
    }
}

/// Canonical V4 Game Center queue. Bound buckets are sparse and player-scoped;
/// unbound work is durable but deliberately has no submission or claim API.
struct PlayerScopedGameCenterQueueV1: Codable, Equatable, Sendable {
    /// A defensive persistence bound. Gameplay never evicts an existing player
    /// or fails when this is reached: new attribution falls back to unbound.
    static let maximumPlayerBucketCount = 8

    var pendingByPlayerID: [GameCenterPlayerID: GameCenterPendingMaximaV1]
    var unboundPending: GameCenterPendingMaximaV1

    private enum CodingKeys: String, CodingKey {
        case pendingByPlayerID
        case unboundPending
    }

    init(
        pendingByPlayerID: [
            GameCenterPlayerID: GameCenterPendingMaximaV1
        ] = [:],
        unboundPending: GameCenterPendingMaximaV1 = GameCenterPendingMaximaV1()
    ) {
        self.pendingByPlayerID = pendingByPlayerID
        self.unboundPending = unboundPending
    }

    /// Duplicate player IDs are ambiguous submission authority. Decode the
    /// alternating-key representation explicitly instead of accepting
    /// Dictionary's last-value-wins behavior.
    init(from decoder: Decoder) throws {
        try requireExactPersistedGameCenterKeys(
            decoder,
            expected: ["pendingByPlayerID", "unboundPending"]
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let dictionaryDecoder = try container.superDecoder(
            forKey: .pendingByPlayerID
        )
        var pairs = try dictionaryDecoder.unkeyedContainer()
        var decoded: [GameCenterPlayerID: GameCenterPendingMaximaV1] = [:]
        while !pairs.isAtEnd {
            let playerID = try pairs.decode(GameCenterPlayerID.self)
            guard !pairs.isAtEnd else {
                throw DecodingError.dataCorruptedError(
                    in: pairs,
                    debugDescription: "Player-scoped Game Center dictionary has an unmatched key"
                )
            }
            let pending = try pairs.decode(GameCenterPendingMaximaV1.self)
            guard decoded[playerID] == nil else {
                throw DecodingError.dataCorruptedError(
                    in: pairs,
                    debugDescription: "Player-scoped Game Center dictionary contains a duplicate player ID"
                )
            }
            decoded[playerID] = pending
        }
        pendingByPlayerID = decoded
        unboundPending = try container.decode(
            GameCenterPendingMaximaV1.self,
            forKey: .unboundPending
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pendingByPlayerID, forKey: .pendingByPlayerID)
        try container.encode(unboundPending, forKey: .unboundPending)
    }

    init(quarantining legacy: LegacyGameCenterSubmissionQueueV1) {
        pendingByPlayerID = [:]
        unboundPending = GameCenterPendingMaximaV1(
            pendingHighScore: legacy.pendingHighScore,
            pendingAchievementPercents: legacy.pendingAchievementPercents
                .filter { $0.value != 0 }
        )
    }

    func pending(for playerID: GameCenterPlayerID) -> GameCenterPendingMaximaV1? {
        pendingByPlayerID[playerID]
    }

    mutating func enqueueUnboundHighScore(_ score: Int) {
        unboundPending.enqueueHighScore(score)
    }

    mutating func enqueueUnboundAchievement(_ progress: AchievementProgress) {
        unboundPending.enqueueAchievement(progress)
    }

    mutating func enqueueUnboundAchievement(
        id: AchievementID,
        percentComplete: Int
    ) {
        unboundPending.enqueueAchievement(
            id: id,
            percentComplete: percentComplete
        )
    }

    /// Returns false when the player ID is invalid or a new player bucket
    /// cannot be admitted. The value is safely quarantined as unbound either
    /// way, so attribution failure never interrupts gameplay.
    @discardableResult
    mutating func enqueueHighScore(
        _ score: Int,
        for playerID: GameCenterPlayerID
    ) -> Bool {
        guard score > 0 else { return true }
        guard GameCenterPlayerIDRuleV1.isValid(playerID) else {
            enqueueUnboundHighScore(score)
            return false
        }
        guard pendingByPlayerID[playerID] != nil
                || pendingByPlayerID.count < Self.maximumPlayerBucketCount else {
            enqueueUnboundHighScore(score)
            return false
        }
        var pending = pendingByPlayerID[playerID] ?? GameCenterPendingMaximaV1()
        pending.enqueueHighScore(score)
        pendingByPlayerID[playerID] = pending
        return true
    }

    /// Returns false when the player ID is invalid or a new player bucket
    /// cannot be admitted. The value is safely quarantined as unbound either
    /// way, so attribution failure never interrupts gameplay.
    @discardableResult
    mutating func enqueueAchievement(
        id: AchievementID,
        percentComplete: Int,
        for playerID: GameCenterPlayerID
    ) -> Bool {
        guard percentComplete > 0 else { return true }
        guard GameCenterPlayerIDRuleV1.isValid(playerID) else {
            enqueueUnboundAchievement(
                id: id,
                percentComplete: percentComplete
            )
            return false
        }
        guard pendingByPlayerID[playerID] != nil
                || pendingByPlayerID.count < Self.maximumPlayerBucketCount else {
            enqueueUnboundAchievement(
                id: id,
                percentComplete: percentComplete
            )
            return false
        }
        var pending = pendingByPlayerID[playerID] ?? GameCenterPendingMaximaV1()
        pending.enqueueAchievement(id: id, percentComplete: percentComplete)
        pendingByPlayerID[playerID] = pending
        return true
    }

    @discardableResult
    mutating func acknowledge(_ batch: GameCenterSubmissionBatch) -> Bool {
        guard var current = pendingByPlayerID[batch.playerID] else { return false }

        if let submittedScore = batch.highScore,
           current.pendingHighScore > 0,
           current.pendingHighScore <= submittedScore {
            current.pendingHighScore = 0
        }
        for submitted in batch.achievements {
            guard let pending = current.pendingAchievementPercents[submitted.id],
                  pending <= submitted.percentComplete else {
                continue
            }
            current.pendingAchievementPercents.removeValue(forKey: submitted.id)
        }

        if current.isEmpty {
            pendingByPlayerID.removeValue(forKey: batch.playerID)
        } else {
            pendingByPlayerID[batch.playerID] = current
        }
        // The exact player bucket existed and was therefore handled. Values
        // newer than the submitted maxima intentionally survive, but that is
        // still a successful acknowledgement of this batch.
        return true
    }
}

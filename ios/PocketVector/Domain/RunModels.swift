import Foundation

extension LaneID: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        guard let lane = LaneID(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown lane identifier: \(rawValue)"
            )
        }
        self = lane
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension LaneID: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(rawValue)
    }
}

extension LaneID: @unchecked Sendable {}

enum RunFinishReason: String, Codable, CaseIterable, Equatable, Sendable {
    case timerExpired
    case abandoned
    case debugPreview

    static var persistedCaseManifest: String {
        allCases.map(\.rawValue).sorted().joined(separator: ",")
    }
}

struct RunConfiguration: Codable, Equatable, Hashable, Sendable {
    let runID: RunID
    let randomSeed: UInt32
    let offenseTeamID: TeamID
    let offenseJerseyID: JerseyID
    let defenseTeamID: TeamID
    let defenseJerseyID: JerseyID
    let footballID: FootballID
    let economyVersion: Int
    let startedAt: Date

    enum CodingKeys: String, CodingKey, CaseIterable {
        case runID
        case randomSeed
        case offenseTeamID
        case offenseJerseyID
        case defenseTeamID
        case defenseJerseyID
        case footballID
        case economyVersion
        case startedAt
    }

    static var persistedFieldManifest: String {
        CodingKeys.allCases.map(\.rawValue).sorted().joined(separator: ",")
    }
}

struct RunStatisticsSnapshot: Codable, Equatable, Sendable {
    static let achievementDependencySemanticIdentifier =
        "pocket-vector-run-statistics-achievement-dependencies-v1"
    static let successfulPassesPolicyIdentifier =
        "completions-plus-touchdowns-native-int-v1"
    static let accuracyPolicyIdentifier =
        "attempts-gte-minimum-and-positive-then-successful-passes-times-100-gte-attempts-times-percent-native-int-v1"

    var attempts: Int
    var completions: Int
    var touchdowns: Int
    var incompletions: Int
    var interceptions: Int
    var longestTouchdownStreak: Int

    enum CodingKeys: String, CodingKey, CaseIterable {
        case attempts
        case completions
        case touchdowns
        case incompletions
        case interceptions
        case longestTouchdownStreak
    }

    static var persistedFieldManifest: String {
        CodingKeys.allCases.map(\.rawValue).sorted().joined(separator: ",")
    }

    static var achievementDependencyFingerprintMaterial: [String] {
        [
            achievementDependencySemanticIdentifier,
            "successfulPassesPolicy", successfulPassesPolicyIdentifier,
            "accuracyPolicy", accuracyPolicyIdentifier,
        ]
    }

    init(
        attempts: Int = 0,
        completions: Int = 0,
        touchdowns: Int = 0,
        incompletions: Int = 0,
        interceptions: Int = 0,
        longestTouchdownStreak: Int = 0
    ) {
        self.attempts = max(0, attempts)
        self.completions = max(0, completions)
        self.touchdowns = max(0, touchdowns)
        self.incompletions = max(0, incompletions)
        self.interceptions = max(0, interceptions)
        self.longestTouchdownStreak = max(0, longestTouchdownStreak)
    }

    var successfulPasses: Int {
        completions + touchdowns
    }

    func meetsAccuracy(percent: Int, minimumAttempts: Int = 0) -> Bool {
        guard attempts >= minimumAttempts, attempts > 0 else { return false }
        return successfulPasses * 100 >= attempts * percent
    }

    var displayedAccuracyPercent: Int {
        guard attempts > 0 else { return 0 }
        return Int((Double(successfulPasses) / Double(attempts) * 100).rounded())
    }
}

struct CompletedRun: Codable, Equatable, Sendable {
    static let achievementEligibilitySemanticIdentifier =
        "pocket-vector-completed-run-achievement-eligibility-v1"
    static let naturalCompletionMinimumElapsedGameplayMilliseconds = 60_000
    static let naturalCompletionElapsedComparisonIdentifier =
        "greater-than-or-equal-v1"

    let configuration: RunConfiguration
    let endedAt: Date
    let elapsedGameplayMilliseconds: Int
    let finishReason: RunFinishReason
    let score: Int
    let statistics: RunStatisticsSnapshot
    let completedLaneIDs: Set<LaneID>
    let bonusTouchdownCount: Int

    enum CodingKeys: String, CodingKey, CaseIterable {
        case configuration
        case endedAt
        case elapsedGameplayMilliseconds
        case finishReason
        case score
        case statistics
        case completedLaneIDs
        case bonusTouchdownCount
    }

    static var persistedFieldManifest: String {
        CodingKeys.allCases.map(\.rawValue).sorted().joined(separator: ",")
    }

    static var achievementEligibilityFingerprintMaterial: [String] {
        [
            achievementEligibilitySemanticIdentifier,
            "requiredFinishReason", RunFinishReason.timerExpired.rawValue,
            "minimumElapsedGameplayMilliseconds",
            String(naturalCompletionMinimumElapsedGameplayMilliseconds),
            "elapsedComparison",
            naturalCompletionElapsedComparisonIdentifier,
        ]
    }

    var runID: RunID { configuration.runID }

    var isNaturallyCompleted: Bool {
        finishReason == .timerExpired
            && elapsedGameplayMilliseconds
                >= Self.naturalCompletionMinimumElapsedGameplayMilliseconds
    }

    var isRewardEligible: Bool {
        isNaturallyCompleted && statistics.attempts >= EconomyConfiguration.minimumRewardAttempts
    }
}

struct CompletedRunRecord: Codable, Equatable, Sendable {
    let run: CompletedRun
    let recordedAt: Date
    let rewardCoins: Int64

    enum CodingKeys: String, CodingKey, CaseIterable {
        case run
        case recordedAt
        case rewardCoins
    }

    static var persistedFieldManifest: String {
        CodingKeys.allCases.map(\.rawValue).sorted().joined(separator: ",")
    }
}

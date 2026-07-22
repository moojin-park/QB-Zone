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
    static let achievementFactsSemanticIdentifier =
        "pocket-vector-completed-run-achievement-facts-v1"
    static let naturalCompletionMinimumElapsedGameplayMilliseconds = 60_000
    static let naturalCompletionElapsedComparisonIdentifier =
        "greater-than-or-equal-v1"
    static let deepCompletionCountPolicyIdentifier =
        "count-authoritative-resolution-when-outcome-completion-and-lane-deep-v1"
    static let maximumOverdriveTouchdownCountPolicyIdentifier =
        "count-authoritative-same-play-touchdown-with-bonus-active-and-capped-three-x-multiplier-v1"
    static let achievementNotificationAuthorityPolicyIdentifier =
        "simulation-resolution-not-feedback-audio-or-ui-delivery-v1"
    static let legacyAchievementFactsDefaultPolicyIdentifier =
        "missing-deep-and-maximum-overdrive-facts-default-to-zero-without-inference-v1"
    static let achievementFactsStructuralValidationPolicyIdentifier =
        "deep-lte-completions-and-deep-lane-when-positive-maximum-overdrive-lte-touchdowns-and-bonus-and-touchdown-lane-when-positive-v1"

    let configuration: RunConfiguration
    let endedAt: Date
    let elapsedGameplayMilliseconds: Int
    let finishReason: RunFinishReason
    let score: Int
    let statistics: RunStatisticsSnapshot
    let completedLaneIDs: Set<LaneID>
    let bonusTouchdownCount: Int
    let deepCompletionCount: Int
    let maximumOverdriveTouchdownCount: Int

    enum CodingKeys: String, CodingKey, CaseIterable {
        case configuration
        case endedAt
        case elapsedGameplayMilliseconds
        case finishReason
        case score
        case statistics
        case completedLaneIDs
        case bonusTouchdownCount
        case deepCompletionCount
        case maximumOverdriveTouchdownCount
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

    static var achievementFactsFingerprintMaterial: [String] {
        [
            achievementFactsSemanticIdentifier,
            "deepCompletionCountPolicy", deepCompletionCountPolicyIdentifier,
            "maximumOverdriveTouchdownCountPolicy",
            maximumOverdriveTouchdownCountPolicyIdentifier,
            "notificationAuthorityPolicy",
            achievementNotificationAuthorityPolicyIdentifier,
            "legacyDefaultPolicy", legacyAchievementFactsDefaultPolicyIdentifier,
            "structuralValidationPolicy",
            achievementFactsStructuralValidationPolicyIdentifier,
            "legacyDeepCompletionCount", "0",
            "legacyMaximumOverdriveTouchdownCount", "0",
        ]
    }

    init(
        configuration: RunConfiguration,
        endedAt: Date,
        elapsedGameplayMilliseconds: Int,
        finishReason: RunFinishReason,
        score: Int,
        statistics: RunStatisticsSnapshot,
        completedLaneIDs: Set<LaneID>,
        bonusTouchdownCount: Int,
        deepCompletionCount: Int = 0,
        maximumOverdriveTouchdownCount: Int = 0
    ) {
        self.configuration = configuration
        self.endedAt = endedAt
        self.elapsedGameplayMilliseconds = elapsedGameplayMilliseconds
        self.finishReason = finishReason
        self.score = score
        self.statistics = statistics
        self.completedLaneIDs = completedLaneIDs
        self.bonusTouchdownCount = bonusTouchdownCount
        self.deepCompletionCount = max(0, deepCompletionCount)
        self.maximumOverdriveTouchdownCount = max(
            0,
            maximumOverdriveTouchdownCount
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        configuration = try container.decode(
            RunConfiguration.self,
            forKey: .configuration
        )
        endedAt = try container.decode(Date.self, forKey: .endedAt)
        elapsedGameplayMilliseconds = try container.decode(
            Int.self,
            forKey: .elapsedGameplayMilliseconds
        )
        finishReason = try container.decode(
            RunFinishReason.self,
            forKey: .finishReason
        )
        score = try container.decode(Int.self, forKey: .score)
        statistics = try container.decode(
            RunStatisticsSnapshot.self,
            forKey: .statistics
        )
        completedLaneIDs = try container.decode(
            Set<LaneID>.self,
            forKey: .completedLaneIDs
        )
        bonusTouchdownCount = try container.decode(
            Int.self,
            forKey: .bonusTouchdownCount
        )
        deepCompletionCount = try container.decodeIfPresent(
            Int.self,
            forKey: .deepCompletionCount
        ) ?? 0
        maximumOverdriveTouchdownCount = try container.decodeIfPresent(
            Int.self,
            forKey: .maximumOverdriveTouchdownCount
        ) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(configuration, forKey: .configuration)
        try container.encode(endedAt, forKey: .endedAt)
        try container.encode(
            elapsedGameplayMilliseconds,
            forKey: .elapsedGameplayMilliseconds
        )
        try container.encode(finishReason, forKey: .finishReason)
        try container.encode(score, forKey: .score)
        try container.encode(statistics, forKey: .statistics)
        try container.encode(completedLaneIDs, forKey: .completedLaneIDs)
        try container.encode(bonusTouchdownCount, forKey: .bonusTouchdownCount)
        try container.encode(deepCompletionCount, forKey: .deepCompletionCount)
        try container.encode(
            maximumOverdriveTouchdownCount,
            forKey: .maximumOverdriveTouchdownCount
        )
    }

    /// Structural facts PM-owned persistence validation must enforce before
    /// replaying achievement progress from decoded completed-run history.
    var achievementFactsAreStructurallyValid: Bool {
        guard deepCompletionCount >= 0,
              deepCompletionCount <= statistics.completions,
              maximumOverdriveTouchdownCount >= 0,
              maximumOverdriveTouchdownCount <= statistics.touchdowns,
              maximumOverdriveTouchdownCount <= bonusTouchdownCount else {
            return false
        }
        if deepCompletionCount > 0, !completedLaneIDs.contains(.deep) {
            return false
        }
        if maximumOverdriveTouchdownCount > 0,
           !completedLaneIDs.contains(.touchdown) {
            return false
        }
        return true
    }

    var runID: RunID { configuration.runID }

    var isNaturallyCompleted: Bool {
        finishReason == .timerExpired
            && elapsedGameplayMilliseconds
                >= Self.naturalCompletionMinimumElapsedGameplayMilliseconds
    }

    var isRewardEligible: Bool {
        RunRewardCalculator.isRewardEligible(self)
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

import Foundation

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

struct GameCenterSubmissionQueue: Codable, Equatable, Sendable {
    var pendingHighScore: Int
    var pendingAchievementPercents: [AchievementID: Int]

    init(
        pendingHighScore: Int = 0,
        pendingAchievementPercents: [AchievementID: Int] = [:]
    ) {
        self.pendingHighScore = max(0, pendingHighScore)
        self.pendingAchievementPercents = pendingAchievementPercents.mapValues {
            min(100, max(0, $0))
        }
    }

    mutating func enqueueHighScore(_ score: Int) {
        pendingHighScore = max(pendingHighScore, score)
    }

    mutating func enqueueAchievement(_ progress: AchievementProgress) {
        pendingAchievementPercents[progress.id] = max(
            pendingAchievementPercents[progress.id, default: 0],
            progress.percentComplete
        )
    }
}

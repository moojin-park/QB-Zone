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

enum RunFinishReason: String, Codable, Equatable, Sendable {
    case timerExpired
    case abandoned
    case debugPreview
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
}

struct RunStatisticsSnapshot: Codable, Equatable, Sendable {
    var attempts: Int
    var completions: Int
    var touchdowns: Int
    var incompletions: Int
    var interceptions: Int
    var longestTouchdownStreak: Int

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
    let configuration: RunConfiguration
    let endedAt: Date
    let elapsedGameplayMilliseconds: Int
    let finishReason: RunFinishReason
    let score: Int
    let statistics: RunStatisticsSnapshot
    let completedLaneIDs: Set<LaneID>
    let bonusTouchdownCount: Int

    var runID: RunID { configuration.runID }

    var isNaturallyCompleted: Bool {
        finishReason == .timerExpired && elapsedGameplayMilliseconds >= 60_000
    }

    var isRewardEligible: Bool {
        isNaturallyCompleted && statistics.attempts >= EconomyConfiguration.minimumRewardAttempts
    }
}

struct CompletedRunRecord: Codable, Equatable, Sendable {
    let run: CompletedRun
    let recordedAt: Date
    let rewardCoins: Int64
}

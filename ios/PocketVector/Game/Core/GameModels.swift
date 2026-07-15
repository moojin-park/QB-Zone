import CoreGraphics
import Foundation

enum GamePhase: Equatable {
    case title
    case countdown
    case playing
    case resolvingFinalBall
    case paused
    case results
}

enum LaneID: String, CaseIterable, Equatable {
    case short
    case medium
    case deep
    case touchdown
}

enum PassOutcome: Equatable {
    case completion
    case touchdown
    case incompletion
    case interception
}

struct WorldPoint: Equatable {
    var x: CGFloat
    var depth: CGFloat
    var height: CGFloat
}

struct LaneConfig: Equatable {
    let id: LaneID
    let label: String
    let depth: CGFloat
    let completionPoints: Int
    let meterGain: Int
    let crossingSeconds: CGFloat
    let catchWidth: CGFloat
}

struct ReceiverState: Identifiable, Equatable {
    let id: Int
    let laneID: LaneID
    var x: CGFloat
    var direction: CGFloat
    var speedPerMillisecond: CGFloat
    var animationMilliseconds: CGFloat
    var pose: Pose = .run
    var hasCaught = false

    enum Pose: Equatable {
        case run
        case `catch`
        case celebrate
    }
}

struct DefenderState: Identifiable, Equatable {
    let id: Int
    let depth: CGFloat
    var x: CGFloat
    var direction: CGFloat
    let speedPerMillisecond: CGFloat
    var animationMilliseconds: CGFloat
    var pose: Pose = .run

    enum Pose: Equatable {
        case run
        case intercept
    }
}

struct BallState: Equatable {
    let id: Int
    var elapsedMilliseconds: CGFloat
    let durationMilliseconds: CGFloat
    let start: WorldPoint
    let target: WorldPoint
    let end: WorldPoint
    let arcHeight: CGFloat
    var current: WorldPoint
    var previous: WorldPoint
    var rollRadians: CGFloat
    let radiusPixels: CGFloat
    let releaseSpeedPixelsPerMillisecond: CGFloat
    let aimMarker: CGPoint
}

struct RunStatistics: Equatable {
    var attempts = 0
    var completions = 0
    var touchdowns = 0
    var incompletions = 0
    var interceptions = 0
    var longestTouchdownStreak = 0

    var accuracy: Int {
        guard attempts > 0 else { return 0 }
        return Int((Double(completions + touchdowns) / Double(attempts) * 100).rounded())
    }
}

struct FeedbackState: Equatable {
    let headline: String
    let detail: String
    let tone: Tone
    var remainingMilliseconds: CGFloat

    enum Tone: Equatable {
        case positive
        case touchdown
        case negative
        case bonus
    }
}

struct PlayScoreResult: Equatable {
    let outcome: PassOutcome
    let laneID: LaneID?
    let basePoints: Int
    let bonusWasActive: Bool
    let bonusPoints: Int
    let touchdownMultiplier: CGFloat
    let awardedPoints: Int
    let totalBefore: Int
    let totalAfter: Int
    let meterBefore: Int
    let meterAfter: Int
    let streakBefore: Int
    let streakAfter: Int
}

struct GameState: Equatable {
    var phase: GamePhase = .title
    var phaseBeforePause: GamePhase?
    var countdownRemainingMilliseconds: CGFloat = 3_000
    var remainingMilliseconds: CGFloat = GameplayConfig.sessionDurationMilliseconds
    var elapsedGameplayMilliseconds: CGFloat = 0
    var finalBallGraceRemainingMilliseconds: CGFloat = GameplayConfig.finalBallGraceMilliseconds
    var score = 0
    var touchdownMeter = 0
    var touchdownStreak = 0
    var receivers: [ReceiverState] = []
    var defenders: [DefenderState] = []
    var ball: BallState?
    var nextEntityID = 1
    var laneSpawnTimers: [LaneID: CGFloat] = [:]
    var playCooldownMilliseconds: CGFloat = 0
    var feedback: FeedbackState?
    var lastPlayScore: PlayScoreResult?
    var statistics = RunStatistics()
    var randomState = GameplayConfig.defaultSeed
}

struct UpdateResult: Equatable {
    var passResolved: PassOutcome?
    var laneID: LaneID?
    var scoreChanged = false
    var runFinished = false
}

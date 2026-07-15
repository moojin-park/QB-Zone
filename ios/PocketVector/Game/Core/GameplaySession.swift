import CoreGraphics
import Foundation

struct GameSettingsProjection: Equatable, Sendable {
    let musicVolume: Float
    let sfxVolume: Float
    let isMuted: Bool
    let reducedMotion: Bool

    init(_ settings: PlayerSettings) {
        musicVolume = Float(min(1, max(0, settings.musicVolume)))
        sfxVolume = Float(min(1, max(0, settings.sfxVolume)))
        isMuted = settings.isMuted
        reducedMotion = settings.reducedMotion
    }
}

struct GameplaySessionStep: Equatable {
    let update: UpdateResult
    let completedRun: CompletedRun?

    static var idle: GameplaySessionStep {
        GameplaySessionStep(update: UpdateResult(), completedRun: nil)
    }
}

struct GameplayRunRecorder: Equatable {
    private(set) var completedLaneIDs: Set<LaneID> = []
    private(set) var bonusTouchdownCount = 0

    mutating func record(
        update: UpdateResult,
        playScore: PlayScoreResult?
    ) {
        guard let outcome = update.passResolved else { return }

        if outcome == .completion || outcome == .touchdown,
           let laneID = update.laneID {
            completedLaneIDs.insert(laneID)
        }

        if outcome == .touchdown, playScore?.bonusWasActive == true {
            bonusTouchdownCount += 1
        }
    }

    func makeCompletedRun(
        configuration: RunConfiguration,
        state: GameState,
        finishReason: RunFinishReason,
        endedAt: Date
    ) -> CompletedRun {
        let statistics = state.statistics
        return CompletedRun(
            configuration: configuration,
            endedAt: max(endedAt, configuration.startedAt),
            elapsedGameplayMilliseconds: max(
                0,
                Int(state.elapsedGameplayMilliseconds.rounded())
            ),
            finishReason: finishReason,
            score: max(0, state.score),
            statistics: RunStatisticsSnapshot(
                attempts: statistics.attempts,
                completions: statistics.completions,
                touchdowns: statistics.touchdowns,
                incompletions: statistics.incompletions,
                interceptions: statistics.interceptions,
                longestTouchdownStreak: statistics.longestTouchdownStreak
            ),
            completedLaneIDs: completedLaneIDs,
            bonusTouchdownCount: bonusTouchdownCount
        )
    }
}

/// Production boundary around the deterministic simulation.
///
/// This value owns only one configured run. It cannot restart itself, and its
/// completion gate returns at most one `CompletedRun` across natural finish,
/// abandon requests, repeated frames, and repeated exit taps.
struct GameplaySession {
    let configuration: RunConfiguration
    let settings: GameSettingsProjection

    private(set) var simulation: GameSimulation
    private(set) var isApplicationActive = true
    private(set) var completedRun: CompletedRun?
    private var recorder = GameplayRunRecorder()

    init(configuration: RunConfiguration, settings: PlayerSettings) {
        self.configuration = configuration
        self.settings = GameSettingsProjection(settings)
        var simulation = GameSimulation(seed: configuration.randomSeed)
        simulation.startRun()
        self.simulation = simulation
    }

    var state: GameState { simulation.state }
    var canThrow: Bool { completedRun == nil && simulation.canThrow }

    @discardableResult
    mutating func throwBall(
        target: WorldPoint,
        releaseSpeedPixelsPerMillisecond: CGFloat,
        aimMarker: CGPoint
    ) -> Bool {
        guard completedRun == nil else { return false }
        return simulation.throwBall(
            target: target,
            releaseSpeedPixelsPerMillisecond: releaseSpeedPixelsPerMillisecond,
            aimMarker: aimMarker
        )
    }

    mutating func togglePause() {
        guard completedRun == nil, isApplicationActive else { return }
        simulation.togglePause()
    }

    mutating func setApplicationActive(_ isActive: Bool) {
        guard isApplicationActive != isActive else { return }
        isApplicationActive = isActive

        if !isActive,
           state.phase == .playing || state.phase == .resolvingFinalBall {
            simulation.togglePause()
        }
    }

    mutating func advance(
        deltaMilliseconds: CGFloat,
        endedAt: Date
    ) -> GameplaySessionStep {
        guard completedRun == nil, isApplicationActive else { return .idle }

        let update = simulation.update(deltaMilliseconds: deltaMilliseconds)
        recorder.record(update: update, playScore: simulation.state.lastPlayScore)

        guard update.runFinished else {
            return GameplaySessionStep(update: update, completedRun: nil)
        }

        let run = recorder.makeCompletedRun(
            configuration: configuration,
            state: simulation.state,
            finishReason: .timerExpired,
            endedAt: endedAt
        )
        completedRun = run
        return GameplaySessionStep(update: update, completedRun: run)
    }

    mutating func abandon(endedAt: Date) -> CompletedRun? {
        guard completedRun == nil else { return nil }

        let run = recorder.makeCompletedRun(
            configuration: configuration,
            state: simulation.state,
            finishReason: .abandoned,
            endedAt: endedAt
        )
        completedRun = run
        return run
    }
}

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

/// The exact live statistics surface consumed by the paused presentation.
struct LiveGameplayStatisticsSnapshot: Equatable, Sendable {
    let attempts: Int
    let successfulCompletions: Int
    let completionPercentage: Int
    let touchdowns: Int

    init(statistics: RunStatistics) {
        let completedRunStatistics = statistics.completedRunSnapshot
        attempts = completedRunStatistics.attempts
        successfulCompletions = completedRunStatistics.successfulPasses
        completionPercentage = completedRunStatistics.displayedAccuracyPercent
        touchdowns = completedRunStatistics.touchdowns
    }
}

/// Read-only gameplay state published to app-owned presentation adapters.
struct GameplaySceneSnapshot: Equatable, Sendable {
    let isPaused: Bool
    let defersBottomSystemGestures: Bool
    let statistics: LiveGameplayStatisticsSnapshot

    init(state: GameState) {
        isPaused = state.phase == .paused
        defersBottomSystemGestures = state.phase == .countdown
            || state.phase == .playing
            || state.phase == .resolvingFinalBall
        statistics = LiveGameplayStatisticsSnapshot(statistics: state.statistics)
    }
}

struct GameplaySnapshotPublicationGate: Equatable {
    private(set) var lastSnapshot: GameplaySceneSnapshot?

    mutating func accept(_ snapshot: GameplaySceneSnapshot) -> Bool {
        guard snapshot != lastSnapshot else { return false }

        lastSnapshot = snapshot
        return true
    }
}

extension RunStatistics {
    var completedRunSnapshot: RunStatisticsSnapshot {
        RunStatisticsSnapshot(
            attempts: attempts,
            completions: completions,
            touchdowns: touchdowns,
            incompletions: incompletions,
            interceptions: interceptions,
            longestTouchdownStreak: longestTouchdownStreak
        )
    }
}

struct GameplayRunRecorder: Equatable {
    private(set) var completedLaneIDs: Set<LaneID> = []
    private(set) var bonusTouchdownCount = 0
    private(set) var deepCompletionCount = 0
    private(set) var maximumOverdriveTouchdownCount = 0

    mutating func record(
        update: UpdateResult,
        playScore: PlayScoreResult?
    ) {
        guard let outcome = update.passResolved else { return }

        if outcome == .completion || outcome == .touchdown,
           let laneID = update.laneID {
            completedLaneIDs.insert(laneID)
        }

        if outcome == .completion, update.laneID == .deep {
            deepCompletionCount += 1
        }

        if outcome == .touchdown, playScore?.bonusWasActive == true {
            bonusTouchdownCount += 1
        }

        if outcome == .touchdown,
           playScore?.outcome == outcome,
           playScore?.laneID == update.laneID,
           playScore?.bonusWasActive == true,
           playScore?.touchdownMultiplier
                == ScoringConfig.touchdownMultipliers.last {
            maximumOverdriveTouchdownCount += 1
        }
    }

    func makeCompletedRun(
        configuration: RunConfiguration,
        state: GameState,
        finishReason: RunFinishReason,
        endedAt: Date
    ) -> CompletedRun {
        return CompletedRun(
            configuration: configuration,
            endedAt: max(endedAt, configuration.startedAt),
            elapsedGameplayMilliseconds: max(
                0,
                Int(state.elapsedGameplayMilliseconds.rounded())
            ),
            finishReason: finishReason,
            score: max(0, state.score),
            statistics: state.statistics.completedRunSnapshot,
            completedLaneIDs: completedLaneIDs,
            bonusTouchdownCount: bonusTouchdownCount,
            deepCompletionCount: deepCompletionCount,
            maximumOverdriveTouchdownCount: maximumOverdriveTouchdownCount
        )
    }
}

enum RestartRoundConfigurationError: Error, Equatable {
    case reusedRunID(RunID)
    case reusedRandomSeed(UInt32)
    case invalidChronology
    case invalidOffenseSelection(InventoryRuleError)
    case unknownDefenseTeam(TeamID)
    case sameTeamMatchup(TeamID)
    case unknownDefenseJersey(JerseyID)
    case defenseJerseyDoesNotBelongToTeam(
        jerseyID: JerseyID,
        teamID: TeamID
    )
}

/// Process-only proof that a paused session was sealed specifically for
/// Restart Round. It is intentionally non-Codable and cannot be reconstructed
/// from an ordinary abandoned run or durable completed-run history.
struct ConfirmedRestartAbandonment: Equatable, Sendable {
    let completedRun: CompletedRun

    fileprivate init(completedRun: CompletedRun) {
        self.completedRun = completedRun
    }
}

/// Builds a new configured run after an abandoned predecessor settles.
///
/// The successor receives fresh simulation identity while preserving the
/// player's exact loadout and matchup. This factory never mutates or reuses the
/// predecessor session, and it carries no durable restart lineage.
struct RestartRoundConfigurationFactory: Sendable {
    let catalog: LaunchCatalog

    init(catalog: LaunchCatalog = .approved) {
        self.catalog = catalog
    }

    func makeSuccessor(
        after restartAbandonment: ConfirmedRestartAbandonment,
        inventory: PlayerInventory,
        runID: RunID = RunID(),
        randomSeed: UInt32,
        startedAt: Date
    ) throws -> RunConfiguration {
        let abandonedRun = restartAbandonment.completedRun
        let predecessor = abandonedRun.configuration
        guard runID != predecessor.runID else {
            throw RestartRoundConfigurationError.reusedRunID(runID)
        }
        guard normalizedSeed(randomSeed)
            != normalizedSeed(predecessor.randomSeed) else {
            throw RestartRoundConfigurationError.reusedRandomSeed(randomSeed)
        }
        guard predecessor.startedAt.timeIntervalSinceReferenceDate.isFinite,
              abandonedRun.endedAt.timeIntervalSinceReferenceDate.isFinite,
              startedAt.timeIntervalSinceReferenceDate.isFinite,
              abandonedRun.endedAt >= predecessor.startedAt,
              startedAt >= abandonedRun.endedAt,
              startedAt != predecessor.startedAt else {
            throw RestartRoundConfigurationError.invalidChronology
        }

        let preservedSelection = PlayerSelection(
            selectedTeamID: predecessor.offenseTeamID,
            selectedJerseyByTeam: [
                predecessor.offenseTeamID: predecessor.offenseJerseyID,
            ],
            selectedFootballID: predecessor.footballID
        )
        do {
            try InventoryRules.validate(
                selection: preservedSelection,
                inventory: inventory,
                catalog: catalog
            )
        } catch let error as InventoryRuleError {
            throw RestartRoundConfigurationError.invalidOffenseSelection(error)
        }

        guard catalog.team(id: predecessor.defenseTeamID) != nil else {
            throw RestartRoundConfigurationError.unknownDefenseTeam(
                predecessor.defenseTeamID
            )
        }
        guard predecessor.defenseTeamID != predecessor.offenseTeamID else {
            throw RestartRoundConfigurationError.sameTeamMatchup(
                predecessor.offenseTeamID
            )
        }
        guard let defenseJersey = catalog.jersey(
            id: predecessor.defenseJerseyID
        ) else {
            throw RestartRoundConfigurationError.unknownDefenseJersey(
                predecessor.defenseJerseyID
            )
        }
        guard defenseJersey.teamID == predecessor.defenseTeamID else {
            throw RestartRoundConfigurationError
                .defenseJerseyDoesNotBelongToTeam(
                    jerseyID: defenseJersey.id,
                    teamID: predecessor.defenseTeamID
                )
        }

        return RunConfiguration(
            runID: runID,
            randomSeed: randomSeed,
            offenseTeamID: predecessor.offenseTeamID,
            offenseJerseyID: predecessor.offenseJerseyID,
            defenseTeamID: predecessor.defenseTeamID,
            defenseJerseyID: predecessor.defenseJerseyID,
            footballID: predecessor.footballID,
            economyVersion: predecessor.economyVersion,
            startedAt: startedAt
        )
    }

    private func normalizedSeed(_ seed: UInt32) -> UInt32 {
        seed == 0 ? GameplayConfig.defaultSeed : seed
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
    var snapshot: GameplaySceneSnapshot { GameplaySceneSnapshot(state: state) }
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

    @discardableResult
    mutating func pause() -> Bool {
        guard completedRun == nil, isApplicationActive else { return false }
        return simulation.pause()
    }

    @discardableResult
    mutating func resume() -> Bool {
        guard completedRun == nil, isApplicationActive else { return false }
        return simulation.resume()
    }

    mutating func setApplicationActive(_ isActive: Bool) {
        guard isApplicationActive != isActive else { return }
        isApplicationActive = isActive

        if !isActive,
           state.phase == .playing || state.phase == .resolvingFinalBall {
            simulation.pause()
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

    /// Seals an active, explicitly paused session for app-owned Restart Round
    /// orchestration. Cancellation never calls this seam. The successor is a
    /// separate session created only after durable settlement succeeds.
    mutating func abandonForConfirmedRestart(
        endedAt: Date
    ) -> ConfirmedRestartAbandonment? {
        guard isApplicationActive, state.phase == .paused else { return nil }
        guard let completedRun = abandon(endedAt: endedAt) else { return nil }
        return ConfirmedRestartAbandonment(completedRun: completedRun)
    }
}

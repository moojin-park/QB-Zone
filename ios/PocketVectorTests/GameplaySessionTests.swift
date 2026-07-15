import CoreGraphics
import Foundation
import XCTest

@testable import PocketVector

final class GameplaySessionTests: XCTestCase {
    func testConfigurationSeedAndSettingsAreProjectedIntoOneSession() {
        let configuration = makeConfiguration(seed: 0x1234_ABCD)
        let settings = PlayerSettings(
            musicVolume: 0.21,
            sfxVolume: 0.87,
            isMuted: true,
            reducedMotion: true,
            tutorialCompleted: true
        )

        let session = GameplaySession(configuration: configuration, settings: settings)

        XCTAssertEqual(session.configuration, configuration)
        XCTAssertEqual(session.simulation.state.randomState, configuration.randomSeed)
        XCTAssertEqual(session.state.phase, .countdown)
        XCTAssertEqual(session.settings.musicVolume, 0.21, accuracy: 0.000_1)
        XCTAssertEqual(session.settings.sfxVolume, 0.87, accuracy: 0.000_1)
        XCTAssertTrue(session.settings.isMuted)
        XCTAssertTrue(session.settings.reducedMotion)
    }

    func testNaturalCompletionConvertsSimulationAndEmitsOnlyOnce() throws {
        let configuration = makeConfiguration(seed: 77)
        let endedAt = configuration.startedAt.addingTimeInterval(64)
        var session = GameplaySession(configuration: configuration, settings: PlayerSettings())

        XCTAssertNil(
            session.advance(deltaMilliseconds: 3_000, endedAt: endedAt).completedRun
        )
        let completion = try XCTUnwrap(
            session.advance(deltaMilliseconds: 60_000, endedAt: endedAt).completedRun
        )

        XCTAssertEqual(completion.configuration, configuration)
        XCTAssertEqual(completion.finishReason, .timerExpired)
        XCTAssertEqual(completion.elapsedGameplayMilliseconds, 60_000)
        XCTAssertEqual(completion.endedAt, endedAt)
        XCTAssertEqual(completion.score, session.state.score)
        XCTAssertEqual(completion.statistics.attempts, session.state.statistics.attempts)
        XCTAssertTrue(completion.isNaturallyCompleted)

        XCTAssertNil(session.advance(deltaMilliseconds: 10_000, endedAt: endedAt).completedRun)
        XCTAssertNil(session.abandon(endedAt: endedAt))
        XCTAssertEqual(session.completedRun, completion)
    }

    func testRecorderTracksCompletedLanesBonusTouchdownsAndExactOutcomes() {
        var recorder = GameplayRunRecorder()
        let completionScore = GameSimulation.calculatePlayScore(
            score: 0,
            meter: 0,
            streak: 0,
            outcome: .completion,
            laneID: .short
        )
        recorder.record(
            update: UpdateResult(
                passResolved: .completion,
                laneID: .short,
                scoreChanged: true,
                runFinished: false
            ),
            playScore: completionScore
        )
        let bonusTouchdownScore = GameSimulation.calculatePlayScore(
            score: completionScore.totalAfter,
            meter: ScoringConfig.meterMaximum,
            streak: 1,
            outcome: .touchdown,
            laneID: .touchdown
        )
        recorder.record(
            update: UpdateResult(
                passResolved: .touchdown,
                laneID: .touchdown,
                scoreChanged: true,
                runFinished: false
            ),
            playScore: bonusTouchdownScore
        )
        recorder.record(
            update: UpdateResult(
                passResolved: .interception,
                laneID: nil,
                scoreChanged: false,
                runFinished: false
            ),
            playScore: GameSimulation.calculatePlayScore(
                score: bonusTouchdownScore.totalAfter,
                meter: 0,
                streak: 0,
                outcome: .interception,
                laneID: nil
            )
        )

        var state = GameState()
        state.elapsedGameplayMilliseconds = 60_000
        state.score = bonusTouchdownScore.totalAfter
        state.statistics = RunStatistics(
            attempts: 3,
            completions: 1,
            touchdowns: 1,
            incompletions: 0,
            interceptions: 1,
            longestTouchdownStreak: 2
        )
        let run = recorder.makeCompletedRun(
            configuration: makeConfiguration(seed: 5),
            state: state,
            finishReason: .timerExpired,
            endedAt: Date(timeIntervalSince1970: 1_100)
        )

        XCTAssertEqual(run.completedLaneIDs, [.short, .touchdown])
        XCTAssertEqual(run.bonusTouchdownCount, 1)
        XCTAssertEqual(run.statistics.attempts, 3)
        XCTAssertEqual(run.statistics.completions, 1)
        XCTAssertEqual(run.statistics.touchdowns, 1)
        XCTAssertEqual(run.statistics.interceptions, 1)
        XCTAssertEqual(run.statistics.successfulPasses, 2)
    }

    func testAbandonmentIsExactOnceAndNeverRewardEligible() throws {
        let configuration = makeConfiguration(seed: 31)
        var session = GameplaySession(configuration: configuration, settings: PlayerSettings())
        _ = session.advance(
            deltaMilliseconds: 3_000,
            endedAt: configuration.startedAt.addingTimeInterval(3)
        )
        _ = session.advance(
            deltaMilliseconds: 1_500,
            endedAt: configuration.startedAt.addingTimeInterval(4.5)
        )

        let abandoned = try XCTUnwrap(
            session.abandon(endedAt: configuration.startedAt.addingTimeInterval(5))
        )

        XCTAssertEqual(abandoned.finishReason, .abandoned)
        XCTAssertEqual(abandoned.elapsedGameplayMilliseconds, 1_500)
        XCTAssertFalse(abandoned.isNaturallyCompleted)
        XCTAssertFalse(abandoned.isRewardEligible)
        XCTAssertNil(session.abandon(endedAt: configuration.startedAt.addingTimeInterval(6)))
        XCTAssertNil(
            session.advance(
                deltaMilliseconds: 60_000,
                endedAt: configuration.startedAt.addingTimeInterval(65)
            ).completedRun
        )
    }

    func testBackgroundPauseDoesNotFabricateElapsedGameplay() {
        let configuration = makeConfiguration(seed: 90)
        var session = GameplaySession(configuration: configuration, settings: PlayerSettings())
        _ = session.advance(
            deltaMilliseconds: 3_000,
            endedAt: configuration.startedAt.addingTimeInterval(3)
        )
        _ = session.advance(
            deltaMilliseconds: 1_000,
            endedAt: configuration.startedAt.addingTimeInterval(4)
        )
        XCTAssertEqual(session.state.elapsedGameplayMilliseconds, 1_000)

        session.setApplicationActive(false)
        XCTAssertEqual(session.state.phase, .paused)
        XCTAssertEqual(
            session.advance(
                deltaMilliseconds: 30_000,
                endedAt: configuration.startedAt.addingTimeInterval(34)
            ),
            .idle
        )
        XCTAssertEqual(session.state.elapsedGameplayMilliseconds, 1_000)

        session.setApplicationActive(true)
        _ = session.advance(
            deltaMilliseconds: 10_000,
            endedAt: configuration.startedAt.addingTimeInterval(44)
        )
        XCTAssertEqual(session.state.elapsedGameplayMilliseconds, 1_000)

        session.togglePause()
        _ = session.advance(
            deltaMilliseconds: 1_000,
            endedAt: configuration.startedAt.addingTimeInterval(45)
        )
        XCTAssertEqual(session.state.elapsedGameplayMilliseconds, 2_000)
    }

    func testAudioAndMotionProjectionUsesSavedPlayerSettings() {
        let projection = GameSettingsProjection(
            PlayerSettings(
                musicVolume: 0.15,
                sfxVolume: 0.65,
                isMuted: true,
                reducedMotion: true
            )
        )

        XCTAssertEqual(projection.musicVolume, 0.15, accuracy: 0.000_1)
        XCTAssertEqual(projection.sfxVolume, 0.65, accuracy: 0.000_1)
        XCTAssertTrue(projection.isMuted)
        XCTAssertTrue(projection.reducedMotion)
    }

    @MainActor
    func testSceneReceivesImmutableConfigurationAndAbandonsExactlyOnce() {
        let configuration = makeConfiguration(seed: 808)
        let settings = PlayerSettings(isMuted: true, reducedMotion: true)
        var callbacks: [CompletedRun] = []
        let scene = GameScene(
            size: GameProjection.sceneSize,
            configuration: configuration,
            settings: settings,
            now: { configuration.startedAt.addingTimeInterval(9) },
            onCompletedRun: { callbacks.append($0) }
        )

        XCTAssertEqual(scene.configuration, configuration)
        XCTAssertEqual(scene.settings, settings)
        scene.requestAbandon()
        scene.requestAbandon()

        XCTAssertEqual(callbacks.count, 1)
        XCTAssertEqual(callbacks.first?.finishReason, .abandoned)
        XCTAssertEqual(callbacks.first?.configuration, configuration)
        scene.setApplicationActive(false)
    }

    @MainActor
    func testAudioControllerAppliesSavedVolumesAndMuteState() {
        let initial = PlayerSettings(
            musicVolume: 0.12,
            sfxVolume: 0.34,
            isMuted: true,
            reducedMotion: false
        )
        let audio = GameAudioController(settings: initial)

        XCTAssertEqual(audio.settings, GameSettingsProjection(initial))
        XCTAssertTrue(audio.isMuted)

        let updated = PlayerSettings(
            musicVolume: 0.78,
            sfxVolume: 0.56,
            isMuted: false,
            reducedMotion: true
        )
        audio.apply(updated)

        XCTAssertEqual(audio.settings, GameSettingsProjection(updated))
        XCTAssertFalse(audio.isMuted)
        audio.suspend()
    }

    private func makeConfiguration(seed: UInt32) -> RunConfiguration {
        let catalog = LaunchCatalog.approved
        let offense = catalog.teams[0]
        let defense = catalog.teams[1]
        return RunConfiguration(
            runID: RunID(
                UUID(uuidString: "00000000-0000-0000-0000-000000000551")!
            ),
            randomSeed: seed,
            offenseTeamID: offense.id,
            offenseJerseyID: offense.primaryJersey.id,
            defenseTeamID: defense.id,
            defenseJerseyID: defense.primaryJersey.id,
            footballID: LaunchFootballID.standard,
            economyVersion: EconomyConfiguration.currentVersion,
            startedAt: Date(timeIntervalSince1970: 1_000)
        )
    }
}

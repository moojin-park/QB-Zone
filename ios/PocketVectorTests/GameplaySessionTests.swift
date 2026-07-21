import CoreGraphics
import Foundation
import SpriteKit
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

    func testLiveSnapshotExposesTouchdownInclusiveCompletionContract() {
        var state = GameState()
        state.phase = .paused
        state.statistics = RunStatistics(
            attempts: 7,
            completions: 3,
            touchdowns: 2,
            incompletions: 1,
            interceptions: 1,
            longestTouchdownStreak: 2
        )

        let snapshot = GameplaySceneSnapshot(state: state)

        XCTAssertTrue(snapshot.isPaused)
        XCTAssertFalse(snapshot.defersBottomSystemGestures)
        XCTAssertEqual(snapshot.statistics.attempts, 7)
        XCTAssertEqual(snapshot.statistics.successfulCompletions, 5)
        XCTAssertEqual(snapshot.statistics.completionPercentage, 71)
        XCTAssertEqual(snapshot.statistics.touchdowns, 2)
        XCTAssertEqual(
            GameplaySceneSnapshot(state: GameState())
                .statistics.completionPercentage,
            0
        )
    }

    func testSnapshotPublicationGateAcceptsOnlyPauseOrStatisticsChanges() {
        var gate = GameplaySnapshotPublicationGate()
        var state = GameState()
        let initial = GameplaySceneSnapshot(state: state)

        XCTAssertTrue(gate.accept(initial))
        XCTAssertFalse(gate.accept(initial))

        state.phase = .paused
        let paused = GameplaySceneSnapshot(state: state)
        XCTAssertTrue(gate.accept(paused))
        XCTAssertFalse(gate.accept(paused))

        state.phase = .playing
        XCTAssertTrue(gate.accept(GameplaySceneSnapshot(state: state)))

        state.statistics = RunStatistics(
            attempts: 2,
            completions: 1,
            touchdowns: 1,
            incompletions: 0,
            interceptions: 0,
            longestTouchdownStreak: 1
        )
        let statisticsChanged = GameplaySceneSnapshot(state: state)
        XCTAssertTrue(gate.accept(statisticsChanged))
        XCTAssertEqual(statisticsChanged.statistics.successfulCompletions, 2)
        XCTAssertEqual(statisticsChanged.statistics.completionPercentage, 100)
        XCTAssertFalse(gate.accept(statisticsChanged))
    }

    func testSnapshotDefersBottomSystemGesturesAcrossCompleteActiveGameplaySurface() {
        let expectations: [(phase: GamePhase, defers: Bool)] = [
            (.title, false),
            (.countdown, true),
            (.playing, true),
            (.resolvingFinalBall, true),
            (.paused, false),
            (.results, false),
        ]

        for expectation in expectations {
            var state = GameState()
            state.phase = expectation.phase
            XCTAssertEqual(
                GameplaySceneSnapshot(state: state).defersBottomSystemGestures,
                expectation.defers,
                "Unexpected bottom-edge deferral for \(expectation.phase)"
            )
        }
    }

    func testSnapshotPublicationGateKeepsActiveTransitionsIdempotent() {
        var gate = GameplaySnapshotPublicationGate()
        var state = GameState()
        state.phase = .countdown

        XCTAssertTrue(gate.accept(GameplaySceneSnapshot(state: state)))
        XCTAssertFalse(gate.accept(GameplaySceneSnapshot(state: state)))
        state.phase = .playing
        XCTAssertFalse(gate.accept(GameplaySceneSnapshot(state: state)))
        state.phase = .paused
        XCTAssertTrue(gate.accept(GameplaySceneSnapshot(state: state)))
        state.phase = .playing
        XCTAssertTrue(gate.accept(GameplaySceneSnapshot(state: state)))
        state.phase = .resolvingFinalBall
        XCTAssertFalse(gate.accept(GameplaySceneSnapshot(state: state)))
        state.phase = .results
        XCTAssertTrue(gate.accept(GameplaySceneSnapshot(state: state)))
    }

    func testExplicitPauseAndResumeAreIdempotent() {
        let configuration = makeConfiguration(seed: 13)
        var session = GameplaySession(configuration: configuration, settings: PlayerSettings())
        _ = session.advance(
            deltaMilliseconds: 3_000,
            endedAt: configuration.startedAt.addingTimeInterval(3)
        )

        XCTAssertEqual(session.state.phase, .playing)
        XCTAssertTrue(session.pause())
        XCTAssertTrue(session.snapshot.isPaused)
        XCTAssertFalse(session.pause())

        XCTAssertTrue(session.resume())
        XCTAssertEqual(session.state.phase, .playing)
        XCTAssertFalse(session.resume())
        XCTAssertEqual(session.state.phase, .playing)
    }

    func testPauseAndResumePreserveAirborneFinalBallState() throws {
        let configuration = makeConfiguration(seed: 14)
        var session = GameplaySession(configuration: configuration, settings: PlayerSettings())
        _ = session.advance(
            deltaMilliseconds: 3_000,
            endedAt: configuration.startedAt.addingTimeInterval(3)
        )
        _ = session.advance(
            deltaMilliseconds: 59_900,
            endedAt: configuration.startedAt.addingTimeInterval(62.9)
        )
        XCTAssertTrue(
            session.throwBall(
                target: WorldPoint(x: 1.2, depth: 1, height: 0.5),
                releaseSpeedPixelsPerMillisecond:
                    GameplayConfig.Throw.slowSpeedPixelsPerMillisecond,
                aimMarker: .zero
            )
        )
        _ = session.advance(
            deltaMilliseconds: 100,
            endedAt: configuration.startedAt.addingTimeInterval(63)
        )

        XCTAssertEqual(session.state.phase, .resolvingFinalBall)
        XCTAssertTrue(session.snapshot.defersBottomSystemGestures)
        XCTAssertFalse(session.canThrow)
        let ballBeforePause = try XCTUnwrap(session.state.ball)
        let graceBeforePause = session.state.finalBallGraceRemainingMilliseconds
        XCTAssertFalse(
            session.throwBall(
                target: WorldPoint(x: 0, depth: 0.5, height: 0.5),
                releaseSpeedPixelsPerMillisecond: 1,
                aimMarker: .zero
            )
        )
        XCTAssertEqual(session.state.ball, ballBeforePause)

        XCTAssertTrue(session.pause())
        XCTAssertFalse(session.snapshot.defersBottomSystemGestures)
        _ = session.advance(
            deltaMilliseconds: 500,
            endedAt: configuration.startedAt.addingTimeInterval(63.5)
        )
        XCTAssertEqual(session.state.ball, ballBeforePause)
        XCTAssertEqual(
            session.state.finalBallGraceRemainingMilliseconds,
            graceBeforePause
        )

        XCTAssertTrue(session.resume())
        XCTAssertEqual(session.state.phase, .resolvingFinalBall)
        XCTAssertTrue(session.snapshot.defersBottomSystemGestures)
        XCTAssertFalse(session.resume())
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
            streak: completionScore.streakAfter,
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
        let interceptionScore = GameSimulation.calculatePlayScore(
            score: bonusTouchdownScore.totalAfter,
            meter: 0,
            streak: bonusTouchdownScore.streakAfter,
            outcome: .interception,
            laneID: nil
        )
        recorder.record(
            update: UpdateResult(
                passResolved: .interception,
                laneID: nil,
                scoreChanged: true,
                runFinished: false
            ),
            playScore: interceptionScore
        )

        var state = GameState()
        state.elapsedGameplayMilliseconds = 60_000
        state.score = interceptionScore.totalAfter
        state.statistics = RunStatistics(
            attempts: 3,
            completions: 1,
            touchdowns: 1,
            incompletions: 0,
            interceptions: 1,
            longestTouchdownStreak: 1
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
        XCTAssertFalse(session.pause())
        XCTAssertFalse(session.resume())
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
        XCTAssertFalse(session.resume())

        session.setApplicationActive(true)
        _ = session.advance(
            deltaMilliseconds: 10_000,
            endedAt: configuration.startedAt.addingTimeInterval(44)
        )
        XCTAssertEqual(session.state.elapsedGameplayMilliseconds, 1_000)

        XCTAssertTrue(session.resume())
        XCTAssertFalse(session.resume())
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
        var snapshots: [GameplaySceneSnapshot] = []
        let scene = GameScene(
            size: GameProjection.sceneSize,
            configuration: configuration,
            settings: settings,
            now: { configuration.startedAt.addingTimeInterval(9) },
            onCompletedRun: { callbacks.append($0) },
            onGameplaySnapshotChanged: { snapshots.append($0) }
        )

        XCTAssertEqual(scene.configuration, configuration)
        XCTAssertEqual(scene.settings, settings)
        XCTAssertTrue(snapshots.isEmpty)
        XCTAssertFalse(scene.currentSnapshot.isPaused)
        scene.setApplicationActive(true)
        XCTAssertTrue(snapshots.isEmpty)
        scene.commitConfirmedExitRun()
        scene.commitConfirmedExitRun()

        XCTAssertEqual(callbacks.count, 1)
        XCTAssertEqual(callbacks.first?.finishReason, .abandoned)
        XCTAssertEqual(callbacks.first?.configuration, configuration)
        scene.setApplicationActive(false)
    }

    @MainActor
    func testMountedScenePublishesExplicitPauseResumeAndIgnoresPausedInput() async throws {
        let configuration = makeConfiguration(seed: 809)
        var snapshots: [GameplaySceneSnapshot] = []
        let scene = GameScene(
            size: GameProjection.sceneSize,
            configuration: configuration,
            settings: PlayerSettings(isMuted: true, reducedMotion: true),
            onCompletedRun: { _ in },
            onGameplaySnapshotChanged: { snapshots.append($0) }
        )
        let view = SKView(frame: CGRect(origin: .zero, size: GameProjection.sceneSize))

        scene.didMove(to: view)
        XCTAssertEqual(snapshots, [scene.currentSnapshot])

        let readinessDeadline = ProcessInfo.processInfo.systemUptime + 8
        while scene.visualReadiness == .preparing,
              ProcessInfo.processInfo.systemUptime < readinessDeadline {
            await Task.yield()
        }
        XCTAssertEqual(scene.visualReadiness, .ready)

        scene.update(0)
        for step in 1 ... 31 {
            scene.update(TimeInterval(step) / 10)
        }
        XCTAssertEqual(snapshots.map(\.defersBottomSystemGestures), [true])

        XCTAssertTrue(scene.pause())
        XCTAssertTrue(scene.currentSnapshot.isPaused)
        XCTAssertEqual(snapshots.map(\.isPaused), [false, true])
        XCTAssertEqual(
            snapshots.map(\.defersBottomSystemGestures),
            [true, false]
        )
        let pausedPublicationCount = snapshots.count
        XCTAssertFalse(scene.pause())
        XCTAssertEqual(snapshots.count, pausedPublicationCount)

        let pausedSnapshot = scene.currentSnapshot
        scene.handlePrimaryInputBegan(
            at: CGPoint(x: scene.size.width / 2, y: scene.size.height / 2)
        )
        XCTAssertEqual(scene.currentSnapshot, pausedSnapshot)
        XCTAssertEqual(snapshots.count, pausedPublicationCount)

        XCTAssertTrue(scene.resume())
        XCTAssertFalse(scene.currentSnapshot.isPaused)
        XCTAssertEqual(snapshots.map(\.isPaused), [false, true, false])
        XCTAssertEqual(
            snapshots.map(\.defersBottomSystemGestures),
            [true, false, true]
        )
        let resumedPublicationCount = snapshots.count
        XCTAssertFalse(scene.resume())
        XCTAssertEqual(snapshots.count, resumedPublicationCount)

        scene.willMove(from: view)
    }

    @MainActor
    func testMountedSceneComposesWideThrowBandWithHUDExclusions() throws {
        let configuration = makeConfiguration(seed: 810)
        let scene = GameScene(
            size: GameProjection.sceneSize,
            configuration: configuration,
            settings: PlayerSettings(isMuted: true, reducedMotion: true),
            onCompletedRun: { _ in }
        )
        let view = SKView(frame: CGRect(origin: .zero, size: GameProjection.sceneSize))

        scene.didMove(to: view)
        let hud = try XCTUnwrap(
            scene.childNode(withName: "broadcastHUD") as? BroadcastHUDNode
        )
        let bottomBar = try XCTUnwrap(
            scene.childNode(withName: "//gameplayLetterbox.bottom") as? SKSpriteNode
        )

        XCTAssertEqual(bottomBar.size.height, 32, accuracy: 0.000_001)
        XCTAssertTrue(scene.containsThrowActivationPoint(CGPoint(x: 512, y: 0)))
        XCTAssertTrue(scene.containsThrowActivationPoint(CGPoint(x: 512, y: 1)))
        XCTAssertFalse(scene.containsThrowActivationPoint(CGPoint(x: 512, y: -0.001)))
        XCTAssertTrue(scene.containsThrowActivationPoint(CGPoint(x: 300, y: 200)))
        XCTAssertTrue(scene.containsThrowActivationPoint(CGPoint(x: 700, y: 200)))
        XCTAssertTrue(scene.containsThrowActivationPoint(CGPoint(x: 512, y: 225)))
        XCTAssertFalse(scene.containsThrowActivationPoint(CGPoint(x: 512, y: 225.001)))
        XCTAssertFalse(
            scene.containsThrowActivationPoint(
                CGPoint(x: hud.muteHitFrame.midX, y: hud.muteHitFrame.midY)
            )
        )
        XCTAssertFalse(
            scene.containsThrowActivationPoint(
                CGPoint(x: hud.pauseHitFrame.midX, y: hud.pauseHitFrame.midY)
            )
        )
        XCTAssertFalse(
            scene.containsThrowActivationPoint(
                CGPoint(
                    x: hud.layout.scorePlateFrame.midX,
                    y: hud.layout.scorePlateFrame.midY
                )
            )
        )
        XCTAssertFalse(
            scene.containsThrowActivationPoint(
                CGPoint(
                    x: hud.layout.feedbackTwoLineFrame.midX,
                    y: hud.layout.feedbackTwoLineFrame.midY
                )
            )
        )

        scene.willMove(from: view)
    }

    @MainActor
    func testMountedCountdownIsInertAndPlayingAcceptsInputUnderBottomBarForBothMotionModes() async throws {
        for reducedMotion in [false, true] {
            var snapshots: [GameplaySceneSnapshot] = []
            let scene = GameScene(
                size: GameProjection.sceneSize,
                configuration: makeConfiguration(seed: reducedMotion ? 813 : 812),
                settings: PlayerSettings(isMuted: true, reducedMotion: reducedMotion),
                onCompletedRun: { _ in },
                onGameplaySnapshotChanged: { snapshots.append($0) }
            )
            let view = SKView(frame: CGRect(origin: .zero, size: GameProjection.sceneSize))
            scene.didMove(to: view)

            XCTAssertEqual(snapshots.map(\.defersBottomSystemGestures), [true])

            let readinessDeadline = ProcessInfo.processInfo.systemUptime + 8
            while scene.visualReadiness == .preparing,
                  ProcessInfo.processInfo.systemUptime < readinessDeadline {
                await Task.yield()
            }
            XCTAssertEqual(scene.visualReadiness, .ready)
            XCTAssertFalse(scene.isGameplayMusicPlaying)
            XCTAssertFalse(scene.isAudioCuePlaying(.countdown))

            let startPoint = CGPoint(x: scene.size.width / 2, y: 1)
            scene.handlePrimaryInputBegan(
                at: startPoint,
                initialSample: TouchSample(
                    point: startPoint,
                    timestampMilliseconds: 0
                )
            )
            XCTAssertFalse(scene.isAiming)
            XCTAssertEqual(scene.currentSnapshot.statistics.attempts, 0)

            scene.update(0)
            for step in 1 ... 20 {
                scene.update(TimeInterval(step) / 10)
            }
            XCTAssertNotNil(scene.childNode(withName: "//countdown"))
            XCTAssertFalse(scene.isAiming)
            XCTAssertEqual(scene.currentSnapshot.statistics.attempts, 0)
            XCTAssertFalse(scene.isGameplayMusicPlaying)
            XCTAssertFalse(scene.isAudioCuePlaying(.countdown))
            XCTAssertEqual(snapshots.map(\.defersBottomSystemGestures), [true])

            for step in 21 ... 31 {
                scene.update(TimeInterval(step) / 10)
            }
            XCTAssertNil(scene.childNode(withName: "//countdown"))
            XCTAssertEqual(snapshots.map(\.defersBottomSystemGestures), [true])

            let bottomBar = try XCTUnwrap(
                scene.childNode(withName: "//gameplayLetterbox.bottom") as? SKSpriteNode
            )
            XCTAssertEqual(bottomBar.size.height, 32, accuracy: 0.000_001)
            scene.handlePrimaryInputBegan(
                at: startPoint,
                initialSample: TouchSample(
                    point: startPoint,
                    timestampMilliseconds: 3_100
                )
            )
            XCTAssertTrue(
                scene.isAiming,
                "Playing input beneath the completed bar must work with reducedMotion=\(reducedMotion)"
            )

            scene.willMove(from: view)
        }
    }

    @MainActor
    func testMountedSceneStartsStandardMotionLetterboxAtZeroHeight() throws {
        let scene = GameScene(
            size: GameProjection.sceneSize,
            configuration: makeConfiguration(seed: 811),
            settings: PlayerSettings(isMuted: true, reducedMotion: false),
            onCompletedRun: { _ in }
        )
        let view = SKView(frame: CGRect(origin: .zero, size: GameProjection.sceneSize))

        scene.didMove(to: view)
        let layer = try XCTUnwrap(scene.childNode(withName: "gameplayLetterbox"))
        let topBar = try XCTUnwrap(
            scene.childNode(withName: "//gameplayLetterbox.top") as? SKSpriteNode
        )
        let bottomBar = try XCTUnwrap(
            scene.childNode(withName: "//gameplayLetterbox.bottom") as? SKSpriteNode
        )

        XCTAssertFalse(layer.isHidden)
        XCTAssertEqual(topBar.size, CGSize(width: 1_024, height: 0))
        XCTAssertEqual(bottomBar.size, topBar.size)
        XCTAssertEqual(topBar.position.y, GameProjection.logicalHeight, accuracy: 0.000_001)
        XCTAssertEqual(bottomBar.position, .zero)
        scene.willMove(from: view)
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

import Foundation
import XCTest

@testable import PocketVector

final class GameplayCoordinatorTests: XCTestCase {
    @MainActor
    func testNaturalCompletionUsesAuthoritativeStateAndResults() async throws {
        var receivedRuns: [CompletedRun] = []
        var authoritativeState = AppCoordinatorState.launchDefault()
        authoritativeState.confirmedCoins = 28
        authoritativeState.personalBest = 14_000

        let coordinator = AppCoordinator(
            environment: makeEnvironment { run in
                receivedRuns.append(run)
                let results = self.makeResults(run: run, state: authoritativeState)
                return .settled(
                    authoritativeSnapshot: self.authoritativeSnapshot(
                        authoritativeState,
                        playerRevision: 1,
                        economyRevision: 1
                    ),
                    results: results
                )
            }
        )
        await coordinator.bootstrap()
        let configuration = try launchConfiguration(from: coordinator)
        let run = makeCompletedRun(configuration: configuration, reason: .timerExpired)

        await coordinator.handleCompletedRun(run)

        XCTAssertEqual(receivedRuns, [run])
        XCTAssertEqual(coordinator.state, authoritativeState)
        XCTAssertNil(coordinator.pendingCompletedRun)
        XCTAssertNil(coordinator.settlementErrorMessage)
        guard case let .runResults(results) = coordinator.currentDestination else {
            return XCTFail("Expected authoritative results navigation")
        }
        XCTAssertEqual(results.completedRun, run)
        XCTAssertEqual(results.earnedCoins, 28)
    }

    @MainActor
    func testAbandonedCompletionSettlesBeforeReturningToMenu() async throws {
        var events: [AppLifecycleEvent] = []
        var authoritativeState = AppCoordinatorState.launchDefault()
        authoritativeState.pendingCoins = 9
        let coordinator = AppCoordinator(
            environment: makeEnvironment(
                observeLifecycleEvent: { events.append($0) },
                settle: { _ in
                    .settled(
                        authoritativeSnapshot: self.authoritativeSnapshot(
                            authoritativeState,
                            playerRevision: 1,
                            economyRevision: 1
                        ),
                        results: nil
                    )
                }
            )
        )
        await coordinator.bootstrap()
        let configuration = try launchConfiguration(from: coordinator)
        let run = makeCompletedRun(configuration: configuration, reason: .abandoned)

        await coordinator.handleCompletedRun(run)

        XCTAssertEqual(coordinator.currentDestination, .mainMenu)
        XCTAssertEqual(coordinator.state, authoritativeState)
        XCTAssertNil(coordinator.pendingCompletedRun)
        XCTAssertEqual(events.last, .didExitRun(run.runID))
    }

    @MainActor
    func testSettlementFailureRetainsGameplayAndRetryRecovers() async throws {
        var attempts = 0
        var authoritativeState = AppCoordinatorState.launchDefault()
        authoritativeState.personalBest = 18_000
        let coordinator = AppCoordinator(
            environment: makeEnvironment { run in
                attempts += 1
                if attempts == 1 {
                    return .failed(message: "Profile sync is temporarily unavailable.")
                }
                return .settled(
                    authoritativeSnapshot: self.authoritativeSnapshot(
                        authoritativeState,
                        playerRevision: 1,
                        economyRevision: 1
                    ),
                    results: self.makeResults(run: run, state: authoritativeState)
                )
            }
        )
        await coordinator.bootstrap()
        let configuration = try launchConfiguration(from: coordinator)
        let run = makeCompletedRun(configuration: configuration, reason: .timerExpired)

        await coordinator.handleCompletedRun(run)

        XCTAssertEqual(coordinator.currentDestination, .gameplay(configuration))
        XCTAssertEqual(coordinator.pendingCompletedRun, run)
        XCTAssertEqual(
            coordinator.settlementErrorMessage,
            "Profile sync is temporarily unavailable."
        )

        await coordinator.retryCompletedRunSettlement()

        XCTAssertEqual(attempts, 2)
        XCTAssertNil(coordinator.pendingCompletedRun)
        XCTAssertNil(coordinator.settlementErrorMessage)
        guard case .runResults = coordinator.currentDestination else {
            return XCTFail("Expected retry to show verified results")
        }
    }

    @MainActor
    func testDisconnectedSettlementNeverFabricatesResultsOrCoins() async throws {
        var initialState = AppCoordinatorState.launchDefault()
        initialState.settings.tutorialCompleted = true
        let coordinator = AppCoordinator(
            state: initialState,
            environment: makeEnvironment(settle: nil)
        )
        await coordinator.bootstrap()
        let configuration = try launchConfiguration(from: coordinator)
        let run = makeCompletedRun(configuration: configuration, reason: .timerExpired)

        await coordinator.handleCompletedRun(run)

        XCTAssertEqual(coordinator.currentDestination, .gameplay(configuration))
        XCTAssertEqual(coordinator.state, initialState)
        XCTAssertEqual(coordinator.pendingCompletedRun, run)
        XCTAssertNotNil(coordinator.settlementErrorMessage)
        XCTAssertEqual(coordinator.state.confirmedCoins, 0)
        XCTAssertEqual(coordinator.state.pendingCoins, 0)
    }

    @MainActor
    func testMissingAuthoritativeResultsRetainsRecoverableRun() async throws {
        var authoritativeState = AppCoordinatorState.launchDefault()
        authoritativeState.pendingCoins = 25
        let coordinator = AppCoordinator(
            environment: makeEnvironment { _ in
                .settled(
                    authoritativeSnapshot: self.authoritativeSnapshot(
                        authoritativeState,
                        playerRevision: 1,
                        economyRevision: 1
                    ),
                    results: nil
                )
            }
        )
        await coordinator.bootstrap()
        let configuration = try launchConfiguration(from: coordinator)
        let run = makeCompletedRun(configuration: configuration, reason: .timerExpired)

        await coordinator.handleCompletedRun(run)

        XCTAssertEqual(coordinator.currentDestination, .gameplay(configuration))
        XCTAssertEqual(coordinator.state, authoritativeState)
        XCTAssertEqual(coordinator.pendingCompletedRun, run)
        XCTAssertNotNil(coordinator.settlementErrorMessage)
    }

    @MainActor
    func testOnlyOneSettlementCanBeInFlight() async throws {
        var settlementCalls = 0
        var continuation: CheckedContinuation<CompletedRunSettlementResult, Never>?
        let coordinator = AppCoordinator(
            environment: makeEnvironment { _ in
                settlementCalls += 1
                return await withCheckedContinuation { continuation = $0 }
            }
        )
        await coordinator.bootstrap()
        let configuration = try launchConfiguration(from: coordinator)
        let run = makeCompletedRun(configuration: configuration, reason: .timerExpired)

        let first = Task { @MainActor in await coordinator.handleCompletedRun(run) }
        while !coordinator.isRunSettlementInFlight {
            await Task.yield()
        }
        let duplicate = Task { @MainActor in await coordinator.handleCompletedRun(run) }
        await Task.yield()

        XCTAssertEqual(settlementCalls, 1)
        continuation?.resume(returning: .failed(message: "Try again."))
        _ = await first.value
        _ = await duplicate.value
        XCTAssertEqual(settlementCalls, 1)
    }

    @MainActor
    func testConfirmedExitBridgeNeverNavigatesOptimisticallyAndRetrySettlesOnce() async throws {
        var settlementCalls = 0
        var settlementContinuations: [CheckedContinuation<CompletedRunSettlementResult, Never>] = []
        let firstSettlementStarted = expectation(description: "Confirmed exit settlement started")
        var settlementStartedExpectation = firstSettlementStarted
        let coordinator = AppCoordinator(
            environment: makeEnvironment { _ in
                settlementCalls += 1
                return await withCheckedContinuation { continuation in
                    settlementContinuations.append(continuation)
                    settlementStartedExpectation.fulfill()
                }
            }
        )
        await coordinator.bootstrap()
        let configuration = try launchConfiguration(from: coordinator)
        var completedRuns: [CompletedRun] = []
        var settlementTask: Task<Void, Never>?
        let scene = GameScene(
            size: GameProjection.sceneSize,
            configuration: configuration,
            settings: PlayerSettings(isMuted: true, reducedMotion: true),
            now: { configuration.startedAt.addingTimeInterval(5) },
            onCompletedRun: { run in
                completedRuns.append(run)
                settlementTask = Task { @MainActor in
                    await coordinator.handleCompletedRun(run)
                }
            }
        )
        let bridge = GameplaySceneBridge(
            target: scene,
            initialResumeRequestID: 0,
            initialConfirmedExitRequestID: 0
        )

        bridge.requestConfirmedExit(id: 1)
        bridge.requestConfirmedExit(id: 1)

        XCTAssertEqual(completedRuns.count, 1)
        XCTAssertEqual(completedRuns.first?.finishReason, .abandoned)
        XCTAssertEqual(coordinator.currentDestination, .gameplay(configuration))

        await fulfillment(of: [firstSettlementStarted], timeout: 5)
        XCTAssertEqual(settlementContinuations.count, 1)
        XCTAssertTrue(coordinator.isRunSettlementInFlight)
        XCTAssertEqual(coordinator.currentDestination, .gameplay(configuration))
        XCTAssertEqual(settlementCalls, 1)

        settlementContinuations[0].resume(
            returning: .failed(message: "Profile sync is temporarily unavailable.")
        )
        _ = await settlementTask?.value

        XCTAssertEqual(coordinator.currentDestination, .gameplay(configuration))
        XCTAssertEqual(coordinator.pendingCompletedRun, completedRuns.first)
        XCTAssertEqual(settlementCalls, 1)

        let retrySettlementStarted = expectation(description: "Retry settlement started")
        settlementStartedExpectation = retrySettlementStarted
        let retryTask = Task { @MainActor in
            await coordinator.retryCompletedRunSettlement()
        }
        await fulfillment(of: [retrySettlementStarted], timeout: 5)
        XCTAssertEqual(settlementContinuations.count, 2)
        XCTAssertTrue(coordinator.isRunSettlementInFlight)
        XCTAssertEqual(coordinator.currentDestination, .gameplay(configuration))

        let authoritativeState = AppCoordinatorState.launchDefault()
        settlementContinuations[1].resume(
            returning: .settled(
                authoritativeSnapshot: authoritativeSnapshot(
                    authoritativeState,
                    playerRevision: 1,
                    economyRevision: 1
                ),
                results: nil
            )
        )
        _ = await retryTask.value

        XCTAssertEqual(settlementCalls, 2)
        XCTAssertEqual(completedRuns.count, 1)
        XCTAssertNil(coordinator.pendingCompletedRun)
        XCTAssertNil(coordinator.settlementErrorMessage)
        XCTAssertEqual(coordinator.currentDestination, .mainMenu)
    }

    @MainActor
    func testDebugPreviewNeverReachesProductionSettlement() async throws {
        var settlementCalls = 0
        let coordinator = AppCoordinator(
            environment: makeEnvironment { _ in
                settlementCalls += 1
                return .failed(message: "Must not run")
            }
        )
        await coordinator.bootstrap()
        let configuration = try launchConfiguration(from: coordinator)
        let preview = makeCompletedRun(configuration: configuration, reason: .debugPreview)

        await coordinator.handleCompletedRun(preview)

        XCTAssertEqual(settlementCalls, 0)
        XCTAssertEqual(coordinator.currentDestination, .mainMenu)
        XCTAssertNil(coordinator.pendingCompletedRun)
    }

    @MainActor
    private func launchConfiguration(from coordinator: AppCoordinator) throws -> RunConfiguration {
        XCTAssertTrue(coordinator.startRun())
        guard case let .gameplay(configuration) = coordinator.currentDestination else {
            throw TestFailure.expectedGameplay
        }
        return configuration
    }

    @MainActor
    private func makeEnvironment(
        observeLifecycleEvent: (@MainActor (AppLifecycleEvent) -> Void)? = nil,
        settle: (@MainActor (CompletedRun) async -> CompletedRunSettlementResult)?
    ) -> AppCoordinatorEnvironment {
        var completedTutorialState = AppCoordinatorState.launchDefault()
        completedTutorialState.settings.tutorialCompleted = true
        return AppCoordinatorEnvironment(
            loadInitialState: {
                .loaded(self.authoritativeSnapshot(completedTutorialState))
            },
            makeRunID: {
                RunID(UUID(uuidString: "00000000-0000-0000-0000-000000000661")!)
            },
            makeSeed: { 661 },
            now: { Date(timeIntervalSince1970: 2_000) },
            performExternalRequest: nil,
            observeLifecycleEvent: observeLifecycleEvent,
            settleCompletedRun: settle
        )
    }

    @MainActor
    private func authoritativeSnapshot(
        _ state: AppCoordinatorState,
        playerRevision: UInt64 = 0,
        economyRevision: UInt64 = 0
    ) -> AuthoritativeAppStateSnapshot {
        AuthoritativeAppStateSnapshot(
            session: ProfileSessionToken(
                accountIdentity: .local,
                nonce: UUID(uuidString: "00000000-0000-0000-0000-000000000661")!,
                profileID: UUID(uuidString: "00000000-0000-0000-0000-000000000662")!
            ),
            playerRevision: playerRevision,
            economyRevision: economyRevision,
            state: state
        )
    }

    private func makeCompletedRun(
        configuration: RunConfiguration,
        reason: RunFinishReason
    ) -> CompletedRun {
        CompletedRun(
            configuration: configuration,
            endedAt: configuration.startedAt.addingTimeInterval(60),
            elapsedGameplayMilliseconds: reason == .timerExpired ? 60_000 : 12_000,
            finishReason: reason,
            score: 14_000,
            statistics: RunStatisticsSnapshot(
                attempts: 10,
                completions: 5,
                touchdowns: 2,
                incompletions: 2,
                interceptions: 1,
                longestTouchdownStreak: 2
            ),
            completedLaneIDs: [.short, .touchdown],
            bonusTouchdownCount: 1
        )
    }

    private func makeResults(
        run: CompletedRun,
        state: AppCoordinatorState
    ) -> RunResultsPresentation {
        RunResultsPresentation(
            completedRun: run,
            earnedCoins: 28,
            pendingCoins: state.pendingCoins,
            personalBest: state.personalBest,
            isNewPersonalBest: true,
            rewardedAdOffer: .progress(validRuns: 1, requiredRuns: 5)
        )
    }

    private enum TestFailure: Error {
        case expectedGameplay
    }
}

final class GameplaySceneBridgeTests: XCTestCase {
    @MainActor
    func testSnapshotRelaySeedsCurrentSceneStateThenForwardsMountedChanges() {
        var initialState = GameState()
        initialState.phase = .playing
        let initialSnapshot = GameplaySceneSnapshot(state: initialState)
        let target = GameplaySceneActionTargetSpy(currentSnapshot: initialSnapshot)
        let bridge = GameplaySceneBridge(
            target: target,
            initialResumeRequestID: 7,
            initialConfirmedExitRequestID: 11
        )
        var receivedSnapshots: [GameplaySceneSnapshot] = []

        var pausedState = initialState
        pausedState.phaseBeforePause = .playing
        pausedState.phase = .paused
        let pausedSnapshot = GameplaySceneSnapshot(state: pausedState)
        bridge.receiveGameplaySnapshot(pausedSnapshot)
        XCTAssertTrue(receivedSnapshots.isEmpty)

        bridge.mountSnapshotPresentation { receivedSnapshots.append($0) }
        XCTAssertEqual(receivedSnapshots, [initialSnapshot])

        bridge.receiveGameplaySnapshot(pausedSnapshot)
        bridge.receiveGameplaySnapshot(pausedSnapshot)
        XCTAssertEqual(receivedSnapshots, [initialSnapshot, pausedSnapshot])

        bridge.unmountSnapshotPresentation()
        bridge.receiveGameplaySnapshot(initialSnapshot)
        XCTAssertEqual(receivedSnapshots, [initialSnapshot, pausedSnapshot])

        target.currentSnapshot = pausedSnapshot
        bridge.mountSnapshotPresentation { receivedSnapshots.append($0) }
        XCTAssertEqual(receivedSnapshots, [initialSnapshot, pausedSnapshot, pausedSnapshot])
    }

    @MainActor
    func testForegroundTransitionLeavesPausedSceneWaitingForExplicitResume() {
        var pausedState = GameState()
        pausedState.phaseBeforePause = .playing
        pausedState.phase = .paused
        let target = GameplaySceneActionTargetSpy(
            currentSnapshot: GameplaySceneSnapshot(state: pausedState)
        )
        let bridge = GameplaySceneBridge(
            target: target,
            initialResumeRequestID: 0,
            initialConfirmedExitRequestID: 0
        )
        var snapshots: [GameplaySceneSnapshot] = []
        bridge.mountSnapshotPresentation { snapshots.append($0) }

        bridge.setApplicationActive(false)
        bridge.setApplicationActive(true)

        XCTAssertEqual(target.applicationActiveValues, [false, true])
        XCTAssertEqual(target.resumeCallCount, 0)
        XCTAssertEqual(snapshots.map(\.isPaused), [true])
    }

    @MainActor
    func testDuplicateResumeRequestIsInertAndDoesNotReplaceSceneTarget() {
        let target = GameplaySceneActionTargetSpy(
            currentSnapshot: GameplaySceneSnapshot(state: GameState())
        )
        let targetIdentity = ObjectIdentifier(target)
        let bridge = GameplaySceneBridge(
            target: target,
            initialResumeRequestID: 21,
            initialConfirmedExitRequestID: 0
        )

        bridge.requestResume(id: 21)
        bridge.requestResume(id: 22)
        bridge.requestResume(id: 22)

        XCTAssertEqual(target.resumeCallCount, 1)
        XCTAssertEqual(ObjectIdentifier(target), targetIdentity)
    }

    @MainActor
    func testConfirmedExitRequestCommitsExactlyOnceForDuplicateID() {
        let target = GameplaySceneActionTargetSpy(
            currentSnapshot: GameplaySceneSnapshot(state: GameState())
        )
        let bridge = GameplaySceneBridge(
            target: target,
            initialResumeRequestID: 0,
            initialConfirmedExitRequestID: 31
        )

        bridge.requestConfirmedExit(id: 31)
        bridge.requestConfirmedExit(id: 32)
        bridge.requestConfirmedExit(id: 32)

        XCTAssertEqual(target.confirmedExitCallCount, 1)
    }
}

@MainActor
private final class GameplaySceneActionTargetSpy: GameplaySceneActionTarget {
    var currentSnapshot: GameplaySceneSnapshot
    private(set) var resumeCallCount = 0
    private(set) var confirmedExitCallCount = 0
    private(set) var applicationActiveValues: [Bool] = []

    init(currentSnapshot: GameplaySceneSnapshot) {
        self.currentSnapshot = currentSnapshot
    }

    func resume() -> Bool {
        resumeCallCount += 1
        return true
    }

    func commitConfirmedExitRun() {
        confirmedExitCallCount += 1
    }

    func setApplicationActive(_ isActive: Bool) {
        applicationActiveValues.append(isActive)
    }
}

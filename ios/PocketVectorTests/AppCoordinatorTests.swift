import Foundation
import XCTest

@testable import PocketVector

final class AppCoordinatorTests: XCTestCase {
    @MainActor
    func testLaunchStateGatesMutableShellUntilBootstrapCompletes() async {
        let coordinator = AppCoordinator()

        XCTAssertEqual(coordinator.bootstrapState, .loading)
        coordinator.showLocker()
        XCTAssertEqual(coordinator.navigationPath, [.mainMenu])

        await coordinator.bootstrap()

        XCTAssertEqual(coordinator.bootstrapState, .ready)
        XCTAssertEqual(coordinator.navigationPath, [.mainMenu])
        XCTAssertEqual(coordinator.currentDestination, .mainMenu)
        XCTAssertEqual(coordinator.catalog.teams.count, 8)
        XCTAssertEqual(coordinator.state.inventory.ownedTeamIDs.count, 4)
        XCTAssertEqual(coordinator.state.selection.selectedTeamID, LaunchTeamID.novaCityComets)
        XCTAssertEqual(coordinator.state.achievementProgress.count, 8)
    }

    @MainActor
    func testCoordinatorOwnsForwardAndBackNavigation() async {
        let coordinator = AppCoordinator()
        await coordinator.bootstrap()

        coordinator.showLocker()
        coordinator.showSettings()
        XCTAssertEqual(coordinator.navigationPath, [.mainMenu, .locker, .settings])

        coordinator.goBack()
        XCTAssertEqual(coordinator.currentDestination, .locker)

        coordinator.returnToMainMenu()
        XCTAssertEqual(coordinator.navigationPath, [.mainMenu])

        coordinator.goBack()
        XCTAssertEqual(coordinator.navigationPath, [.mainMenu])
    }

    @MainActor
    func testSelectionOnlyChangesForOwnedTeamAndUsesReturnedAuthoritativeState() async throws {
        var requests: [AppExternalRequest] = []
        var authoritativeState = AppCoordinatorState.launchDefault()
        var revision: UInt64 = 0
        let coordinator = AppCoordinator(
            environment: environment { request in
                requests.append(request)
                guard case let .updateSelection(selection) = request else {
                    return .completed
                }
                authoritativeState.selection = selection
                revision += 1
                return .applied(
                    self.authoritativeSnapshot(
                        authoritativeState,
                        playerRevision: revision
                    )
                )
            }
        )
        await coordinator.bootstrap()

        await coordinator.selectTeam(LaunchTeamID.lumaCoastPrisms)
        XCTAssertEqual(coordinator.state.selection.selectedTeamID, LaunchTeamID.novaCityComets)
        XCTAssertTrue(requests.isEmpty)

        await coordinator.selectTeam(LaunchTeamID.highMesaHelions)
        XCTAssertEqual(coordinator.state.selection.selectedTeamID, LaunchTeamID.highMesaHelions)
        XCTAssertEqual(requests, [.updateSelection(coordinator.state.selection)])

        let lockedItem = try XCTUnwrap(
            coordinator.catalog.unlockableItems.first {
                $0.kind == .team(LaunchTeamID.lumaCoastPrisms)
            }
        )
        await coordinator.requestUnlock(lockedItem.id)
        XCTAssertEqual(requests.last, .requestCatalogUnlock(lockedItem.id))
    }

    @MainActor
    func testStartRunUsesDeterministicEnvironmentAndPublishesOneSession() async throws {
        let runID = RunID(UUID(uuidString: "00000000-0000-0000-0000-000000000777")!)
        let startedAt = Date(timeIntervalSince1970: 7_000)
        var events: [AppLifecycleEvent] = []
        var completedTutorialState = AppCoordinatorState.launchDefault()
        completedTutorialState.settings.tutorialCompleted = true
        let coordinator = AppCoordinator(
            state: completedTutorialState,
            environment: AppCoordinatorEnvironment(
                loadInitialState: nil,
                makeRunID: { runID },
                makeSeed: { 91 },
                now: { startedAt },
                performExternalRequest: nil,
                observeLifecycleEvent: { events.append($0) }
            )
        )
        await coordinator.bootstrap()

        XCTAssertTrue(coordinator.startRun())
        guard case let .gameplay(configuration) = coordinator.currentDestination else {
            return XCTFail("Expected the coordinator to own the gameplay destination")
        }

        XCTAssertEqual(configuration.runID, runID)
        XCTAssertEqual(configuration.randomSeed, 91)
        XCTAssertEqual(configuration.startedAt, startedAt)
        XCTAssertEqual(configuration.offenseTeamID, LaunchTeamID.novaCityComets)
        XCTAssertNotEqual(configuration.defenseTeamID, configuration.offenseTeamID)
        XCTAssertEqual(events, [.didLaunchRun(configuration)])
    }

    @MainActor
    func testSettingsAreClampedAndCommittedFromAuthoritativeResponses() async {
        var requests: [AppExternalRequest] = []
        var authoritativeState = AppCoordinatorState.launchDefault()
        var revision: UInt64 = 0
        let coordinator = AppCoordinator(
            environment: environment { request in
                requests.append(request)
                guard case let .updateSettings(settings) = request else {
                    return .completed
                }
                authoritativeState.settings = settings
                revision += 1
                return .applied(
                    self.authoritativeSnapshot(
                        authoritativeState,
                        playerRevision: revision
                    )
                )
            }
        )
        await coordinator.bootstrap()

        await coordinator.setMusicVolume(2)
        await coordinator.setSFXVolume(-1)
        await coordinator.setMuted(true)
        await coordinator.setReducedMotion(true)
        await coordinator.setTutorialEnabled(true)
        await coordinator.setTutorialEnabled(true)

        XCTAssertEqual(coordinator.state.settings.musicVolume, 1)
        XCTAssertEqual(coordinator.state.settings.sfxVolume, 0)
        XCTAssertTrue(coordinator.state.settings.isMuted)
        XCTAssertTrue(coordinator.state.settings.reducedMotion)
        XCTAssertFalse(coordinator.state.settings.tutorialCompleted)
        XCTAssertEqual(requests.count, 4, "The unchanged tutorial value must not emit a duplicate write")
        XCTAssertEqual(requests.last, .updateSettings(coordinator.state.settings))
    }

    @MainActor
    func testResultsReplayReplacesResultsBeforeStartingNewSession() async {
        var sequence = 0
        let environment = AppCoordinatorEnvironment(
            loadInitialState: nil,
            makeRunID: {
                sequence += 1
                return RunID(
                    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", sequence))!
                )
            },
            makeSeed: { UInt32(sequence) },
            now: { Date(timeIntervalSince1970: TimeInterval(sequence)) },
            performExternalRequest: nil,
            observeLifecycleEvent: nil
        )
        var completedTutorialState = AppCoordinatorState.launchDefault()
        completedTutorialState.settings.tutorialCompleted = true
        let coordinator = AppCoordinator(
            state: completedTutorialState,
            environment: environment
        )
        await coordinator.bootstrap()

        XCTAssertTrue(coordinator.startRun())
        guard case let .gameplay(firstConfiguration) = coordinator.currentDestination else {
            return XCTFail("Expected gameplay")
        }

        let results = makeResults(configuration: firstConfiguration)
        coordinator.showRunResults(results)
        XCTAssertEqual(coordinator.currentDestination, .runResults(results))

        coordinator.replayAfterResults()
        guard case let .gameplay(replayConfiguration) = coordinator.currentDestination else {
            return XCTFail("Expected replay gameplay")
        }
        XCTAssertEqual(
            coordinator.navigationPath,
            [.mainMenu, .gameplay(replayConfiguration)]
        )
        XCTAssertNotEqual(replayConfiguration.runID, firstConfiguration.runID)
    }

    @MainActor
    func testUnavailablePlatformActionsExplainRatherThanPretendToExecute() async {
        let coordinator = AppCoordinator()
        await coordinator.bootstrap()

        await coordinator.requestLeaderboard()
        XCTAssertNotNil(coordinator.noticeMessage)
        coordinator.dismissNotice()

        await coordinator.requestCoinPack(EconomyConfiguration.coinPacks[0].id)
        XCTAssertEqual(coordinator.noticeMessage, "Purchases are not enabled in this build.")
    }

    @MainActor
    func testFailedProfileMutationRollsBackOptimisticStateAndSurfacesFailure() async {
        let initialState = AppCoordinatorState.launchDefault()
        let coordinator = AppCoordinator(
            state: initialState,
            environment: environment { request in
                guard case .updateSelection = request else { return .completed }
                return .failed(message: "Profile could not be saved.")
            }
        )
        await coordinator.bootstrap()

        await coordinator.selectTeam(LaunchTeamID.highMesaHelions)

        XCTAssertEqual(coordinator.state, initialState)
        XCTAssertEqual(coordinator.noticeMessage, "Profile could not be saved.")
        XCTAssertNil(coordinator.pendingRequest)
    }

    @MainActor
    func testPlatformRequestTracksInFlightStateAndHandlesFailureWithoutStateMutation() async {
        let initialState = AppCoordinatorState.launchDefault()
        var coordinator: AppCoordinator!
        var observedPending: AppExternalRequest?
        coordinator = AppCoordinator(
            state: initialState,
            environment: environment { request in
                observedPending = coordinator.pendingRequest
                return .failed(message: "Game Center is unavailable.")
            }
        )
        await coordinator.bootstrap()

        await coordinator.requestLeaderboard()

        XCTAssertEqual(observedPending, .showLeaderboard)
        XCTAssertNil(coordinator.pendingRequest)
        XCTAssertEqual(coordinator.state, initialState)
        XCTAssertEqual(coordinator.noticeMessage, "Game Center is unavailable.")
    }

    @MainActor
    func testOrdinaryCommerceAppliedResultCannotReplaceProfileSession() async {
        let initialState = AppCoordinatorState.launchDefault()
        var changedState = initialState
        changedState.confirmedCoins = 99_999
        let mismatched = AuthoritativeAppStateSnapshot(
            session: ProfileSessionToken(
                accountIdentity: PlayerAccountIdentity("unverified-account"),
                nonce: UUID(),
                profileID: UUID()
            ),
            playerRevision: 1,
            economyRevision: 1,
            state: changedState
        )
        let coordinator = AppCoordinator(
            state: initialState,
            environment: environment { request in
                guard case .requestCoinPack = request else { return .completed }
                return .applied(mismatched)
            }
        )
        await coordinator.bootstrap()
        let before = coordinator.authoritativeSnapshot

        await coordinator.requestCoinPack(EconomyConfiguration.coinPacks[0].id)

        XCTAssertEqual(coordinator.authoritativeSnapshot, before)
        XCTAssertEqual(coordinator.state, initialState)
        XCTAssertEqual(
            coordinator.noticeMessage,
            "The profile service returned an invalid account state."
        )
    }

    @MainActor
    func testBootstrapFailureIsRecoverableAndDoesNotExposePlaceholderState() async {
        var attempts = 0
        var loadedState = AppCoordinatorState.launchDefault()
        loadedState.personalBest = 44_400
        let coordinator = AppCoordinator(
            environment: AppCoordinatorEnvironment(
                loadInitialState: {
                    attempts += 1
                    if attempts == 1 {
                        return .failed(message: "Saved profile is temporarily unavailable.")
                    }
                    return .loaded(self.authoritativeSnapshot(loadedState))
                },
                makeRunID: { RunID() },
                makeSeed: { 1 },
                now: { Date(timeIntervalSince1970: 1) },
                performExternalRequest: nil,
                observeLifecycleEvent: nil
            )
        )

        await coordinator.bootstrap()
        XCTAssertEqual(
            coordinator.bootstrapState,
            .failed(message: "Saved profile is temporarily unavailable.")
        )
        coordinator.showLocker()
        XCTAssertEqual(coordinator.navigationPath, [.mainMenu])

        await coordinator.bootstrap()
        XCTAssertEqual(coordinator.bootstrapState, .ready)
        XCTAssertEqual(coordinator.state.personalBest, 44_400)
        XCTAssertEqual(attempts, 2)
    }

    @MainActor
    private func environment(
        handler: @escaping @MainActor (AppExternalRequest) async -> AppExternalRequestResult
    ) -> AppCoordinatorEnvironment {
        AppCoordinatorEnvironment(
            loadInitialState: {
                .loaded(self.authoritativeSnapshot(.launchDefault()))
            },
            makeRunID: { RunID(UUID(uuidString: "00000000-0000-0000-0000-000000000001")!) },
            makeSeed: { 1 },
            now: { Date(timeIntervalSince1970: 1) },
            performExternalRequest: handler,
            observeLifecycleEvent: nil
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
                nonce: UUID(uuidString: "00000000-0000-0000-0000-000000000091")!,
                profileID: UUID(uuidString: "00000000-0000-0000-0000-000000000092")!
            ),
            playerRevision: playerRevision,
            economyRevision: economyRevision,
            state: state
        )
    }

    private func makeResults(configuration: RunConfiguration) -> RunResultsPresentation {
        let run = CompletedRun(
            configuration: configuration,
            endedAt: configuration.startedAt.addingTimeInterval(60),
            elapsedGameplayMilliseconds: 60_000,
            finishReason: .timerExpired,
            score: 12_500,
            statistics: RunStatisticsSnapshot(
                attempts: 10,
                completions: 6,
                touchdowns: 2,
                incompletions: 1,
                interceptions: 1,
                longestTouchdownStreak: 2
            ),
            completedLaneIDs: [],
            bonusTouchdownCount: 0
        )
        return RunResultsPresentation(
            completedRun: run,
            earnedCoins: 22,
            pendingCoins: 22,
            personalBest: run.score,
            isNewPersonalBest: true,
            rewardedAdOffer: .progress(validRuns: 1, requiredRuns: 5)
        )
    }
}

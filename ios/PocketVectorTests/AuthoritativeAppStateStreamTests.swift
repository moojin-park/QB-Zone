import Foundation
import XCTest

@testable import PocketVector

final class AuthoritativeAppStateStreamTests: XCTestCase, @unchecked Sendable {
    @MainActor
    func testNewerSameSessionSnapshotAppliesMonotonically() async {
        let initial = snapshot(playerRevision: 2, economyRevision: 3)
        let coordinator = makeCoordinator(initial: initial)
        await coordinator.bootstrap()

        var newerState = initial.state
        newerState.confirmedCoins = 1_500
        let newer = snapshot(
            state: newerState,
            playerRevision: 3,
            economyRevision: 4
        )

        XCTAssertEqual(coordinator.applyAuthoritativeUpdate(newer), .applied)
        XCTAssertEqual(coordinator.authoritativeSnapshot, newer)
        XCTAssertEqual(coordinator.state, newerState)
    }

    @MainActor
    func testExactDuplicateIsIgnoredIdempotently() async {
        let initial = snapshot(playerRevision: 4, economyRevision: 2)
        let coordinator = makeCoordinator(initial: initial)
        await coordinator.bootstrap()

        XCTAssertEqual(
            coordinator.applyAuthoritativeUpdate(initial),
            .duplicateIgnored
        )
        XCTAssertEqual(coordinator.authoritativeSnapshot, initial)
    }

    @MainActor
    func testStaleOrIncomparableRevisionIsRejectedWithoutRegression() async {
        let initial = snapshot(playerRevision: 5, economyRevision: 5)
        let coordinator = makeCoordinator(initial: initial)
        await coordinator.bootstrap()

        var staleState = initial.state
        staleState.personalBest = 99_999
        let stale = snapshot(
            state: staleState,
            playerRevision: 4,
            economyRevision: 6
        )

        XCTAssertEqual(
            coordinator.applyAuthoritativeUpdate(stale),
            .rejected(.staleRevision)
        )
        XCTAssertEqual(coordinator.authoritativeSnapshot, initial)
        XCTAssertEqual(coordinator.state, initial.state)
    }

    @MainActor
    func testEqualRevisionDivergentStateIsRejectedAsCollision() async {
        let initial = snapshot(playerRevision: 7, economyRevision: 8)
        let coordinator = makeCoordinator(initial: initial)
        await coordinator.bootstrap()

        var collisionState = initial.state
        collisionState.pendingCoins = 777
        let collision = snapshot(
            state: collisionState,
            playerRevision: 7,
            economyRevision: 8
        )

        XCTAssertEqual(
            coordinator.applyAuthoritativeUpdate(collision),
            .rejected(.revisionCollision)
        )
        XCTAssertEqual(coordinator.authoritativeSnapshot, initial)
        XCTAssertEqual(coordinator.state, initial.state)
    }

    @MainActor
    func testPlayerRevisionAdvanceCannotCarryAnUnversionedEconomyMutation() async {
        let initial = snapshot(playerRevision: 3, economyRevision: 5)
        let coordinator = makeCoordinator(initial: initial)
        await coordinator.bootstrap()

        var malformedState = initial.state
        malformedState.pendingCoins = 500
        let malformed = snapshot(
            state: malformedState,
            playerRevision: 4,
            economyRevision: 5
        )

        XCTAssertEqual(
            coordinator.applyAuthoritativeUpdate(malformed),
            .rejected(.revisionCollision)
        )
        XCTAssertEqual(coordinator.authoritativeSnapshot, initial)
        XCTAssertEqual(coordinator.state, initial.state)
    }

    @MainActor
    func testPlayerRevisionAdvanceCannotGrantInventoryWithoutEconomyRevision() async {
        let initial = snapshot(playerRevision: 3, economyRevision: 5)
        let coordinator = makeCoordinator(initial: initial)
        await coordinator.bootstrap()

        var malformedState = initial.state
        malformedState.inventory.ownedTeamIDs.insert(LaunchTeamID.lumaCoastPrisms)
        let malformed = snapshot(
            state: malformedState,
            playerRevision: 4,
            economyRevision: 5
        )

        XCTAssertEqual(
            coordinator.applyAuthoritativeUpdate(malformed),
            .rejected(.revisionCollision)
        )
        XCTAssertEqual(coordinator.authoritativeSnapshot, initial)
    }

    @MainActor
    func testPlayerRevisionAdvanceCannotChangeRewardEligibilityWithoutEconomyRevision() async {
        let initial = snapshot(playerRevision: 3, economyRevision: 5)
        let coordinator = makeCoordinator(initial: initial)
        await coordinator.bootstrap()

        var malformedState = initial.state
        _ = malformedState.rewardedAdState.recordValidRun(
            RunID(UUID(uuidString: "00000000-0000-0000-0000-000000000551")!)
        )
        let malformed = snapshot(
            state: malformedState,
            playerRevision: 4,
            economyRevision: 5
        )

        XCTAssertEqual(
            coordinator.applyAuthoritativeUpdate(malformed),
            .rejected(.revisionCollision)
        )
        XCTAssertEqual(coordinator.authoritativeSnapshot, initial)
    }

    @MainActor
    func testEconomyRevisionAdvanceCannotCarryAnUnversionedPlayerMutation() async {
        let initial = snapshot(playerRevision: 3, economyRevision: 5)
        let coordinator = makeCoordinator(initial: initial)
        await coordinator.bootstrap()

        var malformedState = initial.state
        malformedState.settings = PlayerSettings(isMuted: true)
        let malformed = snapshot(
            state: malformedState,
            playerRevision: 3,
            economyRevision: 6
        )

        XCTAssertEqual(
            coordinator.applyAuthoritativeUpdate(malformed),
            .rejected(.revisionCollision)
        )
        XCTAssertEqual(coordinator.authoritativeSnapshot, initial)
        XCTAssertEqual(coordinator.state, initial.state)
    }

    @MainActor
    func testMismatchedSessionIsRejectedAsAccountBoundary() async {
        let initial = snapshot(playerRevision: 1, economyRevision: 1)
        let coordinator = makeCoordinator(initial: initial)
        await coordinator.bootstrap()

        let otherSession = ProfileSessionToken(
            accountIdentity: PlayerAccountIdentity("other-account"),
            nonce: UUID(uuidString: "00000000-0000-0000-0000-000000000099")!,
            profileID: initial.session.profileID
        )
        let foreign = AuthoritativeAppStateSnapshot(
            session: otherSession,
            playerRevision: 2,
            economyRevision: 2,
            state: initial.state
        )

        XCTAssertEqual(
            coordinator.applyAuthoritativeUpdate(foreign),
            .rejected(.sessionMismatch)
        )
        XCTAssertEqual(coordinator.authoritativeSnapshot, initial)
    }

    @MainActor
    func testUpdateBeforeBootstrapCannotEstablishAnUnverifiedSession() {
        let update = snapshot(playerRevision: 1, economyRevision: 1)
        let coordinator = AppCoordinator()

        XCTAssertEqual(
            coordinator.applyAuthoritativeUpdate(update),
            .rejected(.sessionNotEstablished)
        )
        XCTAssertNil(coordinator.authoritativeSnapshot)
    }

    @MainActor
    func testBufferingNewestDeliversTheLatestCompleteSnapshot() async {
        let channel = ProductionAuthoritativeStateChannel()
        let initial = snapshot()
        let coordinator = makeCoordinator(initial: initial, channel: channel)

        for revision in UInt64(1) ... 3 {
            var state = initial.state
            state.personalBest = Int(revision) * 1_000
            channel.publish(
                snapshot(state: state, playerRevision: revision)
            )
        }

        let consumer = Task { @MainActor in
            await coordinator.run()
        }
        await waitUntil { coordinator.state.personalBest == 3_000 }

        XCTAssertEqual(coordinator.authoritativeSnapshot?.playerRevision, 3)
        XCTAssertEqual(coordinator.state.personalBest, 3_000)

        consumer.cancel()
        await consumer.value
    }

    @MainActor
    func testCancellationPreventsLaterStreamMutation() async {
        let channel = ProductionAuthoritativeStateChannel()
        let initial = snapshot()
        let coordinator = makeCoordinator(initial: initial, channel: channel)
        let consumer = Task { @MainActor in
            await coordinator.run()
        }
        await waitUntil { coordinator.bootstrapState == .ready }

        consumer.cancel()
        await consumer.value

        var laterState = initial.state
        laterState.personalBest = 44_000
        channel.publish(snapshot(state: laterState, playerRevision: 1))
        await Task.yield()

        XCTAssertEqual(coordinator.authoritativeSnapshot, initial)
        XCTAssertEqual(coordinator.state.personalBest, 0)
    }

    @MainActor
    func testCancellationThenSecondRunResubscribesAndReplaysLatestSnapshot() async {
        let channel = ProductionAuthoritativeStateChannel()
        let initial = snapshot()
        let coordinator = makeCoordinator(initial: initial, channel: channel)
        await coordinator.bootstrap()

        let firstConsumer = Task { @MainActor in await coordinator.run() }
        await waitUntil {
            coordinator.stateUpdateConsumerIsRunning && channel.subscriberCount == 1
        }
        firstConsumer.cancel()
        await firstConsumer.value
        await waitUntil {
            !coordinator.stateUpdateConsumerIsRunning && channel.subscriberCount == 0
        }

        var latestState = initial.state
        latestState.personalBest = 61_000
        let latest = snapshot(state: latestState, playerRevision: 1)
        channel.publish(latest)
        XCTAssertEqual(coordinator.authoritativeSnapshot, initial)

        let secondConsumer = Task { @MainActor in await coordinator.run() }
        await waitUntil {
            coordinator.authoritativeSnapshot == latest
                && coordinator.stateUpdateConsumerIsRunning
                && channel.subscriberCount == 1
        }

        var followingState = latestState
        followingState.pendingCoins = 17
        let following = snapshot(
            state: followingState,
            playerRevision: 2,
            economyRevision: 1
        )
        channel.publish(following)
        await waitUntil { coordinator.authoritativeSnapshot == following }

        secondConsumer.cancel()
        await secondConsumer.value
        await waitUntil { channel.subscriberCount == 0 }
    }

    @MainActor
    func testConcurrentRunAttemptDoesNotCreateSecondSubscription() async {
        let channel = ProductionAuthoritativeStateChannel()
        let initial = snapshot()
        let coordinator = makeCoordinator(initial: initial, channel: channel)
        await coordinator.bootstrap()

        let firstConsumer = Task { @MainActor in await coordinator.run() }
        await waitUntil {
            coordinator.stateUpdateConsumerIsRunning && channel.subscriberCount == 1
        }
        let duplicateConsumer = Task { @MainActor in await coordinator.run() }
        await duplicateConsumer.value

        XCTAssertTrue(coordinator.stateUpdateConsumerIsRunning)
        XCTAssertEqual(channel.subscriberCount, 1)

        firstConsumer.cancel()
        await firstConsumer.value
        await waitUntil {
            !coordinator.stateUpdateConsumerIsRunning && channel.subscriberCount == 0
        }
    }

    @MainActor
    func testCancellationDuringBootstrapPreventsLateLoadMutation() async {
        var continuation: CheckedContinuation<AppBootstrapLoadResult, Never>?
        let coordinator = AppCoordinator(
            environment: AppCoordinatorEnvironment(
                loadInitialState: {
                    await withCheckedContinuation { continuation = $0 }
                },
                makeRunID: { RunID() },
                makeSeed: { 1 },
                now: { Date(timeIntervalSince1970: 1) },
                performExternalRequest: nil,
                observeLifecycleEvent: nil
            )
        )
        let consumer = Task { @MainActor in await coordinator.run() }
        await waitUntil { continuation != nil }

        var loadedState = AppCoordinatorState.launchDefault()
        loadedState.personalBest = 52_000
        consumer.cancel()
        continuation?.resume(
            returning: .loaded(
                snapshot(state: loadedState, playerRevision: 9, economyRevision: 4)
            )
        )
        await consumer.value

        XCTAssertEqual(coordinator.bootstrapState, .loading)
        XCTAssertNil(coordinator.authoritativeSnapshot)
        XCTAssertEqual(coordinator.state.personalBest, 0)
    }

    @MainActor
    func testDirectResponseAndDuplicateStreamPublicationAreIdempotent() async {
        let channel = ProductionAuthoritativeStateChannel()
        let initial = snapshot()
        var updatedState = initial.state
        updatedState.settings = PlayerSettings(isMuted: true)
        let updated = snapshot(state: updatedState, playerRevision: 1)
        let coordinator = AppCoordinator(
            environment: AppCoordinatorEnvironment(
                loadInitialState: { .loaded(initial) },
                makeAuthoritativeStateUpdates: { channel.makeStream() },
                makeRunID: { RunID() },
                makeSeed: { 1 },
                now: { Date(timeIntervalSince1970: 1) },
                performExternalRequest: { request in
                    guard case .updateSettings = request else { return .completed }
                    channel.publish(updated)
                    return .applied(updated)
                },
                observeLifecycleEvent: nil
            )
        )
        let consumer = Task { @MainActor in await coordinator.run() }
        await waitUntil { coordinator.bootstrapState == .ready }

        await coordinator.setMuted(true)
        await Task.yield()

        XCTAssertEqual(coordinator.authoritativeSnapshot, updated)
        XCTAssertTrue(coordinator.state.settings.isMuted)
        XCTAssertNil(coordinator.noticeMessage)

        consumer.cancel()
        await consumer.value
    }

    @MainActor
    func testLaterStaleResponseCannotOverwriteNewerStreamState() async {
        let channel = ProductionAuthoritativeStateChannel()
        let initial = snapshot()
        var continuation: CheckedContinuation<AppExternalRequestResult, Never>?
        let coordinator = AppCoordinator(
            environment: AppCoordinatorEnvironment(
                loadInitialState: { .loaded(initial) },
                makeAuthoritativeStateUpdates: { channel.makeStream() },
                makeRunID: { RunID() },
                makeSeed: { 1 },
                now: { Date(timeIntervalSince1970: 1) },
                performExternalRequest: { request in
                    guard case .updateSettings = request else { return .completed }
                    return await withCheckedContinuation { continuation = $0 }
                },
                observeLifecycleEvent: nil
            )
        )
        let consumer = Task { @MainActor in await coordinator.run() }
        await waitUntil { coordinator.bootstrapState == .ready }

        let mutation = Task { @MainActor in await coordinator.setMuted(true) }
        await waitUntil { continuation != nil }

        var newestState = initial.state
        newestState.personalBest = 25_000
        let newest = snapshot(state: newestState, playerRevision: 2)
        channel.publish(newest)
        await waitUntil { coordinator.authoritativeSnapshot == newest }

        var staleState = initial.state
        staleState.settings = PlayerSettings(isMuted: true)
        continuation?.resume(
            returning: .applied(
                snapshot(state: staleState, playerRevision: 1)
            )
        )
        await mutation.value

        XCTAssertEqual(coordinator.authoritativeSnapshot, newest)
        XCTAssertEqual(coordinator.state, newestState)

        consumer.cancel()
        await consumer.value
    }

    @MainActor
    func testLateFailedResponseCannotRollbackNewerStreamState() async {
        await assertLateNonStateResponsePreservesNewerState(
            .failed(message: "Save failed."),
            expectedNotice: "Save failed."
        )
    }

    @MainActor
    func testLateCompletedResponseCannotRollbackNewerStreamState() async {
        await assertLateNonStateResponsePreservesNewerState(
            .completed,
            expectedNotice: "The profile service did not return an updated player state."
        )
    }

    @MainActor
    func testBackgroundUpdatePreservesGameplayDestinationAndConfiguration() async throws {
        var playableState = AppCoordinatorState.launchDefault()
        playableState.settings.tutorialCompleted = true
        let initial = snapshot(state: playableState)
        let coordinator = AppCoordinator(
            environment: AppCoordinatorEnvironment(
                loadInitialState: { .loaded(initial) },
                makeRunID: {
                    RunID(UUID(uuidString: "00000000-0000-0000-0000-000000000777")!)
                },
                makeSeed: { 777 },
                now: { Date(timeIntervalSince1970: 7_777) },
                performExternalRequest: nil,
                observeLifecycleEvent: nil
            )
        )
        await coordinator.bootstrap()
        XCTAssertTrue(coordinator.startRun())
        guard case let .gameplay(configuration) = coordinator.currentDestination else {
            return XCTFail("Expected gameplay")
        }

        var backgroundState = playableState
        backgroundState.selection.selectedTeamID = LaunchTeamID.highMesaHelions
        let update = snapshot(state: backgroundState, playerRevision: 1)

        XCTAssertEqual(coordinator.applyAuthoritativeUpdate(update), .applied)
        XCTAssertEqual(coordinator.currentDestination, .gameplay(configuration))
        XCTAssertEqual(
            coordinator.navigationPath,
            [.mainMenu, .gameplay(configuration)]
        )
        XCTAssertEqual(configuration.offenseTeamID, LaunchTeamID.novaCityComets)
        XCTAssertEqual(
            coordinator.state.selection.selectedTeamID,
            LaunchTeamID.highMesaHelions
        )
    }

    @MainActor
    private func makeCoordinator(
        initial: AuthoritativeAppStateSnapshot,
        channel: ProductionAuthoritativeStateChannel? = nil
    ) -> AppCoordinator {
        let makeUpdates: (@MainActor () -> AsyncStream<AuthoritativeAppStateSnapshot>)?
        if let channel {
            makeUpdates = { channel.makeStream() }
        } else {
            makeUpdates = nil
        }
        return AppCoordinator(
            environment: AppCoordinatorEnvironment(
                loadInitialState: { .loaded(initial) },
                makeAuthoritativeStateUpdates: makeUpdates,
                makeRunID: { RunID() },
                makeSeed: { 1 },
                now: { Date(timeIntervalSince1970: 1) },
                performExternalRequest: nil,
                observeLifecycleEvent: nil
            )
        )
    }

    @MainActor
    private func assertLateNonStateResponsePreservesNewerState(
        _ response: AppExternalRequestResult,
        expectedNotice: String
    ) async {
        let channel = ProductionAuthoritativeStateChannel()
        let initial = snapshot()
        var continuation: CheckedContinuation<AppExternalRequestResult, Never>?
        let coordinator = AppCoordinator(
            environment: AppCoordinatorEnvironment(
                loadInitialState: { .loaded(initial) },
                makeAuthoritativeStateUpdates: { channel.makeStream() },
                makeRunID: { RunID() },
                makeSeed: { 1 },
                now: { Date(timeIntervalSince1970: 1) },
                performExternalRequest: { request in
                    guard case .updateSettings = request else { return .completed }
                    return await withCheckedContinuation { continuation = $0 }
                },
                observeLifecycleEvent: nil
            )
        )
        let consumer = Task { @MainActor in await coordinator.run() }
        await waitUntil { coordinator.bootstrapState == .ready }

        let mutation = Task { @MainActor in await coordinator.setMuted(true) }
        await waitUntil { continuation != nil }

        var newestState = initial.state
        newestState.personalBest = 31_000
        let newest = snapshot(state: newestState, playerRevision: 2)
        channel.publish(newest)
        await waitUntil { coordinator.authoritativeSnapshot == newest }

        continuation?.resume(returning: response)
        await mutation.value

        XCTAssertEqual(coordinator.authoritativeSnapshot, newest)
        XCTAssertEqual(coordinator.state, newestState)
        XCTAssertEqual(coordinator.noticeMessage, expectedNotice)

        consumer.cancel()
        await consumer.value
    }

    @MainActor
    private func snapshot(
        state: AppCoordinatorState = .launchDefault(),
        playerRevision: UInt64 = 0,
        economyRevision: UInt64 = 0
    ) -> AuthoritativeAppStateSnapshot {
        AuthoritativeAppStateSnapshot(
            session: ProfileSessionToken(
                accountIdentity: .local,
                nonce: UUID(uuidString: "00000000-0000-0000-0000-000000000041")!,
                profileID: UUID(uuidString: "00000000-0000-0000-0000-000000000042")!
            ),
            playerRevision: playerRevision,
            economyRevision: economyRevision,
            state: state
        )
    }

    @MainActor
    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool,
        iterations: Int = 1_000
    ) async {
        for _ in 0 ..< iterations {
            if condition() { return }
            await Task.yield()
        }
        XCTFail("Timed out waiting for deterministic async state")
    }
}

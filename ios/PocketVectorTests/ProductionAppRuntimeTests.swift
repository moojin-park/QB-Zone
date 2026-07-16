import Foundation
import XCTest

@testable import PocketVector

final class ProductionAppRuntimeTests: XCTestCase, @unchecked Sendable {
    @MainActor
    func testRuntimeRetainsCompositionAndDiagnosticsGraph() throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let recorder = RuntimeTelemetryCapture()
        let reporter = RuntimeDiagnosticsCapture()
        var diagnostics: AppleDiagnosticsRuntime? = makeDiagnostics(
            recorder: recorder,
            reporter: reporter
        )
        let diagnosticsBox = WeakRuntimeBox(diagnostics)
        let channel = ProductionAuthoritativeStateChannel()
        var composition: ProductionAppComposition? = makeComposition(
            root: root,
            channel: channel,
            sink: diagnostics?.sink
        )
        let compositionBox = WeakRuntimeBox(composition)
        var runtime: ProductionAppRuntime? = ProductionAppRuntime(
            coordinator: AppCoordinator(environment: composition!.environment),
            presentationHandoff: UIKitGameKitPresentationHandoff(),
            serviceConfiguration: .parse(infoDictionary: [:]),
            runtimeCapabilities: .appleDiagnosticsOnly,
            composition: composition,
            authoritativeStateChannel: channel,
            diagnostics: diagnostics!
        )

        composition = nil
        diagnostics = nil

        XCTAssertNotNil(compositionBox.value)
        XCTAssertNotNil(diagnosticsBox.value)
        XCTAssertNotNil(runtime?.coordinator)

        runtime = nil
        XCTAssertNil(compositionBox.value)
        XCTAssertNil(diagnosticsBox.value)
    }

    @MainActor
    func testLocalGameplayBootsWithEveryExternalCapabilityUnavailable() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let harness = makeRuntime(root: root)

        await harness.runtime.coordinator.bootstrap()

        XCTAssertEqual(harness.runtime.coordinator.bootstrapState, .ready)
        XCTAssertEqual(
            harness.runtime.runtimeCapabilities.serviceAvailability,
            .unconfigured
        )
        XCTAssertEqual(harness.runtime.coordinator.state.inventory.ownedTeamIDs.count, 4)
        XCTAssertTrue(harness.runtime.coordinator.startRun())
        guard case .tutorial(.beforeRun) = harness.runtime.coordinator.currentDestination else {
            return XCTFail("A fresh local profile should show the first-run tutorial")
        }

        await harness.runtime.coordinator.completeTutorial()

        guard case .gameplay = harness.runtime.coordinator.currentDestination else {
            return XCTFail("Local gameplay should launch after tutorial persistence")
        }
    }

    @MainActor
    func testValidStoreIdentifiersStillCannotPurchaseUnlockRewardOrAdvertiseServices() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let recorder = RuntimeTelemetryCapture()
        let reporter = RuntimeDiagnosticsCapture()
        let diagnostics = makeDiagnostics(recorder: recorder, reporter: reporter)
        let configuration = validStoreKitConfiguration()
        let harness = makeRuntime(
            root: root,
            serviceConfiguration: configuration,
            diagnostics: diagnostics
        )
        let diagnosticsTask = Task { await diagnostics.run() }
        defer { diagnosticsTask.cancel() }

        await harness.runtime.coordinator.bootstrap()
        let before = harness.runtime.coordinator.state
        guard case .validated = harness.runtime.serviceConfiguration.storeKit else {
            return XCTFail("The test fixture must contain valid StoreKit identifiers")
        }
        XCTAssertEqual(
            harness.runtime.runtimeCapabilities.serviceAvailability,
            .unconfigured
        )

        harness.runtime.coordinator.showCoinStore()
        await harness.runtime.coordinator.requestCoinPack(
            EconomyConfiguration.coinPacks[0].id
        )
        let lockedItem = try XCTUnwrap(
            harness.runtime.coordinator.catalog.unlockableItems.first
        )
        await harness.runtime.coordinator.requestUnlock(lockedItem.id)
        await harness.runtime.coordinator.requestRewardedAd(
            RewardOfferID("runtime-test-offer")
        )
        await harness.runtime.coordinator.requestLeaderboard()

        XCTAssertEqual(harness.runtime.coordinator.state, before)
        let telemetryArrived = await eventually {
            await recorder.payloads().count == 1
        }
        let payloads = await recorder.payloads()
        XCTAssertTrue(telemetryArrived)
        XCTAssertEqual(payloads, [.storeOpened])

        diagnosticsTask.cancel()
        await diagnosticsTask.value
    }

    @MainActor
    func testDiagnosticsRegistrationFailureDoesNotBlockProfileBootstrap() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let diagnostics = makeDiagnostics(
            recorder: RuntimeTelemetryCapture(),
            reporter: RuntimeDiagnosticsCapture(),
            registration: FailingRuntimeMetricKitRegistration()
        )
        let harness = makeRuntime(root: root, diagnostics: diagnostics)
        let diagnosticsTask = Task { await diagnostics.run() }

        await harness.runtime.coordinator.bootstrap()

        XCTAssertEqual(harness.runtime.coordinator.bootstrapState, .ready)
        XCTAssertNotNil(harness.runtime.coordinator.authoritativeSnapshot)

        diagnosticsTask.cancel()
        await diagnosticsTask.value
    }

    @MainActor
    func testRuntimeStartsDiagnosticsOnceAndCancelsItOnDeinit() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let registration = CountingRuntimeMetricKitRegistration()
        let diagnostics = makeDiagnostics(
            recorder: RuntimeTelemetryCapture(),
            reporter: RuntimeDiagnosticsCapture(),
            registration: registration
        )
        let channel = ProductionAuthoritativeStateChannel()
        let composition = makeComposition(
            root: root,
            channel: channel,
            sink: diagnostics.sink
        )
        var runtime: ProductionAppRuntime? = ProductionAppRuntime(
            coordinator: AppCoordinator(environment: composition.environment),
            presentationHandoff: UIKitGameKitPresentationHandoff(),
            serviceConfiguration: .parse(infoDictionary: [:]),
            runtimeCapabilities: .appleDiagnosticsOnly,
            composition: composition,
            authoritativeStateChannel: channel,
            diagnostics: diagnostics
        )

        runtime?.startAppleDiagnostics()
        runtime?.startAppleDiagnostics()
        let registeredOnce = await eventually {
            registration.snapshot().registerCalls == 1
        }
        XCTAssertTrue(registeredOnce)

        runtime = nil
        let unregisteredOnce = await eventually {
            registration.snapshot().unregisterCalls == 1
        }
        XCTAssertTrue(unregisteredOnce)
        XCTAssertEqual(
            registration.snapshot(),
            .init(registerCalls: 1, unregisterCalls: 1)
        )
    }

    @MainActor
    func testRuntimeOwnsOneCoordinatorConsumerAndCancelsItOnDeinit() async throws {
        let channel = ProductionAuthoritativeStateChannel()
        let initial = runtimeSnapshot(
            state: .launchDefault(),
            identity: 15
        )
        let coordinator = AppCoordinator(
            environment: AppCoordinatorEnvironment(
                loadInitialState: { .loaded(initial) },
                makeAuthoritativeStateUpdates: { channel.makeStream() },
                makeRunID: { RunID() },
                makeSeed: { 15 },
                now: { Date(timeIntervalSince1970: 15) },
                performExternalRequest: nil,
                observeLifecycleEvent: nil
            )
        )
        let diagnostics = makeDiagnostics(
            recorder: RuntimeTelemetryCapture(),
            reporter: RuntimeDiagnosticsCapture()
        )
        var runtime: ProductionAppRuntime? = ProductionAppRuntime(
            coordinator: coordinator,
            presentationHandoff: UIKitGameKitPresentationHandoff(),
            serviceConfiguration: .parse(infoDictionary: [:]),
            runtimeCapabilities: .appleDiagnosticsOnly,
            composition: nil,
            authoritativeStateChannel: channel,
            diagnostics: diagnostics
        )

        runtime?.startCoordinator()
        runtime?.startCoordinator()
        let subscribedOnce = await waitUntilMainActor {
            runtime?.coordinatorTaskIsRunning == true
                && coordinator.stateUpdateConsumerIsRunning
                && channel.subscriberCount == 1
        }
        XCTAssertTrue(subscribedOnce)

        runtime = nil
        let cancelled = await waitUntilMainActor {
            !coordinator.stateUpdateConsumerIsRunning
                && channel.subscriberCount == 0
        }
        XCTAssertTrue(cancelled)
    }

    @MainActor
    func testFailedCoordinatorAttemptClearsRuntimeTaskAndCanRetry() async throws {
        let channel = ProductionAuthoritativeStateChannel()
        let initial = runtimeSnapshot(
            state: .launchDefault(),
            identity: 16
        )
        var loadAttempts = 0
        let coordinator = AppCoordinator(
            environment: AppCoordinatorEnvironment(
                loadInitialState: {
                    loadAttempts += 1
                    if loadAttempts == 1 {
                        return .failed(message: "Expected first-attempt failure")
                    }
                    return .loaded(initial)
                },
                makeAuthoritativeStateUpdates: { channel.makeStream() },
                makeRunID: { RunID() },
                makeSeed: { 16 },
                now: { Date(timeIntervalSince1970: 16) },
                performExternalRequest: nil,
                observeLifecycleEvent: nil
            )
        )
        let diagnostics = makeDiagnostics(
            recorder: RuntimeTelemetryCapture(),
            reporter: RuntimeDiagnosticsCapture()
        )
        var runtime: ProductionAppRuntime? = ProductionAppRuntime(
            coordinator: coordinator,
            presentationHandoff: UIKitGameKitPresentationHandoff(),
            serviceConfiguration: .parse(infoDictionary: [:]),
            runtimeCapabilities: .appleDiagnosticsOnly,
            composition: nil,
            authoritativeStateChannel: channel,
            diagnostics: diagnostics
        )

        runtime?.startCoordinator()
        let firstAttemptFinished = await waitUntilMainActor {
            coordinator.bootstrapState
                == .failed(message: "Expected first-attempt failure")
                && runtime?.coordinatorTaskIsRunning == false
        }
        XCTAssertTrue(firstAttemptFinished)
        XCTAssertEqual(loadAttempts, 1)

        runtime?.startCoordinator()
        let retrySubscribed = await waitUntilMainActor {
            coordinator.bootstrapState == .ready
                && runtime?.coordinatorTaskIsRunning == true
                && coordinator.stateUpdateConsumerIsRunning
                && channel.subscriberCount == 1
        }
        XCTAssertTrue(retrySubscribed)
        XCTAssertEqual(loadAttempts, 2)

        runtime = nil
        let cancelled = await waitUntilMainActor {
            !coordinator.stateUpdateConsumerIsRunning
                && channel.subscriberCount == 0
        }
        XCTAssertTrue(cancelled)
    }

    @MainActor
    func testVerifiedRunAndReplayEmitOnlyCoarseTelemetryWithOneCorrelation() async throws {
        let recorder = RuntimeTelemetryCapture()
        let diagnostics = makeDiagnostics(
            recorder: recorder,
            reporter: RuntimeDiagnosticsCapture()
        )
        let diagnosticsTask = Task { await diagnostics.run() }
        let correlationID = ReplayCorrelationID()
        var nowValue: TimeInterval = 20_000
        var runSequence = 0
        var initialState = AppCoordinatorState.launchDefault()
        initialState.settings.tutorialCompleted = true
        let initialSnapshot = runtimeSnapshot(state: initialState, identity: 20)
        let coordinator = AppCoordinator(
            environment: AppCoordinatorEnvironment(
                loadInitialState: { .loaded(initialSnapshot) },
                diagnosticsSink: diagnostics.sink,
                makeReplayCorrelationID: { correlationID },
                makeRunID: {
                    runSequence += 1
                    return RunID(self.fixedUUID(900 + runSequence))
                },
                makeSeed: { UInt32(runSequence) },
                now: {
                    defer { nowValue += 1 }
                    return Date(timeIntervalSince1970: nowValue)
                },
                performExternalRequest: nil,
                observeLifecycleEvent: nil,
                settleCompletedRun: { run in
                    var settledState = initialState
                    settledState.personalBest = run.score
                    settledState.pendingCoins = 28
                    return .settled(
                        authoritativeSnapshot: self.runtimeSnapshot(
                            state: settledState,
                            identity: 20,
                            playerRevision: 1,
                            economyRevision: 1
                        ),
                        results: self.runtimeResults(for: run)
                    )
                }
            )
        )

        await coordinator.bootstrap()
        coordinator.showCoinStore()
        coordinator.returnToMainMenu()
        XCTAssertTrue(coordinator.startRun())
        guard case let .gameplay(configuration) = coordinator.currentDestination else {
            return XCTFail("Expected the verified telemetry run to launch")
        }
        let completedRun = runtimeCompletedRun(
            configuration: configuration,
            reason: .timerExpired
        )

        await coordinator.handleCompletedRun(completedRun)
        guard case .runResults = coordinator.currentDestination else {
            return XCTFail("Expected verified results")
        }
        coordinator.replayAfterResults()
        guard case .gameplay = coordinator.currentDestination else {
            return XCTFail("Expected a successful replay transition")
        }

        let telemetryArrived = await eventually {
            await recorder.payloads().count == 5
        }
        let payloads = await recorder.payloads()
        XCTAssertTrue(telemetryArrived)
        XCTAssertEqual(
            payloads,
            [
                .storeOpened,
                .runStarted,
                .runResultsShown(
                    correlationID: correlationID,
                    scoreBand: .from15KTo24999,
                    accuracyBand: .from70To79,
                    attemptBand: .from10To19
                ),
                .runStarted,
                .replayStarted(correlationID: correlationID),
            ]
        )

        diagnosticsTask.cancel()
        await diagnosticsTask.value
    }

    @MainActor
    func testDebugAbandonedAndFailedRunsNeverEmitResultsOrReplaySuccess() async throws {
        let recorder = RuntimeTelemetryCapture()
        let diagnostics = makeDiagnostics(
            recorder: recorder,
            reporter: RuntimeDiagnosticsCapture()
        )
        let diagnosticsTask = Task { await diagnostics.run() }

        let debugCoordinator = makeRunTelemetryCoordinator(
            identity: 31,
            sink: diagnostics.sink,
            settlement: { _ in .failed(message: "Must not be called") }
        )
        await debugCoordinator.bootstrap()
        let debugConfiguration = try launchConfiguration(from: debugCoordinator)
        await debugCoordinator.handleCompletedRun(
            runtimeCompletedRun(
                configuration: debugConfiguration,
                reason: .debugPreview
            )
        )

        let abandonedState = playableRuntimeState()
        let abandonedCoordinator = makeRunTelemetryCoordinator(
            identity: 32,
            sink: diagnostics.sink,
            settlement: { _ in
                .settled(
                    authoritativeSnapshot: self.runtimeSnapshot(
                        state: abandonedState,
                        identity: 32,
                        playerRevision: 1,
                        economyRevision: 1
                    ),
                    results: nil
                )
            }
        )
        await abandonedCoordinator.bootstrap()
        let abandonedConfiguration = try launchConfiguration(from: abandonedCoordinator)
        await abandonedCoordinator.handleCompletedRun(
            runtimeCompletedRun(
                configuration: abandonedConfiguration,
                reason: .abandoned
            )
        )

        let failedCoordinator = makeRunTelemetryCoordinator(
            identity: 33,
            sink: diagnostics.sink,
            settlement: { _ in .failed(message: "Expected failure") }
        )
        await failedCoordinator.bootstrap()
        let failedConfiguration = try launchConfiguration(from: failedCoordinator)
        await failedCoordinator.handleCompletedRun(
            runtimeCompletedRun(
                configuration: failedConfiguration,
                reason: .timerExpired
            )
        )

        let telemetryArrived = await eventually {
            await recorder.payloads().count == 3
        }
        let payloads = await recorder.payloads()
        XCTAssertTrue(telemetryArrived)
        XCTAssertEqual(payloads, [.runStarted, .runStarted, .runStarted])

        diagnosticsTask.cancel()
        await diagnosticsTask.value
    }

    @MainActor
    func testProfileRecoveryEmitsOnlyClosedPersistenceReasonsWithoutPaths() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let recorder = RuntimeTelemetryCapture()
        let reporter = RuntimeDiagnosticsCapture()
        let diagnostics = makeDiagnostics(recorder: recorder, reporter: reporter)
        let diagnosticsTask = Task { await diagnostics.run() }

        let firstChannel = ProductionAuthoritativeStateChannel()
        let firstComposition = ProductionAppComposition(
            dependencies: ProductionAppDependencies(
                applicationSupportDirectoryURL: root,
                accountIdentity: .local,
                deviceID: "recovery-test-device",
                sessionNonce: fixedUUID(41),
                newProfileID: fixedUUID(42),
                now: { Date(timeIntervalSince1970: 40_000) },
                makeRunID: { RunID(self.fixedUUID(43)) },
                makeSeed: { 43 }
            ),
            authoritativeStateChannel: firstChannel,
            diagnosticsSink: diagnostics.sink
        )
        let firstCoordinator = AppCoordinator(environment: firstComposition.environment)
        await firstCoordinator.bootstrap()
        await firstCoordinator.setMuted(true)

        let profileDirectory = ProductionAppComposition.profileDirectoryURL(
            applicationSupportDirectoryURL: root,
            accountIdentity: .local
        )
        let locations = ProfileStorageLocations(directoryURL: profileDirectory)
        try Data([0x00, 0x01, 0x02]).write(
            to: locations.primaryURL,
            options: .atomic
        )

        let secondChannel = ProductionAuthoritativeStateChannel()
        let secondComposition = ProductionAppComposition(
            dependencies: ProductionAppDependencies(
                applicationSupportDirectoryURL: root,
                accountIdentity: .local,
                deviceID: "recovery-test-device",
                sessionNonce: fixedUUID(44),
                newProfileID: fixedUUID(45),
                now: { Date(timeIntervalSince1970: 40_100) },
                makeRunID: { RunID(self.fixedUUID(46)) },
                makeSeed: { 46 }
            ),
            authoritativeStateChannel: secondChannel,
            diagnosticsSink: diagnostics.sink
        )
        let recoveredCoordinator = AppCoordinator(
            environment: secondComposition.environment
        )
        await recoveredCoordinator.bootstrap()

        let diagnosticsArrived = await eventually {
            await reporter.entries().count == 3
        }
        let entries = await reporter.entries()
        XCTAssertTrue(diagnosticsArrived)
        XCTAssertEqual(
            entries,
            [
                .init(
                    payload: .persistence(.createdFreshProfile),
                    severity: .info
                ),
                .init(
                    payload: .persistence(.quarantinedCorruptFile),
                    severity: .warning
                ),
                .init(
                    payload: .persistence(.restoredBackup),
                    severity: .warning
                ),
            ]
        )

        diagnosticsTask.cancel()
        await diagnosticsTask.value
    }

    @MainActor
    private func makeRuntime(
        root: URL,
        serviceConfiguration: ProductionServiceConfiguration = .parse(
            infoDictionary: [:]
        ),
        diagnostics: AppleDiagnosticsRuntime? = nil
    ) -> RuntimeHarness {
        let resolvedDiagnostics = diagnostics ?? makeDiagnostics(
            recorder: RuntimeTelemetryCapture(),
            reporter: RuntimeDiagnosticsCapture()
        )
        let channel = ProductionAuthoritativeStateChannel()
        let composition = makeComposition(
            root: root,
            channel: channel,
            sink: resolvedDiagnostics.sink
        )
        let runtime = ProductionAppRuntime(
            coordinator: AppCoordinator(environment: composition.environment),
            presentationHandoff: UIKitGameKitPresentationHandoff(),
            serviceConfiguration: serviceConfiguration,
            runtimeCapabilities: .appleDiagnosticsOnly,
            composition: composition,
            authoritativeStateChannel: channel,
            diagnostics: resolvedDiagnostics
        )
        return RuntimeHarness(
            runtime: runtime,
            serviceConfiguration: serviceConfiguration
        )
    }

    @MainActor
    private func makeRunTelemetryCoordinator(
        identity: Int,
        sink: AppleDiagnosticsSink,
        settlement: @escaping @MainActor (CompletedRun) async -> CompletedRunSettlementResult
    ) -> AppCoordinator {
        let state = playableRuntimeState()
        return AppCoordinator(
            environment: AppCoordinatorEnvironment(
                loadInitialState: {
                    .loaded(
                        self.runtimeSnapshot(state: state, identity: identity)
                    )
                },
                diagnosticsSink: sink,
                makeRunID: { RunID(self.fixedUUID(700 + identity)) },
                makeSeed: { UInt32(identity) },
                now: { Date(timeIntervalSince1970: TimeInterval(30_000 + identity)) },
                performExternalRequest: nil,
                observeLifecycleEvent: nil,
                settleCompletedRun: settlement
            )
        )
    }

    @MainActor
    private func launchConfiguration(
        from coordinator: AppCoordinator
    ) throws -> RunConfiguration {
        XCTAssertTrue(coordinator.startRun())
        guard case let .gameplay(configuration) = coordinator.currentDestination else {
            throw RuntimeTestFailure.expectedGameplay
        }
        return configuration
    }

    @MainActor
    private func playableRuntimeState() -> AppCoordinatorState {
        var state = AppCoordinatorState.launchDefault()
        state.settings.tutorialCompleted = true
        return state
    }

    @MainActor
    private func runtimeSnapshot(
        state: AppCoordinatorState,
        identity: Int,
        playerRevision: UInt64 = 0,
        economyRevision: UInt64 = 0
    ) -> AuthoritativeAppStateSnapshot {
        AuthoritativeAppStateSnapshot(
            session: ProfileSessionToken(
                accountIdentity: .local,
                nonce: fixedUUID(identity * 10 + 1),
                profileID: fixedUUID(identity * 10 + 2)
            ),
            playerRevision: playerRevision,
            economyRevision: economyRevision,
            state: state
        )
    }

    private func runtimeCompletedRun(
        configuration: RunConfiguration,
        reason: RunFinishReason
    ) -> CompletedRun {
        CompletedRun(
            configuration: configuration,
            endedAt: configuration.startedAt.addingTimeInterval(60),
            elapsedGameplayMilliseconds: reason == .timerExpired ? 60_000 : 12_000,
            finishReason: reason,
            score: 18_750,
            statistics: RunStatisticsSnapshot(
                attempts: 12,
                completions: 7,
                touchdowns: 2,
                incompletions: 2,
                interceptions: 1,
                longestTouchdownStreak: 2
            ),
            completedLaneIDs: [.short, .touchdown],
            bonusTouchdownCount: 0
        )
    }

    private func runtimeResults(for run: CompletedRun) -> RunResultsPresentation {
        RunResultsPresentation(
            completedRun: run,
            earnedCoins: 28,
            pendingCoins: 28,
            personalBest: run.score,
            isNewPersonalBest: true,
            rewardedAdOffer: .progress(validRuns: 1, requiredRuns: 5)
        )
    }

    @MainActor
    private func makeComposition(
        root: URL,
        channel: ProductionAuthoritativeStateChannel,
        sink: AppleDiagnosticsSink?
    ) -> ProductionAppComposition {
        ProductionAppComposition(
            dependencies: ProductionAppDependencies(
                applicationSupportDirectoryURL: root,
                accountIdentity: .local,
                deviceID: "runtime-test-device",
                sessionNonce: fixedUUID(1),
                newProfileID: fixedUUID(2),
                now: { Date(timeIntervalSince1970: 10_000) },
                makeRunID: { RunID(self.fixedUUID(3)) },
                makeSeed: { 3 }
            ),
            authoritativeStateChannel: channel,
            diagnosticsSink: sink
        )
    }

    private func makeDiagnostics(
        recorder: RuntimeTelemetryCapture,
        reporter: RuntimeDiagnosticsCapture,
        registration: any AppleMetricKitRegistering = NoOpAppleMetricKitRegistration()
    ) -> AppleDiagnosticsRuntime {
        AppleDiagnosticsRuntime(
            telemetryRecorder: recorder,
            diagnosticsReporter: reporter,
            metricKitSubscription: AppleMetricKitSubscriptionService(
                registration: registration
            )
        )
    }

    @MainActor
    private func validStoreKitConfiguration() -> ProductionServiceConfiguration {
        let productIdentifiers = Dictionary(
            uniqueKeysWithValues: EconomyConfiguration.coinPacks.map {
                ($0.id.rawValue, "test.coin.\($0.id.rawValue)")
            }
        )
        return .parse(
            infoDictionary: [
                "PocketVectorServices": [
                    "StoreKit": [
                        "ProductIdentifiers": productIdentifiers,
                    ] as [String: Any],
                ] as [String: Any],
            ]
        )
    }

    private func eventually(
        iterations: Int = 2_000,
        condition: @escaping @Sendable () async -> Bool
    ) async -> Bool {
        for _ in 0 ..< iterations {
            if await condition() { return true }
            await Task.yield()
        }
        return false
    }

    @MainActor
    private func waitUntilMainActor(
        iterations: Int = 2_000,
        condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        for _ in 0 ..< iterations {
            if condition() { return true }
            await Task.yield()
        }
        return false
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "PocketVector-Runtime-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        return url
    }

    private func removeTemporaryDirectory(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func fixedUUID(_ value: Int) -> UUID {
        UUID(
            uuidString: String(
                format: "00000000-0000-0000-0000-%012d",
                value
            )
        )!
    }

    private enum RuntimeTestFailure: Error {
        case expectedGameplay
    }
}

@MainActor
private struct RuntimeHarness {
    let runtime: ProductionAppRuntime
    let serviceConfiguration: ProductionServiceConfiguration
}

private final class WeakRuntimeBox<Value: AnyObject> {
    weak var value: Value?

    init(_ value: Value?) {
        self.value = value
    }
}

private actor RuntimeTelemetryCapture: TelemetryRecording {
    private var storedPayloads: [TelemetryPayload] = []

    func record(
        _ event: TelemetryEvent,
        at date: Date
    ) -> TelemetryEnqueueResult {
        storedPayloads.append(event.payload)
        return .enqueued
    }

    func payloads() -> [TelemetryPayload] {
        storedPayloads
    }
}

private actor RuntimeDiagnosticsCapture: DiagnosticsReporting {
    struct Entry: Equatable, Sendable {
        let payload: DiagnosticPayload
        let severity: DiagnosticSeverity
    }

    private var storedEntries: [Entry] = []

    func report(_ report: DiagnosticReport) {
        storedEntries.append(
            Entry(payload: report.payload, severity: report.severity)
        )
    }

    func entries() -> [Entry] {
        storedEntries
    }
}

private struct FailingRuntimeMetricKitRegistration: AppleMetricKitRegistering {
    func register() throws {
        throw Failure.expected
    }

    func unregister() throws {}

    private enum Failure: Error {
        case expected
    }
}

private final class CountingRuntimeMetricKitRegistration: AppleMetricKitRegistering,
    @unchecked Sendable
{
    struct Snapshot: Equatable {
        let registerCalls: Int
        let unregisterCalls: Int
    }

    private let lock = NSLock()
    private var registerCalls = 0
    private var unregisterCalls = 0

    func register() {
        lock.withLock { registerCalls += 1 }
    }

    func unregister() {
        lock.withLock { unregisterCalls += 1 }
    }

    func snapshot() -> Snapshot {
        lock.withLock {
            Snapshot(
                registerCalls: registerCalls,
                unregisterCalls: unregisterCalls
            )
        }
    }
}

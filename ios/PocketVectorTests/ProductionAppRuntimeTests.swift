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
    func testStartCoordinatorBootsLocallyThenRefreshesAccountGraphWithoutCommerce()
        async throws
    {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let events = AccountRuntimeEventRecorder()
        let discovery = AccountRuntimeDiscovery(
            states: [.signedOut],
            events: events
        )
        let router = ProductionAccountRuntimeRouter(
            accountDiscovery: discovery,
            accountClaimer: AccountRuntimeClaimer(
                claims: [:],
                events: events
            ),
            runtimeBuilder: AccountRuntimeBuilder(events: events)
        )
        let diagnostics = makeDiagnostics(
            recorder: RuntimeTelemetryCapture(),
            reporter: RuntimeDiagnosticsCapture()
        )
        let channel = ProductionAuthoritativeStateChannel()
        let composition = makeComposition(
            root: root,
            channel: channel,
            sink: diagnostics.sink
        )
        let runtime = ProductionAppRuntime(
            coordinator: AppCoordinator(environment: composition.environment),
            presentationHandoff: UIKitGameKitPresentationHandoff(),
            serviceConfiguration: .parse(infoDictionary: [:]),
            runtimeCapabilities: .appleDiagnosticsOnly,
            composition: composition,
            authoritativeStateChannel: channel,
            diagnostics: diagnostics,
            accountRuntimeRouter: router
        )

        runtime.startCoordinator()
        runtime.applicationDidBecomeActive()
        var refreshed = false
        for _ in 0 ..< 200 {
            if await events.snapshot().contains("discover:signedOut") {
                refreshed = true
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(runtime.coordinator.bootstrapState, .ready)
        XCTAssertTrue(refreshed)
        await runtime.shutdownAccountRuntime()
    }

    @MainActor
    func testBackgroundedAccountRefreshCannotStartGameCenterAndNextActivationRetries()
        async throws
    {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let accountID = CloudAccountID("account-v1-background-lifecycle")
        let claim = try await makeVerifiedAccountClaim(
            root: root,
            accountID: accountID,
            nonce: fixedUUID(581)
        )
        let gate = AccountRuntimeTestGate()
        let events = AccountRuntimeEventRecorder()
        let discovery = AccountRuntimeDiscovery(
            states: Array(repeating: .available(accountID), count: 8),
            events: events
        )
        let router = ProductionAccountRuntimeRouter(
            accountDiscovery: discovery,
            accountClaimer: AccountRuntimeClaimer(
                claims: [accountID: claim],
                events: events,
                gate: gate
            ),
            runtimeBuilder: AccountRuntimeBuilder(events: events)
        )
        let diagnostics = makeDiagnostics(
            recorder: RuntimeTelemetryCapture(),
            reporter: RuntimeDiagnosticsCapture()
        )
        let channel = ProductionAuthoritativeStateChannel()
        let composition = makeComposition(
            root: root,
            channel: channel,
            sink: diagnostics.sink
        )
        let gameCenterService = LifecycleGameCenterServiceDouble()
        let gameCenterCoordinator = GameCenterDeliveryCoordinator.makeForProduction(
            submissionChannel: LifecycleGameCenterSubmissionChannelDouble(),
            service: gameCenterService
        )
        let gameCenterConfiguration = try GameKitGameCenterConfiguration(
            leaderboardIdentifier:
                "com.pocketvector.game.leaderboard.highscore.v1",
            achievementIdentifiers: Dictionary(
                uniqueKeysWithValues: AchievementCatalog.launch.map {
                    ($0.id, $0.id.rawValue)
                }
            )
        )
        let gameCenterRuntime = ProductionGameCenterRuntime(
            configuration: gameCenterConfiguration,
            coordinator: gameCenterCoordinator
        )
        let runtime = ProductionAppRuntime(
            coordinator: AppCoordinator(environment: composition.environment),
            presentationHandoff: UIKitGameKitPresentationHandoff(),
            serviceConfiguration: .parse(infoDictionary: [:]),
            runtimeCapabilities: .appleDiagnosticsOnly,
            composition: composition,
            authoritativeStateChannel: channel,
            diagnostics: diagnostics,
            accountRuntimeRouter: router,
            gameCenterRuntime: gameCenterRuntime
        )

        await runtime.coordinator.bootstrap()
        runtime.applicationDidBecomeActive()
        let refreshReachedGate = await eventually {
            await events.snapshot().contains(
                "claim:\(accountID.rawValue)"
            )
        }
        XCTAssertTrue(refreshReachedGate)

        runtime.applicationDidEnterBackground()
        await gate.open()
        try await Task.sleep(for: .milliseconds(100))
        let backgroundAuthenticationCount = await gameCenterService
            .authenticationCount()
        let backgroundPresentationCount = await gameCenterService
            .presentationCount()
        XCTAssertEqual(backgroundAuthenticationCount, 0)
        XCTAssertEqual(backgroundPresentationCount, 0)

        runtime.applicationDidBecomeActive()
        let retriedInForeground = await eventually {
            await gameCenterService.authenticationCount() == 1
        }
        let foregroundPresentationCount = await gameCenterService
            .presentationCount()
        XCTAssertTrue(retriedInForeground)
        XCTAssertEqual(foregroundPresentationCount, 0)
        await runtime.shutdownAccountRuntime()
    }

    @MainActor
    func testRapidReactivationDrainsProjectionBeforeStartingNewestForegroundWork()
        async throws
    {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let events = AccountRuntimeEventRecorder()
        let router = ProductionAccountRuntimeRouter(
            accountDiscovery: AccountRuntimeDiscovery(
                states: [.signedOut],
                events: events
            ),
            accountClaimer: AccountRuntimeClaimer(
                claims: [:],
                events: events
            ),
            runtimeBuilder: AccountRuntimeBuilder(events: events)
        )
        let diagnostics = makeDiagnostics(
            recorder: RuntimeTelemetryCapture(),
            reporter: RuntimeDiagnosticsCapture()
        )
        let channel = ProductionAuthoritativeStateChannel()
        let composition = makeComposition(
            root: root,
            channel: channel,
            sink: diagnostics.sink
        )
        let gameCenterService = LifecycleGameCenterServiceDouble()
        let gameCenterRuntime = ProductionGameCenterRuntime(
            configuration: try GameKitGameCenterConfiguration(
                leaderboardIdentifier:
                    "com.pocketvector.game.leaderboard.highscore.v1",
                achievementIdentifiers: Dictionary(
                    uniqueKeysWithValues: AchievementCatalog.launch.map {
                        ($0.id, $0.id.rawValue)
                    }
                )
            ),
            coordinator: GameCenterDeliveryCoordinator.makeForProduction(
                submissionChannel:
                    LifecycleGameCenterSubmissionChannelDouble(),
                service: gameCenterService
            )
        )
        let projectionGate = AccountRuntimeTestGate()
        let runtime = ProductionAppRuntime(
            coordinator: AppCoordinator(environment: composition.environment),
            presentationHandoff: UIKitGameKitPresentationHandoff(),
            serviceConfiguration: .parse(infoDictionary: [:]),
            runtimeCapabilities: .appleDiagnosticsOnly,
            composition: composition,
            authoritativeStateChannel: channel,
            diagnostics: diagnostics,
            accountRuntimeRouter: router,
            gameCenterRuntime: gameCenterRuntime,
            beforeApplyingForegroundAccountProjection: {
                await projectionGate.wait()
            }
        )

        await runtime.coordinator.bootstrap()
        runtime.applicationDidBecomeActive()
        let projectionSuspended = await eventually {
            await projectionGate.waiterCount() == 1
        }
        XCTAssertTrue(projectionSuspended)

        runtime.applicationDidEnterBackground()
        runtime.applicationDidBecomeActive()
        let authenticationBeforeDrain = await gameCenterService
            .authenticationCount()
        XCTAssertEqual(authenticationBeforeDrain, 0)

        await projectionGate.open()
        let newestForegroundDelivered = await eventually {
            await gameCenterService.authenticationCount() == 1
        }
        XCTAssertTrue(newestForegroundDelivered)
        let finalAuthenticationCount = await gameCenterService
            .authenticationCount()
        XCTAssertEqual(finalAuthenticationCount, 1)
        await runtime.shutdownAccountRuntime()
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

    func testAccountRuntimeWithoutCompleteConfigurationFailsClosed() async {
        let router = ProductionAccountRuntimeRouter(
            accountDiscovery: nil,
            accountClaimer: nil,
            runtimeBuilder: nil
        )

        let refresh = await router.refresh()
        let purchase = await router.perform(
            .coinPack(EconomyConfiguration.coinPacks[0].id)
        )
        let context = await router.currentContext()

        XCTAssertEqual(refresh, .unavailable(.configurationUnavailable))
        XCTAssertEqual(purchase, .onlineRequired)
        XCTAssertNil(context)
    }

    func testRuntimeAssemblerRejectsIncompleteConfigurationWithoutCallingFactory() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let source = try await makeLocalRepository(
            root: root,
            nonce: fixedUUID(580)
        )
        let repositoryRouter = ProductionProfileRepositoryRouter(
            route: ProductionProfileRepositoryRoute(
                repository: source,
                authority: .local(
                    accountIdentity: .local,
                    sessionNonce: fixedUUID(580)
                )
            )
        )
        let factory = AccountRuntimeGraphFactory(
            graph: nil
        )

        let assembly = ProductionAccountRuntimeAssembler.assemble(
            serviceConfiguration: .parse(infoDictionary: [:]),
            input: ProductionAccountRuntimeAssemblyInput(
                sourceRepository: source,
                repositoryRouter: repositoryRouter,
                applicationSupportDirectoryURL: root,
                deviceID: "runtime-assembly-device",
                sessionNonce: fixedUUID(580),
                catalog: .approved
            ),
            graphBuilder: factory
        )

        XCTAssertFalse(assembly.graphIsComplete)
        XCTAssertEqual(factory.callCount, 0)
        let purchaseResult = await assembly.router.perform(
            .coinPack(EconomyConfiguration.coinPacks[0].id)
        )
        XCTAssertEqual(purchaseResult, .onlineRequired)
    }

    func testRuntimeAssemblerAcceptsCompleteGraphAndPreservesSourceIdentity() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let nonce = fixedUUID(581)
        let source = try await makeLocalRepository(root: root, nonce: nonce)
        let repositoryRouter = ProductionProfileRepositoryRouter(
            route: ProductionProfileRepositoryRoute(
                repository: source,
                authority: .local(
                    accountIdentity: .local,
                    sessionNonce: nonce
                )
            )
        )
        let accountID = CloudAccountID("runtime-assembly-account")
        let claim = try await makeVerifiedAccountClaim(
            root: root,
            accountID: accountID,
            nonce: fixedUUID(582)
        )
        let events = AccountRuntimeEventRecorder()
        let graph = ProductionConfiguredAccountRuntimeGraph(
            accountDiscovery: AccountRuntimeDiscovery(
                states: Array(repeating: .available(accountID), count: 3),
                events: events
            ),
            accountClaimer: AccountRuntimeClaimer(
                claims: [accountID: claim],
                events: events
            ),
            runtimeBuilder: AccountRuntimeBuilder(events: events)
        )
        let factory = AccountRuntimeGraphFactory(graph: graph)

        let assembly = ProductionAccountRuntimeAssembler.assemble(
            serviceConfiguration: validCommerceConfiguration(),
            input: ProductionAccountRuntimeAssemblyInput(
                sourceRepository: source,
                repositoryRouter: repositoryRouter,
                applicationSupportDirectoryURL: root,
                deviceID: "runtime-assembly-device",
                sessionNonce: nonce,
                catalog: .approved
            ),
            graphBuilder: factory
        )
        let result = await assembly.router.refresh()

        XCTAssertTrue(assembly.graphIsComplete)
        XCTAssertEqual(factory.callCount, 1)
        XCTAssertTrue(factory.sourceRepository === source)
        guard case let .current(context) = result else {
            return XCTFail("A complete configured graph must activate")
        }
        XCTAssertEqual(context.cloudAccountID, accountID)
    }

    func testLaunchRepositoryResolutionIsSingleFlightAndReturnsOneExactInstance() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let sourceNonce = fixedUUID(583)
        let targetNonce = fixedUUID(584)
        let source = try await makeLocalRepository(
            root: root,
            nonce: sourceNonce
        )
        let target = try await makeLocalRepository(
            root: root.appendingPathComponent("target", isDirectory: true),
            nonce: targetNonce
        )
        let targetSnapshot = try await target.snapshot()
        let targetRoute = ProductionProfileRepositoryRoute(
            repository: target,
            authority: .local(
                accountIdentity: .local,
                sessionNonce: targetSnapshot.session.nonce
            )
        )
        let gate = AccountRuntimeTestGate()
        let resolver = AccountRuntimeLaunchResolver(
            route: targetRoute,
            gate: gate
        )
        let router = ProductionProfileRepositoryRouter(
            route: ProductionProfileRepositoryRoute(
                repository: source,
                authority: .local(
                    accountIdentity: .local,
                    sessionNonce: sourceNonce
                )
            ),
            launchResolver: resolver
        )

        let first = Task { try await router.currentRoute() }
        let second = Task { try await router.currentRoute() }
        let oneResolutionStarted = await eventually {
            await resolver.callCount() == 1
        }
        XCTAssertTrue(oneResolutionStarted)
        await gate.open()
        let firstRoute = try await first.value
        let secondRoute = try await second.value

        let resolutionCalls = await resolver.callCount()
        XCTAssertEqual(resolutionCalls, 1)
        XCTAssertTrue(firstRoute.repository === target)
        XCTAssertTrue(secondRoute.repository === target)
        XCTAssertTrue(firstRoute.repository === secondRoute.repository)
    }

    func testCommittedAssociationProviderAdmissionAllowsSameAndOfflineButRejectsDifferent() {
        let committed = CloudAccountID("marker-bound-account")
        XCTAssertNoThrow(
            try ProductionCommittedAssociationRouteResolver
                .validateProviderAccount(
                    .available(committed),
                    committedAccountID: committed
                )
        )
        for offlineState in [
            CloudAccountState.unknown,
            .signedOut,
            .restricted,
        ] {
            XCTAssertNoThrow(
                try ProductionCommittedAssociationRouteResolver
                    .validateProviderAccount(
                        offlineState,
                        committedAccountID: committed
                    )
            )
        }
        XCTAssertThrowsError(
            try ProductionCommittedAssociationRouteResolver
                .validateProviderAccount(
                    .available(CloudAccountID("different-account")),
                    committedAccountID: committed
                )
        )
    }

    func testAccountRuntimePublishesOnlyDurablyClaimedCloudDerivedSessions() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let accountID = CloudAccountID("account-runtime-a")
        let claim = try await makeVerifiedAccountClaim(
            root: root,
            accountID: accountID,
            nonce: fixedUUID(601)
        )
        let events = AccountRuntimeEventRecorder()
        let discovery = AccountRuntimeDiscovery(
            states: Array(repeating: .available(accountID), count: 3),
            events: events
        )
        let claimer = AccountRuntimeClaimer(
            claims: [accountID: claim],
            events: events
        )
        let builder = AccountRuntimeBuilder(events: events)
        let router = ProductionAccountRuntimeRouter(
            accountDiscovery: discovery,
            accountClaimer: claimer,
            runtimeBuilder: builder
        )

        let result = await router.refresh()
        let currentContext = await router.currentContext()
        let context = try XCTUnwrap(currentContext)

        XCTAssertEqual(result, .current(context))
        XCTAssertEqual(context.cloudAccountID, accountID)
        XCTAssertEqual(
            context.profileSnapshot.session.accountIdentity,
            CloudAccountDerivedBindings.derive(from: accountID).playerAccountIdentity
        )
        XCTAssertEqual(
            context.durableEconomyContext.storeSession.nonce,
            context.profileSnapshot.session.nonce
        )
        let recorded = await events.snapshot()
        XCTAssertEqual(
            recorded,
            [
                "discover:account-runtime-a",
                "claim:account-runtime-a",
                "discover:account-runtime-a",
                "build:account-runtime-a",
                "activate:cloud:account-runtime-a",
                "activate:economy:account-runtime-a",
                "activate:storeKit:account-runtime-a",
                "discover:account-runtime-a",
            ]
        )
    }

    func testSameContextWithDifferentInstalledRepositoryRetiresAndRebuilds() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let accountID = CloudAccountID("account-runtime-repository-replacement")
        let nonce = fixedUUID(605)
        let firstClaim = try await makeVerifiedAccountClaim(
            root: root,
            accountID: accountID,
            nonce: nonce
        )
        let secondClaim = try await makeVerifiedAccountClaim(
            root: root,
            accountID: accountID,
            nonce: nonce
        )
        XCTAssertFalse(
            firstClaim.installedRepository === secondClaim.installedRepository
        )
        XCTAssertEqual(firstClaim.snapshot, secondClaim.snapshot)
        let events = AccountRuntimeEventRecorder()
        let router = ProductionAccountRuntimeRouter(
            accountDiscovery: AccountRuntimeDiscovery(
                states: Array(repeating: .available(accountID), count: 6),
                events: events
            ),
            accountClaimer: AccountRuntimeClaimSequence(
                claims: [firstClaim, secondClaim],
                events: events
            ),
            runtimeBuilder: AccountRuntimeBuilder(events: events)
        )

        _ = await router.refresh()
        _ = await router.refresh()
        let recorded = await events.snapshot()

        XCTAssertEqual(recorded.filter { $0.hasPrefix("build:") }.count, 2)
        XCTAssertEqual(
            recorded.filter { $0.hasPrefix("shutdown:storeKit:") }.count,
            1
        )
    }

    func testAccountSwitchAwaitsReverseShutdownBeforeClaimingSuccessor() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let firstID = CloudAccountID("account-runtime-first")
        let secondID = CloudAccountID("account-runtime-second")
        let firstClaim = try await makeVerifiedAccountClaim(
            root: root,
            accountID: firstID,
            nonce: fixedUUID(611)
        )
        let secondClaim = try await makeVerifiedAccountClaim(
            root: root,
            accountID: secondID,
            nonce: fixedUUID(612)
        )
        let events = AccountRuntimeEventRecorder()
        let discovery = AccountRuntimeDiscovery(
            states: [
                .available(firstID), .available(firstID), .available(firstID),
                .available(secondID), .available(secondID), .available(secondID),
            ],
            events: events
        )
        let router = ProductionAccountRuntimeRouter(
            accountDiscovery: discovery,
            accountClaimer: AccountRuntimeClaimer(
                claims: [firstID: firstClaim, secondID: secondClaim],
                events: events
            ),
            runtimeBuilder: AccountRuntimeBuilder(events: events)
        )

        _ = await router.refresh()
        let switched = await router.refresh()
        let currentContext = await router.currentContext()
        let context = try XCTUnwrap(currentContext)
        let recorded = await events.snapshot()

        XCTAssertEqual(switched, .current(context))
        XCTAssertEqual(context.cloudAccountID, secondID)
        let storeShutdown = try XCTUnwrap(
            recorded.firstIndex(of: "shutdown:storeKit:account-runtime-first")
        )
        let economyShutdown = try XCTUnwrap(
            recorded.firstIndex(of: "shutdown:economy:account-runtime-first")
        )
        let cloudShutdown = try XCTUnwrap(
            recorded.firstIndex(of: "shutdown:cloud:account-runtime-first")
        )
        let successorClaim = try XCTUnwrap(
            recorded.firstIndex(of: "claim:account-runtime-second")
        )
        XCTAssertLessThan(storeShutdown, economyShutdown)
        XCTAssertLessThan(economyShutdown, cloudShutdown)
        XCTAssertLessThan(cloudShutdown, successorClaim)
    }

    func testAccountChangeDuringClaimNeverBuildsOrPublishesRuntime() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let accountID = CloudAccountID("account-runtime-loss")
        let claim = try await makeVerifiedAccountClaim(
            root: root,
            accountID: accountID,
            nonce: fixedUUID(621)
        )
        let events = AccountRuntimeEventRecorder()
        let router = ProductionAccountRuntimeRouter(
            accountDiscovery: AccountRuntimeDiscovery(
                states: [.available(accountID), .unknown],
                events: events
            ),
            accountClaimer: AccountRuntimeClaimer(
                claims: [accountID: claim],
                events: events
            ),
            runtimeBuilder: AccountRuntimeBuilder(events: events)
        )

        let result = await router.refresh()
        let context = await router.currentContext()
        let recorded = await events.snapshot()

        XCTAssertEqual(result, .unavailable(.accountChangedDuringActivation))
        XCTAssertNil(context)
        XCTAssertFalse(recorded.contains(where: { $0.hasPrefix("build:") }))
        XCTAssertFalse(recorded.contains(where: { $0.hasPrefix("activate:") }))
    }

    func testCommerceRequestRevalidatesAccountEveryTimeAndUsesActiveService() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let accountID = CloudAccountID("account-runtime-commerce")
        let claim = try await makeVerifiedAccountClaim(
            root: root,
            accountID: accountID,
            nonce: fixedUUID(631)
        )
        let events = AccountRuntimeEventRecorder()
        let discovery = AccountRuntimeDiscovery(
            states: Array(repeating: .available(accountID), count: 7),
            events: events
        )
        let router = ProductionAccountRuntimeRouter(
            accountDiscovery: discovery,
            accountClaimer: AccountRuntimeClaimer(
                claims: [accountID: claim],
                events: events
            ),
            runtimeBuilder: AccountRuntimeBuilder(events: events)
        )

        let first = await router.perform(
            .coinPack(EconomyConfiguration.coinPacks[0].id)
        )
        let second = await router.perform(
            .catalogUnlock(CatalogItemID("football-neon"))
        )
        let recorded = await events.snapshot()

        XCTAssertEqual(first, .succeeded)
        XCTAssertEqual(second, .succeeded)
        XCTAssertEqual(
            recorded.filter { $0.hasPrefix("claim:") }.count,
            2,
            "Every transaction boundary must request a new verified readback"
        )
        XCTAssertEqual(
            recorded.filter { $0.hasPrefix("commerce:") }.count,
            2
        )
        XCTAssertEqual(
            recorded.filter { $0.hasPrefix("build:") }.count,
            1,
            "The same exact session should retain its long-lived runtime"
        )
    }

    func testDuplicateCommerceRequestFailsFastWithoutSecondUnderlyingCall() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let accountID = CloudAccountID("account-runtime-single-flight")
        let claim = try await makeVerifiedAccountClaim(
            root: root,
            accountID: accountID,
            nonce: fixedUUID(641)
        )
        let events = AccountRuntimeEventRecorder()
        let commerceGate = AccountRuntimeTestGate()
        let router = ProductionAccountRuntimeRouter(
            accountDiscovery: AccountRuntimeDiscovery(
                states: Array(repeating: .available(accountID), count: 8),
                events: events
            ),
            accountClaimer: AccountRuntimeClaimer(
                claims: [accountID: claim],
                events: events
            ),
            runtimeBuilder: AccountRuntimeBuilder(
                events: events,
                commerceGate: commerceGate
            )
        )

        let firstTask = Task {
            await router.perform(
                .coinPack(EconomyConfiguration.coinPacks[0].id)
            )
        }
        let firstStarted = await eventually {
            await events.snapshot().contains(where: { $0.hasPrefix("commerce:") })
        }
        XCTAssertTrue(firstStarted)

        let duplicate = await router.perform(
            .coinPack(EconomyConfiguration.coinPacks[0].id)
        )
        let callsBeforeRelease = await events.snapshot().filter {
            $0.hasPrefix("commerce:")
        }.count

        XCTAssertEqual(duplicate, .silentlyCompleted)
        XCTAssertEqual(callsBeforeRelease, 1)

        await commerceGate.open()
        let firstResult = await firstTask.value
        XCTAssertEqual(firstResult, .succeeded)
        let finalCalls = await events.snapshot().filter {
            $0.hasPrefix("commerce:")
        }.count
        XCTAssertEqual(finalCalls, 1)
    }

    func testCancelledCommerceWaiterIsRemovedBeforeRefreshOrServiceCall() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let accountID = CloudAccountID("account-runtime-cancel")
        let claim = try await makeVerifiedAccountClaim(
            root: root,
            accountID: accountID,
            nonce: fixedUUID(651)
        )
        let events = AccountRuntimeEventRecorder()
        let claimGate = AccountRuntimeTestGate()
        let router = ProductionAccountRuntimeRouter(
            accountDiscovery: AccountRuntimeDiscovery(
                states: Array(repeating: .available(accountID), count: 10),
                events: events
            ),
            accountClaimer: AccountRuntimeClaimer(
                claims: [accountID: claim],
                events: events,
                gate: claimGate
            ),
            runtimeBuilder: AccountRuntimeBuilder(events: events)
        )

        let lifecycleTask = Task { await router.refresh() }
        let lifecycleBlocked = await eventually {
            await events.snapshot().contains("claim:account-runtime-cancel")
        }
        XCTAssertTrue(lifecycleBlocked)

        let cancelledTask = Task {
            await router.perform(
                .coinPack(EconomyConfiguration.coinPacks[0].id)
            )
        }
        await Task.yield()
        cancelledTask.cancel()
        await claimGate.open()
        _ = await lifecycleTask.value
        let cancelledResult = await cancelledTask.value

        XCTAssertEqual(cancelledResult, .onlineRequired)
        let callsAfterCancellation = await events.snapshot().filter {
            $0.hasPrefix("commerce:")
        }.count
        XCTAssertEqual(callsAfterCancellation, 0)

        let retry = await router.perform(
            .coinPack(EconomyConfiguration.coinPacks[0].id)
        )
        XCTAssertEqual(retry, .succeeded)
        let callsAfterRetry = await events.snapshot().filter {
            $0.hasPrefix("commerce:")
        }.count
        XCTAssertEqual(callsAfterRetry, 1)
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
                    settledState.pendingCoins = 33
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

    private func makeVerifiedAccountClaim(
        root: URL,
        accountID: CloudAccountID,
        nonce: UUID
    ) async throws -> ProductionVerifiedAccountClaim {
        let bindings = CloudAccountDerivedBindings.derive(from: accountID)
        let directory = ProductionAppComposition.profileDirectoryURL(
            applicationSupportDirectoryURL: root,
            accountIdentity: bindings.playerAccountIdentity
        )
        let repository = LocalPlayerProfileRepository(
            directoryURL: directory,
            deviceID: "account-runtime-test-device",
            accountIdentity: bindings.playerAccountIdentity,
            sessionNonce: nonce
        )
        _ = try await repository.load(
            at: Date(timeIntervalSince1970: 60_000),
            newProfileID: bindings.durableAccountBinding.profileID
        )
        return try await ProductionVerifiedAccountClaim(
            cloudAccountID: accountID,
            derivedBindings: bindings,
            installedRepository: repository
        )
    }

    private func makeLocalRepository(
        root: URL,
        nonce: UUID
    ) async throws -> LocalPlayerProfileRepository {
        let repository = LocalPlayerProfileRepository(
            directoryURL: root.appendingPathComponent(
                "local-\(nonce.uuidString)",
                isDirectory: true
            ),
            deviceID: "runtime-assembly-device",
            accountIdentity: .local,
            sessionNonce: nonce
        )
        _ = try await repository.load(
            at: Date(timeIntervalSince1970: 59_000),
            newProfileID: UUID()
        )
        return repository
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
            completionCoins: 10,
            performanceCoins: 18,
            accuracyCoins: 5,
            signingBonusCoins: 0,
            totalEarnedCoins: 33,
            pendingCoins: 33,
            gameplayRewardState: .pending,
            signingBonusState: nil,
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

    private func validCommerceConfiguration() -> ProductionServiceConfiguration {
        let productIdentifiers = Dictionary(
            uniqueKeysWithValues: EconomyConfiguration.coinPacks.map {
                ($0.id.rawValue, "test.coin.\($0.id.rawValue)")
            }
        )
        return .parse(
            infoDictionary: [
                "PocketVectorServices": [
                    "CloudKit": [
                        "ContainerIdentifier": "iCloud.test.pocket-vector",
                        "ZoneName": "PocketVectorPrivateZone",
                        "PayloadFieldName": "payload",
                        "OperationRecordType": "OperationMarker",
                        "AccountIdentifierNamespace": "account-v1",
                        "RecordNameNamespace": "record-v1",
                        "EconomyRecordID": "economy-head-v1",
                        "EconomyRecordType": "EconomyHead",
                        "EconomyPayloadFieldName": "economyPayload",
                        "ProfileRootRecordType": "ProfileRoot",
                        "ProfileSettingsRecordType": "ProfileSettings",
                        "ProfileSelectionRecordType": "ProfileSelection",
                        "ProfileRunRecordType": "ProfileRun",
                        "ProfilePayloadFieldName": "profilePayload",
                    ] as [String: Any],
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

private final class AccountRuntimeGraphFactory:
    ProductionConfiguredAccountRuntimeGraphBuilding,
    @unchecked Sendable
{
    private let lock = NSLock()
    private let graph: ProductionConfiguredAccountRuntimeGraph?
    private var storedCallCount = 0
    private var storedSourceRepository: LocalPlayerProfileRepository?

    init(graph: ProductionConfiguredAccountRuntimeGraph?) {
        self.graph = graph
    }

    var callCount: Int {
        lock.withLock { storedCallCount }
    }

    var sourceRepository: LocalPlayerProfileRepository? {
        lock.withLock { storedSourceRepository }
    }

    func makeConfiguredAccountRuntimeGraph(
        input: ProductionConfiguredAccountRuntimeGraphInput
    ) throws -> ProductionConfiguredAccountRuntimeGraph {
        lock.withLock {
            storedCallCount += 1
            storedSourceRepository = input.sourceRepository
        }
        guard let graph else {
            throw AccountRuntimeFixtureFailure.missingGraph
        }
        return graph
    }
}

private actor AccountRuntimeLaunchResolver:
    ProductionLaunchRepositoryRouteResolving
{
    private let route: ProductionProfileRepositoryRoute
    private let gate: AccountRuntimeTestGate
    private var storedCallCount = 0

    init(
        route: ProductionProfileRepositoryRoute,
        gate: AccountRuntimeTestGate
    ) {
        self.route = route
        self.gate = gate
    }

    func resolveLaunchRoute() async throws -> ProductionProfileRepositoryRoute? {
        storedCallCount += 1
        await gate.wait()
        return route
    }

    func callCount() -> Int {
        storedCallCount
    }
}

private actor AccountRuntimeEventRecorder {
    private var events: [String] = []

    func append(_ event: String) {
        events.append(event)
    }

    func snapshot() -> [String] {
        events
    }
}

private actor AccountRuntimeTestGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let currentWaiters = waiters
        waiters.removeAll()
        for waiter in currentWaiters {
            waiter.resume()
        }
    }

    func waiterCount() -> Int {
        waiters.count
    }
}

private actor LifecycleGameCenterSubmissionChannelDouble:
    GameCenterSubmissionChannel
{
    func prepareGameCenterSubmission(
        for playerID: GameCenterPlayerID
    ) async throws -> LocalGameCenterPreparedSubmissionV1? {
        nil
    }

    func acknowledgeGameCenterSubmission(
        _ submission: LocalGameCenterPreparedSubmissionV1,
        successfulResult: GameCenterSuccessfulSubmissionV1,
        at date: Date
    ) async throws -> LocalPlayerProfileSnapshot {
        throw ProductionGameCenterSubmissionChannelError.staleAcknowledgement
    }
}

private actor LifecycleGameCenterServiceDouble: GameCenterServicing {
    private let playerID = GameCenterPlayerID("lifecycle-player")
    private var authenticationCalls = 0
    private var presentationCalls = 0
    private var state: GameCenterAuthenticationState = .notRequested

    func authenticationState() -> GameCenterAuthenticationState {
        state
    }

    func authenticate() -> GameCenterAuthenticationState {
        authenticationCalls += 1
        state = .authenticated(playerID)
        return state
    }

    func submit(_ batch: GameCenterSubmissionBatch) throws {}

    func requestPresentation(
        _ destination: GameCenterPresentationDestination
    ) throws {
        presentationCalls += 1
    }

    func authenticationCount() -> Int {
        authenticationCalls
    }

    func presentationCount() -> Int {
        presentationCalls
    }
}

private actor AccountRuntimeDiscovery: ProductionCloudAccountDiscovering {
    private let states: [CloudAccountState]
    private let events: AccountRuntimeEventRecorder
    private var index = 0

    init(
        states: [CloudAccountState],
        events: AccountRuntimeEventRecorder
    ) {
        precondition(!states.isEmpty)
        self.states = states
        self.events = events
    }

    func accountState() async -> CloudAccountState {
        let state = states[min(index, states.count - 1)]
        index += 1
        let label: String
        switch state {
        case let .available(accountID):
            label = accountID.rawValue
        case .unknown:
            label = "unknown"
        case .signedOut:
            label = "signedOut"
        case .restricted:
            label = "restricted"
        }
        await events.append("discover:\(label)")
        return state
    }
}

private actor AccountRuntimeClaimer: ProductionAccountClaiming {
    private let claims: [CloudAccountID: ProductionVerifiedAccountClaim]
    private let events: AccountRuntimeEventRecorder
    private let gate: AccountRuntimeTestGate?

    init(
        claims: [CloudAccountID: ProductionVerifiedAccountClaim],
        events: AccountRuntimeEventRecorder,
        gate: AccountRuntimeTestGate? = nil
    ) {
        self.claims = claims
        self.events = events
        self.gate = gate
    }

    func claimAndHydrate(
        accountID: CloudAccountID,
        derivedBindings: CloudAccountDerivedBindings
    ) async throws -> ProductionVerifiedAccountClaim {
        await events.append("claim:\(accountID.rawValue)")
        await gate?.wait()
        guard derivedBindings == CloudAccountDerivedBindings.derive(from: accountID),
              let claim = claims[accountID] else {
            throw AccountRuntimeFixtureFailure.missingClaim
        }
        return claim
    }
}

private actor AccountRuntimeClaimSequence: ProductionAccountClaiming {
    private let claims: [ProductionVerifiedAccountClaim]
    private let events: AccountRuntimeEventRecorder
    private var index = 0

    init(
        claims: [ProductionVerifiedAccountClaim],
        events: AccountRuntimeEventRecorder
    ) {
        precondition(!claims.isEmpty)
        self.claims = claims
        self.events = events
    }

    func claimAndHydrate(
        accountID: CloudAccountID,
        derivedBindings: CloudAccountDerivedBindings
    ) async throws -> ProductionVerifiedAccountClaim {
        await events.append("claim:\(accountID.rawValue)")
        let claim = claims[min(index, claims.count - 1)]
        index += 1
        guard claim.cloudAccountID == accountID,
              derivedBindings == CloudAccountDerivedBindings.derive(
                from: accountID
              ) else {
            throw AccountRuntimeFixtureFailure.missingClaim
        }
        return claim
    }
}

private actor AccountRuntimeComponent: ProductionAccountRuntimeComponent {
    private let role: String
    private let accountID: CloudAccountID
    private let events: AccountRuntimeEventRecorder
    private var isActive = false

    init(
        role: String,
        accountID: CloudAccountID,
        events: AccountRuntimeEventRecorder
    ) {
        self.role = role
        self.accountID = accountID
        self.events = events
    }

    func activate(context: ProductionAccountRuntimeContext) async throws {
        guard context.cloudAccountID == accountID else {
            throw AccountRuntimeFixtureFailure.contextMismatch
        }
        isActive = true
        await events.append("activate:\(role):\(accountID.rawValue)")
    }

    func shutdown() async {
        isActive = false
        await events.append("shutdown:\(role):\(accountID.rawValue)")
    }
}

private actor AccountRuntimeCommerceService: ProductionCommerceRequestServicing {
    private let accountID: CloudAccountID
    private let events: AccountRuntimeEventRecorder
    private let gate: AccountRuntimeTestGate?

    init(
        accountID: CloudAccountID,
        events: AccountRuntimeEventRecorder,
        gate: AccountRuntimeTestGate?
    ) {
        self.accountID = accountID
        self.events = events
        self.gate = gate
    }

    func perform(
        _ request: ProductionCommerceRequest
    ) async -> ProductionCommerceRequestResult {
        let operation: String
        switch request {
        case .catalogUnlock:
            operation = "unlock"
        case .coinPack:
            operation = "coinPack"
        }
        await events.append("commerce:\(operation):\(accountID.rawValue)")
        await gate?.wait()
        return .succeeded
    }
}

private actor AccountRuntimeBuilder: ProductionAccountScopedRuntimeBuilding {
    private let events: AccountRuntimeEventRecorder
    private let commerceGate: AccountRuntimeTestGate?

    init(
        events: AccountRuntimeEventRecorder,
        commerceGate: AccountRuntimeTestGate? = nil
    ) {
        self.events = events
        self.commerceGate = commerceGate
    }

    func makeAccountScopedRuntime(
        context: ProductionAccountRuntimeContext,
        verifiedClaim: ProductionVerifiedAccountClaim
    ) async throws -> ProductionAccountScopedRuntimeComponents {
        guard verifiedClaim.cloudAccountID == context.cloudAccountID,
              verifiedClaim.snapshot.session
                == context.profileSnapshot.session else {
            throw AccountRuntimeFixtureFailure.contextMismatch
        }
        let accountID = context.cloudAccountID
        await events.append("build:\(accountID.rawValue)")
        return ProductionAccountScopedRuntimeComponents(
            installedRepository: verifiedClaim.installedRepository,
            cloud: AccountRuntimeComponent(
                role: "cloud",
                accountID: accountID,
                events: events
            ),
            economy: AccountRuntimeComponent(
                role: "economy",
                accountID: accountID,
                events: events
            ),
            storeKit: AccountRuntimeComponent(
                role: "storeKit",
                accountID: accountID,
                events: events
            ),
            commerce: AccountRuntimeCommerceService(
                accountID: accountID,
                events: events,
                gate: commerceGate
            )
        )
    }
}

private enum AccountRuntimeFixtureFailure: Error {
    case missingClaim
    case missingGraph
    case contextMismatch
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

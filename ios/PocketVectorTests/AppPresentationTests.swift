import Foundation
import SpriteKit
import SwiftUI
import UIKit
import XCTest

@testable import PocketVector

final class AppPresentationTests: XCTestCase {
    @MainActor
    func testCaptureSharedHeaderAccessibilityMatrix() async throws {
        let coordinator = AppCoordinator()
        await coordinator.bootstrap()
        coordinator.showTutorialReview()

        let results = try makeRunResultsPresentation()
        let surfaces: [(name: String, view: AnyView)] = [
            ("choose-offense", AnyView(TeamSelectionView(coordinator: coordinator))),
            ("team-locker", AnyView(LockerView(coordinator: coordinator))),
            ("coin-store", AnyView(CoinStoreView(coordinator: coordinator))),
            ("achievements", AnyView(AchievementsView(coordinator: coordinator))),
            ("settings", AnyView(SettingsView(coordinator: coordinator))),
            (
                "tutorial-rules",
                AnyView(TutorialView(coordinator: coordinator, initialPage: .gameRules))
            ),
            (
                "tutorial-passing",
                AnyView(TutorialView(coordinator: coordinator, initialPage: .passing))
            ),
            (
                "results",
                AnyView(RunResultsView(results: results, coordinator: coordinator))
            ),
        ]
        let viewports: [(
            name: String,
            size: CGSize,
            horizontalSizeClass: UserInterfaceSizeClass,
            verticalSizeClass: UserInterfaceSizeClass,
            dynamicTypeSize: DynamicTypeSize
        )] = [
            (
                "compact-iphone-landscape-accessibility5",
                CGSize(width: 667, height: 375),
                .compact,
                .compact,
                .accessibility5
            ),
            (
                "regular-iphone-landscape-accessibility5",
                CGSize(width: 874, height: 402),
                .compact,
                .compact,
                .accessibility5
            ),
            (
                "ipad-landscape-accessibility5",
                CGSize(width: 1_376, height: 1_032),
                .regular,
                .regular,
                .accessibility5
            ),
            (
                "regular-iphone-landscape-standard",
                CGSize(width: 874, height: 402),
                .compact,
                .compact,
                .large
            ),
            (
                "ipad-landscape-standard",
                CGSize(width: 1_376, height: 1_032),
                .regular,
                .regular,
                .large
            ),
        ]

        for viewport in viewports {
            for surface in surfaces {
                capture(
                    AnyView(
                        ZStack {
                            PocketVectorBackdrop()
                            surface.view
                        }
                        .dynamicTypeSize(viewport.dynamicTypeSize)
                        .environment(\.horizontalSizeClass, viewport.horizontalSizeClass)
                        .environment(\.verticalSizeClass, viewport.verticalSizeClass)
                    ),
                    size: viewport.size,
                    name: "shared-header-\(surface.name)-\(viewport.name)"
                )
            }
        }
    }

    @MainActor
    func testCaptureAchievementPresentationMatrix() async throws {
        let coordinator = AppCoordinator()
        await coordinator.bootstrap()

        let viewports: [(
            name: String,
            size: CGSize,
            horizontalSizeClass: UserInterfaceSizeClass,
            verticalSizeClass: UserInterfaceSizeClass
        )] = [
            (
                "compact-iphone-landscape",
                CGSize(width: 667, height: 375),
                .compact,
                .compact
            ),
            (
                "regular-iphone-landscape",
                CGSize(width: 874, height: 402),
                .compact,
                .compact
            ),
            (
                "ipad-landscape",
                CGSize(width: 1_376, height: 1_032),
                .regular,
                .regular
            ),
        ]

        for viewport in viewports {
            let evidence = AnyView(
                ZStack {
                    PocketVectorBackdrop()
                    AchievementsView(coordinator: coordinator)
                }
                .dynamicTypeSize(.large)
                .environment(\.horizontalSizeClass, viewport.horizontalSizeClass)
                .environment(\.verticalSizeClass, viewport.verticalSizeClass)
            )
            capture(
                evidence,
                size: viewport.size,
                name: "achievements-v11-\(viewport.name)-top"
            )
            if viewport.name == "compact-iphone-landscape" {
                capture(
                    achievementFinalRowsEvidenceView(
                        coordinator: coordinator,
                        horizontalSizeClass: viewport.horizontalSizeClass,
                        verticalSizeClass: viewport.verticalSizeClass
                    ),
                    size: viewport.size,
                    name: "achievements-v11-\(viewport.name)-bottom"
                )
            } else {
                await captureScrolledToBottom(
                    evidence,
                    size: viewport.size,
                    name: "achievements-v11-\(viewport.name)-bottom"
                )
            }
        }
    }

    @MainActor
    func testCaptureTutorialAndResultsLayoutMatrix() async throws {
        let tutorialCoordinator = AppCoordinator()
        await tutorialCoordinator.bootstrap()
        tutorialCoordinator.showTutorialReview()

        let resultsCoordinator = AppCoordinator()
        let results = try makeRunResultsPresentation()
        let frozenGameplayFrame = try await makeFrozenGameplayFrame(
            configuration: results.completedRun.configuration
        )
        let viewports: [(name: String, size: CGSize)] = [
            ("compact-iphone-landscape", CGSize(width: 667, height: 375)),
            ("regular-iphone-landscape", CGSize(width: 874, height: 402)),
            ("ipad-landscape", CGSize(width: 1_376, height: 1_032)),
        ]
        let textSizes: [(name: String, size: DynamicTypeSize)] = [
            ("standard", .large),
            ("accessibility5", .accessibility5),
        ]

        for viewport in viewports {
            for textSize in textSizes {
                capture(
                    AnyView(
                        ZStack {
                            PocketVectorBackdrop()
                            TutorialView(
                                coordinator: tutorialCoordinator,
                                initialPage: .gameRules
                            )
                        }
                        .dynamicTypeSize(textSize.size)
                    ),
                    size: viewport.size,
                    name: "tutorial-rules-\(viewport.name)-\(textSize.name)"
                )
                capture(
                    AnyView(
                        ZStack {
                            PocketVectorBackdrop()
                            TutorialView(
                                coordinator: tutorialCoordinator,
                                initialPage: .passing
                            )
                        }
                        .dynamicTypeSize(textSize.size)
                    ),
                    size: viewport.size,
                    name: "tutorial-passing-\(viewport.name)-\(textSize.name)"
                )
                capture(
                    resultsEvidenceView(
                        frame: frozenGameplayFrame,
                        results: results,
                        coordinator: resultsCoordinator,
                        textSize: textSize.size
                    ),
                    size: viewport.size,
                    name: "retained-results-\(viewport.name)-\(textSize.name)"
                )

                if textSize.size.isAccessibilitySize {
                    await captureScrolledToBottom(
                        resultsEvidenceView(
                            frame: frozenGameplayFrame,
                            results: results,
                            coordinator: resultsCoordinator,
                            textSize: textSize.size
                        ),
                        size: viewport.size,
                        name: "retained-results-\(viewport.name)-\(textSize.name)-bottom"
                    )
                }
            }
        }
    }

    @MainActor
    private func resultsEvidenceView(
        frame: UIImage,
        results: RunResultsPresentation,
        coordinator: AppCoordinator,
        textSize: DynamicTypeSize
    ) -> AnyView {
        AnyView(
            ZStack {
                Color.black
                Image(uiImage: frame)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .accessibilityHidden(true)
                RunResultsView(results: results, coordinator: coordinator)
            }
                .dynamicTypeSize(textSize)
        )
    }

    func testTutorialMediaCacheRejectsSameSizeCorruption() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PocketVectorTutorialCacheTests")
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }

        let expectedData = Data(repeating: 0xA5, count: 64)
        let mediaURL = try TutorialMediaCache.validatedURL(
            for: expectedData,
            directory: directory
        )
        XCTAssertTrue(TutorialMediaCache.fileMatches(at: mediaURL, expectedData: expectedData))

        try Data(repeating: 0x5A, count: expectedData.count)
            .write(to: mediaURL, options: .atomic)
        XCTAssertFalse(TutorialMediaCache.fileMatches(at: mediaURL, expectedData: expectedData))

        let repairedURL = try TutorialMediaCache.validatedURL(
            for: expectedData,
            directory: directory
        )
        XCTAssertEqual(try Data(contentsOf: repairedURL), expectedData)
    }

    func testTutorialScoringGuidanceDefinesPenaltyAndScoreFloor() {
        XCTAssertEqual(
            TutorialRule.scoring.guidance,
            "Completions and touchdowns add points. An interception is a −250-point penalty, but your score cannot fall below zero."
        )
    }

    func testTutorialPassingPageHasRulesAsPreviousPage() {
        XCTAssertEqual(TutorialPage.passing.previous, .gameRules)
        XCTAssertNil(TutorialPage.gameRules.previous)
    }

    func testTutorialPassingGuidanceExplainsBulletAndLobReleaseTiming() {
        XCTAssertEqual(
            TutorialPassingGuidance.instruction,
            "Start on the quarterback, drag to open grass away from defenders, then release. "
                + "Release quickly for a bullet (low trajectory), or hold longer before releasing for a lob "
                + "(high trajectory). The receiver runs under the throw."
        )
    }

    func testTutorialPlaybackOnlyRunsOnActivePassingPageWithMotionEnabled() {
        XCTAssertFalse(TutorialPlaybackPolicy.shouldPlay(
            page: .gameRules,
            mediaIsReady: true,
            reducesMotion: false,
            sceneIsActive: true
        ))
        XCTAssertFalse(TutorialPlaybackPolicy.shouldPlay(
            page: .passing,
            mediaIsReady: true,
            reducesMotion: true,
            sceneIsActive: true
        ))
        XCTAssertFalse(TutorialPlaybackPolicy.shouldPlay(
            page: .passing,
            mediaIsReady: true,
            reducesMotion: false,
            sceneIsActive: false
        ))
        XCTAssertTrue(TutorialPlaybackPolicy.shouldPlay(
            page: .passing,
            mediaIsReady: true,
            reducesMotion: false,
            sceneIsActive: true
        ))
    }

    func testRunResultsCoinLedgerUsesApprovedOrderAndReconcilesToTotal() throws {
        let results = try makeRunResultsPresentation()
        let ledger = RunResultsCoinLedger(results: results)

        XCTAssertEqual(
            ledger.lines.map(\.label),
            ["RUN COMPLETE", "SCORE BONUS", "ACCURACY BONUS", "FIRST RUN BONUS"]
        )
        XCTAssertEqual(ledger.lines.map(\.amount), [10, 12, 5, 250])
        XCTAssertEqual(ledger.total, 277)
        XCTAssertEqual(ledger.lines.reduce(0) { $0 + $1.amount }, ledger.total)
    }

    func testRunResultsCoinLedgerOmitsUnearnedSigningBonus() throws {
        let firstRunResults = try makeRunResultsPresentation()
        let laterRunResults = RunResultsPresentation(
            completedRun: firstRunResults.completedRun,
            completionCoins: firstRunResults.completionCoins,
            performanceCoins: firstRunResults.performanceCoins,
            accuracyCoins: firstRunResults.accuracyCoins,
            signingBonusCoins: 0,
            totalEarnedCoins: 27,
            pendingCoins: 0,
            gameplayRewardState: .recorded,
            signingBonusState: nil,
            personalBest: firstRunResults.personalBest,
            isNewPersonalBest: false,
            rewardedAdOffer: firstRunResults.rewardedAdOffer
        )
        let ledger = RunResultsCoinLedger(results: laterRunResults)

        XCTAssertEqual(
            ledger.lines.map(\.label),
            ["RUN COMPLETE", "SCORE BONUS", "ACCURACY BONUS"]
        )
        XCTAssertEqual(ledger.lines.reduce(0) { $0 + $1.amount }, ledger.total)
    }

    func testRetainedRunPresentationKeepsOneSceneIdentityFromGameplayThroughResults() throws {
        let results = try makeRunResultsPresentation()
        let gameplay = try XCTUnwrap(
            RetainedRunPresentation(destination: .gameplay(results.completedRun.configuration))
        )
        let settled = try XCTUnwrap(
            RetainedRunPresentation(destination: .runResults(results))
        )

        XCTAssertEqual(gameplay.sceneIdentity, settled.sceneIdentity)
        XCTAssertEqual(gameplay.configuration, settled.configuration)
        XCTAssertFalse(gameplay.freezesGameplay)
        XCTAssertTrue(settled.freezesGameplay)
    }

    func testRetainedRunPresentationUsesANewSceneIdentityForReplayRun() throws {
        let results = try makeRunResultsPresentation()
        let firstRun = try XCTUnwrap(
            RetainedRunPresentation(destination: .runResults(results))
        )
        let configuration = results.completedRun.configuration
        let replayConfiguration = RunConfiguration(
            runID: RunID(),
            randomSeed: configuration.randomSeed,
            offenseTeamID: configuration.offenseTeamID,
            offenseJerseyID: configuration.offenseJerseyID,
            defenseTeamID: configuration.defenseTeamID,
            defenseJerseyID: configuration.defenseJerseyID,
            footballID: configuration.footballID,
            economyVersion: configuration.economyVersion,
            startedAt: configuration.startedAt.addingTimeInterval(90)
        )
        let replay = try XCTUnwrap(
            RetainedRunPresentation(destination: .gameplay(replayConfiguration))
        )

        XCTAssertNotEqual(firstRun.sceneIdentity, replay.sceneIdentity)
    }

    @MainActor
    func testHostedShellRetainsAndFreezesExactGameSceneThroughResults() async throws {
        var state = AppCoordinatorState.launchDefault()
        state.settings.tutorialCompleted = true
        let coordinator = AppCoordinator(state: state)
        await coordinator.bootstrap()
        let results = try makeRunResultsPresentation()
        coordinator.navigate(to: .gameplay(results.completedRun.configuration))

        let host = UIHostingController(
            rootView: AppShellView(coordinator: coordinator, onRetryBootstrap: {})
        )
        let size = CGSize(width: 874, height: 402)
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = host
        window.isHidden = false
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()

        let gameplayView = try await waitForGameplayView(
            in: host.view,
            runID: results.completedRun.runID
        )
        let retainedScene = try XCTUnwrap(gameplayView.scene as? GameScene)
        XCTAssertFalse(retainedScene.isPaused)

        for tick in 0 ... 750 {
            retainedScene.update(TimeInterval(tick) * 0.1)
        }
        XCTAssertFalse(retainedScene.currentSnapshot.defersBottomSystemGestures)
        XCTAssertTrue(
            try XCTUnwrap(retainedScene.childNode(withName: "//broadcastHUD")).isHidden
        )

        coordinator.showRunResults(results)
        try await Task.sleep(for: .milliseconds(200))
        let frozenGameplayView = try await waitForGameplayView(
            in: host.view,
            runID: results.completedRun.runID
        )
        let frozenScene = try XCTUnwrap(frozenGameplayView.scene as? GameScene)

        XCTAssertTrue(gameplayView === frozenGameplayView)
        XCTAssertTrue(retainedScene === frozenScene)
        XCTAssertNotNil(frozenGameplayView.texture(from: frozenScene))

        let actionProbe = SKNode()
        frozenScene.addChild(actionProbe)
        actionProbe.run(.moveBy(x: 100, y: 0, duration: 0.05), withKey: "freeze-probe")
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(actionProbe.position, .zero)

        let resultControlPoint = CGPoint(x: size.width * 0.74, y: size.height * 0.88)
        let hitView = host.view.hitTest(resultControlPoint, with: nil)
        XCTAssertFalse(isDescendant(hitView, of: frozenGameplayView))

        coordinator.replayAfterResults()
        guard case let .gameplay(replayConfiguration) = coordinator.currentDestination else {
            return XCTFail("Expected Play Again to start a new gameplay run")
        }
        let replayGameplayView = try await waitForGameplayView(
            in: host.view,
            runID: replayConfiguration.runID
        )
        let replayScene = try XCTUnwrap(replayGameplayView.scene as? GameScene)
        XCTAssertFalse(replayGameplayView === frozenGameplayView)
        XCTAssertFalse(replayScene === frozenScene)

        let replayActionProbe = SKNode()
        replayScene.addChild(replayActionProbe)
        replayActionProbe.run(
            .moveBy(x: 100, y: 0, duration: 0.05),
            withKey: "replay-active-probe"
        )
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(replayActionProbe.position.x, 100, accuracy: 0.5)

        coordinator.returnToMainMenu()
        try await waitForGameplayViewsToUnmount(in: host.view)
    }

    @MainActor
    func testResultsNavigationPreservesMainMenuAndReplayCoordinatorActions() async throws {
        var state = AppCoordinatorState.launchDefault()
        state.settings.tutorialCompleted = true
        let coordinator = AppCoordinator(state: state)
        await coordinator.bootstrap()
        let results = try makeRunResultsPresentation()

        coordinator.showRunResults(results)
        coordinator.returnToMainMenu()
        XCTAssertEqual(coordinator.navigationPath, [.mainMenu])
        XCTAssertNil(RetainedRunPresentation(destination: coordinator.currentDestination))

        coordinator.showRunResults(results)
        coordinator.replayAfterResults()
        guard case let .gameplay(replayConfiguration) = coordinator.currentDestination else {
            return XCTFail("Expected replay to replace Results with gameplay")
        }
        XCTAssertNotEqual(replayConfiguration.runID, results.completedRun.runID)
        XCTAssertEqual(coordinator.navigationPath, [.mainMenu, .gameplay(replayConfiguration)])
    }

    func testFrozenResultsDisableGameplayAndSuppressAllAdapterChrome() throws {
        let results = try makeRunResultsPresentation()
        let retained = try XCTUnwrap(
            RetainedRunPresentation(destination: .runResults(results))
        )
        let chrome = GameplayAdapterChromePolicy(
            freezesPresentation: retained.freezesGameplay
        )

        XCTAssertFalse(retained.allowsGameplayInteraction)
        XCTAssertTrue(retained.hidesGameplayFromAccessibility)
        XCTAssertFalse(chrome.showsPausedControls)
        XCTAssertFalse(chrome.showsSettlementChrome)
        XCTAssertFalse(chrome.allowsGameplayInteraction)
        XCTAssertTrue(chrome.hidesGameplayFromAccessibility)

        var state = GameState()
        state.phase = .results
        let snapshot = GameplaySceneSnapshot(state: state)
        XCTAssertEqual(
            GameplaySystemGestureDeferralPolicy.edges(
                snapshot: snapshot,
                isSettling: false,
                settlementErrorMessage: nil,
                freezesPresentation: true
            ),
            []
        )
        XCTAssertFalse(HUDPresentation(state: state).isVisible)
    }

    func testActiveGameplayPreservesInteractionChromeAndGestureDeferral() {
        let chrome = GameplayAdapterChromePolicy(freezesPresentation: false)
        var state = GameState()
        state.phase = .playing
        let snapshot = GameplaySceneSnapshot(state: state)

        XCTAssertTrue(chrome.showsPausedControls)
        XCTAssertTrue(chrome.showsSettlementChrome)
        XCTAssertTrue(chrome.allowsGameplayInteraction)
        XCTAssertFalse(chrome.hidesGameplayFromAccessibility)
        XCTAssertEqual(
            GameplaySystemGestureDeferralPolicy.edges(
                snapshot: snapshot,
                isSettling: false,
                settlementErrorMessage: nil,
                freezesPresentation: false
            ),
            .bottom
        )
    }

    @MainActor
    func testRootViewControllerLocksBottomGestureDeferralAcrossTheWholeApp() {
        let controller = RecordingRootViewController(
            rootView: AnyView(Color.clear)
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 874, height: 402))
        window.rootViewController = controller
        window.isHidden = false
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        XCTAssertTrue(window.rootViewController === controller)
        XCTAssertEqual(controller.children.count, 1)
        XCTAssertTrue(controller.children[0] is UIHostingController<AnyView>)
        XCTAssertNil(controller.childForScreenEdgesDeferringSystemGestures)
        XCTAssertNil(controller.childForStatusBarHidden)
        XCTAssertNil(controller.childForStatusBarStyle)
        XCTAssertNil(controller.childForHomeIndicatorAutoHidden)
        XCTAssertTrue(controller.prefersStatusBarHidden)
        XCTAssertEqual(controller.preferredStatusBarStyle, .lightContent)
        XCTAssertFalse(controller.prefersHomeIndicatorAutoHidden)
        let deferralRecognizer = controller.bottomSystemGestureDeferralRecognizer
        XCTAssertTrue(controller.view.gestureRecognizers?.contains(deferralRecognizer) == true)
        XCTAssertEqual(deferralRecognizer.maximumNumberOfTouches, 1)
        XCTAssertFalse(deferralRecognizer.cancelsTouchesInView)
        XCTAssertFalse(deferralRecognizer.delaysTouchesBegan)
        XCTAssertFalse(deferralRecognizer.delaysTouchesEnded)
        XCTAssertTrue(deferralRecognizer.delegate === controller)
        XCTAssertTrue(
            controller.gestureRecognizer(
                deferralRecognizer,
                shouldRecognizeSimultaneouslyWith: UIPanGestureRecognizer()
            )
        )
        XCTAssertEqual(controller.preferredScreenEdgesDeferringSystemGestures, .bottom)
        let updateCountAfterAttachment = controller.screenEdgeUpdateRequestCount

        controller.viewDidAppear(false)
        XCTAssertEqual(
            controller.screenEdgeUpdateRequestCount,
            updateCountAfterAttachment + 1
        )
        controller.viewSafeAreaInsetsDidChange()
        XCTAssertEqual(
            controller.screenEdgeUpdateRequestCount,
            updateCountAfterAttachment + 2
        )

        let runID = RunID()
        let state = RootSystemGestureDeferralState()
        func assertRootRemainsLocked(
            _ context: String,
            file: StaticString = #filePath,
            line: UInt = #line
        ) {
            XCTAssertEqual(
                controller.preferredScreenEdgesDeferringSystemGestures,
                .bottom,
                context,
                file: file,
                line: line
            )
        }

        assertRootRemainsLocked("Main Menu must remain deferred")
        state.setApplicationActive(true)
        state.setAllowedGameplayRunID(runID)
        state.receive(
            gameplaySnapshot(phase: .countdown),
            for: runID,
            freezesPresentation: false
        )
        assertRootRemainsLocked("Countdown must remain deferred")

        state.receive(
            gameplaySnapshot(phase: .playing),
            for: runID,
            freezesPresentation: false
        )
        assertRootRemainsLocked("Playing must remain deferred")

        state.receive(
            gameplaySnapshot(phase: .resolvingFinalBall),
            for: runID,
            freezesPresentation: false
        )
        assertRootRemainsLocked("Final-ball resolution must remain deferred")

        state.receive(
            gameplaySnapshot(phase: .paused),
            for: runID,
            freezesPresentation: false
        )
        assertRootRemainsLocked("Pause must remain deferred")

        state.receive(
            gameplaySnapshot(phase: .playing),
            for: runID,
            freezesPresentation: true
        )
        assertRootRemainsLocked("Frozen Results presentation must remain deferred")

        state.setAllowedGameplayRunID(nil)
        assertRootRemainsLocked("Results and settlement must remain deferred")

        state.setApplicationActive(false)
        assertRootRemainsLocked("An inactive scene cannot clear the root policy")

        XCTAssertEqual(
            controller.screenEdgeUpdateRequestCount,
            updateCountAfterAttachment + 2
        )
    }

    @MainActor
    func testRootGestureDeferralRequiresMatchingLiveRunAndClearsAtEveryBlocker() {
        let state = RootSystemGestureDeferralState()
        let firstRunID = RunID()
        let replayRunID = RunID()

        state.setApplicationActive(true)
        state.setAllowedGameplayRunID(firstRunID)
        state.receive(
            gameplaySnapshot(phase: .countdown),
            for: firstRunID,
            freezesPresentation: false
        )
        XCTAssertTrue(state.defersBottomSystemGestures)

        state.receive(
            gameplaySnapshot(phase: .playing),
            for: firstRunID,
            freezesPresentation: false
        )
        XCTAssertTrue(state.defersBottomSystemGestures)

        state.receive(
            gameplaySnapshot(phase: .paused),
            for: firstRunID,
            freezesPresentation: false
        )
        XCTAssertFalse(state.defersBottomSystemGestures)

        state.receive(
            gameplaySnapshot(phase: .playing),
            for: firstRunID,
            freezesPresentation: false
        )
        XCTAssertTrue(state.defersBottomSystemGestures)

        state.receive(
            gameplaySnapshot(phase: .resolvingFinalBall),
            for: firstRunID,
            freezesPresentation: false
        )
        XCTAssertTrue(state.defersBottomSystemGestures)

        state.setAllowedGameplayRunID(nil)
        XCTAssertFalse(state.defersBottomSystemGestures)

        state.setAllowedGameplayRunID(replayRunID)
        XCTAssertFalse(state.defersBottomSystemGestures, "A stale prior-run snapshot cannot defer replay")

        state.receive(
            gameplaySnapshot(phase: .countdown),
            for: replayRunID,
            freezesPresentation: false
        )
        XCTAssertTrue(state.defersBottomSystemGestures)

        state.receive(
            gameplaySnapshot(phase: .playing),
            for: replayRunID,
            freezesPresentation: false
        )
        XCTAssertTrue(state.defersBottomSystemGestures)

        state.receive(
            gameplaySnapshot(phase: .playing),
            for: replayRunID,
            freezesPresentation: true
        )
        XCTAssertFalse(state.defersBottomSystemGestures)

        state.receive(
            gameplaySnapshot(phase: .playing),
            for: replayRunID,
            freezesPresentation: false
        )
        state.setApplicationActive(false)
        XCTAssertFalse(state.defersBottomSystemGestures)

        state.setApplicationActive(true)
        XCTAssertTrue(state.defersBottomSystemGestures)
        state.clearGameplayRequest(for: firstRunID)
        XCTAssertTrue(state.defersBottomSystemGestures, "A stale disappearance cannot clear replay")
        state.clearGameplayRequest(for: replayRunID)
        XCTAssertFalse(state.defersBottomSystemGestures)
    }

    func testRootGesturePresentationPolicyDisablesNonGameplaySettlementAndResults() throws {
        let results = try makeRunResultsPresentation()
        let configuration = results.completedRun.configuration

        XCTAssertEqual(
            RootSystemGestureDeferralPresentationPolicy.allowedGameplayRunID(
                bootstrapState: .ready,
                destination: .gameplay(configuration),
                isSettling: false,
                settlementErrorMessage: nil
            ),
            configuration.runID
        )

        let blockedContexts: [(AppBootstrapState, AppDestination, Bool, String?)] = [
            (.loading, .gameplay(configuration), false, nil),
            (.failed(message: "Unavailable"), .gameplay(configuration), false, nil),
            (.ready, .gameplay(configuration), true, nil),
            (.ready, .gameplay(configuration), false, "Save failed"),
            (.ready, .mainMenu, false, nil),
            (.ready, .settings, false, nil),
            (.ready, .coinStore, false, nil),
            (.ready, .tutorial(.review), false, nil),
            (.ready, .runResults(results), false, nil),
        ]

        for context in blockedContexts {
            XCTAssertNil(
                RootSystemGestureDeferralPresentationPolicy.allowedGameplayRunID(
                    bootstrapState: context.0,
                    destination: context.1,
                    isSettling: context.2,
                    settlementErrorMessage: context.3
                )
            )
        }
    }

    func testTeamPresentationUsesSixteenApprovedTeamsWithFourOwnedAndTwelveLocked() throws {
        let catalog = LaunchCatalog.approved
        let state = AppCoordinatorState.launchDefault(catalog: catalog)
        let cards = AppPresentation.teams(catalog: catalog, state: state)

        XCTAssertEqual(cards.map(\.id), catalog.teams.map(\.id))
        XCTAssertEqual(cards.count, 16)
        XCTAssertEqual(cards.filter(\.isOwned).count, 4)
        XCTAssertEqual(cards.filter(\.isLocked).count, 12)
        XCTAssertTrue(cards.first?.isSelected == true)
        XCTAssertEqual(
            Set(cards.filter(\.isLocked).compactMap(\.unlockItem?.price)),
            [1_500]
        )

        let expansionCards = cards.filter {
            Set(LaunchTeamID.expansionEight).contains($0.id)
        }
        XCTAssertEqual(expansionCards.count, 8)
        for card in expansionCards {
            let team = card.team
            let assetRoot = "teams/\(team.id.rawValue)"
            let identity = try XCTUnwrap(
                LaunchVisualIdentityCatalog.knownTeam(for: team)
            )

            XCTAssertTrue(card.isLocked)
            XCTAssertEqual(card.unlockItem?.price, 1_500)
            XCTAssertEqual(team.assets.logo, "\(assetRoot)/logo")
            XCTAssertEqual(team.assets.fieldBranding, "\(assetRoot)/field-branding")
            XCTAssertEqual(
                identity.jerseys.map(\.jerseyID),
                [team.primaryJersey.id, team.alternateJersey.id]
            )
            XCTAssertNotNil(
                GameAssetResources.url(
                    for: "pixel/\(team.assets.endZone).png"
                )
            )
            XCTAssertNotNil(
                GameAssetResources.url(
                    for: "pixel/\(team.assets.fieldBranding).png"
                )
            )
        }
    }

    func testLockerPresentationKeepsAlternateJerseyTeamScopedAndFootballGlobal() throws {
        let catalog = LaunchCatalog.approved
        let state = AppCoordinatorState.launchDefault(catalog: catalog)
        let team = try XCTUnwrap(catalog.team(id: LaunchTeamID.novaCityComets))

        let jerseys = AppPresentation.jerseys(for: team, catalog: catalog, state: state)
        XCTAssertEqual(jerseys.count, 2)
        XCTAssertTrue(jerseys[0].isOwned)
        XCTAssertTrue(jerseys[0].isEquipped)
        XCTAssertFalse(jerseys[1].isOwned)
        XCTAssertEqual(jerseys[1].unlockItem?.price, EconomyConfiguration.alternateJerseyPrice)
        XCTAssertEqual(jerseys[1].jersey.teamID, team.id)

        let footballs = AppPresentation.footballs(catalog: catalog, state: state)
        XCTAssertEqual(footballs.count, 2)
        XCTAssertTrue(footballs[0].isEquipped)
        XCTAssertEqual(footballs[1].unlockItem?.price, EconomyConfiguration.alternateFootballPrice)
    }

    func testAchievementSummaryAlwaysRepresentsAllFourteenAndOneThousandPoints() {
        var progress = Dictionary(
            uniqueKeysWithValues: AchievementCatalog.launch.map {
                ($0.id, AchievementProgress(id: $0.id))
            }
        )
        let completed = AchievementCatalog.launch[0]
        progress[completed.id] = AchievementProgress(
            id: completed.id,
            percentComplete: 100,
            completedAt: Date(timeIntervalSince1970: 1)
        )

        let cards = AppPresentation.achievements(progress: progress)
        let summary = AppPresentation.achievementSummary(cards: cards)

        XCTAssertEqual(cards.count, 14)
        XCTAssertEqual(summary.completedCount, 1)
        XCTAssertEqual(summary.totalCount, 14)
        XCTAssertEqual(summary.earnedPoints, completed.points)
        XCTAssertEqual(summary.totalPoints, 1_000)
    }

    func testAchievementIconPresentationCoversVersionOneOneCatalog() {
        let expected: [AchievementID: String] = [
            LaunchAchievementID.firstRead: "AchievementFirstReadIcon",
            LaunchAchievementID.paydirt: "AchievementPaydirtIcon",
            LaunchAchievementID.cashTheCharge: "AchievementCashTheChargeIcon",
            LaunchAchievementID.fullRouteTree: "AchievementFullRouteTreeIcon",
            LaunchAchievementID.dialedIn: "AchievementDialedInIcon",
            LaunchAchievementID.hotHand: "AchievementHotHandIcon",
            LaunchAchievementID.lightUpTheBoard: "AchievementLightUpBoardIcon",
            LaunchAchievementID.millenniaOfConnections:
                "AchievementCenturyConnectionsIcon",
            LaunchAchievementID.perfectPocket: "AchievementPerfectPocketIcon",
            LaunchAchievementID.franchisePlayer: "AchievementFranchisePlayerIcon",
            LaunchAchievementID.overcharged: "AchievementOverchargedIcon",
            LaunchAchievementID.deepThreat: "AchievementDeepThreatIcon",
            LaunchAchievementID.untouchable: "AchievementUntouchableIcon",
            LaunchAchievementID.maximumOverdrive:
                "AchievementMaximumOverdriveIcon",
        ]

        XCTAssertEqual(
            Dictionary(
                uniqueKeysWithValues: AchievementCatalog.launch.map {
                    ($0.id, achievementIconName($0.id))
                }
            ),
            expected
        )
        XCTAssertEqual(
            achievementIconName(AchievementID("achievement.unknown.v1")),
            "MenuAchievementIcon"
        )
    }

    func testCoinPackPresentationMatchesApprovedLaunchSurface() {
        XCTAssertEqual(
            EconomyConfiguration.coinPacks.map(\.coins),
            [750, 2_500, 6_000, 11_000]
        )
        XCTAssertEqual(
            EconomyConfiguration.coinPacks.map {
                AppPresentation.proposedUSPriceText($0.proposedUSPrice)
            },
            ["$0.99", "$2.99", "$5.99", "$9.99"]
        )
        XCTAssertEqual(AppPresentation.coinText(11_000), "11,000")
    }

    @MainActor
    private func capture(_ view: AnyView, size: CGSize, name: String) {
        let host = UIHostingController(rootView: view)
        host.view.frame = CGRect(origin: .zero, size: size)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        XCTAssertEqual(image.size, size)
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func achievementFinalRowsEvidenceView(
        coordinator: AppCoordinator,
        horizontalSizeClass: UserInterfaceSizeClass,
        verticalSizeClass: UserInterfaceSizeClass
    ) -> AnyView {
        let cards = AppPresentation.achievements(
            progress: coordinator.state.achievementProgress
        )
        let summary = AppPresentation.achievementSummary(cards: cards)

        return AnyView(
            ZStack {
                PocketVectorBackdrop()
                ChampionshipSubmenuScreen(
                    title: "Achievements",
                    subtitle: achievementOverviewSubtitle,
                    onBack: {}
                ) {
                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            SummaryStat(
                                title: "COMPLETE",
                                value: "\(summary.completedCount) / \(summary.totalCount)"
                            )
                            SummaryStat(
                                title: "POINTS",
                                value: "\(summary.earnedPoints) / \(summary.totalPoints)"
                            )
                        }
                        .padding(.horizontal)

                        VStack(spacing: 12) {
                            ForEach(cards.suffix(2)) { card in
                                AchievementRow(card: card, action: {})
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 14)
                    }
                }
            }
            .dynamicTypeSize(.large)
            .environment(\.horizontalSizeClass, horizontalSizeClass)
            .environment(\.verticalSizeClass, verticalSizeClass)
        )
    }

    @MainActor
    private func captureScrolledToBottom(
        _ view: AnyView,
        size: CGSize,
        name: String
    ) async {
        let host = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = host
        window.isHidden = false
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        host.view.frame = CGRect(origin: .zero, size: size)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        for _ in 0 ..< 4 {
            await Task.yield()
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
        }

        guard let scrollView = descendantScrollViews(in: host.view)
            .max(by: { $0.contentSize.height < $1.contentSize.height }) else {
            return XCTFail("Expected the hosted layout to be scrollable")
        }
        let bottomOffset = max(
            -scrollView.adjustedContentInset.top,
            scrollView.contentSize.height
                - scrollView.bounds.height
                + scrollView.adjustedContentInset.bottom
        )
        XCTAssertGreaterThan(bottomOffset, 0)
        scrollView.setContentOffset(CGPoint(x: 0, y: bottomOffset), animated: false)
        scrollView.layoutIfNeeded()
        host.view.layoutIfNeeded()
        let settledBottomOffset = max(
            -scrollView.adjustedContentInset.top,
            scrollView.contentSize.height
                - scrollView.bounds.height
                + scrollView.adjustedContentInset.bottom
        )
        scrollView.setContentOffset(
            CGPoint(x: 0, y: settledBottomOffset),
            animated: false
        )
        scrollView.layoutIfNeeded()

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        XCTAssertEqual(image.size, size)
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func descendantScrollViews(in view: UIView) -> [UIScrollView] {
        let nested = view.subviews.flatMap(descendantScrollViews)
        guard let scrollView = view as? UIScrollView else { return nested }
        return [scrollView] + nested
    }

    @MainActor
    private func waitForGameplayView(
        in rootView: UIView,
        runID: RunID
    ) async throws -> SKView {
        let deadline = ProcessInfo.processInfo.systemUptime + 8
        while ProcessInfo.processInfo.systemUptime < deadline {
            try await Task.sleep(for: .milliseconds(10))
            rootView.setNeedsLayout()
            rootView.layoutIfNeeded()
            if let gameplayView = descendantGameplayViews(in: rootView).first(where: {
                guard let scene = $0.scene as? GameScene else { return false }
                return scene.configuration.runID == runID
            }), let scene = gameplayView.scene as? GameScene,
               scene.visualReadiness == .ready {
                return gameplayView
            }
        }
        XCTFail("The hosted gameplay scene did not reach the required presentation state")
        throw NSError(
            domain: "AppPresentationTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Gameplay presentation timed out"]
        )
    }

    @MainActor
    private func descendantGameplayViews(in view: UIView) -> [SKView] {
        let nested = view.subviews.flatMap(descendantGameplayViews)
        guard let gameplayView = view as? SKView else { return nested }
        return [gameplayView] + nested
    }

    @MainActor
    private func waitForGameplayViewsToUnmount(in rootView: UIView) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        while ProcessInfo.processInfo.systemUptime < deadline {
            try await Task.sleep(for: .milliseconds(20))
            rootView.setNeedsLayout()
            rootView.layoutIfNeeded()
            if descendantGameplayViews(in: rootView).isEmpty { return }
        }
        XCTFail("Expected the gameplay renderer to unmount after leaving the run")
        throw NSError(
            domain: "AppPresentationTests",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Gameplay renderer did not unmount"]
        )
    }

    @MainActor
    private func isDescendant(_ view: UIView?, of ancestor: UIView) -> Bool {
        var candidate = view
        while let current = candidate {
            if current === ancestor { return true }
            candidate = current.superview
        }
        return false
    }

    @MainActor
    private func makeFrozenGameplayFrame(
        configuration: RunConfiguration
    ) async throws -> UIImage {
        let sceneSize = GameProjection.sceneSize
        let scene = GameScene(
            size: sceneSize,
            configuration: configuration,
            settings: PlayerSettings(),
            onCompletedRun: { _ in }
        )
        scene.scaleMode = .aspectFit

        let view = SKView(frame: CGRect(origin: .zero, size: sceneSize))
        view.ignoresSiblingOrder = true
        view.presentScene(scene)

        let deadline = ProcessInfo.processInfo.systemUptime + 8
        while scene.visualReadiness == .preparing,
              ProcessInfo.processInfo.systemUptime < deadline {
            await Task.yield()
        }
        XCTAssertEqual(scene.visualReadiness, .ready)

        view.isPaused = true
        for tick in 0 ... 750 {
            scene.update(TimeInterval(tick) * 0.1)
        }
        XCTAssertFalse(scene.currentSnapshot.defersBottomSystemGestures)
        XCTAssertTrue(
            try XCTUnwrap(scene.childNode(withName: "//broadcastHUD")).isHidden,
            "The renderer must naturally suppress its gameplay HUD before Results is captured"
        )
        scene.isPaused = true

        let texture = try XCTUnwrap(view.texture(from: scene))
        let image = UIImage(cgImage: texture.cgImage())
        view.presentScene(nil)
        return image
    }

    private func makeRunResultsPresentation() throws -> RunResultsPresentation {
        let catalog = LaunchCatalog.approved
        let offense = try XCTUnwrap(catalog.team(id: LaunchTeamID.novaCityComets))
        let defense = try XCTUnwrap(catalog.team(id: LaunchTeamID.highMesaHelions))
        let configuration = RunConfiguration(
            runID: RunID(),
            randomSeed: 29,
            offenseTeamID: offense.id,
            offenseJerseyID: offense.primaryJersey.id,
            defenseTeamID: defense.id,
            defenseJerseyID: defense.primaryJersey.id,
            footballID: LaunchFootballID.standard,
            economyVersion: EconomyConfiguration.currentVersion,
            startedAt: Date(timeIntervalSince1970: 1)
        )
        let completedRun = CompletedRun(
            configuration: configuration,
            endedAt: Date(timeIntervalSince1970: 61),
            elapsedGameplayMilliseconds: 60_000,
            finishReason: .timerExpired,
            score: 12_500,
            statistics: RunStatisticsSnapshot(
                attempts: 14,
                completions: 7,
                touchdowns: 3,
                incompletions: 3,
                interceptions: 1,
                longestTouchdownStreak: 2
            ),
            completedLaneIDs: [],
            bonusTouchdownCount: 1
        )
        return RunResultsPresentation(
            completedRun: completedRun,
            completionCoins: 10,
            performanceCoins: 12,
            accuracyCoins: 5,
            signingBonusCoins: 250,
            totalEarnedCoins: 277,
            pendingCoins: 0,
            gameplayRewardState: .recorded,
            signingBonusState: .recorded,
            personalBest: 12_500,
            isNewPersonalBest: true,
            rewardedAdOffer: .progress(validRuns: 2, requiredRuns: 5)
        )
    }

    private func gameplaySnapshot(phase: GamePhase) -> GameplaySceneSnapshot {
        var state = GameState()
        state.phase = phase
        return GameplaySceneSnapshot(state: state)
    }
}

@MainActor
private final class RecordingRootViewController: PocketVectorRootViewController {
    private(set) var screenEdgeUpdateRequestCount = 0

    override func requestSystemUIUpdate() {
        screenEdgeUpdateRequestCount += 1
        super.requestSystemUIUpdate()
    }
}

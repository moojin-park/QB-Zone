import GameKit
import UIKit
import XCTest

@testable import PocketVector

@MainActor
final class UIKitGameKitPresentationHandoffTests: XCTestCase {
    func testWindowTrackingAnchorAttachesAndDetachesOnceWithZeroLayout() {
        let anchor = GameKitPresentationAnchorViewController()
        var attachments = 0
        var detachments = 0
        anchor.onAttach = { attached in
            XCTAssertTrue(attached === anchor)
            attachments += 1
        }
        anchor.onDetach = { detached in
            XCTAssertTrue(detached === anchor)
            detachments += 1
        }

        let harness = WindowHarness(anchor: anchor)
        XCTAssertEqual(attachments, 1)
        XCTAssertEqual(detachments, 0)
        XCTAssertEqual(anchor.preferredContentSize, .zero)
        XCTAssertFalse(anchor.view.isUserInteractionEnabled)
        XCTAssertTrue(anchor.view.window === harness.window)

        harness.close()
        XCTAssertEqual(attachments, 1)
        XCTAssertEqual(detachments, 1)
        harness.close()
        XCTAssertEqual(detachments, 1)
    }

    func testUnavailableAnchorDeclinesAuthenticationAndThrowsTypedUnavailable() async {
        let driver = PresentationDriver()
        let handoff = UIKitGameKitPresentationHandoff(operations: driver.operations)
        let detachedAnchor = UIViewController()
        detachedAnchor.loadViewIfNeeded()
        handoff.attach(anchor: detachedAnchor)

        let authentication = await handoff.presentGameKitAuthentication(UIViewController())
        XCTAssertEqual(authentication, .declined)

        do {
            try await handoff.presentGameKit(makeGameCenterController())
            XCTFail("A handoff without a window-backed anchor must fail closed")
        } catch {
            XCTAssertEqual(error as? UIKitGameKitPresentationError, .unavailable)
        }
        XCTAssertEqual(driver.presentationCalls.count, 0)
    }

    func testGameCenterDelegateDismissesBeforeResumingExactlyOnce() async {
        let driver = PresentationDriver()
        let handoff = UIKitGameKitPresentationHandoff(operations: driver.operations)
        let harness = WindowHarness()
        defer { harness.close() }
        handoff.attach(anchor: harness.anchor)

        let controller = makeGameCenterController()
        let probe = GameCenterTaskProbe()
        let task = observePresentation(controller, through: handoff, probe: probe)

        await waitUntil { driver.presentationCalls.count == 1 }
        XCTAssertTrue(driver.presentationCalls[0].presenter === harness.root)
        XCTAssertTrue(driver.presentationCalls[0].presented === controller)
        XCTAssertTrue(driver.presentationCalls[0].gameCenterDelegateWasSet)
        driver.acceptNextPresentation()

        handoff.gameCenterViewControllerDidFinish(controller)
        handoff.gameCenterViewControllerDidFinish(controller)
        XCTAssertEqual(driver.presentationCalls.count, 1)
        XCTAssertEqual(driver.dismissalCalls.count, 1)
        await yieldSeveralTimes()
        XCTAssertTrue(probe.outcomes.isEmpty, "Dismissal must complete before continuation resume")

        driver.completeNextDismissal()
        await task.value
        XCTAssertEqual(probe.outcomes, [.success])

        handoff.gameCenterViewControllerDidFinish(controller)
        XCTAssertEqual(driver.dismissalCalls.count, 1)
        XCTAssertEqual(probe.outcomes, [.success])
    }

    func testBusyRequestsFailClosedAndDetachResumesLifecycleEndedAfterDismissal() async {
        let driver = PresentationDriver()
        let handoff = UIKitGameKitPresentationHandoff(operations: driver.operations)
        let harness = WindowHarness()
        defer { harness.close() }
        handoff.attach(anchor: harness.anchor)

        let controller = makeGameCenterController()
        let probe = GameCenterTaskProbe()
        let task = observePresentation(controller, through: handoff, probe: probe)
        await waitUntil { driver.presentationCalls.count == 1 }
        driver.acceptNextPresentation()

        do {
            try await handoff.presentGameKit(makeGameCenterController())
            XCTFail("A second Game Center presentation must not start")
        } catch {
            XCTAssertEqual(
                error as? UIKitGameKitPresentationError,
                .presentationInProgress
            )
        }
        let busyAuthentication = await handoff.presentGameKitAuthentication(UIViewController())
        XCTAssertEqual(busyAuthentication, .declined)
        XCTAssertEqual(driver.presentationCalls.count, 1)

        handoff.detach(anchor: harness.anchor)
        handoff.detach(anchor: harness.anchor)
        handoff.gameCenterViewControllerDidFinish(controller)
        XCTAssertEqual(driver.dismissalCalls.count, 1)
        await yieldSeveralTimes()
        XCTAssertTrue(probe.outcomes.isEmpty, "Lifecycle failure waits for dismissal")

        driver.completeNextDismissal()
        await task.value
        XCTAssertEqual(probe.outcomes, [.failure(.lifecycleEnded)])
        XCTAssertEqual(driver.dismissalCalls.count, 1)
    }

    func testCurrentDetachOverridesPendingDelegateSuccessWithoutDoubleResume() async {
        let driver = PresentationDriver()
        let handoff = UIKitGameKitPresentationHandoff(operations: driver.operations)
        let harness = WindowHarness()
        defer { harness.close() }
        handoff.attach(anchor: harness.anchor)

        let controller = makeGameCenterController()
        let probe = GameCenterTaskProbe()
        let task = observePresentation(controller, through: handoff, probe: probe)
        await waitUntil { driver.presentationCalls.count == 1 }
        driver.acceptNextPresentation()

        handoff.gameCenterViewControllerDidFinish(controller)
        XCTAssertEqual(driver.dismissalCalls.count, 1)
        handoff.detach(anchor: harness.anchor)
        handoff.gameCenterViewControllerDidFinish(controller)
        XCTAssertEqual(driver.dismissalCalls.count, 1)

        driver.completeNextDismissal()
        await task.value
        XCTAssertEqual(probe.outcomes, [.failure(.lifecycleEnded)])
        await yieldSeveralTimes()
        XCTAssertEqual(probe.outcomes.count, 1)
    }

    func testDetachDuringPresentationWaitsForDismissalAndReturnsLifecycleEnded() async {
        let driver = PresentationDriver()
        let handoff = UIKitGameKitPresentationHandoff(operations: driver.operations)
        let harness = WindowHarness()
        defer { harness.close() }
        handoff.attach(anchor: harness.anchor)

        let controller = makeGameCenterController()
        let probe = GameCenterTaskProbe()
        let task = observePresentation(controller, through: handoff, probe: probe)
        await waitUntil { driver.presentationCalls.count == 1 }

        handoff.detach(anchor: harness.anchor)
        handoff.detach(anchor: harness.anchor)
        XCTAssertEqual(
            driver.dismissalCalls.count,
            0,
            "A pending UIKit presentation cannot be dismissed before acceptance"
        )
        await yieldSeveralTimes()
        XCTAssertTrue(probe.outcomes.isEmpty)

        driver.acceptNextPresentation()
        XCTAssertTrue(driver.isTrackedAsPresented(controller))
        XCTAssertEqual(driver.dismissalCalls.count, 1)
        await yieldSeveralTimes()
        XCTAssertTrue(probe.outcomes.isEmpty)

        driver.completeNextDismissal()
        await task.value
        XCTAssertEqual(probe.outcomes, [.failure(.lifecycleEnded)])
        XCTAssertFalse(driver.isTrackedAsPresented(controller))

        handoff.gameCenterViewControllerDidFinish(controller)
        await yieldSeveralTimes()
        XCTAssertEqual(driver.dismissalCalls.count, 1)
        XCTAssertEqual(probe.outcomes, [.failure(.lifecycleEnded)])
    }

    func testAuthenticationDetachDuringPresentationWaitsForAcceptanceAndCompletesOnce() async {
        let driver = PresentationDriver()
        let handoff = UIKitGameKitPresentationHandoff(operations: driver.operations)
        let harness = WindowHarness()
        defer { harness.close() }
        handoff.attach(anchor: harness.anchor)

        let controller = UIViewController()
        let probe = AuthenticationTaskProbe()
        let task = Task { @MainActor in
            probe.outcomes.append(
                await handoff.presentGameKitAuthentication(controller)
            )
        }
        await waitUntil { driver.presentationCalls.count == 1 }

        handoff.detach(anchor: harness.anchor)
        handoff.detach(anchor: harness.anchor)
        XCTAssertEqual(driver.dismissalCalls.count, 0)
        await yieldSeveralTimes()
        XCTAssertTrue(probe.outcomes.isEmpty)

        driver.acceptNextPresentation()
        XCTAssertTrue(driver.isTrackedAsPresented(controller))
        XCTAssertEqual(driver.dismissalCalls.count, 1)
        await yieldSeveralTimes()
        XCTAssertTrue(probe.outcomes.isEmpty, "Decline waits for accepted controller dismissal")

        driver.completeNextDismissal()
        await task.value
        XCTAssertEqual(probe.outcomes, [.declined])
        XCTAssertFalse(driver.isTrackedAsPresented(controller))

        await yieldSeveralTimes()
        XCTAssertEqual(driver.dismissalCalls.count, 1)
        XCTAssertEqual(probe.outcomes, [.declined])
    }

    func testDetachDuringRejectedPresentationsCompletesDirectlyWithoutDismissal() async {
        let driver = PresentationDriver()
        let handoff = UIKitGameKitPresentationHandoff(operations: driver.operations)
        let harness = WindowHarness()
        defer { harness.close() }
        handoff.attach(anchor: harness.anchor)

        let authenticationProbe = AuthenticationTaskProbe()
        let authenticationTask = Task { @MainActor in
            authenticationProbe.outcomes.append(
                await handoff.presentGameKitAuthentication(UIViewController())
            )
        }
        await waitUntil { driver.presentationCalls.count == 1 }
        handoff.detach(anchor: harness.anchor)
        driver.rejectNextPresentation()
        await authenticationTask.value
        XCTAssertEqual(authenticationProbe.outcomes, [.declined])
        XCTAssertEqual(driver.dismissalCalls.count, 0)

        handoff.attach(anchor: harness.anchor)
        let gameCenterController = makeGameCenterController()
        let gameCenterProbe = GameCenterTaskProbe()
        let gameCenterTask = observePresentation(
            gameCenterController,
            through: handoff,
            probe: gameCenterProbe
        )
        await waitUntil { driver.presentationCalls.count == 2 }
        handoff.detach(anchor: harness.anchor)
        driver.rejectNextPresentation()
        await gameCenterTask.value
        XCTAssertEqual(gameCenterProbe.outcomes, [.failure(.lifecycleEnded)])
        XCTAssertEqual(driver.dismissalCalls.count, 0)
    }

    func testStaleDetachKeepsReplacementAnchorAndUsesItsPresentedChain() async {
        let driver = PresentationDriver()
        let handoff = UIKitGameKitPresentationHandoff(operations: driver.operations)
        let firstHarness = WindowHarness()
        let replacementHarness = WindowHarness()
        defer {
            firstHarness.close()
            replacementHarness.close()
        }

        let overlay = UIViewController()
        await present(overlay, from: replacementHarness.root)
        XCTAssertTrue(overlay.view.window === replacementHarness.window)

        handoff.attach(anchor: firstHarness.anchor)
        handoff.attach(anchor: replacementHarness.anchor)
        handoff.detach(anchor: firstHarness.anchor)

        let authenticationController = UIViewController()
        let task = Task { @MainActor in
            await handoff.presentGameKitAuthentication(authenticationController)
        }
        await waitUntil { driver.presentationCalls.count == 1 }
        XCTAssertTrue(driver.presentationCalls[0].presenter === overlay)
        driver.acceptNextPresentation()
        let authentication = await task.value
        XCTAssertEqual(authentication, .presented)

        handoff.detach(anchor: replacementHarness.anchor)
        XCTAssertEqual(driver.dismissalCalls.count, 1)
        driver.completeNextDismissal()
    }

    func testRejectedUIKitPresentationsFailClosedWithoutDismissal() async {
        let driver = PresentationDriver()
        let handoff = UIKitGameKitPresentationHandoff(operations: driver.operations)
        let harness = WindowHarness()
        defer { harness.close() }
        handoff.attach(anchor: harness.anchor)

        let authenticationTask = Task { @MainActor in
            await handoff.presentGameKitAuthentication(UIViewController())
        }
        await waitUntil { driver.presentationCalls.count == 1 }
        driver.rejectNextPresentation()
        let authentication = await authenticationTask.value
        XCTAssertEqual(authentication, .declined)

        let controller = makeGameCenterController()
        let probe = GameCenterTaskProbe()
        let gameCenterTask = observePresentation(controller, through: handoff, probe: probe)
        await waitUntil { driver.presentationCalls.count == 2 }
        driver.rejectNextPresentation()
        await gameCenterTask.value

        XCTAssertEqual(probe.outcomes, [.failure(.unavailable)])
        XCTAssertEqual(driver.dismissalCalls.count, 0)
    }

    private func observePresentation(
        _ controller: GKGameCenterViewController,
        through handoff: UIKitGameKitPresentationHandoff,
        probe: GameCenterTaskProbe
    ) -> Task<Void, Never> {
        Task { @MainActor in
            do {
                try await handoff.presentGameKit(controller)
                probe.outcomes.append(.success)
            } catch let error as UIKitGameKitPresentationError {
                probe.outcomes.append(.failure(error))
            } catch {
                XCTFail("Unexpected presentation error: \(error)")
            }
        }
    }

    private func makeGameCenterController() -> GKGameCenterViewController {
        GKGameCenterViewController(state: .dashboard)
    }

    private func present(
        _ viewController: UIViewController,
        from presenter: UIViewController
    ) async {
        await withCheckedContinuation { continuation in
            presenter.present(viewController, animated: false) {
                continuation.resume()
            }
        }
    }

    private func waitUntil(
        _ condition: @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0 ..< 200 where !condition() {
            await Task.yield()
        }
        XCTAssertTrue(condition(), "Condition did not become true", file: file, line: line)
    }

    private func yieldSeveralTimes() async {
        for _ in 0 ..< 5 {
            await Task.yield()
        }
    }
}

@MainActor
private final class WindowHarness {
    let window: UIWindow
    let root: UIViewController
    let anchor: UIViewController
    private var isClosed = false

    init(anchor: UIViewController = UIViewController()) {
        self.anchor = anchor
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 844, height: 390))
        root = UIViewController()
        root.view.backgroundColor = .black
        window.rootViewController = root
        window.makeKeyAndVisible()
        root.view.layoutIfNeeded()

        root.addChild(anchor)
        anchor.view.frame = .zero
        root.view.addSubview(anchor.view)
        anchor.didMove(toParent: root)
        root.view.layoutIfNeeded()
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        root.dismiss(animated: false)
        anchor.willMove(toParent: nil)
        anchor.view.removeFromSuperview()
        anchor.removeFromParent()
        window.isHidden = true
        window.rootViewController = nil
    }
}

private enum GameCenterTaskOutcome: Equatable {
    case success
    case failure(UIKitGameKitPresentationError)
}

@MainActor
private final class GameCenterTaskProbe {
    var outcomes: [GameCenterTaskOutcome] = []
}

@MainActor
private final class AuthenticationTaskProbe {
    var outcomes: [GameKitAuthenticationPresentationDisposition] = []
}

@MainActor
private final class PresentationDriver {
    struct PresentationCall {
        let presenter: UIViewController
        let presented: UIViewController
        let gameCenterDelegateWasSet: Bool
    }

    struct DismissalCall {
        let presented: UIViewController
    }

    private struct PendingPresentation {
        let presented: UIViewController
        let completion: UIKitGameKitPresentationOperations.PresentationCompletion
    }

    private struct PendingDismissal {
        let presented: UIViewController
        let completion: UIKitGameKitPresentationOperations.DismissalCompletion
    }

    private var pendingPresentations: [PendingPresentation] = []
    private var pendingDismissals: [PendingDismissal] = []
    private var presentedControllerIDs = Set<ObjectIdentifier>()
    private(set) var presentationCalls: [PresentationCall] = []
    private(set) var dismissalCalls: [DismissalCall] = []

    lazy var operations = UIKitGameKitPresentationOperations(
        present: { [weak self] presenter, presented, completion in
            guard let self else {
                completion(false)
                return
            }
            presentationCalls.append(
                PresentationCall(
                    presenter: presenter,
                    presented: presented,
                    gameCenterDelegateWasSet: (
                        presented as? GKGameCenterViewController
                    )?.gameCenterDelegate != nil
                )
            )
            pendingPresentations.append(
                PendingPresentation(presented: presented, completion: completion)
            )
        },
        dismiss: { [weak self] presented, completion in
            guard let self else {
                completion()
                return
            }
            dismissalCalls.append(DismissalCall(presented: presented))
            guard presentedControllerIDs.contains(ObjectIdentifier(presented)) else {
                // Mirrors the live seam: dismissing a controller that UIKit has
                // not accepted completes immediately and cannot prevent a later
                // presentation callback from putting it onscreen.
                completion()
                return
            }
            pendingDismissals.append(
                PendingDismissal(presented: presented, completion: completion)
            )
        },
        isPresented: { [weak self] viewController in
            self?.presentedControllerIDs.contains(ObjectIdentifier(viewController)) == true
        }
    )

    func acceptNextPresentation() {
        let pending = pendingPresentations.removeFirst()
        presentedControllerIDs.insert(ObjectIdentifier(pending.presented))
        pending.completion(true)
    }

    func rejectNextPresentation() {
        pendingPresentations.removeFirst().completion(false)
    }

    func completeNextDismissal() {
        let pending = pendingDismissals.removeFirst()
        presentedControllerIDs.remove(ObjectIdentifier(pending.presented))
        pending.completion()
    }

    func isTrackedAsPresented(_ viewController: UIViewController) -> Bool {
        presentedControllerIDs.contains(ObjectIdentifier(viewController))
    }
}

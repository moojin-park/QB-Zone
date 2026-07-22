@preconcurrency import GameKit
import SwiftUI
import UIKit

enum UIKitGameKitPresentationError: Error, Equatable, Sendable {
    case unavailable
    case presentationInProgress
    case lifecycleEnded
}

@MainActor
struct UIKitGameKitPresentationOperations {
    typealias PresentationCompletion = (Bool) -> Void
    typealias DismissalCompletion = () -> Void

    let present: (
        _ presenter: UIViewController,
        _ presented: UIViewController,
        _ completion: @escaping PresentationCompletion
    ) -> Void
    let dismiss: (
        _ presented: UIViewController,
        _ completion: @escaping DismissalCompletion
    ) -> Void
    let isPresented: (_ viewController: UIViewController) -> Bool

    static let live = UIKitGameKitPresentationOperations(
        present: { presenter, presented, completion in
            presenter.present(presented, animated: true) {
                completion(
                    presenter.presentedViewController === presented
                        || presented.presentingViewController === presenter
                )
            }
        },
        dismiss: { presented, completion in
            guard presented.presentingViewController != nil
                    || presented.viewIfLoaded?.window != nil else {
                completion()
                return
            }
            presented.dismiss(animated: true, completion: completion)
        },
        isPresented: { viewController in
            viewController.presentingViewController != nil
                || viewController.viewIfLoaded?.window != nil
        }
    )
}

/// Owns the one UIKit presentation lane used by GameKit. The SwiftUI anchor is
/// the only source of a window; this type never guesses at an application-wide
/// key window or scans `UIApplication` scenes.
@MainActor
final class UIKitGameKitPresentationHandoff: NSObject, GameKitPresentationHandoff,
    @MainActor GKGameCenterControllerDelegate
{
    private enum SessionKind: Equatable {
        case authentication
        case gameCenter
    }

    private final class PresentationSession {
        let kind: SessionKind
        let viewController: UIViewController
        var authenticationContinuation:
            CheckedContinuation<GameKitAuthenticationPresentationDisposition, Never>?
        var gameCenterContinuation: CheckedContinuation<Void, any Error>?
        var pendingAuthenticationDisposition: GameKitAuthenticationPresentationDisposition?
        var pendingGameCenterResult: Result<Void, UIKitGameKitPresentationError>?
        var presentationResolved = false
        var presentationAccepted = false
        var dismissalRequested = false
        var dismissalStarted = false

        init(
            viewController: UIViewController,
            authenticationContinuation:
                CheckedContinuation<GameKitAuthenticationPresentationDisposition, Never>
        ) {
            kind = .authentication
            self.viewController = viewController
            self.authenticationContinuation = authenticationContinuation
        }

        init(
            viewController: GKGameCenterViewController,
            gameCenterContinuation: CheckedContinuation<Void, any Error>
        ) {
            kind = .gameCenter
            self.viewController = viewController
            self.gameCenterContinuation = gameCenterContinuation
        }

        func resumeAuthentication(
            returning disposition: GameKitAuthenticationPresentationDisposition
        ) {
            guard let continuation = authenticationContinuation else { return }
            authenticationContinuation = nil
            continuation.resume(returning: disposition)
        }

        func resumeGameCenter(returning result: Result<Void, UIKitGameKitPresentationError>) {
            guard let continuation = gameCenterContinuation else { return }
            gameCenterContinuation = nil
            switch result {
            case .success:
                continuation.resume(returning: ())
            case let .failure(error):
                continuation.resume(throwing: error)
            }
        }
    }

    private let operations: UIKitGameKitPresentationOperations
    private weak var anchorViewController: UIViewController?
    private var activeSession: PresentationSession?
    private var applicationIsActive = false

    override convenience init() {
        self.init(operations: .live)
    }

    init(operations: UIKitGameKitPresentationOperations) {
        self.operations = operations
        super.init()
    }

    /// Accepts only a controller whose view is already attached to a real
    /// window. A newer anchor replaces an older one atomically.
    func attach(anchor viewController: UIViewController) {
        guard viewController.viewIfLoaded?.window != nil else { return }
        anchorViewController = viewController
    }

    /// Identity checking makes a dismantle callback from an old SwiftUI
    /// representable harmless after its replacement has already attached.
    func detach(anchor viewController: UIViewController) {
        guard anchorViewController === viewController else { return }
        anchorViewController = nil

        guard let session = activeSession else { return }
        switch session.kind {
        case .authentication:
            if session.authenticationContinuation != nil {
                session.pendingAuthenticationDisposition = .declined
            }
        case .gameCenter:
            if session.gameCenterContinuation != nil {
                session.pendingGameCenterResult = .failure(.lifecycleEnded)
            }
        }
        requestDismissal(of: session)
    }

    /// Scene activation is an explicit presentation prerequisite. The anchor
    /// may remain attached while UIKit backgrounds its scene, so attachment
    /// alone is not sufficient authority to show GameKit UI.
    func setApplicationActive(_ isActive: Bool) {
        applicationIsActive = isActive
        guard !isActive, let session = activeSession else { return }
        switch session.kind {
        case .authentication:
            if session.authenticationContinuation != nil {
                session.pendingAuthenticationDisposition = .declined
            }
        case .gameCenter:
            if session.gameCenterContinuation != nil {
                session.pendingGameCenterResult = .failure(.lifecycleEnded)
            }
        }
        requestDismissal(of: session)
    }

    func presentGameKitAuthentication(
        _ viewController: UIViewController
    ) async -> GameKitAuthenticationPresentationDisposition {
        reapDismissedAuthenticationSession()
        guard activeSession == nil,
              isAvailableForPresentation(viewController),
              let presenter = resolvedPresenter() else {
            return .declined
        }

        return await withCheckedContinuation { continuation in
            let session = PresentationSession(
                viewController: viewController,
                authenticationContinuation: continuation
            )
            activeSession = session
            operations.present(presenter, viewController) { [weak self, weak session] accepted in
                guard let self, let session, self.activeSession === session else { return }
                guard !session.presentationResolved else { return }
                session.presentationResolved = true
                session.presentationAccepted = accepted

                if session.dismissalRequested {
                    if accepted {
                        self.startDismissalIfReady(of: session)
                    } else {
                        self.finishRejectedPresentation(of: session)
                    }
                    return
                }

                guard accepted, self.anchorViewController != nil else {
                    self.activeSession = nil
                    session.resumeAuthentication(returning: .declined)
                    return
                }
                session.resumeAuthentication(returning: .presented)
                // Authentication has no dismissal delegate. Retain the session
                // while its controller is actually presented and reap it before
                // the next request once UIKit has removed it.
            }
        }
    }

    func presentGameKit(
        _ viewController: GKGameCenterViewController
    ) async throws {
        reapDismissedAuthenticationSession()
        guard activeSession == nil else {
            throw UIKitGameKitPresentationError.presentationInProgress
        }
        guard isAvailableForPresentation(viewController),
              let presenter = resolvedPresenter() else {
            throw UIKitGameKitPresentationError.unavailable
        }

        viewController.gameCenterDelegate = self
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, any Error>) in
            let session = PresentationSession(
                viewController: viewController,
                gameCenterContinuation: continuation
            )
            activeSession = session
            operations.present(presenter, viewController) { [weak self, weak session] accepted in
                guard let self, let session, self.activeSession === session else { return }
                guard !session.presentationResolved else { return }
                session.presentationResolved = true
                session.presentationAccepted = accepted

                if session.dismissalRequested {
                    if accepted {
                        self.startDismissalIfReady(of: session)
                    } else {
                        self.finishRejectedPresentation(of: session)
                    }
                    return
                }

                guard accepted, self.anchorViewController != nil else {
                    self.activeSession = nil
                    session.resumeGameCenter(returning: .failure(.unavailable))
                    return
                }
            }
        }
    }

    func gameCenterViewControllerDidFinish(
        _ gameCenterViewController: GKGameCenterViewController
    ) {
        guard let session = activeSession,
              session.kind == .gameCenter,
              session.viewController === gameCenterViewController,
              session.gameCenterContinuation != nil,
              session.pendingGameCenterResult == nil else {
            return
        }

        session.pendingGameCenterResult = .success(())
        requestDismissal(of: session)
    }

    private func isAvailableForPresentation(_ viewController: UIViewController) -> Bool {
        viewController.presentingViewController == nil
            && viewController.parent == nil
            && viewController.viewIfLoaded?.window == nil
            && !viewController.isBeingDismissed
            && !viewController.isBeingPresented
    }

    private func resolvedPresenter() -> UIViewController? {
        guard applicationIsActive,
              let anchorViewController,
              let window = anchorViewController.viewIfLoaded?.window,
              let rootViewController = window.rootViewController else {
            return nil
        }

        var presenter = rootViewController
        var visited = Set<ObjectIdentifier>()
        while let presented = presenter.presentedViewController {
            guard visited.insert(ObjectIdentifier(presenter)).inserted else {
                return nil
            }
            presenter = presented
        }

        guard presenter.viewIfLoaded?.window === window,
              presenter.presentedViewController == nil,
              !presenter.isBeingDismissed,
              !presenter.isBeingPresented else {
            return nil
        }
        return presenter
    }

    private func reapDismissedAuthenticationSession() {
        guard let session = activeSession,
              session.kind == .authentication,
              session.authenticationContinuation == nil,
              !session.dismissalRequested,
              !operations.isPresented(session.viewController) else {
            return
        }
        activeSession = nil
    }

    private func requestDismissal(of session: PresentationSession) {
        session.dismissalRequested = true
        startDismissalIfReady(of: session)
    }

    /// UIKit can report a presentation asynchronously. A lifecycle teardown
    /// during that interval records its terminal result, but must not ask UIKit
    /// to dismiss a controller that has not been accepted yet: the live dismiss
    /// seam would complete immediately and a later presentation completion
    /// could otherwise leave an orphaned GameKit controller onscreen.
    private func startDismissalIfReady(of session: PresentationSession) {
        guard activeSession === session,
              session.dismissalRequested,
              session.presentationResolved,
              session.presentationAccepted,
              !session.dismissalStarted else {
            return
        }
        session.dismissalStarted = true
        operations.dismiss(session.viewController) { [weak self, weak session] in
            guard let self, let session, self.activeSession === session else { return }
            self.finishPendingOutcome(of: session)
        }
    }

    private func finishRejectedPresentation(of session: PresentationSession) {
        guard activeSession === session else { return }

        switch session.kind {
        case .authentication:
            if session.pendingAuthenticationDisposition == nil {
                session.pendingAuthenticationDisposition = .declined
            }
        case .gameCenter:
            // A lifecycle failure recorded by detach has precedence. A finish
            // callback before UIKit acceptance cannot turn a rejected
            // presentation into success.
            if case .failure(.lifecycleEnded)? = session.pendingGameCenterResult {
                break
            }
            session.pendingGameCenterResult = .failure(.unavailable)
        }

        finishPendingOutcome(of: session)
    }

    private func finishPendingOutcome(of session: PresentationSession) {
        guard activeSession === session else { return }
        activeSession = nil
        if let disposition = session.pendingAuthenticationDisposition {
            session.pendingAuthenticationDisposition = nil
            session.resumeAuthentication(returning: disposition)
        }
        if let result = session.pendingGameCenterResult {
            session.pendingGameCenterResult = nil
            session.resumeGameCenter(returning: result)
        }
    }
}

/// A zero-layout, noninteractive SwiftUI bridge that gives the handoff one
/// concrete view-controller identity and its actual window lifecycle.
@MainActor
struct GameKitPresentationAnchor: UIViewControllerRepresentable {
    final class Coordinator {
        weak var handoff: UIKitGameKitPresentationHandoff?

        init(handoff: UIKitGameKitPresentationHandoff) {
            self.handoff = handoff
        }
    }

    let handoff: UIKitGameKitPresentationHandoff

    func makeCoordinator() -> Coordinator {
        Coordinator(handoff: handoff)
    }

    func makeUIViewController(context: Context) -> GameKitPresentationAnchorViewController {
        let viewController = GameKitPresentationAnchorViewController()
        configure(viewController, coordinator: context.coordinator)
        return viewController
    }

    func updateUIViewController(
        _ uiViewController: GameKitPresentationAnchorViewController,
        context: Context
    ) {
        if context.coordinator.handoff !== handoff {
            context.coordinator.handoff?.detach(anchor: uiViewController)
            context.coordinator.handoff = handoff
        }
        configure(uiViewController, coordinator: context.coordinator)
        if uiViewController.viewIfLoaded?.window != nil {
            handoff.attach(anchor: uiViewController)
        }
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiViewController: GameKitPresentationAnchorViewController,
        context: Context
    ) -> CGSize? {
        .zero
    }

    static func dismantleUIViewController(
        _ uiViewController: GameKitPresentationAnchorViewController,
        coordinator: Coordinator
    ) {
        coordinator.handoff?.detach(anchor: uiViewController)
        uiViewController.onAttach = nil
        uiViewController.onDetach = nil
    }

    private func configure(
        _ viewController: GameKitPresentationAnchorViewController,
        coordinator: Coordinator
    ) {
        viewController.onAttach = { [weak coordinator] anchor in
            coordinator?.handoff?.attach(anchor: anchor)
        }
        viewController.onDetach = { [weak coordinator] anchor in
            coordinator?.handoff?.detach(anchor: anchor)
        }
    }
}

@MainActor
final class GameKitPresentationAnchorViewController: UIViewController {
    var onAttach: ((UIViewController) -> Void)?
    var onDetach: ((UIViewController) -> Void)?

    private weak var observedWindow: UIWindow?
    private var isWindowBacked = false

    override func loadView() {
        let trackingView = GameKitPresentationWindowTrackingView()
        trackingView.backgroundColor = .clear
        trackingView.isUserInteractionEnabled = false
        trackingView.windowDidChange = { [weak self] window in
            self?.windowDidChange(to: window)
        }
        view = trackingView
        preferredContentSize = .zero
    }

    private func windowDidChange(to window: UIWindow?) {
        if let window {
            if isWindowBacked, observedWindow !== window {
                isWindowBacked = false
                observedWindow = nil
                onDetach?(self)
            }
            guard !isWindowBacked else { return }
            observedWindow = window
            isWindowBacked = true
            onAttach?(self)
        } else if isWindowBacked {
            isWindowBacked = false
            observedWindow = nil
            onDetach?(self)
        }
    }
}

@MainActor
private final class GameKitPresentationWindowTrackingView: UIView {
    var windowDidChange: ((UIWindow?) -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        windowDidChange?(window)
    }
}

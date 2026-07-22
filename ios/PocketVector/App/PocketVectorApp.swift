import SwiftUI
import UIKit

@MainActor
@main
final class PocketVectorApp: UIResponder, UIApplicationDelegate {
    private var runtime: ProductionAppRuntime?
    private var systemGestureDeferralState: RootSystemGestureDeferralState?
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let runtime = ProductionAppRuntime.live()
        runtime.startCoordinator()
        runtime.startAppleDiagnostics()
        self.runtime = runtime
        systemGestureDeferralState = RootSystemGestureDeferralState()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sceneWillConnect(_:)),
            name: UIScene.willConnectNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sceneDidActivate(_:)),
            name: UIScene.didActivateNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sceneDidEnterBackground(_:)),
            name: UIScene.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sceneDidDisconnect(_:)),
            name: UIScene.didDisconnectNotification,
            object: nil
        )
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: "Pocket Vector",
            sessionRole: connectingSceneSession.role
        )
        configuration.delegateClass = PocketVectorSceneDelegate.self
        return configuration
    }

    func installRootWindow(in windowScene: UIWindowScene) {
        if window?.windowScene === windowScene,
           window?.rootViewController is PocketVectorRootViewController {
            return
        }
        guard let runtime, let systemGestureDeferralState else { return }

        let rootView = PocketVectorRootView(
            runtime: runtime,
            systemGestureDeferralState: systemGestureDeferralState
        )
        let rootController = PocketVectorRootViewController(
            rootView: AnyView(rootView)
        )
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = rootController
        window.makeKeyAndVisible()
        self.window = window
    }

    @objc private func sceneWillConnect(_ notification: Notification) {
        guard let windowScene = notification.object as? UIWindowScene else { return }
        installRootWindow(in: windowScene)
    }

    @objc private func sceneDidActivate(_ notification: Notification) {
        guard let windowScene = notification.object as? UIWindowScene else { return }
        installRootWindow(in: windowScene)
        systemGestureDeferralState?.setApplicationActive(true)
        if window?.windowScene === windowScene,
           let rootController = window?.rootViewController as? PocketVectorRootViewController {
            rootController.requestSystemUIUpdate()
        }
    }

    @objc private func sceneDidEnterBackground(_ notification: Notification) {
        systemGestureDeferralState?.setApplicationActive(false)
    }

    @objc private func sceneDidDisconnect(_ notification: Notification) {
        systemGestureDeferralState?.setApplicationActive(false)
        window?.isHidden = true
        window = nil
    }
}

@MainActor
final class PocketVectorSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        guard let appDelegate = UIApplication.shared.delegate as? PocketVectorApp else {
            return
        }
        appDelegate.installRootWindow(in: windowScene)
        window = windowScene.windows.first(where: { $0.isKeyWindow })
    }
}

@MainActor
struct PocketVectorRootView: View {
    let runtime: ProductionAppRuntime
    let systemGestureDeferralState: RootSystemGestureDeferralState

    var body: some View {
        AppShellView(
            coordinator: runtime.coordinator,
            onRetryBootstrap: { runtime.startCoordinator() }
        )
        .environment(\.rootSystemGestureDeferralState, systemGestureDeferralState)
        .background {
            GameKitPresentationAnchor(
                handoff: runtime.presentationHandoff
            )
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
        .onChange(of: allowedGameplayRunID, initial: true) { _, runID in
            systemGestureDeferralState.setAllowedGameplayRunID(runID)
        }
    }

    private var allowedGameplayRunID: RunID? {
        RootSystemGestureDeferralPresentationPolicy.allowedGameplayRunID(
            bootstrapState: runtime.coordinator.bootstrapState,
            destination: runtime.coordinator.currentDestination,
            isSettling: runtime.coordinator.isRunSettlementInFlight,
            settlementErrorMessage: runtime.coordinator.settlementErrorMessage
        )
    }
}

enum RootSystemGestureDeferralPresentationPolicy {
    static func allowedGameplayRunID(
        bootstrapState: AppBootstrapState,
        destination: AppDestination,
        isSettling: Bool,
        settlementErrorMessage: String?
    ) -> RunID? {
        guard bootstrapState == .ready,
              !isSettling,
              settlementErrorMessage == nil,
              case let .gameplay(configuration) = destination else {
            return nil
        }
        return configuration.runID
    }
}

@MainActor
class PocketVectorRootViewController: UIViewController, UIGestureRecognizerDelegate {
    private let contentController: UIHostingController<AnyView>
    private(set) lazy var bottomSystemGestureDeferralRecognizer: UIPanGestureRecognizer = {
        let recognizer = UIPanGestureRecognizer(
            target: self,
            action: #selector(handleBottomSystemGestureDeferralPan(_:))
        )
        recognizer.maximumNumberOfTouches = 1
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        recognizer.delegate = self
        return recognizer
    }()

    init(rootView: AnyView) {
        contentController = UIHostingController(rootView: rootView)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(contentController)
        contentController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentController.view)
        NSLayoutConstraint.activate([
            contentController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentController.view.topAnchor.constraint(equalTo: view.topAnchor),
            contentController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        contentController.didMove(toParent: self)
        view.addGestureRecognizer(bottomSystemGestureDeferralRecognizer)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        requestSystemUIUpdate()
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        requestSystemUIUpdate()
    }

    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge {
        // Pocket Vector is a landscape, full-screen game. The owner-approved
        // policy deliberately requires the two-swipe Home gesture everywhere
        // in the app, independent of scene lifecycle or gameplay snapshots.
        .bottom
    }

    override var childForScreenEdgesDeferringSystemGestures: UIViewController? {
        nil
    }

    override var prefersStatusBarHidden: Bool { true }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    // Keep the Home indicator under UIKit's normal visible policy. Physical
    // Face ID testing proved that auto-hiding it lets one bottom-edge swipe
    // leave the app even while this root continues to defer the bottom edge.
    override var prefersHomeIndicatorAutoHidden: Bool { false }

    func requestSystemUIUpdate() {
        setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
        setNeedsStatusBarAppearanceUpdate()
        setNeedsUpdateOfHomeIndicatorAutoHidden()
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        gestureRecognizer === bottomSystemGestureDeferralRecognizer
            || otherGestureRecognizer === bottomSystemGestureDeferralRecognizer
    }

    @objc
    private func handleBottomSystemGestureDeferralPan(
        _ recognizer: UIPanGestureRecognizer
    ) {}
}

@MainActor
final class RootSystemGestureDeferralState {
    var onEffectiveDeferralChanged: (() -> Void)?

    private(set) var allowedGameplayRunID: RunID?
    private(set) var requestingGameplayRunID: RunID?
    private(set) var gameplaySnapshotRequestsDeferral = false
    private(set) var isApplicationActive = false

    var defersBottomSystemGestures: Bool {
        isApplicationActive
            && allowedGameplayRunID != nil
            && allowedGameplayRunID == requestingGameplayRunID
            && gameplaySnapshotRequestsDeferral
    }

    func setAllowedGameplayRunID(_ runID: RunID?) {
        updateEffectiveDeferral {
            allowedGameplayRunID = runID
        }
    }

    func receive(
        _ snapshot: GameplaySceneSnapshot,
        for runID: RunID,
        freezesPresentation: Bool
    ) {
        updateEffectiveDeferral {
            requestingGameplayRunID = runID
            gameplaySnapshotRequestsDeferral = !freezesPresentation
                && snapshot.defersBottomSystemGestures
        }
    }

    func clearGameplayRequest(for runID: RunID) {
        guard requestingGameplayRunID == runID else { return }
        updateEffectiveDeferral {
            requestingGameplayRunID = nil
            gameplaySnapshotRequestsDeferral = false
        }
    }

    func setApplicationActive(_ isActive: Bool) {
        updateEffectiveDeferral {
            isApplicationActive = isActive
        }
    }

    private func updateEffectiveDeferral(_ update: () -> Void) {
        let previouslyDeferred = defersBottomSystemGestures
        update()
        guard previouslyDeferred != defersBottomSystemGestures else { return }
        onEffectiveDeferralChanged?()
    }
}

private struct RootSystemGestureDeferralStateKey: EnvironmentKey {
    static let defaultValue: RootSystemGestureDeferralState? = nil
}

extension EnvironmentValues {
    var rootSystemGestureDeferralState: RootSystemGestureDeferralState? {
        get { self[RootSystemGestureDeferralStateKey.self] }
        set { self[RootSystemGestureDeferralStateKey.self] = newValue }
    }
}

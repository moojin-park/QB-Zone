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
            selector: #selector(sceneWillDeactivate(_:)),
            name: UIScene.willDeactivateNotification,
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
           window?.rootViewController is PocketVectorRootHostingController {
            return
        }
        guard let runtime, let systemGestureDeferralState else { return }

        let rootView = PocketVectorRootView(
            runtime: runtime,
            systemGestureDeferralState: systemGestureDeferralState
        )
        let rootController = PocketVectorRootHostingController(
            rootView: AnyView(rootView),
            systemGestureDeferralState: systemGestureDeferralState
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
    }

    @objc private func sceneWillDeactivate(_ notification: Notification) {
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
class PocketVectorRootHostingController: UIHostingController<AnyView> {
    private let systemGestureDeferralState: RootSystemGestureDeferralState

    init(
        rootView: AnyView,
        systemGestureDeferralState: RootSystemGestureDeferralState
    ) {
        self.systemGestureDeferralState = systemGestureDeferralState
        super.init(rootView: rootView)
        systemGestureDeferralState.onEffectiveDeferralChanged = { [weak self] in
            self?.requestScreenEdgesDeferralUpdate()
        }
    }

    @available(*, unavailable)
    required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge {
        systemGestureDeferralState.defersBottomSystemGestures ? .bottom : []
    }

    func requestScreenEdgesDeferralUpdate() {
        setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
    }
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

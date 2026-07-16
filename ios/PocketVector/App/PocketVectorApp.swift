import SwiftUI

@MainActor
@main
struct PocketVectorApp: App {
    @State private var runtime: ProductionAppRuntime

    init() {
        let runtime = ProductionAppRuntime.live()
        runtime.startCoordinator()
        runtime.startAppleDiagnostics()
        _runtime = State(
            initialValue: runtime
        )
    }

    var body: some Scene {
        WindowGroup {
            AppShellView(
                coordinator: runtime.coordinator,
                onRetryBootstrap: { runtime.startCoordinator() }
            )
                .background {
                    GameKitPresentationAnchor(
                        handoff: runtime.presentationHandoff
                    )
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
                }
        }
    }
}

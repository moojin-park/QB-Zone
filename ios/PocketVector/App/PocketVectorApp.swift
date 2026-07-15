import SwiftUI

@MainActor
@main
struct PocketVectorApp: App {
    @State private var coordinator: AppCoordinator

    init() {
        _coordinator = State(initialValue: AppCoordinator())
    }

    var body: some Scene {
        WindowGroup {
            AppShellView(coordinator: coordinator)
        }
    }
}

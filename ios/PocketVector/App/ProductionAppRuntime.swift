import Foundation

/// Retains the complete process-scoped production graph and both long-lived
/// consumers. Their lifetimes follow the runtime rather than a transient view.
@MainActor
final class ProductionAppRuntime {
    let coordinator: AppCoordinator
    let presentationHandoff: UIKitGameKitPresentationHandoff
    let serviceConfiguration: ProductionServiceConfiguration
    let runtimeCapabilities: ProductionRuntimeCapabilities

    private let composition: ProductionAppComposition?
    private let authoritativeStateChannel: ProductionAuthoritativeStateChannel
    private let diagnostics: AppleDiagnosticsRuntime
    private var coordinatorTask: Task<Void, Never>?
    private var coordinatorTaskID: UUID?
    private var diagnosticsTask: Task<Void, Never>?

    init(
        coordinator: AppCoordinator,
        presentationHandoff: UIKitGameKitPresentationHandoff,
        serviceConfiguration: ProductionServiceConfiguration,
        runtimeCapabilities: ProductionRuntimeCapabilities,
        composition: ProductionAppComposition?,
        authoritativeStateChannel: ProductionAuthoritativeStateChannel,
        diagnostics: AppleDiagnosticsRuntime
    ) {
        self.coordinator = coordinator
        self.presentationHandoff = presentationHandoff
        self.serviceConfiguration = serviceConfiguration
        self.runtimeCapabilities = runtimeCapabilities
        self.composition = composition
        self.authoritativeStateChannel = authoritativeStateChannel
        self.diagnostics = diagnostics
        coordinatorTask = nil
        coordinatorTaskID = nil
        diagnosticsTask = nil
    }

    static func live(
        bundle: Bundle = .main,
        fileManager: FileManager = .default,
        userDefaults: UserDefaults = .standard
    ) -> ProductionAppRuntime {
        let serviceConfiguration = ProductionServiceConfiguration.from(bundle: bundle)
        let runtimeCapabilities = ProductionRuntimeCapabilities.appleDiagnosticsOnly
        let presentationHandoff = UIKitGameKitPresentationHandoff()
        let diagnostics = AppleDiagnosticsRuntime.live(
            subsystem: bundle.bundleIdentifier ?? "PocketVector"
        )
        let channel = ProductionAuthoritativeStateChannel()
        let privacySupportConfiguration = PrivacySupportConfiguration.from(
            bundle: bundle,
            services: runtimeCapabilities.serviceAvailability
        )

        guard let applicationSupportDirectoryURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            var environment = AppCoordinatorEnvironment.profileStorageUnavailable
            environment.privacySupportConfiguration = privacySupportConfiguration
            environment.diagnosticsSink = diagnostics.sink
            return ProductionAppRuntime(
                coordinator: AppCoordinator(environment: environment),
                presentationHandoff: presentationHandoff,
                serviceConfiguration: serviceConfiguration,
                runtimeCapabilities: runtimeCapabilities,
                composition: nil,
                authoritativeStateChannel: channel,
                diagnostics: diagnostics
            )
        }

        let deviceID = StableInstallationDeviceIdentifierStore(
            userDefaults: userDefaults
        ).identifier()
        let composition = ProductionAppComposition(
            dependencies: ProductionAppDependencies(
                applicationSupportDirectoryURL: applicationSupportDirectoryURL,
                accountIdentity: .local,
                deviceID: deviceID
            ),
            authoritativeStateChannel: channel,
            diagnosticsSink: diagnostics.sink
        )
        var environment = composition.environment
        environment.privacySupportConfiguration = privacySupportConfiguration

        return ProductionAppRuntime(
            coordinator: AppCoordinator(
                catalog: .approved,
                environment: environment
            ),
            presentationHandoff: presentationHandoff,
            serviceConfiguration: serviceConfiguration,
            runtimeCapabilities: runtimeCapabilities,
            composition: composition,
            authoritativeStateChannel: channel,
            diagnostics: diagnostics
        )
    }

    var coordinatorTaskIsRunning: Bool {
        coordinatorTask != nil
    }

    /// Starts the one process-scoped profile bootstrap/state consumer. A
    /// completed attempt clears its slot so the failure UI can explicitly
    /// retry without creating an unowned task or overlapping consumers.
    func startCoordinator() {
        guard coordinatorTask == nil else { return }
        let taskID = UUID()
        let coordinator = self.coordinator
        coordinatorTaskID = taskID
        coordinatorTask = Task { @MainActor [weak self] in
            await coordinator.run()
            self?.coordinatorTaskDidFinish(taskID)
        }
    }

    func startAppleDiagnostics() {
        guard diagnosticsTask == nil else { return }
        let diagnostics = self.diagnostics
        diagnosticsTask = Task {
            await diagnostics.run()
        }
    }

    deinit {
        coordinatorTask?.cancel()
        diagnosticsTask?.cancel()
    }

    private func coordinatorTaskDidFinish(_ taskID: UUID) {
        guard coordinatorTaskID == taskID else { return }
        coordinatorTask = nil
        coordinatorTaskID = nil
    }
}

import SwiftUI

@MainActor
struct AppShellView: View {
    @Bindable var coordinator: AppCoordinator
    let onRetryBootstrap: @MainActor () -> Void
    @Environment(\.accessibilityReduceMotion) private var systemReducedMotion

    var body: some View {
        ZStack(alignment: .topTrailing) {
            PocketVectorBackdrop()

            presentedDestination
                .transition(.opacity)
                .disabled(
                    coordinator.isRequestInFlight && !coordinator.isRunSettlementInFlight
                )

            if coordinator.isRequestInFlight && retainedRunPresentation?.isResultsPresented != true {
                ProgressView("Working")
                    .tint(PocketVectorTheme.cyan)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.82), in: Capsule())
                    .padding()
                    .accessibilityLabel("Request in progress")
            }
        }
        .animation(
            reducesMotion ? nil : .easeInOut(duration: 0.16),
            value: destinationIdentity
        )
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .alert(
            "Pocket Vector",
            isPresented: Binding(
                get: { coordinator.noticeMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        coordinator.dismissNotice()
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                coordinator.dismissNotice()
            }
        } message: {
            Text(coordinator.noticeMessage ?? "")
        }
    }

    @ViewBuilder
    private var presentedDestination: some View {
        if let retainedRunPresentation {
            RetainedRunSurface(
                presentation: retainedRunPresentation,
                settings: gameplaySettings,
                coordinator: coordinator
            )
            .id(retainedRunPresentation.sceneIdentity)
        } else {
            destinationView
                .id(destinationIdentity)
        }
    }

    @ViewBuilder
    private var destinationView: some View {
        switch coordinator.bootstrapState {
        case .loading:
            BootstrapLoadingView()
        case let .failed(message):
            BootstrapFailureView(
                message: message,
                onRetry: onRetryBootstrap
            )
        case .ready:
            switch coordinator.currentDestination {
            case .mainMenu:
                MainMenuView(coordinator: coordinator)
            case .teamSelection:
                TeamSelectionView(coordinator: coordinator)
            case .locker:
                LockerView(coordinator: coordinator)
            case .achievements:
                AchievementsView(coordinator: coordinator)
            case let .achievementDetail(achievementID):
                AchievementDetailView(
                    achievementID: achievementID,
                    coordinator: coordinator
                )
            case .coinStore:
                CoinStoreView(coordinator: coordinator)
            case .settings:
                SettingsView(coordinator: coordinator)
            case .tutorial:
                TutorialView(coordinator: coordinator)
            case .privacySupport:
                PrivacySupportView(coordinator: coordinator)
            case .gameplay, .runResults:
                EmptyView()
            }
        }
    }

    private var retainedRunPresentation: RetainedRunPresentation? {
        guard coordinator.bootstrapState == .ready else { return nil }
        return RetainedRunPresentation(destination: coordinator.currentDestination)
    }

    private var destinationIdentity: String {
        switch coordinator.bootstrapState {
        case .loading:
            return "bootstrap-loading"
        case let .failed(message):
            return "bootstrap-failed-\(message)"
        case .ready:
            break
        }

        switch coordinator.currentDestination {
        case .mainMenu: return "menu"
        case .teamSelection: return "teams"
        case .locker: return "locker"
        case .achievements: return "achievements"
        case let .achievementDetail(id): return "achievement-\(id.rawValue)"
        case .coinStore: return "coin-store"
        case .settings: return "settings"
        case let .tutorial(context):
            switch context {
            case .beforeRun: return "tutorial-before-run"
            case .review: return "tutorial-review"
            }
        case .privacySupport: return "privacy-support"
        case let .gameplay(configuration): return "gameplay-\(configuration.runID.description)"
        case let .runResults(results): return "results-\(results.completedRun.runID.description)"
        }
    }

    private var reducesMotion: Bool {
        systemReducedMotion || coordinator.state.settings.reducedMotion
    }

    private var gameplaySettings: PlayerSettings {
        let saved = coordinator.state.settings
        return PlayerSettings(
            musicVolume: saved.musicVolume,
            sfxVolume: saved.sfxVolume,
            isMuted: saved.isMuted,
            reducedMotion: systemReducedMotion || saved.reducedMotion,
            tutorialCompleted: saved.tutorialCompleted
        )
    }
}

struct RetainedRunPresentation: Equatable {
    let configuration: RunConfiguration
    let results: RunResultsPresentation?

    init?(destination: AppDestination) {
        switch destination {
        case let .gameplay(configuration):
            self.configuration = configuration
            results = nil
        case let .runResults(results):
            configuration = results.completedRun.configuration
            self.results = results
        default:
            return nil
        }
    }

    var sceneIdentity: RunID { configuration.runID }
    var isResultsPresented: Bool { results != nil }
    var freezesGameplay: Bool { isResultsPresented }
    var allowsGameplayInteraction: Bool { !isResultsPresented }
    var hidesGameplayFromAccessibility: Bool { isResultsPresented }
}

@MainActor
struct RetainedRunSurface: View {
    let presentation: RetainedRunPresentation
    let settings: PlayerSettings
    @Bindable var coordinator: AppCoordinator

    var body: some View {
        ZStack {
            LegacyGameplayAdapterView(
                configuration: presentation.configuration,
                settings: settings,
                isSettling: coordinator.isRunSettlementInFlight,
                settlementErrorMessage: coordinator.settlementErrorMessage,
                freezesPresentation: presentation.freezesGameplay,
                onCompletedRun: { completedRun in
                    Task { await coordinator.handleCompletedRun(completedRun) }
                },
                onRetrySettlement: {
                    Task { await coordinator.retryCompletedRunSettlement() }
                },
                onConfirmRestart: {
                    coordinator.prepareRestartRound(
                        presentation.configuration
                    )
                },
                onConfirmedRestartAbandonment: {
                    restartAbandonment in
                    _ = coordinator.retainConfirmedRestartAbandonment(
                        restartAbandonment
                    )
                }
            )
            .id(presentation.sceneIdentity)
            .allowsHitTesting(presentation.allowsGameplayInteraction)
            .accessibilityHidden(presentation.hidesGameplayFromAccessibility)

            if let results = presentation.results {
                RunResultsView(results: results, coordinator: coordinator)
                    .transition(.opacity)
            }
        }
    }
}

private struct BootstrapLoadingView: View {
    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
                .tint(PocketVectorTheme.cyan)
            Text("Loading Player Profile")
                .font(.title2.weight(.bold))
            Text("Preparing your teams, settings, scores, and unlocks.")
                .font(.subheadline)
                .foregroundStyle(PocketVectorTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .pocketVectorPanel()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading player profile")
    }
}

private struct BootstrapFailureView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(PocketVectorTheme.warning)
                .accessibilityHidden(true)
            Text("Profile Couldn’t Load")
                .font(.title2.weight(.bold))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(PocketVectorTheme.textSecondary)
                .multilineTextAlignment(.center)
            Button("Try Again", action: onRetry)
                .buttonStyle(PrimaryActionButtonStyle())
                .accessibilityHint("Retries loading the player profile")
        }
        .frame(maxWidth: 480)
        .padding(24)
        .pocketVectorPanel()
    }
}

import SwiftUI

@MainActor
struct AppShellView: View {
    @Bindable var coordinator: AppCoordinator
    let onRetryBootstrap: @MainActor () -> Void
    @Environment(\.accessibilityReduceMotion) private var systemReducedMotion

    var body: some View {
        ZStack(alignment: .topTrailing) {
            PocketVectorBackdrop()

            destinationView
                .id(destinationIdentity)
                .transition(.opacity)
                .disabled(
                    coordinator.isRequestInFlight && !coordinator.isRunSettlementInFlight
                )

            if coordinator.isRequestInFlight {
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
            case let .gameplay(configuration):
                LegacyGameplayAdapterView(
                    configuration: configuration,
                    settings: gameplaySettings,
                    isSettling: coordinator.isRunSettlementInFlight,
                    settlementErrorMessage: coordinator.settlementErrorMessage,
                    onCompletedRun: { completedRun in
                        Task { await coordinator.handleCompletedRun(completedRun) }
                    },
                    onRetrySettlement: {
                        Task { await coordinator.retryCompletedRunSettlement() }
                    }
                )
            case let .runResults(results):
                RunResultsView(results: results, coordinator: coordinator)
            }
        }
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

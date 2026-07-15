import SwiftUI

@MainActor
struct MainMenuView: View {
    @Bindable var coordinator: AppCoordinator

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: adaptiveSpacing(for: geometry.size)) {
                        hero
                            .frame(maxWidth: 430)
                        menu
                            .frame(maxWidth: 680)
                    }

                    VStack(spacing: 18) {
                        hero
                        menu
                    }
                }
                .frame(maxWidth: 1180)
                .padding(adaptivePadding(for: geometry.size))
                .frame(minHeight: geometry.size.height)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                if let team = coordinator.selectedTeam {
                    TeamMark(team: team, size: 72)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("POCKET VECTOR")
                        .font(.largeTitle.weight(.black))
                        .foregroundStyle(PocketVectorTheme.textPrimary)
                        .minimumScaleFactor(0.72)
                        .lineLimit(1)
                    Text("Read the field. Fire the pass.")
                        .font(.headline)
                        .foregroundStyle(PocketVectorTheme.cyan)
                }
            }

            Text("A fast arcade passing challenge built for one more run.")
                .font(.body)
                .foregroundStyle(PocketVectorTheme.textSecondary)

            HStack(spacing: 10) {
                BalanceBadge(
                    confirmedCoins: coordinator.state.confirmedCoins,
                    pendingCoins: coordinator.state.pendingCoins
                )

                VStack(alignment: .leading, spacing: 1) {
                    Text("PERSONAL BEST")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(PocketVectorTheme.textSecondary)
                    Text(coordinator.state.personalBest.formatted())
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(PocketVectorTheme.textPrimary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(PocketVectorTheme.raisedSurface, in: Capsule())
                .accessibilityElement(children: .combine)
            }

            Button {
                coordinator.showTeamSelection()
            } label: {
                Label("Play", systemImage: "play.fill")
            }
            .buttonStyle(PrimaryActionButtonStyle())
            .accessibilityHint("Choose an offense and start a run")
        }
        .padding(20)
        .pocketVectorPanel()
    }

    private var menu: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 230), spacing: 12)],
            spacing: 12
        ) {
            MenuTile(
                title: "Team & Locker",
                detail: "Choose uniforms and footballs",
                systemImage: "tshirt.fill",
                action: coordinator.showLocker
            )
            MenuTile(
                title: "Achievements",
                detail: "Track all eight launch challenges",
                systemImage: "trophy.fill",
                action: coordinator.showAchievements
            )
            MenuTile(
                title: "Leaderboard",
                detail: "Open the global high score board",
                systemImage: "chart.bar.fill",
                action: {
                    Task { await coordinator.requestLeaderboard() }
                }
            )
            MenuTile(
                title: "Coin Store",
                detail: "View available coin packs",
                systemImage: "circle.hexagongrid.fill",
                action: coordinator.showCoinStore
            )
            MenuTile(
                title: "Settings",
                detail: "Audio, motion, and tutorial controls",
                systemImage: "gearshape.fill",
                action: coordinator.showSettings
            )
        }
    }

    private func adaptivePadding(for size: CGSize) -> CGFloat {
        min(32, max(14, min(size.width, size.height) * 0.04))
    }

    private func adaptiveSpacing(for size: CGSize) -> CGFloat {
        min(36, max(16, size.width * 0.03))
    }
}

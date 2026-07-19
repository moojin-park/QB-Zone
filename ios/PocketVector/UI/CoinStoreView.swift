import SwiftUI

@MainActor
struct CoinStoreView: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @Bindable var coordinator: AppCoordinator

    private var expandedLayout: Bool {
        verticalSizeClass == .regular
    }

    var body: some View {
        ChampionshipSubmenuScreen(
            title: "Coin Store",
            subtitle: "Coins unlock teams and cosmetics. Gameplay can also earn coins.",
            onBack: coordinator.goBack,
            headerAccessory: {
                BalanceBadge(
                    confirmedCoins: coordinator.state.confirmedCoins,
                    pendingCoins: coordinator.state.pendingCoins
                )
            }
        ) {
            VStack(spacing: 12) {
                HStack {
                    StatusPill(text: syncLabel, color: syncColor)
                    Spacer()
                }
                .padding(.horizontal)

                ScrollView {
                    LazyVGrid(
                        columns: expandedLayout
                            ? [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]
                            : [GridItem(.adaptive(minimum: 220, maximum: 400), spacing: 12)],
                        spacing: expandedLayout ? 16 : 12
                    ) {
                        ForEach(EconomyConfiguration.coinPacks, id: \.id) { pack in
                            CoinPackCard(pack: pack, expanded: expandedLayout) {
                                Task { await coordinator.requestCoinPack(pack.id) }
                            }
                        }
                    }
                    .padding(.horizontal)

                    Text("Prices are proposed U.S. launch prices. The App Store purchase sheet must confirm the final localized price before any charge.")
                        .font(.caption)
                        .foregroundStyle(PocketVectorTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 720)
                        .padding()
                }
                .frame(maxHeight: expandedLayout ? 650 : .infinity)
            }
        }
    }

    private var syncLabel: String {
        switch coordinator.state.syncStatus {
        case .current: "Balance current"
        case .syncing: "Syncing"
        case .localOnly: "Local profile"
        case .unavailable: "Cloud unavailable"
        case .failed: "Sync needs attention"
        }
    }

    private var syncColor: Color {
        switch coordinator.state.syncStatus {
        case .current: PocketVectorTheme.success
        case .syncing: PocketVectorTheme.cyan
        case .localOnly, .unavailable, .failed: PocketVectorTheme.warning
        }
    }
}

private struct CoinPackCard: View {
    let pack: CoinPackDescriptor
    let expanded: Bool
    let action: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            CoinStack(expanded: expanded)

            VStack(spacing: 2) {
                Text(pack.displayName)
                    .font(.system(expanded ? .title2 : .title3, design: .monospaced, weight: .black))
                    .foregroundStyle(PocketVectorTheme.championshipGlacier)
                CoinAmount(amount: pack.coins, iconSize: 21)
            }

            Button(action: action) {
                Text(AppPresentation.proposedUSPriceText(pack.proposedUSPrice))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(ChampionshipPrimaryButtonStyle(compact: true))
            .accessibilityLabel("Buy \(pack.displayName), \(pack.coins) coins")
            .accessibilityValue(AppPresentation.proposedUSPriceText(pack.proposedUSPrice))
            .accessibilityHint("Requests the App Store purchase sheet")
        }
        .padding(expanded ? 22 : 16)
        .frame(maxWidth: .infinity, minHeight: expanded ? 248 : 190)
        .championshipPanel()
    }
}

private struct CoinStack: View {
    let expanded: Bool

    var body: some View {
        ZStack {
            coin(offset: CGSize(width: -19, height: 8), scale: 0.82)
            coin(offset: CGSize(width: 19, height: 8), scale: 0.82)
            coin(offset: CGSize(width: 0, height: -7), scale: 1)
        }
        .frame(width: expanded ? 116 : 92, height: expanded ? 76 : 58)
        .accessibilityHidden(true)
    }

    private func coin(offset: CGSize, scale: CGFloat) -> some View {
        Image("MenuCoinIcon")
            .resizable()
            .interpolation(.none)
            .scaledToFit()
            .frame(width: expanded ? 42 : 32, height: expanded ? 42 : 32)
            .scaleEffect(scale)
            .offset(offset)
    }
}

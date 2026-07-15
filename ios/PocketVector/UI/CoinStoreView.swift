import SwiftUI

@MainActor
struct CoinStoreView: View {
    @Bindable var coordinator: AppCoordinator

    var body: some View {
        PocketVectorScreen(
            title: "Coin Store",
            subtitle: "Coins unlock teams and cosmetics. Gameplay can also earn coins.",
            onBack: coordinator.goBack
        ) {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    BalanceBadge(
                        confirmedCoins: coordinator.state.confirmedCoins,
                        pendingCoins: coordinator.state.pendingCoins
                    )
                    StatusPill(text: syncLabel, color: syncColor)
                    Spacer()
                }
                .padding(.horizontal)

                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 220, maximum: 400), spacing: 12)],
                        spacing: 12
                    ) {
                        ForEach(EconomyConfiguration.coinPacks, id: \.id) { pack in
                            CoinPackCard(pack: pack) {
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
    let action: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "circle.hexagongrid.fill")
                .font(.largeTitle.weight(.black))
                .foregroundStyle(PocketVectorTheme.gold)
                .accessibilityHidden(true)

            VStack(spacing: 2) {
                Text(pack.displayName)
                    .font(.title2.weight(.black))
                Text("\(AppPresentation.coinText(pack.coins)) coins")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(PocketVectorTheme.cyan)
            }

            Button(action: action) {
                Text(AppPresentation.proposedUSPriceText(pack.proposedUSPrice))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryActionButtonStyle())
            .accessibilityLabel("Buy \(pack.displayName), \(pack.coins) coins")
            .accessibilityValue(AppPresentation.proposedUSPriceText(pack.proposedUSPrice))
            .accessibilityHint("Requests the App Store purchase sheet")
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 190)
        .pocketVectorPanel()
    }
}

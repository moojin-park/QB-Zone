import SwiftUI

@MainActor
struct RunResultsView: View {
    let results: RunResultsPresentation
    @Bindable var coordinator: AppCoordinator

    var body: some View {
        PocketVectorScreen(
            title: "Run Complete",
            subtitle: results.isNewPersonalBest ? "New personal best" : "Review the run, then go again.",
            showsBackButton: false,
            onBack: {}
        ) {
            GeometryReader { geometry in
                ScrollView {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 16) {
                            scorePanel
                            detailPanel
                        }
                        VStack(spacing: 16) {
                            scorePanel
                            detailPanel
                        }
                    }
                    .frame(maxWidth: 1040)
                    .padding(.horizontal)
                    .padding(.bottom, 16)
                    .frame(minHeight: geometry.size.height, alignment: .center)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var scorePanel: some View {
        VStack(spacing: 14) {
            if results.isNewPersonalBest {
                StatusPill(text: "New Best", color: PocketVectorTheme.gold)
            }
            Text("SCORE")
                .font(.caption.weight(.black))
                .tracking(1.4)
                .foregroundStyle(PocketVectorTheme.textSecondary)
            Text(results.score.formatted())
                .font(.system(.largeTitle, design: .rounded, weight: .black))
                .foregroundStyle(PocketVectorTheme.cyan)
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text("Personal best \(results.personalBest.formatted())")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(PocketVectorTheme.textSecondary)

            Divider()
                .overlay(PocketVectorTheme.border.opacity(0.5))

            HStack(spacing: 18) {
                ResultStat(title: "ATT", value: results.statistics.attempts)
                ResultStat(title: "COMP", value: results.statistics.successfulPasses)
                ResultStat(title: "TD", value: results.statistics.touchdowns)
                ResultStat(title: "ACC", valueText: "\(results.statistics.displayedAccuracyPercent)%")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 260)
        .pocketVectorPanel()
        .accessibilityElement(children: .combine)
    }

    private var detailPanel: some View {
        VStack(spacing: 12) {
            coinPanel
            rewardedAdPanel

            HStack(spacing: 12) {
                Button {
                    coordinator.returnToMainMenu()
                } label: {
                    Label("Home", systemImage: "house.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(PocketVectorTheme.cyan)

                Button {
                    coordinator.replayAfterResults()
                } label: {
                    Label("Play Again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .accessibilityHint("Starts another run with the same offense and equipment")
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var coinPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Run Coins", systemImage: "circle.hexagongrid.fill")
                .font(.headline.weight(.bold))
                .foregroundStyle(PocketVectorTheme.gold)

            HStack(alignment: .firstTextBaseline) {
                Text("+\(AppPresentation.coinText(results.earnedCoins))")
                    .font(.title.weight(.black).monospacedDigit())
                Spacer()
                if results.pendingCoins > 0 {
                    StatusPill(text: "Pending Sync", color: PocketVectorTheme.warning)
                } else {
                    StatusPill(text: "Recorded", color: PocketVectorTheme.success)
                }
            }

            if results.pendingCoins > 0 {
                Text("\(AppPresentation.coinText(results.pendingCoins)) earned coins are saved locally and waiting for durable cloud confirmation.")
                    .font(.caption)
                    .foregroundStyle(PocketVectorTheme.textSecondary)
            }
        }
        .padding(16)
        .pocketVectorPanel()
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var rewardedAdPanel: some View {
        switch results.rewardedAdOffer {
        case let .progress(validRuns, requiredRuns):
            VStack(alignment: .leading, spacing: 8) {
                Label("Rewarded Ad Bonus", systemImage: "play.rectangle.fill")
                    .font(.headline.weight(.bold))
                ProgressView(value: Double(validRuns), total: Double(max(1, requiredRuns)))
                    .tint(PocketVectorTheme.cyan)
                Text("\(validRuns) of \(requiredRuns) eligible runs")
                    .font(.caption)
                    .foregroundStyle(PocketVectorTheme.textSecondary)
            }
            .padding(16)
            .pocketVectorPanel()

        case let .eligible(offerID, rewardCoins, canPresent):
            VStack(alignment: .leading, spacing: 10) {
                Text("Optional Coin Bonus")
                    .font(.headline.weight(.bold))
                Text("Watch one rewarded ad for \(AppPresentation.coinText(rewardCoins)) coins.")
                    .font(.subheadline)
                    .foregroundStyle(PocketVectorTheme.textSecondary)
                Button {
                    Task { await coordinator.requestRewardedAd(offerID) }
                } label: {
                    Label("Watch for \(AppPresentation.coinText(rewardCoins)) Coins", systemImage: "play.fill")
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .disabled(!canPresent)
                .accessibilityHint("The reward is credited only after verified ad completion")
                if !canPresent {
                    Text("Connect to the service before loading the optional ad.")
                        .font(.caption)
                        .foregroundStyle(PocketVectorTheme.warning)
                }
            }
            .padding(16)
            .pocketVectorPanel()

        case .loading:
            RewardStatusPanel(title: "Loading optional ad", systemImage: "arrow.triangle.2.circlepath")
        case .verifying:
            RewardStatusPanel(title: "Verifying reward", systemImage: "checkmark.shield")
        case let .rewarded(coins):
            RewardStatusPanel(
                title: "+\(AppPresentation.coinText(coins)) coins rewarded",
                systemImage: "checkmark.circle.fill",
                color: PocketVectorTheme.success
            )
        case let .unavailable(message):
            VStack(alignment: .leading, spacing: 6) {
                Label("Optional ad unavailable", systemImage: "wifi.exclamationmark")
                    .font(.headline.weight(.bold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(PocketVectorTheme.textSecondary)
            }
            .padding(16)
            .pocketVectorPanel()
        }
    }
}

private struct ResultStat: View {
    let title: String
    let valueText: String

    init(title: String, value: Int) {
        self.title = title
        valueText = value.formatted()
    }

    init(title: String, valueText: String) {
        self.title = title
        self.valueText = valueText
    }

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption2.weight(.black))
                .foregroundStyle(PocketVectorTheme.textSecondary)
            Text(valueText)
                .font(.headline.weight(.black).monospacedDigit())
        }
    }
}

private struct RewardStatusPanel: View {
    let title: String
    let systemImage: String
    var color: Color = PocketVectorTheme.cyan

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.headline.weight(.bold))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .pocketVectorPanel()
            .accessibilityElement(children: .combine)
    }
}

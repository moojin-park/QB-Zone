import SwiftUI

@MainActor
struct RunResultsView: View {
    let results: RunResultsPresentation
    @Bindable var coordinator: AppCoordinator

    var body: some View {
        ChampionshipSubmenuScreen(
            title: "Run Complete",
            subtitle: results.isNewPersonalBest ? "NEW PERSONAL BEST" : "FINAL RUN SUMMARY",
            showsBackButton: false,
            onBack: {}
        ) {
            GeometryReader { geometry in
                let compact = geometry.size.height < 430
                let expanded = geometry.size.width / max(geometry.size.height, 1) < 1.65

                ScrollView {
                    HStack(alignment: .top, spacing: compact ? 10 : 16) {
                        scorePanel(compact: compact, expanded: expanded)
                            .frame(maxWidth: .infinity)

                        detailPanel(compact: compact, expanded: expanded)
                            .frame(maxWidth: expanded ? 520 : 430)
                    }
                    .frame(maxWidth: expanded ? 1_180 : 1_020)
                    .padding(.horizontal, compact ? 2 : 8)
                    .padding(.vertical, compact ? 2 : 8)
                    .frame(minHeight: geometry.size.height, alignment: .center)
                    .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
    }

    private func scorePanel(compact: Bool, expanded: Bool) -> some View {
        VStack(spacing: compact ? 6 : 10) {
            HStack {
                Text("FINAL SCORE")
                    .font(.system(
                        compact ? .caption : .subheadline,
                        design: .monospaced,
                        weight: .black
                    ))
                    .tracking(compact ? 1.2 : 2)
                    .foregroundStyle(PocketVectorTheme.championshipSilver)

                Spacer(minLength: 8)

                if results.isNewPersonalBest {
                    StatusPill(text: "New Best", color: PocketVectorTheme.gold)
                }
            }

            Text(results.score.formatted())
                .font(.system(
                    size: compact ? 56 : (expanded ? 96 : 72),
                    weight: .black,
                    design: .monospaced
                ))
                .tracking(compact ? -3 : -4)
                .foregroundStyle(PocketVectorTheme.championshipGlacier)
                .monospacedDigit()
                .minimumScaleFactor(0.52)
                .lineLimit(1)
                .shadow(color: .black.opacity(0.92), radius: 0, x: 3, y: 4)

            HStack(spacing: 7) {
                Text("PERSONAL BEST")
                    .foregroundStyle(PocketVectorTheme.championshipSilver)
                Text(results.personalBest.formatted())
                    .foregroundStyle(results.isNewPersonalBest ? PocketVectorTheme.gold : PocketVectorTheme.championshipGlacier)
            }
            .font(.system(
                compact ? .caption : .headline,
                design: .monospaced,
                weight: .black
            ).monospacedDigit())

            Divider()
                .overlay(PocketVectorTheme.championshipSilver.opacity(0.38))

            HStack(spacing: 0) {
                ResultStat(
                    title: "ATTEMPTS",
                    value: results.statistics.attempts,
                    compact: compact,
                    expanded: expanded
                )
                statDivider
                ResultStat(
                    title: "COMPLETIONS",
                    value: results.statistics.successfulPasses,
                    compact: compact,
                    expanded: expanded
                )
                statDivider
                ResultStat(
                    title: "ACCURACY",
                    valueText: "\(results.statistics.displayedAccuracyPercent)%",
                    compact: compact,
                    expanded: expanded
                )
                statDivider
                ResultStat(
                    title: "TOUCHDOWNS",
                    value: results.statistics.touchdowns,
                    compact: compact,
                    expanded: expanded
                )
            }
            .frame(maxWidth: .infinity)
        }
        .padding(compact ? 12 : (expanded ? 24 : 18))
        .frame(
            maxWidth: .infinity,
            minHeight: compact ? 260 : (expanded ? 480 : 330)
        )
        .championshipPanel(isSelected: results.isNewPersonalBest)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(results.isNewPersonalBest ? PocketVectorTheme.gold : PocketVectorTheme.championshipStatus)
                .frame(height: 3)
                .padding(.horizontal, 10)
                .padding(.top, 5)
        }
        .accessibilityElement(children: .combine)
    }

    private var statDivider: some View {
        Rectangle()
            .fill(PocketVectorTheme.championshipSteel.opacity(0.62))
            .frame(width: 1, height: 46)
            .accessibilityHidden(true)
    }

    private func detailPanel(compact: Bool, expanded: Bool) -> some View {
        VStack(spacing: compact ? 8 : 12) {
            coinPanel(compact: compact)
            rewardedAdPanel(compact: compact)

            HStack(spacing: compact ? 8 : 12) {
                Button {
                    coordinator.returnToMainMenu()
                } label: {
                    Text("MAIN MENU")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ChampionshipSecondaryButtonStyle())
                .accessibilityHint("Returns to the main menu")

                Button {
                    coordinator.replayAfterResults()
                } label: {
                    HStack(spacing: 7) {
                        ChampionshipPixelIcon(
                            name: "SubmenuPlayIcon",
                            size: compact ? 22 : 26
                        )
                        Text("PLAY AGAIN")
                    }
                }
                .buttonStyle(ChampionshipPrimaryButtonStyle(compact: true))
                .accessibilityHint("Starts another run with the same offense and equipment")
            }
        }
        .frame(minHeight: compact ? 260 : (expanded ? 480 : 330))
        .frame(maxWidth: .infinity)
    }

    private func coinPanel(compact: Bool) -> some View {
        HStack(spacing: compact ? 10 : 14) {
            Image("MenuCoinIcon")
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .frame(width: compact ? 38 : 48, height: compact ? 38 : 48)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text("RUN REWARD")
                    .font(.system(.caption2, design: .monospaced, weight: .black))
                    .tracking(0.8)
                    .foregroundStyle(PocketVectorTheme.championshipSilver)
                Text("+\(AppPresentation.coinText(results.earnedCoins))")
                    .font(.system(
                        compact ? .title2 : .title,
                        design: .monospaced,
                        weight: .black
                    ).monospacedDigit())
                    .foregroundStyle(PocketVectorTheme.gold)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 4) {
                if results.pendingCoins > 0 {
                    StatusPill(text: "Pending Sync", color: PocketVectorTheme.warning)
                } else {
                    StatusPill(text: "Recorded", color: PocketVectorTheme.success)
                }

                if results.pendingCoins > 0 {
                    Text("\(AppPresentation.coinText(results.pendingCoins)) LOCAL")
                        .font(.system(.caption2, design: .monospaced, weight: .bold).monospacedDigit())
                        .foregroundStyle(PocketVectorTheme.championshipSilver)
                }
            }
        }
        .padding(.horizontal, compact ? 12 : 16)
        .padding(.vertical, compact ? 8 : 12)
        .frame(maxWidth: .infinity, minHeight: compact ? 70 : 90)
        .championshipPanel()
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func rewardedAdPanel(compact: Bool) -> some View {
        switch results.rewardedAdOffer {
        case let .progress(validRuns, requiredRuns):
            VStack(alignment: .leading, spacing: compact ? 5 : 8) {
                rewardHeader("OPTIONAL BONUS")
                ProgressView(value: Double(validRuns), total: Double(max(1, requiredRuns)))
                    .tint(PocketVectorTheme.championshipStatus)
                Text("\(validRuns) OF \(requiredRuns) ELIGIBLE RUNS")
                    .font(.system(.caption2, design: .monospaced, weight: .bold).monospacedDigit())
                    .foregroundStyle(PocketVectorTheme.championshipSilver)
            }
            .rewardPanel(compact: compact)

        case let .eligible(offerID, rewardCoins, canPresent):
            VStack(alignment: .leading, spacing: compact ? 6 : 9) {
                rewardHeader("OPTIONAL BONUS")
                Button {
                    Task { await coordinator.requestRewardedAd(offerID) }
                } label: {
                    HStack(spacing: 7) {
                        ChampionshipPixelIcon(name: "SubmenuPlayIcon", size: compact ? 20 : 24)
                        Text("WATCH FOR")
                        CoinAmount(amount: rewardCoins, iconSize: compact ? 18 : 21)
                    }
                }
                .buttonStyle(ChampionshipSecondaryButtonStyle())
                .disabled(!canPresent)
                .accessibilityHint("The reward is credited only after verified ad completion")
                if !canPresent {
                    Text("Connect to the service before loading the optional ad.")
                        .font(.caption2)
                        .foregroundStyle(PocketVectorTheme.warning)
                }
            }
            .rewardPanel(compact: compact)

        case .loading:
            RewardStatusPanel(title: "LOADING OPTIONAL BONUS", color: PocketVectorTheme.championshipStatus, compact: compact)
        case .verifying:
            RewardStatusPanel(title: "VERIFYING REWARD", color: PocketVectorTheme.championshipStatus, compact: compact)
        case let .rewarded(coins):
            RewardStatusPanel(
                title: "+\(AppPresentation.coinText(coins)) REWARDED",
                color: PocketVectorTheme.success,
                compact: compact
            )
        case let .unavailable(message):
            VStack(alignment: .leading, spacing: compact ? 4 : 6) {
                rewardHeader("OPTIONAL BONUS UNAVAILABLE")
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(PocketVectorTheme.championshipSilver)
                    .lineLimit(compact ? 2 : 3)
            }
            .rewardPanel(compact: compact)
        }
    }

    private func rewardHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption, design: .monospaced, weight: .black))
            .tracking(0.7)
            .foregroundStyle(PocketVectorTheme.championshipGlacier)
    }
}

private struct ResultStat: View {
    let title: String
    let valueText: String
    let compact: Bool
    let expanded: Bool

    init(title: String, value: Int, compact: Bool, expanded: Bool) {
        self.title = title
        valueText = value.formatted()
        self.compact = compact
        self.expanded = expanded
    }

    init(title: String, valueText: String, compact: Bool, expanded: Bool) {
        self.title = title
        self.valueText = valueText
        self.compact = compact
        self.expanded = expanded
    }

    var body: some View {
        VStack(spacing: compact ? 2 : 4) {
            Text(title)
                .font(.system(
                    size: compact ? 8 : (expanded ? 12 : 10),
                    weight: .black,
                    design: .monospaced
                ))
                .minimumScaleFactor(0.62)
                .lineLimit(1)
                .foregroundStyle(PocketVectorTheme.championshipSilver)
            Text(valueText)
                .font(.system(
                    compact ? .headline : (expanded ? .title : .title2),
                    design: .monospaced,
                    weight: .black
                ).monospacedDigit())
                .foregroundStyle(PocketVectorTheme.championshipGlacier)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct RewardStatusPanel: View {
    let title: String
    let color: Color
    let compact: Bool

    var body: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
                .shadow(color: color.opacity(0.7), radius: 4)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(.caption, design: .monospaced, weight: .black))
                .foregroundStyle(PocketVectorTheme.championshipGlacier)
            Spacer(minLength: 0)
        }
            .rewardPanel(compact: compact)
            .accessibilityElement(children: .combine)
    }
}

private extension View {
    func rewardPanel(compact: Bool) -> some View {
        padding(.horizontal, compact ? 12 : 16)
            .padding(.vertical, compact ? 8 : 12)
            .frame(maxWidth: .infinity, minHeight: compact ? 72 : 96, alignment: .leading)
            .championshipPanel()
    }
}

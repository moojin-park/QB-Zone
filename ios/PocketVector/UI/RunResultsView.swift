import SwiftUI

@MainActor
struct RunResultsView: View {
    let results: RunResultsPresentation
    @Bindable var coordinator: AppCoordinator
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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

                if dynamicTypeSize.isAccessibilitySize {
                    accessibilityLayout(
                        compact: compact,
                        expanded: expanded,
                        availableWidth: geometry.size.width
                    )
                } else {
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
    }

    private func accessibilityLayout(
        compact: Bool,
        expanded: Bool,
        availableWidth: CGFloat
    ) -> some View {
        VStack(spacing: 6) {
            accessibleScoreSummaryPanel(compact: compact)
                .frame(maxWidth: expanded ? 760 : .infinity)
                .padding(.horizontal, compact ? 2 : 8)

            ScrollView {
                VStack(spacing: 10) {
                    accessibleStatsPanel(expanded: expanded)
                    coinPanel(compact: true, accessibleType: true)
                    rewardedAdPanel(compact: true, accessibleType: true)
                }
                .frame(maxWidth: expanded ? 760 : .infinity)
                .padding(.horizontal, compact ? 2 : 8)
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .clipped()

            resultsActions(
                compact: true,
                accessibleType: true,
                stacksVertically: availableWidth < 520
            )
                .padding(.horizontal, compact ? 2 : 8)
                .padding(.top, 4)
                .padding(.bottom, 2)
                .background(PocketVectorTheme.championshipVoid.opacity(0.98))
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(PocketVectorTheme.championshipSilver.opacity(0.38))
                        .frame(height: 1)
                }
        }
    }

    private func accessibleScoreSummaryPanel(compact: Bool) -> some View {
        Group {
            if compact {
                compactAccessibleScoreHeader
            } else {
                expandedAccessibleScoreHeader
            }
        }
        .padding(compact ? 10 : 14)
        .frame(maxWidth: .infinity)
        .championshipPanel(isSelected: results.isNewPersonalBest)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(
                    results.isNewPersonalBest ? PocketVectorTheme.gold : PocketVectorTheme.championshipStatus
                )
                .frame(height: 3)
                .padding(.horizontal, 10)
                .padding(.top, 5)
        }
        .accessibilityElement(children: .combine)
    }

    private func accessibleStatsPanel(expanded: Bool) -> some View {
        VStack(spacing: 8) {
            Text("RUN STATS")
                .font(.system(.caption2, design: .monospaced, weight: .black))
                .tracking(0.7)
                .foregroundStyle(PocketVectorTheme.championshipSilver)
                .frame(maxWidth: .infinity, alignment: .leading)

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 8),
                    count: expanded ? 4 : 2
                ),
                spacing: 8
            ) {
                AccessibleResultStat(title: "ATTEMPTS", value: results.statistics.attempts.formatted())
                AccessibleResultStat(
                    title: "COMPLETIONS", value: results.statistics.successfulPasses.formatted())
                AccessibleResultStat(
                    title: "ACCURACY", value: "\(results.statistics.displayedAccuracyPercent)%")
                AccessibleResultStat(title: "TOUCHDOWNS", value: results.statistics.touchdowns.formatted())
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .championshipPanel()
        .accessibilityElement(children: .combine)
    }

    private var compactAccessibleScoreHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("FINAL SCORE")
                    .font(.system(.caption2, design: .monospaced, weight: .black))
                    .fontWidth(.compressed)
                    .tracking(0.5)
                    .foregroundStyle(PocketVectorTheme.championshipSilver)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    accessibleScoreValue(size: 38)

                    if results.isNewPersonalBest {
                        newBestBadge
                    }
                }
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 2) {
                Text("PERSONAL BEST")
                    .font(.system(.caption2, design: .monospaced, weight: .black))
                    .fontWidth(.compressed)
                    .foregroundStyle(PocketVectorTheme.championshipSilver)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text(results.personalBest.formatted())
                    .font(.system(.headline, design: .monospaced, weight: .black).monospacedDigit())
                    .foregroundStyle(
                        results.isNewPersonalBest
                            ? PocketVectorTheme.gold
                            : PocketVectorTheme.championshipGlacier
                    )
            }
            .multilineTextAlignment(.trailing)
        }
    }

    private var expandedAccessibleScoreHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("FINAL SCORE")
                        .font(.system(.headline, design: .monospaced, weight: .black))
                        .tracking(0.8)
                        .foregroundStyle(PocketVectorTheme.championshipSilver)
                        .fixedSize(horizontal: false, vertical: true)

                    if results.isNewPersonalBest {
                        newBestBadge
                    }
                }

                accessibleScoreValue(size: 54)
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 3) {
                Text("PERSONAL BEST")
                    .font(.system(.caption, design: .monospaced, weight: .black))
                    .foregroundStyle(PocketVectorTheme.championshipSilver)
                Text(results.personalBest.formatted())
                    .font(.system(.title3, design: .monospaced, weight: .black).monospacedDigit())
                    .foregroundStyle(
                        results.isNewPersonalBest
                            ? PocketVectorTheme.gold
                            : PocketVectorTheme.championshipGlacier
                    )
            }
            .multilineTextAlignment(.trailing)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var newBestBadge: some View {
        Text("NEW BEST")
            .font(.system(size: 11, weight: .black, design: .monospaced))
            .foregroundStyle(.black)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(PocketVectorTheme.gold, in: Capsule())
            .fixedSize()
    }

    private func accessibleScoreValue(size: CGFloat) -> some View {
        Text(results.score.formatted())
            .font(.system(size: size, weight: .black, design: .monospaced))
            .tracking(size < 50 ? -2 : -3)
            .foregroundStyle(PocketVectorTheme.championshipGlacier)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .shadow(color: .black.opacity(0.92), radius: 0, x: 3, y: 4)
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
            coinPanel(compact: compact, accessibleType: false)
            rewardedAdPanel(compact: compact, accessibleType: false)
            resultsActions(compact: compact, accessibleType: false)
        }
        .frame(minHeight: compact ? 260 : (expanded ? 480 : 330))
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func resultsActions(
        compact: Bool,
        accessibleType: Bool,
        stacksVertically: Bool = false
    ) -> some View {
        let layout = stacksVertically
            ? AnyLayout(VStackLayout(spacing: 8))
            : AnyLayout(HStackLayout(spacing: compact ? 8 : 12))

        layout {
            Button {
                coordinator.returnToMainMenu()
            } label: {
                Text("MAIN MENU")
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(ChampionshipSecondaryButtonStyle(
                accessibilityCompact: accessibleType
            ))
            .accessibilityHint("Returns to the main menu")

            Button {
                coordinator.replayAfterResults()
            } label: {
                HStack(spacing: 7) {
                    if !accessibleType {
                        ChampionshipPixelIcon(
                            name: "SubmenuPlayIcon",
                            size: compact ? 22 : 26
                        )
                    }
                    Text("PLAY AGAIN")
                        .lineLimit(1)
                        .minimumScaleFactor(accessibleType ? 0.65 : 0.8)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(ChampionshipPrimaryButtonStyle(
                compact: true,
                accessibilityCompact: accessibleType
            ))
            .accessibilityHint("Starts another run with the same offense and equipment")
        }
    }

    @ViewBuilder
    private func coinPanel(compact: Bool, accessibleType: Bool) -> some View {
        let content = HStack(spacing: compact ? 10 : 14) {
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

        if accessibleType {
            content
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .championshipPanel()
                .accessibilityElement(children: .combine)
        } else {
            content
                .padding(.horizontal, compact ? 12 : 16)
                .padding(.vertical, compact ? 8 : 12)
                .frame(maxWidth: .infinity, minHeight: compact ? 70 : 90)
                .championshipPanel()
                .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private func rewardedAdPanel(compact: Bool, accessibleType: Bool) -> some View {
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
                        .font(accessibleType ? .body : .caption2)
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
                    .font(accessibleType ? .body : .caption2)
                    .foregroundStyle(PocketVectorTheme.championshipSilver)
                    .lineLimit(accessibleType ? nil : (compact ? 2 : 3))
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

private struct AccessibleResultStat: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(.caption, design: .monospaced, weight: .black))
                .foregroundStyle(PocketVectorTheme.championshipSilver)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(value)
                .font(.system(.title2, design: .monospaced, weight: .black).monospacedDigit())
                .foregroundStyle(PocketVectorTheme.championshipGlacier)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 72)
        .background(PocketVectorTheme.championshipVoid.opacity(0.54))
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .stroke(PocketVectorTheme.championshipSteel.opacity(0.65), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
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

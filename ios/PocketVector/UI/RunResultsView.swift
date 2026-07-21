import SwiftUI
import UIKit

@MainActor
struct RunResultsView: View {
    let results: RunResultsPresentation
    @Bindable var coordinator: AppCoordinator

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ResultsFieldBackdrop(configuration: results.completedRun.configuration)

                Color.black
                    .opacity(dynamicTypeSize.isAccessibilitySize ? 0.48 : 0.34)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                if dynamicTypeSize.isAccessibilitySize {
                    accessibilityLayout(availableSize: geometry.size)
                } else {
                    standardLayout(availableSize: geometry.size)
                }
            }
        }
        .foregroundStyle(PocketVectorTheme.championshipGlacier)
    }

    private func standardLayout(availableSize: CGSize) -> some View {
        let metrics = ResultsLayoutMetrics(size: availableSize)

        return VStack(spacing: metrics.sectionSpacing) {
            scoreMarquee(metrics: metrics)
                .frame(width: metrics.marqueeWidth, height: metrics.marqueeHeight)

            HStack(alignment: .top, spacing: 0) {
                statisticsWing(metrics: metrics)
                    .frame(width: metrics.wingWidth, height: metrics.wingHeight)

                Spacer(minLength: metrics.centerOpening)

                coinLedgerWing(metrics: metrics)
                    .frame(width: metrics.wingWidth, height: metrics.wingHeight)
            }
            .frame(maxWidth: metrics.maximumContentWidth)

            optionalBonusRail(metrics: metrics, accessibleType: false)
                .frame(width: metrics.bonusWidth)
                .frame(minHeight: metrics.bonusHeight)

            resultsActions(
                compact: metrics.compact,
                expanded: metrics.expanded,
                accessibleType: false
            )
                .frame(width: metrics.actionsWidth)
        }
        .padding(.horizontal, metrics.horizontalPadding)
        .padding(.vertical, metrics.verticalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func accessibilityLayout(availableSize: CGSize) -> some View {
        let expanded = availableSize.width / max(availableSize.height, 1) < 1.65

        return ScrollView {
            VStack(spacing: 12) {
                accessibleScoreMarquee
                accessibleStatisticsPanel
                accessibleCoinLedgerPanel
                optionalBonusRail(
                    metrics: ResultsLayoutMetrics(size: availableSize),
                    accessibleType: true
                )
                resultsActions(
                    compact: availableSize.height < 430,
                    expanded: false,
                    accessibleType: true,
                    stacksVertically: availableSize.width < 900
                )
            }
            .frame(maxWidth: expanded ? 820 : 760)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func scoreMarquee(metrics: ResultsLayoutMetrics) -> some View {
        Group {
            if metrics.compact {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("RUN COMPLETE")
                            .font(.system(size: 20, weight: .black, design: .monospaced))
                            .tracking(-1)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .shadow(color: .black.opacity(0.94), radius: 0, x: 2, y: 3)

                        Text("FINAL SCORE")
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                            .tracking(0.7)
                            .foregroundStyle(PocketVectorTheme.championshipStatus)
                    }

                    Spacer(minLength: 0)

                    Text(results.score.formatted())
                        .font(.system(size: 30, weight: .black, design: .monospaced))
                        .tracking(-2)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                        .shadow(color: .black.opacity(0.94), radius: 0, x: 3, y: 4)
                }
            } else {
                VStack(spacing: metrics.expanded ? 7 : 3) {
                    Text("RUN COMPLETE")
                        .font(.system(
                            size: metrics.expanded ? 52 : 29,
                            weight: .black,
                            design: .monospaced
                        ))
                        .tracking(-0.6)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .shadow(color: .black.opacity(0.94), radius: 0, x: 2, y: 3)

                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("FINAL SCORE")
                            .font(.system(
                                size: metrics.expanded ? 19 : 11,
                                weight: .black,
                                design: .monospaced
                            ))
                            .tracking(0.8)
                            .foregroundStyle(PocketVectorTheme.championshipStatus)

                        Text(results.score.formatted())
                            .font(.system(
                                size: metrics.expanded ? 78 : 36,
                                weight: .black,
                                design: .monospaced
                            ))
                            .tracking(-3)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.68)
                            .shadow(color: .black.opacity(0.94), radius: 0, x: 3, y: 4)
                    }
                }
            }
        }
        .padding(.horizontal, metrics.compact ? 22 : 30)
        .padding(.top, metrics.compact ? 11 : (metrics.expanded ? 20 : 14))
        .padding(.bottom, metrics.compact ? 8 : (metrics.expanded ? 12 : 10))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .resultsBroadcastPanel(emphasis: true, bezel: .marquee)
        .overlay(alignment: .bottom) {
            if results.isNewPersonalBest {
                Text("NEW BEST")
                    .font(.system(
                        size: metrics.expanded ? 13 : 9,
                        weight: .black,
                        design: .monospaced
                    ))
                    .tracking(0.5)
                    .foregroundStyle(.black)
                    .padding(.horizontal, metrics.expanded ? 12 : 8)
                    .padding(.vertical, metrics.expanded ? 4 : 2)
                    .background(PocketVectorTheme.gold, in: Capsule())
                    .offset(y: metrics.compact ? 6 : (metrics.expanded ? 9 : 7))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Run complete")
        .accessibilityValue(
            results.isNewPersonalBest
                ? "Final score \(results.score), new personal best"
                : "Final score \(results.score)"
        )
        .accessibilityAddTraits(.isHeader)
        .accessibilitySortPriority(10)
    }

    private var accessibleScoreMarquee: some View {
        VStack(spacing: 6) {
            Text("RUN COMPLETE")
                .font(.system(.title2, design: .monospaced, weight: .black))
                .multilineTextAlignment(.center)

            Text("FINAL SCORE")
                .font(.system(.headline, design: .monospaced, weight: .black))
                .foregroundStyle(PocketVectorTheme.championshipStatus)

            Text(results.score.formatted())
                .font(.system(.largeTitle, design: .monospaced, weight: .black).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.68)
                .shadow(color: .black.opacity(0.94), radius: 0, x: 3, y: 4)

            if results.isNewPersonalBest {
                Text("NEW PERSONAL BEST")
                    .font(.system(.headline, design: .monospaced, weight: .black))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(PocketVectorTheme.gold, in: Capsule())
            } else {
                Text("PERSONAL BEST \(results.personalBest.formatted())")
                    .font(.system(.headline, design: .monospaced, weight: .black))
                    .foregroundStyle(PocketVectorTheme.championshipSilver)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
        .resultsBroadcastPanel(emphasis: true, bezel: .marquee)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Run complete")
        .accessibilityValue(
            results.isNewPersonalBest
                ? "Final score \(results.score), new personal best"
                : "Final score \(results.score), personal best \(results.personalBest)"
        )
        .accessibilityAddTraits(.isHeader)
        .accessibilitySortPriority(10)
    }

    private func statisticsWing(metrics: ResultsLayoutMetrics) -> some View {
        VStack(spacing: 0) {
            resultStatRow(
                title: "ATTEMPTS",
                value: results.statistics.attempts.formatted(),
                iconName: "ResultsAttemptsIcon",
                metrics: metrics
            )
            resultDivider
            resultStatRow(
                title: "COMPLETIONS",
                value: results.statistics.successfulPasses.formatted(),
                iconName: "ResultsCompletionsIcon",
                metrics: metrics
            )
            resultDivider
            resultStatRow(
                title: "ACCURACY",
                value: "\(results.statistics.displayedAccuracyPercent)%",
                iconName: "ResultsAccuracyIcon",
                metrics: metrics
            )
            resultDivider
            resultStatRow(
                title: "TOUCHDOWNS",
                value: results.statistics.touchdowns.formatted(),
                iconName: "ResultsTouchdownIcon",
                metrics: metrics
            )
        }
        .padding(.horizontal, metrics.compact ? 18 : (metrics.expanded ? 26 : 20))
        .padding(.vertical, metrics.compact ? 13 : (metrics.expanded ? 24 : 16))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .resultsBroadcastPanel(bezel: .wing)
        .accessibilityElement(children: .contain)
    }

    private func resultStatRow(
        title: String,
        value: String,
        iconName: String,
        metrics: ResultsLayoutMetrics
    ) -> some View {
        HStack(spacing: metrics.expanded ? 16 : (metrics.compact ? 7 : 10)) {
            ChampionshipPixelIcon(
                name: iconName,
                size: metrics.expanded ? 54 : (metrics.compact ? 28 : 34)
            )

            VStack(alignment: .leading, spacing: metrics.expanded ? 4 : 0) {
                Text(title)
                    .font(.system(
                        size: metrics.expanded ? 19 : (metrics.compact ? 8 : 10),
                        weight: .black,
                        design: .monospaced
                    ))
                    .tracking(metrics.expanded ? 0.8 : 0.3)
                    .foregroundStyle(PocketVectorTheme.championshipSilver)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)

                Text(value)
                    .font(.system(
                        size: metrics.expanded ? 44 : (metrics.compact ? 19 : 24),
                        weight: .black,
                        design: .monospaced
                    ))
                    .monospacedDigit()
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title.capitalized)
        .accessibilityValue(value)
    }

    private var resultDivider: some View {
        Rectangle()
            .fill(PocketVectorTheme.championshipSilver.opacity(0.30))
            .frame(height: 1)
            .accessibilityHidden(true)
    }

    private var accessibleStatisticsPanel: some View {
        VStack(spacing: 10) {
            Text("RUN STATS")
                .font(.system(.headline, design: .monospaced, weight: .black))
                .frame(maxWidth: .infinity, alignment: .leading)

            LazyVGrid(columns: [GridItem(.flexible())], spacing: 8) {
                AccessibleResultStat(title: "ATTEMPTS", value: results.statistics.attempts.formatted())
                AccessibleResultStat(
                    title: "COMPLETIONS",
                    value: results.statistics.successfulPasses.formatted()
                )
                AccessibleResultStat(
                    title: "ACCURACY",
                    value: "\(results.statistics.displayedAccuracyPercent)%"
                )
                AccessibleResultStat(
                    title: "TOUCHDOWNS",
                    value: results.statistics.touchdowns.formatted()
                )
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .resultsBroadcastPanel(bezel: .wing)
    }

    private func coinLedgerWing(metrics: ResultsLayoutMetrics) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: metrics.compact ? 6 : 9) {
                Image("MenuCoinIcon")
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(
                        width: metrics.expanded ? 52 : (metrics.compact ? 27 : 34),
                        height: metrics.expanded ? 52 : (metrics.compact ? 27 : 34)
                    )
                    .accessibilityHidden(true)

                Text("COINS WON")
                    .font(.system(
                        size: metrics.expanded ? 22 : (metrics.compact ? 11 : 13),
                        weight: .black,
                        design: .monospaced
                    ))
                    .tracking(metrics.expanded ? 1.0 : 0.5)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if hasPendingSettlementCredit {
                    Text("PENDING")
                        .font(.system(
                            size: metrics.expanded ? 11 : 7,
                            weight: .black,
                            design: .monospaced
                        ))
                        .foregroundStyle(PocketVectorTheme.warning)
                }
            }
            .padding(.bottom, metrics.compact ? 4 : (metrics.expanded ? 12 : 7))

            resultDivider

            VStack(spacing: 0) {
                ForEach(coinLedger.lines) { line in
                    coinLedgerRow(line, metrics: metrics)
                }
            }
            .frame(maxHeight: .infinity)

            resultDivider

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("TOTAL")
                    .font(.system(
                        size: metrics.expanded ? 21 : (metrics.compact ? 11 : 14),
                        weight: .black,
                        design: .monospaced
                    ))
                Spacer(minLength: 4)
                Text("+\(AppPresentation.coinText(coinLedger.total))")
                    .font(.system(
                        size: metrics.expanded ? 48 : (metrics.compact ? 24 : 30),
                        weight: .black,
                        design: .monospaced
                    ))
                    .monospacedDigit()
                    .foregroundStyle(PocketVectorTheme.gold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                    .shadow(color: .black.opacity(0.92), radius: 0, x: 2, y: 3)
            }
            .padding(.top, metrics.compact ? 4 : (metrics.expanded ? 10 : 6))
        }
        .padding(.horizontal, metrics.compact ? 18 : (metrics.expanded ? 26 : 20))
        .padding(.vertical, metrics.compact ? 13 : (metrics.expanded ? 24 : 16))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .resultsBroadcastPanel(bezel: .wing)
        .accessibilityElement(children: .contain)
    }

    private func coinLedgerRow(
        _ line: RunResultsCoinLine,
        metrics: ResultsLayoutMetrics
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(line.label)
                .font(.system(
                    size: metrics.expanded ? 18 : (metrics.compact ? 8 : 10),
                    weight: .black,
                    design: .monospaced
                ))
                .foregroundStyle(PocketVectorTheme.championshipSilver)
                .lineLimit(1)
                .minimumScaleFactor(0.64)

            Spacer(minLength: 3)

            Text("+\(AppPresentation.coinText(line.amount))")
                .font(.system(
                    size: metrics.expanded ? 21 : (metrics.compact ? 11 : 13),
                    weight: .black,
                    design: .monospaced
                ))
                .monospacedDigit()
                .foregroundStyle(PocketVectorTheme.gold)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(line.label.capitalized)
        .accessibilityValue("\(line.amount) coins")
    }

    private var accessibleCoinLedgerPanel: some View {
        VStack(spacing: 10) {
            HStack(spacing: 9) {
                Image("MenuCoinIcon")
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: 34, height: 34)
                    .accessibilityHidden(true)
                Text("COINS WON")
                    .font(.system(.title3, design: .monospaced, weight: .black))
                Spacer(minLength: 0)
            }
            .accessibilityAddTraits(.isHeader)

            ForEach(coinLedger.lines) { line in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(line.label)
                        .font(.system(.body, design: .monospaced, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 6)
                    Text("+\(AppPresentation.coinText(line.amount))")
                        .font(.system(.headline, design: .monospaced, weight: .black).monospacedDigit())
                        .foregroundStyle(PocketVectorTheme.gold)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(line.label.capitalized)
                .accessibilityValue("\(line.amount) coins")
            }

            resultDivider

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("TOTAL")
                    .font(.system(.title3, design: .monospaced, weight: .black))
                Spacer(minLength: 6)
                Text("+\(AppPresentation.coinText(coinLedger.total))")
                    .font(.system(.title2, design: .monospaced, weight: .black).monospacedDigit())
                    .foregroundStyle(PocketVectorTheme.gold)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Total coins won")
            .accessibilityValue("\(coinLedger.total) coins")

            if hasPendingSettlementCredit {
                Text("REWARD PENDING SYNC")
                    .font(.system(.body, design: .monospaced, weight: .black))
                    .foregroundStyle(PocketVectorTheme.warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .resultsBroadcastPanel(bezel: .wing)
    }

    private func optionalBonusRail(
        metrics: ResultsLayoutMetrics,
        accessibleType: Bool
    ) -> some View {
        Group {
            switch results.rewardedAdOffer {
            case let .progress(validRuns, requiredRuns):
                VStack(spacing: accessibleType ? 8 : 3) {
                    HStack(spacing: 8) {
                        Text("OPTIONAL BONUS")
                            .font(.system(
                                accessibleType ? .headline : .caption2,
                                design: .monospaced,
                                weight: .black
                            ))
                        Spacer(minLength: 6)
                        Text("\(validRuns) OF \(requiredRuns) ELIGIBLE RUNS")
                            .font(.system(
                                accessibleType ? .body : .caption2,
                                design: .monospaced,
                                weight: .bold
                            ).monospacedDigit())
                            .foregroundStyle(PocketVectorTheme.championshipSilver)
                            .multilineTextAlignment(.trailing)
                    }
                    ProgressView(value: Double(validRuns), total: Double(max(1, requiredRuns)))
                        .tint(PocketVectorTheme.championshipStatus)
                }

            case let .eligible(offerID, rewardCoins, canPresent):
                Button {
                    Task { await coordinator.requestRewardedAd(offerID) }
                } label: {
                    HStack(spacing: 8) {
                        Text("OPTIONAL BONUS")
                        Spacer(minLength: 6)
                        Text("WATCH FOR")
                        CoinAmount(
                            amount: rewardCoins,
                            iconSize: accessibleType ? 24 : 18,
                            font: accessibleType
                                ? .headline.weight(.black).monospacedDigit()
                                : .caption.weight(.black).monospacedDigit()
                        )
                    }
                    .font(.system(
                        accessibleType ? .headline : .caption,
                        design: .monospaced,
                        weight: .black
                    ))
                }
                .buttonStyle(.plain)
                .disabled(!canPresent)
                .accessibilityHint("The reward is credited only after verified ad completion")

            case .loading:
                rewardStatusRail("LOADING OPTIONAL BONUS", color: PocketVectorTheme.championshipStatus)
            case .verifying:
                rewardStatusRail("VERIFYING REWARD", color: PocketVectorTheme.championshipStatus)
            case let .rewarded(coins):
                rewardStatusRail(
                    "+\(AppPresentation.coinText(coins)) REWARDED",
                    color: PocketVectorTheme.success
                )
            case let .unavailable(message):
                VStack(alignment: .leading, spacing: 3) {
                    Text("OPTIONAL BONUS UNAVAILABLE")
                        .font(.system(
                            accessibleType ? .headline : .caption2,
                            design: .monospaced,
                            weight: .black
                        ))
                    Text(message)
                        .font(accessibleType ? .body : .caption2)
                        .foregroundStyle(PocketVectorTheme.championshipSilver)
                        .lineLimit(accessibleType ? nil : 1)
                }
            }
        }
        .padding(.horizontal, accessibleType ? 24 : (metrics.compact ? 26 : 30))
        .padding(.vertical, accessibleType ? 16 : (metrics.compact ? 8 : 11))
        .frame(maxWidth: .infinity, minHeight: accessibleType ? 88 : metrics.bonusHeight)
        .resultsBroadcastPanel(bezel: .bonus)
    }

    private func rewardStatusRail(_ text: String, color: Color) -> some View {
        HStack(spacing: 9) {
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
                .shadow(color: color.opacity(0.7), radius: 4)
                .accessibilityHidden(true)
            Text(text)
                .font(.system(.caption, design: .monospaced, weight: .black))
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func resultsActions(
        compact: Bool,
        expanded: Bool,
        accessibleType: Bool,
        stacksVertically: Bool = false
    ) -> some View {
        let layout = stacksVertically
            ? AnyLayout(VStackLayout(spacing: 10))
            : AnyLayout(HStackLayout(spacing: compact ? 10 : 14))

        layout {
            Button {
                coordinator.returnToMainMenu()
            } label: {
                Text("MAIN MENU")
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: expanded ? 72 : nil)
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
                            size: compact ? 20 : 25
                        )
                    }
                    Text("PLAY AGAIN")
                        .lineLimit(1)
                        .minimumScaleFactor(accessibleType ? 0.70 : 0.80)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: expanded ? 72 : nil)
            }
            .buttonStyle(ChampionshipPrimaryButtonStyle(
                compact: true,
                accessibilityCompact: accessibleType
            ))
            .accessibilityHint("Starts another run with the same offense and equipment")
        }
    }

    private var coinLedger: RunResultsCoinLedger {
        RunResultsCoinLedger(results: results)
    }

    private var hasPendingSettlementCredit: Bool {
        results.gameplayRewardState == .pending || results.signingBonusState == .pending
    }
}

private struct ResultsLayoutMetrics {
    let size: CGSize

    var compact: Bool { size.height < 430 }
    var expanded: Bool { !compact && size.width / max(size.height, 1) < 1.65 }
    var horizontalPadding: CGFloat { compact ? 14 : (expanded ? 28 : 20) }
    var verticalPadding: CGFloat { compact ? 5 : (expanded ? 20 : 10) }
    var sectionSpacing: CGFloat { compact ? 4 : (expanded ? 12 : 6) }
    var marqueeWidth: CGFloat {
        min(size.width - horizontalPadding * 2, expanded ? 520 : (compact ? 350 : 430))
    }
    var marqueeHeight: CGFloat { compact ? 78 : (expanded ? 180 : 90) }
    var maximumContentWidth: CGFloat { min(size.width - horizontalPadding * 2, expanded ? 1_260 : 1_080) }
    var wingWidth: CGFloat {
        if expanded { return min(390, maximumContentWidth * 0.31) }
        return min(compact ? 250 : 300, max(compact ? 200 : 230, maximumContentWidth * 0.30))
    }
    var centerOpening: CGFloat { max(36, maximumContentWidth - wingWidth * 2) }
    var bonusHeight: CGFloat { compact ? 36 : (expanded ? 62 : 42) }
    var actionsHeight: CGFloat { compact ? 48 : (expanded ? 64 : 50) }
    var wingHeight: CGFloat {
        let reserved = verticalPadding * 2
            + marqueeHeight
            + bonusHeight
            + actionsHeight
            + sectionSpacing * 3
        return min(expanded ? 610 : 260, max(compact ? 176 : 210, size.height - reserved))
    }
    var bonusWidth: CGFloat { min(maximumContentWidth, expanded ? 760 : (compact ? 440 : 560)) }
    var actionsWidth: CGFloat { min(maximumContentWidth, expanded ? 720 : (compact ? 430 : 520)) }
}

struct RunResultsCoinLine: Identifiable, Equatable {
    let id: String
    let label: String
    let amount: Int64
}

struct RunResultsCoinLedger: Equatable {
    let lines: [RunResultsCoinLine]
    let total: Int64

    init(results: RunResultsPresentation) {
        total = max(0, results.totalEarnedCoins)

        let components = [
            results.completionCoins,
            results.performanceCoins,
            results.accuracyCoins,
            results.signingBonusCoins,
        ]
        guard components.allSatisfy({ $0 >= 0 }),
              let reconciledTotal = components.checkedSum,
              reconciledTotal == total else {
            lines = [RunResultsCoinLine(id: "run-reward", label: "RUN REWARD", amount: total)]
            return
        }

        var earnedLines = [
            RunResultsCoinLine(
                id: "run-complete",
                label: "RUN COMPLETE",
                amount: results.completionCoins
            ),
            RunResultsCoinLine(
                id: "score-bonus",
                label: "SCORE BONUS",
                amount: results.performanceCoins
            ),
            RunResultsCoinLine(
                id: "accuracy-bonus",
                label: "ACCURACY BONUS",
                amount: results.accuracyCoins
            ),
        ]
        if results.signingBonusCoins > 0 {
            earnedLines.append(RunResultsCoinLine(
                id: "first-run-bonus",
                label: "FIRST RUN BONUS",
                amount: results.signingBonusCoins
            ))
        }
        lines = earnedLines
    }
}

private extension Array where Element == Int64 {
    var checkedSum: Int64? {
        var total: Int64 = 0
        for value in self {
            let (sum, overflow) = total.addingReportingOverflow(value)
            guard !overflow else { return nil }
            total = sum
        }
        return total
    }
}

private struct ResultsFieldBackdrop: View {
    let configuration: RunConfiguration

    private var layerPaths: [String] {
        GameplayFieldLayerStack(offenseTeamID: configuration.offenseTeamID)
            .orderedLayers
            .map(\.relativePath)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(layerPaths, id: \.self) { relativePath in
                    if let image = ResultsFieldImageLoader.image(relativePath: relativePath) {
                        Image(uiImage: image)
                            .resizable()
                            .interpolation(.none)
                            .scaledToFill()
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .clipped()
                    }
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private enum ResultsFieldImageLoader {
    static func image(relativePath: String) -> UIImage? {
        guard let url = GameAssetResources.url(for: relativePath) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
}

private struct ResultsBroadcastPanelModifier: ViewModifier {
    let emphasis: Bool
    let bezel: ResultsPanelBezel?

    func body(content: Content) -> some View {
        content
            .background(
                LinearGradient(
                    colors: [
                        PocketVectorTheme.championshipNavy.opacity(emphasis ? 0.90 : 0.84),
                        PocketVectorTheme.championshipVoid.opacity(emphasis ? 0.94 : 0.88),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 9)
            )
            .overlay {
                if let bezel {
                    Image(bezel.assetName)
                        .resizable(
                            capInsets: bezel.capInsets,
                            resizingMode: .stretch
                        )
                        .interpolation(.none)
                        .accessibilityHidden(true)
                } else {
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(PocketVectorTheme.championshipSteel.opacity(0.96), lineWidth: 2)
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(
                                    emphasis
                                        ? PocketVectorTheme.championshipStatus.opacity(0.68)
                                        : PocketVectorTheme.championshipSilver.opacity(0.42),
                                    lineWidth: 1
                                )
                                .padding(4)
                        }
                }
            }
            .shadow(color: .black.opacity(0.82), radius: 4, x: 0, y: 4)
    }
}

private enum ResultsPanelBezel {
    case marquee
    case wing
    case bonus

    var assetName: String {
        switch self {
        case .marquee: "ResultsMarqueeBezel"
        case .wing: "ResultsWingBezel"
        case .bonus: "ResultsBonusBezel"
        }
    }

    var capInsets: EdgeInsets {
        switch self {
        case .marquee:
            EdgeInsets(top: 15, leading: 17, bottom: 15, trailing: 17)
        case .wing:
            EdgeInsets(top: 18, leading: 16, bottom: 18, trailing: 16)
        case .bonus:
            EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20)
        }
    }
}

private extension View {
    func resultsBroadcastPanel(
        emphasis: Bool = false,
        bezel: ResultsPanelBezel? = nil
    ) -> some View {
        modifier(ResultsBroadcastPanelModifier(emphasis: emphasis, bezel: bezel))
    }
}

private struct AccessibleResultStat: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.system(.body, design: .monospaced, weight: .black))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 6)
            Text(value)
                .font(.system(.title3, design: .monospaced, weight: .black).monospacedDigit())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, minHeight: 54)
        .background(PocketVectorTheme.championshipVoid.opacity(0.52))
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .stroke(PocketVectorTheme.championshipSteel.opacity(0.70), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title.capitalized)
        .accessibilityValue(value)
    }
}

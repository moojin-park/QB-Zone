import SwiftUI

@MainActor
struct AchievementsView: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @Bindable var coordinator: AppCoordinator

    private var expandedLayout: Bool {
        verticalSizeClass == .regular
    }

    private var cards: [AchievementCardPresentation] {
        AppPresentation.achievements(progress: coordinator.state.achievementProgress)
    }

    private var summary: AchievementSummaryPresentation {
        AppPresentation.achievementSummary(cards: cards)
    }

    var body: some View {
        ChampionshipSubmenuScreen(
            title: "Achievements",
            subtitle: "Eight launch challenges worth 600 Game Center points.",
            onBack: coordinator.goBack
        ) {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    SummaryStat(
                        title: "COMPLETE",
                        value: "\(summary.completedCount) / \(summary.totalCount)"
                    )
                    SummaryStat(
                        title: "POINTS",
                        value: "\(summary.earnedPoints) / \(summary.totalPoints)"
                    )
                }
                .padding(.horizontal)

                ScrollView {
                    LazyVGrid(
                        columns: expandedLayout
                            ? [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]
                            : [GridItem(.adaptive(minimum: 280, maximum: 520), spacing: 12)],
                        spacing: 12
                    ) {
                        ForEach(cards) { card in
                            AchievementRow(card: card) {
                                coordinator.showAchievement(card.id)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 14)
                }
                .frame(maxHeight: expandedLayout ? 560 : .infinity)
            }
        }
    }
}
@MainActor
struct AchievementDetailView: View {
    let achievementID: AchievementID
    @Bindable var coordinator: AppCoordinator

    private var card: AchievementCardPresentation? {
        AppPresentation.achievements(progress: coordinator.state.achievementProgress)
            .first { $0.id == achievementID }
    }

    var body: some View {
        ChampionshipSubmenuScreen(
            title: card?.definition.displayName ?? "Achievement",
            subtitle: "Launch achievement detail",
            onBack: coordinator.goBack
        ) {
            if let card {
                ScrollView {
                    VStack(spacing: 18) {
                        ZStack {
                            Circle()
                                .fill(
                                    card.progress.isCompleted
                                        ? PocketVectorTheme.gold.opacity(0.22)
                                        : PocketVectorTheme.championshipGraphite
                                )
                            ChampionshipPixelIcon(
                                name: achievementIconName(card.id),
                                size: 86
                            )
                            .saturation(card.progress.isCompleted ? 1 : 0.24)
                            .opacity(card.progress.isCompleted ? 1 : 0.74)
                        }
                        .frame(width: 104, height: 104)
                        .accessibilityHidden(true)

                        VStack(spacing: 8) {
                            Text(card.definition.displayName)
                                .font(.largeTitle.weight(.black))
                                .multilineTextAlignment(.center)
                            Text(card.definition.detail)
                                .font(.title3)
                                .foregroundStyle(PocketVectorTheme.textSecondary)
                                .multilineTextAlignment(.center)
                        }

                        VStack(spacing: 8) {
                            ProgressView(value: Double(card.progress.percentComplete), total: 100)
                                .tint(card.progress.isCompleted ? PocketVectorTheme.success : PocketVectorTheme.cyan)
                            HStack {
                                Text("\(card.progress.percentComplete)% complete")
                                Spacer()
                                Text("\(card.definition.points) points")
                            }
                            .font(.headline.monospacedDigit())
                        }
                        .padding(16)
                        .championshipPanel()
                        .accessibilityElement(children: .combine)

                        if let completedAt = card.progress.completedAt {
                            Text("Completed \(completedAt.formatted(date: .abbreviated, time: .omitted))")
                                .font(.subheadline)
                                .foregroundStyle(PocketVectorTheme.success)
                        }
                    }
                    .frame(maxWidth: 620)
                    .padding()
                    .frame(maxWidth: .infinity)
                }
            } else {
                VStack(spacing: 12) {
                    ChampionshipPixelIcon(name: "MenuAchievementIcon", size: 76)
                    Text("Achievement unavailable")
                        .font(.title2.weight(.black))
                    Text("Return to the achievement list and try again.")
                        .font(.subheadline)
                        .foregroundStyle(PocketVectorTheme.championshipSilver)
                }
                .padding(24)
                .championshipPanel()
                .accessibilityElement(children: .combine)
            }
        }
    }
}

private struct SummaryStat: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption2.weight(.black))
                .foregroundStyle(PocketVectorTheme.textSecondary)
            Text(value)
                .font((verticalSizeClass == .regular ? Font.title : .title2).weight(.black).monospacedDigit())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, verticalSizeClass == .regular ? 14 : 10)
        .championshipPanel()
        .accessibilityElement(children: .combine)
    }
}

private struct AchievementRow: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    let card: AchievementCardPresentation
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                ChampionshipPixelIcon(
                    name: achievementIconName(card.id),
                    size: verticalSizeClass == .regular ? 58 : 44
                )
                    .saturation(card.progress.isCompleted ? 1 : 0.22)
                    .opacity(card.progress.isCompleted ? 1 : 0.68)
                    .frame(width: verticalSizeClass == .regular ? 52 : 38)

                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(card.definition.displayName)
                            .font((verticalSizeClass == .regular ? Font.title3 : .headline).weight(.bold))
                            .foregroundStyle(PocketVectorTheme.textPrimary)
                        Spacer(minLength: 8)
                        Text("\(card.definition.points) pts")
                            .font((verticalSizeClass == .regular ? Font.subheadline : .caption).weight(.bold))
                            .foregroundStyle(PocketVectorTheme.gold)
                    }
                    Text(card.definition.detail)
                        .font(verticalSizeClass == .regular ? .subheadline : .caption)
                        .foregroundStyle(PocketVectorTheme.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    ProgressView(value: Double(card.progress.percentComplete), total: 100)
                        .tint(card.progress.isCompleted ? PocketVectorTheme.success : PocketVectorTheme.cyan)
                }

                ChampionshipPixelIcon(name: "SubmenuForwardIcon", size: 22)
            }
            .padding(verticalSizeClass == .regular ? 18 : 14)
            .frame(
                maxWidth: .infinity,
                minHeight: verticalSizeClass == .regular ? 124 : 104,
                alignment: .leading
            )
            .championshipPanel()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(card.definition.displayName)
        .accessibilityValue("\(card.progress.percentComplete) percent complete, \(card.definition.points) points")
        .accessibilityHint("Shows achievement details")
        .accessibilityAddTraits(.isButton)
    }
}

private func achievementIconName(_ id: AchievementID) -> String {
    switch id {
    case LaunchAchievementID.firstRead:
        "AchievementFirstReadIcon"
    case LaunchAchievementID.paydirt:
        "AchievementPaydirtIcon"
    case LaunchAchievementID.cashTheCharge:
        "AchievementCashTheChargeIcon"
    case LaunchAchievementID.fullRouteTree:
        "AchievementFullRouteTreeIcon"
    case LaunchAchievementID.dialedIn:
        "AchievementDialedInIcon"
    case LaunchAchievementID.hotHand:
        "AchievementHotHandIcon"
    case LaunchAchievementID.lightUpTheBoard:
        "AchievementLightUpBoardIcon"
    case LaunchAchievementID.centuryOfConnections:
        "AchievementCenturyConnectionsIcon"
    default:
        "MenuAchievementIcon"
    }
}

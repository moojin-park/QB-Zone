import SwiftUI

@MainActor
struct AchievementsView: View {
    @Bindable var coordinator: AppCoordinator

    private var cards: [AchievementCardPresentation] {
        AppPresentation.achievements(progress: coordinator.state.achievementProgress)
    }

    private var summary: AchievementSummaryPresentation {
        AppPresentation.achievementSummary(cards: cards)
    }

    var body: some View {
        PocketVectorScreen(
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
                        columns: [GridItem(.adaptive(minimum: 280, maximum: 520), spacing: 12)],
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
        PocketVectorScreen(
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
                                        : PocketVectorTheme.raisedSurface
                                )
                            Image(systemName: card.progress.isCompleted ? "trophy.fill" : "trophy")
                                .font(.system(.largeTitle, design: .rounded, weight: .black))
                                .foregroundStyle(PocketVectorTheme.gold)
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
                        .pocketVectorPanel()
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
                ContentUnavailableView(
                    "Achievement unavailable",
                    systemImage: "trophy",
                    description: Text("Return to the achievement list and try again.")
                )
            }
        }
    }
}

private struct SummaryStat: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption2.weight(.black))
                .foregroundStyle(PocketVectorTheme.textSecondary)
            Text(value)
                .font(.title2.weight(.black).monospacedDigit())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .pocketVectorPanel()
        .accessibilityElement(children: .combine)
    }
}

private struct AchievementRow: View {
    let card: AchievementCardPresentation
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: card.progress.isCompleted ? "trophy.fill" : "trophy")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(PocketVectorTheme.gold)
                    .frame(width: 38)

                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(card.definition.displayName)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(PocketVectorTheme.textPrimary)
                        Spacer(minLength: 8)
                        Text("\(card.definition.points) pts")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(PocketVectorTheme.gold)
                    }
                    Text(card.definition.detail)
                        .font(.caption)
                        .foregroundStyle(PocketVectorTheme.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    ProgressView(value: Double(card.progress.percentComplete), total: 100)
                        .tint(card.progress.isCompleted ? PocketVectorTheme.success : PocketVectorTheme.cyan)
                }

                Image(systemName: "chevron.right")
                    .foregroundStyle(PocketVectorTheme.textSecondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
            .pocketVectorPanel()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(card.definition.displayName)
        .accessibilityValue("\(card.progress.percentComplete) percent complete, \(card.definition.points) points")
        .accessibilityHint("Shows achievement details")
        .accessibilityAddTraits(.isButton)
    }
}

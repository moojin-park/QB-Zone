import SwiftUI

@MainActor
struct TeamSelectionView: View {
    @Bindable var coordinator: AppCoordinator

    private var cards: [TeamCardPresentation] {
        AppPresentation.teams(catalog: coordinator.catalog, state: coordinator.state)
    }

    var body: some View {
        PocketVectorScreen(
            title: "Choose Your Offense",
            subtitle: "The defense is randomized from the other seven teams.",
            onBack: coordinator.goBack
        ) {
            VStack(spacing: 10) {
                HStack {
                    BalanceBadge(
                        confirmedCoins: coordinator.state.confirmedCoins,
                        pendingCoins: coordinator.state.pendingCoins
                    )
                    Spacer()
                    Text("4 free · 4 coin unlocks")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PocketVectorTheme.textSecondary)
                }
                .padding(.horizontal)

                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 220, maximum: 360), spacing: 12)],
                        spacing: 12
                    ) {
                        ForEach(cards) { card in
                            TeamSelectionCard(card: card) {
                                activate(card)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }

                HStack(spacing: 12) {
                    if let team = coordinator.selectedTeam {
                        HStack(spacing: 10) {
                            TeamMark(team: team, size: 42)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("OFFENSE")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(PocketVectorTheme.textSecondary)
                                Text(team.displayName)
                                    .font(.headline)
                                    .lineLimit(1)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }

                    Spacer(minLength: 10)

                    Button {
                        _ = coordinator.startRun()
                    } label: {
                        Label("Start Run", systemImage: "play.fill")
                            .frame(minWidth: 150)
                    }
                    .buttonStyle(PrimaryActionButtonStyle())
                    .fixedSize(horizontal: true, vertical: false)
                    .accessibilityHint("Starts gameplay with the selected offense")
                }
                .padding(.horizontal)
                .padding(.bottom, 10)
            }
        }
    }

    private func activate(_ card: TeamCardPresentation) {
        Task {
            if card.isOwned {
                await coordinator.selectTeam(card.team.id)
            } else if let item = card.unlockItem {
                await coordinator.requestUnlock(item.id)
            }
        }
    }
}

private struct TeamSelectionCard: View {
    let card: TeamCardPresentation
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    TeamMark(team: card.team)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(card.team.displayName)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(PocketVectorTheme.textPrimary)
                            .multilineTextAlignment(.leading)
                        Text(card.isOwned ? "Ready to play" : "Team unlock")
                            .font(.caption)
                            .foregroundStyle(PocketVectorTheme.textSecondary)
                    }

                    Spacer(minLength: 4)

                    if card.isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(PocketVectorTheme.success)
                            .accessibilityHidden(true)
                    } else if card.isLocked {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(PocketVectorTheme.gold)
                            .accessibilityHidden(true)
                    }
                }

                HStack {
                    Circle().fill(Color(card.team.primaryColor))
                    Circle().fill(Color(card.team.secondaryColor))
                    Circle().fill(Color(card.team.accentColor))
                    Spacer()
                    if let price = card.unlockItem?.price, card.isLocked {
                        Text("\(AppPresentation.coinText(price)) coins")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(PocketVectorTheme.gold)
                    } else if !card.isSelected {
                        Text("Choose")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(PocketVectorTheme.cyan)
                    }
                }
                .frame(height: 22)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
            .background(
                card.isSelected
                    ? PocketVectorTheme.raisedSurface
                    : PocketVectorTheme.surface,
                in: RoundedRectangle(cornerRadius: 16)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        card.isSelected ? PocketVectorTheme.cyan : PocketVectorTheme.border.opacity(0.6),
                        lineWidth: card.isSelected ? 3 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(card.team.displayName)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(card.isOwned ? "Selects this team as your offense" : "Requests this team unlock")
        .accessibilityAddTraits(card.isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var accessibilityValue: String {
        if card.isSelected {
            return "Selected"
        }
        if let price = card.unlockItem?.price, card.isLocked {
            return "Locked, \(price) coins"
        }
        return "Owned"
    }
}

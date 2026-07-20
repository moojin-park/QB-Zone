import SwiftUI

@MainActor
struct TeamSelectionView: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @Bindable var coordinator: AppCoordinator

    private var expandedLayout: Bool {
        verticalSizeClass == .regular
    }

    private var cards: [TeamCardPresentation] {
        AppPresentation.teams(catalog: coordinator.catalog, state: coordinator.state)
    }

    private var selectedJersey: JerseyDescriptor? {
        guard let team = coordinator.selectedTeam else { return nil }
        guard let jerseyID = coordinator.state.selection.selectedJerseyByTeam[team.id] else {
            return team.primaryJersey
        }
        return coordinator.catalog.jersey(id: jerseyID) ?? team.primaryJersey
    }

    var body: some View {
        ChampionshipSubmenuScreen(
            title: "Choose Your Offense",
            subtitle: "The defense is randomized from the other seven teams.",
            onBack: coordinator.goBack,
            headerAccessory: {
                BalanceBadge(
                    confirmedCoins: coordinator.state.confirmedCoins,
                    pendingCoins: coordinator.state.pendingCoins
                )
            }
        ) {
            VStack(spacing: 10) {
                HStack {
                    Spacer()
                    Text("4 FREE  •  4 UNLOCKS")
                        .font(.system(.caption2, design: .monospaced, weight: .bold))
                        .tracking(0.7)
                        .foregroundStyle(PocketVectorTheme.championshipSilver)
                }
                .padding(.horizontal)

                ScrollView {
                    LazyVGrid(
                        columns: expandedLayout
                            ? [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]
                            : [GridItem(.adaptive(minimum: 220, maximum: 360), spacing: 12)],
                        spacing: expandedLayout ? 16 : 12
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
                .frame(maxHeight: expandedLayout ? 540 : .infinity)

                HStack(spacing: 12) {
                    if let team = coordinator.selectedTeam {
                        HStack(spacing: 10) {
                            TeamMark(team: team, size: expandedLayout ? 56 : 42)
                            if let selectedJersey {
                                JerseyPreview(jersey: selectedJersey)
                                    .frame(
                                        width: expandedLayout ? 64 : 48,
                                        height: expandedLayout ? 56 : 42
                                    )
                            }
                            VStack(alignment: .leading, spacing: 1) {
                                Text("OFFENSE")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(PocketVectorTheme.textSecondary)
                                Text(team.displayName)
                                    .font(expandedLayout ? .title3 : .headline)
                                    .lineLimit(1)
                            }

                            Text("EQUIPPED")
                                .font(.system(.caption2, design: .monospaced, weight: .black))
                                .foregroundStyle(PocketVectorTheme.success)
                        }
                        .accessibilityElement(children: .combine)
                    }

                    Spacer(minLength: 10)

                    Button {
                        _ = coordinator.startRun()
                    } label: {
                        HStack(spacing: 9) {
                            ChampionshipPixelIcon(name: "SubmenuPlayIcon", size: 28)
                            Text("START RUN")
                        }
                            .frame(minWidth: expandedLayout ? 190 : 150)
                    }
                    .buttonStyle(ChampionshipPrimaryButtonStyle(compact: !expandedLayout))
                    .fixedSize(horizontal: true, vertical: false)
                    .accessibilityHint("Starts gameplay with the selected offense")
                }
                .padding(expandedLayout ? 14 : 10)
                .championshipPanel()
                .padding(.horizontal)
                .padding(.bottom, 8)
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
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    let card: TeamCardPresentation
    let action: () -> Void

    private var compactLandscape: Bool {
        verticalSizeClass == .compact
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: compactLandscape ? 6 : 10) {
                HStack(alignment: .top, spacing: compactLandscape ? 9 : 12) {
                    TeamMark(team: card.team, size: compactLandscape ? 50 : 68)

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
                        ChampionshipPixelIcon(name: "SubmenuSelectedIcon", size: 24)
                    } else if card.isLocked {
                        ChampionshipPixelIcon(name: "SubmenuLockIcon", size: 24)
                    }
                }

                HStack {
                    Circle().fill(Color(card.team.primaryColor))
                    Circle().fill(Color(card.team.secondaryColor))
                    Circle().fill(Color(card.team.accentColor))
                    Spacer()
                    if let price = card.unlockItem?.price, card.isLocked {
                        CoinAmount(amount: price, iconSize: 20)
                    } else if !card.isSelected {
                        Text("Choose")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(PocketVectorTheme.championshipSilver)
                    } else {
                        Text("Selected")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(PocketVectorTheme.success)
                    }
                }
                .frame(height: 22)
            }
            .padding(compactLandscape ? 10 : 18)
            .frame(
                maxWidth: .infinity,
                minHeight: compactLandscape ? 100 : 160,
                alignment: .topLeading
            )
            .championshipPanel(isSelected: card.isSelected)
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

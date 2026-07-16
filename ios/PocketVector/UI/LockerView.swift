import SwiftUI

@MainActor
struct LockerView: View {
    @Bindable var coordinator: AppCoordinator

    private var teamCards: [TeamCardPresentation] {
        AppPresentation.teams(catalog: coordinator.catalog, state: coordinator.state)
    }

    private var selectedTeam: TeamDescriptor {
        coordinator.selectedTeam ?? coordinator.catalog.teams[0]
    }

    private var jerseyCards: [JerseyCardPresentation] {
        AppPresentation.jerseys(
            for: selectedTeam,
            catalog: coordinator.catalog,
            state: coordinator.state
        )
    }

    private var footballCards: [FootballCardPresentation] {
        AppPresentation.footballs(catalog: coordinator.catalog, state: coordinator.state)
    }

    var body: some View {
        PocketVectorScreen(
            title: "Team & Locker",
            subtitle: "Uniforms stay with their team. Footballs work with every offense.",
            onBack: coordinator.goBack
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("OFFENSE")
                            .font(.headline.weight(.black))
                        Spacer()
                        BalanceBadge(
                            confirmedCoins: coordinator.state.confirmedCoins,
                            pendingCoins: coordinator.state.pendingCoins
                        )
                    }

                    ScrollView(.horizontal) {
                        HStack(spacing: 10) {
                            ForEach(teamCards) { card in
                                LockerTeamButton(card: card) {
                                    activateTeam(card)
                                }
                            }
                        }
                    }
                    .scrollIndicators(.hidden)

                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 16) {
                            jerseySection
                            footballSection
                        }
                        VStack(spacing: 16) {
                            jerseySection
                            footballSection
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 16)
            }
        }
    }

    private var jerseySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(selectedTeam.displayName) Jerseys")
                .font(.title3.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 180), spacing: 10)],
                spacing: 10
            ) {
                ForEach(jerseyCards) { card in
                    JerseyLockerCard(card: card) {
                        Task {
                            if card.isOwned {
                                await coordinator.equipJersey(card.jersey.id, for: selectedTeam.id)
                            } else if let item = card.unlockItem {
                                await coordinator.requestUnlock(item.id)
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pocketVectorPanel()
    }

    private var footballSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Footballs")
                .font(.title3.weight(.bold))

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 180), spacing: 10)],
                spacing: 10
            ) {
                ForEach(footballCards) { card in
                    FootballLockerCard(card: card) {
                        Task {
                            if card.isOwned {
                                await coordinator.equipFootball(card.football.id)
                            } else if let item = card.unlockItem {
                                await coordinator.requestUnlock(item.id)
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pocketVectorPanel()
    }

    private func activateTeam(_ card: TeamCardPresentation) {
        Task {
            if card.isOwned {
                await coordinator.selectTeam(card.team.id)
            } else if let item = card.unlockItem {
                await coordinator.requestUnlock(item.id)
            }
        }
    }
}

private struct LockerTeamButton: View {
    let card: TeamCardPresentation
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                TeamMark(team: card.team, size: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.team.displayName)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(PocketVectorTheme.textPrimary)
                        .lineLimit(2)
                    if card.isLocked, let price = card.unlockItem?.price {
                        Text("\(AppPresentation.coinText(price)) coins")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(PocketVectorTheme.gold)
                    } else {
                        Text(card.isSelected ? "Selected" : "Owned")
                            .font(.caption)
                            .foregroundStyle(
                                card.isSelected
                                    ? PocketVectorTheme.success
                                    : PocketVectorTheme.textSecondary
                            )
                    }
                }
                if card.isLocked {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(PocketVectorTheme.gold)
                }
            }
            .padding(10)
            .frame(width: 196, alignment: .leading)
            .frame(minHeight: 66)
            .background(PocketVectorTheme.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        card.isSelected ? PocketVectorTheme.cyan : PocketVectorTheme.border.opacity(0.55),
                        lineWidth: card.isSelected ? 3 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(card.team.displayName)
        .accessibilityHint(card.isOwned ? "Selects this offense" : "Requests this team unlock")
        .accessibilityAddTraits(card.isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

private struct JerseyLockerCard: View {
    let card: JerseyCardPresentation
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                JerseyPreview(jersey: card.jersey)
                    .frame(height: 70)

                HStack {
                    Text(card.jersey.displayName)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(PocketVectorTheme.textPrimary)
                    Spacer()
                    status
                }
            }
            .padding(10)
            .background(PocketVectorTheme.raisedSurface, in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        card.isEquipped ? PocketVectorTheme.cyan : .clear,
                        lineWidth: 3
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(card.jersey.displayName) jersey")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(card.isOwned ? "Equips this jersey" : "Requests this jersey unlock")
        .accessibilityAddTraits(card.isEquipped ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private var status: some View {
        if card.isEquipped {
            StatusPill(text: "Equipped", color: PocketVectorTheme.success)
        } else if let price = card.unlockItem?.price, card.isLocked {
            Text("\(AppPresentation.coinText(price))")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(PocketVectorTheme.gold)
        } else {
            Text("Equip")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(PocketVectorTheme.cyan)
        }
    }

    private var accessibilityValue: String {
        if card.isEquipped { return "Equipped" }
        if let price = card.unlockItem?.price, card.isLocked {
            return "Locked, \(price) coins"
        }
        return "Owned"
    }
}

private struct FootballLockerCard: View {
    let card: FootballCardPresentation
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                FootballPreview(footballID: card.football.id)
                    .frame(height: 70)

                HStack {
                    Text(card.football.displayName)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(PocketVectorTheme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    Spacer()
                    if card.isEquipped {
                        StatusPill(text: "Equipped", color: PocketVectorTheme.success)
                    } else if let price = card.unlockItem?.price, card.isLocked {
                        Text(AppPresentation.coinText(price))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(PocketVectorTheme.gold)
                    } else {
                        Text("Equip")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(PocketVectorTheme.cyan)
                    }
                }
            }
            .padding(10)
            .background(PocketVectorTheme.raisedSurface, in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(card.isEquipped ? PocketVectorTheme.cyan : .clear, lineWidth: 3)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(card.football.displayName)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(card.isOwned ? "Equips this football" : "Requests this football unlock")
        .accessibilityAddTraits(card.isEquipped ? [.isButton, .isSelected] : .isButton)
    }

    private var accessibilityValue: String {
        if card.isEquipped { return "Equipped" }
        if let price = card.unlockItem?.price, card.isLocked {
            return "Locked, \(price) coins"
        }
        return "Owned"
    }
}

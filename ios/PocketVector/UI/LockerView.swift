import SwiftUI

@MainActor
struct LockerView: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @Bindable var coordinator: AppCoordinator

    private var expandedLayout: Bool {
        verticalSizeClass == .regular
    }

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
        ChampionshipSubmenuScreen(
            title: "Team & Locker",
            subtitle: "Uniforms stay with their team. Footballs work with every offense.",
            onBack: coordinator.goBack,
            headerAccessory: {
                BalanceBadge(
                    confirmedCoins: coordinator.state.confirmedCoins,
                    pendingCoins: coordinator.state.pendingCoins
                )
            }
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ChampionshipSectionTitle("Offense")

                    if expandedLayout {
                        LazyVGrid(
                            columns: Array(
                                repeating: GridItem(.flexible(), spacing: 10),
                                count: 4
                            ),
                            spacing: 10
                        ) {
                            ForEach(teamCards) { card in
                                LockerTeamButton(card: card) {
                                    activateTeam(card)
                                }
                            }
                        }
                    } else {
                        ScrollViewReader { proxy in
                            ScrollView(.horizontal) {
                                HStack(spacing: 10) {
                                    ForEach(teamCards) { card in
                                        LockerTeamButton(card: card) {
                                            activateTeam(card)
                                        }
                                        .id(card.team.id)
                                    }
                                }
                            }
                            .scrollIndicators(.hidden)
                            .onAppear {
                                proxy.scrollTo(selectedTeam.id, anchor: .center)
                            }
                            .onChange(of: selectedTeam.id) { _, teamID in
                                proxy.scrollTo(teamID, anchor: .center)
                            }
                        }
                    }

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
                .padding(.top, expandedLayout ? 20 : 0)
                .padding(.bottom, expandedLayout ? 30 : 16)
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
        .frame(
            maxWidth: .infinity,
            minHeight: expandedLayout ? 360 : nil,
            alignment: .topLeading
        )
        .championshipPanel()
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
        .frame(
            maxWidth: .infinity,
            minHeight: expandedLayout ? 360 : nil,
            alignment: .topLeading
        )
        .championshipPanel()
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
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    let card: TeamCardPresentation
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: verticalSizeClass == .regular ? 13 : 9) {
                TeamMark(team: card.team, size: verticalSizeClass == .regular ? 54 : 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.team.displayName)
                        .font((verticalSizeClass == .regular ? Font.headline : .subheadline).weight(.bold))
                        .foregroundStyle(PocketVectorTheme.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                        .layoutPriority(1)
                    if card.isLocked, let price = card.unlockItem?.price {
                        CoinAmount(
                            amount: price,
                            iconSize: 17,
                            font: .caption.weight(.semibold).monospacedDigit()
                        )
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
                .frame(maxWidth: .infinity, alignment: .leading)
                if card.isLocked {
                    ChampionshipPixelIcon(name: "SubmenuLockIcon", size: 22)
                }
            }
            .padding(verticalSizeClass == .regular ? 14 : 10)
            .frame(width: verticalSizeClass == .regular ? nil : 196, alignment: .leading)
            .frame(maxWidth: verticalSizeClass == .regular ? .infinity : nil)
            .frame(minHeight: verticalSizeClass == .regular ? 84 : 66)
            .championshipPanel(isSelected: card.isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(card.team.displayName)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(card.isOwned ? "Selects this offense" : "Requests this team unlock")
        .accessibilityAddTraits(card.isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var accessibilityValue: String {
        if card.isSelected {
            return "Selected"
        }
        if card.isLocked, let price = card.unlockItem?.price {
            return "Locked, \(price) coins"
        }
        return "Owned"
    }
}

private struct JerseyLockerCard: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    let card: JerseyCardPresentation
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                JerseyPreview(jersey: card.jersey)
                    .frame(height: verticalSizeClass == .regular ? 176 : 70)

                cardFooter
            }
            .padding(verticalSizeClass == .regular ? 14 : 10)
            .championshipPanel(isSelected: card.isEquipped)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(card.jersey.displayName) jersey")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(card.isOwned ? "Equips this jersey" : "Requests this jersey unlock")
        .accessibilityAddTraits(card.isEquipped ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private var cardFooter: some View {
        if verticalSizeClass == .regular {
            VStack(alignment: .leading, spacing: 7) {
                Text(card.jersey.displayName)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(PocketVectorTheme.textPrimary)
                    .lineLimit(2)
                status
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack {
                Text(card.jersey.displayName)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(PocketVectorTheme.textPrimary)
                Spacer()
                status
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        if card.isEquipped {
            StatusPill(text: "Equipped", color: PocketVectorTheme.success)
        } else if let price = card.unlockItem?.price, card.isLocked {
            CoinAmount(amount: price, iconSize: 19)
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
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    let card: FootballCardPresentation
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                FootballPreview(footballID: card.football.id)
                    .frame(height: verticalSizeClass == .regular ? 176 : 70)

                cardFooter
            }
            .padding(verticalSizeClass == .regular ? 14 : 10)
            .championshipPanel(isSelected: card.isEquipped)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(card.football.displayName)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(card.isOwned ? "Equips this football" : "Requests this football unlock")
        .accessibilityAddTraits(card.isEquipped ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private var cardFooter: some View {
        if verticalSizeClass == .regular {
            VStack(alignment: .leading, spacing: 7) {
                footballName
                footballStatus
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack {
                footballName
                Spacer()
                footballStatus
            }
        }
    }

    private var footballName: some View {
        Text(card.football.displayName)
            .font(.headline.weight(.bold))
            .foregroundStyle(PocketVectorTheme.textPrimary)
            .lineLimit(verticalSizeClass == .regular ? 2 : 1)
            .minimumScaleFactor(0.78)
    }

    @ViewBuilder
    private var footballStatus: some View {
        if card.isEquipped {
            StatusPill(text: "Equipped", color: PocketVectorTheme.success)
        } else if let price = card.unlockItem?.price, card.isLocked {
            CoinAmount(amount: price, iconSize: 19)
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

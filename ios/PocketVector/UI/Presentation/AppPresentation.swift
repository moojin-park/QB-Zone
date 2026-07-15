import Foundation

struct TeamCardPresentation: Equatable, Identifiable {
    let team: TeamDescriptor
    let isOwned: Bool
    let isSelected: Bool
    let unlockItem: CatalogItemDescriptor?

    var id: TeamID { team.id }
    var isLocked: Bool { !isOwned }
}
struct JerseyCardPresentation: Equatable, Identifiable {
    let jersey: JerseyDescriptor
    let isOwned: Bool
    let isEquipped: Bool
    let unlockItem: CatalogItemDescriptor?

    var id: JerseyID { jersey.id }
    var isLocked: Bool { !isOwned }
}

struct FootballCardPresentation: Equatable, Identifiable {
    let football: FootballDescriptor
    let isOwned: Bool
    let isEquipped: Bool
    let unlockItem: CatalogItemDescriptor?

    var id: FootballID { football.id }
    var isLocked: Bool { !isOwned }
}

struct AchievementCardPresentation: Equatable, Identifiable {
    let definition: AchievementDefinition
    let progress: AchievementProgress

    var id: AchievementID { definition.id }
}

struct AchievementSummaryPresentation: Equatable {
    let completedCount: Int
    let totalCount: Int
    let earnedPoints: Int
    let totalPoints: Int
}

enum AppPresentation {
    static func teams(
        catalog: LaunchCatalog,
        state: AppCoordinatorState
    ) -> [TeamCardPresentation] {
        catalog.teams.map { team in
            TeamCardPresentation(
                team: team,
                isOwned: state.inventory.ownedTeamIDs.contains(team.id),
                isSelected: state.selection.selectedTeamID == team.id,
                unlockItem: catalog.unlockableItems.first {
                    $0.kind == .team(team.id)
                }
            )
        }
    }

    static func jerseys(
        for team: TeamDescriptor,
        catalog: LaunchCatalog,
        state: AppCoordinatorState
    ) -> [JerseyCardPresentation] {
        team.jerseys.map { jersey in
            JerseyCardPresentation(
                jersey: jersey,
                isOwned: state.inventory.ownedJerseyIDs.contains(jersey.id),
                isEquipped: state.selection.selectedJerseyByTeam[team.id] == jersey.id,
                unlockItem: catalog.unlockableItems.first {
                    $0.kind == .alternateJersey(jersey.id)
                }
            )
        }
    }

    static func footballs(
        catalog: LaunchCatalog,
        state: AppCoordinatorState
    ) -> [FootballCardPresentation] {
        catalog.footballs.map { football in
            FootballCardPresentation(
                football: football,
                isOwned: state.inventory.ownedFootballIDs.contains(football.id),
                isEquipped: state.selection.selectedFootballID == football.id,
                unlockItem: catalog.unlockableItems.first {
                    $0.kind == .football(football.id)
                }
            )
        }
    }

    static func achievements(
        definitions: [AchievementDefinition] = AchievementCatalog.launch,
        progress: [AchievementID: AchievementProgress]
    ) -> [AchievementCardPresentation] {
        definitions.map { definition in
            AchievementCardPresentation(
                definition: definition,
                progress: progress[definition.id]
                    ?? AchievementProgress(id: definition.id)
            )
        }
    }

    static func achievementSummary(
        cards: [AchievementCardPresentation]
    ) -> AchievementSummaryPresentation {
        AchievementSummaryPresentation(
            completedCount: cards.filter(\.progress.isCompleted).count,
            totalCount: cards.count,
            earnedPoints: cards.reduce(0) { partial, card in
                partial + (card.progress.isCompleted ? card.definition.points : 0)
            },
            totalPoints: cards.reduce(0) { $0 + $1.definition.points }
        )
    }

    static func coinText(_ coins: Int64) -> String {
        coins.formatted(.number.grouping(.automatic))
    }

    static func proposedUSPriceText(_ price: Decimal) -> String {
        String(
            format: "$%.2f",
            locale: Locale(identifier: "en_US_POSIX"),
            NSDecimalNumber(decimal: price).doubleValue
        )
    }
}

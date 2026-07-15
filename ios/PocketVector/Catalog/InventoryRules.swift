import Foundation

enum InventoryRuleError: Error, Equatable {
    case unknownTeam(TeamID)
    case unknownJersey(JerseyID)
    case unknownFootball(FootballID)
    case unknownCatalogItem(CatalogItemID)
    case teamNotOwned(TeamID)
    case jerseyNotOwned(JerseyID)
    case footballNotOwned(FootballID)
    case jerseyDoesNotBelongToTeam(jerseyID: JerseyID, teamID: TeamID)
    case alreadyOwned(CatalogItemID)
    case alternateRequiresTeam(teamID: TeamID)
}

enum InventoryRules {
    static func initialInventory(catalog: LaunchCatalog = .approved) -> PlayerInventory {
        let ownedTeams = Set(catalog.teams.filter(\.initiallyOwned).map(\.id))
        let primaryJerseys = Set(
            catalog.teams
                .filter(\.initiallyOwned)
                .map(\.primaryJersey.id)
        )
        let footballs = Set(catalog.footballs.filter(\.initiallyOwned).map(\.id))
        return PlayerInventory(
            ownedTeamIDs: ownedTeams,
            ownedJerseyIDs: primaryJerseys,
            ownedFootballIDs: footballs
        )
    }

    static func initialSelection(catalog: LaunchCatalog = .approved) -> PlayerSelection {
        let selectedTeam = LaunchTeamID.novaCityComets
        let jerseysByTeam = Dictionary(
            uniqueKeysWithValues: catalog.teams.map { ($0.id, $0.primaryJersey.id) }
        )
        return PlayerSelection(
            selectedTeamID: selectedTeam,
            selectedJerseyByTeam: jerseysByTeam,
            selectedFootballID: LaunchFootballID.standard
        )
    }

    static func validate(
        selection: PlayerSelection,
        inventory: PlayerInventory,
        catalog: LaunchCatalog = .approved
    ) throws {
        guard catalog.team(id: selection.selectedTeamID) != nil else {
            throw InventoryRuleError.unknownTeam(selection.selectedTeamID)
        }
        guard inventory.ownedTeamIDs.contains(selection.selectedTeamID) else {
            throw InventoryRuleError.teamNotOwned(selection.selectedTeamID)
        }
        guard let selectedJerseyID = selection.selectedJerseyID else {
            throw InventoryRuleError.jerseyNotOwned(
                JerseyID("missing-selection.\(selection.selectedTeamID.rawValue)")
            )
        }
        guard let jersey = catalog.jersey(id: selectedJerseyID) else {
            throw InventoryRuleError.unknownJersey(selectedJerseyID)
        }
        guard jersey.teamID == selection.selectedTeamID else {
            throw InventoryRuleError.jerseyDoesNotBelongToTeam(
                jerseyID: selectedJerseyID,
                teamID: selection.selectedTeamID
            )
        }
        guard inventory.ownedJerseyIDs.contains(selectedJerseyID) else {
            throw InventoryRuleError.jerseyNotOwned(selectedJerseyID)
        }
        guard catalog.football(id: selection.selectedFootballID) != nil else {
            throw InventoryRuleError.unknownFootball(selection.selectedFootballID)
        }
        guard inventory.ownedFootballIDs.contains(selection.selectedFootballID) else {
            throw InventoryRuleError.footballNotOwned(selection.selectedFootballID)
        }
    }

    @discardableResult
    static func applyUnlock(
        itemID: CatalogItemID,
        to inventory: inout PlayerInventory,
        catalog: LaunchCatalog = .approved
    ) throws -> Int64 {
        guard let item = catalog.item(id: itemID) else {
            throw InventoryRuleError.unknownCatalogItem(itemID)
        }

        switch item.kind {
        case let .team(teamID):
            guard !inventory.ownedTeamIDs.contains(teamID) else {
                throw InventoryRuleError.alreadyOwned(itemID)
            }
            guard let team = catalog.team(id: teamID) else {
                throw InventoryRuleError.unknownTeam(teamID)
            }
            inventory.ownedTeamIDs.insert(teamID)
            inventory.ownedJerseyIDs.insert(team.primaryJersey.id)

        case let .alternateJersey(jerseyID):
            guard !inventory.ownedJerseyIDs.contains(jerseyID) else {
                throw InventoryRuleError.alreadyOwned(itemID)
            }
            guard let jersey = catalog.jersey(id: jerseyID) else {
                throw InventoryRuleError.unknownJersey(jerseyID)
            }
            guard inventory.ownedTeamIDs.contains(jersey.teamID) else {
                throw InventoryRuleError.alternateRequiresTeam(teamID: jersey.teamID)
            }
            inventory.ownedJerseyIDs.insert(jerseyID)

        case let .football(footballID):
            guard !inventory.ownedFootballIDs.contains(footballID) else {
                throw InventoryRuleError.alreadyOwned(itemID)
            }
            guard catalog.football(id: footballID) != nil else {
                throw InventoryRuleError.unknownFootball(footballID)
            }
            inventory.ownedFootballIDs.insert(footballID)
        }

        return item.price
    }
}

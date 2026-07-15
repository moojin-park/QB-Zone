import Foundation
import XCTest

@testable import PocketVector

final class CatalogRulesTests: XCTestCase {
    func testApprovedRosterPalettesFreeSplitAndPricesAreLocked() {
        let catalog = LaunchCatalog.approved

        XCTAssertEqual(catalog.teams.count, 8)
        XCTAssertEqual(
            catalog.teams.map(\.displayName),
            [
                "Nova City Comets",
                "High Mesa Helions",
                "Luma Coast Prisms",
                "Foundry Reach Orbiters",
                "Neon Basin Eclipses",
                "Meridian Plains Radiants",
                "Rainport Auroras",
                "Bayline Redshifts",
            ]
        )
        XCTAssertEqual(
            catalog.teams.filter(\.initiallyOwned).map(\.id),
            [
                LaunchTeamID.novaCityComets,
                LaunchTeamID.highMesaHelions,
                LaunchTeamID.foundryReachOrbiters,
                LaunchTeamID.rainportAuroras,
            ]
        )
        XCTAssertEqual(
            catalog.teams.map(\.primaryColor.hex),
            ["#1DE6EF", "#F06A3B", "#63CFE7", "#146353", "#171923", "#C72F4F", "#0B3A4A", "#842C4B"]
        )

        XCTAssertEqual(catalog.unlockableItems.count, 13)
        XCTAssertEqual(catalog.unlockableItems.reduce(0) { $0 + $1.price }, 10_750)
        XCTAssertEqual(
            catalog.unlockableItems.filter {
                if case .team = $0.kind { return true }
                return false
            }.count,
            4
        )
        XCTAssertEqual(
            catalog.unlockableItems.filter {
                if case .alternateJersey = $0.kind { return true }
                return false
            }.count,
            8
        )
    }

    func testTeamDescriptorContainsPresentationDataAndNoGameplayModifiers() throws {
        let labels = Set(Mirror(reflecting: try XCTUnwrap(LaunchCatalog.approved.teams.first)).children.compactMap(\.label))
        XCTAssertEqual(
            labels,
            [
                "id", "displayName", "initiallyOwned", "primaryColor", "secondaryColor",
                "accentColor", "primaryJersey", "alternateJersey", "assets",
            ]
        )
    }

    func testInitialInventoryIncludesFourTeamsTheirPrimariesAndDefaultFootball() {
        let inventory = InventoryRules.initialInventory()
        XCTAssertEqual(inventory.ownedTeamIDs.count, 4)
        XCTAssertEqual(inventory.ownedJerseyIDs.count, 4)
        XCTAssertEqual(inventory.ownedFootballIDs, [LaunchFootballID.standard])
        XCTAssertTrue(inventory.ownedTeamIDs.contains(LaunchTeamID.novaCityComets))
    }

    func testTeamUnlockIncludesPrimaryAndAlternateStillRequiresSeparatePurchase() throws {
        let catalog = LaunchCatalog.approved
        let team = try XCTUnwrap(catalog.team(id: LaunchTeamID.lumaCoastPrisms))
        let teamItem = try XCTUnwrap(catalog.unlockableItems.first { $0.kind == .team(team.id) })
        let alternateItem = try XCTUnwrap(
            catalog.unlockableItems.first { $0.kind == .alternateJersey(team.alternateJersey.id) }
        )
        var inventory = InventoryRules.initialInventory(catalog: catalog)

        XCTAssertThrowsError(
            try InventoryRules.applyUnlock(
                itemID: alternateItem.id,
                to: &inventory,
                catalog: catalog
            )
        ) { error in
            XCTAssertEqual(
                error as? InventoryRuleError,
                .alternateRequiresTeam(teamID: team.id)
            )
        }

        XCTAssertEqual(
            try InventoryRules.applyUnlock(itemID: teamItem.id, to: &inventory, catalog: catalog),
            1_500
        )
        XCTAssertTrue(inventory.ownedTeamIDs.contains(team.id))
        XCTAssertTrue(inventory.ownedJerseyIDs.contains(team.primaryJersey.id))
        XCTAssertFalse(inventory.ownedJerseyIDs.contains(team.alternateJersey.id))

        XCTAssertEqual(
            try InventoryRules.applyUnlock(
                itemID: alternateItem.id,
                to: &inventory,
                catalog: catalog
            ),
            500
        )
        XCTAssertTrue(inventory.ownedJerseyIDs.contains(team.alternateJersey.id))
    }

    func testAlternateFootballIsGlobalInventory() throws {
        let catalog = LaunchCatalog.approved
        let item = try XCTUnwrap(
            catalog.unlockableItems.first { $0.kind == .football(LaunchFootballID.alternate) }
        )
        var inventory = InventoryRules.initialInventory(catalog: catalog)

        XCTAssertEqual(
            try InventoryRules.applyUnlock(itemID: item.id, to: &inventory, catalog: catalog),
            750
        )
        XCTAssertTrue(inventory.ownedFootballIDs.contains(LaunchFootballID.alternate))
    }

    func testMatchupIsDeterministicExcludesOffenseAndIncludesLockedOpponents() throws {
        let catalog = LaunchCatalog.approved
        let generator = MatchupGenerator(catalog: catalog)
        let inventory = InventoryRules.initialInventory(catalog: catalog)
        let selection = InventoryRules.initialSelection(catalog: catalog)
        let runID = RunID(UUID(uuidString: "00000000-0000-0000-0000-000000000123")!)
        let startedAt = Date(timeIntervalSince1970: 500)

        let first = try generator.makeRunConfiguration(
            selection: selection,
            inventory: inventory,
            runID: runID,
            seed: 91,
            startedAt: startedAt
        )
        let repeated = try generator.makeRunConfiguration(
            selection: selection,
            inventory: inventory,
            runID: runID,
            seed: 91,
            startedAt: startedAt
        )

        XCTAssertEqual(first, repeated)
        XCTAssertNotEqual(first.offenseTeamID, first.defenseTeamID)

        var opponents = Set<TeamID>()
        for seed in UInt32(0) ..< 500 {
            let configuration = try generator.makeRunConfiguration(
                selection: selection,
                inventory: inventory,
                seed: seed,
                startedAt: startedAt
            )
            opponents.insert(configuration.defenseTeamID)
        }
        XCTAssertEqual(opponents, Set(catalog.teams.map(\.id)).subtracting([selection.selectedTeamID]))
        XCTAssertTrue(opponents.contains(LaunchTeamID.neonBasinEclipses))
    }

    func testClashResolverCoversAll112OffenseJerseyOpponentPairs() {
        let catalog = LaunchCatalog.approved
        var evaluatedPairs = 0

        for offenseTeam in catalog.teams {
            for offenseJersey in offenseTeam.jerseys {
                for defenseTeam in catalog.teams where defenseTeam.id != offenseTeam.id {
                    evaluatedPairs += 1
                    let resolved = UniformClashResolver.resolve(
                        offense: offenseJersey,
                        defenseTeam: defenseTeam
                    )
                    XCTAssertTrue(defenseTeam.jerseys.contains(resolved))
                    let resolvedScore = UniformClashResolver.score(
                        offense: offenseJersey,
                        defense: resolved
                    )
                    for candidate in defenseTeam.jerseys {
                        XCTAssertGreaterThanOrEqual(
                            resolvedScore.total + 0.000_000_001,
                            UniformClashResolver.score(
                                offense: offenseJersey,
                                defense: candidate
                            ).total
                        )
                    }
                }
            }
        }

        XCTAssertEqual(evaluatedPairs, 112)
    }
}

import CryptoKit
import Foundation
import XCTest

@testable import PocketVector

final class CatalogRulesTests: XCTestCase {
    func testApprovedRosterPalettesOwnershipAndPricesAreLocked() {
        let catalog = LaunchCatalog.approved

        XCTAssertEqual(catalog.teams.count, 16)
        XCTAssertEqual(
            catalog.teams.map(\.id),
            LaunchTeamID.originalEight + LaunchTeamID.expansionEight
        )
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
                "Obsidian Vale Quasars",
                "Cobalt Junction Pulsars",
                "Copper Hollow Tremors",
                "Sunreef Currents",
                "Crown Rift Arclights",
                "Gilded Delta Monarchs",
                "Axiom Point Gravitons",
                "Emerald Spire Vortices",
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
        XCTAssertTrue(
            LaunchTeamID.expansionEight.allSatisfy {
                catalog.team(id: $0)?.initiallyOwned == false
            }
        )
        XCTAssertEqual(
            catalog.teams.map(\.primaryColor.hex),
            [
                "#1DE6EF", "#F06A3B", "#63CFE7", "#146353",
                "#171923", "#C72F4F", "#0B3A4A", "#842C4B",
                "#0B0D10", "#14284F", "#43271D", "#003F3C",
                "#40215F", "#26303B", "#1648B8", "#0D8642",
            ]
        )
        XCTAssertEqual(
            catalog.teams.map(\.secondaryColor.hex),
            [
                "#7D4DFF", "#2B234D", "#30214F", "#D4A73E",
                "#ADB5C2", "#F0A253", "#9DD643", "#C87845",
                "#E5484D", "#72C9F2", "#F57422", "#FF8C72",
                "#D9AE36", "#C2A36A", "#EFCB32", "#000000",
            ]
        )
        XCTAssertEqual(
            catalog.teams.map(\.accentColor.hex),
            [
                "#F7FCFF", "#D8F0EC", "#F4C64E", "#F0E8CF",
                "#A05CFF", "#FFF0DD", "#E5F2EA", "#DFE5E2",
                "#C5CFD8", "#F26678", "#F3DFC1", "#F4E8D8",
                "#F2EAF8", "#F6F0E4", "#F4F7FC", "#FFFFFF",
            ]
        )

        let teamItems = catalog.unlockableItems.filter {
            if case .team = $0.kind { return true }
            return false
        }
        let jerseyItems = catalog.unlockableItems.filter {
            if case .alternateJersey = $0.kind { return true }
            return false
        }
        let footballItems = catalog.unlockableItems.filter {
            if case .football = $0.kind { return true }
            return false
        }

        XCTAssertEqual(catalog.unlockableItems.count, 29)
        XCTAssertEqual(catalog.unlockableItems.reduce(0) { $0 + $1.price }, 26_750)
        XCTAssertEqual(teamItems.count, 12)
        XCTAssertTrue(teamItems.allSatisfy { $0.price == 1_500 })
        XCTAssertEqual(jerseyItems.count, 16)
        XCTAssertTrue(jerseyItems.allSatisfy { $0.price == 500 })
        XCTAssertEqual(footballItems.count, 1)
        XCTAssertEqual(footballItems.first?.price, 750)
        XCTAssertEqual(
            catalog.footballs,
            [
                FootballDescriptor(
                    id: LaunchFootballID.standard,
                    displayName: "Standard Football",
                    initiallyOwned: true,
                    assetKey: "footballs/standard"
                ),
                FootballDescriptor(
                    id: LaunchFootballID.alternate,
                    displayName: "Alternate Football",
                    initiallyOwned: false,
                    assetKey: "footballs/alternate"
                ),
            ]
        )
    }

    func testEveryTeamOwnsCanonicalUniqueJerseysAndAssetKeys() {
        let catalog = LaunchCatalog.approved
        let allJerseys = catalog.teams.flatMap(\.jerseys)

        XCTAssertEqual(allJerseys.count, 32)
        XCTAssertEqual(Set(allJerseys.map(\.id)).count, 32)

        for team in catalog.teams {
            XCTAssertEqual(
                team.primaryJersey.id,
                JerseyID("jersey.\(team.id.rawValue).primary")
            )
            XCTAssertEqual(team.primaryJersey.teamID, team.id)
            XCTAssertEqual(team.primaryJersey.kind, .primary)
            XCTAssertEqual(team.primaryJersey.displayName, "Primary")
            XCTAssertEqual(team.primaryJersey.primaryColor, team.primaryColor)
            XCTAssertEqual(team.primaryJersey.secondaryColor, team.secondaryColor)
            XCTAssertEqual(team.primaryJersey.accentColor, team.accentColor)
            XCTAssertEqual(
                team.primaryJersey.assets.paletteToken,
                "teams/\(team.id.rawValue)/primary"
            )
            XCTAssertEqual(
                team.alternateJersey.id,
                JerseyID("jersey.\(team.id.rawValue).alternate")
            )
            XCTAssertEqual(team.alternateJersey.teamID, team.id)
            XCTAssertEqual(team.alternateJersey.kind, .alternate)
            XCTAssertEqual(team.alternateJersey.displayName, "Alternate")
            XCTAssertEqual(team.alternateJersey.primaryColor, team.secondaryColor)
            XCTAssertEqual(team.alternateJersey.secondaryColor, team.accentColor)
            XCTAssertEqual(team.alternateJersey.accentColor, team.primaryColor)
            XCTAssertEqual(
                team.alternateJersey.assets.paletteToken,
                "teams/\(team.id.rawValue)/alternate"
            )
            XCTAssertEqual(team.assets.logo, "teams/\(team.id.rawValue)/logo")
            XCTAssertEqual(team.assets.endZone, "teams/\(team.id.rawValue)/end-zone")
            XCTAssertEqual(
                team.assets.fieldBranding,
                "teams/\(team.id.rawValue)/field-branding"
            )
        }
    }

    func testTeamDescriptorContainsPresentationDataAndNoGameplayModifiers() throws {
        let labels = Set(
            Mirror(
                reflecting: try XCTUnwrap(LaunchCatalog.approved.teams.first)
            ).children.compactMap(\.label)
        )
        XCTAssertEqual(
            labels,
            [
                "id", "displayName", "initiallyOwned", "primaryColor", "secondaryColor",
                "accentColor", "primaryJersey", "alternateJersey", "assets",
            ]
        )
    }

    func testInitialInventoryPreservesOriginalFourWhileNewSelectionKnowsAllPrimaries() {
        let catalog = LaunchCatalog.approved
        let inventory = InventoryRules.initialInventory(catalog: catalog)
        let selection = InventoryRules.initialSelection(catalog: catalog)

        XCTAssertEqual(
            inventory.ownedTeamIDs,
            Set([
                LaunchTeamID.novaCityComets,
                LaunchTeamID.highMesaHelions,
                LaunchTeamID.foundryReachOrbiters,
                LaunchTeamID.rainportAuroras,
            ])
        )
        XCTAssertEqual(inventory.ownedJerseyIDs.count, 4)
        XCTAssertEqual(inventory.ownedFootballIDs, [LaunchFootballID.standard])
        XCTAssertEqual(selection.selectedTeamID, LaunchTeamID.novaCityComets)
        XCTAssertEqual(selection.selectedFootballID, LaunchFootballID.standard)
        XCTAssertEqual(selection.selectedJerseyByTeam.count, 16)

        for team in catalog.teams {
            XCTAssertEqual(
                selection.selectedJerseyByTeam[team.id],
                team.primaryJersey.id
            )
        }
        XCTAssertTrue(
            Set(LaunchTeamID.expansionEight).isDisjoint(
                with: inventory.ownedTeamIDs
            )
        )
    }

    func testEveryExpansionUnlockUsesEstablishedTeamAndAlternatePrices() throws {
        let catalog = LaunchCatalog.approved

        for teamID in LaunchTeamID.expansionEight {
            let team = try XCTUnwrap(catalog.team(id: teamID))
            let teamItem = try XCTUnwrap(
                catalog.unlockableItems.first { $0.kind == .team(team.id) }
            )
            let alternateItem = try XCTUnwrap(
                catalog.unlockableItems.first {
                    $0.kind == .alternateJersey(team.alternateJersey.id)
                }
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
                try InventoryRules.applyUnlock(
                    itemID: teamItem.id,
                    to: &inventory,
                    catalog: catalog
                ),
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
    }

    func testAlternateFootballIsGlobalInventory() throws {
        let catalog = LaunchCatalog.approved
        let item = try XCTUnwrap(
            catalog.unlockableItems.first {
                $0.kind == .football(LaunchFootballID.alternate)
            }
        )
        var inventory = InventoryRules.initialInventory(catalog: catalog)

        XCTAssertEqual(
            try InventoryRules.applyUnlock(
                itemID: item.id,
                to: &inventory,
                catalog: catalog
            ),
            750
        )
        XCTAssertTrue(inventory.ownedFootballIDs.contains(LaunchFootballID.alternate))
    }

    func testEveryOffenseCanDeterministicallyReachAllOtherFifteenTeams() throws {
        let catalog = LaunchCatalog.approved
        let generator = MatchupGenerator(catalog: catalog)
        let inventory = PlayerInventory(
            ownedTeamIDs: Set(catalog.teams.map(\.id)),
            ownedJerseyIDs: Set(catalog.teams.flatMap(\.jerseys).map(\.id)),
            ownedFootballIDs: [LaunchFootballID.standard]
        )
        let startedAt = Date(timeIntervalSince1970: 500)
        let deterministicRunID = RunID(
            UUID(uuidString: "00000000-0000-4000-8000-000000000091")!
        )

        for offenseTeam in catalog.teams {
            let selection = PlayerSelection(
                selectedTeamID: offenseTeam.id,
                selectedJerseyByTeam: [
                    offenseTeam.id: offenseTeam.primaryJersey.id,
                ],
                selectedFootballID: LaunchFootballID.standard
            )
            let first = try generator.makeRunConfiguration(
                selection: selection,
                inventory: inventory,
                runID: deterministicRunID,
                seed: 91,
                startedAt: startedAt
            )
            let repeated = try generator.makeRunConfiguration(
                selection: selection,
                inventory: inventory,
                runID: deterministicRunID,
                seed: 91,
                startedAt: startedAt
            )
            XCTAssertEqual(first, repeated)
            XCTAssertNotEqual(first.offenseTeamID, first.defenseTeamID)

            var opponents = Set<TeamID>()
            for seed in UInt32(0) ..< 2_048 {
                let configuration = try generator.makeRunConfiguration(
                    selection: selection,
                    inventory: inventory,
                    seed: seed,
                    startedAt: startedAt
                )
                opponents.insert(configuration.defenseTeamID)
            }
            XCTAssertEqual(
                opponents,
                Set(catalog.teams.map(\.id)).subtracting([offenseTeam.id]),
                offenseTeam.id.rawValue
            )
        }
    }

    func testClashResolverCoversAll480OffenseJerseyOpponentPairsAndTieUsesPrimary() {
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

                    let configuration = RunConfiguration(
                        runID: RunID(),
                        randomSeed: UInt32(evaluatedPairs),
                        offenseTeamID: offenseTeam.id,
                        offenseJerseyID: offenseJersey.id,
                        defenseTeamID: defenseTeam.id,
                        defenseJerseyID: resolved.id,
                        footballID: LaunchFootballID.standard,
                        economyVersion: EconomyConfiguration.currentVersion,
                        startedAt: Date(timeIntervalSince1970: 1)
                    )
                    let roots = RunGameplayUniformAssetRoots(
                        configuration: configuration,
                        catalog: catalog
                    )
                    XCTAssertEqual(roots?.offense.jerseyID, offenseJersey.id)
                    XCTAssertEqual(roots?.defense.jerseyID, resolved.id)
                    let visual = LaunchVisualIdentityCatalog.approved.runIdentity(
                        for: configuration
                    )
                    XCTAssertEqual(visual?.offenseTeam.teamID, offenseTeam.id)
                    XCTAssertEqual(visual?.defenseTeam.teamID, defenseTeam.id)
                }
            }
        }
        XCTAssertEqual(evaluatedPairs, 480)

        let offense = catalog.teams[0].primaryJersey
        let defenseID = TeamID("tie_defense")
        let tiedPrimary = makeJersey(
            id: "jersey.tie_defense.primary",
            teamID: defenseID,
            kind: .primary,
            color: RGBColor(hex: "#101010")
        )
        let tiedAlternate = makeJersey(
            id: "jersey.tie_defense.alternate",
            teamID: defenseID,
            kind: .alternate,
            color: RGBColor(hex: "#101010")
        )
        let defense = TeamDescriptor(
            id: defenseID,
            displayName: "Tie Defense",
            initiallyOwned: false,
            primaryColor: tiedPrimary.primaryColor,
            secondaryColor: tiedAlternate.primaryColor,
            accentColor: RGBColor(hex: "#FFFFFF"),
            primaryJersey: tiedPrimary,
            alternateJersey: tiedAlternate,
            assets: TeamAssetKeys(
                logo: "teams/tie_defense/logo",
                endZone: "teams/tie_defense/end-zone",
                fieldBranding: "teams/tie_defense/field-branding"
            )
        )
        XCTAssertEqual(
            UniformClashResolver.resolve(offense: offense, defenseTeam: defense),
            tiedPrimary
        )
    }

    func testLegacyEightTeamDomainSelectionInventoryAndRunReferencesRemainValid()
        throws
    {
        let catalog = LaunchCatalog.approved
        var rememberedJerseys: [TeamID: JerseyID] = [:]
        for teamID in LaunchTeamID.originalEight {
            let team = try XCTUnwrap(catalog.team(id: teamID))
            rememberedJerseys[team.id] = team.primaryJersey.id
        }

        let luma = try XCTUnwrap(catalog.team(id: LaunchTeamID.lumaCoastPrisms))
        rememberedJerseys[luma.id] = luma.alternateJersey.id
        let legacySelection = PlayerSelection(
            selectedTeamID: luma.id,
            selectedJerseyByTeam: rememberedJerseys,
            selectedFootballID: LaunchFootballID.alternate
        )
        var legacyInventory = InventoryRules.initialInventory(catalog: catalog)
        legacyInventory.ownedTeamIDs.insert(luma.id)
        legacyInventory.ownedJerseyIDs.formUnion([
            luma.primaryJersey.id,
            luma.alternateJersey.id,
        ])
        legacyInventory.ownedFootballIDs.insert(LaunchFootballID.alternate)

        let decodedSelection = try JSONDecoder().decode(
            PlayerSelection.self,
            from: JSONEncoder().encode(legacySelection)
        )
        let decodedInventory = try JSONDecoder().decode(
            PlayerInventory.self,
            from: JSONEncoder().encode(legacyInventory)
        )

        try InventoryRules.validate(
            selection: decodedSelection,
            inventory: decodedInventory,
            catalog: catalog
        )
        XCTAssertEqual(decodedSelection, legacySelection)
        XCTAssertEqual(decodedInventory, legacyInventory)
        XCTAssertEqual(
            Set(decodedSelection.selectedJerseyByTeam.keys),
            Set(LaunchTeamID.originalEight)
        )
        XCTAssertTrue(
            Set(LaunchTeamID.expansionEight).isDisjoint(
                with: decodedInventory.ownedTeamIDs
            )
        )
        XCTAssertTrue(
            Set(
                LaunchTeamID.expansionEight.compactMap {
                    catalog.team(id: $0)?.primaryJersey.id
                }
            ).isDisjoint(with: decodedInventory.ownedJerseyIDs)
        )

        let highMesa = try XCTUnwrap(
            catalog.team(id: LaunchTeamID.highMesaHelions)
        )
        let legacyRun = RunConfiguration(
            runID: RunID(
                UUID(uuidString: "00000000-0000-4000-8000-000000000160")!
            ),
            randomSeed: 160,
            offenseTeamID: luma.id,
            offenseJerseyID: luma.alternateJersey.id,
            defenseTeamID: highMesa.id,
            defenseJerseyID: highMesa.primaryJersey.id,
            footballID: LaunchFootballID.alternate,
            economyVersion: 1,
            startedAt: Date(timeIntervalSince1970: 160)
        )
        let decodedRun = try JSONDecoder().decode(
            RunConfiguration.self,
            from: JSONEncoder().encode(legacyRun)
        )
        XCTAssertEqual(decodedRun, legacyRun)
        let roots = try XCTUnwrap(
            RunGameplayUniformAssetRoots(
                configuration: decodedRun,
                catalog: catalog
            )
        )
        XCTAssertEqual(
            roots.offense.relativePath,
            "characters/teams/luma_coast_prisms/alternate"
        )
        XCTAssertEqual(
            roots.defense.relativePath,
            "characters/teams/high_mesa_helions/primary"
        )
    }

    func testPreExpansionItemsRemainExactInExpandedCatalog() {
        let expected = Set([
            "unlock.football.football.alternate|football:football.alternate|750",
            "unlock.jersey.jersey.bayline_redshifts.alternate|alternate:jersey.bayline_redshifts.alternate|500",
            "unlock.jersey.jersey.foundry_reach_orbiters.alternate|alternate:jersey.foundry_reach_orbiters.alternate|500",
            "unlock.jersey.jersey.high_mesa_helions.alternate|alternate:jersey.high_mesa_helions.alternate|500",
            "unlock.jersey.jersey.luma_coast_prisms.alternate|alternate:jersey.luma_coast_prisms.alternate|500",
            "unlock.jersey.jersey.meridian_plains_radiants.alternate|alternate:jersey.meridian_plains_radiants.alternate|500",
            "unlock.jersey.jersey.neon_basin_eclipses.alternate|alternate:jersey.neon_basin_eclipses.alternate|500",
            "unlock.jersey.jersey.nova_city_comets.alternate|alternate:jersey.nova_city_comets.alternate|500",
            "unlock.jersey.jersey.rainport_auroras.alternate|alternate:jersey.rainport_auroras.alternate|500",
            "unlock.team.bayline_redshifts|team:bayline_redshifts|1500",
            "unlock.team.luma_coast_prisms|team:luma_coast_prisms|1500",
            "unlock.team.meridian_plains_radiants|team:meridian_plains_radiants|1500",
            "unlock.team.neon_basin_eclipses|team:neon_basin_eclipses|1500",
        ])
        let current = Set(
            LaunchCatalog.approved.unlockableItems
                .map(itemSignature)
                .filter(expected.contains)
        )
        XCTAssertEqual(current, expected)
    }

    func testCatalogTransitionFreezesPredecessorAndCurrentFingerprints() {
        let source = LaunchCatalogTransitionV1ToV2
            .sourcePersistedFingerprintMaterial
        let current = LaunchCatalog.approved.persistedFingerprintMaterial

        XCTAssertEqual(
            LaunchCatalogTransitionV1ToV2.sourceCatalogSemanticIdentifier,
            "pocket-vector-launch-catalog-persisted-semantics-v1"
        )
        XCTAssertEqual(
            LaunchCatalogTransitionV1ToV2.targetCatalogSemanticIdentifier,
            "pocket-vector-launch-catalog-persisted-semantics-v2"
        )
        XCTAssertEqual(
            source.count,
            LaunchCatalogTransitionV1ToV2.sourceCatalogMaterialCount
        )
        XCTAssertEqual(
            fingerprint(source),
            LaunchCatalogTransitionV1ToV2.sourceCatalogFingerprint
        )
        XCTAssertEqual(
            fingerprint(source),
            "74420bf94ecb3707676b6a784a9a1df36f784faac8b83f792b8cabee786d024b"
        )
        XCTAssertEqual(current.first, LaunchCatalog.persistedSemanticIdentifier)
        XCTAssertNotEqual(current, source)
        XCTAssertEqual(
            current.count,
            LaunchCatalogTransitionV1ToV2.targetCatalogMaterialCount
        )
        XCTAssertEqual(
            fingerprint(current),
            LaunchCatalogTransitionV1ToV2.targetCatalogFingerprint
        )
        XCTAssertEqual(
            LaunchCatalogTransitionV1ToV2.addedTeamIDs,
            LaunchTeamID.expansionEight
        )
        XCTAssertTrue(
            LaunchCatalogTransitionV1ToV2.persistedFingerprintMaterial
                .contains(LaunchCatalogTransitionV1ToV2.localEnvelopePolicyIdentifier)
        )

        let catalog = LaunchCatalog.approved
        let reordered = LaunchCatalog(
            teams: Array(catalog.teams.reversed()),
            footballs: Array(catalog.footballs.reversed()),
            unlockableItems: Array(catalog.unlockableItems.reversed())
        )
        XCTAssertEqual(
            catalog.persistedFingerprintMaterial,
            reordered.persistedFingerprintMaterial
        )
    }

    private func makeJersey(
        id: String,
        teamID: TeamID,
        kind: JerseyKind,
        color: RGBColor
    ) -> JerseyDescriptor {
        JerseyDescriptor(
            id: JerseyID(id),
            teamID: teamID,
            kind: kind,
            displayName: kind.rawValue,
            primaryColor: color,
            secondaryColor: RGBColor(hex: "#202020"),
            accentColor: RGBColor(hex: "#FFFFFF"),
            assets: JerseyAssetKeys(
                paletteToken: "teams/\(teamID.rawValue)/\(kind.rawValue)"
            )
        )
    }

    private func itemSignature(_ item: CatalogItemDescriptor) -> String {
        let kind: String
        switch item.kind {
        case let .team(teamID):
            kind = "team:\(teamID.rawValue)"
        case let .alternateJersey(jerseyID):
            kind = "alternate:\(jerseyID.rawValue)"
        case let .football(footballID):
            kind = "football:\(footballID.rawValue)"
        }
        return "\(item.id.rawValue)|\(kind)|\(item.price)"
    }

    private func fingerprint(_ components: [String]) -> String {
        var hasher = SHA256()
        for component in components {
            let data = Data(component.utf8)
            var length = UInt64(data.count).bigEndian
            withUnsafeBytes(of: &length) {
                hasher.update(data: Data($0))
            }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

import Foundation

enum LaunchTeamID {
    static let novaCityComets = TeamID("nova_city_comets")
    static let highMesaHelions = TeamID("high_mesa_helions")
    static let lumaCoastPrisms = TeamID("luma_coast_prisms")
    static let foundryReachOrbiters = TeamID("foundry_reach_orbiters")
    static let neonBasinEclipses = TeamID("neon_basin_eclipses")
    static let meridianPlainsRadiants = TeamID("meridian_plains_radiants")
    static let rainportAuroras = TeamID("rainport_auroras")
    static let baylineRedshifts = TeamID("bayline_redshifts")
    static let obsidianValeQuasars = TeamID("obsidian_vale_quasars")
    static let cobaltJunctionPulsars = TeamID("cobalt_junction_pulsars")
    static let copperHollowTremors = TeamID("copper_hollow_tremors")
    static let sunreefCurrents = TeamID("sunreef_currents")
    static let crownRiftArclights = TeamID("crown_rift_arclights")
    static let gildedDeltaMonarchs = TeamID("gilded_delta_monarchs")
    static let axiomPointGravitons = TeamID("axiom_point_gravitons")
    static let emeraldSpireVortices = TeamID("emerald_spire_vortices")

    static let originalEight = [
        novaCityComets,
        highMesaHelions,
        lumaCoastPrisms,
        foundryReachOrbiters,
        neonBasinEclipses,
        meridianPlainsRadiants,
        rainportAuroras,
        baylineRedshifts,
    ]

    static let expansionEight = [
        obsidianValeQuasars,
        cobaltJunctionPulsars,
        copperHollowTremors,
        sunreefCurrents,
        crownRiftArclights,
        gildedDeltaMonarchs,
        axiomPointGravitons,
        emeraldSpireVortices,
    ]
}

enum LaunchFootballID {
    static let standard = FootballID("football.standard")
    static let alternate = FootballID("football.alternate")
}

enum LaunchCatalogPersistedSemanticVersion {
    static let v1 = "pocket-vector-launch-catalog-persisted-semantics-v1"
    static let v2 = "pocket-vector-launch-catalog-persisted-semantics-v2"
}

struct LaunchCatalog: Equatable, Sendable {
    static let persistedSemanticIdentifier = LaunchCatalogPersistedSemanticVersion.v2

    let teams: [TeamDescriptor]
    let footballs: [FootballDescriptor]
    let unlockableItems: [CatalogItemDescriptor]

    init(
        teams: [TeamDescriptor],
        footballs: [FootballDescriptor],
        unlockableItems: [CatalogItemDescriptor]
    ) {
        precondition(Set(teams.map(\.id)).count == teams.count, "Team IDs must be unique")
        precondition(Set(footballs.map(\.id)).count == footballs.count, "Football IDs must be unique")
        precondition(
            Set(unlockableItems.map(\.id)).count == unlockableItems.count,
            "Catalog item IDs must be unique"
        )
        let jerseys = teams.flatMap(\.jerseys)
        precondition(
            Set(jerseys.map(\.id)).count == jerseys.count,
            "Jersey IDs must be globally unique"
        )
        precondition(
            teams.allSatisfy {
                $0.primaryJersey.teamID == $0.id
                    && $0.primaryJersey.kind == .primary
                    && $0.alternateJersey.teamID == $0.id
                    && $0.alternateJersey.kind == .alternate
            },
            "Every team must own one correctly classified primary and alternate jersey"
        )
        self.teams = teams
        self.footballs = footballs
        self.unlockableItems = unlockableItems
    }

    func team(id: TeamID) -> TeamDescriptor? {
        teams.first { $0.id == id }
    }

    func jersey(id: JerseyID) -> JerseyDescriptor? {
        teams.lazy.flatMap(\.jerseys).first { $0.id == id }
    }

    func football(id: FootballID) -> FootballDescriptor? {
        footballs.first { $0.id == id }
    }

    func item(id: CatalogItemID) -> CatalogItemDescriptor? {
        unlockableItems.first { $0.id == id }
    }

    /// Presentation order, display copy, palettes, and asset keys do not affect
    /// persisted ownership. Every persisted relationship is normalized by its
    /// stable identifier before entering the combined cloud scope.
    var persistedFingerprintMaterial: [String] {
        let orderedTeams = teams.sorted {
            $0.id.rawValue.utf8.lexicographicallyPrecedes($1.id.rawValue.utf8)
        }
        let orderedFootballs = footballs.sorted {
            $0.id.rawValue.utf8.lexicographicallyPrecedes($1.id.rawValue.utf8)
        }
        let orderedItems = unlockableItems.sorted {
            $0.id.rawValue.utf8.lexicographicallyPrecedes($1.id.rawValue.utf8)
        }
        let inventoryRules = InventoryRules.persistedFingerprintMaterial
        let transition = LaunchCatalogTransitionV1ToV2.persistedFingerprintMaterial

        var material = [
            Self.persistedSemanticIdentifier,
            "inventoryRuleMaterialCount", String(inventoryRules.count),
        ] + inventoryRules + [
            "transitionMaterialCount", String(transition.count),
        ] + transition

        material.append(contentsOf: ["teamCount", String(orderedTeams.count)])
        for team in orderedTeams {
            material.append(contentsOf: [
                "team", team.id.rawValue,
                "initiallyOwned", String(team.initiallyOwned),
                "primaryJerseyID", team.primaryJersey.id.rawValue,
                "primaryJerseyTeamID", team.primaryJersey.teamID.rawValue,
                "primaryJerseyKind", team.primaryJersey.kind.rawValue,
                "alternateJerseyID", team.alternateJersey.id.rawValue,
                "alternateJerseyTeamID", team.alternateJersey.teamID.rawValue,
                "alternateJerseyKind", team.alternateJersey.kind.rawValue,
            ])
        }

        material.append(contentsOf: [
            "footballCount", String(orderedFootballs.count),
        ])
        for football in orderedFootballs {
            material.append(contentsOf: [
                "football", football.id.rawValue,
                "initiallyOwned", String(football.initiallyOwned),
            ])
        }

        material.append(contentsOf: [
            "unlockableItemCount", String(orderedItems.count),
        ])
        for item in orderedItems {
            let kind = Self.persistedMaterial(for: item.kind)
            material.append(contentsOf: [
                "unlockableItem", item.id.rawValue,
                "kindMaterialCount", String(kind.count),
            ])
            material.append(contentsOf: kind)
            material.append(contentsOf: ["price", String(item.price)])
        }
        return material
    }

    static let approved: LaunchCatalog = {
        let teams = [
            makeTeam(
                id: LaunchTeamID.novaCityComets,
                name: "Nova City Comets",
                initiallyOwned: true,
                primary: RGBColor(hex: "#1DE6EF"),
                secondary: RGBColor(hex: "#7D4DFF"),
                accent: RGBColor(hex: "#F7FCFF")
            ),
            makeTeam(
                id: LaunchTeamID.highMesaHelions,
                name: "High Mesa Helions",
                initiallyOwned: true,
                primary: RGBColor(hex: "#F06A3B"),
                secondary: RGBColor(hex: "#2B234D"),
                accent: RGBColor(hex: "#D8F0EC")
            ),
            makeTeam(
                id: LaunchTeamID.lumaCoastPrisms,
                name: "Luma Coast Prisms",
                initiallyOwned: false,
                primary: RGBColor(hex: "#63CFE7"),
                secondary: RGBColor(hex: "#30214F"),
                accent: RGBColor(hex: "#F4C64E")
            ),
            makeTeam(
                id: LaunchTeamID.foundryReachOrbiters,
                name: "Foundry Reach Orbiters",
                initiallyOwned: true,
                primary: RGBColor(hex: "#146353"),
                secondary: RGBColor(hex: "#D4A73E"),
                accent: RGBColor(hex: "#F0E8CF")
            ),
            makeTeam(
                id: LaunchTeamID.neonBasinEclipses,
                name: "Neon Basin Eclipses",
                initiallyOwned: false,
                primary: RGBColor(hex: "#171923"),
                secondary: RGBColor(hex: "#ADB5C2"),
                accent: RGBColor(hex: "#A05CFF")
            ),
            makeTeam(
                id: LaunchTeamID.meridianPlainsRadiants,
                name: "Meridian Plains Radiants",
                initiallyOwned: false,
                primary: RGBColor(hex: "#C72F4F"),
                secondary: RGBColor(hex: "#F0A253"),
                accent: RGBColor(hex: "#FFF0DD")
            ),
            makeTeam(
                id: LaunchTeamID.rainportAuroras,
                name: "Rainport Auroras",
                initiallyOwned: true,
                primary: RGBColor(hex: "#0B3A4A"),
                secondary: RGBColor(hex: "#9DD643"),
                accent: RGBColor(hex: "#E5F2EA")
            ),
            makeTeam(
                id: LaunchTeamID.baylineRedshifts,
                name: "Bayline Redshifts",
                initiallyOwned: false,
                primary: RGBColor(hex: "#842C4B"),
                secondary: RGBColor(hex: "#C87845"),
                accent: RGBColor(hex: "#DFE5E2")
            ),
            makeTeam(
                id: LaunchTeamID.obsidianValeQuasars,
                name: "Obsidian Vale Quasars",
                initiallyOwned: false,
                primary: RGBColor(hex: "#0B0D10"),
                secondary: RGBColor(hex: "#E5484D"),
                accent: RGBColor(hex: "#C5CFD8")
            ),
            makeTeam(
                id: LaunchTeamID.cobaltJunctionPulsars,
                name: "Cobalt Junction Pulsars",
                initiallyOwned: false,
                primary: RGBColor(hex: "#14284F"),
                secondary: RGBColor(hex: "#72C9F2"),
                accent: RGBColor(hex: "#F26678")
            ),
            makeTeam(
                id: LaunchTeamID.copperHollowTremors,
                name: "Copper Hollow Tremors",
                initiallyOwned: false,
                primary: RGBColor(hex: "#43271D"),
                secondary: RGBColor(hex: "#F57422"),
                accent: RGBColor(hex: "#F3DFC1")
            ),
            makeTeam(
                id: LaunchTeamID.sunreefCurrents,
                name: "Sunreef Currents",
                initiallyOwned: false,
                primary: RGBColor(hex: "#003F3C"),
                secondary: RGBColor(hex: "#FF8C72"),
                accent: RGBColor(hex: "#F4E8D8")
            ),
            makeTeam(
                id: LaunchTeamID.crownRiftArclights,
                name: "Crown Rift Arclights",
                initiallyOwned: false,
                primary: RGBColor(hex: "#40215F"),
                secondary: RGBColor(hex: "#D9AE36"),
                accent: RGBColor(hex: "#F2EAF8")
            ),
            makeTeam(
                id: LaunchTeamID.gildedDeltaMonarchs,
                name: "Gilded Delta Monarchs",
                initiallyOwned: false,
                primary: RGBColor(hex: "#26303B"),
                secondary: RGBColor(hex: "#C2A36A"),
                accent: RGBColor(hex: "#F6F0E4")
            ),
            makeTeam(
                id: LaunchTeamID.axiomPointGravitons,
                name: "Axiom Point Gravitons",
                initiallyOwned: false,
                primary: RGBColor(hex: "#1648B8"),
                secondary: RGBColor(hex: "#EFCB32"),
                accent: RGBColor(hex: "#F4F7FC")
            ),
            makeTeam(
                id: LaunchTeamID.emeraldSpireVortices,
                name: "Emerald Spire Vortices",
                initiallyOwned: false,
                primary: RGBColor(hex: "#0D8642"),
                secondary: RGBColor(hex: "#000000"),
                accent: RGBColor(hex: "#FFFFFF")
            ),
        ]

        let footballs = [
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

        var items = teams.filter { !$0.initiallyOwned }.map { team in
            CatalogItemDescriptor(
                id: CatalogItemID("unlock.team.\(team.id.rawValue)"),
                displayName: team.displayName,
                kind: .team(team.id),
                price: EconomyConfiguration.lockedTeamPrice
            )
        }
        items += teams.map { team in
            CatalogItemDescriptor(
                id: CatalogItemID("unlock.jersey.\(team.alternateJersey.id.rawValue)"),
                displayName: "\(team.displayName) Alternate Jersey",
                kind: .alternateJersey(team.alternateJersey.id),
                price: EconomyConfiguration.alternateJerseyPrice
            )
        }
        items.append(
            CatalogItemDescriptor(
                id: CatalogItemID("unlock.football.\(LaunchFootballID.alternate.rawValue)"),
                displayName: "Alternate Football",
                kind: .football(LaunchFootballID.alternate),
                price: EconomyConfiguration.alternateFootballPrice
            )
        )

        return LaunchCatalog(teams: teams, footballs: footballs, unlockableItems: items)
    }()

    private static func makeTeam(
        id: TeamID,
        name: String,
        initiallyOwned: Bool,
        primary: RGBColor,
        secondary: RGBColor,
        accent: RGBColor
    ) -> TeamDescriptor {
        let primaryJersey = JerseyDescriptor(
            id: JerseyID("jersey.\(id.rawValue).primary"),
            teamID: id,
            kind: .primary,
            displayName: "Primary",
            primaryColor: primary,
            secondaryColor: secondary,
            accentColor: accent,
            assets: JerseyAssetKeys(paletteToken: "teams/\(id.rawValue)/primary")
        )
        let alternateJersey = JerseyDescriptor(
            id: JerseyID("jersey.\(id.rawValue).alternate"),
            teamID: id,
            kind: .alternate,
            displayName: "Alternate",
            primaryColor: secondary,
            secondaryColor: accent,
            accentColor: primary,
            assets: JerseyAssetKeys(paletteToken: "teams/\(id.rawValue)/alternate")
        )
        return TeamDescriptor(
            id: id,
            displayName: name,
            initiallyOwned: initiallyOwned,
            primaryColor: primary,
            secondaryColor: secondary,
            accentColor: accent,
            primaryJersey: primaryJersey,
            alternateJersey: alternateJersey,
            assets: TeamAssetKeys(
                logo: "teams/\(id.rawValue)/logo",
                endZone: "teams/\(id.rawValue)/end-zone",
                fieldBranding: "teams/\(id.rawValue)/field-branding"
            )
        )
    }

    private static func persistedMaterial(
        for kind: CatalogItemKind
    ) -> [String] {
        switch kind {
        case let .team(teamID):
            ["kind", "team", "targetTeamID", teamID.rawValue]
        case let .alternateJersey(jerseyID):
            [
                "kind", "alternateJersey",
                "targetJerseyID", jerseyID.rawValue,
            ]
        case let .football(footballID):
            ["kind", "football", "targetFootballID", footballID.rawValue]
        }
    }
}

/// Frozen Technical contract for advancing the permanent product catalog from the original
/// eight-team Build 160 scope to the additive sixteen-team Version 1.1 scope. Persistence and
/// cloud services can use `sourcePersistedFingerprintMaterial` to reconstruct the exact
/// predecessor scope without consulting the live catalog.
enum LaunchCatalogTransitionV1ToV2 {
    static let persistedSemanticIdentifier =
        "pocket-vector-launch-catalog-transition-v1-to-v2"
    static let sourceCatalogSemanticIdentifier = LaunchCatalogPersistedSemanticVersion.v1
    static let targetCatalogSemanticIdentifier = LaunchCatalogPersistedSemanticVersion.v2
    static let fingerprintAlgorithmIdentifier =
        "sha256-uint64-big-endian-length-prefixed-components-v1"
    static let sourceCatalogMaterialCount = 292
    static let sourceCatalogFingerprint =
        "74420bf94ecb3707676b6a784a9a1df36f784faac8b83f792b8cabee786d024b"
    /// The target checksum cannot be embedded in its own material. Focused tests bind this
    /// externally reported checksum to the complete live V2 material instead.
    static let targetCatalogMaterialCount = 915
    static let targetCatalogFingerprint =
        "8b3414aed40d704d8cb6688e0ac99116b8b05391dcc6fe48e6995433efd74e8d"

    static let localEnvelopePolicyIdentifier =
        "additive-identifiers-require-no-local-profile-envelope-version-change-v1"
    static let ownershipPolicyIdentifier =
        "preserve-existing-inventory-and-ledger-expansion-teams-start-locked-v1"
    static let selectionPolicyIdentifier =
        "preserve-existing-selection-missing-expansion-jersey-memory-is-valid-v1"
    static let unlockPolicyIdentifier =
        "new-team-unlock-grants-primary-and-alternate-remains-separate-v1"
    static let runHistoryPolicyIdentifier =
        "preserve-recorded-team-and-jersey-identifiers-never-regenerate-matchups-v1"
    static let cloudScopePolicyIdentifier =
        "reconstruct-source-from-frozen-v1-material-and-target-from-live-v2-material-v1"

    static let addedTeamIDs = [
        TeamID("obsidian_vale_quasars"),
        TeamID("cobalt_junction_pulsars"),
        TeamID("copper_hollow_tremors"),
        TeamID("sunreef_currents"),
        TeamID("crown_rift_arclights"),
        TeamID("gilded_delta_monarchs"),
        TeamID("axiom_point_gravitons"),
        TeamID("emerald_spire_vortices"),
    ]

    /// This material intentionally contains no reference to `LaunchCatalog.approved`,
    /// `InventoryRules`, or live economy prices.
    static let sourcePersistedFingerprintMaterial: [String] = {
        let inventoryRules = [
            "pocket-vector-inventory-rules-persisted-semantics-v1",
            "initialInventoryPolicy",
            "initially-owned-teams-grant-primary-jerseys-and-initial-footballs-v1",
            "selectionValidationPolicy",
            "owned-team-associated-owned-jersey-and-owned-football-v1",
            "unlockTransitionPolicy",
            "team-grants-primary-alternate-requires-team-football-grants-global-v1",
            "defaultSelectionPolicy",
            "fixed-team-all-team-primaries-and-fixed-football-v1",
            "unlockReplayOrderingPolicy",
            "team-before-alternate-before-football-then-item-id-v1",
            "defaultSelectedTeamID",
            "nova_city_comets",
            "defaultSelectedJerseyPolicy",
            "primary-jersey-for-each-team-v1",
            "defaultSelectedFootballID",
            "football.standard",
        ]
        let teams: [(id: String, initiallyOwned: Bool)] = [
            ("bayline_redshifts", false),
            ("foundry_reach_orbiters", true),
            ("high_mesa_helions", true),
            ("luma_coast_prisms", false),
            ("meridian_plains_radiants", false),
            ("neon_basin_eclipses", false),
            ("nova_city_comets", true),
            ("rainport_auroras", true),
        ]
        let items: [(
            id: String,
            kind: String,
            targetLabel: String,
            targetID: String,
            price: String
        )] = [
            (
                "unlock.football.football.alternate",
                "football",
                "targetFootballID",
                "football.alternate",
                "750"
            ),
            (
                "unlock.jersey.jersey.bayline_redshifts.alternate",
                "alternateJersey",
                "targetJerseyID",
                "jersey.bayline_redshifts.alternate",
                "500"
            ),
            (
                "unlock.jersey.jersey.foundry_reach_orbiters.alternate",
                "alternateJersey",
                "targetJerseyID",
                "jersey.foundry_reach_orbiters.alternate",
                "500"
            ),
            (
                "unlock.jersey.jersey.high_mesa_helions.alternate",
                "alternateJersey",
                "targetJerseyID",
                "jersey.high_mesa_helions.alternate",
                "500"
            ),
            (
                "unlock.jersey.jersey.luma_coast_prisms.alternate",
                "alternateJersey",
                "targetJerseyID",
                "jersey.luma_coast_prisms.alternate",
                "500"
            ),
            (
                "unlock.jersey.jersey.meridian_plains_radiants.alternate",
                "alternateJersey",
                "targetJerseyID",
                "jersey.meridian_plains_radiants.alternate",
                "500"
            ),
            (
                "unlock.jersey.jersey.neon_basin_eclipses.alternate",
                "alternateJersey",
                "targetJerseyID",
                "jersey.neon_basin_eclipses.alternate",
                "500"
            ),
            (
                "unlock.jersey.jersey.nova_city_comets.alternate",
                "alternateJersey",
                "targetJerseyID",
                "jersey.nova_city_comets.alternate",
                "500"
            ),
            (
                "unlock.jersey.jersey.rainport_auroras.alternate",
                "alternateJersey",
                "targetJerseyID",
                "jersey.rainport_auroras.alternate",
                "500"
            ),
            (
                "unlock.team.bayline_redshifts",
                "team",
                "targetTeamID",
                "bayline_redshifts",
                "1500"
            ),
            (
                "unlock.team.luma_coast_prisms",
                "team",
                "targetTeamID",
                "luma_coast_prisms",
                "1500"
            ),
            (
                "unlock.team.meridian_plains_radiants",
                "team",
                "targetTeamID",
                "meridian_plains_radiants",
                "1500"
            ),
            (
                "unlock.team.neon_basin_eclipses",
                "team",
                "targetTeamID",
                "neon_basin_eclipses",
                "1500"
            ),
        ]

        var material = [
            sourceCatalogSemanticIdentifier,
            "inventoryRuleMaterialCount", String(inventoryRules.count),
        ] + inventoryRules + [
            "teamCount", String(teams.count),
        ]
        for team in teams {
            material.append(contentsOf: [
                "team", team.id,
                "initiallyOwned", String(team.initiallyOwned),
                "primaryJerseyID", "jersey.\(team.id).primary",
                "primaryJerseyTeamID", team.id,
                "primaryJerseyKind", "primary",
                "alternateJerseyID", "jersey.\(team.id).alternate",
                "alternateJerseyTeamID", team.id,
                "alternateJerseyKind", "alternate",
            ])
        }
        material.append(contentsOf: [
            "footballCount", "2",
            "football", "football.alternate",
            "initiallyOwned", "false",
            "football", "football.standard",
            "initiallyOwned", "true",
            "unlockableItemCount", String(items.count),
        ])
        for item in items {
            material.append(contentsOf: [
                "unlockableItem", item.id,
                "kindMaterialCount", "4",
                "kind", item.kind,
                item.targetLabel, item.targetID,
                "price", item.price,
            ])
        }
        return material
    }()

    static var persistedFingerprintMaterial: [String] {
        [
            persistedSemanticIdentifier,
            "sourceCatalogSemanticIdentifier", sourceCatalogSemanticIdentifier,
            "targetCatalogSemanticIdentifier", targetCatalogSemanticIdentifier,
            "fingerprintAlgorithm", fingerprintAlgorithmIdentifier,
            "sourceCatalogFingerprint", sourceCatalogFingerprint,
            "localEnvelopePolicy", localEnvelopePolicyIdentifier,
            "ownershipPolicy", ownershipPolicyIdentifier,
            "selectionPolicy", selectionPolicyIdentifier,
            "unlockPolicy", unlockPolicyIdentifier,
            "runHistoryPolicy", runHistoryPolicyIdentifier,
            "cloudScopePolicy", cloudScopePolicyIdentifier,
            "addedTeamCount", String(addedTeamIDs.count),
        ] + addedTeamIDs.flatMap { ["addedTeamID", $0.rawValue] } + [
            "sourceCatalogMaterialCount",
            String(sourcePersistedFingerprintMaterial.count),
        ] + sourcePersistedFingerprintMaterial
    }
}

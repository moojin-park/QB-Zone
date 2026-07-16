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
}

enum LaunchFootballID {
    static let standard = FootballID("football.standard")
    static let alternate = FootballID("football.alternate")
}

struct LaunchCatalog: Equatable, Sendable {
    static let persistedSemanticIdentifier =
        "pocket-vector-launch-catalog-persisted-semantics-v1"

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

        var material = [
            Self.persistedSemanticIdentifier,
            "inventoryRuleMaterialCount", String(inventoryRules.count),
        ] + inventoryRules

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

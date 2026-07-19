import Foundation

// This file intentionally contains presentation data only. Its normalized geometry and RGB
// values can be converted by either SwiftUI or SpriteKit without importing either framework.

enum BrandPaletteRole: String, CaseIterable, Codable, Hashable, Sendable {
    case primary
    case secondary
    case accent
}

struct TeamBrandPalette: Codable, Equatable, Hashable, Sendable {
    let primary: RGBColor
    let secondary: RGBColor
    let accent: RGBColor

    func color(for role: BrandPaletteRole) -> RGBColor {
        switch role {
        case .primary: primary
        case .secondary: secondary
        case .accent: accent
        }
    }
}

struct UnitPoint2D: Codable, Equatable, Hashable, Sendable {
    let x: Double
    let y: Double
}

struct UnitRect2D: Codable, Equatable, Hashable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

/// Geometry is expressed on a zero-to-one canvas. Emblems cannot contain text, which keeps
/// letterforms and monograms out of the logo layer by construction.
enum EmblemPrimitive: Codable, Equatable, Hashable, Sendable {
    case disk(center: UnitPoint2D, radius: Double, fill: BrandPaletteRole)
    case ring(
        center: UnitPoint2D,
        radius: Double,
        lineWidth: Double,
        color: BrandPaletteRole
    )
    case arc(
        center: UnitPoint2D,
        radius: Double,
        startDegrees: Double,
        endDegrees: Double,
        lineWidth: Double,
        color: BrandPaletteRole
    )
    case polygon(vertices: [UnitPoint2D], fill: BrandPaletteRole)
    case polyline(
        vertices: [UnitPoint2D],
        lineWidth: Double,
        color: BrandPaletteRole
    )
    case roundedBar(
        frame: UnitRect2D,
        cornerRadius: Double,
        fill: BrandPaletteRole
    )

    var usesNormalizedCanvas: Bool {
        func contains(_ point: UnitPoint2D) -> Bool {
            (0 ... 1).contains(point.x) && (0 ... 1).contains(point.y)
        }

        func containsCircle(center: UnitPoint2D, radius: Double) -> Bool {
            contains(center) && radius > 0
                && center.x - radius >= 0 && center.x + radius <= 1
                && center.y - radius >= 0 && center.y + radius <= 1
        }

        func contains(_ frame: UnitRect2D) -> Bool {
            frame.x >= 0 && frame.y >= 0 && frame.width > 0 && frame.height > 0
                && frame.x + frame.width <= 1 && frame.y + frame.height <= 1
        }

        switch self {
        case let .disk(center, radius, _), let .ring(center, radius, _, _):
            return containsCircle(center: center, radius: radius)
        case let .arc(center, radius, _, _, lineWidth, _):
            return containsCircle(center: center, radius: radius) && lineWidth > 0
        case let .polygon(vertices, _):
            return vertices.count >= 3 && vertices.allSatisfy(contains)
        case let .polyline(vertices, lineWidth, _):
            return vertices.count >= 2 && lineWidth > 0 && vertices.allSatisfy(contains)
        case let .roundedBar(frame, cornerRadius, _):
            return contains(frame) && cornerRadius >= 0
                && cornerRadius <= min(frame.width, frame.height) / 2
        }
    }
}

enum EmblemMotif: String, CaseIterable, Codable, Hashable, Sendable {
    case cometOrbit
    case solarMesa
    case splitBeamPrism
    case rivetedOrbit
    case offsetEclipse
    case reactorCore
    case auroraGridWave
    case redshiftBars
}

enum UnitCanvasOrigin: String, Codable, Equatable, Hashable, Sendable {
    case bottomLeading
}

struct EmblemDefinition: Codable, Equatable, Hashable, Sendable {
    let motif: EmblemMotif
    let coordinateOrigin: UnitCanvasOrigin
    let primitives: [EmblemPrimitive]

    init(
        motif: EmblemMotif,
        coordinateOrigin: UnitCanvasOrigin = .bottomLeading,
        primitives: [EmblemPrimitive]
    ) {
        self.motif = motif
        self.coordinateOrigin = coordinateOrigin
        self.primitives = primitives
    }
}

enum WordmarkLayout: String, Codable, Equatable, Hashable, Sendable {
    case orbitStack
    case horizonStack
    case splitBeam
    case ringStack
    case offsetStack
    case coreStack
    case waveStack
    case recedingStack
}

enum WordmarkAlignment: String, Codable, Equatable, Hashable, Sendable {
    case leading
    case centered
    case trailing
}

struct TeamWordmarkTreatment: Codable, Equatable, Hashable, Sendable {
    let marketLine: String
    let nicknameLine: String
    let layout: WordmarkLayout
    let alignment: WordmarkAlignment
    let marketColor: BrandPaletteRole
    let nicknameColor: BrandPaletteRole
    let tracking: Double
    let slantDegrees: Double
}

enum EndZoneMotifLayout: String, Codable, Equatable, Hashable, Sendable {
    case mirroredCorners
    case horizonBand
    case splitRays
    case rivetRail
    case offsetDisks
    case radialCore
    case waveBands
    case frequencySteps
}

struct EndZoneTreatment: Codable, Equatable, Hashable, Sendable {
    let background: BrandPaletteRole
    let boundary: BrandPaletteRole
    let wordmark: BrandPaletteRole
    let motif: BrandPaletteRole
    let motifLayout: EndZoneMotifLayout
    let motifOpacity: Double
    let motifRepeatCount: Int
}

struct HUDVisualPalette: Codable, Equatable, Hashable, Sendable {
    let primary: RGBColor
    let secondary: RGBColor
    let accent: RGBColor
}

enum UniformSquadRole: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case offense
    case defense
}

/// Named slots correspond to shared sprite masks rather than individual uniform image sets.
struct UniformSpritePalette: Codable, Equatable, Hashable, Sendable {
    let jerseyBody: RGBColor
    let shoulderPanel: RGBColor
    let numberAndName: RGBColor
    let trim: RGBColor
    let helmetShell: RGBColor
    let helmetDetail: RGBColor
    let pants: RGBColor
    let socks: RGBColor
}

struct JerseyVisualIdentity: Codable, Equatable, Hashable, Sendable {
    let jerseyID: JerseyID
    let teamID: TeamID
    let kind: JerseyKind
    let offense: UniformSpritePalette
    let defense: UniformSpritePalette

    func palette(for role: UniformSquadRole) -> UniformSpritePalette {
        switch role {
        case .offense: offense
        case .defense: defense
        }
    }
}

struct TeamVisualIdentity: Codable, Equatable, Hashable, Sendable {
    let teamID: TeamID
    let displayName: String
    let palette: TeamBrandPalette
    let emblem: EmblemDefinition
    let wordmark: TeamWordmarkTreatment
    let endZone: EndZoneTreatment
    let hud: HUDVisualPalette
    let jerseys: [JerseyVisualIdentity]
}

enum FootballPanelTreatment: String, Codable, Equatable, Hashable, Sendable {
    case orbitalSeam
    case vectorArcBands
}

struct FootballVisualStyle: Codable, Equatable, Hashable, Sendable {
    let footballID: FootballID
    let panelTreatment: FootballPanelTreatment
    let surface: RGBColor
    let seam: RGBColor
    let laces: RGBColor
    let detail: RGBColor
}

/// Fully resolved presentation data for one immutable run. The resolver deliberately follows
/// the jersey IDs already selected by `MatchupGenerator`; this keeps uniform-clash resolution in
/// the catalog layer and prevents rendering from silently choosing a different defense uniform.
struct RunVisualIdentity: Equatable, Sendable {
    let offenseTeam: TeamVisualIdentity
    let offenseUniform: UniformSpritePalette
    let defenseTeam: TeamVisualIdentity
    let defenseUniform: UniformSpritePalette
    let football: FootballVisualStyle
}

/// The launch visual catalog validates the supplied product catalog before exposing any data.
/// Unknown teams, cross-team jersey IDs, and unknown football IDs return nil rather than falling
/// back to another identity.
struct LaunchVisualIdentityCatalog: Sendable {
    let allTeams: [TeamVisualIdentity]
    let allFootballStyles: [FootballVisualStyle]

    private let teamsByID: [TeamID: TeamVisualIdentity]
    private let footballsByID: [FootballID: FootballVisualStyle]

    static let approved: LaunchVisualIdentityCatalog = {
        guard let catalog = LaunchVisualIdentityCatalog(catalog: .approved) else {
            preconditionFailure("Approved launch catalog does not match visual identity data")
        }
        return catalog
    }()

    init?(catalog: LaunchCatalog) {
        let specs = Self.identitySpecs
        guard catalog.teams.count == specs.count,
              Set(catalog.teams.map(\.id)) == Set(specs.keys),
              catalog.footballs.count == Self.footballStyles.count,
              Set(catalog.footballs.map(\.id)) == Set(Self.footballStyles.keys)
        else {
            return nil
        }

        var identities: [TeamVisualIdentity] = []
        identities.reserveCapacity(catalog.teams.count)

        for team in catalog.teams {
            guard let spec = specs[team.id],
                  Self.matchesApprovedDescriptor(team, spec: spec)
            else {
                return nil
            }

            let brandPalette = TeamBrandPalette(
                primary: team.primaryColor,
                secondary: team.secondaryColor,
                accent: team.accentColor
            )
            let jerseys = team.jerseys.map(Self.makeJerseyIdentity)
            identities.append(
                TeamVisualIdentity(
                    teamID: team.id,
                    displayName: team.displayName,
                    palette: spec.emblemPalette,
                    emblem: spec.emblem,
                    wordmark: spec.wordmark,
                    endZone: spec.endZone,
                    hud: HUDVisualPalette(
                        primary: brandPalette.primary,
                        secondary: brandPalette.secondary,
                        accent: brandPalette.accent
                    ),
                    jerseys: jerseys
                )
            )
        }

        let footballs = catalog.footballs.compactMap { Self.footballStyles[$0.id] }
        guard footballs.count == catalog.footballs.count else { return nil }

        allTeams = identities
        allFootballStyles = footballs
        teamsByID = Dictionary(uniqueKeysWithValues: identities.map { ($0.teamID, $0) })
        footballsByID = Dictionary(uniqueKeysWithValues: footballs.map { ($0.footballID, $0) })
    }

    var allJerseys: [JerseyVisualIdentity] {
        allTeams.flatMap(\.jerseys)
    }

    func team(id: TeamID) -> TeamVisualIdentity? {
        teamsByID[id]
    }

    func jersey(teamID: TeamID, jerseyID: JerseyID) -> JerseyVisualIdentity? {
        guard let team = teamsByID[teamID] else { return nil }
        return team.jerseys.first { $0.jerseyID == jerseyID && $0.teamID == teamID }
    }

    func uniform(
        teamID: TeamID,
        jerseyID: JerseyID,
        role: UniformSquadRole
    ) -> UniformSpritePalette? {
        jersey(teamID: teamID, jerseyID: jerseyID)?.palette(for: role)
    }

    func football(id: FootballID) -> FootballVisualStyle? {
        footballsByID[id]
    }

    func runIdentity(for configuration: RunConfiguration) -> RunVisualIdentity? {
        guard configuration.offenseTeamID != configuration.defenseTeamID,
              let offenseTeam = team(id: configuration.offenseTeamID),
              let offenseUniform = uniform(
                  teamID: configuration.offenseTeamID,
                  jerseyID: configuration.offenseJerseyID,
                  role: .offense
              ),
              let defenseTeam = team(id: configuration.defenseTeamID),
              let defenseUniform = uniform(
                  teamID: configuration.defenseTeamID,
                  jerseyID: configuration.defenseJerseyID,
                  role: .defense
              ),
              let football = football(id: configuration.footballID)
        else {
            return nil
        }

        return RunVisualIdentity(
            offenseTeam: offenseTeam,
            offenseUniform: offenseUniform,
            defenseTeam: defenseTeam,
            defenseUniform: defenseUniform,
            football: football
        )
    }
}

private extension LaunchVisualIdentityCatalog {
    struct IdentitySpec: Sendable {
        let displayName: String
        /// Catalog colors remain authoritative for uniforms, HUD, and descriptor validation.
        let palette: TeamBrandPalette
        /// Emblems use a deliberately independent material palette so their small-scale marks
        /// can stay distinctive without changing team uniforms or other catalog-owned colors.
        let emblemPalette: TeamBrandPalette
        let emblem: EmblemDefinition
        let wordmark: TeamWordmarkTreatment
        let endZone: EndZoneTreatment
    }

    static func p(_ x: Double, _ y: Double) -> UnitPoint2D {
        UnitPoint2D(x: x, y: y)
    }

    static func rect(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> UnitRect2D {
        UnitRect2D(x: x, y: y, width: width, height: height)
    }

    static func palette(_ primary: String, _ secondary: String, _ accent: String) -> TeamBrandPalette {
        TeamBrandPalette(
            primary: RGBColor(hex: primary),
            secondary: RGBColor(hex: secondary),
            accent: RGBColor(hex: accent)
        )
    }

    static func wordmark(
        market: String,
        nickname: String,
        layout: WordmarkLayout,
        alignment: WordmarkAlignment,
        tracking: Double,
        slant: Double = 0
    ) -> TeamWordmarkTreatment {
        TeamWordmarkTreatment(
            marketLine: market,
            nicknameLine: nickname,
            layout: layout,
            alignment: alignment,
            marketColor: .accent,
            nicknameColor: .primary,
            tracking: tracking,
            slantDegrees: slant
        )
    }

    static func endZone(
        layout: EndZoneMotifLayout,
        repeatCount: Int,
        background: BrandPaletteRole = .secondary
    ) -> EndZoneTreatment {
        EndZoneTreatment(
            background: background,
            boundary: .accent,
            wordmark: .accent,
            motif: .primary,
            motifLayout: layout,
            motifOpacity: 0.28,
            motifRepeatCount: repeatCount
        )
    }

    static let identitySpecs: [TeamID: IdentitySpec] = [
        LaunchTeamID.novaCityComets: IdentitySpec(
            displayName: "Nova City Comets",
            palette: palette("#1DE6EF", "#7D4DFF", "#F7FCFF"),
            emblemPalette: palette("#08B59F", "#F4C64E", "#F7FCFF"),
            emblem: EmblemDefinition(
                motif: .cometOrbit,
                primitives: [
                    // Layered teal plasma trail, kept broad enough to survive the 42-point badge.
                    .polygon(
                        vertices: [
                            p(0.08, 0.43), p(0.34, 0.38), p(0.62, 0.45),
                            p(0.47, 0.54), p(0.20, 0.57),
                        ],
                        fill: .primary
                    ),
                    .polygon(
                        vertices: [
                            p(0.13, 0.35), p(0.39, 0.37), p(0.63, 0.45),
                            p(0.40, 0.45), p(0.22, 0.50),
                        ],
                        fill: .accent
                    ),
                    .arc(
                        center: p(0.71, 0.47), radius: 0.22, startDegrees: 198,
                        endDegrees: 514, lineWidth: 0.065, color: .primary
                    ),
                    .polygon(
                        vertices: [
                            p(0.26, 0.79), p(0.49, 0.70), p(0.62, 0.57),
                            p(0.42, 0.69),
                        ],
                        fill: .secondary
                    ),
                    .disk(center: p(0.71, 0.47), radius: 0.145, fill: .accent),
                    .ring(
                        center: p(0.71, 0.47), radius: 0.19,
                        lineWidth: 0.055, color: .primary
                    ),
                    .disk(center: p(0.16, 0.66), radius: 0.018, fill: .secondary),
                    .disk(center: p(0.22, 0.30), radius: 0.014, fill: .accent),
                ]
            ),
            wordmark: wordmark(
                market: "NOVA CITY", nickname: "COMETS", layout: .orbitStack,
                alignment: .trailing, tracking: 0.11, slant: -8
            ),
            endZone: endZone(layout: .mirroredCorners, repeatCount: 2)
        ),
        LaunchTeamID.highMesaHelions: IdentitySpec(
            displayName: "High Mesa Helions",
            palette: palette("#F06A3B", "#2B234D", "#D8F0EC"),
            emblemPalette: palette("#F06A3B", "#6F35C5", "#D8F0EC"),
            emblem: EmblemDefinition(
                motif: .solarMesa,
                primitives: [
                    .disk(center: p(0.50, 0.34), radius: 0.20, fill: .primary),
                    .arc(
                        center: p(0.50, 0.34), radius: 0.13, startDegrees: 110,
                        endDegrees: 175, lineWidth: 0.025, color: .accent
                    ),
                    .polygon(
                        vertices: [
                            p(0.12, 0.76), p(0.28, 0.54), p(0.43, 0.54),
                            p(0.51, 0.43), p(0.61, 0.60), p(0.78, 0.60), p(0.90, 0.76),
                        ],
                        fill: .secondary
                    ),
                    .polyline(
                        vertices: [p(0.20, 0.72), p(0.45, 0.54), p(0.74, 0.70)],
                        lineWidth: 0.025, color: .accent
                    ),
                    .polyline(
                        vertices: [p(0.13, 0.80), p(0.50, 0.80), p(0.87, 0.80)],
                        lineWidth: 0.045, color: .accent
                    ),
                ]
            ),
            wordmark: wordmark(
                market: "HIGH MESA", nickname: "HELIONS", layout: .horizonStack,
                alignment: .centered, tracking: 0.07
            ),
            endZone: endZone(layout: .horizonBand, repeatCount: 3)
        ),
        LaunchTeamID.lumaCoastPrisms: IdentitySpec(
            displayName: "Luma Coast Prisms",
            palette: palette("#63CFE7", "#30214F", "#F4C64E"),
            emblemPalette: palette("#63CFE7", "#54308F", "#F4C64E"),
            emblem: EmblemDefinition(
                motif: .splitBeamPrism,
                primitives: [
                    .polyline(
                        vertices: [p(0.05, 0.49), p(0.35, 0.49)],
                        lineWidth: 0.06, color: .primary
                    ),
                    .polygon(
                        vertices: [p(0.34, 0.16), p(0.34, 0.84), p(0.71, 0.50)],
                        fill: .secondary
                    ),
                    .polyline(
                        vertices: [p(0.34, 0.84), p(0.53, 0.58), p(0.71, 0.50)],
                        lineWidth: 0.032, color: .primary
                    ),
                    .polyline(
                        vertices: [p(0.34, 0.16), p(0.53, 0.42), p(0.71, 0.50)],
                        lineWidth: 0.032, color: .accent
                    ),
                    .polyline(
                        vertices: [p(0.34, 0.50), p(0.53, 0.42), p(0.53, 0.58)],
                        lineWidth: 0.025, color: .primary
                    ),
                    .polyline(
                        vertices: [p(0.70, 0.50), p(0.95, 0.27)],
                        lineWidth: 0.045, color: .accent
                    ),
                    .polyline(
                        vertices: [p(0.70, 0.50), p(0.97, 0.50)],
                        lineWidth: 0.045, color: .primary
                    ),
                    .polyline(
                        vertices: [p(0.70, 0.50), p(0.95, 0.73)],
                        lineWidth: 0.045, color: .accent
                    ),
                ]
            ),
            wordmark: wordmark(
                market: "LUMA COAST", nickname: "PRISMS", layout: .splitBeam,
                alignment: .leading, tracking: 0.09, slant: -5
            ),
            endZone: endZone(layout: .splitRays, repeatCount: 3)
        ),
        LaunchTeamID.foundryReachOrbiters: IdentitySpec(
            displayName: "Foundry Reach Orbiters",
            palette: palette("#146353", "#D4A73E", "#F0E8CF"),
            emblemPalette: palette("#0C705C", "#D9A928", "#F4EED8"),
            emblem: EmblemDefinition(
                motif: .rivetedOrbit,
                primitives: [
                    .ring(
                        center: p(0.50, 0.50), radius: 0.36,
                        lineWidth: 0.085, color: .primary
                    ),
                    .ring(
                        center: p(0.50, 0.50), radius: 0.29,
                        lineWidth: 0.025, color: .accent
                    ),
                    .ring(
                        center: p(0.50, 0.50), radius: 0.20,
                        lineWidth: 0.055, color: .secondary
                    ),
                    .polyline(
                        vertices: [p(0.14, 0.50), p(0.86, 0.50)],
                        lineWidth: 0.035, color: .secondary
                    ),
                    .polyline(
                        vertices: [p(0.50, 0.14), p(0.50, 0.86)],
                        lineWidth: 0.035, color: .secondary
                    ),
                    .disk(center: p(0.50, 0.14), radius: 0.050, fill: .accent),
                    .disk(center: p(0.86, 0.50), radius: 0.050, fill: .accent),
                    .disk(center: p(0.50, 0.86), radius: 0.050, fill: .accent),
                    .disk(center: p(0.14, 0.50), radius: 0.050, fill: .accent),
                    .disk(center: p(0.27, 0.27), radius: 0.025, fill: .secondary),
                    .disk(center: p(0.73, 0.27), radius: 0.025, fill: .secondary),
                    .disk(center: p(0.73, 0.73), radius: 0.025, fill: .secondary),
                    .disk(center: p(0.27, 0.73), radius: 0.025, fill: .secondary),
                    .disk(center: p(0.50, 0.50), radius: 0.135, fill: .secondary),
                    .polygon(
                        vertices: [
                            p(0.50, 0.39), p(0.61, 0.50),
                            p(0.50, 0.61), p(0.39, 0.50),
                        ],
                        fill: .accent
                    ),
                    .disk(center: p(0.50, 0.50), radius: 0.045, fill: .primary),
                ]
            ),
            wordmark: wordmark(
                market: "FOUNDRY REACH", nickname: "ORBITERS", layout: .ringStack,
                alignment: .centered, tracking: 0.05
            ),
            endZone: endZone(layout: .rivetRail, repeatCount: 8, background: .primary)
        ),
        LaunchTeamID.neonBasinEclipses: IdentitySpec(
            displayName: "Neon Basin Eclipses",
            palette: palette("#171923", "#ADB5C2", "#A05CFF"),
            emblemPalette: palette("#111118", "#FFC928", "#FF9B4A"),
            emblem: EmblemDefinition(
                motif: .offsetEclipse,
                primitives: [
                    .arc(
                        center: p(0.49, 0.50), radius: 0.38, startDegrees: 35,
                        endDegrees: 305, lineWidth: 0.055, color: .accent
                    ),
                    .disk(center: p(0.45, 0.52), radius: 0.29, fill: .secondary),
                    .disk(center: p(0.58, 0.47), radius: 0.29, fill: .primary),
                    .polygon(
                        vertices: [
                            p(0.84, 0.54), p(0.87, 0.57), p(0.90, 0.54),
                            p(0.87, 0.51),
                        ],
                        fill: .secondary
                    ),
                    .polyline(
                        vertices: [p(0.82, 0.54), p(0.92, 0.54)],
                        lineWidth: 0.018, color: .accent
                    ),
                    .polyline(
                        vertices: [p(0.87, 0.49), p(0.87, 0.59)],
                        lineWidth: 0.018, color: .accent
                    ),
                ]
            ),
            wordmark: wordmark(
                market: "NEON BASIN", nickname: "ECLIPSES", layout: .offsetStack,
                alignment: .trailing, tracking: 0.10, slant: -6
            ),
            endZone: endZone(layout: .offsetDisks, repeatCount: 4, background: .primary)
        ),
        LaunchTeamID.meridianPlainsRadiants: IdentitySpec(
            displayName: "Meridian Plains Radiants",
            palette: palette("#C72F4F", "#F0A253", "#FFF0DD"),
            emblemPalette: palette("#C72F4F", "#F06A3B", "#FFD166"),
            emblem: EmblemDefinition(
                motif: .reactorCore,
                primitives: [
                    .polygon(
                        vertices: [
                            p(0.50, 0.04), p(0.57, 0.36), p(0.84, 0.16),
                            p(0.64, 0.43), p(0.96, 0.50), p(0.64, 0.57),
                            p(0.84, 0.84), p(0.57, 0.64), p(0.50, 0.96),
                            p(0.43, 0.64), p(0.16, 0.84), p(0.36, 0.57),
                            p(0.04, 0.50), p(0.36, 0.43), p(0.16, 0.16),
                            p(0.43, 0.36),
                        ],
                        fill: .secondary
                    ),
                    .polygon(
                        vertices: [
                            p(0.50, 0.14), p(0.62, 0.38), p(0.86, 0.50),
                            p(0.62, 0.62), p(0.50, 0.86), p(0.38, 0.62),
                            p(0.14, 0.50), p(0.38, 0.38),
                        ],
                        fill: .accent
                    ),
                    .polygon(
                        vertices: [
                            p(0.50, 0.23), p(0.77, 0.50),
                            p(0.50, 0.77), p(0.23, 0.50),
                        ],
                        fill: .primary
                    ),
                    .polygon(
                        vertices: [
                            p(0.50, 0.34), p(0.58, 0.42), p(0.66, 0.50),
                            p(0.58, 0.58), p(0.50, 0.66), p(0.42, 0.58),
                            p(0.34, 0.50), p(0.42, 0.42),
                        ],
                        fill: .accent
                    ),
                    .disk(center: p(0.50, 0.50), radius: 0.055, fill: .primary),
                ]
            ),
            wordmark: wordmark(
                market: "MERIDIAN PLAINS", nickname: "RADIANTS", layout: .coreStack,
                alignment: .centered, tracking: 0.06
            ),
            endZone: endZone(layout: .radialCore, repeatCount: 5, background: .primary)
        ),
        LaunchTeamID.rainportAuroras: IdentitySpec(
            displayName: "Rainport Auroras",
            palette: palette("#0B3A4A", "#9DD643", "#E5F2EA"),
            emblemPalette: palette("#0B4D5C", "#9DD643", "#C7ECEA"),
            emblem: EmblemDefinition(
                motif: .auroraGridWave,
                primitives: [
                    .polyline(
                        vertices: [
                            p(0.08, 0.34), p(0.28, 0.22), p(0.50, 0.38),
                            p(0.72, 0.24), p(0.92, 0.35),
                        ],
                        lineWidth: 0.095, color: .secondary
                    ),
                    .polyline(
                        vertices: [
                            p(0.12, 0.55), p(0.31, 0.43), p(0.52, 0.58),
                            p(0.73, 0.44), p(0.88, 0.54),
                        ],
                        lineWidth: 0.075, color: .accent
                    ),
                    .polyline(
                        vertices: [p(0.14, 0.67), p(0.86, 0.67)],
                        lineWidth: 0.025, color: .primary
                    ),
                    .polyline(
                        vertices: [p(0.24, 0.70), p(0.24, 0.84)],
                        lineWidth: 0.022, color: .primary
                    ),
                    .polyline(
                        vertices: [p(0.42, 0.70), p(0.42, 0.90)],
                        lineWidth: 0.022, color: .primary
                    ),
                    .polyline(
                        vertices: [p(0.60, 0.70), p(0.60, 0.86)],
                        lineWidth: 0.022, color: .primary
                    ),
                    .polyline(
                        vertices: [p(0.77, 0.70), p(0.77, 0.88)],
                        lineWidth: 0.022, color: .primary
                    ),
                    .polyline(
                        vertices: [p(0.35, 0.13), p(0.35, 0.22)],
                        lineWidth: 0.018, color: .primary
                    ),
                    .polyline(
                        vertices: [p(0.66, 0.12), p(0.66, 0.22)],
                        lineWidth: 0.018, color: .primary
                    ),
                ]
            ),
            wordmark: wordmark(
                market: "RAINPORT", nickname: "AURORAS", layout: .waveStack,
                alignment: .leading, tracking: 0.08, slant: -3
            ),
            endZone: endZone(layout: .waveBands, repeatCount: 3, background: .primary)
        ),
        LaunchTeamID.baylineRedshifts: IdentitySpec(
            displayName: "Bayline Redshifts",
            palette: palette("#842C4B", "#C87845", "#DFE5E2"),
            emblemPalette: palette("#9A3154", "#D77B46", "#F4F2EA"),
            emblem: EmblemDefinition(
                motif: .redshiftBars,
                primitives: [
                    .roundedBar(
                        frame: rect(0.44, 0.70, 0.31, 0.10), cornerRadius: 0.045,
                        fill: .secondary
                    ),
                    .roundedBar(
                        frame: rect(0.34, 0.51, 0.42, 0.10), cornerRadius: 0.045,
                        fill: .primary
                    ),
                    .roundedBar(
                        frame: rect(0.25, 0.32, 0.51, 0.10), cornerRadius: 0.045,
                        fill: .secondary
                    ),
                    .roundedBar(
                        frame: rect(0.16, 0.13, 0.61, 0.10), cornerRadius: 0.045,
                        fill: .accent
                    ),
                    .polyline(
                        vertices: [p(0.80, 0.10), p(0.80, 0.86)],
                        lineWidth: 0.030, color: .accent
                    ),
                ]
            ),
            wordmark: wordmark(
                market: "BAYLINE", nickname: "REDSHIFTS", layout: .recedingStack,
                alignment: .trailing, tracking: 0.12, slant: -7
            ),
            endZone: endZone(layout: .frequencySteps, repeatCount: 4, background: .primary)
        ),
    ]

    static let footballStyles: [FootballID: FootballVisualStyle] = [
        LaunchFootballID.standard: FootballVisualStyle(
            footballID: LaunchFootballID.standard,
            panelTreatment: .orbitalSeam,
            surface: RGBColor(hex: "#713B2C"),
            seam: RGBColor(hex: "#2C1712"),
            laces: RGBColor(hex: "#F2E6D0"),
            detail: RGBColor(hex: "#C87845")
        ),
        LaunchFootballID.alternate: FootballVisualStyle(
            footballID: LaunchFootballID.alternate,
            panelTreatment: .vectorArcBands,
            surface: RGBColor(hex: "#171923"),
            seam: RGBColor(hex: "#7D4DFF"),
            laces: RGBColor(hex: "#F7FCFF"),
            detail: RGBColor(hex: "#1DE6EF")
        ),
    ]

    static func matchesApprovedDescriptor(_ team: TeamDescriptor, spec: IdentitySpec) -> Bool {
        let expectedPalette = TeamBrandPalette(
            primary: team.primaryColor,
            secondary: team.secondaryColor,
            accent: team.accentColor
        )
        let primary = team.primaryJersey
        let alternate = team.alternateJersey

        return team.displayName == spec.displayName
            && expectedPalette == spec.palette
            && primary.id == JerseyID("jersey.\(team.id.rawValue).primary")
            && primary.teamID == team.id
            && primary.kind == .primary
            && primary.primaryColor == team.primaryColor
            && primary.secondaryColor == team.secondaryColor
            && primary.accentColor == team.accentColor
            && alternate.id == JerseyID("jersey.\(team.id.rawValue).alternate")
            && alternate.teamID == team.id
            && alternate.kind == .alternate
            && alternate.primaryColor == team.secondaryColor
            && alternate.secondaryColor == team.accentColor
            && alternate.accentColor == team.primaryColor
    }

    static func makeJerseyIdentity(_ jersey: JerseyDescriptor) -> JerseyVisualIdentity {
        let offense = UniformSpritePalette(
            jerseyBody: jersey.primaryColor,
            shoulderPanel: jersey.secondaryColor,
            numberAndName: jersey.accentColor,
            trim: jersey.accentColor,
            helmetShell: jersey.primaryColor,
            helmetDetail: jersey.accentColor,
            pants: jersey.secondaryColor,
            socks: jersey.accentColor
        )
        let defense = UniformSpritePalette(
            jerseyBody: jersey.primaryColor,
            shoulderPanel: jersey.secondaryColor,
            numberAndName: jersey.accentColor,
            trim: jersey.accentColor,
            helmetShell: jersey.secondaryColor,
            helmetDetail: jersey.accentColor,
            pants: jersey.primaryColor,
            socks: jersey.secondaryColor
        )
        return JerseyVisualIdentity(
            jerseyID: jersey.id,
            teamID: jersey.teamID,
            kind: jersey.kind,
            offense: offense,
            defense: defense
        )
    }
}

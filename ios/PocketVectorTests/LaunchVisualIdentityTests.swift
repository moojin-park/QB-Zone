import Foundation
import XCTest

@testable import PocketVector

final class LaunchVisualIdentityTests: XCTestCase {
    func testLaunchCoverageAndPalettesMatchApprovedCatalog() throws {
        let productCatalog = LaunchCatalog.approved
        let visuals = LaunchVisualIdentityCatalog.approved

        XCTAssertEqual(visuals.allTeams.map(\.teamID), productCatalog.teams.map(\.id))
        XCTAssertEqual(visuals.allTeams.count, 8)
        XCTAssertEqual(visuals.allJerseys.count, 16)
        XCTAssertEqual(Set(visuals.allJerseys.map(\.jerseyID)).count, 16)
        XCTAssertEqual(
            visuals.allFootballStyles.map(\.footballID),
            productCatalog.footballs.map(\.id)
        )
        XCTAssertEqual(visuals.allFootballStyles.count, 2)
        XCTAssertEqual(Set(visuals.allFootballStyles.map(\.panelTreatment)).count, 2)
        for football in productCatalog.footballs {
            XCTAssertEqual(visuals.football(id: football.id)?.footballID, football.id)
        }

        for team in productCatalog.teams {
            let identity = try XCTUnwrap(visuals.team(id: team.id))
            let expectedPalette = TeamBrandPalette(
                primary: team.primaryColor,
                secondary: team.secondaryColor,
                accent: team.accentColor
            )
            XCTAssertEqual(identity.displayName, team.displayName)
            XCTAssertEqual(identity.palette, expectedPalette)
            XCTAssertEqual(
                identity.hud,
                HUDVisualPalette(
                    primary: team.primaryColor,
                    secondary: team.secondaryColor,
                    accent: team.accentColor
                )
            )
            XCTAssertFalse(identity.emblem.primitives.isEmpty)
            XCTAssertEqual(identity.emblem.coordinateOrigin, .bottomLeading)
            XCTAssertTrue(identity.emblem.primitives.allSatisfy(\.usesNormalizedCanvas))
            XCTAssertEqual(identity.jerseys.map(\.jerseyID), team.jerseys.map(\.id))

            for descriptor in team.jerseys {
                let jersey = try XCTUnwrap(
                    visuals.jersey(teamID: team.id, jerseyID: descriptor.id)
                )
                XCTAssertEqual(jersey.kind, descriptor.kind)

                for role in UniformSquadRole.allCases {
                    let palette = jersey.palette(for: role)
                    XCTAssertEqual(palette.jerseyBody, descriptor.primaryColor)
                    XCTAssertEqual(palette.shoulderPanel, descriptor.secondaryColor)
                    XCTAssertEqual(palette.numberAndName, descriptor.accentColor)

                    let approvedColors = Set([
                        descriptor.primaryColor,
                        descriptor.secondaryColor,
                        descriptor.accentColor,
                    ])
                    XCTAssertTrue(
                        [
                            palette.jerseyBody, palette.shoulderPanel,
                            palette.numberAndName, palette.trim,
                            palette.helmetShell, palette.helmetDetail,
                            palette.pants, palette.socks,
                        ].allSatisfy(approvedColors.contains)
                    )
                }
            }
        }
    }

    func testEveryTeamUsesAnOriginalUniqueGeometricMotifAndApprovedWordmark() {
        let productCatalog = LaunchCatalog.approved
        let visuals = LaunchVisualIdentityCatalog.approved

        XCTAssertEqual(Set(visuals.allTeams.map { $0.emblem.motif }).count, 8)
        XCTAssertEqual(Set(visuals.allTeams.map { $0.emblem.motif }), Set(EmblemMotif.allCases))

        for team in productCatalog.teams {
            guard let identity = visuals.team(id: team.id) else {
                XCTFail("Missing visual identity for \(team.id)")
                continue
            }
            let fullWordmark = "\(identity.wordmark.marketLine) \(identity.wordmark.nicknameLine)"
            XCTAssertEqual(fullWordmark, team.displayName.uppercased())
        }
    }

    func testDefensePresentationDoesNotDependOnPlayerOwnership() throws {
        let productCatalog = LaunchCatalog.approved
        let visuals = LaunchVisualIdentityCatalog.approved
        let playerOwnedTeamIDs: Set<TeamID> = []
        let playerOwnedJerseyIDs: Set<JerseyID> = []
        let lockedOpponent = try XCTUnwrap(
            productCatalog.team(id: LaunchTeamID.lumaCoastPrisms)
        )

        XCTAssertFalse(lockedOpponent.initiallyOwned)
        XCTAssertFalse(playerOwnedTeamIDs.contains(lockedOpponent.id))
        XCTAssertFalse(playerOwnedJerseyIDs.contains(lockedOpponent.alternateJersey.id))
        XCTAssertNotNil(
            visuals.uniform(
                teamID: lockedOpponent.id,
                jerseyID: lockedOpponent.alternateJersey.id,
                role: .defense
            )
        )

        let anotherTeam = try XCTUnwrap(
            productCatalog.team(id: LaunchTeamID.novaCityComets)
        )
        XCTAssertNil(
            visuals.uniform(
                teamID: anotherTeam.id,
                jerseyID: lockedOpponent.alternateJersey.id,
                role: .defense
            ),
            "A jersey ID must not cross team boundaries"
        )
    }

    func testUnknownAndCatalogMismatchesFailClosed() throws {
        let productCatalog = LaunchCatalog.approved
        let visuals = LaunchVisualIdentityCatalog.approved

        XCTAssertNil(visuals.team(id: TeamID("unknown_team")))
        XCTAssertNil(
            visuals.jersey(
                teamID: LaunchTeamID.novaCityComets,
                jerseyID: JerseyID("jersey.unknown.primary")
            )
        )
        XCTAssertNil(visuals.football(id: FootballID("football.unknown")))

        let first = try XCTUnwrap(productCatalog.teams.first)
        let mismatched = TeamDescriptor(
            id: first.id,
            displayName: first.displayName,
            initiallyOwned: first.initiallyOwned,
            primaryColor: RGBColor(hex: "#000000"),
            secondaryColor: first.secondaryColor,
            accentColor: first.accentColor,
            primaryJersey: first.primaryJersey,
            alternateJersey: first.alternateJersey,
            assets: first.assets
        )
        let malformedCatalog = LaunchCatalog(
            teams: [mismatched] + Array(productCatalog.teams.dropFirst()),
            footballs: productCatalog.footballs,
            unlockableItems: productCatalog.unlockableItems
        )

        XCTAssertNil(LaunchVisualIdentityCatalog(catalog: malformedCatalog))
    }
}

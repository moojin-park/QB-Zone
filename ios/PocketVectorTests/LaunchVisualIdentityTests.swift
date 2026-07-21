import Foundation
import SpriteKit
import SwiftUI
import UIKit
import XCTest

@testable import PocketVector

@MainActor
private final class RecordingUniformTexturePreloader: UniformTexturePreloading {
    private(set) var invocationCount = 0
    private(set) var textureCount = 0
    private(set) var didComplete = false

    func preload(_ texture: SKTexture) async -> Bool {
        invocationCount += 1
        textureCount += 1
        await Task.yield()
        didComplete = true
        return true
    }
}

private final class VisualLifecycleReceipt: @unchecked Sendable {
    let expectation: XCTestExpectation

    init(_ description: String) {
        expectation = XCTestExpectation(description: description)
        expectation.assertForOverFulfill = true
    }

    func record() {
        expectation.fulfill()
    }
}

private actor ControlledUniformTexturePreparer: UniformTexturePreparing {
    private let firstStarted: VisualLifecycleReceipt
    private let firstObservedCancellation: VisualLifecycleReceipt
    private var invocationCount = 0
    private var firstRequests: [UniformTexturePreparationRequest] = []
    private var firstContinuation: CheckedContinuation<[PreparedUniformTexture], Never>?

    init(
        firstStarted: VisualLifecycleReceipt,
        firstObservedCancellation: VisualLifecycleReceipt
    ) {
        self.firstStarted = firstStarted
        self.firstObservedCancellation = firstObservedCancellation
    }

    func prepare(
        _ requests: [UniformTexturePreparationRequest]
    ) async -> [PreparedUniformTexture] {
        invocationCount += 1
        guard invocationCount == 1 else {
            return Self.syntheticTextures(for: requests)
        }

        firstRequests = requests
        firstStarted.record()
        let prepared = await withCheckedContinuation { continuation in
            firstContinuation = continuation
        }
        if Task.isCancelled {
            firstObservedCancellation.record()
        }
        return prepared
    }

    func completeFirstPreparation() {
        let continuation = firstContinuation
        firstContinuation = nil
        continuation?.resume(returning: Self.syntheticTextures(for: firstRequests))
    }

    private static func syntheticTextures(
        for requests: [UniformTexturePreparationRequest]
    ) -> [PreparedUniformTexture] {
        requests.map { request in
            PreparedUniformTexture(
                cacheKey: request.cacheKey,
                width: 1,
                height: 1,
                bytesPerRow: 4,
                rgbaData: Data([255, 0, 0, 255])
            )
        }
    }
}

private struct SyntheticUniformTexturePreparer: UniformTexturePreparing {
    func prepare(
        _ requests: [UniformTexturePreparationRequest]
    ) async -> [PreparedUniformTexture] {
        requests.map { request in
            PreparedUniformTexture(
                cacheKey: request.cacheKey,
                width: 1,
                height: 1,
                bytesPerRow: 4,
                rgbaData: Data([255, 0, 0, 255])
            )
        }
    }
}

private actor FallbackOnlyUniformTexturePreparer: UniformTexturePreparing {
    private var fallbackPaths: [String?] = []

    func prepare(
        _ requests: [UniformTexturePreparationRequest]
    ) async -> [PreparedUniformTexture] {
        fallbackPaths += requests.map(\.developmentFallbackRelativePath)
        return requests.compactMap { request in
            guard request.developmentFallbackRelativePath != nil else { return nil }
            return PreparedUniformTexture(
                cacheKey: request.cacheKey,
                width: 1,
                height: 1,
                bytesPerRow: 4,
                rgbaData: Data([255, 0, 0, 255])
            )
        }
    }

    func recordedFallbackPaths() -> [String?] {
        fallbackPaths
    }
}

@MainActor
private final class FirstTextureGatePreloader: UniformTexturePreloading {
    private let firstStarted: VisualLifecycleReceipt
    private var firstContinuation: CheckedContinuation<Void, Never>?
    private var activeInvocationCount = 0
    private(set) var invocationCount = 0
    private(set) var maximumConcurrentInvocationCount = 0

    init(firstStarted: VisualLifecycleReceipt) {
        self.firstStarted = firstStarted
    }

    func preload(_ texture: SKTexture) async -> Bool {
        invocationCount += 1
        activeInvocationCount += 1
        maximumConcurrentInvocationCount = max(
            maximumConcurrentInvocationCount,
            activeInvocationCount
        )
        defer { activeInvocationCount -= 1 }

        if invocationCount == 1 {
            firstStarted.record()
            await withCheckedContinuation { continuation in
                firstContinuation = continuation
            }
        }
        return true
    }

    func releaseFirstTexture() {
        let continuation = firstContinuation
        firstContinuation = nil
        continuation?.resume()
    }
}

final class LaunchVisualIdentityTests: XCTestCase {
    func testLaunchCoverageAndPalettesMatchApprovedVisualDirection() throws {
        let productCatalog = LaunchCatalog.approved
        let visuals = LaunchVisualIdentityCatalog.approved
        let approvedEmblemPalettes: [TeamID: TeamBrandPalette] = [
            LaunchTeamID.novaCityComets: TeamBrandPalette(
                primary: RGBColor(hex: "#08B59F"),
                secondary: RGBColor(hex: "#F4C64E"),
                accent: RGBColor(hex: "#F7FCFF")
            ),
            LaunchTeamID.highMesaHelions: TeamBrandPalette(
                primary: RGBColor(hex: "#F06A3B"),
                secondary: RGBColor(hex: "#6F35C5"),
                accent: RGBColor(hex: "#D8F0EC")
            ),
            LaunchTeamID.lumaCoastPrisms: TeamBrandPalette(
                primary: RGBColor(hex: "#63CFE7"),
                secondary: RGBColor(hex: "#54308F"),
                accent: RGBColor(hex: "#F4C64E")
            ),
            LaunchTeamID.foundryReachOrbiters: TeamBrandPalette(
                primary: RGBColor(hex: "#0C705C"),
                secondary: RGBColor(hex: "#D9A928"),
                accent: RGBColor(hex: "#F4EED8")
            ),
            LaunchTeamID.neonBasinEclipses: TeamBrandPalette(
                primary: RGBColor(hex: "#111118"),
                secondary: RGBColor(hex: "#FFC928"),
                accent: RGBColor(hex: "#FF9B4A")
            ),
            LaunchTeamID.meridianPlainsRadiants: TeamBrandPalette(
                primary: RGBColor(hex: "#C72F4F"),
                secondary: RGBColor(hex: "#F06A3B"),
                accent: RGBColor(hex: "#FFD166")
            ),
            LaunchTeamID.rainportAuroras: TeamBrandPalette(
                primary: RGBColor(hex: "#0B4D5C"),
                secondary: RGBColor(hex: "#9DD643"),
                accent: RGBColor(hex: "#C7ECEA")
            ),
            LaunchTeamID.baylineRedshifts: TeamBrandPalette(
                primary: RGBColor(hex: "#9A3154"),
                secondary: RGBColor(hex: "#D77B46"),
                accent: RGBColor(hex: "#F4F2EA")
            ),
        ]

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
        XCTAssertEqual(Set(visuals.allTeams.map(\.palette)).count, 8)
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
            XCTAssertEqual(identity.palette, approvedEmblemPalettes[team.id])
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

    func testEveryLaunchJerseyAndFootballResolvesThroughImmutableRunConfiguration() throws {
        let productCatalog = LaunchCatalog.approved
        let visuals = LaunchVisualIdentityCatalog.approved
        var resolvedCombinations = 0

        for (teamIndex, offenseTeam) in productCatalog.teams.enumerated() {
            let defenseTeam = productCatalog.teams[(teamIndex + 1) % productCatalog.teams.count]
            for offenseJersey in offenseTeam.jerseys {
                for football in productCatalog.footballs {
                    let configuration = RunConfiguration(
                        runID: RunID(),
                        randomSeed: UInt32(resolvedCombinations + 1),
                        offenseTeamID: offenseTeam.id,
                        offenseJerseyID: offenseJersey.id,
                        defenseTeamID: defenseTeam.id,
                        defenseJerseyID: defenseTeam.alternateJersey.id,
                        footballID: football.id,
                        economyVersion: EconomyConfiguration.currentVersion,
                        startedAt: Date(timeIntervalSince1970: 1)
                    )
                    let resolved = try XCTUnwrap(visuals.runIdentity(for: configuration))
                    XCTAssertEqual(resolved.offenseTeam.teamID, offenseTeam.id)
                    XCTAssertEqual(
                        resolved.offenseUniform,
                        try XCTUnwrap(
                            visuals.uniform(
                                teamID: offenseTeam.id,
                                jerseyID: offenseJersey.id,
                                role: .offense
                            )
                        )
                    )
                    XCTAssertEqual(resolved.defenseTeam.teamID, defenseTeam.id)
                    XCTAssertEqual(
                        resolved.defenseUniform,
                        try XCTUnwrap(
                            visuals.uniform(
                                teamID: defenseTeam.id,
                                jerseyID: defenseTeam.alternateJersey.id,
                                role: .defense
                            )
                        )
                    )
                    XCTAssertEqual(resolved.football.footballID, football.id)
                    resolvedCombinations += 1
                }
            }
        }

        XCTAssertEqual(resolvedCombinations, 32)
    }

    func testRunVisualResolverFailsClosedForCrossTeamJerseyAndSameTeamMatchup() throws {
        let productCatalog = LaunchCatalog.approved
        let visuals = LaunchVisualIdentityCatalog.approved
        let offense = try XCTUnwrap(productCatalog.teams.first)
        let defense = try XCTUnwrap(productCatalog.teams.dropFirst().first)

        let crossTeamJersey = RunConfiguration(
            runID: RunID(),
            randomSeed: 1,
            offenseTeamID: offense.id,
            offenseJerseyID: defense.primaryJersey.id,
            defenseTeamID: defense.id,
            defenseJerseyID: defense.primaryJersey.id,
            footballID: LaunchFootballID.standard,
            economyVersion: EconomyConfiguration.currentVersion,
            startedAt: Date(timeIntervalSince1970: 1)
        )
        XCTAssertNil(visuals.runIdentity(for: crossTeamJersey))

        let sameTeam = RunConfiguration(
            runID: RunID(),
            randomSeed: 2,
            offenseTeamID: offense.id,
            offenseJerseyID: offense.primaryJersey.id,
            defenseTeamID: offense.id,
            defenseJerseyID: offense.alternateJersey.id,
            footballID: LaunchFootballID.standard,
            economyVersion: EconomyConfiguration.currentVersion,
            startedAt: Date(timeIntervalSince1970: 1)
        )
        XCTAssertNil(visuals.runIdentity(for: sameTeam))
    }

    func testMatchupClashChoiceIsTheDefenseUniformRenderedForTheRun() throws {
        let catalog = LaunchCatalog.approved
        let visuals = LaunchVisualIdentityCatalog.approved
        var inventory = InventoryRules.initialInventory(catalog: catalog)
        inventory.ownedTeamIDs = Set(catalog.teams.map(\.id))
        inventory.ownedJerseyIDs = Set(catalog.teams.flatMap(\.jerseys).map(\.id))

        for offenseTeam in catalog.teams {
            for offenseJersey in offenseTeam.jerseys {
                let selection = PlayerSelection(
                    selectedTeamID: offenseTeam.id,
                    selectedJerseyByTeam: [offenseTeam.id: offenseJersey.id],
                    selectedFootballID: LaunchFootballID.standard
                )
                let configuration = try MatchupGenerator(catalog: catalog).makeRunConfiguration(
                    selection: selection,
                    inventory: inventory,
                    seed: UInt32(offenseTeam.id.rawValue.utf8.reduce(0, { $0 + UInt32($1) })),
                    startedAt: Date(timeIntervalSince1970: 1)
                )
                let defense = try XCTUnwrap(catalog.team(id: configuration.defenseTeamID))
                let expectedJersey = UniformClashResolver.resolve(
                    offense: offenseJersey,
                    defenseTeam: defense
                )
                XCTAssertEqual(configuration.defenseJerseyID, expectedJersey.id)

                let uniformAssetRoots = try XCTUnwrap(
                    RunGameplayUniformAssetRoots(
                        configuration: configuration,
                        catalog: catalog
                    )
                )
                XCTAssertEqual(uniformAssetRoots.offense.teamID, offenseTeam.id)
                XCTAssertEqual(uniformAssetRoots.offense.jerseyID, offenseJersey.id)
                XCTAssertEqual(
                    uniformAssetRoots.offense.relativePath,
                    "characters/teams/\(offenseTeam.id.rawValue)/\(offenseJersey.kind.rawValue)"
                )
                XCTAssertEqual(uniformAssetRoots.defense.teamID, defense.id)
                XCTAssertEqual(uniformAssetRoots.defense.jerseyID, expectedJersey.id)
                XCTAssertEqual(
                    uniformAssetRoots.defense.relativePath,
                    "characters/teams/\(defense.id.rawValue)/\(expectedJersey.kind.rawValue)"
                )

                let resolved = try XCTUnwrap(visuals.runIdentity(for: configuration))
                XCTAssertEqual(
                    resolved.defenseUniform,
                    try XCTUnwrap(
                        visuals.uniform(
                            teamID: defense.id,
                            jerseyID: expectedJersey.id,
                            role: .defense
                        )
                    )
                )
            }
        }
    }

    @MainActor
    func testAllSixteenLaunchJerseysResolveEveryBakedGameplayFrame() throws {
        let catalog = LaunchCatalog.approved
        let genericFramePaths = TextureLibrary.offenseUniformPaths
            + TextureLibrary.defenseUniformPaths
        var assetRoots = Set<GameplayJerseyAssetRoot>()
        var cacheKeys = Set<UniformTextureCacheKey>()

        XCTAssertEqual(catalog.teams.count, 8)
        XCTAssertEqual(genericFramePaths.count, 34)
        for team in catalog.teams {
            for jersey in team.jerseys {
                let approvedJersey = try XCTUnwrap(catalog.jersey(id: jersey.id))
                XCTAssertEqual(approvedJersey, jersey)

                let root = try XCTUnwrap(
                    GameplayJerseyAssetRoot(
                        teamID: team.id,
                        jerseyID: approvedJersey.id,
                        catalog: catalog
                    )
                )
                XCTAssertEqual(
                    root.relativePath,
                    "characters/teams/\(team.id.rawValue)/\(jersey.kind.rawValue)"
                )
                assetRoots.insert(root)

                for genericFramePath in genericFramePaths {
                    let bakedFramePath = try XCTUnwrap(
                        root.framePath(for: genericFramePath)
                    )
                    XCTAssertNotNil(
                        GameAssetResources.url(for: bakedFramePath),
                        bakedFramePath
                    )
                    XCTAssertEqual(
                        BakedUniformRasterPreprocessor.pixelSize(
                            relativePath: bakedFramePath
                        ),
                        CGSize(
                            width: BakedUniformRasterPreprocessor.framePixelWidth,
                            height: BakedUniformRasterPreprocessor.framePixelHeight
                        ),
                        bakedFramePath
                    )
                    cacheKeys.insert(
                        UniformTextureCacheKey(
                            assetRoot: root,
                            genericFramePath: genericFramePath
                        )
                    )
                }

            }
        }

        XCTAssertEqual(assetRoots.count, 16)
        XCTAssertEqual(cacheKeys.count, 16 * 34)
    }

    func testRaisedForegroundQuarterbackRoutesEveryPoseForAllSixteenUniforms() throws {
        let catalog = LaunchCatalog.approved
        let poses = ForegroundQuarterbackPose.allCases
        var routedFrameCount = 0

        XCTAssertEqual(ForegroundQuarterbackPresentation.renderedBaselineY, -310)
        XCTAssertEqual(
            ForegroundQuarterbackPresentation.spriteSize,
            CGSize(width: 438, height: 584)
        )
        XCTAssertEqual(
            Set(poses.map(\.texturePath)),
            Set([
                "characters/qb-idle.webp",
                "characters/qb-aim.webp",
                "characters/qb-throw.webp",
                "characters/qb-recovery.webp",
            ])
        )

        for team in catalog.teams {
            for jersey in team.jerseys {
                let root = try XCTUnwrap(
                    GameplayJerseyAssetRoot(
                        teamID: team.id,
                        jerseyID: jersey.id,
                        catalog: catalog
                    )
                )
                for pose in poses {
                    let framePath = try XCTUnwrap(
                        root.framePath(for: pose.texturePath)
                    )
                    XCTAssertNotNil(GameAssetResources.url(for: framePath), framePath)
                    XCTAssertEqual(
                        BakedUniformRasterPreprocessor.pixelSize(
                            relativePath: framePath
                        ),
                        CGSize(width: 384, height: 512),
                        framePath
                    )
                    routedFrameCount += 1
                }
            }
        }

        XCTAssertEqual(routedFrameCount, 16 * poses.count)
    }

    @MainActor
    func testAllSixteenLaunchJerseysUseSeparateNearestNeighborCacheEntries() async throws {
        let catalog = LaunchCatalog.approved
        let preloader = RecordingUniformTexturePreloader()
        let library = TextureLibrary(
            uniformTexturePreparer: SyntheticUniformTexturePreparer(),
            uniformTexturePreloader: preloader
        )
        let genericFramePath = "characters/qb-idle.webp"
        var cachedTextureIdentities = Set<ObjectIdentifier>()

        for team in catalog.teams {
            let defense = try XCTUnwrap(catalog.teams.first { $0.id != team.id })
            for jersey in team.jerseys {
                let configuration = RunConfiguration(
                    runID: RunID(),
                    randomSeed: 11,
                    offenseTeamID: team.id,
                    offenseJerseyID: jersey.id,
                    defenseTeamID: defense.id,
                    defenseJerseyID: defense.primaryJersey.id,
                    footballID: LaunchFootballID.standard,
                    economyVersion: EconomyConfiguration.currentVersion,
                    startedAt: Date(timeIntervalSince1970: 1)
                )
                let roots = try XCTUnwrap(
                    RunGameplayUniformAssetRoots(
                        configuration: configuration,
                        catalog: catalog
                    )
                )
                let result = await library.prewarmRunUniformTextures(
                    uniformAssetRoots: roots
                )
                XCTAssertTrue(result.isComplete)

                let texture = try XCTUnwrap(
                    library.uniformTexture(
                        genericFramePath,
                        assetRoot: roots.offense
                    )
                )
                XCTAssertEqual(texture.filteringMode, .nearest)
                cachedTextureIdentities.insert(ObjectIdentifier(texture))
                XCTAssertTrue(
                    texture === library.uniformTexture(
                        genericFramePath,
                        assetRoot: roots.offense
                    )
                )
            }
        }

        XCTAssertEqual(cachedTextureIdentities.count, 16)
        XCTAssertEqual(
            preloader.invocationCount,
            16 * (TextureLibrary.offenseUniformPaths.count
                + TextureLibrary.defenseUniformPaths.count)
        )
    }

    func testRunUniformAssetRootsRejectCrossTeamJerseys() throws {
        let catalog = LaunchCatalog.approved
        let offense = try XCTUnwrap(catalog.team(id: LaunchTeamID.novaCityComets))
        let defense = try XCTUnwrap(catalog.team(id: LaunchTeamID.highMesaHelions))
        let valid = RunConfiguration(
            runID: RunID(),
            randomSeed: 7,
            offenseTeamID: offense.id,
            offenseJerseyID: offense.alternateJersey.id,
            defenseTeamID: defense.id,
            defenseJerseyID: defense.primaryJersey.id,
            footballID: LaunchFootballID.standard,
            economyVersion: EconomyConfiguration.currentVersion,
            startedAt: Date(timeIntervalSince1970: 1)
        )
        XCTAssertNotNil(
            RunGameplayUniformAssetRoots(configuration: valid, catalog: catalog)
        )

        let mismatched = RunConfiguration(
            runID: valid.runID,
            randomSeed: valid.randomSeed,
            offenseTeamID: valid.offenseTeamID,
            offenseJerseyID: defense.alternateJersey.id,
            defenseTeamID: valid.defenseTeamID,
            defenseJerseyID: valid.defenseJerseyID,
            footballID: valid.footballID,
            economyVersion: valid.economyVersion,
            startedAt: valid.startedAt
        )
        XCTAssertNil(
            RunGameplayUniformAssetRoots(configuration: mismatched, catalog: catalog)
        )

        let sameTeam = RunConfiguration(
            runID: valid.runID,
            randomSeed: valid.randomSeed,
            offenseTeamID: valid.offenseTeamID,
            offenseJerseyID: valid.offenseJerseyID,
            defenseTeamID: valid.offenseTeamID,
            defenseJerseyID: offense.primaryJersey.id,
            footballID: valid.footballID,
            economyVersion: valid.economyVersion,
            startedAt: valid.startedAt
        )
        XCTAssertNil(
            RunGameplayUniformAssetRoots(configuration: sameTeam, catalog: catalog)
        )
    }

    func testBakedUniformPreparationPreservesDecodedRGBAWithoutProjection() throws {
        let team = try XCTUnwrap(
            LaunchCatalog.approved.team(id: LaunchTeamID.novaCityComets)
        )
        let root = try XCTUnwrap(
            GameplayJerseyAssetRoot(
                teamID: team.id,
                jerseyID: team.primaryJersey.id
            )
        )
        let genericFramePath = "characters/qb-idle.webp"
        let bakedFramePath = try XCTUnwrap(root.framePath(for: genericFramePath))
        let decoded = try XCTUnwrap(
            BakedUniformRasterPreprocessor.loadRaster(relativePath: bakedFramePath)
        )
        let prepared = try XCTUnwrap(
            BakedUniformRasterPreprocessor.prepare(
                UniformTexturePreparationRequest(
                    relativePath: bakedFramePath,
                    developmentFallbackRelativePath: nil,
                    cacheKey: UniformTextureCacheKey(
                        assetRoot: root,
                        genericFramePath: genericFramePath
                    )
                )
            )
        )

        XCTAssertEqual(prepared.width, decoded.width)
        XCTAssertEqual(prepared.height, decoded.height)
        XCTAssertEqual(prepared.bytesPerRow, decoded.bytesPerRow)
        XCTAssertEqual(prepared.rgbaData, Data(decoded.bytes))
    }

    func testGenericUniformFallbackRequiresExplicitDevelopmentRequest() throws {
        let team = try XCTUnwrap(
            LaunchCatalog.approved.team(id: LaunchTeamID.novaCityComets)
        )
        let root = try XCTUnwrap(
            GameplayJerseyAssetRoot(
                teamID: team.id,
                jerseyID: team.primaryJersey.id
            )
        )
        let cacheKey = UniformTextureCacheKey(
            assetRoot: root,
            genericFramePath: "characters/qb-idle.webp"
        )
        let missingBakedPath = "characters/teams/missing/primary/qb-idle.webp"

        XCTAssertNil(
            BakedUniformRasterPreprocessor.prepare(
                UniformTexturePreparationRequest(
                    relativePath: missingBakedPath,
                    developmentFallbackRelativePath: nil,
                    cacheKey: cacheKey
                )
            )
        )
        XCTAssertNotNil(
            BakedUniformRasterPreprocessor.prepare(
                UniformTexturePreparationRequest(
                    relativePath: missingBakedPath,
                    developmentFallbackRelativePath: "characters/qb-idle.webp",
                    cacheKey: cacheKey
                )
            )
        )
    }

    @MainActor
    func testTextureLibraryDefaultDisablesGenericFallback() async throws {
        let roots = try launchUniformAssetRoots()
        let defaultPreparer = FallbackOnlyUniformTexturePreparer()
        let explicitPreparer = FallbackOnlyUniformTexturePreparer()

        let defaultLibrary = TextureLibrary(
            uniformTexturePreparer: defaultPreparer,
            uniformTexturePreloader: RecordingUniformTexturePreloader()
        )
        let defaultResult = await defaultLibrary.prewarmRunUniformTextures(
            uniformAssetRoots: roots
        )
        XCTAssertFalse(defaultResult.isComplete)
        XCTAssertEqual(defaultResult.preparedCount, 0)
        XCTAssertNil(
            defaultLibrary.uniformTexture(
                "characters/qb-idle.webp",
                assetRoot: roots.offense
            )
        )
        let defaultFallbacks = await defaultPreparer.recordedFallbackPaths()
        XCTAssertEqual(defaultFallbacks.count, 34)
        XCTAssertTrue(defaultFallbacks.allSatisfy { $0 == nil })

        let developmentLibrary = TextureLibrary(
            uniformTexturePreparer: explicitPreparer,
            uniformTexturePreloader: RecordingUniformTexturePreloader(),
            gameplayUniformFallbackPolicy: .developmentGeneric
        )
        let developmentResult = await developmentLibrary.prewarmRunUniformTextures(
            uniformAssetRoots: roots
        )
        XCTAssertTrue(developmentResult.isComplete)
        XCTAssertNotNil(
            developmentLibrary.uniformTexture(
                "characters/qb-idle.webp",
                assetRoot: roots.offense
            )
        )
        let explicitFallbacks = await explicitPreparer.recordedFallbackPaths()
        XCTAssertEqual(explicitFallbacks.count, 34)
        XCTAssertTrue(explicitFallbacks.allSatisfy { $0 != nil })
    }

    func testPausedGameplayResumeIssuesOneRequestPerPausedEpoch() {
        var requestState = GameplayPauseRequestState()
        var pausedState = GameState()
        pausedState.phaseBeforePause = .playing
        pausedState.phase = .paused
        let pausedSnapshot = GameplaySceneSnapshot(state: pausedState)

        requestState.receive(pausedSnapshot)
        XCTAssertTrue(requestState.requestResume(whilePaused: true))
        XCTAssertFalse(requestState.requestResume(whilePaused: true))
        XCTAssertEqual(requestState.resumeRequestID, 1)

        requestState.receive(pausedSnapshot)
        XCTAssertFalse(requestState.requestResume(whilePaused: true))
        XCTAssertEqual(requestState.resumeRequestID, 1)

        var playingState = pausedState
        playingState.phase = .playing
        playingState.phaseBeforePause = nil
        requestState.receive(GameplaySceneSnapshot(state: playingState))
        requestState.receive(pausedSnapshot)

        XCTAssertTrue(requestState.requestResume(whilePaused: true))
        XCTAssertFalse(requestState.requestResume(whilePaused: true))
        XCTAssertEqual(requestState.resumeRequestID, 2)
    }

    func testGameplayBottomSystemGestureDeferralFollowsLivePlayTransitions() {
        let transitions: [(
            name: String,
            snapshot: GameplaySceneSnapshot?,
            isSettling: Bool,
            settlementErrorMessage: String?,
            expectedEdges: Edge.Set
        )] = [
            ("non-gameplay", nil, false, nil, []),
            ("countdown", gameplaySnapshot(phase: .countdown), false, nil, []),
            ("playing", gameplaySnapshot(phase: .playing), false, nil, .bottom),
            ("paused", gameplaySnapshot(phase: .paused), false, nil, []),
            ("resumed", gameplaySnapshot(phase: .playing), false, nil, .bottom),
            ("settling", gameplaySnapshot(phase: .playing), true, nil, []),
            ("settlement-error", gameplaySnapshot(phase: .playing), false, "Save failed", []),
            ("empty-settlement-error", gameplaySnapshot(phase: .playing), false, "", []),
            (
                "resolving-final-ball",
                gameplaySnapshot(phase: .resolvingFinalBall),
                false,
                nil,
                .bottom
            ),
            ("results", gameplaySnapshot(phase: .results), false, nil, []),
        ]

        for transition in transitions {
            XCTAssertEqual(
                GameplaySystemGestureDeferralPolicy.edges(
                    snapshot: transition.snapshot,
                    isSettling: transition.isSettling,
                    settlementErrorMessage: transition.settlementErrorMessage
                ),
                transition.expectedEdges,
                "Unexpected deferred edges during \(transition.name)"
            )
        }
    }

    func testPausedGameplayConfirmedExitIsGatedAndExactOnce() {
        var requestState = GameplayPauseRequestState()

        XCTAssertFalse(requestState.requestConfirmedExit(whilePaused: false))
        XCTAssertTrue(requestState.requestConfirmedExit(whilePaused: true))
        XCTAssertFalse(requestState.requestConfirmedExit(whilePaused: true))
        XCTAssertFalse(requestState.requestResume(whilePaused: true))
        XCTAssertEqual(requestState.confirmedExitRequestID, 1)
        XCTAssertTrue(requestState.confirmedExitRequestPending)
    }

    private func gameplaySnapshot(phase: GamePhase) -> GameplaySceneSnapshot {
        var state = GameState()
        state.phase = phase
        return GameplaySceneSnapshot(state: state)
    }

    func testPausedGameplayExitConfirmationCancelLeavesRequestsUntouched() {
        var confirmation = GameplayExitConfirmationState()
        let requestState = GameplayPauseRequestState()

        XCTAssertFalse(confirmation.present(whilePaused: false))
        XCTAssertTrue(confirmation.present(whilePaused: true))
        XCTAssertFalse(confirmation.present(whilePaused: true))
        XCTAssertTrue(confirmation.isPresented)

        confirmation.cancel()

        XCTAssertFalse(confirmation.isPresented)
        XCTAssertEqual(requestState.resumeRequestID, 0)
        XCTAssertEqual(requestState.confirmedExitRequestID, 0)
    }

    func testPausedGameplayStatsUseSuccessfulCompletions() throws {
        let statistics = RunStatistics(
            attempts: 9,
            completions: 4,
            touchdowns: 2,
            incompletions: 2,
            interceptions: 1,
            longestTouchdownStreak: 1
        )
        let liveStatistics = LiveGameplayStatisticsSnapshot(statistics: statistics)
        let items = Dictionary(
            uniqueKeysWithValues: GameplayPauseStatPresentation
                .items(for: liveStatistics)
                .map { ($0.id, $0.value) }
        )

        XCTAssertEqual(items[.attempts], "9")
        XCTAssertEqual(items[.completions], "6")
        XCTAssertEqual(items[.completionPercentage], "67%")
        XCTAssertEqual(items[.touchdowns], "2")
    }

    func testPausedGameplayPanelFitsRepresentativeLandscapeSafeAreas() {
        let scenarios: [(size: CGSize, expectedColumns: Int)] = [
            (CGSize(width: 579, height: 354), 2),
            (CGSize(width: 852, height: 409), 4),
            (CGSize(width: 1_194, height: 834), 4),
        ]

        for scenario in scenarios {
            let layout = GameplayPauseLayout(availableSize: scenario.size)
            XCTAssertEqual(layout.statColumnCount, scenario.expectedColumns)
            XCTAssertGreaterThanOrEqual(layout.buttonHeight, 44)
            XCTAssertLessThanOrEqual(
                layout.panelWidth + (layout.outerMargin * 2),
                scenario.size.width
            )
            XCTAssertLessThanOrEqual(
                layout.panelHeight + (layout.outerMargin * 2),
                scenario.size.height
            )
        }
    }

    func testPausedGameplayExitConfirmationFitsRepresentativeLandscapeSafeAreas() {
        let sizes = [
            CGSize(width: 579, height: 354),
            CGSize(width: 852, height: 409),
            CGSize(width: 1_194, height: 834),
        ]

        for size in sizes {
            let layout = GameplayExitConfirmationLayout(availableSize: size)
            XCTAssertGreaterThanOrEqual(layout.buttonHeight, 44)
            XCTAssertLessThanOrEqual(
                layout.panelWidth + (layout.outerMargin * 2),
                size.width
            )
            XCTAssertLessThanOrEqual(
                layout.panelHeight + (layout.outerMargin * 2),
                size.height
            )
        }
    }

    @MainActor
    func testAllEightGameplayFieldStacksResolveAndPreloadInExactOrder() async throws {
        let catalog = LaunchCatalog.approved
        let preloader = RecordingUniformTexturePreloader()
        let library = TextureLibrary(uniformTexturePreloader: preloader)
        var endZonePaths = Set<String>()
        var brandingPaths = Set<String>()

        for team in catalog.teams {
            let stack = GameplayFieldLayerStack(offenseTeamID: team.id)
            let layers = stack.orderedLayers
            XCTAssertEqual(
                layers.map(\.kind),
                [.neutralBase, .endZone, .fieldBranding, .markings]
            )
            XCTAssertEqual(
                layers.map(\.relativePath),
                [
                    "pixel/stadium-field-neutral-v1.png",
                    "pixel/teams/\(team.id.rawValue)/end-zone.png",
                    "pixel/teams/\(team.id.rawValue)/field-branding.png",
                    "pixel/field-markings-v1.png",
                ]
            )
            endZonePaths.insert(layers[1].relativePath)
            brandingPaths.insert(layers[2].relativePath)

            for layer in layers {
                let url = try XCTUnwrap(GameAssetResources.url(for: layer.relativePath))
                let image = try XCTUnwrap(UIImage(contentsOfFile: url.path))
                let cgImage = try XCTUnwrap(image.cgImage)
                XCTAssertEqual(cgImage.width, 1_728, layer.relativePath)
                XCTAssertEqual(cgImage.height, 768, layer.relativePath)
            }

            let result = await library.prewarmGameplayFieldTextures(stack)
            XCTAssertEqual(result.requestedCount, 4)
            XCTAssertEqual(result.loadedCount, 4)
            XCTAssertEqual(result.preloadedCount, 4)
            XCTAssertTrue(result.isComplete)
        }

        XCTAssertEqual(endZonePaths.count, 8)
        XCTAssertEqual(brandingPaths.count, 8)
        XCTAssertEqual(
            preloader.invocationCount,
            18,
            "Two shared layers preload once and each team contributes two unique layers"
        )
    }

    @MainActor
    func testRunVisualReadinessCombinesUniformAndFieldPreloads() async throws {
        let uniformAssetRoots = try launchUniformAssetRoots()
        let preloader = RecordingUniformTexturePreloader()
        let library = TextureLibrary(
            uniformTexturePreparer: SyntheticUniformTexturePreparer(),
            uniformTexturePreloader: preloader
        )
        let stack = GameplayFieldLayerStack(offenseTeamID: LaunchTeamID.novaCityComets)

        let result = await library.prewarmRunVisualTextures(
            uniformAssetRoots: uniformAssetRoots,
            fieldLayerStack: stack
        )

        XCTAssertEqual(result.requestedCount, 38)
        XCTAssertEqual(result.preparedCount, 38)
        XCTAssertEqual(result.preloadedCount, 38)
        XCTAssertEqual(result.field.requestedCount, 4)
        XCTAssertEqual(result.field.loadedCount, 4)
        XCTAssertEqual(result.field.preloadedCount, 4)
        XCTAssertTrue(result.isComplete)
        XCTAssertEqual(preloader.invocationCount, 38)

        let cached = await library.prewarmRunVisualTextures(
            uniformAssetRoots: uniformAssetRoots,
            fieldLayerStack: stack
        )
        XCTAssertTrue(cached.isComplete)
        XCTAssertEqual(cached.preloadedCount, 38)
        XCTAssertEqual(preloader.invocationCount, 38)
    }

    @MainActor
    func testMissingTeamFieldLayersFailVisualReadinessClosed() async {
        let preloader = RecordingUniformTexturePreloader()
        let library = TextureLibrary(uniformTexturePreloader: preloader)
        let result = await library.prewarmGameplayFieldTextures(
            GameplayFieldLayerStack(offenseTeamID: TeamID("missing_field_team"))
        )

        XCTAssertEqual(result.requestedCount, 4)
        XCTAssertEqual(result.loadedCount, 2)
        XCTAssertEqual(result.preloadedCount, 2)
        XCTAssertFalse(result.isComplete)
    }

    @MainActor
    func testCancellationDuringFieldPreloadSerializesAndRetryCompletes() async throws {
        let firstTextureStarted = VisualLifecycleReceipt(
            "First gameplay field texture preload started"
        )
        let preloader = FirstTextureGatePreloader(firstStarted: firstTextureStarted)
        let library = TextureLibrary(uniformTexturePreloader: preloader)
        let stack = GameplayFieldLayerStack(offenseTeamID: LaunchTeamID.novaCityComets)

        let cancelledTask = Task { @MainActor in
            await library.prewarmGameplayFieldTextures(stack)
        }
        await fulfillment(of: [firstTextureStarted.expectation], timeout: 5)
        cancelledTask.cancel()

        let retryEntered = VisualLifecycleReceipt("Field retry entered TextureLibrary")
        let retryTask = Task { @MainActor in
            retryEntered.record()
            return await library.prewarmGameplayFieldTextures(stack)
        }
        await fulfillment(of: [retryEntered.expectation], timeout: 5)
        preloader.releaseFirstTexture()

        let cancelledResult = await cancelledTask.value
        let retryResult = await retryTask.value
        XCTAssertEqual(cancelledResult.loadedCount, 4)
        XCTAssertEqual(cancelledResult.preloadedCount, 1)
        XCTAssertFalse(cancelledResult.isComplete)
        XCTAssertTrue(retryResult.isComplete)
        XCTAssertEqual(retryResult.preloadedCount, 4)
        XCTAssertEqual(preloader.invocationCount, 4)
        XCTAssertEqual(preloader.maximumConcurrentInvocationCount, 1)
    }

    @MainActor
    func testFieldLayersKeepLegacyPlateRegistrationAcrossLandscapeViewports() throws {
        let viewSizes = [
            CGSize(width: 667, height: 375),
            CGSize(width: 932, height: 430),
            CGSize(width: 1_366, height: 1_024),
        ]

        for viewSize in viewSizes {
            let configuration = try launchRunConfiguration()
            let scene = GameScene(
                size: GameProjection.classicSceneSize,
                configuration: configuration,
                settings: PlayerSettings(isMuted: true, reducedMotion: true),
                textures: TextureLibrary(
                    uniformTexturePreparer: SyntheticUniformTexturePreparer()
                ),
                onCompletedRun: { _ in }
            )
            let view = SKView(frame: CGRect(origin: .zero, size: viewSize))
            let expectedViewport = GameViewport(
                viewSize: viewSize,
                safeAreaInsets: .zero
            )

            scene.didMove(to: view)
            XCTAssertEqual(
                scene.fieldLayerStack.offenseTeamID,
                configuration.offenseTeamID
            )
            for (index, layer) in scene.fieldLayerStack.orderedLayers.enumerated() {
                let node = try XCTUnwrap(
                    scene.childNode(withName: "//\(layer.nodeName)") as? SKSpriteNode
                )
                XCTAssertEqual(node.anchorPoint, CGPoint(x: 0.5, y: 0))
                XCTAssertEqual(node.size, GameplayFieldLayerStack.textureSize)
                XCTAssertEqual(
                    node.position.x,
                    expectedViewport.projection.centerX,
                    accuracy: 0.000_1
                )
                XCTAssertEqual(node.position.y, 0, accuracy: 0.000_1)
                XCTAssertEqual(node.xScale, 1)
                XCTAssertEqual(node.yScale, 1)
                XCTAssertEqual(node.zPosition, -1_000 + CGFloat(index))
            }
            scene.willMove(from: view)
        }
    }

    @MainActor
    func testSidelineEnvironmentRetainsOnlyPylonsAndOfficials() {
        let environment = SidelineEnvironmentNode()
        environment.rebuild(
            for: GameProjection(viewportWidth: GameProjection.maximumFieldArtWidth),
            textures: TextureLibrary()
        )
        let childNames = environment.children.compactMap(\.name)

        XCTAssertEqual(childNames.filter { $0.hasPrefix("sideline.pylon.") }.count, 4)
        XCTAssertEqual(childNames.filter { $0.hasPrefix("sideline.official.") }.count, 2)
        XCTAssertTrue(
            childNames.allSatisfy {
                $0.hasPrefix("sideline.pylon.") || $0.hasPrefix("sideline.official.")
            }
        )
    }

    @MainActor
    func testFiniteRunTextureSetPrewarmsBeforeGameplay() async throws {
        XCTAssertEqual(TextureLibrary.offenseUniformPaths.count, 24)
        XCTAssertEqual(TextureLibrary.defenseUniformPaths.count, 10)
        XCTAssertEqual(Set(TextureLibrary.offenseUniformPaths).count, 24)
        XCTAssertEqual(Set(TextureLibrary.defenseUniformPaths).count, 10)

        let uniformAssetRoots = try launchUniformAssetRoots(offenseAlternate: true)

        let library = TextureLibrary()
        let heartbeat = Task { @MainActor in
            await Task.yield()
            return ProcessInfo.processInfo.systemUptime
        }
        let result = await library.prewarmRunUniformTextures(
            uniformAssetRoots: uniformAssetRoots
        )
        let completionTime = ProcessInfo.processInfo.systemUptime
        let heartbeatTime = await heartbeat.value
        XCTAssertEqual(result.requestedCount, 34)
        XCTAssertEqual(result.preparedCount, 34)
        XCTAssertEqual(result.preloadedCount, 34)
        XCTAssertTrue(result.isComplete)
        XCTAssertLessThan(
            heartbeatTime,
            completionTime,
            "The main actor must remain schedulable while cold raster preprocessing runs"
        )
        XCTAssertLessThan(
            result.mainActorInstallationDurationMilliseconds,
            16.67,
            "Only the final cache installation may run on the main actor, within one 60 Hz frame"
        )

        let firstPassTiming = XCTAttachment(
            string: String(
                format: "Prepared all 34 run-uniform textures in %.3f ms (off-main %.3f ms, max main batch %.3f ms, total main install %.3f ms, SpriteKit preload %.3f ms)",
                result.durationMilliseconds,
                result.preprocessingDurationMilliseconds,
                result.mainActorInstallationDurationMilliseconds,
                result.totalMainActorInstallationDurationMilliseconds,
                result.spriteKitPreloadDurationMilliseconds
            )
        )
        firstPassTiming.name = "Run texture prewarm timing"
        firstPassTiming.lifetime = .keepAlways
        add(firstPassTiming)

        let cachedResult = await library.prewarmRunUniformTextures(
            uniformAssetRoots: uniformAssetRoots
        )
        XCTAssertTrue(cachedResult.isComplete)
        XCTAssertEqual(cachedResult.preloadedCount, 34)
        XCTAssertEqual(cachedResult.preprocessingDurationMilliseconds, 0)
        XCTAssertEqual(cachedResult.mainActorInstallationDurationMilliseconds, 0)
        XCTAssertEqual(cachedResult.totalMainActorInstallationDurationMilliseconds, 0)
        XCTAssertEqual(cachedResult.spriteKitPreloadDurationMilliseconds, 0)
        XCTAssertLessThan(
            cachedResult.durationMilliseconds,
            16.67,
            "All gameplay-time frame swaps must stay cache reads within one 60 Hz frame"
        )
    }

    @MainActor
    func testTexturePrewarmAwaitsInjectedSpriteKitPreloadCompletion() async throws {
        let uniformAssetRoots = try launchUniformAssetRoots()
        let preloader = RecordingUniformTexturePreloader()
        let library = TextureLibrary(uniformTexturePreloader: preloader)

        let result = await library.prewarmRunUniformTextures(
            uniformAssetRoots: uniformAssetRoots
        )

        XCTAssertEqual(preloader.invocationCount, 34)
        XCTAssertEqual(preloader.textureCount, 34)
        XCTAssertTrue(preloader.didComplete)
        XCTAssertEqual(result.preloadedCount, 34)
        XCTAssertTrue(result.isComplete)
    }

    @MainActor
    func testCancelledPrewarmAfterPreparationDoesNotInstallOrPreload() async throws {
        let uniformAssetRoots = try launchUniformAssetRoots()
        let preparationStarted = VisualLifecycleReceipt("Uniform preparation started")
        let cancellationObserved = VisualLifecycleReceipt(
            "Uniform preparation observed task cancellation"
        )
        let preparer = ControlledUniformTexturePreparer(
            firstStarted: preparationStarted,
            firstObservedCancellation: cancellationObserved
        )
        let preloader = RecordingUniformTexturePreloader()
        let library = TextureLibrary(
            uniformTexturePreparer: preparer,
            uniformTexturePreloader: preloader
        )

        let task = Task { @MainActor in
            await library.prewarmRunUniformTextures(
                uniformAssetRoots: uniformAssetRoots
            )
        }
        await fulfillment(of: [preparationStarted.expectation], timeout: 5)

        task.cancel()
        await preparer.completeFirstPreparation()
        await fulfillment(of: [cancellationObserved.expectation], timeout: 5)
        let result = await task.value

        XCTAssertEqual(result.requestedCount, 34)
        XCTAssertEqual(result.preparedCount, 0)
        XCTAssertEqual(result.preloadedCount, 0)
        XCTAssertFalse(result.isComplete)
        XCTAssertEqual(preloader.invocationCount, 0)
        XCTAssertTrue(
            TextureLibrary.offenseUniformPaths.allSatisfy { path in
                library.uniformTexture(
                    path,
                    assetRoot: uniformAssetRoots.offense
                ) == nil
            }
        )
        XCTAssertTrue(
            TextureLibrary.defenseUniformPaths.allSatisfy { path in
                library.uniformTexture(
                    path,
                    assetRoot: uniformAssetRoots.defense
                ) == nil
            }
        )
    }

    @MainActor
    func testCancellationDuringPreloadStopsRemainingUploadsAndSerializesRetry() async throws {
        let uniformAssetRoots = try launchUniformAssetRoots()
        let firstTextureStarted = VisualLifecycleReceipt("First texture preload started")
        let preloader = FirstTextureGatePreloader(firstStarted: firstTextureStarted)
        let library = TextureLibrary(
            uniformTexturePreparer: SyntheticUniformTexturePreparer(),
            uniformTexturePreloader: preloader
        )

        let cancelledTask = Task { @MainActor in
            await library.prewarmRunUniformTextures(
                uniformAssetRoots: uniformAssetRoots
            )
        }
        await fulfillment(of: [firstTextureStarted.expectation], timeout: 5)
        cancelledTask.cancel()

        let retryEntered = VisualLifecycleReceipt("Retry entered TextureLibrary")
        let retryTask = Task { @MainActor in
            retryEntered.record()
            return await library.prewarmRunUniformTextures(
                uniformAssetRoots: uniformAssetRoots
            )
        }
        await fulfillment(of: [retryEntered.expectation], timeout: 5)
        preloader.releaseFirstTexture()

        let cancelledResult = await cancelledTask.value
        let retryResult = await retryTask.value
        XCTAssertEqual(cancelledResult.preparedCount, 34)
        XCTAssertEqual(cancelledResult.preloadedCount, 1)
        XCTAssertFalse(cancelledResult.isComplete)
        XCTAssertTrue(retryResult.isComplete)
        XCTAssertEqual(retryResult.preloadedCount, 34)
        XCTAssertEqual(preloader.invocationCount, 35)
        XCTAssertEqual(preloader.maximumConcurrentInvocationCount, 1)

        let cachedResult = await library.prewarmRunUniformTextures(
            uniformAssetRoots: uniformAssetRoots
        )
        XCTAssertTrue(cachedResult.isComplete)
        XCTAssertEqual(cachedResult.preprocessingDurationMilliseconds, 0)
        XCTAssertEqual(cachedResult.totalMainActorInstallationDurationMilliseconds, 0)
        XCTAssertEqual(cachedResult.spriteKitPreloadDurationMilliseconds, 0)
        XCTAssertEqual(preloader.invocationCount, 35)
    }

    @MainActor
    func testGameSceneTeardownCancelsPrewarmWithoutRetainingScene() async throws {
        let uniformAssetRoots = try launchUniformAssetRoots()
        let preparationStarted = VisualLifecycleReceipt("Scene uniform preparation started")
        let cancellationObserved = VisualLifecycleReceipt(
            "Scene uniform preparation observed cancellation"
        )
        let preparer = ControlledUniformTexturePreparer(
            firstStarted: preparationStarted,
            firstObservedCancellation: cancellationObserved
        )
        let preloader = RecordingUniformTexturePreloader()
        let library = TextureLibrary(
            uniformTexturePreparer: preparer,
            uniformTexturePreloader: preloader
        )
        let configuration = try launchRunConfiguration()
        let view = SKView(frame: CGRect(origin: .zero, size: GameProjection.classicSceneSize))
        var scene: GameScene? = GameScene(
            size: GameProjection.classicSceneSize,
            configuration: configuration,
            settings: PlayerSettings(),
            textures: library,
            onCompletedRun: { _ in }
        )
        weak var releasedScene = scene

        scene?.didMove(to: view)
        await fulfillment(of: [preparationStarted.expectation], timeout: 5)
        scene?.willMove(from: view)
        scene = nil
        XCTAssertNil(
            releasedScene,
            "The preload task must not retain a torn-down GameScene across preparation"
        )

        await preparer.completeFirstPreparation()
        await fulfillment(of: [cancellationObserved.expectation], timeout: 5)

        // A live retry is event-driven proof that the cancelled scene task
        // released TextureLibrary's serialized prewarm turn without uploading.
        let retryResult = await library.prewarmRunUniformTextures(
            uniformAssetRoots: uniformAssetRoots
        )
        XCTAssertTrue(retryResult.isComplete)
        XCTAssertEqual(preloader.invocationCount, 34)
    }

    @MainActor
    func testGameSceneExposesReadinessBeforeStartingCountdown() async throws {
        let catalog = LaunchCatalog.approved
        let offense = try XCTUnwrap(catalog.team(id: LaunchTeamID.highMesaHelions))
        let defense = try XCTUnwrap(catalog.team(id: LaunchTeamID.novaCityComets))
        let configuration = RunConfiguration(
            runID: RunID(),
            randomSeed: 17,
            offenseTeamID: offense.id,
            offenseJerseyID: offense.alternateJersey.id,
            defenseTeamID: defense.id,
            defenseJerseyID: defense.primaryJersey.id,
            footballID: LaunchFootballID.alternate,
            economyVersion: EconomyConfiguration.currentVersion,
            startedAt: Date(timeIntervalSince1970: 1)
        )
        let scene = GameScene(
            size: GameProjection.classicSceneSize,
            configuration: configuration,
            settings: PlayerSettings(),
            onCompletedRun: { _ in }
        )
        let view = SKView(frame: CGRect(origin: .zero, size: GameProjection.classicSceneSize))

        scene.didMove(to: view)
        XCTAssertEqual(scene.visualReadiness, .preparing)
        XCTAssertNotNil(scene.childNode(withName: "//visualReadiness.loading"))

        let deadline = ProcessInfo.processInfo.systemUptime + 8
        while scene.visualReadiness == .preparing,
              ProcessInfo.processInfo.systemUptime < deadline {
            await Task.yield()
        }

        XCTAssertEqual(scene.visualReadiness, .ready)
        XCTAssertNil(scene.childNode(withName: "//visualReadiness.loading"))
        let result = try XCTUnwrap(scene.visualPreparationResult)
        XCTAssertTrue(result.isComplete)
        XCTAssertEqual(result.preloadedCount, 38)
        XCTAssertEqual(result.field.preloadedCount, 4)
        XCTAssertLessThan(result.mainActorInstallationDurationMilliseconds, 16.67)

        for layer in scene.fieldLayerStack.orderedLayers {
            let node = try XCTUnwrap(
                scene.childNode(withName: "//\(layer.nodeName)") as? SKSpriteNode
            )
            XCTAssertNotNil(node.texture)
        }

        scene.willMove(from: view)
        scene.didMove(to: view)
        XCTAssertEqual(scene.visualReadiness, .preparing)
        XCTAssertNil(scene.visualPreparationResult)
        for layer in scene.fieldLayerStack.orderedLayers {
            let node = try XCTUnwrap(
                scene.childNode(withName: "//\(layer.nodeName)") as? SKSpriteNode
            )
            XCTAssertNil(node.texture)
        }
        scene.update(0)
        for step in 1 ... 31 {
            scene.update(TimeInterval(step) / 10)
        }
        XCTAssertFalse(
            scene.pause(),
            "A remount must not advance countdown before rebuilt field nodes are ready"
        )

        let remountDeadline = ProcessInfo.processInfo.systemUptime + 8
        while scene.visualReadiness == .preparing,
              ProcessInfo.processInfo.systemUptime < remountDeadline {
            await Task.yield()
        }
        XCTAssertEqual(scene.visualReadiness, .ready)
        XCTAssertEqual(scene.visualPreparationResult?.preloadedCount, 38)
        for layer in scene.fieldLayerStack.orderedLayers {
            let node = try XCTUnwrap(
                scene.childNode(withName: "//\(layer.nodeName)") as? SKSpriteNode
            )
            XCTAssertNotNil(node.texture)
        }
        scene.willMove(from: view)
    }

    private func launchUniformAssetRoots(
        offenseAlternate: Bool = false
    ) throws -> RunGameplayUniformAssetRoots {
        let catalog = LaunchCatalog.approved
        let offenseTeam = try XCTUnwrap(catalog.team(id: LaunchTeamID.novaCityComets))
        let defenseTeam = try XCTUnwrap(catalog.team(id: LaunchTeamID.highMesaHelions))
        let configuration = RunConfiguration(
            runID: RunID(),
            randomSeed: 29,
            offenseTeamID: offenseTeam.id,
            offenseJerseyID: offenseAlternate
                ? offenseTeam.alternateJersey.id
                : offenseTeam.primaryJersey.id,
            defenseTeamID: defenseTeam.id,
            defenseJerseyID: defenseTeam.primaryJersey.id,
            footballID: LaunchFootballID.standard,
            economyVersion: EconomyConfiguration.currentVersion,
            startedAt: Date(timeIntervalSince1970: 1)
        )
        return try XCTUnwrap(
            RunGameplayUniformAssetRoots(configuration: configuration, catalog: catalog)
        )
    }

    private func launchRunConfiguration() throws -> RunConfiguration {
        let catalog = LaunchCatalog.approved
        let offense = try XCTUnwrap(catalog.team(id: LaunchTeamID.novaCityComets))
        let defense = try XCTUnwrap(catalog.team(id: LaunchTeamID.highMesaHelions))
        return RunConfiguration(
            runID: RunID(),
            randomSeed: 29,
            offenseTeamID: offense.id,
            offenseJerseyID: offense.primaryJersey.id,
            defenseTeamID: defense.id,
            defenseJerseyID: defense.primaryJersey.id,
            footballID: LaunchFootballID.standard,
            economyVersion: EconomyConfiguration.currentVersion,
            startedAt: Date(timeIntervalSince1970: 1)
        )
    }
}

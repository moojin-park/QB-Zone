import Foundation
import SpriteKit
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

    func testSharedUniformPixelsProjectToExactJerseySlotsWithoutTintingSkin() throws {
        let visuals = LaunchVisualIdentityCatalog.approved
        let team = try XCTUnwrap(LaunchCatalog.approved.team(id: LaunchTeamID.novaCityComets))
        let primary = try XCTUnwrap(
            visuals.uniform(teamID: team.id, jerseyID: team.primaryJersey.id, role: .offense)
        )
        let alternate = try XCTUnwrap(
            visuals.uniform(teamID: team.id, jerseyID: team.alternateJersey.id, role: .offense)
        )
        let authoredRed = UniformPixel(red: 210, green: 35, blue: 38, alpha: 255)
        let primaryBody = UniformTextureProjection.project(
            authoredRed,
            normalizedX: 0.5,
            normalizedY: 0.45,
            role: .offense,
            palette: primary
        )
        let alternateBody = UniformTextureProjection.project(
            authoredRed,
            normalizedX: 0.5,
            normalizedY: 0.45,
            role: .offense,
            palette: alternate
        )
        XCTAssertNotEqual(primaryBody, authoredRed)
        XCTAssertNotEqual(primaryBody, alternateBody)

        let authoredBlue = UniformPixel(red: 28, green: 112, blue: 220, alpha: 255)
        let defense = try XCTUnwrap(
            visuals.uniform(
                teamID: LaunchTeamID.highMesaHelions,
                jerseyID: JerseyID("jersey.high_mesa_helions.primary"),
                role: .defense
            )
        )
        let defenseBody = UniformTextureProjection.project(
            authoredBlue,
            normalizedX: 0.5,
            normalizedY: 0.45,
            role: .defense,
            palette: defense
        )
        let defenseHelmet = UniformTextureProjection.project(
            authoredBlue,
            normalizedX: 0.5,
            normalizedY: 0.35,
            role: .defense,
            palette: defense
        )
        XCTAssertNotEqual(defenseBody, authoredBlue)
        XCTAssertNotEqual(defenseHelmet, authoredBlue)
        XCTAssertNotEqual(defenseHelmet, defenseBody)

        let skin = UniformPixel(red: 176, green: 100, blue: 56, alpha: 255)
        XCTAssertEqual(
            UniformTextureProjection.project(
                skin,
                normalizedX: 0.5,
                normalizedY: 0.45,
                role: .offense,
                palette: primary
            ),
            skin
        )

        let neutralSkinHighlight = UniformPixel(red: 220, green: 198, blue: 190, alpha: 255)
        XCTAssertEqual(
            UniformTextureProjection.project(
                neutralSkinHighlight,
                normalizedX: 0.22,
                normalizedY: 0.43,
                role: .offense,
                palette: primary
            ),
            neutralSkinHighlight
        )

        let eyeWhite = UniformPixel(red: 248, green: 246, blue: 240, alpha: 255)
        XCTAssertEqual(
            UniformTextureProjection.project(
                eyeWhite,
                normalizedX: 0.5,
                normalizedY: 0.25,
                role: .offense,
                palette: primary
            ),
            eyeWhite
        )
        XCTAssertNotEqual(
            UniformTextureProjection.project(
                eyeWhite,
                normalizedX: 0.5,
                normalizedY: 0.45,
                role: .offense,
                palette: primary
            ),
            eyeWhite,
            "The same authored neutral is a number/name slot below the protected face region"
        )

        let antialiasedRedEdge = UniformPixel(red: 128, green: 0, blue: 0, alpha: 128)
        let projectedEdge = UniformTextureProjection.project(
            antialiasedRedEdge,
            normalizedX: 0.5,
            normalizedY: 0.45,
            role: .offense,
            palette: primary
        )
        XCTAssertNotEqual(projectedEdge, antialiasedRedEdge)
        XCTAssertEqual(projectedEdge.alpha, antialiasedRedEdge.alpha)
        XCTAssertLessThanOrEqual(projectedEdge.red, projectedEdge.alpha)
        XCTAssertLessThanOrEqual(projectedEdge.green, projectedEdge.alpha)
        XCTAssertLessThanOrEqual(projectedEdge.blue, projectedEdge.alpha)
    }

    func testShippedRasterUsesAuthoredTopToBottomUniformSlots() throws {
        let relativePath = "characters/qb-idle.webp"
        let source = try XCTUnwrap(
            UniformRasterPreprocessor.loadRaster(relativePath: relativePath)
        )
        XCTAssertEqual(source.width, 384)
        XCTAssertEqual(source.height, 512)

        let team = try XCTUnwrap(
            LaunchCatalog.approved.team(id: LaunchTeamID.novaCityComets)
        )
        let palette = try XCTUnwrap(
            LaunchVisualIdentityCatalog.approved.uniform(
                teamID: team.id,
                jerseyID: team.primaryJersey.id,
                role: .offense
            )
        )
        let projected = UniformRasterPreprocessor.projectedRaster(
            source,
            palette: palette,
            role: .offense
        )

        let helmetX = 165
        let helmetY = 120
        let helmetSource = try XCTUnwrap(source.pixel(x: helmetX, y: helmetY))
        XCTAssertGreaterThan(helmetSource.red, helmetSource.green)
        let helmetExpected = UniformTextureProjection.project(
            helmetSource,
            normalizedX: CGFloat(helmetX) / CGFloat(source.width - 1),
            normalizedY: CGFloat(helmetY) / CGFloat(source.height - 1),
            role: .offense,
            palette: palette
        )
        let helmetActual = try XCTUnwrap(projected.pixel(x: helmetX, y: helmetY))
        XCTAssertEqual(helmetActual, helmetExpected)
        XCTAssertNotEqual(helmetActual, helmetSource)
        XCTAssertNotEqual(
            helmetActual,
            UniformTextureProjection.project(
                helmetSource,
                normalizedX: CGFloat(helmetX) / CGFloat(source.width - 1),
                normalizedY: 1 - CGFloat(helmetY) / CGFloat(source.height - 1),
                role: .offense,
                palette: palette
            ),
            "An inverted scanline would incorrectly assign this authored helmet to a lower slot"
        )

        let sockX = 135
        let sockY = 400
        let sockSource = try XCTUnwrap(source.pixel(x: sockX, y: sockY))
        XCTAssertGreaterThan(sockSource.red, sockSource.green)
        let sockActual = try XCTUnwrap(projected.pixel(x: sockX, y: sockY))
        XCTAssertEqual(
            sockActual,
            UniformTextureProjection.project(
                sockSource,
                normalizedX: CGFloat(sockX) / CGFloat(source.width - 1),
                normalizedY: CGFloat(sockY) / CGFloat(source.height - 1),
                role: .offense,
                palette: palette
            )
        )
        XCTAssertNotEqual(sockActual, sockSource)

        let skinX = 104
        let skinY = 250
        let skinSource = try XCTUnwrap(source.pixel(x: skinX, y: skinY))
        XCTAssertEqual(
            try XCTUnwrap(projected.pixel(x: skinX, y: skinY)),
            skinSource,
            "A known shipped skin highlight must survive real-raster palette projection"
        )
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

    func testPausedGameplayConfirmedExitIsGatedAndExactOnce() {
        var requestState = GameplayPauseRequestState()

        XCTAssertFalse(requestState.requestConfirmedExit(whilePaused: false))
        XCTAssertTrue(requestState.requestConfirmedExit(whilePaused: true))
        XCTAssertFalse(requestState.requestConfirmedExit(whilePaused: true))
        XCTAssertFalse(requestState.requestResume(whilePaused: true))
        XCTAssertEqual(requestState.confirmedExitRequestID, 1)
        XCTAssertTrue(requestState.confirmedExitRequestPending)
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
    func testFiniteRunTextureSetPrewarmsBeforeGameplay() async throws {
        XCTAssertEqual(TextureLibrary.offenseUniformPaths.count, 24)
        XCTAssertEqual(TextureLibrary.defenseUniformPaths.count, 10)
        XCTAssertEqual(Set(TextureLibrary.offenseUniformPaths).count, 24)
        XCTAssertEqual(Set(TextureLibrary.defenseUniformPaths).count, 10)

        let visuals = LaunchVisualIdentityCatalog.approved
        let offenseTeam = try XCTUnwrap(
            LaunchCatalog.approved.team(id: LaunchTeamID.novaCityComets)
        )
        let defenseTeam = try XCTUnwrap(
            LaunchCatalog.approved.team(id: LaunchTeamID.highMesaHelions)
        )
        let offense = try XCTUnwrap(
            visuals.uniform(
                teamID: offenseTeam.id,
                jerseyID: offenseTeam.alternateJersey.id,
                role: .offense
            )
        )
        let defense = try XCTUnwrap(
            visuals.uniform(
                teamID: defenseTeam.id,
                jerseyID: defenseTeam.primaryJersey.id,
                role: .defense
            )
        )

        let library = TextureLibrary()
        let heartbeat = Task { @MainActor in
            await Task.yield()
            return ProcessInfo.processInfo.systemUptime
        }
        let result = await library.prewarmRunUniformTextures(
            offensePalette: offense,
            defensePalette: defense
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
            offensePalette: offense,
            defensePalette: defense
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
        let visuals = LaunchVisualIdentityCatalog.approved
        let catalog = LaunchCatalog.approved
        let offenseTeam = try XCTUnwrap(catalog.team(id: LaunchTeamID.novaCityComets))
        let defenseTeam = try XCTUnwrap(catalog.team(id: LaunchTeamID.highMesaHelions))
        let offense = try XCTUnwrap(
            visuals.uniform(
                teamID: offenseTeam.id,
                jerseyID: offenseTeam.primaryJersey.id,
                role: .offense
            )
        )
        let defense = try XCTUnwrap(
            visuals.uniform(
                teamID: defenseTeam.id,
                jerseyID: defenseTeam.primaryJersey.id,
                role: .defense
            )
        )
        let preloader = RecordingUniformTexturePreloader()
        let library = TextureLibrary(uniformTexturePreloader: preloader)

        let result = await library.prewarmRunUniformTextures(
            offensePalette: offense,
            defensePalette: defense
        )

        XCTAssertEqual(preloader.invocationCount, 34)
        XCTAssertEqual(preloader.textureCount, 34)
        XCTAssertTrue(preloader.didComplete)
        XCTAssertEqual(result.preloadedCount, 34)
        XCTAssertTrue(result.isComplete)
    }

    @MainActor
    func testCancelledPrewarmAfterPreparationDoesNotInstallOrPreload() async throws {
        let palettes = try launchUniformPalettes()
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
                offensePalette: palettes.offense,
                defensePalette: palettes.defense
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
                    palette: palettes.offense,
                    role: .offense
                ) == nil
            }
        )
        XCTAssertTrue(
            TextureLibrary.defenseUniformPaths.allSatisfy { path in
                library.uniformTexture(
                    path,
                    palette: palettes.defense,
                    role: .defense
                ) == nil
            }
        )
    }

    @MainActor
    func testCancellationDuringPreloadStopsRemainingUploadsAndSerializesRetry() async throws {
        let palettes = try launchUniformPalettes()
        let firstTextureStarted = VisualLifecycleReceipt("First texture preload started")
        let preloader = FirstTextureGatePreloader(firstStarted: firstTextureStarted)
        let library = TextureLibrary(
            uniformTexturePreparer: SyntheticUniformTexturePreparer(),
            uniformTexturePreloader: preloader
        )

        let cancelledTask = Task { @MainActor in
            await library.prewarmRunUniformTextures(
                offensePalette: palettes.offense,
                defensePalette: palettes.defense
            )
        }
        await fulfillment(of: [firstTextureStarted.expectation], timeout: 5)
        cancelledTask.cancel()

        let retryEntered = VisualLifecycleReceipt("Retry entered TextureLibrary")
        let retryTask = Task { @MainActor in
            retryEntered.record()
            return await library.prewarmRunUniformTextures(
                offensePalette: palettes.offense,
                defensePalette: palettes.defense
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
            offensePalette: palettes.offense,
            defensePalette: palettes.defense
        )
        XCTAssertTrue(cachedResult.isComplete)
        XCTAssertEqual(cachedResult.preprocessingDurationMilliseconds, 0)
        XCTAssertEqual(cachedResult.totalMainActorInstallationDurationMilliseconds, 0)
        XCTAssertEqual(cachedResult.spriteKitPreloadDurationMilliseconds, 0)
        XCTAssertEqual(preloader.invocationCount, 35)
    }

    @MainActor
    func testGameSceneTeardownCancelsPrewarmWithoutRetainingScene() async throws {
        let palettes = try launchUniformPalettes()
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
            offensePalette: palettes.offense,
            defensePalette: palettes.defense
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
        XCTAssertEqual(result.preloadedCount, 34)
        XCTAssertLessThan(result.mainActorInstallationDurationMilliseconds, 16.67)
    }

    private func launchUniformPalettes() throws -> (
        offense: UniformSpritePalette,
        defense: UniformSpritePalette
    ) {
        let visuals = LaunchVisualIdentityCatalog.approved
        let catalog = LaunchCatalog.approved
        let offenseTeam = try XCTUnwrap(catalog.team(id: LaunchTeamID.novaCityComets))
        let defenseTeam = try XCTUnwrap(catalog.team(id: LaunchTeamID.highMesaHelions))
        return (
            offense: try XCTUnwrap(
                visuals.uniform(
                    teamID: offenseTeam.id,
                    jerseyID: offenseTeam.primaryJersey.id,
                    role: .offense
                )
            ),
            defense: try XCTUnwrap(
                visuals.uniform(
                    teamID: defenseTeam.id,
                    jerseyID: defenseTeam.primaryJersey.id,
                    role: .defense
                )
            )
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

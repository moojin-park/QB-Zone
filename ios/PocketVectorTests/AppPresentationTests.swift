import Foundation
import SwiftUI
import UIKit
import XCTest

@testable import PocketVector

final class AppPresentationTests: XCTestCase {
    @MainActor
    func testCaptureSharedHeaderAccessibilityMatrix() async throws {
        let coordinator = AppCoordinator()
        await coordinator.bootstrap()
        coordinator.showTutorialReview()

        let results = try makeRunResultsPresentation()
        let surfaces: [(name: String, view: AnyView)] = [
            ("choose-offense", AnyView(TeamSelectionView(coordinator: coordinator))),
            ("team-locker", AnyView(LockerView(coordinator: coordinator))),
            ("coin-store", AnyView(CoinStoreView(coordinator: coordinator))),
            ("achievements", AnyView(AchievementsView(coordinator: coordinator))),
            ("settings", AnyView(SettingsView(coordinator: coordinator))),
            (
                "tutorial-rules",
                AnyView(TutorialView(coordinator: coordinator, initialPage: .gameRules))
            ),
            (
                "tutorial-passing",
                AnyView(TutorialView(coordinator: coordinator, initialPage: .passing))
            ),
            (
                "results",
                AnyView(RunResultsView(results: results, coordinator: coordinator))
            ),
        ]
        let viewports: [(
            name: String,
            size: CGSize,
            horizontalSizeClass: UserInterfaceSizeClass,
            verticalSizeClass: UserInterfaceSizeClass,
            dynamicTypeSize: DynamicTypeSize
        )] = [
            (
                "compact-iphone-landscape-accessibility5",
                CGSize(width: 667, height: 375),
                .compact,
                .compact,
                .accessibility5
            ),
            (
                "regular-iphone-landscape-accessibility5",
                CGSize(width: 874, height: 402),
                .compact,
                .compact,
                .accessibility5
            ),
            (
                "ipad-landscape-accessibility5",
                CGSize(width: 1_376, height: 1_032),
                .regular,
                .regular,
                .accessibility5
            ),
            (
                "regular-iphone-landscape-standard",
                CGSize(width: 874, height: 402),
                .compact,
                .compact,
                .large
            ),
            (
                "ipad-landscape-standard",
                CGSize(width: 1_376, height: 1_032),
                .regular,
                .regular,
                .large
            ),
        ]

        for viewport in viewports {
            for surface in surfaces {
                capture(
                    AnyView(
                        ZStack {
                            PocketVectorBackdrop()
                            surface.view
                        }
                        .dynamicTypeSize(viewport.dynamicTypeSize)
                        .environment(\.horizontalSizeClass, viewport.horizontalSizeClass)
                        .environment(\.verticalSizeClass, viewport.verticalSizeClass)
                    ),
                    size: viewport.size,
                    name: "shared-header-\(surface.name)-\(viewport.name)"
                )
            }
        }
    }

    @MainActor
    func testCaptureTutorialAndResultsLayoutMatrix() async throws {
        let tutorialCoordinator = AppCoordinator()
        await tutorialCoordinator.bootstrap()
        tutorialCoordinator.showTutorialReview()

        let resultsCoordinator = AppCoordinator()
        let results = try makeRunResultsPresentation()
        let viewports: [(name: String, size: CGSize)] = [
            ("compact-iphone-landscape", CGSize(width: 667, height: 375)),
            ("regular-iphone-landscape", CGSize(width: 874, height: 402)),
            ("ipad-landscape", CGSize(width: 1_376, height: 1_032)),
        ]
        let textSizes: [(name: String, size: DynamicTypeSize)] = [
            ("standard", .large),
            ("accessibility5", .accessibility5),
        ]

        for viewport in viewports {
            for textSize in textSizes {
                capture(
                    AnyView(
                        ZStack {
                            PocketVectorBackdrop()
                            TutorialView(
                                coordinator: tutorialCoordinator,
                                initialPage: .gameRules
                            )
                        }
                        .dynamicTypeSize(textSize.size)
                    ),
                    size: viewport.size,
                    name: "tutorial-rules-\(viewport.name)-\(textSize.name)"
                )
                capture(
                    AnyView(
                        ZStack {
                            PocketVectorBackdrop()
                            TutorialView(
                                coordinator: tutorialCoordinator,
                                initialPage: .passing
                            )
                        }
                        .dynamicTypeSize(textSize.size)
                    ),
                    size: viewport.size,
                    name: "tutorial-passing-\(viewport.name)-\(textSize.name)"
                )
                capture(
                    AnyView(
                        ZStack {
                            PocketVectorBackdrop()
                            RunResultsView(results: results, coordinator: resultsCoordinator)
                        }
                        .dynamicTypeSize(textSize.size)
                    ),
                    size: viewport.size,
                    name: "results-option3-\(viewport.name)-\(textSize.name)"
                )
            }
        }
    }

    func testTutorialMediaCacheRejectsSameSizeCorruption() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PocketVectorTutorialCacheTests")
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }

        let expectedData = Data(repeating: 0xA5, count: 64)
        let mediaURL = try TutorialMediaCache.validatedURL(
            for: expectedData,
            directory: directory
        )
        XCTAssertTrue(TutorialMediaCache.fileMatches(at: mediaURL, expectedData: expectedData))

        try Data(repeating: 0x5A, count: expectedData.count)
            .write(to: mediaURL, options: .atomic)
        XCTAssertFalse(TutorialMediaCache.fileMatches(at: mediaURL, expectedData: expectedData))

        let repairedURL = try TutorialMediaCache.validatedURL(
            for: expectedData,
            directory: directory
        )
        XCTAssertEqual(try Data(contentsOf: repairedURL), expectedData)
    }

    func testTutorialScoringGuidanceDefinesPenaltyAndScoreFloor() {
        XCTAssertEqual(
            TutorialRule.scoring.guidance,
            "Completions and touchdowns add points. An interception is a −250-point penalty, but your score cannot fall below zero."
        )
    }

    func testTutorialPassingPageHasRulesAsPreviousPage() {
        XCTAssertEqual(TutorialPage.passing.previous, .gameRules)
        XCTAssertNil(TutorialPage.gameRules.previous)
    }

    func testTutorialPassingGuidanceExplainsBulletAndLobReleaseTiming() {
        XCTAssertEqual(
            TutorialPassingGuidance.instruction,
            "Start on the quarterback, drag to open grass away from defenders, then release. "
                + "Release quickly for a bullet (low trajectory), or hold longer before releasing for a lob "
                + "(high trajectory). The receiver runs under the throw."
        )
    }

    func testTutorialPlaybackOnlyRunsOnActivePassingPageWithMotionEnabled() {
        XCTAssertFalse(TutorialPlaybackPolicy.shouldPlay(
            page: .gameRules,
            mediaIsReady: true,
            reducesMotion: false,
            sceneIsActive: true
        ))
        XCTAssertFalse(TutorialPlaybackPolicy.shouldPlay(
            page: .passing,
            mediaIsReady: true,
            reducesMotion: true,
            sceneIsActive: true
        ))
        XCTAssertFalse(TutorialPlaybackPolicy.shouldPlay(
            page: .passing,
            mediaIsReady: true,
            reducesMotion: false,
            sceneIsActive: false
        ))
        XCTAssertTrue(TutorialPlaybackPolicy.shouldPlay(
            page: .passing,
            mediaIsReady: true,
            reducesMotion: false,
            sceneIsActive: true
        ))
    }

    func testRunResultsCoinLedgerUsesApprovedOrderAndReconcilesToTotal() throws {
        let results = try makeRunResultsPresentation()
        let ledger = RunResultsCoinLedger(results: results)

        XCTAssertEqual(
            ledger.lines.map(\.label),
            ["RUN COMPLETE", "SCORE BONUS", "ACCURACY BONUS", "FIRST RUN BONUS"]
        )
        XCTAssertEqual(ledger.lines.map(\.amount), [10, 12, 5, 250])
        XCTAssertEqual(ledger.total, 277)
        XCTAssertEqual(ledger.lines.reduce(0) { $0 + $1.amount }, ledger.total)
    }

    func testRunResultsCoinLedgerOmitsUnearnedSigningBonus() throws {
        let firstRunResults = try makeRunResultsPresentation()
        let laterRunResults = RunResultsPresentation(
            completedRun: firstRunResults.completedRun,
            earnedCoins: 27,
            pendingCoins: 0,
            personalBest: firstRunResults.personalBest,
            isNewPersonalBest: false,
            rewardedAdOffer: firstRunResults.rewardedAdOffer
        )
        let ledger = RunResultsCoinLedger(results: laterRunResults)

        XCTAssertEqual(
            ledger.lines.map(\.label),
            ["RUN COMPLETE", "SCORE BONUS", "ACCURACY BONUS"]
        )
        XCTAssertEqual(ledger.lines.reduce(0) { $0 + $1.amount }, ledger.total)
    }

    func testTeamPresentationUsesAllEightApprovedTeamsAndLockedPrices() throws {
        let catalog = LaunchCatalog.approved
        let state = AppCoordinatorState.launchDefault(catalog: catalog)
        let cards = AppPresentation.teams(catalog: catalog, state: state)

        XCTAssertEqual(cards.map(\.id), catalog.teams.map(\.id))
        XCTAssertEqual(cards.count, 8)
        XCTAssertEqual(cards.filter(\.isOwned).count, 4)
        XCTAssertEqual(cards.filter(\.isLocked).count, 4)
        XCTAssertTrue(cards.first?.isSelected == true)
        XCTAssertEqual(
            Set(cards.filter(\.isLocked).compactMap(\.unlockItem?.price)),
            [EconomyConfiguration.lockedTeamPrice]
        )
    }

    func testLockerPresentationKeepsAlternateJerseyTeamScopedAndFootballGlobal() throws {
        let catalog = LaunchCatalog.approved
        let state = AppCoordinatorState.launchDefault(catalog: catalog)
        let team = try XCTUnwrap(catalog.team(id: LaunchTeamID.novaCityComets))

        let jerseys = AppPresentation.jerseys(for: team, catalog: catalog, state: state)
        XCTAssertEqual(jerseys.count, 2)
        XCTAssertTrue(jerseys[0].isOwned)
        XCTAssertTrue(jerseys[0].isEquipped)
        XCTAssertFalse(jerseys[1].isOwned)
        XCTAssertEqual(jerseys[1].unlockItem?.price, EconomyConfiguration.alternateJerseyPrice)
        XCTAssertEqual(jerseys[1].jersey.teamID, team.id)

        let footballs = AppPresentation.footballs(catalog: catalog, state: state)
        XCTAssertEqual(footballs.count, 2)
        XCTAssertTrue(footballs[0].isEquipped)
        XCTAssertEqual(footballs[1].unlockItem?.price, EconomyConfiguration.alternateFootballPrice)
    }

    func testAchievementSummaryAlwaysRepresentsAllEightAndSixHundredPoints() {
        var progress = Dictionary(
            uniqueKeysWithValues: AchievementCatalog.launch.map {
                ($0.id, AchievementProgress(id: $0.id))
            }
        )
        let completed = AchievementCatalog.launch[0]
        progress[completed.id] = AchievementProgress(
            id: completed.id,
            percentComplete: 100,
            completedAt: Date(timeIntervalSince1970: 1)
        )

        let cards = AppPresentation.achievements(progress: progress)
        let summary = AppPresentation.achievementSummary(cards: cards)

        XCTAssertEqual(cards.count, 8)
        XCTAssertEqual(summary.completedCount, 1)
        XCTAssertEqual(summary.totalCount, 8)
        XCTAssertEqual(summary.earnedPoints, completed.points)
        XCTAssertEqual(summary.totalPoints, 600)
    }

    func testCoinPackPresentationMatchesApprovedLaunchSurface() {
        XCTAssertEqual(
            EconomyConfiguration.coinPacks.map(\.coins),
            [750, 2_500, 6_000, 11_000]
        )
        XCTAssertEqual(
            EconomyConfiguration.coinPacks.map {
                AppPresentation.proposedUSPriceText($0.proposedUSPrice)
            },
            ["$0.99", "$2.99", "$5.99", "$9.99"]
        )
        XCTAssertEqual(AppPresentation.coinText(11_000), "11,000")
    }

    @MainActor
    private func capture(_ view: AnyView, size: CGSize, name: String) {
        let host = UIHostingController(rootView: view)
        host.view.frame = CGRect(origin: .zero, size: size)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        XCTAssertEqual(image.size, size)
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func makeRunResultsPresentation() throws -> RunResultsPresentation {
        let catalog = LaunchCatalog.approved
        let offense = try XCTUnwrap(catalog.team(id: LaunchTeamID.novaCityComets))
        let defense = try XCTUnwrap(catalog.team(id: LaunchTeamID.highMesaHelions))
        let configuration = RunConfiguration(
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
        let completedRun = CompletedRun(
            configuration: configuration,
            endedAt: Date(timeIntervalSince1970: 61),
            elapsedGameplayMilliseconds: 60_000,
            finishReason: .timerExpired,
            score: 12_500,
            statistics: RunStatisticsSnapshot(
                attempts: 14,
                completions: 7,
                touchdowns: 3,
                incompletions: 3,
                interceptions: 1,
                longestTouchdownStreak: 2
            ),
            completedLaneIDs: [],
            bonusTouchdownCount: 1
        )
        return RunResultsPresentation(
            completedRun: completedRun,
            earnedCoins: 277,
            pendingCoins: 0,
            personalBest: 12_500,
            isNewPersonalBest: true,
            rewardedAdOffer: .progress(validRuns: 2, requiredRuns: 5)
        )
    }
}

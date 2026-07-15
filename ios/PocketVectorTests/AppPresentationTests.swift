import Foundation
import XCTest

@testable import PocketVector

final class AppPresentationTests: XCTestCase {
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
            [500, 1_650, 3_600, 6_500]
        )
        XCTAssertEqual(
            EconomyConfiguration.coinPacks.map {
                AppPresentation.proposedUSPriceText($0.proposedUSPrice)
            },
            ["$0.99", "$2.99", "$5.99", "$9.99"]
        )
        XCTAssertEqual(AppPresentation.coinText(6_500), "6,500")
    }
}

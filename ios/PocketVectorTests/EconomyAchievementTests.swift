import Foundation
import XCTest

@testable import PocketVector

final class EconomyAchievementTests: XCTestCase {
    func testApprovedEconomyAndCoinPackValues() {
        XCTAssertEqual(EconomyConfiguration.signingBonusCoins, 250)
        XCTAssertEqual(EconomyConfiguration.rewardedAdCoins, 100)
        XCTAssertEqual(EconomyConfiguration.rewardedAdRunThreshold, 5)
        XCTAssertEqual(EconomyConfiguration.lockedTeamPrice, 1_500)
        XCTAssertEqual(EconomyConfiguration.alternateJerseyPrice, 500)
        XCTAssertEqual(EconomyConfiguration.alternateFootballPrice, 750)
        XCTAssertEqual(EconomyConfiguration.coinPacks.map(\.coins), [500, 1_650, 3_600, 6_500])
        XCTAssertEqual(
            EconomyConfiguration.coinPacks.map(\.proposedUSPrice),
            [Decimal(string: "0.99")!, Decimal(string: "2.99")!, Decimal(string: "5.99")!, Decimal(string: "9.99")!]
        )
    }

    func testRunRewardBoundariesAndCap() {
        XCTAssertEqual(
            RunRewardCalculator.calculate(for: makeRun(score: 999)).totalCoins,
            10
        )
        XCTAssertEqual(
            RunRewardCalculator.calculate(for: makeRun(score: 1_000)).totalCoins,
            11
        )

        let accurate = RunStatisticsSnapshot(
            attempts: 10,
            completions: 7,
            incompletions: 3
        )
        let atCap = RunRewardCalculator.calculate(
            for: makeRun(score: 25_000, statistics: accurate)
        )
        let aboveCap = RunRewardCalculator.calculate(
            for: makeRun(score: 99_000, statistics: accurate)
        )

        XCTAssertEqual(atCap.completionCoins, 10)
        XCTAssertEqual(atCap.performanceCoins, 25)
        XCTAssertEqual(atCap.accuracyCoins, 5)
        XCTAssertEqual(atCap.totalCoins, 40)
        XCTAssertEqual(aboveCap.totalCoins, 40)
    }

    func testAccuracyBonusUsesExactThresholdAndMinimumAttempts() {
        let belowPercent = RunStatisticsSnapshot(
            attempts: 100,
            completions: 69,
            incompletions: 31
        )
        let tooFewAttempts = RunStatisticsSnapshot(
            attempts: 9,
            completions: 9
        )
        let threshold = RunStatisticsSnapshot(
            attempts: 10,
            completions: 7,
            incompletions: 3
        )

        XCTAssertEqual(
            RunRewardCalculator.calculate(
                for: makeRun(score: 0, statistics: belowPercent)
            ).accuracyCoins,
            0
        )
        XCTAssertEqual(
            RunRewardCalculator.calculate(
                for: makeRun(score: 0, statistics: tooFewAttempts)
            ).accuracyCoins,
            0
        )
        XCTAssertEqual(
            RunRewardCalculator.calculate(
                for: makeRun(score: 0, statistics: threshold)
            ).accuracyCoins,
            5
        )
    }

    func testIneligibleRunsEarnNothing() {
        let twoAttempts = RunStatisticsSnapshot(attempts: 2, completions: 2)
        XCTAssertEqual(
            RunRewardCalculator.calculate(
                for: makeRun(score: 25_000, statistics: twoAttempts)
            ),
            .ineligible
        )
        XCTAssertEqual(
            RunRewardCalculator.calculate(
                for: makeRun(score: 25_000, finishReason: .abandoned)
            ),
            .ineligible
        )
    }

    func testEightAchievementCatalogTotals600Points() {
        XCTAssertEqual(AchievementCatalog.launch.count, 8)
        XCTAssertEqual(Set(AchievementCatalog.launch.map(\.id)).count, 8)
        XCTAssertEqual(AchievementCatalog.launch.reduce(0) { $0 + $1.points }, 600)
    }

    func testEvaluatorCompletesAllEightAtExactRequirements() {
        let statistics = RunStatisticsSnapshot(
            attempts: 12,
            completions: 6,
            touchdowns: 4,
            incompletions: 2,
            longestTouchdownStreak: 4
        )
        let run = makeRun(
            score: 25_000,
            statistics: statistics,
            lanes: Set(LaneID.allCases),
            bonusTouchdowns: 1
        )
        var career = CareerStatistics()
        career.completions = 96
        career.touchdowns = 4
        career.bonusTouchdowns = 1
        let evaluatedAt = Date(timeIntervalSince1970: 2_000)

        let updates = AchievementEvaluator.evaluate(
            run: run,
            careerAfter: career,
            existing: [:],
            evaluatedAt: evaluatedAt
        )

        XCTAssertEqual(updates.count, 8)
        XCTAssertTrue(updates.allSatisfy { $0.current.percentComplete == 100 })
        XCTAssertTrue(updates.allSatisfy { $0.current.completedAt == evaluatedAt })
    }

    func testSingleRunAchievementThresholdsDoNotCompleteEarly() {
        let statistics = RunStatisticsSnapshot(
            attempts: 12,
            completions: 5,
            touchdowns: 4,
            incompletions: 3,
            longestTouchdownStreak: 3
        )
        let run = makeRun(
            score: 24_999,
            statistics: statistics,
            lanes: [.short, .medium, .deep]
        )
        var career = CareerStatistics()
        career.completions = 9

        let updates = AchievementEvaluator.evaluate(
            run: run,
            careerAfter: career,
            existing: [:],
            evaluatedAt: Date(timeIntervalSince1970: 3_000)
        )
        let progress = Dictionary(uniqueKeysWithValues: updates.map { ($0.current.id, $0.current) })

        XCTAssertNil(progress[LaunchAchievementID.fullRouteTree])
        XCTAssertNil(progress[LaunchAchievementID.dialedIn])
        XCTAssertNil(progress[LaunchAchievementID.hotHand])
        XCTAssertNil(progress[LaunchAchievementID.lightUpTheBoard])
    }

    func testOnlyCenturyReportsIncrementalProgress() {
        let run = makeRun(score: 24_999)
        var career = CareerStatistics()
        career.completions = 99

        let updates = AchievementEvaluator.evaluate(
            run: run,
            careerAfter: career,
            existing: [:],
            evaluatedAt: Date(timeIntervalSince1970: 4_000)
        )
        let progress = Dictionary(uniqueKeysWithValues: updates.map { ($0.current.id, $0.current) })

        XCTAssertEqual(
            progress[LaunchAchievementID.centuryOfConnections]?.percentComplete,
            99
        )
        for definition in AchievementCatalog.launch
            where definition.id != LaunchAchievementID.centuryOfConnections {
            let percent = progress[definition.id]?.percentComplete ?? 0
            XCTAssertTrue(percent == 0 || percent == 100)
        }
    }

    func testAchievementProgressNeverRegressesOrRecompletes() {
        let completed = Dictionary(
            uniqueKeysWithValues: AchievementCatalog.launch.map {
                ($0.id, AchievementProgress(id: $0.id, percentComplete: 100, completedAt: Date(timeIntervalSince1970: 10)))
            }
        )
        let weakRun = makeRun(score: 0)

        XCTAssertTrue(
            AchievementEvaluator.evaluate(
                run: weakRun,
                careerAfter: CareerStatistics(),
                existing: completed,
                evaluatedAt: Date(timeIntervalSince1970: 20)
            ).isEmpty
        )
    }

    func testCareerStatisticsIgnoresAbandonedRuns() {
        var career = CareerStatistics()
        career.apply(makeRun(score: 3_000, finishReason: .abandoned))
        XCTAssertEqual(career, CareerStatistics())

        career.apply(makeRun(score: 3_000))
        XCTAssertEqual(career.completedRuns, 1)
        XCTAssertEqual(career.rewardEligibleRuns, 1)
        XCTAssertEqual(career.highestScore, 3_000)
        XCTAssertEqual(career.totalScore, 3_000)
    }

    private func makeRun(
        score: Int,
        finishReason: RunFinishReason = .timerExpired,
        statistics: RunStatisticsSnapshot = RunStatisticsSnapshot(
            attempts: 3,
            completions: 2,
            incompletions: 1
        ),
        lanes: Set<LaneID> = [],
        bonusTouchdowns: Int = 0
    ) -> CompletedRun {
        let startedAt = Date(timeIntervalSince1970: 1_000)
        return CompletedRun(
            configuration: RunConfiguration(
                runID: RunID(),
                randomSeed: 7,
                offenseTeamID: LaunchTeamID.novaCityComets,
                offenseJerseyID: JerseyID("jersey.nova_city_comets.primary"),
                defenseTeamID: LaunchTeamID.highMesaHelions,
                defenseJerseyID: JerseyID("jersey.high_mesa_helions.primary"),
                footballID: LaunchFootballID.standard,
                economyVersion: EconomyConfiguration.currentVersion,
                startedAt: startedAt
            ),
            endedAt: startedAt.addingTimeInterval(60),
            elapsedGameplayMilliseconds: 60_000,
            finishReason: finishReason,
            score: score,
            statistics: statistics,
            completedLaneIDs: lanes,
            bonusTouchdownCount: bonusTouchdowns
        )
    }
}

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
        XCTAssertEqual(EconomyConfiguration.coinPacks.map(\.coins), [750, 2_500, 6_000, 11_000])
        XCTAssertEqual(
            EconomyConfiguration.coinPacks.map(\.proposedUSPrice),
            [Decimal(string: "0.99")!, Decimal(string: "2.99")!, Decimal(string: "5.99")!, Decimal(string: "9.99")!]
        )
    }

    func testCoinPackValueStrictlyImprovesAtEveryTier() {
        let packs = EconomyConfiguration.coinPacks

        for (lower, higher) in zip(packs, packs.dropFirst()) {
            let higherValue = Decimal(higher.coins) * lower.proposedUSPrice
            let lowerValue = Decimal(lower.coins) * higher.proposedUSPrice
            XCTAssertGreaterThan(
                higherValue,
                lowerValue,
                "\(higher.displayName) must provide more coins per dollar than \(lower.displayName)"
            )
        }
    }

    func testNoLowerTierCombinationBeatsVaultAtOrBelowItsPrice() {
        let lowerPacks = Array(EconomyConfiguration.coinPacks.dropLast())
        let vault = EconomyConfiguration.coinPacks.last!

        for pocketCount in 0 ... 10 {
            for teamCount in 0 ... 3 {
                for bundleCount in 0 ... 1 {
                    let counts = [pocketCount, teamCount, bundleCount]
                    let price = zip(lowerPacks, counts).reduce(Decimal.zero) {
                        $0 + ($1.0.proposedUSPrice * Decimal($1.1))
                    }
                    let coins = zip(lowerPacks, counts).reduce(Int64.zero) {
                        $0 + ($1.0.coins * Int64($1.1))
                    }
                    if price <= vault.proposedUSPrice {
                        XCTAssertLessThan(coins, vault.coins)
                    }
                }
            }
        }
    }

    func testCompletedRunRewardBreakdownUsesScoreFloorAndCap() throws {
        let expectations: [(score: Int, performanceCoins: Int64)] = [
            (0, 0),
            (999, 0),
            (1_000, 1),
            (1_999, 1),
            (2_000, 2),
            (24_999, 24),
            (25_000, 25),
            (25_001, 25),
            (1_000_000, 25),
        ]

        for expectation in expectations {
            let breakdown = try makeRun(score: expectation.score).rewardBreakdown()

            XCTAssertTrue(breakdown.isEligible, "score: \(expectation.score)")
            XCTAssertEqual(breakdown.completionCoins, 10, "score: \(expectation.score)")
            XCTAssertEqual(
                breakdown.performanceCoins,
                expectation.performanceCoins,
                "score: \(expectation.score)"
            )
            XCTAssertEqual(breakdown.accuracyCoins, 0, "score: \(expectation.score)")
            XCTAssertEqual(
                breakdown.totalCoins,
                10 + expectation.performanceCoins,
                "score: \(expectation.score)"
            )
        }
    }

    func testCompletedRunRewardBreakdownUsesExactAccuracyThresholds() throws {
        let expectations: [(statistics: RunStatisticsSnapshot, accuracyCoins: Int64)] = [
            (
                RunStatisticsSnapshot(attempts: 9, completions: 9),
                0
            ),
            (
                RunStatisticsSnapshot(attempts: 10, completions: 6, incompletions: 4),
                0
            ),
            (
                RunStatisticsSnapshot(attempts: 10, completions: 7, incompletions: 3),
                5
            ),
            (
                RunStatisticsSnapshot(attempts: 99, completions: 69, incompletions: 30),
                0
            ),
            (
                RunStatisticsSnapshot(attempts: 100, completions: 70, incompletions: 30),
                5
            ),
            (
                RunStatisticsSnapshot(
                    attempts: 10,
                    completions: 5,
                    touchdowns: 2,
                    incompletions: 3
                ),
                5
            ),
            (
                RunStatisticsSnapshot(
                    attempts: Int.max,
                    completions: Int.max,
                    touchdowns: Int.max
                ),
                0
            ),
        ]

        for expectation in expectations {
            let breakdown = try makeRun(
                score: 0,
                statistics: expectation.statistics
            ).rewardBreakdown()

            XCTAssertEqual(
                breakdown.accuracyCoins,
                expectation.accuracyCoins,
                "statistics: \(expectation.statistics)"
            )
        }
    }

    func testCompletedRunRewardBreakdownEligibilityAndIneligibleRuns() throws {
        let eligible = try makeRun(score: 0).rewardBreakdown()
        XCTAssertTrue(makeRun(score: 0).isNaturallyCompleted)
        XCTAssertTrue(makeRun(score: 0).isRewardEligible)
        XCTAssertEqual(
            eligible,
            RunRewardBreakdown(
                isEligible: true,
                completionCoins: 10,
                performanceCoins: 0,
                accuracyCoins: 0
            )
        )

        let ineligibleRuns = [
            makeRun(
                score: 25_000,
                statistics: RunStatisticsSnapshot(
                    attempts: 2,
                    completions: 2
                )
            ),
            makeRun(score: 25_000, finishReason: .abandoned),
            makeRun(score: 25_000, finishReason: .debugPreview),
            makeRun(score: 25_000, elapsedGameplayMilliseconds: 59_999),
            makeRun(score: 25_000, elapsedGameplayMilliseconds: 60_001),
        ]

        for run in ineligibleRuns {
            XCTAssertFalse(run.isRewardEligible)
            XCTAssertEqual(try run.rewardBreakdown(), .ineligible)
        }
    }

    func testCompletedRunRewardBreakdownRejectsUnsupportedEconomyVersions() {
        XCTAssertEqual(RunRewardCalculator.supportedEconomyVersions, [1])

        for economyVersion in [0, 2] {
            let run = makeRun(score: 0, economyVersion: economyVersion)

            XCTAssertFalse(run.isRewardEligible)
            XCTAssertThrowsError(try run.rewardBreakdown()) { error in
                XCTAssertEqual(
                    error as? RunRewardBreakdownError,
                    .unsupportedEconomyVersion(economyVersion)
                )
            }
        }
    }

    func testCompletedRunRewardBreakdownMatchesSettlementForEverySupportedVersion() throws {
        let scenarios: [(
            score: Int,
            statistics: RunStatisticsSnapshot,
            finishReason: RunFinishReason,
            elapsed: Int
        )] = [
            (0, RunStatisticsSnapshot(attempts: 3, completions: 2, incompletions: 1), .timerExpired, 60_000),
            (999, RunStatisticsSnapshot(attempts: 3, completions: 2, incompletions: 1), .timerExpired, 60_000),
            (1_000, RunStatisticsSnapshot(attempts: 3, completions: 2, incompletions: 1), .timerExpired, 60_000),
            (24_999, RunStatisticsSnapshot(attempts: 10, completions: 7, incompletions: 3), .timerExpired, 60_000),
            (25_000, RunStatisticsSnapshot(attempts: 10, completions: 7, incompletions: 3), .timerExpired, 60_000),
            (99_000, RunStatisticsSnapshot(attempts: 10, completions: 6, incompletions: 4), .timerExpired, 60_000),
            (25_000, RunStatisticsSnapshot(attempts: 2, completions: 2), .timerExpired, 60_000),
            (25_000, RunStatisticsSnapshot(attempts: 3, completions: 2, incompletions: 1), .abandoned, 30_000),
            (25_000, RunStatisticsSnapshot(attempts: 3, completions: 2, incompletions: 1), .debugPreview, 60_000),
            (25_000, RunStatisticsSnapshot(attempts: 3, completions: 2, incompletions: 1), .timerExpired, 59_999),
            (25_000, RunStatisticsSnapshot(attempts: 3, completions: 2, incompletions: 1), .timerExpired, 60_001),
        ]

        for economyVersion in RunRewardCalculator.supportedEconomyVersions {
            for scenario in scenarios {
                let run = makeRun(
                    score: scenario.score,
                    finishReason: scenario.finishReason,
                    statistics: scenario.statistics,
                    economyVersion: economyVersion,
                    elapsedGameplayMilliseconds: scenario.elapsed
                )
                let breakdown = try run.rewardBreakdown()

                XCTAssertEqual(
                    breakdown.totalCoins,
                    try CompletedRunValidator.rewardCoins(for: run),
                    "economy v\(economyVersion), score \(scenario.score), "
                        + "finish \(scenario.finishReason), elapsed \(scenario.elapsed)"
                )
            }
        }
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
        bonusTouchdowns: Int = 0,
        economyVersion: Int = EconomyConfiguration.currentVersion,
        elapsedGameplayMilliseconds: Int = 60_000
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
                economyVersion: economyVersion,
                startedAt: startedAt
            ),
            endedAt: startedAt.addingTimeInterval(60),
            elapsedGameplayMilliseconds: elapsedGameplayMilliseconds,
            finishReason: finishReason,
            score: score,
            statistics: statistics,
            completedLaneIDs: lanes,
            bonusTouchdownCount: bonusTouchdowns
        )
    }
}

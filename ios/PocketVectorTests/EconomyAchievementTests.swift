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

    func testFourteenAchievementCatalogTotals1000Points() {
        XCTAssertEqual(AchievementCatalog.launch.count, 14)
        XCTAssertEqual(Set(AchievementCatalog.launch.map(\.id)).count, 14)
        XCTAssertEqual(AchievementCatalog.launch.reduce(0) { $0 + $1.points }, 1_000)

        let definitions = Dictionary(
            uniqueKeysWithValues: AchievementCatalog.launch.map { ($0.id, $0) }
        )
        XCTAssertEqual(
            definitions[LaunchAchievementID.lightUpTheBoard],
            AchievementDefinition(
                id: LaunchAchievementID.lightUpTheBoard,
                displayName: "Light Up the Board",
                detail: "Reach 65,000 points during one run.",
                points: 100,
                rule: .singleRunScore(65_000)
            )
        )
        XCTAssertEqual(
            definitions[LaunchAchievementID.dialedIn],
            AchievementDefinition(
                id: LaunchAchievementID.dialedIn,
                displayName: "Dialed In",
                detail: "Finish with at least 80% accuracy over at least 25 pass attempts.",
                points: 75,
                rule: .singleRunAccuracy(percent: 80, minimumAttempts: 25)
            )
        )
        XCTAssertEqual(
            definitions[LaunchAchievementID.millenniaOfConnections],
            AchievementDefinition(
                id: AchievementID("achievement.millenia_of_connections.v1"),
                displayName: "Millennia of Connections",
                detail: "Complete 1,000 career passes, including touchdowns.",
                points: 100,
                rule: .incrementalCareerSuccessfulPasses(1_000)
            )
        )
        XCTAssertNil(
            definitions[AchievementID("achievement.century_of_connections.v1")]
        )
        XCTAssertEqual(
            [
                LaunchAchievementID.perfectPocket.rawValue,
                LaunchAchievementID.franchisePlayer.rawValue,
                LaunchAchievementID.overcharged.rawValue,
                LaunchAchievementID.deepThreat.rawValue,
                LaunchAchievementID.untouchable.rawValue,
                LaunchAchievementID.maximumOverdrive.rawValue,
            ],
            [
                "achievement.perfect_pocket.v1",
                "achievement.franchise_player.v1",
                "achievement.overcharged.v1",
                "achievement.deep_threat.v1",
                "achievement.untouchable.v1",
                "achievement.maximum_overdrive.v1",
            ]
        )

        let additions: [AchievementID: AchievementDefinition] = [
            LaunchAchievementID.perfectPocket: AchievementDefinition(
                id: LaunchAchievementID.perfectPocket,
                displayName: "Perfect Pocket",
                detail: "Finish with 100% accuracy over at least 20 pass attempts.",
                points: 75,
                rule: .singleRunAccuracy(percent: 100, minimumAttempts: 20)
            ),
            LaunchAchievementID.franchisePlayer: AchievementDefinition(
                id: LaunchAchievementID.franchisePlayer,
                displayName: "Franchise Player",
                detail: "Complete 50 natural runs.",
                points: 50,
                rule: .incrementalCareerCompletedRuns(50)
            ),
            LaunchAchievementID.overcharged: AchievementDefinition(
                id: LaunchAchievementID.overcharged,
                displayName: "Overcharged",
                detail: "Score three TD Bonus touchdowns during one run.",
                points: 50,
                rule: .singleRunBonusTouchdowns(3)
            ),
            LaunchAchievementID.deepThreat: AchievementDefinition(
                id: LaunchAchievementID.deepThreat,
                displayName: "Deep Threat",
                detail: "Complete five passes in the deep lane during one run.",
                points: 50,
                rule: .singleRunDeepCompletions(5)
            ),
            LaunchAchievementID.untouchable: AchievementDefinition(
                id: LaunchAchievementID.untouchable,
                displayName: "Untouchable",
                detail: "Reach 100,000 points during one run.",
                points: 100,
                rule: .singleRunScore(100_000)
            ),
            LaunchAchievementID.maximumOverdrive: AchievementDefinition(
                id: LaunchAchievementID.maximumOverdrive,
                displayName: "Maximum Overdrive",
                detail: "Score a touchdown with TD Bonus active and the capped 3× multiplier.",
                points: 75,
                rule: .singleRunMaximumOverdriveTouchdowns(1)
            ),
        ]
        for (achievementID, expected) in additions {
            XCTAssertEqual(definitions[achievementID], expected)
        }
    }

    func testEvaluatorCompletesAllFourteenAtExactRequirements() {
        let statistics = RunStatisticsSnapshot(
            attempts: 25,
            completions: 19,
            touchdowns: 6,
            longestTouchdownStreak: 6
        )
        let run = makeRun(
            score: 100_000,
            statistics: statistics,
            lanes: Set(LaneID.allCases),
            bonusTouchdowns: 3,
            deepCompletions: 5,
            maximumOverdriveTouchdowns: 1
        )
        var career = CareerStatistics()
        career.completedRuns = 50
        career.completions = 994
        career.touchdowns = 6
        career.bonusTouchdowns = 3
        let evaluatedAt = Date(timeIntervalSince1970: 2_000)

        let updates = AchievementEvaluator.evaluate(
            run: run,
            careerAfter: career,
            existing: [:],
            evaluatedAt: evaluatedAt
        )

        XCTAssertEqual(updates.count, 14)
        XCTAssertTrue(updates.allSatisfy { $0.current.percentComplete == 100 })
        XCTAssertTrue(updates.allSatisfy { $0.current.completedAt == evaluatedAt })
    }

    func testSingleRunAchievementThresholdsDoNotCompleteEarly() {
        let statistics = RunStatisticsSnapshot(
            attempts: 24,
            completions: 16,
            touchdowns: 4,
            incompletions: 4,
            longestTouchdownStreak: 3
        )
        let run = makeRun(
            score: 64_999,
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

    func testLightUpTheBoardRequiresExactly65000Points() {
        XCTAssertNil(
            evaluatedProgress(run: makeRun(score: 64_999))[
                LaunchAchievementID.lightUpTheBoard
            ]
        )
        XCTAssertEqual(
            evaluatedProgress(run: makeRun(score: 65_000))[
                LaunchAchievementID.lightUpTheBoard
            ]?.percentComplete,
            100
        )
    }

    func testDialedInRequires25AttemptsAndAtLeast80PercentAccuracy() {
        let twentyFourPerfect = RunStatisticsSnapshot(
            attempts: 24,
            completions: 24
        )
        XCTAssertNil(
            evaluatedProgress(
                run: makeRun(score: 0, statistics: twentyFourPerfect)
            )[LaunchAchievementID.dialedIn]
        )

        let exactlyEightyPercent = RunStatisticsSnapshot(
            attempts: 25,
            completions: 20,
            incompletions: 5
        )
        XCTAssertEqual(
            evaluatedProgress(
                run: makeRun(score: 0, statistics: exactlyEightyPercent)
            )[LaunchAchievementID.dialedIn]?.percentComplete,
            100
        )

        let belowEightyPercent = RunStatisticsSnapshot(
            attempts: 25,
            completions: 19,
            incompletions: 6
        )
        XCTAssertNil(
            evaluatedProgress(
                run: makeRun(score: 0, statistics: belowEightyPercent)
            )[LaunchAchievementID.dialedIn]
        )
    }

    func testPerfectPocketRequires20AttemptsAndExactly100PercentAccuracy() {
        XCTAssertNil(
            evaluatedProgress(
                run: makeRun(
                    score: 0,
                    statistics: RunStatisticsSnapshot(
                        attempts: 19,
                        completions: 19
                    )
                )
            )[LaunchAchievementID.perfectPocket]
        )
        XCTAssertNil(
            evaluatedProgress(
                run: makeRun(
                    score: 0,
                    statistics: RunStatisticsSnapshot(
                        attempts: 20,
                        completions: 19,
                        incompletions: 1
                    )
                )
            )[LaunchAchievementID.perfectPocket]
        )
        XCTAssertEqual(
            evaluatedProgress(
                run: makeRun(
                    score: 0,
                    statistics: RunStatisticsSnapshot(
                        attempts: 20,
                        completions: 20
                    )
                )
            )[LaunchAchievementID.perfectPocket]?.percentComplete,
            100
        )
    }

    func testFranchisePlayerProgressesAt49AndCompletesAt50NaturalRuns() {
        let run = makeRun(score: 0)
        var career = CareerStatistics()
        career.completedRuns = 49

        XCTAssertEqual(
            evaluatedProgress(
                run: run,
                career: career
            )[LaunchAchievementID.franchisePlayer]?.percentComplete,
            98
        )

        career.completedRuns = 50
        XCTAssertEqual(
            evaluatedProgress(
                run: run,
                career: career
            )[LaunchAchievementID.franchisePlayer]?.percentComplete,
            100
        )

        XCTAssertTrue(
            AchievementEvaluator.evaluate(
                run: makeRun(score: 0, finishReason: .abandoned),
                careerAfter: career,
                existing: [:],
                evaluatedAt: Date(timeIntervalSince1970: 9_000)
            ).isEmpty
        )
    }

    func testOverchargedDeepThreatUntouchableAndMaximumOverdriveBoundaries() {
        XCTAssertNil(
            evaluatedProgress(
                run: makeRun(score: 99_999, bonusTouchdowns: 2)
            )[LaunchAchievementID.overcharged]
        )
        XCTAssertEqual(
            evaluatedProgress(
                run: makeRun(score: 99_999, bonusTouchdowns: 3)
            )[LaunchAchievementID.overcharged]?.percentComplete,
            100
        )

        XCTAssertNil(
            evaluatedProgress(
                run: makeRun(
                    score: 99_999,
                    statistics: RunStatisticsSnapshot(
                        attempts: 4,
                        completions: 4
                    ),
                    lanes: [.deep],
                    deepCompletions: 4
                )
            )[LaunchAchievementID.deepThreat]
        )
        XCTAssertEqual(
            evaluatedProgress(
                run: makeRun(
                    score: 99_999,
                    statistics: RunStatisticsSnapshot(
                        attempts: 5,
                        completions: 5
                    ),
                    lanes: [.deep],
                    deepCompletions: 5
                )
            )[LaunchAchievementID.deepThreat]?.percentComplete,
            100
        )
        XCTAssertNil(
            evaluatedProgress(
                run: makeRun(score: 99_999, lanes: [.deep])
            )[LaunchAchievementID.deepThreat]
        )

        XCTAssertNil(
            evaluatedProgress(run: makeRun(score: 99_999))[
                LaunchAchievementID.untouchable
            ]
        )
        XCTAssertEqual(
            evaluatedProgress(run: makeRun(score: 100_000))[
                LaunchAchievementID.untouchable
            ]?.percentComplete,
            100
        )

        XCTAssertNil(
            evaluatedProgress(
                run: makeRun(
                    score: 99_999,
                    statistics: RunStatisticsSnapshot(
                        attempts: 3,
                        touchdowns: 3,
                        longestTouchdownStreak: 3
                    ),
                    lanes: [.touchdown],
                    bonusTouchdowns: 3,
                    maximumOverdriveTouchdowns: 0
                )
            )[LaunchAchievementID.maximumOverdrive]
        )
        XCTAssertEqual(
            evaluatedProgress(
                run: makeRun(
                    score: 99_999,
                    statistics: RunStatisticsSnapshot(
                        attempts: 1,
                        touchdowns: 1,
                        longestTouchdownStreak: 1
                    ),
                    lanes: [.touchdown],
                    bonusTouchdowns: 1,
                    maximumOverdriveTouchdowns: 1
                )
            )[LaunchAchievementID.maximumOverdrive]?.percentComplete,
            100
        )
    }

    func testCompletedRunDefaultsMissingVersion11FactsWithoutInference() throws {
        let source = makeRun(
            score: 100_000,
            statistics: RunStatisticsSnapshot(
                attempts: 20,
                completions: 14,
                touchdowns: 6,
                longestTouchdownStreak: 6
            ),
            lanes: [.deep, .touchdown],
            bonusTouchdowns: 3,
            deepCompletions: 5,
            maximumOverdriveTouchdowns: 1
        )
        let encoded = try JSONEncoder().encode(source)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "deepCompletionCount")
        object.removeValue(forKey: "maximumOverdriveTouchdownCount")
        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(CompletedRun.self, from: legacyData)

        XCTAssertEqual(decoded.deepCompletionCount, 0)
        XCTAssertEqual(decoded.maximumOverdriveTouchdownCount, 0)
        XCTAssertEqual(decoded.completedLaneIDs, [.deep, .touchdown])
        XCTAssertEqual(decoded.bonusTouchdownCount, 3)
        XCTAssertTrue(decoded.achievementFactsAreStructurallyValid)
        XCTAssertNil(
            evaluatedProgress(run: decoded)[LaunchAchievementID.deepThreat]
        )
        XCTAssertNil(
            evaluatedProgress(run: decoded)[LaunchAchievementID.maximumOverdrive]
        )
    }

    func testCompletedRunAchievementFactStructuralBoundaries() {
        XCTAssertTrue(
            makeRun(
                score: 0,
                statistics: RunStatisticsSnapshot(
                    attempts: 2,
                    completions: 1,
                    touchdowns: 1
                ),
                lanes: [.deep, .touchdown],
                bonusTouchdowns: 1,
                deepCompletions: 1,
                maximumOverdriveTouchdowns: 1
            ).achievementFactsAreStructurallyValid
        )
        XCTAssertFalse(
            makeRun(
                score: 0,
                statistics: RunStatisticsSnapshot(attempts: 2, completions: 2),
                lanes: [.short],
                deepCompletions: 1
            ).achievementFactsAreStructurallyValid
        )
        XCTAssertFalse(
            makeRun(
                score: 0,
                statistics: RunStatisticsSnapshot(
                    attempts: 1,
                    touchdowns: 1
                ),
                lanes: [.deep],
                bonusTouchdowns: 1,
                maximumOverdriveTouchdowns: 1
            ).achievementFactsAreStructurallyValid
        )

        let invalidRun = makeRun(
            score: 100_000,
            statistics: RunStatisticsSnapshot(attempts: 2, completions: 2),
            lanes: [.deep],
            deepCompletions: 5
        )
        XCTAssertTrue(
            AchievementEvaluator.evaluate(
                run: invalidRun,
                careerAfter: CareerStatistics(),
                existing: [:],
                evaluatedAt: Date(timeIntervalSince1970: 9_500)
            ).isEmpty
        )
        XCTAssertFalse(
            makeRun(
                score: 0,
                statistics: RunStatisticsSnapshot(attempts: 2, completions: 2),
                lanes: [.deep],
                deepCompletions: 3
            ).achievementFactsAreStructurallyValid
        )
        XCTAssertFalse(
            makeRun(
                score: 0,
                statistics: RunStatisticsSnapshot(attempts: 1, touchdowns: 1),
                lanes: [.touchdown],
                bonusTouchdowns: 0,
                maximumOverdriveTouchdowns: 1
            ).achievementFactsAreStructurallyValid
        )
    }

    func testMillenniaOfConnectionsRequires1000CareerSuccessfulPasses() {
        let run = makeRun(score: 0)
        var career = CareerStatistics()
        career.completions = 999

        let belowTarget = AchievementEvaluator.evaluate(
            run: run,
            careerAfter: career,
            existing: [:],
            evaluatedAt: Date(timeIntervalSince1970: 4_000)
        )
        let belowProgress = Dictionary(
            uniqueKeysWithValues: belowTarget.map { ($0.current.id, $0.current) }
        )

        XCTAssertEqual(
            belowProgress[LaunchAchievementID.millenniaOfConnections]?
                .percentComplete,
            99
        )
        XCTAssertNil(
            belowProgress[LaunchAchievementID.millenniaOfConnections]?
                .completedAt
        )

        career.completions = 999
        career.touchdowns = 1
        let atTarget = AchievementEvaluator.evaluate(
            run: run,
            careerAfter: career,
            existing: [:],
            evaluatedAt: Date(timeIntervalSince1970: 5_000)
        )
        let atTargetProgress = Dictionary(
            uniqueKeysWithValues: atTarget.map { ($0.current.id, $0.current) }
        )
        XCTAssertEqual(
            atTargetProgress[LaunchAchievementID.millenniaOfConnections]?
                .percentComplete,
            100
        )
        XCTAssertEqual(
            atTargetProgress[LaunchAchievementID.millenniaOfConnections]?
                .completedAt,
            Date(timeIntervalSince1970: 5_000)
        )

        for definition in AchievementCatalog.launch
            where definition.id != LaunchAchievementID.millenniaOfConnections {
            let percent = belowProgress[definition.id]?.percentComplete ?? 0
            XCTAssertTrue(percent == 0 || percent == 100)
        }
    }

    func testCatalogTransitionContractMapsRetiredIDAndRecomputesOnlyTargets() {
        let retired = AchievementID("achievement.century_of_connections.v1")
        XCTAssertEqual(
            AchievementCatalogTransitionV1ToV2.sourceCatalogSemanticIdentifier,
            "pocket-vector-launch-achievement-catalog-semantics-v1"
        )
        XCTAssertEqual(
            AchievementCatalogTransitionV1ToV2.targetCatalogSemanticIdentifier,
            "pocket-vector-launch-achievement-catalog-semantics-v2"
        )
        XCTAssertEqual(
            AchievementCatalogTransitionV1ToV2.identifierReplacements,
            [retired: LaunchAchievementID.millenniaOfConnections]
        )
        XCTAssertEqual(
            AchievementCatalogTransitionV1ToV2.currentStateForbiddenIDs,
            [retired]
        )
        XCTAssertEqual(
            AchievementCatalogTransitionV1ToV2.pendingQueueScrubIDs,
            [
                retired,
                LaunchAchievementID.dialedIn,
                LaunchAchievementID.lightUpTheBoard,
                LaunchAchievementID.millenniaOfConnections,
            ]
        )
        XCTAssertEqual(
            AchievementCatalogTransitionV1ToV2.pendingEvidenceSourceIDs(
                for: LaunchAchievementID.dialedIn
            ),
            [LaunchAchievementID.dialedIn]
        )
        XCTAssertEqual(
            AchievementCatalogTransitionV1ToV2.pendingEvidenceSourceIDs(
                for: LaunchAchievementID.lightUpTheBoard
            ),
            [LaunchAchievementID.lightUpTheBoard]
        )
        XCTAssertEqual(
            AchievementCatalogTransitionV1ToV2.pendingEvidenceSourceIDs(
                for: LaunchAchievementID.millenniaOfConnections
            ),
            [retired, LaunchAchievementID.millenniaOfConnections]
        )

        XCTAssertEqual(
            AchievementCatalogTransitionV1ToV2.recomputedPercent(
                for: LaunchAchievementID.millenniaOfConnections,
                careerSuccessfulPasses: 999,
                completedRuns: []
            ),
            99
        )
        XCTAssertEqual(
            AchievementCatalogTransitionV1ToV2.recomputedPercent(
                for: LaunchAchievementID.millenniaOfConnections,
                careerSuccessfulPasses: 1_000,
                completedRuns: []
            ),
            100
        )
        XCTAssertNil(
            AchievementCatalogTransitionV1ToV2.recomputedPercent(
                for: LaunchAchievementID.firstRead,
                careerSuccessfulPasses: 1_000,
                completedRuns: []
            )
        )

        XCTAssertNil(
            AchievementCatalogTransitionV1ToV2.reconciledPendingPercent(
                for: LaunchAchievementID.millenniaOfConnections,
                pendingEvidencePercentsInSameProvenanceBucket: [:],
                recomputedEarnedPercent: 100
            )
        )
        XCTAssertNil(
            AchievementCatalogTransitionV1ToV2.reconciledPendingPercent(
                for: LaunchAchievementID.millenniaOfConnections,
                pendingEvidencePercentsInSameProvenanceBucket: [retired: 0],
                recomputedEarnedPercent: 100
            )
        )
        XCTAssertEqual(
            AchievementCatalogTransitionV1ToV2.reconciledPendingPercent(
                for: LaunchAchievementID.millenniaOfConnections,
                pendingEvidencePercentsInSameProvenanceBucket: [retired: 100],
                recomputedEarnedPercent: 37
            ),
            37
        )
        XCTAssertEqual(
            AchievementCatalogTransitionV1ToV2.reconciledPendingPercent(
                for: LaunchAchievementID.millenniaOfConnections,
                pendingEvidencePercentsInSameProvenanceBucket: [
                    retired: 100,
                    LaunchAchievementID.millenniaOfConnections: 25,
                ],
                recomputedEarnedPercent: 52
            ),
            52
        )
        XCTAssertNil(
            AchievementCatalogTransitionV1ToV2.reconciledPendingPercent(
                for: LaunchAchievementID.dialedIn,
                pendingEvidencePercentsInSameProvenanceBucket: [
                    LaunchAchievementID.lightUpTheBoard: 100,
                ],
                recomputedEarnedPercent: 100
            )
        )
        XCTAssertNil(
            AchievementCatalogTransitionV1ToV2.reconciledPendingPercent(
                for: LaunchAchievementID.dialedIn,
                pendingEvidencePercentsInSameProvenanceBucket: [
                    LaunchAchievementID.dialedIn: 100,
                ],
                recomputedEarnedPercent: 0
            )
        )
    }

    func testCatalogTransitionReconcilesStricterRunsAndCompletionDates() {
        let abandonedQualifying = CompletedRunRecord(
            run: makeRun(
                score: 80_000,
                finishReason: .abandoned,
                statistics: RunStatisticsSnapshot(
                    attempts: 25,
                    completions: 25
                )
            ),
            recordedAt: Date(timeIntervalSince1970: 1_200),
            rewardCoins: 0
        )
        let obsoleteOnly = CompletedRunRecord(
            run: makeRun(
                score: 64_999,
                statistics: RunStatisticsSnapshot(
                    attempts: 24,
                    completions: 24
                )
            ),
            recordedAt: Date(timeIntervalSince1970: 1_300),
            rewardCoins: 40
        )
        let qualifying = CompletedRunRecord(
            run: makeRun(
                score: 65_000,
                statistics: RunStatisticsSnapshot(
                    attempts: 25,
                    completions: 20,
                    incompletions: 5
                )
            ),
            recordedAt: Date(timeIntervalSince1970: 1_400),
            rewardCoins: 40
        )
        let records = [qualifying, obsoleteOnly, abandonedQualifying]

        XCTAssertEqual(
            AchievementCatalogTransitionV1ToV2.recomputedPercent(
                for: LaunchAchievementID.dialedIn,
                careerSuccessfulPasses: 0,
                completedRuns: [obsoleteOnly, abandonedQualifying]
            ),
            0
        )
        XCTAssertEqual(
            AchievementCatalogTransitionV1ToV2.recomputedPercent(
                for: LaunchAchievementID.lightUpTheBoard,
                careerSuccessfulPasses: 0,
                completedRuns: [obsoleteOnly, abandonedQualifying]
            ),
            0
        )
        XCTAssertEqual(
            AchievementCatalogTransitionV1ToV2.recomputedPercent(
                for: LaunchAchievementID.dialedIn,
                careerSuccessfulPasses: 0,
                completedRuns: records
            ),
            100
        )
        XCTAssertEqual(
            AchievementCatalogTransitionV1ToV2.recomputedPercent(
                for: LaunchAchievementID.lightUpTheBoard,
                careerSuccessfulPasses: 0,
                completedRuns: records
            ),
            100
        )
        XCTAssertEqual(
            AchievementCatalogTransitionV1ToV2.recomputedCompletedAt(
                for: LaunchAchievementID.dialedIn,
                completedRuns: records
            ),
            qualifying.recordedAt
        )
        XCTAssertEqual(
            AchievementCatalogTransitionV1ToV2.recomputedCompletedAt(
                for: LaunchAchievementID.lightUpTheBoard,
                completedRuns: records
            ),
            qualifying.recordedAt
        )
    }

    func testCatalogTransitionDatesMillenniaAtFirst1000PassCrossing() {
        let beforeCrossing = [300, 300, 300, 99].enumerated().map {
            index, successfulPasses in
            CompletedRunRecord(
                run: makeRun(
                    score: 0,
                    statistics: RunStatisticsSnapshot(
                        attempts: successfulPasses,
                        completions: successfulPasses
                    )
                ),
                recordedAt: Date(
                    timeIntervalSince1970: Double(1_600 + index * 100)
                ),
                rewardCoins: 15
            )
        }
        let crossing = CompletedRunRecord(
            run: makeRun(
                score: 0,
                statistics: RunStatisticsSnapshot(attempts: 1, touchdowns: 1)
            ),
            recordedAt: Date(timeIntervalSince1970: 2_000),
            rewardCoins: 0
        )

        XCTAssertNil(
            AchievementCatalogTransitionV1ToV2.recomputedCompletedAt(
                for: LaunchAchievementID.millenniaOfConnections,
                completedRuns: beforeCrossing
            )
        )
        XCTAssertEqual(
            AchievementCatalogTransitionV1ToV2.recomputedCompletedAt(
                for: LaunchAchievementID.millenniaOfConnections,
                completedRuns: [crossing] + Array(beforeCrossing.reversed())
            ),
            crossing.recordedAt
        )
    }

    func testCatalogV2ToV3TransitionDeclaresExactAdditiveContract() {
        XCTAssertEqual(
            AchievementCatalogTransitionV2ToV3.sourceCatalogSemanticIdentifier,
            "pocket-vector-launch-achievement-catalog-semantics-v2"
        )
        XCTAssertEqual(
            AchievementCatalogTransitionV2ToV3.targetCatalogSemanticIdentifier,
            "pocket-vector-launch-achievement-catalog-semantics-v3"
        )
        XCTAssertEqual(
            AchievementCatalogTransitionV2ToV3.addedAchievementIDs,
            [
                LaunchAchievementID.perfectPocket,
                LaunchAchievementID.franchisePlayer,
                LaunchAchievementID.overcharged,
                LaunchAchievementID.deepThreat,
                LaunchAchievementID.untouchable,
                LaunchAchievementID.maximumOverdrive,
            ]
        )
        XCTAssertEqual(
            AchievementCatalogTransitionV2ToV3
                .historicallyReplayableAchievementIDs,
            [
                LaunchAchievementID.perfectPocket,
                LaunchAchievementID.franchisePlayer,
                LaunchAchievementID.overcharged,
                LaunchAchievementID.untouchable,
            ]
        )
        XCTAssertEqual(
            AchievementCatalogTransitionV2ToV3.nonretroactiveAchievementIDs,
            [
                LaunchAchievementID.deepThreat,
                LaunchAchievementID.maximumOverdrive,
            ]
        )
        XCTAssertEqual(
            AchievementCatalogTransitionV2ToV3.legacyDeepCompletionCount,
            0
        )
        XCTAssertEqual(
            AchievementCatalogTransitionV2ToV3
                .legacyMaximumOverdriveTouchdownCount,
            0
        )
    }

    func testCatalogV2ToV3ReplaysOnlyProvableHistoricalAchievements() {
        let firstDate = Date(timeIntervalSince1970: 10_000)
        var records = (0 ..< 50).map { index in
            CompletedRunRecord(
                run: makeRun(score: 0),
                recordedAt: firstDate.addingTimeInterval(Double(index)),
                rewardCoins: 10
            )
        }
        let qualifying = CompletedRunRecord(
            run: makeRun(
                score: 100_000,
                statistics: RunStatisticsSnapshot(
                    attempts: 20,
                    completions: 14,
                    touchdowns: 6,
                    longestTouchdownStreak: 6
                ),
                lanes: [.deep, .touchdown],
                bonusTouchdowns: 3
            ),
            recordedAt: firstDate.addingTimeInterval(-1),
            rewardCoins: 40
        )
        records.append(qualifying)

        XCTAssertEqual(
            AchievementCatalogTransitionV2ToV3.recomputedPercent(
                for: LaunchAchievementID.perfectPocket,
                completedRuns: records
            ),
            100
        )
        XCTAssertEqual(
            AchievementCatalogTransitionV2ToV3.recomputedPercent(
                for: LaunchAchievementID.franchisePlayer,
                completedRuns: Array(records.prefix(49))
            ),
            98
        )
        XCTAssertEqual(
            AchievementCatalogTransitionV2ToV3.recomputedPercent(
                for: LaunchAchievementID.franchisePlayer,
                completedRuns: records
            ),
            100
        )
        XCTAssertEqual(
            AchievementCatalogTransitionV2ToV3.recomputedPercent(
                for: LaunchAchievementID.overcharged,
                completedRuns: records
            ),
            100
        )
        XCTAssertEqual(
            AchievementCatalogTransitionV2ToV3.recomputedPercent(
                for: LaunchAchievementID.untouchable,
                completedRuns: records
            ),
            100
        )
        XCTAssertEqual(
            AchievementCatalogTransitionV2ToV3.recomputedPercent(
                for: LaunchAchievementID.deepThreat,
                completedRuns: records
            ),
            0
        )
        XCTAssertEqual(
            AchievementCatalogTransitionV2ToV3.recomputedPercent(
                for: LaunchAchievementID.maximumOverdrive,
                completedRuns: records
            ),
            0
        )
        XCTAssertNil(
            AchievementCatalogTransitionV2ToV3.recomputedCompletedAt(
                for: LaunchAchievementID.deepThreat,
                completedRuns: records
            )
        )
        XCTAssertNil(
            AchievementCatalogTransitionV2ToV3.recomputedCompletedAt(
                for: LaunchAchievementID.maximumOverdrive,
                completedRuns: records
            )
        )
        XCTAssertEqual(
            AchievementCatalogTransitionV2ToV3.recomputedCompletedAt(
                for: LaunchAchievementID.perfectPocket,
                completedRuns: records
            ),
            qualifying.recordedAt
        )
        XCTAssertNil(
            AchievementCatalogTransitionV2ToV3.recomputedPercent(
                for: LaunchAchievementID.firstRead,
                completedRuns: records
            )
        )
    }

    func testCatalogV2ToV3DatesFranchiseAtFiftiethNaturalRun() {
        let baseDate = Date(timeIntervalSince1970: 20_000)
        let naturalRuns = (0 ..< 50).map { index in
            CompletedRunRecord(
                run: makeRun(score: 0),
                recordedAt: baseDate.addingTimeInterval(Double(index)),
                rewardCoins: 10
            )
        }
        let abandoned = CompletedRunRecord(
            run: makeRun(score: 100_000, finishReason: .abandoned),
            recordedAt: baseDate.addingTimeInterval(-10),
            rewardCoins: 0
        )

        XCTAssertNil(
            AchievementCatalogTransitionV2ToV3.recomputedCompletedAt(
                for: LaunchAchievementID.franchisePlayer,
                completedRuns: Array(naturalRuns.prefix(49)) + [abandoned]
            )
        )
        XCTAssertEqual(
            AchievementCatalogTransitionV2ToV3.recomputedCompletedAt(
                for: LaunchAchievementID.franchisePlayer,
                completedRuns: Array(naturalRuns.reversed()) + [abandoned]
            ),
            naturalRuns[49].recordedAt
        )
    }

    func testAchievementSemanticFingerprintIncludesFrozenV2AndAdditiveV3Contracts() {
        let material = AchievementCatalog.persistedFingerprintMaterial()

        XCTAssertEqual(
            AchievementCatalog.persistedSemanticIdentifier,
            "pocket-vector-launch-achievement-catalog-semantics-v3"
        )
        XCTAssertTrue(
            material.contains(
                AchievementCatalogTransitionV1ToV2.persistedSemanticIdentifier
            )
        )
        XCTAssertTrue(material.contains("achievement.century_of_connections.v1"))
        XCTAssertTrue(material.contains("achievement.millenia_of_connections.v1"))
        XCTAssertTrue(
            material.contains(
                AchievementCatalogTransitionV1ToV2.pendingQueuePolicyIdentifier
            )
        )
        XCTAssertTrue(
            material.contains(
                AchievementCatalogTransitionV1ToV2.submissionPolicyIdentifier
            )
        )
        XCTAssertTrue(
            material.contains(
                AchievementCatalogTransitionV1ToV2
                    .settlementReceiptPolicyIdentifier
            )
        )
        XCTAssertTrue(
            material.contains(
                AchievementCatalogTransitionV1ToV2
                    .settlementReceiptPreservationPolicyIdentifier
            )
        )
        XCTAssertEqual(
            AchievementCatalogTransitionV1ToV2.targetCatalogSemanticIdentifier,
            "pocket-vector-launch-achievement-catalog-semantics-v2"
        )
        XCTAssertTrue(
            material.contains(
                AchievementCatalogTransitionV2ToV3.persistedSemanticIdentifier
            )
        )
        XCTAssertTrue(
            material.contains(
                AchievementCatalogTransitionV2ToV3.legacyRunFactPolicyIdentifier
            )
        )
        XCTAssertTrue(
            material.contains(
                AchievementCatalogTransitionV2ToV3.pendingQueuePolicyIdentifier
            )
        )
        XCTAssertTrue(
            material.contains(
                AchievementCatalogTransitionV2ToV3.cloudScopePolicyIdentifier
            )
        )
        XCTAssertTrue(material.contains(CompletedRun.deepCompletionCountPolicyIdentifier))
        XCTAssertTrue(
            material.contains(
                AchievementEvaluator.achievementFactValidationPolicyIdentifier
            )
        )
        XCTAssertTrue(
            material.contains(
                CompletedRun.maximumOverdriveTouchdownCountPolicyIdentifier
            )
        )
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

    private func evaluatedProgress(
        run: CompletedRun,
        career: CareerStatistics = CareerStatistics()
    ) -> [AchievementID: AchievementProgress] {
        Dictionary(
            uniqueKeysWithValues: AchievementEvaluator.evaluate(
                run: run,
                careerAfter: career,
                existing: [:],
                evaluatedAt: Date(timeIntervalSince1970: 9_000)
            ).map { ($0.current.id, $0.current) }
        )
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
        deepCompletions: Int = 0,
        maximumOverdriveTouchdowns: Int = 0,
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
            bonusTouchdownCount: bonusTouchdowns,
            deepCompletionCount: deepCompletions,
            maximumOverdriveTouchdownCount: maximumOverdriveTouchdowns
        )
    }
}

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
    }

    func testEvaluatorCompletesAllEightAtExactRequirements() {
        let statistics = RunStatisticsSnapshot(
            attempts: 25,
            completions: 16,
            touchdowns: 4,
            incompletions: 5,
            longestTouchdownStreak: 4
        )
        let run = makeRun(
            score: 65_000,
            statistics: statistics,
            lanes: Set(LaneID.allCases),
            bonusTouchdowns: 1
        )
        var career = CareerStatistics()
        career.completions = 996
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

    func testAchievementSemanticFingerprintIncludesV2TransitionContract() {
        let material = AchievementCatalog.persistedFingerprintMaterial()

        XCTAssertEqual(
            AchievementCatalog.persistedSemanticIdentifier,
            "pocket-vector-launch-achievement-catalog-semantics-v2"
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

import Foundation

enum AchievementEvaluator {
    static let persistedSemanticIdentifier =
        "pocket-vector-achievement-evaluator-semantics-v2"
    static let eligibleRunPolicyIdentifier =
        "naturally-completed-runs-only-v1"
    static let achievementFactValidationPolicyIdentifier =
        "reject-structurally-invalid-completed-run-achievement-facts-v1"
    static let evaluationOrderPolicyIdentifier =
        "achievement-id-utf8-ascending-v1"
    static let progressPolicyIdentifier =
        "monotonic-max-percent-and-first-completion-date-v1"
    static let binaryProgressPolicyIdentifier =
        "value-greater-than-or-equal-target-yields-100-else-0-v1"
    static let scaledProgressPolicyIdentifier =
        "target-nonpositive-100-else-clamped-integer-floor-percent-v1"
    static let allLanesPolicyIdentifier =
        "set-intersection-with-all-lane-ids-v1"

    static var persistedFingerprintMaterial: [String] {
        let completedRun = CompletedRun.achievementEligibilityFingerprintMaterial
        let achievementFacts = CompletedRun.achievementFactsFingerprintMaterial
        let runStatistics =
            RunStatisticsSnapshot.achievementDependencyFingerprintMaterial
        let career = CareerStatistics.achievementDependencyFingerprintMaterial
        let accumulator = PersistedCareerAccumulatorV1.persistedFingerprintMaterial
        return [
            persistedSemanticIdentifier,
            "eligibleRunPolicy", eligibleRunPolicyIdentifier,
            "achievementFactValidationPolicy",
            achievementFactValidationPolicyIdentifier,
            "evaluationOrderPolicy", evaluationOrderPolicyIdentifier,
            "progressPolicy", progressPolicyIdentifier,
            "binaryProgressPolicy", binaryProgressPolicyIdentifier,
            "scaledProgressPolicy", scaledProgressPolicyIdentifier,
            "allLanesPolicy", allLanesPolicyIdentifier,
            "completedRunDependencyMaterialCount", String(completedRun.count),
        ] + completedRun + [
            "achievementFactMaterialCount", String(achievementFacts.count),
        ] + achievementFacts + [
            "runStatisticsDependencyMaterialCount", String(runStatistics.count),
        ] + runStatistics + [
            "careerDependencyMaterialCount", String(career.count),
        ] + career + [
            "careerAccumulatorDependencyMaterialCount", String(accumulator.count),
        ] + accumulator
    }

    static func evaluate(
        run: CompletedRun,
        careerAfter: CareerStatistics,
        existing: [AchievementID: AchievementProgress],
        evaluatedAt: Date
    ) -> [AchievementProgressUpdate] {
        guard run.isNaturallyCompleted,
              run.achievementFactsAreStructurallyValid else { return [] }

        return AchievementCatalog.persistedEvaluationOrder(
            AchievementCatalog.launch
        ).compactMap { definition in
            let previous = existing[definition.id]
                ?? AchievementProgress(id: definition.id)
            let evaluatedPercent = percentComplete(
                for: definition.rule,
                run: run,
                careerAfter: careerAfter
            )
            let newPercent = max(previous.percentComplete, evaluatedPercent)
            guard newPercent != previous.percentComplete else { return nil }

            var current = previous
            current.percentComplete = newPercent
            if newPercent == 100, previous.completedAt == nil {
                current.completedAt = evaluatedAt
            }
            return AchievementProgressUpdate(previous: previous, current: current)
        }
    }

    private static func percentComplete(
        for rule: AchievementRule,
        run: CompletedRun,
        careerAfter: CareerStatistics
    ) -> Int {
        switch rule {
        case let .careerSuccessfulPasses(target):
            return binaryPercent(value: careerAfter.successfulPasses, target: target)

        case let .incrementalCareerSuccessfulPasses(target):
            return scaledPercent(value: careerAfter.successfulPasses, target: target)

        case let .incrementalCareerCompletedRuns(target):
            return scaledPercent(value: careerAfter.completedRuns, target: target)

        case let .careerTouchdowns(target):
            return binaryPercent(value: careerAfter.touchdowns, target: target)

        case let .careerBonusTouchdowns(target):
            return binaryPercent(value: careerAfter.bonusTouchdowns, target: target)

        case .allLanesInSingleRun:
            let completedCount = Set(LaneID.allCases).intersection(run.completedLaneIDs).count
            return binaryPercent(value: completedCount, target: LaneID.allCases.count)

        case let .singleRunAccuracy(percent, minimumAttempts):
            return run.statistics.meetsAccuracy(
                percent: percent,
                minimumAttempts: minimumAttempts
            ) ? 100 : 0

        case let .singleRunBonusTouchdowns(target):
            return binaryPercent(value: run.bonusTouchdownCount, target: target)

        case let .singleRunDeepCompletions(target):
            return binaryPercent(value: run.deepCompletionCount, target: target)

        case let .singleRunMaximumOverdriveTouchdowns(target):
            return binaryPercent(
                value: run.maximumOverdriveTouchdownCount,
                target: target
            )

        case let .singleRunTouchdownStreak(target):
            return binaryPercent(
                value: run.statistics.longestTouchdownStreak,
                target: target
            )

        case let .singleRunScore(target):
            return binaryPercent(value: run.score, target: target)
        }
    }

    private static func binaryPercent(value: Int, target: Int) -> Int {
        value >= target ? 100 : 0
    }

    private static func scaledPercent(value: Int, target: Int) -> Int {
        guard target > 0 else { return 100 }
        let clampedValue = min(target, max(0, value))
        return clampedValue * 100 / target
    }
}

import Foundation

enum AchievementEvaluator {
    static func evaluate(
        run: CompletedRun,
        careerAfter: CareerStatistics,
        existing: [AchievementID: AchievementProgress],
        evaluatedAt: Date
    ) -> [AchievementProgressUpdate] {
        guard run.isNaturallyCompleted else { return [] }

        return AchievementCatalog.launch.compactMap { definition in
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

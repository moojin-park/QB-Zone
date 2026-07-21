import Foundation

struct RunRewardBreakdown: Codable, Equatable, Sendable {
    let isEligible: Bool
    let completionCoins: Int64
    let performanceCoins: Int64
    let accuracyCoins: Int64

    var totalCoins: Int64 {
        completionCoins + performanceCoins + accuracyCoins
    }

    static let ineligible = RunRewardBreakdown(
        isEligible: false,
        completionCoins: 0,
        performanceCoins: 0,
        accuracyCoins: 0
    )
}

enum RunRewardBreakdownError: Error, Equatable, Sendable {
    case unsupportedEconomyVersion(Int)
}

extension CompletedRun {
    /// Resolves this run against the immutable economy rules captured when the run began.
    /// Supported but ineligible runs return an all-zero breakdown; unknown versions fail closed.
    func rewardBreakdown() throws -> RunRewardBreakdown {
        try RunRewardCalculator.calculate(for: self)
    }
}

enum RunRewardCalculator {
    static let supportedEconomyVersions: Set<Int> = [
        PersistedEconomyRulesV1.run.economyVersion,
    ]

    static func calculate(for run: CompletedRun) throws -> RunRewardBreakdown {
        guard let rules = rules(for: run.configuration.economyVersion) else {
            throw RunRewardBreakdownError.unsupportedEconomyVersion(
                run.configuration.economyVersion
            )
        }
        guard rules.isRewardEligible(run) else { return .ineligible }

        let nonnegativeScore = max(0, run.score)
        let performanceCoins = min(
            rules.maximumScoreCoins,
            Int64(nonnegativeScore / rules.scoreCoinsPerPoints)
        )
        let accuracyCoins = meetsAccuracy(run.statistics, rules: rules)
            ? rules.accuracyBonusCoins
            : 0

        return RunRewardBreakdown(
            isEligible: true,
            completionCoins: rules.baseRunCoins,
            performanceCoins: performanceCoins,
            accuracyCoins: accuracyCoins
        )
    }

    static func isRewardEligible(_ run: CompletedRun) -> Bool {
        rules(for: run.configuration.economyVersion)?.isRewardEligible(run) ?? false
    }

    private static func rules(
        for economyVersion: Int
    ) -> PersistedEconomyRulesV1.RunRules? {
        PersistedEconomyRulesV1.runRules(for: economyVersion)
    }

    private static func meetsAccuracy(
        _ statistics: RunStatisticsSnapshot,
        rules: PersistedEconomyRulesV1.RunRules
    ) -> Bool {
        guard statistics.attempts >= rules.accuracyMinimumAttempts,
              statistics.attempts > 0 else {
            return false
        }

        let successfulPasses = statistics.completions.addingReportingOverflow(
            statistics.touchdowns
        )
        let successfulPercent = successfulPasses.partialValue.multipliedReportingOverflow(
            by: 100
        )
        let requiredPercent = statistics.attempts.multipliedReportingOverflow(
            by: rules.accuracyMinimumPercent
        )
        guard !successfulPasses.overflow,
              !successfulPercent.overflow,
              !requiredPercent.overflow else {
            return false
        }

        return successfulPercent.partialValue >= requiredPercent.partialValue
    }
}

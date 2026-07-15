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

enum RunRewardCalculator {
    static func calculate(for run: CompletedRun) -> RunRewardBreakdown {
        guard run.isRewardEligible else { return .ineligible }

        let nonnegativeScore = max(0, run.score)
        let performanceCoins = min(
            EconomyConfiguration.maximumScoreCoins,
            Int64(nonnegativeScore / EconomyConfiguration.scoreCoinsPerPoints)
        )
        let accuracyCoins = run.statistics.meetsAccuracy(
            percent: EconomyConfiguration.accuracyBonusMinimumPercent,
            minimumAttempts: EconomyConfiguration.accuracyBonusMinimumAttempts
        )
            ? EconomyConfiguration.accuracyBonusCoins
            : 0

        return RunRewardBreakdown(
            isEligible: true,
            completionCoins: EconomyConfiguration.baseRunCoins,
            performanceCoins: performanceCoins,
            accuracyCoins: accuracyCoins
        )
    }
}

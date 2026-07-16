import Foundation

/// Immutable launch rules used to decode and validate profile schema V1.
/// These values intentionally do not read mutable live configuration. A future
/// economy change must introduce a profile migration/versioned ledger reason
/// before changing how already-persisted V1 entries are interpreted.
enum PersistedEconomyRulesV1 {
    struct RunRules: Equatable, Sendable {
        let economyVersion: Int
        let naturalRunMilliseconds: Int
        let minimumRewardAttempts: Int
        let baseRunCoins: Int64
        let scoreCoinsPerPoints: Int
        let maximumScoreCoins: Int64
        let accuracyBonusCoins: Int64
        let accuracyMinimumAttempts: Int
        let accuracyMinimumPercent: Int

        func isNaturallyCompleted(_ run: CompletedRun) -> Bool {
            run.finishReason == .timerExpired
                && run.elapsedGameplayMilliseconds == naturalRunMilliseconds
        }

        func isRewardEligible(_ run: CompletedRun) -> Bool {
            isNaturallyCompleted(run)
                && run.statistics.attempts >= minimumRewardAttempts
        }

        func rewardCoins(for run: CompletedRun) -> Int64 {
            guard isRewardEligible(run) else { return 0 }
            let performance = min(
                maximumScoreCoins,
                Int64(max(0, run.score) / scoreCoinsPerPoints)
            )
            let hasAccuracyBonus = run.statistics.attempts >= accuracyMinimumAttempts
                && run.statistics.attempts > 0
                && run.statistics.successfulPasses * 100
                    >= run.statistics.attempts * accuracyMinimumPercent
            return baseRunCoins
                + performance
                + (hasAccuracyBonus ? accuracyBonusCoins : 0)
        }
    }

    static let run = RunRules(
        economyVersion: 1,
        naturalRunMilliseconds: 60_000,
        minimumRewardAttempts: 3,
        baseRunCoins: 10,
        scoreCoinsPerPoints: 1_000,
        maximumScoreCoins: 25,
        accuracyBonusCoins: 5,
        accuracyMinimumAttempts: 10,
        accuracyMinimumPercent: 70
    )

    static let signingBonusVersion = 1
    static let signingBonusCoins: Int64 = 250
    /// The signing bonus is an account-wide singleton whose full ledger entry
    /// must compare identically on every device. This fixed value is an
    /// identity field, not the wall-clock time at which a player earned it.
    static let signingBonusLedgerCreatedAt = Date(timeIntervalSince1970: 0)
    static let rewardedAdCoins: Int64 = 100
    static let rewardedAdRunThreshold = 5
    static let lockedTeamPrice: Int64 = 1_500
    static let alternateJerseyPrice: Int64 = 500
    static let alternateFootballPrice: Int64 = 750

    static let coinPackCoins: [CoinPackID: Int64] = [
        CoinPackID("pocket"): 500,
        CoinPackID("team"): 1_650,
        CoinPackID("bundle"): 3_600,
        CoinPackID("vault"): 6_500,
    ]

    static func runRules(for economyVersion: Int) -> RunRules? {
        economyVersion == run.economyVersion ? run : nil
    }

    static func catalogPrice(for item: CatalogItemDescriptor) -> Int64 {
        switch item.kind {
        case .team:
            lockedTeamPrice
        case .alternateJersey:
            alternateJerseyPrice
        case .football:
            alternateFootballPrice
        }
    }
}

enum PersistedCareerAccumulatorV1 {
    static let semanticIdentifier =
        "pocket-vector-persisted-career-accumulator-v1"
    static let naturalCompletionPolicyIdentifier =
        "supported-economy-version-and-timer-expired-with-exact-persisted-run-duration-v1"
    static let nonNaturalRunPolicyIdentifier = "return-input-career-unchanged-v1"
    static let integerAdditionPolicyIdentifier =
        "native-int-adding-reporting-overflow-throws-arithmetic-overflow-v1"
    static let totalScoreAdditionPolicyIdentifier =
        "int64-adding-reporting-overflow-throws-arithmetic-overflow-v1"
    static let highestScorePolicyIdentifier = "maximum-existing-and-run-score-v1"
    static let recomputePolicyIdentifier =
        "input-sequence-left-fold-from-zero-career-v1"
    static let fieldUpdateManifest =
        "attempts+=run.attempts,bonusTouchdowns+=run.bonusTouchdownCount," +
        "completedRuns+=1,completions+=run.completions," +
        "incompletions+=run.incompletions," +
        "interceptions+=run.interceptions," +
        "rewardEligibleRuns+=1-if-eligible,touchdowns+=run.touchdowns"

    static var persistedFingerprintMaterial: [String] {
        let rules = PersistedEconomyRulesV1.run
        return [
            semanticIdentifier,
            "supportedEconomyVersion", String(rules.economyVersion),
            "naturalCompletionPolicy", naturalCompletionPolicyIdentifier,
            "naturalCompletionFinishReason",
            RunFinishReason.timerExpired.rawValue,
            "naturalCompletionMilliseconds",
            String(rules.naturalRunMilliseconds),
            "rewardEligibilityMinimumAttempts",
            String(rules.minimumRewardAttempts),
            "nonNaturalRunPolicy", nonNaturalRunPolicyIdentifier,
            "fieldUpdates", fieldUpdateManifest,
            "integerAdditionPolicy", integerAdditionPolicyIdentifier,
            "successfulPassesOverflowCheck",
            "checked-completions-plus-touchdowns-v1",
            "highestScorePolicy", highestScorePolicyIdentifier,
            "totalScoreUpdate", "existing-totalScore-plus-int64-run-score-v1",
            "totalScoreAdditionPolicy", totalScoreAdditionPolicyIdentifier,
            "recomputePolicy", recomputePolicyIdentifier,
        ]
    }

    static func applying(
        _ run: CompletedRun,
        to career: CareerStatistics
    ) throws -> CareerStatistics {
        guard let rules = PersistedEconomyRulesV1.runRules(
            for: run.configuration.economyVersion
        ) else {
            throw ProfileValidationError.invalidCompletedRun(
                run.runID,
                .unsupportedEconomyVersion(run.configuration.economyVersion)
            )
        }
        guard rules.isNaturallyCompleted(run) else { return career }

        var next = career
        next.completedRuns = try adding(next.completedRuns, 1)
        if rules.isRewardEligible(run) {
            next.rewardEligibleRuns = try adding(next.rewardEligibleRuns, 1)
        }
        next.attempts = try adding(next.attempts, run.statistics.attempts)
        next.completions = try adding(next.completions, run.statistics.completions)
        next.touchdowns = try adding(next.touchdowns, run.statistics.touchdowns)
        next.incompletions = try adding(next.incompletions, run.statistics.incompletions)
        next.interceptions = try adding(next.interceptions, run.statistics.interceptions)
        next.bonusTouchdowns = try adding(
            next.bonusTouchdowns,
            run.bonusTouchdownCount
        )
        _ = try adding(next.completions, next.touchdowns)
        next.highestScore = max(next.highestScore, run.score)
        let total = next.totalScore.addingReportingOverflow(Int64(run.score))
        guard !total.overflow else {
            throw ProfileValidationError.arithmeticOverflow
        }
        next.totalScore = total.partialValue
        return next
    }

    static func recompute(
        from records: some Sequence<CompletedRunRecord>
    ) throws -> CareerStatistics {
        var career = CareerStatistics()
        for record in records {
            career = try applying(record.run, to: career)
        }
        return career
    }

    private static func adding(_ lhs: Int, _ rhs: Int) throws -> Int {
        let result = lhs.addingReportingOverflow(rhs)
        guard !result.overflow else {
            throw ProfileValidationError.arithmeticOverflow
        }
        return result.partialValue
    }
}

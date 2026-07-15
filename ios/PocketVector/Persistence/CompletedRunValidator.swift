import Foundation

enum CompletedRunValidator {
    static let maximumAcceptedScore = 1_000_000
    static let maximumAcceptedAttempts = 300

    static func validate(
        _ run: CompletedRun,
        recordedAt: Date,
        inventory: PlayerInventory,
        catalog: LaunchCatalog = .approved
    ) throws {
        guard run.finishReason != .debugPreview else {
            throw CompletedRunValidationError.debugPreviewNotPersistable
        }
        guard let rules = PersistedEconomyRulesV1.runRules(
            for: run.configuration.economyVersion
        ) else {
            throw CompletedRunValidationError.unsupportedEconomyVersion(
                run.configuration.economyVersion
            )
        }
        try validateChronology(run, recordedAt: recordedAt, rules: rules)
        try validateScoreAndStatistics(run)
        try validateConfiguration(run.configuration, inventory: inventory, catalog: catalog)
    }

    static func rewardCoins(for run: CompletedRun) throws -> Int64 {
        guard let rules = PersistedEconomyRulesV1.runRules(
            for: run.configuration.economyVersion
        ) else {
            throw CompletedRunValidationError.unsupportedEconomyVersion(
                run.configuration.economyVersion
            )
        }
        return rules.rewardCoins(for: run)
    }

    static func isRewardEligible(_ run: CompletedRun) -> Bool {
        PersistedEconomyRulesV1.runRules(for: run.configuration.economyVersion)?
            .isRewardEligible(run) ?? false
    }

    static func isNaturallyCompleted(_ run: CompletedRun) -> Bool {
        PersistedEconomyRulesV1.runRules(for: run.configuration.economyVersion)?
            .isNaturallyCompleted(run) ?? false
    }

    private static func validateChronology(
        _ run: CompletedRun,
        recordedAt: Date,
        rules: PersistedEconomyRulesV1.RunRules
    ) throws {
        let started = run.configuration.startedAt.timeIntervalSince1970
        let ended = run.endedAt.timeIntervalSince1970
        let recorded = recordedAt.timeIntervalSince1970
        guard started.isFinite, ended.isFinite, recorded.isFinite,
              run.endedAt >= run.configuration.startedAt,
              recordedAt >= run.endedAt else {
            throw CompletedRunValidationError.invalidChronology
        }

        let elapsed = run.elapsedGameplayMilliseconds
        switch run.finishReason {
        case .timerExpired:
            guard elapsed == rules.naturalRunMilliseconds else {
                throw CompletedRunValidationError.invalidElapsedMilliseconds(elapsed)
            }
        case .abandoned:
            guard (0 ... rules.naturalRunMilliseconds).contains(elapsed) else {
                throw CompletedRunValidationError.invalidElapsedMilliseconds(elapsed)
            }
        case .debugPreview:
            throw CompletedRunValidationError.debugPreviewNotPersistable
        }

        let wallClockMilliseconds = run.endedAt.timeIntervalSince(
            run.configuration.startedAt
        ) * 1_000
        guard wallClockMilliseconds + 1 >= Double(elapsed) else {
            throw CompletedRunValidationError.invalidChronology
        }
    }

    private static func validateScoreAndStatistics(_ run: CompletedRun) throws {
        guard (0 ... maximumAcceptedScore).contains(run.score) else {
            throw CompletedRunValidationError.invalidScore(run.score)
        }
        let statistics = run.statistics
        let values = [
            statistics.attempts,
            statistics.completions,
            statistics.touchdowns,
            statistics.incompletions,
            statistics.interceptions,
            statistics.longestTouchdownStreak,
            run.bonusTouchdownCount,
        ]
        guard values.allSatisfy({ $0 >= 0 }),
              statistics.attempts <= maximumAcceptedAttempts,
              statistics.completions <= statistics.attempts,
              statistics.touchdowns <= statistics.attempts,
              statistics.incompletions <= statistics.attempts,
              statistics.interceptions <= statistics.attempts,
              statistics.longestTouchdownStreak <= statistics.touchdowns,
              run.bonusTouchdownCount <= statistics.touchdowns else {
            throw CompletedRunValidationError.invalidStatistics
        }

        let first = statistics.completions.addingReportingOverflow(
            statistics.touchdowns
        )
        let second = first.partialValue.addingReportingOverflow(
            statistics.incompletions
        )
        let third = second.partialValue.addingReportingOverflow(
            statistics.interceptions
        )
        guard !first.overflow, !second.overflow, !third.overflow,
              third.partialValue == statistics.attempts else {
            throw CompletedRunValidationError.invalidStatistics
        }

        let successfulPasses = first.partialValue
        guard run.completedLaneIDs.isSubset(of: Set(LaneID.allCases)),
              run.completedLaneIDs.count <= successfulPasses else {
            throw CompletedRunValidationError.invalidLaneHistory
        }
    }

    private static func validateConfiguration(
        _ configuration: RunConfiguration,
        inventory: PlayerInventory,
        catalog: LaunchCatalog
    ) throws {
        guard catalog.team(id: configuration.offenseTeamID) != nil else {
            throw CompletedRunValidationError.unknownOffenseTeam(
                configuration.offenseTeamID
            )
        }
        guard inventory.ownedTeamIDs.contains(configuration.offenseTeamID) else {
            throw CompletedRunValidationError.offenseTeamNotOwned(
                configuration.offenseTeamID
            )
        }
        guard let offenseJersey = catalog.jersey(id: configuration.offenseJerseyID),
              offenseJersey.teamID == configuration.offenseTeamID else {
            throw CompletedRunValidationError.invalidOffenseJersey(
                configuration.offenseJerseyID
            )
        }
        guard inventory.ownedJerseyIDs.contains(configuration.offenseJerseyID) else {
            throw CompletedRunValidationError.offenseJerseyNotOwned(
                configuration.offenseJerseyID
            )
        }
        guard catalog.team(id: configuration.defenseTeamID) != nil else {
            throw CompletedRunValidationError.unknownDefenseTeam(
                configuration.defenseTeamID
            )
        }
        guard configuration.defenseTeamID != configuration.offenseTeamID else {
            throw CompletedRunValidationError.sameTeamMatchup(
                configuration.offenseTeamID
            )
        }
        guard let defenseJersey = catalog.jersey(id: configuration.defenseJerseyID),
              defenseJersey.teamID == configuration.defenseTeamID else {
            throw CompletedRunValidationError.invalidDefenseJersey(
                configuration.defenseJerseyID
            )
        }
        guard catalog.football(id: configuration.footballID) != nil else {
            throw CompletedRunValidationError.invalidFootball(
                configuration.footballID
            )
        }
        guard inventory.ownedFootballIDs.contains(configuration.footballID) else {
            throw CompletedRunValidationError.footballNotOwned(
                configuration.footballID
            )
        }
    }
}

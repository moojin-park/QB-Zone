import Foundation

enum LaunchAchievementID {
    static let firstRead = AchievementID("achievement.first_read.v1")
    static let paydirt = AchievementID("achievement.paydirt.v1")
    static let cashTheCharge = AchievementID("achievement.cash_the_charge.v1")
    static let fullRouteTree = AchievementID("achievement.full_route_tree.v1")
    static let dialedIn = AchievementID("achievement.dialed_in.v1")
    static let hotHand = AchievementID("achievement.hot_hand.v1")
    static let lightUpTheBoard = AchievementID("achievement.light_up_the_board.v1")
    static let millenniaOfConnections = AchievementID(
        "achievement.millenia_of_connections.v1"
    )
    static let perfectPocket = AchievementID("achievement.perfect_pocket.v1")
    static let franchisePlayer = AchievementID("achievement.franchise_player.v1")
    static let overcharged = AchievementID("achievement.overcharged.v1")
    static let deepThreat = AchievementID("achievement.deep_threat.v1")
    static let untouchable = AchievementID("achievement.untouchable.v1")
    static let maximumOverdrive = AchievementID(
        "achievement.maximum_overdrive.v1"
    )

    /// Source compatibility for presentation routing while Art adopts the new
    /// symbol. This alias resolves to the current permanent Game Center ID; it
    /// never makes the retired raw ID part of the launch catalog.
    static let centuryOfConnections = millenniaOfConnections
}

enum AchievementCatalog {
    static let v2PersistedSemanticIdentifier =
        "pocket-vector-launch-achievement-catalog-semantics-v2"
    static let persistedSemanticIdentifier =
        "pocket-vector-launch-achievement-catalog-semantics-v3"

    static let launch: [AchievementDefinition] = [
        AchievementDefinition(
            id: LaunchAchievementID.firstRead,
            displayName: "First Read",
            detail: "Complete any successful pass.",
            points: 25,
            rule: .careerSuccessfulPasses(1)
        ),
        AchievementDefinition(
            id: LaunchAchievementID.paydirt,
            displayName: "Paydirt",
            detail: "Score a touchdown.",
            points: 50,
            rule: .careerTouchdowns(1)
        ),
        AchievementDefinition(
            id: LaunchAchievementID.cashTheCharge,
            displayName: "Cash the Charge",
            detail: "Score a touchdown while TD Bonus is active.",
            points: 75,
            rule: .careerBonusTouchdowns(1)
        ),
        AchievementDefinition(
            id: LaunchAchievementID.fullRouteTree,
            displayName: "Full Route Tree",
            detail: "Complete a pass in all four lanes during one run.",
            points: 75,
            rule: .allLanesInSingleRun
        ),
        AchievementDefinition(
            id: LaunchAchievementID.dialedIn,
            displayName: "Dialed In",
            detail: "Finish with at least 80% accuracy over at least 25 pass attempts.",
            points: 75,
            rule: .singleRunAccuracy(percent: 80, minimumAttempts: 25)
        ),
        AchievementDefinition(
            id: LaunchAchievementID.hotHand,
            displayName: "Hot Hand",
            detail: "Score four consecutive touchdowns during one run.",
            points: 100,
            rule: .singleRunTouchdownStreak(4)
        ),
        AchievementDefinition(
            id: LaunchAchievementID.lightUpTheBoard,
            displayName: "Light Up the Board",
            detail: "Reach 65,000 points during one run.",
            points: 100,
            rule: .singleRunScore(65_000)
        ),
        AchievementDefinition(
            id: LaunchAchievementID.millenniaOfConnections,
            displayName: "Millennia of Connections",
            detail: "Complete 1,000 career passes, including touchdowns.",
            points: 100,
            rule: .incrementalCareerSuccessfulPasses(1_000)
        ),
        AchievementDefinition(
            id: LaunchAchievementID.perfectPocket,
            displayName: "Perfect Pocket",
            detail: "Finish with 100% accuracy over at least 20 pass attempts.",
            points: 75,
            rule: .singleRunAccuracy(percent: 100, minimumAttempts: 20)
        ),
        AchievementDefinition(
            id: LaunchAchievementID.franchisePlayer,
            displayName: "Franchise Player",
            detail: "Complete 50 natural runs.",
            points: 50,
            rule: .incrementalCareerCompletedRuns(50)
        ),
        AchievementDefinition(
            id: LaunchAchievementID.overcharged,
            displayName: "Overcharged",
            detail: "Score three TD Bonus touchdowns during one run.",
            points: 50,
            rule: .singleRunBonusTouchdowns(3)
        ),
        AchievementDefinition(
            id: LaunchAchievementID.deepThreat,
            displayName: "Deep Threat",
            detail: "Complete five passes in the deep lane during one run.",
            points: 50,
            rule: .singleRunDeepCompletions(5)
        ),
        AchievementDefinition(
            id: LaunchAchievementID.untouchable,
            displayName: "Untouchable",
            detail: "Reach 100,000 points during one run.",
            points: 100,
            rule: .singleRunScore(100_000)
        ),
        AchievementDefinition(
            id: LaunchAchievementID.maximumOverdrive,
            displayName: "Maximum Overdrive",
            detail: "Score a touchdown with TD Bonus active and the capped 3× multiplier.",
            points: 75,
            rule: .singleRunMaximumOverdriveTouchdowns(1)
        ),
    ]

    /// Achievement updates are persisted in settlement receipts. Declaration
    /// order is presentation-only, so persisted evaluation always uses this
    /// stable semantic order instead of the source array's insertion order.
    static func persistedEvaluationOrder(
        _ definitions: [AchievementDefinition]
    ) -> [AchievementDefinition] {
        precondition(
            Set(definitions.map(\.id)).count == definitions.count,
            "Achievement IDs must be unique"
        )
        return definitions.sorted {
            $0.id.rawValue.utf8.lexicographicallyPrecedes($1.id.rawValue.utf8)
        }
    }

    static func persistedFingerprintMaterial(
        for definitions: [AchievementDefinition] = launch
    ) -> [String] {
        let ordered = persistedEvaluationOrder(definitions)
        let evaluator = AchievementEvaluator.persistedFingerprintMaterial
        var material = [
            persistedSemanticIdentifier,
            "evaluatorMaterialCount", String(evaluator.count),
        ] + evaluator
        material.append(contentsOf: [
            "achievementCount", String(ordered.count),
        ])
        for definition in ordered {
            let rule = definition.rule.persistedFingerprintMaterial
            material.append(contentsOf: [
                "achievement", definition.id.rawValue,
                "points", String(definition.points),
                "ruleMaterialCount", String(rule.count),
            ])
            material.append(contentsOf: rule)
        }
        let transitionV1ToV2 = AchievementCatalogTransitionV1ToV2
            .persistedFingerprintMaterial
        material.append(contentsOf: [
            "transitionV1ToV2MaterialCount", String(transitionV1ToV2.count),
        ])
        material.append(contentsOf: transitionV1ToV2)
        let transitionV2ToV3 = AchievementCatalogTransitionV2ToV3
            .persistedFingerprintMaterial
        material.append(contentsOf: [
            "transitionV2ToV3MaterialCount", String(transitionV2ToV3.count),
        ])
        material.append(contentsOf: transitionV2ToV3)
        return material
    }
}

/// Declarative Technical contract for the PM-owned durable transition from the
/// pre-release V1 catalog to the current V2 catalog. Persistence must apply
/// this contract before validating a profile against `AchievementCatalog`.
enum AchievementCatalogTransitionV1ToV2 {
    static let persistedSemanticIdentifier =
        "pocket-vector-launch-achievement-catalog-transition-v1-to-v2"
    static let sourceCatalogSemanticIdentifier =
        "pocket-vector-launch-achievement-catalog-semantics-v1"
    static let targetCatalogSemanticIdentifier =
        AchievementCatalog.v2PersistedSemanticIdentifier

    static let retiredCenturyOfConnections = AchievementID(
        "achievement.century_of_connections.v1"
    )
    static let identifierReplacements = [
        retiredCenturyOfConnections: LaunchAchievementID.millenniaOfConnections,
    ]
    static let recomputedAchievementIDs: Set<AchievementID> = [
        LaunchAchievementID.dialedIn,
        LaunchAchievementID.lightUpTheBoard,
        LaunchAchievementID.millenniaOfConnections,
    ]
    static let currentStateForbiddenIDs: Set<AchievementID> = [
        retiredCenturyOfConnections,
    ]
    static let pendingQueueScrubIDs = recomputedAchievementIDs.union(
        currentStateForbiddenIDs
    )

    static let applicationPolicyIdentifier =
        "apply-once-before-current-catalog-validation-idempotently-v1"
    static let careerSourcePolicyIdentifier =
        "authoritative-career-successful-passes-counter-v1"
    static let completedRunSourcePolicyIdentifier =
        "naturally-completed-runs-ordered-by-recorded-at-then-run-id-v1"
    static let millenniaProgressPolicyIdentifier =
        "ignore-stored-percent-and-floor-clamped-career-passes-times-100-over-1000-v1"
    static let binaryReconciliationPolicyIdentifier =
        "ignore-stored-completion-and-recompute-from-earliest-qualifying-run-v1"
    static let currentStatePolicyIdentifier =
        "remove-retired-id-and-replace-only-three-targets-preserve-unrelated-v1"
    static let pendingQueuePolicyIdentifier =
        "scrub-each-provenance-bucket-and-reinsert-only-positive-same-logical-achievement-evidence-capped-to-earned-remove-empty-buckets-v1"
    static let pendingQueueCollapsePolicyIdentifier =
        "same-bucket-old-and-new-millennia-evidence-collapses-to-one-current-entry-v1"
    static let settlementReceiptPolicyIdentifier =
        "stable-replay-natural-runs-under-v2-and-replace-only-affected-updates-by-run-id-v1"
    static let settlementReceiptPreservationPolicyIdentifier =
        "preserve-unrelated-updates-and-all-nonachievement-receipt-fields-v1"
    static let submissionPolicyIdentifier =
        "never-manufacture-acknowledged-work-or-duplicate-awards-v1"

    static var persistedFingerprintMaterial: [String] {
        [
            persistedSemanticIdentifier,
            "sourceCatalog", sourceCatalogSemanticIdentifier,
            "targetCatalog", targetCatalogSemanticIdentifier,
            "replacementCount", "1",
            "replace", retiredCenturyOfConnections.rawValue,
            "with", LaunchAchievementID.millenniaOfConnections.rawValue,
            "recomputedAchievementCount", "3",
            "recomputedAchievement", LaunchAchievementID.dialedIn.rawValue,
            "recomputedAchievement", LaunchAchievementID.lightUpTheBoard.rawValue,
            "recomputedAchievement", LaunchAchievementID.millenniaOfConnections.rawValue,
            "currentStateForbiddenCount", "1",
            "currentStateForbidden", retiredCenturyOfConnections.rawValue,
            "pendingQueueScrubCount", "4",
            "pendingQueueScrub", retiredCenturyOfConnections.rawValue,
            "pendingQueueScrub", LaunchAchievementID.dialedIn.rawValue,
            "pendingQueueScrub", LaunchAchievementID.lightUpTheBoard.rawValue,
            "pendingQueueScrub", LaunchAchievementID.millenniaOfConnections.rawValue,
            "pendingEvidenceMappingCount", "4",
            "pendingEvidenceCurrent", LaunchAchievementID.dialedIn.rawValue,
            "pendingEvidenceSource", LaunchAchievementID.dialedIn.rawValue,
            "pendingEvidenceCurrent", LaunchAchievementID.lightUpTheBoard.rawValue,
            "pendingEvidenceSource", LaunchAchievementID.lightUpTheBoard.rawValue,
            "pendingEvidenceCurrent", LaunchAchievementID.millenniaOfConnections.rawValue,
            "pendingEvidenceSource", retiredCenturyOfConnections.rawValue,
            "pendingEvidenceCurrent", LaunchAchievementID.millenniaOfConnections.rawValue,
            "pendingEvidenceSource", LaunchAchievementID.millenniaOfConnections.rawValue,
            "applicationPolicy", applicationPolicyIdentifier,
            "careerSourcePolicy", careerSourcePolicyIdentifier,
            "completedRunSourcePolicy", completedRunSourcePolicyIdentifier,
            "millenniaProgressPolicy", millenniaProgressPolicyIdentifier,
            "binaryReconciliationPolicy", binaryReconciliationPolicyIdentifier,
            "currentStatePolicy", currentStatePolicyIdentifier,
            "pendingQueuePolicy", pendingQueuePolicyIdentifier,
            "pendingQueueCollapsePolicy", pendingQueueCollapsePolicyIdentifier,
            "settlementReceiptPolicy", settlementReceiptPolicyIdentifier,
            "settlementReceiptPreservationPolicy",
            settlementReceiptPreservationPolicyIdentifier,
            "submissionPolicy", submissionPolicyIdentifier,
        ]
    }

    /// Returns authoritative post-transition progress for the three changed
    /// achievements. Unrelated IDs return `nil` so migration preserves them.
    static func recomputedPercent(
        for achievementID: AchievementID,
        careerSuccessfulPasses: Int,
        completedRuns: [CompletedRunRecord]
    ) -> Int? {
        switch achievementID {
        case LaunchAchievementID.millenniaOfConnections:
            let clampedPasses = min(1_000, max(0, careerSuccessfulPasses))
            return clampedPasses * 100 / 1_000
        case LaunchAchievementID.dialedIn:
            return orderedNaturalRuns(completedRuns).contains {
                $0.run.statistics.meetsAccuracy(
                    percent: 80,
                    minimumAttempts: 25
                )
            } ? 100 : 0
        case LaunchAchievementID.lightUpTheBoard:
            return orderedNaturalRuns(completedRuns).contains {
                $0.run.score >= 65_000
            } ? 100 : 0
        default:
            return nil
        }
    }

    /// Returns the only IDs that may authorize rebuilt pending work for a
    /// current achievement inside one bound or unbound provenance bucket.
    static func pendingEvidenceSourceIDs(
        for currentAchievementID: AchievementID
    ) -> Set<AchievementID> {
        switch currentAchievementID {
        case LaunchAchievementID.dialedIn:
            [LaunchAchievementID.dialedIn]
        case LaunchAchievementID.lightUpTheBoard:
            [LaunchAchievementID.lightUpTheBoard]
        case LaunchAchievementID.millenniaOfConnections:
            [
                retiredCenturyOfConnections,
                LaunchAchievementID.millenniaOfConnections,
            ]
        default:
            []
        }
    }

    /// Pending Game Center work is recreated only when the same provenance
    /// bucket contains positive evidence for that logical achievement. The
    /// value is replaced by (never maxed with) freshly earned progress, and
    /// zero removes the entry. Mixed Century/Millennia evidence collapses to
    /// one current ID.
    static func reconciledPendingPercent(
        for currentAchievementID: AchievementID,
        pendingEvidencePercentsInSameProvenanceBucket: [AchievementID: Int],
        recomputedEarnedPercent: Int
    ) -> Int? {
        let permittedEvidence = pendingEvidenceSourceIDs(
            for: currentAchievementID
        )
        guard pendingEvidencePercentsInSameProvenanceBucket.contains(
            where: { permittedEvidence.contains($0.key) && $0.value > 0 }
        )
        else {
            return nil
        }
        let clamped = min(100, max(0, recomputedEarnedPercent))
        return clamped > 0 ? clamped : nil
    }

    /// Supplies the completion date PM persistence must retain after
    /// recomputation. Millennia uses the first chronological run that takes the
    /// authoritative successful-pass history across 1,000.
    static func recomputedCompletedAt(
        for achievementID: AchievementID,
        completedRuns: [CompletedRunRecord]
    ) -> Date? {
        let ordered = orderedNaturalRuns(completedRuns)
        switch achievementID {
        case LaunchAchievementID.millenniaOfConnections:
            var successfulPasses = 0
            for record in ordered {
                let completions = min(
                    1_000 - successfulPasses,
                    record.run.statistics.completions
                )
                successfulPasses += completions
                let touchdowns = min(
                    1_000 - successfulPasses,
                    record.run.statistics.touchdowns
                )
                successfulPasses += touchdowns
                if successfulPasses >= 1_000 {
                    return record.recordedAt
                }
            }
            return nil
        case LaunchAchievementID.dialedIn:
            return ordered.first {
                $0.run.statistics.meetsAccuracy(
                    percent: 80,
                    minimumAttempts: 25
                )
            }?.recordedAt
        case LaunchAchievementID.lightUpTheBoard:
            return ordered.first { $0.run.score >= 65_000 }?.recordedAt
        default:
            return nil
        }
    }

    private static func orderedNaturalRuns(
        _ completedRuns: [CompletedRunRecord]
    ) -> [CompletedRunRecord] {
        completedRuns
            .filter { $0.run.isNaturallyCompleted }
            .sorted {
                if $0.recordedAt != $1.recordedAt {
                    return $0.recordedAt < $1.recordedAt
                }
                return $0.run.runID.description.utf8.lexicographicallyPrecedes(
                    $1.run.runID.description.utf8
                )
            }
    }
}

/// Declarative Technical contract for the PM-owned durable transition from the
/// shipped eight-achievement V2 catalog to the additive Version 1.1 V3 catalog.
/// Persistence and cloud scope migration must apply this contract exactly once
/// before validating a profile against the current catalog.
enum AchievementCatalogTransitionV2ToV3 {
    static let persistedSemanticIdentifier =
        "pocket-vector-launch-achievement-catalog-transition-v2-to-v3"
    static let sourceCatalogSemanticIdentifier =
        AchievementCatalog.v2PersistedSemanticIdentifier
    static let targetCatalogSemanticIdentifier =
        AchievementCatalog.persistedSemanticIdentifier

    static let addedAchievementIDsInPersistedOrder: [AchievementID] = [
        LaunchAchievementID.deepThreat,
        LaunchAchievementID.franchisePlayer,
        LaunchAchievementID.maximumOverdrive,
        LaunchAchievementID.overcharged,
        LaunchAchievementID.perfectPocket,
        LaunchAchievementID.untouchable,
    ]
    static let addedAchievementIDs = Set(addedAchievementIDsInPersistedOrder)
    static let historicallyReplayableAchievementIDs: Set<AchievementID> = [
        LaunchAchievementID.franchisePlayer,
        LaunchAchievementID.overcharged,
        LaunchAchievementID.perfectPocket,
        LaunchAchievementID.untouchable,
    ]
    static let nonretroactiveAchievementIDs: Set<AchievementID> = [
        LaunchAchievementID.deepThreat,
        LaunchAchievementID.maximumOverdrive,
    ]

    static let legacyDeepCompletionCount = 0
    static let legacyMaximumOverdriveTouchdownCount = 0
    static let applicationPolicyIdentifier =
        "apply-once-from-explicit-v2-source-to-v3-before-current-validation-idempotently-v1"
    static let sourceStatePolicyIdentifier =
        "reject-added-v3-ids-in-v2-progress-queues-or-receipts-v1"
    static let completedRunUpgradePolicyIdentifier =
        "upgrade-player-and-settlement-receipt-run-copies-identically-v1"
    static let legacyRunFactPolicyIdentifier =
        "default-both-new-run-facts-to-zero-without-lane-score-bonus-or-streak-inference-v1"
    static let completedRunSourcePolicyIdentifier =
        "naturally-completed-runs-ordered-by-recorded-at-then-run-id-v1"
    static let replayPolicyIdentifier =
        "replay-perfect-franchise-overcharged-untouchable-from-authoritative-v2-history-v1"
    static let nonretroactivePolicyIdentifier =
        "deep-threat-and-maximum-overdrive-remain-zero-for-v2-history-v1"
    static let progressStatePolicyIdentifier =
        "seed-all-six-ids-replace-only-six-preserve-original-eight-and-unrelated-v1"
    static let pendingQueuePolicyIdentifier =
        "preserve-existing-buckets-and-enqueue-positive-replayed-new-maxima-once-as-unbound-v1"
    static let settlementReceiptPolicyIdentifier =
        "stable-replay-and-replace-only-six-updates-by-run-id-v1"
    static let settlementReceiptPreservationPolicyIdentifier =
        "preserve-existing-eight-updates-and-all-nonachievement-receipt-fields-v1"
    static let submissionPolicyIdentifier =
        "durable-source-target-marker-prevents-requeue-or-duplicate-submission-after-ack-v1"
    static let cloudScopePolicyIdentifier =
        "freeze-v2-predecessor-scope-upgrade-run-payloads-recompute-digests-and-never-merge-scopes-v1"

    static var persistedFingerprintMaterial: [String] {
        let replayable = addedAchievementIDsInPersistedOrder.filter {
            historicallyReplayableAchievementIDs.contains($0)
        }
        let nonretroactive = addedAchievementIDsInPersistedOrder.filter {
            nonretroactiveAchievementIDs.contains($0)
        }
        var material = [
            persistedSemanticIdentifier,
            "sourceCatalog", sourceCatalogSemanticIdentifier,
            "targetCatalog", targetCatalogSemanticIdentifier,
            "addedAchievementCount", String(addedAchievementIDsInPersistedOrder.count),
        ]
        for achievementID in addedAchievementIDsInPersistedOrder {
            material.append(contentsOf: [
                "addedAchievement", achievementID.rawValue,
            ])
        }
        material.append(contentsOf: [
            "historicallyReplayableCount", String(replayable.count),
        ])
        for achievementID in replayable {
            material.append(contentsOf: [
                "historicallyReplayable", achievementID.rawValue,
            ])
        }
        material.append(contentsOf: [
            "nonretroactiveCount", String(nonretroactive.count),
        ])
        for achievementID in nonretroactive {
            material.append(contentsOf: [
                "nonretroactive", achievementID.rawValue,
            ])
        }
        material.append(contentsOf: [
            "legacyDeepCompletionCount", String(legacyDeepCompletionCount),
            "legacyMaximumOverdriveTouchdownCount",
            String(legacyMaximumOverdriveTouchdownCount),
            "applicationPolicy", applicationPolicyIdentifier,
            "sourceStatePolicy", sourceStatePolicyIdentifier,
            "completedRunUpgradePolicy", completedRunUpgradePolicyIdentifier,
            "legacyRunFactPolicy", legacyRunFactPolicyIdentifier,
            "completedRunSourcePolicy", completedRunSourcePolicyIdentifier,
            "replayPolicy", replayPolicyIdentifier,
            "nonretroactivePolicy", nonretroactivePolicyIdentifier,
            "progressStatePolicy", progressStatePolicyIdentifier,
            "pendingQueuePolicy", pendingQueuePolicyIdentifier,
            "settlementReceiptPolicy", settlementReceiptPolicyIdentifier,
            "settlementReceiptPreservationPolicy",
            settlementReceiptPreservationPolicyIdentifier,
            "submissionPolicy", submissionPolicyIdentifier,
            "cloudScopePolicy", cloudScopePolicyIdentifier,
        ])
        return material
    }

    /// Recomputes only the six additive V3 achievements from V2 history.
    /// Deep Threat and Maximum Overdrive remain zero because V2 did not retain
    /// the exact event multiplicity and same-play conjunction they require.
    static func recomputedPercent(
        for achievementID: AchievementID,
        completedRuns: [CompletedRunRecord]
    ) -> Int? {
        let ordered = orderedNaturalRuns(completedRuns)
        switch achievementID {
        case LaunchAchievementID.perfectPocket:
            return ordered.contains {
                $0.run.statistics.meetsAccuracy(
                    percent: 100,
                    minimumAttempts: 20
                )
            } ? 100 : 0
        case LaunchAchievementID.franchisePlayer:
            return min(50, ordered.count) * 100 / 50
        case LaunchAchievementID.overcharged:
            return ordered.contains { $0.run.bonusTouchdownCount >= 3 }
                ? 100 : 0
        case LaunchAchievementID.untouchable:
            return ordered.contains { $0.run.score >= 100_000 } ? 100 : 0
        case LaunchAchievementID.deepThreat,
             LaunchAchievementID.maximumOverdrive:
            return 0
        default:
            return nil
        }
    }

    static func recomputedCompletedAt(
        for achievementID: AchievementID,
        completedRuns: [CompletedRunRecord]
    ) -> Date? {
        let ordered = orderedNaturalRuns(completedRuns)
        switch achievementID {
        case LaunchAchievementID.perfectPocket:
            return ordered.first {
                $0.run.statistics.meetsAccuracy(
                    percent: 100,
                    minimumAttempts: 20
                )
            }?.recordedAt
        case LaunchAchievementID.franchisePlayer:
            return ordered.count >= 50 ? ordered[49].recordedAt : nil
        case LaunchAchievementID.overcharged:
            return ordered.first {
                $0.run.bonusTouchdownCount >= 3
            }?.recordedAt
        case LaunchAchievementID.untouchable:
            return ordered.first { $0.run.score >= 100_000 }?.recordedAt
        case LaunchAchievementID.deepThreat,
             LaunchAchievementID.maximumOverdrive:
            return nil
        default:
            return nil
        }
    }

    private static func orderedNaturalRuns(
        _ completedRuns: [CompletedRunRecord]
    ) -> [CompletedRunRecord] {
        completedRuns
            .filter { $0.run.isNaturallyCompleted }
            .sorted {
                if $0.recordedAt != $1.recordedAt {
                    return $0.recordedAt < $1.recordedAt
                }
                return $0.run.runID.description.utf8.lexicographicallyPrecedes(
                    $1.run.runID.description.utf8
                )
            }
    }
}

import Foundation

enum LaunchAchievementID {
    static let firstRead = AchievementID("achievement.first_read.v1")
    static let paydirt = AchievementID("achievement.paydirt.v1")
    static let cashTheCharge = AchievementID("achievement.cash_the_charge.v1")
    static let fullRouteTree = AchievementID("achievement.full_route_tree.v1")
    static let dialedIn = AchievementID("achievement.dialed_in.v1")
    static let hotHand = AchievementID("achievement.hot_hand.v1")
    static let lightUpTheBoard = AchievementID("achievement.light_up_the_board.v1")
    static let centuryOfConnections = AchievementID("achievement.century_of_connections.v1")
}

enum AchievementCatalog {
    static let persistedSemanticIdentifier =
        "pocket-vector-launch-achievement-catalog-semantics-v1"

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
            detail: "Finish with at least 80% accuracy over at least 12 attempts.",
            points: 75,
            rule: .singleRunAccuracy(percent: 80, minimumAttempts: 12)
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
            detail: "Reach 25,000 points during one run.",
            points: 100,
            rule: .singleRunScore(25_000)
        ),
        AchievementDefinition(
            id: LaunchAchievementID.centuryOfConnections,
            displayName: "Century of Connections",
            detail: "Complete 100 career passes, including touchdowns.",
            points: 100,
            rule: .incrementalCareerSuccessfulPasses(100)
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
        return material
    }
}

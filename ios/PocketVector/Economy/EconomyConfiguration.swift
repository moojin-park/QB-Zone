import Foundation

enum EconomyConfiguration {
    static let currentVersion = 1

    static let minimumRewardAttempts = 3
    static let baseRunCoins: Int64 = 10
    static let scoreCoinsPerPoints = 1_000
    static let maximumScoreCoins: Int64 = 25
    static let accuracyBonusCoins: Int64 = 5
    static let accuracyBonusMinimumAttempts = 10
    static let accuracyBonusMinimumPercent = 70

    static let signingBonusVersion = 1
    static let signingBonusCoins: Int64 = 250

    static let rewardedAdRunThreshold = 5
    static let rewardedAdCoins: Int64 = 100

    static let lockedTeamPrice: Int64 = 1_500
    static let alternateJerseyPrice: Int64 = 500
    static let alternateFootballPrice: Int64 = 750

    static let coinPacks: [CoinPackDescriptor] = [
        CoinPackDescriptor(
            id: CoinPackID("pocket"),
            displayName: "Pocket",
            coins: 500,
            proposedUSPrice: 0.99
        ),
        CoinPackDescriptor(
            id: CoinPackID("team"),
            displayName: "Team",
            coins: 1_650,
            proposedUSPrice: 2.99
        ),
        CoinPackDescriptor(
            id: CoinPackID("bundle"),
            displayName: "Bundle",
            coins: 3_600,
            proposedUSPrice: 5.99
        ),
        CoinPackDescriptor(
            id: CoinPackID("vault"),
            displayName: "Vault",
            coins: 6_500,
            proposedUSPrice: 9.99
        ),
    ]
}

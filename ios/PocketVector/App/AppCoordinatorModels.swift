import Foundation

enum AppDestination: Equatable {
    case mainMenu
    case teamSelection
    case locker
    case achievements
    case achievementDetail(AchievementID)
    case coinStore
    case settings
    case gameplay(RunConfiguration)
    case runResults(RunResultsPresentation)
}

enum AppBootstrapState: Equatable {
    case loading
    case ready
    case failed(message: String)
}

enum AppBootstrapLoadResult: Equatable {
    case loaded(AppCoordinatorState)
    case failed(message: String)
}

struct AppCoordinatorState: Equatable {
    var inventory: PlayerInventory
    var selection: PlayerSelection
    var settings: PlayerSettings
    var confirmedCoins: Int64
    var pendingCoins: Int64
    var personalBest: Int
    var achievementProgress: [AchievementID: AchievementProgress]
    var rewardedAdState: RewardedAdState
    var syncStatus: ProfileSyncStatus

    static func launchDefault(catalog: LaunchCatalog = .approved) -> AppCoordinatorState {
        AppCoordinatorState(
            inventory: InventoryRules.initialInventory(catalog: catalog),
            selection: InventoryRules.initialSelection(catalog: catalog),
            settings: PlayerSettings(),
            confirmedCoins: 0,
            pendingCoins: 0,
            personalBest: 0,
            achievementProgress: Dictionary(
                uniqueKeysWithValues: AchievementCatalog.launch.map {
                    ($0.id, AchievementProgress(id: $0.id))
                }
            ),
            rewardedAdState: RewardedAdState(),
            syncStatus: .localOnly
        )
    }
}

enum AppExternalRequest: Equatable {
    case updateSelection(PlayerSelection)
    case updateSettings(PlayerSettings)
    case showLeaderboard
    case requestCatalogUnlock(CatalogItemID)
    case requestCoinPack(CoinPackID)
    case requestRewardedAd(RewardOfferID)
}

enum AppExternalRequestResult: Equatable {
    case applied(AppCoordinatorState)
    case completed
    case failed(message: String)
}

enum CompletedRunSettlementResult: Equatable {
    case settled(
        authoritativeState: AppCoordinatorState,
        results: RunResultsPresentation?
    )
    case failed(message: String)
}

enum AppLifecycleEvent: Equatable {
    case didLaunchRun(RunConfiguration)
    case didExitRun(RunID)
}

struct AppCoordinatorEnvironment {
    var loadInitialState: (@MainActor () async -> AppBootstrapLoadResult)?
    var makeRunID: @MainActor () -> RunID
    var makeSeed: @MainActor () -> UInt32
    var now: @MainActor () -> Date
    var performExternalRequest: (@MainActor (AppExternalRequest) async -> AppExternalRequestResult)?
    var observeLifecycleEvent: (@MainActor (AppLifecycleEvent) -> Void)?
    var settleCompletedRun: (
        @MainActor (CompletedRun) async -> CompletedRunSettlementResult
    )?

    init(
        loadInitialState: (@MainActor () async -> AppBootstrapLoadResult)?,
        makeRunID: @escaping @MainActor () -> RunID,
        makeSeed: @escaping @MainActor () -> UInt32,
        now: @escaping @MainActor () -> Date,
        performExternalRequest: (
            @MainActor (AppExternalRequest) async -> AppExternalRequestResult
        )?,
        observeLifecycleEvent: (@MainActor (AppLifecycleEvent) -> Void)?,
        settleCompletedRun: (
            @MainActor (CompletedRun) async -> CompletedRunSettlementResult
        )? = nil
    ) {
        self.loadInitialState = loadInitialState
        self.makeRunID = makeRunID
        self.makeSeed = makeSeed
        self.now = now
        self.performExternalRequest = performExternalRequest
        self.observeLifecycleEvent = observeLifecycleEvent
        self.settleCompletedRun = settleCompletedRun
    }

    static let disconnected = AppCoordinatorEnvironment(
        loadInitialState: nil,
        makeRunID: { RunID() },
        makeSeed: { UInt32.random(in: UInt32.min ... UInt32.max) },
        now: Date.init,
        performExternalRequest: nil,
        observeLifecycleEvent: nil,
        settleCompletedRun: nil
    )
}

struct RunResultsPresentation: Equatable {
    let completedRun: CompletedRun
    let earnedCoins: Int64
    let pendingCoins: Int64
    let personalBest: Int
    let isNewPersonalBest: Bool
    let rewardedAdOffer: RewardedAdOfferPresentation
    let achievementUpdates: [AchievementProgressUpdate]

    init(
        completedRun: CompletedRun,
        earnedCoins: Int64,
        pendingCoins: Int64,
        personalBest: Int,
        isNewPersonalBest: Bool,
        rewardedAdOffer: RewardedAdOfferPresentation,
        achievementUpdates: [AchievementProgressUpdate] = []
    ) {
        self.completedRun = completedRun
        self.earnedCoins = earnedCoins
        self.pendingCoins = pendingCoins
        self.personalBest = personalBest
        self.isNewPersonalBest = isNewPersonalBest
        self.rewardedAdOffer = rewardedAdOffer
        self.achievementUpdates = achievementUpdates
    }

    var score: Int { completedRun.score }
    var statistics: RunStatisticsSnapshot { completedRun.statistics }
}

enum RewardedAdOfferPresentation: Equatable {
    case progress(validRuns: Int, requiredRuns: Int)
    case eligible(offerID: RewardOfferID, rewardCoins: Int64, canPresent: Bool)
    case loading
    case verifying
    case rewarded(coins: Int64)
    case unavailable(message: String)
}

import Foundation

enum AppDestination: Equatable {
    case mainMenu
    case teamSelection
    case locker
    case achievements
    case achievementDetail(AchievementID)
    case coinStore
    case settings
    case tutorial(TutorialLaunchContext)
    case privacySupport
    case gameplay(RunConfiguration)
    case runResults(RunResultsPresentation)
}

enum TutorialLaunchContext: Equatable, Sendable {
    case beforeRun(RunLaunchIntent)
    case review
}

struct RunLaunchIntent: Equatable, Sendable {
    let selection: PlayerSelection
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

struct AppReleaseInformation: Equatable, Sendable {
    let appName: String
    let version: String?
    let build: String?

    static func from(bundle: Bundle) -> AppReleaseInformation {
        let displayName = nonEmptyString(
            bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        )
        let bundleName = nonEmptyString(
            bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
        )

        return AppReleaseInformation(
            appName: displayName ?? bundleName ?? "Pocket Vector",
            version: nonEmptyString(
                bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ),
            build: nonEmptyString(
                bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            )
        )
    }

    var versionAndBuildText: String {
        switch (version, build) {
        case let (.some(version), .some(build)):
            return "Version \(version) (\(build))"
        case let (.some(version), .none):
            return "Version \(version)"
        case let (.none, .some(build)):
            return "Build \(build)"
        case (.none, .none):
            return "Version and build unavailable"
        }
    }

    private static func nonEmptyString(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

struct AppServiceAvailability: Equatable, Sendable {
    var rewardedAdsAreConfigured: Bool
    var purchasesAreConfigured: Bool
    var gameCenterIsConfigured: Bool
    var iCloudSyncIsConfigured: Bool

    static let unconfigured = AppServiceAvailability(
        rewardedAdsAreConfigured: false,
        purchasesAreConfigured: false,
        gameCenterIsConfigured: false,
        iCloudSyncIsConfigured: false
    )
}

enum PrivacySupportConfigurationIssue: String, CaseIterable, Equatable, Identifiable, Sendable {
    case privacyPolicyURLMissing
    case privacyPolicyURLInvalid
    case supportURLMissing
    case supportURLInvalid
    case supportEmailMissing
    case supportEmailInvalid

    var id: String { rawValue }

    var message: String {
        switch self {
        case .privacyPolicyURLMissing:
            return "Privacy policy URL is not configured."
        case .privacyPolicyURLInvalid:
            return "Privacy policy URL must be a valid HTTPS address."
        case .supportURLMissing:
            return "Support URL is not configured."
        case .supportURLInvalid:
            return "Support URL must be a valid HTTPS address."
        case .supportEmailMissing:
            return "Support email is not configured."
        case .supportEmailInvalid:
            return "Support email is not valid."
        }
    }
}

struct PrivacySupportConfiguration: Equatable, Sendable {
    static let privacyPolicyInfoKey = "PocketVectorPrivacyPolicyURL"
    static let supportURLInfoKey = "PocketVectorSupportURL"
    static let supportEmailInfoKey = "PocketVectorSupportEmail"

    let privacyPolicyURL: URL?
    let supportURL: URL?
    let supportEmail: String?
    let appInformation: AppReleaseInformation
    let services: AppServiceAvailability
    let issues: [PrivacySupportConfigurationIssue]

    init(
        privacyPolicyURLString: String?,
        supportURLString: String?,
        supportEmail: String?,
        appInformation: AppReleaseInformation,
        services: AppServiceAvailability = .unconfigured
    ) {
        let privacyPolicyValidation = Self.validateHTTPSURL(privacyPolicyURLString)
        let supportURLValidation = Self.validateHTTPSURL(supportURLString)
        let emailValidation = Self.validateEmail(supportEmail)

        privacyPolicyURL = privacyPolicyValidation.value
        supportURL = supportURLValidation.value
        self.supportEmail = emailValidation.value
        self.appInformation = appInformation
        self.services = services

        var issues: [PrivacySupportConfigurationIssue] = []
        switch privacyPolicyValidation.failure {
        case .missing: issues.append(.privacyPolicyURLMissing)
        case .invalid: issues.append(.privacyPolicyURLInvalid)
        case nil: break
        }
        switch supportURLValidation.failure {
        case .missing: issues.append(.supportURLMissing)
        case .invalid: issues.append(.supportURLInvalid)
        case nil: break
        }
        switch emailValidation.failure {
        case .missing: issues.append(.supportEmailMissing)
        case .invalid: issues.append(.supportEmailInvalid)
        case nil: break
        }
        self.issues = issues
    }

    static func from(
        bundle: Bundle,
        services: AppServiceAvailability = .unconfigured
    ) -> PrivacySupportConfiguration {
        PrivacySupportConfiguration(
            privacyPolicyURLString: bundle.object(
                forInfoDictionaryKey: privacyPolicyInfoKey
            ) as? String,
            supportURLString: bundle.object(
                forInfoDictionaryKey: supportURLInfoKey
            ) as? String,
            supportEmail: bundle.object(
                forInfoDictionaryKey: supportEmailInfoKey
            ) as? String,
            appInformation: .from(bundle: bundle),
            services: services
        )
    }

    var isReleaseContactConfigurationComplete: Bool {
        issues.isEmpty
    }

    var supportEmailURL: URL? {
        guard let supportEmail else { return nil }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = supportEmail
        components.queryItems = [
            URLQueryItem(
                name: "subject",
                value: "\(appInformation.appName) Support"
            )
        ]
        return components.url
    }

    private enum ValidationFailure {
        case missing
        case invalid
    }

    private static func validateHTTPSURL(
        _ rawValue: String?
    ) -> (value: URL?, failure: ValidationFailure?) {
        guard let trimmed = normalized(rawValue) else {
            return (nil, .missing)
        }
        guard let components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "https",
              let host = components.host,
              host.contains("."),
              !host.hasPrefix("."),
              !host.hasSuffix("."),
              !host.contains(".."),
              components.user == nil,
              components.password == nil,
              let url = components.url else {
            return (nil, .invalid)
        }
        return (url, nil)
    }

    private static func validateEmail(
        _ rawValue: String?
    ) -> (value: String?, failure: ValidationFailure?) {
        guard let trimmed = normalized(rawValue) else {
            return (nil, .missing)
        }
        guard !trimmed.contains(where: { $0.isWhitespace }),
              trimmed.filter({ $0 == "@" }).count == 1 else {
            return (nil, .invalid)
        }

        let parts = trimmed.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let localPart = parts.first,
              !localPart.isEmpty,
              !localPart.hasPrefix("."),
              !localPart.hasSuffix("."),
              !localPart.contains(".."),
              let domain = parts.last,
              domain.contains("."),
              !domain.hasPrefix("."),
              !domain.hasSuffix("."),
              !domain.contains("..") else {
            return (nil, .invalid)
        }
        return (trimmed, nil)
    }

    private static func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
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
    var privacySupportConfiguration: PrivacySupportConfiguration

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
        )? = nil,
        privacySupportConfiguration: PrivacySupportConfiguration = .from(bundle: .main)
    ) {
        self.loadInitialState = loadInitialState
        self.makeRunID = makeRunID
        self.makeSeed = makeSeed
        self.now = now
        self.performExternalRequest = performExternalRequest
        self.observeLifecycleEvent = observeLifecycleEvent
        self.settleCompletedRun = settleCompletedRun
        self.privacySupportConfiguration = privacySupportConfiguration
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

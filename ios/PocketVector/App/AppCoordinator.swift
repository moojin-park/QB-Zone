import Foundation
import Observation

@MainActor
@Observable
final class AppCoordinator {
    let catalog: LaunchCatalog
    private(set) var navigationPath: [AppDestination]
    private(set) var state: AppCoordinatorState
    private(set) var bootstrapState: AppBootstrapState
    private(set) var noticeMessage: String?
    private(set) var pendingRequest: AppExternalRequest?
    private(set) var pendingCompletedRun: CompletedRun?
    private(set) var isRunSettlementInFlight: Bool
    private(set) var settlementErrorMessage: String?

    private let environment: AppCoordinatorEnvironment
    private let matchupGenerator: MatchupGenerator
    private var bootstrapIsRunning: Bool

    init(
        catalog: LaunchCatalog = .approved,
        state: AppCoordinatorState? = nil,
        environment: AppCoordinatorEnvironment = .disconnected
    ) {
        self.catalog = catalog
        self.state = state ?? .launchDefault(catalog: catalog)
        self.environment = environment
        matchupGenerator = MatchupGenerator(catalog: catalog)
        navigationPath = [.mainMenu]
        bootstrapState = .loading
        pendingRequest = nil
        pendingCompletedRun = nil
        isRunSettlementInFlight = false
        settlementErrorMessage = nil
        bootstrapIsRunning = false
    }

    var currentDestination: AppDestination {
        navigationPath.last ?? .mainMenu
    }

    var selectedTeam: TeamDescriptor? {
        catalog.team(id: state.selection.selectedTeamID)
    }

    var canGoBack: Bool {
        navigationPath.count > 1
    }

    var isRequestInFlight: Bool {
        pendingRequest != nil || isRunSettlementInFlight
    }

    func bootstrap() async {
        guard bootstrapState != .ready, !bootstrapIsRunning else { return }
        bootstrapIsRunning = true
        defer { bootstrapIsRunning = false }
        bootstrapState = .loading

        guard let loadInitialState = environment.loadInitialState else {
            // The disconnected shell has no durable repository yet. Keeping
            // this promotion explicit prevents a flash of mutable placeholder
            // data while the production adapter is being connected.
            bootstrapState = .ready
            return
        }

        switch await loadInitialState() {
        case let .loaded(initialState):
            state = initialState
            bootstrapState = .ready
        case let .failed(message):
            bootstrapState = .failed(message: message)
        }
    }

    func navigate(to destination: AppDestination) {
        guard bootstrapState == .ready else { return }
        guard currentDestination != destination else { return }
        navigationPath.append(destination)
    }

    func goBack() {
        guard navigationPath.count > 1 else { return }
        navigationPath.removeLast()
    }

    func returnToMainMenu() {
        navigationPath = [.mainMenu]
    }

    func dismissNotice() {
        noticeMessage = nil
    }

    func showTeamSelection() {
        navigate(to: .teamSelection)
    }

    func showLocker() {
        navigate(to: .locker)
    }

    func showAchievements() {
        navigate(to: .achievements)
    }

    func showAchievement(_ achievementID: AchievementID) {
        guard AchievementCatalog.launch.contains(where: { $0.id == achievementID }) else {
            return
        }
        navigate(to: .achievementDetail(achievementID))
    }

    func showCoinStore() {
        navigate(to: .coinStore)
    }

    func showSettings() {
        navigate(to: .settings)
    }

    func requestLeaderboard() async {
        guard bootstrapState == .ready else { return }
        guard environment.performExternalRequest != nil else {
            noticeMessage = "Game Center will be available after its account service is connected."
            return
        }
        await performPlatformRequest(.showLeaderboard)
    }

    func requestUnlock(_ itemID: CatalogItemID) async {
        guard bootstrapState == .ready else { return }
        guard catalog.item(id: itemID) != nil else { return }
        guard environment.performExternalRequest != nil else {
            noticeMessage = "Unlocks are shown for planning, but cloud-backed spending is not connected yet."
            return
        }
        await performPlatformRequest(.requestCatalogUnlock(itemID))
    }

    func requestCoinPack(_ packID: CoinPackID) async {
        guard bootstrapState == .ready else { return }
        guard EconomyConfiguration.coinPacks.contains(where: { $0.id == packID }) else {
            return
        }
        guard environment.performExternalRequest != nil else {
            noticeMessage = "Purchases are not enabled in this build."
            return
        }
        await performPlatformRequest(.requestCoinPack(packID))
    }

    func requestRewardedAd(_ offerID: RewardOfferID) async {
        guard bootstrapState == .ready else { return }
        guard environment.performExternalRequest != nil else {
            noticeMessage = "Rewarded ads are not enabled in this build."
            return
        }
        await performPlatformRequest(.requestRewardedAd(offerID))
    }

    func selectTeam(_ teamID: TeamID) async {
        guard bootstrapState == .ready else { return }
        guard let team = catalog.team(id: teamID),
              state.inventory.ownedTeamIDs.contains(teamID) else {
            return
        }

        var candidate = state
        candidate.selection.selectedTeamID = teamID
        let rememberedJerseyID = candidate.selection.selectedJerseyByTeam[teamID]
        if rememberedJerseyID == nil
            || !candidate.inventory.ownedJerseyIDs.contains(rememberedJerseyID!) {
            candidate.selection.selectedJerseyByTeam[teamID] = team.primaryJersey.id
        }
        await performStateChange(
            candidate,
            request: .updateSelection(candidate.selection)
        )
    }

    func equipJersey(_ jerseyID: JerseyID, for teamID: TeamID) async {
        guard bootstrapState == .ready else { return }
        guard let jersey = catalog.jersey(id: jerseyID),
              jersey.teamID == teamID,
              state.inventory.ownedTeamIDs.contains(teamID),
              state.inventory.ownedJerseyIDs.contains(jerseyID) else {
            return
        }

        var candidate = state
        candidate.selection.selectedTeamID = teamID
        candidate.selection.selectedJerseyByTeam[teamID] = jerseyID
        await performStateChange(
            candidate,
            request: .updateSelection(candidate.selection)
        )
    }

    func equipFootball(_ footballID: FootballID) async {
        guard bootstrapState == .ready else { return }
        guard catalog.football(id: footballID) != nil,
              state.inventory.ownedFootballIDs.contains(footballID) else {
            return
        }

        var candidate = state
        candidate.selection.selectedFootballID = footballID
        await performStateChange(
            candidate,
            request: .updateSelection(candidate.selection)
        )
    }

    func setMusicVolume(_ volume: Double) async {
        guard bootstrapState == .ready else { return }
        await updateSettings(
            PlayerSettings(
                musicVolume: volume,
                sfxVolume: state.settings.sfxVolume,
                isMuted: state.settings.isMuted,
                reducedMotion: state.settings.reducedMotion,
                tutorialCompleted: state.settings.tutorialCompleted
            )
        )
    }

    func setSFXVolume(_ volume: Double) async {
        guard bootstrapState == .ready else { return }
        await updateSettings(
            PlayerSettings(
                musicVolume: state.settings.musicVolume,
                sfxVolume: volume,
                isMuted: state.settings.isMuted,
                reducedMotion: state.settings.reducedMotion,
                tutorialCompleted: state.settings.tutorialCompleted
            )
        )
    }

    func setMuted(_ isMuted: Bool) async {
        guard bootstrapState == .ready else { return }
        await updateSettings(
            PlayerSettings(
                musicVolume: state.settings.musicVolume,
                sfxVolume: state.settings.sfxVolume,
                isMuted: isMuted,
                reducedMotion: state.settings.reducedMotion,
                tutorialCompleted: state.settings.tutorialCompleted
            )
        )
    }

    func setReducedMotion(_ reducedMotion: Bool) async {
        guard bootstrapState == .ready else { return }
        await updateSettings(
            PlayerSettings(
                musicVolume: state.settings.musicVolume,
                sfxVolume: state.settings.sfxVolume,
                isMuted: state.settings.isMuted,
                reducedMotion: reducedMotion,
                tutorialCompleted: state.settings.tutorialCompleted
            )
        )
    }

    func setTutorialEnabled(_ isEnabled: Bool) async {
        guard bootstrapState == .ready else { return }
        await updateSettings(
            PlayerSettings(
                musicVolume: state.settings.musicVolume,
                sfxVolume: state.settings.sfxVolume,
                isMuted: state.settings.isMuted,
                reducedMotion: state.settings.reducedMotion,
                tutorialCompleted: !isEnabled
            )
        )
    }

    @discardableResult
    func startRun() -> Bool {
        guard bootstrapState == .ready else { return false }
        guard pendingCompletedRun == nil, !isRunSettlementInFlight else {
            noticeMessage = "Finish saving the current run before starting another."
            return false
        }
        do {
            let configuration = try matchupGenerator.makeRunConfiguration(
                selection: state.selection,
                inventory: state.inventory,
                runID: environment.makeRunID(),
                seed: environment.makeSeed(),
                startedAt: environment.now()
            )
            navigate(to: .gameplay(configuration))
            environment.observeLifecycleEvent?(.didLaunchRun(configuration))
            return true
        } catch {
            noticeMessage = "Choose an owned team, jersey, and football before starting a run."
            return false
        }
    }

    func handleCompletedRun(_ completedRun: CompletedRun) async {
        guard case let .gameplay(configuration) = currentDestination,
              configuration.runID == completedRun.runID,
              configuration == completedRun.configuration else {
            return
        }

        guard completedRun.finishReason != .debugPreview else {
            // Preview scenes are not production runs and never cross the
            // settlement boundary.
            returnToMainMenu()
            return
        }

        if let pendingCompletedRun {
            guard pendingCompletedRun == completedRun else { return }
        } else {
            pendingCompletedRun = completedRun
        }

        await settlePendingCompletedRun()
    }

    func retryCompletedRunSettlement() async {
        guard pendingCompletedRun != nil else { return }
        await settlePendingCompletedRun()
    }

    func showRunResults(_ results: RunResultsPresentation) {
        if case .gameplay = currentDestination {
            navigationPath.removeLast()
        }
        navigationPath.append(.runResults(results))
    }

    private func settlePendingCompletedRun() async {
        guard !isRunSettlementInFlight,
              let completedRun = pendingCompletedRun else {
            return
        }

        guard let settleCompletedRun = environment.settleCompletedRun else {
            exposeSettlementFailure(
                "Run saving is not connected in this build. Your results have not been awarded."
            )
            return
        }

        isRunSettlementInFlight = true
        settlementErrorMessage = nil
        let result = await settleCompletedRun(completedRun)
        isRunSettlementInFlight = false

        guard pendingCompletedRun == completedRun else { return }

        switch result {
        case let .failed(message):
            exposeSettlementFailure(message)

        case let .settled(authoritativeState, results):
            state = authoritativeState

            switch completedRun.finishReason {
            case .timerExpired:
                guard completedRun.isNaturallyCompleted,
                      let results,
                      results.completedRun == completedRun else {
                    exposeSettlementFailure(
                        "The run was saved, but verified results were not returned. Retry to load them."
                    )
                    return
                }

                pendingCompletedRun = nil
                settlementErrorMessage = nil
                noticeMessage = nil
                showRunResults(results)

            case .abandoned:
                pendingCompletedRun = nil
                settlementErrorMessage = nil
                noticeMessage = nil
                environment.observeLifecycleEvent?(.didExitRun(completedRun.runID))
                returnToMainMenu()

            case .debugPreview:
                // Guarded before invoking the production seam.
                break
            }
        }
    }

    private func exposeSettlementFailure(_ message: String) {
        settlementErrorMessage = message
    }

    func replayAfterResults() {
        guard case .runResults = currentDestination else { return }
        navigationPath.removeLast()
        _ = startRun()
    }

    private func updateSettings(_ settings: PlayerSettings) async {
        guard state.settings != settings else { return }
        var candidate = state
        candidate.settings = settings
        await performStateChange(candidate, request: .updateSettings(settings))
    }

    private func performStateChange(
        _ candidate: AppCoordinatorState,
        request: AppExternalRequest
    ) async {
        guard pendingRequest == nil else { return }
        guard let performRequest = environment.performExternalRequest else {
            noticeMessage = "Saved player changes are unavailable in this presentation build."
            return
        }

        let previous = state
        state = candidate
        pendingRequest = request
        let result = await performRequest(request)
        pendingRequest = nil

        switch result {
        case let .applied(authoritativeState):
            state = authoritativeState
        case .completed:
            state = previous
            noticeMessage = "The profile service did not return an updated player state."
        case let .failed(message):
            state = previous
            noticeMessage = message
        }
    }

    private func performPlatformRequest(_ request: AppExternalRequest) async {
        guard pendingRequest == nil,
              let performRequest = environment.performExternalRequest else {
            return
        }

        pendingRequest = request
        let result = await performRequest(request)
        pendingRequest = nil

        switch result {
        case let .applied(authoritativeState):
            state = authoritativeState
        case .completed:
            break
        case let .failed(message):
            noticeMessage = message
        }
    }
}

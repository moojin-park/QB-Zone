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
    private(set) var authoritativeSnapshot: AuthoritativeAppStateSnapshot?
    private(set) var stateUpdateConsumerIsRunning: Bool
    let privacySupportConfiguration: PrivacySupportConfiguration

    private let environment: AppCoordinatorEnvironment
    private let matchupGenerator: MatchupGenerator
    private var bootstrapIsRunning: Bool
    private var visibleResultsTelemetry: VisibleResultsTelemetry?

    init(
        catalog: LaunchCatalog = .approved,
        state: AppCoordinatorState? = nil,
        environment: AppCoordinatorEnvironment = .disconnected
    ) {
        self.catalog = catalog
        self.state = state ?? .launchDefault(catalog: catalog)
        self.environment = environment
        privacySupportConfiguration = environment.privacySupportConfiguration
        matchupGenerator = MatchupGenerator(catalog: catalog)
        navigationPath = [.mainMenu]
        bootstrapState = .loading
        pendingRequest = nil
        pendingCompletedRun = nil
        isRunSettlementInFlight = false
        settlementErrorMessage = nil
        authoritativeSnapshot = nil
        stateUpdateConsumerIsRunning = false
        bootstrapIsRunning = false
        visibleResultsTelemetry = nil
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

        let result = await loadInitialState()
        guard !Task.isCancelled else { return }

        switch result {
        case let .loaded(initialSnapshot):
            authoritativeSnapshot = initialSnapshot
            state = initialSnapshot.state
            bootstrapState = .ready
        case let .failed(message):
            bootstrapState = .failed(message: message)
        }
    }

    /// Bootstraps the durable profile and then consumes complete background
    /// projections for the same immutable profile session until cancelled.
    func run() async {
        guard !Task.isCancelled else { return }
        await bootstrap()
        guard !Task.isCancelled,
              bootstrapState == .ready,
              let makeUpdates = environment.makeAuthoritativeStateUpdates,
              !stateUpdateConsumerIsRunning else {
            return
        }
        stateUpdateConsumerIsRunning = true
        defer { stateUpdateConsumerIsRunning = false }
        let updates = makeUpdates()

        for await update in updates {
            guard !Task.isCancelled else { return }
            _ = applyAuthoritativeUpdate(update)
        }
    }

    /// Applies a complete profile projection without changing navigation. In
    /// particular, a gameplay destination keeps its immutable configuration
    /// even if inventory or selection changes in the background.
    @discardableResult
    func applyAuthoritativeUpdate(
        _ update: AuthoritativeAppStateSnapshot
    ) -> AuthoritativeStateApplyResult {
        guard let accepted = authoritativeSnapshot else {
            return .rejected(.sessionNotEstablished)
        }
        guard update.session == accepted.session else {
            return .rejected(.sessionMismatch)
        }
        guard update.playerRevision >= accepted.playerRevision,
              update.economyRevision >= accepted.economyRevision else {
            return .rejected(.staleRevision)
        }

        if update.playerRevision == accepted.playerRevision,
           update.state.authoritativePlayerPartition
            != accepted.state.authoritativePlayerPartition {
            return .rejected(.revisionCollision)
        }
        if update.economyRevision == accepted.economyRevision,
           update.state.authoritativeEconomyPartition
            != accepted.state.authoritativeEconomyPartition {
            return .rejected(.revisionCollision)
        }

        if update.playerRevision == accepted.playerRevision,
           update.economyRevision == accepted.economyRevision {
            guard update.state == accepted.state else {
                return .rejected(.revisionCollision)
            }
            state = accepted.state
            return .duplicateIgnored
        }

        authoritativeSnapshot = update
        state = update.state
        return .applied
    }

    func navigate(to destination: AppDestination) {
        guard bootstrapState == .ready else { return }
        guard currentDestination != destination else { return }
        if case .runResults = currentDestination {
            visibleResultsTelemetry = nil
        }
        navigationPath.append(destination)
        if case .coinStore = destination {
            recordTelemetry(.storeOpened, at: environment.now())
        }
    }

    func goBack() {
        guard navigationPath.count > 1 else { return }
        if case .runResults = currentDestination {
            visibleResultsTelemetry = nil
        }
        navigationPath.removeLast()
    }

    func returnToMainMenu() {
        visibleResultsTelemetry = nil
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

    func showTutorialReview() {
        navigate(to: .tutorial(.review))
    }

    func showPrivacySupport() {
        navigate(to: .privacySupport)
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

    func cancelTutorial() {
        guard pendingRequest == nil,
              case .tutorial = currentDestination else {
            return
        }
        goBack()
    }

    func completeTutorial() async {
        guard bootstrapState == .ready,
              pendingRequest == nil,
              case let .tutorial(context) = currentDestination else {
            return
        }

        switch context {
        case .review:
            goBack()

        case let .beforeRun(intent):
            if !state.settings.tutorialCompleted {
                let completedSettings = PlayerSettings(
                    musicVolume: state.settings.musicVolume,
                    sfxVolume: state.settings.sfxVolume,
                    isMuted: state.settings.isMuted,
                    reducedMotion: state.settings.reducedMotion,
                    tutorialCompleted: true
                )
                guard await updateSettings(completedSettings),
                      state.settings.tutorialCompleted else {
                    return
                }
            }

            guard currentDestination == .tutorial(context) else { return }
            _ = launchRun(intent: intent, replacingTutorial: true)
        }
    }

    @discardableResult
    func startRun() -> Bool {
        guard bootstrapState == .ready else { return false }
        guard pendingCompletedRun == nil, !isRunSettlementInFlight else {
            noticeMessage = "Finish saving the current run before starting another."
            return false
        }

        let intent = RunLaunchIntent(selection: state.selection)
        guard isValidRunIntent(intent) else {
            noticeMessage = "Choose an owned team, jersey, and football before starting a run."
            return false
        }

        if !state.settings.tutorialCompleted {
            navigate(to: .tutorial(.beforeRun(intent)))
            return true
        }

        return launchRun(intent: intent, replacingTutorial: false)
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
        visibleResultsTelemetry = nil
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

        case let .settled(authoritativeSnapshot, results):
            let applyResult = applyAuthoritativeUpdate(authoritativeSnapshot)
            guard applyResult.acceptsRepositorySuccess else {
                exposeSettlementFailure(
                    "The saved profile response failed an integrity check. Retry to load verified results."
                )
                return
            }

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
                showVerifiedRunResults(results)

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
        guard case let .runResults(results) = currentDestination else { return }
        let replayCorrelationID: ReplayCorrelationID?
        if visibleResultsTelemetry?.results == results {
            replayCorrelationID = visibleResultsTelemetry?.correlationID
        } else {
            replayCorrelationID = nil
        }
        visibleResultsTelemetry = nil
        navigationPath.removeLast()
        guard startRun(),
              case let .gameplay(configuration) = currentDestination,
              let replayCorrelationID else {
            return
        }
        recordTelemetry(
            .replayStarted(correlationID: replayCorrelationID),
            at: configuration.startedAt
        )
    }

    private func isValidRunIntent(_ intent: RunLaunchIntent) -> Bool {
        do {
            try InventoryRules.validate(
                selection: intent.selection,
                inventory: state.inventory,
                catalog: catalog
            )
        } catch {
            return false
        }

        guard let jerseyID = intent.selection.selectedJerseyID,
              catalog.jersey(id: jerseyID) != nil else {
            return false
        }
        return catalog.teams.contains { $0.id != intent.selection.selectedTeamID }
    }

    @discardableResult
    private func launchRun(
        intent: RunLaunchIntent,
        replacingTutorial: Bool
    ) -> Bool {
        guard state.selection == intent.selection,
              isValidRunIntent(intent) else {
            noticeMessage = "Your selected team or equipment changed while the tutorial was open. Review your locker before starting a run."
            return false
        }

        do {
            let configuration = try matchupGenerator.makeRunConfiguration(
                selection: intent.selection,
                inventory: state.inventory,
                runID: environment.makeRunID(),
                seed: environment.makeSeed(),
                startedAt: environment.now()
            )
            if replacingTutorial, case .tutorial = currentDestination {
                navigationPath.removeLast()
            }
            navigate(to: .gameplay(configuration))
            environment.observeLifecycleEvent?(.didLaunchRun(configuration))
            recordTelemetry(.runStarted, at: configuration.startedAt)
            return true
        } catch {
            noticeMessage = "Choose an owned team, jersey, and football before starting a run."
            return false
        }
    }

    @discardableResult
    private func updateSettings(_ settings: PlayerSettings) async -> Bool {
        guard state.settings != settings else { return true }
        var candidate = state
        candidate.settings = settings
        return await performStateChange(
            candidate,
            request: .updateSettings(settings)
        )
    }

    @discardableResult
    private func performStateChange(
        _ candidate: AppCoordinatorState,
        request: AppExternalRequest
    ) async -> Bool {
        guard pendingRequest == nil else { return false }
        guard let performRequest = environment.performExternalRequest else {
            noticeMessage = "Saved player changes are unavailable in this presentation build."
            return false
        }

        let previous = state
        state = candidate
        pendingRequest = request
        let result = await performRequest(request)
        pendingRequest = nil

        switch result {
        case let .applied(authoritativeSnapshot):
            let applyResult = applyAuthoritativeUpdate(authoritativeSnapshot)
            guard applyResult.acceptsRepositorySuccess else {
                state = self.authoritativeSnapshot?.state ?? previous
                noticeMessage = "The saved profile response failed an integrity check. No unverified changes were applied."
                return false
            }
            return true
        case .completed:
            state = authoritativeSnapshot?.state ?? previous
            noticeMessage = "The profile service did not return an updated player state."
            return false
        case let .failed(message):
            state = authoritativeSnapshot?.state ?? previous
            noticeMessage = message
            return false
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
        case let .applied(authoritativeSnapshot):
            let applyResult = applyAuthoritativeUpdate(authoritativeSnapshot)
            if !applyResult.acceptsRepositorySuccess {
                noticeMessage = "The profile service returned an invalid account state."
            }
        case .completed:
            break
        case let .failed(message):
            noticeMessage = message
        }
    }

    private func showVerifiedRunResults(_ results: RunResultsPresentation) {
        showRunResults(results)
        guard currentDestination == .runResults(results) else { return }

        let correlationID = environment.makeReplayCorrelationID()
        visibleResultsTelemetry = VisibleResultsTelemetry(
            results: results,
            correlationID: correlationID
        )
        recordTelemetry(
            TelemetryBandClassifier.runResultsPayload(
                correlationID: correlationID,
                score: results.score,
                displayedAccuracyPercent: results.statistics.displayedAccuracyPercent,
                attempts: results.statistics.attempts
            ),
            at: environment.now()
        )
    }

    private func recordTelemetry(_ payload: TelemetryPayload, at date: Date) {
        environment.diagnosticsSink?.record(payload, at: date)
    }
}

private struct VisibleResultsTelemetry {
    let results: RunResultsPresentation
    let correlationID: ReplayCorrelationID
}

private extension AuthoritativeStateApplyResult {
    var acceptsRepositorySuccess: Bool {
        switch self {
        case .applied, .duplicateIgnored:
            true
        case .rejected:
            false
        }
    }
}

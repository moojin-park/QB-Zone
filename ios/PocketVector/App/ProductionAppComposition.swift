import CryptoKit
import Foundation

enum ProductionProfileRepositoryRouteAuthority: Equatable, Sendable {
    case local(
        accountIdentity: PlayerAccountIdentity,
        sessionNonce: UUID
    )
    case verifiedPrivateCloud(ProductionVerifiedAccountClaim)
}

struct ProductionProfileRepositoryRoute: Sendable {
    let repository: LocalPlayerProfileRepository
    let authority: ProductionProfileRepositoryRouteAuthority

    func authorizes(_ snapshot: LocalPlayerProfileSnapshot) -> Bool {
        switch authority {
        case let .local(accountIdentity, sessionNonce):
            snapshot.session.accountIdentity == accountIdentity
                && snapshot.session.nonce == sessionNonce
        case let .verifiedPrivateCloud(claim):
            repository === claim.installedRepository
                && snapshot.session == claim.snapshot.session
                && snapshot.player.profileID == claim.snapshot.player.profileID
                && snapshot.player.revision >= claim.snapshot.player.revision
                && snapshot.economyRevision >= claim.snapshot.economyRevision
        }
    }
}

/// A bounded proof that one App result was projected from the exact repository
/// installed by a durable private-cloud claim. Its initializer is sealed; an
/// arbitrary external-response closure cannot mint session-replacement power.
struct ProductionVerifiedSessionAdoption: Equatable, Sendable {
    private let claim: ProductionVerifiedAccountClaim

    private init(claim: ProductionVerifiedAccountClaim) {
        self.claim = claim
    }

    fileprivate static func mint(
        route: ProductionProfileRepositoryRoute,
        snapshot: LocalPlayerProfileSnapshot
    ) -> ProductionVerifiedSessionAdoption? {
        guard case let .verifiedPrivateCloud(claim) = route.authority,
              route.authorizes(snapshot) else {
            return nil
        }
        return ProductionVerifiedSessionAdoption(claim: claim)
    }

    func authorizes(_ snapshot: AuthoritativeAppStateSnapshot) -> Bool {
        snapshot.session == claim.snapshot.session
            && snapshot.playerRevision >= claim.snapshot.player.revision
            && snapshot.economyRevision >= claim.snapshot.economyRevision
    }
}

private struct ProductionRepositoryRefresh {
    let snapshot: AuthoritativeAppStateSnapshot
    let sessionAdoption: ProductionVerifiedSessionAdoption?
}

protocol ProductionProfileRepositoryRouting: Sendable {
    func currentRoute() async throws -> ProductionProfileRepositoryRoute
}

protocol ProductionLaunchRepositoryRouteResolving: Sendable {
    func resolveLaunchRoute() async throws -> ProductionProfileRepositoryRoute?
}

final class ProductionLaunchCloudAccountDiscovery: @unchecked Sendable {
    private let lock = NSLock()
    private var discovery: (any ProductionCloudAccountDiscovering)?

    func install(_ discovery: any ProductionCloudAccountDiscovering) {
        lock.withLock { self.discovery = discovery }
    }

    func accountState() async -> CloudAccountState {
        let current = lock.withLock { discovery }
        return await current?.accountState() ?? .unknown
    }
}

/// Reopens a committed local-to-private-cloud association before bootstrap can
/// touch the preserved local source. A present but invalid marker fails closed;
/// it is never rewritten as permission to fall back to the local repository.
struct ProductionCommittedAssociationRouteResolver:
    ProductionLaunchRepositoryRouteResolving
{
    let associationStore: ProfileInitialAssociationStoreV1
    let sourceRepository: LocalPlayerProfileRepository
    let sourceDirectoryURL: URL
    let deviceID: String
    let sessionNonce: UUID
    let catalog: LaunchCatalog
    let accountDiscovery: ProductionLaunchCloudAccountDiscovery
    let now: @Sendable () -> Date

    static func validateProviderAccount(
        _ state: CloudAccountState,
        committedAccountID: CloudAccountID
    ) throws {
        if case let .available(accountID) = state,
           accountID != committedAccountID {
            throw ProductionAppCompositionError.authoritativeSessionMismatch
        }
    }

    func resolveLaunchRoute() async throws -> ProductionProfileRepositoryRoute? {
        guard let association = try await associationStore.committedAssociation(
            sourceDirectoryURL: sourceDirectoryURL
        ) else {
            return nil
        }
        try Self.validateProviderAccount(
            await accountDiscovery.accountState(),
            committedAccountID: association.cloudAccountID
        )
        // Unknown/signed-out/restricted keeps the committed target as the only
        // durable offline route. Commerce separately remains fail-closed.

        let targetRepository = LocalPlayerProfileRepository(
            directoryURL: association.targetDirectoryURL,
            deviceID: deviceID,
            accountIdentity: association.targetPlayerAccountIdentity,
            sessionNonce: sessionNonce,
            catalog: catalog,
            economyMutationPolicy: .requireDurablePrivateCloud
        )
        let result = try await associationStore.reopenCommittedAssociation(
            association,
            expectedAccountID: association.cloudAccountID,
            sourceRepository: sourceRepository,
            targetRepository: targetRepository,
            at: now()
        )
        let bindings = CloudAccountDerivedBindings.derive(
            from: association.cloudAccountID
        )
        let claim = try await ProductionVerifiedAccountClaim(
            cloudAccountID: association.cloudAccountID,
            derivedBindings: bindings,
            installedRepository: targetRepository
        )
        guard result.cloudAccountID == claim.cloudAccountID,
              result.targetSnapshot == claim.snapshot else {
            throw ProductionAppCompositionError.authoritativeSessionMismatch
        }
        return ProductionProfileRepositoryRoute(
            repository: targetRepository,
            authority: .verifiedPrivateCloud(claim)
        )
    }
}

/// App-owned indirection for the repository that owns the active account
/// session. A launch association lookup can install a verified route before
/// bootstrap, while first claim can atomically replace the local source route.
actor ProductionProfileRepositoryRouter: ProductionProfileRepositoryRouting {
    private var route: ProductionProfileRepositoryRoute
    private let launchResolver:
        (any ProductionLaunchRepositoryRouteResolving)?
    private var launchRouteWasResolved: Bool
    private var launchResolutionTask:
        Task<ProductionProfileRepositoryRoute?, Error>?

    init(
        route: ProductionProfileRepositoryRoute,
        launchResolver:
            (any ProductionLaunchRepositoryRouteResolving)? = nil
    ) {
        self.route = route
        self.launchResolver = launchResolver
        launchRouteWasResolved = launchResolver == nil
        launchResolutionTask = nil
    }

    func currentRoute() async throws -> ProductionProfileRepositoryRoute {
        guard !launchRouteWasResolved else { return route }
        if launchResolutionTask == nil, let launchResolver {
            launchResolutionTask = Task {
                try await launchResolver.resolveLaunchRoute()
            }
        }
        let resolutionTask = launchResolutionTask
        do {
            let resolved = try await resolutionTask?.value
            guard !launchRouteWasResolved else { return route }
            if let resolved {
                route = resolved
            }
            launchRouteWasResolved = true
            launchResolutionTask = nil
        } catch {
            if !launchRouteWasResolved {
                launchResolutionTask = nil
            }
            throw error
        }
        return route
    }

    /// The claim service calls this only after durable association/adoption and
    /// exact target-repository reload. The old route becomes unreachable before
    /// the method returns.
    func adoptVerifiedPrivateCloud(
        repository: LocalPlayerProfileRepository,
        claim: ProductionVerifiedAccountClaim
    ) async throws {
        guard repository === claim.installedRepository else {
            throw ProductionAppCompositionError.authoritativeSessionMismatch
        }
        let candidate = ProductionProfileRepositoryRoute(
            repository: repository,
            authority: .verifiedPrivateCloud(claim)
        )
        let snapshot = try await repository.snapshot()
        guard candidate.authorizes(snapshot) else {
            throw ProductionAppCompositionError.authoritativeSessionMismatch
        }
        route = candidate
        launchRouteWasResolved = true
        launchResolutionTask?.cancel()
        launchResolutionTask = nil
    }
}

/// Dependencies whose values must remain stable for the lifetime of one app
/// process. Tests inject every value; the release factory obtains only
/// app-scoped, local values and never logs or displays them.
@MainActor
struct ProductionAppDependencies {
    let applicationSupportDirectoryURL: URL
    let accountIdentity: PlayerAccountIdentity
    let deviceID: String
    let sessionNonce: UUID
    let newProfileID: UUID
    let catalog: LaunchCatalog
    let now: @MainActor @Sendable () -> Date
    let makeRunID: @MainActor @Sendable () -> RunID
    let makeSeed: @MainActor @Sendable () -> UInt32

    init(
        applicationSupportDirectoryURL: URL,
        accountIdentity: PlayerAccountIdentity,
        deviceID: String,
        sessionNonce: UUID = UUID(),
        newProfileID: UUID = UUID(),
        catalog: LaunchCatalog = .approved,
        now: @escaping @MainActor @Sendable () -> Date = Date.init,
        makeRunID: @escaping @MainActor @Sendable () -> RunID = { RunID() },
        makeSeed: @escaping @MainActor @Sendable () -> UInt32 = {
            UInt32.random(in: UInt32.min ... UInt32.max)
        }
    ) {
        precondition(!deviceID.isEmpty, "A stable app-scoped device ID is required")
        self.applicationSupportDirectoryURL = applicationSupportDirectoryURL
        self.accountIdentity = accountIdentity
        self.deviceID = deviceID
        self.sessionNonce = sessionNonce
        self.newProfileID = newProfileID
        self.catalog = catalog
        self.now = now
        self.makeRunID = makeRunID
        self.makeSeed = makeSeed
    }
}

/// Stores a random installation identifier in this app's defaults domain.
/// It is not derived from hardware, advertising, account, or Game Center data.
@MainActor
struct StableInstallationDeviceIdentifierStore {
    static let productionStorageKey = "installation-device-id.v1"

    let userDefaults: UserDefaults
    let storageKey: String
    let makeUUID: () -> UUID

    init(
        userDefaults: UserDefaults,
        storageKey: String = Self.productionStorageKey,
        makeUUID: @escaping () -> UUID = UUID.init
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
        self.makeUUID = makeUUID
    }

    func identifier() -> String {
        if let stored = userDefaults.string(forKey: storageKey),
           let parsed = UUID(uuidString: stored) {
            return parsed.uuidString.lowercased()
        }

        let created = makeUUID().uuidString.lowercased()
        userDefaults.set(created, forKey: storageKey)
        return created
    }
}

/// Owns the active local profile repository and exposes only the closures the
/// app coordinator needs. All state shown by the shell is projected from a
/// successfully persisted repository snapshot.
@MainActor
final class ProductionAppComposition {
    /// Persisted fields controlled by `PlayerSnapshot.revision`. The derived
    /// coin balance is intentionally excluded and guarded with the economy
    /// fields below. Runtime sync status is deliberately excluded and owned by
    /// the composition's independent sync revision.
    private struct PlayerRevisionPartition: Equatable {
        let profileID: UUID
        let settings: PlayerSettings
        let selection: PlayerSelection
        let inventory: PlayerInventory
        let career: CareerStatistics
        let achievementProgress: [AchievementID: AchievementProgress]
        let rewardedAdState: RewardedAdState
        let completedRuns: [RunID: CompletedRunRecord]

        init(snapshot: LocalPlayerProfileSnapshot) {
            profileID = snapshot.player.profileID
            settings = snapshot.player.settings
            selection = snapshot.player.selection
            inventory = snapshot.player.inventory
            career = snapshot.player.career
            achievementProgress = snapshot.player.achievementProgress
            rewardedAdState = snapshot.player.rewardedAdState
            completedRuns = snapshot.completedRuns
        }
    }

    /// Persisted economy fields plus the redundant player-facing total derived
    /// from them. Comparing the derived total prevents an internally
    /// inconsistent snapshot from crossing a player-only revision update.
    private struct EconomyRevisionPartition: Equatable {
        let inventory: PlayerInventory
        let rewardedAdState: RewardedAdState
        let derivedPlayerCoinBalance: Int64
        let coinBalances: CoinBalanceSummary
        let ledger: [LedgerEntryID: CoinLedgerEntry]
        let pendingLedgerEntryIDs: Set<LedgerEntryID>
        let rewardedRunObservations: [RunID: RewardedRunObservation]

        init(snapshot: LocalPlayerProfileSnapshot) {
            // Catalog ownership and rewarded-ad progress are stored on the
            // player document, but production only changes them together with
            // a durable economy mutation. Membership in both partitions
            // enforces that coupled invariant.
            inventory = snapshot.player.inventory
            rewardedAdState = snapshot.player.rewardedAdState
            derivedPlayerCoinBalance = snapshot.player.coinBalance
            coinBalances = snapshot.coinBalances
            ledger = snapshot.ledger
            pendingLedgerEntryIDs = snapshot.pendingLedgerEntryIDs
            rewardedRunObservations = snapshot.rewardedRunObservations
        }
    }

    private enum Message {
        static let loadFailed =
            "Saved player data could not be opened. Check available storage and try again."
        static let profileUnavailable =
            "Saved player data is not ready. No changes were made."
        static let mutationFailed =
            "The player profile could not be saved. No unverified changes were applied."
        static let integrityCollision =
            "The player profile returned conflicting data for the same revision. No unverified changes were applied."
        static let selectionTooBroad =
            "That equipment change could not be verified. No changes were made."
        static let runFailed =
            "The completed run could not be verified and saved. Retry before leaving the run."
        static let gameCenterUnavailable =
            "Game Center is not connected in this build."
        static let onlinePurchaseWarning =
            ProductionAccountRuntimeRouter.onlinePurchaseWarning
        static let purchaseFailed =
            "The purchase could not be completed. No changes were made."
        static let adsUnavailable =
            "Rewarded ads are not enabled in this build."
    }

    private let dependencies: ProductionAppDependencies
    private let repositoryRouter: any ProductionProfileRepositoryRouting
    private let authoritativeStateChannel: ProductionAuthoritativeStateChannel
    private let diagnosticsSink: AppleDiagnosticsSink?
    private let commerceRequestService:
        (any ProductionCommerceRequestServicing)?
    private var currentSnapshot: LocalPlayerProfileSnapshot?
    private var syncStatus: ProfileSyncStatus
    private var syncRevision: UInt64

    init(
        dependencies: ProductionAppDependencies,
        authoritativeStateChannel: ProductionAuthoritativeStateChannel = .init(),
        diagnosticsSink: AppleDiagnosticsSink? = nil,
        repository: LocalPlayerProfileRepository? = nil,
        repositoryRouter: (any ProductionProfileRepositoryRouting)? = nil,
        commerceRequestService:
            (any ProductionCommerceRequestServicing)? = nil
    ) {
        self.dependencies = dependencies
        self.authoritativeStateChannel = authoritativeStateChannel
        self.diagnosticsSink = diagnosticsSink
        self.commerceRequestService = commerceRequestService
        syncStatus = .localOnly
        syncRevision = 0
        let initialRepository = repository ?? LocalPlayerProfileRepository(
            directoryURL: Self.profileDirectoryURL(
                applicationSupportDirectoryURL: dependencies.applicationSupportDirectoryURL,
                accountIdentity: dependencies.accountIdentity
            ),
            deviceID: dependencies.deviceID,
            accountIdentity: dependencies.accountIdentity,
            sessionNonce: dependencies.sessionNonce,
            catalog: dependencies.catalog,
            economyMutationPolicy: .requireDurablePrivateCloud
        )
        self.repositoryRouter = repositoryRouter ?? ProductionProfileRepositoryRouter(
            route: ProductionProfileRepositoryRoute(
                repository: initialRepository,
                authority: .local(
                    accountIdentity: dependencies.accountIdentity,
                    sessionNonce: dependencies.sessionNonce
                )
            )
        )
    }

    var environment: AppCoordinatorEnvironment {
        AppCoordinatorEnvironment(
            loadInitialState: { [self] in
                await loadInitialState()
            },
            makeAuthoritativeStateUpdates: { [channel = authoritativeStateChannel] in
                channel.makeStream()
            },
            diagnosticsSink: diagnosticsSink,
            makeRunID: dependencies.makeRunID,
            makeSeed: dependencies.makeSeed,
            now: dependencies.now,
            performExternalRequest: { [self] request in
                await perform(request)
            },
            observeLifecycleEvent: nil,
            settleCompletedRun: { [self] run in
                await settle(run)
            }
        )
    }

    nonisolated static func profileDirectoryURL(
        applicationSupportDirectoryURL: URL,
        accountIdentity: PlayerAccountIdentity
    ) -> URL {
        let digest = SHA256.hash(data: Data(accountIdentity.rawValue.utf8))
        let accountScope = digest.prefix(16).map {
            String(format: "%02x", $0)
        }.joined()

        return applicationSupportDirectoryURL
            .appendingPathComponent("PocketVector", isDirectory: true)
            .appendingPathComponent("Profiles", isDirectory: true)
            .appendingPathComponent(accountScope, isDirectory: true)
    }

    private func loadInitialState() async -> AppBootstrapLoadResult {
        if let currentSnapshot {
            return .loaded(authoritativeSnapshot(from: currentSnapshot))
        }

        do {
            let loadedAt = dependencies.now()
            let route = try await repositoryRouter.currentRoute()
            let snapshot = try await route.repository.load(
                at: loadedAt,
                newProfileID: dependencies.newProfileID
            )
            guard route.authorizes(snapshot) else {
                throw ProductionAppCompositionError.authoritativeSessionMismatch
            }
            let accepted = try accept(snapshot, publishUpdate: false)
            if let report = await route.repository.lastLoadReport {
                reportPersistenceRecovery(report, at: loadedAt)
            }
            return .loaded(authoritativeSnapshot(from: accepted))
        } catch {
            return .failed(message: Message.loadFailed)
        }
    }

    /// Reprojects the repository only after its caller has committed durable
    /// state. SDK callbacks never construct or publish UI state themselves.
    @discardableResult
    private func refreshAuthoritativeStateFromRepository(
        allowVerifiedSessionAdoption: Bool = false
    ) async
        -> ProductionRepositoryRefresh? {
        do {
            let route = try await repositoryRouter.currentRoute()
            let snapshot = try await route.repository.snapshot()
            guard route.authorizes(snapshot) else { return nil }
            let accepted: LocalPlayerProfileSnapshot
            if let currentSnapshot,
               snapshot.session != currentSnapshot.session {
                guard allowVerifiedSessionAdoption,
                      case .verifiedPrivateCloud = route.authority else {
                    return nil
                }
                accepted = try adoptVerifiedSession(
                    snapshot,
                    publishUpdate: true
                )
            } else {
                accepted = try accept(snapshot, publishUpdate: true)
            }
            let projected = authoritativeSnapshot(from: accepted)
            return ProductionRepositoryRefresh(
                snapshot: projected,
                sessionAdoption: ProductionVerifiedSessionAdoption.mint(
                    route: route,
                    snapshot: snapshot
                )
            )
        } catch {
            // A refresh is advisory. The last verified projection remains
            // authoritative and foreground mutations continue to surface their
            // own specific failures.
            return nil
        }
    }

    /// Publishes a runtime-only sync transition without manufacturing a player
    /// or economy revision. Repository snapshots cannot select this status, and
    /// repeating the current status is an idempotent no-op.
    @discardableResult
    func publishSyncStatusTransition(
        _ status: ProfileSyncStatus
    ) throws -> AuthoritativeAppStateSnapshot? {
        guard status != syncStatus else { return nil }
        let nextRevision = syncRevision.addingReportingOverflow(1)
        guard !nextRevision.overflow else {
            throw ProductionAppCompositionError.syncRevisionOverflow
        }

        syncStatus = status
        syncRevision = nextRevision.partialValue
        guard let currentSnapshot else { return nil }
        let update = authoritativeSnapshot(from: currentSnapshot)
        authoritativeStateChannel.publish(update)
        return update
    }

    private func perform(_ request: AppExternalRequest) async -> AppExternalRequestResult {
        guard let currentSnapshot else {
            return .failed(message: Message.profileUnavailable)
        }

        switch request {
        case let .updateSelection(selection):
            do {
                let route = try await repositoryRouter.currentRoute()
                guard route.authorizes(currentSnapshot) else {
                    return .failed(message: Message.profileUnavailable)
                }
                return await updateSelection(
                    selection,
                    currentSnapshot: currentSnapshot,
                    repository: route.repository
                )
            } catch {
                return .failed(message: Message.mutationFailed)
            }

        case let .updateSettings(settings):
            do {
                let route = try await repositoryRouter.currentRoute()
                guard route.authorizes(currentSnapshot) else {
                    return .failed(message: Message.profileUnavailable)
                }
                let snapshot = try await route.repository.updateSettings(
                    settings,
                    session: currentSnapshot.session,
                    at: dependencies.now()
                )
                return try publishMutation(snapshot)
            } catch ProductionAppCompositionError.authoritativeRevisionCollision {
                return .failed(message: Message.integrityCollision)
            } catch {
                return .failed(message: Message.mutationFailed)
            }

        case .showLeaderboard:
            return .failed(message: Message.gameCenterUnavailable)

        case let .requestCatalogUnlock(itemID):
            return await performCommerce(.catalogUnlock(itemID))

        case let .requestCoinPack(packID):
            return await performCommerce(.coinPack(packID))

        case .requestRewardedAd:
            return .failed(message: Message.adsUnavailable)
        }
    }

    private func performCommerce(
        _ request: ProductionCommerceRequest
    ) async -> AppExternalRequestResult {
        guard let commerceRequestService else {
            return .failed(message: Message.onlinePurchaseWarning)
        }

        let before = currentSnapshot.map { authoritativeSnapshot(from: $0) }
        let result = await commerceRequestService.perform(request)
        let refreshed = await refreshAuthoritativeStateFromRepository(
            allowVerifiedSessionAdoption: true
        )
        switch result {
        case .onlineRequired:
            if let refreshed, refreshed.snapshot != before {
                return externalResult(
                    refreshed,
                    message: Message.onlinePurchaseWarning
                )
            }
            return .failed(message: Message.onlinePurchaseWarning)
        case .rejected:
            if let refreshed, refreshed.snapshot != before {
                return externalResult(
                    refreshed,
                    message: Message.purchaseFailed
                )
            }
            return .failed(message: Message.purchaseFailed)
        case .silentlyCompleted:
            if let refreshed, refreshed.snapshot != before {
                return externalResult(refreshed, message: nil)
            }
            return .completed
        case .succeeded:
            // The commerce service owns durable mutation, but never owns App
            // presentation state. Re-read the retained repository and project
            // only that verified snapshot after success.
            guard let refreshed else {
                return .failed(message: Message.purchaseFailed)
            }
            return externalResult(refreshed, message: nil)
        }
    }

    private func externalResult(
        _ refreshed: ProductionRepositoryRefresh,
        message: String?
    ) -> AppExternalRequestResult {
        if let authority = refreshed.sessionAdoption {
            return .adoptedVerifiedPrivateCloud(
                refreshed.snapshot,
                authority: authority,
                message: message
            )
        }
        if let message {
            return .appliedWithNotice(refreshed.snapshot, message: message)
        }
        return .applied(refreshed.snapshot)
    }

    private func updateSelection(
        _ requested: PlayerSelection,
        currentSnapshot: LocalPlayerProfileSnapshot,
        repository: LocalPlayerProfileRepository
    ) async -> AppExternalRequestResult {
        let current = currentSnapshot.player.selection
        let teamChanged = requested.selectedTeamID != current.selectedTeamID
        let footballChanged = requested.selectedFootballID != current.selectedFootballID
        let allTeamIDs = Set(requested.selectedJerseyByTeam.keys)
            .union(current.selectedJerseyByTeam.keys)
        let changedJerseyTeamIDs = allTeamIDs.filter {
            requested.selectedJerseyByTeam[$0] != current.selectedJerseyByTeam[$0]
        }
        let changeCount = (teamChanged ? 1 : 0)
            + (footballChanged ? 1 : 0)
            + changedJerseyTeamIDs.count

        guard changeCount <= 1 else {
            return .failed(message: Message.selectionTooBroad)
        }
        guard changeCount == 1 else {
            return .applied(authoritativeSnapshot(from: currentSnapshot))
        }

        do {
            let snapshot: LocalPlayerProfileSnapshot
            if teamChanged {
                snapshot = try await repository.selectTeam(
                    requested.selectedTeamID,
                    session: currentSnapshot.session,
                    at: dependencies.now()
                )
            } else if footballChanged {
                snapshot = try await repository.equipFootball(
                    requested.selectedFootballID,
                    session: currentSnapshot.session,
                    at: dependencies.now()
                )
            } else if let teamID = changedJerseyTeamIDs.first,
                      let jerseyID = requested.selectedJerseyByTeam[teamID] {
                snapshot = try await repository.equipJersey(
                    jerseyID,
                    for: teamID,
                    session: currentSnapshot.session,
                    at: dependencies.now()
                )
            } else {
                return .failed(message: Message.selectionTooBroad)
            }
            return try publishMutation(snapshot)
        } catch ProductionAppCompositionError.authoritativeRevisionCollision {
            return .failed(message: Message.integrityCollision)
        } catch {
            return .failed(message: Message.mutationFailed)
        }
    }

    private func settle(_ run: CompletedRun) async -> CompletedRunSettlementResult {
        guard let currentSnapshot else {
            return .failed(message: Message.profileUnavailable)
        }

        do {
            let route = try await repositoryRouter.currentRoute()
            guard route.authorizes(currentSnapshot) else {
                return .failed(message: Message.profileUnavailable)
            }
            let settlement = try await route.repository.settle(
                run,
                session: currentSnapshot.session,
                recordedAt: dependencies.now()
            )
            let snapshot = try await route.repository.snapshot()
            let accepted = try accept(snapshot, publishUpdate: true)
            let authoritativeSnapshot = authoritativeSnapshot(from: accepted)

            guard run.finishReason == .timerExpired else {
                return .settled(
                    authoritativeSnapshot: authoritativeSnapshot,
                    results: nil
                )
            }

            let results = try Self.makeResults(
                run: run,
                settlement: settlement,
                snapshot: accepted
            )
            return .settled(
                authoritativeSnapshot: authoritativeSnapshot,
                results: results
            )
        } catch {
            return .failed(message: Message.runFailed)
        }
    }

    private func publishMutation(
        _ snapshot: LocalPlayerProfileSnapshot
    ) throws -> AppExternalRequestResult {
        let accepted = try accept(snapshot, publishUpdate: true)
        return .applied(authoritativeSnapshot(from: accepted))
    }

    /// Accepts only monotonic repository projections. If an older async call
    /// finishes after a newer one, its caller receives the newest accepted
    /// snapshot and the presentation stream never regresses.
    func accept(
        _ candidate: LocalPlayerProfileSnapshot,
        publishUpdate: Bool
    ) throws -> LocalPlayerProfileSnapshot {
        guard let currentSnapshot else {
            self.currentSnapshot = candidate
            if publishUpdate {
                authoritativeStateChannel.publish(
                    authoritativeSnapshot(from: candidate)
                )
            }
            return candidate
        }

        guard candidate.session == currentSnapshot.session else {
            throw ProductionAppCompositionError.authoritativeSessionMismatch
        }
        guard candidate.player.revision >= currentSnapshot.player.revision,
              candidate.economyRevision >= currentSnapshot.economyRevision else {
            return currentSnapshot
        }

        if candidate.player.revision == currentSnapshot.player.revision,
           PlayerRevisionPartition(snapshot: candidate)
            != PlayerRevisionPartition(snapshot: currentSnapshot) {
            throw ProductionAppCompositionError.authoritativeRevisionCollision
        }
        if candidate.economyRevision == currentSnapshot.economyRevision,
           EconomyRevisionPartition(snapshot: candidate)
            != EconomyRevisionPartition(snapshot: currentSnapshot) {
            throw ProductionAppCompositionError.authoritativeRevisionCollision
        }

        if candidate.player.revision == currentSnapshot.player.revision,
           candidate.economyRevision == currentSnapshot.economyRevision {
            // The two explicit persisted partitions cover every repository
            // field except the legacy projection-only sync status. That status
            // is ignored here and can change only through the sync transition
            // method above.
            return currentSnapshot
        }

        self.currentSnapshot = candidate
        if publishUpdate {
            authoritativeStateChannel.publish(
                authoritativeSnapshot(from: candidate)
            )
        }
        return candidate
    }

    /// The sole in-process local-to-private-cloud session replacement. Its
    /// caller has already required a verified-cloud repository route whose
    /// exact session matches the durable claim readback.
    private func adoptVerifiedSession(
        _ candidate: LocalPlayerProfileSnapshot,
        publishUpdate: Bool
    ) throws -> LocalPlayerProfileSnapshot {
        let nextSyncRevision = syncRevision.addingReportingOverflow(1)
        guard !nextSyncRevision.overflow else {
            throw ProductionAppCompositionError.syncRevisionOverflow
        }
        currentSnapshot = candidate
        syncStatus = .current
        syncRevision = nextSyncRevision.partialValue
        if publishUpdate {
            authoritativeStateChannel.publish(
                authoritativeSnapshot(from: candidate)
            )
        }
        return candidate
    }

    private func reportPersistenceRecovery(
        _ report: ProfileLoadReport,
        at date: Date
    ) {
        guard let diagnosticsSink else { return }

        if !report.quarantinedURLs.isEmpty {
            diagnosticsSink.report(
                .persistence(.quarantinedCorruptFile),
                severity: .warning,
                at: date
            )
        }

        switch report.source {
        case .primary:
            break
        case .backup:
            diagnosticsSink.report(
                .persistence(.restoredBackup),
                severity: .warning,
                at: date
            )
        case .createdFresh:
            diagnosticsSink.report(
                .persistence(.createdFreshProfile),
                severity: .info,
                at: date
            )
        }
    }

    private func authoritativeSnapshot(
        from snapshot: LocalPlayerProfileSnapshot
    ) -> AuthoritativeAppStateSnapshot {
        AuthoritativeAppStateSnapshot(
            session: snapshot.session,
            playerRevision: snapshot.player.revision,
            economyRevision: snapshot.economyRevision,
            syncRevision: syncRevision,
            state: Self.project(snapshot, syncStatus: syncStatus)
        )
    }

    private static func project(
        _ snapshot: LocalPlayerProfileSnapshot,
        syncStatus: ProfileSyncStatus
    ) -> AppCoordinatorState {
        AppCoordinatorState(
            inventory: snapshot.player.inventory,
            selection: snapshot.player.selection,
            settings: snapshot.player.settings,
            confirmedCoins: snapshot.coinBalances.confirmed,
            pendingCoins: snapshot.coinBalances.pending,
            personalBest: snapshot.personalBest,
            achievementProgress: snapshot.player.achievementProgress,
            rewardedAdState: snapshot.player.rewardedAdState,
            syncStatus: syncStatus
        )
    }

    private static func makeResults(
        run: CompletedRun,
        settlement: RunSettlementResult,
        snapshot: LocalPlayerProfileSnapshot
    ) throws -> RunResultsPresentation {
        let settledRun = settlement.outcome.record.run
        guard settledRun == run else {
            throw ProductionAppCompositionError.authoritativeSettlementMismatch
        }
        let coinProjection = try RunResultsCoinProjection.make(
            settlement: settlement,
            snapshot: snapshot
        )

        let priorPersonalBest = snapshot.completedRuns.values.reduce(0) { best, record in
            guard record.run.runID != run.runID,
                  CompletedRunValidator.isNaturallyCompleted(record.run) else {
                return best
            }
            return max(best, record.run.score)
        }
        let isNewPersonalBest = CompletedRunValidator.isNaturallyCompleted(run)
            && run.score > priorPersonalBest

        let rewardedAdOffer: RewardedAdOfferPresentation
        if let offerID = snapshot.player.rewardedAdState.eligibleOfferID {
            rewardedAdOffer = .eligible(
                offerID: offerID,
                rewardCoins: PersistedEconomyRulesV1.rewardedAdCoins,
                canPresent: false
            )
        } else {
            rewardedAdOffer = .progress(
                validRuns: snapshot.player.rewardedAdState.validRunsSinceReward,
                requiredRuns: PersistedEconomyRulesV1.rewardedAdRunThreshold
            )
        }

        return RunResultsPresentation(
            completedRun: settledRun,
            completionCoins: coinProjection.completionCoins,
            performanceCoins: coinProjection.performanceCoins,
            accuracyCoins: coinProjection.accuracyCoins,
            signingBonusCoins: coinProjection.signingBonusCoins,
            totalEarnedCoins: coinProjection.totalEarnedCoins,
            pendingCoins: coinProjection.pendingCoins,
            gameplayRewardState: coinProjection.gameplayRewardState,
            signingBonusState: coinProjection.signingBonusState,
            personalBest: settlement.outcome.resultingPersonalBest,
            isNewPersonalBest: isNewPersonalBest,
            rewardedAdOffer: rewardedAdOffer,
            achievementUpdates: settlement.outcome.achievementUpdates
        )
    }
}

/// Projects only the two ledger entries named by one durable run-settlement
/// receipt. Profile-wide pending credits and rewarded-ad ledger entries are
/// deliberately outside this Results contract.
struct RunResultsCoinProjection: Equatable, Sendable {
    let completionCoins: Int64
    let performanceCoins: Int64
    let accuracyCoins: Int64
    let signingBonusCoins: Int64
    let totalEarnedCoins: Int64
    let pendingCoins: Int64
    let gameplayRewardState: RunResultsLedgerState?
    let signingBonusState: RunResultsLedgerState?

    static func make(
        settlement: RunSettlementResult,
        snapshot: LocalPlayerProfileSnapshot
    ) throws -> RunResultsCoinProjection {
        let outcome = settlement.outcome
        let record = outcome.record
        let run = record.run
        guard let rules = PersistedEconomyRulesV1.runRules(
            for: run.configuration.economyVersion
        ) else {
            throw ProductionAppCompositionError.authoritativeSettlementMismatch
        }

        let rewardIsEligible = rules.isRewardEligible(run)
        let completionCoins = rewardIsEligible ? rules.baseRunCoins : 0
        let performanceCoins = rewardIsEligible
            ? min(
                rules.maximumScoreCoins,
                Int64(max(0, run.score) / rules.scoreCoinsPerPoints)
            )
            : 0
        let hasAccuracyBonus = rewardIsEligible
            && run.statistics.attempts >= rules.accuracyMinimumAttempts
            && run.statistics.attempts > 0
            && run.statistics.successfulPasses * 100
                >= run.statistics.attempts * rules.accuracyMinimumPercent
        let accuracyCoins = hasAccuracyBonus ? rules.accuracyBonusCoins : 0
        let gameplayCoins = try checkedSum(
            completionCoins,
            performanceCoins,
            accuracyCoins
        )
        guard gameplayCoins == record.rewardCoins else {
            throw ProductionAppCompositionError.authoritativeSettlementMismatch
        }

        let gameplayRewardState: RunResultsLedgerState?
        if let entryID = outcome.gameplayRewardEntryID {
            guard let entry = snapshot.ledger[entryID] else {
                throw ProductionAppCompositionError.authoritativeLedgerEntryMissing
            }
            guard entry.id == entryID,
                  entryID == CoinLedgerID.gameplay(runID: run.runID),
                  entry.delta == gameplayCoins,
                  entry.delta > 0,
                  case let .gameplay(entryRunID, economyVersion) = entry.reason,
                  entryRunID == run.runID,
                  economyVersion == run.configuration.economyVersion else {
                throw ProductionAppCompositionError.authoritativeLedgerEntryInvalid
            }
            gameplayRewardState = snapshot.pendingLedgerEntryIDs.contains(entryID)
                ? .pending
                : .recorded
        } else {
            guard gameplayCoins == 0 else {
                throw ProductionAppCompositionError.authoritativeSettlementMismatch
            }
            gameplayRewardState = nil
        }

        let signingBonusCoins: Int64
        let signingBonusState: RunResultsLedgerState?
        if let entryID = outcome.signingBonusEntryID {
            guard rewardIsEligible,
                  entryID != outcome.gameplayRewardEntryID,
                  let entry = snapshot.ledger[entryID] else {
                throw ProductionAppCompositionError.authoritativeLedgerEntryMissing
            }
            guard entry.id == entryID,
                  entry.delta == PersistedEconomyRulesV1.signingBonusCoins,
                  case let .signingBonus(version) = entry.reason,
                  version == PersistedEconomyRulesV1.signingBonusVersion,
                  entryID == CoinLedgerID.signingBonus(version: version) else {
                throw ProductionAppCompositionError.authoritativeLedgerEntryInvalid
            }
            signingBonusCoins = entry.delta
            signingBonusState = snapshot.pendingLedgerEntryIDs.contains(entryID)
                ? .pending
                : .recorded
        } else {
            signingBonusCoins = 0
            signingBonusState = nil
        }

        let totalEarnedCoins = try checkedSum(gameplayCoins, signingBonusCoins)
        let pendingGameplayCoins = gameplayRewardState == .pending ? gameplayCoins : 0
        let pendingSigningBonusCoins = signingBonusState == .pending ? signingBonusCoins : 0
        let pendingCoins = try checkedSum(
            pendingGameplayCoins,
            pendingSigningBonusCoins
        )

        return RunResultsCoinProjection(
            completionCoins: completionCoins,
            performanceCoins: performanceCoins,
            accuracyCoins: accuracyCoins,
            signingBonusCoins: signingBonusCoins,
            totalEarnedCoins: totalEarnedCoins,
            pendingCoins: pendingCoins,
            gameplayRewardState: gameplayRewardState,
            signingBonusState: signingBonusState
        )
    }

    private static func checkedSum(_ values: Int64...) throws -> Int64 {
        var total: Int64 = 0
        for value in values {
            let next = total.addingReportingOverflow(value)
            guard !next.overflow else {
                throw ProductionAppCompositionError.authoritativeLedgerOverflow
            }
            total = next.partialValue
        }
        return total
    }
}

enum ProductionAppCompositionError: Error, Equatable {
    case authoritativeLedgerEntryMissing
    case authoritativeLedgerEntryInvalid
    case authoritativeLedgerOverflow
    case authoritativeSettlementMismatch
    case authoritativeSessionMismatch
    case authoritativeRevisionCollision
    case syncRevisionOverflow
}

extension AppCoordinatorEnvironment {
    @MainActor
    static var profileStorageUnavailable: AppCoordinatorEnvironment {
        AppCoordinatorEnvironment(
            loadInitialState: {
                .failed(
                    message: "Saved player data storage is unavailable on this device."
                )
            },
            makeAuthoritativeStateUpdates: nil,
            makeRunID: { RunID() },
            makeSeed: { UInt32.random(in: UInt32.min ... UInt32.max) },
            now: Date.init,
            performExternalRequest: { _ in
                .failed(message: "Saved player data storage is unavailable on this device.")
            },
            observeLifecycleEvent: nil,
            settleCompletedRun: { _ in
                .failed(message: "Saved player data storage is unavailable on this device.")
            }
        )
    }
}

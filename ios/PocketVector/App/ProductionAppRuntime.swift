import Foundation

/// The account router deliberately depends on only the fresh account probe,
/// rather than treating a previously published sync badge as commerce proof.
protocol ProductionCloudAccountDiscovering: Sendable {
    func accountState() async -> CloudAccountState
}

extension CloudKitCloudSyncTransport: ProductionCloudAccountDiscovering {}

enum ProductionVerifiedAccountClaimError: Error, Equatable, Sendable {
    case cloudAccountMismatch
    case profileAccountMismatch
    case profileIdentifierMismatch
}

/// The result of the durable claim/hydration transaction. Construction checks
/// the complete deterministic private-account binding; the claiming service's
/// protocol contract additionally requires that the returned snapshot was read
/// back from the installed repository after its hydration journal completed.
struct ProductionVerifiedAccountClaim: Equatable, Sendable {
    let cloudAccountID: CloudAccountID
    let installedRepository: LocalPlayerProfileRepository
    let snapshot: LocalPlayerProfileSnapshot

    init(
        cloudAccountID: CloudAccountID,
        derivedBindings: CloudAccountDerivedBindings,
        installedRepository: LocalPlayerProfileRepository
    ) async throws {
        let snapshot = try await installedRepository.snapshot()
        guard derivedBindings == CloudAccountDerivedBindings.derive(
            from: cloudAccountID
        ) else {
            throw ProductionVerifiedAccountClaimError.cloudAccountMismatch
        }
        guard snapshot.session.accountIdentity
                == derivedBindings.playerAccountIdentity else {
            throw ProductionVerifiedAccountClaimError.profileAccountMismatch
        }
        guard snapshot.session.profileID
                == derivedBindings.durableAccountBinding.profileID,
              snapshot.player.profileID
                == derivedBindings.durableAccountBinding.profileID else {
            throw ProductionVerifiedAccountClaimError.profileIdentifierMismatch
        }

        self.cloudAccountID = cloudAccountID
        self.installedRepository = installedRepository
        self.snapshot = snapshot
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.cloudAccountID == rhs.cloudAccountID
            && lhs.installedRepository === rhs.installedRepository
            && lhs.snapshot == rhs.snapshot
    }
}

/// Owns the only production path that may claim a local profile for a private
/// cloud account or hydrate an already claimed profile. Returning success is a
/// durability assertion, not merely a validated in-memory merge plan.
protocol ProductionAccountClaiming: Sendable {
    func claimAndHydrate(
        accountID: CloudAccountID,
        derivedBindings: CloudAccountDerivedBindings
    ) async throws -> ProductionVerifiedAccountClaim
}

struct ProductionAccountRuntimeContext: Equatable, Sendable {
    let cloudAccountID: CloudAccountID
    let derivedBindings: CloudAccountDerivedBindings
    let profileSnapshot: LocalPlayerProfileSnapshot
    let durableEconomyContext: DurableEconomySessionContext

    init(verifiedClaim: ProductionVerifiedAccountClaim) throws {
        let derivedBindings = CloudAccountDerivedBindings.derive(
            from: verifiedClaim.cloudAccountID
        )
        guard verifiedClaim.snapshot.session.accountIdentity
                == derivedBindings.playerAccountIdentity,
              verifiedClaim.snapshot.session.profileID
                == derivedBindings.durableAccountBinding.profileID,
              verifiedClaim.snapshot.player.profileID
                == derivedBindings.durableAccountBinding.profileID else {
            throw ProductionVerifiedAccountClaimError.profileAccountMismatch
        }
        let storeSession = StoreActiveSession(
            binding: derivedBindings.storeAccountBinding,
            nonce: verifiedClaim.snapshot.session.nonce
        )
        durableEconomyContext = try DurableEconomySessionContext(
            cloudAccountID: verifiedClaim.cloudAccountID,
            accountBinding: derivedBindings.durableAccountBinding,
            profileSession: verifiedClaim.snapshot.session,
            storeSession: storeSession
        )
        cloudAccountID = verifiedClaim.cloudAccountID
        self.derivedBindings = derivedBindings
        profileSnapshot = verifiedClaim.snapshot
    }
}

enum ProductionCommerceRequest: Equatable, Sendable {
    case catalogUnlock(CatalogItemID)
    case coinPack(CoinPackID)
}

enum ProductionCommerceRequestResult: Equatable, Sendable {
    case succeeded
    case onlineRequired
    case silentlyCompleted
    case rejected
}

protocol ProductionCommerceRequestServicing: Sendable {
    func perform(
        _ request: ProductionCommerceRequest
    ) async -> ProductionCommerceRequestResult
}

struct ProductionOnlineCommerceBridge: ProductionCommerceRequestServicing {
    let coordinator: OnlineCommerceCoordinator
    let makeOperationID: @Sendable () -> OperationID

    init(
        coordinator: OnlineCommerceCoordinator,
        makeOperationID: @escaping @Sendable () -> OperationID = {
            OperationID(UUID().uuidString.lowercased())
        }
    ) {
        self.coordinator = coordinator
        self.makeOperationID = makeOperationID
    }

    func perform(
        _ request: ProductionCommerceRequest
    ) async -> ProductionCommerceRequestResult {
        switch request {
        case let .catalogUnlock(itemID):
            switch await coordinator.purchaseCatalogItem(
                itemID,
                requestOperationID: makeOperationID()
            ) {
            case .purchased:
                return .succeeded
            case let .failed(failure):
                return Self.map(failure)
            }
        case let .coinPack(packID):
            switch await coordinator.requestCoinPack(packID) {
            case let .failed(failure):
                return Self.map(failure)
            case let .completed(completion):
                return Self.map(completion)
            }
        }
    }

    private static func map(
        _ failure: OnlineCommerceFailure
    ) -> ProductionCommerceRequestResult {
        switch failure {
        case .onlineRequired, .cancelled:
            .onlineRequired
        case .requestAlreadyInFlight:
            .silentlyCompleted
        case .store, .catalogRejected, .integrityFailure:
            .rejected
        }
    }

    private static func map(
        _ completion: StoreKitRuntimePurchaseCompletion
    ) -> ProductionCommerceRequestResult {
        switch completion {
        case .processed(.delivered), .processed(.ignoredAlreadyFinished),
             .processed(.ignoredDuplicateInFlight):
            .succeeded
        case .pending, .userCancelled, .purchaseAlreadyInFlight,
             .purchasePending:
            .silentlyCompleted
        case .cancelled, .inactive:
            .onlineRequired
        case .processed(.rejected), .processed(.deferred), .failed,
             .productUnavailable:
            .rejected
        }
    }
}

/// One retained account component. Activation receives the exact context made
/// from the durable claim, and shutdown must be idempotent and return only once
/// all account-scoped work has stopped.
protocol ProductionAccountRuntimeComponent: Sendable {
    func activate(context: ProductionAccountRuntimeContext) async throws
    func shutdown() async
}

/// The builder returns a fully assembled but inactive graph. The router keeps
/// each role explicit so retirement can stop StoreKit before economy and cloud.
struct ProductionAccountScopedRuntimeComponents: Sendable {
    let installedRepository: LocalPlayerProfileRepository
    let cloud: any ProductionAccountRuntimeComponent
    let economy: any ProductionAccountRuntimeComponent
    let storeKit: any ProductionAccountRuntimeComponent
    let commerce: any ProductionCommerceRequestServicing

    init(
        installedRepository: LocalPlayerProfileRepository,
        cloud: any ProductionAccountRuntimeComponent,
        economy: any ProductionAccountRuntimeComponent,
        storeKit: any ProductionAccountRuntimeComponent,
        commerce: any ProductionCommerceRequestServicing
    ) {
        self.installedRepository = installedRepository
        self.cloud = cloud
        self.economy = economy
        self.storeKit = storeKit
        self.commerce = commerce
    }
}

protocol ProductionAccountScopedRuntimeBuilding: Sendable {
    func makeAccountScopedRuntime(
        context: ProductionAccountRuntimeContext,
        verifiedClaim: ProductionVerifiedAccountClaim
    ) async throws -> ProductionAccountScopedRuntimeComponents
}

enum ProductionAccountRuntimeUnavailability: Equatable, Sendable {
    case configurationUnavailable
    case accountUnknown
    case signedOut
    case restricted
    case accountChangedDuringActivation
    case claimOrHydrationFailed
    case componentActivationFailed
    case cancelled
}

enum ProductionAccountRuntimeRefreshResult: Equatable, Sendable {
    case current(ProductionAccountRuntimeContext)
    case unavailable(ProductionAccountRuntimeUnavailability)
}

/// Serializes every account transition. An account switch first awaits the
/// prior StoreKit/economy/cloud shutdown, then claims and activates a successor.
/// No component or commerce service becomes visible before durable hydration,
/// binding validation, and a second fresh provider-account probe all succeed.
actor ProductionAccountRuntimeRouter: ProductionCommerceRequestServicing {
    static let onlinePurchaseWarning =
        "You must be online to make purchases. Your earned coins are saved and will sync when you reconnect."

    private struct ActiveRuntime {
        var context: ProductionAccountRuntimeContext
        let components: ProductionAccountScopedRuntimeComponents
    }

    private struct TransitionWaiter {
        let id: UInt64
        let continuation: CheckedContinuation<Bool, Never>
    }

    private let accountDiscovery: (any ProductionCloudAccountDiscovering)?
    private let accountClaimer: (any ProductionAccountClaiming)?
    private let runtimeBuilder: (any ProductionAccountScopedRuntimeBuilding)?
    private var activeRuntime: ActiveRuntime?
    private var transitionIsRunning = false
    private var transitionWaiters: [TransitionWaiter] = []
    private var nextWaiterID: UInt64 = 0
    private var commerceRequestIsRunning = false

    init(
        accountDiscovery: (any ProductionCloudAccountDiscovering)?,
        accountClaimer: (any ProductionAccountClaiming)?,
        runtimeBuilder: (any ProductionAccountScopedRuntimeBuilding)?
    ) {
        self.accountDiscovery = accountDiscovery
        self.accountClaimer = accountClaimer
        self.runtimeBuilder = runtimeBuilder
    }

    func currentContext() -> ProductionAccountRuntimeContext? {
        activeRuntime?.context
    }

    /// Always consults the provider. Callers use this at a transaction
    /// boundary; a cached sync status never enters this decision.
    func refresh() async -> ProductionAccountRuntimeRefreshResult {
        guard await acquireTransitionGate() else {
            return .unavailable(.cancelled)
        }
        defer { releaseTransitionGate() }
        return await refreshWhileHoldingTransitionGate()
    }

    func perform(
        _ request: ProductionCommerceRequest
    ) async -> ProductionCommerceRequestResult {
        guard !Task.isCancelled else {
            return .onlineRequired
        }
        // Duplicate taps must never wait behind a purchase and then open a
        // second sheet. Treat them as an already-admitted command.
        guard !commerceRequestIsRunning else { return .silentlyCompleted }
        commerceRequestIsRunning = true
        defer { commerceRequestIsRunning = false }

        guard await acquireTransitionGate() else {
            return .onlineRequired
        }
        defer { releaseTransitionGate() }

        guard case .current = await refreshWhileHoldingTransitionGate(),
              !Task.isCancelled,
              let commerce = activeRuntime?.components.commerce else {
            return .onlineRequired
        }
        return await commerce.perform(request)
    }

    /// Returns only after all retained account work has stopped.
    func shutdown() async {
        guard await acquireTransitionGate() else { return }
        defer { releaseTransitionGate() }
        await retireActiveRuntime()
    }

    private func refreshWhileHoldingTransitionGate() async
        -> ProductionAccountRuntimeRefreshResult {
        guard !Task.isCancelled else { return .unavailable(.cancelled) }
        guard let accountDiscovery, let accountClaimer, let runtimeBuilder else {
            await retireActiveRuntime()
            return .unavailable(.configurationUnavailable)
        }

        let firstState = await accountDiscovery.accountState()
        guard case let .available(accountID) = firstState else {
            await retireActiveRuntime()
            if Task.isCancelled { return .unavailable(.cancelled) }
            return .unavailable(Self.unavailability(for: firstState))
        }

        if activeRuntime?.context.cloudAccountID != accountID {
            await retireActiveRuntime()
        }
        guard !Task.isCancelled else { return .unavailable(.cancelled) }

        let derivedBindings = CloudAccountDerivedBindings.derive(from: accountID)
        let claim: ProductionVerifiedAccountClaim
        let context: ProductionAccountRuntimeContext
        do {
            claim = try await accountClaimer.claimAndHydrate(
                accountID: accountID,
                derivedBindings: derivedBindings
            )
            context = try ProductionAccountRuntimeContext(
                verifiedClaim: claim
            )
            guard claim.cloudAccountID == accountID,
                  context.cloudAccountID == accountID else {
                throw ProductionVerifiedAccountClaimError.cloudAccountMismatch
            }
        } catch {
            await retireActiveRuntime()
            if error is CancellationError || Task.isCancelled {
                return .unavailable(.cancelled)
            }
            return .unavailable(.claimOrHydrationFailed)
        }
        guard !Task.isCancelled else {
            await retireActiveRuntime()
            return .unavailable(.cancelled)
        }

        let stateAfterClaim = await accountDiscovery.accountState()
        guard !Task.isCancelled else {
            await retireActiveRuntime()
            return .unavailable(.cancelled)
        }
        guard stateAfterClaim == .available(accountID) else {
            await retireActiveRuntime()
            return .unavailable(.accountChangedDuringActivation)
        }

        if var activeRuntime,
           activeRuntime.context.durableEconomyContext
            == context.durableEconomyContext,
           activeRuntime.components.installedRepository
            === claim.installedRepository {
            // The claim service has refreshed the same retained repository.
            // Keep its long-lived tasks, but expose the newest verified readback.
            activeRuntime.context = context
            self.activeRuntime = activeRuntime
            return .current(context)
        }

        await retireActiveRuntime()

        var candidateComponents: ProductionAccountScopedRuntimeComponents?
        do {
            try Task.checkCancellation()
            let components = try await runtimeBuilder.makeAccountScopedRuntime(
                context: context,
                verifiedClaim: claim
            )
            guard components.installedRepository
                    === claim.installedRepository else {
                throw ProductionVerifiedAccountClaimError.cloudAccountMismatch
            }
            candidateComponents = components
            try Task.checkCancellation()
            try await components.cloud.activate(context: context)
            try Task.checkCancellation()
            try await components.economy.activate(context: context)
            try Task.checkCancellation()
            try await components.storeKit.activate(context: context)
            try Task.checkCancellation()
        } catch {
            if let components = candidateComponents {
                await Self.shutdown(components)
            }
            if error is CancellationError || Task.isCancelled {
                return .unavailable(.cancelled)
            }
            return .unavailable(.componentActivationFailed)
        }
        guard let components = candidateComponents else {
            return .unavailable(.componentActivationFailed)
        }

        let stateAfterActivation = await accountDiscovery.accountState()
        guard !Task.isCancelled else {
            await Self.shutdown(components)
            return .unavailable(.cancelled)
        }
        guard stateAfterActivation == .available(accountID) else {
            await Self.shutdown(components)
            return .unavailable(.accountChangedDuringActivation)
        }

        activeRuntime = ActiveRuntime(
            context: context,
            components: components
        )
        return .current(context)
    }

    private func retireActiveRuntime() async {
        guard let activeRuntime else { return }
        self.activeRuntime = nil
        await Self.shutdown(activeRuntime.components)
    }

    private static func shutdown(
        _ components: ProductionAccountScopedRuntimeComponents
    ) async {
        await components.storeKit.shutdown()
        await components.economy.shutdown()
        await components.cloud.shutdown()
    }

    private static func unavailability(
        for state: CloudAccountState
    ) -> ProductionAccountRuntimeUnavailability {
        switch state {
        case .unknown:
            .accountUnknown
        case .signedOut:
            .signedOut
        case .restricted:
            .restricted
        case .available:
            .accountChangedDuringActivation
        }
    }

    private func acquireTransitionGate() async -> Bool {
        guard !Task.isCancelled else { return false }
        if !transitionIsRunning {
            transitionIsRunning = true
            return true
        }

        let waiterID = nextWaiterID
        let advanced = nextWaiterID.addingReportingOverflow(1)
        precondition(!advanced.overflow, "Account transition waiter ID exhausted")
        nextWaiterID = advanced.partialValue
        let granted = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                transitionWaiters.append(
                    TransitionWaiter(id: waiterID, continuation: continuation)
                )
            }
        } onCancel: {
            Task { await self.cancelTransitionWaiter(id: waiterID) }
        }
        guard granted else { return false }
        if Task.isCancelled {
            releaseTransitionGate()
            return false
        }
        return true
    }

    private func releaseTransitionGate() {
        guard !transitionWaiters.isEmpty else {
            transitionIsRunning = false
            return
        }
        transitionWaiters.removeFirst().continuation.resume(returning: true)
    }

    private func cancelTransitionWaiter(id: UInt64) {
        guard let index = transitionWaiters.firstIndex(where: { $0.id == id }) else {
            return
        }
        transitionWaiters.remove(at: index).continuation.resume(returning: false)
    }
}

struct ProductionConfiguredAccountRuntimeGraph: Sendable {
    let accountDiscovery: any ProductionCloudAccountDiscovering
    let accountClaimer: any ProductionAccountClaiming
    let runtimeBuilder: any ProductionAccountScopedRuntimeBuilding
}

struct ProductionConfiguredAccountRuntimeGraphInput: Sendable {
    let cloudWriteConfiguration: ProductionCloudWriteConfiguration
    let storeKitConfiguration: StoreKit2ProductConfiguration
    let sourceRepository: LocalPlayerProfileRepository
    let repositoryRouter: ProductionProfileRepositoryRouter
    let applicationSupportDirectoryURL: URL
    let deviceID: String
    let sessionNonce: UUID
    let catalog: LaunchCatalog
}

struct ProductionAccountRuntimeAssemblyInput: Sendable {
    let sourceRepository: LocalPlayerProfileRepository
    let repositoryRouter: ProductionProfileRepositoryRouter
    let applicationSupportDirectoryURL: URL
    let deviceID: String
    let sessionNonce: UUID
    let catalog: LaunchCatalog
}

/// App-owned construction seam for the concrete Services graph. It admits a
/// graph only when both validated configurations are present, and keeps test
/// doubles out of the release factory itself.
protocol ProductionConfiguredAccountRuntimeGraphBuilding: Sendable {
    func makeConfiguredAccountRuntimeGraph(
        input: ProductionConfiguredAccountRuntimeGraphInput
    ) throws -> ProductionConfiguredAccountRuntimeGraph
}

struct ProductionLiveAccountRuntimeGraphBuilder:
    ProductionConfiguredAccountRuntimeGraphBuilding
{
    func makeConfiguredAccountRuntimeGraph(
        input: ProductionConfiguredAccountRuntimeGraphInput
    ) throws -> ProductionConfiguredAccountRuntimeGraph {
        let cloud = CloudKitCloudSyncTransport.live(
            configuration: input.cloudWriteConfiguration.transport
        )
        let core = ProductionLiveAccountRuntimeCore(
            input: input,
            cloud: cloud,
            associationStore: ProfileInitialAssociationStoreV1()
        )
        return ProductionConfiguredAccountRuntimeGraph(
            accountDiscovery: cloud,
            accountClaimer: core,
            runtimeBuilder: core
        )
    }
}

private enum ProductionLiveAccountRuntimeError: Error {
    case contextMismatch
    case missingClaimBundle
    case storeActivationFailed
}

private struct ProductionStoreSessionSource: StoreKitRuntimeSessionSourcing {
    let authority: DurableEconomySessionAuthority

    func currentStoreSession() async -> StoreActiveSession? {
        await authority.currentContext()?.storeSession
    }
}

private actor ProductionNoopAccountRuntimeComponent:
    ProductionAccountRuntimeComponent
{
    func activate(context: ProductionAccountRuntimeContext) async throws {}
    func shutdown() async {}
}

private actor ProductionEconomyAuthorityRuntimeComponent:
    ProductionAccountRuntimeComponent
{
    let authority: DurableEconomySessionAuthority

    init(authority: DurableEconomySessionAuthority) {
        self.authority = authority
    }

    func activate(context: ProductionAccountRuntimeContext) async throws {
        await authority.activate(context.durableEconomyContext)
    }

    func shutdown() async {
        await authority.invalidate()
    }
}

private actor ProductionStoreKitAccountRuntimeComponent:
    ProductionAccountRuntimeComponent
{
    let coordinator: StoreKitRuntimeCoordinator

    init(coordinator: StoreKitRuntimeCoordinator) {
        self.coordinator = coordinator
    }

    func activate(context: ProductionAccountRuntimeContext) async throws {
        switch await coordinator.activate() {
        case .activated, .unchanged:
            return
        case .noActiveSession, .cancelled, .superseded:
            throw ProductionLiveAccountRuntimeError.storeActivationFailed
        }
    }

    func shutdown() async {
        await coordinator.shutdown()
    }
}

private actor ProductionLiveAccountRuntimeCore:
    ProductionAccountClaiming,
    ProductionAccountScopedRuntimeBuilding
{
    private struct ClaimBundle {
        let context: DurableEconomySessionContext
        let repository: LocalPlayerProfileRepository
        let sessionAuthority: DurableEconomySessionAuthority
        let economy: DurableEconomyCoordinator
        let preparer: ProductionCloudProfileReplicaPreparerV1
    }

    private let input: ProductionConfiguredAccountRuntimeGraphInput
    private let cloud: CloudKitCloudSyncTransport
    private let associationStore: ProfileInitialAssociationStoreV1
    private var bundlesByRepository: [ObjectIdentifier: ClaimBundle] = [:]

    init(
        input: ProductionConfiguredAccountRuntimeGraphInput,
        cloud: CloudKitCloudSyncTransport,
        associationStore: ProfileInitialAssociationStoreV1
    ) {
        self.input = input
        self.cloud = cloud
        self.associationStore = associationStore
    }

    func claimAndHydrate(
        accountID: CloudAccountID,
        derivedBindings: CloudAccountDerivedBindings
    ) async throws -> ProductionVerifiedAccountClaim {
        guard derivedBindings == CloudAccountDerivedBindings.derive(
            from: accountID
        ) else {
            throw ProductionLiveAccountRuntimeError.contextMismatch
        }

        if let existing = try await existingVerifiedRepository(
            accountID: accountID
        ) {
            let bundle = try bundle(
                accountID: accountID,
                repository: existing.repository,
                snapshot: existing.snapshot
            )
            _ = try await bundle.preparer.refreshAndHydrateSameRepository(
                expected: bundle.context,
                repository: bundle.repository
            )
            return try await publishClaim(
                accountID: accountID,
                derivedBindings: derivedBindings,
                bundle: bundle
            )
        }

        let targetDirectoryURL = ProductionAppComposition.profileDirectoryURL(
            applicationSupportDirectoryURL:
                input.applicationSupportDirectoryURL,
            accountIdentity: derivedBindings.playerAccountIdentity
        )
        let targetRepository = LocalPlayerProfileRepository(
            directoryURL: targetDirectoryURL,
            deviceID: input.deviceID,
            accountIdentity: derivedBindings.playerAccountIdentity,
            sessionNonce: input.sessionNonce,
            catalog: input.catalog,
            economyMutationPolicy: .requireDurablePrivateCloud
        )
        let bundle = try bundle(
            accountID: accountID,
            repository: targetRepository,
            snapshot: nil
        )
        let association = CloudInitialProfileAssociationCoordinatorV1(
            cloud: cloud,
            planner: CloudInitialProfilePublicationPlannerV1(
                profileConfiguration: input.cloudWriteConfiguration.profile,
                economyConfiguration: input.cloudWriteConfiguration.economy,
                catalog: input.catalog
            ),
            replicaPreparer: bundle.preparer,
            associationStore: associationStore,
            installingDeviceID: input.deviceID
        )
        _ = try await association.claimAndHydrate(
            accountID: accountID,
            sourceRepository: input.sourceRepository,
            targetDirectoryURL: targetDirectoryURL,
            targetRepository: targetRepository
        )
        return try await publishClaim(
            accountID: accountID,
            derivedBindings: derivedBindings,
            bundle: bundle
        )
    }

    func makeAccountScopedRuntime(
        context: ProductionAccountRuntimeContext,
        verifiedClaim: ProductionVerifiedAccountClaim
    ) async throws -> ProductionAccountScopedRuntimeComponents {
        guard let bundle = bundlesByRepository[
            ObjectIdentifier(verifiedClaim.installedRepository)
        ] else {
            throw ProductionLiveAccountRuntimeError.missingClaimBundle
        }
        guard bundle.repository === verifiedClaim.installedRepository,
              bundle.context == context.durableEconomyContext else {
            throw ProductionLiveAccountRuntimeError.contextMismatch
        }

        let storeAdapter = StoreKit2CoinTransactionAdapter(
            configuration: input.storeKitConfiguration,
            platformClient: LiveStoreKit2PlatformClient(),
            durableDelivery: bundle.economy
        )
        let storeRuntime = StoreKitRuntimeCoordinator(
            adapter: storeAdapter,
            sessionSource: ProductionStoreSessionSource(
                authority: bundle.sessionAuthority
            )
        )
        let authorizer = PrivateCloudCommerceTransactionAuthorizer(
            sessionAuthority: bundle.sessionAuthority,
            cloud: cloud,
            networkProbeRecordID:
                input.cloudWriteConfiguration.economy.recordID
        )
        let commerce = OnlineCommerceCoordinator(
            context: context.durableEconomyContext,
            authorizer: authorizer,
            economy: bundle.economy,
            refresher: SameRepositoryOnlineCommerceAuthoritativeRefresherV1(
                preparer: bundle.preparer,
                repository: bundle.repository
            ),
            store: storeRuntime
        )
        return ProductionAccountScopedRuntimeComponents(
            installedRepository: bundle.repository,
            cloud: ProductionNoopAccountRuntimeComponent(),
            economy: ProductionEconomyAuthorityRuntimeComponent(
                authority: bundle.sessionAuthority
            ),
            storeKit: ProductionStoreKitAccountRuntimeComponent(
                coordinator: storeRuntime
            ),
            commerce: ProductionOnlineCommerceBridge(coordinator: commerce)
        )
    }

    private func existingVerifiedRepository(
        accountID: CloudAccountID
    ) async throws -> (
        repository: LocalPlayerProfileRepository,
        snapshot: LocalPlayerProfileSnapshot
    )? {
        let route = try await input.repositoryRouter.currentRoute()
        guard case let .verifiedPrivateCloud(claim) = route.authority,
              claim.cloudAccountID == accountID,
              route.repository === claim.installedRepository else {
            return nil
        }
        return (route.repository, try await route.repository.snapshot())
    }

    private func bundle(
        accountID: CloudAccountID,
        repository: LocalPlayerProfileRepository,
        snapshot: LocalPlayerProfileSnapshot?
    ) throws -> ClaimBundle {
        let key = ObjectIdentifier(repository)
        if let existing = bundlesByRepository[key] {
            return existing
        }
        let bindings = CloudAccountDerivedBindings.derive(from: accountID)
        let profileSession = snapshot?.session ?? ProfileSessionToken(
            accountIdentity: bindings.playerAccountIdentity,
            nonce: input.sessionNonce,
            profileID: bindings.durableAccountBinding.profileID
        )
        let context = try DurableEconomySessionContext(
            cloudAccountID: accountID,
            accountBinding: bindings.durableAccountBinding,
            profileSession: profileSession,
            storeSession: StoreActiveSession(
                binding: bindings.storeAccountBinding,
                nonce: profileSession.nonce
            )
        )
        let sessionAuthority = DurableEconomySessionAuthority()
        let productionEconomy = DurableEconomyCoordinator.makeProduction(
            context: context,
            sessionAuthority: sessionAuthority,
            repository: repository,
            cloud: cloud,
            configuration: input.cloudWriteConfiguration.economy,
            catalog: input.catalog
        )
        let preparer = try ProductionCloudProfileReplicaPreparerV1.live(
            accountID: accountID,
            checkpointRootDirectoryURL: input.applicationSupportDirectoryURL
                .appendingPathComponent(
                    "PocketVector/CloudReplicaCheckpoints",
                    isDirectory: true
                ),
            configuration: input.cloudWriteConfiguration,
            economyVerifier: productionEconomy.verifier,
            installingDeviceID: input.deviceID
        )
        let bundle = ClaimBundle(
            context: context,
            repository: repository,
            sessionAuthority: sessionAuthority,
            economy: productionEconomy.coordinator,
            preparer: preparer
        )
        bundlesByRepository[key] = bundle
        return bundle
    }

    private func publishClaim(
        accountID: CloudAccountID,
        derivedBindings: CloudAccountDerivedBindings,
        bundle: ClaimBundle
    ) async throws -> ProductionVerifiedAccountClaim {
        let claim = try await ProductionVerifiedAccountClaim(
            cloudAccountID: accountID,
            derivedBindings: derivedBindings,
            installedRepository: bundle.repository
        )
        guard claim.snapshot.session == bundle.context.profileSession else {
            throw ProductionLiveAccountRuntimeError.contextMismatch
        }
        try await input.repositoryRouter.adoptVerifiedPrivateCloud(
            repository: bundle.repository,
            claim: claim
        )
        return claim
    }
}

struct ProductionAccountRuntimeAssembly: Sendable {
    let router: ProductionAccountRuntimeRouter
    let graphIsComplete: Bool
    let accountDiscovery: (any ProductionCloudAccountDiscovering)?
}

enum ProductionAccountRuntimeAssembler {
    static func assemble(
        serviceConfiguration: ProductionServiceConfiguration,
        input: ProductionAccountRuntimeAssemblyInput,
        graphBuilder:
            (any ProductionConfiguredAccountRuntimeGraphBuilding)?
    ) -> ProductionAccountRuntimeAssembly {
        guard case let .validated(cloudWrite) = serviceConfiguration.cloudWrite,
              case let .validated(storeKit) = serviceConfiguration.storeKit,
              let graphBuilder,
              let graph = try? graphBuilder.makeConfiguredAccountRuntimeGraph(
                input: ProductionConfiguredAccountRuntimeGraphInput(
                    cloudWriteConfiguration: cloudWrite,
                    storeKitConfiguration: storeKit,
                    sourceRepository: input.sourceRepository,
                    repositoryRouter: input.repositoryRouter,
                    applicationSupportDirectoryURL:
                        input.applicationSupportDirectoryURL,
                    deviceID: input.deviceID,
                    sessionNonce: input.sessionNonce,
                    catalog: input.catalog
                )
              ) else {
            return ProductionAccountRuntimeAssembly(
                router: ProductionAccountRuntimeRouter(
                    accountDiscovery: nil,
                    accountClaimer: nil,
                    runtimeBuilder: nil
                ),
                graphIsComplete: false,
                accountDiscovery: nil
            )
        }
        return ProductionAccountRuntimeAssembly(
            router: ProductionAccountRuntimeRouter(
                accountDiscovery: graph.accountDiscovery,
                accountClaimer: graph.accountClaimer,
                runtimeBuilder: graph.runtimeBuilder
            ),
            graphIsComplete: true,
            accountDiscovery: graph.accountDiscovery
        )
    }
}

/// Retains the complete process-scoped production graph and both long-lived
/// consumers. Their lifetimes follow the runtime rather than a transient view.
@MainActor
final class ProductionAppRuntime {
    let coordinator: AppCoordinator
    let presentationHandoff: UIKitGameKitPresentationHandoff
    let serviceConfiguration: ProductionServiceConfiguration
    let runtimeCapabilities: ProductionRuntimeCapabilities
    let accountRuntimeRouter: ProductionAccountRuntimeRouter?

    private let composition: ProductionAppComposition?
    private let authoritativeStateChannel: ProductionAuthoritativeStateChannel
    private let diagnostics: AppleDiagnosticsRuntime
    private var coordinatorTask: Task<Void, Never>?
    private var coordinatorTaskID: UUID?
    private var diagnosticsTask: Task<Void, Never>?

    init(
        coordinator: AppCoordinator,
        presentationHandoff: UIKitGameKitPresentationHandoff,
        serviceConfiguration: ProductionServiceConfiguration,
        runtimeCapabilities: ProductionRuntimeCapabilities,
        composition: ProductionAppComposition?,
        authoritativeStateChannel: ProductionAuthoritativeStateChannel,
        diagnostics: AppleDiagnosticsRuntime,
        accountRuntimeRouter: ProductionAccountRuntimeRouter? = nil
    ) {
        self.coordinator = coordinator
        self.presentationHandoff = presentationHandoff
        self.serviceConfiguration = serviceConfiguration
        self.runtimeCapabilities = runtimeCapabilities
        self.composition = composition
        self.authoritativeStateChannel = authoritativeStateChannel
        self.diagnostics = diagnostics
        self.accountRuntimeRouter = accountRuntimeRouter
        coordinatorTask = nil
        coordinatorTaskID = nil
        diagnosticsTask = nil
    }

    static func live(
        bundle: Bundle = .main,
        fileManager: FileManager = .default,
        userDefaults: UserDefaults = .standard,
        accountRuntimeGraphBuilder:
            (any ProductionConfiguredAccountRuntimeGraphBuilding)? =
                ProductionLiveAccountRuntimeGraphBuilder()
    ) -> ProductionAppRuntime {
        let serviceConfiguration = ProductionServiceConfiguration.from(bundle: bundle)
        let presentationHandoff = UIKitGameKitPresentationHandoff()
        let diagnostics = AppleDiagnosticsRuntime.live(
            subsystem: bundle.bundleIdentifier ?? "PocketVector"
        )
        let channel = ProductionAuthoritativeStateChannel()

        guard let applicationSupportDirectoryURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            let runtimeCapabilities = ProductionRuntimeCapabilities
                .appleDiagnosticsOnly
            let privacySupportConfiguration = PrivacySupportConfiguration.from(
                bundle: bundle,
                services: runtimeCapabilities.serviceAvailability
            )
            var environment = AppCoordinatorEnvironment.profileStorageUnavailable
            environment.privacySupportConfiguration = privacySupportConfiguration
            environment.diagnosticsSink = diagnostics.sink
            return ProductionAppRuntime(
                coordinator: AppCoordinator(environment: environment),
                presentationHandoff: presentationHandoff,
                serviceConfiguration: serviceConfiguration,
                runtimeCapabilities: runtimeCapabilities,
                composition: nil,
                authoritativeStateChannel: channel,
                diagnostics: diagnostics
            )
        }

        let deviceID = StableInstallationDeviceIdentifierStore(
            userDefaults: userDefaults
        ).identifier()
        let sessionNonce = UUID()
        let dependencies = ProductionAppDependencies(
            applicationSupportDirectoryURL: applicationSupportDirectoryURL,
            accountIdentity: .local,
            deviceID: deviceID,
            sessionNonce: sessionNonce
        )
        let sourceDirectoryURL = ProductionAppComposition.profileDirectoryURL(
            applicationSupportDirectoryURL: applicationSupportDirectoryURL,
            accountIdentity: .local
        )
        let sourceRepository = LocalPlayerProfileRepository(
            directoryURL: sourceDirectoryURL,
            deviceID: deviceID,
            accountIdentity: .local,
            sessionNonce: sessionNonce,
            catalog: dependencies.catalog,
            economyMutationPolicy: .requireDurablePrivateCloud
        )
        let launchAccountDiscovery = ProductionLaunchCloudAccountDiscovery()
        let repositoryRouter = ProductionProfileRepositoryRouter(
            route: ProductionProfileRepositoryRoute(
                repository: sourceRepository,
                authority: .local(
                    accountIdentity: .local,
                    sessionNonce: sessionNonce
                )
            ),
            launchResolver: ProductionCommittedAssociationRouteResolver(
                associationStore: ProfileInitialAssociationStoreV1(),
                sourceRepository: sourceRepository,
                sourceDirectoryURL: sourceDirectoryURL,
                deviceID: deviceID,
                sessionNonce: sessionNonce,
                catalog: dependencies.catalog,
                accountDiscovery: launchAccountDiscovery,
                now: Date.init
            )
        )
        let accountRuntimeAssembly = ProductionAccountRuntimeAssembler.assemble(
            serviceConfiguration: serviceConfiguration,
            input: ProductionAccountRuntimeAssemblyInput(
                sourceRepository: sourceRepository,
                repositoryRouter: repositoryRouter,
                applicationSupportDirectoryURL: applicationSupportDirectoryURL,
                deviceID: deviceID,
                sessionNonce: sessionNonce,
                catalog: dependencies.catalog
            ),
            graphBuilder: accountRuntimeGraphBuilder
        )
        let accountRuntimeRouter = accountRuntimeAssembly.router
        let accountGraphIsComplete = accountRuntimeAssembly.graphIsComplete
        if let accountDiscovery = accountRuntimeAssembly.accountDiscovery {
            launchAccountDiscovery.install(accountDiscovery)
        }
        let runtimeCapabilities = ProductionRuntimeCapabilities(
            serviceAvailability: AppServiceAvailability(
                rewardedAdsAreConfigured: false,
                purchasesAreConfigured: accountGraphIsComplete,
                gameCenterIsConfigured: false,
                iCloudSyncIsConfigured: accountGraphIsComplete
            )
        )
        let privacySupportConfiguration = PrivacySupportConfiguration.from(
            bundle: bundle,
            services: runtimeCapabilities.serviceAvailability
        )
        let composition = ProductionAppComposition(
            dependencies: dependencies,
            authoritativeStateChannel: channel,
            diagnosticsSink: diagnostics.sink,
            repository: sourceRepository,
            repositoryRouter: repositoryRouter,
            commerceRequestService: accountRuntimeRouter
        )
        var environment = composition.environment
        environment.privacySupportConfiguration = privacySupportConfiguration

        return ProductionAppRuntime(
            coordinator: AppCoordinator(
                catalog: .approved,
                environment: environment
            ),
            presentationHandoff: presentationHandoff,
            serviceConfiguration: serviceConfiguration,
            runtimeCapabilities: runtimeCapabilities,
            composition: composition,
            authoritativeStateChannel: channel,
            diagnostics: diagnostics,
            accountRuntimeRouter: accountRuntimeRouter
        )
    }

    var coordinatorTaskIsRunning: Bool {
        coordinatorTask != nil
    }

    /// Starts the one process-scoped profile bootstrap/state consumer. A
    /// completed attempt clears its slot so the failure UI can explicitly
    /// retry without creating an unowned task or overlapping consumers.
    func startCoordinator() {
        guard coordinatorTask == nil else { return }
        let taskID = UUID()
        let coordinator = self.coordinator
        coordinatorTaskID = taskID
        coordinatorTask = Task { @MainActor [weak self] in
            await coordinator.run()
            self?.coordinatorTaskDidFinish(taskID)
        }
    }

    func startAppleDiagnostics() {
        guard diagnosticsTask == nil else { return }
        let diagnostics = self.diagnostics
        diagnosticsTask = Task {
            await diagnostics.run()
        }
    }

    /// Explicit owner shutdown for tests and future scene/process lifecycle
    /// integration. Deinit retains a best-effort fallback because it cannot
    /// itself await account-scoped producers.
    func shutdownAccountRuntime() async {
        await accountRuntimeRouter?.shutdown()
    }

    deinit {
        coordinatorTask?.cancel()
        diagnosticsTask?.cancel()
        if let accountRuntimeRouter {
            Task {
                await accountRuntimeRouter.shutdown()
            }
        }
    }

    private func coordinatorTaskDidFinish(_ taskID: UUID) {
        guard coordinatorTaskID == taskID else { return }
        coordinatorTask = nil
        coordinatorTaskID = nil
    }
}

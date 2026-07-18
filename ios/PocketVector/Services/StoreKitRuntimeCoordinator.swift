import Foundation

/// The production StoreKit adapter is kept behind a protocol so lifecycle and
/// presentation behavior can be proven without contacting StoreKit. App
/// composition remains responsible for constructing the live adapter only when
/// every account and private-cloud prerequisite is available.
protocol StoreKit2CoinTransactionAdapting: Sendable {
    func products() async throws -> [StoreProduct]
    func purchaseOnline(
        _ packID: CoinPackID,
        session: StoreActiveSession,
        expected context: DurableEconomySessionContext,
        authorizer: any OnlineCommerceTransactionAuthorizing
    ) async throws -> StoreKit2CoinPurchaseResult
    func recoverUnfinishedTransactions(
        session: StoreActiveSession
    ) async -> [StoreKit2TransactionProcessingResult]
    func transactionUpdates(
        session: StoreActiveSession
    ) async -> StoreKit2OwnedUpdateListener<StoreKit2TransactionProcessingResult>
}

extension StoreKit2CoinTransactionAdapter: StoreKit2CoinTransactionAdapting {}

/// The account-scoped runtime coordinator is the only production source of an
/// active StoreKit session. Returning nil keeps commerce dormant.
protocol StoreKitRuntimeSessionSourcing: Sendable {
    func currentStoreSession() async -> StoreActiveSession?
}

enum StoreKitRuntimeFailure: Error, Equatable, Sendable {
    case noActiveSession
    case networkUnavailable
    case storeUnavailable
    case purchasesNotAllowed
    case productNotConfigured(CoinPackID)
    case productUnavailable(CoinPackID)
    case productIsNotConsumable(CoinPackID)
    case invalidProductResponse
    case transactionUpdatesEnded
    case transactionDeferred(StoreKit2TransactionDeferral)

    init(error: any Error) {
        if let failure = error as? DurableEconomyCoordinatorError {
            switch failure {
            case .noCurrentSession, .staleSession, .profileSessionMismatch,
                 .cloudAccountUnavailable, .cloudAccountMismatch,
                 .cloudRebaseRequired, .economyRevisionChanged:
                self = .noActiveSession
            default:
                self = .storeUnavailable
            }
            return
        }
        if let failure = error as? CloudSyncTransportError {
            switch failure {
            case .accountUnavailable, .accountMismatch:
                self = .noActiveSession
            case .conflict, .operationIDCollision:
                self = .storeUnavailable
            }
            return
        }
        if let failure = error as? CloudKitCloudSyncError {
            switch failure {
            case .accountRestricted, .accountTemporarilyUnavailable:
                self = .noActiveSession
            case .networkUnavailable, .serviceUnavailable, .rateLimited:
                self = .networkUnavailable
            default:
                self = .storeUnavailable
            }
            return
        }
        guard let failure = error as? StoreKit2AdapterFailure else {
            self = .storeUnavailable
            return
        }
        switch failure {
        case .networkUnavailable:
            self = .networkUnavailable
        case .storeUnavailable:
            self = .storeUnavailable
        case .purchasesNotAllowed:
            self = .purchasesNotAllowed
        case let .productNotConfigured(packID):
            self = .productNotConfigured(packID)
        case let .productUnavailable(packID):
            self = .productUnavailable(packID)
        case let .productIsNotConsumable(packID):
            self = .productIsNotConsumable(packID)
        case .invalidProductResponse:
            self = .invalidProductResponse
        }
    }
}

/// Removes transaction and ledger identifiers before a result reaches
/// presentation or telemetry.
enum StoreKitRuntimeProcessingOutcome: Equatable, Sendable {
    case delivered(StoreKit2DurableDeliveryStatus)
    case rejected(StoreKit2TransactionRejection)
    case deferred(StoreKit2TransactionDeferral)
    case ignoredAlreadyFinished
    case ignoredDuplicateInFlight

    init(_ result: StoreKit2TransactionProcessingResult) {
        switch result {
        case let .deliveredAndFinished(_, _, _, deliveryStatus):
            self = .delivered(deliveryStatus)
        case let .rejected(rejection):
            self = .rejected(rejection)
        case let .deferred(_, reason):
            self = .deferred(reason)
        case .ignoredAlreadyFinished:
            self = .ignoredAlreadyFinished
        case .ignoredDuplicateInFlight:
            self = .ignoredDuplicateInFlight
        }
    }
}

enum StoreKitRuntimeOutcomeSource: Equatable, Sendable {
    case unfinishedRecovery
    case transactionUpdate
    case purchase(CoinPackID)
}

enum StoreKitRuntimeLatestOutcome: Equatable, Sendable {
    case processed(
        source: StoreKitRuntimeOutcomeSource,
        outcome: StoreKitRuntimeProcessingOutcome
    )
    case purchasePending(CoinPackID)
    case purchaseCancelled(CoinPackID)
    case purchaseFailed(packID: CoinPackID, failure: StoreKitRuntimeFailure)
}

enum StoreKitRuntimePresentationPhase: Equatable, Sendable {
    case inactive
    case starting
    case loading
    case available
    case purchasing(CoinPackID)
    case pending(CoinPackID)
    case unavailable(StoreKitRuntimeFailure)
    case retrying
}

struct StoreKitRuntimePresentationState: Equatable, Sendable {
    let phase: StoreKitRuntimePresentationPhase
    let products: [StoreProduct]
    let latestOutcome: StoreKitRuntimeLatestOutcome?

    static let inactive = StoreKitRuntimePresentationState(
        phase: .inactive,
        products: [],
        latestOutcome: nil
    )
}

enum StoreKitRuntimeActivationResult: Equatable, Sendable {
    case activated
    case unchanged
    case noActiveSession
    case cancelled
    case superseded
}

/// Identifier-free completion for the foreground request that opened the
/// StoreKit sheet. Unlike presentation observation, this value is correlated
/// with exactly one admitted tap and can therefore be awaited by the commerce
/// transaction boundary.
enum StoreKitRuntimePurchaseCompletion: Equatable, Sendable {
    case processed(StoreKitRuntimeProcessingOutcome)
    case pending
    case userCancelled
    case failed(StoreKitRuntimeFailure)
    case cancelled
    case inactive
    case productUnavailable
    case purchaseAlreadyInFlight
    case purchasePending
}

/// Revalidates the exact private-cloud/profile/store generation. Production
/// purchase requests pass this authority into the awaited StoreKit entry point
/// so the last check occurs inside the task immediately before the SDK call.
protocol OnlineCommerceTransactionAuthorizing: Sendable {
    func revalidate(
        expected context: DurableEconomySessionContext
    ) async throws
}

struct PrivateCloudCommerceTransactionAuthorizer:
    OnlineCommerceTransactionAuthorizing,
    Sendable
{
    let sessionAuthority: any DurableEconomySessionAuthorizing
    let cloud: any CloudSyncTransport
    /// A known private-zone record (normally the economy head). Reading it is a
    /// harmless network round trip; absence is valid for a newly claimed
    /// account, while transport/account loss fails closed.
    let networkProbeRecordID: CloudRecordID

    func revalidate(
        expected context: DurableEconomySessionContext
    ) async throws {
        try Task.checkCancellation()
        guard let current = await sessionAuthority.currentContext() else {
            throw DurableEconomyCoordinatorError.noCurrentSession
        }
        guard current == context else {
            throw DurableEconomyCoordinatorError.staleSession
        }
        switch await cloud.accountState() {
        case let .available(accountID) where accountID == context.cloudAccountID:
            break
        case .available:
            throw DurableEconomyCoordinatorError.cloudAccountMismatch
        case .unknown, .signedOut, .restricted:
            throw DurableEconomyCoordinatorError.cloudAccountUnavailable
        }
        _ = try await cloud.records(
            accountID: context.cloudAccountID,
            ids: [networkProbeRecordID]
        )
        try Task.checkCancellation()
        switch await cloud.accountState() {
        case let .available(accountID) where accountID == context.cloudAccountID:
            return
        case .available:
            throw DurableEconomyCoordinatorError.cloudAccountMismatch
        case .unknown, .signedOut, .restricted:
            throw DurableEconomyCoordinatorError.cloudAccountUnavailable
        }
    }
}

protocol OnlineCommerceDurableEconomyTransacting: Sendable {
    func confirmAllPendingCredits() async throws -> DurablePendingCreditResult?
    func unlock(
        itemID: CatalogItemID,
        requestOperationID: OperationID,
        session: ProfileSessionToken
    ) async throws -> DurableCatalogUnlockResult
}

extension DurableEconomyCoordinator: OnlineCommerceDurableEconomyTransacting {}

/// Performs the complete cloud-replica refresh/rebase and returns the snapshot
/// read back from the installed account-scoped repository. This is deliberately
/// stronger than republishing a cached sync status.
protocol OnlineCommerceAuthoritativeRefreshing: Sendable {
    func refreshAuthoritativeProfile(
        expected context: DurableEconomySessionContext
    ) async throws -> LocalPlayerProfileSnapshot
}

protocol OnlineCommerceStorePurchasing: Sendable {
    func purchaseAndWait(
        _ packID: CoinPackID,
        expected context: DurableEconomySessionContext,
        authorizer: any OnlineCommerceTransactionAuthorizing
    ) async -> StoreKitRuntimePurchaseCompletion
}

enum OnlineCommerceFailure: Error, Equatable, Sendable {
    /// Presentation maps this single bounded case to the existing online-only
    /// purchase warning. No provider text or account identifier escapes.
    case onlineRequired
    case requestAlreadyInFlight
    case cancelled
    case store(StoreKitRuntimeFailure)
    case catalogRejected
    case integrityFailure

    static func classify(_ error: any Error) -> Self {
        if error is CancellationError { return .cancelled }
        if let failure = error as? DurableEconomyCoordinatorError {
            switch failure {
            case .noCurrentSession, .staleSession, .profileSessionMismatch,
                 .cloudAccountUnavailable, .cloudAccountMismatch,
                 .cloudRebaseRequired, .economyRevisionChanged:
                return .onlineRequired
            case .invalidCatalogUnlockRequest:
                return .catalogRejected
            default:
                return .integrityFailure
            }
        }
        if let failure = error as? CloudSyncTransportError {
            switch failure {
            case .accountUnavailable, .accountMismatch:
                return .onlineRequired
            case .conflict, .operationIDCollision:
                return .integrityFailure
            }
        }
        if let failure = error as? CloudKitCloudSyncError {
            switch failure {
            case .accountRestricted, .accountTemporarilyUnavailable,
                 .networkUnavailable, .serviceUnavailable, .rateLimited:
                return .onlineRequired
            default:
                return .integrityFailure
            }
        }
        if let failure = error as? LocalPlayerRepositoryError {
            switch failure {
            case .inventory:
                return .catalogRejected
            default:
                return .integrityFailure
            }
        }
        return .integrityFailure
    }
}

enum OnlineCommerceCatalogResult: Equatable, Sendable {
    case purchased(DurableCatalogUnlockResult)
    case failed(OnlineCommerceFailure)
}

enum OnlineCommerceCoinPackResult: Equatable, Sendable {
    case completed(StoreKitRuntimePurchaseCompletion)
    case failed(OnlineCommerceFailure)
}

/// One fail-closed transaction boundary for both coin debits and StoreKit
/// requests. Admission is fail-fast rather than queued, so duplicate taps and
/// cancelled waiters can never execute later. Every admitted request confirms
/// pending gameplay credits, refreshes the authoritative replica, and then
/// performs one final exact-generation check before mutation/presentation.
actor OnlineCommerceCoordinator {
    private let context: DurableEconomySessionContext
    private let authorizer: any OnlineCommerceTransactionAuthorizing
    private let economy: any OnlineCommerceDurableEconomyTransacting
    private let refresher: any OnlineCommerceAuthoritativeRefreshing
    private let store: any OnlineCommerceStorePurchasing
    private var requestIsInFlight = false

    init(
        context: DurableEconomySessionContext,
        authorizer: any OnlineCommerceTransactionAuthorizing,
        economy: any OnlineCommerceDurableEconomyTransacting,
        refresher: any OnlineCommerceAuthoritativeRefreshing,
        store: any OnlineCommerceStorePurchasing
    ) {
        self.context = context
        self.authorizer = authorizer
        self.economy = economy
        self.refresher = refresher
        self.store = store
    }

    func purchaseCatalogItem(
        _ itemID: CatalogItemID,
        requestOperationID: OperationID
    ) async -> OnlineCommerceCatalogResult {
        guard !Task.isCancelled else { return .failed(.cancelled) }
        guard !requestIsInFlight else { return .failed(.requestAlreadyInFlight) }
        requestIsInFlight = true
        defer { requestIsInFlight = false }

        do {
            try await prepareCurrentTransaction()
            try Task.checkCancellation()
            try await authorizer.revalidate(expected: context)
            try Task.checkCancellation()
            return .purchased(
                try await economy.unlock(
                    itemID: itemID,
                    requestOperationID: requestOperationID,
                    session: context.profileSession
                )
            )
        } catch {
            return .failed(OnlineCommerceFailure.classify(error))
        }
    }

    func requestCoinPack(
        _ packID: CoinPackID
    ) async -> OnlineCommerceCoinPackResult {
        guard !Task.isCancelled else { return .failed(.cancelled) }
        guard !requestIsInFlight else { return .failed(.requestAlreadyInFlight) }
        requestIsInFlight = true
        defer { requestIsInFlight = false }

        do {
            try await prepareCurrentTransaction()
            try Task.checkCancellation()
            let completion = await store.purchaseAndWait(
                packID,
                expected: context,
                authorizer: authorizer
            )
            return mapStoreCompletion(completion)
        } catch {
            return .failed(OnlineCommerceFailure.classify(error))
        }
    }

    private func prepareCurrentTransaction() async throws {
        try await authorizer.revalidate(expected: context)
        try Task.checkCancellation()
        _ = try await economy.confirmAllPendingCredits()
        try Task.checkCancellation()
        let refreshed = try await refresher.refreshAuthoritativeProfile(
            expected: context
        )
        try Task.checkCancellation()
        guard refreshed.session == context.profileSession else {
            throw DurableEconomyCoordinatorError.staleSession
        }
    }

    private func mapStoreCompletion(
        _ completion: StoreKitRuntimePurchaseCompletion
    ) -> OnlineCommerceCoinPackResult {
        switch completion {
        case .inactive:
            return .failed(.onlineRequired)
        case .cancelled:
            return .failed(.cancelled)
        case .purchaseAlreadyInFlight:
            return .failed(.requestAlreadyInFlight)
        case .failed(.noActiveSession), .failed(.networkUnavailable),
             .failed(.transactionDeferred(.durableDeliveryConnectivityUnavailable)),
             .processed(.deferred(.durableDeliveryConnectivityUnavailable)):
            return .failed(.onlineRequired)
        case let .processed(.deferred(reason)):
            return .failed(.store(.transactionDeferred(reason)))
        case let .failed(failure):
            return .failed(.store(failure))
        default:
            return .completed(completion)
        }
    }
}

/// Retains every StoreKit task for exactly one account/session generation.
/// Replacing a generation invalidates it before cancellation, then awaits all
/// retired work before a successor can begin. Every callback rechecks both the
/// hidden generation token and the exact StoreActiveSession before publishing.
actor StoreKitRuntimeCoordinator {
    private final class GenerationIdentity: Sendable {}
    private final class LifecycleRequestIdentity: Sendable {}
    private final class ReapIdentity: Sendable {}

    private struct ActiveGeneration {
        let identity: GenerationIdentity
        let session: StoreActiveSession
        var startupTask: Task<Void, Never>?
        var updatesListener: StoreKit2OwnedUpdateListener<StoreKit2TransactionProcessingResult>?
        var updatesTask: Task<Void, Never>?
        var purchaseTask: Task<StoreKitRuntimePurchaseCompletion, Never>?
        var retryRequiredFailure: StoreKitRuntimeFailure?
    }

    private struct ReapOperation {
        let identity: ReapIdentity
        let task: Task<Void, Never>
    }

    private let adapter: any StoreKit2CoinTransactionAdapting
    private let sessionSource: any StoreKitRuntimeSessionSourcing
    private var activeGeneration: ActiveGeneration?
    private var latestLifecycleRequest: LifecycleRequestIdentity?
    private var reapOperation: ReapOperation?
    private var presentationContinuations:
        [UUID: AsyncStream<StoreKitRuntimePresentationState>.Continuation]
    private(set) var presentationState: StoreKitRuntimePresentationState

    init(
        adapter: any StoreKit2CoinTransactionAdapting,
        sessionSource: any StoreKitRuntimeSessionSourcing
    ) {
        self.adapter = adapter
        self.sessionSource = sessionSource
        activeGeneration = nil
        latestLifecycleRequest = nil
        reapOperation = nil
        presentationContinuations = [:]
        presentationState = .inactive
    }

    deinit {
        activeGeneration?.startupTask?.cancel()
        activeGeneration?.updatesTask?.cancel()
        activeGeneration?.purchaseTask?.cancel()
        if let listener = activeGeneration?.updatesListener {
            Task {
                await listener.cancelAndWait()
            }
        }
        for continuation in presentationContinuations.values {
            continuation.finish()
        }
    }

    /// Returns one complete, identifier-free presentation snapshot.
    func snapshot() -> StoreKitRuntimePresentationState {
        presentationState
    }

    /// Creates a restartable, newest-only presentation subscription. Every
    /// subscriber immediately receives the current complete snapshot.
    func presentationUpdates() -> AsyncStream<StoreKitRuntimePresentationState> {
        let pair = AsyncStream<StoreKitRuntimePresentationState>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        let subscriberID = UUID()
        pair.continuation.onTermination = { [weak self] _ in
            Task { [weak self] in
                await self?.removePresentationSubscriber(subscriberID)
            }
        }
        presentationContinuations[subscriberID] = pair.continuation
        pair.continuation.yield(presentationState)
        return pair.stream
    }

    /// Activating the exact current session is an idempotent no-op. Failures do
    /// not cause background retries; callers explicitly invoke `retry()`.
    func activate() async -> StoreKitRuntimeActivationResult {
        let request = beginLifecycleRequest()
        let requestedSession = await sessionSource.currentStoreSession()
        guard request === latestLifecycleRequest else { return .superseded }
        guard !Task.isCancelled else { return .cancelled }
        guard let requestedSession else {
            await retireActiveGeneration(nextPhase: .inactive)
            guard request === latestLifecycleRequest else { return .superseded }
            guard !Task.isCancelled else { return .cancelled }
            return .noActiveSession
        }
        if activeGeneration?.session == requestedSession {
            return .unchanged
        }

        await retireActiveGeneration(nextPhase: .starting)
        guard request === latestLifecycleRequest else { return .superseded }
        guard !Task.isCancelled else {
            setPresentation(phase: .inactive, products: [], latestOutcome: nil)
            return .cancelled
        }
        startGeneration(session: requestedSession, initialPhase: .starting)
        return .activated
    }

    /// A foreground or user retry replaces even the same session generation.
    /// There is intentionally no timer or automatic backoff.
    func retry() async -> StoreKitRuntimeActivationResult {
        let request = beginLifecycleRequest()
        let requestedSession = await sessionSource.currentStoreSession()
        guard request === latestLifecycleRequest else { return .superseded }
        guard !Task.isCancelled else { return .cancelled }
        guard let requestedSession else {
            await retireActiveGeneration(nextPhase: .inactive)
            guard request === latestLifecycleRequest else { return .superseded }
            guard !Task.isCancelled else { return .cancelled }
            return .noActiveSession
        }

        await retireActiveGeneration(nextPhase: .retrying)
        guard request === latestLifecycleRequest else { return .superseded }
        guard !Task.isCancelled else {
            setPresentation(phase: .inactive, products: [], latestOutcome: nil)
            return .cancelled
        }
        startGeneration(session: requestedSession, initialPhase: .retrying)
        return .activated
    }

    /// Returns only after all work owned by the retired session has completed.
    func deactivate() async {
        await shutdown()
    }

    /// The proof-bearing owner shutdown path. A retained composition must await
    /// this before releasing or replacing the coordinator. `deinit` provides a
    /// cancellation fallback only because destructors cannot await producers.
    func shutdown() async {
        _ = beginLifecycleRequest()
        await retireActiveGeneration(nextPhase: .inactive)
    }

    /// Fail-fast, correlated purchase admission for online commerce. No caller
    /// is queued: a duplicate tap receives `purchaseAlreadyInFlight`, so it can
    /// never become a second StoreKit sheet after the first request completes.
    /// Cancellation before the final authorization also cannot reach StoreKit.
    func purchaseAndWait(
        _ packID: CoinPackID,
        expected context: DurableEconomySessionContext,
        authorizer: any OnlineCommerceTransactionAuthorizing
    ) async -> StoreKitRuntimePurchaseCompletion {
        guard !Task.isCancelled else { return .cancelled }
        guard var generation = activeGeneration else { return .inactive }
        guard generation.session == context.storeSession else { return .inactive }
        guard generation.retryRequiredFailure == nil else {
            return .productUnavailable
        }
        guard presentationState.products.contains(where: { $0.packID == packID }) else {
            return .productUnavailable
        }
        guard generation.purchaseTask == nil else {
            return .purchaseAlreadyInFlight
        }
        if case .pending = presentationState.phase {
            return .purchasePending
        }
        guard case .available = presentationState.phase else {
            return .productUnavailable
        }

        setPresentation(
            phase: .purchasing(packID),
            products: presentationState.products,
            latestOutcome: presentationState.latestOutcome
        )
        let generationIdentity = generation.identity
        let session = generation.session
        let adapter = self.adapter
        let sessionSource = self.sessionSource
        let task = Task { [weak self] in
            let result: Result<StoreKit2CoinPurchaseResult, StoreKitRuntimeFailure>
            do {
                try Task.checkCancellation()
                guard await sessionSource.currentStoreSession() == session else {
                    throw DurableEconomyCoordinatorError.staleSession
                }
                try Task.checkCancellation()
                result = .success(
                    try await adapter.purchaseOnline(
                        packID,
                        session: session,
                        expected: context,
                        authorizer: authorizer
                    )
                )
            } catch is CancellationError {
                return StoreKitRuntimePurchaseCompletion.cancelled
            } catch {
                result = .failure(StoreKitRuntimeFailure(error: error))
            }
            guard !Task.isCancelled else {
                return StoreKitRuntimePurchaseCompletion.cancelled
            }
            await self?.purchaseDidComplete(
                result,
                packID: packID,
                generationIdentity: generationIdentity,
                session: session
            )
            switch result {
            case let .success(.processed(processingResult)):
                return .processed(StoreKitRuntimeProcessingOutcome(processingResult))
            case .success(.pending):
                return .pending
            case .success(.userCancelled):
                return .userCancelled
            case let .failure(failure):
                return .failed(failure)
            }
        }
        generation.purchaseTask = task
        activeGeneration = generation
        let completion = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }

        // A cancellation/error before `purchaseDidComplete` must clear the
        // admitted slot and restore presentation only for this exact generation.
        if completion == .cancelled {
            purchaseWasCancelledBeforeCompletion(
                packID: packID,
                generationIdentity: generationIdentity,
                session: session
            )
        }
        return completion
    }

    private func purchaseWasCancelledBeforeCompletion(
        packID: CoinPackID,
        generationIdentity: GenerationIdentity,
        session: StoreActiveSession
    ) {
        guard var generation = activeGeneration,
              generation.identity === generationIdentity,
              generation.session == session else { return }
        generation.purchaseTask = nil
        activeGeneration = generation
        guard generation.retryRequiredFailure == nil,
              case .purchasing(packID) = presentationState.phase else { return }
        setPresentation(
            phase: .available,
            products: presentationState.products,
            latestOutcome: presentationState.latestOutcome
        )
    }

    private func beginLifecycleRequest() -> LifecycleRequestIdentity {
        let request = LifecycleRequestIdentity()
        latestLifecycleRequest = request
        return request
    }

    private func startGeneration(
        session: StoreActiveSession,
        initialPhase: StoreKitRuntimePresentationPhase
    ) {
        let generationIdentity = GenerationIdentity()
        setPresentation(phase: initialPhase, products: [], latestOutcome: nil)
        let adapter = self.adapter
        let task = Task<Void, Never> { [weak self] in
            let finishStartup: @Sendable () async -> Void = { [weak self] in
                await self?.startupDidEnd(
                    generationIdentity: generationIdentity,
                    session: session
                )
            }

            let listener = await adapter.transactionUpdates(session: session)
            guard !Task.isCancelled else {
                await listener.cancelAndWait()
                await finishStartup()
                return
            }
            guard await self?.installUpdatesListener(
                listener,
                generationIdentity: generationIdentity,
                session: session
            ) == true else {
                await listener.cancelAndWait()
                await finishStartup()
                return
            }

            let recovered = await adapter.recoverUnfinishedTransactions(session: session)
            guard !Task.isCancelled,
                  await self?.applyRecoveredResults(
                    recovered,
                    generationIdentity: generationIdentity,
                    session: session
                  ) == true else {
                await finishStartup()
                return
            }
            guard await self?.beginProductLoading(
                generationIdentity: generationIdentity,
                session: session
            ) == true,
            !Task.isCancelled else {
                await finishStartup()
                return
            }

            do {
                let products = try await adapter.products()
                guard !Task.isCancelled else {
                    await finishStartup()
                    return
                }
                await self?.productsDidLoad(
                    products,
                    generationIdentity: generationIdentity,
                    session: session
                )
            } catch is CancellationError {
                // Retirement owns presentation state and producer cleanup.
            } catch {
                guard !Task.isCancelled else {
                    await finishStartup()
                    return
                }
                await self?.productsDidFail(
                    error,
                    generationIdentity: generationIdentity,
                    session: session
                )
            }
            await finishStartup()
        }
        activeGeneration = ActiveGeneration(
            identity: generationIdentity,
            session: session,
            startupTask: task,
            updatesListener: nil,
            updatesTask: nil,
            purchaseTask: nil,
            retryRequiredFailure: nil
        )
    }

    private func installUpdatesListener(
        _ listener: StoreKit2OwnedUpdateListener<StoreKit2TransactionProcessingResult>,
        generationIdentity: GenerationIdentity,
        session: StoreActiveSession
    ) -> Bool {
        guard var generation = activeGeneration,
              generation.identity === generationIdentity,
              generation.session == session,
              generation.retryRequiredFailure == nil else { return false }
        let task = Task<Void, Never> { [weak self] in
            for await result in listener.updates {
                guard !Task.isCancelled else { break }
                await self?.receiveUpdate(
                    result,
                    generationIdentity: generationIdentity,
                    session: session
                )
            }
            let wasCancelled = Task.isCancelled
            await listener.cancelAndWait()
            await self?.updatesDidEnd(
                generationIdentity: generationIdentity,
                session: session,
                wasCancelled: wasCancelled
            )
        }
        generation.updatesListener = listener
        generation.updatesTask = task
        activeGeneration = generation
        return true
    }

    private func applyRecoveredResults(
        _ recovered: [StoreKit2TransactionProcessingResult],
        generationIdentity: GenerationIdentity,
        session: StoreActiveSession
    ) -> Bool {
        guard generationCanContinue(generationIdentity, session: session) else {
            return false
        }
        for result in recovered {
            apply(
                result,
                source: .unfinishedRecovery,
                generationIdentity: generationIdentity,
                session: session
            )
        }
        return generationCanContinue(generationIdentity, session: session)
    }

    private func beginProductLoading(
        generationIdentity: GenerationIdentity,
        session: StoreActiveSession
    ) -> Bool {
        guard generationCanContinue(generationIdentity, session: session) else {
            return false
        }
        setPresentation(
            phase: .loading,
            products: [],
            latestOutcome: presentationState.latestOutcome
        )
        return true
    }

    private func productsDidLoad(
        _ products: [StoreProduct],
        generationIdentity: GenerationIdentity,
        session: StoreActiveSession
    ) {
        guard generationCanContinue(generationIdentity, session: session) else { return }
        guard products.map(\.packID) == EconomyConfiguration.coinPacks.map(\.id),
              products.map(\.coins) == EconomyConfiguration.coinPacks.map(\.coins) else {
            setPresentation(
                phase: .unavailable(.invalidProductResponse),
                products: [],
                latestOutcome: presentationState.latestOutcome
            )
            return
        }
        setPresentation(
            phase: .available,
            products: products,
            latestOutcome: presentationState.latestOutcome
        )
    }

    private func productsDidFail(
        _ error: any Error,
        generationIdentity: GenerationIdentity,
        session: StoreActiveSession
    ) {
        guard generationCanContinue(generationIdentity, session: session) else { return }
        setPresentation(
            phase: .unavailable(StoreKitRuntimeFailure(error: error)),
            products: [],
            latestOutcome: presentationState.latestOutcome
        )
    }

    private func receiveUpdate(
        _ result: StoreKit2TransactionProcessingResult,
        generationIdentity: GenerationIdentity,
        session: StoreActiveSession
    ) {
        guard generationCanContinue(generationIdentity, session: session) else { return }
        apply(
            result,
            source: .transactionUpdate,
            generationIdentity: generationIdentity,
            session: session
        )
    }

    private func apply(
        _ result: StoreKit2TransactionProcessingResult,
        source: StoreKitRuntimeOutcomeSource,
        generationIdentity: GenerationIdentity,
        session: StoreActiveSession
    ) {
        guard generationCanContinue(generationIdentity, session: session) else { return }
        let outcome = StoreKitRuntimeProcessingOutcome(result)
        let latest: StoreKitRuntimeLatestOutcome = .processed(
            source: source,
            outcome: outcome
        )
        if case let .deferred(reason) = outcome {
            blockGenerationUntilRetry(
                failure: .transactionDeferred(reason),
                latestOutcome: latest,
                generationIdentity: generationIdentity,
                session: session
            )
            return
        }
        let nextPhase: StoreKitRuntimePresentationPhase
        if case let .pending(pendingPackID) = presentationState.phase,
           case let .deliveredAndFinished(_, deliveredPackID, _, _) = result,
           deliveredPackID == pendingPackID {
            nextPhase = .available
        } else {
            nextPhase = presentationState.phase
        }
        setPresentation(
            phase: nextPhase,
            products: presentationState.products,
            latestOutcome: latest
        )
    }

    private func purchaseDidComplete(
        _ result: Result<StoreKit2CoinPurchaseResult, StoreKitRuntimeFailure>,
        packID: CoinPackID,
        generationIdentity: GenerationIdentity,
        session: StoreActiveSession
    ) {
        guard var generation = activeGeneration,
              generation.identity === generationIdentity,
              generation.session == session else { return }
        generation.purchaseTask = nil
        activeGeneration = generation
        guard generation.retryRequiredFailure == nil else { return }

        switch result {
        case let .success(.processed(processingResult)):
            let outcome = StoreKitRuntimeProcessingOutcome(processingResult)
            let latest: StoreKitRuntimeLatestOutcome = .processed(
                source: .purchase(packID),
                outcome: outcome
            )
            if case let .deferred(reason) = outcome {
                blockGenerationUntilRetry(
                    failure: .transactionDeferred(reason),
                    latestOutcome: latest,
                    generationIdentity: generationIdentity,
                    session: session
                )
            } else {
                setPresentation(
                    phase: .available,
                    products: presentationState.products,
                    latestOutcome: latest
                )
            }
        case .success(.pending):
            setPresentation(
                phase: .pending(packID),
                products: presentationState.products,
                latestOutcome: .purchasePending(packID)
            )
        case .success(.userCancelled):
            setPresentation(
                phase: .available,
                products: presentationState.products,
                latestOutcome: .purchaseCancelled(packID)
            )
        case let .failure(failure):
            setPresentation(
                phase: .unavailable(failure),
                products: presentationState.products,
                latestOutcome: .purchaseFailed(packID: packID, failure: failure)
            )
        }
    }

    private func startupDidEnd(
        generationIdentity: GenerationIdentity,
        session: StoreActiveSession
    ) {
        guard var generation = activeGeneration,
              generation.identity === generationIdentity,
              generation.session == session else { return }
        generation.startupTask = nil
        activeGeneration = generation
    }

    private func updatesDidEnd(
        generationIdentity: GenerationIdentity,
        session: StoreActiveSession,
        wasCancelled: Bool
    ) {
        guard var generation = activeGeneration,
              generation.identity === generationIdentity,
              generation.session == session else { return }
        generation.updatesListener = nil
        generation.updatesTask = nil
        activeGeneration = generation
        guard !wasCancelled else { return }
        blockGenerationUntilRetry(
            failure: .transactionUpdatesEnded,
            latestOutcome: presentationState.latestOutcome,
            generationIdentity: generationIdentity,
            session: session
        )
    }

    private func blockGenerationUntilRetry(
        failure: StoreKitRuntimeFailure,
        latestOutcome: StoreKitRuntimeLatestOutcome?,
        generationIdentity: GenerationIdentity,
        session: StoreActiveSession
    ) {
        guard var generation = activeGeneration,
              generation.identity === generationIdentity,
              generation.session == session,
              generation.retryRequiredFailure == nil else { return }
        generation.retryRequiredFailure = failure
        generation.startupTask?.cancel()
        generation.updatesTask?.cancel()
        generation.purchaseTask?.cancel()
        activeGeneration = generation
        setPresentation(
            phase: .unavailable(failure),
            products: presentationState.products,
            latestOutcome: latestOutcome
        )
    }

    private func generationCanContinue(
        _ generationIdentity: GenerationIdentity,
        session: StoreActiveSession
    ) -> Bool {
        guard let generation = activeGeneration else { return false }
        return generation.identity === generationIdentity
            && generation.session == session
            && generation.retryRequiredFailure == nil
    }

    private func retireActiveGeneration(
        nextPhase: StoreKitRuntimePresentationPhase
    ) async {
        let listener = activeGeneration?.updatesListener
        let startupTask = activeGeneration?.startupTask
        let updatesTask = activeGeneration?.updatesTask
        let purchaseTask = activeGeneration?.purchaseTask

        // Invalidate the session before cancellation so a callback that wins a
        // race cannot publish into a replacement generation.
        activeGeneration = nil
        setPresentation(phase: nextPhase, products: [], latestOutcome: nil)
        startupTask?.cancel()
        updatesTask?.cancel()
        purchaseTask?.cancel()

        let priorReapTask = reapOperation?.task
        guard startupTask != nil || updatesTask != nil || purchaseTask != nil
                || listener != nil || priorReapTask != nil else { return }
        let reapIdentity = ReapIdentity()
        let task = Task {
            if let priorReapTask {
                await priorReapTask.value
            }
            if let listener {
                await listener.cancelAndWait()
            }
            await startupTask?.value
            await updatesTask?.value
            _ = await purchaseTask?.value
        }
        reapOperation = ReapOperation(identity: reapIdentity, task: task)
        await task.value
        if reapOperation?.identity === reapIdentity {
            reapOperation = nil
        }
    }

    private func setPresentation(
        phase: StoreKitRuntimePresentationPhase,
        products: [StoreProduct],
        latestOutcome: StoreKitRuntimeLatestOutcome?
    ) {
        presentationState = StoreKitRuntimePresentationState(
            phase: phase,
            products: products,
            latestOutcome: latestOutcome
        )
        for continuation in presentationContinuations.values {
            continuation.yield(presentationState)
        }
    }

    private func removePresentationSubscriber(_ subscriberID: UUID) {
        presentationContinuations.removeValue(forKey: subscriberID)
    }
}

extension StoreKitRuntimeCoordinator: OnlineCommerceStorePurchasing {}

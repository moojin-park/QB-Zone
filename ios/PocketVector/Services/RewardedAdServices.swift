import Foundation

enum ConsentStatus: String, Codable, Equatable, Sendable {
    case unknown
    case notRequired
    case obtained
    case denied
    case unavailable
}

struct ConsentSnapshot: Codable, Equatable, Sendable {
    let status: ConsentStatus
    let canRequestAds: Bool
    let privacyOptionsRequired: Bool

    static let unknown = ConsentSnapshot(
        status: .unknown,
        canRequestAds: false,
        privacyOptionsRequired: false
    )
}

protocol ConsentServicing: Sendable {
    func currentConsent() async -> ConsentSnapshot
    func refreshConsent() async throws -> ConsentSnapshot
    func presentPrivacyOptions() async throws -> ConsentSnapshot
}

struct RewardedAdAttempt: Codable, Equatable, Sendable {
    let binding: DurableAccountBinding
    let presentationSessionNonce: UUID
    let offerID: RewardOfferID
    let attemptID: UUID

    var presentationSession: ActiveAccountSession {
        ActiveAccountSession(binding: binding, nonce: presentationSessionNonce)
    }
}

enum RewardedAdPresentationResult: Codable, Equatable, Sendable {
    case dismissed
    case clientRewardEarned(attemptID: UUID)
}

protocol RewardedAdServing: Sendable {
    func load(offerID: RewardOfferID, session: ActiveAccountSession) async throws
    func present(_ attempt: RewardedAdAttempt) async throws -> RewardedAdPresentationResult
}

struct VerifiedRewardReceipt: Codable, Equatable, Hashable, Sendable {
    let binding: DurableAccountBinding
    let offerID: RewardOfferID
    let attemptID: UUID
    let providerTransactionID: AdProviderTransactionID
}

enum RewardedAdSettlementDisposition: String, Codable, Equatable, Sendable {
    case committed
    case alreadyCommitted
}

/// Returned only after one durable operation has both inserted (or found) the
/// provider-keyed +100 ledger entry and redeemed the five-run offer.
struct RewardedAdSettlementAcknowledgement: Codable, Equatable, Sendable {
    let session: ActiveAccountSession
    let receipt: VerifiedRewardReceipt
    let ledgerEntryID: LedgerEntryID
    let disposition: RewardedAdSettlementDisposition
    let resultingEconomyState: RewardedAdState
    let resultingEconomyRevision: UInt64
}

struct RewardedAdAccountContext: Equatable, Sendable {
    let session: ActiveAccountSession
    let economyState: RewardedAdState
    let economyRevision: UInt64
    let proof: AccountScopedEconomyProof?

    func hasCurrentEconomy(at date: Date) -> Bool {
        proof?.isCurrent(
            for: session,
            economyRevision: economyRevision,
            at: date
        ) == true
    }
}

enum RewardedAdDurableFlow: Codable, Equatable, Sendable {
    case presentationStarted(RewardedAdAttempt)
    case awaitingVerification(RewardedAdAttempt)
    case verifiedAwaitingSettlement(
        receipt: VerifiedRewardReceipt,
        commandSession: ActiveAccountSession?
    )
}

struct RewardedAdDurableState: Codable, Equatable, Sendable {
    var flow: RewardedAdDurableFlow?
    var settledProviderTransactionIDs: Set<AdProviderTransactionID>

    init(
        flow: RewardedAdDurableFlow? = nil,
        settledProviderTransactionIDs: Set<AdProviderTransactionID> = []
    ) {
        self.flow = flow
        self.settledProviderTransactionIDs = settledProviderTransactionIDs
    }
}

enum RewardedAdCoordinatorPhase: Equatable, Sendable {
    case blockedByConsent
    case blockedByEconomy
    case unavailable
    case idle(RewardOfferID)
    case loading(RewardOfferID)
    case ready(RewardOfferID)
    case presenting(RewardedAdAttempt)
    case awaitingVerification(RewardedAdAttempt)
    case awaitingSettlement(VerifiedRewardReceipt)
}

enum RewardedAdCommand: Equatable, Sendable {
    case load(offerID: RewardOfferID, session: ActiveAccountSession)
    case present(RewardedAdAttempt)
    case settleVerifiedReward(
        session: ActiveAccountSession,
        receipt: VerifiedRewardReceipt,
        ledgerEntryID: LedgerEntryID,
        coins: Int64
    )
}

struct RewardedAdCoordinatorState: Equatable, Sendable {
    private(set) var durableState: RewardedAdDurableState
    private(set) var consent: ConsentSnapshot
    private(set) var accountContext: RewardedAdAccountContext?
    private(set) var phase: RewardedAdCoordinatorPhase

    init(
        durableState: RewardedAdDurableState = RewardedAdDurableState(),
        consent: ConsentSnapshot = .unknown,
        accountContext: RewardedAdAccountContext? = nil,
        at date: Date
    ) {
        self.durableState = durableState
        self.consent = consent
        self.accountContext = accountContext
        phase = Self.flowPhase(durableState.flow)
            ?? Self.restingPhase(consent: consent, context: accountContext, at: date)
    }

    mutating func updateConsent(_ snapshot: ConsentSnapshot, at date: Date) {
        consent = snapshot
        guard durableState.flow == nil else { return }
        phase = restingPhase(at: date)
    }

    mutating func updateAccountContext(
        _ context: RewardedAdAccountContext?,
        at date: Date
    ) {
        accountContext = context
        guard durableState.flow == nil else {
            phase = Self.flowPhase(durableState.flow) ?? .blockedByEconomy
            return
        }
        phase = restingPhase(at: date)
    }

    mutating func requestLoad(at date: Date) -> RewardedAdCommand? {
        guard durableState.flow == nil,
              consent.canRequestAds,
              let context = currentContext(at: date),
              let offerID = context.economyState.eligibleOfferID,
              phase == .idle(offerID) else {
            return nil
        }
        phase = .loading(offerID)
        return .load(offerID: offerID, session: context.session)
    }

    @discardableResult
    mutating func loadDidSucceed(
        offerID: RewardOfferID,
        session: ActiveAccountSession,
        at date: Date
    ) -> Bool {
        guard durableState.flow == nil,
              consent.canRequestAds,
              let context = currentContext(at: date),
              context.session == session,
              context.economyState.eligibleOfferID == offerID,
              phase == .loading(offerID) else {
            return false
        }
        phase = .ready(offerID)
        return true
    }

    mutating func loadDidFail(
        offerID: RewardOfferID,
        session: ActiveAccountSession,
        at date: Date
    ) {
        guard accountContext?.session == session,
              phase == .loading(offerID) else {
            return
        }
        phase = restingPhase(at: date)
    }

    mutating func beginPresentation(
        attemptID: UUID,
        at date: Date
    ) -> RewardedAdCommand? {
        guard durableState.flow == nil,
              consent.canRequestAds,
              let context = currentContext(at: date),
              let offerID = context.economyState.eligibleOfferID,
              phase == .ready(offerID) else {
            return nil
        }

        let attempt = RewardedAdAttempt(
            binding: context.session.binding,
            presentationSessionNonce: context.session.nonce,
            offerID: offerID,
            attemptID: attemptID
        )
        durableState.flow = .presentationStarted(attempt)
        phase = .presenting(attempt)
        return .present(attempt)
    }

    mutating func declineOffer(at date: Date) {
        guard durableState.flow == nil else { return }
        switch phase {
        case .idle, .loading, .ready:
            phase = restingPhase(at: date)
        case .blockedByConsent, .blockedByEconomy, .unavailable, .presenting,
             .awaitingVerification, .awaitingSettlement:
            break
        }
    }

    @discardableResult
    mutating func clientRewardDidEarn(
        attemptID: UUID,
        session: ActiveAccountSession
    ) -> Bool {
        guard accountContext?.session == session,
              case let .presentationStarted(attempt) = durableState.flow,
              attempt.attemptID == attemptID,
              attempt.presentationSession == session else {
            return false
        }
        durableState.flow = .awaitingVerification(attempt)
        phase = .awaitingVerification(attempt)
        return true
    }

    @discardableResult
    mutating func presentationDidDismissWithoutReward(
        attemptID: UUID,
        session: ActiveAccountSession,
        at date: Date
    ) -> Bool {
        guard accountContext?.session == session,
              case let .presentationStarted(attempt) = durableState.flow,
              attempt.attemptID == attemptID,
              attempt.presentationSession == session else {
            return false
        }
        durableState.flow = nil
        phase = restingPhase(at: date)
        return true
    }

    mutating func verificationDidFail(
        attemptID: UUID,
        binding: DurableAccountBinding,
        at date: Date
    ) {
        guard let attempt = pendingAttempt,
              attempt.attemptID == attemptID,
              attempt.binding == binding else {
            return
        }
        durableState.flow = nil
        phase = restingPhase(at: date)
    }

    mutating func verificationDidSucceed(
        _ receipt: VerifiedRewardReceipt,
        at date: Date
    ) -> RewardedAdCommand? {
        guard !durableState.settledProviderTransactionIDs.contains(
            receipt.providerTransactionID
        ) else {
            return nil
        }

        switch durableState.flow {
        case let .presentationStarted(attempt), let .awaitingVerification(attempt):
            guard receiptMatches(receipt, attempt: attempt) else { return nil }
            durableState.flow = .verifiedAwaitingSettlement(
                receipt: receipt,
                commandSession: nil
            )
            phase = .awaitingSettlement(receipt)
            return recoveryCommands(at: date).first
        case let .verifiedAwaitingSettlement(existingReceipt, _):
            guard existingReceipt == receipt else { return nil }
            return recoveryCommands(at: date).first
        case nil:
            return nil
        }
    }

    mutating func recoveryCommands(at date: Date) -> [RewardedAdCommand] {
        guard let context = currentContext(at: date) else { return [] }

        switch durableState.flow {
        case let .verifiedAwaitingSettlement(receipt, _):
            guard receipt.binding == context.session.binding else {
                return []
            }
            durableState.flow = .verifiedAwaitingSettlement(
                receipt: receipt,
                commandSession: context.session
            )
            phase = .awaitingSettlement(receipt)
            return [settlementCommand(receipt: receipt, session: context.session)]
        case .presentationStarted, .awaitingVerification, nil:
            return []
        }
    }

    @discardableResult
    mutating func atomicSettlementDidCommit(
        _ acknowledgement: RewardedAdSettlementAcknowledgement,
        at date: Date
    ) -> Bool {
        let receipt = acknowledgement.receipt
        guard let context = currentContext(at: date),
              context.session == acknowledgement.session,
              case let .verifiedAwaitingSettlement(pendingReceipt, commandSession)
                = durableState.flow,
              pendingReceipt == receipt,
              commandSession == acknowledgement.session,
              acknowledgement.ledgerEntryID == CoinLedgerID.rewardedAd(
                providerTransactionID: receipt.providerTransactionID
              ),
              acknowledgement.resultingEconomyState.validRunsSinceReward == 0,
              acknowledgement.resultingEconomyState.eligibleOfferID == nil else {
            return false
        }

        durableState.settledProviderTransactionIDs.insert(receipt.providerTransactionID)
        durableState.flow = nil
        accountContext = RewardedAdAccountContext(
            session: acknowledgement.session,
            economyState: acknowledgement.resultingEconomyState,
            economyRevision: acknowledgement.resultingEconomyRevision,
            proof: nil
        )
        phase = restingPhase(at: date)
        return true
    }

    private var pendingAttempt: RewardedAdAttempt? {
        switch durableState.flow {
        case let .presentationStarted(attempt), let .awaitingVerification(attempt):
            attempt
        case .verifiedAwaitingSettlement, nil:
            nil
        }
    }

    private func currentContext(at date: Date) -> RewardedAdAccountContext? {
        guard let accountContext,
              accountContext.hasCurrentEconomy(at: date) else {
            return nil
        }
        return accountContext
    }

    private func restingPhase(at date: Date) -> RewardedAdCoordinatorPhase {
        Self.restingPhase(consent: consent, context: accountContext, at: date)
    }

    private static func restingPhase(
        consent: ConsentSnapshot,
        context: RewardedAdAccountContext?,
        at date: Date
    ) -> RewardedAdCoordinatorPhase {
        guard consent.canRequestAds else { return .blockedByConsent }
        guard let context, context.hasCurrentEconomy(at: date) else {
            return .blockedByEconomy
        }
        guard let offerID = context.economyState.eligibleOfferID else {
            return .unavailable
        }
        return .idle(offerID)
    }

    private static func flowPhase(
        _ flow: RewardedAdDurableFlow?
    ) -> RewardedAdCoordinatorPhase? {
        switch flow {
        case let .presentationStarted(attempt):
            .awaitingVerification(attempt)
        case let .awaitingVerification(attempt):
            .awaitingVerification(attempt)
        case let .verifiedAwaitingSettlement(receipt, _):
            .awaitingSettlement(receipt)
        case nil:
            nil
        }
    }

    private func receiptMatches(
        _ receipt: VerifiedRewardReceipt,
        attempt: RewardedAdAttempt
    ) -> Bool {
        receipt.binding == attempt.binding
            && receipt.offerID == attempt.offerID
            && receipt.attemptID == attempt.attemptID
    }

    private func settlementCommand(
        receipt: VerifiedRewardReceipt,
        session: ActiveAccountSession
    ) -> RewardedAdCommand {
        .settleVerifiedReward(
            session: session,
            receipt: receipt,
            ledgerEntryID: CoinLedgerID.rewardedAd(
                providerTransactionID: receipt.providerTransactionID
            ),
            coins: EconomyConfiguration.rewardedAdCoins
        )
    }
}

actor InMemoryConsentService: ConsentServicing {
    private var snapshot: ConsentSnapshot
    private var refreshResult: Result<ConsentSnapshot, ConsentServiceError>
    private var privacyOptionsResult: Result<ConsentSnapshot, ConsentServiceError>

    init(snapshot: ConsentSnapshot = .unknown) {
        self.snapshot = snapshot
        refreshResult = .success(snapshot)
        privacyOptionsResult = .success(snapshot)
    }

    func currentConsent() -> ConsentSnapshot {
        snapshot
    }

    func refreshConsent() throws -> ConsentSnapshot {
        let refreshed = try refreshResult.get()
        snapshot = refreshed
        return refreshed
    }

    func presentPrivacyOptions() throws -> ConsentSnapshot {
        let updated = try privacyOptionsResult.get()
        snapshot = updated
        return updated
    }

    func setRefreshResult(_ result: Result<ConsentSnapshot, ConsentServiceError>) {
        refreshResult = result
    }

    func setPrivacyOptionsResult(_ result: Result<ConsentSnapshot, ConsentServiceError>) {
        privacyOptionsResult = result
    }
}

actor InMemoryRewardedAdService: RewardedAdServing {
    private var loadFailure: RewardedAdServiceError?
    private var presentationResults: [RewardedAdPresentationResult]
    private(set) var loadRequests: [(RewardOfferID, ActiveAccountSession)] = []
    private(set) var presentedAttempts: [RewardedAdAttempt] = []

    init(presentationResults: [RewardedAdPresentationResult] = []) {
        self.presentationResults = presentationResults
    }

    func load(offerID: RewardOfferID, session: ActiveAccountSession) throws {
        if let loadFailure { throw loadFailure }
        loadRequests.append((offerID, session))
    }

    func present(_ attempt: RewardedAdAttempt) throws -> RewardedAdPresentationResult {
        guard loadRequests.contains(where: {
            $0.0 == attempt.offerID && $0.1 == attempt.presentationSession
        }) else {
            throw RewardedAdServiceError.notLoaded
        }
        presentedAttempts.append(attempt)
        return presentationResults.isEmpty ? .dismissed : presentationResults.removeFirst()
    }

    func setLoadFailure(_ failure: RewardedAdServiceError?) {
        loadFailure = failure
    }

    func appendPresentationResult(_ result: RewardedAdPresentationResult) {
        presentationResults.append(result)
    }
}

enum ConsentServiceError: Error, Equatable, Sendable {
    case unavailable
    case presentationFailed
}

enum RewardedAdServiceError: Error, Equatable, Sendable {
    case unavailable
    case notLoaded
    case presentationFailed
}

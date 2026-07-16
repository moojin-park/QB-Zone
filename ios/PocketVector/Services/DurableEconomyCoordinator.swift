import CryptoKit
import Foundation

enum DurableEconomyCloudConfigurationError: Error, Equatable, Sendable {
    case emptyRecordID
    case emptyRecordType
    case emptyPayloadFieldName
    case invalidConflictRetryLimit
}

/// Release composition supplies the CloudKit schema identifiers. There are no
/// production container, record, or field names in the durable economy layer.
struct DurableEconomyCloudConfiguration: Equatable, Sendable {
    let recordID: CloudRecordID
    let recordType: String
    let payloadFieldName: String
    let conflictRetryLimit: Int

    init(
        recordID: CloudRecordID,
        recordType: String,
        payloadFieldName: String,
        conflictRetryLimit: Int = 3
    ) throws {
        guard !recordID.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DurableEconomyCloudConfigurationError.emptyRecordID
        }
        guard !recordType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DurableEconomyCloudConfigurationError.emptyRecordType
        }
        guard !payloadFieldName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DurableEconomyCloudConfigurationError.emptyPayloadFieldName
        }
        guard conflictRetryLimit >= 0 else {
            throw DurableEconomyCloudConfigurationError.invalidConflictRetryLimit
        }

        self.recordID = recordID
        self.recordType = recordType
        self.payloadFieldName = payloadFieldName
        self.conflictRetryLimit = conflictRetryLimit
    }
}

enum DurableEconomySessionContextError: Error, Equatable, Sendable {
    case profileBindingMismatch
    case storeBindingMismatch
    case sessionNonceMismatch
}

/// The account coordinator mints one context for one active private-iCloud and
/// local-repository session. A relaunch or account switch must mint a new nonce
/// and replace the active context in `DurableEconomySessionAuthority`.
struct DurableEconomySessionContext: Equatable, Sendable {
    let cloudAccountID: CloudAccountID
    let accountBinding: DurableAccountBinding
    let profileSession: ProfileSessionToken
    let storeSession: StoreActiveSession

    init(
        cloudAccountID: CloudAccountID,
        accountBinding: DurableAccountBinding,
        profileSession: ProfileSessionToken,
        storeSession: StoreActiveSession
    ) throws {
        guard accountBinding.profileID == profileSession.profileID else {
            throw DurableEconomySessionContextError.profileBindingMismatch
        }
        guard storeSession.binding.account == accountBinding else {
            throw DurableEconomySessionContextError.storeBindingMismatch
        }
        guard storeSession.nonce == profileSession.nonce else {
            throw DurableEconomySessionContextError.sessionNonceMismatch
        }

        self.cloudAccountID = cloudAccountID
        self.accountBinding = accountBinding
        self.profileSession = profileSession
        self.storeSession = storeSession
    }
}

protocol DurableEconomySessionAuthorizing: Sendable {
    func currentContext() async -> DurableEconomySessionContext?
}

/// A small account-coordinator seam that can be shared by CloudKit, StoreKit,
/// and rewarded-ad delivery. Clearing or replacing it invalidates every
/// callback that captured the previous account or session.
actor DurableEconomySessionAuthority: DurableEconomySessionAuthorizing {
    private var context: DurableEconomySessionContext?

    init(context: DurableEconomySessionContext? = nil) {
        self.context = context
    }

    func currentContext() -> DurableEconomySessionContext? {
        context
    }

    func activate(_ context: DurableEconomySessionContext) {
        self.context = context
    }

    func invalidate() {
        context = nil
    }
}

/// Provider adapters can classify the special case where an idempotency marker
/// proves that the mutation committed, but the target record has since moved
/// forward. The coordinator must refresh; it must never submit the mutation a
/// second time in response to this signal.
struct CloudCommittedOperationRefresh: Equatable, Sendable {
    let operationID: OperationID
    let recordIDs: [CloudRecordID]
}

protocol CloudCommittedOperationRefreshClassifying: Error {
    var committedOperationRefresh: CloudCommittedOperationRefresh? { get }
}

extension CloudKitCloudSyncError: CloudCommittedOperationRefreshClassifying {
    var committedOperationRefresh: CloudCommittedOperationRefresh? {
        guard case let .committedOperationRequiresRefresh(operationID, recordIDs) = self else {
            return nil
        }
        return CloudCommittedOperationRefresh(
            operationID: operationID,
            recordIDs: recordIDs
        )
    }
}

protocol DurableEconomyLocalPersisting: Sendable {
    func durableEconomySnapshot() async throws -> LocalPlayerProfileSnapshot
    func durableConfirmPendingCredits(
        _ entryIDs: Set<LedgerEntryID>,
        session: ProfileSessionToken,
        confirmation: DurableEconomyConfirmation,
        savedAt: Date
    ) async throws -> LocalPlayerProfileSnapshot
    func durableRecordConfirmedCredit(
        _ entry: CoinLedgerEntry,
        session: ProfileSessionToken,
        confirmation: DurableEconomyConfirmation,
        savedAt: Date
    ) async throws -> LocalPlayerProfileSnapshot
    func durablePrepareUnlock(
        itemID: CatalogItemID,
        operationID: OperationID,
        session: ProfileSessionToken
    ) async throws -> DurableCatalogUnlockRequest
    func durableApplyUnlock(
        using receipt: DurableCatalogUnlockReceipt,
        session: ProfileSessionToken,
        at date: Date
    ) async throws -> CatalogUnlockOutcome
    func durableSettleRewardedAd(
        using receipt: DurableRewardedAdReceipt,
        session: ProfileSessionToken,
        savedAt: Date
    ) async throws -> RewardedAdSettlementOutcome
}

extension LocalPlayerProfileRepository: DurableEconomyLocalPersisting {
    func durableEconomySnapshot() async throws -> LocalPlayerProfileSnapshot {
        try snapshot()
    }

    func durableConfirmPendingCredits(
        _ entryIDs: Set<LedgerEntryID>,
        session: ProfileSessionToken,
        confirmation: DurableEconomyConfirmation,
        savedAt: Date
    ) async throws -> LocalPlayerProfileSnapshot {
        try confirmPendingCredits(
            entryIDs,
            session: session,
            confirmation: confirmation,
            savedAt: savedAt
        )
    }

    func durableRecordConfirmedCredit(
        _ entry: CoinLedgerEntry,
        session: ProfileSessionToken,
        confirmation: DurableEconomyConfirmation,
        savedAt: Date
    ) async throws -> LocalPlayerProfileSnapshot {
        try recordConfirmedCredit(
            entry,
            session: session,
            confirmation: confirmation,
            savedAt: savedAt
        )
    }

    func durablePrepareUnlock(
        itemID: CatalogItemID,
        operationID: OperationID,
        session: ProfileSessionToken
    ) async throws -> DurableCatalogUnlockRequest {
        try prepareUnlock(
            itemID: itemID,
            operationID: operationID,
            session: session
        )
    }

    func durableApplyUnlock(
        using receipt: DurableCatalogUnlockReceipt,
        session: ProfileSessionToken,
        at date: Date
    ) async throws -> CatalogUnlockOutcome {
        try unlock(using: receipt, session: session, at: date)
    }

    func durableSettleRewardedAd(
        using receipt: DurableRewardedAdReceipt,
        session: ProfileSessionToken,
        savedAt: Date
    ) async throws -> RewardedAdSettlementOutcome {
        try settleRewardedAd(using: receipt, session: session, savedAt: savedAt)
    }
}

enum DurableEconomyCloudCommitStatus: Equatable, Sendable {
    case committed
    case alreadyCommitted
    case committedThenRefreshed
}

/// `CloudAtomicWriteReceipt` alone cannot represent a committed operation whose
/// original change tag was superseded. This receipt always names the freshly
/// observed economy head and explicitly describes how durability was proven.
struct DurableEconomyCloudCommitReceipt: Equatable, Sendable {
    let accountID: CloudAccountID
    let operationID: OperationID
    let recordID: CloudRecordID
    let observedChangeTag: CloudChangeTag
    let cloudEconomyRevision: UInt64
    let status: DurableEconomyCloudCommitStatus
}

struct DurablePendingCreditResult: Equatable, Sendable {
    let snapshot: LocalPlayerProfileSnapshot
    let entryIDs: Set<LedgerEntryID>
    let cloudReceipt: DurableEconomyCloudCommitReceipt
}

struct DurableCatalogUnlockResult: Equatable, Sendable {
    let outcome: CatalogUnlockOutcome
    let cloudReceipt: DurableEconomyCloudCommitReceipt
}

/// This is intentionally downstream of provider verification. It does not
/// validate an ad SDK callback or invent server-side verification; it only
/// durably delivers evidence accepted by the future SSV coordinator.
struct VerifiedRewardedAdDurableDeliveryRequest: Equatable, Sendable {
    let session: ProfileSessionToken
    let offerID: RewardOfferID
    let providerTransactionID: AdProviderTransactionID
    let rewardedAt: Date
}

struct DurableRewardedAdDeliveryResult: Equatable, Sendable {
    let outcome: RewardedAdSettlementOutcome
    let cloudReceipt: DurableEconomyCloudCommitReceipt
}

protocol VerifiedRewardedAdDurableCreditDelivering: Sendable {
    func deliverVerifiedReward(
        _ request: VerifiedRewardedAdDurableDeliveryRequest
    ) async throws -> DurableRewardedAdDeliveryResult
}

enum DurableEconomyCoordinatorError: Error, Equatable, Sendable {
    case noCurrentSession
    case staleSession
    case profileSessionMismatch
    case cloudAccountUnavailable
    case cloudAccountMismatch
    case emptyCreditSet
    case pendingCreditMissing(LedgerEntryID)
    case invalidCredit(LedgerEntryID)
    case invalidStoreKitRequest
    case invalidCatalogUnlockRequest
    case invalidRewardedAdRequest
    case malformedCloudRecord
    case duplicateCloudRecord
    case cloudStateBindingMismatch
    case cloudStateDiverged
    case cloudLedgerCollision(LedgerEntryID)
    case cloudUnlockCollision(CatalogItemID)
    case cloudRewardCollision(RewardOfferID)
    case cloudBalanceInvalid
    case cloudRevisionOverflow
    case conflictRetryLimitReached
    case cloudReceiptMismatch
    case committedOperationRefreshMismatch
    case committedOperationMissingAfterRefresh(OperationID)
    case economyRevisionChanged(expected: UInt64, actual: UInt64)
}

/// Serializes every economy mutation for one active account/profile session.
/// The CloudKit economy head commits first; the local repository is updated
/// only from a bound receipt after the account, session, and local economy
/// revision have been revalidated.
actor DurableEconomyCoordinator: StoreKit2DurableCreditDelivering,
    VerifiedRewardedAdDurableCreditDelivering
{
    private let context: DurableEconomySessionContext
    private let sessionAuthority: any DurableEconomySessionAuthorizing
    private let repository: any DurableEconomyLocalPersisting
    private let cloud: any CloudSyncTransport
    private let configuration: DurableEconomyCloudConfiguration
    private let catalog: LaunchCatalog
    private let now: @Sendable () -> Date
    private var mutationIsRunning = false
    private var mutationWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        context: DurableEconomySessionContext,
        sessionAuthority: any DurableEconomySessionAuthorizing,
        repository: any DurableEconomyLocalPersisting,
        cloud: any CloudSyncTransport,
        configuration: DurableEconomyCloudConfiguration,
        catalog: LaunchCatalog = .approved,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.context = context
        self.sessionAuthority = sessionAuthority
        self.repository = repository
        self.cloud = cloud
        self.configuration = configuration
        self.catalog = catalog
        self.now = now
    }

    func confirmAllPendingCredits() async throws -> DurablePendingCreditResult? {
        await acquireMutationGate()
        defer { releaseMutationGate() }
        return try await confirmAllPendingCreditsImpl()
    }

    private func confirmAllPendingCreditsImpl() async throws -> DurablePendingCreditResult? {
        let snapshot = try await validatedSnapshot()
        guard !snapshot.pendingLedgerEntryIDs.isEmpty else { return nil }
        return try await confirmPendingCreditsImpl(
            snapshot.pendingLedgerEntryIDs,
            session: snapshot.session
        )
    }

    func confirmPendingCredits(
        _ entryIDs: Set<LedgerEntryID>,
        session: ProfileSessionToken
    ) async throws -> DurablePendingCreditResult {
        await acquireMutationGate()
        defer { releaseMutationGate() }
        return try await confirmPendingCreditsImpl(entryIDs, session: session)
    }

    private func confirmPendingCreditsImpl(
        _ entryIDs: Set<LedgerEntryID>,
        session: ProfileSessionToken
    ) async throws -> DurablePendingCreditResult {
        guard !entryIDs.isEmpty else {
            throw DurableEconomyCoordinatorError.emptyCreditSet
        }
        let snapshot = try await validatedSnapshot(expectedSession: session)
        var entries: [LedgerEntryID: CoinLedgerEntry] = [:]
        for entryID in entryIDs {
            guard let entry = snapshot.ledger[entryID] else {
                throw DurableEconomyCoordinatorError.pendingCreditMissing(entryID)
            }
            guard entry.delta > 0 else {
                throw DurableEconomyCoordinatorError.invalidCredit(entryID)
            }
            entries[entryID] = entry
        }

        let operationID = mutationOperationID(
            kind: "pending-credit",
            entryIDs: entryIDs
        )
        let committed = try await commitCreditMutation(
            entries: entries,
            kind: .pendingCredits,
            operationID: operationID,
            sourceSnapshot: snapshot
        )
        try await revalidateAfterCloudCommit(sourceSnapshot: snapshot)

        let confirmation = DurableEconomyConfirmation(
            confirmationID: operationID,
            session: session,
            entries: entries,
            expectedEconomyRevision: snapshot.economyRevision,
            confirmedBalanceBefore: snapshot.coinBalances.confirmed,
            confirmedAt: now(),
            authority: .durablePrivateCloud
        )
        let saved = try await repository.durableConfirmPendingCredits(
            entryIDs,
            session: session,
            confirmation: confirmation,
            savedAt: confirmation.confirmedAt
        )
        try await requireCurrentContext()
        return DurablePendingCreditResult(
            snapshot: saved,
            entryIDs: entryIDs,
            cloudReceipt: committed.receipt
        )
    }

    func deliver(
        _ request: StoreKit2DurableDeliveryRequest
    ) async throws -> StoreKit2DurableDeliveryAcknowledgement {
        await acquireMutationGate()
        defer { releaseMutationGate() }
        return try await deliverImpl(request)
    }

    private func deliverImpl(
        _ request: StoreKit2DurableDeliveryRequest
    ) async throws -> StoreKit2DurableDeliveryAcknowledgement {
        guard request.session == context.storeSession,
              request.session.binding.account == context.accountBinding,
              request.session.nonce == context.profileSession.nonce,
              request.transaction.verification == .verified,
              request.transaction.appAccountToken == request.session.binding.appAccountToken,
              request.transaction.packID == request.pack.id,
              request.ledgerEntry.id == CoinLedgerID.storeKit(
                  transactionID: request.transaction.transactionID
              ),
              request.ledgerEntry.delta == request.pack.coins,
              case let .storeKit(transactionID, packID) = request.ledgerEntry.reason,
              transactionID == request.transaction.transactionID,
              packID == request.pack.id,
              EconomyConfiguration.coinPacks.first(where: { $0.id == request.pack.id })
                == request.pack,
              PersistedEconomyRulesV1.coinPackCoins[request.pack.id] == request.pack.coins
        else {
            throw DurableEconomyCoordinatorError.invalidStoreKitRequest
        }

        let snapshot = try await validatedSnapshot(
            expectedSession: context.profileSession
        )
        let operationID = mutationOperationID(
            kind: "storekit-credit",
            entryIDs: [request.ledgerEntry.id]
        )
        let committed = try await commitCreditMutation(
            entries: [request.ledgerEntry.id: request.ledgerEntry],
            kind: .storeKit,
            operationID: operationID,
            sourceSnapshot: snapshot
        )
        try await revalidateAfterCloudCommit(sourceSnapshot: snapshot)

        let confirmation = DurableEconomyConfirmation(
            confirmationID: operationID,
            session: snapshot.session,
            entries: [request.ledgerEntry.id: request.ledgerEntry],
            expectedEconomyRevision: snapshot.economyRevision,
            confirmedBalanceBefore: snapshot.coinBalances.confirmed,
            confirmedAt: now(),
            authority: .durablePrivateCloud
        )
        _ = try await repository.durableRecordConfirmedCredit(
            request.ledgerEntry,
            session: snapshot.session,
            confirmation: confirmation,
            savedAt: confirmation.confirmedAt
        )
        try await requireCurrentContext()

        let deliveryStatus: StoreKit2DurableDeliveryStatus =
            committed.receipt.status == .committed ? .committed : .alreadyCommitted
        return StoreKit2DurableDeliveryAcknowledgement(
            session: request.session,
            transactionID: request.transaction.transactionID,
            ledgerEntryID: request.ledgerEntry.id,
            status: deliveryStatus
        )
    }

    func unlock(
        itemID: CatalogItemID,
        requestOperationID: OperationID,
        session: ProfileSessionToken
    ) async throws -> DurableCatalogUnlockResult {
        await acquireMutationGate()
        defer { releaseMutationGate() }
        return try await unlockImpl(
            itemID: itemID,
            requestOperationID: requestOperationID,
            session: session
        )
    }

    private func unlockImpl(
        itemID: CatalogItemID,
        requestOperationID: OperationID,
        session: ProfileSessionToken
    ) async throws -> DurableCatalogUnlockResult {
        let snapshot = try await validatedSnapshot(expectedSession: session)
        guard let item = catalog.item(id: itemID) else {
            throw LocalPlayerRepositoryError.inventory(.unknownCatalogItem(itemID))
        }
        let ledgerID = CoinLedgerID.catalogUnlock(itemID: itemID)
        let price = PersistedEconomyRulesV1.catalogPrice(for: item)
        try validateSourceUnlockPrerequisites(
            item: item,
            inventory: snapshot.player.inventory
        )
        let operationID = mutationOperationID(
            kind: "catalog-unlock",
            entryIDs: [ledgerID]
        )

        if itemIsOwned(item, inventory: snapshot.player.inventory) {
            guard let localEntry = snapshot.ledger[ledgerID] else {
                throw DurableEconomyCoordinatorError.cloudStateDiverged
            }
            let committed = try await commitExistingUnlockMutation(
                itemID: itemID,
                entry: localEntry,
                operationID: operationID,
                sourceSnapshot: snapshot
            )
            return DurableCatalogUnlockResult(
                outcome: CatalogUnlockOutcome(
                    itemID: itemID,
                    price: price,
                    wasAlreadyUnlocked: true,
                    confirmedBalanceAfter: snapshot.coinBalances.confirmed
                ),
                cloudReceipt: committed.receipt
            )
        }

        let request = try await repository.durablePrepareUnlock(
            itemID: itemID,
            operationID: requestOperationID,
            session: session
        )
        try validateCatalogUnlockRequest(
            request,
            requestOperationID: requestOperationID,
            item: item,
            ledgerID: ledgerID,
            price: price,
            sourceSnapshot: snapshot
        )
        let createdAt = now()
        let committed = try await commitUnlockMutation(
            item: item,
            request: request,
            operationID: operationID,
            sourceSnapshot: snapshot,
            createdAt: createdAt
        )
        try await revalidateAfterCloudCommit(sourceSnapshot: snapshot)

        guard let committedEntry = committed.entries[ledgerID] else {
            throw DurableEconomyCoordinatorError.malformedCloudRecord
        }
        let confirmedBalanceAfter = try cloudBalance(committed.state)
        let receipt = DurableCatalogUnlockReceipt(
            receiptID: operationID,
            requestOperationID: requestOperationID,
            session: session,
            itemID: itemID,
            ledgerEntryID: ledgerID,
            price: price,
            expectedEconomyRevision: snapshot.economyRevision,
            confirmedBalanceBefore: snapshot.coinBalances.confirmed,
            confirmedBalanceAfter: confirmedBalanceAfter,
            // A retry after a cloud-first commit must reproduce the immutable
            // ledger entry locally. The cloud marker therefore owns the
            // original timestamp instead of a newly sampled wall clock.
            confirmedAt: committedEntry.createdAt,
            authority: .durablePrivateCloud
        )
        let outcome = try await repository.durableApplyUnlock(
            using: receipt,
            session: session,
            at: now()
        )
        try await requireCurrentContext()
        return DurableCatalogUnlockResult(
            outcome: outcome,
            cloudReceipt: committed.receipt
        )
    }

    func deliverVerifiedReward(
        _ request: VerifiedRewardedAdDurableDeliveryRequest
    ) async throws -> DurableRewardedAdDeliveryResult {
        await acquireMutationGate()
        defer { releaseMutationGate() }
        return try await deliverVerifiedRewardImpl(request)
    }

    private func deliverVerifiedRewardImpl(
        _ request: VerifiedRewardedAdDurableDeliveryRequest
    ) async throws -> DurableRewardedAdDeliveryResult {
        guard request.session == context.profileSession,
              request.rewardedAt.timeIntervalSince1970.isFinite
        else {
            throw DurableEconomyCoordinatorError.invalidRewardedAdRequest
        }
        let snapshot = try await validatedSnapshot(expectedSession: request.session)
        let ledgerID = CoinLedgerID.rewardedAd(
            providerTransactionID: request.providerTransactionID
        )
        let entry = CoinLedgerEntry(
            id: ledgerID,
            delta: PersistedEconomyRulesV1.rewardedAdCoins,
            reason: .rewardedAd(
                offerID: request.offerID,
                providerTransactionID: request.providerTransactionID
            ),
            createdAt: request.rewardedAt
        )
        if let localEntry = snapshot.ledger[ledgerID] {
            guard localEntry == entry,
                  !snapshot.pendingLedgerEntryIDs.contains(ledgerID)
            else {
                throw DurableEconomyCoordinatorError.cloudLedgerCollision(ledgerID)
            }
        } else if snapshot.player.rewardedAdState.eligibleOfferID != request.offerID {
            throw LocalPlayerRepositoryError.rewardedOfferNotEligible(request.offerID)
        }
        let operationID = mutationOperationID(
            kind: "rewarded-ad-credit",
            entryIDs: [ledgerID]
        )
        let committed = try await commitRewardedAdMutation(
            entry: entry,
            offerID: request.offerID,
            providerTransactionID: request.providerTransactionID,
            operationID: operationID,
            sourceSnapshot: snapshot
        )
        try await revalidateAfterCloudCommit(sourceSnapshot: snapshot)

        let receipt = DurableRewardedAdReceipt(
            receiptID: operationID,
            session: request.session,
            offerID: request.offerID,
            providerTransactionID: request.providerTransactionID,
            expectedEconomyRevision: snapshot.economyRevision,
            confirmedBalanceBefore: snapshot.coinBalances.confirmed,
            rewardedAt: request.rewardedAt,
            authority: .durablePrivateCloud
        )
        let outcome = try await repository.durableSettleRewardedAd(
            using: receipt,
            session: request.session,
            savedAt: now()
        )
        try await requireCurrentContext()
        return DurableRewardedAdDeliveryResult(
            outcome: outcome,
            cloudReceipt: committed.receipt
        )
    }
}

private extension DurableEconomyCoordinator {
    enum MutationKind: String, Codable, Equatable, Sendable {
        case pendingCredits = "pending-credits"
        case storeKit = "storekit"
        case catalogUnlock = "catalog-unlock"
        case rewardedAd = "rewarded-ad"
    }

    struct MutationBinding: Codable, Equatable, Sendable {
        let cloudAccountID: CloudAccountID
        let accountBinding: DurableAccountBinding
        let profileAccountIdentity: PlayerAccountIdentity
        let profileSessionNonce: UUID
        let sourceEconomyRevision: UInt64
        let operationID: OperationID
        let kind: MutationKind
    }

    struct CloudLedgerRecord: Codable, Equatable, Sendable {
        let entry: CoinLedgerEntry
        let binding: MutationBinding
    }

    struct RewardRedemption: Codable, Equatable, Sendable {
        let offerID: RewardOfferID
        let providerTransactionID: AdProviderTransactionID
        let ledgerEntryID: LedgerEntryID
    }

    /// A fixed-width commitment to the complete immutable marker set. The XOR
    /// accumulator is order-independent so the local full ledger can reproduce
    /// it without downloading history. Entry count prevents duplicate
    /// cancellation, balance preserves the authoritative spendable total, and
    /// every individual ID remains indefinitely provable through its immutable
    /// marker record.
    struct LedgerAccumulator: Codable, Equatable, Sendable {
        static let digestByteCount = 32

        var entryCount: UInt64
        var confirmedBalance: Int64
        var digest: Data

        static let empty = LedgerAccumulator(
            entryCount: 0,
            confirmedBalance: 0,
            digest: Data(repeating: 0, count: digestByteCount)
        )
    }

    struct CloudLedgerMarkerV1: Codable, Equatable, Sendable {
        static let schemaVersion = 1

        let schemaVersion: Int
        let headRecordID: CloudRecordID
        let record: CloudLedgerRecord
    }

    struct CloudRewardOfferMarkerV1: Codable, Equatable, Sendable {
        static let schemaVersion = 1

        let schemaVersion: Int
        let headRecordID: CloudRecordID
        let redemption: RewardRedemption
        let binding: MutationBinding
    }

    /// The mutable account head is deliberately constant-size with respect to
    /// play, purchase, and rewarded-ad history. Only `unlockedItemIDs` grows,
    /// and that set is strictly bounded by the finite launch catalog. Full
    /// ledger entries and reward-offer dedupe keys live in deterministic,
    /// immutable records written atomically with this head.
    struct CloudAccountHeadV2: Codable, Equatable, Sendable {
        static let schemaVersion = 2

        let schemaVersion: Int
        let cloudAccountID: CloudAccountID
        let accountBinding: DurableAccountBinding
        let profileAccountIdentity: PlayerAccountIdentity
        var revision: UInt64
        var ledgerAccumulator: LedgerAccumulator
        var unlockedItemIDs: [CatalogItemID]

        mutating func appendUnlockedItem(_ itemID: CatalogItemID) {
            unlockedItemIDs.append(itemID)
            unlockedItemIDs.sort { $0.rawValue < $1.rawValue }
        }
    }

    struct LoadedCloudState: Sendable {
        let state: CloudAccountHeadV2?
        let changeTag: CloudChangeTag?
        let ledgerMarkers: [LedgerEntryID: CloudLedgerMarkerV1]
        let rewardOfferMarkers: [RewardOfferID: CloudRewardOfferMarkerV1]
    }

    struct CommittedMutation: Sendable {
        let state: CloudAccountHeadV2
        let receipt: DurableEconomyCloudCommitReceipt
        let entries: [LedgerEntryID: CoinLedgerEntry]
    }

    struct MutationPlan: Sendable {
        let kind: MutationKind
        let entries: [LedgerEntryID: CoinLedgerEntry]
        let unlockedItemID: CatalogItemID?
        let rewardRedemption: RewardRedemption?
        let requiredBalanceBefore: Int64?
        let recoversExistingCatalogUnlockTimestamp: Bool
    }

    func validatedSnapshot(
        expectedSession: ProfileSessionToken? = nil
    ) async throws -> LocalPlayerProfileSnapshot {
        try await requireCurrentContext()
        let snapshot = try await repository.durableEconomySnapshot()
        guard snapshot.session == context.profileSession else {
            throw DurableEconomyCoordinatorError.profileSessionMismatch
        }
        if let expectedSession, snapshot.session != expectedSession {
            throw DurableEconomyCoordinatorError.staleSession
        }
        return snapshot
    }

    func requireCurrentContext() async throws {
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
    }

    func revalidateAfterCloudCommit(
        sourceSnapshot: LocalPlayerProfileSnapshot
    ) async throws {
        let current = try await validatedSnapshot(
            expectedSession: sourceSnapshot.session
        )
        guard current.economyRevision == sourceSnapshot.economyRevision else {
            throw DurableEconomyCoordinatorError.economyRevisionChanged(
                expected: sourceSnapshot.economyRevision,
                actual: current.economyRevision
            )
        }
    }

    func loadCloudState(
        entryIDs: Set<LedgerEntryID> = [],
        rewardOfferIDs: Set<RewardOfferID> = []
    ) async throws -> LoadedCloudState {
        try await requireCurrentContext()

        let ledgerIDsByRecordID = Dictionary(
            uniqueKeysWithValues: entryIDs.map { (ledgerMarkerRecordID(for: $0), $0) }
        )
        let offersByRecordID = Dictionary(
            uniqueKeysWithValues: rewardOfferIDs.map {
                (rewardOfferMarkerRecordID(for: $0), $0)
            }
        )
        let requestedIDs = [configuration.recordID]
            + Array(ledgerIDsByRecordID.keys)
            + Array(offersByRecordID.keys)
        guard Set(requestedIDs).count == requestedIDs.count else {
            throw DurableEconomyCoordinatorError.malformedCloudRecord
        }

        let records = try await cloud.records(
            accountID: context.cloudAccountID,
            ids: requestedIDs.sorted { $0.rawValue < $1.rawValue }
        )
        try await requireCurrentContext()
        guard records.count <= requestedIDs.count,
              Set(records.map(\.id)).count == records.count,
              records.allSatisfy({ requestedIDs.contains($0.id) })
        else {
            throw DurableEconomyCoordinatorError.duplicateCloudRecord
        }

        let recordsByID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        let headRecord = recordsByID[configuration.recordID]
        let state: CloudAccountHeadV2?
        if let headRecord {
            state = try decodeCloudPayload(CloudAccountHeadV2.self, from: headRecord)
            try validateCloudState(state!)
        } else {
            state = nil
        }

        var ledgerMarkers: [LedgerEntryID: CloudLedgerMarkerV1] = [:]
        for (recordID, entryID) in ledgerIDsByRecordID {
            guard let record = recordsByID[recordID] else { continue }
            let marker = try decodeCloudPayload(CloudLedgerMarkerV1.self, from: record)
            guard marker.schemaVersion == CloudLedgerMarkerV1.schemaVersion,
                  marker.headRecordID == configuration.recordID,
                  marker.record.entry.id == entryID
            else {
                throw DurableEconomyCoordinatorError.malformedCloudRecord
            }
            try validateCloudLedgerRecord(marker.record)
            ledgerMarkers[entryID] = marker
        }

        var rewardOfferMarkers: [RewardOfferID: CloudRewardOfferMarkerV1] = [:]
        for (recordID, offerID) in offersByRecordID {
            guard let record = recordsByID[recordID] else { continue }
            let marker = try decodeCloudPayload(
                CloudRewardOfferMarkerV1.self,
                from: record
            )
            guard marker.schemaVersion == CloudRewardOfferMarkerV1.schemaVersion,
                  marker.headRecordID == configuration.recordID,
                  marker.redemption.offerID == offerID,
                  marker.redemption.ledgerEntryID == CoinLedgerID.rewardedAd(
                      providerTransactionID: marker.redemption.providerTransactionID
                  ),
                  marker.binding.kind == .rewardedAd
            else {
                throw DurableEconomyCoordinatorError.malformedCloudRecord
            }
            try validateMutationBinding(marker.binding)
            rewardOfferMarkers[offerID] = marker
        }

        guard state != nil || (ledgerMarkers.isEmpty && rewardOfferMarkers.isEmpty) else {
            throw DurableEconomyCoordinatorError.cloudStateDiverged
        }
        return LoadedCloudState(
            state: state,
            changeTag: headRecord?.changeTag,
            ledgerMarkers: ledgerMarkers,
            rewardOfferMarkers: rewardOfferMarkers
        )
    }

    func validatedState(
        from loaded: LoadedCloudState,
        allowCreation: Bool = true
    ) throws -> CloudAccountHeadV2 {
        if let state = loaded.state { return state }
        guard allowCreation else {
            throw DurableEconomyCoordinatorError.cloudStateDiverged
        }
        return CloudAccountHeadV2(
            schemaVersion: CloudAccountHeadV2.schemaVersion,
            cloudAccountID: context.cloudAccountID,
            accountBinding: context.accountBinding,
            profileAccountIdentity: context.profileSession.accountIdentity,
            revision: 0,
            ledgerAccumulator: .empty,
            unlockedItemIDs: []
        )
    }

    func validateCloudState(_ state: CloudAccountHeadV2) throws {
        guard state.schemaVersion == CloudAccountHeadV2.schemaVersion,
              state.cloudAccountID == context.cloudAccountID,
              state.accountBinding == context.accountBinding,
              state.profileAccountIdentity == context.profileSession.accountIdentity
        else {
            throw DurableEconomyCoordinatorError.cloudStateBindingMismatch
        }

        guard state.ledgerAccumulator.digest.count == LedgerAccumulator.digestByteCount,
              state.ledgerAccumulator.confirmedBalance >= 0,
              Set(state.unlockedItemIDs).count == state.unlockedItemIDs.count,
              state.unlockedItemIDs.count <= catalog.unlockableItems.count,
              Set(state.unlockedItemIDs).isSubset(
                  of: Set(catalog.unlockableItems.map(\.id))
              )
        else {
            throw DurableEconomyCoordinatorError.malformedCloudRecord
        }
        if state.ledgerAccumulator.entryCount == 0 {
            guard state.ledgerAccumulator.confirmedBalance == 0,
                  state.ledgerAccumulator.digest
                    == LedgerAccumulator.empty.digest,
                  state.unlockedItemIDs.isEmpty
            else {
                throw DurableEconomyCoordinatorError.malformedCloudRecord
            }
        }

        try validateCloudUnlockPrerequisites(state)
    }

    func validateCloudLedgerRecord(_ record: CloudLedgerRecord) throws {
        try validateMutationBinding(record.binding)
        let entry = record.entry
        let valid: Bool
        switch entry.reason {
        case let .gameplay(runID, economyVersion):
            let rules = PersistedEconomyRulesV1.runRules(for: economyVersion)
            let maximumReward = rules.map {
                $0.baseRunCoins + $0.maximumScoreCoins + $0.accuracyBonusCoins
            }
            valid = record.binding.kind == .pendingCredits
                && entry.id == CoinLedgerID.gameplay(runID: runID)
                && rules != nil
                && entry.delta >= (rules?.baseRunCoins ?? .max)
                && entry.delta <= (maximumReward ?? .min)
        case let .signingBonus(version):
            valid = record.binding.kind == .pendingCredits
                && version == PersistedEconomyRulesV1.signingBonusVersion
                && entry.id == CoinLedgerID.signingBonus(version: version)
                && entry.delta == PersistedEconomyRulesV1.signingBonusCoins
        case let .rewardedAd(_, providerTransactionID):
            valid = record.binding.kind == .rewardedAd
                && entry.id == CoinLedgerID.rewardedAd(
                    providerTransactionID: providerTransactionID
                )
                && entry.delta == PersistedEconomyRulesV1.rewardedAdCoins
        case let .storeKit(transactionID, packID):
            valid = record.binding.kind == .storeKit
                && entry.id == CoinLedgerID.storeKit(transactionID: transactionID)
                && entry.delta == PersistedEconomyRulesV1.coinPackCoins[packID]
        case let .catalogUnlock(itemID):
            let item = catalog.item(id: itemID)
            valid = record.binding.kind == .catalogUnlock
                && entry.id == CoinLedgerID.catalogUnlock(itemID: itemID)
                && item.map {
                    entry.delta == -PersistedEconomyRulesV1.catalogPrice(for: $0)
                } == true
        }
        guard valid, entry.createdAt.timeIntervalSince1970.isFinite else {
            throw DurableEconomyCoordinatorError.malformedCloudRecord
        }
    }

    func validateMutationBinding(_ binding: MutationBinding) throws {
        guard binding.cloudAccountID == context.cloudAccountID,
              binding.accountBinding == context.accountBinding,
              binding.profileAccountIdentity == context.profileSession.accountIdentity,
              !binding.operationID.rawValue.isEmpty
        else {
            throw DurableEconomyCoordinatorError.malformedCloudRecord
        }
    }

    func decodeCloudPayload<T: Decodable>(
        _ type: T.Type,
        from record: CloudRecord
    ) throws -> T {
        guard record.recordType == configuration.recordType,
              let payload = record.fields[configuration.payloadFieldName]
        else {
            throw DurableEconomyCoordinatorError.malformedCloudRecord
        }
        do {
            return try JSONDecoder().decode(type, from: payload)
        } catch {
            throw DurableEconomyCoordinatorError.malformedCloudRecord
        }
    }

    func commitCreditMutation(
        entries: [LedgerEntryID: CoinLedgerEntry],
        kind: MutationKind,
        operationID: OperationID,
        sourceSnapshot: LocalPlayerProfileSnapshot
    ) async throws -> CommittedMutation {
        try await commitMutation(
            operationID: operationID,
            sourceSnapshot: sourceSnapshot,
            plan: MutationPlan(
                kind: kind,
                entries: entries,
                unlockedItemID: nil,
                rewardRedemption: nil,
                requiredBalanceBefore: nil,
                recoversExistingCatalogUnlockTimestamp: false
            )
        )
    }

    func commitExistingUnlockMutation(
        itemID: CatalogItemID,
        entry: CoinLedgerEntry,
        operationID: OperationID,
        sourceSnapshot: LocalPlayerProfileSnapshot
    ) async throws -> CommittedMutation {
        try await commitMutation(
            operationID: operationID,
            sourceSnapshot: sourceSnapshot,
            plan: MutationPlan(
                kind: .catalogUnlock,
                entries: [entry.id: entry],
                unlockedItemID: itemID,
                rewardRedemption: nil,
                requiredBalanceBefore: nil,
                recoversExistingCatalogUnlockTimestamp: false
            )
        )
    }

    func validateCreditEntries(
        _ entries: [LedgerEntryID: CoinLedgerEntry]
    ) throws {
        for (entryID, entry) in entries {
            guard entryID == entry.id, entry.delta > 0 else {
                throw DurableEconomyCoordinatorError.invalidCredit(entryID)
            }
        }
    }

    func validateCatalogUnlockRequest(
        _ request: DurableCatalogUnlockRequest,
        requestOperationID: OperationID,
        item: CatalogItemDescriptor,
        ledgerID: LedgerEntryID,
        price: Int64,
        sourceSnapshot: LocalPlayerProfileSnapshot
    ) throws {
        guard !requestOperationID.rawValue.isEmpty,
              request.operationID == requestOperationID,
              request.session == sourceSnapshot.session,
              request.itemID == item.id,
              request.ledgerEntryID == ledgerID,
              request.price == price,
              request.expectedEconomyRevision == sourceSnapshot.economyRevision,
              request.confirmedBalanceBefore
                == sourceSnapshot.coinBalances.confirmed
        else {
            throw DurableEconomyCoordinatorError.invalidCatalogUnlockRequest
        }
    }

    func commitUnlockMutation(
        item: CatalogItemDescriptor,
        request: DurableCatalogUnlockRequest,
        operationID: OperationID,
        sourceSnapshot: LocalPlayerProfileSnapshot,
        createdAt: Date
    ) async throws -> CommittedMutation {
        let entry = CoinLedgerEntry(
            id: request.ledgerEntryID,
            delta: -request.price,
            reason: .catalogUnlock(itemID: request.itemID),
            createdAt: createdAt
        )
        return try await commitMutation(
            operationID: operationID,
            sourceSnapshot: sourceSnapshot,
            plan: MutationPlan(
                kind: .catalogUnlock,
                entries: [request.ledgerEntryID: entry],
                unlockedItemID: item.id,
                rewardRedemption: nil,
                requiredBalanceBefore: request.confirmedBalanceBefore,
                recoversExistingCatalogUnlockTimestamp: true
            )
        )
    }

    func commitRewardedAdMutation(
        entry: CoinLedgerEntry,
        offerID: RewardOfferID,
        providerTransactionID: AdProviderTransactionID,
        operationID: OperationID,
        sourceSnapshot: LocalPlayerProfileSnapshot
    ) async throws -> CommittedMutation {
        try await commitMutation(
            operationID: operationID,
            sourceSnapshot: sourceSnapshot,
            plan: MutationPlan(
                kind: .rewardedAd,
                entries: [entry.id: entry],
                unlockedItemID: nil,
                rewardRedemption: RewardRedemption(
                    offerID: offerID,
                    providerTransactionID: providerTransactionID,
                    ledgerEntryID: entry.id
                ),
                requiredBalanceBefore: nil,
                recoversExistingCatalogUnlockTimestamp: false
            )
        )
    }

    func commitMutation(
        operationID: OperationID,
        sourceSnapshot: LocalPlayerProfileSnapshot,
        plan: MutationPlan
    ) async throws -> CommittedMutation {
        guard !plan.entries.isEmpty,
              plan.entries.allSatisfy({ $0.key == $0.value.id })
        else {
            throw DurableEconomyCoordinatorError.malformedCloudRecord
        }
        if plan.kind == .pendingCredits || plan.kind == .storeKit {
            try validateCreditEntries(plan.entries)
        }

        let entryIDs = Set(plan.entries.keys)
        let offerIDs = Set([plan.rewardRedemption?.offerID].compactMap { $0 })
        var conflictCount = 0
        while true {
            try await revalidateBeforeCloudMutation(sourceSnapshot: sourceSnapshot)
            let loaded = try await loadCloudState(
                entryIDs: entryIDs,
                rewardOfferIDs: offerIDs
            )
            var state = try validatedState(from: loaded)
            try validateMutationMarkers(
                plan: plan,
                operationID: operationID,
                loaded: loaded,
                state: state
            )
            try validateLocalCloudBase(
                sourceSnapshot: sourceSnapshot,
                cloudState: state,
                targetEntries: plan.entries,
                targetMarkers: loaded.ledgerMarkers
            )

            let missingEntries = plan.entries.filter {
                loaded.ledgerMarkers[$0.key] == nil
            }
            if missingEntries.isEmpty {
                let receipt = try cloudReceipt(
                    operationID: operationID,
                    loaded: loaded,
                    state: state,
                    status: .alreadyCommitted
                )
                return CommittedMutation(
                    state: state,
                    receipt: receipt,
                    entries: try committedEntries(for: plan, loaded: loaded)
                )
            }

            if let requiredBalanceBefore = plan.requiredBalanceBefore {
                guard state.ledgerAccumulator.confirmedBalance == requiredBalanceBefore else {
                    throw DurableEconomyCoordinatorError.cloudStateDiverged
                }
            }

            let binding = mutationBinding(
                kind: plan.kind,
                operationID: operationID,
                sourceEconomyRevision: sourceSnapshot.economyRevision
            )
            var newMarkers: [LedgerEntryID: CloudLedgerMarkerV1] = [:]
            for (entryID, entry) in missingEntries {
                let cloudRecord = CloudLedgerRecord(entry: entry, binding: binding)
                try validateCloudLedgerRecord(cloudRecord)
                newMarkers[entryID] = CloudLedgerMarkerV1(
                    schemaVersion: CloudLedgerMarkerV1.schemaVersion,
                    headRecordID: configuration.recordID,
                    record: cloudRecord
                )
                try add(entry, to: &state.ledgerAccumulator)
            }

            if let itemID = plan.unlockedItemID {
                guard missingEntries.count == 1,
                      !state.unlockedItemIDs.contains(itemID)
                else {
                    throw DurableEconomyCoordinatorError.cloudUnlockCollision(itemID)
                }
                state.appendUnlockedItem(itemID)
            }

            var newRewardMarker: CloudRewardOfferMarkerV1?
            if let redemption = plan.rewardRedemption {
                guard missingEntries.count == 1,
                      loaded.rewardOfferMarkers[redemption.offerID] == nil
                else {
                    throw DurableEconomyCoordinatorError.cloudRewardCollision(
                        redemption.offerID
                    )
                }
                newRewardMarker = CloudRewardOfferMarkerV1(
                    schemaVersion: CloudRewardOfferMarkerV1.schemaVersion,
                    headRecordID: configuration.recordID,
                    redemption: redemption,
                    binding: binding
                )
            }

            let increment = state.revision.addingReportingOverflow(1)
            guard !increment.overflow else {
                throw DurableEconomyCoordinatorError.cloudRevisionOverflow
            }
            state.revision = increment.partialValue
            try validateCloudState(state)

            var writes = [try makeHeadWrite(state: state, loaded: loaded)]
            for marker in newMarkers.values {
                writes.append(try makeLedgerMarkerWrite(marker))
            }
            if let newRewardMarker {
                writes.append(try makeRewardOfferMarkerWrite(newRewardMarker))
            }
            writes.sort { $0.id.rawValue < $1.id.rawValue }
            let request = CloudAtomicWriteRequest(
                accountID: context.cloudAccountID,
                operationID: operationID,
                writes: writes
            )

            do {
                let providerReceipt = try await cloud.commitAtomically(request)
                try validateProviderReceipt(providerReceipt, request: request)
                try await requireCurrentContext()
                guard let tag = providerReceipt.savedChangeTags[configuration.recordID] else {
                    throw DurableEconomyCoordinatorError.cloudReceiptMismatch
                }
                return CommittedMutation(
                    state: state,
                    receipt: DurableEconomyCloudCommitReceipt(
                        accountID: context.cloudAccountID,
                        operationID: operationID,
                        recordID: configuration.recordID,
                        observedChangeTag: tag,
                        cloudEconomyRevision: state.revision,
                        status: .committed
                    ),
                    entries: plan.entries
                )
            } catch let error as CloudSyncTransportError {
                guard case .conflict = error else { throw error }
                guard conflictCount < configuration.conflictRetryLimit else {
                    throw DurableEconomyCoordinatorError.conflictRetryLimitReached
                }
                conflictCount += 1
                continue
            } catch {
                guard let classified = error as? any CloudCommittedOperationRefreshClassifying,
                      let refresh = classified.committedOperationRefresh
                else {
                    throw error
                }
                guard refresh.operationID == operationID,
                      Set(refresh.recordIDs) == Set(request.writes.map(\.id))
                else {
                    throw DurableEconomyCoordinatorError.committedOperationRefreshMismatch
                }

                // A marker proves the operation committed. Do not retry the
                // mutation. Read the current head and prove the immutable target
                // entries still exist before acknowledging local durability.
                let refreshed = try await loadCloudState(
                    entryIDs: entryIDs,
                    rewardOfferIDs: offerIDs
                )
                let refreshedState = try validatedState(
                    from: refreshed,
                    allowCreation: false
                )
                try validateMutationMarkers(
                    plan: plan,
                    operationID: operationID,
                    loaded: refreshed,
                    state: refreshedState
                )
                try validateLocalCloudBase(
                    sourceSnapshot: sourceSnapshot,
                    cloudState: refreshedState,
                    targetEntries: plan.entries,
                    targetMarkers: refreshed.ledgerMarkers
                )
                for (targetID, expected) in plan.entries {
                    guard refreshed.ledgerMarkers[targetID]?.record.entry == expected
                    else {
                        throw DurableEconomyCoordinatorError
                            .committedOperationMissingAfterRefresh(operationID)
                    }
                }
                return CommittedMutation(
                    state: refreshedState,
                    receipt: try cloudReceipt(
                        operationID: operationID,
                        loaded: refreshed,
                        state: refreshedState,
                        status: .committedThenRefreshed
                    ),
                    entries: try committedEntries(
                        for: plan,
                        loaded: refreshed
                    )
                )
            }
        }
    }

    func revalidateBeforeCloudMutation(
        sourceSnapshot: LocalPlayerProfileSnapshot
    ) async throws {
        let current = try await validatedSnapshot(
            expectedSession: sourceSnapshot.session
        )
        guard current.economyRevision == sourceSnapshot.economyRevision else {
            throw DurableEconomyCoordinatorError.economyRevisionChanged(
                expected: sourceSnapshot.economyRevision,
                actual: current.economyRevision
            )
        }
    }

    func validateLocalCloudBase(
        sourceSnapshot: LocalPlayerProfileSnapshot,
        cloudState: CloudAccountHeadV2,
        targetEntries: [LedgerEntryID: CoinLedgerEntry],
        targetMarkers: [LedgerEntryID: CloudLedgerMarkerV1]
    ) throws {
        var local = confirmedLocalLedger(sourceSnapshot)
        var cloudBase = cloudState.ledgerAccumulator
        var cloudUnlocked = Set(cloudState.unlockedItemIDs)
        for (entryID, expectedEntry) in targetEntries {
            // A locally confirmed target can only be the aftermath of an
            // earlier cloud-first acknowledgement. Its deterministic immutable
            // marker must exist; local state can never repair a missing marker.
            if local[entryID] != nil, targetMarkers[entryID] == nil {
                throw DurableEconomyCoordinatorError.cloudStateDiverged
            }
            if let localEntry = local[entryID], localEntry != expectedEntry {
                throw DurableEconomyCoordinatorError.cloudLedgerCollision(entryID)
            }
            local.removeValue(forKey: entryID)

            if let marker = targetMarkers[entryID] {
                do {
                    try remove(marker.record.entry, from: &cloudBase)
                } catch {
                    throw DurableEconomyCoordinatorError.cloudStateDiverged
                }
                if case let .catalogUnlock(itemID) = marker.record.entry.reason {
                    guard cloudUnlocked.remove(itemID) != nil else {
                        throw DurableEconomyCoordinatorError.cloudStateDiverged
                    }
                }
            }
        }

        let localBase = try ledgerAccumulator(for: local.values)
        let localUnlocked = Set(local.values.compactMap { entry -> CatalogItemID? in
            guard case let .catalogUnlock(itemID) = entry.reason else { return nil }
            return itemID
        })
        guard localBase == cloudBase, localUnlocked == cloudUnlocked else {
            throw DurableEconomyCoordinatorError.cloudStateDiverged
        }
    }

    func validateMutationMarkers(
        plan: MutationPlan,
        operationID: OperationID,
        loaded: LoadedCloudState,
        state: CloudAccountHeadV2
    ) throws {
        guard (plan.unlockedItemID != nil) == (plan.kind == .catalogUnlock),
              (plan.rewardRedemption != nil) == (plan.kind == .rewardedAd)
        else {
            throw DurableEconomyCoordinatorError.malformedCloudRecord
        }

        for (entryID, expectedEntry) in plan.entries {
            guard let marker = loaded.ledgerMarkers[entryID] else { continue }
            let exactMatch = marker.record.entry == expectedEntry
            let recoveredUnlockMatch = plan.recoversExistingCatalogUnlockTimestamp
                && catalogUnlockEntryMatchesIgnoringTimestamp(
                    marker.record.entry,
                    expectedEntry
                )
            guard exactMatch || recoveredUnlockMatch else {
                if let itemID = plan.unlockedItemID {
                    throw DurableEconomyCoordinatorError.cloudUnlockCollision(itemID)
                }
                throw DurableEconomyCoordinatorError.cloudLedgerCollision(entryID)
            }
            guard marker.record.binding.kind == plan.kind else {
                throw DurableEconomyCoordinatorError.malformedCloudRecord
            }
            // Catalog unlocks always have one deterministic ledger ID, so the
            // account-scoped operation ID is stable even when a caller mints a
            // new request ID after relaunch. Pending-credit batches can be
            // regrouped, so their marker binding cannot use this same check.
            if plan.kind == .catalogUnlock,
               marker.record.binding.operationID != operationID {
                throw DurableEconomyCoordinatorError.malformedCloudRecord
            }
        }

        if let itemID = plan.unlockedItemID,
           let entryID = plan.entries.keys.first {
            let markerExists = loaded.ledgerMarkers[entryID] != nil
            let ownershipExists = state.unlockedItemIDs.contains(itemID)
            guard markerExists == ownershipExists else {
                throw DurableEconomyCoordinatorError.cloudUnlockCollision(itemID)
            }
        }

        if let redemption = plan.rewardRedemption {
            let entryMarker = loaded.ledgerMarkers[redemption.ledgerEntryID]
            let offerMarker = loaded.rewardOfferMarkers[redemption.offerID]
            if let offerMarker {
                guard offerMarker.redemption == redemption else {
                    throw DurableEconomyCoordinatorError.cloudRewardCollision(
                        redemption.offerID
                    )
                }
            }
            guard (entryMarker != nil) == (offerMarker != nil) else {
                throw DurableEconomyCoordinatorError.malformedCloudRecord
            }
            if let entryMarker, let offerMarker {
                guard entryMarker.record.binding == offerMarker.binding else {
                    throw DurableEconomyCoordinatorError.malformedCloudRecord
                }
            }
        }
    }

    func committedEntries(
        for plan: MutationPlan,
        loaded: LoadedCloudState
    ) throws -> [LedgerEntryID: CoinLedgerEntry] {
        var entries: [LedgerEntryID: CoinLedgerEntry] = [:]
        for entryID in plan.entries.keys {
            guard let marker = loaded.ledgerMarkers[entryID] else {
                throw DurableEconomyCoordinatorError.malformedCloudRecord
            }
            entries[entryID] = marker.record.entry
        }
        return entries
    }

    func catalogUnlockEntryMatchesIgnoringTimestamp(
        _ left: CoinLedgerEntry,
        _ right: CoinLedgerEntry
    ) -> Bool {
        guard left.id == right.id,
              left.delta == right.delta,
              left.reason == right.reason,
              case .catalogUnlock = left.reason,
              left.createdAt.timeIntervalSince1970.isFinite,
              right.createdAt.timeIntervalSince1970.isFinite
        else {
            return false
        }
        return true
    }

    func confirmedLocalLedger(
        _ snapshot: LocalPlayerProfileSnapshot
    ) -> [LedgerEntryID: CoinLedgerEntry] {
        snapshot.ledger.filter { !snapshot.pendingLedgerEntryIDs.contains($0.key) }
    }

    func makeHeadWrite(
        state: CloudAccountHeadV2,
        loaded: LoadedCloudState
    ) throws -> CloudRecordWrite {
        let precondition: CloudRecordPrecondition
        if let tag = loaded.changeTag {
            precondition = .changeTag(tag)
        } else {
            precondition = .mustNotExist
        }
        return CloudRecordWrite(
            id: configuration.recordID,
            recordType: configuration.recordType,
            fields: [configuration.payloadFieldName: try encodeCloudPayload(state)],
            precondition: precondition
        )
    }

    func makeLedgerMarkerWrite(
        _ marker: CloudLedgerMarkerV1
    ) throws -> CloudRecordWrite {
        CloudRecordWrite(
            id: ledgerMarkerRecordID(for: marker.record.entry.id),
            recordType: configuration.recordType,
            fields: [configuration.payloadFieldName: try encodeCloudPayload(marker)],
            precondition: .mustNotExist
        )
    }

    func makeRewardOfferMarkerWrite(
        _ marker: CloudRewardOfferMarkerV1
    ) throws -> CloudRecordWrite {
        CloudRecordWrite(
            id: rewardOfferMarkerRecordID(for: marker.redemption.offerID),
            recordType: configuration.recordType,
            fields: [configuration.payloadFieldName: try encodeCloudPayload(marker)],
            precondition: .mustNotExist
        )
    }

    func encodeCloudPayload<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    func validateProviderReceipt(
        _ receipt: CloudAtomicWriteReceipt,
        request: CloudAtomicWriteRequest
    ) throws {
        guard receipt.accountID == request.accountID,
              receipt.operationID == request.operationID,
              Set(receipt.savedChangeTags.keys) == Set(request.writes.map(\.id))
        else {
            throw DurableEconomyCoordinatorError.cloudReceiptMismatch
        }
    }

    func cloudReceipt(
        operationID: OperationID,
        loaded: LoadedCloudState,
        state: CloudAccountHeadV2,
        status: DurableEconomyCloudCommitStatus
    ) throws -> DurableEconomyCloudCommitReceipt {
        // Existing durable state always came from a fetched CloudRecord.
        // `validatedState(... allowCreation:)` prevents this path for a missing
        // record, so a missing tag is malformed rather than synthetic proof.
        guard let tag = loaded.changeTag else {
            throw DurableEconomyCoordinatorError.malformedCloudRecord
        }
        return DurableEconomyCloudCommitReceipt(
            accountID: context.cloudAccountID,
            operationID: operationID,
            recordID: configuration.recordID,
            observedChangeTag: tag,
            cloudEconomyRevision: state.revision,
            status: status
        )
    }

    func cloudBalance(_ state: CloudAccountHeadV2) throws -> Int64 {
        guard state.ledgerAccumulator.confirmedBalance >= 0 else {
            throw DurableEconomyCoordinatorError.cloudBalanceInvalid
        }
        return state.ledgerAccumulator.confirmedBalance
    }

    /// Swift actors are reentrant at every suspension point. This FIFO gate
    /// keeps one mutation in ownership from its first snapshot through cloud
    /// commit and local acknowledgement, preventing a second callback from
    /// observing and acting on the first callback's intermediate state.
    func acquireMutationGate() async {
        if !mutationIsRunning {
            mutationIsRunning = true
            return
        }
        await withCheckedContinuation { continuation in
            mutationWaiters.append(continuation)
        }
    }

    func releaseMutationGate() {
        guard !mutationWaiters.isEmpty else {
            mutationIsRunning = false
            return
        }
        let next = mutationWaiters.removeFirst()
        next.resume()
    }

    func ledgerAccumulator(
        for entries: some Sequence<CoinLedgerEntry>
    ) throws -> LedgerAccumulator {
        var result = LedgerAccumulator.empty
        for entry in entries {
            try add(entry, to: &result, requireNonnegativeBalance: false)
        }
        return result
    }

    func add(
        _ entry: CoinLedgerEntry,
        to accumulator: inout LedgerAccumulator,
        requireNonnegativeBalance: Bool = true
    ) throws {
        let count = accumulator.entryCount.addingReportingOverflow(1)
        let balance = accumulator.confirmedBalance.addingReportingOverflow(entry.delta)
        guard !count.overflow, !balance.overflow else {
            throw DurableEconomyCoordinatorError.cloudBalanceInvalid
        }
        if requireNonnegativeBalance, balance.partialValue < 0 {
            throw DurableEconomyCoordinatorError.cloudBalanceInvalid
        }
        accumulator.entryCount = count.partialValue
        accumulator.confirmedBalance = balance.partialValue
        accumulator.digest = xor(accumulator.digest, ledgerDigest(for: entry))
    }

    func remove(
        _ entry: CoinLedgerEntry,
        from accumulator: inout LedgerAccumulator
    ) throws {
        guard accumulator.entryCount > 0 else {
            throw DurableEconomyCoordinatorError.cloudStateDiverged
        }
        let balance = accumulator.confirmedBalance.subtractingReportingOverflow(entry.delta)
        guard !balance.overflow else {
            throw DurableEconomyCoordinatorError.cloudStateDiverged
        }
        accumulator.entryCount -= 1
        accumulator.confirmedBalance = balance.partialValue
        accumulator.digest = xor(accumulator.digest, ledgerDigest(for: entry))
    }

    func ledgerDigest(for entry: CoinLedgerEntry) -> Data {
        var digest = SHA256()
        append("pocket-vector-ledger-entry-v1", to: &digest)
        append(entry.id.rawValue, to: &digest)
        append(String(entry.delta), to: &digest)
        append(String(entry.createdAt.timeIntervalSinceReferenceDate.bitPattern), to: &digest)
        switch entry.reason {
        case let .gameplay(runID, economyVersion):
            append("gameplay", to: &digest)
            append(runID.description, to: &digest)
            append(String(economyVersion), to: &digest)
        case let .signingBonus(version):
            append("signing-bonus", to: &digest)
            append(String(version), to: &digest)
        case let .rewardedAd(offerID, providerTransactionID):
            append("rewarded-ad", to: &digest)
            append(offerID.rawValue, to: &digest)
            append(providerTransactionID.rawValue, to: &digest)
        case let .storeKit(transactionID, packID):
            append("storekit", to: &digest)
            append(String(transactionID), to: &digest)
            append(packID.rawValue, to: &digest)
        case let .catalogUnlock(itemID):
            append("catalog-unlock", to: &digest)
            append(itemID.rawValue, to: &digest)
        }
        return Data(digest.finalize())
    }

    func xor(_ left: Data, _ right: Data) -> Data {
        precondition(
            left.count == LedgerAccumulator.digestByteCount
                && right.count == LedgerAccumulator.digestByteCount
        )
        return Data(zip(left, right).map { $0 ^ $1 })
    }

    func ledgerMarkerRecordID(for entryID: LedgerEntryID) -> CloudRecordID {
        immutableMarkerRecordID(kind: "ledger-entry-v1", value: entryID.rawValue)
    }

    func rewardOfferMarkerRecordID(for offerID: RewardOfferID) -> CloudRecordID {
        immutableMarkerRecordID(kind: "reward-offer-v1", value: offerID.rawValue)
    }

    func immutableMarkerRecordID(kind: String, value: String) -> CloudRecordID {
        var digest = SHA256()
        append("pocket-vector-durable-economy-marker-v1", to: &digest)
        append(configuration.recordID.rawValue, to: &digest)
        append(kind, to: &digest)
        append(value, to: &digest)
        let value = digest.finalize().map { String(format: "%02x", $0) }.joined()
        return CloudRecordID("economy-marker-v1-\(value)")
    }

    func mutationBinding(
        kind: MutationKind,
        operationID: OperationID,
        sourceEconomyRevision: UInt64
    ) -> MutationBinding {
        MutationBinding(
            cloudAccountID: context.cloudAccountID,
            accountBinding: context.accountBinding,
            profileAccountIdentity: context.profileSession.accountIdentity,
            profileSessionNonce: context.profileSession.nonce,
            sourceEconomyRevision: sourceEconomyRevision,
            operationID: operationID,
            kind: kind
        )
    }

    func mutationOperationID(
        kind: String,
        entryIDs: Set<LedgerEntryID>
    ) -> OperationID {
        var digest = SHA256()
        append("pocket-vector-durable-economy-operation-v2", to: &digest)
        append(context.cloudAccountID.rawValue, to: &digest)
        append(context.accountBinding.accountKey.rawValue, to: &digest)
        append(context.accountBinding.profileID.uuidString.lowercased(), to: &digest)
        append(context.profileSession.accountIdentity.rawValue, to: &digest)
        append(kind, to: &digest)
        for entryID in entryIDs.sorted(by: { $0.rawValue < $1.rawValue }) {
            append(entryID.rawValue, to: &digest)
        }
        let value = digest.finalize().map { String(format: "%02x", $0) }.joined()
        return OperationID("economy-v2-\(value)")
    }

    func append(_ value: String, to digest: inout SHA256) {
        let data = Data(value.utf8)
        var length = UInt64(data.count).bigEndian
        withUnsafeBytes(of: &length) { digest.update(data: Data($0)) }
        digest.update(data: data)
    }

    func itemIsOwned(
        _ item: CatalogItemDescriptor,
        inventory: PlayerInventory
    ) -> Bool {
        switch item.kind {
        case let .team(teamID):
            inventory.ownedTeamIDs.contains(teamID)
        case let .alternateJersey(jerseyID):
            inventory.ownedJerseyIDs.contains(jerseyID)
        case let .football(footballID):
            inventory.ownedFootballIDs.contains(footballID)
        }
    }

    /// Runs the catalog's authoritative unlock transition against the exact
    /// source snapshot without mutating durable state. Removing an already-
    /// owned target from the copy lets the same prerequisite checks protect
    /// the idempotent path instead of stopping at `alreadyOwned`.
    func validateSourceUnlockPrerequisites(
        item: CatalogItemDescriptor,
        inventory: PlayerInventory
    ) throws {
        var projectedInventory = inventory
        if itemIsOwned(item, inventory: inventory) {
            switch item.kind {
            case let .team(teamID):
                projectedInventory.ownedTeamIDs.remove(teamID)
            case let .alternateJersey(jerseyID):
                projectedInventory.ownedJerseyIDs.remove(jerseyID)
            case let .football(footballID):
                projectedInventory.ownedFootballIDs.remove(footballID)
            }
        }

        do {
            _ = try InventoryRules.applyUnlock(
                itemID: item.id,
                to: &projectedInventory,
                catalog: catalog
            )
        } catch let error as InventoryRuleError {
            throw LocalPlayerRepositoryError.inventory(error)
        }
    }

    /// Cloud ownership contains only paid catalog items, so initially-owned
    /// teams are implicit. An alternate for any other team must be accompanied
    /// by that team's paid unlock in the bounded authoritative head.
    func validateCloudUnlockPrerequisites(_ state: CloudAccountHeadV2) throws {
        for itemID in state.unlockedItemIDs {
            guard let item = catalog.item(id: itemID) else {
                throw DurableEconomyCoordinatorError.malformedCloudRecord
            }
            guard case let .alternateJersey(jerseyID) = item.kind else { continue }
            guard let jersey = catalog.jersey(id: jerseyID),
                  let team = catalog.team(id: jersey.teamID) else {
                throw DurableEconomyCoordinatorError.malformedCloudRecord
            }
            guard !team.initiallyOwned else { continue }

            let teamUnlocks = catalog.unlockableItems.filter { candidate in
                guard case let .team(teamID) = candidate.kind else { return false }
                return teamID == team.id
            }
            guard teamUnlocks.count == 1,
                  state.unlockedItemIDs.contains(teamUnlocks[0].id)
            else {
                throw DurableEconomyCoordinatorError.malformedCloudRecord
            }
        }
    }
}

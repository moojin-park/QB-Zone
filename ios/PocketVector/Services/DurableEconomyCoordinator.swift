import CryptoKit
import Foundation

enum DurableEconomyCloudSchema {
    static let schemaIdentifier = "pocket-vector-durable-economy-cloud-schema-v1"
    static let headSchemaVersion = 3
    static let ledgerMarkerSchemaVersion = 2
    static let rewardOfferMarkerSchemaVersion = 2
    static let rewardedAdHeadSchemaVersion = 1
    static let ledgerAccumulatorDigestByteCount = 32
    static let ledgerDigestDomain = "pocket-vector-ledger-entry-v1"
    static let immutableMarkerAddressDomain =
        "pocket-vector-durable-economy-marker-v1"
    static let immutableMarkerRecordPrefix = "economy-marker-v1-"
    static let ledgerMarkerKind = "ledger-entry-v1"
    static let rewardOfferMarkerKind = "reward-offer-v1"
    static let operationAddressDomain =
        "pocket-vector-durable-economy-operation-v3"
    static let operationRecordPrefix = "economy-v3-"
    static let pendingCreditOperationKind = "pending-credit"
    static let storeKitCreditOperationKind = "storekit-credit"
    static let catalogUnlockOperationKind = "catalog-unlock"
    static let rewardedAdCreditOperationKind = "rewarded-ad-credit"
    static let payloadEncoding =
        "sorted-key-json-default-keys-without-escaped-slashes-deferred-date-base64-data-nonfinite-float-throw-v1"
    static let digestAlgorithmIdentifier = "sha256-v1"
    static let digestComponentEncodingIdentifier =
        "uint64-big-endian-length-prefixed-utf8-components-v1"
    static let digestHexEncodingIdentifier =
        "lowercase-two-digit-hex-per-byte-v1"
    static let immutableMarkerAddressPolicyIdentifier =
        "domain-head-record-kind-value-digest-prefixed-hex-v1"
    static let operationAddressPolicyIdentifier =
        "domain-cloud-account-id-account-key-profile-id-player-account-identity-kind-entry-count-then-entry-ids-digest-prefixed-hex-v2"
    static let mutationOperationSessionPolicyIdentifier =
        "durable-binding-and-player-identity-excludes-session-nonce-v1"
    static let identifierOrderingPolicyIdentifier =
        "utf8-byte-lexicographic-ascending-v1"
    static let mutationEntryCountEncodingIdentifier =
        "base-10-nonnegative-int-no-leading-zero-utf8-component-v1"
    static let mutationEntryOrderingPolicyIdentifier =
        "ledger-entry-id-utf8-byte-ascending-v1"
    static let eventBatchAssignmentPolicyIdentifier =
        "missing-ledger-entry-id-utf8-byte-ascending-zero-based-contiguous-uint32-v1"
    static let cloudWriteOrderingPolicyIdentifier =
        "cloud-record-id-utf8-byte-ascending-v1"
    static let ledgerEntryDigestPolicyIdentifier =
        "domain-id-delta-date-reference-bitpattern-reason-tag-associated-values-v1"
    static let ledgerAccumulatorPolicyIdentifier =
        "entry-count-confirmed-balance-order-independent-xor-entry-digests-v1"
    static let economyEventOrderingPolicyIdentifier =
        "cloud-head-revision-then-batch-index-v1"
    static let unlockedItemOrderingPolicyIdentifier =
        "catalog-item-id-utf8-byte-ascending-v1"

    static func utf8Precedes(_ lhs: String, _ rhs: String) -> Bool {
        lhs.utf8.lexicographicallyPrecedes(rhs.utf8)
    }

    static func batchIndex(forZeroBasedOffset offset: Int) -> UInt32? {
        guard offset >= 0 else { return nil }
        return UInt32(exactly: offset)
    }
    static var durableAccountBindingFields: String {
        DurableAccountBinding.persistedFieldManifest
    }

    static var headFields: String {
        DurableEconomyCoordinator.CloudAccountHeadV3.persistedFieldManifest
    }

    static var ledgerAccumulatorFields: String {
        DurableEconomyCoordinator.LedgerAccumulator.persistedFieldManifest
    }

    static var rewardedAdHeadFields: String {
        DurableEconomyCoordinator.CloudRewardedAdHeadV1.persistedFieldManifest
    }

    static var ledgerMarkerFields: String {
        DurableEconomyCoordinator.CloudLedgerMarkerV2.persistedFieldManifest
    }

    static var rewardOfferMarkerFields: String {
        DurableEconomyCoordinator.CloudRewardOfferMarkerV2.persistedFieldManifest
    }

    static var ledgerRecordFields: String {
        DurableEconomyCoordinator.CloudLedgerRecord.persistedFieldManifest
    }

    static var mutationBindingFields: String {
        DurableEconomyCoordinator.MutationBinding.persistedFieldManifest
    }

    static var rewardRedemptionFields: String {
        DurableEconomyCoordinator.RewardRedemption.persistedFieldManifest
    }

    static var eventPositionFields: String {
        DurableEconomyCoordinator.CloudEconomyEventPosition.persistedFieldManifest
    }

    static var mutationKindCases: String {
        DurableEconomyCoordinator.MutationKind.allCases
            .map(\.rawValue)
            .sorted(by: utf8Precedes)
            .joined(separator: ",")
    }

    static var gameplayResolutionCases: String {
        DurableEconomyCoordinator.GameplayRewardResolution.persistedCaseManifest
    }

    static func ledgerMarkerRecordID(
        for entryID: LedgerEntryID,
        headRecordID: CloudRecordID
    ) -> CloudRecordID {
        immutableMarkerRecordID(
            kind: ledgerMarkerKind,
            value: entryID.rawValue,
            headRecordID: headRecordID
        )
    }

    static func rewardOfferMarkerRecordID(
        for offerID: RewardOfferID,
        headRecordID: CloudRecordID
    ) -> CloudRecordID {
        immutableMarkerRecordID(
            kind: rewardOfferMarkerKind,
            value: offerID.rawValue,
            headRecordID: headRecordID
        )
    }

    static func fingerprintMaterial(
        for configuration: DurableEconomyCloudConfiguration
    ) -> [String] {
        let coinLedgerAddresses = CoinLedgerID.fingerprintMaterial
        let rewardOfferAddresses = RewardedAdState.offerAddressFingerprintMaterial
        return [
            schemaIdentifier,
            "headLogicalRecordID", configuration.recordID.rawValue,
            "recordType", configuration.recordType,
            "payloadFieldName", configuration.payloadFieldName,
            "headSchemaVersion", String(headSchemaVersion),
            "ledgerMarkerSchemaVersion", String(ledgerMarkerSchemaVersion),
            "rewardOfferMarkerSchemaVersion",
            String(rewardOfferMarkerSchemaVersion),
            "rewardedAdHeadSchemaVersion", String(rewardedAdHeadSchemaVersion),
            "ledgerAccumulatorDigestByteCount",
            String(ledgerAccumulatorDigestByteCount),
            "ledgerDigestDomain", ledgerDigestDomain,
            "immutableMarkerAddressDomain", immutableMarkerAddressDomain,
            "immutableMarkerRecordPrefix", immutableMarkerRecordPrefix,
            "ledgerMarkerKind", ledgerMarkerKind,
            "rewardOfferMarkerKind", rewardOfferMarkerKind,
            "operationAddressDomain", operationAddressDomain,
            "operationRecordPrefix", operationRecordPrefix,
            "pendingCreditOperationKind", pendingCreditOperationKind,
            "storeKitCreditOperationKind", storeKitCreditOperationKind,
            "catalogUnlockOperationKind", catalogUnlockOperationKind,
            "rewardedAdCreditOperationKind", rewardedAdCreditOperationKind,
            "payloadEncoding", payloadEncoding,
            "digestAlgorithm", digestAlgorithmIdentifier,
            "digestComponentEncoding", digestComponentEncodingIdentifier,
            "digestHexEncoding", digestHexEncodingIdentifier,
            "immutableMarkerAddressPolicy",
            immutableMarkerAddressPolicyIdentifier,
            "operationAddressPolicy", operationAddressPolicyIdentifier,
            "mutationOperationSessionPolicy",
            mutationOperationSessionPolicyIdentifier,
            "identifierOrderingPolicy", identifierOrderingPolicyIdentifier,
            "mutationEntryCountEncoding",
            mutationEntryCountEncodingIdentifier,
            "mutationEntryOrderingPolicy",
            mutationEntryOrderingPolicyIdentifier,
            "eventBatchAssignmentPolicy", eventBatchAssignmentPolicyIdentifier,
            "cloudWriteOrderingPolicy", cloudWriteOrderingPolicyIdentifier,
            "ledgerEntryDigestPolicy", ledgerEntryDigestPolicyIdentifier,
            "ledgerAccumulatorPolicy", ledgerAccumulatorPolicyIdentifier,
            "economyEventOrderingPolicy", economyEventOrderingPolicyIdentifier,
            "unlockedItemOrderingPolicy", unlockedItemOrderingPolicyIdentifier,
            "headFields", headFields,
            "ledgerAccumulatorFields", ledgerAccumulatorFields,
            "rewardedAdHeadFields", rewardedAdHeadFields,
            "ledgerMarkerFields", ledgerMarkerFields,
            "rewardOfferMarkerFields", rewardOfferMarkerFields,
            "ledgerRecordFields", ledgerRecordFields,
            "coinLedgerEntryFields", CoinLedgerEntry.persistedFieldManifest,
            "coinLedgerReasonCases", CoinLedgerReason.persistedCaseManifest,
            "mutationBindingFields", mutationBindingFields,
            "durableAccountBindingFields", durableAccountBindingFields,
            "mutationKindCases", mutationKindCases,
            "rewardRedemptionFields", rewardRedemptionFields,
            "eventPositionFields", eventPositionFields,
            "rewardedRunObservationFields",
            RewardedRunObservation.persistedFieldManifest,
            "rewardedRunObservationDispositionCases",
            RewardedRunObservation.dispositionCaseManifest,
            "gameplayRewardResolutionCases", gameplayResolutionCases,
            "coinLedgerAddressMaterialCount", String(coinLedgerAddresses.count),
        ] + coinLedgerAddresses + [
            "rewardOfferAddressMaterialCount", String(rewardOfferAddresses.count),
        ] + rewardOfferAddresses + persistedEconomyRulesFingerprintMaterial
    }

    static func makePayloadEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.keyEncodingStrategy = .useDefaultKeys
        encoder.dateEncodingStrategy = .deferredToDate
        encoder.dataEncodingStrategy = .base64
        encoder.nonConformingFloatEncodingStrategy = .throw
        return encoder
    }

    static func makePayloadDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        decoder.dateDecodingStrategy = .deferredToDate
        decoder.dataDecodingStrategy = .base64
        decoder.nonConformingFloatDecodingStrategy = .throw
        return decoder
    }

    private static var persistedEconomyRulesFingerprintMaterial: [String] {
        let run = PersistedEconomyRulesV1.run
        var material: [String] = [
            "persistedEconomyRules", "pocket-vector-persisted-economy-rules-v1",
            "runEconomyVersion", String(run.economyVersion),
            "runNaturalMilliseconds", String(run.naturalRunMilliseconds),
            "runMinimumRewardAttempts", String(run.minimumRewardAttempts),
            "runBaseCoins", String(run.baseRunCoins),
            "runScoreCoinsPerPoints", String(run.scoreCoinsPerPoints),
            "runMaximumScoreCoins", String(run.maximumScoreCoins),
            "runAccuracyBonusCoins", String(run.accuracyBonusCoins),
            "runAccuracyMinimumAttempts", String(run.accuracyMinimumAttempts),
            "runAccuracyMinimumPercent", String(run.accuracyMinimumPercent),
        ]
        material.append(contentsOf: [
            "signingBonusVersion", String(PersistedEconomyRulesV1.signingBonusVersion),
            "signingBonusCoins", String(PersistedEconomyRulesV1.signingBonusCoins),
            "signingBonusCreatedAt1970BitPattern",
            String(
                PersistedEconomyRulesV1.signingBonusLedgerCreatedAt
                    .timeIntervalSince1970.bitPattern
            ),
            "rewardedAdCoins", String(PersistedEconomyRulesV1.rewardedAdCoins),
            "rewardedAdRunThreshold",
            String(PersistedEconomyRulesV1.rewardedAdRunThreshold),
            "lockedTeamPrice", String(PersistedEconomyRulesV1.lockedTeamPrice),
            "alternateJerseyPrice",
            String(PersistedEconomyRulesV1.alternateJerseyPrice),
            "alternateFootballPrice",
            String(PersistedEconomyRulesV1.alternateFootballPrice),
        ])
        let packs = PersistedEconomyRulesV1.coinPackCoins.sorted {
            utf8Precedes($0.key.rawValue, $1.key.rawValue)
        }
        material.append(contentsOf: ["coinPackCount", String(packs.count)])
        for (packID, coins) in packs {
            material.append(contentsOf: ["coinPack", packID.rawValue, String(coins)])
        }
        return material
    }

    private static func immutableMarkerRecordID(
        kind: String,
        value: String,
        headRecordID: CloudRecordID
    ) -> CloudRecordID {
        var digest = SHA256()
        append(immutableMarkerAddressDomain, to: &digest)
        append(headRecordID.rawValue, to: &digest)
        append(kind, to: &digest)
        append(value, to: &digest)
        let hex = digest.finalize().map { String(format: "%02x", $0) }.joined()
        return CloudRecordID("\(immutableMarkerRecordPrefix)\(hex)")
    }

    private static func append(_ value: String, to digest: inout SHA256) {
        let data = Data(value.utf8)
        var length = UInt64(data.count).bigEndian
        withUnsafeBytes(of: &length) { digest.update(data: Data($0)) }
        digest.update(data: data)
    }
}

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

    var fingerprintMaterial: [String] {
        DurableEconomyCloudSchema.fingerprintMaterial(for: self)
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

/// One canonical address function is shared by cloud mutation and the sealed
/// rewarded-ad delivery acknowledgement. Keeping it here prevents a result
/// from proving an arbitrary operation ID that merely resembles a cloud
/// receipt.
private enum DurableEconomyOperationAddressV3 {
    static func operationID(
        kind: String,
        entryIDs: Set<LedgerEntryID>,
        cloudAccountID: CloudAccountID,
        accountBinding: DurableAccountBinding,
        profileAccountIdentity: PlayerAccountIdentity
    ) -> OperationID {
        var digest = SHA256()
        append(DurableEconomyCloudSchema.operationAddressDomain, to: &digest)
        append(cloudAccountID.rawValue, to: &digest)
        append(accountBinding.accountKey.rawValue, to: &digest)
        append(accountBinding.profileID.uuidString.lowercased(), to: &digest)
        append(profileAccountIdentity.rawValue, to: &digest)
        append(kind, to: &digest)
        let orderedEntryIDs = entryIDs.sorted {
            DurableEconomyCloudSchema.utf8Precedes(
                $0.rawValue,
                $1.rawValue
            )
        }
        append(String(orderedEntryIDs.count), to: &digest)
        for entryID in orderedEntryIDs {
            append(entryID.rawValue, to: &digest)
        }
        let value = digest.finalize().map {
            String(format: "%02x", $0)
        }.joined()
        return OperationID(
            "\(DurableEconomyCloudSchema.operationRecordPrefix)\(value)"
        )
    }

    static func rewardedAdOperationID(
        cloudAccountID: CloudAccountID,
        accountBinding: DurableAccountBinding,
        profileAccountIdentity: PlayerAccountIdentity,
        providerTransactionID: AdProviderTransactionID
    ) -> OperationID {
        operationID(
            kind: DurableEconomyCloudSchema.rewardedAdCreditOperationKind,
            entryIDs: [
                CoinLedgerID.rewardedAd(
                    providerTransactionID: providerTransactionID
                ),
            ],
            cloudAccountID: cloudAccountID,
            accountBinding: accountBinding,
            profileAccountIdentity: profileAccountIdentity
        )
    }

    private static func append(_ value: String, to digest: inout SHA256) {
        let data = Data(value.utf8)
        var length = UInt64(data.count).bigEndian
        withUnsafeBytes(of: &length) { digest.update(data: Data($0)) }
        digest.update(data: data)
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

/// This is intentionally downstream of provider verification. Its only
/// initializer requires a non-Codable process claim minted by the verification
/// client after exact server correlation.
struct VerifiedRewardedAdDurableDeliveryRequest: Equatable, Sendable {
    let session: ProfileSessionToken
    private let verifiedClaim: VerifiedRewardedAdClaim

    var offerID: RewardOfferID { verifiedClaim.receipt.offerID }
    var providerTransactionID: AdProviderTransactionID {
        verifiedClaim.receipt.providerTransactionID
    }
    var rewardedAt: Date { verifiedClaim.receipt.rewardedAt }
    var verifiedBinding: DurableAccountBinding {
        verifiedClaim.receipt.binding
    }

    init(
        session: ProfileSessionToken,
        currentBinding: DurableAccountBinding,
        verifiedClaim: VerifiedRewardedAdClaim
    ) throws {
        // Durable ownership survives session rollover. The presentation nonce
        // is correlation evidence, not owner authority; the coordinator still
        // requires `session` to equal its exact current mutation session.
        guard currentBinding == verifiedClaim.receipt.binding else {
            throw RewardedAdVerificationError.durableOwnerMismatch
        }
        guard session.profileID == currentBinding.profileID else {
            throw RewardedAdVerificationError.profileSessionMismatch
        }
        self.session = session
        self.verifiedClaim = verifiedClaim
    }
}

private final class DurableRewardedAdDeliveryProcessAuthority:
    @unchecked Sendable
{}

private struct DurableRewardedAdDeliveryAcknowledgement: Sendable {
    let outcome: RewardedAdSettlementOutcome
    let cloudReceipt: DurableEconomyCloudCommitReceipt
    let session: ProfileSessionToken
    let binding: DurableAccountBinding
    let offerID: RewardOfferID
    let providerTransactionID: AdProviderTransactionID
    let rewardedAt: Date
    let cloudAccountID: CloudAccountID
    let operationID: OperationID
    let recordID: CloudRecordID
    private let processAuthority: DurableRewardedAdDeliveryProcessAuthority

    init(
        outcome: RewardedAdSettlementOutcome,
        cloudReceipt: DurableEconomyCloudCommitReceipt,
        session: ProfileSessionToken,
        binding: DurableAccountBinding,
        offerID: RewardOfferID,
        providerTransactionID: AdProviderTransactionID,
        rewardedAt: Date,
        cloudAccountID: CloudAccountID,
        operationID: OperationID,
        recordID: CloudRecordID,
        processAuthority: DurableRewardedAdDeliveryProcessAuthority
    ) {
        self.outcome = outcome
        self.cloudReceipt = cloudReceipt
        self.session = session
        self.binding = binding
        self.offerID = offerID
        self.providerTransactionID = providerTransactionID
        self.rewardedAt = rewardedAt
        self.cloudAccountID = cloudAccountID
        self.operationID = operationID
        self.recordID = recordID
        self.processAuthority = processAuthority
    }

    func wasMinted(
        by authority: DurableRewardedAdDeliveryProcessAuthority
    ) -> Bool {
        processAuthority === authority
    }

    func equals(_ other: Self) -> Bool {
        processAuthority === other.processAuthority
            && outcome == other.outcome
            && cloudReceipt == other.cloudReceipt
            && session == other.session
            && binding == other.binding
            && offerID == other.offerID
            && providerTransactionID == other.providerTransactionID
            && rewardedAt == other.rewardedAt
            && cloudAccountID == other.cloudAccountID
            && operationID == other.operationID
            && recordID == other.recordID
    }
}

/// A non-Codable, process-sealed acknowledgement of exact durable delivery.
/// Release code outside this file can inspect the outcome but cannot mint a
/// value capable of authorizing recovery-journal deletion.
struct DurableRewardedAdDeliveryResult: Equatable, Sendable {
    let outcome: RewardedAdSettlementOutcome
    let cloudReceipt: DurableEconomyCloudCommitReceipt
    private let processAuthority: DurableRewardedAdDeliveryProcessAuthority
    private let acknowledgement: DurableRewardedAdDeliveryAcknowledgement

    fileprivate init(
        validatedOutcome outcome: RewardedAdSettlementOutcome,
        cloudReceipt: DurableEconomyCloudCommitReceipt,
        request: VerifiedRewardedAdDurableDeliveryRequest,
        context: DurableEconomySessionContext,
        operationID: OperationID,
        recordID: CloudRecordID
    ) throws {
        let expectedLedgerID = CoinLedgerID.rewardedAd(
            providerTransactionID: request.providerTransactionID
        )
        let expectedOperationID = DurableEconomyOperationAddressV3
            .rewardedAdOperationID(
                cloudAccountID: context.cloudAccountID,
                accountBinding: context.accountBinding,
                profileAccountIdentity: request.session.accountIdentity,
                providerTransactionID: request.providerTransactionID
            )
        let derived = CloudAccountDerivedBindings.derive(
            from: cloudReceipt.accountID
        )
        guard request.session == context.profileSession,
              request.verifiedBinding == context.accountBinding,
              request.session.profileID == context.accountBinding.profileID,
              request.rewardedAt.timeIntervalSince1970.isFinite,
              outcome.offerID == request.offerID,
              outcome.providerTransactionID == request.providerTransactionID,
              outcome.ledgerEntryID == expectedLedgerID,
              outcome.coins == PersistedEconomyRulesV1.rewardedAdCoins,
              cloudReceipt.accountID == context.cloudAccountID,
              cloudReceipt.operationID == operationID,
              operationID == expectedOperationID,
              cloudReceipt.recordID == recordID,
              derived.durableAccountBinding == context.accountBinding,
              derived.playerAccountIdentity == request.session.accountIdentity
        else {
            throw DurableEconomyCoordinatorError.invalidRewardedAdRequest
        }
        self.outcome = outcome
        self.cloudReceipt = cloudReceipt
        let processAuthority = DurableRewardedAdDeliveryProcessAuthority()
        self.processAuthority = processAuthority
        acknowledgement = DurableRewardedAdDeliveryAcknowledgement(
            outcome: outcome,
            cloudReceipt: cloudReceipt,
            session: request.session,
            binding: context.accountBinding,
            offerID: request.offerID,
            providerTransactionID: request.providerTransactionID,
            rewardedAt: request.rewardedAt,
            cloudAccountID: context.cloudAccountID,
            operationID: operationID,
            recordID: recordID,
            processAuthority: processAuthority
        )
    }

    func authorizesJournalDeletion(
        currentSession: ProfileSessionToken,
        currentBinding: DurableAccountBinding,
        offerID: RewardOfferID,
        providerTransactionID: AdProviderTransactionID,
        rewardedAt: Date
    ) -> Bool {
        let expectedLedgerID = CoinLedgerID.rewardedAd(
            providerTransactionID: providerTransactionID
        )
        let derived = CloudAccountDerivedBindings.derive(
            from: cloudReceipt.accountID
        )
        let expectedOperationID = DurableEconomyOperationAddressV3
            .rewardedAdOperationID(
                cloudAccountID: cloudReceipt.accountID,
                accountBinding: currentBinding,
                profileAccountIdentity: currentSession.accountIdentity,
                providerTransactionID: providerTransactionID
            )
        guard acknowledgement.wasMinted(by: processAuthority),
              acknowledgement.outcome == outcome,
              acknowledgement.cloudReceipt == cloudReceipt,
              acknowledgement.session == currentSession,
              acknowledgement.binding == currentBinding,
              acknowledgement.offerID == offerID,
              acknowledgement.providerTransactionID == providerTransactionID,
              acknowledgement.rewardedAt == rewardedAt,
              acknowledgement.cloudAccountID == cloudReceipt.accountID,
              acknowledgement.operationID == cloudReceipt.operationID,
              acknowledgement.operationID == expectedOperationID,
              acknowledgement.recordID == cloudReceipt.recordID,
              currentSession.profileID == currentBinding.profileID,
              derived.durableAccountBinding == currentBinding,
              derived.playerAccountIdentity == currentSession.accountIdentity,
              outcome.offerID == offerID,
              outcome.providerTransactionID == providerTransactionID,
              outcome.ledgerEntryID == expectedLedgerID,
              outcome.coins == PersistedEconomyRulesV1.rewardedAdCoins
        else {
            return false
        }
        switch cloudReceipt.status {
        case .committed, .alreadyCommitted, .committedThenRefreshed:
            return true
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.processAuthority === rhs.processAuthority
            && lhs.outcome == rhs.outcome
            && lhs.cloudReceipt == rhs.cloudReceipt
            && lhs.acknowledgement.equals(rhs.acknowledgement)
    }

#if DEBUG
    init(
        testingOutcome outcome: RewardedAdSettlementOutcome,
        cloudReceipt: DurableEconomyCloudCommitReceipt,
        acknowledgedSession: ProfileSessionToken,
        acknowledgedBinding: DurableAccountBinding,
        acknowledgedOfferID: RewardOfferID,
        acknowledgedProviderTransactionID: AdProviderTransactionID,
        acknowledgedRewardedAt: Date,
        acknowledgedCloudAccountID: CloudAccountID,
        acknowledgedOperationID: OperationID? = nil,
        acknowledgedRecordID: CloudRecordID,
        acknowledgedCloudReceipt: DurableEconomyCloudCommitReceipt? = nil
    ) {
        let operationID = acknowledgedOperationID
            ?? DurableEconomyOperationAddressV3.rewardedAdOperationID(
                cloudAccountID: acknowledgedCloudAccountID,
                accountBinding: acknowledgedBinding,
                profileAccountIdentity: acknowledgedSession.accountIdentity,
                providerTransactionID: acknowledgedProviderTransactionID
        )
        self.outcome = outcome
        self.cloudReceipt = cloudReceipt
        let processAuthority = DurableRewardedAdDeliveryProcessAuthority()
        self.processAuthority = processAuthority
        acknowledgement = DurableRewardedAdDeliveryAcknowledgement(
            outcome: outcome,
            cloudReceipt: acknowledgedCloudReceipt ?? cloudReceipt,
            session: acknowledgedSession,
            binding: acknowledgedBinding,
            offerID: acknowledgedOfferID,
            providerTransactionID: acknowledgedProviderTransactionID,
            rewardedAt: acknowledgedRewardedAt,
            cloudAccountID: acknowledgedCloudAccountID,
            operationID: operationID,
            recordID: acknowledgedRecordID,
            processAuthority: processAuthority
        )
    }

    static func testingRewardedAdOperationID(
        cloudAccountID: CloudAccountID,
        binding: DurableAccountBinding,
        session: ProfileSessionToken,
        providerTransactionID: AdProviderTransactionID
    ) -> OperationID {
        DurableEconomyOperationAddressV3.rewardedAdOperationID(
            cloudAccountID: cloudAccountID,
            accountBinding: binding,
            profileAccountIdentity: session.accountIdentity,
            providerTransactionID: providerTransactionID
        )
    }
#endif
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
    /// The cloud contains confirmed history absent from this local profile.
    /// Mutation remains blocked until a complete replica hydrator rebases it.
    case cloudRebaseRequired
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
    case missingRewardedRunObservation(RunID)
    case rewardedRunObservationAhead(observed: UInt64, current: UInt64)
    case invalidRewardEventPosition
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

    /// Release construction stays file-sealed until trusted production account,
    /// repository, CloudKit transport, and head configuration composition is
    /// added in this reviewed file.
    fileprivate init(
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

#if DEBUG
    init(
        testingContext context: DurableEconomySessionContext,
        sessionAuthority: any DurableEconomySessionAuthorizing,
        repository: any DurableEconomyLocalPersisting,
        cloud: any CloudSyncTransport,
        configuration: DurableEconomyCloudConfiguration,
        catalog: LaunchCatalog = .approved,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.init(
            context: context,
            sessionAuthority: sessionAuthority,
            repository: repository,
            cloud: cloud,
            configuration: configuration,
            catalog: catalog,
            now: now
        )
    }
#endif

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
        let gameplayRewardObservations = try gameplayRewardObservations(
            for: entries,
            snapshot: snapshot
        )

        let operationID = mutationOperationID(
            kind: DurableEconomyCloudSchema.pendingCreditOperationKind,
            entryIDs: entryIDs
        )
        let committed = try await commitCreditMutation(
            entries: entries,
            kind: .pendingCredits,
            operationID: operationID,
            sourceSnapshot: snapshot,
            gameplayRewardObservations: gameplayRewardObservations
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
            kind: DurableEconomyCloudSchema.storeKitCreditOperationKind,
            entryIDs: [request.ledgerEntry.id]
        )
        let committed = try await commitCreditMutation(
            entries: [request.ledgerEntry.id: request.ledgerEntry],
            kind: .storeKit,
            operationID: operationID,
            sourceSnapshot: snapshot,
            gameplayRewardObservations: [:]
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
            kind: DurableEconomyCloudSchema.catalogUnlockOperationKind,
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
        let derived = CloudAccountDerivedBindings.derive(
            from: context.cloudAccountID
        )
        guard request.session == context.profileSession,
              request.verifiedBinding == context.accountBinding,
              request.rewardedAt.timeIntervalSince1970.isFinite,
              derived.durableAccountBinding == context.accountBinding,
              derived.playerAccountIdentity
                == context.profileSession.accountIdentity
        else {
            throw DurableEconomyCoordinatorError.invalidRewardedAdRequest
        }
        let ledgerID = CoinLedgerID.rewardedAd(
            providerTransactionID: request.providerTransactionID
        )
        let redemption = RewardRedemption(
            offerID: request.offerID,
            providerTransactionID: request.providerTransactionID,
            ledgerEntryID: ledgerID
        )
        // Preserve the immutable offer-level collision signal before a stale
        // device attempts to publish its still-pending gameplay credits. The
        // preflight is only diagnostic; the later CAS mutation repeats every
        // binding check and remains authoritative if cloud state races.
        let existingReward = try await loadCloudState(
            rewardOfferIDs: [request.offerID]
        ).rewardOfferMarkers[request.offerID]
        if let existingReward,
           existingReward.redemption != redemption {
            throw DurableEconomyCoordinatorError.cloudRewardCollision(
                request.offerID
            )
        }

        var snapshot = try await validatedSnapshot(expectedSession: request.session)
        // A verified ad callback can arrive immediately after the fifth local
        // run. Resolve every pending gameplay observation into the canonical
        // cloud head before attempting to consume its offer.
        if snapshot.player.rewardedAdState.eligibleOfferID == request.offerID,
           !snapshot.pendingLedgerEntryIDs.isEmpty {
            _ = try await confirmPendingCreditsImpl(
                snapshot.pendingLedgerEntryIDs,
                session: request.session
            )
            snapshot = try await validatedSnapshot(expectedSession: request.session)
        }
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
            kind: DurableEconomyCloudSchema.rewardedAdCreditOperationKind,
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
        return try DurableRewardedAdDeliveryResult(
            validatedOutcome: outcome,
            cloudReceipt: committed.receipt,
            request: request,
            context: context,
            operationID: operationID,
            recordID: configuration.recordID
        )
    }
}

/// Internal history models are intentionally visible to the forthcoming full
/// CloudKit hydrator. Mutations remain actor-serialized, while restoration can
/// decode and replay the same fail-closed event schema without duplicating it.
extension DurableEconomyCoordinator {
    enum MutationKind: String, Codable, CaseIterable, Equatable, Sendable {
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

        enum CodingKeys: String, CodingKey, CaseIterable {
            case cloudAccountID
            case accountBinding
            case profileAccountIdentity
            case profileSessionNonce
            case sourceEconomyRevision
            case operationID
            case kind
        }

        static var persistedFieldManifest: String {
            CodingKeys.allCases.map(\.rawValue)
                .sorted(by: DurableEconomyCloudSchema.utf8Precedes)
                .joined(separator: ",")
        }
    }

    struct CloudLedgerRecord: Codable, Equatable, Sendable {
        let entry: CoinLedgerEntry
        let binding: MutationBinding

        enum CodingKeys: String, CodingKey, CaseIterable {
            case entry
            case binding
        }

        static var persistedFieldManifest: String {
            CodingKeys.allCases.map(\.rawValue)
                .sorted(by: DurableEconomyCloudSchema.utf8Precedes)
                .joined(separator: ",")
        }
    }

    struct RewardRedemption: Codable, Equatable, Sendable {
        let offerID: RewardOfferID
        let providerTransactionID: AdProviderTransactionID
        let ledgerEntryID: LedgerEntryID

        enum CodingKeys: String, CodingKey, CaseIterable {
            case offerID
            case providerTransactionID
            case ledgerEntryID
        }

        static var persistedFieldManifest: String {
            CodingKeys.allCases.map(\.rawValue)
                .sorted(by: DurableEconomyCloudSchema.utf8Precedes)
                .joined(separator: ",")
        }
    }

    /// A fixed-width commitment to the complete immutable marker set. The XOR
    /// accumulator is order-independent so the local full ledger can reproduce
    /// it without downloading history. Entry count prevents duplicate
    /// cancellation, balance preserves the authoritative spendable total, and
    /// every individual ID remains indefinitely provable through its immutable
    /// marker record.
    struct LedgerAccumulator: Codable, Equatable, Sendable {
        static let digestByteCount =
            DurableEconomyCloudSchema.ledgerAccumulatorDigestByteCount

        var entryCount: UInt64
        var confirmedBalance: Int64
        var digest: Data

        enum CodingKeys: String, CodingKey, CaseIterable {
            case entryCount
            case confirmedBalance
            case digest
        }

        static var persistedFieldManifest: String {
            CodingKeys.allCases.map(\.rawValue)
                .sorted(by: DurableEconomyCloudSchema.utf8Precedes)
                .joined(separator: ",")
        }

        static let empty = LedgerAccumulator(
            entryCount: 0,
            confirmedBalance: 0,
            digest: Data(repeating: 0, count: digestByteCount)
        )
    }

    struct CloudEconomyEventPosition: Codable, Equatable, Hashable, Sendable,
        Comparable
    {
        let cloudHeadRevision: UInt64
        let batchIndex: UInt32

        enum CodingKeys: String, CodingKey, CaseIterable {
            case cloudHeadRevision
            case batchIndex
        }

        static var persistedFieldManifest: String {
            CodingKeys.allCases.map(\.rawValue)
                .sorted(by: DurableEconomyCloudSchema.utf8Precedes)
                .joined(separator: ",")
        }

        static func < (
            lhs: CloudEconomyEventPosition,
            rhs: CloudEconomyEventPosition
        ) -> Bool {
            if lhs.cloudHeadRevision != rhs.cloudHeadRevision {
                return lhs.cloudHeadRevision < rhs.cloudHeadRevision
            }
            return lhs.batchIndex < rhs.batchIndex
        }
    }

    enum GameplayRewardResolution: Codable, Equatable, Sendable {
        case counted(
            cycle: UInt64,
            resultingCount: Int,
            unlockedOfferID: RewardOfferID?
        )
        case ignoredActiveOffer(cycle: UInt64, offerID: RewardOfferID)
        case ignoredStaleCycle(observedCycle: UInt64, currentCycle: UInt64)
        case ignoredLegacyNonCounting

        enum PersistedCase: String, CaseIterable {
            case counted
            case ignoredActiveOffer
            case ignoredStaleCycle
            case ignoredLegacyNonCounting

            var associatedFields: [String] {
                switch self {
                case .counted:
                    ["cycle", "resultingCount", "unlockedOfferID"]
                case .ignoredActiveOffer:
                    ["cycle", "offerID"]
                case .ignoredStaleCycle:
                    ["observedCycle", "currentCycle"]
                case .ignoredLegacyNonCounting:
                    []
                }
            }
        }

        static var persistedCaseManifest: String {
            PersistedCase.allCases.sorted {
                DurableEconomyCloudSchema.utf8Precedes(
                    $0.rawValue,
                    $1.rawValue
                )
            }.map { persistedCase in
                let fields = persistedCase.associatedFields
                    .sorted(by: DurableEconomyCloudSchema.utf8Precedes)
                    .joined(separator: ",")
                return fields.isEmpty
                    ? persistedCase.rawValue
                    : "\(persistedCase.rawValue)(\(fields))"
            }.joined(separator: ",")
        }
    }

    struct CloudLedgerMarkerV2: Codable, Equatable, Sendable {
        static let schemaVersion = DurableEconomyCloudSchema.ledgerMarkerSchemaVersion

        let schemaVersion: Int
        let headRecordID: CloudRecordID
        let record: CloudLedgerRecord
        let eventPosition: CloudEconomyEventPosition
        let gameplayRewardObservation: RewardedRunObservation?
        let gameplayRewardResolution: GameplayRewardResolution?

        enum CodingKeys: String, CodingKey, CaseIterable {
            case schemaVersion
            case headRecordID
            case record
            case eventPosition
            case gameplayRewardObservation
            case gameplayRewardResolution
        }

        static var persistedFieldManifest: String {
            CodingKeys.allCases.map(\.rawValue)
                .sorted(by: DurableEconomyCloudSchema.utf8Precedes)
                .joined(separator: ",")
        }
    }

    struct CloudRewardOfferMarkerV2: Codable, Equatable, Sendable {
        static let schemaVersion =
            DurableEconomyCloudSchema.rewardOfferMarkerSchemaVersion

        let schemaVersion: Int
        let headRecordID: CloudRecordID
        let redemption: RewardRedemption
        let binding: MutationBinding
        let eventPosition: CloudEconomyEventPosition

        enum CodingKeys: String, CodingKey, CaseIterable {
            case schemaVersion
            case headRecordID
            case redemption
            case binding
            case eventPosition
        }

        static var persistedFieldManifest: String {
            CodingKeys.allCases.map(\.rawValue)
                .sorted(by: DurableEconomyCloudSchema.utf8Precedes)
                .joined(separator: ",")
        }
    }

    struct CloudRewardedAdHeadV1: Codable, Equatable, Sendable {
        static let schemaVersion = DurableEconomyCloudSchema.rewardedAdHeadSchemaVersion

        let schemaVersion: Int
        private(set) var cycle: UInt64
        private(set) var validRunsSinceReward: Int
        private(set) var eligibleOfferID: RewardOfferID?

        enum CodingKeys: String, CodingKey, CaseIterable {
            case schemaVersion
            case cycle
            case validRunsSinceReward
            case eligibleOfferID
        }

        static var persistedFieldManifest: String {
            CodingKeys.allCases.map(\.rawValue)
                .sorted(by: DurableEconomyCloudSchema.utf8Precedes)
                .joined(separator: ",")
        }

        static let initial = CloudRewardedAdHeadV1(
            schemaVersion: schemaVersion,
            cycle: 0,
            validRunsSinceReward: 0,
            eligibleOfferID: nil
        )

        mutating func resolveGameplay(
            observation: RewardedRunObservation
        ) throws -> GameplayRewardResolution {
            if observation.disposition == .legacyNonCounting {
                guard observation.observedCycle == 0 else {
                    throw DurableEconomyCoordinatorError.malformedCloudRecord
                }
                return .ignoredLegacyNonCounting
            }
            guard observation.observedCycle <= cycle else {
                throw DurableEconomyCoordinatorError.rewardedRunObservationAhead(
                    observed: observation.observedCycle,
                    current: cycle
                )
            }
            if observation.observedCycle < cycle {
                return .ignoredStaleCycle(
                    observedCycle: observation.observedCycle,
                    currentCycle: cycle
                )
            }

            let offerID = RewardedAdState.offerID(for: cycle)
            if observation.disposition == .ignoredWhileOfferPending
                || eligibleOfferID != nil
            {
                return .ignoredActiveOffer(cycle: cycle, offerID: offerID)
            }

            validRunsSinceReward += 1
            if validRunsSinceReward == PersistedEconomyRulesV1.rewardedAdRunThreshold {
                eligibleOfferID = offerID
            }
            return .counted(
                cycle: cycle,
                resultingCount: validRunsSinceReward,
                unlockedOfferID: eligibleOfferID
            )
        }

        mutating func redeem(_ offerID: RewardOfferID) throws {
            guard eligibleOfferID == offerID,
                  validRunsSinceReward == PersistedEconomyRulesV1.rewardedAdRunThreshold
            else {
                throw DurableEconomyCoordinatorError.cloudRewardCollision(offerID)
            }
            let nextCycle = cycle.addingReportingOverflow(1)
            guard !nextCycle.overflow else {
                throw DurableEconomyCoordinatorError.cloudRevisionOverflow
            }
            cycle = nextCycle.partialValue
            validRunsSinceReward = 0
            eligibleOfferID = nil
        }
    }

    /// The mutable account head is deliberately constant-size with respect to
    /// play, purchase, and rewarded-ad history. Only `unlockedItemIDs` grows,
    /// and that set is strictly bounded by the finite launch catalog. Full
    /// ledger entries and reward-offer dedupe keys live in deterministic,
    /// immutable records written atomically with this head.
    struct CloudAccountHeadV3: Codable, Equatable, Sendable {
        static let schemaVersion = DurableEconomyCloudSchema.headSchemaVersion

        let schemaVersion: Int
        let cloudAccountID: CloudAccountID
        let accountBinding: DurableAccountBinding
        let profileAccountIdentity: PlayerAccountIdentity
        var revision: UInt64
        var ledgerAccumulator: LedgerAccumulator
        var unlockedItemIDs: [CatalogItemID]
        var rewardedAd: CloudRewardedAdHeadV1

        enum CodingKeys: String, CodingKey, CaseIterable {
            case schemaVersion
            case cloudAccountID
            case accountBinding
            case profileAccountIdentity
            case revision
            case ledgerAccumulator
            case unlockedItemIDs
            case rewardedAd
        }

        static var persistedFieldManifest: String {
            CodingKeys.allCases.map(\.rawValue)
                .sorted(by: DurableEconomyCloudSchema.utf8Precedes)
                .joined(separator: ",")
        }

        mutating func appendUnlockedItem(_ itemID: CatalogItemID) {
            unlockedItemIDs.append(itemID)
            unlockedItemIDs.sort {
                DurableEconomyCloudSchema.utf8Precedes(
                    $0.rawValue,
                    $1.rawValue
                )
            }
        }
    }

    struct LoadedCloudState: Sendable {
        let state: CloudAccountHeadV3?
        let changeTag: CloudChangeTag?
        let ledgerMarkers: [LedgerEntryID: CloudLedgerMarkerV2]
        let rewardOfferMarkers: [RewardOfferID: CloudRewardOfferMarkerV2]
    }

    struct CommittedMutation: Sendable {
        let state: CloudAccountHeadV3
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
        let gameplayRewardObservations: [LedgerEntryID: RewardedRunObservation]
    }

    private enum CompleteHistoryEvent {
        case gameplay(CloudLedgerMarkerV2)
        case redemption(CloudRewardOfferMarkerV2)

        var position: CloudEconomyEventPosition {
            switch self {
            case let .gameplay(marker): marker.eventPosition
            case let .redemption(marker): marker.eventPosition
            }
        }
    }

    /// Validates one complete, already-discovered immutable economy replica.
    /// Partial known-ID reads must never call this API or claim hydration proof.
    @discardableResult
    func verifyCompleteCloudHistory(
        head: CloudAccountHeadV3,
        ledgerMarkers: [LedgerEntryID: CloudLedgerMarkerV2],
        rewardOfferMarkers: [RewardOfferID: CloudRewardOfferMarkerV2]
    ) throws -> CloudAccountHeadV3 {
        try validateCloudState(head)
        if head.ledgerAccumulator.entryCount == 0 {
            guard head.revision == 0 else {
                throw DurableEconomyCoordinatorError.malformedCloudRecord
            }
        } else {
            guard head.revision > 0,
                  head.revision <= head.ledgerAccumulator.entryCount else {
                throw DurableEconomyCoordinatorError.malformedCloudRecord
            }
        }

        var unlockedItemIDs = Set<CatalogItemID>()
        var events: [CompleteHistoryEvent] = []
        var ledgerPositionOwners: [CloudEconomyEventPosition: LedgerEntryID] = [:]

        for (entryID, marker) in ledgerMarkers.sorted(by: {
            DurableEconomyCloudSchema.utf8Precedes(
                $0.key.rawValue,
                $1.key.rawValue
            )
        }) {
            guard entryID == marker.record.entry.id,
                  marker.schemaVersion == CloudLedgerMarkerV2.schemaVersion,
                  marker.headRecordID == configuration.recordID,
                  ledgerPositionOwners.updateValue(
                      entryID,
                      forKey: marker.eventPosition
                  ) == nil
            else {
                throw DurableEconomyCoordinatorError.invalidRewardEventPosition
            }
            try validateCloudLedgerRecord(marker.record)
            try validateCloudLedgerMarker(marker, headRevision: head.revision)
            switch marker.record.entry.reason {
            case .gameplay:
                events.append(.gameplay(marker))

            case let .rewardedAd(offerID, providerTransactionID):
                guard let offerMarker = rewardOfferMarkers[offerID],
                      offerMarker.redemption.offerID == offerID,
                      offerMarker.redemption.providerTransactionID
                        == providerTransactionID,
                      offerMarker.redemption.ledgerEntryID == entryID,
                      offerMarker.eventPosition == marker.eventPosition,
                      offerMarker.binding == marker.record.binding
                else {
                    throw DurableEconomyCoordinatorError.malformedCloudRecord
                }

            case let .catalogUnlock(itemID):
                guard unlockedItemIDs.insert(itemID).inserted else {
                    throw DurableEconomyCoordinatorError.malformedCloudRecord
                }

            case .signingBonus, .storeKit:
                break
            }
        }

        var offerPositions = Set<CloudEconomyEventPosition>()
        for (offerID, marker) in rewardOfferMarkers.sorted(by: {
            DurableEconomyCloudSchema.utf8Precedes(
                $0.key.rawValue,
                $1.key.rawValue
            )
        }) {
            guard offerID == marker.redemption.offerID,
                  marker.schemaVersion == CloudRewardOfferMarkerV2.schemaVersion,
                  marker.headRecordID == configuration.recordID,
                  marker.binding.kind == .rewardedAd,
                  offerPositions.insert(marker.eventPosition).inserted
            else {
                throw DurableEconomyCoordinatorError.malformedCloudRecord
            }
            try validateMutationBinding(marker.binding)
            try validateEventPosition(
                marker.eventPosition,
                headRevision: head.revision
            )
            let redemption = marker.redemption
            guard let ledgerMarker = ledgerMarkers[redemption.ledgerEntryID],
                  ledgerPositionOwners[marker.eventPosition]
                    == redemption.ledgerEntryID,
                  ledgerMarker.eventPosition == marker.eventPosition,
                  ledgerMarker.record.binding == marker.binding,
                  case let .rewardedAd(ledgerOfferID, providerTransactionID)
                    = ledgerMarker.record.entry.reason,
                  ledgerOfferID == offerID,
                  providerTransactionID == redemption.providerTransactionID
            else {
                throw DurableEconomyCoordinatorError.malformedCloudRecord
            }
            events.append(.redemption(marker))
        }

        let orderedLedgerMarkers = ledgerMarkers.values.sorted {
            $0.eventPosition < $1.eventPosition
        }
        let markersByRevision = Dictionary(
            grouping: orderedLedgerMarkers,
            by: { $0.eventPosition.cloudHeadRevision }
        )
        guard UInt64(markersByRevision.count) == head.revision else {
            throw DurableEconomyCoordinatorError.invalidRewardEventPosition
        }
        var revisionByOperationID: [OperationID: UInt64] = [:]
        for (revision, markers) in markersByRevision {
            let canonical = markers.sorted {
                $0.eventPosition.batchIndex < $1.eventPosition.batchIndex
            }
            guard let binding = canonical.first?.record.binding,
                  canonical.allSatisfy({ $0.record.binding == binding }) else {
                throw DurableEconomyCoordinatorError.malformedCloudRecord
            }
            if let priorRevision = revisionByOperationID.updateValue(
                revision,
                forKey: binding.operationID
            ), priorRevision != revision {
                throw DurableEconomyCoordinatorError.malformedCloudRecord
            }
            for (offset, marker) in canonical.enumerated() {
                guard let expectedIndex = DurableEconomyCloudSchema
                    .batchIndex(forZeroBasedOffset: offset),
                      marker.eventPosition.batchIndex == expectedIndex else {
                    throw DurableEconomyCoordinatorError.invalidRewardEventPosition
                }
            }
            let positionedEntryIDs = canonical.map(\.record.entry.id.rawValue)
            guard positionedEntryIDs == positionedEntryIDs.sorted(
                by: DurableEconomyCloudSchema.utf8Precedes
            ) else {
                throw DurableEconomyCoordinatorError.invalidRewardEventPosition
            }
        }

        var accumulator = LedgerAccumulator.empty
        for marker in orderedLedgerMarkers {
            try add(marker.record.entry, to: &accumulator)
        }

        guard accumulator == head.ledgerAccumulator,
              unlockedItemIDs == Set(head.unlockedItemIDs),
              head.unlockedItemIDs
                == head.unlockedItemIDs.sorted(by: {
                    DurableEconomyCloudSchema.utf8Precedes(
                        $0.rawValue,
                        $1.rawValue
                    )
                })
        else {
            throw DurableEconomyCoordinatorError.cloudStateDiverged
        }

        events.sort { $0.position < $1.position }
        guard Set(events.map(\.position)).count == events.count else {
            throw DurableEconomyCoordinatorError.invalidRewardEventPosition
        }

        var replayed = CloudRewardedAdHeadV1.initial
        for event in events {
            switch event {
            case let .gameplay(marker):
                guard let observation = marker.gameplayRewardObservation,
                      let resolution = marker.gameplayRewardResolution,
                      try replayed.resolveGameplay(observation: observation)
                        == resolution
                else {
                    throw DurableEconomyCoordinatorError.malformedCloudRecord
                }

            case let .redemption(marker):
                try replayed.redeem(marker.redemption.offerID)
            }
        }
        guard replayed == head.rewardedAd else {
            throw DurableEconomyCoordinatorError.cloudStateDiverged
        }
        return head
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
            ids: requestedIDs.sorted {
                DurableEconomyCloudSchema.utf8Precedes(
                    $0.rawValue,
                    $1.rawValue
                )
            }
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
        let state: CloudAccountHeadV3?
        if let headRecord {
            state = try decodeCloudPayload(CloudAccountHeadV3.self, from: headRecord)
            try validateCloudState(state!)
        } else {
            state = nil
        }

        var ledgerMarkers: [LedgerEntryID: CloudLedgerMarkerV2] = [:]
        for (recordID, entryID) in ledgerIDsByRecordID {
            guard let record = recordsByID[recordID] else { continue }
            let marker = try decodeCloudPayload(CloudLedgerMarkerV2.self, from: record)
            guard marker.schemaVersion == CloudLedgerMarkerV2.schemaVersion,
                  marker.headRecordID == configuration.recordID,
                  marker.record.entry.id == entryID
            else {
                throw DurableEconomyCoordinatorError.malformedCloudRecord
            }
            try validateCloudLedgerRecord(marker.record)
            try validateCloudLedgerMarker(marker, headRevision: state?.revision)
            ledgerMarkers[entryID] = marker
        }

        var rewardOfferMarkers: [RewardOfferID: CloudRewardOfferMarkerV2] = [:]
        for (recordID, offerID) in offersByRecordID {
            guard let record = recordsByID[recordID] else { continue }
            let marker = try decodeCloudPayload(
                CloudRewardOfferMarkerV2.self,
                from: record
            )
            guard marker.schemaVersion == CloudRewardOfferMarkerV2.schemaVersion,
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
            try validateEventPosition(
                marker.eventPosition,
                headRevision: state?.revision
            )
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
    ) throws -> CloudAccountHeadV3 {
        if let state = loaded.state { return state }
        guard allowCreation else {
            throw DurableEconomyCoordinatorError.cloudStateDiverged
        }
        return CloudAccountHeadV3(
            schemaVersion: CloudAccountHeadV3.schemaVersion,
            cloudAccountID: context.cloudAccountID,
            accountBinding: context.accountBinding,
            profileAccountIdentity: context.profileSession.accountIdentity,
            revision: 0,
            ledgerAccumulator: .empty,
            unlockedItemIDs: [],
            rewardedAd: .initial
        )
    }

    func validateCloudState(_ state: CloudAccountHeadV3) throws {
        guard state.schemaVersion == CloudAccountHeadV3.schemaVersion,
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
              ),
              state.rewardedAd.schemaVersion == CloudRewardedAdHeadV1.schemaVersion,
              (0 ... PersistedEconomyRulesV1.rewardedAdRunThreshold)
                .contains(state.rewardedAd.validRunsSinceReward)
        else {
            throw DurableEconomyCoordinatorError.malformedCloudRecord
        }
        if state.ledgerAccumulator.entryCount == 0 {
            guard state.ledgerAccumulator.confirmedBalance == 0,
                  state.ledgerAccumulator.digest
                    == LedgerAccumulator.empty.digest,
                  state.unlockedItemIDs.isEmpty,
                  state.rewardedAd == .initial
            else {
                throw DurableEconomyCoordinatorError.malformedCloudRecord
            }
        }

        let expectedOffer = state.rewardedAd.validRunsSinceReward
            == PersistedEconomyRulesV1.rewardedAdRunThreshold
            ? RewardedAdState.offerID(for: state.rewardedAd.cycle)
            : nil
        guard state.rewardedAd.eligibleOfferID == expectedOffer,
              state.rewardedAd.cycle <= state.ledgerAccumulator.entryCount
        else {
            throw DurableEconomyCoordinatorError.malformedCloudRecord
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
                && entry.createdAt
                    == PersistedEconomyRulesV1.signingBonusLedgerCreatedAt
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

    func validateCloudLedgerMarker(
        _ marker: CloudLedgerMarkerV2,
        headRevision: UInt64?
    ) throws {
        try validateEventPosition(marker.eventPosition, headRevision: headRevision)

        switch marker.record.entry.reason {
        case .gameplay:
            guard let observation = marker.gameplayRewardObservation,
                  let resolution = marker.gameplayRewardResolution
            else {
                throw DurableEconomyCoordinatorError.malformedCloudRecord
            }
            try validateGameplayResolution(
                resolution,
                observation: observation
            )
        case .signingBonus, .rewardedAd, .storeKit, .catalogUnlock:
            guard marker.gameplayRewardObservation == nil,
                  marker.gameplayRewardResolution == nil
            else {
                throw DurableEconomyCoordinatorError.malformedCloudRecord
            }
        }
    }

    func validateEventPosition(
        _ position: CloudEconomyEventPosition,
        headRevision: UInt64?
    ) throws {
        guard position.cloudHeadRevision > 0,
              headRevision.map({ position.cloudHeadRevision <= $0 }) ?? true
        else {
            throw DurableEconomyCoordinatorError.invalidRewardEventPosition
        }
    }

    func validateGameplayResolution(
        _ resolution: GameplayRewardResolution,
        observation: RewardedRunObservation
    ) throws {
        let threshold = PersistedEconomyRulesV1.rewardedAdRunThreshold
        switch resolution {
        case let .counted(cycle, resultingCount, unlockedOfferID):
            let expectedOffer = resultingCount == threshold
                ? RewardedAdState.offerID(for: cycle)
                : nil
            guard observation.disposition == .candidate,
                  cycle == observation.observedCycle,
                  (1 ... threshold).contains(resultingCount),
                  unlockedOfferID == expectedOffer
            else {
                throw DurableEconomyCoordinatorError.malformedCloudRecord
            }

        case let .ignoredActiveOffer(cycle, offerID):
            guard cycle == observation.observedCycle,
                  offerID == RewardedAdState.offerID(for: cycle),
                  observation.disposition != .legacyNonCounting
            else {
                throw DurableEconomyCoordinatorError.malformedCloudRecord
            }

        case let .ignoredStaleCycle(observedCycle, currentCycle):
            guard observedCycle == observation.observedCycle,
                  observedCycle < currentCycle,
                  observation.disposition != .legacyNonCounting
            else {
                throw DurableEconomyCoordinatorError.malformedCloudRecord
            }

        case .ignoredLegacyNonCounting:
            guard observation.disposition == .legacyNonCounting,
                  observation.observedCycle == 0 else {
                throw DurableEconomyCoordinatorError.malformedCloudRecord
            }
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
            return try DurableEconomyCloudSchema.makePayloadDecoder().decode(
                type,
                from: payload
            )
        } catch {
            throw DurableEconomyCoordinatorError.malformedCloudRecord
        }
    }

    func commitCreditMutation(
        entries: [LedgerEntryID: CoinLedgerEntry],
        kind: MutationKind,
        operationID: OperationID,
        sourceSnapshot: LocalPlayerProfileSnapshot,
        gameplayRewardObservations: [LedgerEntryID: RewardedRunObservation]
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
                recoversExistingCatalogUnlockTimestamp: false,
                gameplayRewardObservations: gameplayRewardObservations
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
                recoversExistingCatalogUnlockTimestamp: false,
                gameplayRewardObservations: [:]
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

    func gameplayRewardObservations(
        for entries: [LedgerEntryID: CoinLedgerEntry],
        snapshot: LocalPlayerProfileSnapshot
    ) throws -> [LedgerEntryID: RewardedRunObservation] {
        var observations: [LedgerEntryID: RewardedRunObservation] = [:]
        for (entryID, entry) in entries {
            guard case let .gameplay(runID, _) = entry.reason else { continue }
            guard let observation = snapshot.rewardedRunObservations[runID] else {
                throw DurableEconomyCoordinatorError.missingRewardedRunObservation(runID)
            }
            observations[entryID] = observation
        }
        return observations
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
                recoversExistingCatalogUnlockTimestamp: true,
                gameplayRewardObservations: [:]
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
                recoversExistingCatalogUnlockTimestamp: false,
                gameplayRewardObservations: [:]
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
        let gameplayEntryIDs = Set(plan.entries.compactMap { entryID, entry in
            if case .gameplay = entry.reason { return entryID }
            return nil
        })
        guard Set(plan.gameplayRewardObservations.keys) == gameplayEntryIDs else {
            throw DurableEconomyCoordinatorError.malformedCloudRecord
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

            let increment = state.revision.addingReportingOverflow(1)
            guard !increment.overflow else {
                throw DurableEconomyCoordinatorError.cloudRevisionOverflow
            }
            let targetHeadRevision = increment.partialValue
            let binding = mutationBinding(
                kind: plan.kind,
                operationID: operationID,
                sourceEconomyRevision: sourceSnapshot.economyRevision
            )
            let orderedMissingEntries = missingEntries.sorted {
                DurableEconomyCloudSchema.utf8Precedes(
                    $0.key.rawValue,
                    $1.key.rawValue
                )
            }
            var newMarkers: [LedgerEntryID: CloudLedgerMarkerV2] = [:]
            for (offset, element) in orderedMissingEntries.enumerated() {
                let (entryID, entry) = element
                guard let batchIndex = DurableEconomyCloudSchema
                    .batchIndex(forZeroBasedOffset: offset) else {
                    throw DurableEconomyCoordinatorError.invalidRewardEventPosition
                }
                let eventPosition = CloudEconomyEventPosition(
                    cloudHeadRevision: targetHeadRevision,
                    batchIndex: batchIndex
                )
                let cloudRecord = CloudLedgerRecord(entry: entry, binding: binding)
                try validateCloudLedgerRecord(cloudRecord)
                let observation = plan.gameplayRewardObservations[entryID]
                let resolution = try observation.map {
                    try state.rewardedAd.resolveGameplay(observation: $0)
                }
                let marker = CloudLedgerMarkerV2(
                    schemaVersion: CloudLedgerMarkerV2.schemaVersion,
                    headRecordID: configuration.recordID,
                    record: cloudRecord,
                    eventPosition: eventPosition,
                    gameplayRewardObservation: observation,
                    gameplayRewardResolution: resolution
                )
                try validateCloudLedgerMarker(
                    marker,
                    headRevision: targetHeadRevision
                )
                newMarkers[entryID] = marker
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

            var newRewardMarker: CloudRewardOfferMarkerV2?
            if let redemption = plan.rewardRedemption {
                guard missingEntries.count == 1,
                      loaded.rewardOfferMarkers[redemption.offerID] == nil,
                      let ledgerMarker = newMarkers[redemption.ledgerEntryID]
                else {
                    throw DurableEconomyCoordinatorError.cloudRewardCollision(
                        redemption.offerID
                    )
                }
                try state.rewardedAd.redeem(redemption.offerID)
                newRewardMarker = CloudRewardOfferMarkerV2(
                    schemaVersion: CloudRewardOfferMarkerV2.schemaVersion,
                    headRecordID: configuration.recordID,
                    redemption: redemption,
                    binding: binding,
                    eventPosition: ledgerMarker.eventPosition
                )
            }

            state.revision = targetHeadRevision
            try validateCloudState(state)

            var writes = [try makeHeadWrite(state: state, loaded: loaded)]
            for marker in newMarkers.values {
                writes.append(try makeLedgerMarkerWrite(marker))
            }
            if let newRewardMarker {
                writes.append(try makeRewardOfferMarkerWrite(newRewardMarker))
            }
            writes.sort {
                DurableEconomyCloudSchema.utf8Precedes(
                    $0.id.rawValue,
                    $1.id.rawValue
                )
            }
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
                switch error {
                case .conflict:
                    guard conflictCount < configuration.conflictRetryLimit else {
                        throw DurableEconomyCoordinatorError.conflictRetryLimitReached
                    }
                    conflictCount += 1
                    continue

                case let .operationIDCollision(collisionID):
                    guard collisionID == operationID else { throw error }
                    do {
                        return try await exactCollisionRefresh(
                            operationID: operationID,
                            sourceSnapshot: sourceSnapshot,
                            plan: plan,
                            entryIDs: entryIDs,
                            offerIDs: offerIDs,
                            expectedMarkers: newMarkers,
                            expectedRewardMarker: newRewardMarker
                        )
                    } catch {
                        // An operation marker with the same deterministic ID is
                        // not proof unless one exact read establishes the full
                        // immutable target attempted by this coordinator.
                        throw CloudSyncTransportError.operationIDCollision(collisionID)
                    }

                case .accountUnavailable, .accountMismatch:
                    throw error
                }
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

    func exactCollisionRefresh(
        operationID: OperationID,
        sourceSnapshot: LocalPlayerProfileSnapshot,
        plan: MutationPlan,
        entryIDs: Set<LedgerEntryID>,
        offerIDs: Set<RewardOfferID>,
        expectedMarkers: [LedgerEntryID: CloudLedgerMarkerV2],
        expectedRewardMarker: CloudRewardOfferMarkerV2?
    ) async throws -> CommittedMutation {
        // Partial overlap cannot prove which prior request owned the shared
        // operation marker without complete history. Keep that case failed
        // closed for the hydrator instead of treating a partial read as proof.
        guard Set(expectedMarkers.keys) == entryIDs else {
            throw DurableEconomyCoordinatorError.malformedCloudRecord
        }

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

        for (entryID, expected) in expectedMarkers {
            guard let actual = refreshed.ledgerMarkers[entryID],
                  actual.schemaVersion == expected.schemaVersion,
                  actual.headRecordID == expected.headRecordID,
                  (actual.record.entry == expected.record.entry
                    || (plan.recoversExistingCatalogUnlockTimestamp
                        && catalogUnlockEntryMatchesIgnoringTimestamp(
                            actual.record.entry,
                            expected.record.entry
                        ))),
                  collisionEquivalentBinding(
                      actual.record.binding,
                      expected.record.binding
                  ),
                  actual.eventPosition == expected.eventPosition,
                  actual.gameplayRewardObservation
                    == expected.gameplayRewardObservation,
                  actual.gameplayRewardResolution
                    == expected.gameplayRewardResolution
            else {
                throw DurableEconomyCoordinatorError.malformedCloudRecord
            }
        }

        switch (expectedRewardMarker, plan.rewardRedemption) {
        case (nil, nil):
            guard refreshed.rewardOfferMarkers.isEmpty else {
                throw DurableEconomyCoordinatorError.malformedCloudRecord
            }

        case let (expected?, redemption?):
            guard let actual = refreshed.rewardOfferMarkers[redemption.offerID],
                  actual.schemaVersion == expected.schemaVersion,
                  actual.headRecordID == expected.headRecordID,
                  actual.redemption == expected.redemption,
                  actual.eventPosition == expected.eventPosition,
                  collisionEquivalentBinding(actual.binding, expected.binding),
                  let ledger = refreshed.ledgerMarkers[redemption.ledgerEntryID],
                  ledger.eventPosition == actual.eventPosition,
                  ledger.record.binding == actual.binding
            else {
                throw DurableEconomyCoordinatorError.malformedCloudRecord
            }

        case (nil, _?), (_?, nil):
            throw DurableEconomyCoordinatorError.malformedCloudRecord
        }

        return CommittedMutation(
            state: refreshedState,
            receipt: try cloudReceipt(
                operationID: operationID,
                loaded: refreshed,
                state: refreshedState,
                status: .committedThenRefreshed
            ),
            entries: try committedEntries(for: plan, loaded: refreshed)
        )
    }

    func collisionEquivalentBinding(
        _ actual: MutationBinding,
        _ expected: MutationBinding
    ) -> Bool {
        actual.cloudAccountID == expected.cloudAccountID
            && actual.accountBinding == expected.accountBinding
            && actual.profileAccountIdentity == expected.profileAccountIdentity
            && actual.operationID == expected.operationID
            && actual.kind == expected.kind
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
        cloudState: CloudAccountHeadV3,
        targetEntries: [LedgerEntryID: CoinLedgerEntry],
        targetMarkers: [LedgerEntryID: CloudLedgerMarkerV2]
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
            if cloudBase.entryCount > localBase.entryCount {
                throw DurableEconomyCoordinatorError.cloudRebaseRequired
            }
            throw DurableEconomyCoordinatorError.cloudStateDiverged
        }
    }

    func validateMutationMarkers(
        plan: MutationPlan,
        operationID: OperationID,
        loaded: LoadedCloudState,
        state: CloudAccountHeadV3
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
            guard marker.gameplayRewardObservation
                == plan.gameplayRewardObservations[entryID]
            else {
                throw DurableEconomyCoordinatorError.cloudLedgerCollision(entryID)
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
                guard entryMarker.record.binding == offerMarker.binding,
                      entryMarker.eventPosition == offerMarker.eventPosition else {
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
        state: CloudAccountHeadV3,
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
        _ marker: CloudLedgerMarkerV2
    ) throws -> CloudRecordWrite {
        CloudRecordWrite(
            id: ledgerMarkerRecordID(for: marker.record.entry.id),
            recordType: configuration.recordType,
            fields: [configuration.payloadFieldName: try encodeCloudPayload(marker)],
            precondition: .mustNotExist
        )
    }

    func makeRewardOfferMarkerWrite(
        _ marker: CloudRewardOfferMarkerV2
    ) throws -> CloudRecordWrite {
        CloudRecordWrite(
            id: rewardOfferMarkerRecordID(for: marker.redemption.offerID),
            recordType: configuration.recordType,
            fields: [configuration.payloadFieldName: try encodeCloudPayload(marker)],
            precondition: .mustNotExist
        )
    }

    func encodeCloudPayload<T: Encodable>(_ value: T) throws -> Data {
        try DurableEconomyCloudSchema.makePayloadEncoder().encode(value)
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
        state: CloudAccountHeadV3,
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

    func cloudBalance(_ state: CloudAccountHeadV3) throws -> Int64 {
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
        append(DurableEconomyCloudSchema.ledgerDigestDomain, to: &digest)
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
        DurableEconomyCloudSchema.ledgerMarkerRecordID(
            for: entryID,
            headRecordID: configuration.recordID
        )
    }

    func rewardOfferMarkerRecordID(for offerID: RewardOfferID) -> CloudRecordID {
        DurableEconomyCloudSchema.rewardOfferMarkerRecordID(
            for: offerID,
            headRecordID: configuration.recordID
        )
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
        DurableEconomyOperationAddressV3.operationID(
            kind: kind,
            entryIDs: entryIDs,
            cloudAccountID: context.cloudAccountID,
            accountBinding: context.accountBinding,
            profileAccountIdentity: context.profileSession.accountIdentity
        )
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
    func validateCloudUnlockPrerequisites(_ state: CloudAccountHeadV3) throws {
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

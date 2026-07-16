import Foundation

struct PlayerAccountIdentity: RawRepresentable, Codable, Equatable, Hashable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        precondition(!rawValue.isEmpty, "PlayerAccountIdentity cannot be empty")
        self.rawValue = rawValue
    }

    init(_ rawValue: String) {
        self.init(rawValue: rawValue)
    }

    static let local = PlayerAccountIdentity("local-player")
}

struct ProfileSessionToken: Equatable, Hashable, Sendable {
    let accountIdentity: PlayerAccountIdentity
    let nonce: UUID
    let profileID: UUID
}

struct LocalPlayerDocumentV1: Codable, Equatable, Sendable {
    var accountIdentity: PlayerAccountIdentity
    var player: PlayerDocumentV1
    var economyRevision: UInt64
    var pendingLedgerEntryIDs: Set<LedgerEntryID>
    var settlementReceipts: [RunID: RunSettlementOutcome]
    /// Optional only at the Codable boundary for legacy V1 envelopes. The V1
    /// migrator immediately supplies explicit non-counting observations, and
    /// every V2-or-later document persists a complete map.
    var rewardedRunObservations: [RunID: RewardedRunObservation]?
}

struct PlayerProfileEnvelopeV1: Codable, Equatable, Sendable {
    static let formatIdentifier = "com.pocketvector.player-profile"
    static let schemaVersion = 1

    let format: String
    let schemaVersion: Int
    let savedAt: Date
    let document: LocalPlayerDocumentV1

    init(document: LocalPlayerDocumentV1, savedAt: Date) {
        format = Self.formatIdentifier
        schemaVersion = Self.schemaVersion
        self.savedAt = savedAt
        self.document = document
    }
}

struct PlayerProfileEnvelopeV2: Codable, Equatable, Sendable {
    static let formatIdentifier = PlayerProfileEnvelopeV1.formatIdentifier
    static let schemaVersion = 2

    let format: String
    let schemaVersion: Int
    let savedAt: Date
    let document: LocalPlayerDocumentV1

    init(document: LocalPlayerDocumentV1, savedAt: Date) {
        format = Self.formatIdentifier
        schemaVersion = Self.schemaVersion
        self.savedAt = savedAt
        self.document = document
    }
}

struct PlayerProfileEnvelopeV3: Codable, Equatable, Sendable {
    static let formatIdentifier = PlayerProfileEnvelopeV1.formatIdentifier
    static let schemaVersion = 3

    let format: String
    let schemaVersion: Int
    let savedAt: Date
    let document: LocalPlayerDocumentV1

    init(document: LocalPlayerDocumentV1, savedAt: Date) {
        format = Self.formatIdentifier
        schemaVersion = Self.schemaVersion
        self.savedAt = savedAt
        self.document = document
    }
}

struct CoinBalanceSummary: Equatable, Sendable {
    let confirmed: Int64
    let pending: Int64

    var total: Int64 {
        confirmed + pending
    }

    var availableToSpend: Int64 {
        confirmed
    }
}

struct LocalPlayerProfileSnapshot: Equatable, Sendable {
    let session: ProfileSessionToken
    let player: PlayerSnapshot
    let economyRevision: UInt64
    let coinBalances: CoinBalanceSummary
    let completedRuns: [RunID: CompletedRunRecord]
    let ledger: [LedgerEntryID: CoinLedgerEntry]
    let pendingLedgerEntryIDs: Set<LedgerEntryID>
    let rewardedRunObservations: [RunID: RewardedRunObservation]

    init(
        session: ProfileSessionToken,
        player: PlayerSnapshot,
        economyRevision: UInt64,
        coinBalances: CoinBalanceSummary,
        completedRuns: [RunID: CompletedRunRecord],
        ledger: [LedgerEntryID: CoinLedgerEntry],
        pendingLedgerEntryIDs: Set<LedgerEntryID>,
        rewardedRunObservations: [RunID: RewardedRunObservation] = [:]
    ) {
        self.session = session
        self.player = player
        self.economyRevision = economyRevision
        self.coinBalances = coinBalances
        self.completedRuns = completedRuns
        self.ledger = ledger
        self.pendingLedgerEntryIDs = pendingLedgerEntryIDs
        self.rewardedRunObservations = rewardedRunObservations
    }

    var personalBest: Int {
        player.career.highestScore
    }
}

struct RunSettlementOutcome: Codable, Equatable, Sendable {
    let record: CompletedRunRecord
    let gameplayRewardEntryID: LedgerEntryID?
    let signingBonusEntryID: LedgerEntryID?
    let achievementUpdates: [AchievementProgressUpdate]
    let rewardedOfferUnlocked: RewardOfferID?
    let resultingPersonalBest: Int
}

struct RunSettlementResult: Equatable, Sendable {
    let outcome: RunSettlementOutcome
    let wasAlreadySettled: Bool
}

struct CatalogUnlockOutcome: Equatable, Sendable {
    let itemID: CatalogItemID
    let price: Int64
    let wasAlreadyUnlocked: Bool
    let confirmedBalanceAfter: Int64
}

enum EconomyStateAuthority: String, Codable, Equatable, Sendable {
    case durablePrivateCloud
    case localTest
}

enum EconomyMutationPolicy: Equatable, Sendable {
    case requireDurablePrivateCloud
    case allowLocalTesting

    func permits(_ authority: EconomyStateAuthority) -> Bool {
        switch (self, authority) {
        case (.requireDurablePrivateCloud, .durablePrivateCloud),
             (.allowLocalTesting, .durablePrivateCloud),
             (.allowLocalTesting, .localTest):
            true
        case (.requireDurablePrivateCloud, .localTest):
            false
        }
    }
}

/// Evidence supplied by a future CloudKit adapter when a positive credit has
/// reached durable private-cloud state. `localTest` is rejected by production
/// repositories and exists only to exercise the transactional core.
struct DurableEconomyConfirmation: Equatable, Sendable {
    let confirmationID: OperationID
    let session: ProfileSessionToken
    let entries: [LedgerEntryID: CoinLedgerEntry]
    let expectedEconomyRevision: UInt64
    let confirmedBalanceBefore: Int64
    let confirmedAt: Date
    let authority: EconomyStateAuthority

    var entryIDs: Set<LedgerEntryID> {
        Set(entries.keys)
    }
}

/// Returned only after the catalog debit and ownership grant have committed in
/// the same durable private-cloud operation. Local inventory is never changed
/// before this receipt is presented to the repository.
struct DurableCatalogUnlockRequest: Equatable, Sendable {
    let operationID: OperationID
    let session: ProfileSessionToken
    let itemID: CatalogItemID
    let ledgerEntryID: LedgerEntryID
    let price: Int64
    let expectedEconomyRevision: UInt64
    let confirmedBalanceBefore: Int64
}

struct DurableCatalogUnlockReceipt: Equatable, Sendable {
    let receiptID: OperationID
    let requestOperationID: OperationID
    let session: ProfileSessionToken
    let itemID: CatalogItemID
    let ledgerEntryID: LedgerEntryID
    let price: Int64
    let expectedEconomyRevision: UInt64
    let confirmedBalanceBefore: Int64
    let confirmedBalanceAfter: Int64
    let confirmedAt: Date
    let authority: EconomyStateAuthority
}

struct DurableRewardedAdReceipt: Equatable, Sendable {
    let receiptID: OperationID
    let session: ProfileSessionToken
    let offerID: RewardOfferID
    let providerTransactionID: AdProviderTransactionID
    let expectedEconomyRevision: UInt64
    let confirmedBalanceBefore: Int64
    let rewardedAt: Date
    let authority: EconomyStateAuthority
}

struct RewardedAdSettlementOutcome: Equatable, Sendable {
    let offerID: RewardOfferID
    let providerTransactionID: AdProviderTransactionID
    let ledgerEntryID: LedgerEntryID
    let coins: Int64
    let wasAlreadySettled: Bool
    let confirmedBalanceAfter: Int64
}

enum CompletedRunValidationError: Error, Equatable, Sendable {
    case debugPreviewNotPersistable
    case invalidChronology
    case invalidElapsedMilliseconds(Int)
    case invalidScore(Int)
    case invalidStatistics
    case invalidLaneHistory
    case unsupportedEconomyVersion(Int)
    case unknownOffenseTeam(TeamID)
    case offenseTeamNotOwned(TeamID)
    case invalidOffenseJersey(JerseyID)
    case offenseJerseyNotOwned(JerseyID)
    case unknownDefenseTeam(TeamID)
    case sameTeamMatchup(TeamID)
    case invalidDefenseJersey(JerseyID)
    case invalidFootball(FootballID)
    case footballNotOwned(FootballID)
}

enum ProfileLoadSource: String, Equatable, Sendable {
    case primary
    case backup
    case createdFresh
}

struct ProfileLoadReport: Equatable, Sendable {
    let source: ProfileLoadSource
    let quarantinedURLs: [URL]
}

struct ProfileStorageLocations: Equatable, Sendable {
    let directoryURL: URL
    let primaryURL: URL
    let backupURL: URL
    let quarantineDirectoryURL: URL

    init(directoryURL: URL) {
        self.directoryURL = directoryURL
        primaryURL = directoryURL.appendingPathComponent("player-profile.json")
        backupURL = directoryURL.appendingPathComponent("player-profile.backup.json")
        quarantineDirectoryURL = directoryURL.appendingPathComponent(
            "Quarantine",
            isDirectory: true
        )
    }
}

enum ProfileMigrationError: Error, Equatable {
    case malformedEnvelope
    case unexpectedFormat(String)
    case unsupportedSchemaVersion(Int)
}

enum ProfileValidationError: Error, Equatable {
    case invalidAccountIdentity
    case ledgerKeyMismatch(LedgerEntryID)
    case runKeyMismatch(RunID)
    case receiptKeyMismatch(RunID)
    case missingRunRecord(RunID)
    case orphanSettlementReceipt(RunID)
    case receiptDoesNotMatchRun(RunID)
    case pendingEntryMissing(LedgerEntryID)
    case pendingEntryMustBePositive(LedgerEntryID)
    case invalidSigningBonus(LedgerEntryID)
    case multipleSigningBonuses
    case rewardLedgerMismatch(RunID)
    case rewardCalculationMismatch(RunID)
    case invalidRunStatistics(RunID)
    case invalidCompletedRun(RunID, CompletedRunValidationError)
    case orphanGameplayLedger(RunID)
    case invalidCatalogUnlock(CatalogItemID)
    case invalidStoreKitCredit(LedgerEntryID)
    case invalidRewardedAdCredit(LedgerEntryID)
    case unknownOwnedTeam(TeamID)
    case unknownOwnedJersey(JerseyID)
    case unknownOwnedFootball(FootballID)
    case missingOwnedPrimaryJersey(TeamID)
    case alternateOwnedWithoutTeam(JerseyID)
    case jerseyOwnedWithoutTeam(JerseyID)
    case invalidRememberedJersey(teamID: TeamID, jerseyID: JerseyID)
    case invalidSelection(InventoryRuleError)
    case invalidSelectionStamp
    case invalidSettings
    case invalidSettingsStamp
    case invalidAchievementProgress(AchievementID)
    case invalidRewardedAdState
    case invalidRewardedRunObservation(RunID)
    case missingRewardedRunObservations
    case careerAggregateMismatch
    case invalidLedger(CoinLedgerValidationError)
    case arithmeticOverflow
}

enum LocalPlayerRepositoryError: Error, Equatable {
    case notLoaded
    case accountIdentityMismatch(
        expected: PlayerAccountIdentity,
        actual: PlayerAccountIdentity
    )
    case sessionInvalidated
    case sessionMismatch
    case invalidRun(CompletedRunValidationError)
    case runIDConflict(RunID)
    case ledgerIDConflict(LedgerEntryID)
    case invalidCredit(LedgerEntryID)
    case pendingCreditNotFound(LedgerEntryID)
    case economyAuthorityRejected(EconomyStateAuthority)
    case economyConfirmationBindingMismatch
    case durableUnlockReceiptMismatch
    case rewardedAdReceiptMismatch
    case rewardedOfferNotEligible(RewardOfferID)
    case economyStateProfileMismatch
    case economyStateStale(expected: UInt64, actual: UInt64)
    case economyBalanceStale(expected: Int64, actual: Int64)
    case economyStateExpired
    case insufficientConfirmedCoins(required: Int64, available: Int64)
    case inventory(InventoryRuleError)
    case validation(ProfileValidationError)
}

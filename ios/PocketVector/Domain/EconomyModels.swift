import Foundation

enum CoinLedgerReason: Codable, Equatable, Hashable, Sendable {
    case gameplay(runID: RunID, economyVersion: Int)
    case signingBonus(version: Int)
    case rewardedAd(
        offerID: RewardOfferID,
        providerTransactionID: AdProviderTransactionID
    )
    case storeKit(transactionID: UInt64, packID: CoinPackID)
    case catalogUnlock(itemID: CatalogItemID)

    enum PersistedCase: String, CaseIterable {
        case gameplay
        case signingBonus
        case rewardedAd
        case storeKit
        case catalogUnlock

        var associatedFields: [String] {
            switch self {
            case .gameplay:
                ["runID", "economyVersion"]
            case .signingBonus:
                ["version"]
            case .rewardedAd:
                ["offerID", "providerTransactionID"]
            case .storeKit:
                ["transactionID", "packID"]
            case .catalogUnlock:
                ["itemID"]
            }
        }
    }

    static var persistedCaseManifest: String {
        PersistedCase.allCases.sorted {
            $0.rawValue.utf8.lexicographicallyPrecedes($1.rawValue.utf8)
        }.map { persistedCase in
            let fields = persistedCase.associatedFields.sorted {
                $0.utf8.lexicographicallyPrecedes($1.utf8)
            }.joined(separator: ",")
            return "\(persistedCase.rawValue)(\(fields))"
        }.joined(separator: ",")
    }
}

struct CoinLedgerEntry: Codable, Equatable, Hashable, Sendable {
    let id: LedgerEntryID
    let delta: Int64
    let reason: CoinLedgerReason
    let createdAt: Date

    enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case delta
        case reason
        case createdAt
    }

    static var persistedFieldManifest: String {
        CodingKeys.allCases.map(\.rawValue).sorted().joined(separator: ",")
    }
}

enum CoinLedgerID {
    static let addressSchemaIdentifier = "pocket-vector-coin-ledger-addresses-v1"
    static let gameplayPrefix = "run/"
    static let gameplaySuffix = "/reward"
    static let signingBonusPrefix = "signing-bonus/v"
    static let rewardedAdPrefix = "rewarded-ad/"
    static let storeKitPrefix = "storekit/"
    static let catalogUnlockPrefix = "unlock/"

    static var fingerprintMaterial: [String] {
        [
            addressSchemaIdentifier,
            "gameplayPrefix", gameplayPrefix,
            "gameplaySuffix", gameplaySuffix,
            "signingBonusPrefix", signingBonusPrefix,
            "rewardedAdPrefix", rewardedAdPrefix,
            "storeKitPrefix", storeKitPrefix,
            "catalogUnlockPrefix", catalogUnlockPrefix,
        ]
    }

    static func gameplay(runID: RunID) -> LedgerEntryID {
        LedgerEntryID("\(gameplayPrefix)\(runID.description)\(gameplaySuffix)")
    }

    static func signingBonus(version: Int) -> LedgerEntryID {
        LedgerEntryID("\(signingBonusPrefix)\(version)")
    }

    static func rewardedAd(
        providerTransactionID: AdProviderTransactionID
    ) -> LedgerEntryID {
        LedgerEntryID("\(rewardedAdPrefix)\(providerTransactionID.rawValue)")
    }

    static func storeKit(transactionID: UInt64) -> LedgerEntryID {
        LedgerEntryID("\(storeKitPrefix)\(transactionID)")
    }

    static func catalogUnlock(itemID: CatalogItemID) -> LedgerEntryID {
        LedgerEntryID("\(catalogUnlockPrefix)\(itemID.rawValue)")
    }
}

enum CoinLedgerValidationError: Error, Equatable {
    case invalidDelta(LedgerEntryID)
    case overflow
    case negativeBalance(Int64)
}

enum CoinLedger {
    static func balance(entries: some Sequence<CoinLedgerEntry>) throws -> Int64 {
        var balance: Int64 = 0
        for entry in entries {
            try validateSign(of: entry)
            let addition = balance.addingReportingOverflow(entry.delta)
            guard !addition.overflow else {
                throw CoinLedgerValidationError.overflow
            }
            balance = addition.partialValue
        }
        guard balance >= 0 else {
            throw CoinLedgerValidationError.negativeBalance(balance)
        }
        return balance
    }

    private static func validateSign(of entry: CoinLedgerEntry) throws {
        let signIsValid: Bool
        switch entry.reason {
        case .gameplay, .signingBonus, .rewardedAd, .storeKit:
            signIsValid = entry.delta > 0
        case .catalogUnlock:
            signIsValid = entry.delta < 0
        }
        guard signIsValid else {
            throw CoinLedgerValidationError.invalidDelta(entry.id)
        }
    }
}

struct RewardedAdState: Codable, Equatable, Sendable {
    static let offerAddressSchemaIdentifier =
        "pocket-vector-rewarded-ad-offer-address-v1"
    static let offerIDPrefix = "reward-cycle/"

    static var offerAddressFingerprintMaterial: [String] {
        [
            offerAddressSchemaIdentifier,
            "offerIDPrefix", offerIDPrefix,
        ]
    }

    private(set) var cycle: UInt64
    private(set) var validRunsSinceReward: Int
    private(set) var eligibleOfferID: RewardOfferID?
    private(set) var accountedRunIDs: Set<RunID>

    init(
        cycle: UInt64 = 0,
        validRunsSinceReward: Int = 0,
        eligibleOfferID: RewardOfferID? = nil,
        accountedRunIDs: Set<RunID> = []
    ) {
        self.cycle = cycle
        self.validRunsSinceReward = min(
            EconomyConfiguration.rewardedAdRunThreshold,
            max(0, validRunsSinceReward)
        )
        self.eligibleOfferID = eligibleOfferID
        self.accountedRunIDs = accountedRunIDs
        if self.validRunsSinceReward == EconomyConfiguration.rewardedAdRunThreshold,
           self.eligibleOfferID == nil {
            self.eligibleOfferID = Self.offerID(for: cycle)
        }
    }

    var isEligible: Bool {
        eligibleOfferID != nil
    }

    @discardableResult
    mutating func recordValidRun(_ runID: RunID) -> Bool {
        guard accountedRunIDs.insert(runID).inserted else { return false }
        guard eligibleOfferID == nil else {
            // Runs never bank while an offer is waiting for the player's choice.
            return false
        }

        validRunsSinceReward = min(
            EconomyConfiguration.rewardedAdRunThreshold,
            validRunsSinceReward + 1
        )
        if validRunsSinceReward == EconomyConfiguration.rewardedAdRunThreshold {
            eligibleOfferID = Self.offerID(for: cycle)
            return true
        }
        return false
    }

    @discardableResult
    mutating func redeem(_ offerID: RewardOfferID) -> Bool {
        guard eligibleOfferID == offerID else { return false }
        cycle += 1
        validRunsSinceReward = 0
        eligibleOfferID = nil
        return true
    }

    static func offerID(for cycle: UInt64) -> RewardOfferID {
        RewardOfferID("\(offerIDPrefix)\(cycle)")
    }
}

/// Immutable context captured when a reward-eligible run settles locally.
///
/// The cloud economy head owns the canonical reward cycle. A run created while
/// offline must retain the cycle the device actually observed so a delayed
/// upload can never become progress in a later cycle after another device has
/// redeemed the offer.
struct RewardedRunObservation: Codable, Equatable, Sendable {
    enum Disposition: String, Codable, CaseIterable, Equatable, Sendable {
        case candidate
        case ignoredWhileOfferPending
        /// A pre-observation-schema run whose original reward cycle cannot be
        /// reconstructed safely. Its gameplay coins remain deliverable, but it
        /// can never contribute rewarded-ad progress.
        case legacyNonCounting
    }

    let observedCycle: UInt64
    let disposition: Disposition

    enum CodingKeys: String, CodingKey, CaseIterable {
        case observedCycle
        case disposition
    }

    static var persistedFieldManifest: String {
        CodingKeys.allCases.map(\.rawValue).sorted().joined(separator: ",")
    }

    static var dispositionCaseManifest: String {
        Disposition.allCases.map(\.rawValue).sorted().joined(separator: ",")
    }
}

struct CoinPackDescriptor: Codable, Equatable, Hashable, Sendable {
    let id: CoinPackID
    let displayName: String
    let coins: Int64
    let proposedUSPrice: Decimal
}

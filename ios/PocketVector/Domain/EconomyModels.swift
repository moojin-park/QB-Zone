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
}

struct CoinLedgerEntry: Codable, Equatable, Hashable, Sendable {
    let id: LedgerEntryID
    let delta: Int64
    let reason: CoinLedgerReason
    let createdAt: Date
}

enum CoinLedgerID {
    static func gameplay(runID: RunID) -> LedgerEntryID {
        LedgerEntryID("run/\(runID.description)/reward")
    }

    static func signingBonus(version: Int) -> LedgerEntryID {
        LedgerEntryID("signing-bonus/v\(version)")
    }

    static func rewardedAd(
        providerTransactionID: AdProviderTransactionID
    ) -> LedgerEntryID {
        LedgerEntryID("rewarded-ad/\(providerTransactionID.rawValue)")
    }

    static func storeKit(transactionID: UInt64) -> LedgerEntryID {
        LedgerEntryID("storekit/\(transactionID)")
    }

    static func catalogUnlock(itemID: CatalogItemID) -> LedgerEntryID {
        LedgerEntryID("unlock/\(itemID.rawValue)")
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
        RewardOfferID("reward-cycle/\(cycle)")
    }
}

struct CoinPackDescriptor: Codable, Equatable, Hashable, Sendable {
    let id: CoinPackID
    let displayName: String
    let coins: Int64
    let proposedUSPrice: Decimal
}

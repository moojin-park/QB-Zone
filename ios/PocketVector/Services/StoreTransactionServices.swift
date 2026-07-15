import Foundation

struct StoreProduct: Codable, Equatable, Sendable {
    let packID: CoinPackID
    let displayName: String
    let displayPrice: String
    let coins: Int64
}

enum StoreTransactionVerification: Codable, Equatable, Sendable {
    case verified
    case unverified(reason: String)
}

struct StoreTransactionEnvelope: Codable, Equatable, Sendable {
    let transactionID: UInt64
    let packID: CoinPackID
    let appAccountToken: UUID?
    let verification: StoreTransactionVerification
}

enum StorePurchaseResult: Codable, Equatable, Sendable {
    case success(StoreTransactionEnvelope)
    case pending
    case userCancelled
}

protocol StoreTransactionServicing: Sendable {
    func products(for packIDs: [CoinPackID]) async throws -> [StoreProduct]
    func purchase(_ packID: CoinPackID, appAccountToken: UUID) async throws -> StorePurchaseResult
    func unfinishedTransactions() async -> [StoreTransactionEnvelope]
    func transactionUpdates() async -> AsyncStream<StoreTransactionEnvelope>
    func finish(transactionID: UInt64) async throws
}

enum StoreTransactionDeliveryPhase: String, Codable, Equatable, Sendable {
    case awaitingDurableLedger
    case ledgerAcknowledged
    case finished
}

struct StoreTransactionDeliveryRecord: Codable, Equatable, Sendable {
    let transaction: StoreTransactionEnvelope
    let pack: CoinPackDescriptor
    let binding: StoreAccountBinding
    var commandSessionNonce: UUID
    var phase: StoreTransactionDeliveryPhase

    var commandSession: StoreActiveSession {
        StoreActiveSession(binding: binding, nonce: commandSessionNonce)
    }
}

struct StoreLedgerAcknowledgement: Codable, Equatable, Sendable {
    let transactionID: UInt64
    let ledgerEntryID: LedgerEntryID
    let session: StoreActiveSession
}

enum StoreTransactionRejection: Codable, Equatable, Sendable {
    case unverified
    case missingAppAccountToken
    case appAccountTokenMismatch
    case unknownCoinPack
    case transactionIDCollision
    case accountBindingMismatch
    case staleSession
    case invalidLedgerAcknowledgement
}

enum StoreTransactionDeliveryCommand: Codable, Equatable, Sendable {
    case settleLedger(
        session: StoreActiveSession,
        transaction: StoreTransactionEnvelope,
        pack: CoinPackDescriptor,
        ledgerEntryID: LedgerEntryID
    )
    case finish(session: StoreActiveSession, transactionID: UInt64)
    case reject(transactionID: UInt64, reason: StoreTransactionRejection)
}

struct StoreTransactionDeliveryReducer: Codable, Equatable, Sendable {
    private(set) var records: [UInt64: StoreTransactionDeliveryRecord] = [:]

    mutating func receive(
        _ transaction: StoreTransactionEnvelope,
        currentSession: StoreActiveSession
    ) -> [StoreTransactionDeliveryCommand] {
        if var existing = records[transaction.transactionID] {
            guard existing.transaction == transaction else {
                return rejection(transaction.transactionID, .transactionIDCollision)
            }
            guard existing.binding == currentSession.binding else {
                return rejection(transaction.transactionID, .accountBindingMismatch)
            }
            guard transaction.appAccountToken == currentSession.binding.appAccountToken else {
                return rejection(transaction.transactionID, .appAccountTokenMismatch)
            }
            guard approvedPack(for: transaction.packID) == existing.pack else {
                return rejection(transaction.transactionID, .unknownCoinPack)
            }

            let isRelaunchRebind = existing.commandSessionNonce != currentSession.nonce
            if isRelaunchRebind {
                existing.commandSessionNonce = currentSession.nonce
                records[transaction.transactionID] = existing
            }

            switch existing.phase {
            case .awaitingDurableLedger:
                return isRelaunchRebind ? [settlementCommand(for: existing)] : []
            case .ledgerAcknowledged:
                return [
                    .finish(
                        session: currentSession,
                        transactionID: transaction.transactionID
                    ),
                ]
            case .finished:
                return []
            }
        }

        guard transaction.verification == .verified else {
            return rejection(transaction.transactionID, .unverified)
        }
        guard let token = transaction.appAccountToken else {
            return rejection(transaction.transactionID, .missingAppAccountToken)
        }
        guard token == currentSession.binding.appAccountToken else {
            return rejection(transaction.transactionID, .appAccountTokenMismatch)
        }
        guard let pack = approvedPack(for: transaction.packID) else {
            return rejection(transaction.transactionID, .unknownCoinPack)
        }

        let record = StoreTransactionDeliveryRecord(
            transaction: transaction,
            pack: pack,
            binding: currentSession.binding,
            commandSessionNonce: currentSession.nonce,
            phase: .awaitingDurableLedger
        )
        records[transaction.transactionID] = record
        return [settlementCommand(for: record)]
    }

    mutating func recoveryCommands(
        rebindingTo currentSession: StoreActiveSession
    ) -> [StoreTransactionDeliveryCommand] {
        var commands: [StoreTransactionDeliveryCommand] = []
        for transactionID in records.keys.sorted() {
            guard var record = records[transactionID],
                  record.binding == currentSession.binding else {
                continue
            }

            record.commandSessionNonce = currentSession.nonce
            records[transactionID] = record
            switch record.phase {
            case .awaitingDurableLedger:
                commands.append(settlementCommand(for: record))
            case .ledgerAcknowledged:
                commands.append(
                    .finish(
                        session: currentSession,
                        transactionID: transactionID
                    )
                )
            case .finished:
                break
            }
        }
        return commands
    }

    mutating func acknowledgeDurableLedger(
        _ acknowledgement: StoreLedgerAcknowledgement,
        currentSession: StoreActiveSession
    ) -> [StoreTransactionDeliveryCommand] {
        guard var record = records[acknowledgement.transactionID] else {
            return rejection(acknowledgement.transactionID, .invalidLedgerAcknowledgement)
        }
        guard record.binding == currentSession.binding else {
            return rejection(acknowledgement.transactionID, .accountBindingMismatch)
        }
        guard acknowledgement.session == currentSession,
              record.commandSessionNonce == currentSession.nonce else {
            return rejection(acknowledgement.transactionID, .staleSession)
        }
        guard acknowledgement.ledgerEntryID == CoinLedgerID.storeKit(
            transactionID: acknowledgement.transactionID
        ) else {
            return rejection(acknowledgement.transactionID, .invalidLedgerAcknowledgement)
        }

        switch record.phase {
        case .awaitingDurableLedger:
            record.phase = .ledgerAcknowledged
            records[acknowledgement.transactionID] = record
            return [
                .finish(
                    session: currentSession,
                    transactionID: acknowledgement.transactionID
                ),
            ]
        case .ledgerAcknowledged:
            return [
                .finish(
                    session: currentSession,
                    transactionID: acknowledgement.transactionID
                ),
            ]
        case .finished:
            return []
        }
    }

    @discardableResult
    mutating func finishDidSucceed(
        transactionID: UInt64,
        session: StoreActiveSession
    ) -> Bool {
        guard var record = records[transactionID],
              record.binding == session.binding,
              record.commandSessionNonce == session.nonce,
              record.phase == .ledgerAcknowledged else {
            return false
        }
        record.phase = .finished
        records[transactionID] = record
        return true
    }

    private func approvedPack(for id: CoinPackID) -> CoinPackDescriptor? {
        EconomyConfiguration.coinPacks.first { $0.id == id }
    }

    private func settlementCommand(
        for record: StoreTransactionDeliveryRecord
    ) -> StoreTransactionDeliveryCommand {
        .settleLedger(
            session: record.commandSession,
            transaction: record.transaction,
            pack: record.pack,
            ledgerEntryID: CoinLedgerID.storeKit(
                transactionID: record.transaction.transactionID
            )
        )
    }

    private func rejection(
        _ transactionID: UInt64,
        _ reason: StoreTransactionRejection
    ) -> [StoreTransactionDeliveryCommand] {
        [.reject(transactionID: transactionID, reason: reason)]
    }
}

actor InMemoryStoreTransactionService: StoreTransactionServicing {
    private var productsByID: [CoinPackID: StoreProduct]
    private var purchaseResults: [CoinPackID: StorePurchaseResult]
    private var unfinished: [StoreTransactionEnvelope]
    private var continuations: [UUID: AsyncStream<StoreTransactionEnvelope>.Continuation] = [:]
    private var nextFailure: StoreTransactionServiceError?
    private(set) var purchaseRequests: [(CoinPackID, UUID)] = []
    private(set) var finishedTransactionIDs: [UInt64] = []

    init(
        products: [StoreProduct] = [],
        unfinishedTransactions: [StoreTransactionEnvelope] = []
    ) {
        productsByID = Dictionary(uniqueKeysWithValues: products.map { ($0.packID, $0) })
        purchaseResults = [:]
        unfinished = unfinishedTransactions
    }

    func products(for packIDs: [CoinPackID]) throws -> [StoreProduct] {
        if let nextFailure { throw nextFailure }
        return packIDs.compactMap { productsByID[$0] }
    }

    func purchase(
        _ packID: CoinPackID,
        appAccountToken: UUID
    ) throws -> StorePurchaseResult {
        if let nextFailure { throw nextFailure }
        purchaseRequests.append((packID, appAccountToken))
        return purchaseResults[packID] ?? .userCancelled
    }

    func unfinishedTransactions() -> [StoreTransactionEnvelope] {
        unfinished
    }

    func transactionUpdates() -> AsyncStream<StoreTransactionEnvelope> {
        let continuationID = UUID()
        return AsyncStream { continuation in
            continuations[continuationID] = continuation
        }
    }

    func finish(transactionID: UInt64) throws {
        if let nextFailure { throw nextFailure }
        finishedTransactionIDs.append(transactionID)
        unfinished.removeAll { $0.transactionID == transactionID }
    }

    func setPurchaseResult(_ result: StorePurchaseResult, for packID: CoinPackID) {
        purchaseResults[packID] = result
    }

    func setFailure(_ failure: StoreTransactionServiceError?) {
        nextFailure = failure
    }

    func emit(_ transaction: StoreTransactionEnvelope) {
        for continuation in continuations.values {
            continuation.yield(transaction)
        }
    }

    func addUnfinished(_ transaction: StoreTransactionEnvelope) {
        unfinished.append(transaction)
    }
}

enum StoreTransactionServiceError: Error, Equatable, Sendable {
    case unavailable
    case productNotFound
    case finishFailed
}

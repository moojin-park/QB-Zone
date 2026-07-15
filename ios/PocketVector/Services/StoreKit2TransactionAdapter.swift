import Foundation
@preconcurrency import StoreKit

enum StoreKit2ProductConfigurationError: Error, Equatable, Sendable {
    case invalidLaunchPackSet
    case emptyProductIdentifier(CoinPackID)
    case duplicateProductIdentifier
    case unsupportedPack(CoinPackID)
}

/// App Store Connect product identifiers are injected by app composition. The
/// configuration deliberately has no production defaults and accepts exactly
/// the four consumable packs in the approved launch economy.
struct StoreKit2ProductConfiguration: Equatable, Sendable {
    private let productIdentifierByPackID: [CoinPackID: String]
    private let packIDByProductIdentifier: [String: CoinPackID]

    init(productIdentifiers: [CoinPackID: String]) throws {
        let launchPackIDs = Set(EconomyConfiguration.coinPacks.map(\.id))
        guard productIdentifiers.count == launchPackIDs.count,
              Set(productIdentifiers.keys) == launchPackIDs else {
            throw StoreKit2ProductConfigurationError.invalidLaunchPackSet
        }

        var normalizedByPackID: [CoinPackID: String] = [:]
        for pack in EconomyConfiguration.coinPacks {
            guard let identifier = productIdentifiers[pack.id] else {
                throw StoreKit2ProductConfigurationError.invalidLaunchPackSet
            }
            let normalized = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else {
                throw StoreKit2ProductConfigurationError.emptyProductIdentifier(pack.id)
            }
            normalizedByPackID[pack.id] = normalized
        }
        guard Set(normalizedByPackID.values).count == launchPackIDs.count else {
            throw StoreKit2ProductConfigurationError.duplicateProductIdentifier
        }

        productIdentifierByPackID = normalizedByPackID
        packIDByProductIdentifier = Dictionary(
            uniqueKeysWithValues: normalizedByPackID.map { ($0.value, $0.key) }
        )
    }

    var orderedLaunchPackIDs: [CoinPackID] {
        EconomyConfiguration.coinPacks.map(\.id)
    }

    var allProductIdentifiers: Set<String> {
        Set(productIdentifierByPackID.values)
    }

    func productIdentifier(for packID: CoinPackID) throws -> String {
        guard let identifier = productIdentifierByPackID[packID] else {
            throw StoreKit2ProductConfigurationError.unsupportedPack(packID)
        }
        return identifier
    }

    func packID(for productIdentifier: String) -> CoinPackID? {
        packIDByProductIdentifier[productIdentifier]
    }
}

struct StoreKit2PlatformProduct: Equatable, Sendable {
    let productIdentifier: String
    let displayName: String
    let displayPrice: String
    let isConsumable: Bool
}

struct StoreKit2PlatformTransaction: Equatable, Sendable {
    let transactionID: UInt64
    let productIdentifier: String
    let appAccountToken: UUID?
    let purchaseDate: Date
    let isRevoked: Bool
}

enum StoreKit2PlatformVerification: Equatable, Sendable {
    /// Only the verified payload is exposed. An unverified payload's fields are
    /// never trusted for product mapping, account binding, delivery, or finish.
    case verified(StoreKit2PlatformTransaction)
    case unverified
}

enum StoreKit2PlatformPurchaseResult: Equatable, Sendable {
    case success(StoreKit2PlatformVerification)
    case pending
    case userCancelled
}

enum StoreKit2PlatformFailure: Error, Equatable, Sendable {
    case productUnavailable
    case transactionUnavailable
}

/// Protocol isolation keeps StoreKit values out of deterministic unit tests.
/// The live implementation is the only type that imports and retains Product
/// and Transaction instances.
protocol StoreKit2PlatformClient: Sendable {
    func products(for identifiers: Set<String>) async throws -> [StoreKit2PlatformProduct]
    func purchase(
        productIdentifier: String,
        appAccountToken: UUID
    ) async throws -> StoreKit2PlatformPurchaseResult
    func unfinishedTransactions() async -> [StoreKit2PlatformVerification]
    func transactionUpdates() async -> AsyncStream<StoreKit2PlatformVerification>
    func finish(transactionID: UInt64) async throws
}

actor LiveStoreKit2PlatformClient: StoreKit2PlatformClient {
    private var productsByIdentifier: [String: Product] = [:]
    private var transactionsByID: [UInt64: Transaction] = [:]

    func products(
        for identifiers: Set<String>
    ) async throws -> [StoreKit2PlatformProduct] {
        let products = try await Product.products(for: identifiers.sorted())
        for product in products {
            productsByIdentifier[product.id] = product
        }
        return products.map(Self.snapshot)
    }

    func purchase(
        productIdentifier: String,
        appAccountToken: UUID
    ) async throws -> StoreKit2PlatformPurchaseResult {
        let product: Product
        if let cached = productsByIdentifier[productIdentifier] {
            product = cached
        } else {
            let loaded = try await Product.products(for: [productIdentifier])
            guard let first = loaded.first, first.id == productIdentifier else {
                throw StoreKit2PlatformFailure.productUnavailable
            }
            productsByIdentifier[first.id] = first
            product = first
        }

        let result = try await product.purchase(
            options: [.appAccountToken(appAccountToken)]
        )
        switch result {
        case let .success(verification):
            return .success(capture(verification))
        case .pending:
            return .pending
        case .userCancelled:
            return .userCancelled
        @unknown default:
            throw StoreKit2PlatformFailure.productUnavailable
        }
    }

    func unfinishedTransactions() async -> [StoreKit2PlatformVerification] {
        var results: [StoreKit2PlatformVerification] = []
        for await verification in Transaction.unfinished {
            results.append(capture(verification))
        }
        return results
    }

    func transactionUpdates() -> AsyncStream<StoreKit2PlatformVerification> {
        AsyncStream { continuation in
            let task = Task { [weak self] in
                for await verification in Transaction.updates {
                    guard !Task.isCancelled, let self else { break }
                    let result = await self.capture(verification)
                    continuation.yield(result)
                }
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    func finish(transactionID: UInt64) async throws {
        guard let transaction = transactionsByID[transactionID] else {
            throw StoreKit2PlatformFailure.transactionUnavailable
        }
        await transaction.finish()
        transactionsByID.removeValue(forKey: transactionID)
    }

    private func capture(
        _ verification: VerificationResult<Transaction>
    ) -> StoreKit2PlatformVerification {
        switch verification {
        case let .verified(transaction):
            transactionsByID[transaction.id] = transaction
            return .verified(Self.snapshot(transaction))
        case .unverified:
            return .unverified
        }
    }

    private static func snapshot(_ product: Product) -> StoreKit2PlatformProduct {
        StoreKit2PlatformProduct(
            productIdentifier: product.id,
            displayName: product.displayName,
            displayPrice: product.displayPrice,
            isConsumable: product.type == .consumable
        )
    }

    private static func snapshot(
        _ transaction: Transaction
    ) -> StoreKit2PlatformTransaction {
        StoreKit2PlatformTransaction(
            transactionID: transaction.id,
            productIdentifier: transaction.productID,
            appAccountToken: transaction.appAccountToken,
            purchaseDate: transaction.purchaseDate,
            isRevoked: transaction.revocationDate != nil
        )
    }
}

enum StoreKit2AdapterFailure: Error, Equatable, Sendable {
    case networkUnavailable
    case storeUnavailable
    case purchasesNotAllowed
    case productNotConfigured(CoinPackID)
    case productUnavailable(CoinPackID)
    case productIsNotConsumable(CoinPackID)
    case invalidProductResponse
}

enum StoreKit2FailureClassifier {
    /// The UI and telemetry receive only this bounded classification. Provider
    /// error text, account tokens, and transaction identifiers never enter it.
    static func classify(
        _ error: any Error,
        packID: CoinPackID
    ) -> StoreKit2AdapterFailure {
        if let failure = error as? StoreKit2AdapterFailure {
            return failure
        }
        if let failure = error as? StoreKit2ProductConfigurationError,
           case let .unsupportedPack(unsupportedPackID) = failure {
            return .productNotConfigured(unsupportedPackID)
        }
        if let failure = error as? StoreKit2PlatformFailure {
            switch failure {
            case .productUnavailable:
                return .productUnavailable(packID)
            case .transactionUnavailable:
                return .storeUnavailable
            }
        }
        if let error = error as? StoreKitError {
            switch error {
            case .networkError:
                return .networkUnavailable
            case .notAvailableInStorefront:
                return .productUnavailable(packID)
            case .notEntitled:
                return .purchasesNotAllowed
            case .userCancelled, .systemError, .unknown, .unsupported:
                return .storeUnavailable
            @unknown default:
                return .storeUnavailable
            }
        }
        if let error = error as? Product.PurchaseError {
            switch error {
            case .productUnavailable:
                return .productUnavailable(packID)
            case .purchaseNotAllowed:
                return .purchasesNotAllowed
            default:
                return .storeUnavailable
            }
        }

        let descriptor = error as NSError
        if descriptor.domain == NSURLErrorDomain {
            return .networkUnavailable
        }
        if descriptor.domain == SKErrorDomain {
            switch descriptor.code {
            case SKError.Code.cloudServiceNetworkConnectionFailed.rawValue:
                return .networkUnavailable
            case SKError.Code.paymentNotAllowed.rawValue:
                return .purchasesNotAllowed
            case SKError.Code.storeProductNotAvailable.rawValue:
                return .productUnavailable(packID)
            default:
                return .storeUnavailable
            }
        }
        return .storeUnavailable
    }
}

struct StoreKit2DurableDeliveryRequest: Equatable, Sendable {
    let session: StoreActiveSession
    let transaction: StoreTransactionEnvelope
    let pack: CoinPackDescriptor
    let ledgerEntry: CoinLedgerEntry
}

enum StoreKit2DurableDeliveryStatus: Equatable, Sendable {
    case committed
    case alreadyCommitted
}

struct StoreKit2DurableDeliveryAcknowledgement: Equatable, Sendable {
    let session: StoreActiveSession
    let transactionID: UInt64
    let ledgerEntryID: LedgerEntryID
    let status: StoreKit2DurableDeliveryStatus
}

/// App composition injects a callback that first commits the credit to private
/// CloudKit and the account-scoped repository. A retry must return
/// `alreadyCommitted` for the same deterministic ledger entry.
protocol StoreKit2DurableCreditDelivering: Sendable {
    func deliver(
        _ request: StoreKit2DurableDeliveryRequest
    ) async throws -> StoreKit2DurableDeliveryAcknowledgement
}

enum StoreKit2TransactionRejection: Equatable, Sendable {
    case verificationFailed
    case unknownProduct
    case missingAppAccountToken
    case appAccountTokenMismatch
    case revokedTransaction
    case invalidTransactionDate
    case invalidDurableAcknowledgement
}

enum StoreKit2TransactionDeferral: Equatable, Sendable {
    case durableDeliveryUnavailable
    case finishUnavailable
}

enum StoreKit2TransactionProcessingResult: Equatable, Sendable {
    case deliveredAndFinished(
        transactionID: UInt64,
        ledgerEntryID: LedgerEntryID,
        deliveryStatus: StoreKit2DurableDeliveryStatus
    )
    case rejected(StoreKit2TransactionRejection)
    case deferred(transactionID: UInt64, reason: StoreKit2TransactionDeferral)
    case ignoredAlreadyFinished(transactionID: UInt64)
    case ignoredDuplicateInFlight(transactionID: UInt64)
}

enum StoreKit2CoinPurchaseResult: Equatable, Sendable {
    case processed(StoreKit2TransactionProcessingResult)
    case pending
    case userCancelled
}

/// StoreKit 2's raw `finish(transactionID:)` seam cannot prove durable credit
/// delivery by itself. This production adapter owns the only finish path and
/// requires a bound, matching durable acknowledgement before invoking it.
actor StoreKit2CoinTransactionAdapter {
    private let configuration: StoreKit2ProductConfiguration
    private let platformClient: any StoreKit2PlatformClient
    private let durableDelivery: any StoreKit2DurableCreditDelivering
    private var inFlightTransactionIDs: Set<UInt64> = []
    private var finishedTransactionIDs: Set<UInt64> = []

    init(
        configuration: StoreKit2ProductConfiguration,
        platformClient: any StoreKit2PlatformClient,
        durableDelivery: any StoreKit2DurableCreditDelivering
    ) {
        self.configuration = configuration
        self.platformClient = platformClient
        self.durableDelivery = durableDelivery
    }

    func products() async throws -> [StoreProduct] {
        try await validatedProducts(for: configuration.orderedLaunchPackIDs)
    }

    func purchase(
        _ packID: CoinPackID,
        session: StoreActiveSession
    ) async throws -> StoreKit2CoinPurchaseResult {
        _ = try await validatedProducts(for: [packID])

        let productIdentifier: String
        do {
            productIdentifier = try configuration.productIdentifier(for: packID)
        } catch {
            throw StoreKit2FailureClassifier.classify(error, packID: packID)
        }

        let result: StoreKit2PlatformPurchaseResult
        do {
            result = try await platformClient.purchase(
                productIdentifier: productIdentifier,
                appAccountToken: session.binding.appAccountToken
            )
        } catch {
            if case StoreKitError.userCancelled = error {
                return .userCancelled
            }
            throw StoreKit2FailureClassifier.classify(error, packID: packID)
        }

        switch result {
        case let .success(verification):
            return .processed(await process(verification, session: session))
        case .pending:
            return .pending
        case .userCancelled:
            return .userCancelled
        }
    }

    func recoverUnfinishedTransactions(
        session: StoreActiveSession
    ) async -> [StoreKit2TransactionProcessingResult] {
        let unfinished = await platformClient.unfinishedTransactions()
        var results: [StoreKit2TransactionProcessingResult] = []
        results.reserveCapacity(unfinished.count)
        for verification in unfinished {
            results.append(await process(verification, session: session))
        }
        return results
    }

    func transactionUpdates(
        session: StoreActiveSession
    ) async -> AsyncStream<StoreKit2TransactionProcessingResult> {
        let upstream = await platformClient.transactionUpdates()
        return AsyncStream { continuation in
            let task = Task { [weak self] in
                for await verification in upstream {
                    guard !Task.isCancelled, let self else { break }
                    let result = await self.process(verification, session: session)
                    continuation.yield(result)
                }
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    private func validatedProducts(
        for packIDs: [CoinPackID]
    ) async throws -> [StoreProduct] {
        let uniquePackIDs = packIDs.reduce(into: [CoinPackID]()) { ordered, packID in
            if !ordered.contains(packID) {
                ordered.append(packID)
            }
        }
        var identifierByPackID: [CoinPackID: String] = [:]
        for packID in uniquePackIDs {
            do {
                identifierByPackID[packID] = try configuration.productIdentifier(
                    for: packID
                )
            } catch {
                throw StoreKit2FailureClassifier.classify(error, packID: packID)
            }
        }

        let loaded: [StoreKit2PlatformProduct]
        do {
            loaded = try await platformClient.products(
                for: Set(identifierByPackID.values)
            )
        } catch {
            let packID = uniquePackIDs.first ?? EconomyConfiguration.coinPacks[0].id
            throw StoreKit2FailureClassifier.classify(error, packID: packID)
        }

        guard Set(loaded.map(\.productIdentifier)).count == loaded.count else {
            throw StoreKit2AdapterFailure.invalidProductResponse
        }
        let loadedByIdentifier = Dictionary(
            uniqueKeysWithValues: loaded.map { ($0.productIdentifier, $0) }
        )
        guard Set(loadedByIdentifier.keys) == Set(identifierByPackID.values) else {
            for packID in uniquePackIDs {
                if let identifier = identifierByPackID[packID],
                   loadedByIdentifier[identifier] == nil {
                    throw StoreKit2AdapterFailure.productUnavailable(packID)
                }
            }
            throw StoreKit2AdapterFailure.invalidProductResponse
        }

        return try uniquePackIDs.map { packID in
            guard let descriptor = EconomyConfiguration.coinPacks.first(
                where: { $0.id == packID }
            ),
            let identifier = identifierByPackID[packID],
            let product = loadedByIdentifier[identifier] else {
                throw StoreKit2AdapterFailure.productNotConfigured(packID)
            }
            guard product.isConsumable else {
                throw StoreKit2AdapterFailure.productIsNotConsumable(packID)
            }
            return StoreProduct(
                packID: packID,
                displayName: product.displayName,
                displayPrice: product.displayPrice,
                coins: descriptor.coins
            )
        }
    }

    private func process(
        _ verification: StoreKit2PlatformVerification,
        session: StoreActiveSession
    ) async -> StoreKit2TransactionProcessingResult {
        guard case let .verified(transaction) = verification else {
            return .rejected(.verificationFailed)
        }
        guard let packID = configuration.packID(
            for: transaction.productIdentifier
        ),
        let pack = EconomyConfiguration.coinPacks.first(
            where: { $0.id == packID }
        ) else {
            return .rejected(.unknownProduct)
        }
        guard let appAccountToken = transaction.appAccountToken else {
            return .rejected(.missingAppAccountToken)
        }
        guard appAccountToken == session.binding.appAccountToken else {
            return .rejected(.appAccountTokenMismatch)
        }
        guard !transaction.isRevoked else {
            return .rejected(.revokedTransaction)
        }
        guard transaction.purchaseDate.timeIntervalSince1970.isFinite else {
            return .rejected(.invalidTransactionDate)
        }

        if finishedTransactionIDs.contains(transaction.transactionID) {
            return .ignoredAlreadyFinished(transactionID: transaction.transactionID)
        }
        guard inFlightTransactionIDs.insert(transaction.transactionID).inserted else {
            return .ignoredDuplicateInFlight(transactionID: transaction.transactionID)
        }
        defer {
            inFlightTransactionIDs.remove(transaction.transactionID)
        }

        let envelope = StoreTransactionEnvelope(
            transactionID: transaction.transactionID,
            packID: packID,
            appAccountToken: appAccountToken,
            verification: .verified
        )
        let ledgerEntry = CoinLedgerEntry(
            id: CoinLedgerID.storeKit(transactionID: transaction.transactionID),
            delta: pack.coins,
            reason: .storeKit(
                transactionID: transaction.transactionID,
                packID: packID
            ),
            createdAt: transaction.purchaseDate
        )
        let request = StoreKit2DurableDeliveryRequest(
            session: session,
            transaction: envelope,
            pack: pack,
            ledgerEntry: ledgerEntry
        )

        let acknowledgement: StoreKit2DurableDeliveryAcknowledgement
        do {
            acknowledgement = try await durableDelivery.deliver(request)
        } catch {
            return .deferred(
                transactionID: transaction.transactionID,
                reason: .durableDeliveryUnavailable
            )
        }
        guard acknowledgement.session == session,
              acknowledgement.transactionID == transaction.transactionID,
              acknowledgement.ledgerEntryID == ledgerEntry.id else {
            return .rejected(.invalidDurableAcknowledgement)
        }

        do {
            try await platformClient.finish(transactionID: transaction.transactionID)
        } catch {
            return .deferred(
                transactionID: transaction.transactionID,
                reason: .finishUnavailable
            )
        }
        finishedTransactionIDs.insert(transaction.transactionID)
        return .deliveredAndFinished(
            transactionID: transaction.transactionID,
            ledgerEntryID: ledgerEntry.id,
            deliveryStatus: acknowledgement.status
        )
    }
}

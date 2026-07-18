import XCTest

@testable import PocketVector

@MainActor
final class StoreKit2TransactionAdapterTests: XCTestCase {
    func testConfigurationRequiresExactlyFourUniqueInjectedProductIdentifiers() throws {
        let identifiers = testProductIdentifiers()
        let configuration = try StoreKit2ProductConfiguration(
            productIdentifiers: identifiers
        )

        XCTAssertEqual(
            configuration.orderedLaunchPackIDs,
            EconomyConfiguration.coinPacks.map(\.id)
        )
        XCTAssertEqual(configuration.allProductIdentifiers, Set(identifiers.values))
        for (packID, productIdentifier) in identifiers {
            XCTAssertEqual(
                try configuration.productIdentifier(for: packID),
                productIdentifier
            )
            XCTAssertEqual(
                configuration.packID(for: productIdentifier),
                packID
            )
        }

        var missing = identifiers
        missing.removeValue(forKey: EconomyConfiguration.coinPacks[0].id)
        XCTAssertThrowsError(
            try StoreKit2ProductConfiguration(productIdentifiers: missing)
        ) { error in
            XCTAssertEqual(
                error as? StoreKit2ProductConfigurationError,
                .invalidLaunchPackSet
            )
        }

        let duplicate = Dictionary(
            uniqueKeysWithValues: EconomyConfiguration.coinPacks.map {
                ($0.id, "test.coin.duplicate")
            }
        )
        XCTAssertThrowsError(
            try StoreKit2ProductConfiguration(productIdentifiers: duplicate)
        ) { error in
            XCTAssertEqual(
                error as? StoreKit2ProductConfigurationError,
                .duplicateProductIdentifier
            )
        }
    }

    func testProductsUseLocalizedStoreDisplayDataAndControlledCoinAmounts() async throws {
        let fixture = try makeFixture()

        let products = try await fixture.adapter.products()

        XCTAssertEqual(products.map(\.packID), EconomyConfiguration.coinPacks.map(\.id))
        XCTAssertEqual(products.map(\.coins), EconomyConfiguration.coinPacks.map(\.coins))
        XCTAssertEqual(
            products.map(\.displayName),
            EconomyConfiguration.coinPacks.map { "Localized \($0.displayName)" }
        )
        XCTAssertEqual(
            products.map(\.displayPrice),
            ["Localized 1", "Localized 2", "Localized 3", "Localized 4"]
        )
    }

    func testProductCoverageRejectsMissingAndNonConsumableProducts() async throws {
        let identifiers = testProductIdentifiers()
        let configuration = try StoreKit2ProductConfiguration(
            productIdentifiers: identifiers
        )
        let missingPack = EconomyConfiguration.coinPacks[2].id
        let missingProductID = try configuration.productIdentifier(for: missingPack)
        let products = try platformProducts(configuration: configuration)
            .filter { $0.productIdentifier != missingProductID }
        let platform = DeterministicStoreKit2PlatformClient(products: products)
        let delivery = DeterministicStoreKit2DurableDelivery()
        let adapter = StoreKit2CoinTransactionAdapter(
            configuration: configuration,
            platformClient: platform,
            durableDelivery: delivery
        )

        do {
            _ = try await adapter.products()
            XCTFail("Missing StoreKit products must fail the catalog load")
        } catch {
            XCTAssertEqual(
                error as? StoreKit2AdapterFailure,
                .productUnavailable(missingPack)
            )
        }

        let nonConsumablePack = EconomyConfiguration.coinPacks[1].id
        let nonConsumableProductID = try configuration.productIdentifier(
            for: nonConsumablePack
        )
        let wrongTypeProducts = try platformProducts(configuration: configuration).map {
            product in
            StoreKit2PlatformProduct(
                productIdentifier: product.productIdentifier,
                displayName: product.displayName,
                displayPrice: product.displayPrice,
                isConsumable: product.productIdentifier != nonConsumableProductID
            )
        }
        let wrongTypePlatform = DeterministicStoreKit2PlatformClient(
            products: wrongTypeProducts
        )
        let wrongTypeAdapter = StoreKit2CoinTransactionAdapter(
            configuration: configuration,
            platformClient: wrongTypePlatform,
            durableDelivery: delivery
        )
        do {
            _ = try await wrongTypeAdapter.products()
            XCTFail("Every launch coin pack must be a consumable")
        } catch {
            XCTAssertEqual(
                error as? StoreKit2AdapterFailure,
                .productIsNotConsumable(nonConsumablePack)
            )
        }
    }

    func testUnverifiedPurchaseNeverDeliversOrFinishes() async throws {
        let fixture = try makeFixture()
        let packID = EconomyConfiguration.coinPacks[0].id
        await fixture.platform.setPurchaseResult(.success(.unverified))

        let result = try await purchaseOnline(packID, fixture: fixture)

        XCTAssertEqual(result, .processed(.rejected(.verificationFailed)))
        let deliveryCount = await fixture.delivery.requestCount()
        let finishedIDs = await fixture.platform.finishedTransactionIDs()
        XCTAssertEqual(deliveryCount, 0)
        XCTAssertEqual(finishedIDs, [])
    }

    func testAccountTokenMismatchNeverDeliversOrFinishes() async throws {
        let fixture = try makeFixture()
        let packID = EconomyConfiguration.coinPacks[0].id
        let transaction = try platformTransaction(
            id: 22,
            packID: packID,
            configuration: fixture.configuration,
            appAccountToken: uuid(999)
        )
        await fixture.platform.setPurchaseResult(.success(.verified(transaction)))

        let result = try await purchaseOnline(packID, fixture: fixture)

        XCTAssertEqual(result, .processed(.rejected(.appAccountTokenMismatch)))
        let deliveryCount = await fixture.delivery.requestCount()
        let finishedIDs = await fixture.platform.finishedTransactionIDs()
        XCTAssertEqual(deliveryCount, 0)
        XCTAssertEqual(finishedIDs, [])
    }

    func testFinishOccursOnlyAfterMatchingDurableCommitAcknowledgement() async throws {
        let events = StoreKit2TestEventRecorder()
        let fixture = try makeFixture(events: events)
        let packID = EconomyConfiguration.coinPacks[1].id
        let transaction = try platformTransaction(
            id: 42,
            packID: packID,
            configuration: fixture.configuration,
            appAccountToken: fixture.session.binding.appAccountToken
        )
        await fixture.platform.setPurchaseResult(.success(.verified(transaction)))

        let result = try await purchaseOnline(packID, fixture: fixture)

        XCTAssertEqual(
            result,
            .processed(
                .deliveredAndFinished(
                    transactionID: 42,
                    packID: packID,
                    ledgerEntryID: CoinLedgerID.storeKit(transactionID: 42),
                    deliveryStatus: .committed
                )
            )
        )
        let purchaseRequests = await fixture.platform.purchaseRequestsSnapshot()
        XCTAssertEqual(
            purchaseRequests,
            [
                StoreKit2TestPurchaseRequest(
                    productIdentifier: try fixture.configuration.productIdentifier(
                        for: packID
                    ),
                    appAccountToken: fixture.session.binding.appAccountToken
                ),
            ]
        )
        let orderedEvents = await events.snapshot()
        XCTAssertEqual(orderedEvents, ["products", "purchase", "deliver", "finish"])

        await fixture.delivery.setReturnsInvalidAcknowledgement(true)
        let nextTransaction = try platformTransaction(
            id: 43,
            packID: packID,
            configuration: fixture.configuration,
            appAccountToken: fixture.session.binding.appAccountToken
        )
        await fixture.platform.setPurchaseResult(.success(.verified(nextTransaction)))
        let invalidResult = try await purchaseOnline(packID, fixture: fixture)
        XCTAssertEqual(
            invalidResult,
            .processed(.rejected(.invalidDurableAcknowledgement))
        )
        let finishedIDs = await fixture.platform.finishedTransactionIDs()
        XCTAssertEqual(finishedIDs, [42])
    }

    func testDurableDeliveryClassifiesConnectivitySeparatelyFromIntegrityFailure() async throws {
        let fixture = try makeFixture()
        let packID = EconomyConfiguration.coinPacks[0].id
        let connectivityTransaction = try platformTransaction(
            id: 70,
            packID: packID,
            configuration: fixture.configuration,
            appAccountToken: fixture.session.binding.appAccountToken
        )
        await fixture.delivery.setFailure(.connectivity)
        await fixture.platform.setPurchaseResult(.success(.verified(connectivityTransaction)))

        let connectivityResult = try await purchaseOnline(packID, fixture: fixture)
        XCTAssertEqual(
            connectivityResult,
            .processed(
                .deferred(
                    transactionID: 70,
                    reason: .durableDeliveryConnectivityUnavailable
                )
            )
        )

        let integrityTransaction = try platformTransaction(
            id: 71,
            packID: packID,
            configuration: fixture.configuration,
            appAccountToken: fixture.session.binding.appAccountToken
        )
        await fixture.delivery.setFailure(.integrity)
        await fixture.platform.setPurchaseResult(.success(.verified(integrityTransaction)))

        let integrityResult = try await purchaseOnline(packID, fixture: fixture)
        let finishedTransactionIDs = await fixture.platform.finishedTransactionIDs()
        XCTAssertEqual(
            integrityResult,
            .processed(
                .deferred(
                    transactionID: 71,
                    reason: .durableDeliveryUnavailable
                )
            )
        )
        XCTAssertEqual(finishedTransactionIDs, [])
    }

    func testOnlinePurchaseAuthorizesAfterProductWorkImmediatelyBeforePlatformRequest() async throws {
        let events = StoreKit2TestEventRecorder()
        let fixture = try makeFixture(events: events)
        let context = try DurableEconomySessionContext(
            cloudAccountID: CloudAccountID("online-purchase-cloud"),
            accountBinding: fixture.session.binding.account,
            profileSession: ProfileSessionToken(
                accountIdentity: PlayerAccountIdentity("online-purchase-player"),
                nonce: fixture.session.nonce,
                profileID: fixture.session.binding.account.profileID
            ),
            storeSession: fixture.session
        )
        let authorizer = StoreKit2TestOnlineAuthorizer(events: events)

        let result = try await fixture.adapter.purchaseOnline(
            EconomyConfiguration.coinPacks[0].id,
            session: fixture.session,
            expected: context,
            authorizer: authorizer
        )
        let orderedEvents = await events.snapshot()

        XCTAssertEqual(result, .userCancelled)
        XCTAssertEqual(orderedEvents, ["products", "authorize", "purchase"])
    }

    func testCancellationDuringPlatformProductResolutionNeverOpensSheet() async throws {
        let fixture = try makeFixture()
        let context = try commerceContext(fixture: fixture)
        let resolutionGate = StoreKit2TestGate()
        await fixture.platform.setNextPurchaseResolutionGate(resolutionGate)
        let authorizer = StoreKit2ControllableOnlineAuthorizer()
        let packID = EconomyConfiguration.coinPacks[0].id

        let request = Task {
            try await fixture.adapter.purchaseOnline(
                packID,
                session: fixture.session,
                expected: context,
                authorizer: authorizer
            )
        }
        for _ in 0 ..< 10_000 {
            if await fixture.platform.purchaseResolutionWaitCount() == 1 { break }
            await Task.yield()
        }
        let resolutionWaitCount = await fixture.platform.purchaseResolutionWaitCount()
        XCTAssertEqual(resolutionWaitCount, 1)

        request.cancel()
        await resolutionGate.open()
        do {
            _ = try await request.value
            XCTFail("Cancellation during product resolution must stop presentation")
        } catch is CancellationError {
            // Expected.
        }
        let purchaseRequests = await fixture.platform.purchaseRequestsSnapshot()
        let authorizationRequests = await authorizer.requestCount()
        XCTAssertEqual(purchaseRequests, [])
        XCTAssertEqual(authorizationRequests, 0)
    }

    func testAccountLossDuringPlatformProductResolutionNeverOpensSheet() async throws {
        let fixture = try makeFixture()
        let context = try commerceContext(fixture: fixture)
        let resolutionGate = StoreKit2TestGate()
        await fixture.platform.setNextPurchaseResolutionGate(resolutionGate)
        let authorizer = StoreKit2ControllableOnlineAuthorizer()
        let packID = EconomyConfiguration.coinPacks[0].id

        let request = Task {
            try await fixture.adapter.purchaseOnline(
                packID,
                session: fixture.session,
                expected: context,
                authorizer: authorizer
            )
        }
        for _ in 0 ..< 10_000 {
            if await fixture.platform.purchaseResolutionWaitCount() == 1 { break }
            await Task.yield()
        }
        let resolutionWaitCount = await fixture.platform.purchaseResolutionWaitCount()
        XCTAssertEqual(resolutionWaitCount, 1)

        await authorizer.failWithAccountLoss()
        await resolutionGate.open()
        do {
            _ = try await request.value
            XCTFail("A lost account must stop presentation after product resolution")
        } catch {
            XCTAssertEqual(
                error as? DurableEconomyCoordinatorError,
                .cloudAccountUnavailable
            )
        }
        let purchaseRequests = await fixture.platform.purchaseRequestsSnapshot()
        let authorizationRequests = await authorizer.requestCount()
        XCTAssertEqual(purchaseRequests, [])
        XCTAssertEqual(authorizationRequests, 1)
    }

    func testDuplicateUnfinishedTransactionDeliversAndFinishesOncePerProcess() async throws {
        let fixture = try makeFixture()
        let transaction = try platformTransaction(
            id: 51,
            packID: EconomyConfiguration.coinPacks[0].id,
            configuration: fixture.configuration,
            appAccountToken: fixture.session.binding.appAccountToken
        )
        await fixture.platform.setUnfinished([
            .verified(transaction),
            .verified(transaction),
        ])

        let results = await fixture.adapter.recoverUnfinishedTransactions(
            session: fixture.session
        )

        XCTAssertEqual(
            results,
            [
                .deliveredAndFinished(
                    transactionID: 51,
                    packID: EconomyConfiguration.coinPacks[0].id,
                    ledgerEntryID: CoinLedgerID.storeKit(transactionID: 51),
                    deliveryStatus: .committed
                ),
                .ignoredAlreadyFinished(transactionID: 51),
            ]
        )
        let deliveryCount = await fixture.delivery.requestCount()
        let finishedIDs = await fixture.platform.finishedTransactionIDs()
        XCTAssertEqual(deliveryCount, 1)
        XCTAssertEqual(finishedIDs, [51])
    }

    func testRelaunchRecoveryFinishesAfterAlreadyCommittedDelivery() async throws {
        let fixture = try makeFixture()
        let transaction = try platformTransaction(
            id: 61,
            packID: EconomyConfiguration.coinPacks[3].id,
            configuration: fixture.configuration,
            appAccountToken: fixture.session.binding.appAccountToken
        )
        await fixture.platform.setUnfinished([.verified(transaction)])
        await fixture.platform.setFinishFailureEnabled(true)

        let firstResults = await fixture.adapter.recoverUnfinishedTransactions(
            session: fixture.session
        )
        XCTAssertEqual(
            firstResults,
            [.deferred(transactionID: 61, reason: .finishUnavailable)]
        )
        let firstDeliveryCount = await fixture.delivery.requestCount()
        let firstCommittedEntryCount = await fixture.delivery.committedLedgerEntryCount()
        XCTAssertEqual(firstDeliveryCount, 1)
        XCTAssertEqual(firstCommittedEntryCount, 1)

        await fixture.platform.setFinishFailureEnabled(false)
        let relaunchedAdapter = StoreKit2CoinTransactionAdapter(
            configuration: fixture.configuration,
            platformClient: fixture.platform,
            durableDelivery: fixture.delivery
        )
        let recoveryResults = await relaunchedAdapter.recoverUnfinishedTransactions(
            session: fixture.session
        )

        XCTAssertEqual(
            recoveryResults,
            [
                .deliveredAndFinished(
                    transactionID: 61,
                    packID: EconomyConfiguration.coinPacks[3].id,
                    ledgerEntryID: CoinLedgerID.storeKit(transactionID: 61),
                    deliveryStatus: .alreadyCommitted
                ),
            ]
        )
        let recoveryDeliveryCount = await fixture.delivery.requestCount()
        let recoveryCommittedEntryCount = await fixture.delivery.committedLedgerEntryCount()
        let recoveryFinishedIDs = await fixture.platform.finishedTransactionIDs()
        XCTAssertEqual(recoveryDeliveryCount, 2)
        XCTAssertEqual(recoveryCommittedEntryCount, 1)
        XCTAssertEqual(recoveryFinishedIDs, [61])
    }

    func testPurchaseReportsCancelledPendingAndUnavailableWithoutRawErrors() async throws {
        let fixture = try makeFixture()
        let packID = EconomyConfiguration.coinPacks[0].id

        await fixture.platform.setPurchaseResult(.userCancelled)
        let cancelled = try await purchaseOnline(packID, fixture: fixture)
        XCTAssertEqual(cancelled, .userCancelled)

        await fixture.platform.setPurchaseResult(.pending)
        let pending = try await purchaseOnline(packID, fixture: fixture)
        XCTAssertEqual(pending, .pending)

        await fixture.platform.setPurchaseFailure(.productUnavailable)
        do {
            _ = try await purchaseOnline(packID, fixture: fixture)
            XCTFail("Unavailable products must remain retryable and uncredited")
        } catch {
            XCTAssertEqual(
                error as? StoreKit2AdapterFailure,
                .productUnavailable(packID)
            )
        }
        let deliveryCount = await fixture.delivery.requestCount()
        let finishedIDs = await fixture.platform.finishedTransactionIDs()
        XCTAssertEqual(deliveryCount, 0)
        XCTAssertEqual(finishedIDs, [])
    }

    func testVerifiedTransactionUpdatesUseTheSameDurableFinishGate() async throws {
        let fixture = try makeFixture()
        let transaction = try platformTransaction(
            id: 71,
            packID: EconomyConfiguration.coinPacks[2].id,
            configuration: fixture.configuration,
            appAccountToken: fixture.session.binding.appAccountToken
        )
        let listener = await fixture.adapter.transactionUpdates(session: fixture.session)
        var iterator = listener.updates.makeAsyncIterator()

        await fixture.platform.emitUpdate(.verified(transaction))
        let result = await iterator.next()
        await fixture.platform.finishUpdates()
        await listener.cancelAndWait()

        XCTAssertEqual(
            result,
            .deliveredAndFinished(
                transactionID: 71,
                packID: EconomyConfiguration.coinPacks[2].id,
                ledgerEntryID: CoinLedgerID.storeKit(transactionID: 71),
                deliveryStatus: .committed
            )
        )
        let finishedIDs = await fixture.platform.finishedTransactionIDs()
        XCTAssertEqual(finishedIDs, [71])
    }

    func testOwnedListenerCancellationAwaitsPlatformProducerTermination() async throws {
        let fixture = try makeFixture()
        let stopGate = StoreKit2TestGate()
        let cancellationFinished = StoreKit2TestFlag()
        await fixture.platform.setNextListenerStopGate(stopGate)
        let listener = await fixture.adapter.transactionUpdates(session: fixture.session)

        let cancellation = Task {
            await listener.cancelAndWait()
            await cancellationFinished.setTrue()
        }
        for _ in 0 ..< 10_000 {
            if await fixture.platform.listenerStoppingCount() == 1 { break }
            await Task.yield()
        }
        let stoppingCount = await fixture.platform.listenerStoppingCount()
        let finishedBeforeGate = await cancellationFinished.value()
        XCTAssertEqual(stoppingCount, 1)
        XCTAssertFalse(finishedBeforeGate)

        await stopGate.open()
        await cancellation.value
        let stoppedCount = await fixture.platform.listenerStoppedCount()
        let finishedAfterGate = await cancellationFinished.value()
        XCTAssertEqual(stoppedCount, 1)
        XCTAssertTrue(finishedAfterGate)
    }

    private func makeFixture(
        events: StoreKit2TestEventRecorder? = nil
    ) throws -> StoreKit2TestFixture {
        let configuration = try StoreKit2ProductConfiguration(
            productIdentifiers: testProductIdentifiers()
        )
        let platform = DeterministicStoreKit2PlatformClient(
            products: try platformProducts(configuration: configuration),
            events: events
        )
        let delivery = DeterministicStoreKit2DurableDelivery(events: events)
        let adapter = StoreKit2CoinTransactionAdapter(
            configuration: configuration,
            platformClient: platform,
            durableDelivery: delivery
        )
        return StoreKit2TestFixture(
            configuration: configuration,
            session: storeSession(),
            platform: platform,
            delivery: delivery,
            adapter: adapter
        )
    }

    private func purchaseOnline(
        _ packID: CoinPackID,
        fixture: StoreKit2TestFixture
    ) async throws -> StoreKit2CoinPurchaseResult {
        let context = try commerceContext(fixture: fixture)
        return try await fixture.adapter.purchaseOnline(
            packID,
            session: fixture.session,
            expected: context,
            authorizer: StoreKit2AlwaysOnlineAuthorizer()
        )
    }

    private func commerceContext(
        fixture: StoreKit2TestFixture
    ) throws -> DurableEconomySessionContext {
        try DurableEconomySessionContext(
            cloudAccountID: CloudAccountID("adapter-test-cloud"),
            accountBinding: fixture.session.binding.account,
            profileSession: ProfileSessionToken(
                accountIdentity: PlayerAccountIdentity("adapter-test-player"),
                nonce: fixture.session.nonce,
                profileID: fixture.session.binding.account.profileID
            ),
            storeSession: fixture.session
        )
    }

    private func testProductIdentifiers() -> [CoinPackID: String] {
        Dictionary(
            uniqueKeysWithValues: EconomyConfiguration.coinPacks.map {
                ($0.id, "test.coin.\($0.id.rawValue)")
            }
        )
    }

    private func platformProducts(
        configuration: StoreKit2ProductConfiguration
    ) throws -> [StoreKit2PlatformProduct] {
        try EconomyConfiguration.coinPacks.enumerated().map { index, pack in
            StoreKit2PlatformProduct(
                productIdentifier: try configuration.productIdentifier(for: pack.id),
                displayName: "Localized \(pack.displayName)",
                displayPrice: "Localized \(index + 1)",
                isConsumable: true
            )
        }
    }

    private func platformTransaction(
        id: UInt64,
        packID: CoinPackID,
        configuration: StoreKit2ProductConfiguration,
        appAccountToken: UUID?
    ) throws -> StoreKit2PlatformTransaction {
        StoreKit2PlatformTransaction(
            transactionID: id,
            productIdentifier: try configuration.productIdentifier(for: packID),
            appAccountToken: appAccountToken,
            purchaseDate: Date(timeIntervalSince1970: 1_750_000_000 + Double(id)),
            isRevoked: false
        )
    }

    private func storeSession() -> StoreActiveSession {
        StoreActiveSession(
            binding: StoreAccountBinding(
                account: DurableAccountBinding(
                    accountKey: ServiceAccountKey("test-account"),
                    profileID: uuid(100)
                ),
                appAccountToken: uuid(200)
            ),
            nonce: uuid(300)
        )
    }

    private func uuid(_ value: Int) -> UUID {
        UUID(
            uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", value))"
        )!
    }
}

private struct StoreKit2TestFixture {
    let configuration: StoreKit2ProductConfiguration
    let session: StoreActiveSession
    let platform: DeterministicStoreKit2PlatformClient
    let delivery: DeterministicStoreKit2DurableDelivery
    let adapter: StoreKit2CoinTransactionAdapter
}

private actor StoreKit2TestEventRecorder {
    private var events: [String] = []

    func record(_ event: String) {
        events.append(event)
    }

    func snapshot() -> [String] {
        events
    }
}

private actor StoreKit2TestOnlineAuthorizer: OnlineCommerceTransactionAuthorizing {
    private let events: StoreKit2TestEventRecorder

    init(events: StoreKit2TestEventRecorder) {
        self.events = events
    }

    func revalidate(expected _: DurableEconomySessionContext) async throws {
        await events.record("authorize")
    }
}

private struct StoreKit2AlwaysOnlineAuthorizer:
    OnlineCommerceTransactionAuthorizing {
    func revalidate(expected _: DurableEconomySessionContext) async throws {}
}

private actor StoreKit2ControllableOnlineAuthorizer:
    OnlineCommerceTransactionAuthorizing {
    private var accountIsAvailable = true
    private var requests = 0

    func revalidate(expected _: DurableEconomySessionContext) async throws {
        requests += 1
        guard accountIsAvailable else {
            throw DurableEconomyCoordinatorError.cloudAccountUnavailable
        }
    }

    func failWithAccountLoss() {
        accountIsAvailable = false
    }

    func requestCount() -> Int {
        requests
    }
}

private actor StoreKit2TestGate {
    private var isOpen = false

    func wait() async {
        while !isOpen {
            await Task.yield()
        }
    }

    func open() {
        isOpen = true
    }
}

private actor StoreKit2TestFlag {
    private var storedValue = false

    func setTrue() {
        storedValue = true
    }

    func value() -> Bool {
        storedValue
    }
}

private struct StoreKit2TestPurchaseRequest: Equatable, Sendable {
    let productIdentifier: String
    let appAccountToken: UUID
}

private actor DeterministicStoreKit2PlatformClient: StoreKit2PlatformClient {
    private var productsByIdentifier: [String: StoreKit2PlatformProduct]
    private var purchaseResult: StoreKit2PlatformPurchaseResult = .userCancelled
    private var purchaseFailure: StoreKit2PlatformFailure?
    private var unfinished: [StoreKit2PlatformVerification] = []
    private var updateContinuations:
        [AsyncStream<StoreKit2PlatformVerification>.Continuation] = []
    private var nextListenerStopGate: StoreKit2TestGate?
    private var stoppingListeners = 0
    private var stoppedListeners = 0
    private var finishedIDs: [UInt64] = []
    private var purchaseRequests: [StoreKit2TestPurchaseRequest] = []
    private var nextPurchaseResolutionGate: StoreKit2TestGate?
    private var purchaseResolutionWaits = 0
    private var finishFailureEnabled = false
    private let events: StoreKit2TestEventRecorder?

    init(
        products: [StoreKit2PlatformProduct],
        events: StoreKit2TestEventRecorder? = nil
    ) {
        productsByIdentifier = Dictionary(
            uniqueKeysWithValues: products.map { ($0.productIdentifier, $0) }
        )
        self.events = events
    }

    func products(
        for identifiers: Set<String>
    ) async throws -> [StoreKit2PlatformProduct] {
        await events?.record("products")
        return identifiers.sorted().compactMap { productsByIdentifier[$0] }
    }

    func purchaseAuthorized(
        productIdentifier: String,
        appAccountToken: UUID,
        finalAuthorization: @escaping @Sendable () async throws -> Void
    ) async throws -> StoreKit2PlatformPurchaseResult {
        let resolutionGate = nextPurchaseResolutionGate
        nextPurchaseResolutionGate = nil
        if let resolutionGate {
            purchaseResolutionWaits += 1
            await resolutionGate.wait()
        }
        try Task.checkCancellation()
        try await finalAuthorization()
        try Task.checkCancellation()
        await events?.record("purchase")
        if let purchaseFailure {
            throw purchaseFailure
        }
        purchaseRequests.append(
            StoreKit2TestPurchaseRequest(
                productIdentifier: productIdentifier,
                appAccountToken: appAccountToken
            )
        )
        return purchaseResult
    }

    func unfinishedTransactions() -> [StoreKit2PlatformVerification] {
        unfinished
    }

    func transactionUpdates() -> StoreKit2OwnedUpdateListener<StoreKit2PlatformVerification> {
        let input = AsyncStream<StoreKit2PlatformVerification>.makeStream()
        let output = AsyncStream<StoreKit2PlatformVerification>.makeStream()
        updateContinuations.append(input.continuation)
        let stopGate = nextListenerStopGate
        nextListenerStopGate = nil
        let task = Task<Void, Never> { [weak self] in
            for await verification in input.stream {
                guard !Task.isCancelled else { break }
                output.continuation.yield(verification)
            }
            await self?.recordListenerStopping()
            await stopGate?.wait()
            output.continuation.finish()
            await self?.recordListenerStopped()
        }
        output.continuation.onTermination = { @Sendable _ in
            task.cancel()
        }
        return StoreKit2OwnedUpdateListener(updates: output.stream) {
            input.continuation.finish()
            task.cancel()
            await task.value
        }
    }

    func finish(transactionID: UInt64) async throws {
        await events?.record("finish")
        if finishFailureEnabled {
            throw StoreKit2PlatformFailure.transactionUnavailable
        }
        finishedIDs.append(transactionID)
        unfinished.removeAll { verification in
            guard case let .verified(transaction) = verification else { return false }
            return transaction.transactionID == transactionID
        }
    }

    func setPurchaseResult(_ result: StoreKit2PlatformPurchaseResult) {
        purchaseResult = result
        purchaseFailure = nil
    }

    func setPurchaseFailure(_ failure: StoreKit2PlatformFailure?) {
        purchaseFailure = failure
    }

    func setNextPurchaseResolutionGate(_ gate: StoreKit2TestGate) {
        nextPurchaseResolutionGate = gate
    }

    func purchaseResolutionWaitCount() -> Int {
        purchaseResolutionWaits
    }

    func setUnfinished(_ transactions: [StoreKit2PlatformVerification]) {
        unfinished = transactions
    }

    func setFinishFailureEnabled(_ isEnabled: Bool) {
        finishFailureEnabled = isEnabled
    }

    func setNextListenerStopGate(_ gate: StoreKit2TestGate) {
        nextListenerStopGate = gate
    }

    func emitUpdate(_ verification: StoreKit2PlatformVerification) {
        for continuation in updateContinuations {
            continuation.yield(verification)
        }
    }

    func finishUpdates() {
        for continuation in updateContinuations {
            continuation.finish()
        }
        updateContinuations.removeAll()
    }

    func finishedTransactionIDs() -> [UInt64] {
        finishedIDs
    }

    func purchaseRequestsSnapshot() -> [StoreKit2TestPurchaseRequest] {
        purchaseRequests
    }

    func listenerStoppingCount() -> Int {
        stoppingListeners
    }

    func listenerStoppedCount() -> Int {
        stoppedListeners
    }

    private func recordListenerStopping() {
        stoppingListeners += 1
    }

    private func recordListenerStopped() {
        stoppedListeners += 1
    }
}

private enum DeterministicStoreKit2DeliveryFailure: Error {
    case unavailable
}

private enum DeterministicStoreKit2DeliveryFailureMode: Sendable {
    case connectivity
    case integrity
}

private actor DeterministicStoreKit2DurableDelivery: StoreKit2DurableCreditDelivering {
    private var requests: [StoreKit2DurableDeliveryRequest] = []
    private var committedLedgerEntryIDs: Set<LedgerEntryID> = []
    private var returnsInvalidAcknowledgement = false
    private var failure: DeterministicStoreKit2DeliveryFailureMode?
    private let events: StoreKit2TestEventRecorder?

    init(events: StoreKit2TestEventRecorder? = nil) {
        self.events = events
    }

    func deliver(
        _ request: StoreKit2DurableDeliveryRequest
    ) async throws -> StoreKit2DurableDeliveryAcknowledgement {
        await events?.record("deliver")
        requests.append(request)
        switch failure {
        case .connectivity:
            throw CloudKitCloudSyncError.networkUnavailable(retryAfterSeconds: nil)
        case .integrity:
            throw DeterministicStoreKit2DeliveryFailure.unavailable
        case nil:
            break
        }
        let insertion = committedLedgerEntryIDs.insert(request.ledgerEntry.id)
        return StoreKit2DurableDeliveryAcknowledgement(
            session: request.session,
            transactionID: returnsInvalidAcknowledgement
                ? request.transaction.transactionID + 1
                : request.transaction.transactionID,
            ledgerEntryID: request.ledgerEntry.id,
            status: insertion.inserted ? .committed : .alreadyCommitted
        )
    }

    func setReturnsInvalidAcknowledgement(_ returnsInvalid: Bool) {
        returnsInvalidAcknowledgement = returnsInvalid
    }

    func setFailure(_ failure: DeterministicStoreKit2DeliveryFailureMode?) {
        self.failure = failure
    }

    func requestCount() -> Int {
        requests.count
    }

    func committedLedgerEntryCount() -> Int {
        committedLedgerEntryIDs.count
    }
}

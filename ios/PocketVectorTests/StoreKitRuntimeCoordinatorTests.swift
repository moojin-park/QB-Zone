import XCTest

@testable import PocketVector

@MainActor
final class StoreKitRuntimeCoordinatorTests: XCTestCase {
    func testInstallsUpdatesBeforeRecoveryAndAcceptsUpdateDuringRecovery() async throws {
        let session = storeSession(1)
        let recoveryGate = StoreKitRuntimeTestGate()
        let adapter = StoreKitRuntimeTestAdapter(products: localizedProducts(prefix: "Launch"))
        await adapter.setNextRecoveryGate(recoveryGate)
        let source = StoreKitRuntimeTestSessionSource(session: session)
        let coordinator = StoreKitRuntimeCoordinator(
            adapter: adapter,
            sessionSource: source
        )

        await assertEqual({ await coordinator.activate() }, .activated)
        await assertEventually {
            await adapter.events().contains(.recovery(session.nonce))
        }
        let events = await adapter.events()
        let installedIndex = try XCTUnwrap(
            events.firstIndex(of: .updatesInstalled(session.nonce))
        )
        let recoveryIndex = try XCTUnwrap(
            events.firstIndex(of: .recovery(session.nonce))
        )
        XCTAssertLessThan(installedIndex, recoveryIndex)

        await adapter.emit(
            .rejected(.verificationFailed),
            for: session
        )
        await assertEventually {
            await coordinator.snapshot().latestOutcome == .processed(
                source: .transactionUpdate,
                outcome: .rejected(.verificationFailed)
            )
        }

        await recoveryGate.open()
        await assertEventually {
            await coordinator.snapshot().phase == .available
        }
        await assertEqual(
            { await coordinator.snapshot().products },
            localizedProducts(prefix: "Launch")
        )
        await coordinator.deactivate()
    }

    func testExactActivationIsIdempotent() async {
        let session = storeSession(2)
        let adapter = StoreKitRuntimeTestAdapter(products: localizedProducts(prefix: "One"))
        let source = StoreKitRuntimeTestSessionSource(session: session)
        let coordinator = StoreKitRuntimeCoordinator(adapter: adapter, sessionSource: source)

        await assertEqual({ await coordinator.activate() }, .activated)
        await assertEventually {
            await coordinator.snapshot().phase == .available
        }
        await assertEqual({ await coordinator.activate() }, .unchanged)
        await assertEqual(
            { await adapter.events().filter { event in
                event == .updatesInstalled(session.nonce)
            }.count },
            1
        )
        await coordinator.deactivate()
    }

    func testAccountSwitchCancelsAndReapsOldProductsBeforeStartingNewSession() async {
        let oldSession = storeSession(3)
        let newSession = storeSession(4)
        let oldProductsGate = StoreKitRuntimeTestGate()
        let adapter = StoreKitRuntimeTestAdapter(products: localizedProducts(prefix: "New"))
        await adapter.enqueueProducts(
            localizedProducts(prefix: "Old"),
            gate: oldProductsGate
        )
        await adapter.enqueueProducts(localizedProducts(prefix: "New"))
        let source = StoreKitRuntimeTestSessionSource(session: oldSession)
        let coordinator = StoreKitRuntimeCoordinator(adapter: adapter, sessionSource: source)

        await assertEqual({ await coordinator.activate() }, .activated)
        await assertEventually {
            await adapter.events().contains(.products(0))
        }

        await source.setSession(newSession)
        let switchTask = Task { await coordinator.activate() }
        await assertEventually {
            await coordinator.snapshot().phase == .starting
        }
        let newListenerStartedBeforeReap = await adapter.events()
            .contains(.updatesInstalled(newSession.nonce))
        XCTAssertFalse(newListenerStartedBeforeReap)

        await oldProductsGate.open()
        let switchResult = await switchTask.value
        XCTAssertEqual(switchResult, .activated)
        await assertEventually {
            let state = await coordinator.snapshot()
            return state.phase == .available
                && state.products == self.localizedProducts(prefix: "New")
        }
        let switchedEvents = await adapter.events()
        let oldProducerStoppedIndex = switchedEvents.firstIndex(
            of: .updatesProducerStopped(oldSession.nonce)
        )
        let newListenerInstalledIndex = switchedEvents.firstIndex(
            of: .updatesInstalled(newSession.nonce)
        )
        XCTAssertNotNil(oldProducerStoppedIndex)
        XCTAssertNotNil(newListenerInstalledIndex)
        if let oldProducerStoppedIndex, let newListenerInstalledIndex {
            XCTAssertLessThan(oldProducerStoppedIndex, newListenerInstalledIndex)
        }

        let beforeStaleUpdate = await coordinator.snapshot()
        await adapter.emit(
            .rejected(.revokedTransaction),
            for: oldSession
        )
        for _ in 0 ..< 100 { await Task.yield() }
        await assertEqual({ await coordinator.snapshot() }, beforeStaleUpdate)
        await coordinator.deactivate()
    }

    func testCancelledAccountSwitchAfterRetirementDoesNotStartSuccessor() async {
        let oldSession = storeSession(13)
        let newSession = storeSession(14)
        let oldProductsGate = StoreKitRuntimeTestGate()
        let adapter = StoreKitRuntimeTestAdapter(products: localizedProducts(prefix: "New"))
        await adapter.enqueueProducts(
            localizedProducts(prefix: "Old"),
            gate: oldProductsGate
        )
        let source = StoreKitRuntimeTestSessionSource(session: oldSession)
        let coordinator = StoreKitRuntimeCoordinator(adapter: adapter, sessionSource: source)

        await assertEqual({ await coordinator.activate() }, .activated)
        await assertEventually {
            await adapter.events().contains(.products(0))
        }

        await source.setSession(newSession)
        let switchTask = Task { await coordinator.activate() }
        await assertEventually {
            await coordinator.snapshot().phase == .starting
        }
        switchTask.cancel()
        await oldProductsGate.open()

        await assertEqual({ await switchTask.value }, .cancelled)
        await assertEqual({ await coordinator.snapshot() }, .inactive)
        await assertEqual(
            { await adapter.events().contains(.updatesInstalled(newSession.nonce)) },
            false
        )
        await coordinator.shutdown()
    }

    func testUnexpectedUpdatesEndDuringRecoveryDominatesStartupUntilRetry() async {
        let session = storeSession(5)
        let recoveryGate = StoreKitRuntimeTestGate()
        let adapter = StoreKitRuntimeTestAdapter(products: localizedProducts(prefix: "Products"))
        await adapter.setNextRecoveryGate(recoveryGate)
        let source = StoreKitRuntimeTestSessionSource(session: session)
        let coordinator = StoreKitRuntimeCoordinator(adapter: adapter, sessionSource: source)

        await assertEqual({ await coordinator.activate() }, .activated)
        await assertEventually {
            await adapter.events().contains(.recovery(session.nonce))
        }
        await adapter.finishUpdates(for: session)
        await assertEventually {
            await coordinator.snapshot().phase == .unavailable(.transactionUpdatesEnded)
        }

        await recoveryGate.open()
        for _ in 0 ..< 100 { await Task.yield() }
        await assertEqual(
            { await coordinator.snapshot().phase },
            .unavailable(.transactionUpdatesEnded)
        )

        await assertEqual({ await coordinator.retry() }, .activated)
        await assertEventually {
            await coordinator.snapshot().phase == .available
        }
        await coordinator.deactivate()
    }

    func testDeferredRecoveryBlocksProductLoadingUntilExplicitRetry() async {
        let session = storeSession(9)
        let adapter = StoreKitRuntimeTestAdapter(products: localizedProducts(prefix: "Products"))
        await adapter.setNextRecoveryResults([
            .deferred(
                transactionID: 9_001,
                reason: .durableDeliveryUnavailable
            ),
        ])
        let source = StoreKitRuntimeTestSessionSource(session: session)
        let coordinator = StoreKitRuntimeCoordinator(adapter: adapter, sessionSource: source)

        await assertEqual({ await coordinator.activate() }, .activated)
        await assertEventually {
            let state = await coordinator.snapshot()
            return state.phase == .unavailable(
                .transactionDeferred(.durableDeliveryUnavailable)
            ) && state.latestOutcome == .processed(
                source: .unfinishedRecovery,
                outcome: .deferred(.durableDeliveryUnavailable)
            )
        }
        await assertEqual(
            { await adapter.events().filter { event in
                if case .products = event { return true }
                return false
            }.count },
            0
        )
        await assertEqual({ await coordinator.activate() }, .unchanged)
        await assertEqual(
            { await coordinator.snapshot().phase },
            .unavailable(.transactionDeferred(.durableDeliveryUnavailable))
        )

        await assertEqual({ await coordinator.retry() }, .activated)
        await assertEventually {
            await coordinator.snapshot().phase == .available
        }
        await coordinator.deactivate()
    }

    func testDeferredLiveUpdateBlocksConcurrentPurchaseCompletionUntilRetry() async {
        let session = storeSession(10)
        let purchaseGate = StoreKitRuntimeTestGate()
        let adapter = StoreKitRuntimeTestAdapter(products: localizedProducts(prefix: "Store"))
        await adapter.enqueuePurchase(.userCancelled, gate: purchaseGate)
        let source = StoreKitRuntimeTestSessionSource(session: session)
        let coordinator = StoreKitRuntimeCoordinator(adapter: adapter, sessionSource: source)
        let packID = EconomyConfiguration.coinPacks[0].id

        await assertEqual({ await coordinator.activate() }, .activated)
        await assertEventually {
            await coordinator.snapshot().phase == .available
        }
        await assertEqual({ await coordinator.purchase(packID) }, .started)
        await assertEventually { await adapter.activePurchaseCount() == 1 }

        await adapter.emit(
            .deferred(
                transactionID: 10_001,
                reason: .durableDeliveryUnavailable
            ),
            for: session
        )
        await assertEventually {
            let state = await coordinator.snapshot()
            return state.phase == .unavailable(
                .transactionDeferred(.durableDeliveryUnavailable)
            ) && state.latestOutcome == .processed(
                source: .transactionUpdate,
                outcome: .deferred(.durableDeliveryUnavailable)
            )
        }
        let blockedState = await coordinator.snapshot()

        await purchaseGate.open()
        await assertEventually { await adapter.activePurchaseCount() == 0 }
        for _ in 0 ..< 100 { await Task.yield() }
        await assertEqual({ await coordinator.snapshot() }, blockedState)
        await assertEqual({ await coordinator.purchase(packID) }, .productUnavailable)

        await assertEqual({ await coordinator.retry() }, .activated)
        await assertEventually {
            await coordinator.snapshot().phase == .available
        }
        await coordinator.deactivate()
    }

    func testCancelledActivationCannotStartGeneration() async {
        let sessionGate = StoreKitRuntimeTestGate()
        let session = storeSession(6)
        let adapter = StoreKitRuntimeTestAdapter(products: localizedProducts(prefix: "Never"))
        let source = StoreKitRuntimeTestSessionSource(
            session: session,
            nextGate: sessionGate
        )
        let coordinator = StoreKitRuntimeCoordinator(adapter: adapter, sessionSource: source)

        let activation = Task { await coordinator.activate() }
        await assertEventually { await source.requestCount() == 1 }
        activation.cancel()
        await sessionGate.open()

        let activationResult = await activation.value
        XCTAssertEqual(activationResult, .cancelled)
        await assertEqual({ await coordinator.snapshot() }, .inactive)
        await assertEqual({ await adapter.events() }, [])
    }

    func testPurchaseSerializationPendingCorrelationAndBoundedOutcomeMapping() async {
        let session = storeSession(7)
        let purchaseGate = StoreKitRuntimeTestGate()
        let adapter = StoreKitRuntimeTestAdapter(products: localizedProducts(prefix: "Store"))
        await adapter.enqueuePurchase(.pending, gate: purchaseGate)
        await adapter.enqueuePurchase(.userCancelled)
        await adapter.enqueuePurchase(
            .processed(.rejected(.revokedTransaction))
        )
        await adapter.enqueuePurchase(
            .processed(
                .deferred(
                    transactionID: 900,
                    reason: .durableDeliveryUnavailable
                )
            )
        )
        await adapter.enqueuePurchase(
            .processed(
                .deliveredAndFinished(
                    transactionID: 901,
                    packID: EconomyConfiguration.coinPacks[0].id,
                    ledgerEntryID: LedgerEntryID("secret-ledger-id"),
                    deliveryStatus: .committed
                )
            )
        )
        let source = StoreKitRuntimeTestSessionSource(session: session)
        let coordinator = StoreKitRuntimeCoordinator(adapter: adapter, sessionSource: source)
        let packID = EconomyConfiguration.coinPacks[0].id

        await assertEqual({ await coordinator.activate() }, .activated)
        await assertEventually {
            await coordinator.snapshot().phase == .available
        }

        await assertEqual({ await coordinator.purchase(packID) }, .started)
        await assertEventually {
            await adapter.events().contains(.purchase(packID, session.nonce))
        }
        await assertEqual(
            { await coordinator.purchase(EconomyConfiguration.coinPacks[1].id) },
            .purchaseAlreadyInFlight
        )
        await purchaseGate.open()
        await assertEventually {
            await coordinator.snapshot().phase == .pending(packID)
        }
        await assertEqual({ await coordinator.purchase(packID) }, .purchasePending)

        await adapter.emit(
            .deliveredAndFinished(
                transactionID: 999,
                packID: EconomyConfiguration.coinPacks[1].id,
                ledgerEntryID: LedgerEntryID("not-presented"),
                deliveryStatus: .alreadyCommitted
            ),
            for: session
        )
        await assertEventually {
            let state = await coordinator.snapshot()
            return state.phase == .pending(packID)
                && state.latestOutcome == .processed(
                    source: .transactionUpdate,
                    outcome: .delivered(.alreadyCommitted)
                )
        }
        await assertEqual({ await coordinator.purchase(packID) }, .purchasePending)

        await adapter.emit(
            .deliveredAndFinished(
                transactionID: 1_000,
                packID: packID,
                ledgerEntryID: LedgerEntryID("matching-not-presented"),
                deliveryStatus: .committed
            ),
            for: session
        )
        await assertEventually {
            let state = await coordinator.snapshot()
            return state.phase == .available
                && state.latestOutcome == .processed(
                    source: .transactionUpdate,
                    outcome: .delivered(.committed)
                )
        }

        await assertEqual({ await coordinator.purchase(packID) }, .started)
        await assertEventually {
            await coordinator.snapshot().latestOutcome == .purchaseCancelled(packID)
        }

        await assertEqual({ await coordinator.purchase(packID) }, .started)
        await assertEventually {
            await coordinator.snapshot().latestOutcome == .processed(
                source: .purchase(packID),
                outcome: .rejected(.revokedTransaction)
            )
        }

        await assertEqual({ await coordinator.purchase(packID) }, .started)
        await assertEventually {
            let state = await coordinator.snapshot()
            return state.phase == .unavailable(
                .transactionDeferred(.durableDeliveryUnavailable)
            ) && state.latestOutcome == .processed(
                source: .purchase(packID),
                outcome: .deferred(.durableDeliveryUnavailable)
            )
        }

        await assertEqual({ await coordinator.retry() }, .activated)
        await assertEventually {
            await coordinator.snapshot().phase == .available
        }
        await assertEqual({ await coordinator.purchase(packID) }, .started)
        await assertEventually {
            await coordinator.snapshot().latestOutcome == .processed(
                source: .purchase(packID),
                outcome: .delivered(.committed)
            )
        }
        await coordinator.deactivate()
    }

    func testDeactivateWaitsForPurchaseCleanupAndSuppressesStaleCompletion() async {
        let session = storeSession(8)
        let purchaseGate = StoreKitRuntimeTestGate()
        let adapter = StoreKitRuntimeTestAdapter(products: localizedProducts(prefix: "Store"))
        await adapter.enqueuePurchase(.userCancelled, gate: purchaseGate)
        let source = StoreKitRuntimeTestSessionSource(session: session)
        let coordinator = StoreKitRuntimeCoordinator(adapter: adapter, sessionSource: source)
        let packID = EconomyConfiguration.coinPacks[0].id

        await assertEqual({ await coordinator.activate() }, .activated)
        await assertEventually {
            await coordinator.snapshot().phase == .available
        }
        await assertEqual({ await coordinator.purchase(packID) }, .started)
        await assertEventually { await adapter.activePurchaseCount() == 1 }

        let deactivation = Task {
            await coordinator.deactivate()
            return true
        }
        await assertEventually {
            await coordinator.snapshot().phase == .inactive
        }
        await assertEqual({ await adapter.activePurchaseCount() }, 1)

        await purchaseGate.open()
        let deactivated = await deactivation.value
        XCTAssertTrue(deactivated)
        await assertEqual({ await adapter.activePurchaseCount() }, 0)
        await assertEqual({ await coordinator.snapshot() }, .inactive)
    }

    func testShutdownAwaitsOwnedListenerProducerTermination() async {
        let session = storeSession(11)
        let stopGate = StoreKitRuntimeTestGate()
        let shutdownFinished = StoreKitRuntimeTestFlag()
        let adapter = StoreKitRuntimeTestAdapter(products: localizedProducts(prefix: "Store"))
        await adapter.setNextListenerStopGate(stopGate)
        let source = StoreKitRuntimeTestSessionSource(session: session)
        let coordinator = StoreKitRuntimeCoordinator(adapter: adapter, sessionSource: source)

        await assertEqual({ await coordinator.activate() }, .activated)
        await assertEventually {
            await coordinator.snapshot().phase == .available
        }

        let shutdownTask = Task {
            await coordinator.shutdown()
            await shutdownFinished.setTrue()
        }
        await assertEventually {
            await coordinator.snapshot().phase == .inactive
        }
        await assertEqual({ await shutdownFinished.value() }, false)
        await assertEqual(
            { await adapter.events().contains(.updatesProducerStopped(session.nonce)) },
            false
        )

        await stopGate.open()
        await shutdownTask.value
        await assertEqual({ await shutdownFinished.value() }, true)
        await assertEqual(
            { await adapter.events().contains(.updatesProducerStopped(session.nonce)) },
            true
        )
    }

    func testDropWithoutShutdownDoesNotRetainCoordinatorAndEventuallyStopsProducer() async {
        let session = storeSession(12)
        let adapter = StoreKitRuntimeTestAdapter(products: localizedProducts(prefix: "Store"))
        let source = StoreKitRuntimeTestSessionSource(session: session)
        var coordinator: StoreKitRuntimeCoordinator? = StoreKitRuntimeCoordinator(
            adapter: adapter,
            sessionSource: source
        )

        await assertEqual({ await coordinator?.activate() }, .activated)
        await assertEventually {
            await coordinator?.snapshot().phase == .available
        }
        weak let releasedCoordinator = coordinator
        coordinator = nil

        await assertEventually { releasedCoordinator == nil }
        await assertEventually {
            await adapter.events().contains(.updatesProducerStopped(session.nonce))
        }
    }

    func testPresentationSubscriptionStartsWithCompleteCurrentSnapshot() async {
        let adapter = StoreKitRuntimeTestAdapter(products: localizedProducts(prefix: "Store"))
        let source = StoreKitRuntimeTestSessionSource(session: nil)
        let coordinator = StoreKitRuntimeCoordinator(adapter: adapter, sessionSource: source)
        let stream = await coordinator.presentationUpdates()
        var iterator = stream.makeAsyncIterator()

        let initialState = await iterator.next()
        XCTAssertEqual(initialState, .inactive)
    }

    private func localizedProducts(prefix: String) -> [StoreProduct] {
        EconomyConfiguration.coinPacks.enumerated().map { index, pack in
            StoreProduct(
                packID: pack.id,
                displayName: "\(prefix) \(pack.displayName)",
                displayPrice: "Localized \(index + 1)",
                coins: pack.coins
            )
        }
    }

    private func storeSession(_ index: Int) -> StoreActiveSession {
        StoreActiveSession(
            binding: StoreAccountBinding(
                account: DurableAccountBinding(
                    accountKey: ServiceAccountKey("store-runtime-account-\(index)"),
                    profileID: uuid(index * 10 + 1)
                ),
                appAccountToken: uuid(index * 10 + 2)
            ),
            nonce: uuid(index * 10 + 3)
        )
    }

    private func uuid(_ value: Int) -> UUID {
        UUID(
            uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", value))"
        )!
    }

    private func eventually(
        iterations: Int = 10_000,
        _ condition: @escaping () async -> Bool
    ) async -> Bool {
        for _ in 0 ..< iterations {
            if await condition() { return true }
            await Task.yield()
        }
        return false
    }

    private func assertEventually(
        iterations: Int = 10_000,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: @escaping () async -> Bool
    ) async {
        let succeeded = await eventually(iterations: iterations, condition)
        XCTAssertTrue(succeeded, file: file, line: line)
    }

    private func assertEqual<Value: Equatable>(
        _ expression: () async -> Value,
        _ expected: Value,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let actual = await expression()
        XCTAssertEqual(actual, expected, file: file, line: line)
    }
}

private actor StoreKitRuntimeTestGate {
    private var isOpen: Bool

    init(isOpen: Bool = false) {
        self.isOpen = isOpen
    }

    func wait() async {
        while !isOpen {
            await Task.yield()
        }
    }

    func open() {
        isOpen = true
    }
}

private actor StoreKitRuntimeTestFlag {
    private var storedValue = false

    func setTrue() {
        storedValue = true
    }

    func value() -> Bool {
        storedValue
    }
}

private actor StoreKitRuntimeTestSessionSource: StoreKitRuntimeSessionSourcing {
    private var session: StoreActiveSession?
    private var nextGate: StoreKitRuntimeTestGate?
    private var requests = 0

    init(
        session: StoreActiveSession?,
        nextGate: StoreKitRuntimeTestGate? = nil
    ) {
        self.session = session
        self.nextGate = nextGate
    }

    func currentStoreSession() async -> StoreActiveSession? {
        requests += 1
        let gate = nextGate
        nextGate = nil
        await gate?.wait()
        return session
    }

    func setSession(_ session: StoreActiveSession?) {
        self.session = session
    }

    func requestCount() -> Int {
        requests
    }
}

private enum StoreKitRuntimeTestEvent: Equatable, Sendable {
    case updatesRequested(UUID)
    case updatesInstalled(UUID)
    case updatesProducerStopped(UUID)
    case recovery(UUID)
    case products(Int)
    case purchase(CoinPackID, UUID)
}

private actor StoreKitRuntimeTestAdapter: StoreKit2CoinTransactionAdapting {
    private struct ProductPlan {
        let products: [StoreProduct]
        let gate: StoreKitRuntimeTestGate?
    }

    private struct PurchasePlan {
        let result: StoreKit2CoinPurchaseResult
        let gate: StoreKitRuntimeTestGate?
    }

    private let defaultProducts: [StoreProduct]
    private var productPlans: [ProductPlan] = []
    private var purchasePlans: [PurchasePlan] = []
    private var nextRecoveryGate: StoreKitRuntimeTestGate?
    private var nextRecoveryResults: [StoreKit2TransactionProcessingResult] = []
    private var nextListenerStopGate: StoreKitRuntimeTestGate?
    private var recordedEvents: [StoreKitRuntimeTestEvent] = []
    private var updateContinuations:
        [UUID: [AsyncStream<StoreKit2TransactionProcessingResult>.Continuation]] = [:]
    private var productCalls = 0
    private var activePurchases = 0

    init(products: [StoreProduct]) {
        defaultProducts = products
    }

    func products() async throws -> [StoreProduct] {
        let callIndex = productCalls
        productCalls += 1
        recordedEvents.append(.products(callIndex))
        let plan = productPlans.isEmpty
            ? ProductPlan(products: defaultProducts, gate: nil)
            : productPlans.removeFirst()
        await plan.gate?.wait()
        return plan.products
    }

    func purchase(
        _ packID: CoinPackID,
        session: StoreActiveSession
    ) async throws -> StoreKit2CoinPurchaseResult {
        recordedEvents.append(.purchase(packID, session.nonce))
        activePurchases += 1
        defer { activePurchases -= 1 }
        let plan = purchasePlans.isEmpty
            ? PurchasePlan(result: .userCancelled, gate: nil)
            : purchasePlans.removeFirst()
        await plan.gate?.wait()
        return plan.result
    }

    func recoverUnfinishedTransactions(
        session: StoreActiveSession
    ) async -> [StoreKit2TransactionProcessingResult] {
        recordedEvents.append(.recovery(session.nonce))
        let gate = nextRecoveryGate
        nextRecoveryGate = nil
        let results = nextRecoveryResults
        nextRecoveryResults = []
        await gate?.wait()
        return results
    }

    func transactionUpdates(
        session: StoreActiveSession
    ) async -> StoreKit2OwnedUpdateListener<StoreKit2TransactionProcessingResult> {
        recordedEvents.append(.updatesRequested(session.nonce))
        let input = AsyncStream<StoreKit2TransactionProcessingResult>.makeStream()
        let output = AsyncStream<StoreKit2TransactionProcessingResult>.makeStream()
        updateContinuations[session.nonce, default: []].append(input.continuation)
        let stopGate = nextListenerStopGate
        nextListenerStopGate = nil
        let task = Task<Void, Never> { [weak self] in
            for await result in input.stream {
                guard !Task.isCancelled else { break }
                output.continuation.yield(result)
            }
            await stopGate?.wait()
            output.continuation.finish()
            await self?.recordProducerStopped(session.nonce)
        }
        output.continuation.onTermination = { @Sendable _ in
            task.cancel()
        }
        recordedEvents.append(.updatesInstalled(session.nonce))
        return StoreKit2OwnedUpdateListener(updates: output.stream) {
            input.continuation.finish()
            task.cancel()
            await task.value
        }
    }

    func setNextRecoveryGate(_ gate: StoreKitRuntimeTestGate) {
        nextRecoveryGate = gate
    }

    func setNextRecoveryResults(
        _ results: [StoreKit2TransactionProcessingResult]
    ) {
        nextRecoveryResults = results
    }

    func setNextListenerStopGate(_ gate: StoreKitRuntimeTestGate) {
        nextListenerStopGate = gate
    }

    func enqueueProducts(
        _ products: [StoreProduct],
        gate: StoreKitRuntimeTestGate? = nil
    ) {
        productPlans.append(ProductPlan(products: products, gate: gate))
    }

    func enqueuePurchase(
        _ result: StoreKit2CoinPurchaseResult,
        gate: StoreKitRuntimeTestGate? = nil
    ) {
        purchasePlans.append(PurchasePlan(result: result, gate: gate))
    }

    func emit(
        _ result: StoreKit2TransactionProcessingResult,
        for session: StoreActiveSession
    ) {
        for continuation in updateContinuations[session.nonce, default: []] {
            continuation.yield(result)
        }
    }

    func finishUpdates(for session: StoreActiveSession) {
        for continuation in updateContinuations[session.nonce, default: []] {
            continuation.finish()
        }
        updateContinuations[session.nonce] = []
    }

    func events() -> [StoreKitRuntimeTestEvent] {
        recordedEvents
    }

    func activePurchaseCount() -> Int {
        activePurchases
    }

    private func recordProducerStopped(_ nonce: UUID) {
        recordedEvents.append(.updatesProducerStopped(nonce))
    }
}

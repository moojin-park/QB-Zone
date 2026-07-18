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
        let context = try! commerceContext(session: session, index: 10)
        let authorizer = OnlineCommerceTestAuthorizer()
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
        let purchase = Task {
            await coordinator.purchaseAndWait(
                packID,
                expected: context,
                authorizer: authorizer
            )
        }
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
        _ = await purchase.value
        await assertEventually { await adapter.activePurchaseCount() == 0 }
        for _ in 0 ..< 100 { await Task.yield() }
        await assertEqual({ await coordinator.snapshot() }, blockedState)
        await assertEqual(
            {
                await coordinator.purchaseAndWait(
                    packID,
                    expected: context,
                    authorizer: authorizer
                )
            },
            .productUnavailable
        )

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
        let context = try! commerceContext(session: session, index: 7)
        let authorizer = OnlineCommerceTestAuthorizer()
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

        let firstPurchase = Task {
            await coordinator.purchaseAndWait(
                packID,
                expected: context,
                authorizer: authorizer
            )
        }
        await assertEventually {
            await adapter.events().contains(.purchase(packID, session.nonce))
        }
        await assertEqual(
            {
                await coordinator.purchaseAndWait(
                    EconomyConfiguration.coinPacks[1].id,
                    expected: context,
                    authorizer: authorizer
                )
            },
            .purchaseAlreadyInFlight
        )
        await purchaseGate.open()
        await assertEqual({ await firstPurchase.value }, .pending)
        await assertEventually {
            await coordinator.snapshot().phase == .pending(packID)
        }
        await assertEqual(
            {
                await coordinator.purchaseAndWait(
                    packID,
                    expected: context,
                    authorizer: authorizer
                )
            },
            .purchasePending
        )

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
        await assertEqual(
            {
                await coordinator.purchaseAndWait(
                    packID,
                    expected: context,
                    authorizer: authorizer
                )
            },
            .purchasePending
        )

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

        await assertEqual(
            {
                await coordinator.purchaseAndWait(
                    packID,
                    expected: context,
                    authorizer: authorizer
                )
            },
            .userCancelled
        )
        await assertEventually {
            await coordinator.snapshot().latestOutcome == .purchaseCancelled(packID)
        }

        await assertEqual(
            {
                await coordinator.purchaseAndWait(
                    packID,
                    expected: context,
                    authorizer: authorizer
                )
            },
            .processed(.rejected(.revokedTransaction))
        )
        await assertEventually {
            await coordinator.snapshot().latestOutcome == .processed(
                source: .purchase(packID),
                outcome: .rejected(.revokedTransaction)
            )
        }

        await assertEqual(
            {
                await coordinator.purchaseAndWait(
                    packID,
                    expected: context,
                    authorizer: authorizer
                )
            },
            .processed(
                .deferred(.durableDeliveryUnavailable)
            )
        )
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
        await assertEqual(
            {
                await coordinator.purchaseAndWait(
                    packID,
                    expected: context,
                    authorizer: authorizer
                )
            },
            .processed(.delivered(.committed))
        )
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
        let context = try! commerceContext(session: session, index: 8)
        let authorizer = OnlineCommerceTestAuthorizer()
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
        let purchase = Task {
            await coordinator.purchaseAndWait(
                packID,
                expected: context,
                authorizer: authorizer
            )
        }
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
        await assertEqual({ await purchase.value }, .cancelled)
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

    func testAwaitedOnlinePurchaseRejectsDuplicateWithoutOpeningSecondSheet() async throws {
        let session = storeSession(20)
        let context = try commerceContext(session: session, index: 20)
        let purchaseGate = StoreKitRuntimeTestGate()
        let adapter = StoreKitRuntimeTestAdapter(products: localizedProducts(prefix: "Store"))
        await adapter.enqueuePurchase(.userCancelled, gate: purchaseGate)
        let source = StoreKitRuntimeTestSessionSource(session: session)
        let authorizer = OnlineCommerceTestAuthorizer()
        let coordinator = StoreKitRuntimeCoordinator(adapter: adapter, sessionSource: source)
        let packID = EconomyConfiguration.coinPacks[0].id

        await assertEqual({ await coordinator.activate() }, .activated)
        await assertEventually { await coordinator.snapshot().phase == .available }

        let first = Task {
            await coordinator.purchaseAndWait(
                packID,
                expected: context,
                authorizer: authorizer
            )
        }
        await assertEventually { await adapter.activePurchaseCount() == 1 }
        let duplicate = await coordinator.purchaseAndWait(
            packID,
            expected: context,
            authorizer: authorizer
        )
        XCTAssertEqual(duplicate, .purchaseAlreadyInFlight)
        let purchaseCount = await adapter.events().filter {
            if case .purchase = $0 { return true }
            return false
        }.count
        XCTAssertEqual(purchaseCount, 1)

        await purchaseGate.open()
        let firstResult = await first.value
        XCTAssertEqual(firstResult, .userCancelled)
        await coordinator.shutdown()
    }

    func testCancelledAwaitedAuthorizationNeverOpensStoreKitSheet() async throws {
        let session = storeSession(21)
        let context = try commerceContext(session: session, index: 21)
        let adapter = StoreKitRuntimeTestAdapter(products: localizedProducts(prefix: "Store"))
        let source = StoreKitRuntimeTestSessionSource(session: session)
        let authorizationGate = OnlineCommerceCancellationGate()
        let authorizer = OnlineCommerceTestAuthorizer(gate: authorizationGate)
        let coordinator = StoreKitRuntimeCoordinator(adapter: adapter, sessionSource: source)
        let packID = EconomyConfiguration.coinPacks[0].id

        await assertEqual({ await coordinator.activate() }, .activated)
        await assertEventually { await coordinator.snapshot().phase == .available }
        let request = Task {
            await coordinator.purchaseAndWait(
                packID,
                expected: context,
                authorizer: authorizer
            )
        }
        await assertEventually { await authorizer.requestCount() == 1 }
        request.cancel()

        let requestResult = await request.value
        let purchaseCount = await adapter.events().filter {
            if case .purchase = $0 { return true }
            return false
        }.count
        XCTAssertEqual(requestResult, .cancelled)
        XCTAssertEqual(purchaseCount, 0)
        await coordinator.shutdown()
    }

    func testOfflineCommerceAttemptLeavesCompleteProfileSnapshotUnchanged() async throws {
        let fixture = try commerceFixture(index: 22)
        let recorder = OnlineCommerceTestRecorder()
        let authorizer = OnlineCommerceTestAuthorizer(
            failures: [.network],
            recorder: recorder
        )
        let economy = OnlineCommerceTestEconomy(recorder: recorder)
        let refresher = OnlineCommerceTestRefresher(
            snapshot: fixture.snapshot,
            recorder: recorder
        )
        let store = OnlineCommerceTestStore(recorder: recorder)
        let coordinator = OnlineCommerceCoordinator(
            context: fixture.context,
            authorizer: authorizer,
            economy: economy,
            refresher: refresher,
            store: store
        )
        let before = await refresher.currentSnapshot()

        let result = await coordinator.requestCoinPack(
            EconomyConfiguration.coinPacks[0].id
        )

        XCTAssertEqual(result, .failed(.onlineRequired))
        let after = await refresher.currentSnapshot()
        let events = await recorder.events()
        let confirmationCount = await economy.confirmCount()
        let sheetCount = await store.sheetCount()
        XCTAssertEqual(after, before)
        XCTAssertEqual(events, [.authorize])
        XCTAssertEqual(confirmationCount, 0)
        XCTAssertEqual(sheetCount, 0)
    }

    func testOnlineCoinPackConfirmsPendingThenRefreshesBeforeFinalAuthorization() async throws {
        let fixture = try commerceFixture(index: 23)
        let recorder = OnlineCommerceTestRecorder()
        let authorizer = OnlineCommerceTestAuthorizer(recorder: recorder)
        let economy = OnlineCommerceTestEconomy(recorder: recorder)
        let refresher = OnlineCommerceTestRefresher(
            snapshot: fixture.snapshot,
            recorder: recorder
        )
        let store = OnlineCommerceTestStore(recorder: recorder)
        let coordinator = OnlineCommerceCoordinator(
            context: fixture.context,
            authorizer: authorizer,
            economy: economy,
            refresher: refresher,
            store: store
        )

        let result = await coordinator.requestCoinPack(
            EconomyConfiguration.coinPacks[0].id
        )

        XCTAssertEqual(result, .completed(.userCancelled))
        let events = await recorder.events()
        XCTAssertEqual(
            events,
            [.authorize, .confirmPending, .refresh, .authorize, .storeSheet]
        )
    }

    func testConnectivityLossAtFinalCoinPackAuthorizationOpensNoSheet() async throws {
        let fixture = try commerceFixture(index: 24)
        let recorder = OnlineCommerceTestRecorder()
        let authorizer = OnlineCommerceTestAuthorizer(
            failures: [nil, .service],
            recorder: recorder
        )
        let economy = OnlineCommerceTestEconomy(recorder: recorder)
        let refresher = OnlineCommerceTestRefresher(
            snapshot: fixture.snapshot,
            recorder: recorder
        )
        let store = OnlineCommerceTestStore(recorder: recorder)
        let coordinator = OnlineCommerceCoordinator(
            context: fixture.context,
            authorizer: authorizer,
            economy: economy,
            refresher: refresher,
            store: store
        )
        let before = await refresher.currentSnapshot()

        let result = await coordinator.requestCoinPack(
            EconomyConfiguration.coinPacks[0].id
        )

        XCTAssertEqual(result, .failed(.onlineRequired))
        let after = await refresher.currentSnapshot()
        let sheetCount = await store.sheetCount()
        let events = await recorder.events()
        XCTAssertEqual(after, before)
        XCTAssertEqual(sheetCount, 0)
        XCTAssertEqual(events, [.authorize, .confirmPending, .refresh, .authorize])
    }

    func testDuplicateCoinPackTapIsFailFastAndOpensOneSheet() async throws {
        let fixture = try commerceFixture(index: 25)
        let recorder = OnlineCommerceTestRecorder()
        let authorizer = OnlineCommerceTestAuthorizer(recorder: recorder)
        let economy = OnlineCommerceTestEconomy(recorder: recorder)
        let refresher = OnlineCommerceTestRefresher(
            snapshot: fixture.snapshot,
            recorder: recorder
        )
        let storeGate = StoreKitRuntimeTestGate()
        let store = OnlineCommerceTestStore(recorder: recorder, gate: storeGate)
        let coordinator = OnlineCommerceCoordinator(
            context: fixture.context,
            authorizer: authorizer,
            economy: economy,
            refresher: refresher,
            store: store
        )
        let packID = EconomyConfiguration.coinPacks[0].id

        let first = Task { await coordinator.requestCoinPack(packID) }
        await assertEventually { await store.sheetCount() == 1 }
        let duplicate = await coordinator.requestCoinPack(packID)
        let sheetCount = await store.sheetCount()
        XCTAssertEqual(duplicate, .failed(.requestAlreadyInFlight))
        XCTAssertEqual(sheetCount, 1)
        await storeGate.open()
        let firstResult = await first.value
        XCTAssertEqual(firstResult, .completed(.userCancelled))
    }

    func testOfflineCatalogUnlockLeavesCompleteProfileSnapshotUnchanged()
        async throws
    {
        let fixture = try commerceFixture(index: 28)
        let recorder = OnlineCommerceTestRecorder()
        let authorizer = OnlineCommerceTestAuthorizer(
            failures: [.network],
            recorder: recorder
        )
        let economy = OnlineCommerceTestEconomy(recorder: recorder)
        let refresher = OnlineCommerceTestRefresher(
            snapshot: fixture.snapshot,
            recorder: recorder
        )
        let coordinator = OnlineCommerceCoordinator(
            context: fixture.context,
            authorizer: authorizer,
            economy: economy,
            refresher: refresher,
            store: OnlineCommerceTestStore(recorder: recorder)
        )
        let before = await refresher.currentSnapshot()
        let itemID = try XCTUnwrap(
            LaunchCatalog.approved.unlockableItems.first?.id
        )

        let result = await coordinator.purchaseCatalogItem(
            itemID,
            requestOperationID: OperationID("offline-catalog-unlock")
        )

        XCTAssertEqual(result, .failed(.onlineRequired))
        let after = await refresher.currentSnapshot()
        let events = await recorder.events()
        let confirmationCount = await economy.confirmCount()
        let unlockCount = await economy.unlockCount()
        XCTAssertEqual(after, before)
        XCTAssertEqual(events, [.authorize])
        XCTAssertEqual(confirmationCount, 0)
        XCTAssertEqual(unlockCount, 0)
    }

    func testOnlineCatalogUnlockConfirmsRefreshesReauthorizesThenUnlocks()
        async throws
    {
        let fixture = try commerceFixture(index: 29)
        let recorder = OnlineCommerceTestRecorder()
        let itemID = try XCTUnwrap(
            LaunchCatalog.approved.unlockableItems.first?.id
        )
        let expected = catalogUnlockResult(itemID: itemID, index: 29)
        let economy = OnlineCommerceTestEconomy(
            recorder: recorder,
            unlockResult: expected
        )
        let coordinator = OnlineCommerceCoordinator(
            context: fixture.context,
            authorizer: OnlineCommerceTestAuthorizer(recorder: recorder),
            economy: economy,
            refresher: OnlineCommerceTestRefresher(
                snapshot: fixture.snapshot,
                recorder: recorder
            ),
            store: OnlineCommerceTestStore(recorder: recorder)
        )

        let result = await coordinator.purchaseCatalogItem(
            itemID,
            requestOperationID: OperationID("online-catalog-unlock")
        )

        XCTAssertEqual(result, .purchased(expected))
        let events = await recorder.events()
        let unlockCount = await economy.unlockCount()
        XCTAssertEqual(
            events,
            [.authorize, .confirmPending, .refresh, .authorize, .unlock]
        )
        XCTAssertEqual(unlockCount, 1)
    }

    func testConnectivityLossAtFinalCatalogAuthorizationPerformsNoUnlock()
        async throws
    {
        let fixture = try commerceFixture(index: 30)
        let recorder = OnlineCommerceTestRecorder()
        let itemID = try XCTUnwrap(
            LaunchCatalog.approved.unlockableItems.first?.id
        )
        let economy = OnlineCommerceTestEconomy(
            recorder: recorder,
            unlockResult: catalogUnlockResult(itemID: itemID, index: 30)
        )
        let refresher = OnlineCommerceTestRefresher(
            snapshot: fixture.snapshot,
            recorder: recorder
        )
        let coordinator = OnlineCommerceCoordinator(
            context: fixture.context,
            authorizer: OnlineCommerceTestAuthorizer(
                failures: [nil, .service],
                recorder: recorder
            ),
            economy: economy,
            refresher: refresher,
            store: OnlineCommerceTestStore(recorder: recorder)
        )
        let before = await refresher.currentSnapshot()

        let result = await coordinator.purchaseCatalogItem(
            itemID,
            requestOperationID: OperationID("lost-catalog-authorization")
        )

        XCTAssertEqual(result, .failed(.onlineRequired))
        let after = await refresher.currentSnapshot()
        let unlockCount = await economy.unlockCount()
        let events = await recorder.events()
        XCTAssertEqual(after, before)
        XCTAssertEqual(unlockCount, 0)
        XCTAssertEqual(
            events,
            [.authorize, .confirmPending, .refresh, .authorize]
        )
    }

    func testDuplicateCatalogUnlockIsFailFastAndEachRetryHasOneAdmission()
        async throws
    {
        let fixture = try commerceFixture(index: 31)
        let recorder = OnlineCommerceTestRecorder()
        let itemID = try XCTUnwrap(
            LaunchCatalog.approved.unlockableItems.first?.id
        )
        let expected = catalogUnlockResult(itemID: itemID, index: 31)
        let unlockGate = StoreKitRuntimeTestGate()
        let economy = OnlineCommerceTestEconomy(
            recorder: recorder,
            unlockResult: expected,
            unlockGate: unlockGate
        )
        let coordinator = OnlineCommerceCoordinator(
            context: fixture.context,
            authorizer: OnlineCommerceTestAuthorizer(recorder: recorder),
            economy: economy,
            refresher: OnlineCommerceTestRefresher(
                snapshot: fixture.snapshot,
                recorder: recorder
            ),
            store: OnlineCommerceTestStore(recorder: recorder)
        )

        let first = Task {
            await coordinator.purchaseCatalogItem(
                itemID,
                requestOperationID: OperationID("catalog-first")
            )
        }
        await assertEventually { await economy.unlockCount() == 1 }

        let duplicate = await coordinator.purchaseCatalogItem(
            itemID,
            requestOperationID: OperationID("catalog-duplicate")
        )
        let unlockCountAfterDuplicate = await economy.unlockCount()
        XCTAssertEqual(duplicate, .failed(.requestAlreadyInFlight))
        XCTAssertEqual(unlockCountAfterDuplicate, 1)

        await unlockGate.open()
        let firstResult = await first.value
        XCTAssertEqual(firstResult, .purchased(expected))

        let retry = await coordinator.purchaseCatalogItem(
            itemID,
            requestOperationID: OperationID("catalog-retry")
        )
        let finalUnlockCount = await economy.unlockCount()
        XCTAssertEqual(retry, .purchased(expected))
        XCTAssertEqual(
            finalUnlockCount,
            2,
            "Only the first tap and one explicit retry may reach durable unlock"
        )
    }

    func testOnlyConnectivityDurableDeferralMapsToOnlineWarning() async throws {
        let fixture = try commerceFixture(index: 26)
        let connectivityRecorder = OnlineCommerceTestRecorder()
        let connectivityCoordinator = OnlineCommerceCoordinator(
            context: fixture.context,
            authorizer: OnlineCommerceTestAuthorizer(recorder: connectivityRecorder),
            economy: OnlineCommerceTestEconomy(recorder: connectivityRecorder),
            refresher: OnlineCommerceTestRefresher(
                snapshot: fixture.snapshot,
                recorder: connectivityRecorder
            ),
            store: OnlineCommerceTestStore(
                recorder: connectivityRecorder,
                completion: .processed(
                    .deferred(.durableDeliveryConnectivityUnavailable)
                )
            )
        )
        let connectivityResult = await connectivityCoordinator.requestCoinPack(
            EconomyConfiguration.coinPacks[0].id
        )
        XCTAssertEqual(connectivityResult, .failed(.onlineRequired))

        let integrityRecorder = OnlineCommerceTestRecorder()
        let integrityCoordinator = OnlineCommerceCoordinator(
            context: fixture.context,
            authorizer: OnlineCommerceTestAuthorizer(recorder: integrityRecorder),
            economy: OnlineCommerceTestEconomy(recorder: integrityRecorder),
            refresher: OnlineCommerceTestRefresher(
                snapshot: fixture.snapshot,
                recorder: integrityRecorder
            ),
            store: OnlineCommerceTestStore(
                recorder: integrityRecorder,
                completion: .processed(.deferred(.durableDeliveryUnavailable))
            )
        )
        let integrityResult = await integrityCoordinator.requestCoinPack(
            EconomyConfiguration.coinPacks[0].id
        )
        XCTAssertEqual(
            integrityResult,
            .failed(
                .store(
                    .transactionDeferred(.durableDeliveryUnavailable)
                )
            )
        )
    }

    func testPrivateCloudAuthorizerProbesNetworkAndRejectsAccountLossAfterProbe() async throws {
        let fixture = try commerceFixture(index: 27)
        let authority = DurableEconomySessionAuthority(context: fixture.context)
        let cloud = OnlineCommerceTestCloud(
            accountStates: [
                .available(fixture.context.cloudAccountID),
                .signedOut,
            ]
        )
        let authorizer = PrivateCloudCommerceTransactionAuthorizer(
            sessionAuthority: authority,
            cloud: cloud,
            networkProbeRecordID: CloudRecordID("commerce-network-probe")
        )

        do {
            try await authorizer.revalidate(expected: fixture.context)
            XCTFail("Account loss after the network probe must fail closed")
        } catch {
            XCTAssertEqual(
                error as? DurableEconomyCoordinatorError,
                .cloudAccountUnavailable
            )
        }
        let events = await cloud.events()
        XCTAssertEqual(events, [.accountState, .records, .accountState])
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

    private func commerceContext(
        session: StoreActiveSession,
        index: Int
    ) throws -> DurableEconomySessionContext {
        try DurableEconomySessionContext(
            cloudAccountID: CloudAccountID("commerce-cloud-\(index)"),
            accountBinding: session.binding.account,
            profileSession: ProfileSessionToken(
                accountIdentity: PlayerAccountIdentity("commerce-player-\(index)"),
                nonce: session.nonce,
                profileID: session.binding.account.profileID
            ),
            storeSession: session
        )
    }

    private func commerceFixture(
        index: Int
    ) throws -> (context: DurableEconomySessionContext, snapshot: LocalPlayerProfileSnapshot) {
        let session = storeSession(index)
        let context = try commerceContext(session: session, index: index)
        let document = PlayerProfileFactory.makeDefault(
            profileID: context.profileSession.profileID,
            accountIdentity: context.profileSession.accountIdentity,
            deviceID: "commerce-device-\(index)",
            createdAt: Date(timeIntervalSince1970: TimeInterval(index))
        )
        let snapshot = try PlayerProfileProjection.snapshot(
            for: document,
            session: context.profileSession,
            syncStatus: .current
        )
        return (context, snapshot)
    }

    private func catalogUnlockResult(
        itemID: CatalogItemID,
        index: Int
    ) -> DurableCatalogUnlockResult {
        DurableCatalogUnlockResult(
            outcome: CatalogUnlockOutcome(
                itemID: itemID,
                price: 500,
                wasAlreadyUnlocked: false,
                confirmedBalanceAfter: 1_000
            ),
            cloudReceipt: DurableEconomyCloudCommitReceipt(
                accountID: CloudAccountID("catalog-cloud-\(index)"),
                operationID: OperationID("catalog-operation-\(index)"),
                recordID: CloudRecordID("catalog-record-\(index)"),
                observedChangeTag: CloudChangeTag("catalog-tag-\(index)"),
                cloudEconomyRevision: UInt64(index),
                status: .committed
            )
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

private enum OnlineCommerceTestEvent: Equatable, Sendable {
    case authorize
    case confirmPending
    case refresh
    case unlock
    case storeSheet
}

private enum OnlineCommerceTestAuthorizationFailure: Sendable {
    case network
    case service
}

private enum OnlineCommerceTestCloudEvent: Equatable, Sendable {
    case accountState
    case records
}

private actor OnlineCommerceTestCloud: CloudSyncTransport {
    private var accountStates: [CloudAccountState]
    private var recordedEvents: [OnlineCommerceTestCloudEvent] = []

    init(accountStates: [CloudAccountState]) {
        self.accountStates = accountStates
    }

    func accountState() -> CloudAccountState {
        recordedEvents.append(.accountState)
        return accountStates.isEmpty ? .unknown : accountStates.removeFirst()
    }

    func records(
        accountID _: CloudAccountID,
        ids _: [CloudRecordID]
    ) throws -> [CloudRecord] {
        recordedEvents.append(.records)
        return []
    }

    func commitAtomically(
        _ request: CloudAtomicWriteRequest
    ) throws -> CloudAtomicWriteReceipt {
        throw CloudKitCloudSyncError.invalidRequest
    }

    func events() -> [OnlineCommerceTestCloudEvent] { recordedEvents }
}

private actor OnlineCommerceTestRecorder {
    private var recorded: [OnlineCommerceTestEvent] = []

    func record(_ event: OnlineCommerceTestEvent) {
        recorded.append(event)
    }

    func events() -> [OnlineCommerceTestEvent] {
        recorded
    }
}

private actor OnlineCommerceCancellationGate {
    private var entered = false
    private var open = false

    func wait() async throws {
        entered = true
        while !open {
            try Task.checkCancellation()
            await Task.yield()
        }
    }

    func hasEntered() -> Bool { entered }
    func release() { open = true }
}

private actor OnlineCommerceTestAuthorizer: OnlineCommerceTransactionAuthorizing {
    private var failures: [OnlineCommerceTestAuthorizationFailure?]
    private let gate: OnlineCommerceCancellationGate?
    private let recorder: OnlineCommerceTestRecorder?
    private var requests = 0

    init(
        failures: [OnlineCommerceTestAuthorizationFailure?] = [],
        gate: OnlineCommerceCancellationGate? = nil,
        recorder: OnlineCommerceTestRecorder? = nil
    ) {
        self.failures = failures
        self.gate = gate
        self.recorder = recorder
    }

    func revalidate(
        expected _: DurableEconomySessionContext
    ) async throws {
        requests += 1
        await recorder?.record(.authorize)
        try await gate?.wait()
        try Task.checkCancellation()
        let failure = failures.isEmpty ? nil : failures.removeFirst()
        switch failure {
        case .network:
            throw CloudKitCloudSyncError.networkUnavailable(retryAfterSeconds: nil)
        case .service:
            throw CloudKitCloudSyncError.serviceUnavailable(retryAfterSeconds: nil)
        case nil:
            return
        }
    }

    func requestCount() -> Int { requests }
}

private actor OnlineCommerceTestEconomy: OnlineCommerceDurableEconomyTransacting {
    private let recorder: OnlineCommerceTestRecorder
    private let unlockResult: DurableCatalogUnlockResult?
    private let unlockGate: StoreKitRuntimeTestGate?
    private var confirmations = 0
    private var unlocks = 0

    init(
        recorder: OnlineCommerceTestRecorder,
        unlockResult: DurableCatalogUnlockResult? = nil,
        unlockGate: StoreKitRuntimeTestGate? = nil
    ) {
        self.recorder = recorder
        self.unlockResult = unlockResult
        self.unlockGate = unlockGate
    }

    func confirmAllPendingCredits() async throws -> DurablePendingCreditResult? {
        confirmations += 1
        await recorder.record(.confirmPending)
        return nil
    }

    func unlock(
        itemID _: CatalogItemID,
        requestOperationID _: OperationID,
        session _: ProfileSessionToken
    ) async throws -> DurableCatalogUnlockResult {
        unlocks += 1
        await recorder.record(.unlock)
        await unlockGate?.wait()
        guard let unlockResult else {
            throw DurableEconomyCoordinatorError.invalidCatalogUnlockRequest
        }
        return unlockResult
    }

    func confirmCount() -> Int { confirmations }
    func unlockCount() -> Int { unlocks }
}

private actor OnlineCommerceTestRefresher: OnlineCommerceAuthoritativeRefreshing {
    private var snapshot: LocalPlayerProfileSnapshot
    private let recorder: OnlineCommerceTestRecorder

    init(
        snapshot: LocalPlayerProfileSnapshot,
        recorder: OnlineCommerceTestRecorder
    ) {
        self.snapshot = snapshot
        self.recorder = recorder
    }

    func refreshAuthoritativeProfile(
        expected _: DurableEconomySessionContext
    ) async throws -> LocalPlayerProfileSnapshot {
        await recorder.record(.refresh)
        return snapshot
    }

    func currentSnapshot() -> LocalPlayerProfileSnapshot { snapshot }
}

private actor OnlineCommerceTestStore: OnlineCommerceStorePurchasing {
    private let recorder: OnlineCommerceTestRecorder
    private let gate: StoreKitRuntimeTestGate?
    private let completion: StoreKitRuntimePurchaseCompletion
    private var sheets = 0

    init(
        recorder: OnlineCommerceTestRecorder,
        gate: StoreKitRuntimeTestGate? = nil,
        completion: StoreKitRuntimePurchaseCompletion = .userCancelled
    ) {
        self.recorder = recorder
        self.gate = gate
        self.completion = completion
    }

    func purchaseAndWait(
        _ packID: CoinPackID,
        expected context: DurableEconomySessionContext,
        authorizer: any OnlineCommerceTransactionAuthorizing
    ) async -> StoreKitRuntimePurchaseCompletion {
        do {
            try await authorizer.revalidate(expected: context)
            try Task.checkCancellation()
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .failed(StoreKitRuntimeFailure(error: error))
        }
        _ = packID
        sheets += 1
        await recorder.record(.storeSheet)
        await gate?.wait()
        return completion
    }

    func sheetCount() -> Int { sheets }
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

    func purchaseOnline(
        _ packID: CoinPackID,
        session: StoreActiveSession,
        expected context: DurableEconomySessionContext,
        authorizer: any OnlineCommerceTransactionAuthorizing
    ) async throws -> StoreKit2CoinPurchaseResult {
        try await authorizer.revalidate(expected: context)
        try Task.checkCancellation()
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

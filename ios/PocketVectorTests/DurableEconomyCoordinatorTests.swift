import XCTest

@testable import PocketVector

final class DurableEconomyCoordinatorTests: XCTestCase, @unchecked Sendable {
    private let baseDate = Date(timeIntervalSince1970: 1_750_000_000)

    func testPendingGameplayAndSigningCreditsCommitExactlyOnceAcrossRelaunch() async throws {
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let database = InMemoryCloudDurableDatabase()
        let cloud = InMemoryCloudSyncTransport(
            accountState: .available(cloudAccountID),
            database: database
        )
        let first = try await makeFixture(
            directory: directory,
            cloud: cloud,
            sessionNonce: uuid(1),
            newProfileID: uuid(2)
        )
        let settlement = try await settleRun(
            index: 1,
            repository: first.repository,
            session: first.snapshot.session
        )
        let entryIDs = Set(
            [
                settlement.outcome.gameplayRewardEntryID,
                settlement.outcome.signingBonusEntryID,
            ].compactMap { $0 }
        )

        let firstResult = try await first.coordinator.confirmPendingCredits(
            entryIDs,
            session: first.snapshot.session
        )
        let retry = try await first.coordinator.confirmPendingCredits(
            entryIDs,
            session: first.snapshot.session
        )

        XCTAssertEqual(firstResult.cloudReceipt.status, .committed)
        XCTAssertEqual(retry.cloudReceipt.status, .alreadyCommitted)
        XCTAssertEqual(
            firstResult.cloudReceipt.operationID,
            retry.cloudReceipt.operationID
        )
        XCTAssertEqual(
            firstResult.cloudReceipt.observedChangeTag,
            retry.cloudReceipt.observedChangeTag
        )
        XCTAssertEqual(retry.snapshot.coinBalances.confirmed, 290)
        XCTAssertEqual(retry.snapshot.coinBalances.pending, 0)
        XCTAssertTrue(retry.snapshot.pendingLedgerEntryIDs.isEmpty)

        let relaunched = try await makeFixture(
            directory: directory,
            cloud: cloud,
            sessionNonce: uuid(3),
            newProfileID: uuid(999)
        )
        let relaunchedRetry = try await relaunched.coordinator.confirmPendingCredits(
            entryIDs,
            session: relaunched.snapshot.session
        )
        XCTAssertEqual(relaunchedRetry.cloudReceipt.status, .alreadyCommitted)
        XCTAssertEqual(
            relaunchedRetry.cloudReceipt.operationID,
            firstResult.cloudReceipt.operationID
        )
        XCTAssertEqual(relaunchedRetry.snapshot.coinBalances.confirmed, 290)
        XCTAssertEqual(relaunchedRetry.snapshot.ledger.count, 2)
    }

    func testCloudCommitSurvivesLostResponseAndLocalRelaunchWithoutDuplicateGrant() async throws {
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let database = InMemoryCloudDurableDatabase()
        let base = InMemoryCloudSyncTransport(
            accountState: .available(cloudAccountID),
            database: database
        )
        let losingTransport = CommitThenFailOnceTransport(base: base)
        let first = try await makeFixture(
            directory: directory,
            cloud: losingTransport,
            sessionNonce: uuid(10),
            newProfileID: uuid(11)
        )
        let settlement = try await settleRun(
            index: 10,
            repository: first.repository,
            session: first.snapshot.session
        )
        let entryIDs = Set(
            [
                settlement.outcome.gameplayRewardEntryID,
                settlement.outcome.signingBonusEntryID,
            ].compactMap { $0 }
        )

        do {
            _ = try await first.coordinator.confirmPendingCredits(
                entryIDs,
                session: first.snapshot.session
            )
            XCTFail("The simulated lost response must not acknowledge local coins")
        } catch {
            XCTAssertEqual(error as? DurableEconomyTestTransportError, .responseLost)
        }
        let stillPending = try await first.repository.snapshot()
        XCTAssertEqual(stillPending.coinBalances.confirmed, 0)
        XCTAssertEqual(stillPending.coinBalances.pending, 290)

        let relaunched = try await makeFixture(
            directory: directory,
            cloud: base,
            sessionNonce: uuid(12),
            newProfileID: uuid(999)
        )
        let recovered = try await relaunched.coordinator.confirmPendingCredits(
            entryIDs,
            session: relaunched.snapshot.session
        )
        XCTAssertEqual(recovered.cloudReceipt.status, .alreadyCommitted)
        XCTAssertEqual(recovered.snapshot.coinBalances.confirmed, 290)
        XCTAssertEqual(recovered.snapshot.coinBalances.pending, 0)
        let records = await base.allRecords(for: cloudAccountID)
        XCTAssertEqual(records.count, 3)
    }

    func testStoreKitAdapterFinishesOnlyAfterCloudAndRepositoryAcknowledgeCredit() async throws {
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let cloud = InMemoryCloudSyncTransport(
            accountState: .available(cloudAccountID)
        )
        let fixture = try await makeFixture(
            directory: directory,
            cloud: cloud,
            sessionNonce: uuid(20),
            newProfileID: uuid(21)
        )
        let identifiers = Dictionary(
            uniqueKeysWithValues: EconomyConfiguration.coinPacks.map {
                ($0.id, "test.pocket-vector.\($0.id.rawValue)")
            }
        )
        let configuration = try StoreKit2ProductConfiguration(
            productIdentifiers: identifiers
        )
        let pack = EconomyConfiguration.coinPacks[1]
        let productID = try configuration.productIdentifier(for: pack.id)
        let transaction = StoreKit2PlatformTransaction(
            transactionID: 2_001,
            productIdentifier: productID,
            appAccountToken: fixture.context.storeSession.binding.appAccountToken,
            purchaseDate: baseDate,
            isRevoked: false
        )
        let platform = DurableEconomyTestStoreKitClient(
            products: try EconomyConfiguration.coinPacks.map { descriptor in
                StoreKit2PlatformProduct(
                    productIdentifier: try configuration.productIdentifier(
                        for: descriptor.id
                    ),
                    displayName: descriptor.displayName,
                    displayPrice: "Localized",
                    isConsumable: true
                )
            },
            unfinished: [.verified(transaction)]
        )
        let adapter = StoreKit2CoinTransactionAdapter(
            configuration: configuration,
            platformClient: platform,
            durableDelivery: fixture.coordinator
        )

        let results = await adapter.recoverUnfinishedTransactions(
            session: fixture.context.storeSession
        )

        XCTAssertEqual(
            results,
            [
                .deliveredAndFinished(
                    transactionID: transaction.transactionID,
                    ledgerEntryID: CoinLedgerID.storeKit(
                        transactionID: transaction.transactionID
                    ),
                    deliveryStatus: .committed
                ),
            ]
        )
        let snapshot = try await fixture.repository.snapshot()
        let finished = await platform.finishedTransactionIDs()
        XCTAssertEqual(snapshot.coinBalances.confirmed, pack.coins)
        XCTAssertEqual(snapshot.coinBalances.pending, 0)
        XCTAssertEqual(finished, [transaction.transactionID])
    }

    func testConflictRefreshesAndRetriesBoundedMutation() async throws {
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let base = InMemoryCloudSyncTransport(
            accountState: .available(cloudAccountID)
        )
        let cloud = ConflictOnceTransport(base: base)
        let fixture = try await makeFixture(
            directory: directory,
            cloud: cloud,
            sessionNonce: uuid(30),
            newProfileID: uuid(31)
        )
        let request = storeDeliveryRequest(
            transactionID: 3_001,
            context: fixture.context,
            pack: EconomyConfiguration.coinPacks[0]
        )

        let acknowledgement = try await fixture.coordinator.deliver(request)
        let commitAttempts = await cloud.commitAttemptCount()

        XCTAssertEqual(acknowledgement.status, .committed)
        XCTAssertEqual(commitAttempts, 2)
        let snapshot = try await fixture.repository.snapshot()
        XCTAssertEqual(snapshot.coinBalances.confirmed, request.pack.coins)
    }

    func testConflictRetryLimitLeavesLocalEconomyUnchanged() async throws {
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let base = InMemoryCloudSyncTransport(
            accountState: .available(cloudAccountID)
        )
        let cloud = AlwaysConflictingTransport(base: base)
        let fixture = try await makeFixture(
            directory: directory,
            cloud: cloud,
            sessionNonce: uuid(40),
            newProfileID: uuid(41),
            conflictRetryLimit: 2
        )
        let request = storeDeliveryRequest(
            transactionID: 4_001,
            context: fixture.context,
            pack: EconomyConfiguration.coinPacks[0]
        )

        do {
            _ = try await fixture.coordinator.deliver(request)
            XCTFail("The bounded conflict retry must eventually stop")
        } catch {
            XCTAssertEqual(
                error as? DurableEconomyCoordinatorError,
                .conflictRetryLimitReached
            )
        }
        let commitAttempts = await cloud.commitAttemptCount()
        XCTAssertEqual(commitAttempts, 3)
        let snapshot = try await fixture.repository.snapshot()
        XCTAssertEqual(snapshot.coinBalances.confirmed, 0)
        XCTAssertNil(snapshot.ledger[request.ledgerEntry.id])
    }

    func testSupersededCommittedReceiptForcesFreshReadAndNeverRetriesMutation() async throws {
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let base = InMemoryCloudSyncTransport(
            accountState: .available(cloudAccountID)
        )
        let cloud = SupersededCommittedReceiptTransport(
            base: base,
            recordID: economyRecordID
        )
        let fixture = try await makeFixture(
            directory: directory,
            cloud: cloud,
            sessionNonce: uuid(50),
            newProfileID: uuid(51)
        )
        let settlement = try await settleRun(
            index: 50,
            repository: fixture.repository,
            session: fixture.snapshot.session
        )
        let entryIDs = Set(
            [
                settlement.outcome.gameplayRewardEntryID,
                settlement.outcome.signingBonusEntryID,
            ].compactMap { $0 }
        )

        let result = try await fixture.coordinator.confirmPendingCredits(
            entryIDs,
            session: fixture.snapshot.session
        )
        let commitAttempts = await cloud.coordinatorCommitAttemptCount()

        XCTAssertEqual(result.cloudReceipt.status, .committedThenRefreshed)
        XCTAssertEqual(commitAttempts, 1)
        XCTAssertEqual(result.snapshot.coinBalances.confirmed, 290)
        XCTAssertEqual(result.snapshot.coinBalances.pending, 0)
    }

    func testAccountSwitchRejectsStaleCallbackBeforeMutation() async throws {
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let base = InMemoryCloudSyncTransport(
            accountState: .available(cloudAccountID)
        )
        let fixture = try await makeFixture(
            directory: directory,
            cloud: base,
            sessionNonce: uuid(60),
            newProfileID: uuid(61)
        )
        let switchedBinding = DurableAccountBinding(
            accountKey: ServiceAccountKey("different-private-account"),
            profileID: fixture.snapshot.player.profileID
        )
        let switchedStoreSession = StoreActiveSession(
            binding: StoreAccountBinding(
                account: switchedBinding,
                appAccountToken: uuid(62)
            ),
            nonce: fixture.snapshot.session.nonce
        )
        let switchedContext = try DurableEconomySessionContext(
            cloudAccountID: CloudAccountID("different-cloud-account"),
            accountBinding: switchedBinding,
            profileSession: fixture.snapshot.session,
            storeSession: switchedStoreSession
        )
        await fixture.authority.activate(switchedContext)
        let request = storeDeliveryRequest(
            transactionID: 6_001,
            context: fixture.context,
            pack: EconomyConfiguration.coinPacks[0]
        )

        do {
            _ = try await fixture.coordinator.deliver(request)
            XCTFail("A callback captured by the old account must be rejected")
        } catch {
            XCTAssertEqual(error as? DurableEconomyCoordinatorError, .staleSession)
        }
        let records = await base.allRecords(for: cloudAccountID)
        let snapshot = try await fixture.repository.snapshot()
        XCTAssertTrue(records.isEmpty)
        XCTAssertEqual(snapshot.coinBalances.confirmed, 0)
    }

    func testAccountInvalidatedAfterCloudCommitDefersLocalAckUntilSafeRetry() async throws {
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let base = InMemoryCloudSyncTransport(
            accountState: .available(cloudAccountID)
        )
        let repository = makeRepository(
            directory: directory,
            sessionNonce: uuid(70)
        )
        let snapshot = try await repository.load(
            at: baseDate,
            newProfileID: uuid(71)
        )
        let context = try makeContext(snapshot: snapshot)
        let authority = DurableEconomySessionAuthority(context: context)
        let cloud = InvalidateAuthorityAfterCommitTransport(
            base: base,
            authority: authority
        )
        let coordinator = try makeCoordinator(
            context: context,
            authority: authority,
            repository: repository,
            cloud: cloud
        )
        let request = storeDeliveryRequest(
            transactionID: 7_001,
            context: context,
            pack: EconomyConfiguration.coinPacks[0]
        )

        do {
            _ = try await coordinator.deliver(request)
            XCTFail("An account invalidated during suspension cannot receive local credit")
        } catch {
            XCTAssertEqual(error as? DurableEconomyCoordinatorError, .noCurrentSession)
        }
        let beforeRetry = try await repository.snapshot()
        XCTAssertEqual(beforeRetry.coinBalances.confirmed, 0)
        XCTAssertNil(beforeRetry.ledger[request.ledgerEntry.id])

        await authority.activate(context)
        let recovered = try await coordinator.deliver(request)
        XCTAssertEqual(recovered.status, .alreadyCommitted)
        let afterRetry = try await repository.snapshot()
        XCTAssertEqual(afterRetry.coinBalances.confirmed, request.pack.coins)
    }

    func testEconomyRevisionChangeAfterCloudCommitRejectsStaleLocalReceipt() async throws {
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let base = InMemoryCloudSyncTransport(
            accountState: .available(cloudAccountID)
        )
        let repository = makeRepository(
            directory: directory,
            sessionNonce: uuid(80)
        )
        let snapshot = try await repository.load(
            at: baseDate,
            newProfileID: uuid(81)
        )
        let context = try makeContext(snapshot: snapshot)
        let authority = DurableEconomySessionAuthority(context: context)
        let cloud = MutateRepositoryAfterCommitTransport(
            base: base,
            repository: repository,
            run: makeRun(index: 80),
            session: snapshot.session,
            recordedAt: baseDate.addingTimeInterval(8_000)
        )
        let coordinator = try makeCoordinator(
            context: context,
            authority: authority,
            repository: repository,
            cloud: cloud
        )
        let request = storeDeliveryRequest(
            transactionID: 8_001,
            context: context,
            pack: EconomyConfiguration.coinPacks[0]
        )

        do {
            _ = try await coordinator.deliver(request)
            XCTFail("The cloud receipt captured the previous economy revision")
        } catch {
            XCTAssertEqual(
                error as? DurableEconomyCoordinatorError,
                .economyRevisionChanged(expected: 0, actual: 1)
            )
        }
        let stale = try await repository.snapshot()
        XCTAssertNil(stale.ledger[request.ledgerEntry.id])
        XCTAssertEqual(stale.coinBalances.confirmed, 0)
        XCTAssertGreaterThan(stale.coinBalances.pending, 0)

        let recovered = try await coordinator.deliver(request)
        XCTAssertEqual(recovered.status, .alreadyCommitted)
        let final = try await repository.snapshot()
        XCTAssertEqual(final.coinBalances.confirmed, request.pack.coins)
        XCTAssertGreaterThan(final.coinBalances.pending, 0)
    }

    func testUnlockRejectsInsufficientConfirmedBalanceWithoutCloudWrite() async throws {
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let cloud = InMemoryCloudSyncTransport(
            accountState: .available(cloudAccountID)
        )
        let fixture = try await makeFixture(
            directory: directory,
            cloud: cloud,
            sessionNonce: uuid(90),
            newProfileID: uuid(91)
        )
        let item = try XCTUnwrap(
            LaunchCatalog.approved.unlockableItems.first(where: {
                if case .team = $0.kind { return true }
                return false
            })
        )

        do {
            _ = try await fixture.coordinator.unlock(
                itemID: item.id,
                requestOperationID: OperationID("insufficient-balance-attempt"),
                session: fixture.snapshot.session
            )
            XCTFail("Pending or absent coins cannot fund a catalog debit")
        } catch {
            XCTAssertEqual(
                error as? LocalPlayerRepositoryError,
                .insufficientConfirmedCoins(required: 1_500, available: 0)
            )
        }
        let records = await cloud.allRecords(for: cloudAccountID)
        XCTAssertTrue(records.isEmpty)
    }

    func testLockedTeamAlternatePrerequisiteFailsBeforeCloudMutation() async throws {
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let base = InMemoryCloudSyncTransport(
            accountState: .available(cloudAccountID)
        )
        let cloud = CommitCountingTransport(base: base)
        let fixture = try await makeFixture(
            directory: directory,
            cloud: cloud,
            sessionNonce: uuid(92),
            newProfileID: uuid(93)
        )
        let pack = EconomyConfiguration.coinPacks[0]
        _ = try await fixture.coordinator.deliver(
            storeDeliveryRequest(
                transactionID: 9_201,
                context: fixture.context,
                pack: pack
            )
        )
        let team = lockedTeam()
        let alternateItem = alternateJerseyItem(for: team)
        let recordsBefore = await base.allRecords(for: cloudAccountID)
        let commitsBefore = await cloud.commitCallCount()

        do {
            _ = try await fixture.coordinator.unlock(
                itemID: alternateItem.id,
                requestOperationID: OperationID("locked-team-alternate-prerequisite"),
                session: fixture.snapshot.session
            )
            XCTFail("A locked team's alternate cannot commit before the team unlock")
        } catch {
            XCTAssertEqual(
                error as? LocalPlayerRepositoryError,
                .inventory(.alternateRequiresTeam(teamID: team.id))
            )
        }

        let recordsAfter = await base.allRecords(for: cloudAccountID)
        let commitsAfter = await cloud.commitCallCount()
        let snapshot = try await fixture.repository.snapshot()
        XCTAssertEqual(commitsAfter, commitsBefore)
        XCTAssertEqual(recordsAfter, recordsBefore)
        XCTAssertEqual(snapshot.coinBalances.confirmed, pack.coins)
        XCTAssertFalse(
            snapshot.player.inventory.ownedJerseyIDs.contains(team.alternateJersey.id)
        )
        XCTAssertNil(snapshot.ledger[CoinLedgerID.catalogUnlock(itemID: alternateItem.id)])
    }

    func testAlreadyOwnedAlternateRejectsCloudHeadMissingLockedTeamUnlock() async throws {
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let cloud = InMemoryCloudSyncTransport(
            accountState: .available(cloudAccountID)
        )
        let fixture = try await makeFixture(
            directory: directory,
            cloud: cloud,
            sessionNonce: uuid(94),
            newProfileID: uuid(95)
        )
        _ = try await fixture.coordinator.deliver(
            storeDeliveryRequest(
                transactionID: 9_401,
                context: fixture.context,
                pack: EconomyConfiguration.coinPacks[2]
            )
        )
        let team = lockedTeam()
        let teamItem = teamUnlockItem(for: team)
        let alternateItem = alternateJerseyItem(for: team)
        _ = try await fixture.coordinator.unlock(
            itemID: teamItem.id,
            requestOperationID: OperationID("unlock-locked-team"),
            session: fixture.snapshot.session
        )
        _ = try await fixture.coordinator.unlock(
            itemID: alternateItem.id,
            requestOperationID: OperationID("unlock-locked-team-alternate"),
            session: fixture.snapshot.session
        )
        let validRetry = try await fixture.coordinator.unlock(
            itemID: alternateItem.id,
            requestOperationID: OperationID("retry-valid-locked-team-alternate"),
            session: fixture.snapshot.session
        )
        XCTAssertTrue(validRetry.outcome.wasAlreadyUnlocked)

        let validRecords = await cloud.allRecords(for: cloudAccountID)
        let validRecord = try XCTUnwrap(
            validRecords.first(where: { $0.id == economyRecordID })
        )
        let tamperedWrite = try cloudWriteRemovingUnlock(
            teamItem.id,
            from: validRecord
        )
        _ = try await cloud.commitAtomically(
            CloudAtomicWriteRequest(
                accountID: cloudAccountID,
                operationID: OperationID("test-remove-locked-team-unlock"),
                writes: [tamperedWrite]
            )
        )
        let tamperedRecords = await cloud.allRecords(for: cloudAccountID)

        do {
            _ = try await fixture.coordinator.unlock(
                itemID: alternateItem.id,
                requestOperationID: OperationID("retry-invalid-locked-team-alternate"),
                session: fixture.snapshot.session
            )
            XCTFail("Idempotent unlock cannot accept an impossible cloud inventory")
        } catch {
            XCTAssertEqual(
                error as? DurableEconomyCoordinatorError,
                .malformedCloudRecord
            )
        }
        let recordsAfterRejectedRetry = await cloud.allRecords(for: cloudAccountID)
        XCTAssertEqual(recordsAfterRejectedRetry, tamperedRecords)
    }

    func testCatalogDebitAndOwnershipAreExactlyOnceAcrossRetryAndRelaunch() async throws {
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let cloud = InMemoryCloudSyncTransport(
            accountState: .available(cloudAccountID)
        )
        let first = try await makeFixture(
            directory: directory,
            cloud: cloud,
            sessionNonce: uuid(100),
            newProfileID: uuid(101)
        )
        let pack = EconomyConfiguration.coinPacks[1]
        _ = try await first.coordinator.deliver(
            storeDeliveryRequest(
                transactionID: 10_001,
                context: first.context,
                pack: pack
            )
        )
        let item = alternateJerseyItem()
        XCTAssertTrue(
            LaunchCatalog.approved.team(id: LaunchTeamID.novaCityComets)!.initiallyOwned
        )

        let unlocked = try await first.coordinator.unlock(
            itemID: item.id,
            requestOperationID: OperationID("unlock-nova-alternate"),
            session: first.snapshot.session
        )
        let retry = try await first.coordinator.unlock(
            itemID: item.id,
            requestOperationID: OperationID("unlock-nova-alternate-retry"),
            session: first.snapshot.session
        )

        XCTAssertFalse(unlocked.outcome.wasAlreadyUnlocked)
        XCTAssertTrue(retry.outcome.wasAlreadyUnlocked)
        XCTAssertEqual(retry.cloudReceipt.status, .alreadyCommitted)
        XCTAssertEqual(retry.outcome.confirmedBalanceAfter, pack.coins - 500)
        let firstSnapshot = try await first.repository.snapshot()
        XCTAssertTrue(firstSnapshot.player.inventory.ownedJerseyIDs.contains(alternateJerseyID()))
        XCTAssertEqual(firstSnapshot.coinBalances.confirmed, pack.coins - 500)

        let relaunched = try await makeFixture(
            directory: directory,
            cloud: cloud,
            sessionNonce: uuid(102),
            newProfileID: uuid(999)
        )
        let relaunchedRetry = try await relaunched.coordinator.unlock(
            itemID: item.id,
            requestOperationID: OperationID("unlock-nova-alternate-after-relaunch"),
            session: relaunched.snapshot.session
        )
        XCTAssertTrue(relaunchedRetry.outcome.wasAlreadyUnlocked)
        XCTAssertEqual(relaunchedRetry.outcome.confirmedBalanceAfter, pack.coins - 500)
        XCTAssertEqual(relaunchedRetry.cloudReceipt.status, .alreadyCommitted)
    }

    func testCatalogUnlockRecoversCloudCommitWithChangingClockBeforeLocalApply() async throws {
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let base = InMemoryCloudSyncTransport(
            accountState: .available(cloudAccountID)
        )
        let fixture = try await makeFixture(
            directory: directory,
            cloud: base,
            sessionNonce: uuid(103),
            newProfileID: uuid(104)
        )
        let pack = EconomyConfiguration.coinPacks[1]
        _ = try await fixture.coordinator.deliver(
            storeDeliveryRequest(
                transactionID: 10_301,
                context: fixture.context,
                pack: pack
            )
        )

        let cloud = CommitThenFailOnceTransport(base: base)
        let firstUnlockTimestamp = baseDate.addingTimeInterval(50_000)
        let clock = DurableEconomyChangingClock(
            initial: firstUnlockTimestamp,
            step: 3_600
        )
        let coordinator = DurableEconomyCoordinator(
            context: fixture.context,
            sessionAuthority: fixture.authority,
            repository: fixture.repository,
            cloud: cloud,
            configuration: try DurableEconomyCloudConfiguration(
                recordID: economyRecordID,
                recordType: "TestEconomyHead",
                payloadFieldName: "economyPayload"
            ),
            now: { clock.next() }
        )
        let item = alternateJerseyItem()
        let ledgerID = CoinLedgerID.catalogUnlock(itemID: item.id)

        do {
            _ = try await coordinator.unlock(
                itemID: item.id,
                requestOperationID: OperationID("unlock-response-lost"),
                session: fixture.snapshot.session
            )
            XCTFail("The first cloud response must be lost before local apply")
        } catch {
            XCTAssertEqual(error as? DurableEconomyTestTransportError, .responseLost)
        }
        let cloudCommittedLocalPending = try await fixture.repository.snapshot()
        XCTAssertFalse(
            cloudCommittedLocalPending.player.inventory.ownedJerseyIDs.contains(
                alternateJerseyID()
            )
        )
        XCTAssertNil(cloudCommittedLocalPending.ledger[ledgerID])
        XCTAssertEqual(cloudCommittedLocalPending.coinBalances.confirmed, pack.coins)

        let recovered = try await coordinator.unlock(
            itemID: item.id,
            requestOperationID: OperationID("unlock-response-lost-retry"),
            session: fixture.snapshot.session
        )
        let idempotent = try await coordinator.unlock(
            itemID: item.id,
            requestOperationID: OperationID("unlock-response-lost-idempotent"),
            session: fixture.snapshot.session
        )

        XCTAssertEqual(recovered.cloudReceipt.status, .alreadyCommitted)
        XCTAssertEqual(idempotent.cloudReceipt.status, .alreadyCommitted)
        XCTAssertEqual(
            recovered.cloudReceipt.operationID,
            idempotent.cloudReceipt.operationID
        )
        XCTAssertFalse(recovered.outcome.wasAlreadyUnlocked)
        XCTAssertTrue(idempotent.outcome.wasAlreadyUnlocked)
        let commitCalls = await cloud.commitCallCount()
        XCTAssertEqual(commitCalls, 1)
        let final = try await fixture.repository.snapshot()
        XCTAssertEqual(final.ledger[ledgerID]?.createdAt, firstUnlockTimestamp)
        XCTAssertEqual(final.coinBalances.confirmed, pack.coins - 500)
        XCTAssertTrue(
            final.player.inventory.ownedJerseyIDs.contains(alternateJerseyID())
        )
    }

    func testCatalogUnlockRejectsEveryMismatchedPreparedRequestBeforeCloudWrite() async throws {
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let base = InMemoryCloudSyncTransport(
            accountState: .available(cloudAccountID)
        )
        let cloud = CommitCountingTransport(base: base)
        let fixture = try await makeFixture(
            directory: directory,
            cloud: cloud,
            sessionNonce: uuid(105),
            newProfileID: uuid(106)
        )
        let pack = EconomyConfiguration.coinPacks[1]
        _ = try await fixture.coordinator.deliver(
            storeDeliveryRequest(
                transactionID: 10_501,
                context: fixture.context,
                pack: pack
            )
        )
        let item = alternateJerseyItem()
        let recordsBefore = await base.allRecords(for: cloudAccountID)
        let commitsBefore = await cloud.commitCallCount()

        for tampering in CatalogUnlockRequestTampering.allCases {
            let repository = TamperingCatalogUnlockRepository(
                base: fixture.repository,
                tampering: tampering
            )
            let coordinator = try makeCoordinator(
                context: fixture.context,
                authority: fixture.authority,
                repository: repository,
                cloud: cloud
            )
            do {
                _ = try await coordinator.unlock(
                    itemID: item.id,
                    requestOperationID: OperationID("malicious-\(tampering.rawValue)"),
                    session: fixture.snapshot.session
                )
                XCTFail("A \(tampering.rawValue) mismatch must be rejected")
            } catch {
                XCTAssertEqual(
                    error as? DurableEconomyCoordinatorError,
                    .invalidCatalogUnlockRequest,
                    "Unexpected result for \(tampering.rawValue)"
                )
            }
        }

        let commitsAfter = await cloud.commitCallCount()
        let recordsAfter = await base.allRecords(for: cloudAccountID)
        XCTAssertEqual(commitsAfter, commitsBefore)
        XCTAssertEqual(recordsAfter, recordsBefore)
        let final = try await fixture.repository.snapshot()
        XCTAssertEqual(final.coinBalances.confirmed, pack.coins)
        XCTAssertNil(final.ledger[CoinLedgerID.catalogUnlock(itemID: item.id)])
        XCTAssertFalse(
            final.player.inventory.ownedJerseyIDs.contains(alternateJerseyID())
        )
    }

    func testRewardedAdSeamCommitsVerifiedRecordAndConsumesOfferExactlyOnce() async throws {
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let cloud = InMemoryCloudSyncTransport(
            accountState: .available(cloudAccountID)
        )
        let fixture = try await makeFixture(
            directory: directory,
            cloud: cloud,
            sessionNonce: uuid(110),
            newProfileID: uuid(111)
        )
        for index in 110 ..< 115 {
            _ = try await settleRun(
                index: index,
                repository: fixture.repository,
                session: fixture.snapshot.session
            )
        }
        let eligible = try await fixture.repository.snapshot()
        let offerID = try XCTUnwrap(eligible.player.rewardedAdState.eligibleOfferID)
        let request = VerifiedRewardedAdDurableDeliveryRequest(
            session: eligible.session,
            offerID: offerID,
            providerTransactionID: AdProviderTransactionID("verified-ssv-transaction"),
            rewardedAt: baseDate.addingTimeInterval(20_000)
        )

        let first = try await fixture.coordinator.deliverVerifiedReward(request)
        let retry = try await fixture.coordinator.deliverVerifiedReward(request)

        XCTAssertFalse(first.outcome.wasAlreadySettled)
        XCTAssertTrue(retry.outcome.wasAlreadySettled)
        XCTAssertEqual(first.outcome.coins, 100)
        XCTAssertEqual(retry.cloudReceipt.status, .alreadyCommitted)
        let snapshot = try await fixture.repository.snapshot()
        XCTAssertEqual(snapshot.coinBalances.confirmed, 100)
        XCTAssertNil(snapshot.player.rewardedAdState.eligibleOfferID)
        XCTAssertGreaterThan(snapshot.coinBalances.pending, 0)
    }

    func testSimultaneousDistinctTransactionsRunFIFOAcrossSuspensionPoints() async throws {
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let base = InMemoryCloudSyncTransport(
            accountState: .available(cloudAccountID)
        )
        let cloud = BlockingFirstCommitTransport(base: base)
        let fixture = try await makeFixture(
            directory: directory,
            cloud: cloud,
            sessionNonce: uuid(120),
            newProfileID: uuid(121)
        )
        let firstRequest = storeDeliveryRequest(
            transactionID: 12_001,
            context: fixture.context,
            pack: EconomyConfiguration.coinPacks[0]
        )
        let secondRequest = storeDeliveryRequest(
            transactionID: 12_002,
            context: fixture.context,
            pack: EconomyConfiguration.coinPacks[1]
        )

        let firstTask = Task { try await fixture.coordinator.deliver(firstRequest) }
        await cloud.waitUntilFirstCommitStarts()
        let secondTask = Task { try await fixture.coordinator.deliver(secondRequest) }
        for _ in 0 ..< 20 { await Task.yield() }

        let commitsWhileFirstSuspended = await cloud.commitCallCount()
        XCTAssertEqual(commitsWhileFirstSuspended, 1)
        await cloud.releaseFirstCommit()

        let first = try await firstTask.value
        let second = try await secondTask.value
        XCTAssertEqual(first.status, .committed)
        XCTAssertEqual(second.status, .committed)
        let final = try await fixture.repository.snapshot()
        XCTAssertEqual(
            final.coinBalances.confirmed,
            firstRequest.pack.coins + secondRequest.pack.coins
        )
        XCTAssertEqual(final.ledger[firstRequest.ledgerEntry.id], firstRequest.ledgerEntry)
        XCTAssertEqual(final.ledger[secondRequest.ledgerEntry.id], secondRequest.ledgerEntry)
        let finalCommitCount = await cloud.commitCallCount()
        XCTAssertEqual(finalCommitCount, 2)
    }

    func testBoundedHeadUsesImmutableMarkersForOldTransactionReplay() async throws {
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let cloud = InMemoryCloudSyncTransport(
            accountState: .available(cloudAccountID)
        )
        let fixture = try await makeFixture(
            directory: directory,
            cloud: cloud,
            sessionNonce: uuid(130),
            newProfileID: uuid(131)
        )
        let pack = EconomyConfiguration.coinPacks[0]
        let firstRequest = storeDeliveryRequest(
            transactionID: 13_000,
            context: fixture.context,
            pack: pack
        )
        _ = try await fixture.coordinator.deliver(firstRequest)
        let firstHead = try headRecord(
            in: await cloud.allRecords(for: cloudAccountID)
        )
        let firstPayloadSize = try headPayload(from: firstHead).count

        for offset in 1 ..< 64 {
            _ = try await fixture.coordinator.deliver(
                storeDeliveryRequest(
                    transactionID: 13_000 + UInt64(offset),
                    context: fixture.context,
                    pack: pack
                )
            )
        }

        let recordsBeforeReplay = await cloud.allRecords(for: cloudAccountID)
        let headBeforeReplay = try headRecord(in: recordsBeforeReplay)
        let payload = try headPayload(from: headBeforeReplay)
        let state = try headJSONObject(from: headBeforeReplay)
        let accumulator = try XCTUnwrap(
            state["ledgerAccumulator"] as? [String: Any]
        )
        XCTAssertEqual((accumulator["entryCount"] as? NSNumber)?.uint64Value, 64)
        XCTAssertEqual(
            (accumulator["confirmedBalance"] as? NSNumber)?.int64Value,
            64 * pack.coins
        )
        XCTAssertNil(state["ledgerRecords"])
        XCTAssertNil(state["rewardRedemptions"])
        XCTAssertLessThan(payload.count, 1_024)
        XCTAssertLessThanOrEqual(payload.count, firstPayloadSize + 48)
        XCTAssertEqual(recordsBeforeReplay.count, 65)
        XCTAssertFalse(String(decoding: payload, as: UTF8.self).contains("13000"))

        let replay = try await fixture.coordinator.deliver(firstRequest)
        XCTAssertEqual(replay.status, .alreadyCommitted)
        let recordsAfterReplay = await cloud.allRecords(for: cloudAccountID)
        let headAfterReplay = try headRecord(in: recordsAfterReplay)
        XCTAssertEqual(headAfterReplay, headBeforeReplay)
        XCTAssertEqual(recordsAfterReplay.count, recordsBeforeReplay.count)
        let final = try await fixture.repository.snapshot()
        XCTAssertEqual(final.coinBalances.confirmed, 64 * pack.coins)
        XCTAssertEqual(final.ledger.count, 64)
    }

    func testHeadAccumulatorCountBalanceAndDigestEachDetectDivergence() async throws {
        for component in ["entryCount", "confirmedBalance", "digest"] {
            let directory = makeTemporaryDirectory()
            defer { removeTemporaryDirectory(directory) }
            let cloud = InMemoryCloudSyncTransport(
                accountState: .available(cloudAccountID)
            )
            let fixture = try await makeFixture(
                directory: directory,
                cloud: cloud,
                sessionNonce: uuid(140),
                newProfileID: uuid(141)
            )
            _ = try await fixture.coordinator.deliver(
                storeDeliveryRequest(
                    transactionID: 14_001,
                    context: fixture.context,
                    pack: EconomyConfiguration.coinPacks[0]
                )
            )
            let head = try headRecord(in: await cloud.allRecords(for: cloudAccountID))
            let tampered = try cloudWriteTamperingAccumulator(
                component,
                in: head
            )
            _ = try await cloud.commitAtomically(
                CloudAtomicWriteRequest(
                    accountID: cloudAccountID,
                    operationID: OperationID("tamper-accumulator-\(component)"),
                    writes: [tampered]
                )
            )

            do {
                _ = try await fixture.coordinator.deliver(
                    storeDeliveryRequest(
                        transactionID: 14_002,
                        context: fixture.context,
                        pack: EconomyConfiguration.coinPacks[0]
                    )
                )
                XCTFail("A mismatched \(component) must reject the cloud head")
            } catch {
                XCTAssertEqual(
                    error as? DurableEconomyCoordinatorError,
                    .cloudStateDiverged
                )
            }
        }
    }

    func testImmutableRewardOfferMarkerRejectsDifferentProviderTransaction() async throws {
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let cloud = InMemoryCloudSyncTransport(
            accountState: .available(cloudAccountID)
        )
        let fixture = try await makeFixture(
            directory: directory,
            cloud: cloud,
            sessionNonce: uuid(150),
            newProfileID: uuid(151)
        )
        for index in 150 ..< 155 {
            _ = try await settleRun(
                index: index,
                repository: fixture.repository,
                session: fixture.snapshot.session
            )
        }
        let eligible = try await fixture.repository.snapshot()
        let offerID = try XCTUnwrap(eligible.player.rewardedAdState.eligibleOfferID)

        // A second in-memory repository models a stale device that still sees
        // the same eligible offer after the first device has redeemed it.
        let staleRepository = makeRepository(
            directory: directory,
            sessionNonce: eligible.session.nonce
        )
        let staleSnapshot = try await staleRepository.load(
            at: baseDate,
            newProfileID: uuid(999)
        )
        let staleContext = try makeContext(snapshot: staleSnapshot)
        let staleAuthority = DurableEconomySessionAuthority(context: staleContext)
        let staleCoordinator = try makeCoordinator(
            context: staleContext,
            authority: staleAuthority,
            repository: staleRepository,
            cloud: cloud
        )

        _ = try await fixture.coordinator.deliverVerifiedReward(
            VerifiedRewardedAdDurableDeliveryRequest(
                session: eligible.session,
                offerID: offerID,
                providerTransactionID: AdProviderTransactionID("provider-a"),
                rewardedAt: baseDate.addingTimeInterval(40_000)
            )
        )
        let recordsBeforeCollision = await cloud.allRecords(for: cloudAccountID)

        do {
            _ = try await staleCoordinator.deliverVerifiedReward(
                VerifiedRewardedAdDurableDeliveryRequest(
                    session: staleSnapshot.session,
                    offerID: offerID,
                    providerTransactionID: AdProviderTransactionID("provider-b"),
                    rewardedAt: baseDate.addingTimeInterval(40_001)
                )
            )
            XCTFail("One reward offer cannot bind to two provider transactions")
        } catch {
            XCTAssertEqual(
                error as? DurableEconomyCoordinatorError,
                .cloudRewardCollision(offerID)
            )
        }
        let recordsAfterCollision = await cloud.allRecords(for: cloudAccountID)
        XCTAssertEqual(recordsAfterCollision, recordsBeforeCollision)
        let staleAfter = try await staleRepository.snapshot()
        XCTAssertEqual(staleAfter.coinBalances.confirmed, 0)
        XCTAssertEqual(staleAfter.player.rewardedAdState.eligibleOfferID, offerID)
    }
}

private extension DurableEconomyCoordinatorTests {
    struct Fixture {
        let repository: LocalPlayerProfileRepository
        let snapshot: LocalPlayerProfileSnapshot
        let context: DurableEconomySessionContext
        let authority: DurableEconomySessionAuthority
        let coordinator: DurableEconomyCoordinator
    }

    var cloudAccountID: CloudAccountID {
        CloudAccountID("test-private-cloud-account")
    }

    var economyRecordID: CloudRecordID {
        CloudRecordID("test-economy-head")
    }

    func makeFixture(
        directory: URL,
        cloud: any CloudSyncTransport,
        sessionNonce: UUID,
        newProfileID: UUID,
        conflictRetryLimit: Int = 3
    ) async throws -> Fixture {
        let repository = makeRepository(
            directory: directory,
            sessionNonce: sessionNonce
        )
        let snapshot = try await repository.load(
            at: baseDate,
            newProfileID: newProfileID
        )
        let context = try makeContext(snapshot: snapshot)
        let authority = DurableEconomySessionAuthority(context: context)
        let coordinator = try makeCoordinator(
            context: context,
            authority: authority,
            repository: repository,
            cloud: cloud,
            conflictRetryLimit: conflictRetryLimit
        )
        return Fixture(
            repository: repository,
            snapshot: snapshot,
            context: context,
            authority: authority,
            coordinator: coordinator
        )
    }

    func makeCoordinator(
        context: DurableEconomySessionContext,
        authority: DurableEconomySessionAuthority,
        repository: any DurableEconomyLocalPersisting,
        cloud: any CloudSyncTransport,
        conflictRetryLimit: Int = 3
    ) throws -> DurableEconomyCoordinator {
        DurableEconomyCoordinator(
            context: context,
            sessionAuthority: authority,
            repository: repository,
            cloud: cloud,
            configuration: try DurableEconomyCloudConfiguration(
                recordID: economyRecordID,
                recordType: "TestEconomyHead",
                payloadFieldName: "economyPayload",
                conflictRetryLimit: conflictRetryLimit
            ),
            now: { [baseDate] in baseDate.addingTimeInterval(30_000) }
        )
    }

    func makeRepository(
        directory: URL,
        sessionNonce: UUID
    ) -> LocalPlayerProfileRepository {
        LocalPlayerProfileRepository(
            directoryURL: directory,
            deviceID: "durable-economy-test-device",
            accountIdentity: PlayerAccountIdentity("test-player-account"),
            sessionNonce: sessionNonce,
            economyMutationPolicy: .requireDurablePrivateCloud
        )
    }

    func makeContext(
        snapshot: LocalPlayerProfileSnapshot
    ) throws -> DurableEconomySessionContext {
        let accountBinding = DurableAccountBinding(
            accountKey: ServiceAccountKey("test-service-account"),
            profileID: snapshot.player.profileID
        )
        return try DurableEconomySessionContext(
            cloudAccountID: cloudAccountID,
            accountBinding: accountBinding,
            profileSession: snapshot.session,
            storeSession: StoreActiveSession(
                binding: StoreAccountBinding(
                    account: accountBinding,
                    appAccountToken: uuid(900)
                ),
                nonce: snapshot.session.nonce
            )
        )
    }

    func storeDeliveryRequest(
        transactionID: UInt64,
        context: DurableEconomySessionContext,
        pack: CoinPackDescriptor
    ) -> StoreKit2DurableDeliveryRequest {
        let entry = CoinLedgerEntry(
            id: CoinLedgerID.storeKit(transactionID: transactionID),
            delta: pack.coins,
            reason: .storeKit(transactionID: transactionID, packID: pack.id),
            createdAt: baseDate.addingTimeInterval(Double(transactionID))
        )
        return StoreKit2DurableDeliveryRequest(
            session: context.storeSession,
            transaction: StoreTransactionEnvelope(
                transactionID: transactionID,
                packID: pack.id,
                appAccountToken: context.storeSession.binding.appAccountToken,
                verification: .verified
            ),
            pack: pack,
            ledgerEntry: entry
        )
    }

    func settleRun(
        index: Int,
        repository: LocalPlayerProfileRepository,
        session: ProfileSessionToken
    ) async throws -> RunSettlementResult {
        try await repository.settle(
            makeRun(index: index),
            session: session,
            recordedAt: baseDate.addingTimeInterval(Double(index * 100))
        )
    }

    func makeRun(index: Int) -> CompletedRun {
        let endedAt = baseDate.addingTimeInterval(Double(index * 100))
        let offense = LaunchCatalog.approved.team(id: LaunchTeamID.novaCityComets)!
        let defense = LaunchCatalog.approved.team(id: LaunchTeamID.highMesaHelions)!
        return CompletedRun(
            configuration: RunConfiguration(
                runID: RunID(uuid(index + 10_000)),
                randomSeed: UInt32(index),
                offenseTeamID: offense.id,
                offenseJerseyID: offense.primaryJersey.id,
                defenseTeamID: defense.id,
                defenseJerseyID: defense.primaryJersey.id,
                footballID: LaunchFootballID.standard,
                economyVersion: PersistedEconomyRulesV1.run.economyVersion,
                startedAt: endedAt.addingTimeInterval(-60)
            ),
            endedAt: endedAt,
            elapsedGameplayMilliseconds: 60_000,
            finishReason: .timerExpired,
            score: 30_000,
            statistics: RunStatisticsSnapshot(
                attempts: 10,
                completions: 4,
                touchdowns: 3,
                incompletions: 3,
                interceptions: 0,
                longestTouchdownStreak: 3
            ),
            completedLaneIDs: Set(LaneID.allCases.prefix(4)),
            bonusTouchdownCount: 1
        )
    }

    func alternateJerseyID() -> JerseyID {
        LaunchCatalog.approved
            .team(id: LaunchTeamID.novaCityComets)!.alternateJersey.id
    }

    func alternateJerseyItem() -> CatalogItemDescriptor {
        let jerseyID = alternateJerseyID()
        return LaunchCatalog.approved.unlockableItems.first {
            if case .alternateJersey(jerseyID) = $0.kind { return true }
            return false
        }!
    }

    func lockedTeam() -> TeamDescriptor {
        LaunchCatalog.approved.teams.first { !$0.initiallyOwned }!
    }

    func teamUnlockItem(for team: TeamDescriptor) -> CatalogItemDescriptor {
        LaunchCatalog.approved.unlockableItems.first { item in
            guard case let .team(teamID) = item.kind else { return false }
            return teamID == team.id
        }!
    }

    func alternateJerseyItem(for team: TeamDescriptor) -> CatalogItemDescriptor {
        LaunchCatalog.approved.unlockableItems.first { item in
            guard case let .alternateJersey(jerseyID) = item.kind else { return false }
            return jerseyID == team.alternateJersey.id
        }!
    }

    func cloudWriteRemovingUnlock(
        _ itemID: CatalogItemID,
        from record: CloudRecord
    ) throws -> CloudRecordWrite {
        let payloadFieldName = "economyPayload"
        guard let payload = record.fields[payloadFieldName],
              var state = try JSONSerialization.jsonObject(with: payload)
                as? [String: Any],
              let unlockedItems = state["unlockedItemIDs"] as? [Any] else {
            throw DurableEconomyTestFixtureError.malformedCloudPayload
        }

        let filteredItems = unlockedItems.filter {
            rawIdentifier($0) != itemID.rawValue
        }
        guard filteredItems.count == unlockedItems.count - 1 else {
            throw DurableEconomyTestFixtureError.malformedCloudPayload
        }

        state["unlockedItemIDs"] = filteredItems
        var fields = record.fields
        fields[payloadFieldName] = try JSONSerialization.data(
            withJSONObject: state,
            options: [.sortedKeys]
        )
        return CloudRecordWrite(
            id: record.id,
            recordType: record.recordType,
            fields: fields,
            precondition: .changeTag(record.changeTag)
        )
    }

    func headRecord(in records: [CloudRecord]) throws -> CloudRecord {
        try XCTUnwrap(records.first(where: { $0.id == economyRecordID }))
    }

    func headPayload(from record: CloudRecord) throws -> Data {
        try XCTUnwrap(record.fields["economyPayload"])
    }

    func headJSONObject(from record: CloudRecord) throws -> [String: Any] {
        let value = try JSONSerialization.jsonObject(with: headPayload(from: record))
        guard let object = value as? [String: Any] else {
            throw DurableEconomyTestFixtureError.malformedCloudPayload
        }
        return object
    }

    func cloudWriteTamperingAccumulator(
        _ component: String,
        in record: CloudRecord
    ) throws -> CloudRecordWrite {
        var state = try headJSONObject(from: record)
        guard var accumulator = state["ledgerAccumulator"] as? [String: Any] else {
            throw DurableEconomyTestFixtureError.malformedCloudPayload
        }
        switch component {
        case "entryCount":
            guard let value = accumulator[component] as? NSNumber else {
                throw DurableEconomyTestFixtureError.malformedCloudPayload
            }
            accumulator[component] = NSNumber(value: value.uint64Value + 1)
        case "confirmedBalance":
            guard let value = accumulator[component] as? NSNumber else {
                throw DurableEconomyTestFixtureError.malformedCloudPayload
            }
            accumulator[component] = NSNumber(value: value.int64Value + 1)
        case "digest":
            accumulator[component] = Data(repeating: 0xA5, count: 32)
                .base64EncodedString()
        default:
            throw DurableEconomyTestFixtureError.malformedCloudPayload
        }
        state["ledgerAccumulator"] = accumulator
        var fields = record.fields
        fields["economyPayload"] = try JSONSerialization.data(
            withJSONObject: state,
            options: [.sortedKeys]
        )
        return CloudRecordWrite(
            id: record.id,
            recordType: record.recordType,
            fields: fields,
            precondition: .changeTag(record.changeTag)
        )
    }

    func rawIdentifier(_ encoded: Any) -> String? {
        if let value = encoded as? String { return value }
        return (encoded as? [String: Any])?["rawValue"] as? String
    }

    func makeTemporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "PocketVectorDurableEconomyTests-\(UUID().uuidString)",
            isDirectory: true
        )
    }

    func removeTemporaryDirectory(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }

    func uuid(_ value: Int) -> UUID {
        UUID(
            uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", value))"
        )!
    }
}

private enum DurableEconomyTestTransportError: Error, Equatable, Sendable {
    case responseLost
}

private enum DurableEconomyTestFixtureError: Error, Equatable, Sendable {
    case malformedCloudPayload
}

private final class DurableEconomyChangingClock: @unchecked Sendable {
    private let lock = NSLock()
    private let initial: Date
    private let step: TimeInterval
    private var invocationCount = 0

    init(initial: Date, step: TimeInterval) {
        self.initial = initial
        self.step = step
    }

    func next() -> Date {
        lock.lock()
        defer { lock.unlock() }
        let result = initial.addingTimeInterval(Double(invocationCount) * step)
        invocationCount += 1
        return result
    }
}

private enum CatalogUnlockRequestTampering: String, CaseIterable, Sendable {
    case operation
    case session
    case item
    case ledger
    case price
    case revision
    case balance

    func apply(to request: DurableCatalogUnlockRequest) -> DurableCatalogUnlockRequest {
        let operationID = self == .operation
            ? OperationID("forged-request-operation")
            : request.operationID
        let session = self == .session
            ? ProfileSessionToken(
                accountIdentity: request.session.accountIdentity,
                nonce: UUID(uuidString: "ffffffff-ffff-ffff-ffff-ffffffffffff")!,
                profileID: request.session.profileID
            )
            : request.session
        let itemID = self == .item
            ? CatalogItemID("forged-catalog-item")
            : request.itemID
        let ledgerEntryID = self == .ledger
            ? LedgerEntryID("forged-catalog-ledger")
            : request.ledgerEntryID
        let price = self == .price ? request.price + 1 : request.price
        let expectedEconomyRevision = self == .revision
            ? request.expectedEconomyRevision + 1
            : request.expectedEconomyRevision
        let confirmedBalanceBefore = self == .balance
            ? request.confirmedBalanceBefore + 1
            : request.confirmedBalanceBefore
        return DurableCatalogUnlockRequest(
            operationID: operationID,
            session: session,
            itemID: itemID,
            ledgerEntryID: ledgerEntryID,
            price: price,
            expectedEconomyRevision: expectedEconomyRevision,
            confirmedBalanceBefore: confirmedBalanceBefore
        )
    }
}

private struct TamperingCatalogUnlockRepository: DurableEconomyLocalPersisting {
    let base: LocalPlayerProfileRepository
    let tampering: CatalogUnlockRequestTampering

    func durableEconomySnapshot() async throws -> LocalPlayerProfileSnapshot {
        try await base.snapshot()
    }

    func durableConfirmPendingCredits(
        _ entryIDs: Set<LedgerEntryID>,
        session: ProfileSessionToken,
        confirmation: DurableEconomyConfirmation,
        savedAt: Date
    ) async throws -> LocalPlayerProfileSnapshot {
        try await base.confirmPendingCredits(
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
        try await base.recordConfirmedCredit(
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
        let request = try await base.prepareUnlock(
            itemID: itemID,
            operationID: operationID,
            session: session
        )
        return tampering.apply(to: request)
    }

    func durableApplyUnlock(
        using receipt: DurableCatalogUnlockReceipt,
        session: ProfileSessionToken,
        at date: Date
    ) async throws -> CatalogUnlockOutcome {
        try await base.unlock(using: receipt, session: session, at: date)
    }

    func durableSettleRewardedAd(
        using receipt: DurableRewardedAdReceipt,
        session: ProfileSessionToken,
        savedAt: Date
    ) async throws -> RewardedAdSettlementOutcome {
        try await base.settleRewardedAd(
            using: receipt,
            session: session,
            savedAt: savedAt
        )
    }
}

private actor BlockingFirstCommitTransport: CloudSyncTransport {
    let base: InMemoryCloudSyncTransport
    private var commits = 0
    private var firstCommitStarted = false
    private var firstCommitReleased = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    init(base: InMemoryCloudSyncTransport) {
        self.base = base
    }

    func accountState() async -> CloudAccountState {
        await base.accountState()
    }

    func records(
        accountID: CloudAccountID,
        ids: [CloudRecordID]
    ) async throws -> [CloudRecord] {
        try await base.records(accountID: accountID, ids: ids)
    }

    func commitAtomically(
        _ request: CloudAtomicWriteRequest
    ) async throws -> CloudAtomicWriteReceipt {
        commits += 1
        if !firstCommitStarted {
            firstCommitStarted = true
            let waiters = startWaiters
            startWaiters.removeAll()
            for waiter in waiters { waiter.resume() }
            if !firstCommitReleased {
                await withCheckedContinuation { continuation in
                    releaseWaiter = continuation
                }
            }
        }
        return try await base.commitAtomically(request)
    }

    func waitUntilFirstCommitStarts() async {
        guard !firstCommitStarted else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func releaseFirstCommit() {
        firstCommitReleased = true
        releaseWaiter?.resume()
        releaseWaiter = nil
    }

    func commitCallCount() -> Int {
        commits
    }
}

private actor CommitCountingTransport: CloudSyncTransport {
    let base: InMemoryCloudSyncTransport
    private var commits = 0

    init(base: InMemoryCloudSyncTransport) {
        self.base = base
    }

    func accountState() async -> CloudAccountState {
        await base.accountState()
    }

    func records(
        accountID: CloudAccountID,
        ids: [CloudRecordID]
    ) async throws -> [CloudRecord] {
        try await base.records(accountID: accountID, ids: ids)
    }

    func commitAtomically(
        _ request: CloudAtomicWriteRequest
    ) async throws -> CloudAtomicWriteReceipt {
        commits += 1
        return try await base.commitAtomically(request)
    }

    func commitCallCount() -> Int {
        commits
    }
}

private actor CommitThenFailOnceTransport: CloudSyncTransport {
    let base: InMemoryCloudSyncTransport
    private var shouldFail = true
    private var commits = 0

    init(base: InMemoryCloudSyncTransport) {
        self.base = base
    }

    func accountState() async -> CloudAccountState {
        await base.accountState()
    }

    func records(
        accountID: CloudAccountID,
        ids: [CloudRecordID]
    ) async throws -> [CloudRecord] {
        try await base.records(accountID: accountID, ids: ids)
    }

    func commitAtomically(
        _ request: CloudAtomicWriteRequest
    ) async throws -> CloudAtomicWriteReceipt {
        commits += 1
        let receipt = try await base.commitAtomically(request)
        if shouldFail {
            shouldFail = false
            throw DurableEconomyTestTransportError.responseLost
        }
        return receipt
    }

    func commitCallCount() -> Int {
        commits
    }
}

private actor ConflictOnceTransport: CloudSyncTransport {
    let base: InMemoryCloudSyncTransport
    private var attempts = 0

    init(base: InMemoryCloudSyncTransport) {
        self.base = base
    }

    func accountState() async -> CloudAccountState {
        await base.accountState()
    }

    func records(
        accountID: CloudAccountID,
        ids: [CloudRecordID]
    ) async throws -> [CloudRecord] {
        try await base.records(accountID: accountID, ids: ids)
    }

    func commitAtomically(
        _ request: CloudAtomicWriteRequest
    ) async throws -> CloudAtomicWriteReceipt {
        attempts += 1
        if attempts == 1 {
            throw CloudSyncTransportError.conflict(request.writes.map(\.id))
        }
        return try await base.commitAtomically(request)
    }

    func commitAttemptCount() -> Int {
        attempts
    }
}

private actor AlwaysConflictingTransport: CloudSyncTransport {
    let base: InMemoryCloudSyncTransport
    private var attempts = 0

    init(base: InMemoryCloudSyncTransport) {
        self.base = base
    }

    func accountState() async -> CloudAccountState {
        await base.accountState()
    }

    func records(
        accountID: CloudAccountID,
        ids: [CloudRecordID]
    ) async throws -> [CloudRecord] {
        try await base.records(accountID: accountID, ids: ids)
    }

    func commitAtomically(
        _ request: CloudAtomicWriteRequest
    ) throws -> CloudAtomicWriteReceipt {
        attempts += 1
        throw CloudSyncTransportError.conflict(request.writes.map(\.id))
    }

    func commitAttemptCount() -> Int {
        attempts
    }
}

private actor SupersededCommittedReceiptTransport: CloudSyncTransport {
    let base: InMemoryCloudSyncTransport
    let recordID: CloudRecordID
    private var attempts = 0

    init(base: InMemoryCloudSyncTransport, recordID: CloudRecordID) {
        self.base = base
        self.recordID = recordID
    }

    func accountState() async -> CloudAccountState {
        await base.accountState()
    }

    func records(
        accountID: CloudAccountID,
        ids: [CloudRecordID]
    ) async throws -> [CloudRecord] {
        try await base.records(accountID: accountID, ids: ids)
    }

    func commitAtomically(
        _ request: CloudAtomicWriteRequest
    ) async throws -> CloudAtomicWriteReceipt {
        attempts += 1
        let first = try await base.commitAtomically(request)
        let firstTag = first.savedChangeTags[recordID]!
        let headWrite = request.writes.first { $0.id == recordID }!
        let supersedingWrites = [
            CloudRecordWrite(
                id: headWrite.id,
                recordType: headWrite.recordType,
                fields: headWrite.fields,
                precondition: .changeTag(firstTag)
            ),
        ]
        _ = try await base.commitAtomically(
            CloudAtomicWriteRequest(
                accountID: request.accountID,
                operationID: OperationID("test-superseding-operation"),
                writes: supersedingWrites
            )
        )
        throw CloudKitCloudSyncError.committedOperationRequiresRefresh(
            operationID: request.operationID,
            recordIDs: request.writes.map(\.id)
        )
    }

    func coordinatorCommitAttemptCount() -> Int {
        attempts
    }
}

private actor InvalidateAuthorityAfterCommitTransport: CloudSyncTransport {
    let base: InMemoryCloudSyncTransport
    let authority: DurableEconomySessionAuthority
    private var shouldInvalidate = true

    init(
        base: InMemoryCloudSyncTransport,
        authority: DurableEconomySessionAuthority
    ) {
        self.base = base
        self.authority = authority
    }

    func accountState() async -> CloudAccountState {
        await base.accountState()
    }

    func records(
        accountID: CloudAccountID,
        ids: [CloudRecordID]
    ) async throws -> [CloudRecord] {
        try await base.records(accountID: accountID, ids: ids)
    }

    func commitAtomically(
        _ request: CloudAtomicWriteRequest
    ) async throws -> CloudAtomicWriteReceipt {
        let receipt = try await base.commitAtomically(request)
        if shouldInvalidate {
            shouldInvalidate = false
            await authority.invalidate()
        }
        return receipt
    }
}

private actor MutateRepositoryAfterCommitTransport: CloudSyncTransport {
    let base: InMemoryCloudSyncTransport
    let repository: LocalPlayerProfileRepository
    let run: CompletedRun
    let session: ProfileSessionToken
    let recordedAt: Date
    private var shouldMutate = true

    init(
        base: InMemoryCloudSyncTransport,
        repository: LocalPlayerProfileRepository,
        run: CompletedRun,
        session: ProfileSessionToken,
        recordedAt: Date
    ) {
        self.base = base
        self.repository = repository
        self.run = run
        self.session = session
        self.recordedAt = recordedAt
    }

    func accountState() async -> CloudAccountState {
        await base.accountState()
    }

    func records(
        accountID: CloudAccountID,
        ids: [CloudRecordID]
    ) async throws -> [CloudRecord] {
        try await base.records(accountID: accountID, ids: ids)
    }

    func commitAtomically(
        _ request: CloudAtomicWriteRequest
    ) async throws -> CloudAtomicWriteReceipt {
        let receipt = try await base.commitAtomically(request)
        if shouldMutate {
            shouldMutate = false
            _ = try await repository.settle(
                run,
                session: session,
                recordedAt: recordedAt
            )
        }
        return receipt
    }
}

private actor DurableEconomyTestStoreKitClient: StoreKit2PlatformClient {
    private let productsByID: [String: StoreKit2PlatformProduct]
    private var unfinished: [StoreKit2PlatformVerification]
    private var finishedIDs: [UInt64] = []

    init(
        products: [StoreKit2PlatformProduct],
        unfinished: [StoreKit2PlatformVerification]
    ) {
        productsByID = Dictionary(
            uniqueKeysWithValues: products.map { ($0.productIdentifier, $0) }
        )
        self.unfinished = unfinished
    }

    func products(
        for identifiers: Set<String>
    ) -> [StoreKit2PlatformProduct] {
        identifiers.sorted().compactMap { productsByID[$0] }
    }

    func purchase(
        productIdentifier: String,
        appAccountToken: UUID
    ) -> StoreKit2PlatformPurchaseResult {
        .userCancelled
    }

    func unfinishedTransactions() -> [StoreKit2PlatformVerification] {
        unfinished
    }

    func transactionUpdates() -> AsyncStream<StoreKit2PlatformVerification> {
        AsyncStream { continuation in continuation.finish() }
    }

    func finish(transactionID: UInt64) {
        finishedIDs.append(transactionID)
        unfinished.removeAll {
            guard case let .verified(transaction) = $0 else { return false }
            return transaction.transactionID == transactionID
        }
    }

    func finishedTransactionIDs() -> [UInt64] {
        finishedIDs
    }
}

import CryptoKit
import XCTest

@testable import PocketVector

final class DurableEconomyCoordinatorTests: XCTestCase, @unchecked Sendable {
    private let baseDate = Date(timeIntervalSince1970: 1_750_000_000)

    func testCloudSchemaFingerprintMaterialBindsExactDurableEconomyContract()
        throws
    {
        let configuration = try DurableEconomyCloudConfiguration(
            recordID: CloudRecordID("economy-head-v1"),
            recordType: "EconomyHead",
            payloadFieldName: "economyPayload"
        )

        XCTAssertEqual(
            configuration.fingerprintMaterial,
            [
                "pocket-vector-durable-economy-cloud-schema-v1",
                "headLogicalRecordID", "economy-head-v1",
                "recordType", "EconomyHead",
                "payloadFieldName", "economyPayload",
                "headSchemaVersion", "3",
                "ledgerMarkerSchemaVersion", "2",
                "rewardOfferMarkerSchemaVersion", "2",
                "rewardedAdHeadSchemaVersion", "1",
                "ledgerAccumulatorDigestByteCount", "32",
                "ledgerDigestDomain", "pocket-vector-ledger-entry-v1",
                "immutableMarkerAddressDomain",
                "pocket-vector-durable-economy-marker-v1",
                "immutableMarkerRecordPrefix", "economy-marker-v1-",
                "ledgerMarkerKind", "ledger-entry-v1",
                "rewardOfferMarkerKind", "reward-offer-v1",
                "operationAddressDomain",
                "pocket-vector-durable-economy-operation-v3",
                "operationRecordPrefix", "economy-v3-",
                "pendingCreditOperationKind", "pending-credit",
                "storeKitCreditOperationKind", "storekit-credit",
                "catalogUnlockOperationKind", "catalog-unlock",
                "rewardedAdCreditOperationKind", "rewarded-ad-credit",
                "payloadEncoding",
                "sorted-key-json-default-keys-without-escaped-slashes-deferred-date-base64-data-nonfinite-float-throw-v1",
                "digestAlgorithm", "sha256-v1",
                "digestComponentEncoding",
                "uint64-big-endian-length-prefixed-utf8-components-v1",
                "digestHexEncoding", "lowercase-two-digit-hex-per-byte-v1",
                "immutableMarkerAddressPolicy",
                "domain-head-record-kind-value-digest-prefixed-hex-v1",
                "operationAddressPolicy",
                "domain-cloud-account-id-account-key-profile-id-player-account-identity-kind-entry-count-then-entry-ids-digest-prefixed-hex-v2",
                "mutationOperationSessionPolicy",
                "durable-binding-and-player-identity-excludes-session-nonce-v1",
                "identifierOrderingPolicy",
                "utf8-byte-lexicographic-ascending-v1",
                "mutationEntryCountEncoding",
                "base-10-nonnegative-int-no-leading-zero-utf8-component-v1",
                "mutationEntryOrderingPolicy",
                "ledger-entry-id-utf8-byte-ascending-v1",
                "eventBatchAssignmentPolicy",
                "missing-ledger-entry-id-utf8-byte-ascending-zero-based-contiguous-uint32-v1",
                "cloudWriteOrderingPolicy",
                "cloud-record-id-utf8-byte-ascending-v1",
                "ledgerEntryDigestPolicy",
                "domain-id-delta-date-reference-bitpattern-reason-tag-associated-values-v1",
                "ledgerAccumulatorPolicy",
                "entry-count-confirmed-balance-order-independent-xor-entry-digests-v1",
                "economyEventOrderingPolicy",
                "cloud-head-revision-then-batch-index-v1",
                "unlockedItemOrderingPolicy",
                "catalog-item-id-utf8-byte-ascending-v1",
                "headFields",
                "accountBinding,cloudAccountID,ledgerAccumulator,profileAccountIdentity,revision,rewardedAd,schemaVersion,unlockedItemIDs",
                "ledgerAccumulatorFields", "confirmedBalance,digest,entryCount",
                "rewardedAdHeadFields",
                "cycle,eligibleOfferID,schemaVersion,validRunsSinceReward",
                "ledgerMarkerFields",
                "eventPosition,gameplayRewardObservation,gameplayRewardResolution,headRecordID,record,schemaVersion",
                "rewardOfferMarkerFields",
                "binding,eventPosition,headRecordID,redemption,schemaVersion",
                "ledgerRecordFields", "binding,entry",
                "coinLedgerEntryFields", "createdAt,delta,id,reason",
                "coinLedgerReasonCases",
                "catalogUnlock(itemID),gameplay(economyVersion,runID),rewardedAd(offerID,providerTransactionID),signingBonus(version),storeKit(packID,transactionID)",
                "mutationBindingFields",
                "accountBinding,cloudAccountID,kind,operationID,profileAccountIdentity,profileSessionNonce,sourceEconomyRevision",
                "durableAccountBindingFields", "accountKey,profileID",
                "mutationKindCases",
                "catalog-unlock,pending-credits,rewarded-ad,storekit",
                "rewardRedemptionFields",
                "ledgerEntryID,offerID,providerTransactionID",
                "eventPositionFields", "batchIndex,cloudHeadRevision",
                "rewardedRunObservationFields", "disposition,observedCycle",
                "rewardedRunObservationDispositionCases",
                "candidate,ignoredWhileOfferPending,legacyNonCounting",
                "gameplayRewardResolutionCases",
                "counted(cycle,resultingCount,unlockedOfferID),ignoredActiveOffer(cycle,offerID),ignoredLegacyNonCounting,ignoredStaleCycle(currentCycle,observedCycle)",
                "coinLedgerAddressMaterialCount", "13",
                "pocket-vector-coin-ledger-addresses-v1",
                "gameplayPrefix", "run/",
                "gameplaySuffix", "/reward",
                "signingBonusPrefix", "signing-bonus/v",
                "rewardedAdPrefix", "rewarded-ad/",
                "storeKitPrefix", "storekit/",
                "catalogUnlockPrefix", "unlock/",
                "rewardOfferAddressMaterialCount", "3",
                "pocket-vector-rewarded-ad-offer-address-v1",
                "offerIDPrefix", "reward-cycle/",
                "persistedEconomyRules",
                "pocket-vector-persisted-economy-rules-v1",
                "runEconomyVersion", "1",
                "runNaturalMilliseconds", "60000",
                "runMinimumRewardAttempts", "3",
                "runBaseCoins", "10",
                "runScoreCoinsPerPoints", "1000",
                "runMaximumScoreCoins", "25",
                "runAccuracyBonusCoins", "5",
                "runAccuracyMinimumAttempts", "10",
                "runAccuracyMinimumPercent", "70",
                "signingBonusVersion", "1",
                "signingBonusCoins", "250",
                "signingBonusCreatedAt1970BitPattern", "0",
                "rewardedAdCoins", "100",
                "rewardedAdRunThreshold", "5",
                "lockedTeamPrice", "1500",
                "alternateJerseyPrice", "500",
                "alternateFootballPrice", "750",
                "coinPackCount", "4",
                "coinPack", "bundle", "3600",
                "coinPack", "pocket", "500",
                "coinPack", "team", "1650",
                "coinPack", "vault", "6500",
            ]
        )
        XCTAssertEqual(
            DurableEconomyCloudSchema.utf8Precedes("z", "é"),
            Data("z".utf8).lexicographicallyPrecedes(Data("é".utf8))
        )
        XCTAssertEqual(
            DurableEconomyCloudSchema.batchIndex(forZeroBasedOffset: 0),
            0
        )
        XCTAssertEqual(
            DurableEconomyCloudSchema.batchIndex(forZeroBasedOffset: 17),
            17
        )
        XCTAssertNil(
            DurableEconomyCloudSchema.batchIndex(forZeroBasedOffset: -1)
        )
        XCTAssertNil(
            DurableEconomyCloudSchema.batchIndex(
                forZeroBasedOffset: Int(UInt32.max) + 1
            )
        )
    }

    func testAssociatedEnumManifestsMatchActualGoldenJSONEncoding() throws {
        XCTAssertEqual(
            CoinLedgerReason.persistedCaseManifest,
            "catalogUnlock(itemID),gameplay(economyVersion,runID)," +
                "rewardedAd(offerID,providerTransactionID)," +
                "signingBonus(version),storeKit(packID,transactionID)"
        )
        XCTAssertEqual(
            DurableEconomyCoordinator.GameplayRewardResolution
                .persistedCaseManifest,
            "counted(cycle,resultingCount,unlockedOfferID)," +
                "ignoredActiveOffer(cycle,offerID)," +
                "ignoredLegacyNonCounting," +
                "ignoredStaleCycle(currentCycle,observedCycle)"
        )

        let reasons: [CoinLedgerReason] = [
            .catalogUnlock(itemID: CatalogItemID("item-a")),
            .gameplay(
                runID: RunID(
                    UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
                ),
                economyVersion: 7
            ),
            .rewardedAd(
                offerID: RewardOfferID("offer-a"),
                providerTransactionID: AdProviderTransactionID("provider-a")
            ),
            .signingBonus(version: 3),
            .storeKit(transactionID: 42, packID: CoinPackID("pack-a")),
        ]
        let reasonCaseNames = [
            "catalogUnlock", "gameplay", "rewardedAd", "signingBonus",
            "storeKit",
        ]
        let reasonJSON = try reasons.map {
            String(
                decoding: try DurableEconomyCloudSchema.makePayloadEncoder()
                    .encode($0),
                as: UTF8.self
            )
        }
        XCTAssertEqual(
            reasonJSON,
            [
                "{\"catalogUnlock\":{\"itemID\":\"item-a\"}}",
                "{\"gameplay\":{\"economyVersion\":7,\"runID\":{\"rawValue\":\"00000000-0000-4000-8000-000000000001\"}}}",
                "{\"rewardedAd\":{\"offerID\":\"offer-a\",\"providerTransactionID\":\"provider-a\"}}",
                "{\"signingBonus\":{\"version\":3}}",
                "{\"storeKit\":{\"packID\":\"pack-a\",\"transactionID\":42}}",
            ]
        )
        for (encoded, caseName) in zip(reasonJSON, reasonCaseNames) {
            let object = try XCTUnwrap(
                JSONSerialization.jsonObject(with: Data(encoded.utf8))
                    as? [String: Any]
            )
            XCTAssertEqual(Set(object.keys), [caseName])
        }

        let resolutions: [DurableEconomyCoordinator.GameplayRewardResolution] = [
            .counted(
                cycle: 2,
                resultingCount: 4,
                unlockedOfferID: RewardOfferID("offer-a")
            ),
            .ignoredActiveOffer(cycle: 2, offerID: RewardOfferID("offer-a")),
            .ignoredLegacyNonCounting,
            .ignoredStaleCycle(observedCycle: 1, currentCycle: 2),
        ]
        let resolutionCaseNames = [
            "counted", "ignoredActiveOffer", "ignoredLegacyNonCounting",
            "ignoredStaleCycle",
        ]
        let resolutionJSON = try resolutions.map {
            String(
                decoding: try DurableEconomyCloudSchema.makePayloadEncoder()
                    .encode($0),
                as: UTF8.self
            )
        }
        XCTAssertEqual(
            resolutionJSON,
            [
                "{\"counted\":{\"cycle\":2,\"resultingCount\":4,\"unlockedOfferID\":\"offer-a\"}}",
                "{\"ignoredActiveOffer\":{\"cycle\":2,\"offerID\":\"offer-a\"}}",
                "{\"ignoredLegacyNonCounting\":{}}",
                "{\"ignoredStaleCycle\":{\"currentCycle\":2,\"observedCycle\":1}}",
            ]
        )
        for (encoded, caseName) in zip(resolutionJSON, resolutionCaseNames) {
            let object = try XCTUnwrap(
                JSONSerialization.jsonObject(with: Data(encoded.utf8))
                    as? [String: Any]
            )
            XCTAssertEqual(Set(object.keys), [caseName])
        }
    }

    func testProductionEconomyAddressDigestAndMaximalPayloadGoldenVectors()
        async throws
    {
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let cloud = InMemoryCloudSyncTransport(
            accountState: .available(cloudAccountID)
        )
        let fixture = try await makeFixture(
            directory: directory,
            cloud: cloud,
            sessionNonce: uuid(1),
            newProfileID: uuid(2)
        )
        let providerTransactionID = AdProviderTransactionID(
            "provider/golden-001"
        )
        let offerID = RewardedAdState.offerID(for: 7)
        let rewardEntry = CoinLedgerEntry(
            id: CoinLedgerID.rewardedAd(
                providerTransactionID: providerTransactionID
            ),
            delta: PersistedEconomyRulesV1.rewardedAdCoins,
            reason: .rewardedAd(
                offerID: offerID,
                providerTransactionID: providerTransactionID
            ),
            createdAt: Date(timeIntervalSince1970: 1_750_000_123)
        )
        let signingEntry = CoinLedgerEntry(
            id: CoinLedgerID.signingBonus(version: 1),
            delta: PersistedEconomyRulesV1.signingBonusCoins,
            reason: .signingBonus(version: 1),
            createdAt: PersistedEconomyRulesV1.signingBonusLedgerCreatedAt
        )
        let rewardOperationID = await fixture.coordinator.mutationOperationID(
            kind: DurableEconomyCloudSchema.rewardedAdCreditOperationKind,
            entryIDs: [rewardEntry.id]
        )
        let batchOperationID = await fixture.coordinator.mutationOperationID(
            kind: DurableEconomyCloudSchema.pendingCreditOperationKind,
            entryIDs: [rewardEntry.id, signingEntry.id]
        )
        let rewardDigest = await fixture.coordinator.ledgerDigest(
            for: rewardEntry
        )
        let signingDigest = await fixture.coordinator.ledgerDigest(
            for: signingEntry
        )
        let accumulator = try await fixture.coordinator.ledgerAccumulator(
            for: [rewardEntry, signingEntry]
        )
        let binding = await fixture.coordinator.mutationBinding(
            kind: .rewardedAd,
            operationID: rewardOperationID,
            sourceEconomyRevision: 41
        )
        let eventPosition = DurableEconomyCoordinator.CloudEconomyEventPosition(
            cloudHeadRevision: 42,
            batchIndex: 0
        )
        let ledgerMarker = DurableEconomyCoordinator.CloudLedgerMarkerV2(
            schemaVersion:
                DurableEconomyCoordinator.CloudLedgerMarkerV2.schemaVersion,
            headRecordID: economyRecordID,
            record: DurableEconomyCoordinator.CloudLedgerRecord(
                entry: rewardEntry,
                binding: binding
            ),
            eventPosition: eventPosition,
            gameplayRewardObservation: RewardedRunObservation(
                observedCycle: 7,
                disposition: .candidate
            ),
            gameplayRewardResolution: .counted(
                cycle: 7,
                resultingCount: 5,
                unlockedOfferID: offerID
            )
        )
        let rewardMarker = DurableEconomyCoordinator.CloudRewardOfferMarkerV2(
            schemaVersion:
                DurableEconomyCoordinator.CloudRewardOfferMarkerV2.schemaVersion,
            headRecordID: economyRecordID,
            redemption: DurableEconomyCoordinator.RewardRedemption(
                offerID: offerID,
                providerTransactionID: providerTransactionID,
                ledgerEntryID: rewardEntry.id
            ),
            binding: binding,
            eventPosition: eventPosition
        )
        var maximalRewardedAdHead =
            DurableEconomyCoordinator.CloudRewardedAdHeadV1.initial
        for _ in 0 ..< PersistedEconomyRulesV1.rewardedAdRunThreshold {
            _ = try maximalRewardedAdHead.resolveGameplay(
                observation: RewardedRunObservation(
                    observedCycle: 0,
                    disposition: .candidate
                )
            )
        }
        XCTAssertEqual(
            maximalRewardedAdHead.eligibleOfferID,
            RewardedAdState.offerID(for: 0)
        )

        let head = DurableEconomyCoordinator.CloudAccountHeadV3(
            schemaVersion:
                DurableEconomyCoordinator.CloudAccountHeadV3.schemaVersion,
            cloudAccountID: fixture.context.cloudAccountID,
            accountBinding: fixture.context.accountBinding,
            profileAccountIdentity: fixture.context.profileSession.accountIdentity,
            revision: 42,
            ledgerAccumulator: accumulator,
            unlockedItemIDs: [CatalogItemID("unlock.golden-item")],
            rewardedAd: maximalRewardedAdHead
        )
        let loaded = DurableEconomyCoordinator.LoadedCloudState(
            state: nil,
            changeTag: nil,
            ledgerMarkers: [:],
            rewardOfferMarkers: [:]
        )
        let headWrite = try await fixture.coordinator.makeHeadWrite(
            state: head,
            loaded: loaded
        )
        let ledgerWrite = try await fixture.coordinator.makeLedgerMarkerWrite(
            ledgerMarker
        )
        let rewardWrite = try await fixture.coordinator.makeRewardOfferMarkerWrite(
            rewardMarker
        )
        let headPayload = try XCTUnwrap(headWrite.fields["economyPayload"])
        let ledgerPayload = try XCTUnwrap(
            ledgerWrite.fields["economyPayload"]
        )
        let rewardPayload = try XCTUnwrap(
            rewardWrite.fields["economyPayload"]
        )

        XCTAssertEqual(
            rewardEntry.id.rawValue,
            "rewarded-ad/provider/golden-001"
        )
        XCTAssertEqual(
            offerID.rawValue,
            "reward-cycle/7"
        )
        XCTAssertEqual(
            ledgerWrite.id.rawValue,
            "economy-marker-v1-b68b7a5c0b77fd21e858bc45d244bcc3062917965ac1f58fc4e78a2228a16429"
        )
        XCTAssertEqual(
            rewardWrite.id.rawValue,
            "economy-marker-v1-dc0752c3f4461f94ec8733befb24e68443cfd517b2c935a3126d4c6f5fff2121"
        )
        XCTAssertEqual(
            rewardOperationID.rawValue,
            "economy-v3-10b47d23503d6540721c2974057cd93d855fe73cfd22bd29f915aa6deef03808"
        )
        XCTAssertEqual(
            batchOperationID.rawValue,
            "economy-v3-df7eebf7d5a4e29027d0758a20cba587cbd8d2f2f54774dcf19b455b1d2c63e0"
        )
        XCTAssertEqual(
            hex(rewardDigest),
            "ff79f657a63355601af7205f9c215cf16ddb18ecbbc81a0bdc2571f078590392"
        )
        XCTAssertEqual(
            hex(signingDigest),
            "e849815cd40843ff013d99607fbd3d91732169475b24eb4d6e58fe2f74e21f32"
        )
        XCTAssertEqual(accumulator.entryCount, 2)
        XCTAssertEqual(accumulator.confirmedBalance, 350)
        XCTAssertEqual(
            hex(accumulator.digest),
            "1730770b723b169f1bcab93fe39c61601efa71abe0ecf146b27d8fdf0cbb1ca0"
        )
        XCTAssertEqual(
            hex(Data(SHA256.hash(data: headPayload))),
            "db228f2708d269ab5faa582293944e8e0735f32c180029b9e343e70ed70913be"
        )
        XCTAssertEqual(
            hex(Data(SHA256.hash(data: ledgerPayload))),
            "f74f011b090002c95cb67e234ccbe2ebb3a21996c4842ebc8c88d0a8c0d88099"
        )
        XCTAssertEqual(
            hex(Data(SHA256.hash(data: rewardPayload))),
            "14272bd9ac9b64319685e2abb6537da8ffdabb27aeb6d541603bcaa9477115d0"
        )

        let relaunchedSession = ProfileSessionToken(
            accountIdentity: fixture.context.profileSession.accountIdentity,
            nonce: uuid(99),
            profileID: fixture.context.profileSession.profileID
        )
        let relaunchedContext = try DurableEconomySessionContext(
            cloudAccountID: fixture.context.cloudAccountID,
            accountBinding: fixture.context.accountBinding,
            profileSession: relaunchedSession,
            storeSession: StoreActiveSession(
                binding: fixture.context.storeSession.binding,
                nonce: relaunchedSession.nonce
            )
        )
        let relaunchedAuthority = DurableEconomySessionAuthority(
            context: relaunchedContext
        )
        let relaunchedCoordinator = try makeCoordinator(
            context: relaunchedContext,
            authority: relaunchedAuthority,
            repository: fixture.repository,
            cloud: cloud
        )
        let relaunchedOperationID = await relaunchedCoordinator
            .mutationOperationID(
                kind: DurableEconomyCloudSchema.pendingCreditOperationKind,
                entryIDs: [signingEntry.id, rewardEntry.id]
            )
        XCTAssertEqual(relaunchedOperationID, batchOperationID)
    }

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
                    packID: pack.id,
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
            testingContext: fixture.context,
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

    func testConcurrentCatalogUnlockCollisionRecoversWinnersImmutableTimestamp()
        async throws
    {
        let firstDirectory = makeTemporaryDirectory()
        let secondDirectory = makeTemporaryDirectory()
        defer {
            removeTemporaryDirectory(firstDirectory)
            removeTemporaryDirectory(secondDirectory)
        }
        let base = InMemoryCloudSyncTransport(
            accountState: .available(cloudAccountID)
        )
        let sharedProfileID = uuid(107)
        let first = try await makeFixture(
            directory: firstDirectory,
            cloud: base,
            sessionNonce: uuid(108),
            newProfileID: sharedProfileID
        )
        let second = try await makeFixture(
            directory: secondDirectory,
            cloud: base,
            sessionNonce: uuid(109),
            newProfileID: sharedProfileID
        )
        let pack = EconomyConfiguration.coinPacks[1]
        let firstPackRequest = storeDeliveryRequest(
            transactionID: 10_700,
            context: first.context,
            pack: pack
        )
        let secondPackRequest = storeDeliveryRequest(
            transactionID: 10_700,
            context: second.context,
            pack: pack
        )
        _ = try await first.coordinator.deliver(firstPackRequest)
        _ = try await second.coordinator.deliver(secondPackRequest)

        let blockedCloud = BlockingFirstCommitTransport(base: base)
        let loserTimestamp = baseDate.addingTimeInterval(60_000)
        let winnerTimestamp = baseDate.addingTimeInterval(61_000)
        let loserCoordinator = DurableEconomyCoordinator(
            testingContext: first.context,
            sessionAuthority: first.authority,
            repository: first.repository,
            cloud: blockedCloud,
            configuration: try DurableEconomyCloudConfiguration(
                recordID: economyRecordID,
                recordType: "TestEconomyHead",
                payloadFieldName: "economyPayload"
            ),
            now: { loserTimestamp }
        )
        let winnerCoordinator = DurableEconomyCoordinator(
            testingContext: second.context,
            sessionAuthority: second.authority,
            repository: second.repository,
            cloud: base,
            configuration: try DurableEconomyCloudConfiguration(
                recordID: economyRecordID,
                recordType: "TestEconomyHead",
                payloadFieldName: "economyPayload"
            ),
            now: { winnerTimestamp }
        )
        let item = alternateJerseyItem()
        let ledgerID = CoinLedgerID.catalogUnlock(itemID: item.id)
        let loserTask = Task {
            try await loserCoordinator.unlock(
                itemID: item.id,
                requestOperationID: OperationID("loser-catalog-collision"),
                session: first.snapshot.session
            )
        }
        await blockedCloud.waitUntilFirstCommitStarts()
        let winnerResult = try await winnerCoordinator.unlock(
            itemID: item.id,
            requestOperationID: OperationID("winner-catalog-collision"),
            session: second.snapshot.session
        )
        await blockedCloud.releaseFirstCommit()
        let recovered = try await loserTask.value

        XCTAssertEqual(winnerResult.cloudReceipt.status, .committed)
        XCTAssertEqual(recovered.cloudReceipt.status, .committedThenRefreshed)
        let firstAfter = try await first.repository.snapshot()
        let secondAfter = try await second.repository.snapshot()
        XCTAssertEqual(firstAfter.ledger[ledgerID]?.createdAt, winnerTimestamp)
        XCTAssertEqual(secondAfter.ledger[ledgerID]?.createdAt, winnerTimestamp)
        XCTAssertNotEqual(firstAfter.ledger[ledgerID]?.createdAt, loserTimestamp)
        XCTAssertTrue(
            firstAfter.player.inventory.ownedJerseyIDs.contains(alternateJerseyID())
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
            newProfileID: uuid(111),
            deriveAccountBindings: true
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
        let request = try await verifiedRewardRequest(
            session: eligible.session,
            accountBinding: fixture.context.accountBinding,
            offerID: offerID,
            providerTransactionID: AdProviderTransactionID("verified-ssv-transaction"),
            rewardedAt: baseDate.addingTimeInterval(20_000)
        )

        let first = try await fixture.coordinator.deliverVerifiedReward(request)
        let retry = try await fixture.coordinator.deliverVerifiedReward(request)

        XCTAssertFalse(first.outcome.wasAlreadySettled)
        XCTAssertTrue(retry.outcome.wasAlreadySettled)
        XCTAssertEqual(first.outcome.coins, 100)
        XCTAssertEqual(first.cloudReceipt.status, .committed)
        XCTAssertEqual(retry.cloudReceipt.status, .alreadyCommitted)
        XCTAssertTrue(
            first.authorizesJournalDeletion(
                currentSession: eligible.session,
                currentBinding: fixture.context.accountBinding,
                offerID: request.offerID,
                providerTransactionID: request.providerTransactionID,
                rewardedAt: request.rewardedAt
            )
        )
        XCTAssertTrue(
            retry.authorizesJournalDeletion(
                currentSession: eligible.session,
                currentBinding: fixture.context.accountBinding,
                offerID: request.offerID,
                providerTransactionID: request.providerTransactionID,
                rewardedAt: request.rewardedAt
            )
        )
        let snapshot = try await fixture.repository.snapshot()
        XCTAssertEqual(snapshot.coinBalances.confirmed, 550)
        XCTAssertNil(snapshot.player.rewardedAdState.eligibleOfferID)
        XCTAssertEqual(snapshot.coinBalances.pending, 0)

        let history = try decodeCloudHistory(
            await cloud.allRecords(for: cloudAccountID)
        )
        XCTAssertEqual(history.head.rewardedAd.cycle, 1)
        XCTAssertEqual(history.head.rewardedAd.validRunsSinceReward, 0)
        XCTAssertNil(history.head.rewardedAd.eligibleOfferID)
        XCTAssertEqual(
            history.rewardOfferMarkers[offerID]?.redemption,
            DurableEconomyCoordinator.RewardRedemption(
                offerID: offerID,
                providerTransactionID: request.providerTransactionID,
                ledgerEntryID: first.outcome.ledgerEntryID
            )
        )
        let verifiedRewardHistory = try await fixture.coordinator
            .verifyCompleteCloudHistory(
                head: history.head,
                ledgerMarkers: history.ledgerMarkers,
                rewardOfferMarkers: history.rewardOfferMarkers
            )
        XCTAssertEqual(
            verifiedRewardHistory.rewardedAd,
            history.head.rewardedAd
        )
        do {
            _ = try await fixture.coordinator.verifyCompleteCloudHistory(
                head: history.head,
                ledgerMarkers: history.ledgerMarkers,
                rewardOfferMarkers: [:]
            )
            XCTFail("A complete replica cannot omit a reward-offer marker")
        } catch {
            XCTAssertEqual(
                error as? DurableEconomyCoordinatorError,
                .malformedCloudRecord
            )
        }
    }

    func testRewardedAdCommittedThenRefreshedSettlesExactlyOnceAndAuthorizesDeletion()
        async throws
    {
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let base = InMemoryCloudSyncTransport(
            accountState: .available(cloudAccountID)
        )
        let fixture = try await makeFixture(
            directory: directory,
            cloud: base,
            sessionNonce: uuid(156),
            newProfileID: uuid(157),
            deriveAccountBindings: true
        )
        for index in 410 ..< 415 {
            _ = try await settleRun(
                index: index,
                repository: fixture.repository,
                session: fixture.snapshot.session
            )
        }
        let confirmation = try await fixture.coordinator
            .confirmAllPendingCredits()
        _ = try XCTUnwrap(confirmation)
        let beforeReward = try await fixture.repository.snapshot()
        let offerID = try XCTUnwrap(
            beforeReward.player.rewardedAdState.eligibleOfferID
        )
        XCTAssertEqual(beforeReward.coinBalances.pending, 0)

        let cloud = SupersededCommittedReceiptTransport(
            base: base,
            recordID: economyRecordID
        )
        let coordinator = try makeCoordinator(
            context: fixture.context,
            authority: fixture.authority,
            repository: fixture.repository,
            cloud: cloud
        )
        let request = try await verifiedRewardRequest(
            session: beforeReward.session,
            accountBinding: fixture.context.accountBinding,
            offerID: offerID,
            providerTransactionID: AdProviderTransactionID(
                "verified-ssv-committed-then-refreshed"
            ),
            rewardedAt: baseDate.addingTimeInterval(80_000)
        )

        let result = try await coordinator.deliverVerifiedReward(request)

        XCTAssertEqual(result.cloudReceipt.status, .committedThenRefreshed)
        XCTAssertTrue(
            result.authorizesJournalDeletion(
                currentSession: beforeReward.session,
                currentBinding: fixture.context.accountBinding,
                offerID: request.offerID,
                providerTransactionID: request.providerTransactionID,
                rewardedAt: request.rewardedAt
            )
        )
        let commitAttempts = await cloud.coordinatorCommitAttemptCount()
        XCTAssertEqual(commitAttempts, 1)

        let afterReward = try await fixture.repository.snapshot()
        XCTAssertEqual(
            afterReward.coinBalances.confirmed,
            beforeReward.coinBalances.confirmed
                + PersistedEconomyRulesV1.rewardedAdCoins
        )
        XCTAssertEqual(afterReward.coinBalances.pending, 0)
        XCTAssertNil(afterReward.player.rewardedAdState.eligibleOfferID)
        XCTAssertEqual(
            afterReward.player.rewardedAdState.cycle,
            beforeReward.player.rewardedAdState.cycle + 1
        )

        let history = try decodeCloudHistory(
            await base.allRecords(for: cloudAccountID)
        )
        XCTAssertEqual(
            history.rewardOfferMarkers[offerID]?.redemption,
            DurableEconomyCoordinator.RewardRedemption(
                offerID: offerID,
                providerTransactionID: request.providerTransactionID,
                ledgerEntryID: result.outcome.ledgerEntryID
            )
        )
    }

    func testRewardedAdRejectsNonDerivedContextBeforeCloudOrLocalMutation()
        async throws
    {
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let base = InMemoryCloudSyncTransport(
            accountState: .available(cloudAccountID)
        )
        let cloud = CommitCountingTransport(base: base)
        let fixture = try await makeFixture(
            directory: directory,
            cloud: cloud,
            sessionNonce: uuid(158),
            newProfileID: uuid(159)
        )
        for index in 420 ..< 425 {
            _ = try await settleRun(
                index: index,
                repository: fixture.repository,
                session: fixture.snapshot.session
            )
        }
        let before = try await fixture.repository.snapshot()
        let offerID = try XCTUnwrap(
            before.player.rewardedAdState.eligibleOfferID
        )
        let locations = ProfileStorageLocations(directoryURL: directory)
        let primaryBefore = try Data(contentsOf: locations.primaryURL)
        let backupBefore = try Data(contentsOf: locations.backupURL)
        let commitsBefore = await cloud.commitCallCount()
        let recordsBefore = await base.allRecords(for: cloudAccountID)
        let request = try await verifiedRewardRequest(
            session: before.session,
            accountBinding: fixture.context.accountBinding,
            offerID: offerID,
            providerTransactionID: AdProviderTransactionID(
                "verified-ssv-non-derived-context"
            ),
            rewardedAt: baseDate.addingTimeInterval(81_000)
        )

        do {
            _ = try await fixture.coordinator.deliverVerifiedReward(request)
            XCTFail("A non-canonical cloud/account binding must fail closed")
        } catch {
            XCTAssertEqual(
                error as? DurableEconomyCoordinatorError,
                .invalidRewardedAdRequest
            )
        }

        let commitsAfter = await cloud.commitCallCount()
        let recordsAfter = await base.allRecords(for: cloudAccountID)
        XCTAssertEqual(commitsAfter, commitsBefore)
        XCTAssertEqual(
            recordsAfter,
            recordsBefore
        )
        let after = try await fixture.repository.snapshot()
        XCTAssertEqual(after, before)
        XCTAssertEqual(
            try Data(contentsOf: locations.primaryURL),
            primaryBefore
        )
        XCTAssertEqual(
            try Data(contentsOf: locations.backupURL),
            backupBefore
        )
        XCTAssertEqual(after.player.rewardedAdState.eligibleOfferID, offerID)
    }

    func testCanonicalRewardBatchUnlocksFiveIgnoresSixthAndRetriesExactlyOnce()
        async throws
    {
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let cloud = InMemoryCloudSyncTransport(
            accountState: .available(cloudAccountID)
        )
        let fixture = try await makeFixture(
            directory: directory,
            cloud: cloud,
            sessionNonce: uuid(112),
            newProfileID: uuid(113)
        )
        var runIDs: [RunID] = []
        for index in 210 ..< 216 {
            let settlement = try await settleRun(
                index: index,
                repository: fixture.repository,
                session: fixture.snapshot.session
            )
            runIDs.append(settlement.outcome.record.run.runID)
        }
        let pending = try await fixture.repository.snapshot()
        let pendingIDs = pending.pendingLedgerEntryIDs

        let first = try await fixture.coordinator.confirmPendingCredits(
            pendingIDs,
            session: pending.session
        )
        let recordsAfterFirst = await cloud.allRecords(for: cloudAccountID)
        let history = try decodeCloudHistory(recordsAfterFirst)

        XCTAssertEqual(first.cloudReceipt.status, .committed)
        XCTAssertEqual(history.head.rewardedAd.cycle, 0)
        XCTAssertEqual(history.head.rewardedAd.validRunsSinceReward, 5)
        XCTAssertEqual(
            history.head.rewardedAd.eligibleOfferID,
            RewardedAdState.offerID(for: 0)
        )
        let orderedMarkers = history.ledgerMarkers.values.sorted {
            $0.eventPosition < $1.eventPosition
        }
        XCTAssertEqual(
            orderedMarkers.map(\.record.entry.id),
            pendingIDs.sorted {
                DurableEconomyCloudSchema.utf8Precedes(
                    $0.rawValue,
                    $1.rawValue
                )
            }
        )
        XCTAssertEqual(
            orderedMarkers.map(\.eventPosition.cloudHeadRevision),
            Array(repeating: 1, count: pendingIDs.count)
        )
        XCTAssertEqual(
            orderedMarkers.map(\.eventPosition.batchIndex),
            (0 ..< UInt32(pendingIDs.count)).map { $0 }
        )

        for (offset, runID) in runIDs.prefix(5).enumerated() {
            let marker = try XCTUnwrap(
                history.ledgerMarkers[CoinLedgerID.gameplay(runID: runID)]
            )
            XCTAssertEqual(
                marker.gameplayRewardObservation,
                RewardedRunObservation(observedCycle: 0, disposition: .candidate)
            )
            XCTAssertEqual(
                marker.gameplayRewardResolution,
                .counted(
                    cycle: 0,
                    resultingCount: offset + 1,
                    unlockedOfferID: offset == 4
                        ? RewardedAdState.offerID(for: 0)
                        : nil
                )
            )
        }
        let sixthMarker = try XCTUnwrap(
            history.ledgerMarkers[CoinLedgerID.gameplay(runID: runIDs[5])]
        )
        XCTAssertEqual(
            sixthMarker.gameplayRewardObservation,
            RewardedRunObservation(
                observedCycle: 0,
                disposition: .ignoredWhileOfferPending
            )
        )
        XCTAssertEqual(
            sixthMarker.gameplayRewardResolution,
            .ignoredActiveOffer(
                cycle: 0,
                offerID: RewardedAdState.offerID(for: 0)
            )
        )
        let verifiedBatchHistory = try await fixture.coordinator
            .verifyCompleteCloudHistory(
                head: history.head,
                ledgerMarkers: history.ledgerMarkers,
                rewardOfferMarkers: history.rewardOfferMarkers
            )
        XCTAssertEqual(
            verifiedBatchHistory.rewardedAd,
            history.head.rewardedAd
        )
        var duplicatePositionMarkers = history.ledgerMarkers
        let firstGameplayID = CoinLedgerID.gameplay(runID: runIDs[0])
        let secondGameplayID = CoinLedgerID.gameplay(runID: runIDs[1])
        let firstGameplayMarker = try XCTUnwrap(
            history.ledgerMarkers[firstGameplayID]
        )
        let secondGameplayMarker = try XCTUnwrap(
            history.ledgerMarkers[secondGameplayID]
        )
        duplicatePositionMarkers[secondGameplayID] =
            DurableEconomyCoordinator.CloudLedgerMarkerV2(
                schemaVersion: secondGameplayMarker.schemaVersion,
                headRecordID: secondGameplayMarker.headRecordID,
                record: secondGameplayMarker.record,
                eventPosition: firstGameplayMarker.eventPosition,
                gameplayRewardObservation:
                    secondGameplayMarker.gameplayRewardObservation,
                gameplayRewardResolution:
                    secondGameplayMarker.gameplayRewardResolution
            )
        do {
            _ = try await fixture.coordinator.verifyCompleteCloudHistory(
                head: history.head,
                ledgerMarkers: duplicatePositionMarkers,
                rewardOfferMarkers: history.rewardOfferMarkers
            )
            XCTFail("Duplicate event positions must fail complete replay")
        } catch {
            XCTAssertEqual(
                error as? DurableEconomyCoordinatorError,
                .invalidRewardEventPosition
            )
        }

        let retry = try await fixture.coordinator.confirmPendingCredits(
            pendingIDs,
            session: pending.session
        )
        let recordsAfterRetry = await cloud.allRecords(for: cloudAccountID)
        XCTAssertEqual(retry.cloudReceipt.status, .alreadyCommitted)
        XCTAssertEqual(recordsAfterRetry, recordsAfterFirst)
    }

    func testStaleRewardCycleAfterRedemptionNeverBanksAndFutureCycleFailsClosed()
        async throws
    {
        let staleDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(staleDirectory) }
        let staleCloud = InMemoryCloudSyncTransport(
            accountState: .available(cloudAccountID)
        )
        let fixture = try await makeFixture(
            directory: staleDirectory,
            cloud: staleCloud,
            sessionNonce: uuid(114),
            newProfileID: uuid(115),
            deriveAccountBindings: true
        )
        for index in 220 ..< 225 {
            _ = try await settleRun(
                index: index,
                repository: fixture.repository,
                session: fixture.snapshot.session
            )
        }
        let eligible = try await fixture.repository.snapshot()
        let offerID = try XCTUnwrap(eligible.player.rewardedAdState.eligibleOfferID)
        _ = try await fixture.coordinator.deliverVerifiedReward(
            try await verifiedRewardRequest(
                session: eligible.session,
                accountBinding: fixture.context.accountBinding,
                offerID: offerID,
                providerTransactionID: AdProviderTransactionID("stale-cycle-redemption"),
                rewardedAt: baseDate.addingTimeInterval(50_000)
            )
        )
        let delayed = try await settleRun(
            index: 225,
            repository: fixture.repository,
            session: fixture.snapshot.session
        )
        let delayedEntryID = try XCTUnwrap(delayed.outcome.gameplayRewardEntryID)
        let delayedRunID = delayed.outcome.record.run.runID
        let staleRepository = RewardObservationOverrideRepository(
            base: fixture.repository,
            overrides: [
                delayedRunID: RewardedRunObservation(
                    observedCycle: 0,
                    disposition: .candidate
                ),
            ]
        )
        let staleCoordinator = try makeCoordinator(
            context: fixture.context,
            authority: fixture.authority,
            repository: staleRepository,
            cloud: staleCloud
        )

        _ = try await staleCoordinator.confirmPendingCredits(
            [delayedEntryID],
            session: fixture.snapshot.session
        )
        let staleHistory = try decodeCloudHistory(
            await staleCloud.allRecords(for: cloudAccountID)
        )
        let delayedMarker = try XCTUnwrap(
            staleHistory.ledgerMarkers[delayedEntryID]
        )
        XCTAssertEqual(
            delayedMarker.gameplayRewardResolution,
            .ignoredStaleCycle(observedCycle: 0, currentCycle: 1)
        )
        XCTAssertEqual(staleHistory.head.rewardedAd.cycle, 1)
        XCTAssertEqual(staleHistory.head.rewardedAd.validRunsSinceReward, 0)
        XCTAssertNil(staleHistory.head.rewardedAd.eligibleOfferID)
        let verifiedStaleHistory = try await staleCoordinator
            .verifyCompleteCloudHistory(
                head: staleHistory.head,
                ledgerMarkers: staleHistory.ledgerMarkers,
                rewardOfferMarkers: staleHistory.rewardOfferMarkers
            )
        XCTAssertEqual(
            verifiedStaleHistory.rewardedAd,
            staleHistory.head.rewardedAd
        )

        let futureDirectory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(futureDirectory) }
        let futureCloud = InMemoryCloudSyncTransport(
            accountState: .available(cloudAccountID)
        )
        let futureFixture = try await makeFixture(
            directory: futureDirectory,
            cloud: futureCloud,
            sessionNonce: uuid(116),
            newProfileID: uuid(117)
        )
        let futureSettlement = try await settleRun(
            index: 226,
            repository: futureFixture.repository,
            session: futureFixture.snapshot.session
        )
        let futureEntryID = try XCTUnwrap(
            futureSettlement.outcome.gameplayRewardEntryID
        )
        let futureRunID = futureSettlement.outcome.record.run.runID
        let futureRepository = RewardObservationOverrideRepository(
            base: futureFixture.repository,
            overrides: [
                futureRunID: RewardedRunObservation(
                    observedCycle: 1,
                    disposition: .candidate
                ),
            ]
        )
        let futureCoordinator = try makeCoordinator(
            context: futureFixture.context,
            authority: futureFixture.authority,
            repository: futureRepository,
            cloud: futureCloud
        )
        let pendingBefore = try await futureFixture.repository.snapshot()

        do {
            _ = try await futureCoordinator.confirmPendingCredits(
                [futureEntryID],
                session: futureFixture.snapshot.session
            )
            XCTFail("An observation from a future reward cycle must fail closed")
        } catch {
            XCTAssertEqual(
                error as? DurableEconomyCoordinatorError,
                .rewardedRunObservationAhead(observed: 1, current: 0)
            )
        }
        let futureRecords = await futureCloud.allRecords(for: cloudAccountID)
        let pendingAfter = try await futureFixture.repository.snapshot()
        XCTAssertTrue(futureRecords.isEmpty)
        XCTAssertEqual(pendingAfter, pendingBefore)
    }

    func testLegacyV1ProfileMigratesProgressAndConfirmsCoinsWithoutAdProgress()
        async throws
    {
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let cloud = InMemoryCloudSyncTransport(
            accountState: .available(cloudAccountID)
        )
        let profileID = uuid(114)
        let original = try await makeFixture(
            directory: directory,
            cloud: cloud,
            sessionNonce: uuid(115),
            newProfileID: profileID
        )
        let pack = EconomyConfiguration.coinPacks[1]
        _ = try await original.coordinator.deliver(
            storeDeliveryRequest(
                transactionID: 11_400,
                context: original.context,
                pack: pack
            )
        )
        let alternate = alternateJerseyItem()
        _ = try await original.coordinator.unlock(
            itemID: alternate.id,
            requestOperationID: OperationID("legacy-inventory-unlock"),
            session: original.snapshot.session
        )
        _ = try await original.repository.updateSettings(
            PlayerSettings(
                musicVolume: 0.25,
                sfxVolume: 0.75,
                isMuted: true,
                reducedMotion: true,
                tutorialCompleted: true
            ),
            session: original.snapshot.session,
            at: baseDate.addingTimeInterval(10)
        )
        let settlement = try await settleRun(
            index: 239,
            repository: original.repository,
            session: original.snapshot.session
        )
        let beforeMigration = try await original.repository.snapshot()
        XCTAssertEqual(beforeMigration.player.rewardedAdState.validRunsSinceReward, 1)
        let signingID = try XCTUnwrap(settlement.outcome.signingBonusEntryID)
        let gameplayID = try XCTUnwrap(settlement.outcome.gameplayRewardEntryID)
        let legacySigningTimestamp = baseDate.addingTimeInterval(23_900)

        let locations = ProfileStorageLocations(directoryURL: directory)
        var legacyDocument = try PlayerProfileMigrator().decode(
            Data(contentsOf: locations.primaryURL)
        )
        let signingEntry = try XCTUnwrap(legacyDocument.player.ledger[signingID])
        legacyDocument.player.ledger[signingID] = CoinLedgerEntry(
            id: signingEntry.id,
            delta: signingEntry.delta,
            reason: signingEntry.reason,
            createdAt: legacySigningTimestamp
        )
        legacyDocument.rewardedRunObservations = nil
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        let scopedV1Data = try encoder.encode(
            PlayerProfileEnvelopeV1(
                document: legacyDocument,
                savedAt: baseDate.addingTimeInterval(24_000)
            )
        )
        var legacyEnvelope = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: scopedV1Data)
                as? [String: Any]
        )
        var legacyLocalDocument = try XCTUnwrap(
            legacyEnvelope["document"] as? [String: Any]
        )
        var legacyPlayer = try XCTUnwrap(
            legacyLocalDocument["player"] as? [String: Any]
        )
        let scopedQueue = try XCTUnwrap(
            legacyPlayer["pendingGameCenter"] as? [String: Any]
        )
        XCTAssertTrue(
            try XCTUnwrap(scopedQueue["pendingByPlayerID"] as? [Any]).isEmpty
        )
        legacyPlayer["pendingGameCenter"] = try XCTUnwrap(
            scopedQueue["unboundPending"] as? [String: Any]
        )
        legacyLocalDocument["player"] = legacyPlayer
        legacyEnvelope["document"] = legacyLocalDocument
        let legacyData = try JSONSerialization.data(
            withJSONObject: legacyEnvelope,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        try legacyData.write(to: locations.primaryURL, options: .atomic)
        try legacyData.write(to: locations.backupURL, options: .atomic)

        let migrated = try await makeFixture(
            directory: directory,
            cloud: cloud,
            sessionNonce: uuid(116),
            newProfileID: uuid(999)
        )
        let loaded = migrated.snapshot
        XCTAssertEqual(loaded.player.profileID, profileID)
        XCTAssertTrue(loaded.player.settings.isMuted)
        XCTAssertTrue(loaded.player.settings.reducedMotion)
        XCTAssertTrue(
            loaded.player.inventory.ownedJerseyIDs.contains(alternateJerseyID())
        )
        XCTAssertNotNil(loaded.completedRuns[settlement.outcome.record.run.runID])
        XCTAssertEqual(loaded.pendingLedgerEntryIDs, [signingID, gameplayID])
        XCTAssertEqual(
            loaded.ledger[signingID]?.createdAt,
            PersistedEconomyRulesV1.signingBonusLedgerCreatedAt
        )
        XCTAssertEqual(
            loaded.rewardedRunObservations[settlement.outcome.record.run.runID],
            RewardedRunObservation(
                observedCycle: 0,
                disposition: .legacyNonCounting
            )
        )
        XCTAssertEqual(loaded.player.rewardedAdState.validRunsSinceReward, 0)
        XCTAssertNil(loaded.player.rewardedAdState.eligibleOfferID)

        let confirmationResult = try await migrated.coordinator
            .confirmAllPendingCredits()
        let confirmed = try XCTUnwrap(confirmationResult)
        XCTAssertEqual(confirmed.snapshot.coinBalances.pending, 0)
        XCTAssertEqual(
            confirmed.snapshot.coinBalances.confirmed,
            loaded.coinBalances.confirmed + loaded.coinBalances.pending
        )
        XCTAssertEqual(
            confirmed.snapshot.player.rewardedAdState.validRunsSinceReward,
            0
        )
        let history = try decodeCloudHistory(
            await cloud.allRecords(for: cloudAccountID)
        )
        XCTAssertEqual(history.head.rewardedAd, .initial)
        XCTAssertEqual(
            history.ledgerMarkers[gameplayID]?.gameplayRewardResolution,
            .ignoredLegacyNonCounting
        )
        let gameplayMarker = try XCTUnwrap(history.ledgerMarkers[gameplayID])
        var invalidLegacyCycleMarkers = history.ledgerMarkers
        invalidLegacyCycleMarkers[gameplayID] =
            DurableEconomyCoordinator.CloudLedgerMarkerV2(
                schemaVersion: gameplayMarker.schemaVersion,
                headRecordID: gameplayMarker.headRecordID,
                record: gameplayMarker.record,
                eventPosition: gameplayMarker.eventPosition,
                gameplayRewardObservation: RewardedRunObservation(
                    observedCycle: 1,
                    disposition: .legacyNonCounting
                ),
                gameplayRewardResolution: .ignoredLegacyNonCounting
            )
        do {
            _ = try await migrated.coordinator.verifyCompleteCloudHistory(
                head: history.head,
                ledgerMarkers: invalidLegacyCycleMarkers,
                rewardOfferMarkers: history.rewardOfferMarkers
            )
            XCTFail("Legacy non-counting observations must use canonical cycle zero")
        } catch {}

        let persistedData = try Data(contentsOf: locations.primaryURL)
        let persistedObject = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: persistedData) as? [String: Any]
        )
        XCTAssertEqual(
            (persistedObject["schemaVersion"] as? NSNumber)?.intValue,
            PlayerProfileEnvelopeV4.schemaVersion
        )
        XCTAssertNotNil(
            (persistedObject["document"] as? [String: Any])?["rewardedRunObservations"]
        )
    }

    func testCompleteHistoryVerifierRejectsWrongHeadFutureOrphanTamperingAndAccumulator()
        async throws
    {
        let directory = makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let cloud = InMemoryCloudSyncTransport(
            accountState: .available(cloudAccountID)
        )
        let fixture = try await makeFixture(
            directory: directory,
            cloud: cloud,
            sessionNonce: uuid(116),
            newProfileID: uuid(117),
            deriveAccountBindings: true
        )
        let pack = EconomyConfiguration.coinPacks[1]
        _ = try await fixture.coordinator.deliver(
            storeDeliveryRequest(
                transactionID: 11_600,
                context: fixture.context,
                pack: pack
            )
        )
        _ = try await fixture.coordinator.unlock(
            itemID: alternateJerseyItem().id,
            requestOperationID: OperationID("history-verifier-unlock"),
            session: fixture.snapshot.session
        )
        for index in 240 ..< 245 {
            _ = try await settleRun(
                index: index,
                repository: fixture.repository,
                session: fixture.snapshot.session
            )
        }
        _ = try await fixture.coordinator.confirmAllPendingCredits()
        let eligible = try await fixture.repository.snapshot()
        let offerID = try XCTUnwrap(eligible.player.rewardedAdState.eligibleOfferID)
        _ = try await fixture.coordinator.deliverVerifiedReward(
            try await verifiedRewardRequest(
                session: eligible.session,
                accountBinding: fixture.context.accountBinding,
                offerID: offerID,
                providerTransactionID: AdProviderTransactionID("verify-complete-history"),
                rewardedAt: baseDate.addingTimeInterval(25_000)
            )
        )
        let history = try decodeCloudHistory(
            await cloud.allRecords(for: cloudAccountID)
        )
        _ = try await fixture.coordinator.verifyCompleteCloudHistory(
            head: history.head,
            ledgerMarkers: history.ledgerMarkers,
            rewardOfferMarkers: history.rewardOfferMarkers
        )

        let signingID = CoinLedgerID.signingBonus(
            version: PersistedEconomyRulesV1.signingBonusVersion
        )
        let signingMarker = try XCTUnwrap(history.ledgerMarkers[signingID])
        var wrongHeadMarkers = history.ledgerMarkers
        wrongHeadMarkers[signingID] = DurableEconomyCoordinator.CloudLedgerMarkerV2(
            schemaVersion: signingMarker.schemaVersion,
            headRecordID: CloudRecordID("wrong-economy-head"),
            record: signingMarker.record,
            eventPosition: signingMarker.eventPosition,
            gameplayRewardObservation: nil,
            gameplayRewardResolution: nil
        )
        do {
            _ = try await fixture.coordinator.verifyCompleteCloudHistory(
                head: history.head,
                ledgerMarkers: wrongHeadMarkers,
                rewardOfferMarkers: history.rewardOfferMarkers
            )
            XCTFail("A marker bound to another head must be rejected")
        } catch {}

        var futureMarkers = history.ledgerMarkers
        futureMarkers[signingID] = DurableEconomyCoordinator.CloudLedgerMarkerV2(
            schemaVersion: signingMarker.schemaVersion,
            headRecordID: signingMarker.headRecordID,
            record: signingMarker.record,
            eventPosition: DurableEconomyCoordinator.CloudEconomyEventPosition(
                cloudHeadRevision: history.head.revision + 1,
                batchIndex: signingMarker.eventPosition.batchIndex
            ),
            gameplayRewardObservation: nil,
            gameplayRewardResolution: nil
        )
        do {
            _ = try await fixture.coordinator.verifyCompleteCloudHistory(
                head: history.head,
                ledgerMarkers: futureMarkers,
                rewardOfferMarkers: history.rewardOfferMarkers
            )
            XCTFail("A future event position must be rejected")
        } catch {}

        var noncontiguousMarkers = history.ledgerMarkers
        noncontiguousMarkers[signingID] =
            DurableEconomyCoordinator.CloudLedgerMarkerV2(
                schemaVersion: signingMarker.schemaVersion,
                headRecordID: signingMarker.headRecordID,
                record: signingMarker.record,
                eventPosition: DurableEconomyCoordinator.CloudEconomyEventPosition(
                    cloudHeadRevision: signingMarker.eventPosition.cloudHeadRevision,
                    batchIndex: 999
                ),
                gameplayRewardObservation: nil,
                gameplayRewardResolution: nil
            )
        do {
            _ = try await fixture.coordinator.verifyCompleteCloudHistory(
                head: history.head,
                ledgerMarkers: noncontiguousMarkers,
                rewardOfferMarkers: history.rewardOfferMarkers
            )
            XCTFail("A noncontiguous batch index must be rejected")
        } catch {}

        let rewardMarker = try XCTUnwrap(history.rewardOfferMarkers[offerID])
        let orphanOfferID = RewardOfferID("reward-cycle/orphan")
        var orphanOffers = history.rewardOfferMarkers
        orphanOffers[orphanOfferID] = DurableEconomyCoordinator.CloudRewardOfferMarkerV2(
            schemaVersion: rewardMarker.schemaVersion,
            headRecordID: rewardMarker.headRecordID,
            redemption: DurableEconomyCoordinator.RewardRedemption(
                offerID: orphanOfferID,
                providerTransactionID: AdProviderTransactionID("orphan-provider"),
                ledgerEntryID: LedgerEntryID("rewarded-ad/orphan-provider")
            ),
            binding: rewardMarker.binding,
            eventPosition: DurableEconomyCoordinator.CloudEconomyEventPosition(
                cloudHeadRevision: history.head.revision,
                batchIndex: 999
            )
        )
        do {
            _ = try await fixture.coordinator.verifyCompleteCloudHistory(
                head: history.head,
                ledgerMarkers: history.ledgerMarkers,
                rewardOfferMarkers: orphanOffers
            )
            XCTFail("An orphan reward-offer marker must be rejected")
        } catch {}

        let gameplay = try XCTUnwrap(history.ledgerMarkers.first(where: {
            if case .gameplay = $0.value.record.entry.reason { return true }
            return false
        }))
        var tamperedResolutionMarkers = history.ledgerMarkers
        let firstTamperedResolution =
            DurableEconomyCoordinator.GameplayRewardResolution.counted(
                cycle: 0,
                resultingCount: 1,
                unlockedOfferID: nil
            )
        let tamperedResolution = gameplay.value.gameplayRewardResolution
            == firstTamperedResolution
            ? DurableEconomyCoordinator.GameplayRewardResolution.counted(
                cycle: 0,
                resultingCount: 2,
                unlockedOfferID: nil
            )
            : firstTamperedResolution
        tamperedResolutionMarkers[gameplay.key] =
            DurableEconomyCoordinator.CloudLedgerMarkerV2(
                schemaVersion: gameplay.value.schemaVersion,
                headRecordID: gameplay.value.headRecordID,
                record: gameplay.value.record,
                eventPosition: gameplay.value.eventPosition,
                gameplayRewardObservation: gameplay.value.gameplayRewardObservation,
                gameplayRewardResolution: tamperedResolution
            )
        do {
            _ = try await fixture.coordinator.verifyCompleteCloudHistory(
                head: history.head,
                ledgerMarkers: tamperedResolutionMarkers,
                rewardOfferMarkers: history.rewardOfferMarkers
            )
            XCTFail("A tampered gameplay resolution must be rejected")
        } catch {}

        let batchGameplay = try XCTUnwrap(history.ledgerMarkers.first(where: {
            guard case .gameplay = $0.value.record.entry.reason else { return false }
            return $0.value.eventPosition.cloudHeadRevision
                == signingMarker.eventPosition.cloudHeadRevision
        }))
        var reorderedBatch = history.ledgerMarkers
        reorderedBatch[signingID] = DurableEconomyCoordinator.CloudLedgerMarkerV2(
            schemaVersion: signingMarker.schemaVersion,
            headRecordID: signingMarker.headRecordID,
            record: signingMarker.record,
            eventPosition: batchGameplay.value.eventPosition,
            gameplayRewardObservation: nil,
            gameplayRewardResolution: nil
        )
        reorderedBatch[batchGameplay.key] =
            DurableEconomyCoordinator.CloudLedgerMarkerV2(
                schemaVersion: batchGameplay.value.schemaVersion,
                headRecordID: batchGameplay.value.headRecordID,
                record: batchGameplay.value.record,
                eventPosition: signingMarker.eventPosition,
                gameplayRewardObservation:
                    batchGameplay.value.gameplayRewardObservation,
                gameplayRewardResolution:
                    batchGameplay.value.gameplayRewardResolution
            )
        do {
            _ = try await fixture.coordinator.verifyCompleteCloudHistory(
                head: history.head,
                ledgerMarkers: reorderedBatch,
                rewardOfferMarkers: history.rewardOfferMarkers
            )
            XCTFail("A batch not ordered by ledger ID must be rejected")
        } catch {}

        let gameplayBinding = batchGameplay.value.record.binding
        var splitBindingBatch = history.ledgerMarkers
        splitBindingBatch[batchGameplay.key] =
            DurableEconomyCoordinator.CloudLedgerMarkerV2(
                schemaVersion: batchGameplay.value.schemaVersion,
                headRecordID: batchGameplay.value.headRecordID,
                record: DurableEconomyCoordinator.CloudLedgerRecord(
                    entry: batchGameplay.value.record.entry,
                    binding: DurableEconomyCoordinator.MutationBinding(
                        cloudAccountID: gameplayBinding.cloudAccountID,
                        accountBinding: gameplayBinding.accountBinding,
                        profileAccountIdentity:
                            gameplayBinding.profileAccountIdentity,
                        profileSessionNonce: gameplayBinding.profileSessionNonce,
                        sourceEconomyRevision:
                            gameplayBinding.sourceEconomyRevision,
                        operationID: OperationID("fabricated-split-batch"),
                        kind: gameplayBinding.kind
                    )
                ),
                eventPosition: batchGameplay.value.eventPosition,
                gameplayRewardObservation:
                    batchGameplay.value.gameplayRewardObservation,
                gameplayRewardResolution:
                    batchGameplay.value.gameplayRewardResolution
            )
        do {
            _ = try await fixture.coordinator.verifyCompleteCloudHistory(
                head: history.head,
                ledgerMarkers: splitBindingBatch,
                rewardOfferMarkers: history.rewardOfferMarkers
            )
            XCTFail("One atomic revision cannot contain multiple mutation bindings")
        } catch {}

        let storeMarker = try XCTUnwrap(history.ledgerMarkers.first(where: {
            if case .storeKit = $0.value.record.entry.reason { return true }
            return false
        }))
        let unlockMarker = try XCTUnwrap(history.ledgerMarkers.first(where: {
            if case .catalogUnlock = $0.value.record.entry.reason { return true }
            return false
        }))
        let unlockBinding = unlockMarker.value.record.binding
        var reusedOperationID = history.ledgerMarkers
        reusedOperationID[unlockMarker.key] =
            DurableEconomyCoordinator.CloudLedgerMarkerV2(
                schemaVersion: unlockMarker.value.schemaVersion,
                headRecordID: unlockMarker.value.headRecordID,
                record: DurableEconomyCoordinator.CloudLedgerRecord(
                    entry: unlockMarker.value.record.entry,
                    binding: DurableEconomyCoordinator.MutationBinding(
                        cloudAccountID: unlockBinding.cloudAccountID,
                        accountBinding: unlockBinding.accountBinding,
                        profileAccountIdentity:
                            unlockBinding.profileAccountIdentity,
                        profileSessionNonce: unlockBinding.profileSessionNonce,
                        sourceEconomyRevision:
                            unlockBinding.sourceEconomyRevision,
                        operationID:
                            storeMarker.value.record.binding.operationID,
                        kind: unlockBinding.kind
                    )
                ),
                eventPosition: unlockMarker.value.eventPosition,
                gameplayRewardObservation: nil,
                gameplayRewardResolution: nil
            )
        do {
            _ = try await fixture.coordinator.verifyCompleteCloudHistory(
                head: history.head,
                ledgerMarkers: reusedOperationID,
                rewardOfferMarkers: history.rewardOfferMarkers
            )
            XCTFail("One operation ID cannot own two cloud-head revisions")
        } catch {
            XCTAssertEqual(
                error as? DurableEconomyCoordinatorError,
                .malformedCloudRecord
            )
        }

        var debitBeforeCredit = history.ledgerMarkers
        debitBeforeCredit[storeMarker.key] =
            DurableEconomyCoordinator.CloudLedgerMarkerV2(
                schemaVersion: storeMarker.value.schemaVersion,
                headRecordID: storeMarker.value.headRecordID,
                record: storeMarker.value.record,
                eventPosition: unlockMarker.value.eventPosition,
                gameplayRewardObservation: nil,
                gameplayRewardResolution: nil
            )
        debitBeforeCredit[unlockMarker.key] =
            DurableEconomyCoordinator.CloudLedgerMarkerV2(
                schemaVersion: unlockMarker.value.schemaVersion,
                headRecordID: unlockMarker.value.headRecordID,
                record: unlockMarker.value.record,
                eventPosition: storeMarker.value.eventPosition,
                gameplayRewardObservation: nil,
                gameplayRewardResolution: nil
            )
        do {
            _ = try await fixture.coordinator.verifyCompleteCloudHistory(
                head: history.head,
                ledgerMarkers: debitBeforeCredit,
                rewardOfferMarkers: history.rewardOfferMarkers
            )
            XCTFail("A debit replayed before its funding credit must be rejected")
        } catch {}

        var accumulatorHead = history.head
        accumulatorHead.ledgerAccumulator.confirmedBalance += 1
        do {
            _ = try await fixture.coordinator.verifyCompleteCloudHistory(
                head: accumulatorHead,
                ledgerMarkers: history.ledgerMarkers,
                rewardOfferMarkers: history.rewardOfferMarkers
            )
            XCTFail("A head accumulator mismatch must be rejected")
        } catch {}
    }

    func testConcurrentSigningBonusCASLoserUploadsGameplayWithExactWinnerMarker()
        async throws
    {
        let winnerDirectory = makeTemporaryDirectory()
        let loserDirectory = makeTemporaryDirectory()
        defer {
            removeTemporaryDirectory(winnerDirectory)
            removeTemporaryDirectory(loserDirectory)
        }
        let base = InMemoryCloudSyncTransport(
            accountState: .available(cloudAccountID)
        )
        let blockedLoserCloud = BlockingFirstCommitTransport(base: base)
        let sharedProfileID = uuid(118)
        let winner = try await makeFixture(
            directory: winnerDirectory,
            cloud: base,
            sessionNonce: uuid(119),
            newProfileID: sharedProfileID
        )
        let loser = try await makeFixture(
            directory: loserDirectory,
            cloud: blockedLoserCloud,
            sessionNonce: uuid(120),
            newProfileID: sharedProfileID
        )
        let winnerSettlement = try await settleRun(
            index: 230,
            repository: winner.repository,
            session: winner.snapshot.session
        )
        let loserSettlement = try await settleRun(
            index: 231,
            repository: loser.repository,
            session: loser.snapshot.session
        )
        let signingID = try XCTUnwrap(winnerSettlement.outcome.signingBonusEntryID)
        XCTAssertEqual(loserSettlement.outcome.signingBonusEntryID, signingID)
        let loserGameplayID = try XCTUnwrap(
            loserSettlement.outcome.gameplayRewardEntryID
        )
        let winnerPending = try await winner.repository.snapshot()
        let loserPending = try await loser.repository.snapshot()
        let winnerEntry = try XCTUnwrap(winnerPending.ledger[signingID])
        let loserEntry = try XCTUnwrap(loserPending.ledger[signingID])
        XCTAssertEqual(winnerEntry, loserEntry)
        XCTAssertEqual(
            winnerEntry.createdAt,
            PersistedEconomyRulesV1.signingBonusLedgerCreatedAt
        )

        let loserTask = Task {
            try await loser.coordinator.confirmPendingCredits(
                [signingID, loserGameplayID],
                session: loser.snapshot.session
            )
        }
        await blockedLoserCloud.waitUntilFirstCommitStarts()
        _ = try await winner.coordinator.confirmPendingCredits(
            [signingID],
            session: winner.snapshot.session
        )
        await blockedLoserCloud.releaseFirstCommit()
        let loserResult = try await loserTask.value
        let loserCommitCount = await blockedLoserCloud.commitCallCount()

        XCTAssertEqual(loserResult.cloudReceipt.status, .committed)
        XCTAssertEqual(loserCommitCount, 2)
        let history = try decodeCloudHistory(
            await base.allRecords(for: cloudAccountID)
        )
        XCTAssertEqual(history.ledgerMarkers[signingID]?.record.entry, winnerEntry)
        XCTAssertEqual(
            history.ledgerMarkers[loserGameplayID]?.record.entry,
            loserResult.snapshot.ledger[loserGameplayID]
        )
        XCTAssertEqual(
            history.ledgerMarkers.values.filter {
                if case .signingBonus = $0.record.entry.reason { return true }
                return false
            }.count,
            1
        )
        XCTAssertEqual(history.head.ledgerAccumulator.entryCount, 2)
        XCTAssertEqual(history.head.rewardedAd.validRunsSinceReward, 1)
        XCTAssertEqual(loserResult.snapshot.coinBalances.pending, 0)
    }

    func testConcurrentSameStoreTransactionRefreshesExactOperationCollision()
        async throws
    {
        let firstDirectory = makeTemporaryDirectory()
        let secondDirectory = makeTemporaryDirectory()
        defer {
            removeTemporaryDirectory(firstDirectory)
            removeTemporaryDirectory(secondDirectory)
        }
        let base = InMemoryCloudSyncTransport(
            accountState: .available(cloudAccountID)
        )
        let blockedFirstCloud = BlockingFirstCommitTransport(base: base)
        let sharedProfileID = uuid(122)
        let first = try await makeFixture(
            directory: firstDirectory,
            cloud: blockedFirstCloud,
            sessionNonce: uuid(123),
            newProfileID: sharedProfileID
        )
        let second = try await makeFixture(
            directory: secondDirectory,
            cloud: base,
            sessionNonce: uuid(124),
            newProfileID: sharedProfileID
        )
        let pack = EconomyConfiguration.coinPacks[0]
        let firstRequest = storeDeliveryRequest(
            transactionID: 12_200,
            context: first.context,
            pack: pack
        )
        let secondRequest = storeDeliveryRequest(
            transactionID: 12_200,
            context: second.context,
            pack: pack
        )
        XCTAssertEqual(firstRequest.ledgerEntry, secondRequest.ledgerEntry)

        let firstTask = Task {
            try await first.coordinator.deliver(firstRequest)
        }
        await blockedFirstCloud.waitUntilFirstCommitStarts()
        let winner = try await second.coordinator.deliver(secondRequest)
        await blockedFirstCloud.releaseFirstCommit()
        let refreshed = try await firstTask.value

        XCTAssertEqual(winner.status, .committed)
        XCTAssertEqual(refreshed.status, .alreadyCommitted)
        let firstAfter = try await first.repository.snapshot()
        let secondAfter = try await second.repository.snapshot()
        XCTAssertEqual(
            firstAfter.coinBalances.confirmed,
            pack.coins
        )
        XCTAssertEqual(
            secondAfter.coinBalances.confirmed,
            pack.coins
        )
        let history = try decodeCloudHistory(
            await base.allRecords(for: cloudAccountID)
        )
        XCTAssertEqual(history.head.ledgerAccumulator.entryCount, 1)
        XCTAssertEqual(
            history.ledgerMarkers[firstRequest.ledgerEntry.id]?.record.entry,
            firstRequest.ledgerEntry
        )
    }

    func testBothDevicesConfirmAllSignalsRebaseWithoutMutatingLoser()
        async throws
    {
        let winnerDirectory = makeTemporaryDirectory()
        let loserDirectory = makeTemporaryDirectory()
        defer {
            removeTemporaryDirectory(winnerDirectory)
            removeTemporaryDirectory(loserDirectory)
        }
        let base = InMemoryCloudSyncTransport(
            accountState: .available(cloudAccountID)
        )
        let blockedLoserCloud = BlockingFirstCommitTransport(base: base)
        let sharedProfileID = uuid(125)
        let winner = try await makeFixture(
            directory: winnerDirectory,
            cloud: base,
            sessionNonce: uuid(126),
            newProfileID: sharedProfileID
        )
        let loser = try await makeFixture(
            directory: loserDirectory,
            cloud: blockedLoserCloud,
            sessionNonce: uuid(127),
            newProfileID: sharedProfileID
        )
        _ = try await settleRun(
            index: 232,
            repository: winner.repository,
            session: winner.snapshot.session
        )
        _ = try await settleRun(
            index: 233,
            repository: loser.repository,
            session: loser.snapshot.session
        )
        let loserBefore = try await loser.repository.snapshot()

        let loserTask = Task {
            try await loser.coordinator.confirmAllPendingCredits()
        }
        await blockedLoserCloud.waitUntilFirstCommitStarts()
        let winnerResult = try await winner.coordinator.confirmAllPendingCredits()
        await blockedLoserCloud.releaseFirstCommit()
        do {
            _ = try await loserTask.value
            XCTFail("Unhydrated remote history must require an explicit rebase")
        } catch {
            XCTAssertEqual(
                error as? DurableEconomyCoordinatorError,
                .cloudRebaseRequired
            )
        }

        let loserAfter = try await loser.repository.snapshot()
        XCTAssertEqual(loserAfter, loserBefore)
        XCTAssertEqual(loserAfter.pendingLedgerEntryIDs.count, 2)
        XCTAssertEqual(winnerResult?.snapshot.pendingLedgerEntryIDs, Set())
        let history = try decodeCloudHistory(
            await base.allRecords(for: cloudAccountID)
        )
        XCTAssertEqual(history.head.ledgerAccumulator.entryCount, 2)
        XCTAssertEqual(history.head.rewardedAd.validRunsSinceReward, 1)
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
                    component == "entryCount"
                        ? .cloudRebaseRequired
                        : .cloudStateDiverged
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
            newProfileID: uuid(151),
            deriveAccountBindings: true
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
            sessionNonce: eligible.session.nonce,
            accountIdentity: fixture.context.profileSession.accountIdentity
        )
        let staleSnapshot = try await staleRepository.load(
            at: baseDate,
            newProfileID: fixture.context.accountBinding.profileID
        )
        let staleContext = try makeContext(
            snapshot: staleSnapshot,
            accountBinding: fixture.context.accountBinding
        )
        let staleAuthority = DurableEconomySessionAuthority(context: staleContext)
        let staleCoordinator = try makeCoordinator(
            context: staleContext,
            authority: staleAuthority,
            repository: staleRepository,
            cloud: cloud
        )

        _ = try await fixture.coordinator.deliverVerifiedReward(
            try await verifiedRewardRequest(
                session: eligible.session,
                accountBinding: fixture.context.accountBinding,
                offerID: offerID,
                providerTransactionID: AdProviderTransactionID("provider-a"),
                rewardedAt: baseDate.addingTimeInterval(40_000)
            )
        )
        let recordsBeforeCollision = await cloud.allRecords(for: cloudAccountID)

        do {
            _ = try await staleCoordinator.deliverVerifiedReward(
                try await verifiedRewardRequest(
                    session: staleSnapshot.session,
                    accountBinding: staleContext.accountBinding,
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

    struct DecodedCloudHistory {
        let head: DurableEconomyCoordinator.CloudAccountHeadV3
        let ledgerMarkers: [
            LedgerEntryID: DurableEconomyCoordinator.CloudLedgerMarkerV2
        ]
        let rewardOfferMarkers: [
            RewardOfferID: DurableEconomyCoordinator.CloudRewardOfferMarkerV2
        ]
    }

    var cloudAccountID: CloudAccountID {
        CloudAccountID("test-private-cloud-account")
    }

    var economyRecordID: CloudRecordID {
        CloudRecordID("test-economy-head")
    }

    func decodeCloudHistory(
        _ records: [CloudRecord]
    ) throws -> DecodedCloudHistory {
        let decoder = JSONDecoder()
        let headRecord = try headRecord(in: records)
        let head = try decoder.decode(
            DurableEconomyCoordinator.CloudAccountHeadV3.self,
            from: headPayload(from: headRecord)
        )
        var ledgerMarkers: [
            LedgerEntryID: DurableEconomyCoordinator.CloudLedgerMarkerV2
        ] = [:]
        var rewardOfferMarkers: [
            RewardOfferID: DurableEconomyCoordinator.CloudRewardOfferMarkerV2
        ] = [:]
        for record in records where record.id != economyRecordID {
            let payload = try headPayload(from: record)
            if let marker = try? decoder.decode(
                DurableEconomyCoordinator.CloudLedgerMarkerV2.self,
                from: payload
            ) {
                guard ledgerMarkers.updateValue(
                    marker,
                    forKey: marker.record.entry.id
                ) == nil else {
                    throw DurableEconomyTestFixtureError.malformedCloudPayload
                }
                continue
            }
            if let marker = try? decoder.decode(
                DurableEconomyCoordinator.CloudRewardOfferMarkerV2.self,
                from: payload
            ) {
                guard rewardOfferMarkers.updateValue(
                    marker,
                    forKey: marker.redemption.offerID
                ) == nil else {
                    throw DurableEconomyTestFixtureError.malformedCloudPayload
                }
                continue
            }
            throw DurableEconomyTestFixtureError.malformedCloudPayload
        }
        return DecodedCloudHistory(
            head: head,
            ledgerMarkers: ledgerMarkers,
            rewardOfferMarkers: rewardOfferMarkers
        )
    }

    func makeFixture(
        directory: URL,
        cloud: any CloudSyncTransport,
        sessionNonce: UUID,
        newProfileID: UUID,
        conflictRetryLimit: Int = 3,
        deriveAccountBindings: Bool = false
    ) async throws -> Fixture {
        let derived = CloudAccountDerivedBindings.derive(from: cloudAccountID)
        let repository = makeRepository(
            directory: directory,
            sessionNonce: sessionNonce,
            accountIdentity: deriveAccountBindings
                ? derived.playerAccountIdentity
                : PlayerAccountIdentity("test-player-account")
        )
        let snapshot = try await repository.load(
            at: baseDate,
            newProfileID: deriveAccountBindings
                ? derived.durableAccountBinding.profileID
                : newProfileID
        )
        let context = try makeContext(
            snapshot: snapshot,
            accountBinding: deriveAccountBindings
                ? derived.durableAccountBinding
                : nil
        )
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
            testingContext: context,
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
        sessionNonce: UUID,
        accountIdentity: PlayerAccountIdentity = PlayerAccountIdentity(
            "test-player-account"
        )
    ) -> LocalPlayerProfileRepository {
        LocalPlayerProfileRepository(
            directoryURL: directory,
            deviceID: "durable-economy-test-device",
            accountIdentity: accountIdentity,
            sessionNonce: sessionNonce,
            economyMutationPolicy: .requireDurablePrivateCloud
        )
    }

    func makeContext(
        snapshot: LocalPlayerProfileSnapshot,
        accountBinding: DurableAccountBinding? = nil
    ) throws -> DurableEconomySessionContext {
        let accountBinding = accountBinding ?? DurableAccountBinding(
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

    func verifiedRewardRequest(
        session: ProfileSessionToken,
        accountBinding: DurableAccountBinding,
        offerID: RewardOfferID,
        providerTransactionID: AdProviderTransactionID,
        rewardedAt: Date
    ) async throws -> VerifiedRewardedAdDurableDeliveryRequest {
        let attempt = RewardedAdAttempt(
            binding: accountBinding,
            presentationSessionNonce: session.nonce,
            offerID: offerID,
            attemptID: UUID()
        )
        let transport = DurableEconomyRewardVerificationTransport(
            attempt: attempt,
            providerTransactionID: providerTransactionID,
            rewardedAt: rewardedAt
        )
        let client = RewardedAdVerificationClient(testingTransport: transport)
        let challenge = try await client.prepareChallenge(for: attempt)
        let status = try await client.verificationStatus(for: challenge)
        guard case let .verified(claim) = status else {
            throw DurableEconomyTestFixtureError.malformedCloudPayload
        }
        return try claim.durableDeliveryRequest(
            session: session,
            currentBinding: accountBinding
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

    func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
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

private struct RewardObservationOverrideRepository: DurableEconomyLocalPersisting {
    let base: LocalPlayerProfileRepository
    let overrides: [RunID: RewardedRunObservation]

    func durableEconomySnapshot() async throws -> LocalPlayerProfileSnapshot {
        let snapshot = try await base.snapshot()
        return LocalPlayerProfileSnapshot(
            session: snapshot.session,
            player: snapshot.player,
            economyRevision: snapshot.economyRevision,
            coinBalances: snapshot.coinBalances,
            completedRuns: snapshot.completedRuns,
            ledger: snapshot.ledger,
            pendingLedgerEntryIDs: snapshot.pendingLedgerEntryIDs,
            rewardedRunObservations: snapshot.rewardedRunObservations.merging(
                overrides,
                uniquingKeysWith: { _, override in override }
            )
        )
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
        try await base.prepareUnlock(
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

private actor DurableEconomyRewardVerificationTransport:
    RewardedAdVerificationTransport
{
    private let attempt: RewardedAdAttempt
    private let providerTransactionID: AdProviderTransactionID
    private let rewardedAt: Date
    private let handle: String
    private let customData: String

    init(
        attempt: RewardedAdAttempt,
        providerTransactionID: AdProviderTransactionID,
        rewardedAt: Date
    ) {
        self.attempt = attempt
        self.providerTransactionID = providerTransactionID
        self.rewardedAt = rewardedAt
        handle = "durable-test-handle-\(attempt.attemptID.uuidString)"
        customData = "durable-test-custom-\(attempt.attemptID.uuidString)"
    }

    func prepareChallenge(
        _ request: RewardedAdVerificationPreparationRequest
    ) -> RewardedAdVerificationPreparationResponse {
        RewardedAdVerificationPreparationResponse(
            attempt: request.attempt,
            verificationHandle: handle,
            providerCustomData: customData
        )
    }

    func verificationStatus(
        _: RewardedAdVerificationStatusRequest
    ) -> RewardedAdVerificationServerStatus {
        .verified(
            RewardedAdVerifiedServerResponse(
                attempt: attempt,
                verificationHandle: handle,
                providerCustomData: customData,
                uniqueProviderTransactionID: providerTransactionID.rawValue,
                rewardedAt: rewardedAt
            )
        )
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

    func purchaseAuthorized(
        productIdentifier: String,
        appAccountToken: UUID,
        finalAuthorization: @escaping @Sendable () async throws -> Void
    ) async throws -> StoreKit2PlatformPurchaseResult {
        try await finalAuthorization()
        try Task.checkCancellation()
        return .userCancelled
    }

    func unfinishedTransactions() -> [StoreKit2PlatformVerification] {
        unfinished
    }

    func transactionUpdates() -> StoreKit2OwnedUpdateListener<StoreKit2PlatformVerification> {
        let pair = AsyncStream<StoreKit2PlatformVerification>.makeStream()
        pair.continuation.finish()
        return StoreKit2OwnedUpdateListener(updates: pair.stream) {
            pair.continuation.finish()
        }
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

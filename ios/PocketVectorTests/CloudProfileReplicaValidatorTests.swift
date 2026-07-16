import XCTest

@testable import PocketVector

final class CloudProfileReplicaValidatorTests: XCTestCase, @unchecked Sendable {
    func testEmptyCompleteReplicaIsExplicitlyUninitialized() async throws {
        let fixture = try makeFixture(includeRun: false)
        let checkpoint = try fixture.checkpoint(records: [:])

        let state = try await fixture.validator().validate(checkpoint)
        XCTAssertEqual(state, .uninitialized)
    }

    func testCompleteReplicaWithUnconfirmedRunIsValidatedAsPending() async throws {
        let fixture = try makeFixture()
        let result = try await fixture.validator().validate(
            fixture.checkpoint()
        )
        guard case let .initialized(replica) = result else {
            return XCTFail("Expected initialized replica")
        }

        XCTAssertEqual(Set(replica.completedRunsByID.keys), [fixture.run.runID])
        XCTAssertEqual(replica.pendingGameplayRunIDs, [fixture.run.runID])
        XCTAssertTrue(replica.confirmedGameplayRunIDs.isEmpty)
        XCTAssertEqual(replica.inventory, InventoryRules.initialInventory())
    }

    func testConfigurationAccountAndScopeBindingsFailClosed() async throws {
        let fixture = try makeFixture()
        XCTAssertThrowsError(
            try fixture.validator(
                expectedBinding: CloudProfileBindingV1(
                    cloudAccountID: CloudAccountID("different"),
                    accountBinding: fixture.binding.accountBinding,
                    profileAccountIdentity: fixture.binding.profileAccountIdentity
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? CloudProfileReplicaValidatorConfigurationError,
                .expectedBindingAccountMismatch
            )
        }

        let colliding = try CloudProfileSchemaConfiguration(
            rootRecordType: fixture.economyConfiguration.recordType,
            settingsRecordType: "ProfileSettings",
            selectionRecordType: "ProfileSelection",
            runRecordType: "CompletedRun",
            payloadFieldName: "payload"
        )
        XCTAssertThrowsError(
            try fixture.validator(configuration: colliding)
        ) { error in
            XCTAssertEqual(
                error as? CloudProfileReplicaValidatorConfigurationError,
                .economyRecordTypeCollision(
                    fixture.economyConfiguration.recordType
                )
            )
        }

        let otherScope = CloudReplicaScopeFingerprint(
            rawValue: String(repeating: "b", count: 64)
        )
        await assertValidationError(.scopeMismatch) {
            try await fixture.validator(
                expectedScope: otherScope
            ).validate(fixture.checkpoint())
        }
    }

    func testEconomyHeadRecordIDCannotAliasProfileSingletons() throws {
        let fixture = try makeFixture()
        for singletonID in [
            fixture.configuration.rootRecordID,
            fixture.configuration.settingsRecordID,
            fixture.configuration.selectionRecordID,
        ] {
            let collidingEconomy = try DurableEconomyCloudConfiguration(
                recordID: singletonID,
                recordType: fixture.economyConfiguration.recordType,
                payloadFieldName: fixture.economyConfiguration.payloadFieldName
            )
            XCTAssertThrowsError(
                try fixture.validator(
                    economyConfiguration: collidingEconomy
                )
            ) { error in
                XCTAssertEqual(
                    error as? CloudProfileReplicaValidatorConfigurationError,
                    .economyRecordIDCollision(singletonID)
                )
            }
        }

        XCTAssertNoThrow(try fixture.validator())
    }

    func testUnknownTypeAndCloudFieldsAreRejected() async throws {
        let fixture = try makeFixture()
        var records = fixture.records
        records[CloudRecordID("unknown")] = fixture.record(
            id: CloudRecordID("unknown"),
            type: "FutureRecord",
            payload: ["value": "future"]
        )
        await assertValidationError(.unknownRecordType("FutureRecord")) {
            try await fixture.validator().validate(
                fixture.checkpoint(records: records)
            )
        }

        records = fixture.records
        let rootRecord = try XCTUnwrap(records[fixture.configuration.rootRecordID])
        records[rootRecord.id] = CloudRecord(
            id: rootRecord.id,
            recordType: rootRecord.recordType,
            fields: rootRecord.fields.merging(["future": Data("x".utf8)]) {
                current, _ in current
            },
            changeTag: rootRecord.changeTag
        )
        await assertValidationError(.unexpectedRecordFields(rootRecord.id)) {
            try await fixture.validator().validate(
                fixture.checkpoint(records: records)
            )
        }

        records = fixture.records
        var object = try XCTUnwrap(
            try JSONSerialization.jsonObject(
                with: try XCTUnwrap(
                    rootRecord.fields[fixture.configuration.payloadFieldName]
                )
            ) as? [String: Any]
        )
        object["futurePayloadField"] = true
        records[rootRecord.id] = CloudRecord(
            id: rootRecord.id,
            recordType: rootRecord.recordType,
            fields: [
                fixture.configuration.payloadFieldName:
                    try JSONSerialization.data(withJSONObject: object),
            ],
            changeTag: rootRecord.changeTag
        )
        await assertValidationError(.malformedPayload(rootRecord.id)) {
            try await fixture.validator().validate(
                fixture.checkpoint(records: records)
            )
        }
    }

    func testEveryStoredProfilePayloadMustUseExactCanonicalBytes() async throws {
        let fixture = try makeFixture()
        let runID = fixture.configuration.runRecordID(for: fixture.run.runID)
        for id in [
            fixture.configuration.rootRecordID,
            fixture.configuration.settingsRecordID,
            fixture.configuration.selectionRecordID,
            runID,
        ] {
            let record = try XCTUnwrap(fixture.records[id])
            let canonical = try XCTUnwrap(
                record.fields[fixture.configuration.payloadFieldName]
            )
            let object = try JSONSerialization.jsonObject(with: canonical)
            let prettyPrinted = try JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys]
            )
            XCTAssertNotEqual(prettyPrinted, canonical)
            await assertRawPayloadReplacement(
                fixture: fixture,
                id: id,
                payload: prettyPrinted,
                expected: .malformedPayload(id)
            )
        }
    }

    func testNoncanonicalKeyOrderAndNestedUnknownRunFieldAreRejected() async throws {
        let fixture = try makeFixture()
        let rootID = fixture.configuration.rootRecordID
        let rootPayload = try XCTUnwrap(
            fixture.records[rootID]?.fields[
                fixture.configuration.payloadFieldName
            ]
        )
        let rootObject = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: rootPayload)
                as? [String: Any]
        )
        let reverseOrdered = try reverseOrderedJSON(rootObject)
        XCTAssertNotEqual(reverseOrdered, rootPayload)
        await assertRawPayloadReplacement(
            fixture: fixture,
            id: rootID,
            payload: reverseOrdered,
            expected: .malformedPayload(rootID)
        )

        let runID = fixture.configuration.runRecordID(for: fixture.run.runID)
        let runPayload = try XCTUnwrap(
            fixture.records[runID]?.fields[
                fixture.configuration.payloadFieldName
            ]
        )
        var payloadObject = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: runPayload)
                as? [String: Any]
        )
        var recordObject = try XCTUnwrap(
            payloadObject["record"] as? [String: Any]
        )
        var runObject = try XCTUnwrap(recordObject["run"] as? [String: Any])
        var configurationObject = try XCTUnwrap(
            runObject["configuration"] as? [String: Any]
        )
        configurationObject["futureNestedField"] = "ignored-by-synthesized-decoder"
        runObject["configuration"] = configurationObject
        recordObject["run"] = runObject
        payloadObject["record"] = recordObject
        let nestedUnknown = try JSONSerialization.data(
            withJSONObject: payloadObject,
            options: [.sortedKeys]
        )
        await assertRawPayloadReplacement(
            fixture: fixture,
            id: runID,
            payload: nestedUnknown,
            expected: .malformedPayload(runID)
        )
    }

    func testEveryProfileRecordTypeIsBoundToItsDeterministicSingletonID() async throws {
        let fixture = try makeFixture()
        for id in [
            fixture.configuration.rootRecordID,
            fixture.configuration.settingsRecordID,
            fixture.configuration.selectionRecordID,
            fixture.economyConfiguration.recordID,
        ] {
            var records = fixture.records
            let record = try XCTUnwrap(records[id])
            records[id] = CloudRecord(
                id: id,
                recordType: "WrongType",
                fields: record.fields,
                changeTag: record.changeTag
            )
            await assertValidationError(.recordTypeMismatch(id)) {
                try await fixture.validator().validate(
                    fixture.checkpoint(records: records)
                )
            }
        }
    }

    func testEveryV1PayloadSchemaAndBindingIsChecked() async throws {
        let fixture = try makeFixture()

        let wrongRoot = CloudProfileRootV1(
            schemaVersion: 99,
            binding: fixture.binding,
            economyHeadRecordID: fixture.economyConfiguration.recordID,
            rootRevision: 1,
            runAccumulator: try fixture.runAccumulator(for: [fixture.run])
        )
        await assertReplacement(
            fixture: fixture,
            id: fixture.configuration.rootRecordID,
            payload: wrongRoot,
            expected: .schemaVersionMismatch(fixture.configuration.rootRecordID)
        )

        let wrongSettings = CloudProfileSettingsV1(
            schemaVersion: 99,
            binding: fixture.binding,
            stamp: fixture.stamp,
            settings: PlayerSettings()
        )
        await assertReplacement(
            fixture: fixture,
            id: fixture.configuration.settingsRecordID,
            payload: wrongSettings,
            expected: .schemaVersionMismatch(fixture.configuration.settingsRecordID)
        )

        let wrongSelection = CloudProfileSelectionV1(
            schemaVersion: 99,
            binding: fixture.binding,
            stamp: fixture.stamp,
            selection: InventoryRules.initialSelection()
        )
        await assertReplacement(
            fixture: fixture,
            id: fixture.configuration.selectionRecordID,
            payload: wrongSelection,
            expected: .schemaVersionMismatch(fixture.configuration.selectionRecordID)
        )

        let wrongRun = CloudProfileCompletedRunV1(
            schemaVersion: 99,
            binding: fixture.binding,
            record: fixture.run.record,
            rewardedRunObservation: fixture.run.rewardedRunObservation
        )
        let runRecordID = fixture.configuration.runRecordID(for: fixture.run.runID)
        await assertReplacement(
            fixture: fixture,
            id: runRecordID,
            payload: wrongRun,
            expected: .schemaVersionMismatch(runRecordID)
        )

        let otherBinding = CloudProfileBindingV1(
            cloudAccountID: fixture.accountID,
            accountBinding: DurableAccountBinding(
                accountKey: ServiceAccountKey("other-service-account"),
                profileID: fixture.binding.accountBinding.profileID
            ),
            profileAccountIdentity: fixture.binding.profileAccountIdentity
        )
        let rootBindingMismatch = CloudProfileRootV1(
            binding: otherBinding,
            economyHeadRecordID: fixture.economyConfiguration.recordID,
            rootRevision: 1,
            runAccumulator: try fixture.runAccumulator(for: [fixture.run])
        )
        await assertReplacement(
            fixture: fixture,
            id: fixture.configuration.rootRecordID,
            payload: rootBindingMismatch,
            expected: .bindingMismatch(fixture.configuration.rootRecordID)
        )

        let settingsBindingMismatch = CloudProfileSettingsV1(
            binding: otherBinding,
            stamp: fixture.stamp,
            settings: PlayerSettings()
        )
        await assertReplacement(
            fixture: fixture,
            id: fixture.configuration.settingsRecordID,
            payload: settingsBindingMismatch,
            expected: .bindingMismatch(fixture.configuration.settingsRecordID)
        )

        let selectionBindingMismatch = CloudProfileSelectionV1(
            binding: otherBinding,
            stamp: fixture.stamp,
            selection: InventoryRules.initialSelection()
        )
        await assertReplacement(
            fixture: fixture,
            id: fixture.configuration.selectionRecordID,
            payload: selectionBindingMismatch,
            expected: .bindingMismatch(fixture.configuration.selectionRecordID)
        )

        let runBindingMismatch = CloudProfileCompletedRunV1(
            binding: otherBinding,
            record: fixture.run.record,
            rewardedRunObservation: fixture.run.rewardedRunObservation
        )
        await assertReplacement(
            fixture: fixture,
            id: runRecordID,
            payload: runBindingMismatch,
            expected: .bindingMismatch(runRecordID)
        )

        let headSchemaMismatch = DurableEconomyCoordinator.CloudAccountHeadV3(
            schemaVersion: 99,
            cloudAccountID: fixture.binding.cloudAccountID,
            accountBinding: fixture.binding.accountBinding,
            profileAccountIdentity: fixture.binding.profileAccountIdentity,
            revision: 0,
            ledgerAccumulator: .empty,
            unlockedItemIDs: [],
            rewardedAd: .initial
        )
        await assertReplacement(
            fixture: fixture,
            id: fixture.economyConfiguration.recordID,
            payload: headSchemaMismatch,
            expected: .schemaVersionMismatch(
                fixture.economyConfiguration.recordID
            )
        )

        let headBindingMismatch = DurableEconomyCoordinator.CloudAccountHeadV3(
            schemaVersion: DurableEconomyCoordinator.CloudAccountHeadV3.schemaVersion,
            cloudAccountID: fixture.binding.cloudAccountID,
            accountBinding: otherBinding.accountBinding,
            profileAccountIdentity: fixture.binding.profileAccountIdentity,
            revision: 0,
            ledgerAccumulator: .empty,
            unlockedItemIDs: [],
            rewardedAd: .initial
        )
        await assertReplacement(
            fixture: fixture,
            id: fixture.economyConfiguration.recordID,
            payload: headBindingMismatch,
            expected: .bindingMismatch(fixture.economyConfiguration.recordID)
        )
    }

    func testMissingSingletonsAndRootEconomyBindingAreRejected() async throws {
        let fixture = try makeFixture()
        let cases: [
            (CloudRecordID, CloudProfileReplicaValidationError)
        ] = [
            (fixture.configuration.rootRecordID, .missingProfileRoot),
            (fixture.configuration.settingsRecordID, .missingSettings),
            (fixture.configuration.selectionRecordID, .missingSelection),
            (fixture.economyConfiguration.recordID, .missingEconomyHead),
        ]
        for (id, expected) in cases {
            var records = fixture.records
            records[id] = nil
            await assertValidationError(expected) {
                try await fixture.validator().validate(
                    fixture.checkpoint(records: records)
                )
            }
        }

        let wrongRoot = CloudProfileRootV1(
            binding: fixture.binding,
            economyHeadRecordID: CloudRecordID("different-economy-head"),
            rootRevision: 1,
            runAccumulator: try fixture.runAccumulator(for: [fixture.run])
        )
        await assertReplacement(
            fixture: fixture,
            id: fixture.configuration.rootRecordID,
            payload: wrongRoot,
            expected: .economyHeadRecordIDMismatch
        )
    }

    func testWrongRunIDRunCollisionAndRootAccumulatorMismatchAreRejected() async throws {
        let fixture = try makeFixture()
        let expectedRunID = fixture.configuration.runRecordID(for: fixture.run.runID)
        var records = fixture.records
        let original = try XCTUnwrap(records.removeValue(forKey: expectedRunID))
        let wrongID = CloudRecordID("profile-run-v1-wrong")
        records[wrongID] = CloudRecord(
            id: wrongID,
            recordType: original.recordType,
            fields: original.fields,
            changeTag: original.changeTag
        )
        await assertValidationError(
            .wrongDeterministicRecordID(expected: expectedRunID, actual: wrongID)
        ) {
            try await fixture.validator().validate(
                fixture.checkpoint(records: records)
            )
        }

        records = fixture.records
        let duplicateID = CloudRecordID("zzzz-duplicate-run")
        records[duplicateID] = CloudRecord(
            id: duplicateID,
            recordType: original.recordType,
            fields: original.fields,
            changeTag: CloudChangeTag("duplicate-tag")
        )
        await assertValidationError(.duplicateRunID(fixture.run.runID)) {
            try await fixture.validator().validate(
                fixture.checkpoint(records: records)
            )
        }

        let wrongAccumulatorRoot = CloudProfileRootV1(
            binding: fixture.binding,
            economyHeadRecordID: fixture.economyConfiguration.recordID,
            rootRevision: 1,
            runAccumulator: .empty
        )
        await assertReplacement(
            fixture: fixture,
            id: fixture.configuration.rootRecordID,
            payload: wrongAccumulatorRoot,
            expected: .runAccumulatorMismatch
        )
    }

    func testSemanticallyValidRunPayloadTamperBreaksRootCommitment() async throws {
        let fixture = try makeFixture()
        let altered = try fixture.makeRun(
            runID: fixture.run.runID,
            score: 2_000
        )

        await assertRunReplacement(
            fixture: fixture,
            run: altered,
            expected: .runAccumulatorMismatch,
            updateRootAccumulator: false
        )
    }

    func testRootRevisionMustCoverBootstrapStampsAndRunCount() async throws {
        let fixture = try makeFixture()
        let root = CloudProfileRootV1(
            binding: fixture.binding,
            economyHeadRecordID: fixture.economyConfiguration.recordID,
            rootRevision: 0,
            runAccumulator: try fixture.runAccumulator(for: [fixture.run])
        )
        await assertReplacement(
            fixture: fixture,
            id: fixture.configuration.rootRecordID,
            payload: root,
            expected: .rootRevisionInconsistent
        )
    }

    func testRunValidationAndRewardObservationCompletenessFailClosed() async throws {
        let fixture = try makeFixture()
        let invalid = try fixture.makeRun(
            runID: fixture.run.runID,
            score: CompletedRunValidator.maximumAcceptedScore + 1
        )
        await assertRunReplacement(
            fixture: fixture,
            run: invalid,
            expected: .invalidCompletedRun(invalid.runID)
        )

        let missingObservation = CloudProfileCompletedRunV1(
            binding: fixture.binding,
            record: fixture.run.record,
            rewardedRunObservation: nil
        )
        await assertRunReplacement(
            fixture: fixture,
            run: missingObservation,
            expected: .missingRewardedRunObservation(fixture.run.runID)
        )

        let abandoned = try fixture.makeRun(
            runID: fixture.run.runID,
            naturallyCompleted: false,
            observation: RewardedRunObservation(
                observedCycle: 0,
                disposition: .candidate
            )
        )
        await assertRunReplacement(
            fixture: fixture,
            run: abandoned,
            expected: .extraRewardedRunObservation(abandoned.runID)
        )
    }

    func testPendingRewardObservationsCannotClaimFutureEconomyCycle() async throws {
        let fixture = try makeFixture()
        for disposition in [
            RewardedRunObservation.Disposition.candidate,
            .ignoredWhileOfferPending,
        ] {
            let future = try fixture.makeRun(
                runID: fixture.run.runID,
                observation: RewardedRunObservation(
                    observedCycle: 1,
                    disposition: disposition
                )
            )
            await assertRunReplacement(
                fixture: fixture,
                run: future,
                expected: .invalidRewardedRunObservation(future.runID)
            )
        }
    }

    func testIgnoredPendingObservationRequiresPlausibleEqualCycleButAllowsStale()
        async throws
    {
        let fixture = try makeFixture()
        let ignoredAtZero = try fixture.makeRun(
            runID: fixture.run.runID,
            observation: RewardedRunObservation(
                observedCycle: 0,
                disposition: .ignoredWhileOfferPending
            )
        )
        await assertRunReplacement(
            fixture: fixture,
            run: ignoredAtZero,
            expected: .invalidRewardedRunObservation(ignoredAtZero.runID)
        )

        var activeRewardHead = DurableEconomyCoordinator.CloudRewardedAdHeadV1
            .initial
        for _ in 0 ..< PersistedEconomyRulesV1.rewardedAdRunThreshold {
            _ = try activeRewardHead.resolveGameplay(
                observation: RewardedRunObservation(
                    observedCycle: 0,
                    disposition: .candidate
                )
            )
        }
        let activeHead = fixture.economyHead(
            rewardedAd: activeRewardHead,
            revision: 5
        )
        let activeResult = try await fixture.validator().validate(
            fixture.checkpoint(
                records: try fixture.records(
                    replacingRun: ignoredAtZero,
                    economyHead: activeHead
                )
            )
        )
        guard case .initialized = activeResult else {
            return XCTFail("Equal-cycle ignored observation should be plausible")
        }

        try activeRewardHead.redeem(RewardedAdState.offerID(for: 0))
        let advancedHead = fixture.economyHead(
            rewardedAd: activeRewardHead,
            revision: 6
        )
        let staleResult = try await fixture.validator().validate(
            fixture.checkpoint(
                records: try fixture.records(
                    replacingRun: ignoredAtZero,
                    economyHead: advancedHead
                )
            )
        )
        guard case .initialized = staleResult else {
            return XCTFail("Stale ignored observation should remain valid")
        }
    }

    func testGameplayMarkerMustHaveExactRunAndRunWithoutMarkerRemainsPending() async throws {
        let fixture = try makeFixture()
        var records = fixture.records
        let marker = fixture.gameplayMarker(for: fixture.run)
        let markerID = CloudProfileEconomyMarkerRecordID.ledger(
            marker.record.entry.id,
            headRecordID: fixture.economyConfiguration.recordID
        )
        records[markerID] = fixture.economyRecord(id: markerID, payload: marker)
        let result = try await fixture.validator().validate(
            fixture.checkpoint(records: records)
        )
        guard case let .initialized(replica) = result else {
            return XCTFail("Expected initialized replica")
        }
        XCTAssertEqual(replica.confirmedGameplayRunIDs, [fixture.run.runID])
        XCTAssertTrue(replica.pendingGameplayRunIDs.isEmpty)

        let missingRunFixture = try makeFixture(includeRun: false)
        records = missingRunFixture.records
        records[markerID] = missingRunFixture.economyRecord(
            id: markerID,
            payload: marker
        )
        await assertValidationError(
            .gameplayMarkerWithoutRun(fixture.run.runID)
        ) {
            try await missingRunFixture.validator().validate(
                missingRunFixture.checkpoint(records: records)
            )
        }

        var mismatchedRecords = fixture.records
        let mismatchedMarker = fixture.gameplayMarker(
            for: fixture.run,
            delta: fixture.run.record.rewardCoins + 1
        )
        mismatchedRecords[markerID] = fixture.economyRecord(
            id: markerID,
            payload: mismatchedMarker
        )
        await assertValidationError(.gameplayMarkerMismatch(fixture.run.runID)) {
            try await fixture.validator().validate(
                fixture.checkpoint(records: mismatchedRecords)
            )
        }
    }

    func testTombstonesForAnyRequiredOrImmutableHistoryAreRejected() async throws {
        let fixture = try makeFixture()
        let locator = CloudProviderRecordLocator("deleted-run")
        let tombstone = CloudReplicaTombstone(
            locator: locator,
            logicalRecordID: CloudRecordID("profile-run-v1-deleted"),
            recordType: fixture.configuration.runRecordType
        )
        let checkpoint = try fixture.checkpoint(
            tombstones: [locator: tombstone]
        )

        await assertValidationError(.tombstonePresent(locator)) {
            try await fixture.validator().validate(checkpoint)
        }
    }

    func testEconomyVerifierFailurePropagatesWithoutBeingReclassified() async throws {
        let fixture = try makeFixture()
        let validator = try fixture.validator(
            verifier: CloudProfileCompleteEconomyHistoryVerifier { _ in
                throw EconomyVerifierStubError.rejected
            }
        )

        do {
            _ = try await validator.validate(fixture.checkpoint())
            XCTFail("Expected economy verifier rejection")
        } catch {
            XCTAssertEqual(error as? EconomyVerifierStubError, .rejected)
        }
    }

    func testEconomyMarkerAddressesExactlyMatchDurableCoordinator() async throws {
        let fixture = try makeFixture()
        let nonce = UUID(
            uuidString: "11111111-2222-4333-8444-555555555555"
        )!
        let profileSession = ProfileSessionToken(
            accountIdentity: fixture.binding.profileAccountIdentity,
            nonce: nonce,
            profileID: fixture.binding.accountBinding.profileID
        )
        let context = try DurableEconomySessionContext(
            cloudAccountID: fixture.accountID,
            accountBinding: fixture.binding.accountBinding,
            profileSession: profileSession,
            storeSession: StoreActiveSession(
                binding: StoreAccountBinding(
                    account: fixture.binding.accountBinding,
                    appAccountToken: UUID(
                        uuidString: "aaaaaaaa-1111-4222-8333-bbbbbbbbbbbb"
                    )!
                ),
                nonce: nonce
            )
        )
        let coordinator = DurableEconomyCoordinator(
            context: context,
            sessionAuthority: DurableEconomySessionAuthority(context: context),
            repository: MarkerAddressRepositoryStub(),
            cloud: InMemoryCloudSyncTransport(
                accountState: .available(fixture.accountID)
            ),
            configuration: fixture.economyConfiguration
        )
        let ledgerEntryID = LedgerEntryID("golden-ledger-entry")
        let offerID = RewardOfferID("golden-reward-offer")

        let writerLedgerID = await coordinator.ledgerMarkerRecordID(
            for: ledgerEntryID
        )
        let writerOfferID = await coordinator.rewardOfferMarkerRecordID(
            for: offerID
        )
        XCTAssertEqual(
            CloudProfileEconomyMarkerRecordID.ledger(
                ledgerEntryID,
                headRecordID: fixture.economyConfiguration.recordID
            ),
            writerLedgerID
        )
        XCTAssertEqual(
            CloudProfileEconomyMarkerRecordID.rewardOffer(
                offerID,
                headRecordID: fixture.economyConfiguration.recordID
            ),
            writerOfferID
        )
    }
}

private enum EconomyVerifierStubError: Error, Equatable {
    case rejected
}

private actor MarkerAddressRepositoryStub: DurableEconomyLocalPersisting {
    func durableEconomySnapshot() async throws -> LocalPlayerProfileSnapshot {
        fatalError("Marker address test never reads the repository")
    }

    func durableConfirmPendingCredits(
        _: Set<LedgerEntryID>,
        session _: ProfileSessionToken,
        confirmation _: DurableEconomyConfirmation,
        savedAt _: Date
    ) async throws -> LocalPlayerProfileSnapshot {
        fatalError("Marker address test never mutates the repository")
    }

    func durableRecordConfirmedCredit(
        _: CoinLedgerEntry,
        session _: ProfileSessionToken,
        confirmation _: DurableEconomyConfirmation,
        savedAt _: Date
    ) async throws -> LocalPlayerProfileSnapshot {
        fatalError("Marker address test never mutates the repository")
    }

    func durablePrepareUnlock(
        itemID _: CatalogItemID,
        operationID _: OperationID,
        session _: ProfileSessionToken
    ) async throws -> DurableCatalogUnlockRequest {
        fatalError("Marker address test never mutates the repository")
    }

    func durableApplyUnlock(
        using _: DurableCatalogUnlockReceipt,
        session _: ProfileSessionToken,
        at _: Date
    ) async throws -> CatalogUnlockOutcome {
        fatalError("Marker address test never mutates the repository")
    }

    func durableSettleRewardedAd(
        using _: DurableRewardedAdReceipt,
        session _: ProfileSessionToken,
        savedAt _: Date
    ) async throws -> RewardedAdSettlementOutcome {
        fatalError("Marker address test never mutates the repository")
    }
}

private struct CloudProfileValidatorFixture {
    let accountID = CloudAccountID("cloud-account")
    let scope = CloudReplicaScopeFingerprint(
        rawValue: String(repeating: "a", count: 64)
    )
    let configuration: CloudProfileSchemaConfiguration
    let economyConfiguration: DurableEconomyCloudConfiguration
    let binding: CloudProfileBindingV1
    let stamp: CloudProfileMergeStampV1
    let run: CloudProfileCompletedRunV1
    let records: [CloudRecordID: CloudRecord]

    func validator(
        configuration: CloudProfileSchemaConfiguration? = nil,
        economyConfiguration: DurableEconomyCloudConfiguration? = nil,
        expectedScope: CloudReplicaScopeFingerprint? = nil,
        expectedBinding: CloudProfileBindingV1? = nil,
        verifier: CloudProfileCompleteEconomyHistoryVerifier? = nil
    ) throws -> CloudProfileReplicaValidator {
        try CloudProfileReplicaValidator(
            configuration: configuration ?? self.configuration,
            economyConfiguration: economyConfiguration
                ?? self.economyConfiguration,
            expectedAccountID: accountID,
            expectedScopeFingerprint: expectedScope ?? scope,
            expectedBinding: expectedBinding ?? binding,
            economyVerifier: verifier ?? CloudProfileCompleteEconomyHistoryVerifier {
                history in history.head
            }
        )
    }

    func checkpoint(
        records: [CloudRecordID: CloudRecord]? = nil,
        tombstones: [CloudProviderRecordLocator: CloudReplicaTombstone] = [:]
    ) throws -> CloudReplicaCheckpointV1 {
        let records = records ?? self.records
        let locatorByID = Dictionary(
            uniqueKeysWithValues: records.keys.map { id in
                (id, CloudProviderRecordLocator("provider-\(id.rawValue)"))
            }
        )
        let idByLocator = Dictionary(
            uniqueKeysWithValues: locatorByID.map { ($0.value, $0.key) }
        )
        return try CloudReplicaCheckpointV1(
            accountID: accountID,
            configurationScopeFingerprint: scope,
            generation: 1,
            finalCursor: CloudChangeCursor(Data("cursor".utf8)),
            recordsByLogicalID: records,
            providerLocatorByLogicalID: locatorByID,
            logicalIDByProviderLocator: idByLocator,
            tombstonesByProviderLocator: tombstones,
            replicaEpoch: UUID(
                uuidString: "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
            )!
        )
    }

    func record<T: Encodable>(
        id: CloudRecordID,
        type: String,
        payload: T
    ) -> CloudRecord {
        CloudRecord(
            id: id,
            recordType: type,
            fields: [
                configuration.payloadFieldName:
                    try! CloudProfileCanonicalPayload.encode(payload),
            ],
            changeTag: CloudChangeTag("tag-\(id.rawValue)")
        )
    }

    func economyRecord<T: Encodable>(
        id: CloudRecordID,
        payload: T
    ) -> CloudRecord {
        CloudRecord(
            id: id,
            recordType: economyConfiguration.recordType,
            fields: [
                economyConfiguration.payloadFieldName: try! JSONEncoder().encode(
                    payload
                ),
            ],
            changeTag: CloudChangeTag("tag-\(id.rawValue)")
        )
    }

    func makeRun(
        runID: RunID,
        score: Int = 1_000,
        naturallyCompleted: Bool = true,
        observation: RewardedRunObservation? = RewardedRunObservation(
            observedCycle: 0,
            disposition: .candidate
        )
    ) throws -> CloudProfileCompletedRunV1 {
        let catalog = LaunchCatalog.approved
        let offense = catalog.team(id: LaunchTeamID.novaCityComets)!
        let defense = catalog.team(id: LaunchTeamID.highMesaHelions)!
        let startedAt = Date(timeIntervalSince1970: 1_000)
        let completed = CompletedRun(
            configuration: RunConfiguration(
                runID: runID,
                randomSeed: 42,
                offenseTeamID: offense.id,
                offenseJerseyID: offense.primaryJersey.id,
                defenseTeamID: defense.id,
                defenseJerseyID: defense.primaryJersey.id,
                footballID: LaunchFootballID.standard,
                economyVersion: 1,
                startedAt: startedAt
            ),
            endedAt: startedAt.addingTimeInterval(
                naturallyCompleted ? 60 : 30
            ),
            elapsedGameplayMilliseconds: naturallyCompleted ? 60_000 : 30_000,
            finishReason: naturallyCompleted ? .timerExpired : .abandoned,
            score: score,
            statistics: RunStatisticsSnapshot(
                attempts: naturallyCompleted ? 3 : 0,
                completions: naturallyCompleted ? 3 : 0,
                touchdowns: 0,
                incompletions: 0,
                interceptions: 0,
                longestTouchdownStreak: 0
            ),
            completedLaneIDs: [],
            bonusTouchdownCount: 0
        )
        return CloudProfileCompletedRunV1(
            binding: binding,
            record: CompletedRunRecord(
                run: completed,
                recordedAt: startedAt.addingTimeInterval(61),
                rewardCoins: try CompletedRunValidator.rewardCoins(for: completed)
            ),
            rewardedRunObservation: observation
        )
    }

    func gameplayMarker(
        for run: CloudProfileCompletedRunV1,
        delta: Int64? = nil
    ) -> DurableEconomyCoordinator.CloudLedgerMarkerV2 {
        let entryID = CoinLedgerID.gameplay(runID: run.runID)
        let binding = DurableEconomyCoordinator.MutationBinding(
            cloudAccountID: self.binding.cloudAccountID,
            accountBinding: self.binding.accountBinding,
            profileAccountIdentity: self.binding.profileAccountIdentity,
            profileSessionNonce: UUID(
                uuidString: "11111111-2222-4333-8444-555555555555"
            )!,
            sourceEconomyRevision: 0,
            operationID: OperationID("gameplay-operation"),
            kind: .pendingCredits
        )
        return DurableEconomyCoordinator.CloudLedgerMarkerV2(
            schemaVersion: DurableEconomyCoordinator.CloudLedgerMarkerV2
                .schemaVersion,
            headRecordID: economyConfiguration.recordID,
            record: DurableEconomyCoordinator.CloudLedgerRecord(
                entry: CoinLedgerEntry(
                    id: entryID,
                    delta: delta ?? run.record.rewardCoins,
                    reason: .gameplay(
                        runID: run.runID,
                        economyVersion: run.record.run.configuration.economyVersion
                    ),
                    createdAt: run.record.recordedAt
                ),
                binding: binding
            ),
            eventPosition: DurableEconomyCoordinator.CloudEconomyEventPosition(
                cloudHeadRevision: 1,
                batchIndex: 0
            ),
            gameplayRewardObservation: run.rewardedRunObservation,
            gameplayRewardResolution: .counted(
                cycle: 0,
                resultingCount: 1,
                unlockedOfferID: nil
            )
        )
    }

    func runAccumulator(
        for runs: [CloudProfileCompletedRunV1]
    ) throws -> CloudProfileRunAccumulatorV1 {
        try CloudProfileRunAccumulatorV1.make(for: runs.map { run in
            CloudProfileRunAccumulatorEntryV1(
                logicalRecordID: configuration.runRecordID(for: run.runID),
                canonicalPayload: try CloudProfileCanonicalPayload.encode(run)
            )
        })
    }

    func economyHead(
        rewardedAd: DurableEconomyCoordinator.CloudRewardedAdHeadV1,
        revision: UInt64
    ) -> DurableEconomyCoordinator.CloudAccountHeadV3 {
        DurableEconomyCoordinator.CloudAccountHeadV3(
            schemaVersion: DurableEconomyCoordinator.CloudAccountHeadV3
                .schemaVersion,
            cloudAccountID: binding.cloudAccountID,
            accountBinding: binding.accountBinding,
            profileAccountIdentity: binding.profileAccountIdentity,
            revision: revision,
            ledgerAccumulator: .empty,
            unlockedItemIDs: [],
            rewardedAd: rewardedAd
        )
    }

    func records(
        replacingRun run: CloudProfileCompletedRunV1,
        economyHead: DurableEconomyCoordinator.CloudAccountHeadV3
    ) throws -> [CloudRecordID: CloudRecord] {
        var next = records
        let runID = configuration.runRecordID(for: run.runID)
        next[runID] = record(
            id: runID,
            type: configuration.runRecordType,
            payload: run
        )
        let root = CloudProfileRootV1(
            binding: binding,
            economyHeadRecordID: economyConfiguration.recordID,
            rootRevision: 1,
            runAccumulator: try runAccumulator(for: [run])
        )
        next[configuration.rootRecordID] = record(
            id: configuration.rootRecordID,
            type: configuration.rootRecordType,
            payload: root
        )
        next[economyConfiguration.recordID] = economyRecord(
            id: economyConfiguration.recordID,
            payload: economyHead
        )
        return next
    }
}

private extension CloudProfileReplicaValidatorTests {
    func makeFixture(
        includeRun: Bool = true
    ) throws -> CloudProfileValidatorFixture {
        let configuration = try CloudProfileSchemaConfiguration(
            rootRecordType: "ProfileRoot",
            settingsRecordType: "ProfileSettings",
            selectionRecordType: "ProfileSelection",
            runRecordType: "CompletedRun",
            payloadFieldName: "payload"
        )
        let economyConfiguration = try DurableEconomyCloudConfiguration(
            recordID: CloudRecordID("economy-head"),
            recordType: "Economy",
            payloadFieldName: "payload"
        )
        let binding = CloudProfileBindingV1(
            cloudAccountID: CloudAccountID("cloud-account"),
            accountBinding: DurableAccountBinding(
                accountKey: ServiceAccountKey("service-account"),
                profileID: UUID(
                    uuidString: "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
                )!
            ),
            profileAccountIdentity: PlayerAccountIdentity("player-account")
        )
        let stamp = try CloudProfileMergeStampV1(
            logicalCounter: 1,
            deviceID: "device-a",
            modifiedAt: Date(timeIntervalSince1970: 1_100)
        )

        let shell = CloudProfileValidatorFixture(
            configuration: configuration,
            economyConfiguration: economyConfiguration,
            binding: binding,
            stamp: stamp,
            run: unsafePlaceholderRun(binding: binding),
            records: [:]
        )
        let run = try shell.makeRun(
            runID: RunID(
                UUID(uuidString: "44444444-4444-4444-8444-444444444444")!
            )
        )
        let runs = includeRun ? [run] : []
        let root = CloudProfileRootV1(
            binding: binding,
            economyHeadRecordID: economyConfiguration.recordID,
            rootRevision: 1,
            runAccumulator: try shell.runAccumulator(for: runs)
        )
        let settings = CloudProfileSettingsV1(
            binding: binding,
            stamp: stamp,
            settings: PlayerSettings()
        )
        let selection = CloudProfileSelectionV1(
            binding: binding,
            stamp: stamp,
            selection: InventoryRules.initialSelection()
        )
        let head = DurableEconomyCoordinator.CloudAccountHeadV3(
            schemaVersion: DurableEconomyCoordinator.CloudAccountHeadV3.schemaVersion,
            cloudAccountID: binding.cloudAccountID,
            accountBinding: binding.accountBinding,
            profileAccountIdentity: binding.profileAccountIdentity,
            revision: 0,
            ledgerAccumulator: .empty,
            unlockedItemIDs: [],
            rewardedAd: .initial
        )
        var records: [CloudRecordID: CloudRecord] = [
            configuration.rootRecordID: shell.record(
                id: configuration.rootRecordID,
                type: configuration.rootRecordType,
                payload: root
            ),
            configuration.settingsRecordID: shell.record(
                id: configuration.settingsRecordID,
                type: configuration.settingsRecordType,
                payload: settings
            ),
            configuration.selectionRecordID: shell.record(
                id: configuration.selectionRecordID,
                type: configuration.selectionRecordType,
                payload: selection
            ),
            economyConfiguration.recordID: shell.economyRecord(
                id: economyConfiguration.recordID,
                payload: head
            ),
        ]
        if includeRun {
            let id = configuration.runRecordID(for: run.runID)
            records[id] = shell.record(
                id: id,
                type: configuration.runRecordType,
                payload: run
            )
        }
        return CloudProfileValidatorFixture(
            configuration: configuration,
            economyConfiguration: economyConfiguration,
            binding: binding,
            stamp: stamp,
            run: run,
            records: records
        )
    }

    func unsafePlaceholderRun(
        binding: CloudProfileBindingV1
    ) -> CloudProfileCompletedRunV1 {
        let date = Date(timeIntervalSince1970: 0)
        return CloudProfileCompletedRunV1(
            binding: binding,
            record: CompletedRunRecord(
                run: CompletedRun(
                    configuration: RunConfiguration(
                        runID: RunID(
                            UUID(
                                uuidString:
                                "55555555-5555-4555-8555-555555555555"
                            )!
                        ),
                        randomSeed: 0,
                        offenseTeamID: LaunchTeamID.novaCityComets,
                        offenseJerseyID: LaunchCatalog.approved.teams[0]
                            .primaryJersey.id,
                        defenseTeamID: LaunchTeamID.highMesaHelions,
                        defenseJerseyID: LaunchCatalog.approved.teams[1]
                            .primaryJersey.id,
                        footballID: LaunchFootballID.standard,
                        economyVersion: 1,
                        startedAt: date
                    ),
                    endedAt: date,
                    elapsedGameplayMilliseconds: 0,
                    finishReason: .abandoned,
                    score: 0,
                    statistics: RunStatisticsSnapshot(),
                    completedLaneIDs: [],
                    bonusTouchdownCount: 0
                ),
                recordedAt: date,
                rewardCoins: 0
            ),
            rewardedRunObservation: nil
        )
    }

    func assertReplacement<T: Encodable>(
        fixture: CloudProfileValidatorFixture,
        id: CloudRecordID,
        payload: T,
        expected: CloudProfileReplicaValidationError
    ) async {
        var records = fixture.records
        guard let current = records[id] else {
            return XCTFail("Missing fixture record \(id)")
        }
        records[id] = current.recordType == fixture.economyConfiguration.recordType
            ? fixture.economyRecord(id: id, payload: payload)
            : fixture.record(id: id, type: current.recordType, payload: payload)
        await assertValidationError(expected) {
            try await fixture.validator().validate(
                fixture.checkpoint(records: records)
            )
        }
    }

    func assertRawPayloadReplacement(
        fixture: CloudProfileValidatorFixture,
        id: CloudRecordID,
        payload: Data,
        expected: CloudProfileReplicaValidationError
    ) async {
        var records = fixture.records
        guard let current = records[id] else {
            return XCTFail("Missing fixture record \(id)")
        }
        records[id] = CloudRecord(
            id: current.id,
            recordType: current.recordType,
            fields: [fixture.configuration.payloadFieldName: payload],
            changeTag: current.changeTag
        )
        await assertValidationError(expected) {
            try await fixture.validator().validate(
                fixture.checkpoint(records: records)
            )
        }
    }

    func assertRunReplacement(
        fixture: CloudProfileValidatorFixture,
        run: CloudProfileCompletedRunV1,
        expected: CloudProfileReplicaValidationError,
        updateRootAccumulator: Bool = true
    ) async {
        var records = fixture.records
        let id = fixture.configuration.runRecordID(for: run.runID)
        records[id] = fixture.record(
            id: id,
            type: fixture.configuration.runRecordType,
            payload: run
        )
        if updateRootAccumulator {
            let root = CloudProfileRootV1(
                binding: fixture.binding,
                economyHeadRecordID: fixture.economyConfiguration.recordID,
                rootRevision: 1,
                runAccumulator: try! fixture.runAccumulator(for: [run])
            )
            records[fixture.configuration.rootRecordID] = fixture.record(
                id: fixture.configuration.rootRecordID,
                type: fixture.configuration.rootRecordType,
                payload: root
            )
        }
        await assertValidationError(expected) {
            try await fixture.validator().validate(
                fixture.checkpoint(records: records)
            )
        }
    }

    func assertValidationError(
        _ expected: CloudProfileReplicaValidationError,
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            XCTFail("Expected \(expected)")
        } catch {
            XCTAssertEqual(error as? CloudProfileReplicaValidationError, expected)
        }
    }

    func reverseOrderedJSON(_ object: [String: Any]) throws -> Data {
        var result = Data("{".utf8)
        for (index, key) in object.keys.sorted(by: >).enumerated() {
            if index > 0 {
                result.append(Data(",".utf8))
            }
            result.append(try JSONEncoder().encode(key))
            result.append(Data(":".utf8))
            result.append(
                try JSONSerialization.data(
                    withJSONObject: object[key]!,
                    options: [.fragmentsAllowed, .sortedKeys]
                )
            )
        }
        result.append(Data("}".utf8))
        return result
    }
}

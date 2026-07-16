import XCTest

@testable import PocketVector

final class ServiceAccountBindingTests: XCTestCase {
    func testProfileDerivationFingerprintMaterialIsVersionedAndExact() {
        XCTAssertEqual(
            CloudAccountDerivedBindings.profileFingerprintMaterial,
            [
                "pocket-vector-private-cloud-account-binding-derivation-v1",
                "rootDomain",
                "pocket-vector-private-cloud-account-binding-v1",
                "playerIdentityDomain", "player-account-identity-v1",
                "serviceAccountKeyDomain", "service-account-key-v1",
                "profileIDDomain", "profile-id-v1",
                "digestAlgorithm", "sha256-v1",
                "componentEncoding",
                "uint64-big-endian-length-prefixed-utf8-components-v1",
                "hexEncoding", "lowercase-two-digit-hex-per-byte-v1",
                "uuidEncoding",
                "sha256-first-16-bytes-rfc9562-version-8-variant-v1",
                "serviceAccountKeyType", "ServiceAccountKey",
                "serviceAccountKeyEncoding", "single-value-raw-string-v1",
            ]
        )
    }

    func testServiceAccountKeyEncodingLabelMatchesProductionJSONShape() throws {
        let binding = DurableAccountBinding(
            accountKey: ServiceAccountKey("service-account-shape"),
            profileID: UUID(
                uuidString: "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
            )!
        )
        let payload = try DurableEconomyCloudSchema.makePayloadEncoder()
            .encode(binding)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: payload) as? [String: Any]
        )

        XCTAssertEqual(
            String(decoding: try JSONEncoder().encode(binding.accountKey), as: UTF8.self),
            "\"service-account-shape\""
        )
        XCTAssertEqual(
            object["accountKey"] as? String,
            binding.accountKey.rawValue
        )
        XCTAssertNil(object["accountKey"] as? [String: Any])
    }

    func testCloudAccountBindingsAreStableAcrossDerivations() {
        let accountID = CloudAccountID(String(repeating: "a", count: 64))

        XCTAssertEqual(
            CloudAccountDerivedBindings.derive(from: accountID),
            CloudAccountDerivedBindings.derive(from: accountID)
        )
    }

    func testCloudAccountBindingsMatchVersionedGoldenVector() {
        let bindings = CloudAccountDerivedBindings.derive(
            from: CloudAccountID(String(repeating: "a", count: 64))
        )

        XCTAssertEqual(
            bindings.playerAccountIdentity.rawValue,
            "abca1bfcb3fe2ea7cdc01adfd7276ccc5d7f031f1c13b9007728606b7d6d05d9"
        )
        XCTAssertEqual(
            bindings.durableAccountBinding.accountKey.rawValue,
            "8f178a3e9db0dee5e84ff5fb9b151eeed17539be23c917128dc79ff1e9058c41"
        )
        XCTAssertEqual(
            bindings.durableAccountBinding.profileID.uuidString.lowercased(),
            "cf32b6c9-4ed9-8efe-8ed3-b65ec181ac58"
        )
        XCTAssertEqual(
            bindings.storeAccountBinding.appAccountToken.uuidString.lowercased(),
            "9ed16459-4661-8ede-ba2e-cf53f38e4ebc"
        )
    }

    func testCloudAccountBindingsAreDomainSeparatedAndOpaque() {
        let rawAccountID = String(repeating: "private-account-value", count: 4)
        let bindings = CloudAccountDerivedBindings.derive(
            from: CloudAccountID(rawAccountID)
        )

        XCTAssertNotEqual(
            bindings.playerAccountIdentity.rawValue,
            bindings.durableAccountBinding.accountKey.rawValue
        )
        XCTAssertNotEqual(
            bindings.durableAccountBinding.profileID,
            bindings.storeAccountBinding.appAccountToken
        )
        XCTAssertFalse(bindings.playerAccountIdentity.rawValue.contains(rawAccountID))
        XCTAssertFalse(
            bindings.durableAccountBinding.accountKey.rawValue.contains(rawAccountID)
        )
        XCTAssertEqual(bindings.playerAccountIdentity.rawValue.count, 64)
        XCTAssertEqual(bindings.durableAccountBinding.accountKey.rawValue.count, 64)
        XCTAssertEqual(bindings.storeAccountBinding.account, bindings.durableAccountBinding)
    }

    func testDifferentCloudAccountsCannotShareOwnershipBindings() {
        let first = CloudAccountDerivedBindings.derive(
            from: CloudAccountID(String(repeating: "a", count: 64))
        )
        let second = CloudAccountDerivedBindings.derive(
            from: CloudAccountID(String(repeating: "b", count: 64))
        )

        XCTAssertNotEqual(first.playerAccountIdentity, second.playerAccountIdentity)
        XCTAssertNotEqual(first.durableAccountBinding, second.durableAccountBinding)
        XCTAssertNotEqual(first.storeAccountBinding, second.storeAccountBinding)
    }

    func testDerivedUUIDsUseApplicationDefinedVersionAndRFCVariant() {
        let bindings = CloudAccountDerivedBindings.derive(
            from: CloudAccountID(String(repeating: "c", count: 64))
        )

        for uuid in [
            bindings.durableAccountBinding.profileID,
            bindings.storeAccountBinding.appAccountToken,
        ] {
            let text = uuid.uuidString.lowercased()
            XCTAssertEqual(text[text.index(text.startIndex, offsetBy: 14)], "8")
            XCTAssertTrue(
                ["8", "9", "a", "b"].contains(
                    String(text[text.index(text.startIndex, offsetBy: 19)])
                )
            )
        }
    }

    func testGenerationActivationBindsExactAccountScopeEpochAndDerivedOwnership() async throws {
        let factory = LockedUUIDSequence([uuid(1), uuid(2)])
        let authority = CloudAccountGenerationAuthority(
            tokenUUIDFactory: { factory.next() }
        )
        let accountID = account("a")
        let scope = scope("1")
        let replicaEpoch = uuid(101)

        let first = try await authority.activate(
            accountID: accountID,
            configurationScopeFingerprint: scope,
            replicaEpoch: replicaEpoch
        )
        let duplicate = try await authority.activate(
            accountID: accountID,
            configurationScopeFingerprint: scope,
            replicaEpoch: replicaEpoch
        )

        XCTAssertEqual(first, duplicate)
        XCTAssertEqual(first.accountID, accountID)
        XCTAssertEqual(
            first.derivedBindings,
            CloudAccountDerivedBindings.derive(from: accountID)
        )
        XCTAssertEqual(first.configurationScopeFingerprint, scope)
        XCTAssertEqual(first.replicaEpoch, replicaEpoch)
        XCTAssertEqual(factory.callCount, 1)
    }

    func testEveryCompletedAccountScopeOrEpochTransitionMintsFreshToken() async throws {
        let factory = LockedUUIDSequence((1 ... 8).map(uuid))
        let authority = CloudAccountGenerationAuthority(
            tokenUUIDFactory: { factory.next() }
        )
        let accountA = account("a")
        let accountB = account("b")
        let scopeA = scope("1")
        let scopeB = scope("2")
        let epochA = uuid(101)
        let epochB = uuid(102)

        let initial = try await authority.activate(
            accountID: accountA,
            configurationScopeFingerprint: scopeA,
            replicaEpoch: epochA
        )
        let epochChanged = try await authority.activate(
            accountID: accountA,
            configurationScopeFingerprint: scopeA,
            replicaEpoch: epochB
        )
        let scopeChanged = try await authority.activate(
            accountID: accountA,
            configurationScopeFingerprint: scopeB,
            replicaEpoch: epochB
        )
        let accountChanged = try await authority.activate(
            accountID: accountB,
            configurationScopeFingerprint: scopeB,
            replicaEpoch: epochB
        )
        let accountReturned = try await authority.activate(
            accountID: accountA,
            configurationScopeFingerprint: scopeA,
            replicaEpoch: epochA
        )
        try await authority.invalidate(accountReturned)
        let afterInvalidation = try await authority.activate(
            accountID: accountA,
            configurationScopeFingerprint: scopeA,
            replicaEpoch: epochA
        )

        let tokens = [
            initial.token,
            epochChanged.token,
            scopeChanged.token,
            accountChanged.token,
            accountReturned.token,
            afterInvalidation.token,
        ]
        XCTAssertEqual(Set(tokens).count, tokens.count)
        XCTAssertEqual(factory.callCount, tokens.count)
    }

    func testNewAuthorityInstanceScopesTokenEvenWhenFactoryUUIDIsIdentical() async throws {
        let repeatedUUID = uuid(201)
        let firstAuthority = CloudAccountGenerationAuthority(
            tokenUUIDFactory: { repeatedUUID }
        )
        let secondAuthority = CloudAccountGenerationAuthority(
            tokenUUIDFactory: { repeatedUUID }
        )
        let accountID = account("a")
        let scope = scope("1")
        let epoch = uuid(202)

        let first = try await firstAuthority.activate(
            accountID: accountID,
            configurationScopeFingerprint: scope,
            replicaEpoch: epoch
        )
        let second = try await secondAuthority.activate(
            accountID: accountID,
            configurationScopeFingerprint: scope,
            replicaEpoch: epoch
        )

        XCTAssertNotEqual(first.token, second.token)
        XCTAssertNotEqual(first, second)
        do {
            let _: Int = try await secondAuthority.withCurrentGeneration(first) { _ in 1 }
            XCTFail("A generation from another authority must be rejected")
        } catch {
            XCTAssertEqual(
                error as? CloudAccountGenerationAuthorityError,
                .generationNotCurrent
            )
        }
        let accepted: Int = try await secondAuthority.withCurrentGeneration(second) { _ in 2 }
        XCTAssertEqual(accepted, 2)
    }

    func testStaleCASInvalidationCannotClearNewerGeneration() async throws {
        let factory = LockedUUIDSequence([uuid(301), uuid(302), uuid(303)])
        let authority = CloudAccountGenerationAuthority(
            tokenUUIDFactory: { factory.next() }
        )
        let first = try await activate(
            authority,
            account: account("a"),
            scope: scope("1"),
            epoch: uuid(304)
        )
        let second = try await activate(
            authority,
            account: account("b"),
            scope: scope("1"),
            epoch: uuid(304)
        )

        do {
            try await authority.invalidate(first)
            XCTFail("Stale invalidation must fail")
        } catch {
            XCTAssertEqual(
                error as? CloudAccountGenerationAuthorityError,
                .generationNotCurrent
            )
        }
        let value: Int = try await authority.withCurrentGeneration(second) { _ in 7 }
        XCTAssertEqual(value, 7)

        try await authority.invalidate(second)
        do {
            try await authority.invalidate(second)
            XCTFail("Invalidating without an active generation must fail")
        } catch {
            XCTAssertEqual(
                error as? CloudAccountGenerationAuthorityError,
                .noActiveGeneration
            )
        }
        let reactivated = try await activate(
            authority,
            account: account("b"),
            scope: scope("1"),
            epoch: uuid(304)
        )
        XCTAssertNotEqual(reactivated.token, second.token)
    }

    func testZeroAndPreviouslyIssuedFactoryOutputPreserveActiveGeneration() async throws {
        let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
        let firstIdentifier = uuid(401)
        let factory = LockedUUIDSequence([
            firstIdentifier,
            zero,
            firstIdentifier,
            uuid(402),
        ])
        let authority = CloudAccountGenerationAuthority(
            tokenUUIDFactory: { factory.next() }
        )
        let first = try await activate(
            authority,
            account: account("a"),
            scope: scope("1"),
            epoch: uuid(403)
        )

        do {
            _ = try await activate(
                authority,
                account: account("b"),
                scope: scope("1"),
                epoch: uuid(403)
            )
            XCTFail("A zero token identifier must fail")
        } catch {
            XCTAssertEqual(
                error as? CloudAccountGenerationAuthorityError,
                .tokenFactoryReturnedZero
            )
        }
        let afterZero: Int = try await authority.withCurrentGeneration(first) { _ in 1 }
        XCTAssertEqual(afterZero, 1)

        do {
            _ = try await activate(
                authority,
                account: account("b"),
                scope: scope("1"),
                epoch: uuid(403)
            )
            XCTFail("Reusing any previously issued identifier must fail")
        } catch {
            XCTAssertEqual(
                error as? CloudAccountGenerationAuthorityError,
                .tokenFactoryCollision
            )
        }
        let afterCollision: Int = try await authority.withCurrentGeneration(first) { _ in 2 }
        XCTAssertEqual(afterCollision, 2)

        let second = try await activate(
            authority,
            account: account("b"),
            scope: scope("1"),
            epoch: uuid(403)
        )
        XCTAssertNotEqual(second.token, first.token)
        XCTAssertEqual(factory.callCount, 4)
    }

    func testIssuedTokenHistoryHasExplicitBoundWithoutReplacingCurrentState() async throws {
        let factory = LockedUUIDSequence([uuid(501), uuid(502), uuid(503)])
        let authority = CloudAccountGenerationAuthority(
            maximumIssuedTokenCount: 2,
            tokenUUIDFactory: { factory.next() }
        )
        _ = try await activate(
            authority,
            account: account("a"),
            scope: scope("1"),
            epoch: uuid(504)
        )
        let second = try await activate(
            authority,
            account: account("b"),
            scope: scope("1"),
            epoch: uuid(504)
        )
        let duplicate = try await activate(
            authority,
            account: account("b"),
            scope: scope("1"),
            epoch: uuid(504)
        )
        XCTAssertEqual(duplicate, second)

        do {
            _ = try await activate(
                authority,
                account: account("c"),
                scope: scope("1"),
                epoch: uuid(504)
            )
            XCTFail("Token history must fail closed at its configured bound")
        } catch {
            XCTAssertEqual(
                error as? CloudAccountGenerationAuthorityError,
                .tokenHistoryLimitReached
            )
        }
        XCTAssertEqual(factory.callCount, 2)
        let preserved: Int = try await authority.withCurrentGeneration(second) { _ in 9 }
        XCTAssertEqual(preserved, 9)
    }

    func testWithCurrentGenerationRejectsStaleGenerationBeforeBodyRuns() async throws {
        let factory = LockedUUIDSequence([uuid(601), uuid(602)])
        let authority = CloudAccountGenerationAuthority(
            tokenUUIDFactory: { factory.next() }
        )
        let stale = try await activate(
            authority,
            account: account("a"),
            scope: scope("1"),
            epoch: uuid(603)
        )
        let current = try await activate(
            authority,
            account: account("b"),
            scope: scope("1"),
            epoch: uuid(603)
        )
        let recorder = InvocationRecorder()

        do {
            let _: Int = try await authority.withCurrentGeneration(stale) { _ in
                await recorder.record()
                return 1
            }
            XCTFail("A stale generation body must not run")
        } catch {
            XCTAssertEqual(
                error as? CloudAccountGenerationAuthorityError,
                .generationNotCurrent
            )
        }
        let invocationCount = await recorder.value
        XCTAssertEqual(invocationCount, 0)
        let accepted: Int = try await authority.withCurrentGeneration(current) { _ in 2 }
        XCTAssertEqual(accepted, 2)
    }

    func testCommitGateRunsQueuedActivationsInFIFOOrderAcrossSuspension() async throws {
        let factory = LockedUUIDSequence([uuid(701), uuid(702), uuid(703)])
        let authority = CloudAccountGenerationAuthority(
            tokenUUIDFactory: { factory.next() }
        )
        let first = try await activate(
            authority,
            account: account("a"),
            scope: scope("1"),
            epoch: uuid(704)
        )
        let blocker = ControlledCommitBody(result: 17)
        let bodyTask = Task {
            try await authority.withCurrentGeneration(first) { _ in
                try await blocker.run()
            }
        }
        let bodyEntered = await waitUntil { await blocker.hasEntered }
        XCTAssertTrue(bodyEntered)

        let secondAccount = account("b")
        let sharedScope = scope("1")
        let sharedEpoch = uuid(704)
        let secondTask = Task {
            try await authority.activate(
                accountID: secondAccount,
                configurationScopeFingerprint: sharedScope,
                replicaEpoch: sharedEpoch
            )
        }
        let secondQueued = await waitUntil {
            await authority.queuedCommitOperationCount() == 1
        }
        XCTAssertTrue(secondQueued)
        let thirdAccount = account("c")
        let thirdTask = Task {
            try await authority.activate(
                accountID: thirdAccount,
                configurationScopeFingerprint: sharedScope,
                replicaEpoch: sharedEpoch
            )
        }
        let thirdQueued = await waitUntil {
            await authority.queuedCommitOperationCount() == 2
        }
        XCTAssertTrue(thirdQueued)

        await blocker.release()
        let bodyResult = try await bodyTask.value
        XCTAssertEqual(bodyResult, 17)
        let second = try await secondTask.value
        let third = try await thirdTask.value
        XCTAssertNotEqual(second.token, third.token)
        XCTAssertEqual(factory.callCount, 3)
        let final: String = try await authority.withCurrentGeneration(third) { _ in "third" }
        XCTAssertEqual(final, "third")
    }

    func testCommitGateOrdersActivationBeforeLaterStaleInvalidation() async throws {
        let factory = LockedUUIDSequence([uuid(801), uuid(802)])
        let authority = CloudAccountGenerationAuthority(
            tokenUUIDFactory: { factory.next() }
        )
        let first = try await activate(
            authority,
            account: account("a"),
            scope: scope("1"),
            epoch: uuid(803)
        )
        let blocker = ControlledCommitBody(result: 1)
        let bodyTask = Task {
            try await authority.withCurrentGeneration(first) { _ in
                try await blocker.run()
            }
        }
        let bodyEntered = await waitUntil { await blocker.hasEntered }
        XCTAssertTrue(bodyEntered)

        let secondAccount = account("b")
        let sharedScope = scope("1")
        let sharedEpoch = uuid(803)
        let activationTask = Task {
            try await authority.activate(
                accountID: secondAccount,
                configurationScopeFingerprint: sharedScope,
                replicaEpoch: sharedEpoch
            )
        }
        let activationQueued = await waitUntil {
            await authority.queuedCommitOperationCount() == 1
        }
        XCTAssertTrue(activationQueued)
        let invalidationTask = Task { try await authority.invalidate(first) }
        let invalidationQueued = await waitUntil {
            await authority.queuedCommitOperationCount() == 2
        }
        XCTAssertTrue(invalidationQueued)

        await blocker.release()
        _ = try await bodyTask.value
        let second = try await activationTask.value
        do {
            try await invalidationTask.value
            XCTFail("FIFO invalidation must observe the preceding activation")
        } catch {
            XCTAssertEqual(
                error as? CloudAccountGenerationAuthorityError,
                .generationNotCurrent
            )
        }
        let preserved: Int = try await authority.withCurrentGeneration(second) { _ in 2 }
        XCTAssertEqual(preserved, 2)
    }

    func testThrowingCommitBodyPreservesBodyErrorAndReleasesGate() async throws {
        let factory = LockedUUIDSequence([uuid(901), uuid(902)])
        let authority = CloudAccountGenerationAuthority(
            tokenUUIDFactory: { factory.next() }
        )
        let first = try await activate(
            authority,
            account: account("a"),
            scope: scope("1"),
            epoch: uuid(903)
        )

        do {
            let _: Int = try await authority.withCurrentGeneration(first) { _ in
                throw ExpectedCommitBodyError.failure
            }
            XCTFail("The body error must escape unchanged")
        } catch {
            XCTAssertEqual(error as? ExpectedCommitBodyError, .failure)
        }

        let second = try await activate(
            authority,
            account: account("b"),
            scope: scope("1"),
            epoch: uuid(903)
        )
        let accepted: Int = try await authority.withCurrentGeneration(second) { _ in 4 }
        XCTAssertEqual(accepted, 4)
    }

    func testCancellingRunningCommitBodyReleasesGateForQueuedActivation() async throws {
        let factory = LockedUUIDSequence([uuid(1_001), uuid(1_002)])
        let authority = CloudAccountGenerationAuthority(
            tokenUUIDFactory: { factory.next() }
        )
        let first = try await activate(
            authority,
            account: account("a"),
            scope: scope("1"),
            epoch: uuid(1_003)
        )
        let blocker = ControlledCommitBody(result: 1)
        let bodyTask = Task {
            try await authority.withCurrentGeneration(first) { _ in
                try await blocker.run()
            }
        }
        let bodyEntered = await waitUntil { await blocker.hasEntered }
        XCTAssertTrue(bodyEntered)
        let secondAccount = account("b")
        let sharedScope = scope("1")
        let sharedEpoch = uuid(1_003)
        let activationTask = Task {
            try await authority.activate(
                accountID: secondAccount,
                configurationScopeFingerprint: sharedScope,
                replicaEpoch: sharedEpoch
            )
        }
        let activationQueued = await waitUntil {
            await authority.queuedCommitOperationCount() == 1
        }
        XCTAssertTrue(activationQueued)

        bodyTask.cancel()
        do {
            _ = try await bodyTask.value
            XCTFail("Cancellation must escape the commit body")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        let second = try await activationTask.value
        let accepted: Int = try await authority.withCurrentGeneration(second) { _ in 5 }
        XCTAssertEqual(accepted, 5)
    }

    func testCancellationDuringSuccessfulNonCooperativeCommitPreservesSuccess() async throws {
        let factory = LockedUUIDSequence([uuid(1_051), uuid(1_052)])
        let authority = CloudAccountGenerationAuthority(
            tokenUUIDFactory: { factory.next() }
        )
        let first = try await activate(
            authority,
            account: account("a"),
            scope: scope("1"),
            epoch: uuid(1_053)
        )
        let body = NonCooperativeCommitBody(result: 41)
        let bodyTask = Task {
            try await authority.withCurrentGeneration(first) { _ in
                await body.run()
            }
        }
        let bodyEntered = await waitUntil { await body.hasEntered }
        XCTAssertTrue(bodyEntered)

        let secondAccount = account("b")
        let sharedScope = scope("1")
        let sharedEpoch = uuid(1_053)
        let activationTask = Task {
            try await authority.activate(
                accountID: secondAccount,
                configurationScopeFingerprint: sharedScope,
                replicaEpoch: sharedEpoch
            )
        }
        let activationQueued = await waitUntil {
            await authority.queuedCommitOperationCount() == 1
        }
        XCTAssertTrue(activationQueued)

        bodyTask.cancel()
        await body.releaseToPerformSideEffect()
        let result = try await bodyTask.value
        XCTAssertEqual(result, 41)
        let sideEffectCompleted = await body.sideEffectCompleted
        XCTAssertTrue(sideEffectCompleted)

        let second = try await activationTask.value
        let accepted: Int = try await authority.withCurrentGeneration(second) { _ in 6 }
        XCTAssertEqual(accepted, 6)
    }

    func testCancellingQueuedActivationRemovesItPromptlyWithoutMinting() async throws {
        let factory = LockedUUIDSequence([uuid(1_101), uuid(1_102)])
        let authority = CloudAccountGenerationAuthority(
            tokenUUIDFactory: { factory.next() }
        )
        let first = try await activate(
            authority,
            account: account("a"),
            scope: scope("1"),
            epoch: uuid(1_103)
        )
        let blocker = ControlledCommitBody(result: 1)
        let bodyTask = Task {
            try await authority.withCurrentGeneration(first) { _ in
                try await blocker.run()
            }
        }
        let bodyEntered = await waitUntil { await blocker.hasEntered }
        XCTAssertTrue(bodyEntered)
        let secondAccount = account("b")
        let sharedScope = scope("1")
        let sharedEpoch = uuid(1_103)
        let cancelledActivation = Task {
            try await authority.activate(
                accountID: secondAccount,
                configurationScopeFingerprint: sharedScope,
                replicaEpoch: sharedEpoch
            )
        }
        let activationQueued = await waitUntil {
            await authority.queuedCommitOperationCount() == 1
        }
        XCTAssertTrue(activationQueued)

        cancelledActivation.cancel()
        let cancellationDrained = await waitUntil {
            await authority.queuedCommitOperationCount() == 0
        }
        XCTAssertTrue(cancellationDrained)
        do {
            _ = try await cancelledActivation.value
            XCTFail("A cancelled waiter must not acquire the gate")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(factory.callCount, 1)

        await blocker.release()
        _ = try await bodyTask.value
        let second = try await activate(
            authority,
            account: account("b"),
            scope: scope("1"),
            epoch: uuid(1_103)
        )
        XCTAssertNotEqual(second.token, first.token)
        XCTAssertEqual(factory.callCount, 2)
    }

    func testCancellingFIFOHeadPreservesQueuedSuccessorWithoutMinting() async throws {
        let factory = LockedUUIDSequence([uuid(1_201), uuid(1_202)])
        let authority = CloudAccountGenerationAuthority(
            tokenUUIDFactory: { factory.next() }
        )
        let first = try await activate(
            authority,
            account: account("a"),
            scope: scope("1"),
            epoch: uuid(1_203)
        )
        let blocker = ControlledCommitBody(result: 1)
        let ownerTask = Task {
            try await authority.withCurrentGeneration(first) { _ in
                try await blocker.run()
            }
        }
        let ownerEntered = await waitUntil { await blocker.hasEntered }
        XCTAssertTrue(ownerEntered)

        let cancelledAccount = account("b")
        let successorAccount = account("c")
        let sharedScope = scope("1")
        let sharedEpoch = uuid(1_203)
        let cancelledActivation = Task {
            try await authority.activate(
                accountID: cancelledAccount,
                configurationScopeFingerprint: sharedScope,
                replicaEpoch: sharedEpoch
            )
        }
        let cancelledQueuedFirst = await waitUntil {
            await authority.queuedCommitOperationCount() == 1
        }
        XCTAssertTrue(cancelledQueuedFirst)

        let successorActivation = Task {
            try await authority.activate(
                accountID: successorAccount,
                configurationScopeFingerprint: sharedScope,
                replicaEpoch: sharedEpoch
            )
        }
        let successorQueuedSecond = await waitUntil {
            await authority.queuedCommitOperationCount() == 2
        }
        XCTAssertTrue(successorQueuedSecond)

        cancelledActivation.cancel()
        let cancelledHeadRemoved = await waitUntil {
            await authority.queuedCommitOperationCount() == 1
        }
        XCTAssertTrue(cancelledHeadRemoved)
        do {
            _ = try await cancelledActivation.value
            XCTFail("The cancelled FIFO head must not acquire the gate")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        let mintCountWhileOwnerIsRunning = factory.callCount
        XCTAssertEqual(mintCountWhileOwnerIsRunning, 1)

        await blocker.release()
        let ownerResult = try await ownerTask.value
        XCTAssertEqual(ownerResult, 1)
        let successor = try await successorActivation.value
        let finalAccountID = successor.accountID
        XCTAssertEqual(finalAccountID, successorAccount)
        let current: Int = try await authority.withCurrentGeneration(successor) { _ in 12 }
        XCTAssertEqual(current, 12)
        let finalMintCount = factory.callCount
        XCTAssertEqual(finalMintCount, 2)
    }

    private func activate(
        _ authority: CloudAccountGenerationAuthority,
        account: CloudAccountID,
        scope: CloudReplicaScopeFingerprint,
        epoch: UUID
    ) async throws -> ActiveCloudAccountGeneration {
        try await authority.activate(
            accountID: account,
            configurationScopeFingerprint: scope,
            replicaEpoch: epoch
        )
    }

    private func account(_ character: Character) -> CloudAccountID {
        CloudAccountID(String(repeating: String(character), count: 64))
    }

    private func scope(_ character: Character) -> CloudReplicaScopeFingerprint {
        CloudReplicaScopeFingerprint(
            rawValue: String(repeating: String(character), count: 64)
        )
    }

    private func uuid(_ value: Int) -> UUID {
        UUID(
            uuidString: String(
                format: "00000000-0000-4000-8000-%012llx",
                UInt64(value)
            )
        )!
    }

    private func waitUntil(
        attempts: Int = 5_000,
        _ condition: @escaping @Sendable () async -> Bool
    ) async -> Bool {
        for _ in 0 ..< attempts {
            if await condition() { return true }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return false
    }
}

private enum ExpectedCommitBodyError: Error, Equatable {
    case failure
}

private final class LockedUUIDSequence: @unchecked Sendable {
    private let lock = NSLock()
    private let values: [UUID]
    private var index = 0

    init(_ values: [UUID]) {
        precondition(!values.isEmpty)
        self.values = values
    }

    func next() -> UUID {
        lock.lock()
        defer { lock.unlock() }
        precondition(index < values.count, "UUID test sequence exhausted")
        defer { index += 1 }
        return values[index]
    }

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return index
    }
}

private actor ControlledCommitBody {
    private let result: Int
    private(set) var hasEntered = false
    private var isReleased = false

    init(result: Int) {
        self.result = result
    }

    func run() async throws -> Int {
        hasEntered = true
        while !isReleased {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        return result
    }

    func release() {
        isReleased = true
    }
}

private actor InvocationRecorder {
    private(set) var value = 0

    func record() {
        value += 1
    }
}

private actor NonCooperativeCommitBody {
    private let result: Int
    private(set) var hasEntered = false
    private(set) var sideEffectCompleted = false
    private var isReleased = false

    init(result: Int) {
        self.result = result
    }

    func run() async -> Int {
        hasEntered = true
        while !isReleased {
            await Task.yield()
        }
        sideEffectCompleted = true
        return result
    }

    func releaseToPerformSideEffect() {
        isReleased = true
    }
}

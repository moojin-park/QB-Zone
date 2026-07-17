import XCTest

@testable import PocketVector

@MainActor
final class RewardedAdVerificationClientTests: XCTestCase {
    private let rewardedAt = Date(timeIntervalSince1970: 1_750_123_456)
    private let handle = "verification-handle-00000001"
    private let customData = "provider-custom-data-00000001"
    private let providerTransactionID = "provider-transaction-00000001"

    func testInitializationIsDormantAndPreparationBindsExactAttempt() async throws {
        let attempt = rewardedAttempt(index: 1)
        let transport = RewardedAdVerificationTestTransport(
            preparation: .success(preparationResponse(for: attempt)),
            status: .success(.pending)
        )
        let client = RewardedAdVerificationClient(testingTransport: transport)

        let initialPrepareCount = await transport.prepareRequestCount()
        let initialStatusCount = await transport.statusRequestCount()
        XCTAssertEqual(initialPrepareCount, 0)
        XCTAssertEqual(initialStatusCount, 0)

        let challenge = try await client.prepareChallenge(for: attempt)

        XCTAssertEqual(challenge.attempt, attempt)
        XCTAssertEqual(challenge.verificationHandle.transportValue, handle)
        XCTAssertEqual(challenge.providerCustomData.transportValue, customData)
        let finalPrepareCount = await transport.prepareRequestCount()
        let finalStatusCount = await transport.statusRequestCount()
        XCTAssertEqual(finalPrepareCount, 1)
        XCTAssertEqual(finalStatusCount, 0)
        let encodedChallenge = try JSONEncoder().encode(challenge)
        let encodedObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encodedChallenge)
                as? [String: Any]
        )
        XCTAssertEqual(
            Set(encodedObject.keys),
            Set([
                "schemaVersion",
                "attempt",
                "verificationHandle",
                "providerCustomData",
            ])
        )
        XCTAssertEqual(
            RewardedAdVerificationChallengeV1.persistedFieldManifest,
            "attempt,providerCustomData,schemaVersion,verificationHandle"
        )
        XCTAssertEqual(
            encodedObject["schemaVersion"] as? Int,
            RewardedAdVerificationChallengeV1.currentSchemaVersion
        )
        let restored = try JSONDecoder().decode(
            RewardedAdVerificationChallengeV1.self,
            from: encodedChallenge
        )
        XCTAssertEqual(restored, challenge)

        var wrongVersionObject = encodedObject
        wrongVersionObject["schemaVersion"] = 2
        let wrongVersionData = try JSONSerialization.data(
            withJSONObject: wrongVersionObject
        )
        XCTAssertThrowsError(try JSONDecoder().decode(
            RewardedAdVerificationChallengeV1.self,
            from: wrongVersionData
        )) {
            XCTAssertEqual(
                $0 as? RewardedAdVerificationError,
                .unsupportedChallengeVersion
            )
        }
    }

    func testPreparationRejectsEveryAttemptCorrelationMismatch() async {
        let attempt = rewardedAttempt(index: 2)
        let wrongBinding = RewardedAdAttempt(
            binding: rewardedAttempt(index: 20).binding,
            presentationSessionNonce: attempt.presentationSessionNonce,
            offerID: attempt.offerID,
            attemptID: attempt.attemptID
        )
        let wrongSession = RewardedAdAttempt(
            binding: attempt.binding,
            presentationSessionNonce: uuid(2_001),
            offerID: attempt.offerID,
            attemptID: attempt.attemptID
        )
        let wrongOffer = RewardedAdAttempt(
            binding: attempt.binding,
            presentationSessionNonce: attempt.presentationSessionNonce,
            offerID: RewardOfferID("reward-offer-wrong"),
            attemptID: attempt.attemptID
        )
        let wrongAttemptID = RewardedAdAttempt(
            binding: attempt.binding,
            presentationSessionNonce: attempt.presentationSessionNonce,
            offerID: attempt.offerID,
            attemptID: uuid(2_002)
        )

        for mismatchedAttempt in [wrongBinding, wrongSession, wrongOffer, wrongAttemptID] {
            let transport = RewardedAdVerificationTestTransport(
                preparation: .success(preparationResponse(for: mismatchedAttempt)),
                status: .success(.pending)
            )
            let client = RewardedAdVerificationClient(testingTransport: transport)
            await assertVerificationError(.preparationMismatch) {
                try await client.prepareChallenge(for: attempt)
            }
        }
    }

    func testPreparationRejectsMalformedAndUnboundedOpaqueValues() async {
        let attempt = rewardedAttempt(index: 3)
        let malformedHandles = [
            "too-short",
            String(repeating: "h", count: 513),
            "verification handle contains spaces",
            "verification-handle-💥-0001",
        ]
        for malformedHandle in malformedHandles {
            let response = RewardedAdVerificationPreparationResponse(
                attempt: attempt,
                verificationHandle: malformedHandle,
                providerCustomData: customData
            )
            let client = RewardedAdVerificationClient(
                testingTransport: RewardedAdVerificationTestTransport(
                    preparation: .success(response),
                    status: .success(.pending)
                )
            )
            await assertVerificationError(.malformedVerificationHandle) {
                try await client.prepareChallenge(for: attempt)
            }
        }

        let malformedCustomData = [
            "too-short",
            String(repeating: "c", count: 513),
            "provider custom data contains spaces",
            "provider-custom-💥-0001",
        ]
        for malformedValue in malformedCustomData {
            let response = RewardedAdVerificationPreparationResponse(
                attempt: attempt,
                verificationHandle: handle,
                providerCustomData: malformedValue
            )
            let client = RewardedAdVerificationClient(
                testingTransport: RewardedAdVerificationTestTransport(
                    preparation: .success(response),
                    status: .success(.pending)
                )
            )
            await assertVerificationError(.malformedProviderCustomData) {
                try await client.prepareChallenge(for: attempt)
            }
        }
    }

    func testPendingAndTerminalRejectionNeverMintClaim() async throws {
        let attempt = rewardedAttempt(index: 4)
        let transport = RewardedAdVerificationTestTransport(
            preparation: .success(preparationResponse(for: attempt)),
            status: .success(.pending)
        )
        let client = RewardedAdVerificationClient(testingTransport: transport)
        let challenge = try await client.prepareChallenge(for: attempt)

        let pending = try await client.verificationStatus(for: challenge)
        guard case .pending = pending else {
            return XCTFail("Pending verification must not mint a claim")
        }

        await transport.setStatus(.success(.terminalRejected(.providerRejected)))
        let rejected = try await client.verificationStatus(for: challenge)
        guard case let .terminalRejected(reason) = rejected else {
            return XCTFail("Terminal rejection must not mint a claim")
        }
        XCTAssertEqual(reason, .providerRejected)
    }

    func testVerifiedStatusMintsProcessClaimWithExactServerTimestamp() async throws {
        let attempt = rewardedAttempt(index: 5)
        let transport = RewardedAdVerificationTestTransport(
            preparation: .success(preparationResponse(for: attempt)),
            status: .success(.verified(verifiedResponse(for: attempt)))
        )
        let client = RewardedAdVerificationClient(testingTransport: transport)
        let challenge = try await client.prepareChallenge(for: attempt)

        let firstStatus = try await client.verificationStatus(for: challenge)
        let secondStatus = try await client.verificationStatus(for: challenge)
        let first = try verifiedClaim(from: firstStatus)
        let second = try verifiedClaim(from: secondStatus)

        XCTAssertEqual(first.receipt.binding, attempt.binding)
        XCTAssertEqual(first.receipt.offerID, attempt.offerID)
        XCTAssertEqual(first.receipt.attemptID, attempt.attemptID)
        XCTAssertEqual(
            first.receipt.providerTransactionID,
            AdProviderTransactionID(providerTransactionID)
        )
        XCTAssertEqual(first.receipt.rewardedAt, rewardedAt)
        XCTAssertEqual(first.challenge, challenge)
        XCTAssertEqual(first.receipt, second.receipt)
        XCTAssertNotEqual(first, second, "Each successful status check mints new process authority")

        let session = profileSession(for: attempt)
        let request = try first.durableDeliveryRequest(
            session: session,
            currentBinding: attempt.binding
        )
        XCTAssertEqual(request.session, session)
        XCTAssertEqual(request.verifiedBinding, attempt.binding)
        XCTAssertEqual(request.offerID, attempt.offerID)
        XCTAssertEqual(
            request.providerTransactionID,
            AdProviderTransactionID(providerTransactionID)
        )
        XCTAssertEqual(request.rewardedAt, rewardedAt)
    }

    func testVerifiedStatusRejectsEveryCorrelationMismatch() async throws {
        let attempt = rewardedAttempt(index: 6)
        let transport = RewardedAdVerificationTestTransport(
            preparation: .success(preparationResponse(for: attempt)),
            status: .success(.pending)
        )
        let client = RewardedAdVerificationClient(testingTransport: transport)
        let challenge = try await client.prepareChallenge(for: attempt)

        let wrongAttempts = [
            RewardedAdAttempt(
                binding: rewardedAttempt(index: 60).binding,
                presentationSessionNonce: attempt.presentationSessionNonce,
                offerID: attempt.offerID,
                attemptID: attempt.attemptID
            ),
            RewardedAdAttempt(
                binding: attempt.binding,
                presentationSessionNonce: uuid(6_001),
                offerID: attempt.offerID,
                attemptID: attempt.attemptID
            ),
            RewardedAdAttempt(
                binding: attempt.binding,
                presentationSessionNonce: attempt.presentationSessionNonce,
                offerID: RewardOfferID("reward-offer-wrong"),
                attemptID: attempt.attemptID
            ),
            RewardedAdAttempt(
                binding: attempt.binding,
                presentationSessionNonce: attempt.presentationSessionNonce,
                offerID: attempt.offerID,
                attemptID: uuid(6_002)
            ),
        ]
        var mismatchedResponses = wrongAttempts.map { verifiedResponse(for: $0) }
        mismatchedResponses.append(
            RewardedAdVerifiedServerResponse(
                attempt: attempt,
                verificationHandle: "different-verification-handle-0001",
                providerCustomData: customData,
                uniqueProviderTransactionID: providerTransactionID,
                rewardedAt: rewardedAt
            )
        )
        mismatchedResponses.append(
            RewardedAdVerifiedServerResponse(
                attempt: attempt,
                verificationHandle: handle,
                providerCustomData: "different-provider-custom-data-0001",
                uniqueProviderTransactionID: providerTransactionID,
                rewardedAt: rewardedAt
            )
        )

        for response in mismatchedResponses {
            await transport.setStatus(.success(.verified(response)))
            await assertVerificationError(.statusMismatch) {
                try await client.verificationStatus(for: challenge)
            }
        }
    }

    func testVerifiedStatusRejectsMalformedTransactionAndNonFiniteTimestamp() async throws {
        let attempt = rewardedAttempt(index: 7)
        let transport = RewardedAdVerificationTestTransport(
            preparation: .success(preparationResponse(for: attempt)),
            status: .success(.pending)
        )
        let client = RewardedAdVerificationClient(testingTransport: transport)
        let challenge = try await client.prepareChallenge(for: attempt)

        for malformedID in [
            "",
            String(repeating: "p", count: 257),
            "provider transaction contains spaces",
            "provider-transaction-💥",
        ] {
            await transport.setStatus(.success(.verified(
                RewardedAdVerifiedServerResponse(
                    attempt: attempt,
                    verificationHandle: handle,
                    providerCustomData: customData,
                    uniqueProviderTransactionID: malformedID,
                    rewardedAt: rewardedAt
                )
            )))
            await assertVerificationError(.malformedProviderTransactionID) {
                try await client.verificationStatus(for: challenge)
            }
        }

        await transport.setStatus(.success(.verified(
            RewardedAdVerifiedServerResponse(
                attempt: attempt,
                verificationHandle: handle,
                providerCustomData: customData,
                uniqueProviderTransactionID: providerTransactionID,
                rewardedAt: Date(timeIntervalSince1970: .infinity)
            )
        )))
        await assertVerificationError(.nonFiniteRewardedAt) {
            try await client.verificationStatus(for: challenge)
        }
    }

    func testTransportFailuresNeverMintClaim() async throws {
        let attempt = rewardedAttempt(index: 8)
        let preparationFailure = RewardedAdVerificationTestTransport(
            preparation: .failure(.offline),
            status: .success(.pending)
        )
        let preparationClient = RewardedAdVerificationClient(
            testingTransport: preparationFailure
        )
        await assertVerificationError(.transportUnavailable) {
            try await preparationClient.prepareChallenge(for: attempt)
        }

        let statusFailure = RewardedAdVerificationTestTransport(
            preparation: .success(preparationResponse(for: attempt)),
            status: .failure(.offline)
        )
        let statusClient = RewardedAdVerificationClient(
            testingTransport: statusFailure
        )
        let challenge = try await statusClient.prepareChallenge(for: attempt)
        await assertVerificationError(.transportUnavailable) {
            try await statusClient.verificationStatus(for: challenge)
        }
    }

    func testProcessClaimRebindsSameOwnerAcrossSessionsAndRejectsCrossOwner() async throws {
        let attempt = rewardedAttempt(index: 9)
        let transport = RewardedAdVerificationTestTransport(
            preparation: .success(preparationResponse(for: attempt)),
            status: .success(.verified(verifiedResponse(for: attempt)))
        )
        let client = RewardedAdVerificationClient(testingTransport: transport)
        let challenge = try await client.prepareChallenge(for: attempt)
        let status = try await client.verificationStatus(for: challenge)
        let claim = try verifiedClaim(from: status)

        let sessionA1 = profileSession(for: attempt)
        let sessionA2 = ProfileSessionToken(
            accountIdentity: sessionA1.accountIdentity,
            nonce: uuid(9_002),
            profileID: attempt.binding.profileID
        )
        let sessionA3 = ProfileSessionToken(
            accountIdentity: sessionA1.accountIdentity,
            nonce: uuid(9_003),
            profileID: attempt.binding.profileID
        )
        XCTAssertNotEqual(sessionA1.nonce, sessionA2.nonce)
        XCTAssertNotEqual(sessionA1.nonce, sessionA3.nonce)

        for currentSession in [sessionA2, sessionA3] {
            let request = try claim.durableDeliveryRequest(
                session: currentSession,
                currentBinding: attempt.binding
            )
            XCTAssertEqual(request.session, currentSession)
            XCTAssertEqual(request.verifiedBinding, attempt.binding)
            XCTAssertEqual(request.offerID, attempt.offerID)
            XCTAssertEqual(
                request.providerTransactionID,
                AdProviderTransactionID(providerTransactionID)
            )
            XCTAssertEqual(request.rewardedAt, rewardedAt)
        }

        let wrongAccountBinding = DurableAccountBinding(
            accountKey: ServiceAccountKey("different-account"),
            profileID: attempt.binding.profileID
        )
        XCTAssertThrowsError(try claim.durableDeliveryRequest(
            session: sessionA2,
            currentBinding: wrongAccountBinding
        )) {
            XCTAssertEqual(
                $0 as? RewardedAdVerificationError,
                .durableOwnerMismatch
            )
        }

        let wrongProfileBinding = DurableAccountBinding(
            accountKey: attempt.binding.accountKey,
            profileID: uuid(9_004)
        )
        let wrongProfileSession = ProfileSessionToken(
            accountIdentity: sessionA1.accountIdentity,
            nonce: uuid(9_005),
            profileID: wrongProfileBinding.profileID
        )
        XCTAssertThrowsError(try claim.durableDeliveryRequest(
            session: wrongProfileSession,
            currentBinding: wrongProfileBinding
        )) {
            XCTAssertEqual(
                $0 as? RewardedAdVerificationError,
                .durableOwnerMismatch
            )
        }

        XCTAssertThrowsError(try claim.durableDeliveryRequest(
            session: wrongProfileSession,
            currentBinding: attempt.binding
        )) {
            XCTAssertEqual(
                $0 as? RewardedAdVerificationError,
                .profileSessionMismatch
            )
        }
    }

    private func rewardedAttempt(index: Int) -> RewardedAdAttempt {
        RewardedAdAttempt(
            binding: DurableAccountBinding(
                accountKey: ServiceAccountKey("verification-account-\(index)"),
                profileID: uuid(index * 10 + 1)
            ),
            presentationSessionNonce: uuid(index * 10 + 2),
            offerID: RewardOfferID("reward-offer-\(index)"),
            attemptID: uuid(index * 10 + 3)
        )
    }

    private func profileSession(
        for attempt: RewardedAdAttempt
    ) -> ProfileSessionToken {
        ProfileSessionToken(
            accountIdentity: PlayerAccountIdentity("test-player"),
            nonce: attempt.presentationSessionNonce,
            profileID: attempt.binding.profileID
        )
    }

    private func preparationResponse(
        for attempt: RewardedAdAttempt
    ) -> RewardedAdVerificationPreparationResponse {
        RewardedAdVerificationPreparationResponse(
            attempt: attempt,
            verificationHandle: handle,
            providerCustomData: customData
        )
    }

    private func verifiedResponse(
        for attempt: RewardedAdAttempt
    ) -> RewardedAdVerifiedServerResponse {
        RewardedAdVerifiedServerResponse(
            attempt: attempt,
            verificationHandle: handle,
            providerCustomData: customData,
            uniqueProviderTransactionID: providerTransactionID,
            rewardedAt: rewardedAt
        )
    }

    private func verifiedClaim(
        from status: RewardedAdVerificationResult
    ) throws -> VerifiedRewardedAdClaim {
        guard case let .verified(claim) = status else {
            throw RewardedAdVerificationTestFailure.expectedVerifiedClaim
        }
        return claim
    }

    private func assertVerificationError<Value>(
        _ expected: RewardedAdVerificationError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () async throws -> Value
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(
                error as? RewardedAdVerificationError,
                expected,
                file: file,
                line: line
            )
        }
    }

    private func uuid(_ value: Int) -> UUID {
        UUID(
            uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", value))"
        )!
    }
}

private enum RewardedAdVerificationTestFailure: Error {
    case offline
    case expectedVerifiedClaim
}

private actor RewardedAdVerificationTestTransport: RewardedAdVerificationTransport {
    private var preparation:
        Result<RewardedAdVerificationPreparationResponse, RewardedAdVerificationTestFailure>
    private var status:
        Result<RewardedAdVerificationServerStatus, RewardedAdVerificationTestFailure>
    private var prepareRequests: [RewardedAdVerificationPreparationRequest] = []
    private var statusRequests: [RewardedAdVerificationStatusRequest] = []

    init(
        preparation:
            Result<RewardedAdVerificationPreparationResponse, RewardedAdVerificationTestFailure>,
        status:
            Result<RewardedAdVerificationServerStatus, RewardedAdVerificationTestFailure>
    ) {
        self.preparation = preparation
        self.status = status
    }

    func prepareChallenge(
        _ request: RewardedAdVerificationPreparationRequest
    ) throws -> RewardedAdVerificationPreparationResponse {
        prepareRequests.append(request)
        return try preparation.get()
    }

    func verificationStatus(
        _ request: RewardedAdVerificationStatusRequest
    ) throws -> RewardedAdVerificationServerStatus {
        statusRequests.append(request)
        return try status.get()
    }

    func setStatus(
        _ status:
            Result<RewardedAdVerificationServerStatus, RewardedAdVerificationTestFailure>
    ) {
        self.status = status
    }

    func prepareRequestCount() -> Int {
        prepareRequests.count
    }

    func statusRequestCount() -> Int {
        statusRequests.count
    }
}

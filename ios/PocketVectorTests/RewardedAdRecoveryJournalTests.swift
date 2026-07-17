import XCTest

@testable import PocketVector

@MainActor
final class RewardedAdRecoveryJournalTests: XCTestCase {
    private let rewardedAt = Date(timeIntervalSince1970: 1_750_123_456)

    func testInstallIsDormantCanonicalChallengeOnlyAndRelaunchRecovers() async throws {
        let fixture = try makeFixture(index: 1)
        defer { fixture.cleanup() }
        let transport = JournalVerificationTransport(
            preparation: preparation(for: fixture.attempt, index: 1),
            status: .pending
        )
        let client = RewardedAdVerificationClient(testingTransport: transport)
        let coordinator = makeCoordinator(for: fixture)

        let initiallyRecovered = try await coordinator.recoverPreparedChallenge(
            currentBinding: fixture.attempt.binding
        )
        XCTAssertNil(initiallyRecovered)
        let initialPrepareCount = await transport.prepareCount()
        let initialStatusCount = await transport.statusCount()
        XCTAssertEqual(initialPrepareCount, 0)
        XCTAssertEqual(initialStatusCount, 0)

        let challenge = try await client.prepareChallenge(for: fixture.attempt)
        let installed = try await coordinator.installPreparedChallenge(
            challenge,
            originalPresentationSession: fixture.attempt.presentationSession
        )
        XCTAssertEqual(installed.challenge, challenge)
        let installedPrepareCount = await transport.prepareCount()
        let installedStatusCount = await transport.statusCount()
        XCTAssertEqual(installedPrepareCount, 1)
        XCTAssertEqual(installedStatusCount, 0)

        let primary = try Data(contentsOf: fixture.primaryURL)
        let backup = try Data(contentsOf: fixture.backupURL)
        XCTAssertEqual(primary, backup)
        XCTAssertLessThanOrEqual(primary.count, 16 * 1_024)
        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: primary) as? [String: Any]
        )
        XCTAssertEqual(
            Set(root.keys),
            Set(["format", "schemaVersion", "challenge"])
        )
        XCTAssertEqual(
            RewardedAdRecoveryJournalV1.persistedFieldManifest,
            "challenge,format,schemaVersion"
        )
        let text = try XCTUnwrap(String(data: primary, encoding: .utf8))
        for forbidden in [
            "providerTransactionID", "rewardedAt", "commandSession",
            "settlement", "ledgerEntryID", "coins", "consent",
            "economyRevision", "settledProviderTransactionIDs",
        ] {
            XCTAssertFalse(text.contains(forbidden), forbidden)
        }

        let relaunched = makeCoordinator(for: fixture)
        let recoveredValue = try await relaunched.recoverPreparedChallenge(
            currentBinding: fixture.attempt.binding
        )
        let recovered = try XCTUnwrap(recoveredValue)
        XCTAssertEqual(recovered.challenge, challenge)
        let relaunchedStatusCount = await transport.statusCount()
        XCTAssertEqual(relaunchedStatusCount, 0)
    }

    func testSameChallengeInstallIsIdempotentAndDifferentAttemptIsBlocked() async throws {
        let fixture = try makeFixture(index: 2)
        defer { fixture.cleanup() }
        let challenge = try await preparedChallenge(for: fixture, index: 2)
        let coordinator = makeCoordinator(for: fixture)
        let first = try await coordinator.installPreparedChallenge(
            challenge,
            originalPresentationSession: fixture.attempt.presentationSession
        )
        let firstBytes = try Data(contentsOf: fixture.primaryURL)
        let second = try await coordinator.installPreparedChallenge(
            challenge,
            originalPresentationSession: fixture.attempt.presentationSession
        )
        XCTAssertEqual(first, second)
        XCTAssertEqual(try Data(contentsOf: fixture.primaryURL), firstBytes)

        let otherAttempt = attempt(index: 200, binding: fixture.attempt.binding)
        let otherChallenge = try await preparedChallenge(
            attempt: otherAttempt,
            index: 200
        )
        await assertJournalError(.journalAlreadyExists) {
            try await coordinator.installPreparedChallenge(
                otherChallenge,
                originalPresentationSession: otherAttempt.presentationSession
            )
        }
        XCTAssertEqual(try Data(contentsOf: fixture.primaryURL), firstBytes)
        XCTAssertEqual(try Data(contentsOf: fixture.backupURL), firstBytes)
    }

    func testInstallRequiresPinnedOwnerAndExactOriginalPresentationSessionWithoutIO() async throws {
        let fixture = try makeFixture(index: 3)
        defer { fixture.cleanup() }
        let challenge = try await preparedChallenge(for: fixture, index: 3)
        let coordinator = makeCoordinator(for: fixture)
        let wrongSession = ActiveAccountSession(
            binding: fixture.attempt.binding,
            nonce: uuid(3_999)
        )
        await assertJournalError(.presentationSessionMismatch) {
            try await coordinator.installPreparedChallenge(
                challenge,
                originalPresentationSession: wrongSession
            )
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.primaryURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.backupURL.path))

        let wrongBinding = binding(index: 333)
        let wrongAttempt = attempt(index: 333, binding: wrongBinding)
        let wrongChallenge = try await preparedChallenge(
            attempt: wrongAttempt,
            index: 333
        )
        await assertJournalError(.durableOwnerMismatch) {
            try await coordinator.installPreparedChallenge(
                wrongChallenge,
                originalPresentationSession: wrongAttempt.presentationSession
            )
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.primaryURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.backupURL.path))
    }

    func testImpossibleRewardOfferIDsAreRejectedBeforePersistence() async throws {
        for (offset, invalidOfferID) in [
            "reward-offer/1",
            "reward-cycle/01",
            "reward-cycle/-1",
            "reward-cycle/not-a-number",
            "reward-cycle/18446744073709551616",
        ].enumerated() {
            let fixture = try makeFixture(index: 40 + offset)
            defer { fixture.cleanup() }
            let invalidAttempt = RewardedAdAttempt(
                binding: fixture.attempt.binding,
                presentationSessionNonce: fixture.attempt.presentationSessionNonce,
                offerID: RewardOfferID(invalidOfferID),
                attemptID: fixture.attempt.attemptID
            )
            let challenge = try await preparedChallenge(
                attempt: invalidAttempt,
                index: 40 + offset
            )
            await assertJournalError(.invalidChallenge) {
                try await makeCoordinator(for: fixture).installPreparedChallenge(
                    challenge,
                    originalPresentationSession: invalidAttempt.presentationSession
                )
            }
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: fixture.primaryURL.path)
            )
        }
    }

    func testPendingAndTransportFailureKeepExactJournal() async throws {
        let fixture = try makeFixture(index: 5)
        defer { fixture.cleanup() }
        let transport = JournalVerificationTransport(
            preparation: preparation(for: fixture.attempt, index: 5),
            status: .pending
        )
        let client = RewardedAdVerificationClient(testingTransport: transport)
        let challenge = try await client.prepareChallenge(for: fixture.attempt)
        let coordinator = makeCoordinator(for: fixture)
        _ = try await coordinator.installPreparedChallenge(
            challenge,
            originalPresentationSession: fixture.attempt.presentationSession
        )
        let exact = try Data(contentsOf: fixture.primaryURL)

        let pending = try await client.checkedVerificationStatus(for: challenge)
        guard case .pending = try await coordinator.handleCheckedStatus(
            pending,
            currentBinding: fixture.attempt.binding
        ) else {
            return XCTFail("Expected pending")
        }
        assertExactCopies(exact, fixture: fixture)

        await transport.setFailure(.offline)
        do {
            _ = try await client.checkedVerificationStatus(for: challenge)
            XCTFail("Expected transport failure")
        } catch {
            XCTAssertEqual(
                error as? RewardedAdVerificationError,
                .transportUnavailable
            )
        }
        assertExactCopies(exact, fixture: fixture)
    }

    func testVerifiedStatusStaysChallengeOnlyAndRelaunchRepollsForFreshClaim() async throws {
        let fixture = try makeFixture(index: 6)
        defer { fixture.cleanup() }
        let transport = JournalVerificationTransport(
            preparation: preparation(for: fixture.attempt, index: 6),
            status: .verified(verifiedResponse(for: fixture.attempt, index: 6))
        )
        let client = RewardedAdVerificationClient(testingTransport: transport)
        let challenge = try await client.prepareChallenge(for: fixture.attempt)
        let coordinator = makeCoordinator(for: fixture)
        _ = try await coordinator.installPreparedChallenge(
            challenge,
            originalPresentationSession: fixture.attempt.presentationSession
        )
        let exact = try Data(contentsOf: fixture.primaryURL)

        let firstObservation = try await client.checkedVerificationStatus(
            for: challenge
        )
        let first = try verifiedClaim(
            from: await coordinator.handleCheckedStatus(
                firstObservation,
                currentBinding: fixture.attempt.binding
            )
        )
        assertExactCopies(exact, fixture: fixture)

        let recoveredValue = try await makeCoordinator(for: fixture)
            .recoverPreparedChallenge(
                currentBinding: fixture.attempt.binding
            )
        let recovered = try XCTUnwrap(
            recoveredValue
        )
        let secondObservation = try await client.checkedVerificationStatus(
            for: recovered.challenge
        )
        let second = try verifiedClaim(
            from: await coordinator.handleCheckedStatus(
                secondObservation,
                currentBinding: fixture.attempt.binding
            )
        )
        XCTAssertNotEqual(first, second)
        let statusCount = await transport.statusCount()
        XCTAssertEqual(statusCount, 2)
        assertExactCopies(exact, fixture: fixture)
        let text = try XCTUnwrap(String(data: exact, encoding: .utf8))
        XCTAssertFalse(text.contains("provider-transaction-6"))
        XCTAssertFalse(text.contains(String(rewardedAt.timeIntervalSince1970)))
    }

    func testTerminalRejectionRequiresCurrentOwnerAndDeletesExactCopies() async throws {
        let fixture = try makeFixture(index: 7)
        defer { fixture.cleanup() }
        let transport = JournalVerificationTransport(
            preparation: preparation(for: fixture.attempt, index: 7),
            status: .terminalRejected(.providerRejected)
        )
        let client = RewardedAdVerificationClient(testingTransport: transport)
        let challenge = try await client.prepareChallenge(for: fixture.attempt)
        let coordinator = makeCoordinator(for: fixture)
        _ = try await coordinator.installPreparedChallenge(
            challenge,
            originalPresentationSession: fixture.attempt.presentationSession
        )
        let observation = try await client.checkedVerificationStatus(for: challenge)
        let exact = try Data(contentsOf: fixture.primaryURL)

        await assertVerificationError(.durableOwnerMismatch) {
            try await coordinator.handleCheckedStatus(
                observation,
                currentBinding: self.binding(index: 700)
            )
        }
        assertExactCopies(exact, fixture: fixture)

        guard case .terminalRejected(.providerRejected) = try await coordinator
            .handleCheckedStatus(
                observation,
                currentBinding: fixture.attempt.binding
            ) else {
            return XCTFail("Expected terminal rejection")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.primaryURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.backupURL.path))
    }

    func testFreshVerifiedClaimMayRebindSessionAndDeletesOnlyAfterExactDurableSuccess() async throws {
        let cases: [(index: Int, mode: JournalDeliveryRecorder.Mode)] = [
            (80, .success(wasAlreadySettled: false)),
            (81, .success(wasAlreadySettled: true)),
            (82, .committedThenRefreshed),
        ]
        for testCase in cases {
            let index = testCase.index
            let fixture = try makeFixture(index: index)
            defer { fixture.cleanup() }
            let (coordinator, observation, claim) = try await installedVerified(
                fixture: fixture,
                index: index
            )
            let reboundSession = ProfileSessionToken(
                accountIdentity: fixture.playerAccountIdentity,
                nonce: uuid(index * 100 + 99),
                profileID: fixture.attempt.binding.profileID
            )
            let deliverer = JournalDeliveryRecorder(
                mode: testCase.mode,
                cloudAccountID: fixture.cloudAccountID
            )
            let result = try await coordinator.deliverVerifiedReward(
                checked: observation,
                currentSession: reboundSession,
                currentBinding: fixture.attempt.binding,
                using: deliverer
            )
            XCTAssertEqual(result.outcome.providerTransactionID, claim.receipt.providerTransactionID)
            if index == 82 {
                XCTAssertEqual(result.cloudReceipt.status, .committedThenRefreshed)
            }
            let deliveredSessions = await deliverer.requests().map(\.session)
            XCTAssertEqual(deliveredSessions, [reboundSession])
            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.primaryURL.path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.backupURL.path))
        }
    }

    func testDeliveryFailureMismatchAndCrossOwnerNeverDeleteJournal() async throws {
        let fixture = try makeFixture(index: 9)
        defer { fixture.cleanup() }
        let (coordinator, observation, _) = try await installedVerified(
            fixture: fixture,
            index: 9
        )
        let exact = try Data(contentsOf: fixture.primaryURL)
        let session = profileSession(for: fixture, nonce: uuid(9_999))

        let failing = JournalDeliveryRecorder(
            mode: .failure,
            cloudAccountID: fixture.cloudAccountID
        )
        do {
            _ = try await coordinator.deliverVerifiedReward(
                checked: observation,
                currentSession: session,
                currentBinding: fixture.attempt.binding,
                using: failing
            )
            XCTFail("Expected delivery failure")
        } catch JournalTestFailure.deliveryFailed {}
        assertExactCopies(exact, fixture: fixture)

        let mismatched = JournalDeliveryRecorder(
            mode: .mismatchedProvider,
            cloudAccountID: fixture.cloudAccountID
        )
        await assertJournalError(.deliveryResultMismatch) {
            try await coordinator.deliverVerifiedReward(
                checked: observation,
                currentSession: session,
                currentBinding: fixture.attempt.binding,
                using: mismatched
            )
        }
        assertExactCopies(exact, fixture: fixture)

        let neverCalled = JournalDeliveryRecorder(
            mode: .success(wasAlreadySettled: false),
            cloudAccountID: fixture.cloudAccountID
        )
        await assertVerificationError(.durableOwnerMismatch) {
            try await coordinator.deliverVerifiedReward(
                checked: observation,
                currentSession: session,
                currentBinding: self.binding(index: 999),
                using: neverCalled
            )
        }
        let neverCalledCount = await neverCalled.requests().count
        XCTAssertEqual(neverCalledCount, 0)
        assertExactCopies(exact, fixture: fixture)
    }

    func testEveryMismatchedSealedAcknowledgementKeepsExactJournal() async throws {
        let fixture = try makeFixture(index: 91)
        defer { fixture.cleanup() }
        let (coordinator, observation, _) = try await installedVerified(
            fixture: fixture,
            index: 91
        )
        let exact = try Data(contentsOf: fixture.primaryURL)
        let session = profileSession(for: fixture, nonce: uuid(91_999))

        for tampering in JournalDeliveryRecorder.AcknowledgementTampering.allCases {
            let deliverer = JournalDeliveryRecorder(
                mode: .tamperedAcknowledgement(tampering),
                cloudAccountID: fixture.cloudAccountID
            )
            await assertJournalError(.deliveryResultMismatch) {
                try await coordinator.deliverVerifiedReward(
                    checked: observation,
                    currentSession: session,
                    currentBinding: fixture.attempt.binding,
                    using: deliverer
                )
            }
            assertExactCopies(
                exact,
                fixture: fixture,
                message: tampering.rawValue
            )
        }
    }

    func testOneValidCopyRepairsMissingAndCorruptCopyByteExactly() async throws {
        let fixture = try makeFixture(index: 10)
        defer { fixture.cleanup() }
        let challenge = try await preparedChallenge(for: fixture, index: 10)
        let coordinator = makeCoordinator(for: fixture)
        _ = try await coordinator.installPreparedChallenge(
            challenge,
            originalPresentationSession: fixture.attempt.presentationSession
        )
        let exact = try Data(contentsOf: fixture.primaryURL)

        try FileManager.default.removeItem(at: fixture.primaryURL)
        let missingRepairValue = try await coordinator.recoverPreparedChallenge(
            currentBinding: fixture.attempt.binding
        )
        let missingRepair = try XCTUnwrap(missingRepairValue)
        XCTAssertEqual(missingRepair.report.source, .backup)
        XCTAssertTrue(missingRepair.report.repairedMissingOrInvalidCopy)
        assertExactCopies(exact, fixture: fixture)

        let corrupt = Data("{\"corrupt\":true}".utf8)
        try corrupt.write(to: fixture.backupURL, options: .atomic)
        let corruptRepairValue = try await coordinator.recoverPreparedChallenge(
            currentBinding: fixture.attempt.binding
        )
        let corruptRepair = try XCTUnwrap(corruptRepairValue)
        XCTAssertEqual(corruptRepair.report.source, .primary)
        XCTAssertTrue(corruptRepair.report.repairedMissingOrInvalidCopy)
        let quarantinedURL = try XCTUnwrap(
            corruptRepair.report.quarantinedURLs.first
        )
        XCTAssertEqual(try Data(contentsOf: quarantinedURL), corrupt)
        assertExactCopies(exact, fixture: fixture)
    }

    func testDuplicateUnknownNoncanonicalAndUnsafeJSONAreQuarantinedBeforeDecode() async throws {
        let mutations: [(String, (Data) throws -> Data)] = [
            ("duplicate-escaped-root", { data in
                let text = try XCTUnwrap(String(data: data, encoding: .utf8))
                return Data(text.replacingOccurrences(
                    of: "{\"challenge\"",
                    with: "{\"\\u0066ormat\":\"com.pocketvector.rewarded-ad-recovery\",\"challenge\""
                ).utf8)
            }),
            ("unknown-root", { data in
                var object = try XCTUnwrap(
                    JSONSerialization.jsonObject(with: data) as? [String: Any]
                )
                object["verified"] = true
                return try JSONSerialization.data(
                    withJSONObject: object,
                    options: [.sortedKeys, .withoutEscapingSlashes]
                )
            }),
            ("unknown-attempt", { data in
                var root = try XCTUnwrap(
                    JSONSerialization.jsonObject(with: data) as? [String: Any]
                )
                var challenge = try XCTUnwrap(root["challenge"] as? [String: Any])
                var attempt = try XCTUnwrap(challenge["attempt"] as? [String: Any])
                attempt["currentSession"] = "must-not-persist"
                challenge["attempt"] = attempt
                root["challenge"] = challenge
                return try JSONSerialization.data(
                    withJSONObject: root,
                    options: [.sortedKeys, .withoutEscapingSlashes]
                )
            }),
            ("noncanonical-whitespace", { data in
                var text = try XCTUnwrap(String(data: data, encoding: .utf8))
                text.append("\n")
                return Data(text.utf8)
            }),
            ("empty-account-key", { data in
                var root = try XCTUnwrap(
                    JSONSerialization.jsonObject(with: data) as? [String: Any]
                )
                var challenge = try XCTUnwrap(root["challenge"] as? [String: Any])
                var attempt = try XCTUnwrap(challenge["attempt"] as? [String: Any])
                var binding = try XCTUnwrap(attempt["binding"] as? [String: Any])
                binding["accountKey"] = ""
                attempt["binding"] = binding
                challenge["attempt"] = attempt
                root["challenge"] = challenge
                return try JSONSerialization.data(
                    withJSONObject: root,
                    options: [.sortedKeys, .withoutEscapingSlashes]
                )
            }),
        ]

        for (offset, mutation) in mutations.enumerated() {
            let fixture = try makeFixture(index: 110 + offset)
            defer { fixture.cleanup() }
            let challenge = try await preparedChallenge(
                for: fixture,
                index: 110 + offset
            )
            let coordinator = makeCoordinator(for: fixture)
            _ = try await coordinator.installPreparedChallenge(
                challenge,
                originalPresentationSession: fixture.attempt.presentationSession
            )
            let canonical = try Data(contentsOf: fixture.primaryURL)
            let malformed = try mutation.1(canonical)
            XCTAssertNotEqual(malformed, canonical, mutation.0)
            try malformed.write(to: fixture.primaryURL, options: .atomic)

            let recoveredValue = try await coordinator.recoverPreparedChallenge(
                currentBinding: fixture.attempt.binding
            )
            let recovered = try XCTUnwrap(
                recoveredValue,
                mutation.0
            )
            XCTAssertEqual(recovered.challenge, challenge, mutation.0)
            let quarantined = try XCTUnwrap(
                recovered.report.quarantinedURLs.first,
                mutation.0
            )
            XCTAssertEqual(
                try Data(contentsOf: quarantined),
                malformed,
                mutation.0
            )
            assertExactCopies(canonical, fixture: fixture, message: mutation.0)
        }
    }

    func testTwoValidUnequalCopiesFailClosedWithoutMutation() async throws {
        let fixture = try makeFixture(index: 12)
        defer { fixture.cleanup() }
        let challengeA = try await preparedChallenge(for: fixture, index: 12)
        let coordinator = makeCoordinator(for: fixture)
        _ = try await coordinator.installPreparedChallenge(
            challengeA,
            originalPresentationSession: fixture.attempt.presentationSession
        )
        let primaryA = try Data(contentsOf: fixture.primaryURL)

        let secondFixture = try makeFixture(
            index: 120,
            binding: fixture.attempt.binding
        )
        defer { secondFixture.cleanup() }
        let challengeB = try await preparedChallenge(
            for: secondFixture,
            index: 120
        )
        _ = try await makeCoordinator(for: secondFixture).installPreparedChallenge(
            challengeB,
            originalPresentationSession: secondFixture.attempt.presentationSession
        )
        let validB = try Data(contentsOf: secondFixture.primaryURL)
        XCTAssertNotEqual(primaryA, validB)
        try validB.write(to: fixture.backupURL, options: .atomic)

        await assertJournalError(.journalCopiesDisagree) {
            try await coordinator.recoverPreparedChallenge(
                currentBinding: fixture.attempt.binding
            )
        }
        XCTAssertEqual(try Data(contentsOf: fixture.primaryURL), primaryA)
        XCTAssertEqual(try Data(contentsOf: fixture.backupURL), validB)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: fixture.quarantineDirectoryURL.path
        ))
    }

    func testPinnedCrossOwnerRecoveryRejectsWithoutRepairOrQuarantine() async throws {
        let fixture = try makeFixture(index: 13)
        defer { fixture.cleanup() }
        let challenge = try await preparedChallenge(for: fixture, index: 13)
        _ = try await makeCoordinator(for: fixture).installPreparedChallenge(
            challenge,
            originalPresentationSession: fixture.attempt.presentationSession
        )
        let primary = try Data(contentsOf: fixture.primaryURL)
        let backup = try Data(contentsOf: fixture.backupURL)
        let ownerB = binding(index: 1_300)
        let crossOwner = RewardedAdRecoveryCoordinator(
            testingProfileDirectoryURL: fixture.directoryURL,
            expectedBinding: ownerB,
            fileSystem: FoundationProfileHydrationFileSystem()
        )

        await assertJournalError(.durableOwnerMismatch) {
            try await crossOwner.recoverPreparedChallenge(currentBinding: ownerB)
        }
        XCTAssertEqual(try Data(contentsOf: fixture.primaryURL), primary)
        XCTAssertEqual(try Data(contentsOf: fixture.backupURL), backup)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: fixture.quarantineDirectoryURL.path
        ))
    }

    func testQuarantineRemainsNewAttemptBarrierAfterValidRecoveryCompletes() async throws {
        let fixture = try makeFixture(index: 14)
        defer { fixture.cleanup() }
        let transport = JournalVerificationTransport(
            preparation: preparation(for: fixture.attempt, index: 14),
            status: .terminalRejected(.expired)
        )
        let client = RewardedAdVerificationClient(testingTransport: transport)
        let challenge = try await client.prepareChallenge(for: fixture.attempt)
        let coordinator = makeCoordinator(for: fixture)
        _ = try await coordinator.installPreparedChallenge(
            challenge,
            originalPresentationSession: fixture.attempt.presentationSession
        )
        let corrupt = Data("invalid-evidence".utf8)
        try corrupt.write(to: fixture.backupURL, options: .atomic)
        let repairedValue = try await coordinator.recoverPreparedChallenge(
            currentBinding: fixture.attempt.binding
        )
        let repaired = try XCTUnwrap(repairedValue)
        XCTAssertEqual(
            try Data(contentsOf: try XCTUnwrap(repaired.report.quarantinedURLs.first)),
            corrupt
        )

        let terminal = try await client.checkedVerificationStatus(for: challenge)
        _ = try await coordinator.handleCheckedStatus(
            terminal,
            currentBinding: fixture.attempt.binding
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.primaryURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.backupURL.path))
        let nextAttempt = attempt(index: 1_401, binding: fixture.attempt.binding)
        let nextChallenge = try await preparedChallenge(
            attempt: nextAttempt,
            index: 1_401
        )
        await assertJournalError(.quarantineBarrier) {
            try await coordinator.installPreparedChallenge(
                nextChallenge,
                originalPresentationSession: nextAttempt.presentationSession
            )
        }
    }

    func testAmbiguousWriteRequiresFreshDurableRewrite() async throws {
        let fixture = try makeFixture(index: 15)
        defer { fixture.cleanup() }
        let fileSystem = JournalFaultingFileSystem()
        fileSystem.failWritesAfterInstall(
            named: fixture.backupURL.lastPathComponent,
            count: 1
        )
        let coordinator = RewardedAdRecoveryCoordinator(
            testingProfileDirectoryURL: fixture.directoryURL,
            expectedBinding: fixture.attempt.binding,
            fileSystem: fileSystem
        )
        let challenge = try await preparedChallenge(for: fixture, index: 15)
        _ = try await coordinator.installPreparedChallenge(
            challenge,
            originalPresentationSession: fixture.attempt.presentationSession
        )
        XCTAssertEqual(
            fileSystem.writeCount(named: fixture.backupURL.lastPathComponent),
            2,
            "An outcome-unknown rename must be followed by a fresh durable write"
        )
        XCTAssertEqual(
            try Data(contentsOf: fixture.primaryURL),
            try Data(contentsOf: fixture.backupURL)
        )
    }

    func testRepeatedAmbiguousWriteStaysBlockedAndRelaunchRepairsExactCopy() async throws {
        let fixture = try makeFixture(index: 16)
        defer { fixture.cleanup() }
        let fileSystem = JournalFaultingFileSystem()
        fileSystem.failWritesAfterInstall(
            named: fixture.backupURL.lastPathComponent,
            count: 2
        )
        let coordinator = RewardedAdRecoveryCoordinator(
            testingProfileDirectoryURL: fixture.directoryURL,
            expectedBinding: fixture.attempt.binding,
            fileSystem: fileSystem
        )
        let challenge = try await preparedChallenge(for: fixture, index: 16)
        await assertJournalError(.atomicWriteOutcomeUnknown) {
            try await coordinator.installPreparedChallenge(
                challenge,
                originalPresentationSession: fixture.attempt.presentationSession
            )
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.backupURL.path))

        let relaunched = makeCoordinator(for: fixture)
        let recoveredValue = try await relaunched.recoverPreparedChallenge(
            currentBinding: fixture.attempt.binding
        )
        let recovered = try XCTUnwrap(recoveredValue)
        XCTAssertEqual(recovered.challenge, challenge)
        XCTAssertEqual(
            try Data(contentsOf: fixture.primaryURL),
            try Data(contentsOf: fixture.backupURL)
        )
    }

    func testAmbiguousRemovalRequiresFreshAbsentDirectorySync() async throws {
        let fixture = try makeFixture(index: 17)
        defer { fixture.cleanup() }
        let fileSystem = JournalFaultingFileSystem()
        let coordinator = RewardedAdRecoveryCoordinator(
            testingProfileDirectoryURL: fixture.directoryURL,
            expectedBinding: fixture.attempt.binding,
            fileSystem: fileSystem
        )
        let transport = JournalVerificationTransport(
            preparation: preparation(for: fixture.attempt, index: 17),
            status: .terminalRejected(.invalidChallenge)
        )
        let client = RewardedAdVerificationClient(testingTransport: transport)
        let challenge = try await client.prepareChallenge(for: fixture.attempt)
        _ = try await coordinator.installPreparedChallenge(
            challenge,
            originalPresentationSession: fixture.attempt.presentationSession
        )
        let primaryRemoveCountBefore = fileSystem.removeCount(
            named: fixture.primaryURL.lastPathComponent
        )
        fileSystem.failRemovalsAfterRemoval(
            named: fixture.primaryURL.lastPathComponent,
            count: 1
        )

        let observation = try await client.checkedVerificationStatus(for: challenge)
        _ = try await coordinator.handleCheckedStatus(
            observation,
            currentBinding: fixture.attempt.binding
        )
        XCTAssertEqual(
            fileSystem.removeCount(named: fixture.primaryURL.lastPathComponent),
            primaryRemoveCountBefore + 2,
            "Observed absence must receive a fresh durable parent sync"
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.primaryURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.backupURL.path))
    }

    func testRelaunchDurablyResyncsBothMissingCopiesAfterFinalRemovalAmbiguity()
        async throws
    {
        let fixture = try makeFixture(index: 171)
        defer { fixture.cleanup() }
        let fileSystem = JournalFaultingFileSystem()
        let coordinator = RewardedAdRecoveryCoordinator(
            testingProfileDirectoryURL: fixture.directoryURL,
            expectedBinding: fixture.attempt.binding,
            fileSystem: fileSystem
        )
        let transport = JournalVerificationTransport(
            preparation: preparation(for: fixture.attempt, index: 171),
            status: .terminalRejected(.invalidChallenge)
        )
        let client = RewardedAdVerificationClient(testingTransport: transport)
        let challenge = try await client.prepareChallenge(for: fixture.attempt)
        _ = try await coordinator.installPreparedChallenge(
            challenge,
            originalPresentationSession: fixture.attempt.presentationSession
        )
        let primaryRemoveCountBefore = fileSystem.removeCount(
            named: fixture.primaryURL.lastPathComponent
        )
        let backupRemoveCountBefore = fileSystem.removeCount(
            named: fixture.backupURL.lastPathComponent
        )
        fileSystem.failRemovalsAfterRemoval(
            named: fixture.backupURL.lastPathComponent,
            count: 2
        )

        let observation = try await client.checkedVerificationStatus(for: challenge)
        await assertJournalError(.ioFailure) {
            try await coordinator.handleCheckedStatus(
                observation,
                currentBinding: fixture.attempt.binding
            )
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.primaryURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.backupURL.path))
        XCTAssertEqual(
            fileSystem.removeCount(named: fixture.primaryURL.lastPathComponent),
            primaryRemoveCountBefore + 1
        )
        XCTAssertEqual(
            fileSystem.removeCount(named: fixture.backupURL.lastPathComponent),
            backupRemoveCountBefore + 2
        )

        let relaunched = RewardedAdRecoveryCoordinator(
            testingProfileDirectoryURL: fixture.directoryURL,
            expectedBinding: fixture.attempt.binding,
            fileSystem: fileSystem
        )
        let recovered = try await relaunched.recoverPreparedChallenge(
            currentBinding: fixture.attempt.binding
        )
        XCTAssertNil(recovered)
        XCTAssertEqual(
            fileSystem.removeCount(named: fixture.primaryURL.lastPathComponent),
            primaryRemoveCountBefore + 2,
            "Relaunch must durably sync even an already-missing primary"
        )
        XCTAssertEqual(
            fileSystem.removeCount(named: fixture.backupURL.lastPathComponent),
            backupRemoveCountBefore + 3,
            "Relaunch must durably sync the ambiguously removed final backup"
        )
    }

    func testDeliveryCommitWithAmbiguousCleanupRetriesIdempotentlyAfterRelaunch() async throws {
        let fixture = try makeFixture(index: 18)
        defer { fixture.cleanup() }
        let fileSystem = JournalFaultingFileSystem()
        let coordinator = RewardedAdRecoveryCoordinator(
            testingProfileDirectoryURL: fixture.directoryURL,
            expectedBinding: fixture.attempt.binding,
            fileSystem: fileSystem
        )
        let transport = JournalVerificationTransport(
            preparation: preparation(for: fixture.attempt, index: 18),
            status: .verified(verifiedResponse(for: fixture.attempt, index: 18))
        )
        let client = RewardedAdVerificationClient(testingTransport: transport)
        let challenge = try await client.prepareChallenge(for: fixture.attempt)
        _ = try await coordinator.installPreparedChallenge(
            challenge,
            originalPresentationSession: fixture.attempt.presentationSession
        )
        let observation = try await client.checkedVerificationStatus(for: challenge)
        fileSystem.failRemovalsAfterRemoval(
            named: fixture.primaryURL.lastPathComponent,
            count: 2
        )
        let firstDeliverer = JournalDeliveryRecorder(
            mode: .success(wasAlreadySettled: false),
            cloudAccountID: fixture.cloudAccountID
        )
        do {
            _ = try await coordinator.deliverVerifiedReward(
                checked: observation,
                currentSession: profileSession(for: fixture),
                currentBinding: fixture.attempt.binding,
                using: firstDeliverer
            )
            XCTFail("Expected ambiguous cleanup")
        } catch {
            XCTAssertEqual(error as? RewardedAdRecoveryJournalError, .ioFailure)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.backupURL.path))

        let relaunched = RewardedAdRecoveryCoordinator(
            testingProfileDirectoryURL: fixture.directoryURL,
            expectedBinding: fixture.attempt.binding,
            fileSystem: fileSystem
        )
        let recoveredValue = try await relaunched.recoverPreparedChallenge(
            currentBinding: fixture.attempt.binding
        )
        let recovered = try XCTUnwrap(recoveredValue)
        let freshObservation = try await client.checkedVerificationStatus(
            for: recovered.challenge
        )
        let retryDeliverer = JournalDeliveryRecorder(
            mode: .success(wasAlreadySettled: true),
            cloudAccountID: fixture.cloudAccountID
        )
        _ = try await relaunched.deliverVerifiedReward(
            checked: freshObservation,
            currentSession: profileSession(
                for: fixture,
                nonce: uuid(18_999)
            ),
            currentBinding: fixture.attempt.binding,
            using: retryDeliverer
        )
        let statusCount = await transport.statusCount()
        XCTAssertEqual(statusCount, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.primaryURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.backupURL.path))
    }
}

private extension RewardedAdRecoveryJournalTests {
    struct Fixture {
        let directoryURL: URL
        let attempt: RewardedAdAttempt
        let cloudAccountID: CloudAccountID
        let playerAccountIdentity: PlayerAccountIdentity

        var recoveryDirectoryURL: URL {
            directoryURL.appendingPathComponent(
                "RewardedAdRecovery",
                isDirectory: true
            )
        }

        var primaryURL: URL {
            recoveryDirectoryURL.appendingPathComponent(
                "rewarded-ad-recovery-journal.json"
            )
        }

        var backupURL: URL {
            recoveryDirectoryURL.appendingPathComponent(
                "rewarded-ad-recovery-journal.backup.json"
            )
        }

        var quarantineDirectoryURL: URL {
            recoveryDirectoryURL.appendingPathComponent(
                "Quarantine",
                isDirectory: true
            )
        }

        func cleanup() {
            try? FileManager.default.removeItem(at: directoryURL)
        }
    }

    func makeFixture(
        index: Int,
        binding: DurableAccountBinding? = nil
    ) throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "pocket-vector-rewarded-ad-journal-\(UUID().uuidString)",
                isDirectory: true
            )
        let cloudAccountID = CloudAccountID(
            "journal-private-cloud-account-\(index)"
        )
        let derived = CloudAccountDerivedBindings.derive(from: cloudAccountID)
        return Fixture(
            directoryURL: directory,
            attempt: attempt(
                index: index,
                binding: binding ?? derived.durableAccountBinding
            ),
            cloudAccountID: cloudAccountID,
            playerAccountIdentity: derived.playerAccountIdentity
        )
    }

    func makeCoordinator(for fixture: Fixture) -> RewardedAdRecoveryCoordinator {
        RewardedAdRecoveryCoordinator(
            testingProfileDirectoryURL: fixture.directoryURL,
            expectedBinding: fixture.attempt.binding,
            fileSystem: FoundationProfileHydrationFileSystem()
        )
    }

    func binding(index: Int) -> DurableAccountBinding {
        CloudAccountDerivedBindings.derive(
            from: CloudAccountID("journal-private-cloud-account-\(index)")
        ).durableAccountBinding
    }

    func attempt(
        index: Int,
        binding: DurableAccountBinding
    ) -> RewardedAdAttempt {
        RewardedAdAttempt(
            binding: binding,
            presentationSessionNonce: uuid(index * 100 + 2),
            offerID: RewardedAdState.offerID(for: UInt64(index)),
            attemptID: uuid(index * 100 + 3)
        )
    }

    func preparation(
        for attempt: RewardedAdAttempt,
        index: Int
    ) -> RewardedAdVerificationPreparationResponse {
        RewardedAdVerificationPreparationResponse(
            attempt: attempt,
            verificationHandle: "journal-verification-handle-\(index)-00000000",
            providerCustomData: "journal-provider-custom-data-\(index)-00000000"
        )
    }

    func verifiedResponse(
        for attempt: RewardedAdAttempt,
        index: Int
    ) -> RewardedAdVerifiedServerResponse {
        let preparation = preparation(for: attempt, index: index)
        return RewardedAdVerifiedServerResponse(
            attempt: attempt,
            verificationHandle: preparation.verificationHandle,
            providerCustomData: preparation.providerCustomData,
            uniqueProviderTransactionID: "provider-transaction-\(index)",
            rewardedAt: rewardedAt
        )
    }

    func preparedChallenge(
        for fixture: Fixture,
        index: Int
    ) async throws -> RewardedAdVerificationChallengeV1 {
        try await preparedChallenge(attempt: fixture.attempt, index: index)
    }

    func preparedChallenge(
        attempt: RewardedAdAttempt,
        index: Int
    ) async throws -> RewardedAdVerificationChallengeV1 {
        let transport = JournalVerificationTransport(
            preparation: preparation(for: attempt, index: index),
            status: .pending
        )
        return try await RewardedAdVerificationClient(
            testingTransport: transport
        ).prepareChallenge(for: attempt)
    }

    func installedVerified(
        fixture: Fixture,
        index: Int
    ) async throws -> (
        RewardedAdRecoveryCoordinator,
        RewardedAdCheckedStatusObservation,
        VerifiedRewardedAdClaim
    ) {
        let transport = JournalVerificationTransport(
            preparation: preparation(for: fixture.attempt, index: index),
            status: .verified(verifiedResponse(for: fixture.attempt, index: index))
        )
        let client = RewardedAdVerificationClient(testingTransport: transport)
        let challenge = try await client.prepareChallenge(for: fixture.attempt)
        let coordinator = self.makeCoordinator(for: fixture)
        _ = try await coordinator.installPreparedChallenge(
            challenge,
            originalPresentationSession: fixture.attempt.presentationSession
        )
        let observation = try await client.checkedVerificationStatus(for: challenge)
        let disposition = try await coordinator.handleCheckedStatus(
            observation,
            currentBinding: fixture.attempt.binding
        )
        return (
            coordinator,
            observation,
            try verifiedClaim(from: disposition)
        )
    }

    func verifiedClaim(
        from disposition: RewardedAdRecoveryCheckedStatusDisposition
    ) throws -> VerifiedRewardedAdClaim {
        guard case let .verified(claim) = disposition else {
            throw JournalTestFailure.expectedVerified
        }
        return claim
    }

    func profileSession(
        for fixture: Fixture,
        nonce: UUID? = nil
    ) -> ProfileSessionToken {
        ProfileSessionToken(
            accountIdentity: fixture.playerAccountIdentity,
            nonce: nonce ?? fixture.attempt.presentationSessionNonce,
            profileID: fixture.attempt.binding.profileID
        )
    }

    func assertExactCopies(
        _ expected: Data,
        fixture: Fixture,
        message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            try Data(contentsOf: fixture.primaryURL),
            expected,
            message,
            file: file,
            line: line
        )
        XCTAssertEqual(
            try Data(contentsOf: fixture.backupURL),
            expected,
            message,
            file: file,
            line: line
        )
    }

    func assertJournalError<Value>(
        _ expected: RewardedAdRecoveryJournalError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () async throws -> Value
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(
                error as? RewardedAdRecoveryJournalError,
                expected,
                file: file,
                line: line
            )
        }
    }

    func assertVerificationError<Value>(
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

    func uuid(_ value: Int) -> UUID {
        UUID(
            uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", value))"
        )!
    }
}

private enum JournalTestFailure: Error {
    case offline
    case deliveryFailed
    case expectedVerified
}

private actor JournalVerificationTransport: RewardedAdVerificationTransport {
    private let preparation: RewardedAdVerificationPreparationResponse
    private var status: Result<RewardedAdVerificationServerStatus, JournalTestFailure>
    private var prepareRequests: [RewardedAdVerificationPreparationRequest] = []
    private var statusRequests: [RewardedAdVerificationStatusRequest] = []

    init(
        preparation: RewardedAdVerificationPreparationResponse,
        status: RewardedAdVerificationServerStatus
    ) {
        self.preparation = preparation
        self.status = .success(status)
    }

    func prepareChallenge(
        _ request: RewardedAdVerificationPreparationRequest
    ) throws -> RewardedAdVerificationPreparationResponse {
        prepareRequests.append(request)
        return preparation
    }

    func verificationStatus(
        _ request: RewardedAdVerificationStatusRequest
    ) throws -> RewardedAdVerificationServerStatus {
        statusRequests.append(request)
        return try status.get()
    }

    func setFailure(_ failure: JournalTestFailure) {
        status = .failure(failure)
    }

    func prepareCount() -> Int { prepareRequests.count }
    func statusCount() -> Int { statusRequests.count }
}

private actor JournalDeliveryRecorder:
    VerifiedRewardedAdDurableCreditDelivering
{
    enum AcknowledgementTampering: String, CaseIterable, Sendable {
        case session
        case binding
        case offerID
        case providerTransactionID
        case cloudAccount
        case receiptCloudAccount
        case operationID
        case recordID
        case rewardedAt
        case arbitraryReceiptIDs
    }

    enum Mode: Sendable {
        case success(wasAlreadySettled: Bool)
        case committedThenRefreshed
        case mismatchedProvider
        case tamperedAcknowledgement(AcknowledgementTampering)
        case failure
    }

    private let mode: Mode
    private let cloudAccountID: CloudAccountID
    private let recordID = CloudRecordID("journal-economy-head")
    private var recordedRequests: [VerifiedRewardedAdDurableDeliveryRequest] = []

    init(mode: Mode, cloudAccountID: CloudAccountID) {
        self.mode = mode
        self.cloudAccountID = cloudAccountID
    }

    func deliverVerifiedReward(
        _ request: VerifiedRewardedAdDurableDeliveryRequest
    ) throws -> DurableRewardedAdDeliveryResult {
        recordedRequests.append(request)
        switch mode {
        case .failure:
            throw JournalTestFailure.deliveryFailed
        case let .success(wasAlreadySettled):
            return result(for: request, wasAlreadySettled: wasAlreadySettled)
        case .committedThenRefreshed:
            return result(
                for: request,
                wasAlreadySettled: false,
                cloudStatus: .committedThenRefreshed
            )
        case .mismatchedProvider:
            return result(
                for: request,
                wasAlreadySettled: false,
                providerTransactionID: AdProviderTransactionID("wrong-provider")
            )
        case let .tamperedAcknowledgement(tampering):
            return result(
                for: request,
                wasAlreadySettled: false,
                acknowledgementTampering: tampering
            )
        }
    }

    func requests() -> [VerifiedRewardedAdDurableDeliveryRequest] {
        recordedRequests
    }

    private func result(
        for request: VerifiedRewardedAdDurableDeliveryRequest,
        wasAlreadySettled: Bool,
        providerTransactionID: AdProviderTransactionID? = nil,
        acknowledgementTampering: AcknowledgementTampering? = nil,
        cloudStatus: DurableEconomyCloudCommitStatus? = nil
    ) -> DurableRewardedAdDeliveryResult {
        let providerTransactionID = providerTransactionID
            ?? request.providerTransactionID
        let outcome = RewardedAdSettlementOutcome(
            offerID: request.offerID,
            providerTransactionID: providerTransactionID,
            ledgerEntryID: CoinLedgerID.rewardedAd(
                providerTransactionID: providerTransactionID
            ),
            coins: PersistedEconomyRulesV1.rewardedAdCoins,
            wasAlreadySettled: wasAlreadySettled,
            confirmedBalanceAfter: 100
        )
        let exactOperationID = DurableRewardedAdDeliveryResult
            .testingRewardedAdOperationID(
                cloudAccountID: cloudAccountID,
                binding: request.verifiedBinding,
                session: request.session,
                providerTransactionID: request.providerTransactionID
            )
        var receiptOperationID = exactOperationID
        var receiptRecordID = recordID
        var receiptCloudAccountID = cloudAccountID
        var acknowledgedSession = request.session
        var acknowledgedBinding = request.verifiedBinding
        var acknowledgedOfferID = request.offerID
        var acknowledgedProviderTransactionID = request.providerTransactionID
        var acknowledgedCloudAccountID = cloudAccountID
        var acknowledgedOperationID: OperationID? = exactOperationID
        var acknowledgedRecordID = recordID
        var acknowledgedRewardedAt = request.rewardedAt

        switch acknowledgementTampering {
        case .session:
            acknowledgedSession = ProfileSessionToken(
                accountIdentity: request.session.accountIdentity,
                nonce: UUID(
                    uuidString: "FFFFFFFF-FFFF-4FFF-BFFF-FFFFFFFFFFFF"
                )!,
                profileID: request.session.profileID
            )
        case .binding:
            acknowledgedBinding = CloudAccountDerivedBindings.derive(
                from: CloudAccountID("wrong-journal-binding-account")
            ).durableAccountBinding
        case .offerID:
            acknowledgedOfferID = RewardedAdState.offerID(for: UInt64.max)
        case .providerTransactionID:
            acknowledgedProviderTransactionID = AdProviderTransactionID(
                "wrong-acknowledged-provider"
            )
        case .cloudAccount:
            acknowledgedCloudAccountID = CloudAccountID(
                "wrong-journal-cloud-account"
            )
        case .receiptCloudAccount:
            let wrongCloudAccountID = CloudAccountID(
                "wrong-journal-receipt-cloud-account"
            )
            let wrongCloudOperationID = DurableRewardedAdDeliveryResult
                .testingRewardedAdOperationID(
                    cloudAccountID: wrongCloudAccountID,
                    binding: request.verifiedBinding,
                    session: request.session,
                    providerTransactionID: request.providerTransactionID
                )
            receiptCloudAccountID = wrongCloudAccountID
            receiptOperationID = wrongCloudOperationID
            acknowledgedCloudAccountID = wrongCloudAccountID
            acknowledgedOperationID = wrongCloudOperationID
        case .operationID:
            acknowledgedOperationID = OperationID(
                "wrong-journal-operation"
            )
        case .recordID:
            acknowledgedRecordID = CloudRecordID("wrong-journal-record")
        case .rewardedAt:
            acknowledgedRewardedAt = request.rewardedAt.addingTimeInterval(1)
        case .arbitraryReceiptIDs:
            receiptOperationID = OperationID("arbitrary-journal-operation")
            receiptRecordID = CloudRecordID("arbitrary-journal-record")
            acknowledgedOperationID = receiptOperationID
            acknowledgedRecordID = receiptRecordID
        case nil:
            break
        }

        let cloudReceipt = DurableEconomyCloudCommitReceipt(
            accountID: receiptCloudAccountID,
            operationID: receiptOperationID,
            recordID: receiptRecordID,
            observedChangeTag: CloudChangeTag("journal-change-tag"),
            cloudEconomyRevision: 1,
            status: cloudStatus
                ?? (wasAlreadySettled ? .alreadyCommitted : .committed)
        )
        return DurableRewardedAdDeliveryResult(
            testingOutcome: outcome,
            cloudReceipt: cloudReceipt,
            acknowledgedSession: acknowledgedSession,
            acknowledgedBinding: acknowledgedBinding,
            acknowledgedOfferID: acknowledgedOfferID,
            acknowledgedProviderTransactionID:
                acknowledgedProviderTransactionID,
            acknowledgedRewardedAt: acknowledgedRewardedAt,
            acknowledgedCloudAccountID: acknowledgedCloudAccountID,
            acknowledgedOperationID: acknowledgedOperationID,
            acknowledgedRecordID: acknowledgedRecordID
        )
    }
}

private final class JournalFaultingFileSystem:
    ProfileHydrationFileSystem,
    @unchecked Sendable
{
    private let base = FoundationProfileHydrationFileSystem()
    private let lock = NSLock()
    private var writeFailuresAfterInstall: [String: Int] = [:]
    private var removalFailuresAfterRemoval: [String: Int] = [:]
    private var writeCounts: [String: Int] = [:]
    private var removeCounts: [String: Int] = [:]

    func failWritesAfterInstall(named name: String, count: Int) {
        lock.withLock { writeFailuresAfterInstall[name] = count }
    }

    func failRemovalsAfterRemoval(named name: String, count: Int) {
        lock.withLock { removalFailuresAfterRemoval[name] = count }
    }

    func writeCount(named name: String) -> Int {
        lock.withLock { writeCounts[name, default: 0] }
    }

    func removeCount(named name: String) -> Int {
        lock.withLock { removeCounts[name, default: 0] }
    }

    func createDirectory(at url: URL) throws {
        try base.createDirectory(at: url)
    }

    func itemStatus(at url: URL) throws -> ProfileHydrationFileItemStatus {
        try base.itemStatus(at: url)
    }

    func fileSize(at url: URL) throws -> Int {
        try base.fileSize(at: url)
    }

    func read(from url: URL) throws -> Data {
        try base.read(from: url)
    }

    func writeAtomicallyDurably(_ data: Data, to url: URL) throws {
        let shouldFail = lock.withLock { () -> Bool in
            writeCounts[url.lastPathComponent, default: 0] += 1
            guard writeFailuresAfterInstall[url.lastPathComponent, default: 0]
                    > 0 else {
                return false
            }
            writeFailuresAfterInstall[url.lastPathComponent, default: 0] -= 1
            return true
        }
        try base.writeAtomicallyDurably(data, to: url)
        if shouldFail {
            throw ProfileHydrationFileSystemError.atomicWriteOutcomeUnknown
        }
    }

    func moveItemDurably(at sourceURL: URL, to destinationURL: URL) throws {
        try base.moveItemDurably(at: sourceURL, to: destinationURL)
    }

    func removeItemDurably(at url: URL) throws {
        let shouldFail = lock.withLock { () -> Bool in
            removeCounts[url.lastPathComponent, default: 0] += 1
            guard removalFailuresAfterRemoval[url.lastPathComponent, default: 0]
                    > 0 else {
                return false
            }
            removalFailuresAfterRemoval[url.lastPathComponent, default: 0] -= 1
            return true
        }
        try base.removeItemDurably(at: url)
        if shouldFail {
            throw ProfileHydrationFileSystemError.ioFailure
        }
    }

    func withExclusiveLock(
        at url: URL,
        perform: () throws -> Void
    ) throws {
        try base.withExclusiveLock(at: url, perform: perform)
    }
}

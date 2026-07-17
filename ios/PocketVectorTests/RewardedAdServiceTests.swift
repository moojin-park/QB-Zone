import XCTest

@testable import PocketVector

final class RewardedAdServiceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000)
    private let allowedConsent = ConsentSnapshot(
        status: .obtained,
        canRequestAds: true,
        privacyOptionsRequired: false
    )

    func testDeclineKeepsFiveRunEligibility() throws {
        let session = activeSession(account: "a", nonce: 1)
        let economy = eligibleEconomyState()
        let context = currentContext(session: session, economy: economy, revision: 1)
        var coordinator = RewardedAdCoordinatorState(
            consent: allowedConsent,
            accountContext: context,
            at: now
        )
        let offerID = try XCTUnwrap(economy.eligibleOfferID)

        XCTAssertEqual(
            coordinator.requestLoad(at: now),
            .load(offerID: offerID, session: session)
        )
        XCTAssertTrue(
            coordinator.loadDidSucceed(
                offerID: offerID,
                session: session,
                at: now
            )
        )
        coordinator.declineOffer(at: now)

        XCTAssertEqual(coordinator.phase, .idle(offerID))
        XCTAssertEqual(
            coordinator.accountContext?.economyState.validRunsSinceReward,
            EconomyConfiguration.rewardedAdRunThreshold
        )
        XCTAssertEqual(coordinator.accountContext?.economyState.eligibleOfferID, offerID)
    }

    func testConsentAndExactCurrentEconomyProofGateLoadAndPresentation() throws {
        let session = activeSession(account: "a", nonce: 1)
        let economy = eligibleEconomyState()
        let staleContext = RewardedAdAccountContext(
            session: session,
            economyState: economy,
            economyRevision: 2,
            proof: economyProof(session: session, revision: 1)
        )
        var coordinator = RewardedAdCoordinatorState(
            consent: .unknown,
            accountContext: staleContext,
            at: now
        )

        XCTAssertEqual(coordinator.phase, .blockedByConsent)
        XCTAssertNil(coordinator.requestLoad(at: now))

        coordinator.updateConsent(allowedConsent, at: now)
        XCTAssertEqual(coordinator.phase, .blockedByEconomy)
        XCTAssertNil(coordinator.requestLoad(at: now))

        let current = currentContext(session: session, economy: economy, revision: 2)
        coordinator.updateAccountContext(current, at: now)
        let offerID = try XCTUnwrap(economy.eligibleOfferID)
        XCTAssertEqual(
            coordinator.requestLoad(at: now),
            .load(offerID: offerID, session: session)
        )
        XCTAssertTrue(
            coordinator.loadDidSucceed(
                offerID: offerID,
                session: session,
                at: now
            )
        )

        let afterExpiry = now.addingTimeInterval(61)
        coordinator.updateAccountContext(current, at: afterExpiry)
        XCTAssertEqual(coordinator.phase, .blockedByEconomy)
        XCTAssertNil(
            coordinator.beginPresentation(
                attemptID: uuid(900),
                at: afterExpiry
            )
        )
    }

    func testDurableRewardFlowSurvivesEveryCrashPointAndRebindsOnlySameOwner() throws {
        let economy = eligibleEconomyState()
        let offerID = try XCTUnwrap(economy.eligibleOfferID)
        let sessionA1 = activeSession(account: "a", nonce: 1)
        let sessionA2 = activeSession(account: "a", nonce: 2)
        let sessionA3 = activeSession(account: "a", nonce: 3)
        let sessionB = activeSession(account: "b", nonce: 4)
        let attemptID = uuid(500)
        let providerID = AdProviderTransactionID("provider-500")
        var coordinator = RewardedAdCoordinatorState(
            consent: allowedConsent,
            accountContext: currentContext(
                session: sessionA1,
                economy: economy,
                revision: 10
            ),
            at: now
        )

        _ = coordinator.requestLoad(at: now)
        XCTAssertTrue(
            coordinator.loadDidSucceed(
                offerID: offerID,
                session: sessionA1,
                at: now
            )
        )
        let presentationCommand = try XCTUnwrap(
            coordinator.beginPresentation(attemptID: attemptID, at: now)
        )
        let attempt: RewardedAdAttempt
        if case let .present(value) = presentationCommand {
            attempt = value
        } else {
            return XCTFail("Expected presentation command")
        }
        XCTAssertEqual(attempt.presentationSession, sessionA1)
        let presentationCrashState = try roundTrip(coordinator.durableState)

        var stalePresentationCallbackProbe = RewardedAdCoordinatorState(
            durableState: presentationCrashState,
            consent: allowedConsent,
            accountContext: currentContext(
                session: sessionA2,
                economy: economy,
                revision: 10
            ),
            at: now
        )
        XCTAssertFalse(
            stalePresentationCallbackProbe.clientRewardDidEarn(
                attemptID: attemptID,
                session: sessionA1
            )
        )

        XCTAssertTrue(
            coordinator.clientRewardDidEarn(
                attemptID: attemptID,
                session: sessionA1
            )
        )
        coordinator = RewardedAdCoordinatorState(
            durableState: try roundTrip(coordinator.durableState),
            consent: allowedConsent,
            accountContext: currentContext(
                session: sessionA1,
                economy: economy,
                revision: 10
            ),
            at: now
        )

        coordinator.updateAccountContext(
            currentContext(session: sessionB, economy: economy, revision: 20),
            at: now
        )
        let receipt = VerifiedRewardReceipt(
            binding: sessionA1.binding,
            offerID: offerID,
            attemptID: attemptID,
            providerTransactionID: providerID,
            rewardedAt: now.addingTimeInterval(10)
        )
        XCTAssertNil(coordinator.verificationDidSucceed(receipt, at: now))
        XCTAssertEqual(coordinator.recoveryCommands(at: now), [])
        XCTAssertNil(coordinator.requestLoad(at: now))

        let verifiedCrashState = try roundTrip(coordinator.durableState)
        let staleProofContext = RewardedAdAccountContext(
            session: sessionA2,
            economyState: economy,
            economyRevision: 11,
            proof: economyProof(session: sessionA2, revision: 10)
        )
        var restored = RewardedAdCoordinatorState(
            durableState: verifiedCrashState,
            consent: allowedConsent,
            accountContext: staleProofContext,
            at: now
        )
        XCTAssertEqual(restored.recoveryCommands(at: now), [])

        restored.updateAccountContext(
            currentContext(session: sessionA2, economy: economy, revision: 11),
            at: now
        )
        XCTAssertEqual(
            restored.recoveryCommands(at: now),
            [
                .settleVerifiedReward(
                    session: sessionA2,
                    receipt: receipt,
                    ledgerEntryID: CoinLedgerID.rewardedAd(
                        providerTransactionID: providerID
                    ),
                    coins: EconomyConfiguration.rewardedAdCoins
                ),
            ]
        )
        restored = RewardedAdCoordinatorState(
            durableState: try roundTrip(restored.durableState),
            consent: allowedConsent,
            accountContext: currentContext(
                session: sessionA2,
                economy: economy,
                revision: 11
            ),
            at: now
        )

        // The repository atomically inserted the +100 ledger entry and redeemed
        // the offer, but its acknowledgement was lost. Durable coordinator
        // state therefore remains the same deterministic pending operation.
        var redeemedEconomy = economy
        XCTAssertTrue(redeemedEconomy.redeem(offerID))
        let lostAcknowledgementState = try roundTrip(restored.durableState)
        var afterSecondRelaunch = RewardedAdCoordinatorState(
            durableState: lostAcknowledgementState,
            consent: allowedConsent,
            accountContext: currentContext(
                session: sessionA3,
                economy: redeemedEconomy,
                revision: 12
            ),
            at: now
        )
        XCTAssertEqual(
            afterSecondRelaunch.recoveryCommands(at: now),
            [
                .settleVerifiedReward(
                    session: sessionA3,
                    receipt: receipt,
                    ledgerEntryID: CoinLedgerID.rewardedAd(
                        providerTransactionID: providerID
                    ),
                    coins: EconomyConfiguration.rewardedAdCoins
                ),
            ]
        )
        afterSecondRelaunch = RewardedAdCoordinatorState(
            durableState: try roundTrip(afterSecondRelaunch.durableState),
            consent: allowedConsent,
            accountContext: currentContext(
                session: sessionA3,
                economy: redeemedEconomy,
                revision: 12
            ),
            at: now
        )

        let staleAcknowledgement = RewardedAdSettlementAcknowledgement(
            session: sessionA2,
            receipt: receipt,
            ledgerEntryID: CoinLedgerID.rewardedAd(providerTransactionID: providerID),
            disposition: .committed,
            resultingEconomyState: redeemedEconomy,
            resultingEconomyRevision: 12
        )
        XCTAssertFalse(
            afterSecondRelaunch.atomicSettlementDidCommit(
                staleAcknowledgement,
                at: now
            )
        )

        let invalidSplitAcknowledgement = RewardedAdSettlementAcknowledgement(
            session: sessionA3,
            receipt: receipt,
            ledgerEntryID: CoinLedgerID.rewardedAd(providerTransactionID: providerID),
            disposition: .alreadyCommitted,
            resultingEconomyState: economy,
            resultingEconomyRevision: 12
        )
        XCTAssertFalse(
            afterSecondRelaunch.atomicSettlementDidCommit(
                invalidSplitAcknowledgement,
                at: now
            )
        )

        let currentAcknowledgement = RewardedAdSettlementAcknowledgement(
            session: sessionA3,
            receipt: receipt,
            ledgerEntryID: CoinLedgerID.rewardedAd(providerTransactionID: providerID),
            disposition: .alreadyCommitted,
            resultingEconomyState: redeemedEconomy,
            resultingEconomyRevision: 12
        )
        XCTAssertTrue(
            afterSecondRelaunch.atomicSettlementDidCommit(
                currentAcknowledgement,
                at: now
            )
        )
        let settledState = try roundTrip(afterSecondRelaunch.durableState)
        XCTAssertNil(settledState.flow)
        XCTAssertTrue(settledState.settledProviderTransactionIDs.contains(providerID))
        XCTAssertEqual(afterSecondRelaunch.phase, .blockedByEconomy)
        XCTAssertNil(afterSecondRelaunch.verificationDidSucceed(receipt, at: now))
    }

    private func eligibleEconomyState() -> RewardedAdState {
        var state = RewardedAdState()
        for value in 1 ... EconomyConfiguration.rewardedAdRunThreshold {
            state.recordValidRun(RunID(uuid(value)))
        }
        return state
    }

    private func currentContext(
        session: ActiveAccountSession,
        economy: RewardedAdState,
        revision: UInt64
    ) -> RewardedAdAccountContext {
        RewardedAdAccountContext(
            session: session,
            economyState: economy,
            economyRevision: revision,
            proof: economyProof(session: session, revision: revision)
        )
    }

    private func economyProof(
        session: ActiveAccountSession,
        revision: UInt64
    ) -> AccountScopedEconomyProof {
        AccountScopedEconomyProof(
            session: session,
            economyRevision: revision,
            validationID: OperationID("proof-\(session.nonce.uuidString)-\(revision)"),
            validatedAt: now,
            expiresAt: now.addingTimeInterval(60)
        )
    }

    private func activeSession(account: String, nonce: Int) -> ActiveAccountSession {
        ActiveAccountSession(
            binding: DurableAccountBinding(
                accountKey: ServiceAccountKey("account-\(account)"),
                profileID: uuid(account == "a" ? 100 : 200)
            ),
            nonce: uuid(nonce)
        )
    }

    private func roundTrip(
        _ state: RewardedAdDurableState
    ) throws -> RewardedAdDurableState {
        try JSONDecoder().decode(
            RewardedAdDurableState.self,
            from: JSONEncoder().encode(state)
        )
    }

    private func uuid(_ value: Int) -> UUID {
        UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", value))")!
    }
}

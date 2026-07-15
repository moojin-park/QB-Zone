import Foundation
import XCTest

@testable import PocketVector

final class DomainContractTests: XCTestCase {
    func testRunStatisticsUsesExactIntegerAccuracyForRules() {
        let sixtyNinePercent = RunStatisticsSnapshot(
            attempts: 100,
            completions: 69,
            incompletions: 31
        )
        let seventyPercent = RunStatisticsSnapshot(
            attempts: 10,
            completions: 7,
            incompletions: 3
        )

        XCTAssertFalse(sixtyNinePercent.meetsAccuracy(percent: 70))
        XCTAssertTrue(seventyPercent.meetsAccuracy(percent: 70))
        XCTAssertFalse(seventyPercent.meetsAccuracy(percent: 70, minimumAttempts: 12))
    }

    func testCompletedRunSeparatesNaturalCompletionFromRewardEligibility() {
        let twoAttempts = makeRun(
            statistics: RunStatisticsSnapshot(attempts: 2, completions: 2)
        )
        let threeAttempts = makeRun(
            statistics: RunStatisticsSnapshot(attempts: 3, completions: 2, incompletions: 1)
        )
        let abandoned = makeRun(
            finishReason: .abandoned,
            statistics: RunStatisticsSnapshot(attempts: 3, completions: 3)
        )

        XCTAssertTrue(twoAttempts.isNaturallyCompleted)
        XCTAssertFalse(twoAttempts.isRewardEligible)
        XCTAssertTrue(threeAttempts.isRewardEligible)
        XCTAssertFalse(abandoned.isNaturallyCompleted)
        XCTAssertFalse(abandoned.isRewardEligible)
    }

    func testLedgerIdentifiersAreStableAndBalanceRejectsInvalidSigns() throws {
        let runID = RunID(UUID(uuidString: "00000000-0000-0000-0000-000000000011")!)
        XCTAssertEqual(
            CoinLedgerID.gameplay(runID: runID).rawValue,
            "run/00000000-0000-0000-0000-000000000011/reward"
        )
        XCTAssertEqual(CoinLedgerID.signingBonus(version: 1).rawValue, "signing-bonus/v1")
        XCTAssertEqual(CoinLedgerID.storeKit(transactionID: 42).rawValue, "storekit/42")
        XCTAssertEqual(
            CoinLedgerID.rewardedAd(
                providerTransactionID: AdProviderTransactionID("provider-completion-abc")
            ).rawValue,
            "rewarded-ad/provider-completion-abc"
        )

        let now = Date(timeIntervalSince1970: 1_000)
        let grant = CoinLedgerEntry(
            id: CoinLedgerID.gameplay(runID: runID),
            delta: 25,
            reason: .gameplay(runID: runID, economyVersion: 1),
            createdAt: now
        )
        let spend = CoinLedgerEntry(
            id: CoinLedgerID.catalogUnlock(itemID: CatalogItemID("unlock.test")),
            delta: -10,
            reason: .catalogUnlock(itemID: CatalogItemID("unlock.test")),
            createdAt: now
        )

        XCTAssertEqual(try CoinLedger.balance(entries: [grant, spend]), 15)

        let invalid = CoinLedgerEntry(
            id: LedgerEntryID("bad-grant"),
            delta: -1,
            reason: .signingBonus(version: 1),
            createdAt: now
        )
        XCTAssertThrowsError(try CoinLedger.balance(entries: [invalid])) { error in
            XCTAssertEqual(error as? CoinLedgerValidationError, .invalidDelta(invalid.id))
        }
    }

    func testRewardedAdLedgerDeduplicatesByProviderTransactionNotOfferCycle() throws {
        let providerTransactionID = AdProviderTransactionID("provider-completion-123")
        let firstOffer = RewardOfferID("reward-cycle/4")
        let retriedOffer = RewardOfferID("reward-cycle/5")
        let firstID = CoinLedgerID.rewardedAd(
            providerTransactionID: providerTransactionID
        )
        let retryID = CoinLedgerID.rewardedAd(
            providerTransactionID: providerTransactionID
        )

        XCTAssertEqual(firstID, retryID)
        XCTAssertEqual(Set([firstID, retryID]).count, 1)
        XCTAssertNotEqual(
            firstID,
            CoinLedgerID.rewardedAd(
                providerTransactionID: AdProviderTransactionID("provider-completion-456")
            )
        )

        let now = Date(timeIntervalSince1970: 1_500)
        let firstReceipt = CoinLedgerEntry(
            id: firstID,
            delta: EconomyConfiguration.rewardedAdCoins,
            reason: .rewardedAd(
                offerID: firstOffer,
                providerTransactionID: providerTransactionID
            ),
            createdAt: now
        )
        let retriedReceipt = CoinLedgerEntry(
            id: retryID,
            delta: EconomyConfiguration.rewardedAdCoins,
            reason: .rewardedAd(
                offerID: retriedOffer,
                providerTransactionID: providerTransactionID
            ),
            createdAt: now
        )

        XCTAssertEqual(try CoinLedger.balance(entries: [firstReceipt]), 100)
        let deduplicated = Dictionary(
            [firstReceipt, retriedReceipt].map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        XCTAssertEqual(
            deduplicated.count,
            1,
            "A provider completion must occupy one durable ledger key even if retried"
        )
    }

    func testRewardedAdProgressClampsAtFiveAndDoesNotBankRuns() {
        var state = RewardedAdState()
        let runIDs = (0 ..< 7).map {
            RunID(UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", $0 + 1))!)
        }

        for runID in runIDs.prefix(4) {
            XCTAssertFalse(state.recordValidRun(runID))
        }
        XCTAssertFalse(state.isEligible)
        XCTAssertTrue(state.recordValidRun(runIDs[4]))
        XCTAssertEqual(state.validRunsSinceReward, 5)
        XCTAssertEqual(state.eligibleOfferID, RewardedAdState.offerID(for: 0))

        XCTAssertFalse(state.recordValidRun(runIDs[5]))
        XCTAssertFalse(state.recordValidRun(runIDs[5]), "Duplicate run IDs must be ignored")
        XCTAssertEqual(state.validRunsSinceReward, 5)

        XCTAssertFalse(state.redeem(RewardOfferID("wrong-cycle")))
        XCTAssertTrue(state.redeem(RewardedAdState.offerID(for: 0)))
        XCTAssertEqual(state.cycle, 1)
        XCTAssertEqual(state.validRunsSinceReward, 0)
        XCTAssertNil(state.eligibleOfferID)

        XCTAssertFalse(state.recordValidRun(runIDs[6]))
        XCTAssertEqual(state.validRunsSinceReward, 1, "Runs completed while eligible must not bank")
    }

    func testIdentifierAndLaneCodableRoundTrip() throws {
        struct Payload: Codable, Equatable {
            let teamID: TeamID
            let lanes: Set<LaneID>
        }

        let payload = Payload(
            teamID: LaunchTeamID.novaCityComets,
            lanes: [.short, .deep, .touchdown]
        )
        let data = try JSONEncoder().encode(payload)
        XCTAssertEqual(try JSONDecoder().decode(Payload.self, from: data), payload)
    }

    private func makeRun(
        finishReason: RunFinishReason = .timerExpired,
        statistics: RunStatisticsSnapshot
    ) -> CompletedRun {
        let startedAt = Date(timeIntervalSince1970: 100)
        return CompletedRun(
            configuration: RunConfiguration(
                runID: RunID(UUID(uuidString: "00000000-0000-0000-0000-000000000001")!),
                randomSeed: 1,
                offenseTeamID: LaunchTeamID.novaCityComets,
                offenseJerseyID: JerseyID("jersey.nova_city_comets.primary"),
                defenseTeamID: LaunchTeamID.highMesaHelions,
                defenseJerseyID: JerseyID("jersey.high_mesa_helions.primary"),
                footballID: LaunchFootballID.standard,
                economyVersion: 1,
                startedAt: startedAt
            ),
            endedAt: startedAt.addingTimeInterval(60),
            elapsedGameplayMilliseconds: 60_000,
            finishReason: finishReason,
            score: 1_000,
            statistics: statistics,
            completedLaneIDs: [],
            bonusTouchdownCount: 0
        )
    }
}

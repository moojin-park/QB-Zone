import XCTest

@testable import PocketVector

final class StoreTransactionServiceTests: XCTestCase {
    func testTransactionFinishesOnlyAfterBoundDurableLedgerAcknowledgement() throws {
        let session = storeSession(account: "a", nonce: 1)
        let transaction = verifiedTransaction(id: 42, session: session)
        let pack = try approvedPack("pocket")
        let ledgerID = CoinLedgerID.storeKit(transactionID: transaction.transactionID)
        var reducer = StoreTransactionDeliveryReducer()

        XCTAssertEqual(
            reducer.receive(transaction, currentSession: session),
            [
                .settleLedger(
                    session: session,
                    transaction: transaction,
                    pack: pack,
                    ledgerEntryID: ledgerID
                ),
            ]
        )
        XCTAssertFalse(
            reducer.finishDidSucceed(
                transactionID: transaction.transactionID,
                session: session
            )
        )

        let acknowledgement = StoreLedgerAcknowledgement(
            transactionID: transaction.transactionID,
            ledgerEntryID: ledgerID,
            session: session
        )
        XCTAssertEqual(
            reducer.acknowledgeDurableLedger(
                acknowledgement,
                currentSession: session
            ),
            [.finish(session: session, transactionID: transaction.transactionID)]
        )
        XCTAssertTrue(
            reducer.finishDidSucceed(
                transactionID: transaction.transactionID,
                session: session
            )
        )
    }

    func testDuplicateDeliveryIsIdempotentAcrossEveryPhase() throws {
        let session = storeSession(account: "a", nonce: 1)
        let transaction = verifiedTransaction(id: 7, session: session)
        let ledgerID = CoinLedgerID.storeKit(transactionID: transaction.transactionID)
        var reducer = StoreTransactionDeliveryReducer()

        XCTAssertEqual(reducer.receive(transaction, currentSession: session).count, 1)
        XCTAssertEqual(reducer.receive(transaction, currentSession: session), [])

        _ = reducer.acknowledgeDurableLedger(
            StoreLedgerAcknowledgement(
                transactionID: transaction.transactionID,
                ledgerEntryID: ledgerID,
                session: session
            ),
            currentSession: session
        )
        XCTAssertEqual(
            reducer.receive(transaction, currentSession: session),
            [.finish(session: session, transactionID: transaction.transactionID)]
        )

        XCTAssertTrue(
            reducer.finishDidSucceed(
                transactionID: transaction.transactionID,
                session: session
            )
        )
        XCTAssertEqual(reducer.receive(transaction, currentSession: session), [])
        XCTAssertEqual(reducer.recoveryCommands(rebindingTo: session), [])
    }

    func testInvalidTokenVerificationAndCatalogPackNeverCreateSettlement() {
        let session = storeSession(account: "a", nonce: 1)
        var reducer = StoreTransactionDeliveryReducer()

        let unverified = StoreTransactionEnvelope(
            transactionID: 1,
            packID: CoinPackID("pocket"),
            appAccountToken: session.binding.appAccountToken,
            verification: .unverified(reason: "signature")
        )
        XCTAssertEqual(
            reducer.receive(unverified, currentSession: session),
            [.reject(transactionID: 1, reason: .unverified)]
        )

        let missingToken = StoreTransactionEnvelope(
            transactionID: 2,
            packID: CoinPackID("pocket"),
            appAccountToken: nil,
            verification: .verified
        )
        XCTAssertEqual(
            reducer.receive(missingToken, currentSession: session),
            [.reject(transactionID: 2, reason: .missingAppAccountToken)]
        )

        let wrongToken = StoreTransactionEnvelope(
            transactionID: 3,
            packID: CoinPackID("pocket"),
            appAccountToken: uuid(999),
            verification: .verified
        )
        XCTAssertEqual(
            reducer.receive(wrongToken, currentSession: session),
            [.reject(transactionID: 3, reason: .appAccountTokenMismatch)]
        )

        let unknownPack = StoreTransactionEnvelope(
            transactionID: 4,
            packID: CoinPackID("not-approved"),
            appAccountToken: session.binding.appAccountToken,
            verification: .verified
        )
        XCTAssertEqual(
            reducer.receive(unknownPack, currentSession: session),
            [.reject(transactionID: 4, reason: .unknownCoinPack)]
        )
        XCTAssertTrue(reducer.records.isEmpty)
    }

    func testAccountSwitchCannotCreditOrFinishWrongProfile() {
        let sharedAppToken = uuid(700)
        let sessionA = storeSession(account: "a", nonce: 1, appToken: sharedAppToken)
        let sessionB = storeSession(account: "b", nonce: 2, appToken: sharedAppToken)
        let transaction = verifiedTransaction(id: 10, session: sessionA)
        var reducer = StoreTransactionDeliveryReducer()

        _ = reducer.receive(transaction, currentSession: sessionA)
        XCTAssertEqual(
            reducer.receive(transaction, currentSession: sessionB),
            [.reject(transactionID: 10, reason: .accountBindingMismatch)]
        )
        XCTAssertEqual(reducer.recoveryCommands(rebindingTo: sessionB), [])

        let acknowledgement = StoreLedgerAcknowledgement(
            transactionID: 10,
            ledgerEntryID: CoinLedgerID.storeKit(transactionID: 10),
            session: sessionA
        )
        XCTAssertEqual(
            reducer.acknowledgeDurableLedger(
                acknowledgement,
                currentSession: sessionB
            ),
            [.reject(transactionID: 10, reason: .accountBindingMismatch)]
        )
        XCTAssertFalse(reducer.finishDidSucceed(transactionID: 10, session: sessionB))
    }

    func testRelaunchRebindsSameDurableOwnerAndRejectsStaleSessionCallback() throws {
        let originalSession = storeSession(account: "a", nonce: 1)
        let relaunchedSession = storeSession(account: "a", nonce: 2)
        let transaction = verifiedTransaction(id: 20, session: originalSession)
        let ledgerID = CoinLedgerID.storeKit(transactionID: 20)
        var original = StoreTransactionDeliveryReducer()
        _ = original.receive(transaction, currentSession: originalSession)

        let encoded = try JSONEncoder().encode(original)
        var restored = try JSONDecoder().decode(
            StoreTransactionDeliveryReducer.self,
            from: encoded
        )
        XCTAssertEqual(
            restored.recoveryCommands(rebindingTo: relaunchedSession),
            [
                .settleLedger(
                    session: relaunchedSession,
                    transaction: transaction,
                    pack: try approvedPack("pocket"),
                    ledgerEntryID: ledgerID
                ),
            ]
        )

        let staleAcknowledgement = StoreLedgerAcknowledgement(
            transactionID: 20,
            ledgerEntryID: ledgerID,
            session: originalSession
        )
        XCTAssertEqual(
            restored.acknowledgeDurableLedger(
                staleAcknowledgement,
                currentSession: relaunchedSession
            ),
            [.reject(transactionID: 20, reason: .staleSession)]
        )

        let currentAcknowledgement = StoreLedgerAcknowledgement(
            transactionID: 20,
            ledgerEntryID: ledgerID,
            session: relaunchedSession
        )
        XCTAssertEqual(
            restored.acknowledgeDurableLedger(
                currentAcknowledgement,
                currentSession: relaunchedSession
            ),
            [.finish(session: relaunchedSession, transactionID: 20)]
        )
        XCTAssertFalse(
            restored.finishDidSucceed(
                transactionID: 20,
                session: originalSession
            )
        )
        XCTAssertTrue(
            restored.finishDidSucceed(
                transactionID: 20,
                session: relaunchedSession
            )
        )
    }

    func testTransactionIDCollisionCannotReplaceOriginalOwnerOrPack() {
        let session = storeSession(account: "a", nonce: 1)
        let original = verifiedTransaction(id: 30, session: session, packID: "pocket")
        let collision = verifiedTransaction(id: 30, session: session, packID: "vault")
        var reducer = StoreTransactionDeliveryReducer()

        _ = reducer.receive(original, currentSession: session)
        XCTAssertEqual(
            reducer.receive(collision, currentSession: session),
            [.reject(transactionID: 30, reason: .transactionIDCollision)]
        )
        XCTAssertEqual(reducer.records[30]?.transaction, original)
    }

    private func verifiedTransaction(
        id: UInt64,
        session: StoreActiveSession,
        packID: String = "pocket"
    ) -> StoreTransactionEnvelope {
        StoreTransactionEnvelope(
            transactionID: id,
            packID: CoinPackID(packID),
            appAccountToken: session.binding.appAccountToken,
            verification: .verified
        )
    }

    private func approvedPack(_ id: String) throws -> CoinPackDescriptor {
        try XCTUnwrap(EconomyConfiguration.coinPacks.first { $0.id == CoinPackID(id) })
    }

    private func storeSession(
        account: String,
        nonce: Int,
        appToken: UUID? = nil
    ) -> StoreActiveSession {
        let binding = DurableAccountBinding(
            accountKey: ServiceAccountKey("account-\(account)"),
            profileID: uuid(account == "a" ? 100 : 200)
        )
        return StoreActiveSession(
            binding: StoreAccountBinding(
                account: binding,
                appAccountToken: appToken ?? uuid(account == "a" ? 300 : 400)
            ),
            nonce: uuid(nonce)
        )
    }

    private func uuid(_ value: Int) -> UUID {
        UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", value))")!
    }
}

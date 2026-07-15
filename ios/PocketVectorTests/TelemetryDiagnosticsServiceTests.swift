import XCTest

@testable import PocketVector

final class TelemetryDiagnosticsServiceTests: XCTestCase {
    func testTelemetryTombstoneDeduplicatesThenExpires() throws {
        let now = Date(timeIntervalSince1970: 100)
        let event = try telemetryEvent(at: now, payload: .runStarted)
        var queue = TelemetryEventQueue(
            retentionPolicy: TelemetryRetentionPolicy(
                tombstoneLifetime: 10,
                maximumTombstones: 10
            )
        )

        XCTAssertEqual(queue.enqueue(event, at: now), .enqueued)
        XCTAssertEqual(queue.enqueue(event, at: now), .duplicate)
        let batch = try XCTUnwrap(queue.nextBatch())
        queue.acknowledge(batch, at: now)
        XCTAssertEqual(queue.pendingCount, 0)
        XCTAssertEqual(queue.tombstoneCount, 1)
        XCTAssertEqual(
            queue.enqueue(event, at: now.addingTimeInterval(9)),
            .duplicate
        )
        XCTAssertEqual(
            queue.enqueue(event, at: now.addingTimeInterval(11)),
            .enqueued
        )
    }

    func testTelemetryTombstonesAreBoundedByRetentionPolicy() throws {
        let now = Date(timeIntervalSince1970: 100)
        let first = try telemetryEvent(at: now, payload: .runStarted)
        let second = try telemetryEvent(
            at: now.addingTimeInterval(1),
            payload: .storeOpened
        )
        let third = try telemetryEvent(
            at: now.addingTimeInterval(2),
            payload: .syncOutcome(.succeeded)
        )
        var queue = TelemetryEventQueue(
            retentionPolicy: TelemetryRetentionPolicy(
                tombstoneLifetime: 100,
                maximumTombstones: 2
            )
        )

        for (offset, event) in [first, second, third].enumerated() {
            let date = now.addingTimeInterval(TimeInterval(offset))
            XCTAssertEqual(queue.enqueue(event, at: date), .enqueued)
            queue.acknowledge(TelemetryBatch(events: [event]), at: date)
        }

        XCTAssertEqual(queue.tombstoneCount, 2)
        XCTAssertEqual(
            queue.enqueue(first, at: now.addingTimeInterval(3)),
            .enqueued
        )
        XCTAssertEqual(
            queue.enqueue(second, at: now.addingTimeInterval(3)),
            .duplicate
        )
    }

    func testTelemetryBatchOrderingIsDeterministic() throws {
        let now = Date(timeIntervalSince1970: 100)
        let first = try telemetryEvent(at: now, payload: .runStarted)
        let second = try telemetryEvent(
            at: now.addingTimeInterval(1),
            payload: .storeOpened
        )
        let third = try telemetryEvent(
            at: now.addingTimeInterval(2),
            payload: .syncOutcome(.offline)
        )
        var queue = TelemetryEventQueue()

        _ = queue.enqueue(third, at: now)
        _ = queue.enqueue(first, at: now)
        _ = queue.enqueue(second, at: now)

        XCTAssertEqual(
            try XCTUnwrap(queue.nextBatch()).events.map(\.name),
            [.runStarted, .storeOpened, .syncOutcome]
        )
    }

    func testTelemetryPrivacyGateRejectsEverySensitiveInput() {
        let now = Date(timeIntervalSince1970: 100)
        assertTelemetryRejection(
            .exactBalance(1_234),
            expected: .exactBalanceRejected,
            at: now
        )
        assertTelemetryRejection(
            .rawProfileID(UUID()),
            expected: .rawProfileIDRejected,
            at: now
        )
        assertTelemetryRejection(
            .providerTransactionID(AdProviderTransactionID("provider-secret")),
            expected: .providerTransactionIDRejected,
            at: now
        )
        assertTelemetryRejection(
            .detailedRunHistory([RunID(UUID())]),
            expected: .detailedRunHistoryRejected,
            at: now
        )
    }

    func testDiagnosticsPrivacyGateRejectsSensitiveMetadataAndFakeStoresOnlyClosedPayload() async throws {
        let now = Date(timeIntervalSince1970: 100)
        assertDiagnosticRejection(
            .exactBalance(1_234),
            expected: .exactBalanceRejected,
            at: now
        )
        assertDiagnosticRejection(
            .rawProfileID(UUID()),
            expected: .rawProfileIDRejected,
            at: now
        )
        assertDiagnosticRejection(
            .providerTransactionID(AdProviderTransactionID("provider-secret")),
            expected: .providerTransactionIDRejected,
            at: now
        )
        assertDiagnosticRejection(
            .detailedRunHistory([RunID(UUID())]),
            expected: .detailedRunHistoryRejected,
            at: now
        )

        let report = try DiagnosticReport.make(
            occurredAt: now,
            severity: .warning,
            input: .allowlisted(.store(.durableSettlementFailed))
        )
        let reporter = InMemoryDiagnosticsReporter()
        await reporter.report(report)
        let reports = await reporter.reports
        XCTAssertEqual(reports, [report])
    }

    private func telemetryEvent(
        at date: Date,
        payload: TelemetryPayload
    ) throws -> TelemetryEvent {
        try TelemetryEvent.make(
            occurredAt: date,
            input: .allowlisted(payload)
        )
    }

    private func assertTelemetryRejection(
        _ input: TelemetryInput,
        expected: TelemetryPrivacyError,
        at date: Date
    ) {
        XCTAssertThrowsError(
            try TelemetryEvent.make(occurredAt: date, input: input)
        ) { error in
            XCTAssertEqual(error as? TelemetryPrivacyError, expected)
        }
    }

    private func assertDiagnosticRejection(
        _ input: DiagnosticInput,
        expected: DiagnosticPrivacyError,
        at date: Date
    ) {
        XCTAssertThrowsError(
            try DiagnosticReport.make(
                occurredAt: date,
                severity: .error,
                input: input
            )
        ) { error in
            XCTAssertEqual(error as? DiagnosticPrivacyError, expected)
        }
    }
}

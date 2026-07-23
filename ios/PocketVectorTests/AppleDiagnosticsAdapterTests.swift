import Foundation
import MetricKit
import XCTest

@testable import PocketVector

final class AppleDiagnosticsAdapterTests: XCTestCase {
    func testDiagnosticsReporterMapsClosedCategoriesReasonsAndSeverities() async throws {
        let writer = RecordingAppleLogWriter()
        let reporter = OSLogDiagnosticsReporter(writer: writer)
        let fixtures: [(DiagnosticPayload, DiagnosticSeverity)] = [
            (.sync(.offline), .info),
            (.store(.verificationFailed), .warning),
            (.reward(.settlementFailed), .error),
            (.gameCenter(.scoreSubmissionFailed), .critical),
            (.persistence(.restoredBackup), .warning),
        ]

        for (offset, fixture) in fixtures.enumerated() {
            let report = try DiagnosticReport.make(
                occurredAt: Date(timeIntervalSince1970: TimeInterval(offset)),
                severity: fixture.1,
                input: .allowlisted(fixture.0)
            )
            await reporter.report(report)
        }

        let entries = await writer.entries()
        let diagnosticEntries = entries.compactMap { entry -> AppleDiagnosticLogEntry? in
            guard case let .diagnostic(diagnosticEntry) = entry else { return nil }
            return diagnosticEntry
        }
        XCTAssertEqual(diagnosticEntries.count, fixtures.count)
        XCTAssertEqual(
            diagnosticEntries.map(\.category),
            [.sync, .store, .reward, .gameCenter, .persistence]
        )
        XCTAssertEqual(
            diagnosticEntries.map(\.severity),
            [.info, .warning, .error, .critical, .warning]
        )
        XCTAssertEqual(
            diagnosticEntries.map(\.reason),
            [
                .sync(.offline),
                .store(.verificationFailed),
                .reward(.settlementFailed),
                .gameCenter(.scoreSubmissionFailed),
                .persistence(.restoredBackup),
            ]
        )
    }

    func testTelemetryMappingCoversAllowlistedNamesAndOnlyCoarseDimensions() {
        let correlationID = ReplayCorrelationID()
        let fixtures: [(TelemetryPayload, TelemetryEventName, [AppleTelemetryLogAttribute])] = [
            (.runStarted, .runStarted, []),
            (.runRestarted, .runRestarted, []),
            (
                .runResultsShown(
                    correlationID: correlationID,
                    scoreBand: .atLeast25K,
                    accuracyBand: .atLeast80,
                    attemptBand: .from10To19
                ),
                .runResultsShown,
                [
                    .scoreBand(.atLeast25K),
                    .accuracyBand(.atLeast80),
                    .attemptBand(.from10To19),
                ]
            ),
            (.replayStarted(correlationID: correlationID), .replayStarted, []),
            (.adOfferShown, .adOfferShown, []),
            (.adOfferAccepted, .adOfferAccepted, []),
            (.adRewardVerified, .adRewardVerified, []),
            (.storeOpened, .storeOpened, []),
            (
                .purchaseOutcome(pack: .bundle, outcome: .pending),
                .purchaseOutcome,
                [.coinPackTier(.bundle), .purchaseOutcome(.pending)]
            ),
            (
                .cosmeticUnlocked(kind: .football),
                .cosmeticUnlocked,
                [.cosmeticKind(.football)]
            ),
            (
                .syncOutcome(.retryableFailure),
                .syncOutcome,
                [.syncOutcome(.retryableFailure)]
            ),
        ]

        for fixture in fixtures {
            let entry = AppleTelemetryLogEntry(payload: fixture.0)
            XCTAssertEqual(entry.name, fixture.1)
            XCTAssertEqual(entry.attributes, fixture.2)
        }
    }

    func testTelemetryEntryDropsEventAndReplayIdentifiers() throws {
        let event = try TelemetryEvent.make(
            occurredAt: Date(timeIntervalSince1970: 1_234),
            input: .allowlisted(
                .runResultsShown(
                    correlationID: ReplayCorrelationID(),
                    scoreBand: .from15KTo24999,
                    accuracyBand: .from70To79,
                    attemptBand: .from3To9
                )
            )
        )
        let encodedEvent = try JSONEncoder().encode(event)
        let encodedText = try XCTUnwrap(String(data: encodedEvent, encoding: .utf8))
        let privateUUIDs = UUIDStrings.extract(from: encodedText)
        XCTAssertEqual(privateUUIDs.count, 2)

        let entry = AppleTelemetryLogEntry(event: event)
        let renderedEntry = String(reflecting: entry)
        for privateUUID in privateUUIDs {
            XCTAssertFalse(renderedEntry.localizedCaseInsensitiveContains(privateUUID))
        }
        XCTAssertEqual(
            entry.attributeToken,
            "score_band=from15KTo24999,accuracy_band=from70To79,attempt_band=from3To9"
        )

        XCTAssertThrowsError(
            try TelemetryEvent.make(
                occurredAt: .distantPast,
                input: .exactBalance(987_654_321)
            )
        )
        XCTAssertThrowsError(
            try TelemetryEvent.make(
                occurredAt: .distantPast,
                input: .providerTransactionID(
                    AdProviderTransactionID("provider-transaction-secret")
                )
            )
        )
        XCTAssertThrowsError(
            try TelemetryEvent.make(
                occurredAt: .distantPast,
                input: .detailedRunHistory([RunID()])
            )
        )
    }

    func testTelemetryRecorderWritesOnceAndDeduplicatesLocally() async throws {
        let writer = RecordingAppleLogWriter()
        let recorder = OSLogTelemetryRecorder(writer: writer)
        let now = Date(timeIntervalSince1970: 500)
        let event = try TelemetryEvent.make(
            occurredAt: now,
            input: .allowlisted(.purchaseOutcome(pack: .team, outcome: .succeeded))
        )

        let firstResult = await recorder.record(event, at: now)
        let secondResult = await recorder.record(event, at: now)
        XCTAssertEqual(firstResult, .enqueued)
        XCTAssertEqual(secondResult, .duplicate)

        let entries = await writer.entries()
        XCTAssertEqual(entries.count, 1)
        guard case let .telemetry(entry) = try XCTUnwrap(entries.first) else {
            return XCTFail("Expected one telemetry log entry")
        }
        XCTAssertEqual(entry.name, .purchaseOutcome)
        XCTAssertEqual(
            entry.attributes,
            [.coinPackTier(.team), .purchaseOutcome(.succeeded)]
        )
    }

    func testMetricKitReducerEmitsCoarseBandsAndNoEmptySignals() {
        let reducer = PrivacySafeAppleMetricKitPayloadReducer()

        XCTAssertEqual(reducer.reduce(metricPayloads: []), [])
        XCTAssertEqual(
            reducer.reduce(metricPayloads: [MXMetricPayload()]),
            [
                AppleMetricKitHealthSignal(
                    kind: .metricPayloadBatch,
                    countBand: .one
                )
            ]
        )
        XCTAssertEqual(
            reducer.reduce(
                metricPayloads: Array(repeating: MXMetricPayload(), count: 5)
            ),
            [
                AppleMetricKitHealthSignal(
                    kind: .metricPayloadBatch,
                    countBand: .fiveOrMore
                )
            ]
        )

        let diagnosticSignals = reducer.reduce(
            diagnosticPayloads: [MXDiagnosticPayload(), MXDiagnosticPayload()]
        )
        XCTAssertEqual(
            diagnosticSignals.first,
            AppleMetricKitHealthSignal(
                kind: .diagnosticPayloadBatch,
                countBand: .twoToFour
            )
        )
        XCTAssertTrue(diagnosticSignals.allSatisfy { signal in
            [.one, .twoToFour, .fiveOrMore].contains(signal.countBand)
        })
        XCTAssertNil(AppleMetricKitCountBand(positiveCount: 0))
    }

    func testMetricKitSubscriberForwardsReducedSignalsOffCallback() async {
        let metricSignal = AppleMetricKitHealthSignal(
            kind: .metricPayloadBatch,
            countBand: .one
        )
        let diagnosticSignal = AppleMetricKitHealthSignal(
            kind: .hangDiagnostic,
            countBand: .twoToFour
        )
        let batchReceipt = MetricKitBatchReceipt(expectedCount: 2)
        let handler = RecordingMetricKitSignalHandler(batchReceipt: batchReceipt)
        let bridge = AppleMetricKitSubscriberBridge(
            reducer: StubMetricKitReducer(
                metricSignals: [metricSignal],
                diagnosticSignals: [diagnosticSignal]
            ),
            handler: handler
        )

        bridge.didReceive([] as [MXMetricPayload])
        bridge.didReceive([] as [MXDiagnosticPayload])

        await fulfillment(of: [batchReceipt.expectation], timeout: 5)
        let batches = await handler.batches()
        XCTAssertEqual(batches, [[metricSignal], [diagnosticSignal]])
    }

    func testMetricKitSubscriberDoesNothingWhenReductionIsEmpty() async {
        let handler = RecordingMetricKitSignalHandler()
        let bridge = AppleMetricKitSubscriberBridge(
            reducer: StubMetricKitReducer(metricSignals: [], diagnosticSignals: []),
            handler: handler
        )

        bridge.didReceive([MXMetricPayload()])
        bridge.didReceive([MXDiagnosticPayload()])

        let batches = await handler.batches()
        XCTAssertEqual(batches, [])
    }

    func testMetricKitRegistrationLifecycleIsConcurrentAndIdempotent() async {
        let registration = StubMetricKitRegistration()
        let service = AppleMetricKitSubscriptionService(registration: registration)

        async let first = service.register()
        async let second = service.register()
        let registerResults = await [first, second]

        XCTAssertTrue(registerResults.contains(.registered))
        XCTAssertTrue(registerResults.contains(.alreadyRegistered))
        XCTAssertEqual(registration.snapshot().registerCalls, 1)
        let registeredState = await service.registrationState()
        XCTAssertTrue(registeredState)

        async let firstStop = service.unregister()
        async let secondStop = service.unregister()
        let unregisterResults = await [firstStop, secondStop]

        XCTAssertTrue(unregisterResults.contains(.unregistered))
        XCTAssertTrue(unregisterResults.contains(.alreadyUnregistered))
        XCTAssertEqual(registration.snapshot().unregisterCalls, 1)
        let unregisteredState = await service.registrationState()
        XCTAssertFalse(unregisteredState)
    }

    func testMetricKitRegistrationFailuresKeepRetryableState() async {
        let registration = StubMetricKitRegistration(failRegister: true)
        let service = AppleMetricKitSubscriptionService(registration: registration)

        let failedRegistration = await service.register()
        let stateAfterFailedRegistration = await service.registrationState()
        XCTAssertEqual(failedRegistration, .failed(.register))
        XCTAssertFalse(stateAfterFailedRegistration)

        registration.setFailures(register: false, unregister: true)
        let successfulRegistration = await service.register()
        let failedUnregistration = await service.unregister()
        let stateAfterFailedUnregistration = await service.registrationState()
        XCTAssertEqual(successfulRegistration, .registered)
        XCTAssertEqual(failedUnregistration, .failed(.unregister))
        XCTAssertTrue(stateAfterFailedUnregistration)

        registration.setFailures(register: false, unregister: false)
        let successfulUnregistration = await service.unregister()
        let finalState = await service.registrationState()
        XCTAssertEqual(successfulUnregistration, .unregistered)
        XCTAssertFalse(finalState)
        XCTAssertEqual(
            registration.snapshot(),
            StubMetricKitRegistration.Snapshot(registerCalls: 2, unregisterCalls: 2)
        )
    }

    func testNoOpAppleAdaptersCompleteWithoutExternalServices() async throws {
        let logWriter = NoOpApplePrivacySafeLogWriter()
        let reporter = OSLogDiagnosticsReporter(writer: logWriter)
        let report = try DiagnosticReport.make(
            occurredAt: .distantPast,
            severity: .info,
            input: .allowlisted(.sync(.offline))
        )
        await reporter.report(report)

        let metricHandler = NoOpAppleMetricKitHealthSignalHandler()
        await metricHandler.handle([
            AppleMetricKitHealthSignal(kind: .metricPayloadBatch, countBand: .one)
        ])

        let service = AppleMetricKitSubscriptionService(
            registration: NoOpAppleMetricKitRegistration()
        )
        let registerResult = await service.register()
        let unregisterResult = await service.unregister()
        XCTAssertEqual(registerResult, .registered)
        XCTAssertEqual(unregisterResult, .unregistered)
    }

}

private actor RecordingAppleLogWriter: ApplePrivacySafeLogWriting {
    private var storedEntries: [ApplePrivacySafeLogEntry] = []

    func write(_ entry: ApplePrivacySafeLogEntry) {
        storedEntries.append(entry)
    }

    func entries() -> [ApplePrivacySafeLogEntry] {
        storedEntries
    }
}

private struct StubMetricKitReducer: AppleMetricKitPayloadReducing {
    let metricSignals: [AppleMetricKitHealthSignal]
    let diagnosticSignals: [AppleMetricKitHealthSignal]

    func reduce(metricPayloads: [MXMetricPayload]) -> [AppleMetricKitHealthSignal] {
        metricSignals
    }

    func reduce(diagnosticPayloads: [MXDiagnosticPayload]) -> [AppleMetricKitHealthSignal] {
        diagnosticSignals
    }
}

private actor RecordingMetricKitSignalHandler: AppleMetricKitHealthSignalHandling {
    private var storedBatches: [[AppleMetricKitHealthSignal]] = []
    private let batchReceipt: MetricKitBatchReceipt?

    init(batchReceipt: MetricKitBatchReceipt? = nil) {
        self.batchReceipt = batchReceipt
    }

    func handle(_ signals: [AppleMetricKitHealthSignal]) {
        storedBatches.append(signals)
        batchReceipt?.record()
    }

    func batches() -> [[AppleMetricKitHealthSignal]] {
        storedBatches
    }

}

/// XCTestExpectation is documented for cross-thread fulfillment. This wrapper
/// makes that synchronization intent explicit at the Sendable actor boundary.
private final class MetricKitBatchReceipt: @unchecked Sendable {
    let expectation: XCTestExpectation

    init(expectedCount: Int) {
        expectation = XCTestExpectation(description: "MetricKit batches forwarded")
        expectation.expectedFulfillmentCount = expectedCount
        expectation.assertForOverFulfill = true
    }

    func record() {
        expectation.fulfill()
    }
}

private final class StubMetricKitRegistration: AppleMetricKitRegistering,
    @unchecked Sendable
{
    struct Snapshot: Equatable, Sendable {
        let registerCalls: Int
        let unregisterCalls: Int
    }

    private enum StubError: Error {
        case requestedFailure
    }

    private let lock = NSLock()
    private var registerCalls = 0
    private var unregisterCalls = 0
    private var failRegister: Bool
    private var failUnregister: Bool

    init(failRegister: Bool = false, failUnregister: Bool = false) {
        self.failRegister = failRegister
        self.failUnregister = failUnregister
    }

    func register() throws {
        try lock.withLock {
            registerCalls += 1
            if failRegister {
                throw StubError.requestedFailure
            }
        }
    }

    func unregister() throws {
        try lock.withLock {
            unregisterCalls += 1
            if failUnregister {
                throw StubError.requestedFailure
            }
        }
    }

    func setFailures(register: Bool, unregister: Bool) {
        lock.withLock {
            failRegister = register
            failUnregister = unregister
        }
    }

    func snapshot() -> Snapshot {
        lock.withLock {
            Snapshot(registerCalls: registerCalls, unregisterCalls: unregisterCalls)
        }
    }
}

private enum UUIDStrings {
    static func extract(from text: String) -> [String] {
        let pattern = #"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[1-5][0-9A-Fa-f]{3}-[89ABab][0-9A-Fa-f]{3}-[0-9A-Fa-f]{12}"#
        let expression = try! NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..., in: text)
        return expression.matches(in: text, range: range).compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            return String(text[range])
        }
    }
}

import Foundation
import XCTest

@testable import PocketVector

final class AppleDiagnosticsRuntimeTests: XCTestCase, @unchecked Sendable {
    func testRunRegistersDrainsInputsInOrderAndUnregistersOnce() async {
        let log = OrderedDiagnosticsLog()
        let registration = RuntimeMetricKitRegistration()
        let runtime = makeRuntime(log: log, registration: registration)
        let task = Task { await runtime.run() }

        let didRegister = await eventually {
            registration.snapshot().registerCalls == 1
        }
        XCTAssertTrue(didRegister)

        let firstDate = Date(timeIntervalSince1970: 100)
        let secondDate = Date(timeIntervalSince1970: 101)
        runtime.sink.record(.runStarted, at: firstDate)
        runtime.sink.report(
            .persistence(.restoredBackup),
            severity: .warning,
            at: secondDate
        )

        let didDrainInputs = await eventually { await log.count() == 2 }
        XCTAssertTrue(didDrainInputs)
        let entries = await log.entries()
        XCTAssertEqual(
            entries,
            [
                .telemetry(.runStarted, occurredAt: firstDate),
                .diagnostic(
                    .persistence(.restoredBackup),
                    severity: .warning,
                    occurredAt: secondDate
                ),
            ]
        )

        task.cancel()
        await task.value

        XCTAssertEqual(
            registration.snapshot(),
            RuntimeMetricKitRegistration.Snapshot(
                registerCalls: 1,
                unregisterCalls: 1
            )
        )
    }

    func testRegistrationFailureDoesNotStopTelemetryAndDoesNotFakeUnregister() async {
        let log = OrderedDiagnosticsLog()
        let registration = RuntimeMetricKitRegistration(failRegister: true)
        let runtime = makeRuntime(log: log, registration: registration)
        let task = Task { await runtime.run() }

        let didAttemptRegistration = await eventually {
            registration.snapshot().registerCalls == 1
        }
        XCTAssertTrue(didAttemptRegistration)

        let occurredAt = Date(timeIntervalSince1970: 200)
        runtime.sink.record(.storeOpened, at: occurredAt)
        let didRecordTelemetry = await eventually { await log.count() == 1 }
        XCTAssertTrue(didRecordTelemetry)
        let entries = await log.entries()
        XCTAssertEqual(
            entries,
            [.telemetry(.storeOpened, occurredAt: occurredAt)]
        )

        task.cancel()
        await task.value

        XCTAssertEqual(
            registration.snapshot(),
            RuntimeMetricKitRegistration.Snapshot(
                registerCalls: 1,
                unregisterCalls: 0
            )
        )
    }

    func testConcurrentRunAttemptDoesNotDuplicateMetricKitLifecycle() async {
        let log = OrderedDiagnosticsLog()
        let registration = RuntimeMetricKitRegistration()
        let runtime = makeRuntime(log: log, registration: registration)
        let first = Task { await runtime.run() }

        let didRegister = await eventually {
            registration.snapshot().registerCalls == 1
        }
        XCTAssertTrue(didRegister)

        let second = Task { await runtime.run() }
        await second.value
        XCTAssertEqual(registration.snapshot().registerCalls, 1)

        first.cancel()
        await first.value
        XCTAssertEqual(registration.snapshot().unregisterCalls, 1)
    }

    func testCancelledRuntimeCanRestartAndDrainInputsQueuedBetweenRuns() async {
        let log = OrderedDiagnosticsLog()
        let registration = RuntimeMetricKitRegistration()
        let runtime = makeRuntime(log: log, registration: registration)
        let first = Task { await runtime.run() }

        let firstDidRegister = await eventually {
            registration.snapshot().registerCalls == 1
        }
        XCTAssertTrue(firstDidRegister)

        let firstDate = Date(timeIntervalSince1970: 300)
        runtime.sink.record(.runStarted, at: firstDate)
        let firstDidDrain = await eventually { await log.count() == 1 }
        XCTAssertTrue(firstDidDrain)

        first.cancel()
        await first.value
        XCTAssertEqual(registration.snapshot().unregisterCalls, 1)

        let secondDate = Date(timeIntervalSince1970: 301)
        runtime.sink.record(.storeOpened, at: secondDate)
        let second = Task { await runtime.run() }

        let secondDidRegisterAndDrain = await eventually {
            guard registration.snapshot().registerCalls == 2 else {
                return false
            }
            return await log.count() == 2
        }
        XCTAssertTrue(secondDidRegisterAndDrain)
        let entries = await log.entries()
        XCTAssertEqual(
            entries,
            [
                .telemetry(.runStarted, occurredAt: firstDate),
                .telemetry(.storeOpened, occurredAt: secondDate),
            ]
        )

        second.cancel()
        await second.value
        XCTAssertEqual(registration.snapshot().unregisterCalls, 2)
    }

    func testTelemetryBandClassifierCoversEveryBoundary() {
        XCTAssertEqual(TelemetryBandClassifier.scoreBand(for: 4_999), .under5K)
        XCTAssertEqual(TelemetryBandClassifier.scoreBand(for: 5_000), .from5KTo14999)
        XCTAssertEqual(TelemetryBandClassifier.scoreBand(for: 14_999), .from5KTo14999)
        XCTAssertEqual(TelemetryBandClassifier.scoreBand(for: 15_000), .from15KTo24999)
        XCTAssertEqual(TelemetryBandClassifier.scoreBand(for: 24_999), .from15KTo24999)
        XCTAssertEqual(TelemetryBandClassifier.scoreBand(for: 25_000), .atLeast25K)

        XCTAssertEqual(
            TelemetryBandClassifier.accuracyBand(forDisplayedPercent: 49),
            .under50
        )
        XCTAssertEqual(
            TelemetryBandClassifier.accuracyBand(forDisplayedPercent: 50),
            .from50To69
        )
        XCTAssertEqual(
            TelemetryBandClassifier.accuracyBand(forDisplayedPercent: 69),
            .from50To69
        )
        XCTAssertEqual(
            TelemetryBandClassifier.accuracyBand(forDisplayedPercent: 70),
            .from70To79
        )
        XCTAssertEqual(
            TelemetryBandClassifier.accuracyBand(forDisplayedPercent: 79),
            .from70To79
        )
        XCTAssertEqual(
            TelemetryBandClassifier.accuracyBand(forDisplayedPercent: 80),
            .atLeast80
        )

        XCTAssertEqual(TelemetryBandClassifier.attemptBand(for: 2), .under3)
        XCTAssertEqual(TelemetryBandClassifier.attemptBand(for: 3), .from3To9)
        XCTAssertEqual(TelemetryBandClassifier.attemptBand(for: 9), .from3To9)
        XCTAssertEqual(TelemetryBandClassifier.attemptBand(for: 10), .from10To19)
        XCTAssertEqual(TelemetryBandClassifier.attemptBand(for: 19), .from10To19)
        XCTAssertEqual(TelemetryBandClassifier.attemptBand(for: 20), .atLeast20)
    }

    func testRunResultsClassifierBuildsOnlyCoarseDimensions() {
        let correlationID = ReplayCorrelationID()

        XCTAssertEqual(
            TelemetryBandClassifier.runResultsPayload(
                correlationID: correlationID,
                score: 18_750,
                displayedAccuracyPercent: 74,
                attempts: 12
            ),
            .runResultsShown(
                correlationID: correlationID,
                scoreBand: .from15KTo24999,
                accuracyBand: .from70To79,
                attemptBand: .from10To19
            )
        )
    }

    private func makeRuntime(
        log: OrderedDiagnosticsLog,
        registration: RuntimeMetricKitRegistration
    ) -> AppleDiagnosticsRuntime {
        AppleDiagnosticsRuntime(
            telemetryRecorder: OrderedRuntimeTelemetryRecorder(log: log),
            diagnosticsReporter: OrderedRuntimeDiagnosticsReporter(log: log),
            metricKitSubscription: AppleMetricKitSubscriptionService(
                registration: registration
            )
        )
    }

    private func eventually(
        iterations: Int = 2_000,
        condition: @escaping @Sendable () async -> Bool
    ) async -> Bool {
        for _ in 0 ..< iterations {
            if await condition() { return true }
            await Task.yield()
        }
        return false
    }
}

private actor OrderedDiagnosticsLog {
    enum Entry: Equatable, Sendable {
        case telemetry(TelemetryPayload, occurredAt: Date)
        case diagnostic(
            DiagnosticPayload,
            severity: DiagnosticSeverity,
            occurredAt: Date
        )
    }

    private var storedEntries: [Entry] = []

    func append(_ entry: Entry) {
        storedEntries.append(entry)
    }

    func entries() -> [Entry] {
        storedEntries
    }

    func count() -> Int {
        storedEntries.count
    }
}

private actor OrderedRuntimeTelemetryRecorder: TelemetryRecording {
    let log: OrderedDiagnosticsLog

    init(log: OrderedDiagnosticsLog) {
        self.log = log
    }

    func record(
        _ event: TelemetryEvent,
        at date: Date
    ) async -> TelemetryEnqueueResult {
        await log.append(.telemetry(event.payload, occurredAt: date))
        return .enqueued
    }
}

private struct OrderedRuntimeDiagnosticsReporter: DiagnosticsReporting {
    let log: OrderedDiagnosticsLog

    func report(_ report: DiagnosticReport) async {
        await log.append(
            .diagnostic(
                report.payload,
                severity: report.severity,
                occurredAt: report.occurredAt
            )
        )
    }
}

private final class RuntimeMetricKitRegistration: AppleMetricKitRegistering,
    @unchecked Sendable
{
    struct Snapshot: Equatable {
        let registerCalls: Int
        let unregisterCalls: Int
    }

    private let lock = NSLock()
    private let failRegister: Bool
    private var registerCalls = 0
    private var unregisterCalls = 0

    init(failRegister: Bool = false) {
        self.failRegister = failRegister
    }

    func register() throws {
        try lock.withLock {
            registerCalls += 1
            if failRegister {
                throw Failure.expected
            }
        }
    }

    func unregister() {
        lock.withLock {
            unregisterCalls += 1
        }
    }

    func snapshot() -> Snapshot {
        lock.withLock {
            Snapshot(
                registerCalls: registerCalls,
                unregisterCalls: unregisterCalls
            )
        }
    }

    private enum Failure: Error {
        case expected
    }
}

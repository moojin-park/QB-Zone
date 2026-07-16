import Foundation

enum AppleDiagnosticsMode: Equatable, Sendable {
    case appleOnly
}

enum AppleDiagnosticsInput: Equatable, Sendable {
    case telemetry(TelemetryPayload, occurredAt: Date)
    case diagnostic(
        DiagnosticPayload,
        severity: DiagnosticSeverity,
        occurredAt: Date
    )
}

/// A synchronous, Sendable producer for the runtime's single ordered input
/// stream. Callers can record only closed, privacy-reviewed payload enums.
struct AppleDiagnosticsSink: Sendable {
    private let enqueue: @Sendable (AppleDiagnosticsInput) -> Void

    fileprivate init(
        enqueue: @escaping @Sendable (AppleDiagnosticsInput) -> Void
    ) {
        self.enqueue = enqueue
    }

    func record(_ payload: TelemetryPayload, at occurredAt: Date) {
        enqueue(.telemetry(payload, occurredAt: occurredAt))
    }

    func report(
        _ payload: DiagnosticPayload,
        severity: DiagnosticSeverity,
        at occurredAt: Date
    ) {
        enqueue(
            .diagnostic(
                payload,
                severity: severity,
                occurredAt: occurredAt
            )
        )
    }
}

/// Keeps diagnostics inputs outside any one `AsyncStream` iterator. Cancelling
/// a Swift concurrency iterator permanently terminates that stream, so the
/// stream is used only as a restartable wake-up signal while the ordered inputs
/// remain in this lock-protected queue.
private final class AppleDiagnosticsInputChannel: @unchecked Sendable {
    private struct SignalSubscription {
        let id: UUID
        let continuation: AsyncStream<Void>.Continuation
    }

    private let lock = NSLock()
    private var pendingInputs: [AppleDiagnosticsInput] = []
    private var pendingStartIndex = 0
    private var signalSubscription: SignalSubscription?

    func enqueue(_ input: AppleDiagnosticsInput) {
        lock.withLock {
            pendingInputs.append(input)
            _ = signalSubscription?.continuation.yield(())
        }
    }

    func makeSignalStream() -> AsyncStream<Void> {
        let subscriptionID = UUID()
        let pair = AsyncStream<Void>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        pair.continuation.onTermination = { [weak self] _ in
            self?.removeSignalSubscription(id: subscriptionID)
        }

        let previousContinuation = lock.withLock {
            let previousContinuation = signalSubscription?.continuation
            signalSubscription = SignalSubscription(
                id: subscriptionID,
                continuation: pair.continuation
            )
            if pendingStartIndex < pendingInputs.count {
                pair.continuation.yield(())
            }
            return previousContinuation
        }
        // `finish()` may synchronously invoke `onTermination`, which takes the
        // same lock. Finish only after the replacement is installed and the
        // critical section has ended.
        previousContinuation?.finish()
        return pair.stream
    }

    func dequeue() -> AppleDiagnosticsInput? {
        lock.withLock {
            guard pendingStartIndex < pendingInputs.count else {
                pendingInputs.removeAll(keepingCapacity: true)
                pendingStartIndex = 0
                return nil
            }

            let input = pendingInputs[pendingStartIndex]
            pendingStartIndex += 1
            if pendingStartIndex >= 64,
               pendingStartIndex * 2 >= pendingInputs.count {
                pendingInputs.removeFirst(pendingStartIndex)
                pendingStartIndex = 0
            }
            return input
        }
    }

    private func removeSignalSubscription(id: UUID) {
        lock.withLock {
            guard signalSubscription?.id == id else { return }
            signalSubscription = nil
        }
    }
}

enum TelemetryBandClassifier {
    static func scoreBand(for score: Int) -> TelemetryScoreBand {
        switch score {
        case ..<5_000:
            .under5K
        case 5_000 ..< 15_000:
            .from5KTo14999
        case 15_000 ..< 25_000:
            .from15KTo24999
        default:
            .atLeast25K
        }
    }

    static func accuracyBand(
        forDisplayedPercent accuracyPercent: Int
    ) -> TelemetryAccuracyBand {
        switch accuracyPercent {
        case ..<50:
            .under50
        case 50 ..< 70:
            .from50To69
        case 70 ..< 80:
            .from70To79
        default:
            .atLeast80
        }
    }

    static func attemptBand(for attempts: Int) -> TelemetryAttemptBand {
        switch attempts {
        case ..<3:
            .under3
        case 3 ..< 10:
            .from3To9
        case 10 ..< 20:
            .from10To19
        default:
            .atLeast20
        }
    }

    static func runResultsPayload(
        correlationID: ReplayCorrelationID,
        score: Int,
        displayedAccuracyPercent: Int,
        attempts: Int
    ) -> TelemetryPayload {
        .runResultsShown(
            correlationID: correlationID,
            scoreBand: scoreBand(for: score),
            accuracyBand: accuracyBand(
                forDisplayedPercent: displayedAccuracyPercent
            ),
            attemptBand: attemptBand(for: attempts)
        )
    }
}

/// Retains the complete Apple-only diagnostics graph for one app runtime.
///
/// MetricKit registration is lifecycle-scoped to `run()`. Registration
/// failure never disables OSLog telemetry or diagnostics. The compatibility
/// adapter intentionally remains behind `AppleMetricKitSubscriptionService`
/// while Pocket Vector supports iOS 17; a future iOS baseline can replace that
/// adapter without changing this runtime or its callers.
actor AppleDiagnosticsRuntime {
    nonisolated let sink: AppleDiagnosticsSink

    private let inputChannel: AppleDiagnosticsInputChannel
    private let telemetryRecorder: any TelemetryRecording
    private let diagnosticsReporter: any DiagnosticsReporting
    private let metricKitSubscription: AppleMetricKitSubscriptionService
    private var isRunning = false

    init(
        telemetryRecorder: any TelemetryRecording,
        diagnosticsReporter: any DiagnosticsReporting,
        metricKitSubscription: AppleMetricKitSubscriptionService
    ) {
        let inputChannel = AppleDiagnosticsInputChannel()
        self.inputChannel = inputChannel
        sink = AppleDiagnosticsSink { input in
            inputChannel.enqueue(input)
        }
        self.telemetryRecorder = telemetryRecorder
        self.diagnosticsReporter = diagnosticsReporter
        self.metricKitSubscription = metricKitSubscription
    }

    static func live(
        subsystem: String = Bundle.main.bundleIdentifier ?? "PocketVector"
    ) -> AppleDiagnosticsRuntime {
        let writer = OSLogApplePrivacySafeLogWriter(subsystem: subsystem)
        let telemetryRecorder = OSLogTelemetryRecorder(writer: writer)
        let diagnosticsReporter = OSLogDiagnosticsReporter(writer: writer)
        let metricKitHandler = OSLogAppleMetricKitHealthSignalHandler(
            writer: writer
        )
        let subscriber = AppleMetricKitSubscriberBridge(
            handler: metricKitHandler
        )
        let registration = SystemAppleMetricKitRegistration(
            subscriber: subscriber
        )
        let subscription = AppleMetricKitSubscriptionService(
            registration: registration
        )

        return AppleDiagnosticsRuntime(
            telemetryRecorder: telemetryRecorder,
            diagnosticsReporter: diagnosticsReporter,
            metricKitSubscription: subscription
        )
    }

    func run() async {
        guard !isRunning, !Task.isCancelled else { return }
        isRunning = true

        _ = await metricKitSubscription.register()

        let signalStream = inputChannel.makeSignalStream()
        for await _ in signalStream {
            guard !Task.isCancelled else { break }
            while !Task.isCancelled,
                  let input = inputChannel.dequeue() {
                await process(input)
            }
        }

        _ = await metricKitSubscription.unregister()
        isRunning = false
    }

    private func process(_ input: AppleDiagnosticsInput) async {
        switch input {
        case let .telemetry(payload, occurredAt):
            guard let event = try? TelemetryEvent.make(
                occurredAt: occurredAt,
                input: .allowlisted(payload)
            ) else {
                return
            }
            _ = await telemetryRecorder.record(event, at: occurredAt)

        case let .diagnostic(payload, severity, occurredAt):
            guard let report = try? DiagnosticReport.make(
                occurredAt: occurredAt,
                severity: severity,
                input: .allowlisted(payload)
            ) else {
                return
            }
            await diagnosticsReporter.report(report)
        }
    }
}

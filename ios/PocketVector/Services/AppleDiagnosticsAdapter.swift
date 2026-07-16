import Foundation
import MetricKit
import OSLog

enum AppleDiagnosticLogCategory: String, Equatable, Sendable {
    case sync
    case store
    case reward
    case gameCenter = "game_center"
    case persistence
}

enum AppleDiagnosticLogReason: Equatable, Sendable {
    case sync(DiagnosticSyncFailure)
    case store(DiagnosticStoreFailure)
    case reward(DiagnosticRewardFailure)
    case gameCenter(DiagnosticGameCenterFailure)
    case persistence(DiagnosticPersistenceRecovery)

    var token: String {
        switch self {
        case let .sync(reason): reason.rawValue
        case let .store(reason): reason.rawValue
        case let .reward(reason): reason.rawValue
        case let .gameCenter(reason): reason.rawValue
        case let .persistence(reason): reason.rawValue
        }
    }
}

struct AppleDiagnosticLogEntry: Equatable, Sendable {
    let category: AppleDiagnosticLogCategory
    let severity: DiagnosticSeverity
    let reason: AppleDiagnosticLogReason

    init(report: DiagnosticReport) {
        severity = report.severity
        switch report.payload {
        case let .sync(reason):
            category = .sync
            self.reason = .sync(reason)
        case let .store(reason):
            category = .store
            self.reason = .store(reason)
        case let .reward(reason):
            category = .reward
            self.reason = .reward(reason)
        case let .gameCenter(reason):
            category = .gameCenter
            self.reason = .gameCenter(reason)
        case let .persistence(reason):
            category = .persistence
            self.reason = .persistence(reason)
        }
    }
}

enum AppleTelemetryLogAttribute: Equatable, Sendable {
    case scoreBand(TelemetryScoreBand)
    case accuracyBand(TelemetryAccuracyBand)
    case attemptBand(TelemetryAttemptBand)
    case coinPackTier(TelemetryCoinPackTier)
    case purchaseOutcome(TelemetryPurchaseOutcome)
    case cosmeticKind(TelemetryCosmeticKind)
    case syncOutcome(TelemetrySyncOutcome)

    var token: String {
        switch self {
        case let .scoreBand(value): "score_band=\(value.rawValue)"
        case let .accuracyBand(value): "accuracy_band=\(value.rawValue)"
        case let .attemptBand(value): "attempt_band=\(value.rawValue)"
        case let .coinPackTier(value): "coin_pack_tier=\(value.rawValue)"
        case let .purchaseOutcome(value): "purchase_outcome=\(value.rawValue)"
        case let .cosmeticKind(value): "cosmetic_kind=\(value.rawValue)"
        case let .syncOutcome(value): "sync_outcome=\(value.rawValue)"
        }
    }
}

struct AppleTelemetryLogEntry: Equatable, Sendable {
    let name: TelemetryEventName
    let attributes: [AppleTelemetryLogAttribute]

    init(event: TelemetryEvent) {
        self.init(payload: event.payload)
    }

    init(payload: TelemetryPayload) {
        name = payload.name
        switch payload {
        case .runStarted,
             .replayStarted,
             .adOfferShown,
             .adOfferAccepted,
             .adRewardVerified,
             .storeOpened:
            attributes = []
        case let .runResultsShown(_, scoreBand, accuracyBand, attemptBand):
            attributes = [
                .scoreBand(scoreBand),
                .accuracyBand(accuracyBand),
                .attemptBand(attemptBand),
            ]
        case let .purchaseOutcome(pack, outcome):
            attributes = [
                .coinPackTier(pack),
                .purchaseOutcome(outcome),
            ]
        case let .cosmeticUnlocked(kind):
            attributes = [.cosmeticKind(kind)]
        case let .syncOutcome(outcome):
            attributes = [.syncOutcome(outcome)]
        }
    }

    var attributeToken: String {
        guard !attributes.isEmpty else { return "none" }
        return attributes.map(\.token).joined(separator: ",")
    }
}

enum AppleMetricKitCountBand: String, Equatable, Sendable {
    case one
    case twoToFour = "two_to_four"
    case fiveOrMore = "five_or_more"

    init?(positiveCount: Int) {
        guard positiveCount > 0 else { return nil }
        switch positiveCount {
        case 1: self = .one
        case 2 ... 4: self = .twoToFour
        default: self = .fiveOrMore
        }
    }
}

enum AppleMetricKitSignalKind: String, Equatable, Sendable {
    case metricPayloadBatch = "metric_payload_batch"
    case diagnosticPayloadBatch = "diagnostic_payload_batch"
    case crashDiagnostic = "crash_diagnostic"
    case hangDiagnostic = "hang_diagnostic"
    case cpuExceptionDiagnostic = "cpu_exception_diagnostic"
    case diskWriteExceptionDiagnostic = "disk_write_exception_diagnostic"
    case appLaunchDiagnostic = "app_launch_diagnostic"
}

/// A deliberately lossy local signal. It contains neither MetricKit payload
/// JSON nor timestamps, versions, call stacks, device data, or user data.
struct AppleMetricKitHealthSignal: Equatable, Sendable {
    let kind: AppleMetricKitSignalKind
    let countBand: AppleMetricKitCountBand
}

enum ApplePrivacySafeLogEntry: Equatable, Sendable {
    case diagnostic(AppleDiagnosticLogEntry)
    case telemetry(AppleTelemetryLogEntry)
    case metricKit(AppleMetricKitHealthSignal)
}

protocol ApplePrivacySafeLogWriting: Sendable {
    func write(_ entry: ApplePrivacySafeLogEntry) async
}

struct NoOpApplePrivacySafeLogWriter: ApplePrivacySafeLogWriting {
    func write(_ entry: ApplePrivacySafeLogEntry) async {}
}

/// Unified logging receives only values derived from the closed enums above.
/// Those allowlisted tokens are intentionally public; no caller-provided text
/// or identifiers reach an OSLog interpolation.
struct OSLogApplePrivacySafeLogWriter: ApplePrivacySafeLogWriting {
    private let diagnosticsLogger: Logger
    private let telemetryLogger: Logger
    private let metricKitLogger: Logger

    init(subsystem: String = Bundle.main.bundleIdentifier ?? "PocketVector") {
        diagnosticsLogger = Logger(subsystem: subsystem, category: "diagnostics")
        telemetryLogger = Logger(subsystem: subsystem, category: "telemetry")
        metricKitLogger = Logger(subsystem: subsystem, category: "metric_kit")
    }

    func write(_ entry: ApplePrivacySafeLogEntry) async {
        switch entry {
        case let .diagnostic(entry):
            writeDiagnostic(entry)
        case let .telemetry(entry):
            let name = entry.name.rawValue
            let attributes = entry.attributeToken
            telemetryLogger.info(
                "event=\(name, privacy: .public) dimensions=\(attributes, privacy: .public)"
            )
        case let .metricKit(signal):
            let kind = signal.kind.rawValue
            let countBand = signal.countBand.rawValue
            metricKitLogger.notice(
                "signal=\(kind, privacy: .public) count_band=\(countBand, privacy: .public)"
            )
        }
    }

    private func writeDiagnostic(_ entry: AppleDiagnosticLogEntry) {
        let category = entry.category.rawValue
        let reason = entry.reason.token
        switch entry.severity {
        case .info:
            diagnosticsLogger.info(
                "category=\(category, privacy: .public) reason=\(reason, privacy: .public)"
            )
        case .warning:
            diagnosticsLogger.warning(
                "category=\(category, privacy: .public) reason=\(reason, privacy: .public)"
            )
        case .error:
            diagnosticsLogger.error(
                "category=\(category, privacy: .public) reason=\(reason, privacy: .public)"
            )
        case .critical:
            diagnosticsLogger.critical(
                "category=\(category, privacy: .public) reason=\(reason, privacy: .public)"
            )
        }
    }
}

struct OSLogDiagnosticsReporter: DiagnosticsReporting {
    private let writer: any ApplePrivacySafeLogWriting

    init(writer: any ApplePrivacySafeLogWriting) {
        self.writer = writer
    }

    func report(_ report: DiagnosticReport) async {
        await writer.write(.diagnostic(AppleDiagnosticLogEntry(report: report)))
    }
}

actor OSLogTelemetryRecorder: TelemetryRecording {
    private let writer: any ApplePrivacySafeLogWriting
    private var queue: TelemetryEventQueue

    init(
        writer: any ApplePrivacySafeLogWriting,
        retentionPolicy: TelemetryRetentionPolicy = TelemetryRetentionPolicy()
    ) {
        self.writer = writer
        queue = TelemetryEventQueue(retentionPolicy: retentionPolicy)
    }

    @discardableResult
    func record(_ event: TelemetryEvent, at date: Date) async -> TelemetryEnqueueResult {
        let result = queue.enqueue(event, at: date)
        guard result == .enqueued else { return result }

        // OSLog is the terminal local sink, so acknowledge before yielding to
        // retain duplicate protection if the calling task is cancelled.
        queue.acknowledge(TelemetryBatch(events: [event]), at: date)
        await writer.write(.telemetry(AppleTelemetryLogEntry(event: event)))
        return .enqueued
    }
}

protocol AppleMetricKitPayloadReducing: Sendable {
    func reduce(metricPayloads: [MXMetricPayload]) -> [AppleMetricKitHealthSignal]
    func reduce(diagnosticPayloads: [MXDiagnosticPayload]) -> [AppleMetricKitHealthSignal]
}

struct PrivacySafeAppleMetricKitPayloadReducer: AppleMetricKitPayloadReducing {
    func reduce(metricPayloads: [MXMetricPayload]) -> [AppleMetricKitHealthSignal] {
        signal(kind: .metricPayloadBatch, positiveCount: metricPayloads.count)
            .map { [$0] } ?? []
    }

    func reduce(diagnosticPayloads: [MXDiagnosticPayload]) -> [AppleMetricKitHealthSignal] {
        var signals: [AppleMetricKitHealthSignal] = []
        append(
            kind: .diagnosticPayloadBatch,
            positiveCount: diagnosticPayloads.count,
            to: &signals
        )
        append(
            kind: .crashDiagnostic,
            positiveCount: saturatedCount(diagnosticPayloads) {
                $0.crashDiagnostics?.count ?? 0
            },
            to: &signals
        )
        append(
            kind: .hangDiagnostic,
            positiveCount: saturatedCount(diagnosticPayloads) {
                $0.hangDiagnostics?.count ?? 0
            },
            to: &signals
        )
        append(
            kind: .cpuExceptionDiagnostic,
            positiveCount: saturatedCount(diagnosticPayloads) {
                $0.cpuExceptionDiagnostics?.count ?? 0
            },
            to: &signals
        )
        append(
            kind: .diskWriteExceptionDiagnostic,
            positiveCount: saturatedCount(diagnosticPayloads) {
                $0.diskWriteExceptionDiagnostics?.count ?? 0
            },
            to: &signals
        )
        append(
            kind: .appLaunchDiagnostic,
            positiveCount: saturatedCount(diagnosticPayloads) {
                $0.appLaunchDiagnostics?.count ?? 0
            },
            to: &signals
        )
        return signals
    }

    private func saturatedCount<Payload>(
        _ payloads: [Payload],
        count: (Payload) -> Int
    ) -> Int {
        payloads.reduce(into: 0) { total, payload in
            total = min(5, total + min(5, count(payload)))
        }
    }

    private func append(
        kind: AppleMetricKitSignalKind,
        positiveCount: Int,
        to signals: inout [AppleMetricKitHealthSignal]
    ) {
        if let signal = signal(kind: kind, positiveCount: positiveCount) {
            signals.append(signal)
        }
    }

    private func signal(
        kind: AppleMetricKitSignalKind,
        positiveCount: Int
    ) -> AppleMetricKitHealthSignal? {
        guard let countBand = AppleMetricKitCountBand(positiveCount: positiveCount) else {
            return nil
        }
        return AppleMetricKitHealthSignal(kind: kind, countBand: countBand)
    }
}

protocol AppleMetricKitHealthSignalHandling: Sendable {
    func handle(_ signals: [AppleMetricKitHealthSignal]) async
}

struct NoOpAppleMetricKitHealthSignalHandler: AppleMetricKitHealthSignalHandling {
    func handle(_ signals: [AppleMetricKitHealthSignal]) async {}
}

struct OSLogAppleMetricKitHealthSignalHandler: AppleMetricKitHealthSignalHandling {
    private let writer: any ApplePrivacySafeLogWriting

    init(writer: any ApplePrivacySafeLogWriting) {
        self.writer = writer
    }

    func handle(_ signals: [AppleMetricKitHealthSignal]) async {
        for signal in signals {
            await writer.write(.metricKit(signal))
        }
    }
}

/// MetricKit objects never cross a concurrency boundary. The callback reduces
/// them to Sendable coarse signals first, then schedules only those signals for
/// asynchronous handling so MetricKit's delivery queue is not held up.
final class AppleMetricKitSubscriberBridge: NSObject, MXMetricManagerSubscriber,
    @unchecked Sendable
{
    private let reducer: any AppleMetricKitPayloadReducing
    private let signalContinuation: AsyncStream<[AppleMetricKitHealthSignal]>.Continuation
    private let forwardingTask: Task<Void, Never>

    init(
        reducer: any AppleMetricKitPayloadReducing = PrivacySafeAppleMetricKitPayloadReducer(),
        handler: any AppleMetricKitHealthSignalHandling
    ) {
        self.reducer = reducer
        let (signalStream, signalContinuation) = AsyncStream.makeStream(
            of: [AppleMetricKitHealthSignal].self
        )
        self.signalContinuation = signalContinuation
        forwardingTask = Task(priority: .utility) {
            for await signals in signalStream {
                await handler.handle(signals)
            }
        }
        super.init()
    }

    deinit {
        // Finishing lets the single consumer drain values yielded before the
        // bridge's registration lifetime ended without cancelling them.
        signalContinuation.finish()
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        dispatch(reducer.reduce(metricPayloads: payloads))
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        dispatch(reducer.reduce(diagnosticPayloads: payloads))
    }

    private func dispatch(_ signals: [AppleMetricKitHealthSignal]) {
        guard !signals.isEmpty else { return }
        // Continuation yields are thread-safe and return immediately. A single
        // consumer preserves callback order and prevents concurrent handler
        // invocations without holding MetricKit's delivery queue.
        signalContinuation.yield(signals)
    }
}

protocol AppleMetricKitRegistering: Sendable {
    func register() throws
    func unregister() throws
}

struct NoOpAppleMetricKitRegistration: AppleMetricKitRegistering {
    func register() throws {}
    func unregister() throws {}
}

/// Owns the subscriber for the full registration lifetime. The lock keeps the
/// SDK-facing seam safe even if a future caller bypasses the actor below.
final class SystemAppleMetricKitRegistration: AppleMetricKitRegistering,
    @unchecked Sendable
{
    private let manager: MXMetricManager
    private let subscriber: AppleMetricKitSubscriberBridge
    private let lock = NSLock()
    private var isRegistered = false

    init(
        manager: MXMetricManager = .shared,
        subscriber: AppleMetricKitSubscriberBridge
    ) {
        self.manager = manager
        self.subscriber = subscriber
    }

    func register() {
        lock.withLock {
            guard !isRegistered else { return }
            manager.add(subscriber)
            isRegistered = true
        }
    }

    func unregister() {
        lock.withLock {
            guard isRegistered else { return }
            manager.remove(subscriber)
            isRegistered = false
        }
    }

    deinit {
        lock.withLock {
            guard isRegistered else { return }
            manager.remove(subscriber)
        }
    }
}

enum AppleMetricKitSubscriptionOperation: Equatable, Sendable {
    case register
    case unregister
}

enum AppleMetricKitSubscriptionResult: Equatable, Sendable {
    case registered
    case alreadyRegistered
    case unregistered
    case alreadyUnregistered
    case failed(AppleMetricKitSubscriptionOperation)
}

/// Serializes lifecycle transitions and changes state only after the SDK seam
/// succeeds, allowing a failed operation to be retried safely.
actor AppleMetricKitSubscriptionService {
    private let registration: any AppleMetricKitRegistering
    private var isRegistered = false

    init(registration: any AppleMetricKitRegistering) {
        self.registration = registration
    }

    func register() -> AppleMetricKitSubscriptionResult {
        guard !isRegistered else { return .alreadyRegistered }
        do {
            try registration.register()
            isRegistered = true
            return .registered
        } catch {
            return .failed(.register)
        }
    }

    func unregister() -> AppleMetricKitSubscriptionResult {
        guard isRegistered else { return .alreadyUnregistered }
        do {
            try registration.unregister()
            isRegistered = false
            return .unregistered
        } catch {
            return .failed(.unregister)
        }
    }

    func registrationState() -> Bool {
        isRegistered
    }
}

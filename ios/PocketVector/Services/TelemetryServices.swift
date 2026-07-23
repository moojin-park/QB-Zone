import Foundation

struct TelemetryEventID: Codable, Hashable, Sendable {
    fileprivate let rawValue: UUID

    init() {
        rawValue = UUID()
    }
}

struct ReplayCorrelationID: Codable, Hashable, Sendable {
    private let rawValue: UUID

    init() {
        rawValue = UUID()
    }
}

enum TelemetryEventName: String, Codable, Equatable, Sendable {
    case runStarted = "run_started"
    case runRestarted = "run_restarted"
    case runResultsShown = "run_results_shown"
    case replayStarted = "replay_started"
    case adOfferShown = "ad_offer_shown"
    case adOfferAccepted = "ad_offer_accepted"
    case adRewardVerified = "ad_reward_verified"
    case storeOpened = "store_opened"
    case purchaseOutcome = "purchase_outcome"
    case cosmeticUnlocked = "cosmetic_unlocked"
    case syncOutcome = "sync_outcome"
}

enum TelemetryScoreBand: String, Codable, Equatable, Sendable {
    case under5K
    case from5KTo14999
    case from15KTo24999
    case atLeast25K
}

enum TelemetryAccuracyBand: String, Codable, Equatable, Sendable {
    case under50
    case from50To69
    case from70To79
    case atLeast80
}

enum TelemetryAttemptBand: String, Codable, Equatable, Sendable {
    case under3
    case from3To9
    case from10To19
    case atLeast20
}

enum TelemetryCoinPackTier: String, Codable, Equatable, Sendable {
    case pocket
    case team
    case bundle
    case vault
}

enum TelemetryPurchaseOutcome: String, Codable, Equatable, Sendable {
    case succeeded
    case pending
    case cancelled
    case failed
}

enum TelemetryCosmeticKind: String, Codable, Equatable, Sendable {
    case team
    case jersey
    case football
}

enum TelemetrySyncOutcome: String, Codable, Equatable, Sendable {
    case succeeded
    case offline
    case conflict
    case retryableFailure
    case permanentFailure
}

enum TelemetryPayload: Codable, Equatable, Sendable {
    case runStarted
    case runRestarted
    case runResultsShown(
        correlationID: ReplayCorrelationID,
        scoreBand: TelemetryScoreBand,
        accuracyBand: TelemetryAccuracyBand,
        attemptBand: TelemetryAttemptBand
    )
    case replayStarted(correlationID: ReplayCorrelationID)
    case adOfferShown
    case adOfferAccepted
    case adRewardVerified
    case storeOpened
    case purchaseOutcome(pack: TelemetryCoinPackTier, outcome: TelemetryPurchaseOutcome)
    case cosmeticUnlocked(kind: TelemetryCosmeticKind)
    case syncOutcome(TelemetrySyncOutcome)

    var name: TelemetryEventName {
        switch self {
        case .runStarted: .runStarted
        case .runRestarted: .runRestarted
        case .runResultsShown: .runResultsShown
        case .replayStarted: .replayStarted
        case .adOfferShown: .adOfferShown
        case .adOfferAccepted: .adOfferAccepted
        case .adRewardVerified: .adRewardVerified
        case .storeOpened: .storeOpened
        case .purchaseOutcome: .purchaseOutcome
        case .cosmeticUnlocked: .cosmeticUnlocked
        case .syncOutcome: .syncOutcome
        }
    }
}

/// Unsafe candidates are accepted only by the privacy gate so tests and future
/// adapters can prove they are rejected before an event can exist.
enum TelemetryInput: Sendable {
    case allowlisted(TelemetryPayload)
    case exactBalance(Int64)
    case rawProfileID(UUID)
    case providerTransactionID(AdProviderTransactionID)
    case detailedRunHistory([RunID])
}

enum TelemetryPrivacyError: Error, Equatable, Sendable {
    case exactBalanceRejected
    case rawProfileIDRejected
    case providerTransactionIDRejected
    case detailedRunHistoryRejected
}

struct TelemetryEvent: Codable, Equatable, Sendable {
    let id: TelemetryEventID
    let occurredAt: Date
    let payload: TelemetryPayload

    var name: TelemetryEventName { payload.name }

    private init(
        id: TelemetryEventID,
        occurredAt: Date,
        payload: TelemetryPayload
    ) {
        self.id = id
        self.occurredAt = occurredAt
        self.payload = payload
    }

    static func make(
        occurredAt: Date,
        input: TelemetryInput
    ) throws -> TelemetryEvent {
        switch input {
        case let .allowlisted(payload):
            TelemetryEvent(
                id: TelemetryEventID(),
                occurredAt: occurredAt,
                payload: payload
            )
        case .exactBalance:
            throw TelemetryPrivacyError.exactBalanceRejected
        case .rawProfileID:
            throw TelemetryPrivacyError.rawProfileIDRejected
        case .providerTransactionID:
            throw TelemetryPrivacyError.providerTransactionIDRejected
        case .detailedRunHistory:
            throw TelemetryPrivacyError.detailedRunHistoryRejected
        }
    }
}

enum TelemetryEnqueueResult: Equatable, Sendable {
    case enqueued
    case duplicate
    case identifierCollision
    case ignored
}

struct TelemetryBatch: Codable, Equatable, Sendable {
    let events: [TelemetryEvent]
}

struct TelemetryRetentionPolicy: Codable, Equatable, Sendable {
    let tombstoneLifetime: TimeInterval
    let maximumTombstones: Int

    init(
        tombstoneLifetime: TimeInterval = 7 * 24 * 60 * 60,
        maximumTombstones: Int = 10_000
    ) {
        precondition(tombstoneLifetime >= 0, "Negative tombstone lifetime")
        precondition(maximumTombstones >= 0, "Negative tombstone limit")
        self.tombstoneLifetime = tombstoneLifetime
        self.maximumTombstones = maximumTombstones
    }
}

struct TelemetryEventQueue: Codable, Equatable, Sendable {
    private let retentionPolicy: TelemetryRetentionPolicy
    private var eventByID: [TelemetryEventID: TelemetryEvent] = [:]
    private var tombstoneExpiryByID: [TelemetryEventID: Date] = [:]

    init(retentionPolicy: TelemetryRetentionPolicy = TelemetryRetentionPolicy()) {
        self.retentionPolicy = retentionPolicy
    }

    mutating func enqueue(
        _ event: TelemetryEvent,
        at date: Date
    ) -> TelemetryEnqueueResult {
        pruneTombstones(at: date)
        if let existing = eventByID[event.id] {
            return existing == event ? .duplicate : .identifierCollision
        }
        if tombstoneExpiryByID[event.id] != nil {
            return .duplicate
        }
        eventByID[event.id] = event
        return .enqueued
    }

    func nextBatch(limit: Int = 50) -> TelemetryBatch? {
        guard limit > 0, !eventByID.isEmpty else { return nil }
        let events = eventByID.values
            .sorted {
                if $0.occurredAt == $1.occurredAt {
                    return $0.id.rawValue.uuidString < $1.id.rawValue.uuidString
                }
                return $0.occurredAt < $1.occurredAt
            }
            .prefix(limit)
        return TelemetryBatch(events: Array(events))
    }

    mutating func acknowledge(_ batch: TelemetryBatch, at date: Date) {
        pruneTombstones(at: date)
        for event in batch.events where eventByID[event.id] == event {
            eventByID.removeValue(forKey: event.id)
            tombstoneExpiryByID[event.id] = date.addingTimeInterval(
                retentionPolicy.tombstoneLifetime
            )
        }
        enforceTombstoneLimit()
        pruneTombstones(at: date)
    }

    mutating func pruneTombstones(at date: Date) {
        tombstoneExpiryByID = tombstoneExpiryByID.filter { $0.value > date }
    }

    var pendingCount: Int { eventByID.count }
    var tombstoneCount: Int { tombstoneExpiryByID.count }

    private mutating func enforceTombstoneLimit() {
        let overflow = tombstoneExpiryByID.count - retentionPolicy.maximumTombstones
        guard overflow > 0 else { return }

        let evictions = tombstoneExpiryByID
            .sorted {
                if $0.value == $1.value {
                    return $0.key.rawValue.uuidString < $1.key.rawValue.uuidString
                }
                return $0.value < $1.value
            }
            .prefix(overflow)
        for eviction in evictions {
            tombstoneExpiryByID.removeValue(forKey: eviction.key)
        }
    }
}

protocol TelemetryRecording: Sendable {
    @discardableResult
    func record(_ event: TelemetryEvent, at date: Date) async -> TelemetryEnqueueResult
}

actor InMemoryTelemetryRecorder: TelemetryRecording {
    private var queue: TelemetryEventQueue

    init(retentionPolicy: TelemetryRetentionPolicy = TelemetryRetentionPolicy()) {
        queue = TelemetryEventQueue(retentionPolicy: retentionPolicy)
    }

    @discardableResult
    func record(_ event: TelemetryEvent, at date: Date) -> TelemetryEnqueueResult {
        queue.enqueue(event, at: date)
    }

    func nextBatch(limit: Int = 50) -> TelemetryBatch? {
        queue.nextBatch(limit: limit)
    }

    func acknowledge(_ batch: TelemetryBatch, at date: Date) {
        queue.acknowledge(batch, at: date)
    }

    func pendingCount() -> Int { queue.pendingCount }
    func tombstoneCount() -> Int { queue.tombstoneCount }
}

struct NoOpTelemetryRecorder: TelemetryRecording {
    func record(_ event: TelemetryEvent, at date: Date) async -> TelemetryEnqueueResult {
        .ignored
    }
}

import Foundation

/// Carries complete, versioned profile projections to the presentation layer.
///
/// Keeping only the newest buffered value is safe because every element is a
/// full state snapshot. Transactional values such as ledger entries, StoreKit
/// transactions, and CloudKit deltas must never use this channel.
@MainActor
final class ProductionAuthoritativeStateChannel {
    private(set) var subscriberCount = 0

    private var continuations: [UUID: AsyncStream<AuthoritativeAppStateSnapshot>.Continuation]
    private var latestSnapshot: AuthoritativeAppStateSnapshot?
    private var isFinished = false

    init() {
        continuations = [:]
    }

    /// Creates an independent, restartable subscription. A new subscriber
    /// immediately receives the latest complete snapshot, if one exists.
    func makeStream() -> AsyncStream<AuthoritativeAppStateSnapshot> {
        let pair = AsyncStream<AuthoritativeAppStateSnapshot>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        guard !isFinished else {
            pair.continuation.finish()
            return pair.stream
        }

        let subscriberID = UUID()
        pair.continuation.onTermination = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.removeSubscriber(subscriberID)
            }
        }
        continuations[subscriberID] = pair.continuation
        subscriberCount = continuations.count
        if let latestSnapshot {
            pair.continuation.yield(latestSnapshot)
        }
        return pair.stream
    }

    func publish(_ snapshot: AuthoritativeAppStateSnapshot) {
        guard !isFinished else { return }
        latestSnapshot = snapshot
        for continuation in continuations.values {
            continuation.yield(snapshot)
        }
    }

    func finish() {
        guard !isFinished else { return }
        isFinished = true
        latestSnapshot = nil
        let activeContinuations = Array(continuations.values)
        continuations.removeAll()
        subscriberCount = 0
        for continuation in activeContinuations {
            continuation.finish()
        }
    }

    private func removeSubscriber(_ subscriberID: UUID) {
        continuations.removeValue(forKey: subscriberID)
        subscriberCount = continuations.count
    }
}

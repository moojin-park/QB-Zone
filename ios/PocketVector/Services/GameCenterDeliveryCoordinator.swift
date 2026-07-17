import Foundation

protocol GameCenterSubmissionRepository: Actor {
    func prepareGameCenterSubmission(
        for playerID: GameCenterPlayerID,
        session: ProfileSessionToken
    ) async throws -> LocalGameCenterPreparedSubmissionV1?

    func acknowledgeGameCenterSubmission(
        _ submission: LocalGameCenterPreparedSubmissionV1,
        successfulResult: GameCenterSuccessfulSubmissionV1,
        session: ProfileSessionToken,
        at date: Date
    ) async throws -> LocalPlayerProfileSnapshot
}

extension LocalPlayerProfileRepository: GameCenterSubmissionRepository {}

/// A process-only success brand. Only this file can mint it, and the delivery
/// coordinator does so only after `submit` returns and the same Game Center
/// player is revalidated. Repository acknowledgement additionally verifies the
/// exact opaque preparation capability carried here.
struct GameCenterSuccessfulSubmissionV1: Equatable, Sendable {
    private let submission: LocalGameCenterPreparedSubmissionV1

    fileprivate init(submission: LocalGameCenterPreparedSubmissionV1) {
        self.submission = submission
    }

    func confirms(_ submission: LocalGameCenterPreparedSubmissionV1) -> Bool {
        self.submission == submission
    }
}

enum GameCenterDeliveryRetentionReason: Equatable, Sendable {
    case cancelled
    case playerChanged
    case submissionFailed
    case repositoryRejected
}

enum GameCenterDeliveryOutcome: Equatable, Sendable {
    case delivered(GameCenterSubmissionBatch)
    case noPendingSubmission(GameCenterPlayerID)
    case unavailable(GameCenterAuthenticationState)
    case retained(GameCenterDeliveryRetentionReason)
    case alreadyInProgress
}

enum GameCenterDeliveryCoordinatorError: Error, Equatable, Sendable {
    case unavailable(GameCenterUnavailableReason)
    case authenticationDidNotComplete
    case playerChanged
}

/// Dormant, dependency-injected orchestration for one exact profile session.
/// It starts no task and owns no retry timer: the future retained app runtime
/// must explicitly call authentication, foreground, delivery, or presentation
/// entry points. Actor state makes delivery single-flight across suspension.
actor GameCenterDeliveryCoordinator {
    private let repository: any GameCenterSubmissionRepository
    private let service: any GameCenterServicing
    private let session: ProfileSessionToken
    private let now: @Sendable () -> Date
    private var deliveryIsInProgress = false

    private init(
        repository: any GameCenterSubmissionRepository,
        service: any GameCenterServicing,
        session: ProfileSessionToken,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.repository = repository
        self.service = service
        self.session = session
        self.now = now
    }

    #if DEBUG
    /// Explicit test-only injection surface. Release builds intentionally have
    /// no construction path until a trusted in-file GameKit factory is added.
    static func makeForTesting(
        repository: any GameCenterSubmissionRepository,
        service: any GameCenterServicing,
        session: ProfileSessionToken,
        now: @escaping @Sendable () -> Date = Date.init
    ) -> GameCenterDeliveryCoordinator {
        GameCenterDeliveryCoordinator(
            repository: repository,
            service: service,
            session: session,
            now: now
        )
    }
    #endif

    func authenticate() async -> GameCenterAuthenticationState {
        await service.authenticate()
    }

    /// A foreground trigger may ask GameKit to authenticate, but never blocks
    /// profile bootstrap or starts a retry loop of its own.
    func foreground() async -> GameCenterDeliveryOutcome {
        await performDelivery(authenticateIfNeeded: true)
    }

    /// An explicit delivery trigger uses only the currently authenticated
    /// player. Callers can choose `foreground()` when authentication UI is
    /// appropriate.
    func deliverPending() async -> GameCenterDeliveryOutcome {
        await performDelivery(authenticateIfNeeded: false)
    }

    func requestPresentation(
        _ destination: GameCenterPresentationDestination
    ) async throws {
        try Task.checkCancellation()
        var state = await service.authenticationState()
        if state.playerID == nil {
            state = await service.authenticate()
        }
        try Task.checkCancellation()
        guard let expectedPlayerID = state.playerID else {
            if case let .unavailable(reason) = state {
                throw GameCenterDeliveryCoordinatorError.unavailable(reason)
            }
            throw GameCenterDeliveryCoordinatorError.authenticationDidNotComplete
        }
        let revalidated = await service.authenticationState()
        guard revalidated.playerID == expectedPlayerID else {
            throw GameCenterDeliveryCoordinatorError.playerChanged
        }
        try Task.checkCancellation()
        try await service.requestPresentation(destination)
    }

    private func performDelivery(
        authenticateIfNeeded: Bool
    ) async -> GameCenterDeliveryOutcome {
        guard !deliveryIsInProgress else { return .alreadyInProgress }
        deliveryIsInProgress = true
        defer { deliveryIsInProgress = false }

        guard !Task.isCancelled else { return .retained(.cancelled) }
        var state = await service.authenticationState()
        if authenticateIfNeeded, state.playerID == nil {
            state = await service.authenticate()
        }
        guard !Task.isCancelled else { return .retained(.cancelled) }
        guard let playerID = state.playerID else { return .unavailable(state) }

        let submission: LocalGameCenterPreparedSubmissionV1
        do {
            guard let prepared = try await repository.prepareGameCenterSubmission(
                for: playerID,
                session: session
            ) else {
                return .noPendingSubmission(playerID)
            }
            submission = prepared
        } catch {
            return .retained(.repositoryRejected)
        }
        guard !Task.isCancelled else { return .retained(.cancelled) }

        let beforeSubmit = await service.authenticationState()
        guard beforeSubmit.playerID == playerID else {
            return .retained(.playerChanged)
        }
        do {
            try await service.submit(submission.batch)
        } catch is CancellationError {
            return .retained(.cancelled)
        } catch {
            return .retained(.submissionFailed)
        }
        // A cancellation after an SDK success but before local acknowledgement
        // is ambiguous. Retaining the maxima makes the next explicit trigger
        // safely resubmit Game Center's monotonic score/progress values.
        guard !Task.isCancelled else { return .retained(.cancelled) }

        let afterSubmit = await service.authenticationState()
        guard afterSubmit.playerID == playerID else {
            return .retained(.playerChanged)
        }
        guard !Task.isCancelled else { return .retained(.cancelled) }
        let successfulResult = GameCenterSuccessfulSubmissionV1(
            submission: submission
        )
        guard !Task.isCancelled else { return .retained(.cancelled) }
        do {
            _ = try await repository.acknowledgeGameCenterSubmission(
                submission,
                successfulResult: successfulResult,
                session: session,
                at: now()
            )
        } catch is CancellationError {
            return .retained(.cancelled)
        } catch {
            return .retained(.repositoryRejected)
        }
        return .delivered(submission.batch)
    }
}

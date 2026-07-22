import Foundation
@preconcurrency import GameKit
import UIKit

enum GameKitGameCenterConfigurationError: Error, Equatable, Sendable {
    case emptyLeaderboardIdentifier
    case invalidAchievementSet
    case emptyAchievementIdentifier
    case duplicateAchievementIdentifier
    case retiredAchievementIdentifier
    case permanentAchievementIdentifierMismatch
    case unapprovedLeaderboardDestination
    case unsupportedAchievement
}

/// App Store Connect identifiers are injected at composition time. This type
/// accepts exactly the launch achievement catalog and one leaderboard so an
/// arbitrary provider identifier cannot enter a production request.
struct GameKitGameCenterConfiguration: Equatable, Sendable {
    let leaderboardIdentifier: String
    let achievementIdentifiers: [AchievementID: String]

    init(
        leaderboardIdentifier: String,
        achievementIdentifiers: [AchievementID: String]
    ) throws {
        let normalizedLeaderboard = leaderboardIdentifier.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !normalizedLeaderboard.isEmpty else {
            throw GameKitGameCenterConfigurationError.emptyLeaderboardIdentifier
        }

        let launchAchievementIDs = Set(AchievementCatalog.launch.map(\.id))
        guard achievementIdentifiers.count == launchAchievementIDs.count,
              Set(achievementIdentifiers.keys) == launchAchievementIDs else {
            throw GameKitGameCenterConfigurationError.invalidAchievementSet
        }

        var normalizedAchievements: [AchievementID: String] = [:]
        let millenniaID = LaunchAchievementID.millenniaOfConnections
        let retiredCenturyID = AchievementCatalogTransitionV1ToV2
            .retiredCenturyOfConnections
        for achievementID in launchAchievementIDs {
            guard let identifier = achievementIdentifiers[achievementID] else {
                throw GameKitGameCenterConfigurationError.invalidAchievementSet
            }
            let normalized = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else {
                throw GameKitGameCenterConfigurationError.emptyAchievementIdentifier
            }
            guard normalized != retiredCenturyID.rawValue else {
                throw GameKitGameCenterConfigurationError
                    .retiredAchievementIdentifier
            }
            if achievementID == millenniaID,
               normalized != millenniaID.rawValue {
                throw GameKitGameCenterConfigurationError
                    .permanentAchievementIdentifierMismatch
            }
            normalizedAchievements[achievementID] = normalized
        }
        guard Set(normalizedAchievements.values).count == launchAchievementIDs.count else {
            throw GameKitGameCenterConfigurationError.duplicateAchievementIdentifier
        }

        self.leaderboardIdentifier = normalizedLeaderboard
        self.achievementIdentifiers = normalizedAchievements
    }

    func presentationRoute(
        for destination: GameCenterPresentationDestination
    ) throws -> GameKitPresentationRoute {
        switch destination {
        case .dashboard:
            return .dashboard
        case let .leaderboard(identifier):
            guard identifier == leaderboardIdentifier else {
                throw GameKitGameCenterConfigurationError.unapprovedLeaderboardDestination
            }
            return .leaderboard(identifier: leaderboardIdentifier)
        case .achievements:
            return .achievements
        }
    }

    func providerIdentifier(for achievementID: AchievementID) throws -> String {
        guard let identifier = achievementIdentifiers[achievementID] else {
            throw GameKitGameCenterConfigurationError.unsupportedAchievement
        }
        return identifier
    }
}

enum GameKitPresentationRoute: Equatable, Sendable {
    case dashboard
    case leaderboard(identifier: String)
    case achievements
}

enum GameKitAuthenticationPresentationDisposition: Equatable, Sendable {
    /// The presenter accepted the controller. GameKit's next authentication
    /// callback, rather than UIKit presentation timing, is authoritative.
    case presented
    case declined
}

/// App composition owns the actual UIKit presentation and dismissal lifecycle.
/// The protocol is main-actor isolated so UIKit values never cross an
/// unstructured concurrency boundary.
@MainActor
protocol GameKitPresentationHandoff: AnyObject, Sendable {
    func presentGameKitAuthentication(
        _ viewController: UIViewController
    ) async -> GameKitAuthenticationPresentationDisposition

    func presentGameKit(
        _ viewController: GKGameCenterViewController
    ) async throws
}

struct GameKitPlayerSnapshot: Equatable, Sendable {
    let isAuthenticated: Bool
    let gamePlayerID: String?

    var playerID: GameCenterPlayerID? {
        guard isAuthenticated,
              let gamePlayerID,
              !gamePlayerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return GameCenterPlayerID(gamePlayerID)
    }
}

struct GameKitErrorDescriptor: Error, Equatable, Sendable {
    let domain: String
    let code: Int

    init(domain: String, code: Int) {
        self.domain = domain
        self.code = code
    }

    init(_ error: any Error) {
        let nsError = error as NSError
        self.init(domain: nsError.domain, code: nsError.code)
    }
}

enum GameKitPlatformAuthenticationOutcome: Equatable, Sendable {
    case authenticated(GameCenterPlayerID)
    case unavailable(GameCenterUnavailableReason)
}

enum GameKitAuthenticationClassifier {
    static func resolve(
        snapshot: GameKitPlayerSnapshot,
        error: GameKitErrorDescriptor?,
        didPresentAuthenticationUI: Bool
    ) -> GameKitPlatformAuthenticationOutcome {
        if let playerID = snapshot.playerID {
            return .authenticated(playerID)
        }

        guard let error else {
            return .unavailable(didPresentAuthenticationUI ? .declined : .signedOut)
        }

        if isNetworkError(error) {
            return .unavailable(.networkUnavailable)
        }
        guard error.domain == GKErrorDomain else {
            return .unavailable(.serviceUnavailable)
        }

        switch error.code {
        case GKError.Code.cancelled.rawValue,
             GKError.Code.userDenied.rawValue:
            return .unavailable(.declined)
        case GKError.Code.parentalControlsBlocked.rawValue,
             GKError.Code.underage.rawValue,
             GKError.Code.restrictedToAutomatch.rawValue,
             GKError.Code.notAuthorized.rawValue,
             36: // GKErrorLockdownMode (introduced in iOS 17.2).
            return .unavailable(.restricted)
        case GKError.Code.invalidCredentials.rawValue,
             GKError.Code.notAuthenticated.rawValue:
            return .unavailable(.signedOut)
        default:
            return .unavailable(.serviceUnavailable)
        }
    }

    static func isNetworkError(_ error: GameKitErrorDescriptor) -> Bool {
        if error.domain == GKErrorDomain {
            return [
                GKError.Code.communicationsFailure.rawValue,
                GKError.Code.unexpectedConnection.rawValue,
                GKError.Code.connectionTimeout.rawValue,
            ].contains(error.code)
        }
        guard error.domain == NSURLErrorDomain else { return false }
        return [
            URLError.Code.timedOut.rawValue,
            URLError.Code.cannotFindHost.rawValue,
            URLError.Code.cannotConnectToHost.rawValue,
            URLError.Code.networkConnectionLost.rawValue,
            URLError.Code.dnsLookupFailed.rawValue,
            URLError.Code.resourceUnavailable.rawValue,
            URLError.Code.notConnectedToInternet.rawValue,
            URLError.Code.internationalRoamingOff.rawValue,
            URLError.Code.callIsActive.rawValue,
            URLError.Code.dataNotAllowed.rawValue,
        ].contains(error.code)
    }
}

enum GameKitScoreConversion {
    /// GameKit's current score API consumes `NSInteger` (`Int` in Swift).
    /// Converting from a durable Int64 through `Int(clamping:)` prevents a
    /// future wider persistence type from overflowing that platform boundary.
    static func platformScore(from durableScore: Int64) -> Int {
        guard durableScore > 0 else { return 0 }
        return Int(clamping: durableScore)
    }

    static func platformScore(fromDomainScore score: Int) -> Int {
        platformScore(from: Int64(clamping: score))
    }
}

struct GameKitAchievementReport: Equatable, Sendable {
    let achievementID: AchievementID
    let providerIdentifier: String
    let percentComplete: Int
}

struct GameKitPlatformSubmission: Equatable, Sendable {
    let expectedPlayerID: GameCenterPlayerID
    let leaderboardIdentifier: String
    let highScore: Int?
    let achievements: [GameKitAchievementReport]

    var isEmpty: Bool {
        highScore == nil && achievements.isEmpty
    }
}

enum GameKitSubmissionBuilder {
    static func build(
        batch: GameCenterSubmissionBatch,
        configuration: GameKitGameCenterConfiguration
    ) throws -> GameKitPlatformSubmission {
        var coalescedAchievements: [AchievementID: Int] = [:]
        for achievement in batch.achievements {
            _ = try configuration.providerIdentifier(for: achievement.id)
            coalescedAchievements[achievement.id] = max(
                coalescedAchievements[achievement.id, default: 0],
                min(100, max(0, achievement.percentComplete))
            )
        }

        let reports = try coalescedAchievements
            .map { achievementID, percentComplete in
                GameKitAchievementReport(
                    achievementID: achievementID,
                    providerIdentifier: try configuration.providerIdentifier(
                        for: achievementID
                    ),
                    percentComplete: percentComplete
                )
            }
            .sorted { $0.achievementID.rawValue < $1.achievementID.rawValue }

        return GameKitPlatformSubmission(
            expectedPlayerID: batch.playerID,
            leaderboardIdentifier: configuration.leaderboardIdentifier,
            highScore: batch.highScore.map(GameKitScoreConversion.platformScore),
            achievements: reports
        )
    }
}

enum GameKitPlatformFailure: Error, Equatable, Sendable {
    case notAuthenticated
    case playerMismatch
    case presentationUnavailable
    case platform(GameKitErrorDescriptor)
}

enum GameKitServiceErrorMapper {
    static func serviceError(for error: any Error) -> GameCenterServiceError {
        if let failure = error as? GameKitPlatformFailure {
            switch failure {
            case .notAuthenticated:
                return .notAuthenticated
            case .playerMismatch:
                return .playerMismatch
            case .presentationUnavailable:
                return .transportUnavailable
            case let .platform(descriptor):
                return serviceError(for: descriptor)
            }
        }
        return serviceError(for: GameKitErrorDescriptor(error))
    }

    private static func serviceError(
        for descriptor: GameKitErrorDescriptor
    ) -> GameCenterServiceError {
        if descriptor.domain == GKErrorDomain,
           [
               GKError.Code.invalidCredentials.rawValue,
               GKError.Code.notAuthenticated.rawValue,
           ].contains(descriptor.code) {
            return .notAuthenticated
        }
        return .transportUnavailable
    }
}

protocol GameKitPlatformClient: Sendable {
    func currentPlayerSnapshot() async -> GameKitPlayerSnapshot
    func authenticate() async -> GameKitPlatformAuthenticationOutcome
    func submit(_ submission: GameKitPlatformSubmission) async throws
    func present(
        _ route: GameKitPresentationRoute,
        expectedPlayerID: GameCenterPlayerID
    ) async throws
}

/// The production GameKit boundary. It intentionally reads only
/// `gamePlayerID`; display names and aliases never enter app state or errors.
@MainActor
final class LiveGameKitPlatformClient: GameKitPlatformClient {
    private let localPlayer: GKLocalPlayer
    private let presenter: (any GameKitPresentationHandoff)?
    private var authenticationContinuation:
        CheckedContinuation<GameKitPlatformAuthenticationOutcome, Never>?
    private var isPresentingAuthenticationUI = false
    private var didPresentAuthenticationUI = false

    init(
        localPlayer: GKLocalPlayer = .local,
        presenter: (any GameKitPresentationHandoff)?
    ) {
        self.localPlayer = localPlayer
        self.presenter = presenter
    }

    func currentPlayerSnapshot() async -> GameKitPlayerSnapshot {
        snapshot()
    }

    func authenticate() async -> GameKitPlatformAuthenticationOutcome {
        let current = snapshot()
        if let playerID = current.playerID {
            return .authenticated(playerID)
        }
        guard authenticationContinuation == nil else {
            return .unavailable(.serviceUnavailable)
        }

        return await withCheckedContinuation { continuation in
            authenticationContinuation = continuation
            didPresentAuthenticationUI = false
            isPresentingAuthenticationUI = false
            localPlayer.authenticateHandler = { [weak self] viewController, error in
                DispatchQueue.main.async {
                    self?.receiveAuthenticationCallback(
                        viewController: viewController,
                        error: error
                    )
                }
            }
        }
    }

    func submit(_ submission: GameKitPlatformSubmission) async throws {
        try validateCurrentPlayer(submission.expectedPlayerID)

        if let highScore = submission.highScore {
            do {
                try await submitScore(
                    highScore,
                    leaderboardIdentifier: submission.leaderboardIdentifier
                )
            } catch {
                throw GameKitPlatformFailure.platform(GameKitErrorDescriptor(error))
            }
        }

        guard !submission.achievements.isEmpty else { return }
        try validateCurrentPlayer(submission.expectedPlayerID)
        let achievements = submission.achievements.map { report in
            let achievement = GKAchievement(identifier: report.providerIdentifier)
            achievement.percentComplete = Double(report.percentComplete)
            achievement.showsCompletionBanner = report.percentComplete == 100
            return achievement
        }
        do {
            try await report(achievements)
        } catch {
            throw GameKitPlatformFailure.platform(GameKitErrorDescriptor(error))
        }
    }

    func present(
        _ route: GameKitPresentationRoute,
        expectedPlayerID: GameCenterPlayerID
    ) async throws {
        try validateCurrentPlayer(expectedPlayerID)
        guard let presenter else {
            throw GameKitPlatformFailure.presentationUnavailable
        }

        let viewController: GKGameCenterViewController
        switch route {
        case .dashboard:
            viewController = GKGameCenterViewController(state: .dashboard)
        case let .leaderboard(identifier):
            viewController = GKGameCenterViewController(
                leaderboardID: identifier,
                playerScope: .global,
                timeScope: .allTime
            )
        case .achievements:
            viewController = GKGameCenterViewController(state: .achievements)
        }

        do {
            try await presenter.presentGameKit(viewController)
        } catch {
            throw GameKitPlatformFailure.platform(GameKitErrorDescriptor(error))
        }
    }

    private func snapshot() -> GameKitPlayerSnapshot {
        GameKitPlayerSnapshot(
            isAuthenticated: localPlayer.isAuthenticated,
            gamePlayerID: localPlayer.isAuthenticated ? localPlayer.gamePlayerID : nil
        )
    }

    private func validateCurrentPlayer(_ expectedPlayerID: GameCenterPlayerID) throws {
        guard localPlayer.isAuthenticated else {
            throw GameKitPlatformFailure.notAuthenticated
        }
        guard localPlayer.gamePlayerID == expectedPlayerID.rawValue else {
            throw GameKitPlatformFailure.playerMismatch
        }
    }

    private func receiveAuthenticationCallback(
        viewController: UIViewController?,
        error: (any Error)?
    ) {
        guard authenticationContinuation != nil else { return }

        let currentSnapshot = snapshot()
        if currentSnapshot.playerID != nil || error != nil {
            finishAuthentication(
                GameKitAuthenticationClassifier.resolve(
                    snapshot: currentSnapshot,
                    error: error.map(GameKitErrorDescriptor.init),
                    didPresentAuthenticationUI: didPresentAuthenticationUI
                )
            )
            return
        }

        guard let viewController else {
            finishAuthentication(
                GameKitAuthenticationClassifier.resolve(
                    snapshot: currentSnapshot,
                    error: nil,
                    didPresentAuthenticationUI: didPresentAuthenticationUI
                )
            )
            return
        }
        guard !isPresentingAuthenticationUI else { return }
        guard let presenter else {
            finishAuthentication(.unavailable(.signedOut))
            return
        }

        isPresentingAuthenticationUI = true
        didPresentAuthenticationUI = true
        Task { @MainActor [weak self] in
            let disposition = await presenter.presentGameKitAuthentication(viewController)
            guard let self, self.authenticationContinuation != nil else { return }
            switch disposition {
            case .declined:
                self.finishAuthentication(.unavailable(.declined))
            case .presented:
                // Await GameKit's terminal callback. Presentation completion
                // alone does not prove that authentication succeeded.
                break
            }
        }
    }

    private func finishAuthentication(_ outcome: GameKitPlatformAuthenticationOutcome) {
        guard let continuation = authenticationContinuation else { return }
        authenticationContinuation = nil
        isPresentingAuthenticationUI = false
        continuation.resume(returning: outcome)
    }

    private func submitScore(
        _ score: Int,
        leaderboardIdentifier: String
    ) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, any Error>) in
            GKLeaderboard.submitScore(
                score,
                context: 0,
                player: localPlayer,
                leaderboardIDs: [leaderboardIdentifier]
            ) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func report(_ achievements: [GKAchievement]) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, any Error>) in
            GKAchievement.report(achievements) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}

actor GameKitGameCenterService: GameCenterServicing {
    private let configuration: GameKitGameCenterConfiguration
    private let platformClient: any GameKitPlatformClient
    private var state: GameCenterAuthenticationState = .notRequested

    init(
        configuration: GameKitGameCenterConfiguration,
        platformClient: any GameKitPlatformClient
    ) {
        self.configuration = configuration
        self.platformClient = platformClient
    }

    @MainActor
    init(
        configuration: GameKitGameCenterConfiguration,
        presenter: (any GameKitPresentationHandoff)?
    ) {
        self.configuration = configuration
        self.platformClient = LiveGameKitPlatformClient(presenter: presenter)
    }

    func authenticationState() async -> GameCenterAuthenticationState {
        if case .authenticating = state {
            return state
        }

        let snapshot = await platformClient.currentPlayerSnapshot()
        if let playerID = snapshot.playerID {
            state = .authenticated(playerID)
        } else if state.playerID != nil {
            state = .unavailable(.signedOut)
        }
        return state
    }

    func authenticate() async -> GameCenterAuthenticationState {
        if case .authenticating = state {
            return state
        }
        state = .authenticating

        let outcome = await platformClient.authenticate()
        switch outcome {
        case let .authenticated(playerID):
            state = .authenticated(playerID)
        case let .unavailable(reason):
            state = .unavailable(reason)
        }
        return state
    }

    func submit(_ batch: GameCenterSubmissionBatch) async throws {
        let currentPlayerID = try await validatedPlayerID(for: batch.playerID)
        guard currentPlayerID == batch.playerID else {
            throw GameCenterServiceError.playerMismatch
        }

        let submission: GameKitPlatformSubmission
        do {
            submission = try GameKitSubmissionBuilder.build(
                batch: batch,
                configuration: configuration
            )
        } catch {
            throw GameCenterServiceError.transportUnavailable
        }
        guard !submission.isEmpty else { return }

        do {
            try await platformClient.submit(submission)
        } catch {
            let serviceError = GameKitServiceErrorMapper.serviceError(for: error)
            await refreshState(after: serviceError)
            throw serviceError
        }
    }

    func requestPresentation(
        _ destination: GameCenterPresentationDestination
    ) async throws {
        let currentPlayerID = try await validatedPlayerID()
        let route: GameKitPresentationRoute
        do {
            route = try configuration.presentationRoute(for: destination)
        } catch {
            throw GameCenterServiceError.transportUnavailable
        }

        do {
            try await platformClient.present(
                route,
                expectedPlayerID: currentPlayerID
            )
        } catch {
            let serviceError = GameKitServiceErrorMapper.serviceError(for: error)
            await refreshState(after: serviceError)
            throw serviceError
        }
    }

    private func validatedPlayerID(
        for expectedPlayerID: GameCenterPlayerID? = nil
    ) async throws -> GameCenterPlayerID {
        let snapshot = await platformClient.currentPlayerSnapshot()
        guard let currentPlayerID = snapshot.playerID else {
            state = .unavailable(.signedOut)
            throw GameCenterServiceError.notAuthenticated
        }
        state = .authenticated(currentPlayerID)
        if let expectedPlayerID, expectedPlayerID != currentPlayerID {
            throw GameCenterServiceError.playerMismatch
        }
        return currentPlayerID
    }

    private func refreshState(after error: GameCenterServiceError) async {
        switch error {
        case .notAuthenticated:
            state = .unavailable(.signedOut)
        case .playerMismatch:
            let snapshot = await platformClient.currentPlayerSnapshot()
            if let playerID = snapshot.playerID {
                state = .authenticated(playerID)
            } else {
                state = .unavailable(.signedOut)
            }
        case .transportUnavailable:
            break
        }
    }
}

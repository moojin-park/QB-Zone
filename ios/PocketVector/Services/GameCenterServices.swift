import Foundation

struct GameCenterPlayerID: RawRepresentable, Codable, Hashable, Sendable, CustomStringConvertible {
    let rawValue: String

    init(rawValue: String) {
        precondition(!rawValue.isEmpty, "GameCenterPlayerID cannot be empty")
        self.rawValue = rawValue
    }

    init(_ rawValue: String) {
        self.init(rawValue: rawValue)
    }

    /// Persisted input must reach the profile validator without invoking the
    /// stricter direct-construction precondition. Preserve the provider text
    /// byte-for-byte; validation, not decoding, decides whether it is usable.
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var description: String { rawValue }
}

enum GameCenterPlayerIDRuleV1 {
    static let maximumUTF8ByteCount = 256

    static func isValid(_ value: GameCenterPlayerID) -> Bool {
        let bytes = value.rawValue.utf8
        return !bytes.isEmpty
            && bytes.count <= maximumUTF8ByteCount
            && !bytes.contains(where: { $0 < 0x20 || $0 == 0x7f })
    }
}

enum GameCenterUnavailableReason: String, Codable, Equatable, Sendable {
    case signedOut
    case declined
    case restricted
    case networkUnavailable
    case serviceUnavailable
}

enum GameCenterAuthenticationState: Codable, Equatable, Sendable {
    case notRequested
    case authenticating
    case authenticated(GameCenterPlayerID)
    case unavailable(GameCenterUnavailableReason)

    var playerID: GameCenterPlayerID? {
        guard case let .authenticated(playerID) = self else { return nil }
        return playerID
    }
}

enum GameCenterPresentationDestination: Codable, Equatable, Sendable {
    case dashboard
    case leaderboard(identifier: String)
    case achievements
}

struct GameCenterAchievementSubmission: Codable, Equatable, Sendable {
    let id: AchievementID
    let percentComplete: Int

    init(id: AchievementID, percentComplete: Int) {
        self.id = id
        self.percentComplete = min(100, max(0, percentComplete))
    }
}

struct GameCenterSubmissionBatch: Codable, Equatable, Sendable {
    let playerID: GameCenterPlayerID
    let highScore: Int?
    let achievements: [GameCenterAchievementSubmission]

    var isEmpty: Bool {
        highScore == nil && achievements.isEmpty
    }
}

protocol GameCenterServicing: Sendable {
    func authenticationState() async -> GameCenterAuthenticationState
    func authenticate() async -> GameCenterAuthenticationState
    func submit(_ batch: GameCenterSubmissionBatch) async throws
    func requestPresentation(_ destination: GameCenterPresentationDestination) async throws
}

typealias AccountScopedGameCenterQueue = PlayerScopedGameCenterQueueV1

extension PlayerScopedGameCenterQueueV1 {
    func batch(for playerID: GameCenterPlayerID) -> GameCenterSubmissionBatch? {
        guard let pending = pendingByPlayerID[playerID], !pending.isEmpty else {
            return nil
        }

        let achievements = pending.pendingAchievementPercents
            .filter { $0.value > 0 }
            .map { GameCenterAchievementSubmission(id: $0.key, percentComplete: $0.value) }
            .sorted { $0.id.rawValue < $1.id.rawValue }

        return GameCenterSubmissionBatch(
            playerID: playerID,
            highScore: pending.pendingHighScore > 0 ? pending.pendingHighScore : nil,
            achievements: achievements
        )
    }

    func pendingPlayerIDs() -> Set<GameCenterPlayerID> {
        Set(pendingByPlayerID.keys)
    }
}

#if DEBUG
/// Test-only service double. Release builds must use a future trusted GameKit
/// factory in the delivery coordinator's file rather than an in-memory success
/// provider that could clear durable submission authority.
actor InMemoryGameCenterService: GameCenterServicing {
    private var state: GameCenterAuthenticationState
    private var authenticationResult: GameCenterAuthenticationState
    private var submissionFailure: GameCenterServiceError?
    private var presentationFailure: GameCenterServiceError?
    private(set) var submittedBatches: [GameCenterSubmissionBatch] = []
    private(set) var presentationRequests: [GameCenterPresentationDestination] = []

    init(
        state: GameCenterAuthenticationState = .notRequested,
        authenticationResult: GameCenterAuthenticationState = .unavailable(.signedOut)
    ) {
        self.state = state
        self.authenticationResult = authenticationResult
    }

    func authenticationState() -> GameCenterAuthenticationState {
        state
    }

    func authenticate() -> GameCenterAuthenticationState {
        state = authenticationResult
        return state
    }

    func submit(_ batch: GameCenterSubmissionBatch) throws {
        guard state.playerID == batch.playerID else {
            throw GameCenterServiceError.playerMismatch
        }
        if let submissionFailure {
            throw submissionFailure
        }
        submittedBatches.append(batch)
    }

    func requestPresentation(_ destination: GameCenterPresentationDestination) throws {
        guard state.playerID != nil else {
            throw GameCenterServiceError.notAuthenticated
        }
        if let presentationFailure {
            throw presentationFailure
        }
        presentationRequests.append(destination)
    }

    func setAuthenticationResult(_ result: GameCenterAuthenticationState) {
        authenticationResult = result
    }

    func setState(_ newState: GameCenterAuthenticationState) {
        state = newState
    }

    func setSubmissionFailure(_ failure: GameCenterServiceError?) {
        submissionFailure = failure
    }

    func setPresentationFailure(_ failure: GameCenterServiceError?) {
        presentationFailure = failure
    }
}
#endif

enum GameCenterServiceError: Error, Equatable, Sendable {
    case notAuthenticated
    case playerMismatch
    case transportUnavailable
}

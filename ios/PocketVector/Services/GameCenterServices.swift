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

    var description: String { rawValue }
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

struct AccountScopedGameCenterQueue: Codable, Equatable, Sendable {
    private struct Pending: Codable, Equatable, Sendable {
        var highScore: Int?
        var achievementPercents: [AchievementID: Int]

        var isEmpty: Bool {
            highScore == nil && achievementPercents.isEmpty
        }
    }

    private var pendingByPlayer: [GameCenterPlayerID: Pending] = [:]

    mutating func enqueueHighScore(_ score: Int, for playerID: GameCenterPlayerID) {
        var pending = pendingByPlayer[playerID] ?? Pending(
            highScore: nil,
            achievementPercents: [:]
        )
        let normalizedScore = max(0, score)
        pending.highScore = max(pending.highScore ?? normalizedScore, normalizedScore)
        pendingByPlayer[playerID] = pending
    }

    mutating func enqueueAchievement(
        id: AchievementID,
        percentComplete: Int,
        for playerID: GameCenterPlayerID
    ) {
        var pending = pendingByPlayer[playerID] ?? Pending(
            highScore: nil,
            achievementPercents: [:]
        )
        let normalizedPercent = min(100, max(0, percentComplete))
        pending.achievementPercents[id] = max(
            pending.achievementPercents[id, default: 0],
            normalizedPercent
        )
        pendingByPlayer[playerID] = pending
    }

    func batch(for playerID: GameCenterPlayerID) -> GameCenterSubmissionBatch? {
        guard let pending = pendingByPlayer[playerID], !pending.isEmpty else {
            return nil
        }

        let achievements = pending.achievementPercents
            .map { GameCenterAchievementSubmission(id: $0.key, percentComplete: $0.value) }
            .sorted { $0.id.rawValue < $1.id.rawValue }

        return GameCenterSubmissionBatch(
            playerID: playerID,
            highScore: pending.highScore,
            achievements: achievements
        )
    }

    @discardableResult
    mutating func acknowledge(_ batch: GameCenterSubmissionBatch) -> Bool {
        guard var current = pendingByPlayer[batch.playerID] else { return false }

        if let submittedScore = batch.highScore,
           let currentScore = current.highScore,
           currentScore <= submittedScore {
            current.highScore = nil
        }

        for submitted in batch.achievements {
            guard let currentPercent = current.achievementPercents[submitted.id],
                  currentPercent <= submitted.percentComplete else {
                continue
            }
            current.achievementPercents.removeValue(forKey: submitted.id)
        }

        if current.isEmpty {
            pendingByPlayer.removeValue(forKey: batch.playerID)
        } else {
            pendingByPlayer[batch.playerID] = current
        }
        return true
    }

    func pendingPlayerIDs() -> Set<GameCenterPlayerID> {
        Set(pendingByPlayer.keys)
    }
}

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

enum GameCenterServiceError: Error, Equatable, Sendable {
    case notAuthenticated
    case playerMismatch
    case transportUnavailable
}

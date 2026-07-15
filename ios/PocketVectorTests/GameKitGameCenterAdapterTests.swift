import Foundation
import GameKit
import XCTest

@testable import PocketVector

@MainActor
final class GameKitGameCenterAdapterTests: XCTestCase {
    func testConfigurationAcceptsOnlyLaunchCatalogAndApprovedDestinations() throws {
        let configuration = try makeConfiguration()

        XCTAssertEqual(
            try configuration.presentationRoute(for: .dashboard),
            .dashboard
        )
        XCTAssertEqual(
            try configuration.presentationRoute(
                for: .leaderboard(identifier: configuration.leaderboardIdentifier)
            ),
            .leaderboard(identifier: configuration.leaderboardIdentifier)
        )
        XCTAssertEqual(
            try configuration.presentationRoute(for: .achievements),
            .achievements
        )
        XCTAssertThrowsError(
            try configuration.presentationRoute(
                for: .leaderboard(identifier: "test.unapproved.leaderboard")
            )
        ) { error in
            XCTAssertEqual(
                error as? GameKitGameCenterConfigurationError,
                .unapprovedLeaderboardDestination
            )
        }

        var incomplete = configuration.achievementIdentifiers
        incomplete.removeValue(forKey: AchievementCatalog.launch[0].id)
        XCTAssertThrowsError(
            try GameKitGameCenterConfiguration(
                leaderboardIdentifier: "test.leaderboard",
                achievementIdentifiers: incomplete
            )
        ) { error in
            XCTAssertEqual(
                error as? GameKitGameCenterConfigurationError,
                .invalidAchievementSet
            )
        }
    }

    func testAuthenticationClassifierProducesPrivacySafeUnavailableStates() {
        let signedOut = GameKitPlayerSnapshot(
            isAuthenticated: false,
            gamePlayerID: nil
        )
        XCTAssertEqual(
            GameKitAuthenticationClassifier.resolve(
                snapshot: GameKitPlayerSnapshot(
                    isAuthenticated: true,
                    gamePlayerID: "game-player-a"
                ),
                error: GameKitErrorDescriptor(
                    domain: NSURLErrorDomain,
                    code: URLError.Code.notConnectedToInternet.rawValue
                ),
                didPresentAuthenticationUI: false
            ),
            .authenticated(GameCenterPlayerID("game-player-a"))
        )
        XCTAssertEqual(
            GameKitAuthenticationClassifier.resolve(
                snapshot: signedOut,
                error: GameKitErrorDescriptor(
                    domain: GKErrorDomain,
                    code: GKError.Code.userDenied.rawValue
                ),
                didPresentAuthenticationUI: true
            ),
            .unavailable(.declined)
        )
        XCTAssertEqual(
            GameKitAuthenticationClassifier.resolve(
                snapshot: signedOut,
                error: GameKitErrorDescriptor(
                    domain: GKErrorDomain,
                    code: GKError.Code.parentalControlsBlocked.rawValue
                ),
                didPresentAuthenticationUI: false
            ),
            .unavailable(.restricted)
        )
        XCTAssertEqual(
            GameKitAuthenticationClassifier.resolve(
                snapshot: signedOut,
                error: GameKitErrorDescriptor(
                    domain: NSURLErrorDomain,
                    code: URLError.Code.networkConnectionLost.rawValue
                ),
                didPresentAuthenticationUI: false
            ),
            .unavailable(.networkUnavailable)
        )
        XCTAssertEqual(
            GameKitAuthenticationClassifier.resolve(
                snapshot: signedOut,
                error: GameKitErrorDescriptor(domain: "test.service", code: 1),
                didPresentAuthenticationUI: false
            ),
            .unavailable(.serviceUnavailable)
        )
        XCTAssertEqual(
            GameKitAuthenticationClassifier.resolve(
                snapshot: signedOut,
                error: nil,
                didPresentAuthenticationUI: false
            ),
            .unavailable(.signedOut)
        )
    }

    func testOperationErrorMappingDropsProviderMessagesAndAliases() {
        let providerError = NSError(
            domain: NSURLErrorDomain,
            code: URLError.Code.notConnectedToInternet.rawValue,
            userInfo: [
                NSLocalizedDescriptionKey: "Do not surface PlayerAlias in the UI",
            ]
        )

        XCTAssertEqual(
            GameKitErrorDescriptor(providerError),
            GameKitErrorDescriptor(
                domain: NSURLErrorDomain,
                code: URLError.Code.notConnectedToInternet.rawValue
            )
        )
        XCTAssertEqual(
            GameKitServiceErrorMapper.serviceError(for: providerError),
            .transportUnavailable
        )
        XCTAssertEqual(
            GameKitServiceErrorMapper.serviceError(
                for: GameKitPlatformFailure.platform(
                    GameKitErrorDescriptor(
                        domain: GKErrorDomain,
                        code: GKError.Code.notAuthenticated.rawValue
                    )
                )
            ),
            .notAuthenticated
        )
    }

    func testAuthenticationDeclineReturnsUnavailableWithoutThrowing() async throws {
        let platform = FakeGameKitPlatformClient(
            snapshot: GameKitPlayerSnapshot(
                isAuthenticated: false,
                gamePlayerID: nil
            ),
            authenticationOutcome: .unavailable(.declined)
        )
        let service = GameKitGameCenterService(
            configuration: try makeConfiguration(),
            platformClient: platform
        )

        let state = await service.authenticate()
        let refreshedState = await service.authenticationState()

        XCTAssertEqual(state, .unavailable(.declined))
        XCTAssertEqual(refreshedState, .unavailable(.declined))
    }

    func testSubmissionRejectsBatchOwnedByAnotherPlayer() async throws {
        let playerA = GameCenterPlayerID("game-player-a")
        let playerB = GameCenterPlayerID("game-player-b")
        let platform = FakeGameKitPlatformClient(
            snapshot: authenticatedSnapshot(playerA),
            authenticationOutcome: .authenticated(playerA)
        )
        let service = GameKitGameCenterService(
            configuration: try makeConfiguration(),
            platformClient: platform
        )
        _ = await service.authenticate()

        do {
            try await service.submit(
                GameCenterSubmissionBatch(
                    playerID: playerB,
                    highScore: 1_000,
                    achievements: []
                )
            )
            XCTFail("A batch from another player must not reach GameKit")
        } catch {
            XCTAssertEqual(error as? GameCenterServiceError, .playerMismatch)
        }
        let submissions = await platform.recordedSubmissions()
        XCTAssertTrue(submissions.isEmpty)
    }

    func testSubmissionRechecksPlatformIdentityAfterAccountChange() async throws {
        let playerA = GameCenterPlayerID("game-player-a")
        let playerB = GameCenterPlayerID("game-player-b")
        let platform = FakeGameKitPlatformClient(
            snapshot: authenticatedSnapshot(playerA),
            authenticationOutcome: .authenticated(playerA)
        )
        let service = GameKitGameCenterService(
            configuration: try makeConfiguration(),
            platformClient: platform
        )
        let authenticatedState = await service.authenticate()
        XCTAssertEqual(authenticatedState, .authenticated(playerA))
        await platform.setSnapshot(authenticatedSnapshot(playerB))

        do {
            try await service.submit(
                GameCenterSubmissionBatch(
                    playerID: playerA,
                    highScore: 2_000,
                    achievements: []
                )
            )
            XCTFail("A stale player queue must not submit after account switching")
        } catch {
            XCTAssertEqual(error as? GameCenterServiceError, .playerMismatch)
        }
        let switchedState = await service.authenticationState()
        XCTAssertEqual(switchedState, .authenticated(playerB))
        let submissions = await platform.recordedSubmissions()
        XCTAssertTrue(submissions.isEmpty)
    }

    func testMaximumScoreAndAllEightAchievementsBuildOneValidatedBatch() async throws {
        let configuration = try makeConfiguration()
        let playerID = GameCenterPlayerID("game-player-a")
        let platform = FakeGameKitPlatformClient(
            snapshot: authenticatedSnapshot(playerID),
            authenticationOutcome: .authenticated(playerID)
        )
        let service = GameKitGameCenterService(
            configuration: configuration,
            platformClient: platform
        )
        _ = await service.authenticate()
        let achievementSubmissions = AchievementCatalog.launch.enumerated().map {
            index, definition in
            GameCenterAchievementSubmission(
                id: definition.id,
                percentComplete: (index + 1) * 10
            )
        }

        try await service.submit(
            GameCenterSubmissionBatch(
                playerID: playerID,
                highScore: Int.max,
                achievements: achievementSubmissions
            )
        )

        let submissions = await platform.recordedSubmissions()
        let submission = try XCTUnwrap(submissions.first)
        XCTAssertEqual(submissions.count, 1)
        XCTAssertEqual(submission.expectedPlayerID, playerID)
        XCTAssertEqual(submission.highScore, Int.max)
        XCTAssertEqual(submission.achievements.count, 8)
        XCTAssertEqual(
            Set(submission.achievements.map(\.providerIdentifier)),
            Set(configuration.achievementIdentifiers.values)
        )
        XCTAssertEqual(
            GameKitScoreConversion.platformScore(from: Int64.max),
            Int.max
        )
        XCTAssertEqual(GameKitScoreConversion.platformScore(from: -1), 0)
    }

    func testPresentationMapsAllDestinationsAndRejectsUnapprovedLeaderboard() async throws {
        let configuration = try makeConfiguration()
        let playerID = GameCenterPlayerID("game-player-a")
        let platform = FakeGameKitPlatformClient(
            snapshot: authenticatedSnapshot(playerID),
            authenticationOutcome: .authenticated(playerID)
        )
        let service = GameKitGameCenterService(
            configuration: configuration,
            platformClient: platform
        )
        _ = await service.authenticate()

        try await service.requestPresentation(.dashboard)
        try await service.requestPresentation(
            .leaderboard(identifier: configuration.leaderboardIdentifier)
        )
        try await service.requestPresentation(.achievements)

        let presentations = await platform.recordedPresentations()
        XCTAssertEqual(
            presentations.map(\.route),
            [
                .dashboard,
                .leaderboard(identifier: configuration.leaderboardIdentifier),
                .achievements,
            ]
        )
        XCTAssertTrue(presentations.allSatisfy { $0.playerID == playerID })

        do {
            try await service.requestPresentation(
                .leaderboard(identifier: "test.unapproved.leaderboard")
            )
            XCTFail("An unapproved leaderboard identifier must not be presented")
        } catch {
            XCTAssertEqual(error as? GameCenterServiceError, .transportUnavailable)
        }
        let unchangedPresentations = await platform.recordedPresentations()
        XCTAssertEqual(unchangedPresentations.count, 3)
    }

    private func makeConfiguration() throws -> GameKitGameCenterConfiguration {
        let mappings = Dictionary(
            uniqueKeysWithValues: AchievementCatalog.launch.enumerated().map {
                index, definition in
                (definition.id, "test.achievement.\(index)")
            }
        )
        return try GameKitGameCenterConfiguration(
            leaderboardIdentifier: "test.leaderboard.all_time",
            achievementIdentifiers: mappings
        )
    }

    private func authenticatedSnapshot(
        _ playerID: GameCenterPlayerID
    ) -> GameKitPlayerSnapshot {
        GameKitPlayerSnapshot(
            isAuthenticated: true,
            gamePlayerID: playerID.rawValue
        )
    }
}

private actor FakeGameKitPlatformClient: GameKitPlatformClient {
    struct Presentation: Equatable, Sendable {
        let route: GameKitPresentationRoute
        let playerID: GameCenterPlayerID
    }

    private var snapshot: GameKitPlayerSnapshot
    private let authenticationOutcome: GameKitPlatformAuthenticationOutcome
    private var submissions: [GameKitPlatformSubmission] = []
    private var presentations: [Presentation] = []

    init(
        snapshot: GameKitPlayerSnapshot,
        authenticationOutcome: GameKitPlatformAuthenticationOutcome
    ) {
        self.snapshot = snapshot
        self.authenticationOutcome = authenticationOutcome
    }

    func currentPlayerSnapshot() async -> GameKitPlayerSnapshot {
        snapshot
    }

    func authenticate() async -> GameKitPlatformAuthenticationOutcome {
        authenticationOutcome
    }

    func submit(_ submission: GameKitPlatformSubmission) async throws {
        guard snapshot.playerID != nil else {
            throw GameKitPlatformFailure.notAuthenticated
        }
        guard snapshot.playerID == submission.expectedPlayerID else {
            throw GameKitPlatformFailure.playerMismatch
        }
        submissions.append(submission)
    }

    func present(
        _ route: GameKitPresentationRoute,
        expectedPlayerID: GameCenterPlayerID
    ) async throws {
        guard snapshot.playerID != nil else {
            throw GameKitPlatformFailure.notAuthenticated
        }
        guard snapshot.playerID == expectedPlayerID else {
            throw GameKitPlatformFailure.playerMismatch
        }
        presentations.append(Presentation(route: route, playerID: expectedPlayerID))
    }

    func setSnapshot(_ snapshot: GameKitPlayerSnapshot) {
        self.snapshot = snapshot
    }

    func recordedSubmissions() -> [GameKitPlatformSubmission] {
        submissions
    }

    func recordedPresentations() -> [Presentation] {
        presentations
    }
}

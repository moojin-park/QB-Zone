import Foundation
import XCTest

@testable import PocketVector

final class GameCenterDeliveryCoordinatorTests: XCTestCase, @unchecked Sendable {
    private let baseDate = Date(timeIntervalSince1970: 1_750_100_000)
    private let playerA = GameCenterPlayerID("game-center-player-a")
    private let playerB = GameCenterPlayerID("game-center-player-b")

    func testSuccessfulDeliveryAcknowledgesExactBatchAndDuplicateTriggerIsEmpty()
        async throws
    {
        let fixture = try await makeFixture(
            pendingHighScore: 12_345,
            pendingAchievements: [LaunchAchievementID.firstRead: 40]
        )
        defer { removeTemporaryDirectory(fixture.directory) }
        let service = GameCenterDeliveryTestService(
            state: .authenticated(playerA)
        )
        let coordinator = makeCoordinator(fixture: fixture, service: service)

        let first = await coordinator.deliverPending()
        XCTAssertEqual(
            first,
            .delivered(
                GameCenterSubmissionBatch(
                    playerID: playerA,
                    highScore: 12_345,
                    achievements: [
                        GameCenterAchievementSubmission(
                            id: LaunchAchievementID.firstRead,
                            percentComplete: 40
                        ),
                    ]
                )
            )
        )
        let duplicate = await coordinator.deliverPending()
        XCTAssertEqual(duplicate, .noPendingSubmission(playerA))
        let submissions = await service.recordedSubmissions()
        XCTAssertEqual(submissions.count, 1)
        let remaining = try await fixture.repository.prepareGameCenterSubmission(
            for: playerA,
            session: fixture.loaded.session
        )
        XCTAssertNil(remaining)
    }

    func testSubmissionFailureRetainsPendingMaxima() async throws {
        let fixture = try await makeFixture(pendingHighScore: 500)
        defer { removeTemporaryDirectory(fixture.directory) }
        let service = GameCenterDeliveryTestService(
            state: .authenticated(playerA),
            submitBehavior: .failure
        )
        let coordinator = makeCoordinator(fixture: fixture, service: service)

        let outcome = await coordinator.deliverPending()
        XCTAssertEqual(outcome, .retained(.submissionFailed))
        try await assertPendingScore(500, fixture: fixture)
    }

    func testProviderCancellationRetainsPendingMaxima() async throws {
        let fixture = try await makeFixture(pendingHighScore: 600)
        defer { removeTemporaryDirectory(fixture.directory) }
        let service = GameCenterDeliveryTestService(
            state: .authenticated(playerA),
            submitBehavior: .cancellation
        )
        let coordinator = makeCoordinator(fixture: fixture, service: service)

        let outcome = await coordinator.deliverPending()
        XCTAssertEqual(outcome, .retained(.cancelled))
        try await assertPendingScore(600, fixture: fixture)
    }

    func testAmbiguousProviderFailureRetainsPendingMaxima() async throws {
        let fixture = try await makeFixture(pendingHighScore: 700)
        defer { removeTemporaryDirectory(fixture.directory) }
        let service = GameCenterDeliveryTestService(
            state: .authenticated(playerA),
            submitBehavior: .ambiguousFailure
        )
        let coordinator = makeCoordinator(fixture: fixture, service: service)

        let outcome = await coordinator.deliverPending()
        XCTAssertEqual(outcome, .retained(.submissionFailed))
        try await assertPendingScore(700, fixture: fixture)
    }

    func testSettlementDuringDeliveryIsQuarantinedAndNeverAcknowledgedAsPlayerA()
        async throws
    {
        let fixture = try await makeFixture(
            pendingHighScore: 100,
            pendingAchievements: [LaunchAchievementID.firstRead: 10]
        )
        defer { removeTemporaryDirectory(fixture.directory) }
        let service = GameCenterDeliveryTestService(
            state: .authenticated(playerA)
        )
        let newerRun = makeRun(score: 500)
        let repository = fixture.repository
        let session = fixture.loaded.session
        let settlementDate = baseDate.addingTimeInterval(1)
        await service.setOnSubmit { _ in
            _ = try await repository.settle(
                newerRun,
                session: session,
                recordedAt: settlementDate
            )
        }
        let coordinator = makeCoordinator(fixture: fixture, service: service)

        let outcome = await coordinator.deliverPending()
        guard case .delivered = outcome else {
            return XCTFail("Expected the older batch to succeed, got \(outcome)")
        }
        let remainingCandidate = try await repository.prepareGameCenterSubmission(
            for: playerA,
            session: session
        )
        XCTAssertNil(remainingCandidate)
        let locations = ProfileStorageLocations(directoryURL: fixture.directory)
        let persisted = try PlayerProfileMigrator().decode(
            Data(contentsOf: locations.primaryURL)
        )
        XCTAssertTrue(
            persisted.player.pendingGameCenter.pendingByPlayerID.isEmpty
        )
        XCTAssertEqual(
            persisted.player.pendingGameCenter.unboundPending.pendingHighScore,
            500
        )
        XCTAssertEqual(
            persisted.player.pendingGameCenter.unboundPending
                .pendingAchievementPercents[LaunchAchievementID.firstRead],
            100
        )
    }

    func testStaleProfileSessionNeverSubmitsOrAcknowledges() async throws {
        let fixture = try await makeFixture(pendingHighScore: 800)
        defer { removeTemporaryDirectory(fixture.directory) }
        let staleSession = ProfileSessionToken(
            accountIdentity: fixture.loaded.session.accountIdentity,
            nonce: UUID(),
            profileID: fixture.loaded.session.profileID
        )
        let service = GameCenterDeliveryTestService(
            state: .authenticated(playerA)
        )
        let coordinator = GameCenterDeliveryCoordinator.makeForTesting(
            repository: fixture.repository,
            service: service,
            session: staleSession,
            now: { self.baseDate }
        )

        let outcome = await coordinator.deliverPending()
        XCTAssertEqual(outcome, .retained(.repositoryRejected))
        let submissions = await service.recordedSubmissions()
        XCTAssertTrue(submissions.isEmpty)
        try await assertPendingScore(800, fixture: fixture)
    }

    func testPlayerSwitchBeforeSubmitRetainsPendingMaxima() async throws {
        let fixture = try await makeFixture(pendingHighScore: 900)
        defer { removeTemporaryDirectory(fixture.directory) }
        let service = GameCenterDeliveryTestService(
            state: .authenticated(playerA)
        )
        await service.setState(
            .authenticated(playerB),
            onAuthenticationStateRead: 2
        )
        let coordinator = makeCoordinator(fixture: fixture, service: service)

        let outcome = await coordinator.deliverPending()
        XCTAssertEqual(outcome, .retained(.playerChanged))
        let submissions = await service.recordedSubmissions()
        XCTAssertTrue(submissions.isEmpty)
        try await assertPendingScore(900, fixture: fixture)
    }

    func testPlayerSwitchDuringSubmitRetainsPendingMaxima() async throws {
        let fixture = try await makeFixture(pendingHighScore: 1_000)
        defer { removeTemporaryDirectory(fixture.directory) }
        let service = GameCenterDeliveryTestService(
            state: .authenticated(playerA),
            submitBehavior: .successAndSwitch(to: playerB)
        )
        let coordinator = makeCoordinator(fixture: fixture, service: service)

        let outcome = await coordinator.deliverPending()
        XCTAssertEqual(outcome, .retained(.playerChanged))
        try await assertPendingScore(1_000, fixture: fixture)
    }

    func testPlayerSwitchOnPostSubmitRevalidationRetainsPendingMaxima()
        async throws
    {
        let fixture = try await makeFixture(pendingHighScore: 1_100)
        defer { removeTemporaryDirectory(fixture.directory) }
        let service = GameCenterDeliveryTestService(
            state: .authenticated(playerA)
        )
        await service.setState(
            .authenticated(playerB),
            onAuthenticationStateRead: 3
        )
        let coordinator = makeCoordinator(fixture: fixture, service: service)

        let outcome = await coordinator.deliverPending()
        XCTAssertEqual(outcome, .retained(.playerChanged))
        try await assertPendingScore(1_100, fixture: fixture)
    }

    func testConcurrentDeliveryIsSingleFlight() async throws {
        let fixture = try await makeFixture(pendingHighScore: 1_200)
        defer { removeTemporaryDirectory(fixture.directory) }
        let service = GameCenterDeliveryTestService(
            state: .authenticated(playerA)
        )
        await service.setSubmissionBlocked(true)
        let coordinator = makeCoordinator(fixture: fixture, service: service)

        let first = Task { await coordinator.deliverPending() }
        try await waitUntil { await service.submissionBlockHasStarted() }
        let concurrent = await coordinator.deliverPending()
        XCTAssertEqual(concurrent, .alreadyInProgress)
        await service.releaseSubmissionBlock()
        let firstOutcome = await first.value
        guard case .delivered = firstOutcome else {
            return XCTFail("Expected first delivery to succeed, got \(firstOutcome)")
        }
        let submissions = await service.recordedSubmissions()
        XCTAssertEqual(submissions.count, 1)
    }

    func testZeroOnlyQueueDoesNotSubmit() async throws {
        let fixture = try await makeFixture(
            pendingHighScore: 0,
            pendingAchievements: [LaunchAchievementID.firstRead: 0]
        )
        defer { removeTemporaryDirectory(fixture.directory) }
        let service = GameCenterDeliveryTestService(
            state: .authenticated(playerA)
        )
        let coordinator = makeCoordinator(fixture: fixture, service: service)

        let outcome = await coordinator.deliverPending()
        XCTAssertEqual(outcome, .noPendingSubmission(playerA))
        let submissions = await service.recordedSubmissions()
        XCTAssertTrue(submissions.isEmpty)
    }

    func testRepositoryPreparationRejectionNeverReachesGameKit() async throws {
        let error = LocalGameCenterSubmissionError
            .unsupportedPendingAchievementIDs(
                [
                    AchievementID("achievement.unknown.a"),
                    AchievementID("achievement.unknown.z"),
                ]
            )
        let repository = RejectingGameCenterSubmissionRepository(error: error)
        let service = GameCenterDeliveryTestService(
            state: .authenticated(playerA)
        )
        let session = ProfileSessionToken(
            accountIdentity: .local,
            nonce: UUID(),
            profileID: UUID()
        )
        let coordinator = GameCenterDeliveryCoordinator.makeForTesting(
            repository: repository,
            service: service,
            session: session,
            now: { self.baseDate }
        )

        let outcome = await coordinator.deliverPending()

        XCTAssertEqual(outcome, .retained(.repositoryRejected))
        let submissions = await service.recordedSubmissions()
        XCTAssertTrue(submissions.isEmpty)
        let observedError = await repository.observedError()
        XCTAssertEqual(observedError, error)
    }

    func testPresentationAuthenticatesAndUsesInjectedService() async throws {
        let fixture = try await makeFixture()
        defer { removeTemporaryDirectory(fixture.directory) }
        let service = GameCenterDeliveryTestService(
            state: .notRequested,
            authenticationResult: .authenticated(playerA)
        )
        let coordinator = makeCoordinator(fixture: fixture, service: service)

        try await coordinator.requestPresentation(.achievements)

        let authenticationCount = await service.recordedAuthenticationCount()
        let presentations = await service.recordedPresentations()
        XCTAssertEqual(authenticationCount, 1)
        XCTAssertEqual(presentations, [.achievements])
    }

    func testCancellationAfterPostSubmitPlayerCheckRetainsPendingMaxima()
        async throws
    {
        let fixture = try await makeFixture(pendingHighScore: 1_300)
        defer { removeTemporaryDirectory(fixture.directory) }
        let service = GameCenterDeliveryTestService(
            state: .authenticated(playerA)
        )
        await service.blockAuthenticationStateRead(3)
        let coordinator = makeCoordinator(fixture: fixture, service: service)

        let delivery = Task { await coordinator.deliverPending() }
        try await waitUntil { await service.authenticationStateBlockHasStarted() }
        delivery.cancel()
        await service.releaseAuthenticationStateBlock()

        let outcome = await delivery.value
        XCTAssertEqual(outcome, .retained(.cancelled))
        try await assertPendingScore(1_300, fixture: fixture)
    }

    func testSuccessProofCannotAcknowledgeAnotherRepository() async throws {
        let profileID = UUID()
        let sessionNonce = UUID()
        let source = try await makeFixture(
            pendingHighScore: 1_400,
            profileID: profileID,
            sessionNonce: sessionNonce
        )
        let sink = try await makeFixture(
            pendingHighScore: 1_400,
            profileID: profileID,
            sessionNonce: sessionNonce
        )
        defer {
            removeTemporaryDirectory(source.directory)
            removeTemporaryDirectory(sink.directory)
        }
        XCTAssertEqual(source.loaded.session, sink.loaded.session)
        let proxy = CrossRepositoryAcknowledgementProxy(
            source: source.repository,
            sink: sink.repository
        )
        let service = GameCenterDeliveryTestService(
            state: .authenticated(playerA)
        )
        let coordinator = GameCenterDeliveryCoordinator.makeForTesting(
            repository: proxy,
            service: service,
            session: source.loaded.session,
            now: { self.baseDate }
        )

        let outcome = await coordinator.deliverPending()
        XCTAssertEqual(outcome, .retained(.repositoryRejected))
        try await assertPendingScore(1_400, fixture: source)
        try await assertPendingScore(1_400, fixture: sink)
    }

    func testSuccessProofCannotAcknowledgeDistinctPreparationOfSameValues()
        async throws
    {
        let fixture = try await makeFixture(pendingHighScore: 1_500)
        defer { removeTemporaryDirectory(fixture.directory) }
        let proxy = RepreparedAcknowledgementProxy(
            repository: fixture.repository
        )
        let service = GameCenterDeliveryTestService(
            state: .authenticated(playerA)
        )
        let coordinator = GameCenterDeliveryCoordinator.makeForTesting(
            repository: proxy,
            service: service,
            session: fixture.loaded.session,
            now: { self.baseDate }
        )

        let outcome = await coordinator.deliverPending()
        XCTAssertEqual(outcome, .retained(.repositoryRejected))
        try await assertPendingScore(1_500, fixture: fixture)
    }

    private func makeCoordinator(
        fixture: Fixture,
        service: GameCenterDeliveryTestService
    ) -> GameCenterDeliveryCoordinator {
        GameCenterDeliveryCoordinator.makeForTesting(
            repository: fixture.repository,
            service: service,
            session: fixture.loaded.session,
            now: { self.baseDate }
        )
    }

    private func makeFixture(
        pendingHighScore: Int = 0,
        pendingAchievements: [AchievementID: Int] = [:],
        profileID: UUID = UUID(),
        sessionNonce: UUID = UUID()
    ) async throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "PocketVectorGameCenterDeliveryTests-\(UUID().uuidString)",
            isDirectory: true
        )
        do {
            let seedRepository = LocalPlayerProfileRepository(
                directoryURL: directory,
                deviceID: "game-center-delivery-tests",
                accountIdentity: .local,
                sessionNonce: UUID(),
                economyMutationPolicy: .allowLocalTesting
            )
            let seeded = try await seedRepository.load(
                at: baseDate,
                newProfileID: profileID
            )
            let pending = GameCenterPendingMaximaV1(
                pendingHighScore: pendingHighScore,
                pendingAchievementPercents: pendingAchievements
            )
            if !pending.isEmpty {
                _ = try await seedRepository.settle(
                    makeRun(score: max(1, pendingHighScore)),
                    session: seeded.session,
                    recordedAt: baseDate
                )
                let locations = ProfileStorageLocations(directoryURL: directory)
                let migrator = PlayerProfileMigrator()
                var earnedDocument = try migrator.decode(
                    Data(contentsOf: locations.primaryURL)
                )
                for (achievementID, percent) in pendingAchievements {
                    earnedDocument.player.achievementProgress[achievementID] =
                        AchievementProgress(
                            id: achievementID,
                            percentComplete: percent,
                            completedAt: percent == 100 ? baseDate : nil
                        )
                }
                earnedDocument.player.pendingGameCenter =
                    PlayerScopedGameCenterQueueV1(
                        pendingByPlayerID: [playerA: pending]
                    )
                try PlayerProfileValidator.validate(earnedDocument)
                let exactEarnedProfile = try migrator.encode(
                    earnedDocument,
                    savedAt: baseDate
                )
                try exactEarnedProfile.write(
                    to: locations.primaryURL,
                    options: .atomic
                )
                try exactEarnedProfile.write(
                    to: locations.backupURL,
                    options: .atomic
                )
            }
            let repository = LocalPlayerProfileRepository(
                directoryURL: directory,
                deviceID: "game-center-delivery-tests",
                accountIdentity: .local,
                sessionNonce: sessionNonce,
                economyMutationPolicy: .allowLocalTesting
            )
            let loaded = try await repository.load(at: baseDate)
            return Fixture(
                directory: directory,
                repository: repository,
                loaded: loaded
            )
        } catch {
            removeTemporaryDirectory(directory)
            throw error
        }
    }

    private func assertPendingScore(
        _ expected: Int,
        fixture: Fixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let preparedCandidate = try await fixture.repository
            .prepareGameCenterSubmission(
                for: playerA,
                session: fixture.loaded.session
            )
        let prepared = try XCTUnwrap(preparedCandidate, file: file, line: line)
        XCTAssertEqual(
            prepared.batch.highScore,
            expected,
            file: file,
            line: line
        )
    }

    private func makeRun(score: Int) -> CompletedRun {
        let offense = LaunchCatalog.approved.team(id: LaunchTeamID.novaCityComets)!
        let defense = LaunchCatalog.approved.team(id: LaunchTeamID.highMesaHelions)!
        return CompletedRun(
            configuration: RunConfiguration(
                runID: RunID(UUID()),
                randomSeed: 1,
                offenseTeamID: offense.id,
                offenseJerseyID: offense.primaryJersey.id,
                defenseTeamID: defense.id,
                defenseJerseyID: defense.primaryJersey.id,
                footballID: LaunchFootballID.standard,
                economyVersion: PersistedEconomyRulesV1.run.economyVersion,
                startedAt: baseDate.addingTimeInterval(-60)
            ),
            endedAt: baseDate,
            elapsedGameplayMilliseconds: 60_000,
            finishReason: .timerExpired,
            score: score,
            statistics: RunStatisticsSnapshot(
                attempts: 2,
                completions: 1,
                touchdowns: 0,
                incompletions: 1,
                interceptions: 0,
                longestTouchdownStreak: 0
            ),
            completedLaneIDs: [.short],
            bonusTouchdownCount: 0
        )
    }

    private func waitUntil(
        _ condition: @escaping @Sendable () async -> Bool
    ) async throws {
        for _ in 0 ..< 1_000 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        throw GameCenterDeliveryTestError.timeout
    }

    private func removeTemporaryDirectory(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }
}

private struct Fixture: Sendable {
    let directory: URL
    let repository: LocalPlayerProfileRepository
    let loaded: LocalPlayerProfileSnapshot
}

private enum GameCenterDeliveryTestError: Error, Equatable, Sendable {
    case submissionFailure
    case ambiguousSubmissionFailure
    case timeout
}

private enum GameCenterDeliveryTestSubmitBehavior: Sendable {
    case success
    case failure
    case cancellation
    case ambiguousFailure
    case successAndSwitch(to: GameCenterPlayerID)
}

private actor GameCenterDeliveryTestService: GameCenterServicing {
    private var state: GameCenterAuthenticationState
    private let authenticationResult: GameCenterAuthenticationState
    private let submitBehavior: GameCenterDeliveryTestSubmitBehavior
    private var stateByAuthenticationRead: [Int: GameCenterAuthenticationState] = [:]
    private var authenticationStateReadCount = 0
    private var authenticationCount = 0
    private var submissions: [GameCenterSubmissionBatch] = []
    private var presentations: [GameCenterPresentationDestination] = []
    private var onSubmit: (@Sendable (GameCenterSubmissionBatch) async throws -> Void)?

    private var blockedAuthenticationStateRead: Int?
    private var authenticationStateBlockStarted = false
    private var authenticationStateContinuation: CheckedContinuation<Void, Never>?
    private var submissionIsBlocked = false
    private var submissionBlockStarted = false
    private var submissionContinuation: CheckedContinuation<Void, Never>?

    init(
        state: GameCenterAuthenticationState,
        authenticationResult: GameCenterAuthenticationState = .unavailable(.signedOut),
        submitBehavior: GameCenterDeliveryTestSubmitBehavior = .success
    ) {
        self.state = state
        self.authenticationResult = authenticationResult
        self.submitBehavior = submitBehavior
    }

    func authenticationState() async -> GameCenterAuthenticationState {
        authenticationStateReadCount += 1
        let read = authenticationStateReadCount
        if blockedAuthenticationStateRead == read {
            authenticationStateBlockStarted = true
            await withCheckedContinuation { continuation in
                authenticationStateContinuation = continuation
            }
        }
        if let replacement = stateByAuthenticationRead[read] {
            state = replacement
        }
        return state
    }

    func authenticate() -> GameCenterAuthenticationState {
        authenticationCount += 1
        state = authenticationResult
        return state
    }

    func submit(_ batch: GameCenterSubmissionBatch) async throws {
        guard state.playerID == batch.playerID else {
            throw GameCenterServiceError.playerMismatch
        }
        submissions.append(batch)
        if let onSubmit {
            try await onSubmit(batch)
        }
        if submissionIsBlocked {
            submissionBlockStarted = true
            await withCheckedContinuation { continuation in
                submissionContinuation = continuation
            }
        }
        switch submitBehavior {
        case .success:
            return
        case .failure:
            throw GameCenterDeliveryTestError.submissionFailure
        case .cancellation:
            throw CancellationError()
        case .ambiguousFailure:
            throw GameCenterDeliveryTestError.ambiguousSubmissionFailure
        case let .successAndSwitch(playerID):
            state = .authenticated(playerID)
        }
    }

    func requestPresentation(
        _ destination: GameCenterPresentationDestination
    ) throws {
        guard state.playerID != nil else {
            throw GameCenterServiceError.notAuthenticated
        }
        presentations.append(destination)
    }

    func setState(
        _ state: GameCenterAuthenticationState,
        onAuthenticationStateRead read: Int
    ) {
        stateByAuthenticationRead[read] = state
    }

    func setOnSubmit(
        _ operation: @escaping @Sendable (
            GameCenterSubmissionBatch
        ) async throws -> Void
    ) {
        onSubmit = operation
    }

    func blockAuthenticationStateRead(_ read: Int) {
        blockedAuthenticationStateRead = read
    }

    func authenticationStateBlockHasStarted() -> Bool {
        authenticationStateBlockStarted
    }

    func releaseAuthenticationStateBlock() {
        authenticationStateContinuation?.resume()
        authenticationStateContinuation = nil
    }

    func setSubmissionBlocked(_ blocked: Bool) {
        submissionIsBlocked = blocked
    }

    func submissionBlockHasStarted() -> Bool {
        submissionBlockStarted
    }

    func releaseSubmissionBlock() {
        submissionContinuation?.resume()
        submissionContinuation = nil
        submissionIsBlocked = false
    }

    func recordedAuthenticationCount() -> Int {
        authenticationCount
    }

    func recordedSubmissions() -> [GameCenterSubmissionBatch] {
        submissions
    }

    func recordedPresentations() -> [GameCenterPresentationDestination] {
        presentations
    }
}

private actor CrossRepositoryAcknowledgementProxy: GameCenterSubmissionRepository {
    private let source: LocalPlayerProfileRepository
    private let sink: LocalPlayerProfileRepository

    init(
        source: LocalPlayerProfileRepository,
        sink: LocalPlayerProfileRepository
    ) {
        self.source = source
        self.sink = sink
    }

    func prepareGameCenterSubmission(
        for playerID: GameCenterPlayerID,
        session: ProfileSessionToken
    ) async throws -> LocalGameCenterPreparedSubmissionV1? {
        try await source.prepareGameCenterSubmission(
            for: playerID,
            session: session
        )
    }

    func acknowledgeGameCenterSubmission(
        _ submission: LocalGameCenterPreparedSubmissionV1,
        successfulResult: GameCenterSuccessfulSubmissionV1,
        session: ProfileSessionToken,
        at date: Date
    ) async throws -> LocalPlayerProfileSnapshot {
        try await sink.acknowledgeGameCenterSubmission(
            submission,
            successfulResult: successfulResult,
            session: session,
            at: date
        )
    }
}

private actor RepreparedAcknowledgementProxy: GameCenterSubmissionRepository {
    private let repository: LocalPlayerProfileRepository

    init(repository: LocalPlayerProfileRepository) {
        self.repository = repository
    }

    func prepareGameCenterSubmission(
        for playerID: GameCenterPlayerID,
        session: ProfileSessionToken
    ) async throws -> LocalGameCenterPreparedSubmissionV1? {
        try await repository.prepareGameCenterSubmission(
            for: playerID,
            session: session
        )
    }

    func acknowledgeGameCenterSubmission(
        _ submission: LocalGameCenterPreparedSubmissionV1,
        successfulResult: GameCenterSuccessfulSubmissionV1,
        session: ProfileSessionToken,
        at date: Date
    ) async throws -> LocalPlayerProfileSnapshot {
        guard let distinctPreparation = try await repository
            .prepareGameCenterSubmission(
                for: submission.batch.playerID,
                session: session
            ) else {
            throw GameCenterDeliveryTestError.submissionFailure
        }
        return try await repository.acknowledgeGameCenterSubmission(
            distinctPreparation,
            successfulResult: successfulResult,
            session: session,
            at: date
        )
    }
}

private actor RejectingGameCenterSubmissionRepository:
    GameCenterSubmissionRepository
{
    private let error: LocalGameCenterSubmissionError
    private var observedPreparationError: LocalGameCenterSubmissionError?

    init(error: LocalGameCenterSubmissionError) {
        self.error = error
    }

    func prepareGameCenterSubmission(
        for playerID: GameCenterPlayerID,
        session: ProfileSessionToken
    ) throws -> LocalGameCenterPreparedSubmissionV1? {
        observedPreparationError = error
        throw error
    }

    func acknowledgeGameCenterSubmission(
        _ submission: LocalGameCenterPreparedSubmissionV1,
        successfulResult: GameCenterSuccessfulSubmissionV1,
        session: ProfileSessionToken,
        at date: Date
    ) throws -> LocalPlayerProfileSnapshot {
        throw error
    }

    func observedError() -> LocalGameCenterSubmissionError? {
        observedPreparationError
    }
}

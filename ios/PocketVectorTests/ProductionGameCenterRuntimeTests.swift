import XCTest
@testable import PocketVector

final class ProductionGameCenterRuntimeTests: XCTestCase, @unchecked Sendable {
    func testClaimCreatesOnceAndSamePlayerRetryIsAuthorized() async throws {
        let configuration = try makeCloudConfiguration()
        let client = GameCenterClaimDatabaseClientDouble()
        let store = ProductionGameCenterCloudClaimStore(
            cloudConfiguration: configuration,
            client: client
        )
        let accountID = configuration.transport.accountID(
            forProviderRecordName: "provider-a"
        )
        let binding = CloudAccountDerivedBindings.derive(from: accountID)
            .durableAccountBinding
        let playerID = GameCenterPlayerID("game-player-a")

        let firstClaim = await store.claimOwnership(
            playerID: playerID,
            accountID: accountID,
            durableBinding: binding
        )
        let retryClaim = await store.claimOwnership(
            playerID: playerID,
            accountID: accountID,
            durableBinding: binding
        )
        let createCount = await client.createCount()

        XCTAssertTrue(isAuthorized(firstClaim))
        XCTAssertTrue(isAuthorized(retryClaim))
        XCTAssertEqual(createCount, 1)
    }

    func testTwoPlayerRaceHasExactlyOneOwner() async throws {
        let configuration = try makeCloudConfiguration()
        let client = GameCenterClaimDatabaseClientDouble()
        let firstStore = ProductionGameCenterCloudClaimStore(
            cloudConfiguration: configuration,
            client: client
        )
        let secondStore = ProductionGameCenterCloudClaimStore(
            cloudConfiguration: configuration,
            client: client
        )
        let accountID = configuration.transport.accountID(
            forProviderRecordName: "provider-a"
        )
        let binding = CloudAccountDerivedBindings.derive(from: accountID)
            .durableAccountBinding

        async let first = firstStore.claimOwnership(
            playerID: GameCenterPlayerID("game-player-a"),
            accountID: accountID,
            durableBinding: binding
        )
        async let second = secondStore.claimOwnership(
            playerID: GameCenterPlayerID("game-player-b"),
            accountID: accountID,
            durableBinding: binding
        )
        let results = await [first, second]

        XCTAssertEqual(results.filter(isAuthorized).count, 1)
        XCTAssertEqual(
            results.filter { $0 == .ownedByDifferentPlayer }.count,
            1
        )
        let createCount = await client.createCount()
        XCTAssertTrue((1 ... 2).contains(createCount))
    }

    func testLostCreateResponseUsesExactReadback() async throws {
        let configuration = try makeCloudConfiguration()
        let client = GameCenterClaimDatabaseClientDouble(
            createFailureAfterSave: true
        )
        let store = ProductionGameCenterCloudClaimStore(
            cloudConfiguration: configuration,
            client: client
        )
        let accountID = configuration.transport.accountID(
            forProviderRecordName: "provider-a"
        )

        let result = await store.claimOwnership(
            playerID: GameCenterPlayerID("game-player-a"),
            accountID: accountID,
            durableBinding: CloudAccountDerivedBindings.derive(
                from: accountID
            ).durableAccountBinding
        )
        XCTAssertTrue(isAuthorized(result))
    }

    func testDifferentPlayerMalformedRecordAccountSwitchAndDeletionFailClosed()
        async throws
    {
        let configuration = try makeCloudConfiguration()
        let client = GameCenterClaimDatabaseClientDouble()
        let store = ProductionGameCenterCloudClaimStore(
            cloudConfiguration: configuration,
            client: client
        )
        let accountID = configuration.transport.accountID(
            forProviderRecordName: "provider-a"
        )
        let binding = CloudAccountDerivedBindings.derive(from: accountID)
            .durableAccountBinding

        let initial = await store.claimOwnership(
            playerID: GameCenterPlayerID("game-player-a"),
            accountID: accountID,
            durableBinding: binding
        )
        let differentPlayer = await store.claimOwnership(
            playerID: GameCenterPlayerID("game-player-b"),
            accountID: accountID,
            durableBinding: binding
        )
        XCTAssertTrue(isAuthorized(initial))
        XCTAssertEqual(differentPlayer, .ownedByDifferentPlayer)

        await client.replaceRecord(
            ProductionGameCenterClaimProviderRecord(
                recordType: configuration.profile.rootRecordType,
                fields: [configuration.transport.payloadFieldName: Data("bad".utf8)]
            )
        )
        let malformed = await store.claimOwnership(
            playerID: GameCenterPlayerID("game-player-a"),
            accountID: accountID,
            durableBinding: binding
        )
        XCTAssertEqual(malformed, .unavailable)

        await client.replaceRecord(nil)
        let deleted = await store.claimOwnership(
            playerID: GameCenterPlayerID("game-player-a"),
            accountID: accountID,
            durableBinding: binding
        )
        XCTAssertEqual(deleted, .unavailable)

        await client.setProviderRecordName("provider-b")
        let switchedAccount = await store.claimOwnership(
            playerID: GameCenterPlayerID("game-player-a"),
            accountID: accountID,
            durableBinding: binding
        )
        XCTAssertEqual(switchedAccount, .unavailable)
    }

    func testDifferentCloudAccountsUseDifferentClaimRecords() async throws {
        let configuration = try makeCloudConfiguration()
        let client = GameCenterClaimDatabaseClientDouble()
        let store = ProductionGameCenterCloudClaimStore(
            cloudConfiguration: configuration,
            client: client
        )
        let firstAccountID = configuration.transport.accountID(
            forProviderRecordName: "provider-a"
        )
        let first = await store.claimOwnership(
            playerID: GameCenterPlayerID("game-player-a"),
            accountID: firstAccountID,
            durableBinding: CloudAccountDerivedBindings.derive(
                from: firstAccountID
            ).durableAccountBinding
        )
        XCTAssertTrue(isAuthorized(first))

        await client.setProviderRecordName("provider-b")
        let secondAccountID = configuration.transport.accountID(
            forProviderRecordName: "provider-b"
        )
        let second = await store.claimOwnership(
            playerID: GameCenterPlayerID("game-player-b"),
            accountID: secondAccountID,
            durableBinding: CloudAccountDerivedBindings.derive(
                from: secondAccountID
            ).durableAccountBinding
        )

        let recordCount = await client.recordCount()
        XCTAssertTrue(isAuthorized(second))
        XCTAssertEqual(recordCount, 2)
    }

    func testVerifiedClaimAttributesUnboundQueueAndAcknowledgesExactlyOnce()
        async throws
    {
        let configuration = try makeCloudConfiguration()
        let client = GameCenterClaimDatabaseClientDouble()
        let claimStore = ProductionGameCenterCloudClaimStore(
            cloudConfiguration: configuration,
            client: client
        )
        let accountID = configuration.transport.accountID(
            forProviderRecordName: "provider-a"
        )
        let bindings = CloudAccountDerivedBindings.derive(from: accountID)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let repository = LocalPlayerProfileRepository(
            directoryURL: directory,
            deviceID: "production-game-center-tests",
            accountIdentity: bindings.playerAccountIdentity,
            sessionNonce: UUID(),
            economyMutationPolicy: .allowLocalTesting
        )
        let loaded = try await repository.load(
            at: Date(timeIntervalSince1970: 100),
            newProfileID: bindings.durableAccountBinding.profileID
        )
        _ = try await repository.settle(
            makeCompletedRun(score: 65_000),
            session: loaded.session,
            recordedAt: Date(timeIntervalSince1970: 101)
        )
        let verifiedClaim = try await ProductionVerifiedAccountClaim(
            cloudAccountID: accountID,
            derivedBindings: bindings,
            installedRepository: repository
        )
        let router = ProductionProfileRepositoryRouter(
            route: ProductionProfileRepositoryRoute(
                repository: repository,
                authority: .verifiedPrivateCloud(verifiedClaim)
            )
        )
        let channel = ProductionRoutingGameCenterSubmissionChannel(
            repositoryRouter: router,
            ownershipClaimer: claimStore,
            now: { Date(timeIntervalSince1970: 101) }
        )
        let playerID = GameCenterPlayerID("game-player-a")
        let service = ProductionGameCenterServiceDouble(
            state: .authenticated(playerID)
        )
        let coordinator = GameCenterDeliveryCoordinator.makeForProduction(
            submissionChannel: channel,
            service: service,
            now: { Date(timeIntervalSince1970: 102) }
        )

        let first = await coordinator.foreground()
        let duplicate = await coordinator.foreground()
        let submissions = await service.recordedSubmissions()
        let persisted = try PlayerProfileMigrator().decode(
            Data(
                contentsOf: ProfileStorageLocations(directoryURL: directory)
                    .primaryURL
            )
        )

        guard case let .delivered(batch) = first else {
            return XCTFail("Expected delivery, got \(first)")
        }
        XCTAssertEqual(batch.playerID, playerID)
        XCTAssertEqual(batch.highScore, 65_000)
        XCTAssertEqual(duplicate, .noPendingSubmission(playerID))
        XCTAssertEqual(submissions.count, 1)
        XCTAssertTrue(
            persisted.player.pendingGameCenter.unboundPending.isEmpty
        )
        XCTAssertNil(
            persisted.player.pendingGameCenter.pendingByPlayerID[playerID]
        )
    }

    @MainActor
    func testDeliveryTriggerAndLeaderboardRequestRemainSerialized() async throws {
        let gate = ProductionGameCenterTestGate()
        let channel = ProductionGameCenterChannelDouble(firstPrepareGate: gate)
        let playerID = GameCenterPlayerID("game-player-a")
        let service = ProductionGameCenterServiceDouble(
            state: .authenticated(playerID)
        )
        let coordinator = GameCenterDeliveryCoordinator.makeForProduction(
            submissionChannel: channel,
            service: service
        )
        let configuration = try GameKitGameCenterConfiguration(
            leaderboardIdentifier:
                "com.pocketvector.game.leaderboard.highscore.v1",
            achievementIdentifiers: Dictionary(
                uniqueKeysWithValues: AchievementCatalog.launch.map {
                    ($0.id, $0.id.rawValue)
                }
            )
        )
        let runtime = ProductionGameCenterRuntime(
            configuration: configuration,
            coordinator: coordinator
        )
        runtime.setApplicationActive(true)

        runtime.scheduleDelivery()
        for _ in 0 ..< 200 {
            if await channel.prepareCount() == 1 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        let initialPrepareCount = await channel.prepareCount()
        XCTAssertEqual(initialPrepareCount, 1)

        runtime.scheduleDelivery()
        let presentation = Task { @MainActor in
            await runtime.presentLeaderboard()
        }
        await gate.open()
        let outcome = await presentation.value
        let prepareCount = await channel.prepareCount()
        let presentationCount = await service.presentationCount()

        XCTAssertEqual(outcome, .completed)
        XCTAssertEqual(prepareCount, 3)
        XCTAssertEqual(presentationCount, 1)
    }

    @MainActor
    func testRapidReactivationDrainsCanceledDeliveryBeforeCoalescedRetry()
        async throws
    {
        let gate = ProductionGameCenterTestGate()
        let channel = ProductionGameCenterChannelDouble(firstPrepareGate: gate)
        let service = ProductionGameCenterServiceDouble(
            state: .authenticated(GameCenterPlayerID("game-player-a"))
        )
        let runtime = ProductionGameCenterRuntime(
            configuration: try GameKitGameCenterConfiguration(
                leaderboardIdentifier:
                    "com.pocketvector.game.leaderboard.highscore.v1",
                achievementIdentifiers: Dictionary(
                    uniqueKeysWithValues: AchievementCatalog.launch.map {
                        ($0.id, $0.id.rawValue)
                    }
                )
            ),
            coordinator: GameCenterDeliveryCoordinator.makeForProduction(
                submissionChannel: channel,
                service: service
            )
        )

        runtime.setApplicationActive(true)
        runtime.scheduleDelivery()
        for _ in 0 ..< 200 {
            if await channel.prepareCount() == 1 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        let firstPrepareCount = await channel.prepareCount()
        XCTAssertEqual(firstPrepareCount, 1)

        runtime.setApplicationActive(false)
        runtime.setApplicationActive(true)
        runtime.scheduleDelivery()
        await gate.open()
        for _ in 0 ..< 200 {
            if await channel.prepareCount() == 2 { break }
            try await Task.sleep(for: .milliseconds(5))
        }

        let finalPrepareCount = await channel.prepareCount()
        let presentationCount = await service.presentationCount()
        XCTAssertEqual(finalPrepareCount, 2)
        XCTAssertEqual(presentationCount, 0)
    }

    private func isAuthorized(
        _ result: ProductionGameCenterClaimResult
    ) -> Bool {
        if case .authorized = result { return true }
        return false
    }

    private func makeCompletedRun(score: Int) -> CompletedRun {
        let catalog = LaunchCatalog.approved
        let offense = catalog.team(id: LaunchTeamID.novaCityComets)!
        let defense = catalog.team(id: LaunchTeamID.highMesaHelions)!
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
                startedAt: Date(timeIntervalSince1970: 40)
            ),
            endedAt: Date(timeIntervalSince1970: 100),
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

    private func makeCloudConfiguration() throws
        -> ProductionCloudWriteConfiguration
    {
        try ProductionCloudWriteConfiguration(
            transport: CloudKitCloudSyncConfiguration._testOnly(
                containerIdentifier: "iCloud.com.pocketvector.game",
                containerEnvironment: .development,
                zoneName: "PocketVectorPrivateZone",
                payloadFieldName: "payload",
                operationRecordType: "OperationMarker",
                accountIdentifierNamespace: "account-v1",
                recordNameNamespace: "record-v1"
            ),
            economy: DurableEconomyCloudConfiguration(
                recordID: CloudRecordID("economy-head-v1"),
                recordType: "EconomyHead",
                payloadFieldName: "economyPayload"
            ),
            profile: CloudProfileSchemaConfiguration(
                rootRecordType: "ProfileRoot",
                settingsRecordType: "ProfileSettings",
                selectionRecordType: "ProfileSelection",
                runRecordType: "ProfileRun",
                payloadFieldName: "profilePayload"
            )
        )
    }
}

private actor ProductionGameCenterServiceDouble: GameCenterServicing {
    private var state: GameCenterAuthenticationState
    private var submissions: [GameCenterSubmissionBatch] = []
    private var presentations: [GameCenterPresentationDestination] = []

    init(state: GameCenterAuthenticationState) {
        self.state = state
    }

    func authenticationState() -> GameCenterAuthenticationState { state }
    func authenticate() -> GameCenterAuthenticationState { state }

    func submit(_ batch: GameCenterSubmissionBatch) {
        submissions.append(batch)
    }

    func requestPresentation(
        _ destination: GameCenterPresentationDestination
    ) {
        presentations.append(destination)
    }

    func recordedSubmissions() -> [GameCenterSubmissionBatch] { submissions }
    func presentationCount() -> Int { presentations.count }
}

private enum ProductionGameCenterTestError: Error {
    case unexpectedAcknowledgement
}

private actor ProductionGameCenterChannelDouble: GameCenterSubmissionChannel {
    private let firstPrepareGate: ProductionGameCenterTestGate
    private var storedPrepareCount = 0

    init(firstPrepareGate: ProductionGameCenterTestGate) {
        self.firstPrepareGate = firstPrepareGate
    }

    func prepareGameCenterSubmission(
        for playerID: GameCenterPlayerID
    ) async -> LocalGameCenterPreparedSubmissionV1? {
        storedPrepareCount += 1
        if storedPrepareCount == 1 {
            await firstPrepareGate.wait()
        }
        return nil
    }

    func acknowledgeGameCenterSubmission(
        _ submission: LocalGameCenterPreparedSubmissionV1,
        successfulResult: GameCenterSuccessfulSubmissionV1,
        at date: Date
    ) throws -> LocalPlayerProfileSnapshot {
        throw ProductionGameCenterTestError.unexpectedAcknowledgement
    }

    func prepareCount() -> Int { storedPrepareCount }
}

private actor ProductionGameCenterTestGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
}

private actor GameCenterClaimDatabaseClientDouble:
    ProductionGameCenterClaimDatabaseClient
{
    private var providerRecordName: String
    private var records: [String: ProductionGameCenterClaimProviderRecord] = [:]
    private var lastRecordName: String?
    private var creates = 0
    private let createFailureAfterSave: Bool

    init(
        providerRecordName: String = "provider-a",
        createFailureAfterSave: Bool = false
    ) {
        self.providerRecordName = providerRecordName
        self.createFailureAfterSave = createFailureAfterSave
    }

    func activeProviderRecordName() -> String {
        providerRecordName
    }

    func fetchClaim(
        recordName: String
    ) -> ProductionGameCenterClaimProviderRecord? {
        lastRecordName = recordName
        return records[recordName]
    }

    func createClaim(
        recordName: String,
        recordType: String,
        payloadFieldName: String,
        payload: Data,
        expectedProviderRecordName: String
    ) throws {
        creates += 1
        guard providerRecordName == expectedProviderRecordName else {
            throw CloudKitClientFailure.providerAccountMismatch
        }
        guard records[recordName] == nil else {
            throw CloudKitClientFailure.conflict(
                recordNames: [recordName]
            )
        }
        lastRecordName = recordName
        records[recordName] = ProductionGameCenterClaimProviderRecord(
            recordType: recordType,
            fields: [payloadFieldName: payload]
        )
        if createFailureAfterSave {
            throw CloudKitClientFailure.responseLost
        }
    }

    func createCount() -> Int {
        creates
    }

    func replaceRecord(_ record: ProductionGameCenterClaimProviderRecord?) {
        guard let lastRecordName else { return }
        records[lastRecordName] = record
    }

    func setProviderRecordName(_ providerRecordName: String) {
        self.providerRecordName = providerRecordName
    }

    func recordCount() -> Int {
        records.count
    }
}

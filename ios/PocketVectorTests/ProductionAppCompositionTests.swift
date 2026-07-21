import Foundation
import XCTest

@testable import PocketVector

final class ProductionAppCompositionTests: XCTestCase, @unchecked Sendable {
    @MainActor
    func testInstallationDeviceIdentifierIsStableAndAppScoped() throws {
        let suiteName = "PocketVector.InstallationID.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let firstUUID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let unusedUUID = UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!

        let first = StableInstallationDeviceIdentifierStore(
            userDefaults: defaults,
            makeUUID: { firstUUID }
        ).identifier()
        let restored = StableInstallationDeviceIdentifierStore(
            userDefaults: defaults,
            makeUUID: { unusedUUID }
        ).identifier()

        XCTAssertEqual(first, firstUUID.uuidString.lowercased())
        XCTAssertEqual(restored, first)
        XCTAssertNotNil(UUID(uuidString: restored))
    }

    @MainActor
    func testAccountScopedPathsAreOpaqueAndIndependent() {
        let root = URL(fileURLWithPath: "/private/test/Application Support")
        let firstIdentity = PlayerAccountIdentity("account-a@example.invalid")
        let secondIdentity = PlayerAccountIdentity("account-b@example.invalid")
        let first = ProductionAppComposition.profileDirectoryURL(
            applicationSupportDirectoryURL: root,
            accountIdentity: firstIdentity
        )
        let second = ProductionAppComposition.profileDirectoryURL(
            applicationSupportDirectoryURL: root,
            accountIdentity: secondIdentity
        )

        XCTAssertNotEqual(first, second)
        XCTAssertFalse(first.path.contains(firstIdentity.rawValue))
        XCTAssertFalse(second.path.contains(secondIdentity.rawValue))
        XCTAssertTrue(first.path.contains("PocketVector/Profiles"))
    }

    @MainActor
    func testDurableSettingsAndSelectionSurviveRelaunch() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let account = PlayerAccountIdentity("durability-test-account")
        let clock = TestClock(Date(timeIntervalSince1970: 10_000))

        let first = AppCoordinator(
            environment: makeEnvironment(
                root: root,
                account: account,
                deviceID: "installation-device-a",
                sessionNonce: fixedUUID(1),
                newProfileID: fixedUUID(101),
                clock: clock
            )
        )
        await first.bootstrap()
        XCTAssertEqual(first.bootstrapState, .ready)

        clock.advance(by: 1)
        await first.selectTeam(LaunchTeamID.highMesaHelions)
        clock.advance(by: 1)
        await first.setMusicVolume(0.19)
        clock.advance(by: 1)
        await first.setMuted(true)

        XCTAssertEqual(first.state.selection.selectedTeamID, LaunchTeamID.highMesaHelions)
        XCTAssertEqual(first.state.settings.musicVolume, 0.19)
        XCTAssertTrue(first.state.settings.isMuted)

        let relaunched = AppCoordinator(
            environment: makeEnvironment(
                root: root,
                account: account,
                deviceID: "installation-device-a",
                sessionNonce: fixedUUID(2),
                newProfileID: fixedUUID(202),
                clock: clock
            )
        )
        await relaunched.bootstrap()

        XCTAssertEqual(relaunched.bootstrapState, .ready)
        XCTAssertEqual(
            relaunched.state.selection.selectedTeamID,
            LaunchTeamID.highMesaHelions
        )
        XCTAssertEqual(relaunched.state.settings.musicVolume, 0.19)
        XCTAssertTrue(relaunched.state.settings.isMuted)
        XCTAssertEqual(relaunched.state.syncStatus, .localOnly)
    }

    @MainActor
    func testSuccessfulRepositoryMutationPublishesMatchingVersionedProjection() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let clock = TestClock(Date(timeIntervalSince1970: 15_000))
        let channel = ProductionAuthoritativeStateChannel()
        let composition = ProductionAppComposition(
            dependencies: ProductionAppDependencies(
                applicationSupportDirectoryURL: root,
                accountIdentity: .local,
                deviceID: "installation-device-stream",
                sessionNonce: fixedUUID(12),
                newProfileID: fixedUUID(112),
                now: { clock.date },
                makeRunID: { self.fixedRunID(12) },
                makeSeed: { 12 }
            ),
            authoritativeStateChannel: channel
        )
        let coordinator = AppCoordinator(environment: composition.environment)
        await coordinator.bootstrap()
        let initial = try XCTUnwrap(coordinator.authoritativeSnapshot)
        XCTAssertEqual(initial.syncRevision, 0)
        XCTAssertEqual(initial.state.syncStatus, .localOnly)
        var iterator = channel.makeStream().makeAsyncIterator()

        clock.advance(by: 1)
        await coordinator.selectTeam(LaunchTeamID.highMesaHelions)
        let published = await iterator.next()

        XCTAssertEqual(published, coordinator.authoritativeSnapshot)
        XCTAssertEqual(published?.session, initial.session)
        XCTAssertEqual(published?.playerRevision, initial.playerRevision + 1)
        XCTAssertEqual(published?.economyRevision, initial.economyRevision)
        XCTAssertEqual(
            published?.state.selection.selectedTeamID,
            LaunchTeamID.highMesaHelions
        )
    }

    @MainActor
    func testSyncTransitionPublishesOnlyOnChangeAndPersistsAcrossRepositoryMutations() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let clock = TestClock(Date(timeIntervalSince1970: 16_000))
        let channel = ProductionAuthoritativeStateChannel()
        let composition = ProductionAppComposition(
            dependencies: ProductionAppDependencies(
                applicationSupportDirectoryURL: root,
                accountIdentity: .local,
                deviceID: "sync-transition-device",
                sessionNonce: fixedUUID(13),
                newProfileID: fixedUUID(113),
                now: { clock.date },
                makeRunID: { self.fixedRunID(13) },
                makeSeed: { 13 }
            ),
            authoritativeStateChannel: channel
        )
        let coordinator = AppCoordinator(environment: composition.environment)
        await coordinator.bootstrap()
        let initial = try XCTUnwrap(coordinator.authoritativeSnapshot)
        var iterator = channel.makeStream().makeAsyncIterator()

        let syncing = try XCTUnwrap(
            composition.publishSyncStatusTransition(.syncing)
        )
        let publishedSyncing = await iterator.next()

        XCTAssertEqual(publishedSyncing, syncing)
        XCTAssertEqual(syncing.playerRevision, initial.playerRevision)
        XCTAssertEqual(syncing.economyRevision, initial.economyRevision)
        XCTAssertEqual(syncing.syncRevision, initial.syncRevision + 1)
        XCTAssertEqual(syncing.state.syncStatus, .syncing)
        XCTAssertNil(try composition.publishSyncStatusTransition(.syncing))
        XCTAssertEqual(coordinator.applyAuthoritativeUpdate(syncing), .applied)

        clock.advance(by: 1)
        await coordinator.setTutorialEnabled(false)
        let settingsUpdate = await iterator.next()
        XCTAssertEqual(settingsUpdate, coordinator.authoritativeSnapshot)
        XCTAssertEqual(settingsUpdate?.syncRevision, syncing.syncRevision)
        XCTAssertEqual(settingsUpdate?.state.syncStatus, .syncing)
        XCTAssertGreaterThan(settingsUpdate?.playerRevision ?? 0, initial.playerRevision)
        XCTAssertEqual(settingsUpdate?.economyRevision, initial.economyRevision)

        let configuration = try await launchConfiguration(from: coordinator)
        let run = makeNaturalRun(configuration: configuration)
        clock.date = run.endedAt.addingTimeInterval(1)
        await coordinator.handleCompletedRun(run)
        let settlementUpdate = await iterator.next()

        XCTAssertEqual(settlementUpdate, coordinator.authoritativeSnapshot)
        XCTAssertEqual(settlementUpdate?.syncRevision, syncing.syncRevision)
        XCTAssertEqual(settlementUpdate?.state.syncStatus, .syncing)
        XCTAssertGreaterThan(
            settlementUpdate?.economyRevision ?? 0,
            initial.economyRevision
        )
    }

    @MainActor
    func testSyncTransitionBeforeProfileLoadIsRetainedInBootstrapSnapshot() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let composition = ProductionAppComposition(
            dependencies: ProductionAppDependencies(
                applicationSupportDirectoryURL: root,
                accountIdentity: .local,
                deviceID: "preload-sync-transition-device",
                sessionNonce: fixedUUID(15),
                newProfileID: fixedUUID(115),
                now: { Date(timeIntervalSince1970: 18_000) },
                makeRunID: { self.fixedRunID(15) },
                makeSeed: { 15 }
            )
        )

        XCTAssertNil(try composition.publishSyncStatusTransition(.syncing))
        XCTAssertNil(try composition.publishSyncStatusTransition(.syncing))

        let coordinator = AppCoordinator(environment: composition.environment)
        await coordinator.bootstrap()
        let bootstrap = try XCTUnwrap(coordinator.authoritativeSnapshot)

        XCTAssertEqual(bootstrap.syncRevision, 1)
        XCTAssertEqual(bootstrap.state.syncStatus, .syncing)
    }

    @MainActor
    func testRepositorySnapshotCannotSelectRuntimeSyncStatus() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let channel = ProductionAuthoritativeStateChannel()
        let composition = ProductionAppComposition(
            dependencies: ProductionAppDependencies(
                applicationSupportDirectoryURL: root,
                accountIdentity: .local,
                deviceID: "repository-sync-isolation-device",
                sessionNonce: fixedUUID(14),
                newProfileID: fixedUUID(114),
                now: { Date(timeIntervalSince1970: 17_000) },
                makeRunID: { self.fixedRunID(14) },
                makeSeed: { 14 }
            ),
            authoritativeStateChannel: channel
        )
        let initial = makeRepositorySnapshot(playerRevision: 4, economyRevision: 9)
        _ = try composition.accept(initial, publishUpdate: false)
        let syncing = try XCTUnwrap(
            composition.publishSyncStatusTransition(.syncing)
        )
        var iterator = channel.makeStream().makeAsyncIterator()
        let replayedSyncing = await iterator.next()
        XCTAssertEqual(replayedSyncing, syncing)

        let repositoryCandidate = replacing(
            initial,
            playerRevision: 5,
            syncStatus: .current
        )
        _ = try composition.accept(repositoryCandidate, publishUpdate: true)
        let nextPublished = await iterator.next()
        let published = try XCTUnwrap(nextPublished)

        XCTAssertEqual(published.playerRevision, 5)
        XCTAssertEqual(published.economyRevision, 9)
        XCTAssertEqual(published.syncRevision, syncing.syncRevision)
        XCTAssertEqual(published.state.syncStatus, .syncing)
    }

    @MainActor
    func testPlayerRevisionAdvanceCannotCarryEconomyPartitionMutation() throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let composition = makeAcceptanceComposition(root: root)
        let initial = makeRepositorySnapshot(playerRevision: 4, economyRevision: 9)
        _ = try composition.accept(initial, publishUpdate: false)

        let entryID = LedgerEntryID("partition-test/economy")
        let entry = CoinLedgerEntry(
            id: entryID,
            delta: 250,
            reason: .gameplay(runID: fixedRunID(880), economyVersion: 1),
            createdAt: Date(timeIntervalSince1970: 880)
        )
        let malformed = replacing(
            initial,
            playerRevision: 5,
            coinBalances: CoinBalanceSummary(confirmed: 250, pending: 0),
            ledger: [entryID: entry]
        )

        XCTAssertThrowsError(try composition.accept(malformed, publishUpdate: false)) {
            XCTAssertEqual(
                $0 as? ProductionAppCompositionError,
                .authoritativeRevisionCollision
            )
        }
        XCTAssertEqual(
            try composition.accept(initial, publishUpdate: false),
            initial
        )
    }

    @MainActor
    func testPlayerRevisionAdvanceCannotGrantInventoryWithoutEconomyRevision() throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let composition = makeAcceptanceComposition(root: root)
        let initial = makeRepositorySnapshot(playerRevision: 4, economyRevision: 9)
        _ = try composition.accept(initial, publishUpdate: false)
        var inventory = initial.player.inventory
        inventory.ownedTeamIDs.insert(LaunchTeamID.lumaCoastPrisms)
        let malformed = replacing(
            initial,
            playerRevision: 5,
            inventory: inventory
        )

        XCTAssertThrowsError(try composition.accept(malformed, publishUpdate: false)) {
            XCTAssertEqual(
                $0 as? ProductionAppCompositionError,
                .authoritativeRevisionCollision
            )
        }
    }

    @MainActor
    func testPlayerRevisionAdvanceCannotChangeRewardEligibilityWithoutEconomyRevision() throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let composition = makeAcceptanceComposition(root: root)
        let initial = makeRepositorySnapshot(playerRevision: 4, economyRevision: 9)
        _ = try composition.accept(initial, publishUpdate: false)
        var rewardedAdState = initial.player.rewardedAdState
        _ = rewardedAdState.recordValidRun(fixedRunID(881))
        let malformed = replacing(
            initial,
            playerRevision: 5,
            rewardedAdState: rewardedAdState
        )

        XCTAssertThrowsError(try composition.accept(malformed, publishUpdate: false)) {
            XCTAssertEqual(
                $0 as? ProductionAppCompositionError,
                .authoritativeRevisionCollision
            )
        }
    }

    @MainActor
    func testPlayerRevisionAdvanceCannotCarryRewardObservationWithoutEconomyRevision() throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let composition = makeAcceptanceComposition(root: root)
        let initial = makeRepositorySnapshot(playerRevision: 4, economyRevision: 9)
        _ = try composition.accept(initial, publishUpdate: false)
        let runID = fixedRunID(882)
        let malformed = replacing(
            initial,
            playerRevision: 5,
            rewardedRunObservations: [
                runID: RewardedRunObservation(
                    observedCycle: 3,
                    disposition: .candidate
                ),
            ]
        )

        XCTAssertThrowsError(try composition.accept(malformed, publishUpdate: false)) {
            XCTAssertEqual(
                $0 as? ProductionAppCompositionError,
                .authoritativeRevisionCollision
            )
        }
    }

    @MainActor
    func testEconomyRevisionAdvanceCannotCarryPlayerPartitionMutation() throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let composition = makeAcceptanceComposition(root: root)
        let initial = makeRepositorySnapshot(playerRevision: 4, economyRevision: 9)
        _ = try composition.accept(initial, publishUpdate: false)
        let malformed = replacing(
            initial,
            economyRevision: 10,
            settings: PlayerSettings(isMuted: true)
        )

        XCTAssertThrowsError(try composition.accept(malformed, publishUpdate: false)) {
            XCTAssertEqual(
                $0 as? ProductionAppCompositionError,
                .authoritativeRevisionCollision
            )
        }
        XCTAssertEqual(
            try composition.accept(initial, publishUpdate: false),
            initial
        )
    }

    @MainActor
    func testFailedProfileLoadDoesNotPublishPlaceholderAsReady() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let blocker = root.appendingPathComponent("not-a-directory")
        try Data([0x01]).write(to: blocker)
        let clock = TestClock(Date(timeIntervalSince1970: 20_000))
        let coordinator = AppCoordinator(
            environment: makeEnvironment(
                root: blocker,
                account: PlayerAccountIdentity("load-failure-account"),
                deviceID: "installation-device-b",
                sessionNonce: fixedUUID(3),
                newProfileID: fixedUUID(303),
                clock: clock
            )
        )

        await coordinator.bootstrap()

        guard case let .failed(message) = coordinator.bootstrapState else {
            return XCTFail("Expected the profile load to fail")
        }
        XCTAssertTrue(message.contains("could not be opened"))
        XCTAssertEqual(coordinator.navigationPath, [.mainMenu])
        XCTAssertEqual(coordinator.state, .launchDefault())
    }

    @MainActor
    func testNaturalRunSettlementReturnsAuthoritativeResultsAndIsIdempotent() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let clock = TestClock(Date(timeIntervalSince1970: 30_000))
        let environment = makeEnvironment(
            root: root,
            account: PlayerAccountIdentity("settlement-account"),
            deviceID: "installation-device-c",
            sessionNonce: fixedUUID(4),
            newProfileID: fixedUUID(404),
            clock: clock,
            runID: fixedRunID(44)
        )
        let coordinator = AppCoordinator(environment: environment)
        await coordinator.bootstrap()
        let configuration = try await launchConfiguration(from: coordinator)
        let run = makeNaturalRun(configuration: configuration)
        clock.date = run.endedAt.addingTimeInterval(1)

        await coordinator.handleCompletedRun(run)

        guard case let .runResults(firstResults) = coordinator.currentDestination else {
            return XCTFail("Expected persisted run results")
        }
        XCTAssertEqual(firstResults.completionCoins, 10)
        XCTAssertEqual(firstResults.performanceCoins, 12)
        XCTAssertEqual(firstResults.accuracyCoins, 5)
        XCTAssertEqual(firstResults.signingBonusCoins, 250)
        XCTAssertEqual(firstResults.totalEarnedCoins, 277)
        XCTAssertEqual(firstResults.pendingCoins, 277)
        XCTAssertEqual(firstResults.gameplayRewardState, .pending)
        XCTAssertEqual(firstResults.signingBonusState, .pending)
        XCTAssertEqual(firstResults.personalBest, run.score)
        XCTAssertTrue(firstResults.isNewPersonalBest)
        XCTAssertFalse(firstResults.achievementUpdates.isEmpty)
        XCTAssertTrue(
            firstResults.achievementUpdates.contains {
                $0.current.id == LaunchAchievementID.firstRead
                    && $0.current.isCompleted
            }
        )
        XCTAssertEqual(coordinator.state.confirmedCoins, 0)
        XCTAssertEqual(coordinator.state.pendingCoins, 277)

        let duplicate = try XCTUnwrap(environment.settleCompletedRun)
        let duplicateResult = await duplicate(run)
        guard case let .settled(duplicateSnapshot, duplicateResults?) = duplicateResult else {
            return XCTFail("Expected the duplicate callback to return its durable receipt")
        }

        XCTAssertEqual(duplicateSnapshot.state, coordinator.state)
        XCTAssertEqual(duplicateResults, firstResults)
        XCTAssertEqual(duplicateSnapshot.state.pendingCoins, 277)
        XCTAssertEqual(duplicateSnapshot.state.confirmedCoins, 0)
    }

    @MainActor
    func testRunResultsPendingStateIgnoresUnrelatedProfileCredits() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let account = PlayerAccountIdentity("results-pending-scope-account")
        let deviceID = "results-pending-scope-device"
        let date = Date(timeIntervalSince1970: 35_000)
        try seedPendingCoinProfile(
            root: root,
            account: account,
            deviceID: deviceID,
            profileID: fixedUUID(450),
            date: date
        )
        let clock = TestClock(date.addingTimeInterval(10))
        let coordinator = AppCoordinator(
            environment: makeEnvironment(
                root: root,
                account: account,
                deviceID: deviceID,
                sessionNonce: fixedUUID(451),
                newProfileID: fixedUUID(452),
                clock: clock,
                runID: fixedRunID(453)
            )
        )
        await coordinator.bootstrap()
        let configuration = try await launchConfiguration(from: coordinator)
        let run = makeNaturalRun(configuration: configuration)
        clock.date = run.endedAt.addingTimeInterval(1)

        await coordinator.handleCompletedRun(run)

        guard case let .runResults(results) = coordinator.currentDestination else {
            return XCTFail("Expected authoritative run results")
        }
        XCTAssertEqual(results.totalEarnedCoins, 277)
        XCTAssertEqual(results.pendingCoins, 277)
        XCTAssertEqual(results.gameplayRewardState, .pending)
        XCTAssertEqual(results.signingBonusState, .pending)
        XCTAssertEqual(coordinator.state.pendingCoins, 2_527)
    }

    @MainActor
    func testLaterSettlementDoesNotReExposeAccountSigningBonus() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let clock = TestClock(Date(timeIntervalSince1970: 35_500))
        var nextRunNumber = 470
        let composition = ProductionAppComposition(
            dependencies: ProductionAppDependencies(
                applicationSupportDirectoryURL: root,
                accountIdentity: .local,
                deviceID: "results-second-run-device",
                sessionNonce: fixedUUID(470),
                newProfileID: fixedUUID(471),
                now: { clock.date },
                makeRunID: {
                    defer { nextRunNumber += 1 }
                    return self.fixedRunID(nextRunNumber)
                },
                makeSeed: { UInt32(nextRunNumber) }
            )
        )
        let coordinator = AppCoordinator(environment: composition.environment)
        await coordinator.bootstrap()

        let firstConfiguration = try await launchConfiguration(from: coordinator)
        let firstRun = makeNaturalRun(configuration: firstConfiguration)
        clock.date = firstRun.endedAt.addingTimeInterval(1)
        await coordinator.handleCompletedRun(firstRun)
        guard case let .runResults(firstResults) = coordinator.currentDestination else {
            return XCTFail("Expected first run results")
        }
        XCTAssertEqual(firstResults.signingBonusCoins, 250)
        XCTAssertEqual(firstResults.signingBonusState, .pending)

        coordinator.replayAfterResults()
        guard case let .gameplay(secondConfiguration) = coordinator.currentDestination else {
            return XCTFail("Expected replay gameplay")
        }
        let secondRun = makeNaturalRun(configuration: secondConfiguration)
        clock.date = secondRun.endedAt.addingTimeInterval(1)
        await coordinator.handleCompletedRun(secondRun)
        guard case let .runResults(secondResults) = coordinator.currentDestination else {
            return XCTFail("Expected second run results")
        }

        XCTAssertEqual(secondResults.completionCoins, 10)
        XCTAssertEqual(secondResults.performanceCoins, 12)
        XCTAssertEqual(secondResults.accuracyCoins, 5)
        XCTAssertEqual(secondResults.signingBonusCoins, 0)
        XCTAssertEqual(secondResults.totalEarnedCoins, 27)
        XCTAssertEqual(secondResults.pendingCoins, 27)
        XCTAssertEqual(secondResults.gameplayRewardState, .pending)
        XCTAssertNil(secondResults.signingBonusState)
        XCTAssertEqual(coordinator.state.pendingCoins, 304)
    }

    @MainActor
    func testDuplicateSettlementReflectsExactRecordedLedgerStatesWithoutRecredit() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let account = PlayerAccountIdentity("results-recorded-account")
        let deviceID = "results-recorded-device"
        let sessionNonce = fixedUUID(480)
        let clock = TestClock(Date(timeIntervalSince1970: 36_500))
        let repository = LocalPlayerProfileRepository(
            directoryURL: ProductionAppComposition.profileDirectoryURL(
                applicationSupportDirectoryURL: root,
                accountIdentity: account
            ),
            deviceID: deviceID,
            accountIdentity: account,
            sessionNonce: sessionNonce,
            economyMutationPolicy: .allowLocalTesting
        )
        let composition = ProductionAppComposition(
            dependencies: ProductionAppDependencies(
                applicationSupportDirectoryURL: root,
                accountIdentity: account,
                deviceID: deviceID,
                sessionNonce: sessionNonce,
                newProfileID: fixedUUID(481),
                now: { clock.date },
                makeRunID: { self.fixedRunID(482) },
                makeSeed: { 482 }
            ),
            repository: repository
        )
        let environment = composition.environment
        let coordinator = AppCoordinator(environment: environment)
        await coordinator.bootstrap()
        let configuration = try await launchConfiguration(from: coordinator)
        let run = makeNaturalRun(configuration: configuration)
        clock.date = run.endedAt.addingTimeInterval(1)
        await coordinator.handleCompletedRun(run)
        guard case let .runResults(pendingResults) = coordinator.currentDestination else {
            return XCTFail("Expected pending first results")
        }
        XCTAssertEqual(pendingResults.pendingCoins, 277)

        let pendingSnapshot = try await repository.snapshot()
        let exactEntryIDs = Set(
            [
                CoinLedgerID.gameplay(runID: run.runID),
                CoinLedgerID.signingBonus(
                    version: PersistedEconomyRulesV1.signingBonusVersion
                ),
            ]
        )
        let exactEntries = Dictionary(
            uniqueKeysWithValues: try exactEntryIDs.map { entryID in
                (entryID, try XCTUnwrap(pendingSnapshot.ledger[entryID]))
            }
        )
        let confirmationDate = clock.date.addingTimeInterval(1)
        let confirmation = DurableEconomyConfirmation(
            confirmationID: OperationID("results-recorded-confirmation"),
            session: pendingSnapshot.session,
            entries: exactEntries,
            expectedEconomyRevision: pendingSnapshot.economyRevision,
            confirmedBalanceBefore: pendingSnapshot.coinBalances.confirmed,
            confirmedAt: confirmationDate,
            authority: .localTest
        )
        _ = try await repository.confirmPendingCredits(
            exactEntryIDs,
            session: pendingSnapshot.session,
            confirmation: confirmation,
            savedAt: confirmationDate
        )
        clock.date = confirmationDate.addingTimeInterval(1)

        let duplicate = try XCTUnwrap(environment.settleCompletedRun)
        let duplicateResult = await duplicate(run)
        guard case let .settled(snapshot, recordedResults?) = duplicateResult else {
            return XCTFail("Expected duplicate settlement to return recorded results")
        }

        XCTAssertEqual(recordedResults.completionCoins, pendingResults.completionCoins)
        XCTAssertEqual(recordedResults.performanceCoins, pendingResults.performanceCoins)
        XCTAssertEqual(recordedResults.accuracyCoins, pendingResults.accuracyCoins)
        XCTAssertEqual(recordedResults.signingBonusCoins, pendingResults.signingBonusCoins)
        XCTAssertEqual(recordedResults.totalEarnedCoins, pendingResults.totalEarnedCoins)
        XCTAssertEqual(recordedResults.pendingCoins, 0)
        XCTAssertEqual(recordedResults.gameplayRewardState, .recorded)
        XCTAssertEqual(recordedResults.signingBonusState, .recorded)
        XCTAssertEqual(snapshot.state.confirmedCoins, 277)
        XCTAssertEqual(snapshot.state.pendingCoins, 0)
    }

    @MainActor
    func testRunResultsCoinProjectionUsesOnlyReceiptLedgerEntries() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let clock = TestClock(Date(timeIntervalSince1970: 36_000))
        let coordinator = AppCoordinator(
            environment: makeEnvironment(
                root: root,
                account: .local,
                deviceID: "results-projection-device",
                sessionNonce: fixedUUID(460),
                newProfileID: fixedUUID(461),
                clock: clock,
                runID: fixedRunID(462)
            )
        )
        await coordinator.bootstrap()
        let configuration = try await launchConfiguration(from: coordinator)
        let run = makeNaturalRun(configuration: configuration)
        let recordedAt = run.endedAt.addingTimeInterval(1)
        let gameplayID = CoinLedgerID.gameplay(runID: run.runID)
        let signingID = CoinLedgerID.signingBonus(
            version: PersistedEconomyRulesV1.signingBonusVersion
        )
        let adTransactionID = AdProviderTransactionID("results-unrelated-ad")
        let adID = CoinLedgerID.rewardedAd(providerTransactionID: adTransactionID)
        let ledger = [
            gameplayID: CoinLedgerEntry(
                id: gameplayID,
                delta: 27,
                reason: .gameplay(runID: run.runID, economyVersion: 1),
                createdAt: recordedAt
            ),
            signingID: CoinLedgerEntry(
                id: signingID,
                delta: 250,
                reason: .signingBonus(version: 1),
                createdAt: PersistedEconomyRulesV1.signingBonusLedgerCreatedAt
            ),
            adID: CoinLedgerEntry(
                id: adID,
                delta: 100,
                reason: .rewardedAd(
                    offerID: RewardOfferID("results-unrelated-offer"),
                    providerTransactionID: adTransactionID
                ),
                createdAt: recordedAt
            ),
        ]
        let snapshot = replacing(
            makeRepositorySnapshot(playerRevision: 1, economyRevision: 1),
            coinBalances: CoinBalanceSummary(confirmed: 250, pending: 127),
            ledger: ledger,
            pendingLedgerEntryIDs: [gameplayID, adID]
        )
        let outcome = RunSettlementOutcome(
            record: CompletedRunRecord(
                run: run,
                recordedAt: recordedAt,
                rewardCoins: 27
            ),
            gameplayRewardEntryID: gameplayID,
            signingBonusEntryID: signingID,
            achievementUpdates: [],
            rewardedOfferUnlocked: nil,
            resultingPersonalBest: run.score
        )

        let projection = try RunResultsCoinProjection.make(
            settlement: RunSettlementResult(outcome: outcome, wasAlreadySettled: false),
            snapshot: snapshot
        )

        XCTAssertEqual(projection.completionCoins, 10)
        XCTAssertEqual(projection.performanceCoins, 12)
        XCTAssertEqual(projection.accuracyCoins, 5)
        XCTAssertEqual(projection.signingBonusCoins, 250)
        XCTAssertEqual(projection.totalEarnedCoins, 277)
        XCTAssertEqual(projection.pendingCoins, 27)
        XCTAssertEqual(projection.gameplayRewardState, .pending)
        XCTAssertEqual(projection.signingBonusState, .recorded)

        let laterOutcome = RunSettlementOutcome(
            record: outcome.record,
            gameplayRewardEntryID: gameplayID,
            signingBonusEntryID: nil,
            achievementUpdates: [],
            rewardedOfferUnlocked: nil,
            resultingPersonalBest: run.score
        )
        let laterProjection = try RunResultsCoinProjection.make(
            settlement: RunSettlementResult(
                outcome: laterOutcome,
                wasAlreadySettled: false
            ),
            snapshot: snapshot
        )
        XCTAssertEqual(laterProjection.signingBonusCoins, 0)
        XCTAssertNil(laterProjection.signingBonusState)
        XCTAssertEqual(laterProjection.totalEarnedCoins, 27)
        XCTAssertEqual(laterProjection.pendingCoins, 27)

        var invalidLedger = ledger
        invalidLedger[gameplayID] = CoinLedgerEntry(
            id: gameplayID,
            delta: 27,
            reason: .storeKit(transactionID: 99, packID: CoinPackID("pocket")),
            createdAt: recordedAt
        )
        let invalidSnapshot = replacing(
            snapshot,
            ledger: invalidLedger
        )
        XCTAssertThrowsError(
            try RunResultsCoinProjection.make(
                settlement: RunSettlementResult(
                    outcome: outcome,
                    wasAlreadySettled: false
                ),
                snapshot: invalidSnapshot
            )
        ) {
            XCTAssertEqual(
                $0 as? ProductionAppCompositionError,
                .authoritativeLedgerEntryInvalid
            )
        }
    }

    @MainActor
    func testAbandonedRunIsDurableButReturnsToMenuWithoutRewards() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let account = PlayerAccountIdentity("abandoned-account")
        let deviceID = "installation-device-d"
        let clock = TestClock(Date(timeIntervalSince1970: 40_000))
        let coordinator = AppCoordinator(
            environment: makeEnvironment(
                root: root,
                account: account,
                deviceID: deviceID,
                sessionNonce: fixedUUID(5),
                newProfileID: fixedUUID(505),
                clock: clock,
                runID: fixedRunID(55)
            )
        )
        await coordinator.bootstrap()
        let configuration = try await launchConfiguration(from: coordinator)
        let run = makeAbandonedRun(configuration: configuration)
        clock.date = run.endedAt.addingTimeInterval(1)

        await coordinator.handleCompletedRun(run)

        XCTAssertEqual(coordinator.currentDestination, .mainMenu)
        XCTAssertEqual(coordinator.state.confirmedCoins, 0)
        XCTAssertEqual(coordinator.state.pendingCoins, 0)
        XCTAssertEqual(coordinator.state.personalBest, 0)

        let inspectionRepository = LocalPlayerProfileRepository(
            directoryURL: ProductionAppComposition.profileDirectoryURL(
                applicationSupportDirectoryURL: root,
                accountIdentity: account
            ),
            deviceID: deviceID,
            accountIdentity: account,
            sessionNonce: fixedUUID(6),
            economyMutationPolicy: .requireDurablePrivateCloud
        )
        let restored = try await inspectionRepository.load(
            at: clock.date.addingTimeInterval(1),
            newProfileID: fixedUUID(606)
        )
        XCTAssertEqual(restored.completedRuns[run.runID]?.run, run)
        XCTAssertEqual(restored.coinBalances, CoinBalanceSummary(confirmed: 0, pending: 0))
        XCTAssertEqual(restored.player.career, CareerStatistics())
    }

    @MainActor
    func testPendingCreditsCannotUnlockOrBePresentedAsSpendable() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let account = PlayerAccountIdentity("pending-credit-account")
        let deviceID = "installation-device-e"
        let profileID = fixedUUID(707)
        let date = Date(timeIntervalSince1970: 50_000)
        try seedPendingCoinProfile(
            root: root,
            account: account,
            deviceID: deviceID,
            profileID: profileID,
            date: date
        )
        let clock = TestClock(date.addingTimeInterval(10))
        let coordinator = AppCoordinator(
            environment: makeEnvironment(
                root: root,
                account: account,
                deviceID: deviceID,
                sessionNonce: fixedUUID(7),
                newProfileID: fixedUUID(808),
                clock: clock
            )
        )
        await coordinator.bootstrap()
        XCTAssertEqual(coordinator.state.confirmedCoins, 0)
        XCTAssertEqual(coordinator.state.pendingCoins, 2_250)
        let before = coordinator.state
        let lockedTeamItem = try XCTUnwrap(
            coordinator.catalog.unlockableItems.first {
                $0.kind == .team(LaunchTeamID.lumaCoastPrisms)
            }
        )

        await coordinator.requestUnlock(lockedTeamItem.id)

        XCTAssertEqual(coordinator.state, before)
        XCTAssertFalse(
            coordinator.state.inventory.ownedTeamIDs.contains(LaunchTeamID.lumaCoastPrisms)
        )
        XCTAssertEqual(
            coordinator.noticeMessage,
            ProductionAccountRuntimeRouter.onlinePurchaseWarning
        )

        coordinator.dismissNotice()
        await coordinator.requestCoinPack(EconomyConfiguration.coinPacks[0].id)
        XCTAssertEqual(coordinator.state, before)
        XCTAssertEqual(
            coordinator.noticeMessage,
            ProductionAccountRuntimeRouter.onlinePurchaseWarning
        )

        coordinator.dismissNotice()
        await coordinator.requestRewardedAd(RewardOfferID("unsupported-test-offer"))
        XCTAssertEqual(coordinator.state, before)
        XCTAssertEqual(
            coordinator.noticeMessage,
            "Rewarded ads are not enabled in this build."
        )

        let relaunched = AppCoordinator(
            environment: makeEnvironment(
                root: root,
                account: account,
                deviceID: deviceID,
                sessionNonce: fixedUUID(8),
                newProfileID: fixedUUID(909),
                clock: clock
            )
        )
        await relaunched.bootstrap()
        XCTAssertEqual(relaunched.state, before)
    }

    @MainActor
    func testOfflineCommerceAttemptsLeaveCompleteRepositorySnapshotUnchanged() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let account = PlayerAccountIdentity("offline-commerce-profile")
        let deviceID = "offline-commerce-device"
        let sessionNonce = fixedUUID(910)
        let profileID = fixedUUID(911)
        let clock = TestClock(Date(timeIntervalSince1970: 91_000))
        let repository = LocalPlayerProfileRepository(
            directoryURL: ProductionAppComposition.profileDirectoryURL(
                applicationSupportDirectoryURL: root,
                accountIdentity: account
            ),
            deviceID: deviceID,
            accountIdentity: account,
            sessionNonce: sessionNonce,
            economyMutationPolicy: .requireDurablePrivateCloud
        )
        let commerce = CompositionCommerceCapture(
            result: .onlineRequired
        )
        let composition = ProductionAppComposition(
            dependencies: ProductionAppDependencies(
                applicationSupportDirectoryURL: root,
                accountIdentity: account,
                deviceID: deviceID,
                sessionNonce: sessionNonce,
                newProfileID: profileID,
                now: { clock.date },
                makeRunID: { self.fixedRunID(910) },
                makeSeed: { 910 }
            ),
            repository: repository,
            commerceRequestService: commerce
        )
        let coordinator = AppCoordinator(environment: composition.environment)
        await coordinator.bootstrap()
        let before = try await repository.snapshot()
        let lockedItem = try XCTUnwrap(
            coordinator.catalog.unlockableItems.first
        )
        let packID = EconomyConfiguration.coinPacks[0].id

        await coordinator.requestUnlock(lockedItem.id)
        XCTAssertEqual(
            coordinator.noticeMessage,
            ProductionAccountRuntimeRouter.onlinePurchaseWarning
        )
        coordinator.dismissNotice()
        await coordinator.requestCoinPack(packID)

        let after = try await repository.snapshot()
        let requests = await commerce.requests()
        XCTAssertEqual(after, before)
        XCTAssertEqual(
            coordinator.noticeMessage,
            ProductionAccountRuntimeRouter.onlinePurchaseWarning
        )
        XCTAssertEqual(
            requests,
            [.catalogUnlock(lockedItem.id), .coinPack(packID)]
        )
    }

    @MainActor
    func testSuccessfulCommerceRefreshesAuthoritativeStateFromRepository() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let account = PlayerAccountIdentity("successful-commerce-local-source")
        let deviceID = "successful-commerce-device"
        let sessionNonce = fixedUUID(920)
        let profileID = fixedUUID(921)
        let clock = TestClock(Date(timeIntervalSince1970: 92_000))
        let sourceRepository = LocalPlayerProfileRepository(
            directoryURL: ProductionAppComposition.profileDirectoryURL(
                applicationSupportDirectoryURL: root,
                accountIdentity: account
            ),
            deviceID: deviceID,
            accountIdentity: account,
            sessionNonce: sessionNonce,
            economyMutationPolicy: .requireDurablePrivateCloud
        )
        let repositoryRouter = ProductionProfileRepositoryRouter(
            route: ProductionProfileRepositoryRoute(
                repository: sourceRepository,
                authority: .local(
                    accountIdentity: account,
                    sessionNonce: sessionNonce
                )
            )
        )
        let cloudAccountID = CloudAccountID("successful-commerce-cloud-account")
        let bindings = CloudAccountDerivedBindings.derive(from: cloudAccountID)
        let targetRepository = LocalPlayerProfileRepository(
            directoryURL: ProductionAppComposition.profileDirectoryURL(
                applicationSupportDirectoryURL: root,
                accountIdentity: bindings.playerAccountIdentity
            ),
            deviceID: deviceID,
            accountIdentity: bindings.playerAccountIdentity,
            sessionNonce: fixedUUID(922),
            economyMutationPolicy: .requireDurablePrivateCloud
        )
        let targetSnapshot = try await targetRepository.load(
            at: clock.date,
            newProfileID: bindings.durableAccountBinding.profileID
        )
        let claim = try await ProductionVerifiedAccountClaim(
            cloudAccountID: cloudAccountID,
            derivedBindings: bindings,
            installedRepository: targetRepository
        )
        let wrongRepository = LocalPlayerProfileRepository(
            directoryURL: root.appendingPathComponent(
                "wrong-cloud-repository",
                isDirectory: true
            ),
            deviceID: deviceID,
            accountIdentity: bindings.playerAccountIdentity,
            sessionNonce: targetSnapshot.session.nonce,
            economyMutationPolicy: .requireDurablePrivateCloud
        )
        do {
            try await repositoryRouter.adoptVerifiedPrivateCloud(
                repository: wrongRepository,
                claim: claim
            )
            XCTFail("A reconstructed repository must not satisfy the claim")
        } catch {
            // Expected: only the exact installed repository instance is valid.
        }
        let routeAfterRejectedAdoption = try await repositoryRouter.currentRoute()
        XCTAssertTrue(routeAfterRejectedAdoption.repository === sourceRepository)
        let commerce = CompositionRepositoryMutatingCommerce(
            sourceRepository: sourceRepository,
            targetRepository: targetRepository,
            repositoryRouter: repositoryRouter,
            verifiedClaim: claim,
            mutationDate: clock.date.addingTimeInterval(1)
        )
        let composition = ProductionAppComposition(
            dependencies: ProductionAppDependencies(
                applicationSupportDirectoryURL: root,
                accountIdentity: account,
                deviceID: deviceID,
                sessionNonce: sessionNonce,
                newProfileID: profileID,
                now: { clock.date },
                makeRunID: { self.fixedRunID(920) },
                makeSeed: { 920 }
            ),
            repository: sourceRepository,
            repositoryRouter: repositoryRouter,
            commerceRequestService: commerce
        )
        let coordinator = AppCoordinator(environment: composition.environment)
        await coordinator.bootstrap()
        let before = try XCTUnwrap(coordinator.authoritativeSnapshot)
        XCTAssertFalse(before.state.settings.isMuted)

        let packID = EconomyConfiguration.coinPacks[0].id
        await coordinator.requestCoinPack(packID)

        let after = try XCTUnwrap(coordinator.authoritativeSnapshot)
        let storedAfterCommerce = try await targetRepository.snapshot()
        XCTAssertNil(coordinator.noticeMessage)
        XCTAssertTrue(after.state.settings.isMuted)
        XCTAssertTrue(storedAfterCommerce.player.settings.isMuted)
        XCTAssertNotEqual(after.session, before.session)
        XCTAssertEqual(after.session, targetSnapshot.session)
        let requests = await commerce.requests()
        XCTAssertEqual(requests, [.coinPack(packID)])

        clock.advance(by: 2)
        await coordinator.setMusicVolume(0.27)

        let storedAfterSettings = try await targetRepository.snapshot()
        XCTAssertEqual(storedAfterSettings.player.settings.musicVolume, 0.27)
        XCTAssertEqual(coordinator.state.settings.musicVolume, 0.27)
        do {
            _ = try await sourceRepository.snapshot()
            XCTFail("The invalidated local source must never become active again")
        } catch {
            // Expected: commerce adoption invalidated the preserved source.
        }
    }

    @MainActor
    func testCommerceFailureClassificationUsesBoundedExistingAlertPresentation() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let clock = TestClock(Date(timeIntervalSince1970: 93_000))
        let commerce = CompositionCommerceCapture(result: .rejected)
        let coordinator = AppCoordinator(
            environment: ProductionAppComposition(
                dependencies: ProductionAppDependencies(
                    applicationSupportDirectoryURL: root,
                    accountIdentity: .local,
                    deviceID: "commerce-classification-device",
                    sessionNonce: fixedUUID(930),
                    newProfileID: fixedUUID(931),
                    now: { clock.date },
                    makeRunID: { self.fixedRunID(930) },
                    makeSeed: { 930 }
                ),
                commerceRequestService: commerce
            ).environment
        )
        await coordinator.bootstrap()
        let before = coordinator.authoritativeSnapshot
        let packID = EconomyConfiguration.coinPacks[0].id

        await coordinator.requestCoinPack(packID)

        XCTAssertEqual(
            coordinator.noticeMessage,
            "The purchase could not be completed. No changes were made."
        )
        XCTAssertEqual(coordinator.authoritativeSnapshot, before)

        coordinator.dismissNotice()
        await commerce.setResult(.silentlyCompleted)
        await coordinator.requestCoinPack(packID)

        XCTAssertNil(coordinator.noticeMessage)
        XCTAssertEqual(coordinator.authoritativeSnapshot, before)
    }

    @MainActor
    private func makeEnvironment(
        root: URL,
        account: PlayerAccountIdentity,
        deviceID: String,
        sessionNonce: UUID,
        newProfileID: UUID,
        clock: TestClock,
        runID: RunID? = nil
    ) -> AppCoordinatorEnvironment {
        let resolvedRunID = runID ?? fixedRunID(1)
        return ProductionAppComposition(
            dependencies: ProductionAppDependencies(
                applicationSupportDirectoryURL: root,
                accountIdentity: account,
                deviceID: deviceID,
                sessionNonce: sessionNonce,
                newProfileID: newProfileID,
                now: { clock.date },
                makeRunID: { resolvedRunID },
                makeSeed: { 91 }
            )
        ).environment
    }

    @MainActor
    private func makeAcceptanceComposition(root: URL) -> ProductionAppComposition {
        ProductionAppComposition(
            dependencies: ProductionAppDependencies(
                applicationSupportDirectoryURL: root,
                accountIdentity: .local,
                deviceID: "partition-test-device",
                sessionNonce: fixedUUID(870),
                newProfileID: fixedUUID(871),
                now: { Date(timeIntervalSince1970: 870) },
                makeRunID: { self.fixedRunID(870) },
                makeSeed: { 870 }
            )
        )
    }

    private func makeRepositorySnapshot(
        playerRevision: UInt64,
        economyRevision: UInt64
    ) -> LocalPlayerProfileSnapshot {
        let state = AppCoordinatorState.launchDefault()
        let profileID = fixedUUID(872)
        return LocalPlayerProfileSnapshot(
            session: ProfileSessionToken(
                accountIdentity: .local,
                nonce: fixedUUID(873),
                profileID: profileID
            ),
            player: PlayerSnapshot(
                profileID: profileID,
                revision: playerRevision,
                settings: state.settings,
                selection: state.selection,
                inventory: state.inventory,
                career: CareerStatistics(),
                coinBalance: 0,
                achievementProgress: state.achievementProgress,
                rewardedAdState: state.rewardedAdState,
                syncStatus: state.syncStatus
            ),
            economyRevision: economyRevision,
            coinBalances: CoinBalanceSummary(confirmed: 0, pending: 0),
            completedRuns: [:],
            ledger: [:],
            pendingLedgerEntryIDs: []
        )
    }

    private func replacing(
        _ snapshot: LocalPlayerProfileSnapshot,
        playerRevision: UInt64? = nil,
        economyRevision: UInt64? = nil,
        settings: PlayerSettings? = nil,
        inventory: PlayerInventory? = nil,
        rewardedAdState: RewardedAdState? = nil,
        syncStatus: ProfileSyncStatus? = nil,
        coinBalances: CoinBalanceSummary? = nil,
        ledger: [LedgerEntryID: CoinLedgerEntry]? = nil,
        pendingLedgerEntryIDs: Set<LedgerEntryID>? = nil,
        rewardedRunObservations: [RunID: RewardedRunObservation]? = nil
    ) -> LocalPlayerProfileSnapshot {
        let resolvedBalances = coinBalances ?? snapshot.coinBalances
        return LocalPlayerProfileSnapshot(
            session: snapshot.session,
            player: PlayerSnapshot(
                profileID: snapshot.player.profileID,
                revision: playerRevision ?? snapshot.player.revision,
                settings: settings ?? snapshot.player.settings,
                selection: snapshot.player.selection,
                inventory: inventory ?? snapshot.player.inventory,
                career: snapshot.player.career,
                coinBalance: resolvedBalances.total,
                achievementProgress: snapshot.player.achievementProgress,
                rewardedAdState: rewardedAdState ?? snapshot.player.rewardedAdState,
                syncStatus: syncStatus ?? snapshot.player.syncStatus
            ),
            economyRevision: economyRevision ?? snapshot.economyRevision,
            coinBalances: resolvedBalances,
            completedRuns: snapshot.completedRuns,
            ledger: ledger ?? snapshot.ledger,
            pendingLedgerEntryIDs:
                pendingLedgerEntryIDs ?? snapshot.pendingLedgerEntryIDs,
            rewardedRunObservations:
                rewardedRunObservations ?? snapshot.rewardedRunObservations
        )
    }

    @MainActor
    private func launchConfiguration(
        from coordinator: AppCoordinator
    ) async throws -> RunConfiguration {
        XCTAssertTrue(coordinator.startRun())
        if case .tutorial(.beforeRun) = coordinator.currentDestination {
            await coordinator.completeTutorial()
        }
        guard case let .gameplay(configuration) = coordinator.currentDestination else {
            throw TestFailure.expectedGameplay
        }
        return configuration
    }

    private func makeNaturalRun(configuration: RunConfiguration) -> CompletedRun {
        CompletedRun(
            configuration: configuration,
            endedAt: configuration.startedAt.addingTimeInterval(60),
            elapsedGameplayMilliseconds: 60_000,
            finishReason: .timerExpired,
            score: 12_000,
            statistics: RunStatisticsSnapshot(
                attempts: 10,
                completions: 6,
                touchdowns: 2,
                incompletions: 1,
                interceptions: 1,
                longestTouchdownStreak: 2
            ),
            completedLaneIDs: [.short, .touchdown],
            bonusTouchdownCount: 1
        )
    }

    private func makeAbandonedRun(configuration: RunConfiguration) -> CompletedRun {
        CompletedRun(
            configuration: configuration,
            endedAt: configuration.startedAt.addingTimeInterval(12),
            elapsedGameplayMilliseconds: 12_000,
            finishReason: .abandoned,
            score: 1_000,
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

    @MainActor
    private func seedPendingCoinProfile(
        root: URL,
        account: PlayerAccountIdentity,
        deviceID: String,
        profileID: UUID,
        date: Date
    ) throws {
        var document = PlayerProfileFactory.makeDefault(
            profileID: profileID,
            accountIdentity: account,
            deviceID: deviceID,
            createdAt: date
        )
        let packID = CoinPackID("pocket")
        for transactionID in UInt64(1) ... UInt64(3) {
            let entryID = CoinLedgerID.storeKit(transactionID: transactionID)
            document.player.ledger[entryID] = CoinLedgerEntry(
                id: entryID,
                delta: 750,
                reason: .storeKit(transactionID: transactionID, packID: packID),
                createdAt: date
            )
            document.pendingLedgerEntryIDs.insert(entryID)
        }
        document.player.revision = 3
        document.economyRevision = 3

        let store = AtomicProfileFileStore(
            directoryURL: ProductionAppComposition.profileDirectoryURL(
                applicationSupportDirectoryURL: root,
                accountIdentity: account
            )
        )
        try store.save(document, at: date, catalog: .approved)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "PocketVector-ProductionComposition-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        return url
    }

    private func removeTemporaryDirectory(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func fixedUUID(_ value: Int) -> UUID {
        UUID(
            uuidString: String(
                format: "00000000-0000-0000-0000-%012d",
                value
            )
        )!
    }

    private func fixedRunID(_ value: Int) -> RunID {
        RunID(fixedUUID(value))
    }

    private enum TestFailure: Error {
        case expectedGameplay
    }
}

private actor CompositionCommerceCapture: ProductionCommerceRequestServicing {
    private var result: ProductionCommerceRequestResult
    private var recordedRequests: [ProductionCommerceRequest] = []

    init(result: ProductionCommerceRequestResult) {
        self.result = result
    }

    func perform(
        _ request: ProductionCommerceRequest
    ) -> ProductionCommerceRequestResult {
        recordedRequests.append(request)
        return result
    }

    func requests() -> [ProductionCommerceRequest] {
        recordedRequests
    }

    func setResult(_ result: ProductionCommerceRequestResult) {
        self.result = result
    }
}

private actor CompositionRepositoryMutatingCommerce:
    ProductionCommerceRequestServicing {
    private let sourceRepository: LocalPlayerProfileRepository
    private let targetRepository: LocalPlayerProfileRepository
    private let repositoryRouter: ProductionProfileRepositoryRouter
    private let verifiedClaim: ProductionVerifiedAccountClaim
    private let mutationDate: Date
    private var recordedRequests: [ProductionCommerceRequest] = []

    init(
        sourceRepository: LocalPlayerProfileRepository,
        targetRepository: LocalPlayerProfileRepository,
        repositoryRouter: ProductionProfileRepositoryRouter,
        verifiedClaim: ProductionVerifiedAccountClaim,
        mutationDate: Date
    ) {
        self.sourceRepository = sourceRepository
        self.targetRepository = targetRepository
        self.repositoryRouter = repositoryRouter
        self.verifiedClaim = verifiedClaim
        self.mutationDate = mutationDate
    }

    func perform(
        _ request: ProductionCommerceRequest
    ) async -> ProductionCommerceRequestResult {
        recordedRequests.append(request)
        do {
            await sourceRepository.invalidateForAccountSwitch()
            try await repositoryRouter.adoptVerifiedPrivateCloud(
                repository: targetRepository,
                claim: verifiedClaim
            )
            let snapshot = try await targetRepository.snapshot()
            var settings = snapshot.player.settings
            settings.isMuted = true
            _ = try await targetRepository.updateSettings(
                settings,
                session: snapshot.session,
                at: mutationDate
            )
            return .succeeded
        } catch {
            return .rejected
        }
    }

    func requests() -> [ProductionCommerceRequest] {
        recordedRequests
    }
}

@MainActor
private final class TestClock {
    var date: Date

    init(_ date: Date) {
        self.date = date
    }

    func advance(by interval: TimeInterval) {
        date = date.addingTimeInterval(interval)
    }
}

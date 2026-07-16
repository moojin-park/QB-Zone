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
        XCTAssertEqual(firstResults.earnedCoins, 277)
        XCTAssertEqual(firstResults.pendingCoins, 277)
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
        guard case let .settled(duplicateState, duplicateResults?) = duplicateResult else {
            return XCTFail("Expected the duplicate callback to return its durable receipt")
        }

        XCTAssertEqual(duplicateState, coordinator.state)
        XCTAssertEqual(duplicateResults, firstResults)
        XCTAssertEqual(duplicateState.pendingCoins, 277)
        XCTAssertEqual(duplicateState.confirmedCoins, 0)
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
        XCTAssertEqual(coordinator.state.pendingCoins, 1_500)
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
        XCTAssertTrue(coordinator.noticeMessage?.contains("No coins were spent") == true)

        coordinator.dismissNotice()
        await coordinator.requestCoinPack(EconomyConfiguration.coinPacks[0].id)
        XCTAssertEqual(coordinator.state, before)
        XCTAssertEqual(
            coordinator.noticeMessage,
            "Purchases are not enabled in this build."
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
                delta: 500,
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

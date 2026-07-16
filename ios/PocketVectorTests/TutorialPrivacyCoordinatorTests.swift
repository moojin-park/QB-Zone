import Foundation
import XCTest

@testable import PocketVector

final class TutorialPrivacyCoordinatorTests: XCTestCase {
    @MainActor
    func testFirstRunPersistsTutorialCompletionBeforeLaunchingIntendedRun() async throws {
        var sequence: [String] = []
        var authoritativeState = AppCoordinatorState.launchDefault()
        let configuration = makePrivacyConfiguration()
        let coordinator = AppCoordinator(
            state: authoritativeState,
            environment: AppCoordinatorEnvironment(
                loadInitialState: {
                    .loaded(self.authoritativeSnapshot(authoritativeState))
                },
                makeRunID: {
                    sequence.append("make-run")
                    return RunID(
                        UUID(uuidString: "00000000-0000-0000-0000-000000000801")!
                    )
                },
                makeSeed: { 801 },
                now: { Date(timeIntervalSince1970: 8_010) },
                performExternalRequest: { request in
                    guard case let .updateSettings(settings) = request else {
                        return .completed
                    }
                    sequence.append("persist-tutorial")
                    authoritativeState.settings = settings
                    return .applied(
                        self.authoritativeSnapshot(authoritativeState, playerRevision: 1)
                    )
                },
                observeLifecycleEvent: { event in
                    guard case .didLaunchRun = event else { return }
                    sequence.append("launch-run")
                },
                privacySupportConfiguration: configuration
            )
        )
        await coordinator.bootstrap()
        coordinator.showTeamSelection()

        XCTAssertTrue(coordinator.startRun())
        guard case let .tutorial(.beforeRun(intent)) = coordinator.currentDestination else {
            return XCTFail("The first run must stop at the tutorial")
        }
        XCTAssertEqual(intent.selection.selectedTeamID, LaunchTeamID.novaCityComets)
        XCTAssertFalse(coordinator.state.settings.tutorialCompleted)
        XCTAssertTrue(sequence.isEmpty, "A tutorial screen is not a launched run")

        await coordinator.completeTutorial()

        XCTAssertEqual(sequence, ["persist-tutorial", "make-run", "launch-run"])
        XCTAssertTrue(coordinator.state.settings.tutorialCompleted)
        guard case let .gameplay(runConfiguration) = coordinator.currentDestination else {
            return XCTFail("Expected gameplay only after the durable settings response")
        }
        XCTAssertEqual(runConfiguration.offenseTeamID, intent.selection.selectedTeamID)
        XCTAssertEqual(runConfiguration.offenseJerseyID, intent.selection.selectedJerseyID)
        XCTAssertEqual(runConfiguration.footballID, intent.selection.selectedFootballID)
        XCTAssertEqual(
            coordinator.navigationPath,
            [.mainMenu, .teamSelection, .gameplay(runConfiguration)]
        )
    }

    @MainActor
    func testTutorialCompletionRevalidatesEntitlementsAfterAuthoritativeWrite() async {
        var authoritativeState = AppCoordinatorState.launchDefault()
        var runIDRequests = 0
        var lifecycleEvents: [AppLifecycleEvent] = []
        let coordinator = AppCoordinator(
            state: authoritativeState,
            environment: AppCoordinatorEnvironment(
                loadInitialState: {
                    .loaded(self.authoritativeSnapshot(authoritativeState))
                },
                makeRunID: {
                    runIDRequests += 1
                    return RunID()
                },
                makeSeed: { 803 },
                now: { Date(timeIntervalSince1970: 8_030) },
                performExternalRequest: { request in
                    guard case let .updateSettings(settings) = request else {
                        return .completed
                    }
                    authoritativeState.settings = settings
                    if let selectedJerseyID = authoritativeState.selection.selectedJerseyID {
                        authoritativeState.inventory.ownedJerseyIDs.remove(selectedJerseyID)
                    }
                    return .applied(
                        self.authoritativeSnapshot(
                            authoritativeState,
                            playerRevision: 1,
                            economyRevision: 1
                        )
                    )
                },
                observeLifecycleEvent: { lifecycleEvents.append($0) },
                privacySupportConfiguration: makePrivacyConfiguration()
            )
        )
        await coordinator.bootstrap()
        coordinator.showTeamSelection()
        XCTAssertTrue(coordinator.startRun())

        await coordinator.completeTutorial()

        guard case .tutorial(.beforeRun) = coordinator.currentDestination else {
            return XCTFail("Revoked post-write ownership must keep gameplay blocked")
        }
        XCTAssertTrue(coordinator.state.settings.tutorialCompleted)
        XCTAssertEqual(runIDRequests, 0)
        XCTAssertTrue(lifecycleEvents.isEmpty)
        XCTAssertEqual(
            coordinator.noticeMessage,
            "Your selected team or equipment changed while the tutorial was open. Review your locker before starting a run."
        )
    }

    @MainActor
    func testCancellingPreRunTutorialDoesNotPersistOrLaunch() async {
        var requests: [AppExternalRequest] = []
        var lifecycleEvents: [AppLifecycleEvent] = []
        let coordinator = AppCoordinator(
            environment: makeEnvironment(
                requestHandler: { request in
                    requests.append(request)
                    return .completed
                },
                observeLifecycleEvent: { lifecycleEvents.append($0) }
            )
        )
        await coordinator.bootstrap()
        coordinator.showTeamSelection()

        XCTAssertTrue(coordinator.startRun())
        coordinator.cancelTutorial()

        XCTAssertEqual(coordinator.currentDestination, .teamSelection)
        XCTAssertFalse(coordinator.state.settings.tutorialCompleted)
        XCTAssertTrue(requests.isEmpty)
        XCTAssertTrue(lifecycleEvents.isEmpty)
    }

    @MainActor
    func testFailedTutorialPersistenceKeepsRunBlockedAndRetryable() async {
        var lifecycleEvents: [AppLifecycleEvent] = []
        let coordinator = AppCoordinator(
            environment: makeEnvironment(
                requestHandler: { request in
                    guard case .updateSettings = request else { return .completed }
                    return .failed(message: "Tutorial progress could not be saved.")
                },
                observeLifecycleEvent: { lifecycleEvents.append($0) }
            )
        )
        await coordinator.bootstrap()
        coordinator.showTeamSelection()
        XCTAssertTrue(coordinator.startRun())

        await coordinator.completeTutorial()

        guard case .tutorial(.beforeRun) = coordinator.currentDestination else {
            return XCTFail("A failed write must not enter gameplay")
        }
        XCTAssertFalse(coordinator.state.settings.tutorialCompleted)
        XCTAssertTrue(lifecycleEvents.isEmpty)
        XCTAssertEqual(coordinator.noticeMessage, "Tutorial progress could not be saved.")
    }

    @MainActor
    func testSettingsCanReplayAndCancelTutorialWithoutChangingCompletion() async {
        var initialState = AppCoordinatorState.launchDefault()
        initialState.settings.tutorialCompleted = true
        var requests: [AppExternalRequest] = []
        let coordinator = AppCoordinator(
            state: initialState,
            environment: makeEnvironment(
                initialState: initialState,
                requestHandler: { request in
                    requests.append(request)
                    return .completed
                }
            )
        )
        await coordinator.bootstrap()
        coordinator.showSettings()

        coordinator.showTutorialReview()
        XCTAssertEqual(coordinator.currentDestination, .tutorial(.review))
        coordinator.cancelTutorial()
        XCTAssertEqual(coordinator.currentDestination, .settings)
        XCTAssertTrue(coordinator.state.settings.tutorialCompleted)

        coordinator.showTutorialReview()
        await coordinator.completeTutorial()
        XCTAssertEqual(coordinator.currentDestination, .settings)
        XCTAssertTrue(coordinator.state.settings.tutorialCompleted)
        XCTAssertTrue(requests.isEmpty, "Reviewing a completed tutorial does not rewrite settings")
    }

    @MainActor
    func testSettingsReviewDoesNotCompleteFirstRunTutorial() async {
        var requests: [AppExternalRequest] = []
        let coordinator = AppCoordinator(
            environment: makeEnvironment(requestHandler: { request in
                requests.append(request)
                return .completed
            })
        )
        await coordinator.bootstrap()
        coordinator.showSettings()
        coordinator.showTutorialReview()

        await coordinator.completeTutorial()

        XCTAssertEqual(coordinator.currentDestination, .settings)
        XCTAssertFalse(coordinator.state.settings.tutorialCompleted)
        XCTAssertTrue(
            requests.isEmpty,
            "Review is informational and must not bypass first-run onboarding"
        )
    }

    @MainActor
    func testTutorialCompletionIgnoresDuplicateTapWhilePersistenceIsInFlight() async throws {
        var requestCount = 0
        var requestedSettings: PlayerSettings?
        var continuation: CheckedContinuation<AppExternalRequestResult, Never>?
        var lifecycleEvents: [AppLifecycleEvent] = []
        var authoritativeState = AppCoordinatorState.launchDefault()
        let coordinator = AppCoordinator(
            environment: makeEnvironment(
                requestHandler: { request in
                    guard case let .updateSettings(settings) = request else {
                        return .completed
                    }
                    requestCount += 1
                    requestedSettings = settings
                    return await withCheckedContinuation { continuation = $0 }
                },
                observeLifecycleEvent: { lifecycleEvents.append($0) }
            )
        )
        await coordinator.bootstrap()
        coordinator.showTeamSelection()
        XCTAssertTrue(coordinator.startRun())

        let firstCompletion = Task { @MainActor in
            await coordinator.completeTutorial()
        }
        while coordinator.pendingRequest == nil {
            await Task.yield()
        }

        await coordinator.completeTutorial()

        XCTAssertEqual(requestCount, 1)
        if case .tutorial(.beforeRun) = coordinator.currentDestination {
            // Expected: the first completion owns the durable write.
        } else {
            XCTFail("Gameplay must remain blocked while the write is pending")
        }

        authoritativeState.settings = try XCTUnwrap(requestedSettings)
        continuation?.resume(
            returning: .applied(
                self.authoritativeSnapshot(authoritativeState, playerRevision: 1)
            )
        )
        await firstCompletion.value

        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(lifecycleEvents.count, 1)
        guard case .gameplay = coordinator.currentDestination else {
            return XCTFail("The single completed write should launch one run")
        }
    }

    @MainActor
    func testPrivacySupportNavigationUsesInjectedFailClosedConfiguration() async {
        let configuration = PrivacySupportConfiguration(
            privacyPolicyURLString: nil,
            supportURLString: nil,
            supportEmail: nil,
            appInformation: AppReleaseInformation(
                appName: "Pocket Vector",
                version: "1.0",
                build: "12"
            )
        )
        let coordinator = AppCoordinator(
            environment: makeEnvironment(privacySupportConfiguration: configuration)
        )
        await coordinator.bootstrap()

        coordinator.showPrivacySupport()

        XCTAssertEqual(coordinator.currentDestination, .privacySupport)
        XCTAssertEqual(coordinator.privacySupportConfiguration, configuration)
        XCTAssertFalse(
            coordinator.privacySupportConfiguration.isReleaseContactConfigurationComplete
        )
        XCTAssertEqual(
            coordinator.privacySupportConfiguration.issues,
            [.privacyPolicyURLMissing, .supportURLMissing, .supportEmailMissing]
        )
    }

    func testPrivacySupportConfigurationAcceptsOnlyValidatedDestinations() throws {
        let configuration = PrivacySupportConfiguration(
            privacyPolicyURLString: " https://legal.pocket-vector.test/privacy ",
            supportURLString: "https://support.pocket-vector.test/help",
            supportEmail: " support+ios@pocket-vector.test ",
            appInformation: AppReleaseInformation(
                appName: "Pocket Vector",
                version: "1.0",
                build: "12"
            )
        )

        XCTAssertTrue(configuration.isReleaseContactConfigurationComplete)
        XCTAssertEqual(
            configuration.privacyPolicyURL?.absoluteString,
            "https://legal.pocket-vector.test/privacy"
        )
        XCTAssertEqual(configuration.supportEmail, "support+ios@pocket-vector.test")
        let emailURL = try XCTUnwrap(configuration.supportEmailURL)
        XCTAssertEqual(emailURL.scheme, "mailto")
        XCTAssertTrue(emailURL.absoluteString.contains("support+ios@pocket-vector.test"))
        XCTAssertTrue(emailURL.absoluteString.contains("Pocket%20Vector%20Support"))
    }

    func testPrivacySupportConfigurationRejectsUnsafeOrMalformedValues() {
        let configuration = PrivacySupportConfiguration(
            privacyPolicyURLString: "http://pocket-vector.test/privacy",
            supportURLString: "https://localhost/help",
            supportEmail: "support at pocket-vector.test",
            appInformation: AppReleaseInformation(
                appName: "Pocket Vector",
                version: nil,
                build: nil
            )
        )

        XCTAssertNil(configuration.privacyPolicyURL)
        XCTAssertNil(configuration.supportURL)
        XCTAssertNil(configuration.supportEmail)
        XCTAssertNil(configuration.supportEmailURL)
        XCTAssertEqual(
            configuration.issues,
            [.privacyPolicyURLInvalid, .supportURLInvalid, .supportEmailInvalid]
        )
        XCTAssertEqual(
            configuration.appInformation.versionAndBuildText,
            "Version and build unavailable"
        )
    }

    @MainActor
    private func makeEnvironment(
        initialState: AppCoordinatorState = .launchDefault(),
        privacySupportConfiguration: PrivacySupportConfiguration? = nil,
        requestHandler: @escaping @MainActor (AppExternalRequest) async -> AppExternalRequestResult = { _ in
            .completed
        },
        observeLifecycleEvent: (@MainActor (AppLifecycleEvent) -> Void)? = nil
    ) -> AppCoordinatorEnvironment {
        AppCoordinatorEnvironment(
            loadInitialState: {
                .loaded(self.authoritativeSnapshot(initialState))
            },
            makeRunID: {
                RunID(UUID(uuidString: "00000000-0000-0000-0000-000000000802")!)
            },
            makeSeed: { 802 },
            now: { Date(timeIntervalSince1970: 8_020) },
            performExternalRequest: requestHandler,
            observeLifecycleEvent: observeLifecycleEvent,
            privacySupportConfiguration: privacySupportConfiguration
                ?? makePrivacyConfiguration()
        )
    }

    @MainActor
    private func authoritativeSnapshot(
        _ state: AppCoordinatorState,
        playerRevision: UInt64 = 0,
        economyRevision: UInt64 = 0
    ) -> AuthoritativeAppStateSnapshot {
        AuthoritativeAppStateSnapshot(
            session: ProfileSessionToken(
                accountIdentity: .local,
                nonce: UUID(uuidString: "00000000-0000-0000-0000-000000000801")!,
                profileID: UUID(uuidString: "00000000-0000-0000-0000-000000000802")!
            ),
            playerRevision: playerRevision,
            economyRevision: economyRevision,
            state: state
        )
    }

    private func makePrivacyConfiguration() -> PrivacySupportConfiguration {
        PrivacySupportConfiguration(
            privacyPolicyURLString: "https://legal.pocket-vector.test/privacy",
            supportURLString: "https://support.pocket-vector.test/help",
            supportEmail: "support@pocket-vector.test",
            appInformation: AppReleaseInformation(
                appName: "Pocket Vector",
                version: "1.0",
                build: "12"
            )
        )
    }
}

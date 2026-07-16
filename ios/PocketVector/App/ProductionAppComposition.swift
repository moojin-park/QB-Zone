import CryptoKit
import Foundation

/// Dependencies whose values must remain stable for the lifetime of one app
/// process. Tests inject every value; the release factory obtains only
/// app-scoped, local values and never logs or displays them.
@MainActor
struct ProductionAppDependencies {
    let applicationSupportDirectoryURL: URL
    let accountIdentity: PlayerAccountIdentity
    let deviceID: String
    let sessionNonce: UUID
    let newProfileID: UUID
    let catalog: LaunchCatalog
    let now: @MainActor @Sendable () -> Date
    let makeRunID: @MainActor @Sendable () -> RunID
    let makeSeed: @MainActor @Sendable () -> UInt32

    init(
        applicationSupportDirectoryURL: URL,
        accountIdentity: PlayerAccountIdentity,
        deviceID: String,
        sessionNonce: UUID = UUID(),
        newProfileID: UUID = UUID(),
        catalog: LaunchCatalog = .approved,
        now: @escaping @MainActor @Sendable () -> Date = Date.init,
        makeRunID: @escaping @MainActor @Sendable () -> RunID = { RunID() },
        makeSeed: @escaping @MainActor @Sendable () -> UInt32 = {
            UInt32.random(in: UInt32.min ... UInt32.max)
        }
    ) {
        precondition(!deviceID.isEmpty, "A stable app-scoped device ID is required")
        self.applicationSupportDirectoryURL = applicationSupportDirectoryURL
        self.accountIdentity = accountIdentity
        self.deviceID = deviceID
        self.sessionNonce = sessionNonce
        self.newProfileID = newProfileID
        self.catalog = catalog
        self.now = now
        self.makeRunID = makeRunID
        self.makeSeed = makeSeed
    }
}

/// Stores a random installation identifier in this app's defaults domain.
/// It is not derived from hardware, advertising, account, or Game Center data.
@MainActor
struct StableInstallationDeviceIdentifierStore {
    static let productionStorageKey = "installation-device-id.v1"

    let userDefaults: UserDefaults
    let storageKey: String
    let makeUUID: () -> UUID

    init(
        userDefaults: UserDefaults,
        storageKey: String = Self.productionStorageKey,
        makeUUID: @escaping () -> UUID = UUID.init
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
        self.makeUUID = makeUUID
    }

    func identifier() -> String {
        if let stored = userDefaults.string(forKey: storageKey),
           let parsed = UUID(uuidString: stored) {
            return parsed.uuidString.lowercased()
        }

        let created = makeUUID().uuidString.lowercased()
        userDefaults.set(created, forKey: storageKey)
        return created
    }
}

/// Owns the active local profile repository and exposes only the closures the
/// app coordinator needs. All state shown by the shell is projected from a
/// successfully persisted repository snapshot.
@MainActor
final class ProductionAppComposition {
    /// Persisted fields controlled by `PlayerSnapshot.revision`. The derived
    /// coin balance is intentionally excluded and guarded with the economy
    /// fields below. Runtime sync status is deliberately excluded and owned by
    /// the composition's independent sync revision.
    private struct PlayerRevisionPartition: Equatable {
        let profileID: UUID
        let settings: PlayerSettings
        let selection: PlayerSelection
        let inventory: PlayerInventory
        let career: CareerStatistics
        let achievementProgress: [AchievementID: AchievementProgress]
        let rewardedAdState: RewardedAdState
        let completedRuns: [RunID: CompletedRunRecord]

        init(snapshot: LocalPlayerProfileSnapshot) {
            profileID = snapshot.player.profileID
            settings = snapshot.player.settings
            selection = snapshot.player.selection
            inventory = snapshot.player.inventory
            career = snapshot.player.career
            achievementProgress = snapshot.player.achievementProgress
            rewardedAdState = snapshot.player.rewardedAdState
            completedRuns = snapshot.completedRuns
        }
    }

    /// Persisted economy fields plus the redundant player-facing total derived
    /// from them. Comparing the derived total prevents an internally
    /// inconsistent snapshot from crossing a player-only revision update.
    private struct EconomyRevisionPartition: Equatable {
        let inventory: PlayerInventory
        let rewardedAdState: RewardedAdState
        let derivedPlayerCoinBalance: Int64
        let coinBalances: CoinBalanceSummary
        let ledger: [LedgerEntryID: CoinLedgerEntry]
        let pendingLedgerEntryIDs: Set<LedgerEntryID>
        let rewardedRunObservations: [RunID: RewardedRunObservation]

        init(snapshot: LocalPlayerProfileSnapshot) {
            // Catalog ownership and rewarded-ad progress are stored on the
            // player document, but production only changes them together with
            // a durable economy mutation. Membership in both partitions
            // enforces that coupled invariant.
            inventory = snapshot.player.inventory
            rewardedAdState = snapshot.player.rewardedAdState
            derivedPlayerCoinBalance = snapshot.player.coinBalance
            coinBalances = snapshot.coinBalances
            ledger = snapshot.ledger
            pendingLedgerEntryIDs = snapshot.pendingLedgerEntryIDs
            rewardedRunObservations = snapshot.rewardedRunObservations
        }
    }

    private enum Message {
        static let loadFailed =
            "Saved player data could not be opened. Check available storage and try again."
        static let profileUnavailable =
            "Saved player data is not ready. No changes were made."
        static let mutationFailed =
            "The player profile could not be saved. No unverified changes were applied."
        static let integrityCollision =
            "The player profile returned conflicting data for the same revision. No unverified changes were applied."
        static let selectionTooBroad =
            "That equipment change could not be verified. No changes were made."
        static let runFailed =
            "The completed run could not be verified and saved. Retry before leaving the run."
        static let gameCenterUnavailable =
            "Game Center is not connected in this build."
        static let unlockUnavailable =
            "Unlocks require verified private-cloud coins and are not enabled yet. No coins were spent."
        static let purchasesUnavailable =
            "Purchases are not enabled in this build."
        static let adsUnavailable =
            "Rewarded ads are not enabled in this build."
    }

    private let dependencies: ProductionAppDependencies
    private let repository: LocalPlayerProfileRepository
    private let authoritativeStateChannel: ProductionAuthoritativeStateChannel
    private let diagnosticsSink: AppleDiagnosticsSink?
    private var currentSnapshot: LocalPlayerProfileSnapshot?
    private var syncStatus: ProfileSyncStatus
    private var syncRevision: UInt64

    init(
        dependencies: ProductionAppDependencies,
        authoritativeStateChannel: ProductionAuthoritativeStateChannel = .init(),
        diagnosticsSink: AppleDiagnosticsSink? = nil
    ) {
        self.dependencies = dependencies
        self.authoritativeStateChannel = authoritativeStateChannel
        self.diagnosticsSink = diagnosticsSink
        syncStatus = .localOnly
        syncRevision = 0
        repository = LocalPlayerProfileRepository(
            directoryURL: Self.profileDirectoryURL(
                applicationSupportDirectoryURL: dependencies.applicationSupportDirectoryURL,
                accountIdentity: dependencies.accountIdentity
            ),
            deviceID: dependencies.deviceID,
            accountIdentity: dependencies.accountIdentity,
            sessionNonce: dependencies.sessionNonce,
            catalog: dependencies.catalog,
            economyMutationPolicy: .requireDurablePrivateCloud
        )
    }

    var environment: AppCoordinatorEnvironment {
        AppCoordinatorEnvironment(
            loadInitialState: { [self] in
                await loadInitialState()
            },
            makeAuthoritativeStateUpdates: { [channel = authoritativeStateChannel] in
                channel.makeStream()
            },
            diagnosticsSink: diagnosticsSink,
            makeRunID: dependencies.makeRunID,
            makeSeed: dependencies.makeSeed,
            now: dependencies.now,
            performExternalRequest: { [self] request in
                await perform(request)
            },
            observeLifecycleEvent: nil,
            settleCompletedRun: { [self] run in
                await settle(run)
            }
        )
    }

    nonisolated static func profileDirectoryURL(
        applicationSupportDirectoryURL: URL,
        accountIdentity: PlayerAccountIdentity
    ) -> URL {
        let digest = SHA256.hash(data: Data(accountIdentity.rawValue.utf8))
        let accountScope = digest.prefix(16).map {
            String(format: "%02x", $0)
        }.joined()

        return applicationSupportDirectoryURL
            .appendingPathComponent("PocketVector", isDirectory: true)
            .appendingPathComponent("Profiles", isDirectory: true)
            .appendingPathComponent(accountScope, isDirectory: true)
    }

    private func loadInitialState() async -> AppBootstrapLoadResult {
        if let currentSnapshot {
            return .loaded(authoritativeSnapshot(from: currentSnapshot))
        }

        do {
            let loadedAt = dependencies.now()
            let snapshot = try await repository.load(
                at: loadedAt,
                newProfileID: dependencies.newProfileID
            )
            let accepted = try accept(snapshot, publishUpdate: false)
            if let report = await repository.lastLoadReport {
                reportPersistenceRecovery(report, at: loadedAt)
            }
            return .loaded(authoritativeSnapshot(from: accepted))
        } catch {
            return .failed(message: Message.loadFailed)
        }
    }

    /// Reprojects the repository only after its caller has committed durable
    /// state. SDK callbacks never construct or publish UI state themselves.
    func refreshAuthoritativeStateFromRepository() async {
        do {
            let snapshot = try await repository.snapshot()
            _ = try accept(snapshot, publishUpdate: true)
        } catch {
            // A refresh is advisory. The last verified projection remains
            // authoritative and foreground mutations continue to surface their
            // own specific failures.
        }
    }

    /// Publishes a runtime-only sync transition without manufacturing a player
    /// or economy revision. Repository snapshots cannot select this status, and
    /// repeating the current status is an idempotent no-op.
    @discardableResult
    func publishSyncStatusTransition(
        _ status: ProfileSyncStatus
    ) throws -> AuthoritativeAppStateSnapshot? {
        guard status != syncStatus else { return nil }
        let nextRevision = syncRevision.addingReportingOverflow(1)
        guard !nextRevision.overflow else {
            throw ProductionAppCompositionError.syncRevisionOverflow
        }

        syncStatus = status
        syncRevision = nextRevision.partialValue
        guard let currentSnapshot else { return nil }
        let update = authoritativeSnapshot(from: currentSnapshot)
        authoritativeStateChannel.publish(update)
        return update
    }

    private func perform(_ request: AppExternalRequest) async -> AppExternalRequestResult {
        guard let currentSnapshot else {
            return .failed(message: Message.profileUnavailable)
        }

        switch request {
        case let .updateSelection(selection):
            return await updateSelection(
                selection,
                currentSnapshot: currentSnapshot
            )

        case let .updateSettings(settings):
            do {
                let snapshot = try await repository.updateSettings(
                    settings,
                    session: currentSnapshot.session,
                    at: dependencies.now()
                )
                return try publishMutation(snapshot)
            } catch ProductionAppCompositionError.authoritativeRevisionCollision {
                return .failed(message: Message.integrityCollision)
            } catch {
                return .failed(message: Message.mutationFailed)
            }

        case .showLeaderboard:
            return .failed(message: Message.gameCenterUnavailable)

        case .requestCatalogUnlock:
            return .failed(message: Message.unlockUnavailable)

        case .requestCoinPack:
            return .failed(message: Message.purchasesUnavailable)

        case .requestRewardedAd:
            return .failed(message: Message.adsUnavailable)
        }
    }

    private func updateSelection(
        _ requested: PlayerSelection,
        currentSnapshot: LocalPlayerProfileSnapshot
    ) async -> AppExternalRequestResult {
        let current = currentSnapshot.player.selection
        let teamChanged = requested.selectedTeamID != current.selectedTeamID
        let footballChanged = requested.selectedFootballID != current.selectedFootballID
        let allTeamIDs = Set(requested.selectedJerseyByTeam.keys)
            .union(current.selectedJerseyByTeam.keys)
        let changedJerseyTeamIDs = allTeamIDs.filter {
            requested.selectedJerseyByTeam[$0] != current.selectedJerseyByTeam[$0]
        }
        let changeCount = (teamChanged ? 1 : 0)
            + (footballChanged ? 1 : 0)
            + changedJerseyTeamIDs.count

        guard changeCount <= 1 else {
            return .failed(message: Message.selectionTooBroad)
        }
        guard changeCount == 1 else {
            return .applied(authoritativeSnapshot(from: currentSnapshot))
        }

        do {
            let snapshot: LocalPlayerProfileSnapshot
            if teamChanged {
                snapshot = try await repository.selectTeam(
                    requested.selectedTeamID,
                    session: currentSnapshot.session,
                    at: dependencies.now()
                )
            } else if footballChanged {
                snapshot = try await repository.equipFootball(
                    requested.selectedFootballID,
                    session: currentSnapshot.session,
                    at: dependencies.now()
                )
            } else if let teamID = changedJerseyTeamIDs.first,
                      let jerseyID = requested.selectedJerseyByTeam[teamID] {
                snapshot = try await repository.equipJersey(
                    jerseyID,
                    for: teamID,
                    session: currentSnapshot.session,
                    at: dependencies.now()
                )
            } else {
                return .failed(message: Message.selectionTooBroad)
            }
            return try publishMutation(snapshot)
        } catch ProductionAppCompositionError.authoritativeRevisionCollision {
            return .failed(message: Message.integrityCollision)
        } catch {
            return .failed(message: Message.mutationFailed)
        }
    }

    private func settle(_ run: CompletedRun) async -> CompletedRunSettlementResult {
        guard let currentSnapshot else {
            return .failed(message: Message.profileUnavailable)
        }

        do {
            let settlement = try await repository.settle(
                run,
                session: currentSnapshot.session,
                recordedAt: dependencies.now()
            )
            let snapshot = try await repository.snapshot()
            let accepted = try accept(snapshot, publishUpdate: true)
            let authoritativeSnapshot = authoritativeSnapshot(from: accepted)

            guard run.finishReason == .timerExpired else {
                return .settled(
                    authoritativeSnapshot: authoritativeSnapshot,
                    results: nil
                )
            }

            let results = try Self.makeResults(
                run: run,
                settlement: settlement,
                snapshot: accepted
            )
            return .settled(
                authoritativeSnapshot: authoritativeSnapshot,
                results: results
            )
        } catch {
            return .failed(message: Message.runFailed)
        }
    }

    private func publishMutation(
        _ snapshot: LocalPlayerProfileSnapshot
    ) throws -> AppExternalRequestResult {
        let accepted = try accept(snapshot, publishUpdate: true)
        return .applied(authoritativeSnapshot(from: accepted))
    }

    /// Accepts only monotonic repository projections. If an older async call
    /// finishes after a newer one, its caller receives the newest accepted
    /// snapshot and the presentation stream never regresses.
    func accept(
        _ candidate: LocalPlayerProfileSnapshot,
        publishUpdate: Bool
    ) throws -> LocalPlayerProfileSnapshot {
        guard let currentSnapshot else {
            self.currentSnapshot = candidate
            if publishUpdate {
                authoritativeStateChannel.publish(
                    authoritativeSnapshot(from: candidate)
                )
            }
            return candidate
        }

        guard candidate.session == currentSnapshot.session else {
            throw ProductionAppCompositionError.authoritativeSessionMismatch
        }
        guard candidate.player.revision >= currentSnapshot.player.revision,
              candidate.economyRevision >= currentSnapshot.economyRevision else {
            return currentSnapshot
        }

        if candidate.player.revision == currentSnapshot.player.revision,
           PlayerRevisionPartition(snapshot: candidate)
            != PlayerRevisionPartition(snapshot: currentSnapshot) {
            throw ProductionAppCompositionError.authoritativeRevisionCollision
        }
        if candidate.economyRevision == currentSnapshot.economyRevision,
           EconomyRevisionPartition(snapshot: candidate)
            != EconomyRevisionPartition(snapshot: currentSnapshot) {
            throw ProductionAppCompositionError.authoritativeRevisionCollision
        }

        if candidate.player.revision == currentSnapshot.player.revision,
           candidate.economyRevision == currentSnapshot.economyRevision {
            // The two explicit persisted partitions cover every repository
            // field except the legacy projection-only sync status. That status
            // is ignored here and can change only through the sync transition
            // method above.
            return currentSnapshot
        }

        self.currentSnapshot = candidate
        if publishUpdate {
            authoritativeStateChannel.publish(
                authoritativeSnapshot(from: candidate)
            )
        }
        return candidate
    }

    private func reportPersistenceRecovery(
        _ report: ProfileLoadReport,
        at date: Date
    ) {
        guard let diagnosticsSink else { return }

        if !report.quarantinedURLs.isEmpty {
            diagnosticsSink.report(
                .persistence(.quarantinedCorruptFile),
                severity: .warning,
                at: date
            )
        }

        switch report.source {
        case .primary:
            break
        case .backup:
            diagnosticsSink.report(
                .persistence(.restoredBackup),
                severity: .warning,
                at: date
            )
        case .createdFresh:
            diagnosticsSink.report(
                .persistence(.createdFreshProfile),
                severity: .info,
                at: date
            )
        }
    }

    private func authoritativeSnapshot(
        from snapshot: LocalPlayerProfileSnapshot
    ) -> AuthoritativeAppStateSnapshot {
        AuthoritativeAppStateSnapshot(
            session: snapshot.session,
            playerRevision: snapshot.player.revision,
            economyRevision: snapshot.economyRevision,
            syncRevision: syncRevision,
            state: Self.project(snapshot, syncStatus: syncStatus)
        )
    }

    private static func project(
        _ snapshot: LocalPlayerProfileSnapshot,
        syncStatus: ProfileSyncStatus
    ) -> AppCoordinatorState {
        AppCoordinatorState(
            inventory: snapshot.player.inventory,
            selection: snapshot.player.selection,
            settings: snapshot.player.settings,
            confirmedCoins: snapshot.coinBalances.confirmed,
            pendingCoins: snapshot.coinBalances.pending,
            personalBest: snapshot.personalBest,
            achievementProgress: snapshot.player.achievementProgress,
            rewardedAdState: snapshot.player.rewardedAdState,
            syncStatus: syncStatus
        )
    }

    private static func makeResults(
        run: CompletedRun,
        settlement: RunSettlementResult,
        snapshot: LocalPlayerProfileSnapshot
    ) throws -> RunResultsPresentation {
        var earnedCoins: Int64 = 0
        let entryIDs = [
            settlement.outcome.gameplayRewardEntryID,
            settlement.outcome.signingBonusEntryID,
        ].compactMap { $0 }

        for entryID in entryIDs {
            guard let entry = snapshot.ledger[entryID], entry.delta > 0 else {
                throw ProductionAppCompositionError.authoritativeLedgerEntryMissing
            }
            let next = earnedCoins.addingReportingOverflow(entry.delta)
            guard !next.overflow else {
                throw ProductionAppCompositionError.authoritativeLedgerOverflow
            }
            earnedCoins = next.partialValue
        }

        let priorPersonalBest = snapshot.completedRuns.values.reduce(0) { best, record in
            guard record.run.runID != run.runID,
                  CompletedRunValidator.isNaturallyCompleted(record.run) else {
                return best
            }
            return max(best, record.run.score)
        }
        let isNewPersonalBest = CompletedRunValidator.isNaturallyCompleted(run)
            && run.score > priorPersonalBest

        let rewardedAdOffer: RewardedAdOfferPresentation
        if let offerID = snapshot.player.rewardedAdState.eligibleOfferID {
            rewardedAdOffer = .eligible(
                offerID: offerID,
                rewardCoins: PersistedEconomyRulesV1.rewardedAdCoins,
                canPresent: false
            )
        } else {
            rewardedAdOffer = .progress(
                validRuns: snapshot.player.rewardedAdState.validRunsSinceReward,
                requiredRuns: PersistedEconomyRulesV1.rewardedAdRunThreshold
            )
        }

        return RunResultsPresentation(
            completedRun: run,
            earnedCoins: earnedCoins,
            pendingCoins: snapshot.coinBalances.pending,
            personalBest: settlement.outcome.resultingPersonalBest,
            isNewPersonalBest: isNewPersonalBest,
            rewardedAdOffer: rewardedAdOffer,
            achievementUpdates: settlement.outcome.achievementUpdates
        )
    }
}

enum ProductionAppCompositionError: Error, Equatable {
    case authoritativeLedgerEntryMissing
    case authoritativeLedgerOverflow
    case authoritativeSessionMismatch
    case authoritativeRevisionCollision
    case syncRevisionOverflow
}

extension AppCoordinatorEnvironment {
    @MainActor
    static var profileStorageUnavailable: AppCoordinatorEnvironment {
        AppCoordinatorEnvironment(
            loadInitialState: {
                .failed(
                    message: "Saved player data storage is unavailable on this device."
                )
            },
            makeAuthoritativeStateUpdates: nil,
            makeRunID: { RunID() },
            makeSeed: { UInt32.random(in: UInt32.min ... UInt32.max) },
            now: Date.init,
            performExternalRequest: { _ in
                .failed(message: "Saved player data storage is unavailable on this device.")
            },
            observeLifecycleEvent: nil,
            settleCompletedRun: { _ in
                .failed(message: "Saved player data storage is unavailable on this device.")
            }
        )
    }
}

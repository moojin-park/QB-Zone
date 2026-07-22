import Foundation

/// Recoverable, process-local admission failures for the exact profile source
/// frozen while a durable hydration transaction is in flight. These errors do
/// not remove durable recovery evidence or release an active mutation barrier.
enum LocalProfileHydrationBarrierError: Error, Equatable, Sendable {
    case hydrationInProgress(transactionID: UUID)
    case initialAssociationInProgress(transactionID: UUID)
    case transactionStoreMismatch
    case hydrationSourceMismatch
    case capabilityMismatch
    case predecessorAbortConfirmationMismatch
    case targetCleanupConfirmationMismatch
}

enum LocalGameCenterSubmissionError: Error, Equatable, Sendable {
    case submissionAuthorityMismatch
    case invalidLaunchAchievementSet
    case invalidPendingHighScore(Int)
    case invalidPendingAchievementPercent(
        achievementID: AchievementID,
        percentComplete: Int
    )
    case unsupportedPendingAchievementIDs([AchievementID])
}

enum LocalGameCenterAttributionError: Error, Equatable, Sendable {
    case ownershipProofMismatch
    case playerBucketLimitReached
}

/// Pure fail-closed planning shared by durable repository preparation and
/// focused validation tests. It accepts only the exact eight launch IDs and
/// never mutates the queue it inspects.
enum LocalGameCenterSubmissionPlanner {
    static func batch(
        for playerID: GameCenterPlayerID,
        queue: GameCenterPendingMaximaV1
    ) throws -> GameCenterSubmissionBatch? {
        guard queue.pendingHighScore >= 0 else {
            throw LocalGameCenterSubmissionError.invalidPendingHighScore(
                queue.pendingHighScore
            )
        }
        let launchAchievements = AchievementCatalog.launch
        let launchAchievementIDs = Set(launchAchievements.map(\.id))
        guard launchAchievements.count == 8,
              launchAchievementIDs.count == 8 else {
            throw LocalGameCenterSubmissionError.invalidLaunchAchievementSet
        }
        let pendingAchievementIDs = Set(
            queue.pendingAchievementPercents.keys
        )
        let unsupportedAchievementIDs = pendingAchievementIDs
            .subtracting(launchAchievementIDs)
            .sorted { $0.rawValue < $1.rawValue }
        guard unsupportedAchievementIDs.isEmpty else {
            throw LocalGameCenterSubmissionError
                .unsupportedPendingAchievementIDs(unsupportedAchievementIDs)
        }
        for achievementID in pendingAchievementIDs.sorted(
            by: { $0.rawValue < $1.rawValue }
        ) {
            guard let percent = queue.pendingAchievementPercents[achievementID],
                  (0 ... 100).contains(percent) else {
                throw LocalGameCenterSubmissionError
                    .invalidPendingAchievementPercent(
                        achievementID: achievementID,
                        percentComplete: queue.pendingAchievementPercents[
                            achievementID
                        ] ?? -1
                    )
            }
        }
        let achievements = queue.pendingAchievementPercents
            .filter { $0.value > 0 }
            .map {
                GameCenterAchievementSubmission(
                    id: $0.key,
                    percentComplete: $0.value
                )
            }
            .sorted { $0.id.rawValue < $1.id.rawValue }
        let batch = GameCenterSubmissionBatch(
            playerID: playerID,
            highScore: queue.pendingHighScore > 0
                ? queue.pendingHighScore
                : nil,
            achievements: achievements
        )
        return batch.isEmpty ? nil : batch
    }
}

/// Strong process identities make a prepared Game Center submission an opaque
/// capability rather than a caller-constructible identifier. The repository
/// retains its identity for its full lifetime and each preparation owns a
/// distinct submission identity.
final class LocalGameCenterSubmissionRepositoryIdentity: Sendable {
    fileprivate init() {}
}

final class LocalGameCenterSubmissionIdentity: Sendable {
    fileprivate init() {}
}

struct LocalGameCenterPreparedSubmissionV1: Equatable, Sendable {
    let batch: GameCenterSubmissionBatch

    private let repositoryIdentity: LocalGameCenterSubmissionRepositoryIdentity
    private let submissionIdentity: LocalGameCenterSubmissionIdentity
    private let session: ProfileSessionToken

    fileprivate init(
        repositoryIdentity: LocalGameCenterSubmissionRepositoryIdentity,
        submissionIdentity: LocalGameCenterSubmissionIdentity,
        session: ProfileSessionToken,
        batch: GameCenterSubmissionBatch
    ) {
        self.repositoryIdentity = repositoryIdentity
        self.submissionIdentity = submissionIdentity
        self.session = session
        self.batch = batch
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.repositoryIdentity === rhs.repositoryIdentity
            && lhs.submissionIdentity === rhs.submissionIdentity
            && lhs.session == rhs.session
            && lhs.batch == rhs.batch
    }

    fileprivate func wasIssued(
        by repositoryIdentity: LocalGameCenterSubmissionRepositoryIdentity,
        for session: ProfileSessionToken
    ) -> Bool {
        self.repositoryIdentity === repositoryIdentity
            && self.session == session
            && batch.playerID.rawValue.isEmpty == false
    }
}

/// Retained by every capability so allocator reuse cannot make a later
/// repository instance appear to own an earlier hydration admission.
fileprivate final class LocalProfileHydrationRepositoryIdentity: Sendable {}
fileprivate final class LocalProfileHydrationCapabilityIdentity: Sendable {}
fileprivate final class LocalProfileInitialAssociationIdentity: Sendable {}

/// Opaque, non-persisted proof that one repository actor froze one exact
/// source for one exact journal. It is intentionally copyable: dropping every
/// caller copy never releases the repository-owned barrier, so task
/// cancellation and ambiguous failures remain fail-closed.
struct LocalProfileHydrationCapabilityV1: Equatable, Hashable, Sendable {
    private let repositoryIdentity: LocalProfileHydrationRepositoryIdentity
    private let admissionIdentity: LocalProfileHydrationCapabilityIdentity
    private let standardizedProfileDirectoryURL: URL
    private let journal: ProfileHydrationJournalV1

    fileprivate init(
        repositoryIdentity: LocalProfileHydrationRepositoryIdentity,
        admissionIdentity: LocalProfileHydrationCapabilityIdentity,
        standardizedProfileDirectoryURL: URL,
        journal: ProfileHydrationJournalV1
    ) {
        self.repositoryIdentity = repositoryIdentity
        self.admissionIdentity = admissionIdentity
        self.standardizedProfileDirectoryURL = standardizedProfileDirectoryURL
        self.journal = journal
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.repositoryIdentity === rhs.repositoryIdentity
            && lhs.admissionIdentity === rhs.admissionIdentity
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(repositoryIdentity))
        hasher.combine(ObjectIdentifier(admissionIdentity))
    }

}

/// A bounded, noncopyable permit used only during the actor-isolated journal
/// admission call. The long-lived capability cannot be replayed directly
/// against the transaction store after the repository releases its barrier.
struct LocalProfileHydrationAdmissionPermitV1: ~Copyable, Sendable {
    private let standardizedProfileDirectoryURL: URL
    private let journal: ProfileHydrationJournalV1
    private let recoveryHandle: LocalProfileHydrationRecoveryHandleV1

    fileprivate init(
        standardizedProfileDirectoryURL: URL,
        journal: ProfileHydrationJournalV1,
        recoveryHandle: LocalProfileHydrationRecoveryHandleV1
    ) {
        self.standardizedProfileDirectoryURL = standardizedProfileDirectoryURL
        self.journal = journal
        self.recoveryHandle = recoveryHandle
    }

    func authorizesHydrationAdmission(
        journal: ProfileHydrationJournalV1,
        profileDirectoryURL: URL
    ) -> Bool {
        self.journal == journal
            && standardizedProfileDirectoryURL
                == profileDirectoryURL.standardizedFileURL
    }

    func completionRecoveryHandle(
        journal: ProfileHydrationJournalV1,
        profileDirectoryURL: URL
    ) throws -> LocalProfileHydrationRecoveryHandleV1 {
        guard authorizesHydrationAdmission(
            journal: journal,
            profileDirectoryURL: profileDirectoryURL
        ) else {
            throw ProfileHydrationTransactionStoreError
                .repositoryAdmissionMismatch
        }
        return recoveryHandle
    }
}

struct LocalProfileHydrationAdmissionV1: Equatable, Sendable {
    let recoveryHandle: LocalProfileHydrationRecoveryHandleV1
    let journalWrite: ProfileHydrationJournalWriteResult

    var capability: LocalProfileHydrationCapabilityV1 {
        recoveryHandle.capability
    }
}

struct LocalProfileInitialAssociationCapabilityV1: Equatable, Sendable {
    let transactionID: UUID
    let sourceDirectoryURL: URL
    let sourceArtifact: CanonicalProfileEnvelopeArtifactV1
    let sourceSession: ProfileSessionToken
    let targetCloudAccountID: CloudAccountID
    let targetDirectoryURL: URL
    fileprivate let identity: LocalProfileInitialAssociationIdentity

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.identity === rhs.identity
    }
}

actor LocalPlayerProfileRepository {
    private let fileStore: AtomicProfileFileStore
    private let catalog: LaunchCatalog
    private let deviceID: String
    private let accountIdentity: PlayerAccountIdentity
    private let economyMutationPolicy: EconomyMutationPolicy

    private var document: LocalPlayerDocumentV1?
    private var persistedArtifact: CanonicalProfileEnvelopeArtifactV1?
    private var pendingReplacementIntent: ExactProfileReplacementIntentV1?
    private let hydrationRepositoryIdentity = LocalProfileHydrationRepositoryIdentity()
    private let gameCenterSubmissionRepositoryIdentity =
        LocalGameCenterSubmissionRepositoryIdentity()
    private var activeHydrationBarrier: ActiveHydrationBarrier?
    private var activeInitialAssociation:
        LocalProfileInitialAssociationCapabilityV1?
    private let sessionNonce: UUID
    private var sessionIsActive = false
    private(set) var lastLoadReport: ProfileLoadReport?

    private struct ActiveHydrationBarrier {
        let recoveryHandle: LocalProfileHydrationRecoveryHandleV1
        let journal: ProfileHydrationJournalV1
        let sourceArtifact: CanonicalProfileEnvelopeArtifactV1
        let sourceSession: ProfileSessionToken
    }

    init(
        directoryURL: URL,
        deviceID: String,
        accountIdentity: PlayerAccountIdentity,
        sessionNonce: UUID = UUID(),
        catalog: LaunchCatalog = .approved,
        economyMutationPolicy: EconomyMutationPolicy = .requireDurablePrivateCloud,
        migrator: any PlayerProfileMigrating = PlayerProfileMigrator(),
        limits: ProfileHydrationLimits = .production,
        fileSystem: any ProfileHydrationFileSystem = FoundationProfileHydrationFileSystem()
    ) {
        precondition(
            ProfileStampDeviceIDRuleV1.isValid(deviceID),
            "A valid stable profile-stamp device ID is required"
        )
        fileStore = AtomicProfileFileStore(
            directoryURL: directoryURL,
            migrator: migrator,
            limits: limits,
            fileSystem: fileSystem
        )
        self.catalog = catalog
        self.deviceID = deviceID
        self.accountIdentity = accountIdentity
        self.sessionNonce = sessionNonce
        self.economyMutationPolicy = economyMutationPolicy
    }

    @discardableResult
    func load(
        at date: Date = Date(),
        newProfileID: UUID = UUID()
    ) throws -> LocalPlayerProfileSnapshot {
        if document != nil {
            return try makeSnapshot(for: requireActiveDocument())
        }

        let loaded = try fileStore.loadOrCreate(
            defaultDocument: PlayerProfileFactory.makeDefault(
                profileID: newProfileID,
                accountIdentity: accountIdentity,
                deviceID: deviceID,
                createdAt: date,
                catalog: catalog
            ),
            at: date,
            catalog: catalog
        )
        guard loaded.artifact.document.accountIdentity == accountIdentity else {
            throw LocalPlayerRepositoryError.accountIdentityMismatch(
                expected: accountIdentity,
                actual: loaded.artifact.document.accountIdentity
            )
        }
        document = loaded.artifact.document
        persistedArtifact = loaded.artifact
        sessionIsActive = true
        lastLoadReport = loaded.report
        return try makeSnapshot(for: loaded.artifact.document)
    }

    func snapshot() throws -> LocalPlayerProfileSnapshot {
        try makeSnapshot(for: requireActiveDocument())
    }

    func profileDirectoryURL() -> URL {
        fileStore.locations.directoryURL.standardizedFileURL
    }

    func beginInitialAssociation(
        targetCloudAccountID: CloudAccountID,
        targetDirectoryURL: URL,
        transactionID: UUID = UUID()
    ) throws -> LocalProfileInitialAssociationCapabilityV1 {
        let current = try requireActiveDocument()
        try rejectMutationDuringHydration()
        guard accountIdentity == .local,
              current.accountIdentity == .local,
              activeInitialAssociation == nil,
              pendingReplacementIntent == nil,
              let persistedArtifact else {
            throw LocalPlayerRepositoryError.profileWriteOutcomeUnknown
        }
        let derived = CloudAccountDerivedBindings.derive(
            from: targetCloudAccountID
        )
        guard derived.playerAccountIdentity != .local,
              fileStore.locations.directoryURL.standardizedFileURL
                != targetDirectoryURL.standardizedFileURL else {
            throw LocalPlayerRepositoryError.accountIdentityMismatch(
                expected: .local,
                actual: derived.playerAccountIdentity
            )
        }
        let capability = LocalProfileInitialAssociationCapabilityV1(
            transactionID: transactionID,
            sourceDirectoryURL:
                fileStore.locations.directoryURL.standardizedFileURL,
            sourceArtifact: persistedArtifact,
            sourceSession: ProfileSessionToken(
                accountIdentity: accountIdentity,
                nonce: sessionNonce,
                profileID: current.player.profileID
            ),
            targetCloudAccountID: targetCloudAccountID,
            targetDirectoryURL: targetDirectoryURL.standardizedFileURL,
            identity: LocalProfileInitialAssociationIdentity()
        )
        activeInitialAssociation = capability
        return capability
    }

    func resumeInitialAssociation(
        targetCloudAccountID: CloudAccountID,
        targetDirectoryURL: URL
    ) throws -> LocalProfileInitialAssociationCapabilityV1 {
        let current = try requireActiveDocument()
        guard let activeInitialAssociation,
              activeInitialAssociation.targetCloudAccountID
                == targetCloudAccountID,
              activeInitialAssociation.targetDirectoryURL
                == targetDirectoryURL.standardizedFileURL,
              persistedArtifact == activeInitialAssociation.sourceArtifact,
              current == activeInitialAssociation.sourceArtifact.document else {
            throw LocalPlayerRepositoryError.hydrationAdoptionSourceMismatch
        }
        return activeInitialAssociation
    }

    func completeInitialAssociation(
        _ capability: LocalProfileInitialAssociationCapabilityV1,
        verifiedTarget: ProfileInitialAssociationVerifiedTargetV1
    ) throws {
        guard let activeInitialAssociation,
              activeInitialAssociation == capability,
              persistedArtifact == capability.sourceArtifact,
              document == capability.sourceArtifact.document else {
            throw LocalPlayerRepositoryError.hydrationAdoptionSourceMismatch
        }
        guard verifiedTarget.authorizes(capability) else {
            throw LocalPlayerRepositoryError.hydrationAdoptionSourceMismatch
        }
        sessionIsActive = false
        document = nil
        persistedArtifact = nil
        self.activeInitialAssociation = nil
    }

    /// Freezes one exact persisted source before the durable journal is
    /// admitted. Actor isolation covers source verification, barrier install,
    /// and the synchronous transaction-store call without an unsafe blocking
    /// bridge or suspension window. A proven pre-claim failure never installs
    /// the barrier; every outcome after the pending physical claim leaves it
    /// installed for explicit recovery.
    func beginHydration(
        _ journal: ProfileHydrationJournalV1,
        session: ProfileSessionToken,
        transactionStore: ProfileHydrationFileTransactionStore
    ) throws -> LocalProfileHydrationAdmissionV1 {
        let current = try requireActiveDocument()
        try validateSession(session, against: current)
        if let activeHydrationBarrier {
            throw LocalProfileHydrationBarrierError.hydrationInProgress(
                transactionID: activeHydrationBarrier.journal.transactionID
            )
        }
        guard pendingReplacementIntent == nil else {
            throw LocalPlayerRepositoryError.profileWriteOutcomeUnknown
        }
        guard transactionStore.locations.profileDirectoryURL.standardizedFileURL
                == fileStore.locations.directoryURL.standardizedFileURL else {
            throw LocalProfileHydrationBarrierError.transactionStoreMismatch
        }
        guard let sourceArtifact = persistedArtifact,
              hydrationSourceMatches(
                journal,
                document: current,
                artifact: sourceArtifact,
                session: session
              ) else {
            throw LocalProfileHydrationBarrierError.hydrationSourceMismatch
        }

        let capability = LocalProfileHydrationCapabilityV1(
            repositoryIdentity: hydrationRepositoryIdentity,
            admissionIdentity: LocalProfileHydrationCapabilityIdentity(),
            standardizedProfileDirectoryURL:
                fileStore.locations.directoryURL.standardizedFileURL,
            journal: journal
        )
        let recoveryHandle = LocalProfileHydrationRecoveryHandleV1(
            capability: capability,
            standardizedProfileDirectoryURL:
                fileStore.locations.directoryURL.standardizedFileURL,
            journal: journal
        )
        let admissionPermit = LocalProfileHydrationAdmissionPermitV1(
            standardizedProfileDirectoryURL:
                fileStore.locations.directoryURL.standardizedFileURL,
            journal: journal,
            recoveryHandle: recoveryHandle
        )
        let barrier = ActiveHydrationBarrier(
            recoveryHandle: recoveryHandle,
            journal: journal,
            sourceArtifact: sourceArtifact,
            sourceSession: session
        )

        let journalWrite = try transactionStore.admitHydration(
            journal,
            permit: admissionPermit
        ) {
            activeHydrationBarrier = barrier
        }
        return LocalProfileHydrationAdmissionV1(
            recoveryHandle: recoveryHandle,
            journalWrite: journalWrite
        )
    }

    /// Recovers the already-installed process barrier after an ambiguous begin
    /// throw or caller cancellation. It never creates a second admission and
    /// returns authority only for the exact active journal and source session.
    func resumeHydrationBarrier(
        _ journal: ProfileHydrationJournalV1,
        session: ProfileSessionToken
    ) throws -> LocalProfileHydrationRecoveryHandleV1 {
        let current = try requireActiveDocument()
        try validateSession(session, against: current)
        guard let barrier = activeHydrationBarrier,
              barrier.journal == journal,
              barrier.sourceSession == session,
              persistedArtifact == barrier.sourceArtifact,
              current == barrier.sourceArtifact.document else {
            throw LocalProfileHydrationBarrierError.capabilityMismatch
        }
        return barrier.recoveryHandle
    }

    /// Re-enters the bounded store admission with the exact actor-owned handle
    /// after lock contention or another ambiguous begin outcome. It never
    /// issues a second capability and revalidates the full journal, source,
    /// session, and store binding before the synchronous retry.
    func retryHydrationAdmission(
        _ journal: ProfileHydrationJournalV1,
        session: ProfileSessionToken,
        transactionStore: ProfileHydrationFileTransactionStore
    ) throws -> LocalProfileHydrationAdmissionV1 {
        let current = try requireActiveDocument()
        try validateSession(session, against: current)
        guard let barrier = activeHydrationBarrier,
              barrier.journal == journal,
              barrier.sourceSession == session,
              persistedArtifact == barrier.sourceArtifact,
              current == barrier.sourceArtifact.document else {
            throw LocalProfileHydrationBarrierError.capabilityMismatch
        }
        guard transactionStore.locations.profileDirectoryURL.standardizedFileURL
                == fileStore.locations.directoryURL.standardizedFileURL else {
            throw LocalProfileHydrationBarrierError.transactionStoreMismatch
        }
        guard hydrationSourceMatches(
            journal,
            document: current,
            artifact: barrier.sourceArtifact,
            session: session
        ) else {
            throw LocalProfileHydrationBarrierError.hydrationSourceMismatch
        }
        let permit = LocalProfileHydrationAdmissionPermitV1(
            standardizedProfileDirectoryURL:
                fileStore.locations.directoryURL.standardizedFileURL,
            journal: journal,
            recoveryHandle: barrier.recoveryHandle
        )
        let journalWrite = try transactionStore.admitHydration(
            journal,
            permit: permit
        ) {}
        return LocalProfileHydrationAdmissionV1(
            recoveryHandle: barrier.recoveryHandle,
            journalWrite: journalWrite
        )
    }

    /// Supplies the exact canonical bytes returned by persistence. Re-encoding
    /// the in-memory document would discard the persisted envelope identity and
    /// is never accepted as hydration compare-and-swap evidence.
    func hydrationSource(
        session: ProfileSessionToken
    ) throws -> CloudProfileHydrationSourceV1 {
        let document = try requireActiveDocument()
        try validateSession(session, against: document)
        try rejectAuthorityProductionDuringHydration()
        guard let persistedArtifact else {
            throw LocalPlayerRepositoryError.notLoaded
        }
        return CloudProfileHydrationSourceV1(
            exactEnvelopeBytes: persistedArtifact.exactBytes,
            activeSession: session
        )
    }

    /// Freezes the current durable maxima into one exact, player-bound
    /// submission capability. Creating mutation authority is forbidden while
    /// hydration owns the repository barrier.
    func prepareGameCenterSubmission(
        for playerID: GameCenterPlayerID,
        session: ProfileSessionToken
    ) throws -> LocalGameCenterPreparedSubmissionV1? {
        let current = try requireActiveDocument()
        try validateSession(session, against: current)
        try rejectAuthorityProductionDuringHydration()

        guard let pending = current.player.pendingGameCenter.pending(for: playerID),
              let batch = try LocalGameCenterSubmissionPlanner.batch(
            for: playerID,
            queue: pending
        ) else { return nil }

        return LocalGameCenterPreparedSubmissionV1(
            repositoryIdentity: gameCenterSubmissionRepositoryIdentity,
            submissionIdentity: LocalGameCenterSubmissionIdentity(),
            session: session,
            batch: batch
        )
    }

    /// Durably assigns previously unbound maxima only after the immutable
    /// private-cloud owner claim has been read back for this exact profile and
    /// Game Center player. A failed or mismatched proof leaves every byte
    /// unchanged. Later gameplay may enqueue new unbound maxima, which are
    /// attributed through the same boundary on the next explicit delivery.
    @discardableResult
    func attributeUnboundGameCenterPending(
        to playerID: GameCenterPlayerID,
        ownershipProof: ProductionGameCenterOwnershipProof,
        session: ProfileSessionToken,
        at date: Date = Date()
    ) throws -> LocalPlayerProfileSnapshot {
        try Task.checkCancellation()
        var next = try requireActiveDocument()
        try validateSession(session, against: next)
        try rejectMutationDuringHydration()
        guard ownershipProof.authorizes(
            playerID: playerID,
            session: session
        ) else {
            throw LocalGameCenterAttributionError.ownershipProofMismatch
        }

        let unbound = next.player.pendingGameCenter.unboundPending
        guard !unbound.isEmpty else { return try makeSnapshot(for: next) }
        guard next.player.pendingGameCenter.pendingByPlayerID[playerID] != nil
                || next.player.pendingGameCenter.pendingByPlayerID.count
                    < PlayerScopedGameCenterQueueV1.maximumPlayerBucketCount else {
            throw LocalGameCenterAttributionError.playerBucketLimitReached
        }

        var bound = next.player.pendingGameCenter.pendingByPlayerID[playerID]
            ?? GameCenterPendingMaximaV1()
        bound.mergeMaxima(from: unbound)
        next.player.pendingGameCenter.pendingByPlayerID[playerID] = bound
        next.player.pendingGameCenter.unboundPending =
            GameCenterPendingMaximaV1()

        try incrementRevisions(of: &next, economyChanged: false)
        try persist(next, at: date)
        return try makeSnapshot(for: next)
    }

    /// Removes only values proven submitted by the exact prepared capability.
    /// A later maximum survives an older acknowledgement. The branded success
    /// value is constructible only by the delivery coordinator after GameKit
    /// success and same-player revalidation.
    @discardableResult
    func acknowledgeGameCenterSubmission(
        _ submission: LocalGameCenterPreparedSubmissionV1,
        successfulResult: GameCenterSuccessfulSubmissionV1,
        session: ProfileSessionToken,
        at date: Date = Date()
    ) throws -> LocalPlayerProfileSnapshot {
        try Task.checkCancellation()
        var next = try requireActiveDocument()
        try validateSession(session, against: next)
        try rejectMutationDuringHydration()
        guard submission.wasIssued(
            by: gameCenterSubmissionRepositoryIdentity,
            for: session
        ), successfulResult.confirms(submission) else {
            throw LocalGameCenterSubmissionError.submissionAuthorityMismatch
        }

        let pendingBeforeAcknowledgement = next.player.pendingGameCenter
        let handled = next.player.pendingGameCenter.acknowledge(submission.batch)
        guard handled,
              next.player.pendingGameCenter != pendingBeforeAcknowledgement else {
            return try makeSnapshot(for: next)
        }

        try incrementRevisions(of: &next, economyChanged: false)
        try persist(next, at: date)
        return try makeSnapshot(for: next)
    }

    /// Adopts only the exact candidate whose target checkpoint cleanup was
    /// confirmed by the transaction store. Invalid candidates or foreign proof
    /// retain the mutation barrier. A successful adoption is the sole target
    /// path that releases it.
    @discardableResult
    func adoptCommittedHydration(
        _ journal: ProfileHydrationJournalV1,
        session: ProfileSessionToken,
        capability: LocalProfileHydrationCapabilityV1,
        cleanupConfirmation: ProfileHydrationTargetCleanupConfirmationV1
    ) throws -> LocalPlayerProfileSnapshot {
        let current = try requireActiveDocument()
        try validateSession(session, against: current)
        let barrier = try matchingHydrationBarrier(
            journal: journal,
            session: session,
            capability: capability
        )
        guard cleanupConfirmation.confirmsTargetCleanup(
            journal: journal,
            profileDirectoryURL: fileStore.locations.directoryURL,
            capability: capability
        ) else {
            throw LocalProfileHydrationBarrierError
                .targetCleanupConfirmationMismatch
        }
        guard persistedArtifact == barrier.sourceArtifact,
              current == barrier.sourceArtifact.document else {
            throw LocalProfileHydrationBarrierError.hydrationSourceMismatch
        }

        let snapshot = try adoptExactInstalledCandidate(
            journal,
            session: session,
            current: current,
            sourceArtifact: barrier.sourceArtifact
        )
        activeHydrationBarrier = nil
        return snapshot
    }

    /// Releases only after the store proves that the exact predecessor is
    /// still current, both profile copies are the source, and durable journal
    /// evidence was removed. Missing-journal reconciliation returns no proof
    /// and therefore cannot call this API.
    @discardableResult
    func releaseHydrationAfterConfirmedPredecessorAbort(
        _ confirmation: ProfileHydrationPredecessorAbortConfirmationV1,
        journal: ProfileHydrationJournalV1,
        session: ProfileSessionToken,
        capability: LocalProfileHydrationCapabilityV1
    ) throws -> LocalPlayerProfileSnapshot {
        let current = try requireActiveDocument()
        try validateSession(session, against: current)
        let barrier = try matchingHydrationBarrier(
            journal: journal,
            session: session,
            capability: capability
        )
        guard confirmation.confirmsPredecessorAbort(
            journal: journal,
            profileDirectoryURL: fileStore.locations.directoryURL,
            capability: capability
        ) else {
            throw LocalProfileHydrationBarrierError
                .predecessorAbortConfirmationMismatch
        }
        guard persistedArtifact == barrier.sourceArtifact,
              current == barrier.sourceArtifact.document else {
            throw LocalProfileHydrationBarrierError.hydrationSourceMismatch
        }
        let snapshot = try makeSnapshot(for: current)
        activeHydrationBarrier = nil
        return snapshot
    }

#if DEBUG
    /// Legacy adoption coverage for low-level fixture matrices. Release builds
    /// expose only the capability-and-proof API above.
    @discardableResult
    func _testOnlyAdoptCommittedHydration(
        _ journal: ProfileHydrationJournalV1,
        session: ProfileSessionToken
    ) throws -> LocalPlayerProfileSnapshot {
        guard pendingReplacementIntent == nil else {
            throw LocalPlayerRepositoryError.profileWriteOutcomeUnknown
        }
        let current = try requireActiveDocument()
        try validateSession(session, against: current)
        guard let sourceArtifact = persistedArtifact else {
            throw LocalPlayerRepositoryError.notLoaded
        }
        return try adoptExactInstalledCandidate(
            journal,
            session: session,
            current: current,
            sourceArtifact: sourceArtifact
        )
    }
#endif

    func settlementReceipt(
        for runID: RunID,
        session: ProfileSessionToken
    ) throws -> RunSettlementOutcome? {
        let document = try requireActiveDocument()
        try validateSession(session, against: document)
        return document.settlementReceipts[runID]
    }

    /// Must be called by the account coordinator before it publishes a new
    /// account. Every in-flight operation holding the prior token is rejected.
    func invalidateForAccountSwitch() {
        guard sessionIsActive else { return }
        sessionIsActive = false
    }

    @discardableResult
    func settle(
        _ run: CompletedRun,
        session: ProfileSessionToken,
        recordedAt: Date = Date()
    ) throws -> RunSettlementResult {
        let current = try requireActiveDocument()
        try validateSession(session, against: current)
        try rejectMutationDuringHydration()
        do {
            try CompletedRunValidator.validate(
                run,
                recordedAt: recordedAt,
                inventory: current.player.inventory,
                catalog: catalog
            )
        } catch let error as CompletedRunValidationError {
            throw LocalPlayerRepositoryError.invalidRun(error)
        }
        if let receipt = current.settlementReceipts[run.runID] {
            guard receipt.record.run == run else {
                throw LocalPlayerRepositoryError.runIDConflict(run.runID)
            }
            return RunSettlementResult(
                outcome: receipt,
                wasAlreadySettled: true
            )
        }
        if current.player.completedRuns[run.runID] != nil {
            throw LocalPlayerRepositoryError.runIDConflict(run.runID)
        }

        var next = current
        let rewardCoins = try CompletedRunValidator.rewardCoins(for: run)
        let isRewardEligible = CompletedRunValidator.isRewardEligible(run)
        var gameplayRewardEntryID: LedgerEntryID?
        if rewardCoins > 0 {
            let entryID = CoinLedgerID.gameplay(runID: run.runID)
            guard next.player.ledger[entryID] == nil else {
                throw LocalPlayerRepositoryError.ledgerIDConflict(entryID)
            }
            next.player.ledger[entryID] = CoinLedgerEntry(
                id: entryID,
                delta: rewardCoins,
                reason: .gameplay(
                    runID: run.runID,
                    economyVersion: run.configuration.economyVersion
                ),
                createdAt: recordedAt
            )
            next.pendingLedgerEntryIDs.insert(entryID)
            gameplayRewardEntryID = entryID
        }

        var signingBonusEntryID: LedgerEntryID?
        if isRewardEligible {
            let entryID = CoinLedgerID.signingBonus(
                version: PersistedEconomyRulesV1.signingBonusVersion
            )
            if next.player.ledger[entryID] == nil {
                next.player.ledger[entryID] = CoinLedgerEntry(
                    id: entryID,
                    delta: PersistedEconomyRulesV1.signingBonusCoins,
                    reason: .signingBonus(
                        version: PersistedEconomyRulesV1.signingBonusVersion
                    ),
                    createdAt: PersistedEconomyRulesV1.signingBonusLedgerCreatedAt
                )
                next.pendingLedgerEntryIDs.insert(entryID)
                signingBonusEntryID = entryID
            }
        }

        next.player.career = try PersistedCareerAccumulatorV1.applying(
            run,
            to: next.player.career
        )
        let achievementUpdates = AchievementEvaluator.evaluate(
            run: run,
            careerAfter: next.player.career,
            existing: next.player.achievementProgress,
            evaluatedAt: recordedAt
        )
        for update in achievementUpdates {
            next.player.achievementProgress[update.current.id] = update.current
            // No proof-bearing GameKit identity spans run start and settlement
            // yet. Preserve progress without silently assigning it to whichever
            // account happens to authenticate later.
            next.player.pendingGameCenter.enqueueUnboundAchievement(update.current)
        }
        if CompletedRunValidator.isNaturallyCompleted(run) {
            next.player.pendingGameCenter.enqueueUnboundHighScore(run.score)
        }

        var rewardedOfferUnlocked: RewardOfferID?
        if isRewardEligible {
            let observation = RewardedRunObservation(
                observedCycle: next.player.rewardedAdState.cycle,
                disposition: next.player.rewardedAdState.eligibleOfferID == nil
                    ? .candidate
                    : .ignoredWhileOfferPending
            )
            if next.rewardedRunObservations == nil {
                next.rewardedRunObservations = [:]
            }
            next.rewardedRunObservations?[run.runID] = observation
            if next.player.rewardedAdState.recordValidRun(run.runID) {
                rewardedOfferUnlocked = next.player.rewardedAdState.eligibleOfferID
            }
        }

        let record = CompletedRunRecord(
            run: run,
            recordedAt: recordedAt,
            rewardCoins: rewardCoins
        )
        let outcome = RunSettlementOutcome(
            record: record,
            gameplayRewardEntryID: gameplayRewardEntryID,
            signingBonusEntryID: signingBonusEntryID,
            achievementUpdates: achievementUpdates,
            rewardedOfferUnlocked: rewardedOfferUnlocked,
            resultingPersonalBest: next.player.career.highestScore
        )
        next.player.completedRuns[run.runID] = record
        next.settlementReceipts[run.runID] = outcome

        try incrementRevisions(of: &next, economyChanged: true)
        try persist(next, at: recordedAt)
        return RunSettlementResult(
            outcome: outcome,
            wasAlreadySettled: false
        )
    }

    /// Marks already-recorded pending credits as durable. Repeating the same
    /// confirmation is a no-op, which makes reconnect retries safe.
    @discardableResult
    func confirmPendingCredits(
        _ entryIDs: Set<LedgerEntryID>,
        session: ProfileSessionToken,
        confirmation: DurableEconomyConfirmation,
        savedAt: Date = Date()
    ) throws -> LocalPlayerProfileSnapshot {
        var next = try requireActiveDocument()
        try validateSession(session, against: next)
        try rejectMutationDuringHydration()
        let balances = try PlayerProfileProjection.coinBalances(for: next)
        var expectedEntries: [LedgerEntryID: CoinLedgerEntry] = [:]

        for entryID in entryIDs {
            guard let entry = next.player.ledger[entryID] else {
                throw LocalPlayerRepositoryError.pendingCreditNotFound(entryID)
            }
            guard entry.delta > 0 else {
                throw LocalPlayerRepositoryError.invalidCredit(entryID)
            }
            expectedEntries[entryID] = entry
        }
        try validateConfirmationBinding(
            confirmation,
            expectedEntries: expectedEntries,
            session: session
        )

        guard entryIDs.contains(where: { next.pendingLedgerEntryIDs.contains($0) }) else {
            return try makeSnapshot(for: next)
        }
        try validateConfirmationFreshness(
            confirmation,
            document: next,
            balances: balances
        )
        next.pendingLedgerEntryIDs.subtract(entryIDs)
        try incrementRevisions(of: &next, economyChanged: true)
        try persist(next, at: savedAt)
        return try makeSnapshot(for: next)
    }

    /// Records a credit that an external service has already made durable.
    /// Deterministic ledger IDs turn repeated delivery into an idempotent read.
    @discardableResult
    func recordConfirmedCredit(
        _ entry: CoinLedgerEntry,
        session: ProfileSessionToken,
        confirmation: DurableEconomyConfirmation,
        savedAt: Date = Date()
    ) throws -> LocalPlayerProfileSnapshot {
        guard entry.delta > 0 else {
            throw LocalPlayerRepositoryError.invalidCredit(entry.id)
        }

        var next = try requireActiveDocument()
        try validateSession(session, against: next)
        try rejectMutationDuringHydration()
        let balances = try PlayerProfileProjection.coinBalances(for: next)
        try validateConfirmationBinding(
            confirmation,
            expectedEntries: [entry.id: entry],
            session: session
        )
        if let existing = next.player.ledger[entry.id] {
            guard existing == entry else {
                throw LocalPlayerRepositoryError.ledgerIDConflict(entry.id)
            }
            guard !next.pendingLedgerEntryIDs.contains(entry.id) else {
                throw LocalPlayerRepositoryError.ledgerIDConflict(entry.id)
            }
            return try makeSnapshot(for: next)
        }

        try validateConfirmationFreshness(
            confirmation,
            document: next,
            balances: balances
        )
        next.player.ledger[entry.id] = entry
        do {
            _ = try CoinLedger.balance(entries: [entry])
        } catch {
            throw LocalPlayerRepositoryError.invalidCredit(entry.id)
        }
        try incrementRevisions(of: &next, economyChanged: true)
        try persist(next, at: savedAt)
        return try makeSnapshot(for: next)
    }

    /// Produces the exact compare-and-swap payload for the private-cloud
    /// transaction. This is read-only; ownership and the debit remain local-
    /// state unchanged until `unlock(using:session:at:)` receives its receipt.
    func prepareUnlock(
        itemID: CatalogItemID,
        operationID: OperationID,
        session: ProfileSessionToken
    ) throws -> DurableCatalogUnlockRequest {
        let current = try requireActiveDocument()
        try validateSession(session, against: current)
        try rejectAuthorityProductionDuringHydration()
        guard let item = catalog.item(id: itemID) else {
            throw LocalPlayerRepositoryError.inventory(.unknownCatalogItem(itemID))
        }
        guard !itemIsOwned(item, inventory: current.player.inventory) else {
            throw LocalPlayerRepositoryError.inventory(.alreadyOwned(itemID))
        }
        let balances = try PlayerProfileProjection.coinBalances(for: current)
        let price = PersistedEconomyRulesV1.catalogPrice(for: item)
        guard balances.confirmed >= price else {
            throw LocalPlayerRepositoryError.insufficientConfirmedCoins(
                required: price,
                available: balances.confirmed
            )
        }
        return DurableCatalogUnlockRequest(
            operationID: operationID,
            session: session,
            itemID: itemID,
            ledgerEntryID: CoinLedgerID.catalogUnlock(itemID: itemID),
            price: price,
            expectedEconomyRevision: current.economyRevision,
            confirmedBalanceBefore: balances.confirmed
        )
    }

    @discardableResult
    func unlock(
        using receipt: DurableCatalogUnlockReceipt,
        session: ProfileSessionToken,
        at date: Date = Date()
    ) throws -> CatalogUnlockOutcome {
        try validateAuthority(receipt.authority)
        let current = try requireActiveDocument()
        try validateSession(session, against: current)
        try rejectMutationDuringHydration()
        guard receipt.session == session,
              !receipt.requestOperationID.rawValue.isEmpty,
              receipt.confirmedAt.timeIntervalSince1970.isFinite else {
            throw LocalPlayerRepositoryError.durableUnlockReceiptMismatch
        }

        let itemID = receipt.itemID
        guard let item = catalog.item(id: itemID) else {
            throw LocalPlayerRepositoryError.inventory(.unknownCatalogItem(itemID))
        }
        let ledgerID = CoinLedgerID.catalogUnlock(itemID: itemID)
        let persistedPrice = PersistedEconomyRulesV1.catalogPrice(for: item)
        guard receipt.ledgerEntryID == ledgerID,
              receipt.price == persistedPrice else {
            throw LocalPlayerRepositoryError.durableUnlockReceiptMismatch
        }
        let currentBalances = try PlayerProfileProjection.coinBalances(for: current)
        let expectedAfter = receipt.confirmedBalanceBefore.subtractingReportingOverflow(
            receipt.price
        )
        guard !expectedAfter.overflow,
              receipt.confirmedBalanceBefore >= receipt.price,
              receipt.confirmedBalanceAfter == expectedAfter.partialValue else {
            throw LocalPlayerRepositoryError.durableUnlockReceiptMismatch
        }

        let expectedEntry = CoinLedgerEntry(
            id: ledgerID,
            delta: -persistedPrice,
            reason: .catalogUnlock(itemID: itemID),
            createdAt: receipt.confirmedAt
        )
        if itemIsOwned(item, inventory: current.player.inventory),
           current.player.ledger[ledgerID] == expectedEntry {
            return CatalogUnlockOutcome(
                itemID: itemID,
                price: persistedPrice,
                wasAlreadyUnlocked: true,
                confirmedBalanceAfter: currentBalances.confirmed
            )
        }

        guard !itemIsOwned(item, inventory: current.player.inventory),
              current.player.ledger[ledgerID] == nil else {
            throw LocalPlayerRepositoryError.durableUnlockReceiptMismatch
        }
        guard receipt.expectedEconomyRevision == current.economyRevision else {
            throw LocalPlayerRepositoryError.economyStateStale(
                expected: receipt.expectedEconomyRevision,
                actual: current.economyRevision
            )
        }
        guard receipt.confirmedBalanceBefore == currentBalances.confirmed else {
            throw LocalPlayerRepositoryError.economyBalanceStale(
                expected: receipt.confirmedBalanceBefore,
                actual: currentBalances.confirmed
            )
        }
        guard currentBalances.confirmed >= receipt.price else {
            throw LocalPlayerRepositoryError.insufficientConfirmedCoins(
                required: receipt.price,
                available: currentBalances.confirmed
            )
        }

        var next = current
        do {
            _ = try InventoryRules.applyUnlock(
                itemID: itemID,
                to: &next.player.inventory,
                catalog: catalog
            )
        } catch let error as InventoryRuleError {
            throw LocalPlayerRepositoryError.inventory(error)
        }

        let rememberedJerseyInsertion: (teamID: TeamID, jerseyID: JerseyID)?
        if case let .team(teamID) = item.kind,
           next.player.selection.value.selectedJerseyByTeam[teamID] == nil,
           let team = catalog.team(id: teamID) {
            rememberedJerseyInsertion = (teamID, team.primaryJersey.id)
        } else {
            rememberedJerseyInsertion = nil
        }

        next.player.ledger[ledgerID] = expectedEntry

        if let rememberedJerseyInsertion {
            try applySelectionMutation(
                to: &next,
                economyChanged: true,
                at: date
            ) { selection in
                selection.selectedJerseyByTeam[rememberedJerseyInsertion.teamID]
                    = rememberedJerseyInsertion.jerseyID
            }
        } else {
            try incrementRevisions(of: &next, economyChanged: true)
        }
        try persist(next, at: date)
        let balanceAfter = try PlayerProfileProjection.coinBalances(for: next).confirmed
        return CatalogUnlockOutcome(
            itemID: itemID,
            price: persistedPrice,
            wasAlreadyUnlocked: false,
            confirmedBalanceAfter: balanceAfter
        )
    }

    /// Applies a server-verified rewarded-ad grant and consumes its five-run
    /// offer in one local transaction. The provider transaction ID is the
    /// idempotency key across callback retries, process restarts, and SSV replay.
    @discardableResult
    func settleRewardedAd(
        using receipt: DurableRewardedAdReceipt,
        session: ProfileSessionToken,
        savedAt: Date = Date()
    ) throws -> RewardedAdSettlementOutcome {
        let current = try requireActiveDocument()
        try validateSession(session, against: current)
        try rejectMutationDuringHydration()
        try validateAuthority(receipt.authority)
        guard receipt.session == session,
              receipt.rewardedAt.timeIntervalSince1970.isFinite else {
            throw LocalPlayerRepositoryError.rewardedAdReceiptMismatch
        }

        let ledgerID = CoinLedgerID.rewardedAd(
            providerTransactionID: receipt.providerTransactionID
        )
        let expectedEntry = CoinLedgerEntry(
            id: ledgerID,
            delta: PersistedEconomyRulesV1.rewardedAdCoins,
            reason: .rewardedAd(
                offerID: receipt.offerID,
                providerTransactionID: receipt.providerTransactionID
            ),
            createdAt: receipt.rewardedAt
        )
        let balances = try PlayerProfileProjection.coinBalances(for: current)

        if let existing = current.player.ledger[ledgerID] {
            guard existing == expectedEntry,
                  current.player.rewardedAdState.eligibleOfferID != receipt.offerID else {
                throw LocalPlayerRepositoryError.ledgerIDConflict(ledgerID)
            }
            return RewardedAdSettlementOutcome(
                offerID: receipt.offerID,
                providerTransactionID: receipt.providerTransactionID,
                ledgerEntryID: ledgerID,
                coins: PersistedEconomyRulesV1.rewardedAdCoins,
                wasAlreadySettled: true,
                confirmedBalanceAfter: balances.confirmed
            )
        }

        guard receipt.expectedEconomyRevision == current.economyRevision else {
            throw LocalPlayerRepositoryError.economyStateStale(
                expected: receipt.expectedEconomyRevision,
                actual: current.economyRevision
            )
        }
        guard receipt.confirmedBalanceBefore == balances.confirmed else {
            throw LocalPlayerRepositoryError.economyBalanceStale(
                expected: receipt.confirmedBalanceBefore,
                actual: balances.confirmed
            )
        }
        guard current.player.rewardedAdState.eligibleOfferID == receipt.offerID else {
            throw LocalPlayerRepositoryError.rewardedOfferNotEligible(receipt.offerID)
        }
        let expectedBalance = balances.confirmed.addingReportingOverflow(
            PersistedEconomyRulesV1.rewardedAdCoins
        )
        guard !expectedBalance.overflow else {
            throw LocalPlayerRepositoryError.validation(.arithmeticOverflow)
        }

        var next = current
        next.player.ledger[ledgerID] = expectedEntry
        guard next.player.rewardedAdState.redeem(receipt.offerID) else {
            throw LocalPlayerRepositoryError.rewardedOfferNotEligible(receipt.offerID)
        }
        try incrementRevisions(of: &next, economyChanged: true)
        try persist(next, at: savedAt)
        let balanceAfter = try PlayerProfileProjection.coinBalances(for: next).confirmed
        guard balanceAfter == expectedBalance.partialValue else {
            throw LocalPlayerRepositoryError.rewardedAdReceiptMismatch
        }
        return RewardedAdSettlementOutcome(
            offerID: receipt.offerID,
            providerTransactionID: receipt.providerTransactionID,
            ledgerEntryID: ledgerID,
            coins: PersistedEconomyRulesV1.rewardedAdCoins,
            wasAlreadySettled: false,
            confirmedBalanceAfter: balanceAfter
        )
    }

    @discardableResult
    func selectTeam(
        _ teamID: TeamID,
        session: ProfileSessionToken,
        at date: Date = Date()
    ) throws -> LocalPlayerProfileSnapshot {
        var next = try requireActiveDocument()
        try validateSession(session, against: next)
        try rejectMutationDuringHydration()
        guard let team = catalog.team(id: teamID) else {
            throw LocalPlayerRepositoryError.inventory(.unknownTeam(teamID))
        }
        guard next.player.inventory.ownedTeamIDs.contains(teamID) else {
            throw LocalPlayerRepositoryError.inventory(.teamNotOwned(teamID))
        }
        if next.player.selection.value.selectedTeamID == teamID {
            return try makeSnapshot(for: next)
        }

        let ownedJerseyIDs = next.player.inventory.ownedJerseyIDs
        try applySelectionMutation(to: &next, economyChanged: false, at: date) { selection in
            let rememberedJersey = selection.selectedJerseyByTeam[teamID]
            if rememberedJersey.map(ownedJerseyIDs.contains) != true {
                selection.selectedJerseyByTeam[teamID] = team.primaryJersey.id
            }
            selection.selectedTeamID = teamID
        }
        try persist(next, at: date)
        return try makeSnapshot(for: next)
    }

    @discardableResult
    func equipJersey(
        _ jerseyID: JerseyID,
        for teamID: TeamID,
        session: ProfileSessionToken,
        at date: Date = Date()
    ) throws -> LocalPlayerProfileSnapshot {
        var next = try requireActiveDocument()
        try validateSession(session, against: next)
        try rejectMutationDuringHydration()
        guard next.player.inventory.ownedTeamIDs.contains(teamID) else {
            throw LocalPlayerRepositoryError.inventory(.teamNotOwned(teamID))
        }
        guard let jersey = catalog.jersey(id: jerseyID) else {
            throw LocalPlayerRepositoryError.inventory(.unknownJersey(jerseyID))
        }
        guard jersey.teamID == teamID else {
            throw LocalPlayerRepositoryError.inventory(
                .jerseyDoesNotBelongToTeam(jerseyID: jerseyID, teamID: teamID)
            )
        }
        guard next.player.inventory.ownedJerseyIDs.contains(jerseyID) else {
            throw LocalPlayerRepositoryError.inventory(.jerseyNotOwned(jerseyID))
        }
        if next.player.selection.value.selectedJerseyByTeam[teamID] == jerseyID {
            return try makeSnapshot(for: next)
        }

        try applySelectionMutation(to: &next, economyChanged: false, at: date) {
            $0.selectedJerseyByTeam[teamID] = jerseyID
        }
        try persist(next, at: date)
        return try makeSnapshot(for: next)
    }

    @discardableResult
    func equipFootball(
        _ footballID: FootballID,
        session: ProfileSessionToken,
        at date: Date = Date()
    ) throws -> LocalPlayerProfileSnapshot {
        var next = try requireActiveDocument()
        try validateSession(session, against: next)
        try rejectMutationDuringHydration()
        guard catalog.football(id: footballID) != nil else {
            throw LocalPlayerRepositoryError.inventory(.unknownFootball(footballID))
        }
        guard next.player.inventory.ownedFootballIDs.contains(footballID) else {
            throw LocalPlayerRepositoryError.inventory(.footballNotOwned(footballID))
        }
        if next.player.selection.value.selectedFootballID == footballID {
            return try makeSnapshot(for: next)
        }

        try applySelectionMutation(to: &next, economyChanged: false, at: date) {
            $0.selectedFootballID = footballID
        }
        try persist(next, at: date)
        return try makeSnapshot(for: next)
    }

    @discardableResult
    func updateSettings(
        _ settings: PlayerSettings,
        session: ProfileSessionToken,
        at date: Date = Date()
    ) throws -> LocalPlayerProfileSnapshot {
        var next = try requireActiveDocument()
        try validateSession(session, against: next)
        try rejectMutationDuringHydration()
        let sanitized = PlayerSettings(
            musicVolume: settings.musicVolume,
            sfxVolume: settings.sfxVolume,
            isMuted: settings.isMuted,
            reducedMotion: settings.reducedMotion,
            tutorialCompleted: settings.tutorialCompleted
        )
        if next.player.settings.value == sanitized {
            return try makeSnapshot(for: next)
        }

        try applySettingsMutation(sanitized, to: &next, at: date)
        try persist(next, at: date)
        return try makeSnapshot(for: next)
    }

    private func matchingHydrationBarrier(
        journal: ProfileHydrationJournalV1,
        session: ProfileSessionToken,
        capability: LocalProfileHydrationCapabilityV1
    ) throws -> ActiveHydrationBarrier {
        guard let barrier = activeHydrationBarrier else {
            throw LocalProfileHydrationBarrierError.capabilityMismatch
        }
        guard barrier.recoveryHandle.capability == capability,
              barrier.journal == journal,
              barrier.sourceSession == session else {
            throw LocalProfileHydrationBarrierError.capabilityMismatch
        }
        return barrier
    }

    private func hydrationSourceMatches(
        _ journal: ProfileHydrationJournalV1,
        document: LocalPlayerDocumentV1,
        artifact: CanonicalProfileEnvelopeArtifactV1,
        session: ProfileSessionToken
    ) -> Bool {
        artifact.document == document
            && artifact.exactBytes == journal.sourceProfileEnvelope
            && artifact.digest == journal.sourceProfileEnvelopeDigest
            && journal.source.accountIdentity == session.accountIdentity
            && journal.source.sessionNonce == session.nonce
            && journal.source.profileID == session.profileID
            && journal.source.playerRevision == document.player.revision
            && journal.source.economyRevision == document.economyRevision
    }

    @discardableResult
    private func adoptExactInstalledCandidate(
        _ journal: ProfileHydrationJournalV1,
        session: ProfileSessionToken,
        current: LocalPlayerDocumentV1,
        sourceArtifact: CanonicalProfileEnvelopeArtifactV1
    ) throws -> LocalPlayerProfileSnapshot {
        guard pendingReplacementIntent == nil else {
            throw LocalPlayerRepositoryError.profileWriteOutcomeUnknown
        }
        guard hydrationSourceMatches(
            journal,
            document: current,
            artifact: sourceArtifact,
            session: session
        ) else {
            throw LocalPlayerRepositoryError.hydrationAdoptionSourceMismatch
        }

        let candidate = try fileStore.readExactInstalledCandidate(
            journal,
            catalog: catalog
        )
        guard candidate.document.accountIdentity == accountIdentity else {
            throw LocalPlayerRepositoryError.accountIdentityMismatch(
                expected: accountIdentity,
                actual: candidate.document.accountIdentity
            )
        }
        guard candidate.document.player.profileID == session.profileID else {
            throw LocalPlayerRepositoryError.hydrationAdoptionSourceMismatch
        }
        let snapshot = try makeSnapshot(for: candidate.document)
        document = candidate.document
        persistedArtifact = candidate
        return snapshot
    }

    private func rejectMutationDuringHydration() throws {
        if activeInitialAssociation != nil {
            throw LocalProfileHydrationBarrierError
                .initialAssociationInProgress(
                    transactionID: activeInitialAssociation!.transactionID
                )
        }
        guard let activeHydrationBarrier else { return }
        throw LocalProfileHydrationBarrierError.hydrationInProgress(
            transactionID: activeHydrationBarrier.journal.transactionID
        )
    }

    private func rejectAuthorityProductionDuringHydration() throws {
        try rejectMutationDuringHydration()
    }

    private func requireActiveDocument() throws -> LocalPlayerDocumentV1 {
        guard sessionIsActive else {
            throw document == nil
                ? LocalPlayerRepositoryError.notLoaded
                : LocalPlayerRepositoryError.sessionInvalidated
        }
        try reconcilePendingReplacementIfNeeded()
        guard let document else {
            throw LocalPlayerRepositoryError.notLoaded
        }
        return document
    }

    private func makeSnapshot(
        for document: LocalPlayerDocumentV1
    ) throws -> LocalPlayerProfileSnapshot {
        try PlayerProfileProjection.snapshot(
            for: document,
            session: ProfileSessionToken(
                accountIdentity: accountIdentity,
                nonce: sessionNonce,
                profileID: document.player.profileID
            )
        )
    }

    private func validateSession(
        _ session: ProfileSessionToken,
        against document: LocalPlayerDocumentV1
    ) throws {
        guard sessionIsActive else {
            throw LocalPlayerRepositoryError.sessionInvalidated
        }
        let active = ProfileSessionToken(
            accountIdentity: accountIdentity,
            nonce: sessionNonce,
            profileID: document.player.profileID
        )
        guard session == active else {
            throw LocalPlayerRepositoryError.sessionMismatch
        }
    }

    private func persist(_ next: LocalPlayerDocumentV1, at date: Date) throws {
        guard next.accountIdentity == accountIdentity else {
            throw LocalPlayerRepositoryError.accountIdentityMismatch(
                expected: accountIdentity,
                actual: next.accountIdentity
            )
        }
        do {
            try PlayerProfileValidator.validate(next, catalog: catalog)
        } catch let error as ProfileValidationError {
            throw LocalPlayerRepositoryError.validation(error)
        }
        guard let persistedArtifact else {
            throw LocalPlayerRepositoryError.notLoaded
        }
        let attempt = try fileStore.save(
            next,
            at: date,
            catalog: catalog,
            replacing: persistedArtifact
        )
        switch attempt {
        case let .committed(saved):
            document = saved.document
            self.persistedArtifact = saved
        case let .reconciliationRequired(intent):
            pendingReplacementIntent = intent
            throw LocalPlayerRepositoryError.profileWriteOutcomeUnknown
        }
    }

    private func reconcilePendingReplacementIfNeeded() throws {
        guard let pendingReplacementIntent else { return }
        guard persistedArtifact == pendingReplacementIntent.source,
              document == pendingReplacementIntent.source.document else {
            throw LocalPlayerRepositoryError.profileWriteOutcomeUnknown
        }
        do {
            switch try fileStore.reconcile(
                pendingReplacementIntent,
                catalog: catalog
            ) {
            case let .committed(saved):
                guard saved == pendingReplacementIntent.candidate else {
                    throw LocalPlayerRepositoryError.profileWriteOutcomeUnknown
                }
                document = saved.document
                persistedArtifact = saved
                self.pendingReplacementIntent = nil
            case let .reconciliationRequired(intent):
                self.pendingReplacementIntent = intent
                throw LocalPlayerRepositoryError.profileWriteOutcomeUnknown
            }
        } catch {
            self.pendingReplacementIntent = pendingReplacementIntent
            throw LocalPlayerRepositoryError.profileWriteOutcomeUnknown
        }
    }

    private func incrementRevisions(
        of document: inout LocalPlayerDocumentV1,
        economyChanged: Bool
    ) throws {
        let advance = try makeRevisionAdvance(
            for: document,
            economyChanged: economyChanged,
            logicalCounter: nil
        )
        apply(advance, to: &document)
    }

    private struct RevisionAdvance {
        let playerRevision: UInt64
        let economyRevision: UInt64?
        let logicalCounter: UInt64?
    }

    private func makeRevisionAdvance(
        for document: LocalPlayerDocumentV1,
        economyChanged: Bool,
        logicalCounter: UInt64?
    ) throws -> RevisionAdvance {
        let nextPlayerRevision = document.player.revision.addingReportingOverflow(1)
        guard !nextPlayerRevision.overflow else {
            throw LocalPlayerRepositoryError.validation(.arithmeticOverflow)
        }

        let nextEconomyRevision: UInt64?
        if economyChanged {
            let result = document.economyRevision.addingReportingOverflow(1)
            guard !result.overflow else {
                throw LocalPlayerRepositoryError.validation(.arithmeticOverflow)
            }
            nextEconomyRevision = result.partialValue
        } else {
            nextEconomyRevision = nil
        }

        let nextLogicalCounter: UInt64?
        if let logicalCounter {
            let result = logicalCounter.addingReportingOverflow(1)
            guard !result.overflow else {
                throw LocalPlayerRepositoryError.validation(.arithmeticOverflow)
            }
            nextLogicalCounter = result.partialValue
        } else {
            nextLogicalCounter = nil
        }

        return RevisionAdvance(
            playerRevision: nextPlayerRevision.partialValue,
            economyRevision: nextEconomyRevision,
            logicalCounter: nextLogicalCounter
        )
    }

    private func apply(
        _ advance: RevisionAdvance,
        to document: inout LocalPlayerDocumentV1
    ) {
        document.player.revision = advance.playerRevision
        if let economyRevision = advance.economyRevision {
            document.economyRevision = economyRevision
        }
    }

    private func applySettingsMutation(
        _ settings: PlayerSettings,
        to document: inout LocalPlayerDocumentV1,
        at date: Date
    ) throws {
        let advance = try makeRevisionAdvance(
            for: document,
            economyChanged: false,
            logicalCounter: document.player.settings.logicalCounter
        )
        guard let logicalCounter = advance.logicalCounter else {
            throw LocalPlayerRepositoryError.validation(.arithmeticOverflow)
        }
        document.player.settings = Stamped(
            value: settings,
            modifiedAt: date,
            deviceID: deviceID,
            logicalCounter: logicalCounter
        )
        apply(advance, to: &document)
    }

    private func applySelectionMutation(
        to document: inout LocalPlayerDocumentV1,
        economyChanged: Bool,
        at date: Date,
        mutation: (inout PlayerSelection) -> Void
    ) throws {
        let advance = try makeRevisionAdvance(
            for: document,
            economyChanged: economyChanged,
            logicalCounter: document.player.selection.logicalCounter
        )
        guard let logicalCounter = advance.logicalCounter else {
            throw LocalPlayerRepositoryError.validation(.arithmeticOverflow)
        }
        var selection = document.player.selection.value
        mutation(&selection)
        document.player.selection = Stamped(
            value: selection,
            modifiedAt: date,
            deviceID: deviceID,
            logicalCounter: logicalCounter
        )
        apply(advance, to: &document)
    }

    private func validateAuthority(_ authority: EconomyStateAuthority) throws {
        guard economyMutationPolicy.permits(authority) else {
            throw LocalPlayerRepositoryError.economyAuthorityRejected(authority)
        }
    }

    private func validateConfirmationBinding(
        _ confirmation: DurableEconomyConfirmation,
        expectedEntries: [LedgerEntryID: CoinLedgerEntry],
        session: ProfileSessionToken
    ) throws {
        try validateAuthority(confirmation.authority)
        guard !expectedEntries.isEmpty,
              confirmation.session == session,
              confirmation.entries == expectedEntries,
              confirmation.confirmedAt.timeIntervalSince1970.isFinite else {
            throw LocalPlayerRepositoryError.economyConfirmationBindingMismatch
        }
    }

    private func validateConfirmationFreshness(
        _ confirmation: DurableEconomyConfirmation,
        document: LocalPlayerDocumentV1,
        balances: CoinBalanceSummary
    ) throws {
        guard confirmation.expectedEconomyRevision == document.economyRevision else {
            throw LocalPlayerRepositoryError.economyStateStale(
                expected: confirmation.expectedEconomyRevision,
                actual: document.economyRevision
            )
        }
        guard confirmation.confirmedBalanceBefore == balances.confirmed else {
            throw LocalPlayerRepositoryError.economyBalanceStale(
                expected: confirmation.confirmedBalanceBefore,
                actual: balances.confirmed
            )
        }
    }

    private func itemIsOwned(
        _ item: CatalogItemDescriptor,
        inventory: PlayerInventory
    ) -> Bool {
        switch item.kind {
        case let .team(teamID):
            inventory.ownedTeamIDs.contains(teamID)
        case let .alternateJersey(jerseyID):
            inventory.ownedJerseyIDs.contains(jerseyID)
        case let .football(footballID):
            inventory.ownedFootballIDs.contains(footballID)
        }
    }
}

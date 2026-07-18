import Foundation

/// An immutable, sealed description of one exact profile replacement. Only the
/// file store can create an intent; reconciliation may replay these exact bytes
/// but may never rebuild a candidate from mutable repository state.
struct ExactProfileReplacementIntentV1: Equatable, Sendable {
    let standardizedProfileDirectoryURL: URL
    let source: CanonicalProfileEnvelopeArtifactV1
    let candidate: CanonicalProfileEnvelopeArtifactV1

    fileprivate init(
        standardizedProfileDirectoryURL: URL,
        source: CanonicalProfileEnvelopeArtifactV1,
        candidate: CanonicalProfileEnvelopeArtifactV1
    ) {
        self.standardizedProfileDirectoryURL = standardizedProfileDirectoryURL
        self.source = source
        self.candidate = candidate
    }
}

enum ExactProfileReplacementAttemptResultV1: Equatable, Sendable {
    case committed(CanonicalProfileEnvelopeArtifactV1)
    case reconciliationRequired(ExactProfileReplacementIntentV1)
}

private struct ProfileLineageHighWatermarkV1: Codable, Equatable, Sendable {
    static let formatVersion = 1

    let formatVersion: Int
    let accountIdentity: PlayerAccountIdentity
    let profileID: UUID
    let playerRevision: UInt64
    let economyRevision: UInt64
    let envelope: Data
    let envelopeDigest: ProfileHydrationDigest

    init(artifact: CanonicalProfileEnvelopeArtifactV1) {
        formatVersion = Self.formatVersion
        accountIdentity = artifact.document.accountIdentity
        profileID = artifact.document.player.profileID
        playerRevision = artifact.document.player.revision
        economyRevision = artifact.document.economyRevision
        envelope = artifact.exactBytes
        envelopeDigest = artifact.digest
    }
}

/// Present only in a private-cloud association target. Its existence turns the
/// adjacent latest-envelope file into required rollback protection; local-only
/// profiles deliberately never create either authority.
private struct ProfileLineageProtectionMarkerV1: Codable, Equatable, Sendable {
    static let formatVersion = 1

    let formatVersion: Int
    let cloudAccountID: CloudAccountID
    let accountIdentity: PlayerAccountIdentity
    let profileID: UUID

    init(cloudAccountID: CloudAccountID) {
        let derived = CloudAccountDerivedBindings.derive(from: cloudAccountID)
        formatVersion = Self.formatVersion
        self.cloudAccountID = cloudAccountID
        accountIdentity = derived.playerAccountIdentity
        profileID = derived.durableAccountBinding.profileID
    }
}

struct AtomicProfileFileStore: Sendable {
    let locations: ProfileStorageLocations
    let transactionLocations: ProfileHydrationTransactionLocations
    let migrator: any PlayerProfileMigrating

    private let limits: ProfileHydrationLimits
    private let fileSystem: any ProfileHydrationFileSystem

    init(
        directoryURL: URL,
        migrator: any PlayerProfileMigrating = PlayerProfileMigrator(),
        limits: ProfileHydrationLimits = .production,
        fileSystem: any ProfileHydrationFileSystem = FoundationProfileHydrationFileSystem()
    ) {
        locations = ProfileStorageLocations(directoryURL: directoryURL)
        transactionLocations = ProfileHydrationTransactionLocations(
            profileDirectoryURL: directoryURL
        )
        self.migrator = migrator
        self.limits = limits
        self.fileSystem = fileSystem
    }

    func loadOrCreate(
        defaultDocument: @autoclosure () -> LocalPlayerDocumentV1,
        at date: Date,
        catalog: LaunchCatalog
    ) throws -> ProfileLoadResult {
        try withLock {
            try assertHydrationRecoveryIsClear()
            try prepareDirectories()
            var quarantinedURLs: [URL] = []

            if let lineage = try requiredProtectedLineage(catalog: catalog) {
                try writeAndVerify(
                    lineage.exactBytes,
                    to: locations.backupURL
                )
                try writeAndVerify(
                    lineage.exactBytes,
                    to: locations.primaryURL
                )
                return ProfileLoadResult(
                    artifact: lineage,
                    report: ProfileLoadReport(
                        source: .primary,
                        quarantinedURLs: quarantinedURLs
                    )
                )
            }

            if try itemIsPresent(at: locations.primaryURL) {
                do {
                    let primary = try readValidated(
                        from: locations.primaryURL,
                        catalog: catalog
                    )
                    try prepareBackup(
                        for: primary,
                        catalog: catalog,
                        at: date,
                        quarantinedURLs: &quarantinedURLs
                    )
                    if primary.rawBytes != primary.artifact.exactBytes {
                        try writeAndVerify(
                            primary.artifact.exactBytes,
                            to: locations.primaryURL
                        )
                    }
                    try advanceLineageHighWatermark(
                        to: primary.artifact,
                        catalog: catalog
                    )
                    return ProfileLoadResult(
                        artifact: primary.artifact,
                        report: ProfileLoadReport(
                            source: .primary,
                            quarantinedURLs: quarantinedURLs
                        )
                    )
                } catch ProfileReadError.invalid {
                    quarantinedURLs.append(
                        try quarantine(locations.primaryURL, at: date)
                    )
                }
            }

            if try itemIsPresent(at: locations.backupURL) {
                do {
                    let backup = try readValidated(
                        from: locations.backupURL,
                        catalog: catalog
                    )
                    if backup.rawBytes != backup.artifact.exactBytes {
                        try writeAndVerify(
                            backup.artifact.exactBytes,
                            to: locations.backupURL
                        )
                    }
                    try writeAndVerify(
                        backup.artifact.exactBytes,
                        to: locations.primaryURL
                    )
                    try advanceLineageHighWatermark(
                        to: backup.artifact,
                        catalog: catalog
                    )
                    return ProfileLoadResult(
                        artifact: backup.artifact,
                        report: ProfileLoadReport(
                            source: .backup,
                            quarantinedURLs: quarantinedURLs
                        )
                    )
                } catch ProfileReadError.invalid {
                    quarantinedURLs.append(
                        try quarantine(locations.backupURL, at: date)
                    )
                }
            }

            let document = defaultDocument()
            try PlayerProfileValidator.validate(document, catalog: catalog)
            let artifact = try migrator.canonicalArtifact(
                for: document,
                savedAt: date
            )
            try validateCanonicalArtifact(artifact, catalog: catalog)
            try advanceLineageHighWatermark(to: artifact, catalog: catalog)
            try writeAndVerify(artifact.exactBytes, to: locations.backupURL)
            try writeAndVerify(artifact.exactBytes, to: locations.primaryURL)
            return ProfileLoadResult(
                artifact: artifact,
                report: ProfileLoadReport(
                    source: .createdFresh,
                    quarantinedURLs: quarantinedURLs
                )
            )
        }
    }

    /// Fresh-fixture/bootstrap seeding only. Existing profile authority can be
    /// replaced solely through an exact replacement intent.
    @discardableResult
    func save(
        _ document: LocalPlayerDocumentV1,
        at date: Date,
        catalog: LaunchCatalog
    ) throws -> CanonicalProfileEnvelopeArtifactV1 {
        try PlayerProfileValidator.validate(document, catalog: catalog)
        let artifact = try migrator.canonicalArtifact(
            for: document,
            savedAt: date
        )
        try validateCanonicalArtifact(artifact, catalog: catalog)

        return try withLock {
            try assertHydrationRecoveryIsClear()
            try prepareDirectories()
            guard try !itemIsPresent(at: locations.primaryURL),
                  try !itemIsPresent(at: locations.backupURL) else {
                throw AtomicProfileFileStoreError.profileAlreadyExists
            }
            try advanceLineageHighWatermark(to: artifact, catalog: catalog)
            try writeAndVerify(artifact.exactBytes, to: locations.backupURL)
            try writeAndVerify(artifact.exactBytes, to: locations.primaryURL)
            return artifact
        }
    }

    /// Begins one exact compare-and-swap replacement. Failures before the
    /// candidate-primary rename are definitive throws. Failures after that
    /// rename may return an immutable reconciliation intent because the
    /// candidate can already be installed even when its durability result is
    /// unknown.
    @discardableResult
    func save(
        _ document: LocalPlayerDocumentV1,
        at date: Date,
        catalog: LaunchCatalog,
        replacing expected: CanonicalProfileEnvelopeArtifactV1
    ) throws -> ExactProfileReplacementAttemptResultV1 {
        let candidate = try migrator.canonicalArtifact(
            for: document,
            savedAt: date
        )
        let intent = ExactProfileReplacementIntentV1(
            standardizedProfileDirectoryURL: locations.directoryURL.standardizedFileURL,
            source: expected,
            candidate: candidate
        )
        return try attempt(intent, catalog: catalog)
    }

    /// Replays only a previously sealed exact intent. No document or envelope
    /// is regenerated during reconciliation.
    @discardableResult
    func reconcile(
        _ intent: ExactProfileReplacementIntentV1,
        catalog: LaunchCatalog
    ) throws -> ExactProfileReplacementAttemptResultV1 {
        return try attempt(intent, catalog: catalog)
    }

    /// Reads one candidate installed by the hydration transaction store without
    /// normalizing, repairing, or publishing it. The journal is validated before
    /// file-system I/O; under the shared hydration lock, every durable barrier
    /// must be absent and both profile copies must be its exact candidate bytes.
    func readExactInstalledCandidate(
        _ journal: ProfileHydrationJournalV1,
        catalog: LaunchCatalog
    ) throws -> CanonicalProfileEnvelopeArtifactV1 {
        do {
            try journal.validate(
                migrator: migrator,
                catalog: catalog,
                limits: limits
            )
        } catch let error as ProfileHydrationJournalValidationError {
            throw AtomicProfileFileStoreError.invalidHydrationJournal(error)
        }
        let candidate: CanonicalProfileEnvelopeArtifactV1
        do {
            let decoded = try migrator.decodeArtifact(
                journal.candidateProfileEnvelope
            )
            candidate = try migrator.canonicalArtifact(
                for: decoded.document,
                savedAt: decoded.savedAt
            )
            try validateCanonicalArtifact(candidate, catalog: catalog)
        } catch {
            throw AtomicProfileFileStoreError.invalidHydrationJournal(
                .invalidCandidateEnvelope
            )
        }
        guard candidate.exactBytes == journal.candidateProfileEnvelope,
              candidate.digest == journal.candidateProfileEnvelopeDigest else {
            throw AtomicProfileFileStoreError.invalidReplacementIntent
        }

        return try withLock {
            try assertHydrationRecoveryIsClear()
            let primary = try hydrationCopyState(
                at: locations.primaryURL,
                journal: journal
            )
            let backup = try hydrationCopyState(
                at: locations.backupURL,
                journal: journal
            )
            guard primary == .candidate, backup == .candidate else {
                throw AtomicProfileFileStoreError
                    .hydrationCandidateNotExactlyInstalled(
                        primary: primary,
                        backup: backup
                    )
            }
            try advanceLineageHighWatermark(to: candidate, catalog: catalog)
            return candidate
        }
    }

    /// Installs rollback protection for one exact association target. The
    /// high-watermark becomes durable before its required marker is published,
    /// so a crash can leave only an ignored orphan watermark, never a marker
    /// that was durably published before its authority.
    /// Caller must already hold this profile directory's transaction lock.
    func installLineageProtectionUnderExternalLock(
        cloudAccountID: CloudAccountID,
        artifact: CanonicalProfileEnvelopeArtifactV1,
        catalog: LaunchCatalog
    ) throws {
        try validateCanonicalArtifact(artifact, catalog: catalog)
        let marker = ProfileLineageProtectionMarkerV1(
            cloudAccountID: cloudAccountID
        )
        guard artifact.document.accountIdentity == marker.accountIdentity,
              artifact.document.player.profileID == marker.profileID else {
            throw AtomicProfileFileStoreError.invalidReplacementIntent
        }
        if let existing = try readLineageProtectionMarker() {
            guard existing == marker else {
                throw AtomicProfileFileStoreError.invalidReplacementIntent
            }
            try advanceLineageHighWatermark(
                to: artifact,
                catalog: catalog
            )
            guard try requiredProtectedLineage(catalog: catalog) == artifact else {
                throw AtomicProfileFileStoreError.atomicWriteOutcomeUnknown
            }
            return
        }
        try writeLineageHighWatermark(
            artifact,
            catalog: catalog,
            requireExistingProtection: false
        )
        try writeLineageProtectionMarkerIfNeeded(marker)
        guard try requiredProtectedLineage(catalog: catalog) == artifact else {
            throw AtomicProfileFileStoreError.atomicWriteOutcomeUnknown
        }
    }

    /// A committed account association requires both its binding marker and
    /// durable latest-envelope authority to exist and agree.
    /// Caller must already hold this profile directory's transaction lock.
    /// The committed-association store holds both source and target locks and
    /// cannot recursively reacquire the target lock through `withLock`.
    func requiredLineageHighWatermarkUnderExternalLock(
        catalog: LaunchCatalog
    ) throws -> CanonicalProfileEnvelopeArtifactV1 {
        guard let artifact = try requiredProtectedLineage(catalog: catalog) else {
            throw AtomicProfileFileStoreError.invalidReplacementIntent
        }
        return artifact
    }
}

struct ProfileInitialAssociationJournalV1: Codable, Equatable, Sendable {
    static let formatVersion = 1

    let formatVersion: Int
    let transactionID: UUID
    let createdAt: Date
    let sourceDirectoryPath: String
    let targetDirectoryPath: String
    let cloudAccountID: CloudAccountID
    let sourceSessionAccountIdentity: PlayerAccountIdentity
    let sourceSessionNonce: UUID
    let sourceProfileID: UUID
    let sourceEnvelope: Data
    let sourceEnvelopeDigest: ProfileHydrationDigest
    let candidateEnvelope: Data
    let candidateEnvelopeDigest: ProfileHydrationDigest
    let targetCheckpoint: CloudReplicaCheckpointV1

    static func make(
        createdAt: Date,
        capability: LocalProfileInitialAssociationCapabilityV1,
        candidateEnvelope: Data,
        targetCheckpoint: CloudReplicaCheckpointV1
    ) throws -> Self {
        let journal = Self(
            formatVersion: formatVersion,
            transactionID: capability.transactionID,
            createdAt: createdAt,
            sourceDirectoryPath: capability.sourceDirectoryURL.path,
            targetDirectoryPath: capability.targetDirectoryURL.path,
            cloudAccountID: capability.targetCloudAccountID,
            sourceSessionAccountIdentity:
                capability.sourceSession.accountIdentity,
            sourceSessionNonce: capability.sourceSession.nonce,
            sourceProfileID: capability.sourceSession.profileID,
            sourceEnvelope: capability.sourceArtifact.exactBytes,
            sourceEnvelopeDigest: capability.sourceArtifact.digest,
            candidateEnvelope: candidateEnvelope,
            candidateEnvelopeDigest:
                .envelopeBytes(candidateEnvelope),
            targetCheckpoint: targetCheckpoint
        )
        try journal.validate()
        return journal
    }

    func validate(
        migrator: any PlayerProfileMigrating = PlayerProfileMigrator(),
        catalog: LaunchCatalog = .approved,
        limits: ProfileHydrationLimits = .production
    ) throws {
        guard formatVersion == Self.formatVersion,
              transactionID != UUID(uuid: (
                0, 0, 0, 0, 0, 0, 0, 0,
                0, 0, 0, 0, 0, 0, 0, 0
              )),
              createdAt.timeIntervalSince1970.isFinite,
              sourceEnvelope.count <= limits.maximumProfileEnvelopeBytes,
              candidateEnvelope.count <= limits.maximumProfileEnvelopeBytes,
              sourceEnvelopeDigest == .envelopeBytes(sourceEnvelope),
              candidateEnvelopeDigest == .envelopeBytes(candidateEnvelope),
              sourceDirectoryURL != targetDirectoryURL,
              sourceDirectoryURL.deletingLastPathComponent()
                == targetDirectoryURL.deletingLastPathComponent(),
              !sourceDirectoryURL.lastPathComponent.isEmpty,
              !targetDirectoryURL.lastPathComponent.isEmpty,
              sourceSessionAccountIdentity == .local
        else {
            throw ProfileInitialAssociationStoreError.invalidJournal
        }
        let source = try migrator.decode(sourceEnvelope)
        let candidate = try migrator.decode(candidateEnvelope)
        try PlayerProfileValidator.validate(source, catalog: catalog)
        try PlayerProfileValidator.validate(candidate, catalog: catalog)
        let sourceCanonical = try migrator.canonicalArtifact(
            for: source,
            savedAt: try migrator.decodeArtifact(sourceEnvelope).savedAt
        )
        let candidateCanonical = try migrator.canonicalArtifact(
            for: candidate,
            savedAt: try migrator.decodeArtifact(candidateEnvelope).savedAt
        )
        let derived = CloudAccountDerivedBindings.derive(from: cloudAccountID)
        let nextPlayerRevision = source.player.revision.addingReportingOverflow(1)
        let nextEconomyRevision = source.economyRevision.addingReportingOverflow(1)
        guard sourceCanonical.exactBytes == sourceEnvelope,
              candidateCanonical.exactBytes == candidateEnvelope,
              source.accountIdentity == .local,
              source.player.profileID == sourceProfileID,
              candidate.accountIdentity == derived.playerAccountIdentity,
              candidate.player.profileID == derived.durableAccountBinding.profileID,
              !nextPlayerRevision.overflow,
              !nextEconomyRevision.overflow,
              candidate.player.revision == nextPlayerRevision.partialValue,
              candidate.economyRevision == nextEconomyRevision.partialValue,
              targetCheckpoint.accountID == cloudAccountID else {
            throw ProfileInitialAssociationStoreError.invalidJournal
        }
        do {
            try targetCheckpoint.validate()
        } catch {
            throw ProfileInitialAssociationStoreError.invalidJournal
        }
    }

    var sourceDirectoryURL: URL {
        URL(fileURLWithPath: sourceDirectoryPath, isDirectory: true)
            .standardizedFileURL
    }

    var targetDirectoryURL: URL {
        URL(fileURLWithPath: targetDirectoryPath, isDirectory: true)
            .standardizedFileURL
    }
}

enum ProfileInitialAssociationStoreError: Error, Equatable, Sendable {
    case invalidJournal
    case capabilityMismatch
    case accountChanged
    case sourceCASMismatch
    case targetOccupied
    case evidenceMissing
    case evidenceDiverged
    case targetVerificationFailed
    case lockContended
    case ioFailure
}

struct ProfileInitialAssociationResultV1: Equatable, Sendable {
    let transactionID: UUID
    let cloudAccountID: CloudAccountID
    let installedArtifact: CanonicalProfileEnvelopeArtifactV1
    let targetSnapshot: LocalPlayerProfileSnapshot
}

struct ProfileCommittedAssociationV1: Codable, Equatable, Sendable {
    static let formatVersion = 1

    let formatVersion: Int
    let associationID: UUID
    let committedAt: Date
    let sourceDirectoryPath: String
    let sourceEnvelopeDigest: ProfileHydrationDigest
    let cloudAccountID: CloudAccountID
    let targetPlayerAccountIdentity: PlayerAccountIdentity
    let targetProfileID: UUID
    let targetDirectoryPath: String
    let targetEnvelopeDigest: ProfileHydrationDigest
    let seedPlayerRevision: UInt64
    let seedEconomyRevision: UInt64
    let seedProfileCreatedAt: Date
    let seedInventory: PlayerInventory
    let seedCompletedRuns: [RunID: CompletedRunRecord]
    let seedLedger: [LedgerEntryID: CoinLedgerEntry]
    let seedSettlementReceipts: [RunID: RunSettlementOutcome]
    let seedRewardedRunObservations: [RunID: RewardedRunObservation]

    var sourceDirectoryURL: URL {
        URL(fileURLWithPath: sourceDirectoryPath, isDirectory: true)
            .standardizedFileURL
    }

    var targetDirectoryURL: URL {
        URL(fileURLWithPath: targetDirectoryPath, isDirectory: true)
            .standardizedFileURL
    }

    func validate() throws {
        let derived = CloudAccountDerivedBindings.derive(from: cloudAccountID)
        guard formatVersion == Self.formatVersion,
              associationID != UUID(uuid: (
                0, 0, 0, 0, 0, 0, 0, 0,
                0, 0, 0, 0, 0, 0, 0, 0
              )),
              committedAt.timeIntervalSince1970.isFinite,
              sourceDirectoryURL != targetDirectoryURL,
              sourceDirectoryURL.deletingLastPathComponent()
                == targetDirectoryURL.deletingLastPathComponent(),
              !sourceDirectoryURL.lastPathComponent.isEmpty,
              !targetDirectoryURL.lastPathComponent.isEmpty,
              targetPlayerAccountIdentity == derived.playerAccountIdentity,
              targetProfileID == derived.durableAccountBinding.profileID,
              seedProfileCreatedAt.timeIntervalSince1970.isFinite,
              sourceEnvelopeDigest != targetEnvelopeDigest else {
            throw ProfileInitialAssociationStoreError.invalidJournal
        }
    }
}

fileprivate final class ProfileInitialAssociationVerificationAuthorityV1:
    Sendable
{}

fileprivate final class ProfileInitialAssociationLockResultBox<Output>:
    @unchecked Sendable
{
    var result: Result<Output, Error>?
}

struct ProfileInitialAssociationVerifiedTargetV1: Sendable {
    private let transactionID: UUID
    private let sourceDigest: ProfileHydrationDigest
    private let targetDigest: ProfileHydrationDigest
    private let cloudAccountID: CloudAccountID
    private let sourceDirectoryURL: URL
    private let targetDirectoryURL: URL
    private let authority: ProfileInitialAssociationVerificationAuthorityV1

    fileprivate init(
        journal: ProfileInitialAssociationJournalV1,
        installedArtifact: CanonicalProfileEnvelopeArtifactV1,
        authority: ProfileInitialAssociationVerificationAuthorityV1
    ) {
        transactionID = journal.transactionID
        sourceDigest = journal.sourceEnvelopeDigest
        targetDigest = installedArtifact.digest
        cloudAccountID = journal.cloudAccountID
        sourceDirectoryURL = journal.sourceDirectoryURL
        targetDirectoryURL = journal.targetDirectoryURL
        self.authority = authority
    }

    func authorizes(
        _ capability: LocalProfileInitialAssociationCapabilityV1
    ) -> Bool {
        transactionID == capability.transactionID
            && sourceDigest == capability.sourceArtifact.digest
            && cloudAccountID == capability.targetCloudAccountID
            && sourceDirectoryURL == capability.sourceDirectoryURL
            && targetDirectoryURL == capability.targetDirectoryURL
            && targetDigest != sourceDigest
    }
}

/// A two-directory, crash-recoverable ownership transition. Journal evidence
/// is mirrored into both explicit account directories before target writes;
/// the exact local primary and backup are never modified. The target primary
/// and backup are both installed and reload-verified through an account-bound
/// repository before the local repository is invalidated and evidence removed.
actor ProfileInitialAssociationStoreV1 {
    private let verificationAuthority =
        ProfileInitialAssociationVerificationAuthorityV1()
    private let fileSystem: any ProfileHydrationFileSystem
    private let migrator: any PlayerProfileMigrating
    private let catalog: LaunchCatalog
    private let limits: ProfileHydrationLimits

    init(
        fileSystem: any ProfileHydrationFileSystem =
            FoundationProfileHydrationFileSystem(),
        migrator: any PlayerProfileMigrating = PlayerProfileMigrator(),
        catalog: LaunchCatalog = .approved,
        limits: ProfileHydrationLimits = .production
    ) {
        self.fileSystem = fileSystem
        self.migrator = migrator
        self.catalog = catalog
        self.limits = limits
    }

    func associate(
        journal: ProfileInitialAssociationJournalV1,
        capability: LocalProfileInitialAssociationCapabilityV1,
        sourceRepository: LocalPlayerProfileRepository,
        targetRepository: LocalPlayerProfileRepository,
        now: Date = Date()
    ) async throws -> ProfileInitialAssociationResultV1 {
        try validate(journal, capability: capability)
        try admitOrReconcile(journal)
        try installTarget(journal)

        let snapshot: LocalPlayerProfileSnapshot
        let installed: CanonicalProfileEnvelopeArtifactV1
        do {
            snapshot = try await targetRepository.load(
                at: now,
                newProfileID: CloudAccountDerivedBindings.derive(
                    from: journal.cloudAccountID
                ).durableAccountBinding.profileID
            )
            let source = try await targetRepository.hydrationSource(
                session: snapshot.session
            )
            let decoded = try migrator.decodeArtifact(source.exactEnvelopeBytes)
            installed = try migrator.canonicalArtifact(
                for: decoded.document,
                savedAt: decoded.savedAt
            )
            guard installed.exactBytes == journal.candidateEnvelope,
                  installed.digest == journal.candidateEnvelopeDigest else {
                throw ProfileInitialAssociationStoreError
                    .targetVerificationFailed
            }
        } catch let error as ProfileInitialAssociationStoreError {
            throw error
        } catch {
            throw ProfileInitialAssociationStoreError.targetVerificationFailed
        }

        let committedAssociation = ProfileCommittedAssociationV1(
            formatVersion: ProfileCommittedAssociationV1.formatVersion,
            associationID: journal.transactionID,
            committedAt: now,
            sourceDirectoryPath: journal.sourceDirectoryURL.path,
            sourceEnvelopeDigest: journal.sourceEnvelopeDigest,
            cloudAccountID: journal.cloudAccountID,
            targetPlayerAccountIdentity:
                installed.document.accountIdentity,
            targetProfileID: installed.document.player.profileID,
            targetDirectoryPath: journal.targetDirectoryURL.path,
            targetEnvelopeDigest: installed.digest,
            seedPlayerRevision: installed.document.player.revision,
            seedEconomyRevision: installed.document.economyRevision,
            seedProfileCreatedAt: installed.document.player.createdAt,
            seedInventory: installed.document.player.inventory,
            seedCompletedRuns: installed.document.player.completedRuns,
            seedLedger: installed.document.player.ledger,
            seedSettlementReceipts: installed.document.settlementReceipts,
            seedRewardedRunObservations:
                installed.document.rewardedRunObservations ?? [:]
        )
        try writeCommittedAssociation(
            committedAssociation,
            journal: journal
        )
        let verifiedTarget = ProfileInitialAssociationVerifiedTargetV1(
            journal: journal,
            installedArtifact: installed,
            authority: verificationAuthority
        )
        try await sourceRepository.completeInitialAssociation(
            capability,
            verifiedTarget: verifiedTarget
        )
        try removeEvidenceAfterVerification(journal)
        return ProfileInitialAssociationResultV1(
            transactionID: journal.transactionID,
            cloudAccountID: journal.cloudAccountID,
            installedArtifact: installed,
            targetSnapshot: snapshot
        )
    }

    func committedAssociation(
        sourceDirectoryURL: URL
    ) throws -> ProfileCommittedAssociationV1? {
        let source = sourceDirectoryURL.standardizedFileURL
        let urls = committedAssociationURLs(source: source)
        var initial: [ProfileCommittedAssociationV1] = []
        do {
            try fileSystem.withExclusiveLock(
                at: source.appendingPathComponent(
                    "player-profile-transaction.lock"
                )
            ) {
                initial = try urls.compactMap(readCommittedAssociationIfPresent)
            }
        } catch ProfileHydrationFileSystemError.lockContended {
            throw ProfileInitialAssociationStoreError.lockContended
        } catch let error as ProfileInitialAssociationStoreError {
            throw error
        } catch {
            throw ProfileInitialAssociationStoreError.ioFailure
        }
        guard let binding = initial.first else { return nil }
        guard initial.allSatisfy({ $0 == binding }),
              binding.sourceDirectoryURL == source else {
            throw ProfileInitialAssociationStoreError.evidenceDiverged
        }
        try binding.validate()
        return try withBothLocks(
            source: source,
            target: binding.targetDirectoryURL
        ) {
            let observed = try urls.compactMap(
                readCommittedAssociationIfPresent
            )
            guard !observed.isEmpty,
                  observed.allSatisfy({ $0 == binding }) else {
                throw ProfileInitialAssociationStoreError.evidenceDiverged
            }
            try prepareCommittedAssociationForTargetLoad(binding)
            let encoded = try canonicalCommittedAssociationData(binding)
            for url in urls where try fileSystem.itemStatus(at: url) == .missing {
                try fileSystem.writeAtomicallyDurably(encoded, to: url)
            }
            return binding
        }
    }

    func reopenCommittedAssociation(
        _ binding: ProfileCommittedAssociationV1,
        expectedAccountID: CloudAccountID,
        sourceRepository: LocalPlayerProfileRepository,
        targetRepository: LocalPlayerProfileRepository,
        at date: Date = Date()
    ) async throws -> ProfileInitialAssociationResultV1 {
        guard binding.cloudAccountID == expectedAccountID else {
            throw ProfileInitialAssociationStoreError.accountChanged
        }
        let current = try committedAssociation(
            sourceDirectoryURL: binding.sourceDirectoryURL
        )
        guard current == binding else {
            throw ProfileInitialAssociationStoreError.evidenceDiverged
        }
        let snapshot = try await targetRepository.load(
            at: date,
            newProfileID: binding.targetProfileID
        )
        let source = try await targetRepository.hydrationSource(
            session: snapshot.session
        )
        let decoded = try migrator.decodeArtifact(source.exactEnvelopeBytes)
        let installed = try migrator.canonicalArtifact(
            for: decoded.document,
            savedAt: decoded.savedAt
        )
        guard installed.document.accountIdentity
                == binding.targetPlayerAccountIdentity,
              installed.document.player.profileID == binding.targetProfileID else {
            throw ProfileInitialAssociationStoreError.targetVerificationFailed
        }
        try withBothLocks(
            source: binding.sourceDirectoryURL,
            target: binding.targetDirectoryURL
        ) {
            try verifyCommittedAssociation(binding)
        }
        await sourceRepository.invalidateForAccountSwitch()
        try cleanupRecoveredEvidence(binding)
        return ProfileInitialAssociationResultV1(
            transactionID: binding.associationID,
            cloudAccountID: binding.cloudAccountID,
            installedArtifact: installed,
            targetSnapshot: snapshot
        )
    }

    /// Startup recovery accepts either mirrored journal copy, but never chooses
    /// between different valid intents. The caller reconstructs account-bound
    /// repositories and re-enters `associate` with the recovered journal.
    func recoverableJournal(
        sourceDirectoryURL: URL,
        targetDirectoryURL: URL
    ) throws -> ProfileInitialAssociationJournalV1? {
        let probe = evidenceURLs(
            source: sourceDirectoryURL.standardizedFileURL,
            target: targetDirectoryURL.standardizedFileURL
        )
        return try withBothLocks(
            source: sourceDirectoryURL,
            target: targetDirectoryURL
        ) {
            let decoded = try probe.compactMap(readJournalIfPresent)
            guard let first = decoded.first else { return nil }
            guard decoded.allSatisfy({ $0 == first }) else {
                throw ProfileInitialAssociationStoreError.evidenceDiverged
            }
            try first.validate(
                migrator: migrator,
                catalog: catalog,
                limits: limits
            )
            return first
        }
    }

    private func validate(
        _ journal: ProfileInitialAssociationJournalV1,
        capability: LocalProfileInitialAssociationCapabilityV1
    ) throws {
        try journal.validate(
            migrator: migrator,
            catalog: catalog,
            limits: limits
        )
        guard capability.sourceDirectoryURL == journal.sourceDirectoryURL,
              capability.transactionID == journal.transactionID,
              capability.targetDirectoryURL == journal.targetDirectoryURL,
              capability.targetCloudAccountID == journal.cloudAccountID,
              capability.sourceArtifact.exactBytes == journal.sourceEnvelope,
              capability.sourceArtifact.digest == journal.sourceEnvelopeDigest,
              capability.sourceSession.accountIdentity
                == journal.sourceSessionAccountIdentity,
              capability.sourceSession.nonce == journal.sourceSessionNonce,
              capability.sourceSession.profileID == journal.sourceProfileID else {
            throw ProfileInitialAssociationStoreError.capabilityMismatch
        }
    }

    private nonisolated func admitOrReconcile(
        _ journal: ProfileInitialAssociationJournalV1
    ) throws {
        try withBothLocks(
            source: journal.sourceDirectoryURL,
            target: journal.targetDirectoryURL
        ) {
            guard try committedAssociationURLs(
                source: journal.sourceDirectoryURL
            ).allSatisfy({
                try fileSystem.itemStatus(at: $0) == .missing
            }) else {
                throw ProfileInitialAssociationStoreError.accountChanged
            }
            try prepareExactSourceBarrier(journal)
            let urls = evidenceURLs(
                source: journal.sourceDirectoryURL,
                target: journal.targetDirectoryURL
            )
            let existing = try urls.compactMap(readJournalIfPresent)
            guard existing.allSatisfy({ $0 == journal }) else {
                throw ProfileInitialAssociationStoreError.evidenceDiverged
            }
            let encoded = try canonicalJournalData(journal)
            for url in urls where try fileSystem.itemStatus(at: url) == .missing {
                try fileSystem.writeAtomicallyDurably(encoded, to: url)
            }
            let verified = try urls.compactMap(readJournalIfPresent)
            guard verified.count == urls.count,
                  verified.allSatisfy({ $0 == journal }) else {
                throw ProfileInitialAssociationStoreError.evidenceMissing
            }
        }
    }

    private nonisolated func installTarget(
        _ journal: ProfileInitialAssociationJournalV1
    ) throws {
        try withBothLocks(
            source: journal.sourceDirectoryURL,
            target: journal.targetDirectoryURL
        ) {
            try requireExactSource(journal)
            try requireExactEvidence(journal)
            let target = ProfileStorageLocations(
                directoryURL: journal.targetDirectoryURL
            )
            for url in [target.backupURL, target.primaryURL] {
                switch try fileSystem.itemStatus(at: url) {
                case .missing:
                    try fileSystem.writeAtomicallyDurably(
                        journal.candidateEnvelope,
                        to: url
                    )
                case .present:
                    guard try boundedRead(url) == journal.candidateEnvelope else {
                        throw ProfileInitialAssociationStoreError.targetOccupied
                    }
                }
            }
            guard try boundedRead(target.primaryURL) == journal.candidateEnvelope,
                  try boundedRead(target.backupURL) == journal.candidateEnvelope else {
                throw ProfileInitialAssociationStoreError
                    .targetVerificationFailed
            }
            let decoded = try migrator.decodeArtifact(journal.candidateEnvelope)
            let candidate = try migrator.canonicalArtifact(
                for: decoded.document,
                savedAt: decoded.savedAt
            )
            do {
                try AtomicProfileFileStore(
                    directoryURL: journal.targetDirectoryURL,
                    migrator: migrator,
                    limits: limits,
                    fileSystem: fileSystem
                ).installLineageProtectionUnderExternalLock(
                    cloudAccountID: journal.cloudAccountID,
                    artifact: candidate,
                    catalog: catalog
                )
            } catch {
                throw ProfileInitialAssociationStoreError
                    .targetVerificationFailed
            }
            try requireExactSource(journal)
        }
    }

    private nonisolated func removeEvidenceAfterVerification(
        _ journal: ProfileInitialAssociationJournalV1
    ) throws {
        try withBothLocks(
            source: journal.sourceDirectoryURL,
            target: journal.targetDirectoryURL
        ) {
            try requireExactSource(journal)
            let target = ProfileStorageLocations(
                directoryURL: journal.targetDirectoryURL
            )
            guard try boundedRead(target.primaryURL) == journal.candidateEnvelope,
                  try boundedRead(target.backupURL) == journal.candidateEnvelope else {
                throw ProfileInitialAssociationStoreError
                    .targetVerificationFailed
            }
            try requireExactEvidence(journal)
            for url in evidenceURLs(
                source: journal.sourceDirectoryURL,
                target: journal.targetDirectoryURL
            ) {
                try fileSystem.removeItemDurably(at: url)
            }
        }
    }

    private nonisolated func writeCommittedAssociation(
        _ binding: ProfileCommittedAssociationV1,
        journal: ProfileInitialAssociationJournalV1
    ) throws {
        try binding.validate()
        try withBothLocks(
            source: journal.sourceDirectoryURL,
            target: journal.targetDirectoryURL
        ) {
            try requireExactSource(journal)
            try requireExactEvidence(journal)
            let target = ProfileStorageLocations(
                directoryURL: journal.targetDirectoryURL
            )
            guard try boundedRead(target.primaryURL)
                    == journal.candidateEnvelope,
                  try boundedRead(target.backupURL)
                    == journal.candidateEnvelope else {
                throw ProfileInitialAssociationStoreError
                    .targetVerificationFailed
            }
            let encoded = try canonicalCommittedAssociationData(binding)
            let urls = committedAssociationURLs(
                source: journal.sourceDirectoryURL
            )
            let existing = try urls.compactMap(
                readCommittedAssociationIfPresent
            )
            guard existing.allSatisfy({ $0 == binding }) else {
                throw ProfileInitialAssociationStoreError.evidenceDiverged
            }
            for url in urls where try fileSystem.itemStatus(at: url) == .missing {
                try fileSystem.writeAtomicallyDurably(encoded, to: url)
            }
            guard try urls.compactMap(readCommittedAssociationIfPresent).count
                    == urls.count else {
                throw ProfileInitialAssociationStoreError.evidenceMissing
            }
        }
    }

    private nonisolated func verifyCommittedAssociation(
        _ binding: ProfileCommittedAssociationV1
    ) throws {
        try repairCommittedSourceArchive(binding)
        let target = ProfileStorageLocations(
            directoryURL: binding.targetDirectoryURL
        )
        let latest = try requiredCommittedTargetLineage(binding)
        guard try boundedRead(target.primaryURL) == latest.exactBytes,
              try boundedRead(target.backupURL) == latest.exactBytes else {
            throw ProfileInitialAssociationStoreError.targetVerificationFailed
        }
    }

    /// The committed source digest is the recovery authority for the preserved
    /// local archive. One matching redundant copy repairs its peer beneath the
    /// same two-directory lock; no matching copy is an unrecoverable CAS loss.
    private nonisolated func repairCommittedSourceArchive(
        _ binding: ProfileCommittedAssociationV1
    ) throws {
        let source = ProfileStorageLocations(
            directoryURL: binding.sourceDirectoryURL
        )
        let urls = [source.primaryURL, source.backupURL]
        let copies: [Data?] = try urls.map { url in
            guard try fileSystem.itemStatus(at: url) == .present else {
                return nil
            }
            return try? boundedRead(url)
        }
        let matching = copies.compactMap { data -> Data? in
            guard let data,
                  ProfileHydrationDigest.envelopeBytes(data)
                    == binding.sourceEnvelopeDigest else { return nil }
            return data
        }
        guard let authoritative = matching.first else {
            throw ProfileInitialAssociationStoreError.sourceCASMismatch
        }
        for (url, copy) in zip(urls, copies) where copy != authoritative {
            try fileSystem.writeAtomicallyDurably(authoritative, to: url)
        }
        guard try urls.allSatisfy({ url in
            ProfileHydrationDigest.envelopeBytes(try boundedRead(url))
                == binding.sourceEnvelopeDigest
        }) else {
            throw ProfileInitialAssociationStoreError.sourceCASMismatch
        }
    }

    /// Before the account repository has loaded, accept one valid bound target
    /// copy so its normal primary/backup recovery can repair the other. Two
    /// valid copies that name different owners are never resolved by choosing
    /// one, even if one happens to match the marker.
    private nonisolated func prepareCommittedAssociationForTargetLoad(
        _ binding: ProfileCommittedAssociationV1
    ) throws {
        try repairCommittedSourceArchive(binding)
        let target = ProfileStorageLocations(
            directoryURL: binding.targetDirectoryURL
        )
        let latest = try requiredCommittedTargetLineage(binding)
        let documents = try [target.primaryURL, target.backupURL].compactMap {
            try validTargetDocumentIfPresent(at: $0)
        }
        guard !documents.isEmpty,
              documents.allSatisfy({
                  isCommittedTargetDescendant($0, binding: binding)
              }) else {
            throw ProfileInitialAssociationStoreError.targetVerificationFailed
        }
        _ = latest
    }

    private nonisolated func requiredCommittedTargetLineage(
        _ binding: ProfileCommittedAssociationV1
    ) throws -> CanonicalProfileEnvelopeArtifactV1 {
        do {
            let artifact = try AtomicProfileFileStore(
                directoryURL: binding.targetDirectoryURL,
                migrator: migrator,
                limits: limits,
                fileSystem: fileSystem
            ).requiredLineageHighWatermarkUnderExternalLock(catalog: catalog)
            guard isCommittedTargetDescendant(
                artifact.document,
                binding: binding
            ) else {
                throw ProfileInitialAssociationStoreError
                    .targetVerificationFailed
            }
            return artifact
        } catch let error as ProfileInitialAssociationStoreError {
            throw error
        } catch {
            throw ProfileInitialAssociationStoreError.targetVerificationFailed
        }
    }

    private nonisolated func validTargetDocumentIfPresent(
        at url: URL
    ) throws -> LocalPlayerDocumentV1? {
        guard try fileSystem.itemStatus(at: url) == .present,
              let data = try? boundedRead(url),
              let decoded = try? migrator.decodeArtifact(data),
              (try? PlayerProfileValidator.validate(
                  decoded.document,
                  catalog: catalog
              )) != nil else { return nil }
        return decoded.document
    }

    private nonisolated func requireBoundTarget(
        at url: URL,
        binding: ProfileCommittedAssociationV1
    ) throws {
        do {
            let decoded = try migrator.decodeArtifact(try boundedRead(url))
            try PlayerProfileValidator.validate(decoded.document, catalog: catalog)
            guard isCommittedTargetDescendant(
                decoded.document,
                binding: binding
            ) else {
                throw ProfileInitialAssociationStoreError
                    .targetVerificationFailed
            }
        } catch let error as ProfileInitialAssociationStoreError {
            throw error
        } catch {
            throw ProfileInitialAssociationStoreError.targetVerificationFailed
        }
    }

    /// A marker does not pin mutable settings, but it does pin the immutable
    /// seed lineage. Exact original bytes are accepted directly; an evolved
    /// profile must retain every seed run, ledger entry, settlement receipt,
    /// rewarded-run observation, and ownership fact while never rolling either
    /// revision backward.
    private nonisolated func isCommittedTargetDescendant(
        _ document: LocalPlayerDocumentV1,
        binding: ProfileCommittedAssociationV1
    ) -> Bool {
        guard document.accountIdentity == binding.targetPlayerAccountIdentity,
              document.player.profileID == binding.targetProfileID,
              document.player.createdAt == binding.seedProfileCreatedAt,
              document.player.revision >= binding.seedPlayerRevision,
              document.economyRevision >= binding.seedEconomyRevision,
              document.player.inventory.ownedTeamIDs
                .isSuperset(of: binding.seedInventory.ownedTeamIDs),
              document.player.inventory.ownedJerseyIDs
                .isSuperset(of: binding.seedInventory.ownedJerseyIDs),
              document.player.inventory.ownedFootballIDs
                .isSuperset(of: binding.seedInventory.ownedFootballIDs),
              binding.seedCompletedRuns.allSatisfy({
                  document.player.completedRuns[$0.key] == $0.value
              }),
              binding.seedLedger.allSatisfy({
                  document.player.ledger[$0.key] == $0.value
              }),
              binding.seedSettlementReceipts.allSatisfy({
                  document.settlementReceipts[$0.key] == $0.value
              }),
              binding.seedRewardedRunObservations.allSatisfy({
                  document.rewardedRunObservations?[$0.key] == $0.value
              }) else { return false }
        return true
    }

    private nonisolated func cleanupRecoveredEvidence(
        _ binding: ProfileCommittedAssociationV1
    ) throws {
        try withBothLocks(
            source: binding.sourceDirectoryURL,
            target: binding.targetDirectoryURL
        ) {
            try verifyCommittedAssociation(binding)
            let urls = evidenceURLs(
                source: binding.sourceDirectoryURL,
                target: binding.targetDirectoryURL
            )
            let observed = try urls.compactMap(readJournalIfPresent)
            guard observed.isEmpty || observed.allSatisfy({
                $0.transactionID == binding.associationID
                    && $0.cloudAccountID == binding.cloudAccountID
                    && $0.sourceEnvelopeDigest
                        == binding.sourceEnvelopeDigest
                    && $0.candidateEnvelopeDigest
                        == binding.targetEnvelopeDigest
            }) else {
                throw ProfileInitialAssociationStoreError.evidenceDiverged
            }
            for url in urls {
                try fileSystem.removeItemDurably(at: url)
            }
        }
    }

    private nonisolated func committedAssociationURLs(source: URL) -> [URL] {
        let directory = source.appendingPathComponent(
            "ProfileCommittedAssociation",
            isDirectory: true
        )
        return [
            directory.appendingPathComponent("association.json"),
            directory.appendingPathComponent("association.backup.json"),
        ]
    }

    private nonisolated func readCommittedAssociationIfPresent(
        _ url: URL
    ) throws -> ProfileCommittedAssociationV1? {
        guard try fileSystem.itemStatus(at: url) == .present else { return nil }
        do {
            let value = try JSONDecoder().decode(
                ProfileCommittedAssociationV1.self,
                from: boundedRead(url)
            )
            try value.validate()
            return value
        } catch let error as ProfileInitialAssociationStoreError {
            throw error
        } catch {
            throw ProfileInitialAssociationStoreError.invalidJournal
        }
    }

    private nonisolated func canonicalCommittedAssociationData(
        _ binding: ProfileCommittedAssociationV1
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(binding)
        guard data.count <= limits.maximumEncodedJournalBytes else {
            throw ProfileInitialAssociationStoreError.invalidJournal
        }
        return data
    }

    private nonisolated func requireExactSource(
        _ journal: ProfileInitialAssociationJournalV1
    ) throws {
        let source = ProfileStorageLocations(
            directoryURL: journal.sourceDirectoryURL
        )
        guard try boundedRead(source.primaryURL) == journal.sourceEnvelope,
              try boundedRead(source.backupURL) == journal.sourceEnvelope else {
            throw ProfileInitialAssociationStoreError.sourceCASMismatch
        }
    }

    private nonisolated func prepareExactSourceBarrier(
        _ journal: ProfileInitialAssociationJournalV1
    ) throws {
        let source = ProfileStorageLocations(
            directoryURL: journal.sourceDirectoryURL
        )
        guard try boundedRead(source.primaryURL) == journal.sourceEnvelope else {
            throw ProfileInitialAssociationStoreError.sourceCASMismatch
        }
        let hydration = ProfileHydrationTransactionLocations(
            profileDirectoryURL: journal.sourceDirectoryURL
        )
        guard try fileSystem.itemStatus(at: hydration.journalPrimaryURL)
                == .missing,
              try fileSystem.itemStatus(at: hydration.journalBackupURL) == .missing
        else {
            throw ProfileInitialAssociationStoreError.sourceCASMismatch
        }
        if try fileSystem.itemStatus(at: source.backupURL) == .missing
            || (try boundedRead(source.backupURL)) != journal.sourceEnvelope
        {
            try fileSystem.writeAtomicallyDurably(
                journal.sourceEnvelope,
                to: source.backupURL
            )
        }
        try requireExactSource(journal)
    }

    private nonisolated func requireExactEvidence(
        _ journal: ProfileInitialAssociationJournalV1
    ) throws {
        let journals = try evidenceURLs(
            source: journal.sourceDirectoryURL,
            target: journal.targetDirectoryURL
        ).compactMap(readJournalIfPresent)
        guard journals.count == 4,
              journals.allSatisfy({ $0 == journal }) else {
            throw ProfileInitialAssociationStoreError.evidenceMissing
        }
    }

    private nonisolated func evidenceURLs(source: URL, target: URL) -> [URL] {
        [source, target].flatMap { directory in
            let evidence = directory.appendingPathComponent(
                "ProfileInitialAssociationTransaction",
                isDirectory: true
            )
            return [
                evidence.appendingPathComponent("association-journal.json"),
                evidence.appendingPathComponent(
                    "association-journal.backup.json"
                ),
            ]
        }
    }

    private nonisolated func readJournalIfPresent(
        _ url: URL
    ) throws -> ProfileInitialAssociationJournalV1? {
        guard try fileSystem.itemStatus(at: url) == .present else { return nil }
        let data = try boundedRead(url)
        do {
            return try JSONDecoder().decode(
                ProfileInitialAssociationJournalV1.self,
                from: data
            )
        } catch {
            throw ProfileInitialAssociationStoreError.invalidJournal
        }
    }

    private nonisolated func canonicalJournalData(
        _ journal: ProfileInitialAssociationJournalV1
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(journal)
        guard data.count <= limits.maximumEncodedJournalBytes else {
            throw ProfileInitialAssociationStoreError.invalidJournal
        }
        return data
    }

    private nonisolated func boundedRead(_ url: URL) throws -> Data {
        guard try fileSystem.itemStatus(at: url) == .present else {
            throw ProfileInitialAssociationStoreError.ioFailure
        }
        let size = try fileSystem.fileSize(at: url)
        guard size >= 0,
              size <= max(
                limits.maximumEncodedJournalBytes,
                limits.maximumProfileEnvelopeBytes
              ) else {
            throw ProfileInitialAssociationStoreError.ioFailure
        }
        return try fileSystem.read(from: url)
    }

    private nonisolated func withBothLocks<Output: Sendable>(
        source: URL,
        target: URL,
        perform: @Sendable () throws -> Output
    ) throws -> Output {
        let source = source.standardizedFileURL
        let target = target.standardizedFileURL
        guard source != target else {
            throw ProfileInitialAssociationStoreError.invalidJournal
        }
        let ordered = [source, target].sorted {
            $0.path.utf8.lexicographicallyPrecedes($1.path.utf8)
        }
        let firstLock = ordered[0].appendingPathComponent(
            "player-profile-transaction.lock"
        )
        let secondLock = ordered[1].appendingPathComponent(
            "player-profile-transaction.lock"
        )
        let box = ProfileInitialAssociationLockResultBox<Output>()
        do {
            try fileSystem.withExclusiveLock(at: firstLock) {
                try fileSystem.withExclusiveLock(at: secondLock) {
                    box.result = Result { try perform() }
                }
            }
        } catch ProfileHydrationFileSystemError.lockContended {
            throw ProfileInitialAssociationStoreError.lockContended
        } catch let error as ProfileInitialAssociationStoreError {
            throw error
        } catch {
            throw ProfileInitialAssociationStoreError.ioFailure
        }
        guard let result = box.result else {
            throw ProfileInitialAssociationStoreError.ioFailure
        }
        return try result.get()
    }
}

private extension AtomicProfileFileStore {
    enum ProfileReadError: Error {
        case invalid
    }

    enum ProfileDataRead {
        case data(Data)
        case state(ProfileEnvelopeCopyState)

        var copyState: ProfileEnvelopeCopyState {
            switch self {
            case let .data(data):
                .unexpected(.envelopeBytes(data))
            case let .state(state):
                state
            }
        }
    }

    enum BackupRelationship {
        case sameDocument
        case strictlyOlder
    }

    struct StoredProfile {
        let rawBytes: Data
        let artifact: CanonicalProfileEnvelopeArtifactV1
    }

    func attempt(
        _ intent: ExactProfileReplacementIntentV1,
        catalog: LaunchCatalog
    ) throws -> ExactProfileReplacementAttemptResultV1 {
        // Revalidate before acquiring the lock so malformed, oversized, or
        // cross-profile intent data can never cause file-system I/O.
        try validateReplacementIntent(intent, catalog: catalog)

        return try withLock {
            try assertHydrationRecoveryIsClear()
            try prepareDirectories()
            let currentRead = try readProfileData(from: locations.primaryURL)
            guard case let .data(currentBytes) = currentRead else {
                throw AtomicProfileFileStoreError.sourceEnvelopeCASMismatch(
                    expected: intent.source.digest,
                    actual: currentRead.copyState
                )
            }

            if currentBytes == intent.source.exactBytes {
                // Until this exact predecessor copy is durable, all failures
                // are definitive and the source remains authoritative.
                try writeAndVerify(
                    intent.source.exactBytes,
                    to: locations.backupURL
                )

                // The durable latest-envelope authority commits before the
                // mutable primary. If the following rename is ambiguous, load
                // can replay these exact sealed bytes; it can never fall back
                // to the now-stale predecessor backup.
                let protectedLineageAdvanced = try advanceLineageHighWatermark(
                    to: intent.candidate,
                    catalog: catalog
                )

                // Invoking the candidate write crosses the uncertainty
                // boundary. A rename may have installed it even if a later
                // verification or parent-directory sync reports failure.
                do {
                    try writeAndVerify(
                        intent.candidate.exactBytes,
                        to: locations.primaryURL
                    )
                    return .committed(intent.candidate)
                } catch AtomicProfileFileStoreError.atomicWriteOutcomeUnknown {
                    return .reconciliationRequired(intent)
                } catch {
                    guard !protectedLineageAdvanced else {
                        return .reconciliationRequired(intent)
                    }
                    throw error
                }
            }

            if currentBytes == intent.candidate.exactBytes {
                // The candidate may be the result of a prior attempt whose
                // response was lost. Rebuild only the exact predecessor backup
                // and re-read the candidate; never rewrite the primary here.
                do {
                    try advanceLineageHighWatermark(
                        to: intent.candidate,
                        catalog: catalog
                    )
                    try writeAndVerify(
                        intent.source.exactBytes,
                        to: locations.backupURL
                    )
                    guard case let .data(verifiedCandidate) = try readProfileData(
                        from: locations.primaryURL
                    ), verifiedCandidate == intent.candidate.exactBytes else {
                        throw AtomicProfileFileStoreError.writeVerificationFailed
                    }
                    return .committed(intent.candidate)
                } catch {
                    return .reconciliationRequired(intent)
                }
            }

            throw AtomicProfileFileStoreError.sourceEnvelopeCASMismatch(
                expected: intent.source.digest,
                actual: .unexpected(.envelopeBytes(currentBytes))
            )
        }
    }

    func validateReplacementIntent(
        _ intent: ExactProfileReplacementIntentV1,
        catalog: LaunchCatalog
    ) throws {
        guard intent.standardizedProfileDirectoryURL
            == locations.directoryURL.standardizedFileURL else {
            throw AtomicProfileFileStoreError.invalidReplacementIntent
        }
        try validateCanonicalArtifact(intent.source, catalog: catalog)
        try validateCanonicalArtifact(intent.candidate, catalog: catalog)
        guard intent.source.document.accountIdentity
                == intent.candidate.document.accountIdentity,
              intent.source.document.player.profileID
                == intent.candidate.document.player.profileID else {
            throw AtomicProfileFileStoreError.invalidReplacementIntent
        }
    }

    func validateCanonicalArtifact(
        _ artifact: CanonicalProfileEnvelopeArtifactV1,
        catalog: LaunchCatalog
    ) throws {
        guard artifact.exactBytes.count <= limits.maximumProfileEnvelopeBytes else {
            throw AtomicProfileFileStoreError.profileEnvelopeTooLarge(
                actual: artifact.exactBytes.count,
                maximum: limits.maximumProfileEnvelopeBytes
            )
        }
        guard artifact.digest == .envelopeBytes(artifact.exactBytes) else {
            throw AtomicProfileFileStoreError.invalidReplacementIntent
        }
        try PlayerProfileValidator.validate(artifact.document, catalog: catalog)
        let canonical = try migrator.canonicalArtifact(
            for: artifact.document,
            savedAt: artifact.savedAt
        )
        guard canonical == artifact else {
            throw AtomicProfileFileStoreError.invalidReplacementIntent
        }
    }

    var lineageHighWatermarkURL: URL {
        locations.directoryURL
            .appendingPathComponent("ProfileLineage", isDirectory: true)
            .appendingPathComponent("latest-envelope.json")
    }

    var lineageProtectionMarkerURL: URL {
        locations.directoryURL
            .appendingPathComponent("ProfileLineage", isDirectory: true)
            .appendingPathComponent("required-association.json")
    }

    func readLineageProtectionMarker()
        throws -> ProfileLineageProtectionMarkerV1?
    {
        guard try itemIsPresent(at: lineageProtectionMarkerURL) else {
            return nil
        }
        let encoded: Data
        do {
            let size = try fileSystem.fileSize(at: lineageProtectionMarkerURL)
            guard size >= 0, size <= limits.maximumEncodedJournalBytes else {
                throw AtomicProfileFileStoreError.invalidReplacementIntent
            }
            encoded = try fileSystem.read(from: lineageProtectionMarkerURL)
        } catch {
            throw AtomicProfileFileStoreError.invalidReplacementIntent
        }
        let marker: ProfileLineageProtectionMarkerV1
        do {
            marker = try JSONDecoder().decode(
                ProfileLineageProtectionMarkerV1.self,
                from: encoded
            )
        } catch {
            throw AtomicProfileFileStoreError.invalidReplacementIntent
        }
        let derived = CloudAccountDerivedBindings.derive(
            from: marker.cloudAccountID
        )
        guard marker.formatVersion
                == ProfileLineageProtectionMarkerV1.formatVersion,
              marker.accountIdentity == derived.playerAccountIdentity,
              marker.profileID == derived.durableAccountBinding.profileID else {
            throw AtomicProfileFileStoreError.invalidReplacementIntent
        }
        return marker
    }

    func requiredProtectedLineage(
        catalog: LaunchCatalog
    ) throws -> CanonicalProfileEnvelopeArtifactV1? {
        guard let marker = try readLineageProtectionMarker() else {
            return nil
        }
        guard let artifact = try readLineageHighWatermark(catalog: catalog),
              artifact.document.accountIdentity == marker.accountIdentity,
              artifact.document.player.profileID == marker.profileID else {
            throw AtomicProfileFileStoreError.invalidReplacementIntent
        }
        try assertProfileCopiesDoNotLead(
            artifact,
            marker: marker,
            catalog: catalog
        )
        return artifact
    }

    func readLineageHighWatermark(
        catalog: LaunchCatalog
    ) throws -> CanonicalProfileEnvelopeArtifactV1? {
        guard try itemIsPresent(at: lineageHighWatermarkURL) else {
            return nil
        }
        let encoded: Data
        do {
            let size = try fileSystem.fileSize(at: lineageHighWatermarkURL)
            guard size >= 0,
                  size <= limits.maximumEncodedJournalBytes else {
                throw AtomicProfileFileStoreError.invalidReplacementIntent
            }
            encoded = try fileSystem.read(from: lineageHighWatermarkURL)
        } catch {
            throw AtomicProfileFileStoreError.invalidReplacementIntent
        }
        let watermark: ProfileLineageHighWatermarkV1
        do {
            watermark = try JSONDecoder().decode(
                ProfileLineageHighWatermarkV1.self,
                from: encoded
            )
        } catch {
            throw AtomicProfileFileStoreError.invalidReplacementIntent
        }
        guard watermark.formatVersion
                == ProfileLineageHighWatermarkV1.formatVersion,
              watermark.envelopeDigest
                == .envelopeBytes(watermark.envelope) else {
            throw AtomicProfileFileStoreError.invalidReplacementIntent
        }
        let decoded = try migrator.decodeArtifact(watermark.envelope)
        let artifact = try migrator.canonicalArtifact(
            for: decoded.document,
            savedAt: decoded.savedAt
        )
        try validateCanonicalArtifact(artifact, catalog: catalog)
        guard artifact.exactBytes == watermark.envelope,
              artifact.digest == watermark.envelopeDigest,
              artifact.document.accountIdentity == watermark.accountIdentity,
              artifact.document.player.profileID == watermark.profileID,
              artifact.document.player.revision == watermark.playerRevision,
              artifact.document.economyRevision
                == watermark.economyRevision else {
            throw AtomicProfileFileStoreError.invalidReplacementIntent
        }
        return artifact
    }

    @discardableResult
    func advanceLineageHighWatermark(
        to candidate: CanonicalProfileEnvelopeArtifactV1,
        catalog: LaunchCatalog
    ) throws -> Bool {
        guard let current = try requiredProtectedLineage(catalog: catalog) else {
            return false
        }
        guard current.document.accountIdentity
                == candidate.document.accountIdentity,
              current.document.player.profileID
                == candidate.document.player.profileID else {
            throw AtomicProfileFileStoreError.invalidReplacementIntent
        }
        try writeLineageHighWatermark(
            candidate,
            catalog: catalog,
            requireExistingProtection: true
        )
        return true
    }

    func writeLineageHighWatermark(
        _ candidate: CanonicalProfileEnvelopeArtifactV1,
        catalog: LaunchCatalog,
        requireExistingProtection: Bool
    ) throws {
        try validateCanonicalArtifact(candidate, catalog: catalog)
        if requireExistingProtection {
            guard let marker = try readLineageProtectionMarker(),
                  marker.accountIdentity == candidate.document.accountIdentity,
                  marker.profileID == candidate.document.player.profileID else {
                throw AtomicProfileFileStoreError.invalidReplacementIntent
            }
        }
        if let current = try readLineageHighWatermark(catalog: catalog) {
            guard current.document.accountIdentity
                    == candidate.document.accountIdentity,
                  current.document.player.profileID
                    == candidate.document.player.profileID,
                  candidate.document.player.revision
                    >= current.document.player.revision,
                  candidate.document.economyRevision
                    >= current.document.economyRevision else {
                throw AtomicProfileFileStoreError.invalidReplacementIntent
            }
            if current == candidate { return }
        }
        let watermark = ProfileLineageHighWatermarkV1(artifact: candidate)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let encoded = try encoder.encode(watermark)
        guard encoded.count <= limits.maximumEncodedJournalBytes else {
            throw AtomicProfileFileStoreError.invalidReplacementIntent
        }
        do {
            try fileSystem.createDirectory(
                at: lineageHighWatermarkURL.deletingLastPathComponent()
            )
            try fileSystem.writeAtomicallyDurably(
                encoded,
                to: lineageHighWatermarkURL
            )
        } catch {
            throw mapped(error)
        }
        guard try readLineageHighWatermark(catalog: catalog) == candidate else {
            throw AtomicProfileFileStoreError.atomicWriteOutcomeUnknown
        }
    }

    func writeLineageProtectionMarkerIfNeeded(
        _ marker: ProfileLineageProtectionMarkerV1
    ) throws {
        if let existing = try readLineageProtectionMarker() {
            guard existing == marker else {
                throw AtomicProfileFileStoreError.invalidReplacementIntent
            }
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let encoded = try encoder.encode(marker)
        guard encoded.count <= limits.maximumEncodedJournalBytes else {
            throw AtomicProfileFileStoreError.invalidReplacementIntent
        }
        do {
            try fileSystem.createDirectory(
                at: lineageProtectionMarkerURL.deletingLastPathComponent()
            )
            try fileSystem.writeAtomicallyDurably(
                encoded,
                to: lineageProtectionMarkerURL
            )
        } catch {
            throw mapped(error)
        }
        guard try readLineageProtectionMarker() == marker else {
            throw AtomicProfileFileStoreError.atomicWriteOutcomeUnknown
        }
    }

    func assertProfileCopiesDoNotLead(
        _ watermark: CanonicalProfileEnvelopeArtifactV1,
        marker: ProfileLineageProtectionMarkerV1,
        catalog: LaunchCatalog
    ) throws {
        for url in [locations.primaryURL, locations.backupURL]
            where try itemIsPresent(at: url)
        {
            guard let stored = try? readValidated(from: url, catalog: catalog)
            else { continue }
            let artifact = stored.artifact
            guard artifact.document.accountIdentity == marker.accountIdentity,
                  artifact.document.player.profileID == marker.profileID else {
                throw AtomicProfileFileStoreError.invalidReplacementIntent
            }
            let playerRevision = artifact.document.player.revision
            let economyRevision = artifact.document.economyRevision
            let watermarkPlayerRevision = watermark.document.player.revision
            let watermarkEconomyRevision = watermark.document.economyRevision
            guard playerRevision <= watermarkPlayerRevision,
                  economyRevision <= watermarkEconomyRevision,
                  playerRevision != watermarkPlayerRevision
                    || economyRevision != watermarkEconomyRevision
                    || artifact == watermark else {
                throw AtomicProfileFileStoreError.invalidReplacementIntent
            }
        }
    }

    func readValidated(
        from url: URL,
        catalog: LaunchCatalog
    ) throws -> StoredProfile {
        let read = try readProfileData(from: url)
        guard case let .data(data) = read else {
            throw ProfileReadError.invalid
        }

        do {
            let decoded = try migrator.decodeArtifact(data)
            try PlayerProfileValidator.validate(decoded.document, catalog: catalog)
            let artifact = try migrator.canonicalArtifact(
                for: decoded.document,
                savedAt: decoded.savedAt
            )
            try validateCanonicalArtifact(artifact, catalog: catalog)
            return StoredProfile(rawBytes: data, artifact: artifact)
        } catch let error as AtomicProfileFileStoreError {
            throw error
        } catch {
            throw ProfileReadError.invalid
        }
    }

    func readProfileData(from url: URL) throws -> ProfileDataRead {
        guard try itemIsPresent(at: url) else {
            return .state(.missing)
        }
        let size: Int
        do {
            size = try fileSystem.fileSize(at: url)
        } catch {
            throw mapped(error)
        }
        guard size >= 0, size <= limits.maximumProfileEnvelopeBytes else {
            return .state(.oversized(max(0, size)))
        }
        let data: Data
        do {
            data = try fileSystem.read(from: url)
        } catch {
            throw mapped(error)
        }
        guard data.count <= limits.maximumProfileEnvelopeBytes else {
            return .state(.oversized(data.count))
        }
        return .data(data)
    }

    func hydrationCopyState(
        at url: URL,
        journal: ProfileHydrationJournalV1
    ) throws -> ProfileHydrationProfileCopyState {
        switch try readProfileData(from: url) {
        case let .data(data):
            if data == journal.candidateProfileEnvelope {
                return .candidate
            }
            if data == journal.sourceProfileEnvelope {
                return .source
            }
            return .unexpected(.envelopeBytes(data))

        case .state(.missing):
            return .missing
        case let .state(.oversized(size)):
            return .oversized(size)
        case let .state(.unexpected(digest)):
            return .unexpected(digest)
        }
    }

    /// Validates both copies before any normalization. A valid divergent backup
    /// is accepted only when it is the same document or a componentwise older
    /// predecessor for the same account/profile.
    func prepareBackup(
        for primary: StoredProfile,
        catalog: LaunchCatalog,
        at date: Date,
        quarantinedURLs: inout [URL]
    ) throws {
        guard try itemIsPresent(at: locations.backupURL) else {
            try writeAndVerify(
                primary.artifact.exactBytes,
                to: locations.backupURL
            )
            return
        }

        let backup: StoredProfile
        do {
            backup = try readValidated(
                from: locations.backupURL,
                catalog: catalog
            )
        } catch ProfileReadError.invalid {
            quarantinedURLs.append(
                try quarantine(locations.backupURL, at: date)
            )
            try writeAndVerify(
                primary.artifact.exactBytes,
                to: locations.backupURL
            )
            return
        }

        switch try backupRelationship(primary: primary, backup: backup) {
        case .sameDocument:
            if backup.rawBytes != primary.artifact.exactBytes {
                try writeAndVerify(
                    primary.artifact.exactBytes,
                    to: locations.backupURL
                )
            }
        case .strictlyOlder:
            // A candidate-primary rename from a prior process can be visible
            // even when its parent-directory fsync reported an unknown result.
            // Replacing the exact predecessor backup and syncing this same
            // directory establishes a durability barrier for both names before
            // the candidate may be published by a reconstructed repository.
            try writeAndVerify(
                backup.artifact.exactBytes,
                to: locations.backupURL
            )
            guard case let .data(verifiedPrimaryBytes) = try readProfileData(
                from: locations.primaryURL
            ), verifiedPrimaryBytes == primary.rawBytes else {
                throw AtomicProfileFileStoreError.writeVerificationFailed
            }
        }
    }

    func backupRelationship(
        primary: StoredProfile,
        backup: StoredProfile
    ) throws -> BackupRelationship {
        let primaryDocument = primary.artifact.document
        let backupDocument = backup.artifact.document
        if backupDocument == primaryDocument {
            return .sameDocument
        }

        guard backupDocument.accountIdentity == primaryDocument.accountIdentity,
              backupDocument.player.profileID == primaryDocument.player.profileID,
              backupDocument.player.revision <= primaryDocument.player.revision,
              backupDocument.economyRevision <= primaryDocument.economyRevision,
              backupDocument.player.revision < primaryDocument.player.revision
                || backupDocument.economyRevision
                    < primaryDocument.economyRevision else {
            throw AtomicProfileFileStoreError.backupEnvelopeConflict(
                primary: primary.artifact.digest,
                backup: backup.artifact.digest
            )
        }
        return .strictlyOlder
    }

    func assertHydrationRecoveryIsClear() throws {
        if try itemIsPresent(at: transactionLocations.journalPrimaryURL)
            || itemIsPresent(at: transactionLocations.journalBackupURL) {
            throw AtomicProfileFileStoreError.hydrationRecoveryRequired
        }
        for index in 0 ..< limits.maximumQuarantineFiles {
            if try itemIsPresent(at: transactionLocations.quarantineSlotURL(index)) {
                throw AtomicProfileFileStoreError.hydrationRecoveryRequired
            }
        }
    }

    func prepareDirectories() throws {
        do {
            try fileSystem.createDirectory(at: locations.directoryURL)
        } catch {
            throw mapped(error)
        }
    }

    func itemIsPresent(at url: URL) throws -> Bool {
        do {
            return try fileSystem.itemStatus(at: url) == .present
        } catch {
            throw mapped(error)
        }
    }

    func writeAndVerify(_ data: Data, to url: URL) throws {
        guard data.count <= limits.maximumProfileEnvelopeBytes else {
            throw AtomicProfileFileStoreError.profileEnvelopeTooLarge(
                actual: data.count,
                maximum: limits.maximumProfileEnvelopeBytes
            )
        }
        do {
            try fileSystem.writeAtomicallyDurably(data, to: url)
        } catch {
            throw mapped(error)
        }
        do {
            guard case let .data(persisted) = try readProfileData(from: url),
                  persisted == data else {
                throw AtomicProfileFileStoreError.atomicWriteOutcomeUnknown
            }
        } catch {
            // The durable writer returned only after its rename and parent
            // sync. A later verification failure cannot safely be classified
            // as pre-install, so exact reconciliation must decide the state.
            throw AtomicProfileFileStoreError.atomicWriteOutcomeUnknown
        }
    }

    func quarantine(_ url: URL, at date: Date) throws -> URL {
        do {
            try fileSystem.createDirectory(at: locations.quarantineDirectoryURL)
            let timestamp = Int64(
                (date.timeIntervalSince1970 * 1_000).rounded()
            )
            let destination = locations.quarantineDirectoryURL.appendingPathComponent(
                "\(url.deletingPathExtension().lastPathComponent)-corrupt-\(timestamp)-\(UUID().uuidString.lowercased()).json"
            )
            try fileSystem.moveItemDurably(at: url, to: destination)
            guard try fileSystem.itemStatus(at: url) == .missing,
                  try fileSystem.itemStatus(at: destination) == .present else {
                throw AtomicProfileFileStoreError.writeVerificationFailed
            }
            return destination
        } catch let error as AtomicProfileFileStoreError {
            throw error
        } catch {
            throw mapped(error)
        }
    }

    func withLock<T>(_ perform: () throws -> T) throws -> T {
        var result: Result<T, any Error>?
        do {
            try fileSystem.withExclusiveLock(at: transactionLocations.lockURL) {
                result = Result { try perform() }
            }
        } catch {
            throw mapped(error)
        }
        guard let result else {
            throw AtomicProfileFileStoreError.ioFailure
        }
        do {
            return try result.get()
        } catch let error as AtomicProfileFileStoreError {
            throw error
        } catch {
            throw error
        }
    }

    func mapped(_ error: any Error) -> AtomicProfileFileStoreError {
        if let error = error as? AtomicProfileFileStoreError {
            return error
        }
        if let error = error as? ProfileHydrationFileSystemError,
           error == .lockContended {
            return .lockContended
        }
        if let error = error as? ProfileHydrationFileSystemError,
           error == .atomicWriteOutcomeUnknown {
            return .atomicWriteOutcomeUnknown
        }
        return .ioFailure
    }
}

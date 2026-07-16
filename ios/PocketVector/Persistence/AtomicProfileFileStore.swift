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
            return candidate
        }
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
                }
            }

            if currentBytes == intent.candidate.exactBytes {
                // The candidate may be the result of a prior attempt whose
                // response was lost. Rebuild only the exact predecessor backup
                // and re-read the candidate; never rewrite the primary here.
                do {
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

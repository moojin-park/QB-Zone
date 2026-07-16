import Darwin
import Foundation

enum ProfileHydrationFileSystemError: Error, Equatable, Sendable {
    case lockContended
    case ioFailure
}

protocol ProfileHydrationFileSystem: Sendable {
    func createDirectory(at url: URL) throws
    func fileExists(at url: URL) -> Bool
    func fileSize(at url: URL) throws -> Int
    func read(from url: URL) throws -> Data
    func writeAtomicallyDurably(_ data: Data, to url: URL) throws
    func moveItemDurably(at sourceURL: URL, to destinationURL: URL) throws
    func removeItemDurably(at url: URL) throws
    func withExclusiveLock(at url: URL, perform: () throws -> Void) throws
}

/// Foundation-backed persistence with a same-volume temporary file, full file
/// synchronization, atomic rename, and parent-directory synchronization.
struct FoundationProfileHydrationFileSystem: ProfileHydrationFileSystem {
    func createDirectory(at url: URL) throws {
        let alreadyExisted = FileManager.default.fileExists(atPath: url.path)
        do {
            try FileManager.default.createDirectory(
                at: url,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: NSNumber(value: Int16(0o700))]
            )
            if !alreadyExisted {
                try synchronizeDirectory(url.deletingLastPathComponent())
            }
        } catch {
            throw ProfileHydrationFileSystemError.ioFailure
        }
    }

    func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    func fileSize(at url: URL) throws -> Int {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard let number = attributes[.size] as? NSNumber,
                  number.int64Value >= 0,
                  UInt64(number.int64Value) <= UInt64(Int.max) else {
                throw ProfileHydrationFileSystemError.ioFailure
            }
            return Int(number.int64Value)
        } catch let error as ProfileHydrationFileSystemError {
            throw error
        } catch {
            throw ProfileHydrationFileSystemError.ioFailure
        }
    }

    func read(from url: URL) throws -> Data {
        do {
            return try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            throw ProfileHydrationFileSystemError.ioFailure
        }
    }

    func writeAtomicallyDurably(_ data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try createDirectory(at: directory)
        let temporaryURL = directory.appendingPathComponent(
            ".\(url.lastPathComponent).write-\(UUID().uuidString.lowercased())",
            isDirectory: false
        )
        var temporaryExists = false
        defer {
            if temporaryExists {
                _ = temporaryURL.path.withCString { Darwin.unlink($0) }
            }
        }

        let descriptor = temporaryURL.path.withCString {
            Darwin.open($0, O_CREAT | O_EXCL | O_WRONLY, S_IRUSR | S_IWUSR)
        }
        guard descriptor >= 0 else {
            throw ProfileHydrationFileSystemError.ioFailure
        }
        temporaryExists = true
        var descriptorIsOpen = true
        defer {
            if descriptorIsOpen {
                _ = Darwin.close(descriptor)
            }
        }

        do {
            try writeAll(data, to: descriptor)
            try synchronizeFile(descriptor)
            guard Darwin.close(descriptor) == 0 else {
                descriptorIsOpen = false
                throw ProfileHydrationFileSystemError.ioFailure
            }
            descriptorIsOpen = false
            guard temporaryURL.path.withCString({ source in
                url.path.withCString { destination in
                    Darwin.rename(source, destination)
                }
            }) == 0 else {
                throw ProfileHydrationFileSystemError.ioFailure
            }
            temporaryExists = false
            try synchronizeDirectory(directory)
        } catch let error as ProfileHydrationFileSystemError {
            throw error
        } catch {
            throw ProfileHydrationFileSystemError.ioFailure
        }
    }

    func moveItemDurably(at sourceURL: URL, to destinationURL: URL) throws {
        let sourceDirectory = sourceURL.deletingLastPathComponent()
        let destinationDirectory = destinationURL.deletingLastPathComponent()
        try createDirectory(at: destinationDirectory)
        guard !fileExists(at: destinationURL) else {
            throw ProfileHydrationFileSystemError.ioFailure
        }
        do {
            try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
            try synchronizeDirectory(destinationDirectory)
            if sourceDirectory.standardizedFileURL != destinationDirectory.standardizedFileURL {
                try synchronizeDirectory(sourceDirectory)
            }
        } catch let error as ProfileHydrationFileSystemError {
            throw error
        } catch {
            throw ProfileHydrationFileSystemError.ioFailure
        }
    }

    func removeItemDurably(at url: URL) throws {
        guard fileExists(at: url) else { return }
        do {
            try FileManager.default.removeItem(at: url)
            try synchronizeDirectory(url.deletingLastPathComponent())
        } catch let error as ProfileHydrationFileSystemError {
            throw error
        } catch {
            throw ProfileHydrationFileSystemError.ioFailure
        }
    }

    func withExclusiveLock(at url: URL, perform: () throws -> Void) throws {
        try createDirectory(at: url.deletingLastPathComponent())
        let descriptor = url.path.withCString {
            Darwin.open($0, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        }
        guard descriptor >= 0 else {
            throw ProfileHydrationFileSystemError.ioFailure
        }
        defer {
            _ = flock(descriptor, LOCK_UN)
            _ = Darwin.close(descriptor)
        }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            if errno == EWOULDBLOCK || errno == EAGAIN {
                throw ProfileHydrationFileSystemError.lockContended
            }
            throw ProfileHydrationFileSystemError.ioFailure
        }
        try perform()
    }

    private func writeAll(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            var offset = 0
            while offset < rawBuffer.count {
                let written = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    rawBuffer.count - offset
                )
                if written < 0, errno == EINTR {
                    continue
                }
                guard written > 0 else {
                    throw ProfileHydrationFileSystemError.ioFailure
                }
                offset += written
            }
        }
    }

    private func synchronizeFile(_ descriptor: Int32) throws {
        if Darwin.fcntl(descriptor, F_FULLFSYNC) == 0 {
            return
        }
        guard Darwin.fsync(descriptor) == 0 else {
            throw ProfileHydrationFileSystemError.ioFailure
        }
    }

    private func synchronizeDirectory(_ directory: URL) throws {
        let descriptor = directory.path.withCString {
            Darwin.open($0, O_RDONLY)
        }
        guard descriptor >= 0 else {
            throw ProfileHydrationFileSystemError.ioFailure
        }
        defer { _ = Darwin.close(descriptor) }
        guard Darwin.fsync(descriptor) == 0 else {
            throw ProfileHydrationFileSystemError.ioFailure
        }
    }
}

struct ProfileHydrationTransactionLocations: Equatable, Sendable {
    let profileDirectoryURL: URL
    let profilePrimaryURL: URL
    let profileBackupURL: URL
    let journalDirectoryURL: URL
    let journalPrimaryURL: URL
    let journalBackupURL: URL
    let quarantineDirectoryURL: URL
    /// Every repository mutation and startup load must eventually share this
    /// exact lock with the hydration coordinator.
    let lockURL: URL

    init(profileDirectoryURL: URL) {
        self.profileDirectoryURL = profileDirectoryURL
        let profileLocations = ProfileStorageLocations(directoryURL: profileDirectoryURL)
        profilePrimaryURL = profileLocations.primaryURL
        profileBackupURL = profileLocations.backupURL
        journalDirectoryURL = profileDirectoryURL.appendingPathComponent(
            "ProfileHydrationTransaction",
            isDirectory: true
        )
        journalPrimaryURL = journalDirectoryURL.appendingPathComponent(
            "profile-hydration-journal.json"
        )
        journalBackupURL = journalDirectoryURL.appendingPathComponent(
            "profile-hydration-journal.backup.json"
        )
        quarantineDirectoryURL = journalDirectoryURL.appendingPathComponent(
            "Quarantine",
            isDirectory: true
        )
        lockURL = profileDirectoryURL.appendingPathComponent(
            "player-profile-transaction.lock"
        )
    }

    func quarantineSlotURL(_ index: Int) -> URL {
        quarantineDirectoryURL.appendingPathComponent(
            "journal-evidence-\(index).json"
        )
    }
}

enum ProfileHydrationBindingMismatch: Equatable, Sendable {
    case cloudAccountID
    case playerAccountIdentity
    case accountKey
    case profileID
    case configurationScopeFingerprint
    case replicaEpoch
}

enum ProfileHydrationTransactionStoreError: Error, Equatable, Sendable {
    case invalidJournal
    case invalidJournalStructure(ProfileHydrationJournalValidationError)
    case journalTooLarge
    case journalAlreadyExists
    case journalCopiesDisagree
    case noValidJournalCopy
    case unrecoverableJournalEvidence
    case quarantineCapacityExceeded
    case journalVerificationFailed
    case bindingMismatch(ProfileHydrationBindingMismatch)
    case transactionMismatch
    case checkpointConfirmationMismatch
    case sourceProfileCASMismatch(ProfileHydrationProfileCopyState)
    case backupNormalizationRejected(ProfileHydrationProfileCopyState)
    case profileCopiesMissing
    case unexpectedProfileBytes
    case profileVerificationFailed
    case lockContended
    case ioFailure
    case encodingFailure
}

enum ProfileHydrationJournalRepair: Equatable, Sendable {
    case none
    case primary
    case backup
}

enum ProfileHydrationProfileCopyState: Equatable, Sendable {
    case source
    case candidate
    case missing
    case unexpected(ProfileHydrationDigest)
    case oversized(Int)
}

enum ProfileHydrationInstallationState: Equatable, Sendable {
    case source
    case partial
    case candidate
    case incomplete
    case unexpected
}

struct ProfileHydrationRecoveryInspection: Equatable, Sendable {
    let journal: ProfileHydrationJournalV1
    let repairedJournalCopy: ProfileHydrationJournalRepair
    let primaryProfileState: ProfileHydrationProfileCopyState
    let backupProfileState: ProfileHydrationProfileCopyState
    let installationState: ProfileHydrationInstallationState
}

struct ProfileHydrationJournalWriteResult: Equatable, Sendable {
    let journal: ProfileHydrationJournalV1
    let wasAlreadyPresent: Bool
    let repairedJournalCopy: ProfileHydrationJournalRepair
}

struct ProfileHydrationCandidateInstallResult: Equatable, Sendable {
    let inspection: ProfileHydrationRecoveryInspection
    let wasAlreadyInstalled: Bool
}

/// Durable file transaction only. It never calls `loadOrCreate`, publishes a
/// repository snapshot, or assumes that a checkpoint has committed. The later
/// coordinator must perform the profile CAS before writing the journal and may
/// remove it only after independently confirming the exact target checkpoint.
struct ProfileHydrationFileTransactionStore: Sendable {
    let locations: ProfileHydrationTransactionLocations

    private let migrator: any PlayerProfileMigrating
    private let catalog: LaunchCatalog
    private let limits: ProfileHydrationLimits
    private let fileSystem: any ProfileHydrationFileSystem

    init(
        profileDirectoryURL: URL,
        migrator: any PlayerProfileMigrating = PlayerProfileMigrator(),
        catalog: LaunchCatalog = .approved,
        limits: ProfileHydrationLimits = .production,
        fileSystem: any ProfileHydrationFileSystem = FoundationProfileHydrationFileSystem()
    ) {
        locations = ProfileHydrationTransactionLocations(
            profileDirectoryURL: profileDirectoryURL
        )
        self.migrator = migrator
        self.catalog = catalog
        self.limits = limits
        self.fileSystem = fileSystem
    }

    /// Atomically prepares one hydration intent. Once repositories adopt the
    /// shared lock exposed by `locations`, this is the sole boundary at which an
    /// exact local source may become recoverable hydration work.
    func beginHydration(
        _ journal: ProfileHydrationJournalV1
    ) throws -> ProfileHydrationJournalWriteResult {
        try withLock {
            let canonicalData = try validatedCanonicalData(for: journal)
            let existing = try resolveJournal(expected: nil, repair: true)
            if let existing {
                guard existing.data == canonicalData else {
                    throw ProfileHydrationTransactionStoreError.journalAlreadyExists
                }
                let inspection = try inspect(
                    journal: existing.journal,
                    repair: existing.repair
                )
                try ensureInstallable(inspection)
                return ProfileHydrationJournalWriteResult(
                    journal: existing.journal,
                    wasAlreadyPresent: true,
                    repairedJournalCopy: existing.repair
                )
            }

            try prepareExactSourceCopies(for: journal)
            guard try profileCopyState(
                at: locations.profilePrimaryURL,
                journal: journal
            ) == .source else {
                throw ProfileHydrationTransactionStoreError
                    .sourceProfileCASMismatch(
                        try profileCopyState(
                            at: locations.profilePrimaryURL,
                            journal: journal
                        )
                    )
            }
            try fileSystem.createDirectory(at: locations.journalDirectoryURL)
            try writeAndVerify(
                canonicalData,
                to: locations.journalPrimaryURL,
                verificationError: .journalVerificationFailed
            )
            try writeAndVerify(
                canonicalData,
                to: locations.journalBackupURL,
                verificationError: .journalVerificationFailed
            )
            guard try exactData(at: locations.journalPrimaryURL, limit: limits.maximumEncodedJournalBytes)
                    == canonicalData,
                  try exactData(at: locations.journalBackupURL, limit: limits.maximumEncodedJournalBytes)
                    == canonicalData else {
                throw ProfileHydrationTransactionStoreError.journalVerificationFailed
            }
            return ProfileHydrationJournalWriteResult(
                journal: journal,
                wasAlreadyPresent: false,
                repairedJournalCopy: .none
            )
        }
    }

    func inspectRecovery(
        expected: ProfileHydrationExpectedBinding
    ) throws -> ProfileHydrationRecoveryInspection? {
        try withLock {
            guard let resolved = try resolveJournal(expected: expected, repair: true) else {
                return nil
            }
            return try inspect(journal: resolved.journal, repair: resolved.repair)
        }
    }

    func installCandidate(
        transactionID: UUID,
        expected: ProfileHydrationExpectedBinding
    ) throws -> ProfileHydrationCandidateInstallResult {
        try withLock {
            guard let resolved = try resolveJournal(expected: expected, repair: true) else {
                throw ProfileHydrationTransactionStoreError.noValidJournalCopy
            }
            guard resolved.journal.transactionID == transactionID else {
                throw ProfileHydrationTransactionStoreError.transactionMismatch
            }
            let before = try inspect(journal: resolved.journal, repair: resolved.repair)
            try ensureInstallable(before)
            if before.installationState == .candidate {
                return ProfileHydrationCandidateInstallResult(
                    inspection: before,
                    wasAlreadyInstalled: true
                )
            }

            if before.backupProfileState != .candidate {
                try writeAndVerify(
                    resolved.journal.candidateProfileEnvelope,
                    to: locations.profileBackupURL,
                    verificationError: .profileVerificationFailed
                )
            }
            guard try profileCopyState(
                at: locations.profileBackupURL,
                journal: resolved.journal
            ) == .candidate else {
                throw ProfileHydrationTransactionStoreError.profileVerificationFailed
            }

            if before.primaryProfileState != .candidate {
                try writeAndVerify(
                    resolved.journal.candidateProfileEnvelope,
                    to: locations.profilePrimaryURL,
                    verificationError: .profileVerificationFailed
                )
            }
            guard try profileCopyState(
                at: locations.profilePrimaryURL,
                journal: resolved.journal
            ) == .candidate else {
                throw ProfileHydrationTransactionStoreError.profileVerificationFailed
            }
            let after = try inspect(journal: resolved.journal, repair: resolved.repair)
            guard after.installationState == .candidate else {
                throw ProfileHydrationTransactionStoreError.profileVerificationFailed
            }
            return ProfileHydrationCandidateInstallResult(
                inspection: after,
                wasAlreadyInstalled: false
            )
        }
    }

    /// The caller supplies the identity it independently observed as committed
    /// by the checkpoint store. No cleanup occurs unless it exactly matches the
    /// immutable target bound into the journal.
    @discardableResult
    func removeJournalAfterCheckpointConfirmation(
        transactionID: UUID,
        expected: ProfileHydrationExpectedBinding,
        committedCheckpointIdentity: ProfileHydrationCheckpointIdentityV1
    ) throws -> Bool {
        try withLock {
            guard let resolved = try resolveJournal(expected: expected, repair: true) else {
                return false
            }
            guard resolved.journal.transactionID == transactionID else {
                throw ProfileHydrationTransactionStoreError.transactionMismatch
            }
            guard resolved.journal.targetCheckpointIdentity
                == committedCheckpointIdentity else {
                throw ProfileHydrationTransactionStoreError.checkpointConfirmationMismatch
            }
            let inspection = try inspect(journal: resolved.journal, repair: resolved.repair)
            guard inspection.installationState == .candidate else {
                throw ProfileHydrationTransactionStoreError.profileVerificationFailed
            }

            // Once the exact target checkpoint is confirmed, invalid-copy
            // evidence from an earlier successful repair is no longer needed.
            // Evidence is removed first so an interrupted cleanup always leaves
            // at least one live journal copy describing the installed profile.
            try removeAllQuarantineEvidence()
            try fileSystem.removeItemDurably(at: locations.journalBackupURL)
            guard !fileSystem.fileExists(at: locations.journalBackupURL) else {
                throw ProfileHydrationTransactionStoreError.ioFailure
            }
            try fileSystem.removeItemDurably(at: locations.journalPrimaryURL)
            guard !fileSystem.fileExists(at: locations.journalPrimaryURL) else {
                throw ProfileHydrationTransactionStoreError.ioFailure
            }
            return true
        }
    }

    func quarantinedEvidenceURLs() throws -> [URL] {
        try withLock {
            try quarantineEvidenceURLs()
        }
    }

    private struct ResolvedJournal {
        let journal: ProfileHydrationJournalV1
        let data: Data
        let repair: ProfileHydrationJournalRepair
    }

    private enum JournalCopy {
        case missing(URL)
        case invalid(URL)
        case valid(URL, Data, ProfileHydrationJournalV1)

        var url: URL {
            switch self {
            case let .missing(url), let .invalid(url), let .valid(url, _, _):
                url
            }
        }
    }

    private func resolveJournal(
        expected: ProfileHydrationExpectedBinding?,
        repair: Bool
    ) throws -> ResolvedJournal? {
        let primary = try readJournalCopy(at: locations.journalPrimaryURL)
        let backup = try readJournalCopy(at: locations.journalBackupURL)

        switch (primary, backup) {
        case let (.valid(_, primaryData, primaryJournal),
                  .valid(_, backupData, _)):
            guard primaryData == backupData else {
                // Both are individually valid immutable candidates. Picking or
                // quarantining either one would destroy evidence of a split
                // brain, so fail without touching either file.
                throw ProfileHydrationTransactionStoreError.journalCopiesDisagree
            }
            try validateExpected(expected, journal: primaryJournal)
            return ResolvedJournal(
                journal: primaryJournal,
                data: primaryData,
                repair: .none
            )

        case let (.valid(_, data, journal), other):
            try validateExpected(expected, journal: journal)
            let repaired = try repairCopy(
                other,
                with: data,
                destination: locations.journalBackupURL,
                repair: repair
            )
            return ResolvedJournal(journal: journal, data: data, repair: repaired)

        case let (other, .valid(_, data, journal)):
            try validateExpected(expected, journal: journal)
            let repaired = try repairCopy(
                other,
                with: data,
                destination: locations.journalPrimaryURL,
                repair: repair
            )
            return ResolvedJournal(journal: journal, data: data, repair: repaired)

        case (.missing, .missing):
            guard try quarantineEvidenceURLs().isEmpty else {
                throw ProfileHydrationTransactionStoreError.unrecoverableJournalEvidence
            }
            return nil

        case let (.invalid(primaryURL), .invalid(backupURL)):
            if repair {
                try quarantine(primaryURL)
                try quarantine(backupURL)
            }
            throw ProfileHydrationTransactionStoreError.noValidJournalCopy

        case let (.invalid(url), .missing), let (.missing, .invalid(url)):
            if repair {
                try quarantine(url)
            }
            throw ProfileHydrationTransactionStoreError.noValidJournalCopy
        }
    }

    private func repairCopy(
        _ copy: JournalCopy,
        with canonicalData: Data,
        destination: URL,
        repair: Bool
    ) throws -> ProfileHydrationJournalRepair {
        let repairKind: ProfileHydrationJournalRepair = destination
            == locations.journalPrimaryURL ? .primary : .backup
        switch copy {
        case .valid:
            preconditionFailure("A valid divergent copy must be handled before repair")
        case .missing:
            guard repair else { return .none }
        case let .invalid(url):
            guard repair else { return .none }
            try quarantine(url)
        }
        try writeAndVerify(
            canonicalData,
            to: destination,
            verificationError: .journalVerificationFailed
        )
        return repairKind
    }

    private func readJournalCopy(at url: URL) throws -> JournalCopy {
        guard fileSystem.fileExists(at: url) else { return .missing(url) }
        let size: Int
        do {
            size = try fileSystem.fileSize(at: url)
        } catch {
            throw mapped(error)
        }
        guard size >= 0, size <= limits.maximumEncodedJournalBytes else {
            return .invalid(url)
        }
        let data: Data
        do {
            data = try fileSystem.read(from: url)
        } catch {
            throw mapped(error)
        }
        guard data.count <= limits.maximumEncodedJournalBytes else {
            return .invalid(url)
        }
        do {
            let journal = try ProfileHydrationCanonicalCodec.decode(
                ProfileHydrationJournalV1.self,
                from: data
            )
            try journal.validate(migrator: migrator, catalog: catalog, limits: limits)
            let canonical = try ProfileHydrationCanonicalCodec.encode(journal)
            guard canonical == data else { return .invalid(url) }
            return .valid(url, data, journal)
        } catch {
            return .invalid(url)
        }
    }

    private func validateExpected(
        _ expected: ProfileHydrationExpectedBinding?,
        journal: ProfileHydrationJournalV1
    ) throws {
        guard let expected else { return }
        let target = journal.target
        guard expected.cloudAccountID == target.cloudAccountID else {
            throw ProfileHydrationTransactionStoreError.bindingMismatch(.cloudAccountID)
        }
        guard expected.playerAccountIdentity == target.playerAccountIdentity else {
            throw ProfileHydrationTransactionStoreError.bindingMismatch(.playerAccountIdentity)
        }
        guard expected.accountKey == target.accountKey else {
            throw ProfileHydrationTransactionStoreError.bindingMismatch(.accountKey)
        }
        guard expected.profileID == target.profileID else {
            throw ProfileHydrationTransactionStoreError.bindingMismatch(.profileID)
        }
        guard expected.configurationScopeFingerprint
            == target.configurationScopeFingerprint else {
            throw ProfileHydrationTransactionStoreError.bindingMismatch(
                .configurationScopeFingerprint
            )
        }
        guard expected.replicaEpoch == target.replicaEpoch else {
            throw ProfileHydrationTransactionStoreError.bindingMismatch(.replicaEpoch)
        }
    }

    private func validatedCanonicalData(
        for journal: ProfileHydrationJournalV1
    ) throws -> Data {
        do {
            try journal.validate(migrator: migrator, catalog: catalog, limits: limits)
        } catch let error as ProfileHydrationJournalValidationError {
            throw ProfileHydrationTransactionStoreError.invalidJournalStructure(error)
        } catch {
            throw ProfileHydrationTransactionStoreError.invalidJournal
        }
        do {
            let data = try ProfileHydrationCanonicalCodec.encode(journal)
            guard data.count <= limits.maximumEncodedJournalBytes else {
                throw ProfileHydrationTransactionStoreError.journalTooLarge
            }
            return data
        } catch let error as ProfileHydrationTransactionStoreError {
            throw error
        } catch {
            throw ProfileHydrationTransactionStoreError.encodingFailure
        }
    }

    private func inspect(
        journal: ProfileHydrationJournalV1,
        repair: ProfileHydrationJournalRepair
    ) throws -> ProfileHydrationRecoveryInspection {
        let primary = try profileCopyState(
            at: locations.profilePrimaryURL,
            journal: journal
        )
        let backup = try profileCopyState(
            at: locations.profileBackupURL,
            journal: journal
        )
        let installationState = installationState(primary: primary, backup: backup)
        return ProfileHydrationRecoveryInspection(
            journal: journal,
            repairedJournalCopy: repair,
            primaryProfileState: primary,
            backupProfileState: backup,
            installationState: installationState
        )
    }

    private func profileCopyState(
        at url: URL,
        journal: ProfileHydrationJournalV1
    ) throws -> ProfileHydrationProfileCopyState {
        guard fileSystem.fileExists(at: url) else { return .missing }
        let size: Int
        do {
            size = try fileSystem.fileSize(at: url)
        } catch {
            throw mapped(error)
        }
        guard size >= 0, size <= limits.maximumProfileEnvelopeBytes else {
            return .oversized(max(0, size))
        }
        let data: Data
        do {
            data = try fileSystem.read(from: url)
        } catch {
            throw mapped(error)
        }
        guard data.count <= limits.maximumProfileEnvelopeBytes else {
            return .oversized(data.count)
        }
        if data == journal.sourceProfileEnvelope { return .source }
        if data == journal.candidateProfileEnvelope { return .candidate }
        return .unexpected(.envelopeBytes(data))
    }

    private func prepareExactSourceCopies(
        for journal: ProfileHydrationJournalV1
    ) throws {
        let primary = try profileCopyState(
            at: locations.profilePrimaryURL,
            journal: journal
        )
        guard primary == .source else {
            throw ProfileHydrationTransactionStoreError
                .sourceProfileCASMismatch(primary)
        }

        let backup = try profileCopyState(
            at: locations.profileBackupURL,
            journal: journal
        )
        switch backup {
        case .source:
            return

        case .missing:
            break

        case .unexpected:
            guard try isValidatedStrictlyOlderBackup(
                at: locations.profileBackupURL,
                than: journal
            ) else {
                throw ProfileHydrationTransactionStoreError
                    .backupNormalizationRejected(backup)
            }

        case .candidate, .oversized:
            throw ProfileHydrationTransactionStoreError
                .backupNormalizationRejected(backup)
        }

        try writeAndVerify(
            journal.sourceProfileEnvelope,
            to: locations.profileBackupURL,
            verificationError: .profileVerificationFailed
        )
        let normalized = try profileCopyState(
            at: locations.profileBackupURL,
            journal: journal
        )
        guard normalized == .source else {
            throw ProfileHydrationTransactionStoreError.profileVerificationFailed
        }
    }

    private func isValidatedStrictlyOlderBackup(
        at url: URL,
        than journal: ProfileHydrationJournalV1
    ) throws -> Bool {
        let bytes: Data
        do {
            bytes = try exactData(
                at: url,
                limit: limits.maximumProfileEnvelopeBytes
            )
        } catch {
            return false
        }

        let backupDocument: LocalPlayerDocumentV1
        let sourceDocument: LocalPlayerDocumentV1
        do {
            backupDocument = try migrator.decode(bytes)
            sourceDocument = try migrator.decode(journal.sourceProfileEnvelope)
            try PlayerProfileValidator.validate(
                backupDocument,
                catalog: catalog
            )
            try PlayerProfileValidator.validate(
                sourceDocument,
                catalog: catalog
            )
        } catch {
            return false
        }

        guard backupDocument.accountIdentity == sourceDocument.accountIdentity,
              backupDocument.player.profileID == sourceDocument.player.profileID,
              backupDocument.player.revision <= sourceDocument.player.revision,
              backupDocument.economyRevision <= sourceDocument.economyRevision
        else {
            return false
        }
        return backupDocument.player.revision < sourceDocument.player.revision
            || backupDocument.economyRevision < sourceDocument.economyRevision
    }

    private func installationState(
        primary: ProfileHydrationProfileCopyState,
        backup: ProfileHydrationProfileCopyState
    ) -> ProfileHydrationInstallationState {
        if primary == .source, backup == .source { return .source }
        if primary == .candidate, backup == .candidate { return .candidate }
        let exactStates: [ProfileHydrationProfileCopyState] = [.source, .candidate, .missing]
        guard exactStates.contains(primary), exactStates.contains(backup) else {
            return .unexpected
        }
        if primary == .missing, backup == .missing { return .incomplete }
        if primary == .missing || backup == .missing { return .incomplete }
        return .partial
    }

    private func ensureInstallable(
        _ inspection: ProfileHydrationRecoveryInspection
    ) throws {
        switch inspection.installationState {
        case .source, .partial, .candidate:
            return
        case .incomplete:
            if inspection.primaryProfileState == .missing,
               inspection.backupProfileState == .missing {
                throw ProfileHydrationTransactionStoreError.profileCopiesMissing
            }
            return
        case .unexpected:
            throw ProfileHydrationTransactionStoreError.unexpectedProfileBytes
        }
    }

    private func writeAndVerify(
        _ data: Data,
        to url: URL,
        verificationError: ProfileHydrationTransactionStoreError
    ) throws {
        do {
            try fileSystem.writeAtomicallyDurably(data, to: url)
            guard try exactData(at: url, limit: max(
                limits.maximumEncodedJournalBytes,
                limits.maximumProfileEnvelopeBytes
            )) == data else {
                throw verificationError
            }
        } catch let error as ProfileHydrationTransactionStoreError {
            throw error
        } catch {
            throw mapped(error)
        }
    }

    private func exactData(at url: URL, limit: Int) throws -> Data {
        guard fileSystem.fileExists(at: url) else {
            throw ProfileHydrationTransactionStoreError.ioFailure
        }
        do {
            let size = try fileSystem.fileSize(at: url)
            guard size >= 0, size <= limit else {
                throw ProfileHydrationTransactionStoreError.journalTooLarge
            }
            let data = try fileSystem.read(from: url)
            guard data.count <= limit else {
                throw ProfileHydrationTransactionStoreError.journalTooLarge
            }
            return data
        } catch let error as ProfileHydrationTransactionStoreError {
            throw error
        } catch {
            throw mapped(error)
        }
    }

    private func quarantine(_ url: URL) throws {
        guard fileSystem.fileExists(at: url) else { return }
        let sourceSize: Int
        do {
            sourceSize = try fileSystem.fileSize(at: url)
        } catch {
            throw mapped(error)
        }
        guard sourceSize >= 0 else {
            throw ProfileHydrationTransactionStoreError.ioFailure
        }
        let existing = try quarantineEvidenceURLs()
        guard existing.count < limits.maximumQuarantineFiles else {
            throw ProfileHydrationTransactionStoreError.quarantineCapacityExceeded
        }
        var totalBytes = 0
        for evidenceURL in existing {
            let size: Int
            do {
                size = try fileSystem.fileSize(at: evidenceURL)
            } catch {
                throw mapped(error)
            }
            let (next, overflow) = totalBytes.addingReportingOverflow(size)
            guard !overflow else {
                throw ProfileHydrationTransactionStoreError.quarantineCapacityExceeded
            }
            totalBytes = next
        }
        let (newTotal, overflow) = totalBytes.addingReportingOverflow(sourceSize)
        guard !overflow, newTotal <= limits.maximumQuarantineBytes else {
            throw ProfileHydrationTransactionStoreError.quarantineCapacityExceeded
        }
        guard let destination = (0 ..< limits.maximumQuarantineFiles)
            .map(locations.quarantineSlotURL)
            .first(where: { !fileSystem.fileExists(at: $0) }) else {
            throw ProfileHydrationTransactionStoreError.quarantineCapacityExceeded
        }
        do {
            try fileSystem.createDirectory(at: locations.quarantineDirectoryURL)
            try fileSystem.moveItemDurably(at: url, to: destination)
        } catch {
            throw mapped(error)
        }
        guard !fileSystem.fileExists(at: url), fileSystem.fileExists(at: destination) else {
            throw ProfileHydrationTransactionStoreError.ioFailure
        }
    }

    private func quarantineEvidenceURLs() throws -> [URL] {
        var result: [URL] = []
        for index in 0 ..< limits.maximumQuarantineFiles {
            let url = locations.quarantineSlotURL(index)
            if fileSystem.fileExists(at: url) {
                result.append(url)
            }
        }
        return result
    }

    private func removeAllQuarantineEvidence() throws {
        for url in try quarantineEvidenceURLs() {
            do {
                try fileSystem.removeItemDurably(at: url)
            } catch {
                throw mapped(error)
            }
        }
    }

    private func withLock<T>(_ perform: () throws -> T) throws -> T {
        var result: Result<T, any Error>?
        do {
            try fileSystem.withExclusiveLock(at: locations.lockURL) {
                result = Result { try perform() }
            }
        } catch {
            throw mapped(error)
        }
        guard let result else {
            throw ProfileHydrationTransactionStoreError.ioFailure
        }
        do {
            return try result.get()
        } catch let error as ProfileHydrationTransactionStoreError {
            throw error
        } catch {
            throw mapped(error)
        }
    }

    private func mapped(_ error: any Error) -> ProfileHydrationTransactionStoreError {
        if let error = error as? ProfileHydrationTransactionStoreError {
            return error
        }
        if let error = error as? ProfileHydrationFileSystemError,
           error == .lockContended {
            return .lockContended
        }
        return .ioFailure
    }
}

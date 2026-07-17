import Darwin
import Foundation

enum ProfileHydrationFileSystemError: Error, Equatable, Sendable {
    case lockContended
    case ioFailure
    /// The atomic rename completed, but a later parent-directory sync failed.
    /// The caller must treat the destination bytes as outcome-unknown.
    case atomicWriteOutcomeUnknown
}

enum ProfileHydrationFileItemStatus: Equatable, Sendable {
    case missing
    case present
}

protocol ProfileHydrationFileSystem: Sendable {
    func createDirectory(at url: URL) throws
    func itemStatus(at url: URL) throws -> ProfileHydrationFileItemStatus
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
        let alreadyExisted = try itemStatus(at: url) == .present
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

    func itemStatus(at url: URL) throws -> ProfileHydrationFileItemStatus {
        var metadata = stat()
        let result = url.path.withCString { Darwin.lstat($0, &metadata) }
        if result == 0 {
            return .present
        }
        if errno == ENOENT {
            return .missing
        }
        throw ProfileHydrationFileSystemError.ioFailure
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
        var destinationWasRenamed = false
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
            destinationWasRenamed = true
            try synchronizeDirectory(directory)
        } catch let error as ProfileHydrationFileSystemError {
            if destinationWasRenamed {
                throw ProfileHydrationFileSystemError.atomicWriteOutcomeUnknown
            }
            throw error
        } catch {
            if destinationWasRenamed {
                throw ProfileHydrationFileSystemError.atomicWriteOutcomeUnknown
            }
            throw ProfileHydrationFileSystemError.ioFailure
        }
    }

    func moveItemDurably(at sourceURL: URL, to destinationURL: URL) throws {
        let sourceDirectory = sourceURL.deletingLastPathComponent()
        let destinationDirectory = destinationURL.deletingLastPathComponent()
        try createDirectory(at: destinationDirectory)
        guard try itemStatus(at: destinationURL) == .missing else {
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
        let directory = url.deletingLastPathComponent()
        do {
            if try itemStatus(at: url) == .present {
                try FileManager.default.removeItem(at: url)
            }
            // Re-sync even an already-absent entry. A prior removal may have
            // completed before its directory sync reported failure, and only a
            // fresh parent sync can turn that ambiguous outcome into a durable
            // absence observation.
            try synchronizeDirectory(directory)
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
    case repositoryAdmissionMismatch
    case repositoryLiveAdmissionInProgress
    case repositoryCompletionAttemptInProgress
    case repositoryCompletionAuthorityConsumed
    case profileDirectoryIdentityUnavailableBeforeAdmission
    case profileDirectoryIdentityUnavailable
    case profileDirectoryIdentityMismatch
    case bindingMismatch(ProfileHydrationBindingMismatch)
    case transactionMismatch
    case checkpointConfirmationMismatch
    case sourceOnlyAbortRejected(
        primary: ProfileHydrationProfileCopyState,
        backup: ProfileHydrationProfileCopyState
    )
    case sourceProfileCASMismatch(ProfileHydrationProfileCopyState)
    case backupNormalizationRejected(ProfileHydrationProfileCopyState)
    case profileCopiesMissing
    case unexpectedProfileBytes
    case profileVerificationFailed
    case lockContended
    case ioFailure
    case encodingFailure
}

/// Strong process identity prevents ABA without retaining an issuance history.
/// A stale handle keeps its own terminal identity alive, while the registry
/// stores at most one live identity per physical profile directory.
fileprivate struct ProfileHydrationPhysicalDirectoryIdentityV1:
    Equatable,
    Hashable,
    Sendable
{
    let device: UInt64
    let inode: UInt64
}

fileprivate final class LocalProfileHydrationAdmissionIdentityV1:
    @unchecked Sendable
{
    fileprivate enum Phase {
        case issued
        case pending
        case ready
        case attempting(LocalProfileHydrationAttemptIdentityV1)
        case consumed
    }

    fileprivate var phase: Phase = .issued
    fileprivate var physicalDirectoryIdentity:
        ProfileHydrationPhysicalDirectoryIdentityV1?
    fileprivate var hasBegunCompletionAttempt = false
}

fileprivate final class LocalProfileHydrationAttemptIdentityV1:
    @unchecked Sendable
{}

/// The Release recovery handle is deliberately inert. Only the transaction
/// store, co-located in this file, can inspect its binding or mutate the
/// private completion registry.
struct LocalProfileHydrationRecoveryHandleV1: Equatable, Sendable {
    let capability: LocalProfileHydrationCapabilityV1
    fileprivate let admissionIdentity: LocalProfileHydrationAdmissionIdentityV1
    fileprivate let standardizedProfileDirectoryURL: URL
    fileprivate let journal: ProfileHydrationJournalV1

    init(
        capability: LocalProfileHydrationCapabilityV1,
        standardizedProfileDirectoryURL: URL,
        journal: ProfileHydrationJournalV1
    ) {
        self.capability = capability
        admissionIdentity = LocalProfileHydrationAdmissionIdentityV1()
        self.standardizedProfileDirectoryURL =
            standardizedProfileDirectoryURL.standardizedFileURL
        self.journal = journal
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.capability == rhs.capability
            && lhs.admissionIdentity === rhs.admissionIdentity
    }
}

fileprivate struct LocalProfileHydrationCompletionAttemptV1: Sendable {
    let admissionIdentity: LocalProfileHydrationAdmissionIdentityV1
    let attemptIdentity: LocalProfileHydrationAttemptIdentityV1
    let physicalDirectoryIdentity:
        ProfileHydrationPhysicalDirectoryIdentityV1
    let standardizedProfileDirectoryURL: URL
    let journal: ProfileHydrationJournalV1
}

/// Registry methods never acquire the file lock. The store calls activation,
/// startup preflight, revalidation, and consumption while it already holds the
/// file lock. Attempt preclaim releases this registry lock before the store
/// waits for the file lock, so lock order cannot invert.
private final class LocalProfileHydrationCompletionRegistryV1:
    @unchecked Sendable
{
    static let shared = LocalProfileHydrationCompletionRegistryV1()

    private struct WeakAdmissionIdentity {
        weak var value: LocalProfileHydrationAdmissionIdentityV1?
    }

    private let lock = NSLock()
    private var currentByDirectory:
        [ProfileHydrationPhysicalDirectoryIdentityV1: WeakAdmissionIdentity] = [:]

    /// Called before waiting on the file lock. It installs a pending claim so
    /// an aliased startup store cannot pass its under-lock preflight while the
    /// repository barrier is waiting to enter the transaction.
    func claimPending(
        _ handle: LocalProfileHydrationRecoveryHandleV1,
        physicalDirectoryIdentity:
            ProfileHydrationPhysicalDirectoryIdentityV1,
        journal: ProfileHydrationJournalV1,
        profileDirectoryURL: URL
    ) throws {
        let lexicalDirectory = profileDirectoryURL.standardizedFileURL
        guard handle.standardizedProfileDirectoryURL == lexicalDirectory,
              handle.journal == journal else {
            throw ProfileHydrationTransactionStoreError
                .repositoryAdmissionMismatch
        }
        lock.lock()
        defer { lock.unlock() }
        pruneReleasedIdentities()
        switch handle.admissionIdentity.phase {
        case .consumed:
            throw ProfileHydrationTransactionStoreError
                .repositoryCompletionAuthorityConsumed
        case .attempting:
            throw ProfileHydrationTransactionStoreError
                .repositoryCompletionAttemptInProgress
        case .pending:
            guard handle.admissionIdentity.physicalDirectoryIdentity
                    == physicalDirectoryIdentity,
                  currentByDirectory[physicalDirectoryIdentity]?.value
                    === handle.admissionIdentity else {
                throw ProfileHydrationTransactionStoreError
                    .repositoryAdmissionMismatch
            }
            return
        case .ready:
            guard !handle.admissionIdentity.hasBegunCompletionAttempt,
                  handle.admissionIdentity.physicalDirectoryIdentity
                    == physicalDirectoryIdentity,
                  currentByDirectory[physicalDirectoryIdentity]?.value
                    === handle.admissionIdentity else {
                throw ProfileHydrationTransactionStoreError
                    .repositoryAdmissionMismatch
            }
            return
        case .issued:
            break
        }
        if let current = currentByDirectory[physicalDirectoryIdentity]?.value {
            guard current === handle.admissionIdentity else {
                throw ProfileHydrationTransactionStoreError
                    .repositoryLiveAdmissionInProgress
            }
            throw ProfileHydrationTransactionStoreError
                .repositoryAdmissionMismatch
        }
        handle.admissionIdentity.physicalDirectoryIdentity =
            physicalDirectoryIdentity
        handle.admissionIdentity.phase = .pending
        currentByDirectory[physicalDirectoryIdentity] = WeakAdmissionIdentity(
            value: handle.admissionIdentity
        )
    }

    /// Called with the file lock held after resolving physical identity again.
    func activateCurrent(
        _ handle: LocalProfileHydrationRecoveryHandleV1,
        physicalDirectoryIdentity:
            ProfileHydrationPhysicalDirectoryIdentityV1,
        journal: ProfileHydrationJournalV1,
        profileDirectoryURL: URL
    ) throws {
        let lexicalDirectory = profileDirectoryURL.standardizedFileURL
        guard handle.standardizedProfileDirectoryURL == lexicalDirectory,
              handle.journal == journal else {
            throw ProfileHydrationTransactionStoreError
                .repositoryAdmissionMismatch
        }
        lock.lock()
        defer { lock.unlock() }
        pruneReleasedIdentities()
        guard handle.admissionIdentity.physicalDirectoryIdentity
                == physicalDirectoryIdentity,
              currentByDirectory[physicalDirectoryIdentity]?.value
                === handle.admissionIdentity else {
            throw ProfileHydrationTransactionStoreError
                .profileDirectoryIdentityMismatch
        }
        switch handle.admissionIdentity.phase {
        case .pending:
            handle.admissionIdentity.phase = .ready
        case .ready:
            return
        case .issued, .attempting, .consumed:
            throw ProfileHydrationTransactionStoreError
                .repositoryAdmissionMismatch
        }
    }

    func rejectStartupRecoveryIfLiveAdmission(
        physicalDirectoryIdentity:
            ProfileHydrationPhysicalDirectoryIdentityV1
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        pruneReleasedIdentities()
        guard currentByDirectory[physicalDirectoryIdentity]?.value == nil else {
            throw ProfileHydrationTransactionStoreError
                .repositoryLiveAdmissionInProgress
        }
    }

    func beginAttempt(
        _ handle: LocalProfileHydrationRecoveryHandleV1,
        physicalDirectoryIdentity:
            ProfileHydrationPhysicalDirectoryIdentityV1,
        profileDirectoryURL: URL
    ) throws -> LocalProfileHydrationCompletionAttemptV1 {
        let lexicalDirectory = profileDirectoryURL.standardizedFileURL
        guard handle.standardizedProfileDirectoryURL == lexicalDirectory else {
            throw ProfileHydrationTransactionStoreError
                .repositoryAdmissionMismatch
        }
        lock.lock()
        defer { lock.unlock() }
        pruneReleasedIdentities()
        switch handle.admissionIdentity.phase {
        case .consumed:
            throw ProfileHydrationTransactionStoreError
                .repositoryCompletionAuthorityConsumed
        case .attempting:
            throw ProfileHydrationTransactionStoreError
                .repositoryCompletionAttemptInProgress
        case .issued, .pending:
            throw ProfileHydrationTransactionStoreError
                .repositoryAdmissionMismatch
        case .ready:
            guard handle.admissionIdentity.physicalDirectoryIdentity
                    == physicalDirectoryIdentity,
                  currentByDirectory[physicalDirectoryIdentity]?.value
                    === handle.admissionIdentity else {
                throw ProfileHydrationTransactionStoreError
                    .repositoryAdmissionMismatch
            }
            let attemptIdentity = LocalProfileHydrationAttemptIdentityV1()
            handle.admissionIdentity.hasBegunCompletionAttempt = true
            handle.admissionIdentity.phase = .attempting(attemptIdentity)
            return LocalProfileHydrationCompletionAttemptV1(
                admissionIdentity: handle.admissionIdentity,
                attemptIdentity: attemptIdentity,
                physicalDirectoryIdentity: physicalDirectoryIdentity,
                standardizedProfileDirectoryURL: lexicalDirectory,
                journal: handle.journal
            )
        }
    }

    func revalidateCurrent(
        _ attempt: LocalProfileHydrationCompletionAttemptV1,
        physicalDirectoryIdentity:
            ProfileHydrationPhysicalDirectoryIdentityV1,
        journal: ProfileHydrationJournalV1,
        profileDirectoryURL: URL
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        pruneReleasedIdentities()
        try validateCurrent(
            attempt,
            physicalDirectoryIdentity: physicalDirectoryIdentity,
            journal: journal,
            profileDirectoryURL: profileDirectoryURL
        )
    }

    func consumeAfterDurableRemoval(
        _ attempt: LocalProfileHydrationCompletionAttemptV1,
        physicalDirectoryIdentity:
            ProfileHydrationPhysicalDirectoryIdentityV1,
        journal: ProfileHydrationJournalV1,
        profileDirectoryURL: URL
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        pruneReleasedIdentities()
        try validateCurrent(
            attempt,
            physicalDirectoryIdentity: physicalDirectoryIdentity,
            journal: journal,
            profileDirectoryURL: profileDirectoryURL
        )
        attempt.admissionIdentity.phase = .consumed
        currentByDirectory.removeValue(
            forKey: physicalDirectoryIdentity
        )
    }

    func resetRetryableIfCurrent(
        _ attempt: LocalProfileHydrationCompletionAttemptV1
    ) {
        lock.lock()
        defer { lock.unlock() }
        pruneReleasedIdentities()
        let physicalDirectoryIdentity = attempt.physicalDirectoryIdentity
        guard currentByDirectory[physicalDirectoryIdentity]?.value
                === attempt.admissionIdentity,
              case let .attempting(currentAttempt) =
                attempt.admissionIdentity.phase,
              currentAttempt === attempt.attemptIdentity else {
            return
        }
        attempt.admissionIdentity.phase = .ready
    }

    private func validateCurrent(
        _ attempt: LocalProfileHydrationCompletionAttemptV1,
        physicalDirectoryIdentity:
            ProfileHydrationPhysicalDirectoryIdentityV1,
        journal: ProfileHydrationJournalV1,
        profileDirectoryURL: URL
    ) throws {
        let lexicalDirectory = profileDirectoryURL.standardizedFileURL
        guard attempt.standardizedProfileDirectoryURL == lexicalDirectory,
              attempt.physicalDirectoryIdentity == physicalDirectoryIdentity,
              attempt.journal == journal,
              currentByDirectory[physicalDirectoryIdentity]?.value
                === attempt.admissionIdentity,
              case let .attempting(currentAttempt) =
                attempt.admissionIdentity.phase,
              currentAttempt === attempt.attemptIdentity else {
            throw ProfileHydrationTransactionStoreError
                .repositoryAdmissionMismatch
        }
    }

    private func pruneReleasedIdentities() {
        currentByDirectory = currentByDirectory.filter {
            $0.value.value != nil
        }
    }
}

#if DEBUG
/// Test-only controlled overlap claim. It exposes no Release mutation surface.
struct ProfileHydrationCompletionClaimTestTokenV1: Sendable {
    fileprivate let attempt: LocalProfileHydrationCompletionAttemptV1
}
#endif

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

/// Sealed evidence that the exact durable journal was removed only while a
/// scoped checkpoint lease confirmed its predecessor and both profile copies
/// remained the exact source. Only the transaction store can mint it.
struct ProfileHydrationPredecessorAbortConfirmationV1: Equatable, Sendable {
    private let standardizedProfileDirectoryURL: URL
    private let journal: ProfileHydrationJournalV1
    private let capability: LocalProfileHydrationCapabilityV1

    fileprivate init(
        standardizedProfileDirectoryURL: URL,
        journal: ProfileHydrationJournalV1,
        capability: LocalProfileHydrationCapabilityV1
    ) {
        self.standardizedProfileDirectoryURL = standardizedProfileDirectoryURL
        self.journal = journal
        self.capability = capability
    }

    func confirmsPredecessorAbort(
        journal: ProfileHydrationJournalV1,
        profileDirectoryURL: URL,
        capability: LocalProfileHydrationCapabilityV1
    ) -> Bool {
        self.journal == journal
            && standardizedProfileDirectoryURL
                == profileDirectoryURL.standardizedFileURL
            && self.capability == capability
    }
}

/// Sealed evidence that the exact target candidate was installed and its
/// journal removed while a scoped checkpoint lease confirmed the target.
/// Repository adoption still verifies both installed profile copies.
struct ProfileHydrationTargetCleanupConfirmationV1: Equatable, Sendable {
    private let standardizedProfileDirectoryURL: URL
    private let journal: ProfileHydrationJournalV1
    private let capability: LocalProfileHydrationCapabilityV1

    fileprivate init(
        standardizedProfileDirectoryURL: URL,
        journal: ProfileHydrationJournalV1,
        capability: LocalProfileHydrationCapabilityV1
    ) {
        self.standardizedProfileDirectoryURL = standardizedProfileDirectoryURL
        self.journal = journal
        self.capability = capability
    }

    func confirmsTargetCleanup(
        journal: ProfileHydrationJournalV1,
        profileDirectoryURL: URL,
        capability: LocalProfileHydrationCapabilityV1
    ) -> Bool {
        self.journal == journal
            && standardizedProfileDirectoryURL
                == profileDirectoryURL.standardizedFileURL
            && self.capability == capability
    }
}

enum ProfileHydrationStartupRecoveryDispositionV1: Equatable, Sendable {
    case noDurableJournal
    case predecessorAborted
    case targetCleaned
}

/// Diagnostic evidence for recovery performed before any repository is
/// loaded, when a prior process capability cannot exist. It is deliberately a
/// different sealed type from both active-transaction confirmations and is
/// never accepted by `LocalPlayerProfileRepository` to release a live barrier.
struct ProfileHydrationStartupRecoveryResultV1: Equatable, Sendable {
    let disposition: ProfileHydrationStartupRecoveryDispositionV1
    let transactionID: UUID?
    let journalSourceDigest: ProfileHydrationDigest?
    let journalCandidateDigest: ProfileHydrationDigest?

    fileprivate init(
        disposition: ProfileHydrationStartupRecoveryDispositionV1,
        journal: ProfileHydrationJournalV1?
    ) {
        self.disposition = disposition
        transactionID = journal?.transactionID
        journalSourceDigest = journal?.sourceProfileEnvelopeDigest
        journalCandidateDigest = journal?.candidateProfileEnvelopeDigest
    }
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
    func admitHydration(
        _ journal: ProfileHydrationJournalV1,
        permit: borrowing LocalProfileHydrationAdmissionPermitV1,
        onPendingClaimEstablished: () -> Void
    ) throws -> ProfileHydrationJournalWriteResult {
        guard permit.authorizesHydrationAdmission(
            journal: journal,
            profileDirectoryURL: locations.profileDirectoryURL
        ) else {
            throw ProfileHydrationTransactionStoreError
                .repositoryAdmissionMismatch
        }
        let recoveryHandle = try permit.completionRecoveryHandle(
            journal: journal,
            profileDirectoryURL: locations.profileDirectoryURL
        )
        let physicalDirectoryIdentity = try physicalProfileDirectoryIdentity(
            beforeAdmission: true
        )
        try LocalProfileHydrationCompletionRegistryV1.shared.claimPending(
            recoveryHandle,
            physicalDirectoryIdentity: physicalDirectoryIdentity,
            journal: journal,
            profileDirectoryURL: locations.profileDirectoryURL
        )
        // The caller installs its actor barrier synchronously here. Pending
        // physical authority already blocks aliased startup recovery, and the
        // file lock has not yet been requested, closing the issued-only race.
        onPendingClaimEstablished()
        return try beginHydrationCore(
            journal,
            recoveryHandle: recoveryHandle,
            preclaimedPhysicalDirectoryIdentity: physicalDirectoryIdentity
        )
    }

#if DEBUG
    /// Low-level durability tests exercise the file transaction independently.
    /// Release builds require the bounded repository admission permit above.
    func _testOnlyBeginHydration(
        _ journal: ProfileHydrationJournalV1
    ) throws -> ProfileHydrationJournalWriteResult {
        try beginHydrationCore(
            journal,
            recoveryHandle: nil,
            preclaimedPhysicalDirectoryIdentity: nil
        )
    }
#endif

    private func beginHydrationCore(
        _ journal: ProfileHydrationJournalV1,
        recoveryHandle: LocalProfileHydrationRecoveryHandleV1?,
        preclaimedPhysicalDirectoryIdentity:
            ProfileHydrationPhysicalDirectoryIdentityV1?
    ) throws -> ProfileHydrationJournalWriteResult {
        try withLock {
            if let recoveryHandle {
                guard let preclaimedPhysicalDirectoryIdentity else {
                    throw ProfileHydrationTransactionStoreError
                        .repositoryAdmissionMismatch
                }
                let lockedPhysicalDirectoryIdentity =
                    try physicalProfileDirectoryIdentity(
                        beforeAdmission: false
                    )
                guard lockedPhysicalDirectoryIdentity
                        == preclaimedPhysicalDirectoryIdentity else {
                    throw ProfileHydrationTransactionStoreError
                        .profileDirectoryIdentityMismatch
                }
                try LocalProfileHydrationCompletionRegistryV1.shared
                    .activateCurrent(
                        recoveryHandle,
                        physicalDirectoryIdentity:
                            lockedPhysicalDirectoryIdentity,
                        journal: journal,
                        profileDirectoryURL: locations.profileDirectoryURL
                    )
            }
            let canonicalData = try validatedCanonicalData(for: journal)
            let preflight = try resolveJournal(expected: nil, repair: false)
            if let preflight {
                guard preflight.data == canonicalData else {
                    throw ProfileHydrationTransactionStoreError.journalAlreadyExists
                }
                let preflightInspection = try inspect(
                    journal: preflight.journal,
                    repair: preflight.repair
                )
                try ensureInstallable(preflightInspection)

                guard let existing = try resolveJournal(
                    expected: nil,
                    repair: true
                ), existing.data == preflight.data else {
                    throw ProfileHydrationTransactionStoreError
                        .journalCopiesDisagree
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
            guard let resolved = try resolveJournal(
                expected: expected,
                repair: false
            ) else {
                return nil
            }
            return try inspect(journal: resolved.journal, repair: resolved.repair)
        }
    }

    func installCandidate(
        transactionID: UUID,
        expected: ProfileHydrationExpectedBinding,
        checkpointLease: borrowing CloudReplicaCheckpointFreshnessLeaseV1
    ) throws -> ProfileHydrationCandidateInstallResult {
        try withLock {
            guard let preflight = try resolveJournal(
                expected: expected,
                repair: false
            ) else {
                throw ProfileHydrationTransactionStoreError.noValidJournalCopy
            }
            guard preflight.journal.transactionID == transactionID else {
                throw ProfileHydrationTransactionStoreError.transactionMismatch
            }
            guard checkpointLease.relationship(to: preflight.journal) == .target else {
                throw ProfileHydrationTransactionStoreError
                    .checkpointConfirmationMismatch
            }
            let preflightInspection = try inspect(
                journal: preflight.journal,
                repair: preflight.repair
            )
            try ensureInstallable(preflightInspection)

            guard let resolved = try resolveJournal(
                expected: expected,
                repair: true
            ), resolved.data == preflight.data else {
                throw ProfileHydrationTransactionStoreError
                    .journalCopiesDisagree
            }
            guard resolved.journal.transactionID == transactionID else {
                throw ProfileHydrationTransactionStoreError.transactionMismatch
            }
            guard checkpointLease.relationship(to: resolved.journal) == .target else {
                throw ProfileHydrationTransactionStoreError
                    .checkpointConfirmationMismatch
            }
            let before = try inspect(
                journal: resolved.journal,
                repair: resolved.repair
            )
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

    /// Abandons a prepared hydration only while a scoped checkpoint lease
    /// confirms that the journal's exact predecessor is still current and both
    /// profile copies remain the exact source bytes. No missing or divergent
    /// profile copy is repaired: ambiguous state retains the complete barrier.
    /// When no journal or quarantine evidence exists, `nil` is an
    /// unauthenticated, non-destructive durable-absence reconciliation; there
    /// is no journal against which transaction, binding, or lease inputs
    /// could be authenticated.
    func confirmPredecessorAbort(
        transactionID: UUID,
        expected: ProfileHydrationExpectedBinding,
        checkpointLease: borrowing CloudReplicaCheckpointFreshnessLeaseV1,
        recoveryHandle: LocalProfileHydrationRecoveryHandleV1
    ) throws -> ProfileHydrationPredecessorAbortConfirmationV1? {
        let physicalDirectoryIdentity = try physicalProfileDirectoryIdentity(
            beforeAdmission: false
        )
        let attempt = try LocalProfileHydrationCompletionRegistryV1.shared
            .beginAttempt(
            recoveryHandle,
            physicalDirectoryIdentity: physicalDirectoryIdentity,
            profileDirectoryURL: locations.profileDirectoryURL
        )
        do {
            guard let journal = try confirmPredecessorAbortCore(
                transactionID: transactionID,
                expected: expected,
                checkpointLease: checkpointLease,
                admission: .active(attempt)
            ) else {
                return nil
            }
            return ProfileHydrationPredecessorAbortConfirmationV1(
                standardizedProfileDirectoryURL:
                    locations.profileDirectoryURL.standardizedFileURL,
                journal: journal,
                capability: recoveryHandle.capability
            )
        } catch {
            LocalProfileHydrationCompletionRegistryV1.shared
                .resetRetryableIfCurrent(attempt)
            throw error
        }
    }

    private func confirmPredecessorAbortCore(
        transactionID: UUID,
        expected: ProfileHydrationExpectedBinding,
        checkpointLease: borrowing CloudReplicaCheckpointFreshnessLeaseV1,
        admission: HydrationRemovalAdmission
    ) throws -> ProfileHydrationJournalV1? {
        try withLock {
            try validateRemovalAdmission(admission, journal: nil)
            guard let resolved = try resolveJournal(
                expected: expected,
                repair: false
            ) else {
                try removeDurableBarrier()
                resetRemovalAdmissionAfterUnauthenticatedAbsence(admission)
                return nil
            }
            guard resolved.journal.transactionID == transactionID else {
                throw ProfileHydrationTransactionStoreError.transactionMismatch
            }
            try validateRemovalAdmission(
                admission,
                journal: resolved.journal
            )
            guard checkpointLease.relationship(to: resolved.journal)
                == .predecessor else {
                throw ProfileHydrationTransactionStoreError
                    .checkpointConfirmationMismatch
            }

            let primary = try profileCopyState(
                at: locations.profilePrimaryURL,
                journal: resolved.journal
            )
            let backup = try profileCopyState(
                at: locations.profileBackupURL,
                journal: resolved.journal
            )
            guard primary == .source, backup == .source else {
                throw ProfileHydrationTransactionStoreError.sourceOnlyAbortRejected(
                    primary: primary,
                    backup: backup
                )
            }

            try removeDurableBarrier(preserving: resolved.data)
            try consumeRemovalAdmission(
                admission,
                journal: resolved.journal
            )
            return resolved.journal
        }
    }

    /// The caller supplies a scoped lease minted while the checkpoint store
    /// holds the account authority lock. No cleanup occurs unless it confirms
    /// the exact target bound into the journal.
    /// When no journal or quarantine evidence exists, `nil` is an
    /// unauthenticated, non-destructive durable-absence reconciliation; there
    /// is no journal against which transaction, binding, or lease inputs
    /// could be authenticated.
    func confirmTargetCleanup(
        transactionID: UUID,
        expected: ProfileHydrationExpectedBinding,
        checkpointLease: borrowing CloudReplicaCheckpointFreshnessLeaseV1,
        recoveryHandle: LocalProfileHydrationRecoveryHandleV1
    ) throws -> ProfileHydrationTargetCleanupConfirmationV1? {
        let physicalDirectoryIdentity = try physicalProfileDirectoryIdentity(
            beforeAdmission: false
        )
        let attempt = try LocalProfileHydrationCompletionRegistryV1.shared
            .beginAttempt(
            recoveryHandle,
            physicalDirectoryIdentity: physicalDirectoryIdentity,
            profileDirectoryURL: locations.profileDirectoryURL
        )
        do {
            guard let journal = try confirmTargetCleanupCore(
                transactionID: transactionID,
                expected: expected,
                checkpointLease: checkpointLease,
                admission: .active(attempt)
            ) else {
                return nil
            }
            return ProfileHydrationTargetCleanupConfirmationV1(
                standardizedProfileDirectoryURL:
                    locations.profileDirectoryURL.standardizedFileURL,
                journal: journal,
                capability: recoveryHandle.capability
            )
        } catch {
            LocalProfileHydrationCompletionRegistryV1.shared
                .resetRetryableIfCurrent(attempt)
            throw error
        }
    }

    private func confirmTargetCleanupCore(
        transactionID: UUID,
        expected: ProfileHydrationExpectedBinding,
        checkpointLease: borrowing CloudReplicaCheckpointFreshnessLeaseV1,
        admission: HydrationRemovalAdmission
    ) throws -> ProfileHydrationJournalV1? {
        try withLock {
            try validateRemovalAdmission(admission, journal: nil)
            guard let resolved = try resolveJournal(
                expected: expected,
                repair: false
            ) else {
                try removeDurableBarrier()
                resetRemovalAdmissionAfterUnauthenticatedAbsence(admission)
                return nil
            }
            guard resolved.journal.transactionID == transactionID else {
                throw ProfileHydrationTransactionStoreError.transactionMismatch
            }
            try validateRemovalAdmission(
                admission,
                journal: resolved.journal
            )
            guard checkpointLease.relationship(to: resolved.journal)
                == .target else {
                throw ProfileHydrationTransactionStoreError.checkpointConfirmationMismatch
            }
            let inspection = try inspect(journal: resolved.journal, repair: resolved.repair)
            guard inspection.installationState == .candidate else {
                throw ProfileHydrationTransactionStoreError.profileVerificationFailed
            }

            try removeDurableBarrier(preserving: resolved.data)
            try consumeRemovalAdmission(
                admission,
                journal: resolved.journal
            )
            return resolved.journal
        }
    }

    /// Startup recovery is admitted only when the store's file-lock-protected
    /// registry preflight proves that this process has no live completion
    /// authority for the directory. The checkpoint lease and exact durable
    /// journal then authorize deterministic predecessor recovery. This result
    /// is diagnostic only and cannot release any repository barrier.
    func recoverPredecessorBeforeRepositoryLoad(
        transactionID: UUID,
        expected: ProfileHydrationExpectedBinding,
        checkpointLease: borrowing CloudReplicaCheckpointFreshnessLeaseV1
    ) throws -> ProfileHydrationStartupRecoveryResultV1 {
        let journal = try confirmPredecessorAbortCore(
            transactionID: transactionID,
            expected: expected,
            checkpointLease: checkpointLease,
            admission: .startupRecovery
        )
        return ProfileHydrationStartupRecoveryResultV1(
            disposition: journal == nil
                ? .noDurableJournal
                : .predecessorAborted,
            journal: journal
        )
    }

    /// Completes target cleanup before repository load after the candidate is
    /// exactly installed and the scoped checkpoint lease confirms its target.
    /// It never mints the active-process proof required by repository adoption.
    func recoverTargetBeforeRepositoryLoad(
        transactionID: UUID,
        expected: ProfileHydrationExpectedBinding,
        checkpointLease: borrowing CloudReplicaCheckpointFreshnessLeaseV1
    ) throws -> ProfileHydrationStartupRecoveryResultV1 {
        let journal = try confirmTargetCleanupCore(
            transactionID: transactionID,
            expected: expected,
            checkpointLease: checkpointLease,
            admission: .startupRecovery
        )
        return ProfileHydrationStartupRecoveryResultV1(
            disposition: journal == nil
                ? .noDurableJournal
                : .targetCleaned,
            journal: journal
        )
    }

    private enum HydrationRemovalAdmission {
        case active(LocalProfileHydrationCompletionAttemptV1)
        case startupRecovery
    }

    private func validateRemovalAdmission(
        _ admission: HydrationRemovalAdmission,
        journal: ProfileHydrationJournalV1?
    ) throws {
        let physicalDirectoryIdentity = try physicalProfileDirectoryIdentity(
            beforeAdmission: false
        )
        switch admission {
        case let .active(attempt):
            try LocalProfileHydrationCompletionRegistryV1.shared
                .revalidateCurrent(
                    attempt,
                    physicalDirectoryIdentity: physicalDirectoryIdentity,
                    journal: journal ?? attempt.journal,
                    profileDirectoryURL: locations.profileDirectoryURL
                )
        case .startupRecovery:
            try LocalProfileHydrationCompletionRegistryV1.shared
                .rejectStartupRecoveryIfLiveAdmission(
                    physicalDirectoryIdentity: physicalDirectoryIdentity
            )
        }
    }

    /// Called under the file lock immediately after the last exact journal
    /// copy is durably absent. Consumption therefore cannot race an identical
    /// re-admission in this process.
    private func consumeRemovalAdmission(
        _ admission: HydrationRemovalAdmission,
        journal: ProfileHydrationJournalV1
    ) throws {
        guard case let .active(attempt) = admission else { return }
        let physicalDirectoryIdentity = try physicalProfileDirectoryIdentity(
            beforeAdmission: false
        )
        try LocalProfileHydrationCompletionRegistryV1.shared
            .consumeAfterDurableRemoval(
                attempt,
                physicalDirectoryIdentity: physicalDirectoryIdentity,
                journal: journal,
                profileDirectoryURL: locations.profileDirectoryURL
            )
    }

    /// Missing durable evidence cannot mint a repository-release proof. The
    /// current authority remains retryable, while a superseded authority is
    /// deliberately left terminal.
    private func resetRemovalAdmissionAfterUnauthenticatedAbsence(
        _ admission: HydrationRemovalAdmission
    ) {
        guard case let .active(attempt) = admission else { return }
        LocalProfileHydrationCompletionRegistryV1.shared
            .resetRetryableIfCurrent(attempt)
    }

#if DEBUG
    func _testOnlyClaimCompletionAttempt(
        recoveryHandle: LocalProfileHydrationRecoveryHandleV1
    ) throws -> ProfileHydrationCompletionClaimTestTokenV1 {
        let physicalDirectoryIdentity = try physicalProfileDirectoryIdentity(
            beforeAdmission: false
        )
        return ProfileHydrationCompletionClaimTestTokenV1(
            attempt: try LocalProfileHydrationCompletionRegistryV1.shared
                .beginAttempt(
                    recoveryHandle,
                    physicalDirectoryIdentity: physicalDirectoryIdentity,
                    profileDirectoryURL: locations.profileDirectoryURL
                )
        )
    }

    func _testOnlyReleaseCompletionAttempt(
        _ token: ProfileHydrationCompletionClaimTestTokenV1
    ) {
        LocalProfileHydrationCompletionRegistryV1.shared
            .resetRetryableIfCurrent(token.attempt)
    }

    /// Compatibility seams for low-level file-transaction matrix tests. Release
    /// code receives sealed confirmations rather than unauthenticated Booleans.
    @discardableResult
    func _testOnlyAbortHydrationAfterPredecessorConfirmation(
        transactionID: UUID,
        expected: ProfileHydrationExpectedBinding,
        checkpointLease: borrowing CloudReplicaCheckpointFreshnessLeaseV1
    ) throws -> Bool {
        try confirmPredecessorAbortCore(
            transactionID: transactionID,
            expected: expected,
            checkpointLease: checkpointLease,
            admission: .startupRecovery
        ) != nil
    }

    @discardableResult
    func _testOnlyRemoveJournalAfterCheckpointConfirmation(
        transactionID: UUID,
        expected: ProfileHydrationExpectedBinding,
        checkpointLease: borrowing CloudReplicaCheckpointFreshnessLeaseV1
    ) throws -> Bool {
        try confirmTargetCleanupCore(
            transactionID: transactionID,
            expected: expected,
            checkpointLease: checkpointLease,
            admission: .startupRecovery
        ) != nil
    }
#endif

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
        guard try itemIsPresent(at: url) else { return .missing(url) }
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
        guard try itemIsPresent(at: url) else { return .missing }
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
        guard try itemIsPresent(at: url) else {
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
        guard try itemIsPresent(at: url) else { return }
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
        var destination: URL?
        for index in 0 ..< limits.maximumQuarantineFiles {
            let candidate = locations.quarantineSlotURL(index)
            if try !itemIsPresent(at: candidate) {
                destination = candidate
                break
            }
        }
        guard let destination else {
            throw ProfileHydrationTransactionStoreError.quarantineCapacityExceeded
        }
        do {
            try fileSystem.createDirectory(at: locations.quarantineDirectoryURL)
            try fileSystem.moveItemDurably(at: url, to: destination)
        } catch {
            throw mapped(error)
        }
        guard try !itemIsPresent(at: url),
              try itemIsPresent(at: destination) else {
            throw ProfileHydrationTransactionStoreError.ioFailure
        }
    }

    private func quarantineEvidenceURLs() throws -> [URL] {
        var result: [URL] = []
        for index in 0 ..< limits.maximumQuarantineFiles {
            let url = locations.quarantineSlotURL(index)
            if try itemIsPresent(at: url) {
                result.append(url)
            }
        }
        return result
    }

    private func removeAllQuarantineEvidence() throws {
        for index in 0 ..< limits.maximumQuarantineFiles {
            // Visit every bounded slot, including slots already observed as
            // missing. This re-syncs the quarantine directory after an earlier
            // removal whose durability outcome was ambiguous.
            try removeAndVerifyMissing(
                at: locations.quarantineSlotURL(index)
            )
        }
    }

    /// Evidence is removed first and an exact journal copy last, so a usable
    /// barrier remains until the final removal attempt. If that final removal
    /// reports a durability ambiguity after unlink, no active-process proof is
    /// minted: retry observes unauthenticated absence and the live authority
    /// keeps startup recovery blocked until actor/process recreation. A retry
    /// with no journal still executes this complete durable-absence sequence.
    private func removeDurableBarrier(
        preserving journalData: Data? = nil
    ) throws {
        try fileSystem.createDirectory(at: locations.journalDirectoryURL)
        try fileSystem.createDirectory(at: locations.quarantineDirectoryURL)
        try removeAllQuarantineEvidence()

        // Normally the backup is removed first and the primary remains as the
        // last valid barrier. If recovery was authorized from the backup alone,
        // remove the invalid/missing primary first so the one valid journal is
        // still retained until the final removal attempt.
        if let journalData,
           try exactJournalCopyMatches(
               journalData,
               at: locations.journalBackupURL
           ),
           try !exactJournalCopyMatches(
               journalData,
               at: locations.journalPrimaryURL
           ) {
            try removeAndVerifyMissing(at: locations.journalPrimaryURL)
            try removeAndVerifyMissing(at: locations.journalBackupURL)
        } else {
            try removeAndVerifyMissing(at: locations.journalBackupURL)
            try removeAndVerifyMissing(at: locations.journalPrimaryURL)
        }
    }

    private func exactJournalCopyMatches(
        _ expectedData: Data,
        at url: URL
    ) throws -> Bool {
        do {
            guard try fileSystem.itemStatus(at: url) == .present,
                  try fileSystem.fileSize(at: url) == expectedData.count else {
                return false
            }
            return try fileSystem.read(from: url) == expectedData
        } catch {
            throw mapped(error)
        }
    }

    private func removeAndVerifyMissing(at url: URL) throws {
        do {
            try fileSystem.removeItemDurably(at: url)
            guard try fileSystem.itemStatus(at: url) == .missing else {
                throw ProfileHydrationTransactionStoreError.ioFailure
            }
        } catch let error as ProfileHydrationTransactionStoreError {
            throw error
        } catch {
            throw mapped(error)
        }
    }

    private func itemIsPresent(at url: URL) throws -> Bool {
        do {
            return try fileSystem.itemStatus(at: url) == .present
        } catch {
            throw mapped(error)
        }
    }

    private func physicalProfileDirectoryIdentity(
        beforeAdmission: Bool
    ) throws -> ProfileHydrationPhysicalDirectoryIdentityV1 {
        var metadata = stat()
        let result = locations.profileDirectoryURL.path.withCString {
            stat($0, &metadata)
        }
        guard result == 0,
              metadata.st_mode & S_IFMT == S_IFDIR,
              metadata.st_ino != 0 else {
            throw beforeAdmission
                ? ProfileHydrationTransactionStoreError
                    .profileDirectoryIdentityUnavailableBeforeAdmission
                : ProfileHydrationTransactionStoreError
                    .profileDirectoryIdentityUnavailable
        }
        return ProfileHydrationPhysicalDirectoryIdentityV1(
            device: UInt64(metadata.st_dev),
            inode: UInt64(metadata.st_ino)
        )
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

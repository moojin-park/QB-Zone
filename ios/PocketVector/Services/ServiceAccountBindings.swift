import CryptoKit
import Foundation

/// A stable, opaque account key supplied by the account coordinator. It must
/// not contain an email address, Game Center alias, or other display identity.
struct ServiceAccountKey: RawRepresentable, Codable, Equatable, Hashable, Sendable {
    static let persistedTypeIdentifier = "ServiceAccountKey"
    static let persistedEncodingIdentifier = "single-value-raw-string-v1"

    let rawValue: String

    init(rawValue: String) {
        precondition(!rawValue.isEmpty, "ServiceAccountKey cannot be empty")
        self.rawValue = rawValue
    }

    init(_ rawValue: String) {
        self.init(rawValue: rawValue)
    }
}

/// Stable ownership survives a normal relaunch. It deliberately excludes the
/// active session nonce so unfinished work can resume for the same profile.
struct DurableAccountBinding: Codable, Equatable, Hashable, Sendable {
    let accountKey: ServiceAccountKey
    let profileID: UUID

    enum CodingKeys: String, CodingKey, CaseIterable {
        case accountKey
        case profileID
    }

    static var persistedFieldManifest: String {
        CodingKeys.allCases.map(\.rawValue).sorted().joined(separator: ",")
    }
}

/// A nonce is minted for each active repository session. Old callbacks cannot
/// mutate a newly activated session even when durable ownership is unchanged.
struct ActiveAccountSession: Codable, Equatable, Hashable, Sendable {
    let binding: DurableAccountBinding
    let nonce: UUID
}

struct StoreAccountBinding: Codable, Equatable, Hashable, Sendable {
    let account: DurableAccountBinding
    let appAccountToken: UUID
}

struct StoreActiveSession: Codable, Equatable, Hashable, Sendable {
    let binding: StoreAccountBinding
    let nonce: UUID
}

enum CloudAccountBindingDerivationV1 {
    static let semanticIdentifier =
        "pocket-vector-private-cloud-account-binding-derivation-v1"
    static let rootDomain =
        "pocket-vector-private-cloud-account-binding-v1"
    static let playerIdentityDomain = "player-account-identity-v1"
    static let serviceAccountKeyDomain = "service-account-key-v1"
    static let profileIDDomain = "profile-id-v1"
    static let storeAppAccountTokenDomain = "store-app-account-token-v1"
    static let digestAlgorithmIdentifier = "sha256-v1"
    static let componentEncodingIdentifier =
        "uint64-big-endian-length-prefixed-utf8-components-v1"
    static let hexEncodingIdentifier = "lowercase-two-digit-hex-per-byte-v1"
    static let uuidEncodingIdentifier =
        "sha256-first-16-bytes-rfc9562-version-8-variant-v1"

    /// Store account-token derivation is owned by the StoreKit scope. Profile
    /// scope binds only outputs persisted in profile payloads.
    static var profileFingerprintMaterial: [String] {
        [
            semanticIdentifier,
            "rootDomain", rootDomain,
            "playerIdentityDomain", playerIdentityDomain,
            "serviceAccountKeyDomain", serviceAccountKeyDomain,
            "profileIDDomain", profileIDDomain,
            "digestAlgorithm", digestAlgorithmIdentifier,
            "componentEncoding", componentEncodingIdentifier,
            "hexEncoding", hexEncodingIdentifier,
            "uuidEncoding", uuidEncodingIdentifier,
            "serviceAccountKeyType",
            ServiceAccountKey.persistedTypeIdentifier,
            "serviceAccountKeyEncoding",
            ServiceAccountKey.persistedEncodingIdentifier,
        ]
    }
}

/// Stable account ownership derived only from the already opaque private-cloud
/// account identifier. Each output uses a separate versioned domain so a value
/// from one service can never be substituted for another service's identity.
///
/// These values are deterministic across devices signed in to the same iCloud
/// account. They deliberately do not depend on a device identifier, Game
/// Center player, display alias, email address, or active-session nonce.
struct CloudAccountDerivedBindings: Equatable, Sendable {
    let playerAccountIdentity: PlayerAccountIdentity
    let durableAccountBinding: DurableAccountBinding
    let storeAccountBinding: StoreAccountBinding

    static var profileFingerprintMaterial: [String] {
        CloudAccountBindingDerivationV1.profileFingerprintMaterial
    }

    static func derive(from cloudAccountID: CloudAccountID) -> Self {
        let playerAccountIdentity = PlayerAccountIdentity(
            AccountBindingDigest.hex(
                domain: CloudAccountBindingDerivationV1.playerIdentityDomain,
                cloudAccountID: cloudAccountID
            )
        )
        let durableAccountBinding = DurableAccountBinding(
            accountKey: ServiceAccountKey(
                AccountBindingDigest.hex(
                    domain: CloudAccountBindingDerivationV1.serviceAccountKeyDomain,
                    cloudAccountID: cloudAccountID
                )
            ),
            profileID: AccountBindingDigest.uuid(
                domain: CloudAccountBindingDerivationV1.profileIDDomain,
                cloudAccountID: cloudAccountID
            )
        )
        return Self(
            playerAccountIdentity: playerAccountIdentity,
            durableAccountBinding: durableAccountBinding,
            storeAccountBinding: StoreAccountBinding(
                account: durableAccountBinding,
                appAccountToken: AccountBindingDigest.uuid(
                    domain: CloudAccountBindingDerivationV1.storeAppAccountTokenDomain,
                    cloudAccountID: cloudAccountID
                )
            )
        )
    }
}

/// Process-local proof that an account authority still owns one exact cloud
/// account, replica scope, and replica epoch. The UUID is deliberately hidden:
/// callers can compare tokens but cannot create, persist, or reinterpret them
/// as an account-session nonce, replica epoch, or checkpoint generation.
struct AccountGenerationToken: Equatable, Hashable, Sendable {
    fileprivate let authorityIdentity: AccountGenerationAuthorityIdentity
    fileprivate let identifier: UUID

    fileprivate init(
        authorityIdentity: AccountGenerationAuthorityIdentity,
        identifier: UUID
    ) {
        self.authorityIdentity = authorityIdentity
        self.identifier = identifier
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.authorityIdentity === rhs.authorityIdentity
            && lhs.identifier == rhs.identifier
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(authorityIdentity))
        hasher.combine(identifier)
    }
}

/// Retained by every token so allocator address reuse cannot make a later
/// authority instance compare equal to a destroyed authority.
fileprivate final class AccountGenerationAuthorityIdentity: Sendable {}

/// The complete account-generation binding protected by
/// ``CloudAccountGenerationAuthority``. Derived service ownership travels with
/// the cloud identity so a commit cannot accidentally mix account domains.
struct ActiveCloudAccountGeneration: Equatable, Sendable {
    let token: AccountGenerationToken
    let accountID: CloudAccountID
    let derivedBindings: CloudAccountDerivedBindings
    let configurationScopeFingerprint: CloudReplicaScopeFingerprint
    let replicaEpoch: UUID

    fileprivate init(
        token: AccountGenerationToken,
        accountID: CloudAccountID,
        derivedBindings: CloudAccountDerivedBindings,
        configurationScopeFingerprint: CloudReplicaScopeFingerprint,
        replicaEpoch: UUID
    ) {
        self.token = token
        self.accountID = accountID
        self.derivedBindings = derivedBindings
        self.configurationScopeFingerprint = configurationScopeFingerprint
        self.replicaEpoch = replicaEpoch
    }
}

enum CloudAccountGenerationAuthorityError: Error, Equatable, Sendable {
    case noActiveGeneration
    case generationNotCurrent
    case tokenFactoryReturnedZero
    case tokenFactoryCollision
    case tokenHistoryLimitReached
}

/// Owns the current process-local account generation. This actor intentionally
/// has no CloudKit or persistence responsibilities: a future account router
/// supplies an already established account, scope, and replica epoch.
///
/// Actor reentrancy normally permits account transitions while an async commit
/// body is suspended. A shared FIFO gate therefore covers activation,
/// invalidation, and the complete `withCurrentGeneration` body.
actor CloudAccountGenerationAuthority {
    typealias TokenUUIDFactory = @Sendable () -> UUID

    private struct CommitOperationWaiter {
        let id: UInt64
        let continuation: CheckedContinuation<Bool, Never>
    }

    private static let zeroUUID = UUID(
        uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    )

    private let tokenUUIDFactory: TokenUUIDFactory
    private let maximumIssuedTokenCount: Int
    private let authorityIdentity = AccountGenerationAuthorityIdentity()
    private var activeGeneration: ActiveCloudAccountGeneration?
    private var issuedTokenIdentifiers: Set<UUID> = []
    private var commitOperationIsRunning = false
    private var commitOperationWaiters: [CommitOperationWaiter] = []
    private var nextCommitOperationWaiterID: UInt64 = 0

    init(
        maximumIssuedTokenCount: Int = 4_096,
        tokenUUIDFactory: @escaping TokenUUIDFactory = { UUID() }
    ) {
        precondition(maximumIssuedTokenCount > 0)
        self.maximumIssuedTokenCount = maximumIssuedTokenCount
        self.tokenUUIDFactory = tokenUUIDFactory
    }

    /// Returns the existing generation only when the complete binding remains
    /// active. Every account, scope, or epoch transition mints a fresh token.
    func activate(
        accountID: CloudAccountID,
        configurationScopeFingerprint: CloudReplicaScopeFingerprint,
        replicaEpoch: UUID
    ) async throws -> ActiveCloudAccountGeneration {
        try await acquireCommitOperationGate()
        defer { releaseCommitOperationGate() }
        try Task.checkCancellation()

        let derivedBindings = CloudAccountDerivedBindings.derive(from: accountID)
        if let activeGeneration,
           activeGeneration.accountID == accountID,
           activeGeneration.derivedBindings == derivedBindings,
           activeGeneration.configurationScopeFingerprint
            == configurationScopeFingerprint,
           activeGeneration.replicaEpoch == replicaEpoch {
            return activeGeneration
        }

        // Remembering every issued identifier prevents ABA token reuse. The
        // explicit process-local cap keeps that protection memory-bounded. At
        // the cap this authority fails closed on every new transition until a
        // process restart; replacing a live authority could create split-brain
        // ownership and is deliberately not an in-process recovery strategy.
        guard issuedTokenIdentifiers.count < maximumIssuedTokenCount else {
            throw CloudAccountGenerationAuthorityError.tokenHistoryLimitReached
        }
        let identifier = tokenUUIDFactory()
        guard identifier != Self.zeroUUID else {
            throw CloudAccountGenerationAuthorityError.tokenFactoryReturnedZero
        }
        guard !issuedTokenIdentifiers.contains(identifier) else {
            throw CloudAccountGenerationAuthorityError.tokenFactoryCollision
        }

        let generation = ActiveCloudAccountGeneration(
            token: AccountGenerationToken(
                authorityIdentity: authorityIdentity,
                identifier: identifier
            ),
            accountID: accountID,
            derivedBindings: derivedBindings,
            configurationScopeFingerprint: configurationScopeFingerprint,
            replicaEpoch: replicaEpoch
        )
        issuedTokenIdentifiers.insert(identifier)
        activeGeneration = generation
        return generation
    }

    /// Compare-and-swap invalidation. A callback holding an older generation
    /// can never clear a generation activated after it.
    func invalidate(_ expectedGeneration: ActiveCloudAccountGeneration) async throws {
        try await acquireCommitOperationGate()
        defer { releaseCommitOperationGate() }
        try Task.checkCancellation()

        guard let activeGeneration else {
            throw CloudAccountGenerationAuthorityError.noActiveGeneration
        }
        guard activeGeneration == expectedGeneration else {
            throw CloudAccountGenerationAuthorityError.generationNotCurrent
        }
        self.activeGeneration = nil
    }

    /// Runs one commit-sized operation only while `expectedGeneration` is the
    /// exact current generation. The gate remains held across suspension; all
    /// account transitions queue behind the body in FIFO arrival order.
    /// `operation` must not call activation, invalidation, or this method on the
    /// same authority, because those calls intentionally wait for this body. It
    /// must contain only bounded local commit, adoption, or publication work;
    /// network fetches happen before entry and are revalidated here before use.
    func withCurrentGeneration<Result: Sendable>(
        _ expectedGeneration: ActiveCloudAccountGeneration,
        perform operation: @Sendable () async throws -> Result
    ) async throws -> Result {
        try await acquireCommitOperationGate()
        defer { releaseCommitOperationGate() }
        try Task.checkCancellation()

        guard let activeGeneration else {
            throw CloudAccountGenerationAuthorityError.noActiveGeneration
        }
        guard activeGeneration == expectedGeneration else {
            throw CloudAccountGenerationAuthorityError.generationNotCurrent
        }

        // The body owns its outcome after admission. In particular, do not
        // turn a successfully returned durable commit into ambiguous
        // CancellationError merely because cancellation arrived during it.
        return try await operation()
    }

    /// Narrow diagnostic used to deterministically verify FIFO admission. It
    /// does not expose the active generation or alter gate ordering.
    func queuedCommitOperationCount() -> Int {
        commitOperationWaiters.count
    }

    private func acquireCommitOperationGate() async throws {
        try Task.checkCancellation()
        if !commitOperationIsRunning {
            commitOperationIsRunning = true
            return
        }

        let waiterID = nextCommitOperationWaiterID
        let advancedID = nextCommitOperationWaiterID.addingReportingOverflow(1)
        precondition(!advancedID.overflow, "Commit-operation waiter ID exhausted")
        nextCommitOperationWaiterID = advancedID.partialValue

        // The continuation closure appends synchronously while this actor job
        // still owns isolation. The cancellation handler's actor hop cannot
        // observe this waiter before it is present in the FIFO.
        let granted = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                commitOperationWaiters.append(
                    CommitOperationWaiter(
                        id: waiterID,
                        continuation: continuation
                    )
                )
            }
        } onCancel: {
            Task { await self.cancelCommitOperationWaiter(id: waiterID) }
        }

        guard granted else {
            throw CancellationError()
        }
        if Task.isCancelled {
            releaseCommitOperationGate()
            throw CancellationError()
        }
    }

    private func releaseCommitOperationGate() {
        guard !commitOperationWaiters.isEmpty else {
            commitOperationIsRunning = false
            return
        }
        let next = commitOperationWaiters.removeFirst()
        next.continuation.resume(returning: true)
    }

    private func cancelCommitOperationWaiter(id: UInt64) {
        // Absence means the waiter was already granted. Its resumed acquire
        // path observes cancellation and hands the gate baton onward exactly
        // once before throwing.
        guard let index = commitOperationWaiters.firstIndex(where: { $0.id == id }) else {
            return
        }
        let waiter = commitOperationWaiters.remove(at: index)
        waiter.continuation.resume(returning: false)
    }
}

private enum AccountBindingDigest {
    static func hex(domain: String, cloudAccountID: CloudAccountID) -> String {
        digest(domain: domain, cloudAccountID: cloudAccountID)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    /// Produces a deterministic RFC 9562 version-8 UUID. Version 8 is reserved
    /// for application-defined UUID layouts; the remaining bits come from a
    /// domain-separated SHA-256 digest and the RFC variant bits are preserved.
    static func uuid(domain: String, cloudAccountID: CloudAccountID) -> UUID {
        var bytes = Array(
            digest(domain: domain, cloudAccountID: cloudAccountID).prefix(16)
        )
        precondition(bytes.count == 16)
        bytes[6] = (bytes[6] & 0x0f) | 0x80
        bytes[8] = (bytes[8] & 0x3f) | 0x80

        let hex = bytes.map { String(format: "%02x", $0) }
        let value = [
            hex[0 ... 3].joined(),
            hex[4 ... 5].joined(),
            hex[6 ... 7].joined(),
            hex[8 ... 9].joined(),
            hex[10 ... 15].joined(),
        ].joined(separator: "-")
        guard let uuid = UUID(uuidString: value) else {
            preconditionFailure("A fixed-width hexadecimal UUID must decode")
        }
        return uuid
    }

    private static func digest(
        domain: String,
        cloudAccountID: CloudAccountID
    ) -> SHA256.Digest {
        var hasher = SHA256()
        append(CloudAccountBindingDerivationV1.rootDomain, to: &hasher)
        append(domain, to: &hasher)
        append(cloudAccountID.rawValue, to: &hasher)
        return hasher.finalize()
    }

    private static func append(_ value: String, to hasher: inout SHA256) {
        let data = Data(value.utf8)
        var length = UInt64(data.count).bigEndian
        withUnsafeBytes(of: &length) { raw in
            hasher.update(data: Data(raw))
        }
        hasher.update(data: data)
    }
}

enum EconomyProofAuthority: String, Codable, Equatable, Sendable {
    case durablePrivateCloud
    case localTest
}

/// A short-lived proof that the exact active session is viewing the current
/// durable economy revision. A proof is invalid after a session, revision, or
/// expiry change.
struct AccountScopedEconomyProof: Codable, Equatable, Sendable {
    let session: ActiveAccountSession
    let economyRevision: UInt64
    let validationID: OperationID
    let validatedAt: Date
    let expiresAt: Date
    let authority: EconomyProofAuthority

    init(
        session: ActiveAccountSession,
        economyRevision: UInt64,
        validationID: OperationID,
        validatedAt: Date,
        expiresAt: Date,
        authority: EconomyProofAuthority = .durablePrivateCloud
    ) {
        precondition(expiresAt >= validatedAt, "Economy proof expiry precedes validation")
        self.session = session
        self.economyRevision = economyRevision
        self.validationID = validationID
        self.validatedAt = validatedAt
        self.expiresAt = expiresAt
        self.authority = authority
    }

    func isCurrent(
        for session: ActiveAccountSession,
        economyRevision: UInt64,
        at date: Date
    ) -> Bool {
        authority == .durablePrivateCloud
            && self.session == session
            && self.economyRevision == economyRevision
            && date >= validatedAt.addingTimeInterval(-5)
            && date <= expiresAt
    }
}

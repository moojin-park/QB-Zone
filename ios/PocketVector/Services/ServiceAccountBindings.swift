import CryptoKit
import Foundation

/// A stable, opaque account key supplied by the account coordinator. It must
/// not contain an email address, Game Center alias, or other display identity.
struct ServiceAccountKey: RawRepresentable, Codable, Equatable, Hashable, Sendable {
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

    static func derive(from cloudAccountID: CloudAccountID) -> Self {
        let playerAccountIdentity = PlayerAccountIdentity(
            AccountBindingDigest.hex(
                domain: "player-account-identity-v1",
                cloudAccountID: cloudAccountID
            )
        )
        let durableAccountBinding = DurableAccountBinding(
            accountKey: ServiceAccountKey(
                AccountBindingDigest.hex(
                    domain: "service-account-key-v1",
                    cloudAccountID: cloudAccountID
                )
            ),
            profileID: AccountBindingDigest.uuid(
                domain: "profile-id-v1",
                cloudAccountID: cloudAccountID
            )
        )
        return Self(
            playerAccountIdentity: playerAccountIdentity,
            durableAccountBinding: durableAccountBinding,
            storeAccountBinding: StoreAccountBinding(
                account: durableAccountBinding,
                appAccountToken: AccountBindingDigest.uuid(
                    domain: "store-app-account-token-v1",
                    cloudAccountID: cloudAccountID
                )
            )
        )
    }
}

private enum AccountBindingDigest {
    private static let rootDomain = "pocket-vector-private-cloud-account-binding-v1"

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
        append(rootDomain, to: &hasher)
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

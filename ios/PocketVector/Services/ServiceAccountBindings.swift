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

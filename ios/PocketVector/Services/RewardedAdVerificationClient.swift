import Foundation

private enum RewardedAdVerificationTokenPolicy {
    static let minimumOpaqueTokenBytes = 16
    static let maximumOpaqueTokenBytes = 512
    static let maximumProviderTransactionIDBytes = 256

    static func isValidOpaqueToken(_ value: String) -> Bool {
        isValidToken(
            value,
            minimumBytes: minimumOpaqueTokenBytes,
            maximumBytes: maximumOpaqueTokenBytes
        )
    }

    static func isValidProviderTransactionID(_ value: String) -> Bool {
        isValidToken(
            value,
            minimumBytes: 1,
            maximumBytes: maximumProviderTransactionIDBytes
        )
    }

    private static func isValidToken(
        _ value: String,
        minimumBytes: Int,
        maximumBytes: Int
    ) -> Bool {
        let bytes = Array(value.utf8)
        guard bytes.count >= minimumBytes, bytes.count <= maximumBytes else {
            return false
        }
        return bytes.allSatisfy { byte in
            switch byte {
            case 45, 46, 48 ... 57, 65 ... 90, 95, 97 ... 122, 126:
                true
            default:
                false
            }
        }
    }
}

enum RewardedAdVerificationError: Error, Equatable, Sendable {
    case transportUnavailable
    case preparationMismatch
    case statusMismatch
    case malformedVerificationHandle
    case malformedProviderCustomData
    case malformedProviderTransactionID
    case nonFiniteRewardedAt
    case unsupportedChallengeVersion
    case durableOwnerMismatch
    case profileSessionMismatch
}

/// Opaque status lookup material. Its representation is intentionally limited
/// to a bounded URL-safe token so it can later be persisted without accepting
/// unbounded or structured user data.
struct RewardedAdVerificationHandle: Codable, Equatable, Hashable, Sendable {
    private let storage: String

    init(validating value: String) throws {
        guard RewardedAdVerificationTokenPolicy.isValidOpaqueToken(value) else {
            throw RewardedAdVerificationError.malformedVerificationHandle
        }
        storage = value
    }

    var transportValue: String { storage }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(validating: container.decode(String.self))
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(storage)
    }
}

/// Opaque provider custom-data material paired with the lookup handle. A live
/// SDK bridge may forward `transportValue`, but it cannot interpret or mint a
/// verified reward from this value.
struct RewardedAdProviderCustomData: Codable, Equatable, Hashable, Sendable {
    private let storage: String

    init(validating value: String) throws {
        guard RewardedAdVerificationTokenPolicy.isValidOpaqueToken(value) else {
            throw RewardedAdVerificationError.malformedProviderCustomData
        }
        storage = value
    }

    var transportValue: String { storage }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(validating: container.decode(String.self))
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(storage)
    }
}

/// Versioned, persistable correlation material. This is not verification
/// authority: after relaunch it must be checked with the injected status
/// transport again before a process claim can be minted.
struct RewardedAdVerificationChallengeV1: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let attempt: RewardedAdAttempt
    let verificationHandle: RewardedAdVerificationHandle
    let providerCustomData: RewardedAdProviderCustomData

    enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion
        case attempt
        case verificationHandle
        case providerCustomData
    }

    static var persistedFieldManifest: String {
        CodingKeys.allCases.map(\.rawValue).sorted().joined(separator: ",")
    }

    fileprivate init(
        attempt: RewardedAdAttempt,
        verificationHandle: RewardedAdVerificationHandle,
        providerCustomData: RewardedAdProviderCustomData
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.attempt = attempt
        self.verificationHandle = verificationHandle
        self.providerCustomData = providerCustomData
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(
            Int.self,
            forKey: .schemaVersion
        )
        guard schemaVersion == Self.currentSchemaVersion else {
            throw RewardedAdVerificationError.unsupportedChallengeVersion
        }
        self.schemaVersion = schemaVersion
        attempt = try container.decode(
            RewardedAdAttempt.self,
            forKey: .attempt
        )
        verificationHandle = try container.decode(
            RewardedAdVerificationHandle.self,
            forKey: .verificationHandle
        )
        providerCustomData = try container.decode(
            RewardedAdProviderCustomData.self,
            forKey: .providerCustomData
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(attempt, forKey: .attempt)
        try container.encode(
            verificationHandle,
            forKey: .verificationHandle
        )
        try container.encode(providerCustomData, forKey: .providerCustomData)
    }
}

struct RewardedAdVerificationPreparationRequest: Equatable, Sendable {
    let attempt: RewardedAdAttempt
}

/// Untrusted transport output. Echoing the complete attempt lets the client
/// reject a server or routing response issued for another account/session.
struct RewardedAdVerificationPreparationResponse: Equatable, Sendable {
    let attempt: RewardedAdAttempt
    let verificationHandle: String
    let providerCustomData: String
}

struct RewardedAdVerificationStatusRequest: Equatable, Sendable {
    let verificationHandle: RewardedAdVerificationHandle
}

enum RewardedAdVerificationTerminalRejection: String, Codable, Equatable, Sendable {
    case expired
    case invalidChallenge
    case providerRejected
    case alreadyConsumed
}

/// Untrusted server payload. The transport contract requires
/// `uniqueProviderTransactionID` to be globally unique and replay-stable. The
/// durable economy layer independently detects collisions by that identifier.
struct RewardedAdVerifiedServerResponse: Equatable, Sendable {
    let attempt: RewardedAdAttempt
    let verificationHandle: String
    let providerCustomData: String
    let uniqueProviderTransactionID: String
    let rewardedAt: Date
}

enum RewardedAdVerificationServerStatus: Equatable, Sendable {
    case pending
    case terminalRejected(RewardedAdVerificationTerminalRejection)
    case verified(RewardedAdVerifiedServerResponse)
}

/// A future authenticated transport implements this protocol. This package
/// deliberately supplies no URL, credential, network client, or ad SDK.
protocol RewardedAdVerificationTransport: Sendable {
    func prepareChallenge(
        _ request: RewardedAdVerificationPreparationRequest
    ) async throws -> RewardedAdVerificationPreparationResponse

    func verificationStatus(
        _ request: RewardedAdVerificationStatusRequest
    ) async throws -> RewardedAdVerificationServerStatus
}

private final class RewardedAdVerifiedProcessAuthority: @unchecked Sendable {}

/// Non-Codable process authority created only after exact server correlation.
/// Persist the challenge, never this claim; recovery must query status again.
struct VerifiedRewardedAdClaim: Equatable, Sendable {
    let receipt: VerifiedRewardReceipt
    let challenge: RewardedAdVerificationChallengeV1
    private let processAuthority: RewardedAdVerifiedProcessAuthority

    fileprivate init(
        receipt: VerifiedRewardReceipt,
        challenge: RewardedAdVerificationChallengeV1
    ) {
        self.receipt = receipt
        self.challenge = challenge
        processAuthority = RewardedAdVerifiedProcessAuthority()
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.processAuthority === rhs.processAuthority
            && lhs.receipt == rhs.receipt
            && lhs.challenge == rhs.challenge
    }

    func durableDeliveryRequest(
        session: ProfileSessionToken,
        currentBinding: DurableAccountBinding
    ) throws -> VerifiedRewardedAdDurableDeliveryRequest {
        try VerifiedRewardedAdDurableDeliveryRequest(
            session: session,
            currentBinding: currentBinding,
            verifiedClaim: self
        )
    }
}

enum RewardedAdVerificationResult: Sendable {
    case pending
    case terminalRejected(RewardedAdVerificationTerminalRejection)
    case verified(VerifiedRewardedAdClaim)
}

/// Dormant verification orchestrator. Initialization starts no task and no
/// timer; every server interaction is an explicit caller-owned operation.
actor RewardedAdVerificationClient {
    private let transport: any RewardedAdVerificationTransport

    /// Construction stays sealed until this trusted file gains an
    /// authenticated production transport factory.
    fileprivate init(transport: any RewardedAdVerificationTransport) {
        self.transport = transport
    }

    func prepareChallenge(
        for attempt: RewardedAdAttempt
    ) async throws -> RewardedAdVerificationChallengeV1 {
        let response: RewardedAdVerificationPreparationResponse
        do {
            response = try await transport.prepareChallenge(
                RewardedAdVerificationPreparationRequest(attempt: attempt)
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw RewardedAdVerificationError.transportUnavailable
        }

        guard response.attempt == attempt else {
            throw RewardedAdVerificationError.preparationMismatch
        }
        let handle = try RewardedAdVerificationHandle(
            validating: response.verificationHandle
        )
        let customData = try RewardedAdProviderCustomData(
            validating: response.providerCustomData
        )
        return RewardedAdVerificationChallengeV1(
            attempt: attempt,
            verificationHandle: handle,
            providerCustomData: customData
        )
    }

    func verificationStatus(
        for challenge: RewardedAdVerificationChallengeV1
    ) async throws -> RewardedAdVerificationResult {
        // Codable recovery cannot bypass the token bounds.
        _ = try RewardedAdVerificationHandle(
            validating: challenge.verificationHandle.transportValue
        )
        _ = try RewardedAdProviderCustomData(
            validating: challenge.providerCustomData.transportValue
        )

        let status: RewardedAdVerificationServerStatus
        do {
            status = try await transport.verificationStatus(
                RewardedAdVerificationStatusRequest(
                    verificationHandle: challenge.verificationHandle
                )
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw RewardedAdVerificationError.transportUnavailable
        }

        switch status {
        case .pending:
            return .pending
        case let .terminalRejected(reason):
            return .terminalRejected(reason)
        case let .verified(response):
            return .verified(try verifiedClaim(
                response: response,
                challenge: challenge
            ))
        }
    }

    private func verifiedClaim(
        response: RewardedAdVerifiedServerResponse,
        challenge: RewardedAdVerificationChallengeV1
    ) throws -> VerifiedRewardedAdClaim {
        guard response.attempt == challenge.attempt,
              response.verificationHandle
                == challenge.verificationHandle.transportValue,
              response.providerCustomData
                == challenge.providerCustomData.transportValue else {
            throw RewardedAdVerificationError.statusMismatch
        }
        guard RewardedAdVerificationTokenPolicy.isValidProviderTransactionID(
            response.uniqueProviderTransactionID
        ) else {
            throw RewardedAdVerificationError.malformedProviderTransactionID
        }
        guard response.rewardedAt.timeIntervalSince1970.isFinite else {
            throw RewardedAdVerificationError.nonFiniteRewardedAt
        }

        let receipt = VerifiedRewardReceipt(
            binding: response.attempt.binding,
            offerID: response.attempt.offerID,
            attemptID: response.attempt.attemptID,
            providerTransactionID: AdProviderTransactionID(
                response.uniqueProviderTransactionID
            ),
            rewardedAt: response.rewardedAt
        )
        return VerifiedRewardedAdClaim(
            receipt: receipt,
            challenge: challenge
        )
    }
}

#if DEBUG
extension RewardedAdVerificationClient {
    /// Unit-test-only injection seam. Release builds intentionally expose no
    /// initializer capable of accepting an arbitrary transport conformer.
    init(testingTransport transport: any RewardedAdVerificationTransport) {
        self.init(transport: transport)
    }
}
#endif

import CryptoKit
import Foundation

struct ProfileHydrationDigest: RawRepresentable, Codable, Equatable, Hashable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        precondition(
            Self.isValid(rawValue),
            "ProfileHydrationDigest must be a lowercase SHA-256 digest"
        )
        self.rawValue = rawValue
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard Self.isValid(value) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid profile-hydration digest"
            )
        }
        rawValue = value
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    static func envelopeBytes(_ data: Data) -> Self {
        var builder = ProfileHydrationDigestBuilder()
        builder.append("pocket-vector-profile-envelope-bytes-v1")
        builder.append(data)
        return Self(rawValue: builder.finalizeHex())
    }

    private static func isValid(_ value: String) -> Bool {
        value.utf8.count == 64
            && value.utf8.allSatisfy {
                ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102)
            }
    }
}

/// A stable identity for a complete checkpoint. This deliberately does not
/// reuse the checkpoint store's private disk envelope or depend on JSON map
/// ordering. Every checkpoint field is length-prefixed and dictionary keys
/// are ordered by their UTF-8 bytes before hashing.
struct ProfileHydrationCheckpointIdentityV1: Codable, Equatable, Sendable {
    let accountID: CloudAccountID
    let configurationScopeFingerprint: CloudReplicaScopeFingerprint
    let replicaEpoch: UUID
    let generation: UInt64
    let finalCursor: Data
    let checkpointDigest: ProfileHydrationDigest

    init(checkpoint: CloudReplicaCheckpointV1) {
        accountID = checkpoint.accountID
        configurationScopeFingerprint = checkpoint.configurationScopeFingerprint
        replicaEpoch = checkpoint.replicaEpoch
        generation = checkpoint.generation
        finalCursor = checkpoint.finalCursor.rawValue
        checkpointDigest = Self.digest(checkpoint)
    }

    func matches(_ checkpoint: CloudReplicaCheckpointV1) -> Bool {
        self == Self(checkpoint: checkpoint)
    }

    private static func digest(
        _ checkpoint: CloudReplicaCheckpointV1
    ) -> ProfileHydrationDigest {
        var builder = ProfileHydrationDigestBuilder()
        builder.append("pocket-vector-profile-hydration-checkpoint-identity-v1")
        builder.append(UInt64(CloudReplicaCheckpointV1.formatVersion))
        builder.append(checkpoint.accountID.rawValue)
        builder.append(checkpoint.configurationScopeFingerprint.rawValue)
        builder.append(checkpoint.replicaEpoch)
        builder.append(checkpoint.generation)
        builder.append(checkpoint.finalCursor.rawValue)

        let logicalRecordIDs = checkpoint.recordsByLogicalID.keys.sorted(by: utf8Less)
        builder.append(UInt64(logicalRecordIDs.count))
        for logicalRecordID in logicalRecordIDs {
            builder.append(logicalRecordID.rawValue)
            guard let record = checkpoint.recordsByLogicalID[logicalRecordID] else {
                preconditionFailure("A checkpoint dictionary key disappeared while hashing")
            }
            builder.append(record.id.rawValue)
            builder.append(record.recordType)
            builder.append(record.changeTag.rawValue)
            let fieldNames = record.fields.keys.sorted(by: utf8Less)
            builder.append(UInt64(fieldNames.count))
            for fieldName in fieldNames {
                builder.append(fieldName)
                builder.append(record.fields[fieldName] ?? Data())
            }
        }

        let providerLogicalIDs = checkpoint.providerLocatorByLogicalID.keys.sorted(by: utf8Less)
        builder.append(UInt64(providerLogicalIDs.count))
        for logicalID in providerLogicalIDs {
            builder.append(logicalID.rawValue)
            builder.append(
                checkpoint.providerLocatorByLogicalID[logicalID]?.rawValue ?? ""
            )
        }

        let providerLocators = checkpoint.logicalIDByProviderLocator.keys.sorted(by: utf8Less)
        builder.append(UInt64(providerLocators.count))
        for locator in providerLocators {
            builder.append(locator.rawValue)
            builder.append(
                checkpoint.logicalIDByProviderLocator[locator]?.rawValue ?? ""
            )
        }

        let tombstoneLocators = checkpoint.tombstonesByProviderLocator.keys.sorted(by: utf8Less)
        builder.append(UInt64(tombstoneLocators.count))
        for locator in tombstoneLocators {
            builder.append(locator.rawValue)
            guard let tombstone = checkpoint.tombstonesByProviderLocator[locator] else {
                preconditionFailure("A checkpoint tombstone disappeared while hashing")
            }
            builder.append(tombstone.locator.rawValue)
            builder.append(tombstone.logicalRecordID != nil)
            if let logicalRecordID = tombstone.logicalRecordID {
                builder.append(logicalRecordID.rawValue)
            }
            builder.append(tombstone.recordType)
        }
        return ProfileHydrationDigest(rawValue: builder.finalizeHex())
    }

    private static func utf8Less<T: RawRepresentable>(
        _ lhs: T,
        _ rhs: T
    ) -> Bool where T.RawValue == String {
        Data(lhs.rawValue.utf8).lexicographicallyPrecedes(Data(rhs.rawValue.utf8))
    }

    private static func utf8Less(_ lhs: String, _ rhs: String) -> Bool {
        Data(lhs.utf8).lexicographicallyPrecedes(Data(rhs.utf8))
    }
}

/// Classifies one independently observed checkpoint against the immutable
/// transition bound into a hydration journal. An absent observation is the
/// exact predecessor only for a generation-one (genesis) transition.
enum ProfileHydrationCheckpointRelationshipV1: Equatable, Sendable {
    case target
    case predecessor
    case unexpected
}

struct ProfileHydrationSourceStateV1: Codable, Equatable, Sendable {
    let accountIdentity: PlayerAccountIdentity
    let sessionNonce: UUID
    let profileID: UUID
    let playerRevision: UInt64
    let economyRevision: UInt64
}

struct ProfileHydrationCloudTargetV1: Codable, Equatable, Sendable {
    let cloudAccountID: CloudAccountID
    let playerAccountIdentity: PlayerAccountIdentity
    let accountKey: ServiceAccountKey
    let profileID: UUID
    let configurationScopeFingerprint: CloudReplicaScopeFingerprint
    let replicaEpoch: UUID

    init(
        cloudAccountID: CloudAccountID,
        configurationScopeFingerprint: CloudReplicaScopeFingerprint,
        replicaEpoch: UUID
    ) {
        let bindings = CloudAccountDerivedBindings.derive(from: cloudAccountID)
        self.cloudAccountID = cloudAccountID
        playerAccountIdentity = bindings.playerAccountIdentity
        accountKey = bindings.durableAccountBinding.accountKey
        profileID = bindings.durableAccountBinding.profileID
        self.configurationScopeFingerprint = configurationScopeFingerprint
        self.replicaEpoch = replicaEpoch
    }
}

struct ProfileHydrationExpectedBinding: Equatable, Sendable {
    let cloudAccountID: CloudAccountID
    let playerAccountIdentity: PlayerAccountIdentity
    let accountKey: ServiceAccountKey
    let profileID: UUID
    let configurationScopeFingerprint: CloudReplicaScopeFingerprint
    let replicaEpoch: UUID

    init(
        cloudAccountID: CloudAccountID,
        configurationScopeFingerprint: CloudReplicaScopeFingerprint,
        replicaEpoch: UUID
    ) {
        let bindings = CloudAccountDerivedBindings.derive(from: cloudAccountID)
        self.cloudAccountID = cloudAccountID
        playerAccountIdentity = bindings.playerAccountIdentity
        accountKey = bindings.durableAccountBinding.accountKey
        profileID = bindings.durableAccountBinding.profileID
        self.configurationScopeFingerprint = configurationScopeFingerprint
        self.replicaEpoch = replicaEpoch
    }

    init(
        cloudAccountID: CloudAccountID,
        playerAccountIdentity: PlayerAccountIdentity,
        accountKey: ServiceAccountKey,
        profileID: UUID,
        configurationScopeFingerprint: CloudReplicaScopeFingerprint,
        replicaEpoch: UUID
    ) {
        self.cloudAccountID = cloudAccountID
        self.playerAccountIdentity = playerAccountIdentity
        self.accountKey = accountKey
        self.profileID = profileID
        self.configurationScopeFingerprint = configurationScopeFingerprint
        self.replicaEpoch = replicaEpoch
    }

    fileprivate func matches(_ target: ProfileHydrationCloudTargetV1) -> Bool {
        cloudAccountID == target.cloudAccountID
            && playerAccountIdentity == target.playerAccountIdentity
            && accountKey == target.accountKey
            && profileID == target.profileID
            && configurationScopeFingerprint
                == target.configurationScopeFingerprint
            && replicaEpoch == target.replicaEpoch
    }
}

struct ProfileHydrationLimits: Equatable, Sendable {
    static let production = ProfileHydrationLimits(
        maximumEncodedJournalBytes: 224 * 1_024 * 1_024,
        maximumProfileEnvelopeBytes: 8 * 1_024 * 1_024,
        maximumEncodedCheckpointBytes: 192 * 1_024 * 1_024,
        maximumIdentifierBytes: 1_024,
        maximumProfileCollectionEntries: 200_000,
        maximumQuarantineFiles: 4,
        maximumQuarantineBytes: 448 * 1_024 * 1_024
    )

    let maximumEncodedJournalBytes: Int
    let maximumProfileEnvelopeBytes: Int
    let maximumEncodedCheckpointBytes: Int
    let maximumIdentifierBytes: Int
    let maximumProfileCollectionEntries: Int
    let maximumQuarantineFiles: Int
    let maximumQuarantineBytes: Int

    init(
        maximumEncodedJournalBytes: Int,
        maximumProfileEnvelopeBytes: Int,
        maximumEncodedCheckpointBytes: Int,
        maximumIdentifierBytes: Int,
        maximumProfileCollectionEntries: Int,
        maximumQuarantineFiles: Int,
        maximumQuarantineBytes: Int
    ) {
        precondition(maximumEncodedJournalBytes > 0)
        precondition(maximumProfileEnvelopeBytes > 0)
        precondition(maximumEncodedCheckpointBytes > 0)
        precondition(maximumIdentifierBytes > 0)
        precondition(maximumProfileCollectionEntries > 0)
        precondition((1 ... 64).contains(maximumQuarantineFiles))
        precondition(maximumQuarantineBytes > 0)
        self.maximumEncodedJournalBytes = maximumEncodedJournalBytes
        self.maximumProfileEnvelopeBytes = maximumProfileEnvelopeBytes
        self.maximumEncodedCheckpointBytes = maximumEncodedCheckpointBytes
        self.maximumIdentifierBytes = maximumIdentifierBytes
        self.maximumProfileCollectionEntries = maximumProfileCollectionEntries
        self.maximumQuarantineFiles = maximumQuarantineFiles
        self.maximumQuarantineBytes = maximumQuarantineBytes
    }
}

enum ProfileHydrationJournalValidationError: Error, Equatable, Sendable {
    case unsupportedFormatVersion
    case unsupportedMergePolicyVersion(Int)
    case invalidTransactionID
    case invalidCreatedAt
    case identifierLimitExceeded
    case sourceEnvelopeLimitExceeded
    case candidateEnvelopeLimitExceeded
    case checkpointLimitExceeded
    case journalLimitExceeded
    case sourceEnvelopeDigestMismatch
    case candidateEnvelopeDigestMismatch
    case invalidSourceEnvelope
    case invalidCandidateEnvelope
    case noncanonicalCandidateEnvelope
    case sourceProfileBindingMismatch
    case candidateProfileBindingMismatch
    case noMaterialChange
    case revisionOverflow
    case candidatePlayerRevisionMismatch
    case candidateEconomyRevisionMismatch
    case profileCollectionLimitExceeded
    case targetAccountBindingMismatch
    case sourceTargetBindingMismatch
    case invalidTargetCheckpoint
    case targetCheckpointBindingMismatch
    case targetCheckpointIdentityMismatch
    case invalidPredecessorIdentity
    case predecessorBindingMismatch
    case predecessorGenerationMismatch
    case predecessorCursorDidNotAdvance
}

/// Immutable intent for one material profile hydration. A no-op merge never
/// creates this journal: both local revisions advance exactly once only when
/// the candidate bytes are different from the bound source bytes.
struct ProfileHydrationJournalV1: Codable, Equatable, Sendable {
    static let formatVersion = 1
    static let mergePolicyVersion = 1

    let transactionID: UUID
    let createdAtMillisecondsSince1970: Int64
    let mergePolicyVersion: Int
    let source: ProfileHydrationSourceStateV1
    let sourceProfileEnvelope: Data
    let sourceProfileEnvelopeDigest: ProfileHydrationDigest
    let candidatePlayerRevision: UInt64
    let candidateEconomyRevision: UInt64
    let candidateProfileEnvelope: Data
    let candidateProfileEnvelopeDigest: ProfileHydrationDigest
    let target: ProfileHydrationCloudTargetV1
    let predecessorCheckpointIdentity: ProfileHydrationCheckpointIdentityV1?
    let targetCheckpoint: CloudReplicaCheckpointV1
    let targetCheckpointIdentity: ProfileHydrationCheckpointIdentityV1

    var createdAt: Date {
        Date(
            timeIntervalSince1970:
                Double(createdAtMillisecondsSince1970) / 1_000
        )
    }

    func checkpointRelationship(
        to observation: CloudReplicaCheckpointObservationV1
    ) -> ProfileHydrationCheckpointRelationshipV1 {
        guard observation.accountID == target.cloudAccountID,
              observation.configurationScopeFingerprint
                == target.configurationScopeFingerprint,
              observation.replicaEpoch == target.replicaEpoch else {
            return .unexpected
        }

        switch observation.state {
        case .absent:
            return predecessorCheckpointIdentity == nil
                ? .predecessor
                : .unexpected

        case let .checkpoint(identity):
            if identity == targetCheckpointIdentity {
                return .target
            }
            if let predecessorCheckpointIdentity,
               identity == predecessorCheckpointIdentity {
                return .predecessor
            }
            return .unexpected
        }
    }

    private init(
        transactionID: UUID,
        createdAtMillisecondsSince1970: Int64,
        mergePolicyVersion: Int,
        source: ProfileHydrationSourceStateV1,
        sourceProfileEnvelope: Data,
        sourceProfileEnvelopeDigest: ProfileHydrationDigest,
        candidatePlayerRevision: UInt64,
        candidateEconomyRevision: UInt64,
        candidateProfileEnvelope: Data,
        candidateProfileEnvelopeDigest: ProfileHydrationDigest,
        target: ProfileHydrationCloudTargetV1,
        predecessorCheckpointIdentity: ProfileHydrationCheckpointIdentityV1?,
        targetCheckpoint: CloudReplicaCheckpointV1,
        targetCheckpointIdentity: ProfileHydrationCheckpointIdentityV1
    ) {
        self.transactionID = transactionID
        self.createdAtMillisecondsSince1970 = createdAtMillisecondsSince1970
        self.mergePolicyVersion = mergePolicyVersion
        self.source = source
        self.sourceProfileEnvelope = sourceProfileEnvelope
        self.sourceProfileEnvelopeDigest = sourceProfileEnvelopeDigest
        self.candidatePlayerRevision = candidatePlayerRevision
        self.candidateEconomyRevision = candidateEconomyRevision
        self.candidateProfileEnvelope = candidateProfileEnvelope
        self.candidateProfileEnvelopeDigest = candidateProfileEnvelopeDigest
        self.target = target
        self.predecessorCheckpointIdentity = predecessorCheckpointIdentity
        self.targetCheckpoint = targetCheckpoint
        self.targetCheckpointIdentity = targetCheckpointIdentity
    }

    static func make(
        transactionID: UUID = UUID(),
        createdAt: Date,
        sourceSession: ProfileSessionToken,
        sourcePlayerRevision: UInt64,
        sourceEconomyRevision: UInt64,
        sourceProfileEnvelope: Data,
        candidateProfileEnvelope: Data,
        cloudAccountID: CloudAccountID,
        configurationScopeFingerprint: CloudReplicaScopeFingerprint,
        replicaEpoch: UUID,
        predecessorCheckpointIdentity: ProfileHydrationCheckpointIdentityV1?,
        targetCheckpoint: CloudReplicaCheckpointV1,
        migrator: any PlayerProfileMigrating = PlayerProfileMigrator(),
        catalog: LaunchCatalog = .approved,
        limits: ProfileHydrationLimits = .production
    ) throws -> Self {
        guard createdAt.timeIntervalSince1970.isFinite,
              createdAt.timeIntervalSince1970 * 1_000
                >= Double(Int64.min),
              createdAt.timeIntervalSince1970 * 1_000
                <= Double(Int64.max)
        else {
            throw ProfileHydrationJournalValidationError.invalidCreatedAt
        }
        guard let createdAtMilliseconds = Int64(
            exactly: (createdAt.timeIntervalSince1970 * 1_000).rounded()
        ) else {
            throw ProfileHydrationJournalValidationError.invalidCreatedAt
        }
        let candidateDocument: LocalPlayerDocumentV1
        do {
            candidateDocument = try migrator.decode(candidateProfileEnvelope)
        } catch {
            throw ProfileHydrationJournalValidationError.invalidCandidateEnvelope
        }
        let target = ProfileHydrationCloudTargetV1(
            cloudAccountID: cloudAccountID,
            configurationScopeFingerprint: configurationScopeFingerprint,
            replicaEpoch: replicaEpoch
        )
        let journal = Self(
            transactionID: transactionID,
            createdAtMillisecondsSince1970: createdAtMilliseconds,
            mergePolicyVersion: Self.mergePolicyVersion,
            source: ProfileHydrationSourceStateV1(
                accountIdentity: sourceSession.accountIdentity,
                sessionNonce: sourceSession.nonce,
                profileID: sourceSession.profileID,
                playerRevision: sourcePlayerRevision,
                economyRevision: sourceEconomyRevision
            ),
            sourceProfileEnvelope: sourceProfileEnvelope,
            sourceProfileEnvelopeDigest: .envelopeBytes(sourceProfileEnvelope),
            candidatePlayerRevision: candidateDocument.player.revision,
            candidateEconomyRevision: candidateDocument.economyRevision,
            candidateProfileEnvelope: candidateProfileEnvelope,
            candidateProfileEnvelopeDigest: .envelopeBytes(candidateProfileEnvelope),
            target: target,
            predecessorCheckpointIdentity: predecessorCheckpointIdentity,
            targetCheckpoint: targetCheckpoint,
            targetCheckpointIdentity: ProfileHydrationCheckpointIdentityV1(
                checkpoint: targetCheckpoint
            )
        )
        try journal.validate(migrator: migrator, catalog: catalog, limits: limits)
        return journal
    }

    func validate(
        migrator: any PlayerProfileMigrating = PlayerProfileMigrator(),
        catalog: LaunchCatalog = .approved,
        limits: ProfileHydrationLimits = .production
    ) throws {
        guard transactionID != UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)) else {
            throw ProfileHydrationJournalValidationError.invalidTransactionID
        }
        guard createdAt.timeIntervalSince1970.isFinite else {
            throw ProfileHydrationJournalValidationError.invalidCreatedAt
        }
        guard mergePolicyVersion == Self.mergePolicyVersion else {
            throw ProfileHydrationJournalValidationError.unsupportedMergePolicyVersion(
                mergePolicyVersion
            )
        }
        guard Self.identifiersAreBounded(
            source: source,
            target: target,
            limits: limits
        ) else {
            throw ProfileHydrationJournalValidationError.identifierLimitExceeded
        }
        guard sourceProfileEnvelope.count <= limits.maximumProfileEnvelopeBytes else {
            throw ProfileHydrationJournalValidationError.sourceEnvelopeLimitExceeded
        }
        guard candidateProfileEnvelope.count <= limits.maximumProfileEnvelopeBytes else {
            throw ProfileHydrationJournalValidationError.candidateEnvelopeLimitExceeded
        }
        guard sourceProfileEnvelopeDigest == .envelopeBytes(sourceProfileEnvelope) else {
            throw ProfileHydrationJournalValidationError.sourceEnvelopeDigestMismatch
        }
        guard candidateProfileEnvelopeDigest == .envelopeBytes(candidateProfileEnvelope) else {
            throw ProfileHydrationJournalValidationError.candidateEnvelopeDigestMismatch
        }
        guard sourceProfileEnvelope != candidateProfileEnvelope else {
            throw ProfileHydrationJournalValidationError.noMaterialChange
        }

        let sourceDocument: LocalPlayerDocumentV1
        do {
            sourceDocument = try migrator.decode(sourceProfileEnvelope)
            try PlayerProfileValidator.validate(sourceDocument, catalog: catalog)
        } catch {
            throw ProfileHydrationJournalValidationError.invalidSourceEnvelope
        }
        let candidateDocument: LocalPlayerDocumentV1
        do {
            candidateDocument = try migrator.decode(candidateProfileEnvelope)
            try PlayerProfileValidator.validate(candidateDocument, catalog: catalog)
        } catch {
            throw ProfileHydrationJournalValidationError.invalidCandidateEnvelope
        }
        try Self.validateProfileCollectionBounds(sourceDocument, limits: limits)
        try Self.validateProfileCollectionBounds(candidateDocument, limits: limits)
        guard sourceDocument.accountIdentity == source.accountIdentity,
              sourceDocument.player.profileID == source.profileID,
              sourceDocument.player.revision == source.playerRevision,
              sourceDocument.economyRevision == source.economyRevision else {
            throw ProfileHydrationJournalValidationError.sourceProfileBindingMismatch
        }
        guard candidateDocument.accountIdentity == target.playerAccountIdentity,
              candidateDocument.player.profileID == target.profileID,
              candidateDocument.player.revision == candidatePlayerRevision,
              candidateDocument.economyRevision == candidateEconomyRevision else {
            throw ProfileHydrationJournalValidationError.candidateProfileBindingMismatch
        }
        let (expectedPlayerRevision, playerOverflow) = source.playerRevision
            .addingReportingOverflow(1)
        let (expectedEconomyRevision, economyOverflow) = source.economyRevision
            .addingReportingOverflow(1)
        guard !playerOverflow, !economyOverflow else {
            throw ProfileHydrationJournalValidationError.revisionOverflow
        }
        guard candidatePlayerRevision == expectedPlayerRevision else {
            throw ProfileHydrationJournalValidationError.candidatePlayerRevisionMismatch
        }
        guard candidateEconomyRevision == expectedEconomyRevision else {
            throw ProfileHydrationJournalValidationError.candidateEconomyRevisionMismatch
        }
        try Self.validateCandidateEnvelopeIsCanonical(
            candidateProfileEnvelope,
            document: candidateDocument,
            migrator: migrator
        )

        let derived = CloudAccountDerivedBindings.derive(from: target.cloudAccountID)
        guard target.playerAccountIdentity == derived.playerAccountIdentity,
              target.accountKey == derived.durableAccountBinding.accountKey,
              target.profileID == derived.durableAccountBinding.profileID else {
            throw ProfileHydrationJournalValidationError.targetAccountBindingMismatch
        }
        // Ordinary hydration is an in-place merge for one cloud-derived
        // player. Cross-account/profile migration requires a separate explicit
        // workflow and cannot be represented by this journal.
        guard source.accountIdentity == target.playerAccountIdentity,
              source.profileID == target.profileID else {
            throw ProfileHydrationJournalValidationError
                .sourceTargetBindingMismatch
        }

        do {
            try targetCheckpoint.validate()
        } catch {
            throw ProfileHydrationJournalValidationError.invalidTargetCheckpoint
        }
        guard targetCheckpoint.accountID == target.cloudAccountID,
              targetCheckpoint.configurationScopeFingerprint
                == target.configurationScopeFingerprint,
              targetCheckpoint.replicaEpoch == target.replicaEpoch else {
            throw ProfileHydrationJournalValidationError.targetCheckpointBindingMismatch
        }
        guard targetCheckpointIdentity.matches(targetCheckpoint) else {
            throw ProfileHydrationJournalValidationError.targetCheckpointIdentityMismatch
        }
        try Self.validateCheckpointIdentifierBounds(
            targetCheckpoint,
            limits: limits
        )
        let encodedCheckpoint: Data
        do {
            encodedCheckpoint = try ProfileHydrationCanonicalCodec.encode(targetCheckpoint)
        } catch {
            throw ProfileHydrationJournalValidationError.invalidTargetCheckpoint
        }
        guard encodedCheckpoint.count <= limits.maximumEncodedCheckpointBytes else {
            throw ProfileHydrationJournalValidationError.checkpointLimitExceeded
        }

        if let predecessorCheckpointIdentity {
            guard predecessorCheckpointIdentity.generation > 0,
                  !predecessorCheckpointIdentity.finalCursor.isEmpty else {
                throw ProfileHydrationJournalValidationError.invalidPredecessorIdentity
            }
            guard predecessorCheckpointIdentity.accountID == target.cloudAccountID,
                  predecessorCheckpointIdentity.configurationScopeFingerprint
                    == target.configurationScopeFingerprint,
                  predecessorCheckpointIdentity.replicaEpoch == target.replicaEpoch else {
                throw ProfileHydrationJournalValidationError.predecessorBindingMismatch
            }
            let (expectedGeneration, overflow) = predecessorCheckpointIdentity.generation
                .addingReportingOverflow(1)
            guard !overflow, targetCheckpoint.generation == expectedGeneration else {
                throw ProfileHydrationJournalValidationError.predecessorGenerationMismatch
            }
            guard predecessorCheckpointIdentity.finalCursor
                != targetCheckpoint.finalCursor.rawValue else {
                throw ProfileHydrationJournalValidationError.predecessorCursorDidNotAdvance
            }
        } else if targetCheckpoint.generation != 1 {
            throw ProfileHydrationJournalValidationError.predecessorGenerationMismatch
        }

        let encodedJournal: Data
        do {
            encodedJournal = try ProfileHydrationCanonicalCodec.encode(self)
        } catch {
            throw ProfileHydrationJournalValidationError.journalLimitExceeded
        }
        guard encodedJournal.count <= limits.maximumEncodedJournalBytes else {
            throw ProfileHydrationJournalValidationError.journalLimitExceeded
        }
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion
        case transactionID
        case createdAtMillisecondsSince1970
        case mergePolicyVersion
        case source
        case sourceProfileEnvelope
        case sourceProfileEnvelopeDigest
        case candidatePlayerRevision
        case candidateEconomyRevision
        case candidateProfileEnvelope
        case candidateProfileEnvelopeDigest
        case target
        case predecessorCheckpointIdentity
        case targetCheckpoint
        case targetCheckpointIdentity
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(Int.self, forKey: .formatVersion) == Self.formatVersion else {
            throw ProfileHydrationJournalValidationError.unsupportedFormatVersion
        }
        transactionID = try container.decode(UUID.self, forKey: .transactionID)
        createdAtMillisecondsSince1970 = try container.decode(
            Int64.self,
            forKey: .createdAtMillisecondsSince1970
        )
        mergePolicyVersion = try container.decode(Int.self, forKey: .mergePolicyVersion)
        source = try container.decode(ProfileHydrationSourceStateV1.self, forKey: .source)
        sourceProfileEnvelope = try container.decode(Data.self, forKey: .sourceProfileEnvelope)
        sourceProfileEnvelopeDigest = try container.decode(
            ProfileHydrationDigest.self,
            forKey: .sourceProfileEnvelopeDigest
        )
        candidatePlayerRevision = try container.decode(
            UInt64.self,
            forKey: .candidatePlayerRevision
        )
        candidateEconomyRevision = try container.decode(
            UInt64.self,
            forKey: .candidateEconomyRevision
        )
        candidateProfileEnvelope = try container.decode(
            Data.self,
            forKey: .candidateProfileEnvelope
        )
        candidateProfileEnvelopeDigest = try container.decode(
            ProfileHydrationDigest.self,
            forKey: .candidateProfileEnvelopeDigest
        )
        target = try container.decode(ProfileHydrationCloudTargetV1.self, forKey: .target)
        predecessorCheckpointIdentity = try container.decodeIfPresent(
            ProfileHydrationCheckpointIdentityV1.self,
            forKey: .predecessorCheckpointIdentity
        )
        targetCheckpoint = try container.decode(
            CloudReplicaCheckpointV1.self,
            forKey: .targetCheckpoint
        )
        targetCheckpointIdentity = try container.decode(
            ProfileHydrationCheckpointIdentityV1.self,
            forKey: .targetCheckpointIdentity
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.formatVersion, forKey: .formatVersion)
        try container.encode(transactionID, forKey: .transactionID)
        try container.encode(
            createdAtMillisecondsSince1970,
            forKey: .createdAtMillisecondsSince1970
        )
        try container.encode(mergePolicyVersion, forKey: .mergePolicyVersion)
        try container.encode(source, forKey: .source)
        try container.encode(sourceProfileEnvelope, forKey: .sourceProfileEnvelope)
        try container.encode(
            sourceProfileEnvelopeDigest,
            forKey: .sourceProfileEnvelopeDigest
        )
        try container.encode(candidatePlayerRevision, forKey: .candidatePlayerRevision)
        try container.encode(candidateEconomyRevision, forKey: .candidateEconomyRevision)
        try container.encode(candidateProfileEnvelope, forKey: .candidateProfileEnvelope)
        try container.encode(
            candidateProfileEnvelopeDigest,
            forKey: .candidateProfileEnvelopeDigest
        )
        try container.encode(target, forKey: .target)
        try container.encodeIfPresent(
            predecessorCheckpointIdentity,
            forKey: .predecessorCheckpointIdentity
        )
        try container.encode(targetCheckpoint, forKey: .targetCheckpoint)
        try container.encode(
            targetCheckpointIdentity,
            forKey: .targetCheckpointIdentity
        )
    }

    private static func validateCandidateEnvelopeIsCanonical(
        _ data: Data,
        document: LocalPlayerDocumentV1,
        migrator: any PlayerProfileMigrating
    ) throws {
        struct EnvelopeHeader: Decodable {
            let format: String
            let savedAt: Date
        }
        let header: EnvelopeHeader
        do {
            header = try ProfileHydrationCanonicalCodec.decode(
                EnvelopeHeader.self,
                from: data
            )
        } catch {
            throw ProfileHydrationJournalValidationError.invalidCandidateEnvelope
        }
        guard header.format == PlayerProfileEnvelopeV1.formatIdentifier,
              header.savedAt.timeIntervalSince1970.isFinite else {
            throw ProfileHydrationJournalValidationError.invalidCandidateEnvelope
        }
        let canonical: Data
        do {
            canonical = try migrator.encode(document, savedAt: header.savedAt)
        } catch {
            throw ProfileHydrationJournalValidationError.invalidCandidateEnvelope
        }
        if canonical == data { return }

        // A journal admitted before the launch-achievement transition binds
        // immutable candidate bytes and their digest. Recover that exact V4
        // identity without rewriting the journal, while still requiring the
        // raw document to transition to the already-validated current one.
        do {
            let predecessor = try migrator
                .decodeArtifactPreservingLaunchAchievementCatalog(data)
            guard predecessor.sourceSchemaVersion
                    == PlayerProfileEnvelopeV4.schemaVersion,
                  try LaunchAchievementPersistenceTransitionV1ToV2.apply(
                    to: predecessor.document
                  ) == document,
                  try migrator.canonicalArtifact(
                    for: predecessor.document,
                    savedAt: predecessor.savedAt
                  ).exactBytes == data else {
                throw ProfileHydrationJournalValidationError
                    .noncanonicalCandidateEnvelope
            }
        } catch let error as ProfileHydrationJournalValidationError {
            throw error
        } catch {
            throw ProfileHydrationJournalValidationError
                .noncanonicalCandidateEnvelope
        }
    }

    private static func identifiersAreBounded(
        source: ProfileHydrationSourceStateV1,
        target: ProfileHydrationCloudTargetV1,
        limits: ProfileHydrationLimits
    ) -> Bool {
        let identifiers = [
            source.accountIdentity.rawValue,
            target.cloudAccountID.rawValue,
            target.playerAccountIdentity.rawValue,
            target.accountKey.rawValue,
            target.configurationScopeFingerprint.rawValue,
        ]
        return identifiers.allSatisfy { identifier in
            let bytes = identifier.utf8
            return !bytes.isEmpty
                && bytes.count <= limits.maximumIdentifierBytes
                && !bytes.contains(where: { $0 < 0x20 || $0 == 0x7f })
        }
    }

    private static func validateProfileCollectionBounds(
        _ document: LocalPlayerDocumentV1,
        limits: ProfileHydrationLimits
    ) throws {
        var counts = [
            document.player.completedRuns.count,
            document.player.ledger.count,
            document.player.achievementProgress.count,
            document.player.pendingGameCenter.pendingByPlayerID.count,
            document.player.pendingGameCenter.unboundPending
                .pendingAchievementPercents.count,
            document.pendingLedgerEntryIDs.count,
            document.settlementReceipts.count,
            document.rewardedRunObservations?.count ?? 0,
            document.player.inventory.ownedTeamIDs.count,
            document.player.inventory.ownedJerseyIDs.count,
            document.player.inventory.ownedFootballIDs.count,
            document.player.selection.value.selectedJerseyByTeam.count,
        ]
        for (playerID, pending) in document.player.pendingGameCenter.pendingByPlayerID {
            let bytes = playerID.rawValue.utf8
            guard !bytes.isEmpty,
                  bytes.count <= limits.maximumIdentifierBytes,
                  !bytes.contains(where: { $0 < 0x20 || $0 == 0x7f }) else {
                throw ProfileHydrationJournalValidationError.identifierLimitExceeded
            }
            counts.append(pending.pendingAchievementPercents.count)
        }
        var total = 0
        for count in counts {
            let (next, overflow) = total.addingReportingOverflow(count)
            guard !overflow, next <= limits.maximumProfileCollectionEntries else {
                throw ProfileHydrationJournalValidationError.profileCollectionLimitExceeded
            }
            total = next
        }
    }

    private static func validateCheckpointIdentifierBounds(
        _ checkpoint: CloudReplicaCheckpointV1,
        limits: ProfileHydrationLimits
    ) throws {
        func isBounded(_ value: String) -> Bool {
            !value.utf8.isEmpty
                && value.utf8.count <= limits.maximumIdentifierBytes
                && !value.utf8.contains(where: { $0 < 0x20 || $0 == 0x7f })
        }
        guard isBounded(checkpoint.accountID.rawValue) else {
            throw ProfileHydrationJournalValidationError.identifierLimitExceeded
        }
        for (logicalID, record) in checkpoint.recordsByLogicalID {
            guard isBounded(logicalID.rawValue),
                  isBounded(record.id.rawValue),
                  isBounded(record.recordType),
                  isBounded(record.changeTag.rawValue),
                  record.fields.keys.allSatisfy(isBounded) else {
                throw ProfileHydrationJournalValidationError.identifierLimitExceeded
            }
        }
        for (logicalID, locator) in checkpoint.providerLocatorByLogicalID {
            guard isBounded(logicalID.rawValue), isBounded(locator.rawValue) else {
                throw ProfileHydrationJournalValidationError.identifierLimitExceeded
            }
        }
        for (locator, logicalID) in checkpoint.logicalIDByProviderLocator {
            guard isBounded(locator.rawValue), isBounded(logicalID.rawValue) else {
                throw ProfileHydrationJournalValidationError.identifierLimitExceeded
            }
        }
        for (locator, tombstone) in checkpoint.tombstonesByProviderLocator {
            guard isBounded(locator.rawValue),
                  isBounded(tombstone.locator.rawValue),
                  isBounded(tombstone.recordType),
                  tombstone.logicalRecordID.map({ isBounded($0.rawValue) }) ?? true else {
                throw ProfileHydrationJournalValidationError.identifierLimitExceeded
            }
        }
    }
}

enum ProfileHydrationCanonicalCodec {
    /// Swift Codable represents dictionaries whose keys are neither `String`
    /// nor `Int` as alternating key/value arrays. JSON `sortedKeys` does not
    /// order those array elements, so the checkpoint maps must be normalized
    /// explicitly before journal bytes can be treated as immutable authority.
    private static let checkpointDictionaryArrayKeys: Set<String> = [
        "recordsByLogicalID",
        "providerLocatorByLogicalID",
        "logicalIDByProviderLocator",
        "tombstonesByProviderLocator",
    ]

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let encoded = try encoder.encode(value)
        let object = try JSONSerialization.jsonObject(with: encoded)
        let normalized = try normalize(object, key: nil)
        return try JSONSerialization.data(
            withJSONObject: normalized,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(type, from: data)
    }

    private static func normalize(_ value: Any, key: String?) throws -> Any {
        if let dictionary = value as? [String: Any] {
            var normalized: [String: Any] = [:]
            for (childKey, childValue) in dictionary {
                normalized[childKey] = try normalize(
                    childValue,
                    key: childKey
                )
            }
            return normalized
        }

        if let array = value as? [Any] {
            if let key, checkpointDictionaryArrayKeys.contains(key) {
                guard array.count.isMultiple(of: 2) else {
                    throw EncodingError.invalidValue(
                        array,
                        EncodingError.Context(
                            codingPath: [],
                            debugDescription:
                                "Checkpoint dictionary array has an odd element count"
                        )
                    )
                }
                var pairs: [(key: Any, value: Any, ordering: Data)] = []
                for index in stride(from: 0, to: array.count, by: 2) {
                    let normalizedKey = try normalize(array[index], key: nil)
                    let normalizedValue = try normalize(
                        array[index + 1],
                        key: nil
                    )
                    pairs.append((
                        key: normalizedKey,
                        value: normalizedValue,
                        ordering: try orderingBytes(for: normalizedKey)
                    ))
                }
                pairs.sort {
                    $0.ordering.lexicographicallyPrecedes($1.ordering)
                }
                return pairs.flatMap { [$0.key, $0.value] }
            }
            return try array.map { try normalize($0, key: nil) }
        }

        return value
    }

    private static func orderingBytes(for value: Any) throws -> Data {
        try JSONSerialization.data(
            withJSONObject: value,
            options: [.sortedKeys, .fragmentsAllowed, .withoutEscapingSlashes]
        )
    }
}

private struct ProfileHydrationDigestBuilder {
    private var hasher = SHA256()

    mutating func append(_ value: String) {
        append(Data(value.utf8))
    }

    mutating func append(_ value: Data) {
        var length = UInt64(value.count).bigEndian
        withUnsafeBytes(of: &length) { hasher.update(data: Data($0)) }
        hasher.update(data: value)
    }

    mutating func append(_ value: UInt64) {
        var encoded = value.bigEndian
        withUnsafeBytes(of: &encoded) { hasher.update(data: Data($0)) }
    }

    mutating func append(_ value: Bool) {
        append(value ? UInt64(1) : UInt64(0))
    }

    mutating func append(_ value: UUID) {
        append(value.uuidString.lowercased())
    }

    mutating func finalizeHex() -> String {
        hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

import Foundation

/// Account-neutral, validated input for a future cloud-profile bootstrap.
///
/// This value deliberately contains no account binding, profile identifier,
/// session authority, transport operation, or write instruction. It is only a
/// deterministic description of local facts plus an eligibility classification;
/// a later owner-bound policy layer must decide whether and how to publish it.
///
/// The seed is intentionally one-way Encodable. It can only be constructed in
/// this file from an exact canonical source artifact; plain SHA-256 is a stable
/// integrity identity, not authority for accepting an externally decoded seed.
struct CloudInitialProfileSeedV1: Encodable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let sourceSavedAt: Date
    let sourceProfileEnvelopeDigest: ProfileHydrationDigest
    let playerRevision: UInt64
    let economyRevision: UInt64
    let settings: Stamped<PlayerSettings>
    let selection: Stamped<PlayerSelection>
    fileprivate let runFacts: [CloudInitialProfileRunFactV1]
    fileprivate let ledgerFacts: [CloudInitialProfileLedgerFactV1]
    fileprivate let eligibility: CloudInitialProfileSeedEligibilityV1
    fileprivate let seedDigest: CloudInitialProfileSeedDigestV1

    fileprivate init(
        schemaVersion: Int,
        sourceSavedAt: Date,
        sourceProfileEnvelopeDigest: ProfileHydrationDigest,
        playerRevision: UInt64,
        economyRevision: UInt64,
        settings: Stamped<PlayerSettings>,
        selection: Stamped<PlayerSelection>,
        runFacts: [CloudInitialProfileRunFactV1],
        ledgerFacts: [CloudInitialProfileLedgerFactV1],
        eligibility: CloudInitialProfileSeedEligibilityV1,
        seedDigest: CloudInitialProfileSeedDigestV1
    ) {
        self.schemaVersion = schemaVersion
        self.sourceSavedAt = sourceSavedAt
        self.sourceProfileEnvelopeDigest = sourceProfileEnvelopeDigest
        self.playerRevision = playerRevision
        self.economyRevision = economyRevision
        self.settings = settings
        self.selection = selection
        self.runFacts = runFacts
        self.ledgerFacts = ledgerFacts
        self.eligibility = eligibility
        self.seedDigest = seedDigest
    }

    func canonicalEncodedData() throws -> Data {
        try CloudInitialProfileSeedCanonicalCodecV1.encode(self)
    }
}

fileprivate struct CloudInitialProfileRunFactV1: Encodable, Equatable, Sendable {
    let record: CompletedRunRecord
    let rewardedRunObservation: RewardedRunObservation?

    var runID: RunID { record.run.runID }

    fileprivate init(
        record: CompletedRunRecord,
        rewardedRunObservation: RewardedRunObservation?
    ) {
        self.record = record
        self.rewardedRunObservation = rewardedRunObservation
    }
}

fileprivate struct CloudInitialProfileLedgerFactV1: Encodable, Equatable, Sendable {
    let entry: CoinLedgerEntry
    let isPending: Bool

    var entryID: LedgerEntryID { entry.id }

    fileprivate init(entry: CoinLedgerEntry, isPending: Bool) {
        self.entry = entry
        self.isPending = isPending
    }
}

fileprivate enum CloudInitialProfileSeedEligibilityV1: Encodable, Equatable, Sendable {
    case emptyEconomyPublishable
    case pendingCreditProjectionRequired(entryIDs: [LedgerEntryID])
    case requiresOwnerPolicy(reasons: [CloudInitialProfileSeedOwnerPolicyReasonV1])
}

fileprivate enum CloudInitialProfileSeedOwnerPolicyReasonV1: Encodable, Equatable, Sendable {
    case confirmedLedgerEntry(LedgerEntryID)
    case storeKitHistory(LedgerEntryID)
    case rewardedAdHistory(LedgerEntryID)
    case catalogUnlockHistory(LedgerEntryID)
    case debitHistory(LedgerEntryID)
    case additionalTeamOwnership(TeamID)
    case additionalJerseyOwnership(JerseyID)
    case additionalFootballOwnership(FootballID)
}

fileprivate struct CloudInitialProfileSeedDigestV1: Encodable, Equatable,
    Hashable, Sendable
{
    fileprivate let rawValue: String

    private init(validatedRawValue: String) {
        precondition(
            Self.isValid(validatedRawValue),
            "CloudInitialProfileSeedDigestV1 must be a lowercase SHA-256 digest"
        )
        self.rawValue = validatedRawValue
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    fileprivate static func digest(canonicalMaterial: Data) -> Self {
        let digest = CloudProfileDigest.sha256(dataComponents: [
            Data("pocket-vector-cloud-initial-profile-seed-v1".utf8),
            canonicalMaterial,
        ])
        return Self(validatedRawValue: CloudProfileDigest.hex(digest))
    }

    private static func isValid(_ value: String) -> Bool {
        value.utf8.count == 64
            && value.utf8.allSatisfy {
                ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102)
            }
    }
}

#if DEBUG
/// Read-only projections for focused tests. These types and accessors do not
/// exist in Release, so they cannot become alternate production constructors.
struct CloudInitialProfileSeedRunFactDebugV1: Equatable {
    let record: CompletedRunRecord
    let rewardedRunObservation: RewardedRunObservation?

    var runID: RunID { record.run.runID }
}

struct CloudInitialProfileSeedLedgerFactDebugV1: Equatable {
    let entry: CoinLedgerEntry
    let isPending: Bool

    var entryID: LedgerEntryID { entry.id }
}

enum CloudInitialProfileSeedEligibilityDebugV1: Equatable {
    case emptyEconomyPublishable
    case pendingCreditProjectionRequired(entryIDs: [LedgerEntryID])
    case requiresOwnerPolicy(reasons: [CloudInitialProfileSeedOwnerPolicyReasonDebugV1])
}

enum CloudInitialProfileSeedOwnerPolicyReasonDebugV1: Equatable {
    case confirmedLedgerEntry(LedgerEntryID)
    case storeKitHistory(LedgerEntryID)
    case rewardedAdHistory(LedgerEntryID)
    case catalogUnlockHistory(LedgerEntryID)
    case debitHistory(LedgerEntryID)
    case additionalTeamOwnership(TeamID)
    case additionalJerseyOwnership(JerseyID)
    case additionalFootballOwnership(FootballID)
}

extension CloudInitialProfileSeedV1 {
    var debugRunFacts: [CloudInitialProfileSeedRunFactDebugV1] {
        runFacts.map {
            CloudInitialProfileSeedRunFactDebugV1(
                record: $0.record,
                rewardedRunObservation: $0.rewardedRunObservation
            )
        }
    }

    var debugLedgerFacts: [CloudInitialProfileSeedLedgerFactDebugV1] {
        ledgerFacts.map {
            CloudInitialProfileSeedLedgerFactDebugV1(
                entry: $0.entry,
                isPending: $0.isPending
            )
        }
    }

    var debugEligibility: CloudInitialProfileSeedEligibilityDebugV1 {
        switch eligibility {
        case .emptyEconomyPublishable:
            return .emptyEconomyPublishable
        case let .pendingCreditProjectionRequired(entryIDs):
            return .pendingCreditProjectionRequired(entryIDs: entryIDs)
        case let .requiresOwnerPolicy(reasons):
            return .requiresOwnerPolicy(reasons: reasons.map(\.debugValue))
        }
    }

    var debugSeedDigestRawValue: String {
        seedDigest.rawValue
    }
}

private extension CloudInitialProfileSeedOwnerPolicyReasonV1 {
    var debugValue: CloudInitialProfileSeedOwnerPolicyReasonDebugV1 {
        switch self {
        case let .confirmedLedgerEntry(id):
            return .confirmedLedgerEntry(id)
        case let .storeKitHistory(id):
            return .storeKitHistory(id)
        case let .rewardedAdHistory(id):
            return .rewardedAdHistory(id)
        case let .catalogUnlockHistory(id):
            return .catalogUnlockHistory(id)
        case let .debitHistory(id):
            return .debitHistory(id)
        case let .additionalTeamOwnership(id):
            return .additionalTeamOwnership(id)
        case let .additionalJerseyOwnership(id):
            return .additionalJerseyOwnership(id)
        case let .additionalFootballOwnership(id):
            return .additionalFootballOwnership(id)
        }
    }
}
#endif

enum CloudInitialProfileSeedError: Error, Equatable, Sendable {
    case sourceEnvelopeLimitExceeded(actual: Int, maximum: Int)
    case malformedSourceEnvelope
    case unsupportedSourceSchemaVersion(Int)
    case noncanonicalSourceEnvelope
    case sourceArtifactEnvelopeMismatch
    case sourceArtifactDigestMismatch
    case invalidSourceProfile
    case sourceAccountClaimAlreadyRequired
    case ledgerKeyMismatch(LedgerEntryID)
    case runKeyMismatch(RunID)
    case pendingEntryMissing(LedgerEntryID)
    case pendingEntryNotPositive(LedgerEntryID)
    case initialInventoryMissing
    case profileCollectionLimitExceeded
    case identifierLimitExceeded
    case seedEncodingFailed
    case seedLimitExceeded(actual: Int, maximum: Int)
}

/// Pure planner for a future initial cloud-profile publication.
///
/// The builder authenticates one exact canonical V4 artifact independently,
/// validates all profile invariants, and returns facts only. It has no storage,
/// repository, transport, checkpoint, journal, or cloud-owner dependency.
struct CloudInitialProfileSeedBuilderV1: Sendable {
    private let catalog: LaunchCatalog
    private let limits: ProfileHydrationLimits

    init(
        catalog: LaunchCatalog = .approved,
        limits: ProfileHydrationLimits = .production
    ) {
        self.catalog = catalog
        self.limits = limits
    }

    func makeSeed(
        from artifact: CanonicalProfileEnvelopeArtifactV1
    ) throws -> CloudInitialProfileSeedV1 {
        let canonical = try authenticate(artifact)
        let document = canonical.document

        try validateDeterministicStructuralErrors(document)
        try validateGameCenterQueue(document.player.pendingGameCenter)
        try validateCollectionBounds(document)
        try validateIdentifierBounds(document)

        do {
            try PlayerProfileValidator.validate(document, catalog: catalog)
        } catch {
            throw CloudInitialProfileSeedError.invalidSourceProfile
        }

        guard document.accountIdentity == .local else {
            throw CloudInitialProfileSeedError.sourceAccountClaimAlreadyRequired
        }

        let initialInventory = InventoryRules.initialInventory(catalog: catalog)
        guard initialInventory.ownedTeamIDs.isSubset(of: document.player.inventory.ownedTeamIDs),
              initialInventory.ownedJerseyIDs.isSubset(
                  of: document.player.inventory.ownedJerseyIDs
              ),
              initialInventory.ownedFootballIDs.isSubset(
                  of: document.player.inventory.ownedFootballIDs
              ) else {
            throw CloudInitialProfileSeedError.initialInventoryMissing
        }

        let observations = document.rewardedRunObservations ?? [:]
        let runFacts = document.player.completedRuns.values.map { record in
            CloudInitialProfileRunFactV1(
                record: record,
                rewardedRunObservation: observations[record.run.runID]
            )
        }.sorted { lhs, rhs in
            utf8Precedes(lhs.runID.description, rhs.runID.description)
        }

        let ledgerFacts = document.player.ledger.values.map { entry in
            CloudInitialProfileLedgerFactV1(
                entry: entry,
                isPending: document.pendingLedgerEntryIDs.contains(entry.id)
            )
        }.sorted { lhs, rhs in
            utf8Precedes(lhs.entryID.rawValue, rhs.entryID.rawValue)
        }

        let eligibility = classify(
            document: document,
            initialInventory: initialInventory,
            ledgerFacts: ledgerFacts
        )

        let material = CloudInitialProfileSeedDigestMaterialV1(
            schemaVersion: CloudInitialProfileSeedV1.schemaVersion,
            sourceSavedAt: canonical.savedAt,
            sourceProfileEnvelopeDigest: canonical.digest,
            playerRevision: document.player.revision,
            economyRevision: document.economyRevision,
            settings: document.player.settings,
            selection: document.player.selection,
            runFacts: runFacts,
            ledgerFacts: ledgerFacts,
            eligibility: eligibility
        )

        let canonicalMaterial: Data
        do {
            canonicalMaterial = try CloudInitialProfileSeedCanonicalCodecV1.encode(material)
        } catch {
            throw CloudInitialProfileSeedError.seedEncodingFailed
        }

        let seed = CloudInitialProfileSeedV1(
            schemaVersion: CloudInitialProfileSeedV1.schemaVersion,
            sourceSavedAt: canonical.savedAt,
            sourceProfileEnvelopeDigest: canonical.digest,
            playerRevision: document.player.revision,
            economyRevision: document.economyRevision,
            settings: document.player.settings,
            selection: document.player.selection,
            runFacts: runFacts,
            ledgerFacts: ledgerFacts,
            eligibility: eligibility,
            seedDigest: .digest(canonicalMaterial: canonicalMaterial)
        )

        let encodedSeed: Data
        do {
            encodedSeed = try seed.canonicalEncodedData()
        } catch {
            throw CloudInitialProfileSeedError.seedEncodingFailed
        }
        guard encodedSeed.count <= limits.maximumEncodedJournalBytes else {
            throw CloudInitialProfileSeedError.seedLimitExceeded(
                actual: encodedSeed.count,
                maximum: limits.maximumEncodedJournalBytes
            )
        }
        return seed
    }

    private func authenticate(
        _ artifact: CanonicalProfileEnvelopeArtifactV1
    ) throws -> CanonicalProfileEnvelopeArtifactV1 {
        guard artifact.exactBytes.count <= limits.maximumProfileEnvelopeBytes else {
            throw CloudInitialProfileSeedError.sourceEnvelopeLimitExceeded(
                actual: artifact.exactBytes.count,
                maximum: limits.maximumProfileEnvelopeBytes
            )
        }

        let decoded: DecodedProfileEnvelopeArtifactV1
        do {
            decoded = try PlayerProfileMigrator().decodeArtifact(artifact.exactBytes)
        } catch let error as ProfileMigrationError {
            switch error {
            case let .unsupportedSchemaVersion(version):
                throw CloudInitialProfileSeedError.unsupportedSourceSchemaVersion(version)
            case .malformedEnvelope, .unexpectedFormat:
                throw CloudInitialProfileSeedError.malformedSourceEnvelope
            }
        } catch {
            throw CloudInitialProfileSeedError.malformedSourceEnvelope
        }

        guard decoded.sourceSchemaVersion == PlayerProfileEnvelopeV4.schemaVersion else {
            throw CloudInitialProfileSeedError.unsupportedSourceSchemaVersion(
                decoded.sourceSchemaVersion
            )
        }

        let canonical: CanonicalProfileEnvelopeArtifactV1
        do {
            canonical = try PlayerProfileMigrator().canonicalArtifact(
                for: decoded.document,
                savedAt: decoded.savedAt
            )
        } catch {
            throw CloudInitialProfileSeedError.malformedSourceEnvelope
        }
        guard canonical.exactBytes == artifact.exactBytes else {
            throw CloudInitialProfileSeedError.noncanonicalSourceEnvelope
        }
        guard artifact.digest == ProfileHydrationDigest.envelopeBytes(artifact.exactBytes) else {
            throw CloudInitialProfileSeedError.sourceArtifactDigestMismatch
        }
        guard artifact.envelope == canonical.envelope else {
            throw CloudInitialProfileSeedError.sourceArtifactEnvelopeMismatch
        }
        return canonical
    }

    private func validateDeterministicStructuralErrors(
        _ document: LocalPlayerDocumentV1
    ) throws {
        let ledgerPairs = document.player.ledger.sorted {
            utf8Precedes($0.key.rawValue, $1.key.rawValue)
        }
        if let mismatch = ledgerPairs.first(where: { $0.key != $0.value.id }) {
            throw CloudInitialProfileSeedError.ledgerKeyMismatch(mismatch.key)
        }

        let runPairs = document.player.completedRuns.sorted {
            utf8Precedes($0.key.description, $1.key.description)
        }
        if let mismatch = runPairs.first(where: {
            $0.key != $0.value.run.runID
        }) {
            throw CloudInitialProfileSeedError.runKeyMismatch(mismatch.key)
        }

        let pendingIDs = document.pendingLedgerEntryIDs.sorted {
            utf8Precedes($0.rawValue, $1.rawValue)
        }
        for pendingID in pendingIDs {
            guard let entry = document.player.ledger[pendingID] else {
                throw CloudInitialProfileSeedError.pendingEntryMissing(pendingID)
            }
            guard entry.delta > 0 else {
                throw CloudInitialProfileSeedError.pendingEntryNotPositive(pendingID)
            }
        }
    }

    private func validateCollectionBounds(
        _ document: LocalPlayerDocumentV1
    ) throws {
        let queue = document.player.pendingGameCenter
        var counts = [
            document.player.completedRuns.count,
            document.player.ledger.count,
            document.player.achievementProgress.count,
            queue.pendingByPlayerID.count,
            queue.unboundPending.pendingAchievementPercents.count,
            document.pendingLedgerEntryIDs.count,
            document.settlementReceipts.count,
            document.rewardedRunObservations?.count ?? 0,
            document.player.inventory.ownedTeamIDs.count,
            document.player.inventory.ownedJerseyIDs.count,
            document.player.inventory.ownedFootballIDs.count,
            document.player.selection.value.selectedJerseyByTeam.count,
        ]
        counts.append(contentsOf: queue.pendingByPlayerID.values.map {
            $0.pendingAchievementPercents.count
        })
        var total = 0
        for count in counts {
            let addition = total.addingReportingOverflow(count)
            guard !addition.overflow,
                  addition.partialValue <= limits.maximumProfileCollectionEntries else {
                throw CloudInitialProfileSeedError.profileCollectionLimitExceeded
            }
            total = addition.partialValue
        }
    }

    /// Independently bounds and validates every persisted Game Center bucket.
    /// This is source validation only: no player bucket is claimed, moved, or
    /// selected, and the seed never depends on a live Game Center identity.
    private func validateGameCenterQueue(
        _ queue: PlayerScopedGameCenterQueueV1
    ) throws {
        guard queue.pendingByPlayerID.count
                <= PlayerScopedGameCenterQueueV1.maximumPlayerBucketCount else {
            throw CloudInitialProfileSeedError.profileCollectionLimitExceeded
        }

        let launchAchievementIDs = Set(AchievementCatalog.launch.map(\.id))
        func validatePending(_ pending: GameCenterPendingMaximaV1) throws {
            guard pending.pendingAchievementPercents.count
                    <= launchAchievementIDs.count else {
                throw CloudInitialProfileSeedError.profileCollectionLimitExceeded
            }
            guard pending.pendingHighScore >= 0 else {
                throw CloudInitialProfileSeedError.invalidSourceProfile
            }
            let achievements = pending.pendingAchievementPercents.sorted {
                utf8Precedes($0.key.rawValue, $1.key.rawValue)
            }
            for (achievementID, percent) in achievements {
                guard isBoundedIdentifier(achievementID.rawValue) else {
                    throw CloudInitialProfileSeedError.identifierLimitExceeded
                }
                guard launchAchievementIDs.contains(achievementID),
                      (0 ... 100).contains(percent) else {
                    throw CloudInitialProfileSeedError.invalidSourceProfile
                }
            }
        }

        try validatePending(queue.unboundPending)
        let playerBuckets = queue.pendingByPlayerID.sorted {
            utf8Precedes($0.key.rawValue, $1.key.rawValue)
        }
        for (playerID, pending) in playerBuckets {
            guard isBoundedIdentifier(playerID.rawValue) else {
                throw CloudInitialProfileSeedError.identifierLimitExceeded
            }
            guard GameCenterPlayerIDRuleV1.isValid(playerID),
                  !pending.isEmpty else {
                throw CloudInitialProfileSeedError.invalidSourceProfile
            }
            try validatePending(pending)
        }
    }

    private func validateIdentifierBounds(
        _ document: LocalPlayerDocumentV1
    ) throws {
        var identifiers = [
            document.accountIdentity.rawValue,
            document.player.settings.deviceID,
            document.player.selection.deviceID,
            document.player.selection.value.selectedTeamID.rawValue,
            document.player.selection.value.selectedFootballID.rawValue,
        ]

        for (teamID, jerseyID) in document.player.selection.value.selectedJerseyByTeam {
            identifiers.append(teamID.rawValue)
            identifiers.append(jerseyID.rawValue)
        }
        identifiers.append(contentsOf: document.player.inventory.ownedTeamIDs.map(\.rawValue))
        identifiers.append(contentsOf: document.player.inventory.ownedJerseyIDs.map(\.rawValue))
        identifiers.append(contentsOf: document.player.inventory.ownedFootballIDs.map(\.rawValue))
        identifiers.append(contentsOf: document.player.achievementProgress.keys.map(\.rawValue))
        let gameCenterQueue = document.player.pendingGameCenter
        identifiers.append(contentsOf: gameCenterQueue.unboundPending
            .pendingAchievementPercents.keys.map(\.rawValue))
        for (playerID, pending) in gameCenterQueue.pendingByPlayerID {
            identifiers.append(playerID.rawValue)
            identifiers.append(contentsOf: pending.pendingAchievementPercents.keys
                .map(\.rawValue))
        }

        for (runID, record) in document.player.completedRuns {
            identifiers.append(runID.description)
            identifiers.append(record.run.configuration.runID.description)
            identifiers.append(record.run.configuration.offenseTeamID.rawValue)
            identifiers.append(record.run.configuration.offenseJerseyID.rawValue)
            identifiers.append(record.run.configuration.defenseTeamID.rawValue)
            identifiers.append(record.run.configuration.defenseJerseyID.rawValue)
            identifiers.append(record.run.configuration.footballID.rawValue)
            identifiers.append(contentsOf: record.run.completedLaneIDs.map(\.rawValue))
        }
        for (entryID, entry) in document.player.ledger {
            identifiers.append(entryID.rawValue)
            identifiers.append(entry.id.rawValue)
            switch entry.reason {
            case let .gameplay(runID, _):
                identifiers.append(runID.description)
            case .signingBonus:
                break
            case let .rewardedAd(offerID, providerTransactionID):
                identifiers.append(offerID.rawValue)
                identifiers.append(providerTransactionID.rawValue)
            case let .storeKit(_, packID):
                identifiers.append(packID.rawValue)
            case let .catalogUnlock(itemID):
                identifiers.append(itemID.rawValue)
            }
        }
        identifiers.append(contentsOf: document.pendingLedgerEntryIDs.map(\.rawValue))
        identifiers.append(contentsOf: document.settlementReceipts.keys.map(\.description))
        identifiers.append(contentsOf: (document.rewardedRunObservations ?? [:]).keys.map(\.description))

        guard identifiers.allSatisfy(isBoundedIdentifier) else {
            throw CloudInitialProfileSeedError.identifierLimitExceeded
        }
    }

    private func isBoundedIdentifier(_ identifier: String) -> Bool {
        let bytes = identifier.utf8
        return !bytes.isEmpty
            && bytes.count <= limits.maximumIdentifierBytes
            && !bytes.contains(where: { $0 < 0x20 || $0 == 0x7f })
    }

    private func classify(
        document: LocalPlayerDocumentV1,
        initialInventory: PlayerInventory,
        ledgerFacts: [CloudInitialProfileLedgerFactV1]
    ) -> CloudInitialProfileSeedEligibilityV1 {
        let extraTeams = document.player.inventory.ownedTeamIDs
            .subtracting(initialInventory.ownedTeamIDs)
            .sorted { utf8Precedes($0.rawValue, $1.rawValue) }
        let extraJerseys = document.player.inventory.ownedJerseyIDs
            .subtracting(initialInventory.ownedJerseyIDs)
            .sorted { utf8Precedes($0.rawValue, $1.rawValue) }
        let extraFootballs = document.player.inventory.ownedFootballIDs
            .subtracting(initialInventory.ownedFootballIDs)
            .sorted { utf8Precedes($0.rawValue, $1.rawValue) }

        if ledgerFacts.isEmpty,
           extraTeams.isEmpty,
           extraJerseys.isEmpty,
           extraFootballs.isEmpty {
            return .emptyEconomyPublishable
        }

        let isPendingCreditOnly = !ledgerFacts.isEmpty
            && ledgerFacts.allSatisfy { fact in
                guard fact.isPending, fact.entry.delta > 0 else { return false }
                switch fact.entry.reason {
                case .gameplay, .signingBonus:
                    return true
                case .rewardedAd, .storeKit, .catalogUnlock:
                    return false
                }
            }
            && extraTeams.isEmpty
            && extraJerseys.isEmpty
            && extraFootballs.isEmpty
        if isPendingCreditOnly {
            return .pendingCreditProjectionRequired(
                entryIDs: ledgerFacts.map(\.entryID)
            )
        }

        var reasons: [CloudInitialProfileSeedOwnerPolicyReasonV1] = []
        for fact in ledgerFacts {
            if !fact.isPending {
                reasons.append(.confirmedLedgerEntry(fact.entryID))
            }
            if fact.entry.delta < 0 {
                reasons.append(.debitHistory(fact.entryID))
            }
            switch fact.entry.reason {
            case .gameplay, .signingBonus:
                break
            case .storeKit:
                reasons.append(.storeKitHistory(fact.entryID))
            case .rewardedAd:
                reasons.append(.rewardedAdHistory(fact.entryID))
            case .catalogUnlock:
                reasons.append(.catalogUnlockHistory(fact.entryID))
            }
        }
        reasons.append(contentsOf: extraTeams.map {
            .additionalTeamOwnership($0)
        })
        reasons.append(contentsOf: extraJerseys.map {
            .additionalJerseyOwnership($0)
        })
        reasons.append(contentsOf: extraFootballs.map {
            .additionalFootballOwnership($0)
        })
        reasons.sort { lhs, rhs in
            lhs.orderingBytes.lexicographicallyPrecedes(rhs.orderingBytes)
        }
        return .requiresOwnerPolicy(reasons: reasons)
    }
}

private struct CloudInitialProfileSeedDigestMaterialV1: Encodable {
    let schemaVersion: Int
    let sourceSavedAt: Date
    let sourceProfileEnvelopeDigest: ProfileHydrationDigest
    let playerRevision: UInt64
    let economyRevision: UInt64
    let settings: Stamped<PlayerSettings>
    let selection: Stamped<PlayerSelection>
    let runFacts: [CloudInitialProfileRunFactV1]
    let ledgerFacts: [CloudInitialProfileLedgerFactV1]
    let eligibility: CloudInitialProfileSeedEligibilityV1
}

private extension CloudInitialProfileSeedOwnerPolicyReasonV1 {
    var orderingBytes: Data {
        let value: String
        switch self {
        case let .confirmedLedgerEntry(id):
            value = "00-confirmed-ledger\u{0}\(id.rawValue)"
        case let .storeKitHistory(id):
            value = "01-storekit\u{0}\(id.rawValue)"
        case let .rewardedAdHistory(id):
            value = "02-rewarded-ad\u{0}\(id.rawValue)"
        case let .catalogUnlockHistory(id):
            value = "03-catalog-unlock\u{0}\(id.rawValue)"
        case let .debitHistory(id):
            value = "04-debit\u{0}\(id.rawValue)"
        case let .additionalTeamOwnership(id):
            value = "05-team\u{0}\(id.rawValue)"
        case let .additionalJerseyOwnership(id):
            value = "06-jersey\u{0}\(id.rawValue)"
        case let .additionalFootballOwnership(id):
            value = "07-football\u{0}\(id.rawValue)"
        }
        return Data(value.utf8)
    }
}

private func utf8Precedes(_ lhs: String, _ rhs: String) -> Bool {
    lhs.utf8.lexicographicallyPrecedes(rhs.utf8)
}

private enum CloudInitialProfileSeedCanonicalCodecV1 {
    private static let dictionaryArrayKeys: Set<String> = [
        "selectedJerseyByTeam",
    ]

    private static let setArrayKeys: Set<String> = [
        "completedLaneIDs",
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

    private static func normalize(_ value: Any, key: String?) throws -> Any {
        if let dictionary = value as? [String: Any] {
            var normalized: [String: Any] = [:]
            for (childKey, childValue) in dictionary {
                normalized[childKey] = try normalize(childValue, key: childKey)
            }
            return normalized
        }

        if let array = value as? [Any] {
            if let key, dictionaryArrayKeys.contains(key) {
                guard array.count.isMultiple(of: 2) else {
                    throw CloudInitialProfileSeedError.seedEncodingFailed
                }
                var pairs: [(key: Any, value: Any, ordering: Data)] = []
                for index in stride(from: 0, to: array.count, by: 2) {
                    let normalizedKey = try normalize(array[index], key: nil)
                    let normalizedValue = try normalize(array[index + 1], key: nil)
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

            let normalized = try array.map { try normalize($0, key: nil) }
            if let key, setArrayKeys.contains(key) {
                return try normalized.sorted {
                    try orderingBytes(for: $0).lexicographicallyPrecedes(
                        orderingBytes(for: $1)
                    )
                }
            }
            return normalized
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

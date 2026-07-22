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

struct CloudInitialProfilePublicationPlanV1: Equatable, Sendable {
    let accountID: CloudAccountID
    let operationID: OperationID
    let sourceProfileEnvelopeDigest: ProfileHydrationDigest
    let writes: [CloudRecordWrite]
}

enum CloudInitialProfilePublicationError: Error, Equatable, Sendable {
    case accountUnavailable
    case accountChanged
    case sourceSessionMismatch
    case sourceChanged
    case invalidProjection
    case ownerPolicyRequired
    case cloudReplicaAlreadyInitialized
    case partialOrDivergentPublication
    case receiptMismatch
}

enum CloudInitialProfilePublicationStatusV1: Equatable, Sendable {
    case committed(CloudAtomicWriteReceipt)
    case alreadyCommitted
}

/// Creates one all-or-nothing initial private-cloud replica. The plan contains
/// no local mutation authority. A caller must fetch the resulting zone through
/// the checkpoint pipeline and validate it before starting association
/// hydration; publication success alone never permits deleting local facts.
struct CloudInitialProfilePublicationPlannerV1: Sendable {
    private let profileConfiguration: CloudProfileSchemaConfiguration
    private let economyConfiguration: DurableEconomyCloudConfiguration
    private let catalog: LaunchCatalog

    init(
        profileConfiguration: CloudProfileSchemaConfiguration,
        economyConfiguration: DurableEconomyCloudConfiguration,
        catalog: LaunchCatalog = .approved
    ) {
        self.profileConfiguration = profileConfiguration
        self.economyConfiguration = economyConfiguration
        self.catalog = catalog
    }

    func makePlan(
        sourceArtifact: CanonicalProfileEnvelopeArtifactV1,
        sourceSession: ProfileSessionToken,
        cloudAccountID: CloudAccountID
    ) throws -> CloudInitialProfilePublicationPlanV1 {
        let seed = try CloudInitialProfileSeedBuilderV1(
            catalog: catalog
        ).makeSeed(from: sourceArtifact)
        guard sourceSession.accountIdentity == .local,
              sourceSession.profileID == sourceArtifact.document.player.profileID
        else {
            throw CloudInitialProfilePublicationError.sourceSessionMismatch
        }
        guard seed.sourceProfileEnvelopeDigest == sourceArtifact.digest else {
            throw CloudInitialProfilePublicationError.sourceChanged
        }
        switch seed.eligibility {
        case .emptyEconomyPublishable,
             .pendingCreditProjectionRequired:
            break
        case .requiresOwnerPolicy:
            throw CloudInitialProfilePublicationError.ownerPolicyRequired
        }

        let derived = CloudAccountDerivedBindings.derive(from: cloudAccountID)
        let binding = CloudProfileBindingV1(
            cloudAccountID: cloudAccountID,
            accountBinding: derived.durableAccountBinding,
            profileAccountIdentity: derived.playerAccountIdentity
        )
        let economy: CloudInitialEconomyProjectionV1
        do {
            economy = try CloudInitialEconomyProjectorV1(catalog: catalog).project(
                document: sourceArtifact.document,
                sourceSession: sourceSession,
                cloudAccountID: cloudAccountID,
                configuration: economyConfiguration
            )
        } catch {
            throw CloudInitialProfilePublicationError.invalidProjection
        }

        let runs = seed.runFacts.map {
            CloudProfileCompletedRunV1(
                binding: binding,
                record: $0.record,
                rewardedRunObservation: $0.rewardedRunObservation
            )
        }
        let runAccumulator = try CloudProfileRunAccumulatorV1.make(
            for: runs.map {
                CloudProfileRunAccumulatorEntryV1(
                    logicalRecordID: profileConfiguration.runRecordID(
                        for: $0.runID
                    ),
                    canonicalPayload: try CloudProfileCanonicalPayload.encode($0)
                )
            }
        )
        let settingsStamp = try CloudProfileMergeStampV1(
            logicalCounter: seed.settings.logicalCounter,
            deviceID: seed.settings.deviceID,
            modifiedAt: seed.settings.modifiedAt
        )
        let selectionStamp = try CloudProfileMergeStampV1(
            logicalCounter: seed.selection.logicalCounter,
            deviceID: seed.selection.deviceID,
            modifiedAt: seed.selection.modifiedAt
        )
        let rootRevision = max(
            1,
            runAccumulator.runCount,
            settingsStamp.logicalCounter,
            selectionStamp.logicalCounter
        )
        let root = CloudProfileRootV1(
            binding: binding,
            economyHeadRecordID: economyConfiguration.recordID,
            rootRevision: rootRevision,
            runAccumulator: runAccumulator
        )
        let settings = CloudProfileSettingsV1(
            binding: binding,
            stamp: settingsStamp,
            settings: seed.settings.value
        )
        let selection = CloudProfileSelectionV1(
            binding: binding,
            stamp: selectionStamp,
            selection: seed.selection.value
        )

        var writes: [CloudRecordWrite] = [
            try profileWrite(
                id: profileConfiguration.rootRecordID,
                recordType: profileConfiguration.rootRecordType,
                payload: root
            ),
            try profileWrite(
                id: profileConfiguration.settingsRecordID,
                recordType: profileConfiguration.settingsRecordType,
                payload: settings
            ),
            try profileWrite(
                id: profileConfiguration.selectionRecordID,
                recordType: profileConfiguration.selectionRecordType,
                payload: selection
            ),
            try economyWrite(
                id: economyConfiguration.recordID,
                payload: economy.head
            ),
        ]
        for run in runs {
            writes.append(try profileWrite(
                id: profileConfiguration.runRecordID(for: run.runID),
                recordType: profileConfiguration.runRecordType,
                payload: run
            ))
        }
        for marker in economy.ledgerMarkers.values {
            writes.append(try economyWrite(
                id: DurableEconomyCloudSchema.ledgerMarkerRecordID(
                    for: marker.record.entry.id,
                    headRecordID: economyConfiguration.recordID
                ),
                payload: marker
            ))
        }
        for marker in economy.rewardOfferMarkers.values {
            writes.append(try economyWrite(
                id: DurableEconomyCloudSchema.rewardOfferMarkerRecordID(
                    for: marker.redemption.offerID,
                    headRecordID: economyConfiguration.recordID
                ),
                payload: marker
            ))
        }
        writes.sort {
            $0.id.rawValue.utf8.lexicographicallyPrecedes($1.id.rawValue.utf8)
        }
        guard Set(writes.map(\.id)).count == writes.count else {
            throw CloudInitialProfilePublicationError.invalidProjection
        }
        let operationDigest = CloudProfileDigest.sha256(components: [
            "pocket-vector-initial-profile-publication-v1",
            cloudAccountID.rawValue,
            seed.seedDigest.rawValue,
        ])
        return CloudInitialProfilePublicationPlanV1(
            accountID: cloudAccountID,
            operationID: OperationID(
                "profile-bootstrap-v1-\(CloudProfileDigest.hex(operationDigest))"
            ),
            sourceProfileEnvelopeDigest: sourceArtifact.digest,
            writes: writes
        )
    }

    private func profileWrite<Payload: Encodable>(
        id: CloudRecordID,
        recordType: String,
        payload: Payload
    ) throws -> CloudRecordWrite {
        CloudRecordWrite(
            id: id,
            recordType: recordType,
            fields: [
                profileConfiguration.payloadFieldName:
                    try CloudProfileCanonicalPayload.encode(payload),
            ],
            precondition: .mustNotExist
        )
    }

    private func economyWrite<Payload: Encodable>(
        id: CloudRecordID,
        payload: Payload
    ) throws -> CloudRecordWrite {
        CloudRecordWrite(
            id: id,
            recordType: economyConfiguration.recordType,
            fields: [
                economyConfiguration.payloadFieldName:
                    try DurableEconomyCloudSchema.makePayloadEncoder()
                        .encode(payload),
            ],
            precondition: .mustNotExist
        )
    }
}

/// Serializes first-publication attempts and proves ambiguous/retried commits
/// by exact record payload comparison. A pre-existing but evolved replica is
/// never treated as this publication and must instead enter ordinary hydration.
actor CloudInitialProfilePublisherV1 {
    private let cloud: any CloudSyncTransport

    init(cloud: any CloudSyncTransport) {
        self.cloud = cloud
    }

    func publish(
        _ plan: CloudInitialProfilePublicationPlanV1
    ) async throws -> CloudInitialProfilePublicationStatusV1 {
        try await requireCurrentAccount(plan.accountID)
        let observed = try await cloud.records(
            accountID: plan.accountID,
            ids: plan.writes.map(\.id)
        )
        if !observed.isEmpty {
            guard exactMatch(observed, plan: plan) else {
                if observed.contains(where: {
                    $0.id == plan.writes.first(where: {
                        $0.id.rawValue == CloudProfileSchemaConfiguration
                            .rootLogicalRecordID.rawValue
                    })?.id
                }) {
                    throw CloudInitialProfilePublicationError
                        .cloudReplicaAlreadyInitialized
                }
                throw CloudInitialProfilePublicationError
                    .partialOrDivergentPublication
            }
            try await requireCurrentAccount(plan.accountID)
            return .alreadyCommitted
        }

        let request = CloudAtomicWriteRequest(
            accountID: plan.accountID,
            operationID: plan.operationID,
            writes: plan.writes
        )
        do {
            let receipt = try await cloud.commitAtomically(request)
            guard receipt.accountID == plan.accountID,
                  receipt.operationID == plan.operationID,
                  Set(receipt.savedChangeTags.keys) == Set(plan.writes.map(\.id))
            else {
                throw CloudInitialProfilePublicationError.receiptMismatch
            }
            try await requireCurrentAccount(plan.accountID)
            return .committed(receipt)
        } catch {
            // Commit responses can be lost after the provider made the atomic
            // transaction durable. Only one exact reread may convert that
            // ambiguity to success; every partial or divergent result fails.
            let refreshed = try await cloud.records(
                accountID: plan.accountID,
                ids: plan.writes.map(\.id)
            )
            guard exactMatch(refreshed, plan: plan) else { throw error }
            try await requireCurrentAccount(plan.accountID)
            return .alreadyCommitted
        }
    }

    private func requireCurrentAccount(_ expected: CloudAccountID) async throws {
        switch await cloud.accountState() {
        case let .available(actual) where actual == expected: return
        case .available: throw CloudInitialProfilePublicationError.accountChanged
        case .unknown, .signedOut, .restricted:
            throw CloudInitialProfilePublicationError.accountUnavailable
        }
    }

    private func exactMatch(
        _ records: [CloudRecord],
        plan: CloudInitialProfilePublicationPlanV1
    ) -> Bool {
        guard records.count == plan.writes.count,
              Set(records.map(\.id)).count == records.count else { return false }
        let byID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        return plan.writes.allSatisfy { write in
            guard let record = byID[write.id] else { return false }
            return record.recordType == write.recordType
                && record.fields == write.fields
        }
    }
}

struct CloudInitialProfileValidatedTargetV1: Sendable {
    let checkpoint: CloudReplicaCheckpointV1
    let replica: ValidatedCloudProfileReplicaV1
}

/// Runtime-owned implementation wraps the sealed checkpoint-store generation
/// lease APIs. The ordering is explicit: prepare/save the zone checkpoint
/// before any atomic write, then fetch/save/validate the complete post-write
/// replica. Recovery validates the exact checkpoint persisted in the mirrored
/// association journal instead of trusting cached sync status.
protocol CloudInitialProfileReplicaPreparingV1: Sendable {
    func prepareCheckpointedZone(
        accountID: CloudAccountID
    ) async throws

    func refreshValidatedTarget(
        accountID: CloudAccountID
    ) async throws -> CloudInitialProfileValidatedTargetV1

    func validateRecoveredTarget(
        checkpoint: CloudReplicaCheckpointV1,
        accountID: CloudAccountID
    ) async throws -> CloudInitialProfileValidatedTargetV1
}

struct CloudAuthoritativeProfileRefreshV1: Sendable {
    let predecessorCheckpointIdentity:
        ProfileHydrationCheckpointIdentityV1?
    let target: CloudInitialProfileValidatedTargetV1
}

enum ProductionCloudProfileReplicaPreparerError: Error, Equatable, Sendable {
    case accountMismatch
    case configurationScopeMismatch
    case replicaEpochMismatch
    case replicaUninitialized
    case checkpointPublicationMismatch
    case hydrationCleanupMissing
}

/// Production checkpoint composition for one exact private-cloud account and
/// configuration scope. This actor creates and retains the canonical process
/// generation authority together with the only disk store bound to it. Every
/// network fetch escapes the bounded generation gate; every durable save
/// re-enters with the exact opaque generation token minted before that fetch.
actor ProductionCloudProfileReplicaPreparerV1:
    CloudInitialProfileReplicaPreparingV1
{
    private let expectedAccountID: CloudAccountID
    private let configurationScopeFingerprint: CloudReplicaScopeFingerprint
    private let predecessorConfigurationScopeFingerprint:
        CloudReplicaScopeFingerprint
    private let generationAuthority: CloudAccountGenerationAuthority
    private let checkpointStore: AtomicCloudReplicaCheckpointDiskStore
    private let changeFetcher: CloudReplicaScopedChangeFetcherV1
    private let validator: CloudProfileReplicaValidator
    private let installingDeviceID: String
    private let now: @Sendable () -> Date
    private let replicaEpochFactory: @Sendable () -> UUID
    private var activeGeneration: ActiveCloudAccountGeneration?

    static func live(
        accountID: CloudAccountID,
        checkpointRootDirectoryURL: URL,
        configuration: ProductionCloudWriteConfiguration,
        economyVerifier: CloudProfileCompleteEconomyHistoryVerifier,
        installingDeviceID: String,
        now: @escaping @Sendable () -> Date = Date.init
    ) throws -> ProductionCloudProfileReplicaPreparerV1 {
        try ProductionCloudProfileReplicaPreparerV1(
            accountID: accountID,
            checkpointRootDirectoryURL: checkpointRootDirectoryURL,
            configuration: configuration,
            economyVerifier: economyVerifier,
            installingDeviceID: installingDeviceID,
            changeFetcher: .live(configuration: configuration),
            fileSystem: FoundationCloudReplicaCheckpointFileSystem(),
            now: now,
            replicaEpochFactory: UUID.init
        )
    }

    private init(
        accountID: CloudAccountID,
        checkpointRootDirectoryURL: URL,
        configuration: ProductionCloudWriteConfiguration,
        economyVerifier: CloudProfileCompleteEconomyHistoryVerifier,
        installingDeviceID: String,
        changeFetcher: CloudReplicaScopedChangeFetcherV1,
        fileSystem: any CloudReplicaCheckpointFileSystem,
        now: @escaping @Sendable () -> Date,
        replicaEpochFactory: @escaping @Sendable () -> UUID
    ) throws {
        precondition(ProfileStampDeviceIDRuleV1.isValid(installingDeviceID))
        let scope = CloudReplicaScopeFingerprint.make(for: configuration)
        guard changeFetcher.configurationScopeFingerprint == scope else {
            throw ProductionCloudProfileReplicaPreparerError
                .configurationScopeMismatch
        }
        let bindings = CloudAccountDerivedBindings.derive(from: accountID)
        let generationAuthority = CloudAccountGenerationAuthority()
        expectedAccountID = accountID
        configurationScopeFingerprint = scope
        predecessorConfigurationScopeFingerprint =
            LaunchAchievementCloudScopeTransitionV2ToV3.sourceScope(
                for: configuration
            )
        self.generationAuthority = generationAuthority
        checkpointStore = AtomicCloudReplicaCheckpointDiskStore(
            rootDirectoryURL: checkpointRootDirectoryURL,
            fileSystem: fileSystem,
            accountGenerationAuthority: generationAuthority
        )
        self.changeFetcher = changeFetcher
        validator = try CloudProfileReplicaValidator(
            configuration: configuration.profile,
            economyConfiguration: configuration.economy,
            expectedAccountID: accountID,
            expectedScopeFingerprint: scope,
            expectedBinding: CloudProfileBindingV1(
                cloudAccountID: accountID,
                accountBinding: bindings.durableAccountBinding,
                profileAccountIdentity: bindings.playerAccountIdentity
            ),
            economyVerifier: economyVerifier
        )
        self.installingDeviceID = installingDeviceID
        self.now = now
        self.replicaEpochFactory = replicaEpochFactory
    }

    #if DEBUG
    init(
        testingAccountID accountID: CloudAccountID,
        checkpointRootDirectoryURL: URL,
        configuration: ProductionCloudWriteConfiguration,
        economyVerifier: CloudProfileCompleteEconomyHistoryVerifier,
        installingDeviceID: String,
        changeFetcher: CloudReplicaScopedChangeFetcherV1,
        fileSystem: any CloudReplicaCheckpointFileSystem =
            FoundationCloudReplicaCheckpointFileSystem(),
        now: @escaping @Sendable () -> Date = Date.init,
        replicaEpochFactory: @escaping @Sendable () -> UUID = UUID.init
    ) throws {
        try self.init(
            accountID: accountID,
            checkpointRootDirectoryURL: checkpointRootDirectoryURL,
            configuration: configuration,
            economyVerifier: economyVerifier,
            installingDeviceID: installingDeviceID,
            changeFetcher: changeFetcher,
            fileSystem: fileSystem,
            now: now,
            replicaEpochFactory: replicaEpochFactory
        )
    }
    #endif

    func prepareCheckpointedZone(accountID: CloudAccountID) async throws {
        let generation = try await requireGeneration(accountID: accountID)
        let checkpoint = try await ensureCheckpoint(generation: generation)
        _ = try await validator.validate(checkpoint)
    }

    func refreshValidatedTarget(
        accountID: CloudAccountID
    ) async throws -> CloudInitialProfileValidatedTargetV1 {
        try await refreshAuthoritativeReplica(accountID: accountID).target
    }

    func validateRecoveredTarget(
        checkpoint: CloudReplicaCheckpointV1,
        accountID: CloudAccountID
    ) async throws -> CloudInitialProfileValidatedTargetV1 {
        let generation = try await requireGeneration(accountID: accountID)
        guard checkpoint.accountID == generation.accountID,
              checkpoint.configurationScopeFingerprint
                == generation.configurationScopeFingerprint,
              checkpoint.replicaEpoch == generation.replicaEpoch else {
            throw ProductionCloudProfileReplicaPreparerError
                .replicaEpochMismatch
        }
        return try await initializedTarget(checkpoint)
    }

    func refreshAuthoritativeReplica(
        accountID: CloudAccountID
    ) async throws -> CloudAuthoritativeProfileRefreshV1 {
        let generation = try await requireGeneration(accountID: accountID)
        let loaded = try await checkpointStore.load(
            for: accountID,
            configurationScopeFingerprint: configurationScopeFingerprint,
            at: now()
        )

        let predecessor: CloudReplicaCheckpointV1
        if let checkpoint = loaded.checkpoint {
            predecessor = checkpoint
        } else {
            let resumed = try await checkpointStore.resumeActiveReplicaEpoch(
                for: accountID,
                configurationScopeFingerprint: configurationScopeFingerprint
            )
            if resumed?.acceptedHistory != nil {
                predecessor = try await reconstructCheckpoint(
                    generation: generation
                )
            } else {
                let checkpoint = try await bootstrapCheckpoint(
                    generation: generation
                )
                return CloudAuthoritativeProfileRefreshV1(
                    predecessorCheckpointIdentity: nil,
                    target: try await initializedTarget(checkpoint)
                )
            }
        }

        let targetCheckpoint = try await advanceCheckpoint(
            predecessor: predecessor,
            generation: generation
        )
        return CloudAuthoritativeProfileRefreshV1(
            predecessorCheckpointIdentity:
                ProfileHydrationCheckpointIdentityV1(
                    checkpoint: predecessor
                ),
            target: try await initializedTarget(targetCheckpoint)
        )
    }

    /// Refreshes and then performs the existing crash-safe in-place profile
    /// transaction. No repository barrier or profile write exists before the
    /// complete network fetch has been durably checkpointed and validated.
    func refreshAndHydrateSameRepository(
        expected context: DurableEconomySessionContext,
        repository: LocalPlayerProfileRepository
    ) async throws -> LocalPlayerProfileSnapshot {
        let bindings = CloudAccountDerivedBindings.derive(
            from: expectedAccountID
        )
        guard context.cloudAccountID == expectedAccountID,
              context.accountBinding == bindings.durableAccountBinding,
              context.profileSession.accountIdentity
                == bindings.playerAccountIdentity,
              context.profileSession.profileID
                == bindings.durableAccountBinding.profileID else {
            throw ProductionCloudProfileReplicaPreparerError.accountMismatch
        }

        let source = try await repository.hydrationSource(
            session: context.profileSession
        )
        let refresh = try await refreshAuthoritativeReplica(
            accountID: expectedAccountID
        )
        let hydrated = try CloudProfileHydrator().hydrate(
            source: source,
            replica: refresh.target.replica,
            context: CloudProfileHydrationContextV1(
                cloudAccountID: expectedAccountID,
                installingDeviceID: installingDeviceID,
                candidateSavedAt: now()
            )
        )
        if hydrated.isNoOp {
            return try await repository.snapshot()
        }

        let checkpoint = refresh.target.checkpoint
        let journal = try ProfileHydrationJournalV1.make(
            createdAt: now(),
            sourceSession: source.activeSession,
            sourcePlayerRevision: hydrated.revisionPlan.sourcePlayerRevision,
            sourceEconomyRevision: hydrated.revisionPlan.sourceEconomyRevision,
            sourceProfileEnvelope: source.exactEnvelopeBytes,
            candidateProfileEnvelope: hydrated.candidateEnvelope.canonicalBytes,
            cloudAccountID: expectedAccountID,
            configurationScopeFingerprint: configurationScopeFingerprint,
            replicaEpoch: checkpoint.replicaEpoch,
            predecessorCheckpointIdentity:
                refresh.predecessorCheckpointIdentity,
            targetCheckpoint: checkpoint
        )
        let transactionStore = ProfileHydrationFileTransactionStore(
            profileDirectoryURL: await repository.profileDirectoryURL()
        )
        let admission: LocalProfileHydrationAdmissionV1
        do {
            admission = try await repository.beginHydration(
                journal,
                session: context.profileSession,
                transactionStore: transactionStore
            )
        } catch let ambiguousAdmissionError {
            // A failed durable write can occur after the repository installed
            // its mutation barrier. Resume that exact actor-owned capability
            // and idempotently re-enter admission; a pre-claim failure has no
            // resumable barrier and preserves the original error.
            do {
                _ = try await repository.resumeHydrationBarrier(
                    journal,
                    session: context.profileSession
                )
                admission = try await repository.retryHydrationAdmission(
                    journal,
                    session: context.profileSession,
                    transactionStore: transactionStore
                )
            } catch {
                throw ambiguousAdmissionError
            }
        }
        let expectedBinding = ProfileHydrationExpectedBinding(
            cloudAccountID: expectedAccountID,
            configurationScopeFingerprint: configurationScopeFingerprint,
            replicaEpoch: checkpoint.replicaEpoch
        )
        let confirmation = try await generationAuthority
            .withCurrentGeneration(
                try await requireGeneration(accountID: expectedAccountID)
            ) { lease in
                try await self.checkpointStore.withCurrentCheckpointLease(
                    generationLease: lease,
                    at: self.now()
                ) { checkpointLease in
                    _ = try transactionStore.installCandidate(
                        transactionID: journal.transactionID,
                        expected: expectedBinding,
                        checkpointLease: checkpointLease
                    )
                    return try transactionStore.confirmTargetCleanup(
                        transactionID: journal.transactionID,
                        expected: expectedBinding,
                        checkpointLease: checkpointLease,
                        recoveryHandle: admission.recoveryHandle
                    )
                }
            }
        guard let confirmation else {
            throw ProductionCloudProfileReplicaPreparerError
                .hydrationCleanupMissing
        }
        _ = try await repository.adoptCommittedHydration(
            journal,
            session: context.profileSession,
            capability: admission.capability,
            cleanupConfirmation: confirmation
        )
        return try await repository.snapshot()
    }

    private func requireGeneration(
        accountID: CloudAccountID
    ) async throws -> ActiveCloudAccountGeneration {
        guard accountID == expectedAccountID else {
            throw ProductionCloudProfileReplicaPreparerError.accountMismatch
        }
        if let activeGeneration { return activeGeneration }
        if let authority = try await checkpointStore.activeReplicaAuthority(
            for: accountID
        ) {
            if authority.configurationScopeFingerprint
                == predecessorConfigurationScopeFingerprint {
                // The repository has already loaded, which proves no durable
                // hydration barrier remains in its profile directory. Revoke
                // the exact V1 epoch before a fresh V2 scope is activated;
                // the old cursor and accepted history are never reused.
                try await checkpointStore.remove(
                    for: accountID,
                    revoking: authority.replicaEpoch
                )
            } else if authority.configurationScopeFingerprint
                        != configurationScopeFingerprint {
                throw ProductionCloudProfileReplicaPreparerError
                    .configurationScopeMismatch
            }
        }
        let resumed = try await checkpointStore.resumeActiveReplicaEpoch(
            for: accountID,
            configurationScopeFingerprint: configurationScopeFingerprint
        )
        let replicaEpoch: UUID
        if let resumed {
            replicaEpoch = resumed.replicaEpoch
        } else {
            replicaEpoch = replicaEpochFactory()
            try await checkpointStore.activate(
                replicaEpoch: replicaEpoch,
                configurationScopeFingerprint: configurationScopeFingerprint,
                for: accountID
            )
        }
        let generation = try await generationAuthority.activate(
            accountID: accountID,
            configurationScopeFingerprint: configurationScopeFingerprint,
            replicaEpoch: replicaEpoch
        )
        activeGeneration = generation
        return generation
    }

    private func ensureCheckpoint(
        generation: ActiveCloudAccountGeneration
    ) async throws -> CloudReplicaCheckpointV1 {
        let loaded = try await checkpointStore.load(
            for: generation.accountID,
            configurationScopeFingerprint: configurationScopeFingerprint,
            at: now()
        )
        if let checkpoint = loaded.checkpoint { return checkpoint }
        let resumed = try await checkpointStore.resumeActiveReplicaEpoch(
            for: generation.accountID,
            configurationScopeFingerprint: configurationScopeFingerprint
        )
        if resumed?.acceptedHistory != nil {
            return try await reconstructCheckpoint(generation: generation)
        }
        return try await bootstrapCheckpoint(generation: generation)
    }

    private func bootstrapCheckpoint(
        generation: ActiveCloudAccountGeneration
    ) async throws -> CloudReplicaCheckpointV1 {
        let context = try await generationAuthority.withCurrentGeneration(
            generation
        ) { lease in
            try await self.checkpointStore.beginInitialBootstrapPublication(
                generationLease: lease,
                at: self.now()
            )
        }
        let publication = try await context.fetchCompleteSnapshot(
            using: changeFetcher
        )
        try await generationAuthority.withCurrentGeneration(generation) {
            lease in
            try await self.checkpointStore.saveInitialBootstrapPublication(
                publication,
                generationLease: lease,
                at: self.now()
            )
        }
        return try await exactReload(publication.checkpoint)
    }

    private func reconstructCheckpoint(
        generation: ActiveCloudAccountGeneration
    ) async throws -> CloudReplicaCheckpointV1 {
        let context = try await generationAuthority.withCurrentGeneration(
            generation
        ) { lease in
            try await self.checkpointStore
                .beginRequireExistingFullSnapshotReconstruction(
                    generationLease: lease,
                    at: self.now()
                )
        }
        let reconstruction = try await context.fetchCompleteSnapshot(
            using: changeFetcher
        )
        try await generationAuthority.withCurrentGeneration(generation) {
            lease in
            try await self.checkpointStore.saveReconstructedFullSnapshot(
                reconstruction,
                generationLease: lease,
                at: self.now()
            )
        }
        return try await exactReload(reconstruction.checkpoint)
    }

    private func advanceCheckpoint(
        predecessor: CloudReplicaCheckpointV1,
        generation: ActiveCloudAccountGeneration
    ) async throws -> CloudReplicaCheckpointV1 {
        let context = try await generationAuthority.withCurrentGeneration(
            generation
        ) { lease in
            try await self.checkpointStore.beginIncrementalOrdinaryPublication(
                generationLease: lease,
                at: self.now()
            )
        }
        let publication = try await context.fetchCompleteChanges(
            using: changeFetcher
        )
        guard publication.predecessorCheckpointIdentity
                == ProfileHydrationCheckpointIdentityV1(
                    checkpoint: predecessor
                ) else {
            throw ProductionCloudProfileReplicaPreparerError
                .checkpointPublicationMismatch
        }
        try await generationAuthority.withCurrentGeneration(generation) {
            lease in
            try await self.checkpointStore.saveOrdinaryPublication(
                publication,
                generationLease: lease,
                at: self.now()
            )
        }
        return try await exactReload(publication.checkpoint)
    }

    private func exactReload(
        _ expected: CloudReplicaCheckpointV1
    ) async throws -> CloudReplicaCheckpointV1 {
        let loaded = try await checkpointStore.load(
            for: expectedAccountID,
            configurationScopeFingerprint: configurationScopeFingerprint,
            at: now()
        )
        guard loaded.checkpoint == expected else {
            throw ProductionCloudProfileReplicaPreparerError
                .checkpointPublicationMismatch
        }
        return expected
    }

    private func initializedTarget(
        _ checkpoint: CloudReplicaCheckpointV1
    ) async throws -> CloudInitialProfileValidatedTargetV1 {
        switch try await validator.validate(checkpoint) {
        case .uninitialized:
            throw ProductionCloudProfileReplicaPreparerError
                .replicaUninitialized
        case let .initialized(replica):
            return CloudInitialProfileValidatedTargetV1(
                checkpoint: checkpoint,
                replica: replica
            )
        }
    }
}

/// Narrow commerce adapter: authoritative refresh and crash-safe installation
/// are inseparable and always target the same repository used by the durable
/// economy coordinator.
struct SameRepositoryOnlineCommerceAuthoritativeRefresherV1:
    OnlineCommerceAuthoritativeRefreshing,
    Sendable
{
    let preparer: ProductionCloudProfileReplicaPreparerV1
    let repository: LocalPlayerProfileRepository

    func refreshAuthoritativeProfile(
        expected context: DurableEconomySessionContext
    ) async throws -> LocalPlayerProfileSnapshot {
        try await preparer.refreshAndHydrateSameRepository(
            expected: context,
            repository: repository
        )
    }
}

enum CloudInitialProfileAssociationCoordinatorError: Error, Equatable,
    Sendable
{
    case accountUnavailable
    case accountChanged
    case recoveredCandidateMismatch
    case refreshedCheckpointMismatch
}

/// End-to-end first-association coordinator. Every mutation-capable local fact
/// is frozen before network work. Publication is preceded by sealed zone
/// bootstrap, followed by a complete checkpoint refresh and schema validation;
/// only that validated replica may create the cross-directory candidate.
actor CloudInitialProfileAssociationCoordinatorV1 {
    private let cloud: any CloudSyncTransport
    private let planner: CloudInitialProfilePublicationPlannerV1
    private let publisher: CloudInitialProfilePublisherV1
    private let replicaPreparer: any CloudInitialProfileReplicaPreparingV1
    private let associationStore: ProfileInitialAssociationStoreV1
    private let installingDeviceID: String
    private let now: @Sendable () -> Date

    init(
        cloud: any CloudSyncTransport,
        planner: CloudInitialProfilePublicationPlannerV1,
        replicaPreparer: any CloudInitialProfileReplicaPreparingV1,
        associationStore: ProfileInitialAssociationStoreV1,
        installingDeviceID: String,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        precondition(ProfileStampDeviceIDRuleV1.isValid(installingDeviceID))
        self.cloud = cloud
        self.planner = planner
        publisher = CloudInitialProfilePublisherV1(cloud: cloud)
        self.replicaPreparer = replicaPreparer
        self.associationStore = associationStore
        self.installingDeviceID = installingDeviceID
        self.now = now
    }

    func claimAndHydrate(
        accountID: CloudAccountID,
        sourceRepository: LocalPlayerProfileRepository,
        targetDirectoryURL: URL,
        targetRepository: LocalPlayerProfileRepository
    ) async throws -> ProfileInitialAssociationResultV1 {
        let sourceDirectoryURL = await sourceRepository.profileDirectoryURL()
        if let committed = try await associationStore.committedAssociation(
            sourceDirectoryURL: sourceDirectoryURL
        ) {
            guard committed.cloudAccountID == accountID,
                  committed.targetDirectoryURL
                    == targetDirectoryURL.standardizedFileURL else {
                throw CloudInitialProfileAssociationCoordinatorError
                    .accountChanged
            }
            let reopened = try await associationStore
                .reopenCommittedAssociation(
                    committed,
                    expectedAccountID: accountID,
                    sourceRepository: sourceRepository,
                    targetRepository: targetRepository,
                    at: now()
            )
            return reopened
        }
        try await requireAccount(accountID)

        if let recovered = try await associationStore.recoverableJournal(
            sourceDirectoryURL: sourceDirectoryURL,
            targetDirectoryURL: targetDirectoryURL
        ) {
            return try await recover(
                recovered,
                accountID: accountID,
                sourceRepository: sourceRepository,
                targetRepository: targetRepository
            )
        }

        let capability = try await sourceRepository.beginInitialAssociation(
            targetCloudAccountID: accountID,
            targetDirectoryURL: targetDirectoryURL
        )
        try await replicaPreparer.prepareCheckpointedZone(accountID: accountID)
        try await requireAccount(accountID)

        let plan = try planner.makePlan(
            sourceArtifact: capability.sourceArtifact,
            sourceSession: capability.sourceSession,
            cloudAccountID: accountID
        )
        do {
            _ = try await publisher.publish(plan)
        } catch CloudInitialProfilePublicationError.cloudReplicaAlreadyInitialized {
            // A same-account replica can have advanced after an earlier exact
            // publication. Never overwrite it; the full refresh below merges.
        }
        try await requireAccount(accountID)
        let target = try await replicaPreparer.refreshValidatedTarget(
            accountID: accountID
        )
        guard target.checkpoint.accountID == accountID else {
            throw CloudInitialProfileAssociationCoordinatorError
                .refreshedCheckpointMismatch
        }
        let hydration = try CloudProfileHydrator().hydrateInitialAssociation(
            source: CloudProfileHydrationSourceV1(
                exactEnvelopeBytes: capability.sourceArtifact.exactBytes,
                activeSession: capability.sourceSession
            ),
            replica: target.replica,
            context: CloudProfileHydrationContextV1(
                cloudAccountID: accountID,
                installingDeviceID: installingDeviceID,
                candidateSavedAt: now()
            )
        )
        let journal = try ProfileInitialAssociationJournalV1.make(
            createdAt: now(),
            capability: capability,
            candidateEnvelope: hydration.candidateEnvelope.canonicalBytes,
            targetCheckpoint: target.checkpoint
        )
        try await requireAccount(accountID)
        return try await associationStore.associate(
            journal: journal,
            capability: capability,
            sourceRepository: sourceRepository,
            targetRepository: targetRepository,
            now: now()
        )
    }

    private func recover(
        _ journal: ProfileInitialAssociationJournalV1,
        accountID: CloudAccountID,
        sourceRepository: LocalPlayerProfileRepository,
        targetRepository: LocalPlayerProfileRepository
    ) async throws -> ProfileInitialAssociationResultV1 {
        guard journal.cloudAccountID == accountID else {
            throw CloudInitialProfileAssociationCoordinatorError.accountChanged
        }
        let capability: LocalProfileInitialAssociationCapabilityV1
        do {
            capability = try await sourceRepository.resumeInitialAssociation(
                targetCloudAccountID: accountID,
                targetDirectoryURL: journal.targetDirectoryURL
            )
        } catch {
            capability = try await sourceRepository.beginInitialAssociation(
                targetCloudAccountID: accountID,
                targetDirectoryURL: journal.targetDirectoryURL,
                transactionID: journal.transactionID
            )
        }
        let target = try await replicaPreparer.validateRecoveredTarget(
            checkpoint: journal.targetCheckpoint,
            accountID: accountID
        )
        guard target.checkpoint == journal.targetCheckpoint else {
            throw CloudInitialProfileAssociationCoordinatorError
                .refreshedCheckpointMismatch
        }
        let hydration = try CloudProfileHydrator().hydrateInitialAssociation(
            source: CloudProfileHydrationSourceV1(
                exactEnvelopeBytes: capability.sourceArtifact.exactBytes,
                activeSession: capability.sourceSession
            ),
            replica: target.replica,
            context: CloudProfileHydrationContextV1(
                cloudAccountID: accountID,
                installingDeviceID: installingDeviceID,
                candidateSavedAt: journal.createdAt
            )
        )
        guard hydration.candidateEnvelope.canonicalBytes
                == journal.candidateEnvelope else {
            throw CloudInitialProfileAssociationCoordinatorError
                .recoveredCandidateMismatch
        }
        try await requireAccount(accountID)
        return try await associationStore.associate(
            journal: journal,
            capability: capability,
            sourceRepository: sourceRepository,
            targetRepository: targetRepository,
            now: now()
        )
    }

    private func requireAccount(_ expected: CloudAccountID) async throws {
        switch await cloud.accountState() {
        case let .available(actual) where actual == expected: return
        case .available:
            throw CloudInitialProfileAssociationCoordinatorError.accountChanged
        case .unknown, .signedOut, .restricted:
            throw CloudInitialProfileAssociationCoordinatorError
                .accountUnavailable
        }
    }

}

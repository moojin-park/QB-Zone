import CryptoKit
import Foundation

/// Exact logical profile-field clocks returned for journaling and later cloud
/// publication. The same counters are embedded in the candidate V4 stamps;
/// this value groups them so a coordinator need not rediscover them.
struct CloudProfileLocalMergeMetadataV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let settingsStamp: CloudProfileMergeStampV1
    let selectionStamp: CloudProfileMergeStampV1

    init(
        schemaVersion: Int = Self.schemaVersion,
        settingsStamp: CloudProfileMergeStampV1,
        selectionStamp: CloudProfileMergeStampV1
    ) {
        self.schemaVersion = schemaVersion
        self.settingsStamp = settingsStamp
        self.selectionStamp = selectionStamp
    }
}

/// A branded source for the pure hydration step. Callers cannot accidentally
/// pass raw CloudKit records: the remote input accepted by `hydrate` is the
/// output type of `CloudProfileReplicaValidator`.
struct CloudProfileHydrationSourceV1: Equatable, Sendable {
    /// Exact bytes currently present in the local primary profile file. A
    /// semantically equivalent re-encode is not sufficient CAS evidence.
    let exactEnvelopeBytes: Data
    let activeSession: ProfileSessionToken
}

struct CloudProfileHydrationContextV1: Equatable, Sendable {
    let cloudAccountID: CloudAccountID
    let derivedBindings: CloudAccountDerivedBindings
    let installingDeviceID: String
    let candidateSavedAt: Date

    init(
        cloudAccountID: CloudAccountID,
        installingDeviceID: String,
        candidateSavedAt: Date
    ) {
        self.cloudAccountID = cloudAccountID
        derivedBindings = CloudAccountDerivedBindings.derive(
            from: cloudAccountID
        )
        self.installingDeviceID = installingDeviceID
        self.candidateSavedAt = candidateSavedAt
    }
}

struct CloudProfileHydrationEnvelopeArtifactV1: Equatable, Sendable {
    let canonicalBytes: Data
    let sha256Digest: Data

    var sha256Hex: String {
        sha256Digest.map { String(format: "%02x", $0) }.joined()
    }
}

struct CloudProfileHydrationRevisionPlanV1: Equatable, Sendable {
    let sourcePlayerRevision: UInt64
    let candidatePlayerRevision: UInt64
    let sourceEconomyRevision: UInt64
    let candidateEconomyRevision: UInt64
    let playerMaterialChanged: Bool
    let economyMaterialChanged: Bool
}

struct CloudProfileHydrationPlanV1: Equatable, Sendable {
    let candidateDocument: LocalPlayerDocumentV1
    let candidateMergeMetadata: CloudProfileLocalMergeMetadataV1
    let revisionPlan: CloudProfileHydrationRevisionPlanV1
    let sourceEnvelope: CloudProfileHydrationEnvelopeArtifactV1
    let candidateEnvelope: CloudProfileHydrationEnvelopeArtifactV1

    var isNoOp: Bool {
        !revisionPlan.playerMaterialChanged
            && !revisionPlan.economyMaterialChanged
    }
}

enum CloudProfileHydrationPartitionV1: String, Equatable, Sendable {
    case player
    case economy
    case selectionStamp
}

enum CloudProfileHydrationError: Error, Equatable, Sendable {
    case malformedSourceEnvelope
    case noncanonicalSourceEnvelope
    case invalidSourceProfile
    case invalidCandidateSavedAt
    case invalidInstallingDeviceID
    case duplicateAchievementDefinition(AchievementID)
    case sourceAccountMigrationRequired(
        expected: PlayerAccountIdentity,
        actual: PlayerAccountIdentity
    )
    case sourceProfileMigrationRequired(expected: UUID, actual: UUID)
    case activeSessionMismatch
    case replicaBindingMismatch
    case invalidValidatedReplica
    case settingsEqualStampDivergence
    case selectionEqualStampDivergence
    case selectionFallbackStampOverflow
    case sourceOwnedTeamMissingFromCloud(TeamID)
    case sourceOwnedJerseyMissingFromCloud(JerseyID)
    case sourceOwnedFootballMissingFromCloud(FootballID)
    case completedRunConflict(RunID)
    case rewardedRunObservationConflict(RunID)
    case ledgerEntryConflict(LedgerEntryID)
    case confirmedLedgerEntryMissingFromCloud(LedgerEntryID)
    case unsupportedPendingLedgerEntry(LedgerEntryID)
    case missingGameplayLedgerEntry(RunID)
    case impossibleSigningBonus
    case impossibleRewardHistory(RunID?)
    case arithmeticOverflow
    case revisionOverflow(CloudProfileHydrationPartitionV1)
    case canonicalEncodingFailed
    case invalidCandidateProfile
}

/// A nontrapping defensive index at the validator/hydrator boundary. The
/// validated replica constructor is sealed, but this remains fail-closed if a
/// future internal refactor ever supplies duplicate embedded ledger IDs.
enum CloudProfileValidatedLedgerIndex {
    static func entries(
        from markers: some Sequence<
            DurableEconomyCoordinator.CloudLedgerMarkerV2
        >
    ) throws -> [LedgerEntryID: CoinLedgerEntry] {
        var result: [LedgerEntryID: CoinLedgerEntry] = [:]
        for marker in markers {
            let entry = marker.record.entry
            guard result.updateValue(entry, forKey: entry.id) == nil else {
                throw CloudProfileHydrationError.invalidValidatedReplica
            }
        }
        return result
    }
}

/// Builds the initial derived-achievement state without relying on a trapping
/// dictionary initializer. Launch catalog validation is a separate boundary;
/// hydration still fails closed if a future catalog source supplies a duplicate
/// persisted achievement identifier.
enum CloudProfileAchievementSeed {
    static func progress(
        definitions: some Sequence<AchievementDefinition>
    ) throws -> [AchievementID: AchievementProgress] {
        var result: [AchievementID: AchievementProgress] = [:]
        for definition in definitions {
            let progress = AchievementProgress(id: definition.id)
            guard result.updateValue(progress, forKey: definition.id) == nil else {
                throw CloudProfileHydrationError
                    .duplicateAchievementDefinition(definition.id)
            }
        }
        return result
    }
}

/// Pure, deterministic merge of one exact local profile and one completely
/// validated private-cloud replica. This type performs no I/O, checkpoint
/// mutation, repository publication, or runtime composition.
struct CloudProfileHydrator: Sendable {
    private let catalog: LaunchCatalog

    init(catalog: LaunchCatalog = .approved) {
        self.catalog = catalog
    }

    func hydrate(
        source: CloudProfileHydrationSourceV1,
        replica: ValidatedCloudProfileReplicaV1,
        context: CloudProfileHydrationContextV1
    ) throws -> CloudProfileHydrationPlanV1 {
        let sourceEnvelope = try decodeCanonicalSource(source.exactEnvelopeBytes)
        let sourceDocument = sourceEnvelope.document
        let metadata = try validateSource(
            source,
            envelope: sourceEnvelope,
            context: context
        )
        let binding = try validateReplica(replica, context: context)

        let sourceArtifact = CloudProfileHydrationEnvelopeArtifactV1(
            canonicalBytes: source.exactEnvelopeBytes,
            sha256Digest: Data(
                SHA256.hash(data: source.exactEnvelopeBytes)
            )
        )
        let mergedSettings = try mergeSettings(
            source: sourceDocument.player.settings,
            localStamp: metadata.settingsStamp,
            remote: replica.settings,
            binding: binding
        )
        let remotelyMergedSelection = try mergeSelection(
            source: sourceDocument.player.selection,
            localStamp: metadata.selectionStamp,
            remote: replica.selection,
            binding: binding
        )

        try requireSourceOwnership(
            sourceDocument.player.inventory,
            remainsIn: replica.inventory
        )

        let mergedRuns = try mergeRuns(
            local: sourceDocument.player.completedRuns,
            remote: replica.completedRunsByID
        )
        let mergedObservations = try mergeRewardObservations(
            local: sourceDocument.rewardedRunObservations ?? [:],
            remote: replica.completedRunsByID,
            mergedRuns: mergedRuns
        )
        var economy = try mergeEconomy(
            source: sourceDocument,
            replica: replica,
            mergedRuns: mergedRuns,
            observations: mergedObservations
        )

        let normalizedSelection = try normalizeSelection(
            remotelyMergedSelection.value,
            inventory: replica.inventory
        )
        var mergedSelectionStamp = remotelyMergedSelection.stamp
        if normalizedSelection != remotelyMergedSelection.value {
            let nextCounter = mergedSelectionStamp.logicalCounter
                .addingReportingOverflow(1)
            guard !nextCounter.overflow else {
                throw CloudProfileHydrationError.selectionFallbackStampOverflow
            }
            do {
                mergedSelectionStamp = try CloudProfileMergeStampV1(
                    logicalCounter: nextCounter.partialValue,
                    deviceID: context.installingDeviceID,
                    modifiedAt: context.candidateSavedAt
                )
            } catch {
                throw CloudProfileHydrationError.invalidInstallingDeviceID
            }
        }

        let derived = try rebuildDerivedPlayerState(
            runs: mergedRuns,
            ledger: economy.ledger,
            pendingLedgerEntryIDs: economy.pendingLedgerEntryIDs,
            observations: mergedObservations,
            rewardResolutionsByRunID: economy.rewardResolutionsByRunID,
            sourceCareer: sourceDocument.player.career,
            sourceAchievements: sourceDocument.player.achievementProgress,
            sourceGameCenter: sourceDocument.player.pendingGameCenter
        )
        economy.rewardedAdState = try makeRewardedAdState(
            replica: replica,
            runs: mergedRuns,
            ledger: economy.ledger,
            pendingLedgerEntryIDs: economy.pendingLedgerEntryIDs,
            observations: mergedObservations,
            rewardResolutionsByRunID: &economy.rewardResolutionsByRunID
        )

        var provisional = sourceDocument
        provisional.player.settings = Stamped(
            value: mergedSettings.value,
            modifiedAt: mergedSettings.stamp.modifiedAt,
            deviceID: mergedSettings.stamp.deviceID,
            logicalCounter: mergedSettings.stamp.logicalCounter
        )
        provisional.player.selection = Stamped(
            value: normalizedSelection,
            modifiedAt: mergedSelectionStamp.modifiedAt,
            deviceID: mergedSelectionStamp.deviceID,
            logicalCounter: mergedSelectionStamp.logicalCounter
        )
        provisional.player.inventory = replica.inventory
        provisional.player.completedRuns = mergedRuns
        provisional.player.ledger = economy.ledger
        provisional.player.career = derived.career
        provisional.player.achievementProgress = derived.achievements
        provisional.player.rewardedAdState = economy.rewardedAdState
        provisional.player.pendingGameCenter = derived.pendingGameCenter
        provisional.pendingLedgerEntryIDs = economy.pendingLedgerEntryIDs
        provisional.settlementReceipts = try rebuildSettlementReceipts(
            runs: mergedRuns,
            ledger: economy.ledger,
            achievements: derived.achievementUpdatesByRunID,
            careerAfterRun: derived.careerAfterRun,
            rewardResolutionsByRunID: economy.rewardResolutionsByRunID
        )
        provisional.rewardedRunObservations = mergedObservations

        let candidateMetadata = CloudProfileLocalMergeMetadataV1(
            settingsStamp: mergedSettings.stamp,
            selectionStamp: mergedSelectionStamp
        )
        let economyChanged = !economyPartition(
            of: provisional,
            equals: sourceDocument
        )
        let playerChanged = provisional != sourceDocument
            || candidateMetadata != metadata
        let materialChanged = playerChanged || economyChanged

        let candidatePlayerRevision: UInt64
        if materialChanged {
            let increment = sourceDocument.player.revision
                .addingReportingOverflow(1)
            guard !increment.overflow else {
                throw CloudProfileHydrationError.revisionOverflow(.player)
            }
            candidatePlayerRevision = increment.partialValue
        } else {
            candidatePlayerRevision = sourceDocument.player.revision
        }

        let candidateEconomyRevision: UInt64
        if materialChanged {
            let increment = sourceDocument.economyRevision
                .addingReportingOverflow(1)
            guard !increment.overflow else {
                throw CloudProfileHydrationError.revisionOverflow(.economy)
            }
            candidateEconomyRevision = increment.partialValue
        } else {
            candidateEconomyRevision = sourceDocument.economyRevision
        }
        provisional.player.revision = candidatePlayerRevision
        provisional.economyRevision = candidateEconomyRevision

        do {
            try PlayerProfileValidator.validate(provisional, catalog: catalog)
        } catch {
            throw CloudProfileHydrationError.invalidCandidateProfile
        }
        let candidateArtifact = try envelopeArtifact(
            document: provisional,
            savedAt: context.candidateSavedAt
        )
        return CloudProfileHydrationPlanV1(
            candidateDocument: provisional,
            candidateMergeMetadata: candidateMetadata,
            revisionPlan: CloudProfileHydrationRevisionPlanV1(
                sourcePlayerRevision: sourceDocument.player.revision,
                candidatePlayerRevision: candidatePlayerRevision,
                sourceEconomyRevision: sourceDocument.economyRevision,
                candidateEconomyRevision: candidateEconomyRevision,
                playerMaterialChanged: playerChanged,
                economyMaterialChanged: economyChanged
            ),
            sourceEnvelope: sourceArtifact,
            candidateEnvelope: candidateArtifact
        )
    }
}

private extension CloudProfileHydrator {
    struct MergedStamped<Value: Equatable & Sendable> {
        let value: Value
        let stamp: CloudProfileMergeStampV1
    }

    struct MergedEconomy {
        var ledger: [LedgerEntryID: CoinLedgerEntry]
        var pendingLedgerEntryIDs: Set<LedgerEntryID>
        var rewardedAdState: RewardedAdState
        var rewardResolutionsByRunID: [
            RunID: DurableEconomyCoordinator.GameplayRewardResolution
        ]
    }

    struct DerivedPlayerState {
        let career: CareerStatistics
        let achievements: [AchievementID: AchievementProgress]
        let pendingGameCenter: PlayerScopedGameCenterQueueV1
        let achievementUpdatesByRunID: [RunID: [AchievementProgressUpdate]]
        let careerAfterRun: [RunID: CareerStatistics]
    }

    func validateSource(
        _ source: CloudProfileHydrationSourceV1,
        envelope: PlayerProfileEnvelopeV4,
        context: CloudProfileHydrationContextV1
    ) throws -> CloudProfileLocalMergeMetadataV1 {
        guard envelope.format == PlayerProfileEnvelopeV4.formatIdentifier,
              envelope.schemaVersion == PlayerProfileEnvelopeV4.schemaVersion,
              envelope.savedAt.timeIntervalSince1970.isFinite
        else {
            throw CloudProfileHydrationError.malformedSourceEnvelope
        }
        guard context.candidateSavedAt.timeIntervalSince1970.isFinite else {
            throw CloudProfileHydrationError.invalidCandidateSavedAt
        }
        do {
            _ = try CloudProfileMergeStampV1(
                logicalCounter: 0,
                deviceID: context.installingDeviceID,
                modifiedAt: context.candidateSavedAt
            )
        } catch {
            throw CloudProfileHydrationError.invalidInstallingDeviceID
        }
        let expectedIdentity = context.derivedBindings.playerAccountIdentity
        let expectedProfileID = context.derivedBindings.durableAccountBinding.profileID
        let document = envelope.document
        guard document.accountIdentity == expectedIdentity else {
            throw CloudProfileHydrationError.sourceAccountMigrationRequired(
                expected: expectedIdentity,
                actual: document.accountIdentity
            )
        }
        guard document.player.profileID == expectedProfileID else {
            throw CloudProfileHydrationError.sourceProfileMigrationRequired(
                expected: expectedProfileID,
                actual: document.player.profileID
            )
        }
        guard source.activeSession.accountIdentity == expectedIdentity,
              source.activeSession.profileID == expectedProfileID
        else {
            throw CloudProfileHydrationError.activeSessionMismatch
        }
        do {
            try PlayerProfileValidator.validate(document, catalog: catalog)
        } catch {
            throw CloudProfileHydrationError.invalidSourceProfile
        }
        do {
            return CloudProfileLocalMergeMetadataV1(
                settingsStamp: try CloudProfileMergeStampV1(
                    logicalCounter: document.player.settings.logicalCounter,
                    deviceID: document.player.settings.deviceID,
                    modifiedAt: document.player.settings.modifiedAt
                ),
                selectionStamp: try CloudProfileMergeStampV1(
                    logicalCounter: document.player.selection.logicalCounter,
                    deviceID: document.player.selection.deviceID,
                    modifiedAt: document.player.selection.modifiedAt
                )
            )
        } catch {
            throw CloudProfileHydrationError.invalidSourceProfile
        }
    }

    func validateReplica(
        _ replica: ValidatedCloudProfileReplicaV1,
        context: CloudProfileHydrationContextV1
    ) throws -> CloudProfileBindingV1 {
        let binding = CloudProfileBindingV1(
            cloudAccountID: context.cloudAccountID,
            accountBinding: context.derivedBindings.durableAccountBinding,
            profileAccountIdentity: context.derivedBindings.playerAccountIdentity
        )
        guard replica.root.binding == binding,
              replica.settings.binding == binding,
              replica.selection.binding == binding,
              replica.economy.head.cloudAccountID == context.cloudAccountID,
              replica.economy.head.accountBinding
                == context.derivedBindings.durableAccountBinding,
              replica.economy.head.profileAccountIdentity
                == context.derivedBindings.playerAccountIdentity,
              replica.completedRunsByID.allSatisfy({
                  $0.key == $0.value.runID && $0.value.binding == binding
              })
        else {
            throw CloudProfileHydrationError.replicaBindingMismatch
        }

        var derivedInventory = InventoryRules.initialInventory(catalog: catalog)
        do {
            let items = try replica.economy.head.unlockedItemIDs.map { itemID in
                guard let item = catalog.item(id: itemID) else {
                    throw CloudProfileHydrationError.invalidValidatedReplica
                }
                return item
            }.sorted { lhs, rhs in
                let left = unlockOrder(lhs.kind)
                let right = unlockOrder(rhs.kind)
                return left == right
                    ? lhs.id.rawValue < rhs.id.rawValue
                    : left < right
            }
            for item in items {
                try InventoryRules.applyUnlock(
                    itemID: item.id,
                    to: &derivedInventory,
                    catalog: catalog
                )
            }
        } catch {
            throw CloudProfileHydrationError.invalidValidatedReplica
        }
        guard derivedInventory == replica.inventory,
              UInt64(replica.economy.ledgerMarkers.count)
                == replica.economy.head.ledgerAccumulator.entryCount
        else {
            throw CloudProfileHydrationError.invalidValidatedReplica
        }

        let confirmed = Set(replica.economy.ledgerMarkers.values.compactMap {
            marker -> RunID? in
            guard case let .gameplay(runID, _) = marker.record.entry.reason
            else { return nil }
            return runID
        })
        let pending = Set(replica.completedRunsByID.values.compactMap {
            payload -> RunID? in
            guard payload.record.rewardCoins > 0,
                  !confirmed.contains(payload.runID)
            else { return nil }
            return payload.runID
        })
        guard confirmed == replica.confirmedGameplayRunIDs,
              pending == replica.pendingGameplayRunIDs
        else {
            throw CloudProfileHydrationError.invalidValidatedReplica
        }

        var confirmedBalance: Int64 = 0
        for marker in replica.economy.ledgerMarkers.values.sorted(by: {
            $0.eventPosition < $1.eventPosition
        }) {
            let result = confirmedBalance.addingReportingOverflow(
                marker.record.entry.delta
            )
            guard !result.overflow, result.partialValue >= 0 else {
                throw CloudProfileHydrationError.invalidValidatedReplica
            }
            confirmedBalance = result.partialValue
        }
        guard confirmedBalance
            == replica.economy.head.ledgerAccumulator.confirmedBalance
        else {
            throw CloudProfileHydrationError.invalidValidatedReplica
        }
        return binding
    }

    func mergeSettings(
        source: Stamped<PlayerSettings>,
        localStamp: CloudProfileMergeStampV1,
        remote: CloudProfileSettingsV1,
        binding: CloudProfileBindingV1
    ) throws -> MergedStamped<PlayerSettings> {
        let local = CloudProfileSettingsV1(
            binding: binding,
            stamp: localStamp,
            settings: source.value
        )
        do {
            let merged = try local.merged(with: remote)
            return MergedStamped(value: merged.settings, stamp: merged.stamp)
        } catch CloudProfileStampedMergeError.equalStampDivergence {
            throw CloudProfileHydrationError.settingsEqualStampDivergence
        } catch {
            throw CloudProfileHydrationError.replicaBindingMismatch
        }
    }

    func mergeSelection(
        source: Stamped<PlayerSelection>,
        localStamp: CloudProfileMergeStampV1,
        remote: CloudProfileSelectionV1,
        binding: CloudProfileBindingV1
    ) throws -> MergedStamped<PlayerSelection> {
        let local = CloudProfileSelectionV1(
            binding: binding,
            stamp: localStamp,
            selection: source.value
        )
        do {
            let merged = try local.merged(with: remote)
            return MergedStamped(value: merged.selection, stamp: merged.stamp)
        } catch CloudProfileStampedMergeError.equalStampDivergence {
            throw CloudProfileHydrationError.selectionEqualStampDivergence
        } catch {
            throw CloudProfileHydrationError.replicaBindingMismatch
        }
    }

    func requireSourceOwnership(
        _ source: PlayerInventory,
        remainsIn remote: PlayerInventory
    ) throws {
        if let missing = source.ownedTeamIDs.subtracting(remote.ownedTeamIDs)
            .sorted(by: { $0.rawValue < $1.rawValue }).first {
            throw CloudProfileHydrationError.sourceOwnedTeamMissingFromCloud(
                missing
            )
        }
        if let missing = source.ownedJerseyIDs.subtracting(remote.ownedJerseyIDs)
            .sorted(by: { $0.rawValue < $1.rawValue }).first {
            throw CloudProfileHydrationError.sourceOwnedJerseyMissingFromCloud(
                missing
            )
        }
        if let missing = source.ownedFootballIDs
            .subtracting(remote.ownedFootballIDs)
            .sorted(by: { $0.rawValue < $1.rawValue }).first {
            throw CloudProfileHydrationError.sourceOwnedFootballMissingFromCloud(
                missing
            )
        }
    }

    func mergeRuns(
        local: [RunID: CompletedRunRecord],
        remote: [RunID: CloudProfileCompletedRunV1]
    ) throws -> [RunID: CompletedRunRecord] {
        var result = local
        for (runID, payload) in remote.sorted(by: {
            $0.key.description < $1.key.description
        }) {
            if let existing = result[runID], existing != payload.record {
                throw CloudProfileHydrationError.completedRunConflict(runID)
            }
            result[runID] = payload.record
        }
        return result
    }

    func mergeRewardObservations(
        local: [RunID: RewardedRunObservation],
        remote: [RunID: CloudProfileCompletedRunV1],
        mergedRuns: [RunID: CompletedRunRecord]
    ) throws -> [RunID: RewardedRunObservation] {
        var result = local
        for (runID, payload) in remote.sorted(by: {
            $0.key.description < $1.key.description
        }) {
            if let remoteObservation = payload.rewardedRunObservation {
                if let existing = result[runID], existing != remoteObservation {
                    throw CloudProfileHydrationError
                        .rewardedRunObservationConflict(runID)
                }
                result[runID] = remoteObservation
            } else if result[runID] != nil {
                throw CloudProfileHydrationError
                    .rewardedRunObservationConflict(runID)
            }
        }
        let eligible = Set(mergedRuns.values.compactMap {
            CompletedRunValidator.isRewardEligible($0.run)
                ? $0.run.runID
                : nil
        })
        guard Set(result.keys) == eligible else {
            let runID = eligible.symmetricDifference(Set(result.keys))
                .sorted(by: { $0.description < $1.description }).first
            throw CloudProfileHydrationError.impossibleRewardHistory(runID)
        }
        return result
    }

    func mergeEconomy(
        source: LocalPlayerDocumentV1,
        replica: ValidatedCloudProfileReplicaV1,
        mergedRuns: [RunID: CompletedRunRecord],
        observations: [RunID: RewardedRunObservation]
    ) throws -> MergedEconomy {
        let remoteLedger = try CloudProfileValidatedLedgerIndex.entries(
            from: replica.economy.ledgerMarkers.values
        )
        var ledger = remoteLedger
        var pending = Set<LedgerEntryID>()

        for (entryID, entry) in source.player.ledger.sorted(by: {
            $0.key.rawValue < $1.key.rawValue
        }) {
            if let remoteEntry = remoteLedger[entryID] {
                guard remoteEntry == entry else {
                    throw CloudProfileHydrationError.ledgerEntryConflict(entryID)
                }
                continue
            }
            guard source.pendingLedgerEntryIDs.contains(entryID) else {
                throw CloudProfileHydrationError
                    .confirmedLedgerEntryMissingFromCloud(entryID)
            }
            switch entry.reason {
            case .gameplay, .signingBonus:
                ledger[entryID] = entry
                pending.insert(entryID)
            case .rewardedAd, .storeKit, .catalogUnlock:
                throw CloudProfileHydrationError
                    .unsupportedPendingLedgerEntry(entryID)
            }
        }

        for runID in replica.pendingGameplayRunIDs.sorted(by: {
            $0.description < $1.description
        }) {
            guard let record = mergedRuns[runID], record.rewardCoins > 0 else {
                throw CloudProfileHydrationError.invalidValidatedReplica
            }
            let entryID = CoinLedgerID.gameplay(runID: runID)
            let expected = CoinLedgerEntry(
                id: entryID,
                delta: record.rewardCoins,
                reason: .gameplay(
                    runID: runID,
                    economyVersion: record.run.configuration.economyVersion
                ),
                createdAt: record.recordedAt
            )
            if let existing = ledger[entryID], existing != expected {
                throw CloudProfileHydrationError.ledgerEntryConflict(entryID)
            }
            ledger[entryID] = expected
            pending.insert(entryID)
        }

        for (runID, record) in mergedRuns.sorted(by: {
            $0.key.description < $1.key.description
        }) {
            let entryID = CoinLedgerID.gameplay(runID: runID)
            if record.rewardCoins > 0 {
                guard let entry = ledger[entryID],
                      entry.delta == record.rewardCoins,
                      entry.createdAt == record.recordedAt,
                      case let .gameplay(entryRunID, economyVersion)
                        = entry.reason,
                      entryRunID == runID,
                      economyVersion
                        == record.run.configuration.economyVersion,
                      observations[runID] != nil
                else {
                    throw CloudProfileHydrationError
                        .missingGameplayLedgerEntry(runID)
                }
            } else if ledger[entryID] != nil {
                throw CloudProfileHydrationError.ledgerEntryConflict(entryID)
            }
        }

        let eligibleRuns = mergedRuns.values.filter {
            CompletedRunValidator.isRewardEligible($0.run)
        }
        let signingID = CoinLedgerID.signingBonus(
            version: PersistedEconomyRulesV1.signingBonusVersion
        )
        let signingEntries = ledger.values.filter {
            if case .signingBonus = $0.reason { return true }
            return false
        }
        guard signingEntries.count <= 1 else {
            throw CloudProfileHydrationError.impossibleSigningBonus
        }
        if eligibleRuns.isEmpty {
            guard signingEntries.isEmpty else {
                throw CloudProfileHydrationError.impossibleSigningBonus
            }
        } else if signingEntries.isEmpty {
            ledger[signingID] = CoinLedgerEntry(
                id: signingID,
                delta: PersistedEconomyRulesV1.signingBonusCoins,
                reason: .signingBonus(
                    version: PersistedEconomyRulesV1.signingBonusVersion
                ),
                createdAt: PersistedEconomyRulesV1
                    .signingBonusLedgerCreatedAt
            )
            pending.insert(signingID)
        } else {
            guard let signing = signingEntries.first,
                  signing.id == signingID,
                  signing.delta == PersistedEconomyRulesV1.signingBonusCoins,
                  signing.createdAt
                    == PersistedEconomyRulesV1.signingBonusLedgerCreatedAt,
                  case .signingBonus(
                    PersistedEconomyRulesV1.signingBonusVersion
                  ) = signing.reason
            else {
                throw CloudProfileHydrationError.impossibleSigningBonus
            }
        }

        var pendingTotal: Int64 = 0
        for entryID in pending.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let entry = ledger[entryID], entry.delta > 0 else {
                throw CloudProfileHydrationError
                    .unsupportedPendingLedgerEntry(entryID)
            }
            let addition = pendingTotal.addingReportingOverflow(entry.delta)
            guard !addition.overflow else {
                throw CloudProfileHydrationError.arithmeticOverflow
            }
            pendingTotal = addition.partialValue
        }
        let total = replica.economy.head.ledgerAccumulator.confirmedBalance
            .addingReportingOverflow(pendingTotal)
        guard !total.overflow, total.partialValue >= 0 else {
            throw CloudProfileHydrationError.arithmeticOverflow
        }

        var resolutions: [
            RunID: DurableEconomyCoordinator.GameplayRewardResolution
        ] = [:]
        for marker in replica.economy.ledgerMarkers.values {
            guard case let .gameplay(runID, _) = marker.record.entry.reason,
                  let resolution = marker.gameplayRewardResolution
            else { continue }
            resolutions[runID] = resolution
        }
        return MergedEconomy(
            ledger: ledger,
            pendingLedgerEntryIDs: pending,
            rewardedAdState: RewardedAdState(),
            rewardResolutionsByRunID: resolutions
        )
    }

    func makeRewardedAdState(
        replica: ValidatedCloudProfileReplicaV1,
        runs: [RunID: CompletedRunRecord],
        ledger: [LedgerEntryID: CoinLedgerEntry],
        pendingLedgerEntryIDs: Set<LedgerEntryID>,
        observations: [RunID: RewardedRunObservation],
        rewardResolutionsByRunID: inout [
            RunID: DurableEconomyCoordinator.GameplayRewardResolution
        ]
    ) throws -> RewardedAdState {
        var head = replica.economy.head.rewardedAd
        for entryID in pendingLedgerEntryIDs.sorted(by: {
            $0.rawValue < $1.rawValue
        }) {
            guard let entry = ledger[entryID],
                  case let .gameplay(runID, _) = entry.reason
            else { continue }
            guard let observation = observations[runID] else {
                throw CloudProfileHydrationError.impossibleRewardHistory(runID)
            }
            do {
                rewardResolutionsByRunID[runID] = try head.resolveGameplay(
                    observation: observation
                )
            } catch {
                throw CloudProfileHydrationError.impossibleRewardHistory(runID)
            }
        }
        let accounted = Set(runs.values.compactMap {
            CompletedRunValidator.isRewardEligible($0.run)
                ? $0.run.runID
                : nil
        })
        return RewardedAdState(
            cycle: head.cycle,
            validRunsSinceReward: head.validRunsSinceReward,
            eligibleOfferID: head.eligibleOfferID,
            accountedRunIDs: accounted
        )
    }

    func rebuildDerivedPlayerState(
        runs: [RunID: CompletedRunRecord],
        ledger _: [LedgerEntryID: CoinLedgerEntry],
        pendingLedgerEntryIDs _: Set<LedgerEntryID>,
        observations _: [RunID: RewardedRunObservation],
        rewardResolutionsByRunID _: [
            RunID: DurableEconomyCoordinator.GameplayRewardResolution
        ],
        sourceCareer: CareerStatistics,
        sourceAchievements: [AchievementID: AchievementProgress],
        sourceGameCenter: PlayerScopedGameCenterQueueV1
    ) throws -> DerivedPlayerState {
        var career = CareerStatistics()
        var achievements = try CloudProfileAchievementSeed.progress(
            definitions: AchievementCatalog.launch
        )
        var updatesByRun: [RunID: [AchievementProgressUpdate]] = [:]
        var careerAfterRun: [RunID: CareerStatistics] = [:]

        for record in orderedRuns(runs) {
            career = try PersistedCareerAccumulatorV1.applying(
                record.run,
                to: career
            )
            let updates = AchievementEvaluator.evaluate(
                run: record.run,
                careerAfter: career,
                existing: achievements,
                evaluatedAt: record.recordedAt
            )
            for update in updates {
                achievements[update.current.id] = update.current
            }
            updatesByRun[record.run.runID] = updates
            careerAfterRun[record.run.runID] = career
        }

        var queue = sourceGameCenter
        if career.highestScore > sourceCareer.highestScore {
            queue.enqueueUnboundHighScore(career.highestScore)
        }
        for progress in achievements.values.sorted(by: {
            $0.id.rawValue < $1.id.rawValue
        }) where progress.percentComplete
            > (sourceAchievements[progress.id]?.percentComplete ?? 0) {
            // Cloud runs do not carry Game Center player provenance. Only the
            // increase over the already-derived source state is quarantined;
            // a true hydration no-op does not recreate delivered work.
            queue.enqueueUnboundAchievement(progress)
        }
        return DerivedPlayerState(
            career: career,
            achievements: achievements,
            pendingGameCenter: queue,
            achievementUpdatesByRunID: updatesByRun,
            careerAfterRun: careerAfterRun
        )
    }

    func rebuildSettlementReceipts(
        runs: [RunID: CompletedRunRecord],
        ledger: [LedgerEntryID: CoinLedgerEntry],
        achievements: [RunID: [AchievementProgressUpdate]],
        careerAfterRun: [RunID: CareerStatistics],
        rewardResolutionsByRunID: [
            RunID: DurableEconomyCoordinator.GameplayRewardResolution
        ]
    ) throws -> [RunID: RunSettlementOutcome] {
        let signingID = CoinLedgerID.signingBonus(
            version: PersistedEconomyRulesV1.signingBonusVersion
        )
        let signingRunID: RunID? = ledger[signingID] == nil
            ? nil
            : orderedRuns(runs).first(where: {
                CompletedRunValidator.isRewardEligible($0.run)
            })?.run.runID

        var receipts: [RunID: RunSettlementOutcome] = [:]
        for record in orderedRuns(runs) {
            let runID = record.run.runID
            let gameplayID = record.rewardCoins > 0
                ? CoinLedgerID.gameplay(runID: runID)
                : nil
            let unlockedOffer: RewardOfferID?
            if case let .counted(_, _, offerID)?
                = rewardResolutionsByRunID[runID] {
                unlockedOffer = offerID
            } else {
                unlockedOffer = nil
            }
            guard let career = careerAfterRun[runID] else {
                throw CloudProfileHydrationError.invalidCandidateProfile
            }
            receipts[runID] = RunSettlementOutcome(
                record: record,
                gameplayRewardEntryID: gameplayID,
                signingBonusEntryID: signingRunID == runID ? signingID : nil,
                achievementUpdates: achievements[runID] ?? [],
                rewardedOfferUnlocked: unlockedOffer,
                resultingPersonalBest: career.highestScore
            )
        }
        return receipts
    }

    func normalizeSelection(
        _ selection: PlayerSelection,
        inventory: PlayerInventory
    ) throws -> PlayerSelection {
        var normalized = selection
        let knownTeamIDs = Set(catalog.teams.map(\.id))
        normalized.selectedJerseyByTeam = normalized.selectedJerseyByTeam
            .filter { teamID, jerseyID in
                guard knownTeamIDs.contains(teamID),
                      let jersey = catalog.jersey(id: jerseyID)
                else { return false }
                return jersey.teamID == teamID
            }

        for team in catalog.teams.sorted(by: {
            $0.id.rawValue < $1.id.rawValue
        }) {
            if inventory.ownedTeamIDs.contains(team.id) {
                let remembered = normalized.selectedJerseyByTeam[team.id]
                if remembered == nil
                    || !inventory.ownedJerseyIDs.contains(remembered!)
                    || catalog.jersey(id: remembered!)?.teamID != team.id
                {
                    normalized.selectedJerseyByTeam[team.id]
                        = team.primaryJersey.id
                }
            } else if normalized.selectedJerseyByTeam[team.id] == nil {
                normalized.selectedJerseyByTeam[team.id]
                    = team.primaryJersey.id
            }
        }

        if !inventory.ownedTeamIDs.contains(normalized.selectedTeamID)
            || catalog.team(id: normalized.selectedTeamID) == nil
        {
            let preferred = InventoryRules.initialSelection(catalog: catalog)
                .selectedTeamID
            normalized.selectedTeamID = inventory.ownedTeamIDs.contains(preferred)
                ? preferred
                : inventory.ownedTeamIDs.sorted(by: {
                    $0.rawValue < $1.rawValue
                }).first ?? preferred
        }
        if !inventory.ownedFootballIDs.contains(normalized.selectedFootballID)
            || catalog.football(id: normalized.selectedFootballID) == nil
        {
            let preferred = InventoryRules.initialSelection(catalog: catalog)
                .selectedFootballID
            normalized.selectedFootballID = inventory.ownedFootballIDs
                .contains(preferred)
                ? preferred
                : inventory.ownedFootballIDs.sorted(by: {
                    $0.rawValue < $1.rawValue
                }).first ?? preferred
        }
        do {
            try InventoryRules.validate(
                selection: normalized,
                inventory: inventory,
                catalog: catalog
            )
        } catch {
            throw CloudProfileHydrationError.invalidValidatedReplica
        }
        return normalized
    }

    func economyPartition(
        of left: LocalPlayerDocumentV1,
        equals right: LocalPlayerDocumentV1
    ) -> Bool {
        left.player.inventory == right.player.inventory
            && left.player.ledger == right.player.ledger
            && left.player.rewardedAdState == right.player.rewardedAdState
            && left.pendingLedgerEntryIDs == right.pendingLedgerEntryIDs
            && left.rewardedRunObservations == right.rewardedRunObservations
    }

    func orderedRuns(
        _ runs: [RunID: CompletedRunRecord]
    ) -> [CompletedRunRecord] {
        runs.values.sorted { lhs, rhs in
            if lhs.recordedAt != rhs.recordedAt {
                return lhs.recordedAt < rhs.recordedAt
            }
            return lhs.run.runID.description < rhs.run.runID.description
        }
    }

    func unlockOrder(_ kind: CatalogItemKind) -> Int {
        switch kind {
        case .team: return 0
        case .alternateJersey: return 1
        case .football: return 2
        }
    }

    func envelopeArtifact(
        document: LocalPlayerDocumentV1,
        savedAt: Date
    ) throws -> CloudProfileHydrationEnvelopeArtifactV1 {
        let bytes: Data
        do {
            bytes = try PlayerProfileMigrator().encode(
                document,
                savedAt: savedAt
            )
        } catch {
            throw CloudProfileHydrationError.canonicalEncodingFailed
        }
        return CloudProfileHydrationEnvelopeArtifactV1(
            canonicalBytes: bytes,
            sha256Digest: Data(SHA256.hash(data: bytes))
        )
    }

    func decodeCanonicalSource(
        _ bytes: Data
    ) throws -> PlayerProfileEnvelopeV4 {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let envelope: PlayerProfileEnvelopeV4
        do {
            envelope = try decoder.decode(PlayerProfileEnvelopeV4.self, from: bytes)
        } catch {
            throw CloudProfileHydrationError.malformedSourceEnvelope
        }
        let canonical: Data
        do {
            canonical = try PlayerProfileMigrator().encode(
                envelope.document,
                savedAt: envelope.savedAt
            )
        } catch {
            throw CloudProfileHydrationError.malformedSourceEnvelope
        }
        guard canonical == bytes else {
            throw CloudProfileHydrationError.noncanonicalSourceEnvelope
        }
        return envelope
    }
}

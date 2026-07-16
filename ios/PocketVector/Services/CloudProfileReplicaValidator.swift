import CryptoKit
import Foundation

struct CloudProfileEconomyHistoryV1: Equatable, Sendable {
    let head: DurableEconomyCoordinator.CloudAccountHeadV3
    let ledgerMarkers: [
        LedgerEntryID: DurableEconomyCoordinator.CloudLedgerMarkerV2
    ]
    let rewardOfferMarkers: [
        RewardOfferID: DurableEconomyCoordinator.CloudRewardOfferMarkerV2
    ]
}

/// Narrow adapter around the durable economy's single authoritative complete-
/// history verifier. Tests can inject a fail-closed fake without recreating
/// economy replay rules; production binds this closure to the active actor.
struct CloudProfileCompleteEconomyHistoryVerifier: Sendable {
    typealias Body = @Sendable (
        CloudProfileEconomyHistoryV1
    ) async throws -> DurableEconomyCoordinator.CloudAccountHeadV3

    private let body: Body

    init(_ body: @escaping Body) {
        self.body = body
    }

    init(coordinator: DurableEconomyCoordinator) {
        body = { history in
            try await coordinator.verifyCompleteCloudHistory(
                head: history.head,
                ledgerMarkers: history.ledgerMarkers,
                rewardOfferMarkers: history.rewardOfferMarkers
            )
        }
    }

    func verify(
        _ history: CloudProfileEconomyHistoryV1
    ) async throws -> DurableEconomyCoordinator.CloudAccountHeadV3 {
        try await body(history)
    }
}

struct ValidatedCloudProfileReplicaV1: Equatable, Sendable {
    let root: CloudProfileRootV1
    let settings: CloudProfileSettingsV1
    let selection: CloudProfileSelectionV1
    let completedRunsByID: [RunID: CloudProfileCompletedRunV1]
    let economy: CloudProfileEconomyHistoryV1
    let inventory: PlayerInventory
    let confirmedGameplayRunIDs: Set<RunID>
    let pendingGameplayRunIDs: Set<RunID>

    fileprivate init(
        root: CloudProfileRootV1,
        settings: CloudProfileSettingsV1,
        selection: CloudProfileSelectionV1,
        completedRunsByID: [RunID: CloudProfileCompletedRunV1],
        economy: CloudProfileEconomyHistoryV1,
        inventory: PlayerInventory,
        confirmedGameplayRunIDs: Set<RunID>,
        pendingGameplayRunIDs: Set<RunID>
    ) {
        self.root = root
        self.settings = settings
        self.selection = selection
        self.completedRunsByID = completedRunsByID
        self.economy = economy
        self.inventory = inventory
        self.confirmedGameplayRunIDs = confirmedGameplayRunIDs
        self.pendingGameplayRunIDs = pendingGameplayRunIDs
    }
}

enum CloudProfileReplicaStateV1: Equatable, Sendable {
    /// A complete checkpoint with no records and no tombstones. Only this state
    /// may enter the separate first-write bootstrap transaction.
    case uninitialized
    case initialized(ValidatedCloudProfileReplicaV1)
}

enum CloudProfileReplicaValidatorConfigurationError: Error, Equatable, Sendable {
    case expectedBindingAccountMismatch
    case economyRecordIDCollision(CloudRecordID)
    case economyRecordTypeCollision(String)
}

enum CloudProfileReplicaValidationError: Error, Equatable, Sendable {
    case invalidCheckpoint
    case accountMismatch
    case scopeMismatch
    case tombstonePresent(CloudProviderRecordLocator)
    case unexpectedRecordFields(CloudRecordID)
    case recordTypeMismatch(CloudRecordID)
    case unknownRecordType(String)
    case wrongDeterministicRecordID(
        expected: CloudRecordID,
        actual: CloudRecordID
    )
    case malformedPayload(CloudRecordID)
    case schemaVersionMismatch(CloudRecordID)
    case bindingMismatch(CloudRecordID)
    case missingProfileRoot
    case missingSettings
    case missingSelection
    case missingEconomyHead
    case duplicateRunID(RunID)
    case duplicateLedgerMarker(LedgerEntryID)
    case duplicateRewardOfferMarker(RewardOfferID)
    case economyHeadRecordIDMismatch
    case rootRevisionInconsistent
    case runAccumulatorMismatch
    case invalidSettings
    case invalidSelection
    case invalidEconomyInventory
    case invalidCompletedRun(RunID)
    case runRewardMismatch(RunID)
    case missingRewardedRunObservation(RunID)
    case extraRewardedRunObservation(RunID)
    case invalidRewardedRunObservation(RunID)
    case economyVerifierReturnedDifferentHead
    case gameplayMarkerWithoutRun(RunID)
    case gameplayMarkerMismatch(RunID)
    case unknownEconomyPayload(CloudRecordID)
}

struct CloudProfileReplicaValidator: Sendable {
    private let configuration: CloudProfileSchemaConfiguration
    private let economyConfiguration: DurableEconomyCloudConfiguration
    private let expectedAccountID: CloudAccountID
    private let expectedScopeFingerprint: CloudReplicaScopeFingerprint
    private let expectedBinding: CloudProfileBindingV1
    private let economyVerifier: CloudProfileCompleteEconomyHistoryVerifier
    private let catalog: LaunchCatalog

    init(
        configuration: CloudProfileSchemaConfiguration,
        economyConfiguration: DurableEconomyCloudConfiguration,
        expectedAccountID: CloudAccountID,
        expectedScopeFingerprint: CloudReplicaScopeFingerprint,
        expectedBinding: CloudProfileBindingV1,
        economyVerifier: CloudProfileCompleteEconomyHistoryVerifier,
        catalog: LaunchCatalog = .approved
    ) throws {
        guard expectedBinding.cloudAccountID == expectedAccountID else {
            throw CloudProfileReplicaValidatorConfigurationError
                .expectedBindingAccountMismatch
        }
        let profileSingletonRecordIDs: Set<CloudRecordID> = [
            configuration.rootRecordID,
            configuration.settingsRecordID,
            configuration.selectionRecordID,
        ]
        guard !profileSingletonRecordIDs.contains(economyConfiguration.recordID)
        else {
            throw CloudProfileReplicaValidatorConfigurationError
                .economyRecordIDCollision(economyConfiguration.recordID)
        }
        let profileTypes = Set([
            configuration.rootRecordType,
            configuration.settingsRecordType,
            configuration.selectionRecordType,
            configuration.runRecordType,
        ])
        guard !profileTypes.contains(economyConfiguration.recordType) else {
            throw CloudProfileReplicaValidatorConfigurationError
                .economyRecordTypeCollision(economyConfiguration.recordType)
        }

        self.configuration = configuration
        self.economyConfiguration = economyConfiguration
        self.expectedAccountID = expectedAccountID
        self.expectedScopeFingerprint = expectedScopeFingerprint
        self.expectedBinding = expectedBinding
        self.economyVerifier = economyVerifier
        self.catalog = catalog
    }

    func validate(
        _ checkpoint: CloudReplicaCheckpointV1
    ) async throws -> CloudProfileReplicaStateV1 {
        do {
            try checkpoint.validate()
        } catch {
            throw CloudProfileReplicaValidationError.invalidCheckpoint
        }
        guard checkpoint.accountID == expectedAccountID else {
            throw CloudProfileReplicaValidationError.accountMismatch
        }
        guard checkpoint.configurationScopeFingerprint
            == expectedScopeFingerprint
        else {
            throw CloudProfileReplicaValidationError.scopeMismatch
        }
        if let tombstone = checkpoint.tombstonesByProviderLocator.values
            .sorted(by: { $0.locator.rawValue < $1.locator.rawValue })
            .first
        {
            throw CloudProfileReplicaValidationError.tombstonePresent(
                tombstone.locator
            )
        }
        if checkpoint.recordsByLogicalID.isEmpty {
            return .uninitialized
        }

        var root: CloudProfileRootV1?
        var settings: CloudProfileSettingsV1?
        var selection: CloudProfileSelectionV1?
        var economyHead: DurableEconomyCoordinator.CloudAccountHeadV3?
        var runsByID: [RunID: CloudProfileCompletedRunV1] = [:]
        var runAccumulatorEntriesByID: [
            RunID: CloudProfileRunAccumulatorEntryV1
        ] = [:]
        var ledgerMarkers: [
            LedgerEntryID: DurableEconomyCoordinator.CloudLedgerMarkerV2
        ] = [:]
        var offerMarkers: [
            RewardOfferID: DurableEconomyCoordinator.CloudRewardOfferMarkerV2
        ] = [:]

        for record in checkpoint.recordsByLogicalID.values.sorted(by: {
            $0.id.rawValue < $1.id.rawValue
        }) {
            if record.id == configuration.rootRecordID {
                try requireRecord(
                    record,
                    type: configuration.rootRecordType,
                    payloadField: configuration.payloadFieldName
                )
                root = try decode(
                    CloudProfileRootV1.self,
                    from: record,
                    field: configuration.payloadFieldName,
                    requiredKeys: Self.rootPayloadKeys,
                    allowedKeys: Self.rootPayloadKeys,
                    requireCanonicalPayload: true
                )
                continue
            }
            if record.id == configuration.settingsRecordID {
                try requireRecord(
                    record,
                    type: configuration.settingsRecordType,
                    payloadField: configuration.payloadFieldName
                )
                settings = try decode(
                    CloudProfileSettingsV1.self,
                    from: record,
                    field: configuration.payloadFieldName,
                    requiredKeys: Self.settingsPayloadKeys,
                    allowedKeys: Self.settingsPayloadKeys,
                    requireCanonicalPayload: true
                )
                continue
            }
            if record.id == configuration.selectionRecordID {
                try requireRecord(
                    record,
                    type: configuration.selectionRecordType,
                    payloadField: configuration.payloadFieldName
                )
                selection = try decode(
                    CloudProfileSelectionV1.self,
                    from: record,
                    field: configuration.payloadFieldName,
                    requiredKeys: Self.selectionPayloadKeys,
                    allowedKeys: Self.selectionPayloadKeys,
                    requireCanonicalPayload: true
                )
                continue
            }
            if record.id == economyConfiguration.recordID {
                try requireRecord(
                    record,
                    type: economyConfiguration.recordType,
                    payloadField: economyConfiguration.payloadFieldName
                )
                economyHead = try decode(
                    DurableEconomyCoordinator.CloudAccountHeadV3.self,
                    from: record,
                    field: economyConfiguration.payloadFieldName,
                    requiredKeys: Self.economyHeadPayloadKeys,
                    allowedKeys: Self.economyHeadPayloadKeys
                )
                continue
            }

            switch record.recordType {
            case configuration.rootRecordType:
                throw wrongID(
                    expected: configuration.rootRecordID,
                    actual: record.id
                )
            case configuration.settingsRecordType:
                throw wrongID(
                    expected: configuration.settingsRecordID,
                    actual: record.id
                )
            case configuration.selectionRecordType:
                throw wrongID(
                    expected: configuration.selectionRecordID,
                    actual: record.id
                )
            case configuration.runRecordType:
                try requireRecord(
                    record,
                    type: configuration.runRecordType,
                    payloadField: configuration.payloadFieldName
                )
                let run = try decode(
                    CloudProfileCompletedRunV1.self,
                    from: record,
                    field: configuration.payloadFieldName,
                    requiredKeys: Self.runRequiredPayloadKeys,
                    allowedKeys: Self.runAllowedPayloadKeys,
                    requireCanonicalPayload: true
                )
                guard runsByID[run.runID] == nil else {
                    throw CloudProfileReplicaValidationError.duplicateRunID(
                        run.runID
                    )
                }
                let expectedID = configuration.runRecordID(for: run.runID)
                guard record.id == expectedID else {
                    throw wrongID(expected: expectedID, actual: record.id)
                }
                runsByID[run.runID] = run
                runAccumulatorEntriesByID[run.runID] =
                    CloudProfileRunAccumulatorEntryV1(
                        logicalRecordID: record.id,
                        canonicalPayload: record.fields[
                            configuration.payloadFieldName
                        ]!
                    )

            case economyConfiguration.recordType:
                try requireFields(
                    record,
                    payloadField: economyConfiguration.payloadFieldName
                )
                try decodeEconomyMarker(
                    record,
                    ledgerMarkers: &ledgerMarkers,
                    offerMarkers: &offerMarkers
                )

            default:
                throw CloudProfileReplicaValidationError.unknownRecordType(
                    record.recordType
                )
            }
        }

        guard let root else {
            throw CloudProfileReplicaValidationError.missingProfileRoot
        }
        guard let settings else {
            throw CloudProfileReplicaValidationError.missingSettings
        }
        guard let selection else {
            throw CloudProfileReplicaValidationError.missingSelection
        }
        guard let economyHead else {
            throw CloudProfileReplicaValidationError.missingEconomyHead
        }

        try validateSchemasAndBindings(
            root: root,
            settings: settings,
            selection: selection,
            runsByID: runsByID,
            economyHead: economyHead,
            ledgerMarkers: ledgerMarkers,
            offerMarkers: offerMarkers
        )

        guard root.rootRevision > 0,
              root.rootRevision >= root.runAccumulator.runCount,
              root.rootRevision >= settings.stamp.logicalCounter,
              root.rootRevision >= selection.stamp.logicalCounter
        else {
            throw CloudProfileReplicaValidationError.rootRevisionInconsistent
        }
        let calculatedAccumulator = try CloudProfileRunAccumulatorV1.make(
            for: runAccumulatorEntriesByID.values
        )
        guard calculatedAccumulator == root.runAccumulator else {
            throw CloudProfileReplicaValidationError.runAccumulatorMismatch
        }

        let economy = CloudProfileEconomyHistoryV1(
            head: economyHead,
            ledgerMarkers: ledgerMarkers,
            rewardOfferMarkers: offerMarkers
        )
        let verifiedHead = try await economyVerifier.verify(economy)
        guard verifiedHead == economyHead else {
            throw CloudProfileReplicaValidationError
                .economyVerifierReturnedDifferentHead
        }

        let inventory = try deriveInventory(from: verifiedHead.unlockedItemIDs)
        try validate(settings: settings.settings)
        do {
            try InventoryRules.validate(
                selection: selection.selection,
                inventory: inventory,
                catalog: catalog
            )
        } catch {
            throw CloudProfileReplicaValidationError.invalidSelection
        }

        for run in runsByID.values {
            try validate(
                run: run,
                inventory: inventory,
                rewardedAdHead: verifiedHead.rewardedAd
            )
        }

        var confirmedGameplayRunIDs = Set<RunID>()
        for marker in ledgerMarkers.values {
            guard case let .gameplay(runID, economyVersion)
                = marker.record.entry.reason
            else {
                continue
            }
            guard let run = runsByID[runID] else {
                throw CloudProfileReplicaValidationError
                    .gameplayMarkerWithoutRun(runID)
            }
            let entry = marker.record.entry
            guard run.record.run.configuration.economyVersion == economyVersion,
                  entry.id == CoinLedgerID.gameplay(runID: runID),
                  entry.delta == run.record.rewardCoins,
                  entry.createdAt == run.record.recordedAt,
                  marker.gameplayRewardObservation
                    == run.rewardedRunObservation
            else {
                throw CloudProfileReplicaValidationError.gameplayMarkerMismatch(
                    runID
                )
            }
            confirmedGameplayRunIDs.insert(runID)
        }

        let pendingGameplayRunIDs = Set<RunID>(
            runsByID.values.compactMap { run in
                guard run.record.rewardCoins > 0,
                      !confirmedGameplayRunIDs.contains(run.runID)
                else {
                    return nil
                }
                return run.runID
            }
        )
        return .initialized(
            ValidatedCloudProfileReplicaV1(
                root: root,
                settings: settings,
                selection: selection,
                completedRunsByID: runsByID,
                economy: economy,
                inventory: inventory,
                confirmedGameplayRunIDs: confirmedGameplayRunIDs,
                pendingGameplayRunIDs: pendingGameplayRunIDs
            )
        )
    }
}

private extension CloudProfileReplicaValidator {
    static let rootPayloadKeys: Set<String> = [
        "schemaVersion", "binding", "economyHeadRecordID", "rootRevision",
        "runAccumulator",
    ]
    static let settingsPayloadKeys: Set<String> = [
        "schemaVersion", "binding", "stamp", "settings",
    ]
    static let selectionPayloadKeys: Set<String> = [
        "schemaVersion", "binding", "stamp", "selection",
    ]
    static let runRequiredPayloadKeys: Set<String> = [
        "schemaVersion", "binding", "record",
    ]
    static let runAllowedPayloadKeys = runRequiredPayloadKeys.union([
        "rewardedRunObservation",
    ])
    static let economyHeadPayloadKeys: Set<String> = [
        "schemaVersion", "cloudAccountID", "accountBinding",
        "profileAccountIdentity", "revision", "ledgerAccumulator",
        "unlockedItemIDs", "rewardedAd",
    ]
    static let ledgerMarkerRequiredPayloadKeys: Set<String> = [
        "schemaVersion", "headRecordID", "record", "eventPosition",
    ]
    static let ledgerMarkerAllowedPayloadKeys =
        ledgerMarkerRequiredPayloadKeys.union([
            "gameplayRewardObservation", "gameplayRewardResolution",
        ])
    static let offerMarkerPayloadKeys: Set<String> = [
        "schemaVersion", "headRecordID", "redemption", "binding",
        "eventPosition",
    ]

    func requireRecord(
        _ record: CloudRecord,
        type: String,
        payloadField: String
    ) throws {
        guard record.recordType == type else {
            throw CloudProfileReplicaValidationError.recordTypeMismatch(
                record.id
            )
        }
        try requireFields(record, payloadField: payloadField)
    }

    func requireFields(
        _ record: CloudRecord,
        payloadField: String
    ) throws {
        guard Set(record.fields.keys) == [payloadField] else {
            throw CloudProfileReplicaValidationError.unexpectedRecordFields(
                record.id
            )
        }
    }

    func decode<T: Codable>(
        _ type: T.Type,
        from record: CloudRecord,
        field: String,
        requiredKeys: Set<String>,
        allowedKeys: Set<String>,
        requireCanonicalPayload: Bool = false
    ) throws -> T {
        guard let payload = record.fields[field] else {
            throw CloudProfileReplicaValidationError.malformedPayload(record.id)
        }
        let keys: Set<String>
        do {
            guard let object = try JSONSerialization.jsonObject(with: payload)
                as? [String: Any]
            else {
                throw CloudProfileReplicaValidationError.malformedPayload(
                    record.id
                )
            }
            keys = Set(object.keys)
        } catch let error as CloudProfileReplicaValidationError {
            throw error
        } catch {
            throw CloudProfileReplicaValidationError.malformedPayload(record.id)
        }
        guard keys.isSuperset(of: requiredKeys),
              keys.isSubset(of: allowedKeys)
        else {
            throw CloudProfileReplicaValidationError.malformedPayload(record.id)
        }
        do {
            let decoded = try JSONDecoder().decode(type, from: payload)
            if requireCanonicalPayload {
                guard try CloudProfileCanonicalPayload.encode(decoded)
                    == payload
                else {
                    throw CloudProfileReplicaValidationError.malformedPayload(
                        record.id
                    )
                }
            }
            return decoded
        } catch let error as CloudProfileReplicaValidationError {
            throw error
        } catch {
            throw CloudProfileReplicaValidationError.malformedPayload(record.id)
        }
    }

    func decodeEconomyMarker(
        _ record: CloudRecord,
        ledgerMarkers: inout [
            LedgerEntryID: DurableEconomyCoordinator.CloudLedgerMarkerV2
        ],
        offerMarkers: inout [
            RewardOfferID: DurableEconomyCoordinator.CloudRewardOfferMarkerV2
        ]
    ) throws {
        guard let payload = record.fields[economyConfiguration.payloadFieldName],
              let object = try? JSONSerialization.jsonObject(with: payload)
                as? [String: Any]
        else {
            throw CloudProfileReplicaValidationError.malformedPayload(record.id)
        }
        let keys = Set(object.keys)

        if keys.contains("record") {
            let marker = try decode(
                DurableEconomyCoordinator.CloudLedgerMarkerV2.self,
                from: record,
                field: economyConfiguration.payloadFieldName,
                requiredKeys: Self.ledgerMarkerRequiredPayloadKeys,
                allowedKeys: Self.ledgerMarkerAllowedPayloadKeys
            )
            let entryID = marker.record.entry.id
            guard ledgerMarkers[entryID] == nil else {
                throw CloudProfileReplicaValidationError.duplicateLedgerMarker(
                    entryID
                )
            }
            let expectedID = DurableEconomyCloudSchema.ledgerMarkerRecordID(
                for: entryID,
                headRecordID: economyConfiguration.recordID
            )
            guard record.id == expectedID else {
                throw wrongID(expected: expectedID, actual: record.id)
            }
            ledgerMarkers[entryID] = marker
            return
        }
        if keys.contains("redemption") {
            let marker = try decode(
                DurableEconomyCoordinator.CloudRewardOfferMarkerV2.self,
                from: record,
                field: economyConfiguration.payloadFieldName,
                requiredKeys: Self.offerMarkerPayloadKeys,
                allowedKeys: Self.offerMarkerPayloadKeys
            )
            let offerID = marker.redemption.offerID
            guard offerMarkers[offerID] == nil else {
                throw CloudProfileReplicaValidationError
                    .duplicateRewardOfferMarker(offerID)
            }
            let expectedID = DurableEconomyCloudSchema.rewardOfferMarkerRecordID(
                for: offerID,
                headRecordID: economyConfiguration.recordID
            )
            guard record.id == expectedID else {
                throw wrongID(expected: expectedID, actual: record.id)
            }
            offerMarkers[offerID] = marker
            return
        }
        if keys == Self.economyHeadPayloadKeys {
            throw wrongID(
                expected: economyConfiguration.recordID,
                actual: record.id
            )
        }
        throw CloudProfileReplicaValidationError.unknownEconomyPayload(record.id)
    }

    func validateSchemasAndBindings(
        root: CloudProfileRootV1,
        settings: CloudProfileSettingsV1,
        selection: CloudProfileSelectionV1,
        runsByID: [RunID: CloudProfileCompletedRunV1],
        economyHead: DurableEconomyCoordinator.CloudAccountHeadV3,
        ledgerMarkers: [
            LedgerEntryID: DurableEconomyCoordinator.CloudLedgerMarkerV2
        ],
        offerMarkers: [
            RewardOfferID: DurableEconomyCoordinator.CloudRewardOfferMarkerV2
        ]
    ) throws {
        guard root.schemaVersion == CloudProfileRootV1.schemaVersion else {
            throw CloudProfileReplicaValidationError.schemaVersionMismatch(
                configuration.rootRecordID
            )
        }
        guard root.binding == expectedBinding else {
            throw CloudProfileReplicaValidationError.bindingMismatch(
                configuration.rootRecordID
            )
        }
        guard root.economyHeadRecordID == economyConfiguration.recordID else {
            throw CloudProfileReplicaValidationError.economyHeadRecordIDMismatch
        }

        guard settings.schemaVersion == CloudProfileSettingsV1.schemaVersion else {
            throw CloudProfileReplicaValidationError.schemaVersionMismatch(
                configuration.settingsRecordID
            )
        }
        guard settings.binding == expectedBinding else {
            throw CloudProfileReplicaValidationError.bindingMismatch(
                configuration.settingsRecordID
            )
        }

        guard selection.schemaVersion == CloudProfileSelectionV1.schemaVersion else {
            throw CloudProfileReplicaValidationError.schemaVersionMismatch(
                configuration.selectionRecordID
            )
        }
        guard selection.binding == expectedBinding else {
            throw CloudProfileReplicaValidationError.bindingMismatch(
                configuration.selectionRecordID
            )
        }

        for run in runsByID.values {
            let recordID = configuration.runRecordID(for: run.runID)
            guard run.schemaVersion == CloudProfileCompletedRunV1.schemaVersion else {
                throw CloudProfileReplicaValidationError.schemaVersionMismatch(
                    recordID
                )
            }
            guard run.binding == expectedBinding else {
                throw CloudProfileReplicaValidationError.bindingMismatch(recordID)
            }
        }

        guard economyHead.schemaVersion
            == DurableEconomyCoordinator.CloudAccountHeadV3.schemaVersion
        else {
            throw CloudProfileReplicaValidationError.schemaVersionMismatch(
                economyConfiguration.recordID
            )
        }
        guard economyHead.cloudAccountID == expectedBinding.cloudAccountID,
              economyHead.accountBinding == expectedBinding.accountBinding,
              economyHead.profileAccountIdentity
                == expectedBinding.profileAccountIdentity
        else {
            throw CloudProfileReplicaValidationError.bindingMismatch(
                economyConfiguration.recordID
            )
        }

        for marker in ledgerMarkers.values {
            let recordID = DurableEconomyCloudSchema.ledgerMarkerRecordID(
                for: marker.record.entry.id,
                headRecordID: economyConfiguration.recordID
            )
            guard marker.schemaVersion
                == DurableEconomyCoordinator.CloudLedgerMarkerV2.schemaVersion
            else {
                throw CloudProfileReplicaValidationError.schemaVersionMismatch(
                    recordID
                )
            }
            guard marker.headRecordID == economyConfiguration.recordID,
                  marker.record.binding.cloudAccountID
                    == expectedBinding.cloudAccountID,
                  marker.record.binding.accountBinding
                    == expectedBinding.accountBinding,
                  marker.record.binding.profileAccountIdentity
                    == expectedBinding.profileAccountIdentity
            else {
                throw CloudProfileReplicaValidationError.bindingMismatch(recordID)
            }
        }

        for marker in offerMarkers.values {
            let recordID = DurableEconomyCloudSchema.rewardOfferMarkerRecordID(
                for: marker.redemption.offerID,
                headRecordID: economyConfiguration.recordID
            )
            guard marker.schemaVersion
                == DurableEconomyCoordinator.CloudRewardOfferMarkerV2.schemaVersion
            else {
                throw CloudProfileReplicaValidationError.schemaVersionMismatch(
                    recordID
                )
            }
            guard marker.headRecordID == economyConfiguration.recordID,
                  marker.binding.cloudAccountID == expectedBinding.cloudAccountID,
                  marker.binding.accountBinding == expectedBinding.accountBinding,
                  marker.binding.profileAccountIdentity
                    == expectedBinding.profileAccountIdentity
            else {
                throw CloudProfileReplicaValidationError.bindingMismatch(recordID)
            }
        }
    }

    func deriveInventory(
        from unlockedItemIDs: [CatalogItemID]
    ) throws -> PlayerInventory {
        guard Set(unlockedItemIDs).count == unlockedItemIDs.count else {
            throw CloudProfileReplicaValidationError.invalidEconomyInventory
        }
        let items: [CatalogItemDescriptor]
        do {
            items = try unlockedItemIDs.map { itemID in
                guard let item = catalog.item(id: itemID) else {
                    throw CloudProfileReplicaValidationError
                        .invalidEconomyInventory
                }
                return item
            }
        } catch {
            throw CloudProfileReplicaValidationError.invalidEconomyInventory
        }

        var inventory = InventoryRules.initialInventory(catalog: catalog)
        let ordered = items.sorted { lhs, rhs in
            let left = Self.unlockOrder(lhs.kind)
            let right = Self.unlockOrder(rhs.kind)
            return left == right
                ? lhs.id.rawValue < rhs.id.rawValue
                : left < right
        }
        do {
            for item in ordered {
                try InventoryRules.applyUnlock(
                    itemID: item.id,
                    to: &inventory,
                    catalog: catalog
                )
            }
        } catch {
            throw CloudProfileReplicaValidationError.invalidEconomyInventory
        }
        return inventory
    }

    static func unlockOrder(_ kind: CatalogItemKind) -> Int {
        switch kind {
        case .team: return 0
        case .alternateJersey: return 1
        case .football: return 2
        }
    }

    func validate(settings: PlayerSettings) throws {
        guard settings.musicVolume.isFinite,
              settings.sfxVolume.isFinite,
              (0 ... 1).contains(settings.musicVolume),
              (0 ... 1).contains(settings.sfxVolume)
        else {
            throw CloudProfileReplicaValidationError.invalidSettings
        }
    }

    func validate(
        run payload: CloudProfileCompletedRunV1,
        inventory: PlayerInventory,
        rewardedAdHead: DurableEconomyCoordinator.CloudRewardedAdHeadV1
    ) throws {
        let runID = payload.runID
        do {
            try CompletedRunValidator.validate(
                payload.record.run,
                recordedAt: payload.record.recordedAt,
                inventory: inventory,
                catalog: catalog
            )
        } catch {
            throw CloudProfileReplicaValidationError.invalidCompletedRun(runID)
        }
        let expectedReward: Int64
        do {
            expectedReward = try CompletedRunValidator.rewardCoins(
                for: payload.record.run
            )
        } catch {
            throw CloudProfileReplicaValidationError.invalidCompletedRun(runID)
        }
        guard payload.record.rewardCoins == expectedReward else {
            throw CloudProfileReplicaValidationError.runRewardMismatch(runID)
        }

        let isRewardEligible = CompletedRunValidator.isRewardEligible(
            payload.record.run
        )
        switch (isRewardEligible, payload.rewardedRunObservation) {
        case (true, nil):
            throw CloudProfileReplicaValidationError
                .missingRewardedRunObservation(runID)
        case (false, .some):
            throw CloudProfileReplicaValidationError
                .extraRewardedRunObservation(runID)
        case let (true, .some(observation)):
            if observation.disposition == .legacyNonCounting {
                guard observation.observedCycle == 0 else {
                    throw CloudProfileReplicaValidationError
                        .invalidRewardedRunObservation(runID)
                }
                return
            }
            guard observation.observedCycle <= rewardedAdHead.cycle else {
                throw CloudProfileReplicaValidationError
                    .invalidRewardedRunObservation(runID)
            }
            if observation.disposition == .ignoredWhileOfferPending,
               observation.observedCycle == rewardedAdHead.cycle,
               rewardedAdHead.eligibleOfferID
                != RewardedAdState.offerID(for: rewardedAdHead.cycle)
            {
                throw CloudProfileReplicaValidationError
                    .invalidRewardedRunObservation(runID)
            }
        case (false, nil):
            break
        }
    }

    func wrongID(
        expected: CloudRecordID,
        actual: CloudRecordID
    ) -> CloudProfileReplicaValidationError {
        .wrongDeterministicRecordID(expected: expected, actual: actual)
    }
}

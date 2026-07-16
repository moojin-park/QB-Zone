import Foundation

/// Canonical bytes for local profile envelopes. Typed-key dictionaries and
/// Sets become JSON arrays under Swift Codable, so JSON sorted keys alone do
/// not make their element order deterministic.
enum PlayerProfileCanonicalEnvelopeEncoderV1 {
    static func encode(_ envelope: PlayerProfileEnvelopeV3) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

        let encoded = try encoder.encode(envelope)
        let object = try JSONSerialization.jsonObject(with: encoded)
        let normalized = try normalize(object, key: nil)
        return try JSONSerialization.data(
            withJSONObject: normalized,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
    }

    private static let dictionaryArrayKeys: Set<String> = [
        "achievementProgress",
        "completedRuns",
        "ledger",
        "pendingAchievementPercents",
        "rewardedRunObservations",
        "selectedJerseyByTeam",
        "settlementReceipts",
    ]

    private static let setArrayKeys: Set<String> = [
        "accountedRunIDs",
        "completedLaneIDs",
        "ownedFootballIDs",
        "ownedJerseyIDs",
        "ownedTeamIDs",
        "pendingLedgerEntryIDs",
    ]

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
                    throw ProfileMigrationError.malformedEnvelope
                }
                var pairs: [(key: Any, value: Any, ordering: Data)] = []
                for index in stride(from: 0, to: array.count, by: 2) {
                    let normalizedKey = try normalize(array[index], key: nil)
                    let normalizedValue = try normalize(array[index + 1], key: nil)
                    let ordering = try orderingBytes(for: normalizedKey)
                    pairs.append((normalizedKey, normalizedValue, ordering))
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

protocol PlayerProfileMigrating: Sendable {
    func decodeArtifact(_ data: Data) throws -> DecodedProfileEnvelopeArtifactV1
    func canonicalArtifact(
        for document: LocalPlayerDocumentV1,
        savedAt: Date
    ) throws -> CanonicalProfileEnvelopeArtifactV1
}

extension PlayerProfileMigrating {
    func decode(_ data: Data) throws -> LocalPlayerDocumentV1 {
        try decodeArtifact(data).document
    }

    func encode(_ document: LocalPlayerDocumentV1, savedAt: Date) throws -> Data {
        try canonicalArtifact(for: document, savedAt: savedAt).exactBytes
    }
}

struct PlayerProfileMigrator: PlayerProfileMigrating {
    private struct EnvelopeHeader: Decodable {
        let format: String
        let schemaVersion: Int
    }

    /// V1 and V2 predate persisted field counters. Keeping their decoding
    /// shape private prevents a declared V3 document from receiving a default
    /// counter when either required field is absent.
    private struct LegacyStamped<Value: Decodable>: Decodable {
        let value: Value
        let modifiedAt: Date
        let deviceID: String
    }

    private struct LegacyPlayerDocumentV1: Decodable {
        let profileID: UUID
        let revision: UInt64
        let createdAt: Date
        let settings: LegacyStamped<PlayerSettings>
        let selection: LegacyStamped<PlayerSelection>
        let inventory: PlayerInventory
        let completedRuns: [RunID: CompletedRunRecord]
        let ledger: [LedgerEntryID: CoinLedgerEntry]
        let career: CareerStatistics
        let achievementProgress: [AchievementID: AchievementProgress]
        let rewardedAdState: RewardedAdState
        let pendingGameCenter: GameCenterSubmissionQueue

        func migratingFieldCounters() -> PlayerDocumentV1 {
            PlayerDocumentV1(
                profileID: profileID,
                revision: revision,
                createdAt: createdAt,
                settings: Stamped(
                    value: settings.value,
                    modifiedAt: settings.modifiedAt,
                    deviceID: settings.deviceID,
                    logicalCounter: revision
                ),
                selection: Stamped(
                    value: selection.value,
                    modifiedAt: selection.modifiedAt,
                    deviceID: selection.deviceID,
                    logicalCounter: revision
                ),
                inventory: inventory,
                completedRuns: completedRuns,
                ledger: ledger,
                career: career,
                achievementProgress: achievementProgress,
                rewardedAdState: rewardedAdState,
                pendingGameCenter: pendingGameCenter
            )
        }
    }

    private struct LegacyLocalPlayerDocumentV1: Decodable {
        let accountIdentity: PlayerAccountIdentity
        let player: LegacyPlayerDocumentV1
        let economyRevision: UInt64
        let pendingLedgerEntryIDs: Set<LedgerEntryID>
        let settlementReceipts: [RunID: RunSettlementOutcome]
        let rewardedRunObservations: [RunID: RewardedRunObservation]?

        func migratingFieldCounters() -> LocalPlayerDocumentV1 {
            LocalPlayerDocumentV1(
                accountIdentity: accountIdentity,
                player: player.migratingFieldCounters(),
                economyRevision: economyRevision,
                pendingLedgerEntryIDs: pendingLedgerEntryIDs,
                settlementReceipts: settlementReceipts,
                rewardedRunObservations: rewardedRunObservations
            )
        }
    }

    private struct LegacyEnvelope: Decodable {
        let format: String
        let schemaVersion: Int
        let savedAt: Date
        let document: LegacyLocalPlayerDocumentV1
    }

    func decodeArtifact(_ data: Data) throws -> DecodedProfileEnvelopeArtifactV1 {
        let header: EnvelopeHeader
        do {
            header = try Self.makeDecoder().decode(EnvelopeHeader.self, from: data)
        } catch {
            throw ProfileMigrationError.malformedEnvelope
        }

        guard header.format == PlayerProfileEnvelopeV3.formatIdentifier else {
            throw ProfileMigrationError.unexpectedFormat(header.format)
        }

        switch header.schemaVersion {
        case PlayerProfileEnvelopeV1.schemaVersion:
            do {
                let envelope = try Self.makeDecoder().decode(LegacyEnvelope.self, from: data)
                guard envelope.format == PlayerProfileEnvelopeV1.formatIdentifier,
                      envelope.schemaVersion == PlayerProfileEnvelopeV1.schemaVersion,
                      envelope.savedAt.timeIntervalSince1970.isFinite else {
                    throw ProfileMigrationError.malformedEnvelope
                }
                let document = envelope.document.migratingFieldCounters()
                return DecodedProfileEnvelopeArtifactV1(
                    sourceSchemaVersion: envelope.schemaVersion,
                    savedAt: envelope.savedAt,
                    document: Self.migrateLegacyV1(document)
                )
            } catch let error as ProfileMigrationError {
                throw error
            } catch {
                throw ProfileMigrationError.malformedEnvelope
            }
        case PlayerProfileEnvelopeV2.schemaVersion:
            do {
                let envelope = try Self.makeDecoder().decode(LegacyEnvelope.self, from: data)
                guard envelope.format == PlayerProfileEnvelopeV2.formatIdentifier,
                      envelope.schemaVersion == PlayerProfileEnvelopeV2.schemaVersion,
                      envelope.savedAt.timeIntervalSince1970.isFinite else {
                    throw ProfileMigrationError.malformedEnvelope
                }
                return DecodedProfileEnvelopeArtifactV1(
                    sourceSchemaVersion: envelope.schemaVersion,
                    savedAt: envelope.savedAt,
                    document: envelope.document.migratingFieldCounters()
                )
            } catch let error as ProfileMigrationError {
                throw error
            } catch {
                throw ProfileMigrationError.malformedEnvelope
            }
        case PlayerProfileEnvelopeV3.schemaVersion:
            do {
                let envelope = try Self.makeDecoder()
                    .decode(PlayerProfileEnvelopeV3.self, from: data)
                guard envelope.format == PlayerProfileEnvelopeV3.formatIdentifier,
                      envelope.schemaVersion == PlayerProfileEnvelopeV3.schemaVersion,
                      envelope.savedAt.timeIntervalSince1970.isFinite else {
                    throw ProfileMigrationError.malformedEnvelope
                }
                return DecodedProfileEnvelopeArtifactV1(
                    sourceSchemaVersion: envelope.schemaVersion,
                    savedAt: envelope.savedAt,
                    document: envelope.document
                )
            } catch let error as ProfileMigrationError {
                throw error
            } catch {
                throw ProfileMigrationError.malformedEnvelope
            }
        default:
            throw ProfileMigrationError.unsupportedSchemaVersion(header.schemaVersion)
        }
    }

    func canonicalArtifact(
        for document: LocalPlayerDocumentV1,
        savedAt: Date
    ) throws -> CanonicalProfileEnvelopeArtifactV1 {
        guard document.rewardedRunObservations != nil,
              savedAt.timeIntervalSince1970.isFinite else {
            throw ProfileMigrationError.malformedEnvelope
        }
        let envelope = PlayerProfileEnvelopeV3(
            document: document,
            savedAt: savedAt
        )
        let exactBytes = try PlayerProfileCanonicalEnvelopeEncoderV1.encode(envelope)
        return CanonicalProfileEnvelopeArtifactV1(
            envelope: envelope,
            exactBytes: exactBytes,
            digest: .envelopeBytes(exactBytes)
        )
    }

    private static func migrateLegacyV1(
        _ source: LocalPlayerDocumentV1
    ) -> LocalPlayerDocumentV1 {
        var document = source

        // The canonical signing timestamp is identity metadata, not an earned-
        // at timestamp. Only normalize the one exact legacy singleton shape;
        // every other malformed signing record remains untouched so validation
        // still fails closed.
        let signingIDs = document.player.ledger.compactMap { entryID, entry in
            if case .signingBonus = entry.reason { return entryID }
            return nil
        }
        if signingIDs.count == 1,
           let signingID = signingIDs.first,
           let entry = document.player.ledger[signingID],
           signingID == CoinLedgerID.signingBonus(
               version: PersistedEconomyRulesV1.signingBonusVersion
           ),
           entry.delta == PersistedEconomyRulesV1.signingBonusCoins,
           case .signingBonus(PersistedEconomyRulesV1.signingBonusVersion) = entry.reason,
           entry.createdAt.timeIntervalSince1970.isFinite {
            document.player.ledger[signingID] = CoinLedgerEntry(
                id: entry.id,
                delta: entry.delta,
                reason: entry.reason,
                createdAt: PersistedEconomyRulesV1.signingBonusLedgerCreatedAt
            )
        }

        guard document.rewardedRunObservations == nil else { return document }

        let eligibleRuns = document.player.completedRuns.values.filter {
            CompletedRunValidator.isRewardEligible($0.run)
        }
        document.rewardedRunObservations = Dictionary(
            uniqueKeysWithValues: eligibleRuns.map {
                (
                    $0.run.runID,
                    RewardedRunObservation(
                        observedCycle: 0,
                        disposition: .legacyNonCounting
                    )
                )
            }
        )

        let prior = document.player.rewardedAdState
        document.player.rewardedAdState = RewardedAdState(
            cycle: prior.cycle,
            validRunsSinceReward: 0,
            eligibleOfferID: nil,
            accountedRunIDs: prior.accountedRunIDs
        )
        return document
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}

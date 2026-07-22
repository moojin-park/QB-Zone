import Foundation

/// Canonical bytes for local profile envelopes. Typed-key dictionaries and
/// Sets become JSON arrays under Swift Codable, so JSON sorted keys alone do
/// not make their element order deterministic.
enum PlayerProfileCanonicalEnvelopeEncoderV1 {
    static func encode(_ envelope: PlayerProfileEnvelopeV4) throws -> Data {
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
        "pendingByPlayerID",
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

/// A bounded syntax and duplicate-member pass that runs before Foundation
/// decoding. JSONDecoder exposes only the final value for duplicate object
/// names, so checking keyed containers after decode is too late to preserve
/// conflicting persistence evidence.
private enum PlayerProfileRawJSONPreflightV1 {
    private static let maximumDepth = 128
    private static let maximumStructuralTokens = 1_000_000

    private enum Failure: Error {
        case invalid
    }

    static func validate(_ data: Data) throws {
        guard data.count <= ProfileHydrationLimits.production
                .maximumProfileEnvelopeBytes,
              String(data: data, encoding: .utf8) != nil else {
            throw Failure.invalid
        }
        var parser = Parser(bytes: Array(data))
        try parser.parseDocument()
    }

    private struct Parser {
        let bytes: [UInt8]
        var index = 0
        var structuralTokenCount = 0

        mutating func parseDocument() throws {
            skipWhitespace()
            try parseValue(depth: 0)
            skipWhitespace()
            guard index == bytes.count else { throw Failure.invalid }
        }

        mutating func parseValue(depth: Int) throws {
            try consumeStructuralToken()
            guard index < bytes.count else { throw Failure.invalid }
            switch bytes[index] {
            case 0x7b:
                try parseObject(depth: depth)
            case 0x5b:
                try parseArray(depth: depth)
            case 0x22:
                _ = try parseString(returnDecodedValue: false)
            case 0x74:
                try consumeLiteral([0x74, 0x72, 0x75, 0x65])
            case 0x66:
                try consumeLiteral([0x66, 0x61, 0x6c, 0x73, 0x65])
            case 0x6e:
                try consumeLiteral([0x6e, 0x75, 0x6c, 0x6c])
            case 0x2d, 0x30 ... 0x39:
                try parseNumber()
            default:
                throw Failure.invalid
            }
        }

        mutating func parseObject(depth: Int) throws {
            guard depth < PlayerProfileRawJSONPreflightV1.maximumDepth else {
                throw Failure.invalid
            }
            index += 1
            skipWhitespace()
            if consume(0x7d) { return }

            var decodedNames: Set<String> = []
            while true {
                try consumeStructuralToken()
                guard index < bytes.count, bytes[index] == 0x22,
                      let name = try parseString(returnDecodedValue: true) else {
                    throw Failure.invalid
                }
                guard decodedNames.insert(name).inserted else {
                    throw Failure.invalid
                }
                skipWhitespace()
                guard consume(0x3a) else { throw Failure.invalid }
                skipWhitespace()
                try parseValue(depth: depth + 1)
                skipWhitespace()
                if consume(0x7d) { return }
                guard consume(0x2c) else { throw Failure.invalid }
                skipWhitespace()
            }
        }

        mutating func parseArray(depth: Int) throws {
            guard depth < PlayerProfileRawJSONPreflightV1.maximumDepth else {
                throw Failure.invalid
            }
            index += 1
            skipWhitespace()
            if consume(0x5d) { return }

            while true {
                try parseValue(depth: depth + 1)
                skipWhitespace()
                if consume(0x5d) { return }
                guard consume(0x2c) else { throw Failure.invalid }
                skipWhitespace()
            }
        }

        mutating func parseString(
            returnDecodedValue: Bool
        ) throws -> String? {
            guard consume(0x22) else { throw Failure.invalid }
            var decodedUTF8: [UInt8] = []

            while index < bytes.count {
                let byte = bytes[index]
                index += 1
                if byte == 0x22 {
                    guard returnDecodedValue else { return nil }
                    guard let decoded = String(
                        bytes: decodedUTF8,
                        encoding: .utf8
                    ) else {
                        throw Failure.invalid
                    }
                    return decoded
                }
                guard byte >= 0x20 else { throw Failure.invalid }
                if byte != 0x5c {
                    if returnDecodedValue { decodedUTF8.append(byte) }
                    continue
                }

                guard index < bytes.count else { throw Failure.invalid }
                let escape = bytes[index]
                index += 1
                switch escape {
                case 0x22, 0x5c, 0x2f:
                    if returnDecodedValue { decodedUTF8.append(escape) }
                case 0x62:
                    if returnDecodedValue { decodedUTF8.append(0x08) }
                case 0x66:
                    if returnDecodedValue { decodedUTF8.append(0x0c) }
                case 0x6e:
                    if returnDecodedValue { decodedUTF8.append(0x0a) }
                case 0x72:
                    if returnDecodedValue { decodedUTF8.append(0x0d) }
                case 0x74:
                    if returnDecodedValue { decodedUTF8.append(0x09) }
                case 0x75:
                    let first = try parseHexCodeUnit()
                    let scalarValue: UInt32
                    if (0xd800 ... 0xdbff).contains(first) {
                        guard index + 1 < bytes.count,
                              bytes[index] == 0x5c,
                              bytes[index + 1] == 0x75 else {
                            throw Failure.invalid
                        }
                        index += 2
                        let second = try parseHexCodeUnit()
                        guard (0xdc00 ... 0xdfff).contains(second) else {
                            throw Failure.invalid
                        }
                        scalarValue = 0x1_0000
                            + (UInt32(first - 0xd800) << 10)
                            + UInt32(second - 0xdc00)
                    } else {
                        guard !(0xdc00 ... 0xdfff).contains(first) else {
                            throw Failure.invalid
                        }
                        scalarValue = UInt32(first)
                    }
                    if returnDecodedValue {
                        guard let scalar = Unicode.Scalar(scalarValue) else {
                            throw Failure.invalid
                        }
                        decodedUTF8.append(contentsOf: String(scalar).utf8)
                    }
                default:
                    throw Failure.invalid
                }
            }
            throw Failure.invalid
        }

        mutating func parseHexCodeUnit() throws -> UInt16 {
            guard index + 4 <= bytes.count else { throw Failure.invalid }
            var result: UInt16 = 0
            for _ in 0 ..< 4 {
                result = result << 4
                switch bytes[index] {
                case 0x30 ... 0x39:
                    result += UInt16(bytes[index] - 0x30)
                case 0x41 ... 0x46:
                    result += UInt16(bytes[index] - 0x41 + 10)
                case 0x61 ... 0x66:
                    result += UInt16(bytes[index] - 0x61 + 10)
                default:
                    throw Failure.invalid
                }
                index += 1
            }
            return result
        }

        mutating func parseNumber() throws {
            _ = consume(0x2d)
            guard index < bytes.count else { throw Failure.invalid }
            if consume(0x30) {
                guard index == bytes.count
                        || !(0x30 ... 0x39).contains(bytes[index]) else {
                    throw Failure.invalid
                }
            } else {
                guard consumeDigit(in: 0x31 ... 0x39) else {
                    throw Failure.invalid
                }
                while consumeDigit(in: 0x30 ... 0x39) {}
            }
            if consume(0x2e) {
                guard consumeDigit(in: 0x30 ... 0x39) else {
                    throw Failure.invalid
                }
                while consumeDigit(in: 0x30 ... 0x39) {}
            }
            if consume(0x65) || consume(0x45) {
                _ = consume(0x2b) || consume(0x2d)
                guard consumeDigit(in: 0x30 ... 0x39) else {
                    throw Failure.invalid
                }
                while consumeDigit(in: 0x30 ... 0x39) {}
            }
        }

        mutating func consumeLiteral(_ literal: [UInt8]) throws {
            guard index + literal.count <= bytes.count,
                  Array(bytes[index ..< index + literal.count]) == literal else {
                throw Failure.invalid
            }
            index += literal.count
        }

        mutating func consumeStructuralToken() throws {
            structuralTokenCount += 1
            guard structuralTokenCount
                    <= PlayerProfileRawJSONPreflightV1.maximumStructuralTokens else {
                throw Failure.invalid
            }
        }

        mutating func skipWhitespace() {
            while index < bytes.count,
                  bytes[index] == 0x20 || bytes[index] == 0x09
                    || bytes[index] == 0x0a || bytes[index] == 0x0d {
                index += 1
            }
        }

        mutating func consume(_ byte: UInt8) -> Bool {
            guard index < bytes.count, bytes[index] == byte else { return false }
            index += 1
            return true
        }

        mutating func consumeDigit(
            in range: ClosedRange<UInt8>
        ) -> Bool {
            guard index < bytes.count, range.contains(bytes[index]) else {
                return false
            }
            index += 1
            return true
        }
    }
}

/// Durable launch-catalog reconciliation shared by every supported profile
/// envelope. The transition deliberately does not change revisions or the
/// envelope timestamp: it replaces only achievement state whose persisted
/// meaning changed between launch catalog V1 and V2.
enum LaunchAchievementPersistenceTransitionV1ToV2 {
    private static let affectedCurrentIDs =
        AchievementCatalogTransitionV1ToV2.recomputedAchievementIDs
    private static let retiredID =
        AchievementCatalogTransitionV1ToV2.retiredCenturyOfConnections

    static func apply(
        to source: LocalPlayerDocumentV1
    ) throws -> LocalPlayerDocumentV1 {
        // Preserve deliberately non-catalog documents used by low-level
        // canonical-codec tests. Such documents remain invalid for production
        // validation; every empty or launch-catalog-bearing profile still
        // enters the transition.
        guard shouldApply(to: source) else { return source }
        try validateTransitionInput(source)
        var document = source
        let completedRuns = Array(document.player.completedRuns.values)

        document.player.achievementProgress.removeValue(forKey: retiredID)
        for achievementID in affectedCurrentIDs {
            guard let percent = AchievementCatalogTransitionV1ToV2
                .recomputedPercent(
                    for: achievementID,
                    careerSuccessfulPasses:
                        document.player.career.successfulPasses,
                    completedRuns: completedRuns
                )
            else {
                throw ProfileMigrationError.malformedEnvelope
            }
            let completedAt = percent == 100
                ? AchievementCatalogTransitionV1ToV2.recomputedCompletedAt(
                    for: achievementID,
                    completedRuns: completedRuns
                )
                : nil
            guard (percent == 100) == (completedAt != nil) else {
                throw ProfileMigrationError.malformedEnvelope
            }
            document.player.achievementProgress[achievementID] =
                AchievementProgress(
                    id: achievementID,
                    percentComplete: percent,
                    completedAt: completedAt
                )
        }

        document.player.pendingGameCenter.unboundPending = reconcile(
            document.player.pendingGameCenter.unboundPending,
            earned: document.player.achievementProgress
        )
        document.player.pendingGameCenter.pendingByPlayerID = Dictionary(
            uniqueKeysWithValues: document.player.pendingGameCenter
                .pendingByPlayerID.compactMap { playerID, pending in
                    let reconciled = reconcile(
                        pending,
                        earned: document.player.achievementProgress
                    )
                    return reconciled.isEmpty ? nil : (playerID, reconciled)
                }
        )

        document.settlementReceipts = try rebuildAffectedReceiptUpdates(
            in: document
        )
        return document
    }

    private static func shouldApply(
        to document: LocalPlayerDocumentV1
    ) -> Bool {
        let catalogIDs = Set(AchievementCatalog.launch.map(\.id)).union(
            [retiredID]
        )
        let progressIDs = Set(document.player.achievementProgress.keys)
        if progressIDs.isEmpty || !progressIDs.isDisjoint(with: catalogIDs) {
            return true
        }
        let queue = document.player.pendingGameCenter
        if !Set(queue.unboundPending.pendingAchievementPercents.keys)
            .isDisjoint(with: catalogIDs) {
            return true
        }
        return queue.pendingByPlayerID.values.contains { pending in
            !Set(pending.pendingAchievementPercents.keys)
                .isDisjoint(with: catalogIDs)
        }
    }

    /// The transition is allowed to remove retired IDs, so validate the
    /// bounded predecessor/current union before mutating it. This prevents a
    /// malformed percentage, key mismatch, or unrelated unknown ID from being
    /// laundered into an otherwise valid current document.
    private static func validateTransitionInput(
        _ document: LocalPlayerDocumentV1
    ) throws {
        let transitionIDs = affectedCurrentIDs.union([retiredID])
        let progress = document.player.achievementProgress
        for (key, value) in progress {
            guard transitionIDs.contains(key)
                    || transitionIDs.contains(value.id) else { continue }
            guard key == value.id,
                  transitionIDs.contains(key),
                  (0 ... 100).contains(value.percentComplete),
                  (value.percentComplete == 100)
                    == (value.completedAt != nil),
                  value.completedAt?.timeIntervalSince1970.isFinite ?? true
            else {
                throw ProfileMigrationError.malformedEnvelope
            }
        }

        let queue = document.player.pendingGameCenter
        func validatePending(
            _ pending: GameCenterPendingMaximaV1
        ) throws {
            for (achievementID, percent) in
                pending.pendingAchievementPercents {
                guard !transitionIDs.contains(achievementID)
                        || (0 ... 100).contains(percent) else {
                    throw ProfileMigrationError.malformedEnvelope
                }
            }
        }
        try validatePending(queue.unboundPending)
        for (_, pending) in queue.pendingByPlayerID {
            try validatePending(pending)
        }
    }

    private static func reconcile(
        _ source: GameCenterPendingMaximaV1,
        earned: [AchievementID: AchievementProgress]
    ) -> GameCenterPendingMaximaV1 {
        let evidence = source.pendingAchievementPercents
        var result = source
        for achievementID in
            AchievementCatalogTransitionV1ToV2.pendingQueueScrubIDs {
            result.pendingAchievementPercents.removeValue(
                forKey: achievementID
            )
        }
        for achievementID in affectedCurrentIDs {
            guard let pending = AchievementCatalogTransitionV1ToV2
                .reconciledPendingPercent(
                    for: achievementID,
                    pendingEvidencePercentsInSameProvenanceBucket: evidence,
                    recomputedEarnedPercent:
                        earned[achievementID]?.percentComplete ?? 0
                )
            else { continue }
            result.pendingAchievementPercents[achievementID] = pending
        }
        result.pendingAchievementPercents = result
            .pendingAchievementPercents.filter { $0.value > 0 }
        return result
    }

    private static func rebuildAffectedReceiptUpdates(
        in document: LocalPlayerDocumentV1
    ) throws -> [RunID: RunSettlementOutcome] {
        let orderedNaturalRecords = document.player.completedRuns.values
            .filter { $0.run.isNaturallyCompleted }
            .sorted(by: orderedBefore)
        var replayCareer = CareerStatistics()
        var replayProgress = Dictionary(
            uniqueKeysWithValues: AchievementCatalog.launch.map {
                ($0.id, AchievementProgress(id: $0.id))
            }
        )
        var replacementsByRunID: [RunID: [AchievementProgressUpdate]] = [:]

        for record in orderedNaturalRecords {
            do {
                replayCareer = try PersistedCareerAccumulatorV1.applying(
                    record.run,
                    to: replayCareer
                )
            } catch {
                throw ProfileMigrationError.malformedEnvelope
            }
            let updates = AchievementEvaluator.evaluate(
                run: record.run,
                careerAfter: replayCareer,
                existing: replayProgress,
                evaluatedAt: record.recordedAt
            )
            for update in updates {
                replayProgress[update.current.id] = update.current
            }
            replacementsByRunID[record.run.runID] = updates.filter {
                affectedCurrentIDs.contains($0.current.id)
            }
        }

        return document.settlementReceipts.mapValues { receipt in
            let unrelated = receipt.achievementUpdates.filter {
                !isAffected($0.previous.id) && !isAffected($0.current.id)
            }
            return RunSettlementOutcome(
                record: receipt.record,
                gameplayRewardEntryID: receipt.gameplayRewardEntryID,
                signingBonusEntryID: receipt.signingBonusEntryID,
                achievementUpdates: unrelated
                    + (replacementsByRunID[receipt.record.run.runID] ?? []),
                rewardedOfferUnlocked: receipt.rewardedOfferUnlocked,
                resultingPersonalBest: receipt.resultingPersonalBest
            )
        }
    }

    private static func isAffected(_ id: AchievementID) -> Bool {
        id == retiredID || affectedCurrentIDs.contains(id)
    }

    private static func orderedBefore(
        _ lhs: CompletedRunRecord,
        _ rhs: CompletedRunRecord
    ) -> Bool {
        if lhs.recordedAt != rhs.recordedAt {
            return lhs.recordedAt < rhs.recordedAt
        }
        return lhs.run.runID.description.utf8.lexicographicallyPrecedes(
            rhs.run.runID.description.utf8
        )
    }
}

protocol PlayerProfileMigrating: Sendable {
    func decodeArtifact(_ data: Data) throws -> DecodedProfileEnvelopeArtifactV1
    /// Exact pre-catalog-transition decoding is reserved for recovery of an
    /// already-durable hydration journal whose byte identities cannot change.
    func decodeArtifactPreservingLaunchAchievementCatalog(
        _ data: Data
    ) throws -> DecodedProfileEnvelopeArtifactV1
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
    /// shape private prevents a declared V3-or-later document from receiving a
    /// default counter when either required field is absent.
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
        let pendingGameCenter: LegacyGameCenterSubmissionQueueV1

        func migratingFieldCountersAndGameCenterQueue() -> PlayerDocumentV1 {
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
                pendingGameCenter: PlayerScopedGameCenterQueueV1(
                    quarantining: pendingGameCenter
                )
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

        func migratingFieldCountersAndGameCenterQueue() -> LocalPlayerDocumentV1 {
            LocalPlayerDocumentV1(
                accountIdentity: accountIdentity,
                player: player.migratingFieldCountersAndGameCenterQueue(),
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

    /// V3 has explicit field counters but still persists the old global Game
    /// Center queue. Decode that exact shape and move it only to unbound.
    private struct LegacyPlayerDocumentV3: Decodable {
        let profileID: UUID
        let revision: UInt64
        let createdAt: Date
        let settings: Stamped<PlayerSettings>
        let selection: Stamped<PlayerSelection>
        let inventory: PlayerInventory
        let completedRuns: [RunID: CompletedRunRecord]
        let ledger: [LedgerEntryID: CoinLedgerEntry]
        let career: CareerStatistics
        let achievementProgress: [AchievementID: AchievementProgress]
        let rewardedAdState: RewardedAdState
        let pendingGameCenter: LegacyGameCenterSubmissionQueueV1

        func migratingGameCenterQueue() -> PlayerDocumentV1 {
            PlayerDocumentV1(
                profileID: profileID,
                revision: revision,
                createdAt: createdAt,
                settings: settings,
                selection: selection,
                inventory: inventory,
                completedRuns: completedRuns,
                ledger: ledger,
                career: career,
                achievementProgress: achievementProgress,
                rewardedAdState: rewardedAdState,
                pendingGameCenter: PlayerScopedGameCenterQueueV1(
                    quarantining: pendingGameCenter
                )
            )
        }
    }

    private struct LegacyLocalPlayerDocumentV3: Decodable {
        let accountIdentity: PlayerAccountIdentity
        let player: LegacyPlayerDocumentV3
        let economyRevision: UInt64
        let pendingLedgerEntryIDs: Set<LedgerEntryID>
        let settlementReceipts: [RunID: RunSettlementOutcome]
        let rewardedRunObservations: [RunID: RewardedRunObservation]?

        func migratingGameCenterQueue() -> LocalPlayerDocumentV1 {
            LocalPlayerDocumentV1(
                accountIdentity: accountIdentity,
                player: player.migratingGameCenterQueue(),
                economyRevision: economyRevision,
                pendingLedgerEntryIDs: pendingLedgerEntryIDs,
                settlementReceipts: settlementReceipts,
                rewardedRunObservations: rewardedRunObservations
            )
        }
    }

    private struct LegacyEnvelopeV3: Decodable {
        let format: String
        let schemaVersion: Int
        let savedAt: Date
        let document: LegacyLocalPlayerDocumentV3
    }

    func decodeArtifact(_ data: Data) throws -> DecodedProfileEnvelopeArtifactV1 {
        let decoded = try decodeArtifactPreservingLaunchAchievementCatalog(data)
        return DecodedProfileEnvelopeArtifactV1(
            sourceSchemaVersion: decoded.sourceSchemaVersion,
            savedAt: decoded.savedAt,
            document: try LaunchAchievementPersistenceTransitionV1ToV2
                .apply(to: decoded.document)
        )
    }

    func decodeArtifactPreservingLaunchAchievementCatalog(
        _ data: Data
    ) throws -> DecodedProfileEnvelopeArtifactV1 {
        do {
            try PlayerProfileRawJSONPreflightV1.validate(data)
        } catch {
            throw ProfileMigrationError.malformedEnvelope
        }

        let header: EnvelopeHeader
        do {
            header = try Self.makeDecoder().decode(EnvelopeHeader.self, from: data)
        } catch {
            throw ProfileMigrationError.malformedEnvelope
        }

        guard header.format == PlayerProfileEnvelopeV4.formatIdentifier else {
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
                let document = envelope.document
                    .migratingFieldCountersAndGameCenterQueue()
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
                    document: envelope.document
                        .migratingFieldCountersAndGameCenterQueue()
                )
            } catch let error as ProfileMigrationError {
                throw error
            } catch {
                throw ProfileMigrationError.malformedEnvelope
            }
        case PlayerProfileEnvelopeV3.schemaVersion:
            do {
                let envelope = try Self.makeDecoder()
                    .decode(LegacyEnvelopeV3.self, from: data)
                guard envelope.format == PlayerProfileEnvelopeV3.formatIdentifier,
                      envelope.schemaVersion == PlayerProfileEnvelopeV3.schemaVersion,
                      envelope.savedAt.timeIntervalSince1970.isFinite else {
                    throw ProfileMigrationError.malformedEnvelope
                }
                return DecodedProfileEnvelopeArtifactV1(
                    sourceSchemaVersion: envelope.schemaVersion,
                    savedAt: envelope.savedAt,
                    document: envelope.document.migratingGameCenterQueue()
                )
            } catch let error as ProfileMigrationError {
                throw error
            } catch {
                throw ProfileMigrationError.malformedEnvelope
            }
        case PlayerProfileEnvelopeV4.schemaVersion:
            do {
                let envelope = try Self.makeDecoder()
                    .decode(PlayerProfileEnvelopeV4.self, from: data)
                guard envelope.format == PlayerProfileEnvelopeV4.formatIdentifier,
                      envelope.schemaVersion == PlayerProfileEnvelopeV4.schemaVersion,
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
        let envelope = PlayerProfileEnvelopeV4(
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

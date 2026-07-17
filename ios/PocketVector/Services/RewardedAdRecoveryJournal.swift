import CoreFoundation
import Foundation

enum RewardedAdRecoveryJournalError: Error, Equatable, Sendable {
    case invalidEnvelope
    case unsupportedSchemaVersion(Int)
    case journalTooLarge(actual: Int, maximum: Int)
    case invalidChallenge
    case journalAlreadyExists
    case journalCopiesDisagree
    case noValidJournalCopy
    case quarantineBarrier
    case quarantineCapacityExceeded
    case durableOwnerMismatch
    case presentationSessionMismatch
    case challengeMismatch
    case statusObservationMismatch
    case deliveryAlreadyInProgress
    case deliveryResultMismatch
    case lockContended
    case atomicWriteOutcomeUnknown
    case ioFailure
}

struct RewardedAdRecoveryJournalV1: Codable, Equatable, Sendable {
    static let formatIdentifier = "com.pocketvector.rewarded-ad-recovery"
    static let currentSchemaVersion = 1

    let format: String
    let schemaVersion: Int
    let challenge: RewardedAdVerificationChallengeV1

    enum CodingKeys: String, CodingKey, CaseIterable {
        case format
        case schemaVersion
        case challenge
    }

    static var persistedFieldManifest: String {
        CodingKeys.allCases.map(\.rawValue).sorted().joined(separator: ",")
    }

    fileprivate init(challenge: RewardedAdVerificationChallengeV1) {
        format = Self.formatIdentifier
        schemaVersion = Self.currentSchemaVersion
        self.challenge = challenge
    }

    init(from decoder: any Decoder) throws {
        try requireExactRewardedAdRecoveryKeys(
            decoder,
            expected: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        format = try container.decode(String.self, forKey: .format)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        challenge = try container.decode(
            RewardedAdVerificationChallengeV1.self,
            forKey: .challenge
        )
    }
}

struct RewardedAdRecoveryJournalArtifactV1: Equatable, Sendable {
    let journal: RewardedAdRecoveryJournalV1
    let exactBytes: Data

    fileprivate init(
        journal: RewardedAdRecoveryJournalV1,
        exactBytes: Data
    ) {
        self.journal = journal
        self.exactBytes = exactBytes
    }
}

enum RewardedAdRecoveryLoadSource: String, Equatable, Sendable {
    case primary
    case backup
}

struct RewardedAdRecoveryLoadReport: Equatable, Sendable {
    let source: RewardedAdRecoveryLoadSource
    let repairedMissingOrInvalidCopy: Bool
    let quarantinedURLs: [URL]
}

struct RewardedAdRecoverySnapshot: Equatable, Sendable {
    let challenge: RewardedAdVerificationChallengeV1
    let report: RewardedAdRecoveryLoadReport
}

enum RewardedAdRecoveryCheckedStatusDisposition: Sendable {
    case pending
    case terminalRejected(RewardedAdVerificationTerminalRejection)
    case verified(VerifiedRewardedAdClaim)
}

private struct RewardedAdRecoveryDynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        return nil
    }
}

private func requireExactRewardedAdRecoveryKeys(
    _ decoder: any Decoder,
    expected: Set<String>
) throws {
    let container = try decoder.container(
        keyedBy: RewardedAdRecoveryDynamicCodingKey.self
    )
    guard Set(container.allKeys.map(\.stringValue)) == expected else {
        throw RewardedAdRecoveryJournalError.invalidEnvelope
    }
}

private enum RewardedAdRecoveryJournalLimitsV1 {
    static let maximumJournalBytes = 16 * 1_024
    static let maximumQuarantineFiles = 8
    static let maximumJSONDepth = 16
    static let maximumJSONStructuralTokens = 8_192
    static let maximumAccountKeyBytes = 256
    static let maximumOfferIDBytes = 128
    static let minimumOpaqueTokenBytes = 16
    static let maximumOpaqueTokenBytes = 512

    static let zeroUUID = UUID(
        uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    )

    static func isValidBoundedIdentifier(
        _ value: String,
        maximumBytes: Int
    ) -> Bool {
        let bytes = Array(value.utf8)
        guard !bytes.isEmpty, bytes.count <= maximumBytes else { return false }
        return bytes.allSatisfy { byte in
            (0x21 ... 0x7e).contains(byte) && byte != 0x22 && byte != 0x5c
        }
    }

    static func isValidOpaqueToken(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard bytes.count >= minimumOpaqueTokenBytes,
              bytes.count <= maximumOpaqueTokenBytes else {
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

    static func isCanonicalRewardOfferID(_ value: String) -> Bool {
        guard value.hasPrefix(RewardedAdState.offerIDPrefix) else { return false }
        let suffix = value.dropFirst(RewardedAdState.offerIDPrefix.count)
        guard !suffix.isEmpty,
              suffix.allSatisfy({ $0.isASCII && $0.isNumber }),
              suffix == "0" || suffix.first != "0",
              let cycle = UInt64(suffix) else {
            return false
        }
        return RewardedAdState.offerID(for: cycle).rawValue == value
    }
}

private enum RewardedAdRecoveryJournalCodecV1 {
    static func artifact(
        for challenge: RewardedAdVerificationChallengeV1
    ) throws -> RewardedAdRecoveryJournalArtifactV1 {
        let journal = RewardedAdRecoveryJournalV1(challenge: challenge)
        try validate(journal)
        let bytes: Data
        do {
            bytes = try encoder().encode(journal)
        } catch {
            throw RewardedAdRecoveryJournalError.invalidEnvelope
        }
        guard bytes.count
                <= RewardedAdRecoveryJournalLimitsV1.maximumJournalBytes else {
            throw RewardedAdRecoveryJournalError.journalTooLarge(
                actual: bytes.count,
                maximum: RewardedAdRecoveryJournalLimitsV1.maximumJournalBytes
            )
        }
        return RewardedAdRecoveryJournalArtifactV1(
            journal: journal,
            exactBytes: bytes
        )
    }

    static func decodeArtifact(
        _ data: Data
    ) throws -> RewardedAdRecoveryJournalArtifactV1 {
        guard data.count
                <= RewardedAdRecoveryJournalLimitsV1.maximumJournalBytes else {
            throw RewardedAdRecoveryJournalError.journalTooLarge(
                actual: data.count,
                maximum: RewardedAdRecoveryJournalLimitsV1.maximumJournalBytes
            )
        }
        do {
            try RewardedAdRecoveryRawJSONPreflightV1.validate(data)
            try RewardedAdRecoveryRawShapeV1.validate(data)
        } catch let error as RewardedAdRecoveryJournalError {
            throw error
        } catch {
            throw RewardedAdRecoveryJournalError.invalidEnvelope
        }

        let journal: RewardedAdRecoveryJournalV1
        do {
            journal = try decoder().decode(
                RewardedAdRecoveryJournalV1.self,
                from: data
            )
        } catch let error as RewardedAdRecoveryJournalError {
            throw error
        } catch {
            throw RewardedAdRecoveryJournalError.invalidEnvelope
        }
        try validate(journal)
        let canonical = try artifact(for: journal.challenge)
        guard canonical.journal == journal,
              canonical.exactBytes == data else {
            throw RewardedAdRecoveryJournalError.invalidEnvelope
        }
        return canonical
    }

    private static func validate(
        _ journal: RewardedAdRecoveryJournalV1
    ) throws {
        guard journal.format == RewardedAdRecoveryJournalV1.formatIdentifier else {
            throw RewardedAdRecoveryJournalError.invalidEnvelope
        }
        guard journal.schemaVersion
                == RewardedAdRecoveryJournalV1.currentSchemaVersion else {
            throw RewardedAdRecoveryJournalError.unsupportedSchemaVersion(
                journal.schemaVersion
            )
        }
        let challenge = journal.challenge
        let attempt = challenge.attempt
        guard challenge.schemaVersion
                == RewardedAdVerificationChallengeV1.currentSchemaVersion,
              RewardedAdRecoveryJournalLimitsV1.isValidBoundedIdentifier(
                attempt.binding.accountKey.rawValue,
                maximumBytes: RewardedAdRecoveryJournalLimitsV1
                    .maximumAccountKeyBytes
              ),
              attempt.binding.profileID
                != RewardedAdRecoveryJournalLimitsV1.zeroUUID,
              attempt.presentationSessionNonce
                != RewardedAdRecoveryJournalLimitsV1.zeroUUID,
              attempt.attemptID != RewardedAdRecoveryJournalLimitsV1.zeroUUID,
              RewardedAdRecoveryJournalLimitsV1.isValidBoundedIdentifier(
                attempt.offerID.rawValue,
                maximumBytes: RewardedAdRecoveryJournalLimitsV1
                    .maximumOfferIDBytes
              ),
              RewardedAdRecoveryJournalLimitsV1.isCanonicalRewardOfferID(
                attempt.offerID.rawValue
              ),
              RewardedAdRecoveryJournalLimitsV1.isValidOpaqueToken(
                challenge.verificationHandle.transportValue
              ),
              RewardedAdRecoveryJournalLimitsV1.isValidOpaqueToken(
                challenge.providerCustomData.transportValue
              ) else {
            throw RewardedAdRecoveryJournalError.invalidChallenge
        }
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.keyEncodingStrategy = .useDefaultKeys
        encoder.dateEncodingStrategy = .deferredToDate
        encoder.dataEncodingStrategy = .base64
        encoder.nonConformingFloatEncodingStrategy = .throw
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        decoder.dateDecodingStrategy = .deferredToDate
        decoder.dataDecodingStrategy = .base64
        decoder.nonConformingFloatDecodingStrategy = .throw
        return decoder
    }
}

/// Validates every object shape and every string that feeds a preconditioned
/// identifier before `JSONDecoder` is allowed to construct domain values.
private enum RewardedAdRecoveryRawShapeV1 {
    private enum Failure: Error { case invalid }

    static func validate(_ data: Data) throws {
        let root: Any
        do {
            root = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw Failure.invalid
        }
        let envelope = try object(
            root,
            keys: ["format", "schemaVersion", "challenge"]
        )
        guard try string(envelope["format"])
                == RewardedAdRecoveryJournalV1.formatIdentifier,
              try integer(envelope["schemaVersion"])
                == RewardedAdRecoveryJournalV1.currentSchemaVersion else {
            throw Failure.invalid
        }

        let challenge = try object(
            envelope["challenge"],
            keys: [
                "schemaVersion", "attempt", "verificationHandle",
                "providerCustomData",
            ]
        )
        guard try integer(challenge["schemaVersion"])
                == RewardedAdVerificationChallengeV1.currentSchemaVersion,
              RewardedAdRecoveryJournalLimitsV1.isValidOpaqueToken(
                try string(challenge["verificationHandle"])
              ),
              RewardedAdRecoveryJournalLimitsV1.isValidOpaqueToken(
                try string(challenge["providerCustomData"])
              ) else {
            throw Failure.invalid
        }

        let attempt = try object(
            challenge["attempt"],
            keys: [
                "binding", "presentationSessionNonce", "offerID", "attemptID",
            ]
        )
        let binding = try object(
            attempt["binding"],
            keys: ["accountKey", "profileID"]
        )
        let accountKey = try string(binding["accountKey"])
        let offerID = try string(attempt["offerID"])
        guard RewardedAdRecoveryJournalLimitsV1.isValidBoundedIdentifier(
                accountKey,
                maximumBytes: RewardedAdRecoveryJournalLimitsV1
                    .maximumAccountKeyBytes
              ),
              RewardedAdRecoveryJournalLimitsV1.isValidBoundedIdentifier(
                offerID,
                maximumBytes: RewardedAdRecoveryJournalLimitsV1
                    .maximumOfferIDBytes
              ),
              RewardedAdRecoveryJournalLimitsV1.isCanonicalRewardOfferID(
                offerID
              ),
              try nonzeroUUID(binding["profileID"]),
              try nonzeroUUID(attempt["presentationSessionNonce"]),
              try nonzeroUUID(attempt["attemptID"]) else {
            throw Failure.invalid
        }
    }

    private static func object(
        _ value: Any?,
        keys: Set<String>
    ) throws -> [String: Any] {
        guard let object = value as? [String: Any],
              Set(object.keys) == keys else {
            throw Failure.invalid
        }
        return object
    }

    private static func string(_ value: Any?) throws -> String {
        guard let value = value as? String else { throw Failure.invalid }
        return value
    }

    private static func integer(_ value: Any?) throws -> Int {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else {
            throw Failure.invalid
        }
        let double = number.doubleValue
        guard double.isFinite,
              double.rounded(.towardZero) == double,
              double >= Double(Int.min), double <= Double(Int.max) else {
            throw Failure.invalid
        }
        return number.intValue
    }

    private static func nonzeroUUID(_ value: Any?) throws -> Bool {
        guard let uuid = UUID(uuidString: try string(value)) else {
            throw Failure.invalid
        }
        return uuid != RewardedAdRecoveryJournalLimitsV1.zeroUUID
    }
}

/// Bounded JSON syntax and duplicate-member validation. Foundation keeps only
/// the final duplicate value, so this must run before keyed decoding.
private enum RewardedAdRecoveryRawJSONPreflightV1 {
    private enum Failure: Error { case invalid }

    static func validate(_ data: Data) throws {
        guard data.count
                <= RewardedAdRecoveryJournalLimitsV1.maximumJournalBytes,
              String(data: data, encoding: .utf8) != nil else {
            throw Failure.invalid
        }
        var parser = Parser(bytes: Array(data))
        try parser.parseDocument()
    }

    private struct Parser {
        let bytes: [UInt8]
        var index = 0
        var tokenCount = 0

        mutating func parseDocument() throws {
            skipWhitespace()
            try parseValue(depth: 0)
            skipWhitespace()
            guard index == bytes.count else { throw Failure.invalid }
        }

        mutating func parseValue(depth: Int) throws {
            try consumeToken()
            guard index < bytes.count else { throw Failure.invalid }
            switch bytes[index] {
            case 0x7b: try parseObject(depth: depth)
            case 0x5b: try parseArray(depth: depth)
            case 0x22: _ = try parseString(returnValue: false)
            case 0x74: try consumeLiteral([0x74, 0x72, 0x75, 0x65])
            case 0x66: try consumeLiteral([0x66, 0x61, 0x6c, 0x73, 0x65])
            case 0x6e: try consumeLiteral([0x6e, 0x75, 0x6c, 0x6c])
            case 0x2d, 0x30 ... 0x39: try parseNumber()
            default: throw Failure.invalid
            }
        }

        mutating func parseObject(depth: Int) throws {
            guard depth < RewardedAdRecoveryJournalLimitsV1.maximumJSONDepth else {
                throw Failure.invalid
            }
            index += 1
            skipWhitespace()
            if consume(0x7d) { return }
            var names: Set<String> = []
            while true {
                try consumeToken()
                guard index < bytes.count, bytes[index] == 0x22,
                      let name = try parseString(returnValue: true),
                      names.insert(name).inserted else {
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
            guard depth < RewardedAdRecoveryJournalLimitsV1.maximumJSONDepth else {
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

        mutating func parseString(returnValue: Bool) throws -> String? {
            guard consume(0x22) else { throw Failure.invalid }
            var decoded: [UInt8] = []
            while index < bytes.count {
                let byte = bytes[index]
                index += 1
                if byte == 0x22 {
                    guard returnValue else { return nil }
                    guard let value = String(bytes: decoded, encoding: .utf8) else {
                        throw Failure.invalid
                    }
                    return value
                }
                guard byte >= 0x20 else { throw Failure.invalid }
                if byte != 0x5c {
                    if returnValue { decoded.append(byte) }
                    continue
                }
                guard index < bytes.count else { throw Failure.invalid }
                let escape = bytes[index]
                index += 1
                switch escape {
                case 0x22, 0x5c, 0x2f:
                    if returnValue { decoded.append(escape) }
                case 0x62:
                    if returnValue { decoded.append(0x08) }
                case 0x66:
                    if returnValue { decoded.append(0x0c) }
                case 0x6e:
                    if returnValue { decoded.append(0x0a) }
                case 0x72:
                    if returnValue { decoded.append(0x0d) }
                case 0x74:
                    if returnValue { decoded.append(0x09) }
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
                    if returnValue {
                        guard let scalar = Unicode.Scalar(scalarValue) else {
                            throw Failure.invalid
                        }
                        decoded.append(contentsOf: String(scalar).utf8)
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
                result <<= 4
                switch bytes[index] {
                case 0x30 ... 0x39: result += UInt16(bytes[index] - 0x30)
                case 0x41 ... 0x46: result += UInt16(bytes[index] - 0x41 + 10)
                case 0x61 ... 0x66: result += UInt16(bytes[index] - 0x61 + 10)
                default: throw Failure.invalid
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

        mutating func consumeToken() throws {
            tokenCount += 1
            guard tokenCount
                    <= RewardedAdRecoveryJournalLimitsV1
                        .maximumJSONStructuralTokens else {
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

        mutating func consumeDigit(in range: ClosedRange<UInt8>) -> Bool {
            guard index < bytes.count, range.contains(bytes[index]) else {
                return false
            }
            index += 1
            return true
        }
    }
}

private struct RewardedAdRecoveryLocationsV1: Sendable {
    let directoryURL: URL
    let primaryURL: URL
    let backupURL: URL
    let quarantineDirectoryURL: URL
    let sharedProfileTransactionLockURL: URL

    init(profileDirectoryURL: URL) {
        let profileDirectoryURL = profileDirectoryURL.standardizedFileURL
        directoryURL = profileDirectoryURL.appendingPathComponent(
            "RewardedAdRecovery",
            isDirectory: true
        )
        primaryURL = directoryURL.appendingPathComponent(
            "rewarded-ad-recovery-journal.json"
        )
        backupURL = directoryURL.appendingPathComponent(
            "rewarded-ad-recovery-journal.backup.json"
        )
        quarantineDirectoryURL = directoryURL.appendingPathComponent(
            "Quarantine",
            isDirectory: true
        )
        // This is intentionally the same lock used by profile persistence and
        // hydration. Callers must pass the profile repository directory, not a
        // separate ad-specific root.
        sharedProfileTransactionLockURL = ProfileHydrationTransactionLocations(
            profileDirectoryURL: profileDirectoryURL
        ).lockURL
    }

    func quarantineSlotURL(_ index: Int) -> URL {
        quarantineDirectoryURL.appendingPathComponent(
            "rewarded-ad-recovery-evidence-\(index).json"
        )
    }
}

private struct RewardedAdRecoveryStoredResolutionV1: Sendable {
    let artifact: RewardedAdRecoveryJournalArtifactV1
    let report: RewardedAdRecoveryLoadReport
}

private struct RewardedAdRecoveryJournalFileStoreV1: Sendable {
    enum CopyState {
        case missing
        case oversized(Int)
        case invalid(Data)
        case valid(RewardedAdRecoveryJournalArtifactV1)
    }

    let locations: RewardedAdRecoveryLocationsV1
    private let expectedBinding: DurableAccountBinding
    private let fileSystem: any ProfileHydrationFileSystem

    init(
        profileDirectoryURL: URL,
        expectedBinding: DurableAccountBinding,
        fileSystem: any ProfileHydrationFileSystem
            = FoundationProfileHydrationFileSystem()
    ) {
        locations = RewardedAdRecoveryLocationsV1(
            profileDirectoryURL: profileDirectoryURL
        )
        self.expectedBinding = expectedBinding
        self.fileSystem = fileSystem
    }

    func load() throws -> RewardedAdRecoveryStoredResolutionV1? {
        try withLock { try resolveLocked() }
    }

    func install(
        challenge: RewardedAdVerificationChallengeV1
    ) throws -> RewardedAdRecoveryStoredResolutionV1 {
        let candidate = try RewardedAdRecoveryJournalCodecV1.artifact(
            for: challenge
        )
        guard challenge.attempt.binding == expectedBinding else {
            throw RewardedAdRecoveryJournalError.durableOwnerMismatch
        }
        return try withLock {
            try prepareDirectory()
            guard try !hasQuarantineEvidenceLocked() else {
                throw RewardedAdRecoveryJournalError.quarantineBarrier
            }
            if let existing = try resolveLocked() {
                guard existing.artifact.exactBytes == candidate.exactBytes else {
                    throw RewardedAdRecoveryJournalError.journalAlreadyExists
                }
                return existing
            }

            try writeAndReconcileExact(
                candidate.exactBytes,
                to: locations.backupURL
            )
            try writeAndReconcileExact(
                candidate.exactBytes,
                to: locations.primaryURL
            )
            return RewardedAdRecoveryStoredResolutionV1(
                artifact: candidate,
                report: RewardedAdRecoveryLoadReport(
                    source: .primary,
                    repairedMissingOrInvalidCopy: false,
                    quarantinedURLs: []
                )
            )
        }
    }

    /// Compare-and-delete is retryable after an ambiguous durable removal. A
    /// missing copy is accepted only while every remaining copy is the exact
    /// immutable journal authorized by the caller.
    func remove(
        expected: RewardedAdRecoveryJournalArtifactV1
    ) throws {
        try withLock {
            let primary = try copyState(at: locations.primaryURL)
            let backup = try copyState(at: locations.backupURL)
            try requireExpectedOrMissing(primary, expected: expected)
            try requireExpectedOrMissing(backup, expected: expected)

            // Observation is not a durability barrier, even for a path that is
            // already absent after an earlier ambiguous removal. Re-sync both
            // parent-directory entries before acknowledging exact deletion.
            try removeAndReconcileAbsence(locations.primaryURL)
            try removeAndReconcileAbsence(locations.backupURL)
        }
    }
}

private extension RewardedAdRecoveryJournalFileStoreV1 {
    func resolveLocked() throws -> RewardedAdRecoveryStoredResolutionV1? {
        try prepareDirectory()
        let primary = try copyState(at: locations.primaryURL)
        let backup = try copyState(at: locations.backupURL)
        let existingQuarantine = try hasQuarantineEvidenceLocked()

        switch (primary, backup) {
        case (.missing, .missing):
            if existingQuarantine {
                throw RewardedAdRecoveryJournalError.quarantineBarrier
            }
            // A relaunch may observe both paths missing after the final remove
            // completed but its parent sync failed. Fresh durable absent-syncs
            // are required before absence can release the recovery barrier.
            try removeAndReconcileAbsence(locations.primaryURL)
            try removeAndReconcileAbsence(locations.backupURL)
            return nil

        case let (.valid(primaryArtifact), .valid(backupArtifact)):
            guard primaryArtifact.exactBytes == backupArtifact.exactBytes else {
                throw RewardedAdRecoveryJournalError.journalCopiesDisagree
            }
            return RewardedAdRecoveryStoredResolutionV1(
                artifact: primaryArtifact,
                report: RewardedAdRecoveryLoadReport(
                    source: .primary,
                    repairedMissingOrInvalidCopy: false,
                    quarantinedURLs: []
                )
            )

        case let (.valid(artifact), .missing):
            try writeAndReconcileExact(
                artifact.exactBytes,
                to: locations.backupURL
            )
            return repaired(
                artifact,
                source: .primary,
                quarantinedURLs: []
            )

        case let (.missing, .valid(artifact)):
            try writeAndReconcileExact(
                artifact.exactBytes,
                to: locations.primaryURL
            )
            return repaired(
                artifact,
                source: .backup,
                quarantinedURLs: []
            )

        case let (.valid(artifact), .invalid(bytes)):
            let quarantined = try quarantine(
                locations.backupURL,
                exactBytes: bytes
            )
            try writeAndReconcileExact(
                artifact.exactBytes,
                to: locations.backupURL
            )
            return repaired(
                artifact,
                source: .primary,
                quarantinedURLs: [quarantined]
            )

        case let (.invalid(bytes), .valid(artifact)):
            let quarantined = try quarantine(
                locations.primaryURL,
                exactBytes: bytes
            )
            try writeAndReconcileExact(
                artifact.exactBytes,
                to: locations.primaryURL
            )
            return repaired(
                artifact,
                source: .backup,
                quarantinedURLs: [quarantined]
            )

        case let (.invalid(primaryBytes), .invalid(backupBytes)):
            _ = try quarantine(
                locations.primaryURL,
                exactBytes: primaryBytes
            )
            _ = try quarantine(
                locations.backupURL,
                exactBytes: backupBytes
            )
            throw RewardedAdRecoveryJournalError.noValidJournalCopy

        case let (.invalid(bytes), .missing):
            _ = try quarantine(locations.primaryURL, exactBytes: bytes)
            throw RewardedAdRecoveryJournalError.noValidJournalCopy

        case let (.missing, .invalid(bytes)):
            _ = try quarantine(locations.backupURL, exactBytes: bytes)
            throw RewardedAdRecoveryJournalError.noValidJournalCopy

        case let (.oversized(size), _), let (_, .oversized(size)):
            // Moving an unbounded file would make the quarantine itself an
            // unbounded storage primitive. Leave it in place as a hard barrier.
            throw RewardedAdRecoveryJournalError.journalTooLarge(
                actual: size,
                maximum: RewardedAdRecoveryJournalLimitsV1.maximumJournalBytes
            )
        }
    }

    func repaired(
        _ artifact: RewardedAdRecoveryJournalArtifactV1,
        source: RewardedAdRecoveryLoadSource,
        quarantinedURLs: [URL]
    ) -> RewardedAdRecoveryStoredResolutionV1 {
        RewardedAdRecoveryStoredResolutionV1(
            artifact: artifact,
            report: RewardedAdRecoveryLoadReport(
                source: source,
                repairedMissingOrInvalidCopy: true,
                quarantinedURLs: quarantinedURLs
            )
        )
    }

    func copyState(at url: URL) throws -> CopyState {
        let status: ProfileHydrationFileItemStatus
        do {
            status = try fileSystem.itemStatus(at: url)
        } catch {
            throw mapped(error)
        }
        guard status == .present else { return .missing }

        let size: Int
        do {
            size = try fileSystem.fileSize(at: url)
        } catch {
            throw mapped(error)
        }
        guard size >= 0,
              size <= RewardedAdRecoveryJournalLimitsV1.maximumJournalBytes else {
            return .oversized(max(0, size))
        }
        let data: Data
        do {
            data = try fileSystem.read(from: url)
        } catch {
            throw mapped(error)
        }
        guard data.count
                <= RewardedAdRecoveryJournalLimitsV1.maximumJournalBytes else {
            return .oversized(data.count)
        }
        do {
            let artifact = try RewardedAdRecoveryJournalCodecV1
                .decodeArtifact(data)
            guard artifact.journal.challenge.attempt.binding
                    == expectedBinding else {
                // Valid evidence owned by another account is neither corrupt
                // nor ours to repair, copy, quarantine, query, or delete.
                throw RewardedAdRecoveryJournalError.durableOwnerMismatch
            }
            return .valid(artifact)
        } catch let error as RewardedAdRecoveryJournalError
            where error == .durableOwnerMismatch {
            throw error
        } catch {
            return .invalid(data)
        }
    }

    func requireExpectedOrMissing(
        _ state: CopyState,
        expected: RewardedAdRecoveryJournalArtifactV1
    ) throws {
        switch state {
        case .missing:
            return
        case let .valid(artifact):
            guard artifact.exactBytes == expected.exactBytes else {
                throw RewardedAdRecoveryJournalError.challengeMismatch
            }
        case .invalid, .oversized:
            throw RewardedAdRecoveryJournalError.noValidJournalCopy
        }
    }

    func prepareDirectory() throws {
        do {
            try fileSystem.createDirectory(at: locations.directoryURL)
        } catch {
            throw mapped(error)
        }
    }

    func hasQuarantineEvidenceLocked() throws -> Bool {
        for index in 0 ..< RewardedAdRecoveryJournalLimitsV1
            .maximumQuarantineFiles {
            do {
                if try fileSystem.itemStatus(
                    at: locations.quarantineSlotURL(index)
                ) == .present {
                    return true
                }
            } catch {
                throw mapped(error)
            }
        }
        return false
    }

    func quarantine(_ url: URL, exactBytes: Data) throws -> URL {
        guard exactBytes.count
                <= RewardedAdRecoveryJournalLimitsV1.maximumJournalBytes else {
            throw RewardedAdRecoveryJournalError.journalTooLarge(
                actual: exactBytes.count,
                maximum: RewardedAdRecoveryJournalLimitsV1.maximumJournalBytes
            )
        }
        do {
            try fileSystem.createDirectory(at: locations.quarantineDirectoryURL)
        } catch {
            throw mapped(error)
        }
        for index in 0 ..< RewardedAdRecoveryJournalLimitsV1
            .maximumQuarantineFiles {
            let destination = locations.quarantineSlotURL(index)
            let status: ProfileHydrationFileItemStatus
            do {
                status = try fileSystem.itemStatus(at: destination)
            } catch {
                throw mapped(error)
            }
            guard status == .missing else { continue }
            do {
                try fileSystem.moveItemDurably(at: url, to: destination)
                guard try fileSystem.itemStatus(at: url) == .missing,
                      try fileSystem.itemStatus(at: destination) == .present,
                      try fileSystem.fileSize(at: destination)
                        == exactBytes.count,
                      try fileSystem.read(from: destination) == exactBytes else {
                    throw RewardedAdRecoveryJournalError.ioFailure
                }
                return destination
            } catch let error as RewardedAdRecoveryJournalError {
                throw error
            } catch {
                throw mapped(error)
            }
        }
        throw RewardedAdRecoveryJournalError.quarantineCapacityExceeded
    }

    func writeAndReconcileExact(_ data: Data, to url: URL) throws {
        do {
            try fileSystem.writeAtomicallyDurably(data, to: url)
        } catch {
            let writeError = mapped(error)
            guard writeError == .atomicWriteOutcomeUnknown else {
                throw writeError
            }
            // Seeing the renamed bytes is not a durability barrier. Repeat the
            // exact write so a fresh file sync, rename, and parent sync must
            // all succeed before returning authority to the caller.
            do {
                try fileSystem.writeAtomicallyDurably(data, to: url)
            } catch {
                throw self.mapped(error)
            }
        }

        do {
            guard try fileSystem.itemStatus(at: url) == .present,
                  try fileSystem.fileSize(at: url) == data.count,
                  try fileSystem.read(from: url) == data else {
                throw RewardedAdRecoveryJournalError.atomicWriteOutcomeUnknown
            }
        } catch let error as RewardedAdRecoveryJournalError {
            throw error
        } catch {
            throw RewardedAdRecoveryJournalError.atomicWriteOutcomeUnknown
        }
    }

    func removeAndReconcileAbsence(_ url: URL) throws {
        do {
            try fileSystem.removeItemDurably(at: url)
        } catch {
            // Removal may have happened before the parent-directory sync
            // failed. Repeating durable removal while absent obtains a fresh
            // parent sync; absence observation by itself is not durability.
            do {
                try fileSystem.removeItemDurably(at: url)
            } catch {
                throw mapped(error)
            }
        }
        do {
            guard try fileSystem.itemStatus(at: url) == .missing else {
                throw RewardedAdRecoveryJournalError.atomicWriteOutcomeUnknown
            }
        } catch let error as RewardedAdRecoveryJournalError {
            throw error
        } catch {
            throw RewardedAdRecoveryJournalError.atomicWriteOutcomeUnknown
        }
    }

    func withLock<T>(_ operation: () throws -> T) throws -> T {
        var result: Result<T, any Error>?
        do {
            try fileSystem.withExclusiveLock(
                at: locations.sharedProfileTransactionLockURL
            ) {
                result = Result { try operation() }
            }
        } catch {
            throw mapped(error)
        }
        guard let result else {
            throw RewardedAdRecoveryJournalError.ioFailure
        }
        do {
            return try result.get()
        } catch let error as RewardedAdRecoveryJournalError {
            throw error
        } catch {
            throw RewardedAdRecoveryJournalError.ioFailure
        }
    }

    func mapped(_ error: any Error) -> RewardedAdRecoveryJournalError {
        if let error = error as? RewardedAdRecoveryJournalError {
            return error
        }
        if let error = error as? ProfileHydrationFileSystemError {
            switch error {
            case .lockContended: return .lockContended
            case .atomicWriteOutcomeUnknown: return .atomicWriteOutcomeUnknown
            case .ioFailure: return .ioFailure
            }
        }
        return .ioFailure
    }
}

/// Dormant, explicit-operation recovery boundary. Initialization performs no
/// I/O and starts no task or timer. The journal never presents an ad, polls a
/// server, or grants coins; callers recover its challenge and explicitly ask
/// `RewardedAdVerificationClient` for a fresh checked status.
actor RewardedAdRecoveryCoordinator {
    private let store: RewardedAdRecoveryJournalFileStoreV1
    private let expectedBinding: DurableAccountBinding
    private var deliveryInFlightAttemptID: UUID?

    /// Release construction remains sealed until the trusted account/runtime
    /// file owns both this path and the current-binding authority.
    fileprivate init(
        profileDirectoryURL: URL,
        expectedBinding: DurableAccountBinding
    ) {
        self.expectedBinding = expectedBinding
        store = RewardedAdRecoveryJournalFileStoreV1(
            profileDirectoryURL: profileDirectoryURL,
            expectedBinding: expectedBinding
        )
    }

#if DEBUG
    init(
        testingProfileDirectoryURL: URL,
        expectedBinding: DurableAccountBinding,
        fileSystem: any ProfileHydrationFileSystem
    ) {
        self.expectedBinding = expectedBinding
        store = RewardedAdRecoveryJournalFileStoreV1(
            profileDirectoryURL: testingProfileDirectoryURL,
            expectedBinding: expectedBinding,
            fileSystem: fileSystem
        )
    }
#endif

    func installPreparedChallenge(
        _ challenge: RewardedAdVerificationChallengeV1,
        originalPresentationSession: ActiveAccountSession
    ) throws -> RewardedAdRecoverySnapshot {
        guard challenge.attempt.binding == originalPresentationSession.binding else {
            throw RewardedAdRecoveryJournalError.durableOwnerMismatch
        }
        guard challenge.attempt.presentationSession
                == originalPresentationSession else {
            throw RewardedAdRecoveryJournalError.presentationSessionMismatch
        }
        let resolved = try store.install(challenge: challenge)
        return snapshot(resolved)
    }

    /// Presence is the barrier: a recovered challenge is status-polled and is
    /// never used to re-present the provider UI.
    func recoverPreparedChallenge(
        currentBinding: DurableAccountBinding
    ) throws -> RewardedAdRecoverySnapshot? {
        guard currentBinding == expectedBinding else {
            throw RewardedAdVerificationError.durableOwnerMismatch
        }
        return try store.load().map(snapshot)
    }

    func handleCheckedStatus(
        _ observation: RewardedAdCheckedStatusObservation,
        currentBinding: DurableAccountBinding
    ) throws -> RewardedAdRecoveryCheckedStatusDisposition {
        guard currentBinding == expectedBinding,
              observation.challenge.attempt.binding == currentBinding else {
            throw RewardedAdVerificationError.durableOwnerMismatch
        }
        let expected = try requireCurrentArtifact(
            matching: observation.challenge
        )
        // The future trusted runtime must source this from its exact current
        // account authority. The journal intentionally has no persisted or
        // independently constructible account-session authority of its own.
        switch observation.outcome {
        case .pending:
            return .pending
        case let .terminalRejected(reason):
            guard deliveryInFlightAttemptID
                    != observation.challenge.attempt.attemptID else {
                throw RewardedAdRecoveryJournalError.deliveryAlreadyInProgress
            }
            try store.remove(expected: expected)
            return .terminalRejected(reason)
        case let .verified(claim):
            guard claim.challenge == observation.challenge else {
                throw RewardedAdRecoveryJournalError.statusObservationMismatch
            }
            return .verified(claim)
        }
    }

    /// Only the fresh process claim inside a sealed checked observation can
    /// form the downstream request. The current durable binding and profile
    /// session remain process-only and the durable economy coordinator still
    /// enforces its exact current session after this actor becomes reentrant.
    func deliverVerifiedReward(
        checked observation: RewardedAdCheckedStatusObservation,
        currentSession: ProfileSessionToken,
        currentBinding: DurableAccountBinding,
        using deliverer: any VerifiedRewardedAdDurableCreditDelivering
    ) async throws -> DurableRewardedAdDeliveryResult {
        guard currentBinding == expectedBinding,
              observation.challenge.attempt.binding == currentBinding else {
            throw RewardedAdVerificationError.durableOwnerMismatch
        }
        let expected = try requireCurrentArtifact(
            matching: observation.challenge
        )
        guard case let .verified(claim) = observation.outcome,
              claim.challenge == observation.challenge else {
            throw RewardedAdRecoveryJournalError.statusObservationMismatch
        }
        let attemptID = observation.challenge.attempt.attemptID
        guard deliveryInFlightAttemptID == nil else {
            throw RewardedAdRecoveryJournalError.deliveryAlreadyInProgress
        }
        let request = try claim.durableDeliveryRequest(
            session: currentSession,
            currentBinding: currentBinding
        )
        deliveryInFlightAttemptID = attemptID
        defer { deliveryInFlightAttemptID = nil }

        let result = try await deliverer.deliverVerifiedReward(request)
        try validateDeliveryResult(
            result,
            claim: claim,
            currentSession: currentSession,
            currentBinding: currentBinding
        )

        // Re-read after the await. A successful delivery is idempotent, while
        // journal deletion remains exact-CAS and retryable after any ambiguity.
        _ = try requireCurrentArtifact(matching: observation.challenge)
        try store.remove(expected: expected)
        return result
    }
}

private extension RewardedAdRecoveryCoordinator {
    func snapshot(
        _ resolution: RewardedAdRecoveryStoredResolutionV1
    ) -> RewardedAdRecoverySnapshot {
        RewardedAdRecoverySnapshot(
            challenge: resolution.artifact.journal.challenge,
            report: resolution.report
        )
    }

    func requireCurrentArtifact(
        matching challenge: RewardedAdVerificationChallengeV1
    ) throws -> RewardedAdRecoveryJournalArtifactV1 {
        guard let resolution = try store.load() else {
            throw RewardedAdRecoveryJournalError.challengeMismatch
        }
        guard resolution.artifact.journal.challenge == challenge else {
            throw RewardedAdRecoveryJournalError.challengeMismatch
        }
        return resolution.artifact
    }

    func validateDeliveryResult(
        _ result: DurableRewardedAdDeliveryResult,
        claim: VerifiedRewardedAdClaim,
        currentSession: ProfileSessionToken,
        currentBinding: DurableAccountBinding
    ) throws {
        let receipt = claim.receipt
        let outcome = result.outcome
        guard receipt.binding == currentBinding,
              result.authorizesJournalDeletion(
                currentSession: currentSession,
                currentBinding: currentBinding,
                offerID: receipt.offerID,
                providerTransactionID: receipt.providerTransactionID,
                rewardedAt: receipt.rewardedAt
              ),
              outcome.offerID == receipt.offerID,
              outcome.providerTransactionID == receipt.providerTransactionID,
              outcome.ledgerEntryID == CoinLedgerID.rewardedAd(
                providerTransactionID: receipt.providerTransactionID
              ),
              outcome.coins == PersistedEconomyRulesV1.rewardedAdCoins else {
            throw RewardedAdRecoveryJournalError.deliveryResultMismatch
        }
        // Both values are exact durable success: false means the operation was
        // committed by this call; true means its identical prior commit was
        // found. Merely beginning or ambiguously failing delivery never gets
        // here and therefore never clears the journal.
        _ = outcome.wasAlreadySettled
        switch result.cloudReceipt.status {
        case .committed, .alreadyCommitted, .committedThenRefreshed:
            break
        }
    }
}

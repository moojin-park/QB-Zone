import Foundation

/// Versioned ordering-key syntax shared by local profile stamps and their
/// cloud replicas. The rule is byte-based so every implementation compares the
/// same finite ASCII domain without locale or Unicode-normalization behavior.
enum ProfileStampDeviceIDRuleV1 {
    static let semanticIdentifier =
        "pocket-vector-profile-stamp-device-id-rule-v1"
    static let minimumUTF8ByteCount = 1
    static let maximumUTF8ByteCount = 64

    /// Ordered material suitable for configuration-scope fingerprints.
    static let fingerprintMaterial = [
        semanticIdentifier,
        "lengthUnit", "utf8-byte",
        "minimumByteCount", String(minimumUTF8ByteCount),
        "maximumByteCount", String(maximumUTF8ByteCount),
        "firstByteClass", "ascii-alphanumeric",
        "remainingByteClass", "ascii-alphanumeric-or-bytes-45-46-95",
    ]

    static func isValid(_ value: String) -> Bool {
        let bytes = value.utf8
        guard (minimumUTF8ByteCount ... maximumUTF8ByteCount)
            .contains(bytes.count),
              let first = bytes.first,
              isASCIIAlphaNumeric(first)
        else {
            return false
        }
        return bytes.dropFirst().allSatisfy { byte in
            isASCIIAlphaNumeric(byte) || byte == 45 || byte == 46 || byte == 95
        }
    }

    private static func isASCIIAlphaNumeric(_ byte: UInt8) -> Bool {
        (byte >= 65 && byte <= 90)
            || (byte >= 97 && byte <= 122)
            || (byte >= 48 && byte <= 57)
    }
}

struct Stamped<Value: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    var value: Value
    var modifiedAt: Date
    var deviceID: String
    var logicalCounter: UInt64

    init(
        value: Value,
        modifiedAt: Date,
        deviceID: String,
        logicalCounter: UInt64
    ) {
        self.value = value
        self.modifiedAt = modifiedAt
        self.deviceID = deviceID
        self.logicalCounter = logicalCounter
    }
}

struct PlayerSettings: Codable, Equatable, Sendable {
    var musicVolume: Double
    var sfxVolume: Double
    var isMuted: Bool
    var reducedMotion: Bool
    var tutorialCompleted: Bool

    enum CodingKeys: String, CodingKey, CaseIterable {
        case musicVolume
        case sfxVolume
        case isMuted
        case reducedMotion
        case tutorialCompleted
    }

    static var persistedFieldManifest: String {
        CodingKeys.allCases.map(\.rawValue).sorted().joined(separator: ",")
    }

    init(
        musicVolume: Double = 0.38,
        sfxVolume: Double = 0.72,
        isMuted: Bool = false,
        reducedMotion: Bool = false,
        tutorialCompleted: Bool = false
    ) {
        self.musicVolume = min(1, max(0, musicVolume))
        self.sfxVolume = min(1, max(0, sfxVolume))
        self.isMuted = isMuted
        self.reducedMotion = reducedMotion
        self.tutorialCompleted = tutorialCompleted
    }
}

struct PlayerSelection: Codable, Equatable, Sendable {
    var selectedTeamID: TeamID
    var selectedJerseyByTeam: [TeamID: JerseyID]
    var selectedFootballID: FootballID

    enum CodingKeys: String, CodingKey, CaseIterable {
        case selectedTeamID
        case selectedJerseyByTeam
        case selectedFootballID
    }

    static var persistedFieldManifest: String {
        CodingKeys.allCases.map(\.rawValue).sorted().joined(separator: ",")
    }

    var selectedJerseyID: JerseyID? {
        selectedJerseyByTeam[selectedTeamID]
    }
}

struct PlayerInventory: Codable, Equatable, Sendable {
    var ownedTeamIDs: Set<TeamID>
    var ownedJerseyIDs: Set<JerseyID>
    var ownedFootballIDs: Set<FootballID>

    init(
        ownedTeamIDs: Set<TeamID> = [],
        ownedJerseyIDs: Set<JerseyID> = [],
        ownedFootballIDs: Set<FootballID> = []
    ) {
        self.ownedTeamIDs = ownedTeamIDs
        self.ownedJerseyIDs = ownedJerseyIDs
        self.ownedFootballIDs = ownedFootballIDs
    }
}

struct CareerStatistics: Codable, Equatable, Sendable {
    static let achievementDependencySemanticIdentifier =
        "pocket-vector-career-statistics-achievement-dependencies-v1"
    static let successfulPassesPolicyIdentifier =
        "completions-plus-touchdowns-native-int-v1"

    var completedRuns = 0
    var rewardEligibleRuns = 0
    var attempts = 0
    var completions = 0
    var touchdowns = 0
    var incompletions = 0
    var interceptions = 0
    var bonusTouchdowns = 0
    var highestScore = 0
    var totalScore: Int64 = 0

    var successfulPasses: Int {
        completions + touchdowns
    }

    static var achievementDependencyFingerprintMaterial: [String] {
        [
            achievementDependencySemanticIdentifier,
            "successfulPassesPolicy", successfulPassesPolicyIdentifier,
        ]
    }

    mutating func apply(_ run: CompletedRun) {
        guard run.isNaturallyCompleted else { return }
        completedRuns += 1
        if run.isRewardEligible {
            rewardEligibleRuns += 1
        }
        attempts += run.statistics.attempts
        completions += run.statistics.completions
        touchdowns += run.statistics.touchdowns
        incompletions += run.statistics.incompletions
        interceptions += run.statistics.interceptions
        bonusTouchdowns += max(0, run.bonusTouchdownCount)
        highestScore = max(highestScore, run.score)
        totalScore += Int64(max(0, run.score))
    }
}

struct PlayerDocumentV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    var profileID: UUID
    var revision: UInt64
    var createdAt: Date
    var settings: Stamped<PlayerSettings>
    var selection: Stamped<PlayerSelection>
    var inventory: PlayerInventory
    var completedRuns: [RunID: CompletedRunRecord]
    var ledger: [LedgerEntryID: CoinLedgerEntry]
    var career: CareerStatistics
    var achievementProgress: [AchievementID: AchievementProgress]
    var rewardedAdState: RewardedAdState
    var pendingGameCenter: GameCenterSubmissionQueue
}

enum ProfileSyncStatus: String, Codable, Equatable, Sendable {
    case localOnly
    case syncing
    case current
    case unavailable
    case failed
}

struct PlayerSnapshot: Equatable, Sendable {
    let profileID: UUID
    let revision: UInt64
    let settings: PlayerSettings
    let selection: PlayerSelection
    let inventory: PlayerInventory
    let career: CareerStatistics
    let coinBalance: Int64
    let achievementProgress: [AchievementID: AchievementProgress]
    let rewardedAdState: RewardedAdState
    let syncStatus: ProfileSyncStatus

    var commerceIsAvailable: Bool {
        syncStatus == .current
    }
}

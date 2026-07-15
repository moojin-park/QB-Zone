import Foundation

struct TeamID: RawRepresentable, Codable, Hashable, Sendable, CustomStringConvertible {
    let rawValue: String

    init(rawValue: String) {
        precondition(!rawValue.isEmpty, "TeamID cannot be empty")
        self.rawValue = rawValue
    }

    init(_ rawValue: String) {
        self.init(rawValue: rawValue)
    }

    var description: String { rawValue }
}

struct JerseyID: RawRepresentable, Codable, Hashable, Sendable, CustomStringConvertible {
    let rawValue: String

    init(rawValue: String) {
        precondition(!rawValue.isEmpty, "JerseyID cannot be empty")
        self.rawValue = rawValue
    }

    init(_ rawValue: String) {
        self.init(rawValue: rawValue)
    }

    var description: String { rawValue }
}

struct FootballID: RawRepresentable, Codable, Hashable, Sendable, CustomStringConvertible {
    let rawValue: String

    init(rawValue: String) {
        precondition(!rawValue.isEmpty, "FootballID cannot be empty")
        self.rawValue = rawValue
    }

    init(_ rawValue: String) {
        self.init(rawValue: rawValue)
    }

    var description: String { rawValue }
}

struct CatalogItemID: RawRepresentable, Codable, Hashable, Sendable, CustomStringConvertible {
    let rawValue: String

    init(rawValue: String) {
        precondition(!rawValue.isEmpty, "CatalogItemID cannot be empty")
        self.rawValue = rawValue
    }

    init(_ rawValue: String) {
        self.init(rawValue: rawValue)
    }

    var description: String { rawValue }
}

struct RunID: RawRepresentable, Codable, Hashable, Sendable, CustomStringConvertible {
    let rawValue: UUID

    init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    init(_ rawValue: UUID = UUID()) {
        self.init(rawValue: rawValue)
    }

    var description: String { rawValue.uuidString.lowercased() }
}

struct LedgerEntryID: RawRepresentable, Codable, Hashable, Sendable, CustomStringConvertible {
    let rawValue: String

    init(rawValue: String) {
        precondition(!rawValue.isEmpty, "LedgerEntryID cannot be empty")
        self.rawValue = rawValue
    }

    init(_ rawValue: String) {
        self.init(rawValue: rawValue)
    }

    var description: String { rawValue }
}

struct AchievementID: RawRepresentable, Codable, Hashable, Sendable, CustomStringConvertible {
    let rawValue: String

    init(rawValue: String) {
        precondition(!rawValue.isEmpty, "AchievementID cannot be empty")
        self.rawValue = rawValue
    }

    init(_ rawValue: String) {
        self.init(rawValue: rawValue)
    }

    var description: String { rawValue }
}

struct RewardOfferID: RawRepresentable, Codable, Hashable, Sendable, CustomStringConvertible {
    let rawValue: String

    init(rawValue: String) {
        precondition(!rawValue.isEmpty, "RewardOfferID cannot be empty")
        self.rawValue = rawValue
    }

    init(_ rawValue: String) {
        self.init(rawValue: rawValue)
    }

    var description: String { rawValue }
}

struct AdProviderTransactionID: RawRepresentable, Codable, Hashable, Sendable,
    CustomStringConvertible
{
    let rawValue: String

    init(rawValue: String) {
        precondition(!rawValue.isEmpty, "AdProviderTransactionID cannot be empty")
        self.rawValue = rawValue
    }

    init(_ rawValue: String) {
        self.init(rawValue: rawValue)
    }

    var description: String { rawValue }
}

struct OperationID: RawRepresentable, Codable, Hashable, Sendable, CustomStringConvertible {
    let rawValue: String

    init(rawValue: String) {
        precondition(!rawValue.isEmpty, "OperationID cannot be empty")
        self.rawValue = rawValue
    }

    init(_ rawValue: String) {
        self.init(rawValue: rawValue)
    }

    var description: String { rawValue }
}

struct CoinPackID: RawRepresentable, Codable, Hashable, Sendable, CustomStringConvertible {
    let rawValue: String

    init(rawValue: String) {
        precondition(!rawValue.isEmpty, "CoinPackID cannot be empty")
        self.rawValue = rawValue
    }

    init(_ rawValue: String) {
        self.init(rawValue: rawValue)
    }

    var description: String { rawValue }
}

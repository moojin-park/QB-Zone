import Foundation

enum ProductionServiceKind: Equatable, Sendable {
    case gameCenter
    case cloudKit
    case storeKit
    case rewardedAds
}

enum ProductionConfigurationField: Equatable, Sendable {
    case leaderboardIdentifier
    case achievementIdentifiers
    case cloudContainerIdentifier
    case cloudZoneName
    case cloudPayloadFieldName
    case cloudOperationRecordType
    case cloudAccountNamespace
    case cloudRecordNamespace
    case economyRecordID
    case economyRecordType
    case economyPayloadFieldName
    case productIdentifiers
}

enum ProductionConfigurationIssue: Equatable, Sendable {
    case missing(ProductionServiceKind, ProductionConfigurationField)
    case invalid(ProductionServiceKind, ProductionConfigurationField)
    case integrationPending(ProductionServiceKind)
}

enum ValidatedServiceConfiguration<Value: Equatable & Sendable>: Equatable, Sendable {
    case unavailable([ProductionConfigurationIssue])
    case validated(Value)
}

struct ProductionCloudWriteConfiguration: Equatable, Sendable {
    let transport: CloudKitCloudSyncConfiguration
    let economy: DurableEconomyCloudConfiguration
}

/// Rewarded ads require a provider and a server-side-verification service.
/// There is intentionally no constructible production value until that
/// integration has been selected and implemented.
enum RewardedAdProductionConfiguration: Equatable, Sendable {}

struct ProductionServiceConfiguration: Equatable, Sendable {
    let gameCenter: ValidatedServiceConfiguration<GameKitGameCenterConfiguration>
    let cloudWrite: ValidatedServiceConfiguration<ProductionCloudWriteConfiguration>
    let storeKit: ValidatedServiceConfiguration<StoreKit2ProductConfiguration>
    let rewardedAds: ValidatedServiceConfiguration<RewardedAdProductionConfiguration>
    let diagnostics: AppleDiagnosticsMode

    static func parse(infoDictionary: [String: Any]) -> ProductionServiceConfiguration {
        let services = dictionaryState(
            forKey: Keys.services,
            in: .value(infoDictionary)
        )

        return ProductionServiceConfiguration(
            gameCenter: parseGameCenter(
                dictionaryState(forKey: Keys.gameCenter, in: services)
            ),
            cloudWrite: parseCloudWrite(
                dictionaryState(forKey: Keys.cloudKit, in: services)
            ),
            storeKit: parseStoreKit(
                dictionaryState(forKey: Keys.storeKit, in: services)
            ),
            rewardedAds: .unavailable([.integrationPending(.rewardedAds)]),
            diagnostics: .appleOnly
        )
    }

    static func from(bundle: Bundle) -> ProductionServiceConfiguration {
        parse(infoDictionary: bundle.infoDictionary ?? [:])
    }
}

/// A validated identifier is only configuration data. It cannot advertise a
/// service as available until a later composition wave constructs and retains
/// that service's complete production runtime.
struct ProductionRuntimeCapabilities: Equatable, Sendable {
    let serviceAvailability: AppServiceAvailability

    static let appleDiagnosticsOnly = ProductionRuntimeCapabilities(
        serviceAvailability: .unconfigured
    )
}

private extension ProductionServiceConfiguration {
    enum Keys {
        static let services = "PocketVectorServices"
        static let gameCenter = "GameCenter"
        static let cloudKit = "CloudKit"
        static let storeKit = "StoreKit"

        static let leaderboardIdentifier = "LeaderboardIdentifier"
        static let achievementIdentifiers = "AchievementIdentifiers"

        static let containerIdentifier = "ContainerIdentifier"
        static let zoneName = "ZoneName"
        static let payloadFieldName = "PayloadFieldName"
        static let operationRecordType = "OperationRecordType"
        static let accountIdentifierNamespace = "AccountIdentifierNamespace"
        static let recordNameNamespace = "RecordNameNamespace"
        static let economyRecordID = "EconomyRecordID"
        static let economyRecordType = "EconomyRecordType"
        static let economyPayloadFieldName = "EconomyPayloadFieldName"

        static let productIdentifiers = "ProductIdentifiers"
    }

    enum DictionaryState {
        case missing
        case invalid
        case value([String: Any])
    }

    enum ParsedField<Value> {
        case invalid(ProductionConfigurationIssue)
        case value(Value)

        var issue: ProductionConfigurationIssue? {
            guard case let .invalid(issue) = self else { return nil }
            return issue
        }

        var value: Value? {
            guard case let .value(value) = self else { return nil }
            return value
        }
    }

    static func dictionaryState(
        forKey key: String,
        in parent: DictionaryState
    ) -> DictionaryState {
        switch parent {
        case .missing:
            return .missing
        case .invalid:
            return .invalid
        case let .value(dictionary):
            guard let value = dictionary[key] else {
                return .missing
            }
            guard let nested = value as? [String: Any] else {
                return .invalid
            }
            return .value(nested)
        }
    }

    static func requiredString(
        _ key: String,
        service: ProductionServiceKind,
        field: ProductionConfigurationField,
        in dictionary: DictionaryState
    ) -> ParsedField<String> {
        let missing = ProductionConfigurationIssue.missing(service, field)
        let invalid = ProductionConfigurationIssue.invalid(service, field)

        switch dictionary {
        case .missing:
            return .invalid(missing)
        case .invalid:
            return .invalid(invalid)
        case let .value(values):
            guard let rawValue = values[key] else {
                return .invalid(missing)
            }
            guard let value = rawValue as? String else {
                return .invalid(invalid)
            }
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else {
                return .invalid(invalid)
            }
            return .value(normalized)
        }
    }

    static func requiredStringDictionary(
        _ key: String,
        service: ProductionServiceKind,
        field: ProductionConfigurationField,
        in dictionary: DictionaryState
    ) -> ParsedField<[String: String]> {
        let missing = ProductionConfigurationIssue.missing(service, field)
        let invalid = ProductionConfigurationIssue.invalid(service, field)

        switch dictionary {
        case .missing:
            return .invalid(missing)
        case .invalid:
            return .invalid(invalid)
        case let .value(values):
            guard let rawValue = values[key] else {
                return .invalid(missing)
            }
            guard let rawDictionary = rawValue as? [String: Any] else {
                return .invalid(invalid)
            }

            var normalized: [String: String] = [:]
            normalized.reserveCapacity(rawDictionary.count)
            for (entryKey, rawEntryValue) in rawDictionary {
                guard let entryValue = rawEntryValue as? String else {
                    return .invalid(invalid)
                }
                let trimmed = entryValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    return .invalid(invalid)
                }
                normalized[entryKey] = trimmed
            }
            return .value(normalized)
        }
    }

    static func requiredSchemaIdentifier(
        _ key: String,
        service: ProductionServiceKind,
        field: ProductionConfigurationField,
        in dictionary: DictionaryState
    ) -> ParsedField<String> {
        let parsed = requiredString(
            key,
            service: service,
            field: field,
            in: dictionary
        )
        guard let value = parsed.value else {
            return parsed
        }
        guard isValidCloudSchemaIdentifier(value) else {
            return .invalid(.invalid(service, field))
        }
        return .value(value)
    }

    static func isValidCloudSchemaIdentifier(_ value: String) -> Bool {
        guard let first = value.unicodeScalars.first,
              CharacterSet.letters.union(CharacterSet(charactersIn: "_")).contains(first)
        else {
            return false
        }
        return value.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_")).contains($0)
        }
    }

    static func parseGameCenter(
        _ dictionary: DictionaryState
    ) -> ValidatedServiceConfiguration<GameKitGameCenterConfiguration> {
        let leaderboard = requiredString(
            Keys.leaderboardIdentifier,
            service: .gameCenter,
            field: .leaderboardIdentifier,
            in: dictionary
        )
        let rawAchievements = requiredStringDictionary(
            Keys.achievementIdentifiers,
            service: .gameCenter,
            field: .achievementIdentifiers,
            in: dictionary
        )

        var issues = [leaderboard.issue, rawAchievements.issue].compactMap { $0 }
        var achievementIdentifiers: [AchievementID: String]?
        if let rawAchievements = rawAchievements.value {
            let approvedByRawID = Dictionary(
                uniqueKeysWithValues: AchievementCatalog.launch.map { ($0.id.rawValue, $0.id) }
            )
            guard rawAchievements.count == approvedByRawID.count,
                  Set(rawAchievements.keys) == Set(approvedByRawID.keys),
                  Set(rawAchievements.values).count == rawAchievements.count else {
                issues.append(.invalid(.gameCenter, .achievementIdentifiers))
                return .unavailable(issues)
            }
            var approvedAchievements: [AchievementID: String] = [:]
            approvedAchievements.reserveCapacity(AchievementCatalog.launch.count)
            for achievement in AchievementCatalog.launch {
                guard let providerIdentifier = rawAchievements[achievement.id.rawValue] else {
                    issues.append(.invalid(.gameCenter, .achievementIdentifiers))
                    return .unavailable(issues)
                }
                approvedAchievements[achievement.id] = providerIdentifier
            }
            achievementIdentifiers = approvedAchievements
        }

        guard issues.isEmpty,
              let leaderboardIdentifier = leaderboard.value,
              let achievementIdentifiers else {
            return .unavailable(issues)
        }

        do {
            return .validated(
                try GameKitGameCenterConfiguration(
                    leaderboardIdentifier: leaderboardIdentifier,
                    achievementIdentifiers: achievementIdentifiers
                )
            )
        } catch {
            return .unavailable([.invalid(.gameCenter, .achievementIdentifiers)])
        }
    }

    static func parseCloudWrite(
        _ dictionary: DictionaryState
    ) -> ValidatedServiceConfiguration<ProductionCloudWriteConfiguration> {
        let containerIdentifier = requiredString(
            Keys.containerIdentifier,
            service: .cloudKit,
            field: .cloudContainerIdentifier,
            in: dictionary
        )
        let zoneName = requiredString(
            Keys.zoneName,
            service: .cloudKit,
            field: .cloudZoneName,
            in: dictionary
        )
        let payloadFieldName = requiredSchemaIdentifier(
            Keys.payloadFieldName,
            service: .cloudKit,
            field: .cloudPayloadFieldName,
            in: dictionary
        )
        let operationRecordType = requiredSchemaIdentifier(
            Keys.operationRecordType,
            service: .cloudKit,
            field: .cloudOperationRecordType,
            in: dictionary
        )
        let accountNamespace = requiredString(
            Keys.accountIdentifierNamespace,
            service: .cloudKit,
            field: .cloudAccountNamespace,
            in: dictionary
        )
        let recordNamespace = requiredString(
            Keys.recordNameNamespace,
            service: .cloudKit,
            field: .cloudRecordNamespace,
            in: dictionary
        )
        let economyRecordID = requiredString(
            Keys.economyRecordID,
            service: .cloudKit,
            field: .economyRecordID,
            in: dictionary
        )
        let economyRecordType = requiredSchemaIdentifier(
            Keys.economyRecordType,
            service: .cloudKit,
            field: .economyRecordType,
            in: dictionary
        )
        let economyPayloadFieldName = requiredSchemaIdentifier(
            Keys.economyPayloadFieldName,
            service: .cloudKit,
            field: .economyPayloadFieldName,
            in: dictionary
        )

        let fields: [ParsedField<String>] = [
            containerIdentifier,
            zoneName,
            payloadFieldName,
            operationRecordType,
            accountNamespace,
            recordNamespace,
            economyRecordID,
            economyRecordType,
            economyPayloadFieldName,
        ]
        let issues = fields.compactMap(\.issue)
        guard issues.isEmpty,
              let containerIdentifier = containerIdentifier.value,
              let zoneName = zoneName.value,
              let payloadFieldName = payloadFieldName.value,
              let operationRecordType = operationRecordType.value,
              let accountNamespace = accountNamespace.value,
              let recordNamespace = recordNamespace.value,
              let economyRecordID = economyRecordID.value,
              let economyRecordType = economyRecordType.value,
              let economyPayloadFieldName = economyPayloadFieldName.value else {
            return .unavailable(issues)
        }

        let transport: CloudKitCloudSyncConfiguration
        do {
            transport = try CloudKitCloudSyncConfiguration(
                containerIdentifier: containerIdentifier,
                zoneName: zoneName,
                payloadFieldName: payloadFieldName,
                operationRecordType: operationRecordType,
                accountIdentifierNamespace: accountNamespace,
                recordNameNamespace: recordNamespace
            )
        } catch let error as CloudKitCloudSyncConfigurationError {
            let field: ProductionConfigurationField
            switch error {
            case .emptyContainerIdentifier:
                field = .cloudContainerIdentifier
            case .emptyZoneName:
                field = .cloudZoneName
            case .invalidPayloadFieldName:
                field = .cloudPayloadFieldName
            case .invalidOperationRecordType:
                field = .cloudOperationRecordType
            case .emptyAccountIdentifierNamespace:
                field = .cloudAccountNamespace
            case .emptyRecordNameNamespace:
                field = .cloudRecordNamespace
            }
            return .unavailable([.invalid(.cloudKit, field)])
        } catch {
            return .unavailable([.invalid(.cloudKit, .cloudPayloadFieldName)])
        }

        let economy: DurableEconomyCloudConfiguration
        do {
            economy = try DurableEconomyCloudConfiguration(
                recordID: CloudRecordID(economyRecordID),
                recordType: economyRecordType,
                payloadFieldName: economyPayloadFieldName
            )
        } catch let error as DurableEconomyCloudConfigurationError {
            let field: ProductionConfigurationField
            switch error {
            case .emptyRecordID:
                field = .economyRecordID
            case .emptyRecordType:
                field = .economyRecordType
            case .emptyPayloadFieldName:
                field = .economyPayloadFieldName
            case .invalidConflictRetryLimit:
                field = .economyPayloadFieldName
            }
            return .unavailable([.invalid(.cloudKit, field)])
        } catch {
            return .unavailable([.invalid(.cloudKit, .economyPayloadFieldName)])
        }

        return .validated(
            ProductionCloudWriteConfiguration(
                transport: transport,
                economy: economy
            )
        )
    }

    static func parseStoreKit(
        _ dictionary: DictionaryState
    ) -> ValidatedServiceConfiguration<StoreKit2ProductConfiguration> {
        let rawProductIdentifiers = requiredStringDictionary(
            Keys.productIdentifiers,
            service: .storeKit,
            field: .productIdentifiers,
            in: dictionary
        )
        if let issue = rawProductIdentifiers.issue {
            return .unavailable([issue])
        }
        guard let rawProductIdentifiers = rawProductIdentifiers.value else {
            return .unavailable([.invalid(.storeKit, .productIdentifiers)])
        }

        let approvedByRawID = Dictionary(
            uniqueKeysWithValues: EconomyConfiguration.coinPacks.map { ($0.id.rawValue, $0.id) }
        )
        guard rawProductIdentifiers.count == approvedByRawID.count,
              Set(rawProductIdentifiers.keys) == Set(approvedByRawID.keys),
              Set(rawProductIdentifiers.values).count == rawProductIdentifiers.count else {
            return .unavailable([.invalid(.storeKit, .productIdentifiers)])
        }
        var productIdentifiers: [CoinPackID: String] = [:]
        productIdentifiers.reserveCapacity(EconomyConfiguration.coinPacks.count)
        for pack in EconomyConfiguration.coinPacks {
            guard let providerIdentifier = rawProductIdentifiers[pack.id.rawValue] else {
                return .unavailable([.invalid(.storeKit, .productIdentifiers)])
            }
            productIdentifiers[pack.id] = providerIdentifier
        }

        do {
            return .validated(
                try StoreKit2ProductConfiguration(productIdentifiers: productIdentifiers)
            )
        } catch {
            return .unavailable([.invalid(.storeKit, .productIdentifiers)])
        }
    }
}

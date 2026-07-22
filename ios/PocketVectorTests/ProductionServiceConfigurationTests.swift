import Foundation
import XCTest

@testable import PocketVector

@MainActor
final class ProductionServiceConfigurationTests: XCTestCase {
    func testShippingPrivacyManifestDeclaresEveryDirectRequiredReasonAPI() throws {
        let manifest = try loadPropertyList(
            at: sourceRoot
                .appendingPathComponent("PocketVector")
                .appendingPathComponent("Resources")
                .appendingPathComponent("PrivacyInfo.xcprivacy")
        )
        let entries = try XCTUnwrap(
            manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]]
        )
        let reasonsByCategory = Dictionary(
            uniqueKeysWithValues: try entries.map { entry in
                (
                    try XCTUnwrap(entry["NSPrivacyAccessedAPIType"] as? String),
                    Set(try XCTUnwrap(entry["NSPrivacyAccessedAPITypeReasons"] as? [String]))
                )
            }
        )

        XCTAssertEqual(
            reasonsByCategory["NSPrivacyAccessedAPICategoryFileTimestamp"],
            ["C617.1"]
        )
        XCTAssertEqual(
            reasonsByCategory["NSPrivacyAccessedAPICategorySystemBootTime"],
            ["35F9.1"]
        )
        XCTAssertEqual(
            reasonsByCategory["NSPrivacyAccessedAPICategoryUserDefaults"],
            ["CA92.1"]
        )
    }

    func testShippingEntitlementsExcludeUnusedPushCapability() throws {
        let entitlements = try loadPropertyList(
            at: sourceRoot
                .appendingPathComponent("PocketVector")
                .appendingPathComponent("PocketVector.entitlements")
        )

        XCTAssertNil(entitlements["aps-environment"])
        XCTAssertEqual(entitlements["com.apple.developer.game-center"] as? Bool, true)
        XCTAssertEqual(
            entitlements["com.apple.developer.icloud-container-identifiers"] as? [String],
            ["iCloud.com.pocketvector.game"]
        )
    }

    func testAbsentServicesFailClosedWithEveryRequiredFieldReported() {
        let configuration = ProductionServiceConfiguration.parse(infoDictionary: [:])

        XCTAssertEqual(
            unavailableIssues(configuration.gameCenter),
            [
                .missing(.gameCenter, .leaderboardIdentifier),
                .missing(.gameCenter, .achievementIdentifiers),
            ]
        )
        XCTAssertEqual(
            unavailableIssues(configuration.cloudWrite),
            cloudFields.map { .missing(.cloudKit, $0) }
        )
        XCTAssertEqual(
            unavailableIssues(configuration.storeKit),
            [.missing(.storeKit, .productIdentifiers)]
        )
        XCTAssertEqual(
            unavailableIssues(configuration.rewardedAds),
            [.integrationPending(.rewardedAds)]
        )
        XCTAssertEqual(configuration.diagnostics, .appleOnly)
    }

    func testPartialServiceDictionariesReportOnlyMissingLeaves() {
        let info: [String: Any] = [
            "PocketVectorServices": [
                "GameCenter": [
                    "LeaderboardIdentifier": "test.leaderboard",
                ],
                "CloudKit": [
                    "ContainerIdentifier": "iCloud.test.pocket-vector",
                ],
                "StoreKit": [String: Any](),
            ] as [String: Any],
        ]

        let configuration = ProductionServiceConfiguration.parse(infoDictionary: info)

        XCTAssertEqual(
            unavailableIssues(configuration.gameCenter),
            [.missing(.gameCenter, .achievementIdentifiers)]
        )
        XCTAssertEqual(
            unavailableIssues(configuration.cloudWrite),
            Array(cloudFields.dropFirst()).map { .missing(.cloudKit, $0) }
        )
        XCTAssertEqual(
            unavailableIssues(configuration.storeKit),
            [.missing(.storeKit, .productIdentifiers)]
        )
    }

    func testMalformedRootInvalidatesEveryAffectedLeaf() {
        let configuration = ProductionServiceConfiguration.parse(
            infoDictionary: ["PocketVectorServices": "not-a-dictionary"]
        )

        XCTAssertEqual(
            unavailableIssues(configuration.gameCenter),
            [
                .invalid(.gameCenter, .leaderboardIdentifier),
                .invalid(.gameCenter, .achievementIdentifiers),
            ]
        )
        XCTAssertEqual(
            unavailableIssues(configuration.cloudWrite),
            cloudFields.map { .invalid(.cloudKit, $0) }
        )
        XCTAssertEqual(
            unavailableIssues(configuration.storeKit),
            [.invalid(.storeKit, .productIdentifiers)]
        )
    }

    func testMalformedServiceDictionariesInvalidateTheirLeaves() {
        let info: [String: Any] = [
            "PocketVectorServices": [
                "GameCenter": 1,
                "CloudKit": ["invalid"],
                "StoreKit": false,
            ] as [String: Any],
        ]

        let configuration = ProductionServiceConfiguration.parse(infoDictionary: info)

        XCTAssertEqual(
            unavailableIssues(configuration.gameCenter),
            [
                .invalid(.gameCenter, .leaderboardIdentifier),
                .invalid(.gameCenter, .achievementIdentifiers),
            ]
        )
        XCTAssertEqual(
            unavailableIssues(configuration.cloudWrite),
            cloudFields.map { .invalid(.cloudKit, $0) }
        )
        XCTAssertEqual(
            unavailableIssues(configuration.storeKit),
            [.invalid(.storeKit, .productIdentifiers)]
        )
    }

    func testWrongLeafTypesFailClosedWithoutDiscardingOtherValidation() {
        var info = validInfoDictionary()
        info = updatingService("GameCenter", in: info) {
            $0["LeaderboardIdentifier"] = 42
            $0["AchievementIdentifiers"] = ["not", "a", "dictionary"]
        }
        info = updatingService("CloudKit", in: info) {
            $0["ZoneName"] = Date(timeIntervalSince1970: 0)
        }
        info = updatingService("StoreKit", in: info) {
            $0["ProductIdentifiers"] = true
        }

        let configuration = ProductionServiceConfiguration.parse(infoDictionary: info)

        XCTAssertEqual(
            unavailableIssues(configuration.gameCenter),
            [
                .invalid(.gameCenter, .leaderboardIdentifier),
                .invalid(.gameCenter, .achievementIdentifiers),
            ]
        )
        XCTAssertEqual(
            unavailableIssues(configuration.cloudWrite),
            [.invalid(.cloudKit, .cloudZoneName)]
        )
        XCTAssertEqual(
            unavailableIssues(configuration.storeKit),
            [.invalid(.storeKit, .productIdentifiers)]
        )
    }

    func testWhitespaceOnlyStringsAndMapValuesFailClosed() {
        var info = validInfoDictionary()
        info = updatingService("GameCenter", in: info) { service in
            service["LeaderboardIdentifier"] = " \n\t "
            var identifiers = service["AchievementIdentifiers"] as! [String: Any]
            identifiers[AchievementCatalog.launch[0].id.rawValue] = "   "
            service["AchievementIdentifiers"] = identifiers
        }
        info = updatingService("CloudKit", in: info) {
            $0["AccountIdentifierNamespace"] = "\n"
        }
        info = updatingService("StoreKit", in: info) { service in
            var identifiers = service["ProductIdentifiers"] as! [String: Any]
            identifiers[EconomyConfiguration.coinPacks[0].id.rawValue] = "  "
            service["ProductIdentifiers"] = identifiers
        }

        let configuration = ProductionServiceConfiguration.parse(infoDictionary: info)

        XCTAssertEqual(
            unavailableIssues(configuration.gameCenter),
            [
                .invalid(.gameCenter, .leaderboardIdentifier),
                .invalid(.gameCenter, .achievementIdentifiers),
            ]
        )
        XCTAssertEqual(
            unavailableIssues(configuration.cloudWrite),
            [.invalid(.cloudKit, .cloudAccountNamespace)]
        )
        XCTAssertEqual(
            unavailableIssues(configuration.storeKit),
            [.invalid(.storeKit, .productIdentifiers)]
        )
    }

    func testCloudContainerEnvironmentComesOnlyFromSealedBuild() throws {
        let info = updatingService("CloudKit", in: validInfoDictionary()) {
            $0["ContainerEnvironment"] = "attacker-controlled"
        }

        let configuration = ProductionServiceConfiguration.parse(
            infoDictionary: info
        )

        guard case let .validated(cloudWrite) = configuration.cloudWrite else {
            return XCTFail(
                "The complete CloudKit write configuration should validate"
            )
        }
        XCTAssertEqual(
            cloudWrite.transport.containerEnvironment,
            CloudKitBuildEnvironment.current
        )
    }

    func testNonStringIdentifierMapValuesFailClosed() {
        var info = validInfoDictionary()
        info = updatingService("GameCenter", in: info) { service in
            var identifiers = service["AchievementIdentifiers"] as! [String: Any]
            identifiers[AchievementCatalog.launch[0].id.rawValue] = 1
            service["AchievementIdentifiers"] = identifiers
        }
        info = updatingService("StoreKit", in: info) { service in
            var identifiers = service["ProductIdentifiers"] as! [String: Any]
            identifiers[EconomyConfiguration.coinPacks[0].id.rawValue] = false
            service["ProductIdentifiers"] = identifiers
        }

        let configuration = ProductionServiceConfiguration.parse(infoDictionary: info)

        XCTAssertEqual(
            unavailableIssues(configuration.gameCenter),
            [.invalid(.gameCenter, .achievementIdentifiers)]
        )
        XCTAssertEqual(
            unavailableIssues(configuration.storeKit),
            [.invalid(.storeKit, .productIdentifiers)]
        )
    }

    func testMalformedCloudSchemaIdentifiersReportEveryAffectedField() {
        let info = updatingService("CloudKit", in: validInfoDictionary()) {
            $0["PayloadFieldName"] = "1payload"
            $0["OperationRecordType"] = "operation-marker"
            $0["EconomyRecordType"] = "economy record"
            $0["EconomyPayloadFieldName"] = "payload.value"
            $0["ProfileRootRecordType"] = "1profile"
            $0["ProfileSettingsRecordType"] = "profile-settings"
            $0["ProfileSelectionRecordType"] = "profile selection"
            $0["ProfileRunRecordType"] = "profile.run"
            $0["ProfilePayloadFieldName"] = "profile-payload"
        }

        let configuration = ProductionServiceConfiguration.parse(infoDictionary: info)

        XCTAssertEqual(
            unavailableIssues(configuration.cloudWrite),
            [
                .invalid(.cloudKit, .cloudPayloadFieldName),
                .invalid(.cloudKit, .cloudOperationRecordType),
                .invalid(.cloudKit, .economyRecordType),
                .invalid(.cloudKit, .economyPayloadFieldName),
                .invalid(.cloudKit, .profileRootRecordType),
                .invalid(.cloudKit, .profileSettingsRecordType),
                .invalid(.cloudKit, .profileSelectionRecordType),
                .invalid(.cloudKit, .profileRunRecordType),
                .invalid(.cloudKit, .profilePayloadFieldName),
            ]
        )
    }

    func testCloudRecordTypeOverlapsFailClosedForEveryCollidingLeaf() {
        let info = updatingService("CloudKit", in: validInfoDictionary()) {
            $0["OperationRecordType"] = "SharedHead"
            $0["EconomyRecordType"] = "SharedHead"
            $0["ProfileRootRecordType"] = "SharedHead"
            $0["ProfileSettingsRecordType"] = "SharedProfile"
            $0["ProfileSelectionRecordType"] = "SharedProfile"
        }

        let configuration = ProductionServiceConfiguration.parse(
            infoDictionary: info
        )

        XCTAssertEqual(
            unavailableIssues(configuration.cloudWrite),
            [
                .invalid(.cloudKit, .cloudOperationRecordType),
                .invalid(.cloudKit, .economyRecordType),
                .invalid(.cloudKit, .profileRootRecordType),
                .invalid(.cloudKit, .profileSettingsRecordType),
                .invalid(.cloudKit, .profileSelectionRecordType),
            ]
        )
    }

    func testCloudWriteValueCannotBypassRecordTypeCollisionInvariant() throws {
        let parsed = ProductionServiceConfiguration.parse(
            infoDictionary: validInfoDictionary()
        )
        guard case let .validated(base) = parsed.cloudWrite else {
            return XCTFail("The complete fixture must validate")
        }
        let collidingProfile = try CloudProfileSchemaConfiguration(
            rootRecordType: base.transport.operationRecordType,
            settingsRecordType: "ProfileSettingsOther",
            selectionRecordType: "ProfileSelectionOther",
            runRecordType: "ProfileRunOther",
            payloadFieldName: "profilePayloadOther"
        )

        XCTAssertThrowsError(
            try ProductionCloudWriteConfiguration(
                transport: base.transport,
                economy: base.economy,
                profile: collidingProfile
            )
        ) { error in
            XCTAssertEqual(
                error as? ProductionCloudWriteConfigurationError,
                .recordTypeCollision(base.transport.operationRecordType)
            )
        }
    }

    func testDuplicateProviderValuesFailClosedAfterNormalization() {
        var info = validInfoDictionary()
        info = updatingService("GameCenter", in: info) { service in
            service["AchievementIdentifiers"] = Dictionary(
                uniqueKeysWithValues: AchievementCatalog.launch.enumerated().map {
                    index, achievement in
                    (
                        achievement.id.rawValue,
                        index == 0 ? "test.duplicate" : " test.duplicate "
                    )
                }
            )
        }
        info = updatingService("StoreKit", in: info) { service in
            service["ProductIdentifiers"] = Dictionary(
                uniqueKeysWithValues: EconomyConfiguration.coinPacks.enumerated().map {
                    index, pack in
                    (pack.id.rawValue, index == 0 ? "test.coin" : " test.coin ")
                }
            )
        }

        let configuration = ProductionServiceConfiguration.parse(infoDictionary: info)

        XCTAssertEqual(
            unavailableIssues(configuration.gameCenter),
            [.invalid(.gameCenter, .achievementIdentifiers)]
        )
        XCTAssertEqual(
            unavailableIssues(configuration.storeKit),
            [.invalid(.storeKit, .productIdentifiers)]
        )
    }

    func testIncompleteIdentifierMapsFailClosed() {
        var info = validInfoDictionary()
        info = updatingService("GameCenter", in: info) { service in
            var identifiers = service["AchievementIdentifiers"] as! [String: Any]
            identifiers.removeValue(forKey: AchievementCatalog.launch[0].id.rawValue)
            service["AchievementIdentifiers"] = identifiers
        }
        info = updatingService("StoreKit", in: info) { service in
            var identifiers = service["ProductIdentifiers"] as! [String: Any]
            identifiers.removeValue(forKey: EconomyConfiguration.coinPacks[0].id.rawValue)
            service["ProductIdentifiers"] = identifiers
        }

        let configuration = ProductionServiceConfiguration.parse(infoDictionary: info)

        XCTAssertEqual(
            unavailableIssues(configuration.gameCenter),
            [.invalid(.gameCenter, .achievementIdentifiers)]
        )
        XCTAssertEqual(
            unavailableIssues(configuration.storeKit),
            [.invalid(.storeKit, .productIdentifiers)]
        )
    }

    func testIdentifierMapsWithExtraKeysFailClosed() {
        var info = validInfoDictionary()
        info = updatingService("GameCenter", in: info) { service in
            var identifiers = service["AchievementIdentifiers"] as! [String: Any]
            identifiers["achievement.unapproved.v1"] = "test.achievement.unapproved"
            service["AchievementIdentifiers"] = identifiers
        }
        info = updatingService("StoreKit", in: info) { service in
            var identifiers = service["ProductIdentifiers"] as! [String: Any]
            identifiers["unapproved"] = "test.coin.unapproved"
            service["ProductIdentifiers"] = identifiers
        }

        let configuration = ProductionServiceConfiguration.parse(infoDictionary: info)

        XCTAssertEqual(
            unavailableIssues(configuration.gameCenter),
            [.invalid(.gameCenter, .achievementIdentifiers)]
        )
        XCTAssertEqual(
            unavailableIssues(configuration.storeKit),
            [.invalid(.storeKit, .productIdentifiers)]
        )
    }

    func testExactLaunchMapsAndCloudFieldsValidateAndNormalize() throws {
        var info = validInfoDictionary()
        info = updatingService("GameCenter", in: info) {
            $0["LeaderboardIdentifier"] = "  test.leaderboard  "
        }
        info = updatingService("CloudKit", in: info) {
            $0["ContainerIdentifier"] = "  iCloud.test.pocket-vector  "
        }
        info = updatingService("StoreKit", in: info) { service in
            var identifiers = service["ProductIdentifiers"] as! [String: Any]
            identifiers[EconomyConfiguration.coinPacks[0].id.rawValue] = "  test.coin.pocket  "
            service["ProductIdentifiers"] = identifiers
        }

        let configuration = ProductionServiceConfiguration.parse(infoDictionary: info)

        guard case let .validated(gameCenter) = configuration.gameCenter else {
            return XCTFail("The exact launch Game Center map should validate")
        }
        XCTAssertEqual(gameCenter.leaderboardIdentifier, "test.leaderboard")
        XCTAssertEqual(
            Set(gameCenter.achievementIdentifiers.keys),
            Set(AchievementCatalog.launch.map(\.id))
        )
        XCTAssertNotNil(
            gameCenter.achievementIdentifiers[
                AchievementID("achievement.millenia_of_connections.v1")
            ]
        )
        XCTAssertEqual(
            gameCenter.achievementIdentifiers[
                AchievementID("achievement.millenia_of_connections.v1")
            ],
            "achievement.millenia_of_connections.v1"
        )
        XCTAssertNil(
            gameCenter.achievementIdentifiers[
                AchievementID("achievement.century_of_connections.v1")
            ]
        )

        guard case let .validated(cloudWrite) = configuration.cloudWrite else {
            return XCTFail("The complete CloudKit write configuration should validate")
        }
        XCTAssertEqual(
            cloudWrite.transport.containerIdentifier,
            "iCloud.test.pocket-vector"
        )
        XCTAssertEqual(
            cloudWrite.transport.containerEnvironment,
            CloudKitBuildEnvironment.current
        )
        XCTAssertEqual(cloudWrite.transport.zoneName, "PocketVectorPrivateZone")
        XCTAssertEqual(cloudWrite.transport.payloadFieldName, "payload")
        XCTAssertEqual(cloudWrite.transport.operationRecordType, "OperationMarker")
        XCTAssertEqual(cloudWrite.transport.accountIdentifierNamespace, "account-v1")
        XCTAssertEqual(cloudWrite.transport.recordNameNamespace, "record-v1")
        XCTAssertEqual(cloudWrite.economy.recordID, CloudRecordID("economy-head-v1"))
        XCTAssertEqual(cloudWrite.economy.recordType, "EconomyHead")
        XCTAssertEqual(cloudWrite.economy.payloadFieldName, "economyPayload")
        XCTAssertEqual(cloudWrite.profile.rootRecordType, "ProfileRoot")
        XCTAssertEqual(cloudWrite.profile.settingsRecordType, "ProfileSettings")
        XCTAssertEqual(cloudWrite.profile.selectionRecordType, "ProfileSelection")
        XCTAssertEqual(cloudWrite.profile.runRecordType, "ProfileRun")
        XCTAssertEqual(cloudWrite.profile.payloadFieldName, "profilePayload")

        guard case let .validated(storeKit) = configuration.storeKit else {
            return XCTFail("The exact launch StoreKit map should validate")
        }
        XCTAssertEqual(
            storeKit.orderedLaunchPackIDs,
            EconomyConfiguration.coinPacks.map(\.id)
        )
        XCTAssertEqual(
            try storeKit.productIdentifier(for: EconomyConfiguration.coinPacks[0].id),
            "test.coin.pocket"
        )

        XCTAssertEqual(
            unavailableIssues(configuration.rewardedAds),
            [.integrationPending(.rewardedAds)]
        )
        XCTAssertEqual(configuration.diagnostics, .appleOnly)
    }

    func testRetiredCenturyGameCenterIdentifierCannotEnterProductionConfiguration() {
        var info = validInfoDictionary()
        info = updatingService("GameCenter", in: info) { service in
            var identifiers = service["AchievementIdentifiers"]
                as! [String: Any]
            let current = "achievement.millenia_of_connections.v1"
            let retired = "achievement.century_of_connections.v1"
            identifiers[retired] = identifiers.removeValue(forKey: current)
            service["AchievementIdentifiers"] = identifiers
        }

        let configuration = ProductionServiceConfiguration.parse(
            infoDictionary: info
        )
        XCTAssertEqual(
            unavailableIssues(configuration.gameCenter),
            [.invalid(.gameCenter, .achievementIdentifiers)]
        )
    }

    func testRetiredCenturyProviderIdentifierCannotMasqueradeAsMillennia() {
        var info = validInfoDictionary()
        info = updatingService("GameCenter", in: info) { service in
            var identifiers = service["AchievementIdentifiers"]
                as! [String: Any]
            identifiers["achievement.millenia_of_connections.v1"] =
                "achievement.century_of_connections.v1"
            service["AchievementIdentifiers"] = identifiers
        }

        let configuration = ProductionServiceConfiguration.parse(
            infoDictionary: info
        )
        XCTAssertEqual(
            unavailableIssues(configuration.gameCenter),
            [.invalid(.gameCenter, .achievementIdentifiers)]
        )
    }

    func testValidConfigurationNeverAdvertisesRuntimeAvailability() {
        let configuration = ProductionServiceConfiguration.parse(
            infoDictionary: validInfoDictionary()
        )

        guard case .validated = configuration.gameCenter,
              case .validated = configuration.cloudWrite,
              case .validated = configuration.storeKit else {
            return XCTFail("The fixture must prove configuration validation is separate")
        }

        XCTAssertEqual(
            ProductionRuntimeCapabilities.appleDiagnosticsOnly.serviceAvailability,
            .unconfigured
        )
        XCTAssertFalse(
            ProductionRuntimeCapabilities.appleDiagnosticsOnly
                .serviceAvailability.rewardedAdsAreConfigured
        )
        XCTAssertFalse(
            ProductionRuntimeCapabilities.appleDiagnosticsOnly
                .serviceAvailability.purchasesAreConfigured
        )
        XCTAssertFalse(
            ProductionRuntimeCapabilities.appleDiagnosticsOnly
                .serviceAvailability.gameCenterIsConfigured
        )
        XCTAssertFalse(
            ProductionRuntimeCapabilities.appleDiagnosticsOnly
                .serviceAvailability.iCloudSyncIsConfigured
        )
    }

    func testBundleParsingUsesOnlyInjectedInfoDictionaryValues() throws {
        let fileManager = FileManager.default
        let temporaryRoot = fileManager.temporaryDirectory.appendingPathComponent(
            "PocketVectorConfigTests-\(UUID().uuidString)",
            isDirectory: true
        )
        let bundleURL = temporaryRoot.appendingPathComponent(
            "Configuration.bundle",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: bundleURL,
            withIntermediateDirectories: true
        )
        defer { try? fileManager.removeItem(at: temporaryRoot) }

        var propertyList = validInfoDictionary()
        propertyList["CFBundleIdentifier"] = "com.pocketvector.configuration-tests"
        propertyList["CFBundleName"] = "Configuration"
        propertyList["CFBundlePackageType"] = "BNDL"
        let data = try PropertyListSerialization.data(
            fromPropertyList: propertyList,
            format: .xml,
            options: 0
        )
        try data.write(to: bundleURL.appendingPathComponent("Info.plist"))

        guard let bundle = Bundle(url: bundleURL) else {
            return XCTFail("The deterministic fixture bundle should load")
        }
        XCTAssertEqual(
            ProductionServiceConfiguration.from(bundle: bundle),
            ProductionServiceConfiguration.parse(infoDictionary: propertyList)
        )
    }
}

private extension ProductionServiceConfigurationTests {
    var sourceRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func loadPropertyList(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(
            PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            ) as? [String: Any]
        )
    }

    var cloudFields: [ProductionConfigurationField] {
        [
            .cloudContainerIdentifier,
            .cloudZoneName,
            .cloudPayloadFieldName,
            .cloudOperationRecordType,
            .cloudAccountNamespace,
            .cloudRecordNamespace,
            .economyRecordID,
            .economyRecordType,
            .economyPayloadFieldName,
            .profileRootRecordType,
            .profileSettingsRecordType,
            .profileSelectionRecordType,
            .profileRunRecordType,
            .profilePayloadFieldName,
        ]
    }

    func unavailableIssues<Value: Equatable & Sendable>(
        _ configuration: ValidatedServiceConfiguration<Value>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> [ProductionConfigurationIssue] {
        guard case let .unavailable(issues) = configuration else {
            XCTFail("Expected production configuration to fail closed", file: file, line: line)
            return []
        }
        return issues
    }

    func validInfoDictionary() -> [String: Any] {
        let achievementIdentifiers = Dictionary(
            uniqueKeysWithValues: AchievementCatalog.launch.map {
                (
                    $0.id.rawValue,
                    $0.id == LaunchAchievementID.millenniaOfConnections
                        ? $0.id.rawValue
                        : "test.game-center.\($0.id.rawValue)"
                )
            }
        )
        let productIdentifiers = Dictionary(
            uniqueKeysWithValues: EconomyConfiguration.coinPacks.map {
                ($0.id.rawValue, "test.coin.\($0.id.rawValue)")
            }
        )

        return [
            "PocketVectorServices": [
                "GameCenter": [
                    "LeaderboardIdentifier": "test.leaderboard",
                    "AchievementIdentifiers": achievementIdentifiers,
                ] as [String: Any],
                "CloudKit": [
                    "ContainerIdentifier": "iCloud.test.pocket-vector",
                    "ZoneName": "PocketVectorPrivateZone",
                    "PayloadFieldName": "payload",
                    "OperationRecordType": "OperationMarker",
                    "AccountIdentifierNamespace": "account-v1",
                    "RecordNameNamespace": "record-v1",
                    "EconomyRecordID": "economy-head-v1",
                    "EconomyRecordType": "EconomyHead",
                    "EconomyPayloadFieldName": "economyPayload",
                    "ProfileRootRecordType": "ProfileRoot",
                    "ProfileSettingsRecordType": "ProfileSettings",
                    "ProfileSelectionRecordType": "ProfileSelection",
                    "ProfileRunRecordType": "ProfileRun",
                    "ProfilePayloadFieldName": "profilePayload",
                ] as [String: Any],
                "StoreKit": [
                    "ProductIdentifiers": productIdentifiers,
                ] as [String: Any],
            ] as [String: Any],
        ]
    }

    func updatingService(
        _ serviceName: String,
        in original: [String: Any],
        _ update: (inout [String: Any]) -> Void
    ) -> [String: Any] {
        var result = original
        var services = result["PocketVectorServices"] as! [String: Any]
        var service = services[serviceName] as! [String: Any]
        update(&service)
        services[serviceName] = service
        result["PocketVectorServices"] = services
        return result
    }
}

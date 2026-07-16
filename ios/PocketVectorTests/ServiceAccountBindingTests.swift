import XCTest

@testable import PocketVector

final class ServiceAccountBindingTests: XCTestCase {
    func testProfileDerivationFingerprintMaterialIsVersionedAndExact() {
        XCTAssertEqual(
            CloudAccountDerivedBindings.profileFingerprintMaterial,
            [
                "pocket-vector-private-cloud-account-binding-derivation-v1",
                "rootDomain",
                "pocket-vector-private-cloud-account-binding-v1",
                "playerIdentityDomain", "player-account-identity-v1",
                "serviceAccountKeyDomain", "service-account-key-v1",
                "profileIDDomain", "profile-id-v1",
                "digestAlgorithm", "sha256-v1",
                "componentEncoding",
                "uint64-big-endian-length-prefixed-utf8-components-v1",
                "hexEncoding", "lowercase-two-digit-hex-per-byte-v1",
                "uuidEncoding",
                "sha256-first-16-bytes-rfc9562-version-8-variant-v1",
                "serviceAccountKeyType", "ServiceAccountKey",
                "serviceAccountKeyEncoding", "single-value-raw-string-v1",
            ]
        )
    }

    func testServiceAccountKeyEncodingLabelMatchesProductionJSONShape() throws {
        let binding = DurableAccountBinding(
            accountKey: ServiceAccountKey("service-account-shape"),
            profileID: UUID(
                uuidString: "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
            )!
        )
        let payload = try DurableEconomyCloudSchema.makePayloadEncoder()
            .encode(binding)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: payload) as? [String: Any]
        )

        XCTAssertEqual(
            String(decoding: try JSONEncoder().encode(binding.accountKey), as: UTF8.self),
            "\"service-account-shape\""
        )
        XCTAssertEqual(
            object["accountKey"] as? String,
            binding.accountKey.rawValue
        )
        XCTAssertNil(object["accountKey"] as? [String: Any])
    }

    func testCloudAccountBindingsAreStableAcrossDerivations() {
        let accountID = CloudAccountID(String(repeating: "a", count: 64))

        XCTAssertEqual(
            CloudAccountDerivedBindings.derive(from: accountID),
            CloudAccountDerivedBindings.derive(from: accountID)
        )
    }

    func testCloudAccountBindingsMatchVersionedGoldenVector() {
        let bindings = CloudAccountDerivedBindings.derive(
            from: CloudAccountID(String(repeating: "a", count: 64))
        )

        XCTAssertEqual(
            bindings.playerAccountIdentity.rawValue,
            "abca1bfcb3fe2ea7cdc01adfd7276ccc5d7f031f1c13b9007728606b7d6d05d9"
        )
        XCTAssertEqual(
            bindings.durableAccountBinding.accountKey.rawValue,
            "8f178a3e9db0dee5e84ff5fb9b151eeed17539be23c917128dc79ff1e9058c41"
        )
        XCTAssertEqual(
            bindings.durableAccountBinding.profileID.uuidString.lowercased(),
            "cf32b6c9-4ed9-8efe-8ed3-b65ec181ac58"
        )
        XCTAssertEqual(
            bindings.storeAccountBinding.appAccountToken.uuidString.lowercased(),
            "9ed16459-4661-8ede-ba2e-cf53f38e4ebc"
        )
    }

    func testCloudAccountBindingsAreDomainSeparatedAndOpaque() {
        let rawAccountID = String(repeating: "private-account-value", count: 4)
        let bindings = CloudAccountDerivedBindings.derive(
            from: CloudAccountID(rawAccountID)
        )

        XCTAssertNotEqual(
            bindings.playerAccountIdentity.rawValue,
            bindings.durableAccountBinding.accountKey.rawValue
        )
        XCTAssertNotEqual(
            bindings.durableAccountBinding.profileID,
            bindings.storeAccountBinding.appAccountToken
        )
        XCTAssertFalse(bindings.playerAccountIdentity.rawValue.contains(rawAccountID))
        XCTAssertFalse(
            bindings.durableAccountBinding.accountKey.rawValue.contains(rawAccountID)
        )
        XCTAssertEqual(bindings.playerAccountIdentity.rawValue.count, 64)
        XCTAssertEqual(bindings.durableAccountBinding.accountKey.rawValue.count, 64)
        XCTAssertEqual(bindings.storeAccountBinding.account, bindings.durableAccountBinding)
    }

    func testDifferentCloudAccountsCannotShareOwnershipBindings() {
        let first = CloudAccountDerivedBindings.derive(
            from: CloudAccountID(String(repeating: "a", count: 64))
        )
        let second = CloudAccountDerivedBindings.derive(
            from: CloudAccountID(String(repeating: "b", count: 64))
        )

        XCTAssertNotEqual(first.playerAccountIdentity, second.playerAccountIdentity)
        XCTAssertNotEqual(first.durableAccountBinding, second.durableAccountBinding)
        XCTAssertNotEqual(first.storeAccountBinding, second.storeAccountBinding)
    }

    func testDerivedUUIDsUseApplicationDefinedVersionAndRFCVariant() {
        let bindings = CloudAccountDerivedBindings.derive(
            from: CloudAccountID(String(repeating: "c", count: 64))
        )

        for uuid in [
            bindings.durableAccountBinding.profileID,
            bindings.storeAccountBinding.appAccountToken,
        ] {
            let text = uuid.uuidString.lowercased()
            XCTAssertEqual(text[text.index(text.startIndex, offsetBy: 14)], "8")
            XCTAssertTrue(
                ["8", "9", "a", "b"].contains(
                    String(text[text.index(text.startIndex, offsetBy: 19)])
                )
            )
        }
    }
}

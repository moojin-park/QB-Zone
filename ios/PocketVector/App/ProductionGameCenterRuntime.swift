import CloudKit
import Foundation

private final class ProductionGameCenterOwnershipProofIdentity: Sendable {}

struct ProductionGameCenterOwnershipProof: Equatable, Sendable {
    private let identity: ProductionGameCenterOwnershipProofIdentity
    private let accountID: CloudAccountID
    private let durableBinding: DurableAccountBinding
    private let playerID: GameCenterPlayerID

    fileprivate init(
        accountID: CloudAccountID,
        durableBinding: DurableAccountBinding,
        playerID: GameCenterPlayerID
    ) {
        identity = ProductionGameCenterOwnershipProofIdentity()
        self.accountID = accountID
        self.durableBinding = durableBinding
        self.playerID = playerID
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.identity === rhs.identity
    }

    func authorizes(
        playerID: GameCenterPlayerID,
        session: ProfileSessionToken
    ) -> Bool {
        let bindings = CloudAccountDerivedBindings.derive(from: accountID)
        return self.playerID == playerID
            && bindings.durableAccountBinding == durableBinding
            && session.accountIdentity == bindings.playerAccountIdentity
            && session.profileID == durableBinding.profileID
    }
}

enum ProductionGameCenterClaimResult: Equatable, Sendable {
    case authorized(ProductionGameCenterOwnershipProof)
    case ownedByDifferentPlayer
    case unavailable
}

enum ProductionGameCenterActionOutcome: Equatable, Sendable {
    case completed
    case unavailable
    case ownedByDifferentPlayer
}

struct ProductionGameCenterClaimProviderRecord: Equatable, Sendable {
    let recordType: String
    let fields: [String: Data]
}

protocol ProductionGameCenterClaimDatabaseClient: Sendable {
    func activeProviderRecordName() async throws -> String
    func fetchClaim(
        recordName: String
    ) async throws -> ProductionGameCenterClaimProviderRecord?
    func createClaim(
        recordName: String,
        recordType: String,
        payloadFieldName: String,
        payload: Data,
        expectedProviderRecordName: String
    ) async throws
}

protocol ProductionGameCenterOwnershipClaiming: Sendable {
    func claimOwnership(
        playerID: GameCenterPlayerID,
        accountID: CloudAccountID,
        durableBinding: DurableAccountBinding
    ) async -> ProductionGameCenterClaimResult
}

/// A single immutable record in the private default zone binds one iCloud
/// profile to its first authenticated Game Center player. Keeping it out of
/// the custom replica zone prevents it from changing checkpoint semantics.
actor LiveProductionGameCenterClaimDatabaseClient:
    ProductionGameCenterClaimDatabaseClient
{
    static let recordName = "game-center-claim-v1"

    private let container: CKContainer
    private let database: CKDatabase

    init(containerIdentifier: String) {
        let container = CKContainer(identifier: containerIdentifier)
        self.container = container
        database = container.privateCloudDatabase
    }

    func activeProviderRecordName() async throws -> String {
        let status = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<CKAccountStatus, any Error>) in
            container.accountStatus { status, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: status)
                }
            }
        }
        guard status == .available else {
            throw CloudSyncTransportError.accountUnavailable
        }
        return try await container.userRecordID().recordName
    }

    func fetchClaim(
        recordName: String
    ) async throws -> ProductionGameCenterClaimProviderRecord? {
        let recordID = claimRecordID(recordName: recordName)
        let results = try await database.records(for: [recordID])
        guard let result = results[recordID] else {
            throw CloudKitClientFailure.providerRejected
        }
        switch result {
        case let .success(record):
            var fields: [String: Data] = [:]
            for key in record.allKeys() {
                guard let value = record[key] as? Data else {
                    throw CloudKitClientFailure.malformedRecord(
                        recordName: recordID.recordName
                    )
                }
                fields[key] = value
            }
            return ProductionGameCenterClaimProviderRecord(
                recordType: record.recordType,
                fields: fields
            )
        case let .failure(error)
            where CloudKitSDKFailureClassifier.isMissingRecord(error):
            return nil
        case let .failure(error):
            throw CloudKitSDKFailureClassifier.classify(
                error,
                fallbackRecordName: recordID.recordName
            )
        }
    }

    func createClaim(
        recordName: String,
        recordType: String,
        payloadFieldName: String,
        payload: Data,
        expectedProviderRecordName: String
    ) async throws {
        guard try await activeProviderRecordName()
                == expectedProviderRecordName else {
            throw CloudKitClientFailure.providerAccountMismatch
        }

        let recordID = claimRecordID(recordName: recordName)
        let record = CKRecord(recordType: recordType, recordID: recordID)
        record[payloadFieldName] = payload as NSData
        let result = try await database.modifyRecords(
            saving: [record],
            deleting: [],
            savePolicy: .ifServerRecordUnchanged,
            atomically: true
        )
        guard let saved = result.saveResults[recordID] else {
            throw CloudKitClientFailure.providerRejected
        }
        switch saved {
        case .success:
            break
        case let .failure(error):
            throw CloudKitSDKFailureClassifier.classify(
                error,
                fallbackRecordName: recordID.recordName
            )
        }
        guard try await activeProviderRecordName()
                == expectedProviderRecordName else {
            throw CloudKitClientFailure.providerAccountMismatch
        }
    }

    private func claimRecordID(recordName: String) -> CKRecord.ID {
        CKRecord.ID(
            recordName: recordName,
            zoneID: CKRecordZone.default().zoneID
        )
    }
}

actor ProductionGameCenterCloudClaimStore:
    ProductionGameCenterOwnershipClaiming
{
    private struct PayloadV1: Codable, Equatable, Sendable {
        static let currentSchemaVersion = 1

        let schemaVersion: Int
        let cloudAccountID: CloudAccountID
        let durableBinding: DurableAccountBinding
        let playerID: GameCenterPlayerID

        enum CodingKeys: String, CodingKey, CaseIterable {
            case schemaVersion
            case cloudAccountID
            case durableBinding
            case playerID
        }
    }

    private let cloudConfiguration: ProductionCloudWriteConfiguration
    private let client: any ProductionGameCenterClaimDatabaseClient
    private var observedClaimAccounts: Set<CloudAccountID> = []

    init(
        cloudConfiguration: ProductionCloudWriteConfiguration,
        client: any ProductionGameCenterClaimDatabaseClient
    ) {
        self.cloudConfiguration = cloudConfiguration
        self.client = client
    }

    static func live(
        cloudConfiguration: ProductionCloudWriteConfiguration
    ) -> ProductionGameCenterCloudClaimStore {
        ProductionGameCenterCloudClaimStore(
            cloudConfiguration: cloudConfiguration,
            client: LiveProductionGameCenterClaimDatabaseClient(
                containerIdentifier:
                    cloudConfiguration.transport.containerIdentifier
            )
        )
    }

    func claimOwnership(
        playerID: GameCenterPlayerID,
        accountID: CloudAccountID,
        durableBinding: DurableAccountBinding
    ) async -> ProductionGameCenterClaimResult {
        guard GameCenterPlayerIDRuleV1.isValid(playerID),
              CloudAccountDerivedBindings.derive(from: accountID)
                .durableAccountBinding == durableBinding else {
            return .unavailable
        }

        let requested = PayloadV1(
            schemaVersion: PayloadV1.currentSchemaVersion,
            cloudAccountID: accountID,
            durableBinding: durableBinding,
            playerID: playerID
        )
        let recordName = claimRecordName(for: accountID)

        do {
            let providerRecordName = try await validatedProviderRecordName(
                for: accountID
            )
            if let existing = try await client.fetchClaim(
                recordName: recordName
            ) {
                guard try await validatedProviderRecordName(for: accountID)
                        == providerRecordName else {
                    return .unavailable
                }
                return classify(
                    existing,
                    requested: requested,
                    accountID: accountID
                )
            }

            // Once this process has observed a claim, a later missing record is
            // deletion/reset evidence and must never silently permit a rebind.
            guard !observedClaimAccounts.contains(accountID) else {
                return .unavailable
            }

            let payload = try canonicalData(for: requested)
            do {
                try await client.createClaim(
                    recordName: recordName,
                    recordType: cloudConfiguration.profile.rootRecordType,
                    payloadFieldName:
                        cloudConfiguration.transport.payloadFieldName,
                    payload: payload,
                    expectedProviderRecordName: providerRecordName
                )
            } catch {
                // A competing device or a lost response is resolved only by
                // an exact readback; the error itself never grants authority.
            }

            guard try await validatedProviderRecordName(for: accountID)
                    == providerRecordName,
                  let readback = try await client.fetchClaim(
                    recordName: recordName
                  ),
                  try await validatedProviderRecordName(for: accountID)
                    == providerRecordName else {
                return .unavailable
            }
            return classify(
                readback,
                requested: requested,
                accountID: accountID
            )
        } catch {
            return .unavailable
        }
    }

    private func validatedProviderRecordName(
        for expectedAccountID: CloudAccountID
    ) async throws -> String {
        let providerRecordName = try await client.activeProviderRecordName()
        guard cloudConfiguration.transport.accountID(
            forProviderRecordName: providerRecordName
        ) == expectedAccountID else {
            throw CloudSyncTransportError.accountMismatch
        }
        return providerRecordName
    }

    private func classify(
        _ record: ProductionGameCenterClaimProviderRecord,
        requested: PayloadV1,
        accountID: CloudAccountID
    ) -> ProductionGameCenterClaimResult {
        observedClaimAccounts.insert(accountID)
        guard record.recordType == cloudConfiguration.profile.rootRecordType,
              Set(record.fields.keys) == [
                  cloudConfiguration.transport.payloadFieldName,
              ],
              let data = record.fields[
                  cloudConfiguration.transport.payloadFieldName
              ],
              let decoded = try? decodeCanonicalPayload(data),
              decoded.schemaVersion == PayloadV1.currentSchemaVersion,
              decoded.cloudAccountID == requested.cloudAccountID,
              decoded.durableBinding == requested.durableBinding,
              GameCenterPlayerIDRuleV1.isValid(decoded.playerID) else {
            return .unavailable
        }
        return decoded.playerID == requested.playerID
            ? .authorized(
                ProductionGameCenterOwnershipProof(
                    accountID: requested.cloudAccountID,
                    durableBinding: requested.durableBinding,
                    playerID: requested.playerID
                )
            )
            : .ownedByDifferentPlayer
    }

    private func claimRecordName(for accountID: CloudAccountID) -> String {
        "\(LiveProductionGameCenterClaimDatabaseClient.recordName)-\(accountID.rawValue)"
    }

    private func canonicalData(for payload: PayloadV1) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(payload)
    }

    private func decodeCanonicalPayload(_ data: Data) throws -> PayloadV1 {
        guard let object = try JSONSerialization.jsonObject(with: data)
                as? [String: Any],
              Set(object.keys) == Set(PayloadV1.CodingKeys.allCases.map(\.rawValue))
        else {
            throw CloudKitClientFailure.malformedRecord(
                recordName:
                    LiveProductionGameCenterClaimDatabaseClient.recordName
            )
        }
        let decoded = try JSONDecoder().decode(PayloadV1.self, from: data)
        guard try canonicalData(for: decoded) == data else {
            throw CloudKitClientFailure.malformedRecord(
                recordName:
                    LiveProductionGameCenterClaimDatabaseClient.recordName
            )
        }
        return decoded
    }
}

struct ProductionGameCenterOwnershipConflict:
    GameCenterSubmissionOwnershipConflictError,
    Equatable,
    Sendable
{}

enum ProductionGameCenterSubmissionChannelError: Error, Equatable, Sendable {
    case routeUnavailable
    case routeChanged
    case ownershipUnavailable
    case staleAcknowledgement
}

/// Converts the V4 unbound maxima into the exact first-player bucket only
/// after the immutable private-cloud claim has been read back. Submission and
/// acknowledgement remain inside the existing branded, exactly-once queue.
actor ProductionRoutingGameCenterSubmissionChannel:
    GameCenterSubmissionChannel
{
    private struct PreparedContext {
        let accountID: CloudAccountID
        let repository: LocalPlayerProfileRepository
        let session: ProfileSessionToken
        let submission: LocalGameCenterPreparedSubmissionV1
    }

    private let repositoryRouter: any ProductionProfileRepositoryRouting
    private let ownershipClaimer: any ProductionGameCenterOwnershipClaiming
    private let now: @Sendable () -> Date
    private var preparedContext: PreparedContext?

    init(
        repositoryRouter: any ProductionProfileRepositoryRouting,
        ownershipClaimer: any ProductionGameCenterOwnershipClaiming,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.repositoryRouter = repositoryRouter
        self.ownershipClaimer = ownershipClaimer
        self.now = now
    }

    func prepareGameCenterSubmission(
        for playerID: GameCenterPlayerID
    ) async throws -> LocalGameCenterPreparedSubmissionV1? {
        preparedContext = nil
        let initialRoute = try await verifiedRoute()
        guard case let .verifiedPrivateCloud(initialClaim) =
                initialRoute.authority else {
            throw ProductionGameCenterSubmissionChannelError.routeUnavailable
        }
        let initialSnapshot = try await initialRoute.repository.snapshot()
        guard initialRoute.authorizes(initialSnapshot) else {
            throw ProductionGameCenterSubmissionChannelError.routeUnavailable
        }

        let accountID = initialClaim.cloudAccountID
        let bindings = CloudAccountDerivedBindings.derive(from: accountID)
        let claimResult = await ownershipClaimer.claimOwnership(
            playerID: playerID,
            accountID: accountID,
            durableBinding: bindings.durableAccountBinding
        )
        let proof: ProductionGameCenterOwnershipProof
        switch claimResult {
        case let .authorized(authorizedProof):
            proof = authorizedProof
        case .ownedByDifferentPlayer:
            throw ProductionGameCenterOwnershipConflict()
        case .unavailable:
            throw ProductionGameCenterSubmissionChannelError
                .ownershipUnavailable
        }
        try Task.checkCancellation()

        let currentRoute = try await verifiedRoute()
        guard case let .verifiedPrivateCloud(currentClaim) =
                currentRoute.authority,
              currentClaim.cloudAccountID == accountID,
              currentRoute.repository === initialRoute.repository else {
            throw ProductionGameCenterSubmissionChannelError.routeChanged
        }
        let currentSnapshot = try await currentRoute.repository.snapshot()
        guard currentSnapshot.session == initialSnapshot.session,
              currentRoute.authorizes(currentSnapshot),
              proof.authorizes(
                playerID: playerID,
                session: currentSnapshot.session
              ) else {
            throw ProductionGameCenterSubmissionChannelError.routeChanged
        }

        _ = try await currentRoute.repository
            .attributeUnboundGameCenterPending(
                to: playerID,
                ownershipProof: proof,
                session: currentSnapshot.session,
                at: now()
            )
        guard let submission = try await currentRoute.repository
            .prepareGameCenterSubmission(
                for: playerID,
                session: currentSnapshot.session
            ) else {
            return nil
        }
        preparedContext = PreparedContext(
            accountID: accountID,
            repository: currentRoute.repository,
            session: currentSnapshot.session,
            submission: submission
        )
        return submission
    }

    func acknowledgeGameCenterSubmission(
        _ submission: LocalGameCenterPreparedSubmissionV1,
        successfulResult: GameCenterSuccessfulSubmissionV1,
        at date: Date
    ) async throws -> LocalPlayerProfileSnapshot {
        guard let context = preparedContext,
              context.submission == submission else {
            throw ProductionGameCenterSubmissionChannelError
                .staleAcknowledgement
        }
        let route = try await verifiedRoute()
        guard case let .verifiedPrivateCloud(claim) = route.authority,
              claim.cloudAccountID == context.accountID,
              route.repository === context.repository else {
            throw ProductionGameCenterSubmissionChannelError.routeChanged
        }
        let snapshot = try await route.repository.snapshot()
        guard snapshot.session == context.session,
              route.authorizes(snapshot) else {
            throw ProductionGameCenterSubmissionChannelError.routeChanged
        }
        let acknowledged = try await route.repository
            .acknowledgeGameCenterSubmission(
                submission,
                successfulResult: successfulResult,
                session: context.session,
                at: date
            )
        preparedContext = nil
        return acknowledged
    }

    private func verifiedRoute() async throws
        -> ProductionProfileRepositoryRoute {
        let route = try await repositoryRouter.currentRoute()
        guard case let .verifiedPrivateCloud(claim) = route.authority,
              route.repository === claim.installedRepository else {
            throw ProductionGameCenterSubmissionChannelError.routeUnavailable
        }
        return route
    }
}

/// Retained app-level orchestration for Game Center. Delivery is single-flight,
/// revalidates both Apple identities at every boundary, and coalesces one
/// foreground retry rather than dropping a trigger during an active request.
@MainActor
final class ProductionGameCenterRuntime {
    private struct ActiveOperation {
        let id: UUID
        let task: Task<ProductionGameCenterActionOutcome, Never>
    }

    private let configuration: GameKitGameCenterConfiguration
    private let coordinator: GameCenterDeliveryCoordinator
    private var activeOperation: ActiveOperation?
    private var deliveryRequestedWhileActive = false
    private var applicationIsActive = false
    private var activationGeneration: UInt64 = 0

    init(
        configuration: GameKitGameCenterConfiguration,
        coordinator: GameCenterDeliveryCoordinator
    ) {
        self.configuration = configuration
        self.coordinator = coordinator
    }

    func setApplicationActive(_ isActive: Bool) {
        guard applicationIsActive != isActive else { return }
        applicationIsActive = isActive
        activationGeneration &+= 1
        guard !isActive else { return }
        activeOperation?.task.cancel()
        deliveryRequestedWhileActive = false
    }

    static func live(
        configuration: GameKitGameCenterConfiguration,
        cloudConfiguration: ProductionCloudWriteConfiguration,
        repositoryRouter: any ProductionProfileRepositoryRouting,
        presentationHandoff: any GameKitPresentationHandoff
    ) -> ProductionGameCenterRuntime {
        let service = GameKitGameCenterService(
            configuration: configuration,
            presenter: presentationHandoff
        )
        let channel = ProductionRoutingGameCenterSubmissionChannel(
            repositoryRouter: repositoryRouter,
            ownershipClaimer: ProductionGameCenterCloudClaimStore.live(
                cloudConfiguration: cloudConfiguration
            )
        )
        return ProductionGameCenterRuntime(
            configuration: configuration,
            coordinator: GameCenterDeliveryCoordinator.makeForProduction(
                submissionChannel: channel,
                service: service
            )
        )
    }

    func scheduleDelivery() {
        guard applicationIsActive else { return }
        guard activeOperation == nil else {
            deliveryRequestedWhileActive = true
            return
        }
        _ = startOperation(
            presentation: nil,
            generation: activationGeneration
        )
    }

    func presentLeaderboard() async -> ProductionGameCenterActionOutcome {
        guard applicationIsActive else { return .unavailable }
        let generation = activationGeneration
        // Completion itself may start one coalesced delivery. Drain the whole
        // serialized chain before installing the presentation operation.
        while let current = activeOperation {
            _ = await current.task.value
            guard applicationIsActive,
                  activationGeneration == generation else {
                return .unavailable
            }
        }
        deliveryRequestedWhileActive = false
        let destination = GameCenterPresentationDestination.leaderboard(
            identifier: configuration.leaderboardIdentifier
        )
        return await startOperation(
            presentation: destination,
            generation: generation
        ).task.value
    }

    func shutdown() {
        activeOperation?.task.cancel()
        activeOperation = nil
        deliveryRequestedWhileActive = false
    }

    private func startOperation(
        presentation: GameCenterPresentationDestination?,
        generation: UInt64
    ) -> ActiveOperation {
        let id = UUID()
        let task = Task<ProductionGameCenterActionOutcome, Never> {
            @MainActor [weak self] in
            guard let self else {
                return ProductionGameCenterActionOutcome.unavailable
            }
            let result = await self.perform(
                presentation: presentation,
                generation: generation
            )
            self.finishOperationAndScheduleCoalescedDelivery(id: id)
            return result
        }
        let operation = ActiveOperation(id: id, task: task)
        activeOperation = operation
        return operation
    }

    private func finishOperationAndScheduleCoalescedDelivery(id: UUID) {
        guard activeOperation?.id == id else { return }
        activeOperation = nil
        guard applicationIsActive,
              deliveryRequestedWhileActive else {
            deliveryRequestedWhileActive = false
            return
        }
        deliveryRequestedWhileActive = false
        scheduleDelivery()
    }

    private func perform(
        presentation: GameCenterPresentationDestination?,
        generation: UInt64
    ) async -> ProductionGameCenterActionOutcome {
        guard !Task.isCancelled,
              applicationIsActive,
              activationGeneration == generation else {
            return .unavailable
        }
        let delivery = await coordinator.foreground()
        guard !Task.isCancelled,
              applicationIsActive,
              activationGeneration == generation else {
            return .unavailable
        }
        switch delivery {
        case .delivered, .noPendingSubmission:
            break
        case .retained(.ownershipConflict):
            return .ownedByDifferentPlayer
        case .unavailable, .retained, .alreadyInProgress:
            return .unavailable
        }

        if let presentation {
            guard applicationIsActive,
                  activationGeneration == generation else {
                return .unavailable
            }
            do {
                try await coordinator.requestPresentation(presentation)
            } catch {
                return .unavailable
            }
        }
        return .completed
    }
}

import Foundation

protocol PlayerProfileMigrating: Sendable {
    func decode(_ data: Data) throws -> LocalPlayerDocumentV1
    func encode(_ document: LocalPlayerDocumentV1, savedAt: Date) throws -> Data
}

struct PlayerProfileMigrator: PlayerProfileMigrating {
    private struct EnvelopeHeader: Decodable {
        let format: String
        let schemaVersion: Int
    }

    func decode(_ data: Data) throws -> LocalPlayerDocumentV1 {
        let header: EnvelopeHeader
        do {
            header = try Self.makeDecoder().decode(EnvelopeHeader.self, from: data)
        } catch {
            throw ProfileMigrationError.malformedEnvelope
        }

        guard header.format == PlayerProfileEnvelopeV2.formatIdentifier else {
            throw ProfileMigrationError.unexpectedFormat(header.format)
        }

        switch header.schemaVersion {
        case PlayerProfileEnvelopeV1.schemaVersion:
            do {
                let document = try Self.makeDecoder()
                    .decode(PlayerProfileEnvelopeV1.self, from: data)
                    .document
                return Self.migrateLegacyV1(document)
            } catch let error as ProfileMigrationError {
                throw error
            } catch {
                throw ProfileMigrationError.malformedEnvelope
            }
        case PlayerProfileEnvelopeV2.schemaVersion:
            do {
                return try Self.makeDecoder()
                    .decode(PlayerProfileEnvelopeV2.self, from: data)
                    .document
            } catch {
                throw ProfileMigrationError.malformedEnvelope
            }
        default:
            throw ProfileMigrationError.unsupportedSchemaVersion(header.schemaVersion)
        }
    }

    func encode(_ document: LocalPlayerDocumentV1, savedAt: Date) throws -> Data {
        guard document.rewardedRunObservations != nil else {
            throw ProfileMigrationError.malformedEnvelope
        }
        let envelope = PlayerProfileEnvelopeV2(
            document: document,
            savedAt: savedAt
        )
        return try Self.makeEncoder().encode(envelope)
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

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}

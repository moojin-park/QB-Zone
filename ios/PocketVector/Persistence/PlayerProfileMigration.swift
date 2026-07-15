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

        guard header.format == PlayerProfileEnvelopeV1.formatIdentifier else {
            throw ProfileMigrationError.unexpectedFormat(header.format)
        }

        switch header.schemaVersion {
        case PlayerProfileEnvelopeV1.schemaVersion:
            do {
                return try Self.makeDecoder()
                    .decode(PlayerProfileEnvelopeV1.self, from: data)
                    .document
            } catch {
                throw ProfileMigrationError.malformedEnvelope
            }
        default:
            throw ProfileMigrationError.unsupportedSchemaVersion(header.schemaVersion)
        }
    }

    func encode(_ document: LocalPlayerDocumentV1, savedAt: Date) throws -> Data {
        let envelope = PlayerProfileEnvelopeV1(
            document: document,
            savedAt: savedAt
        )
        return try Self.makeEncoder().encode(envelope)
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

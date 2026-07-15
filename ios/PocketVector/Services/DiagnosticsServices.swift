import Foundation

enum DiagnosticSeverity: String, Codable, Equatable, Sendable {
    case info
    case warning
    case error
    case critical
}

enum DiagnosticSyncFailure: String, Codable, Equatable, Sendable {
    case offline
    case accountUnavailable
    case conflict
    case retryableTransport
    case permanentTransport
}

enum DiagnosticStoreFailure: String, Codable, Equatable, Sendable {
    case productUnavailable
    case verificationFailed
    case accountMismatch
    case durableSettlementFailed
    case finishFailed
}

enum DiagnosticRewardFailure: String, Codable, Equatable, Sendable {
    case consentUnavailable
    case loadFailed
    case presentationFailed
    case verificationFailed
    case settlementFailed
}

enum DiagnosticGameCenterFailure: String, Codable, Equatable, Sendable {
    case authenticationUnavailable
    case scoreSubmissionFailed
    case achievementSubmissionFailed
    case presentationFailed
}

enum DiagnosticPersistenceRecovery: String, Codable, Equatable, Sendable {
    case restoredBackup
    case quarantinedCorruptFile
    case createdFreshProfile
}

enum DiagnosticPayload: Codable, Equatable, Sendable {
    case sync(DiagnosticSyncFailure)
    case store(DiagnosticStoreFailure)
    case reward(DiagnosticRewardFailure)
    case gameCenter(DiagnosticGameCenterFailure)
    case persistence(DiagnosticPersistenceRecovery)
}

enum DiagnosticInput: Sendable {
    case allowlisted(DiagnosticPayload)
    case exactBalance(Int64)
    case rawProfileID(UUID)
    case providerTransactionID(AdProviderTransactionID)
    case detailedRunHistory([RunID])
}

enum DiagnosticPrivacyError: Error, Equatable, Sendable {
    case exactBalanceRejected
    case rawProfileIDRejected
    case providerTransactionIDRejected
    case detailedRunHistoryRejected
}

struct DiagnosticReport: Codable, Equatable, Sendable {
    let id: UUID
    let occurredAt: Date
    let severity: DiagnosticSeverity
    let payload: DiagnosticPayload

    private init(
        id: UUID,
        occurredAt: Date,
        severity: DiagnosticSeverity,
        payload: DiagnosticPayload
    ) {
        self.id = id
        self.occurredAt = occurredAt
        self.severity = severity
        self.payload = payload
    }

    static func make(
        occurredAt: Date,
        severity: DiagnosticSeverity,
        input: DiagnosticInput
    ) throws -> DiagnosticReport {
        switch input {
        case let .allowlisted(payload):
            DiagnosticReport(
                id: UUID(),
                occurredAt: occurredAt,
                severity: severity,
                payload: payload
            )
        case .exactBalance:
            throw DiagnosticPrivacyError.exactBalanceRejected
        case .rawProfileID:
            throw DiagnosticPrivacyError.rawProfileIDRejected
        case .providerTransactionID:
            throw DiagnosticPrivacyError.providerTransactionIDRejected
        case .detailedRunHistory:
            throw DiagnosticPrivacyError.detailedRunHistoryRejected
        }
    }
}

protocol DiagnosticsReporting: Sendable {
    func report(_ report: DiagnosticReport) async
}

actor InMemoryDiagnosticsReporter: DiagnosticsReporting {
    private(set) var reports: [DiagnosticReport] = []

    func report(_ report: DiagnosticReport) {
        reports.append(report)
    }
}

struct NoOpDiagnosticsReporter: DiagnosticsReporting {
    func report(_ report: DiagnosticReport) async {}
}

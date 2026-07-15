import Foundation

struct AtomicProfileFileStore: Sendable {
    let locations: ProfileStorageLocations
    let migrator: any PlayerProfileMigrating

    init(
        directoryURL: URL,
        migrator: any PlayerProfileMigrating = PlayerProfileMigrator()
    ) {
        locations = ProfileStorageLocations(directoryURL: directoryURL)
        self.migrator = migrator
    }

    func loadOrCreate(
        defaultDocument: @autoclosure () -> LocalPlayerDocumentV1,
        at date: Date,
        catalog: LaunchCatalog
    ) throws -> (document: LocalPlayerDocumentV1, report: ProfileLoadReport) {
        try prepareDirectories()
        var quarantinedURLs: [URL] = []

        if fileExists(at: locations.primaryURL) {
            do {
                let primaryData = try Data(contentsOf: locations.primaryURL)
                let document = try decodeAndValidate(primaryData, catalog: catalog)
                try repairBackupIfNeeded(
                    with: primaryData,
                    catalog: catalog,
                    at: date,
                    quarantinedURLs: &quarantinedURLs
                )
                return (
                    document,
                    ProfileLoadReport(
                        source: .primary,
                        quarantinedURLs: quarantinedURLs
                    )
                )
            } catch {
                quarantinedURLs.append(
                    try quarantine(locations.primaryURL, at: date)
                )
            }
        }

        if fileExists(at: locations.backupURL) {
            do {
                let backupData = try Data(contentsOf: locations.backupURL)
                let document = try decodeAndValidate(backupData, catalog: catalog)
                try atomicWrite(backupData, to: locations.primaryURL)
                return (
                    document,
                    ProfileLoadReport(
                        source: .backup,
                        quarantinedURLs: quarantinedURLs
                    )
                )
            } catch {
                quarantinedURLs.append(
                    try quarantine(locations.backupURL, at: date)
                )
            }
        }

        let document = defaultDocument()
        try PlayerProfileValidator.validate(document, catalog: catalog)
        let data = try migrator.encode(document, savedAt: date)
        try atomicWrite(data, to: locations.primaryURL)
        try atomicWrite(data, to: locations.backupURL)
        return (
            document,
            ProfileLoadReport(
                source: .createdFresh,
                quarantinedURLs: quarantinedURLs
            )
        )
    }

    func save(
        _ document: LocalPlayerDocumentV1,
        at date: Date,
        catalog: LaunchCatalog
    ) throws {
        try prepareDirectories()
        try PlayerProfileValidator.validate(document, catalog: catalog)
        let newData = try migrator.encode(document, savedAt: date)

        if fileExists(at: locations.primaryURL) {
            let currentData = try Data(contentsOf: locations.primaryURL)
            do {
                _ = try decodeAndValidate(currentData, catalog: catalog)
                try atomicWrite(currentData, to: locations.backupURL)
            } catch {
                _ = try quarantine(locations.primaryURL, at: date)
            }
        }

        try atomicWrite(newData, to: locations.primaryURL)
        if !fileExists(at: locations.backupURL) {
            try atomicWrite(newData, to: locations.backupURL)
        }
    }

    private func decodeAndValidate(
        _ data: Data,
        catalog: LaunchCatalog
    ) throws -> LocalPlayerDocumentV1 {
        let document = try migrator.decode(data)
        try PlayerProfileValidator.validate(document, catalog: catalog)
        return document
    }

    private func repairBackupIfNeeded(
        with primaryData: Data,
        catalog: LaunchCatalog,
        at date: Date,
        quarantinedURLs: inout [URL]
    ) throws {
        guard fileExists(at: locations.backupURL) else {
            try atomicWrite(primaryData, to: locations.backupURL)
            return
        }

        do {
            let backupData = try Data(contentsOf: locations.backupURL)
            _ = try decodeAndValidate(backupData, catalog: catalog)
        } catch {
            quarantinedURLs.append(
                try quarantine(locations.backupURL, at: date)
            )
            try atomicWrite(primaryData, to: locations.backupURL)
        }
    }

    private func prepareDirectories() throws {
        try FileManager.default.createDirectory(
            at: locations.directoryURL,
            withIntermediateDirectories: true
        )
    }

    private func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    private func atomicWrite(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }

    private func quarantine(_ url: URL, at date: Date) throws -> URL {
        try FileManager.default.createDirectory(
            at: locations.quarantineDirectoryURL,
            withIntermediateDirectories: true
        )
        let timestamp = Int64((date.timeIntervalSince1970 * 1_000).rounded())
        let destination = locations.quarantineDirectoryURL.appendingPathComponent(
            "\(url.deletingPathExtension().lastPathComponent)-corrupt-\(timestamp)-\(UUID().uuidString.lowercased()).json"
        )
        try FileManager.default.moveItem(at: url, to: destination)
        return destination
    }
}

import ImageIO
import SpriteKit
import UIKit

extension RGBColor {
    var uiColor: UIColor {
        UIColor(
            red: CGFloat(red) / 255,
            green: CGFloat(green) / 255,
            blue: CGFloat(blue) / 255,
            alpha: 1
        )
    }
}

struct UniformTexturePrewarmResult: Equatable, Sendable {
    let requestedCount: Int
    let preparedCount: Int
    let preloadedCount: Int
    let durationMilliseconds: Double
    let preprocessingDurationMilliseconds: Double
    /// Longest uninterrupted main-actor installation batch. Installation yields after each
    /// texture, so this is the frame-pacing gate rather than the aggregate install work.
    let mainActorInstallationDurationMilliseconds: Double
    let totalMainActorInstallationDurationMilliseconds: Double
    let spriteKitPreloadDurationMilliseconds: Double

    var isComplete: Bool {
        requestedCount == preparedCount && preparedCount == preloadedCount
    }
}

struct GameplayFieldLayer: Equatable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        case neutralBase = "neutral"
        case endZone = "endZone"
        case fieldBranding = "fieldBranding"
        case markings = "markings"
    }

    let kind: Kind
    let relativePath: String

    var nodeName: String { "fieldLayer.\(kind.rawValue)" }
}

struct GameplayFieldLayerStack: Equatable, Sendable {
    static let textureSize = CGSize(width: 1_728, height: 768)

    let offenseTeamID: TeamID

    var orderedLayers: [GameplayFieldLayer] {
        let teamRoot = "pixel/teams/\(offenseTeamID.rawValue)"
        return [
            GameplayFieldLayer(
                kind: .neutralBase,
                relativePath: "pixel/stadium-field-neutral-v1.png"
            ),
            GameplayFieldLayer(
                kind: .endZone,
                relativePath: "\(teamRoot)/end-zone.png"
            ),
            GameplayFieldLayer(
                kind: .fieldBranding,
                relativePath: "\(teamRoot)/field-branding.png"
            ),
            GameplayFieldLayer(
                kind: .markings,
                relativePath: "pixel/field-markings-v1.png"
            ),
        ]
    }
}

struct GameplayFieldTexturePreloadResult: Equatable, Sendable {
    let requestedCount: Int
    let loadedCount: Int
    let preloadedCount: Int
    let durationMilliseconds: Double
    let spriteKitPreloadDurationMilliseconds: Double

    var isComplete: Bool {
        requestedCount == loadedCount && loadedCount == preloadedCount
    }
}

struct GameplayVisualPrewarmResult: Equatable, Sendable {
    let uniforms: UniformTexturePrewarmResult
    let field: GameplayFieldTexturePreloadResult
    let durationMilliseconds: Double

    var requestedCount: Int { uniforms.requestedCount + field.requestedCount }
    var preparedCount: Int { uniforms.preparedCount + field.loadedCount }
    var preloadedCount: Int { uniforms.preloadedCount + field.preloadedCount }
    var preprocessingDurationMilliseconds: Double {
        uniforms.preprocessingDurationMilliseconds
    }
    var mainActorInstallationDurationMilliseconds: Double {
        uniforms.mainActorInstallationDurationMilliseconds
    }
    var totalMainActorInstallationDurationMilliseconds: Double {
        uniforms.totalMainActorInstallationDurationMilliseconds
    }
    var spriteKitPreloadDurationMilliseconds: Double {
        uniforms.spriteKitPreloadDurationMilliseconds
            + field.spriteKitPreloadDurationMilliseconds
    }

    var isComplete: Bool { uniforms.isComplete && field.isComplete }
}

struct UniformRaster: Equatable, Sendable {
    let width: Int
    let height: Int
    let bytesPerRow: Int
    let bytes: [UInt8]
}

struct GameplayJerseyAssetRoot: Equatable, Hashable, Sendable {
    let teamID: TeamID
    let jerseyID: JerseyID
    let relativePath: String

    init?(
        teamID: TeamID,
        jerseyID: JerseyID,
        catalog: LaunchCatalog = .approved
    ) {
        guard let jersey = catalog.jersey(id: jerseyID),
              jersey.teamID == teamID
        else {
            return nil
        }
        self.teamID = teamID
        self.jerseyID = jersey.id
        relativePath = "characters/teams/\(teamID.rawValue)/\(jersey.kind.rawValue)"
    }

    func framePath(for genericFramePath: String) -> String? {
        guard genericFramePath.hasPrefix("characters/"),
              !genericFramePath.hasSuffix("/"),
              let frameName = genericFramePath.split(separator: "/").last,
              frameName.hasSuffix(".webp")
        else {
            return nil
        }
        return "\(relativePath)/\(frameName)"
    }
}

struct RunGameplayUniformAssetRoots: Equatable, Hashable, Sendable {
    let offense: GameplayJerseyAssetRoot
    let defense: GameplayJerseyAssetRoot

    init?(
        configuration: RunConfiguration,
        catalog: LaunchCatalog = .approved
    ) {
        guard configuration.offenseTeamID != configuration.defenseTeamID,
              let offense = GameplayJerseyAssetRoot(
            teamID: configuration.offenseTeamID,
            jerseyID: configuration.offenseJerseyID,
            catalog: catalog
        ), let defense = GameplayJerseyAssetRoot(
            teamID: configuration.defenseTeamID,
            jerseyID: configuration.defenseJerseyID,
            catalog: catalog
        ) else {
            return nil
        }
        self.offense = offense
        self.defense = defense
    }
}

struct UniformTexturePreparationRequest: Sendable {
    let relativePath: String
    let developmentFallbackRelativePath: String?
    let cacheKey: UniformTextureCacheKey
}

struct PreparedUniformTexture: Sendable {
    let cacheKey: UniformTextureCacheKey
    let width: Int
    let height: Int
    let bytesPerRow: Int
    let rgbaData: Data
}

struct UniformTextureCacheKey: Hashable, Sendable {
    let assetRoot: GameplayJerseyAssetRoot
    let genericFramePath: String
}

enum GameAssetResources {
    static let rootDirectoryName = "GameAssets"
    static let manifestRelativePath = "native-assets.json"

    static func url(for relativePath: String, in bundle: Bundle = .main) -> URL? {
        let url = bundle.bundleURL
            .appendingPathComponent(rootDirectoryName, isDirectory: true)
            .appendingPathComponent(relativePath)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}

/// Decodes the authored, team-specific sprite frames on the cooperative executor. No UIKit or
/// SpriteKit object crosses this boundary; the main actor receives unchanged RGBA bytes and only
/// performs the short final `SKTexture` installation step.
enum BakedUniformRasterPreprocessor {
    static let framePixelWidth = 384
    static let framePixelHeight = 512

    private struct IndexedPreparation: Sendable {
        let index: Int
        let texture: PreparedUniformTexture?
    }

    static func loadRaster(relativePath: String) -> UniformRaster? {
        guard let url = GameAssetResources.url(for: relativePath),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            return nil
        }

        let width = image.width
        let height = image.height
        guard width == framePixelWidth, height == framePixelHeight else {
            return nil
        }
        let bytesPerRow = width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        let rendered = bytes.withUnsafeMutableBytes { rawBuffer -> Bool in
            guard let baseAddress = rawBuffer.baseAddress,
                  let context = CGContext(
                      data: baseAddress,
                      width: width,
                      height: height,
                      bitsPerComponent: 8,
                      bytesPerRow: bytesPerRow,
                      space: colorSpace,
                      bitmapInfo: bitmapInfo.rawValue
                  )
            else {
                return false
            }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard rendered else { return nil }
        return UniformRaster(
            width: width,
            height: height,
            bytesPerRow: bytesPerRow,
            bytes: bytes
        )
    }

    static func pixelSize(relativePath: String) -> CGSize? {
        guard let url = GameAssetResources.url(for: relativePath),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber
        else {
            return nil
        }
        return CGSize(width: width.intValue, height: height.intValue)
    }

    static func prepare(
        _ request: UniformTexturePreparationRequest
    ) -> PreparedUniformTexture? {
        guard !Task.isCancelled else {
            return nil
        }
        let source = loadRaster(relativePath: request.relativePath)
            ?? request.developmentFallbackRelativePath.flatMap(loadRaster(relativePath:))
        guard let source else { return nil }
        guard !Task.isCancelled else { return nil }
        return PreparedUniformTexture(
            cacheKey: request.cacheKey,
            width: source.width,
            height: source.height,
            bytesPerRow: source.bytesPerRow,
            rgbaData: Data(source.bytes)
        )
    }

    static func prepare(
        _ requests: [UniformTexturePreparationRequest]
    ) async -> [PreparedUniformTexture] {
        await withTaskGroup(of: IndexedPreparation.self) { group in
            for (index, request) in requests.enumerated() {
                guard !Task.isCancelled else { break }
                group.addTask {
                    IndexedPreparation(index: index, texture: prepare(request))
                }
            }

            var preparedByIndex = [PreparedUniformTexture?](
                repeating: nil,
                count: requests.count
            )
            for await preparation in group {
                preparedByIndex[preparation.index] = preparation.texture
            }
            return preparedByIndex.compactMap { $0 }
        }
    }
}

protocol UniformTexturePreparing: Sendable {
    func prepare(
        _ requests: [UniformTexturePreparationRequest]
    ) async -> [PreparedUniformTexture]
}

struct ConcurrentBakedUniformTexturePreparer: UniformTexturePreparing {
    func prepare(
        _ requests: [UniformTexturePreparationRequest]
    ) async -> [PreparedUniformTexture] {
        await BakedUniformRasterPreprocessor.prepare(requests)
    }
}

enum GameplayUniformFallbackPolicy: Sendable {
    case disabled
    case developmentGeneric
}

@MainActor
protocol UniformTexturePreloading {
    func preload(_ texture: SKTexture) async -> Bool
}

@MainActor
struct SpriteKitUniformTexturePreloader: UniformTexturePreloading {
    func preload(_ texture: SKTexture) async -> Bool {
        guard !Task.isCancelled else { return false }
        await withCheckedContinuation { continuation in
            SKTexture.preload([texture]) {
                continuation.resume()
            }
        }
        return true
    }
}

@MainActor
final class TextureLibrary {
    static let offenseUniformPaths: [String] = {
        let directions = ["left", "right"]
        var paths = [
            "characters/qb-idle.webp",
            "characters/qb-aim.webp",
            "characters/qb-throw.webp",
            "characters/qb-recovery.webp",
        ]
        for direction in directions {
            paths.append("characters/receiver-catch-\(direction).webp")
            paths.append("characters/receiver-touchdown-\(direction).webp")
            paths += (1 ... 4).map {
                "characters/receiver-run-\($0)-\(direction).webp"
            }
            paths.append("characters/receiver-carry-\(direction).webp")
            paths += (2 ... 4).map {
                "characters/receiver-carry-\($0)-\(direction).webp"
            }
        }
        return paths
    }()

    static let defenseUniformPaths: [String] = {
        ["left", "right"].flatMap { direction in
            ["characters/defender-interception-\(direction).webp"]
                + (1 ... 4).map {
                    "characters/defender-run-\($0)-\(direction).webp"
                }
        }
    }()

    private var cache: [String: SKTexture] = [:]
    private var uniformCache: [UniformTextureCacheKey: SKTexture] = [:]
    private var preparedRunAssetRoots: Set<RunGameplayUniformAssetRoots> = []
    private var preloadedFieldTexturePaths: Set<String> = []
    private var uniformPrewarmIsActive = false
    private var uniformPrewarmWaiters: [CheckedContinuation<Void, Never>] = []
    private var fieldPrewarmIsActive = false
    private var fieldPrewarmWaiters: [CheckedContinuation<Void, Never>] = []
    private let uniformTexturePreparer: any UniformTexturePreparing
    private let uniformTexturePreloader: any UniformTexturePreloading
    private let gameplayUniformFallbackPolicy: GameplayUniformFallbackPolicy

    init(
        uniformTexturePreparer: any UniformTexturePreparing = ConcurrentBakedUniformTexturePreparer(),
        uniformTexturePreloader: any UniformTexturePreloading = SpriteKitUniformTexturePreloader(),
        gameplayUniformFallbackPolicy: GameplayUniformFallbackPolicy = .disabled
    ) {
        self.uniformTexturePreparer = uniformTexturePreparer
        self.uniformTexturePreloader = uniformTexturePreloader
        self.gameplayUniformFallbackPolicy = gameplayUniformFallbackPolicy
    }

    func texture(_ relativePath: String) -> SKTexture? {
        if let cached = cache[relativePath] {
            return cached
        }

        guard let url = GameAssetResources.url(for: relativePath) else {
            return nil
        }
        guard let image = UIImage(contentsOfFile: url.path) else {
            return nil
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .nearest
        cache[relativePath] = texture
        return texture
    }

    func uniformTexture(
        _ genericFramePath: String,
        assetRoot: GameplayJerseyAssetRoot
    ) -> SKTexture? {
        uniformCache[UniformTextureCacheKey(
            assetRoot: assetRoot,
            genericFramePath: genericFramePath
        )]
    }

    func prewarmRunVisualTextures(
        uniformAssetRoots: RunGameplayUniformAssetRoots,
        fieldLayerStack: GameplayFieldLayerStack
    ) async -> GameplayVisualPrewarmResult {
        let startedAt = ProcessInfo.processInfo.systemUptime
        let uniforms = await prewarmRunUniformTextures(
            uniformAssetRoots: uniformAssetRoots
        )
        let field: GameplayFieldTexturePreloadResult
        if Task.isCancelled {
            field = emptyFieldPreloadResult(
                requestedCount: fieldLayerStack.orderedLayers.count,
                startedAt: ProcessInfo.processInfo.systemUptime
            )
        } else {
            field = await prewarmGameplayFieldTextures(fieldLayerStack)
        }

        return GameplayVisualPrewarmResult(
            uniforms: uniforms,
            field: field,
            durationMilliseconds: (
                ProcessInfo.processInfo.systemUptime - startedAt
            ) * 1_000
        )
    }

    func prewarmGameplayFieldTextures(
        _ layerStack: GameplayFieldLayerStack
    ) async -> GameplayFieldTexturePreloadResult {
        let startedAt = ProcessInfo.processInfo.systemUptime
        let layers = layerStack.orderedLayers
        await acquireFieldPrewarmTurn()
        defer { releaseFieldPrewarmTurn() }

        guard !Task.isCancelled else {
            return emptyFieldPreloadResult(
                requestedCount: layers.count,
                startedAt: startedAt
            )
        }

        let loadedLayers = layers.filter { layer in
            guard let texture = texture(layer.relativePath) else { return false }
            return texture.size() == GameplayFieldLayerStack.textureSize
        }
        var preloadedCount = loadedLayers.reduce(into: 0) { count, layer in
            if preloadedFieldTexturePaths.contains(layer.relativePath) {
                count += 1
            }
        }
        let preloadStartedAt = ProcessInfo.processInfo.systemUptime
        for layer in loadedLayers
        where !preloadedFieldTexturePaths.contains(layer.relativePath) {
            guard !Task.isCancelled,
                  let texture = texture(layer.relativePath) else { break }
            if await uniformTexturePreloader.preload(texture) {
                preloadedFieldTexturePaths.insert(layer.relativePath)
                preloadedCount += 1
            }
            guard !Task.isCancelled else { break }
        }

        return GameplayFieldTexturePreloadResult(
            requestedCount: layers.count,
            loadedCount: loadedLayers.count,
            preloadedCount: preloadedCount,
            durationMilliseconds: (
                ProcessInfo.processInfo.systemUptime - startedAt
            ) * 1_000,
            spriteKitPreloadDurationMilliseconds: (
                ProcessInfo.processInfo.systemUptime - preloadStartedAt
            ) * 1_000
        )
    }

    /// Prepares every finite animation texture used by one run. The baked frames are decoded
    /// without color projection off the main actor; only final cache installation returns here.
    /// `GameScene` exposes a visible readiness state and does not start its countdown until this
    /// completes, so gameplay-time frame swaps are cache reads without a frozen transition.
    func prewarmRunUniformTextures(
        uniformAssetRoots: RunGameplayUniformAssetRoots
    ) async -> UniformTexturePrewarmResult {
        let startedAt = ProcessInfo.processInfo.systemUptime
        let requestedCount = Self.offenseUniformPaths.count + Self.defenseUniformPaths.count
        guard !Task.isCancelled else {
            return emptyPrewarmResult(requestedCount: requestedCount, startedAt: startedAt)
        }
        if preparedRunAssetRoots.contains(uniformAssetRoots) {
            return cachedPrewarmResult(requestedCount: requestedCount, startedAt: startedAt)
        }

        await acquireUniformPrewarmTurn()
        defer { releaseUniformPrewarmTurn() }

        guard !Task.isCancelled else {
            return emptyPrewarmResult(requestedCount: requestedCount, startedAt: startedAt)
        }
        // A preceding serialized request may have completed these roots while
        // the current caller was waiting for its turn.
        if preparedRunAssetRoots.contains(uniformAssetRoots) {
            return cachedPrewarmResult(requestedCount: requestedCount, startedAt: startedAt)
        }

        let requests = makePreparationRequests(
            genericFramePaths: Self.offenseUniformPaths,
            assetRoot: uniformAssetRoots.offense
        ) + makePreparationRequests(
            genericFramePaths: Self.defenseUniformPaths,
            assetRoot: uniformAssetRoots.defense
        )

        let missingRequests = requests.filter { uniformCache[$0.cacheKey] == nil }
        let preprocessingStartedAt = ProcessInfo.processInfo.systemUptime
        let prepared = await uniformTexturePreparer.prepare(missingRequests)
        let preprocessingDuration = (
            ProcessInfo.processInfo.systemUptime - preprocessingStartedAt
        ) * 1_000

        var maximumInstallationBatchMilliseconds = 0.0
        var totalInstallationMilliseconds = 0.0
        guard !Task.isCancelled else {
            return makePrewarmResult(
                requests: requests,
                startedAt: startedAt,
                preprocessingDurationMilliseconds: preprocessingDuration
            )
        }
        for texture in prepared {
            guard !Task.isCancelled else {
                return makePrewarmResult(
                    requests: requests,
                    startedAt: startedAt,
                    preprocessingDurationMilliseconds: preprocessingDuration,
                    maximumInstallationBatchMilliseconds: maximumInstallationBatchMilliseconds,
                    totalInstallationMilliseconds: totalInstallationMilliseconds
                )
            }
            let batchStartedAt = ProcessInfo.processInfo.systemUptime
            _ = install(texture)
            let batchDuration = (
                ProcessInfo.processInfo.systemUptime - batchStartedAt
            ) * 1_000
            maximumInstallationBatchMilliseconds = max(
                maximumInstallationBatchMilliseconds,
                batchDuration
            )
            totalInstallationMilliseconds += batchDuration
            await Task.yield()
            guard !Task.isCancelled else {
                return makePrewarmResult(
                    requests: requests,
                    startedAt: startedAt,
                    preprocessingDurationMilliseconds: preprocessingDuration,
                    maximumInstallationBatchMilliseconds: maximumInstallationBatchMilliseconds,
                    totalInstallationMilliseconds: totalInstallationMilliseconds
                )
            }
        }
        let preparedCount = requests.reduce(into: 0) { count, request in
            if uniformCache[request.cacheKey] != nil {
                count += 1
            }
        }

        let runTextures = requests.compactMap { uniformCache[$0.cacheKey] }
        let preloadStartedAt = ProcessInfo.processInfo.systemUptime
        var preloadedCount = 0
        for texture in runTextures {
            guard !Task.isCancelled else { break }
            if await uniformTexturePreloader.preload(texture) {
                preloadedCount += 1
            }
            guard !Task.isCancelled else { break }
        }
        let preloadDuration = (
            ProcessInfo.processInfo.systemUptime - preloadStartedAt
        ) * 1_000
        if !Task.isCancelled,
           preparedCount == requests.count,
           preloadedCount == requests.count {
            preparedRunAssetRoots.insert(uniformAssetRoots)
        }

        return UniformTexturePrewarmResult(
            requestedCount: requests.count,
            preparedCount: preparedCount,
            preloadedCount: preloadedCount,
            durationMilliseconds: (
                ProcessInfo.processInfo.systemUptime - startedAt
            ) * 1_000,
            preprocessingDurationMilliseconds: preprocessingDuration,
            mainActorInstallationDurationMilliseconds: maximumInstallationBatchMilliseconds,
            totalMainActorInstallationDurationMilliseconds: totalInstallationMilliseconds,
            spriteKitPreloadDurationMilliseconds: preloadDuration
        )
    }

    private func makePreparationRequests(
        genericFramePaths: [String],
        assetRoot: GameplayJerseyAssetRoot
    ) -> [UniformTexturePreparationRequest] {
        genericFramePaths.compactMap { genericFramePath in
            guard let bakedFramePath = assetRoot.framePath(for: genericFramePath) else {
                return nil
            }
            let fallbackPath: String?
            switch gameplayUniformFallbackPolicy {
            case .disabled:
                fallbackPath = nil
            case .developmentGeneric:
                fallbackPath = genericFramePath
            }
            return UniformTexturePreparationRequest(
                relativePath: bakedFramePath,
                developmentFallbackRelativePath: fallbackPath,
                cacheKey: UniformTextureCacheKey(
                    assetRoot: assetRoot,
                    genericFramePath: genericFramePath
                )
            )
        }
    }

    private func acquireUniformPrewarmTurn() async {
        while uniformPrewarmIsActive {
            await withCheckedContinuation { continuation in
                uniformPrewarmWaiters.append(continuation)
            }
        }
        uniformPrewarmIsActive = true
    }

    private func releaseUniformPrewarmTurn() {
        uniformPrewarmIsActive = false
        let waiters = uniformPrewarmWaiters
        uniformPrewarmWaiters.removeAll(keepingCapacity: true)
        waiters.forEach { $0.resume() }
    }

    private func acquireFieldPrewarmTurn() async {
        while fieldPrewarmIsActive {
            await withCheckedContinuation { continuation in
                fieldPrewarmWaiters.append(continuation)
            }
        }
        fieldPrewarmIsActive = true
    }

    private func releaseFieldPrewarmTurn() {
        fieldPrewarmIsActive = false
        let waiters = fieldPrewarmWaiters
        fieldPrewarmWaiters.removeAll(keepingCapacity: true)
        waiters.forEach { $0.resume() }
    }

    private func emptyFieldPreloadResult(
        requestedCount: Int,
        startedAt: TimeInterval
    ) -> GameplayFieldTexturePreloadResult {
        GameplayFieldTexturePreloadResult(
            requestedCount: requestedCount,
            loadedCount: 0,
            preloadedCount: 0,
            durationMilliseconds: (
                ProcessInfo.processInfo.systemUptime - startedAt
            ) * 1_000,
            spriteKitPreloadDurationMilliseconds: 0
        )
    }

    private func emptyPrewarmResult(
        requestedCount: Int,
        startedAt: TimeInterval
    ) -> UniformTexturePrewarmResult {
        UniformTexturePrewarmResult(
            requestedCount: requestedCount,
            preparedCount: 0,
            preloadedCount: 0,
            durationMilliseconds: (
                ProcessInfo.processInfo.systemUptime - startedAt
            ) * 1_000,
            preprocessingDurationMilliseconds: 0,
            mainActorInstallationDurationMilliseconds: 0,
            totalMainActorInstallationDurationMilliseconds: 0,
            spriteKitPreloadDurationMilliseconds: 0
        )
    }

    private func cachedPrewarmResult(
        requestedCount: Int,
        startedAt: TimeInterval
    ) -> UniformTexturePrewarmResult {
        UniformTexturePrewarmResult(
            requestedCount: requestedCount,
            preparedCount: requestedCount,
            preloadedCount: requestedCount,
            durationMilliseconds: (
                ProcessInfo.processInfo.systemUptime - startedAt
            ) * 1_000,
            preprocessingDurationMilliseconds: 0,
            mainActorInstallationDurationMilliseconds: 0,
            totalMainActorInstallationDurationMilliseconds: 0,
            spriteKitPreloadDurationMilliseconds: 0
        )
    }

    private func makePrewarmResult(
        requests: [UniformTexturePreparationRequest],
        startedAt: TimeInterval,
        preprocessingDurationMilliseconds: Double,
        maximumInstallationBatchMilliseconds: Double = 0,
        totalInstallationMilliseconds: Double = 0,
        preloadDurationMilliseconds: Double = 0,
        preloadedCount: Int = 0
    ) -> UniformTexturePrewarmResult {
        let preparedCount = requests.reduce(into: 0) { count, request in
            if uniformCache[request.cacheKey] != nil {
                count += 1
            }
        }
        return UniformTexturePrewarmResult(
            requestedCount: requests.count,
            preparedCount: preparedCount,
            preloadedCount: preloadedCount,
            durationMilliseconds: (
                ProcessInfo.processInfo.systemUptime - startedAt
            ) * 1_000,
            preprocessingDurationMilliseconds: preprocessingDurationMilliseconds,
            mainActorInstallationDurationMilliseconds: maximumInstallationBatchMilliseconds,
            totalMainActorInstallationDurationMilliseconds: totalInstallationMilliseconds,
            spriteKitPreloadDurationMilliseconds: preloadDurationMilliseconds
        )
    }

    func emblemTexture(for identity: TeamVisualIdentity, size: CGSize) -> SKTexture {
        let pixelWidth = max(1, Int(size.width.rounded()))
        let pixelHeight = max(1, Int(size.height.rounded()))
        let key = "emblem:\(identity.teamID.rawValue):\(pixelWidth)x\(pixelHeight)"
        if let cached = cache[key] {
            return cached
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: pixelWidth, height: pixelHeight),
            format: format
        )
        let image = renderer.image { rendererContext in
            drawEmblem(
                identity.emblem,
                palette: identity.palette,
                size: CGSize(width: pixelWidth, height: pixelHeight),
                in: rendererContext.cgContext
            )
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        cache[key] = texture
        return texture
    }

    private func install(_ prepared: PreparedUniformTexture) -> Bool {
        guard let provider = CGDataProvider(data: prepared.rgbaData as CFData),
              let image = CGImage(
                  width: prepared.width,
                  height: prepared.height,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: prepared.bytesPerRow,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo(
                      rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
                  ),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: false,
                  intent: .defaultIntent
              )
        else {
            return false
        }
        let texture = SKTexture(cgImage: image)
        texture.filteringMode = .nearest
        uniformCache[prepared.cacheKey] = texture
        return true
    }

    private func drawEmblem(
        _ emblem: EmblemDefinition,
        palette: TeamBrandPalette,
        size: CGSize,
        in context: CGContext
    ) {
        let scale = min(size.width, size.height)
        let origin = CGPoint(x: (size.width - scale) / 2, y: (size.height - scale) / 2)

        func point(_ unitPoint: UnitPoint2D) -> CGPoint {
            CGPoint(
                x: origin.x + CGFloat(unitPoint.x) * scale,
                y: origin.y + (1 - CGFloat(unitPoint.y)) * scale
            )
        }

        func color(_ role: BrandPaletteRole) -> UIColor {
            palette.color(for: role).uiColor
        }

        context.setLineCap(.round)
        context.setLineJoin(.round)

        for primitive in emblem.primitives {
            let path = CGMutablePath()
            switch primitive {
            case let .disk(center, radius, fill):
                let center = point(center)
                let radius = CGFloat(radius) * scale
                path.addEllipse(in: CGRect(
                    x: center.x - radius,
                    y: center.y - radius,
                    width: radius * 2,
                    height: radius * 2
                ))
                context.addPath(path)
                context.setFillColor(color(fill).cgColor)
                context.fillPath()

            case let .ring(center, radius, lineWidth, role):
                let center = point(center)
                let radius = CGFloat(radius) * scale
                path.addEllipse(in: CGRect(
                    x: center.x - radius,
                    y: center.y - radius,
                    width: radius * 2,
                    height: radius * 2
                ))
                context.addPath(path)
                context.setStrokeColor(color(role).cgColor)
                context.setLineWidth(CGFloat(lineWidth) * scale)
                context.strokePath()

            case let .arc(center, radius, startDegrees, endDegrees, lineWidth, role):
                path.addArc(
                    center: point(center),
                    radius: CGFloat(radius) * scale,
                    startAngle: CGFloat(-startDegrees * .pi / 180),
                    endAngle: CGFloat(-endDegrees * .pi / 180),
                    clockwise: true
                )
                context.addPath(path)
                context.setStrokeColor(color(role).cgColor)
                context.setLineWidth(CGFloat(lineWidth) * scale)
                context.strokePath()

            case let .polygon(vertices, fill):
                guard let first = vertices.first else { continue }
                path.move(to: point(first))
                vertices.dropFirst().forEach { path.addLine(to: point($0)) }
                path.closeSubpath()
                context.addPath(path)
                context.setFillColor(color(fill).cgColor)
                context.fillPath()

            case let .polyline(vertices, lineWidth, role):
                guard let first = vertices.first else { continue }
                path.move(to: point(first))
                vertices.dropFirst().forEach { path.addLine(to: point($0)) }
                context.addPath(path)
                context.setStrokeColor(color(role).cgColor)
                context.setLineWidth(CGFloat(lineWidth) * scale)
                context.strokePath()

            case let .roundedBar(frame, cornerRadius, fill):
                let rect = CGRect(
                    x: origin.x + CGFloat(frame.x) * scale,
                    y: origin.y + (1 - CGFloat(frame.y + frame.height)) * scale,
                    width: CGFloat(frame.width) * scale,
                    height: CGFloat(frame.height) * scale
                )
                path.addPath(
                    CGPath(
                        roundedRect: rect,
                        cornerWidth: CGFloat(cornerRadius) * scale,
                        cornerHeight: CGFloat(cornerRadius) * scale,
                        transform: nil
                    )
                )
                context.addPath(path)
                context.setFillColor(color(fill).cgColor)
                context.fillPath()
            }
        }
    }
}

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

struct UniformPixel: Equatable, Sendable {
    let red: UInt8
    let green: UInt8
    let blue: UInt8
    let alpha: UInt8
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

struct UniformRaster: Equatable, Sendable {
    let width: Int
    let height: Int
    let bytesPerRow: Int
    var bytes: [UInt8]

    func pixel(x: Int, y: Int) -> UniformPixel? {
        guard (0 ..< width).contains(x), (0 ..< height).contains(y) else { return nil }
        let offset = y * bytesPerRow + x * 4
        return UniformPixel(
            red: bytes[offset],
            green: bytes[offset + 1],
            blue: bytes[offset + 2],
            alpha: bytes[offset + 3]
        )
    }
}

struct UniformTexturePreparationRequest: Sendable {
    let relativePath: String
    let cacheKey: UniformTextureCacheKey
    let palette: UniformSpritePalette
    let role: UniformSquadRole
}

struct PreparedUniformTexture: Sendable {
    let cacheKey: UniformTextureCacheKey
    let width: Int
    let height: Int
    let bytesPerRow: Int
    let rgbaData: Data
}

struct UniformTextureCacheKey: Hashable, Sendable {
    let relativePath: String
    let palette: UniformSpritePalette
    let role: UniformSquadRole
}

/// Recolors only the authored red offense or blue defense uniform regions. Skin, hair, shoes,
/// transparent pixels, and field-independent sprite detail remain unchanged. Position-aware slot
/// selection lets the shared launch sprites express helmet, shoulder, number, pants, and sock
/// colors without multiplying the shipped raster asset set by every team and jersey.
enum UniformTextureProjection {
    @inline(__always)
    static func project(
        _ source: UniformPixel,
        normalizedX: CGFloat,
        normalizedY: CGFloat,
        role: UniformSquadRole,
        palette: UniformSpritePalette
    ) -> UniformPixel {
        guard source.alpha >= 16 else { return source }

        // Channel ratios are unchanged by Quartz premultiplication. Integer comparisons avoid
        // millions of HSV conversions during a cold prewarm while retaining the exact authored
        // red/blue hue windows and alpha-relative brightness thresholds.
        let red = Int(source.red)
        let green = Int(source.green)
        let blue = Int(source.blue)
        let alpha = Int(source.alpha)
        let maximum = max(red, green, blue)
        let minimum = min(red, green, blue)
        let delta = maximum - minimum
        let hasUniformSaturation = delta * 100 > maximum * 28
        let hasUniformBrightness = maximum * 100 > alpha * 18

        let isAuthoredUniformColor: Bool
        switch role {
        case .offense:
            isAuthoredUniformColor = hasUniformSaturation
                && hasUniformBrightness
                && red == maximum
                && abs(green - blue) * 60 <= delta * 16
        case .defense:
            let greenBlueSeparation = green - red
            isAuthoredUniformColor = hasUniformSaturation
                && hasUniformBrightness
                && blue == maximum
                && greenBlueSeparation * 60 >= delta * 5
                && greenBlueSeparation * 60 <= delta * 55
        }

        let target: RGBColor?
        if isAuthoredUniformColor {
            if isHelmetShellSlot(normalizedX: normalizedX, normalizedY: normalizedY) {
                target = palette.helmetShell
            } else if normalizedY < 0.51 && (normalizedX < 0.36 || normalizedX > 0.64) {
                target = palette.shoulderPanel
            } else if normalizedY > 0.68 {
                target = palette.socks
            } else {
                target = palette.jerseyBody
            }
        } else if delta * 100 < maximum * 11,
                  minimum * 100 > alpha * 42,
                  maximum * 100 > alpha * 58,
                  !isFaceDetail(normalizedX: normalizedX, normalizedY: normalizedY) {
            if normalizedY < 0.30 {
                target = palette.helmetDetail
            } else if normalizedY > 0.52 {
                target = palette.pants
            } else {
                target = palette.numberAndName
            }
        } else {
            target = nil
        }

        guard let target else { return source }
        let sourceValue = Double(maximum) / Double(alpha)
        return UniformPixel(
            red: premultiplied(
                shaded(target.red, sourceValue: sourceValue),
                alpha: source.alpha
            ),
            green: premultiplied(
                shaded(target.green, sourceValue: sourceValue),
                alpha: source.alpha
            ),
            blue: premultiplied(
                shaded(target.blue, sourceValue: sourceValue),
                alpha: source.alpha
            ),
            alpha: source.alpha
        )
    }

    private static func isFaceDetail(normalizedX: CGFloat, normalizedY: CGFloat) -> Bool {
        (0.29 ... 0.71).contains(normalizedX) && (0.17 ... 0.34).contains(normalizedY)
    }

    private static func isHelmetShellSlot(
        normalizedX: CGFloat,
        normalizedY: CGFloat
    ) -> Bool {
        normalizedY < 0.29 || (
            normalizedY < 0.43 && (0.30 ... 0.70).contains(normalizedX)
        )
    }

    @inline(__always)
    private static func shaded(_ component: UInt8, sourceValue: Double) -> UInt8 {
        let multiplier = 0.44 + sourceValue * 0.78
        let highlightLift = max(0, sourceValue - 0.72) * 145
        let value = Double(component) * multiplier + highlightLift
        return UInt8(max(0, min(255, value.rounded())))
    }

    @inline(__always)
    private static func premultiplied(_ component: UInt8, alpha: UInt8) -> UInt8 {
        UInt8((Double(component) * Double(alpha) / 255).rounded())
    }
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

/// Decodes and recolors the finite run sprite set on the cooperative executor. No UIKit or
/// SpriteKit object crosses this boundary; the main actor receives plain RGBA bytes and only
/// performs the short final `SKTexture` installation step.
enum UniformRasterPreprocessor {
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

    static func projectedRaster(
        _ source: UniformRaster,
        palette: UniformSpritePalette,
        role: UniformSquadRole
    ) -> UniformRaster {
        var output = source
        let normalizedX = (0 ..< output.width).map {
            CGFloat($0) / CGFloat(max(1, output.width - 1))
        }
        output.bytes.withUnsafeMutableBufferPointer { pixels in
            for y in 0 ..< output.height {
                guard !Task.isCancelled else { return }
                // The decoded RGBA buffer preserves authored top-to-bottom raster row order.
                let normalizedY = CGFloat(y) / CGFloat(max(1, output.height - 1))
                for x in 0 ..< output.width {
                    let offset = y * output.bytesPerRow + x * 4
                    // Roughly three quarters of every actor frame is transparent padding.
                    guard pixels[offset + 3] >= 16 else { continue }
                    let projected = UniformTextureProjection.project(
                        UniformPixel(
                            red: pixels[offset],
                            green: pixels[offset + 1],
                            blue: pixels[offset + 2],
                            alpha: pixels[offset + 3]
                        ),
                        normalizedX: normalizedX[x],
                        normalizedY: normalizedY,
                        role: role,
                        palette: palette
                    )
                    pixels[offset] = projected.red
                    pixels[offset + 1] = projected.green
                    pixels[offset + 2] = projected.blue
                    pixels[offset + 3] = projected.alpha
                }
            }
        }
        return output
    }

    static func prepare(
        _ request: UniformTexturePreparationRequest
    ) -> PreparedUniformTexture? {
        guard !Task.isCancelled,
              let source = loadRaster(relativePath: request.relativePath)
        else {
            return nil
        }
        let projected = projectedRaster(source, palette: request.palette, role: request.role)
        guard !Task.isCancelled else { return nil }
        return PreparedUniformTexture(
            cacheKey: request.cacheKey,
            width: projected.width,
            height: projected.height,
            bytesPerRow: projected.bytesPerRow,
            rgbaData: Data(projected.bytes)
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

struct ConcurrentUniformTexturePreparer: UniformTexturePreparing {
    func prepare(
        _ requests: [UniformTexturePreparationRequest]
    ) async -> [PreparedUniformTexture] {
        await UniformRasterPreprocessor.prepare(requests)
    }
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
    private struct RunUniformPaletteKey: Hashable {
        let offense: UniformSpritePalette
        let defense: UniformSpritePalette
    }

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
    private var preparedRunPalettes: Set<RunUniformPaletteKey> = []
    private var uniformPrewarmIsActive = false
    private var uniformPrewarmWaiters: [CheckedContinuation<Void, Never>] = []
    private let uniformTexturePreparer: any UniformTexturePreparing
    private let uniformTexturePreloader: any UniformTexturePreloading

    init(
        uniformTexturePreparer: any UniformTexturePreparing = ConcurrentUniformTexturePreparer(),
        uniformTexturePreloader: any UniformTexturePreloading = SpriteKitUniformTexturePreloader()
    ) {
        self.uniformTexturePreparer = uniformTexturePreparer
        self.uniformTexturePreloader = uniformTexturePreloader
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
        _ relativePath: String,
        palette: UniformSpritePalette,
        role: UniformSquadRole
    ) -> SKTexture? {
        uniformCache[UniformTextureCacheKey(
            relativePath: relativePath,
            palette: palette,
            role: role
        )]
    }

    /// Prepares every finite animation texture used by one run. Raster decode and palette
    /// projection run off the main actor; only the final texture-cache installation returns here.
    /// `GameScene` exposes a visible readiness state and does not start its countdown until this
    /// completes, so gameplay-time frame swaps are cache reads without a frozen transition.
    func prewarmRunUniformTextures(
        offensePalette: UniformSpritePalette,
        defensePalette: UniformSpritePalette
    ) async -> UniformTexturePrewarmResult {
        let startedAt = ProcessInfo.processInfo.systemUptime
        let requestedCount = Self.offenseUniformPaths.count + Self.defenseUniformPaths.count
        let runPaletteKey = RunUniformPaletteKey(
            offense: offensePalette,
            defense: defensePalette
        )
        guard !Task.isCancelled else {
            return emptyPrewarmResult(requestedCount: requestedCount, startedAt: startedAt)
        }
        if preparedRunPalettes.contains(runPaletteKey) {
            return cachedPrewarmResult(requestedCount: requestedCount, startedAt: startedAt)
        }

        await acquireUniformPrewarmTurn()
        defer { releaseUniformPrewarmTurn() }

        guard !Task.isCancelled else {
            return emptyPrewarmResult(requestedCount: requestedCount, startedAt: startedAt)
        }
        // A preceding serialized request may have completed this palette while
        // the current caller was waiting for its turn.
        if preparedRunPalettes.contains(runPaletteKey) {
            return cachedPrewarmResult(requestedCount: requestedCount, startedAt: startedAt)
        }

        let requests = Self.offenseUniformPaths.map { path in
            UniformTexturePreparationRequest(
                relativePath: path,
                cacheKey: UniformTextureCacheKey(
                    relativePath: path,
                    palette: offensePalette,
                    role: .offense
                ),
                palette: offensePalette,
                role: .offense
            )
        } + Self.defenseUniformPaths.map { path in
            UniformTexturePreparationRequest(
                relativePath: path,
                cacheKey: UniformTextureCacheKey(
                    relativePath: path,
                    palette: defensePalette,
                    role: .defense
                ),
                palette: defensePalette,
                role: .defense
            )
        }

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
            preparedRunPalettes.insert(runPaletteKey)
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

import SpriteKit
import UIKit

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

@MainActor
final class TextureLibrary {
    private var cache: [String: SKTexture] = [:]

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
}

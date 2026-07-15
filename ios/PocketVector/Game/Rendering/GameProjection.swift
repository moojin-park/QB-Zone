import CoreGraphics
import Foundation

struct GameSafeAreaInsets: Equatable {
    let top: CGFloat
    let left: CGFloat
    let bottom: CGFloat
    let right: CGFloat

    static let zero = GameSafeAreaInsets(top: 0, left: 0, bottom: 0, right: 0)
}

/// Converts the physical SpriteKit view into the app's fixed-height logical canvas.
///
/// The field is full bleed. Safe-area insets constrain HUD and controls only.
struct GameViewport: Equatable {
    let viewSize: CGSize
    let safeAreaInsets: GameSafeAreaInsets
    let projection: GameProjection
    let pointsPerSceneUnit: CGFloat
    let safeSceneFrame: CGRect

    static let canonical = GameViewport(
        viewSize: GameProjection.classicSceneSize,
        safeAreaInsets: .zero
    )

    init(viewSize: CGSize, safeAreaInsets: GameSafeAreaInsets) {
        let resolvedHeight = max(1, viewSize.height)
        let displayScale = resolvedHeight / GameProjection.logicalHeight
        let logicalWidth = min(
            GameProjection.maximumFieldArtWidth,
            max(
                GameProjection.classicWidth,
                GameProjection.logicalHeight * max(1, viewSize.width) / resolvedHeight
            )
        )
        let projection = GameProjection(viewportWidth: logicalWidth)

        let left = min(logicalWidth, max(0, safeAreaInsets.left / displayScale))
        let right = min(
            max(0, logicalWidth - left),
            max(0, safeAreaInsets.right / displayScale)
        )
        let bottom = min(
            GameProjection.logicalHeight,
            max(0, safeAreaInsets.bottom / displayScale)
        )
        let top = min(
            max(0, GameProjection.logicalHeight - bottom),
            max(0, safeAreaInsets.top / displayScale)
        )

        self.viewSize = viewSize
        self.safeAreaInsets = safeAreaInsets
        self.projection = projection
        pointsPerSceneUnit = displayScale
        safeSceneFrame = CGRect(
            x: left,
            y: bottom,
            width: max(0, logicalWidth - left - right),
            height: max(0, GameProjection.logicalHeight - top - bottom)
        )
    }
}

/// Immutable world-to-screen projection.
///
/// Rendering owns a viewport-width instance. Simulation continues to use the
/// static canonical helpers below, so device relayout cannot affect outcomes.
struct GameProjection: Equatable {
    static let logicalHeight: CGFloat = 768
    static let classicWidth: CGFloat = 1_024
    static let classicSceneSize = CGSize(width: classicWidth, height: logicalHeight)
    static let maximumFieldArtWidth: CGFloat = 1_728

    /// Compatibility name for canonical simulation and unit-test geometry.
    static let sceneSize = classicSceneSize
    static let classic = GameProjection(viewportWidth: classicWidth)

    static let horizonY: CGFloat = 232
    static let nearGroundY: CGFloat = 895
    static let farHalfWidthPixels = FieldBoundaryLayout.farHalfWidthPixels
    static let nearHalfWidthPixels = FieldBoundaryLayout.nearHalfWidthPixels
    static let depthExponent: CGFloat = 2
    static let farActorScale: CGFloat = 0.25
    static let nearActorScale: CGFloat = 1
    static let actorHeightPixels: CGFloat = 300
    static let actorSpriteSize = CGSize(width: 270, height: 360)

    let viewportWidth: CGFloat

    init(viewportWidth: CGFloat) {
        self.viewportWidth = max(Self.classicWidth, viewportWidth)
    }

    var sceneSize: CGSize {
        CGSize(width: viewportWidth, height: Self.logicalHeight)
    }

    var centerX: CGFloat {
        viewportWidth / 2
    }

    var quarterbackHitFrame: CGRect {
        CGRect(x: centerX - 140, y: 0, width: 280, height: 220)
    }

    static func perspectiveFactor(depth: CGFloat) -> CGFloat {
        pow(1 - clamp(depth, minimum: 0, maximum: 1), depthExponent)
    }

    static func actorScale(depth: CGFloat) -> CGFloat {
        let perspective = perspectiveFactor(depth: depth)
        return farActorScale + (nearActorScale - farActorScale) * perspective
    }

    static func groundScreenY(depth: CGFloat) -> CGFloat {
        let perspective = perspectiveFactor(depth: depth)
        return horizonY + (nearGroundY - horizonY) * perspective
    }

    func halfFieldWidth(depth: CGFloat) -> CGFloat {
        let perspective = Self.perspectiveFactor(depth: depth)
        return Self.farHalfWidthPixels
            + (Self.nearHalfWidthPixels - Self.farHalfWidthPixels) * perspective
    }

    /// The absolute world X where an actor's trailing edge has cleared this viewport.
    func worldXForActorToClearViewport(
        depth: CGFloat,
        actorWidthPixels: CGFloat,
        paddingPixels: CGFloat = 0
    ) -> CGFloat {
        let scaledHalfWidth = actorWidthPixels * Self.actorScale(depth: depth) / 2
        return (centerX + scaledHalfWidth + max(0, paddingPixels))
            / halfFieldWidth(depth: depth)
    }

    func worldToScene(_ point: WorldPoint) -> CGPoint {
        let scale = Self.actorScale(depth: point.depth)
        let x = centerX + point.x * halfFieldWidth(depth: point.depth)
        let browserY = Self.groundScreenY(depth: point.depth)
            - point.height * Self.actorHeightPixels * scale
        return CGPoint(x: x, y: Self.logicalHeight - browserY)
    }

    func sceneToWorld(_ point: CGPoint) -> WorldPoint {
        let browserY = Self.logicalHeight - point.y
        let normalizedPerspective = Self.clamp(
            (browserY - Self.horizonY) / (Self.nearGroundY - Self.horizonY),
            minimum: 0,
            maximum: 1
        )
        let depth = 1 - pow(normalizedPerspective, 1 / Self.depthExponent)
        let halfWidth = halfFieldWidth(depth: depth)
        return WorldPoint(
            x: Self.clamp((point.x - centerX) / halfWidth, minimum: -1.18, maximum: 1.18),
            depth: depth,
            height: 0
        )
    }

    func isPointOnQuarterback(_ point: CGPoint) -> Bool {
        quarterbackHitFrame.contains(point)
    }

    /// Canonical wrappers retained for deterministic simulation and existing tests.
    static func halfFieldWidth(depth: CGFloat) -> CGFloat {
        classic.halfFieldWidth(depth: depth)
    }

    static func worldToScene(_ point: WorldPoint) -> CGPoint {
        classic.worldToScene(point)
    }

    static func sceneToWorld(_ point: CGPoint) -> WorldPoint {
        classic.sceneToWorld(point)
    }

    static func isPointOnQuarterback(_ point: CGPoint) -> Bool {
        classic.isPointOnQuarterback(point)
    }

    private static func clamp(_ value: CGFloat, minimum: CGFloat, maximum: CGFloat) -> CGFloat {
        max(minimum, min(maximum, value))
    }
}

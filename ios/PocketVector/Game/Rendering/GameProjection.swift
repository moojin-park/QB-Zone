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
/// The field is full bleed. Safe-area insets constrain HUD, controls, and the
/// lower-field region where a throw may begin.
struct GameViewport: Equatable {
    let viewSize: CGSize
    let safeAreaInsets: GameSafeAreaInsets
    let projection: GameProjection
    let pointsPerSceneUnit: CGFloat
    let safeSceneFrame: CGRect

    var letterboxLayout: GameplayLetterboxLayout {
        GameplayLetterboxLayout(viewport: self)
    }

    /// The unobstructed lower-field band where a throw gesture may begin.
    /// Release points remain free to travel beyond this frame.
    var throwActivationFrame: CGRect {
        let top = min(safeSceneFrame.maxY, GameProjection.throwActivationTopY)
        let bottom = max(safeSceneFrame.minY, letterboxLayout.finalSceneHeight)
        return CGRect(
            x: safeSceneFrame.minX,
            y: bottom,
            width: safeSceneFrame.width,
            height: max(0, top - bottom)
        )
    }

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

    func containsThrowActivationPoint(_ point: CGPoint) -> Bool {
        let frame = throwActivationFrame
        return point.x >= frame.minX
            && point.x <= frame.maxX
            && point.y >= frame.minY
            && point.y <= frame.maxY
    }
}

/// Responsive, render-only geometry and timing for the gameplay letterbox.
///
/// The completed bar height is specified in rendered points, then converted
/// into the fixed-height SpriteKit coordinate space. Countdown progress is
/// sampled from authoritative simulation state so frame partitioning cannot
/// change the presentation.
struct GameplayLetterboxLayout: Equatable {
    static let minimumRenderedHeight: CGFloat = 18
    static let viewportHeightFraction: CGFloat = 0.05
    static let maximumRenderedHeight: CGFloat = 32

    let finalRenderedHeight: CGFloat
    let finalSceneHeight: CGFloat

    init(viewport: GameViewport) {
        finalRenderedHeight = min(
            Self.maximumRenderedHeight,
            max(
                Self.minimumRenderedHeight,
                viewport.viewSize.height * Self.viewportHeightFraction
            )
        )
        finalSceneHeight = finalRenderedHeight / max(0.001, viewport.pointsPerSceneUnit)
    }

    func progress(
        phase: GamePhase,
        countdownRemainingMilliseconds: CGFloat,
        reducedMotion: Bool
    ) -> CGFloat {
        switch phase {
        case .countdown:
            if reducedMotion { return 1 }
            let linearProgress = min(1, max(
                0,
                1 - countdownRemainingMilliseconds
                    / GameplayConfig.countdownDurationMilliseconds
            ))
            return linearProgress * linearProgress * (3 - 2 * linearProgress)
        case .playing, .resolvingFinalBall, .paused:
            return 1
        case .title, .results:
            return 0
        }
    }

    func currentSceneHeight(
        phase: GamePhase,
        countdownRemainingMilliseconds: CGFloat,
        reducedMotion: Bool
    ) -> CGFloat {
        finalSceneHeight * progress(
            phase: phase,
            countdownRemainingMilliseconds: countdownRemainingMilliseconds,
            reducedMotion: reducedMotion
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
    static let throwActivationTopY: CGFloat = 225

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

    private static func clamp(_ value: CGFloat, minimum: CGFloat, maximum: CGFloat) -> CGFloat {
        max(minimum, min(maximum, value))
    }
}

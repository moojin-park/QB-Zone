import CoreGraphics

enum FieldBoundarySide: CGFloat, CaseIterable {
    case left = -1
    case right = 1
}

/// One source of truth for the widened field edge used by projection, art, and
/// sideline staff. The half-widths are the straight-line fit of the original
/// outside hash trajectory on the 1728x768 field plate.
struct FieldBoundaryLayout {
    static let farHalfWidthPixels: CGFloat = 459
    static let nearHalfWidthPixels: CGFloat = 1_226

    static let endZoneBackBrowserY: CGFloat = 230
    static let endZoneFrontBrowserY: CGFloat = 291

    static func halfWidth(atBrowserY browserY: CGFloat) -> CGFloat {
        interpolatedHalfWidth(
            atBrowserY: browserY,
            far: farHalfWidthPixels,
            near: nearHalfWidthPixels
        )
    }

    static func boundaryPoint(
        side: FieldBoundarySide,
        browserY: CGFloat,
        projection: GameProjection
    ) -> CGPoint {
        CGPoint(
            x: projection.centerX + side.rawValue * halfWidth(atBrowserY: browserY),
            y: GameProjection.logicalHeight - browserY
        )
    }

    /// Returns a deterministic staff position in the visible out-of-bounds
    /// wedge. Narrow viewports naturally return nil once the sideline is beyond
    /// the screen, so decorative people never enter the playable field.
    static func staffPosition(
        side: FieldBoundarySide,
        browserY: CGFloat,
        preferredInset: CGFloat,
        projection: GameProjection,
        footprintHalfWidth: CGFloat = 18
    ) -> CGPoint? {
        let boundary = boundaryPoint(side: side, browserY: browserY, projection: projection)
        let availableWidth = side == .left
            ? boundary.x
            : projection.viewportWidth - boundary.x
        let safeHalfWidth = max(0, footprintHalfWidth)
        let viewportEdgePadding: CGFloat = 18
        guard availableWidth >= 2 * safeHalfWidth + viewportEdgePadding else { return nil }

        let inset = min(
            max(24, max(safeHalfWidth, preferredInset)),
            availableWidth - safeHalfWidth - viewportEdgePadding
        )
        return CGPoint(
            x: boundary.x + side.rawValue * inset,
            y: boundary.y
        )
    }

    private static func interpolatedHalfWidth(
        atBrowserY browserY: CGFloat,
        far: CGFloat,
        near: CGFloat
    ) -> CGFloat {
        let perspective = (browserY - GameProjection.horizonY)
            / (GameProjection.nearGroundY - GameProjection.horizonY)
        return far + (near - far) * perspective
    }
}

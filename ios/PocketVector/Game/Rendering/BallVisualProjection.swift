import CoreGraphics
import Foundation

struct BallVisualState: Equatable {
    let headingRadians: CGFloat
    let laceOffset: CGFloat
    let laceOpacity: CGFloat
    let highlightOffset: CGFloat
}

enum BallVisualProjection {
    static let fullRoll = CGFloat.pi * 2

    static func visualState(
        for ball: BallState,
        projection: GameProjection = .classic
    ) -> BallVisualState {
        let current = projection.worldToScene(ball.current)
        let previous = projection.worldToScene(ball.previous)
        let fallbackProgress = min(
            1,
            ball.elapsedMilliseconds / ball.durationMilliseconds + 0.02
        )
        let fallbackWorld = Trajectory.position(
            start: ball.start,
            end: ball.end,
            arcHeight: ball.arcHeight,
            progress: fallbackProgress
        )
        let fallback = projection.worldToScene(fallbackWorld)
        let heading = headingRadians(
            previous: previous,
            current: current,
            fallback: fallback
        )
        let roll = normalizedRoll(ball.rollRadians)
        let frontFacing = max(0, cos(roll))

        return BallVisualState(
            headingRadians: heading,
            laceOffset: sin(roll) * 5.5,
            laceOpacity: pow(frontFacing, 0.55),
            highlightOffset: -sin(roll) * 3
        )
    }

    static func headingRadians(
        previous: CGPoint,
        current: CGPoint,
        fallback: CGPoint
    ) -> CGFloat {
        var deltaX = current.x - previous.x
        var deltaY = current.y - previous.y
        if hypot(deltaX, deltaY) < 0.01 {
            deltaX = fallback.x - current.x
            deltaY = fallback.y - current.y
        }
        guard hypot(deltaX, deltaY) >= 0.01 else { return 0 }
        return atan2(deltaY, deltaX)
    }

    static func normalizedRoll(_ rollRadians: CGFloat) -> CGFloat {
        let remainder = rollRadians.truncatingRemainder(dividingBy: fullRoll)
        return remainder >= 0 ? remainder : remainder + fullRoll
    }
}

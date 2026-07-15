import CoreGraphics
import Foundation

struct TrajectoryParameters: Equatable {
    let durationMilliseconds: CGFloat
    let arcHeight: CGFloat
    let end: WorldPoint
    let normalizedSpeed: CGFloat
}

enum Trajectory {
    static func normalizedThrowSpeed(_ releaseSpeed: CGFloat) -> CGFloat {
        let slow = GameplayConfig.Throw.slowSpeedPixelsPerMillisecond
        let fast = GameplayConfig.Throw.fastSpeedPixelsPerMillisecond
        return clamp((releaseSpeed - slow) / (fast - slow), minimum: 0, maximum: 1)
    }

    static func parameters(
        start: WorldPoint,
        target: WorldPoint,
        releaseSpeedPixelsPerMillisecond: CGFloat
    ) -> TrajectoryParameters {
        let speed = normalizedThrowSpeed(releaseSpeedPixelsPerMillisecond)
        let distance = hypot(target.x - start.x, target.depth - start.depth)
        let distanceFactor = min(1, distance)
        let baseDuration = lerp(
            GameplayConfig.Throw.maximumDurationMilliseconds,
            GameplayConfig.Throw.minimumDurationMilliseconds,
            speed
        )
        let duration = baseDuration * lerp(0.86, 1.12, distanceFactor)
        let arc = lerp(
            GameplayConfig.Throw.maximumArcHeight,
            GameplayConfig.Throw.minimumArcHeight,
            speed
        )
        let end = WorldPoint(x: target.x, depth: min(1.08, target.depth), height: target.height)
        return TrajectoryParameters(
            durationMilliseconds: duration,
            arcHeight: arc,
            end: end,
            normalizedSpeed: speed
        )
    }

    static func position(
        start: WorldPoint,
        end: WorldPoint,
        arcHeight: CGFloat,
        progress: CGFloat
    ) -> WorldPoint {
        let time = clamp(progress, minimum: 0, maximum: 1)
        let horizontalProgress = min(1, time / GameplayConfig.Throw.catchProgress)
        return WorldPoint(
            x: lerp(start.x, end.x, horizontalProgress),
            depth: lerp(start.depth, end.depth, horizontalProgress),
            height: max(
                0,
                lerp(start.height, end.height, time) + 4 * arcHeight * time * (1 - time)
            )
        )
    }

    static func makeBall(
        id: Int,
        target: WorldPoint,
        releaseSpeedPixelsPerMillisecond: CGFloat,
        aimMarker: CGPoint
    ) -> BallState {
        let start = GameplayConfig.quarterbackStart
        let trajectory = parameters(
            start: start,
            target: target,
            releaseSpeedPixelsPerMillisecond: releaseSpeedPixelsPerMillisecond
        )
        return BallState(
            id: id,
            elapsedMilliseconds: 0,
            durationMilliseconds: trajectory.durationMilliseconds,
            start: start,
            target: target,
            end: trajectory.end,
            arcHeight: trajectory.arcHeight,
            current: start,
            previous: start,
            rollRadians: 0,
            radiusPixels: GameplayConfig.defaultBallRadiusPixels,
            releaseSpeedPixelsPerMillisecond: releaseSpeedPixelsPerMillisecond,
            aimMarker: aimMarker
        )
    }

    static func advance(ball: inout BallState, deltaMilliseconds: CGFloat) {
        ball.previous = ball.current
        ball.elapsedMilliseconds = min(
            ball.durationMilliseconds,
            ball.elapsedMilliseconds + deltaMilliseconds
        )
        ball.current = position(
            start: ball.start,
            end: ball.end,
            arcHeight: ball.arcHeight,
            progress: ball.elapsedMilliseconds / ball.durationMilliseconds
        )
        ball.rollRadians += deltaMilliseconds * (
            0.014 + min(0.02, ball.releaseSpeedPixelsPerMillisecond * 0.008)
        )
    }

    private static func lerp(_ start: CGFloat, _ end: CGFloat, _ amount: CGFloat) -> CGFloat {
        start + (end - start) * amount
    }

    private static func clamp(_ value: CGFloat, minimum: CGFloat, maximum: CGFloat) -> CGFloat {
        max(minimum, min(maximum, value))
    }
}

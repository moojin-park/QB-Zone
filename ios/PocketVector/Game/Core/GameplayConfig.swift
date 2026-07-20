import CoreGraphics
import Foundation

enum GameplayConfig {
    static let sessionDurationMilliseconds: CGFloat = 60_000
    static let fixedStepMilliseconds: CGFloat = 1_000 / 60
    static let maximumFrameDeltaMilliseconds: CGFloat = 100
    static let finalBallGraceMilliseconds: CGFloat = 2_000
    static let defaultBallRadiusPixels: CGFloat = 12
    static let defaultSeed: UInt32 = 0x50c4e7

    static let quarterbackStart = WorldPoint(x: 0, depth: 0.035, height: 0.56)
    static let receiverSidelineX: CGFloat = 1
    static let receiverOffscreenX: CGFloat = 1.22
    static let receiverMinimumDespawnX: CGFloat = 1.34
    static let receiverDespawnPaddingPixels: CGFloat = 8
    static let receiverOutsideSidelineSpeedMultiplier: CGFloat = 2
    static let receiverSpawnDelay: ClosedRange<CGFloat> = 180 ... 620
    static let defenderPatrolHalfWidth: CGFloat = 0.78
    static let defenderCrossingSeconds: [CGFloat] = [4.7, 5.8, 6.8]
    static let defenderDepths: [CGFloat] = [0.39, 0.58, 0.73]
    static let defenderWidthWorld: CGFloat = 0.22
    static let playResolutionCooldownMilliseconds: CGFloat = 250

    enum Throw {
        static let minimumGestureDistancePixels: CGFloat = 34
        static let slowSpeedPixelsPerMillisecond: CGFloat = 0.25
        static let fastSpeedPixelsPerMillisecond: CGFloat = 1.8
        static let minimumDurationMilliseconds: CGFloat = 430
        static let maximumDurationMilliseconds: CGFloat = 1_180
        static let minimumArcHeight: CGFloat = 0.28
        static let maximumArcHeight: CGFloat = 1.05
        static let catchProgress: CGFloat = 0.82
    }

    static let lanes: [LaneConfig] = [
        LaneConfig(
            id: .short,
            label: "15",
            depth: 0.28,
            completionPoints: 500,
            meterGain: 15,
            crossingSeconds: 4.4,
            catchWidth: 0.17
        ),
        LaneConfig(
            id: .medium,
            label: "30",
            depth: 0.48,
            completionPoints: 1_000,
            meterGain: 35,
            crossingSeconds: 5,
            catchWidth: 0.15
        ),
        LaneConfig(
            id: .deep,
            label: "45",
            depth: 0.68,
            completionPoints: 1_500,
            meterGain: 50,
            crossingSeconds: 5.7,
            catchWidth: 0.14
        ),
        LaneConfig(
            id: .touchdown,
            label: "END ZONE",
            depth: 0.87,
            completionPoints: 2_500,
            meterGain: 0,
            crossingSeconds: 6.3,
            catchWidth: 0.13
        ),
    ]

    static func lane(_ id: LaneID) -> LaneConfig {
        lanes.first(where: { $0.id == id })!
    }

    /// Keeps a runner alive until the entire sprite has cleared the widest field plate.
    /// The per-lane calculation matters because far-lane world units project to fewer pixels.
    static func receiverDespawnX(for laneID: LaneID) -> CGFloat {
        let lane = lane(laneID)
        let widestProjection = GameProjection(
            viewportWidth: GameProjection.maximumFieldArtWidth
        )
        return max(
            receiverMinimumDespawnX,
            widestProjection.worldXForActorToClearViewport(
                depth: lane.depth,
                actorWidthPixels: GameProjection.actorSpriteSize.width,
                paddingPixels: receiverDespawnPaddingPixels
            )
        )
    }

    /// New and recycled receivers start at the same fully-cleared edge used for culling.
    static func receiverSpawnX(for laneID: LaneID) -> CGFloat {
        receiverDespawnX(for: laneID)
    }

    static func defenderSpeedPerMillisecond(index: Int) -> CGFloat {
        let crossingSeconds = defenderCrossingSeconds.indices.contains(index)
            ? defenderCrossingSeconds[index]
            : 5.8
        return (2 * defenderPatrolHalfWidth) / (crossingSeconds * 1_000)
    }
}

/// Pure, frame-partition-independent receiver movement across the two sidelines.
enum ReceiverMotion {
    struct Step: Equatable {
        let x: CGFloat
        let runAnimationDeltaMilliseconds: CGFloat
    }

    static func speedMultiplier(atX x: CGFloat) -> CGFloat {
        abs(x) > GameplayConfig.receiverSidelineX
            ? GameplayConfig.receiverOutsideSidelineSpeedMultiplier
            : 1
    }

    static func position(
        from startX: CGFloat,
        direction: CGFloat,
        baseSpeedPerMillisecond: CGFloat,
        deltaMilliseconds: CGFloat
    ) -> CGFloat {
        step(
            from: startX,
            direction: direction,
            baseSpeedPerMillisecond: baseSpeedPerMillisecond,
            deltaMilliseconds: deltaMilliseconds
        ).x
    }

    static func step(
        from startX: CGFloat,
        direction: CGFloat,
        baseSpeedPerMillisecond: CGFloat,
        deltaMilliseconds: CGFloat
    ) -> Step {
        guard direction != 0,
              baseSpeedPerMillisecond > 0,
              deltaMilliseconds > 0 else {
            return Step(x: startX, runAnimationDeltaMilliseconds: 0)
        }

        let startTravelCoordinate = travelCoordinate(forX: startX)
        let endTravelCoordinate = startTravelCoordinate
            + direction * baseSpeedPerMillisecond * deltaMilliseconds
        let endX = worldX(forTravelCoordinate: endTravelCoordinate)
        let baseDistancePerMillisecond = abs(direction) * baseSpeedPerMillisecond
        return Step(
            x: endX,
            runAnimationDeltaMilliseconds: abs(endX - startX) / baseDistancePerMillisecond
        )
    }

    static func animationDelta(
        for pose: ReceiverState.Pose,
        step: Step,
        deltaMilliseconds: CGFloat
    ) -> CGFloat {
        switch pose {
        case .run:
            return step.runAnimationDeltaMilliseconds
        case .catch, .celebrate:
            return max(0, deltaMilliseconds)
        }
    }

    /// Compresses each outside-sideline region by the configured multiplier.
    /// Advancing at the base speed in this coordinate integrates exactly to the
    /// sideline, then continues at the correct speed on the other side.
    private static func travelCoordinate(forX x: CGFloat) -> CGFloat {
        let sideline = GameplayConfig.receiverSidelineX
        let multiplier = GameplayConfig.receiverOutsideSidelineSpeedMultiplier
        if x < -sideline {
            return -sideline + (x + sideline) / multiplier
        }
        if x > sideline {
            return sideline + (x - sideline) / multiplier
        }
        return x
    }

    private static func worldX(forTravelCoordinate coordinate: CGFloat) -> CGFloat {
        let sideline = GameplayConfig.receiverSidelineX
        let multiplier = GameplayConfig.receiverOutsideSidelineSpeedMultiplier
        if coordinate < -sideline {
            return -sideline + (coordinate + sideline) * multiplier
        }
        if coordinate > sideline {
            return sideline + (coordinate - sideline) * multiplier
        }
        return coordinate
    }
}

enum ScoringConfig {
    static let meterMaximum = 100
    static let touchdownBonusPoints = 3_000
    static let interceptionPenaltyPoints = 250
    static let touchdownMultipliers: [CGFloat] = [1, 1.25, 1.5, 2, 2.5, 3]
}

struct XorShift32 {
    private(set) var state: UInt32

    init(seed: UInt32) {
        state = seed == 0 ? GameplayConfig.defaultSeed : seed
    }

    mutating func next() -> CGFloat {
        var next = state
        next ^= next << 13
        next ^= next >> 17
        next ^= next << 5
        let value = CGFloat(Double(next) / 4_294_967_296)
        state = next == 0 ? 0x6d2b79f5 : next
        return value
    }

    mutating func value(in range: ClosedRange<CGFloat>) -> CGFloat {
        range.lowerBound + (range.upperBound - range.lowerBound) * next()
    }

    mutating func direction() -> CGFloat {
        next() < 0.5 ? -1 : 1
    }
}

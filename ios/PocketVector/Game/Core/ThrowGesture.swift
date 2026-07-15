import CoreGraphics
import Foundation

struct TouchSample: Equatable {
    let point: CGPoint
    let timestampMilliseconds: CGFloat
}

struct ThrowGesture: Equatable {
    let start: TouchSample
    let release: TouchSample
    let samples: [TouchSample]
    let distancePixels: CGFloat
    let durationMilliseconds: CGFloat
    let averageSpeedPixelsPerMillisecond: CGFloat
    let releaseSpeedPixelsPerMillisecond: CGFloat
    let direction: CGVector

    var isValid: Bool {
        distancePixels >= GameplayConfig.Throw.minimumGestureDistancePixels && direction.dy > 0.08
    }
}

enum ThrowGestureCalculator {
    private static let releaseWindowMilliseconds: CGFloat = 90
    private static let minimumMeaningfulMovementPixels: CGFloat = 0.5
    private static let releaseFallbackSampleCount = 3

    static func calculate(samples: [TouchSample]) -> ThrowGesture? {
        guard let start = samples.first, let release = samples.last, samples.count >= 2 else {
            return nil
        }

        let duration = max(1, release.timestampMilliseconds - start.timestampMilliseconds)
        let pathDistance = sampledPathDistance(samples)
        let movementSamples = meaningfulMovementSamples(samples)
        let movementEnd = movementSamples.last ?? release
        let releaseWindowStart = movementEnd.timestampMilliseconds - releaseWindowMilliseconds
        var recentSamples = movementSamples.filter {
            $0.timestampMilliseconds >= releaseWindowStart
        }
        var releasePath = sampledPathDistance(recentSamples)
        if releasePath < minimumMeaningfulMovementPixels, movementSamples.count > 1 {
            recentSamples = Array(movementSamples.suffix(releaseFallbackSampleCount))
            releasePath = sampledPathDistance(recentSamples)
        }

        let releaseStart = recentSamples.first ?? start
        let stationaryDelay = max(
            0,
            min(
                releaseWindowMilliseconds,
                release.timestampMilliseconds - movementEnd.timestampMilliseconds
            )
        )
        let releaseDuration = max(
            1,
            movementEnd.timestampMilliseconds - releaseStart.timestampMilliseconds + stationaryDelay
        )
        let deltaX = release.point.x - start.point.x
        let deltaY = release.point.y - start.point.y
        let directDistance = hypot(deltaX, deltaY)
        let direction = directDistance == 0
            ? CGVector.zero
            : CGVector(dx: deltaX / directDistance, dy: deltaY / directDistance)

        return ThrowGesture(
            start: start,
            release: release,
            samples: samples,
            distancePixels: directDistance,
            durationMilliseconds: duration,
            averageSpeedPixelsPerMillisecond: pathDistance / duration,
            releaseSpeedPixelsPerMillisecond: recentSamples.count >= 2
                ? releasePath / releaseDuration
                : pathDistance / duration,
            direction: direction
        )
    }

    private static func meaningfulMovementSamples(_ samples: [TouchSample]) -> [TouchSample] {
        guard let first = samples.first else { return [] }
        return samples.dropFirst().reduce(into: [first]) { result, sample in
            guard let previous = result.last else { return }
            if distance(previous.point, sample.point) >= minimumMeaningfulMovementPixels {
                result.append(sample)
            }
        }
    }

    private static func sampledPathDistance(_ samples: [TouchSample]) -> CGFloat {
        zip(samples, samples.dropFirst()).reduce(0) { partial, pair in
            partial + distance(pair.0.point, pair.1.point)
        }
    }

    private static func distance(_ first: CGPoint, _ second: CGPoint) -> CGFloat {
        hypot(second.x - first.x, second.y - first.y)
    }
}

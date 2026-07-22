import CoreGraphics
import Foundation

struct GameSimulation {
    private(set) var state: GameState

    init(seed: UInt32 = GameplayConfig.defaultSeed) {
        state = Self.makeInitialState(seed: seed)
    }

    var canThrow: Bool {
        state.phase == .playing &&
            state.remainingMilliseconds > 0 &&
            state.ball == nil
    }

    mutating func startRun() {
        let seed = state.randomState == 0 ? GameplayConfig.defaultSeed : state.randomState
        state = Self.makeInitialState(seed: seed)
        state.phase = .countdown
    }

    @discardableResult
    mutating func pause() -> Bool {
        guard state.phase == .playing || state.phase == .resolvingFinalBall else {
            return false
        }

        state.phaseBeforePause = state.phase
        state.phase = .paused
        return true
    }

    @discardableResult
    mutating func resume() -> Bool {
        guard state.phase == .paused, let resumePhase = state.phaseBeforePause else {
            return false
        }

        guard resumePhase == .playing || resumePhase == .resolvingFinalBall else {
            return false
        }

        state.phase = resumePhase
        state.phaseBeforePause = nil
        return true
    }

    @discardableResult
    mutating func throwBall(
        target: WorldPoint,
        releaseSpeedPixelsPerMillisecond: CGFloat,
        aimMarker: CGPoint
    ) -> Bool {
        guard canThrow else { return false }
        state.ball = Trajectory.makeBall(
            id: state.nextEntityID,
            target: target,
            releaseSpeedPixelsPerMillisecond: releaseSpeedPixelsPerMillisecond,
            aimMarker: aimMarker
        )
        state.nextEntityID += 1
        return true
    }

    @discardableResult
    mutating func update(deltaMilliseconds: CGFloat) -> UpdateResult {
        var result = UpdateResult()
        guard deltaMilliseconds > 0 else { return result }

        switch state.phase {
        case .title:
            updateAttractMode(deltaMilliseconds: deltaMilliseconds)
            return result
        case .countdown:
            state.countdownRemainingMilliseconds = max(
                0,
                state.countdownRemainingMilliseconds - deltaMilliseconds
            )
            if state.countdownRemainingMilliseconds <= 0 {
                state.phase = .playing
            }
            return result
        case .paused, .results:
            return result
        case .playing, .resolvingFinalBall:
            break
        }

        if state.phase == .playing {
            updateTimer(deltaMilliseconds: deltaMilliseconds)
        }
        updateReceivers(deltaMilliseconds: deltaMilliseconds)
        updateDefenders(deltaMilliseconds: deltaMilliseconds)

        if var feedback = state.feedback {
            feedback.remainingMilliseconds -= deltaMilliseconds
            state.feedback = feedback.remainingMilliseconds > 0 ? feedback : nil
        }

        if var ball = state.ball {
            Trajectory.advance(ball: &ball, deltaMilliseconds: deltaMilliseconds)
            state.ball = ball

            if let collision = firstCollision(ball: ball) {
                let scoreBefore = state.score
                switch collision.kind {
                case let .receiver(index, laneID):
                    state.receivers[index].hasCaught = true
                    state.receivers[index].pose = laneID == .touchdown ? .celebrate : .catch
                    state.receivers[index].animationMilliseconds = 0
                    let outcome: PassOutcome = laneID == .touchdown ? .touchdown : .completion
                    resolvePass(outcome: outcome, laneID: laneID)
                    result.passResolved = outcome
                    result.laneID = laneID
                case let .defender(index):
                    state.defenders[index].pose = .intercept
                    state.defenders[index].animationMilliseconds = 0
                    resolvePass(outcome: .interception, laneID: nil)
                    result.passResolved = .interception
                }
                result.scoreChanged = state.score != scoreBefore
            } else if ball.elapsedMilliseconds >= ball.durationMilliseconds ||
                abs(ball.current.x) > 1.3 ||
                ball.current.depth > 1.06 {
                resolvePass(outcome: .incompletion, laneID: nil)
                result.passResolved = .incompletion
            }
        }

        if state.phase == .resolvingFinalBall {
            state.finalBallGraceRemainingMilliseconds = max(
                0,
                state.finalBallGraceRemainingMilliseconds - deltaMilliseconds
            )
            if state.ball == nil || state.finalBallGraceRemainingMilliseconds <= 0 {
                state.ball = nil
                state.phase = .results
                result.runFinished = true
            }
        }

        return result
    }

    static func makeInitialState(seed: UInt32 = GameplayConfig.defaultSeed) -> GameState {
        var nextID = 1
        let receivers = GameplayConfig.lanes.enumerated().map { index, lane in
            defer { nextID += 1 }
            let direction: CGFloat = index.isMultiple(of: 2) ? 1 : -1
            let offset = CGFloat(index) * 0.24
            let x = direction == 1
                ? -GameplayConfig.receiverOffscreenX + offset
                : GameplayConfig.receiverOffscreenX - offset
            return ReceiverState(
                id: nextID,
                laneID: lane.id,
                x: x,
                direction: direction,
                speedPerMillisecond: (2 * GameplayConfig.receiverOffscreenX) /
                    (lane.crossingSeconds * 1_000),
                animationMilliseconds: offset * 900
            )
        }
        let defenders = GameplayConfig.defenderDepths.enumerated().map { index, depth in
            defer { nextID += 1 }
            let direction: CGFloat = index.isMultiple(of: 2) ? 1 : -1
            let x = direction == 1
                ? -GameplayConfig.defenderPatrolHalfWidth + CGFloat(index) * 0.2
                : GameplayConfig.defenderPatrolHalfWidth - CGFloat(index) * 0.15
            return DefenderState(
                id: nextID,
                depth: depth,
                x: x,
                direction: direction,
                speedPerMillisecond: GameplayConfig.defenderSpeedPerMillisecond(index: index),
                animationMilliseconds: CGFloat(index) * 260
            )
        }

        var state = GameState()
        state.receivers = receivers
        state.defenders = defenders
        state.nextEntityID = nextID
        state.laneSpawnTimers = Dictionary(
            uniqueKeysWithValues: LaneID.allCases.map { ($0, 0) }
        )
        state.randomState = seed == 0 ? GameplayConfig.defaultSeed : seed
        return state
    }

    static func calculatePlayScore(
        score: Int,
        meter: Int,
        streak: Int,
        outcome: PassOutcome,
        laneID: LaneID?
    ) -> PlayScoreResult {
        let lane = laneID.map(GameplayConfig.lane)
        let bonusWasActive = meter >= ScoringConfig.meterMaximum
        let isSuccessful = outcome == .completion || outcome == .touchdown
        let isTouchdown = outcome == .touchdown
        let basePoints = isSuccessful ? lane?.completionPoints ?? 0 : 0
        let bonusPoints = isTouchdown && bonusWasActive
            ? ScoringConfig.touchdownBonusPoints
            : 0
        let multiplier = isTouchdown
            ? ScoringConfig.touchdownMultipliers[
                min(streak, ScoringConfig.touchdownMultipliers.count - 1)
            ]
            : 1
        let earnedPoints = Int((CGFloat(basePoints + bonusPoints) * multiplier).rounded())
        let penaltyPoints = outcome == .interception
            ? ScoringConfig.interceptionPenaltyPoints
            : 0
        let scoreDelta = earnedPoints - penaltyPoints
        let totalAfter = max(0, score + scoreDelta)
        let awardedPoints = totalAfter - score
        let meterAfter = isSuccessful
            ? min(ScoringConfig.meterMaximum, meter + (lane?.meterGain ?? 0))
            : 0
        let streakAfter: Int
        switch outcome {
        case .touchdown:
            streakAfter = streak + 1
        case .completion:
            streakAfter = streak
        case .incompletion, .interception:
            streakAfter = 0
        }

        return PlayScoreResult(
            outcome: outcome,
            laneID: laneID,
            basePoints: basePoints,
            bonusWasActive: bonusWasActive,
            bonusPoints: bonusPoints,
            touchdownMultiplier: multiplier,
            awardedPoints: awardedPoints,
            totalBefore: score,
            totalAfter: totalAfter,
            meterBefore: meter,
            meterAfter: meterAfter,
            streakBefore: streak,
            streakAfter: streakAfter
        )
    }

    private mutating func updateAttractMode(deltaMilliseconds: CGFloat) {
        for index in state.receivers.indices {
            advanceReceiver(at: index, deltaMilliseconds: deltaMilliseconds)
            if abs(state.receivers[index].x) > GameplayConfig.receiverDespawnX(
                for: state.receivers[index].laneID
            ) {
                let spawnX = GameplayConfig.receiverSpawnX(
                    for: state.receivers[index].laneID
                )
                state.receivers[index].x = state.receivers[index].direction == 1
                    ? -spawnX
                    : spawnX
            }
        }
        updateDefenders(deltaMilliseconds: deltaMilliseconds)
    }

    private mutating func updateTimer(deltaMilliseconds: CGFloat) {
        guard state.remainingMilliseconds > 0 else { return }
        let consumed = min(state.remainingMilliseconds, deltaMilliseconds)
        state.remainingMilliseconds = max(0, state.remainingMilliseconds - deltaMilliseconds)
        state.elapsedGameplayMilliseconds += consumed
        if state.remainingMilliseconds <= 0 {
            state.phase = .resolvingFinalBall
            state.finalBallGraceRemainingMilliseconds = GameplayConfig.finalBallGraceMilliseconds
        }
    }

    private mutating func updateReceivers(deltaMilliseconds: CGFloat) {
        for index in state.receivers.indices {
            advanceReceiver(at: index, deltaMilliseconds: deltaMilliseconds)
        }

        let departed = state.receivers.filter {
            abs($0.x) > GameplayConfig.receiverDespawnX(for: $0.laneID)
        }
        if !departed.isEmpty {
            let departedIDs = Set(departed.map(\.id))
            state.receivers.removeAll { departedIDs.contains($0.id) }
            for receiver in departed {
                scheduleSpawn(laneID: receiver.laneID)
            }
        }

        for laneID in LaneID.allCases {
            let remaining = state.laneSpawnTimers[laneID] ?? 0
            state.laneSpawnTimers[laneID] = max(0, remaining - deltaMilliseconds)
            let hasReceiver = state.receivers.contains { $0.laneID == laneID }
            if !hasReceiver, (state.laneSpawnTimers[laneID] ?? 0) <= 0 {
                let receiver = spawnReceiver(laneID: laneID)
                state.receivers.append(receiver)
                state.laneSpawnTimers[laneID] = .infinity
            }
        }
    }

    private mutating func advanceReceiver(at index: Int, deltaMilliseconds: CGFloat) {
        let motion = ReceiverMotion.step(
            from: state.receivers[index].x,
            direction: state.receivers[index].direction,
            baseSpeedPerMillisecond: state.receivers[index].speedPerMillisecond,
            deltaMilliseconds: deltaMilliseconds,
            hasCaught: state.receivers[index].hasCaught
        )
        state.receivers[index].x = motion.x
        state.receivers[index].animationMilliseconds += ReceiverMotion.animationDelta(
            for: state.receivers[index].pose,
            step: motion,
            deltaMilliseconds: deltaMilliseconds
        )
    }

    private mutating func updateDefenders(deltaMilliseconds: CGFloat) {
        for index in state.defenders.indices {
            let patrolLimit = GameplayConfig.defenderPatrolHalfWidth
            state.defenders[index].x = max(
                -patrolLimit,
                min(patrolLimit, state.defenders[index].x)
            )
            if state.defenders[index].x <= -patrolLimit,
               state.defenders[index].direction == -1 {
                state.defenders[index].direction = 1
            }
            if state.defenders[index].x >= patrolLimit,
               state.defenders[index].direction == 1 {
                state.defenders[index].direction = -1
            }

            var distanceRemaining = max(
                0,
                state.defenders[index].speedPerMillisecond * deltaMilliseconds
            )
            while distanceRemaining > 0 {
                let boundary = state.defenders[index].direction == 1
                    ? patrolLimit
                    : -patrolLimit
                let distanceToBoundary = abs(boundary - state.defenders[index].x)
                if distanceRemaining < distanceToBoundary {
                    state.defenders[index].x += state.defenders[index].direction * distanceRemaining
                    distanceRemaining = 0
                } else {
                    state.defenders[index].x = boundary
                    distanceRemaining -= distanceToBoundary
                    state.defenders[index].direction *= -1
                    state.defenders[index].pose = .run
                }
            }
            state.defenders[index].animationMilliseconds += deltaMilliseconds
        }
    }

    private mutating func scheduleSpawn(laneID: LaneID) {
        var random = XorShift32(seed: state.randomState)
        state.laneSpawnTimers[laneID] = random.value(in: GameplayConfig.receiverSpawnDelay)
        state.randomState = random.state
    }

    private mutating func spawnReceiver(laneID: LaneID) -> ReceiverState {
        let lane = GameplayConfig.lane(laneID)
        var random = XorShift32(seed: state.randomState)
        let direction = random.direction()
        let speedJitter = random.value(in: 0.9 ... 1.1)
        state.randomState = random.state
        defer { state.nextEntityID += 1 }
        let spawnX = GameplayConfig.receiverSpawnX(for: laneID)
        return ReceiverState(
            id: state.nextEntityID,
            laneID: laneID,
            x: direction == 1 ? -spawnX : spawnX,
            direction: direction,
            speedPerMillisecond: (
                (2 * GameplayConfig.receiverOffscreenX) / (lane.crossingSeconds * 1_000)
            ) * speedJitter,
            animationMilliseconds: 0
        )
    }

    private enum CollisionKind {
        case receiver(index: Int, laneID: LaneID)
        case defender(index: Int)
    }

    private struct CollisionCandidate {
        let kind: CollisionKind
        let progress: CGFloat
    }

    private func firstCollision(ball: BallState) -> CollisionCandidate? {
        var candidates: [CollisionCandidate] = []
        for index in state.receivers.indices where !state.receivers[index].hasCaught {
            let receiver = state.receivers[index]
            let lane = GameplayConfig.lane(receiver.laneID)
            if let progress = crossingProgress(
                previousDepth: ball.previous.depth,
                currentDepth: ball.current.depth,
                targetDepth: lane.depth
            ) {
                let point = interpolate(ball.previous, ball.current, progress: progress)
                if abs(point.x - receiver.x) <= lane.catchWidth,
                   (0.08 ... 0.92).contains(point.height) {
                    candidates.append(
                        CollisionCandidate(
                            kind: .receiver(index: index, laneID: receiver.laneID),
                            progress: progress
                        )
                    )
                }
            }

            let flightProgress = ball.durationMilliseconds > 0
                ? ball.elapsedMilliseconds / ball.durationMilliseconds
                : 1
            if flightProgress >= GameplayConfig.Throw.catchProgress {
                let ballScene = GameProjection.worldToScene(ball.current)
                let receiverTop = GameProjection.worldToScene(
                    WorldPoint(x: receiver.x, depth: lane.depth, height: 0.92)
                )
                let receiverBottom = GameProjection.worldToScene(
                    WorldPoint(x: receiver.x, depth: lane.depth, height: 0.08)
                )
                let halfCatchWidth = lane.catchWidth * GameProjection.halfFieldWidth(depth: lane.depth)
                let withinWidth = abs(ballScene.x - receiverBottom.x) <= halfCatchWidth
                let withinHeight = ballScene.y >= receiverBottom.y && ballScene.y <= receiverTop.y
                if withinWidth, withinHeight {
                    let catchCenterY = (receiverTop.y + receiverBottom.y) / 2
                    let horizontalDistance = abs(ballScene.x - receiverBottom.x) / halfCatchWidth
                    let verticalDistance = abs(ballScene.y - catchCenterY) /
                        max(1, (receiverTop.y - receiverBottom.y) / 2)
                    candidates.append(
                        CollisionCandidate(
                            kind: .receiver(index: index, laneID: receiver.laneID),
                            progress: 1 + horizontalDistance + verticalDistance
                        )
                    )
                }
            }
        }

        for index in state.defenders.indices {
            let defender = state.defenders[index]
            guard let progress = crossingProgress(
                previousDepth: ball.previous.depth,
                currentDepth: ball.current.depth,
                targetDepth: defender.depth
            ) else { continue }
            let point = interpolate(ball.previous, ball.current, progress: progress)
            let withinWidth = abs(point.x - defender.x) <= GameplayConfig.defenderWidthWorld * 0.55
            if withinWidth, (0.22 ... 0.92).contains(point.height) {
                candidates.append(
                    CollisionCandidate(kind: .defender(index: index), progress: progress)
                )
            }
        }
        return candidates.min { $0.progress < $1.progress }
    }

    private func crossingProgress(
        previousDepth: CGFloat,
        currentDepth: CGFloat,
        targetDepth: CGFloat
    ) -> CGFloat? {
        let delta = currentDepth - previousDepth
        if abs(delta) < 0.000_001 {
            return abs(currentDepth - targetDepth) <= 0.01 ? 1 : nil
        }
        let progress = (targetDepth - previousDepth) / delta
        return (0 ... 1).contains(progress) ? progress : nil
    }

    private func interpolate(
        _ previous: WorldPoint,
        _ current: WorldPoint,
        progress: CGFloat
    ) -> WorldPoint {
        WorldPoint(
            x: previous.x + (current.x - previous.x) * progress,
            depth: previous.depth + (current.depth - previous.depth) * progress,
            height: previous.height + (current.height - previous.height) * progress
        )
    }

    private mutating func resolvePass(outcome: PassOutcome, laneID: LaneID?) {
        let scoreResult = Self.calculatePlayScore(
            score: state.score,
            meter: state.touchdownMeter,
            streak: state.touchdownStreak,
            outcome: outcome,
            laneID: laneID
        )
        state.score = scoreResult.totalAfter
        state.touchdownMeter = scoreResult.meterAfter
        state.touchdownStreak = scoreResult.streakAfter
        state.lastPlayScore = scoreResult
        state.statistics.record(outcome: outcome)
        state.feedback = Self.makeFeedback(result: scoreResult)
        state.ball = nil
    }

    static func makeFeedback(result: PlayScoreResult) -> FeedbackState {
        switch result.outcome {
        case .interception:
            let deductedPoints = max(0, -result.awardedPoints)
            let deductionText = deductedPoints > 0
                ? "−\(Self.formattedPoints(deductedPoints))"
                : "0"
            return FeedbackState(
                headline: "INTERCEPTED \(deductionText)",
                detail: "BONUS LOST",
                tone: .negative,
                remainingMilliseconds: 920
            )
        case .incompletion:
            return FeedbackState(
                headline: "INCOMPLETE",
                detail: "BONUS LOST",
                tone: .negative,
                remainingMilliseconds: 920
            )
        case .touchdown:
            var details: [String] = []
            if result.bonusWasActive { details.append("TD BONUS") }
            if result.touchdownMultiplier > 1 {
                details.append("CHAIN x\(Self.formattedMultiplier(result.touchdownMultiplier))")
            }
            return FeedbackState(
                headline: "TOUCHDOWN +\(Self.formattedPoints(result.awardedPoints))",
                detail: details.joined(separator: "  •  "),
                tone: .touchdown,
                remainingMilliseconds: 1_050
            )
        case .completion:
            let lane = result.laneID?.rawValue.uppercased() ?? "COMPLETE"
            return FeedbackState(
                headline: "\(lane) COMPLETE +\(Self.formattedPoints(result.awardedPoints))",
                detail: "",
                tone: .positive,
                remainingMilliseconds: 760
            )
        }
    }

    private static func formattedPoints(_ points: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: points)) ?? String(points)
    }

    private static func formattedMultiplier(_ multiplier: CGFloat) -> String {
        if multiplier.rounded() == multiplier {
            return String(Int(multiplier))
        }
        if (multiplier * 10).rounded() == multiplier * 10 {
            return String(format: "%.1f", Double(multiplier))
        }
        return String(format: "%.2f", Double(multiplier))
    }
}

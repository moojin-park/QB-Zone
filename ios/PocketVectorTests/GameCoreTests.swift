import AVFAudio
import CoreGraphics
import UIKit
import XCTest

@testable import PocketVector

final class GameCoreTests: XCTestCase {
  func testXorShift32ProducesKnownSequence() {
    var random = XorShift32(seed: 0x1234_5678)
    let expectedStates: [UInt32] = [
      0x8798_5aa5,
      0x155b_24a3,
      0x4820_f4c4,
      0x81b3_ac98,
      0x703a_0788,
    ]

    for expectedState in expectedStates {
      let value = random.next()

      XCTAssertEqual(random.state, expectedState)
      XCTAssertEqual(
        value,
        CGFloat(Double(expectedState) / 4_294_967_296),
        accuracy: 0.000_000_001
      )
    }
  }

  func testLaneConfigurationAndInitialReceiversCoverEveryLane() {
    XCTAssertEqual(GameplayConfig.lanes.map(\.id), LaneID.allCases)
    XCTAssertEqual(GameplayConfig.lanes.map(\.label), ["15", "30", "45", "END ZONE"])
    XCTAssertEqual(GameplayConfig.lanes.map(\.completionPoints), [500, 1_000, 1_500, 2_500])
    XCTAssertEqual(GameplayConfig.lanes.map(\.meterGain), [15, 35, 50, 0])

    let initialState = GameSimulation.makeInitialState(seed: 1)

    XCTAssertEqual(initialState.receivers.map(\.laneID), LaneID.allCases)
    XCTAssertEqual(initialState.receivers.map(\.id), [1, 2, 3, 4])
    XCTAssertEqual(initialState.defenders.map(\.id), [5, 6, 7])
    XCTAssertEqual(initialState.nextEntityID, 8)
    XCTAssertEqual(initialState.laneSpawnTimers.count, LaneID.allCases.count)
    XCTAssertTrue(initialState.laneSpawnTimers.values.allSatisfy { $0 == 0 })
  }

  func testReceiverMotionUsesBaseSpeedOnFieldAndDoubleSpeedOutsideSidelines() {
    XCTAssertEqual(ReceiverMotion.speedMultiplier(atX: 0), 1)
    XCTAssertEqual(ReceiverMotion.speedMultiplier(atX: -GameplayConfig.receiverSidelineX), 1)
    XCTAssertEqual(ReceiverMotion.speedMultiplier(atX: GameplayConfig.receiverSidelineX), 1)
    XCTAssertEqual(ReceiverMotion.speedMultiplier(atX: -1.01), 2)
    XCTAssertEqual(ReceiverMotion.speedMultiplier(atX: 1.01), 2)

    let baseSpeed: CGFloat = 0.001
    XCTAssertEqual(
      ReceiverMotion.position(
        from: 0.25,
        direction: 1,
        baseSpeedPerMillisecond: baseSpeed,
        deltaMilliseconds: 100
      ),
      0.35,
      accuracy: 0.000_001
    )
    XCTAssertEqual(
      ReceiverMotion.position(
        from: 1.1,
        direction: 1,
        baseSpeedPerMillisecond: baseSpeed,
        deltaMilliseconds: 100
      ),
      1.3,
      accuracy: 0.000_001
    )
  }

  func testReceiverMotionIntegratesExactlyToSidelineBeforeRestoringBaseSpeed() {
    let baseSpeed: CGFloat = 0.001
    let singleStep = ReceiverMotion.step(
      from: -1.1,
      direction: 1,
      baseSpeedPerMillisecond: baseSpeed,
      deltaMilliseconds: 200
    )

    var partitioned = CGFloat(-1.1)
    for _ in 0 ..< 4 {
      partitioned = ReceiverMotion.position(
        from: partitioned,
        direction: 1,
        baseSpeedPerMillisecond: baseSpeed,
        deltaMilliseconds: 50
      )
    }

    XCTAssertEqual(singleStep.x, -0.85, accuracy: 0.000_001)
    XCTAssertEqual(singleStep.runAnimationDeltaMilliseconds, 250, accuracy: 0.000_001)
    XCTAssertEqual(partitioned, singleStep.x, accuracy: 0.000_001)
    XCTAssertEqual(
      ReceiverMotion.animationDelta(
        for: .catch,
        step: singleStep,
        deltaMilliseconds: 200
      ),
      200,
      accuracy: 0.000_001
    )
    XCTAssertEqual(
      ReceiverMotion.animationDelta(
        for: .celebrate,
        step: singleStep,
        deltaMilliseconds: 200
      ),
      200,
      accuracy: 0.000_001
    )
  }

  func testReceiverMotionCrossesRightSidelineSymmetrically() {
    let baseSpeed: CGFloat = 0.001
    let singleStep = ReceiverMotion.step(
      from: 1.1,
      direction: -1,
      baseSpeedPerMillisecond: baseSpeed,
      deltaMilliseconds: 200
    )

    var partitioned = CGFloat(1.1)
    for _ in 0 ..< 4 {
      partitioned = ReceiverMotion.position(
        from: partitioned,
        direction: -1,
        baseSpeedPerMillisecond: baseSpeed,
        deltaMilliseconds: 50
      )
    }

    XCTAssertEqual(singleStep.x, 0.85, accuracy: 0.000_001)
    XCTAssertEqual(singleStep.runAnimationDeltaMilliseconds, 250, accuracy: 0.000_001)
    XCTAssertEqual(partitioned, singleStep.x, accuracy: 0.000_001)
  }

  func testSimulationAcceleratesOnlyReceiversCurrentlyOutsideTheSideline() throws {
    var simulation = GameSimulation(seed: 1)
    simulation.startRun()
    simulation.update(deltaMilliseconds: 3_000)

    let outsideBefore = try XCTUnwrap(
      simulation.state.receivers.first(where: { abs($0.x) > GameplayConfig.receiverSidelineX })
    )
    let insideBefore = try XCTUnwrap(
      simulation.state.receivers.first(where: { abs($0.x) < GameplayConfig.receiverSidelineX })
    )

    simulation.update(deltaMilliseconds: 100)

    let outsideAfter = try XCTUnwrap(
      simulation.state.receivers.first(where: { $0.id == outsideBefore.id })
    )
    let insideAfter = try XCTUnwrap(
      simulation.state.receivers.first(where: { $0.id == insideBefore.id })
    )
    XCTAssertEqual(
      outsideAfter.x - outsideBefore.x,
      outsideBefore.direction * outsideBefore.speedPerMillisecond * 100
        * GameplayConfig.receiverOutsideSidelineSpeedMultiplier,
      accuracy: 0.000_001
    )
    XCTAssertEqual(
      outsideAfter.animationMilliseconds - outsideBefore.animationMilliseconds,
      200,
      accuracy: 0.000_001
    )
    XCTAssertEqual(
      insideAfter.x - insideBefore.x,
      insideBefore.direction * insideBefore.speedPerMillisecond * 100,
      accuracy: 0.000_001
    )
    XCTAssertEqual(
      insideAfter.animationMilliseconds - insideBefore.animationMilliseconds,
      100,
      accuracy: 0.000_001
    )
  }

  func testSimulationKeepsFarReceiverUntilItsSpriteClearsTheViewport() throws {
    var simulation = GameSimulation(seed: 1)
    simulation.startRun()
    simulation.update(deltaMilliseconds: 3_000)

    let receiverID = try XCTUnwrap(
      simulation.state.receivers.first(where: { $0.laneID == .touchdown })
    ).id
    simulation.update(deltaMilliseconds: 4_500)

    let stillVisible = try XCTUnwrap(
      simulation.state.receivers.first(where: { $0.id == receiverID })
    )
    XCTAssertGreaterThan(abs(stillVisible.x), GameplayConfig.receiverMinimumDespawnX)
    XCTAssertLessThan(
      abs(stillVisible.x),
      GameplayConfig.receiverDespawnX(for: .touchdown)
    )

    simulation.update(deltaMilliseconds: 1_000)
    XCTAssertFalse(simulation.state.receivers.contains(where: { $0.id == receiverID }))
  }

  func testRespawnedReceiversStartPastTheWidestViewportEdge() {
    var simulation = GameSimulation(seed: 1)
    simulation.startRun()
    simulation.update(deltaMilliseconds: 3_000)
    let originalIDs = Set(simulation.state.receivers.map(\.id))

    simulation.update(deltaMilliseconds: 8_000)

    XCTAssertEqual(simulation.state.receivers.count, LaneID.allCases.count)
    for receiver in simulation.state.receivers {
      XCTAssertFalse(originalIDs.contains(receiver.id))
      XCTAssertEqual(
        abs(receiver.x),
        GameplayConfig.receiverSpawnX(for: receiver.laneID),
        accuracy: 0.000_001
      )
    }
  }

  func testAttractModeRecyclesReceiversPastTheWidestViewportEdge() {
    var simulation = GameSimulation(seed: 1)

    simulation.update(deltaMilliseconds: 8_000)

    for receiver in simulation.state.receivers {
      XCTAssertEqual(
        abs(receiver.x),
        GameplayConfig.receiverSpawnX(for: receiver.laneID),
        accuracy: 0.000_001
      )
    }
  }

  func testSlowThrowIsLongerAndHigherThanFastThrow() {
    let target = WorldPoint(x: 0.42, depth: 0.78, height: 0.5)
    let slow = Trajectory.parameters(
      start: GameplayConfig.quarterbackStart,
      target: target,
      releaseSpeedPixelsPerMillisecond: GameplayConfig.Throw.slowSpeedPixelsPerMillisecond
    )
    let fast = Trajectory.parameters(
      start: GameplayConfig.quarterbackStart,
      target: target,
      releaseSpeedPixelsPerMillisecond: GameplayConfig.Throw.fastSpeedPixelsPerMillisecond
    )

    XCTAssertEqual(slow.normalizedSpeed, 0, accuracy: 0.000_001)
    XCTAssertEqual(fast.normalizedSpeed, 1, accuracy: 0.000_001)
    XCTAssertGreaterThan(slow.durationMilliseconds, fast.durationMilliseconds)
    XCTAssertGreaterThan(slow.arcHeight, fast.arcHeight)
    XCTAssertEqual(slow.end, fast.end)
  }

  func testTrajectoryReachesHorizontalEndpointAtCatchProgress() {
    let start = WorldPoint(x: -0.2, depth: 0.05, height: 0.56)
    let end = WorldPoint(x: 0.65, depth: 0.87, height: 0.45)
    let catchPoint = Trajectory.position(
      start: start,
      end: end,
      arcHeight: 0.7,
      progress: GameplayConfig.Throw.catchProgress
    )
    let landingPoint = Trajectory.position(
      start: start,
      end: end,
      arcHeight: 0.7,
      progress: 1
    )

    XCTAssertEqual(catchPoint.x, end.x, accuracy: 0.000_001)
    XCTAssertEqual(catchPoint.depth, end.depth, accuracy: 0.000_001)
    XCTAssertGreaterThan(catchPoint.height, end.height)
    XCTAssertEqual(landingPoint.x, end.x, accuracy: 0.000_001)
    XCTAssertEqual(landingPoint.depth, end.depth, accuracy: 0.000_001)
    XCTAssertEqual(landingPoint.height, end.height, accuracy: 0.000_001)
  }

  func testCanonicalViewportPreservesTheOriginalLogicalCanvas() {
    let viewport = GameViewport(
      viewSize: CGSize(width: 1_024, height: 768),
      safeAreaInsets: .zero
    )

    XCTAssertEqual(viewport.projection.viewportWidth, 1_024, accuracy: 0.000_001)
    XCTAssertEqual(viewport.projection.sceneSize, CGSize(width: 1_024, height: 768))
    XCTAssertEqual(viewport.pointsPerSceneUnit, 1, accuracy: 0.000_001)
    XCTAssertEqual(viewport.safeSceneFrame, CGRect(x: 0, y: 0, width: 1_024, height: 768))
  }

  func testPhoneViewportExpandsWidthAndConvertsSafeAreaInsets() {
    let viewport = GameViewport(
      viewSize: CGSize(width: 832, height: 384),
      safeAreaInsets: GameSafeAreaInsets(top: 0, left: 59, bottom: 21, right: 59)
    )

    XCTAssertEqual(viewport.projection.viewportWidth, 1_664, accuracy: 0.000_001)
    XCTAssertEqual(viewport.pointsPerSceneUnit, 0.5, accuracy: 0.000_001)
    XCTAssertEqual(
      viewport.safeSceneFrame,
      CGRect(x: 118, y: 42, width: 1_428, height: 726)
    )
  }

  func testViewportCapsAtTheWidestFieldPlate() {
    let viewport = GameViewport(
      viewSize: CGSize(width: 2_000, height: 768),
      safeAreaInsets: .zero
    )

    XCTAssertEqual(
      viewport.projection.viewportWidth,
      GameProjection.maximumFieldArtWidth,
      accuracy: 0.000_001
    )
  }

  func testWideProjectionChangesOnlyTheHorizontalCenter() {
    let world = WorldPoint(x: 0.42, depth: 0.68, height: 0)
    let canonicalPoint = GameProjection.classic.worldToScene(world)

    for width: CGFloat in [1_024, 1_366, 1_664] {
      let projection = GameProjection(viewportWidth: width)
      let scenePoint = projection.worldToScene(world)
      let roundTrip = projection.sceneToWorld(scenePoint)

      XCTAssertEqual(
        scenePoint.x - projection.centerX,
        canonicalPoint.x - GameProjection.classic.centerX,
        accuracy: 0.000_001
      )
      XCTAssertEqual(scenePoint.y, canonicalPoint.y, accuracy: 0.000_001)
      XCTAssertEqual(roundTrip.x, world.x, accuracy: 0.000_001)
      XCTAssertEqual(roundTrip.depth, world.depth, accuracy: 0.000_001)
    }
  }

  func testReceiverDespawnBoundsClearEveryLaneAtWidestViewport() {
    let projection = GameProjection(viewportWidth: GameProjection.maximumFieldArtWidth)

    for lane in GameplayConfig.lanes {
      let despawnX = GameplayConfig.receiverDespawnX(for: lane.id)
      let scale = GameProjection.actorScale(depth: lane.depth)
      let halfSpriteWidth = GameProjection.actorSpriteSize.width * scale / 2
      let rightCenter = projection.worldToScene(
        WorldPoint(x: despawnX, depth: lane.depth, height: 0)
      ).x
      let leftCenter = projection.worldToScene(
        WorldPoint(x: -despawnX, depth: lane.depth, height: 0)
      ).x

      XCTAssertGreaterThan(rightCenter - halfSpriteWidth, projection.viewportWidth)
      XCTAssertLessThan(leftCenter + halfSpriteWidth, 0)
    }

    XCTAssertEqual(
      GameplayConfig.receiverDespawnX(for: .short),
      GameplayConfig.receiverMinimumDespawnX,
      accuracy: 0.000_001
    )
    XCTAssertGreaterThan(
      GameplayConfig.receiverDespawnX(for: .touchdown),
      GameplayConfig.receiverMinimumDespawnX
    )
  }

  func testWidenedSidelineTracksTheOriginalOutsideHashPerspective() {
    let projection = GameProjection(viewportWidth: 1_728)
    let samples: [CGFloat] = [284, 308, 415, 505, 557]

    for browserY in samples {
      let left = FieldBoundaryLayout.boundaryPoint(
        side: .left,
        browserY: browserY,
        projection: projection
      )
      let right = FieldBoundaryLayout.boundaryPoint(
        side: .right,
        browserY: browserY,
        projection: projection
      )
      let expectedLeftX = 672.9 - 1.1562 * browserY

      XCTAssertEqual(left.x, expectedLeftX, accuracy: 1)
      XCTAssertEqual(right.x, 1_728 - left.x, accuracy: 0.000_001)
    }
  }

  func testGameplaySidelineAndPaintedBoundaryShareOneProjection() {
    let projection = GameProjection(viewportWidth: 1_664)

    for lane in GameplayConfig.lanes {
      let browserY = GameProjection.groundScreenY(depth: lane.depth)
      let paintedLeft = FieldBoundaryLayout.boundaryPoint(
        side: .left,
        browserY: browserY,
        projection: projection
      )
      let gameplayLeft = projection.worldToScene(
        WorldPoint(x: -GameplayConfig.receiverSidelineX, depth: lane.depth, height: 0)
      )
      let paintedRight = FieldBoundaryLayout.boundaryPoint(
        side: .right,
        browserY: browserY,
        projection: projection
      )
      let gameplayRight = projection.worldToScene(
        WorldPoint(x: GameplayConfig.receiverSidelineX, depth: lane.depth, height: 0)
      )

      XCTAssertEqual(paintedLeft.x, gameplayLeft.x, accuracy: 0.000_001)
      XCTAssertEqual(paintedLeft.y, gameplayLeft.y, accuracy: 0.000_001)
      XCTAssertEqual(paintedRight.x, gameplayRight.x, accuracy: 0.000_001)
      XCTAssertEqual(paintedRight.y, gameplayRight.y, accuracy: 0.000_001)
    }
  }

  func testSidelineOfficialsStayOutsideThePlayableField() throws {
    let projection = GameProjection(viewportWidth: 1_664)
    let browserY: CGFloat = 355
    let perspective = (browserY - GameProjection.horizonY)
      / (GameProjection.nearGroundY - GameProjection.horizonY)
    let actorScale = GameProjection.farActorScale
      + (GameProjection.nearActorScale - GameProjection.farActorScale) * perspective
    let officialHalfWidth = GameProjection.actorSpriteSize.width * actorScale / 2

    for side in FieldBoundarySide.allCases {
      let boundary = FieldBoundaryLayout.boundaryPoint(
        side: side,
        browserY: browserY,
        projection: projection
      )
      let official = try XCTUnwrap(
        FieldBoundaryLayout.staffPosition(
          side: side,
          browserY: browserY,
          preferredInset: 82,
          projection: projection,
          footprintHalfWidth: officialHalfWidth
        )
      )

      if side == .left {
        XCTAssertLessThanOrEqual(official.x + officialHalfWidth, boundary.x)
        XCTAssertGreaterThanOrEqual(official.x - officialHalfWidth, 18)
      } else {
        XCTAssertGreaterThanOrEqual(official.x - officialHalfWidth, boundary.x)
        XCTAssertLessThanOrEqual(
          official.x + officialHalfWidth,
          projection.viewportWidth - 18
        )
      }
      XCTAssertEqual(official.y, boundary.y, accuracy: 0.000_001)
    }

    let intermediateProjection = GameProjection(viewportWidth: 1_366)
    for side in FieldBoundarySide.allCases {
      XCTAssertNil(
        FieldBoundaryLayout.staffPosition(
          side: side,
          browserY: browserY,
          preferredInset: 82,
          projection: intermediateProjection,
          footprintHalfWidth: officialHalfWidth
        )
      )
    }
  }

  func testQuarterbackHitTargetFollowsTheViewportCenter() {
    let projection = GameProjection(viewportWidth: 1_664)

    XCTAssertEqual(projection.quarterbackHitFrame.midX, projection.centerX, accuracy: 0.000_001)
    XCTAssertTrue(projection.isPointOnQuarterback(CGPoint(x: projection.centerX, y: 100)))
    XCTAssertFalse(projection.isPointOnQuarterback(CGPoint(x: projection.centerX + 141, y: 100)))
  }

  func testCompactHUDStaysInsideTheSafeSceneFrame() {
    let viewport = GameViewport(
      viewSize: CGSize(width: 832, height: 384),
      safeAreaInsets: GameSafeAreaInsets(top: 0, left: 59, bottom: 21, right: 59)
    )
    let layout = HUDLayout(
      sceneSize: viewport.projection.sceneSize,
      contentRect: viewport.safeSceneFrame,
      metrics: .compact,
      displayScale: viewport.pointsPerSceneUnit
    )

    XCTAssertTrue(viewport.safeSceneFrame.contains(layout.adrenalineFrame))
    XCTAssertTrue(viewport.safeSceneFrame.contains(layout.controlsFrame))
    XCTAssertTrue(viewport.safeSceneFrame.contains(layout.scorePlateFrame))
    XCTAssertTrue(viewport.safeSceneFrame.contains(layout.clockTopAnchor))
    XCTAssertEqual(layout.clockTopAnchor.x, viewport.safeSceneFrame.midX, accuracy: 0.000_001)
  }

  func testCompletionAddsPointsFillsMeterAndResetsTouchdownStreak() {
    let result = GameSimulation.calculatePlayScore(
      score: 2_000,
      meter: 80,
      streak: 2,
      outcome: .completion,
      laneID: .deep
    )

    XCTAssertEqual(result.basePoints, 1_500)
    XCTAssertEqual(result.awardedPoints, 1_500)
    XCTAssertEqual(result.totalAfter, 3_500)
    XCTAssertEqual(result.meterAfter, ScoringConfig.meterMaximum)
    XCTAssertEqual(result.streakAfter, 0)
    XCTAssertFalse(result.bonusWasActive)
  }

  func testTouchdownUsesActiveMeterBonusAndCurrentStreakMultiplier() {
    let result = GameSimulation.calculatePlayScore(
      score: 1_000,
      meter: ScoringConfig.meterMaximum,
      streak: 3,
      outcome: .touchdown,
      laneID: .touchdown
    )

    XCTAssertTrue(result.bonusWasActive)
    XCTAssertEqual(result.basePoints, 2_500)
    XCTAssertEqual(result.bonusPoints, 3_000)
    XCTAssertEqual(result.touchdownMultiplier, 2)
    XCTAssertEqual(result.awardedPoints, 11_000)
    XCTAssertEqual(result.totalAfter, 12_000)
    XCTAssertEqual(result.meterAfter, ScoringConfig.meterMaximum)
    XCTAssertEqual(result.streakAfter, 4)
  }

  func testFailedPassResetsMeterAndStreakWithoutChangingScore() {
    let result = GameSimulation.calculatePlayScore(
      score: 4_500,
      meter: 90,
      streak: 4,
      outcome: .interception,
      laneID: nil
    )

    XCTAssertEqual(result.awardedPoints, 0)
    XCTAssertEqual(result.totalAfter, 4_500)
    XCTAssertEqual(result.meterAfter, 0)
    XCTAssertEqual(result.streakAfter, 0)
  }

  func testCountdownStartsGameplayAndExpiredTimerFinishesRun() {
    var simulation = GameSimulation(seed: 7)
    simulation.startRun()

    XCTAssertEqual(simulation.state.phase, .countdown)
    XCTAssertFalse(simulation.canThrow)

    simulation.update(deltaMilliseconds: 2_999)
    XCTAssertEqual(simulation.state.phase, .countdown)
    XCTAssertEqual(simulation.state.countdownRemainingMilliseconds, 1)

    simulation.update(deltaMilliseconds: 1)
    XCTAssertEqual(simulation.state.phase, .playing)
    XCTAssertTrue(simulation.canThrow)

    simulation.update(
      deltaMilliseconds: GameplayConfig.sessionDurationMilliseconds - 1
    )
    XCTAssertEqual(simulation.state.phase, .playing)
    XCTAssertEqual(simulation.state.remainingMilliseconds, 1)

    let result = simulation.update(deltaMilliseconds: 1)

    XCTAssertEqual(simulation.state.remainingMilliseconds, 0)
    XCTAssertEqual(
      simulation.state.elapsedGameplayMilliseconds, GameplayConfig.sessionDurationMilliseconds)
    XCTAssertEqual(simulation.state.phase, .results)
    XCTAssertTrue(result.runFinished)
  }

  func testThrowCreatesBallAndBlocksAnotherThrowUntilResolution() throws {
    var simulation = GameSimulation(seed: 11)
    simulation.startRun()
    simulation.update(deltaMilliseconds: 3_000)

    let target = WorldPoint(x: 0.35, depth: 0.68, height: 0.5)
    let aimMarker = CGPoint(x: 240, y: 180)
    let releaseSpeed: CGFloat = 1.25
    let expectedBallID = simulation.state.nextEntityID

    XCTAssertTrue(
      simulation.throwBall(
        target: target,
        releaseSpeedPixelsPerMillisecond: releaseSpeed,
        aimMarker: aimMarker
      )
    )

    let ball = try XCTUnwrap(simulation.state.ball)
    XCTAssertEqual(ball.id, expectedBallID)
    XCTAssertEqual(ball.start, GameplayConfig.quarterbackStart)
    XCTAssertEqual(ball.target, target)
    XCTAssertEqual(ball.current, GameplayConfig.quarterbackStart)
    XCTAssertEqual(ball.previous, GameplayConfig.quarterbackStart)
    XCTAssertEqual(ball.releaseSpeedPixelsPerMillisecond, releaseSpeed)
    XCTAssertEqual(ball.aimMarker, aimMarker)
    XCTAssertEqual(simulation.state.nextEntityID, expectedBallID + 1)
    XCTAssertFalse(simulation.canThrow)
    XCTAssertFalse(
      simulation.throwBall(
        target: target,
        releaseSpeedPixelsPerMillisecond: releaseSpeed,
        aimMarker: aimMarker
      )
    )
    XCTAssertEqual(simulation.state.nextEntityID, expectedBallID + 1)
  }

  func testBallHeadingFollowsProjectedTravelDirection() {
    XCTAssertEqual(
      BallVisualProjection.headingRadians(
        previous: CGPoint(x: 0, y: 0),
        current: CGPoint(x: 10, y: 0),
        fallback: CGPoint(x: 20, y: 0)
      ),
      0,
      accuracy: 0.000_001
    )
    XCTAssertEqual(
      BallVisualProjection.headingRadians(
        previous: CGPoint(x: 4, y: 4),
        current: CGPoint(x: 4, y: 14),
        fallback: CGPoint(x: 4, y: 24)
      ),
      .pi / 2,
      accuracy: 0.000_001
    )
    XCTAssertEqual(
      BallVisualProjection.headingRadians(
        previous: CGPoint(x: 5, y: 5),
        current: CGPoint(x: 5, y: 5),
        fallback: CGPoint(x: -5, y: 5)
      ),
      .pi,
      accuracy: 0.000_001
    )
  }

  func testAxialRollChangesLacesWithoutChangingFlightHeading() {
    var ball = Trajectory.makeBall(
      id: 1,
      target: WorldPoint(x: 0.45, depth: 0.72, height: 0),
      releaseSpeedPixelsPerMillisecond: 1.2,
      aimMarker: .zero
    )
    Trajectory.advance(ball: &ball, deltaMilliseconds: 120)
    ball.rollRadians = 0
    let lacesFacingCamera = BallVisualProjection.visualState(for: ball)
    ball.rollRadians = .pi
    let lacesBehindBall = BallVisualProjection.visualState(for: ball)

    XCTAssertEqual(
      lacesFacingCamera.headingRadians,
      lacesBehindBall.headingRadians,
      accuracy: 0.000_001
    )
    XCTAssertEqual(lacesFacingCamera.laceOpacity, 1, accuracy: 0.000_001)
    XCTAssertEqual(lacesBehindBall.laceOpacity, 0, accuracy: 0.000_001)
    XCTAssertEqual(
      BallVisualProjection.normalizedRoll(BallVisualProjection.fullRoll + 0.25),
      0.25,
      accuracy: 0.000_001
    )
  }

  func testAudioResourcesAreBundledAndDecodable() throws {
    let musicURL = try XCTUnwrap(GameAudioResources.musicURL())
    let music = try AVAudioPlayer(contentsOf: musicURL)
    XCTAssertTrue(music.prepareToPlay())
    XCTAssertGreaterThan(music.duration, 1)

    for cue in GameAudioCue.allCases {
      let url = try XCTUnwrap(GameAudioResources.url(for: cue), "Missing \(cue.rawValue)")
      let player = try AVAudioPlayer(contentsOf: url)
      XCTAssertTrue(player.prepareToPlay(), "Could not prepare \(cue.rawValue)")
      XCTAssertGreaterThan(player.duration, 0, "Empty sound: \(cue.rawValue)")
    }
  }

  func testNativeAssetManifestMatchesBundledResources() throws {
    let manifestURL = try XCTUnwrap(
      GameAssetResources.url(for: GameAssetResources.manifestRelativePath)
    )
    let manifest = try JSONDecoder().decode(
      NativeAssetManifest.self,
      from: Data(contentsOf: manifestURL)
    )
    let paths = manifest.assets.map(\.path)
    let assetRootURL = manifestURL.deletingLastPathComponent()
    let physicalPaths = try bundledAssetPaths(
      under: assetRootURL,
      excluding: GameAssetResources.manifestRelativePath
    )

    XCTAssertEqual(manifest.schemaVersion, 1)
    XCTAssertEqual(paths.count, 58)
    XCTAssertEqual(Set(paths).count, paths.count, "Manifest contains duplicate paths")
    XCTAssertEqual(
      Set(paths),
      physicalPaths,
      "Manifest paths must exactly match the physical bundled asset files"
    )

    for asset in manifest.assets {
      let url = try XCTUnwrap(
        GameAssetResources.url(for: asset.path),
        "Missing native resource: \(asset.path)"
      )
      switch asset.kind {
      case "image":
        XCTAssertNotNil(
          UIImage(contentsOfFile: url.path),
          "Could not decode native image: \(asset.path)"
        )
      case "audio":
        let player = try AVAudioPlayer(contentsOf: url)
        XCTAssertTrue(player.prepareToPlay(), "Could not decode native audio: \(asset.path)")
        XCTAssertGreaterThan(player.duration, 0, "Empty native audio: \(asset.path)")
      default:
        XCTFail("Unknown native asset kind '\(asset.kind)' for \(asset.path)")
      }
    }
  }

  private func bundledAssetPaths(
    under rootURL: URL,
    excluding excludedRelativePath: String
  ) throws -> Set<String> {
    let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey]
    let enumerator = try XCTUnwrap(
      FileManager.default.enumerator(
        at: rootURL,
        includingPropertiesForKeys: Array(resourceKeys),
        options: [.skipsHiddenFiles]
      )
    )
    var paths = Set<String>()

    for case let fileURL as URL in enumerator {
      let values = try fileURL.resourceValues(forKeys: resourceKeys)
      guard values.isRegularFile == true else { continue }
      let relativePath = String(fileURL.path.dropFirst(rootURL.path.count + 1))
      guard relativePath != excludedRelativePath else { continue }
      paths.insert(relativePath)
    }

    return paths
  }

  @MainActor
  func testAudioControllerStartsMusicAndOverlappingEffects() {
    let audio = GameAudioController()

    XCTAssertFalse(audio.isMuted)
    XCTAssertTrue(audio.play(.throwRelease))
    XCTAssertTrue(audio.play(.throwRelease))
    XCTAssertTrue(audio.play(.ballFlight))
    audio.startMusic()

    XCTAssertTrue(audio.isPlaying(.throwRelease))
    XCTAssertTrue(audio.isPlaying(.ballFlight))
    XCTAssertTrue(audio.isMusicPlaying)
    XCTAssertTrue(audio.toggleMuted())
    XCTAssertTrue(audio.isMuted)
    XCTAssertFalse(audio.toggleMuted())
    XCTAssertFalse(audio.isMuted)
    audio.suspend()
  }

  func testCanonicalHUDLayoutMatchesOriginalBroadcastAnchors() {
    let layout = HUDLayout()

    XCTAssertEqual(layout.adrenalineFrame.minX, 16.384, accuracy: 0.000_001)
    XCTAssertEqual(layout.adrenalineFrame.minY, 648.336, accuracy: 0.000_001)
    XCTAssertEqual(layout.adrenalineFrame.width, 389.12, accuracy: 0.000_001)
    XCTAssertEqual(layout.adrenalineFrame.height, 107.376, accuracy: 0.000_001)
    XCTAssertEqual(layout.meterTrackFrame.minX, 16.384, accuracy: 0.000_001)
    XCTAssertEqual(layout.meterTrackFrame.minY, 661.936, accuracy: 0.000_001)
    XCTAssertEqual(layout.meterTrackFrame.width, 389.12, accuracy: 0.000_001)
    XCTAssertEqual(layout.meterTrackFrame.height, 75.776, accuracy: 0.000_001)
    XCTAssertEqual(layout.clockTopAnchor.x, 512, accuracy: 0.000_001)
    XCTAssertEqual(layout.clockTopAnchor.y, 752.64, accuracy: 0.000_001)

    XCTAssertEqual(layout.muteButtonFrame.minX, 14.336, accuracy: 0.000_001)
    XCTAssertEqual(layout.muteButtonFrame.minY, 13.056, accuracy: 0.000_001)
    XCTAssertEqual(layout.muteButtonFrame.width, 42, accuracy: 0.000_001)
    XCTAssertEqual(layout.pauseButtonFrame.minX, 63.504, accuracy: 0.000_001)
    XCTAssertEqual(layout.controlsFrame.width, 91.168, accuracy: 0.000_001)

    XCTAssertEqual(layout.scorePlateFrame.minX, 697.344, accuracy: 0.000_001)
    XCTAssertEqual(layout.scorePlateFrame.minY, 13.056, accuracy: 0.000_001)
    XCTAssertEqual(layout.scorePlateFrame.width, 312.32, accuracy: 0.000_001)
    XCTAssertEqual(layout.scorePlateFrame.height, 103.68, accuracy: 0.000_001)
    XCTAssertEqual(layout.feedbackTopAnchor.x, 512, accuracy: 0.000_001)
    XCTAssertEqual(layout.feedbackTopAnchor.y, 614.4, accuracy: 0.000_001)

    XCTAssertEqual(layout.clockFontSize, 43.008, accuracy: 0.000_001)
    XCTAssertEqual(layout.scoreFontSize, 50, accuracy: 0.000_001)
    XCTAssertEqual(layout.meterTitleFontSize, 20.992, accuracy: 0.000_001)
    XCTAssertEqual(layout.multiplierFontSize, 26.112, accuracy: 0.000_001)

    let sceneBounds = CGRect(origin: .zero, size: HUDLayout.referenceSize)
    XCTAssertTrue(sceneBounds.contains(layout.adrenalineFrame))
    XCTAssertTrue(sceneBounds.contains(layout.controlsFrame))
    XCTAssertTrue(sceneBounds.contains(layout.scorePlateFrame))
    XCTAssertLessThan(layout.controlsFrame.maxX, layout.scorePlateFrame.minX)
  }

  func testCompactHUDLayoutMatchesShortLandscapeOverrides() {
    let canonical = HUDLayout()
    let compact = HUDLayout(metrics: .compact)

    XCTAssertEqual(compact.adrenalineFrame.minX, 14.336, accuracy: 0.000_001)
    XCTAssertEqual(compact.adrenalineFrame.minY, 650.64, accuracy: 0.000_001)
    XCTAssertEqual(compact.adrenalineFrame.width, 409.6, accuracy: 0.000_001)
    XCTAssertEqual(compact.meterTrackFrame.minY, 664.24, accuracy: 0.000_001)
    XCTAssertEqual(compact.muteButtonFrame.width, 34, accuracy: 0.000_001)
    XCTAssertEqual(compact.pauseButtonFrame.minX, 55.504, accuracy: 0.000_001)
    XCTAssertEqual(compact.scorePlateFrame.minX, 692.224, accuracy: 0.000_001)
    XCTAssertEqual(compact.scorePlateFrame.width, 317.44, accuracy: 0.000_001)
    XCTAssertEqual(compact.scorePlateFrame.height, 111.36, accuracy: 0.000_001)

    XCTAssertGreaterThan(compact.adrenalineFrame.width, canonical.adrenalineFrame.width)
    XCTAssertGreaterThan(compact.scorePlateFrame.height, canonical.scorePlateFrame.height)
    XCTAssertLessThan(compact.muteButtonFrame.width, canonical.muteButtonFrame.width)
  }

  func testHUDLayoutScalesUniformlyWithTheScene() {
    let full = HUDLayout()
    let half = HUDLayout(sceneSize: CGSize(width: 512, height: 384))

    XCTAssertEqual(half.adrenalineFrame.minX, full.adrenalineFrame.minX / 2, accuracy: 0.000_001)
    XCTAssertEqual(half.adrenalineFrame.minY, full.adrenalineFrame.minY / 2, accuracy: 0.000_001)
    XCTAssertEqual(half.adrenalineFrame.width, full.adrenalineFrame.width / 2, accuracy: 0.000_001)
    XCTAssertEqual(half.meterTrackFrame.height, full.meterTrackFrame.height / 2, accuracy: 0.000_001)
    XCTAssertEqual(half.pauseButtonFrame.minX, full.pauseButtonFrame.minX / 2, accuracy: 0.000_001)
    XCTAssertEqual(half.scorePlateFrame.minX, full.scorePlateFrame.minX / 2, accuracy: 0.000_001)
    XCTAssertEqual(half.scorePlateFrame.height, full.scorePlateFrame.height / 2, accuracy: 0.000_001)
    XCTAssertEqual(half.clockFontSize, full.clockFontSize / 2, accuracy: 0.000_001)
  }

  func testAdrenalineMeterUsesExactCurveAndClippedProgressGeometry() {
    XCTAssertEqual(
      AdrenalineMeterGeometry.sourceCommands,
      [
        .move(CGPoint(x: 3, y: 87)),
        .curve(
          to: CGPoint(x: 190, y: 51),
          control1: CGPoint(x: 88, y: 90),
          control2: CGPoint(x: 155, y: 78)
        ),
        .curve(
          to: CGPoint(x: 317, y: 0),
          control1: CGPoint(x: 232, y: 29),
          control2: CGPoint(x: 276, y: 9)
        ),
        .line(CGPoint(x: 317, y: 83)),
        .curve(
          to: CGPoint(x: 190, y: 98),
          control1: CGPoint(x: 278, y: 91),
          control2: CGPoint(x: 234, y: 96)
        ),
        .curve(
          to: CGPoint(x: 3, y: 98),
          control1: CGPoint(x: 136, y: 100),
          control2: CGPoint(x: 74, y: 100)
        ),
        .close,
      ]
    )

    let frame = CGRect(x: 20, y: 30, width: 400, height: 100)
    let path = AdrenalineMeterGeometry.path(in: frame)
    XCTAssertEqual(path.boundingBox.minX, 23.75, accuracy: 0.000_001)
    XCTAssertEqual(path.boundingBox.minY, 30, accuracy: 0.000_001)
    XCTAssertEqual(path.boundingBox.width, 392.5, accuracy: 0.000_001)
    XCTAssertEqual(path.boundingBox.height, 100, accuracy: 0.000_001)

    XCTAssertEqual(
      AdrenalineMeterGeometry.fillFrame(in: frame, progress: -0.5).width,
      0,
      accuracy: 0.000_001
    )
    XCTAssertEqual(
      AdrenalineMeterGeometry.fillFrame(in: frame, progress: 0.5).width,
      200,
      accuracy: 0.000_001
    )
    XCTAssertEqual(
      AdrenalineMeterGeometry.fillFrame(in: frame, progress: 1.5).width,
      400,
      accuracy: 0.000_001
    )
    let dividers = AdrenalineMeterGeometry.dividerXPositions(in: frame)
    XCTAssertEqual(dividers.count, 9)
    XCTAssertEqual(dividers.first, 60)
    XCTAssertEqual(dividers.last, 380)
  }

  func testHUDPresentationFormatsOriginalLabelsAndClampsMeter() {
    var state = GameState()
    state.phase = .playing
    state.remainingMilliseconds = 60_000
    state.score = 17_375
    state.touchdownMeter = 50
    state.touchdownStreak = 2

    let presentation = HUDPresentation(state: state)
    XCTAssertTrue(presentation.isVisible)
    XCTAssertEqual(presentation.clockText, "1:00")
    XCTAssertEqual(presentation.scoreText, "17,375")
    XCTAssertEqual(presentation.multiplierText, "TD x1.5")
    XCTAssertEqual(presentation.meterProgress, 0.5, accuracy: 0.000_001)
    XCTAssertFalse(presentation.isBonusActive)
    XCTAssertFalse(presentation.isTimerWarning)

    state.touchdownMeter = -20
    XCTAssertEqual(HUDPresentation(state: state).meterProgress, 0, accuracy: 0.000_001)
    state.touchdownMeter = 150
    let full = HUDPresentation(state: state)
    XCTAssertEqual(full.meterProgress, 1, accuracy: 0.000_001)
    XCTAssertTrue(full.isBonusActive)

    XCTAssertEqual(HUDPresentation.formatMultiplier(streak: 0), "TD x1")
    XCTAssertEqual(HUDPresentation.formatMultiplier(streak: 1), "TD x1.25")
    XCTAssertEqual(HUDPresentation.formatMultiplier(streak: 2), "TD x1.5")
    XCTAssertEqual(HUDPresentation.formatMultiplier(streak: 100), "TD x3")
  }

  func testHUDPresentationClockWarningAndPhaseVisibility() {
    XCTAssertEqual(HUDPresentation.formatClock(remainingMilliseconds: 59_999), "1:00")
    XCTAssertEqual(HUDPresentation.formatClock(remainingMilliseconds: 44_000), "0:44")
    XCTAssertEqual(HUDPresentation.formatClock(remainingMilliseconds: 10_001), "0:11")
    XCTAssertEqual(HUDPresentation.formatClock(remainingMilliseconds: 10_000), "0:10")
    XCTAssertEqual(HUDPresentation.formatClock(remainingMilliseconds: 1), "0:01")
    XCTAssertEqual(HUDPresentation.formatClock(remainingMilliseconds: 0), "0:00")
    XCTAssertEqual(HUDPresentation.formatClock(remainingMilliseconds: -1), "0:00")

    for (phase, expectedVisibility) in [
      (GamePhase.title, false),
      (.countdown, false),
      (.playing, true),
      (.resolvingFinalBall, true),
      (.paused, false),
      (.results, false),
    ] {
      var state = GameState()
      state.phase = phase
      state.remainingMilliseconds = 10_001
      let beforeWarning = HUDPresentation(state: state)
      XCTAssertEqual(beforeWarning.isVisible, expectedVisibility, "Unexpected visibility for \(phase)")
      XCTAssertFalse(beforeWarning.isTimerWarning)

      state.remainingMilliseconds = 10_000
      XCTAssertEqual(
        HUDPresentation(state: state).isTimerWarning,
        expectedVisibility,
        "Unexpected warning state for \(phase)"
      )
    }
  }

  func testCompactHUDPreservesBrowserPhysicalClampsOnPhone() {
    let displayScale = CGFloat(520) / HUDLayout.referenceSize.width
    let layout = HUDLayout(metrics: .compact, displayScale: displayScale)

    XCTAssertEqual(layout.adrenalineFrame.width * displayScale, 208, accuracy: 0.000_001)
    XCTAssertEqual(layout.meterTrackFrame.height * displayScale, 48, accuracy: 0.000_001)
    XCTAssertEqual(layout.muteButtonFrame.width * displayScale, 28, accuracy: 0.000_001)
    XCTAssertEqual(layout.clockFontSize * displayScale, 26, accuracy: 0.000_001)
    XCTAssertEqual(layout.meterTitleFontSize * displayScale, 15, accuracy: 0.000_001)
    XCTAssertEqual(layout.meterActionFontSize * displayScale, 10, accuracy: 0.000_001)
    XCTAssertEqual(layout.multiplierFontSize * displayScale, 18, accuracy: 0.000_001)
    XCTAssertEqual(layout.readyCopyFontSize * displayScale, 12, accuracy: 0.000_001)
  }

  @MainActor
  func testCompactHUDUsesFullSizeTouchTargetsWithoutGrowingTheArtwork() {
    let viewport = GameViewport(
      viewSize: CGSize(width: 832, height: 384),
      safeAreaInsets: GameSafeAreaInsets(top: 0, left: 59, bottom: 21, right: 59)
    )
    let layout = HUDLayout(
      sceneSize: viewport.projection.sceneSize,
      contentRect: viewport.safeSceneFrame,
      metrics: .compact,
      displayScale: viewport.pointsPerSceneUnit
    )
    let hud = BroadcastHUDNode(layout: layout, textureLibrary: TextureLibrary())

    XCTAssertEqual(hud.muteButtonFrame, layout.muteButtonFrame)
    XCTAssertEqual(hud.pauseButtonFrame, layout.pauseButtonFrame)
    XCTAssertGreaterThanOrEqual(
      hud.muteHitFrame.width * viewport.pointsPerSceneUnit,
      44
    )
    XCTAssertGreaterThanOrEqual(
      hud.pauseHitFrame.width * viewport.pointsPerSceneUnit,
      44
    )
    XCTAssertLessThanOrEqual(hud.muteHitFrame.maxX, hud.pauseHitFrame.minX)
    XCTAssertTrue(hud.muteHitFrame.contains(layout.muteButtonFrame.center))
    XCTAssertTrue(hud.pauseHitFrame.contains(layout.pauseButtonFrame.center))
  }

  @MainActor
  func testControlButtonPixelCutPathFillsTheLeftEdge() {
    let frame = CGRect(x: 14, y: 13, width: 42, height: 42)
    let path = BroadcastHUDNode.controlPixelCutPath(in: frame, corner: 4)

    XCTAssertTrue(path.contains(CGPoint(x: frame.minX + 0.5, y: frame.midY)))
    XCTAssertTrue(path.contains(CGPoint(x: frame.maxX - 0.5, y: frame.midY)))
    XCTAssertFalse(path.contains(CGPoint(x: frame.minX + 0.5, y: frame.maxY - 0.5)))
    XCTAssertFalse(path.contains(CGPoint(x: frame.maxX - 0.5, y: frame.minY + 0.5)))
  }
}

private struct NativeAssetManifest: Decodable {
  struct Asset: Decodable {
    let path: String
    let kind: String
  }

  let schemaVersion: Int
  let assets: [Asset]
}

private extension CGRect {
  var center: CGPoint {
    CGPoint(x: midX, y: midY)
  }
}

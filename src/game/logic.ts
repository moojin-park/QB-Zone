import {
  DEFENDER_BLOCK_RADIUS,
  DEPTH_Z,
  RECEIVER_CATCH_RADIUS,
  THROW_TRAVEL_TIME,
  WORLD
} from './config';
import { clamp, lerp, segmentCircleIntersects } from './physics';
import { resolveScoreAndMeter } from './scoring';
import type {
  BallFlight,
  DepthKey,
  GameState,
  PlayOutcome,
  ReceiverState,
  UpdateIntent
} from './types';

function depthXLimit(z: number): number {
  const normalizedDepth = clamp(z / WORLD.maxDepth, 0, 1);
  return lerp(WORLD.fieldHalfWidth, WORLD.fieldHalfWidth * 0.55, normalizedDepth);
}

function moveWithBounds(
  x: number,
  vx: number,
  dt: number,
  limit: number
): { x: number; vx: number } {
  let nextX = x + vx * dt;
  let nextVx = vx;

  if (nextX < -limit) {
    nextX = -limit;
    nextVx = Math.abs(vx);
  } else if (nextX > limit) {
    nextX = limit;
    nextVx = -Math.abs(vx);
  }

  return { x: nextX, vx: nextVx };
}

function formatCompletion(depth: DepthKey, points: number): string {
  const label = depth.charAt(0).toUpperCase() + depth.slice(1);
  return `${label} Complete +${points}`;
}

function resolvePlay(
  state: GameState,
  depth: DepthKey,
  outcome: PlayOutcome,
  meterFullAtStart: boolean
): GameState {
  const scoreResult = resolveScoreAndMeter({
    currentScore: state.score,
    currentMeter: state.meter,
    outcome,
    depth,
    meterFullAtStart
  });

  const lastPlayText =
    outcome === 'completion'
      ? formatCompletion(depth, scoreResult.awardedPoints)
      : outcome === 'deflected'
        ? 'Deflected!'
        : 'Incompletion';

  return {
    ...state,
    score: scoreResult.nextScore,
    meter: scoreResult.nextMeter,
    lastPlayText,
    ball: null
  };
}

function receiverForDepth(receivers: ReceiverState[], depth: DepthKey): ReceiverState {
  const receiver = receivers.find((item) => item.depth === depth);
  if (!receiver) {
    throw new Error(`Missing receiver for depth: ${depth}`);
  }
  return receiver;
}

export function getBallPosition(ball: BallFlight): { x: number; z: number } {
  const t = clamp(ball.elapsed / ball.travelTime, 0, 1);
  return {
    x: lerp(ball.startX, ball.targetX, t),
    z: lerp(ball.startZ, ball.targetZ, t)
  };
}

function updateBall(state: GameState, dt: number): GameState {
  if (!state.ball) {
    return state;
  }

  const previous = getBallPosition(state.ball);
  const nextElapsed = Math.min(state.ball.elapsed + dt, state.ball.travelTime);
  const updatedBall: BallFlight = {
    ...state.ball,
    elapsed: nextElapsed
  };
  const current = getBallPosition(updatedBall);

  const deflected = segmentCircleIntersects(
    previous.x,
    previous.z,
    current.x,
    current.z,
    state.defender.x,
    state.defender.z,
    DEFENDER_BLOCK_RADIUS
  );

  if (deflected) {
    return resolvePlay(
      { ...state, ball: updatedBall },
      updatedBall.targetDepth,
      'deflected',
      updatedBall.meterFullAtStart
    );
  }

  if (nextElapsed >= updatedBall.travelTime) {
    const receiver = receiverForDepth(state.receivers, updatedBall.targetDepth);
    const dx = receiver.x - updatedBall.targetX;
    const dz = receiver.z - updatedBall.targetZ;
    const outcome: PlayOutcome =
      dx * dx + dz * dz <= RECEIVER_CATCH_RADIUS * RECEIVER_CATCH_RADIUS
        ? 'completion'
        : 'incompletion';

    return resolvePlay(
      { ...state, ball: updatedBall },
      updatedBall.targetDepth,
      outcome,
      updatedBall.meterFullAtStart
    );
  }

  return {
    ...state,
    ball: updatedBall
  };
}

export function updateGameState(
  prevState: GameState,
  dtSeconds: number,
  intent: UpdateIntent
): GameState {
  const dt = clamp(dtSeconds, 0, WORLD.maxDeltaSeconds);

  const receivers = prevState.receivers.map((receiver) => {
    const limit = depthXLimit(receiver.z);
    const moved = moveWithBounds(receiver.x, receiver.vx, dt, limit);
    return {
      ...receiver,
      ...moved
    };
  });

  const defenderLimit = depthXLimit(prevState.defender.z);
  const movedDefender = moveWithBounds(
    prevState.defender.x,
    prevState.defender.vx,
    dt,
    defenderLimit
  );

  let nextState: GameState = {
    ...prevState,
    timeSeconds: prevState.timeSeconds + dt,
    receivers,
    defender: {
      ...prevState.defender,
      ...movedDefender
    }
  };

  if (intent.throwIntent && !nextState.ball) {
    nextState = {
      ...nextState,
      ball: {
        startX: 0,
        startZ: 0,
        targetX: intent.throwIntent.targetX,
        targetZ: DEPTH_Z[intent.throwIntent.targetDepth],
        targetDepth: intent.throwIntent.targetDepth,
        elapsed: 0,
        travelTime: THROW_TRAVEL_TIME[intent.throwIntent.targetDepth],
        meterFullAtStart: nextState.meter >= 100
      }
    };
  }

  return updateBall(nextState, dt);
}

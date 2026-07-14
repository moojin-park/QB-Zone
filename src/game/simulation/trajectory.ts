import { GAMEPLAY_CONFIG } from '../config/gameplayConfig';
import { normalizedThrowSpeed } from '../input/gestureMath';
import type { BallState, ScreenPoint, WorldPoint } from '../state/GameState';

const lerp = (start: number, end: number, amount: number): number => start + (end - start) * amount;

export interface TrajectoryParameters {
  durationMs: number;
  arcHeight: number;
  end: WorldPoint;
  speedNormalized: number;
}

export const createTrajectoryParameters = (
  start: WorldPoint,
  target: WorldPoint,
  releaseSpeedPxPerMs: number,
): TrajectoryParameters => {
  const speedNormalized = normalizedThrowSpeed(releaseSpeedPxPerMs);
  const distanceFactor = Math.min(1, Math.hypot(target.x - start.x, target.depth - start.depth));
  const baseDuration = lerp(
    GAMEPLAY_CONFIG.throw.maximumDurationMs,
    GAMEPLAY_CONFIG.throw.minimumDurationMs,
    speedNormalized,
  );
  const durationMs = baseDuration * lerp(0.86, 1.12, distanceFactor);
  const arcHeight = lerp(
    GAMEPLAY_CONFIG.throw.maximumArcHeight,
    GAMEPLAY_CONFIG.throw.minimumArcHeight,
    speedNormalized,
  );
  const end = {
    ...target,
    depth: Math.min(1.08, target.depth),
  };
  return { durationMs, arcHeight, end, speedNormalized };
};

export const getTrajectoryPosition = (
  start: WorldPoint,
  end: WorldPoint,
  arcHeight: number,
  progress: number,
): WorldPoint => {
  const t = Math.max(0, Math.min(1, progress));
  const horizontalProgress = Math.min(1, t / GAMEPLAY_CONFIG.throw.catchProgress);
  return {
    x: lerp(start.x, end.x, horizontalProgress),
    depth: lerp(start.depth, end.depth, horizontalProgress),
    height: Math.max(0, lerp(start.height, end.height, t) + 4 * arcHeight * t * (1 - t)),
  };
};

export const createBallState = (
  id: number,
  target: WorldPoint,
  releaseSpeedPxPerMs: number,
  aimMarker: ScreenPoint,
): BallState => {
  const start = { ...GAMEPLAY_CONFIG.quarterbackStart };
  const trajectory = createTrajectoryParameters(start, target, releaseSpeedPxPerMs);
  return {
    id,
    elapsedMs: 0,
    durationMs: trajectory.durationMs,
    start,
    target,
    end: trajectory.end,
    arcHeight: trajectory.arcHeight,
    current: { ...start },
    previous: { ...start },
    spinRadians: 0,
    radiusPx: GAMEPLAY_CONFIG.ballRadiusPx,
    releaseSpeedPxPerMs,
    aimMarker,
  };
};

export const advanceBall = (ball: BallState, deltaMs: number): void => {
  ball.previous = { ...ball.current };
  ball.elapsedMs = Math.min(ball.durationMs, ball.elapsedMs + deltaMs);
  ball.current = getTrajectoryPosition(
    ball.start,
    ball.end,
    ball.arcHeight,
    ball.elapsedMs / ball.durationMs,
  );
  ball.spinRadians += deltaMs * (0.014 + Math.min(0.02, ball.releaseSpeedPxPerMs * 0.008));
};

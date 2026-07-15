import {
  DEFAULT_BALL_RADIUS_PX,
  GAMEPLAY_CONFIG,
  getLaneConfig,
  type LaneId,
} from '../config/gameplayConfig';
import type { BallState, DefenderState, ReceiverState, WorldPoint } from '../state/GameState';
import { halfFieldWidthAtDepth, worldToScreen } from '../rendering/projection';
import {
  createDefenderHitZones,
  hitTestDefenderLocal,
  type DefenderHitZone,
} from './defenderHitZones';

const COLLISION_PROJECTION = {
  width: GAMEPLAY_CONFIG.classicLogicalWidth,
  height: GAMEPLAY_CONFIG.logicalHeight,
} as const;

export interface CollisionCandidate {
  type: 'receiver' | 'defender';
  progress: number;
  laneId: LaneId | null;
  receiver?: ReceiverState;
  defender?: DefenderState;
  hitZone?: DefenderHitZone;
  point: WorldPoint;
}

const crossingProgress = (
  previousDepth: number,
  currentDepth: number,
  targetDepth: number,
): number | null => {
  const delta = currentDepth - previousDepth;
  if (Math.abs(delta) < 0.000_001) {
    return Math.abs(currentDepth - targetDepth) <= 0.01 ? 1 : null;
  }
  const progress = (targetDepth - previousDepth) / delta;
  return progress >= 0 && progress <= 1 ? progress : null;
};

const interpolatePoint = (
  previous: WorldPoint,
  current: WorldPoint,
  progress: number,
): WorldPoint => ({
  x: previous.x + (current.x - previous.x) * progress,
  depth: previous.depth + (current.depth - previous.depth) * progress,
  height: previous.height + (current.height - previous.height) * progress,
});

export const findReceiverCollision = (
  ball: BallState,
  receivers: readonly ReceiverState[],
): CollisionCandidate | null => {
  const candidates: CollisionCandidate[] = [];
  const flightProgress = ball.durationMs > 0 ? ball.elapsedMs / ball.durationMs : 1;
  const descendingBallScreen =
    flightProgress >= GAMEPLAY_CONFIG.throw.catchProgress
      ? worldToScreen(ball.current, COLLISION_PROJECTION)
      : null;
  for (const receiver of receivers) {
    if (receiver.hasCaught) continue;

    const lane = getLaneConfig(receiver.laneId);
    const progress = crossingProgress(
      ball.previous.depth,
      ball.current.depth,
      lane.normalizedDepth,
    );
    if (progress !== null) {
      const point = interpolatePoint(ball.previous, ball.current, progress);
      const leadAdjustedReceiverX = receiver.x;
      const withinCatchWidth = Math.abs(point.x - leadAdjustedReceiverX) <= lane.catchWidth;
      const withinCatchHeight = point.height >= 0.08 && point.height <= 0.92;
      if (withinCatchWidth && withinCatchHeight) {
        candidates.push({
          type: 'receiver',
          progress,
          laneId: receiver.laneId,
          receiver,
          point,
        });
      }
    }

    if (!descendingBallScreen) continue;

    // Aiming at the visible body of a receiver maps the marker above that
    // receiver's ground-anchored lane. Once the ball begins its final descent
    // onto the marker, reconcile collision with the same screen-space catch
    // area the player sees instead of requiring another depth-plane crossing.
    const receiverTop = worldToScreen(
      { x: receiver.x, depth: lane.normalizedDepth, height: 0.92 },
      COLLISION_PROJECTION,
    );
    const receiverBottom = worldToScreen(
      { x: receiver.x, depth: lane.normalizedDepth, height: 0.08 },
      COLLISION_PROJECTION,
    );
    const halfCatchWidth =
      lane.catchWidth * halfFieldWidthAtDepth(COLLISION_PROJECTION, lane.normalizedDepth);
    const withinVisibleCatchWidth =
      Math.abs(descendingBallScreen.x - receiverBottom.x) <= halfCatchWidth;
    const withinVisibleCatchHeight =
      descendingBallScreen.y >= receiverTop.y && descendingBallScreen.y <= receiverBottom.y;
    if (withinVisibleCatchWidth && withinVisibleCatchHeight) {
      const catchCenterY = (receiverTop.y + receiverBottom.y) / 2;
      const horizontalDistance =
        Math.abs(descendingBallScreen.x - receiverBottom.x) / halfCatchWidth;
      const verticalDistance =
        Math.abs(descendingBallScreen.y - catchCenterY) /
        Math.max(1, (receiverBottom.y - receiverTop.y) / 2);
      candidates.push({
        type: 'receiver',
        // Swept world-space contacts remain authoritative when both forms of
        // collision happen in the same simulation step.
        progress: 1 + horizontalDistance + verticalDistance,
        laneId: receiver.laneId,
        receiver,
        point: { ...ball.current },
      });
    }
  }
  return candidates.sort((a, b) => a.progress - b.progress)[0] ?? null;
};

export const findDefenderCollision = (
  ball: BallState,
  defenders: readonly DefenderState[],
): CollisionCandidate | null => {
  const candidates: CollisionCandidate[] = [];
  const zones = createDefenderHitZones();
  for (const defender of defenders) {
    const progress = crossingProgress(ball.previous.depth, ball.current.depth, defender.depth);
    if (progress === null) continue;
    const point = interpolatePoint(ball.previous, ball.current, progress);
    const localX = (point.x - defender.x) / GAMEPLAY_CONFIG.defenderWidthWorld;
    const localPrevious = {
      x: (ball.previous.x - defender.x) / GAMEPLAY_CONFIG.defenderWidthWorld,
      y: ball.previous.height,
    };
    const localCurrent = { x: localX, y: point.height };
    const ballRadiusWorld = 0.035 * (ball.radiusPx / DEFAULT_BALL_RADIUS_PX);
    const zone = hitTestDefenderLocal(localPrevious, localCurrent, ballRadiusWorld, zones);
    if (zone?.interceptsBall) {
      candidates.push({
        type: 'defender',
        progress,
        laneId: null,
        defender,
        hitZone: zone,
        point,
      });
    }
  }
  return candidates.sort((a, b) => a.progress - b.progress)[0] ?? null;
};

export const findFirstBallCollision = (
  ball: BallState,
  receivers: readonly ReceiverState[],
  defenders: readonly DefenderState[],
): CollisionCandidate | null => {
  const receiver = findReceiverCollision(ball, receivers);
  const defender = findDefenderCollision(ball, defenders);
  if (!receiver) return defender;
  if (!defender) return receiver;
  return receiver.progress <= defender.progress ? receiver : defender;
};

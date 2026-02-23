import { DEPTHS, DEPTH_Z, WORLD } from './config';
import { clamp, lerp } from './physics';
import type { AimPreview, DepthKey, GameState } from './types';

export interface Projection {
  worldToScreen: (x: number, z: number) => { x: number; y: number; scale: number };
  screenXToWorldXAtDepth: (screenX: number, depth: DepthKey) => number;
  nearestDepthForScreenY: (screenY: number) => DepthKey;
  depthScreenY: (depth: DepthKey) => number;
}

function depthToT(z: number): number {
  return clamp(z / WORLD.maxDepth, 0, 1);
}

export function createProjection(width: number, height: number): Projection {
  const centerX = width * 0.5;
  const nearY = height * 0.94;
  const farY = height * 0.12;
  const nearHalfWidth = width * 0.42;
  const farHalfWidth = width * 0.13;

  const halfWidthAtDepth = (z: number): number => {
    const t = depthToT(z);
    return lerp(nearHalfWidth, farHalfWidth, t);
  };

  const yAtDepth = (z: number): number => {
    const t = depthToT(z);
    return lerp(nearY, farY, t);
  };

  return {
    worldToScreen: (x, z) => {
      const t = depthToT(z);
      const halfWidth = halfWidthAtDepth(z);
      return {
        x: centerX + (x / WORLD.fieldHalfWidth) * halfWidth,
        y: yAtDepth(z),
        scale: lerp(1.2, 0.45, t)
      };
    },
    screenXToWorldXAtDepth: (screenX, depth) => {
      const z = DEPTH_Z[depth];
      const halfWidth = halfWidthAtDepth(z);
      const normalized = (screenX - centerX) / halfWidth;
      return clamp(normalized * WORLD.fieldHalfWidth, -WORLD.fieldHalfWidth, WORLD.fieldHalfWidth);
    },
    nearestDepthForScreenY: (screenY) => {
      let bestDepth: DepthKey = DEPTHS[0];
      let bestDistance = Number.POSITIVE_INFINITY;

      for (const depth of DEPTHS) {
        const y = yAtDepth(DEPTH_Z[depth]);
        const distance = Math.abs(screenY - y);
        if (distance < bestDistance) {
          bestDistance = distance;
          bestDepth = depth;
        }
      }

      return bestDepth;
    },
    depthScreenY: (depth) => yAtDepth(DEPTH_Z[depth])
  };
}

function drawReceiver(
  ctx: CanvasRenderingContext2D,
  projection: Projection,
  x: number,
  z: number,
  color: string
): void {
  const screen = projection.worldToScreen(x, z);
  ctx.beginPath();
  ctx.fillStyle = color;
  ctx.arc(screen.x, screen.y, 10 * screen.scale, 0, Math.PI * 2);
  ctx.fill();
}

function drawDefender(
  ctx: CanvasRenderingContext2D,
  projection: Projection,
  x: number,
  z: number
): void {
  const screen = projection.worldToScreen(x, z);
  const w = 13 * screen.scale;
  const h = 18 * screen.scale;
  ctx.fillStyle = '#f15b5b';
  ctx.fillRect(screen.x - w / 2, screen.y - h / 2, w, h);
}

function drawQB(ctx: CanvasRenderingContext2D, projection: Projection): void {
  const qb = projection.worldToScreen(0, 0);
  ctx.beginPath();
  ctx.fillStyle = '#2e5cff';
  ctx.arc(qb.x, qb.y, 14, 0, Math.PI * 2);
  ctx.fill();
}

function drawBall(
  ctx: CanvasRenderingContext2D,
  projection: Projection,
  ball: NonNullable<GameState['ball']>
): void {
  const t = clamp(ball.elapsed / ball.travelTime, 0, 1);
  const x = lerp(ball.startX, ball.targetX, t);
  const z = lerp(ball.startZ, ball.targetZ, t);
  const screen = projection.worldToScreen(x, z);

  ctx.beginPath();
  ctx.fillStyle = '#ffd66e';
  ctx.arc(screen.x, screen.y - 4 * screen.scale, 4 * screen.scale + 2, 0, Math.PI * 2);
  ctx.fill();
}

function drawAimGuide(
  ctx: CanvasRenderingContext2D,
  projection: Projection,
  aim: AimPreview,
  width: number
): void {
  if (!aim.active || !aim.targetDepth) {
    return;
  }

  const qb = projection.worldToScreen(0, 0);
  const target = projection.worldToScreen(aim.targetX, DEPTH_Z[aim.targetDepth]);

  ctx.strokeStyle = 'rgba(255, 255, 255, 0.75)';
  ctx.lineWidth = 2;
  ctx.setLineDash([8, 6]);
  ctx.beginPath();
  ctx.moveTo(qb.x, qb.y);
  ctx.lineTo(target.x, target.y);
  ctx.stroke();
  ctx.setLineDash([]);

  ctx.fillStyle = 'rgba(255, 255, 255, 0.45)';
  ctx.fillRect(0, 0, width, 26);
  ctx.fillStyle = '#102130';
  ctx.font = '13px monospace';
  ctx.fillText(`Target: ${aim.targetDepth.toUpperCase()}`, 10, 17);
}

function drawField(
  ctx: CanvasRenderingContext2D,
  projection: Projection,
  width: number,
  height: number
): void {
  ctx.clearRect(0, 0, width, height);

  const sky = ctx.createLinearGradient(0, 0, 0, height);
  sky.addColorStop(0, '#5ba6d6');
  sky.addColorStop(0.52, '#8bc6e6');
  sky.addColorStop(0.53, '#2f7347');
  sky.addColorStop(1, '#1f5936');
  ctx.fillStyle = sky;
  ctx.fillRect(0, 0, width, height);

  const nearLeft = projection.worldToScreen(-WORLD.fieldHalfWidth, 0);
  const nearRight = projection.worldToScreen(WORLD.fieldHalfWidth, 0);
  const farLeft = projection.worldToScreen(-WORLD.fieldHalfWidth, WORLD.maxDepth);
  const farRight = projection.worldToScreen(WORLD.fieldHalfWidth, WORLD.maxDepth);

  ctx.beginPath();
  ctx.moveTo(nearLeft.x, nearLeft.y);
  ctx.lineTo(nearRight.x, nearRight.y);
  ctx.lineTo(farRight.x, farRight.y);
  ctx.lineTo(farLeft.x, farLeft.y);
  ctx.closePath();
  ctx.fillStyle = '#2c8f49';
  ctx.fill();

  ctx.lineWidth = 3;
  ctx.strokeStyle = '#e9f8ea';
  ctx.stroke();

  for (const depth of DEPTHS) {
    const y = projection.depthScreenY(depth);
    const left = projection.worldToScreen(-WORLD.fieldHalfWidth, DEPTH_Z[depth]);
    const right = projection.worldToScreen(WORLD.fieldHalfWidth, DEPTH_Z[depth]);

    ctx.lineWidth = depth === 'endzone' ? 3 : 2;
    ctx.strokeStyle = depth === 'endzone' ? '#ffd66e' : 'rgba(255, 255, 255, 0.6)';
    ctx.beginPath();
    ctx.moveTo(left.x, y);
    ctx.lineTo(right.x, y);
    ctx.stroke();
  }
}

export function renderGame(
  ctx: CanvasRenderingContext2D,
  state: GameState,
  width: number,
  height: number,
  aim: AimPreview
): void {
  const projection = createProjection(width, height);

  drawField(ctx, projection, width, height);
  drawQB(ctx, projection);

  drawReceiver(ctx, projection, state.receivers[0].x, state.receivers[0].z, '#4ddf88');
  drawReceiver(ctx, projection, state.receivers[1].x, state.receivers[1].z, '#50c2ff');
  drawReceiver(ctx, projection, state.receivers[2].x, state.receivers[2].z, '#ffc857');

  drawDefender(ctx, projection, state.defender.x, state.defender.z);

  if (state.ball) {
    drawBall(ctx, projection, state.ball);
  }

  drawAimGuide(ctx, projection, aim, width);
}

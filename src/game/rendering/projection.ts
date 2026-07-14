import { VISUAL_CONFIG } from '../config/visualConfig';
import type { ScreenPoint, WorldPoint } from '../state/GameState';

const clamp = (value: number, minimum: number, maximum: number): number =>
  Math.max(minimum, Math.min(maximum, value));

export interface Projection {
  width: number;
  height: number;
}

const canonicalProjection: Projection = {
  width: VISUAL_CONFIG.field.canonicalWidth,
  height: VISUAL_CONFIG.field.canonicalHeight,
};

const projectionScale = (projection: Projection): number =>
  Math.min(
    projection.width / VISUAL_CONFIG.field.canonicalWidth,
    projection.height / VISUAL_CONFIG.field.canonicalHeight,
  );

export const perspectiveFactorAtDepth = (depth: number): number =>
  Math.pow(1 - clamp(depth, 0, 1), VISUAL_CONFIG.field.depthExponent);

export const actorScaleAtDepth = (depth: number): number => {
  const perspective = perspectiveFactorAtDepth(depth);
  return (
    VISUAL_CONFIG.field.farActorScale +
    (VISUAL_CONFIG.field.nearActorScale - VISUAL_CONFIG.field.farActorScale) * perspective
  );
};

export const groundYAtDepth = (
  depth: number,
  projection: Projection = canonicalProjection,
): number => {
  const perspective = perspectiveFactorAtDepth(depth);
  return (
    (VISUAL_CONFIG.field.horizonY +
      (VISUAL_CONFIG.field.nearGroundY - VISUAL_CONFIG.field.horizonY) * perspective) *
    projectionScale(projection)
  );
};

export const halfFieldWidthAtDepth = (projection: Projection, depth: number): number => {
  const perspective = perspectiveFactorAtDepth(depth);
  return (
    (VISUAL_CONFIG.field.farHalfWidthPx +
      (VISUAL_CONFIG.field.nearHalfWidthPx - VISUAL_CONFIG.field.farHalfWidthPx) * perspective) *
    projectionScale(projection)
  );
};

export const worldToScreen = (point: WorldPoint, projection: Projection): ScreenPoint => {
  const scale = actorScaleAtDepth(point.depth);
  return {
    x: projection.width / 2 + point.x * halfFieldWidthAtDepth(projection, point.depth),
    y:
      groundYAtDepth(point.depth, projection) -
      point.height * VISUAL_CONFIG.field.actorHeightPx * scale * projectionScale(projection),
  };
};

export const screenToFieldWorld = (point: ScreenPoint, projection: Projection): WorldPoint => {
  const scale = projectionScale(projection);
  const normalizedPerspective = clamp(
    (point.y / scale - VISUAL_CONFIG.field.horizonY) /
      (VISUAL_CONFIG.field.nearGroundY - VISUAL_CONFIG.field.horizonY),
    0,
    1,
  );
  const depth = 1 - Math.pow(normalizedPerspective, 1 / VISUAL_CONFIG.field.depthExponent);
  const halfWidth = halfFieldWidthAtDepth(projection, depth);
  return {
    x: clamp((point.x - projection.width / 2) / halfWidth, -1.18, 1.18),
    depth,
    height: 0,
  };
};

export const getQuarterbackRect = (projection: Projection): DOMRect => {
  const scale = projectionScale(projection);
  const width = 280 * scale;
  const top = 548 * scale;
  const bottom = 768 * scale;
  return new DOMRect(projection.width / 2 - width / 2, top, width, bottom - top);
};

export const isPointOnQuarterback = (point: ScreenPoint, projection: Projection): boolean => {
  const rect = getQuarterbackRect(projection);
  return (
    point.x >= rect.left && point.x <= rect.right && point.y >= rect.top && point.y <= rect.bottom
  );
};

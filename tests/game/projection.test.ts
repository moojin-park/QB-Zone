import { describe, expect, it } from 'vitest';
import { VISUAL_CONFIG } from '../../src/game/config/visualConfig';
import {
  actorScaleAtDepth,
  groundYAtDepth,
  halfFieldWidthAtDepth,
  perspectiveFactorAtDepth,
  screenToFieldWorld,
  worldToScreen,
  type Projection,
} from '../../src/game/rendering/projection';

const canonical: Projection = {
  width: VISUAL_CONFIG.field.canonicalWidth,
  height: VISUAL_CONFIG.field.canonicalHeight,
};

describe('canonical field projection', () => {
  it('uses one quadratic perspective factor for ground position, width, and actor scale', () => {
    expect(perspectiveFactorAtDepth(0)).toBe(1);
    expect(perspectiveFactorAtDepth(0.5)).toBe(0.25);
    expect(perspectiveFactorAtDepth(1)).toBe(0);

    expect(groundYAtDepth(0)).toBe(VISUAL_CONFIG.field.nearGroundY);
    expect(groundYAtDepth(0.5)).toBeCloseTo(397.75, 8);
    expect(groundYAtDepth(1)).toBe(VISUAL_CONFIG.field.horizonY);

    expect(halfFieldWidthAtDepth(canonical, 0)).toBe(VISUAL_CONFIG.field.nearHalfWidthPx);
    expect(halfFieldWidthAtDepth(canonical, 0.5)).toBeCloseTo(508.75, 8);
    expect(halfFieldWidthAtDepth(canonical, 1)).toBe(VISUAL_CONFIG.field.farHalfWidthPx);

    expect(actorScaleAtDepth(0)).toBe(VISUAL_CONFIG.field.nearActorScale);
    expect(actorScaleAtDepth(0.5)).toBeCloseTo(0.4375, 8);
    expect(actorScaleAtDepth(1)).toBe(VISUAL_CONFIG.field.farActorScale);
  });

  it.each([
    ['short', 0.28, 575.6992, 577.192, 0.6388],
    ['medium', 0.48, 411.2752, 513.952, 0.4528],
    ['deep', 0.68, 299.8912, 471.112, 0.3268],
    ['touchdown', 0.87, 243.2047, 449.3095, 0.262675],
  ])('places the %s lane at its calibrated landmark', (_, depth, y, halfWidth, actorScale) => {
    expect(groundYAtDepth(depth)).toBeCloseTo(y, 6);
    expect(halfFieldWidthAtDepth(canonical, depth)).toBeCloseTo(halfWidth, 6);
    expect(actorScaleAtDepth(depth)).toBeCloseTo(actorScale, 6);
  });

  it.each([
    { x: -0.9, depth: 0.08 },
    { x: -0.35, depth: 0.28 },
    { x: 0, depth: 0.48 },
    { x: 0.42, depth: 0.68 },
    { x: 0.93, depth: 0.96 },
  ])('round-trips a ground point through screen space: $x, $depth', ({ x, depth }) => {
    const screen = worldToScreen({ x, depth, height: 0 }, canonical);
    const restored = screenToFieldWorld(screen, canonical);

    expect(restored.x).toBeCloseTo(x, 8);
    expect(restored.depth).toBeCloseTo(depth, 8);
    expect(restored.height).toBe(0);
  });

  it('uses uniform canonical scaling without widening the camera in a wider viewport', () => {
    const wide: Projection = { width: 1366, height: 768 };
    const halfSize: Projection = { width: 512, height: 384 };

    expect(halfFieldWidthAtDepth(wide, 0.5)).toBeCloseTo(508.75, 8);
    expect(groundYAtDepth(0.5, wide)).toBeCloseTo(397.75, 8);
    expect(halfFieldWidthAtDepth(halfSize, 0.5)).toBeCloseTo(254.375, 8);
    expect(groundYAtDepth(0.5, halfSize)).toBeCloseTo(198.875, 8);
  });

  it('clamps screen points beyond the projected ground range to valid field depth', () => {
    expect(screenToFieldWorld({ x: 512, y: 100 }, canonical).depth).toBe(1);
    expect(screenToFieldWorld({ x: 512, y: 1_000 }, canonical).depth).toBe(0);
  });
});

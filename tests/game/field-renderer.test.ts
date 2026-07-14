import { describe, expect, it } from 'vitest';
import { VISUAL_CONFIG } from '../../src/game/config/visualConfig';
import { FIELD_YARD_LINE_DEPTHS, getEndZoneLayout } from '../../src/game/rendering/FieldRenderer';
import { groundYAtDepth, type Projection } from '../../src/game/rendering/projection';

const canonical: Projection = {
  width: VISUAL_CONFIG.field.canonicalWidth,
  height: VISUAL_CONFIG.field.canonicalHeight,
};

describe('end-zone field layout', () => {
  it('projects a clear end-zone band around the visual touchdown landmark', () => {
    const layout = getEndZoneLayout(canonical);

    expect(layout.backDepth).toBe(1);
    expect(layout.frontDepth).toBe(0.72);
    expect(layout.visualCenterDepth).toBe(0.8);
    expect(layout.backY).toBe(232);
    expect(layout.frontY).toBeCloseTo(283.9792, 6);
    expect(layout.bandHeight).toBeCloseTo(51.9792, 6);
    expect(Math.abs(layout.visualCenterY - layout.centerY)).toBeLessThan(1);
  });

  it('keeps the end-zone wordmark clear of both painted boundaries', () => {
    const layout = getEndZoneLayout(canonical);
    const projectedTextHeight = layout.textFontSize * layout.textScaleY;
    const textClearance = (layout.bandHeight - projectedTextHeight) / 2;

    expect(projectedTextHeight).toBeLessThan(layout.bandHeight / 2);
    expect(textClearance).toBeGreaterThan(15);
  });

  it('leaves no yard stripe inside or immediately beside the goal line', () => {
    const layout = getEndZoneLayout(canonical);
    const nearestYardDepth = FIELD_YARD_LINE_DEPTHS.at(-1);

    expect(nearestYardDepth).toBeDefined();
    expect(FIELD_YARD_LINE_DEPTHS.every((depth) => depth < layout.frontDepth)).toBe(true);
    expect(groundYAtDepth(nearestYardDepth!, canonical) - layout.frontY).toBeGreaterThan(50);
  });
});

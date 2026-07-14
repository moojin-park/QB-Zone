import { describe, expect, it } from 'vitest';
import { GAMEPLAY_CONFIG } from '../../src/game/config/gameplayConfig';
import {
  getAimTrajectoryScreenPoints,
  type AimPreview,
} from '../../src/game/rendering/CanvasRenderer';
import {
  screenToFieldWorld,
  type Projection,
  worldToScreen,
} from '../../src/game/rendering/projection';
import { createBallState, getTrajectoryPosition } from '../../src/game/simulation/trajectory';

const projection: Projection = {
  width: GAMEPLAY_CONFIG.classicLogicalWidth,
  height: GAMEPLAY_CONFIG.logicalHeight,
};

describe('aim trajectory rendering', () => {
  it('samples the same projected path that the released ball follows', () => {
    const aim: AimPreview = {
      start: { x: 512, y: 700 },
      current: { x: 690, y: 330 },
      releaseSpeedPxPerMs: 0.92,
      valid: true,
    };
    const target = screenToFieldWorld(aim.current, projection);
    const ball = createBallState(1, target, aim.releaseSpeedPxPerMs, aim.current);
    const preview = getAimTrajectoryScreenPoints(aim, projection);

    for (const index of [0, 9, 18, 27, 36]) {
      const actualPosition = getTrajectoryPosition(
        ball.start,
        ball.end,
        ball.arcHeight,
        index / 36,
      );
      const actualScreen = worldToScreen(actualPosition, projection);
      expect(preview[index]!.x).toBeCloseTo(actualScreen.x, 8);
      expect(preview[index]!.y).toBeCloseTo(actualScreen.y, 8);
    }
  });

  it('shows slower releases with a visibly higher arc', () => {
    const baseAim = {
      start: { x: 512, y: 700 },
      current: { x: 650, y: 360 },
      valid: true,
    };
    const slow = getAimTrajectoryScreenPoints(
      { ...baseAim, releaseSpeedPxPerMs: GAMEPLAY_CONFIG.throw.slowSpeedPxPerMs },
      projection,
    );
    const fast = getAimTrajectoryScreenPoints(
      { ...baseAim, releaseSpeedPxPerMs: GAMEPLAY_CONFIG.throw.fastSpeedPxPerMs },
      projection,
    );

    expect(slow[18]!.y).toBeLessThan(fast[18]!.y);
  });
});

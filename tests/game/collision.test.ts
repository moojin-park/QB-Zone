import { describe, expect, it } from 'vitest';
import { GAMEPLAY_CONFIG } from '../../src/game/config/gameplayConfig';
import type {
  BallState,
  DefenderState,
  ReceiverState,
  WorldPoint,
} from '../../src/game/state/GameState';
import {
  findDefenderCollision,
  findFirstBallCollision,
  findReceiverCollision,
} from '../../src/game/simulation/collision';
import { screenToFieldWorld } from '../../src/game/rendering/projection';
import {
  createDefenderHitZones,
  hitTestDefenderLocal,
  type DefenderHitZoneId,
} from '../../src/game/simulation/defenderHitZones';
import {
  distancePointToSegmentSquared,
  distanceSegmentToSegmentSquared,
  segmentIntersectsShape,
} from '../../src/game/simulation/geometry';
import { createBallState, getTrajectoryPosition } from '../../src/game/simulation/trajectory';

const world = (x: number, depth: number, height: number): WorldPoint => ({ x, depth, height });

const ballBetween = (previous: WorldPoint, current: WorldPoint): BallState => ({
  id: 1,
  elapsedMs: 10,
  durationMs: 100,
  start: previous,
  target: current,
  end: current,
  arcHeight: 0,
  current,
  previous,
  spinRadians: 0,
  radiusPx: GAMEPLAY_CONFIG.ballRadiusPx,
  releaseSpeedPxPerMs: 1,
  aimMarker: { x: 0, y: 0 },
});

const receiver = (laneId: ReceiverState['laneId'], x = 0, id = 1): ReceiverState => ({
  id,
  laneId,
  x,
  direction: 1,
  speedPerMs: 0,
  animationMs: 0,
  pose: 'run',
  hasCaught: false,
});

const defender = (depth = 0.5, x = 0): DefenderState => ({
  id: 10,
  depth,
  x,
  direction: 1,
  speedPerMs: 0,
  animationMs: 0,
  pose: 'run',
});

describe('defender body-part hit zones', () => {
  const expectedZones: readonly [DefenderHitZoneId, boolean][] = [
    ['head-valid', true],
    ['head-top-pass-through', false],
    ['left-arm-valid', true],
    ['right-arm-valid', true],
    ['left-hand-pass-through', false],
    ['right-hand-pass-through', false],
    ['torso-valid', true],
    ['hips-valid', true],
    ['left-lower-leg-pass-through', false],
    ['right-lower-leg-pass-through', false],
    ['left-foot-pass-through', false],
    ['right-foot-pass-through', false],
  ];

  it('defines every required zone exactly once with the required interception policy', () => {
    const zones = createDefenderHitZones();

    expect(zones.map(({ id, interceptsBall }) => [id, interceptsBall])).toEqual(expectedZones);
    expect(new Set(zones.map((zone) => zone.id)).size).toBe(expectedZones.length);
  });

  it.each([
    ['head-valid', { x: 0, y: 0.78 }],
    ['head-top-pass-through', { x: 0, y: 0.98 }],
    ['left-arm-valid', { x: -0.25, y: 0.56 }],
    ['right-arm-valid', { x: 0.25, y: 0.56 }],
    ['left-hand-pass-through', { x: -0.43, y: 0.4 }],
    ['right-hand-pass-through', { x: 0.43, y: 0.4 }],
    ['torso-valid', { x: 0, y: 0.55 }],
    ['hips-valid', { x: 0.22, y: 0.34 }],
    ['left-lower-leg-pass-through', { x: -0.15, y: 0.18 }],
    ['right-lower-leg-pass-through', { x: 0.15, y: 0.18 }],
    ['left-foot-pass-through', { x: -0.24, y: 0.03 }],
    ['right-foot-pass-through', { x: 0.24, y: 0.03 }],
  ] as const)('classifies a direct hit on %s', (expectedId, point) => {
    const zone = hitTestDefenderLocal(point, point, 0);

    expect(zone?.id).toBe(expectedId);
    expect(zone?.interceptsBall).toBe(expectedZones.find(([id]) => id === expectedId)?.[1]);
  });

  it('returns no body zone for a clear miss', () => {
    expect(hitTestDefenderLocal({ x: -1, y: 1.2 }, { x: -0.8, y: 1.2 }, 0)).toBeNull();
  });

  it('detects a swept valid-zone crossing even when both endpoints miss', () => {
    const zone = hitTestDefenderLocal({ x: -0.8, y: 0.55 }, { x: 0.8, y: 0.55 }, 0);

    expect(zone?.interceptsBall).toBe(true);
    expect(['left-arm-valid', 'torso-valid', 'right-arm-valid']).toContain(zone?.id);
  });

  it('gives an explicit pass-through area priority in an overlapping boundary region', () => {
    const zone = hitTestDefenderLocal({ x: 0, y: 0.9 }, { x: 0, y: 0.9 }, 0.01);

    expect(zone?.id).toBe('head-top-pass-through');
    expect(zone?.interceptsBall).toBe(false);
  });

  it('continues beyond a pass-through cap and intercepts a later valid body contact', () => {
    const zone = hitTestDefenderLocal({ x: 0, y: 1.1 }, { x: 0, y: 0.2 }, 0);

    expect(zone?.interceptsBall).toBe(true);
    expect(['head-valid', 'torso-valid', 'hips-valid']).toContain(zone?.id);
  });
});

describe('swept geometry primitives', () => {
  it('computes squared distance to the interior of a segment', () => {
    expect(distancePointToSegmentSquared({ x: 1, y: 1 }, { x: 0, y: 0 }, { x: 2, y: 0 })).toBe(1);
  });

  it('computes squared distance to a degenerate point segment', () => {
    expect(distancePointToSegmentSquared({ x: 4, y: 5 }, { x: 1, y: 1 }, { x: 1, y: 1 })).toBe(25);
  });

  it('reports zero distance for crossing segments', () => {
    expect(
      distanceSegmentToSegmentSquared(
        { x: -1, y: 0 },
        { x: 1, y: 0 },
        { x: 0, y: -1 },
        { x: 0, y: 1 },
      ),
    ).toBe(0);
  });

  it('detects a segment sweeping through a circle with endpoints outside it', () => {
    expect(
      segmentIntersectsShape(
        { x: -2, y: 0 },
        { x: 2, y: 0 },
        { kind: 'circle', center: { x: 0, y: 0 }, radius: 0.2 },
      ),
    ).toBe(true);
  });

  it('uses ball-radius expansion for a tangent near miss', () => {
    const shape = { kind: 'circle' as const, center: { x: 0, y: 0 }, radius: 0.2 };

    expect(segmentIntersectsShape({ x: -1, y: 0.3 }, { x: 1, y: 0.3 }, shape)).toBe(false);
    expect(segmentIntersectsShape({ x: -1, y: 0.3 }, { x: 1, y: 0.3 }, shape, 0.1)).toBe(true);
  });

  it('detects a swept segment against a capsule', () => {
    expect(
      segmentIntersectsShape(
        { x: -1, y: 0.5 },
        { x: 1, y: 0.5 },
        {
          kind: 'capsule',
          start: { x: 0, y: 0 },
          end: { x: 0, y: 1 },
          radius: 0.05,
        },
      ),
    ).toBe(true);
  });
});

describe('receiver and defender collision ordering', () => {
  it('catches a ball swept through the receiver lane at valid height and width', () => {
    const ball = ballBetween(world(0, 0.2, 0.5), world(0, 0.35, 0.5));

    expect(findReceiverCollision(ball, [receiver('short')])).toMatchObject({
      type: 'receiver',
      laneId: 'short',
      receiver: { id: 1 },
    });
  });

  it.each([
    ['below the catch window', 0.05],
    ['above the catch window', 0.95],
  ])('passes a receiver %s', (_label, height) => {
    const ball = ballBetween(world(0, 0.2, height), world(0, 0.35, height));

    expect(findReceiverCollision(ball, [receiver('short')])).toBeNull();
  });

  it('misses a receiver outside the lane catch width', () => {
    const ball = ballBetween(world(0.4, 0.2, 0.5), world(0.4, 0.35, 0.5));

    expect(findReceiverCollision(ball, [receiver('short', 0)])).toBeNull();
  });

  it('ignores a receiver that already caught a ball during its current trip', () => {
    const ball = ballBetween(world(0, 0.2, 0.5), world(0, 0.35, 0.5));
    const ineligibleReceiver = receiver('short');
    ineligibleReceiver.hasCaught = true;

    expect(findReceiverCollision(ball, [ineligibleReceiver])).toBeNull();
  });

  it('selects the first receiver lane crossed during a large simulation step', () => {
    const ball = ballBetween(world(0, 0.2, 0.5), world(0, 0.8, 0.5));

    expect(
      findReceiverCollision(ball, [receiver('deep', 0, 2), receiver('short', 0, 1)])?.laneId,
    ).toBe('short');
  });

  it.each([
    ['slow lob', GAMEPLAY_CONFIG.throw.slowSpeedPxPerMs],
    ['fast throw', GAMEPLAY_CONFIG.throw.fastSpeedPxPerMs],
  ] as const)(
    'catches a %s aimed at the visible receiver body after it misses the lane plane',
    (_label, releaseSpeed) => {
      const aimMarker = { x: 512, y: 430 };
      const target = screenToFieldWorld(aimMarker, {
        width: GAMEPLAY_CONFIG.classicLogicalWidth,
        height: GAMEPLAY_CONFIG.logicalHeight,
      });
      const ball = createBallState(1, target, releaseSpeed, aimMarker);
      const flightProgress = 0.97;
      ball.elapsedMs = ball.durationMs * flightProgress;
      ball.current = getTrajectoryPosition(ball.start, ball.end, ball.arcHeight, flightProgress);
      ball.previous = { ...ball.current };

      expect(target.depth).not.toBeCloseTo(0.28, 2);

      expect(findReceiverCollision(ball, [receiver('short')])).toMatchObject({
        type: 'receiver',
        laneId: 'short',
        receiver: { id: 1 },
        point: ball.current,
      });
    },
  );

  it('catches a descending ball that visibly overlaps a receiver after missing the lane plane', () => {
    const point = world(0, 0.4, 0.3);
    const ball = {
      ...ballBetween(point, point),
      elapsedMs: 90,
    };

    expect(findReceiverCollision(ball, [receiver('short')])).toMatchObject({
      type: 'receiver',
      laneId: 'short',
      receiver: { id: 1 },
      point,
    });
  });

  it('catches a body-aimed end-zone throw even when the marker is above the field horizon', () => {
    const aimMarker = { x: 512, y: 200 };
    const target = screenToFieldWorld(aimMarker, {
      width: GAMEPLAY_CONFIG.classicLogicalWidth,
      height: GAMEPLAY_CONFIG.logicalHeight,
    });
    const ball = createBallState(1, target, GAMEPLAY_CONFIG.throw.slowSpeedPxPerMs, aimMarker);
    const flightProgress = 0.97;
    ball.elapsedMs = ball.durationMs * flightProgress;
    ball.current = getTrajectoryPosition(ball.start, ball.end, ball.arcHeight, flightProgress);
    ball.previous = { ...ball.current };

    expect(target.depth).toBe(1);
    expect(findReceiverCollision(ball, [receiver('touchdown')])).toMatchObject({
      type: 'receiver',
      laneId: 'touchdown',
    });
  });

  it('does not use visible receiver overlap before the final descent', () => {
    const point = world(0, 0.4, 0.3);
    const ball = {
      ...ballBetween(point, point),
      elapsedMs: 50,
    };

    expect(findReceiverCollision(ball, [receiver('short')])).toBeNull();
  });

  it('does not catch a descending ball that is visibly clear of the receiver', () => {
    const point = world(1, 0.4, 0.3);
    const ball = {
      ...ballBetween(point, point),
      elapsedMs: 90,
    };

    expect(findReceiverCollision(ball, [receiver('short')])).toBeNull();
  });

  it('intercepts a ball at the defender torso', () => {
    const ball = ballBetween(world(0, 0.4, 0.55), world(0, 0.6, 0.55));

    expect(findDefenderCollision(ball, [defender()])).toMatchObject({
      type: 'defender',
      hitZone: { interceptsBall: true },
      defender: { id: 10 },
    });
  });

  it('does not intercept a ball through the helmet top', () => {
    const ball = ballBetween(world(0, 0.4, 0.98), world(0, 0.6, 0.98));

    expect(findDefenderCollision(ball, [defender()])).toBeNull();
  });

  it('does not intercept a ball through a lower leg', () => {
    const x = -0.15 * GAMEPLAY_CONFIG.defenderWidthWorld;
    const ball = ballBetween(world(x, 0.4, 0.18), world(x, 0.6, 0.18));

    expect(findDefenderCollision(ball, [defender()])).toBeNull();
  });

  it('prevents a fast ball from tunneling through a defender between frames', () => {
    const ball = ballBetween(world(0, 0.1, 0.55), world(0, 0.9, 0.55));

    expect(findDefenderCollision(ball, [defender(0.5)])?.hitZone?.interceptsBall).toBe(true);
  });

  it('resolves a nearer receiver before a deeper defender', () => {
    const ball = ballBetween(world(0, 0.2, 0.55), world(0, 0.8, 0.55));

    expect(findFirstBallCollision(ball, [receiver('short')], [defender(0.58)])?.type).toBe(
      'receiver',
    );
  });

  it('resolves a nearer defender before a deeper receiver', () => {
    const ball = ballBetween(world(0, 0.2, 0.55), world(0, 0.8, 0.55));

    expect(findFirstBallCollision(ball, [receiver('deep')], [defender(0.39)])?.type).toBe(
      'defender',
    );
  });
});

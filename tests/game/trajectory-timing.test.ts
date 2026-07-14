import { describe, expect, it } from 'vitest';
import {
  FINAL_BALL_GRACE_MS,
  GAMEPLAY_CONFIG,
  SESSION_DURATION_MS,
} from '../../src/game/config/gameplayConfig';
import { createInitialState } from '../../src/game/state/createInitialState';
import { selectAccuracy, selectCanThrow } from '../../src/game/state/selectors';
import {
  advanceBall,
  createBallState,
  createTrajectoryParameters,
  getTrajectoryPosition,
} from '../../src/game/simulation/trajectory';
import { updateGameplayTimer } from '../../src/game/simulation/timer';

const start = { x: 0, depth: 0.035, height: 0.56 };
const target = { x: 0.35, depth: 0.68, height: 0 };

describe('continuous pass trajectory', () => {
  it('makes a fast swipe flatter and faster than a slow swipe', () => {
    const slow = createTrajectoryParameters(start, target, GAMEPLAY_CONFIG.throw.slowSpeedPxPerMs);
    const fast = createTrajectoryParameters(start, target, GAMEPLAY_CONFIG.throw.fastSpeedPxPerMs);

    expect(fast.durationMs).toBeLessThan(slow.durationMs);
    expect(fast.arcHeight).toBeLessThan(slow.arcHeight);
    expect(slow.speedNormalized).toBe(0);
    expect(fast.speedNormalized).toBe(1);
  });

  it('preserves a continuous speed-to-duration mapping', () => {
    const slow = createTrajectoryParameters(start, target, GAMEPLAY_CONFIG.throw.slowSpeedPxPerMs);
    const middle = createTrajectoryParameters(
      start,
      target,
      (GAMEPLAY_CONFIG.throw.slowSpeedPxPerMs + GAMEPLAY_CONFIG.throw.fastSpeedPxPerMs) / 2,
    );
    const fast = createTrajectoryParameters(start, target, GAMEPLAY_CONFIG.throw.fastSpeedPxPerMs);

    expect(middle.durationMs).toBeLessThan(slow.durationMs);
    expect(middle.durationMs).toBeGreaterThan(fast.durationMs);
    expect(middle.arcHeight).toBeLessThan(slow.arcHeight);
    expect(middle.arcHeight).toBeGreaterThan(fast.arcHeight);
  });

  it('takes longer to reach a distant target at the same release speed', () => {
    const near = createTrajectoryParameters(start, { x: 0, depth: 0.12, height: 0 }, 1);
    const far = createTrajectoryParameters(start, { x: 0.9, depth: 0.95, height: 0 }, 1);

    expect(far.durationMs).toBeGreaterThan(near.durationMs);
  });

  it('extends the trajectory so the intended target occurs at catch progress', () => {
    const trajectory = createTrajectoryParameters(start, target, 1);
    const atCatch = getTrajectoryPosition(
      start,
      trajectory.end,
      trajectory.arcHeight,
      GAMEPLAY_CONFIG.throw.catchProgress,
    );

    expect(atCatch.x).toBeCloseTo(target.x, 10);
    expect(atCatch.depth).toBeCloseTo(target.depth, 10);
  });

  it('returns exact endpoints and clamps out-of-range progress', () => {
    const end = { x: 1, depth: 0.9, height: 0 };

    expect(getTrajectoryPosition(start, end, 0.5, -1)).toEqual(start);
    expect(getTrajectoryPosition(start, end, 0.5, 2)).toEqual(end);
  });

  it('adds the configured arc at the midpoint', () => {
    const end = { x: 1, depth: 0.9, height: 0 };
    const midpoint = getTrajectoryPosition(start, end, 0.7, 0.5);

    expect(midpoint.x).toBe(0.5);
    expect(midpoint.depth).toBeCloseTo((start.depth + end.depth) / 2, 10);
    expect(midpoint.height).toBeCloseTo((start.height + end.height) / 2 + 0.7, 10);
  });

  it('creates a ball with independent start/current/previous world points', () => {
    const ball = createBallState(42, target, 1, { x: 500, y: 200 });

    expect(ball).toMatchObject({
      id: 42,
      elapsedMs: 0,
      target,
      current: GAMEPLAY_CONFIG.quarterbackStart,
      previous: GAMEPLAY_CONFIG.quarterbackStart,
      radiusPx: GAMEPLAY_CONFIG.ballRadiusPx,
      releaseSpeedPxPerMs: 1,
      aimMarker: { x: 500, y: 200 },
    });
    expect(ball.current).not.toBe(ball.previous);
    expect(ball.current).not.toBe(ball.start);
  });

  it('advances fast passes farther than slow lobs over equal wall time', () => {
    const slow = createBallState(1, target, GAMEPLAY_CONFIG.throw.slowSpeedPxPerMs, { x: 0, y: 0 });
    const fast = createBallState(2, target, GAMEPLAY_CONFIG.throw.fastSpeedPxPerMs, { x: 0, y: 0 });

    advanceBall(slow, 250);
    advanceBall(fast, 250);

    expect(fast.current.depth).toBeGreaterThan(slow.current.depth);
  });

  it('is invariant to frame partitioning for position, elapsed time, and spin', () => {
    const singleStep = createBallState(1, target, 1.1, { x: 0, y: 0 });
    const manySteps = createBallState(1, target, 1.1, { x: 0, y: 0 });

    advanceBall(singleStep, 300);
    for (let index = 0; index < 30; index += 1) advanceBall(manySteps, 10);

    expect(manySteps.elapsedMs).toBeCloseTo(singleStep.elapsedMs, 10);
    expect(manySteps.current.x).toBeCloseTo(singleStep.current.x, 10);
    expect(manySteps.current.depth).toBeCloseTo(singleStep.current.depth, 10);
    expect(manySteps.current.height).toBeCloseTo(singleStep.current.height, 10);
    expect(manySteps.spinRadians).toBeCloseTo(singleStep.spinRadians, 10);
  });

  it('never advances elapsed time or position past the trajectory end', () => {
    const ball = createBallState(1, target, 1, { x: 0, y: 0 });

    advanceBall(ball, ball.durationMs * 10);

    expect(ball.elapsedMs).toBe(ball.durationMs);
    expect(ball.current).toEqual(ball.end);
  });

  it('spins a faster pass more rapidly over equal time', () => {
    const slow = createBallState(1, target, 0.3, { x: 0, y: 0 });
    const fast = createBallState(2, target, 2, { x: 0, y: 0 });

    advanceBall(slow, 100);
    advanceBall(fast, 100);

    expect(fast.spinRadians).toBeGreaterThan(slow.spinRadians);
  });
});

describe('authoritative gameplay timer', () => {
  it('initializes a run at exactly 60 seconds', () => {
    const state = createInitialState();

    expect(state.remainingMs).toBe(SESSION_DURATION_MS);
    expect(state.elapsedGameplayMs).toBe(0);
  });

  it('only consumes time during the playing phase', () => {
    const state = createInitialState();
    state.phase = 'title';

    expect(updateGameplayTimer(state, 5_000)).toBe(false);
    expect(state.remainingMs).toBe(SESSION_DURATION_MS);
    expect(state.elapsedGameplayMs).toBe(0);
  });

  it('subtracts active gameplay time without changing phase before zero', () => {
    const state = createInitialState();
    state.phase = 'playing';

    expect(updateGameplayTimer(state, 1_250)).toBe(false);
    expect(state.remainingMs).toBe(58_750);
    expect(state.elapsedGameplayMs).toBe(1_250);
    expect(state.phase).toBe('playing');
  });

  it('transitions to final-ball resolution exactly at zero', () => {
    const state = createInitialState();
    state.phase = 'playing';
    state.remainingMs = 20;

    expect(updateGameplayTimer(state, 20)).toBe(true);
    expect(state.remainingMs).toBe(0);
    expect(state.phase).toBe('resolving-final-ball');
    expect(state.finalBallGraceRemainingMs).toBe(FINAL_BALL_GRACE_MS);
  });

  it('signals expiration only once', () => {
    const state = createInitialState();
    state.phase = 'playing';
    state.remainingMs = 1;

    expect(updateGameplayTimer(state, 1)).toBe(true);
    expect(updateGameplayTimer(state, 1_000)).toBe(false);
    expect(state.elapsedGameplayMs).toBe(1);
  });

  it('produces the same timing state across different frame partitions', () => {
    const single = createInitialState();
    const partitioned = createInitialState();
    single.phase = 'playing';
    partitioned.phase = 'playing';

    updateGameplayTimer(single, 1_000);
    for (let index = 0; index < 100; index += 1) updateGameplayTimer(partitioned, 10);

    expect(partitioned.remainingMs).toBe(single.remainingMs);
    expect(partitioned.elapsedGameplayMs).toBe(single.elapsedGameplayMs);
    expect(partitioned.phase).toBe(single.phase);
  });
});

describe('throw availability and accuracy selectors', () => {
  it('allows a throw only while actively playing with no ball or cooldown', () => {
    const state = createInitialState();
    state.phase = 'playing';

    expect(selectCanThrow(state)).toBe(true);
  });

  it.each([
    ['timer is zero', { remainingMs: 0 }],
    ['play is cooling down', { playCooldownMs: 1 }],
    ['phase is final-ball resolution', { phase: 'resolving-final-ball' as const }],
  ])('blocks a throw when %s', (_label, patch) => {
    const state = createInitialState();
    state.phase = 'playing';
    Object.assign(state, patch);

    expect(selectCanThrow(state)).toBe(false);
  });

  it('blocks a second ball while one is already in flight', () => {
    const state = createInitialState();
    state.phase = 'playing';
    state.ball = createBallState(1, target, 1, { x: 0, y: 0 });

    expect(selectCanThrow(state)).toBe(false);
  });

  it('reports zero accuracy before any attempt', () => {
    expect(selectAccuracy(createInitialState())).toBe(0);
  });

  it('counts normal completions and touchdowns as accurate attempts', () => {
    const state = createInitialState();
    Object.assign(state.stats, { attempts: 7, completions: 2, touchdowns: 2 });

    expect(selectAccuracy(state)).toBe(57);
  });
});

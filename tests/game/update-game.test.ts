import { describe, expect, it } from 'vitest';
import {
  FINAL_BALL_GRACE_MS,
  GAMEPLAY_CONFIG,
  PASSING_LANES,
  getLaneConfig,
  type LaneId,
} from '../../src/game/config/gameplayConfig';
import { screenToFieldWorld } from '../../src/game/rendering/projection';
import { createInitialState } from '../../src/game/state/createInitialState';
import type { GameState, PassOutcome, ReceiverState } from '../../src/game/state/GameState';
import { advanceBall, createBallState } from '../../src/game/simulation/trajectory';
import { updateGame } from '../../src/game/simulation/updateGame';

const quiescentPlayingState = (): GameState => {
  const state = createInitialState();
  state.phase = 'playing';
  state.receivers = [];
  state.defenders = [];
  for (const lane of PASSING_LANES) state.laneSpawnTimers[lane.id] = Number.POSITIVE_INFINITY;
  return state;
};

const stationaryReceiver = (laneId: LaneId, x = 0): ReceiverState => ({
  id: 500,
  laneId,
  x,
  direction: 1,
  speedPerMs: 0,
  animationMs: 0,
  pose: 'run',
});

const setBallApproachingTarget = (state: GameState, laneId: LaneId, x = 0): number => {
  const depth = getLaneConfig(laneId).normalizedDepth;
  const ball = createBallState(100, { x, depth, height: 0 }, 1, { x: 500, y: 200 });
  advanceBall(ball, ball.durationMs * 0.8);
  state.ball = ball;
  return ball.durationMs * 0.04;
};

describe('updateGame phase and fixed-step behavior', () => {
  it('does nothing outside countdown, attract, or simulation phases', () => {
    const state = createInitialState();
    state.phase = 'instructions';
    const receiverX = state.receivers[0]!.x;

    expect(updateGame(state, 1_000)).toEqual({
      timerExpired: false,
      passResolved: null,
      laneId: null,
      scoreChanged: false,
      runReadyToFinish: false,
    });
    expect(state.remainingMs).toBe(60_000);
    expect(state.receivers[0]!.x).toBe(receiverX);
  });

  it('animates title-screen attract entities without consuming gameplay time', () => {
    const state = createInitialState();
    state.phase = 'title';
    const receiverX = state.receivers[0]!.x;

    updateGame(state, 100);

    expect(state.receivers[0]!.x).not.toBe(receiverX);
    expect(state.remainingMs).toBe(60_000);
    expect(state.elapsedGameplayMs).toBe(0);
  });

  it('keeps title-screen defenders on the same bounded patrol as gameplay', () => {
    const state = createInitialState();
    state.phase = 'title';
    const defender = state.defenders[0]!;
    defender.x = GAMEPLAY_CONFIG.defenderPatrolHalfWidth - 0.001;
    defender.direction = 1;

    updateGame(state, 100);

    expect(defender.x).toBeLessThan(GAMEPLAY_CONFIG.defenderPatrolHalfWidth);
    expect(defender.direction).toBe(-1);
  });

  it('decrements only the countdown clock during countdown', () => {
    const state = createInitialState();
    state.phase = 'countdown';
    state.countdownRemainingMs = 1_200;
    const receiverX = state.receivers[0]!.x;

    updateGame(state, 250);

    expect(state.countdownRemainingMs).toBe(950);
    expect(state.remainingMs).toBe(60_000);
    expect(state.receivers[0]!.x).toBe(receiverX);
  });

  it('halts all simulation while the debug freeze is active', () => {
    const state = quiescentPlayingState();
    state.debug.frozen = true;
    state.ball = createBallState(1, { x: 0, depth: 0.6, height: 0 }, 1, { x: 0, y: 0 });

    updateGame(state, 500);

    expect(state.remainingMs).toBe(60_000);
    expect(state.ball.elapsedMs).toBe(0);
  });

  it('applies the debug slow-motion scale consistently to time and movement', () => {
    const state = createInitialState();
    state.phase = 'playing';
    state.debug.slowMotion = 0.5;
    state.defenders = [];
    const item = state.receivers[0]!;
    const beforeX = item.x;

    updateGame(state, 200);

    expect(state.remainingMs).toBe(59_900);
    expect(item.x).toBeCloseTo(beforeX + item.direction * item.speedPerMs * 100, 12);
  });

  it('keeps the timer running and reduces cooldown between resolved passes', () => {
    const state = quiescentPlayingState();
    state.playCooldownMs = 500;

    updateGame(state, 200);

    expect(state.remainingMs).toBe(59_800);
    expect(state.playCooldownMs).toBe(300);
  });

  it('expires readable feedback during active simulation', () => {
    const state = quiescentPlayingState();
    state.feedback = { tone: 'positive', headline: 'COMPLETE', detail: '', remainingMs: 100 };

    updateGame(state, 100);

    expect(state.feedback).toBeNull();
  });

  it('produces equivalent ball and timer state across normal frame partitions', () => {
    const single = quiescentPlayingState();
    const partitioned = quiescentPlayingState();
    single.ball = createBallState(1, { x: 0.2, depth: 0.7, height: 0 }, 0.8, { x: 0, y: 0 });
    partitioned.ball = createBallState(1, { x: 0.2, depth: 0.7, height: 0 }, 0.8, { x: 0, y: 0 });

    updateGame(single, 240);
    for (let index = 0; index < 24; index += 1) updateGame(partitioned, 10);

    expect(partitioned.remainingMs).toBe(single.remainingMs);
    expect(partitioned.ball!.elapsedMs).toBeCloseTo(single.ball!.elapsedMs, 10);
    expect(partitioned.ball!.current.x).toBeCloseTo(single.ball!.current.x, 10);
    expect(partitioned.ball!.current.depth).toBeCloseTo(single.ball!.current.depth, 10);
    expect(partitioned.ball!.current.height).toBeCloseTo(single.ball!.current.height, 10);
  });
});

describe('pass resolution through updateGame', () => {
  it('resolves a swept receiver catch as a normal completion', () => {
    const state = quiescentPlayingState();
    const stepMs = setBallApproachingTarget(state, 'short');
    state.receivers = [stationaryReceiver('short')];

    const result = updateGame(state, stepMs);

    expect(result).toMatchObject({
      passResolved: 'completion',
      laneId: 'short',
      scoreChanged: true,
    });
    expect(state.score).toBe(500);
    expect(state.ball).toBeNull();
    expect(state.receivers[0]!.pose).toBe('catch');
    expect(state.receivers[0]!.animationMs).toBe(0);
  });

  it('resolves a swept end-zone catch as a touchdown', () => {
    const state = quiescentPlayingState();
    const stepMs = setBallApproachingTarget(state, 'touchdown');
    state.receivers = [stationaryReceiver('touchdown')];

    const result = updateGame(state, stepMs);

    expect(result).toMatchObject({
      passResolved: 'touchdown',
      laneId: 'touchdown',
      scoreChanged: true,
    });
    expect(state.score).toBe(2_500);
    expect(state.receivers[0]!.pose).toBe('celebrate');
    expect(state.receivers[0]!.animationMs).toBe(0);
  });

  it('resolves a ball that reaches the trajectory end as an incompletion', () => {
    const state = quiescentPlayingState();
    state.ball = createBallState(1, { x: 0, depth: 0.7, height: 0 }, 1, { x: 0, y: 0 });

    const result = updateGame(state, state.ball.durationMs);

    expect(result).toMatchObject({
      passResolved: 'incompletion',
      laneId: null,
      scoreChanged: false,
    });
    expect(state.stats.incompletions).toBe(1);
    expect(state.ball).toBeNull();
  });

  it('resolves a body-aimed marker overlap as a catch before endpoint incompletion', () => {
    const state = quiescentPlayingState();
    const aimMarker = { x: 512, y: 430 };
    const target = screenToFieldWorld(aimMarker, {
      width: GAMEPLAY_CONFIG.classicLogicalWidth,
      height: GAMEPLAY_CONFIG.logicalHeight,
    });
    state.receivers = [stationaryReceiver('short')];
    state.ball = createBallState(1, target, 1, aimMarker);
    advanceBall(state.ball, state.ball.durationMs * 0.97);

    const result = updateGame(state, state.ball.durationMs - state.ball.elapsedMs);

    expect(result).toMatchObject({
      passResolved: 'completion',
      laneId: 'short',
      scoreChanged: true,
    });
    expect(state.stats.completions).toBe(1);
    expect(state.stats.incompletions).toBe(0);
  });

  it.each([
    ['completion', 'medium', true],
    ['touchdown', 'touchdown', true],
    ['incompletion', null, false],
    ['interception', null, false],
  ] as const)(
    'applies and clears a forced %s outcome exactly once',
    (outcome, laneId, scoreChanged) => {
      const state = quiescentPlayingState();
      state.debug.forcedOutcome = outcome as PassOutcome;
      state.ball = createBallState(1, { x: 0, depth: 0.7, height: 0 }, 1, { x: 0, y: 0 });

      const result = updateGame(state, 1);

      expect(result).toMatchObject({ passResolved: outcome, laneId, scoreChanged });
      expect(state.debug.forcedOutcome).toBeNull();
      expect(state.stats.attempts).toBe(1);
    },
  );
});

describe('timer expiry and final-ball behavior', () => {
  it('becomes ready to finish immediately when time expires with no ball', () => {
    const state = quiescentPlayingState();
    state.remainingMs = 5;

    const result = updateGame(state, 5);

    expect(result).toMatchObject({ timerExpired: true, runReadyToFinish: true });
    expect(state.phase).toBe('resolving-final-ball');
    expect(state.remainingMs).toBe(0);
  });

  it('records only the final timer remainder when a fixed step crosses zero', () => {
    const state = quiescentPlayingState();
    state.remainingMs = 5;
    state.elapsedGameplayMs = 59_995;

    updateGame(state, 16);

    expect(state.remainingMs).toBe(0);
    expect(state.elapsedGameplayMs).toBe(60_000);
  });

  it('keeps a pre-zero football alive after the timer expires', () => {
    const state = quiescentPlayingState();
    state.remainingMs = 1;
    state.ball = createBallState(1, { x: 0, depth: 0.7, height: 0 }, 1, { x: 0, y: 0 });

    const result = updateGame(state, 1);

    expect(result).toMatchObject({ timerExpired: true, runReadyToFinish: false });
    expect(state.phase).toBe('resolving-final-ball');
    expect(state.ball).not.toBeNull();
    expect(state.finalBallGraceRemainingMs).toBe(FINAL_BALL_GRACE_MS - 1);
  });

  it('allows a pre-zero ball to score after crossing zero', () => {
    const state = quiescentPlayingState();
    state.remainingMs = 1;
    const stepMs = setBallApproachingTarget(state, 'deep');
    state.receivers = [stationaryReceiver('deep')];

    const result = updateGame(state, stepMs);

    expect(result).toMatchObject({
      timerExpired: true,
      passResolved: 'completion',
      laneId: 'deep',
      scoreChanged: true,
      runReadyToFinish: true,
    });
    expect(state.score).toBe(1_500);
    expect(state.phase).toBe('resolving-final-ball');
  });

  it('does not consume gameplay time during final-ball resolution', () => {
    const state = quiescentPlayingState();
    state.phase = 'resolving-final-ball';
    state.remainingMs = 0;
    state.elapsedGameplayMs = 60_000;
    state.finalBallGraceRemainingMs = 500;

    const result = updateGame(state, 100);

    expect(state.remainingMs).toBe(0);
    expect(state.elapsedGameplayMs).toBe(60_000);
    expect(state.finalBallGraceRemainingMs).toBe(400);
    expect(result.runReadyToFinish).toBe(true);
  });

  it('finishes when the final in-flight ball resolves naturally', () => {
    const state = quiescentPlayingState();
    state.phase = 'resolving-final-ball';
    state.remainingMs = 0;
    state.finalBallGraceRemainingMs = FINAL_BALL_GRACE_MS;
    state.ball = createBallState(1, { x: 0, depth: 0.7, height: 0 }, 1, { x: 0, y: 0 });
    advanceBall(state.ball, state.ball.durationMs - 1);

    const result = updateGame(state, 1);

    expect(result.passResolved).toBe('incompletion');
    expect(result.runReadyToFinish).toBe(true);
    expect(state.ball).toBeNull();
  });

  it('drops an unresolved final ball when the grace period expires', () => {
    const state = quiescentPlayingState();
    state.phase = 'resolving-final-ball';
    state.remainingMs = 0;
    state.finalBallGraceRemainingMs = 10;
    state.ball = createBallState(1, { x: 0, depth: 0.7, height: 0 }, 1, { x: 0, y: 0 });

    const result = updateGame(state, 10);

    expect(result.runReadyToFinish).toBe(true);
    expect(state.finalBallGraceRemainingMs).toBe(0);
    expect(state.ball).toBeNull();
    expect(state.stats.attempts).toBe(0);
  });
});

import { describe, expect, it } from 'vitest';
import { PASSING_LANES, type LaneId } from '../../src/game/config/gameplayConfig';
import { SCORE_CONFIG } from '../../src/game/config/scoringConfig';
import { createInitialState } from '../../src/game/state/createInitialState';
import { selectTdBonusActive, selectTouchdownMultiplier } from '../../src/game/state/selectors';
import { resolvePass } from '../../src/game/simulation/resolvePass';
import {
  applyPlayScore,
  calculatePlayScore,
  type ScoreState,
} from '../../src/game/simulation/scoring';

const scoreState = (patch: Partial<ScoreState> = {}): ScoreState => ({
  score: 0,
  tdMeter: 0,
  touchdownStreak: 0,
  ...patch,
});

describe('lane scoring configuration', () => {
  it.each([
    ['short', 500, 15],
    ['medium', 1_000, 35],
    ['deep', 1_500, 50],
    ['touchdown', 2_500, 0],
  ] as const)('%s lane awards %i points and %i meter', (laneId, points, meterGain) => {
    expect(SCORE_CONFIG.lanes[laneId]).toEqual({
      completionPoints: points,
      tdMeterGain: meterGain,
    });
    expect(PASSING_LANES.find((lane) => lane.id === laneId)).toMatchObject({
      completionPoints: points,
      tdMeterGain: meterGain,
    });
  });
});

describe('calculatePlayScore', () => {
  it.each([
    ['short', 500, 15],
    ['medium', 1_000, 35],
    ['deep', 1_500, 50],
  ] as const)(
    'scores a %s completion and preserves prior meter progress',
    (laneId, points, gain) => {
      const result = calculatePlayScore(
        scoreState({ score: 700, tdMeter: 10, touchdownStreak: 3 }),
        'completion',
        laneId,
      );

      expect(result).toMatchObject({
        outcome: 'completion',
        laneId,
        baseCompletionPoints: points,
        awardedPoints: points,
        totalScoreBefore: 700,
        totalScoreAfter: 700 + points,
        tdMeterBefore: 10,
        tdMeterAfter: 10 + gain,
        touchdownStreakBefore: 3,
        touchdownStreakAfter: 0,
        tdBonusPoints: 0,
        touchdownMultiplier: 1,
      });
    },
  );

  it.each([
    [0, 1],
    [1, 1.25],
    [2, 1.5],
    [3, 2],
    [4, 2.5],
    [5, 3],
    [9, 3],
  ] as const)('uses the configured multiplier for touchdown streak %i', (streak, multiplier) => {
    const result = calculatePlayScore(
      scoreState({ touchdownStreak: streak }),
      'touchdown',
      'touchdown',
    );

    expect(result.touchdownMultiplier).toBe(multiplier);
    expect(result.awardedPoints).toBe(Math.round(2_500 * multiplier));
    expect(result.touchdownStreakAfter).toBe(streak + 1);
  });

  it('adds the active TD bonus before applying the touchdown multiplier', () => {
    const result = calculatePlayScore(
      scoreState({ score: 10_000, tdMeter: SCORE_CONFIG.tdMeterMaximum, touchdownStreak: 3 }),
      'touchdown',
      'touchdown',
    );

    expect(result).toMatchObject({
      tdBonusWasActive: true,
      tdBonusPoints: 3_000,
      touchdownMultiplier: 2,
      awardedPoints: 11_000,
      totalScoreAfter: 21_000,
      tdMeterAfter: SCORE_CONFIG.tdMeterMaximum,
    });
  });

  it('does not award a TD bonus for a normal completion while the meter is active', () => {
    const result = calculatePlayScore(
      scoreState({ tdMeter: SCORE_CONFIG.tdMeterMaximum }),
      'completion',
      'deep',
    );

    expect(result.tdBonusWasActive).toBe(true);
    expect(result.tdBonusPoints).toBe(0);
    expect(result.awardedPoints).toBe(1_500);
    expect(result.tdMeterAfter).toBe(SCORE_CONFIG.tdMeterMaximum);
  });

  it('caps meter gain at the configured maximum', () => {
    const result = calculatePlayScore(
      scoreState({ tdMeter: SCORE_CONFIG.tdMeterMaximum - 1 }),
      'completion',
      'deep',
    );

    expect(result.tdMeterAfter).toBe(SCORE_CONFIG.tdMeterMaximum);
  });

  it('activates after one short, medium, and deep completion', () => {
    const state = createInitialState();

    for (const laneId of ['short', 'medium', 'deep'] as const) {
      applyPlayScore(state, calculatePlayScore(state, 'completion', laneId));
    }

    expect(state.tdMeter).toBe(100);
    expect(selectTdBonusActive(state)).toBe(true);
  });

  it('does not build meter progress on the touchdown payoff play', () => {
    const result = calculatePlayScore(scoreState({ tdMeter: 85 }), 'touchdown', 'touchdown');

    expect(result.tdBonusWasActive).toBe(false);
    expect(result.tdMeterAfter).toBe(85);
  });

  it.each(['incompletion', 'interception'] as const)(
    '%s awards zero and clears meter and touchdown streak',
    (outcome) => {
      const result = calculatePlayScore(
        scoreState({ score: 8_500, tdMeter: 85, touchdownStreak: 4 }),
        outcome,
        null,
      );

      expect(result).toMatchObject({
        outcome,
        laneId: null,
        baseCompletionPoints: 0,
        tdBonusPoints: 0,
        touchdownMultiplier: 1,
        awardedPoints: 0,
        totalScoreBefore: 8_500,
        totalScoreAfter: 8_500,
        tdMeterBefore: 85,
        tdMeterAfter: 0,
        touchdownStreakBefore: 4,
        touchdownStreakAfter: 0,
      });
    },
  );

  it('does not mutate its source score state and returns independent result objects', () => {
    const source = scoreState({ score: 2_000, tdMeter: 5, touchdownStreak: 1 });
    const before = { ...source };
    const first = calculatePlayScore(source, 'completion', 'medium');
    const second = calculatePlayScore(source, 'completion', 'medium');

    expect(source).toEqual(before);
    expect(first).toEqual(second);
    expect(first).not.toBe(second);
    expect(Object.isFrozen(first)).toBe(true);
    expect(Object.isFrozen(second)).toBe(true);
  });

  it('fills every detail field from the pre-play snapshot', () => {
    const result = calculatePlayScore(
      scoreState({ score: 4_200, tdMeter: 65, touchdownStreak: 2 }),
      'touchdown',
      'touchdown',
    );

    expect(result).toEqual({
      outcome: 'touchdown',
      laneId: 'touchdown',
      baseCompletionPoints: 2_500,
      tdBonusWasActive: false,
      tdBonusPoints: 0,
      touchdownMultiplier: 1.5,
      awardedPoints: 3_750,
      totalScoreBefore: 4_200,
      totalScoreAfter: 7_950,
      tdMeterBefore: 65,
      tdMeterAfter: 65,
      touchdownStreakBefore: 2,
      touchdownStreakAfter: 3,
    });
  });
});

describe('score application and pass resolution', () => {
  it.each([
    ['completion', 'short', 'completions'],
    ['touchdown', 'touchdown', 'touchdowns'],
    ['incompletion', null, 'incompletions'],
    ['interception', null, 'interceptions'],
  ] as const)('records exactly one attempt and the %s stat', (outcome, laneId, stat) => {
    const state = createInitialState();
    const result = calculatePlayScore(state, outcome, laneId as LaneId | null);

    applyPlayScore(state, result);

    expect(state.stats.attempts).toBe(1);
    expect(state.stats[stat]).toBe(1);
    const otherOutcomeCounts = [
      state.stats.completions,
      state.stats.touchdowns,
      state.stats.incompletions,
      state.stats.interceptions,
    ];
    expect(otherOutcomeCounts.reduce((sum, value) => sum + value, 0)).toBe(1);
  });

  it('keeps a prior score-result snapshot stable after later state changes', () => {
    const state = createInitialState();
    resolvePass(state, 'completion', 'medium');
    const firstResult = state.lastPlayScore;
    const snapshot = structuredClone(firstResult);

    state.score += 100_000;
    state.tdMeter = 0;
    state.touchdownStreak = 8;

    expect(firstResult).toEqual(snapshot);
  });

  it('tracks the longest touchdown streak without reducing the historical maximum', () => {
    const state = createInitialState();
    resolvePass(state, 'touchdown', 'touchdown');
    resolvePass(state, 'touchdown', 'touchdown');
    resolvePass(state, 'completion', 'short');

    expect(state.stats.longestTouchdownStreak).toBe(2);
    expect(state.touchdownStreak).toBe(0);
  });

  it('clears the active ball, creates feedback, and applies a short normal cooldown', () => {
    const state = createInitialState();
    state.ball = {
      id: 99,
      elapsedMs: 0,
      durationMs: 100,
      start: { x: 0, depth: 0, height: 0 },
      target: { x: 0, depth: 1, height: 0 },
      end: { x: 0, depth: 1, height: 0 },
      arcHeight: 0,
      current: { x: 0, depth: 0, height: 0 },
      previous: { x: 0, depth: 0, height: 0 },
      spinRadians: 0,
      radiusPx: 12,
      releaseSpeedPxPerMs: 1,
      aimMarker: { x: 0, y: 0 },
    };

    resolvePass(state, 'completion', 'deep');

    expect(state.ball).toBeNull();
    expect(state.playCooldownMs).toBe(250);
    expect(state.feedback).toMatchObject({ tone: 'positive', headline: 'DEEP COMPLETE +1,500' });
  });

  it('uses the longer touchdown cooldown and reports bonus/multiplier feedback', () => {
    const state = createInitialState();
    state.tdMeter = SCORE_CONFIG.tdMeterMaximum;
    state.touchdownStreak = 1;

    resolvePass(state, 'touchdown', 'touchdown');

    expect(state.playCooldownMs).toBe(420);
    expect(state.feedback).toMatchObject({
      tone: 'touchdown',
      headline: 'TOUCHDOWN +6,875',
      detail: 'TD BONUS · STREAK x1.25',
    });
  });

  it('derives bonus-active and capped multiplier selectors from authoritative state', () => {
    const state = createInitialState();
    state.tdMeter = SCORE_CONFIG.tdMeterMaximum;
    state.touchdownStreak = 20;

    expect(selectTdBonusActive(state)).toBe(true);
    expect(selectTouchdownMultiplier(state)).toBe(3);
  });
});

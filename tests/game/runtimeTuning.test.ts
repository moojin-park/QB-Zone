import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { GAMEPLAY_CONFIG, PASSING_LANES } from '../../src/game/config/gameplayConfig';
import {
  RUNTIME_TUNING_GROUPS,
  getRuntimeContinueDurationMs,
  getRuntimeSessionDurationMs,
  getRuntimeTuningValue,
  isRuntimeTuningControlOverridden,
  resetRuntimeTuningToDefaults,
  setRuntimeTuningValue,
} from '../../src/game/config/runtimeTuning';
import { SCORE_CONFIG } from '../../src/game/config/scoringConfig';

describe('development runtime tuning', () => {
  beforeEach(() => resetRuntimeTuningToDefaults());
  afterEach(() => resetRuntimeTuningToDefaults());

  it('exposes the complete grouped control surface', () => {
    const ids = RUNTIME_TUNING_GROUPS.flatMap((group) =>
      group.controls.map((control) => control.id),
    );

    expect(ids).toEqual(
      expect.arrayContaining([
        'session-duration',
        'continue-duration',
        'receiver-spawn-min',
        'lane-touchdown-depth',
        'lane-deep-receiver-crossing',
        'lane-short-catch-width',
        'defender-1-crossing',
        'defender-3-depth',
        'defender-hit-zone-scale',
        'ball-radius',
        'throw-fast-speed',
        'throw-min-duration',
        'arc-max-height',
        'score-touchdown',
        'meter-gain-medium',
        'meter-maximum',
        'td-bonus-points',
        'multiplier-6',
      ]),
    );
    expect(new Set(ids).size).toBe(ids.length);
  });

  it('bounds session and continue durations', () => {
    expect(setRuntimeTuningValue('session-duration', 2)).toBe(true);
    expect(setRuntimeTuningValue('continue-duration', 500)).toBe(true);

    expect(getRuntimeSessionDurationMs()).toBe(10_000);
    expect(getRuntimeContinueDurationMs()).toBe(60_000);
  });

  it('keeps lane depths ordered while updating live lane tuning', () => {
    setRuntimeTuningValue('lane-short-depth', 0.8);
    setRuntimeTuningValue('lane-deep-receiver-crossing', 8.4);
    setRuntimeTuningValue('lane-short-catch-width', 0.24);

    expect(PASSING_LANES[0]!.normalizedDepth).toBeLessThan(PASSING_LANES[1]!.normalizedDepth);
    expect(PASSING_LANES[2]!.receiverCrossingSeconds).toBe(8.4);
    expect(PASSING_LANES[0]!.catchWidth).toBe(0.24);
  });

  it('keeps receiver spawn delay bounds valid', () => {
    setRuntimeTuningValue('receiver-spawn-min', 2_900);
    setRuntimeTuningValue('receiver-spawn-max', 100);

    expect(GAMEPLAY_CONFIG.receiverSpawnDelayMs.max).toBeGreaterThan(
      GAMEPLAY_CONFIG.receiverSpawnDelayMs.min,
    );
  });

  it('updates defender speed, lane, and hit-zone scale configuration', () => {
    setRuntimeTuningValue('defender-1-crossing', 3.2);
    setRuntimeTuningValue('defender-2-depth', 0.7);
    setRuntimeTuningValue('defender-hit-zone-scale', 0.31);

    expect(GAMEPLAY_CONFIG.defenderCrossingSeconds[0]).toBe(3.2);
    expect(GAMEPLAY_CONFIG.defenderDepths[1]).toBeLessThan(GAMEPLAY_CONFIG.defenderDepths[2]!);
    expect(GAMEPLAY_CONFIG.defenderWidthWorld).toBe(0.31);
  });

  it('keeps throw speed, duration, and arc curves valid', () => {
    setRuntimeTuningValue('throw-slow-speed', 2);
    setRuntimeTuningValue('throw-fast-speed', 0.1);
    setRuntimeTuningValue('throw-min-duration', 1_500);
    setRuntimeTuningValue('throw-max-duration', 250);
    setRuntimeTuningValue('arc-min-height', 1.5);
    setRuntimeTuningValue('arc-max-height', 0.1);

    expect(GAMEPLAY_CONFIG.throw.fastSpeedPxPerMs).toBeGreaterThan(
      GAMEPLAY_CONFIG.throw.slowSpeedPxPerMs,
    );
    expect(GAMEPLAY_CONFIG.throw.maximumDurationMs).toBeGreaterThan(
      GAMEPLAY_CONFIG.throw.minimumDurationMs,
    );
    expect(GAMEPLAY_CONFIG.throw.maximumArcHeight).toBeGreaterThan(
      GAMEPLAY_CONFIG.throw.minimumArcHeight,
    );
  });

  it('keeps lane and scoring mirrors synchronized', () => {
    setRuntimeTuningValue('score-deep', 4_200);
    setRuntimeTuningValue('meter-gain-deep', 7);

    expect(SCORE_CONFIG.lanes.deep).toEqual({ completionPoints: 4_200, tdMeterGain: 7 });
    expect(PASSING_LANES[2]).toMatchObject({ completionPoints: 4_200, tdMeterGain: 7 });
  });

  it('tracks overrides and restores every authoritative default', () => {
    setRuntimeTuningValue('ball-radius', 20);
    setRuntimeTuningValue('meter-maximum', 25);
    setRuntimeTuningValue('multiplier-6', 8);

    expect(isRuntimeTuningControlOverridden('ball-radius')).toBe(true);
    expect(getRuntimeTuningValue('meter-maximum')).toBe(25);

    resetRuntimeTuningToDefaults();

    expect(GAMEPLAY_CONFIG.ballRadiusPx).toBe(12);
    expect(SCORE_CONFIG.tdMeterMaximum).toBe(12);
    expect(SCORE_CONFIG.touchdownMultipliers).toEqual([1, 1.25, 1.5, 2, 2.5, 3]);
    expect(isRuntimeTuningControlOverridden('ball-radius')).toBe(false);
  });

  it('rejects unknown controls and non-finite values', () => {
    expect(setRuntimeTuningValue('not-a-control', 1)).toBe(false);
    expect(setRuntimeTuningValue('ball-radius', Number.NaN)).toBe(false);
    expect(GAMEPLAY_CONFIG.ballRadiusPx).toBe(12);
  });
});

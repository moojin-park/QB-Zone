import { describe, expect, it } from 'vitest';
import { PlatformCallGuards } from '../../src/game/platform/guards';

describe('PlatformCallGuards', () => {
  it('deduplicates loading and lifecycle signals', () => {
    const guards = new PlatformCallGuards();

    expect(guards.markLoadingFinished()).toBe(true);
    expect(guards.markLoadingFinished()).toBe(false);
    expect(guards.beginGameplay()).toBe(true);
    expect(guards.beginGameplay()).toBe(false);
    expect(guards.stopGameplay()).toBe(true);
    expect(guards.stopGameplay()).toBe(false);
    expect(guards.beginGameplay()).toBe(true);
  });

  it('accepts only changed non-negative integer live scores', () => {
    const guards = new PlatformCallGuards();

    expect(guards.acceptLiveScore(0)).toBe(true);
    expect(guards.acceptLiveScore(0)).toBe(false);
    expect(guards.acceptLiveScore(500)).toBe(true);
    expect(guards.acceptLiveScore(-1)).toBe(false);
    expect(guards.acceptLiveScore(1.5)).toBe(false);
    expect(guards.acceptLiveScore(Number.MAX_SAFE_INTEGER + 1)).toBe(false);
  });

  it('submits one final score per run and resets on the next start', () => {
    const guards = new PlatformCallGuards();

    guards.beginGameplay();
    expect(guards.acceptFinalScore(2_500)).toEqual({
      accepted: true,
      stoppedActiveGameplay: true,
    });
    expect(guards.acceptFinalScore(2_500).accepted).toBe(false);
    expect(guards.acceptLiveScore(3_000)).toBe(false);

    expect(guards.beginGameplay()).toBe(true);
    expect(guards.snapshot().finalScoreSubmitted).toBe(false);
    expect(guards.acceptLiveScore(0)).toBe(true);
    expect(guards.acceptFinalScore(0).accepted).toBe(true);
  });
});

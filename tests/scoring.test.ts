import { describe, expect, it } from 'vitest';

import { resolveScoreAndMeter } from '../src/game/scoring';

describe('resolveScoreAndMeter', () => {
  it('awards short completion and adds meter', () => {
    const result = resolveScoreAndMeter({
      currentScore: 0,
      currentMeter: 0,
      outcome: 'completion',
      depth: 'short',
      meterFullAtStart: false
    });

    expect(result.awardedPoints).toBe(100);
    expect(result.nextScore).toBe(100);
    expect(result.nextMeter).toBe(25);
  });

  it('awards medium completion and meter fills to cap', () => {
    const result = resolveScoreAndMeter({
      currentScore: 200,
      currentMeter: 75,
      outcome: 'completion',
      depth: 'medium',
      meterFullAtStart: false
    });

    expect(result.awardedPoints).toBe(250);
    expect(result.nextScore).toBe(450);
    expect(result.nextMeter).toBe(100);
  });

  it('resets meter on endzone completion when meter is not full', () => {
    const result = resolveScoreAndMeter({
      currentScore: 0,
      currentMeter: 50,
      outcome: 'completion',
      depth: 'endzone',
      meterFullAtStart: false
    });

    expect(result.awardedPoints).toBe(500);
    expect(result.nextMeter).toBe(0);
  });

  it('doubles points when meter is full at play start', () => {
    const result = resolveScoreAndMeter({
      currentScore: 100,
      currentMeter: 100,
      outcome: 'completion',
      depth: 'medium',
      meterFullAtStart: true
    });

    expect(result.awardedPoints).toBe(500);
    expect(result.nextScore).toBe(600);
  });

  it('resets full meter on non-endzone completion', () => {
    const result = resolveScoreAndMeter({
      currentScore: 100,
      currentMeter: 100,
      outcome: 'completion',
      depth: 'short',
      meterFullAtStart: true
    });

    expect(result.nextMeter).toBe(0);
  });

  it('keeps full meter on endzone completion while full', () => {
    const result = resolveScoreAndMeter({
      currentScore: 100,
      currentMeter: 100,
      outcome: 'completion',
      depth: 'endzone',
      meterFullAtStart: true
    });

    expect(result.nextMeter).toBe(100);
    expect(result.awardedPoints).toBe(1000);
  });

  it('resets full meter on incompletion/deflection', () => {
    const incompletion = resolveScoreAndMeter({
      currentScore: 100,
      currentMeter: 100,
      outcome: 'incompletion',
      depth: 'short',
      meterFullAtStart: true
    });
    const deflection = resolveScoreAndMeter({
      currentScore: 100,
      currentMeter: 100,
      outcome: 'deflected',
      depth: 'endzone',
      meterFullAtStart: true
    });

    expect(incompletion.nextMeter).toBe(0);
    expect(deflection.nextMeter).toBe(0);
    expect(incompletion.awardedPoints).toBe(0);
    expect(deflection.awardedPoints).toBe(0);
  });
});

import { METER_GAIN_BY_DEPTH, SCORE_BY_DEPTH } from './config';
import { clamp } from './physics';
import type { ScoreResolution, ScoreResolutionInput } from './types';

export function resolveScoreAndMeter(input: ScoreResolutionInput): ScoreResolution {
  const { currentScore, currentMeter, outcome, depth, meterFullAtStart } = input;

  const basePoints = outcome === 'completion' ? SCORE_BY_DEPTH[depth] : 0;
  const multiplier = meterFullAtStart ? 2 : 1;
  const awardedPoints = basePoints * multiplier;
  const nextScore = currentScore + awardedPoints;

  let nextMeter = currentMeter;

  if (meterFullAtStart) {
    nextMeter = outcome === 'completion' && depth === 'endzone' ? 100 : 0;
  } else if (outcome === 'completion') {
    if (depth === 'endzone') {
      nextMeter = 0;
    } else {
      nextMeter = clamp(currentMeter + METER_GAIN_BY_DEPTH[depth], 0, 100);
    }
  }

  return {
    nextScore,
    nextMeter,
    awardedPoints
  };
}

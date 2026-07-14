import { SCORE_CONFIG } from '../config/scoringConfig';
import type { LaneId } from '../config/gameplayConfig';
import type { GameState, PassOutcome, PlayScoreResult } from '../state/GameState';

export interface ScoreState {
  score: number;
  tdMeter: number;
  touchdownStreak: number;
}

export const calculatePlayScore = (
  state: ScoreState,
  outcome: PassOutcome,
  laneId: LaneId | null,
): PlayScoreResult => {
  const lane = laneId ? SCORE_CONFIG.lanes[laneId] : null;
  const tdBonusWasActive = state.tdMeter >= SCORE_CONFIG.tdMeterMaximum;
  const isSuccessful = outcome === 'completion' || outcome === 'touchdown';
  const isTouchdown = outcome === 'touchdown';
  const baseCompletionPoints = isSuccessful ? (lane?.completionPoints ?? 0) : 0;
  const tdBonusPoints = isTouchdown && tdBonusWasActive ? SCORE_CONFIG.tdBonusPoints : 0;
  const touchdownMultiplier = isTouchdown
    ? (SCORE_CONFIG.touchdownMultipliers[
        Math.min(state.touchdownStreak, SCORE_CONFIG.touchdownMultipliers.length - 1)
      ] ?? 1)
    : 1;
  const awardedPoints = Math.round(
    isTouchdown
      ? (baseCompletionPoints + tdBonusPoints) * touchdownMultiplier
      : baseCompletionPoints,
  );
  const tdMeterAfter = isSuccessful
    ? Math.min(SCORE_CONFIG.tdMeterMaximum, state.tdMeter + (lane?.tdMeterGain ?? 0))
    : 0;
  const touchdownStreakAfter = isTouchdown ? state.touchdownStreak + 1 : 0;

  return Object.freeze({
    outcome,
    laneId,
    baseCompletionPoints,
    tdBonusWasActive,
    tdBonusPoints,
    touchdownMultiplier,
    awardedPoints,
    totalScoreBefore: state.score,
    totalScoreAfter: state.score + awardedPoints,
    tdMeterBefore: state.tdMeter,
    tdMeterAfter,
    touchdownStreakBefore: state.touchdownStreak,
    touchdownStreakAfter,
  });
};

export const applyPlayScore = (state: GameState, result: PlayScoreResult): void => {
  state.score = result.totalScoreAfter;
  state.tdMeter = result.tdMeterAfter;
  state.touchdownStreak = result.touchdownStreakAfter;
  state.lastPlayScore = result;
  state.stats.attempts += 1;
  if (result.outcome === 'completion') state.stats.completions += 1;
  if (result.outcome === 'touchdown') state.stats.touchdowns += 1;
  if (result.outcome === 'incompletion') state.stats.incompletions += 1;
  if (result.outcome === 'interception') state.stats.interceptions += 1;
  state.stats.longestTouchdownStreak = Math.max(
    state.stats.longestTouchdownStreak,
    result.touchdownStreakAfter,
  );
};

import { getLaneConfig, type LaneId } from '../config/gameplayConfig';
import type { FeedbackState, GameState, PassOutcome } from '../state/GameState';
import { applyPlayScore, calculatePlayScore } from './scoring';

const formatPoints = (points: number): string => `+${points.toLocaleString('en-US')}`;

const createFeedback = (
  outcome: PassOutcome,
  laneId: LaneId | null,
  awardedPoints: number,
  tdBonusActive: boolean,
  multiplier: number,
): FeedbackState => {
  if (outcome === 'interception') {
    return { tone: 'negative', headline: 'INTERCEPTED', detail: 'BONUS LOST', remainingMs: 920 };
  }
  if (outcome === 'incompletion') {
    return { tone: 'negative', headline: 'INCOMPLETE', detail: 'BONUS LOST', remainingMs: 920 };
  }
  if (outcome === 'touchdown') {
    const detail = [tdBonusActive ? 'TD BONUS' : '', multiplier > 1 ? `STREAK x${multiplier}` : '']
      .filter(Boolean)
      .join(' · ');
    return {
      tone: 'touchdown',
      headline: `TOUCHDOWN ${formatPoints(awardedPoints)}`,
      detail,
      remainingMs: 1_050,
    };
  }
  const label = laneId ? getLaneConfig(laneId).id.toUpperCase() : 'COMPLETE';
  return {
    tone: 'positive',
    headline: `${label} COMPLETE ${formatPoints(awardedPoints)}`,
    detail: '',
    remainingMs: 760,
  };
};

export const resolvePass = (
  state: GameState,
  outcome: PassOutcome,
  laneId: LaneId | null,
): void => {
  const result = calculatePlayScore(state, outcome, laneId);
  applyPlayScore(state, result);
  state.feedback = createFeedback(
    outcome,
    laneId,
    result.awardedPoints,
    result.tdBonusWasActive,
    result.touchdownMultiplier,
  );
  state.ball = null;
  state.playCooldownMs = outcome === 'touchdown' ? 420 : 250;
};

import { SCORE_CONFIG } from '../config/scoringConfig';
import type { GameState } from './GameState';

export const selectTdBonusActive = (state: GameState): boolean =>
  state.tdMeter >= SCORE_CONFIG.tdMeterMaximum;

export const selectTouchdownMultiplier = (state: GameState): number =>
  SCORE_CONFIG.touchdownMultipliers[
    Math.min(state.touchdownStreak, SCORE_CONFIG.touchdownMultipliers.length - 1)
  ] ?? 1;

export const selectAccuracy = (state: GameState): number =>
  state.stats.attempts === 0
    ? 0
    : Math.round(((state.stats.completions + state.stats.touchdowns) / state.stats.attempts) * 100);

export const selectCanThrow = (state: GameState): boolean =>
  state.phase === 'playing' &&
  state.remainingMs > 0 &&
  state.ball === null &&
  state.playCooldownMs <= 0;

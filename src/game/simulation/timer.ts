import { FINAL_BALL_GRACE_MS } from '../config/gameplayConfig';
import type { GameState } from '../state/GameState';

export const updateGameplayTimer = (state: GameState, deltaMs: number): boolean => {
  if (state.phase !== 'playing') return false;
  const before = state.remainingMs;
  const consumedMs = Math.min(before, Math.max(0, deltaMs));
  state.remainingMs = Math.max(0, before - consumedMs);
  state.elapsedGameplayMs += consumedMs;
  if (before > 0 && state.remainingMs === 0) {
    state.phase = 'resolving-final-ball';
    state.finalBallGraceRemainingMs = FINAL_BALL_GRACE_MS;
    return true;
  }
  return false;
};

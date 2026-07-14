import { GAMEPLAY_CONFIG, type LaneId } from '../config/gameplayConfig';
import type { GameState, PassOutcome } from '../state/GameState';
import { findFirstBallCollision } from './collision';
import { resolvePass } from './resolvePass';
import { updateDefenders, updateReceivers } from './spawn';
import { advanceBall } from './trajectory';
import { updateGameplayTimer } from './timer';

export interface UpdateResult {
  timerExpired: boolean;
  passResolved: PassOutcome | null;
  laneId: LaneId | null;
  scoreChanged: boolean;
  runReadyToFinish: boolean;
}

const noResult = (): UpdateResult => ({
  timerExpired: false,
  passResolved: null,
  laneId: null,
  scoreChanged: false,
  runReadyToFinish: false,
});

const updateAttractMode = (state: GameState, deltaMs: number): void => {
  for (const receiver of state.receivers) {
    receiver.x += receiver.direction * receiver.speedPerMs * deltaMs;
    receiver.animationMs += deltaMs;
    if (Math.abs(receiver.x) > GAMEPLAY_CONFIG.receiverDespawnX) {
      receiver.x =
        receiver.direction === 1
          ? -GAMEPLAY_CONFIG.receiverOffscreenX
          : GAMEPLAY_CONFIG.receiverOffscreenX;
    }
  }
  updateDefenders(state, deltaMs);
};

export const updateGame = (state: GameState, deltaMs: number): UpdateResult => {
  const result = noResult();
  if (state.debug.frozen) return result;
  const scaledDelta = deltaMs * state.debug.slowMotion;

  if (state.phase === 'countdown') {
    state.countdownRemainingMs = Math.max(0, state.countdownRemainingMs - scaledDelta);
    return result;
  }

  if (state.phase === 'title') {
    updateAttractMode(state, scaledDelta);
    return result;
  }

  const simulationActive = state.phase === 'playing' || state.phase === 'resolving-final-ball';
  if (!simulationActive) return result;

  if (state.phase === 'playing') result.timerExpired = updateGameplayTimer(state, scaledDelta);
  updateReceivers(state, scaledDelta);
  updateDefenders(state, scaledDelta);
  state.playCooldownMs = Math.max(0, state.playCooldownMs - scaledDelta);
  if (state.feedback) {
    state.feedback.remainingMs -= scaledDelta;
    if (state.feedback.remainingMs <= 0) state.feedback = null;
  }

  if (state.ball) {
    advanceBall(state.ball, scaledDelta);
    const collision = findFirstBallCollision(state.ball, state.receivers, state.defenders);
    let outcome: PassOutcome | null = null;
    let laneId: LaneId | null = null;

    if (state.debug.forcedOutcome) {
      outcome = state.debug.forcedOutcome;
      laneId = outcome === 'touchdown' ? 'touchdown' : outcome === 'completion' ? 'medium' : null;
      state.debug.forcedOutcome = null;
    } else if (collision?.type === 'receiver') {
      state.debug.lastCollisionPoint = collision.point;
      state.debug.lastCollisionKind = 'receiver';
      laneId = collision.laneId;
      outcome = laneId === 'touchdown' ? 'touchdown' : 'completion';
      if (collision.receiver) {
        collision.receiver.pose = outcome === 'touchdown' ? 'celebrate' : 'catch';
        collision.receiver.animationMs = 0;
      }
    } else if (collision?.type === 'defender') {
      state.debug.lastCollisionPoint = collision.point;
      state.debug.lastCollisionKind = 'defender';
      outcome = 'interception';
      if (collision.defender) {
        collision.defender.pose = 'intercept';
        collision.defender.animationMs = 0;
      }
    } else if (
      state.ball.elapsedMs >= state.ball.durationMs ||
      Math.abs(state.ball.current.x) > 1.3 ||
      state.ball.current.depth > 1.06
    ) {
      outcome = 'incompletion';
    }

    if (outcome) {
      const scoreBefore = state.score;
      resolvePass(state, outcome, laneId);
      result.passResolved = outcome;
      result.laneId = laneId;
      result.scoreChanged = state.score !== scoreBefore;
    }
  }

  if (state.phase === 'resolving-final-ball') {
    state.finalBallGraceRemainingMs = Math.max(0, state.finalBallGraceRemainingMs - scaledDelta);
    result.runReadyToFinish = state.ball === null || state.finalBallGraceRemainingMs <= 0;
    if (state.finalBallGraceRemainingMs <= 0) state.ball = null;
  }
  return result;
};

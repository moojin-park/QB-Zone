import {
  FINAL_BALL_GRACE_MS,
  GAMEPLAY_CONFIG,
  PASSING_LANES,
  SESSION_DURATION_MS,
  getDefenderPatrolSpeedPerMs,
  type LaneId,
} from '../config/gameplayConfig';
import type { DefenderState, GameSettings, GameState, ReceiverState } from './GameState';

export const DEFAULT_SETTINGS: GameSettings = {
  masterMuted: false,
  musicVolume: 0.38,
  sfxVolume: 0.72,
  reducedMotion: false,
  highContrastAim: false,
  viewMode: 'auto',
  tutorialComplete: false,
};

const createReceiver = (
  id: number,
  laneId: LaneId,
  direction: -1 | 1,
  offset: number,
): ReceiverState => {
  const lane = PASSING_LANES.find((candidate) => candidate.id === laneId)!;
  return {
    id,
    laneId,
    direction,
    x:
      direction === 1
        ? -GAMEPLAY_CONFIG.receiverOffscreenX + offset
        : GAMEPLAY_CONFIG.receiverOffscreenX - offset,
    speedPerMs: (2 * GAMEPLAY_CONFIG.receiverOffscreenX) / (lane.receiverCrossingSeconds * 1_000),
    animationMs: offset * 900,
    pose: 'run',
    hasCaught: false,
  };
};

const createDefender = (id: number, index: number): DefenderState => {
  const direction = (index % 2 === 0 ? 1 : -1) as -1 | 1;
  return {
    id,
    depth: GAMEPLAY_CONFIG.defenderDepths[index] ?? 0.58,
    direction,
    x:
      direction === 1
        ? -GAMEPLAY_CONFIG.defenderPatrolHalfWidth + index * 0.2
        : GAMEPLAY_CONFIG.defenderPatrolHalfWidth - index * 0.15,
    speedPerMs: getDefenderPatrolSpeedPerMs(index),
    animationMs: index * 260,
    pose: 'run',
  };
};

export const createInitialState = (
  settings: GameSettings = DEFAULT_SETTINGS,
  seed: number = GAMEPLAY_CONFIG.defaultSeed,
): GameState => {
  const receivers = PASSING_LANES.map((lane, index) =>
    createReceiver(index + 1, lane.id, (index % 2 === 0 ? 1 : -1) as -1 | 1, index * 0.24),
  );
  const defenders = [0, 1, 2].map((index) => createDefender(receivers.length + index + 1, index));

  return {
    phase: 'loading',
    phaseBeforePause: null,
    countdownRemainingMs: 3_000,
    remainingMs: SESSION_DURATION_MS,
    elapsedGameplayMs: 0,
    finalBallGraceRemainingMs: FINAL_BALL_GRACE_MS,
    score: 0,
    tdMeter: 0,
    touchdownStreak: 0,
    receivers,
    defenders,
    ball: null,
    nextEntityId: receivers.length + defenders.length + 1,
    laneSpawnTimers: { short: 0, medium: 0, deep: 0, touchdown: 0 },
    playCooldownMs: 0,
    feedback: null,
    lastPlayScore: null,
    stats: {
      attempts: 0,
      completions: 0,
      touchdowns: 0,
      incompletions: 0,
      interceptions: 0,
      longestTouchdownStreak: 0,
      rewardedContinueUsed: false,
    },
    continueUses: 0,
    adPreparationStarted: false,
    randomState: seed || GAMEPLAY_CONFIG.defaultSeed,
    settings: { ...settings },
    debug: {
      enabled: false,
      showTrajectory: false,
      showCatchZones: false,
      showDefenderHitZones: false,
      slowMotion: 1,
      frozen: false,
      forcedOutcome: null,
      lastCollisionPoint: null,
      lastCollisionKind: null,
    },
  };
};

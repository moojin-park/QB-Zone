export const SESSION_DURATION_MS = 60_000;
export const REWARDED_CONTINUE_SECONDS = 15;
export const MAX_REWARDED_CONTINUES_PER_RUN = 1;
export const FIXED_STEP_MS = 1000 / 60;
export const MAX_FRAME_DELTA_MS = 100;
export const FINAL_BALL_GRACE_MS = 2_000;
export const DEFAULT_BALL_RADIUS_PX = 12;

export type LaneId = 'short' | 'medium' | 'deep' | 'touchdown';

export interface PassingLaneConfig {
  id: LaneId;
  yardLineLabel: string;
  normalizedDepth: number;
  completionPoints: number;
  tdMeterGain: number;
  receiverCrossingSeconds: number;
  spawnWeight: number;
  maximumConcurrentReceivers: number;
  catchWidth: number;
}

export interface GameplayConfig {
  logicalHeight: number;
  classicLogicalWidth: number;
  wideLogicalWidth: number;
  quarterbackStart: { x: number; depth: number; height: number };
  receiverOffscreenX: number;
  receiverDespawnX: number;
  receiverSpawnDelayMs: { min: number; max: number };
  defenderPatrolHalfWidth: number;
  defenderCrossingSeconds: number[];
  defenderDepths: number[];
  defenderWidthWorld: number;
  ballRadiusPx: number;
  playResolutionCooldownMs: number;
  feedbackDurationMs: number;
  timerWarningMs: number;
  adPrepareAtRemainingMs: number;
  defaultSeed: number;
  throw: {
    minimumGestureDistancePx: number;
    slowSpeedPxPerMs: number;
    fastSpeedPxPerMs: number;
    minimumDurationMs: number;
    maximumDurationMs: number;
    minimumArcHeight: number;
    maximumArcHeight: number;
    catchProgress: number;
  };
}

export const PASSING_LANES: readonly PassingLaneConfig[] = [
  {
    id: 'short',
    yardLineLabel: '15',
    normalizedDepth: 0.28,
    completionPoints: 500,
    tdMeterGain: 1,
    receiverCrossingSeconds: 4.4,
    spawnWeight: 1,
    maximumConcurrentReceivers: 1,
    catchWidth: 0.17,
  },
  {
    id: 'medium',
    yardLineLabel: '30',
    normalizedDepth: 0.48,
    completionPoints: 1_000,
    tdMeterGain: 2,
    receiverCrossingSeconds: 5,
    spawnWeight: 1,
    maximumConcurrentReceivers: 1,
    catchWidth: 0.15,
  },
  {
    id: 'deep',
    yardLineLabel: '45',
    normalizedDepth: 0.68,
    completionPoints: 1_500,
    tdMeterGain: 3,
    receiverCrossingSeconds: 5.7,
    spawnWeight: 0.9,
    maximumConcurrentReceivers: 1,
    catchWidth: 0.14,
  },
  {
    id: 'touchdown',
    yardLineLabel: 'END ZONE',
    normalizedDepth: 0.87,
    completionPoints: 2_500,
    tdMeterGain: 4,
    receiverCrossingSeconds: 6.3,
    spawnWeight: 0.7,
    maximumConcurrentReceivers: 1,
    catchWidth: 0.13,
  },
] as const;

// Deliberately mutable in development. runtimeTuning.ts is the only supported
// writer and clamps every value before updating this authoritative config.
export const GAMEPLAY_CONFIG: GameplayConfig = {
  logicalHeight: 768,
  classicLogicalWidth: 1024,
  wideLogicalWidth: 1366,
  quarterbackStart: { x: 0, depth: 0.035, height: 0.56 },
  receiverOffscreenX: 1.22,
  receiverDespawnX: 1.34,
  receiverSpawnDelayMs: { min: 180, max: 620 },
  defenderPatrolHalfWidth: 0.78,
  defenderCrossingSeconds: [4.7, 5.8, 6.8],
  defenderDepths: [0.39, 0.58, 0.73],
  defenderWidthWorld: 0.22,
  ballRadiusPx: DEFAULT_BALL_RADIUS_PX,
  playResolutionCooldownMs: 260,
  feedbackDurationMs: 920,
  timerWarningMs: 10_000,
  adPrepareAtRemainingMs: 10_000,
  defaultSeed: 0x50c4e7,
  throw: {
    minimumGestureDistancePx: 34,
    slowSpeedPxPerMs: 0.25,
    fastSpeedPxPerMs: 1.8,
    minimumDurationMs: 430,
    maximumDurationMs: 1_180,
    minimumArcHeight: 0.28,
    maximumArcHeight: 1.05,
    catchProgress: 0.82,
  },
};

export const getLaneConfig = (laneId: LaneId): PassingLaneConfig => {
  const lane = PASSING_LANES.find((candidate) => candidate.id === laneId);
  if (!lane) throw new Error(`Unknown lane: ${laneId}`);
  return lane;
};

export const getDefenderPatrolSpeedPerMs = (index: number): number => {
  const crossingSeconds = GAMEPLAY_CONFIG.defenderCrossingSeconds[index] ?? 5.8;
  return (2 * GAMEPLAY_CONFIG.defenderPatrolHalfWidth) / (crossingSeconds * 1_000);
};

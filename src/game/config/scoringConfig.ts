export interface LaneScoreConfig {
  completionPoints: number;
  tdMeterGain: number;
}

export interface ScoreConfig {
  lanes: {
    short: LaneScoreConfig;
    medium: LaneScoreConfig;
    deep: LaneScoreConfig;
    touchdown: LaneScoreConfig;
  };
  tdMeterMaximum: number;
  tdBonusPoints: number;
  touchdownMultipliers: number[];
  incompletionPoints: number;
  interceptionPoints: number;
}

// Deliberately mutable in development. runtimeTuning.ts owns validated writes.
export const SCORE_CONFIG: ScoreConfig = {
  lanes: {
    short: { completionPoints: 500, tdMeterGain: 1 },
    medium: { completionPoints: 1_000, tdMeterGain: 2 },
    deep: { completionPoints: 1_500, tdMeterGain: 3 },
    touchdown: { completionPoints: 2_500, tdMeterGain: 4 },
  },
  tdMeterMaximum: 12,
  tdBonusPoints: 3_000,
  touchdownMultipliers: [1, 1.25, 1.5, 2, 2.5, 3],
  incompletionPoints: 0,
  interceptionPoints: 0,
};

export const MAXIMUM_SUPPORTED_RUN_MS = 75_000;

// A conservative platform cap based on a theoretical touchdown every 430 ms at 3x
// after the streak ramps. Real play cadence is substantially slower.
export const PLAUSIBLE_MAXIMUM_SCORE = 3_000_000;
export const PLAUSIBLE_MAXIMUM_SCORE_PER_SECOND = 45_000;

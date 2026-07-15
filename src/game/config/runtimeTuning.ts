import {
  GAMEPLAY_CONFIG,
  PASSING_LANES,
  REWARDED_CONTINUE_SECONDS,
  SESSION_DURATION_MS,
  type LaneId,
} from './gameplayConfig';
import { SCORE_CONFIG } from './scoringConfig';

export interface RuntimeTuningControl {
  id: string;
  label: string;
  min: number;
  max: number;
  step: number;
  unit: string;
}

export interface RuntimeTuningGroup {
  id: string;
  label: string;
  controls: readonly RuntimeTuningControl[];
}

interface InternalTuningControl extends RuntimeTuningControl {
  defaultValue: number;
  read(): number;
  write(value: number): void;
}

interface LaneDefaults {
  id: LaneId;
  normalizedDepth: number;
  completionPoints: number;
  tdMeterGain: number;
  receiverCrossingSeconds: number;
  catchWidth: number;
}

const MIN_LANE_GAP = 0.04;
const MIN_DEFENDER_GAP = 0.04;
const MIN_RANGE_GAP = 0.01;

const laneDefaults: readonly LaneDefaults[] = PASSING_LANES.map((lane) => ({
  id: lane.id,
  normalizedDepth: lane.normalizedDepth,
  completionPoints: lane.completionPoints,
  tdMeterGain: lane.tdMeterGain,
  receiverCrossingSeconds: lane.receiverCrossingSeconds,
  catchWidth: lane.catchWidth,
}));
const defenderCrossingDefaults = [...GAMEPLAY_CONFIG.defenderCrossingSeconds];
const defenderDepthDefaults = [...GAMEPLAY_CONFIG.defenderDepths];
const receiverSpawnDefaults = { ...GAMEPLAY_CONFIG.receiverSpawnDelayMs };
const throwDefaults = { ...GAMEPLAY_CONFIG.throw };
const defenderWidthDefault = GAMEPLAY_CONFIG.defenderWidthWorld;
const ballRadiusDefault = GAMEPLAY_CONFIG.ballRadiusPx;
const scoreDefaults = {
  lanes: {
    short: { ...SCORE_CONFIG.lanes.short },
    medium: { ...SCORE_CONFIG.lanes.medium },
    deep: { ...SCORE_CONFIG.lanes.deep },
    touchdown: { ...SCORE_CONFIG.lanes.touchdown },
  },
  tdMeterMaximum: SCORE_CONFIG.tdMeterMaximum,
  tdBonusPoints: SCORE_CONFIG.tdBonusPoints,
  touchdownMultipliers: [...SCORE_CONFIG.touchdownMultipliers],
};

let sessionDurationMs = SESSION_DURATION_MS;
let continueDurationMs = REWARDED_CONTINUE_SECONDS * 1_000;
const overriddenControlIds = new Set<string>();

const clamp = (value: number, min: number, max: number): number =>
  Math.max(min, Math.min(max, value));

const roundToStep = (value: number, step: number): number => {
  const rounded = Math.round(value / step) * step;
  return Number(rounded.toFixed(6));
};

const control = (
  metadata: RuntimeTuningControl,
  read: () => number,
  write: (value: number) => void,
): InternalTuningControl => ({
  ...metadata,
  defaultValue: read(),
  read,
  write,
});

const timingControls: InternalTuningControl[] = [
  control(
    { id: 'session-duration', label: 'Session duration', min: 10, max: 300, step: 1, unit: 's' },
    () => sessionDurationMs / 1_000,
    (value) => {
      sessionDurationMs = value * 1_000;
    },
  ),
  control(
    { id: 'continue-duration', label: 'Continue duration', min: 5, max: 60, step: 1, unit: 's' },
    () => continueDurationMs / 1_000,
    (value) => {
      continueDurationMs = value * 1_000;
    },
  ),
];

const laneControls: InternalTuningControl[] = [
  control(
    {
      id: 'receiver-spawn-min',
      label: 'Spawn delay min',
      min: 50,
      max: 3_000,
      step: 10,
      unit: 'ms',
    },
    () => GAMEPLAY_CONFIG.receiverSpawnDelayMs.min,
    (value) => {
      GAMEPLAY_CONFIG.receiverSpawnDelayMs.min = Math.min(
        value,
        GAMEPLAY_CONFIG.receiverSpawnDelayMs.max - 10,
      );
    },
  ),
  control(
    {
      id: 'receiver-spawn-max',
      label: 'Spawn delay max',
      min: 60,
      max: 3_500,
      step: 10,
      unit: 'ms',
    },
    () => GAMEPLAY_CONFIG.receiverSpawnDelayMs.max,
    (value) => {
      GAMEPLAY_CONFIG.receiverSpawnDelayMs.max = Math.max(
        value,
        GAMEPLAY_CONFIG.receiverSpawnDelayMs.min + 10,
      );
    },
  ),
  ...PASSING_LANES.flatMap((lane, index): InternalTuningControl[] => [
    control(
      {
        id: `lane-${lane.id}-depth`,
        label: `${lane.id} lane depth`,
        min: 0.12,
        max: 0.96,
        step: 0.01,
        unit: '',
      },
      () => lane.normalizedDepth,
      (value) => {
        const previous = PASSING_LANES[index - 1];
        const next = PASSING_LANES[index + 1];
        const minimum = previous ? previous.normalizedDepth + MIN_LANE_GAP : 0.12;
        const maximum = next ? next.normalizedDepth - MIN_LANE_GAP : 0.96;
        lane.normalizedDepth = clamp(value, minimum, maximum);
      },
    ),
    control(
      {
        id: `lane-${lane.id}-receiver-crossing`,
        label: `${lane.id} crossing`,
        min: 1.5,
        max: 12,
        step: 0.1,
        unit: 's',
      },
      () => lane.receiverCrossingSeconds,
      (value) => {
        lane.receiverCrossingSeconds = value;
      },
    ),
    control(
      {
        id: `lane-${lane.id}-catch-width`,
        label: `${lane.id} catch width`,
        min: 0.04,
        max: 0.4,
        step: 0.01,
        unit: '',
      },
      () => lane.catchWidth,
      (value) => {
        lane.catchWidth = value;
      },
    ),
  ]),
];

const defenderControls: InternalTuningControl[] = [
  ...GAMEPLAY_CONFIG.defenderCrossingSeconds.flatMap((_, index): InternalTuningControl[] => [
    control(
      {
        id: `defender-${index + 1}-crossing`,
        label: `Defender ${index + 1} crossing`,
        min: 1.5,
        max: 12,
        step: 0.1,
        unit: 's',
      },
      () =>
        GAMEPLAY_CONFIG.defenderCrossingSeconds[index] ?? defenderCrossingDefaults[index] ?? 5.8,
      (value) => {
        GAMEPLAY_CONFIG.defenderCrossingSeconds[index] = value;
      },
    ),
    control(
      {
        id: `defender-${index + 1}-depth`,
        label: `Defender ${index + 1} depth`,
        min: 0.14,
        max: 0.94,
        step: 0.01,
        unit: '',
      },
      () => GAMEPLAY_CONFIG.defenderDepths[index] ?? defenderDepthDefaults[index] ?? 0.58,
      (value) => {
        const previous = GAMEPLAY_CONFIG.defenderDepths[index - 1];
        const next = GAMEPLAY_CONFIG.defenderDepths[index + 1];
        const minimum = previous === undefined ? 0.14 : previous + MIN_DEFENDER_GAP;
        const maximum = next === undefined ? 0.94 : next - MIN_DEFENDER_GAP;
        GAMEPLAY_CONFIG.defenderDepths[index] = clamp(value, minimum, maximum);
      },
    ),
  ]),
  control(
    {
      id: 'defender-hit-zone-scale',
      label: 'Hit-zone width',
      min: 0.1,
      max: 0.42,
      step: 0.01,
      unit: '',
    },
    () => GAMEPLAY_CONFIG.defenderWidthWorld,
    (value) => {
      GAMEPLAY_CONFIG.defenderWidthWorld = value;
    },
  ),
];

const throwControls: InternalTuningControl[] = [
  control(
    { id: 'ball-radius', label: 'Ball radius', min: 4, max: 28, step: 1, unit: 'px' },
    () => GAMEPLAY_CONFIG.ballRadiusPx,
    (value) => {
      GAMEPLAY_CONFIG.ballRadiusPx = value;
    },
  ),
  control(
    {
      id: 'throw-slow-speed',
      label: 'Slow release threshold',
      min: 0.05,
      max: 2,
      step: 0.05,
      unit: 'px/ms',
    },
    () => GAMEPLAY_CONFIG.throw.slowSpeedPxPerMs,
    (value) => {
      GAMEPLAY_CONFIG.throw.slowSpeedPxPerMs = Math.min(
        value,
        GAMEPLAY_CONFIG.throw.fastSpeedPxPerMs - 0.05,
      );
    },
  ),
  control(
    {
      id: 'throw-fast-speed',
      label: 'Fast release threshold',
      min: 0.1,
      max: 4,
      step: 0.05,
      unit: 'px/ms',
    },
    () => GAMEPLAY_CONFIG.throw.fastSpeedPxPerMs,
    (value) => {
      GAMEPLAY_CONFIG.throw.fastSpeedPxPerMs = Math.max(
        value,
        GAMEPLAY_CONFIG.throw.slowSpeedPxPerMs + 0.05,
      );
    },
  ),
  control(
    {
      id: 'throw-min-duration',
      label: 'Fast throw duration',
      min: 150,
      max: 1_500,
      step: 10,
      unit: 'ms',
    },
    () => GAMEPLAY_CONFIG.throw.minimumDurationMs,
    (value) => {
      GAMEPLAY_CONFIG.throw.minimumDurationMs = Math.min(
        value,
        GAMEPLAY_CONFIG.throw.maximumDurationMs - 50,
      );
    },
  ),
  control(
    {
      id: 'throw-max-duration',
      label: 'Slow throw duration',
      min: 250,
      max: 2_500,
      step: 10,
      unit: 'ms',
    },
    () => GAMEPLAY_CONFIG.throw.maximumDurationMs,
    (value) => {
      GAMEPLAY_CONFIG.throw.maximumDurationMs = Math.max(
        value,
        GAMEPLAY_CONFIG.throw.minimumDurationMs + 50,
      );
    },
  ),
  control(
    { id: 'arc-min-height', label: 'Fast throw arc', min: 0.05, max: 1.5, step: 0.01, unit: '' },
    () => GAMEPLAY_CONFIG.throw.minimumArcHeight,
    (value) => {
      GAMEPLAY_CONFIG.throw.minimumArcHeight = Math.min(
        value,
        GAMEPLAY_CONFIG.throw.maximumArcHeight - MIN_RANGE_GAP,
      );
    },
  ),
  control(
    { id: 'arc-max-height', label: 'Slow throw arc', min: 0.1, max: 2.5, step: 0.01, unit: '' },
    () => GAMEPLAY_CONFIG.throw.maximumArcHeight,
    (value) => {
      GAMEPLAY_CONFIG.throw.maximumArcHeight = Math.max(
        value,
        GAMEPLAY_CONFIG.throw.minimumArcHeight + MIN_RANGE_GAP,
      );
    },
  ),
];

const scoreControls: InternalTuningControl[] = [
  ...PASSING_LANES.flatMap((lane): InternalTuningControl[] => [
    control(
      {
        id: `score-${lane.id}`,
        label: `${lane.id} completion`,
        min: 0,
        max: 20_000,
        step: 100,
        unit: 'pts',
      },
      () => SCORE_CONFIG.lanes[lane.id].completionPoints,
      (value) => {
        SCORE_CONFIG.lanes[lane.id].completionPoints = value;
        lane.completionPoints = value;
      },
    ),
    control(
      {
        id: `meter-gain-${lane.id}`,
        label: `${lane.id} meter gain`,
        min: 0,
        max: 100,
        step: 1,
        unit: '',
      },
      () => SCORE_CONFIG.lanes[lane.id].tdMeterGain,
      (value) => {
        SCORE_CONFIG.lanes[lane.id].tdMeterGain = value;
        lane.tdMeterGain = value;
      },
    ),
  ]),
  control(
    { id: 'meter-maximum', label: 'TD meter maximum', min: 1, max: 100, step: 1, unit: '' },
    () => SCORE_CONFIG.tdMeterMaximum,
    (value) => {
      SCORE_CONFIG.tdMeterMaximum = value;
    },
  ),
  control(
    { id: 'td-bonus-points', label: 'TD bonus', min: 0, max: 50_000, step: 100, unit: 'pts' },
    () => SCORE_CONFIG.tdBonusPoints,
    (value) => {
      SCORE_CONFIG.tdBonusPoints = value;
    },
  ),
  ...SCORE_CONFIG.touchdownMultipliers.map((_, index): InternalTuningControl =>
    control(
      {
        id: `multiplier-${index + 1}`,
        label: `TD streak ${index + 1}`,
        min: 1,
        max: 10,
        step: 0.25,
        unit: 'x',
      },
      () => SCORE_CONFIG.touchdownMultipliers[index] ?? 1,
      (value) => {
        const previous = SCORE_CONFIG.touchdownMultipliers[index - 1] ?? 1;
        const next = SCORE_CONFIG.touchdownMultipliers[index + 1] ?? 10;
        SCORE_CONFIG.touchdownMultipliers[index] = clamp(value, previous, next);
      },
    ),
  ),
];

const internalGroups: readonly {
  id: string;
  label: string;
  controls: readonly InternalTuningControl[];
}[] = [
  { id: 'timing', label: 'Timing', controls: timingControls },
  { id: 'lanes', label: 'Lanes & receivers', controls: laneControls },
  { id: 'defenders', label: 'Defenders', controls: defenderControls },
  { id: 'throw', label: 'Ball & throw curves', controls: throwControls },
  { id: 'score', label: 'Scoring & multiplier', controls: scoreControls },
];

const internalControls = internalGroups.flatMap((group) => group.controls);
const internalControlById = new Map(internalControls.map((entry) => [entry.id, entry]));

export const RUNTIME_TUNING_GROUPS: readonly RuntimeTuningGroup[] = internalGroups.map((group) => ({
  id: group.id,
  label: group.label,
  controls: group.controls.map(({ id, label, min, max, step, unit }) => ({
    id,
    label,
    min,
    max,
    step,
    unit,
  })),
}));

const refreshOverrideState = (): void => {
  overriddenControlIds.clear();
  for (const entry of internalControls) {
    if (Math.abs(entry.read() - entry.defaultValue) > 0.000_001) {
      overriddenControlIds.add(entry.id);
    }
  }
};

export const setRuntimeTuningValue = (id: string, rawValue: number): boolean => {
  const entry = internalControlById.get(id);
  if (!entry || !Number.isFinite(rawValue)) return false;
  entry.write(roundToStep(clamp(rawValue, entry.min, entry.max), entry.step));
  refreshOverrideState();
  return true;
};

export const getRuntimeTuningValue = (id: string): number | null =>
  internalControlById.get(id)?.read() ?? null;

export const getRuntimeSessionDurationMs = (): number => sessionDurationMs;

export const getRuntimeContinueDurationMs = (): number => continueDurationMs;

export const isRuntimeTuningControlOverridden = (id: string): boolean =>
  overriddenControlIds.has(id);

export const resetRuntimeTuningToDefaults = (): void => {
  sessionDurationMs = SESSION_DURATION_MS;
  continueDurationMs = REWARDED_CONTINUE_SECONDS * 1_000;
  GAMEPLAY_CONFIG.receiverSpawnDelayMs.min = receiverSpawnDefaults.min;
  GAMEPLAY_CONFIG.receiverSpawnDelayMs.max = receiverSpawnDefaults.max;
  GAMEPLAY_CONFIG.defenderCrossingSeconds.splice(
    0,
    GAMEPLAY_CONFIG.defenderCrossingSeconds.length,
    ...defenderCrossingDefaults,
  );
  GAMEPLAY_CONFIG.defenderDepths.splice(
    0,
    GAMEPLAY_CONFIG.defenderDepths.length,
    ...defenderDepthDefaults,
  );
  GAMEPLAY_CONFIG.defenderWidthWorld = defenderWidthDefault;
  GAMEPLAY_CONFIG.ballRadiusPx = ballRadiusDefault;
  Object.assign(GAMEPLAY_CONFIG.throw, throwDefaults);

  for (const defaults of laneDefaults) {
    const lane = PASSING_LANES.find((candidate) => candidate.id === defaults.id);
    if (!lane) continue;
    lane.normalizedDepth = defaults.normalizedDepth;
    lane.completionPoints = defaults.completionPoints;
    lane.tdMeterGain = defaults.tdMeterGain;
    lane.receiverCrossingSeconds = defaults.receiverCrossingSeconds;
    lane.catchWidth = defaults.catchWidth;
    SCORE_CONFIG.lanes[defaults.id].completionPoints =
      scoreDefaults.lanes[defaults.id].completionPoints;
    SCORE_CONFIG.lanes[defaults.id].tdMeterGain = scoreDefaults.lanes[defaults.id].tdMeterGain;
  }

  SCORE_CONFIG.tdMeterMaximum = scoreDefaults.tdMeterMaximum;
  SCORE_CONFIG.tdBonusPoints = scoreDefaults.tdBonusPoints;
  SCORE_CONFIG.touchdownMultipliers.splice(
    0,
    SCORE_CONFIG.touchdownMultipliers.length,
    ...scoreDefaults.touchdownMultipliers,
  );
  overriddenControlIds.clear();
};

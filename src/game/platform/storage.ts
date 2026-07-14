export const PERSISTED_GAME_DATA_SCHEMA_VERSION = 1 as const;

export const DEFAULT_PERSISTENT_STORAGE_KEY = 'qb-arcade:persisted-game-data';

export interface PersistedGameSettings {
  muted: boolean;
  musicVolume: number;
  sfxVolume: number;
  reducedMotion: boolean;
}

export interface PersistedAggregateStats {
  runsCompleted: number;
  passesAttempted: number;
  passesCompleted: number;
  touchdowns: number;
  interceptions: number;
  totalScore: number;
}

export interface PersistedGameData {
  schemaVersion: typeof PERSISTED_GAME_DATA_SCHEMA_VERSION;
  settings: PersistedGameSettings;
  tutorialCompleted: boolean;
  personalBest: number;
  aggregateStats: PersistedAggregateStats;
}

export interface StorageLike {
  getItem(key: string): string | null;
  setItem(key: string, value: string): void;
}

interface LegacyPersistedGameData extends Record<string, unknown> {
  aggregateStats?: unknown;
  highScore?: unknown;
  muted?: unknown;
  personalBest?: unknown;
  schemaVersion?: unknown;
  settings?: unknown;
  stats?: unknown;
  tutorialComplete?: unknown;
  tutorialCompleted?: unknown;
}

export function createDefaultPersistedGameData(): PersistedGameData {
  return {
    schemaVersion: PERSISTED_GAME_DATA_SCHEMA_VERSION,
    settings: {
      muted: false,
      musicVolume: 0.72,
      sfxVolume: 0.9,
      reducedMotion: false,
    },
    tutorialCompleted: false,
    personalBest: 0,
    aggregateStats: {
      runsCompleted: 0,
      passesAttempted: 0,
      passesCompleted: 0,
      touchdowns: 0,
      interceptions: 0,
      totalScore: 0,
    },
  };
}

/**
 * Validates the current schema and migrates the small unversioned/version-zero
 * shape used by early prototypes. Future schemas are deliberately ignored.
 */
export function normalizePersistedGameData(value: unknown): PersistedGameData | null {
  if (!isRecord(value)) {
    return null;
  }

  if (value.schemaVersion === PERSISTED_GAME_DATA_SCHEMA_VERSION) {
    return validateCurrentSchema(value);
  }

  if (value.schemaVersion !== undefined && value.schemaVersion !== 0) {
    return null;
  }

  return migrateLegacySchema(value);
}

export function parsePersistedGameData(serialized: string): PersistedGameData | null {
  try {
    return normalizePersistedGameData(JSON.parse(serialized) as unknown);
  } catch {
    return null;
  }
}

export function serializePersistedGameData(data: PersistedGameData): string | null {
  const normalized = normalizePersistedGameData(data);
  return normalized === null ? null : JSON.stringify(normalized);
}

export function getBrowserStorage(): StorageLike | null {
  try {
    return typeof window === 'undefined' ? null : window.localStorage;
  } catch {
    return null;
  }
}

export function loadLocalPersistentData(
  storage: StorageLike | null,
  storageKey = DEFAULT_PERSISTENT_STORAGE_KEY,
): PersistedGameData | null {
  if (storage === null) {
    return null;
  }

  try {
    const serialized = storage.getItem(storageKey);
    return serialized === null ? null : parsePersistedGameData(serialized);
  } catch {
    return null;
  }
}

export function saveLocalPersistentData(
  storage: StorageLike | null,
  data: PersistedGameData,
  storageKey = DEFAULT_PERSISTENT_STORAGE_KEY,
): boolean {
  if (storage === null) {
    return false;
  }

  const serialized = serializePersistedGameData(data);
  if (serialized === null) {
    return false;
  }

  try {
    storage.setItem(storageKey, serialized);
    return true;
  } catch {
    return false;
  }
}

function validateCurrentSchema(value: Record<string, unknown>): PersistedGameData | null {
  const settings = validateSettings(value.settings);
  const aggregateStats = validateAggregateStats(value.aggregateStats);

  if (
    settings === null ||
    aggregateStats === null ||
    typeof value.tutorialCompleted !== 'boolean' ||
    !isNonNegativeSafeInteger(value.personalBest)
  ) {
    return null;
  }

  return {
    schemaVersion: PERSISTED_GAME_DATA_SCHEMA_VERSION,
    settings,
    tutorialCompleted: value.tutorialCompleted,
    personalBest: value.personalBest,
    aggregateStats,
  };
}

function migrateLegacySchema(value: LegacyPersistedGameData): PersistedGameData | null {
  const recognizedLegacyKeys = [
    'aggregateStats',
    'highScore',
    'muted',
    'personalBest',
    'settings',
    'stats',
    'tutorialComplete',
    'tutorialCompleted',
  ];

  if (!recognizedLegacyKeys.some((key) => Object.hasOwn(value, key))) {
    return null;
  }

  const defaults = createDefaultPersistedGameData();
  const settingsSource = isRecord(value.settings) ? value.settings : {};
  const statsSource = isRecord(value.aggregateStats)
    ? value.aggregateStats
    : isRecord(value.stats)
      ? value.stats
      : {};

  const muted = readOptionalBoolean(settingsSource.muted ?? value.muted, defaults.settings.muted);
  const musicVolume = readOptionalUnitNumber(
    settingsSource.musicVolume,
    defaults.settings.musicVolume,
  );
  const sfxVolume = readOptionalUnitNumber(settingsSource.sfxVolume, defaults.settings.sfxVolume);
  const reducedMotion = readOptionalBoolean(
    settingsSource.reducedMotion,
    defaults.settings.reducedMotion,
  );
  const tutorialCompleted = readOptionalBoolean(
    value.tutorialCompleted ?? value.tutorialComplete,
    defaults.tutorialCompleted,
  );
  const personalBest = readOptionalNonNegativeInteger(
    value.personalBest ?? value.highScore,
    defaults.personalBest,
  );
  const aggregateStats = migrateLegacyStats(statsSource, defaults.aggregateStats);

  if (
    muted === null ||
    musicVolume === null ||
    sfxVolume === null ||
    reducedMotion === null ||
    tutorialCompleted === null ||
    personalBest === null ||
    aggregateStats === null
  ) {
    return null;
  }

  return {
    schemaVersion: PERSISTED_GAME_DATA_SCHEMA_VERSION,
    settings: { muted, musicVolume, sfxVolume, reducedMotion },
    tutorialCompleted,
    personalBest,
    aggregateStats,
  };
}

function validateSettings(value: unknown): PersistedGameSettings | null {
  if (
    !isRecord(value) ||
    typeof value.muted !== 'boolean' ||
    !isUnitNumber(value.musicVolume) ||
    !isUnitNumber(value.sfxVolume) ||
    typeof value.reducedMotion !== 'boolean'
  ) {
    return null;
  }

  return {
    muted: value.muted,
    musicVolume: value.musicVolume,
    sfxVolume: value.sfxVolume,
    reducedMotion: value.reducedMotion,
  };
}

function validateAggregateStats(value: unknown): PersistedAggregateStats | null {
  if (!isRecord(value)) {
    return null;
  }

  const keys = [
    'runsCompleted',
    'passesAttempted',
    'passesCompleted',
    'touchdowns',
    'interceptions',
    'totalScore',
  ] as const;

  if (keys.some((key) => !isNonNegativeSafeInteger(value[key]))) {
    return null;
  }

  return {
    runsCompleted: value.runsCompleted as number,
    passesAttempted: value.passesAttempted as number,
    passesCompleted: value.passesCompleted as number,
    touchdowns: value.touchdowns as number,
    interceptions: value.interceptions as number,
    totalScore: value.totalScore as number,
  };
}

function migrateLegacyStats(
  value: Record<string, unknown>,
  defaults: PersistedAggregateStats,
): PersistedAggregateStats | null {
  const runsCompleted = readOptionalNonNegativeInteger(
    value.runsCompleted ?? value.gamesPlayed,
    defaults.runsCompleted,
  );
  const passesAttempted = readOptionalNonNegativeInteger(
    value.passesAttempted,
    defaults.passesAttempted,
  );
  const passesCompleted = readOptionalNonNegativeInteger(
    value.passesCompleted ?? value.completions,
    defaults.passesCompleted,
  );
  const touchdowns = readOptionalNonNegativeInteger(value.touchdowns, defaults.touchdowns);
  const interceptions = readOptionalNonNegativeInteger(value.interceptions, defaults.interceptions);
  const totalScore = readOptionalNonNegativeInteger(value.totalScore, defaults.totalScore);

  if (
    runsCompleted === null ||
    passesAttempted === null ||
    passesCompleted === null ||
    touchdowns === null ||
    interceptions === null ||
    totalScore === null
  ) {
    return null;
  }

  return {
    runsCompleted,
    passesAttempted,
    passesCompleted,
    touchdowns,
    interceptions,
    totalScore,
  };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function isUnitNumber(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value) && value >= 0 && value <= 1;
}

function isNonNegativeSafeInteger(value: unknown): value is number {
  return typeof value === 'number' && Number.isSafeInteger(value) && value >= 0;
}

function readOptionalBoolean(value: unknown, fallback: boolean): boolean | null {
  return value === undefined ? fallback : typeof value === 'boolean' ? value : null;
}

function readOptionalUnitNumber(value: unknown, fallback: number): number | null {
  return value === undefined ? fallback : isUnitNumber(value) ? value : null;
}

function readOptionalNonNegativeInteger(value: unknown, fallback: number): number | null {
  return value === undefined ? fallback : isNonNegativeSafeInteger(value) ? value : null;
}

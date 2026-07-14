export const REWARDED_CONTINUE_CONFIG = {
  enabled: true,
  addedTimeMs: 15_000,
  maximumUsesPerRun: 1,
  prepareAtRemainingMs: 10_000,
  placement: 'overtime_continue',
  reward: 'extra_15_seconds',
} as const;

export const BOUNTY_BOARD_CONFIG = {
  initializationTimeoutMs: 2_000,
  adLoadTimeoutMs: 6_000,
  storageKey: 'pocket-vector-save-v1',
} as const;

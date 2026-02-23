import type { DepthKey } from './types';

export const WORLD = {
  fieldHalfWidth: 32,
  maxDepth: 100,
  maxDeltaSeconds: 0.05
} as const;

export const DEPTH_Z: Record<DepthKey, number> = {
  short: 32,
  medium: 58,
  endzone: 88
};

export const THROW_TRAVEL_TIME: Record<DepthKey, number> = {
  short: 0.55,
  medium: 0.85,
  endzone: 1.15
};

export const SCORE_BY_DEPTH: Record<DepthKey, number> = {
  short: 100,
  medium: 250,
  endzone: 500
};

export const METER_GAIN_BY_DEPTH: Record<DepthKey, number> = {
  short: 25,
  medium: 50,
  endzone: 0
};

export const RECEIVER_CATCH_RADIUS = 5;
export const DEFENDER_BLOCK_RADIUS = 5;
export const RECEIVER_BASE_SPEED = 15;
export const DEFENDER_SPEED = 18;

export const DEPTHS: DepthKey[] = ['short', 'medium', 'endzone'];

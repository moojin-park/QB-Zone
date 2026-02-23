import { DEFENDER_SPEED, DEPTH_Z, RECEIVER_BASE_SPEED } from './config';
import type { GameState } from './types';

export function createInitialState(): GameState {
  return {
    timeSeconds: 0,
    score: 0,
    meter: 0,
    lastPlayText: 'Swipe/drag to aim and throw',
    receivers: [
      { id: 'short', depth: 'short', x: -14, z: DEPTH_Z.short, vx: RECEIVER_BASE_SPEED },
      { id: 'medium', depth: 'medium', x: 2, z: DEPTH_Z.medium, vx: -RECEIVER_BASE_SPEED * 0.85 },
      { id: 'endzone', depth: 'endzone', x: 10, z: DEPTH_Z.endzone, vx: RECEIVER_BASE_SPEED * 0.75 }
    ],
    defender: {
      x: -8,
      z: DEPTH_Z.medium - 12,
      vx: DEFENDER_SPEED
    },
    ball: null
  };
}

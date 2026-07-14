import {
  GAMEPLAY_CONFIG,
  PASSING_LANES,
  getLaneConfig,
  type LaneId,
} from '../config/gameplayConfig';
import type { GameState, ReceiverState } from '../state/GameState';
import { randomBetween, randomDirection } from './random';

const scheduleLaneSpawn = (state: GameState, laneId: LaneId): void => {
  const delay = randomBetween(
    state.randomState,
    GAMEPLAY_CONFIG.receiverSpawnDelayMs.min,
    GAMEPLAY_CONFIG.receiverSpawnDelayMs.max,
  );
  state.randomState = delay.state;
  state.laneSpawnTimers[laneId] = delay.value;
};

const spawnReceiver = (state: GameState, laneId: LaneId): ReceiverState => {
  const lane = getLaneConfig(laneId);
  const directionResult = randomDirection(state.randomState);
  state.randomState = directionResult.state;
  const speedJitter = randomBetween(state.randomState, 0.9, 1.1);
  state.randomState = speedJitter.state;
  const direction = directionResult.direction;
  return {
    id: state.nextEntityId++,
    laneId,
    direction,
    x: direction === 1 ? -GAMEPLAY_CONFIG.receiverOffscreenX : GAMEPLAY_CONFIG.receiverOffscreenX,
    speedPerMs:
      ((2 * GAMEPLAY_CONFIG.receiverOffscreenX) / (lane.receiverCrossingSeconds * 1_000)) *
      speedJitter.value,
    animationMs: 0,
    pose: 'run',
  };
};

export const updateReceivers = (state: GameState, deltaMs: number): void => {
  for (const receiver of state.receivers) {
    receiver.x += receiver.direction * receiver.speedPerMs * deltaMs;
    receiver.animationMs += deltaMs;
  }

  const departed = state.receivers.filter(
    (receiver) => Math.abs(receiver.x) > GAMEPLAY_CONFIG.receiverDespawnX,
  );
  if (departed.length > 0) {
    state.receivers = state.receivers.filter(
      (receiver) => Math.abs(receiver.x) <= GAMEPLAY_CONFIG.receiverDespawnX,
    );
    for (const receiver of departed) scheduleLaneSpawn(state, receiver.laneId);
  }

  for (const lane of PASSING_LANES) {
    state.laneSpawnTimers[lane.id] = Math.max(0, state.laneSpawnTimers[lane.id] - deltaMs);
    const currentCount = state.receivers.filter((receiver) => receiver.laneId === lane.id).length;
    if (currentCount < lane.maximumConcurrentReceivers && state.laneSpawnTimers[lane.id] <= 0) {
      state.receivers.push(spawnReceiver(state, lane.id));
      state.laneSpawnTimers[lane.id] = Number.POSITIVE_INFINITY;
    }
  }
};

export const updateDefenders = (state: GameState, deltaMs: number): void => {
  for (const defender of state.defenders) {
    const patrolLimit = GAMEPLAY_CONFIG.defenderPatrolHalfWidth;
    defender.x = Math.max(-patrolLimit, Math.min(patrolLimit, defender.x));
    if (defender.x <= -patrolLimit && defender.direction === -1) defender.direction = 1;
    if (defender.x >= patrolLimit && defender.direction === 1) defender.direction = -1;

    let distanceRemaining = Math.max(0, defender.speedPerMs * deltaMs);
    while (distanceRemaining > 0) {
      const boundary = defender.direction === 1 ? patrolLimit : -patrolLimit;
      const distanceToBoundary = Math.abs(boundary - defender.x);
      if (distanceRemaining < distanceToBoundary) {
        defender.x += defender.direction * distanceRemaining;
        distanceRemaining = 0;
      } else {
        defender.x = boundary;
        distanceRemaining -= distanceToBoundary;
        defender.direction = defender.direction === 1 ? -1 : 1;
        defender.pose = 'run';
      }
    }
    defender.animationMs += deltaMs;
  }
};

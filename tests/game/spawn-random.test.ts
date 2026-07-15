import { describe, expect, it } from 'vitest';
import {
  GAMEPLAY_CONFIG,
  PASSING_LANES,
  getLaneConfig,
} from '../../src/game/config/gameplayConfig';
import { createInitialState, DEFAULT_SETTINGS } from '../../src/game/state/createInitialState';
import { nextRandom, randomBetween, randomDirection } from '../../src/game/simulation/random';
import { updateDefenders, updateReceivers } from '../../src/game/simulation/spawn';

describe('seeded random number generator', () => {
  it('matches the stable xorshift32 sequence for a known seed', () => {
    const first = nextRandom(1);
    const second = nextRandom(first.state);
    const third = nextRandom(second.state);

    expect([first.state, second.state, third.state]).toEqual([270_369, 67_634_689, 2_647_435_461]);
    expect(first.value).toBeCloseTo(270_369 / 0x1_0000_0000, 15);
  });

  it('replays the same values for the same seed', () => {
    const sequence = (seed: number): number[] => {
      const values: number[] = [];
      let state = seed;
      for (let index = 0; index < 8; index += 1) {
        const next = nextRandom(state);
        values.push(next.value);
        state = next.state;
      }
      return values;
    };

    expect(sequence(123_456)).toEqual(sequence(123_456));
    expect(sequence(123_456)).not.toEqual(sequence(123_457));
  });

  it('keeps values in the half-open zero-to-one interval', () => {
    let state = 98_765;
    for (let index = 0; index < 100; index += 1) {
      const next = nextRandom(state);
      expect(next.value).toBeGreaterThanOrEqual(0);
      expect(next.value).toBeLessThan(1);
      state = next.state;
    }
  });

  it('recovers from the all-zero xorshift state', () => {
    const result = nextRandom(0);

    expect(result.state).toBe(0x6d2b79f5);
    expect(result.value).toBe(0);
  });

  it('maps random values into the requested numeric range', () => {
    let state = 3_141_592;
    for (let index = 0; index < 30; index += 1) {
      const result = randomBetween(state, -4, 9);
      expect(result.value).toBeGreaterThanOrEqual(-4);
      expect(result.value).toBeLessThan(9);
      state = result.state;
    }
  });

  it('returns only the two supported horizontal directions deterministically', () => {
    const first = randomDirection(1);
    const repeated = randomDirection(1);

    expect([-1, 1]).toContain(first.direction);
    expect(repeated).toEqual(first);
  });
});

describe('lane and initial entity data', () => {
  it('defines four unique lanes from short through touchdown depth', () => {
    expect(PASSING_LANES.map((lane) => lane.id)).toEqual(['short', 'medium', 'deep', 'touchdown']);
    expect(PASSING_LANES.map((lane) => lane.normalizedDepth)).toEqual(
      [...PASSING_LANES].map((lane) => lane.normalizedDepth).sort((a, b) => a - b),
    );
  });

  it('slows crossing speed and narrows catch width with depth', () => {
    for (let index = 1; index < PASSING_LANES.length; index += 1) {
      expect(PASSING_LANES[index]!.receiverCrossingSeconds).toBeGreaterThan(
        PASSING_LANES[index - 1]!.receiverCrossingSeconds,
      );
      expect(PASSING_LANES[index]!.catchWidth).toBeLessThan(PASSING_LANES[index - 1]!.catchWidth);
    }
  });

  it('returns configured lane records and rejects unknown runtime lane ids', () => {
    expect(getLaneConfig('deep')).toBe(PASSING_LANES[2]);
    expect(() => getLaneConfig('unknown' as 'deep')).toThrow('Unknown lane: unknown');
  });

  it('starts with one horizontal receiver in every lane and three defenders', () => {
    const state = createInitialState();

    expect(state.receivers.map((item) => item.laneId)).toEqual([
      'short',
      'medium',
      'deep',
      'touchdown',
    ]);
    expect(state.receivers.map((item) => item.direction)).toEqual([1, -1, 1, -1]);
    expect(state.defenders).toHaveLength(3);
    expect(new Set([...state.receivers, ...state.defenders].map((item) => item.id)).size).toBe(7);
  });

  it('copies supplied settings instead of retaining a mutable caller reference', () => {
    const supplied = { ...DEFAULT_SETTINGS, musicVolume: 0.9 };
    const state = createInitialState(supplied, 123);

    state.settings.musicVolume = 0.1;

    expect(supplied.musicVolume).toBe(0.9);
    expect(state.randomState).toBe(123);
  });

  it('normalizes a zero initial seed to the configured default', () => {
    expect(createInitialState(DEFAULT_SETTINGS, 0).randomState).toBe(GAMEPLAY_CONFIG.defaultSeed);
  });
});

describe('horizontal receiver simulation', () => {
  it('changes only horizontal position and animation time during an ordinary update', () => {
    const state = createInitialState();
    const before = state.receivers.map((item) => ({ ...item }));

    updateReceivers(state, 100);

    state.receivers.forEach((item, index) => {
      const prior = before[index]!;
      expect(item.x).toBeCloseTo(prior.x + prior.direction * prior.speedPerMs * 100, 12);
      expect(item.animationMs).toBeCloseTo(prior.animationMs + 100, 12);
      expect(item.laneId).toBe(prior.laneId);
      expect(item.direction).toBe(prior.direction);
      expect(item.speedPerMs).toBe(prior.speedPerMs);
    });
  });

  it('is positionally tolerant of different frame partitions before a spawn boundary', () => {
    const single = createInitialState();
    const partitioned = createInitialState();

    updateReceivers(single, 1_000);
    for (let index = 0; index < 10; index += 1) updateReceivers(partitioned, 100);

    partitioned.receivers.forEach((item, index) => {
      expect(item.x).toBeCloseTo(single.receivers[index]!.x, 10);
      expect(item.animationMs).toBeCloseTo(single.receivers[index]!.animationMs, 10);
    });
  });

  it('despawns at the sideline instead of turning around and schedules a replacement', () => {
    const state = createInitialState(DEFAULT_SETTINGS, 99);
    const departing = state.receivers.find((item) => item.laneId === 'short')!;
    departing.x = GAMEPLAY_CONFIG.receiverDespawnX + 0.01;
    departing.direction = 1;

    updateReceivers(state, 1);

    expect(state.receivers.some((item) => item.id === departing.id)).toBe(false);
    expect(state.laneSpawnTimers.short).toBeGreaterThan(0);
    expect(state.laneSpawnTimers.short).toBeLessThanOrEqual(
      GAMEPLAY_CONFIG.receiverSpawnDelayMs.max,
    );
  });

  it('spawns a missing receiver offscreen when its cadence timer expires', () => {
    const state = createInitialState(DEFAULT_SETTINGS, 777);
    state.receivers = state.receivers.filter((item) => item.laneId !== 'medium');
    state.laneSpawnTimers.medium = 0;

    updateReceivers(state, 1);

    const spawned = state.receivers.find((item) => item.laneId === 'medium')!;
    expect(Math.abs(spawned.x)).toBe(GAMEPLAY_CONFIG.receiverOffscreenX);
    expect(spawned.pose).toBe('run');
    expect(spawned.hasCaught).toBe(false);
    expect(state.laneSpawnTimers.medium).toBe(Number.POSITIVE_INFINITY);
  });

  it('never exceeds a lane maximum while a receiver is already active', () => {
    const state = createInitialState();
    state.laneSpawnTimers.deep = 0;

    updateReceivers(state, 1);

    expect(state.receivers.filter((item) => item.laneId === 'deep')).toHaveLength(
      getLaneConfig('deep').maximumConcurrentReceivers,
    );
  });

  it('replays spawn direction and speed jitter from the same seed', () => {
    const runSpawn = () => {
      const state = createInitialState(DEFAULT_SETTINGS, 424_242);
      state.receivers = state.receivers.filter((item) => item.laneId !== 'short');
      state.laneSpawnTimers.short = 0;
      updateReceivers(state, 1);
      return {
        receiver: state.receivers.find((item) => item.laneId === 'short'),
        randomState: state.randomState,
      };
    };

    expect(runSpawn()).toEqual(runSpawn());
  });
});

describe('horizontal defender simulation', () => {
  it('keeps every defender slower than the receiver nearest its coverage depth', () => {
    const state = createInitialState();

    for (const defender of state.defenders) {
      const nearestLane = [...PASSING_LANES].sort(
        (left, right) =>
          Math.abs(left.normalizedDepth - defender.depth) -
          Math.abs(right.normalizedDepth - defender.depth),
      )[0]!;
      const receiver = state.receivers.find((item) => item.laneId === nearestLane.id)!;
      expect(defender.speedPerMs).toBeLessThan(receiver.speedPerMs);
    }
  });

  it('uses each crossing-time setting as one complete sideline-to-sideline patrol', () => {
    const state = createInitialState();

    state.defenders.forEach((defender, index) => {
      const isolated = createInitialState();
      isolated.defenders = [defender];
      defender.x = -GAMEPLAY_CONFIG.defenderPatrolHalfWidth;
      defender.direction = 1;

      updateDefenders(isolated, GAMEPLAY_CONFIG.defenderCrossingSeconds[index]! * 1_000);

      expect(defender.x).toBeCloseTo(GAMEPLAY_CONFIG.defenderPatrolHalfWidth, 12);
      expect(defender.direction).toBe(-1);
    });
  });

  it('changes horizontal position but preserves coverage depth', () => {
    const state = createInitialState();
    const before = state.defenders.map((item) => ({ ...item }));

    updateDefenders(state, 125);

    state.defenders.forEach((item, index) => {
      const prior = before[index]!;
      expect(item.x).toBeCloseTo(prior.x + prior.direction * prior.speedPerMs * 125, 12);
      expect(item.depth).toBe(prior.depth);
      expect(item.direction).toBe(prior.direction);
      expect(item.animationMs).toBe(prior.animationMs + 125);
    });
  });

  it('reflects a defender at the visible patrol edge instead of letting it leave frame', () => {
    const state = createInitialState();
    const item = state.defenders[0]!;
    item.x = GAMEPLAY_CONFIG.defenderPatrolHalfWidth - 0.01;
    item.direction = 1;
    item.speedPerMs = 0.02;
    item.pose = 'intercept';

    updateDefenders(state, 1);

    expect(item.x).toBeCloseTo(GAMEPLAY_CONFIG.defenderPatrolHalfWidth - 0.01, 12);
    expect(item.direction).toBe(-1);
    expect(item.pose).toBe('run');
  });

  it('clamps legacy out-of-bounds positions and turns them back toward the field', () => {
    const state = createInitialState();
    const item = state.defenders[1]!;
    item.x = -(GAMEPLAY_CONFIG.defenderPatrolHalfWidth + 0.2);
    item.direction = -1;

    updateDefenders(state, 0);

    expect(item.x).toBe(-GAMEPLAY_CONFIG.defenderPatrolHalfWidth);
    expect(item.direction).toBe(1);
  });

  it('produces the same bounded patrol across different frame partitions', () => {
    const single = createInitialState(DEFAULT_SETTINGS, 8_675_309);
    const partitioned = createInitialState(DEFAULT_SETTINGS, 8_675_309);
    for (const state of [single, partitioned]) {
      state.defenders[0]!.x = GAMEPLAY_CONFIG.defenderPatrolHalfWidth - 0.05;
      state.defenders[0]!.direction = 1;
      state.defenders[0]!.speedPerMs = 0.001;
    }

    updateDefenders(single, 2_000);
    for (let index = 0; index < 20; index += 1) updateDefenders(partitioned, 100);

    expect(partitioned.defenders[0]!.x).toBeCloseTo(single.defenders[0]!.x, 12);
    expect(partitioned.defenders[0]!.direction).toBe(single.defenders[0]!.direction);
    expect(partitioned.defenders[0]!.animationMs).toBe(single.defenders[0]!.animationMs);
    expect(partitioned.randomState).toBe(single.randomState);
  });

  it('never consumes seeded randomness while defenders patrol', () => {
    const state = createInitialState(DEFAULT_SETTINGS, 2026);
    const initialRandomState = state.randomState;

    updateDefenders(state, 20_000);

    expect(state.randomState).toBe(initialRandomState);
    for (const defender of state.defenders) {
      expect(Math.abs(defender.x)).toBeLessThanOrEqual(GAMEPLAY_CONFIG.defenderPatrolHalfWidth);
    }
  });
});

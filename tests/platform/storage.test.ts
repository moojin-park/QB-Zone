import { describe, expect, it } from 'vitest';
import {
  createDefaultPersistedGameData,
  loadLocalPersistentData,
  normalizePersistedGameData,
  parsePersistedGameData,
  saveLocalPersistentData,
  serializePersistedGameData,
} from '../../src/game/platform/storage';
import type { StorageLike } from '../../src/game/platform/storage';

class MemoryStorage implements StorageLike {
  readonly values = new Map<string, string>();

  getItem(key: string): string | null {
    return this.values.get(key) ?? null;
  }

  setItem(key: string, value: string): void {
    this.values.set(key, value);
  }
}

describe('persistent game data', () => {
  it('round-trips the current schema', () => {
    const data = createDefaultPersistedGameData();
    data.personalBest = 12_500;
    data.aggregateStats.runsCompleted = 3;

    const serialized = serializePersistedGameData(data);

    expect(serialized).not.toBeNull();
    expect(parsePersistedGameData(serialized!)).toEqual(data);
  });

  it('migrates a recognized legacy save', () => {
    expect(
      normalizePersistedGameData({
        highScore: 4_500,
        muted: true,
        tutorialComplete: true,
        stats: {
          gamesPlayed: 2,
          completions: 7,
          touchdowns: 1,
        },
      }),
    ).toMatchObject({
      schemaVersion: 1,
      settings: { muted: true },
      tutorialCompleted: true,
      personalBest: 4_500,
      aggregateStats: {
        runsCompleted: 2,
        passesCompleted: 7,
        touchdowns: 1,
      },
    });
  });

  it('ignores malformed and incompatible saves', () => {
    expect(parsePersistedGameData('{bad json')).toBeNull();
    expect(normalizePersistedGameData({})).toBeNull();
    expect(normalizePersistedGameData({ schemaVersion: 99, personalBest: 10 })).toBeNull();

    const malformed = createDefaultPersistedGameData();
    const unknownMalformed: unknown = { ...malformed, personalBest: -1 };
    expect(normalizePersistedGameData(unknownMalformed)).toBeNull();
  });

  it('fails safely when localStorage is unavailable', () => {
    const throwingStorage: StorageLike = {
      getItem(): string | null {
        throw new DOMException('blocked');
      },
      setItem(): void {
        throw new DOMException('quota');
      },
    };

    expect(loadLocalPersistentData(throwingStorage)).toBeNull();
    expect(saveLocalPersistentData(throwingStorage, createDefaultPersistedGameData())).toBe(false);
  });

  it('reads and writes a supplied storage implementation', () => {
    const storage = new MemoryStorage();
    const data = createDefaultPersistedGameData();
    data.personalBest = 9_000;

    expect(saveLocalPersistentData(storage, data, 'test-save')).toBe(true);
    expect(loadLocalPersistentData(storage, 'test-save')).toEqual(data);
  });
});

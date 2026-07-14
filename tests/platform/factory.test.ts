import { describe, expect, it } from 'vitest';
import { BountyBoardPlatform } from '../../src/game/platform/BountyBoardPlatform';
import { createArcadePlatform, parseAllowedHosts } from '../../src/game/platform/factory';
import { FakePlatform } from '../../src/game/platform/FakePlatform';
import { StandalonePlatform } from '../../src/game/platform/StandalonePlatform';
import { createDefaultPersistedGameData, type StorageLike } from '../../src/game/platform/storage';

class MemoryStorage implements StorageLike {
  readonly values = new Map<string, string>();

  getItem(key: string): string | null {
    return this.values.get(key) ?? null;
  }

  setItem(key: string, value: string): void {
    this.values.set(key, value);
  }
}

describe('platform factory', () => {
  it('defaults to standalone and selects Bounty Board explicitly', () => {
    expect(createArcadePlatform({ environment: {}, storage: null })).toBeInstanceOf(
      StandalonePlatform,
    );
    expect(
      createArcadePlatform({
        environment: { VITE_ARCADE_PLATFORM: 'bountyboard', DEV: true },
        storage: null,
      }),
    ).toBeInstanceOf(BountyBoardPlatform);
  });

  it('normalizes and rejects unsafe allowlist entries', () => {
    expect(
      parseAllowedHosts(
        'Example.com, https://staging.example.com/path, example.com, *.bad.test, javascript://bad',
      ),
    ).toEqual(['example.com', 'staging.example.com']);
  });
});

describe('standalone and fake platforms', () => {
  it('persists standalone data without offering an ad', async () => {
    const storage = new MemoryStorage();
    const platform = new StandalonePlatform({ storage, storageKey: 'save' });
    const data = createDefaultPersistedGameData();
    data.personalBest = 7_500;

    await platform.savePersistentData(data);

    await expect(platform.loadPersistentData()).resolves.toEqual(data);
    await expect(platform.prepareContinueAd()).resolves.toMatchObject({
      status: 'unavailable',
    });
  });

  it('records guarded events in the fake platform', () => {
    const platform = new FakePlatform();

    platform.gameplayStart();
    platform.gameplayStart();
    platform.submitScore(500);
    platform.submitScore(500);
    platform.gameOver(500);
    platform.gameOver(500);

    expect(platform.events).toEqual([
      'gameplayStart',
      'submitScore:500',
      'gameplayStop',
      'gameOver:500',
    ]);
  });
});

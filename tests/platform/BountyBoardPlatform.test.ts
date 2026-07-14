import { describe, expect, it } from 'vitest';
import type {
  BBArcadeConfig,
  BBArcadeLockToHostOptions,
  BBArcadePlayer,
  BBArcadePrepareRewardedAdOptions,
  BBArcadeRewardedAdPreparation,
} from '@bountyboard/arcade-sdk';
import { BountyBoardPlatform } from '../../src/game/platform/BountyBoardPlatform';
import type { BountyBoardSdkClient } from '../../src/game/platform/BountyBoardPlatform';
import { createDefaultPersistedGameData } from '../../src/game/platform/storage';
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

class SdkStub implements BountyBoardSdkClient {
  readonly signals: string[] = [];
  readonly liveScores: number[] = [];
  readonly finalScores: number[] = [];
  lockOptions: BBArcadeLockToHostOptions | undefined;
  initOptions: BBArcadeConfig | undefined;
  prepareOptions: BBArcadePrepareRewardedAdOptions | undefined;
  player: BBArcadePlayer | null = null;
  cloudBlob: string | null = null;
  savedBlob: string | null = null;
  preparation: BBArcadeRewardedAdPreparation = {
    status: 'unavailable',
    placement: 'overtime_continue',
    reward: 'extra_15_seconds',
    adBreakId: 'unavailable',
  };
  loadError: Error | null = null;
  saveError: Error | null = null;

  lockToHost(options?: BBArcadeLockToHostOptions): void {
    this.lockOptions = options;
    this.signals.push('lockToHost');
  }

  init(options?: BBArcadeConfig): Promise<void> {
    this.initOptions = options;
    this.signals.push('init');
    return Promise.resolve();
  }

  gameLoadingFinished(): void {
    this.signals.push('gameLoadingFinished');
  }

  gameplayStart(): void {
    this.signals.push('gameplayStart');
  }

  gameplayStop(): void {
    this.signals.push('gameplayStop');
  }

  submitScore(score: number): void {
    this.liveScores.push(score);
  }

  gameOver(score: number): void {
    this.finalScores.push(score);
  }

  getPlayer(): Promise<BBArcadePlayer | null> {
    return Promise.resolve(this.player);
  }

  prepareRewardedAd(
    options?: BBArcadePrepareRewardedAdOptions,
  ): Promise<BBArcadeRewardedAdPreparation> {
    this.prepareOptions = options;
    return Promise.resolve(this.preparation);
  }

  save(blob: string): Promise<void> {
    if (this.saveError !== null) {
      return Promise.reject(this.saveError);
    }

    this.savedBlob = blob;
    return Promise.resolve();
  }

  load(): Promise<string | null> {
    return this.loadError === null
      ? Promise.resolve(this.cloudBlob)
      : Promise.reject(this.loadError);
  }
}

describe('BountyBoardPlatform', () => {
  it('locks before one non-blocking initialized handshake', async () => {
    const sdk = new SdkStub();
    const platform = new BountyBoardPlatform({
      sdk,
      storage: null,
      allowedHosts: ['play.example.com'],
      signedHostLock: true,
    });

    await Promise.all([platform.initialize(), platform.initialize()]);

    expect(sdk.signals.slice(0, 2)).toEqual(['lockToHost', 'init']);
    expect(sdk.lockOptions).toEqual({
      allow: ['play.example.com'],
      signed: true,
    });
    expect(sdk.initOptions).toMatchObject({
      rewardedAds: { preload: true, testMode: false, loadTimeoutMs: 6_000 },
    });
  });

  it('deduplicates lifecycle, live score, and final score calls', () => {
    const sdk = new SdkStub();
    const platform = new BountyBoardPlatform({
      sdk,
      storage: null,
      lockToHost: false,
    });

    platform.loadingFinished();
    platform.loadingFinished();
    platform.gameplayStart();
    platform.gameplayStart();
    platform.submitScore(0);
    platform.submitScore(0);
    platform.submitScore(500);
    platform.submitScore(-1);
    platform.gameOver(500);
    platform.gameOver(500);
    platform.submitScore(1_000);

    expect(sdk.signals).toEqual(['gameLoadingFinished', 'gameplayStart', 'gameplayStop']);
    expect(sdk.liveScores).toEqual([0, 500]);
    expect(sdk.finalScores).toEqual([500]);

    platform.gameplayStart();
    platform.submitScore(0);
    platform.gameOver(0);
    expect(sdk.finalScores).toEqual([500, 0]);
  });

  it('keeps the prepared show call synchronous and one-shot', async () => {
    const sdk = new SdkStub();
    let showCalls = 0;
    let onStartCalls = 0;
    sdk.preparation = {
      status: 'ready',
      placement: 'overtime_continue',
      reward: 'extra_15_seconds',
      adBreakId: 'ad-1',
      show(): Promise<{
        status: 'viewed';
        placement: string;
        reward: string;
        adBreakId: string;
      }> {
        showCalls += 1;
        sdk.prepareOptions?.onStart?.();
        return Promise.resolve({
          status: 'viewed',
          placement: 'overtime_continue',
          reward: 'extra_15_seconds',
          adBreakId: 'ad-1',
        });
      },
    };
    const platform = new BountyBoardPlatform({
      sdk,
      storage: null,
      lockToHost: false,
      onRewardedAdStart: () => {
        onStartCalls += 1;
      },
    });

    const prepared = await platform.prepareContinueAd();
    expect(prepared.status).toBe('ready');
    if (prepared.status !== 'ready') {
      throw new Error('Expected a ready ad');
    }

    const firstResult = prepared.show();
    expect(showCalls).toBe(1);
    const secondResult = prepared.show();

    expect(secondResult).toBe(firstResult);
    expect(await firstResult).toMatchObject({ status: 'viewed' });
    expect(onStartCalls).toBe(1);
  });

  it('falls back to local persistence and mirrors successful cloud saves', async () => {
    const sdk = new SdkStub();
    const storage = new MemoryStorage();
    const platform = new BountyBoardPlatform({
      sdk,
      storage,
      storageKey: 'save',
      lockToHost: false,
    });
    const data = createDefaultPersistedGameData();
    data.personalBest = 18_000;

    sdk.loadError = Object.assign(new Error('standalone'), {
      code: 'unsupported',
    });
    storage.setItem('save', JSON.stringify(data));
    expect(await platform.loadPersistentData()).toEqual(data);

    sdk.loadError = null;
    data.personalBest = 22_000;
    await platform.savePersistentData(data);

    expect(JSON.parse(sdk.savedBlob!) as unknown).toEqual(data);
    expect(JSON.parse(storage.getItem('save')!) as unknown).toEqual(data);
  });

  it('returns null or unavailable instead of leaking rejected SDK calls', async () => {
    const sdk = new SdkStub();
    sdk.loadError = new Error('network failure');
    sdk.player = null;
    const platform = new BountyBoardPlatform({
      sdk,
      storage: null,
      lockToHost: false,
    });

    await expect(platform.loadPersistentData()).resolves.toBeNull();
    await expect(platform.getPlayer()).resolves.toBeNull();
    await expect(platform.prepareContinueAd()).resolves.toMatchObject({
      status: 'unavailable',
    });
  });
});

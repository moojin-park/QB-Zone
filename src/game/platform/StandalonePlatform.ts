import { createUnavailableContinueAd } from './ad';
import { PlatformCallGuards } from './guards';
import {
  DEFAULT_PERSISTENT_STORAGE_KEY,
  getBrowserStorage,
  loadLocalPersistentData,
  normalizePersistedGameData,
  saveLocalPersistentData,
} from './storage';
import type { PersistedGameData, StorageLike } from './storage';
import type { ArcadePlatform, ArcadePlayer, PreparedContinueAd } from './types';

export interface StandalonePlatformOptions {
  storage?: StorageLike | null;
  storageKey?: string;
}

/** Browser-only implementation with no account, ads, or external signals. */
export class StandalonePlatform implements ArcadePlatform {
  private readonly guards = new PlatformCallGuards();
  private readonly storage: StorageLike | null;
  private readonly storageKey: string;

  constructor(options: StandalonePlatformOptions = {}) {
    this.storage = options.storage === undefined ? getBrowserStorage() : options.storage;
    this.storageKey = options.storageKey ?? DEFAULT_PERSISTENT_STORAGE_KEY;
  }

  initialize(): Promise<void> {
    return Promise.resolve();
  }

  loadingFinished(): void {
    this.guards.markLoadingFinished();
  }

  gameplayStart(): void {
    this.guards.beginGameplay();
  }

  gameplayStop(): void {
    this.guards.stopGameplay();
  }

  submitScore(score: number): void {
    this.guards.acceptLiveScore(score);
  }

  gameOver(finalScore: number): void {
    this.guards.acceptFinalScore(finalScore);
  }

  getPlayer(): Promise<ArcadePlayer | null> {
    return Promise.resolve(null);
  }

  prepareContinueAd(): Promise<PreparedContinueAd> {
    return Promise.resolve(createUnavailableContinueAd());
  }

  loadPersistentData(): Promise<PersistedGameData | null> {
    return Promise.resolve(loadLocalPersistentData(this.storage, this.storageKey));
  }

  savePersistentData(data: PersistedGameData): Promise<void> {
    const normalized = normalizePersistedGameData(data);
    if (normalized !== null) {
      saveLocalPersistentData(this.storage, normalized, this.storageKey);
    }

    return Promise.resolve();
  }
}

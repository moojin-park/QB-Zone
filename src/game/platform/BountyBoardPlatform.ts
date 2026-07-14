import { BBArcade } from '@bountyboard/arcade-sdk';
import type {
  BBArcadeConfig,
  BBArcadeError,
  BBArcadeLockToHostOptions,
  BBArcadePlayer,
  BBArcadePrepareRewardedAdOptions,
  BBArcadeRewardedAdPreparation,
  BBArcadeRewardedAdResult,
} from '@bountyboard/arcade-sdk';
import { BOUNTY_BOARD_CONFIG } from '../config/bountyBoardConfig';
import { CONTINUE_AD_PLACEMENT, CONTINUE_AD_REWARD, createUnavailableContinueAd } from './ad';
import { PlatformCallGuards } from './guards';
import {
  DEFAULT_PERSISTENT_STORAGE_KEY,
  getBrowserStorage,
  loadLocalPersistentData,
  normalizePersistedGameData,
  parsePersistedGameData,
  saveLocalPersistentData,
  serializePersistedGameData,
} from './storage';
import type { PersistedGameData, StorageLike } from './storage';
import type { ArcadePlatform, ArcadePlayer, ContinueAdResult, PreparedContinueAd } from './types';

const DEFAULT_INITIALIZATION_TIMEOUT_MS = BOUNTY_BOARD_CONFIG.initializationTimeoutMs;
const DEFAULT_REQUEST_TIMEOUT_MS = 8_000;

export interface BountyBoardSdkClient {
  lockToHost(options?: BBArcadeLockToHostOptions): void;
  init(options?: BBArcadeConfig): Promise<void>;
  gameLoadingFinished(): void;
  gameplayStart(): void;
  gameplayStop(): void;
  submitScore(score: number): void;
  gameOver(score: number): void;
  getPlayer(): Promise<BBArcadePlayer | null>;
  prepareRewardedAd(
    options?: BBArcadePrepareRewardedAdOptions,
  ): Promise<BBArcadeRewardedAdPreparation>;
  save(blob: string): Promise<void>;
  load(): Promise<string | null>;
}

export interface BountyBoardPlatformOptions {
  sdk?: BountyBoardSdkClient;
  storage?: StorageLike | null;
  storageKey?: string;
  lockToHost?: boolean;
  allowedHosts?: readonly string[];
  signedHostLock?: boolean;
  onHostBlocked?: () => void;
  onRewardedAdStart?: () => void;
  rewardedAdTestMode?: boolean;
  rewardedAdLoadTimeoutMs?: number;
  initializationTimeoutMs?: number;
  requestTimeoutMs?: number;
  onSdkError?: (operation: string, error: unknown) => void;
}

/**
 * Thin, failure-safe boundary around @bountyboard/arcade-sdk. The rest of the
 * game never imports or calls the SDK directly.
 */
export class BountyBoardPlatform implements ArcadePlatform {
  private readonly sdk: BountyBoardSdkClient;
  private readonly storage: StorageLike | null;
  private readonly storageKey: string;
  private readonly shouldLockToHost: boolean;
  private readonly allowedHosts: string[];
  private readonly signedHostLock: boolean;
  private readonly onHostBlocked: (() => void) | undefined;
  private readonly onRewardedAdStart: (() => void) | undefined;
  private readonly rewardedAdTestMode: boolean;
  private readonly rewardedAdLoadTimeoutMs: number;
  private readonly initializationTimeoutMs: number;
  private readonly requestTimeoutMs: number;
  private readonly onSdkError: (operation: string, error: unknown) => void;
  private readonly guards = new PlatformCallGuards();

  private initializationPromise: Promise<void> | null = null;
  private hostLockApplied = false;

  constructor(options: BountyBoardPlatformOptions = {}) {
    this.sdk = options.sdk ?? BBArcade;
    this.storage = options.storage === undefined ? getBrowserStorage() : options.storage;
    this.storageKey = options.storageKey ?? DEFAULT_PERSISTENT_STORAGE_KEY;
    this.shouldLockToHost = options.lockToHost ?? true;
    this.allowedHosts = [...(options.allowedHosts ?? [])];
    this.signedHostLock = options.signedHostLock ?? false;
    this.onHostBlocked = options.onHostBlocked;
    this.onRewardedAdStart = options.onRewardedAdStart;
    this.rewardedAdTestMode = options.rewardedAdTestMode ?? false;
    this.rewardedAdLoadTimeoutMs = clampTimeout(
      options.rewardedAdLoadTimeoutMs,
      BOUNTY_BOARD_CONFIG.adLoadTimeoutMs,
      15_000,
    );
    this.initializationTimeoutMs = clampTimeout(
      options.initializationTimeoutMs,
      DEFAULT_INITIALIZATION_TIMEOUT_MS,
      15_000,
    );
    this.requestTimeoutMs = clampTimeout(
      options.requestTimeoutMs,
      DEFAULT_REQUEST_TIMEOUT_MS,
      30_000,
    );
    this.onSdkError = options.onSdkError ?? (() => undefined);
  }

  initialize(): Promise<void> {
    this.initializationPromise ??= this.initializeSdk();

    return this.initializationPromise;
  }

  loadingFinished(): void {
    if (this.guards.markLoadingFinished()) {
      this.callSignal('gameLoadingFinished', () => {
        this.sdk.gameLoadingFinished();
      });
    }
  }

  gameplayStart(): void {
    if (this.guards.beginGameplay()) {
      this.callSignal('gameplayStart', () => {
        this.sdk.gameplayStart();
      });
    }
  }

  gameplayStop(): void {
    if (this.guards.stopGameplay()) {
      this.callSignal('gameplayStop', () => {
        this.sdk.gameplayStop();
      });
    }
  }

  submitScore(score: number): void {
    if (this.guards.acceptLiveScore(score)) {
      this.callSignal('submitScore', () => {
        this.sdk.submitScore(score);
      });
    }
  }

  gameOver(finalScore: number): void {
    const decision = this.guards.acceptFinalScore(finalScore);
    if (!decision.accepted) {
      return;
    }

    if (decision.stoppedActiveGameplay) {
      this.callSignal('gameplayStop', () => {
        this.sdk.gameplayStop();
      });
    }

    this.callSignal('gameOver', () => {
      this.sdk.gameOver(finalScore);
    });
  }

  async getPlayer(): Promise<ArcadePlayer | null> {
    await this.initialize();
    const player = await this.request('getPlayer', () => this.sdk.getPlayer(), null);

    return isValidPlayer(player) ? { name: player.name, avatarUrl: player.avatarUrl } : null;
  }

  async prepareContinueAd(): Promise<PreparedContinueAd> {
    await this.initialize();

    const preparation = await this.request(
      'prepareRewardedAd',
      () =>
        this.sdk.prepareRewardedAd({
          placement: CONTINUE_AD_PLACEMENT,
          reward: CONTINUE_AD_REWARD,
          loadTimeoutMs: this.rewardedAdLoadTimeoutMs,
          testMode: this.rewardedAdTestMode,
          onStart: this.onRewardedAdStart,
        }),
      null,
    );

    if (preparation === null) {
      return createUnavailableContinueAd('prepare_failed');
    }

    return wrapPreparedContinueAd(preparation, (error) => {
      this.onSdkError('showRewardedAd', error);
    });
  }

  async loadPersistentData(): Promise<PersistedGameData | null> {
    await this.initialize();

    const cloudBlob = await this.request('load', () => this.sdk.load(), null);

    if (cloudBlob !== null) {
      const cloudData = parsePersistedGameData(cloudBlob);
      if (cloudData !== null) {
        saveLocalPersistentData(this.storage, cloudData, this.storageKey);
        return cloudData;
      }
    }

    return loadLocalPersistentData(this.storage, this.storageKey);
  }

  async savePersistentData(data: PersistedGameData): Promise<void> {
    const normalized = normalizePersistedGameData(data);
    if (normalized === null) {
      return;
    }

    const serialized = serializePersistedGameData(normalized);
    if (serialized === null) {
      return;
    }

    await this.initialize();
    await this.request(
      'save',
      async () => {
        await this.sdk.save(serialized);
        return true;
      },
      false,
    );

    // The local mirror makes a hosted-to-standalone transition and transient
    // cloud outages harmless. localStorage access is itself failure-safe.
    saveLocalPersistentData(this.storage, normalized, this.storageKey);
  }

  private async initializeSdk(): Promise<void> {
    this.applyHostLock();

    let initialization: Promise<void>;
    try {
      initialization = this.sdk.init({
        rewardedAds: {
          preload: true,
          testMode: this.rewardedAdTestMode,
          loadTimeoutMs: this.rewardedAdLoadTimeoutMs,
        },
      });
    } catch (error: unknown) {
      this.onSdkError('init', error);
      return;
    }

    await settleWithFallback(initialization, undefined, this.initializationTimeoutMs, (error) => {
      this.onSdkError('init', error);
    });
  }

  private applyHostLock(): void {
    if (!this.shouldLockToHost || this.hostLockApplied) {
      return;
    }

    this.hostLockApplied = true;
    const lockOptions: BBArcadeLockToHostOptions = {
      allow: this.allowedHosts,
      signed: this.signedHostLock,
    };

    if (this.onHostBlocked !== undefined) {
      lockOptions.onBlocked = this.onHostBlocked;
    }

    this.callSignal('lockToHost', () => {
      this.sdk.lockToHost(lockOptions);
    });
  }

  private callSignal(operation: string, signal: () => void): void {
    try {
      signal();
    } catch (error: unknown) {
      this.onSdkError(operation, error);
    }
  }

  private request<T>(operation: string, request: () => Promise<T>, fallback: T): Promise<T> {
    let pending: Promise<T>;
    try {
      pending = request();
    } catch (error: unknown) {
      this.onSdkError(operation, error);
      return Promise.resolve(fallback);
    }

    return settleWithFallback(pending, fallback, this.requestTimeoutMs, (error) => {
      this.onSdkError(operation, error);
    });
  }
}

export function isBBArcadeError(error: unknown): error is BBArcadeError {
  if (!(error instanceof Error) || !('code' in error)) {
    return false;
  }

  return ['unsupported', 'unauthenticated', 'too_large', 'rejected', 'error'].includes(
    String(error.code),
  );
}

function wrapPreparedContinueAd(
  preparation: BBArcadeRewardedAdPreparation,
  onError: (error: unknown) => void,
): PreparedContinueAd {
  if (preparation.status !== 'ready') {
    return {
      status: preparation.status,
      placement: preparation.placement,
      reward: preparation.reward,
      adBreakId: preparation.adBreakId,
      error: preparation.error,
      breakStatus: preparation.breakStatus,
    };
  }

  let finalResultPromise: Promise<ContinueAdResult> | null = null;

  return {
    status: 'ready',
    placement: preparation.placement,
    reward: preparation.reward,
    adBreakId: preparation.adBreakId,
    show(): Promise<ContinueAdResult> {
      if (finalResultPromise !== null) {
        return finalResultPromise;
      }

      try {
        // This SDK call intentionally happens synchronously in show(). The UI
        // must invoke this method directly from its click/pointer handler.
        const sdkResultPromise = preparation.show();
        finalResultPromise = sdkResultPromise.then(
          (result) => normalizeAdResult(result),
          (error: unknown) => {
            onError(error);
            return createAdErrorResult(preparation, error);
          },
        );
      } catch (error: unknown) {
        onError(error);
        finalResultPromise = Promise.resolve(createAdErrorResult(preparation, error));
      }

      return finalResultPromise;
    },
  };
}

function normalizeAdResult(result: BBArcadeRewardedAdResult): ContinueAdResult {
  return {
    status: result.status === 'ready' ? 'error' : result.status,
    placement: result.placement,
    reward: result.reward,
    adBreakId: result.adBreakId,
    error: result.status === 'ready' ? 'invalid_final_status' : result.error,
    breakStatus: result.breakStatus,
  };
}

function createAdErrorResult(
  preparation: { placement: string; reward: string; adBreakId: string },
  error: unknown,
): ContinueAdResult {
  return {
    status: 'error',
    placement: preparation.placement,
    reward: preparation.reward,
    adBreakId: preparation.adBreakId,
    error: error instanceof Error ? error.message : 'show_ad_error',
  };
}

function isValidPlayer(player: BBArcadePlayer | null): player is BBArcadePlayer {
  return (
    player !== null &&
    typeof player.name === 'string' &&
    player.name.trim().length > 0 &&
    (player.avatarUrl === null || typeof player.avatarUrl === 'string')
  );
}

function settleWithFallback<T>(
  pending: Promise<T>,
  fallback: T,
  timeoutMs: number,
  onRejected: (error: unknown) => void,
): Promise<T> {
  return new Promise((resolve) => {
    let settled = false;
    const finish = (value: T): void => {
      if (settled) {
        return;
      }

      settled = true;
      clearTimeout(timeout);
      resolve(value);
    };
    const timeout = setTimeout(() => {
      finish(fallback);
    }, timeoutMs);

    void pending.then(finish, (error: unknown) => {
      onRejected(error);
      finish(fallback);
    });
  });
}

function clampTimeout(value: number | undefined, fallback: number, maximum: number): number {
  if (value === undefined || !Number.isFinite(value)) {
    return fallback;
  }

  return Math.max(0, Math.min(maximum, Math.round(value)));
}

import { createUnavailableContinueAd } from './ad';
import { PlatformCallGuards } from './guards';
import { normalizePersistedGameData } from './storage';
import type { PersistedGameData } from './storage';
import type { ArcadePlatform, ArcadePlayer, PreparedContinueAd } from './types';

export interface FakePlatformOptions {
  player?: ArcadePlayer | null;
  preparedContinueAd?: PreparedContinueAd;
  persistedData?: PersistedGameData | null;
}

/** Deterministic in-memory platform for simulation and UI tests. */
export class FakePlatform implements ArcadePlatform {
  readonly events: string[] = [];
  readonly liveScores: number[] = [];
  readonly finalScores: number[] = [];
  initializeCalls = 0;
  loadingFinishedCalls = 0;
  gameplayStartCalls = 0;
  gameplayStopCalls = 0;
  saveCalls = 0;

  player: ArcadePlayer | null;
  preparedContinueAd: PreparedContinueAd;
  persistedData: PersistedGameData | null;

  private readonly guards = new PlatformCallGuards();

  constructor(options: FakePlatformOptions = {}) {
    this.player = options.player ?? null;
    this.preparedContinueAd = options.preparedContinueAd ?? createUnavailableContinueAd();
    this.persistedData = cloneData(options.persistedData ?? null);
  }

  initialize(): Promise<void> {
    this.initializeCalls += 1;
    this.events.push('initialize');
    return Promise.resolve();
  }

  loadingFinished(): void {
    if (!this.guards.markLoadingFinished()) {
      return;
    }

    this.loadingFinishedCalls += 1;
    this.events.push('loadingFinished');
  }

  gameplayStart(): void {
    if (!this.guards.beginGameplay()) {
      return;
    }

    this.gameplayStartCalls += 1;
    this.events.push('gameplayStart');
  }

  gameplayStop(): void {
    if (!this.guards.stopGameplay()) {
      return;
    }

    this.gameplayStopCalls += 1;
    this.events.push('gameplayStop');
  }

  submitScore(score: number): void {
    if (!this.guards.acceptLiveScore(score)) {
      return;
    }

    this.liveScores.push(score);
    this.events.push(`submitScore:${score}`);
  }

  gameOver(finalScore: number): void {
    const decision = this.guards.acceptFinalScore(finalScore);
    if (!decision.accepted) {
      return;
    }

    if (decision.stoppedActiveGameplay) {
      this.gameplayStopCalls += 1;
      this.events.push('gameplayStop');
    }

    this.finalScores.push(finalScore);
    this.events.push(`gameOver:${finalScore}`);
  }

  getPlayer(): Promise<ArcadePlayer | null> {
    return Promise.resolve(
      this.player === null ? null : { name: this.player.name, avatarUrl: this.player.avatarUrl },
    );
  }

  prepareContinueAd(): Promise<PreparedContinueAd> {
    return Promise.resolve(this.preparedContinueAd);
  }

  loadPersistentData(): Promise<PersistedGameData | null> {
    return Promise.resolve(cloneData(this.persistedData));
  }

  savePersistentData(data: PersistedGameData): Promise<void> {
    const normalized = normalizePersistedGameData(data);
    if (normalized !== null) {
      this.persistedData = normalized;
      this.saveCalls += 1;
      this.events.push('savePersistentData');
    }

    return Promise.resolve();
  }
}

function cloneData(data: PersistedGameData | null): PersistedGameData | null {
  return data === null
    ? null
    : normalizePersistedGameData(JSON.parse(JSON.stringify(data)) as unknown);
}

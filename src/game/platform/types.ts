import type { PersistedGameData } from './storage';

export interface ArcadePlayer {
  name: string;
  avatarUrl: string | null;
}

export type ContinueAdResultStatus = 'viewed' | 'dismissed' | 'unavailable' | 'error';

export interface ContinueAdResult {
  status: ContinueAdResultStatus;
  placement: string;
  reward: string;
  adBreakId: string;
  error?: string;
  breakStatus?: string;
}

export interface ReadyContinueAd {
  status: 'ready';
  placement: string;
  reward: string;
  adBreakId: string;
  show(): Promise<ContinueAdResult>;
}

export interface UnavailableContinueAd {
  status: 'unavailable' | 'error';
  placement: string;
  reward: string;
  adBreakId: string;
  error?: string;
  breakStatus?: string;
}

export type PreparedContinueAd = ReadyContinueAd | UnavailableContinueAd;

export interface ArcadePlatform {
  initialize(): Promise<void>;
  loadingFinished(): void;
  gameplayStart(): void;
  gameplayStop(): void;
  submitScore(score: number): void;
  gameOver(finalScore: number): void;
  getPlayer(): Promise<ArcadePlayer | null>;
  prepareContinueAd(): Promise<PreparedContinueAd>;
  loadPersistentData(): Promise<PersistedGameData | null>;
  savePersistentData(data: PersistedGameData): Promise<void>;
}

export function isValidArcadeScore(score: number): boolean {
  return Number.isSafeInteger(score) && score >= 0;
}

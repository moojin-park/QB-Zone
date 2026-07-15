import type { LaneId } from '../config/gameplayConfig';
import type { ViewMode } from '../config/visualConfig';

export type GamePhase =
  | 'loading'
  | 'title'
  | 'instructions'
  | 'countdown'
  | 'playing'
  | 'resolving-final-ball'
  | 'continue-offer'
  | 'rewarded-ad'
  | 'results'
  | 'paused';

export type PassOutcome = 'completion' | 'touchdown' | 'incompletion' | 'interception';

export interface WorldPoint {
  x: number;
  depth: number;
  height: number;
}

export interface ScreenPoint {
  x: number;
  y: number;
}

export interface ReceiverState {
  id: number;
  laneId: LaneId;
  x: number;
  direction: -1 | 1;
  speedPerMs: number;
  animationMs: number;
  pose: 'run' | 'catch' | 'celebrate';
  hasCaught: boolean;
}

export interface DefenderState {
  id: number;
  depth: number;
  x: number;
  direction: -1 | 1;
  speedPerMs: number;
  animationMs: number;
  pose: 'run' | 'intercept';
}

export interface BallState {
  id: number;
  elapsedMs: number;
  durationMs: number;
  start: WorldPoint;
  target: WorldPoint;
  end: WorldPoint;
  arcHeight: number;
  current: WorldPoint;
  previous: WorldPoint;
  spinRadians: number;
  radiusPx: number;
  releaseSpeedPxPerMs: number;
  aimMarker: ScreenPoint;
}

export interface PlayScoreResult {
  readonly outcome: PassOutcome;
  readonly laneId: LaneId | null;
  readonly baseCompletionPoints: number;
  readonly tdBonusWasActive: boolean;
  readonly tdBonusPoints: number;
  readonly touchdownMultiplier: number;
  readonly awardedPoints: number;
  readonly totalScoreBefore: number;
  readonly totalScoreAfter: number;
  readonly tdMeterBefore: number;
  readonly tdMeterAfter: number;
  readonly touchdownStreakBefore: number;
  readonly touchdownStreakAfter: number;
}

export interface RunStats {
  attempts: number;
  completions: number;
  touchdowns: number;
  incompletions: number;
  interceptions: number;
  longestTouchdownStreak: number;
  rewardedContinueUsed: boolean;
}

export interface FeedbackState {
  tone: 'positive' | 'touchdown' | 'negative' | 'bonus';
  headline: string;
  detail: string;
  remainingMs: number;
  x?: number;
  y?: number;
}

export interface GameSettings {
  masterMuted: boolean;
  musicVolume: number;
  sfxVolume: number;
  reducedMotion: boolean;
  highContrastAim: boolean;
  viewMode: ViewMode;
  tutorialComplete: boolean;
}

export interface DebugState {
  enabled: boolean;
  showTrajectory: boolean;
  showCatchZones: boolean;
  showDefenderHitZones: boolean;
  slowMotion: number;
  frozen: boolean;
  forcedOutcome: PassOutcome | null;
  lastCollisionPoint: WorldPoint | null;
  lastCollisionKind: 'receiver' | 'defender' | null;
}

export interface GameState {
  phase: GamePhase;
  phaseBeforePause: GamePhase | null;
  countdownRemainingMs: number;
  remainingMs: number;
  elapsedGameplayMs: number;
  finalBallGraceRemainingMs: number;
  score: number;
  tdMeter: number;
  touchdownStreak: number;
  receivers: ReceiverState[];
  defenders: DefenderState[];
  ball: BallState | null;
  nextEntityId: number;
  laneSpawnTimers: Record<LaneId, number>;
  playCooldownMs: number;
  feedback: FeedbackState | null;
  lastPlayScore: PlayScoreResult | null;
  stats: RunStats;
  continueUses: number;
  adPreparationStarted: boolean;
  randomState: number;
  settings: GameSettings;
  debug: DebugState;
}

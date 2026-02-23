export type DepthKey = 'short' | 'medium' | 'endzone';

export type PlayOutcome = 'completion' | 'incompletion' | 'deflected';

export interface ReceiverState {
  id: string;
  depth: DepthKey;
  x: number;
  z: number;
  vx: number;
}

export interface DefenderState {
  x: number;
  z: number;
  vx: number;
}

export interface BallFlight {
  startX: number;
  startZ: number;
  targetX: number;
  targetZ: number;
  targetDepth: DepthKey;
  elapsed: number;
  travelTime: number;
  meterFullAtStart: boolean;
}

export interface GameState {
  timeSeconds: number;
  score: number;
  meter: number;
  lastPlayText: string;
  receivers: ReceiverState[];
  defender: DefenderState;
  ball: BallFlight | null;
}

export interface ThrowIntent {
  targetX: number;
  targetDepth: DepthKey;
}

export interface UpdateIntent {
  throwIntent?: ThrowIntent;
}

export interface ScoreResolutionInput {
  currentScore: number;
  currentMeter: number;
  outcome: PlayOutcome;
  depth: DepthKey;
  meterFullAtStart: boolean;
}

export interface ScoreResolution {
  nextScore: number;
  nextMeter: number;
  awardedPoints: number;
}

export interface AimPreview {
  active: boolean;
  startX: number;
  startY: number;
  currentX: number;
  currentY: number;
  targetDepth: DepthKey | null;
  targetX: number;
}

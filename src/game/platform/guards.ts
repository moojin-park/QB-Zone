import { isValidArcadeScore } from './types';

export interface SubmissionState {
  finalScoreSubmitted: boolean;
  lastSubmittedLiveScore: number | null;
}

export interface PlatformGuardSnapshot extends SubmissionState {
  gameplayActive: boolean;
  loadingFinishedSignaled: boolean;
}

export interface FinalScoreDecision {
  accepted: boolean;
  stoppedActiveGameplay: boolean;
}

/** Keeps SDK signals idempotent while still allowing multiple runs per page. */
export class PlatformCallGuards {
  private loadingFinishedSignaled = false;
  private gameplayActive = false;
  private submission: SubmissionState = {
    finalScoreSubmitted: false,
    lastSubmittedLiveScore: null,
  };

  markLoadingFinished(): boolean {
    if (this.loadingFinishedSignaled) {
      return false;
    }

    this.loadingFinishedSignaled = true;
    return true;
  }

  beginGameplay(): boolean {
    if (this.gameplayActive) {
      return false;
    }

    if (this.submission.finalScoreSubmitted) {
      this.submission = {
        finalScoreSubmitted: false,
        lastSubmittedLiveScore: null,
      };
    }

    this.gameplayActive = true;
    return true;
  }

  stopGameplay(): boolean {
    if (!this.gameplayActive) {
      return false;
    }

    this.gameplayActive = false;
    return true;
  }

  acceptLiveScore(score: number): boolean {
    if (
      this.submission.finalScoreSubmitted ||
      !isValidArcadeScore(score) ||
      this.submission.lastSubmittedLiveScore === score
    ) {
      return false;
    }

    this.submission.lastSubmittedLiveScore = score;
    return true;
  }

  acceptFinalScore(score: number): FinalScoreDecision {
    if (this.submission.finalScoreSubmitted || !isValidArcadeScore(score)) {
      return { accepted: false, stoppedActiveGameplay: false };
    }

    const stoppedActiveGameplay = this.gameplayActive;
    this.gameplayActive = false;
    this.submission.finalScoreSubmitted = true;

    return { accepted: true, stoppedActiveGameplay };
  }

  snapshot(): PlatformGuardSnapshot {
    return {
      gameplayActive: this.gameplayActive,
      loadingFinishedSignaled: this.loadingFinishedSignaled,
      finalScoreSubmitted: this.submission.finalScoreSubmitted,
      lastSubmittedLiveScore: this.submission.lastSubmittedLiveScore,
    };
  }
}

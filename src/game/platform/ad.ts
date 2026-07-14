import { REWARDED_CONTINUE_CONFIG } from '../config/bountyBoardConfig';
import type {
  ContinueAdResult,
  PreparedContinueAd,
  ReadyContinueAd,
  UnavailableContinueAd,
} from './types';

export const CONTINUE_AD_PLACEMENT = REWARDED_CONTINUE_CONFIG.placement;
export const CONTINUE_AD_REWARD = REWARDED_CONTINUE_CONFIG.reward;

export function createUnavailableContinueAd(error = 'unsupported'): UnavailableContinueAd {
  return {
    status: 'unavailable',
    placement: CONTINUE_AD_PLACEMENT,
    reward: CONTINUE_AD_REWARD,
    adBreakId: '',
    error,
  };
}

export function createReadyContinueAd(
  result: ContinueAdResult | (() => Promise<ContinueAdResult>),
): ReadyContinueAd {
  let resultPromise: Promise<ContinueAdResult> | null = null;

  return {
    status: 'ready',
    placement: CONTINUE_AD_PLACEMENT,
    reward: CONTINUE_AD_REWARD,
    adBreakId: 'fake-continue-ad',
    show(): Promise<ContinueAdResult> {
      if (resultPromise !== null) {
        return resultPromise;
      }

      try {
        resultPromise = typeof result === 'function' ? result() : Promise.resolve(result);
      } catch (error: unknown) {
        resultPromise = Promise.resolve({
          status: 'error',
          placement: CONTINUE_AD_PLACEMENT,
          reward: CONTINUE_AD_REWARD,
          adBreakId: 'fake-continue-ad',
          error: getErrorMessage(error),
        });
      }

      return resultPromise;
    },
  };
}

export function isContinueRewardGranted(result: ContinueAdResult): boolean {
  return result.status === 'viewed';
}

export function isContinueAdReady(prepared: PreparedContinueAd): prepared is ReadyContinueAd {
  return prepared.status === 'ready';
}

function getErrorMessage(error: unknown): string {
  return error instanceof Error ? error.message : 'show_ad_error';
}

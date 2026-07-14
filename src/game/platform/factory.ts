import { BOUNTY_BOARD_CONFIG } from '../config/bountyBoardConfig';
import { BountyBoardPlatform } from './BountyBoardPlatform';
import type { BountyBoardPlatformOptions, BountyBoardSdkClient } from './BountyBoardPlatform';
import { StandalonePlatform } from './StandalonePlatform';
import type { StorageLike } from './storage';
import type { ArcadePlatform } from './types';

export type ArcadePlatformMode = 'standalone' | 'bountyboard';

export interface ArcadePlatformEnvironment {
  DEV?: boolean;
  PROD?: boolean;
  VITE_ARCADE_PLATFORM?: string;
  VITE_BB_ALLOWED_HOSTS?: string;
  VITE_BB_HOST_LOCK?: string;
  VITE_BB_REWARDED_TEST_MODE?: string;
  VITE_BB_SIGNED_HOST_LOCK?: string;
}

export interface CreateArcadePlatformOptions {
  environment?: ArcadePlatformEnvironment;
  sdk?: BountyBoardSdkClient;
  storage?: StorageLike | null;
  storageKey?: string;
  onHostBlocked?: () => void;
  onRewardedAdStart?: () => void;
  onSdkError?: BountyBoardPlatformOptions['onSdkError'];
}

/**
 * Standalone is the safe default. Set VITE_ARCADE_PLATFORM=bountyboard for the
 * artifact uploaded to Bounty Board; that production path enables host lock.
 */
export function createArcadePlatform(options: CreateArcadePlatformOptions = {}): ArcadePlatform {
  const environment = options.environment ?? readImportMetaEnvironment();
  const mode = parseArcadePlatformMode(environment.VITE_ARCADE_PLATFORM);
  const storageKey = options.storageKey ?? BOUNTY_BOARD_CONFIG.storageKey;

  if (mode === 'standalone') {
    return new StandalonePlatform({
      storage: options.storage,
      storageKey,
    });
  }

  const defaultHostLock = environment.DEV !== true;

  return new BountyBoardPlatform({
    sdk: options.sdk,
    storage: options.storage,
    storageKey,
    lockToHost: parseBooleanEnvironmentValue(environment.VITE_BB_HOST_LOCK, defaultHostLock),
    allowedHosts: parseAllowedHosts(environment.VITE_BB_ALLOWED_HOSTS),
    signedHostLock: parseBooleanEnvironmentValue(environment.VITE_BB_SIGNED_HOST_LOCK, false),
    rewardedAdTestMode: parseBooleanEnvironmentValue(environment.VITE_BB_REWARDED_TEST_MODE, false),
    onHostBlocked: options.onHostBlocked,
    onRewardedAdStart: options.onRewardedAdStart,
    onSdkError: options.onSdkError,
  });
}

export function parseArcadePlatformMode(value: string | undefined): ArcadePlatformMode {
  switch (value?.trim().toLowerCase()) {
    case 'bb':
    case 'bounty-board':
    case 'bountyboard':
      return 'bountyboard';
    default:
      return 'standalone';
  }
}

/**
 * Converts a comma-separated list of plain hosts, host:port pairs, or HTTP(S)
 * URLs into the host strings accepted by BBArcade.lockToHost({ allow }).
 */
export function parseAllowedHosts(value: string | undefined): string[] {
  if (value === undefined || value.trim() === '') {
    return [];
  }

  const allowedHosts: string[] = [];
  const seen = new Set<string>();

  for (const entry of value.split(',')) {
    const host = normalizeAllowedHost(entry);
    if (host !== null && !seen.has(host)) {
      seen.add(host);
      allowedHosts.push(host);
    }
  }

  return allowedHosts;
}

function normalizeAllowedHost(value: string): string | null {
  const candidate = value.trim();
  if (candidate === '' || candidate.includes('*')) {
    return null;
  }

  const isUrl = candidate.includes('://');
  if (
    !isUrl &&
    (candidate.includes('/') ||
      candidate.includes('?') ||
      candidate.includes('#') ||
      candidate.includes('@'))
  ) {
    return null;
  }

  try {
    const url = new URL(isUrl ? candidate : `https://${candidate}`);
    if (
      (url.protocol !== 'https:' && url.protocol !== 'http:') ||
      url.username !== '' ||
      url.password !== '' ||
      !isValidHostname(url.hostname)
    ) {
      return null;
    }

    return url.host.toLowerCase();
  } catch {
    return null;
  }
}

function isValidHostname(hostname: string): boolean {
  const unwrapped =
    hostname.startsWith('[') && hostname.endsWith(']') ? hostname.slice(1, -1) : hostname;

  if (unwrapped.includes(':')) {
    return /^[0-9a-f:.]+$/i.test(unwrapped);
  }

  if (unwrapped.length === 0 || unwrapped.length > 253) {
    return false;
  }

  const labels = unwrapped.split('.');
  return labels.every(
    (label) =>
      label.length > 0 && label.length <= 63 && /^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$/i.test(label),
  );
}

function parseBooleanEnvironmentValue(value: string | undefined, fallback: boolean): boolean {
  switch (value?.trim().toLowerCase()) {
    case '1':
    case 'on':
    case 'true':
    case 'yes':
      return true;
    case '0':
    case 'false':
    case 'no':
    case 'off':
      return false;
    default:
      return fallback;
  }
}

function readImportMetaEnvironment(): ArcadePlatformEnvironment {
  const value: unknown = import.meta.env;
  if (typeof value !== 'object' || value === null) {
    return {};
  }

  const environment = value as Record<string, unknown>;
  return {
    DEV: typeof environment.DEV === 'boolean' ? environment.DEV : undefined,
    PROD: typeof environment.PROD === 'boolean' ? environment.PROD : undefined,
    VITE_ARCADE_PLATFORM: readEnvironmentString(environment.VITE_ARCADE_PLATFORM),
    VITE_BB_ALLOWED_HOSTS: readEnvironmentString(environment.VITE_BB_ALLOWED_HOSTS),
    VITE_BB_HOST_LOCK: readEnvironmentString(environment.VITE_BB_HOST_LOCK),
    VITE_BB_REWARDED_TEST_MODE: readEnvironmentString(environment.VITE_BB_REWARDED_TEST_MODE),
    VITE_BB_SIGNED_HOST_LOCK: readEnvironmentString(environment.VITE_BB_SIGNED_HOST_LOCK),
  };
}

function readEnvironmentString(value: unknown): string | undefined {
  return typeof value === 'string' ? value : undefined;
}

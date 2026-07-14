export const ASSET_MANIFEST = {
  art: {
    logo: '/assets/art/logo.svg',
    field: '/assets/art/field.svg',
    pixelBackground: '/assets/pixel/stadium-field.png',
    quarterback: {
      idle: '/assets/characters/qb-idle.webp',
      aim: '/assets/characters/qb-aim.webp',
      throw: '/assets/characters/qb-throw.webp',
      recovery: '/assets/characters/qb-recovery.webp',
    },
    receiver: {
      run1: {
        left: '/assets/characters/receiver-run-1-left.webp',
        right: '/assets/characters/receiver-run-1-right.webp',
      },
      run2: {
        left: '/assets/characters/receiver-run-2-left.webp',
        right: '/assets/characters/receiver-run-2-right.webp',
      },
      run3: {
        left: '/assets/characters/receiver-run-3-left.webp',
        right: '/assets/characters/receiver-run-3-right.webp',
      },
      run4: {
        left: '/assets/characters/receiver-run-4-left.webp',
        right: '/assets/characters/receiver-run-4-right.webp',
      },
      catch: {
        left: '/assets/characters/receiver-catch-left.webp',
        right: '/assets/characters/receiver-catch-right.webp',
      },
      touchdown: {
        left: '/assets/characters/receiver-touchdown-left.webp',
        right: '/assets/characters/receiver-touchdown-right.webp',
      },
    },
    defender: {
      run1: {
        left: '/assets/characters/defender-run-1-left.webp',
        right: '/assets/characters/defender-run-1-right.webp',
      },
      run2: {
        left: '/assets/characters/defender-run-2-left.webp',
        right: '/assets/characters/defender-run-2-right.webp',
      },
      run3: {
        left: '/assets/characters/defender-run-3-left.webp',
        right: '/assets/characters/defender-run-3-right.webp',
      },
      run4: {
        left: '/assets/characters/defender-run-4-left.webp',
        right: '/assets/characters/defender-run-4-right.webp',
      },
      interception: {
        left: '/assets/characters/defender-interception-left.webp',
        right: '/assets/characters/defender-interception-right.webp',
      },
    },
    football: '/assets/pixel/football.png',
    effects: {
      score: '/assets/art/effect-score.svg',
      completion: '/assets/art/effect-completion.svg',
      touchdown: '/assets/art/effect-touchdown.svg',
      interception: '/assets/art/effect-interception.svg',
    },
    ui: {
      meterFrame: '/assets/art/meter-frame.svg',
      meterFill: '/assets/art/meter-fill.svg',
      multiplier: '/assets/art/multiplier.svg',
      timerWarning: '/assets/art/timer-warning.svg',
      button: '/assets/art/button.svg',
      mute: '/assets/art/icon-mute.svg',
      unmute: '/assets/art/icon-unmute.svg',
      pause: '/assets/art/icon-pause.svg',
      avatarFrame: '/assets/art/avatar-frame.svg',
    },
  },
} as const;

export type AssetImageMap = ReadonlyMap<string, HTMLImageElement>;

const flattenPaths = (value: unknown, result: string[]): void => {
  if (typeof value === 'string') {
    result.push(value);
    return;
  }
  if (value && typeof value === 'object') {
    for (const child of Object.values(value)) flattenPaths(child, result);
  }
};

export const getArtAssetPaths = (): string[] => {
  const paths: string[] = [];
  flattenPaths(ASSET_MANIFEST.art, paths);
  return paths;
};

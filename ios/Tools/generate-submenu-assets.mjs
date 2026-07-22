import { execFileSync } from 'node:child_process';
import { mkdirSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const iosRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const repositoryRoot = path.resolve(iosRoot, '..');
const sourceRoot = path.join(iosRoot, 'AssetSources', 'Submenus');
const catalogRoot = path.join(
  iosRoot,
  'PocketVector',
  'Resources',
  'Assets.xcassets',
);

const assets = [
  ['SubmenuStadiumBackdrop', 'submenu-stadium-backdrop-v1.png', 2532, 1170],
  ['SubmenuBackIcon', 'submenu-back-v1.png', 144, 144],
  ['SubmenuForwardIcon', 'submenu-forward-v1.png', 144, 144],
  ['SubmenuLockIcon', 'submenu-lock-v1.png', 144, 144],
  ['SubmenuSelectedIcon', 'submenu-selected-v1.png', 144, 144],
  ['SubmenuPlayIcon', 'submenu-play-v1.png', 144, 144],
  ['AchievementFirstReadIcon', 'achievement-first-read-v1.png', 384, 384],
  ['AchievementPaydirtIcon', 'achievement-paydirt-v1.png', 384, 384],
  ['AchievementCashTheChargeIcon', 'achievement-cash-charge-v1.png', 384, 384],
  ['AchievementFullRouteTreeIcon', 'achievement-route-tree-v1.png', 384, 384],
  ['AchievementDialedInIcon', 'achievement-dialed-in-v1.png', 384, 384],
  ['AchievementHotHandIcon', 'achievement-hot-hand-v1.png', 384, 384],
  ['AchievementLightUpBoardIcon', 'achievement-light-board-v1.png', 384, 384],
  ['AchievementCenturyConnectionsIcon', 'achievement-century-v1.png', 384, 384],
  ['AchievementPerfectPocketIcon', 'achievement-perfect-pocket-v1.png', 384, 384],
  ['AchievementFranchisePlayerIcon', 'achievement-franchise-player-v1.png', 384, 384],
  ['AchievementOverchargedIcon', 'achievement-overcharged-v1.png', 384, 384],
  ['AchievementDeepThreatIcon', 'achievement-deep-threat-v1.png', 384, 384],
  ['AchievementUntouchableIcon', 'achievement-untouchable-v1.png', 384, 384],
  ['AchievementMaximumOverdriveIcon', 'achievement-maximum-overdrive-v1.png', 384, 384],
  ['SettingsAudioIcon', 'settings-audio-v1.png', 192, 192],
  ['SettingsMusicIcon', 'settings-music-v1.png', 144, 144],
  ['SettingsSFXIcon', 'settings-sfx-v1.png', 144, 144],
  ['SettingsGameplayIcon', 'settings-gameplay-v1.png', 192, 192],
  ['SettingsTutorialIcon', 'settings-tutorial-v1.png', 144, 144],
  ['SettingsPrivacySupportIcon', 'settings-privacy-v1.png', 144, 144],
];

function contents(filename) {
  return `${JSON.stringify({
    images: [{ filename, idiom: 'universal', scale: '1x' }],
    info: { author: 'xcode', version: 1 },
    properties: { 'compression-type': 'lossless' },
  }, null, 2)}\n`;
}

try {
  for (const [assetName, filename, width, height] of assets) {
    const source = path.join(sourceRoot, filename);
    const imageset = path.join(catalogRoot, `${assetName}.imageset`);
    const output = path.join(imageset, filename);
    mkdirSync(imageset, { recursive: true });

    execFileSync(
      'magick',
      [
        source,
        '-filter', 'point',
        '-resize', `${width}x${height}!`,
        '-colorspace', 'sRGB',
        '-depth', '8',
        '-strip',
        output,
      ],
      { stdio: 'inherit' },
    );
    writeFileSync(path.join(imageset, 'Contents.json'), contents(filename));
    console.log(`Generated ${path.relative(repositoryRoot, output)}`);
  }
} catch (error) {
  if (error && typeof error === 'object' && 'code' in error && error.code === 'ENOENT') {
    throw new Error('ImageMagick is required to generate submenu assets.', { cause: error });
  }
  throw error;
}

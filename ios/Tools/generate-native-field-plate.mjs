import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const iosRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const repositoryRoot = path.resolve(iosRoot, '..');
const source = path.join(iosRoot, 'AssetSources', 'Field', 'stadium-field-wide-endzone-v2.png');
const wideOutput = path.join(
  iosRoot,
  'PocketVector',
  'Resources',
  'GameAssets',
  'pixel',
  'stadium-field-wide-endzone-v3.png',
);

// The v2 plate baked the old x = +/-1 sidelines into the turf. The widened
// native projection draws its new boundaries in SpriteKit, so replace only the
// old painted line with same-row turf sampled 24 pixels toward midfield. Using
// a horizontal sample preserves every crossing yard line and the authored
// grass texture while removing the obsolete diagonal and front pylons.
const removeLegacySidelines = [
  'j < 200 || j > 767 ? u :',
  '((j < 235 && i >= 405 && i <= 433) ? u.p{i+32,j} :',
  '((j < 235 && i >= 1295 && i <= 1323) ? u.p{i-32,j} :',
  '((j >= 240 && j <= 300 && i >= 382 && i <= 407) ? u.p{i+64,j} :',
  '((j >= 240 && j <= 300 && i >= 1321 && i <= 1346) ? u.p{i-64,j} :',
  '(abs(i-(508.3-0.3846*j)) < 11 ? u.p{i+24,j} :',
  '(abs(i-(1219.7+0.3846*j)) < 11 ? u.p{i-24,j} : u))))))',
].join(' ');

try {
  execFileSync('magick', [source, '-fx', removeLegacySidelines, '-strip', wideOutput], {
    stdio: 'inherit',
  });
} catch (error) {
  if (error && typeof error === 'object' && 'code' in error && error.code === 'ENOENT') {
    throw new Error('ImageMagick is required. Install it so the `magick` command is available.', {
      cause: error,
    });
  }
  throw error;
}

console.log(`Generated ${path.relative(repositoryRoot, wideOutput)}`);

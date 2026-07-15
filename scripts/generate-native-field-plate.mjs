import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const pixelAssets = path.join(projectRoot, 'public', 'assets', 'pixel');
const artAssets = path.join(projectRoot, 'public', 'assets', 'art');
const source = path.join(pixelAssets, 'stadium-field-wide-endzone-v2.png');
const wideOutput = path.join(pixelAssets, 'stadium-field-wide-endzone-v3.png');
const classicOutput = path.join(pixelAssets, 'stadium-field-endzone-v3.png');
const endZoneOutput = path.join(artAssets, 'endzone-nova-city-native.png');

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
  // Rectify the legacy end-zone quad into the same locked outside-hash
  // perspective used by FieldBoundaryLayout. The transparent top corners let
  // SpriteKit place this exact artwork over the full widened trapezoid.
  execFileSync(
    'magick',
    [
      wideOutput,
      '-crop',
      '937x61+396+230',
      '+repage',
      '(',
      '+clone',
      '-fill',
      'black',
      '-colorize',
      '100',
      '-fill',
      'white',
      '-draw',
      'polygon 24,0 912,0 936,60 0,60',
      ')',
      '-alpha',
      'off',
      '-compose',
      'CopyOpacity',
      '-composite',
      '-virtual-pixel',
      'transparent',
      '-define',
      'distort:viewport=1055x61+0+0',
      '-distort',
      'Perspective',
      '24,0 70,0 912,0 984,0 0,60 0,60 936,60 1054,60',
      '-strip',
      endZoneOutput,
    ],
    { stdio: 'inherit' },
  );
  execFileSync(
    'magick',
    [wideOutput, '-gravity', 'center', '-crop', '1024x768+0+0', '+repage', '-strip', classicOutput],
    { stdio: 'inherit' },
  );
} catch (error) {
  if (error && typeof error === 'object' && 'code' in error && error.code === 'ENOENT') {
    throw new Error('ImageMagick is required. Install it so the `magick` command is available.', {
      cause: error,
    });
  }
  throw error;
}

console.log(`Generated ${path.relative(projectRoot, wideOutput)}`);
console.log(`Generated ${path.relative(projectRoot, classicOutput)}`);
console.log(`Generated ${path.relative(projectRoot, endZoneOutput)}`);

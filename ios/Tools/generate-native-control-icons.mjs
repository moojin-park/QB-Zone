import { execFileSync } from 'node:child_process';
import { rmSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const iosRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const repositoryRoot = path.resolve(iosRoot, '..');
const sourceAssets = path.join(iosRoot, 'AssetSources', 'Controls');
const runtimeAssets = path.join(iosRoot, 'PocketVector', 'Resources', 'GameAssets', 'art');
const iconNames = ['mute', 'unmute', 'pause'];

try {
  for (const iconName of iconNames) {
    const source = path.join(sourceAssets, `icon-${iconName}.svg`);
    const output = path.join(runtimeAssets, `icon-${iconName}-native.png`);
    const temporaryOutput = `${output}.tmp.png`;

    try {
      // CoreSVG preserves the source's transparent canvas and complete cyan
      // strokes. ImageMagick then strips nondeterministic PNG metadata.
      execFileSync('sips', ['-s', 'format', 'png', source, '--out', temporaryOutput], {
        stdio: 'inherit',
      });
      execFileSync('magick', [temporaryOutput, '-depth', '8', '-strip', output], {
        stdio: 'inherit',
      });
    } finally {
      rmSync(temporaryOutput, { force: true });
    }
    console.log(`Generated ${path.relative(repositoryRoot, output)}`);
  }
} catch (error) {
  if (error && typeof error === 'object' && 'code' in error && error.code === 'ENOENT') {
    throw new Error(
      'The macOS `sips` command and ImageMagick are required to generate native icons.',
      { cause: error },
    );
  }
  throw error;
}

import { execFileSync } from 'node:child_process';
import { rmSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const artAssets = path.join(projectRoot, 'public', 'assets', 'art');
const iconNames = ['mute', 'unmute', 'pause'];

try {
  for (const iconName of iconNames) {
    const source = path.join(artAssets, `icon-${iconName}.svg`);
    const output = path.join(artAssets, `icon-${iconName}-native.png`);
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
    console.log(`Generated ${path.relative(projectRoot, output)}`);
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

import { describe, expect, it } from 'vitest';

import { getArtAssetPaths } from '../../src/game/assets/assetManifest';
import { getCharacterAnimationFrame } from '../../src/game/rendering/CanvasRenderer';

describe('character animation frame selection', () => {
  it('walks a four-frame cycle and wraps deterministically', () => {
    expect(getCharacterAnimationFrame(0, 0, 100, 4)).toMatchObject({ frame: 0 });
    expect(getCharacterAnimationFrame(107, 0, 100, 4)).toMatchObject({ frame: 1 });
    expect(getCharacterAnimationFrame(426, 0, 100, 4)).toMatchObject({ frame: 0 });
  });

  it('gives individual actors stable phase offsets', () => {
    const first = getCharacterAnimationFrame(0, 1, 100, 4);
    const second = getCharacterAnimationFrame(0, 2, 100, 4);

    expect(first.frame).toBe(0);
    expect(second.frame).toBe(1);
    expect(getCharacterAnimationFrame(0, 2, 100, 4)).toEqual(second);
  });

  it('loads all four directional run phases for both moving roles', () => {
    const paths = getArtAssetPaths();

    expect(paths).toContain('/assets/characters/receiver-run-4-left.webp');
    expect(paths).toContain('/assets/characters/receiver-run-4-right.webp');
    expect(paths).toContain('/assets/characters/defender-run-4-left.webp');
    expect(paths).toContain('/assets/characters/defender-run-4-right.webp');
  });
});

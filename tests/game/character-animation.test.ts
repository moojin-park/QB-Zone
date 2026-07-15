import { describe, expect, it } from 'vitest';

import { getArtAssetPaths } from '../../src/game/assets/assetManifest';
import {
  getCharacterAnimationFrame,
  getReceiverVisualPose,
  getReceiverVisualSelection,
} from '../../src/game/rendering/CanvasRenderer';

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

  it('holds the catch and touchdown poses before switching caught receivers to carry', () => {
    expect(getReceiverVisualPose({ pose: 'catch', animationMs: 359, hasCaught: true })).toBe(
      'catch',
    );
    expect(getReceiverVisualPose({ pose: 'celebrate', animationMs: 359, hasCaught: true })).toBe(
      'touchdown',
    );
    expect(getReceiverVisualPose({ pose: 'catch', animationMs: 360, hasCaught: true })).toBe(
      'carry',
    );
    expect(getReceiverVisualPose({ pose: 'run', animationMs: 900, hasCaught: false })).toBe('run');
  });

  it('animates caught receivers through all four normal-cadence carry frames', () => {
    const frames = [368, 490, 613, 735].map(
      (animationMs) =>
        getReceiverVisualSelection({
          id: 0,
          pose: 'catch',
          animationMs,
          hasCaught: true,
        }).frame,
    );

    expect(frames).toEqual([3, 0, 1, 2]);
  });

  it('loads all four post-catch carry phases in both directions', () => {
    const paths = getArtAssetPaths();

    for (const suffix of ['', '-2', '-3', '-4']) {
      expect(paths).toContain(`/assets/characters/receiver-carry${suffix}-left.webp`);
      expect(paths).toContain(`/assets/characters/receiver-carry${suffix}-right.webp`);
    }
  });
});

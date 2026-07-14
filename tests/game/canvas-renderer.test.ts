import { afterEach, describe, expect, it, vi } from 'vitest';

import { ASSET_MANIFEST } from '../../src/game/assets/assetManifest';
import { CanvasRenderer } from '../../src/game/rendering/CanvasRenderer';

afterEach(() => {
  vi.unstubAllGlobals();
});

describe('pixel-art canvas rendering', () => {
  it('rebuilds the field cache from the pixel background when assets arrive', () => {
    const mainContext = {
      imageSmoothingEnabled: true,
    } as CanvasRenderingContext2D;
    const fieldContext = {
      imageSmoothingEnabled: true,
      setTransform: vi.fn(),
      clearRect: vi.fn(),
      drawImage: vi.fn(),
    } as unknown as CanvasRenderingContext2D;
    const fieldCanvas = {
      width: 0,
      height: 0,
      getContext: vi.fn(() => fieldContext),
    } as unknown as HTMLCanvasElement;
    vi.stubGlobal('document', {
      createElement: vi.fn(() => fieldCanvas),
    });
    const canvas = {
      getContext: vi.fn(() => mainContext),
    } as unknown as HTMLCanvasElement;
    const background = {} as HTMLImageElement;

    const renderer = new CanvasRenderer(canvas);
    renderer.setAssets(new Map([[ASSET_MANIFEST.art.pixelBackground, background]]));

    expect(mainContext.imageSmoothingEnabled).toBe(false);
    expect(fieldContext.imageSmoothingEnabled).toBe(false);
    expect(fieldContext.drawImage).toHaveBeenCalledWith(background, 0, 0, 1024, 768);
  });
});

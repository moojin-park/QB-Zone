import { getArtAssetPaths, type AssetImageMap } from './assetManifest';

const loadImage = async (path: string): Promise<[string, HTMLImageElement]> =>
  new Promise((resolve, reject) => {
    const image = new Image();
    image.decoding = 'async';
    image.addEventListener('load', () => resolve([path, image]), { once: true });
    image.addEventListener('error', () => reject(new Error(`Could not load ${path}`)), {
      once: true,
    });
    image.src = path;
  });

export interface AssetLoadResult {
  images: AssetImageMap;
  failures: string[];
}

export const loadArtAssets = async (): Promise<AssetLoadResult> => {
  const images = new Map<string, HTMLImageElement>();
  const failures: string[] = [];
  const results = await Promise.allSettled(getArtAssetPaths().map(loadImage));
  for (const result of results) {
    if (result.status === 'fulfilled') images.set(result.value[0], result.value[1]);
    else
      failures.push(result.reason instanceof Error ? result.reason.message : String(result.reason));
  }
  return { images, failures };
};

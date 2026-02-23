import { describe, expect, it } from 'vitest';

import { segmentCircleIntersects } from '../src/game/physics';

describe('segmentCircleIntersects', () => {
  it('returns true when line passes through the circle', () => {
    expect(segmentCircleIntersects(0, 0, 10, 0, 5, 0, 2)).toBe(true);
  });

  it('returns false when line misses the circle', () => {
    expect(segmentCircleIntersects(0, 0, 10, 0, 5, 5, 1)).toBe(false);
  });

  it('returns true on tangent hit', () => {
    expect(segmentCircleIntersects(0, 0, 10, 0, 5, 2, 2)).toBe(true);
  });
});

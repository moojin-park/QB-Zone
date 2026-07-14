import { describe, expect, it } from 'vitest';
import { GAMEPLAY_CONFIG } from '../../src/game/config/gameplayConfig';
import { PointerSampler } from '../../src/game/input/PointerSampler';
import {
  calculateThrowGesture,
  isValidThrowGesture,
  normalizedThrowSpeed,
  type PointerSample,
  type ThrowGesture,
} from '../../src/game/input/gestureMath';

const sample = (x: number, y: number, timestampMs: number): PointerSample => ({
  x,
  y,
  timestampMs,
});

const validGesture = (patch: Partial<ThrowGesture> = {}): ThrowGesture => ({
  start: sample(100, 300, 0),
  release: sample(100, 200, 100),
  samples: [sample(100, 300, 0), sample(100, 200, 100)],
  directionX: 0,
  directionY: -1,
  distancePx: 100,
  durationMs: 100,
  averageSpeedPxPerMs: 1,
  releaseSpeedPxPerMs: 1,
  ...patch,
});

describe('calculateThrowGesture', () => {
  it.each([[[]], [[sample(0, 0, 0)]]])('requires at least two samples', (samples) => {
    expect(calculateThrowGesture(samples)).toBeNull();
  });

  it('derives direction, direct distance, duration, and speed for an upward swipe', () => {
    const gesture = calculateThrowGesture([sample(50, 220, 10), sample(50, 120, 110)]);

    expect(gesture).toMatchObject({
      directionX: 0,
      directionY: -1,
      distancePx: 100,
      durationMs: 100,
      averageSpeedPxPerMs: 1,
      releaseSpeedPxPerMs: 1,
    });
  });

  it('uses the sampled path, not only endpoint distance, for average speed', () => {
    const gesture = calculateThrowGesture([
      sample(0, 100, 0),
      sample(30, 60, 50),
      sample(0, 20, 100),
    ]);

    expect(gesture?.distancePx).toBe(80);
    expect(gesture?.averageSpeedPxPerMs).toBe(1);
  });

  it('weights release speed from the most recent 90 ms window', () => {
    const gesture = calculateThrowGesture([
      sample(0, 100, 0),
      sample(0, 90, 100),
      sample(0, 80, 800),
      sample(0, 0, 850),
    ]);

    expect(gesture?.averageSpeedPxPerMs).toBeCloseTo(100 / 850, 8);
    expect(gesture?.releaseSpeedPxPerMs).toBeCloseTo(1.6, 8);
  });

  it('keeps a jank-spaced mobile swipe valid when pointer-up repeats the last coordinate', () => {
    const gesture = calculateThrowGesture([
      sample(500, 670, 0),
      sample(420, 650, 420),
      sample(340, 630, 840),
      sample(260, 610, 1_260),
      sample(260, 610, 1_300),
    ]);

    expect(gesture?.releaseSpeedPxPerMs).toBeCloseTo(Math.hypot(160, 40) / 880, 8);
    expect(gesture && isValidThrowGesture(gesture)).toBe(true);
  });

  it('keeps a trackpad drag valid after a stationary zero-button release tail', () => {
    const gesture = calculateThrowGesture([
      sample(512, 680, 0),
      sample(510, 670, 400),
      sample(507, 660, 800),
      sample(503, 650, 1_200),
      sample(498, 640, 1_600),
      sample(492, 630, 2_000),
      sample(485, 620, 2_400),
      // Trackpads can repeat the last coordinate while the physical click is
      // released (buttons = 0) and before pointer-up/lost capture settles.
      sample(485, 620, 2_500),
      sample(485, 620, 2_600),
      sample(485, 620, 2_700),
      sample(485, 620, 2_800),
    ]);

    expect(gesture?.release).toEqual(sample(485, 620, 2_800));
    expect(gesture?.releaseSpeedPxPerMs).toBeLessThan(GAMEPLAY_CONFIG.throw.slowSpeedPxPerMs);
    expect(gesture && isValidThrowGesture(gesture)).toBe(true);
    expect(normalizedThrowSpeed(gesture?.releaseSpeedPxPerMs ?? 0)).toBe(0);
  });

  it('handles a stationary gesture without NaN direction values', () => {
    const gesture = calculateThrowGesture([sample(7, 9, 10), sample(7, 9, 10)]);

    expect(gesture).toMatchObject({
      directionX: 0,
      directionY: 0,
      distancePx: 0,
      durationMs: 1,
      averageSpeedPxPerMs: 0,
      releaseSpeedPxPerMs: 0,
    });
  });

  it('returns an independent copy of the input sample list', () => {
    const samples = [sample(0, 100, 0), sample(0, 0, 100)];
    const gesture = calculateThrowGesture(samples);
    samples.push(sample(10, 0, 110));

    expect(gesture?.samples).toHaveLength(2);
    expect(gesture?.release).toEqual(sample(0, 0, 100));
  });
});

describe('throw gesture validity and normalization', () => {
  it('accepts a sufficiently long, fast, upfield gesture', () => {
    expect(isValidThrowGesture(validGesture())).toBe(true);
  });

  it('rejects a gesture below the minimum distance', () => {
    expect(
      isValidThrowGesture(
        validGesture({ distancePx: GAMEPLAY_CONFIG.throw.minimumGestureDistancePx - 0.01 }),
      ),
    ).toBe(false);
  });

  it('accepts a sufficiently long stationary release as a lob', () => {
    const gesture = validGesture({ releaseSpeedPxPerMs: 0 });

    expect(isValidThrowGesture(gesture)).toBe(true);
    expect(normalizedThrowSpeed(gesture.releaseSpeedPxPerMs)).toBe(0);
  });

  it.each([
    ['horizontal', 0],
    ['downfield-screen direction', 0.2],
    ['the exact direction threshold', -0.08],
  ])('rejects %s release direction', (_label, directionY) => {
    expect(isValidThrowGesture(validGesture({ directionY }))).toBe(false);
  });

  it('maps slow and fast configured speeds to zero and one', () => {
    expect(normalizedThrowSpeed(GAMEPLAY_CONFIG.throw.slowSpeedPxPerMs)).toBe(0);
    expect(normalizedThrowSpeed(GAMEPLAY_CONFIG.throw.fastSpeedPxPerMs)).toBe(1);
  });

  it('clamps speeds outside the configured range', () => {
    expect(normalizedThrowSpeed(-100)).toBe(0);
    expect(normalizedThrowSpeed(100)).toBe(1);
  });

  it('preserves continuous values between slow and fast rather than quantizing', () => {
    const midpoint =
      (GAMEPLAY_CONFIG.throw.slowSpeedPxPerMs + GAMEPLAY_CONFIG.throw.fastSpeedPxPerMs) / 2;
    expect(normalizedThrowSpeed(midpoint)).toBeCloseTo(0.5, 10);
  });
});

describe('PointerSampler single-pointer ownership', () => {
  it('starts one pointer and rejects a duplicate concurrent pointer', () => {
    const sampler = new PointerSampler();

    expect(sampler.start(1, sample(0, 100, 0))).toBe(true);
    expect(sampler.start(2, sample(10, 100, 1))).toBe(false);
    expect(sampler.getSamples()).toEqual([sample(0, 100, 0)]);
  });

  it('ignores moves and releases from a non-owning pointer', () => {
    const sampler = new PointerSampler();
    sampler.start(4, sample(0, 100, 0));

    sampler.add(5, sample(0, 80, 10));
    expect(sampler.finish(5, sample(0, 60, 20))).toBeNull();
    expect(sampler.isActive).toBe(true);
    expect(sampler.getSamples()).toEqual([sample(0, 100, 0)]);
  });

  it('finishes once, resets ownership, and prevents a duplicate throw', () => {
    const sampler = new PointerSampler();
    sampler.start(7, sample(0, 100, 0));

    const first = sampler.finish(7, sample(0, 0, 100));
    const duplicate = sampler.finish(7, sample(0, -20, 120));

    expect(first?.distancePx).toBe(100);
    expect(duplicate).toBeNull();
    expect(sampler.isActive).toBe(false);
    expect(sampler.getSamples()).toEqual([]);
  });

  it('finishes a coalesced trackpad drag from its last sample after capture loss', () => {
    const sampler = new PointerSampler();
    sampler.start(17, sample(512, 680, 0));
    sampler.addMany(17, [
      sample(500, 630, 60),
      sample(480, 570, 120),
      sample(452, 500, 180),
      sample(420, 430, 240),
      sample(420, 430, 300),
      sample(420, 430, 360),
    ]);

    // A lost-capture fallback has no new pointer-up coordinate to append.
    const gesture = sampler.finish(17);

    expect(gesture?.release).toEqual(sample(420, 430, 360));
    expect(gesture && isValidThrowGesture(gesture)).toBe(true);
    expect(sampler.isActive).toBe(false);
  });

  it('ignores decreasing timestamps from the active pointer', () => {
    const sampler = new PointerSampler();
    sampler.start(1, sample(0, 100, 100));
    sampler.add(1, sample(0, 80, 90));

    expect(sampler.getSamples()).toEqual([sample(0, 100, 100)]);
  });

  it('retains only the rolling 24 most recent samples', () => {
    const sampler = new PointerSampler();
    sampler.start(1, sample(0, 100, 0));
    for (let index = 1; index <= 30; index += 1) {
      sampler.add(1, sample(index, 100 - index, index));
    }

    expect(sampler.getSamples()).toHaveLength(24);
    expect(sampler.getSamples()[0]).toEqual(sample(0, 100, 0));
    expect(sampler.getSamples().at(-1)).toEqual(sample(30, 70, 30));
  });

  it('keeps the true pointer-down as the destination origin after a long drag', () => {
    const sampler = new PointerSampler();
    sampler.start(1, sample(10, 500, 0));
    for (let index = 1; index <= 40; index += 1) {
      sampler.add(1, sample(10 + index, 500 - index * 5, index * 10));
    }

    const gesture = sampler.finish(1, sample(60, 250, 410));
    expect(gesture?.start).toEqual(sample(10, 500, 0));
    expect(gesture?.distancePx).toBeCloseTo(Math.hypot(50, -250), 8);
  });

  it('only cancels when the owner is canceled, unless cancellation is global', () => {
    const sampler = new PointerSampler();
    sampler.start(3, sample(0, 100, 0));

    sampler.cancel(9);
    expect(sampler.isActive).toBe(true);
    sampler.cancel(3);
    expect(sampler.isActive).toBe(false);

    sampler.start(4, sample(0, 100, 0));
    sampler.cancel();
    expect(sampler.isActive).toBe(false);
  });

  it('allows a new pointer only after the previous gesture has reset', () => {
    const sampler = new PointerSampler();
    sampler.start(1, sample(0, 100, 0));
    sampler.finish(1, sample(0, 0, 100));

    expect(sampler.start(2, sample(10, 100, 110))).toBe(true);
    expect(sampler.isActive).toBe(true);
  });
});

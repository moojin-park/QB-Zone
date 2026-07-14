import { GAMEPLAY_CONFIG } from '../config/gameplayConfig';

export interface PointerSample {
  x: number;
  y: number;
  timestampMs: number;
}

export interface ThrowGesture {
  start: PointerSample;
  release: PointerSample;
  samples: PointerSample[];
  directionX: number;
  directionY: number;
  distancePx: number;
  durationMs: number;
  averageSpeedPxPerMs: number;
  releaseSpeedPxPerMs: number;
}

const distance = (a: PointerSample, b: PointerSample): number => Math.hypot(b.x - a.x, b.y - a.y);

const sampledPathDistance = (samples: readonly PointerSample[]): number => {
  let result = 0;
  for (let index = 1; index < samples.length; index += 1) {
    const previous = samples[index - 1];
    const current = samples[index];
    if (previous && current) result += distance(previous, current);
  }
  return result;
};

const RELEASE_WINDOW_MS = 90;
const MINIMUM_MEANINGFUL_MOVEMENT_PX = 0.5;
const RELEASE_FALLBACK_SAMPLE_COUNT = 3;

const meaningfulMovementSamples = (samples: readonly PointerSample[]): readonly PointerSample[] => {
  const first = samples[0];
  if (!first) return [];

  const result = [first];
  for (let index = 1; index < samples.length; index += 1) {
    const current = samples[index];
    const previousMeaningful = result[result.length - 1];
    if (
      current &&
      previousMeaningful &&
      distance(previousMeaningful, current) >= MINIMUM_MEANINGFUL_MOVEMENT_PX
    ) {
      result.push(current);
    }
  }
  return result;
};

export const calculateThrowGesture = (samples: readonly PointerSample[]): ThrowGesture | null => {
  if (samples.length < 2) return null;
  const start = samples[0];
  const release = samples[samples.length - 1];
  if (!start || !release) return null;

  const durationMs = Math.max(1, release.timestampMs - start.timestampMs);
  const pathDistancePx = sampledPathDistance(samples);

  // Mouse and trackpad releases often repeat the final coordinate several
  // times, especially after the player pauses briefly to lead a receiver.
  // Estimate release velocity from the last real movement while retaining the
  // true pointer-up sample as the destination.
  const movementSamples = meaningfulMovementSamples(samples);
  const movementEnd = movementSamples[movementSamples.length - 1] ?? release;
  const releaseWindowStart = movementEnd.timestampMs - RELEASE_WINDOW_MS;
  let recentSamples = movementSamples.filter((sample) => sample.timestampMs >= releaseWindowStart);
  let releasePath = sampledPathDistance(recentSamples);
  // Busy render loops can space continuous events by more than the velocity
  // window. Fall back to the final two movement segments rather than a tail of
  // duplicate release coordinates.
  if (releasePath < MINIMUM_MEANINGFUL_MOVEMENT_PX && movementSamples.length > 1) {
    recentSamples = movementSamples.slice(-RELEASE_FALLBACK_SAMPLE_COUNT);
    releasePath = sampledPathDistance(recentSamples);
  }
  const releaseStart = recentSamples[0] ?? start;
  const stationaryReleaseDelay = Math.max(
    0,
    Math.min(RELEASE_WINDOW_MS, release.timestampMs - movementEnd.timestampMs),
  );
  const releaseDuration = Math.max(
    1,
    movementEnd.timestampMs - releaseStart.timestampMs + stationaryReleaseDelay,
  );
  const deltaX = release.x - start.x;
  const deltaY = release.y - start.y;
  const directDistance = Math.hypot(deltaX, deltaY);

  return {
    start,
    release,
    samples: [...samples],
    directionX: directDistance === 0 ? 0 : deltaX / directDistance,
    directionY: directDistance === 0 ? 0 : deltaY / directDistance,
    distancePx: directDistance,
    durationMs,
    averageSpeedPxPerMs: pathDistancePx / durationMs,
    releaseSpeedPxPerMs:
      recentSamples.length >= 2 ? releasePath / releaseDuration : pathDistancePx / durationMs,
  };
};

export const isValidThrowGesture = (gesture: ThrowGesture): boolean =>
  gesture.distancePx >= GAMEPLAY_CONFIG.throw.minimumGestureDistancePx &&
  gesture.directionY < -0.08;

export const normalizedThrowSpeed = (releaseSpeedPxPerMs: number): number => {
  const { slowSpeedPxPerMs, fastSpeedPxPerMs } = GAMEPLAY_CONFIG.throw;
  return Math.max(
    0,
    Math.min(1, (releaseSpeedPxPerMs - slowSpeedPxPerMs) / (fastSpeedPxPerMs - slowSpeedPxPerMs)),
  );
};

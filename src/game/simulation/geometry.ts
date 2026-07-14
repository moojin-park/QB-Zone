export interface Point2D {
  x: number;
  y: number;
}

export interface CircleShape {
  kind: 'circle';
  center: Point2D;
  radius: number;
}

export interface CapsuleShape {
  kind: 'capsule';
  start: Point2D;
  end: Point2D;
  radius: number;
}

export type CollisionShape = CircleShape | CapsuleShape;

const EPSILON = 1e-9;

const firstCircleIntersectionProgress = (
  start: Point2D,
  end: Point2D,
  center: Point2D,
  radius: number,
): number | null => {
  const offsetX = start.x - center.x;
  const offsetY = start.y - center.y;
  const radiusSquared = radius * radius;
  if (offsetX * offsetX + offsetY * offsetY <= radiusSquared) return 0;

  const deltaX = end.x - start.x;
  const deltaY = end.y - start.y;
  const a = deltaX * deltaX + deltaY * deltaY;
  if (a <= EPSILON) return null;
  const b = 2 * (offsetX * deltaX + offsetY * deltaY);
  const c = offsetX * offsetX + offsetY * offsetY - radiusSquared;
  const discriminant = b * b - 4 * a * c;
  if (discriminant < 0) return null;
  const root = (-b - Math.sqrt(discriminant)) / (2 * a);
  return root >= 0 && root <= 1 ? root : null;
};

const firstRectangleIntersectionProgress = (
  start: Point2D,
  end: Point2D,
  minimum: Point2D,
  maximum: Point2D,
): number | null => {
  let entry = 0;
  let exit = 1;
  for (const axis of ['x', 'y'] as const) {
    const delta = end[axis] - start[axis];
    if (Math.abs(delta) <= EPSILON) {
      if (start[axis] < minimum[axis] || start[axis] > maximum[axis]) return null;
      continue;
    }
    const first = (minimum[axis] - start[axis]) / delta;
    const second = (maximum[axis] - start[axis]) / delta;
    entry = Math.max(entry, Math.min(first, second));
    exit = Math.min(exit, Math.max(first, second));
    if (entry > exit) return null;
  }
  return entry >= 0 && entry <= 1 ? entry : null;
};

export const firstSegmentShapeIntersectionProgress = (
  start: Point2D,
  end: Point2D,
  shape: CollisionShape,
  expansion = 0,
): number | null => {
  const radius = Math.max(0, shape.radius + expansion);
  if (shape.kind === 'circle') {
    return firstCircleIntersectionProgress(start, end, shape.center, radius);
  }

  const axisX = shape.end.x - shape.start.x;
  const axisY = shape.end.y - shape.start.y;
  const length = Math.hypot(axisX, axisY);
  if (length <= EPSILON) {
    return firstCircleIntersectionProgress(start, end, shape.start, radius);
  }
  const unitX = axisX / length;
  const unitY = axisY / length;
  const toLocal = (point: Point2D): Point2D => {
    const x = point.x - shape.start.x;
    const y = point.y - shape.start.y;
    return { x: x * unitX + y * unitY, y: -x * unitY + y * unitX };
  };
  const localStart = toLocal(start);
  const localEnd = toLocal(end);
  const candidates = [
    firstRectangleIntersectionProgress(
      localStart,
      localEnd,
      { x: 0, y: -radius },
      { x: length, y: radius },
    ),
    firstCircleIntersectionProgress(localStart, localEnd, { x: 0, y: 0 }, radius),
    firstCircleIntersectionProgress(localStart, localEnd, { x: length, y: 0 }, radius),
  ].filter((value): value is number => value !== null);
  return candidates.length > 0 ? Math.min(...candidates) : null;
};

export const distancePointToSegmentSquared = (
  point: Point2D,
  start: Point2D,
  end: Point2D,
): number => {
  const dx = end.x - start.x;
  const dy = end.y - start.y;
  const lengthSquared = dx * dx + dy * dy;
  if (lengthSquared === 0) return (point.x - start.x) ** 2 + (point.y - start.y) ** 2;
  const t = Math.max(
    0,
    Math.min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared),
  );
  const closestX = start.x + dx * t;
  const closestY = start.y + dy * t;
  return (point.x - closestX) ** 2 + (point.y - closestY) ** 2;
};

const orientation = (a: Point2D, b: Point2D, c: Point2D): number =>
  (b.y - a.y) * (c.x - b.x) - (b.x - a.x) * (c.y - b.y);

const segmentsIntersect = (a: Point2D, b: Point2D, c: Point2D, d: Point2D): boolean => {
  const first = orientation(a, b, c);
  const second = orientation(a, b, d);
  const third = orientation(c, d, a);
  const fourth = orientation(c, d, b);
  return first * second < 0 && third * fourth < 0;
};

export const distanceSegmentToSegmentSquared = (
  a: Point2D,
  b: Point2D,
  c: Point2D,
  d: Point2D,
): number => {
  if (segmentsIntersect(a, b, c, d)) return 0;
  return Math.min(
    distancePointToSegmentSquared(a, c, d),
    distancePointToSegmentSquared(b, c, d),
    distancePointToSegmentSquared(c, a, b),
    distancePointToSegmentSquared(d, a, b),
  );
};

export const segmentIntersectsShape = (
  start: Point2D,
  end: Point2D,
  shape: CollisionShape,
  expansion = 0,
): boolean => {
  return firstSegmentShapeIntersectionProgress(start, end, shape, expansion) !== null;
};

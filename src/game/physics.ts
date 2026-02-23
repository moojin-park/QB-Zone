export function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value));
}

export function lerp(a: number, b: number, t: number): number {
  return a + (b - a) * t;
}

export function segmentCircleIntersects(
  ax: number,
  az: number,
  bx: number,
  bz: number,
  cx: number,
  cz: number,
  radius: number
): boolean {
  const abx = bx - ax;
  const abz = bz - az;
  const acx = cx - ax;
  const acz = cz - az;
  const abLenSq = abx * abx + abz * abz;

  if (abLenSq <= Number.EPSILON) {
    const dx = ax - cx;
    const dz = az - cz;
    return dx * dx + dz * dz <= radius * radius;
  }

  const projected = (acx * abx + acz * abz) / abLenSq;
  const t = clamp(projected, 0, 1);
  const nearestX = ax + abx * t;
  const nearestZ = az + abz * t;
  const dx = nearestX - cx;
  const dz = nearestZ - cz;

  return dx * dx + dz * dz <= radius * radius;
}

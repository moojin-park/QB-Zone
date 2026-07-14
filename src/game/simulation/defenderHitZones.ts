import type { CollisionShape } from './geometry';
import { firstSegmentShapeIntersectionProgress } from './geometry';

export type DefenderHitZoneId =
  | 'head-valid'
  | 'head-top-pass-through'
  | 'left-arm-valid'
  | 'right-arm-valid'
  | 'left-hand-pass-through'
  | 'right-hand-pass-through'
  | 'torso-valid'
  | 'hips-valid'
  | 'left-lower-leg-pass-through'
  | 'right-lower-leg-pass-through'
  | 'left-foot-pass-through'
  | 'right-foot-pass-through';

export interface DefenderHitZone {
  id: DefenderHitZoneId;
  interceptsBall: boolean;
  shape: CollisionShape;
}

export const createDefenderHitZones = (): readonly DefenderHitZone[] =>
  [
    {
      id: 'head-valid',
      interceptsBall: true,
      shape: { kind: 'circle', center: { x: 0, y: 0.78 }, radius: 0.13 },
    },
    {
      id: 'head-top-pass-through',
      interceptsBall: false,
      shape: {
        kind: 'capsule',
        start: { x: -0.08, y: 0.93 },
        end: { x: 0.08, y: 0.93 },
        radius: 0.07,
      },
    },
    {
      id: 'left-arm-valid',
      interceptsBall: true,
      shape: {
        kind: 'capsule',
        start: { x: -0.16, y: 0.67 },
        end: { x: -0.34, y: 0.46 },
        radius: 0.075,
      },
    },
    {
      id: 'right-arm-valid',
      interceptsBall: true,
      shape: {
        kind: 'capsule',
        start: { x: 0.16, y: 0.67 },
        end: { x: 0.34, y: 0.46 },
        radius: 0.075,
      },
    },
    {
      id: 'left-hand-pass-through',
      interceptsBall: false,
      shape: { kind: 'circle', center: { x: -0.39, y: 0.4 }, radius: 0.09 },
    },
    {
      id: 'right-hand-pass-through',
      interceptsBall: false,
      shape: { kind: 'circle', center: { x: 0.39, y: 0.4 }, radius: 0.09 },
    },
    {
      id: 'torso-valid',
      interceptsBall: true,
      shape: { kind: 'capsule', start: { x: 0, y: 0.67 }, end: { x: 0, y: 0.4 }, radius: 0.17 },
    },
    {
      id: 'hips-valid',
      interceptsBall: true,
      shape: {
        kind: 'capsule',
        start: { x: -0.11, y: 0.34 },
        end: { x: 0.11, y: 0.34 },
        radius: 0.12,
      },
    },
    {
      id: 'left-lower-leg-pass-through',
      interceptsBall: false,
      shape: {
        kind: 'capsule',
        start: { x: -0.11, y: 0.28 },
        end: { x: -0.16, y: 0.09 },
        radius: 0.07,
      },
    },
    {
      id: 'right-lower-leg-pass-through',
      interceptsBall: false,
      shape: {
        kind: 'capsule',
        start: { x: 0.11, y: 0.28 },
        end: { x: 0.16, y: 0.09 },
        radius: 0.07,
      },
    },
    {
      id: 'left-foot-pass-through',
      interceptsBall: false,
      shape: {
        kind: 'capsule',
        start: { x: -0.19, y: 0.05 },
        end: { x: -0.08, y: 0.05 },
        radius: 0.06,
      },
    },
    {
      id: 'right-foot-pass-through',
      interceptsBall: false,
      shape: {
        kind: 'capsule',
        start: { x: 0.08, y: 0.05 },
        end: { x: 0.19, y: 0.05 },
        radius: 0.06,
      },
    },
  ] as const;

export const hitTestDefenderLocal = (
  previous: { x: number; y: number },
  current: { x: number; y: number },
  ballRadius = 0.035,
  zones: readonly DefenderHitZone[] = createDefenderHitZones(),
): DefenderHitZone | null => {
  const contacts = zones
    .map((zone) => ({
      zone,
      progress: firstSegmentShapeIntersectionProgress(previous, current, zone.shape, ballRadius),
    }))
    .filter(
      (contact): contact is { zone: DefenderHitZone; progress: number } =>
        contact.progress !== null,
    )
    .sort((first, second) => first.progress - second.progress);
  let lastMaskingZone: DefenderHitZone | null = null;
  for (const validContact of contacts.filter((contact) => contact.zone.interceptsBall)) {
    const contactPoint = {
      x: previous.x + (current.x - previous.x) * validContact.progress,
      y: previous.y + (current.y - previous.y) * validContact.progress,
    };
    const overlappingPassThrough = zones.find(
      (zone) =>
        !zone.interceptsBall &&
        firstSegmentShapeIntersectionProgress(
          contactPoint,
          contactPoint,
          zone.shape,
          ballRadius,
        ) !== null,
    );
    if (!overlappingPassThrough) return validContact.zone;
    lastMaskingZone = overlappingPassThrough;
  }
  return lastMaskingZone ?? contacts[0]?.zone ?? null;
};

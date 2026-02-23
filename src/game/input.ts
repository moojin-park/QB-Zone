import { createProjection } from './render';
import type { AimPreview, ThrowIntent } from './types';

export interface InputController {
  getAimPreview: () => AimPreview;
  consumeThrowIntent: () => ThrowIntent | null;
  destroy: () => void;
}

interface Size {
  width: number;
  height: number;
}

export function createInputController(
  canvas: HTMLCanvasElement,
  getSize: () => Size
): InputController {
  let pointerId: number | null = null;
  let pendingThrow: ThrowIntent | null = null;
  let aim: AimPreview = {
    active: false,
    startX: 0,
    startY: 0,
    currentX: 0,
    currentY: 0,
    targetDepth: null,
    targetX: 0
  };

  const updateAimTarget = (): void => {
    if (!aim.active) {
      return;
    }

    const size = getSize();
    const projection = createProjection(size.width, size.height);
    const targetDepth = projection.nearestDepthForScreenY(aim.currentY);
    const targetX = projection.screenXToWorldXAtDepth(aim.currentX, targetDepth);

    aim = {
      ...aim,
      targetDepth,
      targetX
    };
  };

  const toLocalPoint = (event: PointerEvent): { x: number; y: number } => {
    const rect = canvas.getBoundingClientRect();
    return {
      x: event.clientX - rect.left,
      y: event.clientY - rect.top
    };
  };

  const onPointerDown = (event: PointerEvent): void => {
    if (pointerId !== null) {
      return;
    }

    pointerId = event.pointerId;
    canvas.setPointerCapture(pointerId);
    const point = toLocalPoint(event);
    aim = {
      active: true,
      startX: point.x,
      startY: point.y,
      currentX: point.x,
      currentY: point.y,
      targetDepth: null,
      targetX: 0
    };
    updateAimTarget();
  };

  const onPointerMove = (event: PointerEvent): void => {
    if (!aim.active || pointerId !== event.pointerId) {
      return;
    }

    const point = toLocalPoint(event);
    aim = {
      ...aim,
      currentX: point.x,
      currentY: point.y
    };
    updateAimTarget();
  };

  const finishPointer = (event: PointerEvent): void => {
    if (!aim.active || pointerId !== event.pointerId) {
      return;
    }

    const point = toLocalPoint(event);
    aim = {
      ...aim,
      currentX: point.x,
      currentY: point.y
    };
    updateAimTarget();

    if (aim.targetDepth) {
      pendingThrow = {
        targetDepth: aim.targetDepth,
        targetX: aim.targetX
      };
    }

    canvas.releasePointerCapture(event.pointerId);
    pointerId = null;
    aim = {
      ...aim,
      active: false
    };
  };

  canvas.addEventListener('pointerdown', onPointerDown);
  canvas.addEventListener('pointermove', onPointerMove);
  canvas.addEventListener('pointerup', finishPointer);
  canvas.addEventListener('pointercancel', finishPointer);

  return {
    getAimPreview: () => aim,
    consumeThrowIntent: () => {
      const value = pendingThrow;
      pendingThrow = null;
      return value;
    },
    destroy: () => {
      canvas.removeEventListener('pointerdown', onPointerDown);
      canvas.removeEventListener('pointermove', onPointerMove);
      canvas.removeEventListener('pointerup', finishPointer);
      canvas.removeEventListener('pointercancel', finishPointer);
    }
  };
}

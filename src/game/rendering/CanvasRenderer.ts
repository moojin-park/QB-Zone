import { ASSET_MANIFEST, type AssetImageMap } from '../assets/assetManifest';
import { DEFAULT_BALL_RADIUS_PX, GAMEPLAY_CONFIG, getLaneConfig } from '../config/gameplayConfig';
import { VISUAL_CONFIG } from '../config/visualConfig';
import type { GameState, ReceiverState, ScreenPoint } from '../state/GameState';
import { createDefenderHitZones } from '../simulation/defenderHitZones';
import { createTrajectoryParameters, getTrajectoryPosition } from '../simulation/trajectory';
import { renderField, renderFieldWarning } from './FieldRenderer';
import {
  actorScaleAtDepth,
  halfFieldWidthAtDepth,
  screenToFieldWorld,
  type Projection,
  worldToScreen,
} from './projection';

export interface AimPreview {
  start: ScreenPoint;
  current: ScreenPoint;
  releaseSpeedPxPerMs: number;
  valid: boolean;
}

const AIM_TRAJECTORY_SEGMENTS = 36;
const RECEIVER_FRAME_DURATION_MS = 115;
const DEFENDER_FRAME_DURATION_MS = 145;
const RUN_FRAME_COUNT = 4;
const RECEIVER_ACTION_HOLD_MS = 360;
const DEFENDER_ACTION_HOLD_MS = 340;
const PIXEL_ART_GRID_PX = 2;
const BALL_END_ON_DIAMETER_PX = 38;

const snapToPixelArtGrid = (value: number): number =>
  Math.round(value / PIXEL_ART_GRID_PX) * PIXEL_ART_GRID_PX;

const snapPixelArtSize = (value: number): number =>
  Math.max(PIXEL_ART_GRID_PX, snapToPixelArtGrid(value));

export interface CharacterAnimationFrame {
  frame: number;
  cycleProgress: number;
}

export type ReceiverVisualPose = 'run' | 'catch' | 'carry' | 'touchdown';

export const getReceiverVisualPose = (
  receiver: Pick<ReceiverState, 'pose' | 'animationMs' | 'hasCaught'>,
): ReceiverVisualPose => {
  if (receiver.pose === 'catch' && receiver.animationMs < RECEIVER_ACTION_HOLD_MS) {
    return 'catch';
  }
  if (receiver.pose === 'celebrate' && receiver.animationMs < RECEIVER_ACTION_HOLD_MS) {
    return 'touchdown';
  }
  return receiver.hasCaught ? 'carry' : 'run';
};

export const getCharacterAnimationFrame = (
  animationMs: number,
  entityId: number,
  frameDurationMs: number,
  frameCount: number,
): CharacterAnimationFrame => {
  const safeFrameCount = Math.max(1, Math.floor(frameCount));
  const safeFrameDuration = Math.max(1, frameDurationMs);
  const cadenceScale = 0.94 + ((Math.abs(entityId) * 37) % 13) * 0.01;
  const cycleDuration = safeFrameDuration * safeFrameCount;
  const phaseMs =
    (Math.max(0, animationMs) * cadenceScale + Math.abs(entityId) * 71) % cycleDuration;
  return {
    frame: Math.floor(phaseMs / safeFrameDuration),
    cycleProgress: phaseMs / cycleDuration,
  };
};

export interface ReceiverVisualSelection {
  pose: ReceiverVisualPose;
  frame: number;
}

export const getReceiverVisualSelection = (
  receiver: Pick<ReceiverState, 'id' | 'pose' | 'animationMs' | 'hasCaught'>,
): ReceiverVisualSelection => {
  const pose = getReceiverVisualPose(receiver);
  const frame =
    pose === 'run' || pose === 'carry'
      ? getCharacterAnimationFrame(
          receiver.animationMs,
          receiver.id,
          RECEIVER_FRAME_DURATION_MS,
          RUN_FRAME_COUNT,
        ).frame
      : 0;
  return { pose, frame };
};

export const getAimTrajectoryScreenPoints = (
  aim: AimPreview,
  projection: Projection,
): ScreenPoint[] => {
  const start = GAMEPLAY_CONFIG.quarterbackStart;
  const target = screenToFieldWorld(aim.current, projection);
  const trajectory = createTrajectoryParameters(start, target, aim.releaseSpeedPxPerMs);

  return Array.from({ length: AIM_TRAJECTORY_SEGMENTS + 1 }, (_, index) => {
    const position = getTrajectoryPosition(
      start,
      trajectory.end,
      trajectory.arcHeight,
      index / AIM_TRAJECTORY_SEGMENTS,
    );
    return worldToScreen(position, projection);
  });
};

const drawImageCentered = (
  context: CanvasRenderingContext2D,
  image: HTMLImageElement | undefined,
  x: number,
  y: number,
  width: number,
  height: number,
): void => {
  if (!image) return;
  const snappedWidth = snapPixelArtSize(width);
  const snappedHeight = snapPixelArtSize(height);
  const centerX = snapToPixelArtGrid(x);
  const bottom = snapToPixelArtGrid(y);
  context.drawImage(
    image,
    centerX - snappedWidth / 2,
    bottom - snappedHeight,
    snappedWidth,
    snappedHeight,
  );
};

export class CanvasRenderer {
  private readonly context: CanvasRenderingContext2D;
  private readonly fieldCanvas: HTMLCanvasElement;
  private readonly fieldContext: CanvasRenderingContext2D;
  private images: AssetImageMap = new Map();
  private projection: Projection = {
    width: GAMEPLAY_CONFIG.classicLogicalWidth,
    height: GAMEPLAY_CONFIG.logicalHeight,
  };

  public constructor(private readonly canvas: HTMLCanvasElement) {
    const context = canvas.getContext('2d');
    if (!context) throw new Error('Canvas 2D is unavailable.');
    this.context = context;
    this.context.imageSmoothingEnabled = false;
    this.fieldCanvas = document.createElement('canvas');
    const fieldContext = this.fieldCanvas.getContext('2d');
    if (!fieldContext) throw new Error('Field cache canvas is unavailable.');
    this.fieldContext = fieldContext;
    this.fieldContext.imageSmoothingEnabled = false;
  }

  public getProjection(): Projection {
    return this.projection;
  }

  public setAssets(images: AssetImageMap): void {
    this.images = images;
    this.rebuildFieldCache();
  }

  public resize(devicePixelRatio: number): void {
    const logicalWidth = GAMEPLAY_CONFIG.classicLogicalWidth;
    this.projection = { width: logicalWidth, height: GAMEPLAY_CONFIG.logicalHeight };
    this.canvas.width = Math.round(logicalWidth * devicePixelRatio);
    this.canvas.height = Math.round(GAMEPLAY_CONFIG.logicalHeight * devicePixelRatio);
    this.context.setTransform(devicePixelRatio, 0, 0, devicePixelRatio, 0, 0);
    this.context.imageSmoothingEnabled = false;
    this.rebuildFieldCache();
  }

  public render(state: GameState, aim: AimPreview | null): void {
    const context = this.context;
    context.clearRect(0, 0, this.projection.width, this.projection.height);
    this.drawField(state);
    this.drawEntities(state);
    this.drawQuarterback(state, aim);
    if (state.ball) this.drawAim(state, null);
    this.drawBall(state);
    if (aim) this.drawAim(state, aim);
    if (state.debug.showTrajectory && state.ball) this.drawTrajectory(state.ball);
    if (state.debug.showCatchZones) this.drawCatchZones(state);
    if (state.debug.showDefenderHitZones) this.drawDefenderZones(state);
  }

  private getImage(path: string): HTMLImageElement | undefined {
    return this.images.get(path);
  }

  private drawField(state: GameState): void {
    this.context.drawImage(this.fieldCanvas, 0, 0, this.projection.width, this.projection.height);
    const warningActive =
      state.remainingMs <= GAMEPLAY_CONFIG.timerWarningMs && state.phase === 'playing';
    const warningPulse = warningActive ? 0.62 + Math.sin(state.elapsedGameplayMs / 140) * 0.38 : 0;
    if (warningPulse > 0) renderFieldWarning(this.context, this.projection, warningPulse);
  }

  private rebuildFieldCache(): void {
    this.fieldCanvas.width = this.projection.width;
    this.fieldCanvas.height = this.projection.height;
    this.fieldContext.setTransform(1, 0, 0, 1, 0, 0);
    this.fieldContext.imageSmoothingEnabled = false;
    this.fieldContext.clearRect(0, 0, this.projection.width, this.projection.height);
    const pixelBackground = this.getImage(ASSET_MANIFEST.art.pixelBackground);
    if (pixelBackground) {
      this.fieldContext.drawImage(
        pixelBackground,
        0,
        0,
        this.projection.width,
        this.projection.height,
      );
    } else {
      renderField(this.fieldContext, this.projection);
    }
  }

  private drawEntities(state: GameState): void {
    const ordered = [
      ...state.receivers.map((receiver) => ({
        kind: 'receiver' as const,
        depth: getLaneConfig(receiver.laneId).normalizedDepth,
        entity: receiver,
      })),
      ...state.defenders.map((defender) => ({
        kind: 'defender' as const,
        depth: defender.depth,
        entity: defender,
      })),
    ].sort((a, b) => b.depth - a.depth);

    for (const entry of ordered) {
      const scale = actorScaleAtDepth(entry.depth);
      if (entry.kind === 'receiver') {
        const receiver = entry.entity;
        const direction = receiver.direction < 0 ? 'left' : 'right';
        const point = worldToScreen(
          { x: receiver.x, depth: entry.depth, height: 0 },
          this.projection,
        );
        const visual = getReceiverVisualSelection(receiver);
        const runFrames = [
          ASSET_MANIFEST.art.receiver.run1[direction],
          ASSET_MANIFEST.art.receiver.run2[direction],
          ASSET_MANIFEST.art.receiver.run3[direction],
          ASSET_MANIFEST.art.receiver.run4[direction],
        ] as const;
        const carryFrames = ASSET_MANIFEST.art.receiver.carry[direction];
        const path =
          visual.pose === 'catch'
            ? ASSET_MANIFEST.art.receiver.catch[direction]
            : visual.pose === 'touchdown'
              ? ASSET_MANIFEST.art.receiver.touchdown[direction]
              : visual.pose === 'carry'
                ? (carryFrames[visual.frame] ?? carryFrames[0])
                : (runFrames[visual.frame] ?? runFrames[0]);
        drawImageCentered(
          this.context,
          this.getImage(path),
          point.x,
          point.y + 10,
          270 * scale,
          360 * scale,
        );
      } else {
        const defender = entry.entity;
        const direction = defender.direction < 0 ? 'left' : 'right';
        const point = worldToScreen(
          { x: defender.x, depth: defender.depth, height: 0 },
          this.projection,
        );
        const animation = getCharacterAnimationFrame(
          defender.animationMs,
          defender.id,
          DEFENDER_FRAME_DURATION_MS,
          RUN_FRAME_COUNT,
        );
        const runFrames = [
          ASSET_MANIFEST.art.defender.run1[direction],
          ASSET_MANIFEST.art.defender.run2[direction],
          ASSET_MANIFEST.art.defender.run3[direction],
          ASSET_MANIFEST.art.defender.run4[direction],
        ] as const;
        const showInterception =
          defender.pose === 'intercept' && defender.animationMs < DEFENDER_ACTION_HOLD_MS;
        const path = showInterception
          ? ASSET_MANIFEST.art.defender.interception[direction]
          : (runFrames[animation.frame] ?? runFrames[0]);
        drawImageCentered(
          this.context,
          this.getImage(path),
          point.x,
          point.y + 10,
          270 * scale,
          360 * scale,
        );
      }
    }
  }

  private drawQuarterback(state: GameState, aim: AimPreview | null): void {
    const path = aim
      ? ASSET_MANIFEST.art.quarterback.aim
      : state.ball && state.ball.elapsedMs < 180
        ? ASSET_MANIFEST.art.quarterback.throw
        : state.ball && state.ball.elapsedMs < 520
          ? ASSET_MANIFEST.art.quarterback.recovery
          : ASSET_MANIFEST.art.quarterback.idle;
    const baselineY = this.projection.height + 330;
    drawImageCentered(
      this.context,
      this.getImage(path),
      this.projection.width / 2,
      baselineY,
      438,
      584,
    );
  }

  private drawBall(state: GameState): void {
    if (!state.ball) return;
    const point = worldToScreen(state.ball.current, this.projection);
    const scale = actorScaleAtDepth(state.ball.current.depth);
    const radiusScale = state.ball.radiusPx / DEFAULT_BALL_RADIUS_PX;
    const image = this.getImage(ASSET_MANIFEST.art.football);
    if (!image) return;
    const x = snapToPixelArtGrid(point.x);
    const y = snapToPixelArtGrid(point.y);
    // The football's rear end faces the quarterback/camera. Rotating a square,
    // end-on sprite reads as a longitudinal spiral instead of a side-on tumble.
    const diameter = snapPixelArtSize(BALL_END_ON_DIAMETER_PX * scale * radiusScale);
    this.context.save();
    this.context.translate(x, y);
    this.context.rotate(state.ball.spinRadians);
    this.context.shadowColor = 'rgba(0, 0, 0, 0.45)';
    this.context.shadowBlur = 0;
    this.context.shadowOffsetX = PIXEL_ART_GRID_PX;
    this.context.shadowOffsetY = PIXEL_ART_GRID_PX;
    this.context.drawImage(image, -diameter / 2, -diameter / 2, diameter, diameter);
    this.context.restore();
  }

  private drawAim(state: GameState, aim: AimPreview | null): void {
    const marker = aim?.current ?? state.ball?.aimMarker ?? null;
    if (!marker) return;
    const context = this.context;
    const size = aim ? 24 : 18;
    const highContrast = state.settings.highContrastAim;
    context.save();
    if (aim && Math.hypot(aim.current.x - aim.start.x, aim.current.y - aim.start.y) >= 8) {
      const points = getAimTrajectoryScreenPoints(aim, this.projection);
      const trailBlock = highContrast ? 8 : 6;
      for (let index = 2; index < points.length - 1; index += 3) {
        const point = points[index];
        if (!point) continue;
        const x = snapToPixelArtGrid(point.x) - trailBlock / 2;
        const y = snapToPixelArtGrid(point.y) - trailBlock / 2;
        context.fillStyle = 'rgba(2, 8, 18, 0.82)';
        context.fillRect(x - 2, y - 2, trailBlock + 4, trailBlock + 4);
        context.fillStyle = aim.valid ? '#3cc6dc' : '#f4bc35';
        context.fillRect(x, y, trailBlock, trailBlock);
      }
    }

    const markerBlock = highContrast ? 6 : 4;
    const markerX = snapToPixelArtGrid(marker.x);
    const markerY = snapToPixelArtGrid(marker.y);
    const markerColor = aim?.valid === false ? VISUAL_CONFIG.colors.gold : '#e94b35';
    const paintMarker = (blockSize: number, color: string): void => {
      context.fillStyle = color;
      for (let offset = -size; offset <= size; offset += markerBlock) {
        context.fillRect(
          markerX + offset - blockSize / 2,
          markerY + offset - blockSize / 2,
          blockSize,
          blockSize,
        );
        context.fillRect(
          markerX + offset - blockSize / 2,
          markerY - offset - blockSize / 2,
          blockSize,
          blockSize,
        );
      }
    };
    paintMarker(markerBlock + 4, 'rgba(2, 8, 18, 0.86)');
    paintMarker(markerBlock, markerColor);
    context.restore();
  }

  private drawTrajectory(ball: NonNullable<GameState['ball']>): void {
    const context = this.context;
    context.save();
    context.beginPath();
    for (let index = 0; index <= 32; index += 1) {
      const position = getTrajectoryPosition(ball.start, ball.end, ball.arcHeight, index / 32);
      const screen = worldToScreen(position, this.projection);
      if (index === 0) context.moveTo(screen.x, screen.y);
      else context.lineTo(screen.x, screen.y);
    }
    context.strokeStyle = VISUAL_CONFIG.colors.cyan;
    context.setLineDash([6, 6]);
    context.lineWidth = 2;
    context.stroke();
    context.restore();
  }

  private drawCatchZones(state: GameState): void {
    const context = this.context;
    context.save();
    context.strokeStyle = 'rgba(66, 232, 255, 0.9)';
    context.lineWidth = 2;
    for (const receiver of state.receivers) {
      const lane = getLaneConfig(receiver.laneId);
      const top = worldToScreen(
        { x: receiver.x, depth: lane.normalizedDepth, height: 0.92 },
        this.projection,
      );
      const bottom = worldToScreen(
        { x: receiver.x, depth: lane.normalizedDepth, height: 0.08 },
        this.projection,
      );
      const halfCatchWidth =
        lane.catchWidth * halfFieldWidthAtDepth(this.projection, lane.normalizedDepth);
      context.strokeRect(top.x - halfCatchWidth, top.y, halfCatchWidth * 2, bottom.y - top.y);
    }
    context.restore();
  }

  private drawDefenderZones(state: GameState): void {
    const context = this.context;
    for (const defender of state.defenders) {
      const ground = worldToScreen(
        { x: defender.x, depth: defender.depth, height: 0 },
        this.projection,
      );
      const scale = actorScaleAtDepth(defender.depth);
      const localWorldWidth =
        GAMEPLAY_CONFIG.defenderWidthWorld * halfFieldWidthAtDepth(this.projection, defender.depth);
      for (const zone of createDefenderHitZones()) {
        context.save();
        context.translate(ground.x, ground.y);
        context.scale(localWorldWidth, -VISUAL_CONFIG.field.actorHeightPx * scale);
        const zoneColor = zone.interceptsBall ? '#ff5d73' : '#42e8ff';
        context.lineCap = 'round';
        if (zone.shape.kind === 'circle') {
          context.beginPath();
          context.arc(zone.shape.center.x, zone.shape.center.y, zone.shape.radius, 0, Math.PI * 2);
          context.fillStyle = `${zoneColor}42`;
          context.fill();
          context.lineWidth = 0.014;
          context.strokeStyle = zoneColor;
          context.stroke();
        } else {
          context.beginPath();
          context.moveTo(zone.shape.start.x, zone.shape.start.y);
          context.lineTo(zone.shape.end.x, zone.shape.end.y);
          context.lineWidth = zone.shape.radius * 2;
          context.strokeStyle = `${zoneColor}42`;
          context.stroke();
          context.lineWidth = 0.014;
          context.strokeStyle = zoneColor;
          context.stroke();
        }
        context.restore();
      }
    }

    if (state.ball) {
      const previous = worldToScreen(state.ball.previous, this.projection);
      const current = worldToScreen(state.ball.current, this.projection);
      context.save();
      context.strokeStyle = VISUAL_CONFIG.colors.gold;
      context.fillStyle = VISUAL_CONFIG.colors.gold;
      context.lineWidth = 2;
      context.setLineDash([4, 4]);
      context.beginPath();
      context.moveTo(previous.x, previous.y);
      context.lineTo(current.x, current.y);
      context.stroke();
      context.setLineDash([]);
      context.beginPath();
      context.arc(previous.x, previous.y, state.ball.radiusPx, 0, Math.PI * 2);
      context.stroke();
      context.beginPath();
      context.arc(current.x, current.y, state.ball.radiusPx, 0, Math.PI * 2);
      context.stroke();
      context.font = '800 11px system-ui, sans-serif';
      context.fillText('PREV', previous.x + 15, previous.y - 10);
      context.fillText('NOW', current.x + 15, current.y - 10);
      context.restore();
    }

    if (state.debug.lastCollisionPoint) {
      const collision = worldToScreen(state.debug.lastCollisionPoint, this.projection);
      context.save();
      context.strokeStyle = VISUAL_CONFIG.colors.gold;
      context.fillStyle = VISUAL_CONFIG.colors.gold;
      context.lineWidth = 3;
      context.beginPath();
      context.moveTo(collision.x - 10, collision.y);
      context.lineTo(collision.x + 10, collision.y);
      context.moveTo(collision.x, collision.y - 10);
      context.lineTo(collision.x, collision.y + 10);
      context.stroke();
      context.font = '900 12px system-ui, sans-serif';
      context.fillText(
        state.debug.lastCollisionKind === 'defender' ? 'INTERCEPTION POINT' : 'CATCH POINT',
        collision.x + 14,
        collision.y - 12,
      );
      context.restore();
    }
  }
}

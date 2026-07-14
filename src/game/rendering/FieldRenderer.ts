import { groundYAtDepth, halfFieldWidthAtDepth, type Projection } from './projection';

export interface FieldRenderOptions {
  /** Normalized 0-1 urgency supplied by the game timer. */
  warningPulse?: number;
}

interface TurfFleck {
  readonly xRatio: number;
  readonly depth: number;
  readonly opacity: number;
  readonly length: number;
  readonly light: boolean;
}

interface CrowdMember {
  readonly xRatio: number;
  readonly yRatio: number;
  readonly scale: number;
  readonly color: string;
}

const TURF_COLORS = {
  far: '#07533f',
  middle: '#0c8156',
  near: '#19aa69',
  stripe: '#77d99d',
  line: '#effff3',
  endZoneFar: '#0b2e6d',
  endZoneNear: '#1268a4',
} as const;

const CROWD_COLORS = ['#52d6d0', '#ffca66', '#ff6f68', '#b7c5ff', '#6d91e8'] as const;
/**
 * Field stripes stop before the end zone. The former 0.72 and 0.82 stripes
 * either duplicated the goal line or crossed the painted end-zone band.
 */
export const FIELD_YARD_LINE_DEPTHS = [0.12, 0.24, 0.36, 0.48, 0.6] as const;
const END_ZONE_BACK_DEPTH = 1;
const END_ZONE_FRONT_DEPTH = 0.72;
const END_ZONE_VISUAL_CENTER_DEPTH = 0.8;
const END_ZONE_TEXT_SCALE_Y = 0.58;
const MOWING_BAND_COUNT = 10;

const clamp01 = (value: number): number => Math.max(0, Math.min(1, value));

const makeDeterministicValues = (count: number, seed: number): number[] => {
  const values: number[] = [];
  let state = seed >>> 0;
  for (let index = 0; index < count; index += 1) {
    state = (Math.imul(state, 1_664_525) + 1_013_904_223) >>> 0;
    values.push(state / 4_294_967_296);
  }
  return values;
};

const createTurfFlecks = (): readonly TurfFleck[] => {
  const random = makeDeterministicValues(180 * 5, 0x4e43_4649);
  const flecks: TurfFleck[] = [];
  for (let index = 0; index < 180; index += 1) {
    const offset = index * 5;
    const xRatio = random[offset] ?? 0.5;
    const depth = 0.03 + (random[offset + 1] ?? 0.5) * 0.91;
    const opacity = 0.025 + (random[offset + 2] ?? 0.5) * 0.055;
    const length = 0.7 + (random[offset + 3] ?? 0.5) * 2.1;
    const light = (random[offset + 4] ?? 0.5) > 0.48;
    flecks.push({ xRatio, depth, opacity, length, light });
  }
  return flecks;
};

const createCrowd = (): readonly CrowdMember[] => {
  const random = makeDeterministicValues(92 * 4, 0x5354_4144);
  const crowd: CrowdMember[] = [];
  for (let index = 0; index < 92; index += 1) {
    const offset = index * 4;
    const colorIndex = Math.floor((random[offset + 3] ?? 0) * CROWD_COLORS.length);
    crowd.push({
      xRatio: random[offset] ?? 0.5,
      yRatio: random[offset + 1] ?? 0.5,
      scale: 0.65 + (random[offset + 2] ?? 0.5) * 0.7,
      color: CROWD_COLORS[colorIndex] ?? CROWD_COLORS[0],
    });
  }
  return crowd;
};

const TURF_FLECKS = createTurfFlecks();
const CROWD = createCrowd();

const drawStadiumLights = (
  context: CanvasRenderingContext2D,
  projection: Projection,
  fieldTopY: number,
): void => {
  const { width } = projection;
  const lightY = Math.max(28, fieldTopY - 137);
  for (let index = -2; index <= 2; index += 1) {
    const x = width / 2 + index * width * 0.085;
    const glow = context.createRadialGradient(x, lightY, 0, x, lightY, width * 0.075);
    glow.addColorStop(0, 'rgba(226, 255, 250, 0.48)');
    glow.addColorStop(0.14, 'rgba(129, 232, 255, 0.18)');
    glow.addColorStop(1, 'rgba(64, 128, 190, 0)');
    context.fillStyle = glow;
    context.fillRect(x - width * 0.08, lightY - 52, width * 0.16, 104);

    context.fillStyle = 'rgba(230, 255, 251, 0.9)';
    context.beginPath();
    context.arc(x, lightY, 3.4, 0, Math.PI * 2);
    context.fill();
  }
};

const drawGoalpost = (
  context: CanvasRenderingContext2D,
  projection: Projection,
  fieldTopY: number,
): void => {
  const { width } = projection;
  const centerX = width / 2;
  const halfGoalWidth = width * 0.088;
  const crossbarY = fieldTopY - 51;
  const uprightTopY = Math.max(22, fieldTopY - 151);

  context.save();
  context.strokeStyle = 'rgba(4, 17, 35, 0.52)';
  context.lineWidth = 9;
  context.lineCap = 'round';
  context.beginPath();
  context.moveTo(centerX - halfGoalWidth + 3, uprightTopY + 4);
  context.lineTo(centerX - halfGoalWidth + 3, crossbarY + 4);
  context.lineTo(centerX + halfGoalWidth + 3, crossbarY + 4);
  context.lineTo(centerX + halfGoalWidth + 3, uprightTopY + 4);
  context.moveTo(centerX + 3, crossbarY + 4);
  context.lineTo(centerX + 3, fieldTopY + 15);
  context.stroke();

  context.strokeStyle = '#d9fff4';
  context.lineWidth = 5;
  context.beginPath();
  context.moveTo(centerX - halfGoalWidth, uprightTopY);
  context.lineTo(centerX - halfGoalWidth, crossbarY);
  context.lineTo(centerX + halfGoalWidth, crossbarY);
  context.lineTo(centerX + halfGoalWidth, uprightTopY);
  context.moveTo(centerX, crossbarY);
  context.lineTo(centerX, fieldTopY + 13);
  context.stroke();

  const padWidth = Math.max(13, width * 0.017);
  const padGradient = context.createLinearGradient(centerX - padWidth, 0, centerX + padWidth, 0);
  padGradient.addColorStop(0, '#082958');
  padGradient.addColorStop(0.5, '#167bb3');
  padGradient.addColorStop(1, '#082958');
  context.fillStyle = padGradient;
  context.beginPath();
  context.roundRect(centerX - padWidth / 2, fieldTopY - 15, padWidth, 38, 5);
  context.fill();
  context.restore();
};

const drawStadium = (
  context: CanvasRenderingContext2D,
  projection: Projection,
  fieldTopY: number,
): void => {
  const { width } = projection;
  const stadiumGradient = context.createLinearGradient(0, 0, 0, fieldTopY);
  stadiumGradient.addColorStop(0, '#050b19');
  stadiumGradient.addColorStop(0.42, '#091b33');
  stadiumGradient.addColorStop(1, '#0d3151');
  context.fillStyle = stadiumGradient;
  context.fillRect(0, 0, width, fieldTopY + 2);

  drawStadiumLights(context, projection, fieldTopY);

  const standsTop = Math.max(68, fieldTopY - 106);
  const standsHeight = Math.max(54, fieldTopY - standsTop - 19);
  context.fillStyle = '#071a2b';
  context.fillRect(0, standsTop, width, standsHeight);

  context.save();
  context.beginPath();
  context.rect(0, standsTop, width, standsHeight);
  context.clip();
  for (const member of CROWD) {
    const x = member.xRatio * width;
    const y = standsTop + member.yRatio * standsHeight;
    const radius = 1.8 * member.scale;
    context.globalAlpha = 0.38 + member.yRatio * 0.24;
    context.fillStyle = member.color;
    context.beginPath();
    context.arc(x, y, radius, 0, Math.PI * 2);
    context.fill();
    context.fillRect(x - radius * 1.3, y + radius * 0.7, radius * 2.6, radius * 2.9);
  }
  context.restore();

  context.fillStyle = '#0b3d67';
  context.fillRect(0, fieldTopY - 22, width, 24);
  context.fillStyle = 'rgba(83, 207, 231, 0.34)';
  context.fillRect(0, fieldTopY - 22, width, 3);

  drawGoalpost(context, projection, fieldTopY);
};

const drawTurf = (
  context: CanvasRenderingContext2D,
  projection: Projection,
  fieldTopY: number,
): void => {
  const { width, height } = projection;
  const turfGradient = context.createLinearGradient(0, fieldTopY, 0, height);
  turfGradient.addColorStop(0, TURF_COLORS.far);
  turfGradient.addColorStop(0.33, TURF_COLORS.middle);
  turfGradient.addColorStop(1, TURF_COLORS.near);
  context.fillStyle = turfGradient;
  context.fillRect(0, fieldTopY, width, height - fieldTopY);

  for (let index = 0; index < MOWING_BAND_COUNT; index += 1) {
    const nearDepth = index / MOWING_BAND_COUNT;
    const farDepth = (index + 1) / MOWING_BAND_COUNT;
    const nearY = groundYAtDepth(nearDepth);
    const farY = groundYAtDepth(farDepth);
    context.fillStyle = index % 2 === 0 ? 'rgba(215, 255, 221, 0.022)' : 'rgba(1, 42, 34, 0.03)';
    context.fillRect(0, Math.min(nearY, farY), width, Math.abs(nearY - farY));
  }

  for (const fleck of TURF_FLECKS) {
    const y = groundYAtDepth(fleck.depth);
    const perspectiveScale = 0.45 + (1 - fleck.depth) * 0.9;
    context.globalAlpha = fleck.opacity;
    context.fillStyle = fleck.light ? '#d6ffe0' : '#004c3d';
    context.fillRect(
      fleck.xRatio * width,
      y,
      fleck.length * perspectiveScale,
      Math.max(0.55, perspectiveScale * 0.8),
    );
  }
  context.globalAlpha = 1;

  const pool = context.createRadialGradient(
    width / 2,
    height * 0.53,
    width * 0.03,
    width / 2,
    height * 0.53,
    width * 0.61,
  );
  pool.addColorStop(0, 'rgba(168, 255, 207, 0.11)');
  pool.addColorStop(0.55, 'rgba(80, 216, 165, 0.045)');
  pool.addColorStop(1, 'rgba(0, 41, 38, 0)');
  context.fillStyle = pool;
  context.fillRect(0, fieldTopY, width, height - fieldTopY);
};

const drawPylon = (
  context: CanvasRenderingContext2D,
  x: number,
  baselineY: number,
  scale: number,
): void => {
  const width = 9 * scale;
  const height = 25 * scale;
  context.save();
  context.translate(x, baselineY);
  context.fillStyle = 'rgba(0, 22, 24, 0.22)';
  context.beginPath();
  context.ellipse(2, 2, width * 1.35, width * 0.46, 0, 0, Math.PI * 2);
  context.fill();

  const pylonGradient = context.createLinearGradient(-width / 2, 0, width / 2, 0);
  pylonGradient.addColorStop(0, '#d33937');
  pylonGradient.addColorStop(0.5, '#ff8252');
  pylonGradient.addColorStop(1, '#b62731');
  context.fillStyle = pylonGradient;
  context.beginPath();
  context.roundRect(-width / 2, -height, width, height, width * 0.35);
  context.fill();
  context.restore();
};

export interface EndZoneLayout {
  readonly backDepth: number;
  readonly frontDepth: number;
  readonly visualCenterDepth: number;
  readonly backY: number;
  readonly frontY: number;
  readonly centerY: number;
  readonly visualCenterY: number;
  readonly bandHeight: number;
  readonly backHalfWidth: number;
  readonly frontHalfWidth: number;
  readonly textFontSize: number;
  readonly textScaleY: number;
}

/**
 * Returns the deterministic projected end-zone geometry used by the renderer.
 * The 0.8 visual-center landmark sits within one pixel of the band's screen
 * midpoint at the canonical 4:3 projection.
 */
export const getEndZoneLayout = (projection: Projection): EndZoneLayout => {
  const { width } = projection;
  const backY = groundYAtDepth(END_ZONE_BACK_DEPTH, projection);
  const frontY = groundYAtDepth(END_ZONE_FRONT_DEPTH, projection);
  const bandHeight = Math.abs(frontY - backY);
  const projectedBackHalf = halfFieldWidthAtDepth(projection, END_ZONE_BACK_DEPTH) * 1.23;
  const projectedFrontHalf = halfFieldWidthAtDepth(projection, END_ZONE_FRONT_DEPTH) * 1.34;

  return {
    backDepth: END_ZONE_BACK_DEPTH,
    frontDepth: END_ZONE_FRONT_DEPTH,
    visualCenterDepth: END_ZONE_VISUAL_CENTER_DEPTH,
    backY,
    frontY,
    centerY: (backY + frontY) / 2,
    visualCenterY: groundYAtDepth(END_ZONE_VISUAL_CENTER_DEPTH, projection),
    bandHeight,
    backHalfWidth: Math.max(width * 0.41, projectedBackHalf),
    frontHalfWidth: Math.max(width * 0.55, projectedFrontHalf),
    textFontSize: Math.min(width * 0.036, (bandHeight * 0.42) / END_ZONE_TEXT_SCALE_Y),
    textScaleY: END_ZONE_TEXT_SCALE_Y,
  };
};

const drawEndZone = (context: CanvasRenderingContext2D, projection: Projection): void => {
  const { width } = projection;
  const centerX = width / 2;
  const layout = getEndZoneLayout(projection);
  const {
    backY,
    frontY,
    centerY,
    bandHeight,
    backHalfWidth,
    frontHalfWidth,
    textFontSize,
    textScaleY,
  } = layout;

  context.save();
  context.beginPath();
  context.moveTo(centerX - backHalfWidth, backY);
  context.lineTo(centerX + backHalfWidth, backY);
  context.lineTo(centerX + frontHalfWidth, frontY);
  context.lineTo(centerX - frontHalfWidth, frontY);
  context.closePath();
  context.clip();

  const endZoneGradient = context.createLinearGradient(0, backY, 0, frontY);
  endZoneGradient.addColorStop(0, TURF_COLORS.endZoneFar);
  endZoneGradient.addColorStop(1, TURF_COLORS.endZoneNear);
  context.fillStyle = endZoneGradient;
  context.fillRect(0, Math.min(backY, frontY), width, Math.abs(frontY - backY));

  context.fillStyle = 'rgba(102, 220, 255, 0.08)';
  for (let index = -8; index <= 8; index += 2) {
    context.save();
    context.translate(centerX + index * width * 0.07, centerY);
    context.rotate(-0.27);
    context.fillRect(-width * 0.022, -bandHeight, width * 0.044, bandHeight * 2);
    context.restore();
  }
  context.restore();

  context.save();
  context.translate(centerX, centerY);
  context.scale(1, textScaleY);
  context.fillStyle = 'rgba(225, 251, 255, 0.88)';
  context.font = `italic 900 ${textFontSize}px system-ui, sans-serif`;
  context.textAlign = 'center';
  context.textBaseline = 'middle';
  context.fillText('NOVA CITY', 0, 0);
  context.restore();

  context.strokeStyle = 'rgba(242, 255, 246, 0.92)';
  context.lineWidth = 3.2;
  context.beginPath();
  context.moveTo(Math.max(-8, centerX - frontHalfWidth), frontY);
  context.lineTo(Math.min(width + 8, centerX + frontHalfWidth), frontY);
  context.stroke();

  drawPylon(context, centerX - backHalfWidth, backY + 2, 0.66);
  drawPylon(context, centerX + backHalfWidth, backY + 2, 0.66);
  drawPylon(context, Math.max(13, centerX - frontHalfWidth), frontY + 2, 0.9);
  drawPylon(context, Math.min(width - 13, centerX + frontHalfWidth), frontY + 2, 0.9);
};

const fieldHalfWidthForLine = (projection: Projection, depth: number): number => {
  const projected = halfFieldWidthAtDepth(projection, depth) * 1.23;
  const edgeFilling = projection.width * (0.43 + (1 - depth) * 0.22);
  return Math.max(projected, edgeFilling);
};

const drawYardLines = (context: CanvasRenderingContext2D, projection: Projection): void => {
  const { width } = projection;
  const centerX = width / 2;
  context.save();
  context.lineCap = 'butt';

  for (const depth of FIELD_YARD_LINE_DEPTHS) {
    const y = groundYAtDepth(depth);
    const halfWidth = fieldHalfWidthForLine(projection, depth);
    const startX = Math.max(-10, centerX - halfWidth);
    const endX = Math.min(width + 10, centerX + halfWidth);
    const perspective = 1 - depth;

    context.strokeStyle = `rgba(239, 255, 243, ${0.67 + perspective * 0.2})`;
    context.lineWidth = 1.25 + perspective * 2.8;
    context.beginPath();
    context.moveTo(startX, y);
    context.lineTo(endX, y);
    context.stroke();

    const hashHalfLength = 6 + perspective * 13;
    const hashOffset = Math.min(width * 0.22, halfWidth * 0.38);
    context.lineWidth = 1 + perspective * 1.8;
    for (const direction of [-1, 1] as const) {
      const hashX = centerX + direction * hashOffset;
      context.beginPath();
      context.moveTo(hashX - hashHalfLength, y);
      context.lineTo(hashX + hashHalfLength, y);
      context.stroke();
    }
  }
  context.restore();
};

const drawMidfieldMark = (context: CanvasRenderingContext2D, projection: Projection): void => {
  const { width, height } = projection;
  const centerY = groundYAtDepth(0.52) + height * 0.012;
  const markWidth = Math.min(width * 0.66, 700);
  const markHeight = height * 0.145;

  context.save();
  context.translate(width / 2, centerY);
  context.transform(markWidth / 640, 0, -0.08, markHeight / 180, 0, 0);
  context.globalAlpha = 0.88;

  context.fillStyle = 'rgba(2, 42, 55, 0.27)';
  context.beginPath();
  context.ellipse(5, 18, 304, 74, 0, 0, Math.PI * 2);
  context.fill();

  context.fillStyle = '#0b4b83';
  context.beginPath();
  context.moveTo(-300, 12);
  context.bezierCurveTo(-210, -68, -58, -80, 112, -31);
  context.bezierCurveTo(-38, -29, -132, 2, -245, 60);
  context.closePath();
  context.fill();

  context.fillStyle = '#32d6dc';
  context.beginPath();
  context.moveTo(-284, -5);
  context.bezierCurveTo(-182, -59, -46, -56, 117, -18);
  context.bezierCurveTo(-40, -14, -139, 14, -238, 48);
  context.closePath();
  context.fill();

  context.fillStyle = '#b8fff3';
  context.beginPath();
  context.moveTo(-220, 2);
  context.bezierCurveTo(-135, -29, -31, -31, 105, -11);
  context.bezierCurveTo(-30, -4, -111, 15, -176, 32);
  context.closePath();
  context.fill();

  const cometGradient = context.createRadialGradient(144, -25, 9, 166, -4, 78);
  cometGradient.addColorStop(0, '#fff7b0');
  cometGradient.addColorStop(0.44, '#ffd15e');
  cometGradient.addColorStop(1, '#ef654f');
  context.fillStyle = cometGradient;
  context.beginPath();
  context.ellipse(151, -3, 76, 62, -0.16, 0, Math.PI * 2);
  context.fill();

  context.strokeStyle = 'rgba(135, 62, 57, 0.34)';
  context.lineWidth = 6;
  context.beginPath();
  context.ellipse(130, -25, 17, 10, -0.35, 0, Math.PI * 2);
  context.moveTo(184, 13);
  context.ellipse(184, 13, 11, 7, 0.2, 0, Math.PI * 2);
  context.stroke();

  context.textAlign = 'center';
  context.textBaseline = 'middle';
  context.font = 'italic 900 126px system-ui, sans-serif';
  context.lineJoin = 'round';
  context.strokeStyle = '#062d57';
  context.lineWidth = 17;
  context.strokeText('NC', -34, -2);
  context.fillStyle = '#f2fff7';
  context.fillText('NC', -34, -2);
  context.strokeStyle = 'rgba(39, 211, 221, 0.82)';
  context.lineWidth = 4;
  context.strokeText('NC', -34, -2);

  context.font = 'italic 900 30px system-ui, sans-serif';
  context.letterSpacing = '7px';
  context.fillStyle = '#062d57';
  context.fillText('COMETS', -37, 62);
  context.restore();
};

const drawDepthLighting = (
  context: CanvasRenderingContext2D,
  projection: Projection,
  fieldTopY: number,
): void => {
  const { width, height } = projection;
  const horizonShade = context.createLinearGradient(0, fieldTopY, 0, height * 0.58);
  horizonShade.addColorStop(0, 'rgba(1, 24, 39, 0.2)');
  horizonShade.addColorStop(1, 'rgba(1, 24, 39, 0)');
  context.fillStyle = horizonShade;
  context.fillRect(0, fieldTopY, width, height * 0.58 - fieldTopY);

  const sideShade = context.createLinearGradient(0, 0, width, 0);
  sideShade.addColorStop(0, 'rgba(0, 23, 30, 0.15)');
  sideShade.addColorStop(0.19, 'rgba(0, 23, 30, 0)');
  sideShade.addColorStop(0.81, 'rgba(0, 23, 30, 0)');
  sideShade.addColorStop(1, 'rgba(0, 23, 30, 0.15)');
  context.fillStyle = sideShade;
  context.fillRect(0, fieldTopY, width, height - fieldTopY);
};

const drawWarningPulse = (
  context: CanvasRenderingContext2D,
  projection: Projection,
  amount: number,
): void => {
  if (amount <= 0) return;
  const { width, height } = projection;
  const outerBand = 12;
  const innerBand = 24;
  context.fillStyle = `rgba(235, 55, 46, ${amount * 0.13})`;
  context.fillRect(0, 0, width, outerBand);
  context.fillRect(0, height - outerBand, width, outerBand);
  context.fillRect(0, outerBand, outerBand, height - outerBand * 2);
  context.fillRect(width - outerBand, outerBand, outerBand, height - outerBand * 2);

  context.fillStyle = `rgba(235, 55, 46, ${amount * 0.055})`;
  context.fillRect(outerBand, outerBand, width - outerBand * 2, innerBand);
  context.fillRect(outerBand, height - outerBand - innerBand, width - outerBand * 2, innerBand);
  context.fillRect(
    outerBand,
    outerBand + innerBand,
    innerBand,
    height - outerBand * 2 - innerBand * 2,
  );
  context.fillRect(
    width - outerBand - innerBand,
    outerBand + innerBand,
    innerBand,
    height - outerBand * 2 - innerBand * 2,
  );
};

/**
 * Draws the fixed-camera stadium and field beneath all gameplay entities.
 * The layer is intentionally stateless; all visual texture is generated from
 * module-level seeded constants so repeated renders are deterministic.
 */
export const renderField = (
  context: CanvasRenderingContext2D,
  projection: Projection,
  options: FieldRenderOptions = {},
): void => {
  const fieldTopY = groundYAtDepth(1);
  context.save();
  drawStadium(context, projection, fieldTopY);
  drawTurf(context, projection, fieldTopY);
  drawEndZone(context, projection);
  drawYardLines(context, projection);
  drawMidfieldMark(context, projection);
  drawDepthLighting(context, projection, fieldTopY);
  drawWarningPulse(context, projection, clamp01(options.warningPulse ?? 0));
  context.restore();
};

export const renderFieldWarning = (
  context: CanvasRenderingContext2D,
  projection: Projection,
  amount: number,
): void => {
  context.save();
  drawWarningPulse(context, projection, clamp01(amount));
  context.restore();
};

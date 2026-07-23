import { execFileSync } from 'node:child_process';
import {
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import os from 'node:os';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const iosRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const repositoryRoot = path.resolve(iosRoot, '..');
const sourceRoot = path.join(iosRoot, 'AssetSources', 'Field');
const runtimeRoot = path.join(
  iosRoot,
  'PocketVector',
  'Resources',
  'GameAssets',
  'pixel',
);
const neutralSource = path.join(sourceRoot, 'stadium-field-neutral-v1.png');
const layerSpecPath = path.join(sourceRoot, 'field-layers-v1.json');
const markingsSource = path.join(sourceRoot, 'field-markings-v1.png');
const distressSource = path.join(sourceRoot, 'field-paint-distress-mask-v1.png');
const neutralOutput = path.join(runtimeRoot, 'stadium-field-neutral-v1.png');
const markingsOutput = path.join(runtimeRoot, 'field-markings-v1.png');
const compatibilityOutput = path.join(runtimeRoot, 'stadium-field-wide-endzone-v3.png');
const sourceTeamsRoot = path.join(sourceRoot, 'teams');
const runtimeTeamsRoot = path.join(runtimeRoot, 'teams');
const tempRoot = mkdtempSync(path.join(os.tmpdir(), 'pocket-vector-field-'));

function runMagick(args) {
  try {
    execFileSync('magick', args, { stdio: 'inherit' });
  } catch (error) {
    if (error && typeof error === 'object' && 'code' in error && error.code === 'ENOENT') {
      throw new Error('ImageMagick is required. Install it so the `magick` command is available.', {
        cause: error,
      });
    }
    throw error;
  }
}

function renderSvg(name, svg, output) {
  const source = path.join(tempRoot, `${name}.svg`);
  writeFileSync(source, svg);
  mkdirSync(path.dirname(output), { recursive: true });
  runMagick([
    '-background',
    'none',
    source,
    '-colorspace',
    'sRGB',
    '-strip',
    output,
  ]);
}

function copyPng(source, output, alpha) {
  mkdirSync(path.dirname(output), { recursive: true });
  const alphaArguments = alpha ? [] : ['-alpha', 'off'];
  runMagick([
    source,
    '-colorspace',
    'sRGB',
    ...alphaArguments,
    '-strip',
    output,
  ]);
}

function applyDistress(source, mask, output) {
  mkdirSync(path.dirname(output), { recursive: true });
  runMagick([
    source,
    '(',
    mask,
    '-alpha',
    'copy',
    ')',
    '-compose',
    'DstIn',
    '-composite',
    '-colorspace',
    'sRGB',
    '-strip',
    output,
  ]);
}

function makeRandom(seed) {
  let state = seed >>> 0;
  return () => {
    state ^= state << 13;
    state ^= state >>> 17;
    state ^= state << 5;
    return (state >>> 0) / 0x100000000;
  };
}

function pointString(points) {
  return points.map(([x, y]) => `${x.toFixed(3)},${y.toFixed(3)}`).join(' ');
}

function buildDistressHoles(seed, bounds, count) {
  const random = makeRandom(seed);
  const holes = [];
  for (let index = 0; index < count; index += 1) {
    const width = 1 + Math.floor(random() * 3);
    const height = 1 + Math.floor(random() * 2);
    const x = bounds.x + Math.floor(random() * Math.max(1, bounds.width - width));
    const y = bounds.y + Math.floor(random() * Math.max(1, bounds.height - height));
    holes.push(`<rect x="${x}" y="${y}" width="${width}" height="${height}" fill="black"/>`);
  }
  return holes.join('');
}

function halfWidth(spec, y) {
  const projection = spec.projection;
  return projection.farHalfWidth
    + (projection.nearHalfWidth - projection.farHalfWidth)
      * ((y - projection.horizonY) / (projection.nearGroundY - projection.horizonY));
}

function boundaryPoint(spec, side, y) {
  return [spec.projection.centerX + side * halfWidth(spec, y), y];
}

function svgDocument(spec, body, definitions = '') {
  return [
    `<svg xmlns="http://www.w3.org/2000/svg" width="${spec.canvas.width}" height="${spec.canvas.height}" viewBox="0 0 ${spec.canvas.width} ${spec.canvas.height}">`,
    '<defs>',
    definitions,
    '</defs>',
    body,
    '</svg>',
  ].join('');
}

function fieldMarkingsSvg(spec) {
  const { centerX, endZoneBackY, endZoneFrontY, yardLines } = spec.projection;
  const leftBack = boundaryPoint(spec, -1, endZoneBackY);
  const rightBack = boundaryPoint(spec, 1, endZoneBackY);
  const leftFront = boundaryPoint(spec, -1, endZoneFrontY);
  const rightFront = boundaryPoint(spec, 1, endZoneFrontY);
  const sideExitY = spec.projection.horizonY
    + (centerX - spec.projection.farHalfWidth)
      * (spec.projection.nearGroundY - spec.projection.horizonY)
      / (spec.projection.nearHalfWidth - spec.projection.farHalfWidth);
  const lineDefinitions = [
    { start: leftBack, end: [0, sideExitY], width: 5 },
    { start: rightBack, end: [spec.canvas.width, sideExitY], width: 5 },
    { start: leftFront, end: rightFront, width: 4 },
    ...yardLines.map(({ y, width }) => ({
      start: boundaryPoint(spec, -1, y),
      end: boundaryPoint(spec, 1, y),
      width,
    })),
  ];

  const backLeftEnd = [centerX - 16, endZoneBackY];
  const backRightStart = [centerX + 16, endZoneBackY];
  const backSegments = [
    { start: leftBack, end: backLeftEnd, width: 3 },
    { start: backRightStart, end: rightBack, width: 3 },
  ];
  const allLines = [...backSegments, ...lineDefinitions];
  const shadowLines = allLines.map(({ start, end, width }) => (
    `<line x1="${start[0].toFixed(3)}" y1="${start[1].toFixed(3)}" x2="${end[0].toFixed(3)}" y2="${end[1].toFixed(3)}" stroke="#02181F" stroke-opacity="0.42" stroke-width="${width + 3}"/>`
  )).join('');
  const chalkLines = allLines.map(({ start, end, width }) => (
    `<line x1="${start[0].toFixed(3)}" y1="${start[1].toFixed(3)}" x2="${end[0].toFixed(3)}" y2="${end[1].toFixed(3)}" stroke="#ECF1DC" stroke-opacity="0.86" stroke-width="${width}"/>`
  )).join('');

  const hashBounds = [endZoneFrontY, ...yardLines.map(({ y }) => y), spec.canvas.height];
  const hashLines = [];
  for (let section = 0; section < hashBounds.length - 1; section += 1) {
    const startY = hashBounds[section];
    const endY = hashBounds[section + 1];
    for (let division = 1; division <= 3; division += 1) {
      const y = startY + (endY - startY) * division / 4;
      const projectedHalfWidth = halfWidth(spec, y);
      const hashOffset = projectedHalfWidth * 0.48;
      const length = 11 + Math.max(0, y - endZoneFrontY) * 0.055;
      const width = Math.max(2, Math.round(2 + (y - endZoneFrontY) / 115));
      for (const side of [-1, 1]) {
        const x = centerX + side * hashOffset;
        hashLines.push(
          `<line x1="${(x - length / 2).toFixed(3)}" y1="${y.toFixed(3)}" x2="${(x + length / 2).toFixed(3)}" y2="${y.toFixed(3)}" stroke="#ECF1DC" stroke-opacity="0.82" stroke-width="${width}"/>`,
        );
      }
    }
  }

  return svgDocument(
    spec,
    `<g fill="none" stroke-linecap="butt" shape-rendering="crispEdges">${shadowLines}${chalkLines}${hashLines.join('')}</g>`,
  );
}

function emblemPrimitiveSvg(primitive, palette) {
  const color = palette[primitive.role];
  const point = ([x, y]) => [x * 1000, (1 - y) * 1000];
  const dotStroke = (points, lineWidth) => {
    const radius = lineWidth * 500;
    const dots = [];
    for (let index = 0; index < points.length - 1; index += 1) {
      const start = points[index];
      const end = points[index + 1];
      const distance = Math.hypot(end[0] - start[0], end[1] - start[1]);
      const steps = Math.max(1, Math.ceil(distance / Math.max(1, radius * 1.1)));
      for (let step = 0; step <= steps; step += 1) {
        const progress = step / steps;
        dots.push(
          `<circle cx="${start[0] + (end[0] - start[0]) * progress}" cy="${start[1] + (end[1] - start[1]) * progress}" r="${radius}" fill="${color}"/>`,
        );
      }
    }
    return dots.join('');
  };
  switch (primitive.type) {
  case 'disk': {
    const [cx, cy] = point(primitive.center);
    return `<circle cx="${cx}" cy="${cy}" r="${primitive.radius * 1000}" fill="${color}"/>`;
  }
  case 'ring': {
    const [cx, cy] = point(primitive.center);
    const points = [];
    for (let index = 0; index <= 96; index += 1) {
      const radians = index / 96 * Math.PI * 2;
      points.push([
        cx + primitive.radius * 1000 * Math.cos(radians),
        cy + primitive.radius * 1000 * Math.sin(radians),
      ]);
    }
    return dotStroke(points, primitive.lineWidth);
  }
  case 'arc': {
    const [cx, cy] = point(primitive.center);
    const points = [];
    const steps = 36;
    for (let index = 0; index <= steps; index += 1) {
      const degrees = primitive.start + (primitive.end - primitive.start) * index / steps;
      const radians = -degrees * Math.PI / 180;
      points.push([
        cx + primitive.radius * 1000 * Math.cos(radians),
        cy + primitive.radius * 1000 * Math.sin(radians),
      ]);
    }
    return dotStroke(points, primitive.lineWidth);
  }
  case 'polygon':
    return `<polygon points="${pointString(primitive.points.map(point))}" fill="${color}"/>`;
  case 'polyline':
    return dotStroke(primitive.points.map(point), primitive.lineWidth);
  case 'roundedBar': {
    const [x, y, width, height] = primitive.frame;
    return `<rect x="${x * 1000}" y="${(1 - y - height) * 1000}" width="${width * 1000}" height="${height * 1000}" rx="${primitive.cornerRadius * 1000}" fill="${color}"/>`;
  }
  default:
    throw new Error(`Unsupported emblem primitive: ${primitive.type}`);
  }
}

const pixelGlyphs = {
  ' ': ['00000', '00000', '00000', '00000', '00000', '00000', '00000'],
  A: ['01110', '10001', '10001', '11111', '10001', '10001', '10001'],
  B: ['11110', '10001', '10001', '11110', '10001', '10001', '11110'],
  C: ['01111', '10000', '10000', '10000', '10000', '10000', '01111'],
  D: ['11110', '10001', '10001', '10001', '10001', '10001', '11110'],
  E: ['11111', '10000', '10000', '11110', '10000', '10000', '11111'],
  F: ['11111', '10000', '10000', '11110', '10000', '10000', '10000'],
  G: ['01111', '10000', '10000', '10111', '10001', '10001', '01111'],
  H: ['10001', '10001', '10001', '11111', '10001', '10001', '10001'],
  I: ['11111', '00100', '00100', '00100', '00100', '00100', '11111'],
  L: ['10000', '10000', '10000', '10000', '10000', '10000', '11111'],
  M: ['10001', '11011', '10101', '10101', '10001', '10001', '10001'],
  N: ['10001', '11001', '10101', '10011', '10001', '10001', '10001'],
  O: ['01110', '10001', '10001', '10001', '10001', '10001', '01110'],
  P: ['11110', '10001', '10001', '11110', '10000', '10000', '10000'],
  Q: ['01110', '10001', '10001', '10001', '10101', '10010', '01101'],
  R: ['11110', '10001', '10001', '11110', '10100', '10010', '10001'],
  S: ['01111', '10000', '10000', '01110', '00001', '00001', '11110'],
  T: ['11111', '00100', '00100', '00100', '00100', '00100', '00100'],
  U: ['10001', '10001', '10001', '10001', '10001', '10001', '01110'],
  V: ['10001', '10001', '10001', '10001', '10001', '01010', '00100'],
  Y: ['10001', '10001', '01010', '00100', '00100', '00100', '00100'],
};

function pixelTextSvg(text, centerX, topY, pixelWidth, pixelHeight, color, opacity) {
  const characters = [...text.toUpperCase()];
  const advance = pixelWidth * 6;
  const width = characters.length === 0
    ? 0
    : (characters.length - 1) * advance + pixelWidth * 5;
  const startX = centerX - width / 2;
  const pixels = [];
  characters.forEach((character, characterIndex) => {
    const glyph = pixelGlyphs[character];
    if (!glyph) {
      throw new Error(`Unsupported field wordmark character: ${character}`);
    }
    glyph.forEach((row, rowIndex) => {
      [...row].forEach((value, columnIndex) => {
        if (value === '1') {
          pixels.push(
            `<rect x="${startX + characterIndex * advance + columnIndex * pixelWidth}" y="${topY + rowIndex * pixelHeight}" width="${pixelWidth}" height="${pixelHeight}"/>`,
          );
        }
      });
    });
  });
  return `<g fill="${color}" fill-opacity="${opacity}" shape-rendering="crispEdges">${pixels.join('')}</g>`;
}

function teamLayerSvgs(spec, team) {
  const { centerX, endZoneBackY, endZoneFrontY } = spec.projection;
  const endZonePoints = [
    boundaryPoint(spec, -1, endZoneBackY),
    boundaryPoint(spec, 1, endZoneBackY),
    boundaryPoint(spec, 1, endZoneFrontY),
    boundaryPoint(spec, -1, endZoneFrontY),
  ];
  const endZoneBody = [
    '<g shape-rendering="crispEdges">',
    `<polygon points="${pointString(endZonePoints)}" fill="${team.palette[team.endZoneBackground]}" fill-opacity="0.68"/>`,
    pixelTextSvg(team.nickname, centerX, 238, 9, 7, team.palette.accent, 0.94),
    '</g>',
  ].join('');

  const fieldPaintColor = team.fieldPaintColor ?? team.palette[team.fieldPaintRole];
  const fieldPalette = {
    primary: fieldPaintColor,
    secondary: fieldPaintColor,
    accent: fieldPaintColor,
  };
  const emblemBody = team.emblem.map((primitive) => emblemPrimitiveSvg(
    primitive,
    fieldPalette,
  )).join('');
  const fieldBody = [
    `<g opacity="0.66" fill="${fieldPaintColor}" stroke="${fieldPaintColor}" stroke-linecap="round" stroke-linejoin="round">`,
    '<g transform="translate(604 333) scale(0.52 0.115)">',
    emblemBody,
    '</g>',
    '</g>',
  ].join('');

  return {
    endZone: svgDocument(spec, endZoneBody),
    fieldBranding: svgDocument(spec, fieldBody),
  };
}

function distressMaskSvg(spec) {
  const endZoneHoles = buildDistressHoles(
    0x5f3759df,
    { x: 330, y: 228, width: 1068, height: 66 },
    900,
  );
  const fieldHoles = buildDistressHoles(
    0x9e3779b9,
    { x: 605, y: 332, width: 518, height: 122 },
    500,
  );
  return svgDocument(
    spec,
    `<rect width="${spec.canvas.width}" height="${spec.canvas.height}" fill="white"/>${endZoneHoles}${fieldHoles}<rect x="848" y="227" width="32" height="8" fill="black"/>`,
  );
}

function identify(pathname) {
  return execFileSync('magick', [
    'identify',
    '-format',
    '%w|%h|%[channels]|%[opaque]',
    pathname,
  ], { encoding: 'utf8' }).trim();
}

function validateImage(pathname, { alpha }) {
  const [width, height, channels, opaque] = identify(pathname).split('|');
  if (width !== '1728' || height !== '768') {
    throw new Error(`${pathname} must be 1728x768; got ${width}x${height}`);
  }
  if (alpha && (opaque === 'True' || !channels.includes('a'))) {
    throw new Error(`${pathname} must contain transparency; got ${channels} opaque=${opaque}`);
  }
  if (!alpha && opaque !== 'True') {
    throw new Error(`${pathname} must be opaque; got ${channels} opaque=${opaque}`);
  }
}

try {
  const spec = JSON.parse(readFileSync(layerSpecPath, 'utf8'));
  if (spec.canvas.width !== 1728 || spec.canvas.height !== 768) {
    throw new Error('Field layer specification must remain exactly 1728x768.');
  }
  if (spec.teams.length !== 16 || new Set(spec.teams.map(({ id }) => id)).size !== 16) {
    throw new Error('Field layer specification must contain sixteen unique teams.');
  }

  mkdirSync(runtimeRoot, { recursive: true });
  mkdirSync(sourceTeamsRoot, { recursive: true });
  mkdirSync(runtimeTeamsRoot, { recursive: true });

  copyPng(neutralSource, neutralOutput, false);
  renderSvg('field-markings-v1', fieldMarkingsSvg(spec), markingsSource);
  copyPng(markingsSource, markingsOutput, true);
  renderSvg('field-paint-distress-mask-v1', distressMaskSvg(spec), distressSource);

  runMagick([
    neutralOutput,
    markingsOutput,
    '-compose',
    'over',
    '-composite',
    '-alpha',
    'off',
    '-colorspace',
    'sRGB',
    '-strip',
    compatibilityOutput,
  ]);

  const generated = [neutralOutput, markingsOutput, compatibilityOutput];
  for (const team of spec.teams) {
    const sourceTeamRoot = path.join(sourceTeamsRoot, team.id);
    const runtimeTeamRoot = path.join(runtimeTeamsRoot, team.id);
    const layers = teamLayerSvgs(spec, team);
    const endZoneSource = path.join(sourceTeamRoot, 'end-zone-v1.png');
    const fieldBrandingSource = path.join(sourceTeamRoot, 'field-branding-v1.png');
    const endZoneOutput = path.join(runtimeTeamRoot, 'end-zone.png');
    const fieldBrandingOutput = path.join(runtimeTeamRoot, 'field-branding.png');

    const rawEndZone = path.join(tempRoot, `${team.id}-end-zone-raw.png`);
    const rawFieldBranding = path.join(tempRoot, `${team.id}-field-branding-raw.png`);
    renderSvg(`${team.id}-end-zone`, layers.endZone, rawEndZone);
    renderSvg(`${team.id}-field-branding`, layers.fieldBranding, rawFieldBranding);
    applyDistress(rawEndZone, distressSource, endZoneSource);
    applyDistress(rawFieldBranding, distressSource, fieldBrandingSource);
    copyPng(endZoneSource, endZoneOutput, true);
    copyPng(fieldBrandingSource, fieldBrandingOutput, true);
    generated.push(endZoneOutput, fieldBrandingOutput);
  }

  validateImage(neutralSource, { alpha: false });
  validateImage(neutralOutput, { alpha: false });
  validateImage(compatibilityOutput, { alpha: false });
  validateImage(markingsSource, { alpha: true });
  validateImage(markingsOutput, { alpha: true });
  for (const pathname of generated.slice(3)) {
    validateImage(pathname, { alpha: true });
  }

  console.log(`Generated ${generated.length} runtime field assets from ${path.relative(repositoryRoot, neutralSource)}`);
} finally {
  if (process.env.POCKET_VECTOR_KEEP_FIELD_TEMP === '1') {
    console.log(`Kept temporary field sources at ${tempRoot}`);
  } else {
    rmSync(tempRoot, { recursive: true, force: true });
  }
}

import { mkdir, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const ART_DIR = resolve(ROOT, 'public/assets/art');
const MUSIC_DIR = resolve(ROOT, 'public/assets/audio/music');
const SFX_DIR = resolve(ROOT, 'public/assets/audio/sfx');
const SAMPLE_RATE = 22_050;

const PALETTE = Object.freeze({
  midnight: '#071326',
  navy: '#102548',
  turf: '#0d5a55',
  turfDark: '#073f42',
  cyan: '#1de6ef',
  cyanLight: '#b8fbff',
  violet: '#7d4dff',
  violetDark: '#39257f',
  coral: '#ff5f61',
  coralLight: '#ffb09f',
  amber: '#ffc857',
  cream: '#fff5da',
  white: '#f7fcff',
  ink: '#020713',
});

const ART = Object.freeze({
  logo: '/assets/art/logo.svg',
  field: '/assets/art/field.svg',
  destinationX: '/assets/art/aim-destination-x.svg',
  quarterback: {
    idle: '/assets/art/qb-idle.svg',
    aim: '/assets/art/qb-aim.svg',
    throw: '/assets/art/qb-throw.svg',
    recovery: '/assets/art/qb-recovery.svg',
  },
  receiver: {
    run1: '/assets/art/receiver-run-1.svg',
    run2: '/assets/art/receiver-run-2.svg',
    catch: '/assets/art/receiver-catch.svg',
    touchdown: '/assets/art/receiver-touchdown.svg',
  },
  defender: {
    run1: '/assets/art/defender-run-1.svg',
    run2: '/assets/art/defender-run-2.svg',
    interception: '/assets/art/defender-interception.svg',
  },
  football: '/assets/art/football.svg',
  effects: {
    scoreBurst: '/assets/art/effect-score.svg',
    completion: '/assets/art/effect-completion.svg',
    touchdown: '/assets/art/effect-touchdown.svg',
    interception: '/assets/art/effect-interception.svg',
  },
  hud: {
    meterFrame: '/assets/art/meter-frame.svg',
    meterFill: '/assets/art/meter-fill.svg',
    multiplier: '/assets/art/multiplier.svg',
    timerWarning: '/assets/art/timer-warning.svg',
  },
  controls: {
    buttonPrimary: '/assets/art/button.svg',
    buttonSecondary: '/assets/art/ui-button-secondary.svg',
    mute: '/assets/art/icon-mute.svg',
    unmute: '/assets/art/icon-unmute.svg',
    pause: '/assets/art/icon-pause.svg',
    play: '/assets/art/icon-play.svg',
    restart: '/assets/art/icon-restart.svg',
    info: '/assets/art/icon-info.svg',
    avatarFrame: '/assets/art/avatar-frame.svg',
  },
});

const AUDIO = Object.freeze({
  music: {
    gameplay: '/assets/audio/music/pocket-vector-drive.wav',
  },
  sfx: {
    uiHover: '/assets/audio/sfx/ui-hover.wav',
    uiSelect: '/assets/audio/sfx/ui-select.wav',
    countdown: '/assets/audio/sfx/countdown.wav',
    snap: '/assets/audio/sfx/snap.wav',
    throwRelease: '/assets/audio/sfx/throw.wav',
    ballFlight: '/assets/audio/sfx/flight.wav',
    catch: '/assets/audio/sfx/catch.wav',
    deepCompletion: '/assets/audio/sfx/deep-completion.wav',
    touchdown: '/assets/audio/sfx/touchdown.wav',
    tdBonusActivate: '/assets/audio/sfx/bonus-active.wav',
    multiplierUp: '/assets/audio/sfx/multiplier.wav',
    incompletion: '/assets/audio/sfx/incomplete.wav',
    interception: '/assets/audio/sfx/interception.wav',
    meterLoss: '/assets/audio/sfx/meter-loss.wav',
    timerWarning: '/assets/audio/sfx/timer-warning.wav',
    gameOver: '/assets/audio/sfx/game-over.wav',
    continueSuccess: '/assets/audio/sfx/continue-success.wav',
  },
});

function xmlEscape(value) {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
}

function countStringLeaves(value) {
  if (typeof value === 'string') return 1;
  return Object.values(value).reduce((total, child) => total + countStringLeaves(child), 0);
}

function svgDocument(viewBox, title, description, content) {
  return `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="${viewBox}" role="img" aria-labelledby="title desc">
  <title id="title">${xmlEscape(title)}</title>
  <desc id="desc">${xmlEscape(description)}</desc>
${content}
</svg>
`;
}

function sharedDefs() {
  return `  <defs>
    <linearGradient id="cyanMetal" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="${PALETTE.cyanLight}"/>
      <stop offset="0.35" stop-color="${PALETTE.cyan}"/>
      <stop offset="1" stop-color="#0782b9"/>
    </linearGradient>
    <linearGradient id="violetMetal" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#b5a1ff"/>
      <stop offset="0.45" stop-color="${PALETTE.violet}"/>
      <stop offset="1" stop-color="${PALETTE.violetDark}"/>
    </linearGradient>
    <linearGradient id="coralMetal" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="${PALETTE.coralLight}"/>
      <stop offset="0.42" stop-color="${PALETTE.coral}"/>
      <stop offset="1" stop-color="#a51f45"/>
    </linearGradient>
    <linearGradient id="darkMetal" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#36527b"/>
      <stop offset="0.55" stop-color="${PALETTE.navy}"/>
      <stop offset="1" stop-color="${PALETTE.midnight}"/>
    </linearGradient>
    <radialGradient id="glow" cx="50%" cy="50%" r="50%">
      <stop offset="0" stop-color="${PALETTE.cyan}" stop-opacity="0.95"/>
      <stop offset="1" stop-color="${PALETTE.cyan}" stop-opacity="0"/>
    </radialGradient>
    <filter id="shadow" x="-30%" y="-30%" width="160%" height="180%">
      <feDropShadow dx="0" dy="7" stdDeviation="5" flood-color="${PALETTE.ink}" flood-opacity="0.65"/>
    </filter>
    <filter id="neon" x="-50%" y="-50%" width="200%" height="200%">
      <feGaussianBlur stdDeviation="5" result="blur"/>
      <feMerge><feMergeNode in="blur"/><feMergeNode in="SourceGraphic"/></feMerge>
    </filter>
  </defs>`;
}

function lineLimb(x1, y1, x2, y2, width, color, highlight = PALETTE.cyanLight) {
  const highlightWidth = Math.max(2, width * 0.22);
  return `<g>
    <line x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}" stroke="${PALETTE.ink}" stroke-width="${width + 8}" stroke-linecap="round"/>
    <line x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}" stroke="${color}" stroke-width="${width}" stroke-linecap="round"/>
    <line x1="${x1 + 2}" y1="${y1 - 1}" x2="${x2 + 2}" y2="${y2 - 1}" stroke="${highlight}" stroke-opacity="0.34" stroke-width="${highlightWidth}" stroke-linecap="round"/>
  </g>`;
}

function shoe(x, y, rotation, accent) {
  return `<g transform="translate(${x} ${y}) rotate(${rotation})">
    <path d="M-18-8 Q2-14 23-1 Q28 3 22 11 L-19 11 Q-27 5-18-8Z" fill="${PALETTE.ink}" stroke="${PALETTE.ink}" stroke-width="4"/>
    <path d="M-14-6 Q1-9 18-1 L21 5 L-18 5Z" fill="${PALETTE.white}"/>
    <path d="M7-5 L19 0" stroke="${accent}" stroke-width="4" stroke-linecap="round"/>
  </g>`;
}

function glove(x, y, rotation, color = PALETTE.white) {
  return `<g transform="translate(${x} ${y}) rotate(${rotation})">
    <path d="M-11 7 Q-15-4-7-12 Q-2-18 5-11 L14-3 Q17 3 11 10 Q1 16-11 7Z" fill="${color}" stroke="${PALETTE.ink}" stroke-width="5"/>
    <path d="M-4-10 L3 6 M2-9 L8 3" stroke="${PALETTE.cyan}" stroke-opacity="0.55" stroke-width="2"/>
  </g>`;
}

function helmet(x, y, colors, facing = 1) {
  const flip = facing < 0 ? 'scale(-1 1)' : '';
  return `<g transform="translate(${x} ${y}) ${flip}">
    <path d="M-31 6 Q-32-32-3-39 Q26-41 35-13 Q39 5 27 22 L8 20 L-1 7Z" fill="${colors.helmet}" stroke="${PALETTE.ink}" stroke-width="7"/>
    <path d="M-22-18 Q0-35 23-20" fill="none" stroke="${colors.helmetHighlight}" stroke-width="7" stroke-linecap="round" opacity="0.78"/>
    <path d="M14 2 L39 7 L34 25 L18 25" fill="none" stroke="${PALETTE.white}" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"/>
    <path d="M28-8 L39 0" stroke="${colors.accent}" stroke-width="6" stroke-linecap="round"/>
    <path d="M-31-2 Q-37 12-27 20" fill="${colors.accent}" stroke="${PALETTE.ink}" stroke-width="4"/>
  </g>`;
}

const OFFENSE = Object.freeze({
  jersey: 'url(#cyanMetal)',
  pants: 'url(#violetMetal)',
  helmet: PALETTE.violet,
  helmetHighlight: '#b9a6ff',
  accent: PALETTE.cyan,
  sock: PALETTE.cyanLight,
});

const DEFENSE = Object.freeze({
  jersey: 'url(#coralMetal)',
  pants: 'url(#darkMetal)',
  helmet: PALETTE.coral,
  helmetHighlight: PALETTE.coralLight,
  accent: PALETTE.amber,
  sock: PALETTE.coralLight,
});

function footballMarkup(x, y, rotation = -18, scale = 1) {
  return `<g transform="translate(${x} ${y}) rotate(${rotation}) scale(${scale})">
    <path d="M-29 0 Q-15-23 0-24 Q16-23 30 0 Q16 23 0 24 Q-16 22-29 0Z" fill="#9e4328" stroke="${PALETTE.ink}" stroke-width="6"/>
    <path d="M-20-8 Q0-20 21-7" fill="none" stroke="#df7653" stroke-width="5" stroke-linecap="round" opacity="0.8"/>
    <path d="M-3-12 L-3 12 M-10-7 L4-7 M-10-1 L4-1 M-10 5 L4 5" stroke="${PALETTE.cream}" stroke-width="3.5" stroke-linecap="round"/>
    <path d="M-22 0 L-15 0 M16 0 L23 0" stroke="${PALETTE.cream}" stroke-width="4"/>
  </g>`;
}

function quarterbackSvg(pose) {
  const poses = {
    idle: {
      backLeg: [90, 178, 72, 229],
      frontLeg: [112, 179, 127, 230],
      backFoot: [65, 234, -8],
      frontFoot: [135, 235, 8],
      backArm: [78, 104, 64, 151],
      frontArm: [124, 107, 132, 147],
      ball: [101, 139, -9, 0.72],
      torsoRotate: 0,
      head: [101, 63],
    },
    aim: {
      backLeg: [88, 178, 62, 225],
      frontLeg: [112, 179, 137, 224],
      backFoot: [54, 231, -16],
      frontFoot: [146, 230, 14],
      backArm: [82, 106, 60, 130],
      frontArm: [119, 105, 149, 84],
      ball: [55, 120, -38, 0.73],
      torsoRotate: -5,
      head: [103, 62],
    },
    throw: {
      backLeg: [91, 178, 65, 230],
      frontLeg: [113, 178, 145, 218],
      backFoot: [58, 235, -11],
      frontFoot: [154, 223, 20],
      backArm: [82, 108, 61, 153],
      frontArm: [120, 101, 170, 72],
      ball: null,
      torsoRotate: 8,
      head: [104, 62],
    },
    recovery: {
      backLeg: [93, 178, 81, 231],
      frontLeg: [112, 178, 139, 224],
      backFoot: [74, 236, -4],
      frontFoot: [148, 229, 17],
      backArm: [82, 107, 71, 156],
      frontArm: [122, 108, 153, 145],
      ball: null,
      torsoRotate: 6,
      head: [104, 63],
    },
  };
  const p = poses[pose];
  return `${sharedDefs()}
  <ellipse cx="102" cy="239" rx="70" ry="13" fill="${PALETTE.ink}" opacity="0.42"/>
  <g filter="url(#shadow)">
    ${lineLimb(...p.backLeg, 25, OFFENSE.pants, '#aa90ff')}
    ${shoe(...p.backFoot, PALETTE.cyan)}
    ${lineLimb(...p.backArm, 20, OFFENSE.jersey)}
    <g transform="rotate(${p.torsoRotate} 102 137)">
      <path d="M71 97 Q101 82 132 98 L143 157 Q129 183 101 185 Q73 181 61 157Z" fill="${OFFENSE.jersey}" stroke="${PALETTE.ink}" stroke-width="8" stroke-linejoin="round"/>
      <path d="M75 103 Q102 92 129 104" fill="none" stroke="${PALETTE.cyanLight}" stroke-width="8" stroke-linecap="round" opacity="0.7"/>
      <path d="M69 151 Q101 162 137 150 L134 175 Q101 189 67 173Z" fill="${PALETTE.violet}" stroke="${PALETTE.ink}" stroke-width="5"/>
      <text x="101" y="149" text-anchor="middle" font-family="Arial Black, sans-serif" font-size="37" fill="${PALETTE.white}" stroke="${PALETTE.navy}" stroke-width="3">7</text>
    </g>
    ${lineLimb(...p.frontLeg, 27, OFFENSE.pants, '#b6a7ff')}
    <line x1="${p.frontLeg[2]}" y1="${p.frontLeg[3] - 16}" x2="${p.frontLeg[2]}" y2="${p.frontLeg[3] + 2}" stroke="${OFFENSE.sock}" stroke-width="17" stroke-linecap="round"/>
    ${shoe(...p.frontFoot, PALETTE.cyan)}
    ${lineLimb(...p.frontArm, 21, OFFENSE.jersey)}
    ${glove(p.backArm[2], p.backArm[3], -10)}
    ${glove(p.frontArm[2], p.frontArm[3], 12)}
    ${helmet(...p.head, OFFENSE, 1)}
    ${p.ball ? footballMarkup(...p.ball) : ''}
  </g>
  <circle cx="100" cy="246" r="3" fill="${PALETTE.coral}" opacity="0.01"/>`;
}

function runnerSvg({ team, pose, role }) {
  const isReceiver = role === 'receiver';
  const frames = {
    run1: {
      torso: -10,
      head: [105, 62],
      backLeg: [94, 173, 56, 218],
      frontLeg: [112, 174, 153, 211],
      backFoot: [49, 224, -18],
      frontFoot: [163, 216, 20],
      backArm: [81, 106, 53, 137],
      frontArm: [122, 105, 151, 78],
    },
    run2: {
      torso: 7,
      head: [105, 62],
      backLeg: [93, 173, 137, 215],
      frontLeg: [113, 174, 72, 224],
      backFoot: [146, 219, 16],
      frontFoot: [64, 230, -13],
      backArm: [80, 105, 54, 78],
      frontArm: [123, 108, 151, 140],
    },
    catch: {
      torso: -3,
      head: [104, 63],
      backLeg: [92, 174, 75, 226],
      frontLeg: [113, 174, 135, 224],
      backFoot: [68, 232, -8],
      frontFoot: [144, 230, 12],
      backArm: [82, 106, 133, 77],
      frontArm: [122, 106, 153, 80],
    },
    touchdown: {
      torso: 0,
      head: [102, 64],
      backLeg: [92, 174, 82, 228],
      frontLeg: [112, 174, 125, 228],
      backFoot: [75, 234, -5],
      frontFoot: [133, 234, 6],
      backArm: [80, 106, 48, 61],
      frontArm: [123, 106, 154, 58],
    },
    interception: {
      torso: -5,
      head: [104, 63],
      backLeg: [92, 174, 68, 225],
      frontLeg: [113, 174, 141, 220],
      backFoot: [60, 231, -12],
      frontFoot: [150, 225, 14],
      backArm: [81, 107, 127, 76],
      frontArm: [122, 106, 154, 72],
    },
  };
  const p = frames[pose];
  const number = isReceiver ? '11' : '24';
  const outline = PALETTE.ink;
  const celebration = pose === 'touchdown';
  const interception = pose === 'interception';
  return `${sharedDefs()}
  ${celebration ? `<g opacity="0.7" filter="url(#neon)"><path d="M32 58 L15 24 M53 38 L48 7 M167 57 L185 23 M148 37 L153 6" stroke="${PALETTE.amber}" stroke-width="8" stroke-linecap="round"/></g>` : ''}
  <ellipse cx="103" cy="238" rx="72" ry="13" fill="${PALETTE.ink}" opacity="0.42"/>
  <g filter="url(#shadow)">
    ${lineLimb(...p.backLeg, 24, team.pants, team.accent)}
    ${shoe(...p.backFoot, team.accent)}
    ${lineLimb(...p.backArm, 19, team.jersey, team.accent)}
    <g transform="rotate(${p.torso} 103 137)">
      <path d="M72 97 Q102 84 133 98 L143 154 Q131 181 102 184 Q73 181 62 155Z" fill="${team.jersey}" stroke="${outline}" stroke-width="8" stroke-linejoin="round"/>
      <path d="M74 104 Q103 93 131 104" fill="none" stroke="${team.accent}" stroke-width="8" opacity="0.75" stroke-linecap="round"/>
      <path d="M68 151 Q102 162 138 150 L134 174 Q103 188 68 173Z" fill="${team.pants}" stroke="${outline}" stroke-width="5"/>
      <text x="103" y="147" text-anchor="middle" font-family="Arial Black, sans-serif" font-size="31" fill="${PALETTE.white}" stroke="${PALETTE.navy}" stroke-width="3">${number}</text>
    </g>
    ${lineLimb(...p.frontLeg, 26, team.pants, team.accent)}
    <line x1="${p.frontLeg[2]}" y1="${p.frontLeg[3] - 16}" x2="${p.frontLeg[2]}" y2="${p.frontLeg[3] + 1}" stroke="${team.sock}" stroke-width="16" stroke-linecap="round"/>
    ${shoe(...p.frontFoot, team.accent)}
    ${lineLimb(...p.frontArm, 20, team.jersey, team.accent)}
    ${glove(p.backArm[2], p.backArm[3], -12)}
    ${glove(p.frontArm[2], p.frontArm[3], 10)}
    ${helmet(...p.head, team, 1)}
    ${pose === 'catch' || interception ? footballMarkup(143, 77, -14, 0.58) : ''}
  </g>
  <circle cx="100" cy="246" r="3" fill="${PALETTE.coral}" opacity="0.01"/>`;
}

function logoSvg() {
  return `${sharedDefs()}
  <rect x="14" y="22" width="772" height="276" rx="56" fill="${PALETTE.ink}" opacity="0.72"/>
  <path d="M83 83 Q163 19 245 69 Q297 101 311 159 Q327 219 273 268 Q212 313 126 274 Q53 241 44 169 Q36 113 83 83Z" fill="url(#violetMetal)" stroke="${PALETTE.cyan}" stroke-width="12" filter="url(#shadow)"/>
  <path d="M111 230 L111 92 L180 92 Q246 92 246 151 Q246 211 177 211 L148 211 L148 230Z M148 127 L148 177 L177 177 Q205 177 205 151 Q205 127 177 127Z" fill="${PALETTE.white}" stroke="${PALETTE.ink}" stroke-width="7" fill-rule="evenodd"/>
  <path d="M186 93 L224 93 L252 194 L280 93 L320 93 L273 235 L230 235Z" fill="${PALETTE.coral}" stroke="${PALETTE.ink}" stroke-width="7"/>
  <g filter="url(#neon)">
    <text x="351" y="144" font-family="Arial Black, Impact, sans-serif" font-size="70" letter-spacing="3" fill="${PALETTE.white}" stroke="${PALETTE.midnight}" stroke-width="8" paint-order="stroke">POCKET</text>
    <text x="351" y="226" font-family="Arial Black, Impact, sans-serif" font-size="78" letter-spacing="1" fill="${PALETTE.cyan}" stroke="${PALETTE.midnight}" stroke-width="9" paint-order="stroke">VECTOR</text>
  </g>
  <path d="M349 252 H730" stroke="${PALETTE.coral}" stroke-width="10" stroke-linecap="round"/>
  <path d="M674 73 L757 117 L727 129 L766 169 L746 186 L706 145 L693 175Z" fill="${PALETTE.amber}" stroke="${PALETTE.ink}" stroke-width="7"/>
  ${footballMarkup(315, 53, 10, 0.72)}`;
}

function fieldSvg() {
  const yardLines = Array.from({ length: 8 }, (_, index) => {
    const t = index / 7;
    const y = 178 + Math.pow(t, 1.62) * 518;
    const halfWidth = 240 + t * 310;
    const opacity = 0.42 + t * 0.4;
    return `<path d="M${512 - halfWidth} ${y.toFixed(1)} H${512 + halfWidth}" stroke="${PALETTE.white}" stroke-opacity="${opacity.toFixed(2)}" stroke-width="${(3 + t * 4).toFixed(1)}"/>
      <text x="${(512 - halfWidth + 30).toFixed(1)}" y="${(y - 10).toFixed(1)}" fill="${PALETTE.white}" fill-opacity="0.6" font-family="Arial Black, sans-serif" font-size="${(18 + t * 11).toFixed(0)}">${index === 0 ? 'GOAL' : index * 10}</text>`;
  }).join('\n    ');
  const crowd = Array.from({ length: 72 }, (_, index) => {
    const x = 18 + ((index * 73) % 988);
    const y = 36 + ((index * 29) % 105);
    const color = [PALETTE.cyan, PALETTE.coral, PALETTE.violet, PALETTE.amber][index % 4];
    return `<circle cx="${x}" cy="${y}" r="${2 + (index % 3)}" fill="${color}" opacity="${0.26 + (index % 5) * 0.09}"/>`;
  }).join('\n    ');
  return `  <defs>
    <linearGradient id="sky" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#020713"/><stop offset="1" stop-color="${PALETTE.navy}"/></linearGradient>
    <linearGradient id="turfGradient" x1="0" y1="0" x2="0" y2="1"><stop stop-color="${PALETTE.turfDark}"/><stop offset="1" stop-color="${PALETTE.turf}"/></linearGradient>
    <pattern id="endzonePattern" width="36" height="36" patternUnits="userSpaceOnUse" patternTransform="skewX(-14)"><rect width="18" height="36" fill="${PALETTE.violet}"/><rect x="18" width="18" height="36" fill="${PALETTE.violetDark}"/></pattern>
    <radialGradient id="fieldLight" cx="50%" cy="27%" r="68%"><stop stop-color="${PALETTE.cyan}" stop-opacity="0.17"/><stop offset="1" stop-color="${PALETTE.ink}" stop-opacity="0"/></radialGradient>
  </defs>
  <rect width="1024" height="768" fill="url(#sky)"/>
  <path d="M0 28 Q512-24 1024 28 V152 Q512 106 0 152Z" fill="${PALETTE.ink}"/>
  <g>${crowd}</g>
  <path d="M255 119 L769 119 L1060 768 L-36 768Z" fill="url(#turfGradient)" stroke="${PALETTE.cyan}" stroke-opacity="0.35" stroke-width="5"/>
  <path d="M314 155 H710 L738 217 H286Z" fill="url(#endzonePattern)" stroke="${PALETTE.white}" stroke-width="5"/>
  <text x="512" y="201" text-anchor="middle" font-family="Arial Black, sans-serif" font-size="40" letter-spacing="8" fill="${PALETTE.white}" opacity="0.86">VECTOR CITY</text>
  <g>${yardLines}</g>
  <path d="M255 119 L-36 768 M769 119 L1060 768" stroke="${PALETTE.white}" stroke-width="8" opacity="0.8"/>
  <path d="M362 119 L238 768 M662 119 L786 768" stroke="${PALETTE.white}" stroke-width="3" stroke-dasharray="11 13" opacity="0.28"/>
  <rect width="1024" height="768" fill="url(#fieldLight)" pointer-events="none"/>
  <path d="M0 0 H1024 V768 H0Z" fill="none" stroke="${PALETTE.cyan}" stroke-opacity="0.18" stroke-width="22"/>`;
}

function destinationXSvg() {
  return `${sharedDefs()}
  <circle cx="48" cy="48" r="37" fill="${PALETTE.ink}" fill-opacity="0.32" stroke="${PALETTE.coral}" stroke-width="4" stroke-dasharray="7 7"/>
  <circle cx="48" cy="48" r="23" fill="none" stroke="${PALETTE.amber}" stroke-width="3" opacity="0.75"/>
  <path d="M25 25 L71 71 M71 25 L25 71" stroke="${PALETTE.ink}" stroke-width="16" stroke-linecap="round"/>
  <path d="M25 25 L71 71 M71 25 L25 71" stroke="${PALETTE.coral}" stroke-width="9" stroke-linecap="round" filter="url(#neon)"/>
  <path d="M48 2 V13 M48 83 V94 M2 48 H13 M83 48 H94" stroke="${PALETTE.white}" stroke-width="4" stroke-linecap="round"/>`;
}

function footballSvg() {
  return `${sharedDefs()}
  <ellipse cx="64" cy="67" rx="45" ry="12" fill="${PALETTE.ink}" opacity="0.25"/>
  ${footballMarkup(64, 58, -18, 1.55)}
  <path d="M14 24 Q2 40 11 59 M111 17 Q126 34 119 51" fill="none" stroke="${PALETTE.cyan}" stroke-width="4" stroke-linecap="round" opacity="0.7"/>`;
}

function scoreBurstSvg() {
  return `${sharedDefs()}
  <g filter="url(#shadow)">
    <path d="M128 6 L152 52 L198 26 L196 77 L248 75 L215 116 L256 147 L206 161 L223 211 L175 192 L157 246 L124 207 L83 242 L72 190 L18 208 L42 159 L0 130 L49 105 L20 62 L74 61 L81 12Z" fill="url(#violetMetal)" stroke="${PALETTE.cyan}" stroke-width="8"/>
    <circle cx="128" cy="128" r="74" fill="${PALETTE.midnight}" stroke="${PALETTE.amber}" stroke-width="7"/>
    <path d="M76 128 H180 M128 76 V180" stroke="${PALETTE.cyan}" stroke-width="10" stroke-linecap="round"/>
  </g>`;
}

function completionEffectSvg() {
  return `${sharedDefs()}
  <g fill="none" stroke-linecap="round">
    <circle cx="128" cy="128" r="92" stroke="${PALETTE.cyan}" stroke-width="12" opacity="0.34"/>
    <circle cx="128" cy="128" r="61" stroke="${PALETTE.cyanLight}" stroke-width="8" stroke-dasharray="22 12"/>
    <path d="M79 130 L112 164 L181 87" stroke="${PALETTE.ink}" stroke-width="27" stroke-linejoin="round"/>
    <path d="M79 130 L112 164 L181 87" stroke="${PALETTE.cyan}" stroke-width="15" stroke-linejoin="round" filter="url(#neon)"/>
  </g>`;
}

function touchdownEffectSvg() {
  return `${sharedDefs()}
  <g filter="url(#shadow)">
    <path d="M127 8 L155 79 L231 57 L182 120 L247 160 L169 161 L159 241 L124 178 L57 224 L83 151 L8 126 L83 103 L46 32 L113 75Z" fill="${PALETTE.amber}" stroke="${PALETTE.ink}" stroke-width="8"/>
    <path d="M114 45 L169 45 L139 111 L182 111 L88 219 L113 137 L74 137Z" fill="${PALETTE.coral}" stroke="${PALETTE.ink}" stroke-width="7"/>
  </g>`;
}

function interceptionEffectSvg() {
  return `${sharedDefs()}
  <g filter="url(#shadow)">
    <path d="M128 8 L224 43 V119 Q224 196 128 246 Q32 196 32 119 V43Z" fill="url(#coralMetal)" stroke="${PALETTE.ink}" stroke-width="9"/>
    <path d="M76 76 L180 180 M180 76 L76 180" stroke="${PALETTE.ink}" stroke-width="30" stroke-linecap="round"/>
    <path d="M76 76 L180 180 M180 76 L76 180" stroke="${PALETTE.white}" stroke-width="16" stroke-linecap="round"/>
  </g>`;
}

function meterFrameSvg() {
  return `${sharedDefs()}
  <path d="M31 5 H329 L355 29 L329 53 H31 L5 29Z" fill="${PALETTE.ink}" stroke="${PALETTE.cyan}" stroke-width="7"/>
  <path d="M37 14 H318 L336 29 L318 44 H37 L20 29Z" fill="${PALETTE.navy}" stroke="${PALETTE.white}" stroke-opacity="0.27" stroke-width="2"/>
  <path d="M58 8 V50 M302 8 V50" stroke="${PALETTE.violet}" stroke-width="7"/>
  <circle cx="29" cy="29" r="7" fill="${PALETTE.amber}"/><circle cx="331" cy="29" r="7" fill="${PALETTE.amber}"/>`;
}

function meterFillSvg() {
  return `${sharedDefs()}
  <path d="M22 7 H334 L354 29 L334 51 H22 L4 29Z" fill="url(#cyanMetal)" stroke="${PALETTE.cyanLight}" stroke-width="4"/>
  <path d="M32 16 H316" stroke="${PALETTE.white}" stroke-opacity="0.62" stroke-width="7" stroke-linecap="round"/>
  <path d="M25 42 H335" stroke="${PALETTE.violet}" stroke-opacity="0.55" stroke-width="6"/>
  <g stroke="${PALETTE.midnight}" stroke-opacity="0.32" stroke-width="3">${Array.from({ length: 11 }, (_, index) => `<path d="M${40 + index * 26} 10 V48"/>`).join('')}</g>`;
}

function multiplierBadgeSvg() {
  return `${sharedDefs()}
  <path d="M63 5 H165 L193 33 V91 L166 119 H62 L35 92 V33Z" fill="url(#violetMetal)" stroke="${PALETTE.cyan}" stroke-width="7" filter="url(#shadow)"/>
  <path d="M57 43 L91 77 M91 43 L57 77" stroke="${PALETTE.white}" stroke-width="13" stroke-linecap="round"/>
  <path d="M113 77 H166" stroke="${PALETTE.amber}" stroke-width="10" stroke-linecap="round"/>
  <path d="M127 48 H166" stroke="${PALETTE.amber}" stroke-width="10" stroke-linecap="round" opacity="0.62"/>`;
}

function timerWarningSvg() {
  return `${sharedDefs()}
  <circle cx="64" cy="64" r="55" fill="${PALETTE.ink}" stroke="${PALETTE.coral}" stroke-width="8" filter="url(#shadow)"/>
  <path d="M64 28 V68 L90 84" fill="none" stroke="${PALETTE.white}" stroke-width="10" stroke-linecap="round" stroke-linejoin="round"/>
  <path d="M19 18 L34 32 M109 18 L94 32" stroke="${PALETTE.amber}" stroke-width="8" stroke-linecap="round"/>
  <circle cx="64" cy="64" r="48" fill="none" stroke="${PALETTE.coralLight}" stroke-width="4" stroke-dasharray="9 8"/>`;
}

function buttonSvg(primary) {
  const fill = primary ? 'url(#cyanMetal)' : 'url(#darkMetal)';
  const border = primary ? PALETTE.cyanLight : PALETTE.violet;
  const notch = primary ? PALETTE.coral : PALETTE.cyan;
  return `${sharedDefs()}
  <path d="M28 5 H332 L355 28 V65 L332 88 H28 L5 65 V28Z" fill="${fill}" stroke="${PALETTE.ink}" stroke-width="9" filter="url(#shadow)"/>
  <path d="M31 12 H327 L347 32" fill="none" stroke="${border}" stroke-width="5" stroke-linecap="round" opacity="0.82"/>
  <path d="M18 45 H43 M317 45 H342" stroke="${notch}" stroke-width="8" stroke-linecap="round"/>`;
}

function iconSvg(kind) {
  const base = `${sharedDefs()}
  <circle cx="48" cy="48" r="42" fill="${PALETTE.ink}" fill-opacity="0.88" stroke="${PALETTE.cyan}" stroke-width="5"/>`;
  const paths = {
    mute: `<path d="M21 39 H34 L51 25 V71 L34 57 H21Z" fill="${PALETTE.white}"/><path d="M64 35 L81 61 M81 35 L64 61" stroke="${PALETTE.coral}" stroke-width="7" stroke-linecap="round"/>`,
    unmute: `<path d="M18 39 H31 L48 25 V71 L31 57 H18Z" fill="${PALETTE.white}"/><path d="M59 36 Q70 48 59 60 M68 27 Q87 48 68 69" fill="none" stroke="${PALETTE.cyan}" stroke-width="6" stroke-linecap="round"/>`,
    pause: `<rect x="27" y="23" width="14" height="50" rx="4" fill="${PALETTE.white}"/><rect x="55" y="23" width="14" height="50" rx="4" fill="${PALETTE.white}"/>`,
    play: `<path d="M35 23 L75 48 L35 73Z" fill="${PALETTE.white}" stroke="${PALETTE.violet}" stroke-width="4"/>`,
    restart: `<path d="M71 35 Q56 16 35 30 Q14 44 25 65 Q35 84 58 74 Q67 70 72 61" fill="none" stroke="${PALETTE.white}" stroke-width="8" stroke-linecap="round"/><path d="M70 18 L72 40 L51 38Z" fill="${PALETTE.coral}"/>`,
    info: `<circle cx="48" cy="30" r="7" fill="${PALETTE.amber}"/><path d="M48 43 V69" stroke="${PALETTE.white}" stroke-width="9" stroke-linecap="round"/>`,
  };
  return `${base}${paths[kind]}`;
}

function avatarFrameSvg() {
  return `${sharedDefs()}
  <circle cx="64" cy="64" r="58" fill="${PALETTE.ink}" stroke="${PALETTE.cyan}" stroke-width="7" filter="url(#shadow)"/>
  <circle cx="64" cy="64" r="48" fill="none" stroke="${PALETTE.violet}" stroke-width="6" stroke-dasharray="18 8"/>
  <path d="M22 47 L9 39 M106 47 L119 39 M22 81 L9 89 M106 81 L119 89" stroke="${PALETTE.coral}" stroke-width="6" stroke-linecap="round"/>`;
}

async function writeSvg(name, viewBox, title, description, content) {
  await writeFile(
    resolve(ART_DIR, name),
    svgDocument(viewBox, title, description, content),
    'utf8',
  );
}

function xorshift32(seed) {
  let state = seed >>> 0;
  return () => {
    state ^= state << 13;
    state ^= state >>> 17;
    state ^= state << 5;
    return (state >>> 0) / 4_294_967_296;
  };
}

function oscillator(shape, phase) {
  const cycle = phase - Math.floor(phase);
  if (shape === 'square') return cycle < 0.5 ? 1 : -1;
  if (shape === 'saw') return cycle * 2 - 1;
  if (shape === 'triangle') return 1 - 4 * Math.abs(cycle - 0.5);
  return Math.sin(phase * Math.PI * 2);
}

function envelope(time, duration, attack = 0.01, release = 0.08) {
  const attackGain = attack <= 0 ? 1 : Math.min(1, time / attack);
  const releaseGain = release <= 0 ? 1 : Math.min(1, (duration - time) / release);
  return Math.max(0, Math.min(attackGain, releaseGain));
}

function addTone(buffer, options) {
  const {
    start = 0,
    duration,
    frequency,
    endFrequency = frequency,
    volume = 0.2,
    wave = 'sine',
    attack = 0.01,
    release = 0.08,
    vibratoHz = 0,
    vibratoDepth = 0,
    circular = false,
  } = options;
  const startSample = Math.round(start * SAMPLE_RATE);
  const sampleCount = Math.max(1, Math.round(duration * SAMPLE_RATE));
  let phase = 0;
  for (let index = 0; index < sampleCount; index += 1) {
    const time = index / SAMPLE_RATE;
    const progress = index / sampleCount;
    const baseFrequency = frequency + (endFrequency - frequency) * progress;
    const pitch = baseFrequency * (1 + Math.sin(time * Math.PI * 2 * vibratoHz) * vibratoDepth);
    phase += pitch / SAMPLE_RATE;
    const value = oscillator(wave, phase) * envelope(time, duration, attack, release) * volume;
    const rawIndex = startSample + index;
    if (circular) {
      buffer[((rawIndex % buffer.length) + buffer.length) % buffer.length] += value;
    } else if (rawIndex >= 0 && rawIndex < buffer.length) {
      buffer[rawIndex] += value;
    }
  }
}

function addNoise(buffer, options) {
  const {
    start = 0,
    duration,
    volume = 0.15,
    attack = 0,
    release = 0.1,
    seed = 1,
    color = 'white',
    circular = false,
  } = options;
  const random = xorshift32(seed);
  const startSample = Math.round(start * SAMPLE_RATE);
  const sampleCount = Math.max(1, Math.round(duration * SAMPLE_RATE));
  let previous = 0;
  for (let index = 0; index < sampleCount; index += 1) {
    const white = random() * 2 - 1;
    previous = color === 'soft' ? previous * 0.82 + white * 0.18 : white;
    const time = index / SAMPLE_RATE;
    const value = previous * envelope(time, duration, attack, release) * volume;
    const rawIndex = startSample + index;
    if (circular) {
      buffer[((rawIndex % buffer.length) + buffer.length) % buffer.length] += value;
    } else if (rawIndex >= 0 && rawIndex < buffer.length) {
      buffer[rawIndex] += value;
    }
  }
}

function addKick(buffer, start, circular = false) {
  addTone(buffer, {
    start,
    duration: 0.3,
    frequency: 126,
    endFrequency: 43,
    volume: 0.6,
    wave: 'sine',
    attack: 0.001,
    release: 0.22,
    circular,
  });
  addNoise(buffer, {
    start,
    duration: 0.018,
    volume: 0.17,
    release: 0.015,
    seed: 700 + Math.round(start * 100),
    circular,
  });
}

function addSnare(buffer, start, circular = false) {
  addNoise(buffer, {
    start,
    duration: 0.22,
    volume: 0.27,
    release: 0.18,
    seed: 1_900 + Math.round(start * 100),
    circular,
  });
  addTone(buffer, {
    start,
    duration: 0.18,
    frequency: 176,
    endFrequency: 130,
    volume: 0.18,
    wave: 'triangle',
    attack: 0.002,
    release: 0.15,
    circular,
  });
}

function addHat(buffer, start, open, circular = false) {
  addNoise(buffer, {
    start,
    duration: open ? 0.18 : 0.055,
    volume: open ? 0.09 : 0.07,
    release: open ? 0.15 : 0.045,
    seed: 3_100 + Math.round(start * 1_000),
    circular,
  });
}

function midiToHz(note) {
  return 440 * 2 ** ((note - 69) / 12);
}

function createMusic() {
  const bpm = 140;
  const beat = 60 / bpm;
  const bars = 32;
  const duration = bars * 4 * beat;
  const buffer = new Float64Array(Math.round(duration * SAMPLE_RATE));
  const bassPattern = [42, 42, 49, 42, 45, 45, 52, 45, 38, 38, 45, 38, 40, 40, 47, 40];
  const chordRoots = [54, 57, 50, 52];
  const hook = [66, 69, 73, 69, 64, 66, 69, 73, 71, 69, 66, 64, 61, 64, 66, 69];

  for (let bar = 0; bar < bars; bar += 1) {
    const barStart = bar * 4 * beat;
    const sectionLift = Math.floor(bar / 8) % 2 === 1;
    for (let step = 0; step < 8; step += 1) {
      const start = barStart + step * beat * 0.5;
      addHat(buffer, start, step === 7, true);
      if (step % 2 === 0) addKick(buffer, start, true);
      if (step === 2 || step === 6) addSnare(buffer, start, true);
      const bassNote = bassPattern[(bar * 2 + Math.floor(step / 4)) % bassPattern.length];
      addTone(buffer, {
        start,
        duration: beat * 0.47,
        frequency: midiToHz(bassNote),
        volume: 0.18,
        wave: 'square',
        attack: 0.006,
        release: 0.08,
        circular: true,
      });
    }

    const chordRoot = chordRoots[bar % chordRoots.length];
    for (const interval of [0, 3, 7]) {
      addTone(buffer, {
        start: barStart,
        duration: beat * 3.85,
        frequency: midiToHz(chordRoot + interval),
        volume: 0.035,
        wave: 'saw',
        attack: 0.08,
        release: 0.25,
        vibratoHz: 4.5,
        vibratoDepth: 0.002,
        circular: true,
      });
    }

    for (let step = 0; step < 16; step += 1) {
      const note =
        chordRoot + [12, 15, 19, 22][step % 4] + (sectionLift && step % 8 === 7 ? 12 : 0);
      addTone(buffer, {
        start: barStart + step * beat * 0.25,
        duration: beat * 0.2,
        frequency: midiToHz(note),
        volume: 0.055,
        wave: 'triangle',
        attack: 0.004,
        release: 0.045,
        circular: true,
      });
    }

    if (bar % 4 >= 2) {
      for (let step = 0; step < 8; step += 1) {
        const note = hook[(bar * 4 + step) % hook.length] + (sectionLift ? 12 : 0);
        addTone(buffer, {
          start: barStart + step * beat * 0.5,
          duration: beat * (step % 4 === 3 ? 0.8 : 0.34),
          frequency: midiToHz(note),
          volume: 0.09,
          wave: 'square',
          attack: 0.008,
          release: 0.1,
          vibratoHz: 5.8,
          vibratoDepth: 0.004,
          circular: true,
        });
      }
    }
  }

  for (let index = 0; index < buffer.length; index += 1) {
    buffer[index] = Math.tanh(buffer[index] * 1.15) * 0.72;
  }
  return { buffer, bpm, bars, duration };
}

function createSfx() {
  const make = (seconds) => new Float64Array(Math.ceil(seconds * SAMPLE_RATE));
  const output = {};

  output['ui-hover.wav'] = make(0.09);
  addTone(output['ui-hover.wav'], {
    duration: 0.08,
    frequency: 900,
    endFrequency: 1_240,
    volume: 0.22,
    wave: 'triangle',
    release: 0.05,
  });

  output['ui-select.wav'] = make(0.2);
  addTone(output['ui-select.wav'], {
    duration: 0.09,
    frequency: 560,
    endFrequency: 760,
    volume: 0.25,
    wave: 'square',
    release: 0.05,
  });
  addTone(output['ui-select.wav'], {
    start: 0.085,
    duration: 0.1,
    frequency: 840,
    volume: 0.23,
    wave: 'triangle',
    release: 0.07,
  });

  output['countdown.wav'] = make(0.28);
  addTone(output['countdown.wav'], {
    duration: 0.25,
    frequency: 740,
    volume: 0.27,
    wave: 'square',
    attack: 0.003,
    release: 0.13,
  });
  addTone(output['countdown.wav'], {
    duration: 0.25,
    frequency: 1_480,
    volume: 0.08,
    wave: 'sine',
    attack: 0.003,
    release: 0.18,
  });

  output['snap.wav'] = make(0.28);
  addKick(output['snap.wav'], 0);
  addNoise(output['snap.wav'], {
    start: 0.025,
    duration: 0.09,
    volume: 0.2,
    release: 0.07,
    seed: 44,
  });
  addTone(output['snap.wav'], {
    start: 0.05,
    duration: 0.19,
    frequency: 250,
    endFrequency: 115,
    volume: 0.2,
    wave: 'triangle',
    release: 0.14,
  });

  output['throw.wav'] = make(0.34);
  addNoise(output['throw.wav'], {
    duration: 0.31,
    volume: 0.24,
    attack: 0.05,
    release: 0.13,
    seed: 88,
    color: 'soft',
  });
  addTone(output['throw.wav'], {
    duration: 0.29,
    frequency: 210,
    endFrequency: 690,
    volume: 0.16,
    wave: 'sine',
    attack: 0.03,
    release: 0.09,
  });

  output['flight.wav'] = make(0.72);
  addNoise(output['flight.wav'], {
    duration: 0.68,
    volume: 0.14,
    attack: 0.12,
    release: 0.2,
    seed: 120,
    color: 'soft',
  });
  addTone(output['flight.wav'], {
    duration: 0.66,
    frequency: 118,
    endFrequency: 182,
    volume: 0.07,
    wave: 'sine',
    attack: 0.12,
    release: 0.18,
    vibratoHz: 10,
    vibratoDepth: 0.08,
  });

  output['catch.wav'] = make(0.32);
  addNoise(output['catch.wav'], {
    duration: 0.08,
    volume: 0.3,
    release: 0.06,
    seed: 303,
    color: 'soft',
  });
  addTone(output['catch.wav'], {
    duration: 0.28,
    frequency: 170,
    endFrequency: 74,
    volume: 0.38,
    wave: 'sine',
    attack: 0.002,
    release: 0.19,
  });

  output['deep-completion.wav'] = make(0.62);
  [0, 4, 7, 12].forEach((interval, index) =>
    addTone(output['deep-completion.wav'], {
      start: index * 0.09,
      duration: 0.32,
      frequency: midiToHz(66 + interval),
      volume: 0.16,
      wave: 'triangle',
      release: 0.2,
    }),
  );

  output['touchdown.wav'] = make(1.55);
  [0, 4, 7, 12, 16].forEach((interval, index) =>
    addTone(output['touchdown.wav'], {
      start: index * 0.12,
      duration: 0.58,
      frequency: midiToHz(61 + interval),
      volume: 0.16,
      wave: index % 2 ? 'square' : 'triangle',
      release: 0.3,
    }),
  );
  [0, 0.42, 0.84].forEach((start) => addKick(output['touchdown.wav'], start));
  addNoise(output['touchdown.wav'], {
    start: 0.72,
    duration: 0.72,
    volume: 0.08,
    attack: 0.16,
    release: 0.42,
    seed: 404,
  });

  output['bonus-active.wav'] = make(1.0);
  [0, 3, 7, 10, 12, 19].forEach((interval, index) =>
    addTone(output['bonus-active.wav'], {
      start: index * 0.1,
      duration: 0.42,
      frequency: midiToHz(72 + interval),
      volume: 0.12,
      wave: 'sine',
      release: 0.28,
    }),
  );
  addNoise(output['bonus-active.wav'], {
    start: 0.45,
    duration: 0.45,
    volume: 0.06,
    attack: 0.12,
    release: 0.3,
    seed: 505,
  });

  output['multiplier.wav'] = make(0.58);
  addTone(output['multiplier.wav'], {
    duration: 0.5,
    frequency: 390,
    endFrequency: 1_180,
    volume: 0.22,
    wave: 'triangle',
    attack: 0.01,
    release: 0.16,
  });
  addTone(output['multiplier.wav'], {
    start: 0.22,
    duration: 0.3,
    frequency: 1_560,
    volume: 0.12,
    wave: 'sine',
    release: 0.2,
  });

  output['incomplete.wav'] = make(0.56);
  addTone(output['incomplete.wav'], {
    duration: 0.5,
    frequency: 330,
    endFrequency: 135,
    volume: 0.27,
    wave: 'square',
    attack: 0.01,
    release: 0.2,
  });
  addNoise(output['incomplete.wav'], {
    start: 0.26,
    duration: 0.23,
    volume: 0.1,
    release: 0.18,
    seed: 606,
  });

  output['interception.wav'] = make(0.82);
  addTone(output['interception.wav'], {
    duration: 0.72,
    frequency: 245,
    endFrequency: 160,
    volume: 0.25,
    wave: 'saw',
    attack: 0.01,
    release: 0.22,
    vibratoHz: 8,
    vibratoDepth: 0.06,
  });
  addTone(output['interception.wav'], {
    start: 0.05,
    duration: 0.6,
    frequency: 370,
    endFrequency: 220,
    volume: 0.2,
    wave: 'square',
    attack: 0.01,
    release: 0.2,
  });
  addNoise(output['interception.wav'], { duration: 0.18, volume: 0.15, release: 0.12, seed: 707 });

  output['meter-loss.wav'] = make(0.72);
  for (let index = 0; index < 6; index += 1) {
    addTone(output['meter-loss.wav'], {
      start: index * 0.075,
      duration: 0.27,
      frequency: 1_100 - index * 135,
      endFrequency: 760 - index * 105,
      volume: 0.09,
      wave: 'square',
      release: 0.16,
    });
  }
  addNoise(output['meter-loss.wav'], {
    start: 0.25,
    duration: 0.38,
    volume: 0.09,
    release: 0.32,
    seed: 808,
  });

  output['timer-warning.wav'] = make(0.29);
  addTone(output['timer-warning.wav'], {
    duration: 0.25,
    frequency: 1_020,
    volume: 0.28,
    wave: 'square',
    attack: 0.003,
    release: 0.09,
  });
  addTone(output['timer-warning.wav'], {
    duration: 0.25,
    frequency: 510,
    volume: 0.12,
    wave: 'triangle',
    attack: 0.003,
    release: 0.12,
  });

  output['game-over.wav'] = make(1.8);
  [0, 3, 7, 12, 7, 15].forEach((interval, index) =>
    addTone(output['game-over.wav'], {
      start: index * 0.17,
      duration: index === 5 ? 0.85 : 0.35,
      frequency: midiToHz(54 + interval),
      volume: 0.15,
      wave: index % 2 ? 'triangle' : 'square',
      release: index === 5 ? 0.55 : 0.2,
    }),
  );
  addKick(output['game-over.wav'], 0.02);
  addKick(output['game-over.wav'], 0.7);

  output['continue-success.wav'] = make(1.2);
  addTone(output['continue-success.wav'], {
    duration: 0.94,
    frequency: 155,
    endFrequency: 960,
    volume: 0.18,
    wave: 'saw',
    attack: 0.05,
    release: 0.24,
  });
  [0, 4, 7, 12].forEach((interval, index) =>
    addTone(output['continue-success.wav'], {
      start: 0.28 + index * 0.12,
      duration: 0.5,
      frequency: midiToHz(64 + interval),
      volume: 0.12,
      wave: 'triangle',
      release: 0.3,
    }),
  );
  addNoise(output['continue-success.wav'], {
    start: 0.55,
    duration: 0.5,
    volume: 0.055,
    attack: 0.12,
    release: 0.33,
    seed: 909,
  });

  return output;
}

function encodeWav(samples) {
  let peak = 0;
  for (const sample of samples) peak = Math.max(peak, Math.abs(sample));
  const gain = peak > 0.92 ? 0.92 / peak : 1;
  const byteLength = 44 + samples.length * 2;
  const wav = Buffer.alloc(byteLength);
  wav.write('RIFF', 0);
  wav.writeUInt32LE(byteLength - 8, 4);
  wav.write('WAVE', 8);
  wav.write('fmt ', 12);
  wav.writeUInt32LE(16, 16);
  wav.writeUInt16LE(1, 20);
  wav.writeUInt16LE(1, 22);
  wav.writeUInt32LE(SAMPLE_RATE, 24);
  wav.writeUInt32LE(SAMPLE_RATE * 2, 28);
  wav.writeUInt16LE(2, 32);
  wav.writeUInt16LE(16, 34);
  wav.write('data', 36);
  wav.writeUInt32LE(samples.length * 2, 40);
  for (let index = 0; index < samples.length; index += 1) {
    const shaped = Math.tanh(samples[index] * gain * 1.08);
    wav.writeInt16LE(Math.round(Math.max(-1, Math.min(1, shaped)) * 32_767), 44 + index * 2);
  }
  return wav;
}

async function generateArt() {
  await writeSvg(
    'logo.svg',
    '0 0 800 320',
    'Pocket Vector logo',
    'Neon arcade football wordmark with an original PV emblem.',
    logoSvg(),
  );
  await writeSvg(
    'field.svg',
    '0 0 1024 768',
    'Vector City football field',
    'Pseudo-perspective football field for a 4 by 3 arcade playfield.',
    fieldSvg(),
  );
  await writeSvg(
    'aim-destination-x.svg',
    '0 0 96 96',
    'Pass destination marker',
    'Coral destination X with a readable crosshair.',
    destinationXSvg(),
  );
  for (const pose of ['idle', 'aim', 'throw', 'recovery']) {
    await writeSvg(
      `qb-${pose}.svg`,
      '0 0 200 260',
      `Quarterback ${pose}`,
      `Nova City Comets quarterback number 7 in the ${pose} animation pose.`,
      quarterbackSvg(pose),
    );
  }
  for (const pose of ['run1', 'run2', 'catch', 'touchdown']) {
    const filename = pose.startsWith('run')
      ? `receiver-run-${pose.slice(-1)}.svg`
      : `receiver-${pose}.svg`;
    await writeSvg(
      filename,
      '0 0 200 260',
      `Receiver ${pose}`,
      `Nova City Comets receiver number 11 in the ${pose} animation pose.`,
      runnerSvg({ team: OFFENSE, pose, role: 'receiver' }),
    );
  }
  for (const pose of ['run1', 'run2', 'interception']) {
    const filename = pose.startsWith('run')
      ? `defender-run-${pose.slice(-1)}.svg`
      : `defender-${pose}.svg`;
    await writeSvg(
      filename,
      '0 0 200 260',
      `Defender ${pose}`,
      `Iron Bay Phantoms defender number 24 in the ${pose} animation pose.`,
      runnerSvg({ team: DEFENSE, pose, role: 'defender' }),
    );
  }
  await writeSvg(
    'football.svg',
    '0 0 128 96',
    'Arcade football',
    'Rotation-ready original football sprite with transparent background.',
    footballSvg(),
  );
  await writeSvg(
    'effect-score.svg',
    '0 0 256 256',
    'Score burst',
    'Layered arcade burst for score popup animation.',
    scoreBurstSvg(),
  );
  await writeSvg(
    'effect-completion.svg',
    '0 0 256 256',
    'Completion effect',
    'Cyan rings and check mark for completed passes.',
    completionEffectSvg(),
  );
  await writeSvg(
    'effect-touchdown.svg',
    '0 0 256 256',
    'Touchdown effect',
    'Amber starburst with a coral lightning bolt.',
    touchdownEffectSvg(),
  );
  await writeSvg(
    'effect-interception.svg',
    '0 0 256 256',
    'Interception effect',
    'Coral warning shield with a white X.',
    interceptionEffectSvg(),
  );
  await writeSvg(
    'meter-frame.svg',
    '0 0 360 58',
    'TD Bonus meter frame',
    'Dark neon frame sized for a twelve-segment bonus meter.',
    meterFrameSvg(),
  );
  await writeSvg(
    'meter-fill.svg',
    '0 0 360 58',
    'TD Bonus meter fill',
    'Cyan segmented fill that can be clipped to authoritative progress.',
    meterFillSvg(),
  );
  await writeSvg(
    'multiplier.svg',
    '0 0 200 128',
    'Touchdown multiplier badge',
    'Violet arcade badge used beneath a dynamic multiplier value.',
    multiplierBadgeSvg(),
  );
  await writeSvg(
    'timer-warning.svg',
    '0 0 128 128',
    'Timer warning',
    'Coral countdown clock for the final seconds.',
    timerWarningSvg(),
  );
  await writeSvg(
    'button.svg',
    '0 0 360 96',
    'Primary button frame',
    'Cyan beveled touch button surface without baked-in text.',
    buttonSvg(true),
  );
  await writeSvg(
    'ui-button-secondary.svg',
    '0 0 360 96',
    'Secondary button frame',
    'Midnight and violet beveled touch button surface without baked-in text.',
    buttonSvg(false),
  );
  for (const kind of ['mute', 'unmute', 'pause', 'play', 'restart', 'info']) {
    await writeSvg(
      `icon-${kind}.svg`,
      '0 0 96 96',
      `${kind} icon`,
      `High-contrast ${kind} control icon.`,
      iconSvg(kind),
    );
  }
  await writeSvg(
    'avatar-frame.svg',
    '0 0 128 128',
    'Player avatar frame',
    'Neon circular frame for an optional platform avatar.',
    avatarFrameSvg(),
  );
}

async function generateAudio() {
  const music = createMusic();
  await writeFile(resolve(MUSIC_DIR, 'pocket-vector-drive.wav'), encodeWav(music.buffer));
  const sfx = createSfx();
  await Promise.all(
    Object.entries(sfx).map(([name, samples]) =>
      writeFile(resolve(SFX_DIR, name), encodeWav(samples)),
    ),
  );
  return music;
}

async function main() {
  await Promise.all([
    mkdir(ART_DIR, { recursive: true }),
    mkdir(MUSIC_DIR, { recursive: true }),
    mkdir(SFX_DIR, { recursive: true }),
  ]);
  await generateArt();
  const music = await generateAudio();
  const manifest = {
    schemaVersion: 1,
    title: 'Pocket Vector',
    generation: {
      command: 'npm run generate:assets',
      generator: 'scripts/generate-assets.mjs',
      deterministic: true,
      sampleRateHz: SAMPLE_RATE,
      musicBpm: music.bpm,
      musicBars: music.bars,
      musicDurationSeconds: Number(music.duration.toFixed(6)),
    },
    teams: {
      offense: {
        name: 'Nova City Comets',
        colors: { primary: PALETTE.cyan, secondary: PALETTE.violet, trim: PALETTE.white },
      },
      defense: {
        name: 'Iron Bay Phantoms',
        colors: { primary: PALETTE.coral, secondary: PALETTE.navy, trim: PALETTE.amber },
      },
    },
    palette: PALETTE,
    spriteGeometry: {
      playerViewBox: { x: 0, y: 0, width: 200, height: 260 },
      playerAnchor: { x: 100, y: 246 },
      footballViewBox: { x: 0, y: 0, width: 128, height: 96 },
      footballAnchor: { x: 64, y: 48 },
      fieldViewBox: { x: 0, y: 0, width: 1024, height: 768 },
    },
    art: ART,
    audio: AUDIO,
  };
  await writeFile(
    resolve(ROOT, 'public/assets/asset-manifest.json'),
    `${JSON.stringify(manifest, null, 2)}\n`,
    'utf8',
  );
  process.stdout.write(
    `Generated ${countStringLeaves(ART)} SVG assets, ${Object.keys(AUDIO.sfx).length} sound effects, and ${music.duration.toFixed(2)}s of music.\n`,
  );
}

await main();

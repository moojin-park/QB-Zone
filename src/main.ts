import './style.css';

import { WORLD } from './game/config';
import { createInputController } from './game/input';
import { getBallPosition, updateGameState } from './game/logic';
import { renderGame } from './game/render';
import { createInitialState } from './game/state';

interface HudElements {
  score: HTMLElement;
  meterFill: HTMLElement;
  meterText: HTMLElement;
  lastPlay: HTMLElement;
  resetButton: HTMLButtonElement;
}

function getElement<T extends HTMLElement>(id: string): T {
  const element = document.getElementById(id);
  if (!element) {
    throw new Error(`Missing element: ${id}`);
  }
  return element as T;
}

const canvas = getElement<HTMLCanvasElement>('game-canvas');
const context = canvas.getContext('2d');
if (!context) {
  throw new Error('2D context unavailable');
}

const hud: HudElements = {
  score: getElement('score'),
  meterFill: getElement('meter-fill'),
  meterText: getElement('meter-text'),
  lastPlay: getElement('last-play'),
  resetButton: getElement('reset-btn')
};

let state = createInitialState();
let cssWidth = 0;
let cssHeight = 0;
let devicePixelRatioValue = Math.max(1, window.devicePixelRatio || 1);

const getCanvasSize = (): { width: number; height: number } => ({
  width: cssWidth,
  height: cssHeight
});

const input = createInputController(canvas, getCanvasSize);

function updateHud(): void {
  hud.score.textContent = `Score: ${state.score}`;
  hud.meterFill.style.width = `${state.meter}%`;
  hud.meterText.textContent = `${Math.round(state.meter)}%`;
  hud.lastPlay.textContent = state.lastPlayText;
}

function resizeCanvas(): void {
  const rect = canvas.getBoundingClientRect();
  cssWidth = Math.max(1, Math.floor(rect.width));
  cssHeight = Math.max(1, Math.floor(rect.height));
  devicePixelRatioValue = Math.max(1, window.devicePixelRatio || 1);

  canvas.width = Math.floor(cssWidth * devicePixelRatioValue);
  canvas.height = Math.floor(cssHeight * devicePixelRatioValue);
  context.setTransform(devicePixelRatioValue, 0, 0, devicePixelRatioValue, 0, 0);
}

function draw(): void {
  context.setTransform(devicePixelRatioValue, 0, 0, devicePixelRatioValue, 0, 0);
  renderGame(context, state, cssWidth, cssHeight, input.getAimPreview());
}

function step(dt: number): void {
  const throwIntent = input.consumeThrowIntent();
  state = updateGameState(state, dt, { throwIntent: throwIntent ?? undefined });
}

let previousTime = performance.now();

function frame(time: number): void {
  const elapsed = (time - previousTime) / 1000;
  previousTime = time;
  const dt = Math.min(elapsed, WORLD.maxDeltaSeconds);

  step(dt);
  updateHud();
  draw();

  requestAnimationFrame(frame);
}

hud.resetButton.addEventListener('click', () => {
  state = createInitialState();
  updateHud();
  draw();
});

window.addEventListener('resize', () => {
  resizeCanvas();
  draw();
});

interface TestBridge {
  advanceTime: (ms: number) => void;
  render_game_to_text: () => string;
}

const bridge = window as Window & Partial<TestBridge>;

bridge.advanceTime = (ms: number): void => {
  const fixedStep = 1 / 60;
  let remaining = Math.max(0, ms) / 1000;

  while (remaining > 0) {
    const dt = Math.min(fixedStep, remaining, WORLD.maxDeltaSeconds);
    step(dt);
    remaining -= dt;
  }

  updateHud();
  draw();
};

bridge.render_game_to_text = (): string => {
  const ball = state.ball ? getBallPosition(state.ball) : null;
  return JSON.stringify({
    coordinateSystem: 'origin at QB. x=left/right, z=forward toward endzone.',
    score: state.score,
    meter: state.meter,
    lastPlay: state.lastPlayText,
    receivers: state.receivers.map((receiver) => ({
      id: receiver.id,
      depth: receiver.depth,
      x: Number(receiver.x.toFixed(2)),
      z: Number(receiver.z.toFixed(2))
    })),
    defender: {
      x: Number(state.defender.x.toFixed(2)),
      z: Number(state.defender.z.toFixed(2))
    },
    ball,
    inputHint: 'Drag and release to throw. Target depth snaps to nearest lane.'
  });
};

resizeCanvas();
updateHud();
draw();
requestAnimationFrame(frame);

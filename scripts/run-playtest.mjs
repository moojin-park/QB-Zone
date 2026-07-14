import { mkdir, rm, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright';

const baseUrl = process.env.PLAYTEST_URL ?? 'http://127.0.0.1:5173/';
const outputDirectory = fileURLToPath(new URL('../output/playtest/', import.meta.url));
const failures = [];
const consoleErrors = [];
const lastMouseTimestampByPage = new WeakMap();

const check = (condition, message) => {
  if (!condition) failures.push(message);
};

const state = async (page) =>
  JSON.parse(
    await page.evaluate(() => {
      if (!window.render_game_to_text) throw new Error('render_game_to_text is unavailable');
      return window.render_game_to_text();
    }),
  );

const advance = async (page, milliseconds) => {
  await page.evaluate((duration) => window.advanceTime?.(duration), milliseconds);
  await page.waitForTimeout(0);
};

const setSimulationSpeed = (page, value) =>
  page.evaluate((speed) => {
    const input = document.querySelector('[data-debug-control="slow-motion"]');
    if (!(input instanceof HTMLInputElement)) throw new Error('Missing slow-motion control');
    input.value = String(speed);
    input.dispatchEvent(new Event('change', { bubbles: true }));
  }, value);

const observeConsole = (page, label) => {
  page.on('console', (message) => {
    if (message.type() === 'error') consoleErrors.push(`${label}: ${message.text()}`);
  });
  page.on('pageerror', (error) => consoleErrors.push(`${label}: ${error.message}`));
};

const waitForPhase = async (page, phase) => {
  await page.waitForFunction((expected) => {
    if (!window.render_game_to_text) return false;
    return JSON.parse(window.render_game_to_text()).phase === expected;
  }, phase);
};

const enterGameplay = async (page) => {
  await page.locator('#play-button').click();
  const current = await state(page);
  if (current.phase === 'instructions') await page.locator('#instructions-play-button').click();
  await advance(page, 3_050);
  await waitForPhase(page, 'playing');
};

const logicalToClient = async (page, point) => {
  const canvas = page.locator('#game-canvas');
  const box = await canvas.boundingBox();
  if (!box) throw new Error('Canvas has no bounding box');
  const current = await state(page);
  const match = /([0-9]+)x([0-9]+)$/.exec(current.coordinateSystem);
  if (!match) throw new Error(`Unknown coordinate system: ${current.coordinateSystem}`);
  return {
    x: box.x + (point.x / Number(match[1])) * box.width,
    y: box.y + (point.y / Number(match[2])) * box.height,
  };
};

const mouseThrow = async (page, target, { durationMs = 70, aimScreenshot } = {}) => {
  const current = await state(page);
  const start = await logicalToClient(page, {
    x: current.quarterback.x + current.quarterback.width / 2,
    y: current.quarterback.y + current.quarterback.height * 0.55,
  });
  const end = await logicalToClient(page, target);
  const client = await page.context().newCDPSession(page);
  const steps = Math.max(8, Math.round(durationMs / 14));
  const durationSeconds = durationMs / 1_000;
  const timestampBase = Math.max(
    Date.now() / 1_000 + 0.1,
    (lastMouseTimestampByPage.get(page) ?? 0) + 0.01,
  );
  await client.send('Input.dispatchMouseEvent', {
    type: 'mouseMoved',
    x: start.x,
    y: start.y,
    timestamp: timestampBase,
  });
  await client.send('Input.dispatchMouseEvent', {
    type: 'mousePressed',
    x: start.x,
    y: start.y,
    button: 'left',
    clickCount: 1,
    timestamp: timestampBase + 0.001,
  });
  for (let index = 1; index <= steps; index += 1) {
    const progress = index / steps;
    const x = start.x + (end.x - start.x) * progress;
    const y = start.y + (end.y - start.y) * progress;
    await client.send('Input.dispatchMouseEvent', {
      type: 'mouseMoved',
      x,
      y,
      button: 'left',
      buttons: 1,
      timestamp: timestampBase + durationSeconds * progress,
    });
    if (aimScreenshot && index === Math.ceil(steps * 0.5)) {
      await page.waitForTimeout(34);
      await page.screenshot({ path: aimScreenshot });
    }
  }
  await client.send('Input.dispatchMouseEvent', {
    type: 'mouseReleased',
    x: end.x,
    y: end.y,
    button: 'left',
    clickCount: 1,
    timestamp: timestampBase + durationSeconds + 0.002,
  });
  lastMouseTimestampByPage.set(page, timestampBase + durationSeconds + 0.002);
  await client.detach();
};

const pausedTrackpadThrow = async (page, target) => {
  const current = await state(page);
  const start = await logicalToClient(page, {
    x: current.quarterback.x + current.quarterback.width / 2,
    y: current.quarterback.y + current.quarterback.height * 0.55,
  });
  const end = await logicalToClient(page, target);
  const client = await page.context().newCDPSession(page);
  const timestampBase = Math.max(
    Date.now() / 1_000 + 0.1,
    (lastMouseTimestampByPage.get(page) ?? 0) + 0.01,
  );
  await client.send('Input.dispatchMouseEvent', {
    type: 'mouseMoved',
    x: start.x,
    y: start.y,
    timestamp: timestampBase,
  });
  await client.send('Input.dispatchMouseEvent', {
    type: 'mousePressed',
    x: start.x,
    y: start.y,
    button: 'left',
    buttons: 1,
    clickCount: 1,
    timestamp: timestampBase + 0.001,
  });
  for (let index = 1; index <= 6; index += 1) {
    const progress = index / 6;
    await client.send('Input.dispatchMouseEvent', {
      type: 'mouseMoved',
      x: start.x + (end.x - start.x) * progress,
      y: start.y + (end.y - start.y) * progress,
      button: 'left',
      buttons: 1,
      timestamp: timestampBase + progress * 3,
    });
  }
  // Model a trackpad pause at the destination followed by final events whose
  // button mask has already dropped to zero.
  for (let index = 1; index <= 4; index += 1) {
    await client.send('Input.dispatchMouseEvent', {
      type: 'mouseMoved',
      x: end.x,
      y: end.y,
      buttons: 0,
      timestamp: timestampBase + 3 + index * 0.1,
    });
  }
  await client.send('Input.dispatchMouseEvent', {
    type: 'mouseReleased',
    x: end.x,
    y: end.y,
    button: 'left',
    buttons: 0,
    clickCount: 1,
    timestamp: timestampBase + 3.5,
  });
  lastMouseTimestampByPage.set(page, timestampBase + 3.5);
  await client.detach();
};

const captureAim = async (page, target, path) => {
  const current = await state(page);
  const start = await logicalToClient(page, {
    x: current.quarterback.x + current.quarterback.width / 2,
    y: current.quarterback.y + current.quarterback.height * 0.55,
  });
  const end = await logicalToClient(page, target);
  await page.evaluate(() => {
    const canvas = document.querySelector('#game-canvas');
    if (!(canvas instanceof HTMLCanvasElement)) throw new Error('Missing canvas');
    canvas.addEventListener(
      'pointerdown',
      (event) => {
        canvas.dataset.playtestPointerId = String(event.pointerId);
      },
      { once: true },
    );
  });
  await page.mouse.move(start.x, start.y);
  await page.mouse.down();
  await page.mouse.move(end.x, end.y, { steps: 4 });
  await page.waitForTimeout(34);
  await page.screenshot({ path });
  await page.evaluate(() => {
    const canvas = document.querySelector('#game-canvas');
    if (!(canvas instanceof HTMLCanvasElement)) throw new Error('Missing canvas');
    canvas.dispatchEvent(
      new PointerEvent('pointercancel', {
        pointerId: Number(canvas.dataset.playtestPointerId),
        pointerType: 'mouse',
        bubbles: true,
      }),
    );
  });
  await page.mouse.up();
};

const touchThrow = async (context, page, target) => {
  const current = await state(page);
  const start = await logicalToClient(page, {
    x: current.quarterback.x + current.quarterback.width / 2,
    y: current.quarterback.y + current.quarterback.height * 0.55,
  });
  const end = await logicalToClient(page, target);
  const client = await context.newCDPSession(page);
  await client.send('Input.dispatchTouchEvent', {
    type: 'touchStart',
    touchPoints: [{ x: start.x, y: start.y, id: 1, radiusX: 8, radiusY: 8 }],
  });
  for (let index = 1; index <= 6; index += 1) {
    const progress = index / 6;
    await client.send('Input.dispatchTouchEvent', {
      type: 'touchMove',
      touchPoints: [
        {
          x: start.x + (end.x - start.x) * progress,
          y: start.y + (end.y - start.y) * progress,
          id: 1,
          radiusX: 8,
          radiusY: 8,
        },
      ],
    });
    await page.waitForTimeout(14);
  }
  await client.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
  await client.detach();
};

const cancelMouseGesture = async (page) => {
  const current = await state(page);
  const start = await logicalToClient(page, {
    x: current.quarterback.x + current.quarterback.width / 2,
    y: current.quarterback.y + current.quarterback.height * 0.55,
  });
  await page.evaluate(() => {
    const canvas = document.querySelector('#game-canvas');
    if (!(canvas instanceof HTMLCanvasElement)) throw new Error('Missing canvas');
    canvas.addEventListener(
      'pointerdown',
      (event) => {
        canvas.dataset.playtestPointerId = String(event.pointerId);
      },
      { once: true },
    );
  });
  await page.mouse.move(start.x, start.y);
  await page.mouse.down();
  await page.mouse.move(start.x + 40, start.y - 90);
  await page.evaluate(() => {
    const canvas = document.querySelector('#game-canvas');
    if (!(canvas instanceof HTMLCanvasElement)) throw new Error('Missing canvas');
    const pointerId = Number(canvas.dataset.playtestPointerId);
    canvas.dispatchEvent(
      new PointerEvent('pointercancel', {
        pointerId,
        pointerType: 'mouse',
        bubbles: true,
      }),
    );
  });
  await page.mouse.up();
};

const forceOutcome = async (page, outcome) => {
  await page.evaluate((value) => {
    const button = document.querySelector(`[data-debug-action="${value}"]`);
    if (!(button instanceof HTMLButtonElement)) throw new Error(`Missing debug outcome: ${value}`);
    button.click();
  }, outcome);
  await advance(page, 40);
  await advance(page, 460);
};

const screenshot = (page, name) =>
  page.screenshot({ path: join(outputDirectory, `${name}.png`), fullPage: true });

await rm(outputDirectory, { recursive: true, force: true });
await mkdir(outputDirectory, { recursive: true });

const browser = await chromium.launch({ headless: true });
try {
  const desktop = await browser.newContext({ viewport: { width: 1024, height: 768 } });
  const page = await desktop.newPage();
  observeConsole(page, 'desktop');
  await page.goto(baseUrl, { waitUntil: 'networkidle' });
  await waitForPhase(page, 'title');
  check(
    (await state(page)).remainingMs === 60_000,
    'Title screen must retain the full 60-second timer',
  );
  await screenshot(page, '01-title-4x3');

  await page.locator('#how-button').click();
  check(
    (await state(page)).phase === 'instructions',
    'Instructions must open from the title screen',
  );
  await advance(page, 5_000);
  check((await state(page)).remainingMs === 60_000, 'Instructions must not consume gameplay time');
  await screenshot(page, '02-instructions');
  await page.locator('#instructions-back-button').click();

  await enterGameplay(page);
  await screenshot(page, '03-gameplay-4x3');
  console.log('[playtest] desktop gameplay ready');

  await pausedTrackpadThrow(page, { x: 512, y: 500 });
  const trackpadBall = (await state(page)).ball;
  check(Boolean(trackpadBall), 'A slow trackpad drag that pauses before release must throw');
  check(
    (trackpadBall?.durationMs ?? 0) > 1_000,
    'A slow paused trackpad drag must become a lob rather than a failed gesture',
  );
  await advance(page, 1_500);

  const startState = await state(page);
  const shortReceiver = startState.receivers.find((receiver) => receiver.lane === 'short');
  check(Boolean(shortReceiver), 'A short-lane receiver must be available');
  if (shortReceiver) {
    const shortTarget = {
      x: shortReceiver.x + shortReceiver.direction * 76,
      y: shortReceiver.y,
    };
    await mouseThrow(page, shortTarget, { durationMs: 70 });
    const afterFastThrow = await state(page);
    const ball = afterFastThrow.ball;
    check(
      Boolean(ball),
      `A fast mouse swipe from the quarterback must release a ball (${JSON.stringify({ feedback: afterFastThrow.feedback, canThrow: afterFastThrow.canThrow, input: afterFastThrow.input })})`,
    );
    const fastDuration = ball?.durationMs ?? Number.POSITIVE_INFINITY;
    await advance(page, 1_400);

    let realCompletions =
      (await state(page)).stats.completions + (await state(page)).stats.touchdowns;

    await advance(page, 300);
    const slowTargetState = await state(page);
    const mediumReceiver = slowTargetState.receivers.find((receiver) => receiver.lane === 'medium');
    if (mediumReceiver) {
      await mouseThrow(
        page,
        { x: mediumReceiver.x + mediumReceiver.direction * 155, y: mediumReceiver.y },
        { durationMs: 430 },
      );
      const slowBall = (await state(page)).ball;
      check(Boolean(slowBall), 'A slow mouse swipe from the quarterback must release a lob');
      check(
        (slowBall?.durationMs ?? 0) > fastDuration,
        'A slow swipe must produce a longer flight than a fast swipe',
      );
      await advance(page, 1_500);
      const afterSlow = await state(page);
      realCompletions = afterSlow.stats.completions + afterSlow.stats.touchdowns;
    }

    for (let attempt = 0; attempt < 6 && realCompletions === 0; attempt += 1) {
      await advance(page, 300);
      await setSimulationSpeed(page, 0.1);
      const attemptState = await state(page);
      const receiver = attemptState.receivers.find((candidate) => candidate.lane === 'short');
      if (!receiver) {
        await setSimulationSpeed(page, 1);
        continue;
      }
      await mouseThrow(
        page,
        { x: receiver.x + receiver.direction * (85 + attempt * 12), y: receiver.y },
        { durationMs: 65 },
      );
      await setSimulationSpeed(page, 1);
      await advance(page, 700);
      const resolved = await state(page);
      realCompletions = resolved.stats.completions + resolved.stats.touchdowns;
    }
    check(realCompletions > 0, 'At least one genuinely aimed lead throw must be catchable');
    console.log('[playtest] gesture and lead-pass checks complete');

    await advance(page, 300);
    const rapidState = await state(page);
    const rapidReceiver = rapidState.receivers.find((receiver) => receiver.lane === 'medium');
    if (rapidReceiver) {
      const target = { x: rapidReceiver.x + rapidReceiver.direction * 80, y: rapidReceiver.y };
      await mouseThrow(page, target, { durationMs: 60 });
      const firstBallId = (await state(page)).ball?.id;
      await mouseThrow(page, target, { durationMs: 60 });
      check(
        (await state(page)).ball?.id === firstBallId,
        'Rapid repeated gestures must not create a second ball',
      );
      await advance(page, 1_400);
    }

    await advance(page, 300);
    await mouseThrow(page, { x: 1_600, y: -80 }, { durationMs: 60 });
    check(
      Boolean((await state(page)).ball),
      'Releasing outside the canvas must safely resolve the captured gesture',
    );
    await advance(page, 1_500);
  }

  await page.locator('#pause-button').click();
  const pausedAt = (await state(page)).remainingMs;
  await advance(page, 2_000);
  check((await state(page)).remainingMs === pausedAt, 'Pause must freeze the gameplay timer');
  await screenshot(page, '05-pause-settings');
  await page.locator('#resume-button').click();
  check((await state(page)).phase === 'playing', 'Resume must return to gameplay');

  for (let index = 0; index < 6; index += 1) await forceOutcome(page, 'complete');
  await forceOutcome(page, 'touchdown');
  await forceOutcome(page, 'touchdown');
  const bonusState = await state(page);
  check(
    bonusState.tdMeter.value === bonusState.tdMeter.maximum,
    'Successful plays must fill the TD Bonus meter',
  );
  check(bonusState.touchdownStreak === 2, 'Consecutive touchdowns must build the streak');
  await screenshot(page, '06-td-bonus-streak');

  const timerBeforeMute = (await state(page)).remainingMs;
  await page.locator('#mute-button').click();
  check(
    (await page.locator('#mute-button').getAttribute('aria-pressed')) === 'true',
    'Mute control must activate',
  );
  check((await state(page)).remainingMs <= timerBeforeMute, 'Mute must not reset gameplay');

  await advance(page, 120_000);
  await waitForPhase(page, 'results');
  await screenshot(page, '07-results');
  await page.locator('#results-restart-button').click();
  await advance(page, 3_050);
  await waitForPhase(page, 'playing');
  await advance(page, 60_100);
  await waitForPhase(page, 'results');
  check(
    (await state(page)).phase === 'results',
    'A second full run must complete without reloading',
  );

  await page.locator('#results-restart-button').click();
  await advance(page, 3_050);
  await waitForPhase(page, 'playing');
  await advance(page, 59_500);
  await setSimulationSpeed(page, 0.1);
  const finalBallState = await state(page);
  const finalTarget = finalBallState.receivers.find((receiver) => receiver.lane === 'deep');
  if (finalTarget) {
    await mouseThrow(
      page,
      { x: finalTarget.x + finalTarget.direction * 70, y: finalTarget.y },
      { durationMs: 430 },
    );
    check(Boolean((await state(page)).ball), 'A throw released before zero must enter flight');
    await setSimulationSpeed(page, 1);
    await advance(page, 600);
    const resolving = await state(page);
    check(
      resolving.phase === 'resolving-final-ball',
      'Timer zero with a live ball must enter final-ball resolution',
    );
    check(Boolean(resolving.ball), 'The final in-flight ball must not be discarded at zero');
    await advance(page, 2_000);
    await waitForPhase(page, 'results');
  }

  await page.locator('#results-restart-button').click();
  await advance(page, 3_050);
  await waitForPhase(page, 'playing');
  const invalidState = await state(page);
  const invalidStart = await logicalToClient(page, {
    x: invalidState.quarterback.x + invalidState.quarterback.width / 2,
    y: invalidState.quarterback.y + invalidState.quarterback.height * 0.55,
  });
  await page.mouse.move(invalidStart.x, invalidStart.y);
  await page.mouse.down();
  await page.mouse.move(invalidStart.x + 5, invalidStart.y - 12);
  await page.mouse.up();
  check((await state(page)).ball === null, 'A too-short swipe must not release a ball');
  await cancelMouseGesture(page);
  check(
    (await state(page)).canThrow,
    'Pointer cancellation must leave input ready for another throw',
  );
  check(
    !(await state(page)).input.pointerActive,
    'Pointer cancellation must release pointer ownership',
  );
  await desktop.close();
  console.log('[playtest] desktop run checks complete');

  const wide = await browser.newContext({ viewport: { width: 1366, height: 768 } });
  const widePage = await wide.newPage();
  observeConsole(widePage, 'wide');
  await widePage.goto(baseUrl, { waitUntil: 'networkidle' });
  await waitForPhase(widePage, 'title');
  await enterGameplay(widePage);
  await screenshot(widePage, '08-gameplay-wide');
  const wideState = await state(widePage);
  const wideReceiver = wideState.receivers.find((receiver) => receiver.lane === 'short');
  if (wideReceiver) {
    await captureAim(
      widePage,
      { x: wideReceiver.x + wideReceiver.direction * 78, y: wideReceiver.y },
      join(outputDirectory, '04-destination-x.png'),
    );
  }
  check(
    (await widePage.locator('#game-shell').boundingBox())?.width > 1_300,
    'Adaptive widescreen presentation must use the available landscape width',
  );
  const wideCanvasBox = await widePage.locator('#game-canvas').boundingBox();
  check(
    Boolean(wideCanvasBox && wideCanvasBox.width >= 1_015 && wideCanvasBox.width <= 1_030),
    'Widescreen presentation must preserve a centered 4:3 gameplay stage',
  );
  check(
    wideState.coordinateSystem.endsWith('1024x768'),
    'Widescreen presentation must keep the canonical 1024x768 gameplay camera',
  );
  await wide.close();
  console.log('[playtest] wide fixed-stage checks complete');

  const mobile = await browser.newContext({
    viewport: { width: 844, height: 390 },
    deviceScaleFactor: 3,
    hasTouch: true,
    isMobile: true,
  });
  const mobilePage = await mobile.newPage();
  observeConsole(mobilePage, 'mobile');
  await mobilePage.goto(baseUrl, { waitUntil: 'networkidle' });
  await waitForPhase(mobilePage, 'title');
  await enterGameplay(mobilePage);
  const mobileState = await state(mobilePage);
  const mobileReceiver = mobileState.receivers.find((receiver) => receiver.lane === 'short');
  if (mobileReceiver) {
    await touchThrow(mobile, mobilePage, {
      x: mobileReceiver.x + mobileReceiver.direction * 75,
      y: mobileReceiver.y,
    });
    check(Boolean((await state(mobilePage)).ball), 'A touch swipe must release a ball');
  }
  await screenshot(mobilePage, '09-iphone-landscape-touch');
  await mobilePage.setViewportSize({ width: 390, height: 844 });
  await mobilePage.waitForTimeout(50);
  check(
    await mobilePage.locator('#orientation-message').isVisible(),
    'Portrait mode must show a rotate warning',
  );
  await screenshot(mobilePage, '10-portrait-warning');
  await mobile.close();
  console.log('[playtest] mobile touch checks complete');

  const continueContext = await browser.newContext({ viewport: { width: 1024, height: 768 } });
  const continuePage = await continueContext.newPage();
  observeConsole(continuePage, 'continue-viewed');
  await continuePage.goto(new URL('?mockAd=viewed', baseUrl).href, { waitUntil: 'networkidle' });
  await waitForPhase(continuePage, 'title');
  await enterGameplay(continuePage);
  await advance(continuePage, 50_100);
  await continuePage.waitForTimeout(0);
  await advance(continuePage, 10_000);
  await waitForPhase(continuePage, 'continue-offer');
  await screenshot(continuePage, '11-continue-offer');
  await continuePage.locator('#watch-ad-button').click();
  await waitForPhase(continuePage, 'playing');
  const overtime = await state(continuePage);
  check(
    overtime.remainingMs <= 15_000 && overtime.remainingMs >= 14_500,
    `A viewed rewarded ad must resume from a 15-second overtime clock (observed ${overtime.remainingMs}ms)`,
  );
  check(overtime.stats.rewardedContinueUsed, 'A viewed rewarded ad must mark overtime as used');
  await advance(continuePage, 15_100);
  await waitForPhase(continuePage, 'results');
  check(
    (await state(continuePage)).stats.rewardedContinueUsed,
    'Overtime result must preserve the used marker',
  );
  await screenshot(continuePage, '12-overtime-results');
  await continueContext.close();

  const dismissedContext = await browser.newContext({ viewport: { width: 1024, height: 768 } });
  const dismissedPage = await dismissedContext.newPage();
  observeConsole(dismissedPage, 'continue-dismissed');
  await dismissedPage.goto(new URL('?mockAd=dismissed', baseUrl).href, {
    waitUntil: 'networkidle',
  });
  await waitForPhase(dismissedPage, 'title');
  await enterGameplay(dismissedPage);
  await advance(dismissedPage, 50_100);
  await dismissedPage.waitForTimeout(0);
  await advance(dismissedPage, 10_000);
  await waitForPhase(dismissedPage, 'continue-offer');
  await dismissedPage.locator('#watch-ad-button').click();
  await waitForPhase(dismissedPage, 'results');
  check(
    !(await state(dismissedPage)).stats.rewardedContinueUsed,
    'A dismissed ad must not grant overtime',
  );
  await dismissedContext.close();

  const unavailableContext = await browser.newContext({ viewport: { width: 1024, height: 768 } });
  const unavailablePage = await unavailableContext.newPage();
  observeConsole(unavailablePage, 'standalone-unavailable');
  await unavailablePage.goto(baseUrl, { waitUntil: 'networkidle' });
  await waitForPhase(unavailablePage, 'title');
  await enterGameplay(unavailablePage);
  await advance(unavailablePage, 60_100);
  await waitForPhase(unavailablePage, 'results');
  check(
    !(await state(unavailablePage)).stats.rewardedContinueUsed,
    'Standalone mode must finish without an ad',
  );
  await unavailableContext.close();
} finally {
  await browser.close();
}

const report = {
  baseUrl,
  passed: failures.length === 0 && consoleErrors.length === 0,
  failures,
  consoleErrors,
};
await writeFile(join(outputDirectory, 'report.json'), `${JSON.stringify(report, null, 2)}\n`);

if (!report.passed) {
  console.error(JSON.stringify(report, null, 2));
  process.exitCode = 1;
} else {
  console.log(`Playtest passed. Screenshots and report: ${outputDirectory}`);
}

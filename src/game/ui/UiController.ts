import { SCORE_CONFIG } from '../config/scoringConfig';
import {
  RUNTIME_TUNING_GROUPS,
  getRuntimeContinueDurationMs,
  getRuntimeSessionDurationMs,
  getRuntimeTuningValue,
  isRuntimeTuningControlOverridden,
  type RuntimeTuningControl,
} from '../config/runtimeTuning';
import { VISUAL_CONFIG } from '../config/visualConfig';
import { selectAccuracy, selectTdBonusActive, selectTouchdownMultiplier } from '../state/selectors';
import type { GamePhase, GameSettings, GameState } from '../state/GameState';

const getRequired = <T extends Element>(root: ParentNode, selector: string): T => {
  const element = root.querySelector<T>(selector);
  if (!element) throw new Error(`Missing UI element: ${selector}`);
  return element;
};

export interface UiCallbacks {
  onPlay(): void;
  onInstructions(): void;
  onInstructionsBack(): void;
  onInstructionsDone(): void;
  onPause(): void;
  onResume(): void;
  onRestart(): void;
  onFinishRun(): void;
  onWatchAd(): void;
  onSettingsChanged(settings: Partial<GameSettings>): void;
  onToggleMute(): void;
  onDebugAction(action: string, value?: string): void;
}

export class UiController {
  public readonly canvas: HTMLCanvasElement;
  public readonly shell: HTMLDivElement;
  private readonly screens: Map<GamePhase, HTMLElement>;
  private readonly score: HTMLElement;
  private readonly timer: HTMLElement;
  private readonly meterFill: HTMLElement;
  private readonly meterLabel: HTMLElement;
  private readonly multiplier: HTMLElement;
  private readonly feedback: HTMLElement;
  private readonly feedbackHeadline: HTMLElement;
  private readonly feedbackDetail: HTMLElement;
  private readonly countdown: HTMLElement;
  private readonly muteButton: HTMLButtonElement;
  private readonly muteButtonIcon: HTMLImageElement;
  private readonly continueWatchButton: HTMLButtonElement;
  private readonly orientation: HTMLElement;
  private readonly debugPanel: HTMLElement | null;
  private activePhase: GamePhase = 'loading';

  public constructor(root: HTMLElement, callbacks: UiCallbacks) {
    root.innerHTML = this.template();
    this.canvas = getRequired(root, '#game-canvas');
    this.shell = getRequired(root, '#game-shell');
    this.score = getRequired(root, '#hud-score');
    this.timer = getRequired(root, '#hud-timer');
    this.meterFill = getRequired(root, '#meter-fill');
    this.meterLabel = getRequired(root, '#meter-label');
    this.multiplier = getRequired(root, '#hud-multiplier');
    this.feedback = getRequired(root, '#play-feedback');
    this.feedbackHeadline = getRequired(root, '#feedback-headline');
    this.feedbackDetail = getRequired(root, '#feedback-detail');
    this.countdown = getRequired(root, '#countdown-value');
    this.muteButton = getRequired(root, '#mute-button');
    this.muteButtonIcon = getRequired(root, '#mute-button-icon');
    this.continueWatchButton = getRequired(root, '#watch-ad-button');
    this.orientation = getRequired(root, '#orientation-message');
    this.debugPanel = import.meta.env.DEV ? getRequired<HTMLElement>(root, '#debug-panel') : null;
    this.screens = new Map(
      [...root.querySelectorAll<HTMLElement>('[data-screen]')].map((element) => [
        element.dataset.screen as GamePhase,
        element,
      ]),
    );
    this.bind(callbacks);
    if (import.meta.env.DEV) this.syncRuntimeTuningControls();
  }

  public setPhase(phase: GamePhase): void {
    this.activePhase = phase;
    for (const [screenPhase, screen] of this.screens) {
      screen.hidden = screenPhase !== phase;
    }
    const gameplayVisible = phase === 'playing' || phase === 'resolving-final-ball';
    this.shell.dataset.phase = phase;
    getRequired<HTMLElement>(this.shell, '#game-hud').hidden = !gameplayVisible;
    if (phase === 'countdown') this.countdown.textContent = '3';
  }

  public render(state: GameState): void {
    if (this.activePhase !== state.phase) this.setPhase(state.phase);
    this.score.textContent = state.score.toLocaleString('en-US');
    this.timer.textContent = Math.ceil(state.remainingMs / 1_000).toString();
    this.timer.classList.toggle('is-warning', state.remainingMs <= 10_000);
    const meterPercent = Math.min(100, (state.tdMeter / SCORE_CONFIG.tdMeterMaximum) * 100);
    this.meterFill.style.width = `${meterPercent}%`;
    this.meterFill.parentElement?.setAttribute(
      'aria-valuemax',
      String(SCORE_CONFIG.tdMeterMaximum),
    );
    this.meterFill.parentElement?.setAttribute('aria-valuenow', String(state.tdMeter));
    const bonusActive = selectTdBonusActive(state);
    this.meterFill.parentElement?.classList.toggle('is-active', bonusActive);
    this.meterLabel.textContent = bonusActive
      ? 'TD BONUS ACTIVE'
      : `TD BONUS ${state.tdMeter}/${SCORE_CONFIG.tdMeterMaximum}`;
    const multiplier = selectTouchdownMultiplier(state);
    this.multiplier.textContent = state.touchdownStreak > 0 ? `TD x${multiplier}` : 'TD x1';
    this.muteButton.setAttribute('aria-pressed', String(state.settings.masterMuted));
    this.muteButton.title = state.settings.masterMuted ? 'Unmute audio' : 'Mute audio';
    this.muteButton.classList.toggle('is-muted', state.settings.masterMuted);
    this.muteButtonIcon.src = state.settings.masterMuted
      ? '/assets/art/icon-mute.svg'
      : '/assets/art/icon-unmute.svg';

    if (state.feedback) {
      this.feedback.hidden = false;
      this.feedback.dataset.tone = state.feedback.tone;
      this.feedbackHeadline.textContent = state.feedback.headline;
      this.feedbackDetail.textContent = state.feedback.detail;
    } else {
      this.feedback.hidden = true;
    }

    if (state.phase === 'countdown') {
      this.countdown.textContent = Math.max(
        1,
        Math.ceil(state.countdownRemainingMs / 1_000),
      ).toString();
    }
    if (state.phase === 'results') this.renderResults(state);
  }

  public setLoadingProgress(percent: number, label: string): void {
    getRequired<HTMLElement>(this.shell, '#loading-bar-fill').style.width =
      `${Math.max(0, Math.min(100, percent))}%`;
    getRequired<HTMLElement>(this.shell, '#loading-label').textContent = label;
  }

  public setPlayerGreeting(name: string | null, avatarUrl: string | null): void {
    const greeting = getRequired<HTMLElement>(this.shell, '#player-greeting');
    greeting.textContent = name ? `Ready, ${name}?` : 'Read it. Lead it. Rip it.';
    const avatar = getRequired<HTMLImageElement>(this.shell, '#player-avatar');
    if (avatarUrl) {
      avatar.src = avatarUrl;
      avatar.hidden = false;
    } else {
      avatar.hidden = true;
    }
  }

  public setContinueReady(ready: boolean): void {
    this.continueWatchButton.disabled = !ready;
    this.continueWatchButton.hidden = !ready;
    if (ready) {
      this.continueWatchButton.textContent = `Watch ad for +${getRuntimeContinueDurationMs() / 1_000} seconds`;
    }
    getRequired<HTMLElement>(this.shell, '#continue-unavailable').hidden = ready;
  }

  public setContinuePending(pending: boolean): void {
    this.continueWatchButton.disabled = pending;
    this.continueWatchButton.textContent = pending
      ? 'Opening…'
      : `Watch ad for +${getRuntimeContinueDurationMs() / 1_000} seconds`;
  }

  public setPersonalBest(score: number): void {
    getRequired<HTMLElement>(this.shell, '#result-best').textContent =
      score.toLocaleString('en-US');
  }

  public setOrientationWarning(visible: boolean): void {
    this.orientation.hidden = !visible;
  }

  public setAspectRatio(ratio: number): void {
    this.shell.style.setProperty('--game-aspect', ratio.toString());
  }

  public syncSettings(settings: GameSettings): void {
    this.muteButton.setAttribute('aria-pressed', String(settings.masterMuted));
    this.muteButton.title = settings.masterMuted ? 'Unmute audio' : 'Mute audio';
    this.muteButton.classList.toggle('is-muted', settings.masterMuted);
    this.muteButtonIcon.src = settings.masterMuted
      ? '/assets/art/icon-mute.svg'
      : '/assets/art/icon-unmute.svg';
    getRequired<HTMLInputElement>(this.shell, '#music-volume').value = String(settings.musicVolume);
    getRequired<HTMLInputElement>(this.shell, '#sfx-volume').value = String(settings.sfxVolume);
    getRequired<HTMLInputElement>(this.shell, '#reduced-motion').checked = settings.reducedMotion;
    getRequired<HTMLInputElement>(this.shell, '#high-contrast-aim').checked =
      settings.highContrastAim;
    getRequired<HTMLSelectElement>(this.shell, '#view-mode').value = settings.viewMode;
  }

  public syncRuntimeTuningControls(): void {
    if (!import.meta.env.DEV || !this.debugPanel) return;
    let modifiedCount = 0;
    for (const input of this.shell.querySelectorAll<HTMLInputElement>('[data-runtime-tuning]')) {
      const id = input.dataset.runtimeTuning ?? '';
      const value = getRuntimeTuningValue(id);
      if (value !== null) input.value = String(value);
      const overridden = isRuntimeTuningControlOverridden(id);
      input.closest('label')?.classList.toggle('is-overridden', overridden);
      if (overridden) modifiedCount += 1;
    }
    getRequired<HTMLElement>(this.shell, '#debug-modified-count').textContent =
      modifiedCount > 0 ? `${modifiedCount} modified` : 'Defaults active';

    const sessionSeconds = getRuntimeSessionDurationMs() / 1_000;
    const continueSeconds = getRuntimeContinueDurationMs() / 1_000;
    getRequired<HTMLButtonElement>(this.shell, '#play-button').textContent =
      `PLAY ${sessionSeconds}`;
    getRequired<HTMLElement>(this.shell, '#continue-copy').textContent =
      `One rewarded break adds ${continueSeconds} seconds to this score.`;
    if (this.continueWatchButton.textContent !== 'Opening…') {
      this.continueWatchButton.textContent = `Watch ad for +${continueSeconds} seconds`;
    }
  }

  private renderResults(state: GameState): void {
    getRequired<HTMLElement>(this.shell, '#result-score').textContent =
      state.score.toLocaleString('en-US');
    getRequired<HTMLElement>(this.shell, '#result-touchdowns').textContent = String(
      state.stats.touchdowns,
    );
    getRequired<HTMLElement>(this.shell, '#result-streak').textContent = String(
      state.stats.longestTouchdownStreak,
    );
    getRequired<HTMLElement>(this.shell, '#result-completions').textContent = String(
      state.stats.completions + state.stats.touchdowns,
    );
    getRequired<HTMLElement>(this.shell, '#result-incompletions').textContent = String(
      state.stats.incompletions,
    );
    getRequired<HTMLElement>(this.shell, '#result-interceptions').textContent = String(
      state.stats.interceptions,
    );
    getRequired<HTMLElement>(this.shell, '#result-accuracy').textContent =
      `${selectAccuracy(state)}%`;
    getRequired<HTMLElement>(this.shell, '#result-overtime').textContent = state.stats
      .rewardedContinueUsed
      ? 'Used'
      : 'No';
  }

  private bind(callbacks: UiCallbacks): void {
    const click = (selector: string, handler: () => void): void => {
      getRequired<HTMLButtonElement>(this.shell, selector).addEventListener('click', handler);
    };
    click('#play-button', callbacks.onPlay);
    click('#how-button', callbacks.onInstructions);
    click('#instructions-play-button', callbacks.onInstructionsDone);
    click('#instructions-back-button', callbacks.onInstructionsBack);
    click('#pause-button', callbacks.onPause);
    click('#resume-button', callbacks.onResume);
    click('#restart-button', callbacks.onRestart);
    click('#results-restart-button', callbacks.onRestart);
    click('#finish-run-button', callbacks.onFinishRun);
    click('#watch-ad-button', callbacks.onWatchAd);
    click('#mute-button', callbacks.onToggleMute);
    if (import.meta.env.DEV && this.debugPanel) {
      click('#debug-toggle', () => {
        if (this.debugPanel) this.debugPanel.hidden = !this.debugPanel.hidden;
      });
    }

    getRequired<HTMLInputElement>(this.shell, '#music-volume').addEventListener(
      'input',
      (event) => {
        callbacks.onSettingsChanged({
          musicVolume: Number((event.target as HTMLInputElement).value),
        });
      },
    );
    getRequired<HTMLInputElement>(this.shell, '#sfx-volume').addEventListener('input', (event) => {
      callbacks.onSettingsChanged({ sfxVolume: Number((event.target as HTMLInputElement).value) });
    });
    getRequired<HTMLInputElement>(this.shell, '#reduced-motion').addEventListener(
      'change',
      (event) => {
        callbacks.onSettingsChanged({ reducedMotion: (event.target as HTMLInputElement).checked });
      },
    );
    getRequired<HTMLInputElement>(this.shell, '#high-contrast-aim').addEventListener(
      'change',
      (event) => {
        callbacks.onSettingsChanged({
          highContrastAim: (event.target as HTMLInputElement).checked,
        });
      },
    );
    getRequired<HTMLSelectElement>(this.shell, '#view-mode').addEventListener('change', (event) => {
      const value = (event.target as HTMLSelectElement).value;
      if (value === 'auto' || value === 'classic' || value === 'wide') {
        callbacks.onSettingsChanged({ viewMode: value });
      }
    });

    if (import.meta.env.DEV) {
      for (const button of this.shell.querySelectorAll<HTMLButtonElement>('[data-debug-action]')) {
        button.addEventListener('click', () =>
          callbacks.onDebugAction(button.dataset.debugAction ?? ''),
        );
      }
      for (const input of this.shell.querySelectorAll<HTMLInputElement>('[data-debug-control]')) {
        input.addEventListener('change', () =>
          callbacks.onDebugAction(
            input.dataset.debugControl ?? '',
            input.type === 'checkbox' ? String(input.checked) : input.value,
          ),
        );
      }
      for (const input of this.shell.querySelectorAll<HTMLInputElement>('[data-runtime-tuning]')) {
        input.addEventListener('change', () => {
          callbacks.onDebugAction(input.dataset.runtimeTuning ?? '', input.value);
        });
      }
    }
  }

  private tuningControlTemplate(control: RuntimeTuningControl): string {
    const value = getRuntimeTuningValue(control.id) ?? control.min;
    return `<label class="debug-number-row">
      <span>${control.label}</span>
      <span class="debug-number-input">
        <input type="number" min="${control.min}" max="${control.max}" step="${control.step}" value="${value}" data-runtime-tuning="${control.id}" aria-label="${control.label}" />
        <small>${control.unit}</small>
      </span>
    </label>`;
  }

  private tuningGroupsTemplate(): string {
    return RUNTIME_TUNING_GROUPS.map(
      (group, index) => `<details class="debug-group" ${index === 0 ? 'open' : ''}>
        <summary>${group.label}</summary>
        <div class="debug-control-list">${group.controls.map((entry) => this.tuningControlTemplate(entry)).join('')}</div>
      </details>`,
    ).join('');
  }

  private developmentToolsTemplate(): string {
    if (!import.meta.env.DEV) return '';
    return `<button class="debug-toggle" id="debug-toggle" aria-label="Open tuning panel">TUNE</button>
      <aside class="debug-panel" id="debug-panel" hidden>
        <header><strong>Development tuning</strong><span id="debug-modified-count">Defaults active</span></header>
        ${this.tuningGroupsTemplate()}
        <details class="debug-group" open>
          <summary>Debug & outcomes</summary>
          <div class="debug-control-list debug-checks">
            <label><span>Trajectory</span><input type="checkbox" data-debug-control="trajectory" /></label>
            <label><span>Catch zones</span><input type="checkbox" data-debug-control="catch-zones" /></label>
            <label><span>Defender zones</span><input type="checkbox" data-debug-control="defender-zones" /></label>
            <label><span>Simulation speed</span><input type="range" min="0.1" max="1" step="0.1" value="1" data-debug-control="slow-motion" /></label>
            <label><span>Random seed</span><input type="number" min="1" step="1" value="5293287" data-debug-control="seed" /></label>
          </div>
          <div class="debug-button-row"><button data-debug-action="freeze">Freeze frame</button><button data-debug-action="reset-run">Reset run</button></div>
          <div class="debug-button-row"><button data-debug-action="complete">Complete</button><button data-debug-action="touchdown">TD</button><button data-debug-action="incomplete">Miss</button><button data-debug-action="interception">INT</button></div>
        </details>
        <button class="debug-reset-defaults" data-debug-action="reset-defaults">Reset all tuning to defaults</button>
      </aside>`;
  }

  private template(): string {
    return `
      <main class="app-frame" aria-label="${VISUAL_CONFIG.title}">
        <div class="game-shell" id="game-shell" data-phase="loading">
          <div class="game-stage" id="game-stage">
          <canvas id="game-canvas" aria-label="Football passing playfield" tabindex="-1"></canvas>

          <div class="game-hud" id="game-hud" hidden>
            <div class="hud-score-cluster">
              <span class="hud-kicker">POINTS</span>
              <strong id="hud-score">0</strong>
            </div>
            <div class="hud-center-window" aria-hidden="true"><span>NOVA DOME</span></div>
            <div class="hud-right-rack">
              <div class="hud-bonus-cluster">
                <div class="meter-copy" id="meter-label">TD BONUS 0/${SCORE_CONFIG.tdMeterMaximum}</div>
                <div class="meter-track" role="meter" aria-label="Touchdown bonus meter" aria-valuemin="0" aria-valuemax="${SCORE_CONFIG.tdMeterMaximum}">
                  <div class="meter-fill" id="meter-fill"></div>
                </div>
                <div class="hud-multiplier" id="hud-multiplier">TD x1</div>
              </div>
              <div class="hud-time-cluster">
                <span class="hud-kicker">TIME</span>
                <strong id="hud-timer">60</strong>
                <button class="icon-button" id="mute-button" aria-label="Toggle audio" aria-pressed="false"><img id="mute-button-icon" src="/assets/art/icon-unmute.svg" alt="" aria-hidden="true" /></button>
                <button class="icon-button" id="pause-button" aria-label="Pause game"><img src="/assets/art/icon-pause.svg" alt="" aria-hidden="true" /></button>
              </div>
            </div>
          </div>

          <div class="play-feedback" id="play-feedback" hidden aria-live="polite">
            <strong id="feedback-headline"></strong>
            <span id="feedback-detail"></span>
          </div>

          <section class="screen loading-screen" data-screen="loading" aria-label="Loading">
            <div class="loading-mark">PV</div>
            <p id="loading-label">Drawing the field…</p>
            <div class="loading-bar"><div id="loading-bar-fill"></div></div>
          </section>

          <section class="screen title-screen" data-screen="title" hidden>
            <div class="title-copy">
              <img class="game-logo" src="/assets/pixel/logo.png" alt="Pocket Vector" />
              <p id="player-greeting">Read it. Lead it. Rip it.</p>
              <img id="player-avatar" class="player-avatar" alt="Player avatar" hidden />
              <div class="title-actions">
                <button class="arcade-button primary" id="play-button">PLAY ${getRuntimeSessionDurationMs() / 1_000}</button>
                <button class="arcade-button secondary" id="how-button">HOW TO THROW</button>
              </div>
            </div>
            <div class="title-tag">NOVA CITY COMETS <span>VS</span> IRON BAY PHANTOMS</div>
          </section>

          <section class="screen instructions-screen" data-screen="instructions" hidden>
            <div class="panel instructions-panel">
              <p class="eyebrow">THE READ</p>
              <h1>Lead the lane.</h1>
              <div class="gesture-demo" aria-hidden="true"><span class="demo-qb">QB</span><span class="demo-line"></span><span class="demo-x">×</span></div>
              <ol>
                <li><strong>Press the quarterback.</strong> Drag toward open grass.</li>
                <li><strong>Release ahead of a runner.</strong> They keep moving in flight.</li>
                <li><strong>Rip fast for a bullet.</strong> Ease up for a higher lob.</li>
              </ol>
              <div class="rule-chips">
                <span>Deep = more points</span><span>Completions fill TD Bonus</span><span>Misses wipe the meter</span><span>Back-to-back TDs multiply</span>
              </div>
              <div class="panel-actions">
                <button class="arcade-button secondary" id="instructions-back-button">BACK</button>
                <button class="arcade-button primary" id="instructions-play-button">START RUN</button>
              </div>
            </div>
          </section>

          <section class="screen countdown-screen" data-screen="countdown" hidden aria-live="assertive">
            <span>LOCK IN</span><strong id="countdown-value">3</strong>
          </section>

          <section class="screen pause-screen" data-screen="paused" hidden>
            <div class="panel settings-panel">
              <p class="eyebrow">HUDDLE</p><h1>Paused</h1>
              <label>Music <input id="music-volume" type="range" min="0" max="1" step="0.05" /></label>
              <label>SFX <input id="sfx-volume" type="range" min="0" max="1" step="0.05" /></label>
              <label class="toggle-row"><input id="reduced-motion" type="checkbox" /> Reduced motion</label>
              <label class="toggle-row"><input id="high-contrast-aim" type="checkbox" /> High-contrast aim X</label>
              <label>Cabinet fit <select id="view-mode"><option value="auto">Auto side rails</option><option value="classic">Exact 4:3</option><option value="wide">Wide side rails</option></select></label>
              <div class="panel-actions"><button class="arcade-button secondary" id="restart-button">RESTART</button><button class="arcade-button primary" id="resume-button">RESUME</button></div>
            </div>
          </section>

          <section class="screen continue-screen" data-screen="continue-offer" hidden>
            <div class="panel continue-panel">
              <p class="eyebrow">OVERTIME WINDOW</p><h1>Keep the drive alive?</h1>
              <p id="continue-copy">One rewarded break adds ${getRuntimeContinueDurationMs() / 1_000} seconds to this score.</p>
              <p id="continue-unavailable">No overtime break is available in standalone play.</p>
              <div class="panel-actions"><button class="arcade-button secondary" id="finish-run-button">FINISH RUN</button><button class="arcade-button primary" id="watch-ad-button" hidden disabled>Watch ad for +15 seconds</button></div>
            </div>
          </section>

          <section class="screen ad-screen" data-screen="rewarded-ad" hidden>
            <div class="panel"><p class="eyebrow">TIMEOUT</p><h1>Rewarded break</h1><p>Gameplay and audio are paused.</p></div>
          </section>

          <section class="screen results-screen" data-screen="results" hidden>
            <div class="panel results-panel">
              <p class="eyebrow">FINAL WHISTLE</p><h1 id="result-score">0</h1><span class="score-label">FINAL SCORE</span>
              <div class="result-grid">
                <span>Touchdowns<strong id="result-touchdowns">0</strong></span>
                <span>Longest TD streak<strong id="result-streak">0</strong></span>
                <span>Completions<strong id="result-completions">0</strong></span>
                <span>Incompletions<strong id="result-incompletions">0</strong></span>
                <span>Interceptions<strong id="result-interceptions">0</strong></span>
                <span>Accuracy<strong id="result-accuracy">0%</strong></span>
                <span>Overtime<strong id="result-overtime">No</strong></span>
                <span>Personal best<strong id="result-best">0</strong></span>
              </div>
              <button class="arcade-button primary" id="results-restart-button">RUN IT BACK</button>
            </div>
          </section>

          <aside class="orientation-message" id="orientation-message" hidden>
            <strong>Rotate to landscape</strong><span>The arcade camera stays 4:3 for an accurate passing view.</span>
          </aside>
          </div>

          ${this.developmentToolsTemplate()}
        </div>
      </main>`;
  }
}

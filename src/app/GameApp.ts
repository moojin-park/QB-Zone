import { loadArtAssets } from '../game/assets/loadAssets';
import { AudioManager } from '../game/audio/AudioManager';
import {
  FINAL_BALL_GRACE_MS,
  FIXED_STEP_MS,
  GAMEPLAY_CONFIG,
  MAX_FRAME_DELTA_MS,
  MAX_REWARDED_CONTINUES_PER_RUN,
  PASSING_LANES,
  getDefenderPatrolSpeedPerMs,
  getLaneConfig,
} from '../game/config/gameplayConfig';
import {
  getRuntimeContinueDurationMs,
  getRuntimeSessionDurationMs,
  isRuntimeTuningControlOverridden,
  resetRuntimeTuningToDefaults,
  setRuntimeTuningValue,
} from '../game/config/runtimeTuning';
import { SCORE_CONFIG } from '../game/config/scoringConfig';
import { PointerSampler } from '../game/input/PointerSampler';
import {
  calculateThrowGesture,
  isValidThrowGesture,
  type PointerSample,
} from '../game/input/gestureMath';
import {
  CONTINUE_AD_PLACEMENT,
  CONTINUE_AD_REWARD,
  FakePlatform,
  createArcadePlatform,
  createDefaultPersistedGameData,
  createReadyContinueAd,
  isContinueAdReady,
  isContinueRewardGranted,
  type ArcadePlatform,
  type PersistedGameData,
  type PreparedContinueAd,
} from '../game/platform';
import {
  CanvasRenderer,
  getReceiverVisualSelection,
  type AimPreview,
} from '../game/rendering/CanvasRenderer';
import {
  getQuarterbackRect,
  isPointOnQuarterback,
  screenToFieldWorld,
  worldToScreen,
} from '../game/rendering/projection';
import { createInitialState } from '../game/state/createInitialState';
import { selectCanThrow } from '../game/state/selectors';
import type {
  FeedbackState,
  GameSettings,
  GameState,
  PassOutcome,
  ScreenPoint,
} from '../game/state/GameState';
import { createBallState } from '../game/simulation/trajectory';
import { updateGame, type UpdateResult } from '../game/simulation/updateGame';
import { UiController, type UiCallbacks } from '../game/ui/UiController';

const createGamePlatform = (
  options: Parameters<typeof createArcadePlatform>[0],
): ArcadePlatform => {
  if (import.meta.env.DEV) {
    const mockStatus = new URLSearchParams(window.location.search).get('mockAd');
    if (mockStatus === 'viewed' || mockStatus === 'dismissed' || mockStatus === 'error') {
      return new FakePlatform({
        preparedContinueAd: createReadyContinueAd({
          status: mockStatus,
          placement: CONTINUE_AD_PLACEMENT,
          reward: CONTINUE_AD_REWARD,
          adBreakId: 'browser-playtest-ad',
          ...(mockStatus === 'error' ? { error: 'browser_playtest_error' } : {}),
        }),
      });
    }
    if (mockStatus === 'unavailable') return new FakePlatform();
  }
  return createArcadePlatform(options);
};

export class GameApp {
  private state: GameState;
  private readonly ui: UiController;
  private readonly renderer: CanvasRenderer;
  private readonly audio: AudioManager;
  private readonly platform: ArcadePlatform;
  private readonly pointerSampler = new PointerSampler();
  private persistedData: PersistedGameData = createDefaultPersistedGameData();
  private preparedContinueAd: PreparedContinueAd | null = null;
  private aimPreview: AimPreview | null = null;
  private runPrepared = false;
  private finalRunSubmitted = false;
  private hostBlocked = false;
  private animationFrame = 0;
  private lastFrameTimestamp = 0;
  private accumulatorMs = 0;
  private lastCountdownValue = 3;

  public constructor(private readonly root: HTMLElement) {
    this.state = createInitialState();
    this.ui = new UiController(root, this.createUiCallbacks());
    this.renderer = new CanvasRenderer(this.ui.canvas);
    this.audio = new AudioManager(this.state.settings);
    this.platform = createGamePlatform({
      onHostBlocked: () => this.handleHostBlocked(),
      onRewardedAdStart: () => {
        void this.audio.pause();
      },
      onSdkError: (operation, error) => {
        if (import.meta.env.DEV) console.warn(`Bounty Board ${operation} failed safely.`, error);
      },
    });
  }

  public async boot(): Promise<void> {
    if (import.meta.env.DEV) document.body.dataset.development = 'true';
    this.installEventHandlers();
    this.resize();
    this.ui.setPhase('loading');
    this.ui.setLoadingProgress(12, 'Marking the lanes…');
    this.renderer.render(this.state, null);

    void this.platform.initialize();
    void this.loadPersistentData();
    void this.loadPlayerIdentity();

    const [art, audioFailures] = await Promise.all([loadArtAssets(), this.audio.prepare()]);
    this.renderer.setAssets(art.images);
    const failureCount = art.failures.length + audioFailures.length;
    this.ui.setLoadingProgress(
      100,
      failureCount > 0 ? 'Ready — some audio may be unavailable' : 'Pocket ready',
    );
    this.state.phase = this.hostBlocked ? 'loading' : 'title';
    this.ui.setPhase(this.state.phase);
    this.platform.loadingFinished();
    if (import.meta.env.DEV) this.installTestHooks();
    this.animationFrame = requestAnimationFrame((timestamp) => this.frame(timestamp));
  }

  public destroy(): void {
    cancelAnimationFrame(this.animationFrame);
    this.audio.destroy();
    this.root.replaceChildren();
  }

  private createUiCallbacks(): UiCallbacks {
    return {
      onPlay: () => this.handlePlay(),
      onInstructions: () => this.showInstructions(),
      onInstructionsBack: () => this.returnToTitle(),
      onInstructionsDone: () => this.completeInstructions(),
      onPause: () => this.pause(),
      onResume: () => this.resume(),
      onRestart: () => this.restart(),
      onFinishRun: () => this.finishRun(),
      onWatchAd: () => this.watchContinueAd(),
      onSettingsChanged: (settings) => this.updateSettings(settings),
      onToggleMute: () => this.updateSettings({ masterMuted: !this.state.settings.masterMuted }),
      onDebugAction: (action, value) => this.handleDebugAction(action, value),
    };
  }

  private installEventHandlers(): void {
    window.addEventListener('resize', () => this.resize());
    window.addEventListener('orientationchange', () => this.resize());
    document.addEventListener('visibilitychange', () => {
      if (document.hidden && this.state.phase === 'playing') this.pause();
    });
    document.addEventListener('keydown', (event) => {
      if (event.key === 'Escape') {
        if (this.state.phase === 'paused') this.resume();
        else if (this.state.phase === 'playing') this.pause();
      }
      if (event.key.toLowerCase() === 'f' && !event.metaKey && !event.ctrlKey) {
        void this.toggleFullscreen();
      }
    });
    const canvas = this.ui.canvas;
    canvas.addEventListener('pointerdown', (event) => this.onPointerDown(event));
    // Window-level release listeners cover trackpads that lose canvas capture
    // immediately before emitting their final zero-button pointer event.
    window.addEventListener('pointermove', (event) => this.onPointerMove(event));
    window.addEventListener('pointerup', (event) => this.onPointerUp(event));
    window.addEventListener('pointercancel', (event) => this.onPointerCancel(event));
    canvas.addEventListener('lostpointercapture', (event) => this.onPointerCaptureLost(event));
    canvas.addEventListener('contextmenu', (event) => event.preventDefault());
  }

  private async loadPersistentData(): Promise<void> {
    const loaded = await this.platform.loadPersistentData();
    if (!loaded) return;
    this.persistedData = loaded;
    this.state.settings = {
      ...this.state.settings,
      masterMuted: loaded.settings.muted,
      musicVolume: loaded.settings.musicVolume,
      sfxVolume: loaded.settings.sfxVolume,
      reducedMotion: loaded.settings.reducedMotion,
      tutorialComplete: loaded.tutorialCompleted,
    };
    this.audio.applySettings(this.state.settings);
    this.ui.syncSettings(this.state.settings);
    this.ui.setPersonalBest(loaded.personalBest);
    this.resize();
  }

  private async loadPlayerIdentity(): Promise<void> {
    const player = await this.platform.getPlayer();
    this.ui.setPlayerGreeting(player?.name ?? null, player?.avatarUrl ?? null);
  }

  private handlePlay(): void {
    void this.audio.unlock().then(() => this.audio.play('uiSelect'));
    this.prepareNewRun();
    if (this.state.settings.tutorialComplete) this.beginCountdown();
    else this.state.phase = 'instructions';
    this.ui.setPhase(this.state.phase);
  }

  private showInstructions(): void {
    this.runPrepared = false;
    this.state.phase = 'instructions';
    this.ui.setPhase('instructions');
    this.audio.play('uiSelect');
  }

  private returnToTitle(): void {
    this.runPrepared = false;
    this.state.phase = 'title';
    this.ui.setPhase('title');
  }

  private completeInstructions(): void {
    const settings = { ...this.state.settings, tutorialComplete: true };
    if (!this.runPrepared) this.prepareNewRun(settings);
    else this.state.settings = settings;
    this.persistedData.tutorialCompleted = true;
    void this.savePersistentData();
    void this.audio.unlock().then(() => this.audio.play('uiSelect'));
    this.beginCountdown();
  }

  private prepareNewRun(settings: GameSettings = this.state.settings): void {
    const debug = this.state.debug;
    const seed = this.state.randomState || GAMEPLAY_CONFIG.defaultSeed;
    this.state = createInitialState({ ...settings }, seed);
    this.state.debug = {
      ...debug,
      frozen: false,
      forcedOutcome: null,
      lastCollisionPoint: null,
      lastCollisionKind: null,
    };
    this.state.remainingMs = getRuntimeSessionDurationMs();
    this.state.finalBallGraceRemainingMs = FINAL_BALL_GRACE_MS;
    this.preparedContinueAd = null;
    this.finalRunSubmitted = false;
    this.lastCountdownValue = 3;
    this.runPrepared = true;
    this.ui.syncSettings(this.state.settings);
    this.ui.setContinuePending(false);
    this.ui.setContinueReady(false);
  }

  private beginCountdown(): void {
    this.state.phase = 'countdown';
    this.state.countdownRemainingMs = 3_000;
    this.ui.setPhase('countdown');
    this.audio.play('countdown');
  }

  private restart(): void {
    if (this.state.phase === 'playing') this.platform.gameplayStop();
    this.prepareNewRun();
    void this.audio.unlock();
    this.beginCountdown();
  }

  private pause(): void {
    if (this.state.phase !== 'playing' && this.state.phase !== 'resolving-final-ball') return;
    this.state.phaseBeforePause = this.state.phase;
    this.state.phase = 'paused';
    this.platform.gameplayStop();
    void this.audio.pause();
    this.ui.setPhase('paused');
  }

  private resume(): void {
    if (this.state.phase !== 'paused') return;
    const resumePhase = this.state.phaseBeforePause ?? 'playing';
    this.state.phase = resumePhase;
    this.state.phaseBeforePause = null;
    if (resumePhase === 'playing') this.platform.gameplayStart();
    void this.audio.resume();
    this.ui.setPhase(resumePhase);
  }

  private frame(timestamp: number): void {
    if (this.lastFrameTimestamp === 0) this.lastFrameTimestamp = timestamp;
    const elapsed = Math.min(MAX_FRAME_DELTA_MS, timestamp - this.lastFrameTimestamp);
    this.lastFrameTimestamp = timestamp;
    this.accumulatorMs += elapsed;
    while (this.accumulatorMs >= FIXED_STEP_MS) {
      this.advanceSimulation(FIXED_STEP_MS);
      this.accumulatorMs -= FIXED_STEP_MS;
    }
    this.renderer.render(this.state, this.aimPreview);
    this.ui.render(this.state);
    this.animationFrame = requestAnimationFrame((nextTimestamp) => this.frame(nextTimestamp));
  }

  private advanceSimulation(deltaMs: number): void {
    this.synchronizeTunedEntities();
    const phaseBefore = this.state.phase;
    const result = updateGame(this.state, deltaMs);
    this.synchronizeTunedEntities();

    if (phaseBefore === 'countdown') {
      const countdownValue = Math.max(1, Math.ceil(this.state.countdownRemainingMs / 1_000));
      if (countdownValue !== this.lastCountdownValue) {
        this.lastCountdownValue = countdownValue;
        this.audio.play('countdown');
      }
      if (this.state.countdownRemainingMs <= 0) {
        this.state.phase = 'playing';
        this.platform.gameplayStart();
        this.audio.startMusic();
        this.audio.play('snap');
      }
      return;
    }

    if (
      this.state.phase === 'playing' &&
      !this.state.adPreparationStarted &&
      this.state.remainingMs <= GAMEPLAY_CONFIG.adPrepareAtRemainingMs &&
      this.state.continueUses < MAX_REWARDED_CONTINUES_PER_RUN
    ) {
      this.state.adPreparationStarted = true;
      void this.platform.prepareContinueAd().then((prepared) => {
        this.preparedContinueAd = prepared;
      });
    }

    if (result.timerExpired) {
      this.platform.gameplayStop();
      this.audio.play('timerWarning');
    }
    if (result.passResolved) this.reactToPass(result);
    if (result.runReadyToFinish) this.offerContinueOrFinish();
  }

  private reactToPass(result: UpdateResult): void {
    if (result.scoreChanged) this.platform.submitScore(this.state.score);
    const score = this.state.lastPlayScore;
    switch (result.passResolved) {
      case 'completion':
        this.audio.play(result.laneId === 'deep' ? 'deep' : 'catch');
        break;
      case 'touchdown':
        this.audio.play('touchdown');
        if ((score?.touchdownMultiplier ?? 1) > 1) this.audio.play('multiplier');
        break;
      case 'interception':
        this.audio.play('interception');
        this.audio.play('meterLoss');
        break;
      case 'incompletion':
        this.audio.play('incomplete');
        this.audio.play('meterLoss');
        break;
      default:
        break;
    }
    if (
      score &&
      score.tdMeterBefore < SCORE_CONFIG.tdMeterMaximum &&
      score.tdMeterAfter >= SCORE_CONFIG.tdMeterMaximum
    ) {
      this.audio.play('bonus');
    }
  }

  private offerContinueOrFinish(): void {
    if (
      this.state.continueUses < MAX_REWARDED_CONTINUES_PER_RUN &&
      this.preparedContinueAd &&
      isContinueAdReady(this.preparedContinueAd)
    ) {
      this.state.phase = 'continue-offer';
      this.ui.setContinueReady(true);
      this.ui.setPhase('continue-offer');
      return;
    }
    this.finishRun();
  }

  private watchContinueAd(): void {
    if (!this.preparedContinueAd || !isContinueAdReady(this.preparedContinueAd)) return;
    const resultPromise = this.preparedContinueAd.show();
    this.state.phase = 'rewarded-ad';
    this.ui.setContinuePending(true);
    this.ui.setPhase('rewarded-ad');
    void resultPromise.then((result) => {
      this.ui.setContinuePending(false);
      if (isContinueRewardGranted(result)) {
        this.state.remainingMs = getRuntimeContinueDurationMs();
        this.state.continueUses += 1;
        this.state.stats.rewardedContinueUsed = true;
        this.state.phase = 'playing';
        this.state.playCooldownMs = 280;
        this.platform.gameplayStart();
        void this.audio.resume();
        this.audio.play('continueSuccess');
        this.ui.setPhase('playing');
      } else {
        void this.audio.resume();
        this.finishRun();
      }
    });
  }

  private finishRun(): void {
    if (this.finalRunSubmitted) return;
    this.finalRunSubmitted = true;
    this.platform.gameplayStop();
    this.platform.gameOver(this.state.score);
    this.audio.stopMusic();
    this.audio.play('gameOver');
    this.state.phase = 'results';
    this.persistedData.personalBest = Math.max(this.persistedData.personalBest, this.state.score);
    this.persistedData.aggregateStats.runsCompleted += 1;
    this.persistedData.aggregateStats.passesAttempted += this.state.stats.attempts;
    this.persistedData.aggregateStats.passesCompleted +=
      this.state.stats.completions + this.state.stats.touchdowns;
    this.persistedData.aggregateStats.touchdowns += this.state.stats.touchdowns;
    this.persistedData.aggregateStats.interceptions += this.state.stats.interceptions;
    this.persistedData.aggregateStats.totalScore += this.state.score;
    this.ui.setPersonalBest(this.persistedData.personalBest);
    this.ui.setPhase('results');
    void this.savePersistentData();
  }

  private updateSettings(patch: Partial<GameSettings>): void {
    this.state.settings = { ...this.state.settings, ...patch };
    this.audio.applySettings(this.state.settings);
    this.ui.syncSettings(this.state.settings);
    document.body.dataset.reducedMotion = String(this.state.settings.reducedMotion);
    this.resize();
    void this.savePersistentData();
  }

  private async savePersistentData(): Promise<void> {
    this.persistedData.settings = {
      muted: this.state.settings.masterMuted,
      musicVolume: this.state.settings.musicVolume,
      sfxVolume: this.state.settings.sfxVolume,
      reducedMotion: this.state.settings.reducedMotion,
    };
    this.persistedData.tutorialCompleted = this.state.settings.tutorialComplete;
    await this.platform.savePersistentData(this.persistedData);
  }

  private onPointerDown(event: PointerEvent): void {
    if (!selectCanThrow(this.state)) return;
    const point = this.pointerToLogical(event);
    if (!isPointOnQuarterback(point, this.renderer.getProjection())) return;
    const sample = this.pointerSample(event, point);
    if (!this.pointerSampler.start(event.pointerId, sample)) return;
    this.ui.canvas.setPointerCapture(event.pointerId);
    this.aimPreview = { start: point, current: point, releaseSpeedPxPerMs: 0, valid: false };
    event.preventDefault();
  }

  private onPointerMove(event: PointerEvent): void {
    if (!this.pointerSampler.owns(event.pointerId)) return;
    this.addPointerEventSamples(event);
    const gesture = calculateThrowGesture(this.pointerSampler.getSamples());
    if (gesture) {
      const current = { x: gesture.release.x, y: gesture.release.y };
      this.aimPreview = {
        start: { x: gesture.start.x, y: gesture.start.y },
        current,
        releaseSpeedPxPerMs: gesture.releaseSpeedPxPerMs,
        valid: isValidThrowGesture(gesture),
      };
    }
    event.preventDefault();
  }

  private onPointerUp(event: PointerEvent): void {
    if (!this.pointerSampler.owns(event.pointerId)) return;
    this.addPointerEventSamples(event);
    const gesture = this.pointerSampler.finish(event.pointerId);
    this.completePointerGesture(event.pointerId, gesture, event);
  }

  private completePointerGesture(
    pointerId: number,
    gesture: ReturnType<PointerSampler['finish']>,
    event?: PointerEvent,
  ): void {
    this.aimPreview = null;
    if (this.ui.canvas.hasPointerCapture(pointerId))
      this.ui.canvas.releasePointerCapture(pointerId);
    if (!gesture || !isValidThrowGesture(gesture) || !selectCanThrow(this.state)) {
      this.state.feedback = this.createInputFeedback(
        'SWIPE UPFIELD',
        'Start on the QB, then release toward a lane.',
      );
      event?.preventDefault();
      return;
    }
    const point = { x: gesture.release.x, y: gesture.release.y };
    const target = screenToFieldWorld(point, this.renderer.getProjection());
    this.state.debug.lastCollisionPoint = null;
    this.state.debug.lastCollisionKind = null;
    this.state.ball = createBallState(
      this.state.nextEntityId++,
      target,
      gesture.releaseSpeedPxPerMs,
      point,
    );
    this.audio.play('throw');
    this.audio.play('flight');
    event?.preventDefault();
  }

  private onPointerCancel(event: PointerEvent): void {
    if (!this.pointerSampler.owns(event.pointerId)) return;
    this.pointerSampler.cancel(event.pointerId);
    this.aimPreview = null;
  }

  private onPointerCaptureLost(event: PointerEvent): void {
    if (!this.pointerSampler.owns(event.pointerId)) return;
    if (event.pointerType === 'touch') {
      this.onPointerCancel(event);
      return;
    }
    // A trackpad can report capture loss instead of delivering pointer-up to
    // the canvas. The last accepted sample is still a valid release location.
    const gesture = this.pointerSampler.finish(event.pointerId);
    this.completePointerGesture(event.pointerId, gesture, event);
  }

  private addPointerEventSamples(event: PointerEvent): void {
    let coalescedEvents: PointerEvent[] = [];
    try {
      coalescedEvents = event.getCoalescedEvents();
    } catch {
      // Some WebKit builds expose the method but throw for pointer-up.
    }
    for (const sampleEvent of [...coalescedEvents, event]) {
      const point = this.pointerToLogical(sampleEvent);
      this.pointerSampler.add(event.pointerId, this.pointerSample(sampleEvent, point));
    }
  }

  private pointerToLogical(event: PointerEvent): ScreenPoint {
    const rect = this.ui.canvas.getBoundingClientRect();
    const projection = this.renderer.getProjection();
    return {
      x: ((event.clientX - rect.left) / rect.width) * projection.width,
      y: ((event.clientY - rect.top) / rect.height) * projection.height,
    };
  }

  private pointerSample(event: PointerEvent, point: ScreenPoint): PointerSample {
    return { x: point.x, y: point.y, timestampMs: event.timeStamp };
  }

  private createInputFeedback(headline: string, detail: string): FeedbackState {
    return { tone: 'negative', headline, detail, remainingMs: 950 };
  }

  private resize(): void {
    const viewportRatio = window.innerWidth / Math.max(1, window.innerHeight);
    const ratio =
      this.state.settings.viewMode === 'classic'
        ? 4 / 3
        : this.state.settings.viewMode === 'wide'
          ? 16 / 9
          : Math.max(4 / 3, Math.min(16 / 9, viewportRatio));
    this.ui.setAspectRatio(ratio);
    const devicePixelRatio = window.devicePixelRatio || 1;
    const stageWidth = this.ui.canvas.getBoundingClientRect().width;
    const renderScale = Math.max(
      1,
      Math.min(2, (stageWidth * devicePixelRatio) / GAMEPLAY_CONFIG.classicLogicalWidth),
    );
    this.renderer.resize(renderScale);
    this.ui.setOrientationWarning(window.innerHeight > window.innerWidth * 0.94);
    this.renderer.render(this.state, this.aimPreview);
  }

  private handleDebugAction(action: string, value?: string): void {
    if (!import.meta.env.DEV) return;
    switch (action) {
      case 'trajectory':
        this.state.debug.showTrajectory = value === 'true';
        break;
      case 'catch-zones':
        this.state.debug.showCatchZones = value === 'true';
        break;
      case 'defender-zones':
        this.state.debug.showDefenderHitZones = value === 'true';
        break;
      case 'slow-motion':
        this.state.debug.slowMotion = Math.max(0.1, Math.min(1, Number(value) || 1));
        break;
      case 'seed':
        this.state.randomState = Math.max(1, Number(value) || GAMEPLAY_CONFIG.defaultSeed);
        break;
      case 'freeze':
        this.state.debug.frozen = !this.state.debug.frozen;
        break;
      case 'reset':
      case 'reset-run':
        this.restart();
        break;
      case 'reset-defaults':
        resetRuntimeTuningToDefaults();
        this.applyRuntimeTuningToCurrentState('reset-defaults', true);
        this.ui.syncRuntimeTuningControls();
        break;
      case 'complete':
      case 'touchdown':
      case 'incomplete':
      case 'interception':
        this.forceOutcome(
          action === 'complete' ? 'completion' : action === 'incomplete' ? 'incompletion' : action,
        );
        break;
      default:
        if (value !== undefined && setRuntimeTuningValue(action, Number(value))) {
          this.applyRuntimeTuningToCurrentState(action);
          this.ui.syncRuntimeTuningControls();
        }
        break;
    }
  }

  private synchronizeTunedEntities(): void {
    for (const receiver of this.state.receivers) {
      if (!isRuntimeTuningControlOverridden(`lane-${receiver.laneId}-receiver-crossing`)) continue;
      const lane = getLaneConfig(receiver.laneId);
      receiver.speedPerMs =
        (2 * GAMEPLAY_CONFIG.receiverOffscreenX) / (lane.receiverCrossingSeconds * 1_000);
    }
    for (const [index, defender] of this.state.defenders.entries()) {
      if (isRuntimeTuningControlOverridden(`defender-${index + 1}-crossing`)) {
        if (GAMEPLAY_CONFIG.defenderCrossingSeconds[index] !== undefined) {
          defender.speedPerMs = getDefenderPatrolSpeedPerMs(index);
        }
      }
      if (isRuntimeTuningControlOverridden(`defender-${index + 1}-depth`)) {
        const depth = GAMEPLAY_CONFIG.defenderDepths[index];
        if (depth !== undefined) defender.depth = depth;
      }
    }
  }

  private applyRuntimeTuningToCurrentState(controlId: string, forceAll = false): void {
    const inactiveRun =
      this.state.phase === 'loading' ||
      this.state.phase === 'title' ||
      this.state.phase === 'instructions' ||
      this.state.phase === 'countdown' ||
      this.state.phase === 'results';
    if ((forceAll || controlId === 'session-duration') && inactiveRun) {
      this.state.remainingMs = getRuntimeSessionDurationMs();
    }
    if (forceAll || controlId === 'ball-radius') {
      if (this.state.ball) this.state.ball.radiusPx = GAMEPLAY_CONFIG.ballRadiusPx;
    }
    if (forceAll || controlId === 'meter-maximum') {
      this.state.tdMeter = Math.min(this.state.tdMeter, SCORE_CONFIG.tdMeterMaximum);
    }
    if (forceAll || controlId.startsWith('receiver-spawn-')) {
      for (const lane of PASSING_LANES) {
        const timer = this.state.laneSpawnTimers[lane.id];
        if (Number.isFinite(timer)) {
          this.state.laneSpawnTimers[lane.id] = Math.min(
            timer,
            GAMEPLAY_CONFIG.receiverSpawnDelayMs.max,
          );
        }
      }
    }

    if (forceAll || controlId.includes('receiver-crossing')) {
      for (const receiver of this.state.receivers) {
        const lane = getLaneConfig(receiver.laneId);
        receiver.speedPerMs =
          (2 * GAMEPLAY_CONFIG.receiverOffscreenX) / (lane.receiverCrossingSeconds * 1_000);
      }
    }
    const defenderSpeedChanged =
      forceAll || (controlId.startsWith('defender-') && controlId.endsWith('-crossing'));
    const defenderDepthChanged =
      forceAll || (controlId.startsWith('defender-') && controlId.endsWith('-depth'));
    if (defenderSpeedChanged || defenderDepthChanged) {
      for (const [index, defender] of this.state.defenders.entries()) {
        const crossingSeconds = GAMEPLAY_CONFIG.defenderCrossingSeconds[index];
        const depth = GAMEPLAY_CONFIG.defenderDepths[index];
        if (defenderSpeedChanged && crossingSeconds !== undefined) {
          defender.speedPerMs = getDefenderPatrolSpeedPerMs(index);
        }
        if (defenderDepthChanged && depth !== undefined) defender.depth = depth;
      }
    }
  }

  private forceOutcome(outcome: PassOutcome): void {
    if (this.state.phase !== 'playing') return;
    this.state.debug.forcedOutcome = outcome;
    if (!this.state.ball) {
      const target = { x: 0, depth: outcome === 'touchdown' ? 0.87 : 0.48, height: 0 };
      const marker = worldToScreen(target, this.renderer.getProjection());
      this.state.ball = createBallState(this.state.nextEntityId++, target, 1, marker);
    }
  }

  private installTestHooks(): void {
    window.render_game_to_text = () => this.renderGameToText();
    window.advanceTime = (milliseconds: number) => {
      const clamped = Math.max(0, Math.min(120_000, milliseconds));
      for (let elapsed = 0; elapsed < clamped; elapsed += FIXED_STEP_MS) {
        this.advanceSimulation(Math.min(FIXED_STEP_MS, clamped - elapsed));
      }
      this.renderer.render(this.state, this.aimPreview);
      this.ui.render(this.state);
    };
    window.setGameSeed = (seed: number) => {
      this.state.randomState = Math.max(1, Math.trunc(seed));
    };
  }

  private renderGameToText(): string {
    const projection = this.renderer.getProjection();
    const quarterback = getQuarterbackRect(projection);
    const ballScreen = this.state.ball ? worldToScreen(this.state.ball.current, projection) : null;
    return JSON.stringify({
      coordinateSystem: `logical pixels, origin top-left, +x right, +y down, ${projection.width}x${projection.height}`,
      phase: this.state.phase,
      score: this.state.score,
      remainingMs: Math.round(this.state.remainingMs),
      tdMeter: { value: this.state.tdMeter, maximum: SCORE_CONFIG.tdMeterMaximum },
      touchdownStreak: this.state.touchdownStreak,
      canThrow: selectCanThrow(this.state),
      input: {
        pointerActive: this.pointerSampler.isActive,
        aimActive: this.aimPreview !== null,
      },
      quarterback: {
        x: Math.round(quarterback.x),
        y: Math.round(quarterback.y),
        width: Math.round(quarterback.width),
        height: Math.round(quarterback.height),
      },
      receivers: this.state.receivers.map((receiver) => {
        const depth = getLaneConfig(receiver.laneId).normalizedDepth;
        const screen = worldToScreen({ x: receiver.x, depth, height: 0 }, projection);
        const visual = getReceiverVisualSelection(receiver);
        return {
          id: receiver.id,
          lane: receiver.laneId,
          x: Math.round(screen.x),
          y: Math.round(screen.y),
          direction: receiver.direction,
          pose: receiver.pose,
          visualPose: visual.pose,
          visualFrame: visual.frame + 1,
          hasCaught: receiver.hasCaught,
          animationMs: Math.round(receiver.animationMs),
        };
      }),
      defenders: this.state.defenders.map((defender) => {
        const screen = worldToScreen(
          { x: defender.x, depth: defender.depth, height: 0 },
          projection,
        );
        return {
          id: defender.id,
          x: Math.round(screen.x),
          y: Math.round(screen.y),
          direction: defender.direction,
          pose: defender.pose,
          animationMs: Math.round(defender.animationMs),
        };
      }),
      ball: this.state.ball
        ? {
            x: this.state.ball.current.x,
            depth: this.state.ball.current.depth,
            height: this.state.ball.current.height,
            elapsedMs: this.state.ball.elapsedMs,
            durationMs: this.state.ball.durationMs,
            screen: ballScreen ? { x: ballScreen.x, y: ballScreen.y } : null,
            aimMarker: this.state.ball.aimMarker,
            landing: this.state.ball.end,
          }
        : null,
      feedback: this.state.feedback?.headline ?? null,
      stats: this.state.stats,
    });
  }

  private handleHostBlocked(): void {
    this.hostBlocked = true;
    this.state.phase = 'loading';
    this.ui.setLoadingProgress(100, 'This build is not approved for the current host.');
    this.ui.setPhase('loading');
  }

  private async toggleFullscreen(): Promise<void> {
    if (document.fullscreenElement) await document.exitFullscreen();
    else await this.ui.shell.requestFullscreen();
    this.resize();
  }
}

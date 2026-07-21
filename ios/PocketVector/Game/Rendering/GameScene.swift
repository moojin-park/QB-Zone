import Foundation
import SpriteKit
import UIKit

enum GameSceneVisualReadiness: Equatable {
    case preparing
    case ready
    case failed
}

enum ForegroundQuarterbackPose: CaseIterable, Equatable {
    case idle
    case aim
    case throwing
    case recovery

    var texturePath: String {
        switch self {
        case .idle:
            "characters/qb-idle.webp"
        case .aim:
            "characters/qb-aim.webp"
        case .throwing:
            "characters/qb-throw.webp"
        case .recovery:
            "characters/qb-recovery.webp"
        }
    }
}

/// Render-only placement for the foreground quarterback and the opening
/// frames of the football's flight. Simulation continues to use
/// `GameplayConfig.quarterbackStart` as its authoritative release point.
enum ForegroundQuarterbackPresentation {
    static let renderedBaselineY: CGFloat = -310
    static let spriteSize = CGSize(width: 438, height: 584)
    static let releaseVerticalOffset: CGFloat = 60
    static let releaseAlignmentDurationMilliseconds: CGFloat = 180

    static func position(for projection: GameProjection) -> CGPoint {
        CGPoint(x: projection.centerX, y: renderedBaselineY)
    }

    static func pose(
        isAiming: Bool,
        ballElapsedMilliseconds: CGFloat?
    ) -> ForegroundQuarterbackPose {
        if isAiming {
            return .aim
        }
        guard let ballElapsedMilliseconds else {
            return .idle
        }
        if ballElapsedMilliseconds < releaseAlignmentDurationMilliseconds {
            return .throwing
        }
        if ballElapsedMilliseconds < 520 {
            return .recovery
        }
        return .idle
    }

    static func renderedBallPosition(
        simulatedPosition: CGPoint,
        elapsedMilliseconds: CGFloat
    ) -> CGPoint {
        CGPoint(
            x: simulatedPosition.x,
            y: simulatedPosition.y + releaseOffset(
                elapsedMilliseconds: elapsedMilliseconds
            )
        )
    }

    static func releaseOffset(elapsedMilliseconds: CGFloat) -> CGFloat {
        let alignmentWeight = min(1, max(
            0,
            1 - elapsedMilliseconds / releaseAlignmentDurationMilliseconds
        ))
        return releaseVerticalOffset * alignmentWeight
    }
}

@MainActor
final class GameScene: SKScene {
    private enum Palette {
        static let midnight = UIColor(red: 7 / 255, green: 21 / 255, blue: 38 / 255, alpha: 1)
        static let ink = UIColor(red: 3 / 255, green: 16 / 255, blue: 29 / 255, alpha: 1)
        static let cyan = UIColor(red: 66 / 255, green: 232 / 255, blue: 1, alpha: 1)
        static let coral = UIColor(red: 1, green: 93 / 255, blue: 115 / 255, alpha: 1)
        static let gold = UIColor(red: 1, green: 209 / 255, blue: 102 / 255, alpha: 1)
        static let ice = UIColor(red: 239 / 255, green: 252 / 255, blue: 1, alpha: 1)
        static let leather = UIColor(red: 158 / 255, green: 67 / 255, blue: 40 / 255, alpha: 1)
        static let leatherLight = UIColor(red: 226 / 255, green: 122 / 255, blue: 69 / 255, alpha: 1)
        static let leatherDark = UIColor(red: 70 / 255, green: 23 / 255, blue: 19 / 255, alpha: 1)
    }

    let configuration: RunConfiguration
    let settings: PlayerSettings

    private let runVisuals: RunVisualIdentity
    private let runUniformAssetRoots: RunGameplayUniformAssetRoots
    let fieldLayerStack: GameplayFieldLayerStack
    private var session: GameplaySession
    private let textures: TextureLibrary
    private let audio: GameAudioController
    private let now: @MainActor () -> Date
    private let onCompletedRun: @MainActor (CompletedRun) -> Void
    private let onGameplaySnapshotChanged: @MainActor (GameplaySceneSnapshot) -> Void
    private var snapshotPublicationGate = GameplaySnapshotPublicationGate()
    private var previousUpdateTime: TimeInterval?
    private var accumulatedMilliseconds: CGFloat = 0
    private var renderedPhase: GamePhase?
    private var lastCountdownValue = 3
    private var applicationIsActive = true
    private var viewport = GameViewport.canonical
    private var stageIsBuilt = false
    private(set) var visualReadiness: GameSceneVisualReadiness = .preparing
    private(set) var visualPreparationResult: GameplayVisualPrewarmResult?
    private var visualPreparationTask: Task<Void, Never>?

    private var projection: GameProjection {
        viewport.projection
    }

    private var fieldLayerNodes: [SKSpriteNode] = []
    private let sidelineEnvironmentNode = SidelineEnvironmentNode()
    private let actorLayer = SKNode()
    private let quarterbackNode = SKSpriteNode()
    private let ballNode = SKNode()
    private let ballBodyNode = SKShapeNode()
    private let ballShadeNode = SKShapeNode()
    private let ballHighlightNode = SKShapeNode()
    private let ballPanelNode = SKShapeNode()
    private let ballLacesNode = SKShapeNode()
    private var receiverNodes: [Int: SKSpriteNode] = [:]
    private var defenderNodes: [Int: SKSpriteNode] = [:]

    private var broadcastHUD: BroadcastHUDNode?
    private let phaseOverlay = SKNode()
    private let aimPathNode = SKShapeNode()
    private let aimMarkerNode = SKShapeNode()

    private var activeSamples: [TouchSample] = []
    private var isAiming = false

    #if DEBUG
    private var hudPreviewState: GameState?
    #endif

    init(
        size: CGSize,
        configuration: RunConfiguration,
        settings: PlayerSettings,
        textures: TextureLibrary = TextureLibrary(),
        now: @escaping @MainActor () -> Date = { Date() },
        onCompletedRun: @escaping @MainActor (CompletedRun) -> Void,
        onGameplaySnapshotChanged: @escaping @MainActor (GameplaySceneSnapshot) -> Void = { _ in }
    ) {
        guard let runVisuals = LaunchVisualIdentityCatalog.approved.runIdentity(
            for: configuration
        ) else {
            preconditionFailure("Run configuration does not resolve to approved shipping visuals")
        }
        guard let runUniformAssetRoots = RunGameplayUniformAssetRoots(
            configuration: configuration,
            catalog: .approved
        ) else {
            preconditionFailure("Run configuration does not resolve to approved baked uniforms")
        }
        self.configuration = configuration
        self.settings = settings
        self.runVisuals = runVisuals
        self.runUniformAssetRoots = runUniformAssetRoots
        fieldLayerStack = GameplayFieldLayerStack(
            offenseTeamID: configuration.offenseTeamID
        )
        session = GameplaySession(configuration: configuration, settings: settings)
        self.textures = textures
        audio = GameAudioController(settings: settings)
        self.now = now
        self.onCompletedRun = onCompletedRun
        self.onGameplaySnapshotChanged = onGameplaySnapshotChanged
        super.init(size: size)
        anchorPoint = .zero
        backgroundColor = Palette.ink
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("GameScene must be created programmatically")
    }

    deinit {
        visualPreparationTask?.cancel()
    }

    override func didMove(to view: SKView) {
        cancelVisualPreparation()
        visualReadiness = .preparing
        visualPreparationResult = nil
        previousUpdateTime = nil
        stageIsBuilt = false
        view.ignoresSiblingOrder = true
        view.isMultipleTouchEnabled = false
        applyViewport(makeViewport(for: view), relayout: false)
        setupStage()
        setupHUD()
        setupAimNodes()
        stageIsBuilt = true
        publishGameplaySnapshotIfNeeded()
        showVisualReadinessOverlay(.preparing)
        beginVisualPreparation()
    }

    override func willMove(from view: SKView) {
        cancelVisualPreparation()
        super.willMove(from: view)
    }

    override func update(_ currentTime: TimeInterval) {
        syncViewportIfNeeded()
        guard visualReadiness == .ready else {
            previousUpdateTime = nil
            return
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--spiral-preview") ||
            ProcessInfo.processInfo.arguments.contains("--hud-preview-active") {
            renderFrame()
            return
        }
        #endif
        guard applicationIsActive else {
            previousUpdateTime = nil
            renderFrame()
            return
        }
        guard let previousUpdateTime else {
            self.previousUpdateTime = currentTime
            renderFrame()
            return
        }

        let frameMilliseconds = min(
            GameplayConfig.maximumFrameDeltaMilliseconds,
            CGFloat((currentTime - previousUpdateTime) * 1_000)
        )
        self.previousUpdateTime = currentTime
        accumulatedMilliseconds += max(0, frameMilliseconds)
        while accumulatedMilliseconds >= GameplayConfig.fixedStepMilliseconds {
            advanceSimulationStep(deltaMilliseconds: GameplayConfig.fixedStepMilliseconds)
            accumulatedMilliseconds -= GameplayConfig.fixedStepMilliseconds
        }
        renderFrame()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        handlePrimaryInputBegan(
            at: touch.location(in: self),
            initialSample: sample(for: touch)
        )
    }

    /// Shared point-input seam for SpriteKit delivery and focused regression
    /// tests. A missing sample can inspect non-throw controls without starting
    /// an aiming gesture.
    func handlePrimaryInputBegan(
        at point: CGPoint,
        initialSample: TouchSample? = nil
    ) {
        guard visualReadiness == .ready else { return }

        switch session.state.phase {
        case .title, .results:
            // Production sessions are configured and started by SwiftUI. The
            // scene never owns title, replay, or results navigation.
            break
        case .paused:
            // Pause-menu actions are explicit SwiftUI controls. Gameplay
            // touches remain inert until the app requests Resume.
            break
        case .playing, .resolvingFinalBall:
            if broadcastHUD?.containsMuteControl(point) == true {
                let isMuted = audio.toggleMuted()
                if !isMuted {
                    audio.play(.uiSelect)
                }
                renderFrame()
                return
            }
            if broadcastHUD?.containsPauseControl(point) == true {
                pause()
                return
            }
            guard session.canThrow,
                  containsThrowActivationPoint(point),
                  let initialSample else { return }
            isAiming = true
            activeSamples = [initialSample]
            renderAimPreview(currentPoint: point)
        case .countdown:
            break
        }
    }

    /// Composes viewport-safe activation geometry with every lower-HUD
    /// exclusion. Control actions retain priority in `handlePrimaryInputBegan`.
    func containsThrowActivationPoint(_ point: CGPoint) -> Bool {
        guard viewport.containsThrowActivationPoint(point),
              broadcastHUD?.containsMuteControl(point) != true,
              broadcastHUD?.containsPauseControl(point) != true,
              broadcastHUD?.containsScoreReactionSurface(point) != true else {
            return false
        }
        return true
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isAiming, let touch = touches.first else { return }
        activeSamples.append(sample(for: touch))
        renderAimPreview(currentPoint: touch.location(in: self))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isAiming, let touch = touches.first else { return }
        activeSamples.append(sample(for: touch))
        let releasePoint = touch.location(in: self)
        if let gesture = ThrowGestureCalculator.calculate(samples: activeSamples), gesture.isValid {
            let target = projection.sceneToWorld(releasePoint)
            let didThrow = session.throwBall(
                target: target,
                releaseSpeedPixelsPerMillisecond: gesture.releaseSpeedPixelsPerMillisecond,
                aimMarker: GameProjection.worldToScene(target)
            )
            if didThrow {
                audio.play(.throwRelease)
                audio.play(.ballFlight)
            }
        }
        clearGesture()
        renderFrame()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        clearGesture()
        if visualReadiness == .ready {
            renderFrame()
        }
    }

    func setApplicationActive(_ isActive: Bool) {
        applicationIsActive = isActive
        previousUpdateTime = nil
        session.setApplicationActive(isActive)
        if isActive {
            audio.activateSession()
        } else {
            clearGesture()
            audio.suspend()
        }
        if visualReadiness == .ready {
            renderFrame()
        } else {
            showVisualReadinessOverlay(visualReadiness)
            publishGameplaySnapshotIfNeeded()
        }
    }

    var currentSnapshot: GameplaySceneSnapshot { session.snapshot }

    /// Resumes only an already-paused active run. Repeated requests are inert.
    @discardableResult
    func resume() -> Bool {
        guard session.resume() else { return false }

        previousUpdateTime = nil
        audio.play(.uiSelect)
        audio.startMusic()
        if visualReadiness == .ready {
            renderFrame()
        } else {
            publishGameplaySnapshotIfNeeded()
        }
        return true
    }

    /// Ends a run only after the app-owned confirmation flow authorizes it.
    /// The session completion gate keeps repeated confirmed requests exact-once.
    func commitConfirmedExitRun() {
        guard let completedRun = session.abandon(endedAt: now()) else { return }
        cancelVisualPreparation()
        previousUpdateTime = nil
        accumulatedMilliseconds = 0
        clearGesture()
        audio.stopMusic()
        audio.stopEffects()
        onCompletedRun(completedRun)
    }

    /// Compatibility seam for the existing PM-owned bridge. New integration
    /// should use `commitConfirmedExitRun()` only after confirmation succeeds.
    func requestAbandon() {
        commitConfirmedExitRun()
    }

    private func makeViewport(for view: SKView) -> GameViewport {
        let insets = view.safeAreaInsets
        return GameViewport(
            viewSize: view.bounds.size,
            safeAreaInsets: GameSafeAreaInsets(
                top: insets.top,
                left: insets.left,
                bottom: insets.bottom,
                right: insets.right
            )
        )
    }

    private func syncViewportIfNeeded() {
        guard let view else { return }
        applyViewport(makeViewport(for: view), relayout: stageIsBuilt)
    }

    private func applyViewport(_ newViewport: GameViewport, relayout: Bool) {
        guard newViewport != viewport else { return }
        viewport = newViewport
        size = newViewport.projection.sceneSize

        guard relayout else { return }
        clearGesture()
        layoutStageForViewport()
        setupHUD()
        renderedPhase = nil
        if visualReadiness != .ready {
            showVisualReadinessOverlay(visualReadiness)
        }
    }

    private func layoutStageForViewport() {
        for node in fieldLayerNodes {
            node.position = CGPoint(x: projection.centerX, y: 0)
        }
        sidelineEnvironmentNode.rebuild(
            for: projection,
            textures: textures
        )
        sidelineEnvironmentNode.isPaused = session.settings.reducedMotion
        quarterbackNode.position = ForegroundQuarterbackPresentation.position(
            for: projection
        )
    }

    private func advanceSimulationStep(deltaMilliseconds: CGFloat) {
        let phaseBefore = session.state.phase
        let remainingBefore = session.state.remainingMilliseconds
        let meterBefore = session.state.touchdownMeter
        let step = session.advance(deltaMilliseconds: deltaMilliseconds, endedAt: now())
        let result = step.update

        if phaseBefore == .countdown {
            if session.state.phase == .countdown {
                let countdownValue = max(
                    1,
                    Int(ceil(Double(session.state.countdownRemainingMilliseconds / 1_000)))
                )
                if countdownValue != lastCountdownValue {
                    lastCountdownValue = countdownValue
                    audio.play(.countdown)
                }
            } else if session.state.phase == .playing {
                audio.startMusic()
                audio.play(.snap)
            }
        }

        if phaseBefore == .playing,
           remainingBefore > 0,
           session.state.remainingMilliseconds <= 0 {
            audio.play(.timerExpired)
        }

        if let outcome = result.passResolved {
            switch outcome {
            case .completion:
                audio.play(result.laneID == .deep ? .deepCompletion : .catchCompletion)
            case .touchdown:
                audio.play(.touchdown)
                if (session.state.lastPlayScore?.touchdownMultiplier ?? 1) > 1 {
                    audio.play(.multiplierIncreased)
                }
            case .incompletion:
                audio.play(.incompletion)
                audio.play(.meterLoss)
            case .interception:
                audio.play(.interception)
                audio.play(.meterLoss)
            }

            if meterBefore < ScoringConfig.meterMaximum,
               session.state.touchdownMeter >= ScoringConfig.meterMaximum {
                audio.play(.bonusActivated)
            }
        }

        if result.runFinished {
            audio.stopMusic()
            audio.play(.gameOver)
        }

        if let completedRun = step.completedRun {
            onCompletedRun(completedRun)
        }
    }

    #if DEBUG
    private func configureHUDPreview() {
        _ = session.advance(deltaMilliseconds: 3_000, endedAt: now())

        var preview = session.state
        preview.phase = .playing
        preview.remainingMilliseconds = 44_000
        preview.score = 17_375
        preview.touchdownMeter = ScoringConfig.meterMaximum
        preview.touchdownStreak = 2
        preview.feedback = FeedbackState(
            headline: "TOUCHDOWN  +6,875",
            detail: "TD BONUS  ·  CHAIN x1.25",
            tone: .touchdown,
            remainingMilliseconds: 10_000
        )
        hudPreviewState = preview
    }

    private func configureSpiralPreview() {
        _ = session.advance(deltaMilliseconds: 3_000, endedAt: now())
        _ = session.throwBall(
            target: WorldPoint(x: 0.58, depth: 0.78, height: 0),
            releaseSpeedPixelsPerMillisecond: 0.35,
            aimMarker: CGPoint(x: 690, y: 520)
        )
        _ = session.advance(deltaMilliseconds: 360, endedAt: now())
    }
    #endif

    private func setupStage() {
        removeAllChildren()
        actorLayer.removeAllChildren()
        fieldLayerNodes.removeAll(keepingCapacity: true)
        receiverNodes.removeAll(keepingCapacity: true)
        defenderNodes.removeAll(keepingCapacity: true)

        for (index, layer) in fieldLayerStack.orderedLayers.enumerated() {
            let node = SKSpriteNode()
            node.name = layer.nodeName
            node.size = GameplayFieldLayerStack.textureSize
            node.anchorPoint = CGPoint(x: 0.5, y: 0)
            node.position = CGPoint(x: projection.centerX, y: 0)
            node.xScale = 1
            node.yScale = 1
            node.zPosition = -1_000 + CGFloat(index)
            fieldLayerNodes.append(node)
            addChild(node)
        }

        sidelineEnvironmentNode.name = "sideline.environment"
        sidelineEnvironmentNode.zPosition = -900
        addChild(sidelineEnvironmentNode)

        actorLayer.zPosition = 0
        addChild(actorLayer)

        quarterbackNode.anchorPoint = CGPoint(x: 0.5, y: 0)
        quarterbackNode.size = ForegroundQuarterbackPresentation.spriteSize
        quarterbackNode.zPosition = 1_500
        actorLayer.addChild(quarterbackNode)

        setupBallNode()
        layoutStageForViewport()
    }

    private func setupBallNode() {
        ballNode.removeAllChildren()
        ballNode.zPosition = 2_000
        ballNode.isHidden = true

        let bodyPath = CGMutablePath()
        bodyPath.move(to: CGPoint(x: -28, y: 0))
        bodyPath.addCurve(
            to: CGPoint(x: 28, y: 0),
            control1: CGPoint(x: -17, y: 15),
            control2: CGPoint(x: 17, y: 15)
        )
        bodyPath.addCurve(
            to: CGPoint(x: -28, y: 0),
            control1: CGPoint(x: 17, y: -15),
            control2: CGPoint(x: -17, y: -15)
        )
        bodyPath.closeSubpath()
        ballBodyNode.path = bodyPath
        ballBodyNode.fillColor = runVisuals.football.surface.uiColor
        ballBodyNode.strokeColor = runVisuals.football.seam.uiColor
        ballBodyNode.lineWidth = 4
        ballBodyNode.isAntialiased = false
        ballNode.addChild(ballBodyNode)

        let shadePath = CGMutablePath()
        shadePath.move(to: CGPoint(x: -17, y: -6))
        shadePath.addCurve(
            to: CGPoint(x: 19, y: -5),
            control1: CGPoint(x: -6, y: -12),
            control2: CGPoint(x: 9, y: -12)
        )
        ballShadeNode.path = shadePath
        ballShadeNode.strokeColor = runVisuals.football.seam.uiColor.withAlphaComponent(0.88)
        ballShadeNode.lineWidth = 4
        ballShadeNode.lineCap = .round
        ballShadeNode.isAntialiased = false
        ballShadeNode.zPosition = 1
        ballNode.addChild(ballShadeNode)

        let highlightPath = CGMutablePath()
        highlightPath.move(to: CGPoint(x: -17, y: 6))
        highlightPath.addCurve(
            to: CGPoint(x: 10, y: 8),
            control1: CGPoint(x: -9, y: 11),
            control2: CGPoint(x: 2, y: 11)
        )
        ballHighlightNode.path = highlightPath
        ballHighlightNode.strokeColor = runVisuals.football.detail.uiColor
        ballHighlightNode.lineWidth = 3
        ballHighlightNode.lineCap = .round
        ballHighlightNode.isAntialiased = false
        ballHighlightNode.zPosition = 2
        ballNode.addChild(ballHighlightNode)

        let panelPath = CGMutablePath()
        switch runVisuals.football.panelTreatment {
        case .orbitalSeam:
            panelPath.addEllipse(in: CGRect(x: -15, y: -10, width: 30, height: 20))
        case .vectorArcBands:
            panelPath.move(to: CGPoint(x: -20, y: -8))
            panelPath.addQuadCurve(
                to: CGPoint(x: -20, y: 8),
                control: CGPoint(x: -7, y: 0)
            )
            panelPath.move(to: CGPoint(x: 20, y: -8))
            panelPath.addQuadCurve(
                to: CGPoint(x: 20, y: 8),
                control: CGPoint(x: 7, y: 0)
            )
        }
        ballPanelNode.path = panelPath
        ballPanelNode.strokeColor = runVisuals.football.detail.uiColor
        ballPanelNode.lineWidth = 2.5
        ballPanelNode.lineCap = .round
        ballPanelNode.isAntialiased = false
        ballPanelNode.zPosition = 2.5
        ballNode.addChild(ballPanelNode)

        let lacesPath = CGMutablePath()
        lacesPath.move(to: CGPoint(x: -10, y: 0))
        lacesPath.addLine(to: CGPoint(x: 10, y: 0))
        for x in stride(from: CGFloat(-7), through: CGFloat(7), by: 3.5) {
            lacesPath.move(to: CGPoint(x: x, y: -3))
            lacesPath.addLine(to: CGPoint(x: x, y: 3))
        }
        ballLacesNode.path = lacesPath
        ballLacesNode.strokeColor = runVisuals.football.laces.uiColor
        ballLacesNode.lineWidth = 2
        ballLacesNode.lineCap = .square
        ballLacesNode.isAntialiased = false
        ballLacesNode.zPosition = 3
        ballNode.addChild(ballLacesNode)

        actorLayer.addChild(ballNode)
    }

    private func setupHUD() {
        broadcastHUD?.removeFromParent()
        let usesCompactHUD = UIDevice.current.userInterfaceIdiom == .phone &&
            min(viewport.viewSize.width, viewport.viewSize.height) <= 520
        let layout = HUDLayout(
            sceneSize: size,
            contentRect: viewport.safeSceneFrame,
            metrics: usesCompactHUD ? .compact : .canonical,
            displayScale: viewport.pointsPerSceneUnit
        )
        let hud = BroadcastHUDNode(
            layout: layout,
            textureLibrary: textures,
            teamIdentity: runVisuals.offenseTeam
        )
        broadcastHUD = hud
        addChild(hud)

        phaseOverlay.zPosition = 6_000
        if phaseOverlay.parent == nil {
            addChild(phaseOverlay)
        }
    }

    private func beginVisualPreparation() {
        cancelVisualPreparation()
        let textures = textures
        let uniformAssetRoots = runUniformAssetRoots
        let fieldLayerStack = fieldLayerStack
        visualPreparationTask = Task { [weak self, textures] in
            let result = await textures.prewarmRunVisualTextures(
                uniformAssetRoots: uniformAssetRoots,
                fieldLayerStack: fieldLayerStack
            )
            guard !Task.isCancelled, let self else { return }
            finishVisualPreparation(result)
        }
    }

    private func cancelVisualPreparation() {
        visualPreparationTask?.cancel()
        visualPreparationTask = nil
    }

    private func finishVisualPreparation(_ result: GameplayVisualPrewarmResult) {
        visualPreparationResult = result
        visualPreparationTask = nil
        guard result.isComplete, installFieldLayerTextures() else {
            visualReadiness = .failed
            showVisualReadinessOverlay(.failed)
            assertionFailure("Every run visual texture must be available before countdown")
            return
        }

        visualReadiness = .ready
        phaseOverlay.removeAllChildren()
        renderedPhase = nil
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--hud-preview-active") {
            configureHUDPreview()
            renderFrame()
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--spiral-preview") {
            configureSpiralPreview()
            renderFrame()
            return
        }
        #endif
        if applicationIsActive {
            audio.play(.countdown)
        }
        renderFrame()
    }

    private func installFieldLayerTextures() -> Bool {
        let layers = fieldLayerStack.orderedLayers
        let fieldTextures = layers.compactMap { layer in
            textures.texture(layer.relativePath)
        }
        guard fieldTextures.count == layers.count,
              fieldTextures.allSatisfy({
                  $0.size() == GameplayFieldLayerStack.textureSize
              }),
              fieldLayerNodes.count == layers.count else {
            return false
        }

        for (node, texture) in zip(fieldLayerNodes, fieldTextures) {
            node.texture = texture
            node.size = texture.size()
        }
        return true
    }

    private func showVisualReadinessOverlay(_ readiness: GameSceneVisualReadiness) {
        guard readiness != .ready else {
            phaseOverlay.removeAllChildren()
            return
        }

        phaseOverlay.removeAllChildren()
        addOverlayBackdrop(alpha: 0.48)

        let container = SKNode()
        container.name = readiness == .preparing
            ? "visualReadiness.loading"
            : "visualReadiness.failed"
        container.position = CGPoint(
            x: viewport.safeSceneFrame.midX,
            y: viewport.safeSceneFrame.midY
        )
        phaseOverlay.addChild(container)

        let panelSize = CGSize(width: min(580, viewport.safeSceneFrame.width * 0.62), height: 154)
        let panel = SKShapeNode(rectOf: panelSize, cornerRadius: 24)
        panel.fillColor = Palette.midnight.withAlphaComponent(0.97)
        panel.strokeColor = runVisuals.offenseTeam.hud.accent.uiColor
        panel.lineWidth = 4
        panel.zPosition = 0
        container.addChild(panel)

        let headline = makeLabel(
            readiness == .preparing ? "READYING MATCHUP" : "MATCHUP UNAVAILABLE",
            fontName: "AvenirNext-Heavy",
            fontSize: 34,
            color: Palette.ice
        )
        headline.position = CGPoint(x: 0, y: 22)
        headline.zPosition = 1
        container.addChild(headline)

        let detail = makeLabel(
            readiness == .preparing
                ? "Preparing matchup visuals…"
                : "Return home and try this run again.",
            fontName: "AvenirNext-DemiBold",
            fontSize: 20,
            color: readiness == .preparing
                ? runVisuals.offenseTeam.hud.primary.uiColor
                : Palette.coral
        )
        detail.position = CGPoint(x: 0, y: -28)
        detail.zPosition = 1
        container.addChild(detail)
    }

    private func setupAimNodes() {
        aimPathNode.strokeColor = runVisuals.offenseTeam.hud.primary.uiColor
        aimPathNode.lineWidth = 4
        aimPathNode.glowWidth = 1
        aimPathNode.zPosition = 2_500
        aimPathNode.isHidden = true
        addChild(aimPathNode)

        let markerPath = CGMutablePath()
        markerPath.move(to: CGPoint(x: -18, y: -18))
        markerPath.addLine(to: CGPoint(x: 18, y: 18))
        markerPath.move(to: CGPoint(x: -18, y: 18))
        markerPath.addLine(to: CGPoint(x: 18, y: -18))
        aimMarkerNode.path = markerPath
        aimMarkerNode.strokeColor = runVisuals.offenseTeam.hud.accent.uiColor
        aimMarkerNode.lineWidth = 6
        aimMarkerNode.zPosition = 2_510
        aimMarkerNode.isHidden = true
        addChild(aimMarkerNode)
    }

    private func renderFrame() {
        syncActors()
        syncBall()
        syncQuarterback()
        syncHUD()
        syncPhaseOverlay()
        syncAimMarker()
        publishGameplaySnapshotIfNeeded()
    }

    @discardableResult
    func pause() -> Bool {
        guard session.pause() else { return false }

        audio.play(.uiSelect)
        audio.pauseMusic()
        audio.stopEffects()
        clearGesture()
        renderFrame()
        return true
    }

    private func publishGameplaySnapshotIfNeeded() {
        guard stageIsBuilt else { return }

        let snapshot = session.snapshot
        guard snapshotPublicationGate.accept(snapshot) else { return }

        onGameplaySnapshotChanged(snapshot)
    }

    private func syncActors() {
        let receiverIDs = Set(session.state.receivers.map(\.id))
        for (id, node) in receiverNodes where !receiverIDs.contains(id) {
            node.removeFromParent()
            receiverNodes[id] = nil
        }
        for receiver in session.state.receivers {
            let node: SKSpriteNode
            if let existing = receiverNodes[receiver.id] {
                node = existing
            } else {
                node = SKSpriteNode()
                node.anchorPoint = CGPoint(x: 0.5, y: 0)
                actorLayer.addChild(node)
                receiverNodes[receiver.id] = node
            }
            let lane = GameplayConfig.lane(receiver.laneID)
            let scale = GameProjection.actorScale(depth: lane.depth)
            let ground = projection.worldToScene(
                WorldPoint(x: receiver.x, depth: lane.depth, height: 0)
            )
            node.position = CGPoint(x: ground.x, y: ground.y - 10)
            node.size = CGSize(
                width: GameProjection.actorSpriteSize.width * scale,
                height: GameProjection.actorSpriteSize.height * scale
            )
            node.zPosition = 1_000 - lane.depth * 500
            node.texture = textures.uniformTexture(
                receiverTexturePath(receiver),
                assetRoot: runUniformAssetRoots.offense
            )
        }

        let defenderIDs = Set(session.state.defenders.map(\.id))
        for (id, node) in defenderNodes where !defenderIDs.contains(id) {
            node.removeFromParent()
            defenderNodes[id] = nil
        }
        for defender in session.state.defenders {
            let node: SKSpriteNode
            if let existing = defenderNodes[defender.id] {
                node = existing
            } else {
                node = SKSpriteNode()
                node.anchorPoint = CGPoint(x: 0.5, y: 0)
                actorLayer.addChild(node)
                defenderNodes[defender.id] = node
            }
            let scale = GameProjection.actorScale(depth: defender.depth)
            let ground = projection.worldToScene(
                WorldPoint(x: defender.x, depth: defender.depth, height: 0)
            )
            node.position = CGPoint(x: ground.x, y: ground.y - 10)
            node.size = CGSize(
                width: GameProjection.actorSpriteSize.width * scale,
                height: GameProjection.actorSpriteSize.height * scale
            )
            node.zPosition = 1_000 - defender.depth * 500
            node.texture = textures.uniformTexture(
                defenderTexturePath(defender),
                assetRoot: runUniformAssetRoots.defense
            )
        }
    }

    private func syncBall() {
        guard let ball = session.state.ball else {
            ballNode.isHidden = true
            return
        }
        ballNode.isHidden = false
        ballNode.position = ForegroundQuarterbackPresentation.renderedBallPosition(
            simulatedPosition: projection.worldToScene(ball.current),
            elapsedMilliseconds: ball.elapsedMilliseconds
        )
        let scale = GameProjection.actorScale(depth: ball.current.depth)
        let radiusScale = ball.radiusPixels / GameplayConfig.defaultBallRadiusPixels
        ballNode.setScale(scale * radiusScale)

        let visual = BallVisualProjection.visualState(for: ball, projection: projection)
        ballNode.zRotation = visual.headingRadians
        ballLacesNode.position.y = visual.laceOffset
        ballLacesNode.alpha = visual.laceOpacity
        ballHighlightNode.position.y = visual.highlightOffset
        ballHighlightNode.alpha = 0.52 + visual.laceOpacity * 0.38
    }

    private func syncQuarterback() {
        let pose = ForegroundQuarterbackPresentation.pose(
            isAiming: isAiming,
            ballElapsedMilliseconds: session.state.ball?.elapsedMilliseconds
        )
        quarterbackNode.texture = textures.uniformTexture(
            pose.texturePath,
            assetRoot: runUniformAssetRoots.offense
        )
    }

    private func syncHUD() {
        #if DEBUG
        let state = hudPreviewState ?? session.state
        #else
        let state = session.state
        #endif
        broadcastHUD?.update(
            presentation: HUDPresentation(state: state),
            feedback: state.feedback,
            isMuted: audio.isMuted,
            reducedMotion: session.settings.reducedMotion
        )
    }

    private func syncPhaseOverlay() {
        let phase = session.state.phase
        if renderedPhase != phase {
            renderedPhase = phase
            phaseOverlay.removeAllChildren()
            switch phase {
            case .title, .results:
                // App-owned views present the title and authoritative results.
                break
            case .countdown:
                buildCountdownOverlay()
            case .paused:
                buildPausedOverlay()
            case .playing, .resolvingFinalBall:
                break
            }
        }

        if phase == .countdown,
           let countdown = phaseOverlay.childNode(withName: "countdown") as? SKLabelNode {
            countdown.text = String(max(1, Int(ceil(
                Double(session.state.countdownRemainingMilliseconds / 1_000)
            ))))
        }
    }

    private func buildCountdownOverlay() {
        addOverlayBackdrop(alpha: 0.18)
        let ready = makeLabel(
            "GET READY",
            fontName: "AvenirNext-Heavy",
            fontSize: 24,
            color: Palette.ice
        )
        ready.position = CGPoint(x: projection.centerX, y: 450)
        phaseOverlay.addChild(ready)

        let countdown = makeLabel(
            "3",
            fontName: "AvenirNext-Heavy",
            fontSize: 116,
            color: Palette.gold
        )
        countdown.name = "countdown"
        countdown.position = CGPoint(x: projection.centerX, y: 350)
        phaseOverlay.addChild(countdown)
    }

    private func buildPausedOverlay() {
        addOverlayBackdrop(alpha: 0.72)
        let title = makeLabel(
            "PAUSED",
            fontName: "AvenirNext-Heavy",
            fontSize: 62,
            color: Palette.ice
        )
        title.position = CGPoint(x: projection.centerX, y: 425)
        phaseOverlay.addChild(title)
    }

    private func addOverlayBackdrop(alpha: CGFloat) {
        let backdrop = SKSpriteNode(
            color: Palette.ink.withAlphaComponent(alpha),
            size: size
        )
        backdrop.anchorPoint = .zero
        backdrop.position = .zero
        backdrop.zPosition = -1
        phaseOverlay.addChild(backdrop)
    }

    private func renderAimPreview(currentPoint: CGPoint) {
        guard isAiming, let first = activeSamples.first else { return }
        let gesture = ThrowGestureCalculator.calculate(samples: activeSamples)
        let speed = gesture?.releaseSpeedPixelsPerMillisecond ?? 0.8
        let target = projection.sceneToWorld(currentPoint)
        let trajectory = Trajectory.parameters(
            start: GameplayConfig.quarterbackStart,
            target: target,
            releaseSpeedPixelsPerMillisecond: speed
        )
        let path = CGMutablePath()
        for index in 0 ... 36 {
            let progress = CGFloat(index) / 36
            let world = Trajectory.position(
                start: GameplayConfig.quarterbackStart,
                end: trajectory.end,
                arcHeight: trajectory.arcHeight,
                progress: progress
            )
            let point = ForegroundQuarterbackPresentation.renderedBallPosition(
                simulatedPosition: projection.worldToScene(world),
                elapsedMilliseconds: trajectory.durationMilliseconds * progress
            )
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        aimPathNode.path = path
        aimPathNode.strokeColor = gesture?.isValid == false
            ? Palette.gold
            : runVisuals.offenseTeam.hud.primary.uiColor
        aimPathNode.isHidden = hypot(currentPoint.x - first.point.x, currentPoint.y - first.point.y) < 8
        aimMarkerNode.position = projection.worldToScene(target)
        aimMarkerNode.strokeColor = gesture?.isValid == false
            ? Palette.gold
            : runVisuals.offenseTeam.hud.accent.uiColor
        aimMarkerNode.isHidden = false
    }

    private func syncAimMarker() {
        if isAiming { return }
        aimPathNode.isHidden = true
        if let ball = session.state.ball {
            aimMarkerNode.position = projection.worldToScene(ball.target)
            aimMarkerNode.strokeColor = runVisuals.offenseTeam.hud.accent.uiColor
            aimMarkerNode.isHidden = false
        } else {
            aimMarkerNode.isHidden = true
        }
    }

    private func clearGesture() {
        isAiming = false
        activeSamples.removeAll(keepingCapacity: true)
        aimPathNode.isHidden = true
    }

    private func sample(for touch: UITouch) -> TouchSample {
        TouchSample(
            point: touch.location(in: self),
            timestampMilliseconds: CGFloat(touch.timestamp * 1_000)
        )
    }

    private func receiverTexturePath(_ receiver: ReceiverState) -> String {
        let direction = receiver.direction < 0 ? "left" : "right"
        if receiver.pose == .catch, receiver.animationMilliseconds < 360 {
            return "characters/receiver-catch-\(direction).webp"
        }
        if receiver.pose == .celebrate, receiver.animationMilliseconds < 360 {
            return "characters/receiver-touchdown-\(direction).webp"
        }
        let frame = animationFrame(
            milliseconds: receiver.animationMilliseconds,
            entityID: receiver.id,
            frameDurationMilliseconds: 115
        ) + 1
        if receiver.hasCaught {
            let suffix = frame == 1 ? "" : "-\(frame)"
            return "characters/receiver-carry\(suffix)-\(direction).webp"
        }
        return "characters/receiver-run-\(frame)-\(direction).webp"
    }

    private func defenderTexturePath(_ defender: DefenderState) -> String {
        let direction = defender.direction < 0 ? "left" : "right"
        if defender.pose == .intercept, defender.animationMilliseconds < 340 {
            return "characters/defender-interception-\(direction).webp"
        }
        let frame = animationFrame(
            milliseconds: defender.animationMilliseconds,
            entityID: defender.id,
            frameDurationMilliseconds: 145
        ) + 1
        return "characters/defender-run-\(frame)-\(direction).webp"
    }

    private func animationFrame(
        milliseconds: CGFloat,
        entityID: Int,
        frameDurationMilliseconds: CGFloat
    ) -> Int {
        guard !session.settings.reducedMotion else { return 0 }
        let cadence = 0.94 + CGFloat((abs(entityID) * 37) % 13) * 0.01
        let cycleDuration = frameDurationMilliseconds * 4
        let phase = (
            max(0, milliseconds) * cadence + CGFloat(abs(entityID) * 71)
        ).truncatingRemainder(dividingBy: cycleDuration)
        return Int(phase / frameDurationMilliseconds)
    }

    private func makeLabel(
        _ text: String,
        fontName: String,
        fontSize: CGFloat,
        color: UIColor
    ) -> SKLabelNode {
        let label = SKLabelNode(fontNamed: fontName)
        label.text = text
        label.fontSize = fontSize
        label.fontColor = color
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        return label
    }

}

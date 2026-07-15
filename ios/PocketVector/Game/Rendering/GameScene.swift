import SpriteKit
import UIKit

@MainActor
final class GameScene: SKScene {
    private enum Palette {
        static let midnight = UIColor(red: 7 / 255, green: 21 / 255, blue: 38 / 255, alpha: 1)
        static let ink = UIColor(red: 3 / 255, green: 16 / 255, blue: 29 / 255, alpha: 1)
        static let cyan = UIColor(red: 66 / 255, green: 232 / 255, blue: 1, alpha: 1)
        static let coral = UIColor(red: 1, green: 93 / 255, blue: 115 / 255, alpha: 1)
        static let gold = UIColor(red: 1, green: 209 / 255, blue: 102 / 255, alpha: 1)
        static let ice = UIColor(red: 239 / 255, green: 252 / 255, blue: 1, alpha: 1)
        static let turf = UIColor(red: 25 / 255, green: 170 / 255, blue: 136 / 255, alpha: 1)
        static let leather = UIColor(red: 158 / 255, green: 67 / 255, blue: 40 / 255, alpha: 1)
        static let leatherLight = UIColor(red: 226 / 255, green: 122 / 255, blue: 69 / 255, alpha: 1)
        static let leatherDark = UIColor(red: 70 / 255, green: 23 / 255, blue: 19 / 255, alpha: 1)
    }

    private var simulation = GameSimulation()
    private let textures = TextureLibrary()
    private let audio = GameAudioController()
    private var previousUpdateTime: TimeInterval?
    private var accumulatedMilliseconds: CGFloat = 0
    private var renderedPhase: GamePhase?
    private var lastCountdownValue = 3
    private var applicationIsActive = true
    private var viewport = GameViewport.canonical
    private var stageIsBuilt = false

    private var projection: GameProjection {
        viewport.projection
    }

    private let fieldFillNode = SKSpriteNode()
    private let fieldNode = SKSpriteNode()
    private let sidelineEnvironmentNode = SidelineEnvironmentNode()
    private let actorLayer = SKNode()
    private let quarterbackNode = SKSpriteNode()
    private let ballNode = SKNode()
    private let ballBodyNode = SKShapeNode()
    private let ballShadeNode = SKShapeNode()
    private let ballHighlightNode = SKShapeNode()
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

    override init(size: CGSize) {
        super.init(size: size)
        anchorPoint = .zero
        backgroundColor = Palette.ink
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("GameScene must be created programmatically")
    }

    override func didMove(to view: SKView) {
        view.ignoresSiblingOrder = true
        view.isMultipleTouchEnabled = false
        applyViewport(makeViewport(for: view), relayout: false)
        setupStage()
        setupHUD()
        setupAimNodes()
        stageIsBuilt = true
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
        renderFrame()
    }

    override func update(_ currentTime: TimeInterval) {
        syncViewportIfNeeded()
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
        let point = touch.location(in: self)

        switch simulation.state.phase {
        case .title, .results:
            audio.stopMusic()
            audio.stopEffects()
            audio.play(.uiSelect)
            simulation.startRun()
            lastCountdownValue = 3
            audio.play(.countdown)
            clearGesture()
            renderFrame()
        case .paused:
            audio.play(.uiSelect)
            simulation.togglePause()
            audio.startMusic()
            renderFrame()
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
                audio.play(.uiSelect)
                simulation.togglePause()
                audio.pauseMusic()
                audio.stopEffects()
                clearGesture()
                renderFrame()
                return
            }
            guard simulation.canThrow, projection.isPointOnQuarterback(point) else { return }
            isAiming = true
            activeSamples = [sample(for: touch)]
            renderAimPreview(currentPoint: point)
        case .countdown:
            break
        }
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
            let didThrow = simulation.throwBall(
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
        renderFrame()
    }

    func setApplicationActive(_ isActive: Bool) {
        applicationIsActive = isActive
        previousUpdateTime = nil
        if isActive {
            audio.activateSession()
        } else {
            if simulation.state.phase == .playing || simulation.state.phase == .resolvingFinalBall {
                simulation.togglePause()
            }
            clearGesture()
            audio.suspend()
        }
        renderFrame()
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
    }

    private func layoutStageForViewport() {
        fieldFillNode.size = size
        fieldFillNode.position = .zero
        fieldNode.position = CGPoint(x: projection.centerX, y: 0)
        sidelineEnvironmentNode.rebuild(
            for: projection,
            endZoneTexture: textures.texture("art/endzone-nova-city-native.png"),
            textures: textures
        )
        quarterbackNode.position = CGPoint(x: projection.centerX, y: -370)
    }

    private func advanceSimulationStep(deltaMilliseconds: CGFloat) {
        let phaseBefore = simulation.state.phase
        let remainingBefore = simulation.state.remainingMilliseconds
        let meterBefore = simulation.state.touchdownMeter
        let result = simulation.update(deltaMilliseconds: deltaMilliseconds)

        if phaseBefore == .countdown {
            if simulation.state.phase == .countdown {
                let countdownValue = max(
                    1,
                    Int(ceil(Double(simulation.state.countdownRemainingMilliseconds / 1_000)))
                )
                if countdownValue != lastCountdownValue {
                    lastCountdownValue = countdownValue
                    audio.play(.countdown)
                }
            } else if simulation.state.phase == .playing {
                audio.startMusic()
                audio.play(.snap)
            }
        }

        if phaseBefore == .playing,
           remainingBefore > 0,
           simulation.state.remainingMilliseconds <= 0 {
            audio.play(.timerExpired)
        }

        if let outcome = result.passResolved {
            switch outcome {
            case .completion:
                audio.play(result.laneID == .deep ? .deepCompletion : .catchCompletion)
            case .touchdown:
                audio.play(.touchdown)
                if (simulation.state.lastPlayScore?.touchdownMultiplier ?? 1) > 1 {
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
               simulation.state.touchdownMeter >= ScoringConfig.meterMaximum {
                audio.play(.bonusActivated)
            }
        }

        if result.runFinished {
            audio.stopMusic()
            audio.play(.gameOver)
        }
    }

    #if DEBUG
    private func configureHUDPreview() {
        simulation.startRun()
        simulation.update(deltaMilliseconds: 3_000)

        var preview = simulation.state
        preview.phase = .playing
        preview.remainingMilliseconds = 44_000
        preview.score = 17_375
        preview.touchdownMeter = ScoringConfig.meterMaximum
        preview.touchdownStreak = 2
        preview.feedback = FeedbackState(
            headline: "TOUCHDOWN  +6,875",
            detail: "TD BONUS  ·  STREAK x1.25",
            tone: .touchdown,
            remainingMilliseconds: 10_000
        )
        hudPreviewState = preview
    }

    private func configureSpiralPreview() {
        simulation.startRun()
        simulation.update(deltaMilliseconds: 3_000)
        _ = simulation.throwBall(
            target: WorldPoint(x: 0.58, depth: 0.78, height: 0),
            releaseSpeedPixelsPerMillisecond: 0.35,
            aimMarker: CGPoint(x: 690, y: 520)
        )
        simulation.update(deltaMilliseconds: 360)
    }
    #endif

    private func setupStage() {
        removeAllChildren()
        actorLayer.removeAllChildren()
        receiverNodes.removeAll(keepingCapacity: true)
        defenderNodes.removeAll(keepingCapacity: true)

        fieldFillNode.color = Palette.turf
        fieldFillNode.colorBlendFactor = 1
        fieldFillNode.anchorPoint = .zero
        fieldFillNode.zPosition = -1_001
        addChild(fieldFillNode)

        let fieldTexture = textures.texture("pixel/stadium-field-wide-endzone-v3.png")
        if let fieldTexture {
            fieldNode.texture = fieldTexture
            fieldNode.size = fieldTexture.size()
            fieldNode.anchorPoint = CGPoint(x: 0.5, y: 0)
            fieldNode.zPosition = -1_000
            addChild(fieldNode)
        }

        sidelineEnvironmentNode.zPosition = -900
        addChild(sidelineEnvironmentNode)

        actorLayer.zPosition = 0
        addChild(actorLayer)

        quarterbackNode.anchorPoint = CGPoint(x: 0.5, y: 0)
        quarterbackNode.size = CGSize(width: 438, height: 584)
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
        ballBodyNode.fillColor = Palette.leather
        ballBodyNode.strokeColor = Palette.ink
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
        ballShadeNode.strokeColor = Palette.leatherDark
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
        ballHighlightNode.strokeColor = Palette.leatherLight
        ballHighlightNode.lineWidth = 3
        ballHighlightNode.lineCap = .round
        ballHighlightNode.isAntialiased = false
        ballHighlightNode.zPosition = 2
        ballNode.addChild(ballHighlightNode)

        let lacesPath = CGMutablePath()
        lacesPath.move(to: CGPoint(x: -10, y: 0))
        lacesPath.addLine(to: CGPoint(x: 10, y: 0))
        for x in stride(from: CGFloat(-7), through: CGFloat(7), by: 3.5) {
            lacesPath.move(to: CGPoint(x: x, y: -3))
            lacesPath.addLine(to: CGPoint(x: x, y: 3))
        }
        ballLacesNode.path = lacesPath
        ballLacesNode.strokeColor = UIColor(red: 1, green: 248 / 255, blue: 221 / 255, alpha: 1)
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
        let hud = BroadcastHUDNode(layout: layout, textureLibrary: textures)
        broadcastHUD = hud
        addChild(hud)

        phaseOverlay.zPosition = 6_000
        if phaseOverlay.parent == nil {
            addChild(phaseOverlay)
        }
    }

    private func setupAimNodes() {
        aimPathNode.strokeColor = Palette.cyan
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
        aimMarkerNode.strokeColor = Palette.coral
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
    }

    private func syncActors() {
        let receiverIDs = Set(simulation.state.receivers.map(\.id))
        for (id, node) in receiverNodes where !receiverIDs.contains(id) {
            node.removeFromParent()
            receiverNodes[id] = nil
        }
        for receiver in simulation.state.receivers {
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
            node.texture = textures.texture(receiverTexturePath(receiver))
        }

        let defenderIDs = Set(simulation.state.defenders.map(\.id))
        for (id, node) in defenderNodes where !defenderIDs.contains(id) {
            node.removeFromParent()
            defenderNodes[id] = nil
        }
        for defender in simulation.state.defenders {
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
            node.texture = textures.texture(defenderTexturePath(defender))
        }
    }

    private func syncBall() {
        guard let ball = simulation.state.ball else {
            ballNode.isHidden = true
            return
        }
        ballNode.isHidden = false
        ballNode.position = projection.worldToScene(ball.current)
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
        let path: String
        if isAiming {
            path = "characters/qb-aim.webp"
        } else if let ball = simulation.state.ball, ball.elapsedMilliseconds < 180 {
            path = "characters/qb-throw.webp"
        } else if let ball = simulation.state.ball, ball.elapsedMilliseconds < 520 {
            path = "characters/qb-recovery.webp"
        } else {
            path = "characters/qb-idle.webp"
        }
        quarterbackNode.texture = textures.texture(path)
    }

    private func syncHUD() {
        #if DEBUG
        let state = hudPreviewState ?? simulation.state
        #else
        let state = simulation.state
        #endif
        broadcastHUD?.update(
            presentation: HUDPresentation(state: state),
            feedback: state.feedback,
            isMuted: audio.isMuted
        )
    }

    private func syncPhaseOverlay() {
        let phase = simulation.state.phase
        if renderedPhase != phase {
            renderedPhase = phase
            phaseOverlay.removeAllChildren()
            switch phase {
            case .title:
                buildTitleOverlay()
            case .countdown:
                buildCountdownOverlay()
            case .paused:
                buildPausedOverlay()
            case .results:
                buildResultsOverlay()
            case .playing, .resolvingFinalBall:
                break
            }
        }

        if phase == .countdown,
           let countdown = phaseOverlay.childNode(withName: "countdown") as? SKLabelNode {
            countdown.text = String(max(1, Int(ceil(
                Double(simulation.state.countdownRemainingMilliseconds / 1_000)
            ))))
        }
    }

    private func buildTitleOverlay() {
        addOverlayBackdrop(alpha: 0.28)
        if let logoTexture = textures.texture("pixel/logo.png") {
            let logo = SKSpriteNode(texture: logoTexture)
            logo.size = CGSize(width: 500, height: 200)
            logo.position = CGPoint(x: projection.centerX, y: 520)
            logo.zPosition = 1
            phaseOverlay.addChild(logo)
        } else {
            let title = makeLabel(
                "POCKET VECTOR",
                fontName: "AvenirNext-Heavy",
                fontSize: 62,
                color: Palette.ice
            )
            title.position = CGPoint(x: projection.centerX, y: 525)
            phaseOverlay.addChild(title)
        }

        let subtitle = makeLabel(
            "NOVA CITY COMETS  vs  IRON BAY PHANTOMS",
            fontName: "AvenirNext-DemiBold",
            fontSize: 18,
            color: Palette.cyan
        )
        subtitle.position = CGPoint(x: projection.centerX, y: 410)
        phaseOverlay.addChild(subtitle)

        let start = makeLabel(
            "TAP TO START",
            fontName: "AvenirNext-Heavy",
            fontSize: 30,
            color: Palette.gold
        )
        start.position = CGPoint(x: projection.centerX, y: 325)
        phaseOverlay.addChild(start)

        let instructions = makeLabel(
            "PRESS THE QB  •  DRAG TO OPEN GRASS  •  RELEASE TO THROW",
            fontName: "AvenirNext-DemiBold",
            fontSize: 15,
            color: Palette.ice
        )
        instructions.position = CGPoint(x: projection.centerX, y: 282)
        phaseOverlay.addChild(instructions)
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

        let resume = makeLabel(
            "TAP ANYWHERE TO RESUME",
            fontName: "AvenirNext-DemiBold",
            fontSize: 22,
            color: Palette.gold
        )
        resume.position = CGPoint(x: projection.centerX, y: 350)
        phaseOverlay.addChild(resume)
    }

    private func buildResultsOverlay() {
        addOverlayBackdrop(alpha: 0.78)
        let title = makeLabel(
            "FINAL SCORE",
            fontName: "AvenirNext-Heavy",
            fontSize: 30,
            color: Palette.cyan
        )
        title.position = CGPoint(x: projection.centerX, y: 535)
        phaseOverlay.addChild(title)

        let score = makeLabel(
            formattedPoints(simulation.state.score),
            fontName: "Menlo-Bold",
            fontSize: 70,
            color: Palette.gold
        )
        score.position = CGPoint(x: projection.centerX, y: 455)
        phaseOverlay.addChild(score)

        let stats = simulation.state.statistics
        let summary = makeLabel(
            "\(stats.completions + stats.touchdowns)/\(stats.attempts) COMPLETE   •   \(stats.accuracy)% ACCURACY   •   \(stats.touchdowns) TD",
            fontName: "AvenirNext-DemiBold",
            fontSize: 19,
            color: Palette.ice
        )
        summary.position = CGPoint(x: projection.centerX, y: 370)
        phaseOverlay.addChild(summary)

        let replay = makeLabel(
            "TAP TO PLAY AGAIN",
            fontName: "AvenirNext-Heavy",
            fontSize: 26,
            color: Palette.gold
        )
        replay.position = CGPoint(x: projection.centerX, y: 295)
        phaseOverlay.addChild(replay)
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
            let world = Trajectory.position(
                start: GameplayConfig.quarterbackStart,
                end: trajectory.end,
                arcHeight: trajectory.arcHeight,
                progress: CGFloat(index) / 36
            )
            let point = projection.worldToScene(world)
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        aimPathNode.path = path
        aimPathNode.strokeColor = gesture?.isValid == false ? Palette.gold : Palette.cyan
        aimPathNode.isHidden = hypot(currentPoint.x - first.point.x, currentPoint.y - first.point.y) < 8
        aimMarkerNode.position = projection.worldToScene(target)
        aimMarkerNode.strokeColor = gesture?.isValid == false ? Palette.gold : Palette.coral
        aimMarkerNode.isHidden = false
    }

    private func syncAimMarker() {
        if isAiming { return }
        aimPathNode.isHidden = true
        if let ball = simulation.state.ball {
            aimMarkerNode.position = projection.worldToScene(ball.target)
            aimMarkerNode.strokeColor = Palette.coral
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

    private func formattedPoints(_ points: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: points)) ?? String(points)
    }
}

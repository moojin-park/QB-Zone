import SpriteKit
import UIKit

/// Keeps the HUD API aligned with the browser game's play-feedback model while
/// using the native simulation's existing value type.
typealias PlayFeedback = FeedbackState

/// SpriteKit rendering of the original browser game's four-corner broadcast HUD.
///
/// The node is intentionally self-contained: callers only add it to the scene,
/// forward the current presentation state, and use the exposed hit frames for
/// the two interactive controls.
@MainActor
final class BroadcastHUDNode: SKNode {
    private enum Palette {
        static let void = color(0x020611)
        static let ink = color(0x030914)
        static let cream = color(0xF4EAD4)
        static let clockCream = color(0xFFFAF0)
        static let meterCream = color(0xFFF5D5)
        static let steelLight = color(0xD0C9B8)
        static let steel = color(0x758092)
        static let steelDark = color(0x354157)
        static let gold = color(0xF4BC35)
        static let meterGold = color(0xFFD844)
        static let meterGoldActive = color(0xFFF08A)
        static let meterRed = color(0xED3B2B)
        static let meterRedActive = color(0xFF3829)
        static let red = color(0xD43A2E)
        static let redDark = color(0x7D1D22)
        static let coral = color(0xFF6A46)
        static let cobaltLight = color(0x29A7D2)
        static let positive = color(0x8CE6E6)
        static let scoreStripe = color(0x10233B)
        static let scoreBase = color(0x07101F)
        static let scoreInset = color(0x020914, alpha: 0.52)

        private static func color(_ value: UInt32, alpha: CGFloat = 1) -> UIColor {
            UIColor(
                red: CGFloat((value >> 16) & 0xff) / 255,
                green: CGFloat((value >> 8) & 0xff) / 255,
                blue: CGFloat(value & 0xff) / 255,
                alpha: alpha
            )
        }
    }

    let layout: HUDLayout
    let muteHitFrame: CGRect
    let pauseHitFrame: CGRect
    let scoreReactionExclusionFrame: CGRect

    /// Compatibility aliases for scene code that names the visible controls as buttons.
    var muteButtonFrame: CGRect { layout.muteButtonFrame }
    var pauseButtonFrame: CGRect { layout.pauseButtonFrame }

    private let textureLibrary: TextureLibrary
    private let scale: CGFloat
    private let teamIdentity: TeamVisualIdentity?
    private let teamPrimary: UIColor
    private let teamSecondary: UIColor
    private let teamAccent: UIColor
    private let feedbackAnnouncementHandler: (String) -> Void

    private let meterNode = SKNode()
    private let meterCopyNode = SKNode()
    private let fillCropNode = SKCropNode()
    private let fillMaskNode = SKSpriteNode(color: .white, size: .zero)
    private let goldFillNode = SKSpriteNode()
    private let redFillNode = SKSpriteNode()
    private let meterOutlineNode = SKShapeNode()
    private let meterActiveGlowNode = SKShapeNode()
    private let multiplierLabel: ShadowedLabel

    private let clockLabel: ShadowedLabel
    private let scoreLabel: ShadowedLabel
    private let muteIconNode = SKSpriteNode()
    private let pauseIconNode = SKSpriteNode()
    private let muteBorderNode = SKShapeNode()
    private let feedbackNode = SKNode()

    private var renderedMuted: Bool?
    private var renderedBonusActive: Bool?
    private var renderedTimerWarning: Bool?
    private var renderedFeedbackSignature: String?
    private var renderedFeedbackRemainingMilliseconds: CGFloat?
    private var renderedFeedbackFinalPosition: CGPoint?
    private var reducedMotion = false

    static let feedbackRevealActionKey = "scoreReactionReveal"

    init(
        layout: HUDLayout,
        textureLibrary: TextureLibrary,
        teamIdentity: TeamVisualIdentity? = nil,
        feedbackAnnouncementHandler: @escaping (String) -> Void = { announcement in
            guard UIAccessibility.isVoiceOverRunning else { return }
            UIAccessibility.post(notification: .announcement, argument: announcement)
        }
    ) {
        self.layout = layout
        self.textureLibrary = textureLibrary
        self.teamIdentity = teamIdentity
        let resolvedPrimary = teamIdentity?.hud.primary.uiColor ?? Palette.red
        let resolvedSecondary = teamIdentity?.hud.secondary.uiColor ?? Palette.redDark
        let resolvedAccent = teamIdentity?.hud.accent.uiColor ?? Palette.coral
        teamPrimary = resolvedPrimary
        teamSecondary = resolvedSecondary
        teamAccent = resolvedAccent
        self.feedbackAnnouncementHandler = feedbackAnnouncementHandler
        let controlHitFrames = Self.controlHitFrames(for: layout)
        muteHitFrame = controlHitFrames.mute
        pauseHitFrame = controlHitFrames.pause
        scoreReactionExclusionFrame = layout.scorePlateFrame.union(
            layout.feedbackTwoLineFrame
        )
        let sceneScale = min(
            layout.contentRect.width / HUDLayout.referenceSize.width,
            layout.contentRect.height / HUDLayout.referenceSize.height
        )
        scale = max(sceneScale, 1 / layout.displayScale)

        multiplierLabel = ShadowedLabel(
            fontName: "Impact",
            fontSize: layout.multiplierFontSize,
            color: resolvedAccent,
            outlineDistance: max(1, 2 * scale)
        )
        clockLabel = ShadowedLabel(
            fontName: "Impact",
            fontSize: layout.clockFontSize,
            color: Palette.clockCream,
            outlineDistance: max(1, 2 * scale),
            dropDistance: max(2, 4 * scale)
        )
        scoreLabel = ShadowedLabel(
            fontName: "Impact",
            fontSize: layout.scoreFontSize,
            color: Palette.cream,
            outlineDistance: max(1, 3 * scale),
            dropDistance: max(2, 4 * scale)
        )

        super.init()

        name = "broadcastHUD"
        zPosition = 5_000
        isUserInteractionEnabled = false

        buildMeter()
        buildClock()
        buildScoreBug()
        buildControls()
        feedbackNode.name = "scoreReaction"
        feedbackNode.zPosition = 9
        feedbackNode.isAccessibilityElement = false
        feedbackNode.accessibilityElementsHidden = true
        addChild(feedbackNode)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("BroadcastHUDNode must be created programmatically")
    }

    private static func controlHitFrames(for layout: HUDLayout) -> (mute: CGRect, pause: CGRect) {
        let minimumHitSide = 44 / max(0.001, layout.displayScale)
        let visualSide = max(layout.muteButtonFrame.width, layout.pauseButtonFrame.width)
        guard minimumHitSide > visualSide else {
            return (layout.muteButtonFrame, layout.pauseButtonFrame)
        }

        let dividerX = (layout.muteButtonFrame.maxX + layout.pauseButtonFrame.minX) / 2
        let visualMidY = (layout.muteButtonFrame.midY + layout.pauseButtonFrame.midY) / 2
        let hitY = max(
            layout.contentRect.minY,
            min(visualMidY - minimumHitSide / 2, layout.contentRect.maxY - minimumHitSide)
        )

        return (
            CGRect(
                x: dividerX - minimumHitSide,
                y: hitY,
                width: minimumHitSide,
                height: minimumHitSide
            ),
            CGRect(
                x: dividerX,
                y: hitY,
                width: minimumHitSide,
                height: minimumHitSide
            )
        )
    }

    func update(
        presentation: HUDPresentation,
        feedback: PlayFeedback?,
        isMuted: Bool,
        reducedMotion: Bool
    ) {
        let motionSettingChanged = self.reducedMotion != reducedMotion
        self.reducedMotion = reducedMotion
        isHidden = !presentation.isVisible
        guard presentation.isVisible else {
            feedbackNode.isHidden = true
            return
        }

        clockLabel.text = presentation.clockText
        clockLabel.color = presentation.isTimerWarning ? Palette.coral : Palette.clockCream
        if renderedTimerWarning != presentation.isTimerWarning || motionSettingChanged {
            renderedTimerWarning = presentation.isTimerWarning
            setTimerWarning(presentation.isTimerWarning)
        }
        scoreLabel.text = presentation.scoreText
        multiplierLabel.text = presentation.multiplierText

        let fillFrame = layout.meterFillFrame(progress: presentation.meterProgress)
        fillMaskNode.size = CGSize(
            width: max(0.01, fillFrame.width),
            height: fillFrame.height
        )
        fillMaskNode.position = CGPoint(x: fillFrame.midX, y: fillFrame.midY)
        fillCropNode.isHidden = fillFrame.width <= 0.01

        if renderedBonusActive != presentation.isBonusActive || motionSettingChanged {
            renderedBonusActive = presentation.isBonusActive
            setBonusActive(presentation.isBonusActive)
        }

        if renderedMuted != isMuted {
            renderedMuted = isMuted
            muteIconNode.texture = textureLibrary.texture(
                isMuted ? "art/icon-mute-native.png" : "art/icon-unmute-native.png"
            )
            muteBorderNode.fillColor = isMuted ? Palette.red : teamAccent
        }

        if motionSettingChanged { settleCurrentFeedbackMotion() }
        updateFeedback(feedback)
    }

    func containsMuteControl(_ scenePoint: CGPoint) -> Bool {
        muteHitFrame.contains(scenePoint)
    }

    func containsPauseControl(_ scenePoint: CGPoint) -> Bool {
        pauseHitFrame.contains(scenePoint)
    }

    func containsScoreReactionSurface(_ scenePoint: CGPoint) -> Bool {
        scoreReactionExclusionFrame.contains(scenePoint)
    }

    private func buildMeter() {
        meterNode.name = "adrenalineMeter"
        meterNode.zPosition = 10
        addChild(meterNode)

        let trackFrame = layout.meterTrackFrame
        let trackPath = layout.meterMaskPath

        let dropShadow = SKShapeNode(path: trackPath)
        dropShadow.fillColor = Palette.void.withAlphaComponent(0.90)
        dropShadow.strokeColor = .clear
        dropShadow.position = CGPoint(x: max(2, 4 * scale), y: -max(3, 5 * scale))
        dropShadow.zPosition = -3
        meterNode.addChild(dropShadow)

        let meterCrop = SKCropNode()
        let curveMask = SKShapeNode(path: trackPath)
        curveMask.fillColor = .white
        curveMask.strokeColor = .clear
        curveMask.isAntialiased = true
        meterCrop.maskNode = curveMask
        meterCrop.zPosition = 0
        meterNode.addChild(meterCrop)

        meterCrop.addChild(sprite(
            color: Palette.ink,
            frame: trackFrame,
            zPosition: 0
        ))

        let goldPreviewFrame = CGRect(
            x: trackFrame.minX,
            y: trackFrame.minY,
            width: trackFrame.width * 0.70,
            height: trackFrame.height
        )
        meterCrop.addChild(sprite(
            color: Palette.meterGold.withAlphaComponent(0.28),
            frame: goldPreviewFrame,
            zPosition: 1
        ))
        meterCrop.addChild(sprite(
            color: Palette.meterRed.withAlphaComponent(0.34),
            frame: CGRect(
                x: goldPreviewFrame.maxX,
                y: trackFrame.minY,
                width: trackFrame.width * 0.30,
                height: trackFrame.height
            ),
            zPosition: 1
        ))

        fillMaskNode.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        fillCropNode.maskNode = fillMaskNode
        fillCropNode.zPosition = 2
        meterCrop.addChild(fillCropNode)

        goldFillNode.color = Palette.meterGold
        goldFillNode.size = goldPreviewFrame.size
        goldFillNode.position = CGPoint(x: goldPreviewFrame.midX, y: goldPreviewFrame.midY)
        goldFillNode.zPosition = 0
        fillCropNode.addChild(goldFillNode)

        let redFillFrame = CGRect(
            x: goldPreviewFrame.maxX,
            y: trackFrame.minY,
            width: trackFrame.width * 0.30,
            height: trackFrame.height
        )
        redFillNode.color = Palette.meterRed
        redFillNode.size = redFillFrame.size
        redFillNode.position = CGPoint(x: redFillFrame.midX, y: redFillFrame.midY)
        redFillNode.zPosition = 0
        fillCropNode.addChild(redFillNode)

        fillCropNode.addChild(sprite(
            color: UIColor.black.withAlphaComponent(0.32),
            frame: CGRect(
                x: trackFrame.minX,
                y: trackFrame.minY,
                width: trackFrame.width,
                height: trackFrame.height * 0.32
            ),
            zPosition: 1
        ))

        meterCrop.addChild(sprite(
            color: UIColor.white.withAlphaComponent(0.20),
            frame: CGRect(
                x: trackFrame.minX,
                y: trackFrame.maxY - trackFrame.height * 0.22,
                width: trackFrame.width,
                height: trackFrame.height * 0.22
            ),
            zPosition: 3
        ))
        meterCrop.addChild(sprite(
            color: UIColor.black.withAlphaComponent(0.24),
            frame: CGRect(
                x: trackFrame.minX,
                y: trackFrame.minY,
                width: trackFrame.width,
                height: trackFrame.height * 0.18
            ),
            zPosition: 3
        ))

        let dividerWidth = max(2, 4 * scale)
        for xPosition in layout.meterDividerXPositions {
            let divider = SKSpriteNode(
                color: Palette.void.withAlphaComponent(0.96),
                size: CGSize(width: dividerWidth, height: trackFrame.height)
            )
            divider.position = CGPoint(x: xPosition, y: trackFrame.midY)
            divider.zPosition = 4
            meterCrop.addChild(divider)
        }

        meterOutlineNode.path = trackPath
        meterOutlineNode.fillColor = .clear
        meterOutlineNode.strokeColor = Palette.meterCream.withAlphaComponent(0.22)
        meterOutlineNode.lineWidth = max(1, scale)
        meterOutlineNode.zPosition = 5
        meterNode.addChild(meterOutlineNode)

        meterActiveGlowNode.path = trackPath
        meterActiveGlowNode.fillColor = .clear
        meterActiveGlowNode.strokeColor = Palette.meterGoldActive.withAlphaComponent(0.92)
        meterActiveGlowNode.lineWidth = max(1, 2 * scale)
        meterActiveGlowNode.glowWidth = max(3, 8 * scale)
        meterActiveGlowNode.zPosition = 6
        meterActiveGlowNode.isHidden = true
        meterNode.addChild(meterActiveGlowNode)

        buildMeterCopy()
    }

    private func buildMeterCopy() {
        meterCopyNode.zPosition = 10
        meterNode.addChild(meterCopyNode)

        let title = ShadowedLabel(
            fontName: "Impact",
            fontSize: layout.meterTitleFontSize,
            color: Palette.meterCream,
            outlineDistance: max(1, 2 * scale)
        )
        title.text = "ADRENALINE"
        title.horizontalAlignmentMode = .left
        title.verticalAlignmentMode = .top
        title.position = layout.meterHeadingAnchor
        meterCopyNode.addChild(title)

        let action = ShadowedLabel(
            fontName: "AvenirNextCondensed-HeavyItalic",
            fontSize: layout.meterActionFontSize,
            color: teamAccent,
            outlineDistance: max(1, scale)
        )
        action.text = "COMPLETE PASSES"
        action.horizontalAlignmentMode = .left
        action.verticalAlignmentMode = .top
        action.position = CGPoint(
            x: layout.adrenalineFrame.minX + layout.adrenalineFrame.width * 0.43,
            y: layout.meterHeadingAnchor.y - max(2, layout.meterTitleFontSize * 0.12)
        )
        meterCopyNode.addChild(action)

        multiplierLabel.text = "TD x1"
        multiplierLabel.horizontalAlignmentMode = .left
        multiplierLabel.verticalAlignmentMode = .top
        multiplierLabel.position = layout.multiplierTopAnchor
        meterCopyNode.addChild(multiplierLabel)

        let ready = ShadowedLabel(
            fontName: "AvenirNextCondensed-HeavyItalic",
            fontSize: layout.readyCopyFontSize,
            color: teamAccent,
            outlineDistance: max(1, scale)
        )
        ready.text = "LET IT RIP!"
        ready.horizontalAlignmentMode = .right
        ready.verticalAlignmentMode = .center
        ready.position = layout.readyCopyAnchor
        meterCopyNode.addChild(ready)
    }

    private func buildClock() {
        clockLabel.name = "gameClock"
        clockLabel.text = "1:00"
        clockLabel.horizontalAlignmentMode = .center
        clockLabel.verticalAlignmentMode = .top
        clockLabel.position = layout.clockTopAnchor
        clockLabel.zPosition = 20
        addChild(clockLabel)
    }

    private func buildScoreBug() {
        let frame = layout.scorePlateFrame
        let path = scoreBugPath(in: frame)
        let root = SKNode()
        root.name = "scoreBug"
        root.zPosition = 10
        addChild(root)

        let shadow = SKShapeNode(path: path)
        shadow.fillColor = UIColor.black.withAlphaComponent(0.86)
        shadow.strokeColor = .clear
        shadow.position = CGPoint(x: max(2, 4 * scale), y: -max(2, 4 * scale))
        shadow.zPosition = -2
        root.addChild(shadow)

        let crop = SKCropNode()
        let mask = SKShapeNode(path: path)
        mask.fillColor = .white
        mask.strokeColor = .clear
        mask.isAntialiased = false
        crop.maskNode = mask
        crop.zPosition = 0
        root.addChild(crop)

        crop.addChild(sprite(color: Palette.scoreBase, frame: frame, zPosition: 0))
        let stripeHeight = max(2, 4 * scale)
        let stripePeriod = stripeHeight * 2
        var stripeY = frame.minY
        while stripeY < frame.maxY {
            crop.addChild(sprite(
                color: teamPrimary.withAlphaComponent(0.22),
                frame: CGRect(
                    x: frame.minX,
                    y: stripeY,
                    width: frame.width,
                    height: min(stripeHeight, frame.maxY - stripeY)
                ),
                zPosition: 1
            ))
            stripeY += stripePeriod
        }

        crop.addChild(sprite(
            color: UIColor(red: 207 / 255, green: 212 / 255, blue: 216 / 255, alpha: 1),
            frame: CGRect(
                x: frame.minX,
                y: frame.maxY - frame.height * 0.05,
                width: frame.width,
                height: frame.height * 0.05
            ),
            zPosition: 2
        ))
        crop.addChild(sprite(
            color: UIColor(red: 107 / 255, green: 119 / 255, blue: 136 / 255, alpha: 1),
            frame: CGRect(
                x: frame.minX,
                y: frame.maxY - frame.height * 0.10,
                width: frame.width,
                height: frame.height * 0.05
            ),
            zPosition: 2
        ))

        let redStripeFrame = CGRect(
            x: frame.maxX - frame.width * 0.045,
            y: frame.minY + frame.height * 0.07,
            width: frame.width * 0.045,
            height: frame.height * 0.83
        )
        crop.addChild(sprite(
            color: Palette.void,
            frame: CGRect(
                x: redStripeFrame.minX - max(2, 3 * scale),
                y: redStripeFrame.minY,
                width: max(2, 3 * scale),
                height: redStripeFrame.height
            ),
            zPosition: 3
        ))
        crop.addChild(sprite(color: teamPrimary, frame: redStripeFrame, zPosition: 4))
        crop.addChild(sprite(
            color: teamAccent,
            frame: CGRect(
                x: redStripeFrame.minX,
                y: redStripeFrame.maxY - redStripeFrame.height * 0.24,
                width: redStripeFrame.width,
                height: redStripeFrame.height * 0.24
            ),
            zPosition: 5
        ))
        crop.addChild(sprite(
            color: teamSecondary,
            frame: CGRect(
                x: redStripeFrame.minX,
                y: redStripeFrame.minY,
                width: redStripeFrame.width,
                height: redStripeFrame.height * 0.24
            ),
            zPosition: 5
        ))

        let insetFrame = CGRect(
            x: frame.minX + frame.width * 0.07,
            y: frame.minY + frame.height * 0.09,
            width: frame.width * 0.88,
            height: frame.height * 0.76
        )
        let insetShadow = SKShapeNode(rect: insetFrame.insetBy(dx: -max(1, 2 * scale), dy: -max(1, 2 * scale)))
        insetShadow.fillColor = Palette.void
        insetShadow.strokeColor = .clear
        insetShadow.zPosition = 5
        crop.addChild(insetShadow)

        let inset = SKShapeNode(rect: insetFrame)
        inset.fillColor = Palette.scoreInset
        inset.strokeColor = UIColor(red: 80 / 255, green: 97 / 255, blue: 122 / 255, alpha: 1)
        inset.lineWidth = max(1, 2 * scale)
        inset.zPosition = 6
        crop.addChild(inset)

        let insetTop = SKSpriteNode(
            color: UIColor(red: 24 / 255, green: 50 / 255, blue: 79 / 255, alpha: 1),
            size: CGSize(width: insetFrame.width, height: max(1, 2 * scale))
        )
        insetTop.position = CGPoint(x: insetFrame.midX, y: insetFrame.maxY - max(0.5, scale))
        insetTop.zPosition = 7
        crop.addChild(insetTop)

        let kicker = ShadowedLabel(
            fontName: "AvenirNextCondensed-HeavyItalic",
            fontSize: layout.pointsFontSize,
            color: UIColor(red: 206 / 255, green: 213 / 255, blue: 223 / 255, alpha: 1),
            outlineDistance: max(1, 2 * scale)
        )
        kicker.text = "POINTS"
        kicker.horizontalAlignmentMode = .right
        kicker.verticalAlignmentMode = .center
        kicker.position = layout.pointsKickerAnchor
        kicker.zPosition = 10
        root.addChild(kicker)

        scoreLabel.text = "0"
        scoreLabel.horizontalAlignmentMode = .left
        scoreLabel.verticalAlignmentMode = .center
        scoreLabel.position = layout.scoreValueAnchor
        scoreLabel.zPosition = 10
        root.addChild(scoreLabel)

        if let teamIdentity {
            let emblemSide = min(frame.height * 0.46, frame.width * 0.15)
            let emblem = SKSpriteNode(texture: textureLibrary.emblemTexture(
                for: teamIdentity,
                size: CGSize(width: emblemSide, height: emblemSide)
            ))
            emblem.name = "hudTeamEmblem.\(teamIdentity.teamID.rawValue)"
            emblem.size = CGSize(width: emblemSide, height: emblemSide)
            emblem.position = CGPoint(x: frame.minX + frame.width * 0.16, y: frame.midY)
            emblem.zPosition = 11
            root.addChild(emblem)
        }
    }

    private func buildControls() {
        let controls = SKNode()
        controls.name = "hudControls"
        controls.zPosition = 20
        addChild(controls)

        let muteButton = buildControlButton(
            frame: layout.muteButtonFrame,
            iconNode: muteIconNode,
            iconPath: "art/icon-unmute-native.png"
        )
        muteBorderNode.path = Self.controlPixelCutPath(
            in: layout.muteButtonFrame,
            corner: max(2, 4 * scale)
        )
        muteBorderNode.fillColor = teamAccent
        muteBorderNode.strokeColor = .clear
        muteBorderNode.zPosition = 0
        muteButton.addChild(muteBorderNode)
        controls.addChild(muteButton)

        controls.addChild(buildControlButton(
            frame: layout.pauseButtonFrame,
            iconNode: pauseIconNode,
            iconPath: "art/icon-pause-native.png",
            includeBorder: true
        ))
    }

    private func buildControlButton(
        frame: CGRect,
        iconNode: SKSpriteNode,
        iconPath: String,
        includeBorder: Bool = false
    ) -> SKNode {
        let root = SKNode()

        let path = Self.controlPixelCutPath(in: frame, corner: max(2, 4 * scale))
        let shadow = SKShapeNode(path: path)
        shadow.fillColor = UIColor.black
        shadow.strokeColor = .clear
        shadow.position = CGPoint(x: 0, y: -max(2, 3 * scale))
        shadow.zPosition = -2
        root.addChild(shadow)

        if includeBorder {
            let border = SKShapeNode(path: path)
            border.fillColor = teamAccent
            border.strokeColor = .clear
            border.zPosition = 0
            root.addChild(border)
        }

        let innerFrame = frame.insetBy(dx: max(1, 2 * scale), dy: max(1, 2 * scale))
        let innerPath = Self.controlPixelCutPath(in: innerFrame, corner: max(1, 3 * scale))
        let crop = SKCropNode()
        let mask = SKShapeNode(path: innerPath)
        mask.fillColor = .white
        mask.strokeColor = .clear
        mask.isAntialiased = false
        crop.maskNode = mask
        crop.zPosition = 1
        root.addChild(crop)

        crop.addChild(sprite(
            color: UIColor(red: 12 / 255, green: 30 / 255, blue: 53 / 255, alpha: 1),
            frame: innerFrame,
            zPosition: 0
        ))
        crop.addChild(sprite(
            color: UIColor(red: 51 / 255, green: 68 / 255, blue: 93 / 255, alpha: 1),
            frame: CGRect(
                x: innerFrame.minX,
                y: innerFrame.maxY - innerFrame.height * 0.18,
                width: innerFrame.width,
                height: innerFrame.height * 0.18
            ),
            zPosition: 1
        ))
        crop.addChild(sprite(
            color: Palette.ink,
            frame: CGRect(
                x: innerFrame.minX,
                y: innerFrame.minY,
                width: innerFrame.width,
                height: innerFrame.height * 0.22
            ),
            zPosition: 1
        ))
        crop.addChild(sprite(
            color: UIColor(red: 98 / 255, green: 114 / 255, blue: 138 / 255, alpha: 1),
            frame: CGRect(
                x: innerFrame.minX,
                y: innerFrame.maxY - max(1, 2 * scale),
                width: innerFrame.width,
                height: max(1, 2 * scale)
            ),
            zPosition: 2
        ))

        iconNode.texture = textureLibrary.texture(iconPath)
        iconNode.size = CGSize(
            width: max(1, frame.width - max(6, 8 * scale)),
            height: max(1, frame.height - max(6, 8 * scale))
        )
        iconNode.position = CGPoint(x: frame.midX, y: frame.midY)
        iconNode.zPosition = 3
        root.addChild(iconNode)

        return root
    }

    private func setBonusActive(_ isActive: Bool) {
        goldFillNode.color = isActive ? Palette.meterGoldActive : Palette.meterGold
        redFillNode.color = isActive ? Palette.meterRedActive : Palette.meterRed
        meterActiveGlowNode.isHidden = !isActive

        meterActiveGlowNode.removeAction(forKey: "adrenalineFlash")
        meterCopyNode.removeAction(forKey: "adrenalineCopyFlash")
        meterActiveGlowNode.alpha = 1
        meterCopyNode.alpha = 1

        guard isActive, !reducedMotion else { return }

        let flash = SKAction.repeatForever(.sequence([
            .fadeAlpha(to: 0.55, duration: 0),
            .wait(forDuration: 0.24),
            .fadeAlpha(to: 1, duration: 0),
            .wait(forDuration: 0.24),
        ]))
        meterActiveGlowNode.run(flash, withKey: "adrenalineFlash")

        let copyFlash = SKAction.repeatForever(.sequence([
            .fadeAlpha(to: 0.70, duration: 0),
            .wait(forDuration: 0.24),
            .fadeAlpha(to: 1, duration: 0),
            .wait(forDuration: 0.24),
        ]))
        meterCopyNode.run(copyFlash, withKey: "adrenalineCopyFlash")
    }

    private func setTimerWarning(_ isWarning: Bool) {
        clockLabel.removeAction(forKey: "timerWarning")
        clockLabel.alpha = 1
        guard isWarning, !reducedMotion else { return }

        clockLabel.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.62, duration: 0),
            .wait(forDuration: 0.26),
            .fadeAlpha(to: 1, duration: 0),
            .wait(forDuration: 0.26),
        ])), withKey: "timerWarning")
    }

    private func updateFeedback(_ feedback: PlayFeedback?) {
        guard let feedback else {
            feedbackNode.isHidden = true
            feedbackNode.removeAction(forKey: Self.feedbackRevealActionKey)
            renderedFeedbackSignature = nil
            renderedFeedbackRemainingMilliseconds = nil
            renderedFeedbackFinalPosition = nil
            return
        }

        feedbackNode.isHidden = false
        let signature = [feedback.headline, feedback.detail, toneKey(feedback.tone)].joined(separator: "|")
        let lifetimeRestarted = signature == renderedFeedbackSignature &&
            feedback.remainingMilliseconds >
            (renderedFeedbackRemainingMilliseconds ?? feedback.remainingMilliseconds) + 0.5
        renderedFeedbackRemainingMilliseconds = feedback.remainingMilliseconds
        guard signature != renderedFeedbackSignature || lifetimeRestarted else { return }
        renderedFeedbackSignature = signature

        feedbackNode.removeAllActions()
        feedbackNode.removeAllChildren()
        feedbackNode.alpha = 1
        feedbackNode.setScale(1)

        let headlineColor: UIColor
        let semanticColor: UIColor
        switch feedback.tone {
        case .positive:
            headlineColor = Palette.positive
            semanticColor = Palette.positive
        case .touchdown, .bonus:
            headlineColor = Palette.gold
            semanticColor = Palette.gold
        case .negative:
            headlineColor = Palette.coral
            semanticColor = Palette.coral
        }

        let headline = ShadowedLabel(
            fontName: "AvenirNextCondensed-Heavy",
            fontSize: layout.feedbackHeadlineFontSize,
            color: headlineColor,
            outlineDistance: max(1 / layout.displayScale, 1.5 * scale)
        )
        headline.name = "scoreReaction.headline"
        headline.isAccessibilityElement = false
        headline.text = feedback.headline.uppercased()
        headline.horizontalAlignmentMode = .center
        headline.verticalAlignmentMode = .center

        let hasDetail = !feedback.detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let detail = ShadowedLabel(
            fontName: "AvenirNextCondensed-Heavy",
            fontSize: layout.feedbackDetailFontSize,
            color: Palette.cream,
            outlineDistance: max(1 / layout.displayScale, scale)
        )
        detail.name = "scoreReaction.detail"
        detail.isAccessibilityElement = false
        detail.text = feedback.detail
        detail.horizontalAlignmentMode = .center
        detail.verticalAlignmentMode = .center

        let panelFrame = layout.feedbackFrame(hasDetail: hasDetail)
        let localFrame = CGRect(
            x: -panelFrame.width / 2,
            y: -panelFrame.height / 2,
            width: panelFrame.width,
            height: panelFrame.height
        )
        let finalPosition = CGPoint(x: panelFrame.midX, y: panelFrame.midY)
        renderedFeedbackFinalPosition = finalPosition
        feedbackNode.position = finalPosition

        let renderedPoint = 1 / max(0.001, layout.displayScale)
        let shadowOffset = 3 * renderedPoint
        let shadowFrame = localFrame.offsetBy(dx: shadowOffset, dy: -shadowOffset)
        let shadow = SKShapeNode(
            path: pixelCutPath(in: shadowFrame, corner: max(2 * renderedPoint, 3 * scale))
        )
        shadow.name = "scoreReaction.shadow"
        shadow.fillColor = UIColor.black.withAlphaComponent(0.86)
        shadow.strokeColor = .clear
        shadow.zPosition = -5
        feedbackNode.addChild(shadow)

        let steelFrame = localFrame
        let steel = SKShapeNode(
            path: pixelCutPath(in: steelFrame, corner: max(2 * renderedPoint, 4 * scale))
        )
        steel.name = "scoreReaction.steel"
        steel.fillColor = Palette.steelDark
        steel.strokeColor = .clear
        steel.zPosition = -4
        feedbackNode.addChild(steel)

        let teamFrame = steelFrame.insetBy(dx: 1.5 * renderedPoint, dy: 1.5 * renderedPoint)
        let teamBorder = SKShapeNode(
            path: pixelCutPath(in: teamFrame, corner: max(1.5 * renderedPoint, 3 * scale))
        )
        teamBorder.name = "scoreReaction.teamBorder"
        teamBorder.fillColor = teamPrimary
        teamBorder.strokeColor = .clear
        teamBorder.zPosition = -3
        feedbackNode.addChild(teamBorder)

        let bodyFrame = teamFrame.insetBy(dx: 1.5 * renderedPoint, dy: 1.5 * renderedPoint)
        let body = SKShapeNode(
            path: pixelCutPath(in: bodyFrame, corner: max(renderedPoint, 2 * scale))
        )
        body.name = "scoreReaction.body"
        body.fillColor = Palette.scoreBase
        body.strokeColor = .clear
        body.zPosition = -2
        feedbackNode.addChild(body)

        let railFrame = bodyFrame.insetBy(
            dx: 2.5 * renderedPoint,
            dy: 2.5 * renderedPoint
        )
        let semanticRail = SKShapeNode(
            path: pixelCutPath(in: railFrame, corner: max(renderedPoint, 1.5 * scale))
        )
        semanticRail.name = "scoreReaction.semanticRail"
        semanticRail.fillColor = .clear
        semanticRail.strokeColor = semanticColor
        semanticRail.lineWidth = layout.feedbackInnerRailWidth
        semanticRail.isAntialiased = false
        semanticRail.zPosition = -1
        feedbackNode.addChild(semanticRail)

        let maxTextWidth = bodyFrame.width - layout.feedbackHorizontalTextPadding * 2
        if headline.contentWidth > maxTextWidth {
            headline.xScale = maxTextWidth / headline.contentWidth
        }
        if hasDetail, detail.contentWidth > maxTextWidth {
            detail.xScale = maxTextWidth / detail.contentWidth
        }

        if hasDetail {
            let rowGap = 1.5 * renderedPoint
            let blockHeight = headline.contentHeight + rowGap + detail.contentHeight
            headline.position = CGPoint(
                x: 0,
                y: blockHeight / 2 - headline.contentHeight / 2
            )
            detail.position = CGPoint(
                x: 0,
                y: -blockHeight / 2 + detail.contentHeight / 2
            )
            detail.zPosition = 0
            feedbackNode.addChild(detail)
        } else {
            headline.position = .zero
        }
        headline.zPosition = 0
        feedbackNode.addChild(headline)

        Self.excludeFromAccessibility(feedbackNode)
        feedbackAnnouncementHandler(Self.feedbackAnnouncementText(feedback))
        revealFeedback(from: finalPosition)
    }

    private static func excludeFromAccessibility(_ node: SKNode) {
        node.isAccessibilityElement = false
        node.children.forEach(excludeFromAccessibility)
    }

    static func feedbackAnnouncementText(_ feedback: PlayFeedback) -> String {
        let detail = feedback.detail
            .replacingOccurrences(of: "•", with: ",")
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
            .replacingOccurrences(of: " ,", with: ",")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return [feedback.headline, detail]
            .filter { !$0.isEmpty }
            .joined(separator: ". ")
    }

    private func revealFeedback(from finalPosition: CGPoint) {
        let motion = HUDFeedbackMotionSpec.resolved(
            reducedMotion: reducedMotion,
            displayScale: layout.displayScale
        )
        feedbackNode.alpha = 0
        feedbackNode.setScale(1)
        feedbackNode.position = CGPoint(
            x: finalPosition.x,
            y: finalPosition.y - motion.travel
        )

        let fade = SKAction.fadeAlpha(to: 1, duration: motion.duration)
        fade.timingMode = .easeOut
        if motion.usesTranslation {
            let move = SKAction.moveTo(y: finalPosition.y, duration: motion.duration)
            move.timingMode = .easeOut
            feedbackNode.run(
                .group([fade, move]),
                withKey: Self.feedbackRevealActionKey
            )
        } else {
            feedbackNode.run(fade, withKey: Self.feedbackRevealActionKey)
        }
    }

    private func settleCurrentFeedbackMotion() {
        guard let finalPosition = renderedFeedbackFinalPosition else { return }
        feedbackNode.removeAction(forKey: Self.feedbackRevealActionKey)
        feedbackNode.position = finalPosition
        feedbackNode.alpha = 1
        feedbackNode.setScale(1)
    }

    private func toneKey(_ tone: FeedbackState.Tone) -> String {
        switch tone {
        case .positive: return "positive"
        case .touchdown: return "touchdown"
        case .negative: return "negative"
        case .bonus: return "bonus"
        }
    }

    private func scoreBugPath(in frame: CGRect) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: frame.minX + frame.width * 0.09, y: frame.maxY))
        path.addLine(to: CGPoint(x: frame.maxX, y: frame.maxY))
        path.addLine(to: CGPoint(x: frame.maxX, y: frame.minY))
        path.addLine(to: CGPoint(x: frame.minX + frame.width * 0.04, y: frame.minY))
        path.addLine(to: CGPoint(x: frame.minX, y: frame.minY + frame.height * 0.24))
        path.addLine(to: CGPoint(x: frame.minX, y: frame.minY + frame.height * 0.76))
        path.closeSubpath()
        return path
    }

    static func controlPixelCutPath(in frame: CGRect, corner: CGFloat) -> CGPath {
        let c = min(corner, min(frame.width, frame.height) / 4)
        let half = c / 2
        let path = CGMutablePath()
        path.move(to: CGPoint(x: frame.minX + c, y: frame.maxY))
        path.addLine(to: CGPoint(x: frame.maxX - c, y: frame.maxY))
        path.addLine(to: CGPoint(x: frame.maxX - c, y: frame.maxY - half))
        path.addLine(to: CGPoint(x: frame.maxX, y: frame.maxY - half))
        path.addLine(to: CGPoint(x: frame.maxX, y: frame.minY + c))
        path.addLine(to: CGPoint(x: frame.maxX - half, y: frame.minY + c))
        path.addLine(to: CGPoint(x: frame.maxX - half, y: frame.minY))
        path.addLine(to: CGPoint(x: frame.minX + c, y: frame.minY))
        path.addLine(to: CGPoint(x: frame.minX + c, y: frame.minY + half))
        path.addLine(to: CGPoint(x: frame.minX, y: frame.minY + half))
        path.addLine(to: CGPoint(x: frame.minX, y: frame.maxY - c))
        path.addLine(to: CGPoint(x: frame.minX + half, y: frame.maxY - c))
        path.addLine(to: CGPoint(x: frame.minX + half, y: frame.maxY))
        path.closeSubpath()
        return path
    }

    private func pixelCutPath(in frame: CGRect, corner: CGFloat) -> CGPath {
        let c = min(corner, min(frame.width, frame.height) / 4)
        let half = c / 2
        let path = CGMutablePath()
        path.move(to: CGPoint(x: frame.minX + c, y: frame.maxY))
        path.addLine(to: CGPoint(x: frame.maxX - c, y: frame.maxY))
        path.addLine(to: CGPoint(x: frame.maxX - c, y: frame.maxY - half))
        path.addLine(to: CGPoint(x: frame.maxX, y: frame.maxY - half))
        path.addLine(to: CGPoint(x: frame.maxX, y: frame.minY + c))
        path.addLine(to: CGPoint(x: frame.maxX - half, y: frame.minY + c))
        path.addLine(to: CGPoint(x: frame.maxX - half, y: frame.minY))
        path.addLine(to: CGPoint(x: frame.minX + c, y: frame.minY))
        path.addLine(to: CGPoint(x: frame.minX + c, y: frame.minY + half))
        path.addLine(to: CGPoint(x: frame.minX, y: frame.minY + half))
        path.addLine(to: CGPoint(x: frame.minX, y: frame.minY + c))
        path.addLine(to: CGPoint(x: frame.minX + c, y: frame.minY + c))
        path.closeSubpath()
        return path
    }

    private func sprite(color: UIColor, frame: CGRect, zPosition: CGFloat) -> SKSpriteNode {
        let node = SKSpriteNode(color: color, size: frame.size)
        node.position = CGPoint(x: frame.midX, y: frame.midY)
        node.zPosition = zPosition
        return node
    }

    @MainActor
    private final class ShadowedLabel: SKNode {
        private let foreground: SKLabelNode
        private let shadows: [SKLabelNode]

        var text: String? {
            didSet {
                foreground.text = text
                shadows.forEach { $0.text = text }
            }
        }

        var color: UIColor {
            get { foreground.fontColor ?? .white }
            set { foreground.fontColor = newValue }
        }

        var horizontalAlignmentMode: SKLabelHorizontalAlignmentMode {
            get { foreground.horizontalAlignmentMode }
            set {
                foreground.horizontalAlignmentMode = newValue
                shadows.forEach { $0.horizontalAlignmentMode = newValue }
            }
        }

        var verticalAlignmentMode: SKLabelVerticalAlignmentMode {
            get { foreground.verticalAlignmentMode }
            set {
                foreground.verticalAlignmentMode = newValue
                shadows.forEach { $0.verticalAlignmentMode = newValue }
            }
        }

        var contentWidth: CGFloat { foreground.frame.width }
        var contentHeight: CGFloat { foreground.frame.height }

        init(
            fontName: String,
            fontSize: CGFloat,
            color: UIColor,
            outlineDistance: CGFloat,
            dropDistance: CGFloat? = nil
        ) {
            foreground = SKLabelNode(fontNamed: fontName)

            var offsets = [
                CGPoint(x: -outlineDistance, y: -outlineDistance),
                CGPoint(x: outlineDistance, y: -outlineDistance),
                CGPoint(x: -outlineDistance, y: outlineDistance),
                CGPoint(x: outlineDistance, y: outlineDistance),
            ]
            if let dropDistance {
                offsets.append(CGPoint(x: dropDistance, y: -dropDistance))
            }
            shadows = offsets.map { offset in
                let label = SKLabelNode(fontNamed: fontName)
                label.fontSize = fontSize
                label.fontColor = Palette.void
                label.position = offset
                return label
            }

            super.init()

            for shadow in shadows {
                shadow.zPosition = 0
                addChild(shadow)
            }
            foreground.fontSize = fontSize
            foreground.fontColor = color
            foreground.zPosition = 1
            addChild(foreground)
        }

        required init?(coder aDecoder: NSCoder) {
            fatalError("ShadowedLabel must be created programmatically")
        }
    }
}

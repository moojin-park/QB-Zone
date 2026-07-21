import CoreGraphics
import Foundation

/// Reference metrics for the browser game's broadcast HUD.
///
/// Values expressed as fractions follow the original CSS so that the HUD keeps
/// the same four anchors at any uniformly scaled 4:3 scene size. Point values
/// are measured in the canonical 1024 x 768 coordinate system and scale with
/// the scene.
struct HUDLayoutMetrics: Equatable {
    let adrenalineLeftFraction: CGFloat
    let adrenalineTopFraction: CGFloat
    let adrenalineWidthFraction: CGFloat
    let scoreRightFraction: CGFloat
    let scoreBottomFraction: CGFloat
    let scoreWidthFraction: CGFloat
    let scoreHeightFraction: CGFloat
    let controlsLeftFraction: CGFloat
    let controlsBottomFraction: CGFloat
    let controlSide: CGFloat

    static let canonical = HUDLayoutMetrics(
        adrenalineLeftFraction: 0.016,
        adrenalineTopFraction: 0.016,
        adrenalineWidthFraction: 0.38,
        scoreRightFraction: 0.014,
        scoreBottomFraction: 0.017,
        scoreWidthFraction: 0.305,
        scoreHeightFraction: 0.135,
        controlsLeftFraction: 0.014,
        controlsBottomFraction: 0.017,
        controlSide: 42
    )

    /// Matches the coarse-pointer, short-landscape media query in the web HUD.
    static let compact = HUDLayoutMetrics(
        adrenalineLeftFraction: 0.014,
        adrenalineTopFraction: 0.013,
        adrenalineWidthFraction: 0.40,
        scoreRightFraction: 0.014,
        scoreBottomFraction: 0.017,
        scoreWidthFraction: 0.31,
        scoreHeightFraction: 0.145,
        controlsLeftFraction: 0.014,
        controlsBottomFraction: 0.017,
        controlSide: 34
    )
}

struct HUDFeedbackMotionSpec: Equatable {
    let travel: CGFloat
    let duration: TimeInterval
    let usesTranslation: Bool
    let usesScale: Bool

    static func resolved(reducedMotion: Bool, displayScale: CGFloat) -> Self {
        if reducedMotion {
            return Self(
                travel: 0,
                duration: 0.08,
                usesTranslation: false,
                usesScale: false
            )
        }
        return Self(
            travel: 4 / max(0.001, displayScale),
            duration: 0.14,
            usesTranslation: true,
            usesScale: false
        )
    }
}

/// Pure SpriteKit-coordinate layout for the in-game HUD.
///
/// All returned rectangles use a bottom-left origin, matching `SKScene`.
struct HUDLayout: Equatable {
    static let referenceSize = CGSize(width: 1_024, height: 768)

    let sceneSize: CGSize
    let contentRect: CGRect
    let metrics: HUDLayoutMetrics
    let topObstructionHeight: CGFloat
    let topHUDOffset: CGFloat
    /// SpriteKit scene units to one rendered point in the containing view.
    ///
    /// The browser HUD uses CSS `clamp()` values, so its phone typography and
    /// controls do not simply shrink with the 1024 x 768 stage. Keeping this
    /// scale here lets the native HUD preserve those physical minimums while
    /// all anchors remain in SpriteKit coordinates.
    let displayScale: CGFloat
    let adrenalineFrame: CGRect
    let meterTrackFrame: CGRect
    let clockTopAnchor: CGPoint
    let muteButtonFrame: CGRect
    let pauseButtonFrame: CGRect
    let controlsFrame: CGRect
    let scorePlateFrame: CGRect
    let feedbackOneLineFrame: CGRect
    let feedbackTwoLineFrame: CGRect
    let feedbackAttachmentOverlap: CGFloat
    let feedbackInnerRailWidth: CGFloat
    let feedbackHorizontalTextPadding: CGFloat
    let feedbackHeadlineFontSize: CGFloat
    let feedbackDetailFontSize: CGFloat
    let meterHeadingAnchor: CGPoint
    let multiplierTopAnchor: CGPoint
    let readyCopyAnchor: CGPoint
    let pointsKickerAnchor: CGPoint
    let scoreValueAnchor: CGPoint
    let clockFontSize: CGFloat
    let scoreFontSize: CGFloat
    let pointsFontSize: CGFloat
    let meterTitleFontSize: CGFloat
    let meterActionFontSize: CGFloat
    let multiplierFontSize: CGFloat
    let readyCopyFontSize: CGFloat

    init(
        sceneSize: CGSize = HUDLayout.referenceSize,
        contentRect: CGRect? = nil,
        metrics: HUDLayoutMetrics = .canonical,
        displayScale: CGFloat? = nil,
        topObstructionHeight: CGFloat = 0
    ) {
        self.sceneSize = sceneSize
        let resolvedContentRect = contentRect ?? CGRect(origin: .zero, size: sceneSize)
        self.contentRect = resolvedContentRect
        self.metrics = metrics
        self.topObstructionHeight = max(0, topObstructionHeight)

        let safeTopInset = max(0, sceneSize.height - resolvedContentRect.maxY)
        let resolvedTopHUDOffset = max(0, self.topObstructionHeight - safeTopInset)
        topHUDOffset = min(resolvedContentRect.height, resolvedTopHUDOffset)

        let sceneScale = min(
            resolvedContentRect.width / Self.referenceSize.width,
            resolvedContentRect.height / Self.referenceSize.height
        )
        let resolvedDisplayScale = max(0.001, displayScale ?? (1 / sceneScale))
        self.displayScale = resolvedDisplayScale
        let renderedStageWidth = resolvedContentRect.width * resolvedDisplayScale
        func cssClamp(_ minimum: CGFloat, _ fluid: CGFloat, _ maximum: CGFloat) -> CGFloat {
            min(maximum, max(minimum, renderedStageWidth * fluid)) / resolvedDisplayScale
        }

        let meterTrackHeight = cssClamp(48, 0.074, 76)
        let titleSize = cssClamp(15, 0.0205, 21)
        let readySize = cssClamp(12, 0.0155, 16)
        let meterTrackTopInset = cssClamp(13, 0.017578125, 18)
        let readyCopyOverlap = 2.4 * sceneScale
        let readyCopyHeight = cssClamp(12, 0.015625, 16)
        let adrenalineHeight = meterTrackTopInset
            + meterTrackHeight
            - readyCopyOverlap
            + readyCopyHeight
        let adrenalineLeft = resolvedContentRect.minX
            + resolvedContentRect.width * metrics.adrenalineLeftFraction
        let adrenalineTop = topHUDOffset
            + resolvedContentRect.height * metrics.adrenalineTopFraction
        let adrenalineWidth = resolvedContentRect.width * metrics.adrenalineWidthFraction

        adrenalineFrame = Self.topLeftFrame(
            x: adrenalineLeft,
            top: adrenalineTop,
            width: adrenalineWidth,
            height: adrenalineHeight,
            topEdge: resolvedContentRect.maxY
        )
        meterTrackFrame = Self.topLeftFrame(
            x: adrenalineLeft,
            top: adrenalineTop + meterTrackTopInset,
            width: adrenalineWidth,
            height: meterTrackHeight,
            topEdge: resolvedContentRect.maxY
        )

        clockTopAnchor = CGPoint(
            x: resolvedContentRect.midX,
            y: resolvedContentRect.maxY
                - topHUDOffset
                - resolvedContentRect.height * 0.02
        )

        let controlsLeft = resolvedContentRect.minX
            + resolvedContentRect.width * metrics.controlsLeftFraction
        let controlsBottom = resolvedContentRect.minY
            + resolvedContentRect.height * metrics.controlsBottomFraction
        let controlSide = metrics == .compact
            ? cssClamp(28, 0.041, 34)
            : cssClamp(30, 0.0415, 42)
        let controlGap = cssClamp(4, 0.007, 8)
        muteButtonFrame = CGRect(
            x: controlsLeft,
            y: controlsBottom,
            width: controlSide,
            height: controlSide
        )
        pauseButtonFrame = CGRect(
            x: muteButtonFrame.maxX + controlGap,
            y: controlsBottom,
            width: controlSide,
            height: controlSide
        )
        controlsFrame = muteButtonFrame.union(pauseButtonFrame)

        let scoreWidth = resolvedContentRect.width * metrics.scoreWidthFraction
        let scoreHeight = resolvedContentRect.height * metrics.scoreHeightFraction
        let resolvedScorePlateFrame = CGRect(
            x: resolvedContentRect.maxX
                - resolvedContentRect.width * metrics.scoreRightFraction
                - scoreWidth,
            y: resolvedContentRect.minY
                + resolvedContentRect.height * metrics.scoreBottomFraction,
            width: scoreWidth,
            height: scoreHeight
        )
        scorePlateFrame = resolvedScorePlateFrame

        let feedbackRenderedMetrics: (
            width: CGFloat,
            oneLineHeight: CGFloat,
            twoLineHeight: CGFloat,
            headlineFontSize: CGFloat,
            detailFontSize: CGFloat,
            railWidth: CGFloat,
            horizontalTextPadding: CGFloat
        )
        if renderedStageWidth <= 740 {
            feedbackRenderedMetrics = (172, 32, 46, 15, 12, 2, 4)
        } else if renderedStageWidth >= 1_100 {
            feedbackRenderedMetrics = (316, 42, 56, 22, 16, 3, 9)
        } else {
            feedbackRenderedMetrics = (248, 34, 48, 18, 13, 2.5, 7)
        }

        let resolvedFeedbackAttachmentOverlap = 3 / resolvedDisplayScale
        feedbackAttachmentOverlap = resolvedFeedbackAttachmentOverlap
        feedbackInnerRailWidth = feedbackRenderedMetrics.railWidth / resolvedDisplayScale
        feedbackHorizontalTextPadding = feedbackRenderedMetrics.horizontalTextPadding
            / resolvedDisplayScale
        feedbackHeadlineFontSize = feedbackRenderedMetrics.headlineFontSize
            / resolvedDisplayScale
        feedbackDetailFontSize = feedbackRenderedMetrics.detailFontSize
            / resolvedDisplayScale

        func attachedFeedbackFrame(renderedHeight: CGFloat) -> CGRect {
            let width = min(
                resolvedContentRect.width,
                feedbackRenderedMetrics.width / resolvedDisplayScale
            )
            let height = min(
                resolvedContentRect.height,
                renderedHeight / resolvedDisplayScale
            )
            let centeredX = resolvedScorePlateFrame.midX - width / 2
            let x = min(
                max(resolvedContentRect.minX, centeredX),
                resolvedContentRect.maxX - width
            )
            let attachedY = resolvedScorePlateFrame.maxY - resolvedFeedbackAttachmentOverlap
            let y = min(
                max(resolvedContentRect.minY, attachedY),
                resolvedContentRect.maxY - height
            )
            return CGRect(x: x, y: y, width: width, height: height)
        }

        feedbackOneLineFrame = attachedFeedbackFrame(
            renderedHeight: feedbackRenderedMetrics.oneLineHeight
        )
        feedbackTwoLineFrame = attachedFeedbackFrame(
            renderedHeight: feedbackRenderedMetrics.twoLineHeight
        )
        meterHeadingAnchor = CGPoint(
            x: adrenalineFrame.minX + adrenalineFrame.width * 0.03,
            y: adrenalineFrame.maxY
        )
        multiplierTopAnchor = CGPoint(
            x: adrenalineFrame.minX + adrenalineFrame.width * 0.03,
            y: adrenalineFrame.maxY - cssClamp(25, 0.0315, 34)
        )
        readyCopyAnchor = CGPoint(
            x: adrenalineFrame.maxX - adrenalineFrame.width * 0.025,
            y: adrenalineFrame.minY + readyCopyHeight / 2
        )
        pointsKickerAnchor = CGPoint(
            x: scorePlateFrame.minX + scorePlateFrame.width * 0.45,
            y: scorePlateFrame.midY
        )
        scoreValueAnchor = CGPoint(
            x: scorePlateFrame.minX + scorePlateFrame.width * 0.54,
            y: scorePlateFrame.midY
        )

        clockFontSize = cssClamp(26, 0.042, 44)
        scoreFontSize = cssClamp(26, 0.049, 50)
        pointsFontSize = cssClamp(8, 0.0112, 12)
        meterTitleFontSize = titleSize
        meterActionFontSize = cssClamp(10, 0.013, 14)
        multiplierFontSize = cssClamp(18, 0.0255, 27)
        readyCopyFontSize = readySize
    }

    func feedbackFrame(hasDetail: Bool) -> CGRect {
        hasDetail ? feedbackTwoLineFrame : feedbackOneLineFrame
    }

    var meterMaskPath: CGPath {
        AdrenalineMeterGeometry.path(in: meterTrackFrame)
    }

    func meterFillFrame(progress: CGFloat) -> CGRect {
        AdrenalineMeterGeometry.fillFrame(in: meterTrackFrame, progress: progress)
    }

    var meterDividerXPositions: [CGFloat] {
        AdrenalineMeterGeometry.dividerXPositions(in: meterTrackFrame)
    }

    private static func topLeftFrame(
        x: CGFloat,
        top: CGFloat,
        width: CGFloat,
        height: CGFloat,
        topEdge: CGFloat
    ) -> CGRect {
        CGRect(x: x, y: topEdge - top - height, width: width, height: height)
    }
}

/// The exact 320 x 100 source outline used by the web Adrenaline meter mask.
enum AdrenalineMeterGeometry {
    enum PathCommand: Equatable {
        case move(CGPoint)
        case line(CGPoint)
        case curve(to: CGPoint, control1: CGPoint, control2: CGPoint)
        case close
    }

    static let sourceSize = CGSize(width: 320, height: 100)
    static let sourceCommands: [PathCommand] = [
        .move(CGPoint(x: 3, y: 87)),
        .curve(
            to: CGPoint(x: 190, y: 51),
            control1: CGPoint(x: 88, y: 90),
            control2: CGPoint(x: 155, y: 78)
        ),
        .curve(
            to: CGPoint(x: 317, y: 0),
            control1: CGPoint(x: 232, y: 29),
            control2: CGPoint(x: 276, y: 9)
        ),
        .line(CGPoint(x: 317, y: 83)),
        .curve(
            to: CGPoint(x: 190, y: 98),
            control1: CGPoint(x: 278, y: 91),
            control2: CGPoint(x: 234, y: 96)
        ),
        .curve(
            to: CGPoint(x: 3, y: 98),
            control1: CGPoint(x: 136, y: 100),
            control2: CGPoint(x: 74, y: 100)
        ),
        .close,
    ]

    static func path(in frame: CGRect) -> CGPath {
        let path = CGMutablePath()
        for command in sourceCommands {
            switch command {
            case let .move(point):
                path.move(to: transform(point, into: frame))
            case let .line(point):
                path.addLine(to: transform(point, into: frame))
            case let .curve(to, control1, control2):
                path.addCurve(
                    to: transform(to, into: frame),
                    control1: transform(control1, into: frame),
                    control2: transform(control2, into: frame)
                )
            case .close:
                path.closeSubpath()
            }
        }
        return path
    }

    static func fillFrame(in frame: CGRect, progress: CGFloat) -> CGRect {
        let clampedProgress = max(0, min(1, progress))
        return CGRect(
            x: frame.minX,
            y: frame.minY,
            width: frame.width * clampedProgress,
            height: frame.height
        )
    }

    static func dividerXPositions(in frame: CGRect) -> [CGFloat] {
        (1 ..< 10).map { frame.minX + frame.width * CGFloat($0) / 10 }
    }

    private static func transform(_ point: CGPoint, into frame: CGRect) -> CGPoint {
        CGPoint(
            x: frame.minX + point.x / sourceSize.width * frame.width,
            y: frame.maxY - point.y / sourceSize.height * frame.height
        )
    }
}

/// Text and state styling consumed by the HUD renderer.
struct HUDPresentation: Equatable {
    let isVisible: Bool
    let scoreText: String
    let clockText: String
    let multiplierText: String
    let meterProgress: CGFloat
    let isBonusActive: Bool
    let isTimerWarning: Bool

    init(state: GameState) {
        isVisible = state.phase == .playing || state.phase == .resolvingFinalBall
        scoreText = Self.formatScore(state.score)
        clockText = Self.formatClock(remainingMilliseconds: state.remainingMilliseconds)
        multiplierText = Self.formatMultiplier(streak: state.touchdownStreak)
        meterProgress = max(
            0,
            min(1, CGFloat(state.touchdownMeter) / CGFloat(ScoringConfig.meterMaximum))
        )
        isBonusActive = state.touchdownMeter >= ScoringConfig.meterMaximum
        isTimerWarning = isVisible && state.remainingMilliseconds <= 10_000
    }

    static func formatClock(remainingMilliseconds: CGFloat) -> String {
        let totalSeconds = max(0, Int(ceil(Double(remainingMilliseconds) / 1_000)))
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    static func formatScore(_ score: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        formatter.usesGroupingSeparator = true
        return formatter.string(from: NSNumber(value: score)) ?? String(score)
    }

    static func formatMultiplier(streak: Int) -> String {
        let multiplier = ScoringConfig.touchdownMultipliers[
            min(max(0, streak), ScoringConfig.touchdownMultipliers.count - 1)
        ]
        let value: String
        if multiplier.rounded() == multiplier {
            value = String(Int(multiplier))
        } else if (multiplier * 10).rounded() == multiplier * 10 {
            value = String(format: "%.1f", Double(multiplier))
        } else {
            value = String(format: "%.2f", Double(multiplier))
        }
        return "TD x\(value)"
    }
}

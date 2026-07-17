import CoreImage
import SwiftUI
import UIKit

@MainActor
struct MainMenuView: View {
    @Bindable var coordinator: AppCoordinator
    @State private var renderedScene: UIImage?
    @State private var renderedSceneKey = ""
    @State private var renderedSceneAssetName = ""

    private var team: TeamDescriptor {
        coordinator.selectedTeam ?? coordinator.catalog.teams[0]
    }

    private var identity: TeamVisualIdentity {
        LaunchVisualIdentityCatalog.approved.team(id: team.id)!
    }

    var body: some View {
        GeometryReader { geometry in
            let viewport = CGRect(origin: .zero, size: geometry.size)
            let metrics = MenuSceneMetrics.forViewport(geometry.size)
            let artRect = aspectFit(metrics.referenceSize, inside: viewport)
            let requestKey = renderKey(for: metrics)

            ZStack {
                conceptBackdrop(metrics: metrics, size: geometry.size)

                conceptScene(in: artRect, metrics: metrics, renderKey: requestKey)

                utilityCorner(insets: windowSafeAreaInsets)

                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityElement()
                    .accessibilityLabel("Pocket Vector main menu")
                    .accessibilityValue("Selected team \(team.displayName)")
                    .accessibilityAddTraits(.isHeader)
                    .accessibilitySortPriority(100)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(PocketVectorTheme.void)
            .task(id: requestKey) {
                let image = await ConceptSceneRenderer.shared.image(
                    sourceName: metrics.assetName,
                    primary: identity.palette.primary,
                    secondary: identity.palette.secondary,
                    accent: identity.palette.accent
                )
                guard !Task.isCancelled else { return }
                renderedScene = image
                renderedSceneKey = requestKey
                renderedSceneAssetName = metrics.assetName
            }
        }
        .ignoresSafeArea()
    }

    private func conceptBackdrop(metrics: MenuSceneMetrics, size: CGSize) -> some View {
        conceptImage(metrics: metrics, renderKey: renderKey(for: metrics))
            .resizable()
            .interpolation(.none)
            .antialiased(false)
            .scaledToFill()
            .frame(width: size.width, height: size.height)
            .clipped()
            .blur(radius: 18, opaque: true)
            .overlay(PocketVectorTheme.void.opacity(0.68))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func conceptScene(
        in artRect: CGRect,
        metrics: MenuSceneMetrics,
        renderKey: String
    ) -> some View {
        ZStack {
            conceptImage(metrics: metrics, renderKey: renderKey)
                .resizable()
                .interpolation(.none)
                .antialiased(false)
                .frame(width: artRect.width, height: artRect.height)
                .position(x: artRect.midX, y: artRect.midY)
                .accessibilityHidden(true)

            TeamAtmosphere(
                primary: Color(illuminatedConceptColor(
                    primary: identity.palette.primary,
                    secondary: identity.palette.secondary,
                    accent: identity.palette.accent
                )),
                secondary: Color(identity.palette.secondary)
            )
            .frame(frame: artRect)

            integratedTeamBanner(mirrored: false)
                .frame(frame: mapped(metrics.leftBanner, metrics: metrics, into: artRect))

            integratedTeamBanner(mirrored: true)
                .frame(frame: mapped(metrics.rightBanner, metrics: metrics, into: artRect))

            PersonalBestScoreboard(
                value: coordinator.state.personalBest.formatted(),
                color: Color(conceptAccent)
            )
            .frame(frame: mapped(metrics.personalBest, metrics: metrics, into: artRect))

            hotspot(
                label: "Play",
                hint: "Choose an offense and start a run",
                cornerRadius: 22,
                action: coordinator.showTeamSelection
            )
            .frame(frame: mapped(metrics.playHotspot, metrics: metrics, into: artRect))

            hotspot(
                label: "Team and Locker",
                cornerRadius: 14,
                action: coordinator.showLocker
            )
            .frame(frame: mapped(metrics.lockerHotspot, metrics: metrics, into: artRect))

            hotspot(
                label: "Leaderboard",
                cornerRadius: 14,
                action: {
                    Task { await coordinator.requestLeaderboard() }
                }
            )
            .frame(frame: mapped(metrics.leaderboardHotspot, metrics: metrics, into: artRect))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func conceptImage(metrics: MenuSceneMetrics, renderKey: String) -> Image {
        let image = renderedSceneKey == renderKey || renderedSceneAssetName == metrics.assetName
            ? renderedScene
            : UIImage(named: metrics.assetName)
        return Image(uiImage: image ?? UIImage())
    }

    private func integratedTeamBanner(mirrored: Bool) -> some View {
        IntegratedTeamBanner(
            team: team,
            identity: identity,
            mirrored: mirrored
        )
    }

    private func hotspot(
        label: String,
        hint: String? = nil,
        cornerRadius: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Color.clear
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
        .buttonStyle(
            ConceptHotspotButtonStyle(
                color: Color(conceptAccent),
                cornerRadius: cornerRadius
            )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityHint(hint ?? "Opens \(label)")
        .accessibilityAddTraits(.isButton)
    }

    private func utilityCorner(insets: EdgeInsets) -> some View {
        VStack(alignment: .trailing, spacing: 5) {
            CoinBalanceHUD(
                confirmed: coordinator.state.confirmedCoins,
                pending: coordinator.state.pendingCoins
            )

            VStack(spacing: 2) {
                MenuUtilityIcon(
                    imageName: "MenuAchievementIcon",
                    label: "Achievements",
                    reducedMotion: coordinator.state.settings.reducedMotion,
                    action: coordinator.showAchievements
                )

                MenuUtilityIcon(
                    imageName: "MenuStoreIcon",
                    label: "Store",
                    reducedMotion: coordinator.state.settings.reducedMotion,
                    action: coordinator.showCoinStore
                )

                MenuUtilityIcon(
                    imageName: "MenuSettingsIcon",
                    label: "Settings",
                    reducedMotion: coordinator.state.settings.reducedMotion,
                    action: coordinator.showSettings
                )
            }
        }
        .padding(.top, max(8, insets.top + 6))
        .padding(.trailing, max(8, insets.trailing + 6))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }

    private var conceptAccent: RGBColor {
        illuminatedConceptColor(
            primary: identity.palette.primary,
            secondary: identity.palette.secondary,
            accent: identity.palette.accent
        )
    }

    private var windowSafeAreaInsets: EdgeInsets {
        let insets = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .safeAreaInsets ?? .zero
        return EdgeInsets(
            top: insets.top,
            leading: insets.left,
            bottom: insets.bottom,
            trailing: insets.right
        )
    }

    private func renderKey(for metrics: MenuSceneMetrics) -> String {
        "\(metrics.assetName)-\(identity.palette.primary.hex)-\(identity.palette.secondary.hex)-\(identity.palette.accent.hex)"
    }

    private func mapped(
        _ source: CGRect,
        metrics: MenuSceneMetrics,
        into destination: CGRect
    ) -> CGRect {
        CGRect(
            x: destination.minX + source.minX / metrics.referenceSize.width * destination.width,
            y: destination.minY + source.minY / metrics.referenceSize.height * destination.height,
            width: source.width / metrics.referenceSize.width * destination.width,
            height: source.height / metrics.referenceSize.height * destination.height
        )
    }

    private func aspectFit(_ source: CGSize, inside destination: CGRect) -> CGRect {
        let scale = min(
            destination.width / source.width,
            destination.height / source.height
        )
        let size = CGSize(width: source.width * scale, height: source.height * scale)
        return CGRect(
            x: destination.midX - size.width / 2,
            y: destination.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}

private struct MenuSceneMetrics {
    let assetName: String
    let referenceSize: CGSize
    let leftBanner: CGRect
    let rightBanner: CGRect
    let personalBest: CGRect
    let playHotspot: CGRect
    let lockerHotspot: CGRect
    let leaderboardHotspot: CGRect

    static func forViewport(_ size: CGSize) -> Self {
        size.width / max(size.height, 1) < 1.7 ? .pad : .phone
    }

    static let phone = Self(
        assetName: "MenuConceptScene",
        referenceSize: CGSize(width: 1_847, height: 851),
        leftBanner: CGRect(x: 73, y: 151, width: 103, height: 172),
        rightBanner: CGRect(x: 1_661, y: 151, width: 110, height: 172),
        personalBest: CGRect(x: 1_575, y: 385, width: 190, height: 110),
        playHotspot: CGRect(x: 518, y: 366, width: 806, height: 262),
        lockerHotspot: CGRect(x: 281, y: 669, width: 389, height: 139),
        leaderboardHotspot: CGRect(x: 1_148, y: 669, width: 416, height: 140)
    )

    static let pad = Self(
        assetName: "MenuConceptScenePad",
        referenceSize: CGSize(width: 1_448, height: 1_086),
        leftBanner: CGRect(x: 54, y: 318, width: 93, height: 168),
        rightBanner: CGRect(x: 1_303, y: 318, width: 96, height: 168),
        personalBest: CGRect(x: 1_246, y: 488, width: 154, height: 89),
        playHotspot: CGRect(x: 406, y: 496, width: 634, height: 202),
        lockerHotspot: CGRect(x: 216, y: 736, width: 312, height: 108),
        leaderboardHotspot: CGRect(x: 902, y: 736, width: 326, height: 108)
    )
}

private struct TeamAtmosphere: View {
    let primary: Color
    let secondary: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RadialGradient(
                    colors: [primary.opacity(0.22), .clear],
                    center: .topLeading,
                    startRadius: 8,
                    endRadius: geometry.size.width * 0.68
                )

                RadialGradient(
                    colors: [secondary.opacity(0.20), .clear],
                    center: .topTrailing,
                    startRadius: 8,
                    endRadius: geometry.size.width * 0.60
                )
            }
            .blendMode(.screen)
            .mask {
                LinearGradient(
                    colors: [.white, .white.opacity(0.72), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct PersonalBestScoreboard: View {
    let value: String
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Image("MenuPersonalBest")
                    .resizable()
                    .interpolation(.none)
                    .antialiased(false)
                    .scaledToFit()

                Text(value)
                    .font(.system(size: geometry.size.height * 0.26, weight: .black, design: .monospaced))
                    .foregroundStyle(color)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.40)
                    .frame(
                        width: geometry.size.width * 0.34,
                        height: geometry.size.height * 0.28
                    )
                    .background(Color(red: 0.005, green: 0.018, blue: 0.038))
                    .position(
                        x: geometry.size.width * 0.50,
                        y: geometry.size.height * 0.61
                    )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Personal best")
        .accessibilityValue(value)
    }
}

private struct IntegratedTeamBanner: View {
    let team: TeamDescriptor
    let identity: TeamVisualIdentity
    let mirrored: Bool

    var body: some View {
        VStack(spacing: 2) {
            TeamMark(team: team, size: 36)
                .frame(maxHeight: .infinity)

            Text(identity.wordmark.marketLine)
            Text(identity.wordmark.nicknameLine)
                .foregroundStyle(Color(identity.palette.primary))
        }
        .font(.system(.caption2, design: .monospaced, weight: .black))
        .foregroundStyle(Color(identity.palette.accent))
        .lineLimit(1)
        .minimumScaleFactor(0.35)
        .padding(.horizontal, 5)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [
                    Color(identity.palette.secondary).opacity(0.46),
                    PocketVectorTheme.void.opacity(0.98),
                    PocketVectorTheme.void.opacity(0.98),
                ],
                startPoint: mirrored ? .topTrailing : .topLeading,
                endPoint: mirrored ? .bottomLeading : .bottomTrailing
            )
        )
        .overlay {
            Rectangle()
                .stroke(Color.white.opacity(0.34), lineWidth: 3)
                .padding(2)
        }
        .overlay {
            Rectangle()
                .stroke(Color(identity.palette.primary).opacity(0.78), lineWidth: 1)
                .padding(5)
        }
        .clipped()
        .accessibilityHidden(true)
    }
}

private struct CoinBalanceHUD: View {
    let confirmed: Int64
    let pending: Int64

    var body: some View {
        HStack(spacing: 5) {
            Image("MenuCoinIcon")
                .resizable()
                .interpolation(.none)
                .antialiased(false)
                .scaledToFit()
                .frame(width: 26, height: 26)

            Text(AppPresentation.coinText(confirmed))
                .font(.system(.headline, design: .monospaced, weight: .black))
                .foregroundStyle(PocketVectorTheme.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .allowsTightening(true)

            if pending > 0 {
                Text("+\(AppPresentation.coinText(pending))")
                    .font(.system(.caption2, design: .monospaced, weight: .black))
                    .foregroundStyle(PocketVectorTheme.gold)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
        }
        .shadow(color: .black, radius: 0, x: 2, y: 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Coin balance")
        .accessibilityValue(
            pending > 0
                ? "\(confirmed), plus \(pending) pending"
                : "\(confirmed)"
        )
    }
}

private struct MenuUtilityIcon: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let imageName: String
    let label: String
    let reducedMotion: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(imageName)
                .resizable()
                .interpolation(.none)
                .antialiased(false)
                .scaledToFit()
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(UtilityTileButtonStyle(reduceMotion: reduceMotion || reducedMotion))
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityHint("Opens \(label)")
    }
}

private struct UtilityTileButtonStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? 0.20 : 0)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

private struct ConceptHotspotButtonStyle: ButtonStyle {
    let color: Color
    let cornerRadius: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(configuration.isPressed ? color.opacity(0.22) : .clear)
                    .blendMode(.screen)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        configuration.isPressed ? color.opacity(0.78) : .clear,
                        lineWidth: 3
                    )
                    .padding(4)
            }
    }
}

private actor ConceptSceneRenderer {
    static let shared = ConceptSceneRenderer()

    private static let cubeDimension = 32
    private let context = CIContext(options: [.cacheIntermediates: true])
    private let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 4
        cache.totalCostLimit = 64 * 1_024 * 1_024
        return cache
    }()

    func image(
        sourceName: String,
        primary: RGBColor,
        secondary: RGBColor,
        accent: RGBColor
    ) -> UIImage? {
        let illuminatedPrimary = illuminatedConceptColor(
            primary: primary,
            secondary: secondary,
            accent: accent
        )
        let key = "\(sourceName)-\(illuminatedPrimary.hex)-\(secondary.hex)-\(accent.hex)" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        guard let source = UIImage(named: sourceName),
              let input = CIImage(image: source),
              let filter = CIFilter(name: "CIColorCube")
        else {
            return nil
        }

        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(Self.cubeDimension, forKey: "inputCubeDimension")
        filter.setValue(
            Self.colorCube(primary: illuminatedPrimary, secondary: secondary),
            forKey: "inputCubeData"
        )

        guard let recolored = filter.outputImage else {
            return nil
        }

        let output: CIImage
        if let mask = Self.protectedMask(
            sourceName: sourceName,
            width: Int(input.extent.width),
            height: Int(input.extent.height)
        ), let blend = CIFilter(name: "CIBlendWithMask") {
            blend.setValue(input, forKey: kCIInputImageKey)
            blend.setValue(recolored, forKey: kCIInputBackgroundImageKey)
            blend.setValue(mask, forKey: kCIInputMaskImageKey)
            output = blend.outputImage ?? recolored
        } else {
            output = recolored
        }

        guard
              let cgImage = context.createCGImage(output, from: input.extent)
        else {
            return nil
        }

        let image = UIImage(cgImage: cgImage, scale: source.scale, orientation: source.imageOrientation)
        cache.setObject(
            image,
            forKey: key,
            cost: cgImage.bytesPerRow * cgImage.height
        )
        return image
    }

    private static func colorCube(primary: RGBColor, secondary: RGBColor) -> Data {
        let primaryHSV = HSV(rgb: primary)
        let secondaryHSV = HSV(rgb: secondary)
        let maximum = CGFloat(cubeDimension - 1)
        var values = [Float]()
        values.reserveCapacity(cubeDimension * cubeDimension * cubeDimension * 4)

        for blueIndex in 0 ..< cubeDimension {
            for greenIndex in 0 ..< cubeDimension {
                for redIndex in 0 ..< cubeDimension {
                    let red = CGFloat(redIndex) / maximum
                    let green = CGFloat(greenIndex) / maximum
                    let blue = CGFloat(blueIndex) / maximum
                    let source = HSV(red: red, green: green, blue: blue)

                    let result: UIColor
                    if source.isConceptOrange {
                        result = UIColor(
                            hue: primaryHSV.hue,
                            saturation: max(0.42, primaryHSV.saturation * 0.95),
                            brightness: source.brightness,
                            alpha: 1
                        )
                    } else if source.isConceptNavy {
                        result = UIColor(
                            hue: secondaryHSV.hue,
                            saturation: max(0.12, secondaryHSV.saturation * 0.85),
                            brightness: source.brightness,
                            alpha: 1
                        )
                    } else {
                        result = UIColor(red: red, green: green, blue: blue, alpha: 1)
                    }

                    var outputRed: CGFloat = 0
                    var outputGreen: CGFloat = 0
                    var outputBlue: CGFloat = 0
                    var outputAlpha: CGFloat = 0
                    result.getRed(
                        &outputRed,
                        green: &outputGreen,
                        blue: &outputBlue,
                        alpha: &outputAlpha
                    )
                    values.append(Float(outputRed))
                    values.append(Float(outputGreen))
                    values.append(Float(outputBlue))
                    values.append(Float(outputAlpha))
                }
            }
        }

        return values.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    private static func protectedMask(
        sourceName: String,
        width: Int,
        height: Int
    ) -> CIImage? {
        let regions: [CGRect]
        if sourceName == "MenuConceptScenePad" {
            regions = [
                CGRect(x: 131, y: 441, width: 64, height: 68),
                CGRect(x: 252, y: 429, width: 42, height: 48),
                CGRect(x: 314, y: 480, width: 58, height: 62),
                CGRect(x: 1_116, y: 430, width: 45, height: 54),
                CGRect(x: 1_106, y: 474, width: 54, height: 67),
                CGRect(x: 1_198, y: 474, width: 60, height: 66),
            ]
        } else {
            regions = [
                CGRect(x: 177, y: 300, width: 70, height: 82),
                CGRect(x: 312, y: 285, width: 44, height: 55),
                CGRect(x: 417, y: 373, width: 70, height: 70),
                CGRect(x: 1_433, y: 279, width: 50, height: 61),
                CGRect(x: 1_417, y: 330, width: 61, height: 72),
                CGRect(x: 1_543, y: 365, width: 68, height: 74),
            ]
        }

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }

        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(gray: 1, alpha: 1)
        for region in regions {
            let quartzRegion = CGRect(
                x: region.minX,
                y: CGFloat(height) - region.maxY,
                width: region.width,
                height: region.height
            )
            context.fillEllipse(in: quartzRegion)
        }

        guard let cgImage = context.makeImage() else { return nil }
        return CIImage(cgImage: cgImage)
    }
}

private func illuminatedConceptColor(
    primary: RGBColor,
    secondary: RGBColor,
    accent: RGBColor
) -> RGBColor {
    let primaryHSV = HSV(rgb: primary)
    if primary.relativeLuminance >= 0.075, primaryHSV.saturation >= 0.35 {
        return primary
    }

    let secondaryHSV = HSV(rgb: secondary)
    let accentHSV = HSV(rgb: accent)
    return accentHSV.saturation >= secondaryHSV.saturation ? accent : secondary
}

private struct HSV {
    let hue: CGFloat
    let saturation: CGFloat
    let brightness: CGFloat

    init(rgb: RGBColor) {
        self.init(
            red: CGFloat(rgb.red) / 255,
            green: CGFloat(rgb.green) / 255,
            blue: CGFloat(rgb.blue) / 255
        )
    }

    init(red: CGFloat, green: CGFloat, blue: CGFloat) {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        UIColor(red: red, green: green, blue: blue, alpha: 1).getHue(
            &hue,
            saturation: &saturation,
            brightness: &brightness,
            alpha: &alpha
        )
        self.hue = hue
        self.saturation = saturation
        self.brightness = brightness
    }

    var isConceptOrange: Bool {
        (hue <= 0.17 || hue >= 0.98)
            && saturation > 0.20
            && brightness > 0.08
    }

    var isConceptNavy: Bool {
        (0.53 ... 0.76).contains(hue)
            && saturation > 0.28
            && brightness < 0.58
    }
}

private extension View {
    func frame(frame: CGRect) -> some View {
        self
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
    }
}

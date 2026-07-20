import SwiftUI

struct PocketVectorScreen<Content: View>: View {
    let title: String
    let subtitle: String?
    let showsBackButton: Bool
    let onBack: () -> Void
    @ViewBuilder let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        showsBackButton: Bool = true,
        onBack: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.showsBackButton = showsBackButton
        self.onBack = onBack
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                if showsBackButton {
                    Button(action: onBack) {
                        Label("Back", systemImage: "chevron.left")
                            .font(.headline)
                    }
                    .buttonStyle(.bordered)
                    .tint(PocketVectorTheme.cyan)
                    .accessibilityHint("Returns to the previous screen")
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.largeTitle.weight(.black))
                        .foregroundStyle(PocketVectorTheme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    if let subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(PocketVectorTheme.textSecondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 8)
            }
            .padding(.horizontal)
            .padding(.top, 8)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .foregroundStyle(PocketVectorTheme.textPrimary)
    }
}
struct BalanceBadge: View {
    let confirmedCoins: Int64
    let pendingCoins: Int64

    var body: some View {
        HStack(spacing: 7) {
            Image("MenuCoinIcon")
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
            Text(AppPresentation.coinText(confirmedCoins))
                .font(.system(.headline, design: .monospaced, weight: .black).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.68)
            if pendingCoins > 0 {
                Text("+\(AppPresentation.coinText(pendingCoins)) PENDING")
                    .font(.system(.caption2, design: .monospaced, weight: .bold))
                    .foregroundStyle(PocketVectorTheme.gold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.64)
            }
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 44)
        .background(
            PocketVectorTheme.championshipVoid.opacity(0.97),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(PocketVectorTheme.championshipSilver.opacity(0.86), lineWidth: 1.5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Coin balance")
        .accessibilityValue(
            pendingCoins > 0
                ? "\(confirmedCoins) available, \(pendingCoins) pending"
                : "\(confirmedCoins) available"
        )
    }
}

struct ChampionshipSubmenuScreen<HeaderAccessory: View, Content: View>: View {
    let title: String
    let subtitle: String?
    let showsBackButton: Bool
    let onBack: () -> Void
    @ViewBuilder let headerAccessory: HeaderAccessory
    @ViewBuilder let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        showsBackButton: Bool = true,
        onBack: @escaping () -> Void,
        @ViewBuilder headerAccessory: () -> HeaderAccessory,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.showsBackButton = showsBackButton
        self.onBack = onBack
        self.headerAccessory = headerAccessory()
        self.content = content()
    }

    var body: some View {
        GeometryReader { proxy in
            let compactHeight = proxy.size.height < 430
            let padLayout = proxy.size.width / max(proxy.size.height, 1) < 1.65
            let horizontalPadding: CGFloat = compactHeight ? 12 : (padLayout ? 22 : 18)
            let headerHeight: CGFloat = compactHeight ? 72 : (padLayout ? 132 : 88)
            let innerWidth = proxy.size.width - (horizontalPadding * 2)
            let sideWidth = compactHeight
                ? min(max(proxy.size.width * 0.23, 176), 220)
                : min(max(proxy.size.width * 0.18, 210), padLayout ? 280 : 250)
            let titleWidth = max(
                240,
                min(
                    proxy.size.width * (padLayout ? 0.62 : 0.58),
                    padLayout ? 720 : 760,
                    innerWidth - (sideWidth * 2) - 20
                )
            )

            ZStack {
                ChampionshipBackdrop()

                VStack(spacing: compactHeight ? 7 : 10) {
                    ZStack {
                        ChampionshipTitleMarquee(
                            title: title,
                            subtitle: subtitle,
                            compact: compactHeight,
                            expanded: padLayout
                        )
                        .frame(width: titleWidth, height: headerHeight)

                        HStack(spacing: 0) {
                            Group {
                                if showsBackButton {
                                    Button(action: onBack) {
                                        HStack(spacing: compactHeight ? 5 : 7) {
                                            ChampionshipPixelIcon(
                                                name: "SubmenuBackIcon",
                                                size: compactHeight ? 28 : (padLayout ? 40 : 32)
                                            )
                                            Text("BACK")
                                                .font(.system(
                                                    compactHeight ? .subheadline : (padLayout ? .title3 : .headline),
                                                    design: .monospaced,
                                                    weight: .black
                                                ))
                                                .tracking(0.5)
                                        }
                                    }
                                    .buttonStyle(ChampionshipBackButtonStyle(compact: compactHeight))
                                    .accessibilityHint("Returns to the previous screen")
                                    .accessibilitySortPriority(3)
                                } else {
                                    Color.clear
                                        .frame(height: headerHeight)
                                        .accessibilityHidden(true)
                                }
                            }
                            .frame(width: sideWidth, alignment: .leading)
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Color.clear
                                .frame(width: sideWidth, height: headerHeight)
                                .overlay(alignment: .trailing) {
                                    headerAccessory
                                }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: headerHeight)

                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, compactHeight ? 6 : 10)
                .padding(.bottom, compactHeight ? 7 : 11)
            }
        }
        .foregroundStyle(PocketVectorTheme.championshipGlacier)
    }
}

extension ChampionshipSubmenuScreen where HeaderAccessory == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        showsBackButton: Bool = true,
        onBack: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            showsBackButton: showsBackButton,
            onBack: onBack,
            headerAccessory: { EmptyView() },
            content: content
        )
    }
}

private struct ChampionshipTitleMarquee: View {
    let title: String
    let subtitle: String?
    let compact: Bool
    let expanded: Bool

    var body: some View {
        VStack(spacing: compact ? 1 : 3) {
            ZStack {
                Text(title.uppercased())
                    .foregroundStyle(.black.opacity(0.85))
                    .offset(x: 2, y: 3)
                    .accessibilityHidden(true)
                Text(title.uppercased())
                    .foregroundStyle(PocketVectorTheme.championshipGlacier)
            }
            .font(.system(
                size: expanded ? 46 : (compact ? 28 : 34),
                weight: .black,
                design: .monospaced
            ))
            .tracking(compact ? -1.0 : (expanded ? -0.3 : -0.6))
            .lineLimit(1)
            .minimumScaleFactor(0.62)

            if let subtitle {
                Text(subtitle)
                    .font(.system(
                        compact ? .caption2 : (expanded ? .subheadline : .caption),
                        design: .monospaced,
                        weight: .bold
                    ))
                    .foregroundStyle(PocketVectorTheme.championshipSilver)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .padding(.horizontal, compact ? 14 : (expanded ? 28 : 22))
        .padding(.vertical, compact ? 7 : (expanded ? 14 : 10))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .championshipPanel()
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(PocketVectorTheme.championshipGlacier.opacity(0.78))
                .frame(height: 1)
                .padding(.horizontal, 12)
                .padding(.bottom, 5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilitySortPriority(2)
    }
}

struct ChampionshipPixelIcon: View {
    let name: String
    var size: CGFloat

    var body: some View {
        Image(name)
            .resizable()
            .interpolation(.none)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct CoinAmount: View {
    let amount: Int64
    var iconSize: CGFloat = 22
    var font: Font = .subheadline.weight(.black).monospacedDigit()

    var body: some View {
        HStack(spacing: 5) {
            Image("MenuCoinIcon")
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .frame(width: iconSize, height: iconSize)
                .accessibilityHidden(true)
            Text(AppPresentation.coinText(amount))
                .font(font)
                .foregroundStyle(PocketVectorTheme.gold)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(amount) coins")
    }
}

struct ChampionshipSectionTitle: View {
    let title: String
    let iconName: String?

    init(_ title: String, iconName: String? = nil) {
        self.title = title
        self.iconName = iconName
    }

    var body: some View {
        HStack(spacing: 9) {
            if let iconName {
                ChampionshipPixelIcon(name: iconName, size: 30)
            }
            Text(title.uppercased())
                .font(.system(.headline, design: .monospaced, weight: .black))
                .tracking(0.8)
                .foregroundStyle(PocketVectorTheme.championshipGlacier)
            Spacer(minLength: 0)
        }
    }
}

private struct ChampionshipBackButtonStyle: ButtonStyle {
    let compact: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(PocketVectorTheme.championshipGlacier)
            .padding(.horizontal, compact ? 9 : 12)
            .frame(minHeight: compact ? 44 : 48)
            .background(
                PocketVectorTheme.championshipVoid.opacity(
                    configuration.isPressed ? 0.72 : 0.96
                ),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(PocketVectorTheme.championshipSilver, lineWidth: 1.5)
            }
            .shadow(color: .black.opacity(0.7), radius: 2, x: 0, y: 2)
    }
}

struct ChampionshipPrimaryButtonStyle: ButtonStyle {
    var compact: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(
                compact ? .headline : .title3,
                design: .monospaced,
                weight: .black
            ))
            .tracking(0.6)
            .foregroundStyle(PocketVectorTheme.championshipGlacier)
            .frame(maxWidth: .infinity)
            .frame(minHeight: compact ? 48 : 54)
            .padding(.horizontal, compact ? 12 : 18)
            .background(
                LinearGradient(
                    colors: configuration.isPressed
                        ? [PocketVectorTheme.championshipGraphite, PocketVectorTheme.championshipVoid]
                        : [PocketVectorTheme.championshipNavy, PocketVectorTheme.championshipVoid],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                in: RoundedRectangle(cornerRadius: 9)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .stroke(PocketVectorTheme.championshipGlacier, lineWidth: 2)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(PocketVectorTheme.championshipStatus.opacity(0.72), lineWidth: 1)
                    .padding(4)
            }
            .shadow(
                color: PocketVectorTheme.championshipStatus.opacity(configuration.isPressed ? 0.20 : 0.42),
                radius: configuration.isPressed ? 2 : 5
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

struct ChampionshipSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, design: .monospaced, weight: .bold))
            .foregroundStyle(PocketVectorTheme.championshipGlacier)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(
                PocketVectorTheme.championshipGraphite.opacity(
                    configuration.isPressed ? 0.72 : 0.96
                ),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(PocketVectorTheme.championshipSilver.opacity(0.82), lineWidth: 1.5)
            }
    }
}

struct TeamMark: View {
    let team: TeamDescriptor
    var size: CGFloat = 58

    private var identity: TeamVisualIdentity? {
        LaunchVisualIdentityCatalog.approved.team(id: team.id)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22)
                .fill(
                    LinearGradient(
                        colors: [PocketVectorTheme.void, PocketVectorTheme.raisedSurface],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            if let identity {
                TeamEmblemCanvas(identity: identity)
                    .padding(size * 0.10)
            }
        }
        .frame(width: size, height: size)
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.22)
                .stroke(Color(team.accentColor), lineWidth: 2)
        }
        .accessibilityHidden(true)
    }
}

private struct TeamEmblemCanvas: View {
    let identity: TeamVisualIdentity

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height)
            let origin = CGPoint(
                x: (size.width - scale) / 2,
                y: (size.height - scale) / 2
            )

            func point(_ unitPoint: UnitPoint2D) -> CGPoint {
                CGPoint(
                    x: origin.x + CGFloat(unitPoint.x) * scale,
                    y: origin.y + (1 - CGFloat(unitPoint.y)) * scale
                )
            }

            func color(_ role: BrandPaletteRole) -> Color {
                Color(identity.palette.color(for: role))
            }

            for primitive in identity.emblem.primitives {
                switch primitive {
                case let .disk(center, radius, fill):
                    let center = point(center)
                    let radius = CGFloat(radius) * scale
                    context.fill(
                        Path(ellipseIn: CGRect(
                            x: center.x - radius,
                            y: center.y - radius,
                            width: radius * 2,
                            height: radius * 2
                        )),
                        with: .color(color(fill))
                    )

                case let .ring(center, radius, lineWidth, role):
                    let center = point(center)
                    let radius = CGFloat(radius) * scale
                    context.stroke(
                        Path(ellipseIn: CGRect(
                            x: center.x - radius,
                            y: center.y - radius,
                            width: radius * 2,
                            height: radius * 2
                        )),
                        with: .color(color(role)),
                        style: StrokeStyle(lineWidth: CGFloat(lineWidth) * scale)
                    )

                case let .arc(center, radius, startDegrees, endDegrees, lineWidth, role):
                    var path = Path()
                    path.addArc(
                        center: point(center),
                        radius: CGFloat(radius) * scale,
                        startAngle: .degrees(-startDegrees),
                        endAngle: .degrees(-endDegrees),
                        clockwise: true
                    )
                    context.stroke(
                        path,
                        with: .color(color(role)),
                        style: StrokeStyle(
                            lineWidth: CGFloat(lineWidth) * scale,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )

                case let .polygon(vertices, fill):
                    guard let first = vertices.first else { continue }
                    var path = Path()
                    path.move(to: point(first))
                    vertices.dropFirst().forEach { path.addLine(to: point($0)) }
                    path.closeSubpath()
                    context.fill(path, with: .color(color(fill)))

                case let .polyline(vertices, lineWidth, role):
                    guard let first = vertices.first else { continue }
                    var path = Path()
                    path.move(to: point(first))
                    vertices.dropFirst().forEach { path.addLine(to: point($0)) }
                    context.stroke(
                        path,
                        with: .color(color(role)),
                        style: StrokeStyle(
                            lineWidth: CGFloat(lineWidth) * scale,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )

                case let .roundedBar(frame, cornerRadius, fill):
                    let rect = CGRect(
                        x: origin.x + CGFloat(frame.x) * scale,
                        y: origin.y + (1 - CGFloat(frame.y + frame.height)) * scale,
                        width: CGFloat(frame.width) * scale,
                        height: CGFloat(frame.height) * scale
                    )
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: CGFloat(cornerRadius) * scale),
                        with: .color(color(fill))
                    )
                }
            }
        }
    }
}

struct JerseyPreview: View {
    let jersey: JerseyDescriptor

    private var palette: UniformSpritePalette? {
        LaunchVisualIdentityCatalog.approved.uniform(
            teamID: jersey.teamID,
            jerseyID: jersey.id,
            role: .offense
        )
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [PocketVectorTheme.void, PocketVectorTheme.surface],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if let palette {
                Canvas { context, size in
                    let width = min(size.width * 0.64, size.height * 0.92)
                    let height = size.height * 0.78
                    let origin = CGPoint(
                        x: (size.width - width) / 2,
                        y: (size.height - height) / 2
                    )
                    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                        CGPoint(x: origin.x + x * width, y: origin.y + y * height)
                    }

                    var silhouette = Path()
                    silhouette.move(to: point(0.30, 0.08))
                    silhouette.addLine(to: point(0.15, 0.20))
                    silhouette.addLine(to: point(0.02, 0.44))
                    silhouette.addLine(to: point(0.21, 0.54))
                    silhouette.addLine(to: point(0.29, 0.43))
                    silhouette.addLine(to: point(0.25, 0.94))
                    silhouette.addLine(to: point(0.75, 0.94))
                    silhouette.addLine(to: point(0.71, 0.43))
                    silhouette.addLine(to: point(0.79, 0.54))
                    silhouette.addLine(to: point(0.98, 0.44))
                    silhouette.addLine(to: point(0.85, 0.20))
                    silhouette.addLine(to: point(0.70, 0.08))
                    silhouette.addQuadCurve(to: point(0.30, 0.08), control: point(0.50, 0.25))
                    silhouette.closeSubpath()
                    context.fill(silhouette, with: .color(Color(palette.jerseyBody)))
                    context.stroke(
                        silhouette,
                        with: .color(Color(palette.trim)),
                        style: StrokeStyle(lineWidth: max(2, width * 0.035), lineJoin: .round)
                    )

                    var shoulders = Path()
                    shoulders.move(to: point(0.20, 0.18))
                    shoulders.addLine(to: point(0.34, 0.10))
                    shoulders.addQuadCurve(to: point(0.50, 0.23), control: point(0.42, 0.24))
                    shoulders.addQuadCurve(to: point(0.66, 0.10), control: point(0.58, 0.24))
                    shoulders.addLine(to: point(0.80, 0.18))
                    shoulders.addLine(to: point(0.72, 0.34))
                    shoulders.addLine(to: point(0.28, 0.34))
                    shoulders.closeSubpath()
                    context.fill(shoulders, with: .color(Color(palette.shoulderPanel)))

                    let numberColor = Color(palette.numberAndName)
                    let numberWidth = max(3, width * 0.075)
                    context.fill(
                        Path(roundedRect: CGRect(
                            x: origin.x + width * 0.40,
                            y: origin.y + height * 0.43,
                            width: numberWidth,
                            height: height * 0.27
                        ), cornerRadius: numberWidth * 0.25),
                        with: .color(numberColor)
                    )
                    context.fill(
                        Path(roundedRect: CGRect(
                            x: origin.x + width * 0.54,
                            y: origin.y + height * 0.43,
                            width: numberWidth,
                            height: height * 0.27
                        ), cornerRadius: numberWidth * 0.25),
                        with: .color(numberColor)
                    )
                }
                .padding(.vertical, 3)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityHidden(true)
    }
}

struct FootballPreview: View {
    let footballID: FootballID

    private var style: FootballVisualStyle? {
        LaunchVisualIdentityCatalog.approved.football(id: footballID)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [PocketVectorTheme.void, PocketVectorTheme.surface],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if let style {
                Canvas { context, size in
                    let width = min(size.width * 0.66, size.height * 1.35)
                    let height = min(size.height * 0.62, width * 0.48)
                    let frame = CGRect(
                        x: (size.width - width) / 2,
                        y: (size.height - height) / 2,
                        width: width,
                        height: height
                    )
                    var body = Path()
                    body.move(to: CGPoint(x: frame.minX, y: frame.midY))
                    body.addCurve(
                        to: CGPoint(x: frame.maxX, y: frame.midY),
                        control1: CGPoint(x: frame.minX + width * 0.28, y: frame.minY),
                        control2: CGPoint(x: frame.maxX - width * 0.28, y: frame.minY)
                    )
                    body.addCurve(
                        to: CGPoint(x: frame.minX, y: frame.midY),
                        control1: CGPoint(x: frame.maxX - width * 0.28, y: frame.maxY),
                        control2: CGPoint(x: frame.minX + width * 0.28, y: frame.maxY)
                    )
                    body.closeSubpath()
                    context.fill(body, with: .color(Color(style.surface)))
                    context.stroke(
                        body,
                        with: .color(Color(style.seam)),
                        style: StrokeStyle(lineWidth: max(2, height * 0.08), lineJoin: .round)
                    )

                    var detail = Path()
                    switch style.panelTreatment {
                    case .orbitalSeam:
                        detail.addEllipse(in: frame.insetBy(dx: width * 0.22, dy: height * 0.12))
                    case .vectorArcBands:
                        detail.move(to: CGPoint(x: frame.minX + width * 0.18, y: frame.minY + height * 0.24))
                        detail.addQuadCurve(
                            to: CGPoint(x: frame.minX + width * 0.18, y: frame.maxY - height * 0.24),
                            control: CGPoint(x: frame.minX + width * 0.42, y: frame.midY)
                        )
                        detail.move(to: CGPoint(x: frame.maxX - width * 0.18, y: frame.minY + height * 0.24))
                        detail.addQuadCurve(
                            to: CGPoint(x: frame.maxX - width * 0.18, y: frame.maxY - height * 0.24),
                            control: CGPoint(x: frame.maxX - width * 0.42, y: frame.midY)
                        )
                    }
                    context.stroke(
                        detail,
                        with: .color(Color(style.detail)),
                        style: StrokeStyle(lineWidth: max(2, height * 0.07), lineCap: .round)
                    )

                    var laces = Path()
                    let laceWidth = width * 0.22
                    laces.move(to: CGPoint(x: frame.midX - laceWidth / 2, y: frame.midY))
                    laces.addLine(to: CGPoint(x: frame.midX + laceWidth / 2, y: frame.midY))
                    for index in -2 ... 2 {
                        let x = frame.midX + CGFloat(index) * laceWidth / 5
                        laces.move(to: CGPoint(x: x, y: frame.midY - height * 0.12))
                        laces.addLine(to: CGPoint(x: x, y: frame.midY + height * 0.12))
                    }
                    context.stroke(
                        laces,
                        with: .color(Color(style.laces)),
                        style: StrokeStyle(lineWidth: max(1.5, height * 0.055), lineCap: .round)
                    )
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityHidden(true)
    }
}

struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.black))
            .tracking(0.8)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .allowsTightening(true)
            .foregroundStyle(PocketVectorTheme.void)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color, in: Capsule())
    }
}

struct PrimaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.bold))
            .foregroundStyle(PocketVectorTheme.void)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                configuration.isPressed
                    ? PocketVectorTheme.cyan.opacity(0.78)
                    : PocketVectorTheme.cyan,
                in: RoundedRectangle(cornerRadius: 12)
            )
    }
}

struct MenuTile: View {
    let title: String
    let detail: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(PocketVectorTheme.cyan)
                    .frame(width: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(PocketVectorTheme.textPrimary)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(PocketVectorTheme.textSecondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .foregroundStyle(PocketVectorTheme.textSecondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .pocketVectorPanel()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

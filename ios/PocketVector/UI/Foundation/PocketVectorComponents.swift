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
            Image(systemName: "circle.hexagongrid.fill")
                .foregroundStyle(PocketVectorTheme.gold)
            Text(AppPresentation.coinText(confirmedCoins))
                .font(.headline.monospacedDigit())
            if pendingCoins > 0 {
                Text("+\(AppPresentation.coinText(pendingCoins)) pending")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PocketVectorTheme.warning)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(PocketVectorTheme.raisedSurface, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Coin balance")
        .accessibilityValue(
            pendingCoins > 0
                ? "\(confirmedCoins) available, \(pendingCoins) pending"
                : "\(confirmedCoins) available"
        )
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

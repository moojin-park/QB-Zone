import SwiftUI
import UIKit

@MainActor
struct MainMenuView: View {
    @Bindable var coordinator: AppCoordinator

    private var team: TeamDescriptor {
        coordinator.selectedTeam ?? coordinator.catalog.teams[0]
    }

    private var identity: TeamVisualIdentity {
        // The approved gameplay catalog and approved visual catalog are validated as one set.
        LaunchVisualIdentityCatalog.approved.team(id: team.id)!
    }

    private var selectedJerseyID: JerseyID {
        coordinator.state.selection.selectedJerseyByTeam[team.id] ?? team.primaryJersey.id
    }

    private var uniformPalette: UniformSpritePalette {
        LaunchVisualIdentityCatalog.approved.uniform(
            teamID: team.id,
            jerseyID: selectedJerseyID,
            role: .offense
        ) ?? identity.jerseys[0].offense
    }

    var body: some View {
        GeometryReader { geometry in
            let safeHeight = max(
                320,
                geometry.size.height
                    - geometry.safeAreaInsets.top
                    - geometry.safeAreaInsets.bottom
            )
            // Preserve the concept's wide marquee rhythm on taller iPads instead of
            // allowing flexible panels to consume the full 4:3 viewport height.
            let layoutHeight = min(
                safeHeight,
                max(320, geometry.size.width * 0.55)
            )
            let spacing = min(12, max(6, layoutHeight * 0.014))
            let headerHeight = min(190, max(102, layoutHeight * 0.27))
            let utilityHeight = min(62, max(44, layoutHeight * 0.072))
            let navigationHeight = min(124, max(72, layoutHeight * 0.17))
            let stageHeight = max(
                145,
                layoutHeight - headerHeight - utilityHeight - navigationHeight - spacing * 3
            )
            let contentHeight =
                headerHeight + stageHeight + utilityHeight + navigationHeight + spacing * 3

            ZStack {
                stadiumBackdrop(size: geometry.size)

                ScrollView(.vertical) {
                    VStack(spacing: spacing) {
                        menuHeader
                            .frame(height: headerHeight)

                        actionStage
                            .frame(height: stageHeight)

                        utilityNavigation
                            .frame(height: utilityHeight)

                        primaryNavigation
                            .frame(height: navigationHeight)
                    }
                    .frame(height: contentHeight)
                    .frame(minHeight: safeHeight)
                    .padding(.top, geometry.safeAreaInsets.top)
                    .padding(.bottom, geometry.safeAreaInsets.bottom)
                    .padding(.leading, max(12, geometry.safeAreaInsets.leading + 8))
                    .padding(.trailing, max(12, geometry.safeAreaInsets.trailing + 8))
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
    }

    private func stadiumBackdrop(size: CGSize) -> some View {
        let billboardWidth = min(118, max(82, size.width * 0.11))
        let billboardHeight = min(190, max(110, size.height * 0.32))

        return ZStack {
            Image("MenuStadium")
                .resizable()
                .interpolation(.none)
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .clipped()

            LinearGradient(
                colors: [
                    Color(identity.palette.primary).opacity(0.42),
                    .clear,
                    Color(identity.palette.secondary).opacity(0.48),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .blendMode(.color)

            HStack(spacing: 0) {
                RadialGradient(
                    colors: [
                        Color(identity.palette.primary).opacity(0.34),
                        .clear,
                    ],
                    center: .leading,
                    startRadius: 0,
                    endRadius: max(160, size.width * 0.48)
                )
                RadialGradient(
                    colors: [
                        Color(identity.palette.secondary).opacity(0.38),
                        .clear,
                    ],
                    center: .trailing,
                    startRadius: 0,
                    endRadius: max(160, size.width * 0.48)
                )
            }
            .blendMode(.screen)

            StadiumTeamBillboard(team: team, identity: identity)
                .frame(width: billboardWidth, height: billboardHeight)
                .position(x: size.width * 0.105, y: size.height * 0.46)

            StadiumTeamBillboard(team: team, identity: identity)
                .frame(width: billboardWidth, height: billboardHeight)
                .position(x: size.width * 0.895, y: size.height * 0.46)

            LinearGradient(
                colors: [
                    PocketVectorTheme.void.opacity(0.20),
                    .clear,
                    PocketVectorTheme.void.opacity(0.38),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            Canvas { context, canvasSize in
                let stripeColor = Color(identity.palette.primary).opacity(0.08)
                for y in stride(from: CGFloat(4), through: canvasSize.height, by: 8) {
                    context.fill(
                        Path(CGRect(x: 0, y: y, width: canvasSize.width, height: 1)),
                        with: .color(stripeColor)
                    )
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var menuHeader: some View {
        HStack(spacing: 8) {
            TeamStadiumBanner(team: team, identity: identity)
                .frame(maxWidth: 150)

            VStack(spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("POCKET")
                        .foregroundStyle(PocketVectorTheme.textPrimary)
                    Text("VECTOR")
                        .foregroundStyle(Color(identity.palette.primary))
                }
                .font(.system(.largeTitle, design: .rounded, weight: .black))
                .tracking(-1)
                .lineLimit(1)
                .minimumScaleFactor(0.46)
                .shadow(color: .black.opacity(0.88), radius: 0, x: 3, y: 3)

                Text("READ THE FIELD. FIRE THE PASS.")
                    .font(.system(.caption, design: .monospaced, weight: .black))
                    .tracking(1.25)
                    .foregroundStyle(Color(identity.palette.accent))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity)
                    .background(PocketVectorTheme.void.opacity(0.94), in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(Color(identity.palette.primary).opacity(0.85), lineWidth: 1)
                    }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .conceptPanel(primary: Color(identity.palette.primary), cornerRadius: 12)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Pocket Vector. Read the field. Fire the pass.")

            VStack(spacing: 7) {
                MenuStat(
                    label: "PERSONAL BEST",
                    value: coordinator.state.personalBest.formatted(),
                    color: Color(identity.palette.primary)
                )
                MenuStat(
                    label: "COINS",
                    value: AppPresentation.coinText(coordinator.state.confirmedCoins),
                    supplementalValue: coordinator.state.pendingCoins > 0
                        ? "+\(AppPresentation.coinText(coordinator.state.pendingCoins)) PENDING"
                        : nil,
                    color: PocketVectorTheme.gold
                )
            }
            .frame(maxWidth: 150)
        }
    }

    private var actionStage: some View {
        ZStack(alignment: .bottom) {
            HStack(alignment: .bottom, spacing: 0) {
                MenuUniformedCharacter(
                    relativePath: "characters/qb-aim.webp",
                    palette: uniformPalette,
                    role: .offense
                )
                .frame(maxWidth: 190, maxHeight: .infinity)

                Spacer(minLength: 180)

                MenuUniformedCharacter(
                    relativePath: "characters/receiver-touchdown-right.webp",
                    palette: uniformPalette,
                    role: .offense
                )
                .frame(maxWidth: 190, maxHeight: .infinity)
            }
            .padding(.horizontal, 4)

            VStack(spacing: 7) {
                TeamWordmarkPlate(identity: identity)

                Button {
                    coordinator.showTeamSelection()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "football.fill")
                            .font(.system(.title2, design: .rounded, weight: .black))
                        Text("PLAY")
                            .font(.system(.largeTitle, design: .rounded, weight: .black))
                            .tracking(1.5)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(
                    ConceptPlayButtonStyle(
                        primary: Color(identity.palette.primary),
                        secondary: Color(identity.palette.secondary),
                        foreground: identity.palette.primary.accessibleForegroundColor
                    )
                )
                .accessibilityLabel("Play")
                .accessibilityHint("Choose an offense and start a run")
            }
            .frame(maxWidth: 610, maxHeight: .infinity)
            .padding(.horizontal, 124)
            .padding(.vertical, 4)
        }
    }

    private var utilityNavigation: some View {
        HStack(spacing: 8) {
            CompactMenuAction(
                title: "Coin Store",
                systemImage: "circle.hexagongrid.fill",
                color: PocketVectorTheme.gold,
                action: coordinator.showCoinStore
            )
            CompactMenuAction(
                title: "Settings",
                systemImage: "gearshape.fill",
                color: Color(identity.palette.primary),
                action: coordinator.showSettings
            )
            CompactMenuAction(
                title: "Privacy & Support",
                systemImage: "hand.raised.fill",
                color: Color(identity.palette.accent),
                action: coordinator.showPrivacySupport
            )
        }
    }

    private var primaryNavigation: some View {
        HStack(spacing: 9) {
            ConceptMenuAction(
                title: "Team & Locker",
                systemImage: "tshirt.fill",
                color: Color(identity.palette.primary),
                action: coordinator.showLocker
            )
            ConceptMenuAction(
                title: "Achievements",
                systemImage: "trophy.fill",
                color: PocketVectorTheme.gold,
                action: coordinator.showAchievements
            )
            ConceptMenuAction(
                title: "Leaderboard",
                systemImage: "chart.bar.fill",
                color: Color(identity.palette.primary),
                action: {
                    Task { await coordinator.requestLeaderboard() }
                }
            )
        }
    }
}

private struct TeamStadiumBanner: View {
    let team: TeamDescriptor
    let identity: TeamVisualIdentity

    var body: some View {
        VStack(spacing: 5) {
            TeamMark(team: team, size: 48)

            Text(identity.wordmark.marketLine)
                .font(.system(.caption2, design: .monospaced, weight: .bold))
                .foregroundStyle(Color(identity.palette.accent))
            Text(identity.wordmark.nicknameLine)
                .font(.system(.headline, design: .rounded, weight: .black))
                .foregroundStyle(Color(identity.palette.primary))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.58)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            LinearGradient(
                colors: [
                    Color(identity.palette.secondary).opacity(0.92),
                    PocketVectorTheme.void.opacity(0.96),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(identity.palette.primary), lineWidth: 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Selected team")
        .accessibilityValue(team.displayName)
    }
}

private struct StadiumTeamBillboard: View {
    let team: TeamDescriptor
    let identity: TeamVisualIdentity

    var body: some View {
        VStack(spacing: 4) {
            TeamMark(team: team, size: 34)

            Text(identity.wordmark.marketLine)
                .font(.system(.caption2, design: .monospaced, weight: .bold))
                .foregroundStyle(Color(identity.palette.accent))

            Text(identity.wordmark.nicknameLine)
                .font(.system(.caption, design: .rounded, weight: .black))
                .foregroundStyle(Color(identity.palette.primary))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(7)
        .background(
            LinearGradient(
                colors: [
                    Color(identity.palette.secondary).opacity(0.90),
                    PocketVectorTheme.void.opacity(0.92),
                ],
                startPoint: .top,
                endPoint: .bottom
            ),
            in: RoundedRectangle(cornerRadius: 7)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color(identity.palette.primary).opacity(0.96), lineWidth: 2)
        }
        .shadow(color: .black.opacity(0.75), radius: 0, x: 0, y: 4)
    }
}

private struct TeamWordmarkPlate: View {
    let identity: TeamVisualIdentity

    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(Color(identity.palette.primary))
                .frame(width: 22, height: 3)
            Text(identity.wordmark.marketLine)
                .foregroundStyle(Color(identity.palette.accent))
            Text(identity.wordmark.nicknameLine)
                .foregroundStyle(Color(identity.palette.primary))
            Rectangle()
                .fill(Color(identity.palette.primary))
                .frame(width: 22, height: 3)
        }
        .font(.system(.caption, design: .monospaced, weight: .black))
        .tracking(0.8)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(PocketVectorTheme.void.opacity(0.94), in: Capsule())
        .overlay {
            Capsule().stroke(Color(identity.palette.primary).opacity(0.8), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

private struct MenuStat: View {
    let label: String
    let value: String
    var supplementalValue: String? = nil
    let color: Color

    var body: some View {
        VStack(spacing: 1) {
            Text(label)
                .font(.system(.caption2, design: .monospaced, weight: .black))
                .foregroundStyle(PocketVectorTheme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            HStack(spacing: 4) {
                Text(value)
                    .font(.system(.title3, design: .monospaced, weight: .black))
                    .foregroundStyle(color)
                    .monospacedDigit()

                if let supplementalValue {
                    Text(supplementalValue)
                        .font(.system(.caption2, design: .monospaced, weight: .bold))
                        .foregroundStyle(PocketVectorTheme.textSecondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.52)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(PocketVectorTheme.void.opacity(0.93), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(color.opacity(0.82), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ConceptMenuAction: View {
    let title: String
    let systemImage: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(.title2, design: .rounded, weight: .black))
                    .foregroundStyle(color)
                    .frame(minWidth: 34)

                Text(title.uppercased())
                    .font(.system(.subheadline, design: .rounded, weight: .black))
                    .foregroundStyle(PocketVectorTheme.textPrimary)
                    .lineLimit(1)
                    .allowsTightening(true)
                    .minimumScaleFactor(0.52)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 2)
            }
            .padding(.horizontal, 13)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .conceptPanel(primary: color, cornerRadius: 11)
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 11))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
    }
}

private struct CompactMenuAction: View {
    let title: String
    let systemImage: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(color)
                Text(title)
                    .foregroundStyle(PocketVectorTheme.textPrimary)
            }
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.68)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(PocketVectorTheme.void.opacity(0.90), in: Capsule())
                .overlay {
                    Capsule().stroke(color.opacity(0.92), lineWidth: 1.5)
                }
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
        .accessibilityLabel(title)
    }
}

private struct ConceptPlayButtonStyle: ButtonStyle {
    let primary: Color
    let secondary: Color
    let foreground: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foreground)
            .background(
                configuration.isPressed ? primary.opacity(0.78) : primary,
                in: RoundedRectangle(cornerRadius: 14)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(PocketVectorTheme.textPrimary.opacity(0.88), lineWidth: 3)
                    .padding(4)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(secondary.opacity(0.95), lineWidth: 7)
            }
            .shadow(color: .black.opacity(0.88), radius: 0, x: 0, y: 6)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

private struct ConceptPanelModifier: ViewModifier {
    let primary: Color
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                PocketVectorTheme.void.opacity(0.94),
                in: RoundedRectangle(cornerRadius: cornerRadius)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(PocketVectorTheme.textSecondary.opacity(0.72), lineWidth: 3)
            }
            .overlay {
                RoundedRectangle(cornerRadius: max(2, cornerRadius - 4))
                    .stroke(primary.opacity(0.92), lineWidth: 2)
                    .padding(4)
            }
            .shadow(color: .black.opacity(0.90), radius: 0, x: 0, y: 5)
    }
}

private extension View {
    func conceptPanel(primary: Color, cornerRadius: CGFloat) -> some View {
        modifier(ConceptPanelModifier(primary: primary, cornerRadius: cornerRadius))
    }
}

private struct MenuCharacterLoadID: Hashable {
    let relativePath: String
    let palette: UniformSpritePalette
    let role: UniformSquadRole
}

private struct MenuUniformedCharacter: View {
    let relativePath: String
    let palette: UniformSpritePalette
    let role: UniformSquadRole

    @State private var renderedImage: UIImage?

    private var loadID: MenuCharacterLoadID {
        MenuCharacterLoadID(
            relativePath: relativePath,
            palette: palette,
            role: role
        )
    }

    var body: some View {
        Group {
            if let renderedImage {
                Image(uiImage: renderedImage)
                    .resizable()
                    .interpolation(.none)
                    .antialiased(false)
                    .scaledToFit()
            } else {
                Color.clear
            }
        }
        .accessibilityHidden(true)
        .task(id: loadID) {
            renderedImage = nil
            let request = UniformTexturePreparationRequest(
                relativePath: relativePath,
                cacheKey: UniformTextureCacheKey(
                    relativePath: relativePath,
                    palette: palette,
                    role: role
                ),
                palette: palette,
                role: role
            )
            guard let prepared = await UniformRasterPreprocessor.prepare([request]).first,
                  !Task.isCancelled
            else {
                return
            }
            renderedImage = makeImage(from: prepared)
        }
    }

    private func makeImage(from prepared: PreparedUniformTexture) -> UIImage? {
        guard let provider = CGDataProvider(data: prepared.rgbaData as CFData),
              let cgImage = CGImage(
                  width: prepared.width,
                  height: prepared.height,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: prepared.bytesPerRow,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo.byteOrder32Big.union(
                      CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
                  ),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: false,
                  intent: .defaultIntent
              )
        else {
            return nil
        }
        return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
    }
}

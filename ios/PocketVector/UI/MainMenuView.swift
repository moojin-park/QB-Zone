import SwiftUI
import UIKit

@MainActor
struct MainMenuView: View {
    @Bindable var coordinator: AppCoordinator

    private var team: TeamDescriptor {
        coordinator.selectedTeam ?? coordinator.catalog.teams[0]
    }

    var body: some View {
        GeometryReader { geometry in
            let viewport = CGRect(origin: .zero, size: geometry.size)
            let metrics = MenuSceneMetrics.forViewport(geometry.size)
            let artRect = aspectFit(metrics.referenceSize, inside: viewport)

            ZStack {
                conceptBackdrop(metrics: metrics, size: geometry.size)

                conceptScene(in: artRect, metrics: metrics)

                coinCorner(insets: windowSafeAreaInsets)

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
        }
        .ignoresSafeArea()
    }

    private func conceptBackdrop(metrics: MenuSceneMetrics, size: CGSize) -> some View {
        Image(metrics.assetName)
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
        metrics: MenuSceneMetrics
    ) -> some View {
        ZStack {
            Image(metrics.assetName)
                .resizable()
                .interpolation(.none)
                .antialiased(false)
                .frame(width: artRect.width, height: artRect.height)
                .position(x: artRect.midX, y: artRect.midY)
                .accessibilityHidden(true)

            PersonalBestScoreboard(
                value: coordinator.state.personalBest.formatted(),
                color: highMesaEmber
            )
            .frame(frame: mapped(metrics.personalBest, metrics: metrics, into: artRect))

            utilityRow(metrics: metrics)
                .position(mapped(metrics.utilityRowCenter, metrics: metrics, into: artRect))

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
                color: highMesaEmber,
                cornerRadius: cornerRadius
            )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityHint(hint ?? "Opens \(label)")
        .accessibilityAddTraits(.isButton)
    }

    private func utilityRow(metrics: MenuSceneMetrics) -> some View {
        HStack(spacing: metrics.utilitySpacing) {
            MenuUtilityIcon(
                imageName: "MenuAchievementIcon",
                label: "Achievements",
                artworkSize: metrics.utilityIconSize,
                targetSize: metrics.utilityTargetSize,
                artworkOffsetY: metrics.utilityIconOffsetY,
                reducedMotion: coordinator.state.settings.reducedMotion,
                action: coordinator.showAchievements
            )

            MenuUtilityIcon(
                imageName: "MenuStoreIcon",
                label: "Store",
                artworkSize: metrics.utilityIconSize,
                targetSize: metrics.utilityTargetSize,
                artworkOffsetY: metrics.utilityIconOffsetY,
                reducedMotion: coordinator.state.settings.reducedMotion,
                action: coordinator.showCoinStore
            )

            MenuUtilityIcon(
                imageName: "MenuSettingsIcon",
                label: "Settings",
                artworkSize: metrics.utilityIconSize,
                targetSize: metrics.utilityTargetSize,
                artworkOffsetY: metrics.utilityIconOffsetY,
                reducedMotion: coordinator.state.settings.reducedMotion,
                action: coordinator.showSettings
            )
        }
    }

    private func coinCorner(insets: EdgeInsets) -> some View {
        CoinBalanceHUD(
            confirmed: coordinator.state.confirmedCoins,
            pending: coordinator.state.pendingCoins
        )
        .padding(.top, max(8, insets.top + 6))
        .padding(.leading, max(8, insets.leading + 6))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var highMesaEmber: Color {
        Color(red: 240 / 255.0, green: 106 / 255.0, blue: 59 / 255.0)
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

    private func mapped(
        _ source: CGPoint,
        metrics: MenuSceneMetrics,
        into destination: CGRect
    ) -> CGPoint {
        CGPoint(
            x: destination.minX + source.x / metrics.referenceSize.width * destination.width,
            y: destination.minY + source.y / metrics.referenceSize.height * destination.height
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
    let personalBest: CGRect
    let utilityRowCenter: CGPoint
    let utilityIconSize: CGFloat
    let utilityTargetSize: CGFloat
    let utilitySpacing: CGFloat
    let utilityIconOffsetY: CGFloat
    let playHotspot: CGRect
    let lockerHotspot: CGRect
    let leaderboardHotspot: CGRect

    static func forViewport(_ size: CGSize) -> Self {
        size.width / max(size.height, 1) < 1.7 ? .pad : .phone
    }

    static let phone = Self(
        assetName: "MenuHighMesaScenePhone",
        referenceSize: CGSize(width: 1_847, height: 851),
        personalBest: CGRect(x: 793.5, y: 618, width: 260, height: 150),
        utilityRowCenter: CGPoint(x: 923.5, y: 758),
        utilityIconSize: 24,
        utilityTargetSize: 44,
        utilitySpacing: 4,
        utilityIconOffsetY: 10,
        playHotspot: CGRect(x: 518, y: 366, width: 806, height: 262),
        lockerHotspot: CGRect(x: 281, y: 669, width: 389, height: 139),
        leaderboardHotspot: CGRect(x: 1_148, y: 669, width: 416, height: 140)
    )

    static let pad = Self(
        assetName: "MenuHighMesaScenePad",
        referenceSize: CGSize(width: 1_448, height: 1_086),
        personalBest: CGRect(x: 604, y: 721, width: 240, height: 139),
        utilityRowCenter: CGPoint(x: 724, y: 888),
        utilityIconSize: 36,
        utilityTargetSize: 52,
        utilitySpacing: 6,
        utilityIconOffsetY: 0,
        playHotspot: CGRect(x: 406, y: 496, width: 634, height: 202),
        lockerHotspot: CGRect(x: 216, y: 736, width: 312, height: 108),
        leaderboardHotspot: CGRect(x: 902, y: 736, width: 326, height: 108)
    )
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
        .padding(.horizontal, 8)
        .frame(minHeight: 44)
        .background {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(red: 0.005, green: 0.018, blue: 0.038).opacity(0.94))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.black, lineWidth: 3)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 2)
                .stroke(Color(red: 240 / 255.0, green: 106 / 255.0, blue: 59 / 255.0), lineWidth: 1)
                .padding(3)
        }
        .shadow(color: .black.opacity(0.88), radius: 0, x: 2, y: 2)
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
    let artworkSize: CGFloat
    let targetSize: CGFloat
    let artworkOffsetY: CGFloat
    let reducedMotion: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(imageName)
                .resizable()
                .interpolation(.none)
                .antialiased(false)
                .scaledToFit()
                .frame(width: artworkSize, height: artworkSize)
                .offset(y: artworkOffsetY)
                .contentShape(Rectangle())
        }
        .buttonStyle(UtilityTileButtonStyle(reduceMotion: reduceMotion || reducedMotion))
        .frame(width: targetSize, height: targetSize)
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

private extension View {
    func frame(frame: CGRect) -> some View {
        self
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
    }
}

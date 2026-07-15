import SpriteKit
import SwiftUI

@MainActor
struct GameRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    private let scene: GameScene

    init() {
        let scene = GameScene(size: GameProjection.sceneSize)
        scene.scaleMode = .aspectFit
        self.scene = scene
    }

    var body: some View {
        SpriteView(
            scene: scene,
            preferredFramesPerSecond: 60,
            options: [.ignoresSiblingOrder]
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CabinetPalette.midnight)
        .ignoresSafeArea()
        .background(CabinetPalette.void.ignoresSafeArea())
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onChange(of: scenePhase) { _, newPhase in
            scene.setApplicationActive(newPhase == .active)
        }
    }
}

private struct CabinetBackdrop: View {
    var body: some View {
        ZStack {
            CabinetPalette.void

            Canvas { context, size in
                for y in stride(from: CGFloat(6), through: size.height, by: 8) {
                    context.fill(
                        Path(CGRect(x: 0, y: y, width: size.width, height: 2)),
                        with: .color(Color(red: 22 / 255, green: 59 / 255, blue: 92 / 255).opacity(0.16))
                    )
                }

                for x in stride(from: CGFloat(14), through: size.width, by: 16) {
                    context.fill(
                        Path(CGRect(x: x, y: 0, width: 2, height: size.height)),
                        with: .color(Color(red: 5 / 255, green: 20 / 255, blue: 38 / 255).opacity(0.72))
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct CabinetShell: View {
    let stageWidth: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let sideSpace = max(0, (size.width - stageWidth) / 2)
            let railInset = max(6, size.width * 0.01)
            let railWidth = min(size.width * 0.08, max(0, sideSpace - railInset - 6))
            let railHeight = size.height * 0.84

            ZStack {
                LinearGradient(
                    stops: [
                        .init(color: CabinetPalette.steelDark, location: 0),
                        .init(color: CabinetPalette.steelDark, location: 0.02),
                        .init(color: CabinetPalette.navy, location: 0.02),
                        .init(color: CabinetPalette.navy, location: 0.09),
                        .init(color: CabinetPalette.ink, location: 0.09),
                        .init(color: CabinetPalette.ink, location: 0.91),
                        .init(color: CabinetPalette.navy, location: 0.91),
                        .init(color: CabinetPalette.navy, location: 0.98),
                        .init(color: CabinetPalette.steelDark, location: 0.98),
                        .init(color: CabinetPalette.steelDark, location: 1),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                CabinetShellScanlines()

                if railWidth >= 12 {
                    CabinetRail(side: .left)
                        .frame(width: railWidth, height: railHeight)
                        .position(x: railInset + (railWidth / 2), y: size.height / 2)

                    CabinetRail(side: .right)
                        .frame(width: railWidth, height: railHeight)
                        .position(x: size.width - railInset - (railWidth / 2), y: size.height / 2)
                }

                if sideSpace >= 4 {
                    CabinetStageEdge()
                        .frame(width: 4, height: size.height)
                        .position(x: sideSpace - 2, y: size.height / 2)

                    CabinetStageEdge()
                        .frame(width: 4, height: size.height)
                        .scaleEffect(x: -1, y: 1)
                        .position(x: size.width - sideSpace + 2, y: size.height / 2)
                }
            }
            .overlay {
                Rectangle()
                    .stroke(CabinetPalette.steelLight, lineWidth: 3)
            }
            .overlay {
                Rectangle()
                    .inset(by: 3)
                    .stroke(Color(red: 238 / 255, green: 240 / 255, blue: 230 / 255), lineWidth: 2)
            }
            .overlay {
                Rectangle()
                    .inset(by: 6)
                    .stroke(Color(red: 29 / 255, green: 40 / 255, blue: 57 / 255), lineWidth: 3)
            }
            .shadow(color: .black.opacity(0.78), radius: 0, x: 8, y: 8)
        }
    }
}

private struct CabinetShellScanlines: View {
    var body: some View {
        Canvas { context, size in
            for y in stride(from: CGFloat(10), through: size.height, by: 12) {
                context.fill(
                    Path(CGRect(x: 0, y: y, width: size.width, height: 2)),
                    with: .color(Color(red: 41 / 255, green: 167 / 255, blue: 210 / 255).opacity(0.13))
                )
            }
        }
    }
}

private struct CabinetRail: View {
    let side: CabinetSide

    var body: some View {
        let shape = PixelRailShape(side: side)

        ZStack {
            shape.fill(CabinetPalette.navy)

            Canvas { context, size in
                for y in stride(from: CGFloat(0), through: size.height, by: 22) {
                    context.fill(
                        Path(CGRect(x: 0, y: y, width: size.width, height: 14)),
                        with: .color(Color(red: 8 / 255, green: 24 / 255, blue: 45 / 255))
                    )
                    context.fill(
                        Path(CGRect(x: 0, y: y + 14, width: size.width, height: 4)),
                        with: .color(Color(red: 12 / 255, green: 45 / 255, blue: 78 / 255))
                    )
                    context.fill(
                        Path(CGRect(x: 0, y: y + 18, width: size.width, height: 4)),
                        with: .color(Color(red: 6 / 255, green: 18 / 255, blue: 34 / 255))
                    )
                }

                for x in stride(from: CGFloat(9), through: size.width, by: 11) {
                    context.fill(
                        Path(CGRect(x: x, y: 0, width: 2, height: size.height)),
                        with: .color(CabinetPalette.gold.opacity(0.38))
                    )
                }
            }

            HStack(spacing: 0) {
                Rectangle()
                    .fill(CabinetPalette.steelLight.opacity(0.24))
                    .frame(width: 3)
                Spacer(minLength: 0)
                Rectangle()
                    .fill(CabinetPalette.void.opacity(0.82))
                    .frame(width: 3)
            }
        }
        .clipShape(shape)
        .overlay {
            shape.stroke(CabinetPalette.steelDark, lineWidth: 3)
        }
        .opacity(0.96)
    }
}

private struct CabinetStageEdge: View {
    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(CabinetPalette.void)
            Rectangle().fill(CabinetPalette.steelDark)
        }
    }
}

private struct PixelRailShape: Shape {
    let side: CabinetSide

    func path(in rect: CGRect) -> Path {
        let notch = min(8, min(rect.width, rect.height) / 3)
        var path = Path()

        switch side {
        case .left:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY + notch))
            path.addLine(to: CGPoint(x: rect.minX + notch, y: rect.minY + notch))
            path.addLine(to: CGPoint(x: rect.minX + notch, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + notch, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + notch, y: rect.maxY - notch))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - notch))
        case .right:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - notch, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - notch, y: rect.minY + notch))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + notch))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - notch))
            path.addLine(to: CGPoint(x: rect.maxX - notch, y: rect.maxY - notch))
            path.addLine(to: CGPoint(x: rect.maxX - notch, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }

        path.closeSubpath()
        return path
    }
}

private enum CabinetSide {
    case left
    case right
}

private enum CabinetPalette {
    static let void = Color(red: 2 / 255, green: 6 / 255, blue: 17 / 255)
    static let ink = Color(red: 5 / 255, green: 13 / 255, blue: 29 / 255)
    static let midnight = Color(red: 8 / 255, green: 22 / 255, blue: 42 / 255)
    static let navy = Color(red: 10 / 255, green: 36 / 255, blue: 66 / 255)
    static let steelLight = Color(red: 208 / 255, green: 201 / 255, blue: 184 / 255)
    static let steelDark = Color(red: 53 / 255, green: 65 / 255, blue: 87 / 255)
    static let gold = Color(red: 244 / 255, green: 188 / 255, blue: 53 / 255)
}

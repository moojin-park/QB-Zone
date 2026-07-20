import SwiftUI

enum PocketVectorTheme {
    static let void = Color(red: 0.02, green: 0.04, blue: 0.09)
    static let background = Color(red: 0.04, green: 0.09, blue: 0.16)
    static let surface = Color(red: 0.07, green: 0.15, blue: 0.24)
    static let raisedSurface = Color(red: 0.10, green: 0.21, blue: 0.31)
    static let border = Color(red: 0.28, green: 0.61, blue: 0.74)
    static let cyan = Color(red: 0.11, green: 0.90, blue: 0.94)
    static let gold = Color(red: 0.96, green: 0.74, blue: 0.21)
    static let success = Color(red: 0.45, green: 0.89, blue: 0.48)
    static let warning = Color(red: 1.00, green: 0.66, blue: 0.28)
    static let textPrimary = Color.white
    static let textSecondary = Color(red: 0.78, green: 0.86, blue: 0.91)

    // The Championship submenu system is deliberately independent of every
    // launch-team palette. Team colors remain inside identity artwork only.
    static let championshipVoid = Color(red: 0.015, green: 0.035, blue: 0.060)
    static let championshipNavy = Color(red: 0.028, green: 0.070, blue: 0.115)
    static let championshipGraphite = Color(red: 0.065, green: 0.100, blue: 0.135)
    static let championshipSteel = Color(red: 0.41, green: 0.48, blue: 0.54)
    static let championshipSilver = Color(red: 0.78, green: 0.83, blue: 0.86)
    static let championshipGlacier = Color(red: 0.95, green: 0.97, blue: 0.98)
    static let championshipStatus = Color(red: 0.40, green: 0.85, blue: 0.90)
}
extension Color {
    init(_ color: RGBColor) {
        self.init(
            red: Double(color.red) / 255,
            green: Double(color.green) / 255,
            blue: Double(color.blue) / 255
        )
    }
}

extension RGBColor {
    var accessibleForegroundColor: Color {
        relativeLuminance > 0.46 ? PocketVectorTheme.void : .white
    }
}

struct PocketVectorBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [PocketVectorTheme.background, PocketVectorTheme.void],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Canvas { context, size in
                for y in stride(from: CGFloat(8), through: size.height, by: 12) {
                    context.fill(
                        Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                        with: .color(PocketVectorTheme.cyan.opacity(0.05))
                    )
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct PocketVectorPanelModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(PocketVectorTheme.surface.opacity(0.96), in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(PocketVectorTheme.border.opacity(0.72), lineWidth: 1)
            }
    }
}

struct ChampionshipBackdrop: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Image("SubmenuStadiumBackdrop")
                    .resizable()
                    .interpolation(.none)
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()

                LinearGradient(
                    colors: [
                        PocketVectorTheme.championshipVoid.opacity(0.18),
                        PocketVectorTheme.championshipVoid.opacity(0.48)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                Canvas { context, size in
                    for y in stride(from: CGFloat(7), through: size.height, by: 8) {
                        context.fill(
                            Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                            with: .color(.black.opacity(0.14))
                        )
                    }
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct ChampionshipPanelModifier: ViewModifier {
    let isSelected: Bool

    func body(content: Content) -> some View {
        content
            .background(
                LinearGradient(
                    colors: [
                        PocketVectorTheme.championshipNavy.opacity(0.98),
                        PocketVectorTheme.championshipVoid.opacity(0.99)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        isSelected
                            ? PocketVectorTheme.championshipGlacier
                            : PocketVectorTheme.championshipSteel.opacity(0.88),
                        lineWidth: isSelected ? 2.5 : 1.5
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(
                        isSelected
                            ? PocketVectorTheme.championshipStatus.opacity(0.72)
                            : PocketVectorTheme.championshipSilver.opacity(0.16),
                        lineWidth: 1
                    )
                    .padding(4)
            }
            .shadow(color: .black.opacity(0.62), radius: 3, x: 0, y: 3)
    }
}

extension View {
    func pocketVectorPanel() -> some View {
        modifier(PocketVectorPanelModifier())
    }

    func championshipPanel(isSelected: Bool = false) -> some View {
        modifier(ChampionshipPanelModifier(isSelected: isSelected))
    }
}

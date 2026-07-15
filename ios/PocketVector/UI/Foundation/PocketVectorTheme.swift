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

extension View {
    func pocketVectorPanel() -> some View {
        modifier(PocketVectorPanelModifier())
    }
}

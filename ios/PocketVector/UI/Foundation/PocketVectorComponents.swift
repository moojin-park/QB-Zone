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

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22)
                .fill(
                    LinearGradient(
                        colors: [Color(team.primaryColor), Color(team.secondaryColor)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text(initials)
                .font(.system(size: size * 0.28, weight: .black, design: .rounded))
                .foregroundStyle(team.primaryColor.accessibleForegroundColor)
                .shadow(color: .black.opacity(0.45), radius: 1, x: 0, y: 1)
        }
        .frame(width: size, height: size)
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.22)
                .stroke(Color(team.accentColor), lineWidth: 2)
        }
        .accessibilityHidden(true)
    }

    private var initials: String {
        team.displayName
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
    }
}

struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.black))
            .tracking(0.8)
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

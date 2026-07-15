import SwiftUI

/// SwiftUI owns run navigation and settlement; SpriteKit owns only the active
/// configured simulation. Exit never changes destinations until the scene has
/// emitted an authoritative `.abandoned` run and settlement has accepted it.
@MainActor
struct LegacyGameplayAdapterView: View {
    let configuration: RunConfiguration
    let settings: PlayerSettings
    let isSettling: Bool
    let settlementErrorMessage: String?
    let onCompletedRun: (CompletedRun) -> Void
    let onRetrySettlement: () -> Void

    @State private var showsExitConfirmation = false
    @State private var abandonRequestID = 0
    @State private var abandonWasRequested = false

    private let catalog = LaunchCatalog.approved

    var body: some View {
        ZStack(alignment: .topLeading) {
            GameRootView(
                configuration: configuration,
                settings: settings,
                abandonRequestID: abandonRequestID,
                onCompletedRun: { completedRun in
                    abandonWasRequested = true
                    onCompletedRun(completedRun)
                }
            )

            HStack(spacing: 10) {
                Button {
                    showsExitConfirmation = true
                } label: {
                    Label("Exit Run", systemImage: "xmark")
                        .font(.headline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(.black.opacity(0.76), in: Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .disabled(abandonWasRequested || isSettling)
                .accessibilityHint("Asks for confirmation before ending this run")

                if let offense = catalog.team(id: configuration.offenseTeamID),
                   let defense = catalog.team(id: configuration.defenseTeamID) {
                    Text("\(offense.displayName) vs \(defense.displayName)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 9)
                        .background(.black.opacity(0.76), in: Capsule())
                        .accessibilityLabel(
                            "\(offense.displayName) offense against \(defense.displayName) defense"
                        )
                }
            }
            .padding()

            if isSettling || settlementErrorMessage != nil {
                settlementOverlay
            }
        }
        .background(PocketVectorTheme.void)
        .ignoresSafeArea()
        .confirmationDialog(
            "End this run?",
            isPresented: $showsExitConfirmation,
            titleVisibility: .visible
        ) {
            Button("End Run", role: .destructive) {
                guard !abandonWasRequested else { return }
                abandonWasRequested = true
                abandonRequestID &+= 1
            }
            Button("Keep Playing", role: .cancel) {}
        } message: {
            Text("This run will be recorded as abandoned and will not earn coins.")
        }
    }

    private var settlementOverlay: some View {
        ZStack {
            Color.black.opacity(0.72)
                .ignoresSafeArea()
                .contentShape(Rectangle())

            VStack(spacing: 14) {
                if isSettling {
                    ProgressView()
                        .controlSize(.large)
                        .tint(PocketVectorTheme.cyan)
                    Text("Saving Run")
                        .font(.title2.weight(.bold))
                    Text("Keeping your score, progress, and rewards consistent.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.76))
                } else if let settlementErrorMessage {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(PocketVectorTheme.gold)
                    Text("Run Not Saved Yet")
                        .font(.title2.weight(.bold))
                    Text(settlementErrorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                    Button("Retry Save", action: onRetrySettlement)
                        .buttonStyle(.borderedProminent)
                        .tint(PocketVectorTheme.cyan)
                        .foregroundStyle(PocketVectorTheme.void)
                }
            }
            .frame(maxWidth: 440)
            .padding(28)
            .background(.black.opacity(0.9), in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(PocketVectorTheme.cyan.opacity(0.65), lineWidth: 2)
            }
            .padding(24)
        }
        .accessibilityElement(children: .contain)
    }
}

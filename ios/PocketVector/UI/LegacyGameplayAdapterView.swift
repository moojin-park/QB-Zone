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

    @State private var exitConfirmation = GameplayExitConfirmationState()
    @State private var gameplaySnapshot: GameplaySceneSnapshot?
    @State private var pauseRequests = GameplayPauseRequestState()

    private let catalog = LaunchCatalog.approved

    var body: some View {
        ZStack {
            GameRootView(
                configuration: configuration,
                settings: settings,
                abandonRequestID: pauseRequests.confirmedExitRequestID,
                resumeRequestID: pauseRequests.resumeRequestID,
                onCompletedRun: { completedRun in
                    onCompletedRun(completedRun)
                },
                onGameplaySnapshotChanged: { snapshot in
                    pauseRequests.receive(snapshot)
                    gameplaySnapshot = snapshot
                    if !snapshot.isPaused {
                        exitConfirmation.dismiss()
                    }
                }
            )

            if let gameplaySnapshot, gameplaySnapshot.isPaused {
                PausedGameplayOverlay(
                    statistics: gameplaySnapshot.statistics,
                    accent: pauseAccent,
                    accentForeground: pauseAccentForeground,
                    resumeIsPending: pauseRequests.resumeRequestPending,
                    exitIsPending: pauseRequests.confirmedExitRequestPending || isSettling,
                    onResume: requestResume,
                    onExit: {
                        _ = exitConfirmation.present(whilePaused: true)
                    }
                )
                .allowsHitTesting(!exitConfirmation.isPresented)
                .accessibilityHidden(exitConfirmation.isPresented)

                if exitConfirmation.isPresented {
                    ExitRunConfirmationOverlay(
                        accent: pauseAccent,
                        accentForeground: pauseAccentForeground,
                        actionsAreDisabled: isSettling
                            || pauseRequests.confirmedExitRequestPending,
                        onKeepPlaying: { exitConfirmation.cancel() },
                        onEndRun: confirmExit
                    )
                }
            }

            if isSettling || settlementErrorMessage != nil {
                settlementOverlay
            }
        }
        .background(PocketVectorTheme.void)
        .ignoresSafeArea()
    }

    private var pauseAccent: Color {
        guard let team = catalog.team(id: configuration.offenseTeamID) else {
            return PocketVectorTheme.cyan
        }
        return Color(team.accentColor)
    }

    private var pauseAccentForeground: Color {
        guard let team = catalog.team(id: configuration.offenseTeamID) else {
            return PocketVectorTheme.void
        }
        return team.accentColor.accessibleForegroundColor
    }

    private func requestResume() {
        _ = pauseRequests.requestResume(
            whilePaused: gameplaySnapshot?.isPaused == true
        )
    }

    private func confirmExit() {
        guard !isSettling,
              pauseRequests.requestConfirmedExit(
                whilePaused: gameplaySnapshot?.isPaused == true
              ) else { return }

        exitConfirmation.dismiss()
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

struct GameplayPauseRequestState: Equatable {
    private(set) var resumeRequestID = 0
    private(set) var confirmedExitRequestID = 0
    private(set) var resumeRequestPending = false
    private(set) var confirmedExitRequestPending = false

    mutating func receive(_ snapshot: GameplaySceneSnapshot) {
        if !snapshot.isPaused {
            resumeRequestPending = false
        }
    }

    @discardableResult
    mutating func requestResume(whilePaused: Bool) -> Bool {
        guard whilePaused,
              !resumeRequestPending,
              !confirmedExitRequestPending else { return false }

        resumeRequestPending = true
        resumeRequestID &+= 1
        return true
    }

    @discardableResult
    mutating func requestConfirmedExit(whilePaused: Bool) -> Bool {
        guard whilePaused,
              !resumeRequestPending,
              !confirmedExitRequestPending else { return false }

        confirmedExitRequestPending = true
        confirmedExitRequestID &+= 1
        return true
    }
}

struct GameplayExitConfirmationState: Equatable {
    private(set) var isPresented = false

    @discardableResult
    mutating func present(whilePaused: Bool) -> Bool {
        guard whilePaused, !isPresented else { return false }
        isPresented = true
        return true
    }

    mutating func cancel() {
        isPresented = false
    }

    mutating func dismiss() {
        isPresented = false
    }
}

struct GameplayPauseLayout: Equatable {
    let isCompact: Bool
    let panelWidth: CGFloat
    let panelHeight: CGFloat
    let panelPadding: CGFloat
    let sectionSpacing: CGFloat
    let headerHeight: CGFloat
    let statCellHeight: CGFloat
    let statColumnCount: Int
    let statGridSpacing: CGFloat
    let buttonHeight: CGFloat
    let outerMargin: CGFloat

    init(availableSize: CGSize) {
        isCompact = availableSize.width < 700 || availableSize.height < 390
        outerMargin = isCompact ? 10 : 24
        panelPadding = isCompact ? 12 : 18
        sectionSpacing = isCompact ? 8 : 12
        headerHeight = isCompact ? 44 : 54
        statCellHeight = isCompact ? 52 : 70
        statColumnCount = isCompact ? 2 : 4
        statGridSpacing = isCompact ? 6 : 10
        buttonHeight = isCompact ? 48 : 54
        panelWidth = min(
            isCompact ? 600 : 680,
            max(0, availableSize.width - (outerMargin * 2))
        )

        let rowCount = statColumnCount == 2 ? 2 : 1
        let gridHeight = CGFloat(rowCount) * statCellHeight
            + CGFloat(rowCount - 1) * statGridSpacing
        panelHeight = (panelPadding * 2)
            + headerHeight
            + 1
            + gridHeight
            + buttonHeight
            + (sectionSpacing * 3)
    }
}

struct GameplayExitConfirmationLayout: Equatable {
    let isCompact: Bool
    let panelWidth: CGFloat
    let panelHeight: CGFloat
    let panelPadding: CGFloat
    let sectionSpacing: CGFloat
    let headerHeight: CGFloat
    let messageHeight: CGFloat
    let buttonHeight: CGFloat
    let outerMargin: CGFloat

    init(availableSize: CGSize) {
        isCompact = availableSize.width < 700 || availableSize.height < 390
        outerMargin = isCompact ? 10 : 24
        panelPadding = isCompact ? 14 : 20
        sectionSpacing = isCompact ? 8 : 12
        headerHeight = isCompact ? 36 : 44
        messageHeight = isCompact ? 32 : 44
        buttonHeight = isCompact ? 48 : 54
        panelWidth = min(
            isCompact ? 520 : 560,
            max(0, availableSize.width - (outerMargin * 2))
        )
        panelHeight = (panelPadding * 2)
            + headerHeight
            + messageHeight
            + buttonHeight
            + (sectionSpacing * 2)
    }
}

struct GameplayPauseStatPresentation: Identifiable, Equatable {
    enum ID: CaseIterable {
        case attempts
        case completions
        case completionPercentage
        case touchdowns
    }

    let id: ID
    let title: String
    let accessibilityTitle: String
    let value: String

    static func items(
        for statistics: LiveGameplayStatisticsSnapshot
    ) -> [GameplayPauseStatPresentation] {
        [
            GameplayPauseStatPresentation(
                id: .attempts,
                title: "ATTEMPTS",
                accessibilityTitle: "Pass attempts",
                value: statistics.attempts.formatted()
            ),
            GameplayPauseStatPresentation(
                id: .completions,
                title: "COMPLETIONS",
                accessibilityTitle: "Successful completions",
                value: statistics.successfulCompletions.formatted()
            ),
            GameplayPauseStatPresentation(
                id: .completionPercentage,
                title: "COMPLETION %",
                accessibilityTitle: "Completion percentage",
                value: "\(statistics.completionPercentage)%"
            ),
            GameplayPauseStatPresentation(
                id: .touchdowns,
                title: "TOUCHDOWNS",
                accessibilityTitle: "Touchdowns thrown",
                value: statistics.touchdowns.formatted()
            ),
        ]
    }
}

private struct PausedGameplayOverlay: View {
    let statistics: LiveGameplayStatisticsSnapshot
    let accent: Color
    let accentForeground: Color
    let resumeIsPending: Bool
    let exitIsPending: Bool
    let onResume: () -> Void
    let onExit: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let safeWidth = max(
                0,
                geometry.size.width
                    - geometry.safeAreaInsets.leading
                    - geometry.safeAreaInsets.trailing
            )
            let safeHeight = max(
                0,
                geometry.size.height
                    - geometry.safeAreaInsets.top
                    - geometry.safeAreaInsets.bottom
            )
            let availableSize = CGSize(width: safeWidth, height: safeHeight)
            let layout = GameplayPauseLayout(availableSize: availableSize)

            ZStack {
                Color.black.opacity(0.08)
                    .contentShape(Rectangle())
                    .accessibilityHidden(true)

                PausedGameplayPanel(
                    statistics: statistics,
                    layout: layout,
                    accent: accent,
                    accentForeground: accentForeground,
                    resumeIsPending: resumeIsPending,
                    exitIsPending: exitIsPending,
                    onResume: onResume,
                    onExit: onExit
                )
                .position(
                    x: geometry.safeAreaInsets.leading + (safeWidth / 2),
                    y: geometry.safeAreaInsets.top + (safeHeight / 2)
                )
            }
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .contain)
    }
}

private struct ExitRunConfirmationOverlay: View {
    let accent: Color
    let accentForeground: Color
    let actionsAreDisabled: Bool
    let onKeepPlaying: () -> Void
    let onEndRun: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let safeWidth = max(
                0,
                geometry.size.width
                    - geometry.safeAreaInsets.leading
                    - geometry.safeAreaInsets.trailing
            )
            let safeHeight = max(
                0,
                geometry.size.height
                    - geometry.safeAreaInsets.top
                    - geometry.safeAreaInsets.bottom
            )
            let availableSize = CGSize(width: safeWidth, height: safeHeight)
            let layout = GameplayExitConfirmationLayout(availableSize: availableSize)

            ZStack {
                Color.black.opacity(0.68)
                    .contentShape(Rectangle())
                    .accessibilityHidden(true)

                ExitRunConfirmationPanel(
                    layout: layout,
                    accent: accent,
                    accentForeground: accentForeground,
                    actionsAreDisabled: actionsAreDisabled,
                    onKeepPlaying: onKeepPlaying,
                    onEndRun: onEndRun
                )
                .position(
                    x: geometry.safeAreaInsets.leading + (safeWidth / 2),
                    y: geometry.safeAreaInsets.top + (safeHeight / 2)
                )
            }
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .contain)
    }
}

private struct ExitRunConfirmationPanel: View {
    let layout: GameplayExitConfirmationLayout
    let accent: Color
    let accentForeground: Color
    let actionsAreDisabled: Bool
    let onKeepPlaying: () -> Void
    let onEndRun: () -> Void

    var body: some View {
        VStack(spacing: layout.sectionSpacing) {
            HStack(spacing: layout.isCompact ? 9 : 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(
                        size: layout.isCompact ? 20 : 25,
                        weight: .black
                    ))
                    .foregroundStyle(GameplayPauseButtonStyle.exitCoral)
                    .accessibilityHidden(true)

                Text("END THIS RUN?")
                    .font(.system(
                        size: layout.isCompact ? 24 : 30,
                        weight: .black,
                        design: .rounded
                    ))
                    .tracking(layout.isCompact ? 0.8 : 1.2)
                    .foregroundStyle(PocketVectorTheme.textPrimary)
                    .shadow(color: .black, radius: 0, x: 2, y: 3)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: layout.headerHeight)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("End this run?")
            .accessibilityAddTraits(.isHeader)

            Text("This run will be recorded as abandoned and will not earn coins.")
                .font(.system(
                    size: layout.isCompact ? 12 : 14,
                    weight: .semibold,
                    design: .rounded
                ))
                .foregroundStyle(PocketVectorTheme.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: layout.messageHeight)

            HStack(spacing: layout.isCompact ? 8 : 12) {
                Button(action: onKeepPlaying) {
                    Label("KEEP PLAYING", systemImage: "arrow.uturn.backward")
                        .frame(maxWidth: .infinity, minHeight: layout.buttonHeight)
                }
                .buttonStyle(
                    GameplayPauseButtonStyle(
                        kind: .primary,
                        tint: accent,
                        foreground: accentForeground
                    )
                )
                .disabled(actionsAreDisabled)
                .accessibilityHint("Closes this confirmation and returns to the pause menu")

                Button(action: onEndRun) {
                    Label("END RUN", systemImage: "rectangle.portrait.and.arrow.right")
                        .frame(maxWidth: .infinity, minHeight: layout.buttonHeight)
                }
                .buttonStyle(
                    GameplayPauseButtonStyle(
                        kind: .destructive,
                        tint: GameplayPauseButtonStyle.exitCoral,
                        foreground: .white
                    )
                )
                .disabled(actionsAreDisabled)
                .accessibilityHint("Confirms this run should end without earning coins")
            }
        }
        .padding(layout.panelPadding)
        .frame(width: layout.panelWidth, height: layout.panelHeight)
        .background {
            BroadcastPlateShape(cut: layout.isCompact ? 9 : 13)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.04, green: 0.08, blue: 0.13),
                            Color(red: 0.08, green: 0.13, blue: 0.19),
                            Color(red: 0.025, green: 0.05, blue: 0.09),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: .black.opacity(0.95), radius: 0, x: 0, y: 8)
        }
        .overlay {
            BroadcastPlateShape(cut: layout.isCompact ? 9 : 13)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.88),
                            Color(red: 0.30, green: 0.38, blue: 0.47),
                            Color(red: 0.12, green: 0.17, blue: 0.23),
                            Color.white.opacity(0.58),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: layout.isCompact ? 3 : 4
                )
        }
        .overlay {
            BroadcastPlateShape(cut: layout.isCompact ? 7 : 10)
                .inset(by: layout.isCompact ? 6 : 8)
                .strokeBorder(GameplayPauseButtonStyle.exitCoral.opacity(0.82), lineWidth: 1.5)
        }
        .overlay {
            GameplayPauseRivets(inset: layout.isCompact ? 7 : 10)
        }
        .accessibilityElement(children: .contain)
    }
}

private struct PausedGameplayPanel: View {
    let statistics: LiveGameplayStatisticsSnapshot
    let layout: GameplayPauseLayout
    let accent: Color
    let accentForeground: Color
    let resumeIsPending: Bool
    let exitIsPending: Bool
    let onResume: () -> Void
    let onExit: () -> Void

    private var statColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: layout.statGridSpacing),
            count: layout.statColumnCount
        )
    }

    var body: some View {
        VStack(spacing: layout.sectionSpacing) {
            header
                .frame(height: layout.headerHeight)

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.clear, accent.opacity(0.9), Color.clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
                .accessibilityHidden(true)

            LazyVGrid(columns: statColumns, spacing: layout.statGridSpacing) {
                ForEach(GameplayPauseStatPresentation.items(for: statistics)) { item in
                    PausedGameplayStatCell(item: item, accent: accent)
                        .frame(height: layout.statCellHeight)
                }
            }

            HStack(spacing: layout.isCompact ? 8 : 12) {
                Button(action: onResume) {
                    Label(
                        resumeIsPending ? "RESUMING" : "RESUME",
                        systemImage: "play.fill"
                    )
                    .frame(maxWidth: .infinity, minHeight: layout.buttonHeight)
                }
                .buttonStyle(
                    GameplayPauseButtonStyle(
                        kind: .primary,
                        tint: accent,
                        foreground: accentForeground
                    )
                )
                .disabled(resumeIsPending || exitIsPending)
                .accessibilityHint("Returns to the paused run")

                Button(action: onExit) {
                    Label("EXIT RUN", systemImage: "rectangle.portrait.and.arrow.right")
                        .frame(maxWidth: .infinity, minHeight: layout.buttonHeight)
                }
                .buttonStyle(
                    GameplayPauseButtonStyle(
                        kind: .destructive,
                        tint: GameplayPauseButtonStyle.exitCoral,
                        foreground: .white
                    )
                )
                .disabled(resumeIsPending || exitIsPending)
                .accessibilityHint("Asks for confirmation before ending this run")
            }
        }
        .padding(layout.panelPadding)
        .frame(width: layout.panelWidth, height: layout.panelHeight)
        .background {
            BroadcastPlateShape(cut: layout.isCompact ? 9 : 13)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.04, green: 0.08, blue: 0.13),
                            Color(red: 0.07, green: 0.15, blue: 0.23),
                            Color(red: 0.025, green: 0.06, blue: 0.11),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: .black.opacity(0.9), radius: 0, x: 0, y: 8)
        }
        .overlay {
            BroadcastPlateShape(cut: layout.isCompact ? 9 : 13)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.88),
                            Color(red: 0.30, green: 0.38, blue: 0.47),
                            Color(red: 0.12, green: 0.17, blue: 0.23),
                            Color.white.opacity(0.58),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: layout.isCompact ? 3 : 4
                )
        }
        .overlay {
            BroadcastPlateShape(cut: layout.isCompact ? 7 : 10)
                .inset(by: layout.isCompact ? 6 : 8)
                .strokeBorder(accent.opacity(0.88), lineWidth: 1.5)
        }
        .overlay {
            GameplayPauseRivets(inset: layout.isCompact ? 7 : 10)
        }
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(spacing: layout.isCompact ? 9 : 13) {
            Spacer(minLength: 0)

            ZStack {
                BroadcastPlateShape(cut: layout.isCompact ? 4 : 6)
                    .fill(Color.black.opacity(0.74))
                BroadcastPlateShape(cut: layout.isCompact ? 4 : 6)
                    .strokeBorder(accent.opacity(0.9), lineWidth: 1.5)
                Image(systemName: "pause.fill")
                    .font(.system(
                        size: layout.isCompact ? 16 : 21,
                        weight: .black,
                        design: .rounded
                    ))
                    .foregroundStyle(accent)
            }
            .frame(
                width: layout.isCompact ? 36 : 44,
                height: layout.isCompact ? 34 : 42
            )
            .accessibilityHidden(true)

            VStack(alignment: .center, spacing: 0) {
                Text("PAUSED")
                    .font(.system(
                        size: layout.isCompact ? 28 : 36,
                        weight: .black,
                        design: .rounded
                    ))
                    .tracking(layout.isCompact ? 1.2 : 1.8)
                    .foregroundStyle(PocketVectorTheme.textPrimary)
                    .shadow(color: .black, radius: 0, x: 2, y: 3)
                    .lineLimit(1)

                Text("STATS")
                    .font(.system(
                        size: layout.isCompact ? 8 : 10,
                        weight: .black,
                        design: .rounded
                    ))
                    .tracking(1.5)
                    .foregroundStyle(PocketVectorTheme.textSecondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Game paused")
            .accessibilityAddTraits(.isHeader)

            Color.clear
                .frame(
                    width: layout.isCompact ? 36 : 44,
                    height: layout.isCompact ? 34 : 42
                )
                .accessibilityHidden(true)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct PausedGameplayStatCell: View {
    let item: GameplayPauseStatPresentation
    let accent: Color

    var body: some View {
        VStack(spacing: 1) {
            Text(item.title)
                .font(.system(size: 9, weight: .black, design: .rounded))
                .tracking(0.7)
                .foregroundStyle(PocketVectorTheme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(item.value)
                .font(.system(size: 27, weight: .black, design: .monospaced))
                .foregroundStyle(PocketVectorTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
                .shadow(color: accent.opacity(0.55), radius: 0, x: 1, y: 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            BroadcastPlateShape(cut: 5)
                .fill(Color.black.opacity(0.55))
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(accent.opacity(0.78))
                .frame(height: 2)
                .padding(.horizontal, 8)
        }
        .overlay {
            BroadcastPlateShape(cut: 5)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.accessibilityTitle)
        .accessibilityValue(item.value)
    }
}

private struct GameplayPauseButtonStyle: ButtonStyle {
    enum Kind {
        case primary
        case destructive
    }

    static let exitCoral = Color(red: 1, green: 0.30, blue: 0.34)

    let kind: Kind
    let tint: Color
    let foreground: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .black, design: .rounded))
            .tracking(0.7)
            .foregroundStyle(kind == .primary ? foreground : tint)
            .background {
                BroadcastPlateShape(cut: 7)
                    .fill(
                        kind == .primary
                            ? tint.opacity(configuration.isPressed ? 0.74 : 1)
                            : Color.black.opacity(configuration.isPressed ? 0.88 : 0.7)
                    )
                    .shadow(color: .black.opacity(0.9), radius: 0, x: 0, y: 4)
            }
            .overlay {
                BroadcastPlateShape(cut: 7)
                    .strokeBorder(
                        kind == .primary ? Color.white.opacity(0.74) : tint,
                        lineWidth: 2
                    )
            }
            .offset(y: configuration.isPressed ? 2 : 0)
            .opacity(configuration.isPressed ? 0.92 : 1)
    }
}

private struct BroadcastPlateShape: InsettableShape {
    let cut: CGFloat
    private var insetAmount: CGFloat = 0

    init(cut: CGFloat) {
        self.cut = cut
    }

    func path(in rect: CGRect) -> Path {
        let frame = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let resolvedCut = max(
            0,
            min(cut - insetAmount, min(frame.width, frame.height) / 2)
        )
        var path = Path()
        path.move(to: CGPoint(x: frame.minX + resolvedCut, y: frame.minY))
        path.addLine(to: CGPoint(x: frame.maxX - resolvedCut, y: frame.minY))
        path.addLine(to: CGPoint(x: frame.maxX, y: frame.minY + resolvedCut))
        path.addLine(to: CGPoint(x: frame.maxX, y: frame.maxY - resolvedCut))
        path.addLine(to: CGPoint(x: frame.maxX - resolvedCut, y: frame.maxY))
        path.addLine(to: CGPoint(x: frame.minX + resolvedCut, y: frame.maxY))
        path.addLine(to: CGPoint(x: frame.minX, y: frame.maxY - resolvedCut))
        path.addLine(to: CGPoint(x: frame.minX, y: frame.minY + resolvedCut))
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> BroadcastPlateShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

private struct GameplayPauseRivets: View {
    let inset: CGFloat

    var body: some View {
        Canvas { context, size in
            let radius: CGFloat = 2.2
            let positions = [
                CGPoint(x: inset, y: inset),
                CGPoint(x: size.width - inset, y: inset),
                CGPoint(x: inset, y: size.height - inset),
                CGPoint(x: size.width - inset, y: size.height - inset),
            ]
            for position in positions {
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: position.x - radius,
                        y: position.y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )),
                    with: .color(Color.white.opacity(0.72))
                )
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: position.x - 0.8,
                        y: position.y - 0.8,
                        width: 1.6,
                        height: 1.6
                    )),
                    with: .color(Color.black.opacity(0.85))
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

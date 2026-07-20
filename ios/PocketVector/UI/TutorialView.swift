import AVFoundation
import Combine
import SwiftUI
import UIKit

@MainActor
struct TutorialView: View {
    @Bindable var coordinator: AppCoordinator

    @Environment(\.accessibilityReduceMotion) private var systemReducedMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase

    @State private var player = AVPlayer()
    @State private var mediaIsReady = false
    @State private var playbackStage = 0
    @State private var hasAutoplayed = false

    private let playbackClock = Timer.publish(
        every: 0.10,
        on: .main,
        in: .common
    )
    .autoconnect()

    private let stages = TutorialStage.allCases

    var body: some View {
        ChampionshipSubmenuScreen(
            title: "How to Play",
            onBack: coordinator.cancelTutorial,
            headerAccessory: {
                TutorialStepBadge()
            }
        ) {
            GeometryReader { proxy in
                let compact = proxy.size.height < 330
                let padLayout = proxy.size.width / max(proxy.size.height, 1) < 1.65
                let accessibleType = dynamicTypeSize.isAccessibilitySize
                let horizontalInset: CGFloat = compact ? 2 : (padLayout ? 18 : 8)
                let verticalInset: CGFloat = compact ? 0 : (padLayout ? 18 : 4)
                let stackSpacing: CGFloat = compact ? 6 : (padLayout ? 12 : 9)
                let contentWidth = min(
                    max(0, proxy.size.width - (horizontalInset * 2)),
                    padLayout ? 1_280 : 1_240
                )
                let filmHeight: CGFloat = compact
                    ? 160
                    : (padLayout ? min(520, proxy.size.height * 0.63) : min(330, proxy.size.height * 0.66))

                ScrollView {
                    VStack(spacing: stackSpacing) {
                        filmstrip(
                            width: contentWidth,
                            height: filmHeight,
                            compact: compact,
                            expanded: padLayout,
                            accessibleType: accessibleType
                        )

                        TutorialInstructionRail(compact: compact)

                        transport(compact: compact, expanded: padLayout)
                    }
                    .frame(width: contentWidth)
                    .frame(
                        minHeight: accessibleType ? nil : proxy.size.height - (verticalInset * 2),
                        alignment: .center
                    )
                    .padding(.horizontal, horizontalInset)
                    .padding(.vertical, verticalInset)
                    .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .task {
            prepareMediaIfNeeded()
        }
        .onReceive(playbackClock) { _ in
            updatePlaybackStage()
        }
        .onChange(of: reducesMotion) { _, reduced in
            if reduced {
                player.pause()
                player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
                playbackStage = 0
            } else if mediaIsReady, !hasAutoplayed {
                hasAutoplayed = true
                replayDemo()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                player.pause()
            }
        }
        .onDisappear {
            player.pause()
        }
    }

    private var completionTitle: String {
        if case .tutorial(.beforeRun) = coordinator.currentDestination {
            return "Start Run"
        }
        return "Finish Review"
    }

    private var completionHint: String {
        if case .tutorial(.beforeRun) = coordinator.currentDestination {
            return "Saves tutorial completion, then starts the selected run"
        }
        return "Finishes the tutorial and returns to Settings"
    }

    private var reducesMotion: Bool {
        systemReducedMotion || coordinator.state.settings.reducedMotion
    }

    @ViewBuilder
    private func filmstrip(
        width: CGFloat,
        height: CGFloat,
        compact: Bool,
        expanded: Bool,
        accessibleType: Bool
    ) -> some View {
        if accessibleType {
            VStack(spacing: expanded ? 14 : 10) {
                ForEach(stages) { stage in
                    filmFrame(
                        stage,
                        width: width,
                        height: expanded ? 330 : 220,
                        compact: false,
                        expanded: expanded
                    )
                }
            }
        } else {
            let spacing: CGFloat = compact ? 6 : (expanded ? 14 : 10)
            let frameWidth = max(0, (width - (spacing * 2)) / 3)

            HStack(spacing: spacing) {
                ForEach(stages) { stage in
                    filmFrame(
                        stage,
                        width: frameWidth,
                        height: height,
                        compact: compact,
                        expanded: expanded
                    )
                }
            }
            .frame(height: height)
        }
    }

    private func filmFrame(
        _ stage: TutorialStage,
        width: CGFloat,
        height: CGFloat,
        compact: Bool,
        expanded: Bool
    ) -> some View {
        TutorialFilmFrame(
            stage: stage,
            isActive: playbackStage == stage.index,
            width: width,
            height: height,
            compact: compact,
            expanded: expanded
        ) {
            if stage == .throwToIt {
                ZStack {
                    tutorialImage(named: stage.posterAssetName)
                    if mediaIsReady {
                        TutorialPlayerSurface(player: player)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
            } else {
                tutorialImage(named: stage.posterAssetName)
            }
        }
    }

    private func tutorialImage(named name: String) -> some View {
        TutorialGameplayPoster(name: name)
            .accessibilityHidden(true)
    }

    private func transport(compact: Bool, expanded: Bool) -> some View {
        let replayWidth: CGFloat = compact ? 150 : (expanded ? 260 : 210)
        let completionWidth: CGFloat = compact ? 190 : (expanded ? 310 : 270)

        return HStack(spacing: compact ? 8 : 12) {
            Button(action: replayDemo) {
                HStack(spacing: compact ? 6 : 9) {
                    ChampionshipPixelIcon(
                        name: "SubmenuPlayIcon",
                        size: compact ? 22 : (expanded ? 34 : 28)
                    )
                    Text("REPLAY")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(ChampionshipSecondaryButtonStyle())
            .frame(width: replayWidth)
            .disabled(!mediaIsReady)
            .accessibilityLabel("Replay passing demonstration")
            .accessibilityHint("Plays the complete tutorial animation from the beginning")

            TutorialProgressLights(activeStage: playbackStage)
                .frame(maxWidth: .infinity)

            Button {
                Task { await coordinator.completeTutorial() }
            } label: {
                HStack(spacing: compact ? 6 : 9) {
                    Text(completionTitle.uppercased())
                    ChampionshipPixelIcon(
                        name: completionTitle == "Start Run"
                            ? "SubmenuPlayIcon"
                            : "SubmenuForwardIcon",
                        size: compact ? 22 : (expanded ? 34 : 28)
                    )
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(ChampionshipPrimaryButtonStyle(compact: compact))
            .frame(width: completionWidth)
            .accessibilityHint(completionHint)
            .disabled(coordinator.isRequestInFlight)
        }
        .frame(maxWidth: expanded ? 1_080 : 980)
        .frame(maxWidth: .infinity)
    }

    private func prepareMediaIfNeeded() {
        guard player.currentItem == nil else { return }
        guard let dataAsset = NSDataAsset(name: "TutorialRunUnder") else { return }

        do {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("PocketVectorTutorial", isDirectory: true)
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let mediaURL = directory.appendingPathComponent("tutorial-pass-run-under-v1.mp4")
            let existingSize = try? mediaURL.resourceValues(forKeys: [.fileSizeKey]).fileSize
            if existingSize != dataAsset.data.count {
                try dataAsset.data.write(to: mediaURL, options: .atomic)
            }

            let item = AVPlayerItem(url: mediaURL)
            player.replaceCurrentItem(with: item)
            player.actionAtItemEnd = .pause
            player.isMuted = true
            mediaIsReady = true

            if reducesMotion {
                player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
            } else {
                hasAutoplayed = true
                replayDemo()
            }
        } catch {
            mediaIsReady = false
        }
    }

    private func replayDemo() {
        guard mediaIsReady else { return }
        playbackStage = 0
        player.pause()
        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        player.play()
    }

    private func updatePlaybackStage() {
        guard mediaIsReady else { return }
        let elapsed = player.currentTime().seconds
        guard elapsed.isFinite else { return }

        if elapsed < 1.45 {
            playbackStage = 0
        } else if elapsed < 2.45 {
            playbackStage = 1
        } else {
            playbackStage = 2
        }
    }
}

private enum TutorialStage: Int, CaseIterable, Identifiable {
    case pickASpot
    case throwToIt
    case avoidDefenders

    var id: Int { rawValue }
    var index: Int { rawValue }
    var number: Int { rawValue + 1 }

    var title: String {
        switch self {
        case .pickASpot: "Pick a spot"
        case .throwToIt: "Throw to it"
        case .avoidDefenders: "Avoid the defenders"
        }
    }

    var posterAssetName: String {
        switch self {
        case .pickASpot: "TutorialPickSpot"
        case .throwToIt: "TutorialThrowToIt"
        case .avoidDefenders: "TutorialAvoidDefenders"
        }
    }
}

private struct TutorialStepBadge: View {
    var body: some View {
        HStack(spacing: 7) {
            ForEach(0 ..< 3, id: \.self) { _ in
                Circle()
                    .fill(PocketVectorTheme.championshipStatus)
                    .frame(width: 7, height: 7)
            }
            Text("3 STEPS")
                .font(.system(.caption, design: .monospaced, weight: .black))
                .tracking(0.6)
                .foregroundStyle(PocketVectorTheme.championshipGlacier)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(
            PocketVectorTheme.championshipVoid.opacity(0.96),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(PocketVectorTheme.championshipSilver.opacity(0.86), lineWidth: 1.5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Three tutorial steps")
    }
}

private struct TutorialFilmFrame<Media: View>: View {
    let stage: TutorialStage
    let isActive: Bool
    let width: CGFloat
    let height: CGFloat
    let compact: Bool
    let expanded: Bool
    @ViewBuilder let media: Media

    @ScaledMetric(relativeTo: .headline) private var regularTitleSize: CGFloat = 14
    @ScaledMetric(relativeTo: .title3) private var expandedTitleSize: CGFloat = 20
    @ScaledMetric(relativeTo: .headline) private var regularNumberSize: CGFloat = 17
    @ScaledMetric(relativeTo: .title3) private var expandedNumberSize: CGFloat = 23

    var body: some View {
        let titleSize = compact ? 10 : (expanded ? expandedTitleSize : regularTitleSize)
        let numberSize = compact ? 13 : (expanded ? expandedNumberSize : regularNumberSize)
        let numberBoxSize = compact ? 25 : max(expanded ? 42 : 32, numberSize * 1.8)
        let headerHeight = compact ? 34 : max(expanded ? 54 : 42, numberBoxSize + 12)

        VStack(spacing: 0) {
            HStack(spacing: compact ? 5 : (expanded ? 10 : 7)) {
                Text(stage.number.formatted())
                    .font(.system(
                        size: numberSize,
                        weight: .black,
                        design: .monospaced
                    ))
                    .foregroundStyle(PocketVectorTheme.championshipStatus)
                    .frame(
                        width: numberBoxSize,
                        height: numberBoxSize
                    )
                    .overlay {
                        Rectangle()
                            .stroke(PocketVectorTheme.championshipStatus, lineWidth: 2)
                    }

                Text(stage.title.uppercased())
                    .font(.system(
                        size: titleSize,
                        weight: .black,
                        design: .monospaced
                    ))
                    .tracking(compact ? -0.6 : 0.2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.54)
                    .foregroundStyle(PocketVectorTheme.championshipGlacier)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, compact ? 6 : (expanded ? 13 : 9))
            .frame(height: headerHeight)
            .background(PocketVectorTheme.championshipVoid.opacity(0.98))

            media
                .frame(width: width, height: max(0, height - headerHeight))
                .clipped()
                .overlay {
                    LinearGradient(
                        colors: [.clear, PocketVectorTheme.championshipVoid.opacity(0.12)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .allowsHitTesting(false)
                }
        }
        .frame(width: width, height: height)
        .championshipPanel(isSelected: isActive)
        .animation(.easeInOut(duration: 0.15), value: isActive)
        .accessibilityHidden(true)
    }
}

private struct TutorialInstructionRail: View {
    let compact: Bool

    var body: some View {
        Text(
            "Start on the quarterback, drag to open grass away from defenders, "
                + "then release. The receiver runs under the throw."
        )
        .font(.system(
            compact ? .caption2 : .subheadline,
            design: .monospaced,
            weight: .bold
        ))
        .foregroundStyle(PocketVectorTheme.championshipGlacier)
        .multilineTextAlignment(.center)
        .lineLimit(compact ? 2 : 2)
        .minimumScaleFactor(0.72)
        .padding(.horizontal, compact ? 10 : 18)
        .frame(maxWidth: 1_040)
        .frame(minHeight: compact ? 36 : 48)
        .championshipPanel()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Passing demonstration")
        .accessibilityValue(
            "Step 1, Pick a spot. Step 2, Throw to it. Step 3, Avoid the defenders. "
                + "Start on the quarterback, drag to open grass away from defenders, "
                + "then release. The receiver runs under the throw."
        )
    }
}

private struct TutorialProgressLights: View {
    let activeStage: Int

    var body: some View {
        HStack(spacing: 11) {
            ForEach(0 ..< 3, id: \.self) { index in
                Circle()
                    .fill(
                        index == activeStage
                            ? PocketVectorTheme.championshipStatus
                            : PocketVectorTheme.championshipGraphite
                    )
                    .frame(width: index == activeStage ? 14 : 11, height: index == activeStage ? 14 : 11)
                    .overlay {
                        Circle()
                            .stroke(
                                index == activeStage
                                    ? PocketVectorTheme.championshipGlacier
                                    : PocketVectorTheme.championshipSteel,
                                lineWidth: 1.5
                            )
                    }
                    .shadow(
                        color: index == activeStage
                            ? PocketVectorTheme.championshipStatus.opacity(0.7)
                            : .clear,
                        radius: 4
                    )
            }
        }
        .frame(minWidth: 76, minHeight: 44)
        .accessibilityHidden(true)
    }
}

private struct TutorialPlayerSurface: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> TutorialPlayerView {
        let view = TutorialPlayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        return view
    }

    func updateUIView(_ uiView: TutorialPlayerView, context: Context) {
        uiView.playerLayer.player = player
    }
}

private struct TutorialGameplayPoster: View {
    let name: String

    private let sourceAspectRatio: CGFloat = 4 / 3

    var body: some View {
        GeometryReader { proxy in
            let targetAspectRatio = proxy.size.width / max(proxy.size.height, 1)
            let renderSize: CGSize = if targetAspectRatio >= sourceAspectRatio {
                CGSize(
                    width: proxy.size.width,
                    height: proxy.size.width / sourceAspectRatio
                )
            } else {
                CGSize(
                    width: proxy.size.height * sourceAspectRatio,
                    height: proxy.size.height
                )
            }

            Image(name)
                .resizable()
                .interpolation(.none)
                .frame(width: renderSize.width, height: renderSize.height)
                .position(
                    x: proxy.size.width / 2,
                    y: proxy.size.height - (renderSize.height / 2)
                )
        }
        .clipped()
    }
}

private final class TutorialPlayerView: UIView {
    let playerLayer = AVPlayerLayer()
    private let sourceAspectRatio: CGFloat = 4 / 3

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.addSublayer(playerLayer)
        layer.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        layer.addSublayer(playerLayer)
        layer.masksToBounds = true
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }

        let targetAspectRatio = bounds.width / bounds.height
        if targetAspectRatio >= sourceAspectRatio {
            let renderHeight = bounds.width / sourceAspectRatio
            playerLayer.frame = CGRect(
                x: 0,
                y: bounds.height - renderHeight,
                width: bounds.width,
                height: renderHeight
            )
        } else {
            let renderWidth = bounds.height * sourceAspectRatio
            playerLayer.frame = CGRect(
                x: (bounds.width - renderWidth) / 2,
                y: 0,
                width: renderWidth,
                height: bounds.height
            )
        }
    }
}

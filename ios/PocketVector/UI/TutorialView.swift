import AVFoundation
import Combine
import CryptoKit
import SwiftUI
import UIKit

enum TutorialPage: Int, CaseIterable {
    case gameRules
    case passing

    var number: Int { rawValue + 1 }

    var previous: TutorialPage? {
        TutorialPage(rawValue: rawValue - 1)
    }
}

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
    @State private var page: TutorialPage

    private let playbackClock = Timer.publish(
        every: 0.10,
        on: .main,
        in: .common
    )
    .autoconnect()

    private let stages = TutorialStage.allCases

    init(
        coordinator: AppCoordinator,
        initialPage: TutorialPage = .gameRules
    ) {
        self.coordinator = coordinator
        _page = State(initialValue: initialPage)
    }

    var body: some View {
        ChampionshipSubmenuScreen(
            title: "How to Play",
            onBack: coordinator.cancelTutorial,
            headerAccessory: {
                TutorialPageBadge(page: page)
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
                VStack(spacing: accessibleType ? 6 : 0) {
                    ScrollView {
                        pageContent(
                            width: contentWidth,
                            availableHeight: proxy.size.height,
                            compact: compact,
                            expanded: padLayout,
                            accessibleType: accessibleType,
                            spacing: stackSpacing
                        )
                        .frame(width: contentWidth)
                        .frame(
                            minHeight: accessibleType
                                ? nil
                                : proxy.size.height - (verticalInset * 2),
                            alignment: .center
                        )
                        .padding(.horizontal, horizontalInset)
                        .padding(.vertical, verticalInset)
                        .frame(maxWidth: .infinity)
                    }
                    .scrollBounceBehavior(.basedOnSize)

                    if accessibleType {
                        tutorialActions(
                            compact: true,
                            expanded: padLayout,
                            accessibleType: true
                        )
                        .padding(.horizontal, max(2, horizontalInset))
                        .padding(.bottom, 2)
                    }
                }
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
    private func pageContent(
        width: CGFloat,
        availableHeight: CGFloat,
        compact: Bool,
        expanded: Bool,
        accessibleType: Bool,
        spacing: CGFloat
    ) -> some View {
        VStack(spacing: spacing) {
            switch page {
            case .gameRules:
                gameRules(
                    width: width,
                    compact: compact,
                    expanded: expanded,
                    accessibleType: accessibleType
                )
            case .passing:
                passingLesson(
                    width: width,
                    availableHeight: availableHeight,
                    compact: compact,
                    expanded: expanded,
                    accessibleType: accessibleType,
                    spacing: spacing
                )
            }

            if !accessibleType {
                tutorialActions(
                    compact: compact,
                    expanded: expanded,
                    accessibleType: false
                )
            }
        }
    }

    @ViewBuilder
    private func gameRules(
        width: CGFloat,
        compact: Bool,
        expanded: Bool,
        accessibleType: Bool
    ) -> some View {
        let rules = TutorialRule.allCases

        if accessibleType {
            LazyVStack(spacing: 10) {
                ForEach(rules) { rule in
                    TutorialRuleCard(
                        rule: rule,
                        compact: false,
                        expanded: expanded,
                        accessibleType: true
                    )
                }
            }
        } else {
            let spacing: CGFloat = compact ? 6 : (expanded ? 14 : 10)
            let cardWidth = max(0, (width - (spacing * 2)) / 3)

            HStack(spacing: spacing) {
                ForEach(rules) { rule in
                    TutorialRuleCard(
                        rule: rule,
                        compact: compact,
                        expanded: expanded,
                        accessibleType: false
                    )
                        .frame(width: cardWidth)
                }
            }
            .frame(height: compact ? 180 : (expanded ? 460 : 280))
        }
    }

    @ViewBuilder
    private func passingLesson(
        width: CGFloat,
        availableHeight: CGFloat,
        compact: Bool,
        expanded: Bool,
        accessibleType: Bool,
        spacing: CGFloat
    ) -> some View {
        if accessibleType {
            LazyVStack(spacing: 10) {
                ForEach(stages) { stage in
                    AccessibleTutorialStep(stage: stage, isActive: playbackStage == stage.index) {
                        tutorialMedia(for: stage)
                    }
                }

                TutorialInstructionRail(compact: false, accessibleType: true)
            }
        } else {
            let filmHeight: CGFloat =
                compact
                ? 160
                : (expanded
                    ? min(520, availableHeight * 0.63)
                    : min(330, availableHeight * 0.66))

            filmstrip(
                width: width,
                height: filmHeight,
                compact: compact,
                expanded: expanded
            )

            TutorialInstructionRail(compact: compact, accessibleType: false)
        }
    }

    @ViewBuilder
    private func filmstrip(
        width: CGFloat,
        height: CGFloat,
        compact: Bool,
        expanded: Bool
    ) -> some View {
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
            reducesMotion: reducesMotion,
            width: width,
            height: height,
            compact: compact,
            expanded: expanded
        ) {
            tutorialMedia(for: stage)
        }
    }

    @ViewBuilder
    private func tutorialMedia(for stage: TutorialStage) -> some View {
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

    private func tutorialImage(named name: String) -> some View {
        TutorialGameplayPoster(name: name)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func tutorialActions(
        compact: Bool,
        expanded: Bool,
        accessibleType: Bool
    ) -> some View {
        if page == .gameRules {
            Button {
                page = .passing
            } label: {
                HStack(spacing: 8) {
                    Text("NEXT: PASSING")
                        .lineLimit(1)
                    ChampionshipPixelIcon(
                        name: "SubmenuForwardIcon",
                        size: accessibleType ? 22 : (compact ? 22 : 28)
                    )
                }
                .font(
                    accessibleType
                        ? .system(.headline, design: .monospaced, weight: .black)
                        : .system(
                            size: compact ? 17 : 20,
                            weight: .black,
                            design: .monospaced
                        )
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(ChampionshipPrimaryButtonStyle(compact: true))
            .frame(maxWidth: accessibleType ? .infinity : (expanded ? 420 : 330))
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityHint("Shows the passing gesture lesson")
        } else {
            transport(
                compact: compact,
                expanded: expanded,
                accessibleType: accessibleType
            )
        }
    }

    @ViewBuilder
    private func transport(
        compact: Bool,
        expanded: Bool,
        accessibleType: Bool
    ) -> some View {
        let previousWidth: CGFloat = compact ? 132 : (expanded ? 240 : 190)
        let replayWidth: CGFloat = compact ? 150 : (expanded ? 260 : 210)
        let completionWidth: CGFloat = compact ? 190 : (expanded ? 310 : 270)

        if accessibleType {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    previousButton(
                        compact: compact,
                        expanded: expanded,
                        accessibleType: true
                    )
                    .frame(maxWidth: .infinity)

                    replayButton(
                        compact: compact,
                        expanded: expanded,
                        accessibleType: true
                    )
                    .frame(maxWidth: .infinity)
                }

                completionButton(
                    compact: compact,
                    expanded: expanded,
                    accessibleType: true
                )
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
        } else {
            HStack(spacing: compact ? 8 : 12) {
                previousButton(
                    compact: compact,
                    expanded: expanded,
                    accessibleType: false
                )
                .frame(width: previousWidth)

                replayButton(
                    compact: compact,
                    expanded: expanded,
                    accessibleType: false
                )
                .frame(width: replayWidth)

                TutorialProgressLights(activeStage: playbackStage)
                    .frame(maxWidth: .infinity)

                completionButton(
                    compact: compact,
                    expanded: expanded,
                    accessibleType: false
                )
                .frame(width: completionWidth)
            }
            .frame(maxWidth: expanded ? 1_180 : 980)
            .frame(maxWidth: .infinity)
        }
    }

    private func previousButton(
        compact: Bool,
        expanded: Bool,
        accessibleType: Bool
    ) -> some View {
        Button(action: showRules) {
            HStack(spacing: compact ? 6 : 9) {
                if !accessibleType {
                    ChampionshipPixelIcon(
                        name: "SubmenuBackIcon",
                        size: compact ? 22 : (expanded ? 34 : 28)
                    )
                }
                Text("PREVIOUS")
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(ChampionshipSecondaryButtonStyle())
        .accessibilityHint("Returns to the tutorial rules")
    }

    private func replayButton(
        compact: Bool,
        expanded: Bool,
        accessibleType: Bool
    ) -> some View {
        Button(action: replayDemo) {
            HStack(spacing: compact ? 6 : 9) {
                if !accessibleType {
                    ChampionshipPixelIcon(
                        name: "SubmenuPlayIcon",
                        size: compact ? 22 : (expanded ? 34 : 28)
                    )
                }
                Text("REPLAY")
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(ChampionshipSecondaryButtonStyle())
        .disabled(!mediaIsReady)
        .accessibilityLabel("Replay passing demonstration")
        .accessibilityHint("Plays the complete tutorial animation from the beginning")
    }

    private func completionButton(
        compact: Bool,
        expanded: Bool,
        accessibleType: Bool
    ) -> some View {
        Button {
            Task { await coordinator.completeTutorial() }
        } label: {
            HStack(spacing: compact ? 6 : 9) {
                Text(completionTitle.uppercased())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if !accessibleType {
                    ChampionshipPixelIcon(
                        name: completionTitle == "Start Run"
                            ? "SubmenuPlayIcon"
                            : "SubmenuForwardIcon",
                        size: compact ? 22 : (expanded ? 34 : 28)
                    )
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(ChampionshipPrimaryButtonStyle(compact: compact))
        .accessibilityHint(completionHint)
        .disabled(coordinator.isRequestInFlight)
    }

    private func showRules() {
        guard let previousPage = page.previous else { return }
        player.pause()
        page = previousPage
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
            let mediaURL = try TutorialMediaCache.validatedURL(
                for: dataAsset.data,
                directory: directory
            )

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

enum TutorialRule: Int, CaseIterable, Identifiable {
    case clock
    case scoring
    case adrenaline

    var id: Int { rawValue }

    var eyebrow: String {
        switch self {
        case .clock: "THE CLOCK"
        case .scoring: "SCORING"
        case .adrenaline: "ADRENALINE"
        }
    }

    var display: String {
        switch self {
        case .clock: "60"
        case .scoring: "−250"
        case .adrenaline: "100"
        }
    }

    var displayCaption: String {
        switch self {
        case .clock: "SECOND RUN"
        case .scoring: "INTERCEPTION"
        case .adrenaline: "BONUS READY"
        }
    }

    var guidance: String {
        switch self {
        case .clock:
            "Score as many points as you can before the game clock reaches zero."
        case .scoring:
            "Completions and touchdowns add points. An interception is a −250-point penalty, but your score cannot fall below zero."
        case .adrenaline:
            "Completions fill Adrenaline for a touchdown bonus. The TD multiplier resets only after an incompletion or interception."
        }
    }

    var accessibilityValue: String {
        "\(displayCaption). \(guidance)"
    }
}

private struct TutorialPageBadge: View {
    let page: TutorialPage

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: 7) {
            if !dynamicTypeSize.isAccessibilitySize {
                ForEach(TutorialPage.allCases.indices, id: \.self) { index in
                    Circle()
                        .fill(
                            index == page.rawValue
                                ? PocketVectorTheme.championshipStatus
                                : PocketVectorTheme.championshipGraphite
                        )
                        .frame(width: 7, height: 7)
                }
            }

            Text(
                dynamicTypeSize.isAccessibilitySize
                    ? "\(page.number)/2"
                    : "\(page.number) OF 2"
            )
                .font(.system(.caption2, design: .monospaced, weight: .black))
                .tracking(0.6)
                .foregroundStyle(PocketVectorTheme.championshipGlacier)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: true)
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
        .accessibilityLabel("Tutorial page \(page.number) of 2")
    }
}

private struct TutorialRuleCard: View {
    let rule: TutorialRule
    let compact: Bool
    let expanded: Bool
    let accessibleType: Bool

    var body: some View {
        VStack(spacing: accessibleType ? 10 : (compact ? 5 : 10)) {
            Text(rule.eyebrow)
                .font(
                    .system(
                        accessibleType
                            ? .headline
                            : (compact ? .caption2 : (expanded ? .title2 : .headline)),
                        design: .monospaced,
                        weight: .black
                    )
                )
                .tracking(accessibleType ? 0.4 : 1)
                .foregroundStyle(PocketVectorTheme.championshipSilver)
                .frame(maxWidth: .infinity)

            VStack(spacing: compact ? 0 : 2) {
                Text(rule.display)
                    .font(
                        .system(
                            size: accessibleType ? 48 : (compact ? 48 : (expanded ? 104 : 72)),
                            weight: .black,
                            design: .monospaced
                        )
                    )
                    .tracking(-2)
                    .foregroundStyle(
                        rule == .scoring
                            ? PocketVectorTheme.warning
                            : PocketVectorTheme.championshipGlacier
                    )
                    .shadow(color: .black.opacity(0.9), radius: 0, x: 3, y: 3)

                Text(rule.displayCaption)
                    .font(
                        .system(
                            accessibleType
                                ? .subheadline
                                : (compact ? .caption2 : (expanded ? .title3 : .subheadline)),
                            design: .monospaced,
                            weight: .black
                        )
                    )
                    .foregroundStyle(
                        rule == .adrenaline
                            ? PocketVectorTheme.championshipStatus
                            : PocketVectorTheme.gold
                    )
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)

            Rectangle()
                .fill(PocketVectorTheme.championshipSteel.opacity(0.7))
                .frame(height: 1)

            Text(rule.guidance)
                .font(
                    .system(
                        accessibleType
                            ? .body
                            : (compact ? .caption2 : (expanded ? .title3 : .subheadline)),
                        design: .monospaced,
                        weight: .bold
                    )
                )
                .foregroundStyle(PocketVectorTheme.championshipGlacier)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(compact ? 9 : (expanded ? 24 : 16))
        .frame(maxWidth: .infinity, maxHeight: accessibleType ? nil : .infinity)
        .championshipPanel(isSelected: rule == .adrenaline)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(
                    rule == .scoring
                        ? PocketVectorTheme.warning
                        : PocketVectorTheme.championshipStatus
                )
                .frame(height: 3)
                .padding(.horizontal, 9)
                .padding(.top, 5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rule.eyebrow)
        .accessibilityValue(rule.accessibilityValue)
    }
}

private struct AccessibleTutorialStep<Media: View>: View {
    let stage: TutorialStage
    let isActive: Bool
    @ViewBuilder let media: Media

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(stage.number.formatted())
                    .font(.system(.headline, design: .monospaced, weight: .black))
                    .foregroundStyle(PocketVectorTheme.championshipStatus)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .overlay {
                        Rectangle()
                            .stroke(PocketVectorTheme.championshipStatus, lineWidth: 2)
                    }

                Text(stage.title.uppercased())
                    .font(.system(.headline, design: .monospaced, weight: .black))
                    .foregroundStyle(PocketVectorTheme.championshipGlacier)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(10)

            media
                .frame(maxWidth: .infinity)
                .frame(height: 140)
                .clipped()
                .accessibilityHidden(true)
        }
        .championshipPanel(isSelected: isActive)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(stage.number), \(stage.title)")
    }
}

private struct TutorialFilmFrame<Media: View>: View {
    let stage: TutorialStage
    let isActive: Bool
    let reducesMotion: Bool
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
        .animation(
            reducesMotion ? nil : .easeInOut(duration: 0.15),
            value: isActive
        )
        .accessibilityHidden(true)
    }
}

private struct TutorialInstructionRail: View {
    let compact: Bool
    let accessibleType: Bool

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
        .lineLimit(accessibleType ? nil : 2)
        .minimumScaleFactor(accessibleType ? 1 : 0.72)
        .fixedSize(horizontal: false, vertical: accessibleType)
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

enum TutorialMediaCache {
    private static let fileName = "tutorial-pass-run-under-v1.mp4"

    static func validatedURL(for data: Data, directory: URL) throws -> URL {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let mediaURL = directory.appendingPathComponent(fileName)
        if !fileMatches(at: mediaURL, expectedData: data) {
            try data.write(to: mediaURL, options: .atomic)
        }
        return mediaURL
    }

    static func fileMatches(at url: URL, expectedData: Data) -> Bool {
        guard let existingData = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            return false
        }
        return SHA256.hash(data: existingData) == SHA256.hash(data: expectedData)
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

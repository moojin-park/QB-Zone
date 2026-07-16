import SwiftUI

@MainActor
struct TutorialView: View {
    @Bindable var coordinator: AppCoordinator
    @Environment(\.accessibilityReduceMotion) private var systemReducedMotion
    @State private var selectedStep = 0

    private let steps = TutorialStep.launch

    var body: some View {
        PocketVectorScreen(
            title: "How to Play",
            subtitle: "Step \(selectedStep + 1) of \(steps.count)",
            onBack: coordinator.cancelTutorial
        ) {
            VStack(spacing: 12) {
                ProgressView(value: Double(selectedStep + 1), total: Double(steps.count))
                    .tint(PocketVectorTheme.cyan)
                    .padding(.horizontal)
                    .accessibilityLabel("Tutorial progress")
                    .accessibilityValue("Step \(selectedStep + 1) of \(steps.count)")

                ScrollView {
                    TutorialStepCard(step: steps[selectedStep])
                        .id(steps[selectedStep].id)
                        .frame(maxWidth: 760)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                        .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.basedOnSize)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        leadingControl
                        Spacer(minLength: 8)
                        trailingControl
                    }
                    VStack(spacing: 8) {
                        trailingControl
                            .frame(maxWidth: .infinity)
                        leadingControl
                            .frame(maxWidth: .infinity)
                    }
                }
                .font(.headline)
                .padding(.horizontal)
                .padding(.bottom, 10)
            }
        }
    }

    private var completionTitle: String {
        if case .tutorial(.beforeRun) = coordinator.currentDestination {
            return "Start Run"
        }
        return "Finish Review"
    }

    private var completionIcon: String {
        if case .tutorial(.beforeRun) = coordinator.currentDestination {
            return "play.fill"
        }
        return "checkmark"
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

    private func move(to step: Int) {
        let update = {
            selectedStep = min(max(0, step), steps.count - 1)
        }
        if reducesMotion {
            update()
        } else {
            withAnimation(.easeInOut(duration: 0.16), update)
        }
    }

    @ViewBuilder
    private var leadingControl: some View {
        if selectedStep > 0 {
            Button {
                move(to: selectedStep - 1)
            } label: {
                Label("Previous", systemImage: "chevron.left")
            }
            .buttonStyle(.bordered)
            .tint(PocketVectorTheme.cyan)
        }
    }

    @ViewBuilder
    private var trailingControl: some View {
        if selectedStep < steps.count - 1 {
            Button {
                move(to: selectedStep + 1)
            } label: {
                Label("Next", systemImage: "chevron.right")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderedProminent)
            .tint(PocketVectorTheme.cyan)
            .foregroundStyle(PocketVectorTheme.void)
        } else {
            Button {
                Task { await coordinator.completeTutorial() }
            } label: {
                Label(completionTitle, systemImage: completionIcon)
            }
            .buttonStyle(.borderedProminent)
            .tint(PocketVectorTheme.cyan)
            .foregroundStyle(PocketVectorTheme.void)
            .accessibilityHint(completionHint)
            .disabled(coordinator.isRequestInFlight)
        }
    }
}

private struct TutorialStepCard: View {
    let step: TutorialStep

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: step.systemImage)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(PocketVectorTheme.cyan)
                    .frame(width: 54, height: 54)
                    .background(PocketVectorTheme.raisedSurface, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(step.eyebrow.uppercased())
                        .font(.caption.weight(.black))
                        .tracking(0.8)
                        .foregroundStyle(PocketVectorTheme.cyan)
                    Text(step.title)
                        .font(.title.weight(.black))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text(step.summary)
                .font(.title3.weight(.semibold))
                .foregroundStyle(PocketVectorTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(step.points, id: \.self) { point in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 7))
                            .foregroundStyle(PocketVectorTheme.gold)
                            .accessibilityHidden(true)
                        Text(point)
                            .font(.body)
                            .foregroundStyle(PocketVectorTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pocketVectorPanel()
        .accessibilityElement(children: .combine)
    }
}

private struct TutorialStep: Identifiable, Sendable {
    let id: String
    let eyebrow: String
    let title: String
    let systemImage: String
    let summary: String
    let points: [String]

    static let launch: [TutorialStep] = [
        TutorialStep(
            id: "throw",
            eyebrow: "The gesture",
            title: "Swipe Upfield to Throw",
            systemImage: "hand.draw.fill",
            summary: "Touch the quarterback, drag upfield, and release where you want the football to arrive.",
            points: [
                "Aim ahead of a moving receiver instead of at where the receiver started.",
                "A quick release produces a flatter, faster pass; a slower swipe creates a higher lob.",
            ]
        ),
        TutorialStep(
            id: "lanes",
            eyebrow: "Read the field",
            title: "Find Space in Four Lanes",
            systemImage: "point.3.connected.trianglepath.dotted",
            summary: "Receivers cross the field at four depths while defenders patrol between them.",
            points: [
                "Lead a receiver horizontally and release before the passing window closes.",
                "The farthest lane is the end zone. A catch there scores a touchdown.",
            ]
        ),
        TutorialStep(
            id: "score",
            eyebrow: "Build a big run",
            title: "Score Before Time Expires",
            systemImage: "timer",
            summary: "You have 60 seconds of gameplay time to complete passes and stack points.",
            points: [
                "Short, medium, and deep completions build the Adrenaline / TD Bonus meter.",
                "Fill the meter, then land a touchdown to cash the bonus. A miss or interception resets the meter.",
            ]
        ),
        TutorialStep(
            id: "controls",
            eyebrow: "Play your way",
            title: "Pause, Mute, and Adjust",
            systemImage: "slider.horizontal.3",
            summary: "Use the HUD controls to pause or mute without changing the rules of the run.",
            points: [
                "Music, sound effects, and Reduced Motion can be adjusted in Settings.",
                "Pocket Vector also respects the device’s Reduce Motion preference.",
            ]
        ),
    ]
}

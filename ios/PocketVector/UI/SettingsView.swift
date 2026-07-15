import SwiftUI

@MainActor
struct SettingsView: View {
    @Bindable var coordinator: AppCoordinator

    var body: some View {
        PocketVectorScreen(
            title: "Settings",
            subtitle: "Adjust audio, motion, and tutorial preferences.",
            onBack: coordinator.goBack
        ) {
            ScrollView {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        audioPanel
                        playPanel
                    }
                    VStack(spacing: 16) {
                        audioPanel
                        playPanel
                    }
                }
                .frame(maxWidth: 980)
                .padding(.horizontal)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var audioPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Audio", systemImage: "speaker.wave.2.fill")
                .font(.title2.weight(.bold))

            Toggle(
                "Mute all audio",
                isOn: Binding(
                    get: { coordinator.state.settings.isMuted },
                    set: { value in
                        Task { await coordinator.setMuted(value) }
                    }
                )
            )
            .tint(PocketVectorTheme.cyan)

            VolumeControl(
                title: "Music",
                systemImage: "music.note",
                value: coordinator.state.settings.musicVolume,
                onCommit: { value in
                    Task { await coordinator.setMusicVolume(value) }
                }
            )
            .disabled(coordinator.state.settings.isMuted)
            .opacity(coordinator.state.settings.isMuted ? 0.58 : 1)

            VolumeControl(
                title: "Sound effects",
                systemImage: "waveform",
                value: coordinator.state.settings.sfxVolume,
                onCommit: { value in
                    Task { await coordinator.setSFXVolume(value) }
                }
            )
            .disabled(coordinator.state.settings.isMuted)
            .opacity(coordinator.state.settings.isMuted ? 0.58 : 1)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pocketVectorPanel()
    }

    private var playPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Play", systemImage: "figure.run")
                .font(.title2.weight(.bold))

            Toggle(
                "Reduce motion",
                isOn: Binding(
                    get: { coordinator.state.settings.reducedMotion },
                    set: { value in
                        Task { await coordinator.setReducedMotion(value) }
                    }
                )
            )
            .tint(PocketVectorTheme.cyan)
            .accessibilityHint("Reduces animation in menus and gameplay")

            Divider()
                .overlay(PocketVectorTheme.border.opacity(0.5))

            Toggle(
                "Show tutorial before next run",
                isOn: Binding(
                    get: { !coordinator.state.settings.tutorialCompleted },
                    set: { value in
                        Task { await coordinator.setTutorialEnabled(value) }
                    }
                )
            )
            .tint(PocketVectorTheme.cyan)

            Text("Turn this on whenever you want to review the controls before playing.")
                .font(.caption)
                .foregroundStyle(PocketVectorTheme.textSecondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pocketVectorPanel()
    }
}

private struct VolumeControl: View {
    let title: String
    let systemImage: String
    let value: Double
    let onCommit: (Double) -> Void
    @State private var draftValue: Double

    init(
        title: String,
        systemImage: String,
        value: Double,
        onCommit: @escaping (Double) -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.value = value
        self.onCommit = onCommit
        _draftValue = State(initialValue: value)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                Text("\(Int((draftValue * 100).rounded()))%")
                    .monospacedDigit()
                    .foregroundStyle(PocketVectorTheme.textSecondary)
            }
            .font(.headline)

            Slider(
                value: $draftValue,
                in: 0 ... 1,
                step: 0.05,
                onEditingChanged: { isEditing in
                    if !isEditing {
                        onCommit(draftValue)
                    }
                }
            )
                .tint(PocketVectorTheme.cyan)
                .accessibilityLabel(title)
                .accessibilityValue("\(Int((draftValue * 100).rounded())) percent")
        }
        .onChange(of: value) { _, newValue in
            draftValue = newValue
        }
    }
}

import SwiftUI

@MainActor
struct SettingsView: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @Bindable var coordinator: AppCoordinator

    private var expandedLayout: Bool {
        verticalSizeClass == .regular
    }

    var body: some View {
        ChampionshipSubmenuScreen(
            title: "Settings",
            subtitle: "Adjust audio, motion, and tutorial preferences.",
            onBack: coordinator.goBack
        ) {
            ScrollView {
                HStack(alignment: .top, spacing: 12) {
                    audioPanel
                    playPanel
                }
                .frame(maxWidth: expandedLayout ? 1180 : 980)
                .padding(.horizontal)
                .padding(.vertical, expandedLayout ? 64 : 0)
                .padding(.bottom, expandedLayout ? 32 : 16)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var audioPanel: some View {
        VStack(alignment: .leading, spacing: expandedLayout ? 26 : 18) {
            SettingsPanelHeader(
                title: "Audio",
                iconName: "SettingsAudioIcon",
                expanded: expandedLayout
            )

            Toggle(
                "Mute all audio",
                isOn: Binding(
                    get: { coordinator.state.settings.isMuted },
                    set: { value in
                        Task { await coordinator.setMuted(value) }
                    }
                )
            )
            .tint(PocketVectorTheme.championshipStatus)

            VolumeControl(
                title: "Music",
                iconName: "SettingsMusicIcon",
                value: coordinator.state.settings.musicVolume,
                expanded: expandedLayout,
                onCommit: { value in
                    Task { await coordinator.setMusicVolume(value) }
                }
            )
            .disabled(coordinator.state.settings.isMuted)
            .opacity(coordinator.state.settings.isMuted ? 0.58 : 1)

            VolumeControl(
                title: "Sound effects",
                iconName: "SettingsSFXIcon",
                value: coordinator.state.settings.sfxVolume,
                expanded: expandedLayout,
                onCommit: { value in
                    Task { await coordinator.setSFXVolume(value) }
                }
            )
            .disabled(coordinator.state.settings.isMuted)
            .opacity(coordinator.state.settings.isMuted ? 0.58 : 1)
        }
        .padding(expandedLayout ? 26 : 18)
        .frame(
            maxWidth: .infinity,
            minHeight: expandedLayout ? 470 : nil,
            alignment: .leading
        )
        .championshipPanel()
    }

    private var playPanel: some View {
        VStack(alignment: .leading, spacing: expandedLayout ? 26 : 18) {
            SettingsPanelHeader(
                title: "Play",
                iconName: "SettingsGameplayIcon",
                expanded: expandedLayout
            )

            Toggle(
                "Reduce motion",
                isOn: Binding(
                    get: { coordinator.state.settings.reducedMotion },
                    set: { value in
                        Task { await coordinator.setReducedMotion(value) }
                    }
                )
            )
            .tint(PocketVectorTheme.championshipStatus)
            .accessibilityHint("Reduces animation in menus and gameplay")

            Divider()
                .overlay(PocketVectorTheme.border.opacity(0.5))

            Button {
                coordinator.showTutorialReview()
            } label: {
                HStack(spacing: 9) {
                    ChampionshipPixelIcon(name: "SettingsTutorialIcon", size: 28)
                    Text("REVIEW HOW TO PLAY")
                }
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(ChampionshipSecondaryButtonStyle())
            .accessibilityHint("Opens the four-step gameplay tutorial")

            Text(tutorialStatusText)
                .font(.caption)
                .foregroundStyle(PocketVectorTheme.textSecondary)

            Divider()
                .overlay(PocketVectorTheme.border.opacity(0.5))

            Button {
                coordinator.showPrivacySupport()
            } label: {
                HStack(spacing: 9) {
                    ChampionshipPixelIcon(name: "SettingsPrivacySupportIcon", size: 28)
                    Text("PRIVACY & SUPPORT")
                }
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(ChampionshipSecondaryButtonStyle())
            .accessibilityHint("Shows support contacts and feature disclosures")
        }
        .padding(expandedLayout ? 26 : 18)
        .frame(
            maxWidth: .infinity,
            minHeight: expandedLayout ? 470 : nil,
            alignment: .leading
        )
        .championshipPanel()
    }

    private var tutorialStatusText: String {
        coordinator.state.settings.tutorialCompleted
            ? "The first-run tutorial is complete. You can review it without changing your progress."
            : "The tutorial is required before your first gameplay run. Leaving it early will not mark it complete."
    }
}

private struct VolumeControl: View {
    let title: String
    let iconName: String
    let value: Double
    let expanded: Bool
    let onCommit: (Double) -> Void
    @State private var draftValue: Double

    init(
        title: String,
        iconName: String,
        value: Double,
        expanded: Bool,
        onCommit: @escaping (Double) -> Void
    ) {
        self.title = title
        self.iconName = iconName
        self.value = value
        self.expanded = expanded
        self.onCommit = onCommit
        _draftValue = State(initialValue: value)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                HStack(spacing: 7) {
                    ChampionshipPixelIcon(name: iconName, size: expanded ? 36 : 28)
                    Text(title)
                }
                Spacer()
                Text("\(Int((draftValue * 100).rounded()))%")
                    .monospacedDigit()
                    .foregroundStyle(PocketVectorTheme.textSecondary)
            }
            .font(expanded ? .title3 : .headline)

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
                .tint(PocketVectorTheme.championshipStatus)
                .accessibilityLabel(title)
                .accessibilityValue("\(Int((draftValue * 100).rounded())) percent")
        }
        .onChange(of: value) { _, newValue in
            draftValue = newValue
        }
    }
}

private struct SettingsPanelHeader: View {
    let title: String
    let iconName: String
    let expanded: Bool

    var body: some View {
        HStack(spacing: 10) {
            ChampionshipPixelIcon(name: iconName, size: expanded ? 56 : 42)
            Text(title.uppercased())
                .font(.system(expanded ? .title2 : .title3, design: .monospaced, weight: .black))
                .tracking(0.7)
        }
    }
}

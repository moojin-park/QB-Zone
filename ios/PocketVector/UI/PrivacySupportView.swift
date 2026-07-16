import SwiftUI

@MainActor
struct PrivacySupportView: View {
    @Bindable var coordinator: AppCoordinator

    private var configuration: PrivacySupportConfiguration {
        coordinator.privacySupportConfiguration
    }

    var body: some View {
        PocketVectorScreen(
            title: "Privacy & Support",
            subtitle: "Review contact links and how optional platform features handle game data.",
            onBack: coordinator.goBack
        ) {
            ScrollView {
                VStack(spacing: 16) {
                    configurationStatus

                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 16) {
                            contactPanel
                            disclosuresPanel
                        }
                        VStack(spacing: 16) {
                            contactPanel
                            disclosuresPanel
                        }
                    }
                }
                .frame(maxWidth: 1040)
                .padding(.horizontal)
                .padding(.bottom, 18)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    @ViewBuilder
    private var configurationStatus: some View {
        if configuration.isReleaseContactConfigurationComplete {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.title2)
                    .foregroundStyle(PocketVectorTheme.success)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Contact links configured")
                        .font(.headline.weight(.bold))
                    Text("Links open only after you choose them.")
                        .font(.caption)
                        .foregroundStyle(PocketVectorTheme.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .pocketVectorPanel()
            .accessibilityElement(children: .combine)
        } else {
            VStack(alignment: .leading, spacing: 9) {
                Label("Release setup incomplete", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(PocketVectorTheme.warning)

                Text("App Store release is blocked until each contact destination below is configured and validated.")
                    .font(.subheadline)
                    .foregroundStyle(PocketVectorTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(configuration.issues) { issue in
                    Label(issue.message, systemImage: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(PocketVectorTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PocketVectorTheme.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(PocketVectorTheme.warning.opacity(0.8), lineWidth: 1)
            }
        }
    }

    private var contactPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(configuration.appInformation.appName)
                    .font(.title2.weight(.black))
                Text(configuration.appInformation.versionAndBuildText)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(PocketVectorTheme.textSecondary)
            }
            .accessibilityElement(children: .combine)

            Divider()
                .overlay(PocketVectorTheme.border.opacity(0.5))

            ExternalDestinationRow(
                title: "Privacy Policy",
                detail: configuration.privacyPolicyURL?.host()
                    ?? "Not configured for this build",
                systemImage: "hand.raised.fill",
                actionTitle: "Open Privacy Policy",
                destination: configuration.privacyPolicyURL
            )

            ExternalDestinationRow(
                title: "Support Website",
                detail: configuration.supportURL?.host()
                    ?? "Not configured for this build",
                systemImage: "safari.fill",
                actionTitle: "Open Support Website",
                destination: configuration.supportURL
            )

            ExternalDestinationRow(
                title: "Email Support",
                detail: configuration.supportEmail
                    ?? "Not configured for this build",
                systemImage: "envelope.fill",
                actionTitle: "Compose Support Email",
                destination: configuration.supportEmailURL
            )
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pocketVectorPanel()
    }

    private var disclosuresPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Feature Disclosures", systemImage: "checklist")
                .font(.title2.weight(.bold))

            DisclosureRow(
                title: "Saved game data",
                status: "On device",
                isConfigured: true,
                detail: "Pocket Vector saves settings, scores, team selections, unlocks, coins, and achievement progress on this device."
            )

            DisclosureRow(
                title: "iCloud",
                status: serviceStatus(configuration.services.iCloudSyncIsConfigured),
                isConfigured: configuration.services.iCloudSyncIsConfigured,
                detail: configuration.services.iCloudSyncIsConfigured
                    ? "Private iCloud profile sync is configured. Availability still depends on the player’s account and network."
                    : "Private iCloud profile sync is not configured in this build; progress remains on this device."
            )

            DisclosureRow(
                title: "Game Center",
                status: serviceStatus(configuration.services.gameCenterIsConfigured),
                isConfigured: configuration.services.gameCenterIsConfigured,
                detail: configuration.services.gameCenterIsConfigured
                    ? "Game Center is configured for achievements and the global high score after player authentication."
                    : "Game Center submission is not configured in this build."
            )

            DisclosureRow(
                title: "Coin purchases",
                status: serviceStatus(configuration.services.purchasesAreConfigured),
                isConfigured: configuration.services.purchasesAreConfigured,
                detail: configuration.services.purchasesAreConfigured
                    ? "Coin packs are configured through Apple in-app purchase. Coins unlock cosmetics and do not remove ads."
                    : "Coin purchases are not configured in this build."
            )

            DisclosureRow(
                title: "Rewarded ads",
                status: serviceStatus(configuration.services.rewardedAdsAreConfigured),
                isConfigured: configuration.services.rewardedAdsAreConfigured,
                detail: configuration.services.rewardedAdsAreConfigured
                    ? "Only optional rewarded ads are configured. Pocket Vector does not use forced or banner ads."
                    : "Rewarded ads are not configured in this build. No forced or banner ads are used."
            )
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pocketVectorPanel()
    }

    private func serviceStatus(_ isConfigured: Bool) -> String {
        isConfigured ? "Configured" : "Not configured"
    }
}

private struct ExternalDestinationRow: View {
    let title: String
    let detail: String
    let systemImage: String
    let actionTitle: String
    let destination: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.headline.weight(.bold))

            Text(detail)
                .font(.caption)
                .foregroundStyle(PocketVectorTheme.textSecondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            if let destination {
                Link(destination: destination) {
                    Label(actionTitle, systemImage: "arrow.up.right.square")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(PocketVectorTheme.cyan)
                .accessibilityHint("Opens an external destination after activation")
            } else {
                Button(actionTitle) {}
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                    .disabled(true)
                    .accessibilityHint("Unavailable because this release destination is not configured")
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct DisclosureRow: View {
    let title: String
    let status: String
    let isConfigured: Bool
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.headline.weight(.bold))
                    Spacer(minLength: 8)
                    statusPill
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.headline.weight(.bold))
                    statusPill
                }
            }

            Text(detail)
                .font(.caption)
                .foregroundStyle(PocketVectorTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var statusPill: some View {
        StatusPill(
            text: status,
            color: isConfigured ? PocketVectorTheme.success : PocketVectorTheme.warning
        )
    }
}

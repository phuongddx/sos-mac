import SwiftUI
import AppKit
import CleanCore

/// Matches `updater.html`: a per-app list with an icon, installed → latest
/// version, and a status badge. Read-only Sparkle appcast monitoring per
/// README — there is no "install update"/"Update All" action here, only
/// detection/display (the "View in App Store" link is a pre-existing
/// external deep-link, not an install action, so it stays).
struct UpdaterView: View {
    @State private var viewModel = UpdaterViewModel()

    var body: some View {
        Group {
            if viewModel.rows.isEmpty {
                emptyState
            } else {
                content
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .auroraBloom()
        .navigationTitle("Updater")
        .task {
            viewModel.loadApps()
            await viewModel.checkAll()
        }
    }

    // MARK: - Idle / no apps detected

    private var emptyState: some View {
        EmptyStateView(
            systemImage: "arrow.triangle.2.circlepath",
            title: "Looking for installed applications",
            message: "Scanning your Mac for installed apps and checking their versions. If nothing turns up, try checking again.",
            hue: Theme.hue(for: .updater),
            actionTitle: "Check Again"
        ) {
            viewModel.loadApps()
            Task { await viewModel.checkAll() }
        }
    }

    // MARK: - Populated list

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                header
                if isCheckingAny {
                    if let progress = viewModel.progressTracker.progress {
                        ScanProgressPanel(progress: progress, showCurrentPath: true)
                    } else {
                        // Brief window between checkAll() starting and the
                        // first row finishing, before progressTracker has
                        // anything to report yet.
                        StepRowView(name: "Checking for updates…", meta: nil, state: .active)
                    }
                } else if !viewModel.hasAnyUpdate {
                    Text("No Sparkle-based updates pending")
                        .font(.system(size: Theme.TextSize.sm))
                        .foregroundStyle(Theme.muted)
                }
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(viewModel.rows) { row in
                        rowView(row)
                    }
                }
            }
            .padding(Theme.Spacing.xxxl)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Updater")
                    .font(.system(size: Theme.TextSize.xl, weight: .semibold))
                    .foregroundStyle(Theme.foreground)
                Text(headerMeta)
                    .font(.system(size: Theme.TextSize.sm))
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
            Button("Check Again") {
                Task { await viewModel.checkAll() }
            }
            .buttonStyle(.bordered)
            .tint(Theme.accent)
            .disabled(viewModel.isCheckingAll)
        }
    }

    private var headerMeta: String {
        switch updatesAvailableCount {
        case 0: return "All applications up to date"
        case 1: return "1 update available"
        default: return "\(updatesAvailableCount) updates available"
        }
    }

    private var isCheckingAny: Bool {
        viewModel.rows.contains { $0.isChecking }
    }

    private var updatesAvailableCount: Int {
        viewModel.rows.filter(viewModel.isUpdateAvailable).count
    }

    // MARK: - Row

    @ViewBuilder
    private func rowView(_ row: UpdaterViewModel.AppUpdateRow) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            appIcon(for: row.app)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.app.name)
                    .font(.system(size: Theme.TextSize.sm, weight: .semibold))
                    .foregroundStyle(Theme.foreground)
                versionText(for: row)
            }

            Spacer(minLength: Theme.Spacing.md)

            statusView(for: row)
        }
        .careCard()
    }

    @ViewBuilder
    private func versionText(for row: UpdaterViewModel.AppUpdateRow) -> some View {
        if let installed = row.app.version {
            if viewModel.isUpdateAvailable(row), let latest = row.latestVersion {
                Text("\(installed) → \(latest)")
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(Theme.muted)
            } else {
                Text(installed)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    @ViewBuilder
    private func statusView(for row: UpdaterViewModel.AppUpdateRow) -> some View {
        if row.isChecking {
            ProgressView().controlSize(.small)
        } else if viewModel.isUpdateAvailable(row) {
            BadgeView(text: "Update available", style: .attention)
        } else if row.app.isAppStoreDistributed {
            Button("View in App Store") {
                openAppStoreSearch(for: row.app.name)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(Theme.accent)
        } else if row.app.sparkleFeedURL == nil {
            BadgeView(text: "No update mechanism", style: .neutral)
        } else {
            BadgeView(text: "Up to date", style: .safe)
        }
    }

    private func appIcon(for app: InstalledApp) -> some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: app.bundlePath))
            .resizable()
            .frame(width: 30, height: 30)
            .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    /// No local App Store product-ID lookup exists without a network call
    /// to Apple's iTunes Search API (not built in this phase), so this opens
    /// a name-based App Store search rather than the exact product page.
    private func openAppStoreSearch(for appName: String) {
        var components = URLComponents(string: "https://apps.apple.com/search")
        components?.queryItems = [URLQueryItem(name: "term", value: appName)]
        guard let url = components?.url else { return }
        NSWorkspace.shared.open(url)
    }
}

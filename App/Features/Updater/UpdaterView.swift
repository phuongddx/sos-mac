import SwiftUI
import AppKit
import CleanCore

/// Updater on the shared lifecycle frame (plan PR 10) — built like the Junk & Cache
/// reference screen and the Uninstaller. The view owns no screen state of its own: it
/// switches on `viewModel.phase`, composes the shared components and passes real values into
/// `ModuleScreen`. Read-only: nothing here installs an update.
///
/// Documented deviations from the prototype (also in the PR 10 gallery README):
/// - `results` keeps the frame's hard-coded dock: a disabled "Clean" CTA, a disabled
///   "Review Items…" and "Scan Again". Nothing is cleaned here; the frame cannot relabel
///   them without touching `ModuleScreen` (outside this PR's write set), so the honest
///   "Check Again" button sits in the results header.
/// - `empty` keeps the frame's "Scan Again" CTA; the card carries "Check Again".
/// - Two extra groups appear only when needed: "Couldn't check" (OD-10) and "Not checked
///   yet" (after Stop).
struct UpdaterView: View {
    @Environment(ModuleStore.self) private var store
    private var viewModel: UpdaterViewModel { store.updater }

    var body: some View {
        UpdaterScreen(viewModel: viewModel)
    }
}

private struct UpdaterScreen: View {
    var viewModel: UpdaterViewModel

    private typealias UpdaterFrame = ModuleScreen<AnyView>

    private let module = ModuleIdentity(module: .updater)

    var body: some View {
        ModuleScreen(
            module: module,
            state: viewModel.lifecycle,
            subtitle: toolbarSubtitle,
            actions: actions,
            progress: scanFraction
        ) {
            AnyView(content)
        }
        .accessibilityIdentifier("updater-screen")
        .task {
            #if DEBUG
            if UITestHooks.current.fixtures, UITestHooks.current.destination == .updater {
                viewModel.loadFixtureFromLaunchHooks()
                return
            }
            #endif
            // OD-10: only lists the installed apps. No update check runs on a visit.
            viewModel.loadApps()
        }
    }

    // MARK: - Content (one branch per Phase)

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .idle: startContent
        case .checking: checkingContent
        case .results: resultsContent
        case .empty: emptyContent
        case .failed(let message): failedContent(message: message)
        }
    }

    // MARK: Start

    private var startContent: some View {
        let count = viewModel.rows.count
        return StartView(
            module: module,
            title: "See which apps have updates",
            lede: count == 0
                ? "SOS Mac looked in /Applications and ~/Applications and found no apps to check."
                : "\(count) \(count == 1 ? "app" : "apps") found. Check reads each app's update feed over the network. Nothing is installed or changed.",
            bullets: [
                .init(symbol: "arrow.triangle.2.circlepath",
                      title: "Apps with an update feed",
                      text: "SOS Mac asks the feed for the newest version and compares it with the one installed."),
                .init(symbol: "bag",
                      title: "App Store apps",
                      text: "Opens the App Store so you can update there."),
            ])
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Checking

    private var checkingContent: some View {
        let progress = viewModel.progressTracker.progress
        let total = progress?.totalItems ?? viewModel.checkableCount
        let done = progress?.itemsProcessed ?? 0
        let current = viewModel.currentlyCheckingRow?.app.name
        return ScanningView(
            module: module,
            title: current.map { "Checking \($0)…" } ?? "Checking for updates…",
            eyebrow: "Checking",
            lede: "Asking each app's update feed for its newest version. Nothing is installed.",
            steps: checkingSteps,
            progress: scanFraction,
            progressLeading: total > 0 ? "\(min(done + 1, total)) of \(total) apps" : nil,
            progressTrailing: scanFraction.map { "\(Int(($0 * 100).rounded()))%" },
            path: current)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Per spec: rows show "Checked" or a spinner. The list is the last few finished rows
    /// and the one in flight, so a 60-app list does not push the progress off screen.
    private var checkingSteps: [ScanningView.Step] {
        let finished = viewModel.rows.filter { $0.hasVerdict }.suffix(3).map { row in
            ScanningView.Step(name: row.app.name,
                              meta: row.checkError == nil ? "Checked" : "Couldn't check",
                              state: row.checkError == nil ? .done : .failed)
        }
        let active = viewModel.currentlyCheckingRow.map { [ScanningView.Step(name: $0.app.name, state: .active)] } ?? []
        return Array(finished) + active
    }

    private var scanFraction: Double? {
        guard viewModel.isCheckingAll,
              let progress = viewModel.progressTracker.progress,
              let total = progress.totalItems, total > 0 else { return nil }
        return min(1, Double(progress.itemsProcessed) / Double(total))
    }

    // MARK: Results

    private var resultsContent: some View {
        let updates = viewModel.updatesAvailableCount
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ResultsHeaderView(
                    hue: module.hue,
                    title: updates == 0 ? "No updates available" : UpdaterGroups.updatesText(updates),
                    sub: resultsSub,
                    eyebrow: "Checked") {
                    Button("Check Again") { viewModel.startCheck() }
                        .sosButton(.default)
                        .accessibilityIdentifier("updater-check-again")
                }
                if viewModel.hasCheckError {
                    failedBanner
                        .padding(.vertical, Theme.Spacing.s2)
                }
                ForEach(viewModel.groups) { group in
                    groupSection(group)
                }
            }
            .padding(EdgeInsets(top: Theme.Spacing.s2, leading: Self.contentPadding, bottom: Theme.Spacing.s5, trailing: Self.contentPadding))
        }
        .accessibilityIdentifier("updater-list")
    }

    private static let contentPadding: CGFloat = 40

    private var resultsSub: String {
        let checked = viewModel.checkedCount
        return "\(checked) \(checked == 1 ? "app" : "apps") checked. Updates are installed in each app or in the App Store."
    }

    /// OD-10: one or more feeds failed — said plainly, with a retry for just those rows.
    private var failedBanner: some View {
        let failed = viewModel.failedRows
        return BannerView(
            kind: .err,
            title: failed.count == 1 ? "Couldn't check \(failed[0].app.name)" : "Couldn't check \(failed.count) apps",
            text: failed.count == 1
                ? (failed[0].checkError ?? "The update feed didn't answer.") + " It is not shown as up to date."
                : "Their update feeds didn't answer. They are not shown as up to date.") {
            Button("Try Again") { viewModel.retryFailedChecks() }
                .sosButton(.default)
                .accessibilityIdentifier("updater-retry-failed")
        }
    }

    private func groupSection(_ group: UpdaterGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s2) {
                Text(group.kind.title)
                    .font(Theme.Font.title3)
                    .foregroundStyle(Theme.Color.textPrimary)
                Text("\(group.rows.count)")
                    .font(Theme.Font.callout.monospacedDigit())
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            if let note = group.kind.note {
                Text(note)
                    .font(Theme.Font.callout)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .padding(.top, 2)
            }
            ForEach(group.rows) { row in
                appRow(row)
            }
        }
        .padding(.top, Theme.Spacing.s4)
        .accessibilityIdentifier("updater-group-\(group.id)")
    }

    private func appRow(_ row: UpdaterViewModel.AppUpdateRow) -> some View {
        let status = UpdaterGroups.status(of: row)
        return HStack(spacing: Theme.Spacing.s3) {
            UpdaterAppIcon(app: row.app, icon: viewModel.icon(for: row.app), side: 36)
            VStack(alignment: .leading, spacing: 0) {
                Text(row.app.name)
                    .font(Theme.Font.headline)
                    .foregroundStyle(Theme.Color.textPrimary)
                    .lineLimit(1)
                Text(Self.versionLine(row: row, status: status))
                    .font(Theme.Font.subheadline.monospacedDigit())
                    .foregroundStyle(Theme.Color.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Theme.Spacing.s3)
            statusView(status, row: row)
        }
        .padding(.vertical, Theme.Spacing.s2)
        .padding(.top, Theme.Spacing.s1)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.Derived.hairline).frame(height: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("updater-row-\(row.app.bundleIdentifier)")
    }

    /// "1.2.3 → 1.2.4" for an update, the installed version otherwise; a failed row
    /// carries the reason instead.
    static func versionLine(row: UpdaterViewModel.AppUpdateRow, status: UpdaterRowStatus) -> String {
        switch status {
        case .updateAvailable(let installed, let latest):
            return "\(installed) → \(latest)"
        case .checkFailed(let message):
            return message
        case .appStore, .upToDate, .noFeed, .notChecked:
            return row.app.version.map { "Version \($0)" } ?? "Version unknown"
        }
    }

    @ViewBuilder
    private func statusView(_ status: UpdaterRowStatus, row: UpdaterViewModel.AppUpdateRow) -> some View {
        switch status {
        case .updateAvailable:
            BadgeView(text: "Update available", style: .caution)
        case .appStore:
            Button("View in App Store") { Self.openAppStoreSearch(for: row.app.name) }
                .sosButton(.default)
                .accessibilityLabel("View \(row.app.name) in the App Store")
        case .upToDate:
            BadgeView(text: "Up to date", style: .safe)
        case .noFeed:
            BadgeView(text: "Can't check", style: .neutral)
        case .checkFailed:
            BadgeView(text: "Couldn't check", style: .risky)
        case .notChecked:
            BadgeView(text: "Not checked", style: .neutral)
        }
    }

    /// No local App Store product-ID lookup exists without a network call to Apple's iTunes
    /// Search API, so this opens a name-based App Store search (a user-initiated link, not
    /// an install action).
    private static func openAppStoreSearch(for appName: String) {
        var components = URLComponents(string: "https://apps.apple.com/search")
        components?.queryItems = [URLQueryItem(name: "term", value: appName)]
        guard let url = components?.url else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: Empty / Failed

    private var emptyContent: some View {
        let checked = viewModel.checkedCount
        var text = "\(checked) \(checked == 1 ? "app" : "apps") checked. None has a newer version in its update feed."
        let noFeed = viewModel.noFeedCount
        if noFeed > 0 {
            text += " \(noFeed) \(noFeed == 1 ? "app has" : "apps have") no update feed and \(noFeed == 1 ? "wasn't" : "weren't") checked."
        }
        return StatusStateView(
            kind: .ok,
            symbol: "checkmark.circle",
            title: "All apps are up to date",
            text: text) {
            Button("Check Again") { viewModel.startCheck() }
                .sosButton(.default)
                .accessibilityIdentifier("updater-check-again-empty")
        }
    }

    private func failedContent(message: String) -> some View {
        StatusStateView(
            kind: .error,
            symbol: "exclamationmark.triangle",
            title: "Couldn't check for updates",
            text: message) {
            Button("Try Again") { viewModel.startCheck() }
                .sosButton(.default)
                .accessibilityIdentifier("updater-try-again")
        }
    }

    // MARK: - Frame wiring

    private var actions: UpdaterFrame.Actions {
        var actions = UpdaterFrame.Actions()
        switch viewModel.phase {
        case .idle:
            // With no apps there is nothing to check: the CTA stays disabled.
            if !viewModel.rows.isEmpty { actions.primary = { viewModel.startCheck() } }
        case .checking:
            actions.stop = { viewModel.stopCheck() }
        case .results:
            // "Clean" stays disabled (deviation): nothing is cleaned here.
            actions.scanAgain = { viewModel.startCheck() }
        case .empty:
            actions.scanAgain = { viewModel.startCheck() }
        case .failed:
            actions.primary = { viewModel.startCheck() }
        }
        return actions
    }

    /// F6: a real subtitle wherever one exists; otherwise the state's default.
    private var toolbarSubtitle: String? {
        switch viewModel.phase {
        case .idle:
            viewModel.rows.isEmpty ? nil : "\(viewModel.rows.count) \(viewModel.rows.count == 1 ? "app" : "apps")"
        case .checking:
            checkingSubtitle
        case .results:
            viewModel.updatesAvailableCount == 0 ? "No updates available" : UpdaterGroups.updatesText(viewModel.updatesAvailableCount)
        case .empty:
            "No updates available"
        case .failed:
            nil
        }
    }

    private var checkingSubtitle: String? {
        guard let progress = viewModel.progressTracker.progress, let total = progress.totalItems, total > 0 else { return nil }
        return "\(min(progress.itemsProcessed + 1, total)) of \(total) apps"
    }
}

/// OD-12: the app's real icon when its bundle is on disk, else a letter tile in the module
/// hue (also what the fictional fixture apps get).
struct UpdaterAppIcon: View {
    let app: InstalledApp
    let icon: NSImage?
    let side: CGFloat

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                let shape = RoundedRectangle(cornerRadius: side * 0.24, style: .continuous)
                ZStack {
                    shape.fill(LinearGradient(colors: [Theme.Hue.updater, Theme.Hue.updater.opacity(0.72)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing))
                    Text(String(app.name.prefix(1)).uppercased())
                        .font(.system(size: side * 0.44, weight: .bold))
                        .foregroundStyle(Theme.Hue.Ink.updater)
                }
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}

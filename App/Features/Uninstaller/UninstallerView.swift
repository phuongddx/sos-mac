import SwiftUI
import AppKit
import CleanCore

/// Uninstaller on the shared lifecycle frame (plan PR 9) — built like the Junk & Cache
/// reference screen. The view owns no screen state of its own: it switches on
/// `viewModel.phase`, composes the shared components and passes real values into
/// `ModuleScreen` (toolbar, aurora canvas, dock, sheet).
///
/// Documented deviations from the prototype (also in the PR 9 gallery README):
/// - `results` carries the dock's per-module "Review" CTA (Appendix A, PR 16), disabled
///   with a hint: an app is removed from its own review, never in bulk, so the state
///   offers no primary action.
/// - `done` / `empty` show "Back to Apps" / "Check Again" on the card; the dock matches
///   through `ModuleIdentity.dock` (Appendix A, PR 16).
/// - Two-column review: the app panel sits over the frame's (empty) groups column.
struct UninstallerView: View {
    @Environment(ModuleStore.self) private var store
    private var viewModel: UninstallerViewModel { store.uninstaller }

    var body: some View {
        UninstallerScreen(viewModel: viewModel)
    }
}

private struct UninstallerScreen: View {
    @Bindable var viewModel: UninstallerViewModel
    @Environment(ModuleStore.self) private var store

    private typealias UninstallerFrame = ModuleScreen<AnyView>

    @State private var overlay: ModuleOverlay?

    private let module = ModuleIdentity(module: .uninstaller)

    var body: some View {
        ModuleScreen(
            module: module,
            state: viewModel.lifecycle,
            subtitle: toolbarSubtitle,
            back: toolbarBack,
            tools: toolbarTools,
            actions: actions,
            progress: scanRingProgress,
            selection: selectionSummary,
            overlay: $overlay
        ) {
            AnyView(content)
        }
        .accessibilityIdentifier("uninstaller-screen")
        .task(id: appsTaskGate) {
            #if DEBUG
            if UITestHooks.current.fixtures, UITestHooks.current.destination == .uninstaller {
                viewModel.loadFixtureFromLaunchHooks()
                return
            }
            #endif
            #if MAS_BUILD
            // Fail closed: without the Applications grant the enumerator
            // would walk nothing and report a fake "no apps".
            guard !store.masAccess.needsApplicationsGrant else { return }
            #endif
            viewModel.loadApps()
        }
    }

    /// MAS: re-runs `.task` when the Applications grant lands (the store
    /// rebuilds the view model, and the fresh one has not loaded apps yet).
    private var appsTaskGate: String {
        #if MAS_BUILD
        store.masAccess.applicationsRoot ?? ""
        #else
        ""
        #endif
    }

    // MARK: - Content (one branch per Phase)

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .browsing, .measured:
            switch viewModel.lifecycle {
            case .empty: emptyContent
            case .error: errorContent
            default: listContent
            }
        case .inspectingAll(let currentBundleID):
            scanningContent(currentBundleID: currentBundleID)
        case .reviewing:
            reviewContent
        case .cleaning:
            cleaningContent
        case .removed(let appName, let atLeastBytes, let itemCount, let failedCount):
            doneContent(appName: appName, atLeastBytes: atLeastBytes, itemCount: itemCount, failedCount: failedCount)
        }
    }

    // MARK: Start / Results — the app list

    private var listContent: some View {
        let isMeasured = viewModel.phase == .measured
        let rows = viewModel.visibleApps
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ResultsHeaderView(
                    hue: module.hue,
                    title: isMeasured ? measuredTitle : "Pick an app to see what it left behind",
                    sub: isMeasured
                        ? "Review an app to choose what moves to the Trash. Sizes are real; folders are not measured yet."
                        : "\(viewModel.apps.count) \(viewModel.apps.count == 1 ? "app" : "apps") installed. Inspect one, or measure them all.",
                    eyebrow: isMeasured ? "Measured" : "Apps")
                if rows.isEmpty {
                    Text("No apps match “\(viewModel.filterText)”.")
                        .font(Theme.Font.callout)
                        .foregroundStyle(Theme.Color.textSecondary)
                        .padding(.vertical, Theme.Spacing.s5)
                }
                ForEach(rows) { row in
                    appRow(row)
                }
            }
            .padding(EdgeInsets(top: Theme.Spacing.s2, leading: Self.contentPadding, bottom: Theme.Spacing.s5, trailing: Self.contentPadding))
        }
        .accessibilityIdentifier("uninstaller-list")
    }

    private static let contentPadding: CGFloat = 40

    private var measuredTitle: String {
        let measured = viewModel.measuredAppCount
        return "\(measured) of \(viewModel.apps.count) apps measured"
    }

    private func appRow(_ row: UninstallerViewModel.AppRow) -> some View {
        let isBusy = viewModel.inspectingBundleID == row.app.bundleIdentifier
        return VStack(alignment: .leading, spacing: Theme.Spacing.s2) {
            HStack(spacing: Theme.Spacing.s3) {
                UninstallerAppIcon(app: row.app, icon: viewModel.icon(for: row.app), side: 36)
                VStack(alignment: .leading, spacing: 0) {
                    Text(row.app.name)
                        .font(Theme.Font.headline)
                        .foregroundStyle(Theme.Color.textPrimary)
                        .lineLimit(1)
                    if let version = row.app.version {
                        Text("Version \(version)")
                            .font(Theme.Font.subheadline)
                            .foregroundStyle(Theme.Color.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: Theme.Spacing.s3)
                if row.app.isAppStoreDistributed {
                    BadgeView(text: "App Store", style: .accent)
                }
                if let sizeText = Self.rowSizeText(row) {
                    Text(sizeText)
                        .font(Theme.Font.body.monospacedDigit())
                        .foregroundStyle(Theme.Color.textSecondary)
                        .frame(minWidth: 96, alignment: .trailing)
                }
                if isBusy {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Inspect") {
                        Task { await viewModel.inspect(row) }
                    }
                    .sosButton(.default)
                    .disabled(viewModel.inspectingBundleID != nil)
                    .accessibilityLabel("Inspect \(row.app.name)")
                }
            }
            if let message = row.inspectError {
                BannerView(kind: .err, title: "Couldn't inspect \(row.app.name)", text: message)
            }
        }
        .padding(.vertical, Theme.Spacing.s2)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.Derived.hairline).frame(height: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("uninstaller-row-\(row.app.bundleIdentifier)")
    }

    /// D1: "At least …" whenever the row's size leaves out an unmeasured folder; `nil`
    /// (nothing shown) until the app has really been measured.
    static func rowSizeText(_ row: UninstallerViewModel.AppRow) -> String? {
        guard let bytes = row.inspectedSize else { return nil }
        let text = ConfirmItemList.sizeText(for: bytes)
        return row.unmeasuredFolderCount > 0 ? "At least \(text)" : text
    }

    // MARK: Scanning (Inspect All)

    private func scanningContent(currentBundleID: String?) -> some View {
        let progress = viewModel.progressTracker.progress
        let total = progress?.totalItems ?? viewModel.apps.count
        let done = progress?.itemsProcessed ?? 0
        let appName = viewModel.row(forBundleID: currentBundleID ?? "")?.app.name
        return ScanningView(
            module: module,
            title: appName.map { "Inspecting \($0)…" } ?? "Inspecting your apps…",
            lede: "Reading each app's files to find what it left behind. Nothing is changed.",
            progress: scanFraction,
            progressLeading: total > 0 ? "\(min(done + 1, total)) of \(total) apps" : nil,
            progressTrailing: scanFraction.map { "\(Int(($0 * 100).rounded()))%" },
            path: appName)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var scanFraction: Double? {
        guard let progress = viewModel.progressTracker.progress,
              let total = progress.totalItems, total > 0 else { return nil }
        return min(1, Double(progress.itemsProcessed) / Double(total))
    }

    // MARK: Review (two columns)

    private var reviewContent: some View {
        ReviewFrameView(
            layout: .twoColumns,
            sections: [],
            listHead: listHead,
            items: itemModels,
            onToggleItem: { viewModel.toggleSelection(path: $0.id) },
            onFocusItem: { _ in },
            onGroup: { _ in })
            .overlay(alignment: .topLeading) {
                if let app = viewModel.reviewedApp {
                    UninstallerAppPanel(
                        app: app,
                        icon: viewModel.icon(for: app),
                        itemCount: viewModel.associatedItems.count,
                        selectedCount: viewModel.selectedItems.count,
                        sizeText: viewModel.selectedSizeText,
                        unmeasuredFolderCount: viewModel.unmeasuredFolderCount,
                        isRunning: viewModel.isReviewedAppRunning)
                        .padding(.top, 1)
                }
            }
    }

    private var listHead: ReviewFrameView.ListHead {
        let all = viewModel.associatedItems
        let selected = viewModel.selectedItems
        let count = all.count
        return ReviewFrameView.ListHead(
            title: viewModel.reviewedApp.map { "\($0.name) · \(count) \(count == 1 ? "item" : "items")" } ?? "Items",
            sub: "Everything is selected. Uncheck what you want to keep.",
            isSelectAllEnabled: selected.count < count,
            isDeselectAllEnabled: !selected.isEmpty,
            selectAll: { viewModel.selectAll() },
            deselectAll: { viewModel.deselectAll() },
            banner: AnyView(reviewBanners))
    }

    /// Under the list head: OD-9's "Quit «App» first" and D1's "N folders not measured yet."
    @ViewBuilder
    private var reviewBanners: some View {
        VStack(spacing: Theme.Spacing.s2) {
            if viewModel.isReviewedAppRunning, let app = viewModel.reviewedApp {
                BannerView(kind: .warn,
                           title: "Quit \(app.name) first",
                           text: "\(app.name) is open. Quit it, then check again — it can't be moved to the Trash while it runs.")
                HStack {
                    Button("Check Again") { viewModel.refreshRunningState() }
                        .buttonStyle(.sosPlain)
                        .accessibilityIdentifier("uninstaller-check-again")
                    Spacer()
                }
            }
            if viewModel.unmeasuredFolderCount > 0 {
                let count = viewModel.unmeasuredFolderCount
                BannerView(kind: .info,
                           title: "\(count) \(count == 1 ? "folder" : "folders") not measured yet.",
                           text: "Folders show no size, so totals read “at least”. Everything in a folder you keep selected moves with it.")
            }
        }
    }

    private var itemModels: [ReviewItemRow.Model] {
        viewModel.associatedItems.map { item in
            let isBundle = viewModel.isAppBundle(item)
            let isFolder = viewModel.isUnmeasuredFolder(item)
            return ReviewItemRow.Model(
                id: item.path,
                name: (item.path as NSString).lastPathComponent,
                path: item.path,
                // D1: a folder never shows a size.
                sizeText: isFolder ? "Folder" : ConfirmItemList.sizeText(for: item.size),
                badges: isBundle ? [ReviewItemRow.Badge(text: "App", style: .accent)] : [],
                isSelected: viewModel.selectedPaths.contains(item.path))
        }
    }

    // MARK: Cleaning

    private var cleaningContent: some View {
        let progress = viewModel.cleaningProgress
        let fraction = progress.map { Double($0.attemptedCount) / Double(max($0.totalCount, 1)) }
        return ScanningView(
            module: module,
            title: progress.map { "Moving \($0.attemptedCount) of \($0.totalCount) \($0.totalCount == 1 ? "item" : "items") to the Trash…" }
                ?? "Moving items to the Trash…",
            eyebrow: "Moving to Trash",
            lede: "You can put items back from the Trash in Finder.",
            progress: fraction,
            progressLeading: progress.map { "\($0.attemptedCount) of \($0.totalCount) items" },
            path: progress?.currentPath)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Done

    private func doneContent(appName: String, atLeastBytes: Int64, itemCount: Int, failedCount: Int) -> some View {
        let bytesText = ConfirmItemList.sizeText(for: atLeastBytes)
        let movedApp = viewModel.lastRemovalIncludedApp
        return DoneView(
            hue: module.hue,
            title: "At least \(bytesText) moved to the Trash",
            sub: movedApp
                ? "\(appName) and \(max(itemCount - 1, 0)) related \(itemCount - 1 == 1 ? "item" : "items") are in the Trash."
                : "\(itemCount) \(itemCount == 1 ? "item" : "items") from \(appName) are in the Trash.",
            stats: [
                .init(label: "Moved to Trash (at least)", value: bytesText, isBytes: true),
                .init(label: "Items", value: "\(itemCount)"),
                .init(label: "Couldn't move", value: "\(failedCount)"),
            ],
            actions: AnyView(Button("Back to Apps") { viewModel.backToApps() }
                .sosButton(.default)
                .accessibilityIdentifier("uninstaller-back-to-apps")),
            extra: { failureBanners })
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// F4: every item that stayed is listed with the engine's own reason.
    @ViewBuilder
    private var failureBanners: some View {
        if !viewModel.lastFailedItems.isEmpty {
            ScrollView {
                VStack(spacing: Theme.Spacing.s2) {
                    ForEach(Array(viewModel.lastFailedItems.enumerated()), id: \.offset) { _, failure in
                        BannerView(kind: .err,
                                   title: "Couldn't move \((failure.item.path as NSString).lastPathComponent)",
                                   text: failure.reason)
                    }
                }
            }
            .frame(maxHeight: 220)
        }
    }

    // MARK: Empty / Error

    private var emptyContent: some View {
        StatusStateView(
            kind: .neutral,
            symbol: "square.grid.2x2",
            title: "No apps found",
            text: "SOS Mac looked in /Applications and ~/Applications and found no apps to inspect.") {
            Button("Check Again") { viewModel.checkAgain() }
                .sosButton(.default)
                .accessibilityIdentifier("uninstaller-check-again-empty")
        }
    }

    private var errorContent: some View {
        let failed = viewModel.failedRows
        let first = failed.first
        return StatusStateView(
            kind: .error,
            symbol: "exclamationmark.triangle",
            title: failed.count == 1 ? "Couldn't inspect \(first?.app.name ?? "this app")" : "Couldn't inspect \(failed.count) apps",
            text: failed.count == 1
                ? (first?.inspectError ?? "The inspect stopped.")
                : failed.map(\.app.name).joined(separator: ", ") + " couldn't be read. Try again, or inspect another app.") {
            Button("Show Apps") { viewModel.dismissInspectErrors() }
                .sosButton(.default)
                .accessibilityIdentifier("uninstaller-show-apps")
        }
    }

    // MARK: - Frame wiring

    private var actions: UninstallerFrame.Actions {
        var actions = UninstallerFrame.Actions()
        switch viewModel.phase {
        case .browsing:
            if viewModel.lifecycle == .error {
                actions.primary = { Task { await viewModel.retryFailedInspects() } }
            } else {
                actions.primary = {
                    #if MAS_BUILD
                    guard store.masEnsureApplicationsAccess() else { return }
                    #endif
                    viewModel.startInspectAll()
                }
                // Empty's CTA is the frame's "Scan Again".
                actions.scanAgain = { viewModel.checkAgain() }
            }
        case .inspectingAll:
            actions.stop = { viewModel.cancelInspectAll() }
        case .measured:
            if viewModel.lifecycle == .error {
                actions.primary = { Task { await viewModel.retryFailedInspects() } }
            } else {
                // The dock CTA is "Review" (Appendix A): an app is removed from its own
                // review, never in bulk — no primary action while browsing the list.
                actions.scanAgain = { viewModel.startInspectAll() }
            }
        case .reviewing:
            // S1: every removal path opens the confirmation first. A running app blocks it
            // (OD-9) — the review's banner says why, with Check Again.
            if !viewModel.selectedPaths.isEmpty, !viewModel.isReviewedAppRunning {
                actions.primary = { presentUninstallConfirmation() }
            }
        case .cleaning:
            break
        case .removed:
            actions.scanAgain = { viewModel.backToApps() }
            actions.openTrash = openTrash
        }
        return actions
    }

    /// CF-3: the same selection the review bar and the confirmation show.
    private var selectionSummary: UninstallerFrame.SelectionSummary? {
        guard viewModel.phase.isReviewing else { return nil }
        return UninstallerFrame.SelectionSummary(count: viewModel.selectedItems.count,
                                                 sizeText: viewModel.selectedSizeText)
    }

    private func presentUninstallConfirmation() {
        // Re-checks the running state first; `nil` means the app is running (OD-9).
        guard let model = viewModel.uninstallConfirmation() else { return }
        overlay = .confirmation(model)
    }

    /// "Open Trash" reveals the Trash in Finder; if the URL can't be resolved nothing
    /// happens rather than a guessed path (fail closed).
    private func openTrash() {
        guard let trashURL = try? FileManager.default.url(
            for: .trashDirectory, in: .userDomainMask, appropriateFor: nil, create: false) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([trashURL])
    }

    /// F6: a real subtitle wherever one exists; otherwise the state's default.
    private var toolbarSubtitle: String? {
        switch viewModel.phase {
        case .browsing:
            viewModel.apps.isEmpty ? nil : "\(viewModel.apps.count) \(viewModel.apps.count == 1 ? "app" : "apps")"
        case .inspectingAll:
            scanningSubtitle
        case .measured:
            "\(viewModel.measuredAppCount) of \(viewModel.apps.count) apps measured"
        case .reviewing:
            viewModel.reviewedApp?.name
        case .cleaning:
            viewModel.cleaningProgress.map {
                "Moving \($0.attemptedCount) of \($0.totalCount) \($0.totalCount == 1 ? "item" : "items")…"
            }
        case .removed:
            nil
        }
    }

    private var scanningSubtitle: String? {
        guard let progress = viewModel.progressTracker.progress, let total = progress.totalItems, total > 0 else { return nil }
        return "\(min(progress.itemsProcessed + 1, total)) of \(total) apps"
    }

    private var toolbarBack: ModuleToolbarModel.Back? {
        switch viewModel.phase {
        case .reviewing:
            return ModuleToolbarModel.Back(label: "Apps", action: { viewModel.backToApps() })
        case .browsing, .inspectingAll, .measured, .cleaning, .removed:
            return nil
        }
    }

    /// OD-13: the local name filter, shown only where there is a list to filter.
    private var toolbarTools: AnyView? {
        switch viewModel.phase {
        case .browsing, .measured:
            guard viewModel.lifecycle != .empty else { return nil }
            return AnyView(
                TextField("Filter apps", text: $viewModel.filterText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                    .accessibilityIdentifier("uninstaller-filter"))
        case .inspectingAll, .reviewing, .cleaning, .removed:
            return nil
        }
    }

    private var scanRingProgress: Double? {
        guard viewModel.isInspectingAll else { return nil }
        return scanFraction
    }
}

private extension UninstallerViewModel.Phase {
    var isReviewing: Bool {
        if case .reviewing = self { return true }
        return false
    }
}

import SwiftUI
import AppKit
import SwiftData
import CleanCore

/// Junk & Cache on the shared lifecycle frame — the reference screen every later
/// screen PR copies. The view owns no screen state of its own: it switches on
/// `viewModel.phase`, composes the shared components, and passes real values into
/// `ModuleScreen` (which owns the toolbar, aurora canvas, dock and sheet).
struct JunkCleanerView: View {
    @Environment(ModuleStore.self) private var store
    private var viewModel: JunkCleanerViewModel { store.junkCleaner }

    var body: some View {
        JunkCleanerScreen(viewModel: viewModel)
    }
}

private struct JunkCleanerScreen: View {
    @Bindable var viewModel: JunkCleanerViewModel

    /// `ModuleScreen`'s nested types carry the frame's generic parameter, so a screen
    /// that computes its `Actions`/`SelectionSummary` in properties (rather than inline
    /// at the call site, as the component gallery does) names them through one concrete
    /// frame — and passes its content as `AnyView` to match. The frame re-identifies the
    /// content per state, so F7's cross-fade is unaffected. This is the spelling every
    /// later screen PR copies.
    private typealias JunkFrame = ModuleScreen<AnyView>

    /// The sheet `ModuleScreen` presents (OD-4): a `ConfirmSheet` built by the view
    /// model, cleared on dismiss (Escape and Cancel land here too).
    @State private var overlay: ModuleOverlay?

    private let module = ModuleIdentity(module: .junkCleaner)

    var body: some View {
        ModuleScreen(
            module: module,
            state: viewModel.lifecycle,
            subtitle: toolbarSubtitle,
            back: toolbarBack,
            actions: actions,
            progress: scanRingProgress,
            selection: selectionSummary,
            overlay: $overlay
        ) {
            AnyView(content)
        }
        .accessibilityIdentifier("junk-cleaner-screen")
        .task {
            #if DEBUG
            viewModel.loadFixtureFromLaunchHooks()
            #endif
        }
    }

    // MARK: - Content (one branch per Phase — the state table's right column)

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .idle:
            startContent
        case .scanning:
            scanningContent
        case .results:
            // F3: zero items and no failure is the empty state, not a results grid.
            if viewModel.items.isEmpty {
                emptyContent
            } else {
                resultsContent
            }
        case .review:
            reviewContent
        case .cleaning:
            cleaningContent
        case .done(let movedBytes, let movedCount, let failedCount):
            doneContent(movedBytes: movedBytes, movedCount: movedCount, failedCount: failedCount)
        case .failed(let message):
            errorContent(message: message)
        }
    }

    private var startContent: some View {
        StartView(
            module: module,
            title: "Clear caches and old logs",
            lede: "Apps rebuild these files on their own. You see every file before it moves, and everything goes to the Trash.",
            bullets: ruleBullets,
            note: "System Caches need your approval. They're never selected for you.")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// One bullet per junk rule with its root path (spec §5.3 `start` row). The
    /// summaries come from the view model's injected rules, so the start screen
    /// always describes the exact set a scan will walk.
    private var ruleBullets: [StartView.Bullet] {
        viewModel.ruleSummaries.map { summary in
            StartView.Bullet(symbol: summary.requiresPrivilegedHelper ? "key" : "folder",
                             title: summary.title,
                             text: summary.root)
        }
    }

    private var scanningContent: some View {
        // Deviation from the prototype, fail-closed: the engine's per-rule progress
        // callback reports the completed rule's label, not the file being walked, so
        // the scanning state shows no path line rather than a fabricated one.
        ScanningView(
            module: module,
            title: "Looking for junk files…",
            steps: scanningSteps,
            progress: scanFraction,
            countLine: scanCountLine,
            progressLeading: scanLeadingText,
            progressTrailing: scanPercentText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Four step rows in scan order. Rule `i` is done once `i` completed rules were
    /// reported; the next is active. There is no per-rule "started" signal from the
    /// engine (only "rule N completed"), so rule 0 shows active at count 0 — the best
    /// available truth without an engine callback nobody else needs.
    private var scanningSteps: [ScanningView.Step] {
        let completed = viewModel.progressTracker.progress?.itemsProcessed ?? 0
        return viewModel.ruleLabels.enumerated().map { index, label in
            let state: StepRowView.StepState = index < completed ? .done : (index == completed ? .active : .pending)
            return ScanningView.Step(name: label, state: state)
        }
    }

    private var scanFraction: Double? {
        guard let progress = viewModel.progressTracker.progress,
              let total = progress.totalItems, total > 0 else { return nil }
        return min(1, Double(progress.itemsProcessed) / Double(total))
    }

    private var scanLeadingText: String? {
        guard let progress = viewModel.progressTracker.progress else { return nil }
        return "\(min(progress.itemsProcessed + 1, viewModel.locationCount)) of \(viewModel.locationCount) locations"
    }

    private var scanPercentText: String? {
        scanFraction.map { "\(Int(($0 * 100).rounded()))%" }
    }

    private var scanCountLine: String? {
        guard scanFraction == nil else { return nil }
        return "Scanning \(min((viewModel.progressTracker.progress?.itemsProcessed ?? 0) + 1, viewModel.locationCount)) of \(viewModel.locationCount) locations"
    }

    private var resultsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ResultsHeaderView(
                    hue: module.hue,
                    title: "\(ByteFormatter.string(fromByteCount: viewModel.totalBytes)) of junk found",
                    sub: "\(viewModel.items.count) \(viewModel.items.count == 1 ? "file" : "files") in \(viewModel.locationCount) locations · \(ByteFormatter.string(fromByteCount: viewModel.totalSelectedBytes)) selected (safe files only)")
                LazyVGrid(columns: Self.tileColumns, spacing: Self.tileSpacing) {
                    ForEach(viewModel.reviewLocations) { location in
                        locationTile(location)
                    }
                }
                .padding(.bottom, Theme.Spacing.s5)
            }
            .padding(EdgeInsets(top: Theme.Spacing.s2, leading: Self.contentPadding, bottom: 0, trailing: Self.contentPadding))
        }
        .accessibilityIdentifier("junk-results")
    }

    private static let tileColumns = [
        GridItem(.flexible(), spacing: tileSpacing),
        GridItem(.flexible(), spacing: tileSpacing)
    ]
    private static let tileSpacing: CGFloat = 14
    /// The prototype's `.results` side padding (styles.css).
    private static let contentPadding: CGFloat = 40

    /// One wide tile per location (spec §5.3 `results` row): file count and root in the
    /// caption, the real selected/caution counts in the foot, the helper location's
    /// "Needs approval · not selected" instead.
    private func locationTile(_ location: JunkCleanerViewModel.JunkLocation) -> some View {
        let bytes = location.items.reduce(Int64(0)) { $0 + $1.size }
        let split = Self.valueAndUnit(bytes)
        let selected = viewModel.selectedCount(in: location)
        let caution = location.items.count { $0.severity == .caution }
        return ResultTileView(
            hue: module.hue,
            ink: Theme.Hue.Ink.junk,
            symbol: location.requiresPrivilegedHelper ? "key" : "folder",
            label: location.title,
            value: split.value,
            unit: split.unit,
            caption: "\(location.items.count) \(location.items.count == 1 ? "file" : "files") · \(location.root)")
        {
            if location.requiresPrivilegedHelper {
                BadgeView(text: "Needs approval · not selected", style: .neutral, systemImage: "key")
            } else {
                BadgeView(text: "\(selected) selected", style: .safe)
                if caution > 0 {
                    BadgeView(text: "\(caution) caution", style: .caution, systemImage: "exclamationmark.triangle")
                }
            }
        }
        .accessibilityIdentifier("junk-tile-\(location.id)")
    }

    /// Splits a formatted byte count into the tile's numeral + unit slots
    /// ("3.4 GB" → "3.4" / "GB"). ByteCountFormatter localises with a space between the
    /// figure and the unit; a one-word result ("820 bytes") is shown whole.
    private static func valueAndUnit(_ bytes: Int64) -> (value: String, unit: String) {
        let text = ByteFormatter.string(fromByteCount: bytes)
        guard let separator = text.firstIndex(where: { $0.isWhitespace }) else {
            return (text, "")
        }
        return (String(text[..<separator]), String(text[text.index(after: separator)...]))
    }

    private var reviewContent: some View {
        ReviewFrameView(
            sections: [ReviewFrameView.GroupSection(id: "junk-locations",
                                                    title: "Locations",
                                                    groups: groupModels)],
            listHead: listHead,
            items: itemModels,
            onToggleItem: { viewModel.toggleSelection(path: $0.id) },
            onFocusItem: { viewModel.focusItem(path: $0.id) },
            onGroup: { viewModel.selectGroup($0.id) },
            detail: detail)
    }

    private var groupModels: [ReviewGroupRow.Model] {
        viewModel.reviewLocations.map { location in
            ReviewGroupRow.Model(
                id: location.id,
                label: location.title,
                sub: "\(location.root) · \(location.items.count) \(location.items.count == 1 ? "file" : "files")",
                selectedCount: viewModel.selectedCount(in: location),
                eligibleCount: location.items.count,
                isCurrent: location.id == viewModel.currentLocation?.id)
        }
    }

    private var listHead: ReviewFrameView.ListHead {
        let location = viewModel.currentLocation
        let eligible = location?.items.filter(JunkCleanerViewModel.isPreSelectable) ?? []
        let selected = location?.items.filter { viewModel.selectedPaths.contains($0.path) } ?? []
        return ReviewFrameView.ListHead(
            title: location?.title ?? "Locations",
            sub: location.map { "\($0.root) · \($0.items.count) \($0.items.count == 1 ? "file" : "files")" },
            isSelectAllEnabled: !eligible.allSatisfy { viewModel.selectedPaths.contains($0.path) },
            isDeselectAllEnabled: !selected.isEmpty,
            selectAll: { viewModel.selectAllEligibleInCurrentGroup() },
            deselectAll: { viewModel.deselectAllInCurrentGroup() },
            banner: AnyView(reviewBanners))
    }

    /// The banners under the list head: the S7 helper explanation on every helper
    /// location, and — above it — an action error such as a failed ignore-list save
    /// (N4: the error sits next to what caused it, never in a bare red line).
    @ViewBuilder
    private var reviewBanners: some View {
        VStack(spacing: Theme.Spacing.s2) {
            if let message = viewModel.actionErrorMessage {
                BannerView(kind: .err, title: "Couldn't ignore this file", text: message)
            }
            if viewModel.currentLocation?.requiresPrivilegedHelper == true {
                BannerView(kind: .info,
                           title: "Needs your approval",
                           text: "Moving these uses the SOS Mac helper. macOS asks for your password once.")
            }
        }
    }

    private var itemModels: [ReviewItemRow.Model] {
        (viewModel.currentLocation?.items ?? []).map { item in
            ReviewItemRow.Model(
                id: item.path,
                name: (item.path as NSString).lastPathComponent,
                path: item.path,
                sizeText: ByteFormatter.string(fromByteCount: item.size),
                badges: Self.badges(for: item),
                isSelected: viewModel.selectedPaths.contains(item.path),
                isFocused: viewModel.focusedItem?.path == item.path)
        }
    }

    private static func badges(for item: ScanItem) -> [ReviewItemRow.Badge] {
        var badges: [ReviewItemRow.Badge] = []
        switch item.severity {
        case .safe:
            badges.append(ReviewItemRow.Badge(text: "Safe", style: .safe))
        case .caution:
            badges.append(ReviewItemRow.Badge(text: "Caution", style: .caution))
        case .risky:
            badges.append(ReviewItemRow.Badge(text: "Risky", style: .risky))
        }
        if item.requiresPrivilegedHelper {
            badges.append(ReviewItemRow.Badge(text: "Needs approval", style: .neutral, systemImage: "key"))
        }
        return badges
    }

    private var detail: AnyView? {
        if let item = viewModel.focusedItem {
            return AnyView(JunkReviewDetail(item: item, onIgnore: { viewModel.ignore(item) }))
        }
        return nil
    }

    private var cleaningContent: some View {
        let progress = viewModel.cleaningProgress
        let fraction = progress.map { Double($0.attemptedCount) / Double(max($0.totalCount, 1)) }
        return ScanningView(
            module: module,
            title: progress.map { progress in
                "Moving \(progress.attemptedCount) of \(progress.totalCount) \(progress.totalCount == 1 ? "file" : "files") to the Trash…"
            } ?? "Moving files to the Trash…",
            eyebrow: "Moving to Trash",
            lede: "You can put items back from the Trash in Finder.",
            progress: fraction,
            progressLeading: progress.map { "\($0.attemptedCount) of \($0.totalCount) files" },
            path: progress?.currentPath)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func doneContent(movedBytes: Int64, movedCount: Int, failedCount: Int) -> some View {
        DoneView(
            hue: module.hue,
            title: "\(ByteFormatter.string(fromByteCount: movedBytes)) moved to the Trash",
            sub: "\(movedCount) \(movedCount == 1 ? "file" : "files") cleared from your caches and logs.",
            stats: [
                .init(label: "Moved to Trash", value: ByteFormatter.string(fromByteCount: movedBytes), isBytes: true),
                .init(label: "Files", value: "\(movedCount)"),
                .init(label: "Couldn't move", value: "\(failedCount)"),
            ],
            extra: { failureBanners })
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// F4: every failure is surfaced with the engine's own reason, never folded into a
    /// "reclaimed" figure. The scroll keeps a large failure set readable.
    @ViewBuilder
    private var failureBanners: some View {
        if !viewModel.lastFailedItems.isEmpty {
            ScrollView {
                VStack(spacing: Theme.Spacing.s2) {
                    ForEach(Array(viewModel.lastFailedItems.enumerated()), id: \.offset) { _, failure in
                        BannerView(
                            kind: .err,
                            title: "Couldn't move \((failure.item.path as NSString).lastPathComponent)",
                            text: failure.reason)
                    }
                }
            }
            .frame(maxHeight: 220)
        }
    }

    private var emptyContent: some View {
        StatusStateView(
            kind: .ok,
            symbol: "checkmark",
            title: "No junk found",
            text: "Your caches and logs are already clear in all \(viewModel.locationCount) locations.")
    }

    private func errorContent(message: String) -> some View {
        // §6.3: truthful copy — the title is fixed, the body is the engine's reason.
        // The prototype's System Caches story is deliberately not used: the scanner
        // skips unreadable roots and throws only on cancellation or a walker error.
        StatusStateView(
            kind: .error,
            symbol: "exclamationmark.triangle",
            title: "The scan stopped",
            text: message)
    }

    // MARK: - Frame wiring

    /// The frame's actions, one per control a state shows. A missing action disables its
    /// control rather than hiding it (F1) — e.g. "Clean" with nothing selected.
    private var actions: JunkFrame.Actions {
        var actions = JunkFrame.Actions()
        switch viewModel.phase {
        case .idle:
            actions.primary = { viewModel.startScan() }
        case .scanning:
            actions.stop = { viewModel.cancelScan() }
        case .results:
            // S1: every removal path opens the confirmation first.
            if !viewModel.selectedPaths.isEmpty {
                actions.primary = { presentTrashConfirmation(fromResults: true) }
            }
            if !viewModel.items.isEmpty {
                actions.reviewItems = { viewModel.enterReview() }
            }
            actions.scanAgain = { viewModel.startScan() }
        case .review:
            if !viewModel.selectedPaths.isEmpty {
                actions.primary = { presentTrashConfirmation(fromResults: false) }
            }
        case .cleaning:
            break
        case .done:
            actions.scanAgain = { viewModel.startScan() }
            actions.openTrash = openTrash
        case .failed:
            actions.primary = { viewModel.startScan() }
        }
        return actions
    }

    /// CF-3: the same selection the review bar and the confirmation show.
    private var selectionSummary: JunkFrame.SelectionSummary? {
        switch viewModel.phase {
        case .results, .review:
            JunkFrame.SelectionSummary(
                count: viewModel.selectedItems.count,
                sizeText: ConfirmItemList.sizeText(for: viewModel.totalSelectedBytes))
        case .idle, .scanning, .cleaning, .done, .failed:
            nil
        }
    }


    private func presentTrashConfirmation(fromResults: Bool) {
        overlay = .confirmation(viewModel.trashConfirmation(isFromResults: fromResults))
    }

    /// §5.3: "Open Trash" reveals the Trash in Finder. The URL comes from the one
    /// documented API; if it cannot be resolved the action does nothing rather than
    /// guessing a path (fail closed).
    private func openTrash() {
        guard let trashURL = try? FileManager.default.url(
            for: .trashDirectory, in: .userDomainMask, appropriateFor: nil, create: false) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([trashURL])
    }

    /// F6: a real subtitle wherever one exists; otherwise the state's default.
    private var toolbarSubtitle: String? {
        switch viewModel.phase {
        case .idle, .done, .failed:
            nil
        case .scanning:
            scanLeadingText
        case .results:
            viewModel.items.isEmpty
                ? nil
                : "\(viewModel.items.count) \(viewModel.items.count == 1 ? "file" : "files") in \(viewModel.locationCount) locations"
        case .review:
            nil
        case .cleaning:
            viewModel.cleaningProgress.map { progress in
                "Moving \(progress.attemptedCount) of \(progress.totalCount) \(progress.totalCount == 1 ? "file" : "files")…"
            }
        }
    }

    private var toolbarBack: ModuleToolbarModel.Back? {
        guard viewModel.phase == .review else { return nil }
        return ModuleToolbarModel.Back(label: "Results", action: { viewModel.backToResults() })
    }

    private var scanRingProgress: Double? {
        guard viewModel.phase == .scanning else { return nil }
        return scanFraction
    }

}

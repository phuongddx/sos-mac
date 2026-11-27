import SwiftUI
import AppKit
import CleanCore

/// Duplicate Finder on the shared lifecycle frame (plan PR 6) — copies the Junk & Cache
/// reference pattern: the view owns no screen state of its own, switches on
/// `viewModel.phase`, composes the shared components, and passes real values into
/// `ModuleScreen` (which owns the toolbar, aurora canvas, dock and sheet).
struct DuplicateFinderView: View {
    @Environment(ModuleStore.self) private var store
    private var viewModel: DuplicateFinderViewModel { store.duplicates }

    var body: some View {
        DuplicateFinderScreen(viewModel: viewModel)
    }
}

private struct DuplicateFinderScreen: View {
    @Bindable var viewModel: DuplicateFinderViewModel

    /// One concrete frame type, so `Actions`/`SelectionSummary` can be computed in properties
    /// (the spelling Junk & Cache set).
    private typealias DuplicateFrame = ModuleScreen<AnyView>

    /// The sheet `ModuleScreen` presents (OD-4): a `ConfirmSheet` built by the view model,
    /// cleared on dismiss (Escape and Cancel land here too).
    @State private var overlay: ModuleOverlay?

    private let module = ModuleIdentity(module: .duplicateFinder)

    private var isSimilar: Bool { viewModel.mode == .similarImages }

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
        .accessibilityIdentifier("duplicate-finder-screen")
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
            // F3: no sets and no failure is the empty state, not a results grid.
            if viewModel.sets.isEmpty {
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

    // MARK: Similar banner (S3)

    /// S3: Similar images warn before anything is selected — on Start, Results and Review.
    private var similarBanner: some View {
        BannerView(kind: .warn,
                   title: "Similar isn’t identical",
                   text: "There’s no preview or similarity score yet, so check each image before you move it.")
    }

    // MARK: Start

    private var startContent: some View {
        StartView(
            module: module,
            title: isSimilar ? "Find similar images" : "Find identical copies",
            lede: isSimilar
                ? "Looks for near-identical photos and screenshots in your Home folder."
                : "Compares file contents across your Home folder, so renamed copies are found too.",
            bullets: [
                StartView.Bullet(symbol: "lock",
                                 title: "The newest copy is kept",
                                 text: "In every set, the copy with the latest date modified can’t be selected."),
                StartView.Bullet(symbol: "trash",
                                 title: "Copies go to the Trash",
                                 text: "Put anything back from the Trash in Finder."),
            ],
            note: "Hashing every file can take a few minutes on a large Home folder.",
            extra: {
                if isSimilar {
                    similarBanner
                        .frame(maxWidth: StartView.ledeWidth)
                        .padding(.top, Theme.Spacing.s4)
                }
            })
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Scanning

    /// The engine reports no progress while it lists files (exact mode), so the first step has
    /// no files-counted meta and the bar appears only once hashing starts — nothing is made up.
    private var scanningContent: some View {
        let progress = viewModel.progressTracker.progress
        let hashing = viewModel.isHashing
        let candidates = progress?.totalItems
        return ScanningView(
            module: module,
            title: hashing ? "Hashing files…" : "Scanning for duplicates…",
            steps: scanningSteps(hashing: hashing, candidates: candidates),
            progress: scanFraction,
            countLine: hashing ? nil : "Counting files in your Home folder…",
            progressLeading: scanLeadingText,
            progressTrailing: scanPercentText,
            path: progress?.currentPath)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func scanningSteps(hashing: Bool, candidates: Int?) -> [ScanningView.Step] {
        let listing = isSimilar ? "Scanning similar images" : "Find files with the same size"
        let comparing = isSimilar ? "Comparing images" : "Compare contents"
        return [
            ScanningView.Step(name: listing,
                              meta: hashing ? candidates.map { "\($0.formatted()) candidates" } : nil,
                              state: hashing ? .done : .active),
            ScanningView.Step(name: comparing,
                              meta: hashing ? nil : "Waiting…",
                              state: hashing ? .active : .pending),
        ]
    }

    private var scanFraction: Double? {
        guard let progress = viewModel.progressTracker.progress,
              let total = progress.totalItems, total > 0 else { return nil }
        return min(1, Double(progress.itemsProcessed) / Double(total))
    }

    private var scanLeadingText: String? {
        guard let progress = viewModel.progressTracker.progress, let total = progress.totalItems else { return nil }
        return "\(progress.itemsProcessed.formatted()) of \(total.formatted()) \(total == 1 ? "file" : "files")"
    }

    private var scanPercentText: String? {
        scanFraction.map { "\(Int(($0 * 100).rounded()))%" }
    }

    // MARK: Results

    private var resultsContent: some View {
        let selectedBytes = Self.valueAndUnit(viewModel.totalSelectedBytes)
        let selectedCount = viewModel.selectedItems.count
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ResultsHeaderView(
                    hue: module.hue,
                    title: resultsTitle,
                    sub: "The newest copy in each set is kept.")
                if isSimilar {
                    similarBanner
                        .padding(.bottom, Self.tileSpacing)
                }
                LazyVGrid(columns: Self.tileColumns, spacing: Self.tileSpacing) {
                    ResultTileView(
                        hue: module.hue,
                        ink: Theme.Hue.Ink.duplicates,
                        symbol: "doc.on.doc",
                        label: "Sets found",
                        value: viewModel.sets.count.formatted(),
                        unit: "",
                        caption: "\(viewModel.totalFileCount.formatted()) \(viewModel.totalFileCount == 1 ? "file" : "files") in total")
                        .accessibilityIdentifier("duplicates-tile-sets")
                    ResultTileView(
                        hue: module.hue,
                        ink: Theme.Hue.Ink.duplicates,
                        symbol: "trash",
                        label: "Selected",
                        value: selectedBytes.value,
                        unit: selectedBytes.unit,
                        caption: "\(selectedCount.formatted()) extra \(selectedCount == 1 ? "copy" : "copies")",
                        isSelected: selectedCount > 0)
                    {
                        BadgeView(text: "\(viewModel.sets.count.formatted()) kept", style: .keep)
                    }
                    .accessibilityIdentifier("duplicates-tile-selected")
                }
                if viewModel.skippedCount > 0 {
                    BannerView(kind: .info,
                               title: skippedTitle,
                               text: "They couldn’t be read, so they may be missing from these results.")
                        .padding(.top, Self.tileSpacing)
                        .accessibilityIdentifier("duplicates-skipped")
                }
            }
            .padding(EdgeInsets(top: Theme.Spacing.s2, leading: Self.contentPadding,
                                bottom: Theme.Spacing.s5, trailing: Self.contentPadding))
        }
        .accessibilityIdentifier("duplicates-results")
    }

    private var resultsTitle: String {
        let count = viewModel.sets.count
        let noun = count == 1 ? "set" : "sets"
        return isSimilar
            ? "\(count.formatted()) \(noun) of similar images"
            : "\(count.formatted()) \(noun) of identical files"
    }

    private var skippedTitle: String {
        let count = viewModel.skippedCount
        return "\(count.formatted()) \(count == 1 ? "file was" : "files were") skipped"
    }

    private static let tileColumns = [
        GridItem(.flexible(), spacing: tileSpacing),
        GridItem(.flexible(), spacing: tileSpacing)
    ]
    private static let tileSpacing: CGFloat = 14
    /// The prototype's `.results` side padding (styles.css).
    private static let contentPadding: CGFloat = 40

    /// Splits a formatted byte count into the tile's numeral + unit slots ("3.4 GB" →
    /// "3.4" / "GB"). Zero is shown as "0 KB" — the formatter's "Zero KB" is a word, not a
    /// numeral.
    private static func valueAndUnit(_ bytes: Int64) -> (value: String, unit: String) {
        if bytes == 0 { return ("0", "KB") }
        let text = ByteFormatter.string(fromByteCount: bytes)
        guard let separator = text.firstIndex(where: { $0.isWhitespace }) else {
            return (text, "")
        }
        return (String(text[..<separator]), String(text[text.index(after: separator)...]))
    }

    // MARK: Review

    private var reviewContent: some View {
        ReviewFrameView(
            sections: [ReviewFrameView.GroupSection(id: "duplicate-sets",
                                                    title: isSimilar ? "Similar images" : "Identical sets",
                                                    groups: groupModels)],
            listHead: listHead,
            items: itemModels,
            onToggleItem: { viewModel.toggleSelection(path: $0.id) },
            onFocusItem: { viewModel.focusItem(path: $0.id) },
            onGroup: { viewModel.selectSet($0.id) },
            detail: detail)
    }

    /// OD-b: each set's row carries its own extra-copy count and the size it would free.
    private var groupModels: [ReviewGroupRow.Model] {
        viewModel.sets.map { set in
            let extra = set.extraItems.count
            return ReviewGroupRow.Model(
                id: set.id,
                label: set.title,
                sub: "\(extra) extra \(extra == 1 ? "copy" : "copies") · \(ByteFormatter.string(fromByteCount: set.extraBytes))",
                selectedCount: viewModel.selectedCount(in: set),
                eligibleCount: extra,
                isCurrent: set.id == viewModel.currentSet?.id)
        }
    }

    private var listHead: ReviewFrameView.ListHead {
        let set = viewModel.currentSet
        let extras = set?.extraItems ?? []
        let selected = extras.filter { viewModel.selectedPaths.contains($0.path) }
        return ReviewFrameView.ListHead(
            title: set?.title ?? "Sets",
            sub: set.map { listSub($0) },
            isSelectAllEnabled: selected.count < extras.count,
            isDeselectAllEnabled: !selected.isEmpty,
            selectAll: { viewModel.selectAllInCurrentSet() },
            deselectAll: { viewModel.deselectAllInCurrentSet() },
            banner: isSimilar ? AnyView(similarBanner) : nil)
    }

    /// "3 copies · 612.3 MB each" — the prototype's set sub. Similar images differ in size, so
    /// no per-copy size is quoted for them.
    private func listSub(_ set: DuplicateFinderViewModel.DuplicateSet) -> String {
        let count = set.items.count
        if isSimilar {
            return "\(count) \(count == 1 ? "image" : "images")"
        }
        return "\(count) \(count == 1 ? "copy" : "copies") · \(ByteFormatter.string(fromByteCount: set.copySize)) each"
    }

    private var itemModels: [ReviewItemRow.Model] {
        (viewModel.currentSet?.items ?? []).map { item in
            let kept = viewModel.isKept(path: item.path)
            return ReviewItemRow.Model(
                id: item.path,
                name: (item.path as NSString).lastPathComponent,
                path: item.path,
                sizeText: ByteFormatter.string(fromByteCount: item.size),
                isKept: kept,
                isSelected: !kept && viewModel.selectedPaths.contains(item.path),
                isFocused: viewModel.focusedItem?.path == item.path)
        }
    }

    private var detail: AnyView? {
        guard let item = viewModel.focusedItem else { return nil }
        let keep = viewModel.currentSet?.items.first { viewModel.isKept(path: $0.path) }
        return AnyView(DuplicateSetDetail(item: item,
                                          isKept: viewModel.isKept(path: item.path),
                                          keepItem: keep))
    }

    // MARK: Cleaning

    private var cleaningContent: some View {
        let progress = viewModel.cleaningProgress
        let fraction = progress.map { Double($0.attemptedCount) / Double(max($0.totalCount, 1)) }
        return ScanningView(
            module: module,
            title: progress.map { progress in
                "Moving \(progress.attemptedCount) of \(progress.totalCount) \(progress.totalCount == 1 ? "copy" : "copies") to the Trash…"
            } ?? "Moving copies to the Trash…",
            eyebrow: "Moving to Trash",
            lede: "You can put items back from the Trash in Finder.",
            progress: fraction,
            progressLeading: progress.map { "\($0.attemptedCount) of \($0.totalCount) \($0.totalCount == 1 ? "copy" : "copies")" },
            path: progress?.currentPath)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Done

    private func doneContent(movedBytes: Int64, movedCount: Int, failedCount: Int) -> some View {
        var stats: [DoneView.Stat] = [
            .init(label: "Moved to Trash", value: ByteFormatter.string(fromByteCount: movedBytes), isBytes: true),
            .init(label: "Copies", value: "\(movedCount)"),
            .init(label: "Sets kept", value: "\(viewModel.lastKeptCount)"),
        ]
        // S5: a failure is never folded into the moved figures — it gets its own stat.
        if failedCount > 0 {
            stats.append(.init(label: "Couldn’t move", value: "\(failedCount)"))
        }
        return DoneView(
            hue: module.hue,
            title: "\(ByteFormatter.string(fromByteCount: movedBytes)) moved to the Trash",
            sub: "\(movedCount) extra \(movedCount == 1 ? "copy" : "copies") moved. The newest copy in every set stayed.",
            stats: stats,
            extra: { failureBanners })
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// S5: every failure is surfaced with the engine's own reason. The scroll keeps a large
    /// failure set readable.
    @ViewBuilder
    private var failureBanners: some View {
        if !viewModel.lastFailedItems.isEmpty {
            ScrollView {
                VStack(spacing: Theme.Spacing.s2) {
                    ForEach(Array(viewModel.lastFailedItems.enumerated()), id: \.offset) { _, failure in
                        BannerView(
                            kind: .err,
                            title: "Couldn’t move \((failure.item.path as NSString).lastPathComponent)",
                            text: failure.reason)
                    }
                }
            }
            .frame(maxHeight: 220)
        }
    }

    // MARK: Empty and error

    private var emptyContent: some View {
        let skipped = viewModel.skippedCount
        let base = isSimilar
            ? "No similar images were found in your Home folder."
            : "No identical files were found in your Home folder."
        // Never claim a clean bill of health while files were unreadable.
        let text = skipped > 0
            ? "\(base) \(skipped.formatted()) \(skipped == 1 ? "file was" : "files were") skipped."
            : base
        return StatusStateView(kind: .ok, symbol: "checkmark", title: "No duplicates found", text: text)
    }

    /// §6.3 / OD-18: the engine's reason, then Full Disk Access as instruction text — no
    /// button (the pane has no documented URL).
    private func errorContent(message: String) -> some View {
        StatusStateView(
            kind: .error,
            symbol: "exclamationmark.triangle",
            title: "The scan stopped",
            text: DuplicateFinderViewModel.failureText(reason: message))
    }

    // MARK: - Frame wiring

    /// The frame's actions, one per control a state shows. A missing action disables its
    /// control rather than hiding it (F1) — e.g. "Clean" with nothing selected.
    private var actions: DuplicateFrame.Actions {
        var actions = DuplicateFrame.Actions()
        switch viewModel.phase {
        case .idle:
            actions.primary = { viewModel.startScan() }
        case .scanning:
            actions.stop = { viewModel.cancelScan() }
        case .results:
            // S1: every removal path opens the confirmation first.
            if !viewModel.selectedItems.isEmpty {
                actions.primary = { presentTrashConfirmation(fromResults: true) }
            }
            if !viewModel.sets.isEmpty {
                actions.reviewItems = { viewModel.enterReview() }
            }
            actions.scanAgain = { viewModel.startScan() }
        case .review:
            if !viewModel.selectedItems.isEmpty {
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
    private var selectionSummary: DuplicateFrame.SelectionSummary? {
        switch viewModel.phase {
        case .results, .review:
            DuplicateFrame.SelectionSummary(
                count: viewModel.selectedItems.count,
                // The shared formatter spells zero as the words "Zero KB"; the dock shows a numeral.
                sizeText: viewModel.totalSelectedBytes == 0
                    ? "0 KB"
                    : ConfirmItemList.sizeText(for: viewModel.totalSelectedBytes))
        case .idle, .scanning, .cleaning, .done, .failed:
            nil
        }
    }

    private func presentTrashConfirmation(fromResults: Bool) {
        overlay = .confirmation(viewModel.trashConfirmation(isFromResults: fromResults))
    }

    /// §5.4: "Open Trash" reveals the Trash in Finder. The URL comes from the one documented
    /// API; if it cannot be resolved the action does nothing rather than guessing a path.
    private func openTrash() {
        guard let trashURL = try? FileManager.default.url(
            for: .trashDirectory, in: .userDomainMask, appropriateFor: nil, create: false) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([trashURL])
    }

    // MARK: Toolbar

    /// The match-type segment (spec §5.4): shown where the mode can still change — Start,
    /// Results (including Empty) and Review. Switching discards the current results (the two
    /// passes are separate scans).
    private var toolbarTools: AnyView? {
        switch viewModel.phase {
        case .idle, .results, .review:
            AnyView(
                Picker("Match type", selection: Binding(get: { viewModel.mode },
                                                        set: { viewModel.setMode($0) })) {
                    ForEach(DuplicateFinderViewModel.Mode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel("Match type")
                .accessibilityIdentifier("duplicates-mode"))
        case .scanning, .cleaning, .done, .failed:
            nil
        }
    }

    /// F6: a real subtitle wherever one exists; otherwise the state's default.
    private var toolbarSubtitle: String? {
        switch viewModel.phase {
        case .idle, .done, .failed, .review:
            nil
        case .scanning:
            scanLeadingText
        case .results:
            viewModel.sets.isEmpty
                ? nil
                : "\(viewModel.sets.count.formatted()) \(viewModel.sets.count == 1 ? "set" : "sets")"
        case .cleaning:
            viewModel.cleaningProgress.map { progress in
                "Moving \(progress.attemptedCount) of \(progress.totalCount) \(progress.totalCount == 1 ? "copy" : "copies")…"
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

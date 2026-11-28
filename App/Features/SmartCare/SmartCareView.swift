import SwiftUI
import AppKit
import CleanCore

/// Smart Care on the shared lifecycle frame (plan PR 7). The view owns no screen state
/// of its own: it switches on `viewModel.phase`, composes the shared components, and
/// passes real values into `ModuleScreen` (which owns the toolbar, aurora canvas, dock
/// and sheet). Same spelling as the reference screen (`JunkCleanerView`).
struct SmartCareView: View {
    @Environment(ModuleStore.self) private var store
    private var viewModel: SmartCareViewModel { store.smartCare }

    var body: some View {
        SmartCareScreen(viewModel: viewModel)
    }
}

private struct SmartCareScreen: View {
    @Bindable var viewModel: SmartCareViewModel
    @Environment(ModuleStore.self) private var store

    /// `ModuleScreen`'s nested types carry the frame's generic parameter; a screen that
    /// computes its `Actions`/`SelectionSummary` in properties names them through one
    /// concrete frame and passes its content as `AnyView` (the reference screen's note).
    private typealias SmartCareFrame = ModuleScreen<AnyView>

    /// The sheet `ModuleScreen` presents (OD-4): a `ConfirmSheet` built by the view
    /// model, cleared on dismiss (Escape and Cancel land here too).
    @State private var overlay: ModuleOverlay?

    private let module = ModuleIdentity(module: .smartCare)

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
        .accessibilityIdentifier("smartcare-screen")
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
            // F3: no findings and no failure is the empty state, not a results grid.
            if viewModel.reviewItems.isEmpty && !viewModel.hasModuleFailure {
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
            title: "Junk and duplicates, in one pass",
            lede: "Smart Care scans your caches, duplicate files and your Mac's health together. You see every file before anything moves, and everything goes to the Trash.",
            bullets: [
                StartView.Bullet(symbol: "folder",
                                 title: SmartCareViewModel.junkModuleName,
                                 text: "\(viewModel.junkLocationCount) locations, no extra permission"),
                StartView.Bullet(symbol: "doc.on.doc",
                                 title: SmartCareViewModel.duplicatesModuleName,
                                 text: "The newest copy is always kept"),
                StartView.Bullet(symbol: "gauge",
                                 title: SmartCareViewModel.healthModuleName,
                                 text: "Read-only"),
            ],
            // §6.3: the prototype's "no extra permission" bullet stays, and the note
            // gains the folder-access sentence macOS can really produce.
            note: "The duplicate pass reads every file in the Home folder and can take a few minutes. macOS may ask for access to Desktop, Documents or Downloads the first time.")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var scanningContent: some View {
        ScanningView(
            module: module,
            title: "Looking for junk and duplicates…",
            steps: scanningSteps,
            progress: scanFraction,
            progressLeading: scanLeadingText,
            progressTrailing: scanPercentText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Three step rows (spec §5.2 `scanning`): the two scan legs from the view model's
    /// module statuses, then Health check — done as soon as the read-only snapshot is
    /// in (it reads nothing the user could clean).
    private var scanningSteps: [ScanningView.Step] {
        var steps: [ScanningView.Step] = [
            step(for: SmartCareViewModel.junkModuleName),
            step(for: SmartCareViewModel.duplicatesModuleName),
        ]
        let healthState: StepRowView.StepState = viewModel.performanceSnapshot == nil ? .pending : .done
        steps.append(ScanningView.Step(name: SmartCareViewModel.healthModuleName,
                                       meta: viewModel.performanceSnapshot == nil ? "Waiting…" : "Read",
                                       state: healthState))
        return steps
    }

    private func step(for name: String) -> ScanningView.Step {
        let status = viewModel.moduleStatuses[name] ?? .pending
        switch status {
        case .pending:
            return ScanningView.Step(name: name, meta: "Waiting…", state: .pending)
        case .scanning:
            return ScanningView.Step(name: name, meta: "Scanning…", state: .active)
        case .done(let count):
            return ScanningView.Step(name: name, meta: "Found \(count)", state: .done)
        case .failed:
            return ScanningView.Step(name: name, meta: nil, state: .failed)
        }
    }

    /// The aggregate fraction the view model builds (mean of each in-flight module's own
    /// fraction); `nil` keeps the CTA ring indeterminate rather than guessing.
    private var scanFraction: Double? {
        guard let progress = viewModel.aggregateProgress,
              let total = progress.totalItems, total > 0 else { return nil }
        return min(1, Double(progress.itemsProcessed) / Double(total))
    }

    private var scanLeadingText: String? {
        let doneCount = viewModel.moduleStatuses.values.count { status in
            if case .done = status { return true }
            return false
        }
        return "\(min(doneCount + 1, 2)) of 2 modules"
    }

    private var scanPercentText: String? {
        scanFraction.map { "\(Int(($0 * 100).rounded()))%" }
    }

    // MARK: - Results

    private var resultsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ResultsHeaderView(
                    hue: module.hue,
                    title: viewModel.hasModuleFailure
                        ? "Smart Care finished with a problem"
                        : "Here's what Smart Care found",
                    sub: resultsSubtitle)
                if let failure = moduleFailure {
                    // N4: the error sits next to what failed — above the tiles it names —
                    // with Try Again re-running the whole pass (§4.7, §5.2).
                    BannerView(kind: .err,
                               title: failure.bannerTitle,
                               text: failure.reason) {
                        Button("Try Again") { viewModel.startScan() }
                            .buttonStyle(.sosPlain)
                    }
                    .padding(.bottom, Theme.Spacing.s4)
                }
                LazyVGrid(columns: Self.tileColumns, spacing: Self.tileSpacing) {
                    junkTile
                    duplicatesTile
                }
                .padding(.bottom, Theme.Spacing.s5)
                if let snapshot = viewModel.performanceSnapshot {
                    healthTile(snapshot)
                        .padding(.bottom, Theme.Spacing.s5)
                }
            }
            .padding(EdgeInsets(top: Theme.Spacing.s2, leading: Self.contentPadding, bottom: 0, trailing: Self.contentPadding))
        }
        .accessibilityIdentifier("smartcare-results")
    }

    /// The real counts behind the header's sub line — only the modules that actually
    /// produced figures this scan.
    private var resultsSubtitle: String? {
        var parts: [String] = []
        if viewModel.junkErrorMessage == nil {
            parts.append("\(viewModel.junkItemsCount) junk \(viewModel.junkItemsCount == 1 ? "file" : "files")")
        }
        if viewModel.duplicateErrorMessage == nil {
            parts.append("\(viewModel.duplicateSetCount) duplicate \(viewModel.duplicateSetCount == 1 ? "set" : "sets")")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var junkTile: some View {
        let bytes = viewModel.junkTotalBytes
        let split = Self.valueAndUnit(bytes)
        let isFailed = viewModel.junkErrorMessage != nil
        return ResultTileView(
            hue: module.hue,
            ink: Theme.Hue.Ink.smartcare,
            symbol: "folder",
            label: SmartCareViewModel.junkModuleName,
            value: split.value,
            unit: split.unit,
            caption: isFailed
                ? "Scan stopped"
                : "\(ByteFormatter.string(fromByteCount: viewModel.selectedJunkBytes)) of \(ByteFormatter.string(fromByteCount: bytes)) selected · \(viewModel.junkItemsCount) \(viewModel.junkItemsCount == 1 ? "file" : "files") in \(viewModel.junkLocationCount) locations",
            isSelected: !isFailed && viewModel.selectedJunkCount > 0,
            isSkipped: isFailed)
        {
            if isFailed {
                BadgeView(text: "Failed", style: .risky)
            } else {
                let safeSelected = viewModel.selectedJunkCount - viewModel.selectedCautionJunkCount
                if safeSelected > 0 {
                    BadgeView(text: "\(safeSelected) safe selected", style: .safe)
                }
                if viewModel.cautionJunkCount > 0 {
                    BadgeView(text: "\(viewModel.cautionJunkCount) need a look",
                              style: .caution,
                              systemImage: "exclamationmark.triangle")
                }
            }
        }
        .accessibilityIdentifier("smartcare-tile-junk")
    }

    private var duplicatesTile: some View {
        let isFailed = viewModel.duplicateErrorMessage != nil
        return ResultTileView(
            hue: module.hue,
            ink: Theme.Hue.Ink.smartcare,
            symbol: "doc.on.doc",
            label: SmartCareViewModel.duplicatesModuleName,
            value: "\(viewModel.duplicateSetCount)",
            unit: viewModel.duplicateSetCount == 1 ? "set" : "sets",
            caption: isFailed
                ? "Scan stopped"
                : "\(ByteFormatter.string(fromByteCount: viewModel.selectedDuplicateBytes)) selected · \(viewModel.extraCopyCount) extra \(viewModel.extraCopyCount == 1 ? "copy" : "copies")",
            isSelected: !isFailed && viewModel.selectedDuplicateCount > 0,
            isSkipped: isFailed)
        {
            if isFailed {
                BadgeView(text: "Failed", style: .risky)
            } else {
                // S4: the keep copy is locked everywhere — the badge says so up front.
                BadgeView(text: "Newest copy kept", style: .keep, systemImage: "lock")
            }
        }
        .accessibilityIdentifier("smartcare-tile-duplicates")
    }

    /// §4.3's full tile with the three-column health check as its body — figures from
    /// the one-off `PerformanceSnapshot` (§6.4), read when the scan started.
    private func healthTile(_ snapshot: PerformanceSnapshot) -> some View {
        ResultTileView(
            hue: module.hue,
            ink: Theme.Hue.Ink.smartcare,
            symbol: "gauge",
            label: SmartCareViewModel.healthModuleName,
            value: "",
            caption: "Read when the scan started",
            span: .full)
        {
            HStack(alignment: .top, spacing: Theme.Spacing.s6) {
                healthColumn("Load (1m)",
                             value: snapshot.oneMinuteLoad.map { String(format: "%.2f", $0) } ?? "—")
                healthColumn("Memory",
                             value: memoryLine(snapshot))
                healthColumn("Thermal",
                             value: snapshot.thermalState.rawValue.capitalized)
            }
            .padding(.top, Theme.Spacing.s3)
        }
        .accessibilityIdentifier("smartcare-tile-health")
    }

    private func memoryLine(_ snapshot: PerformanceSnapshot) -> String {
        guard let used = snapshot.memoryUsedBytes, let total = snapshot.memoryTotalBytes else { return "—" }
        return "\(ByteFormatter.string(fromByteCount: Int64(used))) of \(ByteFormatter.string(fromByteCount: Int64(total)))"
    }

    private func healthColumn(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(Theme.Font.callout)
                .foregroundStyle(Theme.Color.textSecondary)
            Text(value)
                .font(Theme.Font.headline)
                .monospacedDigit()
                .foregroundStyle(Theme.Color.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// Splits a formatted byte count into the tile's numeral + unit slots
    /// ("3.4 GB" → "3.4" / "GB"); a one-word result ("820 bytes") is shown whole.
    private static func valueAndUnit(_ bytes: Int64) -> (value: String, unit: String) {
        let text = ByteFormatter.string(fromByteCount: bytes)
        guard let separator = text.firstIndex(where: { $0.isWhitespace }) else {
            return (text, "")
        }
        return (String(text[..<separator]), String(text[text.index(after: separator)...]))
    }

    // MARK: - Review

    private var reviewContent: some View {
        ReviewFrameView(
            sections: reviewSections,
            listHead: listHead,
            items: itemModels,
            onToggleItem: { viewModel.toggleSelection(path: $0.id) },
            onFocusItem: { viewModel.focusItem(path: $0.id) },
            onGroup: { viewModel.selectGroup($0.id) },
            detail: detail)
    }

    /// Two sections in the groups column (spec §5.2 `review`): junk by rule, duplicates
    /// by set. A section with no groups this scan is left out entirely.
    private var reviewSections: [ReviewFrameView.GroupSection] {
        var sections: [ReviewFrameView.GroupSection] = []
        if !viewModel.junkGroups.isEmpty {
            sections.append(ReviewFrameView.GroupSection(id: "junk-section",
                                                         title: SmartCareViewModel.junkModuleName,
                                                         groups: viewModel.junkGroups.map(groupModel)))
        }
        if !viewModel.duplicateGroups.isEmpty {
            sections.append(ReviewFrameView.GroupSection(id: "duplicates-section",
                                                         title: SmartCareViewModel.duplicatesModuleName,
                                                         groups: viewModel.duplicateGroups.map(groupModel)))
        }
        return sections
    }

    private func groupModel(_ group: SmartCareReviewGroup) -> ReviewGroupRow.Model {
        ReviewGroupRow.Model(
            id: group.id,
            label: group.title,
            sub: group.sub,
            selectedCount: group.items.count { viewModel.selectedPaths.contains($0.id) },
            eligibleCount: group.items.count,
            isCurrent: group.id == viewModel.currentGroup?.id)
    }

    private var listHead: ReviewFrameView.ListHead {
        let group = viewModel.currentGroup
        let eligible = group?.items.filter(SmartCareViewModel.isPreSelectable) ?? []
        let selected = group?.items.filter { viewModel.selectedPaths.contains($0.id) } ?? []
        return ReviewFrameView.ListHead(
            title: group?.title ?? "Items",
            sub: group?.sub,
            isSelectAllEnabled: !eligible.allSatisfy { viewModel.selectedPaths.contains($0.id) },
            isDeselectAllEnabled: !selected.isEmpty,
            selectAll: { viewModel.selectAllEligibleInCurrentGroup() },
            deselectAll: { viewModel.deselectAllInCurrentGroup() })
    }

    private var itemModels: [ReviewItemRow.Model] {
        (viewModel.currentGroup?.items ?? []).map { item in
            ReviewItemRow.Model(
                id: item.id,
                name: (item.item.path as NSString).lastPathComponent,
                path: item.item.path,
                sizeText: ByteFormatter.string(fromByteCount: item.item.size),
                badges: badges(for: item),
                isKept: item.isRecommendedKeep,
                isSelected: viewModel.selectedPaths.contains(item.id),
                isFocused: viewModel.focusedItem?.id == item.id)
        }
    }

    private func badges(for item: SmartCareReviewItem) -> [ReviewItemRow.Badge] {
        // Kept rows read "Keep" through the row's own locked badge (§4.6); no second
        // badge next to it.
        guard !item.isRecommendedKeep else { return [] }
        guard item.sourceModule == SmartCareViewModel.junkModuleName else { return [] }
        switch item.item.severity {
        case .safe:
            return [ReviewItemRow.Badge(text: "Safe", style: .safe)]
        case .caution:
            return [ReviewItemRow.Badge(text: "Caution", style: .caution)]
        case .risky:
            return [ReviewItemRow.Badge(text: "Risky", style: .risky)]
        }
    }

    private var detail: AnyView? {
        if let item = viewModel.focusedItem {
            return AnyView(SmartCareReviewDetail(item: item, group: viewModel.currentGroup))
        }
        return nil
    }

    // MARK: - Cleaning, done, empty, error

    private var cleaningContent: some View {
        let progress = viewModel.cleaningProgress
        let fraction = progress.map { Double($0.attemptedCount) / Double(max($0.totalCount, 1)) }
        return ScanningView(
            module: module,
            title: progress.map { progress in
                "Moving \(progress.attemptedCount) of \(progress.totalCount) \(progress.totalCount == 1 ? "item" : "items") to the Trash…"
            } ?? "Moving items to the Trash…",
            eyebrow: "Moving to Trash",
            lede: "You can put items back from the Trash in Finder.",
            progress: fraction,
            progressLeading: progress.map { "\($0.attemptedCount) of \($0.totalCount) items" },
            path: progress?.currentPath)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func doneContent(movedBytes: Int64, movedCount: Int, failedCount: Int) -> some View {
        DoneView(
            hue: module.hue,
            title: "\(ByteFormatter.string(fromByteCount: movedBytes)) moved to the Trash",
            sub: "Smart Care cleared \(movedCount) \(movedCount == 1 ? "item" : "items") from your caches and duplicates.",
            stats: [
                .init(label: "Moved to Trash", value: ByteFormatter.string(fromByteCount: movedBytes), isBytes: true),
                .init(label: "Items", value: "\(movedCount)"),
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

    /// F3's `empty`: "Nothing to clean" · Scan Again (the dock's CTA) · the health tile.
    private var emptyContent: some View {
        VStack(spacing: 0) {
            StatusStateView(
                kind: .ok,
                symbol: "checkmark",
                title: "Nothing to clean",
                text: "No junk and no duplicate copies turned up, and the health check is read-only.")
            if let snapshot = viewModel.performanceSnapshot {
                healthTile(snapshot)
                    .padding(.horizontal, Self.contentPadding)
                    .padding(.bottom, Theme.Spacing.s6)
                    .frame(maxWidth: 760)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorContent(message: String) -> some View {
        // §5.2 `error` (full): the fixed title, the body is the engine's reason.
        StatusStateView(
            kind: .error,
            symbol: "exclamationmark.triangle",
            title: "Smart Care couldn't start",
            text: message)
    }

    // MARK: - Frame wiring

    /// The frame's actions, one per control a state shows. A missing action disables its
    /// control rather than hiding it (F1) — e.g. "Clean" with nothing selected.
    private var actions: SmartCareFrame.Actions {
        var actions = SmartCareFrame.Actions()
        switch viewModel.phase {
        case .idle:
            actions.primary = {
                #if MAS_BUILD
                guard store.masEnsureHomeAccess() else { return }
                #endif
                viewModel.startScan()
            }
        case .scanning:
            actions.stop = { viewModel.cancelScan() }
        case .results:
            // S1: every removal path opens the confirmation first.
            if !viewModel.selectedPaths.isEmpty {
                actions.primary = {
                guard store.pro.require(for: .smartCare) else { return }
                presentTrashConfirmation(fromResults: true)
            }
            }
            if !viewModel.reviewItems.isEmpty {
                actions.reviewItems = { viewModel.enterReview() }
            }
            actions.scanAgain = { viewModel.startScan() }
        case .review:
            if !viewModel.selectedPaths.isEmpty {
                actions.primary = {
                guard store.pro.require(for: .smartCare) else { return }
                presentTrashConfirmation(fromResults: false)
            }
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
    private var selectionSummary: SmartCareFrame.SelectionSummary? {
        switch viewModel.phase {
        case .results, .review:
            SmartCareFrame.SelectionSummary(
                count: viewModel.selectedItems.count,
                sizeText: ConfirmItemList.sizeText(for: viewModel.totalSelectedBytes))
        case .idle, .scanning, .cleaning, .done, .failed:
            nil
        }
    }

    private func presentTrashConfirmation(fromResults: Bool) {
        overlay = .confirmation(viewModel.trashConfirmation(isFromResults: fromResults))
    }

    /// "Open Trash" reveals the Trash in Finder. The URL comes from the one documented
    /// API; if it cannot be resolved the action does nothing rather than guessing a path
    /// (fail closed).
    private func openTrash() {
        guard let trashURL = try? FileManager.default.url(
            for: .trashDirectory, in: .userDomainMask, appropriateFor: nil, create: false) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([trashURL])
    }

    /// F6: a real subtitle wherever one exists; otherwise the state's default.
    private var toolbarSubtitle: String? {
        switch viewModel.phase {
        case .idle, .done, .failed, .review:
            nil
        case .scanning:
            scanLeadingText
        case .results:
            resultsSubtitle
        case .cleaning:
            viewModel.cleaningProgress.map { progress in
                "Moving \(progress.attemptedCount) of \(progress.totalCount) \(progress.totalCount == 1 ? "item" : "items")…"
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

    private static let tileColumns = [
        GridItem(.flexible(), spacing: tileSpacing),
        GridItem(.flexible(), spacing: tileSpacing)
    ]
    private static let tileSpacing: CGFloat = 14
    /// The prototype's `.results` side padding (styles.css).
    private static let contentPadding: CGFloat = 40
}

/// The partial-failure facts the results view renders live in `SmartCareScreen`'s
/// `moduleFailure` helper — which module failed and the banner copy naming it
/// (spec §5.2: "Couldn't finish the duplicate scan").

private extension SmartCareScreen {
    var moduleFailure: (bannerTitle: String, reason: String)? {
        if let reason = viewModel.junkErrorMessage {
            return (bannerTitle: "Couldn't finish the junk scan", reason: reason)
        }
        if let reason = viewModel.duplicateErrorMessage {
            return (bannerTitle: "Couldn't finish the duplicate scan", reason: reason)
        }
        return nil
    }
}

/// The review frame's detail column (spec §4.5): junk rows read like the reference
/// screen's detail (rule, location, size, safety); duplicate rows name their set, the
/// modified date and the keep rule (S4's explanation, right where the user decides).
private struct SmartCareReviewDetail: View {
    let item: SmartCareReviewItem
    let group: SmartCareReviewGroup?

    private var isDuplicate: Bool {
        item.sourceModule == SmartCareViewModel.duplicatesModuleName
    }

    var body: some View {
        ReviewDetailView(title: (item.item.path as NSString).lastPathComponent) {
            if isDuplicate {
                ReviewDetailView.KeyRow(label: "Set", value: group?.title ?? "")
                ReviewDetailView.PathRow(label: "Location", value: item.item.path)
                ReviewDetailView.KeyRow(label: "Size", value: ByteFormatter.string(fromByteCount: item.item.size))
                if let modified = item.item.lastModified {
                    ReviewDetailView.KeyRow(label: "Modified", value: modified.formatted(date: .abbreviated, time: .omitted))
                }
                ReviewDetailView.Explanation(leadIn: isKeep ? "Kept:" : "Extra copy:",
                                             text: isKeep
                                             ? "the newest copy of this set by modified date. SOS Mac never selects it, so the set always keeps one file."
                                             : "a copy of “\(group?.title ?? "the set")”. The newest copy stays on your Mac; moving this one is safe.")
            } else {
                if let rule = item.item.sourceLabel {
                    ReviewDetailView.KeyRow(label: "Rule", value: rule)
                }
                ReviewDetailView.PathRow(label: "Location", value: item.item.path)
                ReviewDetailView.KeyRow(label: "Size", value: ByteFormatter.string(fromByteCount: item.item.size))
                ReviewDetailView.Explanation(leadIn: explanationLeadIn, text: explanationText)
            }
        }
    }

    private var isKeep: Bool { item.isRecommendedKeep }

    private var explanationLeadIn: String {
        item.item.severity == .safe ? "Safe:" : "Caution:"
    }

    private var explanationText: String {
        if item.item.severity == .safe {
            return "a cache the app rebuilds on its own. It goes to the Trash, so you can put it back."
        }
        return "the app that owns this file may rebuild it or lose a setting. Not selected for you; select it only if you know the app."
    }
}

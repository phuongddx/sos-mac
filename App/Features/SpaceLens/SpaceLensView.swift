import SwiftUI
import AppKit
import CleanCore

/// Space Lens on the shared lifecycle frame — plan PR 8 (spec §5.5). The view owns no
/// screen state of its own: it switches on `viewModel.phase`, composes the shared
/// components, and passes real values into `ModuleScreen` (which owns the toolbar,
/// aurora canvas, dock and sheet). The cleanup-list sheet (§4.8) is the screen's
/// review state *and* its confirmation — `ConfirmSheet`'s cleanup-list variant.
struct SpaceLensView: View {
    @Environment(ModuleStore.self) private var store
    private var viewModel: SpaceLensViewModel { store.spaceLens }

    var body: some View {
        SpaceLensScreen(viewModel: viewModel)
    }
}

private struct SpaceLensScreen: View {
    @Bindable var viewModel: SpaceLensViewModel
    @Environment(ModuleStore.self) private var store

    /// `ModuleScreen`'s nested types carry the frame's generic parameter — the same
    /// concrete-frame spelling every screen PR copies (PR 5's `JunkFrame` note).
    private typealias SpaceLensFrame = ModuleScreen<AnyView>

    /// The sheet `ModuleScreen` presents (OD-4): the cleanup list, built by the view
    /// model, cleared on dismiss (Escape and Cancel land here too).
    @State private var overlay: ModuleOverlay?

    private let module = ModuleIdentity(module: .spaceLens)

    /// The prototype's inspector column width (`.lens` grid: 1fr 260px).
    private static let inspectorWidth: CGFloat = 260

    var body: some View {
        SpaceLensFrame(
            module: module,
            state: viewModel.lifecycle,
            subtitle: toolbarSubtitle,
            tools: tools,
            actions: actions,
            selection: selectionSummary,
            overlay: $overlay
        ) {
            AnyView(content)
        }
        .accessibilityIdentifier("space-lens-screen")
        .task {
            #if DEBUG
            viewModel.loadFixtureFromLaunchHooks()
            // The review snapshot renders with the sheet up (the review state *is* the
            // cleanup-list sheet); in a normal run the phase only ever enters `.review`
            // with this same sheet already presented.
            if viewModel.phase == .review {
                overlay = .confirmation(viewModel.cleanupConfirmation())
            }
            #endif
        }
        .onChange(of: viewModel.phase) { _, newPhase in
            if newPhase != .review { overlay = nil }
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
        case .results, .review:
            // F3: an empty folder is the empty state, not a blank map.
            if viewModel.lifecycle == .empty {
                emptyContent
            } else {
                resultsContent
            }
        case .cleaning:
            cleaningContent
        case .done(let movedBytes, let movedCount, let failedCount):
            doneContent(movedBytes: movedBytes, movedCount: movedCount, failedCount: failedCount)
        case .failed(let message):
            errorContent(message: message)
        }
    }

    // MARK: - Start (source list: Home, Choose Folder…, external volumes)

    private var startContent: some View {
        StartView(
            module: module,
            title: "See what fills your disk",
            lede: "Map a folder and click any rectangle to see what it is. Add what you don't need to the cleanup list — nothing moves until you review the list and confirm.",
            extra: { sourceList })
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The source list (§5.5 `start` row): Home (recommended), Choose Folder…, one row
    /// per external volume. A row starts the scan for that location; the dock's Scan
    /// scans the current root (Home on a fresh visit).
    private var sourceList: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s2) {
            sourceRow(symbol: "house", title: "Home", sub: "~ · recommended",
                      hue: Theme.Hue.spacelens, ink: Theme.Hue.Ink.spacelens) {
                #if MAS_BUILD
                // Gate the Home shortcut on the sandbox grant; the panel
                // opens first and the row works on the next tap.
                guard store.masEnsureHomeAccess() else { return }
                #endif
                viewModel.selectHomeFolder()
            }
            .accessibilityIdentifier("spacelens-source-home")
            sourceRow(symbol: "folder", title: "Choose Folder…", sub: "Any folder you can open",
                      hue: Theme.Hue.junk, ink: Theme.Hue.Ink.junk) {
                viewModel.chooseFolder()
            }
            .accessibilityIdentifier("spacelens-source-choose")
            ForEach(viewModel.externalVolumes) { volume in
                sourceRow(symbol: "externaldrive", title: volume.name, sub: volume.url.path,
                          hue: Theme.Hue.cloud, ink: Theme.Hue.Ink.cloud) {
                    viewModel.selectVolume(at: volume.url)
                }
            }
        }
        .padding(.bottom, Theme.Spacing.s2)
        .frame(maxWidth: 560, alignment: .leading)
    }

    private func sourceRow(symbol: String, title: String, sub: String,
                           hue: SwiftUI.Color, ink: SwiftUI.Color,
                           action: @escaping @MainActor () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.s3) {
                ModuleTileView(hue: hue, ink: ink, symbol: symbol, size: .card)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.Color.textPrimary)
                    Text(sub)
                        .font(Theme.Font.callout)
                        .foregroundStyle(Theme.Color.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(Theme.Font.callout)
                    .foregroundStyle(Theme.Color.textTertiary)
            }
            .padding(Theme.Spacing.s2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Scanning (count-only: the total is unknown until the scan ends)

    private var scanningContent: some View {
        ScanningView(
            module: module,
            title: viewModel.isHomeRoot
                ? "Mapping your Home folder…"
                : "Mapping “\(viewModel.rootName)”…",
            lede: "The total isn't known until the scan ends, so there's no percentage.",
            progress: nil,
            countLine: scanCountLine)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("spacelens-scanning")
    }

    private var scanCountLine: String? {
        guard let progress = viewModel.progressTracker.progress else { return "Scanning…" }
        return "Scanned \(progress.itemsProcessed) item\(progress.itemsProcessed == 1 ? "" : "s")…"
    }

    // MARK: - Results (breadcrumb · segment · treemap · legend · inspector)

    private var resultsContent: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                breadcrumbBar
                GeometryReader { geo in
                    let items = viewModel.layoutRects(in: CGRect(origin: .zero, size: geo.size))
                    TreemapCanvasView(
                        items: items,
                        cartPaths: viewModel.selectedPaths,
                        selectedItemID: viewModel.selectedItem?.id,
                        onTap: { viewModel.handleTap(on: $0) },
                        onDrill: { viewModel.drillIn(on: $0) })
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                        .strokeBorder(Theme.Derived.hairline, lineWidth: 1))
                .padding(.horizontal, Theme.Spacing.s5)
                legend
                    .padding(.horizontal, Theme.Spacing.s5)
                    .padding(.vertical, Theme.Spacing.s2)
            }

            Rectangle()
                .fill(Theme.Derived.hairline)
                .frame(width: 1)

            SpaceLensInspector(viewModel: viewModel)
                .frame(width: Self.inspectorWidth)
                .background(inspectorBackground)
        }
        .accessibilityIdentifier("spacelens-results")
    }

    /// The review frame's column material (§4.5): "bgBase 60 % over card".
    @Environment(\.self) private var environment
    private var inspectorBackground: SwiftUI.Color {
        ColorMix.mix(Theme.Color.bgBase, Theme.Color.card, fraction: 0.60, in: environment)
    }

    @ViewBuilder
    private var breadcrumbBar: some View {
        HStack(spacing: Theme.Spacing.s1) {
            switch viewModel.viewMode {
            case .tree:
                let labels = viewModel.breadcrumbLabels
                ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(Theme.Font.subheadline)
                            .foregroundStyle(Theme.Color.textTertiary)
                    }
                    Button(label) { viewModel.zoomOut(to: index) }
                        .buttonStyle(.plain)
                        .font(Theme.Font.callout.weight(index == labels.count - 1 ? .semibold : .regular))
                        .foregroundStyle(index == labels.count - 1 ? Theme.Color.textPrimary : Theme.Color.textSecondary)
                }
            case .category:
                Text("All file types")
                    .font(Theme.Font.callout.weight(.semibold))
                    .foregroundStyle(Theme.Color.textPrimary)
            }
            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.s5)
        .padding(.top, Theme.Spacing.s3)
        .padding(.bottom, Theme.Spacing.s2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Folder path")
    }

    @ViewBuilder
    private var legend: some View {
        switch viewModel.viewMode {
        case .tree:
            HStack(spacing: Theme.Spacing.s5) {
                Label("Area is size. Shades only tell neighbours apart.", systemImage: "info.circle")
                    .font(Theme.Font.callout)
                    .foregroundStyle(Theme.Color.textSecondary)
                HStack(spacing: Theme.Spacing.s2) {
                    Circle()
                        .fill(Theme.Color.neonMagenta)
                        .frame(width: 8, height: 8)
                    Text("In cleanup list")
                        .font(Theme.Font.callout)
                        .foregroundStyle(Theme.Color.textSecondary)
                }
            }
            .accessibilityElement(children: .combine)
        case .category:
            // One row per type: the cell's own hue (D9 — the same mixed fill the map
            // draws, with a 1 pt border in the pure hue), the type's name and its real
            // total — legend and map can never disagree.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], spacing: Theme.Spacing.s1) {
                ForEach(viewModel.categoryLegend, id: \.category) { entry in
                    HStack(spacing: Theme.Spacing.s2) {
                        RoundedRectangle(cornerRadius: Theme.Radius.xs, style: .continuous)
                            .fill(TreemapCanvasView.categoryHue(for: entry.category))
                            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.xs, style: .continuous)
                                .fill(Theme.Derived.treemapMix))
                            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.xs, style: .continuous)
                                .strokeBorder(TreemapCanvasView.categoryHue(for: entry.category), lineWidth: 1))
                            .frame(width: 10, height: 10)
                        Text(entry.category.rawValue)
                            .font(Theme.Font.callout)
                            .foregroundStyle(Theme.Color.textSecondary)
                        Spacer(minLength: Theme.Spacing.s1)
                        Text(ByteFormatter.string(fromByteCount: entry.bytes))
                            .font(Theme.Font.callout)
                            .monospacedDigit()
                            .foregroundStyle(Theme.Color.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    // MARK: - Cleaning / Done / Empty / Error

    private var cleaningContent: some View {
        let progress = viewModel.cleaningProgress
        return ScanningView(
            module: module,
            title: progress.map { progress in
                "Moving \(progress.attemptedCount) of \(progress.totalCount) item\(progress.totalCount == 1 ? "" : "s") to the Trash…"
            } ?? "Moving items to the Trash…",
            eyebrow: "Moving to Trash",
            lede: "You can put items back from the Trash in Finder.",
            progress: progress.map { Double($0.attemptedCount) / Double(max($0.totalCount, 1)) },
            progressLeading: progress.map { "\($0.attemptedCount) of \($0.totalCount) items" },
            path: progress?.currentPath)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("spacelens-cleaning")
    }

    private func doneContent(movedBytes: Int64, movedCount: Int, failedCount: Int) -> some View {
        DoneView(
            hue: module.hue,
            // D6: all-failed leads with the failure, never "0 bytes moved to the Trash";
            // the per-item reasons render below (failureBanners, F4).
            title: SpaceLensViewModel.doneTitle(
                movedBytes: movedBytes, movedCount: movedCount, failedCount: failedCount),
            sub: SpaceLensViewModel.doneSub(
                movedCount: movedCount, failedCount: failedCount, rootName: viewModel.rootName),
            stats: [
                .init(label: "Moved to Trash", value: ByteFormatter.string(fromByteCount: movedBytes), isBytes: true),
                .init(label: "Items", value: "\(movedCount)"),
                .init(label: "Couldn't move", value: "\(failedCount)"),
            ],
            actions: AnyView(
                Button("Back to Map") { viewModel.backToMap() }
                    .sosButton(.prominent)
                    .accessibilityIdentifier("spacelens-back-to-map")),
            extra: { failureBanners })
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// F4: every failure is surfaced with the engine's own reason.
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
        // D5: cleaned-empty is not scanned-empty — the scan found items; this session
        // moved them. The copy never claims the scan found nothing.
        let cleanedEmpty = viewModel.isCleanedEmpty
        return StatusStateView(
            kind: .ok,
            symbol: cleanedEmpty ? "checkmark.circle" : "folder",
            title: SpaceLensViewModel.emptyTitle(isCleanedEmpty: cleanedEmpty, rootName: viewModel.rootName),
            text: SpaceLensViewModel.emptyText(isCleanedEmpty: cleanedEmpty, rootPath: viewModel.rootPath))
        {
            Button("Choose Folder…") { viewModel.chooseFolder() }
                .sosButton(.default)
                .accessibilityIdentifier("spacelens-empty-choose")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorContent(message: String) -> some View {
        StatusStateView(
            kind: .error,
            symbol: "exclamationmark.triangle",
            title: "Couldn't read “\(viewModel.rootName)”",
            text: message)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Frame wiring

    /// The frame's actions, one per control a state shows. A missing action disables its
    /// control rather than hiding it (F1) — e.g. "Clean" with an empty cleanup list.
    private var actions: SpaceLensFrame.Actions {
        var actions = SpaceLensFrame.Actions()
        switch viewModel.phase {
        case .idle:
            actions.primary = { viewModel.startScan() }
        case .scanning:
            actions.stop = { viewModel.cancelScan() }
        case .results:
            if viewModel.lifecycle == .results {
                // S1: the CTA and the review button both open the cleanup-list sheet —
                // the confirmation with checkboxes (the prototype's single "Review…").
                if !viewModel.cleanupItems.isEmpty {
                    actions.primary = {
                    guard store.pro.require(for: .spaceLens) else { return }
                    presentCleanupList()
                }
                    actions.reviewItems = {
                    guard store.pro.require(for: .spaceLens) else { return }
                    presentCleanupList()
                }
                }
                actions.scanAgain = { viewModel.scanAgain() }
            } else {
                // Empty folder (§5.5): scanned-empty keeps "Choose Folder…" as the CTA;
                // a session-emptied folder offers "Scan Again" (D5) — the map can be
                // re-read to show the folder really is empty now.
                if viewModel.isCleanedEmpty {
                    actions.emptyCTATitle = "Scan Again"
                    actions.scanAgain = { viewModel.scanAgain() }
                } else {
                    actions.scanAgain = { viewModel.chooseFolder() }
                }
            }
        case .review:
            break  // the cleanup-list sheet owns the confirm (S1); the bar behind is idle
        case .cleaning:
            break
        case .done:
            // §5.5 done row: the card's "Back to Map" is the prominent action (N7);
            // the dock carries "Scan Again" plus the "Open Trash" trailing secondary.
            actions.scanAgain = { viewModel.scanAgain() }
            actions.openTrash = openTrash
        case .failed:
            actions.primary = { viewModel.scanAgain() }
            actions.escape = SpaceLensFrame.Actions.Escape(
                label: "Choose Another Folder",
                action: { viewModel.chooseFolder() })
        }
        return actions
    }

    /// CF-3: the same selection the dock meta and the sheet title show.
    private var selectionSummary: SpaceLensFrame.SelectionSummary? {
        switch viewModel.phase {
        case .results, .review:
            SpaceLensFrame.SelectionSummary(
                count: viewModel.cleanupItems.count,
                sizeText: ConfirmItemList.sizeText(for: viewModel.totalSelectedBytes))
        case .idle, .scanning, .cleaning, .done, .failed:
            nil
        }
    }

    /// F6: a real subtitle wherever one exists; otherwise the state's default.
    private var toolbarSubtitle: String? {
        switch viewModel.phase {
        case .idle, .review, .done, .failed:
            return nil
        case .scanning:
            return scanCountLine
        case .results:
            guard viewModel.lifecycle == .results else {
                // D5: the state's default word ("Nothing found") would claim the scan
                // found nothing; a session-emptied folder gets its own honest word.
                return viewModel.isCleanedEmpty ? "You moved everything out" : nil
            }
            let count = viewModel.scannedItemCount
            return "Scanned \(count) item\(count == 1 ? "" : "s") in “\(viewModel.rootName)”"
        case .cleaning(let selectedCount):
            return viewModel.cleaningProgress.map { progress in
                "Moving \(progress.attemptedCount) of \(selectedCount) items…"
            }
        }
    }

    /// The By Folder / By Type segment, where the prototype puts it: the toolbar
    /// (`tools`), visible in `results`.
    private var tools: AnyView? {
        guard viewModel.lifecycle == .results else { return nil }
        return AnyView(
            Picker("Group by", selection: Binding(
                get: { viewModel.viewMode },
                set: { viewModel.viewMode = $0 })) {
                ForEach(SpaceLensViewModel.ViewMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 180)
            .accessibilityIdentifier("spacelens-view-mode"))
    }

    private func presentCleanupList() {
        viewModel.beginCleanupReview()
        overlay = .confirmation(viewModel.cleanupConfirmation())
    }

    /// §5.5: "Open Trash" reveals the Trash in Finder; fail closed when it cannot be
    /// resolved rather than guessing a path.
    private func openTrash() {
        guard let trashURL = try? FileManager.default.url(
            for: .trashDirectory, in: .userDomainMask, appropriateFor: nil, create: false) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([trashURL])
    }
}

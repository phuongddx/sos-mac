import SwiftUI
import AppKit
import CleanCore

/// Cloud Cleanup on the shared lifecycle frame (plan PR 11, spec §5.6). The
/// view owns no screen state of its own: it switches on the selected
/// provider's `Phase`, composes the shared components, and passes real values
/// into `ModuleScreen` (which owns the toolbar, aurora canvas, dock/review
/// bar and sheet). Same spelling as the reference screen (`JunkCleanerView`)
/// and the merged PR 6/7/9 screens.
///
/// Every state keeps the providers column (prototype `.cloud` grid):
/// iCloud Drive ("Local scan") plus the three "Not set up in this build"
/// API providers (D5).
struct CloudCleanupView: View {
    @Environment(ModuleStore.self) private var store
    private var viewModel: CloudCleanupViewModel { store.cloudCleanup }

    var body: some View {
        CloudCleanupScreen(viewModel: viewModel)
    }
}

private struct CloudCleanupScreen: View {
    @Bindable var viewModel: CloudCleanupViewModel

    /// `ModuleScreen`'s nested types carry the frame's generic parameter; a
    /// screen that computes its `Actions`/`SelectionSummary` in properties
    /// names them through one concrete frame (the reference screen's note).
    private typealias CloudFrame = ModuleScreen<AnyView>

    @Environment(\.self) private var environment

    /// The sheet `ModuleScreen` presents (OD-4): a `ConfirmSheet` built by
    /// the view model, cleared on dismiss (Escape and Cancel land here too)
    /// and on a provider switch (a confirmation belongs to one provider).
    @State private var overlay: ModuleOverlay?

    /// The frame's toolbar identity: the screen name stays "Cloud Cleanup";
    /// an API provider's review surface carries its provider-named danger
    /// CTA ("Delete from Google Drive…"), iCloud Drive the standard
    /// "Move to Trash…".
    private var frameModule: ModuleIdentity {
        switch viewModel.selectedProvider {
        case .iCloudDrive:
            return ModuleIdentity(module: .cloudCleanup)
        default:
            return ModuleIdentity(name: "Cloud Cleanup",
                                  hue: Theme.Hue.cloud,
                                  symbol: "icloud",
                                  startActionTitle: "Scan",
                                  reviewActionTitle: "Delete from \(viewModel.selectedProvider.rawValue)…")
        }
    }

    /// The eyebrow/orb identity of the state views: the provider's own name
    /// and glyph, as the prototype draws ("iCloud Drive" over the orb).
    private var displayModule: ModuleIdentity {
        ModuleIdentity(name: viewModel.selectedProvider.rawValue,
                       hue: Theme.Hue.cloud,
                       symbol: viewModel.selectedProvider.symbol)
    }

    var body: some View {
        ModuleScreen(
            module: frameModule,
            state: viewModel.lifecycle,
            subtitle: toolbarSubtitle,
            back: toolbarBack,
            actions: actions,
            progress: scanRingProgress,
            selection: selectionSummary,
            overlay: $overlay
        ) {
            AnyView(rootContent)
        }
        .accessibilityIdentifier("cloud-cleanup-screen")
        .onChange(of: viewModel.selectedProvider) {
            overlay = nil
        }
        .task {
            #if DEBUG
            viewModel.loadFixtureFromLaunchHooks()
            #endif
        }
    }

    // MARK: - Root (providers column + the selected provider's surface)

    @ViewBuilder
    private var rootContent: some View {
        HStack(spacing: 0) {
            CloudProvidersColumn(providers: CloudCleanupViewModel.Provider.allCases,
                                 selected: viewModel.selectedProvider,
                                 onSelect: { viewModel.selectProvider($0) })
            mainContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Main area (one branch per Phase — the state table's right column)

    @ViewBuilder
    private var mainContent: some View {
        let provider = viewModel.selectedProvider
        switch viewModel.phase(of: provider) {
        case .notConfigured:
            notConfiguredContent(provider)
        case .idle:
            startContent(provider)
        case .scanning:
            scanningContent(provider)
        case .results:
            if provider == .iCloudDrive {
                if viewModel.sets.isEmpty {
                    emptyContent(provider)
                } else {
                    iCloudResultsContent
                }
            } else {
                if viewModel.apiSets.isEmpty {
                    emptyContent(provider)
                } else {
                    apiResultsContent(provider)
                }
            }
        case .review:
            if provider == .iCloudDrive {
                iCloudReviewContent
            } else {
                apiResultsContent(provider)
            }
        case .cleaning:
            cleaningContent(provider)
        case .done(let movedBytes, let movedCount, let failedCount):
            doneContent(provider, movedBytes: movedBytes, movedCount: movedCount, failedCount: failedCount)
        case .empty:
            emptyContent(provider)
        case .failed(let message):
            errorContent(provider, message: message)
        }
    }

    // MARK: - Not configured (D5)

    /// "«Provider» isn't set up in this build" with the disabled Connect and
    /// the path to iCloud Drive. The frame's dock shows its disabled Scan
    /// CTA (F1: the focal action is present, here truthfully unusable); the
    /// prototype omits the dock in this state — a documented difference.
    private func notConfiguredContent(_ provider: CloudCleanupViewModel.Provider) -> some View {
        StatusStateView(
            kind: .neutral,
            symbol: provider.symbol,
            title: "\(provider.rawValue) isn’t set up in this build",
            text: "Connecting \(provider.rawValue) needs a registered sign-in app, which this build doesn’t have yet. iCloud Drive works now with a local scan.")
        {
            Button("Connect \(provider.rawValue)") {}
                .sosButton(.default)
                .disabled(true)
                .accessibilityIdentifier("cloud-connect-disabled")
            Button("Use iCloud Drive") { viewModel.selectProvider(.iCloudDrive) }
                .sosButton(.prominent)
                .accessibilityIdentifier("cloud-use-icloud")
        }
    }

    // MARK: - Start

    private func startContent(_ provider: CloudCleanupViewModel.Provider) -> some View {
        VStack(spacing: 0) {
            infoBanner(provider)
                .padding(EdgeInsets(top: Theme.Spacing.s4, leading: 24, bottom: 0, trailing: 24))
            StartView(
                module: displayModule,
                title: provider == .iCloudDrive
                    ? "Find duplicates in iCloud Drive"
                    : "Find duplicates in \(provider.rawValue)",
                lede: provider == .iCloudDrive
                    ? "Compares files by content. The newest copy is always kept, and the rest go to the Trash on this Mac."
                    : "Compares the provider’s own content hashes. The newest copy is always kept; deleting extra copies happens on \(provider.rawValue)’s servers.")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// The start banner (§5.6): iCloud's scan is local; an API provider's is
    /// a server listing.
    private func infoBanner(_ provider: CloudCleanupViewModel.Provider) -> some View {
        provider == .iCloudDrive
            ? BannerView(kind: .info,
                         title: "Local scan",
                         text: "Reads iCloud Drive files that are already downloaded to this Mac. Files only in the cloud aren’t checked.")
            : BannerView(kind: .info,
                         title: "Server scan",
                         text: "Reads the file list from \(provider.rawValue) and compares the provider’s own content hashes. Files are never downloaded.")
    }

    // MARK: - Scanning

    private func scanningContent(_ provider: CloudCleanupViewModel.Provider) -> some View {
        let progress = provider == .iCloudDrive ? viewModel.progressTracker.progress : viewModel.apiProgress[provider]
        let listed = progress.map { "\($0.itemsProcessed.formatted()) files listed" }
        return ScanningView(
            module: displayModule,
            title: provider == .iCloudDrive
                ? "Checking iCloud Drive…"
                : "Checking \(provider.rawValue)…",
            steps: provider == .iCloudDrive ? iCloudScanSteps : [],
            progress: scanFraction(provider),
            countLine: provider == .iCloudDrive ? nil : listed,
            progressLeading: progressLeading(provider),
            path: progress?.currentPath)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// iCloud's two legs: list the locally synced files, then compare
    /// contents. The listing pass reports no progress — nothing is made up
    /// (the reference screen's rule).
    private var iCloudScanSteps: [ScanningView.Step] {
        let comparing = viewModel.progressTracker.progress?.totalItems != nil
        return [
            ScanningView.Step(name: "List iCloud Drive files",
                              meta: comparing ? "\(viewModel.iCloudListedCount.formatted()) listed" : nil,
                              state: comparing ? .done : .active),
            ScanningView.Step(name: "Compare contents",
                              meta: comparing ? nil : "Waiting…",
                              state: comparing ? .active : .pending),
        ]
    }

    private func scanFraction(_ provider: CloudCleanupViewModel.Provider) -> Double? {
        guard let progress = provider == .iCloudDrive
            ? viewModel.progressTracker.progress
            : viewModel.apiProgress[provider],
              let total = progress.totalItems, total > 0 else { return nil }
        return min(1, Double(progress.itemsProcessed) / Double(total))
    }

    private func progressLeading(_ provider: CloudCleanupViewModel.Provider) -> String? {
        guard let progress = provider == .iCloudDrive
            ? viewModel.progressTracker.progress
            : viewModel.apiProgress[provider] else { return nil }
        if let total = progress.totalItems {
            return "\(progress.itemsProcessed.formatted()) of \(total.formatted()) \(total == 1 ? "file" : "files")"
        }
        return "\(progress.itemsProcessed.formatted()) files listed"
    }

    // MARK: - iCloud results

    private var iCloudResultsContent: some View {
        let selectedBytes = Self.valueAndUnit(viewModel.totalSelectedBytes)
        let selectedCount = viewModel.selectedItems.count
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ResultsHeaderView(
                    hue: Theme.Hue.cloud,
                    title: resultsTitle,
                    sub: "\(viewModel.listedFileCount.formatted()) files listed · newest copy kept in each set",
                    eyebrow: viewModel.selectedProvider.rawValue)
                LazyVGrid(columns: Self.tileColumns, spacing: Self.tileSpacing) {
                    ResultTileView(
                        hue: Theme.Hue.cloud,
                        ink: Theme.Hue.Ink.cloud,
                        symbol: "doc.on.doc",
                        label: "Sets found",
                        value: viewModel.sets.count.formatted(),
                        unit: "",
                        caption: totalFilesCaption)
                        .accessibilityIdentifier("cloud-tile-sets")
                    ResultTileView(
                        hue: Theme.Hue.cloud,
                        ink: Theme.Hue.Ink.cloud,
                        symbol: "trash",
                        label: "Selected",
                        value: selectedBytes.value,
                        unit: selectedBytes.unit,
                        caption: "\(selectedCount.formatted()) extra \(selectedCount == 1 ? "copy" : "copies") · go to the Trash on this Mac",
                        isSelected: selectedCount > 0)
                    {
                        BadgeView(text: "Newest copy kept", style: .keep, systemImage: "lock")
                    }
                    .accessibilityIdentifier("cloud-tile-selected")
                }
                if viewModel.iCloudSkippedCount > 0 {
                    BannerView(kind: .info,
                               title: "\(viewModel.iCloudSkippedCount.formatted()) files were skipped",
                               text: "They couldn’t be read, so they may be missing from these results.")
                        .padding(.top, Self.tileSpacing)
                }
            }
            .padding(EdgeInsets(top: Theme.Spacing.s2, leading: Self.contentPadding,
                                bottom: Theme.Spacing.s5, trailing: Self.contentPadding))
        }
        .accessibilityIdentifier("cloud-results")
    }

    private var resultsTitle: String {
        let count = viewModel.sets.count
        return "\(count.formatted()) \(count == 1 ? "set" : "sets") of duplicate files"
    }

    private var totalFilesCaption: String {
        let count = viewModel.sets.reduce(0) { $0 + $1.items.count }
        return "\(count.formatted()) \(count == 1 ? "file" : "files")"
    }

    // MARK: - Review lists (all sets inline — the prototype's cloud layout)

    /// The review surfaces draw **every set expanded in one list** (the
    /// prototype's `?screen=cloud&state=review` / `state=drive`): with the
    /// providers column beside them, a groups + items + detail split leaves
    /// the middle column too narrow, and the prototype never uses one for
    /// Cloud. Composed from the shared `ReviewItemRow` and Theme tokens; the
    /// keep lock, the row badges and the selection rules are the frame's.
    private func inlineSetsContent(head: InlineListHead,
                                   banner: BannerView?,
                                   sets: [InlineSet]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                inlineListHead(head)
                if let banner {
                    banner
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(sets) { set in
                    Section {
                        ForEach(set.rows) { row in
                            ReviewItemRow(model: row,
                                          toggle: { viewModel.toggleSelection(key: row.id) },
                                          focus: { })
                        }
                    } header: {
                        setHead(title: set.title, sub: set.sub)
                    }
                }
                // The scroll's breathing room at the bottom.
                Color.clear.frame(height: Theme.Spacing.s5)
            }
        }
        .accessibilityIdentifier("cloud-review")
    }

    /// The review list head (§4.5): title + sub on the left, Select All /
    /// Deselect All on the right, each disabled when it would change nothing.
    private func inlineListHead(_ head: InlineListHead) -> some View {
        HStack(alignment: .center, spacing: Theme.Spacing.s3 - 2) {
            VStack(alignment: .leading, spacing: 2) {
                Text(head.title)
                    .font(Theme.Font.headline)
                    .foregroundStyle(Theme.Color.textPrimary)
                    .lineLimit(1)
                if let sub = head.sub {
                    Text(sub)
                        .font(Theme.Font.subheadline)
                        .foregroundStyle(Theme.Color.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            HStack(spacing: Theme.Spacing.s2 - 2) {
                Button("Select All") { viewModel.selectAllExtras() }
                    .buttonStyle(.sosPlain)
                    .disabled(!head.isSelectAllEnabled)
                    .accessibilityIdentifier("cloud-select-all")
                Button("Deselect All") { viewModel.deselectAll() }
                    .buttonStyle(.sosPlain)
                    .disabled(!head.isDeselectAllEnabled)
                    .accessibilityIdentifier("cloud-deselect-all")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.Derived.hairline).frame(height: 1)
        }
        .background(Theme.Color.card)
        .accessibilityElement(children: .contain)
    }

    /// The prototype's `.set-head`: the set's title and its per-copy line,
    /// pinned while the set's rows scroll past.
    private func setHead(title: String, sub: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Font.headline)
                    .foregroundStyle(Theme.Color.textPrimary)
                    .lineLimit(1)
                Text(sub)
                    .font(Theme.Font.subheadline)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(EdgeInsets(top: 12, leading: 16, bottom: 8, trailing: 16))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ColorMix.mix(Theme.Color.bgBase, Theme.Color.card, fraction: 0.88, in: environment))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.Derived.hairline).frame(height: 1)
        }
        .accessibilityAddTraits(.isHeader)
    }

    /// The head's facts for the selected provider: how many of the extra
    /// copies are already selected gates the two bulk buttons.
    private var iCloudInlineHead: InlineListHead {
        let extras = viewModel.sets.flatMap(\.extraItems)
        let selected = extras.filter { (viewModel.selectedPaths[.iCloudDrive] ?? []).contains($0.path) }
        return InlineListHead(
            title: "\(viewModel.selectedProvider.rawValue) · \(viewModel.sets.count.formatted()) \(viewModel.sets.count == 1 ? "set" : "sets")",
            sub: "The newest copy by date modified is kept.",
            isSelectAllEnabled: selected.count < extras.count,
            isDeselectAllEnabled: !selected.isEmpty)
    }

    private func apiInlineHead(_ provider: CloudCleanupViewModel.Provider) -> InlineListHead {
        let extras = viewModel.apiSets.flatMap(\.extraItems)
        let selected = extras.filter { (viewModel.selectedPaths[provider] ?? []).contains($0.id) }
        return InlineListHead(
            title: "\(provider.rawValue) · \(viewModel.apiSets.count.formatted()) \(viewModel.apiSets.count == 1 ? "set" : "sets")",
            sub: "\(viewModel.listedFileCount.formatted()) files listed. Nothing is selected: deleting happens on \(provider.rawValue)’s servers.",
            isSelectAllEnabled: selected.count < extras.count,
            isDeselectAllEnabled: !selected.isEmpty)
    }

    private var iCloudInlineSets: [InlineSet] {
        viewModel.sets.map { set in
            InlineSet(
                id: set.id,
                title: set.title,
                sub: "\(set.items.count) \(set.items.count == 1 ? "copy" : "copies") · \(ByteFormatter.string(fromByteCount: set.copySize)) each",
                rows: set.items.map { item in
                    let kept = viewModel.isKept(item.path)
                    return ReviewItemRow.Model(
                        id: item.path,
                        name: (item.path as NSString).lastPathComponent,
                        path: item.path,
                        sizeText: ByteFormatter.string(fromByteCount: item.size),
                        isKept: kept,
                        isSelected: !kept && (viewModel.selectedPaths[.iCloudDrive] ?? []).contains(item.path))
                })
        }
    }

    private func apiInlineSets(_ provider: CloudCleanupViewModel.Provider) -> [InlineSet] {
        viewModel.apiSets.map { set in
            InlineSet(
                id: set.id,
                title: set.title,
                sub: "\(set.items.count) \(set.items.count == 1 ? "copy" : "copies") · \(ByteFormatter.string(fromByteCount: set.copySize)) each",
                rows: set.items.map { file in
                    let kept = viewModel.isKept(file.id)
                    return ReviewItemRow.Model(
                        id: file.id,
                        name: file.name,
                        path: file.modifiedDate.map { "Modified \($0.formatted(date: .abbreviated, time: .shortened))" },
                        sizeText: ByteFormatter.string(fromByteCount: file.size),
                        isKept: kept,
                        isSelected: !kept && (viewModel.selectedPaths[provider] ?? []).contains(file.id))
                })
        }
    }

    private var iCloudReviewContent: some View {
        inlineSetsContent(head: iCloudInlineHead, banner: nil, sets: iCloudInlineSets)
    }

    private func apiResultsContent(_ provider: CloudCleanupViewModel.Provider) -> some View {
        inlineSetsContent(head: apiInlineHead(provider),
                          banner: serverDeleteBanner(provider),
                          sets: apiInlineSets(provider))
    }

    /// §4.7/§5.6: the warn banner sits above the list it names.
    private func serverDeleteBanner(_ provider: CloudCleanupViewModel.Provider) -> BannerView {
        BannerView(kind: .warn,
                   title: "Deleting here is not Move to Trash",
                   text: "Files go to \(provider.rawValue)’s own trash, on \(provider.rawValue)’s servers. SOS Mac can’t undo it.")
    }

    // MARK: - Cleaning, done, empty, error

    private func cleaningContent(_ provider: CloudCleanupViewModel.Provider) -> some View {
        let progress = viewModel.cleaningProgress
        let fraction = provider == .iCloudDrive
            ? progress.map { Double($0.attemptedCount) / Double(max($0.totalCount, 1)) }
            : nil // a server-side delete is one call — no per-file progress
        let title = provider == .iCloudDrive
            ? (progress.map { "Moving \($0.attemptedCount) of \($0.totalCount) \($0.totalCount == 1 ? "copy" : "copies") to the Trash…" }
               ?? "Moving copies to the Trash…")
            : (progress.map { "Deleting \($0.attemptedCount) of \($0.totalCount) \($0.totalCount == 1 ? "file" : "files") from \(provider.rawValue)…" }
               ?? "Deleting files…")
        return ScanningView(
            module: displayModule,
            title: title,
            eyebrow: provider == .iCloudDrive ? "Moving to Trash" : "Deleting",
            lede: provider == .iCloudDrive
                ? "You can put items back from the Trash in Finder."
                : "They go to \(provider.rawValue)’s own trash. SOS Mac can’t undo this.",
            progress: fraction,
            progressLeading: progress.map { "\($0.attemptedCount) of \($0.totalCount)" },
            path: provider == .iCloudDrive ? progress?.currentPath : nil)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func doneContent(_ provider: CloudCleanupViewModel.Provider,
                             movedBytes: Int64, movedCount: Int, failedCount: Int) -> some View {
        let stats: [DoneView.Stat] = provider == .iCloudDrive
            ? [
                .init(label: "Moved to Trash", value: ByteFormatter.string(fromByteCount: movedBytes), isBytes: true),
                .init(label: "Copies", value: "\(movedCount)"),
                .init(label: "Couldn’t move", value: "\(failedCount)"),
            ]
            : [
                .init(label: "Deleted", value: "\(movedCount)"),
                .init(label: "Couldn’t delete", value: "\(failedCount)"),
            ]
        return DoneView(
            hue: Theme.Hue.cloud,
            title: provider == .iCloudDrive
                ? "\(ByteFormatter.string(fromByteCount: movedBytes)) moved to the Trash"
                : "\(movedCount.formatted()) \(movedCount == 1 ? "file" : "files") deleted from \(provider.rawValue)",
            sub: provider == .iCloudDrive
                ? "iCloud removes these copies from your other devices once you empty the Trash."
                : "They go to \(provider.rawValue)’s own trash. Restore them from \(provider.rawValue) if it was a mistake.",
            stats: stats,
            extra: { failureBanners(provider) })
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// F4/S6: every failure is surfaced with its own reason, never folded
    /// into a success figure. The scroll keeps a large failure set readable.
    @ViewBuilder
    private func failureBanners(_ provider: CloudCleanupViewModel.Provider) -> some View {
        if provider == .iCloudDrive, !viewModel.lastFailedItems.isEmpty {
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
        } else if provider != .iCloudDrive {
            let failures = viewModel.apiDeleteFailures[provider] ?? []
            let files = viewModel.apiFiles[provider] ?? []
            ScrollView {
                VStack(spacing: Theme.Spacing.s2) {
                    if let wholeError = viewModel.apiDeleteError[provider] {
                        BannerView(kind: .err, title: "Couldn’t delete from \(provider.rawValue)", text: wholeError)
                    }
                    ForEach(failures, id: \.id) { failure in
                        BannerView(
                            kind: .err,
                            title: "Couldn’t delete \(files.first(where: { $0.id == failure.id })?.name ?? failure.id)",
                            text: failure.reason)
                    }
                }
            }
            .frame(maxHeight: 220)
        }
    }

    /// F3's `empty`: "every step succeeded and found nothing" — with the
    /// real listed count, never a bare "nothing found".
    private func emptyContent(_ provider: CloudCleanupViewModel.Provider) -> some View {
        StatusStateView(
            kind: .ok,
            symbol: "checkmark",
            title: provider == .iCloudDrive
                ? "No duplicates in iCloud Drive"
                : "No duplicates in \(provider.rawValue)",
            text: "\(viewModel.listedFileCount.formatted()) files listed. \(provider == .iCloudDrive ? "Every file that’s on this Mac is unique." : "Every file in the account is unique.")")
    }

    /// F5/OD-18: iCloud names Apple Account › iCloud as instruction text —
    /// no button (the pane has no documented URL). The engine's own reason
    /// comes first, as on Duplicate Finder.
    private func errorContent(_ provider: CloudCleanupViewModel.Provider, message: String) -> some View {
        StatusStateView(
            kind: .error,
            symbol: provider == .iCloudDrive ? "icloud" : "exclamationmark.triangle",
            title: provider == .iCloudDrive
                ? "iCloud Drive isn’t available"
                : "The scan stopped",
            text: provider == .iCloudDrive
                ? "\(message) Sign in to iCloud in System Settings and turn on iCloud Drive, then scan again."
                : message)
    }

    // MARK: - Frame wiring

    /// The frame's actions, one per control a state shows. A missing action
    /// disables its control rather than hiding it (F1).
    private var actions: CloudFrame.Actions {
        var actions = CloudFrame.Actions()
        let provider = viewModel.selectedProvider
        switch viewModel.phase(of: provider) {
        case .notConfigured:
            break // no focal action: the provider cannot scan (D5)
        case .idle:
            actions.primary = { viewModel.startScan() }
        case .scanning:
            actions.stop = { viewModel.cancelScan() }
        case .results:
            if provider == .iCloudDrive {
                // S1: the removal path opens the local Trash confirmation first.
                if !viewModel.selectedItems.isEmpty {
                    actions.primary = { presentTrashConfirmation(fromResults: true) }
                }
                if !viewModel.sets.isEmpty {
                    actions.reviewItems = { viewModel.enterReview() }
                }
                actions.scanAgain = { viewModel.startScan() }
            } else {
                // S2: the server-delete surface is its own review; the danger
                // CTA opens the cloud confirmation.
                if !viewModel.selectedFiles.isEmpty {
                    actions.primary = { presentCloudConfirmation() }
                }
            }
        case .review:
            if provider == .iCloudDrive {
                if !viewModel.selectedItems.isEmpty {
                    actions.primary = { presentTrashConfirmation(fromResults: false) }
                }
            } else if !viewModel.selectedFiles.isEmpty {
                actions.primary = { presentCloudConfirmation() }
            }
        case .cleaning:
            break
        case .done:
            actions.scanAgain = { viewModel.startScan() }
            if provider == .iCloudDrive {
                actions.openTrash = openTrash
            }
        case .empty:
            actions.scanAgain = { viewModel.startScan() }
        case .failed:
            actions.primary = { viewModel.startScan() }
        }
        return actions
    }

    /// CF-3: the same selection the review bar and the confirmation show.
    private var selectionSummary: CloudFrame.SelectionSummary? {
        switch viewModel.lifecycle {
        case .results, .review:
            CloudFrame.SelectionSummary(
                count: viewModel.selectedCount,
                // The shared formatter spells zero as the words "Zero KB"; the
                // dock shows a numeral.
                sizeText: viewModel.totalSelectedBytes == 0
                    ? "0 KB"
                    : ConfirmItemList.sizeText(for: viewModel.totalSelectedBytes))
        case .start, .scanning, .cleaning, .done, .empty, .error:
            nil
        }
    }

    private func presentTrashConfirmation(fromResults: Bool) {
        overlay = .confirmation(viewModel.iCloudTrashConfirmation(isFromResults: fromResults))
    }

    private func presentCloudConfirmation() {
        overlay = .confirmation(viewModel.cloudConfirmation(for: viewModel.selectedProvider))
    }

    /// "Open Trash" reveals the Trash in Finder. The URL comes from the one
    /// documented API; if it cannot be resolved the action does nothing
    /// rather than guessing a path (fail closed).
    private func openTrash() {
        guard let trashURL = try? FileManager.default.url(
            for: .trashDirectory, in: .userDomainMask, appropriateFor: nil, create: false) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([trashURL])
    }

    // MARK: - Toolbar

    /// F6: a real subtitle wherever one exists; otherwise the state's
    /// default.
    private var toolbarSubtitle: String? {
        let provider = viewModel.selectedProvider
        switch viewModel.phase(of: provider) {
        case .notConfigured, .idle, .done, .failed:
            return nil
        case .scanning:
            return progressLeading(provider)
        case .results:
            if provider == .iCloudDrive {
                if viewModel.sets.isEmpty { return nil }
                return "\(viewModel.sets.count.formatted()) \(viewModel.sets.count == 1 ? "set" : "sets")"
            }
            return provider.rawValue
        case .review:
            return nil
        case .cleaning:
            guard let progress = viewModel.cleaningProgress else { return nil }
            return provider == .iCloudDrive
                ? "Moving \(progress.attemptedCount) of \(progress.totalCount)…"
                : "Deleting \(progress.attemptedCount) of \(progress.totalCount)…"
        case .empty:
            return nil
        }
    }

    private var toolbarBack: ModuleToolbarModel.Back? {
        guard viewModel.selectedProvider == .iCloudDrive,
              viewModel.phase(of: .iCloudDrive) == .review else { return nil }
        return ModuleToolbarModel.Back(label: "Results", action: { viewModel.backToResults() })
    }

    private var scanRingProgress: Double? {
        guard viewModel.phase(of: viewModel.selectedProvider) == .scanning else { return nil }
        return scanFraction(viewModel.selectedProvider)
    }

    /// Splits a formatted byte count into the tile's numeral + unit slots
    /// ("3.4 GB" → "3.4" / "GB"); zero is shown as "0 KB" — the formatter's
    /// "Zero KB" is a word, not a numeral.
    private static func valueAndUnit(_ bytes: Int64) -> (value: String, unit: String) {
        if bytes == 0 { return ("0", "KB") }
        let text = ByteFormatter.string(fromByteCount: bytes)
        guard let separator = text.firstIndex(where: { $0.isWhitespace }) else {
            return (text, "")
        }
        return (String(text[..<separator]), String(text[text.index(after: separator)...]))
    }

    private static let tileColumns = [
        GridItem(.flexible(), spacing: tileSpacing),
        GridItem(.flexible(), spacing: tileSpacing)
    ]
    private static let tileSpacing: CGFloat = 14
    /// The prototype's `.results` side padding (styles.css).
    private static let contentPadding: CGFloat = 40

    /// The inline review list's head facts: the title/sub lines and the two
    /// bulk buttons' gates (each disabled when it would change nothing).
    private struct InlineListHead {
        let title: String
        var sub: String?
        var isSelectAllEnabled: Bool
        var isDeselectAllEnabled: Bool
    }

    /// One set drawn inline: its header facts and its rows (the prototype's
    /// `.set-head` + its `.irow`s).
    private struct InlineSet: Identifiable {
        let id: String
        let title: String
        let sub: String
        let rows: [ReviewItemRow.Model]
    }
}


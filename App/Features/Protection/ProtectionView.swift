import SwiftUI
import CleanCore

/// Protection on the shared lifecycle frame (plan PR 13, spec §5.10) — built like the Junk &
/// Cache reference screen. The view owns no screen state beyond the sheet binding: it
/// switches on `viewModel.phase`, composes the shared components and passes real values
/// into `ModuleScreen` (toolbar, aurora canvas, dock, sheet).
///
/// Documented deviations from the prototype (also in the PR 13 gallery README):
/// - `results` keeps the frame's hard-coded "Clean" CTA, disabled: a finding is quarantined
///   from its own review, never in bulk. `done` keeps the frame's "Open Trash" dock button,
///   disabled: quarantine is not the Trash. The frame has no label overrides and
///   `ModuleScreen` is outside this PR's write set.
/// - The Quarantine sub-screen has no lifecycle state, so it composes the aurora canvas and
///   toolbar itself (back button "Protection") instead of using the dock.
/// - Review is nothing-pre-selected: the review bar's "Quarantine…" stays disabled until the
///   user checks a finding (spec: never auto-select a quarantine target).
/// - "Check VirusTotal" is removed (OD-15).
struct ProtectionView: View {
    @Environment(ModuleStore.self) private var store
    private var viewModel: ProtectionViewModel { store.protection }

    var body: some View {
        ProtectionScreen(viewModel: viewModel)
    }
}

private struct ProtectionScreen: View {
    @Bindable var viewModel: ProtectionViewModel

    private typealias ProtectionFrame = ModuleScreen<AnyView>

    @State private var overlay: ModuleOverlay?

    private let module = ModuleIdentity(module: .protection)

    private static let contentPadding: CGFloat = 40
    private static let tileSpacing: CGFloat = 14

    var body: some View {
        Group {
            if viewModel.isShowingQuarantine {
                quarantineScreen
            } else {
                frame
            }
        }
        .accessibilityIdentifier("protection-screen")
        .task {
            #if DEBUG
            if UITestHooks.current.fixtures, UITestHooks.current.destination == .protection {
                viewModel.loadFixtureFromLaunchHooks()
                return
            }
            #endif
            viewModel.refreshQuarantineRecords()
        }
    }

    private var frame: some View {
        ModuleScreen(
            module: module,
            state: viewModel.lifecycle,
            subtitle: toolbarSubtitle,
            tools: toolbarTools,
            actions: actions,
            progress: scanFraction,
            selection: selectionSummary,
            overlay: $overlay
        ) {
            AnyView(content)
        }
    }

    // MARK: - Content (one branch per Phase)

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .idle: startContent
        case .scanning: scanningContent
        case .results: viewModel.findings.isEmpty ? AnyView(emptyContent) : AnyView(resultsContent)
        case .review: reviewContent
        case .quarantining: cleaningContent
        case .done(let quarantinedCount, let failedCount):
            doneContent(quarantinedCount: quarantinedCount, failedCount: failedCount)
        case .failed(let message): errorContent(message: message)
        }
    }

    /// D4: what Protection really is, said once on every state that shows a scan's outcome.
    private var disclaimer: some View {
        BannerView(kind: .info,
                   title: "Known-signature scan",
                   text: "Protection checks files against known malware signatures when you run a scan. It isn't real-time antivirus.")
            .padding(EdgeInsets(top: Theme.Spacing.s3, leading: Self.contentPadding, bottom: 0, trailing: Self.contentPadding))
    }

    // MARK: Start

    private var startContent: some View {
        StartView(
            module: module,
            title: "Check for known malware",
            lede: "Scans \(viewModel.locationCount) places where unwanted software usually hides. Anything found is quarantined, never deleted, so you can restore it.",
            note: "Protection checks files against known malware signatures when you run a scan. It isn't real-time antivirus.") {
            VStack(alignment: .leading, spacing: Theme.Spacing.s4) {
                locationChips
                if !viewModel.quarantinedRecords.isEmpty {
                    quarantinePanel(form: .compact)
                }
            }
            .padding(.top, Theme.Spacing.s4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var locationChips: some View {
        let columns = [GridItem(.adaptive(minimum: 150), spacing: Theme.Spacing.s2, alignment: .leading)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.Spacing.s2) {
            ForEach(viewModel.locationSummaries) { location in
                HStack(spacing: Theme.Spacing.s2) {
                    Image(systemName: "folder")
                        .font(.system(size: Theme.TextSize.xs))
                        .foregroundStyle(Theme.Color.textSecondary)
                    Text(location.label)
                        .font(Theme.Font.callout)
                        .foregroundStyle(Theme.Color.textPrimary)
                        .lineLimit(1)
                }
                .padding(.horizontal, Theme.Spacing.s3 - 2)
                .padding(.vertical, Theme.Spacing.s2 - 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).fill(Theme.Color.card))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .strokeBorder(Theme.Derived.hairline, lineWidth: 1))
            }
        }
        .frame(maxWidth: StartView.ledeWidth, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("protection-locations")
    }

    // MARK: Scanning

    private var scanningContent: some View {
        let progress = viewModel.progressTracker.progress
        let total = progress?.totalItems
        let done = progress?.itemsProcessed ?? 0
        return VStack(spacing: 0) {
            disclaimer
            ScanningView(
                module: module,
                title: "Checking files…",
                steps: scanningSteps,
                progress: scanFraction,
                progressLeading: total.map { "\(Self.number(min(done, $0))) of \(Self.number($0)) files" },
                progressTrailing: viewModel.progressTracker.estimatedTimeRemainingText,
                path: progress?.currentPath.map { viewModel.displayPath($0) })
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var scanningSteps: [ScanningView.Step] {
        viewModel.scanStepStates.map { step in
            let state: StepRowView.StepState = switch step.state {
            case .done: .done
            case .active: .active
            case .pending: .pending
            }
            return ScanningView.Step(name: step.label, state: state)
        }
    }

    private var scanFraction: Double? {
        guard viewModel.phase == .scanning,
              let progress = viewModel.progressTracker.progress,
              let total = progress.totalItems, total > 0 else { return nil }
        return min(1, Double(progress.itemsProcessed) / Double(total))
    }

    // MARK: Results

    private var resultsContent: some View {
        let findings = viewModel.findings
        let groups = viewModel.findingGroups
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                disclaimer
                    .padding(.horizontal, -Self.contentPadding)
                ResultsHeaderView(
                    hue: module.hue,
                    title: "\(findings.count) \(findings.count == 1 ? "threat" : "threats") found",
                    sub: resultsSub)
                LazyVGrid(columns: Self.tileColumns, spacing: Self.tileSpacing) {
                    threatTile(findings: findings, groupCount: groups.count)
                    quarantineTile
                }
                .padding(.bottom, Theme.Spacing.s5)
            }
            .padding(EdgeInsets(top: Theme.Spacing.s2, leading: Self.contentPadding, bottom: 0, trailing: Self.contentPadding))
        }
        .accessibilityIdentifier("protection-results")
    }

    private static let tileColumns = [
        GridItem(.flexible(), spacing: tileSpacing),
        GridItem(.flexible(), spacing: tileSpacing)
    ]

    /// The engine's own file count; omitted (never invented) when it reported none.
    private var resultsSub: String {
        let places = "\(viewModel.locationCount) \(viewModel.locationCount == 1 ? "location" : "locations")"
        let checked = viewModel.checkedFileCount > 0
            ? "\(Self.number(viewModel.checkedFileCount)) files checked in \(places). "
            : "Checked \(places). "
        return checked + "Nothing is selected for you."
    }

    private func threatTile(findings: [ThreatFinding], groupCount: Int) -> some View {
        let caption: String
        if let first = findings.first, findings.count == 1 {
            caption = "\((first.path as NSString).lastPathComponent) in \(viewModel.displayFolder(of: first.path))"
        } else {
            caption = "\(findings.count) files in \(groupCount) \(groupCount == 1 ? "location" : "locations")"
        }
        let methods = Array(Set(findings.map(\.detectionMethod))).sorted { $0.rawValue < $1.rawValue }
        return ResultTileView(
            hue: Theme.Hue.threat,
            ink: Theme.Hue.Ink.threat,
            symbol: "exclamationmark.triangle",
            label: "Known threats",
            value: Self.number(findings.count),
            caption: caption) {
            ForEach(methods, id: \.self) { method in
                BadgeView(text: Self.methodName(method), style: .threat, systemImage: "shield")
            }
        }
        .accessibilityIdentifier("protection-tile-threats")
    }

    private var quarantineTile: some View {
        ResultTileView(
            hue: Theme.Hue.protection,
            ink: Theme.Hue.Ink.protection,
            symbol: "lock",
            label: "Already in quarantine",
            value: Self.number(viewModel.quarantinedRecords.count),
            caption: "Restorable at any time")
        .accessibilityIdentifier("protection-tile-quarantine")
    }

    // MARK: Empty / Error

    private var emptyContent: some View {
        let places = "\(viewModel.locationCount) \(viewModel.locationCount == 1 ? "location" : "locations")"
        return VStack(spacing: 0) {
            disclaimer
            StatusStateView(
                kind: .ok,
                symbol: "shield",
                title: "No known threats found",
                text: viewModel.checkedFileCount > 0
                    ? "\(Self.number(viewModel.checkedFileCount)) files checked in \(places)."
                    : "Checked \(places).")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorContent(message: String) -> some View {
        VStack(spacing: 0) {
            disclaimer
            StatusStateView(
                kind: .error,
                symbol: "exclamationmark.triangle",
                title: "The scan stopped",
                text: message) {
                Button("Try Again") { viewModel.startScan() }
                    .sosButton(.default)
                    .accessibilityIdentifier("protection-try-again")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Review

    private var reviewContent: some View {
        ReviewFrameView(
            sections: [ReviewFrameView.GroupSection(id: "protection-locations",
                                                    title: "Findings",
                                                    groups: groupModels)],
            listHead: listHead,
            items: itemModels,
            onToggleItem: { viewModel.toggleSelection(for: $0.id) },
            onFocusItem: { viewModel.focusFinding(path: $0.id) },
            onGroup: { viewModel.selectGroup($0.id) },
            detail: detail)
    }

    private var groupModels: [ReviewGroupRow.Model] {
        let current = viewModel.currentGroup?.id
        return viewModel.findingGroups.map { group in
            ReviewGroupRow.Model(
                id: group.id,
                label: group.label,
                sub: Self.findingCount(group.findings.count),
                selectedCount: group.findings.count { viewModel.selectedPaths.contains($0.path) },
                eligibleCount: group.findings.count,
                isCurrent: group.id == current)
        }
    }

    private var listHead: ReviewFrameView.ListHead {
        let group = viewModel.currentGroup
        let all = group?.findings ?? []
        let selected = all.filter { viewModel.selectedPaths.contains($0.path) }
        return ReviewFrameView.ListHead(
            title: group?.label ?? "Findings",
            sub: group.map { Self.findingCount($0.findings.count) },
            isSelectAllEnabled: selected.count < all.count,
            isDeselectAllEnabled: !selected.isEmpty,
            selectAll: { viewModel.selectAllInCurrentGroup() },
            deselectAll: { viewModel.deselectAllInCurrentGroup() })
    }

    private var itemModels: [ReviewItemRow.Model] {
        (viewModel.currentGroup?.findings ?? []).map { finding in
            ReviewItemRow.Model(
                id: finding.path,
                name: (finding.path as NSString).lastPathComponent,
                path: viewModel.displayPath(finding.path),
                sizeText: ConfirmItemList.sizeText(for: finding.size),
                badges: [ReviewItemRow.Badge(text: Self.methodName(finding.detectionMethod), style: .threat, systemImage: "shield")],
                isSelected: viewModel.selectedPaths.contains(finding.path),
                isFocused: viewModel.focusedFinding?.path == finding.path)
        }
    }

    private var detail: AnyView? {
        guard let finding = viewModel.focusedFinding else { return nil }
        return AnyView(
            ReviewDetailView(title: (finding.path as NSString).lastPathComponent) {
                ReviewDetailView.KeyRow(label: "Detection", value: Self.methodName(finding.detectionMethod))
                ReviewDetailView.PathRow(label: "Identifier", value: finding.identifier)
                ReviewDetailView.KeyRow(label: "Found",
                                        value: finding.detectedAt.formatted(date: .abbreviated, time: .shortened))
                ReviewDetailView.PathRow(label: "Path", value: viewModel.displayPath(finding.path))
                ReviewDetailView.KeyRow(label: "Size", value: ConfirmItemList.sizeText(for: finding.size))
                ReviewDetailView.Explanation(
                    leadIn: "Quarantine is reversible.",
                    text: "The file moves to a folder only SOS Mac uses. Restore puts it back where it was.")
            })
    }

    // MARK: Cleaning

    private var cleaningContent: some View {
        let progress = viewModel.quarantineProgress
        let fraction = progress.map { Double($0.attemptedCount) / Double(max($0.totalCount, 1)) }
        return ScanningView(
            module: module,
            title: progress.map { "Moving \($0.attemptedCount) of \($0.totalCount) \($0.totalCount == 1 ? "item" : "items") to quarantine…" }
                ?? "Moving items to quarantine…",
            eyebrow: "Quarantining",
            lede: "They can't run from quarantine. Restore them from the Quarantine list.",
            progress: fraction,
            progressLeading: progress.map { "\($0.attemptedCount) of \($0.totalCount) items" },
            path: progress?.currentPath.map { viewModel.displayPath($0) })
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Done

    private func doneContent(quarantinedCount: Int, failedCount: Int) -> some View {
        let title: String
        if failedCount == 0 {
            title = "\(quarantinedCount) \(quarantinedCount == 1 ? "item" : "items") quarantined"
        } else if quarantinedCount == 0 {
            title = "Nothing was quarantined"
        } else {
            title = "\(quarantinedCount) quarantined, \(failedCount) couldn't be moved"
        }
        var stats: [DoneView.Stat] = [
            .init(label: "Quarantined", value: "\(quarantinedCount)", isBytes: true),
            .init(label: "In quarantine", value: "\(viewModel.quarantinedRecords.count)"),
        ]
        if failedCount > 0 {
            stats.append(.init(label: "Couldn't move", value: "\(failedCount)"))
        }
        return ScrollView {
            DoneView(
                hue: module.hue,
                title: title,
                sub: quarantinedCount > 0
                    ? "It can't run from quarantine. Restore it if it was a mistake."
                    : "Everything you chose is still where it was.",
                stats: stats,
                actions: AnyView(Button("Open Quarantine") { viewModel.showQuarantine() }
                    .sosButton(.default)
                    .accessibilityIdentifier("protection-open-quarantine")),
                hint: nil,
                extra: { doneExtra })
        }
        .accessibilityIdentifier("protection-done")
    }

    /// F4: every file that did not end up cleanly quarantined is listed with a reason, above
    /// the quarantine list.
    @ViewBuilder
    private var doneExtra: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s3) {
            ForEach(Array(viewModel.lastFailures.enumerated()), id: \.offset) { _, failure in
                BannerView(kind: .err, title: "Couldn't quarantine \(failure.name)", text: failure.reason)
            }
            if !viewModel.quarantinedRecords.isEmpty {
                quarantinePanel(form: .compact)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: Quarantine sub-screen

    private var quarantineScreen: some View {
        VStack(spacing: 0) {
            quarantinePanel(form: .full)
                .padding(EdgeInsets(top: Theme.Spacing.s4, leading: Self.contentPadding, bottom: Theme.Spacing.s5, trailing: Self.contentPadding))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .auroraBackground(hue: module.hue)
        .background(Theme.Color.bgBase)
        .moduleToolbar(ModuleToolbarModel(
            title: module.name,
            subtitle: "Quarantine",
            back: ModuleToolbarModel.Back(label: "Protection", action: { viewModel.hideQuarantine() })))
        .accessibilityIdentifier("protection-quarantine-screen")
    }

    private func quarantinePanel(form: QuarantinePanelView.Form) -> some View {
        QuarantinePanelView(
            records: viewModel.quarantinedRecords,
            form: form,
            hue: module.hue,
            displayFolder: { viewModel.displayPath($0) },
            actionError: viewModel.actionError,
            onRestore: { viewModel.restore($0) },
            onShowAll: { viewModel.showQuarantine() },
            onDismissError: { viewModel.dismissActionError() })
    }

    // MARK: - Frame wiring

    private var actions: ProtectionFrame.Actions {
        var actions = ProtectionFrame.Actions()
        switch viewModel.phase {
        case .idle:
            actions.primary = { viewModel.startScan() }
        case .scanning:
            actions.stop = { viewModel.cancelScan() }
        case .results:
            if viewModel.findings.isEmpty {
                actions.scanAgain = { viewModel.startScan() }
            } else {
                // "Clean" stays disabled: a finding is quarantined from its own review.
                actions.reviewItems = { viewModel.enterReview() }
                actions.scanAgain = { viewModel.startScan() }
            }
        case .review:
            // Every quarantine opens the confirmation first (CF-1).
            if !viewModel.selectedPaths.isEmpty {
                actions.primary = { presentQuarantineConfirmation() }
            }
        case .quarantining:
            break
        case .done:
            actions.scanAgain = { viewModel.startScan() }
        case .failed:
            actions.primary = { viewModel.startScan() }
        }
        return actions
    }

    /// CF-3: the same selection the review bar and the confirmation show.
    private var selectionSummary: ProtectionFrame.SelectionSummary? {
        guard viewModel.phase == .review else { return nil }
        let selected = viewModel.selectedFindings
        return ProtectionFrame.SelectionSummary(
            count: selected.count,
            sizeText: selected.isEmpty ? nil : ConfirmItemList.sizeText(for: viewModel.selectedBytes))
    }

    private func presentQuarantineConfirmation() {
        guard let model = viewModel.quarantineConfirmation() else { return }
        overlay = .confirmation(model)
    }

    /// F6: a real subtitle wherever one exists; otherwise the state's default.
    private var toolbarSubtitle: String? {
        switch viewModel.phase {
        case .idle, .results, .done, .failed:
            nil
        case .scanning:
            scanningSubtitle
        case .review:
            viewModel.currentGroup?.label
        case .quarantining:
            viewModel.quarantineProgress.map {
                "Moving \($0.attemptedCount) of \($0.totalCount) \($0.totalCount == 1 ? "item" : "items")…"
            }
        }
    }

    private var scanningSubtitle: String? {
        guard let progress = viewModel.progressTracker.progress, let total = progress.totalItems, total > 0 else { return nil }
        return "\(Self.number(min(progress.itemsProcessed, total))) of \(Self.number(total)) files"
    }

    /// The quarantine list opens from the toolbar wherever it is safe to leave the screen
    /// (never mid-scan or mid-quarantine), and only when there is something to open.
    private var toolbarTools: AnyView? {
        guard !viewModel.isBusy, viewModel.phase != .review, !viewModel.quarantinedRecords.isEmpty else { return nil }
        return AnyView(
            Button {
                viewModel.showQuarantine()
            } label: {
                Label("Quarantine", systemImage: "lock")
            }
            .sosButton(.default)
            .accessibilityIdentifier("protection-toolbar-quarantine"))
    }

    // MARK: - Formatting

    private static func number(_ value: Int) -> String {
        value.formatted(.number)
    }

    private static func findingCount(_ count: Int) -> String {
        "\(count) \(count == 1 ? "finding" : "findings")"
    }

    private static func methodName(_ method: DetectionMethod) -> String {
        switch method {
        case .hash: "Known signature"
        case .yara: "Pattern rule"
        }
    }
}

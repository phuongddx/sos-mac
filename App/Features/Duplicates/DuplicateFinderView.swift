import SwiftUI
import CleanCore

struct DuplicateFinderView: View {
    @State private var viewModel = DuplicateFinderViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Visible in every phase (not just idle/scanning) — otherwise
            // there's no way to change mode or start over once a scan
            // reaches results/done short of navigating away from the screen.
            Picker("Mode", selection: $viewModel.mode) {
                ForEach(DuplicateFinderViewModel.Mode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(Theme.Spacing.xl)
            .disabled(viewModel.phase == .scanning)

            if viewModel.mode == .similarImages, viewModel.phase != .scanning {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: "exclamationmark.triangle")
                    Text("Similar images are near-matches, not byte-identical copies — review carefully before deleting.")
                }
                .font(.system(size: Theme.TextSize.xs))
                .foregroundStyle(Theme.warn)
                .padding(.horizontal, Theme.Spacing.xxxl)
                .padding(.bottom, Theme.Spacing.sm)
            }

            content

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.system(size: Theme.TextSize.sm))
                    .foregroundStyle(Theme.danger)
                    .padding(Theme.Spacing.lg)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .auroraBloom()
        .navigationTitle("Duplicate Finder")
        .onDisappear { viewModel.cancelScan() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .idle:
            EmptyStateView(
                systemImage: "doc.on.doc",
                title: "Find Duplicates",
                message: "Scans for exact duplicate files, or visually similar images.",
                hue: Theme.hue(for: .duplicateFinder),
                actionTitle: "Start Scan",
                action: { viewModel.startScan() }
            )

        case .scanning:
            scanningView

        case .results:
            resultsView

        case .done(let reclaimedBytes):
            doneView(reclaimedBytes: reclaimedBytes)
        }
    }

    // MARK: - Scanning

    private var scanningView: some View {
        VStack(spacing: Theme.Spacing.lg) {
            ScanProgressPanel(
                progress: viewModel.progressTracker.progress,
                showCurrentPath: true,
                steps: scanningSteps
            )
            .frame(maxWidth: 420)

            Button("Cancel") { viewModel.cancelScan() }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Spacing.giant)
    }

    /// `DuplicateFinder`'s listing phase (`SizeGrouper`/the image-collecting
    /// walk) never calls `onProgress` at all — only the hashing loop does,
    /// and always with a real `totalItems` once it starts — so `progress`
    /// being non-nil is exactly "hashing has begun," with no in-between
    /// state to special-case.
    private var scanningSteps: [ScanProgressPanel.StepModel] {
        let isHashing = viewModel.progressTracker.progress != nil
        return [
            .init(name: "Scanning \(viewModel.mode.rawValue.lowercased())…", meta: nil, state: isHashing ? .done : .active),
            .init(
                name: viewModel.mode == .exact ? "Hashing files…" : "Comparing images…",
                meta: isHashing ? nil : "Waiting…",
                state: isHashing ? .active : .pending
            )
        ]
    }

    // MARK: - Results

    private var resultsView: some View {
        VStack(spacing: 0) {
            resultsHeader
                .padding(.horizontal, Theme.Spacing.xxxl)
                .padding(.top, Theme.Spacing.xxxl)
                .padding(.bottom, Theme.Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    if viewModel.skippedCount > 0 {
                        Text("\(viewModel.skippedCount) file\(viewModel.skippedCount == 1 ? "" : "s") couldn't be scanned and may be missing from these results.")
                            .font(.system(size: Theme.TextSize.xs))
                            .foregroundStyle(Theme.muted)
                    }
                    if viewModel.groups.isEmpty {
                        Text("No duplicates found.")
                            .font(.system(size: Theme.TextSize.sm))
                            .foregroundStyle(Theme.muted)
                    }
                    ForEach(viewModel.groups) { group in
                        groupCard(group)
                    }
                }
                .padding(.horizontal, Theme.Spacing.xxxl)
                .padding(.bottom, Theme.Spacing.xxxl)
            }

            StickyFooterView(
                totalLabel: "Selected for cleanup",
                totalValue: ByteFormatter.string(fromByteCount: viewModel.totalSelectedBytes)
            ) {
                HStack(spacing: Theme.Spacing.md) {
                    Button("New Scan") { viewModel.startNewScan() }
                        .buttonStyle(.bordered)
                    Button("Clean") {
                        Task { await viewModel.clean() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.danger)
                    .disabled(viewModel.selectedPaths.isEmpty)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resultsHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Duplicate Finder")
                .font(.system(size: Theme.TextSize.xl, weight: .semibold))
                .foregroundStyle(Theme.foreground)
            Text(resultsSummary)
                .font(.system(size: Theme.TextSize.sm))
                .foregroundStyle(Theme.muted)
        }
    }

    private var resultsSummary: String {
        let setCount = viewModel.groups.count
        return "\(setCount) duplicate set\(setCount == 1 ? "" : "s") found"
    }

    private func groupCard(_ group: DuplicateGroup) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(groupTitle(group))
                        .font(.system(size: Theme.TextSize.base, weight: .semibold))
                        .foregroundStyle(Theme.foreground)
                    Text(groupSubtitle(group))
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 0)
                BadgeView(text: modeBadgeText, style: modeBadgeStyle)
            }

            VStack(spacing: 0) {
                ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        Rectangle()
                            .fill(Theme.border)
                            .frame(height: 1)
                    }
                    itemRow(item, group: group)
                }
            }
        }
        .careCard()
    }

    private func itemRow(_ item: ScanItem, group: DuplicateGroup) -> some View {
        // The recommended-keep item is never a deletion candidate — its
        // toggle stays disabled so a user can't accidentally select the
        // one copy `DuplicateFinderViewModel` protects by design.
        let isRecommendedKeep = item.path == group.recommendedKeepPath

        return HStack(spacing: Theme.Spacing.md) {
            Toggle("", isOn: Binding(
                get: { viewModel.selectedPaths.contains(item.path) },
                set: { _ in viewModel.toggleSelection(for: item.path) }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .disabled(isRecommendedKeep)

            VStack(alignment: .leading, spacing: 1) {
                Text((item.path as NSString).lastPathComponent)
                    .font(.system(size: Theme.TextSize.sm, weight: .medium))
                    .foregroundStyle(Theme.foreground)
                Text(item.path)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: Theme.Spacing.md)

            if isRecommendedKeep {
                BadgeView(text: "Keep", style: .safe)
            }

            Text(ByteFormatter.string(fromByteCount: item.size))
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.muted)
                .monospacedDigit()
        }
        .padding(.vertical, Theme.Spacing.sm)
    }

    private func groupTitle(_ group: DuplicateGroup) -> String {
        let path = group.recommendedKeepPath ?? group.items.first?.path
        guard let path else { return "Duplicate set" }
        return (path as NSString).lastPathComponent
    }

    private func groupSubtitle(_ group: DuplicateGroup) -> String {
        let count = group.items.count
        let size = ByteFormatter.string(fromByteCount: group.items.first?.size ?? 0)
        return "\(count) copies · \(size) each"
    }

    private var modeBadgeText: String {
        viewModel.mode == .exact ? "Exact match" : "Similar images"
    }

    private var modeBadgeStyle: BadgeStyle {
        viewModel.mode == .exact ? .neutral : .attention
    }

    // MARK: - Done

    private func doneView(reclaimedBytes: Int64) -> some View {
        VStack(spacing: Theme.Spacing.lg) {
            SummaryCardView(
                bigNumber: ByteFormatter.string(fromByteCount: reclaimedBytes),
                caption: "reclaimed"
            )
            .frame(maxWidth: 420)

            HStack(spacing: Theme.Spacing.md) {
                Button("New Scan") { viewModel.startNewScan() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                Button("Back to Results") { viewModel.backToResults() }
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Spacing.giant)
    }
}

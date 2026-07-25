import SwiftUI
import SwiftData
import CleanCore

struct JunkCleanerView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: JunkCleanerViewModel?

    var body: some View {
        Group {
            if let viewModel {
                JunkCleanerContentView(viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        .task {
            if viewModel == nil {
                viewModel = JunkCleanerViewModel(modelContext: modelContext)
            }
        }
        .onDisappear { viewModel?.cancelScan() }
        .navigationTitle("Junk & Cache Scanner")
    }
}

private struct JunkCleanerContentView: View {
    @Bindable var viewModel: JunkCleanerViewModel

    var body: some View {
        VStack(spacing: 0) {
            switch viewModel.phase {
            case .idle:
                EmptyStateView(
                    systemImage: "trash",
                    title: "Scan for junk",
                    message: "Finds caches and logs that are safe to remove.",
                    hue: Theme.hue(for: .junkCleaner),
                    actionTitle: "Start Scan",
                    action: { viewModel.startScan() }
                )

            case .scanning:
                VStack(spacing: Theme.Spacing.lg) {
                    ScanProgressPanel(progress: viewModel.progressTracker.progress, steps: scanningSteps)
                        .frame(maxWidth: 420)
                    Button("Cancel") { viewModel.cancelScan() }
                        .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(Theme.Spacing.giant)

            case .results, .cleaning:
                resultsList
                footer

            case .done(let reclaimedBytes):
                VStack(spacing: Theme.Spacing.lg) {
                    SummaryCardView(
                        bigNumber: ByteFormatter.string(fromByteCount: reclaimedBytes),
                        caption: "reclaimed"
                    )
                    Button("Done") { viewModel.backToResults() }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(Theme.Spacing.xxxl)
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.system(size: Theme.TextSize.sm))
                    .foregroundStyle(Theme.danger)
                    .padding()
            }
        }
        .background(Theme.background)
        .auroraBloom()
    }

    private var resultsList: some View {
        List {
            ForEach(viewModel.items) { item in
                itemRow(item)
                    .listRowBackground(Theme.surface)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
    }

    private func itemRow(_ item: ScanItem) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Toggle(isOn: Binding(
                get: { viewModel.selectedPaths.contains(item.path) },
                set: { isOn in
                    if isOn { viewModel.selectedPaths.insert(item.path) }
                    else { viewModel.selectedPaths.remove(item.path) }
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text((item.path as NSString).lastPathComponent)
                        .font(.system(size: Theme.TextSize.sm, weight: .medium))
                        .foregroundStyle(Theme.foreground)
                    HStack(spacing: Theme.Spacing.sm) {
                        if let label = item.sourceLabel {
                            Text(label)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.muted)
                        }
                        BadgeView(text: item.severity.rawValue.capitalized, style: badgeStyle(for: item.severity))
                        if item.requiresPrivilegedHelper {
                            BadgeView(text: "Needs Helper", style: .neutral)
                        }
                    }
                }
            }
            .toggleStyle(.checkbox)

            Spacer(minLength: 0)

            Text(ByteFormatter.string(fromByteCount: item.size))
                .font(.system(size: Theme.TextSize.sm))
                .foregroundStyle(Theme.muted)
                .monospacedDigit()

            Button("Ignore") { viewModel.ignore(item) }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.muted)
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    private func badgeStyle(for severity: Severity) -> BadgeStyle {
        switch severity {
        case .safe: return .safe
        case .caution: return .attention
        case .risky: return .risk
        }
    }

    /// Rule `i` is done once `itemsProcessed > i` completed rules have been
    /// reported; the very next rule in order is `.active`; everything after
    /// that is `.pending`. There's no per-rule "started" signal from the
    /// engine (only "rule N completed"), so rule 0 shows `.active`
    /// immediately at `itemsProcessed == 0` — the best available
    /// approximation without adding a start-of-rule callback nobody else needs.
    private var scanningSteps: [ScanProgressPanel.StepModel] {
        let completedCount = viewModel.progressTracker.progress?.itemsProcessed ?? 0
        return viewModel.ruleLabels.enumerated().map { index, label in
            let state: StepRowView.StepState = index < completedCount ? .done : (index == completedCount ? .active : .pending)
            return ScanProgressPanel.StepModel(name: label, meta: nil, state: state)
        }
    }

    private var footer: some View {
        StickyFooterView(
            totalLabel: "Total reclaimable",
            totalValue: ByteFormatter.string(fromByteCount: viewModel.totalSelectedBytes)
        ) {
            Button("Clean") {
                Task { await viewModel.clean() }
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .disabled(viewModel.selectedPaths.isEmpty || viewModel.phase == .cleaning)
        }
    }
}

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
                    actionTitle: "Start Scan",
                    action: { Task { await viewModel.startScan() } }
                )

            case .scanning:
                VStack(spacing: Theme.Spacing.md) {
                    ProgressView()
                    Text("Scanning your Mac for junk and cache files…")
                        .font(.system(size: Theme.TextSize.sm))
                        .foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

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

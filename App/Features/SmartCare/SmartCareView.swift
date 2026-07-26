import SwiftUI
import CleanCore

struct SmartCareView: View {
    @State private var viewModel = SmartCareViewModel()

    var body: some View {
        VStack(spacing: 0) {
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
        .navigationTitle("Smart Care")
        .onDisappear { viewModel.cancelScan() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .idle:
            idleState

        case .scanning:
            scanningState

        case .review, .cleaning:
            VStack(spacing: 0) {
                reviewList
                StickyFooterView(
                    totalLabel: "Total selected",
                    totalValue: ByteFormatter.string(fromByteCount: viewModel.totalSelectedBytes)
                ) {
                    Button("Clean Selected", role: .destructive) {
                        Task { await viewModel.clean() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.danger)
                    .controlSize(.large)
                    .disabled(viewModel.selectedPaths.isEmpty || viewModel.phase == .cleaning)
                }
            }

        case .summary(let reclaimedBytes, let itemCount, let failureCount):
            summaryState(reclaimedBytes: reclaimedBytes, itemCount: itemCount, failureCount: failureCount)
        }
    }

    private var idleState: some View {
        EmptyStateView(
            systemImage: "wand.and.stars",
            title: "Run Smart Care",
            message: "Smart Care runs Junk & Cache cleanup and Duplicate Finder together, with a quick health check — nothing is deleted without your review.",
            hue: Theme.hue(for: .smartCare),
            actionTitle: "Run Smart Care",
            action: { viewModel.startScan() }
        )
    }

    private var scanningState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                if let aggregate = viewModel.aggregateProgress {
                    ScanProgressPanel(progress: aggregate)
                }
                ForEach([SmartCareViewModel.junkModuleName, SmartCareViewModel.duplicatesModuleName], id: \.self) { name in
                    stepRow(for: name, status: viewModel.moduleStatuses[name] ?? .pending)
                }
            }
            .padding(Theme.Spacing.xxxl)
        }
    }

    @ViewBuilder
    private func stepRow(for name: String, status: SmartCareViewModel.ModuleStatus) -> some View {
        switch status {
        case .pending:
            StepRowView(name: name, meta: "Waiting…", state: .pending)
        case .scanning:
            StepRowView(name: name, meta: "Scanning…", state: .active)
        case .done(let count):
            StepRowView(name: name, meta: "Found \(count)", state: .done)
        case .failed:
            // Don't force a StepRowView.State that doesn't exist for
            // "failed" — keep the row neutral and surface the failure via
            // a risk badge alongside it instead.
            StepRowView(name: name, meta: nil, state: .pending)
                .overlay(alignment: .trailing) {
                    BadgeView(text: "Failed", style: .risk)
                        .padding(.trailing, Theme.Spacing.lg)
                }
        }
    }

    private var reviewList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                if let snapshot = viewModel.performanceSnapshot {
                    healthCheckCard(snapshot)
                }

                ForEach(groupedReviewItems, id: \.module) { group in
                    reviewGroupCard(group)
                }

                if viewModel.reviewItems.isEmpty {
                    Text("Nothing found — you're all clean.")
                        .font(.system(size: Theme.TextSize.sm))
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(Theme.Spacing.xxxl)
                }
            }
            .padding(Theme.Spacing.xxxl)
        }
    }

    private func healthCheckCard(_ snapshot: PerformanceSnapshot) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Health Check")
                .font(.system(size: Theme.TextSize.base, weight: .semibold))
                .foregroundStyle(Theme.foreground)

            if let load = snapshot.oneMinuteLoad {
                healthRow("Load Average (1m)", value: String(format: "%.2f", load))
            }
            if let used = snapshot.memoryUsedBytes, let total = snapshot.memoryTotalBytes {
                healthRow("Memory", value: "\(ByteFormatter.string(fromByteCount: Int64(used))) / \(ByteFormatter.string(fromByteCount: Int64(total)))")
            }
            healthRow("Thermal State", value: snapshot.thermalState.rawValue.capitalized)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .careCard()
    }

    private func healthRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: Theme.TextSize.sm))
                .foregroundStyle(Theme.muted)
            Spacer()
            Text(value)
                .font(.system(size: Theme.TextSize.sm, weight: .medium))
                .foregroundStyle(Theme.foreground)
        }
    }

    private func reviewGroupCard(_ group: ReviewGroup) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text(group.module)
                    .font(.system(size: Theme.TextSize.base, weight: .semibold))
                    .foregroundStyle(Theme.foreground)
                Spacer()
                Text(ByteFormatter.string(fromByteCount: group.totalBytes))
                    .font(.system(size: Theme.TextSize.sm))
                    .foregroundStyle(Theme.muted)
            }

            VStack(spacing: Theme.Spacing.sm) {
                ForEach(group.items) { reviewItem in
                    reviewItemRow(reviewItem)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .careCard()
    }

    private func reviewItemRow(_ reviewItem: SmartCareReviewItem) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Toggle(isOn: Binding(
                get: { viewModel.selectedPaths.contains(reviewItem.item.path) },
                set: { _ in viewModel.toggleSelection(for: reviewItem.item.path) }
            )) {
                Text((reviewItem.item.path as NSString).lastPathComponent)
                    .font(.system(size: Theme.TextSize.sm))
                    .foregroundStyle(Theme.foreground)
            }
            .toggleStyle(.checkbox)

            Spacer()

            Text(ByteFormatter.string(fromByteCount: reviewItem.item.size))
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.muted)
                .monospacedDigit()
        }
    }

    private struct ReviewGroup {
        let module: String
        let items: [SmartCareReviewItem]
        var totalBytes: Int64 { items.reduce(0) { $0 + $1.item.size } }
    }

    private var groupedReviewItems: [ReviewGroup] {
        Dictionary(grouping: viewModel.reviewItems, by: \.sourceModule)
            .map { ReviewGroup(module: $0.key, items: $0.value) }
            .sorted { $0.module < $1.module }
    }

    private func summaryState(reclaimedBytes: Int64, itemCount: Int, failureCount: Int) -> some View {
        VStack(spacing: Theme.Spacing.xl) {
            SummaryCardView(
                bigNumber: "\(ByteFormatter.string(fromByteCount: reclaimedBytes)) reclaimed",
                caption: "Smart Care reclaimed space across \(itemCount) item\(itemCount == 1 ? "" : "s")"
            )

            if failureCount > 0 {
                BadgeView(text: "\(failureCount) item\(failureCount == 1 ? "" : "s") failed", style: .risk)
            }

            Button("New Scan") { viewModel.startNewScan() }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .controlSize(.large)
        }
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Spacing.xxxl)
    }
}

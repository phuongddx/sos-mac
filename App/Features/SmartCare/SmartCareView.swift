import SwiftUI
import CleanCore

struct SmartCareView: View {
    @State private var viewModel = SmartCareViewModel()

    var body: some View {
        VStack(spacing: 0) {
            content

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage).foregroundStyle(.red).padding()
            }
        }
        .navigationTitle("Smart Care")
        .onDisappear { viewModel.cancelScan() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .idle:
            ContentUnavailableView(
                "Smart Care",
                systemImage: "sparkles",
                description: Text("Runs Junk & Cache and Duplicate Finder together, with a quick health check — nothing is deleted without your review.")
            )
            Button("Run Smart Care") { viewModel.startScan() }
                .padding()

        case .scanning:
            scanningProgress

        case .review, .cleaning:
            reviewList
            footer

        case .summary(let reclaimedBytes, let itemCount, let failureCount):
            ContentUnavailableView(
                "Smart Care Complete",
                systemImage: "checkmark.circle",
                description: Text(summaryDescription(reclaimedBytes: reclaimedBytes, itemCount: itemCount, failureCount: failureCount))
            )
            Button("New Scan") { viewModel.startNewScan() }
                .padding()
        }
    }

    private var scanningProgress: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach([SmartCareViewModel.junkModuleName, SmartCareViewModel.duplicatesModuleName], id: \.self) { name in
                HStack {
                    Text(name)
                    Spacer()
                    statusView(for: viewModel.moduleStatuses[name] ?? .pending)
                }
            }
        }
        .padding()
    }

    @ViewBuilder
    private func statusView(for status: SmartCareViewModel.ModuleStatus) -> some View {
        switch status {
        case .pending:
            Text("Waiting…").foregroundStyle(.secondary)
        case .scanning:
            ProgressView().scaleEffect(0.6)
        case .done(let count):
            Text("Found \(count)").foregroundStyle(.secondary)
        case .failed:
            Text("Failed").foregroundStyle(.red)
        }
    }

    private var reviewList: some View {
        List {
            if let snapshot = viewModel.performanceSnapshot {
                Section("Health Check") {
                    if let load = snapshot.oneMinuteLoad {
                        healthRow("Load Average (1m)", value: String(format: "%.2f", load))
                    }
                    if let used = snapshot.memoryUsedBytes, let total = snapshot.memoryTotalBytes {
                        healthRow("Memory", value: "\(ByteFormatter.string(fromByteCount: Int64(used))) / \(ByteFormatter.string(fromByteCount: Int64(total)))")
                    }
                    healthRow("Thermal State", value: snapshot.thermalState.rawValue.capitalized)
                }
            }

            ForEach(groupedReviewItems, id: \.module) { group in
                Section("\(group.module) (\(ByteFormatter.string(fromByteCount: group.totalBytes)))") {
                    ForEach(group.items) { reviewItem in
                        HStack {
                            Toggle(isOn: Binding(
                                get: { viewModel.selectedPaths.contains(reviewItem.item.path) },
                                set: { _ in viewModel.toggleSelection(for: reviewItem.item.path) }
                            )) {
                                Text((reviewItem.item.path as NSString).lastPathComponent)
                            }
                            Spacer()
                            Text(ByteFormatter.string(fromByteCount: reviewItem.item.size))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if viewModel.reviewItems.isEmpty {
                Text("Nothing found — you're all clean.").foregroundStyle(.secondary)
            }
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

    private func healthRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack {
            Text("Total: \(ByteFormatter.string(fromByteCount: viewModel.totalSelectedBytes))")
            Spacer()
            Button("Clean Selected", role: .destructive) {
                Task { await viewModel.clean() }
            }
            .disabled(viewModel.selectedPaths.isEmpty || viewModel.phase == .cleaning)
        }
        .padding()
    }

    private func summaryDescription(reclaimedBytes: Int64, itemCount: Int, failureCount: Int) -> String {
        var text = "Reclaimed \(ByteFormatter.string(fromByteCount: reclaimedBytes)) across \(itemCount) item\(itemCount == 1 ? "" : "s")."
        if failureCount > 0 {
            text += " \(failureCount) item\(failureCount == 1 ? "" : "s") couldn't be removed."
        }
        return text
    }
}

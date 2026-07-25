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
            .padding()
            .disabled(viewModel.phase == .scanning)

            if viewModel.mode == .similarImages, viewModel.phase != .scanning {
                Text("Similar images are near-matches, not byte-identical copies — review carefully before deleting.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal)
            }

            content

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage).foregroundStyle(.red).padding()
            }
        }
        .navigationTitle("Duplicate Finder")
        .onDisappear { viewModel.cancelScan() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .idle:
            ContentUnavailableView(
                "Find Duplicates",
                systemImage: "doc.on.doc",
                description: Text("Scans for exact duplicate files, or visually similar images.")
            )
            Button("Start Scan") { viewModel.startScan() }
                .padding()

        case .scanning:
            ProgressView("Scanning…").padding()
            Button("Cancel") { viewModel.cancelScan() }

        case .results:
            resultsList
            footer

        case .done(let reclaimedBytes):
            ContentUnavailableView(
                "Cleaned up",
                systemImage: "checkmark.circle",
                description: Text("Reclaimed \(ByteFormatter.string(fromByteCount: reclaimedBytes))")
            )
            HStack {
                Button("Done") { viewModel.backToResults() }
                Button("New Scan") { viewModel.startNewScan() }
            }
            .padding()
        }
    }

    private var resultsList: some View {
        List {
            if viewModel.skippedCount > 0 {
                Text("\(viewModel.skippedCount) file\(viewModel.skippedCount == 1 ? "" : "s") couldn't be scanned and may be missing from these results.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if viewModel.groups.isEmpty {
                Text("No duplicates found.").foregroundStyle(.secondary)
            }
            ForEach(viewModel.groups) { group in
                Section {
                    ForEach(group.items) { item in
                        HStack {
                            Toggle(isOn: Binding(
                                get: { viewModel.selectedPaths.contains(item.path) },
                                set: { _ in viewModel.toggleSelection(for: item.path) }
                            )) {
                                VStack(alignment: .leading) {
                                    Text((item.path as NSString).lastPathComponent)
                                    Text(item.path).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            Spacer()
                            if item.path == group.recommendedKeepPath {
                                Text("Keep").font(.caption).foregroundStyle(.green)
                            }
                            Text(ByteFormatter.string(fromByteCount: item.size))
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("\(group.items.count) copies · \(ByteFormatter.string(fromByteCount: group.items.first?.size ?? 0)) each")
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("Total: \(ByteFormatter.string(fromByteCount: viewModel.totalSelectedBytes))")
            Spacer()
            Button("New Scan") { viewModel.startNewScan() }
            Button("Clean", role: .destructive) {
                Task { await viewModel.clean() }
            }
            .disabled(viewModel.selectedPaths.isEmpty)
        }
        .padding()
    }
}

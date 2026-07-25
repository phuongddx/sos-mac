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
                ContentUnavailableView(
                    "Scan for junk",
                    systemImage: "trash",
                    description: Text("Finds caches and logs that are safe to remove.")
                )
                Button("Start Scan") {
                    Task { await viewModel.startScan() }
                }
                .padding()

            case .scanning:
                ProgressView("Scanning…")
                    .padding()

            case .results, .cleaning:
                resultsList
                footer

            case .done(let reclaimedBytes):
                ContentUnavailableView(
                    "Cleaned up",
                    systemImage: "checkmark.circle",
                    description: Text("Reclaimed \(ByteFormatter.string(fromByteCount: reclaimedBytes))")
                )
                Button("Done") { viewModel.backToResults() }
                    .padding()
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .padding()
            }
        }
    }

    private var resultsList: some View {
        List {
            ForEach(viewModel.items) { item in
                HStack {
                    Toggle(isOn: Binding(
                        get: { viewModel.selectedPaths.contains(item.path) },
                        set: { isOn in
                            if isOn { viewModel.selectedPaths.insert(item.path) }
                            else { viewModel.selectedPaths.remove(item.path) }
                        }
                    )) {
                        VStack(alignment: .leading) {
                            Text((item.path as NSString).lastPathComponent)
                            if let label = item.sourceLabel {
                                Text(label)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(item.requiresPrivilegedHelper)

                    Spacer()
                    Text(ByteFormatter.string(fromByteCount: item.size))
                        .foregroundStyle(.secondary)

                    Button("Ignore") { viewModel.ignore(item) }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("Total: \(ByteFormatter.string(fromByteCount: viewModel.totalSelectedBytes))")
            Spacer()
            Button("Clean") {
                Task { await viewModel.clean() }
            }
            .disabled(viewModel.selectedPaths.isEmpty || viewModel.phase == .cleaning)
        }
        .padding()
    }
}

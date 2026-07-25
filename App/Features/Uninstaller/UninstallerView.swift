import SwiftUI
import CleanCore

struct UninstallerView: View {
    @State private var viewModel = UninstallerViewModel()

    var body: some View {
        content
            .navigationTitle("Uninstaller")
            .task { viewModel.loadApps() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .browsing:
            browsingList

        case .inspecting:
            inspectingList

        case .removed(let appName, let reclaimedBytes):
            ContentUnavailableView(
                "\(appName) removed",
                systemImage: "checkmark.circle",
                description: Text("Reclaimed \(ByteFormatter.string(fromByteCount: reclaimedBytes))")
            )
            Button("Done") { viewModel.backToBrowsing() }
                .padding()
        }
    }

    private var browsingList: some View {
        List(viewModel.apps) { row in
            HStack {
                Text(row.app.name)
                Spacer()
                if let version = row.app.version {
                    Text(version).foregroundStyle(.secondary)
                }
                if viewModel.inspectingBundleID == row.app.bundleIdentifier {
                    ProgressView().scaleEffect(0.6)
                } else {
                    Button("Inspect") {
                        Task { await viewModel.inspect(row) }
                    }
                    .disabled(viewModel.inspectingBundleID != nil)
                }
            }
        }
    }

    private var inspectingList: some View {
        VStack(spacing: 0) {
            List(viewModel.associatedItems) { item in
                HStack {
                    Toggle(isOn: Binding(
                        get: { viewModel.selectedPaths.contains(item.path) },
                        set: { isOn in
                            if isOn { viewModel.selectedPaths.insert(item.path) }
                            else { viewModel.selectedPaths.remove(item.path) }
                        }
                    )) {
                        VStack(alignment: .leading) {
                            Text(item.path).font(.caption).lineLimit(1)
                            if let label = item.sourceLabel {
                                Text(label).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Spacer()
                    Text(ByteFormatter.string(fromByteCount: item.size))
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Button("Cancel") { viewModel.cancelInspection() }
                Spacer()
                Button("Uninstall", role: .destructive) {
                    let appName = currentAppName
                    Task { await viewModel.confirmUninstall(appName: appName) }
                }
                .disabled(viewModel.selectedPaths.isEmpty)
            }
            .padding()
        }
    }

    private var currentAppName: String {
        guard case .inspecting(let bundleID) = viewModel.phase,
              let row = viewModel.apps.first(where: { $0.app.bundleIdentifier == bundleID })
        else { return "App" }
        return row.app.name
    }
}

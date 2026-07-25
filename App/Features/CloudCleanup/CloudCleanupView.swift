import SwiftUI
import CleanCore

struct CloudCleanupView: View {
    @State private var viewModel = CloudCleanupViewModel()
    @State private var selectedTab: Tab = .googleDrive

    private enum Tab: String, CaseIterable, Identifiable {
        case googleDrive = "Google Drive"
        case dropbox = "Dropbox"
        case oneDrive = "OneDrive"
        case iCloud = "iCloud Drive"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Provider", selection: $selectedTab) {
                ForEach(Tab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            switch selectedTab {
            case .googleDrive:
                apiProviderView(.googleDrive)
            case .dropbox:
                apiProviderView(.dropbox)
            case .oneDrive:
                apiProviderView(.oneDrive)
            case .iCloud:
                iCloudView
            }
        }
        .navigationTitle("Cloud Cleanup")
    }

    // MARK: - API providers (Google Drive / Dropbox / OneDrive)

    @ViewBuilder
    private func apiProviderView(_ kind: CloudCleanupViewModel.APIProviderKind) -> some View {
        let state = viewModel.apiStates[kind] ?? CloudAPIProviderState()

        VStack(spacing: 0) {
            Text("Connects over the real \(kind.rawValue) API — file list and delete actions happen on the server, not just locally.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            if !state.isAuthenticated {
                ContentUnavailableView(
                    "Connect \(kind.rawValue)",
                    systemImage: "link",
                    description: Text("Sign in to scan for duplicates and free up space.")
                )
                Button("Connect") {
                    Task { await viewModel.connect(kind) }
                }
                .disabled(state.isLoading)
                .padding()
            } else {
                HStack {
                    Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    Spacer()
                    Button("Refresh") { Task { await viewModel.loadFiles(kind) } }
                    Button("Disconnect") { Task { await viewModel.disconnect(kind) } }
                }
                .padding()

                if state.isLoading {
                    ProgressView("Loading…").padding()
                } else {
                    List {
                        if state.duplicateGroups.isEmpty {
                            Text("No duplicate files found.").foregroundStyle(.secondary)
                        }
                        ForEach(state.duplicateGroups) { group in
                            Section("\(group.files.count) copies") {
                                ForEach(group.files) { file in
                                    let isRecommendedKeep = file.id == group.recommendedKeepID
                                    HStack {
                                        Text(file.name)
                                        Spacer()
                                        if isRecommendedKeep {
                                            Text("Keep").font(.caption).foregroundStyle(.green)
                                        }
                                        Text(ByteFormatter.string(fromByteCount: file.size))
                                            .foregroundStyle(.secondary)
                                        // Never let the newest/recommended copy in a
                                        // group be deleted without an explicit second
                                        // step — mirrors Phase 3/5's local "keep
                                        // newest" protection, which cloud duplicates
                                        // had none of before this fix.
                                        Button("Delete", role: .destructive) {
                                            Task { await viewModel.delete([file.id], from: kind) }
                                        }
                                        .disabled(isRecommendedKeep)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            if let errorMessage = state.errorMessage {
                Text(errorMessage).foregroundStyle(.red).font(.caption).padding()
            }
        }
        .task { if state.isAuthenticated, state.files.isEmpty { await viewModel.loadFiles(kind) } }
    }

    // MARK: - iCloud Drive (local sync scan — behaviorally distinct)

    private var iCloudView: some View {
        VStack(spacing: 0) {
            // Deliberately distinct styling + copy from the API-provider
            // screens above — this is a local scan of already-synced files,
            // not a live query against Apple's servers, and users need to
            // understand that difference (Phase 6's own explicit requirement).
            HStack(spacing: 8) {
                Image(systemName: "internaldrive")
                Text("Local Scan — reads files already synced to this Mac. Not a live iCloud API call (Apple provides none).")
                    .font(.caption)
            }
            .foregroundStyle(.orange)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.1))

            if viewModel.iCloudState.isLoading {
                ProgressView("Scanning…").padding()
            } else if viewModel.iCloudState.items.isEmpty {
                ContentUnavailableView(
                    "iCloud Drive",
                    systemImage: "icloud",
                    description: Text("Scan locally-synced iCloud Drive files for exact duplicates.")
                )
                Button("Scan") { Task { await viewModel.loadICloudFiles() } }
                    .padding()
            } else {
                List {
                    ForEach(viewModel.iCloudState.duplicateGroups) { group in
                        Section("\(group.items.count) copies") {
                            ForEach(group.items) { item in
                                let isRecommendedKeep = item.path == group.recommendedKeepPath
                                HStack {
                                    Text((item.path as NSString).lastPathComponent)
                                    Spacer()
                                    if isRecommendedKeep {
                                        Text("Keep").font(.caption).foregroundStyle(.green)
                                    }
                                    Text(ByteFormatter.string(fromByteCount: item.size))
                                        .foregroundStyle(.secondary)
                                    Button("Trash", role: .destructive) {
                                        Task { await viewModel.cleanICloudFiles([item]) }
                                    }
                                    .disabled(isRecommendedKeep)
                                }
                            }
                        }
                    }
                }
            }

            if let errorMessage = viewModel.iCloudState.errorMessage {
                Text(errorMessage).foregroundStyle(.red).font(.caption).padding()
            }
        }
    }
}

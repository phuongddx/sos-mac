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
            .padding(Theme.Spacing.xl)

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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .auroraBloom()
        .navigationTitle("Cloud Cleanup")
    }

    // MARK: - API providers (Google Drive / Dropbox / OneDrive)

    @ViewBuilder
    private func apiProviderView(_ kind: CloudCleanupViewModel.APIProviderKind) -> some View {
        let state = viewModel.apiStates[kind] ?? CloudAPIProviderState()

        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                Text("Connects over the real \(kind.rawValue) API — file list and delete actions happen on the server, not just locally.")
                    .font(.system(size: Theme.TextSize.xs))
                    .foregroundStyle(Theme.muted)

                providerTile(kind: kind, state: state)

                if let errorMessage = state.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(Theme.danger)
                        .font(.system(size: Theme.TextSize.xs))
                }
            }
            .padding(Theme.Spacing.xl)

            if !state.isAuthenticated {
                EmptyStateView(
                    systemImage: "link",
                    title: "Connect \(kind.rawValue)",
                    message: "Sign in to scan for duplicates and free up space.",
                    hue: Theme.hue(for: .cloudCleanup)
                )
            } else if state.isLoading {
                VStack(spacing: Theme.Spacing.md) {
                    ProgressView()
                    if let progress = state.scanProgress {
                        ScanProgressPanel(progress: progress, countOnlyLabel: { "\($0.formatted()) files listed…" })
                    } else {
                        Text("Loading…")
                            .font(.system(size: Theme.TextSize.sm))
                            .foregroundStyle(Theme.muted)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if state.duplicateGroups.isEmpty {
                EmptyStateView(
                    systemImage: "checkmark.circle",
                    title: "No duplicates found",
                    message: "\(kind.rawValue) is clean — no duplicate files were found in your account.",
                    hue: Theme.hue(for: .cloudCleanup)
                )
            } else {
                duplicatesList(state.duplicateGroups, kind: kind)
                let reclaimable = reclaimableBytes(in: state.duplicateGroups)
                if reclaimable > 0 {
                    StickyFooterView(
                        totalLabel: "Potential savings",
                        totalValue: ByteFormatter.string(fromByteCount: reclaimable)
                    ) { EmptyView() }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { if state.isAuthenticated, state.files.isEmpty { await viewModel.loadFiles(kind) } }
    }

    /// The connected/disconnected header tile — mirrors the mockup's provider
    /// card head (logo, name, status badge, primary action), minus the quota
    /// bar: `CloudAPIProviderState` has no quota-usage field to back it, and
    /// Rule "no fabricated data" means that number stays out rather than
    /// getting hardcoded.
    private func providerTile(kind: CloudCleanupViewModel.APIProviderKind, state: CloudAPIProviderState) -> some View {
        let icon = providerIcon(kind)

        return HStack(spacing: Theme.Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .fill(icon.tint)
                    .frame(width: 40, height: 40)
                Image(systemName: icon.symbol)
                    .foregroundStyle(.white)
                    .font(.system(size: 16, weight: .semibold))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(kind.rawValue)
                    .font(.system(size: Theme.TextSize.sm, weight: .semibold))
                    .foregroundStyle(Theme.foreground)
                if state.isAuthenticated {
                    BadgeView(text: "Connected", style: .safe)
                } else {
                    BadgeView(text: "Disconnected", style: .risk)
                }
            }

            Spacer()

            if state.isAuthenticated {
                Button("Refresh") { Task { await viewModel.loadFiles(kind) } }
                    .disabled(state.isLoading)
                Button("Disconnect") { Task { await viewModel.disconnect(kind) } }
                    .disabled(state.isLoading)
            } else {
                Button("Connect") { Task { await viewModel.connect(kind) } }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .disabled(state.isLoading)
            }
        }
        .careCard()
    }

    private func providerIcon(_ kind: CloudCleanupViewModel.APIProviderKind) -> (symbol: String, tint: Color) {
        switch kind {
        case .googleDrive: return ("g.circle.fill", Color(hex: "#1A9349"))
        case .dropbox: return ("d.circle.fill", Color(hex: "#0061FE"))
        case .oneDrive: return ("o.circle.fill", Color(hex: "#094AB2"))
        }
    }

    private func duplicatesList(_ groups: [CloudDuplicateGroup], kind: CloudCleanupViewModel.APIProviderKind) -> some View {
        List {
            ForEach(groups) { group in
                Section("\(group.files.count) copies") {
                    ForEach(group.files) { file in
                        let isRecommendedKeep = file.id == group.recommendedKeepID
                        HStack {
                            Text(file.name)
                            Spacer()
                            if isRecommendedKeep {
                                BadgeView(text: "Keep", style: .safe)
                            }
                            Text(ByteFormatter.string(fromByteCount: file.size))
                                .foregroundStyle(Theme.muted)
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

    /// Sum of every duplicate file's size except each group's recommended
    /// keep — real derived data from already-loaded `CloudDuplicateGroup`s,
    /// not a fabricated mockup number.
    private func reclaimableBytes(in groups: [CloudDuplicateGroup]) -> Int64 {
        groups.reduce(into: Int64(0)) { sum, group in
            for file in group.files where file.id != group.recommendedKeepID {
                sum += file.size
            }
        }
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
                ProgressView("Scanning…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.iCloudState.items.isEmpty {
                EmptyStateView(
                    systemImage: "icloud",
                    title: "iCloud Drive",
                    message: "Scan locally-synced iCloud Drive files for exact duplicates.",
                    hue: Theme.hue(for: .cloudCleanup),
                    actionTitle: "Scan"
                ) {
                    Task { await viewModel.loadICloudFiles() }
                }
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
                                        BadgeView(text: "Keep", style: .safe)
                                    }
                                    Text(ByteFormatter.string(fromByteCount: item.size))
                                        .foregroundStyle(Theme.muted)
                                    Button("Trash", role: .destructive) {
                                        Task { await viewModel.cleanICloudFiles([item]) }
                                    }
                                    .disabled(isRecommendedKeep)
                                }
                            }
                        }
                    }
                }
                if reclaimableICloudBytes > 0 {
                    StickyFooterView(
                        totalLabel: "Potential savings",
                        totalValue: ByteFormatter.string(fromByteCount: reclaimableICloudBytes)
                    ) { EmptyView() }
                }
            }

            if let errorMessage = viewModel.iCloudState.errorMessage {
                Text(errorMessage).foregroundStyle(Theme.danger).font(.caption).padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Sum of every local duplicate item's size except each group's
    /// recommended keep — same real-derived-data rule as `reclaimableBytes`.
    private var reclaimableICloudBytes: Int64 {
        viewModel.iCloudState.duplicateGroups.reduce(into: Int64(0)) { sum, group in
            for item in group.items where item.path != group.recommendedKeepPath {
                sum += item.size
            }
        }
    }
}

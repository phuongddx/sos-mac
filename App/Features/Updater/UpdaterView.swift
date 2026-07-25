import SwiftUI
import AppKit
import CleanCore

struct UpdaterView: View {
    @State private var viewModel = UpdaterViewModel()

    var body: some View {
        Group {
            if viewModel.rows.isEmpty {
                ProgressView()
            } else {
                list
            }
        }
        .navigationTitle("Updater")
        .task {
            viewModel.loadApps()
            await viewModel.checkAll()
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            // The per-app list (including App Store deep-links and "no update
            // mechanism" rows) must stay visible even when no Sparkle app has
            // a pending update — hiding it behind a full-screen "up to date"
            // state would make App Store apps and no-feed apps unreachable.
            if !viewModel.hasAnyUpdate {
                Text("No Sparkle-based updates pending")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
            List(viewModel.rows) { row in
                HStack {
                    VStack(alignment: .leading) {
                        Text(row.app.name)
                        if let installed = row.app.version {
                            Text("Installed: \(installed)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()

                    if row.isChecking {
                        ProgressView().scaleEffect(0.6)
                    } else if viewModel.isUpdateAvailable(row), let latest = row.latestVersion {
                        Label("→ \(latest)", systemImage: "arrow.up.circle.fill")
                            .foregroundStyle(.orange)
                    } else if row.app.isAppStoreDistributed {
                        Button("View in App Store") {
                            openAppStoreSearch(for: row.app.name)
                        }
                    } else if row.app.sparkleFeedURL == nil {
                        Text("No update mechanism detected").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Up to date").foregroundStyle(.secondary)
                    }
                }
            }
            refreshButton
        }
    }

    private var refreshButton: some View {
        Button("Check Again") {
            Task { await viewModel.checkAll() }
        }
        .padding()
    }

    /// No local App Store product-ID lookup exists without a network call
    /// to Apple's iTunes Search API (not built in this phase), so this opens
    /// a name-based App Store search rather than the exact product page.
    private func openAppStoreSearch(for appName: String) {
        var components = URLComponents(string: "https://apps.apple.com/search")
        components?.queryItems = [URLQueryItem(name: "term", value: appName)]
        guard let url = components?.url else { return }
        NSWorkspace.shared.open(url)
    }
}

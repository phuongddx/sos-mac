import SwiftUI
import CleanCore

/// Matches `uninstaller.html`'s app list + leftover review, adapted to the
/// real flow: `UninstallerViewModel` inspects and confirms one app at a
/// time (no bulk multi-select), and tracks neither per-app disk size nor a
/// "last used" date, so those mockup columns are omitted rather than
/// fabricated. See plans/0725-1315-apply-open-design-system/phase-04-retrofit.md.
struct UninstallerView: View {
    @State private var viewModel = UninstallerViewModel()

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
            .auroraBloom()
            .navigationTitle("Uninstaller")
            .task { viewModel.loadApps() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .browsing:
            browsingContent

        case .inspecting:
            inspectingContent

        case .removed(let appName, let reclaimedBytes):
            removedContent(appName: appName, reclaimedBytes: reclaimedBytes)
        }
    }

    // MARK: - Browsing

    private var browsingContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            browsingHeader
            if viewModel.apps.isEmpty {
                EmptyStateView(
                    systemImage: "xmark.bin",
                    title: "No applications found",
                    message: "SOS Mac couldn't find any applications in /Applications or ~/Applications.",
                    hue: Theme.hue(for: .uninstaller)
                )
            } else {
                List(viewModel.apps) { row in
                    appRow(row)
                        .listRowInsets(EdgeInsets(
                            top: Theme.Spacing.xs, leading: Theme.Spacing.xxl,
                            bottom: Theme.Spacing.xs, trailing: Theme.Spacing.xxl
                        ))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private var browsingHeader: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Uninstaller")
                        .font(.system(size: Theme.TextSize.xl, weight: .semibold))
                        .foregroundStyle(Theme.foreground)
                    Text(headerSubtitle)
                        .font(.system(size: Theme.TextSize.sm))
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                if viewModel.isInspectingAll {
                    Button("Cancel") { viewModel.cancelInspectAll() }
                        .buttonStyle(.bordered)
                } else {
                    Button("Inspect All") { viewModel.startInspectAll() }
                        .buttonStyle(.bordered)
                        .disabled(viewModel.apps.isEmpty || viewModel.inspectingBundleID != nil)
                }
            }
            if viewModel.isInspectingAll, let progress = viewModel.progressTracker.progress {
                ScanProgressPanel(progress: progress, showCurrentPath: true)
            }
        }
        .padding(Theme.Spacing.xxxl)
    }

    private var headerSubtitle: String {
        guard viewModel.totalInspectedBytes > 0 else {
            return "\(viewModel.apps.count) applications installed"
        }
        return "\(viewModel.apps.count) applications installed · \(ByteFormatter.string(fromByteCount: viewModel.totalInspectedBytes)) reclaimable if all removed"
    }

    private func appRow(_ row: UninstallerViewModel.AppRow) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            appIcon(for: row.app.name)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.app.name)
                    .font(.system(size: Theme.TextSize.sm, weight: .medium))
                    .foregroundStyle(Theme.foreground)
                if let version = row.app.version {
                    Text("Version \(version)")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                }
            }

            Spacer(minLength: Theme.Spacing.md)

            if let inspectedSize = row.inspectedSize {
                Text(ByteFormatter.string(fromByteCount: inspectedSize))
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.muted)
                    .monospacedDigit()
            }

            if row.app.isAppStoreDistributed {
                BadgeView(text: "App Store", style: .accent)
            }

            if viewModel.inspectingBundleID == row.app.bundleIdentifier {
                ProgressView().scaleEffect(0.6)
            } else {
                Button("Inspect") {
                    Task { await viewModel.inspect(row) }
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.inspectingBundleID != nil || viewModel.isInspectingAll)
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        .elevation(.raised)
    }

    private func appIcon(for name: String) -> some View {
        let hue = Theme.hue(for: .uninstaller)
        return ZStack {
            RoundedRectangle(cornerRadius: 7)
                .fill(LinearGradient(colors: [hue, hue.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 30, height: 30)
                .shadow(color: hue.opacity(0.35), radius: 5, x: 0, y: 3)
            Text(String(name.prefix(1)).uppercased())
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
        }
    }

    // MARK: - Inspecting

    private var inspectingContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Reviewing \(currentAppName)")
                .font(.system(size: Theme.TextSize.base, weight: .semibold))
                .foregroundStyle(Theme.foreground)
                .padding(.horizontal, Theme.Spacing.xxxl)
                .padding(.top, Theme.Spacing.xxxl)
                .padding(.bottom, Theme.Spacing.md)

            List(viewModel.associatedItems) { item in
                itemRow(item)
                    .listRowInsets(EdgeInsets(
                        top: Theme.Spacing.xs, leading: Theme.Spacing.xxl,
                        bottom: Theme.Spacing.xs, trailing: Theme.Spacing.xxl
                    ))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.system(size: Theme.TextSize.sm))
                    .foregroundStyle(Theme.danger)
                    .padding(.horizontal, Theme.Spacing.xxxl)
                    .padding(.bottom, Theme.Spacing.sm)
            }

            StickyFooterView(
                totalLabel: "Selected",
                totalValue: "\(viewModel.selectedPaths.count) items · \(ByteFormatter.string(fromByteCount: selectedBytes))"
            ) {
                HStack(spacing: Theme.Spacing.md) {
                    Button("Cancel") { viewModel.cancelInspection() }
                        .buttonStyle(.bordered)
                    Button("Uninstall", role: .destructive) {
                        let appName = currentAppName
                        Task { await viewModel.confirmUninstall(appName: appName) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.danger)
                    .disabled(viewModel.selectedPaths.isEmpty)
                }
            }
        }
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
                    Text(item.path)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.foreground)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let label = item.sourceLabel {
                        Text(label)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.muted)
                    }
                }
            }
            .toggleStyle(.checkbox)

            Spacer(minLength: Theme.Spacing.md)

            Text(ByteFormatter.string(fromByteCount: item.size))
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.muted)
                .monospacedDigit()
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        .elevation(.raised)
    }

    private var selectedBytes: Int64 {
        viewModel.associatedItems
            .filter { viewModel.selectedPaths.contains($0.path) }
            .reduce(0) { $0 + $1.size }
    }

    // MARK: - Removed

    private func removedContent(appName: String, reclaimedBytes: Int64) -> some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()
            SummaryCardView(
                bigNumber: ByteFormatter.string(fromByteCount: reclaimedBytes),
                caption: "\(appName) removed, along with its associated files."
            )
            .frame(maxWidth: 420)
            Button("Done") { viewModel.backToBrowsing() }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .controlSize(.large)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Spacing.xxxl)
    }

    private var currentAppName: String {
        guard case .inspecting(let bundleID) = viewModel.phase,
              let row = viewModel.apps.first(where: { $0.app.bundleIdentifier == bundleID })
        else { return "App" }
        return row.app.name
    }
}

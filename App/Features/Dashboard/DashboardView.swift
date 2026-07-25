import SwiftUI

/// Matches `index.html`'s dashboard layout: storage card, Smart Care CTA,
/// and a module grid. Deliberately omits the mockup's health ring and
/// recent-activity feed — neither has a real backing data source yet
/// (no Protection/health scoring module, no persisted cross-session
/// activity log), and every ViewModel in this app resets to `.idle` each
/// time its view is (re)created, so there is no real "last scanned" history
/// to show. See plans/0725-1315-apply-open-design-system/phase-03-dashboard.md.
struct DashboardView: View {
    let onSelect: (SidebarDestination) -> Void

    @State private var storage = VolumeStorageInfo.current()
    @State private var performanceSnapshot = PerformanceSnapshot.capture()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxxl) {
                header
                topRow
                modulesSection
            }
            .padding(Theme.Spacing.xxxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .navigationTitle("Dashboard")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Dashboard")
                .font(.system(size: Theme.TextSize.xl, weight: .semibold))
                .foregroundStyle(Theme.foreground)
            Text("Pick a module below, or run Smart Care for a guided pass across the essentials.")
                .font(.system(size: Theme.TextSize.sm))
                .foregroundStyle(Theme.muted)
        }
    }

    private var topRow: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.xl) {
            storageCard
            smartCareCard
        }
    }

    private var storageCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Storage")
                .font(.system(size: Theme.TextSize.base, weight: .semibold))
                .foregroundStyle(Theme.foreground)
            if let storage {
                Text("\(storage.usedDescription) used of \(storage.totalDescription) · \(storage.freeDescription) free")
                    .font(.system(size: Theme.TextSize.sm))
                    .foregroundStyle(Theme.muted)
                ProgressBarView(progress: storage.usedFraction)
                    .frame(height: 10)
            } else {
                Text("Storage info unavailable")
                    .font(.system(size: Theme.TextSize.sm))
                    .foregroundStyle(Theme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .careCard()
    }

    private var smartCareCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .fill(Theme.accent.opacity(0.14))
                    .frame(width: 36, height: 36)
                Image(systemName: "wand.and.stars").foregroundStyle(Theme.accent)
            }
            Text("Run Smart Care")
                .font(.system(size: Theme.TextSize.base, weight: .semibold))
                .foregroundStyle(Theme.foreground)
            Text("Clean, optimize, and review in one guided pass.")
                .font(.system(size: Theme.TextSize.sm))
                .foregroundStyle(Theme.muted)
            Button("Run Smart Care") { onSelect(.smartCare) }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .careCard()
    }

    private var modulesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("MODULES")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Theme.muted)
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 220), spacing: Theme.Spacing.xl)],
                spacing: Theme.Spacing.xl
            ) {
                ModuleCardView(
                    systemImage: "trash", title: "Junk & Cache", subtitle: "Cache & temp files",
                    stat: "Not scanned this session", badgeText: "Open", badgeStyle: .neutral
                ) { onSelect(.junkCleaner) }

                ModuleCardView(
                    systemImage: "xmark.bin", title: "Uninstaller", subtitle: "Apps & leftovers",
                    stat: "Not reviewed this session", badgeText: "Open", badgeStyle: .neutral
                ) { onSelect(.uninstaller) }

                ModuleCardView(
                    systemImage: "arrow.triangle.2.circlepath", title: "Updater", subtitle: "App updates",
                    stat: "Not checked this session", badgeText: "Open", badgeStyle: .neutral
                ) { onSelect(.updater) }

                ModuleCardView(
                    systemImage: "square.grid.3x3.fill", title: "Space Lens", subtitle: "Disk usage map",
                    stat: "Not scanned this session", badgeText: "Open", badgeStyle: .neutral
                ) { onSelect(.spaceLens) }

                ModuleCardView(
                    systemImage: "doc.on.doc", title: "Duplicate Finder", subtitle: "Exact & similar files",
                    stat: "Not scanned this session", badgeText: "Open", badgeStyle: .neutral
                ) { onSelect(.duplicateFinder) }

                ModuleCardView(
                    systemImage: "gauge.with.dots.needle.50percent", title: "Performance", subtitle: "Live system metrics",
                    stat: performanceStat, badgeText: "Live", badgeStyle: .safe
                ) { onSelect(.performance) }

                ModuleCardView(
                    systemImage: "icloud", title: "Cloud Cleanup", subtitle: "Drive · Dropbox · OneDrive · iCloud",
                    stat: "Not opened this session", badgeText: "Open", badgeStyle: .neutral
                ) { onSelect(.cloudCleanup) }

                ModuleCardView(
                    systemImage: "shield.lefthalf.filled", title: "Protection", subtitle: "Known-signature malware scan",
                    stat: "Not scanned this session", badgeText: "Open", badgeStyle: .neutral
                ) { onSelect(.protection) }
            }
        }
    }

    private var performanceStat: String {
        guard let used = performanceSnapshot.memoryUsedBytes,
              let total = performanceSnapshot.memoryTotalBytes, total > 0 else {
            return "Live metrics"
        }
        let ramPercent = Int((Double(used) / Double(total)) * 100)
        if let load = performanceSnapshot.oneMinuteLoad {
            return String(format: "Load %.1f · RAM %d%%", load, ramPercent)
        }
        return "RAM \(ramPercent)%"
    }
}

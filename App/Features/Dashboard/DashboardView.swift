import SwiftUI

/// Matches `index.html`'s dashboard layout: aurora hero (storage bar behind
/// a hairline divider, one primary CTA) + hue-coded module grid. Deliberately
/// omits the mockup's health ring and recent-activity feed — neither has a
/// real backing data source yet (no Protection/health scoring module, no
/// persisted cross-session activity log), and every ViewModel in this app
/// resets to `.idle` each time its view is (re)created, so there is no real
/// "last scanned" history to show, and no honest health score to compute.
/// See plans/0725-1315-apply-open-design-system/phase-03-dashboard.md.
struct DashboardView: View {
    let onSelect: (SidebarDestination) -> Void

    @State private var storage = VolumeStorageInfo.current()
    @State private var performanceSnapshot = PerformanceSnapshot.capture()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxxl) {
                hero
                modulesSection
            }
            .padding(Theme.Spacing.xxxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .auroraBloom()
        .navigationTitle("Dashboard")
    }

    private var hero: some View {
        HeroPanelView(
            eyebrow: "System status",
            title: "Pick a module, or run Smart Care",
            subtitle: "A guided pass across the essentials cleans, optimizes, and reviews in one go — nothing is changed until you approve it.",
            hue: Theme.hue(for: .dashboard),
            primaryActionTitle: "Run Smart Care",
            primaryAction: { onSelect(.smartCare) },
            trailing: { storageStat }
        )
    }

    @ViewBuilder
    private var storageStat: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Storage")
                .font(.system(size: Theme.TextSize.base, weight: .semibold))
                .foregroundStyle(Theme.foreground)
            if let storage {
                Text("\(storage.usedDescription) used of \(storage.totalDescription)")
                    .font(.system(size: Theme.TextSize.sm))
                    .foregroundStyle(Theme.muted)
                ProgressBarView(progress: storage.usedFraction)
                    .frame(height: 10)
                Text("\(storage.freeDescription) free")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
                    .monospacedDigit()
            } else {
                Text("Storage info unavailable")
                    .font(.system(size: Theme.TextSize.sm))
                    .foregroundStyle(Theme.muted)
            }
        }
        .frame(width: 240, alignment: .leading)
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
                    stat: "Not scanned this session", badgeText: "Open", badgeStyle: .neutral,
                    hue: Theme.hue(for: .junkCleaner)
                ) { onSelect(.junkCleaner) }

                ModuleCardView(
                    systemImage: "xmark.bin", title: "Uninstaller", subtitle: "Apps & leftovers",
                    stat: "Not reviewed this session", badgeText: "Open", badgeStyle: .neutral,
                    hue: Theme.hue(for: .uninstaller)
                ) { onSelect(.uninstaller) }

                ModuleCardView(
                    systemImage: "arrow.triangle.2.circlepath", title: "Updater", subtitle: "App updates",
                    stat: "Not checked this session", badgeText: "Open", badgeStyle: .neutral,
                    hue: Theme.hue(for: .updater)
                ) { onSelect(.updater) }

                ModuleCardView(
                    systemImage: "square.grid.3x3.fill", title: "Space Lens", subtitle: "Disk usage map",
                    stat: "Not scanned this session", badgeText: "Open", badgeStyle: .neutral,
                    hue: Theme.hue(for: .spaceLens)
                ) { onSelect(.spaceLens) }

                ModuleCardView(
                    systemImage: "doc.on.doc", title: "Duplicate Finder", subtitle: "Exact & similar files",
                    stat: "Not scanned this session", badgeText: "Open", badgeStyle: .neutral,
                    hue: Theme.hue(for: .duplicateFinder)
                ) { onSelect(.duplicateFinder) }

                ModuleCardView(
                    systemImage: "gauge.with.dots.needle.50percent", title: "Performance", subtitle: "Live system metrics",
                    stat: performanceStat, badgeText: "Live", badgeStyle: .safe,
                    hue: Theme.hue(for: .performance)
                ) { onSelect(.performance) }

                ModuleCardView(
                    systemImage: "icloud", title: "Cloud Cleanup", subtitle: "Drive · Dropbox · OneDrive · iCloud",
                    stat: "Not opened this session", badgeText: "Open", badgeStyle: .neutral,
                    hue: Theme.hue(for: .cloudCleanup)
                ) { onSelect(.cloudCleanup) }

                ModuleCardView(
                    systemImage: "shield.lefthalf.filled", title: "Protection", subtitle: "Known-signature malware scan",
                    stat: "Not scanned this session", badgeText: "Open", badgeStyle: .neutral,
                    hue: Theme.hue(for: .protection)
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

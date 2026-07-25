import SwiftUI
import ServiceManagement
import CleanCore

/// Matches `performance.html`'s layout — careCard() metric tiles, a
/// maintenance list, the menu bar widget CTA, and login items — using only
/// the real live-polled data `PerformanceViewModel` exposes. Deliberately
/// omits the mockup's Disk/Network sparkline tiles and the Processes /
/// per-app Login-Item-toggle tables: there is no disk I/O, network
/// throughput, running-process, or per-third-party-app login-item control
/// backing those in this app (SMAppService only lets us manage this app's
/// own login item, not other apps'). Purge RAM / Flush DNS now route through
/// `PrivilegedHelperClient` (Phase 8) — first use installs the helper and
/// prompts for System Settings approval, which is expected, not an error.
struct PerformanceView: View {
    @State private var viewModel = PerformanceViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxxl) {
                header
                metricsSection
                systemInfoSection
                maintenanceSection
                menuBarWidgetSection
                loginItemsSection

                if let maintenanceMessage = viewModel.maintenanceMessage {
                    Text(maintenanceMessage)
                        .font(.system(size: Theme.TextSize.sm))
                        .foregroundStyle(Theme.muted)
                }
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.system(size: Theme.TextSize.sm))
                        .foregroundStyle(Theme.danger)
                }
            }
            .padding(Theme.Spacing.xxxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .auroraBloom()
        .navigationTitle("Performance")
        .task { await viewModel.runPollingLoop() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Performance")
                .font(.system(size: Theme.TextSize.xl, weight: .semibold))
                .foregroundStyle(Theme.foreground)
            Text("Live system metrics, updated every couple of seconds.")
                .font(.system(size: Theme.TextSize.sm))
                .foregroundStyle(Theme.muted)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(Theme.muted)
    }

    // MARK: - Live metric tiles

    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            sectionLabel("Live Metrics")
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 200), spacing: Theme.Spacing.xl)],
                spacing: Theme.Spacing.xl
            ) {
                cpuCard
                memoryCard
                thermalCard
                loadCard
            }
        }
    }

    private var cpuCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("CPU")
                .font(.system(size: Theme.TextSize.sm, weight: .semibold))
                .foregroundStyle(Theme.foreground)
            if let cpu = viewModel.cpuUsagePercent {
                Text(String(format: "%.0f%%", cpu))
                    .font(.system(size: Theme.TextSize.xl, weight: .bold))
                    .foregroundStyle(Theme.foreground)
                ProgressBarView(progress: cpu / 100, style: AnyShapeStyle(Theme.accent))
            } else {
                Text("—")
                    .font(.system(size: Theme.TextSize.xl, weight: .bold))
                    .foregroundStyle(Theme.muted)
                ProgressBarView(progress: 0, style: AnyShapeStyle(Theme.accent))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .careCard()
    }

    private var memoryCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Memory")
                .font(.system(size: Theme.TextSize.sm, weight: .semibold))
                .foregroundStyle(Theme.foreground)
            if let mem = viewModel.memoryInfo, mem.totalBytes > 0 {
                let percent = Double(mem.usedBytes) / Double(mem.totalBytes)
                Text(String(format: "%.0f%%", percent * 100))
                    .font(.system(size: Theme.TextSize.xl, weight: .bold))
                    .foregroundStyle(Theme.foreground)
                ProgressBarView(progress: percent, style: AnyShapeStyle(Theme.warn))
                Text("\(ByteFormatter.string(fromByteCount: Int64(mem.usedBytes))) / \(ByteFormatter.string(fromByteCount: Int64(mem.totalBytes)))")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.muted)
            } else {
                Text("—")
                    .font(.system(size: Theme.TextSize.xl, weight: .bold))
                    .foregroundStyle(Theme.muted)
                ProgressBarView(progress: 0, style: AnyShapeStyle(Theme.warn))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .careCard()
    }

    private var thermalCard: some View {
        let badge = thermalBadge(for: viewModel.thermalState)
        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Thermal State")
                .font(.system(size: Theme.TextSize.sm, weight: .semibold))
                .foregroundStyle(Theme.foreground)
            BadgeView(text: badge.text, style: badge.style)
            Text(viewModel.thermalState.rawValue.capitalized)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .careCard()
    }

    /// Maps the real `ThermalState` cases (nominal/fair/serious/critical)
    /// onto the design system's three severity tiers — no invented middle
    /// ground beyond what the enum actually has.
    private func thermalBadge(for state: ThermalState) -> (text: String, style: BadgeStyle) {
        switch state {
        case .nominal: return ("Normal", .safe)
        case .fair: return ("Elevated", .attention)
        case .serious: return ("Serious", .risk)
        case .critical: return ("Critical", .risk)
        }
    }

    private var loadCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Load Average")
                .font(.system(size: Theme.TextSize.sm, weight: .semibold))
                .foregroundStyle(Theme.foreground)
            if let loads = viewModel.loadAverages {
                Text(String(format: "%.2f", loads.oneMinute))
                    .font(.system(size: Theme.TextSize.xl, weight: .bold))
                    .foregroundStyle(Theme.foreground)
                Text(String(format: "1m %.2f · 5m %.2f · 15m %.2f", loads.oneMinute, loads.fiveMinute, loads.fifteenMinute))
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.muted)
            } else {
                Text("—")
                    .font(.system(size: Theme.TextSize.xl, weight: .bold))
                    .foregroundStyle(Theme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .careCard()
    }

    // MARK: - System info (swap / architecture / uptime)

    private var systemInfoSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            sectionLabel("System")
            systemInfoCard
        }
    }

    private var systemInfoRows: [(label: String, value: String)] {
        var rows: [(label: String, value: String)] = []
        if let swap = viewModel.swapUsage {
            rows.append((
                "Swap",
                "\(ByteFormatter.string(fromByteCount: Int64(swap.usedBytes))) / \(ByteFormatter.string(fromByteCount: Int64(swap.totalBytes)))"
            ))
        }
        rows.append(("Architecture", viewModel.isAppleSilicon ? "Apple Silicon" : "Intel"))
        if let bootTime = viewModel.bootTime {
            rows.append(("Uptime Since", bootTime.formatted(date: .abbreviated, time: .shortened)))
        }
        return rows
    }

    private var systemInfoCard: some View {
        let rows = systemInfoRows
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                metricRow(row.label, value: row.value)
                    .padding(.vertical, Theme.Spacing.sm)
                if index < rows.count - 1 {
                    Divider()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .careCard()
    }

    private func metricRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: Theme.TextSize.sm))
                .foregroundStyle(Theme.foreground)
            Spacer()
            Text(value)
                .font(.system(size: Theme.TextSize.sm))
                .foregroundStyle(Theme.muted)
        }
    }

    // MARK: - Maintenance

    private var maintenanceSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            sectionLabel("Maintenance")
            maintenanceCard
        }
    }

    private var maintenanceCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            maintenanceRow(
                icon: "memorychip",
                title: "Free up RAM",
                description: "Clears inactive memory held by idle apps and background caches.",
                tooltip: "Runs the root-only `purge` command via the privileged helper.",
                action: { await viewModel.freeUpRAM() }
            )
            Divider()
            maintenanceRow(
                icon: "network",
                title: "Flush DNS Cache",
                description: "Resolves slow or broken site loads caused by stale DNS records.",
                tooltip: "Runs `dscacheutil -flushcache` via the privileged helper.",
                action: { await viewModel.flushDNSCache() }
            )
        }
        .careCard()
    }

    private func maintenanceRow(
        icon: String,
        title: String,
        description: String,
        tooltip: String,
        action: @escaping () async -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .fill(Theme.accent.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .foregroundStyle(Theme.accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: Theme.TextSize.sm, weight: .semibold))
                    .foregroundStyle(Theme.foreground)
                Text(description)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
            Button("Run") { Task { await action() } }
                .buttonStyle(.bordered)
        }
        .padding(.vertical, Theme.Spacing.md)
        .help(tooltip)
    }

    // MARK: - Menu bar widget

    private var menuBarWidgetSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            sectionLabel("Menu Bar Widget")
            menuBarWidgetCard
        }
    }

    private var menuBarWidgetCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Live CPU/RAM readout in the menu bar")
                .font(.system(size: Theme.TextSize.sm, weight: .semibold))
                .foregroundStyle(Theme.foreground)
            Text("Auto-launch at login isn't wired yet — open manually for now.")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.muted)
            Button("Open Menu Bar Widget") { viewModel.openMenuBarWidget() }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .careCard()
    }

    // MARK: - Login items

    private var loginItemsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            sectionLabel("Login Items")
            loginItemsCard
        }
    }

    private var loginItemsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Toggle("Launch SOS Mac at Login", isOn: Binding(
                get: { viewModel.launchAtLoginStatus == .enabled },
                set: { _ in viewModel.toggleLaunchAtLogin() }
            ))
            .toggleStyle(.switch)

            if !viewModel.loginItems.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Installed Launch Agents")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                    ForEach(viewModel.loginItems) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.label)
                                .font(.system(size: Theme.TextSize.sm))
                                .foregroundStyle(Theme.foreground)
                            Text(item.path)
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.muted)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .careCard()
    }
}

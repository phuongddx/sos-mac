import SwiftUI
import ServiceManagement
import CleanCore

struct PerformanceView: View {
    @State private var viewModel = PerformanceViewModel()

    var body: some View {
        List {
            Section("Live Metrics") {
                metricRow("CPU", value: viewModel.cpuUsagePercent.map { String(format: "%.0f%%", $0) } ?? "—")
                if let mem = viewModel.memoryInfo {
                    metricRow("Memory", value: "\(ByteFormatter.string(fromByteCount: Int64(mem.usedBytes))) / \(ByteFormatter.string(fromByteCount: Int64(mem.totalBytes)))")
                }
                if let swap = viewModel.swapUsage {
                    metricRow("Swap", value: "\(ByteFormatter.string(fromByteCount: Int64(swap.usedBytes))) / \(ByteFormatter.string(fromByteCount: Int64(swap.totalBytes)))")
                }
                metricRow("Thermal State", value: viewModel.thermalState.rawValue.capitalized)
                if let loads = viewModel.loadAverages {
                    metricRow("Load Avg (1/5/15m)", value: String(format: "%.2f / %.2f / %.2f", loads.oneMinute, loads.fiveMinute, loads.fifteenMinute))
                }
                if let bootTime = viewModel.bootTime {
                    metricRow("Uptime Since", value: bootTime.formatted(date: .abbreviated, time: .shortened))
                }
                metricRow("Architecture", value: viewModel.isAppleSilicon ? "Apple Silicon" : "Intel")
            }

            Section("Maintenance") {
                maintenanceRow(
                    title: "Purge RAM",
                    tooltip: "Requires the privileged helper (not yet available) to run the root-only `purge` command."
                )
                maintenanceRow(
                    title: "Flush DNS Cache",
                    tooltip: "Requires the privileged helper (not yet available) to run `dscacheutil -flushcache`."
                )
            }

            Section("Menu Bar Widget") {
                HStack {
                    Text("Live CPU/RAM readout in the menu bar")
                    Spacer()
                    Button("Open") { viewModel.openMenuBarWidget() }
                }
                Text("Auto-launch at login isn't wired yet — open manually for now.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Login Items") {
                Toggle("Launch SOS Mac at Login", isOn: Binding(
                    get: { viewModel.launchAtLoginStatus == .enabled },
                    set: { _ in viewModel.toggleLaunchAtLogin() }
                ))
                ForEach(viewModel.loginItems) { item in
                    Text(item.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
        }
        .navigationTitle("Performance")
        .task { await viewModel.runPollingLoop() }
    }

    private func metricRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }

    private func maintenanceRow(title: String, tooltip: String) -> some View {
        HStack {
            Button(title) {
                // Unreachable: the button is always disabled until Phase 8's
                // privileged helper exists to actually run these root-only
                // commands. No handler here — don't fake success.
            }
            .disabled(true)
            Spacer()
            Image(systemName: "lock.fill").foregroundStyle(.secondary)
        }
        .help(tooltip)
    }
}

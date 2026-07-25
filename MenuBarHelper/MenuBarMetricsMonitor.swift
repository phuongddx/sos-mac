import Foundation
import Observation
import CleanCore

/// Runs standalone, reading `CleanCore`'s metrics engine directly — no IPC
/// with the main app needed, since this process links the same package.
@MainActor
@Observable
final class MenuBarMetricsMonitor {
    private static let pollInterval: Duration = .seconds(2)

    private(set) var cpuPercent: Double?
    private(set) var memoryUsedBytes: UInt64?
    private(set) var memoryTotalBytes: UInt64?

    private var previousTicks: CPUTicks?
    private var pollingTask: Task<Void, Never>?

    var labelText: String {
        cpuPercent.map { String(format: "CPU %.0f%%", $0) } ?? "SOS Mac"
    }

    init() {
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.sampleOnce()
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
    }

    private func sampleOnce() {
        if let current = MachHostStats.cpuTicks() {
            if let previous = previousTicks {
                cpuPercent = MachHostStats.cpuUsagePercent(from: previous, to: current)
            }
            previousTicks = current
        }

        if let memory = MachHostStats.memoryInfo() {
            memoryUsedBytes = memory.usedBytes
            memoryTotalBytes = memory.totalBytes
        }
    }
}

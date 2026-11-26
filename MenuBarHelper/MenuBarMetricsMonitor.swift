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
    /// Memory genuinely in use (`inUseBytes`: wired + active + compressed), not the legacy
    /// `usedBytes` percentage, which reads ~99% on an idle Mac (spec OD-11, plan E1).
    private(set) var memoryInUseBytes: UInt64?
    private(set) var memoryTotalBytes: UInt64?

    private var previousTicks: CPUTicks?
    private var pollingTask: Task<Void, Never>?

    /// Sample text; the label view holds a fixed frame (hidden "CPU 100%") so the menu
    /// bar item does not reflow between samples. Padding keeps the numeral field
    /// visually aligned until the first sample replaces "SOS Mac".
    var labelText: String {
        cpuPercent.map { String(format: "CPU %3.0f%%", $0) } ?? "SOS Mac"
    }

    var memoryFraction: Double? {
        guard let used = memoryInUseBytes, let total = memoryTotalBytes, total > 0 else { return nil }
        return Double(used) / Double(total)
    }

    var memoryPercentText: String? {
        memoryFraction.map { String(format: "%.0f%%", $0 * 100) }
    }

    var memoryDetailText: String? {
        guard let used = memoryInUseBytes, let total = memoryTotalBytes else { return nil }
        return "\(ByteFormatter.string(fromByteCount: Int64(used))) of \(ByteFormatter.string(fromByteCount: Int64(total)))"
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
            memoryInUseBytes = memory.inUseBytes
            memoryTotalBytes = memory.totalBytes
        }
    }
}

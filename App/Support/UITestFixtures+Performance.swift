#if DEBUG
import Foundation
import CleanCore

/// Fictional Performance sample data (PR 12), built on `UITestFixtures.metrics`. Nothing is
/// read from the machine: CPU 23 %, swap 1.25 of 2.15 GB, load 2.41 / 2.88 / 3.02, thermal
/// nominal, boot time 2026-11-24 09:14 — all the fixture's made-up values. The memory
/// segments are the prototype's idealised set (they sum exactly to the 16 GB total), so the
/// bar/legend agree; the "segments don't sum exactly" normalisation is covered by
/// `PerformanceViewModelTests` on constructed segments instead.
extension UITestFixtures {
    static func performanceSample() -> PerformanceViewModel.Sample {
        let fixture = metrics
        return PerformanceViewModel.Sample(
            cpuUsagePercent: Double(fixture.cpuPercent),
            memory: PerformanceViewModel.MemorySegments(
                wired: UInt64(fixture.wired),
                active: UInt64(fixture.active),
                compressed: UInt64(fixture.compressed),
                inactive: UInt64(fixture.inactive),
                free: UInt64(fixture.free),
                total: 16_000_000_000,
                // The engine's OD-11 figure for these made-up segments (2.84 + 5.61 +
                // 2.79 GB = 11.24 GB of the 16 GB total) — the fixture states its own
                // values, it re-derives nothing.
                inUseBytes: 11_240_000_000),
            swap: PerformanceViewModel.SwapUsagePair(used: UInt64(fixture.swapUsed),
                                                     total: UInt64(fixture.swapTotal)),
            thermal: .nominal,
            load: PerformanceViewModel.LoadAverages(
                oneMinute: fixture.loadAverage[0],
                fiveMinute: fixture.loadAverage[1],
                fifteenMinute: fixture.loadAverage[2]),
            // 2026-11-24 09:14:00 UTC as a fixed instant (a shared DateFormatter is not
            // concurrency-safe; a fixed epoch needs no formatter at all).
            bootTime: Date(timeIntervalSince1970: 1_795_511_640),
            isAppleSilicon: true)
    }

    /// The unavailable-state sample — what the real seams return when the engine's memory
    /// read fails: a **non-nil partial sample** (no memory, and no CPU percentage — the
    /// first tick after a baseline reset) with the remaining reads present. The screen's
    /// own gating must handle this; a `nil` sample here would mask it.
    static func performanceUnavailableSample() -> PerformanceViewModel.Sample {
        var sample = performanceSample()
        sample.cpuUsagePercent = nil
        sample.memory = nil
        return sample
    }

    /// The fixture launch agents, filed under the fictional home — a label and a path, like
    /// `LoginItemsManager.listInstalledAgents()` returns; no date column exists in the model.
    static func performanceLoginItems() -> [LoginItemEntry] {
        metrics.loginAgents.map { agent in
            LoginItemEntry(label: agent, path: "\(home)/Library/LaunchAgents/\(agent)")
        }
    }
}
#endif

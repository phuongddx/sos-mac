#if DEBUG
import Foundation
import CleanCore

extension DashboardSnapshot {
    /// Made-up readings for UITest fixture runs (`SOSMAC_UITEST_FIXTURES=1`), so snapshots never
    /// show this Mac's load, memory or thermal state. Built from `UITestFixtures.metrics`:
    /// memory in use is wired + active + compressed (the same definition as `inUseBytes`),
    /// against all five buckets as the total.
    static var fixture: DashboardSnapshot {
        let m = UITestFixtures.metrics
        let inUse = m.wired + m.active + m.compressed
        let total = inUse + m.inactive + m.free
        return DashboardSnapshot(
            oneMinuteLoad: m.loadAverage.first,
            memory: Memory(inUseBytes: UInt64(inUse), totalBytes: UInt64(total)),
            thermalState: ThermalState(rawValue: m.thermal.lowercased()))
    }
}
#endif

import Darwin

/// Raw cumulative-since-boot tick counts from `host_statistics64`. These are
/// NOT a "current" percentage on their own — a live reading requires two
/// samples a short interval apart and a diff (see `cpuUsagePercent`), the
/// same technique Activity Monitor and `top` use.
public struct CPUTicks: Sendable {
    public let user: UInt32
    public let system: UInt32
    public let idle: UInt32
    public let nice: UInt32

    public var total: UInt64 {
        UInt64(user) + UInt64(system) + UInt64(idle) + UInt64(nice)
    }
}

public struct MemoryInfo: Sendable {
    public let freeBytes: UInt64
    public let activeBytes: UInt64
    public let inactiveBytes: UInt64
    public let wiredBytes: UInt64
    public let compressedBytes: UInt64
    public let totalBytes: UInt64

    public var usedBytes: UInt64 {
        totalBytes > freeBytes ? totalBytes - freeBytes : 0
    }
}

public enum MachHostStats {
    public static func cpuTicks() -> CPUTicks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &info) { infoPtr -> kern_return_t in
            infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(mach_host_self(), HOST_CPU_LOAD_INFO, intPtr, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        // cpu_ticks is CPU_STATE_MAX (4) natural_t entries in the fixed
        // kernel order [USER, SYSTEM, IDLE, NICE] — imported as a tuple
        // since it's a fixed-size C array.
        return CPUTicks(
            user: info.cpu_ticks.0,
            system: info.cpu_ticks.1,
            idle: info.cpu_ticks.2,
            nice: info.cpu_ticks.3
        )
    }

    /// Percentage of non-idle time between two samples. Callers sample
    /// `cpuTicks()` twice, roughly a polling interval apart, and diff.
    public static func cpuUsagePercent(from previous: CPUTicks, to current: CPUTicks) -> Double? {
        let totalDelta = Double(current.total) - Double(previous.total)
        guard totalDelta > 0 else { return nil }
        let idleDelta = Double(current.idle) - Double(previous.idle)
        return max(0, min(100, (1 - idleDelta / totalDelta) * 100))
    }

    public static func memoryInfo() -> MemoryInfo? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &stats) { statsPtr -> kern_return_t in
            statsPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPtr, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        var pageSize: vm_size_t = 0
        guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS else { return nil }
        let pageSizeBytes = UInt64(pageSize)

        let free = UInt64(stats.free_count) * pageSizeBytes
        let active = UInt64(stats.active_count) * pageSizeBytes
        let inactive = UInt64(stats.inactive_count) * pageSizeBytes
        let wired = UInt64(stats.wire_count) * pageSizeBytes
        let compressed = UInt64(stats.compressor_page_count) * pageSizeBytes
        let total = SysctlReader.physicalMemoryBytes() ?? (free + active + inactive + wired)

        return MemoryInfo(
            freeBytes: free,
            activeBytes: active,
            inactiveBytes: inactive,
            wiredBytes: wired,
            compressedBytes: compressed,
            totalBytes: total
        )
    }
}

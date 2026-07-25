import Darwin
import Foundation

/// Centralizes every `sysctlbyname` call behind one typed wrapper instead of
/// scattering raw calls (and their raw-memory-layout risk) across call sites.
public enum SysctlReader {
    /// Reads a fixed-size POD value (Int32, UInt64, or a C struct with a
    /// stable layout like `struct timeval`). The size check against
    /// `MemoryLayout<T>.size` is the safety net: if `T`'s layout doesn't
    /// match what the kernel actually returned, this fails closed (`nil`)
    /// instead of reinterpreting garbage bytes as a value.
    public static func read<T>(_ name: String) -> T? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size == MemoryLayout<T>.size else {
            return nil
        }

        let buffer = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: MemoryLayout<T>.alignment)
        defer { buffer.deallocate() }

        guard sysctlbyname(name, buffer, &size, nil, 0) == 0 else { return nil }
        return buffer.load(as: T.self)
    }

    public static func readString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }

        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        let nullTerminatorIndex = buffer.firstIndex(of: 0) ?? buffer.count
        return String(decoding: buffer[..<nullTerminatorIndex].map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    public static func isAppleSilicon() -> Bool {
        (read("hw.optional.arm64") as Int32?) == 1
    }

    public static func physicalMemoryBytes() -> UInt64? {
        read("hw.memsize")
    }

    public static func cpuCoreCount() -> Int? {
        (read("hw.ncpu") as Int32?).map(Int.init)
    }

    public struct SwapUsage: Sendable {
        public let totalBytes: UInt64
        public let usedBytes: UInt64
        public let freeBytes: UInt64
    }

    public static func swapUsage() -> SwapUsage? {
        // Darwin's own `xsw_usage` type (from <sys/sysctl.h>), not a
        // hand-rolled mirror — see the comment in `bootTime()` for why a
        // Swift-layout mirror struct isn't safe to reinterpret raw kernel
        // bytes as.
        guard let raw: xsw_usage = read("vm.swapusage") else { return nil }
        return SwapUsage(totalBytes: raw.xsu_total, usedBytes: raw.xsu_used, freeBytes: raw.xsu_avail)
    }

    public static func bootTime() -> Date? {
        // Uses Darwin's actual `timeval` type rather than a hand-rolled
        // mirror struct: Swift's default struct layout doesn't guarantee
        // C-compatible padding, and a hand-rolled `{ Int64; Int32 }` mirror
        // came out to 12 bytes here instead of C's 16 — silently failing the
        // read via the size-mismatch guard in `read<T>`, not crashing, but
        // still wrong. The real `timeval` type is guaranteed to match what
        // the kernel returns.
        guard let raw: timeval = read("kern.boottime") else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(raw.tv_sec))
    }

    public static func loadAverages() -> (oneMinute: Double, fiveMinute: Double, fifteenMinute: Double)? {
        var loads = [Double](repeating: 0, count: 3)
        guard getloadavg(&loads, 3) == 3 else { return nil }
        return (loads[0], loads[1], loads[2])
    }
}

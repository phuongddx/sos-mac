import Foundation
import CleanCore

/// Real boot-volume storage stats for the sidebar footer and Dashboard
/// storage card. Not part of CleanCore since it's a single `FileManager`
/// read, not a scanning/cleaning engine concern.
struct VolumeStorageInfo {
    /// The boot volume's display name (e.g. "Macintosh HD"), or `nil` when the
    /// system does not report one. Callers omit the name rather than guess it.
    let volumeName: String?
    let usedBytes: Int64
    let totalBytes: Int64
    let freeBytes: Int64

    var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes)
    }

    var usedDescription: String { ByteFormatter.string(fromByteCount: usedBytes) }
    var totalDescription: String { ByteFormatter.string(fromByteCount: totalBytes) }
    var freeDescription: String { ByteFormatter.string(fromByteCount: freeBytes) }

    /// Sizes come from the file system holding `path` (the home folder by default,
    /// i.e. the data volume, as before); the name comes from the boot volume `/`,
    /// whose name is the one Finder shows ("Macintosh HD" rather than "… - Data").
    static func current(
        path: String = NSHomeDirectory(),
        bootVolume: URL = URL(fileURLWithPath: "/", isDirectory: true)
    ) -> VolumeStorageInfo? {
        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: path),
              let total = attrs[.systemSize] as? NSNumber,
              let free = attrs[.systemFreeSize] as? NSNumber else {
            return nil
        }
        let totalBytes = total.int64Value
        let freeBytes = free.int64Value
        return VolumeStorageInfo(
            volumeName: volumeName(of: bootVolume),
            usedBytes: totalBytes - freeBytes,
            totalBytes: totalBytes,
            freeBytes: freeBytes
        )
    }

    /// `URLResourceKey.volumeNameKey`; `nil` (never a made-up default) when it is
    /// missing or blank.
    static func volumeName(of url: URL) -> String? {
        guard let name = try? url.resourceValues(forKeys: [.volumeNameKey]).volumeName,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return name
    }
}

#if DEBUG
extension VolumeStorageInfo {
    /// Made-up numbers for UITest fixture runs (`SOSMAC_UITEST_FIXTURES=1`), so
    /// snapshots never show the real disk. From `UITestFixtures.metrics`.
    static var fixture: VolumeStorageInfo {
        let m = UITestFixtures.metrics
        return VolumeStorageInfo(
            volumeName: m.volumeName,
            usedBytes: m.usedBytes,
            totalBytes: m.totalBytes,
            freeBytes: m.totalBytes - m.usedBytes
        )
    }
}
#endif

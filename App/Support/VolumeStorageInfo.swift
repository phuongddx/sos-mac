import Foundation
import CleanCore

/// Real boot-volume storage stats for the sidebar footer and Dashboard
/// storage card. Not part of CleanCore since it's a single `FileManager`
/// read, not a scanning/cleaning engine concern.
struct VolumeStorageInfo {
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

    static func current(path: String = NSHomeDirectory()) -> VolumeStorageInfo? {
        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: path),
              let total = attrs[.systemSize] as? NSNumber,
              let free = attrs[.systemFreeSize] as? NSNumber else {
            return nil
        }
        let totalBytes = total.int64Value
        let freeBytes = free.int64Value
        return VolumeStorageInfo(usedBytes: totalBytes - freeBytes, totalBytes: totalBytes, freeBytes: freeBytes)
    }
}

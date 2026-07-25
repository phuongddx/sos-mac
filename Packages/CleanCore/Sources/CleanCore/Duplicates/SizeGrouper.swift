import Foundation

/// First pass of duplicate detection: bucket files by exact byte size, which
/// is nearly free compared to hashing, and discard any bucket with only one
/// file — a unique size can never have a duplicate, so there's no reason to
/// ever hash it.
public struct SizeGrouper: Sendable {
    public init() {}

    public func group(rootPath: String) async -> [Int64: [ScanItem]] {
        var buckets: [Int64: [ScanItem]] = [:]
        // Zero-byte files (`.gitkeep`, empty logs/placeholders) all hash
        // identically and would otherwise form one giant "duplicate group"
        // that isn't what a user means by duplicates — every real
        // duplicate-finder tool excludes empty files from this comparison.
        for await item in FTSWrapper.walk(root: rootPath) where item.kind == .file && item.size > 0 {
            buckets[item.size, default: []].append(item)
        }
        return buckets.filter { $0.value.count >= 2 }
    }
}

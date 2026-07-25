import Foundation

public struct DuplicateGroup: Sendable, Identifiable {
    public let id: String
    public let items: [ScanItem]

    public init(id: String, items: [ScanItem]) {
        self.id = id
        self.items = items
    }

    /// "Keep newest by modification date" — deliberately `lastModified`
    /// (st_mtime), not `lastAccessed` (st_atime): merely viewing a duplicate
    /// in Preview/QuickLook bumps its atime without it being any more
    /// "recent" than its siblings.
    public var recommendedKeepPath: String? {
        items.max { lhs, rhs in
            (lhs.lastModified ?? .distantPast) < (rhs.lastModified ?? .distantPast)
        }?.path
    }
}

/// A scan pass's groups plus how many candidate files were skipped (unreadable,
/// deleted mid-scan, undecodable image) — surfaced so an incomplete-looking
/// result isn't silently presented as exhaustive.
public struct DuplicateScanResult: Sendable {
    public let groups: [DuplicateGroup]
    public let skippedCount: Int
}

/// Composes `SizeGrouper` + `StreamingHasher` into exact-duplicate groups
/// (a `Scanner`), and separately offers `PerceptualHasher`-based "similar
/// images" as an opt-in second mode — never blended into the same result,
/// since perceptual matches are approximate by nature and must stay clearly
/// labeled "similar" rather than "identical."
public struct DuplicateFinder: Scanner {
    private static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "tiff", "bmp", "gif", "webp"
    ]

    public let rootPath: String

    public init(rootPath: String) {
        self.rootPath = rootPath
    }

    public func scan() async throws -> [ScanItem] {
        try await findExactDuplicateGroups().groups.flatMap(\.items)
    }

    public func findExactDuplicateGroups() async throws -> DuplicateScanResult {
        let sizeBuckets = await SizeGrouper().group(rootPath: rootPath)
        var hashGroups: [String: [ScanItem]] = [:]
        var skippedCount = 0

        for (_, items) in sizeBuckets {
            for item in items {
                // Hashing thousands of same-size files can take real time;
                // without this, cancelling a scan only stops before/after
                // this whole function, not the expensive work inside it.
                try Task.checkCancellation()

                do {
                    let hash = try StreamingHasher.sha256(ofFileAtPath: item.path)
                    hashGroups[hash, default: []].append(item)
                } catch {
                    // Unreadable (permission denied, deleted mid-scan, I/O
                    // error) — drop the item, never guess/merge it into a
                    // bucket by exact size alone, but don't hide that it
                    // happened either.
                    skippedCount += 1
                }
            }
        }

        let groups = hashGroups
            .filter { $0.value.count >= 2 }
            .map { DuplicateGroup(id: $0.key, items: $0.value) }
        return DuplicateScanResult(groups: groups, skippedCount: skippedCount)
    }

    public func findSimilarImageGroups(hammingThreshold: Int = 10) async throws -> DuplicateScanResult {
        var imageItems: [ScanItem] = []
        for await item in FTSWrapper.walk(root: rootPath) where item.kind == .file {
            try Task.checkCancellation()
            let ext = (item.path as NSString).pathExtension.lowercased()
            if Self.imageExtensions.contains(ext) {
                imageItems.append(item)
            }
        }

        var hashed: [(item: ScanItem, hash: UInt64)] = []
        var skippedCount = 0
        for item in imageItems {
            try Task.checkCancellation()
            if let hash = PerceptualHasher.dHash(imageAtPath: item.path) {
                hashed.append((item, hash))
            } else {
                skippedCount += 1
            }
        }

        try Task.checkCancellation()
        let clusters = PerceptualHasher.cluster(hashes: hashed.map(\.hash), threshold: hammingThreshold)
        let groups = clusters.map { indices in
            DuplicateGroup(
                id: "similar-\(hashed[indices[0]].item.path)",
                items: indices.map { hashed[$0].item }
            )
        }

        return DuplicateScanResult(groups: groups, skippedCount: skippedCount)
    }
}

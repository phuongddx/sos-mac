import Foundation

public struct CloudDuplicateGroup: Sendable, Identifiable {
    public let id: String
    public let files: [CloudFileMetadata]

    public init(id: String, files: [CloudFileMetadata]) {
        self.id = id
        self.files = files
    }

    /// "Keep newest by modification date" — mirrors `DuplicateGroup
    /// .recommendedKeepPath` (Phase 3) exactly, so the UI can protect the
    /// same file the local duplicate finder would protect, instead of
    /// letting every copy in a cloud duplicate group be deleted with no
    /// safety net.
    public var recommendedKeepID: String? {
        files.max { lhs, rhs in
            (lhs.modifiedDate ?? .distantPast) < (rhs.modifiedDate ?? .distantPast)
        }?.id
    }
}

/// Reuses Phase 3's two-pass grouping concept (size first, then hash) but
/// matches on API-provided metadata instead of downloading files to hash
/// locally — bandwidth matters here in a way it doesn't for local scans, so
/// a cloud file's content is never fetched just to compare it.
public enum CloudDuplicateGrouper {
    public static func findDuplicates(among files: [CloudFileMetadata]) -> [CloudDuplicateGroup] {
        let sizeBuckets = Dictionary(grouping: files.filter { !$0.isFolder }, by: \.size)
            .filter { $0.value.count >= 2 && $0.key > 0 } // zero-byte files aren't meaningful duplicates

        var groups: [CloudDuplicateGroup] = []
        for (_, sameSizeFiles) in sizeBuckets {
            // A provider-supplied hash is required to go further — without
            // one, matching size alone isn't proof of duplication the way
            // it is once local SHA-256 hashing confirms it in Phase 3.
            let hashGroups = Dictionary(
                grouping: sameSizeFiles.filter { $0.contentHash != nil },
                by: { $0.contentHash! }
            ).filter { $0.value.count >= 2 }

            for (hash, matchingFiles) in hashGroups {
                groups.append(CloudDuplicateGroup(id: hash, files: matchingFiles))
            }
        }

        return groups
    }
}

import Foundation

public enum ScanItemKind: String, Sendable, Codable {
    case file
    case directory
    case symlink
}

public struct ScanItem: Sendable, Codable, Identifiable, Hashable {
    public let id: String
    public let path: String
    public let size: Int64
    public let kind: ScanItemKind
    public let lastAccessed: Date?
    /// st_mtime — when the file's *content* last changed, distinct from
    /// lastAccessed (st_atime, which a mere read/view bumps). Duplicate
    /// Finder's "keep newest" heuristic needs this one specifically: using
    /// atime there would make a duplicate you just viewed in Preview look
    /// "newest" regardless of which copy is actually more recent.
    public let lastModified: Date?
    public let severity: Severity
    /// Human-readable origin (e.g. a JunkRule's label) so the UI can show
    /// *why* something is flaggable instead of a bare path.
    public let sourceLabel: String?
    /// True when deleting this item needs the Phase 8 privileged helper
    /// (root-owned paths) — lets the UI disable selection until that lands.
    public let requiresPrivilegedHelper: Bool

    public init(
        path: String,
        size: Int64,
        kind: ScanItemKind,
        lastAccessed: Date? = nil,
        lastModified: Date? = nil,
        severity: Severity = .safe,
        sourceLabel: String? = nil,
        requiresPrivilegedHelper: Bool = false
    ) {
        self.id = path
        self.path = path
        self.size = size
        self.kind = kind
        self.lastAccessed = lastAccessed
        self.lastModified = lastModified
        self.severity = severity
        self.sourceLabel = sourceLabel
        self.requiresPrivilegedHelper = requiresPrivilegedHelper
    }
}

public struct CleanResult: Sendable, Codable {
    public let succeeded: [ScanItem]
    public let failed: [FailedItem]

    public struct FailedItem: Sendable, Codable, Hashable {
        public let item: ScanItem
        public let reason: String

        public init(item: ScanItem, reason: String) {
            self.item = item
            self.reason = reason
        }
    }

    public var reclaimedBytes: Int64 {
        succeeded.reduce(0) { $0 + $1.size }
    }

    public init(succeeded: [ScanItem], failed: [FailedItem]) {
        self.succeeded = succeeded
        self.failed = failed
    }
}

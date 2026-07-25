import Foundation

/// A snapshot of a scan's progress, reported by whichever engine type is
/// currently walking/enumerating. `totalItems` is `nil` whenever a total
/// isn't knowable ahead of the walk (e.g. an arbitrary user-chosen directory)
/// — callers must never fabricate one; a `nil` total means "show a running
/// count, not a percentage."
public struct ScanProgress: Sendable {
    public let itemsProcessed: Int
    public let totalItems: Int?
    public let currentPath: String?

    public init(itemsProcessed: Int, totalItems: Int? = nil, currentPath: String? = nil) {
        self.itemsProcessed = itemsProcessed
        self.totalItems = totalItems
        self.currentPath = currentPath
    }
}

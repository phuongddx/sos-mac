import SwiftData
import Foundation

/// A user's explicit "don't flag this again" choice, keyed by path so it
/// survives across scans regardless of which scanner produced the item.
@Model
final class IgnoredItem {
    @Attribute(.unique) var path: String
    var addedAt: Date

    init(path: String, addedAt: Date = Date()) {
        self.path = path
        self.addedAt = addedAt
    }
}

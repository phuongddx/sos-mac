import SwiftData
import Foundation

/// Persisted mapping for a quarantined file so it can be restored to its
/// exact original path after an app relaunch — `QuarantineManager` (CleanCore)
/// does the actual file move but holds no persistence of its own, same
/// "engine layer stays UI/persistence-free" boundary `IgnoredItem` already
/// established for JunkCleaner's ignore list.
@Model
final class QuarantineRecord {
    @Attribute(.unique) var quarantinePath: String
    var originalPath: String
    var threatIdentifier: String
    var quarantinedAt: Date

    init(originalPath: String, quarantinePath: String, threatIdentifier: String, quarantinedAt: Date = Date()) {
        self.originalPath = originalPath
        self.quarantinePath = quarantinePath
        self.threatIdentifier = threatIdentifier
        self.quarantinedAt = quarantinedAt
    }
}

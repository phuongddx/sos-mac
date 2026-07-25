import Foundation

/// Finds every file/folder associated with an app's bundle identifier across
/// the standard Library subpaths, so an uninstall can show the user the full
/// list before deleting anything.
public struct BundleAssociatedFilesFinder: Sendable {
    private static let librarySubpaths = [
        "Library/Caches",
        "Library/Preferences",
        "Library/Application Support",
        "Library/Saved Application State",
        "Library/Containers",
        "Library/LaunchAgents"
    ]

    public init() {}

    public func associatedFiles(
        forBundleIdentifier bundleID: String,
        homeOverride: String? = nil
    ) -> [ScanItem] {
        let fileManager = FileManager.default
        let home = homeOverride ?? NSHomeDirectory()
        var results: [ScanItem] = []

        for subpath in Self.librarySubpaths {
            let root = (home as NSString).appendingPathComponent(subpath)
            guard let entries = try? fileManager.contentsOfDirectory(atPath: root) else { continue }

            for entry in entries where Self.matches(entry: entry, bundleID: bundleID) {
                let fullPath = (root as NSString).appendingPathComponent(entry)
                guard let attrs = try? fileManager.attributesOfItem(atPath: fullPath) else { continue }
                let size = (attrs[.size] as? Int64) ?? 0
                let isDirectory = (attrs[.type] as? FileAttributeType) == .typeDirectory
                results.append(
                    ScanItem(
                        path: fullPath,
                        size: size,
                        kind: isDirectory ? .directory : .file,
                        severity: .safe,
                        sourceLabel: "Associated with \(bundleID)"
                    )
                )
            }
        }

        return results
    }

    /// Exact match, or `<bundleID>` followed by a separator (".plist",
    /// ".savedState", a numbered container, etc.) — never a bare substring
    /// match, which would let "com.foo.app" wrongly match "com.foo.app2"'s
    /// files and delete another app's data. An empty bundleID (a malformed
    /// or corrupted Info.plist) must never reach the prefix check below —
    /// `"".hasPrefix(".")`-style logic would otherwise match every
    /// dotfile/dot-folder across five Library subpaths, turning one broken
    /// app's uninstall into a system-wide wildcard delete.
    static func matches(entry: String, bundleID: String) -> Bool {
        guard !bundleID.isEmpty else { return false }
        return entry == bundleID || entry.hasPrefix(bundleID + ".")
    }
}

import Foundation

/// Reads iCloud Drive's locally-synced files under `~/Library/Mobile
/// Documents/<container>/` — there is no public iCloud Drive API, so unlike
/// the other three providers this is a plain local `Scanner`/`Cleaner` pair
/// (the same `FTSWrapper` + trash-routed `Cleaner.clean` path as every other
/// local module), not a `CloudProvider`. The app's UI must visually
/// distinguish this from the true cloud-API providers so users understand
/// it reflects local sync state, not a live query against Apple's servers.
public struct ICloudLocalScanner: Scanner, Cleaner {
    /// e.g. "com~apple~CloudDocs" for the main iCloud Drive container; nil
    /// scans every container folder found under Mobile Documents (Pages,
    /// Numbers, and other iCloud-enabled apps each get their own).
    public let containerFilter: String?
    /// Injectable for testing — `~/Library/Mobile Documents` carries real
    /// TCC-style permission protection that a sandboxed test process may not
    /// have, the same class of restriction hit with `~/.Trash` in Phase 0.
    /// Defaults to the real path in production, matching every other local
    /// scanner's `rootPath`-parameter pattern (`DiskTreeScanner`, etc.).
    public let root: String

    public static var mobileDocumentsRoot: String {
        ("~/Library/Mobile Documents" as NSString).expandingTildeInPath
    }

    public init(containerFilter: String? = nil, root: String = ICloudLocalScanner.mobileDocumentsRoot) {
        self.containerFilter = containerFilter
        self.root = root
    }

    public func scan() async throws -> [ScanItem] {
        let fm = FileManager.default
        guard let containers = try? fm.contentsOfDirectory(atPath: root) else {
            return []
        }

        var items: [ScanItem] = []
        for container in containers {
            if let containerFilter, container != containerFilter { continue }

            let containerPath = (root as NSString).appendingPathComponent(container)
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: containerPath, isDirectory: &isDirectory), isDirectory.boolValue else {
                continue
            }

            for await item in FTSWrapper.walk(root: containerPath) where item.kind == .file {
                items.append(item)
            }
        }

        return items
    }
}

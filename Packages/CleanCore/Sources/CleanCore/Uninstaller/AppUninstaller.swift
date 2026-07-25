import Foundation

/// Composes an app bundle + every associated file into one batch, and
/// deletes purely through the shared `Cleaner.clean` default — one item's
/// failure (e.g. a locked Preferences file) doesn't hide the rest.
public struct AppUninstaller: Scanner, Cleaner {
    public let appBundlePath: String
    public let bundleIdentifier: String
    private let associatedFilesFinder: BundleAssociatedFilesFinder

    public init(
        appBundlePath: String,
        bundleIdentifier: String,
        associatedFilesFinder: BundleAssociatedFilesFinder = BundleAssociatedFilesFinder()
    ) {
        self.appBundlePath = appBundlePath
        self.bundleIdentifier = bundleIdentifier
        self.associatedFilesFinder = associatedFilesFinder
    }

    public func scan() async throws -> [ScanItem] {
        var totalSize: Int64 = 0
        for await item in FTSWrapper.walk(root: appBundlePath) where item.kind == .file {
            totalSize += item.size
        }

        var items: [ScanItem] = []
        if FileManager.default.fileExists(atPath: appBundlePath) {
            items.append(
                ScanItem(
                    path: appBundlePath,
                    size: totalSize,
                    kind: .directory,
                    severity: .safe,
                    sourceLabel: "Application bundle"
                )
            )
        }
        items.append(contentsOf: associatedFilesFinder.associatedFiles(forBundleIdentifier: bundleIdentifier))
        return items
    }
}

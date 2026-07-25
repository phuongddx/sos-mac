import Foundation

public struct InstalledApp: Sendable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let bundleIdentifier: String
    public let version: String?
    public let sparkleFeedURL: URL?
    public let bundlePath: String
    /// True when the bundle carries a Mac App Store receipt — there's no
    /// official API to auto-update these, so the Updater surfaces a deep
    /// link to the App Store instead of attempting an update itself.
    public let isAppStoreDistributed: Bool

    public init(
        name: String,
        bundleIdentifier: String,
        version: String?,
        sparkleFeedURL: URL?,
        bundlePath: String,
        isAppStoreDistributed: Bool
    ) {
        self.id = bundlePath
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.version = version
        self.sparkleFeedURL = sparkleFeedURL
        self.bundlePath = bundlePath
        self.isAppStoreDistributed = isAppStoreDistributed
    }
}

public struct InstalledAppsEnumerator: Sendable {
    private let searchDirectories: [String]

    public init(
        searchDirectories: [String] = [
            "/Applications",
            ("~/Applications" as NSString).expandingTildeInPath
        ]
    ) {
        self.searchDirectories = searchDirectories
    }

    public func enumerate() -> [InstalledApp] {
        var apps: [InstalledApp] = []
        let fileManager = FileManager.default

        for directory in searchDirectories {
            guard let entries = try? fileManager.contentsOfDirectory(atPath: directory) else { continue }

            for entry in entries where entry.hasSuffix(".app") {
                let bundlePath = (directory as NSString).appendingPathComponent(entry)
                let infoPlistPath = (bundlePath as NSString).appendingPathComponent("Contents/Info.plist")

                guard let plist = NSDictionary(contentsOfFile: infoPlistPath) as? [String: Any],
                      let bundleID = plist["CFBundleIdentifier"] as? String,
                      !bundleID.isEmpty
                else { continue }

                let name = (plist["CFBundleName"] as? String) ?? (entry as NSString).deletingPathExtension
                let version = plist["CFBundleShortVersionString"] as? String
                let feedURL = (plist["SUFeedURL"] as? String).flatMap(URL.init(string:))
                let receiptPath = (bundlePath as NSString).appendingPathComponent("Contents/_MASReceipt/receipt")
                let isAppStoreDistributed = fileManager.fileExists(atPath: receiptPath)

                apps.append(
                    InstalledApp(
                        name: name,
                        bundleIdentifier: bundleID,
                        version: version,
                        sparkleFeedURL: feedURL,
                        bundlePath: bundlePath,
                        isAppStoreDistributed: isAppStoreDistributed
                    )
                )
            }
        }

        return apps
    }
}

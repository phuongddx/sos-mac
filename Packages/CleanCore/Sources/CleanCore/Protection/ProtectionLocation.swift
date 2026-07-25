import Foundation

/// The allowlist of common malware-drop locations Protection's static
/// scanner walks — same "explicit reviewable list, not a heuristic crawl"
/// philosophy as `JunkRule`: a scan of "everywhere" would be both slow and a
/// false sense of thoroughness.
public struct ProtectionLocation: Sendable, Identifiable {
    public enum Kind: Sendable {
        case directPath(String)
        /// `~/Library/Application Support/Firefox/Profiles/*/extensions` —
        /// never the whole profile directory, which also holds history,
        /// cookies, and saved-login databases that have nothing to do with
        /// malware-drop scanning.
        case firefoxProfileExtensionsGlob
    }

    public let id: String
    public let label: String
    public let kind: Kind

    public init(id: String, label: String, kind: Kind) {
        self.id = id
        self.label = label
        self.kind = kind
    }

    /// `firefoxProfilesRootOverride` lets tests point the glob at a fixture
    /// directory instead of the real `~/Library/Application Support/Firefox/
    /// Profiles` — same injectable-root pattern `ICloudLocalScanner`/
    /// `BundleAssociatedFilesFinder` already use for sandbox-walled paths.
    public func resolvedPaths(fileManager: FileManager = .default, firefoxProfilesRootOverride: String? = nil) -> [String] {
        switch kind {
        case .directPath(let template):
            return [(template as NSString).expandingTildeInPath]

        case .firefoxProfileExtensionsGlob:
            let profilesRoot = firefoxProfilesRootOverride
                ?? ("~/Library/Application Support/Firefox/Profiles" as NSString).expandingTildeInPath
            guard let profileDirs = try? fileManager.contentsOfDirectory(atPath: profilesRoot) else {
                return []
            }
            return profileDirs.map { profileDir in
                let profilePath = (profilesRoot as NSString).appendingPathComponent(profileDir)
                return (profilePath as NSString).appendingPathComponent("extensions")
            }
        }
    }
}

extension ProtectionLocation {
    public static let allowlist: [ProtectionLocation] = [
        ProtectionLocation(id: "downloads", label: "Downloads", kind: .directPath("~/Downloads")),
        ProtectionLocation(id: "user-login-items", label: "User Login Items", kind: .directPath("~/Library/LaunchAgents")),
        ProtectionLocation(id: "system-login-items", label: "System Login Items", kind: .directPath("/Library/LaunchAgents")),
        ProtectionLocation(id: "system-daemons", label: "System Daemons", kind: .directPath("/Library/LaunchDaemons")),
        ProtectionLocation(
            id: "chrome-extensions",
            label: "Chrome Extensions",
            kind: .directPath("~/Library/Application Support/Google/Chrome/Default/Extensions")
        ),
        ProtectionLocation(id: "firefox-extensions", label: "Firefox Extensions", kind: .firefoxProfileExtensionsGlob)
    ]
}

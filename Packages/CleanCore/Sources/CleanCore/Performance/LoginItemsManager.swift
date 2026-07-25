import Foundation
import ServiceManagement

public struct LoginItemEntry: Sendable, Identifiable, Hashable {
    public let id: String
    public let label: String
    public let path: String

    public init(label: String, path: String) {
        self.id = path
        self.label = label
        self.path = path
    }
}

/// Uses `SMAppService` exclusively — never the deprecated
/// `SMLoginItemSetEnabled`/`AuthorizationExecuteWithPrivileges`.
public enum LoginItemsManager {
    private static let searchDirectories = [
        ("~/Library/LaunchAgents" as NSString).expandingTildeInPath,
        "/Library/LaunchAgents",
        "/Library/LaunchDaemons"
    ]

    /// Read-only enumeration of every installed LaunchAgent/LaunchDaemon
    /// plist — this app can only *manage* (register/unregister) its own
    /// entries via SMAppService, so this list is informational, not a set
    /// of togglable rows.
    public static func listInstalledAgents() -> [LoginItemEntry] {
        let fm = FileManager.default
        var entries: [LoginItemEntry] = []

        for directory in searchDirectories {
            guard let files = try? fm.contentsOfDirectory(atPath: directory) else { continue }
            for file in files where file.hasSuffix(".plist") {
                let fullPath = (directory as NSString).appendingPathComponent(file)
                entries.append(LoginItemEntry(label: file, path: fullPath))
            }
        }

        return entries
    }

    public static func mainAppLoginItemStatus() -> SMAppService.Status {
        SMAppService.mainApp.status
    }

    public static func registerMainAppAsLoginItem() throws {
        try SMAppService.mainApp.register()
    }

    public static func unregisterMainAppAsLoginItem() throws {
        try SMAppService.mainApp.unregister()
    }
}

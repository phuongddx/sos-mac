#if DEBUG
import Foundation
import CleanCore

/// Fictional Uninstaller sample data (PR 9). Built on `UITestFixtures.apps`; nothing is read
/// from the machine. Mirrors what the real engine reports (D1): the app bundle carries its
/// walked size, associated *files* carry their size, associated *folders* carry only a
/// directory-entry size that the screen never shows as a measurement.
extension UITestFixtures {
    /// The fixture apps as `InstalledApp`s, under a fictional `/Applications`.
    static var installedApps: [InstalledApp] {
        apps.map { fixture in
            InstalledApp(name: fixture.name,
                         bundleIdentifier: fixture.bundleID,
                         version: fixture.version,
                         sparkleFeedURL: nil,
                         bundlePath: bundlePath(for: fixture),
                         isAppStoreDistributed: fixture.isAppStore)
        }
    }

    static func bundlePath(for fixture: AppFixture) -> String {
        "/Applications/\(fixture.name).app"
    }

    /// What an inspect of `app` finds: the bundle, then associated files and folders.
    static func uninstallerItems(for app: InstalledApp) -> [ScanItem] {
        guard let fixture = apps.first(where: { $0.bundleID == app.bundleIdentifier }) else { return [] }
        let label = "Associated with \(fixture.bundleID)"
        let library = "\(home)/Library"
        return [
            ScanItem(path: app.bundlePath, size: fixture.appBytes, kind: .directory,
                     severity: .caution, sourceLabel: "Application bundle"),
            ScanItem(path: "\(library)/Preferences/\(fixture.bundleID).plist", size: 18_400, kind: .file,
                     sourceLabel: label),
            ScanItem(path: "\(library)/Application Support/\(fixture.name)", size: 64, kind: .directory,
                     sourceLabel: label),
            ScanItem(path: "\(library)/Caches/\(fixture.bundleID)", size: 64, kind: .directory,
                     sourceLabel: label),
            ScanItem(path: "\(library)/Saved Application State/\(fixture.bundleID).savedState", size: 64,
                     kind: .directory, sourceLabel: label),
            ScanItem(path: "\(library)/Logs/\(fixture.name).log", size: 412_000, kind: .file,
                     sourceLabel: label),
        ]
    }
}
#endif

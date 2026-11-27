#if DEBUG
import Foundation
import CleanCore

/// Fictional Updater sample data (PR 10). Built on `UITestFixtures.apps` and
/// `UITestFixtures.updaterRows`; nothing is read from the machine and the update feeds are
/// never contacted — the `.invalid` host (RFC 2606) cannot resolve, and the fixture loader
/// applies the "feed answers" directly instead of calling the feed.
extension UITestFixtures {
    /// A made-up Sparkle feed URL that can never resolve.
    static func fixtureFeedURL(for fixture: AppFixture) -> URL? {
        URL(string: "https://updates.example.invalid/\(fixture.id)/appcast.xml")
    }

    private static func updaterApp(_ fixture: AppFixture, version: String, hasFeed: Bool) -> InstalledApp {
        InstalledApp(name: fixture.name,
                     bundleIdentifier: fixture.bundleID,
                     version: version,
                     sparkleFeedURL: hasFeed ? fixtureFeedURL(for: fixture) : nil,
                     bundlePath: bundlePath(for: fixture),
                     isAppStoreDistributed: fixture.isAppStore)
    }

    /// The eight Updater fixture apps across the four groups (spec §5.8): three with a newer
    /// version, two App Store apps, two up to date, one without a feed.
    static var updaterApps: [InstalledApp] {
        updaterRows.compactMap { row in
            guard let fixture = apps.first(where: { $0.id == row.appID }) else { return nil }
            let hasFeed = row.kind == .updateAvailable || row.kind == .upToDate
            return updaterApp(fixture, version: row.installedVersion, hasFeed: hasFeed)
        }
    }

    /// The "all up to date" screen: every app has a feed and reports its own version. There is
    /// no App Store app and no app without a feed — either would keep the results screen,
    /// because "all up to date" is only claimed when every app was checkable and checked.
    static var updaterEmptyApps: [InstalledApp] {
        apps.filter { !$0.isAppStore }.map { fixture in
            updaterApp(fixture, version: fixture.version, hasFeed: true)
        }
    }

    /// What the fictional feed of the app at `bundlePath` reports: the fixture row's latest
    /// version, or — for the "all up to date" apps — the installed version itself.
    static func updaterLatestVersion(forBundlePath path: String) -> String? {
        guard let fixture = apps.first(where: { bundlePath(for: $0) == path }) else { return nil }
        if let row = updaterRows.first(where: { $0.appID == fixture.id }) {
            return row.latestVersion
        }
        return fixture.version
    }
}
#endif

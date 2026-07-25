import Foundation
import Testing
@testable import CleanCore

struct BundleAssociatedFilesFinderTests {
    @Test func findsExactMatchesAndExcludesDifferentBundleID() {
        #expect(BundleAssociatedFilesFinder.matches(entry: "com.example.app", bundleID: "com.example.app"))
        #expect(BundleAssociatedFilesFinder.matches(entry: "com.example.app.plist", bundleID: "com.example.app"))
        #expect(BundleAssociatedFilesFinder.matches(entry: "com.example.app.savedState", bundleID: "com.example.app"))

        // A different app whose id happens to be a superstring must NOT match
        // — this is the exact false-positive cross-app deletion risk.
        #expect(!BundleAssociatedFilesFinder.matches(entry: "com.example.app2", bundleID: "com.example.app"))
        #expect(!BundleAssociatedFilesFinder.matches(entry: "com.example.app2.plist", bundleID: "com.example.app"))
        #expect(!BundleAssociatedFilesFinder.matches(entry: "com.other.thing", bundleID: "com.example.app"))

        // An empty bundleID (malformed/corrupted Info.plist) must never fall
        // through to the prefix check — "".hasPrefix(".") would otherwise
        // match every dotfile/dot-folder, turning one broken app's uninstall
        // into a wildcard delete across every Library subpath.
        #expect(!BundleAssociatedFilesFinder.matches(entry: ".DS_Store", bundleID: ""))
        #expect(!BundleAssociatedFilesFinder.matches(entry: "", bundleID: ""))
    }

    @Test func associatedFilesFindsMatchingBundleAndExcludesOthers() throws {
        let fm = FileManager.default
        let fakeHome = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: fakeHome, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: fakeHome) }

        let bundleID = "com.example.testapp"
        let otherBundleID = "com.example.otherapp"

        let prefsDir = fakeHome.appendingPathComponent("Library/Preferences")
        try fm.createDirectory(at: prefsDir, withIntermediateDirectories: true)
        try "prefs".write(to: prefsDir.appendingPathComponent("\(bundleID).plist"), atomically: true, encoding: .utf8)
        try "other-prefs".write(to: prefsDir.appendingPathComponent("\(otherBundleID).plist"), atomically: true, encoding: .utf8)

        let cachesDir = fakeHome.appendingPathComponent("Library/Caches")
        try fm.createDirectory(at: cachesDir.appendingPathComponent(bundleID), withIntermediateDirectories: true)
        try fm.createDirectory(at: cachesDir.appendingPathComponent(otherBundleID), withIntermediateDirectories: true)

        let launchAgentsDir = fakeHome.appendingPathComponent("Library/LaunchAgents")
        try fm.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true)
        try "agent".write(to: launchAgentsDir.appendingPathComponent("\(bundleID).helper.plist"), atomically: true, encoding: .utf8)

        // Redirect NSHomeDirectory-based lookup by scanning the subpaths directly
        // against our fake home via a finder configured with that root.
        let finder = BundleAssociatedFilesFinder()
        let results = finder.associatedFiles(forBundleIdentifier: bundleID, homeOverride: fakeHome.path)
        let foundPaths = Set(results.map(\.path))

        #expect(foundPaths.contains(prefsDir.appendingPathComponent("\(bundleID).plist").path))
        #expect(foundPaths.contains(cachesDir.appendingPathComponent(bundleID).path))
        #expect(foundPaths.contains(launchAgentsDir.appendingPathComponent("\(bundleID).helper.plist").path))
        #expect(!foundPaths.contains(prefsDir.appendingPathComponent("\(otherBundleID).plist").path))
        #expect(!foundPaths.contains(cachesDir.appendingPathComponent(otherBundleID).path))
    }
}

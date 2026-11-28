import Foundation
import Testing
@testable import CleanCore

/// Security-scoped bookmark roundtrip: an NSOpenPanel grant saved as bookmark
/// data must resolve back to the same folder across launches (a fresh
/// UserDefaults suite stands in for "relaunch").
struct SecurityScopedBookmarkStoreTests {
    private func makeDefaults() -> UserDefaults {
        let suite = "bookmark-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeStore() -> SecurityScopedBookmarkStore {
        SecurityScopedBookmarkStore(defaults: makeDefaults())
    }

    @Test func roundtripsFolderAcrossFreshStore() throws {
        let fm = FileManager.default
        let folder = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: folder) }

        let defaults = makeDefaults()
        let first = SecurityScopedBookmarkStore(defaults: defaults)
        try first.store(folder, forKey: "home")

        // A fresh store over the same suite = a relaunch reading the same defaults.
        let relaunch = SecurityScopedBookmarkStore(defaults: defaults)
        let resolved = relaunch.resolveURL(forKey: "home")

        #expect(resolved?.resolvingSymlinksInPath() == folder.resolvingSymlinksInPath())
    }

    @Test func resolveReturnsNilForMissingKey() {
        let store = makeStore()
        #expect(store.resolveURL(forKey: "nope") == nil)
    }

    @Test func removeDeletesBookmark() throws {
        let fm = FileManager.default
        let folder = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: folder) }

        let store = makeStore()
        try store.store(folder, forKey: "home")
        store.remove(forKey: "home")

        #expect(store.resolveURL(forKey: "home") == nil)
    }

    @Test func storingReplacesPreviousBookmark() throws {
        let fm = FileManager.default
        let folderA = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folderB = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: folderA, withIntermediateDirectories: true)
        try fm.createDirectory(at: folderB, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: folderA); try? fm.removeItem(at: folderB) }

        let store = makeStore()
        try store.store(folderA, forKey: "home")
        try store.store(folderB, forKey: "home")

        #expect(store.resolveURL(forKey: "home")?.resolvingSymlinksInPath() == folderB.resolvingSymlinksInPath())
    }
}

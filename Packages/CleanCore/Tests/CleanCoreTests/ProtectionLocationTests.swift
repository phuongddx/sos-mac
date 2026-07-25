import Foundation
import Testing
@testable import CleanCore

struct ProtectionLocationTests {
    @Test func firefoxGlobResolvesToEachProfilesExtensionsSubfolderOnly() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let profilesRoot = root.appendingPathComponent("Firefox/Profiles")
        let profileA = profilesRoot.appendingPathComponent("abc123.default")
        let profileB = profilesRoot.appendingPathComponent("xyz789.dev-edition")
        try fm.createDirectory(at: profileA.appendingPathComponent("extensions"), withIntermediateDirectories: true)
        try fm.createDirectory(at: profileB.appendingPathComponent("extensions"), withIntermediateDirectories: true)
        // A sibling file that must never be included in the scan targets —
        // this is exactly the private data (history/cookies/logins) the
        // whole-profile path used to sweep in before this fix.
        try Data("not an extension".utf8).write(to: profileA.appendingPathComponent("places.sqlite"))
        defer { try? fm.removeItem(at: root) }

        let location = ProtectionLocation(id: "firefox-extensions", label: "Firefox Extensions", kind: .firefoxProfileExtensionsGlob)
        let resolved = location.resolvedPaths(fileManager: fm, firefoxProfilesRootOverride: profilesRoot.path)

        #expect(Set(resolved) == Set([
            profileA.appendingPathComponent("extensions").path,
            profileB.appendingPathComponent("extensions").path
        ]))
        #expect(!resolved.contains { $0.contains("places.sqlite") })
    }

    @Test func directPathExpandsTilde() {
        let location = ProtectionLocation(id: "test", label: "Test", kind: .directPath("~/Downloads"))
        let resolved = location.resolvedPaths()
        #expect(resolved == [(("~/Downloads" as NSString).expandingTildeInPath)])
    }
}

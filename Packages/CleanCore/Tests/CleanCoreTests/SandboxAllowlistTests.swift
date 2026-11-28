import Foundation
import Testing
@testable import CleanCore

/// The App Sandbox rule factories: same ids/labels/severities as the tilde
/// allowlist (so grouping and UI keep working), but rooted at the injected
/// concrete home folder, with helper/system locations dropped.
struct SandboxAllowlistTests {
    @Test func junkSandboxAllowlistUsesConcreteRootsAndDropsSystemCaches() throws {
        let home = "/Users/somebody"
        let rules = JunkRule.sandboxAllowlist(homeRoot: home)

        #expect(rules.count == 3)
        #expect(rules.map(\.id) == ["user-caches", "user-logs", "app-support-caches"])
        #expect(rules.allSatisfy { !$0.requiresPrivilegedHelper })

        let roots = rules.flatMap { $0.resolvedRoots(fileManager: .default) }
        #expect(roots.contains("/Users/somebody/Library/Caches"))
        #expect(roots.contains("/Users/somebody/Library/Logs"))
        // No tilde-expansion (which would resolve to the sandbox container).
        #expect(roots.allSatisfy { $0.hasPrefix("/Users/somebody") })
    }

    @Test func junkSandboxAllowlistGlobsAppSupportCachesUnderRoot() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let appSupport = home.appendingPathComponent("Library/Application Support")
        try fm.createDirectory(at: appSupport.appendingPathComponent("SomeApp/Caches"), withIntermediateDirectories: true)
        try fm.createDirectory(at: appSupport.appendingPathComponent("OtherApp/NotCache"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: home) }

        let rules = JunkRule.sandboxAllowlist(homeRoot: home.path)
        let glob = rules.first { $0.id == "app-support-caches" }
        let roots = try #require(glob).resolvedRoots(fileManager: fm)

        #expect(roots == [appSupport.appendingPathComponent("SomeApp/Caches").path])
    }

    @Test func junkSandboxAllowlistRejectsEmptyAndRootPaths() {
        #expect(JunkRule.sandboxAllowlist(homeRoot: "").isEmpty)
        #expect(JunkRule.sandboxAllowlist(homeRoot: "/").isEmpty)
    }

    @Test func protectionSandboxAllowlistDropsSystemLocations() {
        let home = "/Users/somebody"
        let locations = ProtectionLocation.sandboxAllowlist(homeRoot: home)

        #expect(locations.count == 4)
        #expect(locations.map(\.id) == ["downloads", "user-login-items", "chrome-extensions", "firefox-extensions"])

        let directRoots = locations.flatMap { location -> [String] in
            if case .directPath(let path) = location.kind { return [path] }
            return []
        }
        #expect(directRoots.allSatisfy { $0.hasPrefix("/Users/somebody") })
    }

    @Test func protectionSandboxFirefoxGlobWalksUnderInjectedRoot() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let profiles = home.appendingPathComponent("Library/Application Support/Firefox/Profiles")
        try fm.createDirectory(at: profiles.appendingPathComponent("abc.default"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: home) }

        let locations = ProtectionLocation.sandboxAllowlist(homeRoot: home.path)
        let firefox = locations.first { $0.id == "firefox-extensions" }
        let paths = try #require(firefox).resolvedPaths(fileManager: fm)

        #expect(paths == [profiles.appendingPathComponent("abc.default/extensions").path])
    }

    @Test func protectionSandboxAllowlistRejectsEmptyHome() {
        #expect(ProtectionLocation.sandboxAllowlist(homeRoot: "").isEmpty)
    }
}

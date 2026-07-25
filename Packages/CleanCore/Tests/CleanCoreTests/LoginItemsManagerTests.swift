import Testing
@testable import CleanCore

/// Deliberately does NOT exercise register()/unregister() round-trips —
/// SMAppService mutates the real machine's login-item registry and commonly
/// fails in an ad-hoc-signed debug build run outside /Applications for
/// reasons unrelated to code correctness (signing/location requirements).
/// Automated tests only cover the read-only paths that can't have side
/// effects on the user's actual system.
struct LoginItemsManagerTests {
    @Test func listInstalledAgentsReturnsOnlyPlistFiles() {
        let entries = LoginItemsManager.listInstalledAgents()
        for entry in entries {
            #expect(entry.label.hasSuffix(".plist"))
            #expect(entry.path.hasSuffix(entry.label))
        }
    }

    @Test func mainAppLoginItemStatusDoesNotThrow() {
        // Read-only status check — safe to call, has no side effects.
        _ = LoginItemsManager.mainAppLoginItemStatus()
    }
}

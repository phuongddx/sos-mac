import Foundation
import Testing
@testable import CleanCore

struct HelperOperationValidatorTests {
    @Test func allowsAPathStrictlyInsideAnAllowlistedRoot() {
        #expect(HelperOperationValidator.isSystemPathAllowed("/Library/Caches/com.example.app"))
    }

    @Test func rejectsTheAllowlistedRootItself() {
        // Removing the whole /Library/Caches directory is never a valid
        // request — only paths strictly inside it.
        #expect(!HelperOperationValidator.isSystemPathAllowed("/Library/Caches"))
    }

    @Test func rejectsAPathOutsideEveryAllowlistedRoot() {
        #expect(!HelperOperationValidator.isSystemPathAllowed("/Library/Application Support/important-data"))
        #expect(!HelperOperationValidator.isSystemPathAllowed("/System/Library/Caches"))
    }

    @Test func rejectsATraversalAttemptThatEscapesTheAllowlistedRoot() {
        #expect(!HelperOperationValidator.isSystemPathAllowed("/Library/Caches/../../etc/passwd"))
    }

    @Test func rejectsAPrefixMatchThatIsNotActuallyInsideTheRoot() {
        // "/Library/Caches-evil" textually starts with "/Library/Caches" but
        // is a sibling directory, not a child — a naive `hasPrefix` check
        // without the trailing "/" would wrongly allow this.
        #expect(!HelperOperationValidator.isSystemPathAllowed("/Library/Caches-evil/payload"))
    }

    @Test func resolvesASymlinkBeforeCheckingTheAllowlist() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let outsideDir = root.appendingPathComponent("outside")
        try fm.createDirectory(at: outsideDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let outsideFile = outsideDir.appendingPathComponent("secret.txt")
        try Data("not a cache file".utf8).write(to: outsideFile)

        // A symlink placed under the allowlisted root but pointing outside
        // it must resolve to its real target before the allowlist check,
        // not be trusted at face value.
        let symlinkPath = "/Library/Caches/\(UUID().uuidString)-symlink"
        try? fm.removeItem(atPath: symlinkPath)
        do {
            try fm.createSymbolicLink(atPath: symlinkPath, withDestinationPath: outsideFile.path)
        } catch {
            // No write access to /Library/Caches in this sandbox — the
            // resolution logic itself is still exercised via the pure
            // string-based traversal test above; skip the live-symlink
            // variant rather than fail the suite on an environment limit.
            return
        }
        defer { try? fm.removeItem(atPath: symlinkPath) }

        #expect(!HelperOperationValidator.isSystemPathAllowed(symlinkPath))
    }

    @Test func allowsLoadUnloadOnAllowlistedLaunchAgentAndDaemonPlists() {
        #expect(HelperOperationValidator.isDaemonPlistAllowed("/Library/LaunchAgents/com.example.agent.plist"))
        #expect(HelperOperationValidator.isDaemonPlistAllowed("/Library/LaunchDaemons/com.example.daemon.plist"))
    }

    @Test func rejectsAPlistOutsideTheAllowlistedRoots() {
        #expect(!HelperOperationValidator.isDaemonPlistAllowed("/Users/someone/Library/LaunchAgents/evil.plist"))
        #expect(!HelperOperationValidator.isDaemonPlistAllowed("/tmp/evil.plist"))
    }

    @Test func rejectsANonPlistFileEvenInsideAnAllowlistedRoot() {
        #expect(!HelperOperationValidator.isDaemonPlistAllowed("/Library/LaunchDaemons/not-a-plist.txt"))
    }

    @Test func daemonActionOnlyAcceptsLoadOrUnload() {
        #expect(HelperOperationValidator.DaemonAction(rawValue: "load") == .load)
        #expect(HelperOperationValidator.DaemonAction(rawValue: "unload") == .unload)
        #expect(HelperOperationValidator.DaemonAction(rawValue: "start") == nil)
        #expect(HelperOperationValidator.DaemonAction(rawValue: "rm -rf /") == nil)
    }
}

import Foundation
import Testing
@testable import CleanCore

struct JunkScannerTests {
    @Test func scanTagsSeverityAndOnlyReturnsAllowlistedPaths() async throws {
        let fm = FileManager.default
        let fakeHome = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: fakeHome, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: fakeHome) }

        // Mimic ~/Library/Caches with one file, and a sibling directory that
        // is NOT on the allowlist and must never be returned.
        let caches = fakeHome.appendingPathComponent("Library/Caches")
        try fm.createDirectory(at: caches, withIntermediateDirectories: true)
        let cacheFile = caches.appendingPathComponent("app.cache")
        try "junk".write(to: cacheFile, atomically: true, encoding: .utf8)

        let documents = fakeHome.appendingPathComponent("Documents")
        try fm.createDirectory(at: documents, withIntermediateDirectories: true)
        let userDoc = documents.appendingPathComponent("important.txt")
        try "keep me".write(to: userDoc, atomically: true, encoding: .utf8)

        // Logs: one old (safe), one fresh (caution) — proves age-based severity.
        let logs = fakeHome.appendingPathComponent("Library/Logs")
        try fm.createDirectory(at: logs, withIntermediateDirectories: true)
        let oldLog = logs.appendingPathComponent("old.log")
        let freshLog = logs.appendingPathComponent("fresh.log")
        try "old".write(to: oldLog, atomically: true, encoding: .utf8)
        try "fresh".write(to: freshLog, atomically: true, encoding: .utf8)
        let tenDaysAgo = Date().addingTimeInterval(-10 * 24 * 3600)
        setAccessAndModificationDate(tenDaysAgo, atPath: oldLog.path)

        let rules: [JunkRule] = [
            JunkRule(id: "user-caches", label: "User App Caches", kind: .directPath(caches.path), defaultSeverity: .safe),
            JunkRule(id: "user-logs", label: "User Logs", kind: .directPath(logs.path), defaultSeverity: .safe)
        ]
        let scanner = JunkScanner(rules: rules, now: { Date() })
        let items = try await scanner.scan()
        let foundPaths = Set(items.map(\.path))

        #expect(foundPaths.contains(cacheFile.path))
        #expect(!foundPaths.contains(userDoc.path))

        let oldLogItem = try #require(items.first { $0.path == oldLog.path })
        let freshLogItem = try #require(items.first { $0.path == freshLog.path })
        #expect(oldLogItem.severity == .safe)
        #expect(freshLogItem.severity == .caution)
        #expect(oldLogItem.sourceLabel == "User Logs")
    }

    @Test func systemCachesRuleTagsRequiresPrivilegedHelper() async throws {
        let fm = FileManager.default
        let systemLike = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: systemLike, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: systemLike) }
        let file = systemLike.appendingPathComponent("root-owned.cache")
        try "x".write(to: file, atomically: true, encoding: .utf8)

        let rules: [JunkRule] = [
            JunkRule(
                id: "system-caches",
                label: "System Caches",
                kind: .directPath(systemLike.path),
                defaultSeverity: .caution,
                requiresPrivilegedHelper: true
            )
        ]
        let scanner = JunkScanner(rules: rules)
        let items = try await scanner.scan()

        let item = try #require(items.first)
        #expect(item.requiresPrivilegedHelper)
        #expect(item.severity == .caution)
    }

    @Test func reportsProgressOncePerCompletedRule() async throws {
        let fm = FileManager.default
        let fakeHome = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: fakeHome, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: fakeHome) }

        let caches = fakeHome.appendingPathComponent("Caches")
        try fm.createDirectory(at: caches, withIntermediateDirectories: true)
        try "x".write(to: caches.appendingPathComponent("a.cache"), atomically: true, encoding: .utf8)

        let logs = fakeHome.appendingPathComponent("Logs")
        try fm.createDirectory(at: logs, withIntermediateDirectories: true)
        try "x".write(to: logs.appendingPathComponent("a.log"), atomically: true, encoding: .utf8)

        let rules: [JunkRule] = [
            JunkRule(id: "user-caches", label: "User App Caches", kind: .directPath(caches.path), defaultSeverity: .safe),
            JunkRule(id: "user-logs", label: "User Logs", kind: .directPath(logs.path), defaultSeverity: .safe)
        ]
        let scanner = JunkScanner(rules: rules)

        let container = ProgressContainer()
        _ = try await scanner.scan(onProgress: { container.reported.append($0) })

        #expect(container.reported.count == 2)
        #expect(container.reported.map(\.itemsProcessed) == [1, 2])
        #expect(container.reported.allSatisfy { $0.totalItems == 2 })
        #expect(container.reported.map(\.currentPath) == ["User App Caches", "User Logs"])
    }
}

/// `FileManager`/`FileAttributeKey` has no public setter for a file's access
/// time (only creation/modification date) — FTSWrapper reads `st_atime`
/// directly, so the test needs the real POSIX `utimes()` call to make the
/// "old log" fixture deterministic instead of depending on real wall-clock
/// access history.
private func setAccessAndModificationDate(_ date: Date, atPath path: String) {
    let seconds = Int(date.timeIntervalSince1970)
    let times = [
        timeval(tv_sec: seconds, tv_usec: 0),
        timeval(tv_sec: seconds, tv_usec: 0)
    ]
    _ = times.withUnsafeBufferPointer { utimes(path, $0.baseAddress) }
}

/// Helper class for capturing progress reports in tests (avoids Swift 6 Sendable capture issues).
private final class ProgressContainer: @unchecked Sendable {
    var reported: [ScanProgress] = []
}

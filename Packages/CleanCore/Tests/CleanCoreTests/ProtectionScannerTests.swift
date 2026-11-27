import Foundation
import Testing
@testable import CleanCore

struct ProtectionScannerTests {
    /// 250 files crosses exactly one 200-file throttle boundary, so a correct
    /// implementation reports twice: once at 200, once for the final item.
    @Test func reportsThrottledProgressWithRealPreCountedTotal() async throws {
        let fileCount = 250
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        // Nested on purpose — proves the pre-count recurses into
        // subdirectories rather than only counting root's immediate children.
        let nested = root.appendingPathComponent("nested")
        try fm.createDirectory(at: nested, withIntermediateDirectories: true)
        for index in 0..<fileCount {
            let directory = index.isMultiple(of: 2) ? root : nested
            try "\(index)".write(to: directory.appendingPathComponent("f\(index).txt"), atomically: true, encoding: .utf8)
        }

        let locations = [ProtectionLocation(id: "test", label: "Test Location", kind: .directPath(root.path))]
        let scanner = ProtectionScanner(locations: locations, signatureDatabase: .empty)

        let container = ProgressContainer()
        _ = try await scanner.scan(onProgress: { container.reported.append($0) })

        let reported = container.reported
        // Throttled: far fewer callbacks than files, but never zero.
        #expect(!reported.isEmpty)
        #expect(reported.count < fileCount)
        #expect(reported.allSatisfy { $0.totalItems == fileCount })
        #expect(reported.map(\.itemsProcessed) == reported.map(\.itemsProcessed).sorted())
        // The last item always reports, even off a throttle boundary, so the
        // bar reliably reaches 100%.
        #expect(reported.last?.itemsProcessed == fileCount)
        #expect(reported.allSatisfy { $0.currentPath != nil })
    }

    /// A scan smaller than one throttle interval must still report — the
    /// completion report is unconditional, not boundary-dependent.
    @Test func reportsFinalProgressEvenBelowThrottleInterval() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        try "a".write(to: root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "b".write(to: root.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)

        let locations = [ProtectionLocation(id: "test", label: "Test Location", kind: .directPath(root.path))]
        let scanner = ProtectionScanner(locations: locations, signatureDatabase: .empty)

        let container = ProgressContainer()
        _ = try await scanner.scan(onProgress: { container.reported.append($0) })

        #expect(container.reported.count == 1)
        #expect(container.reported.last?.itemsProcessed == 2)
        #expect(container.reported.last?.totalItems == 2)
    }

    // MARK: - Unreadable roots (review F, D10)

    /// A root the test user cannot open is reported with the system's reason and never
    /// walked; a root that does not exist is a legitimately empty location, not an
    /// unreadable one; a readable root is walked and is in neither list.
    @Test func reportsAnUnreadableRootButNotAMissingOne() async throws {
        // As root, chmod 000 does not block reads, so the premise cannot be set up.
        guard geteuid() != 0 else { return }

        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("sosmac-protection-roots-\(UUID().uuidString)")
        let readable = base.appendingPathComponent("readable")
        let locked = base.appendingPathComponent("locked")
        let missing = base.appendingPathComponent("missing")
        try fm.createDirectory(at: readable, withIntermediateDirectories: true)
        try fm.createDirectory(at: locked, withIntermediateDirectories: true)
        try "a".write(to: readable.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "b".write(to: locked.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer {
            // Restore access first, or the fixture cannot be removed.
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
            try? fm.removeItem(at: base)
        }

        let locations = [
            ProtectionLocation(id: "readable", label: "Readable", kind: .directPath(readable.path)),
            ProtectionLocation(id: "locked", label: "Locked", kind: .directPath(locked.path)),
            ProtectionLocation(id: "missing", label: "Missing", kind: .directPath(missing.path)),
        ]
        let scanner = ProtectionScanner(locations: locations, signatureDatabase: .empty)

        let container = ProgressContainer()
        let outcome = try await scanner.scan(onProgress: { container.reported.append($0) })

        #expect(outcome.findings.isEmpty)
        #expect(outcome.unreadableRoots.map(\.path) == [locked.path])
        #expect(outcome.unreadableRoots.first?.reason.isEmpty == false)
        // Only the readable root was walked: its one file is the whole total.
        #expect(container.reported.last?.itemsProcessed == 1)
        #expect(container.reported.last?.totalItems == 1)
    }

    @Test func aTreeWithEveryRootReadableReportsNoUnreadableRoots() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        try "a".write(to: root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)

        let locations = [ProtectionLocation(id: "test", label: "Test", kind: .directPath(root.path))]
        let outcome = try await ProtectionScanner(locations: locations, signatureDatabase: .empty).scan()

        #expect(outcome.unreadableRoots.isEmpty)
    }

    /// A cancelled scan throws `CancellationError` out of the engine rather than returning a
    /// partial outcome that could read as a result.
    @Test func aCancelledScanThrowsCancellationError() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        for index in 0..<300 {
            try "\(index)".write(to: root.appendingPathComponent("f\(index).txt"), atomically: true, encoding: .utf8)
        }
        let locations = [ProtectionLocation(id: "test", label: "Test", kind: .directPath(root.path))]
        let scanner = ProtectionScanner(locations: locations, signatureDatabase: .empty)

        let task = Task { try await scanner.scan(onProgress: { _ in }) }
        task.cancel()

        await #expect(throws: CancellationError.self) { try await task.value }
    }
}

/// Helper class for capturing progress reports in tests (avoids Swift 6 Sendable capture issues).
private final class ProgressContainer: @unchecked Sendable {
    var reported: [ScanProgress] = []
}

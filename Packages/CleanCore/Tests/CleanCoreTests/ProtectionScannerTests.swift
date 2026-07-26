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
}

/// Helper class for capturing progress reports in tests (avoids Swift 6 Sendable capture issues).
private final class ProgressContainer: @unchecked Sendable {
    var reported: [ScanProgress] = []
}

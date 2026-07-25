import Foundation
import Testing
@testable import CleanCore

struct ProtectionScannerTests {
    @Test func reportsPerFileProgressWithRealPreCountedTotal() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        // Nested on purpose — proves the pre-count recurses into
        // subdirectories rather than only counting root's immediate children.
        let nested = root.appendingPathComponent("nested")
        try fm.createDirectory(at: nested, withIntermediateDirectories: true)
        try "a".write(to: root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "b".write(to: nested.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)

        let locations = [ProtectionLocation(id: "test", label: "Test Location", kind: .directPath(root.path))]
        let scanner = ProtectionScanner(locations: locations, signatureDatabase: .empty)

        let container = ProgressContainer()
        _ = try await scanner.scan(onProgress: { container.reported.append($0) })

        #expect(container.reported.count == 2)
        #expect(container.reported.allSatisfy { $0.totalItems == 2 })
        #expect(container.reported.map(\.itemsProcessed) == [1, 2])
        // .compactMap, not .map, so this compares Set<String> to Set<String>
        // — every currentPath is non-nil here, but keeping both sides the
        // same concrete (non-Optional) type avoids relying on Optional's
        // Set/Equatable inference at the call site.
        #expect(Set(container.reported.compactMap(\.currentPath)) == Set([root.appendingPathComponent("a.txt").path, nested.appendingPathComponent("b.txt").path]))
    }
}

/// Helper class for capturing progress reports in tests (avoids Swift 6 Sendable capture issues).
private final class ProgressContainer: @unchecked Sendable {
    var reported: [ScanProgress] = []
}

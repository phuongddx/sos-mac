import Foundation
import Testing
import CleanCore
@testable import SOSMac

/// `ProgressiveCleaner` follows `CleanerTrashTests`' pattern: real temp files, the real
/// `Cleaner.clean(_:)` trash route, and the trashed file removed from the user's Trash
/// afterwards so no debris is left behind.
@Suite("ProgressiveCleaner")
struct ProgressiveCleanerTests {
    private struct TestCleaner: Cleaner {}

    /// Collects the per-item progress on the main actor, as the frame consumes it.
    @MainActor
    private final class ProgressRecorder {
        var calls: [(index: Int, path: String)] = []

        func append(index: Int, item: ScanItem) {
            calls.append((index, item.path))
        }
    }

    private func makeItem(in dir: URL, name: String, bytes: Int64, exists: Bool = true) throws -> ScanItem {
        let file = dir.appendingPathComponent(name)
        if exists {
            try String(repeating: "x", count: Int(max(bytes, 1))).write(to: file, atomically: true, encoding: .utf8)
        }
        return ScanItem(path: file.path, size: bytes, kind: .file)
    }

    @Test("moves items one by one, yields per-item progress, aggregates one result")
    func movesOneByOneAndReportsProgress() async throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        // Unique names so the resulting Trash paths are deterministic (see CleanerTrashTests).
        let names = (0..<3).map { "progressive-\(UUID().uuidString)-\($0).txt" }
        let items = try names.map { try makeItem(in: dir, name: $0, bytes: 4) }
        let recorder = ProgressRecorder()

        let result = await ProgressiveCleaner().clean(items, using: TestCleaner()) { index, item in
            recorder.append(index: index, item: item)
        }

        #expect(result.succeeded.count == 3)
        #expect(result.failed.isEmpty)
        #expect(result.reclaimedBytes == 12)
        #expect(Set(result.succeeded.map(\.path)) == Set(items.map(\.path)))

        let progress = await recorder.calls
        #expect(progress.map(\.index) == [0, 1, 2])
        #expect(progress.map(\.path) == items.map(\.path))
        // Every source file left its place — through the one trash route.
        for item in items {
            #expect(!fm.fileExists(atPath: item.path))
        }
        // Don't leave test debris in the real Trash.
        let trash = try fm.url(for: .trashDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        for name in names {
            try? fm.removeItem(at: trash.appendingPathComponent(name))
        }
    }

    @Test("a failed item is aggregated, not thrown, and still counts as progress")
    func failureIsAggregatedAndCounted() async throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        let goodName = "progressive-good-\(UUID().uuidString).txt"
        let good = try makeItem(in: dir, name: goodName, bytes: 2)
        let missing = try makeItem(in: dir, name: "progressive-missing-\(UUID().uuidString).txt", bytes: 5, exists: false)
        let items = [missing, good]
        let recorder = ProgressRecorder()

        let result = await ProgressiveCleaner().clean(items, using: TestCleaner()) { index, item in
            recorder.append(index: index, item: item)
        }

        #expect(result.succeeded.map(\.path) == [good.path])
        #expect(result.failed.count == 1)
        #expect(result.failed.first?.item.path == missing.path)
        #expect(!(result.failed.first?.reason.isEmpty ?? true))
        #expect(!fm.fileExists(atPath: good.path))

        let progress = await recorder.calls
        #expect(progress.map(\.index) == [0, 1])
        // The frame's "n of N" counts attempts, not successes.
        #expect(progress.map(\.path) == [missing.path, good.path])

        let trash = try fm.url(for: .trashDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        try? fm.removeItem(at: trash.appendingPathComponent(goodName))
    }

    @Test("an empty selection yields an empty result and no progress")
    func emptySelectionDoesNothing() async throws {
        let recorder = ProgressRecorder()
        let result = await ProgressiveCleaner().clean([], using: TestCleaner()) { index, item in
            recorder.append(index: index, item: item)
        }
        #expect(result.succeeded.isEmpty)
        #expect(result.failed.isEmpty)
        let progress = await recorder.calls
        #expect(progress.isEmpty)
    }
}

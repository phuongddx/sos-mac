import Foundation
import Testing
@testable import CleanCore

final class ProgressCollector: Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var _reported: [ScanProgress] = []

    var reported: [ScanProgress] {
        lock.lock()
        defer { lock.unlock() }
        return _reported
    }

    func append(_ progress: ScanProgress) {
        lock.lock()
        defer { lock.unlock() }
        _reported.append(progress)
    }
}

struct DuplicateFinderTests {
    /// 250 same-size files cross exactly one 200-file throttle boundary, so a
    /// correct implementation reports twice: once at 200, once at completion.
    @Test func findExactDuplicateGroupsReportsThrottledHashingProgress() async throws {
        let fileCount = 250
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        // Same size, same content — real duplicates, so every file reaches the
        // hashing phase (SizeGrouper only groups by size; a singleton-size
        // bucket never gets hashed at all).
        for index in 0..<fileCount {
            try Data(repeating: 0x41, count: 16).write(to: root.appendingPathComponent("f\(index).txt"))
        }

        let collector = ProgressCollector()
        let result = try await DuplicateFinder(rootPath: root.path)
            .findExactDuplicateGroups(onProgress: { progress in
                collector.append(progress)
            })

        #expect(result.groups.count == 1)

        let reported = collector.reported
        let listingUpdates = reported.filter { $0.totalItems == nil }
        let hashingUpdates = reported.filter { $0.totalItems != nil }
        // Throttled: far fewer callbacks than files, but never zero.
        #expect(!hashingUpdates.isEmpty)
        #expect(hashingUpdates.count < fileCount)
        #expect(hashingUpdates.allSatisfy { $0.totalItems == fileCount })
        #expect(hashingUpdates.map(\.itemsProcessed) == hashingUpdates.map(\.itemsProcessed).sorted())
        // The last item always reports, even off a throttle boundary.
        #expect(hashingUpdates.last?.itemsProcessed == fileCount)
        // Listing-phase updates (if any fired for this fixture) must never
        // claim a total the engine can't know ahead of the walk.
        #expect(listingUpdates.allSatisfy { $0.totalItems == nil })
    }

    /// A batch smaller than one throttle interval must still report — the
    /// completion report is unconditional, not boundary-dependent.
    @Test func findSimilarImageGroupsReportsFinalProgressBelowThrottleInterval() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        // Not a valid image — PerceptualHasher.dHash will fail to decode it,
        // which is fine here: this test only asserts the *count* of hashing
        // attempts, not that a match was found.
        try "not an image".write(to: root.appendingPathComponent("a.jpg"), atomically: true, encoding: .utf8)

        let collector = ProgressCollector()
        _ = try await DuplicateFinder(rootPath: root.path)
            .findSimilarImageGroups(onProgress: { progress in
                collector.append(progress)
            })

        let hashingUpdates = collector.reported.filter { $0.totalItems != nil }
        #expect(hashingUpdates.count == 1)
        #expect(hashingUpdates[0].totalItems == 1)
        #expect(hashingUpdates[0].itemsProcessed == 1)
    }

    @Test func findSimilarImageGroupsThrottlesProgressAcrossManyImages() async throws {
        let fileCount = 250
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        for index in 0..<fileCount {
            try "not an image \(index)".write(to: root.appendingPathComponent("f\(index).jpg"), atomically: true, encoding: .utf8)
        }

        let collector = ProgressCollector()
        _ = try await DuplicateFinder(rootPath: root.path)
            .findSimilarImageGroups(onProgress: { progress in
                collector.append(progress)
            })

        let hashingUpdates = collector.reported.filter { $0.totalItems != nil }
        #expect(!hashingUpdates.isEmpty)
        #expect(hashingUpdates.count < fileCount)
        #expect(hashingUpdates.allSatisfy { $0.totalItems == fileCount })
        #expect(hashingUpdates.last?.itemsProcessed == fileCount)
    }
}

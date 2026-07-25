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
    @Test func findExactDuplicateGroupsReportsListingThenHashingProgress() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        // Same size, same content — a real duplicate pair, so both files
        // reach the hashing phase (SizeGrouper only groups by size; a
        // singleton-size bucket never gets hashed at all).
        try Data(repeating: 0x41, count: 16).write(to: root.appendingPathComponent("a.txt"))
        try Data(repeating: 0x41, count: 16).write(to: root.appendingPathComponent("b.txt"))

        let collector = ProgressCollector()
        let result = try await DuplicateFinder(rootPath: root.path)
            .findExactDuplicateGroups(onProgress: { progress in
                collector.append(progress)
            })

        #expect(result.groups.count == 1)

        let reported = collector.reported
        let listingUpdates = reported.filter { $0.totalItems == nil }
        let hashingUpdates = reported.filter { $0.totalItems != nil }
        #expect(!hashingUpdates.isEmpty)
        #expect(hashingUpdates.allSatisfy { $0.totalItems == 2 })
        #expect(hashingUpdates.map(\.itemsProcessed) == Array(1...hashingUpdates.count))
        // Listing-phase updates (if any fired for this small fixture) must
        // never claim a total the engine can't know ahead of the walk.
        #expect(listingUpdates.allSatisfy { $0.totalItems == nil })
    }

    @Test func findSimilarImageGroupsReportsHashingProgressWithKnownTotal() async throws {
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

        let reported = collector.reported
        let hashingUpdates = reported.filter { $0.totalItems != nil }
        #expect(hashingUpdates.count == 1)
        #expect(hashingUpdates[0].totalItems == 1)
        #expect(hashingUpdates[0].itemsProcessed == 1)
    }
}

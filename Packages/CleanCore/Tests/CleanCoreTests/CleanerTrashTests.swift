import Foundation
import Testing
@testable import CleanCore

private struct TestCleaner: Cleaner {}

struct CleanerTrashTests {
    @Test func defaultCleanRoutesThroughTrashNotHardDelete() async throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        // Name embeds a UUID so the resulting Trash path is deterministic:
        // Finder/FileManager append a " 2" suffix on a name collision, which
        // would make a fixed "~/.Trash/<name>" existence check flaky against
        // leftovers from prior runs. Listing ~/.Trash's contents to search
        // for the file instead hits a TCC permission wall outside a signed,
        // user-consented app context, so a collision-proof deterministic path
        // is the robust way to prove trash-routing here.
        let uniqueName = "delete-me-\(UUID().uuidString).txt"
        let file = dir.appendingPathComponent(uniqueName)
        try "temp".write(to: file, atomically: true, encoding: .utf8)

        let item = ScanItem(path: file.path, size: 4, kind: .file)
        let result = try await TestCleaner().clean([item])

        #expect(result.succeeded.count == 1)
        #expect(result.failed.isEmpty)
        #expect(!fm.fileExists(atPath: file.path))

        let trashURL = try fm.url(for: .trashDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        let landedPath = trashURL.appendingPathComponent(uniqueName).path
        #expect(fm.fileExists(atPath: landedPath))

        try? fm.removeItem(atPath: landedPath) // don't leave test debris in the user's real Trash
    }

    @Test func defaultCleanCollectsFailureWithoutAbortingBatch() async throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        let goodFile = dir.appendingPathComponent("good.txt")
        try "ok".write(to: goodFile, atomically: true, encoding: .utf8)
        let missingFile = dir.appendingPathComponent("does-not-exist.txt")

        let items = [
            ScanItem(path: missingFile.path, size: 0, kind: .file),
            ScanItem(path: goodFile.path, size: 2, kind: .file)
        ]

        let result = try await TestCleaner().clean(items)

        #expect(result.succeeded.count == 1)
        #expect(result.succeeded.first?.path == goodFile.path)
        #expect(result.failed.count == 1)
        #expect(result.failed.first?.item.path == missingFile.path)
        #expect(!fm.fileExists(atPath: goodFile.path))
    }
}

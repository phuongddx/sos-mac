import Foundation
import Testing
@testable import CleanCore

struct SpaceLensCleanupPolicyTests {
    @Test func permitsWritableFileBelowScanRoot() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("movie.mov")
        try Data(repeating: 0, count: 10).write(to: file)

        let item = ScanItem(path: file.path, size: 10, kind: .file)

        #expect(SpaceLensCleanupPolicy().eligibility(for: item, scanRootPath: root.path) == .eligible)
    }

    @Test(arguments: ["/System/Library/test", "/private/tmp/test", "/usr/local/test", "/bin/test", "/sbin/test"])
    func rejectsProtectedSystemPaths(_ path: String) {
        let item = ScanItem(path: path, size: 1, kind: .file)

        guard case .ineligible = SpaceLensCleanupPolicy().eligibility(for: item, scanRootPath: "/") else {
            Issue.record("Protected path was selectable: \(path)")
            return
        }
    }

    @Test func rejectsScanRootAndPathsOutsideIt() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let outside = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: outside) }

        let rootItem = ScanItem(path: root.path, size: 0, kind: .directory)
        let outsideItem = ScanItem(path: outside.path, size: 0, kind: .directory)

        guard case .ineligible = SpaceLensCleanupPolicy().eligibility(for: rootItem, scanRootPath: root.path) else {
            Issue.record("Scan root was selectable")
            return
        }
        guard case .ineligible = SpaceLensCleanupPolicy().eligibility(for: outsideItem, scanRootPath: root.path) else {
            Issue.record("Outside path was selectable")
            return
        }
    }

    @Test func removesSelectedDescendantWhenDirectoryIsAlsoSelected() {
        let root = "/Users/ana/Downloads"
        let folder = ScanItem(path: "\(root)/project", size: 50, kind: .directory)
        let child = ScanItem(path: "\(root)/project/build.zip", size: 20, kind: .file)

        let selection = SpaceLensCleanupPolicy().normalizedSelection(from: [child, folder], scanRootPath: root)

        #expect(selection == [folder])
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

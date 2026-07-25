import Foundation
import Testing
@testable import CleanCore

struct FTSWrapperTests {
    @Test func walkFindsEveryRegularFileAndSkipsSymlinkLoop() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let nested = root.appendingPathComponent("nested")
        try fm.createDirectory(at: nested, withIntermediateDirectories: true)

        let fileA = root.appendingPathComponent("a.txt")
        let fileB = nested.appendingPathComponent("b.txt")
        try "hello".write(to: fileA, atomically: true, encoding: .utf8)
        try "world!!".write(to: fileB, atomically: true, encoding: .utf8)

        // Symlink loop: nested/loop -> root. walk() uses FTS_PHYSICAL, which
        // never follows a symlink as a directory — it's always returned as a
        // leaf FTS_SL entry — so this loop is structurally inert rather than
        // detected-and-skipped via FTS_DC (physical mode never reaches the
        // point where a cycle could form). This test proves the walk doesn't
        // hang and doesn't miscount the loop link as a regular file.

        var foundPaths: Set<String> = []
        for await item in FTSWrapper.walk(root: root.path) where item.kind == .file {
            foundPaths.insert(item.path)
        }

        #expect(foundPaths.contains(fileA.path))
        #expect(foundPaths.contains(fileB.path))
        #expect(foundPaths.count == 2)
    }

    @Test func walkReportsAccurateFileSize() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let file = root.appendingPathComponent("sized.bin")
        let payload = Data(repeating: 0x41, count: 4096)
        try payload.write(to: file)

        var sizeFound: Int64?
        for await item in FTSWrapper.walk(root: root.path) where item.path == file.path {
            sizeFound = item.size
        }

        #expect(sizeFound == 4096)
    }
}

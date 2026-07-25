import Foundation
import Testing
@testable import CleanCore

struct SizeGrouperTests {
    @Test func singletonSizeFilesAreExcludedFromGroups() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        // Two files share size 100 (should be grouped), one file is size 42
        // and unique (must never appear in any group).
        try Data(repeating: 0x41, count: 100).write(to: root.appendingPathComponent("a.bin"))
        try Data(repeating: 0x42, count: 100).write(to: root.appendingPathComponent("b.bin"))
        try Data(repeating: 0x43, count: 42).write(to: root.appendingPathComponent("unique.bin"))

        let groups = await SizeGrouper().group(rootPath: root.path)

        #expect(groups[42] == nil)
        let sharedGroup = try #require(groups[100])
        #expect(Set(sharedGroup.map(\.path)) == Set([
            root.appendingPathComponent("a.bin").path,
            root.appendingPathComponent("b.bin").path
        ]))
    }

    @Test func emptyDirectoryProducesNoGroups() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let groups = await SizeGrouper().group(rootPath: root.path)
        #expect(groups.isEmpty)
    }

    @Test func zeroByteFilesAreExcludedEvenWhenThereAreSeveral() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        // Several empty files (like .gitkeep placeholders) all share size 0
        // and would otherwise form one giant meaningless "duplicate group."
        try Data().write(to: root.appendingPathComponent("a.keep"))
        try Data().write(to: root.appendingPathComponent("b.keep"))
        try Data().write(to: root.appendingPathComponent("c.keep"))

        let groups = await SizeGrouper().group(rootPath: root.path)
        #expect(groups[0] == nil)
        #expect(groups.isEmpty)
    }
}

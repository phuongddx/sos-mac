import Foundation
import Testing
@testable import CleanCore

struct DiskTreeScannerTests {
    @Test func buildTreeProducesCorrectHierarchyAndAggregatedSizes() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let nested = root.appendingPathComponent("nested")
        try fm.createDirectory(at: nested, withIntermediateDirectories: true)

        try Data(repeating: 0x41, count: 100).write(to: root.appendingPathComponent("a.txt"))
        try Data(repeating: 0x42, count: 50).write(to: nested.appendingPathComponent("b.txt"))
        try Data(repeating: 0x43, count: 25).write(to: nested.appendingPathComponent("c.txt"))

        let scanner = DiskTreeScanner(rootPath: root.path)
        let result = await scanner.buildTree()

        // Root is index 0 by construction.
        let rootIndex: Int32 = 0
        #expect(result.tree.nodes[Int(rootIndex)].size == 175)

        let nestedIndex = try #require(
            result.tree.children(of: rootIndex).first { result.tree.pathComponent(of: $0) == "nested" }
        )
        #expect(result.tree.nodes[Int(nestedIndex)].size == 75)

        // scan() (the Scanner conformance) must return the same flat items
        // from the same underlying pass.
        let flatItems = try await scanner.scan()
        let flatPaths = Set(flatItems.map(\.path))
        #expect(flatPaths.contains(root.appendingPathComponent("a.txt").path))
        #expect(flatPaths.contains(nested.appendingPathComponent("b.txt").path))
    }

    @Test func normalizesTrailingSlashInRootPath() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        try "x".write(to: root.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)

        // A trailing slash must not break parent-path matching (deletingLastPathComponent
        // strips it), which would otherwise silently drop every child's subtree.
        let scanner = DiskTreeScanner(rootPath: root.path + "/")
        let result = await scanner.buildTree()

        #expect(result.tree.nodes.count == 2) // root + file.txt
        #expect(result.tree.nodes[0].size == (result.items.first?.size ?? -1))
    }

    @Test func reportsDescendantCountsForDirectories() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let nested = root.appendingPathComponent("nested")
        try fm.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: 10).write(to: root.appendingPathComponent("a.txt"))
        try Data(repeating: 0x42, count: 10).write(to: nested.appendingPathComponent("b.txt"))
        try Data(repeating: 0x43, count: 10).write(to: nested.appendingPathComponent("c.txt"))

        let result = await DiskTreeScanner(rootPath: root.path).buildTree()
        let nestedIndex = try #require(
            result.tree.children(of: 0).first { result.tree.pathComponent(of: $0) == "nested" }
        )

        #expect(result.tree.descendantCount(of: nestedIndex) == 2)
        #expect(result.tree.descendantCount(of: 0) == 4)
    }
}

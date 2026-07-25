import Testing
@testable import CleanCore

struct ArenaTreeTests {
    @Test func directorySizesEqualSumOfLeafSizes() {
        var tree = ArenaTree()
        // root
        //  ├─ a.txt (100)
        //  └─ nested/
        //      ├─ b.txt (50)
        //      └─ c.txt (25)
        let root = tree.addNode(pathComponent: "root", size: 0, kind: .directory, parentIndex: ArenaTree.Node.noIndex)
        tree.addNode(pathComponent: "a.txt", size: 100, kind: .file, parentIndex: root)
        let nested = tree.addNode(pathComponent: "nested", size: 0, kind: .directory, parentIndex: root)
        tree.addNode(pathComponent: "b.txt", size: 50, kind: .file, parentIndex: nested)
        tree.addNode(pathComponent: "c.txt", size: 25, kind: .file, parentIndex: nested)

        tree.recomputeDirectorySizes()

        #expect(tree.nodes[Int(nested)].size == 75)
        #expect(tree.nodes[Int(root)].size == 175)
    }

    @Test func childrenReturnsInsertedNodesRegardlessOfOrder() {
        var tree = ArenaTree()
        let root = tree.addNode(pathComponent: "root", size: 0, kind: .directory, parentIndex: ArenaTree.Node.noIndex)
        let a = tree.addNode(pathComponent: "a", size: 1, kind: .file, parentIndex: root)
        let b = tree.addNode(pathComponent: "b", size: 2, kind: .file, parentIndex: root)

        let childIndices = Set(tree.children(of: root))
        #expect(childIndices == Set([a, b]))
    }

    @Test func pathComponentAndFullPathReconstructCorrectly() {
        var tree = ArenaTree()
        let root = tree.addNode(pathComponent: "Users", size: 0, kind: .directory, parentIndex: ArenaTree.Node.noIndex)
        let lib = tree.addNode(pathComponent: "Library", size: 0, kind: .directory, parentIndex: root)
        let caches = tree.addNode(pathComponent: "Caches", size: 10, kind: .directory, parentIndex: lib)

        #expect(tree.pathComponent(of: caches) == "Caches")
        #expect(tree.fullPath(of: caches) == "Users/Library/Caches")
    }

    @Test func fullPathDoesNotDoubleSlashWhenRootIsLiteralSlash() {
        var tree = ArenaTree()
        // A full-disk scan's root component is "/" itself — naive
        // "/".joined(components) would produce "//Users" instead of "/Users".
        let root = tree.addNode(pathComponent: "/", size: 0, kind: .directory, parentIndex: ArenaTree.Node.noIndex)
        let users = tree.addNode(pathComponent: "Users", size: 0, kind: .directory, parentIndex: root)

        #expect(tree.fullPath(of: users) == "/Users")
    }
}

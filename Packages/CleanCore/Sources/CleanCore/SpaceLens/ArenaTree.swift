import Foundation

/// Nodes stored in a contiguous array with parent/first-child/next-sibling
/// indices — not a class-per-node tree — and leaf path components interned
/// in a single byte buffer instead of one `String` per node. This keeps
/// memory bounded when scanning multi-million-file volumes.
public struct ArenaTree: Sendable {
    public struct Node: Sendable {
        public static let noIndex: Int32 = -1

        let componentStart: Int32
        let componentLength: Int32
        public internal(set) var size: Int64
        public let kind: ScanItemKind
        public let parentIndex: Int32
        var firstChildIndex: Int32 = Node.noIndex
        var nextSiblingIndex: Int32 = Node.noIndex
    }

    public private(set) var nodes: [Node] = []
    private var stringPool: [UInt8] = []

    public init() {}

    /// `pathComponent` is only the leaf name (e.g. "Caches"), never the full
    /// path — full paths are reconstructed on demand by walking the parent
    /// chain (see `fullPath(of:)`), so siblings sharing a long common prefix
    /// never store that prefix more than once.
    @discardableResult
    public mutating func addNode(
        pathComponent: String,
        size: Int64,
        kind: ScanItemKind,
        parentIndex: Int32
    ) -> Int32 {
        let componentBytes = Array(pathComponent.utf8)
        let start = Int32(stringPool.count)
        stringPool.append(contentsOf: componentBytes)

        let newIndex = Int32(nodes.count)
        nodes.append(
            Node(
                componentStart: start,
                componentLength: Int32(componentBytes.count),
                size: size,
                kind: kind,
                parentIndex: parentIndex
            )
        )

        if parentIndex != Node.noIndex {
            let oldFirstChild = nodes[Int(parentIndex)].firstChildIndex
            nodes[Int(newIndex)].nextSiblingIndex = oldFirstChild
            nodes[Int(parentIndex)].firstChildIndex = newIndex
        }

        return newIndex
    }

    public func children(of index: Int32) -> [Int32] {
        var result: [Int32] = []
        var current = nodes[Int(index)].firstChildIndex
        while current != Node.noIndex {
            result.append(current)
            current = nodes[Int(current)].nextSiblingIndex
        }
        return result
    }

    public func pathComponent(of index: Int32) -> String {
        let node = nodes[Int(index)]
        let start = Int(node.componentStart)
        let end = start + Int(node.componentLength)
        return String(decoding: stringPool[start..<end], as: UTF8.self)
    }

    public func fullPath(of index: Int32) -> String {
        var components: [String] = []
        var current: Int32? = index
        while let idx = current, idx != Node.noIndex {
            components.append(pathComponent(of: idx))
            current = nodes[Int(idx)].parentIndex
        }

        let ordered = components.reversed()
        guard var path = ordered.first else { return "" }
        // NSString's appendingPathComponent, not a naive "/".joined(), because
        // a literal "/" root component would otherwise double up to "//Users"
        // under plain string interpolation.
        for component in ordered.dropFirst() {
            path = (path as NSString).appendingPathComponent(component)
        }
        return path
    }

    /// Recomputes every directory's size as the sum of its children's sizes.
    /// A node's parent always has a strictly smaller index than the node
    /// itself (a child can only be added after its parent already exists),
    /// so a single reverse pass visits every child before its parent and
    /// each directory's total is fully accumulated by the time it's reached.
    /// Must run once after all nodes are added — directory sizes are
    /// meaningless mid-build.
    public mutating func recomputeDirectorySizes() {
        guard !nodes.isEmpty else { return }
        for index in stride(from: nodes.count - 1, through: 0, by: -1) {
            let parentIndex = nodes[index].parentIndex
            guard parentIndex != Node.noIndex else { continue }
            nodes[Int(parentIndex)].size += nodes[index].size
        }
    }
}

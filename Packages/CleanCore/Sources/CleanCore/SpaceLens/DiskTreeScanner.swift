import Foundation

/// Builds an `ArenaTree` from a single `FTSWrapper` pass over `rootPath`.
/// Also conforms to `Scanner` (returning the same pass's flat items) so it
/// composes with the rest of CleanCore's scanner-based tooling, but Space
/// Lens itself consumes `buildTree()` for the hierarchical view.
public struct DiskTreeScanner: Scanner {
    public let rootPath: String

    public init(rootPath: String) {
        // Normalizes away things like a trailing slash or redundant "//" —
        // buildTree() matches a child's `deletingLastPathComponent` against
        // this exact string to find its parent node, so any inconsistency
        // here would silently drop that child's whole subtree.
        self.rootPath = (rootPath as NSString).standardizingPath
    }

    public func scan() async throws -> [ScanItem] {
        let result = await buildTree()
        return result.items
    }

    /// `onProgress` reports the running scanned-item count every 2,000 items
    /// — a full home directory can legitimately take a long time (real
    /// disks, iCloud placeholder files, large `~/Library` trees), and
    /// without live feedback a slow-but-working scan is indistinguishable
    /// from a hung one in the UI.
    public func buildTree(onProgress: (@Sendable (ScanProgress) -> Void)? = nil) async -> (tree: ArenaTree, items: [ScanItem]) {
        var arena = ArenaTree()
        var indexByPath: [String: Int32] = [:]
        var items: [ScanItem] = []

        let rootComponent = (rootPath as NSString).lastPathComponent
        let rootIndex = arena.addNode(
            pathComponent: rootComponent.isEmpty ? rootPath : rootComponent,
            size: 0,
            kind: .directory,
            parentIndex: ArenaTree.Node.noIndex
        )
        indexByPath[rootPath] = rootIndex

        for await item in FTSWrapper.walk(root: rootPath) {
            // AsyncStream's `for await` doesn't stop on its own just because
            // the enclosing Task was cancelled — it only stops once this loop
            // itself breaks, which then lets the stream's onTermination fire
            // and cancel FTSWrapper's underlying walk. Without this check, a
            // cancelled Space Lens scan on a slow/spinning drive would keep
            // walking the full tree in the background regardless.
            if Task.isCancelled { break }
            guard item.path != rootPath else { continue }

            let parentPath = (item.path as NSString).deletingLastPathComponent
            guard let parentIndex = indexByPath[parentPath] else { continue }

            let component = (item.path as NSString).lastPathComponent
            // Directories start at 0 and get their real total from
            // recomputeDirectorySizes() below; files carry their true size.
            let size: Int64 = item.kind == .directory ? 0 : item.size
            let nodeIndex = arena.addNode(
                pathComponent: component,
                size: size,
                kind: item.kind,
                parentIndex: parentIndex
            )

            if item.kind == .directory {
                indexByPath[item.path] = nodeIndex
            }
            items.append(item)

            if let onProgress, items.count % 2000 == 0 {
                onProgress(ScanProgress(itemsProcessed: items.count, totalItems: nil, currentPath: nil))
            }
        }

        arena.recomputeDirectorySizes()
        return (arena, items)
    }
}

import Foundation
import Observation
import CoreGraphics
import CleanCore
import TreemapKit

@MainActor
@Observable
final class SpaceLensViewModel {
    enum Phase: Equatable {
        case idle
        case scanning
        case loaded
    }

    enum ViewMode: String, CaseIterable, Hashable {
        case tree = "By Folder"
        case category = "By Type"
    }

    struct DisplayItem: Identifiable {
        let id: Int32
        let label: String
        let size: Int64
        let rect: CGRect
        let isDirectory: Bool
    }

    let rootPath: String
    private(set) var phase: Phase = .idle
    private(set) var errorMessage: String?
    var viewMode: ViewMode = .tree

    private var tree: ArenaTree?
    private var flatItems: [ScanItem] = []
    private var currentRootIndex: Int32 = 0
    private var breadcrumb: [Int32] = []
    private var scanTask: Task<Void, Never>?

    /// Computed once when the scan completes, not per render — aggregating
    /// a realistic whole-home-directory scan (~1M items) measured ~330ms,
    /// and `layoutRects(in:)` is called on every SwiftUI render pass.
    private var categoryTotals: [(FileCategory, Int64)] = []

    private struct LayoutCacheKey: Equatable {
        let rootIndex: Int32
        let viewMode: ViewMode
        let containerSize: CGSize
    }
    private var layoutCacheKey: LayoutCacheKey?
    private var layoutCacheResult: [DisplayItem] = []

    init(rootPath: String = NSHomeDirectory()) {
        self.rootPath = rootPath
    }

    var breadcrumbLabels: [String] {
        guard let tree else { return [] }
        return breadcrumb.map { tree.pathComponent(of: $0) }
    }

    func startScan() {
        scanTask?.cancel()
        scanTask = Task { [weak self] in
            await self?.performScan()
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        if phase == .scanning { phase = .idle }
    }

    private func performScan() async {
        phase = .scanning
        errorMessage = nil

        let scanner = DiskTreeScanner(rootPath: rootPath)
        let result = await scanner.buildTree()
        guard !Task.isCancelled else { return }

        guard !result.tree.nodes.isEmpty else {
            errorMessage = "Couldn't read \(rootPath)"
            phase = .idle
            return
        }

        tree = result.tree
        flatItems = result.items
        currentRootIndex = 0
        breadcrumb = [0]

        let totals = FileTypeAggregator.aggregate(items: result.items)
        categoryTotals = FileCategory.allCases.compactMap { category in
            guard let size = totals[category], size > 0 else { return nil }
            return (category, size)
        }

        layoutCacheKey = nil
        phase = .loaded
    }

    func layoutRects(in containerRect: CGRect) -> [DisplayItem] {
        guard let tree, containerRect.width > 0, containerRect.height > 0 else { return [] }

        let cacheKey = LayoutCacheKey(rootIndex: currentRootIndex, viewMode: viewMode, containerSize: containerRect.size)
        if cacheKey == layoutCacheKey {
            return layoutCacheResult
        }

        let result: [DisplayItem]
        switch viewMode {
        case .tree:
            let childIndices = tree.children(of: currentRootIndex)
            if childIndices.isEmpty {
                result = []
            } else {
                let sizes = childIndices.map { Double(tree.nodes[Int($0)].size) }
                let rects = SquarifiedTreemap.layout(values: sizes, in: containerRect)
                result = zip(childIndices, rects).map { index, rect in
                    let node = tree.nodes[Int(index)]
                    return DisplayItem(
                        id: index,
                        label: tree.pathComponent(of: index),
                        size: node.size,
                        rect: rect,
                        isDirectory: node.kind == .directory
                    )
                }
            }

        case .category:
            if categoryTotals.isEmpty {
                result = []
            } else {
                let sizes = categoryTotals.map { Double($0.1) }
                let rects = SquarifiedTreemap.layout(values: sizes, in: containerRect)
                result = zip(categoryTotals, rects).enumerated().map { offset, pair in
                    let ((category, size), rect) = pair
                    return DisplayItem(
                        id: Int32(-(offset + 1)), // negative synthetic ids never collide with real tree indices
                        label: category.rawValue,
                        size: size,
                        rect: rect,
                        isDirectory: false
                    )
                }
            }
        }

        layoutCacheKey = cacheKey
        layoutCacheResult = result
        return result
    }

    /// Tapping a directory (tree mode only) re-roots the layout at that
    /// subtree; tapping a file or a category swatch is a no-op here — there's
    /// nothing further to drill into.
    func handleTap(on item: DisplayItem) {
        guard viewMode == .tree, item.isDirectory else { return }
        currentRootIndex = item.id
        breadcrumb.append(item.id)
    }

    func zoomOut(to breadcrumbIndex: Int) {
        guard breadcrumb.indices.contains(breadcrumbIndex) else { return }
        breadcrumb = Array(breadcrumb.prefix(breadcrumbIndex + 1))
        currentRootIndex = breadcrumb.last ?? 0
    }
}

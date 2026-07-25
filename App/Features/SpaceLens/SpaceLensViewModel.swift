import AppKit
import CoreGraphics
import Foundation
import Observation
import CleanCore
import TreemapKit

@MainActor
@Observable
final class SpaceLensViewModel {
    enum Phase: Equatable {
        case idle
        case scanning
        case loaded
        case reviewing
        case cleaning
        case done(reclaimedBytes: Int64)
    }

    enum ViewMode: String, CaseIterable, Hashable {
        case tree = "By Folder"
        case category = "By Type"
    }

    struct ScanLocation: Identifiable {
        let url: URL
        let name: String

        var id: URL { url }
    }

    struct DisplayItem: Identifiable {
        let id: Int32
        let label: String
        let path: String?
        let size: Int64
        let rect: CGRect
        let isDirectory: Bool
        let descendantCount: Int
        let lastModified: Date?
    }

    var rootPath: String
    private(set) var phase: Phase = .idle
    private(set) var errorMessage: String?
    private(set) var scannedItemCount = 0
    var viewMode: ViewMode = .tree {
        didSet { selectedItem = nil }
    }
    private(set) var selectedItem: DisplayItem?

    private var tree: ArenaTree?
    private var flatItems: [ScanItem] = []
    private var currentRootIndex: Int32 = 0
    private var breadcrumb: [Int32] = []
    private var scanTask: Task<Void, Never>?
    private let cleaner = DefaultCleaner()
    private let cleanupPolicy = SpaceLensCleanupPolicy()
    private var selectedItemsByPath: [String: ScanItem] = [:]

    private var categoryTotals: [(FileCategory, Int64)] = []

    private struct LayoutCacheKey: Equatable {
        let rootIndex: Int32
        let viewMode: ViewMode
        let containerSize: CGSize
    }
    private var layoutCacheKey: LayoutCacheKey?
    private var layoutCacheResult: [DisplayItem] = []

    init(rootPath: String = NSHomeDirectory()) {
        self.rootPath = (rootPath as NSString).standardizingPath
    }

    var breadcrumbLabels: [String] {
        guard let tree else { return [] }
        return breadcrumb.map { tree.pathComponent(of: $0) }
    }

    var externalVolumes: [ScanLocation] {
        FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeNameKey, .volumeIsRemovableKey],
            options: [.skipHiddenVolumes]
        )?
        .compactMap { url in
            let values = try? url.resourceValues(forKeys: [.volumeNameKey, .volumeIsRemovableKey])
            guard values?.volumeIsRemovable == true else { return nil }
            return ScanLocation(url: url, name: values?.volumeName ?? url.lastPathComponent)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } ?? []
    }

    var selectedPaths: Set<String> { Set(selectedItemsByPath.keys) }

    var cleanupItems: [ScanItem] {
        cleanupPolicy.normalizedSelection(from: Array(selectedItemsByPath.values), scanRootPath: rootPath)
    }

    var totalSelectedBytes: Int64 {
        cleanupItems.reduce(0) { $0 + $1.size }
    }

    var selectedItemEligibility: SpaceLensCleanupEligibility? {
        guard let selectedItem, let item = scanItem(for: selectedItem) else { return nil }
        return cleanupPolicy.eligibility(for: item, scanRootPath: rootPath)
    }

    var isSelectedItemInCleanup: Bool {
        guard let path = selectedItem?.path else { return false }
        return selectedItemsByPath[path] != nil
    }

    func selectHomeFolder() {
        selectLocation(at: NSHomeDirectory())
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose a folder to map"
        panel.prompt = "Scan Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        selectLocation(at: url.path)
    }

    func selectVolume(at url: URL) {
        selectLocation(at: url.path)
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

    func handleTap(on item: DisplayItem) {
        selectedItem = item.path == nil ? nil : item
    }

    func clearSelectedItem() {
        selectedItem = nil
    }

    func openSelectedFolder() {
        guard let item = selectedItem, item.isDirectory else { return }
        currentRootIndex = item.id
        breadcrumb.append(item.id)
        selectedItem = nil
    }

    func zoomOut(to breadcrumbIndex: Int) {
        guard breadcrumb.indices.contains(breadcrumbIndex) else { return }
        breadcrumb = Array(breadcrumb.prefix(breadcrumbIndex + 1))
        currentRootIndex = breadcrumb.last ?? 0
        selectedItem = nil
    }

    func toggleSelectedItemCleanup() {
        guard let selectedItem, let item = scanItem(for: selectedItem),
              case .eligible = cleanupPolicy.eligibility(for: item, scanRootPath: rootPath)
        else { return }

        if selectedItemsByPath[item.path] == nil {
            selectedItemsByPath[item.path] = item
        } else {
            selectedItemsByPath[item.path] = nil
        }
    }

    func beginCleanupReview() {
        guard !cleanupItems.isEmpty else { return }
        phase = .reviewing
    }

    func cancelCleanupReview() {
        guard phase == .reviewing else { return }
        phase = .loaded
    }

    func cleanSelectedItems() async {
        let items = cleanupItems
        guard !items.isEmpty else { return }
        phase = .cleaning

        do {
            let result = try await cleaner.clean(items)
            for item in result.succeeded {
                selectedItemsByPath[item.path] = nil
            }
            if let failed = result.failed.first {
                errorMessage = "\(result.failed.count) item\(result.failed.count == 1 ? "" : "s") couldn't be moved to Trash: \(failed.reason)"
            }
            phase = .done(reclaimedBytes: result.reclaimedBytes)
        } catch {
            errorMessage = error.localizedDescription
            phase = .loaded
        }
    }

    func scanAgain() {
        resetScanState()
        startScan()
    }

    func layoutRects(in containerRect: CGRect) -> [DisplayItem] {
        guard let tree, containerRect.width > 0, containerRect.height > 0 else { return [] }

        let cacheKey = LayoutCacheKey(rootIndex: currentRootIndex, viewMode: viewMode, containerSize: containerRect.size)
        if cacheKey == layoutCacheKey { return layoutCacheResult }

        let result: [DisplayItem]
        switch viewMode {
        case .tree:
            let childIndices = tree.children(of: currentRootIndex)
            let sizes = childIndices.map { Double(tree.nodes[Int($0)].size) }
            let rects = SquarifiedTreemap.layout(values: sizes, in: containerRect)
            result = zip(childIndices, rects).map { index, rect in
                let node = tree.nodes[Int(index)]
                let path = resolvedPath(of: index, in: tree)
                return DisplayItem(
                    id: index,
                    label: tree.pathComponent(of: index),
                    path: path,
                    size: node.size,
                    rect: rect,
                    isDirectory: node.kind == .directory,
                    descendantCount: node.kind == .directory ? tree.descendantCount(of: index) : 0,
                    lastModified: flatItems.first(where: { $0.path == path })?.lastModified
                )
            }

        case .category:
            let sizes = categoryTotals.map { Double($0.1) }
            let rects = SquarifiedTreemap.layout(values: sizes, in: containerRect)
            result = zip(categoryTotals, rects).enumerated().map { offset, pair in
                let ((category, size), rect) = pair
                return DisplayItem(
                    id: Int32(-(offset + 1)),
                    label: category.rawValue,
                    path: nil,
                    size: size,
                    rect: rect,
                    isDirectory: false,
                    descendantCount: 0,
                    lastModified: nil
                )
            }
        }

        layoutCacheKey = cacheKey
        layoutCacheResult = result
        return result
    }

    private func selectLocation(at path: String) {
        rootPath = (path as NSString).standardizingPath
        resetScanState()
        startScan()
    }

    private func resetScanState() {
        scanTask?.cancel()
        tree = nil
        flatItems = []
        categoryTotals = []
        currentRootIndex = 0
        breadcrumb = []
        selectedItem = nil
        selectedItemsByPath = [:]
        layoutCacheKey = nil
        layoutCacheResult = []
        errorMessage = nil
        scannedItemCount = 0
        phase = .idle
    }

    private func performScan() async {
        phase = .scanning
        errorMessage = nil
        scannedItemCount = 0

        let scanner = DiskTreeScanner(rootPath: rootPath)
        let result = await scanner.buildTree(onProgress: { [weak self] count in
            Task { @MainActor in self?.scannedItemCount = count }
        })
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
            totals[category].map { (category, $0) }.flatMap { $0.1 > 0 ? $0 : nil }
        }
        layoutCacheKey = nil
        phase = .loaded
    }

    private func scanItem(for displayItem: DisplayItem) -> ScanItem? {
        guard let path = displayItem.path else { return nil }
        return ScanItem(
            path: path,
            size: displayItem.size,
            kind: displayItem.isDirectory ? .directory : .file,
            lastModified: displayItem.lastModified
        )
    }

    private func resolvedPath(of index: Int32, in tree: ArenaTree) -> String {
        guard index != 0 else { return rootPath }
        var components: [String] = []
        var current = index
        while current != 0 {
            components.append(tree.pathComponent(of: current))
            current = tree.nodes[Int(current)].parentIndex
        }
        return components.reversed().reduce(rootPath) { partial, component in
            (partial as NSString).appendingPathComponent(component)
        }
    }
}

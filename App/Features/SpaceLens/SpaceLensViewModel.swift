import AppKit
import Foundation
import Observation
import CleanCore
import TreemapKit

/// Space Lens — plan PR 8 of the UI migration (spec §5.5).
///
/// The file follows the pattern set by the reference screen (Junk & Cache, PR 5):
///
/// 1. **State table** — spec §5.5's lifecycle → `Phase` → what-is-shown table, restated
///    here so the code and the spec can be checked against each other.
/// 2. **`Phase`** — one enum carrying the whole screen state; no screen-state booleans.
/// 3. **`lifecycle`** — a pure, unit-tested `Phase → LifecycleState` mapping that the
///    shared `ModuleScreen` frame renders from.
/// 4. **Fixture states** — `loadFixture(_:)` for each lifecycle state, Debug only
///    (`UITestFixtures.spaceLensRoot` is the fictional tree; nothing real is read).
/// 5. **Snapshots** — the eight states × By Folder / By Type, dark and light.
///
/// | Lifecycle | `Phase` | What is shown |
/// |---|---|---|
/// | `start` | `idle` | "See what fills your disk" · source list: Home, Choose Folder…, external volumes · **Scan** |
/// | `scanning` | `scanning` | "Mapping «folder»…" · "The total isn't known until the scan ends, so there's no percentage." · "Scanned N items…" · **Stop** |
/// | `results` | `results` (items found) | Breadcrumb · segment By Folder / By Type · treemap · legend · inspector · review bar |
/// | `empty` | `results` (empty folder) | "This folder is empty — «path» has no files in it." · Choose Folder… |
/// | `review` | `review` | The **cleanup list** sheet with checkboxes and a Total row (§4.8) |
/// | `cleaning` | `cleaning(selectedCount:)` | "Moving n of N items to the Trash…" + the current path (N5) |
/// | `done` | `done(movedBytes:movedCount:failedCount:)` | stats · **Back to Map** (N7) · Open Trash · Scan Again |
/// | `error` | `failed(message:)` | "Couldn't read «folder»" + the reason · Try Again · Choose Another Folder |
///
/// Safety: nothing is pre-selected (§5.5); the cart only ever holds policy-eligible,
/// non-protected paths; every removal goes through `ProgressiveCleaner` → the one
/// `Cleaner.clean(_:)` extension method, per item, behind the cleanup-list confirmation.
@MainActor
@Observable
final class SpaceLensViewModel {

    // MARK: - Phase (the screen's whole state)

    /// The state machine contract the shared frame maps from (spec §5.5, normative).
    enum Phase: Equatable {
        case idle
        case scanning
        case results
        case review
        case cleaning(selectedCount: Int)
        case done(movedBytes: Int64, movedCount: Int, failedCount: Int)
        case failed(message: String)
    }

    /// A snapshot of the per-item moving loop (spec §6.5), `nil` outside `cleaning`.
    struct CleaningProgress: Equatable, Sendable {
        let attemptedCount: Int
        let totalCount: Int
        let currentPath: String?
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

    /// One rectangle of the current level's treemap. Folders and files come from the
    /// scan tree; By Type cells aggregate by category; the "N smaller items" cell
    /// merges everything below the spec's 0.4 % draw threshold (§5.5).
    struct DisplayItem: Identifiable, Equatable {
        let id: Int32
        let label: String
        let path: String?
        let size: Int64
        var rect: CGRect
        let isDirectory: Bool
        let descendantCount: Int
        let lastModified: Date?
        /// Position in the level's size-descending order — the treemap1…8 ramp index
        /// (spec §5.5). By Type cells carry their `FileCategory` order instead, so a
        /// type keeps one colour across scans and the legend matches the map.
        var rampIndex: Int = 0
        /// The merged "N smaller items" cell — no path, never drillable, never cleanable.
        var isSmallerBucket: Bool = false
        /// A By Type aggregate — no path, so never cleanable either.
        var isCategory: Bool = false
    }

    /// Spec §5.5: items below 0.4 % of the scanned total merge into one cell.
    static let smallerItemsFraction: Double = 0.004
    /// The merged cell's id — far outside the category id range (−1…−8) and the tree's
    /// non-negative ids, so it can never collide.
    static let smallerBucketID: Int32 = -1_000_001

    // MARK: - Stored state

    var rootPath: String
    private(set) var phase: Phase = .idle
    let progressTracker = ScanProgressTracker()
    var viewMode: ViewMode = .tree {
        didSet { selectedItem = nil }
    }
    private(set) var selectedItem: DisplayItem?
    /// Per-item failures of the last clean, surfaced on Done (F4) — never dropped.
    private(set) var lastFailedItems: [CleanResult.FailedItem] = []
    /// Real per-item moving progress (N5, §6.5); `nil` outside `cleaning`.
    private(set) var cleaningProgress: CleaningProgress?

    private var tree: ArenaTree?
    private var flatItems: [ScanItem] = []
    /// Top-most paths already moved to the Trash this session. The tree is immutable
    /// here (CleanCore/TreemapKit are read-only), so every level rebuild filters it.
    private var removedRoots: [String] = []
    private var lastModifiedByPath: [String: Date] = [:]
    private var currentRootIndex: Int32 = 0
    private var breadcrumb: [Int32] = []
    private var scanTask: Task<Void, Never>?
    private let cleaner = DefaultCleaner()
    private let progressiveCleaner = ProgressiveCleaner()
    private let cleanupPolicy = SpaceLensCleanupPolicy()
    private var selectedItemsByPath: [String: ScanItem] = [:]
    private var categoryTotals: [(FileCategory, Int64)] = []

    #if DEBUG
    /// Fixture-only flag: real external volumes never appear over fixture data.
    private var showsFixtureVolumesOnly = false
    #endif

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

    // MARK: - Lifecycle mapping (pattern step 3)

    /// The pure mapping the shared frame renders from. `results` over an empty folder
    /// is `empty` (F3) — a folder the engine could not open at all is `.failed`, so it
    /// can never look like "nothing found".
    var lifecycle: LifecycleState {
        switch phase {
        case .idle: .start
        case .scanning: .scanning
        case .results: flatItems.isEmpty ? .empty : .results
        case .review: .review
        case .cleaning: .cleaning
        case .done: .done
        case .failed: .error
        }
    }

    /// True while files are moving — the re-entrancy guard's input.
    var isCleaning: Bool {
        if case .cleaning = phase { return true }
        return false
    }

    // MARK: - Derived state (real values only)

    var breadcrumbLabels: [String] {
        guard let tree else { return [] }
        return breadcrumb.map { tree.pathComponent(of: $0) }
    }

    /// The count the toolbar subtitle shows: "Scanned N items in «root»" (§6.4).
    /// Items the session already moved are gone from it, so Back to Map stays true.
    var scannedItemCount: Int { flatItems.count }

    /// The scanned root's folder name, as the copy quotes it.
    var rootName: String { (rootPath as NSString).lastPathComponent }

    var isHomeRoot: Bool {
        rootPath == (NSHomeDirectory() as NSString).standardizingPath
    }

    /// The type totals behind the By Type map and its legend, size-descending.
    var categoryLegend: [(category: FileCategory, bytes: Int64)] {
        categoryTotals.sorted { $0.1 > $1.1 }
    }

    var externalVolumes: [ScanLocation] {
        #if DEBUG
        if showsFixtureVolumesOnly { return [] }
        #endif
        return FileManager.default.mountedVolumeURLs(
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

    /// The cart: policy-normalized so it holds each removable subtree once — only the
    /// top-most selected item of a chain (the engine's `normalizedSelection`).
    var cleanupItems: [ScanItem] {
        cleanupPolicy.normalizedSelection(from: Array(selectedItemsByPath.values), scanRootPath: rootPath)
    }

    var totalSelectedBytes: Int64 {
        cleanupItems.reduce(0) { $0 + $1.size }
    }

    var selectedItemEligibility: SpaceLensCleanupEligibility? {
        #if DEBUG
        // Fixture data never touches the real file system — the policy's writable
        // check would read it, so fixture selections present as eligible (the
        // prototype's interactive results state).
        if showsFixtureVolumesOnly { return .eligible }
        #endif
        guard let selectedItem, let item = scanItem(for: selectedItem) else { return nil }
        return cleanupPolicy.eligibility(for: item, scanRootPath: rootPath)
    }

    var isSelectedItemInCleanup: Bool {
        guard let path = selectedItem?.path else { return false }
        return selectedItemsByPath[path] != nil
    }

    /// The current level's total, for the inspector's fallback detail.
    var levelTotalBytes: Int64 {
        switch viewMode {
        case .tree:
            guard let tree else { return 0 }
            return tree.nodes[Int(currentRootIndex)].size
        case .category:
            return categoryTotals.reduce(0) { $0 + $1.1 }
        }
    }

    // MARK: - Source selection (the start screen)

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

    // MARK: - Scan

    /// `false` when a scan or clean is already running (PR 3 re-entrancy guard).
    @discardableResult
    func startScan() -> Bool {
        guard phase != .scanning, !isCleaning else { return false }
        scanTask?.cancel()
        scanTask = Task { [weak self] in
            await self?.performScan()
        }
        return true
    }

    /// F2: Stop returns to `start` and discards partial results — including the
    /// previous scan's, which would otherwise look like this scan's outcome.
    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        guard phase == .scanning else { return }
        resetScanState()
        phase = .idle
    }

    func scanAgain() {
        resetScanState()
        startScan()
    }

    // MARK: - Map interaction

    func handleTap(on item: DisplayItem) {
        selectedItem = item
    }

    func clearSelectedItem() {
        selectedItem = nil
    }

    /// Click selects (§5.5); double-click drills into a folder.
    func drillIn(on item: DisplayItem) {
        guard item.isDirectory, !item.isSmallerBucket, item.path != nil else { return }
        currentRootIndex = item.id
        breadcrumb.append(item.id)
        selectedItem = nil
    }

    func drillIntoSelectedItem() {
        guard let selectedItem else { return }
        drillIn(on: selectedItem)
    }

    func zoomOut(to breadcrumbIndex: Int) {
        guard breadcrumb.indices.contains(breadcrumbIndex) else { return }
        breadcrumb = Array(breadcrumb.prefix(breadcrumbIndex + 1))
        currentRootIndex = breadcrumb.last ?? 0
        selectedItem = nil
        layoutCacheKey = nil
    }

    // MARK: - Cleanup cart (nothing is pre-selected; §5.5)

    /// The top-level Library folder of the scanned root (§5.5): it holds settings and
    /// data apps need, so the inspector offers no cleanup action for it and the cart
    /// refuses it. Its *contents* are not covered — Junk & Cache and Uninstaller own
    /// the files inside Library.
    static func isProtectedLocation(_ path: String, scanRootPath: String) -> Bool {
        path == (scanRootPath as NSString).appendingPathComponent("Library")
    }

    func toggleSelectedItemCleanup() {
        guard let selectedItem,
              let item = scanItem(for: selectedItem),
              !Self.isProtectedLocation(item.path, scanRootPath: rootPath),
              case .eligible = cleanupPolicy.eligibility(for: item, scanRootPath: rootPath)
        else { return }

        if selectedItemsByPath[item.path] == nil {
            selectedItemsByPath[item.path] = item
        } else {
            selectedItemsByPath[item.path] = nil
        }
    }

    // MARK: - Review and confirmation (S1: nothing moves without one)

    func beginCleanupReview() {
        guard phase == .results, !cleanupItems.isEmpty else { return }
        phase = .review
    }

    func cancelCleanupReview() {
        guard phase == .review else { return }
        phase = .results
    }

    /// The cleanup-list confirmation (§4.8, CF-3): the title's count and size are the
    /// cart's own numbers, computed once here. The checkboxes live in `ConfirmSheet`'s
    /// cleanup-list variant; what the user leaves checked is what moves.
    func cleanupConfirmation() -> ConfirmSheet.Model {
        let items = cleanupItems
        return ConfirmSheet.Model(
            variant: .cleanupList,
            count: items.count,
            sizeText: ConfirmItemList.sizeText(for: items.reduce(0) { $0 + $1.size }),
            items: items.map { item in
                ConfirmItem(id: item.path,
                            name: (item.path as NSString).lastPathComponent,
                            path: item.path,
                            size: item.size)
            },
            hue: Theme.Hue.spacelens,
            confirm: { [weak self] selection in
                self?.beginClean(checkedIDs: selection.itemIDs)
            },
            cancel: { })
    }

    private func beginClean(checkedIDs: Set<String>) {
        Task { [weak self] in
            await self?.clean(checkedIDs: checkedIDs)
        }
    }

    // MARK: - Clean (§6.5: one `Cleaner.clean([item])` per item, real progress)

    /// Moves the checked cart items. Re-entrant calls are refused while a clean is in
    /// flight. Failures are counted and surfaced on Done (F4) — never folded into the
    /// moved figure, and the copy never says "reclaimed".
    @discardableResult
    func clean(checkedIDs: Set<String>) async -> Bool {
        guard !isCleaning else { return false }
        let cartPaths = Set(cleanupItems.map(\.path))
        let toClean = cleanupItems.filter { checkedIDs.contains($0.path) && cartPaths.contains($0.path) }
        guard !toClean.isEmpty else { return false }

        phase = .cleaning(selectedCount: toClean.count)
        cleaningProgress = CleaningProgress(attemptedCount: 0, totalCount: toClean.count, currentPath: nil)
        lastFailedItems = []

        let result = await progressiveCleaner.clean(toClean, using: cleaner) { [weak self] index, item in
            self?.cleaningProgress = CleaningProgress(attemptedCount: index + 1,
                                                       totalCount: toClean.count,
                                                       currentPath: item.path)
        }

        let succeededPaths = Set(result.succeeded.map(\.path))
        selectedItemsByPath = selectedItemsByPath.filter { !succeededPaths.contains($0.key) }
        applyRemovals(succeededPaths)
        cleaningProgress = nil
        lastFailedItems = result.failed
        phase = .done(movedBytes: result.reclaimedBytes,
                      movedCount: result.succeeded.count,
                      failedCount: result.failed.count)
        return true
    }

    /// N7: Back to Map — the map now shows what is really still on disk.
    func backToMap() {
        guard case .done = phase else { return }
        phase = .results
    }

    // MARK: - Layout (the treemap's level entries)

    /// The current level's cells with their layout rects, cached per (root, mode, size).
    func layoutRects(in containerRect: CGRect) -> [DisplayItem] {
        guard tree != nil, containerRect.width > 0, containerRect.height > 0 else { return [] }

        let cacheKey = LayoutCacheKey(rootIndex: currentRootIndex, viewMode: viewMode, containerSize: containerRect.size)
        if cacheKey == layoutCacheKey { return layoutCacheResult }

        var entries = levelEntries()
        if viewMode == .tree {
            entries = Self.mergingSmallerItems(entries)
        }
        let rects = SquarifiedTreemap.layout(values: entries.map { Double($0.size) }, in: containerRect)
        let result = zip(entries, rects).map { entry, rect -> DisplayItem in
            var item = entry
            item.rect = rect
            return item
        }

        layoutCacheKey = cacheKey
        layoutCacheResult = result
        return result
    }

    /// Pure merge (pattern step 3's testable core): everything below 0.4 % of the
    /// level total becomes one "N smaller items" cell carrying the real count and
    /// size (§5.5). The result stays size-descending.
    static func mergingSmallerItems(_ entries: [DisplayItem]) -> [DisplayItem] {
        let total = entries.reduce(Int64(0)) { $0 + $1.size }
        guard total > 0 else { return entries }

        let big = entries.filter { Double($0.size) / Double(total) >= smallerItemsFraction }
        let small = entries.filter { Double($0.size) / Double(total) < smallerItemsFraction }
        guard !small.isEmpty else { return entries }

        let bucket = DisplayItem(
            id: smallerBucketID,
            label: "\(small.count) smaller item\(small.count == 1 ? "" : "s")",
            path: nil,
            size: small.reduce(0) { $0 + $1.size },
            rect: .zero,
            isDirectory: false,
            descendantCount: 0,
            lastModified: nil,
            isSmallerBucket: true)
        let merged = (big + [bucket]).sorted { $0.size > $1.size }
        return merged.enumerated().map { index, item in
            var updated = item
            updated.rampIndex = index
            return updated
        }
    }

    private func levelEntries() -> [DisplayItem] {
        switch viewMode {
        case .tree:
            guard let tree else { return [] }
            return tree.children(of: currentRootIndex)
                .map { index -> (path: String, item: DisplayItem) in
                    let node = tree.nodes[Int(index)]
                    let path = resolvedPath(of: index, in: tree)
                    let item = DisplayItem(
                        id: index,
                        label: tree.pathComponent(of: index),
                        path: path,
                        size: node.size,
                        rect: .zero,
                        isDirectory: node.kind == .directory,
                        descendantCount: node.kind == .directory ? tree.descendantCount(of: index) : 0,
                        lastModified: lastModifiedByPath[path])
                    return (path, item)
                }
                // Paths moved this session are gone from the map (Back to Map stays true).
                .filter { !isRemoved($0.path) }
                .map(\.item)
                .sorted { $0.size > $1.size }
                .enumerated()
                .map { index, item -> DisplayItem in
                    var updated = item
                    updated.rampIndex = index
                    return updated
                }

        case .category:
            return categoryLegend.enumerated().map { offset, pair -> DisplayItem in
                DisplayItem(
                    id: Int32(-(offset + 1)),
                    label: pair.category.rawValue,
                    path: nil,
                    size: pair.bytes,
                    rect: .zero,
                    isDirectory: false,
                    descendantCount: 0,
                    lastModified: nil,
                    rampIndex: FileCategory.allCases.firstIndex(of: pair.category) ?? offset,
                    isCategory: true)
            }
        }
    }

    // MARK: - Session removals (Back to Map stays honest)

    /// Drops moved paths from the scan state: the flat list, the type totals, the
    /// modified-date index and the layout cache. Level entries filter by `removedRoots`
    /// on rebuild, so a moved folder vanishes from the map without tree surgery.
    private func applyRemovals(_ paths: Set<String>) {
        guard !paths.isEmpty else { return }
        removedRoots.append(contentsOf: paths.map { ($0 as NSString).standardizingPath })
        flatItems.removeAll { isRemoved($0.path) }
        categoryTotals = Self.categoryTotals(from: flatItems)
        lastModifiedByPath = lastModifiedByPath.filter { !isRemoved($0.key) }
        if let selected = selectedItem, let path = selected.path, isRemoved(path) {
            self.selectedItem = nil
        }
        layoutCacheKey = nil
    }

    private func isRemoved(_ path: String) -> Bool {
        guard !removedRoots.isEmpty else { return false }
        let standardized = (path as NSString).standardizingPath
        return removedRoots.contains { standardized == $0 || standardized.hasPrefix($0 + "/") }
    }

    private static func categoryTotals(from items: [ScanItem]) -> [(FileCategory, Int64)] {
        let totals = FileTypeAggregator.aggregate(items: items)
        return FileCategory.allCases.compactMap { category in
            guard let total = totals[category], total > 0 else { return nil }
            return (category, total)
        }
    }

    // MARK: - Private plumbing

    private func selectLocation(at path: String) {
        rootPath = (path as NSString).standardizingPath
        resetScanState()
        startScan()
    }

    private func resetScanState() {
        scanTask?.cancel()
        tree = nil
        flatItems = []
        removedRoots = []
        lastModifiedByPath = [:]
        categoryTotals = []
        currentRootIndex = 0
        breadcrumb = []
        selectedItem = nil
        selectedItemsByPath = [:]
        layoutCacheKey = nil
        layoutCacheResult = []
        lastFailedItems = []
        cleaningProgress = nil
        progressTracker.reset()
        phase = .idle
    }

    private func performScan() async {
        phase = .scanning
        lastFailedItems = []
        let generation = progressTracker.start()

        // F5: the only scan failure the engine can really produce on a single root is
        // "could not open it" — the walker skips whatever else it cannot read, so an
        // unreadable root is told apart from a genuinely empty folder before scanning.
        guard FileManager.default.isReadableFile(atPath: rootPath) else {
            guard !Task.isCancelled else { return }
            phase = .failed(message: "SOS Mac couldn’t open this folder. Check that it exists and that you have permission to read it.")
            return
        }

        let scanner = DiskTreeScanner(rootPath: rootPath)
        let result = await scanner.buildTree(onProgress: { [weak self] progress in
            Task { @MainActor in self?.progressTracker.record(progress, generation: generation) }
        })
        guard !Task.isCancelled else { return }

        tree = result.tree
        flatItems = result.items
        removedRoots = []
        var modifiedDates: [String: Date] = [:]
        for item in result.items {
            if let modified = item.lastModified, modifiedDates[item.path] == nil {
                modifiedDates[item.path] = modified
            }
        }
        lastModifiedByPath = modifiedDates
        currentRootIndex = 0
        breadcrumb = [0]
        categoryTotals = Self.categoryTotals(from: result.items)
        selectedItem = nil
        selectedItemsByPath = [:]
        layoutCacheKey = nil
        // An empty folder lands here too: `lifecycle` maps zero items to `empty` (F3).
        phase = .results
    }

    private func scanItem(for displayItem: DisplayItem) -> ScanItem? {
        guard let path = displayItem.path, !displayItem.isSmallerBucket, !displayItem.isCategory else { return nil }
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

// MARK: - Fixtures (pattern step 4; Debug builds only)

#if DEBUG
extension SpaceLensViewModel {
    /// Launch-hook half of the fixture convention: applies the state named by
    /// `SOSMAC_UITEST_SCREEN`/`SOSMAC_UITEST_STATE` when fixtures are on, and the
    /// snapshot script's `SOSMAC_UITEST_VIEW=type` switches the map to By Type.
    func loadFixtureFromLaunchHooks() {
        let hooks = UITestHooks.current
        guard hooks.fixtures, hooks.destination == .spaceLens,
              let raw = hooks.state, let state = LifecycleState(rawValue: raw) else { return }
        loadFixture(state)
        if ProcessInfo.processInfo.environment["SOSMAC_UITEST_VIEW"] == "type" {
            viewMode = .category
        }
    }

    /// Loads one of the eight lifecycle states from the fictional sample tree
    /// (`UITestFixtures.spaceLensRoot`, paths under `/Users/sample`). Never reads the
    /// real file system, and suppresses the real external-volume list in `start`.
    func loadFixture(_ state: LifecycleState) {
        switch state {
        case .start:
            resetScanState()
            rootPath = UITestFixtures.home
            showsFixtureVolumesOnly = true
            phase = .idle

        case .scanning:
            applyFixtureTree()
            phase = .scanning
            let generation = progressTracker.start()
            progressTracker.record(ScanProgress(itemsProcessed: 84_219, totalItems: nil),
                                   generation: generation)

        case .results:
            applyFixtureTree()
            // The prototype's results state renders with one selected cell, so the
            // inspector detail and the selection ring are visible in the snapshot.
            // A root-level cell — "Old Installers" lives one level down.
            selectFixtureItem(named: "Downloads")

        case .empty:
            applyFixtureTree(emptyFolder: true)
            phase = .results

        case .review:
            applyFixtureTree()
            addFixtureCart()
            phase = .review

        case .cleaning:
            applyFixtureTree()
            addFixtureCart()
            phase = .cleaning(selectedCount: selectedItemsByPath.count)
            cleaningProgress = CleaningProgress(
                attemptedCount: 1,
                totalCount: selectedItemsByPath.count,
                currentPath: selectedItemsByPath.keys.sorted().first)

        case .done:
            applyFixtureTree()
            // As if the cart had just been confirmed: real cart figures on the card.
            addFixtureCart()
            let moved = Array(selectedItemsByPath.values)
            selectedItemsByPath = [:]
            phase = .done(movedBytes: moved.reduce(0) { $0 + $1.size },
                          movedCount: moved.count,
                          failedCount: 0)

        case .error:
            resetScanState()
            rootPath = UITestFixtures.home
            showsFixtureVolumesOnly = true
            phase = .failed(message: "SOS Mac couldn’t open this folder. Check that it exists and that you have permission to read it.")
        }
    }

    private func applyFixtureTree(emptyFolder: Bool = false) {
        resetScanState()
        rootPath = UITestFixtures.home
        showsFixtureVolumesOnly = true

        var tree = ArenaTree()
        var items: [ScanItem] = []
        let rootName = (UITestFixtures.home as NSString).lastPathComponent
        // The root's total: its children's declared bytes (the fallback inspector and
        // the breadcrumb bar quote it; the prototype's own "~" total).
        let rootBytes = UITestFixtures.spaceLensRoot.children.reduce(Int64(0)) { $0 + $1.bytes }
        let rootIndex = tree.addNode(pathComponent: rootName, size: rootBytes, kind: .directory,
                                     parentIndex: ArenaTree.Node.noIndex)

        func add(_ node: UITestFixtures.LensNode, parent: Int32) {
            let kind: ScanItemKind = node.isDirectory ? .directory : .file
            // The prototype's own numbers, verbatim: directories carry their declared
            // total (the prototype's LENS sizes do not sum exactly either — it is
            // fictional snapshot data). No `recomputeDirectorySizes` here: the real
            // scanner's walk covers that path, and several fixture leaves (Library,
            // Documents…) have no children to sum.
            let index = tree.addNode(pathComponent: node.name,
                                     size: node.bytes,
                                     kind: kind,
                                     parentIndex: parent)
            items.append(ScanItem(path: node.path, size: node.bytes, kind: kind))
            for child in node.children {
                add(child, parent: index)
            }
        }

        if !emptyFolder {
            for child in UITestFixtures.spaceLensRoot.children {
                add(child, parent: rootIndex)
            }
        }

        self.tree = tree
        flatItems = items
        currentRootIndex = rootIndex
        breadcrumb = [rootIndex]
        categoryTotals = Self.categoryTotals(from: items)
        selectedItem = nil
        selectedItemsByPath = [:]
        layoutCacheKey = nil
        phase = .results
    }

    private func selectFixtureItem(named name: String) {
        guard let items = layoutRects(in: CGRect(x: 0, y: 0, width: 1000, height: 600)).first(where: { $0.label == name }) else { return }
        selectedItem = items
    }

    /// The fixture cart: two top-most Downloads entries, as if the user had added
    /// them. `normalizedSelection` keeps descendant-free carts, so only top-most
    /// fixture paths belong here.
    private func addFixtureCart() {
        let downloads = UITestFixtures.spaceLensRoot.children.first { $0.name == "Downloads" }
        for node in downloads?.children ?? [] where ["Old Installers", "raw-footage-2026-09.zip"].contains(node.name) {
            selectedItemsByPath[node.path] = ScanItem(
                path: node.path,
                size: node.bytes,
                kind: node.isDirectory ? .directory : .file)
        }
    }
}
#endif

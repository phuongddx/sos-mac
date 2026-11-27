import Foundation
import Testing
import CleanCore
@testable import SOSMac

/// Space Lens view-model tests (plan PR 8). Cover the plan's list — nothing
/// pre-selected, the cart keeps only top-most items, the smaller-items merge (count
/// and size), selection never includes an ineligible path, the phase mapping — plus
/// the confirmation's CF-3 numbers, the review-cancel path (§5.5: dismissing the
/// review sheet exits review), the real hermetic clean (the one trash-routed
/// path), failure accounting on Done, and the re-entrancy guards. Real scans run over
/// unique temp trees; nothing outside those trees is ever touched.
@Suite("SpaceLensViewModel")
@MainActor
struct SpaceLensViewModelTests {

    // MARK: - Fixtures

    private let fileManager = FileManager.default

    /// The scan root the way the view model stores it (symlinks resolved, as
    /// `NSString.standardizingPath` does for `temporaryDirectory`'s /var path).
    private func standardPath(_ url: URL) -> String {
        (url.path as NSString).standardizingPath
    }

    /// A hermetic temp tree with a shape that exercises everything:
    /// `big.dat` (100 000 — always a cell), `Nested/` (30 000, two files), and three
    /// small files (600 total, each < 0.4 % of the level) for the smaller-items merge.
    private func makeTree() throws -> URL {
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("spacelens-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        func makeFile(_ name: String, in directory: URL, bytes: Int) throws {
            try Data(repeating: 0x61, count: bytes)
                .write(to: directory.appendingPathComponent(name))
        }
        try makeFile("big.dat", in: root, bytes: 100_000)
        let nested = root.appendingPathComponent("Nested", isDirectory: true)
        try fileManager.createDirectory(at: nested, withIntermediateDirectories: true)
        try makeFile("nested-0.dat", in: nested, bytes: 20_000)
        try makeFile("nested-1.dat", in: nested, bytes: 10_000)
        try makeFile("small-0.dat", in: root, bytes: 300)
        try makeFile("small-1.dat", in: root, bytes: 200)
        try makeFile("small-2.dat", in: root, bytes: 100)
        return root
    }

    private func makeViewModel(root: URL) -> SpaceLensViewModel {
        SpaceLensViewModel(rootPath: root.path)
    }

    private func wait<T: Equatable>(
        until expected: T,
        _ value: () -> T,
        timeout: TimeInterval = 5
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if value() == expected { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return value() == expected
    }

    private func waitForResults(_ viewModel: SpaceLensViewModel) async -> Bool {
        await wait(until: SpaceLensViewModel.Phase.results) { viewModel.phase }
    }

    private func scanTree() async throws -> (viewModel: SpaceLensViewModel, root: URL) {
        let root = try makeTree()
        let viewModel = makeViewModel(root: root)
        viewModel.startScan()
        guard await waitForResults(viewModel) else {
            Issue.record("scan did not reach .results; phase is \(viewModel.phase)")
            return (viewModel, root)
        }
        return (viewModel, root)
    }

    /// The level's cells at a fixed canvas size.
    private func cells(_ viewModel: SpaceLensViewModel) -> [SpaceLensViewModel.DisplayItem] {
        viewModel.layoutRects(in: CGRect(x: 0, y: 0, width: 1000, height: 800))
    }

    /// A tree whose every item is a top-level cell above the 0.4 % threshold, so the whole
    /// folder can be emptied through the cart (the D5/D6 tests).
    private func makeEmptyableTree() throws -> URL {
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("spacelens-empty-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        for index in 0..<2 {
            try Data(repeating: 0x61, count: 100_000 + index)
                .write(to: root.appendingPathComponent("only-\(index).dat"))
        }
        return root
    }

    private func cell(_ viewModel: SpaceLensViewModel, named label: String) -> SpaceLensViewModel.DisplayItem? {
        cells(viewModel).first { $0.label == label }
    }

    private func select(_ viewModel: SpaceLensViewModel, named label: String) {
        guard let item = cell(viewModel, named: label) else {
            Issue.record("no cell named \(label) in \(cells(viewModel).map(\.label))")
            return
        }
        viewModel.handleTap(on: item)
        viewModel.toggleSelectedItemCleanup()
    }

    @Test("lifecycle maps every phase, including empty and failed")
    func lifecycleMapping() async throws {
        let root = try makeTree()
        defer { try? fileManager.removeItem(at: root) }

        // idle → start
        let viewModel = makeViewModel(root: root)
        #expect(viewModel.lifecycle == .start)

        // results → results
        viewModel.startScan()
        guard await waitForResults(viewModel) else {
            Issue.record("scan did not reach .results")
            return
        }
        #expect(viewModel.lifecycle == .results)

        // An empty folder lands in `results` and maps to `empty` (F3).
        let bare = fileManager.temporaryDirectory
            .appendingPathComponent("spacelens-empty-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: bare, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: bare) }
        let emptyViewModel = makeViewModel(root: bare)
        emptyViewModel.startScan()
        guard await waitForResults(emptyViewModel) else {
            Issue.record("empty scan did not reach .results")
            return
        }
        #expect(emptyViewModel.lifecycle == .empty)

        // An unreadable root is `failed` and maps to `error` — never "empty".
        let missing = fileManager.temporaryDirectory
            .appendingPathComponent("spacelens-missing-\(UUID().uuidString)", isDirectory: true)
        let failedViewModel = makeViewModel(root: missing)
        failedViewModel.startScan()
        var reachedFailed = false
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, !reachedFailed {
            if case .failed = failedViewModel.phase { reachedFailed = true }
            if !reachedFailed { try? await Task.sleep(for: .milliseconds(10)) }
        }
        guard reachedFailed else {
            Issue.record("missing-root scan did not reach .failed")
            return
        }
        #expect(failedViewModel.lifecycle == .error)
    }

    // MARK: - Nothing pre-selected (§5.5)

    @Test("a fresh scan pre-selects nothing")
    func nothingIsPreSelected() async throws {
        let (viewModel, root) = try await scanTree()
        defer { try? fileManager.removeItem(at: root) }

        #expect(viewModel.selectedPaths.isEmpty)
        #expect(viewModel.cleanupItems.isEmpty)
        #expect(viewModel.totalSelectedBytes == 0)
    }

    // MARK: - The cart keeps only top-most items

    @Test("selecting a folder and its descendant keeps only the top-most item")
    func cartKeepsOnlyTopMostItems() async throws {
        let (viewModel, root) = try await scanTree()
        defer { try? fileManager.removeItem(at: root) }

        select(viewModel, named: "Nested")
        viewModel.drillIn(on: cell(viewModel, named: "Nested")!)
        select(viewModel, named: "nested-0.dat")
        #expect(viewModel.selectedPaths.count == 2)

        let nestedPath = (standardPath(root) as NSString).appendingPathComponent("Nested")
        let cart = viewModel.cleanupItems
        #expect(cart.count == 1)
        #expect(cart.first?.path == nestedPath)
    }

    // MARK: - The smaller-items merge (count and size)

    @Test("cells below 0.4 % merge into one real-count, real-size bucket")
    func smallerItemsMerge() throws {
        func item(_ id: Int32, _ label: String, _ size: Int64) -> SpaceLensViewModel.DisplayItem {
            SpaceLensViewModel.DisplayItem(
                id: id, label: label, path: "/tmp/\(label)", size: size, rect: .zero,
                isDirectory: false, descendantCount: 0, lastModified: nil)
        }

        // Total 504 100 → threshold 2 016.4: a (2 100) stays, b (2 000) merges.
        let merged = SpaceLensViewModel.mergingSmallerItems([
            item(1, "big", 500_000), item(2, "a", 2_100), item(3, "b", 2_000),
        ])
        #expect(merged.map(\.label) == ["big", "a", "1 smaller item"])
        let bucket = merged.first { $0.isSmallerBucket }
        #expect(bucket?.size == 2_000)
        #expect(bucket?.path == nil)
        #expect(bucket?.isDirectory == false)

        // Nothing below the threshold: no bucket at all.
        let noMerge = SpaceLensViewModel.mergingSmallerItems([
            item(1, "big", 500_000), item(2, "a", 2_100),
        ])
        #expect(noMerge.count == 2)
        #expect(!noMerge.contains { $0.isSmallerBucket })

        // Multiple small cells: the label carries their real count, the size their sum.
        let multi = SpaceLensViewModel.mergingSmallerItems([
            item(1, "a", 600), item(2, "b", 300), item(3, "t1", 2), item(4, "t2", 2), item(5, "t3", 2),
        ])
        #expect(multi.count == 3)
        let multiBucket = multi.first { $0.isSmallerBucket }
        #expect(multiBucket?.label == "3 smaller items")
        #expect(multiBucket?.size == 6)
    }

    @Test("the laid-out map carries one real smaller-items bucket")
    func layoutCarriesBucket() async throws {
        let (viewModel, root) = try await scanTree()
        defer { try? fileManager.removeItem(at: root) }

        // Level total 130 600 → threshold 522.4: the three small files merge.
        let bucket = cell(viewModel, named: "3 smaller items")
        #expect(bucket?.size == 600)
        #expect(bucket?.isDirectory == false)
        #expect(cells(viewModel).filter { $0.isSmallerBucket }.count == 1)
    }

    // MARK: - Selection never includes an ineligible path

    @Test("the root's top-level Library folder is protected and never enters the cart")
    func protectedLibraryNeverSelected() async throws {
        let root = try makeTree()
        defer { try? fileManager.removeItem(at: root) }
        let library = root.appendingPathComponent("Library", isDirectory: true)
        try fileManager.createDirectory(at: library, withIntermediateDirectories: true)
        try Data(repeating: 0x62, count: 10_000)
            .write(to: library.appendingPathComponent("settings.dat"))

        let viewModel = makeViewModel(root: root)
        viewModel.startScan()
        guard await waitForResults(viewModel) else {
            Issue.record("scan did not reach .results")
            return
        }

        select(viewModel, named: "Library")
        #expect(viewModel.selectedPaths.isEmpty)

        // The rule the inspector reads for the protected explanation: the top-level
        // Library only — its contents belong to Junk & Cache / Uninstaller.
        let libraryPath = (standardPath(root) as NSString).appendingPathComponent("Library")
        #expect(SpaceLensViewModel.isProtectedLocation(libraryPath, scanRootPath: standardPath(root)))
        #expect(!SpaceLensViewModel.isProtectedLocation(
            (libraryPath as NSString).appendingPathComponent("settings.dat"),
            scanRootPath: standardPath(root)))
    }

    @Test("By Type cells and the smaller-items bucket never enter the cart")
    func pathlessCellsNeverSelected() async throws {
        let (viewModel, root) = try await scanTree()
        defer { try? fileManager.removeItem(at: root) }

        viewModel.viewMode = .category
        guard let category = cells(viewModel).first(where: { $0.isCategory }) else {
            Issue.record("no category cells laid out")
            return
        }
        viewModel.handleTap(on: category)
        viewModel.toggleSelectedItemCleanup()
        #expect(viewModel.selectedPaths.isEmpty)

        viewModel.viewMode = .tree
        if let bucket = cell(viewModel, named: "3 smaller items") {
            viewModel.handleTap(on: bucket)
            viewModel.toggleSelectedItemCleanup()
            #expect(viewModel.selectedPaths.isEmpty)
        }
    }

    @Test("the cart boundary filters outside-root and root-self paths (policy normalization)")
    func cartBoundaryFiltersIneligiblePaths() {
        let policy = SpaceLensCleanupPolicy()
        let root = standardPath(fileManager.temporaryDirectory
            .appendingPathComponent("spacelens-policy-\(UUID().uuidString)"))
        let inside = (root as NSString).appendingPathComponent("Nested")
        let insideChild = (inside as NSString).appendingPathComponent("nested-0.dat")

        func item(_ path: String) -> ScanItem {
            ScanItem(path: path, size: 1_000, kind: .directory)
        }

        let normalized = policy.normalizedSelection(
            from: [item(insideChild), item(inside), item(root), item("/somewhere/else")],
            scanRootPath: root)

        // Only the top-most inside path survives: the child (double-counted subtree),
        // the root itself and the outside path are all gone.
        #expect(normalized.map { $0.path } == [inside])
    }

    // MARK: - Confirmation (CF-3: the sheet shows the cart's own numbers)

    @Test("the cleanup-list confirmation carries the cart's count, size and items")
    func cleanupConfirmationCarriesCartNumbers() async throws {
        let (viewModel, root) = try await scanTree()
        defer { try? fileManager.removeItem(at: root) }

        select(viewModel, named: "big.dat")
        select(viewModel, named: "Nested")

        let model = viewModel.cleanupConfirmation()
        let cart = viewModel.cleanupItems
        #expect(model.variant == .cleanupList)
        #expect(model.count == cart.count)
        #expect(model.count == 2)
        #expect(model.sizeText == ConfirmItemList.sizeText(for: viewModel.totalSelectedBytes))
        #expect(Set(model.items.map(\.id)) == Set(cart.map(\.path)))
        // The checkout list's own checkboxes: every item starts checked.
        let state = ConfirmSheetState(model: model)
        #expect(state.checkedItemIDs == Set(cart.map(\.path)))
        #expect(state.isConfirmEnabled)
    }

    // MARK: - Review cancel (§5.5: dismissing the review sheet exits review)

    @Test("cancelCleanupReview resets .review to .results and is a no-op outside review")
    func cancelCleanupReviewResetsAndIsNoOpOutsideReview() async throws {
        let (viewModel, root) = try await scanTree()
        defer { try? fileManager.removeItem(at: root) }

        // Outside .review (still .results): a no-op.
        viewModel.cancelCleanupReview()
        #expect(viewModel.phase == .results)

        select(viewModel, named: "big.dat")
        viewModel.beginCleanupReview()
        #expect(viewModel.phase == .review)

        viewModel.cancelCleanupReview()
        #expect(viewModel.phase == .results)
        // The map's review CTA works again (beginCleanupReview guards .results).
        viewModel.beginCleanupReview()
        #expect(viewModel.phase == .review)
    }

    @Test("the confirmation model's cancel closure exits review (Cancel and Escape)")
    func confirmationCancelClosureExitsReview() async throws {
        let (viewModel, root) = try await scanTree()
        defer { try? fileManager.removeItem(at: root) }

        select(viewModel, named: "big.dat")
        viewModel.beginCleanupReview()
        #expect(viewModel.phase == .review)

        // The sheet's Cancel button and Escape both land on this closure (CF-1).
        viewModel.cleanupConfirmation().cancel()
        #expect(viewModel.phase == .results)
    }

    // MARK: - Clean (the real, trash-routed path)

    @Test("a confirmed clean moves the checked items and reports real figures")
    func cleanMovesCheckedItemsAndReportsFigures() async throws {
        let (viewModel, root) = try await scanTree()

        select(viewModel, named: "big.dat")
        select(viewModel, named: "Nested")
        let cart = viewModel.cleanupItems
        let expectedBytes = cart.reduce(0) { $0 + $1.size }
        let nestedPath = (standardPath(root) as NSString).appendingPathComponent("Nested")

        let accepted = await viewModel.clean(checkedIDs: Set(cart.map(\.path)))
        defer {
            // Trash cleanup for the moved test files.
            if let trash = try? fileManager.url(for: .trashDirectory, in: .userDomainMask,
                                                appropriateFor: nil, create: false) {
                for item in cart {
                    try? fileManager.removeItem(at: trash.appendingPathComponent(
                        (item.path as NSString).lastPathComponent))
                }
            }
            try? fileManager.removeItem(at: root)
        }

        #expect(accepted)
        guard case .done(let movedBytes, let movedCount, let failedCount) = viewModel.phase else {
            Issue.record("phase should be .done, got \(viewModel.phase)")
            return
        }
        #expect(movedBytes == expectedBytes)
        #expect(movedCount == cart.count)
        #expect(failedCount == 0)
        #expect(viewModel.lastFailedItems.isEmpty)
        // The cart is empty and the map no longer lists what moved (N7 stays true).
        #expect(viewModel.cleanupItems.isEmpty)
        #expect(!fileManager.fileExists(atPath: nestedPath))
        #expect(!fileManager.fileExists(atPath: (standardPath(root) as NSString).appendingPathComponent("big.dat")))

        viewModel.backToMap()
        #expect(viewModel.phase == .results)
        #expect(viewModel.lifecycle == .results)
        let labels = cells(viewModel).map(\.label)
        #expect(!labels.contains("big.dat"))
        #expect(!labels.contains("Nested"))
    }

    @Test("a moved item fails honestly: counted, surfaced, never a success")
    func failedMovesAreCountedAndSurfaced() async throws {
        let (viewModel, root) = try await scanTree()

        select(viewModel, named: "big.dat")
        select(viewModel, named: "Nested")
        let cart = viewModel.cleanupItems
        let big = cart.first { !$0.path.hasSuffix("Nested") }!

        // The file disappears before the clean runs (test fixture management only):
        // the real Cleaner fails on it and the Done state must say so.
        try fileManager.removeItem(at: URL(fileURLWithPath: big.path))

        let accepted = await viewModel.clean(checkedIDs: Set(cart.map(\.path)))
        defer {
            if let trash = try? fileManager.url(for: .trashDirectory, in: .userDomainMask,
                                                appropriateFor: nil, create: false) {
                try? fileManager.removeItem(at: trash.appendingPathComponent("Nested"))
            }
            try? fileManager.removeItem(at: root)
        }

        #expect(accepted)
        guard case .done(let movedBytes, let movedCount, let failedCount) = viewModel.phase else {
            Issue.record("phase should be .done, got \(viewModel.phase)")
            return
        }
        #expect(movedCount == 1)
        #expect(failedCount == 1)
        #expect(movedBytes == 30_000)
        #expect(viewModel.lastFailedItems.count == 1)
        #expect(viewModel.lastFailedItems.first?.item.path == big.path)
        #expect(!viewModel.lastFailedItems.first!.reason.isEmpty)
        #expect(viewModel.selectedPaths.contains(big.path))  // failures stay in the cart
    }

    @Test("a session-emptied folder is not a scanned-empty folder")
    func cleanedEmptyIsNotScannedEmpty() async throws {
        let root = try makeEmptyableTree()
        defer { try? fileManager.removeItem(at: root) }
        let viewModel = makeViewModel(root: root)
        viewModel.startScan()
        guard await waitForResults(viewModel) else {
            Issue.record("scan did not reach .results; phase is \(viewModel.phase)")
            return
        }

        select(viewModel, named: "only-0.dat")
        select(viewModel, named: "only-1.dat")
        let cart = viewModel.cleanupItems
        #expect(cart.count == 2)
        defer {
            // Trash cleanup for the moved test files.
            if let trash = try? fileManager.url(for: .trashDirectory, in: .userDomainMask,
                                                appropriateFor: nil, create: false) {
                for item in cart {
                    try? fileManager.removeItem(at: trash.appendingPathComponent(
                        (item.path as NSString).lastPathComponent))
                }
            }
        }

        let accepted = await viewModel.clean(checkedIDs: Set(cart.map(\.path)))
        #expect(accepted)
        guard case .done(let movedBytes, let movedCount, let failedCount) = viewModel.phase else {
            Issue.record("phase should be .done, got \(viewModel.phase)")
            return
        }
        #expect(movedBytes == cart.reduce(0) { $0 + $1.size })
        #expect(movedCount == 2)
        #expect(failedCount == 0)

        viewModel.backToMap()
        // F3: results over an empty folder is the empty state — but the scan did find
        // items (D5): this session emptied it, a different truth from scanned-empty.
        #expect(viewModel.phase == .results)
        #expect(viewModel.lifecycle == .empty)
        #expect(viewModel.isCleanedEmpty)
        #expect(SpaceLensViewModel.emptyTitle(isCleanedEmpty: true, rootName: viewModel.rootName)
                == "You moved everything out of “\(viewModel.rootName)”")
        #expect(SpaceLensViewModel.emptyTitle(isCleanedEmpty: false, rootName: viewModel.rootName)
                == "This folder is empty")
    }

    @Test("a folder that really scanned empty keeps the scanned-empty story")
    func scannedEmptyKeepsItsStory() async throws {
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("spacelens-gone-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }
        let viewModel = makeViewModel(root: root)
        viewModel.startScan()
        guard await waitForResults(viewModel) else {
            Issue.record("scan did not reach .results; phase is \(viewModel.phase)")
            return
        }

        #expect(viewModel.lifecycle == .empty)
        #expect(!viewModel.isCleanedEmpty)
        #expect(SpaceLensViewModel.emptyTitle(isCleanedEmpty: false, rootName: viewModel.rootName)
                == "This folder is empty")
    }

    @Test("Done with every move failed leads with the failure, never 0 bytes")
    func doneAllFailedLeadsWithTheFailure() async throws {
        let root = try makeEmptyableTree()
        defer { try? fileManager.removeItem(at: root) }
        let viewModel = makeViewModel(root: root)
        viewModel.startScan()
        guard await waitForResults(viewModel) else {
            Issue.record("scan did not reach .results; phase is \(viewModel.phase)")
            return
        }

        select(viewModel, named: "only-0.dat")
        select(viewModel, named: "only-1.dat")
        let cart = viewModel.cleanupItems
        #expect(cart.count == 2)

        // The files disappear before the clean runs (test fixture management only): the
        // real Cleaner fails on both, and the Done state must lead with the failure (D6).
        for item in cart {
            try fileManager.removeItem(atPath: item.path)
        }

        let accepted = await viewModel.clean(checkedIDs: Set(cart.map(\.path)))
        #expect(accepted)
        guard case .done(let movedBytes, let movedCount, let failedCount) = viewModel.phase else {
            Issue.record("phase should be .done, got \(viewModel.phase)")
            return
        }
        #expect(movedBytes == 0)
        #expect(movedCount == 0)
        #expect(failedCount == 2)
        #expect(viewModel.lastFailedItems.count == 2)  // F4: the reasons render below the headline

        #expect(SpaceLensViewModel.doneTitle(movedBytes: 0, movedCount: 0, failedCount: 2)
                == "Nothing could be moved to the Trash")
        #expect(SpaceLensViewModel.doneSub(movedCount: 0, failedCount: 2, rootName: viewModel.rootName)
                == "The items are still where they were.")
        // The mixed and all-success cases keep their copy.
        #expect(SpaceLensViewModel.doneTitle(movedBytes: 30_000, movedCount: 1, failedCount: 0)
                == "30 KB moved to the Trash")
        #expect(SpaceLensViewModel.doneSub(movedCount: 1, failedCount: 0, rootName: "Downloads")
                == "From Downloads.")
    }

    @Test("clean with nothing checked does nothing")
    func emptyCleanDoesNothing() async throws {
        let (viewModel, root) = try await scanTree()
        defer { try? fileManager.removeItem(at: root) }

        let accepted = await viewModel.clean(checkedIDs: ["/tmp/never-selected"])

        #expect(!accepted)
        #expect(viewModel.lifecycle == .results)
    }

    // MARK: - Re-entrancy (a second clean while moving is refused)

    @Test("cleaning refuses a second call while files are moving")
    func cleanRefusesASecondCall() async throws {
        // The Debug fixture loads `.cleaning` with a cart in flight (no real files).
        let viewModel = SpaceLensViewModel()
        viewModel.loadFixture(.cleaning)
        guard case .cleaning(let selectedCount) = viewModel.phase else {
            Issue.record("fixture should be in .cleaning")
            return
        }
        let cart = viewModel.cleanupItems
        #expect(!cart.isEmpty)
        let selectionBefore = viewModel.selectedPaths

        let accepted = await viewModel.clean(checkedIDs: Set(cart.map(\.path)))

        #expect(!accepted)
        guard case .cleaning(let stillSelectedCount) = viewModel.phase else {
            Issue.record("phase must stay .cleaning")
            return
        }
        #expect(stillSelectedCount == selectedCount)
        #expect(viewModel.selectedPaths == selectionBefore)
    }

    // MARK: - Scan guards (F2)

    @Test("Stop returns to start and discards results")
    func cancelScanReturnsToStart() async throws {
        let root = try makeTree()
        defer { try? fileManager.removeItem(at: root) }
        let viewModel = makeViewModel(root: root)

        viewModel.startScan()
        viewModel.cancelScan()

        #expect(viewModel.phase == .idle)
        #expect(viewModel.lifecycle == .start)
        // Re-entry is refused while a scan runs (PR 3 guard).
        #expect(viewModel.startScan())
        #expect(await waitForResults(viewModel))
    }
}

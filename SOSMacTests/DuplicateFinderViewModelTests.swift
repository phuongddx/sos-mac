import Foundation
import Testing
import CleanCore
@testable import SOSMac

/// Duplicate Finder view-model tests (plan PR 6): the lifecycle mapping, the Keep lock in
/// both modes, pre-selection (OD-a), per-set totals (OD-b), the clean guards and the
/// group recompute after a clean. Real clean tests follow `JunkCleanerViewModelTests`:
/// UUID-named temp files, the real trash route, no debris left in the user's Trash.
@Suite("DuplicateFinderViewModel")
@MainActor
struct DuplicateFinderViewModelTests {

    // MARK: - Fixtures

    private static let newer = Date(timeIntervalSince1970: 1_800_000_000)
    private static let older = Date(timeIntervalSince1970: 1_700_000_000)
    private static let oldest = Date(timeIntervalSince1970: 1_600_000_000)

    /// A `ScanItem` at a unique temp path that is never created.
    private static func missing(_ name: String, size: Int64, modified: Date) -> ScanItem {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("dup-missing-\(UUID().uuidString)-\(name)").path
        return ScanItem(path: path, size: size, kind: .file, lastModified: modified)
    }

    /// Two sets: A (3 copies, the first is newest) and B (2 copies, the last is newest).
    /// Paths never exist, so a clean over them exercises the real `Cleaner` failure path.
    private static func twoSets() -> [DuplicateGroup] {
        [
            DuplicateGroup(id: "a", items: [
                missing("a.zip", size: 1_000, modified: newer),
                missing("a.zip", size: 1_000, modified: older),
                missing("a.zip", size: 1_000, modified: oldest),
            ]),
            DuplicateGroup(id: "b", items: [
                missing("b.mov", size: 5_000, modified: older),
                missing("b.mov", size: 5_000, modified: newer),
            ]),
        ]
    }

    private static func makeViewModel(cleaner: any Cleaner = DefaultCleaner()) -> DuplicateFinderViewModel {
        DuplicateFinderViewModel(rootPath: FileManager.default.temporaryDirectory.path, cleaner: cleaner)
    }

    private static func keepPaths(_ groups: [DuplicateGroup]) -> Set<String> {
        Set(groups.compactMap(\.recommendedKeepPath))
    }

    // MARK: - Lifecycle mapping

    @Test("every phase maps to its lifecycle state; results without sets is empty")
    func lifecycleMapping() {
        let viewModel = Self.makeViewModel()
        #expect(viewModel.lifecycle == .start)

        viewModel.loadFixture(.scanning)
        #expect(viewModel.lifecycle == .scanning)

        viewModel.loadFixture(.results)
        #expect(viewModel.lifecycle == .results)

        viewModel.loadFixture(.review)
        #expect(viewModel.lifecycle == .review)

        viewModel.loadFixture(.cleaning)
        #expect(viewModel.lifecycle == .cleaning)

        viewModel.loadFixture(.done)
        #expect(viewModel.lifecycle == .done)

        viewModel.loadFixture(.error)
        #expect(viewModel.lifecycle == .error)

        viewModel.loadFixture(.empty)
        #expect(viewModel.lifecycle == .empty)
        #expect(viewModel.phase == .results)
        #expect(viewModel.sets.isEmpty)
    }

    @Test("a finished scan with no duplicate sets is the empty state, not a failure")
    func emptyIsNotFailure() {
        let viewModel = Self.makeViewModel()
        viewModel.loadFixtureResults([])
        #expect(viewModel.lifecycle == .empty)
        #expect(viewModel.errorMessage == nil)
    }

    @Test("a failed scan is the error state and keeps the engine's reason")
    func failedMapsToError() {
        let viewModel = Self.makeViewModel()
        viewModel.loadFixture(.error)
        guard case .failed(let message) = viewModel.phase else {
            Issue.record("phase should be .failed, got \(viewModel.phase)")
            return
        }
        #expect(!message.isEmpty)
        #expect(viewModel.errorMessage == message)
        #expect(viewModel.lifecycle == .error)
    }

    @Test("the error text names Full Disk Access under Privacy & Security — text only")
    func failureTextNamesFullDiskAccess() {
        let text = DuplicateFinderViewModel.failureText(reason: "Couldn't read the folder.")
        #expect(text.hasPrefix("Couldn't read the folder."))
        #expect(text.contains("Full Disk Access"))
        #expect(text.contains("Privacy & Security"))
    }

    // MARK: - Sets mapping

    @Test("sets map one per group, titled by the keep copy's file name")
    func setsMapping() {
        let groups = Self.twoSets()
        let sets = DuplicateFinderViewModel.sets(from: groups)

        #expect(sets.map(\.id) == ["a", "b"])
        #expect(sets[0].items.count == 3)
        #expect(sets[0].keepPath == groups[0].items[0].path)
        #expect(sets[1].keepPath == groups[1].items[1].path)
        #expect(sets[0].title.hasSuffix("a.zip"))
        #expect(sets[1].title.hasSuffix("b.mov"))
    }

    @Test("a group with fewer than two copies is not a duplicate set")
    func singleCopyGroupDropped() {
        let single = DuplicateGroup(id: "x", items: [Self.missing("x.bin", size: 10, modified: Self.newer)])
        let sets = DuplicateFinderViewModel.sets(from: [single] + Self.twoSets())
        #expect(sets.map(\.id) == ["a", "b"])
    }

    @Test("the keep copy is the newest by date modified")
    func keepIsNewestByModified() {
        // The oldest-modified copy carries the newest access time: access time must not matter.
        let accessedRecently = ScanItem(
            path: "/tmp/dup-atime-\(UUID().uuidString)", size: 10, kind: .file,
            lastAccessed: Date(), lastModified: Self.oldest)
        let modifiedRecently = ScanItem(
            path: "/tmp/dup-mtime-\(UUID().uuidString)", size: 10, kind: .file,
            lastAccessed: Self.oldest, lastModified: Self.newer)
        let sets = DuplicateFinderViewModel.sets(
            from: [DuplicateGroup(id: "g", items: [accessedRecently, modifiedRecently])])
        #expect(sets[0].keepPath == modifiedRecently.path)
    }

    // MARK: - Per-set totals (OD-b)

    @Test("each set reports its own extra copies and the bytes they free")
    func perSetTotals() {
        let sets = DuplicateFinderViewModel.sets(from: Self.twoSets())

        #expect(sets[0].extraItems.count == 2)
        #expect(sets[0].extraBytes == 2_000)
        #expect(sets[1].extraItems.count == 1)
        #expect(sets[1].extraBytes == 5_000)
        #expect(sets[0].copySize == 1_000)
        #expect(sets[0].extraItems.allSatisfy { $0.path != sets[0].keepPath })
    }

    @Test("results totals count sets, files and the selected bytes")
    func resultsTotals() {
        let viewModel = Self.makeViewModel()
        viewModel.loadFixtureResults(Self.twoSets())

        #expect(viewModel.sets.count == 2)
        #expect(viewModel.totalFileCount == 5)
        #expect(viewModel.selectedItems.count == 3)
        #expect(viewModel.totalSelectedBytes == 7_000)
    }

    // MARK: - Pre-selection (OD-a)

    @Test("Exact mode pre-selects every extra copy and never a keep copy")
    func exactPreSelectsExtras() {
        let groups = Self.twoSets()
        let viewModel = Self.makeViewModel()
        viewModel.loadFixtureResults(groups, mode: .exact)

        let keeps = Self.keepPaths(groups)
        let extras = Set(groups.flatMap(\.items).map(\.path)).subtracting(keeps)
        #expect(viewModel.selectedPaths == extras)
        #expect(viewModel.selectedPaths.isDisjoint(with: keeps))
    }

    @Test("Similar mode pre-selects nothing (OD-a)")
    func similarPreSelectsNothing() {
        let viewModel = Self.makeViewModel()
        viewModel.loadFixtureResults(Self.twoSets(), mode: .similarImages)

        #expect(viewModel.selectedPaths.isEmpty)
        #expect(viewModel.selectedItems.isEmpty)
        #expect(viewModel.totalSelectedBytes == 0)
        #expect(!viewModel.sets.isEmpty)
    }

    @Test("pre-selection is a pure function of mode")
    func preSelectionPure() {
        let sets = DuplicateFinderViewModel.sets(from: Self.twoSets())
        #expect(DuplicateFinderViewModel.preSelection(for: sets, mode: .similarImages).isEmpty)
        #expect(DuplicateFinderViewModel.preSelection(for: sets, mode: .exact).count == 3)
    }

    // MARK: - Keep lock (both modes)

    @Test("the keep copy can never be selected — toggle is refused in both modes",
          arguments: [DuplicateFinderViewModel.Mode.exact, .similarImages])
    func keepNeverSelectable(mode: DuplicateFinderViewModel.Mode) {
        let groups = Self.twoSets()
        let viewModel = Self.makeViewModel()
        viewModel.loadFixtureResults(groups, mode: mode)
        let keeps = Self.keepPaths(groups)

        for keep in keeps {
            #expect(viewModel.isKept(path: keep))
            viewModel.toggleSelection(path: keep)
            #expect(!viewModel.selectedPaths.contains(keep))
            #expect(!viewModel.selectedItems.contains { $0.path == keep })
        }
        // An extra copy toggles normally.
        let extra = groups[0].items[1].path
        let before = viewModel.selectedPaths.contains(extra)
        viewModel.toggleSelection(path: extra)
        #expect(viewModel.selectedPaths.contains(extra) != before)
    }

    @Test("Select All in a set takes the extras and skips the keep copy, in both modes",
          arguments: [DuplicateFinderViewModel.Mode.exact, .similarImages])
    func selectAllSkipsKept(mode: DuplicateFinderViewModel.Mode) throws {
        let groups = Self.twoSets()
        let viewModel = Self.makeViewModel()
        viewModel.loadFixtureResults(groups, mode: mode)
        viewModel.enterReview()
        viewModel.selectSet("a")
        viewModel.deselectAllInCurrentSet()

        viewModel.selectAllInCurrentSet()

        let set = try #require(viewModel.currentSet)
        #expect(set.id == "a")
        #expect(viewModel.selectedPaths.isSuperset(of: set.extraItems.map(\.path)))
        #expect(!viewModel.selectedPaths.contains(set.keepPath!))
        #expect(viewModel.selectedCount(in: set) == 2)
    }

    @Test("Deselect All clears the current set only")
    func deselectAllScopedToSet() {
        let groups = Self.twoSets()
        let viewModel = Self.makeViewModel()
        viewModel.loadFixtureResults(groups, mode: .exact)
        viewModel.enterReview()
        viewModel.selectSet("a")

        viewModel.deselectAllInCurrentSet()

        let a = viewModel.sets[0], b = viewModel.sets[1]
        #expect(viewModel.selectedCount(in: a) == 0)
        #expect(viewModel.selectedCount(in: b) == 1)
    }

    @Test("a keep path smuggled into the selection still never reaches the cleaner")
    func cleanFiltersKeepCopies() async {
        let groups = Self.twoSets()
        let viewModel = Self.makeViewModel()
        viewModel.loadFixtureResults(groups, mode: .exact)
        let keeps = Self.keepPaths(groups)
        // The Keep lock refuses the toggle; whatever `selectedItems` reports is all `clean()` uses.
        for keep in keeps { viewModel.toggleSelection(path: keep) }

        #expect(viewModel.selectedItems.allSatisfy { !keeps.contains($0.path) })
        #expect(viewModel.trashConfirmation(isFromResults: true).count == 3)
    }

    // MARK: - Mode switching

    @Test("switching the match type discards results and returns to Start")
    func setModeResets() {
        let viewModel = Self.makeViewModel()
        viewModel.loadFixtureResults(Self.twoSets(), mode: .exact)
        #expect(!viewModel.sets.isEmpty)

        viewModel.setMode(.similarImages)

        #expect(viewModel.mode == .similarImages)
        #expect(viewModel.phase == .idle)
        #expect(viewModel.sets.isEmpty)
        #expect(viewModel.selectedPaths.isEmpty)
        #expect(viewModel.skippedCount == 0)
    }

    @Test("setting the same mode keeps the results")
    func setModeSameIsNoOp() {
        let viewModel = Self.makeViewModel()
        viewModel.loadFixtureResults(Self.twoSets(), mode: .exact)
        viewModel.setMode(.exact)
        #expect(viewModel.phase == .results)
        #expect(!viewModel.sets.isEmpty)
    }

    @Test("the mode cannot change while a scan runs or files are moving")
    func setModeRefusedWhileBusy() {
        let scanning = Self.makeViewModel()
        scanning.loadFixture(.scanning)
        scanning.setMode(.similarImages)
        #expect(scanning.mode == .exact)
        #expect(scanning.phase == .scanning)

        let cleaning = Self.makeViewModel()
        cleaning.loadFixture(.cleaning)
        cleaning.setMode(.similarImages)
        #expect(cleaning.mode == .exact)
        #expect(cleaning.isCleaning)
    }

    // MARK: - Re-entrancy guards

    @Test("a scan cannot start while one runs or while copies are moving")
    func startScanGuard() {
        let scanning = Self.makeViewModel()
        scanning.loadFixture(.scanning)
        #expect(scanning.startScan() == false)

        let cleaning = Self.makeViewModel()
        cleaning.loadFixture(.cleaning)
        #expect(cleaning.startScan() == false)
        #expect(cleaning.isCleaning)
    }

    @Test("clean is refused while a clean is in flight and with nothing selected")
    func cleanGuards() async {
        let cleaning = Self.makeViewModel()
        cleaning.loadFixture(.cleaning)
        #expect(await cleaning.clean() == false)
        #expect(cleaning.isCleaning)

        let similar = Self.makeViewModel()
        similar.loadFixtureResults(Self.twoSets(), mode: .similarImages)
        #expect(await similar.clean() == false)   // OD-a: nothing selected, nothing moves
        #expect(similar.phase == .results)
    }

    // MARK: - Confirmation (S1)

    @Test("the confirmation carries the selection's count and bytes, without the keep copies")
    func confirmationMatchesSelection() {
        let groups = Self.twoSets()
        let viewModel = Self.makeViewModel()
        viewModel.loadFixtureResults(groups, mode: .exact)
        let keeps = Self.keepPaths(groups)

        let fromResults = viewModel.trashConfirmation(isFromResults: true)
        #expect(fromResults.count == 3)
        #expect(fromResults.isFromResults)
        #expect(fromResults.reviewItems != nil)
        #expect(fromResults.items.allSatisfy { !keeps.contains($0.id) })

        let fromReview = viewModel.trashConfirmation(isFromResults: false)
        #expect(fromReview.reviewItems == nil)
        #expect(fromReview.count == 3)
    }

    // MARK: - Failure accounting (S5)

    @Test("a failing clean counts failures on Done and moves nothing")
    func failuresCountedOnDone() async {
        let viewModel = Self.makeViewModel()
        viewModel.loadFixtureResults(Self.twoSets(), mode: .exact)

        let accepted = await viewModel.clean()

        #expect(accepted)
        guard case .done(let movedBytes, let movedCount, let failedCount) = viewModel.phase else {
            Issue.record("phase should be .done, got \(viewModel.phase)")
            return
        }
        #expect(movedCount == 0)
        #expect(movedBytes == 0)
        #expect(failedCount == 3)
        #expect(viewModel.lastFailedItems.count == 3)
        #expect(viewModel.lastKeptCount == 0)
        // Nothing moved, so every set and its selection are still there.
        #expect(viewModel.sets.count == 2)
        #expect(viewModel.selectedItems.count == 3)
    }

    // MARK: - Groups recompute after a clean (real files)

    @Test("after a real clean the groups recompute: a set down to one copy disappears")
    func groupsRecomputeAfterClean() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("dup-clean-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        // UUID-embedded names keep the Trash landing path deterministic (see
        // JunkCleanerViewModelTests); the Trash cleanup is a `defer`, so a failed expectation
        // leaves no debris.
        let tag = UUID().uuidString
        let payload = Data("sos-mac duplicate clean test".utf8)
        // Set 1: two copies. Set 2: three copies.
        func make(_ name: String, modified: Date) throws -> ScanItem {
            let url = root.appendingPathComponent("\(tag)-\(name)")
            try payload.write(to: url)
            try fileManager.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
            return ScanItem(path: url.path, size: Int64(payload.count), kind: .file, lastModified: modified)
        }
        let one = [try make("one-new.txt", modified: Self.newer), try make("one-old.txt", modified: Self.older)]
        let two = [try make("two-new.txt", modified: Self.newer),
                   try make("two-mid.txt", modified: Self.older),
                   try make("two-old.txt", modified: Self.oldest)]
        let trash = try fileManager.url(for: .trashDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        defer {
            for item in one + two {
                try? fileManager.removeItem(at: trash.appendingPathComponent((item.path as NSString).lastPathComponent))
            }
        }

        let viewModel = Self.makeViewModel()
        viewModel.loadFixtureResults([DuplicateGroup(id: "one", items: one), DuplicateGroup(id: "two", items: two)],
                                     mode: .exact)
        #expect(viewModel.selectedItems.count == 3)

        // Move only set 1's extra and one of set 2's extras.
        viewModel.toggleSelection(path: two[2].path)   // deselect two-old
        #expect(viewModel.selectedItems.count == 2)

        let accepted = await viewModel.clean()

        #expect(accepted)
        guard case .done(_, let movedCount, let failedCount) = viewModel.phase else {
            Issue.record("phase should be .done, got \(viewModel.phase)")
            return
        }
        #expect(movedCount == 2)
        #expect(failedCount == 0)
        #expect(viewModel.lastKeptCount == 2)

        // Set 1 is down to its keep copy only → gone. Set 2 keeps two copies (new + old).
        #expect(viewModel.sets.map(\.id) == ["two"])
        #expect(viewModel.sets[0].items.map(\.path).sorted() == [two[0].path, two[2].path].sorted())
        #expect(viewModel.sets[0].keepPath == two[0].path)
        #expect(!fileManager.fileExists(atPath: one[1].path))
        #expect(!fileManager.fileExists(atPath: two[1].path))
        #expect(fileManager.fileExists(atPath: one[0].path))      // keep copies never move
        #expect(fileManager.fileExists(atPath: two[0].path))
        #expect(fileManager.fileExists(atPath: two[2].path))
        // The deselected extra is not selected any more than before; moved paths are gone.
        #expect(!viewModel.selectedPaths.contains(one[1].path))
        #expect(!viewModel.selectedPaths.contains(two[1].path))
    }
}

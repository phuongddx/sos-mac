import Foundation
import SwiftData
import Testing
import CleanCore
@testable import SOSMac

/// Junk & Cache view-model tests (plan PR 5). Together with
/// `LifecycleMappingTests.swift` they cover the reference screen's contract:
/// pre-selection, Select All, the clean re-entrancy guard, failure accounting and the
/// ignore list. Real clean tests follow `ProgressiveCleanerTests` / `CleanerTrashTests`:
/// real temp files, the real trash route, no debris left in the user's Trash.
@Suite("JunkCleanerViewModel")
@MainActor
struct JunkCleanerViewModelTests {

    // MARK: - Fixtures

    static func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: IgnoredItem.self, QuarantineRecord.self,
            configurations: configuration
        )
        return ModelContext(container)
    }

    static func makeViewModel(
        context: ModelContext? = nil,
        rules: [JunkRule] = JunkRule.allowlist,
        cleaner: any Cleaner = DefaultCleaner(),
        privilegedHelper: any JunkPrivilegedTrashing = FailingHelper()
    ) throws -> JunkCleanerViewModel {
        JunkCleanerViewModel(
            modelContext: try context ?? makeContext(),
            rules: rules,
            cleaner: cleaner,
            privilegedHelper: privilegedHelper)
    }

    /// The helper seam's failure double: helper selections fail loudly in tests
    /// instead of talking to (or depending on) a real privileged daemon.
    @MainActor
    private struct FailingHelper: JunkPrivilegedTrashing {
        func trashSystemPath(_ path: String) async throws {
            throw PrivilegedHelperError.notRegistered
        }
    }

    @MainActor
    private final class HelperSpy: JunkPrivilegedTrashing {
        private(set) var trashedPaths: [String] = []

        func trashSystemPath(_ path: String) async throws {
            trashedPaths.append(path)
        }
    }

    private func fixtureItems() -> [ScanItem] {
        UITestFixtures.junkRules.flatMap(\.items)
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

    private func waitForResults(_ viewModel: JunkCleanerViewModel) async -> Bool {
        await wait(until: JunkCleanerViewModel.Phase.results) { viewModel.phase }
    }

    /// ScanItems pointing at unique temp paths that are **never created**. A clean
    /// over them exercises the real `Cleaner` failure path (per-item `trashItem`
    /// errors) without depending on anything in the user's home directory — the
    /// `/Users/sample` fixture paths must never reach the cleaner, because on a
    /// machine that really has such a user they would move real files.
    private static func missingItems(_ count: Int, helper: Bool = false) -> [ScanItem] {
        (0..<count).map { index in
            let path = FileManager.default.temporaryDirectory
                .appendingPathComponent("junk-missing-\(UUID().uuidString)-\(index).db")
                .path
            return ScanItem(
                path: path,
                size: Int64(100 + index),
                kind: .file,
                severity: helper ? .caution : .safe,
                sourceLabel: helper ? "System Caches (requires additional permission)" : "User App Caches",
                requiresPrivilegedHelper: helper)
        }
    }

    // MARK: - Pre-selection

    @Test("pre-selection selects safe items only — never caution, never helper items")
    func preSelectionIsSafeAndHelperFree() throws {
        let viewModel = try Self.makeViewModel()
        viewModel.loadFixture(.results)

        let safeNonHelper = fixtureItems().filter(JunkCleanerViewModel.isPreSelectable)
        #expect(viewModel.selectedPaths == Set(safeNonHelper.map(\.path)))

        let cautionItems = fixtureItems().filter { $0.severity == .caution }
        #expect(!cautionItems.isEmpty)
        #expect(cautionItems.allSatisfy { !viewModel.selectedPaths.contains($0.path) })

        let helperItems = fixtureItems().filter(\.requiresPrivilegedHelper)
        #expect(!helperItems.isEmpty)
        #expect(helperItems.allSatisfy { !viewModel.selectedPaths.contains($0.path) })
    }

    // MARK: - Select All

    @Test("Select All in a helper location selects nothing")
    func selectAllSkipsHelperItems() throws {
        let viewModel = try Self.makeViewModel()
        viewModel.loadFixture(.review)
        viewModel.selectGroup("system-caches")   // every item needs the helper

        viewModel.selectAllEligibleInCurrentGroup()

        let helperPaths = Set(viewModel.currentLocation?.items.map(\.path) ?? [])
        #expect(!helperPaths.isEmpty)
        #expect(helperPaths.isDisjoint(with: viewModel.selectedPaths))
    }

    @Test("Select All in a mixed location selects the safe items and skips caution")
    func selectAllSkipsCautionItems() throws {
        let viewModel = try Self.makeViewModel()
        viewModel.loadFixture(.review)
        viewModel.selectGroup("user-logs")   // safe files plus two caution files

        viewModel.selectAllEligibleInCurrentGroup()

        let groupItems = viewModel.currentLocation?.items ?? []
        #expect(!groupItems.isEmpty)
        #expect(groupItems.count { $0.severity == .caution } > 0)
        for item in groupItems {
            if JunkCleanerViewModel.isPreSelectable(item) {
                #expect(viewModel.selectedPaths.contains(item.path), "safe item \(item.path) should be selected")
            } else {
                #expect(!viewModel.selectedPaths.contains(item.path), "item \(item.path) must not be bulk-selected")
            }
        }
    }

    @Test("Deselect All clears the current group's selection only")
    func deselectAllIsGroupLocal() throws {
        let viewModel = try Self.makeViewModel()
        viewModel.loadFixture(.review)
        let before = viewModel.selectedPaths
        viewModel.selectGroup("user-logs")

        viewModel.deselectAllInCurrentGroup()

        let groupPaths = Set(viewModel.currentLocation?.items.map(\.path) ?? [])
        #expect(groupPaths.isDisjoint(with: viewModel.selectedPaths))
        #expect(viewModel.selectedPaths == before.subtracting(groupPaths))
    }

    // MARK: - Clean

    @Test("cleaning refuses a second call while files are moving")
    func cleanRefusesASecondCall() async throws {
        let viewModel = try Self.makeViewModel()
        viewModel.loadFixture(.cleaning)
        let itemsBefore = viewModel.items
        let selectionBefore = viewModel.selectedPaths
        guard case .cleaning(let selectedCount) = viewModel.phase else {
            Issue.record("fixture should be in .cleaning")
            return
        }

        let accepted = await viewModel.clean()

        #expect(accepted == false)
        guard case .cleaning(let stillSelectedCount) = viewModel.phase else {
            Issue.record("phase must stay .cleaning")
            return
        }
        #expect(stillSelectedCount == selectedCount)
        #expect(viewModel.items == itemsBefore)
        #expect(viewModel.selectedPaths == selectionBefore)
    }

    @Test("failures are counted, surfaced and never turned into a success")
    func failuresAreCountedAndSurfaced() async throws {
        // Unique temp paths that are never created: every trash attempt fails
        // through the real Cleaner error path, and no machine state can make a
        // real file move.
        let missing = Self.missingItems(3)
        let viewModel = try Self.makeViewModel()
        viewModel.loadFixtureResults(missing)
        let selected = viewModel.selectedItems
        #expect(selected.count == missing.count)

        let accepted = await viewModel.clean()

        #expect(accepted)
        guard case .done(let movedBytes, let movedCount, let failedCount) = viewModel.phase else {
            Issue.record("phase should be .done, got \(viewModel.phase)")
            return
        }
        #expect(movedBytes == 0)
        #expect(movedCount == 0)
        #expect(failedCount == selected.count)
        #expect(viewModel.lastFailedItems.count == selected.count)
        #expect(viewModel.lastFailedItems.allSatisfy { !$0.reason.isEmpty })
        // Nothing succeeded, so the results list is unchanged — and nothing landed
        // anywhere, so there is no debris to clean up.
        #expect(viewModel.items.count == missing.count)
    }

    @Test("helper items are routed to the privileged helper, not Cleaner.clean")
    func helperItemsRouteThroughThePrivilegedHelper() async throws {
        // Two user items at paths that never exist (they will fail to trash) and
        // one helper item — the helper item is the only one that can "move", and
        // only through the spy.
        let userItems = Self.missingItems(2)
        let helperItem = Self.missingItems(1, helper: true)[0]
        let helper = HelperSpy()
        let viewModel = try Self.makeViewModel(privilegedHelper: helper)
        viewModel.loadFixtureResults(userItems + [helperItem])
        viewModel.toggleSelection(path: helperItem.path)
        #expect(viewModel.selectedItems.count == 3)

        await viewModel.clean()

        #expect(helper.trashedPaths == [helperItem.path])
        guard case .done(_, let movedCount, let failedCount) = viewModel.phase else {
            Issue.record("phase should be .done")
            return
        }
        // The helper item moved through the spy; the user items failed to trash.
        #expect(movedCount == 1)
        #expect(failedCount == userItems.count)
        #expect(!viewModel.items.contains { $0.path == helperItem.path })
        #expect(viewModel.items.count == userItems.count)
    }

    @Test("a successful clean moves the selected files and reports real figures")
    func successfulCleanMovesFilesAndReportsFigures() async throws {
        // A real scan over a hermetic temp tree, then a real clean: the whole flow
        // runs through the production paths with no fixture state.
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("junk-clean-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }
        // UUID-embedded names make the Trash landing path deterministic even against
        // leftovers from earlier runs (CleanerTrashTests' collision note): a fixed
        // name would make `trashItem` land as "<name> 2.db" and the cleanup below
        // could then remove an unrelated pre-existing file. The Trash cleanup is a
        // `defer`, so a failed expectation still leaves no debris behind.
        let names = (0..<3).map { "junk-clean-\(UUID().uuidString)-\($0).db" }
        let payload = Data("sos-mac junk clean test".utf8)
        for name in names {
            try payload.write(to: root.appendingPathComponent(name))
        }
        let trash = try fileManager.url(for: .trashDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        defer {
            for name in names {
                try? fileManager.removeItem(at: trash.appendingPathComponent(name))
            }
        }
        let rule = JunkRule(id: "test-caches",
                            label: "Test Caches",
                            kind: .directPath(root.path),
                            defaultSeverity: .safe)
        let viewModel = try Self.makeViewModel(rules: [rule])

        viewModel.startScan()
        #expect(await waitForResults(viewModel))
        let scanned = viewModel.items
        #expect(scanned.count == 3)
        let expectedBytes = scanned.reduce(Int64(0)) { $0 + $1.size }

        let accepted = await viewModel.clean()

        #expect(accepted)
        guard case .done(let movedBytes, let movedCount, let failedCount) = viewModel.phase else {
            Issue.record("phase should be .done, got \(viewModel.phase)")
            return
        }
        #expect(movedCount == 3)
        #expect(movedBytes == expectedBytes)
        #expect(failedCount == 0)
        #expect(viewModel.items.isEmpty)
        #expect(viewModel.selectedPaths.isEmpty)
        for item in scanned {
            #expect(!fileManager.fileExists(atPath: item.path))
        }
    }

    @Test("clean with an empty selection does nothing")
    func emptySelectionDoesNothing() async throws {
        let viewModel = try Self.makeViewModel()
        viewModel.loadFixture(.results)
        for path in viewModel.selectedPaths {
            viewModel.toggleSelection(path: path)
        }
        #expect(viewModel.selectedPaths.isEmpty)

        let accepted = await viewModel.clean()

        #expect(accepted == false)
        #expect(viewModel.lifecycle == .results)
    }

    // MARK: - Ignore (OD-8)

    @Test("Ignore removes the file from the list and the next scan (persisted)")
    func ignoreKeepsWorking() async throws {
        // A real scanner over a hermetic temp tree: the ignore list is SwiftData, so
        // the whole flow (scan → ignore → rescan) runs for real with no fixtures.
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("junk-ignore-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }
        for index in 0..<3 {
            let file = root.appendingPathComponent("cache-\(index).db", isDirectory: false)
            fileManager.createFile(atPath: file.path, contents: Data("cache".utf8))
        }
        let rule = JunkRule(id: "test-caches",
                            label: "Test Caches",
                            kind: .directPath(root.path),
                            defaultSeverity: .safe)
        let viewModel = try Self.makeViewModel(rules: [rule])

        viewModel.startScan()
        #expect(await waitForResults(viewModel))
        #expect(viewModel.items.count == 3)

        let ignored = viewModel.items[0]
        viewModel.ignore(ignored)

        #expect(viewModel.items.count == 2)
        #expect(viewModel.items.allSatisfy { $0.path != ignored.path })
        #expect(!viewModel.selectedPaths.contains(ignored.path))

        viewModel.startScan()
        #expect(await waitForResults(viewModel))
        #expect(viewModel.items.count == 2)
        #expect(viewModel.items.allSatisfy { $0.path != ignored.path })
    }

    // MARK: - Grouping

    @Test("grouping puts every item in exactly one location, in rule order")
    func groupingCoversEveryItem() throws {
        let items = fixtureItems()
        let locations = JunkCleanerViewModel.locations(from: items, rules: JunkRule.allowlist)

        #expect(locations.count == 4)
        #expect(locations.map(\.id) == ["user-caches", "user-logs", "app-support-caches", "system-caches"])
        #expect(locations.flatMap(\.items).count == items.count)
        #expect(Set(locations.flatMap(\.items).map(\.path)) == Set(items.map(\.path)))
        let helperLocation = locations.first { $0.requiresPrivilegedHelper }
        #expect(helperLocation?.id == "system-caches")
        #expect(helperLocation?.root == "/Library/Caches")
    }
}

import Foundation
import Testing
// @testable: the successful-delete tests construct `CloudDeleteResult`, whose
// memberwise initializer is internal (CleanCore's own providers build the rows
// in-module). Debug builds of the local package keep testability on; if that
// ever changes, these tests fall back to the throwing-fake design.
@testable import CleanCore
@testable import SOSMac

/// Cloud Cleanup view-model tests (plan PR 11), following the merged screens'
/// pattern (PR 6/7): fixtures for the pure states, hermetic temp trees for the
/// real iCloud clean path (UUID-named files, the real trash route, no debris
/// left in the user's Trash), and engine-never-reached doubles for the API
/// providers — no OAuth, no network, ever (the plan's stated risk: the
/// server-delete UI is unreachable without registered apps, so it is proven
/// with a fake provider only).
///
/// Selections in the drive fixtures toggle **known fixture ids** (the API
/// groups arrive in unspecified order — `CloudDuplicateGrouper` groups through
/// a dictionary), so no test depends on group order.
@Suite("CloudCleanupViewModel")
@MainActor
struct CloudCleanupViewModelTests {

    // MARK: - Doubles

    /// A fake API provider: the file list and the delete result are fixed by
    /// the test; every delete call is recorded. Nothing leaves the process.
    /// `CloudDeleteFailure` has no public initializer (CleanCore builds rows
    /// internally), so partial per-file failures cannot be fabricated here —
    /// the failure tests cover the whole-call error and the iCloud leg.
    private final class FakeCloudProvider: CloudProvider, @unchecked Sendable {
        let providerName: String
        var listFilesResult: CloudFilePage
        var deleteResult: CloudDeleteResult
        /// A small real delay at the delete/list await points, so re-entrancy
        /// guards are observable.
        let delay: UInt64
        private(set) var deleteCalls: [[String]] = []

        init(providerName: String,
             listFilesResult: CloudFilePage = CloudFilePage(files: [], nextCursor: nil),
             deleteResult: CloudDeleteResult = CloudDeleteResult(succeededIDs: [], failed: []),
             delayMilliseconds: UInt64 = 80) {
            self.providerName = providerName
            self.listFilesResult = listFilesResult
            self.deleteResult = deleteResult
            self.delay = delayMilliseconds * 1_000_000
        }

        func isAuthenticated() async -> Bool { true }
        func authenticate() async throws {}
        func signOut() async throws {}

        func listFiles(cursor: String?) async throws -> CloudFilePage {
            try? await Task.sleep(nanoseconds: delay)
            return listFilesResult
        }

        func delete(fileIDs: [String]) async throws -> CloudDeleteResult {
            deleteCalls.append(fileIDs)
            try? await Task.sleep(nanoseconds: delay)
            return deleteResult
        }
    }

    /// A provider whose `delete` throws — the network/auth failure class.
    private final class FailingDeleteProvider: CloudProvider, @unchecked Sendable {
        let providerName = "OneDrive"
        private struct StubError: LocalizedError { var errorDescription: String? { "Request failed (HTTP 503)." } }
        func isAuthenticated() async -> Bool { true }
        func authenticate() async throws {}
        func signOut() async throws {}
        func listFiles(cursor: String?) async throws -> CloudFilePage { CloudFilePage(files: [], nextCursor: nil) }
        func delete(fileIDs: [String]) async throws -> CloudDeleteResult { throw StubError() }
    }

    private static func makeViewModel(apiProviders: [CloudCleanupViewModel.Provider: any CloudProvider]? = nil)
        -> CloudCleanupViewModel {
        CloudCleanupViewModel(apiProviders: apiProviders)
    }

    private func waitForPhase(_ viewModel: CloudCleanupViewModel,
                              _ expected: CloudCleanupViewModel.Phase,
                              for provider: CloudCleanupViewModel.Provider,
                              timeout: TimeInterval = 10) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if viewModel.phase(of: provider) == expected { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return viewModel.phase(of: provider) == expected
    }

    /// A hermetic one-set iCloud scan: two **real** temp files inside a
    /// UUID-named temp folder (the newest is the keep). The caller removes
    /// the folder and the Trash landings in a `defer` — no debris even when
    /// an expectation fails.
    private struct HermeticSet {
        let extra: ScanItem
        let keep: ScanItem
        let folder: URL

        var items: [ScanItem] { [keep, extra] }

        func cleanup() {
            let fileManager = FileManager.default
            try? fileManager.removeItem(at: folder)
            if let trash = try? fileManager.url(for: .trashDirectory, in: .userDomainMask,
                                                appropriateFor: nil, create: false) {
                for item in [keep, extra] {
                    try? fileManager.removeItem(at: trash.appendingPathComponent((item.path as NSString).lastPathComponent))
                }
            }
        }
    }

    private static func makeHermeticSet() throws -> HermeticSet {
        let fileManager = FileManager.default
        let folder = fileManager.temporaryDirectory
            .appendingPathComponent("cloud-clean-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let payload = Data("sos-mac cloud clean test".utf8)
        var made: [ScanItem] = []
        for (name, modified) in [("keep-\(UUID().uuidString).txt", Date(timeIntervalSinceNow: -60)),
                                 ("extra-\(UUID().uuidString).txt", Date(timeIntervalSinceNow: -3600))] {
            let url = folder.appendingPathComponent(name)
            try payload.write(to: url)
            try fileManager.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
            made.append(ScanItem(path: url.path, size: Int64(payload.count), kind: .file, lastModified: modified))
        }
        return HermeticSet(extra: made[1], keep: made[0], folder: folder)
    }

    /// A `ScanItem` at a unique temp path that is never created — the clean
    /// failure path without touching anything real.
    private static func missingItem(_ index: Int) -> ScanItem {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("cloud-missing-\(UUID().uuidString)-\(index).bin")
            .path
        return ScanItem(path: path, size: Int64(500 + index), kind: .file, sourceLabel: "iCloud Drive")
    }

    // MARK: - Initial state and phases (D5)

    @Test("iCloud Drive starts idle; the three API providers start not configured (D5)")
    func initialPhases() {
        let viewModel = Self.makeViewModel()

        #expect(viewModel.phase(of: .iCloudDrive) == .idle)
        #expect(viewModel.phase(of: .googleDrive) == .notConfigured)
        #expect(viewModel.phase(of: .dropbox) == .notConfigured)
        #expect(viewModel.phase(of: .oneDrive) == .notConfigured)
        #expect(viewModel.selectedProvider == .iCloudDrive)
        #expect(viewModel.lifecycle == .start)
        #expect(!viewModel.isAnyProviderBusy)
    }

    // MARK: - Lifecycle mapping (the pure, unit-tested table)

    @Test("lifecycle mapping: iCloud's eight states map onto the shared frame; notConfigured too")
    func lifecycleMapping() {
        let viewModel = Self.makeViewModel()
        func load(_ phase: CloudCleanupViewModel.Phase) {
            switch phase {
            case .notConfigured: viewModel.loadNotConfiguredFixture(.googleDrive)
            case .idle: viewModel.loadFixture(.start)
            case .scanning: viewModel.loadFixture(.scanning)
            case .results: viewModel.loadFixture(.results)
            case .review: viewModel.loadFixture(.review)
            case .cleaning: viewModel.loadFixture(.cleaning)
            case .done: viewModel.loadFixture(.done)
            case .empty: viewModel.loadFixture(.empty)
            case .failed: viewModel.loadFixture(.error)
            }
        }
        let iCloudExpectations: [(CloudCleanupViewModel.Phase, LifecycleState)] = [
            (.idle, .start),
            (.scanning, .scanning),
            (.results, .results),
            (.review, .review),
            (.cleaning(selectedCount: 2), .cleaning),
            (.done(movedBytes: 10, movedCount: 1, failedCount: 0), .done),
            (.empty, .empty),
            (.failed(message: "reason"), .error),
        ]
        for (phase, expected) in iCloudExpectations {
            load(phase)
            #expect(viewModel.lifecycle == expected,
                    "\(phase) must map to \(expected), got \(viewModel.lifecycle)")
        }
        load(.notConfigured)
        #expect(viewModel.phase(of: .googleDrive) == .notConfigured)
        #expect(viewModel.lifecycle == .start, "notConfigured has no lifecycle of its own — the frame shows start with a disabled CTA")
    }

    @Test("an API provider's results map to .review — the server-delete surface")
    func apiResultsMapToReview() {
        let viewModel = Self.makeViewModel()
        viewModel.loadFixtureAPIResults(.googleDrive, files: UITestFixtures.driveFiles)

        #expect(viewModel.phase(of: .googleDrive) == .results)
        #expect(viewModel.lifecycle == .review)
        #expect(viewModel.selectedProvider == .googleDrive)
    }

    // MARK: - Pre-selection (OD-7) and the keep lock

    @Test("iCloud pre-selects nothing (OD-7); Select All picks extra copies only, never the keep")
    func iCloudPreSelectionIsNothing() {
        let viewModel = Self.makeViewModel()
        viewModel.loadFixture(.results)

        #expect(!viewModel.sets.isEmpty)
        #expect(viewModel.selectedItems.isEmpty, "OD-7: nothing pre-selected in iCloud Drive")

        // Select All: every extra copy of every set, never a keep.
        viewModel.selectAllExtras()
        let extras = viewModel.sets.flatMap(\.extraItems)
        #expect(Set(viewModel.selectedItems.map(\.path)) == Set(extras.map(\.path)))

        // The keep copies refuse a direct toggle.
        for keepPath in viewModel.sets.compactMap(\.keepKey) {
            viewModel.toggleSelection(key: keepPath)
            #expect(!viewModel.selectedItems.contains { $0.path == keepPath })
        }

        viewModel.deselectAll()
        #expect(viewModel.selectedItems.isEmpty)
    }

    @Test("the server-delete surface starts with nothing selected; its keep copies are locked")
    func apiStartsWithNothingSelected() {
        let viewModel = Self.makeViewModel()
        viewModel.loadDriveFixture()

        #expect(viewModel.selectedProvider == .googleDrive)
        #expect(viewModel.selectedFiles.isEmpty, "the drive target shows nothing selected")
        #expect(viewModel.apiSets.count == 3, "the fixture's three content-hash groups")

        // drv-001 is a keep (newest of the brand group): refused.
        viewModel.toggleSelection(key: "drv-001")
        #expect(viewModel.selectedFiles.isEmpty)

        // An extra copy toggles on and off.
        viewModel.toggleSelection(key: "drv-002")
        #expect(viewModel.selectedFiles.map(\.id) == ["drv-002"])
        viewModel.toggleSelection(key: "drv-002")
        #expect(viewModel.selectedFiles.isEmpty)
    }

    // MARK: - iCloud clean: confirmation-first, recompute, failures (S1/S6)

    @Test("nothing is deleted before the confirmation; confirming moves the copy to the Trash (S1)")
    func nothingDeletedBeforeConfirmation() async throws {
        let fileManager = FileManager.default
        let set = try Self.makeHermeticSet()
        defer { set.cleanup() }

        let viewModel = Self.makeViewModel()
        viewModel.loadFixtureResults([DuplicateGroup(id: "set", items: set.items)], listedCount: 2)
        viewModel.toggleSelection(key: set.extra.path)
        #expect(viewModel.selectedItems.count == 1)

        // Building the confirmation deletes nothing — and Cancel never calls it.
        let model = viewModel.iCloudTrashConfirmation(isFromResults: false)
        #expect(model.variant == .trash)
        let state = ConfirmSheetState(model: model)
        state.cancel()
        try await Task.sleep(for: .milliseconds(50))
        #expect(fileManager.fileExists(atPath: set.extra.path), "cancel never removes anything")

        // Confirming (what the sheet's Move to Trash button does) is the only
        // path into the cleaner.
        #expect(state.confirm() != nil)
        #expect(await waitForPhase(viewModel,
                                   .done(movedBytes: set.extra.size, movedCount: 1, failedCount: 0),
                                   for: .iCloudDrive))
        #expect(!fileManager.fileExists(atPath: set.extra.path), "the confirmed copy moved to the Trash")
        #expect(fileManager.fileExists(atPath: set.keep.path), "the keep copy never moves")
    }

    @Test("after a real iCloud clean the groups recompute (S6): a set down to one copy disappears")
    func iCloudGroupsRecomputeAfterClean() async throws {
        let set = try Self.makeHermeticSet()
        defer { set.cleanup() }

        let viewModel = Self.makeViewModel()
        viewModel.loadFixtureResults([DuplicateGroup(id: "set", items: set.items)], listedCount: 2)
        #expect(viewModel.sets.count == 1)
        viewModel.selectAllExtras()
        #expect(viewModel.selectedItems.count == 1, "only the extra copy")

        #expect(await viewModel.cleanICloud())
        #expect(viewModel.sets.isEmpty, "a set with only its keep left is no longer a duplicate set")
        #expect(viewModel.selectedItems.isEmpty)
    }

    @Test("a failed iCloud move is reported on Done, never folded into the moved figures (F4/S6)")
    func iCloudFailuresAreReported() async throws {
        let viewModel = Self.makeViewModel()
        // Three copies in the set: one is the keep (never selectable), two
        // extras are selected and fail.
        let missing = (0..<3).map(Self.missingItem)
        viewModel.loadFixtureResults([DuplicateGroup(id: "set", items: missing)], listedCount: 3)
        viewModel.selectAllExtras()
        #expect(viewModel.selectedItems.count == 2)

        #expect(await viewModel.cleanICloud())
        guard case .done(_, let movedCount, let failedCount) = viewModel.phase(of: .iCloudDrive) else {
            Issue.record("phase should be .done, got \(viewModel.phase(of: .iCloudDrive))")
            return
        }
        #expect(movedCount == 0)
        #expect(failedCount == 2)
        #expect(viewModel.lastFailedItems.count == 2)
    }

    // MARK: - Server-side delete: acknowledgement gate, recompute, failures (S2/S6)

    @Test("the cloud confirm is disabled until the acknowledgement is ticked; confirming calls the provider once (S2)")
    func cloudConfirmRequiresAcknowledgement() async throws {
        let provider = FakeCloudProvider(
            providerName: "Google Drive",
            deleteResult: CloudDeleteResult(succeededIDs: ["drv-002", "drv-003"], failed: []))
        let viewModel = Self.makeViewModel(apiProviders: [.googleDrive: provider])
        viewModel.loadFixtureAPIResults(.googleDrive, files: UITestFixtures.driveFiles)

        // Select the brand group's two extra copies by id (order-independent).
        viewModel.toggleSelection(key: "drv-002")
        viewModel.toggleSelection(key: "drv-003")
        #expect(viewModel.selectedFiles.count == 2)

        let model = viewModel.cloudConfirmation(for: .googleDrive)
        #expect(model.variant == .cloud)
        let state = ConfirmSheetState(model: model)
        #expect(!state.isConfirmEnabled, "the Delete button is disabled until the acknowledgement")

        // A disabled confirm never reaches the provider.
        #expect(state.confirm() == nil)
        #expect(provider.deleteCalls.isEmpty, "nothing is deleted before the confirmation")

        state.toggleAcknowledgement()
        #expect(state.isConfirmEnabled)
        #expect(state.confirm() != nil)

        #expect(await waitForPhase(viewModel,
                                   .done(movedBytes: 1_624_600_000, movedCount: 2, failedCount: 0),
                                   for: .googleDrive))
        #expect(provider.deleteCalls.count == 1)
        #expect(Set(provider.deleteCalls[0]) == ["drv-002", "drv-003"])
        // S6: the groups recompute — the brand group is down to its keep, so
        // only the other two groups remain.
        #expect(viewModel.apiSets.count == 2)
        #expect(viewModel.apiSets.allSatisfy { $0.id != "fixture-hash-brand" })
        #expect(viewModel.selectedFiles.isEmpty)
    }

    @Test("a whole-call delete failure reports every selected file as failed (S6)")
    func apiWholeCallFailure() async throws {
        let provider = FailingDeleteProvider()
        let viewModel = Self.makeViewModel(apiProviders: [.oneDrive: provider])
        viewModel.loadFixtureAPIResults(.oneDrive, files: UITestFixtures.driveFiles)
        viewModel.toggleSelection(key: "drv-002")
        viewModel.toggleSelection(key: "drv-003")

        #expect(await viewModel.deleteFromAPI(.oneDrive) == false)
        guard case .done(_, let movedCount, let failedCount) = viewModel.phase(of: .oneDrive) else {
            Issue.record("phase should be .done, got \(viewModel.phase(of: .oneDrive))")
            return
        }
        #expect(movedCount == 0)
        #expect(failedCount == 2)
        #expect(viewModel.apiDeleteError[.oneDrive] == "Request failed (HTTP 503).")
        #expect(viewModel.apiSets.count == 3, "nothing was deleted, so every group stays")
    }

    // MARK: - API scan with a fake provider (the day-OAuth-lands path)

    @Test("an API provider scan lists, groups and pre-selects nothing")
    func apiScanListsAndGroups() async throws {
        let provider = FakeCloudProvider(
            providerName: "Google Drive",
            listFilesResult: CloudFilePage(files: UITestFixtures.driveFiles, nextCursor: nil))
        let viewModel = Self.makeViewModel(apiProviders: [.googleDrive: provider])
        viewModel.selectProvider(.googleDrive)

        #expect(viewModel.startScan())
        #expect(await waitForPhase(viewModel, .results, for: .googleDrive))

        #expect(viewModel.apiListedCount[.googleDrive] == UITestFixtures.driveFiles.count)
        #expect(viewModel.apiSets.count == 3)
        #expect(viewModel.selectedFiles.isEmpty)
        #expect(viewModel.lifecycle == .review)
    }

    // MARK: - Provider switching keeps per-provider state (§6.6)

    @Test("switching providers keeps each provider's phase, results and selection")
    func providerStateSurvivesSwitching() {
        let viewModel = Self.makeViewModel()
        viewModel.loadDriveFixture()
        viewModel.toggleSelection(key: "drv-002")
        #expect(viewModel.selectedFiles.count == 1)

        viewModel.selectProvider(.iCloudDrive)
        #expect(viewModel.phase(of: .iCloudDrive) == .idle)
        #expect(viewModel.lifecycle == .start)

        viewModel.selectProvider(.googleDrive)
        #expect(viewModel.phase(of: .googleDrive) == .results)
        #expect(viewModel.selectedFiles.map(\.id) == ["drv-002"])
    }

    // MARK: - Fixtures (the snapshot states)

    @Test("the drive fixture reproduces the design target; launch hooks without env are a no-op")
    func driveFixture() {
        let viewModel = Self.makeViewModel()
        viewModel.loadFixtureFromLaunchHooks() // no hooks → no-op
        #expect(viewModel.selectedProvider == .iCloudDrive)

        viewModel.loadDriveFixture()
        #expect(viewModel.selectedProvider == .googleDrive)
        #expect(viewModel.phase(of: .googleDrive) == .results)
        #expect(viewModel.selectedFiles.isEmpty)
        #expect(viewModel.apiSets.count == 3)
    }

    @Test("the not-configured fixtures select the provider and stay honest (D5)")
    func notConfiguredFixtures() {
        let viewModel = Self.makeViewModel()
        viewModel.loadNotConfiguredFixture(.dropbox)
        #expect(viewModel.selectedProvider == .dropbox)
        #expect(viewModel.phase(of: .dropbox) == .notConfigured)
        #expect(viewModel.lifecycle == .start)

        viewModel.loadNotConfiguredFixture(.oneDrive)
        #expect(viewModel.phase(of: .oneDrive) == .notConfigured)
    }

    // MARK: - Re-entrancy (PR 3 guard)

    @Test("a second scan while one runs is refused; the sidebar busy flag reads any provider")
    func reentrancyGuards() async throws {
        let provider = FakeCloudProvider(
            providerName: "Google Drive",
            listFilesResult: CloudFilePage(files: UITestFixtures.driveFiles, nextCursor: nil))
        let viewModel = Self.makeViewModel(apiProviders: [.googleDrive: provider])
        viewModel.selectProvider(.googleDrive)

        #expect(viewModel.startScan())
        #expect(await waitForPhase(viewModel, .scanning, for: .googleDrive),
                "the scan's first hop sets the phase")
        #expect(viewModel.isAnyProviderBusy, "the sidebar busy dot sees the running scan")
        #expect(!viewModel.startScan(), "a second scan while one runs is refused")
        #expect(await waitForPhase(viewModel, .results, for: .googleDrive))
        #expect(!viewModel.isAnyProviderBusy)
    }
}

import Foundation
import SwiftData
import Testing
@testable import SOSMac

/// `Phase → LifecycleState` mapping tables, one suite per screen (the reference
/// pattern from PR 5: every later screen PR appends its suite here, so the shared
/// frame's contract stays covered in one place).
///
/// The mapping is pure and total — every phase maps to exactly one lifecycle state,
/// and the `empty`/`results` distinction (F3) is decided by data, never by a flag.
@Suite("Lifecycle mapping")
struct LifecycleMappingTests {

    @Suite("Junk & Cache")
    @MainActor
    struct JunkCache {

        static func makeViewModel() throws -> JunkCleanerViewModel {
            let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
            let container = try ModelContainer(
                for: IgnoredItem.self, QuarantineRecord.self,
                configurations: configuration
            )
            return JunkCleanerViewModel(modelContext: ModelContext(container))
        }

        /// The whole state table at once: each fixture state sets the phase the spec's
        /// table names, and `lifecycle` must resolve to that state.
        @Test("state table: every lifecycle state maps from the phase spec §5.3 defines")
        func stateTable() throws {
            let viewModel = try Self.makeViewModel()

            #expect(viewModel.phase == .idle)
            #expect(viewModel.lifecycle == .start)

            viewModel.loadFixture(.scanning)
            #expect(viewModel.phase == .scanning)
            #expect(viewModel.lifecycle == .scanning)

            viewModel.loadFixture(.results)
            #expect(viewModel.phase == .results)
            #expect(!viewModel.items.isEmpty)
            #expect(viewModel.lifecycle == .results)

            viewModel.loadFixture(.review)
            #expect(viewModel.phase == .review)
            #expect(viewModel.lifecycle == .review)

            viewModel.loadFixture(.cleaning)
            guard case .cleaning = viewModel.phase else {
                Issue.record("expected .cleaning, got \(viewModel.phase)")
                return
            }
            #expect(viewModel.lifecycle == .cleaning)

            viewModel.loadFixture(.done)
            guard case .done(let movedBytes, let movedCount, let failedCount) = viewModel.phase else {
                Issue.record("expected .done, got \(viewModel.phase)")
                return
            }
            #expect(movedBytes > 0)
            #expect(movedCount > 0)
            #expect(failedCount == 0)
            #expect(viewModel.lifecycle == .done)

            viewModel.loadFixture(.empty)
            #expect(viewModel.phase == .results)
            #expect(viewModel.items.isEmpty)
            #expect(viewModel.lifecycle == .empty)

            viewModel.loadFixture(.error)
            guard case .failed(let message) = viewModel.phase else {
                Issue.record("expected .failed, got \(viewModel.phase)")
                return
            }
            #expect(!message.isEmpty)
            #expect(viewModel.lifecycle == .error)
        }

        /// F3: `empty` is a data condition of `results`, never a separate phase — and a
        /// scan failure can never masquerade as "nothing found".
        @Test("empty means results with no items; a failure is never empty")
        func emptyIsResultsWithNoItems() throws {
            let viewModel = try Self.makeViewModel()

            viewModel.loadFixture(.results)
            #expect(viewModel.lifecycle == .results)

            viewModel.loadFixture(.empty)
            #expect(viewModel.phase == .results)
            #expect(viewModel.items.isEmpty)
            #expect(viewModel.lifecycle == .empty)

            viewModel.loadFixture(.error)
            #expect(viewModel.items.isEmpty)
            #expect(viewModel.lifecycle == .error)
            #expect(viewModel.lifecycle != .empty)
        }

        /// F2: Stop returns to `start` and discards the previous results.
        @Test("Stop returns to start and discards results")
        func stopDiscardsResults() throws {
            let viewModel = try Self.makeViewModel()
            viewModel.loadFixture(.results)
            #expect(!viewModel.items.isEmpty)
            #expect(!viewModel.selectedPaths.isEmpty)

            viewModel.loadFixture(.scanning)
            viewModel.cancelScan()

            #expect(viewModel.phase == .idle)
            #expect(viewModel.lifecycle == .start)
            #expect(viewModel.items.isEmpty)
            #expect(viewModel.selectedPaths.isEmpty)
        }

        /// The frame's subtitle never invents a number: before the first rule
        /// completes the state is still `scanning`, not a partial result.
        @Test("scan progress maps without inventing a total")
        func scanningStateNeedsNoFabricatedTotal() throws {
            let viewModel = try Self.makeViewModel()
            viewModel.loadFixture(.scanning)

            #expect(viewModel.phase == .scanning)
            #expect(viewModel.progressTracker.progress?.totalItems == viewModel.locationCount)
            #expect(viewModel.lifecycle == .scanning)
        }
    }
}

/// PR 16: the per-module dock wording the shared frame reads from `ModuleIdentity.dock`
/// (spec Appendix A — "one verb per idea"). The defaults are the cleaner modules' text, so
/// every screen that does not override a label keeps today's dock exactly.
@Suite("Dock copy (Appendix A)")
struct DockCopyTests {

    private static let cleaners: [SidebarDestination] = [.smartCare, .junkCleaner, .duplicateFinder, .cloudCleanup]

    @Test("cleaner modules keep the frame's default wording", arguments: cleaners)
    func cleanersKeepDefaults(module: SidebarDestination) {
        let dock = ModuleIdentity(module: module).dock
        #expect(dock.resultsAction == "Clean")
        #expect(dock.openReview == "Review Items…")
        #expect(dock.nothingSelectedMeta == "Nothing selected")
        #expect(dock.resultsHint == nil)
        #expect(dock.resultsFinish == "Scan Again")
        #expect(dock.doneAction == "Scan Again")
        #expect(dock.doneSecondary == "Open Trash")
        #expect(dock.emptyAction == "Scan Again")
        #expect(dock == DockCopy())
    }

    @Test("Space Lens: Review…, Scan Again, Choose Folder…")
    func spaceLens() {
        let dock = ModuleIdentity(module: .spaceLens).dock
        #expect(dock.resultsAction == "Review…")
        #expect(dock.openReview == nil)
        #expect(dock.resultsFinish == "Scan Again")
        #expect(dock.doneAction == "Scan Again")
        #expect(dock.doneSecondary == "Open Trash")
        #expect(dock.emptyAction == "Choose Folder…")
    }

    @Test("Uninstaller: Review + hint, Measure Again, Back to Apps, Check Again")
    func uninstaller() {
        let dock = ModuleIdentity(module: .uninstaller).dock
        #expect(dock.resultsAction == "Review")
        #expect(dock.openReview == nil)
        #expect(dock.resultsHint == "Choose an app to review what it left behind")
        #expect(dock.resultsFinish == "Measure Again")
        #expect(dock.doneAction == "Back to Apps")
        #expect(dock.doneSecondary == "Open Trash")
        #expect(dock.emptyAction == "Check Again")
    }

    @Test("Updater: read-only — Check Again, nothing to clean, review or trash")
    func updater() {
        let dock = ModuleIdentity(module: .updater).dock
        #expect(dock.resultsAction == "Check Again")
        #expect(dock.openReview == nil)
        #expect(dock.resultsFinish == nil)
        #expect(dock.doneSecondary == nil)
        #expect(dock.emptyAction == "Check Again")
    }

    @Test("Protection (§5.10): Review + hint, Scan Again, no Open Trash — it quarantines")
    func protection() {
        let dock = ModuleIdentity(module: .protection).dock
        #expect(dock.resultsAction == "Review")
        #expect(dock.openReview == nil)
        #expect(dock.resultsHint == "Review the finding, then quarantine it")
        #expect(dock.resultsFinish == "Scan Again")
        #expect(dock.doneAction == "Scan Again")
        #expect(dock.doneSecondary == nil)
        #expect(dock.emptyAction == "Scan Again")
    }

    @Test("start and review CTA labels are unchanged by the dock copy")
    func startAndReviewLabels() {
        #expect(ModuleIdentity(module: .updater).startActionTitle == "Check")
        #expect(ModuleIdentity(module: .uninstaller).startActionTitle == "Measure All")
        #expect(ModuleIdentity(module: .protection).reviewActionTitle == "Quarantine…")
        #expect(ModuleIdentity(module: .junkCleaner).startActionTitle == "Scan")
        #expect(ModuleIdentity(module: .junkCleaner).reviewActionTitle == "Move to Trash…")
    }

    @Test("Cloud API providers have no Trash to open; iCloud Drive keeps it")
    func cloudDoneSecondary() {
        #expect(CloudCleanupView.frameIdentity(for: .iCloudDrive).dock.doneSecondary == "Open Trash")
        for provider in CloudCleanupViewModel.Provider.allCases where provider != .iCloudDrive {
            #expect(CloudCleanupView.frameIdentity(for: provider).dock.doneSecondary == nil)
        }
    }
}

/// PR 16 (declared extension 2): the orb ring inset is a metric. Every full-size orb keeps the
/// spec's 34 pt; the Dashboard's 112 pt orb passes the prototype's 10 pt.
@Suite("Orb ring inset")
struct OrbRingInsetTests {
    @Test("start, scanning and done orbs keep the 34 pt ring")
    func fullSizeOrbsKeepDefault() {
        #expect(ModuleOrbView.Metrics.start.ringInset == 34)
        #expect(ModuleOrbView.Metrics.scanning.ringInset == 34)
        #expect(ModuleOrbView.Metrics.done.ringInset == 34)
        #expect(ModuleOrbView.Metrics(side: 112, glyphSide: 68, glyphRadius: 18, symbolSize: 34).ringInset == 34)
    }

    @Test("the Dashboard orb's ring sits at 10 pt, inside its 112 pt side")
    func dashboardRing() {
        let metrics = ModuleOrbView.Metrics(side: 112, glyphSide: 68, glyphRadius: 18, symbolSize: 34, ringInset: 10)
        #expect(metrics.ringInset == 10)
        // The ring's diameter must clear the glyph tile (otherwise it hides behind it).
        #expect(metrics.side - 2 * metrics.ringInset > metrics.glyphSide)
    }
}

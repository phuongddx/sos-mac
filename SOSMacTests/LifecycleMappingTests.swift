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

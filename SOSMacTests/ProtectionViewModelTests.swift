import CryptoKit
import Foundation
import SwiftData
import Testing
import CleanCore
@testable import SOSMac

/// Protection view-model tests (plan PR 13): the lifecycle mapping, the re-entrancy guards,
/// nothing-pre-selected, the pure grouping/path helpers and — hermetically — a real scan,
/// quarantine and restore over a UUID-named temp tree with an injected quarantine folder and
/// an in-memory SwiftData store. Nothing here touches a real user path, the real quarantine
/// folder or the real signature feed; the "malware" is a synthetic marker whose hash is
/// injected into a test-only signature database.
@Suite("ProtectionViewModel")
@MainActor
struct ProtectionViewModelTests {

    // MARK: - Fixtures

    static func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: IgnoredItem.self, QuarantineRecord.self,
            configurations: configuration
        )
        return ModelContext(container)
    }

    /// A throwaway scan tree plus its own quarantine folder, both under one UUID-named root.
    struct Sandbox {
        let root: URL
        let scanRoot: URL
        let quarantineRoot: URL
        let badFile: URL
        let cleanFile: URL
        let badContent: Data

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("sosmac-protection-test-\(UUID().uuidString)", isDirectory: true)
            scanRoot = root.appendingPathComponent("Downloads", isDirectory: true)
            quarantineRoot = root.appendingPathComponent("Quarantine", isDirectory: true)
            try FileManager.default.createDirectory(at: scanRoot, withIntermediateDirectories: true)
            badContent = Data("synthetic-test-marker-\(UUID().uuidString)".utf8)
            badFile = scanRoot.appendingPathComponent("marker.bin")
            cleanFile = scanRoot.appendingPathComponent("notes.txt")
            try badContent.write(to: badFile)
            try Data("nothing to see here".utf8).write(to: cleanFile)
        }

        var signatureDatabase: SignatureDatabase {
            let digest = SHA256.hash(data: badContent).map { String(format: "%02x", $0) }.joined()
            return SignatureDatabase(version: 1, knownBadHashes: [digest])
        }

        var location: ProtectionLocation {
            ProtectionLocation(id: "test-downloads", label: "Test Downloads", kind: .directPath(scanRoot.path))
        }

        func cleanUp() {
            try? FileManager.default.removeItem(at: root)
        }
    }

    static func makeViewModel(sandbox: Sandbox, context: ModelContext? = nil) throws -> ProtectionViewModel {
        ProtectionViewModel(
            modelContext: try context ?? makeContext(),
            locations: [sandbox.location],
            signatureDatabase: sandbox.signatureDatabase,
            quarantineManager: QuarantineManager(quarantineDirectory: sandbox.quarantineRoot))
    }

    static func makeFixtureViewModel() throws -> ProtectionViewModel {
        ProtectionViewModel(modelContext: try makeContext(),
                            locations: UITestFixtures.protectionLocations,
                            signatureDatabase: SignatureDatabase(),
                            quarantineManager: QuarantineManager(
                                quarantineDirectory: FileManager.default.temporaryDirectory
                                    .appendingPathComponent("sosmac-protection-unused-\(UUID().uuidString)")))
    }

    /// Waits (bounded) for the scan task to leave `.scanning`.
    static func waitForScan(_ viewModel: ProtectionViewModel) async throws {
        for _ in 0..<200 where viewModel.phase == .scanning {
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    // MARK: - Lifecycle mapping

    @Suite("lifecycle")
    @MainActor
    struct Lifecycle {
        /// The whole state table at once: each fixture state sets the phase the spec's table
        /// names, and `lifecycle` resolves back to that state.
        @Test("every fixture state maps to its lifecycle state", arguments: LifecycleState.allCases)
        func fixtureStatesMap(state: LifecycleState) throws {
            let viewModel = try ProtectionViewModelTests.makeFixtureViewModel()
            viewModel.loadFixture(state)
            #expect(viewModel.lifecycle == state)
        }

        @Test("phases line up with the spec's table")
        func phaseTable() throws {
            let viewModel = try ProtectionViewModelTests.makeFixtureViewModel()

            viewModel.loadFixture(.start)
            #expect(viewModel.phase == .idle)
            viewModel.loadFixture(.scanning)
            #expect(viewModel.phase == .scanning)
            viewModel.loadFixture(.results)
            #expect(viewModel.phase == .results)
            #expect(viewModel.findings.count == 1)
            viewModel.loadFixture(.review)
            #expect(viewModel.phase == .review)
            viewModel.loadFixture(.cleaning)
            #expect(viewModel.phase == .quarantining(selectedCount: 1))
            viewModel.loadFixture(.done)
            #expect(viewModel.phase == .done(quarantinedCount: 1, failedCount: 0))
            viewModel.loadFixture(.error)
            guard case .failed(let message) = viewModel.phase else {
                Issue.record("expected .failed, got \(viewModel.phase)")
                return
            }
            #expect(!message.isEmpty)
        }

        /// F3: `empty` is a data condition of `results`, and a failure can never read as it.
        @Test("empty means results with no findings; a failure is never empty")
        func emptyIsResultsWithNoFindings() throws {
            let viewModel = try ProtectionViewModelTests.makeFixtureViewModel()

            viewModel.loadFixture(.empty)
            #expect(viewModel.phase == .results)
            #expect(viewModel.findings.isEmpty)
            #expect(viewModel.lifecycle == .empty)

            viewModel.loadFixture(.error)
            #expect(viewModel.findings.isEmpty)
            #expect(viewModel.lifecycle == .error)
            #expect(viewModel.lifecycle != .empty)
        }

        /// F2: Stop returns to `start` and discards the previous results too.
        @Test("Stop returns to start and discards results")
        func stopDiscardsResults() throws {
            let viewModel = try ProtectionViewModelTests.makeFixtureViewModel()
            viewModel.loadFixture(.results)
            #expect(!viewModel.findings.isEmpty)

            viewModel.loadFixture(.scanning)
            viewModel.cancelScan()

            #expect(viewModel.phase == .idle)
            #expect(viewModel.lifecycle == .start)
            #expect(viewModel.findings.isEmpty)
            #expect(viewModel.selectedPaths.isEmpty)
            #expect(viewModel.progressTracker.progress == nil)
        }

        @Test("scanning steps follow the engine's current path, in scan order")
        func scanStepsFollowCurrentPath() throws {
            let viewModel = try ProtectionViewModelTests.makeFixtureViewModel()
            viewModel.loadFixture(.scanning)

            let steps = viewModel.scanStepStates
            #expect(steps.map(\.label) == ["Downloads", "User Login Items", "System Login Items",
                                           "System Daemons", "Chrome Extensions", "Firefox Extensions"])
            #expect(steps.map(\.state) == [.done, .done, .done, .active, .pending, .pending])
        }
    }

    // MARK: - Guards and selection

    @Suite("guards")
    @MainActor
    struct Guards {
        @Test("nothing is selected after a fixture load, and Quarantine… needs a selection")
        func nothingPreSelected() throws {
            let viewModel = try ProtectionViewModelTests.makeFixtureViewModel()
            viewModel.loadFixture(.review)

            #expect(viewModel.selectedPaths.isEmpty)
            #expect(viewModel.selectedFindings.isEmpty)
            #expect(viewModel.quarantineConfirmation() == nil)
        }

        @Test("selection is explicit, per finding, and the confirmation carries the same count")
        func explicitSelection() throws {
            let viewModel = try ProtectionViewModelTests.makeFixtureViewModel()
            viewModel.loadFixture(.review)
            let path = try #require(viewModel.findings.first?.path)

            viewModel.toggleSelection(for: path)
            #expect(viewModel.selectedPaths == [path])
            let model = try #require(viewModel.quarantineConfirmation())
            #expect(model.variant == .quarantine)
            #expect(model.count == viewModel.selectedFindings.count)
            #expect(model.items.map(\.id) == [path])

            viewModel.toggleSelection(for: path)
            #expect(viewModel.selectedPaths.isEmpty)

            viewModel.toggleSelection(for: "/not/a/finding")
            #expect(viewModel.selectedPaths.isEmpty)

            viewModel.selectAllInCurrentGroup()
            #expect(viewModel.selectedPaths == [path])
            viewModel.deselectAllInCurrentGroup()
            #expect(viewModel.selectedPaths.isEmpty)
        }

        @Test("scan, quarantine and the list are refused while busy")
        func busyGuards() async throws {
            let viewModel = try ProtectionViewModelTests.makeFixtureViewModel()

            viewModel.loadFixture(.scanning)
            #expect(viewModel.isBusy)
            #expect(viewModel.startScan() == false)
            #expect(await viewModel.quarantineSelected() == false)
            viewModel.showQuarantine()
            #expect(viewModel.isShowingQuarantine == false)

            viewModel.loadFixture(.cleaning)
            #expect(viewModel.isQuarantining)
            #expect(viewModel.startScan() == false)
            #expect(await viewModel.quarantineSelected() == false)
            #expect(viewModel.quarantineConfirmation() == nil)
        }

        @Test("review is only reachable from results with findings")
        func reviewNavigation() throws {
            let viewModel = try ProtectionViewModelTests.makeFixtureViewModel()

            viewModel.loadFixture(.empty)
            viewModel.enterReview()
            #expect(viewModel.phase == .results)

            viewModel.loadFixture(.results)
            viewModel.enterReview()
            #expect(viewModel.phase == .review)
            #expect(viewModel.currentGroup?.id == "downloads")
            viewModel.backToResults()
            #expect(viewModel.phase == .results)
        }

        @Test("the Quarantine sub-screen opens and closes without touching the phase")
        func quarantineSubScreen() throws {
            let viewModel = try ProtectionViewModelTests.makeFixtureViewModel()
            viewModel.loadFixture(.results)

            viewModel.showQuarantine()
            #expect(viewModel.isShowingQuarantine)
            #expect(viewModel.phase == .results)
            viewModel.hideQuarantine()
            #expect(viewModel.isShowingQuarantine == false)
        }
    }

    // MARK: - Pure helpers

    @Suite("helpers")
    @MainActor
    struct Helpers {
        private static let locations = [
            ProtectionViewModel.LocationSummary(id: "downloads", label: "Downloads", roots: ["/Users/sample/Downloads"]),
            ProtectionViewModel.LocationSummary(id: "agents", label: "User Login Items", roots: ["/Users/sample/Library/LaunchAgents/"]),
        ]

        private static func finding(_ path: String) -> ThreatFinding {
            ThreatFinding(path: path, size: 10, detectionMethod: .hash, identifier: "id")
        }

        @Test("a path belongs to a location only on a path boundary")
        func locationBoundary() {
            let locations = Self.locations
            #expect(ProtectionViewModel.locationIndex(forPath: "/Users/sample/Downloads/a.zip", in: locations) == 0)
            #expect(ProtectionViewModel.locationIndex(forPath: "/Users/sample/Downloads", in: locations) == 0)
            #expect(ProtectionViewModel.locationIndex(forPath: "/Users/sample/Downloads2/a.zip", in: locations) == nil)
            #expect(ProtectionViewModel.locationIndex(forPath: "/Users/sample/Library/LaunchAgents/x.plist", in: locations) == 1)
        }

        @Test("groups follow scan order and an unclaimed path is shown, never dropped")
        func groupingFailsClosed() {
            let findings = [
                Self.finding("/Users/sample/Library/LaunchAgents/x.plist"),
                Self.finding("/Users/sample/Downloads/a.zip"),
                Self.finding("/somewhere/else/y.bin"),
            ]
            let groups = ProtectionViewModel.groups(from: findings, locations: Self.locations)

            #expect(groups.map(\.id) == ["downloads", "agents", ProtectionViewModel.fallbackGroupID])
            #expect(groups.map(\.findings.count) == [1, 1, 1])
            #expect(groups.flatMap(\.findings).count == findings.count)
        }

        @Test("a location with no findings gets no group")
        func emptyGroupsOmitted() {
            let groups = ProtectionViewModel.groups(from: [Self.finding("/Users/sample/Downloads/a.zip")],
                                                    locations: Self.locations)
            #expect(groups.map(\.id) == ["downloads"])
        }

        @Test("paths under home are abbreviated, others are left alone")
        func displayPath() {
            #expect(ProtectionViewModel.displayPath("/Users/sample/Downloads/a.zip", home: "/Users/sample") == "~/Downloads/a.zip")
            #expect(ProtectionViewModel.displayPath("/Users/sample", home: "/Users/sample") == "~")
            #expect(ProtectionViewModel.displayPath("/Users/sample2/a", home: "/Users/sample") == "/Users/sample2/a")
            #expect(ProtectionViewModel.displayPath("/Library/LaunchDaemons/x", home: "/Users/sample") == "/Library/LaunchDaemons/x")
        }
    }

    // MARK: - Real scan / quarantine / restore (hermetic)

    @Suite("engine round trip")
    @MainActor
    struct RoundTrip {
        @Test("a real scan finds only the injected signature and selects nothing")
        func scanFindsInjectedSignature() async throws {
            let sandbox = try Sandbox()
            defer { sandbox.cleanUp() }
            let viewModel = try ProtectionViewModelTests.makeViewModel(sandbox: sandbox)

            #expect(viewModel.startScan())
            #expect(viewModel.phase == .scanning)
            try await ProtectionViewModelTests.waitForScan(viewModel)

            #expect(viewModel.phase == .results)
            #expect(viewModel.lifecycle == .results)
            #expect(viewModel.findings.map { ($0.path as NSString).lastPathComponent } == ["marker.bin"])
            #expect(viewModel.selectedPaths.isEmpty)
            #expect(viewModel.checkedFileCount == 2)
            #expect(viewModel.findingGroups.map(\.id) == ["test-downloads"])
        }

        @Test("a clean tree ends in empty, with the engine's file count")
        func cleanTreeIsEmpty() async throws {
            let sandbox = try Sandbox()
            defer { sandbox.cleanUp() }
            try FileManager.default.removeItem(at: sandbox.badFile)
            let viewModel = try ProtectionViewModelTests.makeViewModel(sandbox: sandbox)

            viewModel.startScan()
            try await ProtectionViewModelTests.waitForScan(viewModel)

            #expect(viewModel.lifecycle == .empty)
            #expect(viewModel.checkedFileCount == 1)
        }

        @Test("quarantine moves the file, records it, and restore puts it back")
        func quarantineAndRestore() async throws {
            let sandbox = try Sandbox()
            defer { sandbox.cleanUp() }
            let viewModel = try ProtectionViewModelTests.makeViewModel(sandbox: sandbox)
            viewModel.startScan()
            try await ProtectionViewModelTests.waitForScan(viewModel)
            let path = try #require(viewModel.findings.first?.path)

            viewModel.toggleSelection(for: path)
            #expect(await viewModel.quarantineSelected())

            #expect(viewModel.phase == .done(quarantinedCount: 1, failedCount: 0))
            #expect(viewModel.lifecycle == .done)
            #expect(viewModel.lastFailures.isEmpty)
            #expect(viewModel.findings.isEmpty)
            #expect(viewModel.quarantineProgress == nil)
            #expect(!FileManager.default.fileExists(atPath: sandbox.badFile.path))
            #expect(FileManager.default.fileExists(atPath: sandbox.cleanFile.path))
            let record = try #require(viewModel.quarantinedRecords.first)
            #expect(viewModel.quarantinedRecords.count == 1)
            #expect(record.quarantinePath.hasPrefix(sandbox.quarantineRoot.path))
            #expect(FileManager.default.fileExists(atPath: record.quarantinePath))

            #expect(viewModel.restore(record))
            #expect(viewModel.quarantinedRecords.isEmpty)
            #expect(viewModel.actionError == nil)
            #expect(try Data(contentsOf: sandbox.badFile) == sandbox.badContent)
        }

        @Test("a file that vanished stays listed and is counted as a failure with a reason")
        func failureAccounting() async throws {
            let sandbox = try Sandbox()
            defer { sandbox.cleanUp() }
            let viewModel = try ProtectionViewModelTests.makeViewModel(sandbox: sandbox)
            let ghost = sandbox.scanRoot.appendingPathComponent("ghost.bin").path
            viewModel.loadFixtureResults([
                ThreatFinding(path: ghost, size: 1, detectionMethod: .hash, identifier: "id"),
            ])
            viewModel.toggleSelection(for: ghost)

            #expect(await viewModel.quarantineSelected())

            #expect(viewModel.phase == .done(quarantinedCount: 0, failedCount: 1))
            #expect(viewModel.lastFailures.map(\.name) == ["ghost.bin"])
            #expect(viewModel.lastFailures.first?.reason.isEmpty == false)
            #expect(viewModel.findings.map(\.path) == [ghost])
            #expect(viewModel.quarantinedRecords.isEmpty)
        }

        @Test("restore refuses to overwrite and keeps the record")
        func restoreTargetOccupied() async throws {
            let sandbox = try Sandbox()
            defer { sandbox.cleanUp() }
            let viewModel = try ProtectionViewModelTests.makeViewModel(sandbox: sandbox)
            viewModel.startScan()
            try await ProtectionViewModelTests.waitForScan(viewModel)
            viewModel.toggleSelection(for: try #require(viewModel.findings.first?.path))
            _ = await viewModel.quarantineSelected()
            let record = try #require(viewModel.quarantinedRecords.first)
            try Data("a different file".utf8).write(to: sandbox.badFile)

            #expect(viewModel.restore(record) == false)

            #expect(viewModel.actionError != nil)
            #expect(viewModel.quarantinedRecords.count == 1)
            #expect(FileManager.default.fileExists(atPath: record.quarantinePath))
            #expect(try Data(contentsOf: sandbox.badFile) == Data("a different file".utf8))
        }

        @Test("a second scan after Stop starts clean")
        func rescanAfterStop() async throws {
            let sandbox = try Sandbox()
            defer { sandbox.cleanUp() }
            let viewModel = try ProtectionViewModelTests.makeViewModel(sandbox: sandbox)

            viewModel.startScan()
            viewModel.cancelScan()
            #expect(viewModel.phase == .idle)
            #expect(viewModel.findings.isEmpty)

            viewModel.startScan()
            try await ProtectionViewModelTests.waitForScan(viewModel)
            #expect(viewModel.phase == .results)
            #expect(viewModel.findings.count == 1)
        }
    }
}

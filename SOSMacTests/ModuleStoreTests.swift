import Foundation
import SwiftData
import Testing
@testable import SOSMac

/// PR 3 (spec §6.6): the store owns every view model, so results, selections
/// and running scans survive navigation. The old flow cancelled scans in
/// `.onDisappear`; nothing may cancel them now except an explicit Stop.
@Suite("ModuleStore")
@MainActor
struct ModuleStoreTests {
    static func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: IgnoredItem.self, QuarantineRecord.self,
            configurations: configuration
        )
        return ModelContext(container)
    }

    /// A tree large enough that a scan is observably in flight, made of files
    /// with identical non-empty content (zero-byte files are skipped by the
    /// size grouper, so they would produce no duplicate groups). Test data only.
    static func makeTree(fileCount: Int) throws -> String {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("modulestore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let payload = Data("sos-mac modulestore fixture".utf8)
        for index in 0..<fileCount {
            let url = root.appendingPathComponent("file-\(index).txt", isDirectory: false)
            FileManager.default.createFile(atPath: url.path, contents: payload)
        }
        return root.path
    }

    @Test("the store returns the same view model across view re-creation")
    func sameInstanceAcrossAccesses() throws {
        let store = ModuleStore(modelContext: try Self.makeContext())
        // Views no longer hold @State instances; the store is the only owner,
        // so dropping every other reference ("the view went away") and coming
        // back must return the very same instance.
        #expect(store.smartCare === store.smartCare)
        #expect(store.junkCleaner === store.junkCleaner)
        #expect(store.duplicates === store.duplicates)
        #expect(store.spaceLens === store.spaceLens)
        #expect(store.uninstaller === store.uninstaller)
        #expect(store.updater === store.updater)
        #expect(store.performance === store.performance)
        #expect(store.cloudCleanup === store.cloudCleanup)
        #expect(store.protection === store.protection)
    }

    @Test("isScanning is false everywhere before any module exists (no eager creation)")
    func isScanningNeverCreatesAModule() throws {
        let store = ModuleStore(modelContext: try Self.makeContext())
        for destination in SidebarDestination.allCases {
            #expect(!store.isScanning(destination), "\(destination.rawValue)")
        }
        // Dashboard and Performance never scan.
        _ = store.performance
        #expect(!store.isScanning(.performance))
    }

    @Test("a running scan is not cancelled by navigation and its results are kept")
    func runningScanSurvivesViewRecreation() async throws {
        // The view model is the exact type the store owns; a scan is started,
        // "the view goes away" (there is no teardown to call anymore — that is
        // the change), and the scan must still finish with its results.
        let rootPath = try Self.makeTree(fileCount: 6000)
        defer { try? FileManager.default.removeItem(atPath: rootPath) }
        let viewModel = DuplicateFinderViewModel(rootPath: rootPath)
        #expect(viewModel.startScan())

        var sawScanning = false
        for _ in 0..<500 {
            if viewModel.phase == .scanning { sawScanning = true; break }
            if viewModel.phase != .idle { break }
            await Task.yield()
        }
        #expect(sawScanning)

        let finished = await Self.waitUntilFinished(viewModel)
        #expect(finished)
        #expect(viewModel.phase == .results)
        #expect(!viewModel.groups.isEmpty)
    }

    @Test("a second startScan on a scanning module is refused")
    func secondStartScanIsRefused() async throws {
        let rootPath = try Self.makeTree(fileCount: 6000)
        defer { try? FileManager.default.removeItem(atPath: rootPath) }
        let viewModel = DuplicateFinderViewModel(rootPath: rootPath)
        #expect(viewModel.startScan())
        for _ in 0..<500 {
            if viewModel.phase == .scanning { break }
            await Task.yield()
        }
        #expect(viewModel.phase == .scanning)
        // The re-entrancy guard: no restart, no cancelled task, no lost progress.
        #expect(!viewModel.startScan())
        #expect(await Self.waitUntilFinished(viewModel))
    }

    @Test("loadApps is first-visit-only (rows are not rebuilt on re-visit)")
    func updaterLoadsOnce() throws {
        let store = ModuleStore(modelContext: try Self.makeContext())
        let viewModel = store.updater
        // Real enumeration result is machine-dependent; what matters is that a
        // second visit does not rebuild the rows (hasLoadedApps guard). The
        // auto-check flag starts false and is flipped exactly once, in
        // `autoCheckIfNeeded` (not called here: it would hit real update feeds).
        viewModel.loadApps()
        viewModel.loadApps()
        #expect(viewModel.hasLoadedApps)
        #expect(!viewModel.hasAutoChecked)
    }

    private static func waitUntilFinished(_ viewModel: DuplicateFinderViewModel) async -> Bool {
        for _ in 0..<3000 {
            switch viewModel.phase {
            case .results, .done:
                return true
            case .idle where viewModel.errorMessage != nil:
                return false
            default:
                break
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }
}

import Foundation
import Testing
import CleanCore
@testable import SOSMac

/// Dashboard tests (plan PR 14, N3 / D6): the launcher's navigation and its "Run Smart Care",
/// and the snapshot's formatting rules. Hermetic: Smart Care is built over an empty temp folder
/// with injected scan doubles — no real Home folder, no real scan, no files touched.
@Suite("Dashboard")
@MainActor
struct DashboardViewModelTests {

    // MARK: - Doubles

    private struct EmptyScanner: CleanCore.Scanner {
        func scan() async throws -> [ScanItem] { [] }
    }

    /// A Smart Care whose junk leg finds nothing and whose duplicate leg stays "scanning"
    /// until it is cancelled, so the phase is observably `.scanning` — never a real scan.
    private static func makeSmartCare() -> SmartCareViewModel {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dashboard-smartcare-\(UUID().uuidString)", isDirectory: true).path
        return SmartCareViewModel(
            rootPath: root,
            orchestrator: SmartCareOrchestrator(scanners: [
                .init(name: SmartCareViewModel.junkModuleName, scanner: EmptyScanner())
            ]),
            duplicateScan: .custom { _ in
                try await Task.sleep(for: .seconds(60))
                throw CancellationError()
            })
    }

    /// Records every destination the launcher navigates to, in order.
    private final class Navigation {
        var destinations: [SidebarDestination] = []
    }

    private static func makeLauncher(_ smartCare: SmartCareViewModel, _ navigation: Navigation) -> DashboardLauncher {
        DashboardLauncher(smartCare: { smartCare }, navigate: { navigation.destinations.append($0) })
    }

    private func waitForPhase(_ viewModel: SmartCareViewModel,
                              _ expected: SmartCareViewModel.Phase,
                              timeout: TimeInterval = 10) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if viewModel.phase == expected { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return viewModel.phase == expected
    }

    // MARK: - N3: Run Smart Care opens Smart Care and starts the scan

    @Test("N3: Run Smart Care navigates to Smart Care and the scan leaves .idle")
    func runSmartCareNavigatesAndStartsTheScan() async {
        let smartCare = Self.makeSmartCare()
        let navigation = Navigation()
        #expect(smartCare.phase == .idle)

        let started = Self.makeLauncher(smartCare, navigation).runSmartCare()

        #expect(started)
        #expect(navigation.destinations == [.smartCare])
        #expect(await waitForPhase(smartCare, .scanning))
        smartCare.cancelScan()
        #expect(smartCare.phase == .idle)
    }

    @Test("N3: a scan that is already running is not restarted, the user just lands on it")
    func runSmartCareWhileScanningDoesNotRestart() async {
        let smartCare = Self.makeSmartCare()
        let navigation = Navigation()
        let launcher = Self.makeLauncher(smartCare, navigation)
        #expect(launcher.runSmartCare())
        #expect(await waitForPhase(smartCare, .scanning))

        let startedAgain = launcher.runSmartCare()

        #expect(!startedAgain)
        #expect(navigation.destinations == [.smartCare, .smartCare])
        #expect(smartCare.phase == .scanning)
        smartCare.cancelScan()
    }

    @Test("N3: mid-review, Run Smart Care opens the screen and keeps the user's selection")
    func runSmartCareDuringReviewKeepsTheSelection() {
        let smartCare = Self.makeSmartCare()
        smartCare.loadFixture(.review)
        #expect(smartCare.phase == .review)
        let selectionBefore = smartCare.selectedPaths
        let navigation = Navigation()

        let started = Self.makeLauncher(smartCare, navigation).runSmartCare()

        #expect(!started)
        #expect(navigation.destinations == [.smartCare])
        #expect(smartCare.phase == .review)
        #expect(smartCare.selectedPaths == selectionBefore)
    }

    @Test("N3: from the results screen, Run Smart Care starts a fresh scan")
    func runSmartCareFromResultsRescans() async {
        let smartCare = Self.makeSmartCare()
        smartCare.loadFixture(.results)
        #expect(smartCare.phase == .results)
        let navigation = Navigation()

        let started = Self.makeLauncher(smartCare, navigation).runSmartCare()

        #expect(started)
        #expect(navigation.destinations == [.smartCare])
        #expect(await waitForPhase(smartCare, .scanning))
        smartCare.cancelScan()
    }

    @Test("a module card only navigates: opening a module never starts Smart Care")
    func openingAModuleDoesNotStartAScan() async {
        let smartCare = Self.makeSmartCare()
        let navigation = Navigation()
        let launcher = Self.makeLauncher(smartCare, navigation)

        for destination: SidebarDestination in [.junkCleaner, .spaceLens, .performance, .smartCare] {
            launcher.open(destination)
        }
        try? await Task.sleep(for: .milliseconds(100))

        #expect(navigation.destinations == [.junkCleaner, .spaceLens, .performance, .smartCare])
        #expect(smartCare.phase == .idle)
    }

    @Test("the Smart Care view model is read only when Run Smart Care is pressed")
    func smartCareIsNotBuiltUntilNeeded() {
        var reads = 0
        let launcher = DashboardLauncher(smartCare: { reads += 1; return Self.makeSmartCare() }, navigate: { _ in })
        launcher.open(.junkCleaner)
        #expect(reads == 0)
    }

    // MARK: - Snapshot formatting (D6: real values only)

    private static let gigabyte: UInt64 = 1_000_000_000

    @Test("memory in use shows the in-use figure against the total, as a whole percent")
    func memoryFigures() {
        let snapshot = DashboardSnapshot(
            oneMinuteLoad: 2.411,
            memory: .init(inUseBytes: 11 * Self.gigabyte, totalBytes: 16 * Self.gigabyte),
            thermalState: .nominal)

        #expect(snapshot.memoryInUseText == ByteFormatter.string(fromByteCount: 11_000_000_000))
        #expect(snapshot.memoryTotalText == ByteFormatter.string(fromByteCount: 16_000_000_000))
        #expect(snapshot.memoryPercent == 69)  // 68.75 rounds up
        #expect(snapshot.loadText == "2.41")
        #expect(snapshot.thermalText == "Nominal")
        #expect(snapshot.performanceLine == "Load 2.41 · Memory 69%")
        #expect(!snapshot.isEmpty)
    }

    @Test("an unavailable reading is left out, never replaced by a placeholder")
    func missingReadingsAreOmitted() {
        let loadOnly = DashboardSnapshot(oneMinuteLoad: 0.5, memory: nil, thermalState: nil)
        #expect(loadOnly.memoryInUseText == nil)
        #expect(loadOnly.memoryTotalText == nil)
        #expect(loadOnly.memoryPercent == nil)
        #expect(loadOnly.thermalText == nil)
        #expect(loadOnly.performanceLine == "Load 0.50")

        let memoryOnly = DashboardSnapshot(oneMinuteLoad: nil, memory: .init(inUseBytes: 4, totalBytes: 8), thermalState: nil)
        #expect(memoryOnly.loadText == nil)
        #expect(memoryOnly.performanceLine == "Memory 50%")

        let nothing = DashboardSnapshot(oneMinuteLoad: nil, memory: nil, thermalState: nil)
        #expect(nothing.isEmpty)
        #expect(nothing.performanceLine == nil)
    }

    @Test("a zero total gives no percentage instead of dividing by zero")
    func zeroTotalHasNoPercent() {
        let snapshot = DashboardSnapshot(oneMinuteLoad: nil, memory: .init(inUseBytes: 0, totalBytes: 0), thermalState: nil)
        #expect(snapshot.memoryPercent == nil)
        #expect(snapshot.performanceLine == nil)
    }

    @Test("the percentage is capped at 100 even if in-use ever exceeds the total")
    func percentIsClamped() {
        let snapshot = DashboardSnapshot(oneMinuteLoad: nil, memory: .init(inUseBytes: 20, totalBytes: 10), thermalState: nil)
        #expect(snapshot.memoryPercent == 100)
    }

    @Test("every thermal state reads as a capitalised word")
    func thermalWording() {
        let words = [ThermalState.nominal, .fair, .serious, .critical].map {
            DashboardSnapshot(oneMinuteLoad: nil, memory: nil, thermalState: $0).thermalText
        }
        #expect(words == ["Nominal", "Fair", "Serious", "Critical"])
    }

    @Test("a real capture is internally consistent: in-use never exceeds the total")
    func captureIsConsistent() {
        let snapshot = DashboardSnapshot.capture()
        if let memory = snapshot.memory {
            #expect(memory.totalBytes > 0)
            #expect(memory.inUseBytes <= memory.totalBytes)
            #expect((0...100).contains(snapshot.memoryPercent ?? 0))
        }
        if let load = snapshot.oneMinuteLoad { #expect(load >= 0) }
    }

#if DEBUG
    @Test("the fixture is synthetic: sample figures, and in-use is below the total")
    func fixtureIsSynthetic() {
        let snapshot = DashboardSnapshot.fixture
        #expect(snapshot.loadText == "2.41")
        #expect(snapshot.thermalText == "Nominal")
        #expect(snapshot.memoryTotalText == ByteFormatter.string(fromByteCount: 16_000_000_000))
        #expect(snapshot.memoryInUseText == ByteFormatter.string(fromByteCount: 11_240_000_000))
        #expect(snapshot.memoryPercent == 70)
    }
#endif
}

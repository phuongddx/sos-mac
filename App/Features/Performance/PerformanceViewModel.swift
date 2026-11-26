import AppKit
import Foundation
import Observation
import ServiceManagement
import CleanCore

/// Performance on Palette C (plan PR 12, spec §5.9): a live screen with **no scan lifecycle**.
/// Instead of the scanner `Phase` machine it models two orthogonal things:
///
/// - `metrics: .live / .unavailable` — whether macOS returned the core reads on the latest
///   poll. When it didn't, the screen shows the unavailable banner and every value reads
///   "—" (never a guessed number); polling keeps going, so the next read recovers it.
/// - per maintenance action an `ActionState`: idle · running · needsApproval · succeeded ·
///   failed(message:) — Free up RAM and Flush DNS Cache each carry their own.
///
/// Every figure comes from the injected `Seams` (production: `MachHostStats`, `SysctlReader`,
/// `IOKitSensors`, `LoginItemsManager` — the engine's real APIs). The view model itself never
/// reads a sysctl, calls IOKit or touches `SMAppService` directly, so tests and fixtures run
/// hermetically. The five memory segments do not sum exactly to `totalBytes` (plan risk), so
/// the UI normalises them against their own sum — see `MemorySegments.normalizedFractions`.
///
/// Maintenance routes through the root-only privileged helper. `.needsApproval` is the
/// expected first-run state (`SMAppService.daemon` mandates a System Settings approval, not a
/// failure); the real helper only ever runs from the production closures — tests and fixture
/// mode inject their own operations and can never trigger a system mutation.
@MainActor
@Observable
final class PerformanceViewModel {

    // MARK: - Types

    /// Whether macOS returned the core reads (spec §5.9).
    enum MetricsAvailability: Equatable {
        case live
        case unavailable
    }

    /// State of one maintenance action (spec §5.9).
    enum ActionState: Equatable {
        case idle
        case running
        /// The helper needs approval (or was just registered and does): the row shows the
        /// info banner with the way out — Login Items in System Settings (OD-18).
        case needsApproval
        case succeeded
        case failed(message: String)
    }

    /// The two root-only maintenance actions.
    enum MaintenanceAction: String, CaseIterable {
        case freeRAM
        case flushDNS
    }

    /// One poll's readings, shaped for the UI. App-side value types (constructible in tests
    /// and fixtures); the production adapter in `Seams.live()` fills this from CleanCore's
    /// types by reading their public properties — no engine type is mirrored with new numbers.
    struct Sample: Equatable {
        /// Needs two consecutive ticks to exist; `nil` on the first poll is normal, not an
        /// outage (the card shows "—" until the next interval).
        var cpuUsagePercent: Double?
        var memory: MemorySegments?
        var swap: SwapUsagePair?
        var thermal: ThermalState = .nominal
        var load: LoadAverages?
        var bootTime: Date?
        var isAppleSilicon = false
    }

    /// The five memory segments (spec §5.9). `in use` follows OD-11 / D2: wired + active +
    /// compressed — the legacy `total − free` definition reads ~99 % on an idle Mac and is
    /// never shown here.
    struct MemorySegments: Equatable {
        let wired: UInt64
        let active: UInt64
        let compressed: UInt64
        let inactive: UInt64
        let free: UInt64
        let total: UInt64

        init(wired: UInt64, active: UInt64, compressed: UInt64, inactive: UInt64, free: UInt64, total: UInt64) {
            self.wired = wired
            self.active = active
            self.compressed = compressed
            self.inactive = inactive
            self.free = free
            self.total = total
        }

        /// OD-11: wired + active + compressed, capped at `total` (the segments' accounting
        /// can overshoot by a few pages' worth of kernel reservations).
        var inUseBytes: UInt64 {
            min(total, wired + active + compressed)
        }

        var values: [UInt64] { [wired, active, compressed, inactive, free] }

        /// Fractions for the segmented bar, normalised against the segments' **own sum**, not
        /// against `total`: the five `vm_statistics64` segments don't add up to physical
        /// memory exactly, so dividing by `total` could over- or under-fill the bar (the
        /// plan's stated risk). The fractions always sum to 1; the legend shows the real
        /// bytes, so nothing is invented.
        var normalizedFractions: [Double] {
            let sum = values.reduce(0, +)
            guard sum > 0 else { return values.map { _ in 0 } }
            return values.map { Double($0) / Double(sum) }
        }
    }

    struct SwapUsagePair: Equatable {
        let used: UInt64
        let total: UInt64
    }

    struct LoadAverages: Equatable {
        let oneMinute: Double
        let fiveMinute: Double
        let fifteenMinute: Double
    }

    /// The seams every outside read or privileged action goes through. The defaults are the
    /// production adapters; tests and fixtures inject their own, so nothing hermetic ever
    /// reaches a sysctl, IOKit, `SMAppService` or the helper.
    struct Seams {
        /// The one privileged-helper client for the app session. A `static let` is built on
        /// first access — that is the first real maintenance run, never view-model
        /// construction or a fixture launch.
        @MainActor
        private static let sharedHelperClient = PrivilegedHelperClient()

        var sample: @MainActor () -> Sample
        var purgeRAM: @MainActor () async throws -> Void
        var flushDNS: @MainActor () async throws -> Void
        var registerHelper: @MainActor () throws -> Void
        var openLoginItemsSettings: @MainActor () -> Void
        var loginItems: @MainActor () -> [LoginItemEntry]
        var loginStatus: @MainActor () -> SMAppService.Status
        var setLoginItem: @MainActor (_ enabled: Bool) throws -> Void
        var openMenuBarWidget: @MainActor () throws -> Void

        /// Production adapters. The CPU percentage is diffed from two consecutive
        /// `MachHostStats.cpuTicks()` reads here, so the app-side `Sample` stays a plain
        /// value. `sharedHelperClient` is built lazily on the first real maintenance run —
        /// merely opening the screen never constructs an XPC-ready client.
        static func live() -> Seams {
            var previousTicks: CPUTicks?
            return Seams(
                sample: {
                    var sample = Sample()
                    if let current = MachHostStats.cpuTicks() {
                        if let previous = previousTicks {
                            sample.cpuUsagePercent = MachHostStats.cpuUsagePercent(from: previous, to: current)
                        }
                        previousTicks = current
                    }
                    sample.memory = MachHostStats.memoryInfo().map(MemorySegments.init)
                    sample.swap = SysctlReader.swapUsage().map(SwapUsagePair.init)
                    sample.thermal = IOKitSensors.thermalState()
                    sample.load = SysctlReader.loadAverages().map(LoadAverages.init)
                    sample.bootTime = SysctlReader.bootTime()
                    sample.isAppleSilicon = IOKitSensors.isAppleSilicon()
                    return sample
                },
                purgeRAM: { try await sharedHelperClient.purgeMemory() },
                flushDNS: { try await sharedHelperClient.flushDNSCache() },
                registerHelper: { try sharedHelperClient.register() },
                openLoginItemsSettings: { SMAppService.openSystemSettingsLoginItems() },
                loginItems: { LoginItemsManager.listInstalledAgents() },
                loginStatus: { LoginItemsManager.mainAppLoginItemStatus() },
                setLoginItem: { enabled in
                    if enabled {
                        try LoginItemsManager.registerMainAppAsLoginItem()
                    } else {
                        try LoginItemsManager.unregisterMainAppAsLoginItem()
                    }
                },
                openMenuBarWidget: {
                    // The embedded helper app (see project.yml's post-build script). Until
                    // helper auto-launch ships (needs release-style signing), this is the one
                    // real way to see the widget — the same affordance the old screen had.
                    let helperURL = Bundle.main.bundleURL
                        .appendingPathComponent("Contents/Library/LoginItems/MenuBarHelper.app")
                    guard FileManager.default.fileExists(atPath: helperURL.path) else {
                        throw PrivilegedHelperError.operationFailed("Menu bar widget not found in this build.")
                    }
                    NSWorkspace.shared.open(helperURL)
                })
        }

#if DEBUG
        /// Fixture adapters: no system read, no helper, no System Settings — made-up values
        /// from `UITestFixtures`, an in-memory toggle, recording-free no-ops.
        static func fixture() -> Seams {
            let login = FixtureLoginState()
            return Seams(
                sample: { UITestFixtures.performanceSample() },
                purgeRAM: {},
                flushDNS: {},
                registerHelper: {},
                openLoginItemsSettings: {},
                loginItems: { UITestFixtures.performanceLoginItems() },
                loginStatus: { login.status },
                setLoginItem: { login.enabled = $0 },
                openMenuBarWidget: {})
        }

        /// The fixture toggle's state — a `@MainActor` box so both closures can share it
        /// without sharing a mutable local (a Swift 6 data-race risk the compiler refuses).
        @MainActor
        private final class FixtureLoginState {
            var enabled = true
            var status: SMAppService.Status { enabled ? .enabled : .notRegistered }
        }
#endif
    }

    /// Conservative interval — the old screen's note on battery life stands (spec §5.9:
    /// polling only while the screen is visible is unchanged; SwiftUI's `.task` cancels it).
    private static let pollInterval: Duration = .seconds(2)

    // MARK: - State

    /// The latest poll's readings; `nil` before the first read and in the fixture's
    /// unavailable state (the grid then renders every value as "—").
    private(set) var currentSample: Sample?

    private(set) var metrics: MetricsAvailability = .unavailable
    /// The banner and the "No data" subtitle wait for the first completed read, so opening
    /// the screen never flashes an error for the one frame before polling starts.
    private(set) var hasSampled = false

    private(set) var freeRAMState: ActionState = .idle
    private(set) var flushDNSState: ActionState = .idle

    /// OD-14: this registers the **main app** as a login item; the card's copy says so.
    private(set) var launchAtLoginStatus: SMAppService.Status = .notRegistered
    private(set) var loginItemEntries: [LoginItemEntry] = []
    private(set) var loginItemError: String?
    private(set) var widgetError: String?

    var seams: Seams

    init(seams: Seams? = nil) {
        self.seams = seams ?? Seams.live()
    }

    // MARK: - Sampling

    /// Polls every two seconds while the screen's `.task` is alive (structural cancellation).
    func runPollingLoop() async {
        refreshLoginItems()
        while !Task.isCancelled {
            sampleOnce()
            try? await Task.sleep(for: Self.pollInterval)
        }
    }

    /// One read; also the unavailable banner's "Try Again" action. The loop keeps polling,
    /// so a failed read is retried on the next interval either way.
    func retryReading() {
        sampleOnce()
    }

    func sampleOnce() {
        apply(seams.sample())
    }

    private func apply(_ sample: Sample) {
        currentSample = sample
        metrics = sample.memory != nil ? .live : .unavailable
        hasSampled = true
    }

    private func refreshLoginItems() {
        loginItemEntries = seams.loginItems()
        launchAtLoginStatus = seams.loginStatus()
    }

    // MARK: - Maintenance

    func actionState(of action: MaintenanceAction) -> ActionState {
        switch action {
        case .freeRAM: freeRAMState
        case .flushDNS: flushDNSState
        }
    }

    private func setActionState(_ action: MaintenanceAction, _ state: ActionState) {
        switch action {
        case .freeRAM: freeRAMState = state
        case .flushDNS: flushDNSState = state
        }
    }

    /// Runs one maintenance action. A second run while the action is running is refused
    /// (the row's Run control is already disabled and reads "Running…"). `.requiresApproval`
    /// and a first-use `.notRegistered` land in `.needsApproval` — the expected first-run
    /// state, answered with the info banner and the documented Login Items deep link.
    func run(_ action: MaintenanceAction) async {
        guard actionState(of: action) != .running else { return }
        setActionState(action, .running)
        do {
            switch action {
            case .freeRAM: try await seams.purgeRAM()
            case .flushDNS: try await seams.flushDNS()
            }
            setActionState(action, .succeeded)
        } catch PrivilegedHelperError.requiresApproval {
            enterApproval(action)
        } catch PrivilegedHelperError.notRegistered {
            do {
                try seams.registerHelper()
            } catch {
                setActionState(action, .failed(message: error.localizedDescription))
                return
            }
            enterApproval(action)
        } catch {
            setActionState(action, .failed(message: error.localizedDescription))
        }
    }

    private func enterApproval(_ action: MaintenanceAction) {
        setActionState(action, .needsApproval)
        seams.openLoginItemsSettings()
    }

    /// The approval banner's "Open System Settings" — Login Items has a documented deep
    /// link (OD-18: Full Disk Access and iCloud stay text; this one is a real API).
    func openLoginItemsSettings() {
        seams.openLoginItemsSettings()
    }

    // MARK: - Login item and widget

    /// The "Open at login" switch (OD-14): registers or unregisters the main app.
    func setLoginItem(enabled: Bool) {
        loginItemError = nil
        do {
            try seams.setLoginItem(enabled)
            launchAtLoginStatus = seams.loginStatus()
        } catch {
            loginItemError = error.localizedDescription
        }
    }

    /// "Open Menu Bar Widget": launches the embedded MenuBarHelper.app. Failures surface
    /// next to the card that caused them (spec §4.7), not as a bottom-of-screen line.
    func openMenuBarWidget() {
        widgetError = nil
        do {
            try seams.openMenuBarWidget()
        } catch {
            widgetError = error.localizedDescription
        }
    }
}

// MARK: - Production adapters for CleanCore's types

extension PerformanceViewModel.MemorySegments {
    /// Reads CleanCore's `MemoryInfo` — its memberwise values, no arithmetic of our own
    /// beyond what the struct itself documents.
    init(from info: MemoryInfo) {
        self.init(wired: info.wiredBytes,
                  active: info.activeBytes,
                  compressed: info.compressedBytes,
                  inactive: info.inactiveBytes,
                  free: info.freeBytes,
                  total: info.totalBytes)
    }
}

extension PerformanceViewModel.SwapUsagePair {
    init(from swap: SysctlReader.SwapUsage) {
        self.init(used: swap.usedBytes, total: swap.totalBytes)
    }
}

extension PerformanceViewModel.LoadAverages {
    init(from averages: (oneMinute: Double, fiveMinute: Double, fifteenMinute: Double)) {
        self.init(oneMinute: averages.oneMinute,
                  fiveMinute: averages.fiveMinute,
                  fifteenMinute: averages.fifteenMinute)
    }
}

// MARK: - Fixtures (Debug builds only)

#if DEBUG
extension PerformanceViewModel {
    /// The launch-hook half of the fixture convention (`SOSMAC_UITEST_FIXTURES=1`,
    /// `SOSMAC_UITEST_SCREEN=performance`, `SOSMAC_UITEST_STATE=…`). Never starts the
    /// polling loop: the caller (the screen's `.task`) returns before `runPollingLoop`.
    func loadFixtureFromLaunchHooks() {
        let hooks = UITestHooks.current
        guard hooks.fixtures, hooks.destination == .performance, let state = hooks.state else { return }
        loadFixture(state: state.lowercased())
    }

    /// Snapshot states (plan PR 12): `live`, `running`, `approval`, `actiondone`,
    /// `actionerror`, `unavailable`. Fixture seams are installed first, so even a Run
    /// pressed by hand in fixture mode can never reach the real helper.
    func loadFixture(state: String) {
        seams = Seams.fixture()
        switch state {
        case "live":
            applyFixtureSample()
        case "running":
            applyFixtureSample()
            freeRAMState = .running
        case "approval":
            applyFixtureSample()
            freeRAMState = .needsApproval
        case "actiondone":
            applyFixtureSample()
            freeRAMState = .succeeded
        case "actionerror":
            applyFixtureSample()
            flushDNSState = .failed(message: "The helper didn't respond.")
        case "unavailable":
            currentSample = nil
            metrics = .unavailable
            hasSampled = true
            loginItemEntries = UITestFixtures.performanceLoginItems()
            launchAtLoginStatus = .enabled
        default:
            break
        }
    }

    private func applyFixtureSample() {
        apply(UITestFixtures.performanceSample())
        loginItemEntries = UITestFixtures.performanceLoginItems()
        launchAtLoginStatus = .enabled
    }
}
#endif

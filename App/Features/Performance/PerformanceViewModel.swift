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
        /// `nil` until the silicon read has landed — fail closed: the table dashes
        /// Architecture instead of guessing a chip family.
        var isAppleSilicon: Bool?
    }

    /// The five memory segments (spec §5.9). `in use` follows OD-11 / D2 and is carried
    /// from CleanCore's `MemoryInfo.inUseBytes` (wired + active + compressed, capped at
    /// total) — the legacy `total − free` definition reads ~99 % on an idle Mac and is
    /// never shown here, and the app-side type re-derives nothing.
    struct MemorySegments: Equatable {
        let wired: UInt64
        let active: UInt64
        let compressed: UInt64
        let inactive: UInt64
        let free: UInt64
        let total: UInt64
        /// The OD-11 "in use" figure **as CleanCore computed it** (`MemoryInfo.inUseBytes`:
        /// wired + active + compressed, capped at `total`), carried verbatim from the read.
        /// CleanCore is the single source of truth for the definition — the app never
        /// re-derives it (review fix: the old computed property duplicated the formula).
        let inUseBytes: UInt64

        init(wired: UInt64, active: UInt64, compressed: UInt64, inactive: UInt64, free: UInt64, total: UInt64,
             inUseBytes: UInt64) {
            self.wired = wired
            self.active = active
            self.compressed = compressed
            self.inactive = inactive
            self.free = free
            self.total = total
            self.inUseBytes = inUseBytes
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
        /// Called once per polling start: production drops the CPU tick baseline so the
        /// first read after (re)entering the screen diffs over the next ~2 s interval,
        /// not over the whole away period. Tests observe the call through this seam.
        var resetCPUBaseline: @MainActor () -> Void
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
            // A `@MainActor` box for the CPU tick baseline — both closures share it without
            // sharing a mutable local (a Swift 6 data-race risk the compiler refuses; same
            // pattern as `FixtureLoginState`).
            let baseline = BaselineBox()
            // Architecture and boot time cannot change while the app runs; the old screen
            // read them once per polling start, so the first successful read is cached for
            // the VM's lifetime (review fix: they were re-read on every 2 s poll). Fail
            // closed: until a read lands the value stays `nil` and renders "—" — never a
            // guess. An unreadable `hw.optional.arm64` read retries on the next poll —
            // the cache below only latches successful reads.
            var cachedBootTime: Date?
            var cachedIsAppleSilicon: Bool?
            return Seams(
                sample: {
                    var sample = Sample()
                    if let current = MachHostStats.cpuTicks() {
                        if let previous = baseline.previousTicks {
                            sample.cpuUsagePercent = MachHostStats.cpuUsagePercent(from: previous, to: current)
                        }
                        baseline.previousTicks = current
                    }
                    sample.memory = MachHostStats.memoryInfo().map(MemorySegments.init)
                    sample.swap = SysctlReader.swapUsage().map(SwapUsagePair.init)
                    sample.thermal = IOKitSensors.thermalState()
                    sample.load = SysctlReader.loadAverages().map(LoadAverages.init)
                    if cachedBootTime == nil { cachedBootTime = SysctlReader.bootTime() }
                    sample.bootTime = cachedBootTime
                    if cachedIsAppleSilicon == nil { cachedIsAppleSilicon = IOKitSensors.isAppleSilicon() }
                    sample.isAppleSilicon = cachedIsAppleSilicon
                    return sample
                },
                resetCPUBaseline: { baseline.previousTicks = nil },
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

        /// The live seams' CPU tick baseline — same `@MainActor`-box pattern as
        /// `FixtureLoginState`: the sample and reset closures share the box, not a
        /// mutable local.
        @MainActor
        private final class BaselineBox {
            var previousTicks: CPUTicks?
        }

#if DEBUG
        /// Fixture adapters: no system read, no helper, no System Settings — made-up values
        /// from `UITestFixtures`, an in-memory toggle, recording-free no-ops.
        static func fixture() -> Seams {
            let login = FixtureLoginState()
            return Seams(
                sample: { UITestFixtures.performanceSample() },
                resetCPUBaseline: {},
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
        // Review fix: the CPU tick baseline belonged to the VM (it lives in ModuleStore),
        // so the first reading after returning to the screen averaged over the whole away
        // period. Each polling start drops the baseline — the next interval reads fresh.
        seams.resetCPUBaseline()
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

    /// Deliberate deviation from the old screen (gallery README): the state alone flips to
    /// `.needsApproval` — System Settings is **not** auto-opened. A system pane opening by
    /// itself is a surprise system-UI action; the banner's explicit "Open System Settings"
    /// button is the one way in.
    private func enterApproval(_ action: MaintenanceAction) {
        setActionState(action, .needsApproval)
    }

    /// The approval banner's "Open System Settings" — user-initiated, and Login Items has
    /// a documented deep link (OD-18: Full Disk Access and iCloud stay text; this one is a
    /// real API). The old screen also fired this the moment a run needed approval; that
    /// auto-open is removed.
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
    /// Reads CleanCore's `MemoryInfo` — its memberwise values plus the engine's own
    /// `inUseBytes`; no arithmetic of our own anywhere.
    init(from info: MemoryInfo) {
        self.init(wired: info.wiredBytes,
                  active: info.activeBytes,
                  compressed: info.compressedBytes,
                  inactive: info.inactiveBytes,
                  free: info.freeBytes,
                  total: info.totalBytes,
                  inUseBytes: info.inUseBytes)
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
    func loadFixtureFromLaunchHooks(_ hooks: UITestHooks = UITestHooks.current) {
        guard hooks.fixtures, hooks.destination == .performance else { return }
        guard let state = hooks.state else {
            // Review fix: the fixture seams install whenever the performance key matches —
            // even with no state — so a DEBUG launch hook can never leave the real
            // (privileged) seams in place.
            seams = Seams.fixture()
            return
        }
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
            // The real seams return a non-nil partial sample when the memory read fails
            // (`apply` gates on `memory == nil`), so the fixture models exactly that —
            // a nil sample here would mask the screen's own gating (review fix).
            apply(UITestFixtures.performanceUnavailableSample())
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

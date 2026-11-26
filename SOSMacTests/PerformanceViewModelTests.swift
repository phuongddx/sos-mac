import Foundation
import Testing
import ServiceManagement
import CleanCore
@testable import SOSMac

/// Performance view-model tests (plan PR 12, spec §5.9): the `metrics: .live / .unavailable`
/// rule, the CPU two-sample diff, the OD-11 `in use` definition and the segment
/// normalisation (the segments don't sum exactly to total — the plan's stated risk), and
/// the per-action `ActionState` transitions including the approval flow. Hermetic: every
/// read and every privileged operation is an injected closure — no sysctl, no IOKit, no
/// `SMAppService` call, no helper connection, no System Settings deep link.
@Suite("PerformanceViewModel")
@MainActor
struct PerformanceViewModelTests {

    private typealias VM = PerformanceViewModel
    private typealias Segments = VM.MemorySegments

    // MARK: - Fixtures

    /// A thrown error with a stable message (the state's `failed` payload).
    private struct TestFailure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private nonisolated static let segments = Segments(
        wired: 30, active: 30, compressed: 30, inactive: 5, free: 5, total: 200, inUseBytes: 90)

    private nonisolated static func sample(cpu: Double? = 23,
                                           memory: Segments? = segments) -> VM.Sample {
        VM.Sample(cpuUsagePercent: cpu,
                  memory: memory,
                  swap: VM.SwapUsagePair(used: 1_250_000_000, total: 2_150_000_000),
                  thermal: .nominal,
                  load: VM.LoadAverages(oneMinute: 2.41, fiveMinute: 2.88, fifteenMinute: 3.02),
                  bootTime: Date(timeIntervalSince1970: 1_800_000_000),
                  isAppleSilicon: true)
    }

    /// Records which side effects fired (System Settings, helper registration, widget).
    @MainActor
    private final class Probe {
        private(set) var calls: [String] = []
        func record(_ name: String) { calls.append(name) }
        func count(_ name: String) -> Int { calls.filter { $0 == name }.count }
    }

    /// Holds one maintenance operation open until the test releases it.
    @MainActor
    private final class Gate {
        private(set) var heldCount = 0
        private var continuation: CheckedContinuation<Void, Never>?

        func hold() async {
            heldCount += 1
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                self.continuation = continuation
            }
        }

        func release() {
            continuation?.resume()
            continuation = nil
        }
    }

    private func makeViewModel(
        sample: @escaping @MainActor () -> VM.Sample = { Self.sample() },
        resetCPUBaseline: @escaping @MainActor () -> Void = {},
        purgeRAM: @escaping @MainActor () async throws -> Void = {},
        flushDNS: @escaping @MainActor () async throws -> Void = {},
        registerHelper: @escaping @MainActor () throws -> Void = {},
        openLoginItemsSettings: @escaping @MainActor () -> Void = {},
        loginStatus: @escaping @MainActor () -> SMAppService.Status = { .notRegistered },
        setLoginItem: @escaping @MainActor (_ enabled: Bool) throws -> Void = { _ in },
        openMenuBarWidget: @escaping @MainActor () throws -> Void = {}
    ) -> VM {
        VM(seams: VM.Seams(
            sample: sample,
            resetCPUBaseline: resetCPUBaseline,
            purgeRAM: purgeRAM,
            flushDNS: flushDNS,
            registerHelper: registerHelper,
            openLoginItemsSettings: openLoginItemsSettings,
            loginItems: { [] },
            loginStatus: loginStatus,
            setLoginItem: setLoginItem,
            openMenuBarWidget: openMenuBarWidget))
    }

    private func wait(until condition: () -> Bool, timeout: TimeInterval = 5) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    // MARK: - Sampling and availability

    @Test("First poll has no CPU percentage; the diff appears on the second")
    func cpuPercentageNeedsTwoSamples() async {
        let readings: [VM.Sample] = [
            Self.sample(cpu: nil),
            Self.sample(cpu: 42)
        ]
        var index = 0
        let viewModel = makeViewModel(sample: {
            defer { index += 1 }
            return readings[index]
        })
        viewModel.sampleOnce()
        #expect(viewModel.currentSample?.cpuUsagePercent == nil)
        #expect(viewModel.metrics == .live)
        viewModel.sampleOnce()
        #expect(viewModel.currentSample?.cpuUsagePercent == 42)
        #expect(viewModel.metrics == .live)
    }

    @Test("A memory read that comes back nil marks metrics unavailable; a retry recovers")
    func unavailableAndRetry() async {
        var failRead = true
        let viewModel = makeViewModel(sample: {
            Self.sample(memory: failRead ? nil : Self.segments)
        })
        viewModel.sampleOnce()
        #expect(viewModel.metrics == .unavailable)
        #expect(viewModel.hasSampled)
        failRead = false
        viewModel.retryReading()
        #expect(viewModel.metrics == .live)
        #expect(viewModel.currentSample?.memory != nil)
    }

    @Test("A polling start resets the CPU baseline: the first read carries no percentage")
    func pollingStartResetsCPUBaseline() async {
        let probe = Probe()
        let readings: [VM.Sample] = [Self.sample(cpu: nil), Self.sample(cpu: 42)]
        var index = 0
        let viewModel = makeViewModel(sample: {
            probe.record("sample")
            defer { index += 1 }
            return index < readings.count ? readings[index] : readings[readings.count - 1]
        }, resetCPUBaseline: { probe.record("reset") })

        let task = Task { await viewModel.runPollingLoop() }
        let sampled = await wait(until: { probe.count("sample") == 1 })
        // The loop sleeps pollInterval (2 s) between reads, so exactly one read has run;
        // cancel before the second to keep the observation deterministic.
        task.cancel()
        await task.value

        #expect(sampled)
        #expect(probe.calls.first == "reset")   // the baseline drops before the first read
        #expect(probe.count("reset") == 1)      // once per polling start, not per read
        #expect(viewModel.currentSample?.cpuUsagePercent == nil)  // fresh baseline → no diff
        #expect(viewModel.metrics == .live)
    }

    // MARK: - Unavailable gating (review fixes)

    @Test("A partial sample marks metrics unavailable and dashes the system table")
    func partialSampleIsUnavailableAndTableDashes() {
        // The real seams return a non-nil partial sample when the memory read fails:
        // swap, architecture and boot time present, memory nil, no CPU diff yet. The
        // table must gate on the same unavailable flag as every other card.
        let partial = Self.sample(cpu: nil, memory: nil)
        let viewModel = makeViewModel(sample: { partial })
        viewModel.sampleOnce()
        #expect(viewModel.currentSample != nil)
        #expect(viewModel.metrics == .unavailable)
        #expect(viewModel.hasSampled)

        let gated = PerformanceMetricGrid.systemTableValues(sample: viewModel.currentSample,
                                                            showsUnavailable: true)
        #expect(gated.swapUsed == nil)
        #expect(gated.architecture == nil)
        #expect(gated.runningSince == nil)

        // The same sample without the gate shows the reads that did land — the dashes
        // come from the gating, not from empty data.
        let ungated = PerformanceMetricGrid.systemTableValues(sample: viewModel.currentSample,
                                                              showsUnavailable: false)
        #expect(ungated.swapUsed != nil)
        #expect(ungated.architecture != nil)
        #expect(ungated.runningSince != nil)
    }

    @Test("An unread silicon read dashes Architecture instead of guessing a chip family")
    func architectureFailsClosedWhenSiliconUnread() {
        var partial = Self.sample(cpu: nil, memory: nil)
        partial.isAppleSilicon = nil
        let values = PerformanceMetricGrid.systemTableValues(sample: partial, showsUnavailable: false)
        #expect(values.architecture == nil)
        #expect(values.swapUsed != nil)
        #expect(values.runningSince != nil)
    }

    // MARK: - Memory definitions (OD-11 / D2, plan risk)

    @Test("in use is the engine's figure carried verbatim — the app never re-derives it")
    func inUseIsCarriedNotReDerived() {
        // CleanCore owns the OD-11 formula (wired + active + compressed, capped at total;
        // MachHostStatsTests covers it). The app-side segments carry the engine's value:
        // a re-derived min(total, wired + active + compressed) would read 90, not 42.
        let carried = Segments(wired: 30, active: 30, compressed: 30, inactive: 5, free: 5,
                               total: 200, inUseBytes: 42)
        #expect(carried.inUseBytes == 42)
    }

    @Test("Segment fractions normalise against the segments' own sum, not total")
    func segmentsNormaliseToTheirOwnSum() {
        // The five segments sum to 100 against a 200 total: dividing by total would leave
        // the bar half empty (the plan's stated risk).
        let fractions = Self.segments.normalizedFractions
        #expect(fractions == [0.3, 0.3, 0.3, 0.05, 0.05])
        #expect(abs(fractions.reduce(0, +) - 1) < 1e-12)
    }

    // MARK: - Maintenance: succeeded / failed

    @Test("Free up RAM succeeds and leaves Flush DNS Cache idle")
    func freeRAMSucceeds() async {
        let viewModel = makeViewModel()
        await viewModel.run(.freeRAM)
        #expect(viewModel.actionState(of: .freeRAM) == .succeeded)
        #expect(viewModel.actionState(of: .flushDNS) == .idle)
    }

    @Test("A failed action carries the engine's message and doesn't touch the other action")
    func failedActionCarriesMessage() async {
        let viewModel = makeViewModel(
            purgeRAM: { throw TestFailure(message: "The helper didn't respond.") },
            flushDNS: { throw TestFailure(message: "The helper refused the request.") })
        await viewModel.run(.freeRAM)
        #expect(viewModel.actionState(of: .freeRAM) == .failed(message: "The helper didn't respond."))
        await viewModel.run(.flushDNS)
        #expect(viewModel.actionState(of: .flushDNS) == .failed(message: "The helper refused the request."))
        #expect(viewModel.actionState(of: .freeRAM) == .failed(message: "The helper didn't respond."))
    }

    @Test("A second run while the action is running is refused")
    func secondRunWhileRunningIsRefused() async {
        let gate = Gate()
        let viewModel = makeViewModel(purgeRAM: { await gate.hold() })
        let task = Task { await viewModel.run(.freeRAM) }
        let started = await wait(until: { viewModel.actionState(of: .freeRAM) == .running })
        #expect(started)

        await viewModel.run(.freeRAM) // the guard refuses this — the op must not run twice
        #expect(gate.heldCount == 1)

        gate.release()
        await task.value
        #expect(viewModel.actionState(of: .freeRAM) == .succeeded)
    }

    // MARK: - Maintenance: the approval flow

    @Test("requiresApproval lands in needsApproval without opening System Settings")
    func requiresApprovalDoesNotOpenSettings() async {
        let probe = Probe()
        let viewModel = makeViewModel(
            purgeRAM: { throw PrivilegedHelperError.requiresApproval },
            openLoginItemsSettings: { probe.record("settings") })
        await viewModel.run(.freeRAM)
        #expect(viewModel.actionState(of: .freeRAM) == .needsApproval)
        // Deliberate deviation from the old screen (gallery README): no auto-open — the
        // banner's explicit button is the one way in.
        #expect(probe.calls.isEmpty)
    }

    @Test("notRegistered registers the helper first, then asks for approval — still no auto-open")
    func notRegisteredRegistersThenAsksForApproval() async {
        let probe = Probe()
        let viewModel = makeViewModel(
            flushDNS: { throw PrivilegedHelperError.notRegistered },
            registerHelper: { probe.record("register") },
            openLoginItemsSettings: { probe.record("settings") })
        await viewModel.run(.flushDNS)
        #expect(viewModel.actionState(of: .flushDNS) == .needsApproval)
        #expect(probe.count("register") == 1)
        #expect(probe.count("settings") == 0)
    }

    @Test("The banner's Open System Settings button is the one way in")
    func openSettingsButtonOpensSettings() {
        let probe = Probe()
        let viewModel = makeViewModel(openLoginItemsSettings: { probe.record("settings") })
        viewModel.openLoginItemsSettings()
        #expect(probe.count("settings") == 1)
    }

    @Test("A failed registration fails the action with the reason")
    func failedRegistrationFailsTheAction() async {
        let viewModel = makeViewModel(
            purgeRAM: { throw PrivilegedHelperError.notRegistered },
            registerHelper: { throw TestFailure(message: "Couldn't install the privileged helper.") })
        await viewModel.run(.freeRAM)
        #expect(viewModel.actionState(of: .freeRAM) == .failed(message: "Couldn't install the privileged helper."))
    }

    // MARK: - Login item and widget

    @Test("The login switch updates the status and reports no error on success")
    func loginToggleSucceeds() {
        var enabled = false
        let viewModel = makeViewModel(
            loginStatus: { enabled ? .enabled : .notRegistered },
            setLoginItem: { enabled = $0 })
        viewModel.setLoginItem(enabled: true)
        #expect(viewModel.launchAtLoginStatus == .enabled)
        #expect(viewModel.loginItemError == nil)
        viewModel.setLoginItem(enabled: false)
        #expect(viewModel.launchAtLoginStatus == .notRegistered)
    }

    @Test("A failed login registration surfaces an error and keeps the old status")
    func loginToggleFailureSurfacesError() {
        let viewModel = makeViewModel(
            setLoginItem: { _ in throw TestFailure(message: "Registration failed.") })
        viewModel.setLoginItem(enabled: true)
        #expect(viewModel.loginItemError == "Registration failed.")
        #expect(viewModel.launchAtLoginStatus == .notRegistered)
    }

    @Test("A widget open failure surfaces next to the card; success clears it")
    func widgetErrorAndSuccess() {
        var shouldFail = true
        let viewModel = makeViewModel(openMenuBarWidget: {
            if shouldFail { throw TestFailure(message: "Menu bar widget not found in this build.") }
        })
        viewModel.openMenuBarWidget()
        #expect(viewModel.widgetError == "Menu bar widget not found in this build.")
        shouldFail = false
        viewModel.openMenuBarWidget()
        #expect(viewModel.widgetError == nil)
    }

    // MARK: - Fixtures (Debug builds only)

    @Test("Fixture states set the documented actions and sample, and never read the machine")
    func fixtureStates() async {
        let live = VM()
        live.loadFixture(state: "live")
        #expect(live.currentSample?.cpuUsagePercent == 23)
        #expect(live.metrics == .live)
        #expect(live.actionState(of: .freeRAM) == .idle)
        #expect(live.launchAtLoginStatus == .enabled)
        #expect(live.loginItemEntries.isEmpty == false)
        // The fixture seams are installed: a Run in fixture mode succeeds without the helper.
        await live.run(.flushDNS)
        #expect(live.actionState(of: .flushDNS) == .succeeded)

        let running = VM()
        running.loadFixture(state: "running")
        #expect(running.actionState(of: .freeRAM) == .running)

        let approval = VM()
        approval.loadFixture(state: "approval")
        #expect(approval.actionState(of: .freeRAM) == .needsApproval)

        let actionDone = VM()
        actionDone.loadFixture(state: "actiondone")
        #expect(actionDone.actionState(of: .freeRAM) == .succeeded)

        let actionError = VM()
        actionError.loadFixture(state: "actionerror")
        #expect(actionError.actionState(of: .flushDNS) == .failed(message: "The helper didn't respond."))

        let unavailable = VM()
        unavailable.loadFixture(state: "unavailable")
        // The fixture now carries the real shape: a non-nil partial sample (memory nil,
        // the rest present) that the screen's own gating dashes (review fix — a nil
        // sample here masked the gating bug).
        #expect(unavailable.currentSample != nil)
        #expect(unavailable.currentSample?.memory == nil)
        #expect(unavailable.metrics == .unavailable)
        #expect(unavailable.hasSampled)
    }

    @Test("Fixture launch hooks with no state still install the fixture seams")
    func launchHookWithoutStateInstallsFixtureSeams() {
        let hooks = UITestHooks(environment: [
            "SOSMAC_UITEST_FIXTURES": "1",
            "SOSMAC_UITEST_SCREEN": "performance",
        ])
        let viewModel = makeViewModel(openMenuBarWidget: {
            throw TestFailure(message: "real seams reached")
        })
        viewModel.loadFixtureFromLaunchHooks(hooks)
        viewModel.openMenuBarWidget()  // the fixture seams' no-op: nothing throws
        #expect(viewModel.widgetError == nil)
        #expect(viewModel.hasSampled == false)  // no state → nothing applied, seams swapped only
    }

    @Test("Launch hooks that don't match the performance screen leave the seams alone")
    func launchHookMismatchKeepsInjectedSeams() {
        let environments: [[String: String]] = [
            ["SOSMAC_UITEST_SCREEN": "performance"],                            // fixtures off
            ["SOSMAC_UITEST_FIXTURES": "1", "SOSMAC_UITEST_SCREEN": "updater"], // another screen
        ]
        for environment in environments {
            let hooks = UITestHooks(environment: environment)
            let viewModel = makeViewModel(openMenuBarWidget: {
                throw TestFailure(message: "injected seams still in place")
            })
            viewModel.loadFixtureFromLaunchHooks(hooks)
            viewModel.openMenuBarWidget()
            #expect(viewModel.widgetError == "injected seams still in place")
        }
    }
}

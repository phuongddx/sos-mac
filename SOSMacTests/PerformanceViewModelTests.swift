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
        wired: 30, active: 30, compressed: 30, inactive: 5, free: 5, total: 200)

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

    // MARK: - Memory definitions (OD-11 / D2, plan risk)

    @Test("in use is wired + active + compressed, not total − free")
    func inUseFollowsOD11() {
        // wired 30 + active 30 + compressed 30 = 90; the legacy "total − free" would read 195.
        #expect(Self.segments.inUseBytes == 90)
    }

    @Test("in use is capped at total when the segments' accounting overshoots")
    func inUseCappedAtTotal() {
        let overshooting = Segments(wired: 30, active: 30, compressed: 30, inactive: 5, free: 5, total: 50)
        #expect(overshooting.inUseBytes == 50)
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

    @Test("requiresApproval lands in needsApproval and opens Login Items settings")
    func requiresApprovalOpensSettings() async {
        let probe = Probe()
        let viewModel = makeViewModel(
            purgeRAM: { throw PrivilegedHelperError.requiresApproval },
            openLoginItemsSettings: { probe.record("settings") })
        await viewModel.run(.freeRAM)
        #expect(viewModel.actionState(of: .freeRAM) == .needsApproval)
        #expect(probe.count("settings") == 1)
    }

    @Test("notRegistered registers the helper first, then asks for approval")
    func notRegisteredRegistersThenAsksForApproval() async {
        let probe = Probe()
        let viewModel = makeViewModel(
            flushDNS: { throw PrivilegedHelperError.notRegistered },
            registerHelper: { probe.record("register") },
            openLoginItemsSettings: { probe.record("settings") })
        await viewModel.run(.flushDNS)
        #expect(viewModel.actionState(of: .flushDNS) == .needsApproval)
        #expect(probe.count("register") == 1)
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
        #expect(unavailable.currentSample == nil)
        #expect(unavailable.metrics == .unavailable)
        #expect(unavailable.hasSampled)
    }
}

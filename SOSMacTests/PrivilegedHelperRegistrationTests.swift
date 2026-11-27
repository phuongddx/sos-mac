import Foundation
import Testing
import ServiceManagement
@testable import SOSMac

/// The SMAppService repair contract (SMAppService.h: re-register when a
/// LaunchDaemon's plist or executable changes). The pure decision table gets
/// exhaustive coverage; the repair path runs against recording seams so no
/// test ever touches `SMAppService`, UserDefaults or the app bundle.
@Suite("PrivilegedHelperRegistration")
@MainActor
struct PrivilegedHelperRegistrationTests {

    // MARK: - Doubles

    /// Thread-safe recorder: the fingerprint seams run in detached tasks, so
    /// plain mutable state would race under Swift 6's checking.
    final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var _calls: [String] = []
        private var _stored: String?

        func record(_ call: String) {
            lock.lock()
            defer { lock.unlock() }
            _calls.append(call)
        }

        var calls: [String] {
            lock.lock()
            defer { lock.unlock() }
            return _calls
        }

        var stored: String? {
            lock.lock()
            defer { lock.unlock() }
            return _stored
        }
    }

    private let current = "helperhash:plisthash"
    private let other = "differenthash:otherplist"

    private func makeSeams(
        current: String?,
        stored: String?,
        status: SMAppService.Status,
        recorder: Recorder,
        registerResult: @escaping (Int) throws -> Void = { _ in }
    ) -> PrivilegedHelperRegistration.Seams {
        PrivilegedHelperRegistration.Seams(
            currentFingerprint: { current },
            storedFingerprint: { stored },
            storeFingerprint: { value in
                recorder.record("store")
                recorder.setStored(value)
            },
            registrationStatus: { status },
            unregisterHelper: {
                recorder.record("unregister")
            },
            registerHelper: {
                recorder.record("register")
                try registerResult(recorder.registerCount)
            },
            sleep: { _ in recorder.record("sleep") })
    }

    // MARK: - Decision table

    @Test("unreadable helper fails closed: touch nothing")
    func unreadableHelper() {
        let decision = PrivilegedHelperRegistration.decide(
            currentFingerprint: nil, storedFingerprint: current, status: .enabled)
        #expect(decision == .helperUnreadable)
    }

    @Test("never-registered daemon is a user action, never repaired at launch")
    func notRegistered() {
        let decision = PrivilegedHelperRegistration.decide(
            currentFingerprint: current, storedFingerprint: other, status: .notRegistered)
        #expect(decision == .helperNotRegistered)
    }

    @Test("first run with the fingerprint feature adopts without re-registering")
    func firstRunAdopts() {
        let decision = PrivilegedHelperRegistration.decide(
            currentFingerprint: current, storedFingerprint: nil, status: .enabled)
        #expect(decision == .adoptCurrentFingerprint)
    }

    @Test("same fingerprint: up to date")
    func unchanged() {
        let decision = PrivilegedHelperRegistration.decide(
            currentFingerprint: current, storedFingerprint: current, status: .enabled)
        #expect(decision == .fingerprintUnchanged)
    }

    @Test("changed fingerprint with an existing registration: re-register")
    func changedReregisters() {
        let decision = PrivilegedHelperRegistration.decide(
            currentFingerprint: current, storedFingerprint: other, status: .enabled)
        #expect(decision == .reregisterHelper)

        let approval = PrivilegedHelperRegistration.decide(
            currentFingerprint: current, storedFingerprint: other, status: .requiresApproval)
        #expect(approval == .reregisterHelper)
    }

    // MARK: - Repair execution

    @Test("unchanged helper makes no privileged calls")
    func ensureUnchangedIsQuiet() async {
        let recorder = Recorder()
        let registration = PrivilegedHelperRegistration(
            seams: makeSeams(current: current, stored: current, status: .enabled, recorder: recorder))

        let outcome = await registration.ensureCurrentHelperRegistered()

        #expect(outcome == .upToDate)
        #expect(recorder.calls.isEmpty)
    }

    @Test("never-registered helper makes no privileged calls")
    func ensureNotRegisteredIsQuiet() async {
        let recorder = Recorder()
        let registration = PrivilegedHelperRegistration(
            seams: makeSeams(current: current, stored: other, status: .notRegistered, recorder: recorder))

        let outcome = await registration.ensureCurrentHelperRegistered()

        #expect(outcome == .helperNotRegistered)
        #expect(recorder.calls.isEmpty)
    }

    @Test("first run stores the fingerprint without re-registering")
    func ensureFirstRunAdopts() async {
        let recorder = Recorder()
        let registration = PrivilegedHelperRegistration(
            seams: makeSeams(current: current, stored: nil, status: .enabled, recorder: recorder))

        let outcome = await registration.ensureCurrentHelperRegistered()

        #expect(outcome == .adopted)
        #expect(recorder.calls == ["store"])
        #expect(recorder.stored == current)
    }

    @Test("changed helper unregisters, waits, registers, stores")
    func ensureReregisters() async {
        let recorder = Recorder()
        let registration = PrivilegedHelperRegistration(
            seams: makeSeams(current: current, stored: other, status: .enabled, recorder: recorder))

        let outcome = await registration.ensureCurrentHelperRegistered()

        #expect(outcome == .reregistered)
        #expect(recorder.calls == ["unregister", "sleep", "register", "store"])
        #expect(recorder.stored == current)
    }

    @Test("a failing register is retried before giving up, and nothing is stored on failure")
    func ensureRetriesRegister() async {
        let recorder = Recorder()
        let registration = PrivilegedHelperRegistration(
            seams: makeSeams(
                current: current, stored: other, status: .enabled, recorder: recorder,
                registerResult: { attempt in
                    if attempt < 2 {
                        throw PrivilegedHelperError.operationFailed("Operation not permitted")
                    }
                }))

        let outcome = await registration.ensureCurrentHelperRegistered()

        #expect(outcome == .reregistered)
        #expect(recorder.calls == [
            "unregister", "sleep",                    // unregister, then the repair delay
            "register", "sleep",                       // attempt 1 fails, backoff
            "register", "store",                        // attempt 2 succeeds
        ])
    }

    @Test("every register attempt failing reports failure and stores nothing")
    func ensureFailureStoresNothing() async {
        let recorder = Recorder()
        let registration = PrivilegedHelperRegistration(
            seams: makeSeams(
                current: current, stored: other, status: .enabled, recorder: recorder,
                registerResult: { _ in
                    throw PrivilegedHelperError.operationFailed("Operation not permitted")
                }))

        let outcome = await registration.ensureCurrentHelperRegistered()

        guard case .failed = outcome else {
            Issue.record("expected failure, got \(outcome)")
            return
        }
        #expect(!recorder.calls.contains("store"))
        #expect(recorder.stored == nil)
        // Bounded: unregister + delay + 3 attempts (with backoff sleeps between).
        #expect(recorder.calls.filter { $0 == "register" }.count == 3)
    }

    @Test("a failing unregister does not abort the repair")
    func ensureUnregisterFailureStillRegisters() async {
        let recorder = Recorder()
        var seams = makeSeams(current: current, stored: other, status: .enabled, recorder: recorder)
        seams.unregisterHelper = {
            recorder.record("unregister-failed")
            throw PrivilegedHelperError.operationFailed("Operation not permitted")
        }
        let registration = PrivilegedHelperRegistration(seams: seams)

        let outcome = await registration.ensureCurrentHelperRegistered()

        #expect(outcome == .reregistered)
        #expect(recorder.calls == ["unregister-failed", "sleep", "register", "store"])
    }

    @Test("unreadable helper reports failure and touches nothing")
    func ensureUnreadableIsQuiet() async {
        let recorder = Recorder()
        let registration = PrivilegedHelperRegistration(
            seams: makeSeams(current: nil, stored: other, status: .enabled, recorder: recorder))

        let outcome = await registration.ensureCurrentHelperRegistered()

        guard case .failed = outcome else {
            Issue.record("expected failure, got \(outcome)")
            return
        }
        #expect(recorder.calls.isEmpty)
    }
}

extension PrivilegedHelperRegistrationTests.Recorder {
    func setStored(_ value: String?) {
        lock.lock()
        defer { lock.unlock() }
        _stored = value
    }

    var registerCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _calls.filter { $0 == "register" }.count
    }
}

import Foundation
import ServiceManagement
import CryptoKit
import CleanCore

/// The launch-time repair Apple's `SMAppService.h` requires when a bundled
/// daemon changes:
///
/// > "If an app updates either the plist or the executable for a LaunchAgent
/// > or LaunchDaemon, the SMAppService must be re-registered or it may not
/// > launch. It is recommended to also call unregister before re-registering
/// > if the executable has been changed."
///
/// There is no public API that reports *which* helper version launchd
/// currently has registered, so the app compares the bundled helper's
/// fingerprint — SHA-256 over the helper executable and its launchd plist —
/// with the fingerprint stored the last time registration succeeded. A
/// different fingerprint means exactly the state the header describes: the
/// plist or the executable changed since registration, and the service must
/// be re-registered. This deliberately does **not** depend on Sparkle: a user
/// can replace the app bundle by hand, and the check must repair the
/// registration on every launch regardless of how the update arrived.
///
/// Safety notes, both from the same header and from SMAppService behaviour:
/// - `register()` may legitimately leave the status at `.requiresApproval`
///   (the user must approve the daemon in System Settings); that is success,
///   not failure.
/// - Registering immediately after unregistering is reported (Apple Developer
///   Forums) to sometimes fail with "Operation not permitted"; the repair
///   waits a second first and retries a bounded number of times.
/// - `unregister()` failing does not abort the repair: the registration is
///   already stale at that point, so the required fix is still to register.
/// - When the daemon was never registered, nothing is touched — registering a
///   LaunchDaemon is an explicit user action (Performance screen), never a
///   silent side effect of launching the app.
@MainActor
final class PrivilegedHelperRegistration {

    // MARK: - Seams

    /// Every outside read or privileged action goes through a seam, so tests
    /// never reach the keychain, `SMAppService`, or the app bundle.
    struct Seams: Sendable {
        /// SHA-256 over the bundled helper executable + launchd plist.
        /// `nil` when either file is missing or unreadable (fail closed).
        var currentFingerprint: @Sendable () -> String?
        /// The fingerprint stored after the last successful registration.
        var storedFingerprint: @Sendable () -> String?
        var storeFingerprint: @Sendable (String) -> Void
        var registrationStatus: @MainActor @Sendable () -> SMAppService.Status
        var unregisterHelper: @MainActor @Sendable () throws -> Void
        var registerHelper: @MainActor @Sendable () throws -> Void
        /// Injected `Task.sleep` so tests don't actually wait.
        var sleep: @Sendable (_ seconds: UInt64) async throws -> Void

        /// Production adapters. File hashing happens off the main actor (the
        /// helper executable is a few MB); the `SMAppService` calls stay on
        /// the main actor, matching `PrivilegedHelperClient`'s isolation.
        static func live(client: PrivilegedHelperClient) -> Seams {
            Seams(
                currentFingerprint: Self.liveFingerprint,
                storedFingerprint: { UserDefaults.standard.string(forKey: PrivilegedHelperRegistration.defaultsKey) },
                storeFingerprint: { UserDefaults.standard.set($0, forKey: PrivilegedHelperRegistration.defaultsKey) },
                registrationStatus: { client.refreshStatus(); return client.status },
                unregisterHelper: { try client.unregister() },
                registerHelper: { try client.register() },
                sleep: { seconds in
                    try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                })
        }

        /// The fingerprint the app ships with right now: the helper binary
        /// (`Contents/Resources/com.nextlabs.sosmac.privilegedhelper`) plus
        /// the launchd plist that registers it. Any change to either — new
        /// build number, code change, plist change — changes this value.
        @Sendable
        static func liveFingerprint() -> String? {
            let bundle = Bundle.main
            let helper = bundle.bundleURL
                .appendingPathComponent("Contents/Resources/\(PrivilegedHelperConstants.machServiceName)")
            let plist = bundle.bundleURL
                .appendingPathComponent("Contents/Library/LaunchDaemons/\(PrivilegedHelperConstants.daemonPlistName)")
            guard let helperData = try? Data(contentsOf: helper),
                  let plistData = try? Data(contentsOf: plist) else {
                return nil
            }
            return Self.hex(of: SHA256.hash(data: helperData)) + ":" + Self.hex(of: SHA256.hash(data: plistData))
        }

        private static func hex(of digest: SHA256Digest) -> String {
            digest.map { String(format: "%02x", $0) }.joined()
        }
    }

    // MARK: - Decision

    /// The pure decision table — no I/O, fully testable.
    enum Decision: Equatable, Sendable {
        /// Either bundled file is unreadable: fail closed, touch nothing.
        case helperUnreadable
        /// The daemon was never registered: registering it is a user action.
        case helperNotRegistered
        /// Same fingerprint as the last successful registration.
        case fingerprintUnchanged
        /// First run with the fingerprint feature: latch the current
        /// fingerprint without re-registering (the registration already
        /// points into this bundle; re-registering could re-prompt for
        /// approval and churn the Background Task Management database).
        case adoptCurrentFingerprint
        /// The helper changed since registration: the header-mandated repair.
        case reregisterHelper
    }

    /// What `ensureCurrentHelperRegistered()` actually did.
    enum Outcome: Equatable, Sendable {
        case helperNotRegistered
        case upToDate
        /// First run: current fingerprint stored, registration untouched.
        case adopted
        case reregistered
        /// The repair ran but every `register()` attempt failed. Nothing is
        /// stored, so the next launch retries — the app keeps working, only
        /// privileged operations need the registration fixed.
        case failed(String)
    }

    static func decide(
        currentFingerprint: String?,
        storedFingerprint: String?,
        status: SMAppService.Status
    ) -> Decision {
        guard currentFingerprint != nil else { return .helperUnreadable }
        guard status != .notRegistered else { return .helperNotRegistered }
        guard let storedFingerprint else { return .adoptCurrentFingerprint }
        return storedFingerprint == currentFingerprint ? .fingerprintUnchanged : .reregisterHelper
    }

    // MARK: - Repair

    private let seams: Seams
    /// Pause between `unregister` and the first `register` (forum-reported
    /// "Operation not permitted" when re-registering immediately).
    private static let repairDelaySeconds: UInt64 = 1
    /// Bounded retries so a wedged `register` can't spin forever at launch.
    private static let registerAttempts = 3

    init(seams: Seams) {
        self.seams = seams
    }

    /// Runs at every app launch (see `RootView`). Reads the fingerprint off
    /// the main actor, then decides and, only when the helper changed,
    /// performs the `unregister` → `register` repair.
    func ensureCurrentHelperRegistered() async -> Outcome {
        let current = await Task.detached(priority: .utility) { [seams] in seams.currentFingerprint() }.value
        let stored = await Task.detached(priority: .utility) { [seams] in seams.storedFingerprint() }.value

        switch Self.decide(currentFingerprint: current, storedFingerprint: stored, status: seams.registrationStatus()) {
        case .helperUnreadable:
            return .failed("The bundled privileged helper could not be read; its registration was left untouched.")
        case .helperNotRegistered:
            return .helperNotRegistered
        case .fingerprintUnchanged:
            return .upToDate
        case .adoptCurrentFingerprint:
            guard let current else { return .failed("The bundled privileged helper could not be read.") }
            seams.storeFingerprint(current)
            return .adopted
        case .reregisterHelper:
            return await reregister(current: current)
        }
    }

    private func reregister(current: String?) async -> Outcome {
        // SMAppService.h: unregister first when the executable changed; a
        // failing unregister doesn't abort — the stale registration is the
        // thing being repaired, so the fix is still to register.
        do {
            try seams.unregisterHelper()
        } catch {
            // Continue: see above.
        }
        try? await seams.sleep(Self.repairDelaySeconds)

        var lastError: Error?
        for attempt in 0..<Self.registerAttempts {
            do {
                try seams.registerHelper()
                if let current {
                    seams.storeFingerprint(current)
                }
                return .reregistered
            } catch {
                lastError = error
                if attempt + 1 < Self.registerAttempts {
                    try? await seams.sleep(Self.repairDelaySeconds * UInt64(attempt + 1))
                }
            }
        }
        let reason = lastError.map(String.init(describing:)) ?? "unknown error"
        return .failed("Re-registering the privileged helper failed: \(reason)")
    }

    // MARK: - Manual registration bookkeeping

    /// Called after **any** successful `register()` — including the deliberate
    /// one from the Performance screen — so the stored fingerprint always
    /// names the binary launchd now runs. Without this, a user who
    /// re-registers manually right after an update would get one spurious
    /// repair cycle on the next launch.
    static func recordSuccessfulRegistration() {
        guard let fingerprint = Seams.liveFingerprint() else { return }
        UserDefaults.standard.set(fingerprint, forKey: defaultsKey)
    }

    private nonisolated static let defaultsKey = "PrivilegedHelperRegistration.lastFingerprint"

    // MARK: - Launch gating

    /// The repair only runs in a real app launch: never under XCTest (the
    /// unit-test host is this very app) and never in a UI-test or
    /// screenshot-launch, both of which speak through `SOSMAC_UITEST_*`
    /// environment variables. Everything else is the user opening the app.
    static var shouldRunAtLaunch: Bool {
        let environment = ProcessInfo.processInfo.environment
        if environment["XCTestConfigurationFilePath"] != nil { return false }
        #if DEBUG
        if environment.keys.contains(where: { $0.hasPrefix("SOSMAC_UITEST_") }) { return false }
        #endif
        return true
    }
}

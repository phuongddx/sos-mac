import Foundation

/// Headless launch mode for the merge gate (`Scripts/verify-gate.sh`, step 4).
///
/// Every shipped executable — the app, Menu Bar Helper, and the privileged
/// helper — checks this at the very top of startup and exits before creating
/// any UI, status item, or XPC listener. dyld has already mapped every linked
/// library by that point, so a load-time failure (the hardened-runtime
/// library-validation crash that killed Release installs on 2026-11-27 before
/// any window appeared) aborts the process with a non-zero status *before*
/// the check runs, and the gate fails. Unit tests cannot catch that class of
/// bug because `xcodebuild test` runs the host under a debugger, which
/// suspends library validation.
public enum GateSmokeMode {
    /// The command-line argument that enables the mode. `Scripts/verify-gate.sh`
    /// passes this exact flag; `GateSmokeModeTests` pins the value so the two
    /// cannot drift apart silently.
    public static let flag = "--gate-smoke"

    /// Whether the current process was launched in gate smoke mode.
    public static var isEnabled: Bool {
        CommandLine.arguments.contains(flag)
    }
}

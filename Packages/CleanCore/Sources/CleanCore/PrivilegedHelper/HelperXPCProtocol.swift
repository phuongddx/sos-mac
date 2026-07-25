import Foundation

/// The full, fixed operation set the privileged helper exposes over XPC —
/// deliberately NOT a generic "run this command as root" passthrough, which
/// would be a serious local-privilege-escalation surface. Every new
/// privileged capability must be a deliberate, reviewed addition here (see
/// phase-08-privileged-helper.md's own risk note), never an incidental one.
///
/// `@objc` (required by `NSXPCInterface`) can't bridge a Swift enum
/// parameter directly, so `manageSystemDaemon`'s action crosses the wire as
/// a raw `String` — the helper-side implementation converts it back to
/// `HelperOperationValidator.DaemonAction` and rejects anything that isn't
/// exactly `"load"`/`"unload"`.
@objc public protocol HelperXPCProtocol {
    func trashSystemPath(_ path: String, withReply reply: sending @escaping @Sendable (Bool, String?) -> Void)
    func purgeMemory(withReply reply: sending @escaping @Sendable (Bool, String?) -> Void)
    func flushDNSCache(withReply reply: sending @escaping @Sendable (Bool, String?) -> Void)
    func manageSystemDaemon(plistPath: String, action: String, withReply reply: sending @escaping @Sendable (Bool, String?) -> Void)
}

/// Shared identifiers both the app and the helper daemon need to agree on.
public enum PrivilegedHelperConstants {
    /// Must match the `MachServices` key in the daemon's bundled launchd
    /// plist and the `Label` used to register it.
    public static let machServiceName = "com.nextlabs.sosmac.privilegedhelper"
    public static let daemonPlistName = "com.nextlabs.sosmac.privilegedhelper.plist"
    /// The main app's own bundle identifier — the helper checks every
    /// incoming XPC connection's code signature against this rather than
    /// trusting "something connected to my Mach service" alone.
    public static let expectedClientBundleIdentifier = "com.nextlabs.sosmac"
}

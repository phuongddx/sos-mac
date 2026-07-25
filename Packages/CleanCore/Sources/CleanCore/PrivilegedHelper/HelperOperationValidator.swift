import Foundation

/// Server-side validation for every privileged-helper operation. The helper
/// daemon runs as root, so it must never trust that the client app's UI
/// already restricted what it sends — every input is re-validated here,
/// independently of whatever the app-side UI enforces. Deliberately a
/// small, explicit, auditable allowlist — same "reviewable list, not a
/// heuristic crawl" philosophy as `JunkRule` — because the #1 way a
/// root-level cleaner causes real damage is an overbroad delete target.
public enum HelperOperationValidator {
    /// System directories this app is entitled to remove *contents* from via
    /// the privileged helper. An allowlisted root itself is never a valid
    /// target — only paths strictly inside it — so a client can't ask the
    /// helper to remove the whole directory.
    public static let allowedSystemPathRoots: [String] = [
        "/Library/Caches"
    ]

    /// Resolves `path` to its real, symlink-free absolute form and checks it
    /// falls strictly inside one of `allowedSystemPathRoots`. This guards
    /// against a symlink already sitting at `path` *before* this check runs
    /// (e.g. something under `/Library/Caches` that is itself a link
    /// pointing outside the allowlist) — it is a check-then-use check, not a
    /// TOCTOU-proof one: the validated string and the path `moveItem`
    /// actually operates on afterward are the same string re-resolved by a
    /// fresh syscall, so a swap in the narrow window between this check and
    /// the move is a real, if low-impact, race (a `rename()`-style move
    /// relocates a symlink itself rather than dereferencing into its
    /// target, so this cannot be used to move a sensitive file to a
    /// different path — at worst it moves the attacker's own symlink away).
    /// Closing this fully would mean resolving once and operating via
    /// `O_NOFOLLOW`/file-descriptor-relative APIs rather than re-resolving a
    /// path string twice.
    public static func isSystemPathAllowed(_ path: String) -> Bool {
        let resolved = (path as NSString).resolvingSymlinksInPath
        for root in allowedSystemPathRoots {
            let resolvedRoot = (root as NSString).resolvingSymlinksInPath
            if resolved != resolvedRoot, resolved.hasPrefix(resolvedRoot + "/") {
                return true
            }
        }
        return false
    }

    public enum DaemonAction: String, Sendable {
        case load
        case unload
    }

    /// Plists this helper may load/unload — never an arbitrary path, and
    /// never an action beyond load/unload (no "run this plist's arbitrary
    /// `ProgramArguments`" surface).
    public static let allowedDaemonPlistRoots: [String] = [
        "/Library/LaunchAgents",
        "/Library/LaunchDaemons"
    ]

    public static func isDaemonPlistAllowed(_ plistPath: String) -> Bool {
        guard plistPath.hasSuffix(".plist") else { return false }
        let resolved = (plistPath as NSString).resolvingSymlinksInPath
        return allowedDaemonPlistRoots.contains { root in
            let resolvedRoot = (root as NSString).resolvingSymlinksInPath
            return resolved.hasPrefix(resolvedRoot + "/")
        }
    }
}

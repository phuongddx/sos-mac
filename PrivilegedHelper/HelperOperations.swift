import Foundation
import CleanCore

/// Implements every op in `HelperXPCProtocol`. Runs as root — every method
/// re-validates its input against `HelperOperationValidator` before touching
/// the filesystem or spawning a process, regardless of what the client
/// already checked.
final class HelperOperations: NSObject, HelperXPCProtocol {
    /// A root-owned, reversible holding area for files removed via
    /// `trashSystemPath` — mirrors the whole app's "never a hard delete"
    /// invariant (`Cleaner`, `QuarantineManager`). There is no per-user
    /// `~/.Trash` concept available to a root process acting on
    /// system-owned paths, so this is the root-level equivalent.
    private static let systemTrashDirectory = URL(fileURLWithPath: "/Library/Application Support/com.nextlabs.sosmac/SystemTrash")

    func trashSystemPath(_ path: String, withReply reply: sending @escaping @Sendable (Bool, String?) -> Void) {
        guard HelperOperationValidator.isSystemPathAllowed(path) else {
            reply(false, "Path is not in the allowed system locations.")
            return
        }

        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(
                at: Self.systemTrashDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            reply(false, error.localizedDescription)
            return
        }

        let destinationDirectory = Self.systemTrashDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
            let destination = destinationDirectory.appendingPathComponent((path as NSString).lastPathComponent)
            try fileManager.moveItem(at: URL(fileURLWithPath: path), to: destination)
            reply(true, nil)
        } catch {
            // The subfolder may already exist by this point — don't leave
            // an orphaned, root-owned empty directory behind on every
            // failed attempt (same fix already applied to QuarantineManager
            // in Phase 7 for the identical failure mode).
            try? fileManager.removeItem(at: destinationDirectory)
            reply(false, error.localizedDescription)
        }
    }

    func purgeMemory(withReply reply: sending @escaping @Sendable (Bool, String?) -> Void) {
        Task {
            do {
                _ = try await Shell.run("/usr/sbin/purge", args: [])
                reply(true, nil)
            } catch {
                reply(false, error.localizedDescription)
            }
        }
    }

    func flushDNSCache(withReply reply: sending @escaping @Sendable (Bool, String?) -> Void) {
        Task {
            do {
                _ = try await Shell.run("/usr/bin/dscacheutil", args: ["-flushcache"])
                _ = try await Shell.run("/usr/bin/killall", args: ["-HUP", "mDNSResponder"])
                reply(true, nil)
            } catch {
                reply(false, error.localizedDescription)
            }
        }
    }

    func manageSystemDaemon(plistPath: String, action: String, withReply reply: sending @escaping @Sendable (Bool, String?) -> Void) {
        guard HelperOperationValidator.isDaemonPlistAllowed(plistPath) else {
            reply(false, "Plist path is not in the allowed locations.")
            return
        }
        guard let daemonAction = HelperOperationValidator.DaemonAction(rawValue: action) else {
            reply(false, "Action must be \"load\" or \"unload\".")
            return
        }

        Task {
            do {
                _ = try await Shell.run("/bin/launchctl", args: [daemonAction.rawValue, plistPath])
                reply(true, nil)
            } catch {
                reply(false, error.localizedDescription)
            }
        }
    }
}

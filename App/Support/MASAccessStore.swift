#if MAS_BUILD
import AppKit
import Foundation
import Observation
import CleanCore

/// The Mac App Store build's folder grants. In the sandbox, `~` and
/// `NSHomeDirectory()` resolve to the app container, so every home-rooted
/// scan would silently find nothing. This store is the one place that:
///
/// 1. asks the person for the two folders the app needs (home, Applications)
///    with an `NSOpenPanel`;
/// 2. persists each grant as an app-scope security-scoped bookmark
///    (`SecurityScopedBookmarkStore`), so it survives relaunches;
/// 3. holds `startAccessingSecurityScopedResource()` for the whole session,
///    so background scans and Trash moves keep working without per-call
///    start/stop juggling.
///
/// Fail closed: a missing or stale grant reads as `nil` and the UI shows the
/// grant call-to-action again; a scan never runs un-granted (which would
/// report a fake empty result), and `url.path` values are never guessed.
@MainActor
@Observable
final class MASAccessStore {
    /// Real home folder path (`/Users/…`) once granted; `nil` until then.
    private(set) var homeRoot: String?
    /// Real /Applications path once granted; `nil` until then.
    private(set) var applicationsRoot: String?
    /// The last error shown next to a grant button (panel cancelled is not an error).
    private(set) var grantError: String?

    /// Called after any grant changes so `ModuleStore` can rebuild the view
    /// models whose scan roots depend on the granted folder.
    var onAccessChanged: (@MainActor () -> Void)?

    private let bookmarks: SecurityScopedBookmarkStore
    /// URLs whose security scope is currently held for the session.
    private var heldURLs: [URL] = []

    private static let homeKey = "mas.grant.home"
    private static let applicationsKey = "mas.grant.applications"
    private static let spaceLensKey = "mas.grant.spacelens"

    init(bookmarks: SecurityScopedBookmarkStore = SecurityScopedBookmarkStore()) {
        self.bookmarks = bookmarks
        restoreHeld(Self.homeKey)
        restoreHeld(Self.applicationsKey)
        restoreHeld(Self.spaceLensKey)
    }

    var needsHomeGrant: Bool { homeRoot == nil }
    var needsApplicationsGrant: Bool { applicationsRoot == nil }

    // MARK: - Grant requests (NSOpenPanel)

    /// Opens the panel for the real home folder. Returns true only when a
    /// folder was chosen, bookmarked and its access held.
    @discardableResult
    func requestHomeAccess() -> Bool {
        requestAccess(
            title: "Grant access to your Home folder",
            message: "SOS Mac scans caches, logs, duplicates and threats inside your Home folder. Nothing is moved without your confirmation.",
            key: Self.homeKey,
            assign: { [weak self] root in self?.homeRoot = root }
        )
    }

    /// Opens the panel for /Applications (used by Uninstaller and Updater).
    @discardableResult
    func requestApplicationsAccess() -> Bool {
        requestAccess(
            title: "Grant access to Applications",
            message: "SOS Mac reads installed apps' versions to list updates and leftovers. Pick the Applications folder.",
            key: Self.applicationsKey,
            assign: { [weak self] root in self?.applicationsRoot = root }
        )
    }

    /// The directories Uninstaller/Updater scan: the granted Applications
    /// folder plus the user-domain Applications under the granted home, when
    /// both exist. Empty until granted (the UI gates the scan).
    var applicationsSearchDirectories: [String] {
        var roots: [String] = []
        if let applicationsRoot { roots.append(applicationsRoot) }
        if let homeRoot {
            let userApps = (homeRoot as NSString).appendingPathComponent("Applications")
            if FileManager.default.fileExists(atPath: userApps) { roots.append(userApps) }
        }
        return roots
    }

    // MARK: - Space Lens folder persistence

    /// Persists a folder chosen in Space Lens's own panel as a bookmark so the
    /// last folder can be offered again on relaunch. The grant itself (the
    /// NSOpenPanel pick) already gives session access; this keeps it across
    /// launches. Fail closed: a bookmark failure leaves the session access in
    /// place and simply does not persist.
    func storeSpaceLensFolder(_ url: URL) {
        try? bookmarks.store(url, forKey: Self.spaceLensKey)
        holdAccess(url)
    }

    /// The last Space Lens folder, with its scope held, or nil.
    func restoreSpaceLensFolder() -> String? {
        guard let url = bookmarks.resolveURL(forKey: Self.spaceLensKey) else { return nil }
        holdAccess(url)
        return url.path
    }

    // MARK: - Internals

    @discardableResult
    private func requestAccess(title: String, message: String, key: String,
                                assign: @escaping (String) -> Void) -> Bool {
        grantError = nil
        let panel = NSOpenPanel()
        panel.title = title
        panel.message = message
        panel.prompt = "Grant Access"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        // Start at the real home (not the container): the panel runs
        // out-of-process and can navigate anywhere.
        if key == Self.homeKey {
            panel.directoryURL = URL(fileURLWithPath: "/Users/\(NSUserName())")
        } else {
            panel.directoryURL = URL(fileURLWithPath: "/Applications")
        }

        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            try bookmarks.store(url, forKey: key)
        } catch {
            grantError = "Couldn't save the folder choice: \(error.localizedDescription)"
            return false
        }
        holdAccess(url)
        assign(url.path)
        onAccessChanged?()
        return true
    }

    /// Resolves a saved bookmark on launch and holds its scope for the session.
    private func restoreHeld(_ key: String) {
        guard let url = bookmarks.resolveURL(forKey: key) else { return }
        holdAccess(url)
        switch key {
        case Self.homeKey: homeRoot = url.path
        case Self.applicationsKey: applicationsRoot = url.path
        default: break
        }
    }

    private func holdAccess(_ url: URL) {
        guard !heldURLs.contains(url) else { return }
        if url.startAccessingSecurityScopedResource() {
            heldURLs.append(url)
        }
        // A failed start = the grant is stale (folder moved / access revoked):
        // leave the stored bookmark, but don't pretend access exists.
    }
}
#endif

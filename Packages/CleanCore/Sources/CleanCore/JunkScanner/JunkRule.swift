import Foundation

/// The allowlist of scannable junk subpaths. Deliberately a single flat list
/// (not a generic filesystem crawl) — this is the #1 place cleaner apps
/// destroy user data, so every eligible path is explicit and reviewable here
/// rather than discovered by a heuristic.
public struct JunkRule: Sendable, Identifiable {
    public enum Kind: Sendable {
        case directPath(String)
        /// `~/Library/Application Support/*/Cache*` — never the app's whole
        /// Application Support root, only subfolders literally named "Cache*".
        case applicationSupportCacheGlob
        /// Same glob, but anchored at a concrete home root the caller resolved
        /// from a user-selected security-scoped bookmark (App Sandbox builds:
        /// `~` expands to the container, so the real home must be injected).
        case applicationSupportCacheGlobUnderRoot(String)
    }

    public let id: String
    public let label: String
    public let kind: Kind
    public let defaultSeverity: Severity
    public let requiresPrivilegedHelper: Bool

    public init(
        id: String,
        label: String,
        kind: Kind,
        defaultSeverity: Severity,
        requiresPrivilegedHelper: Bool = false
    ) {
        self.id = id
        self.label = label
        self.kind = kind
        self.defaultSeverity = defaultSeverity
        self.requiresPrivilegedHelper = requiresPrivilegedHelper
    }

    public func resolvedRoots(fileManager: FileManager) -> [String] {
        switch kind {
        case .directPath(let template):
            return [(template as NSString).expandingTildeInPath]

        case .applicationSupportCacheGlob:
            let appSupport = ("~/Library/Application Support" as NSString).expandingTildeInPath
            return Self.applicationSupportCacheRoots(appSupport, fileManager: fileManager)

        case .applicationSupportCacheGlobUnderRoot(let homeRoot):
            let appSupport = (homeRoot as NSString).appendingPathComponent("Library/Application Support")
            return Self.applicationSupportCacheRoots(appSupport, fileManager: fileManager)
        }
    }

    /// The shared `*/Cache*` glob walker for both app-support kinds.
    private static func applicationSupportCacheRoots(_ appSupport: String, fileManager: FileManager) -> [String] {
            guard let appDirs = try? fileManager.contentsOfDirectory(atPath: appSupport) else {
                return []
            }
            var roots: [String] = []
            for appDir in appDirs {
                let appDirPath = (appSupport as NSString).appendingPathComponent(appDir)
                guard let children = try? fileManager.contentsOfDirectory(atPath: appDirPath) else {
                    continue
                }
                for child in children where child.hasPrefix("Cache") {
                    roots.append((appDirPath as NSString).appendingPathComponent(child))
                }
            }
            return roots
    }

    /// Most rules just carry a fixed severity; logs are the one case where
    /// severity depends on the item itself (age), so this stays a function
    /// rather than a stored property.
    public func severity(for lastAccessed: Date?, now: Date) -> Severity {
        guard id == "user-logs" else { return defaultSeverity }
        guard let lastAccessed else { return .caution }
        let sevenDays: TimeInterval = 7 * 24 * 3600
        return now.timeIntervalSince(lastAccessed) > sevenDays ? .safe : .caution
    }
}

extension JunkRule {
    public static let allowlist: [JunkRule] = [
        JunkRule(
            id: "user-caches",
            label: "User App Caches",
            kind: .directPath("~/Library/Caches"),
            defaultSeverity: .safe
        ),
        JunkRule(
            id: "user-logs",
            label: "User Logs (7+ days old)",
            kind: .directPath("~/Library/Logs"),
            defaultSeverity: .safe
        ),
        JunkRule(
            id: "app-support-caches",
            label: "App Support Cache Folders",
            kind: .applicationSupportCacheGlob,
            defaultSeverity: .safe
        ),
        JunkRule(
            id: "system-caches",
            label: "System Caches (requires additional permission)",
            kind: .directPath("/Library/Caches"),
            defaultSeverity: .caution,
            requiresPrivilegedHelper: true
        )
    ]

    /// The Smart Care one-click flow's rule set — deliberately narrower than
    /// `allowlist`, kept as one named, auditable list per the Phase 5 spec's
    /// own instruction, rather than re-deriving eligibility ad hoc at each
    /// call site. Excludes anything requiring the not-yet-built privileged
    /// helper, so Smart Care never silently depends on it.
    public static let smartCareEligible: [JunkRule] = allowlist.filter { !$0.requiresPrivilegedHelper }

    /// The App Sandbox allowlist: the same three user-domain rules, rooted at
    /// the concrete home folder the caller resolved from a user-granted
    /// (security-scoped) bookmark instead of `~` — inside App Sandbox
    /// `NSHomeDirectory()` and `~` resolve to the app container, so the tilde
    /// rules would silently walk nothing and report a fake "no junk found".
    ///
    /// System Caches (`/Library/Caches`) is deliberately absent: it needs the
    /// PrivilegedHelper, which Mac App Store builds do not embed.
    /// An empty `homeRoot` yields an empty list — the app layer gates scans
    /// on the grant existing, so an un-granted sandbox build never scans at all.
    public static func sandboxAllowlist(homeRoot: String) -> [JunkRule] {
        let root = (homeRoot as NSString).standardizingPath
        guard !root.isEmpty, root != "/" else { return [] }
        return [
            JunkRule(
                id: "user-caches",
                label: "User App Caches",
                kind: .directPath((root as NSString).appendingPathComponent("Library/Caches")),
                defaultSeverity: .safe
            ),
            JunkRule(
                id: "user-logs",
                label: "User Logs (7+ days old)",
                kind: .directPath((root as NSString).appendingPathComponent("Library/Logs")),
                defaultSeverity: .safe
            ),
            JunkRule(
                id: "app-support-caches",
                label: "App Support Cache Folders",
                kind: .applicationSupportCacheGlobUnderRoot(root),
                defaultSeverity: .safe
            )
        ]
    }
}

import Foundation

/// Persists security-scoped folder grants as app-scope bookmark data in
/// `UserDefaults`, and resolves them back to URLs across launches — the
/// documented App Sandbox pattern for keeping access to a folder the person
/// chose in an `NSOpenPanel`.
///
/// The store only writes opaque bookmark `Data`; it never starts or stops
/// access itself. Callers hold the returned URL's
/// `startAccessingSecurityScopedResource()` for as long as they read from it
/// (the app layer holds it for the session, so background scans keep working),
/// and call `stopAccessingSecurityScopedResource()` when they release it.
///
/// Thread-safety: `UserDefaults` is thread-safe, and every operation is a
/// single read or write, so the type is safe to share across concurrency
/// domains as `@unchecked Sendable`.
public final class SecurityScopedBookmarkStore: @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Creates and stores app-scope bookmark data for `url`. Replaces any
    /// previous bookmark under `key`. Throws the underlying
    /// `bookmarkData(with:options:)` error (fail closed, never a silent no-op).
    public func store(_ url: URL, forKey key: String) throws {
        let data = try url.bookmarkData(options: [], relativeTo: nil)
        defaults.set(data, forKey: key)
    }

    /// Resolves the bookmark stored under `key`. `nil` when nothing is stored
    /// or the bookmark is stale (the folder moved or the app lost access);
    /// callers treat `nil` as "grant again".
    public func resolveURL(forKey key: String) -> URL? {
        guard let data = defaults.data(forKey: key) else { return nil }
        var isStale = false
        // `.withoutUI`: never mount UI while resolving (background restore).
        // `try?` = fail closed: an unreadable bookmark reads as "grant again".
        return try? URL(resolvingBookmarkData: data, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &isStale)
    }

    /// Removes the stored bookmark (revoke).
    public func remove(forKey key: String) {
        defaults.removeObject(forKey: key)
    }
}

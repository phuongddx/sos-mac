import Foundation

public struct CloudFileMetadata: Sendable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let size: Int64
    /// Provider-supplied content hash, when the API exposes one (Dropbox's
    /// `content_hash`, Drive's `md5Checksum`) — lets duplicate detection
    /// compare files without downloading them, which matters here in a way
    /// it doesn't for local scans.
    public let contentHash: String?
    public let modifiedDate: Date?
    public let isFolder: Bool

    public init(
        id: String,
        name: String,
        size: Int64,
        contentHash: String? = nil,
        modifiedDate: Date? = nil,
        isFolder: Bool = false
    ) {
        self.id = id
        self.name = name
        self.size = size
        self.contentHash = contentHash
        self.modifiedDate = modifiedDate
        self.isFolder = isFolder
    }
}

public struct CloudFilePage: Sendable {
    public let files: [CloudFileMetadata]
    public let nextCursor: String?

    public init(files: [CloudFileMetadata], nextCursor: String?) {
        self.files = files
        self.nextCursor = nextCursor
    }
}

public struct CloudDeleteFailure: Sendable {
    public let id: String
    public let reason: String
}

public struct CloudDeleteResult: Sendable {
    public let succeededIDs: [String]
    public let failed: [CloudDeleteFailure]
}

public enum CloudProviderError: Error, Sendable, Equatable {
    /// The OAuth client ID/redirect URI hasn't been filled in with a real,
    /// registered app's values yet — see `CloudProviderConfig`. Every
    /// provider fails closed with this rather than attempting a doomed
    /// network call or pretending to succeed.
    case notConfigured
    case notAuthenticated
    case requestFailed(statusCode: Int)
    case rateLimited
}

/// One real, registered OAuth app's client ID + redirect URI per provider.
/// These are NOT secrets that can be fabricated here — they must come from
/// the developer's own Google Cloud Console / Dropbox App Console / Azure AD
/// app registration (see Phase 6's own blocking-prerequisite note). Left
/// empty by default, which every provider treats as `.notConfigured`.
public struct CloudProviderConfig: Sendable {
    public let clientID: String
    public let redirectURI: String

    public init(clientID: String = "", redirectURI: String = "") {
        self.clientID = clientID
        self.redirectURI = redirectURI
    }

    public var isConfigured: Bool {
        !clientID.isEmpty && !redirectURI.isEmpty
    }
}

/// A real cloud storage backend (Google Drive, Dropbox, OneDrive) reached
/// over OAuth2 + REST — as opposed to `ICloudLocalScanner`, which reads
/// iCloud Drive's locally-synced files and is a plain `Scanner`/`Cleaner`,
/// not a `CloudProvider` (there is no public iCloud Drive API).
public protocol CloudProvider: Sendable {
    var providerName: String { get }
    func isAuthenticated() async -> Bool
    func authenticate() async throws
    func signOut() async throws
    func listFiles(cursor: String?) async throws -> CloudFilePage
    func delete(fileIDs: [String]) async throws -> CloudDeleteResult
}

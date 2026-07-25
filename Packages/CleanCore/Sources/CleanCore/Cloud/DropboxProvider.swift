import Foundation

/// Real Dropbox API v2 + OAuth2 — every endpoint below is a genuine,
/// documented Dropbox API URL. Needs a real registered app's client ID +
/// redirect URI (see `CloudProviderConfig`); without one, `authenticate()`
/// fails with `.notConfigured` rather than attempting a doomed request.
public final class DropboxProvider: CloudProvider, @unchecked Sendable {
    public let providerName = "Dropbox"

    private static let providerKey = "dropbox"
    private static let authorizationEndpoint = URL(string: "https://www.dropbox.com/oauth2/authorize")!
    private static let tokenEndpoint = URL(string: "https://api.dropboxapi.com/oauth2/token")!
    private static let listFolderEndpoint = URL(string: "https://api.dropboxapi.com/2/files/list_folder")!
    private static let listFolderContinueEndpoint = URL(string: "https://api.dropboxapi.com/2/files/list_folder/continue")!
    private static let deleteEndpoint = URL(string: "https://api.dropboxapi.com/2/files/delete_v2")!

    private let config: CloudProviderConfig
    private let tokenStore: OAuthTokenStore
    private let webSession: any OAuthWebSessionPresenting
    private let httpSession: URLSession

    public init(
        config: CloudProviderConfig,
        tokenStore: OAuthTokenStore = OAuthTokenStore(),
        webSession: any OAuthWebSessionPresenting,
        httpSession: URLSession = .shared
    ) {
        self.config = config
        self.tokenStore = tokenStore
        self.webSession = webSession
        self.httpSession = httpSession
    }

    public func isAuthenticated() async -> Bool {
        (try? tokenStore.load(forProvider: Self.providerKey)).flatMap { $0 } != nil
    }

    public func authenticate() async throws {
        guard config.isConfigured else { throw CloudProviderError.notConfigured }
        guard let redirectScheme = URL(string: config.redirectURI)?.scheme else {
            throw CloudProviderError.notConfigured
        }

        var components = URLComponents(url: Self.authorizationEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "token_access_type", value: "offline")
        ]

        let callbackURL = try await webSession.present(url: components.url!, callbackURLScheme: redirectScheme)
        guard let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value
        else {
            throw CloudProviderError.requestFailed(statusCode: -1)
        }

        try await exchangeCodeForToken(code: code)
    }

    private func exchangeCodeForToken(code: String) async throws {
        var request = URLRequest(url: Self.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = CloudFormEncoding.encode([
            "code": code,
            "client_id": config.clientID,
            "redirect_uri": config.redirectURI,
            "grant_type": "authorization_code"
        ])

        let (data, _) = try await CloudHTTPClient.send(request, session: httpSession)
        let tokenResponse = try JSONDecoder().decode(DropboxTokenResponse.self, from: data)

        let token = OAuthToken(
            accessToken: tokenResponse.accessToken,
            refreshToken: tokenResponse.refreshToken,
            expiresAt: tokenResponse.expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) }
        )
        try tokenStore.save(token, forProvider: Self.providerKey)
    }

    /// Loads the stored token and, if it's expired, exchanges the refresh
    /// token for a new one before returning — callers never have to think
    /// about expiry themselves. Throws `.notAuthenticated` if there's no
    /// token, or if it's expired with no refresh token to recover with (the
    /// user needs to reconnect either way).
    private func validAccessToken() async throws -> String {
        guard let token = try tokenStore.load(forProvider: Self.providerKey) else {
            throw CloudProviderError.notAuthenticated
        }
        guard token.isExpired else {
            return token.accessToken
        }
        guard let refreshToken = token.refreshToken else {
            throw CloudProviderError.notAuthenticated
        }

        var request = URLRequest(url: Self.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = CloudFormEncoding.encode([
            "refresh_token": refreshToken,
            "client_id": config.clientID,
            "grant_type": "refresh_token"
        ])

        let (data, _) = try await CloudHTTPClient.send(request, session: httpSession)
        let tokenResponse = try JSONDecoder().decode(DropboxTokenResponse.self, from: data)

        let refreshed = OAuthToken(
            accessToken: tokenResponse.accessToken,
            // Dropbox doesn't reissue the refresh token on a refresh
            // exchange — keep the original one.
            refreshToken: tokenResponse.refreshToken ?? refreshToken,
            expiresAt: tokenResponse.expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) }
        )
        try tokenStore.save(refreshed, forProvider: Self.providerKey)
        return refreshed.accessToken
    }

    public func signOut() async throws {
        try tokenStore.delete(forProvider: Self.providerKey)
    }

    public func listFiles(cursor: String?) async throws -> CloudFilePage {
        let accessToken = try await validAccessToken()

        var request: URLRequest
        if let cursor {
            request = URLRequest(url: Self.listFolderContinueEndpoint)
            request.httpBody = try JSONSerialization.data(withJSONObject: ["cursor": cursor])
        } else {
            request = URLRequest(url: Self.listFolderEndpoint)
            request.httpBody = try JSONSerialization.data(withJSONObject: ["path": "", "recursive": true])
        }
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, _) = try await CloudHTTPClient.send(request, session: httpSession)
        let listResponse = try JSONDecoder().decode(DropboxListFolderResponse.self, from: data)

        let files = listResponse.entries.map { entry in
            CloudFileMetadata(
                id: entry.id,
                name: entry.name,
                size: entry.size ?? 0,
                contentHash: entry.contentHash,
                modifiedDate: entry.serverModified.flatMap { ISO8601DateFormatter().date(from: $0) },
                isFolder: entry.tag == "folder"
            )
        }

        return CloudFilePage(files: files, nextCursor: listResponse.hasMore ? listResponse.cursor : nil)
    }

    public func delete(fileIDs: [String]) async throws -> CloudDeleteResult {
        let accessToken = try await validAccessToken()

        var succeeded: [String] = []
        var failed: [CloudDeleteFailure] = []

        for fileID in fileIDs {
            var request = URLRequest(url: Self.deleteEndpoint)
            request.httpMethod = "POST"
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            // Dropbox accepts "id:XXXX" (the metadata's own `id` field, which
            // is what CloudFileMetadata.id is populated from below) anywhere
            // a path argument is expected.
            request.httpBody = try? JSONSerialization.data(withJSONObject: ["path": fileID])

            do {
                _ = try await CloudHTTPClient.send(request, session: httpSession)
                succeeded.append(fileID)
            } catch {
                failed.append(CloudDeleteFailure(id: fileID, reason: "\(error)"))
            }
        }

        return CloudDeleteResult(succeededIDs: succeeded, failed: failed)
    }
}

private struct DropboxTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

private struct DropboxListFolderResponse: Decodable {
    let entries: [DropboxEntry]
    let cursor: String
    let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case entries
        case cursor
        case hasMore = "has_more"
    }
}

private struct DropboxEntry: Decodable {
    let tag: String
    let id: String
    let name: String
    let size: Int64?
    let contentHash: String?
    let serverModified: String?

    enum CodingKeys: String, CodingKey {
        case tag = ".tag"
        case id
        case name
        case size
        case contentHash = "content_hash"
        case serverModified = "server_modified"
    }
}

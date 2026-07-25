import Foundation

/// Real Google Drive API v3 + OAuth2 — every endpoint below is a genuine,
/// documented Google API URL. Needs a real registered OAuth app's client ID
/// + redirect URI (see `CloudProviderConfig`); without one, `authenticate()`
/// fails with `.notConfigured` rather than attempting a doomed request.
public final class GoogleDriveProvider: CloudProvider, @unchecked Sendable {
    public let providerName = "Google Drive"

    private static let providerKey = "google-drive"
    private static let authorizationEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    private static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!
    private static let filesEndpoint = URL(string: "https://www.googleapis.com/drive/v3/files")!
    private static let scope = "https://www.googleapis.com/auth/drive"

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
            URLQueryItem(name: "scope", value: Self.scope),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
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
        let tokenResponse = try JSONDecoder().decode(GoogleTokenResponse.self, from: data)

        let token = OAuthToken(
            accessToken: tokenResponse.accessToken,
            refreshToken: tokenResponse.refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))
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
        let tokenResponse = try JSONDecoder().decode(GoogleTokenResponse.self, from: data)

        let refreshed = OAuthToken(
            accessToken: tokenResponse.accessToken,
            // Google doesn't reissue the refresh token on a refresh
            // exchange — keep the original one.
            refreshToken: tokenResponse.refreshToken ?? refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))
        )
        try tokenStore.save(refreshed, forProvider: Self.providerKey)
        return refreshed.accessToken
    }

    public func signOut() async throws {
        try tokenStore.delete(forProvider: Self.providerKey)
    }

    public func listFiles(cursor: String?) async throws -> CloudFilePage {
        let accessToken = try await validAccessToken()

        var components = URLComponents(url: Self.filesEndpoint, resolvingAgainstBaseURL: false)!
        var queryItems = [
            URLQueryItem(name: "pageSize", value: "100"),
            URLQueryItem(name: "fields", value: "nextPageToken,files(id,name,size,md5Checksum,modifiedTime,mimeType)"),
            URLQueryItem(name: "q", value: "trashed = false")
        ]
        if let cursor { queryItems.append(URLQueryItem(name: "pageToken", value: cursor)) }
        components.queryItems = queryItems

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await CloudHTTPClient.send(request, session: httpSession)
        let listResponse = try JSONDecoder().decode(GoogleDriveFileListResponse.self, from: data)

        let files = listResponse.files.map { file in
            CloudFileMetadata(
                id: file.id,
                name: file.name,
                size: Int64(file.size ?? "0") ?? 0,
                contentHash: file.md5Checksum,
                modifiedDate: file.modifiedTime.flatMap { ISO8601DateFormatter().date(from: $0) },
                isFolder: file.mimeType == "application/vnd.google-apps.folder"
            )
        }

        return CloudFilePage(files: files, nextCursor: listResponse.nextPageToken)
    }

    public func delete(fileIDs: [String]) async throws -> CloudDeleteResult {
        let accessToken = try await validAccessToken()

        var succeeded: [String] = []
        var failed: [CloudDeleteFailure] = []

        for fileID in fileIDs {
            var request = URLRequest(url: Self.filesEndpoint.appendingPathComponent(fileID))
            request.httpMethod = "PATCH"
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            // Drive's trash endpoint, not permanent delete — mirrors the
            // local trashItem(at:) philosophy used everywhere else.
            request.httpBody = try? JSONSerialization.data(withJSONObject: ["trashed": true])

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

private struct GoogleTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

private struct GoogleDriveFileListResponse: Decodable {
    let nextPageToken: String?
    let files: [GoogleDriveFile]
}

private struct GoogleDriveFile: Decodable {
    let id: String
    let name: String
    let size: String?
    let md5Checksum: String?
    let modifiedTime: String?
    let mimeType: String?
}

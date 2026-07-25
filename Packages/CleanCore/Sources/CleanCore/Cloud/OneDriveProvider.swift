import Foundation

/// Real Microsoft Graph (OneDrive) API + OAuth2 — every endpoint below is a
/// genuine, documented Graph API URL. Needs a real registered Azure AD app's
/// client ID + redirect URI (see `CloudProviderConfig`); without one,
/// `authenticate()` fails with `.notConfigured` rather than attempting a
/// doomed request.
public final class OneDriveProvider: CloudProvider, @unchecked Sendable {
    public let providerName = "OneDrive"

    private static let providerKey = "onedrive"
    private static let authorizationEndpoint = URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize")!
    private static let tokenEndpoint = URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/token")!
    // `root/children` only returns the root's immediate children — `delta`
    // is Graph's documented way to enumerate an entire drive recursively
    // (paginated the same way via @odata.nextLink), which root/children
    // silently does NOT do, missing every file in a subfolder entirely.
    private static let rootDeltaEndpoint = URL(string: "https://graph.microsoft.com/v1.0/me/drive/root/delta")!
    private static let itemsEndpoint = URL(string: "https://graph.microsoft.com/v1.0/me/drive/items")!
    private static let scope = "Files.ReadWrite offline_access"

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
            URLQueryItem(name: "scope", value: Self.scope)
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
            "grant_type": "authorization_code",
            "scope": Self.scope
        ])

        let (data, _) = try await CloudHTTPClient.send(request, session: httpSession)
        let tokenResponse = try JSONDecoder().decode(GraphTokenResponse.self, from: data)

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
            "grant_type": "refresh_token",
            "scope": Self.scope
        ])

        let (data, _) = try await CloudHTTPClient.send(request, session: httpSession)
        let tokenResponse = try JSONDecoder().decode(GraphTokenResponse.self, from: data)

        let refreshed = OAuthToken(
            accessToken: tokenResponse.accessToken,
            // Graph may or may not rotate the refresh token; keep the old
            // one if a new one wasn't issued.
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

        // Graph's pagination cursor (@odata.nextLink) is a full URL, not a
        // token — unlike Drive/Dropbox, so it's used directly as-is here.
        let requestURL = cursor.flatMap(URL.init(string:)) ?? Self.rootDeltaEndpoint
        var request = URLRequest(url: requestURL)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await CloudHTTPClient.send(request, session: httpSession)
        let listResponse = try JSONDecoder().decode(GraphChildrenResponse.self, from: data)

        let files = listResponse.value.map { item in
            CloudFileMetadata(
                id: item.id,
                name: item.name,
                size: item.size ?? 0,
                contentHash: item.file?.hashes?.quickXorHash,
                modifiedDate: item.lastModifiedDateTime.flatMap { ISO8601DateFormatter().date(from: $0) },
                isFolder: item.folder != nil
            )
        }

        // The final delta page returns @odata.deltaLink instead of
        // @odata.nextLink — absence of nextLink correctly ends pagination
        // either way, so no separate handling is needed here.
        return CloudFilePage(files: files, nextCursor: listResponse.nextLink)
    }

    public func delete(fileIDs: [String]) async throws -> CloudDeleteResult {
        let accessToken = try await validAccessToken()

        var succeeded: [String] = []
        var failed: [CloudDeleteFailure] = []

        for fileID in fileIDs {
            // Graph's DELETE already moves the item to the OneDrive recycle
            // bin rather than permanently deleting it — no separate trash
            // endpoint needed here, unlike Drive/Dropbox.
            var request = URLRequest(url: Self.itemsEndpoint.appendingPathComponent(fileID))
            request.httpMethod = "DELETE"
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

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

private struct GraphTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

private struct GraphChildrenResponse: Decodable {
    let value: [GraphDriveItem]
    let nextLink: String?

    enum CodingKeys: String, CodingKey {
        case value
        case nextLink = "@odata.nextLink"
    }
}

private struct GraphDriveItem: Decodable {
    let id: String
    let name: String
    let size: Int64?
    let lastModifiedDateTime: String?
    let file: GraphFileFacet?
    let folder: GraphFolderFacet?
}

private struct GraphFileFacet: Decodable {
    let hashes: GraphHashes?
}

private struct GraphHashes: Decodable {
    let quickXorHash: String?
}

private struct GraphFolderFacet: Decodable {
    let childCount: Int?
}

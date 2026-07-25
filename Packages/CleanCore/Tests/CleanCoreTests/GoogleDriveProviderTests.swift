import Foundation
import Testing
@testable import CleanCore

private struct StubWebSession: OAuthWebSessionPresenting {
    func present(url: URL, callbackURLScheme: String) async throws -> URL {
        URL(string: "\(callbackURLScheme)://callback?code=stub-code")!
    }
}

// GoogleDriveProvider hardcodes its Keychain provider key ("google-drive")
// internally — every test in this file shares that same Keychain entry via
// the same tokenStore service, so they must run one at a time or they'll
// race on save/delete of the same item (confirmed in practice before this
// was added).
@Suite(.serialized)
struct GoogleDriveProviderTests {
    private static let tokenStoreService = "com.nextlabs.sosmac.oauth.tests"
    private static let providerKey = "google-drive" // matches GoogleDriveProvider's internal key

    private func makeProvider(tokenStore: OAuthTokenStore, httpSession: URLSession) -> GoogleDriveProvider {
        GoogleDriveProvider(
            config: CloudProviderConfig(clientID: "test-client", redirectURI: "com.nextlabs.sosmac://oauth"),
            tokenStore: tokenStore,
            webSession: StubWebSession(),
            httpSession: httpSession
        )
    }

    @Test func authenticateWithoutConfigThrowsNotConfigured() async {
        let unconfigured = GoogleDriveProvider(
            config: CloudProviderConfig(),
            tokenStore: OAuthTokenStore(service: Self.tokenStoreService),
            webSession: StubWebSession()
        )
        await #expect(throws: CloudProviderError.notConfigured) {
            try await unconfigured.authenticate()
        }
    }

    @Test func listFilesWithoutAuthenticationThrowsNotAuthenticated() async throws {
        let tokenStore = OAuthTokenStore(service: Self.tokenStoreService)
        try? tokenStore.delete(forProvider: Self.providerKey)

        let provider = makeProvider(tokenStore: tokenStore, httpSession: .shared)
        await #expect(throws: CloudProviderError.notAuthenticated) {
            _ = try await provider.listFiles(cursor: nil)
        }
    }

    @Test func listFilesParsesPageAndMapsMetadataCorrectly() async throws {
        let tokenStore = OAuthTokenStore(service: Self.tokenStoreService)
        try tokenStore.save(
            OAuthToken(accessToken: "test-access-token", refreshToken: nil, expiresAt: nil),
            forProvider: Self.providerKey
        )
        defer { try? tokenStore.delete(forProvider: Self.providerKey) }

        let responseJSON = """
        {
          "nextPageToken": "page-2-token",
          "files": [
            {"id": "f1", "name": "photo.jpg", "size": "1024", "md5Checksum": "abc123", "modifiedTime": "2026-01-01T00:00:00.000Z", "mimeType": "image/jpeg"},
            {"id": "f2", "name": "Folder", "mimeType": "application/vnd.google-apps.folder"}
          ]
        }
        """
        let token = UUID().uuidString
        let session = StubURLProtocol.makeSession(
            token: token,
            responses: [.init(statusCode: 200, data: responseJSON.data(using: .utf8)!)]
        )

        let provider = makeProvider(tokenStore: tokenStore, httpSession: session)
        let page = try await provider.listFiles(cursor: nil)

        #expect(page.nextCursor == "page-2-token")
        #expect(page.files.count == 2)

        let photo = try #require(page.files.first { $0.id == "f1" })
        #expect(photo.size == 1024)
        #expect(photo.contentHash == "abc123")
        #expect(!photo.isFolder)

        let folder = try #require(page.files.first { $0.id == "f2" })
        #expect(folder.isFolder)
        #expect(folder.size == 0) // Drive omits `size` for folders; must default, not crash
    }

    @Test func listFilesFollowsCursorOnSecondPage() async throws {
        let tokenStore = OAuthTokenStore(service: Self.tokenStoreService)
        try tokenStore.save(
            OAuthToken(accessToken: "test-access-token", refreshToken: nil, expiresAt: nil),
            forProvider: Self.providerKey
        )
        defer { try? tokenStore.delete(forProvider: Self.providerKey) }

        let lastPageJSON = """
        {"files": [{"id": "f3", "name": "last.txt", "size": "10"}]}
        """
        let token = UUID().uuidString
        let session = StubURLProtocol.makeSession(
            token: token,
            responses: [.init(statusCode: 200, data: lastPageJSON.data(using: .utf8)!)]
        )

        let provider = makeProvider(tokenStore: tokenStore, httpSession: session)
        let page = try await provider.listFiles(cursor: "page-2-token")

        #expect(page.nextCursor == nil) // no nextPageToken in the response -> pagination ends
        #expect(page.files.first?.id == "f3")
    }
}

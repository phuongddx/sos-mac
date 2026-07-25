import Foundation
import Testing
@testable import CleanCore

struct OAuthTokenStoreTests {
    @Test func saveLoadDeleteRoundTrip() throws {
        let store = OAuthTokenStore(service: "com.nextlabs.sosmac.oauth.tests")
        let providerKey = "test-provider-\(UUID().uuidString)"
        defer { try? store.delete(forProvider: providerKey) }

        let token = OAuthToken(
            accessToken: "access-123",
            refreshToken: "refresh-456",
            expiresAt: Date().addingTimeInterval(3600)
        )
        try store.save(token, forProvider: providerKey)

        let loaded = try store.load(forProvider: providerKey)
        #expect(loaded == token)

        try store.delete(forProvider: providerKey)
        #expect(try store.load(forProvider: providerKey) == nil)
    }

    @Test func loadForUnknownProviderReturnsNil() throws {
        let store = OAuthTokenStore(service: "com.nextlabs.sosmac.oauth.tests")
        let result = try store.load(forProvider: "never-existed-\(UUID().uuidString)")
        #expect(result == nil)
    }

    @Test func saveOverwritesExistingToken() throws {
        let store = OAuthTokenStore(service: "com.nextlabs.sosmac.oauth.tests")
        let providerKey = "test-provider-\(UUID().uuidString)"
        defer { try? store.delete(forProvider: providerKey) }

        try store.save(OAuthToken(accessToken: "old", refreshToken: nil, expiresAt: nil), forProvider: providerKey)
        try store.save(OAuthToken(accessToken: "new", refreshToken: nil, expiresAt: nil), forProvider: providerKey)

        let loaded = try store.load(forProvider: providerKey)
        #expect(loaded?.accessToken == "new")
    }

    @Test func isExpiredReflectsExpiresAt() {
        let expired = OAuthToken(accessToken: "x", refreshToken: nil, expiresAt: Date().addingTimeInterval(-10))
        let valid = OAuthToken(accessToken: "x", refreshToken: nil, expiresAt: Date().addingTimeInterval(10))
        let noExpiry = OAuthToken(accessToken: "x", refreshToken: nil, expiresAt: nil)

        #expect(expired.isExpired)
        #expect(!valid.isExpired)
        #expect(!noExpiry.isExpired)
    }

    @Test func deleteForUnknownProviderDoesNotThrow() throws {
        let store = OAuthTokenStore(service: "com.nextlabs.sosmac.oauth.tests")
        try store.delete(forProvider: "never-existed-\(UUID().uuidString)")
    }
}

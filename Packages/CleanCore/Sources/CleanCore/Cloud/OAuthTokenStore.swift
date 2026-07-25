import Foundation
import Security

public struct OAuthToken: Sendable, Codable, Equatable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresAt: Date?

    public init(accessToken: String, refreshToken: String?, expiresAt: Date?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }

    public var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt <= Date()
    }
}

public enum OAuthTokenStoreError: Error, Sendable {
    case encodingFailed
    case decodingFailed
    case keychainError(OSStatus)
}

/// Stores OAuth tokens in the Keychain — never `UserDefaults` or a plist,
/// since these are long-lived credentials granting real account access.
public struct OAuthTokenStore: Sendable {
    private let service: String

    public init(service: String = "com.nextlabs.sosmac.oauth") {
        self.service = service
    }

    private func query(forProvider provider: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider
        ]
    }

    public func save(_ token: OAuthToken, forProvider provider: String) throws {
        let data: Data
        do {
            data = try JSONEncoder().encode(token)
        } catch {
            throw OAuthTokenStoreError.encodingFailed
        }

        // Delete-then-add makes this an upsert — SecItemUpdate exists too,
        // but delete+add avoids needing to separately handle "item doesn't
        // exist yet" vs "item exists" as different code paths.
        SecItemDelete(query(forProvider: provider) as CFDictionary)

        var addQuery = query(forProvider: provider)
        addQuery[kSecValueData as String] = data
        // ThisDeviceOnly, not just AfterFirstUnlock — these are long-lived,
        // broad-scope OAuth refresh tokens (full Drive/Dropbox/OneDrive
        // access); excluding them from unencrypted-capable backup/restore-
        // to-new-device flows is the safer default for that blast radius.
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw OAuthTokenStoreError.keychainError(status)
        }
    }

    public func load(forProvider provider: String) throws -> OAuthToken? {
        var lookupQuery = query(forProvider: provider)
        lookupQuery[kSecReturnData as String] = true
        lookupQuery[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(lookupQuery as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw OAuthTokenStoreError.keychainError(status)
        }

        do {
            return try JSONDecoder().decode(OAuthToken.self, from: data)
        } catch {
            throw OAuthTokenStoreError.decodingFailed
        }
    }

    public func delete(forProvider provider: String) throws {
        let status = SecItemDelete(query(forProvider: provider) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw OAuthTokenStoreError.keychainError(status)
        }
    }
}

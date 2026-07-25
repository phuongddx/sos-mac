import CryptoKit
import Foundation

public enum SignatureFeedError: Error, Sendable, Equatable {
    /// No feed URL/publisher key configured yet — see `Config`. Fails
    /// closed rather than attempting a doomed fetch, same pattern as
    /// `CloudProviderConfig.notConfigured`.
    case notConfigured
    /// The feed's Ed25519 signature didn't verify against the configured
    /// publisher key — could mean tampering, tampering-in-transit, or a
    /// wrong key configured. Nothing from this feed is ever ingested.
    case invalidSignature
    case staleVersion
    case malformedFeed
    case requestFailed(statusCode: Int)
    case rateLimited
}

/// The wire shape of a signature feed: a versioned hash/rule payload plus a
/// base64 Ed25519 signature over that payload's canonical encoding. A
/// poisoned signature feed is a supply-chain attack vector on every user who
/// trusts Protection's signature DB — this is verified with the same rigor
/// as Sparkle's own appcast signing before anything is trusted.
public struct SignedSignatureFeed: Sendable, Codable {
    public let version: Int
    public let knownBadHashes: [String]
    public let yaraRuleSources: [String]
    public let signatureBase64: String

    public init(version: Int, knownBadHashes: [String], yaraRuleSources: [String], signatureBase64: String) {
        self.version = version
        self.knownBadHashes = knownBadHashes
        self.yaraRuleSources = yaraRuleSources
        self.signatureBase64 = signatureBase64
    }

    /// The exact bytes the publisher signs — deterministic, independent of
    /// `JSONEncoder`'s key-ordering behavior, and injective: every field and
    /// every list element is length-prefixed (never delimiter-separated), so
    /// no re-splitting/merging of `knownBadHashes` or `yaraRuleSources` can
    /// produce identical signed bytes from a different list. A
    /// delimiter-based encoding (e.g. `\n`-joined hashes) would let an
    /// attacker who can edit the feed body without the private key merge
    /// `["aa", "bb"]` into `["aa\nbb"]` — same bytes, same valid signature,
    /// but a hash silently disappears from `knownBadHashes` after decoding.
    public func signedPayload() -> Data {
        var payload = Data()
        payload.append(Self.lengthPrefixed("\(version)"))

        let sortedHashes = knownBadHashes.sorted()
        payload.append(Self.uint32Bytes(sortedHashes.count))
        for hash in sortedHashes {
            payload.append(Self.lengthPrefixed(hash))
        }

        payload.append(Self.uint32Bytes(yaraRuleSources.count))
        for rule in yaraRuleSources {
            payload.append(Self.lengthPrefixed(rule))
        }

        return payload
    }

    private static func uint32Bytes(_ value: Int) -> Data {
        withUnsafeBytes(of: UInt32(value).bigEndian) { Data($0) }
    }

    private static func lengthPrefixed(_ string: String) -> Data {
        let bytes = Data(string.utf8)
        return uint32Bytes(bytes.count) + bytes
    }
}

/// Fetches a signed signature feed and verifies it before trusting a single
/// byte of it. There is no real signature-feed server behind this yet (see
/// Phase 6's identical `.notConfigured` precedent for OAuth apps) — every
/// piece of verification logic below is real and independently testable
/// against a self-signed test keypair; only the production `feedURL`/
/// `publisherPublicKeyBase64` values are missing.
public struct SignatureUpdateChecker: Sendable {
    public struct Config: Sendable {
        public let feedURL: URL?
        public let publisherPublicKeyBase64: String

        public init(feedURL: URL? = nil, publisherPublicKeyBase64: String = "") {
            self.feedURL = feedURL
            self.publisherPublicKeyBase64 = publisherPublicKeyBase64
        }

        public var isConfigured: Bool {
            feedURL != nil && !publisherPublicKeyBase64.isEmpty
        }
    }

    private let config: Config
    private let session: URLSession

    public init(config: Config, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    /// Fetches the feed, verifies its signature, and returns a
    /// `SignatureDatabase` only if verification succeeds and the feed's
    /// version is newer than `currentVersion`. Throws `.invalidSignature` on
    /// any tampering — nothing from an unverified feed is ever ingested.
    public func fetchUpdate(currentVersion: Int) async throws -> SignatureDatabase {
        guard config.isConfigured, let feedURL = config.feedURL else {
            throw SignatureFeedError.notConfigured
        }

        let (data, response): (Data, HTTPURLResponse)
        do {
            (data, response) = try await ProtectionHTTPClient.send(URLRequest(url: feedURL), session: session)
        } catch ProtectionNetworkError.rateLimited {
            throw SignatureFeedError.rateLimited
        } catch ProtectionNetworkError.requestFailed(let statusCode) {
            throw SignatureFeedError.requestFailed(statusCode: statusCode)
        }

        guard (200..<300).contains(response.statusCode) else {
            throw SignatureFeedError.requestFailed(statusCode: response.statusCode)
        }

        let feed: SignedSignatureFeed
        do {
            feed = try JSONDecoder().decode(SignedSignatureFeed.self, from: data)
        } catch {
            throw SignatureFeedError.malformedFeed
        }

        try Self.verify(feed, publisherPublicKeyBase64: config.publisherPublicKeyBase64)

        guard feed.version > currentVersion else {
            throw SignatureFeedError.staleVersion
        }

        return SignatureDatabase(
            version: feed.version,
            knownBadHashes: Set(feed.knownBadHashes.map { $0.lowercased() }),
            yaraRuleSources: feed.yaraRuleSources
        )
    }

    /// Exposed separately from `fetchUpdate` so tests can verify signature
    /// rejection without needing a real network fetch.
    public static func verify(_ feed: SignedSignatureFeed, publisherPublicKeyBase64: String) throws {
        guard let publicKeyData = Data(base64Encoded: publisherPublicKeyBase64),
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData),
              let signature = Data(base64Encoded: feed.signatureBase64)
        else {
            throw SignatureFeedError.invalidSignature
        }

        guard publicKey.isValidSignature(signature, for: feed.signedPayload()) else {
            throw SignatureFeedError.invalidSignature
        }
    }
}

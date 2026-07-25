import CryptoKit
import Foundation
import Testing
@testable import CleanCore

struct SignatureUpdateCheckerTests {
    /// Regression test for a real bypass a code review caught: a
    /// delimiter-joined (not length-prefixed) payload would make
    /// `["aa", "bb"]` and `["aa\nbb"]` sign identically, letting an attacker
    /// re-split a validly-signed feed's hash list without the private key —
    /// silently dropping hashes from `knownBadHashes` after decoding while
    /// keeping the original signature valid. `signedPayload()` must produce
    /// different bytes for these two inputs.
    @Test func signedPayloadIsInjectiveAgainstHashListReSplitting() {
        let merged = SignedSignatureFeed(version: 1, knownBadHashes: ["aa\nbb"], yaraRuleSources: [], signatureBase64: "")
        let split = SignedSignatureFeed(version: 1, knownBadHashes: ["aa", "bb"], yaraRuleSources: [], signatureBase64: "")

        #expect(merged.signedPayload() != split.signedPayload())
    }

    @Test func signedPayloadIsInjectiveAgainstYaraRuleReSplitting() {
        let merged = SignedSignatureFeed(version: 1, knownBadHashes: [], yaraRuleSources: ["rule a {}\u{0}rule b {}"], signatureBase64: "")
        let split = SignedSignatureFeed(version: 1, knownBadHashes: [], yaraRuleSources: ["rule a {}", "rule b {}"], signatureBase64: "")

        #expect(merged.signedPayload() != split.signedPayload())
    }

    @Test func validSignatureVerifiesSuccessfully() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let feed = SignedSignatureFeed(version: 2, knownBadHashes: ["aa", "bb"], yaraRuleSources: ["rule x {}"], signatureBase64: "")
        let signature = try privateKey.signature(for: feed.signedPayload())
        let signedFeed = SignedSignatureFeed(
            version: feed.version,
            knownBadHashes: feed.knownBadHashes,
            yaraRuleSources: feed.yaraRuleSources,
            signatureBase64: signature.base64EncodedString()
        )

        try SignatureUpdateChecker.verify(
            signedFeed,
            publisherPublicKeyBase64: privateKey.publicKey.rawRepresentation.base64EncodedString()
        )
    }

    @Test func tamperedPayloadFailsVerification() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let original = SignedSignatureFeed(version: 2, knownBadHashes: ["aa"], yaraRuleSources: [], signatureBase64: "")
        let signature = try privateKey.signature(for: original.signedPayload())

        // Same signature, but the hash list was tampered with after signing.
        let tampered = SignedSignatureFeed(
            version: original.version,
            knownBadHashes: ["cc"],
            yaraRuleSources: original.yaraRuleSources,
            signatureBase64: signature.base64EncodedString()
        )

        #expect(throws: SignatureFeedError.invalidSignature) {
            try SignatureUpdateChecker.verify(
                tampered,
                publisherPublicKeyBase64: privateKey.publicKey.rawRepresentation.base64EncodedString()
            )
        }
    }

    @Test func wrongPublisherKeyFailsVerification() throws {
        let signer = Curve25519.Signing.PrivateKey()
        let impostor = Curve25519.Signing.PrivateKey()
        let feed = SignedSignatureFeed(version: 1, knownBadHashes: ["aa"], yaraRuleSources: [], signatureBase64: "")
        let signature = try signer.signature(for: feed.signedPayload())
        let signedFeed = SignedSignatureFeed(
            version: feed.version,
            knownBadHashes: feed.knownBadHashes,
            yaraRuleSources: feed.yaraRuleSources,
            signatureBase64: signature.base64EncodedString()
        )

        #expect(throws: SignatureFeedError.invalidSignature) {
            try SignatureUpdateChecker.verify(
                signedFeed,
                publisherPublicKeyBase64: impostor.publicKey.rawRepresentation.base64EncodedString()
            )
        }
    }

    @Test func fetchUpdateFailsClosedWithoutConfiguration() async {
        let checker = SignatureUpdateChecker(config: .init())

        await #expect(throws: SignatureFeedError.notConfigured) {
            _ = try await checker.fetchUpdate(currentVersion: 0)
        }
    }

    @Test func fetchUpdateRejectsAValidlySignedButStaleFeed() async throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let feed = SignedSignatureFeed(version: 1, knownBadHashes: ["aa"], yaraRuleSources: [], signatureBase64: "")
        let signature = try privateKey.signature(for: feed.signedPayload())
        let signedFeed = SignedSignatureFeed(
            version: feed.version,
            knownBadHashes: feed.knownBadHashes,
            yaraRuleSources: feed.yaraRuleSources,
            signatureBase64: signature.base64EncodedString()
        )
        let body = try JSONEncoder().encode(signedFeed)

        let token = UUID().uuidString
        let session = StubURLProtocol.makeSession(
            token: token,
            responses: [.init(statusCode: 200, data: body)]
        )
        let checker = SignatureUpdateChecker(
            config: .init(
                feedURL: URL(string: "https://example.com/feed.json")!,
                publisherPublicKeyBase64: privateKey.publicKey.rawRepresentation.base64EncodedString()
            ),
            session: session
        )

        // currentVersion (1) is not older than the feed's version (1) — a
        // valid signature alone must not be enough to accept a replayed feed.
        await #expect(throws: SignatureFeedError.staleVersion) {
            _ = try await checker.fetchUpdate(currentVersion: 1)
        }
    }

    @Test func fetchUpdateAcceptsANewerValidlySignedFeed() async throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let feed = SignedSignatureFeed(version: 3, knownBadHashes: ["aa", "bb"], yaraRuleSources: ["rule y {}"], signatureBase64: "")
        let signature = try privateKey.signature(for: feed.signedPayload())
        let signedFeed = SignedSignatureFeed(
            version: feed.version,
            knownBadHashes: feed.knownBadHashes,
            yaraRuleSources: feed.yaraRuleSources,
            signatureBase64: signature.base64EncodedString()
        )
        let body = try JSONEncoder().encode(signedFeed)

        let token = UUID().uuidString
        let session = StubURLProtocol.makeSession(
            token: token,
            responses: [.init(statusCode: 200, data: body)]
        )
        let checker = SignatureUpdateChecker(
            config: .init(
                feedURL: URL(string: "https://example.com/feed.json")!,
                publisherPublicKeyBase64: privateKey.publicKey.rawRepresentation.base64EncodedString()
            ),
            session: session
        )

        let database = try await checker.fetchUpdate(currentVersion: 1)
        #expect(database.version == 3)
        #expect(database.knownBadHashes == ["aa", "bb"])
    }
}

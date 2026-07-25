import Foundation

/// The local, versioned copy of known-bad signatures Protection checks
/// candidate files against. Two independent detection modes read the same
/// database: `HashScanner` (exact SHA-256 match) and `YaraScanner` (pattern
/// match via compiled rule sources).
public struct SignatureDatabase: Sendable, Codable, Equatable {
    public var version: Int
    /// Lowercase hex SHA-256 digests.
    public var knownBadHashes: Set<String>
    /// Raw YARA rule-file contents, compiled fresh per `YaraScanner` instance.
    public var yaraRuleSources: [String]

    public init(version: Int = 0, knownBadHashes: Set<String> = [], yaraRuleSources: [String] = []) {
        self.version = version
        // Normalized here, not just in `containsHash`, so every stored hash
        // is comparable regardless of how a caller or signed feed cased its
        // hex — hex case isn't a guaranteed contract for third-party feeds.
        self.knownBadHashes = Set(knownBadHashes.map { $0.lowercased() })
        self.yaraRuleSources = yaraRuleSources
    }

    public static let empty = SignatureDatabase()

    /// SHA-256 of the industry-standard EICAR antivirus test string — the
    /// exact "does your AV even work" smoke test every real AV product
    /// recognizes. Referenced only by hash: the live test string itself is
    /// never stored anywhere in this repository. This machine's own
    /// real-time protection was confirmed (empirically, while building this
    /// phase) to intercept and delete any file containing the literal string
    /// within moments of it hitting disk, which makes an on-disk EICAR
    /// fixture unreliable for automated tests — see `HashScannerTests` for
    /// how detection is verified instead. Computed via `shasum -a 256` /
    /// `hashlib.sha256` over the canonical 68-byte EICAR test string.
    public static let eicarSHA256 = "275a021bbfb6489e54d471899f7db9d1663fc695ec2fe2a2c4538aabf651fd0f"

    /// Shipped with the app so hash-based detection works before any real
    /// signature feed is configured — see `SignatureUpdateChecker` for how a
    /// production feed extends this.
    public static let bundledBaseline = SignatureDatabase(
        version: 1,
        knownBadHashes: [eicarSHA256],
        yaraRuleSources: []
    )

    public func containsHash(_ hash: String) -> Bool {
        knownBadHashes.contains(hash.lowercased())
    }

    /// Merges an updated feed in, keeping the higher version's content.
    /// Never merges backward — a downgrade attempt (e.g. replaying an old,
    /// still-validly-signed-but-stale feed) is a no-op, not a partial merge.
    public func merging(_ update: SignatureDatabase) -> SignatureDatabase {
        guard update.version > version else { return self }
        return update
    }
}

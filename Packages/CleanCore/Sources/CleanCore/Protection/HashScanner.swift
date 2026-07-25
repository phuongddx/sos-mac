import Foundation

/// Detects known-bad files by exact SHA-256 match against a
/// `SignatureDatabase`. Reuses `StreamingHasher`'s chunked-read discipline —
/// malware candidates can be arbitrarily large, same reasoning as Duplicate
/// Finder.
public struct HashScanner: Sendable {
    private let database: SignatureDatabase

    public init(database: SignatureDatabase) {
        self.database = database
    }

    /// Hashes the file at `path` and checks it against the signature
    /// database. Returns `nil` for a clean file, or one that vanished mid-scan
    /// or couldn't be read — fails closed to "no verdict", never a false
    /// "confirmed safe".
    public func scan(path: String, size: Int64) -> ThreatFinding? {
        guard let hash = try? StreamingHasher.sha256(ofFileAtPath: path) else { return nil }
        guard database.containsHash(hash) else { return nil }
        return ThreatFinding(path: path, size: size, detectionMethod: .hash, identifier: hash)
    }
}

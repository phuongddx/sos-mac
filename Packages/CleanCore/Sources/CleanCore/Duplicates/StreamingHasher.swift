import CryptoKit
import Foundation

public enum StreamingHasherError: Error, Sendable {
    case cannotOpenFile(String)
}

/// SHA-256 over a file read in chunks — never `Data(contentsOf:)` on the
/// whole file, which would defeat the point for anything approaching a large
/// video/disk-image/archive.
public enum StreamingHasher {
    private static let chunkSize = 1024 * 1024 // 1 MB

    public static func sha256(ofFileAtPath path: String) throws -> String {
        guard let handle = FileHandle(forReadingAtPath: path) else {
            throw StreamingHasherError.cannotOpenFile(path)
        }
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            let chunk = handle.readData(ofLength: chunkSize)
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

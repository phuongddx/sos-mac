import Foundation

public enum ByteFormatter {
    // A fresh ByteCountFormatter per call, not a cached static instance:
    // NSFormatter subclasses aren't Sendable, and a shared mutable instance
    // would be a data race under Swift 6 strict concurrency if two scanners
    // format sizes concurrently.
    public static func string(fromByteCount bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

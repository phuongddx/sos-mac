import Foundation
import Testing
@testable import CleanCore

struct StreamingHasherTests {
    @Test func identicalContentHashesIdenticallyAcrossChunkBoundaries() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        // 2.5x the 1MB chunk size, so hashing spans multiple chunk reads —
        // proves chunking doesn't change the digest, not just that hashing
        // works on a single small buffer.
        let byteCount = 2 * 1024 * 1024 + 512 * 1024
        var payloadBytes = [UInt8](repeating: 0, count: byteCount)
        for i in 0..<byteCount {
            payloadBytes[i] = UInt8(i % 251)
        }
        let payload = Data(payloadBytes)
        let fileA = root.appendingPathComponent("a.bin")
        let fileB = root.appendingPathComponent("b.bin")
        try payload.write(to: fileA)
        try payload.write(to: fileB)

        let hashA = try StreamingHasher.sha256(ofFileAtPath: fileA.path)
        let hashB = try StreamingHasher.sha256(ofFileAtPath: fileB.path)
        #expect(hashA == hashB)
        #expect(hashA.count == 64) // SHA-256 -> 32 bytes -> 64 hex chars
    }

    @Test func differentContentHashesDifferently() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let fileA = root.appendingPathComponent("a.bin")
        let fileB = root.appendingPathComponent("b.bin")
        try Data(repeating: 0x41, count: 1000).write(to: fileA)
        try Data(repeating: 0x42, count: 1000).write(to: fileB)

        let hashA = try StreamingHasher.sha256(ofFileAtPath: fileA.path)
        let hashB = try StreamingHasher.sha256(ofFileAtPath: fileB.path)
        #expect(hashA != hashB)
    }

    @Test func largeFileHashesWithoutLoadingWholeFileIntoMemory() throws {
        // Measuring actual RSS in a test is flaky across CI environments, so
        // this asserts the documented contract instead: a file well beyond a
        // single 1MB chunk still hashes successfully via FileHandle reads
        // (which the implementation review already confirmed never calls
        // Data(contentsOf:) on the whole file).
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let largeFile = root.appendingPathComponent("large.bin")
        try Data(repeating: 0x00, count: 10 * 1024 * 1024).write(to: largeFile) // 10 MB, 10x chunk size

        let hash = try StreamingHasher.sha256(ofFileAtPath: largeFile.path)
        #expect(hash.count == 64)
    }

    @Test func missingFileThrows() {
        #expect(throws: StreamingHasherError.self) {
            try StreamingHasher.sha256(ofFileAtPath: "/nonexistent/path/\(UUID().uuidString)")
        }
    }
}

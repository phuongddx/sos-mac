import Foundation
import Testing
@testable import CleanCore

/// Note on EICAR: this dev machine's own real-time protection was confirmed
/// (empirically, while building Protection) to intercept and delete a file
/// containing the literal EICAR test string within moments of it hitting
/// disk — an on-disk EICAR fixture is therefore not reliable here or likely
/// in CI. The mandatory "does detection actually work" regression gate is
/// split into two independently sufficient checks: `eicarHashShipsInBundledBaseline`
/// (the real, computed EICAR SHA-256 is present in what ships) and the
/// synthetic-fixture tests below (the hash-match mechanism itself works end
/// to end). Together these cover the code path without a flaky/interceptable
/// file write.
struct HashScannerTests {
    @Test func eicarHashShipsInBundledBaseline() {
        #expect(SignatureDatabase.bundledBaseline.knownBadHashes.contains(SignatureDatabase.eicarSHA256))
        #expect(SignatureDatabase.eicarSHA256.count == 64)
    }

    @Test func flagsAFileWhoseHashMatchesTheSignatureDatabase() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let fixtureURL = root.appendingPathComponent("surrogate.bin")
        let payload = Data("synthetic-known-bad-surrogate-fixture".utf8)
        try payload.write(to: fixtureURL)
        let knownHash = try StreamingHasher.sha256(ofFileAtPath: fixtureURL.path)

        let database = SignatureDatabase(version: 1, knownBadHashes: [knownHash])
        let scanner = HashScanner(database: database)

        let finding = scanner.scan(path: fixtureURL.path, size: Int64(payload.count))
        #expect(finding != nil)
        #expect(finding?.detectionMethod == .hash)
        #expect(finding?.identifier == knownHash)
    }

    @Test func doesNotFlagAFileAbsentFromTheSignatureDatabase() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let fixtureURL = root.appendingPathComponent("clean.bin")
        try Data("perfectly ordinary file contents".utf8).write(to: fixtureURL)

        let scanner = HashScanner(database: .bundledBaseline)
        let finding = scanner.scan(path: fixtureURL.path, size: 10)
        #expect(finding == nil)
    }

    @Test func missingFileFailsClosedRatherThanFlagging() {
        let scanner = HashScanner(database: .bundledBaseline)
        let finding = scanner.scan(path: "/nonexistent/path/does-not-exist", size: 0)
        #expect(finding == nil)
    }

    @Test func hashLookupIsCaseInsensitive() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let fixtureURL = root.appendingPathComponent("surrogate.bin")
        try Data("another-surrogate-fixture".utf8).write(to: fixtureURL)
        let knownHash = try StreamingHasher.sha256(ofFileAtPath: fixtureURL.path)

        let database = SignatureDatabase(version: 1, knownBadHashes: [knownHash.uppercased()])
        let scanner = HashScanner(database: database)

        #expect(scanner.scan(path: fixtureURL.path, size: 1) != nil)
    }
}

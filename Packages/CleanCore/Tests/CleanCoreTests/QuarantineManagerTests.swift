import Foundation
import Testing
@testable import CleanCore

struct QuarantineManagerTests {
    @Test func quarantineThenRestoreRoundTripsToTheExactOriginalPath() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let sourceDirectory = root.appendingPathComponent("source")
        let quarantineDirectory = root.appendingPathComponent("quarantine")
        try fm.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let originalURL = sourceDirectory.appendingPathComponent("suspicious.bin")
        let payload = Data("quarantine round-trip fixture".utf8)
        try payload.write(to: originalURL)

        let manager = QuarantineManager(quarantineDirectory: quarantineDirectory)
        let finding = ThreatFinding(path: originalURL.path, size: Int64(payload.count), detectionMethod: .hash, identifier: "deadbeef")

        let quarantined = try manager.quarantine(finding)
        #expect(!fm.fileExists(atPath: originalURL.path))
        #expect(fm.fileExists(atPath: quarantined.quarantinePath))

        try manager.restore(quarantined)
        #expect(fm.fileExists(atPath: originalURL.path))
        #expect(!fm.fileExists(atPath: quarantined.quarantinePath))
        #expect(try Data(contentsOf: originalURL) == payload)
    }

    @Test func quarantiningAMissingSourceFileThrows() {
        let fm = FileManager.default
        let quarantineDirectory = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let manager = QuarantineManager(quarantineDirectory: quarantineDirectory)
        defer { try? fm.removeItem(at: quarantineDirectory) }

        let finding = ThreatFinding(path: "/nonexistent/path/gone.bin", size: 0, detectionMethod: .hash, identifier: "x")

        #expect(throws: QuarantineError.self) {
            _ = try manager.quarantine(finding)
        }
    }

    @Test func restoringOverAnOccupiedOriginalPathThrowsRatherThanOverwriting() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let sourceDirectory = root.appendingPathComponent("source")
        let quarantineDirectory = root.appendingPathComponent("quarantine")
        try fm.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let originalURL = sourceDirectory.appendingPathComponent("suspicious.bin")
        try Data("original".utf8).write(to: originalURL)

        let manager = QuarantineManager(quarantineDirectory: quarantineDirectory)
        let finding = ThreatFinding(path: originalURL.path, size: 8, detectionMethod: .hash, identifier: "x")
        let quarantined = try manager.quarantine(finding)

        // Something else now occupies the original path (e.g. the user
        // recreated a file at that location) — restore must refuse to
        // silently overwrite it.
        try Data("someone else's file now lives here".utf8).write(to: originalURL)

        #expect(throws: QuarantineError.self) {
            try manager.restore(quarantined)
        }
    }
}

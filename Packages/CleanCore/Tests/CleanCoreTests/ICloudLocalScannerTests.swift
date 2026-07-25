import Foundation
import Testing
@testable import CleanCore

struct ICloudLocalScannerTests {
    /// `~/Library/Mobile Documents` (the real production default) carries
    /// TCC-style permission protection this sandboxed test process doesn't
    /// have (verified: EPERM 13 creating a directory there) — the same
    /// class of restriction Phase 0 hit with `~/.Trash`. Tests inject a temp
    /// directory as `root` instead, exercising the exact same scan logic
    /// against a fixture that mimics the real "Mobile Documents/<container>"
    /// structure.
    @Test func scanFindsFilesInsideSpecifiedContainer() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let containerName = "com~apple~CloudDocs"
        let container = root.appendingPathComponent(containerName)
        try fm.createDirectory(at: container, withIntermediateDirectories: true)

        let noteFile = container.appendingPathComponent("note.txt")
        try "hello".write(to: noteFile, atomically: true, encoding: .utf8)

        let scanner = ICloudLocalScanner(containerFilter: containerName, root: root.path)
        let items = try await scanner.scan()
        #expect(items.contains { $0.path == noteFile.path })
    }

    @Test func containerFilterExcludesOtherContainers() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let targetContainer = root.appendingPathComponent("target-container")
        let otherContainer = root.appendingPathComponent("other-container")
        try fm.createDirectory(at: targetContainer, withIntermediateDirectories: true)
        try fm.createDirectory(at: otherContainer, withIntermediateDirectories: true)

        try "in-target".write(to: targetContainer.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "in-other".write(to: otherContainer.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)

        let scanner = ICloudLocalScanner(containerFilter: "target-container", root: root.path)
        let items = try await scanner.scan()

        #expect(items.contains { $0.path == targetContainer.appendingPathComponent("a.txt").path })
        #expect(!items.contains { $0.path == otherContainer.appendingPathComponent("b.txt").path })
    }

    @Test func noContainerFilterScansEveryContainer() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let containerA = root.appendingPathComponent("container-a")
        let containerB = root.appendingPathComponent("container-b")
        try fm.createDirectory(at: containerA, withIntermediateDirectories: true)
        try fm.createDirectory(at: containerB, withIntermediateDirectories: true)
        try "a".write(to: containerA.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "b".write(to: containerB.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)

        let scanner = ICloudLocalScanner(root: root.path)
        let items = try await scanner.scan()

        #expect(items.contains { $0.path == containerA.appendingPathComponent("a.txt").path })
        #expect(items.contains { $0.path == containerB.appendingPathComponent("b.txt").path })
    }

    @Test func defaultCleanRoutesThroughTrash() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let container = root.appendingPathComponent("com~apple~CloudDocs")
        try fm.createDirectory(at: container, withIntermediateDirectories: true)

        let uniqueName = "delete-me-\(UUID().uuidString).txt"
        let file = container.appendingPathComponent(uniqueName)
        try "temp".write(to: file, atomically: true, encoding: .utf8)

        let scanner = ICloudLocalScanner(root: root.path)
        let item = ScanItem(path: file.path, size: 4, kind: .file)
        let result = try await scanner.clean([item])

        #expect(result.succeeded.count == 1)
        #expect(!fm.fileExists(atPath: file.path))

        let trashURL = try fm.url(for: .trashDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        let landedPath = trashURL.appendingPathComponent(uniqueName).path
        #expect(fm.fileExists(atPath: landedPath))
        try? fm.removeItem(atPath: landedPath)
    }
}

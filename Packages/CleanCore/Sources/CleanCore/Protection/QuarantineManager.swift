import Foundation

public enum QuarantineError: Error, Sendable {
    case sourceFileMissing(String)
    case moveFailed(String)
    case restoreTargetOccupied(String)
}

public struct QuarantinedFile: Sendable, Codable, Identifiable, Hashable {
    public var id: String { quarantinePath }
    public let originalPath: String
    public let quarantinePath: String
    public let threatIdentifier: String
    public let quarantinedAt: Date

    public init(
        originalPath: String,
        quarantinePath: String,
        threatIdentifier: String,
        quarantinedAt: Date = Date()
    ) {
        self.originalPath = originalPath
        self.quarantinePath = quarantinePath
        self.threatIdentifier = threatIdentifier
        self.quarantinedAt = quarantinedAt
    }
}

/// Moves flagged files into an app-managed quarantine folder instead of
/// straight to Trash — reversible via `restore(_:)`, since false positives
/// are a certainty at some point (the plan's own words) and Trash doesn't
/// preserve enough to reliably restore to the exact original path once a
/// user empties it. Deliberately NOT a `Cleaner` conformer: `Cleaner`'s
/// contract is "route through `FileManager.trashItem`", the wrong semantic
/// here — this needs a *tracked*, *targeted* move, not a trash.
///
/// Holds no persistence of its own — same "engine layer stays UI/persistence
/// free" boundary `JunkCleanerViewModel`/`IgnoredItem` already established:
/// the caller (`ProtectionViewModel`) persists the returned `QuarantinedFile`
/// (via a SwiftData `QuarantineRecord` in the App target) so a restore is
/// still possible after an app relaunch.
public struct QuarantineManager: Sendable {
    private let quarantineDirectory: URL

    public init(quarantineDirectory: URL = QuarantineManager.defaultQuarantineDirectory()) {
        self.quarantineDirectory = quarantineDirectory
    }

    public static func defaultQuarantineDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let bundleID = Bundle.main.bundleIdentifier ?? "com.nextlabs.sosmac"
        return appSupport.appendingPathComponent(bundleID).appendingPathComponent("Quarantine")
    }

    @discardableResult
    public func quarantine(_ finding: ThreatFinding) throws -> QuarantinedFile {
        let fileManager = FileManager.default
        let sourceURL = URL(fileURLWithPath: finding.path)
        guard fileManager.fileExists(atPath: finding.path) else {
            throw QuarantineError.sourceFileMissing(finding.path)
        }

        // A unique-per-quarantine subfolder, not a bare filename, so two
        // different original paths that happen to share a last path
        // component (e.g. two different apps' "helper") never collide.
        let destinationDirectory = quarantineDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        } catch {
            throw QuarantineError.moveFailed(error.localizedDescription)
        }
        let destinationURL = destinationDirectory.appendingPathComponent(sourceURL.lastPathComponent)

        do {
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
        } catch {
            // The subfolder was already created above — don't leave an
            // empty, orphaned quarantine directory behind on every failed
            // attempt (permission denied, source vanished mid-move, etc).
            try? fileManager.removeItem(at: destinationDirectory)
            throw QuarantineError.moveFailed(error.localizedDescription)
        }

        return QuarantinedFile(
            originalPath: finding.path,
            quarantinePath: destinationURL.path,
            threatIdentifier: finding.identifier
        )
    }

    public func restore(_ file: QuarantinedFile) throws {
        let fileManager = FileManager.default
        let quarantineURL = URL(fileURLWithPath: file.quarantinePath)
        let originalURL = URL(fileURLWithPath: file.originalPath)

        guard fileManager.fileExists(atPath: file.quarantinePath) else {
            throw QuarantineError.sourceFileMissing(file.quarantinePath)
        }
        guard !fileManager.fileExists(atPath: file.originalPath) else {
            throw QuarantineError.restoreTargetOccupied(file.originalPath)
        }

        do {
            try fileManager.createDirectory(
                at: originalURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.moveItem(at: quarantineURL, to: originalURL)
        } catch {
            throw QuarantineError.moveFailed(error.localizedDescription)
        }

        // Best-effort cleanup of the now-empty per-quarantine subfolder —
        // failing to remove it doesn't affect correctness of the restore.
        try? fileManager.removeItem(at: quarantineURL.deletingLastPathComponent())
    }
}

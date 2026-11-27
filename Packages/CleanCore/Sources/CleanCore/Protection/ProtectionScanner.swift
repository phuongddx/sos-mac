import Foundation

/// A scan root the engine could not open (permission denied or any other read error). The
/// `reason` is the system's own wording — nothing is invented — so the UI can name what was
/// not checked instead of claiming a full sweep.
public struct UnreadableRoot: Sendable, Equatable {
    public let path: String
    public let reason: String

    public init(path: String, reason: String) {
        self.path = path
        self.reason = reason
    }
}

/// What a Protection scan produced: the findings, and the roots it could not read. A root
/// that does not exist is a legitimately empty location and is NOT listed here.
public struct ProtectionScanOutcome: Sendable {
    public let findings: [ThreatFinding]
    public let unreadableRoots: [UnreadableRoot]

    public init(findings: [ThreatFinding], unreadableRoots: [UnreadableRoot] = []) {
        self.findings = findings
        self.unreadableRoots = unreadableRoots
    }
}

public struct ProtectionScanner: Sendable {
    /// Report every N files rather than every single one — the App layer hops
    /// each callback onto the MainActor in its own unstructured `Task`, so a
    /// per-file callback means 10^4–10^5 Tasks for a real `~/Downloads` scan.
    /// Matches the throttling `DiskTreeScanner.buildTree` already does, at a
    /// finer interval because Protection walks far fewer files.
    private static let progressInterval = 200

    private let locations: [ProtectionLocation]
    private let hashScanner: HashScanner
    private let yaraScanner: YaraScanner?

    public init(
        locations: [ProtectionLocation] = ProtectionLocation.allowlist,
        signatureDatabase: SignatureDatabase,
        yaraScanner: YaraScanner? = nil
    ) {
        self.locations = locations
        self.hashScanner = HashScanner(database: signatureDatabase)
        self.yaraScanner = yaraScanner
    }

    public func scan() async throws -> ProtectionScanOutcome {
        try await scan(onProgress: nil)
    }

    public func scan(onProgress: (@Sendable (ScanProgress) -> Void)? = nil) async throws -> ProtectionScanOutcome {
        let fileManager = FileManager.default
        let roots = locations.flatMap { $0.resolvedPaths(fileManager: fileManager) }

        // Open every root before walking it. A missing root is a legitimately empty location;
        // a root that cannot be read is reported and never walked, so "checked" is never
        // claimed for a place the engine could not look into.
        var walkable: [String] = []
        var unreadableRoots: [UnreadableRoot] = []
        for root in roots {
            switch Self.probe(root: root, fileManager: fileManager) {
            case .readable: walkable.append(root)
            case .missing: break
            case .unreadable(let reason): unreadableRoots.append(UnreadableRoot(path: root, reason: reason))
            }
        }

        let totalItems = onProgress == nil ? nil : try await countFiles(under: walkable)

        var findings: [ThreatFinding] = []
        var itemsProcessed = 0

        for root in walkable {
            for await item in FTSWrapper.walk(root: root) where item.kind == .file {
                try Task.checkCancellation()

                if let hashFinding = hashScanner.scan(path: item.path, size: item.size) {
                    findings.append(hashFinding)
                } else if let yaraScanner,
                          let matches = try? yaraScanner.scan(filePath: item.path),
                          let firstMatch = matches.first {
                    findings.append(
                        ThreatFinding(
                            path: item.path,
                            size: item.size,
                            detectionMethod: .yara,
                            identifier: firstMatch.ruleIdentifier
                        )
                    )
                }

                itemsProcessed += 1
                // The final item always reports even when it doesn't land on
                // a throttle boundary, so the bar reliably reaches 100%.
                if itemsProcessed % Self.progressInterval == 0 || itemsProcessed == totalItems {
                    onProgress?(ScanProgress(itemsProcessed: itemsProcessed, totalItems: totalItems, currentPath: item.path))
                }
            }
        }

        // A cancelled task ends the `for await` loops quietly (no element, no throw), so
        // without this a cancelled scan would return a partial outcome that reads as a result.
        try Task.checkCancellation()
        return ProtectionScanOutcome(findings: findings, unreadableRoots: unreadableRoots)
    }

    /// Counts filenames only — never reads file content — so this is cheap
    /// relative to the real hash/YARA pass above. Skipped entirely
    /// (`onProgress == nil`) when the caller doesn't want progress at all.
    /// `async throws` (not just `async`) purely so it can also honor
    /// cancellation — a user cancelling mid-pre-count shouldn't have to wait
    /// for the count to finish before the real scan even starts.
    private func countFiles(under roots: [String]) async throws -> Int {
        var count = 0
        for root in roots {
            for await item in FTSWrapper.walk(root: root) where item.kind == .file {
                try Task.checkCancellation()
                count += 1
            }
            try Task.checkCancellation()
        }
        return count
    }

    private enum RootState {
        case readable
        case missing
        case unreadable(reason: String)
    }

    /// Opens `root` the way the walk will. "No such file or directory" is `missing`; every
    /// other failure (permission denied, not a directory, I/O error) is `unreadable` with the
    /// system's own reason.
    private static func probe(root: String, fileManager: FileManager) -> RootState {
        do {
            _ = try fileManager.contentsOfDirectory(atPath: root)
            return .readable
        } catch {
            let nsError = error as NSError
            let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
            let isMissing = nsError.code == NSFileReadNoSuchFileError
                || nsError.code == NSFileNoSuchFileError
                || (nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(ENOENT))
                || (underlying?.domain == NSPOSIXErrorDomain && underlying?.code == Int(ENOENT))
            return isMissing ? .missing : .unreadable(reason: error.localizedDescription)
        }
    }
}

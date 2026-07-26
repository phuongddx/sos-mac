import Foundation

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

    public func scan() async throws -> [ThreatFinding] {
        try await scan(onProgress: nil)
    }

    public func scan(onProgress: (@Sendable (ScanProgress) -> Void)? = nil) async throws -> [ThreatFinding] {
        let fileManager = FileManager.default
        let roots = locations.flatMap { $0.resolvedPaths(fileManager: fileManager) }
        let totalItems = onProgress == nil ? nil : try await countFiles(under: roots, fileManager: fileManager)

        var findings: [ThreatFinding] = []
        var itemsProcessed = 0

        for root in roots {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: root, isDirectory: &isDirectory), isDirectory.boolValue else {
                continue
            }

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

        return findings
    }

    /// Counts filenames only — never reads file content — so this is cheap
    /// relative to the real hash/YARA pass above. Skipped entirely
    /// (`onProgress == nil`) when the caller doesn't want progress at all.
    /// `async throws` (not just `async`) purely so it can also honor
    /// cancellation — a user cancelling mid-pre-count shouldn't have to wait
    /// for the count to finish before the real scan even starts.
    private func countFiles(under roots: [String], fileManager: FileManager) async throws -> Int {
        var count = 0
        for root in roots {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: root, isDirectory: &isDirectory), isDirectory.boolValue else {
                continue
            }
            for await item in FTSWrapper.walk(root: root) where item.kind == .file {
                try Task.checkCancellation()
                count += 1
            }
        }
        return count
    }
}

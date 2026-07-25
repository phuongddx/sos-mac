import Foundation

/// Walks `ProtectionLocation.allowlist` and checks every file against
/// hash-based (`HashScanner`, always) and pattern-based (`YaraScanner`,
/// optional) detection. Fully offline — `VirusTotalClient` is a separate,
/// explicitly optional supplementary lookup the UI triggers per finding,
/// never a dependency of this scan (the plan's own requirement: don't make
/// the scanner non-functional offline).
public struct ProtectionScanner: Sendable {
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
        var findings: [ThreatFinding] = []
        let fileManager = FileManager.default

        for location in locations {
            for root in location.resolvedPaths(fileManager: fileManager) {
                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: root, isDirectory: &isDirectory), isDirectory.boolValue else {
                    continue
                }

                for await item in FTSWrapper.walk(root: root) where item.kind == .file {
                    if let hashFinding = hashScanner.scan(path: item.path, size: item.size) {
                        findings.append(hashFinding)
                        continue // already flagged by hash; skip the slower YARA pass
                    }

                    if let yaraScanner,
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
                }
            }
        }

        return findings
    }
}

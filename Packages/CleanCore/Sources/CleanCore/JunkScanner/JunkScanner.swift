import Foundation

public struct JunkScanner: Scanner {
    private let now: @Sendable () -> Date
    private let rules: [JunkRule]

    public init(
        rules: [JunkRule] = JunkRule.allowlist,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.rules = rules
        self.now = now
    }

    public func scan() async throws -> [ScanItem] {
        try await scan(onProgress: nil)
    }

    public func scan(onProgress: (@Sendable (ScanProgress) -> Void)? = nil) async throws -> [ScanItem] {
        var results: [ScanItem] = []
        let currentTime = now()
        let fileManager = FileManager.default

        for (index, rule) in rules.enumerated() {
            for root in rule.resolvedRoots(fileManager: fileManager) {
                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: root, isDirectory: &isDirectory), isDirectory.boolValue else {
                    continue
                }

                for await item in FTSWrapper.walk(root: root) where item.kind == .file {
                    try Task.checkCancellation()
                    results.append(
                        ScanItem(
                            path: item.path,
                            size: item.size,
                            kind: item.kind,
                            lastAccessed: item.lastAccessed,
                            severity: rule.severity(for: item.lastAccessed, now: currentTime),
                            sourceLabel: rule.label,
                            requiresPrivilegedHelper: rule.requiresPrivilegedHelper
                        )
                    )
                }
            }
            onProgress?(ScanProgress(itemsProcessed: index + 1, totalItems: rules.count, currentPath: rule.label))
        }

        return results
    }
}

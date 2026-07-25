public protocol Scanner: Sendable {
    func scan() async throws -> [ScanItem]
    func scan(onProgress: (@Sendable (ScanProgress) -> Void)?) async throws -> [ScanItem]
}

public extension Scanner {
    /// Default: no progress reporting. Only a conformer that overrides this
    /// method (JunkScanner, ProtectionScanner-style bespoke additions, etc.)
    /// reports anything — every other existing `Scanner` conformer keeps
    /// compiling and behaving identically with zero changes.
    func scan(onProgress: (@Sendable (ScanProgress) -> Void)?) async throws -> [ScanItem] {
        try await scan()
    }
}

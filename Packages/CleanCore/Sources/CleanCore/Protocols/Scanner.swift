public protocol Scanner: Sendable {
    func scan() async throws -> [ScanItem]
}

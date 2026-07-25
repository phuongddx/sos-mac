import Foundation

/// Runs a named set of `Scanner`s concurrently and aggregates their results
/// into one `SmartCareReport`, grouped by source module — the mechanism
/// behind Smart Care's one-click flow. Which scanners actually get passed in
/// (e.g. `JunkRule.smartCareEligible` rather than the full allowlist) is the
/// caller's decision; this type only orchestrates whatever it's given.
public struct SmartCareOrchestrator: Sendable {
    public struct NamedScanner: Sendable {
        public let name: String
        public let scanner: any Scanner

        public init(name: String, scanner: any Scanner) {
            self.name = name
            self.scanner = scanner
        }
    }

    private let scanners: [NamedScanner]

    public init(scanners: [NamedScanner]) {
        self.scanners = scanners
    }

    /// `onModuleStart`/`onModuleFinish` let a caller drive a live per-module
    /// progress UI without waiting for every scanner to finish. A failing
    /// scanner doesn't abort the others — its module result just carries the
    /// error and an empty item list, matching every other module's
    /// partial-failure handling in this codebase.
    public func run(
        onModuleStart: (@Sendable (String) -> Void)? = nil,
        onModuleFinish: (@Sendable (String, Result<[ScanItem], Error>) -> Void)? = nil
    ) async -> SmartCareReport {
        await withTaskGroup(of: SmartCareModuleResult.self) { group in
            for named in scanners {
                onModuleStart?(named.name)
                group.addTask {
                    do {
                        let items = try await named.scanner.scan()
                        onModuleFinish?(named.name, .success(items))
                        return SmartCareModuleResult(id: named.name, items: items)
                    } catch {
                        onModuleFinish?(named.name, .failure(error))
                        return SmartCareModuleResult(id: named.name, items: [], errorMessage: error.localizedDescription)
                    }
                }
            }

            var results: [SmartCareModuleResult] = []
            for await result in group {
                results.append(result)
            }
            return SmartCareReport(moduleResults: results)
        }
    }
}

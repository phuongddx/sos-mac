import Foundation
import Testing
@testable import CleanCore

private struct FakeScanner: CleanCore.Scanner {
    let items: [ScanItem]
    let delayNanoseconds: UInt64

    init(items: [ScanItem], delayNanoseconds: UInt64 = 0) {
        self.items = items
        self.delayNanoseconds = delayNanoseconds
    }

    func scan() async throws -> [ScanItem] {
        try await scan(onProgress: nil)
    }

    func scan(onProgress: (@Sendable (ScanProgress) -> Void)?) async throws -> [ScanItem] {
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        onProgress?(ScanProgress(itemsProcessed: items.count, totalItems: items.count))
        return items
    }
}

private struct FailingScanner: CleanCore.Scanner {
    struct Failure: Error {}
    func scan() async throws -> [ScanItem] {
        throw Failure()
    }
}

struct SmartCareOrchestratorTests {
    @Test func aggregatesResultsGroupedBySourceWithCorrectTotals() async {
        let junkItems = [
            ScanItem(path: "/tmp/a.cache", size: 100, kind: .file),
            ScanItem(path: "/tmp/b.cache", size: 200, kind: .file)
        ]
        let duplicateItems = [
            ScanItem(path: "/tmp/dup1.jpg", size: 50, kind: .file)
        ]

        let orchestrator = SmartCareOrchestrator(scanners: [
            .init(name: "Junk & Cache", scanner: FakeScanner(items: junkItems)),
            .init(name: "Duplicate Files", scanner: FakeScanner(items: duplicateItems))
        ])

        let report = await orchestrator.run()

        #expect(report.moduleResults.count == 2)
        #expect(report.totalItemCount == 3)
        #expect(report.totalReclaimableBytes == 350)

        let junkResult = try? #require(report.moduleResults.first { $0.id == "Junk & Cache" })
        #expect(junkResult?.items.count == 2)
        #expect(junkResult?.totalBytes == 300)
    }

    @Test func aFailingScannerDoesNotAbortOthersAndCarriesItsError() async {
        let orchestrator = SmartCareOrchestrator(scanners: [
            .init(name: "Junk & Cache", scanner: FakeScanner(items: [
                ScanItem(path: "/tmp/a.cache", size: 10, kind: .file)
            ])),
            .init(name: "Duplicate Files", scanner: FailingScanner())
        ])

        let report = await orchestrator.run()

        let junkResult = report.moduleResults.first { $0.id == "Junk & Cache" }
        let dupResult = report.moduleResults.first { $0.id == "Duplicate Files" }

        #expect(junkResult?.items.count == 1)
        #expect(dupResult?.items.isEmpty == true)
        #expect(dupResult?.errorMessage != nil)
        #expect(report.totalItemCount == 1) // the failing module contributes nothing, not a crash
    }

    @Test func onModuleStartAndFinishCallbacksFireForEveryScanner() async {
        let started = LockedSet()
        let finished = LockedSet()

        let orchestrator = SmartCareOrchestrator(scanners: [
            .init(name: "Junk & Cache", scanner: FakeScanner(items: [], delayNanoseconds: 10_000_000)),
            .init(name: "Duplicate Files", scanner: FakeScanner(items: []))
        ])

        _ = await orchestrator.run(
            onModuleStart: { name in started.insert(name) },
            onModuleFinish: { name, _ in finished.insert(name) }
        )

        #expect(started.values == Set(["Junk & Cache", "Duplicate Files"]))
        #expect(finished.values == Set(["Junk & Cache", "Duplicate Files"]))
    }

    @Test func onItemProgressForwardsPerModuleUpdatesTaggedWithModuleName() async {
        let reported = LockedSet()
        let orchestrator = SmartCareOrchestrator(scanners: [
            .init(name: "Junk & Cache", scanner: FakeScanner(items: [
                ScanItem(path: "/tmp/a.cache", size: 10, kind: .file)
            ]))
        ])

        _ = await orchestrator.run(onItemProgress: { name, _ in reported.insert(name) })

        #expect(reported.values == Set(["Junk & Cache"]))
    }
}

/// Minimal Sendable box for collecting names from concurrent callback
/// invocations in the test above — the callbacks are `@Sendable` and may run
/// on different executors.
private final class LockedSet: @unchecked Sendable {
    private let lock = NSLock()
    private var _values: Set<String> = []

    var values: Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return _values
    }

    func insert(_ value: String) {
        lock.lock()
        defer { lock.unlock() }
        _values.insert(value)
    }
}

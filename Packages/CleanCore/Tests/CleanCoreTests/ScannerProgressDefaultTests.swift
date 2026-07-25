import Foundation
import Testing
@testable import CleanCore

struct ScannerProgressDefaultTests {
    /// A minimal Scanner that does NOT override `scan(onProgress:)` — proves
    /// the protocol's default extension implementation is a true no-op
    /// passthrough to `scan()`, so every pre-existing conformer keeps
    /// compiling and behaving identically without touching them.
    private struct FixedScanner: CleanCore.Scanner {
        let items: [ScanItem]
        func scan() async throws -> [ScanItem] { items }
    }

    private final class CallTracker: @unchecked Sendable {
        var callCount: Int = 0
    }

    @Test func defaultOnProgressOverloadIgnoresCallbackAndReturnsSameItems() async throws {
        let fixedItem = ScanItem(path: "/tmp/fixed", size: 10, kind: .file)
        let scanner = FixedScanner(items: [fixedItem])

        let tracker = CallTracker()
        let items = try await scanner.scan(onProgress: { _ in
            // Default implementation ignores the callback, so this should never be called
            tracker.callCount += 1
        })

        #expect(items.map(\.path) == [fixedItem.path])
        #expect(tracker.callCount == 0)
    }
}

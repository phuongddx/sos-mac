import Foundation
import CleanCore

/// Real cleaning progress without touching the safety boundary (spec §6.5): calls
/// `Cleaner.clean([item])` once per selected item — the one trash-routed extension method —
/// and aggregates the per-item results into a single `CleanResult`.
///
/// Every delete still goes through the protocol's extension method; there is no other trash
/// call site here, and no batch shortcut. A thrown error (the protocol's contract collects
/// failures per item, but a conformer's scanner could still throw) is recorded as a failed
/// item with the engine's reason, and the loop continues.
struct ProgressiveCleaner: Sendable {
    /// Moves `items` one by one.
    ///
    /// - Parameters:
    ///   - items: The user's current selection, in the order the review bar shows it.
    ///   - cleaner: The module's `Cleaner` (or `DefaultCleaner`).
    ///   - progress: Called on the main actor after each item, with the 0-based index of the
    ///     item just attempted and the item itself — the frame's "n of N" is `index + 1`.
    /// - Returns: One aggregated result: every succeeded item and every failure.
    func clean(_ items: [ScanItem],
               using cleaner: any Cleaner,
               progress: (@MainActor (Int, ScanItem) -> Void)? = nil) async -> CleanResult {
        var succeeded: [ScanItem] = []
        var failed: [CleanResult.FailedItem] = []

        for (index, item) in items.enumerated() {
            do {
                let result = try await cleaner.clean([item])
                succeeded.append(contentsOf: result.succeeded)
                failed.append(contentsOf: result.failed)
            } catch {
                failed.append(CleanResult.FailedItem(item: item, reason: error.localizedDescription))
            }
            if let progress {
                await progress(index, item)
            }
        }

        return CleanResult(succeeded: succeeded, failed: failed)
    }
}

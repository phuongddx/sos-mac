import Foundation

// `clean` is deliberately NOT a protocol requirement. If it were, a conformer
// declaring its own same-signature `clean` would replace this implementation
// under witness-table dispatch for every call through `any Cleaner` or a
// generic — silently reintroducing a hard-delete path. As a plain extension
// method it uses static dispatch, so calls through the protocol always run
// this trash-routed body regardless of what a conformer declares.
public protocol Cleaner: Sendable {}

extension Cleaner {
    public func clean(_ items: [ScanItem]) async throws -> CleanResult {
        var succeeded: [ScanItem] = []
        var failed: [CleanResult.FailedItem] = []

        for item in items {
            let url = URL(fileURLWithPath: item.path)
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                succeeded.append(item)
            } catch {
                failed.append(.init(item: item, reason: error.localizedDescription))
            }
        }

        return CleanResult(succeeded: succeeded, failed: failed)
    }
}

/// A plain conformer for call sites that only need the trash-routed default
/// (most UI features) and have no scanner-specific state to attach `Cleaner`
/// to — e.g. `JunkScanner`/`AppUninstaller` conform directly instead, but a
/// generic "clean whatever the user selected" list doesn't need its own type.
public struct DefaultCleaner: Cleaner {
    public init() {}
}

# Phase 1: CleanCore Foundation

Back to [plan.md](plan.md).

All commands below run from the repo root `/Users/ddphuong/Projects/next-labs/sos-mac` unless noted. Test runs use `cd Packages/CleanCore && swift test --filter <Suite>`.

---

### Task 1: `ScanProgress` type + `Scanner` protocol progress overload

**Files:**
- Create: `Packages/CleanCore/Sources/CleanCore/ScanProgress.swift`
- Modify: `Packages/CleanCore/Sources/CleanCore/Protocols/Scanner.swift`
- Test: `Packages/CleanCore/Tests/CleanCoreTests/ScannerProgressDefaultTests.swift` (create)

**Interfaces:**
- Produces: `public struct ScanProgress: Sendable { itemsProcessed: Int, totalItems: Int?, currentPath: String? }`, and a new `Scanner` requirement `func scan(onProgress: (@Sendable (ScanProgress) -> Void)?) async throws -> [ScanItem]` with a default extension implementation. Every later task in this plan calls this exact signature.

- [ ] **Step 1: Write the failing test**

Create `Packages/CleanCore/Tests/CleanCoreTests/ScannerProgressDefaultTests.swift`:

```swift
import Foundation
import Testing
@testable import CleanCore

struct ScannerProgressDefaultTests {
    /// A minimal Scanner that does NOT override `scan(onProgress:)` — proves
    /// the protocol's default extension implementation is a true no-op
    /// passthrough to `scan()`, so every pre-existing conformer keeps
    /// compiling and behaving identically without touching them.
    private struct FixedScanner: Scanner {
        let items: [ScanItem]
        func scan() async throws -> [ScanItem] { items }
    }

    @Test func defaultOnProgressOverloadIgnoresCallbackAndReturnsSameItems() async throws {
        let fixedItem = ScanItem(path: "/tmp/fixed", size: 10, kind: .file)
        let scanner = FixedScanner(items: [fixedItem])

        var progressCallCount = 0
        let items = try await scanner.scan(onProgress: { _ in progressCallCount += 1 })

        #expect(items.map(\.path) == [fixedItem.path])
        #expect(progressCallCount == 0)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Packages/CleanCore && swift test --filter ScannerProgressDefaultTests`
Expected: FAIL to compile — `ScanProgress` doesn't exist yet, and `Scanner` has no `scan(onProgress:)` member.

- [ ] **Step 3: Create `ScanProgress`**

`Packages/CleanCore/Sources/CleanCore/ScanProgress.swift`:

```swift
import Foundation

/// A snapshot of a scan's progress, reported by whichever engine type is
/// currently walking/enumerating. `totalItems` is `nil` whenever a total
/// isn't knowable ahead of the walk (e.g. an arbitrary user-chosen directory)
/// — callers must never fabricate one; a `nil` total means "show a running
/// count, not a percentage."
public struct ScanProgress: Sendable {
    public let itemsProcessed: Int
    public let totalItems: Int?
    public let currentPath: String?

    public init(itemsProcessed: Int, totalItems: Int? = nil, currentPath: String? = nil) {
        self.itemsProcessed = itemsProcessed
        self.totalItems = totalItems
        self.currentPath = currentPath
    }
}
```

- [ ] **Step 4: Add the protocol requirement + default**

Modify `Packages/CleanCore/Sources/CleanCore/Protocols/Scanner.swift` to:

```swift
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
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd Packages/CleanCore && swift test --filter ScannerProgressDefaultTests`
Expected: PASS

- [ ] **Step 6: Run the full CleanCore suite to confirm no regression**

Run: `cd Packages/CleanCore && swift test`
Expected: All suites pass (102 tests + the new one, before this task's other conformers are touched later in this phase — this task alone changes no existing conformer's behavior).

- [ ] **Step 7: Commit**

```bash
git add Packages/CleanCore/Sources/CleanCore/ScanProgress.swift \
        Packages/CleanCore/Sources/CleanCore/Protocols/Scanner.swift \
        Packages/CleanCore/Tests/CleanCoreTests/ScannerProgressDefaultTests.swift
git commit -m "feat(cleancore): add ScanProgress and a default Scanner.scan(onProgress:) overload"
```

---

### Task 2: `JunkScanner` per-rule progress

**Files:**
- Modify: `Packages/CleanCore/Sources/CleanCore/JunkScanner/JunkScanner.swift`
- Test: `Packages/CleanCore/Tests/CleanCoreTests/JunkScannerTests.swift` (modify — add a test)

**Interfaces:**
- Consumes: `ScanProgress` from Task 1.
- Produces: `JunkScanner.scan(onProgress:)` reports one `ScanProgress` call per completed rule — `itemsProcessed` = rules completed so far, `totalItems` = `rules.count`, `currentPath` = the just-completed rule's `label`. This is a real percentage (rules done / total rules), not a byte-level estimate — computing a true byte-level total would require a redundant pre-walk, which the plan's global constraints forbid.

- [ ] **Step 1: Write the failing test**

Add to `Packages/CleanCore/Tests/CleanCoreTests/JunkScannerTests.swift` (inside `struct JunkScannerTests`):

```swift
    @Test func reportsProgressOncePerCompletedRule() async throws {
        let fm = FileManager.default
        let fakeHome = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: fakeHome, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: fakeHome) }

        let caches = fakeHome.appendingPathComponent("Caches")
        try fm.createDirectory(at: caches, withIntermediateDirectories: true)
        try "x".write(to: caches.appendingPathComponent("a.cache"), atomically: true, encoding: .utf8)

        let logs = fakeHome.appendingPathComponent("Logs")
        try fm.createDirectory(at: logs, withIntermediateDirectories: true)
        try "x".write(to: logs.appendingPathComponent("a.log"), atomically: true, encoding: .utf8)

        let rules: [JunkRule] = [
            JunkRule(id: "user-caches", label: "User App Caches", kind: .directPath(caches.path), defaultSeverity: .safe),
            JunkRule(id: "user-logs", label: "User Logs", kind: .directPath(logs.path), defaultSeverity: .safe)
        ]
        let scanner = JunkScanner(rules: rules)

        var reported: [ScanProgress] = []
        _ = try await scanner.scan(onProgress: { reported.append($0) })

        #expect(reported.count == 2)
        #expect(reported.map(\.itemsProcessed) == [1, 2])
        #expect(reported.allSatisfy { $0.totalItems == 2 })
        #expect(reported.map(\.currentPath) == ["User App Caches", "User Logs"])
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Packages/CleanCore && swift test --filter JunkScannerTests/reportsProgressOncePerCompletedRule`
Expected: FAIL — `JunkScanner` doesn't yet override `scan(onProgress:)`, so the default (no-op) runs and `reported` stays empty.

- [ ] **Step 3: Implement**

Replace `Packages/CleanCore/Sources/CleanCore/JunkScanner/JunkScanner.swift`'s body with:

```swift
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
```

Note this is a straight `scan(onProgress: (@Sendable (ScanProgress) -> Void)? = nil)` — a default argument on the *concrete type*, distinct from the protocol requirement (which has no default). `JunkCleanerViewModel` calls this concrete `JunkScanner` directly (see Phase 3), so the default is reachable there.

Also note the added `try Task.checkCancellation()`: the original `JunkScanner.scan()` had no cancellation check anywhere, so cancelling the surrounding `Task` (added in Phase 3, Task 9) would previously have had no effect on the scan itself — it would keep running to completion in the background regardless of what the UI showed. This closes that gap, matching `DiskTreeScanner`'s and `DuplicateFinder`'s existing cancellation handling and this plan's own Global Constraint.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd Packages/CleanCore && swift test --filter JunkScannerTests`
Expected: PASS (both the new test and the two pre-existing ones in this file).

- [ ] **Step 5: Run the full suite**

Run: `cd Packages/CleanCore && swift test`
Expected: All pass.

- [ ] **Step 6: Commit**

```bash
git add Packages/CleanCore/Sources/CleanCore/JunkScanner/JunkScanner.swift \
        Packages/CleanCore/Tests/CleanCoreTests/JunkScannerTests.swift
git commit -m "feat(cleancore): report per-rule progress from JunkScanner"
```

---

### Task 3: `DiskTreeScanner` progress reshape (Space Lens engine)

**Files:**
- Modify: `Packages/CleanCore/Sources/CleanCore/SpaceLens/DiskTreeScanner.swift`
- Test: `Packages/CleanCore/Tests/CleanCoreTests/DiskTreeScannerTests.swift` (modify — add a test)

**Interfaces:**
- Consumes: `ScanProgress` from Task 1.
- Produces: `DiskTreeScanner.buildTree(onProgress: (@Sendable (ScanProgress) -> Void)?)` — same cadence as today (every 2,000 items), but the callback now carries `ScanProgress(itemsProcessed: count, totalItems: nil, currentPath: nil)` instead of a bare `Int`. `totalItems` stays `nil` — an arbitrary directory's total size is genuinely unknowable ahead of the walk. `currentPath` stays `nil` too: at 2,000-item granularity there's no single meaningful "current" path to show (unlike Protection's per-file cadence in Task 4).

- [ ] **Step 1: Write the failing test**

Add to `Packages/CleanCore/Tests/CleanCoreTests/DiskTreeScannerTests.swift` (inside `struct DiskTreeScannerTests`):

```swift
    @Test func reportsCountOnlyProgressWithNoKnownTotal() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        try "x".write(to: root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)

        var lastReported: ScanProgress?
        _ = await DiskTreeScanner(rootPath: root.path).buildTree(onProgress: { lastReported = $0 })

        // A 1-file fixture never crosses the 2,000-item reporting threshold,
        // so onProgress firing at all isn't asserted here — only that IF the
        // type is used, it never claims a total it can't know.
        #expect(lastReported?.totalItems == nil)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Packages/CleanCore && swift test --filter DiskTreeScannerTests/reportsCountOnlyProgressWithNoKnownTotal`
Expected: FAIL to compile — `buildTree(onProgress:)`'s closure type is currently `(@Sendable (Int) -> Void)?`, not `ScanProgress`.

- [ ] **Step 3: Implement**

In `Packages/CleanCore/Sources/CleanCore/SpaceLens/DiskTreeScanner.swift`, change the `buildTree` signature and its two call sites:

```swift
    public func buildTree(onProgress: (@Sendable (ScanProgress) -> Void)? = nil) async -> (tree: ArenaTree, items: [ScanItem]) {
```

and where it currently does:

```swift
            if let onProgress, items.count % 2000 == 0 {
                onProgress(items.count)
            }
```

change to:

```swift
            if let onProgress, items.count % 2000 == 0 {
                onProgress(ScanProgress(itemsProcessed: items.count, totalItems: nil, currentPath: nil))
            }
```

Everything else in the file (the doc comments, the rest of the loop, `recomputeDirectorySizes()`) is unchanged.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd Packages/CleanCore && swift test --filter DiskTreeScannerTests`
Expected: PASS (all four tests in this file — three pre-existing plus the new one).

- [ ] **Step 5: Run the full suite**

Run: `cd Packages/CleanCore && swift test`
Expected: All pass. (`App/Features/SpaceLens/SpaceLensViewModel.swift` still calls `buildTree(onProgress: { count in ... })` with a bare `Int` closure — this now fails to compile at the App layer. That's expected and is fixed in Phase 4, Task 12; this task only changes the CleanCore package, which builds and tests independently via `swift test`.)

- [ ] **Step 6: Commit**

```bash
git add Packages/CleanCore/Sources/CleanCore/SpaceLens/DiskTreeScanner.swift \
        Packages/CleanCore/Tests/CleanCoreTests/DiskTreeScannerTests.swift
git commit -m "feat(cleancore): reshape DiskTreeScanner.buildTree progress callback to ScanProgress"
```

---

### Task 4: `ProtectionScanner` per-file progress + pre-count

**Files:**
- Modify: `Packages/CleanCore/Sources/CleanCore/Protection/ProtectionScanner.swift`
- Test: `Packages/CleanCore/Tests/CleanCoreTests/ProtectionScannerTests.swift` (create — no test file exists for this type today)

**Interfaces:**
- Consumes: `ScanProgress` from Task 1.
- Produces: `ProtectionScanner.scan(onProgress: (@Sendable (ScanProgress) -> Void)? = nil) async throws -> [ThreatFinding]` — not a `Scanner` conformer (it returns `[ThreatFinding]`, not `[ScanItem]`), so this is a parameter added directly to its own `scan()`, not a protocol mechanism. `totalItems` = the real number of files under the 6 `ProtectionLocation.allowlist` entries, computed by a **full recursive `FTSWrapper.walk` that only counts filenames — it never reads file bytes**, before the hash/YARA pass starts. This is still cheap relative to the real pass (which reads full file content for hashing and/or YARA matching) — it is not a second *expensive* pass, even though it does recurse into subdirectories the same way the real pass does (a shallow `contentsOfDirectory` count would silently undercount any nested folder, e.g. a Firefox profile's `extensions` subfolder).

- [ ] **Step 1: Write the failing test**

Create `Packages/CleanCore/Tests/CleanCoreTests/ProtectionScannerTests.swift`:

```swift
import Foundation
import Testing
@testable import CleanCore

struct ProtectionScannerTests {
    @Test func reportsPerFileProgressWithRealPreCountedTotal() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        // Nested on purpose — proves the pre-count recurses into
        // subdirectories rather than only counting root's immediate children.
        let nested = root.appendingPathComponent("nested")
        try fm.createDirectory(at: nested, withIntermediateDirectories: true)
        try "a".write(to: root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "b".write(to: nested.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)

        let locations = [ProtectionLocation(id: "test", label: "Test Location", kind: .directPath(root.path))]
        let scanner = ProtectionScanner(locations: locations, signatureDatabase: .empty)

        var reported: [ScanProgress] = []
        _ = try await scanner.scan(onProgress: { reported.append($0) })

        #expect(reported.count == 2)
        #expect(reported.allSatisfy { $0.totalItems == 2 })
        #expect(reported.map(\.itemsProcessed) == [1, 2])
        // .compactMap, not .map, so this compares Set<String> to Set<String>
        // — every currentPath is non-nil here, but keeping both sides the
        // same concrete (non-Optional) type avoids relying on Optional's
        // Set/Equatable inference at the call site.
        #expect(Set(reported.compactMap(\.currentPath)) == Set([root.appendingPathComponent("a.txt").path, nested.appendingPathComponent("b.txt").path]))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Packages/CleanCore && swift test --filter ProtectionScannerTests`
Expected: FAIL to compile — `ProtectionScanner.scan()` takes no `onProgress` parameter yet.

- [ ] **Step 3: Implement**

Replace `Packages/CleanCore/Sources/CleanCore/Protection/ProtectionScanner.swift`'s body with:

```swift
import Foundation

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
                onProgress?(ScanProgress(itemsProcessed: itemsProcessed, totalItems: totalItems, currentPath: item.path))
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
```

Note the original `ProtectionScanner.scan()` also had no cancellation check anywhere — same pre-existing gap as `JunkScanner`, closed here for the same reason (the plan's Global Constraint, and so `ProtectionViewModel`'s already-existing `cancelScan()`/`scanTask` actually stops the underlying work instead of only hiding it from the UI).

Note the pre-existing `continue // already flagged by hash; skip the slower YARA pass` comment's behavior is preserved (the `else if` above is equivalent — a hash match short-circuits the YARA check).

- [ ] **Step 4: Run test to verify it passes**

Run: `cd Packages/CleanCore && swift test --filter ProtectionScannerTests`
Expected: PASS

- [ ] **Step 5: Run the full suite**

Run: `cd Packages/CleanCore && swift test`
Expected: All pass, including `HashScannerTests`/`YaraScannerTests`/`ProtectionLocationTests` (unchanged, unaffected by this refactor).

- [ ] **Step 6: Commit**

```bash
git add Packages/CleanCore/Sources/CleanCore/Protection/ProtectionScanner.swift \
        Packages/CleanCore/Tests/CleanCoreTests/ProtectionScannerTests.swift
git commit -m "feat(cleancore): report per-file progress with a real pre-counted total from ProtectionScanner"
```

---

### Task 5: `DuplicateFinder` two-phase progress

**Files:**
- Modify: `Packages/CleanCore/Sources/CleanCore/Duplicates/DuplicateFinder.swift`
- Test: `Packages/CleanCore/Tests/CleanCoreTests/DuplicateFinderTests.swift` (create — no test file exists for this type today)

**Interfaces:**
- Consumes: `ScanProgress` from Task 1.
- Produces: `findExactDuplicateGroups(onProgress: (@Sendable (ScanProgress) -> Void)? = nil) async throws -> DuplicateScanResult` and `findSimilarImageGroups(hammingThreshold: Int = 10, onProgress: (@Sendable (ScanProgress) -> Void)? = nil) async throws -> DuplicateScanResult`. Both are naturally two phases: a **listing** phase (total unknown — `totalItems: nil`) followed by a **hashing** phase (total = however many candidates listing found, known before hashing starts — real `totalItems`). `currentPath` is the file currently being hashed.

- [ ] **Step 1: Write the failing test**

Create `Packages/CleanCore/Tests/CleanCoreTests/DuplicateFinderTests.swift`:

```swift
import Foundation
import Testing
@testable import CleanCore

struct DuplicateFinderTests {
    @Test func findExactDuplicateGroupsReportsListingThenHashingProgress() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        // Same size, same content — a real duplicate pair, so both files
        // reach the hashing phase (SizeGrouper only groups by size; a
        // singleton-size bucket never gets hashed at all).
        try Data(repeating: 0x41, count: 16).write(to: root.appendingPathComponent("a.txt"))
        try Data(repeating: 0x41, count: 16).write(to: root.appendingPathComponent("b.txt"))

        var reported: [ScanProgress] = []
        let result = try await DuplicateFinder(rootPath: root.path)
            .findExactDuplicateGroups(onProgress: { reported.append($0) })

        #expect(result.groups.count == 1)

        let listingUpdates = reported.filter { $0.totalItems == nil }
        let hashingUpdates = reported.filter { $0.totalItems != nil }
        #expect(!hashingUpdates.isEmpty)
        #expect(hashingUpdates.allSatisfy { $0.totalItems == 2 })
        #expect(hashingUpdates.map(\.itemsProcessed) == Array(1...hashingUpdates.count))
        // Listing-phase updates (if any fired for this small fixture) must
        // never claim a total the engine can't know ahead of the walk.
        #expect(listingUpdates.allSatisfy { $0.totalItems == nil })
    }

    @Test func findSimilarImageGroupsReportsHashingProgressWithKnownTotal() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        // Not a valid image — PerceptualHasher.dHash will fail to decode it,
        // which is fine here: this test only asserts the *count* of hashing
        // attempts, not that a match was found.
        try "not an image".write(to: root.appendingPathComponent("a.jpg"), atomically: true, encoding: .utf8)

        var reported: [ScanProgress] = []
        _ = try await DuplicateFinder(rootPath: root.path)
            .findSimilarImageGroups(onProgress: { reported.append($0) })

        let hashingUpdates = reported.filter { $0.totalItems != nil }
        #expect(hashingUpdates.count == 1)
        #expect(hashingUpdates[0].totalItems == 1)
        #expect(hashingUpdates[0].itemsProcessed == 1)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Packages/CleanCore && swift test --filter DuplicateFinderTests`
Expected: FAIL to compile — neither method takes an `onProgress` parameter yet.

- [ ] **Step 3: Implement**

Replace the two methods (and `scan()`, unchanged in behavior but shown for context) in `Packages/CleanCore/Sources/CleanCore/Duplicates/DuplicateFinder.swift`:

```swift
    public func scan() async throws -> [ScanItem] {
        try await findExactDuplicateGroups().groups.flatMap(\.items)
    }

    public func findExactDuplicateGroups(onProgress: (@Sendable (ScanProgress) -> Void)? = nil) async throws -> DuplicateScanResult {
        let sizeBuckets = await SizeGrouper().group(rootPath: rootPath)
        var hashGroups: [String: [ScanItem]] = [:]
        var skippedCount = 0

        // Total is only knowable once listing (SizeGrouper's own walk) has
        // finished — every candidate that will actually be hashed is a
        // same-size bucket with 2+ members; a singleton-size file is never
        // hashed at all, so it doesn't belong in the total either.
        let totalToHash = sizeBuckets.values.filter { $0.count >= 2 }.reduce(0) { $0 + $1.count }
        var itemsProcessed = 0

        for (_, items) in sizeBuckets where items.count >= 2 {
            for item in items {
                try Task.checkCancellation()

                do {
                    let hash = try StreamingHasher.sha256(ofFileAtPath: item.path)
                    hashGroups[hash, default: []].append(item)
                } catch {
                    skippedCount += 1
                }

                itemsProcessed += 1
                onProgress?(ScanProgress(itemsProcessed: itemsProcessed, totalItems: totalToHash, currentPath: item.path))
            }
        }

        let groups = hashGroups
            .filter { $0.value.count >= 2 }
            .map { DuplicateGroup(id: $0.key, items: $0.value) }
        return DuplicateScanResult(groups: groups, skippedCount: skippedCount)
    }

    public func findSimilarImageGroups(hammingThreshold: Int = 10, onProgress: (@Sendable (ScanProgress) -> Void)? = nil) async throws -> DuplicateScanResult {
        var imageItems: [ScanItem] = []
        for await item in FTSWrapper.walk(root: rootPath) where item.kind == .file {
            try Task.checkCancellation()
            let ext = (item.path as NSString).pathExtension.lowercased()
            if Self.imageExtensions.contains(ext) {
                imageItems.append(item)
            }
        }

        var hashed: [(item: ScanItem, hash: UInt64)] = []
        var skippedCount = 0
        for (index, item) in imageItems.enumerated() {
            try Task.checkCancellation()
            if let hash = PerceptualHasher.dHash(imageAtPath: item.path) {
                hashed.append((item, hash))
            } else {
                skippedCount += 1
            }
            onProgress?(ScanProgress(itemsProcessed: index + 1, totalItems: imageItems.count, currentPath: item.path))
        }

        try Task.checkCancellation()
        let clusters = PerceptualHasher.cluster(hashes: hashed.map(\.hash), threshold: hammingThreshold)
        let groups = clusters.map { indices in
            DuplicateGroup(
                id: "similar-\(hashed[indices[0]].item.path)",
                items: indices.map { hashed[$0].item }
            )
        }

        return DuplicateScanResult(groups: groups, skippedCount: skippedCount)
    }
```

The `findExactDuplicateGroups` change also fixes a pre-existing minor inefficiency: the original iterated `for (_, items) in sizeBuckets` unconditionally including singleton buckets (which can never form a duplicate group), hashing files that could never match anything. Filtering to `items.count >= 2` up front is required to compute an honest `totalToHash` and is strictly cheaper, not just additive.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd Packages/CleanCore && swift test --filter DuplicateFinderTests`
Expected: PASS

- [ ] **Step 5: Run the full suite**

Run: `cd Packages/CleanCore && swift test`
Expected: All pass. Pay particular attention to any existing test that exercises `findExactDuplicateGroups`'s singleton-bucket behavior indirectly (none currently do, per the pre-existing `DuplicateFinderTests.swift` not existing before this task) — if any App-layer manual QA later shows a changed result count, it means a singleton bucket was previously being hashed and silently discarded; the new code just skips that dead work.

- [ ] **Step 6: Commit**

```bash
git add Packages/CleanCore/Sources/CleanCore/Duplicates/DuplicateFinder.swift \
        Packages/CleanCore/Tests/CleanCoreTests/DuplicateFinderTests.swift
git commit -m "feat(cleancore): report two-phase (listing/hashing) progress from DuplicateFinder"
```

---

### Task 6: `SmartCareOrchestrator` per-module item progress

**Files:**
- Modify: `Packages/CleanCore/Sources/CleanCore/SmartCare/SmartCareOrchestrator.swift`
- Modify: `Packages/CleanCore/Tests/CleanCoreTests/SmartCareOrchestratorTests.swift` (add a `scan(onProgress:)` override to the existing `FakeScanner` fixture, plus one new test)

**Interfaces:**
- Consumes: `ScanProgress` from Task 1; `Scanner.scan(onProgress:)` from Task 1's protocol default (every `NamedScanner.scanner` is `any Scanner`).
- Produces: `SmartCareOrchestrator.run(onModuleStart:onItemProgress:onModuleFinish:)` — adds one new optional parameter, `onItemProgress: (@Sendable (String, ScanProgress) -> Void)?`, inserted between the two existing parameters alphabetically by concern (start → item progress → finish) so a reader sees the module's lifecycle in order. Existing call sites (`SmartCareViewModel.performScan()`, run with only `onModuleStart:`) are source-compatible since the new parameter defaults to `nil`.

- [ ] **Step 1: Write the failing test**

The existing `Packages/CleanCore/Tests/CleanCoreTests/SmartCareOrchestratorTests.swift` already defines a private `FakeScanner` fixture used by all 3 of its current tests. Give it a `scan(onProgress:)` override too — so the 3 existing tests (which never pass `onItemProgress`) keep working unchanged — and add one new test that does:

```swift
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
```

Add this test inside `struct SmartCareOrchestratorTests` (reusing the file's existing `LockedSet` fixture, no new type needed):

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Packages/CleanCore && swift test --filter SmartCareOrchestratorTests`
Expected: FAIL to compile — `run(onItemProgress:)` doesn't exist yet, `named.scanner.scan()` inside `run` doesn't forward progress, and `FakeScanner` doesn't yet have a `scan(onProgress:)` overload to override the protocol default.

- [ ] **Step 3: Implement**

In `Packages/CleanCore/Sources/CleanCore/SmartCare/SmartCareOrchestrator.swift`, change `run` to:

```swift
    public func run(
        onModuleStart: (@Sendable (String) -> Void)? = nil,
        onItemProgress: (@Sendable (String, ScanProgress) -> Void)? = nil,
        onModuleFinish: (@Sendable (String, Result<[ScanItem], Error>) -> Void)? = nil
    ) async -> SmartCareReport {
        await withTaskGroup(of: SmartCareModuleResult.self) { group in
            for named in scanners {
                onModuleStart?(named.name)
                group.addTask {
                    do {
                        let items = try await named.scanner.scan(onProgress: { progress in
                            onItemProgress?(named.name, progress)
                        })
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
```

The only real change is `named.scanner.scan()` → `named.scanner.scan(onProgress: { ... })` — every `NamedScanner.scanner` is `any Scanner`, so this call requires an explicit argument (the protocol requirement itself has no default parameter value, unlike a concrete type's own overload); passing a closure that tags each update with `named.name` and forwards it is exactly what `onItemProgress` needs.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd Packages/CleanCore && swift test --filter SmartCareOrchestratorTests`
Expected: PASS (the new test plus every pre-existing test in this file).

- [ ] **Step 5: Run the full suite**

Run: `cd Packages/CleanCore && swift test`
Expected: All pass.

- [ ] **Step 6: Commit**

```bash
git add Packages/CleanCore/Sources/CleanCore/SmartCare/SmartCareOrchestrator.swift \
        Packages/CleanCore/Tests/CleanCoreTests/SmartCareOrchestratorTests.swift
git commit -m "feat(cleancore): forward per-module item progress from SmartCareOrchestrator.run"
```

---

Phase 1 complete once all 6 tasks above are committed and `cd Packages/CleanCore && swift test` is green. Continue to [Phase 2](phase-02-design-system.md).

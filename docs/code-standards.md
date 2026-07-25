# Code Standards & Architectural Rules

This document captures the cross-cutting architectural principles and implementation patterns that define SOS Mac's codebase. These are **not style guidelines** — they are enforceable design decisions that prevent entire classes of bugs.

## Core Architectural Rules

### Rule 1: Trash-Safe by Design (Structural Enforcement)

**Principle**: All file deletions route through `FileManager.trashItem(at:)`. This is not a convention — it's structurally enforced via the protocol design.

**Implementation**:
```swift
public protocol Cleaner: Sendable {}

extension Cleaner {
    // NOT a protocol requirement. Implemented as a plain extension method.
    // This ensures static dispatch; no conformer can shadow it via 
    // witness-table dispatch.
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

public struct DefaultCleaner: Cleaner {
    public init() {}
}
```

**Why**: A protocol requirement `func clean(...)` can be shadowed by a conformer's own `clean(...)` declaration under witness-table dispatch, reintroducing a hard-delete path. By making `clean` a non-requirement extension method, we use static dispatch regardless of conformer declarations. Every call goes through this body.

**Consequence**: There is **zero way** to add a direct-delete path to this codebase without removing this protocol altogether. Code reviewers can assert: "No hard deletes exist" by verifying the protocol structure alone.

### Rule 2: Keep Newest = mtime, Not atime

**Principle**: When duplicate finders mark "keep newest" or similar logic, the comparison is ALWAYS against file modification time (`lastModified`), never access time (`lastAccessed`).

**Why**: Access time is unreliable — any file viewer bumps atime. Modification time is the true creation/last-edit timestamp.

**Where This Rule Appears**:
1. `ScanItem` model distinguishes `lastAccessed` and `lastModified`
2. `DuplicateFinder` uses only `lastModified` for sorting
3. `SmartCare` recommendations use `lastModified` when suggesting which duplicate to keep
4. Tests verify this (don't just check for "newest" — verify it uses mtime)

**Implementation Example**:
```swift
// In DuplicateFinder
let sortedByTime = duplicates.sorted { $0.lastModified > $1.lastModified }
// NOT: sorted { $0.lastAccessed > $1.lastAccessed }
```

### Rule 3: Fail-Closed, Never Guess

**Principle**: When the codebase encounters an ambiguous or risky situation, it fails explicitly (throws or returns nil/notConfigured) rather than guessing or using a safe-but-inaccurate default.

**Examples**:

**SysctlReader** (validates struct sizes before trusting):
```swift
public struct SysctlReader {
    public static func readMemory() throws -> MemoryStats {
        var size = MemoryStats.memSize // Pre-computed struct size
        let (vm, phys) = try read(named: "vm.memory_stats", expectedSize: size)
        // Fails if sysctlbyname returns a different size
        // Does NOT read anyway and hope it's correct
    }
}
```

**IOKitSensors** (refuses SMC key reading):
```swift
public func temperatureFromSMC() -> Double? {
    // Always returns nil. No public API exists for SMC keys.
    // We do NOT guess by reading raw IORegistry keys.
    return nil
}

public func thermalState() -> ProcessInfo.ThermalState {
    // Explicitly uses the public ProcessInfo.thermalState API
    return ProcessInfo.processInfo.thermalState
}
```

**CloudProvider** (fails if OAuth app not registered):
```swift
public enum CloudProviderConfig {
    case notConfigured
    case configured(clientID: String, ...)
    
    // If a provider can't be instantiated, we fail loudly, not silently
}
```

**JunkRule** (allowlist, never heuristic):
```swift
// Does NOT use "path contains 'cache'" heuristic
// Instead: explicit list of known-safe paths to clean
let knownJunkPaths = [
    "~/Library/Caches",
    "/Library/Caches",
    "/var/tmp",
    ...
]
```

### Rule 4: Partial-Failure Tolerance

**Principle**: Systems are designed so that one component failing does not abort the entire operation.

**Patterns**:

**CleanResult separates success and failure**:
```swift
public struct CleanResult: Sendable {
    public let succeeded: [ScanItem]
    public let failed: [FailedItem]
}
```
UI displays both: "Deleted 100 items, failed to delete 3" — not just "cleaning failed".

**SmartCareOrchestrator runs scanners in TaskGroup**:
```swift
public func scan() async throws -> SmartCareReport {
    var results: [ScannerResult] = []
    var errors: [Error] = []

    try await withThrowingTaskGroup(...) { group in
        // If JunkScanner throws, Duplicates and Performance still run
        // Errors are collected, not thrown immediately
    }
    
    return SmartCareReport(results: results, errors: errors)
}
```

**Cloud deletion tracks per-item success**:
```swift
public struct CloudDeleteResult {
    let succeeded: [CloudItem]
    let failed: [(item: CloudItem, error: Error)]
}
```

### Rule 5: Streaming Over Buffering

**Principle**: For large-tree operations, yield results incrementally in an AsyncStream rather than accumulating in memory.

**FTSWrapper** (BSD fts() streamer):
```swift
public struct FTSWrapper {
    public func walk(at root: String) -> AsyncStream<ScanItem> {
        return AsyncStream { continuation in
            // Does NOT buffer entire tree
            // Yields ScanItem as traversed
            let fts = FTSInstance(at: root)
            while let entry = fts.next() {
                continuation.yield(ScanItem(from: entry))
            }
        }
    }
}
```

**StreamingHasher** (chunked SHA-256):
```swift
public func hash(filePath: String) async throws -> String {
    var context = CC_SHA256_CTX()
    let handle = try FileHandle(forReadingAtPath: filePath)
    
    while true {
        let chunk = try handle.readUpToCount(8192)
        if chunk.isEmpty { break }
        CC_SHA256_Update(&context, chunk, UInt32(chunk.count))
    }
    // Never loads entire file into memory
}
```

**ArenaTree** (array-of-structs, not class-per-node):
```swift
public struct ArenaTree {
    private var nodes: [Node] = []
    private var stringPool: StringPool = StringPool()
    
    // Scales to millions of files without ARC overhead per node
    // One allocation for node array, one for string pool
}
```

### Rule 6: Never Auto-Delete Without Explicit User Confirm

**Principle**: Deletion always requires user initiation. Recommendations are proposals, not actions.

**Patterns**:
- Smart Care shows recommendations but doesn't pre-select them
- Duplicate Finder groups similar images but doesn't mark any for deletion
- Junk Cleaner shows cache candidates but requires "Clean" button tap
- Cloud Cleanup requires explicit "Delete from Drive" confirmation per group

**Consequence**: No "click OK, stuff disappears" UI. Every delete is multi-step: scan → review → confirm → execute.

### Rule 7: Consistent ViewModel Phase-Enum Pattern

**Principle**: Every feature ViewModel uses an explicit `Phase` enum state machine:
```swift
@MainActor @Observable final class XViewModel {
    enum Phase {
        case idle
        case scanning
        case review(results: [ScanItem])
        case cleaning
        case done(result: CleanResult)
        case error(Error)
    }
    
    @ObservationIgnored var scanTask: Task<Void, Never>?
    @ObservationIgnored var cleanTask: Task<Void, Never>?
    
    var phase: Phase = .idle
    
    func startScan() async {
        phase = .scanning
        scanTask = Task {
            do {
                let results = try await scanner.scan()
                phase = .review(results: results)
            } catch {
                phase = .error(error)
            }
        }
    }
}
```

**View layer** maps phase to UI:
```swift
struct XView: View {
    @State private var viewModel = XViewModel()
    
    var body: some View {
        switch viewModel.phase {
        case .idle:
            idleView()
        case .scanning:
            loadingView()
        case .review(let results):
            reviewView(results: results)
        case .cleaning:
            cleaningProgressView()
        case .done(let result):
            doneView(result: result)
        case .error(let error):
            errorView(error: error)
        }
    }
}
```

**Benefit**: UI state is explicit, single source of truth. No hidden state across multiple @State vars that can get out of sync.

## Cross-Cutting Implementation Patterns

### Pattern 1: Protocol-Based Conformance for Testability

Every engine module provides:
```swift
public protocol Scanner: Sendable {
    func scan() async throws -> [ScanItem]
}

public protocol Cleaner: Sendable {}  // + default clean(_:) impl

public struct XScanner: Scanner {
    public func scan() async throws -> [ScanItem] { ... }
}

public struct XCleaner: Cleaner {}
```

**Benefit**: Tests inject mock/fixture conformers; production uses real ones. No stubs, no fragile mocking.

### Pattern 2: Async Streaming for Large Operations

```swift
public struct FTSWrapper {
    public func walk(at root: String) -> AsyncStream<ScanItem> { ... }
}

// Use:
for await item in ftsWrapper.walk(at: path) {
    // Process one item at a time, never buffer
}
```

### Pattern 3: TaskGroup for Concurrent Scanners (with Error Aggregation)

```swift
public func scan() async throws -> SmartCareReport {
    var results: [ScannerResult] = []
    var errors: [ScannerError] = []

    try await withThrowingTaskGroup(of: ScannerResult.self) { group in
        group.addTask { try await junkScanner.scan() }
        group.addTask { try await duplicates.scan() }
        group.addTask { try await performance.scan() }
        
        for try await result in group {
            results.append(result)
        }
    } catch {
        errors.append(ScannerError(scanner: .unknown, error: error))
    }
    
    return SmartCareReport(results: results, partialErrors: errors)
}
```

### Pattern 4: Per-Test URLProtocol Stubbing (Not Shared Static)

```swift
class CloudProviderTests {
    @Test("Drive API lists files") async throws {
        let token = UUID()
        let stubHandler = TestURLProtocolHandler { request in
            // This token ensures this test doesn't interfere with others
            return MockDriveResponse(token: token)
        }
        
        let session = URLSession(stubHandler: stubHandler)
        let provider = GoogleDriveProvider(session: session)
        let files = try await provider.listFiles()
        
        #expect(files.count > 0)
    }
}
```

**Why**: Shared static URLProtocol queues caused real race conditions under Swift Testing. Per-test tokens isolate tests.

### Pattern 5: @Suite(.serialized) for Keychain Tests

```swift
@Suite(.serialized)  // Prevents concurrent Keychain mutation
struct OAuthTokenStoreTests {
    @Test("Store and retrieve token") async throws {
        let store = OAuthTokenStore(keychainService: "test.\(UUID())")
        try store.save(token: testToken)
        let retrieved = try store.load()
        #expect(retrieved.accessToken == testToken.accessToken)
    }
}
```

### Pattern 6: Sandbox-Free Test Fixtures

```swift
class CloudCleanupTests {
    @Test("Scan iCloud documents") async throws {
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }
        
        let scanner = ICloudLocalScanner(homeOverride: tempDir)
        let results = try await scanner.scan()
        
        #expect(!results.isEmpty)
    }
}
```

**Why**: Real ~/Library/Mobile Documents requires iCloud setup + TCC permissions. Tests inject temp fixtures instead.

## Swift 6 Strict Concurrency Compliance

**Build Setting**: `SWIFT_STRICT_CONCURRENCY: complete` on all targets.

**Requirements**:
- All ViewModel: `@MainActor`
- All Scanner/Cleaner: `Sendable` or explicitly isolated
- All shared mutable state: Protected via actors or isolated properties
- No unsafe Task captures of non-Sendable values

**Common Patterns**:

**MainActor ViewModel**:
```swift
@MainActor @Observable final class XViewModel {
    var phase: Phase = .idle
    // Properties accessed only on MainThread
}
```

**Sendable Scanner**:
```swift
public struct JunkScanner: Scanner, Sendable {
    private let fileSystem: FileSystemInterface  // Must be Sendable
    public func scan() async throws -> [ScanItem] { ... }
}
```

**Isolated Actor**:
```swift
actor KeychainStore {
    private var tokens: [String: String] = [:]
    
    func save(_ token: String, forKey key: String) {
        tokens[key] = token
    }
}
```

## Testing Standards

### Unit Test Pattern (per scanner/cleaner)

```swift
@Suite struct JunkScannerTests {
    let scanner: JunkScanner
    let tempRoot: String
    
    init() async throws {
        tempRoot = try makeTempDirectory()
        scanner = JunkScanner(root: tempRoot)
    }
    
    @Test("Finds cache files") async throws {
        try createFile(at: "\(tempRoot)/Library/Caches/test.cache")
        let results = try await scanner.scan()
        #expect(results.contains { $0.path.contains("test.cache") })
    }
    
    @Test("Never finds non-junk files") async throws {
        try createFile(at: "\(tempRoot)/Documents/important.txt")
        let results = try await scanner.scan()
        #expect(!results.contains { $0.path.contains("important.txt") })
    }
}
```

### Delete Path Verification

Every test that exercises a Cleaner must assert the file ends up in Trash:

```swift
@Test("Cleaning moves files to trash") async throws {
    let testFile = try createTempFile()
    let scanner = TestScanner(items: [testFile])
    let cleaner = DefaultCleaner()
    
    let result = try await cleaner.clean([testFile])
    
    #expect(result.succeeded.count == 1)
    let trashPath = try FileManager.default.trashContents().first?
        .path.hasSuffix(testFile.lastComponent) ?? false
    #expect(trashPath)
}
```

### Real-Hardware Sanity Range Assertions

```swift
@Test("CPU usage is reasonable") async throws {
    let stats = try SysctlReader.readCPU()
    #expect(stats.loadAverage >= 0)
    #expect(stats.loadAverage <= Double(ProcessInfo.processInfo.processorCount) * 2)
}
```

## Known Gaps (Intentional, Not Bugs)

1. **No .entitlements file yet** — Required for Phase 9 distribution
2. **Privileged helper not implemented** — Phase 8 only, buttons disabled
3. **MenuBarHelper not auto-launching** — SMAppService registration deferred
4. **GPU utilization always nil** — No public API; don't guess
5. **Cloud OAuth apps not registered** — Requires human dev account setup
6. **Token refresh never tested against real expiry** — Would need staging account with expired token

## Code Review Checklist

Before approving any PR:

- [ ] All new Cleaners conform to `Cleaner` protocol (no direct FileManager calls)
- [ ] All new Scanners return `[ScanItem]` via `async throws`
- [ ] New tests use per-test URLProtocol tokens (not shared static)
- [ ] Keychain-accessing tests use `@Suite(.serialized)`
- [ ] No `try?` swallowing errors without logging/fallback
- [ ] New ViewModels use explicit `Phase` enum pattern
- [ ] No direct `FileManager` calls outside CleanCore
- [ ] All Swift 6 data race warnings resolved (strict concurrency)
- [ ] Tests don't touch real user files (~/.Trash, ~/Documents, etc.)

## Documentation Map

- **README.md** — How to build, what's shipped
- **docs/project-overview-pdr.md** — Product and roadmap
- **docs/codebase-summary.md** — File/module structure
- **docs/code-standards.md** (this file) — Architectural rules
- **docs/system-architecture.md** — Protocol design and dependency graph
- **plans/0724-2335-macos-cleaner-suite/plan.md** — Phase-by-phase implementation

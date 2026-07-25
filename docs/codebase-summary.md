# Codebase Summary

This document provides a structural overview of the SOS Mac codebase organized by target, package, and module.

## Top-Level Organization

```
sos-mac/
├── App/                    # Main SwiftUI application target (macOS)
├── MenuBarHelper/          # Separate menu-bar-extra app target
├── Packages/
│   ├── CleanCore/         # Core engine Swift package
│   └── TreemapKit/        # Pure-geometry treemap layout package
├── project.yml            # XcodeGen configuration (source of truth)
├── plans/                 # Phase-by-phase implementation plans
└── docs/                  # User and architectural documentation
```

## App Target (`App/`)

**Role**: SwiftUI-based user interface for all 8 feature modules.

**Entry Point**: `SOSMacApp.swift` (20 lines)
- Decorates `RootView()` with `NavigationSplitView` root
- Attaches SwiftData `.modelContainer(for: IgnoredItem.self)`
- Defines `SidebarDestination` enum with 9 cases (dashboard + 8 modules)

**Structure**:
```
App/
├── SOSMacApp.swift                  # @main, NavigationSplitView root, SidebarDestination enum
└── Features/
    ├── SmartCare/
    │   ├── SmartCareView.swift
    │   └── SmartCareViewModel.swift
    ├── JunkCleaner/
    │   ├── JunkCleanerView.swift
    │   └── JunkCleanerViewModel.swift
    ├── Duplicates/
    │   ├── DuplicateFinderView.swift
    │   └── DuplicateFinderViewModel.swift
    ├── SpaceLens/
    │   ├── SpaceLensView.swift
    │   └── SpaceLensViewModel.swift
    ├── Uninstaller/
    │   ├── UninstallerView.swift
    │   └── UninstallerViewModel.swift
    ├── Updater/
    │   ├── UpdaterView.swift
    │   └── UpdaterViewModel.swift
    ├── Performance/
    │   ├── PerformanceView.swift
    │   └── PerformanceViewModel.swift
    └── CloudCleanup/
        ├── CloudCleanupView.swift
        ├── CloudCleanupViewModel.swift
        └── ASWebAuthSessionPresenter.swift
```

**Module Architecture Pattern**:
Each feature module follows a consistent pattern:

1. **ViewModel** (`@MainActor @Observable final class XViewModel`):
   - State machine via explicit `Phase` enum (idle → scanning → review → cleaning → done)
   - `@ObservationIgnored` properties for non-observable refs (e.g., Task cancellation)
   - Async methods that transition phases and populate results
   
2. **View** (`struct XView: View`):
   - Declares `@State private var viewModel = XViewModel()`
   - Binds UI to viewModel state
   - Shows loading/results/error states by Phase
   - Calls viewModel methods on user interaction

3. **Special Case** (JunkCleaner only):
   - Requires `@Environment(\.modelContext)` for SwiftData ignore list
   - Lazy-initializes ViewModel in `.task` after context is available
   - All other modules don't use SwiftData

**Total Lines**: ~2,138 LOC (excluding generated assets).

## MenuBarHelper Target (`MenuBarHelper/`)

**Role**: Separate embedded `.app` process (not IPC-connected to main app). Shows system metrics (CPU, RAM, Disk) in the menu bar.

**File Structure**:
```
MenuBarHelper/
├── MenuBarHelperApp.swift       # @main, MenuBarExtra entry
└── MenuBarHelperView.swift      # SwiftUI view with periodic metrics updates
```

**Key Details**:
- Links CleanCore directly (no IPC with main app)
- Polls system metrics every 2 seconds independently
- Embedded into main app bundle via postbuild script:
  ```
  cp -R ${BUILT_PRODUCTS_DIR}/MenuBarHelper.app 
       ${BUILT_PRODUCTS_DIR}/${CONTENTS_FOLDER_PATH}/Library/LoginItems/
  ```
- Not yet auto-launching (SMAppService registration deferred)
- Uses same `SWIFT_STRICT_CONCURRENCY: complete` as main app

**Total Lines**: ~100 LOC.

## CleanCore Package (`Packages/CleanCore/`)

**Role**: Protocol-based engine with zero UI dependencies. Every module exposes `Scanner` and `Cleaner` conformance for unit testing and reusability.

### Module Breakdown

#### Protocols (`Protocols/`)
**Files**: `Scanner.swift`, `Cleaner.swift`

`Scanner` protocol:
```swift
public protocol Scanner: Sendable {
    func scan() async throws -> [ScanItem]
}
```

`Cleaner` protocol:
```swift
public protocol Cleaner: Sendable {}

extension Cleaner {
    public func clean(_ items: [ScanItem]) async throws -> CleanResult {
        // Routes every delete through FileManager.trashItem(at:)
    }
}
```

**Critical Design**: `clean` is NOT a protocol requirement — it's a plain extension method that uses static dispatch. This prevents any conformer from shadowing the Trash path via witness-table dispatch. Enforces trash-only deletion structurally.

#### Models (`Models/`)
**Files**: `ScanItem.swift`, `Severity.swift`, `CleanResult.swift`

- `ScanItem`: path, size, kind (file/folder), severity, lastAccessed, lastModified
- `Severity`: enum (safe < caution < risky)
- `CleanResult`: succeeded: [ScanItem], failed: [FailedItem]

#### FileSystem (`FileSystem/`)

**ByteFormatter.swift**: Formats byte counts (KB, MB, GB, TB).

**Shell.swift**: Supervised Process runner with:
- Concurrent stdout/stderr draining (avoids pipe deadlock)
- Timeout via cancellable Task + terminationReason check
- Used for privileged operations and shell commands

**FTSWrapper.swift**: Wraps BSD `fts()` C API in AsyncStream:
- Never buffers entire directory tree
- Yields ScanItem as traversed
- Used by all large-tree scanners (Junk, SpaceLens, Duplicates)
- C shim in `Sources/CFTS/` target

#### JunkScanner (`JunkScanner/`)

**JunkRule.swift**: Explicit allowlist of junk paths (caches, temp, logs).
- NOT heuristic-based (the #1 way cleaner apps lose user trust)
- Reviewed during development; auditable

**JunkScanner.swift**: Implements `Scanner` protocol.
- Walks system cache directories (~/Library/Caches, /Library/Caches, /var/tmp, etc.)
- Filters by JunkRule allowlist
- Yields ScanItem with severity labels

#### Duplicates (`Duplicates/`)

**SizeGrouper.swift**: First pass — group files by size.

**StreamingHasher.swift**: 
- Chunked SHA-256 hash (never loads entire file)
- Compares hashes to find exact duplicates
- Yields groups of identical files

**DuplicateFinder.swift**: Implements `Scanner` protocol.
- Composes SizeGrouper + StreamingHasher
- Tracks skippedCount (files that couldn't be hashed)

**PerceptualHasher.swift**: 
- dHash algorithm for similar images
- Optional; used only if user enables "similar images" scan
- Clusters results via single-linkage clustering

#### SpaceLens (`SpaceLens/`)

**ArenaTree.swift**: Array-of-structs tree (not class-per-node).
- Interned string pool for path components
- Scales to millions of files
- Pure struct, no ARC overhead

**DiskTreeScanner.swift**: Scans entire filesystem → ArenaTree.
- Uses FTSWrapper for streaming
- Aggregates by file type and directory

**FileTypeAggregator.swift**: Categorizes files (images, video, documents, archives, etc.).

#### SmartCare (`SmartCare/`)

**SmartCareOrchestrator.swift**:
- Runs Junk, Duplicates, and Performance scanners concurrently via TaskGroup
- Partial-failure tolerant: if one fails, others still complete
- Returns SmartCareReport with all results

**SmartCareReport.swift**: Aggregates results from all scanners.

#### Uninstaller (`Uninstaller/`)

**BundleAssociatedFilesFinder.swift**:
- Locates app support files by bundle ID prefix match
- Guards against empty-bundleID wildcard match (would delete everything)
- Finds: ~/Library/Application Support/*, ~/Library/Caches/BundleID*, etc.

**AppUninstaller.swift**: Implements `Scanner` and `Cleaner`.
- Scans for installed apps
- Pairs each with its associated files

#### Updater (`Updater/`)

**InstalledAppsEnumerator.swift**: Lists all installed apps.

**SparkleAppcastChecker.swift**: Read-only.
- Polls Sparkle appcast (if registered)
- Reports available updates
- Does NOT install (Phase 9)

#### Performance (`Performance/`)

**SysctlReader.swift**: 
- Typed wrapper around Darwin sysctlbyname
- Validates POD sizes before reading
- Fails rather than guesses

**MachHostStats.swift**: Calls `host_statistics64` for:
- CPU load, memory usage, swap usage

**IOKitSensors.swift**:
- Reads fan speeds via IOKit
- Thermal state via ProcessInfo.thermalState
- Deliberately does NOT read raw SMC keys (no public API)
- GPU utilization always returns nil (not guessed)

**LoginItemsManager.swift**: Uses SMAppService (not deprecated SMLoginItemSetEnabled).

#### Cloud (`Cloud/`)

**CloudProvider.swift**: Protocol for OAuth2 + REST providers.

**GoogleDriveProvider.swift**: 
- Real OAuth2 + Drive API v3
- Lists files, folders, metadata
- Implements delete via API call

**DropboxProvider.swift**: 
- Real OAuth2 + Dropbox API v2
- Lists files with metadata
- Implements delete

**OneDriveProvider.swift**: 
- Real OAuth2 + Microsoft Graph
- Delta endpoint for efficient syncing
- Implements delete

**OAuthTokenStore.swift**: Keychain storage.
- kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
- Token refresh lifecycle

**CloudHTTPClient.swift**: 
- Shared URLSession config
- Exponential backoff on network errors
- Request/response logging

**CloudFormEncoding.swift**: 
- Multipart form-data encoding
- Used by OAuth token endpoints

**CloudDuplicateGrouper.swift**: 
- Metadata-only dedup (no downloads)
- Groups by hash/size

**ICloudLocalScanner.swift**: 
- Scans ~/Library/Mobile Documents (synced iCloud)
- No public iCloud API
- Local-filesystem Scanner implementation

**OAuthWebSessionPresenting.swift**: Protocol for ASWebAuthenticationSession.
- Impl lives in App target (UI layer) as ASWebAuthSessionPresenter
- Keeps CleanCore UI-free

### Tests (`Tests/CleanCoreTests/`)

**Pattern**: Per-module test file; 19 test files total.

**Notable Testing Patterns**:
1. **Per-test URLProtocol stubbing**: Each test registers its own URLProtocol subclass. Shared static queue caused real race conditions under Swift Testing concurrency — fixed by per-test token.

2. **@Suite(.serialized)**: Used when multiple tests share Keychain state (e.g., OAuthTokenStoreTests, CloudCleanupTests). Prevents concurrent Keychain mutation.

3. **Sandbox-free test fixture**: 
   - Temp directory fixture instead of real ~/Library/Mobile Documents
   - `root:` and `homeOverride:` injectable params to avoid TCC permission walls
   - Tests don't require actual iCloud, Keychain, or ~/.Trash access (mocked or overridden)

4. **Real-hardware sanity ranges**: Sysctl/mach stats assertions check for realistic ranges rather than mocking syscalls (can't meaningfully mock syscall return values; testing is about "it doesn't crash" and "result is in expected range").

**Coverage Gaps** (Known, not critical):
- No dedicated DropboxProvider tests
- No OneDriveProvider tests
- No AppUninstaller tests
- No InstalledAppsEnumerator tests
- No SparkleAppcastChecker tests

Total: ~1,800 LOC of test code.

## TreemapKit Package (`Packages/TreemapKit/`)

**Role**: Pure-geometry treemap layout algorithm. Zero dependencies. Reusable from SwiftUI or any other context.

**Single File**: `SquarifiedTreemap.swift`

**Public API**:
```swift
public static func layout(
    values: [CGFloat],
    in rect: CGRect
) -> [CGRect]
```

**Algorithm**: Squarified treemap (Bruls, Huizing, van Wijk 1999).
- Lays out rectangles with aspect ratios as close to 1.0 as possible
- Minimizes whitespace and thin slivers
- Used by SpaceLens to visualize disk usage

## Build Configuration

**project.yml** (XcodeGen source of truth):
- Targets: SOSMac (main), MenuBarHelper (embedded app)
- Packages: CleanCore, TreemapKit
- Deployment target: macOS 14.0+
- Bundle ID prefix: com.nextlabs
- Swift 6.0, SWIFT_STRICT_CONCURRENCY: complete
- Hardened Runtime enabled
- Postbuild script embeds MenuBarHelper.app to Library/LoginItems

**Build & Test**:
```bash
xcodegen generate              # Regenerate from project.yml
xcodebuild build -scheme SOSMac
xcodebuild test -scheme CleanCore
```

## Lines of Code Summary

| Component | LOC | Notes |
|-----------|-----|-------|
| App (UI) | 2,138 | 8 feature modules + root |
| MenuBarHelper | ~100 | Menu bar extra app |
| CleanCore (engine) | ~11,000 | 12 modules + tests |
| TreemapKit | ~150 | Single-file treemap algorithm |
| Tests | ~1,800 | 19 test files, per-module coverage |
| **Total** | **~15,000** | Production + tests |

## Key Files for Understanding Architecture

Start here when learning the codebase:

1. **App/SOSMacApp.swift** — Root structure, module navigation
2. **Packages/CleanCore/Sources/CleanCore/Protocols/Cleaner.swift** — Trash-safe design (most critical)
3. **Packages/CleanCore/Sources/CleanCore/Models/ScanItem.swift** — Common data model
4. **App/Features/SmartCare/SmartCareViewModel.swift** — Orchestration pattern
5. **Packages/CleanCore/Sources/CleanCore/FileSystem/FTSWrapper.swift** — Streaming scanner pattern
6. **Packages/CleanCore/Sources/CleanCore/Duplicates/DuplicateFinder.swift** — Streaming hash pattern
7. **Packages/CleanCore/Sources/CleanCore/Cloud/GoogleDriveProvider.swift** — OAuth2 + REST pattern

## Dependency Graph

```
App (SOSMac) → CleanCore + TreemapKit
              ↓
          SwiftUI, SwiftData, Darwin (sysctl, mach, IOKit)

MenuBarHelper → CleanCore
              ↓
          SwiftUI, Darwin

CleanCore → SwiftData (for models), URLSession, Keychain, Darwin
          → (no UI frameworks; pure Swift)
```

## Concurrency Model

- All ViewModels: `@MainActor @Observable`
- All scanners: Async/await with `async throws`
- Smart Care orchestration: TaskGroup-based concurrent scanners
- Cloud providers: Isolated by per-provider URLSession
- Tests: Swift Testing with @Suite, @Test, confirmation

## Documentation Map

- **README.md** — Quick start, what's built, how to build
- **docs/project-overview-pdr.md** — Product vision, features, roadmap
- **docs/codebase-summary.md** (this file) — Structural overview
- **docs/code-standards.md** — Architectural rules and patterns
- **docs/system-architecture.md** — Protocol design, dependency graph, known gaps
- **plans/0724-2335-macos-cleaner-suite/plan.md** — Phase-by-phase detailed plan

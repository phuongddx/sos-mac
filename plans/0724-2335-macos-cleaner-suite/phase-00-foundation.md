# Phase 0: Project & CleanCore Foundation

## Context
Greenfield repo. Nothing exists yet. This phase produces the Xcode project skeleton and the `CleanCore` Swift Package that every later module builds on. No user-facing feature ships in this phase.

## Requirements
- Xcode project targeting macOS 14+, Swift 6 language mode, strict concurrency checking on.
- A local Swift Package `CleanCore` added as a local package dependency (not a separate repo) — keeps it independently testable while staying in this monorepo.
- Three protocols that every module implements: `Scanner`, `Cleaner`, and a shared `ScanItem`/`ScanResult`/`Severity` model set.
- A `Shell` wrapper around `Process` with a timeout, used for the handful of CLI calls the suite needs (`purge`, `dscacheutil -flushcache`, etc.) — centralize this so every call site doesn't reinvent timeout/error handling.
- A `FileSystemScanner` wrapping BSD `fts()` via a thin C shim (Swift can't call `fts()` directly without a bridging shim) — this is the performance-critical primitive every scanner (Junk, Space Lens, Duplicate Finder) reuses.
- `FileManager.trashItem(at:)`-only deletion, enforced by a single `Cleaner.delete(_:)` default implementation in the protocol extension so no module can bypass it.

## Files to create
- `SOSMac.xcodeproj` (or `.xcworkspace` if SPM package is developed as a sibling checkout — prefer local package folder `Packages/CleanCore` referenced in-project for simplicity).
- `App/SOSMacApp.swift` — `@main` entry, empty `WindowGroup` placeholder.
- `Packages/CleanCore/Package.swift`
- `Packages/CleanCore/Sources/CleanCore/Models/ScanItem.swift`
- `Packages/CleanCore/Sources/CleanCore/Models/Severity.swift`
- `Packages/CleanCore/Sources/CleanCore/Protocols/Scanner.swift`
- `Packages/CleanCore/Sources/CleanCore/Protocols/Cleaner.swift`
- `Packages/CleanCore/Sources/CleanCore/FileSystem/FTSWrapper.swift` (+ C shim target `Packages/CleanCore/Sources/CFTS/`)
- `Packages/CleanCore/Sources/CleanCore/Shell.swift`
- `Packages/CleanCore/Sources/CleanCore/ByteFormatter.swift`
- `Packages/CleanCore/Tests/CleanCoreTests/FTSWrapperTests.swift`
- `Packages/CleanCore/Tests/CleanCoreTests/CleanerTrashTests.swift`

## Implementation steps
1. Create Xcode project (App target: macOS App, SwiftUI lifecycle, Swift 6, strict concurrency = complete).
2. Add local SPM package `CleanCore` with two targets: `CFTS` (C target wrapping `<fts.h>`) and `CleanCore` (Swift target depending on `CFTS`).
3. Define `ScanItem` (path, size, kind, lastAccessed) and `Severity` (safe/caution/risky) as `Sendable` structs/enums.
4. Define `protocol Scanner: Sendable { func scan() async throws -> [ScanItem] }` and `protocol Cleaner: Sendable { func clean(_ items: [ScanItem]) async throws -> CleanResult }` with a default `clean` implementation that calls `FileManager.trashItem(at:)` per item and aggregates failures instead of throwing on first error (partial success is expected — one locked file shouldn't abort the whole batch).
5. Implement `FTSWrapper.walk(root:) -> AsyncStream<ScanItem>` streaming results instead of buffering the whole tree in memory (important once Space Lens and full-disk scans reuse this).
6. Implement `Shell.run(_:args:timeout:) async throws -> String` using `Process` + `DispatchWorkItem` timeout, never `Process.launch()` unsupervised.
7. Wire the App target to depend on `CleanCore` and show a placeholder view proving the package compiles and links.

## Tests / validation
- `FTSWrapperTests`: create a temp directory tree with nested files/symlinks, assert `walk` returns every regular file and skips the symlink loop case.
- `CleanerTrashTests`: create a temp file, run default `clean`, assert the file no longer exists at its original path AND exists somewhere findable via `FileManager.url(for: .trashDirectory, ...)` — proves trash routing, not hard delete.
- App builds and launches to the placeholder window on the simulator/local Mac.

## Risks / rollback
- Low risk — no user data touched, no entitlements needed yet. Rollback is simply not merging.

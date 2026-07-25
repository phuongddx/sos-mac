# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

Regenerate the Xcode project after adding, removing, or renaming any file under `App/` or `MenuBarHelper/` — `project.yml` is the XcodeGen source of truth; never hand-edit `SOSMac.xcodeproj/project.pbxproj`:
```bash
xcodegen generate
```

Build the app:
```bash
xcodebuild build -scheme SOSMac -configuration Debug
```

Run the CleanCore engine test suite (Swift Testing — `@Test`/`#expect`, not XCTest):
```bash
cd Packages/CleanCore && swift test
```

Run a single test or suite:
```bash
cd Packages/CleanCore && swift test --filter DuplicateFinderTests
cd Packages/CleanCore && swift test --filter "DuplicateFinderTests/exactMatchesGroupCorrectly"
```

Open in Xcode (after `xcodegen generate`):
```bash
open SOSMac.xcodeproj
```

`libyara` (Protection module's pattern-matching engine) must be installed to build: `brew install yara`.

## Architecture

**Three targets, two local packages**: `SOSMac` (SwiftUI app) and `MenuBarHelper` (a separate embedded `.app`, no IPC — it reads system metrics independently) both depend on `CleanCore` (zero UI dependencies — the engine) and `TreemapKit` (pure-geometry treemap layout, zero dependencies). `project.yml` declares all of this; regenerate it after any source-file change under `App/`/`MenuBarHelper/`.

### The `Cleaner` protocol is the safety boundary — never bypass it
`Cleaner` is an *empty* marker protocol; `clean(_:)` is implemented as a plain extension method, not a protocol requirement. This is deliberate: a protocol requirement can be shadowed by a conformer's own declaration under witness-table dispatch, but a non-requirement extension method uses static dispatch that no conformer can override. Every delete in the app — Junk Cleaner, Uninstaller, Duplicate Finder, Cloud Cleanup, Protection quarantine — routes through this one `FileManager.trashItem(at:)` call. There is no hard-delete path anywhere in the codebase; don't add a `FileManager.removeItem` call outside this protocol, and don't give a conformer its own `clean` override.

### Every ViewModel is a `Phase` state machine
`@MainActor @Observable final class XViewModel` with an explicit `enum Phase` (e.g. `.idle → .scanning → .review/.results → .cleaning → .done/.summary`). The View switches on `phase` to pick which sub-view to render and calls ViewModel methods to drive transitions. Follow this pattern for any new feature rather than ad hoc `@State` flags — it's what every existing module does, and it keeps UI state as a single source of truth instead of several bools that can drift out of sync.

### CleanCore never imports UI frameworks; the App never touches Darwin/Process directly
`Packages/CleanCore/Sources/CleanCore/` exposes a `Scanner` (`func scan() async throws -> [ScanItem]`) and, per module, a `Cleaner` conformer — JunkScanner, Duplicates, SpaceLens, Uninstaller, Updater, Performance, Cloud, SmartCare, Protection — plus shared models (`ScanItem`, `Severity`, `CleanResult`). Views only ever call `Scanner.scan()` / `Cleaner.clean(_:)` and read the resulting models; they never call `sysctl`, `IOKit`, `Process`, or `FileManager.removeItem` directly. When adding a module: engine logic + its own test file goes in CleanCore as a `Scanner`/`Cleaner` conformer; only the SwiftUI View + Phase-enum ViewModel goes in `App/Features/<Module>/`.

### `App/DesignSystem/` is the shared UI layer — compose it, don't restyle ad hoc
Tokens (`Theme`: colors/spacing/radii/text sizes) and shared components (`BadgeView`, `.careCard()`, `ModuleCardView`, `ProgressBarView`, `EmptyStateView`, `StepRowView`, `StickyFooterView`, `SummaryCardView`, sidebar nav-row styles) were transcribed from the Open Design mockups (see below) and are reused across every feature view. Build new UI out of these instead of hand-rolling new card/badge/progress styling.

### Fail-closed, never guess
`SysctlReader` validates POD struct sizes before trusting them; `IOKitSensors` refuses to read raw SMC keys (no public API exists) and returns `nil` for GPU utilization rather than approximating it; `JunkRule` is an explicit allowlist, never a heuristic path match. If a value can't be obtained through a documented public API, surface `nil`/throw — don't guess.

### Recommended-keep protection in duplicate-style flows
Wherever a scanner recommends "keep" one item from a group (Duplicate Finder, Cloud Cleanup's per-provider duplicate groups), the recommendation is based on `lastModified` (mtime), never `lastAccessed` (atime — unreliable, bumped by any viewer opening the file). The recommended item's delete/trash control must stay `.disabled(isRecommendedKeep)` in the View.

## Design reference

The UI design lives in the Open Design MCP project **`macos-care-suite`** (the "Neutral Modern" system). Fetch a screen with `mcp__open-design__get_file(project: "macos-care-suite", path: "<screen>.html")` — e.g. `index.html` (dashboard), `junk-scanner.html`, `cloud-cleanup.html`, `performance.html` — and shared tokens from `styles.css`. `onboarding.html`/`paywall.html` intentionally use a separate `atelier.css` editorial system as a deliberate tonal contrast against the rest — don't unify those with the Neutral Modern screens. See `plans/0725-1315-apply-open-design-system/` for how the mockups were mapped onto `App/DesignSystem/` and each feature view.

## Docs map

- `docs/code-standards.md` — the architectural rules above, in full, with code examples
- `docs/system-architecture.md` — target/package dependency graph, data-flow diagrams, concurrency/isolation model
- `docs/codebase-summary.md` — file-by-file structural index
- `docs/project-roadmap.md` / `docs/project-overview-pdr.md` — phase status and product vision
- `plans/0724-2335-macos-cleaner-suite/plan.md` — phase-by-phase implementation plan

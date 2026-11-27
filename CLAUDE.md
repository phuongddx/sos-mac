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
`Cleaner` is an *empty* marker protocol; `clean(_:)` is implemented as a plain extension method, not a protocol requirement. This is deliberate: a protocol requirement can be shadowed by a conformer's own declaration under witness-table dispatch, but a non-requirement extension method uses static dispatch that no conformer can override. Every local delete in the app — Junk Cleaner, Duplicate Finder, Space Lens, Uninstaller, Smart Care, and Cloud Cleanup's local iCloud files — routes through this one `FileManager.trashItem(at:)` call (views and view models use `DefaultCleaner` or a `Scanner & Cleaner` conformer such as `AppUninstaller`/`ICloudLocalScanner`). There is no hard-delete path anywhere in the codebase; don't add a `FileManager.removeItem` call outside this protocol, and don't give a conformer its own `clean` override.

**Protection quarantine is the one documented exception.** It is not a `Cleaner` conformer and never touches the Trash: `QuarantineManager` makes a reversible, tracked `moveItem` into an app-managed quarantine folder, and the App persists a `QuarantineRecord` so a restore still works after relaunch (spec §5.10 — "quarantined, never deleted"). Nothing in that path deletes a file; don't route it through `Cleaner.clean` (the Trash is the wrong semantic: a restore needs the exact original path) and don't add a delete to it.

### Every ViewModel is a `Phase` state machine
`@MainActor @Observable final class XViewModel` with an explicit `enum Phase` (e.g. `.idle → .scanning → .review/.results → .cleaning → .done/.summary`). The View switches on `phase` to pick which sub-view to render and calls ViewModel methods to drive transitions. Follow this pattern for any new feature rather than ad hoc `@State` flags — it's what every existing module does, and it keeps UI state as a single source of truth instead of several bools that can drift out of sync.

### CleanCore never imports UI frameworks; the App never touches Darwin/Process directly
`Packages/CleanCore/Sources/CleanCore/` exposes a `Scanner` (`func scan() async throws -> [ScanItem]`) per scanning module — `JunkScanner`, `DuplicateFinder`, `DiskTreeScanner` (Space Lens), `AppUninstaller`, `ICloudLocalScanner` — plus engine types that are not `Scanner`s: `ProtectionScanner` (returns a `ProtectionScanOutcome` of findings and unreadable roots) with `QuarantineManager`, `SmartCareOrchestrator`, the Updater checkers (read-only: they never clean anything) and the Performance readers. The `Cleaner` conformers are only `AppUninstaller`, `ICloudLocalScanner` and the plain `DefaultCleaner` that every other deleting module uses; Protection quarantines instead of cleaning. Shared models: `ScanItem`, `Severity`, `CleanResult`. Views only ever call `Scanner.scan()` / `Cleaner.clean(_:)` and read the resulting models; they never call `sysctl`, `IOKit`, `Process`, or `FileManager.removeItem` directly. When adding a module: engine logic + its own test file goes in CleanCore (a `Scanner`, and a `Cleaner` only if it deletes via the Trash); only the SwiftUI View + Phase-enum ViewModel goes in `App/Features/<Module>/`.

### `App/DesignSystem/` is the shared UI layer — compose it, don't restyle ad hoc
`Theme` holds the Palette C ("Midnight Glass") tokens: 28 colours + derived hairlines (`Theme.Color`, `Theme.Derived`), `Gradient`, `Glow`, ten module hues with their glyph inks (`Theme.Hue`, `Theme.Hue.Ink`), `Spacing` (s1…s12), `Radius`, `Motion`, `Font`, and two-layer `Elevation` (via `.elevation(_:)`). The old pre-redesign names (`Theme.background`, `Theme.accent`, `Spacing.md`, `TextSize`, `ModuleHue`, `.careCard()`, `.auroraBloom()`, `HeroPanelView`, …) are gone — don't reintroduce them. Every scanning screen is a `ModuleScreen` (toolbar, `AuroraBackground` tinted with the module hue, per-state content, `DockView` with the round `PrimaryCTAView`, or `ReviewBarView` in `review`) fed by a `ModuleIdentity` (`ModuleIdentity(module: SidebarDestination)`). Per-module dock wording (Appendix A: "Review Items…" vs "Review" vs "Review…", "Scan Again" vs "Check Again" / "Measure Again" / "Back to Apps" / "Back to Map", "Open Trash" or none) lives in `ModuleIdentity.dock` (`DockCopy`) — change a label there, never with a per-screen string in `ModuleScreen`. Build state views from `StartView`, `ScanningView`, `DoneView`, `StatusStateView`, `ResultsHeaderView`/`ResultTileView`, `ReviewFrameView` (+ `ReviewGroupRow`, `ReviewItemRow`, `ReviewDetailView`), `BannerView`, `ConfirmSheet`/`ConfirmItemList`, `BadgeView`/`KeepBadge`, `SOSCheckbox`, `SOSButtonStyle`, `ProgressBarView`, `StepRowView`; tint a module's tile, eyebrow and orb with its `Theme.Hue` rather than `Theme.Color.primary`. Usage rules (spec §2.6): `primaryDeep` is a fill, never text or an icon on a card; neon is a verb, not a surface; `textTertiary` only for large, bold, disabled or placeholder text. See `docs/code-standards.md` (Rule 8) and `docs/codebase-summary.md` for the component table.

### Fail-closed, never guess
`SysctlReader` validates POD struct sizes before trusting them; `IOKitSensors` refuses to read raw SMC keys (no public API exists) and returns `nil` for GPU utilization rather than approximating it; `JunkRule` is an explicit allowlist, never a heuristic path match. If a value can't be obtained through a documented public API, surface `nil`/throw — don't guess.

### Recommended-keep protection in duplicate-style flows
Wherever a scanner recommends "keep" one item from a group (Duplicate Finder, Cloud Cleanup's per-provider duplicate groups), the recommendation is based on `lastModified` (mtime), never `lastAccessed` (atime — unreliable, bumped by any viewer opening the file). The recommended item's delete/trash control must stay `.disabled(isRecommendedKeep)` in the View.

## Design reference

The UI design source is the OpenDesign project **"SOS Mac Redesign v1 — Aurora Indigo"** (id `sos-mac-redesign-v1-aurora-indigo`), Palette C. It supersedes the earlier `macos-care-suite` / "Aurora Care" project. The in-repo copy of the prototype and its state board is `docs/redesign/prototype/` (`index.html?screen=…&state=…&palette=c`, `board.html`, `tokens.css`); the governing document is `docs/superpowers/specs/2026-11-26-ui-migration-palette-c-design.md` (token usage §2.6, lifecycle frame §4.1, dock §4.2, canonical copy Appendix A, acceptance checklist §11) and the plan is `docs/superpowers/plans/2026-11-26-ui-migration-palette-c.md`. Screen-state snapshots of the shipped app (fixture data only, dark and light) are in `docs/redesign/galleries/`, with `docs/redesign/galleries/README.md` indexing every screen and comparing it with `board.html`; regenerate them with `Scripts/ui-snapshots.sh`. Real screens intentionally omit mockup elements with no backing data (e.g. Dashboard has no health dial — there's no health-scoring module; several screens skip fabricated "last scan" stats; the prototype's `.tag-engine` annotations are not UI) — don't add fake numbers to close the gap; see each view's own header comment for its documented deviations. Settings has no screen yet (`SidebarDestination` has no `.settings` case) and Palette C has no Settings hue.

## Docs map

- `docs/code-standards.md` — the architectural rules above, in full, with code examples
- `docs/system-architecture.md` — target/package dependency graph, data-flow diagrams, concurrency/isolation model
- `docs/codebase-summary.md` — file-by-file structural index
- `docs/project-roadmap.md` / `docs/project-overview-pdr.md` — phase status and product vision
- `plans/0724-2335-macos-cleaner-suite/plan.md` — phase-by-phase implementation plan

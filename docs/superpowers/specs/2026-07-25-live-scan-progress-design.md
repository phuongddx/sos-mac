# Live Scan Progress — Design

Status: approved (pending final user sign-off on this document)
Date: 2026-07-25

## Problem

Only Space Lens shows any live progress during a scan (an item count, wired through
`DiskTreeScanner.buildTree(onProgress:)` — a one-off method that bypasses the shared
`Scanner` protocol entirely). Every other module (Junk Cleaner, Protection, Duplicate
Finder, Uninstaller, Cloud Cleanup, Smart Care, Updater) shows either a static
spinner+text or an ad-hoc per-row/per-provider `isLoading` flag. `CleanCore`'s `Scanner`
protocol (`func scan() async throws -> [ScanItem]`) has no progress support at all.

The Open Design mockups (macOS Care Suite / Aurora Care — `junk-scanner.html`,
`protection.html`, `smart-care.html`) already specify a richer visual language than
what's implemented anywhere: a determinate progress bar + percentage, a step-list
breakdown, a live ticker count, a live "currently scanning" path line, and an ETA
caption. This design closes the gap between what the mockups show and what the real
app can honestly back with data — without fabricating numbers the engine can't produce
(per the project's existing "fail closed, never guess" principle).

## Goals

- Give every module with a genuine scan/enumeration a live, honest progress signal.
- One shared SwiftUI component and one shared `ScanProgress` type, not N bespoke
  per-module progress UIs.
- Never show a percentage the engine can't actually back — count-only display when a
  total isn't knowable ahead of the walk.

## Non-goals

- No changes to deletion/cleanup behavior — this is scan-time visibility only.
- No new "Inspect All"-triggered auto-selection or auto-deletion — Uninstaller's new
  batch inspect only pre-computes sizes, it never selects or removes anything.
- No smoothed/EMA rate estimation for ETA — a simple linear extrapolation, gated on a
  minimum sample size, is the v1 bar.

## Section 1 — CleanCore engine layer

New shared type, `Packages/CleanCore/Sources/CleanCore/ScanProgress.swift`:

```swift
public struct ScanProgress: Sendable {
    public let itemsProcessed: Int
    public let totalItems: Int?   // nil = total not knowable ahead of the walk
    public let currentPath: String?
}
```

This is not a single protocol change — not every scan-like operation goes through the
`Scanner` protocol:

| Engine type | Conforms to `Scanner`? | Change |
|---|---|---|
| `JunkScanner` | yes | New `scan(onProgress:)` overload added to the `Scanner` protocol, with a default extension implementation (`{ try await scan() }`) so every existing conformer keeps compiling untouched. `JunkScanner` overrides it. Progress reported **per rule** (4 rules in `JunkRule.allowlist`) — `totalItems` = rule count, `currentPath` = the rule's `label`. This is real progress (rules completed / total rules), not a fabricated byte-level percentage the engine can't cheaply know without a redundant pre-pass. |
| `DiskTreeScanner` (Space Lens) | yes | Reshape the existing `buildTree(onProgress:)` callback to emit `ScanProgress` instead of a bare `Int`. `totalItems` stays `nil` — an arbitrary user-chosen directory's total size is genuinely unknowable upfront. |
| `AppUninstaller` (single-app scan) | yes | Not changed by the protocol addition — its existing per-row spinner is untouched. (Its *new* batch use, "Inspect All", is a Section 3 ViewModel-level concern, not a CleanCore change.) |
| `ProtectionScanner` | no (bespoke `scan() -> [ThreatFinding]`, not a `Scanner` conformer) | Add `onProgress: (@Sendable (ScanProgress) -> Void)? = nil` directly as a parameter on its existing `scan()` — no protocol involved. Progress **per file** across the 6 fixed `ProtectionLocation.allowlist` entries. `totalItems`: pre-enumerate file counts across those locations (cheap — same fixed 6 paths, a `contentsOfDirectory`-level count, not a second deep walk) before the real hash/YARA pass starts. `currentPath` = file currently being checked. |
| `DuplicateFinder` | yes, but the real work is in `findExactDuplicateGroups()` / `findSimilarImageGroups()`, not `scan()` | Add `onProgress:` directly to both methods. Each is naturally two phases: **listing** (walking `rootPath` — total unknown, count-only) then **hashing** (total = however many files listing found, known before hashing starts — real percentage + current filename). Maps onto the 2-row step-list the real view already has. |
| `CloudProvider.listFiles(cursor:)` | separate protocol, not `Scanner` | Add `onProgress:` to `listFiles`. Pagination gives no total (no `totalCount` field on `CloudFilePage`), so this is count-only (files listed so far), same shape as Space Lens. |

**Explicitly not touched by a CleanCore change:** Updater's per-app appcast check and the
new Uninstaller "Inspect All" (Section 3) — their total is already known upfront in the
ViewModel (count of tracked/installed apps) and the per-item work is already a
sequential awaited loop the ViewModel controls, so the ViewModel builds `ScanProgress`
itself with no new engine hook needed.

**Performance guardrail:** the new "pre-count total" passes (Junk Cleaner's rule count,
Protection's file count) must use a cheap `contentsOfDirectory`-style count, never a
second full `FTSWrapper.walk` — that would double the actual scan time.

## Section 2 — Shared UI layer (`App/DesignSystem/`)

**`ScanProgressTracker`** — plain `@Observable` class, not CleanCore (the engine has no
business estimating wall-clock ETAs):

```swift
@Observable
final class ScanProgressTracker {
    private(set) var progress: ScanProgress?
    private var startedAt: Date?

    func start() { startedAt = Date(); progress = nil }
    func record(_ progress: ScanProgress) { self.progress = progress }

    /// nil until there's enough signal to avoid a wild first-tick estimate.
    var estimatedTimeRemaining: TimeInterval? {
        guard let progress, let total = progress.totalItems, let startedAt,
              progress.itemsProcessed >= 20 else { return nil }
        let elapsed = Date().timeIntervalSince(startedAt)
        let rate = Double(progress.itemsProcessed) / elapsed
        return Double(total - progress.itemsProcessed) / rate
    }
}
```

Each feature ViewModel owns one instance: `.start()` when scanning begins, `.record(_:)`
inside the `onProgress` closure (hopped to `@MainActor`, same pattern
`SpaceLensViewModel` already uses). Linear extrapolation, gated on ≥20 items processed —
no smoothing/EMA; can be added later if the raw estimate proves too jumpy in practice.

**`ScanProgressPanel`** — new shared view composing the *existing* `ProgressBarView` and
`StepRowView`, not replacing them:

```swift
struct ScanProgressPanel: View {
    let progress: ScanProgress?
    var ticker: String?                    // e.g. "128,402 files scanned" (Protection only)
    var etaText: String?                   // e.g. "~5 minutes remaining"
    var showCurrentPath = false            // Protection: yes; Junk/Duplicates/SpaceLens: no
    var steps: [StepRowView.Model] = []    // empty = no step list (Protection, Space Lens, Cloud)
}
```

- `progress?.totalItems != nil` → `ProgressBarView` + "N%" label (mirrors the mockups'
  `.progress-row`).
- `nil` → the existing count-only text style Space Lens already uses ("Scanned N
  items…"), never a fake bar.
- `steps` (non-empty) → existing `StepRowView` rows below the bar, unchanged.
- `showCurrentPath` → new: a small monospaced, muted, truncated line (matches the
  mockups' `.pr-scanning-path`; doesn't exist anywhere in the app today).
- `ticker` / `etaText` render only when supplied.

This one view replaces the hand-rolled spinner+text blocks in Junk Cleaner, Protection,
Space Lens, Duplicate Finder, and Cloud Cleanup's scanning states, and slots into Smart
Care's aggregate card and the new Uninstaller/Updater aggregate bars.

## Section 3 — Per-module wiring

| Module | Phase enum change | `ScanProgressPanel` config | Notes |
|---|---|---|---|
| **Junk Cleaner** | none (`.scanning` exists) | `steps`: one row per `JunkRule` (4 rows, done/active/pending, rule labels) + bar (rules completed/total) | Closest 1:1 mockup port. Adds a **Cancel button** (currently missing) — matches Duplicates/Space Lens precedent. |
| **Protection** | none | `ticker` (files scanned so far) + bar (%, from pre-enumerated total) + `etaText` + `showCurrentPath: true` | Closest 1:1 mockup port, most feature-complete. |
| **Space Lens** | none | count-only (no bar), no steps, no path | Re-skin only: swap hand-rolled spinner+text for `ScanProgressPanel` with `totalItems == nil`. Behavior unchanged. |
| **Duplicate Finder** | none | `steps`: 2 rows ("Scanning files…" count-only meta / "Hashing files…" real % + current filename once hashing starts) | Bar only appears once the hashing phase begins (`totalItems` known); listing phase shows step-list only. |
| **Cloud Cleanup** | new: promote each provider's `isLoading: Bool` to carry an accompanying `ScanProgress?` | count-only (files listed so far), no bar, no steps | Smallest structural change of the set. |
| **Smart Care** | none | Aggregate card: existing reclaimed-so-far number + bar computed as Σ(itemsProcessed)/Σ(totalItems) across in-flight sub-scans that report a total, else falls back to today's per-module done/pending step list | Only Junk Cleaner + Duplicates feed real numbers initially; other sub-scans stay pending/done markers as today — incremental, no regression. |
| **Updater** | new: aggregate phase (e.g. `.checkingAll`) around the existing `checkAll()` loop | bar ("X of N apps checked", total = tracked-app count) + `showCurrentPath` (current app name); existing per-row spinners unchanged | No CleanCore change — ViewModel already loops sequentially; wrap it with `tracker.record(ScanProgress(itemsProcessed: i, totalItems: apps.count, currentPath: app.name))` per iteration. |
| **Uninstaller** | new: `.inspectingAll` phase + a new "Inspect All" action | bar ("X of N apps inspected", total known upfront) + `showCurrentPath` (current app name) | New behavior: runs the existing `AppUninstaller(...).scan()` for every row sequentially, caching each app's total reclaimable size onto a new `AppRow.inspectedSize: Int64?` so the browsing list can show real per-row/aggregate reclaimable-size numbers before manual inspection. Purely additive — doesn't touch the existing per-row on-demand `inspect(_:)` flow or deletion. |

## Section 4 — Testing & cross-cutting concerns

**CleanCore unit tests** (Swift Testing, `swift test`) — one test per converted scanner
verifying the progress *contract*, not just the final result:
- `JunkScannerTests`: `onProgress` fires once per rule, in order, `totalItems ==
  rules.count`, `currentPath == rule.label`.
- `ProtectionScannerTests`: pre-enumerated `totalItems` matches actual files scanned in
  a fixture directory.
- `DuplicateFinderTests`: `totalItems == nil` during listing, real `totalItems` once
  hashing starts (both `findExactDuplicateGroups` and `findSimilarImageGroups`).
- `DiskTreeScannerTests`: reshaped to assert on `ScanProgress` instead of a bare `Int`.
- Cloud provider fakes: progress fires after each page with a running count.

**Concurrency:** every `onProgress` closure is `@Sendable`, invoked from the scanner's
background `Task`. Every call site hops to `@MainActor` before touching a
ViewModel/`ScanProgressTracker` — the exact pattern `SpaceLensViewModel` already uses
(`Task { @MainActor in self?.scannedItemCount = count }`), not a new pattern.

**Cancellation:** progress callbacks must stop firing the instant a scan is cancelled.
Every converted scanner already has (or gets) a `Task.isCancelled` /
`Task.checkCancellation()` check before each item — the same place the progress
callback fires, so cancellation silences it for free.

**Known pre-existing gap (not introduced by this design):** App-layer ViewModels have
no automated test target today (only CleanCore's engine layer runs under `swift test`)
— so `ScanProgressTracker`, `ScanProgressPanel`, and the per-module wiring are verified
by build + manual run, same as `SpaceLensViewModel` is today.

## Open questions

None outstanding — all scope/API/ETA decisions were made during brainstorming (see
question log in the conversation this spec was written from).

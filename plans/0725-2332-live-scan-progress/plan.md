# Live Scan Progress — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every CleanCore scan a live, honest progress signal, and a shared SwiftUI component that renders it consistently across all 8 scan-driving modules.

**Architecture:** A new `ScanProgress` value type in CleanCore, threaded through each engine type's existing scan entry point via an additive `onProgress` parameter (protocol default where `Scanner`-conforming, a matching parameter on bespoke methods otherwise). A shared `ScanProgressTracker` (ETA/rate math) and `ScanProgressPanel` (SwiftUI) in `App/DesignSystem/` consume it. Per-module tasks wire the two together — no per-module bespoke progress UI.

**Tech Stack:** Swift 6 / Swift Testing (CleanCore engine), SwiftUI + `@Observable` (App layer), XcodeGen (`project.yml`) for target sources.

**Spec:** `docs/superpowers/specs/2026-07-25-live-scan-progress-design.md` — read this first for the full rationale; this plan only restates what's needed to execute.

## Global Constraints

- Every new/changed CleanCore public API must compile under `SWIFT_STRICT_CONCURRENCY: complete` (project.yml) — all progress closures are `@Sendable`.
- Never add a second full-content read/hash pass just to compute a total — counting entries (no file bytes read) is fine; re-hashing is not.
- Every `onProgress` callback must go silent after `Task.isCancelled`/`Task.checkCancellation()` fires — no stale progress after Cancel.
- No changes to deletion/cleanup behavior anywhere in this plan — scan-time visibility only.
- Run `cd Packages/CleanCore && swift test` after every CleanCore task; run `xcodebuild build -scheme SOSMac -configuration Debug` after every App-layer task. Both must stay green — this repo has zero tolerance for a broken build between tasks.
- Regenerate the Xcode project (`xcodegen generate` from repo root) any time a task adds/removes/renames a file under `App/` — required before that task's build-verify step.
- App-layer changes have no unit test target (only `SOSMacUITests`, a screenshot-only UI test target) — this is a pre-existing gap, not something to fix as a side effect here. App-layer tasks are verified by build + a manual run-through, stated explicitly per task.

---

## Phases

1. **[CleanCore Foundation](phase-01-cleancore-foundation.md)** — `ScanProgress` type + `Scanner` protocol extension, and progress wired into `JunkScanner`, `DiskTreeScanner`, `ProtectionScanner`, `DuplicateFinder`, `SmartCareOrchestrator`. (Tasks 1–6)
2. **[Shared DesignSystem UI](phase-02-design-system.md)** — `ScanProgressTracker` (ETA/rate) and `ScanProgressPanel` (SwiftUI), composing the existing `ProgressBarView`/`StepRowView`. (Tasks 7–8)
3. **[Junk Cleaner + Protection](phase-03-junk-cleaner-and-protection.md)** — the two closest 1:1 mockup ports. (Tasks 9–10)
4. **[Space Lens + Duplicate Finder](phase-04-space-lens-and-duplicate-finder.md)** — re-skin Space Lens onto the shared component; two-phase progress for Duplicate Finder. (Tasks 11–12)
5. **[Cloud Cleanup + Smart Care](phase-05-cloud-and-smart-care.md)** — ViewModel-level pagination progress; aggregate cross-module progress. (Tasks 13–14)
6. **[Updater + Uninstaller](phase-06-updater-and-uninstaller.md)** — aggregate "X of N" progress around existing/new batch loops, including the new Uninstaller "Inspect All" feature. (Tasks 15–16)

Phases 3–6 each depend only on Phases 1–2, not on each other — they can be executed in any order, or in parallel by different reviewers, once Phases 1–2 are merged.

## Status

- [ ] Phase 1 — CleanCore Foundation
- [ ] Phase 2 — Shared DesignSystem UI
- [ ] Phase 3 — Junk Cleaner + Protection
- [ ] Phase 4 — Space Lens + Duplicate Finder
- [ ] Phase 5 — Cloud Cleanup + Smart Care
- [ ] Phase 6 — Updater + Uninstaller

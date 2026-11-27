# Release follow-ups A–F — design note

Date: 2026-11-27 · Branch: fix/ui-palette-c-release-followups → feat/ui-palette-c (PR #17)

Context: the PR #17 gate (build Debug + both test suites) passed at `2a4c210`, but a
Release configuration build failed twice — a `#if DEBUG` scoping bug the Debug gate
cannot see (A) and a universal-slice link failure against Homebrew's arm64-only libyara
(B). C–E are the follow-ups PR 16's report left open; F closes a process gap: three
screens merged straight into the integration branch without the per-PR reviewer every
other screen got.

## A — Release: `BaselineBox` invisible outside DEBUG

- **Cause.** `Seams.live()` — the adapter every configuration builds and Release *only*
  builds — constructs `BaselineBox()` (PerformanceViewModel.swift:157), but the class
  declaration (line ~243) sits inside the `#if DEBUG` block next to `fixture()` and
  `FixtureLoginState`. Debug compiles the whole block; Release drops the class while the
  call site remains → `cannot find 'BaselineBox' in scope`.
- **Chosen fix.** Move `BaselineBox` (with its comment) out of the `#if DEBUG` block. It
  is a `@MainActor private final class` the *live* adapter needs; DEBUG-only types are
  `fixture()`/`FixtureLoginState`, which stay where they are.
- **Rejected.** (1) Guarding the call site with `#if DEBUG` — `live()` is precisely the
  Release code path. (2) Duplicating the class inside and outside the block — two
  declarations that drift. (3) Making `live()` itself debug-only — Performance would have
  no system adapter in Release.
- **Regression guard.** The merge gate now builds Release as a required step
  (`Scripts/verify-gate.sh`), so configuration-scope mistakes fail the gate, not Phương.

## B — Release universal link: libyara is arm64-only

- **Cause.** A command-line `xcodebuild -configuration Release` defaults to
  `ARCHS_STANDARD` (arm64 + x86_64). `CYara` links `-lyara` from `/opt/homebrew`, and
  Homebrew's yara bottle is arm64-only (`lipo`: "Non-fat file … architecture: arm64"),
  so the x86_64 slice of `PrivilegedHelper` fails with `_yr_*` undefined. The same
  `Package.swift` yara flags exist on `main` (`0587765`): the link constraint is
  pre-existing, not introduced by the migration — the migration is just the first thing
  to make a Release build part of the gate.
- **Chosen fix.** Project-level `EXCLUDED_ARCHS: x86_64` in `project.yml` (applies to
  every target, every configuration, including SPM package builds driven by the
  project). Rationale: the dev/test machine is Apple Silicon; nobody runs this app on
  Intel; an x86_64 slice would need a universal libyara we would have to build and
  vendor ourselves; Rosetta would need an x86_64 yara regardless.
- **Rejected.** (1) Build a universal libyara and vendor it — adds a binary to a public
  repo (size, provenance, upgrade burden) to support hardware nobody uses. (2) Fix per
  invocation with `-destination`/`ONLY_ACTIVE_ARCH` — repairs one command and leaves the
  default `xcodebuild -configuration Release` broken, which is exactly the failure mode
  that surfaced this. (3) Drop the yara dependency — Protection's engine requires it;
  changing the engine is out of scope for a UI-migration PR.
- **Known, not fixed here (pre-existing on main).** The linker prefers `libyara.dylib`,
  so builds dynamically link Homebrew's `libyara.10.dylib`; the app runs wherever
  Homebrew yara is installed (true for this machine). A self-contained or Intel build
  needs a vendored static universal libyara — follow-up work, tracked in the PR notes.

## C — `isAppleSilicon()` returns `Bool?`

- **Cause.** `SysctlReader.isAppleSilicon()` folded "the sysctl read failed" (`nil`)
  into `false`, so the app cannot distinguish "read succeeded, Intel" from "could not
  read" — a guess, which the fail-closed rule forbids.
- **Chosen fix.** Return `Bool?` (`nil` = unreadable). `IOKitSensors.isAppleSilicon()`
  forwards the optionality. `Performance`'s `Sample.isAppleSilicon` was already `Bool?`
  and the metric grid already renders `nil` as "—", so the only semantic change is: an
  unreadable chip family shows "—" instead of a guessed "Intel".
- **Rejected.** (1) Keep `Bool` and treat `nil` as `false` — the guess being removed.
  (2) Expose `errno` from `read<T>` to split ENOENT from other failures — wrapper surgery
  and more API surface for one call site; absence-of-key still cannot prove the chip
  family through this wrapper.

## D — Smart Care scan generation guard

- **Cause.** The scan's progress/start callbacks hop to `@MainActor` through
  unstructured `Task { @MainActor … }` closures. Those tasks are *not* children of the
  scan task, so cancelling (Stop, or a re-scan) does not cancel them: hops enqueued by
  an old scan can still land after `resetScanState()`/a new scan and clobber the reset
  state or the new scan's progress. The codebase fixed this exact bug class once before
  (`ScanProgressTracker`, commit `3db527f`); the rewritten Smart Care reintroduced it.
- **Chosen fix.** A `scanGeneration` counter bumped by both `startScan()` and
  `cancelScan()`. `performScan(generation:)` and every hop closure capture the token and
  drop the write when `scanGeneration != generation`; the post-`await` guard becomes
  `guard !Task.isCancelled, generation == scanGeneration`.
- **Rejected.** (1) Restructure progress as structured concurrency/AsyncStream — an
  orchestrator-contract rewrite for a one-line race. (2) "Just cancel the tasks" — no
  task tree exists to cancel unstructured hops. (3) Have hops check `phase == .scanning`
  — a new scan is also `.scanning`, so stale hops would still clobber the *new* scan.

## E — Dashboard: two small fixes from the PR 16 report

- **E1 (capture once per page-open).** Cause: `DashboardView.init` called
  `DashboardSnapshot.capture()` and `VolumeStorageInfo.current()`; SwiftUI runs that
  initializer on every re-render while the page is visible, re-reading
  sysctl/IOKit/volume data that `@State` then ignores (only the first value is kept).
  Chosen: `@State …?` optionals plus one capture in `.onAppear` guarded by nil — the
  sidebar's `switch` recreates the view (fresh identity, fresh `@State`) each time the
  page is opened, so "Read when this page opened" semantics are unchanged while
  re-renders now read nothing; UITest fixtures swap in at capture time. Rejected:
  capturing in `body` (worse), hoisting capture into `ModuleStore` (turns the caption
  into "read when the app launched"), `.task` (async machinery for synchronous reads).
- **E2 (`@MainActor` closure types).** Cause: `DashboardModuleSection.open` and
  `DashboardModuleCard.action` were non-isolated closure types in an otherwise
  `@MainActor`-inferred view layer — compiles only thanks to the SDK's View-wide
  inference, and the isolation should live on the types. Chosen: annotate both
  `@MainActor`. Rejected: leaving as-is (the closures may touch UI state; if inference
  details change they become silently callable off-main), `@Sendable` (the opposite
  direction).

## F — independent review of the directly-merged screens

- **Cause.** PR 8 (Space Lens), PR 10 (Updater) and PR 13 (Protection) merged into the
  integration branch without the per-PR read-only reviewer every other screen had.
- **Chosen.** Fan out three independent read-only reviewers (Worker-S1 / Worker-S2 /
  Worker-G1, one fresh thread each), each comparing the merge diff (`f0e98db`, `8b70606`,
  `1f9715b`) plus the integrated tip against the spec (§5.5 / §5.8 / §5.10 and shared
  §4.1, §4.2, §2.6, Appendix A, CLAUDE.md safety rules); their findings go into PR #17's
  description.
- **Rejected.** Self-review by the implementing agent (the bias the per-PR reviewers
  existed to break); skipping it (the spec's acceptance checklist wants review evidence
  for every screen).

## Gate change

New `Scripts/verify-gate.sh`: `xcodegen generate` → Debug build → **Release build** →
`cd Packages/CleanCore && swift test` → `xcodebuild test -only-testing:SOSMacTests`.
Release is now a hard gate step so class-A configuration bugs cannot reach a merge.

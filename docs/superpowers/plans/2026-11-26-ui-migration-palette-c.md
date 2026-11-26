# SOS Mac UI Migration (Palette C "Midnight Glass") — Implementation Plan

> **For agentic workers:** implement this plan PR by PR with the superpowers executing-plans workflow (one branch per PR, task-by-task). Steps use checkbox (`- [ ]`) syntax for tracking. Read the spec first: [`docs/superpowers/specs/2026-11-26-ui-migration-palette-c-design.md`](../specs/2026-11-26-ui-migration-palette-c-design.md).

Status: **Draft for review. Do not start until Phương approves the spec** and the decisions in §6 below are settled or their defaults accepted.
Date: 2026-11-26
Code baseline: `main` @ `0587765`.

> **Tóm tắt (VN)**
> - 18 PR nhỏ (PR 0 → PR 16) + 1 PR engine tùy chọn (PR E1). Mỗi PR tự đứng được: build pass, test pass, app dùng được.
> - Thứ tự: **nền tảng** PR 0 (dụng cụ test) ∥ PR 1 (token) → PR 2 (shell) → PR 3 (giữ kết quả) → PR 4a/4b (component) → PR 5 (Junk, màn tham chiếu). Sau PR 5, **10 PR màn hình làm song song được** vì mỗi PR chỉ đụng thư mục `App/Features/<Module>/` của mình. PR 16 dọn dẹp đi cuối.
> - Mỗi PR ghi: file bị đụng, cách verify (build, `swift test`, unit test view model, chụp ảnh so với prototype), rủi ro.
> - Verify bằng ảnh không chiếm màn hình: script chụp riêng cửa sổ app chạy ở nền (PR 0), dữ liệu mẫu chỉ có trong bản Debug.

---

## 1. Goal, architecture, tech stack

**Goal.** Move all 10 screens and the menu-bar helper to the redesigned UI with Palette C (dark + light), shipping the safety and data fixes the design depends on, while `main` stays releasable after every PR.

**Architecture.**

- **Tokens first.** `Theme` becomes the Designer's token set with Palette C values. Old token names survive one migration long as deprecated shims that point at the new tokens, and are deleted in PR 16.
- **One shared frame.** Every scanning module maps its own `Phase` enum to `LifecycleState`; one frame view draws toolbar, canvas and dock for all of them.
- **Session store.** An app-level `ModuleStore` owns every view model, so results survive navigation (spec §6.6).
- **Safety boundary untouched.** No change to `Cleaner`, the helper protocol or any scanner. The only CleanCore change in the whole plan is the optional memory definition (PR E1).
- **Screens last, in parallel.** After the reference screen (Junk & Cache) merges, each screen is an independent PR in its own folder.

**Tech stack.** Swift 6 (strict concurrency), SwiftUI, Observation, AppKit (`NSColor`, `NSWorkspace`, `NSRunningApplication`), Swift Testing, XcodeGen (`project.yml`), CleanCore, TreemapKit. macOS 14+; Liquid Glass APIs only behind `#available(macOS 26, *)`.

## 2. Global constraints (apply to every PR)

**Safety and data**

1. Every local removal goes through `Cleaner.clean(_:)`. No `FileManager.removeItem`, no second trash call site. Helper items keep using `privilegedHelperClient.trashSystemPath`.
2. No screen merges without a confirmation on every removal path, and Cancel as the default button.
3. No number on screen that is not in spec §6.4. No placeholder text.
4. The recommended keep copy of a duplicate group is never selectable.
5. Pre-selection is not widened. If a PR needs to, it stops and asks.

**Code**

6. Every view model is `@MainActor @Observable` with an explicit `Phase` enum. Booleans that describe *which state the screen is in* are not allowed; per-row flags (`isChecking`, `inspectError`) are.
7. UI is composed from `App/DesignSystem`. No colours, radii or font sizes outside `Theme`.
8. `CleanCore` never imports a UI framework and is not modified, except PR E1.
9. After adding, removing or moving any file under `App/`, `MenuBarHelper/`, `SOSMacTests/` or `SOSMacUITests/`, run `xcodegen generate` and commit the regenerated project. Never edit `project.pbxproj` by hand.
10. Test-only hooks live in `#if DEBUG` and read only `SOSMAC_UITEST_*` launch variables. A normal launch must behave exactly as before.

**Process**

11. One branch per PR, named `feat/ui-migration-<NN>-<slug>`, off the PR it depends on. Conventional Commits (`feat(junk): …`, `feat(design-system): …`, `docs: …`). Never force-push `main`.
12. A PR does not edit files outside its write set (listed per PR). A shared-component fix needed by two screens becomes its own small `feat(design-system)` PR.
13. Every PR description states: user-facing change, safety impact, the prototype states it implements, tests run, and a link to the snapshot contact sheet.
14. The implementation starts only after Phương approves the spec (standing instruction: no redesign is implemented before approval).

**Commands**

```bash
xcodegen generate                                             # after file changes under App/, MenuBarHelper/, SOSMacTests/, SOSMacUITests/
xcodebuild build -scheme SOSMac -configuration Debug
cd Packages/CleanCore && swift test
xcodebuild test -scheme SOSMac -destination 'platform=macOS' -only-testing:SOSMacTests
Scripts/ui-snapshots.sh -p <pr-name> -s <screen>=<state>[,<screen>=<state>…]
```

## 3. Phases at a glance

| PR | Title | Depends on | Parallel group | Size |
|---|---|---|---|---|
| **0** | Test harness: unit-test target, fixture hooks, window snapshot script | — | A (with 1) | M |
| **1** | Palette C tokens | — | A | M |
| **E1** | CleanCore: memory "in use" (OD-11) | 0 | any time before 12 | S |
| **2** | Shell: window, sidebar, toolbar | 1 | — | M |
| **3** | Session store: results survive navigation | 2 | — | M |
| **4a** | Components: primitives | 1 | — | M |
| **4b** | Components: lifecycle frame, review frame, confirmation | 4a | — | L |
| **5** | Junk & Cache — the reference screen | 3, 4b | — | L |
| **6** | Duplicate Finder | 5 | B | M |
| **7** | Smart Care | 5 | B | M |
| **8** | Space Lens | 5 | B | L |
| **9** | Uninstaller | 5 | B | M |
| **10** | Updater | 5 | B | S–M |
| **11** | Cloud Cleanup | 5 | B | M |
| **12** | Performance | 5 (E1 if OD-11 = fix) | B | M |
| **13** | Protection | 5 | B | M |
| **14** | Dashboard | 3, 4a | B | S–M |
| **15** | Menu bar helper | 1 | B (earliest: after 1) | S–M |
| **16** | Cleanup: legacy components, shims, docs | 6–15 | — | M |

**Dependency graph**

```
Foundation   PR 0 (independent)                       PR 1 ─► PR 2 ─► PR 3 ───────────┐
             PR 1 ─► PR 4a ─► PR 4b ───────────────────────────────────────────────┴─► PR 5
Screens      PR 5 ─► { PR 6 · PR 7 · PR 8 · PR 9 · PR 10 · PR 11 · PR 13 }          (all parallel)
             PR 5 + PR E1 ─► PR 12        PR 3 + PR 4a ─► PR 14 (E1 too if OD-11 = fix)      PR 1 ─► PR 15
Engine       PR 0 ─► PR E1 (only if OD-11 = fix; must land before PR 12)
Last         { PR 6 … PR 15 } ─► PR 16
```

**What can run in parallel**

- PR 0 and PR 1 (disjoint: tests/scripts vs `Theme.swift`).
- PR E1 any time after PR 0; it must land before PR 12 uses the new property.
- PR 15 any time after PR 1.
- PR 6 – PR 14 all at once after PR 5, because each stays inside `App/Features/<Module>/` plus its own test and fixture files. They must not edit `App/SOSMacApp.swift`, `App/State/`, or shared `App/DesignSystem/` files.
- PR 4a can start while PR 2 and PR 3 are in review (it only needs PR 1).

## 4. PR details

### PR 0 — Test harness

**Goal.** Give every later PR a way to prove itself without touching the user's files or screen: a unit-test target for view models, Debug-only fixture hooks that put a screen into a chosen state, and a script that captures the app window in the background.

**Depends on:** nothing. **Write set:** `project.yml`, `.gitignore`, `SOSMacTests/**` (new), `SOSMacUITests/**`, `App/Support/UITestHooks.swift` (new), `App/Support/UITestFixtures.swift` (new), `Scripts/ui-snapshots.sh` (new), `Scripts/window-id.swift` (new), `App/SOSMacApp.swift` (only the hook block).

- [ ] **T0.1 Unit-test target.** In `project.yml` add `SOSMacTests` (`bundle.unit-test`, host `SOSMac`, `SWIFT_STRICT_CONCURRENCY: complete`) and list it under `schemes.SOSMac.test.targets`. Create `SOSMacTests/SidebarDestinationTests.swift` with one Swift Testing case (`@testable import SOSMac`; the enum has 10 cases) to prove the target works. `xcodegen generate`, commit the project.
- [ ] **T0.2 Hook reader.** Add `App/Support/UITestHooks.swift` (`#if DEBUG`): a `Sendable` struct `UITestHooks` read once at launch from `ProcessInfo.processInfo.environment` — `screen: String?`, `state: String?`, `appearance: "light"/"dark"?`, `fixtures: Bool`, `windowSize: CGSize?` (`"1200x760"`), `reduceTransparency: Bool`, `outputDirectory: String?`. Move the existing `SOSMAC_UITEST_APPEARANCE` reading out of `RootView` into it. All variables are prefixed `SOSMAC_UITEST_`; unset means normal behaviour.
- [ ] **T0.3 Fixture data.** Add `App/Support/UITestFixtures.swift` (`#if DEBUG`): made-up sample data modelled on the prototype's `data.js` (the names there are fictional) — junk items for the 4 rules, 6 duplicate sets, 2 similar sets, 10 apps, 8 updater rows, a small Space Lens tree, findings and quarantine records, system metrics. No real paths from any machine.
- [ ] **T0.4 Fixture loading (mechanism only).** Define the convention each screen PR will implement: `func loadFixture(_ state: LifecycleState)` on the view model, available under `#if DEBUG`. PR 0 wires `RootView` to select the initial screen from `hooks.screen` and to apply `appearance`, `windowSize` and `.environment(\.accessibilityReduceTransparency, hooks.reduceTransparency)`.
- [ ] **T0.5 Snapshot script.** `Scripts/ui-snapshots.sh`: build Debug into a throwaway derived-data folder; for each `screen=state` × appearance: launch the built app with `open -n -g --env SOSMAC_UITEST_…`, find the window id with `Scripts/window-id.swift` (`CGWindowListCopyWindowInfo`, owner bundle id `com.nextlabs.sosmac`), capture with `screencapture -l<wid> -o -x`, quit that instance (`osascript`-free: `kill` on the pid the script started). Output: `artifacts/ui-snapshots/<name>/<appearance>-<screen>-<state>.png` plus a contact sheet (`magick montage`). Add `artifacts/` to `.gitignore`.
- [ ] **T0.6 UI tests stop capturing the display.** Replace `SOSMacUITests/AuroraCareScreenshotTests.swift` with `SOSMacUITests/RedesignSmokeTests.swift`: launch, assert each `sidebar-nav-<label>` exists and opens its screen (state identifier on the screen root, e.g. `junk.state.idle`), attach an **element** screenshot of the window (never `XCUIScreen.main`).
- [ ] **T0.7 Document the harness** in `docs/codebase-summary.md` (two paragraphs: hooks, script).

**Verify.** Build; `xcodebuild test … -only-testing:SOSMacTests` passes; `Scripts/ui-snapshots.sh -s dashboard=default` produces `dark-dashboard-default.png` and `light-dashboard-default.png` at 1200 × 760 with the app never brought to the front; a normal launch (no variables) is byte-for-byte the old behaviour.

**Risks.** (a) `screencapture -l` needs Screen Recording permission for the process that runs the script. (b) State restoration can resize the window — `windowSize` is forced by the hook, not by `defaultSize`. (c) XCUITest activates the app: run it only with Phương's go-ahead (OD-17).

**Standalone check.** No user-visible change; `git diff` outside tests, scripts and `#if DEBUG` blocks is empty apart from moving the appearance hook.

### PR 1 — Palette C tokens

**Goal.** `Theme` carries the Designer's token set with Palette C values; the old layout recolours itself through shims.

**Depends on:** nothing (PR 0 helps verification). **Write set:** `App/DesignSystem/Theme.swift`, `App/DesignSystem/AuroraSurface.swift` (new), `SOSMacTests/ThemeContrastTests.swift` (new).

- [ ] **T1.1 Contrast tests first.** `ThemeContrastTests` resolves each `Theme.Color` in light and dark (via `NSAppearance.performAsCurrentDrawingAppearance`) and asserts the rules as numbers: `textPrimary` ≥ 7:1 and `textSecondary` ≥ 4.5:1 on `bgBase`, `bgElevated`, `card`, `glass`, `sidebar` and on `rowSelected` composited over `card` (5.8:1 today, spec T3); `primaryBright` ≥ 4.5:1 on base and card; `success`, `warning`, `danger` ≥ 4.5:1 on card; `onPrimary` ≥ 4.5:1 on `primaryDeep` and `dangerFill`; module-hue ink ≥ 3:1 on its tile. They fail on the old tokens (no such names) and pass after T1.2.
- [ ] **T1.2 Replace `Theme.swift`** with the Designer's structure: `Color.adaptive(light:dark:)` helper, `enum Color` (28 tokens, spec Appendix C.1), `Hue` (9 + `threat`, with `ink`), `Derived`, `Gradient`, `Spacing` (s1…s12), `Radius` (xs 5 … pill), `Motion`, `Font`. Keep `Color(hex:)`.
- [ ] **T1.3 Legacy shims (deprecated).** `background → .bgBase`, `surface → .card`, `foreground → .textPrimary`, `muted → .textSecondary`, `border → .hairline`, `accent → .primaryDeep`, `accent2 → .neonCyan`, `accentGradient → .Gradient.soft`, `success / warn / danger` → the new tokens, `ModuleHue.*` and `hue(for:)` → `Hue.*` (`.dashboard` uses the Smart Care hue), `TextSize` unchanged, `Spacing.xs…giant` mapped to the nearest new step. Mark all `@available(*, deprecated, message: "Use the Palette C token")`.
- [ ] **T1.4 `AuroraSurface`** (the Designer's modifier): solid when Reduce Transparency is on, `glassEffect(.regular, in:)` on macOS 26, `.regularMaterial` on 14–15. Not yet applied anywhere.
- [ ] **T1.5 Check the recoloured old screens.** The shim `accent → primaryDeep` is right for fills and for `.tint` on stock controls, but `primaryDeep` is a fill-only colour (2.81:1 on a dark card). Every old call site that used `Theme.accent` as an **icon or text** colour (`foregroundStyle(Theme.accent)`, tinted symbols) switches to `Theme.Color.primary` in this PR. Also check `border` where it is used as an opaque fill (it is now a translucent hairline).

**Verify.** Build; `swift test` (regression); `SOSMacTests` incl. `ThemeContrastTests`; snapshots of all 10 screens × dark/light before vs after: **layout identical, colours changed**. Read the token values against spec §2.3 line by line.

**Risks.** (a) A shim maps a semantic the old code relied on (e.g. `accent` as *icon tint*, now a fill-only colour) — fix call sites in this PR with the right new token. (b) Palette C light has never been rendered (OD-1): this PR is the first sighting; attach the light snapshots to the PR for the Designer.

**Standalone check.** The app is fully usable in Palette C on the old layout.

### PR E1 — CleanCore: memory "in use" (only if OD-11 = fix)

**Goal.** `MemoryInfo` reports an "in use" figure that does not count reclaimable inactive pages.

**Depends on:** 0. **Write set:** `Packages/CleanCore/Sources/CleanCore/Performance/MachHostStats.swift`, `Packages/CleanCore/Tests/CleanCoreTests/MachHostStatsTests.swift`.

- [ ] Add `public var inUseBytes: UInt64` (wired + active + compressed, capped at `totalBytes`) and `public var availableBytes: UInt64` (free + inactive, capped). Leave `usedBytes` in place; do not change its meaning.
- [ ] Tests: `inUseBytes ≤ totalBytes`, `inUseBytes + availableBytes` ≈ total within the compressor's accounting (assert `≥ totalBytes` is **not** required — document why), values non-negative on a live sample.

**Verify.** `cd Packages/CleanCore && swift test`; the app builds (no call site changes yet).

**Risks.** Physical memory accounting (`compressor_page_count` vs compressed pages) makes the five segments not sum exactly to total; the UI must not draw a 100 %-wide bar from them (PR 12 normalises).

### PR 2 — Shell

**Goal.** The new window, sidebar and toolbar, on every screen, with the old screen bodies.

**Depends on:** 1. **Write set:** `App/SOSMacApp.swift`, `App/DesignSystem/SidebarNavRow.swift`, `App/DesignSystem/ModuleToolbar.swift` (new), `App/Support/VolumeStorageInfo.swift`, `SOSMacUITests/RedesignSmokeTests.swift`.

- [ ] `WindowGroup { … }.defaultSize(width: 1200, height: 760)`; minimum 960 × 600 (OD-5); sidebar column `min: 200, ideal: 240`.
- [ ] Sidebar: the five groups of spec §3.2 in order; group labels; row = 22 pt hue tile (ink per §2.5) + label, 32 pt tall; hover `rowHover`, current `rowSelected` + tile glow; all rows fit at 760 pt.
- [ ] Rename `SidebarDestination.junkCleaner` raw value to `"Junk & Cache"` (identifier `sidebar-nav-Junk & Cache`); update the smoke test list.
- [ ] Footer: volume name + "«free» free", 4 pt meter, "«used» of «total» used". Drop the version line. The volume name is new in `VolumeStorageInfo` (`URLResourceKey.volumeNameKey` on the boot volume URL); omit the name when it is `nil`.
- [ ] Toolbar per spec §3.3 (OD-2): a `ModuleToolbarModel { title, subtitle, back: (label, action)?, tools }` applied with `.toolbar`: `.principal` title + subtitle, `.navigation` back button, `.primaryAction` tools. Set `navigationTitle` from the model so the title shows once. Give every screen a model in this PR (title = screen name; the old in-content headers stay until their screen PR).
- [ ] Materials per spec §7: do not draw a custom background behind system chrome; verify what the stock sidebar and toolbar render on each macOS version before adding any.
- [ ] `.auroraBloom()` stays on the old screens; each screen PR replaces it with `AuroraBackground`.

**Verify.** Build; smoke UI test; snapshots of three screens (Dashboard, Junk idle, Performance) × dark/light × Reduce Transparency on/off, on the newest available macOS and on 14 or 15 if a machine or VM is available; read against `?screen=…` of the prototype.

**Risks.** (a) System toolbar look on macOS 14/15 is unverified (spec D.4) — resolve in this PR with screenshots; if it is unacceptable, raise OD-2 again before continuing. (b) Window state restoration ignores `defaultSize` for existing users. (c) The raw-value rename touches identifiers used in docs.

**Standalone check.** Every old screen still works inside the new shell; nothing is clipped at 960 × 600.

### PR 3 — Session store

**Goal.** Results, selections and running scans survive navigation (spec §6.6).

**Depends on:** 2. **Write set:** `App/State/ModuleStore.swift` (new file in a new folder), `App/SOSMacApp.swift`, `App/Features/*/*View.swift` (only the view-model ownership lines), `App/Features/*/*ViewModel.swift` (only cancel-on-disappear and guards), `SOSMacTests/ModuleStoreTests.swift` (new).

- [ ] `@MainActor @Observable final class ModuleStore` owns one instance of each view model (`smartCare`, `junkCleaner`, `duplicates`, `spaceLens`, `uninstaller`, `updater`, `performance`, `cloudCleanup`, `protection`), plus `isScanning(_:)`.
- [ ] `RootView` owns the store (`@State private var store = ModuleStore()`), injects it with `.environment(store)`; each feature view takes its view model from the store instead of `@State private var viewModel = …`.
- [ ] Remove `.onDisappear { viewModel.cancelScan() }` from the five views that have it. Every scanning screen must keep an explicit Stop control: Smart Care has none today, so this PR adds a plain **Stop** button to its scanning state (PR 7 restyles it). Without it, a background Smart Care scan could not be stopped.
- [ ] `loadApps()` in Uninstaller and Updater, and the Updater auto-check, become first-visit-only (the store keeps rows).
- [ ] Busy dot on sidebar rows (OD-3): `store.isScanning(destination)`.
- [ ] Tests: the store returns the same instance for a destination across re-creation of the view hierarchy; a scan started with a scanner that never finishes is still `.scanning` after the owning view is recreated; a second `startScan` on a scanning module is refused.

**Verify.** Build; `SOSMacTests`; a manual pass on the checklist: start a scan, switch screens, return — same phase and progress; finish a scan, switch, return — same results and selection.

**Risks.** (a) Background scans use CPU and disk while the user is elsewhere; several modules may scan at once (allowed in v1 — a queue is a follow-up). (b) Retained results keep memory for the session (a 100 k-item junk list is a few MB of `ScanItem`s). (c) Views that relied on teardown for cleanup now need explicit resets ("Scan Again" already resets).

**Standalone check.** No visual change except the optional busy dot; behaviour change is the point of the PR.

### PR 4a — Components: primitives

**Goal.** The building blocks every screen needs, with snapshots, before any screen uses them.

**Depends on:** 1. **Write set:** new files in `App/DesignSystem/`: `ModuleTileView.swift`, `SOSButtonStyle.swift`, `SOSCheckbox.swift`, `KeepBadge.swift`, `BadgeView.swift` (restyled), `BannerView.swift`, `ResultTileView.swift`, `AuroraBackground.swift`; `App/DesignSystem/StepRowView.swift`, `ProgressBarView.swift` (restyled); `SOSMacUITests/ComponentGalleryTests.swift` (new).

- [ ] `ModuleTileView(hue:ink:symbol:size:)` — gradient fill, inner highlight, optional idle glow.
- [ ] Buttons (spec §4.4): try stock styles first; add a custom style only for the large CTA and `.plain`. Disabled = 0.42 opacity, no shadow.
- [ ] `SOSCheckbox`: 16 visual / ≥ 20 hit target; states off, on (`primaryDeep`, X1), mixed, disabled (dashed, X2 outline colour).
- [ ] `KeepBadge` and the kept-row treatment; `BadgeView` kinds and the X4 rule.
- [ ] `BannerView(kind:title:text:action:)`.
- [ ] `ResultTileView` (wide/full, check, skipped, body, foot).
- [ ] `AuroraBackground(hue:)` replacing `.auroraBloom()`.
- [ ] Restyle `StepRowView` (pending / active / done / failed) and `ProgressBarView`; keep `ScanProgressPanel` and `ScanProgressTracker` logic untouched.
- [ ] A Debug-only **component gallery** screen (`SOSMAC_UITEST_SCREEN=Gallery`) listing every component in every state, so one snapshot shows all of them.

**Verify.** Build; snapshot the gallery in dark/light/Reduce Transparency; contrast audit with Accessibility Inspector on the gallery; `SOSMacTests` (checkbox state logic if extracted).

**Risks.** Stock macOS buttons may not reach 28 / 34 pt — decide and document here.

**Standalone check.** Nothing uses the new components yet; the app is unchanged.

### PR 4b — Components: lifecycle frame, review frame, confirmation

**Goal.** The frame every scanning screen is assembled from.

**Depends on:** 4a. **Write set:** `App/DesignSystem/LifecycleState.swift`, `ModuleScreen.swift`, `DockView.swift`, `PrimaryCTAView.swift`, `StartView.swift`, `ScanningView.swift`, `DoneView.swift`, `StatusStateView.swift`, `ResultsHeaderView.swift`, `ReviewFrameView.swift`, `ReviewGroupRow.swift`, `ReviewItemRow.swift`, `ReviewDetailView.swift`, `ReviewBarView.swift`, `ConfirmSheet.swift`, `ConfirmItemList.swift` (all new); gallery + tests.

- [ ] `enum LifecycleState` and `ModuleScreen(module:state:subtitle:back:tools:content:overlay:)`: toolbar model, aurora background, canvas, dock, sheet presentation.
- [ ] `DockView` (128 pt) and `PrimaryCTAView` (80 pt circle, ring: none / determinate / indeterminate, stop and moving looks).
- [ ] `StartView`, `ScanningView` (orb sweep, steps, progress, path), `DoneView`, `StatusStateView` (empty / error), `ResultsHeaderView`.
- [ ] `ReviewFrameView` (three and two columns), group row, item row (normal / kept / focused), detail builder, review bar. Virtualised lists.
- [ ] `ConfirmSheet` with the five variants of spec §4.8 and `ConfirmItemList`; **Cancel is the default button**; the cloud variant enables its button only when the acknowledgement is on; presentation as a sheet (OD-4).
- [ ] `ProgressiveCleaner` helper (App target, `App/Services/ProgressiveCleaner.swift`): calls `Cleaner.clean([item])` per item, yields `(index, item)`, returns one aggregated `CleanResult` (spec §6.5).
- [ ] Unit tests: `ProgressiveCleaner` with real temp files, following `CleanerTrashTests` (trash a file, remove it from the Trash afterwards); `ConfirmSheet` state machine (cancel never calls the action; cloud requires the acknowledgement).

**Verify.** Build; `SOSMacTests`; gallery snapshots for every frame state × dark/light; Keyboard: Escape closes the sheet, Return activates Cancel.

**Risks.** Large lists inside a three-column `HStack` need `List` virtualisation in the middle column — test with a 100 k-row fixture.

**Standalone check.** Not used by screens yet; the gallery proves every state.

### PR 5 — Junk & Cache (the reference screen)

**Goal.** The first screen on the new frame. It sets the pattern every other screen PR copies: state table → `Phase` → `lifecycle` mapping → fixture states → snapshots.

**Depends on:** 3, 4b. **Write set:** `App/Features/JunkCleaner/JunkCleanerView.swift`, `JunkCleanerViewModel.swift`, `JunkReviewDetail.swift` (new), `SOSMacTests/JunkCleanerViewModelTests.swift` (new), `SOSMacTests/LifecycleMappingTests.swift` (new), fixture states for Junk in `UITestFixtures.swift`.

- [ ] `Phase`: `idle · scanning · results · review · cleaning(selectedCount:) · done(movedBytes:, movedCount:, failedCount:) · failed(message:)`; `var lifecycle: LifecycleState` (`results` with zero items and no failure → `.empty`).
- [ ] Start, Scanning (4 steps, "k of 4 locations", Stop), Results (4 tiles + banners), Review (groups by rule, helper banner S7, detail, **Ignore** if OD-8), Cleaning (`ProgressiveCleaner`, helper items via `trashSystemPath`), Done (stats + failure banner + Open Trash + Scan Again), Empty, Error (truthful copy, spec §6.3).
- [ ] Trash confirmation on the `results` and `review` paths, with the helper line.
- [ ] `loadFixture(_:)` for all eight states; add the eight states to the snapshot script's default list.
- [ ] Tests: lifecycle mapping table; pre-selection (safe and no helper); Select All skips caution and helper items; `cleaning` refuses a second call; failures are counted and surfaced; `Ignore` keeps working.
- [ ] "Open Trash" → `NSWorkspace.shared.activateFileViewerSelecting([trashURL])`.

**Verify.** Build; `swift test`; `SOSMacTests`; snapshots of all 8 states × dark/light next to `index.html?screen=junk&state=…&palette=c`; a real manual run on the dev Mac: scan → review → confirm → cancel → confirm → done → Trash contains the files.

**Risks.** The per-item clean loop under Swift 6 (first real use); 100 k-row review performance; `Open Trash` needs the Trash URL to exist.

**Standalone check.** Junk is fully migrated; every other screen still works as before.

### PR 6 — Duplicate Finder

**Depends on:** 5. **Write set:** `App/Features/Duplicates/DuplicateFinderView.swift`, `DuplicateFinderViewModel.swift`, `DuplicateSetDetail.swift` (new), `SOSMacTests/DuplicateFinderViewModelTests.swift` (new), fixtures.

- [ ] `Phase` + `.review`, `.cleaning(selectedCount:)`, `.failed(message:)`; re-entrancy guard (S5); failures on Done.
- [ ] Toolbar segment "Exact copies / Similar images" (`Mode` raw values change); the Similar banner on Start, Results, Review (S3).
- [ ] Error state: the reason names Privacy & Security › Full Disk Access; a button that opens it only if OD-18 = 2.
- [ ] Results tiles; skipped-files banner (`skippedCount`); review frame by set with the Keep lock; per-set totals if OD-b.
- [ ] Pre-selection in Similar mode per OD-a.
- [ ] Tests: mapping; keep copy never selectable (both modes); Select All skips kept; pre-selection per OD-a; groups recompute after a clean; per-set totals.

**Verify.** Build; `swift test`; `SOSMacTests`; snapshots of 8 states × 2 modes × dark/light vs `?screen=duplicates…`; manual real run in Exact mode.

**Risks.** Two fixture sets (exact, similar) double the snapshot matrix.

### PR 7 — Smart Care

**Depends on:** 5. **Write set:** `App/Features/SmartCare/SmartCareView.swift`, `SmartCareViewModel.swift`, `SmartCareReviewBuilder.swift` (new), `SOSMacTests/SmartCareViewModelTests.swift` (new), fixtures.

- [ ] `Phase`: `idle · scanning · results · review · cleaning(selectedCount:) · done(movedBytes:, movedCount:, failedCount:) · failed(message:)`.
- [ ] `SmartCareReviewItem` keeps `groupID` and `isRecommendedKeep`; `SmartCareReviewBuilder` groups junk by rule and duplicates by set (pure, tested).
- [ ] Stop button (N6); results tiles incl. the health tile and the failed/skipped tile; partial failure → `results` + banner; review with the Keep lock (S4); cleaning, done, empty, error per spec §5.2.
- [ ] Start-note sentence about macOS folder access (spec §6.3).
- [ ] Tests: keep lock; nothing found in one module and a failure in the other → not `empty`; both failed → `error`; Stop returns to `start`.

**Verify.** Build; `swift test`; `SOSMacTests`; snapshots of 8 states + the partial-failure state × dark/light vs `?screen=smartcare…`; manual real run.

**Risks.** The full-Home duplicate pass is slow to test manually; rely on fixtures for states.

### PR 8 — Space Lens

**Depends on:** 5. **Write set:** `App/Features/SpaceLens/SpaceLensView.swift`, `SpaceLensViewModel.swift`, `TreemapCanvasView.swift`, `SpaceLensInspector.swift` (new), `SpaceLensReviewSheet.swift` (new), `SOSMacTests/SpaceLensViewModelTests.swift` (new), fixtures.

- [ ] Rename phases: `.loaded → .results`, `.reviewing → .review`; add `.cleaning(selectedCount:)`, `.done(movedBytes:, movedCount:, failedCount:)`, `.failed(message:)`.
- [ ] Start with the source list (Home, Choose Folder…, external volumes); Scanning count-only; Results: breadcrumb, segment, treemap, legend, inspector, review bar.
- [ ] Treemap: ramp tokens, "smaller items" cell, size labels by cell size, selection ring, in-list dot, hover, cell accessibility (`accessibilityLabel`, `.isButton`, `accessibilitySortPriority`).
- [ ] Inspector actions; protected explanation; existing ineligibility copy.
- [ ] Cleanup-list sheet with checkboxes and Total (replaces the checkbox-less sheet); Cleaning; Done with Back to Map (N7); Empty; Error.
- [ ] Tests: nothing pre-selected; cart keeps only top-most items; the smaller-items merge (count and size); selection never includes an ineligible path; phase mapping.

**Verify.** Build; `swift test`; `SOSMacTests`; snapshots of 8 states × By Folder / By Type × dark/light vs `?screen=spacelens…`; VoiceOver pass over the treemap; manual run on `/Applications` and on a folder with > 1 000 items.

**Risks.** Treemap label collisions at small sizes; accessibility of hundreds of cells; the canvas and `List` scroll nesting.

### PR 9 — Uninstaller

**Depends on:** 5. **Write set:** `App/Features/Uninstaller/UninstallerView.swift`, `UninstallerViewModel.swift`, `UninstallerReviewDetail.swift` (new), `SOSMacTests/UninstallerViewModelTests.swift` (new), fixtures.

- [ ] `Phase`: `browsing · inspectingAll(currentBundleID:) · measured · reviewing(bundleID:) · cleaning(appName:, selectedCount:) · removed(appName:, atLeastBytes:, itemCount:, failedCount:)`; per-row `inspectError` (busy flags leave the enum's side).
- [ ] Start / Scanning (Inspect All) / Results / Review (two columns) / Cleaning / Done / Empty / Error per spec §5.7.
- [ ] D1 labels: `kind == .directory` → "Folder"; totals with a folder → "At least …"; "N folders not measured yet."
- [ ] Uninstall confirmation; running-app check and "Quit «App» first" step if OD-9; real icons if OD-12; name filter if OD-13.
- [ ] Tests: "At least" only when a directory is selected; `inspectError` surfaces in `browsing`; pre-selection = all items; a second inspect is refused.

**Verify.** Build; `swift test`; `SOSMacTests`; snapshots of 8 states × dark/light vs `?screen=uninstaller…`; manual run on one real app (Phương chooses a disposable one; nothing is moved in the automated checks).

**Risks.** Real icon loading for 60+ apps (cache icons in the view model); `NSRunningApplication` check timing.

### PR 10 — Updater

**Depends on:** 5. **Write set:** `App/Features/Updater/UpdaterView.swift`, `UpdaterViewModel.swift`, `UpdaterGroups.swift` (new), `SOSMacTests/UpdaterViewModelTests.swift` (new), fixtures.

- [ ] `Phase`: `idle · checking · results · empty · failed(message:)`; per-row `checkError`.
- [ ] Start ("Check"), Checking (progress tile, Stop), Results (four groups), Empty; no automatic check on visit (OD-10).
- [ ] Failed-check badge and banner if OD-10 = include; real icons if OD-12.
- [ ] Tests: mapping; a throwing feed sets `checkError` and never reads "Up to date"; Stop leaves rows checked so far.

**Verify.** Build; `swift test`; `SOSMacTests`; snapshots of 4 (+1) states × dark/light vs `?screen=updater…`; manual run (network).

**Risks.** Network-dependent manual run; a failed-check state needs a fixture.

### PR 11 — Cloud Cleanup

**Depends on:** 5. **Write set:** `App/Features/CloudCleanup/CloudCleanupView.swift`, `CloudCleanupViewModel.swift`, `CloudProvidersColumn.swift` (new), `SOSMacTests/CloudCleanupViewModelTests.swift` (new), fixtures.

- [ ] `Phase` per provider (spec §5.6); replace the per-provider Booleans.
- [ ] Providers column; "not set up in this build" states (D5). The iCloud error names Apple Account › iCloud as an instruction (button only if OD-18 = 2).
- [ ] iCloud Drive: full lifecycle with the **local** Trash confirmation; groups recomputed and failures reported after a move (S6); pre-selection per OD-7.
- [ ] Server-side delete: selection + danger CTA + **cloud** confirmation with acknowledgement, on the existing Drive / OneDrive / Dropbox delete paths.
- [ ] Tests (fake provider): nothing is deleted before confirmation; the cloud confirm is disabled until acknowledged; groups recompute; `failed` is reported; iCloud pre-selection rule.

**Verify.** Build; `swift test`; `SOSMacTests`; snapshots of iCloud 8 states + the three not-configured states + the Drive target state × dark/light vs `?screen=cloud…`; manual run on iCloud Drive.

**Risks.** The server-delete UI is unreachable without OAuth apps — prove it with unit tests and a fixture snapshot only.

### PR 12 — Performance

**Depends on:** 5 (and E1 if OD-11 = fix). **Write set:** `App/Features/Performance/PerformanceView.swift`, `PerformanceViewModel.swift`, `PerformanceMetricCards.swift` (new), `MaintenanceRows.swift` (new), `SOSMacTests/PerformanceViewModelTests.swift` (new), fixtures.

- [ ] `metrics: .live / .unavailable`; per action `ActionState: idle · running · needsApproval · succeeded · failed`.
- [ ] Toolbar subtitle; unavailable banner; metric grid (CPU, segmented memory + legend, thermal, load averages, table); maintenance rows with inline banners; widget and login cards.
- [ ] Segment colours per spec §5.9; "in use" from `inUseBytes` (E1) or the OD-11 fallback; switch copy per OD-14; thermal state shown once.

**Verify.** Build; `swift test`; `SOSMacTests`; snapshots of 6 states × dark/light vs `?screen=performance…`; manual: Run Free up RAM on a machine without the helper (approval state) and with it (ok state).

**Risks.** Privileged-helper states are hard to reach deterministically — fixtures.

### PR 13 — Protection

**Depends on:** 5. **Write set:** `App/Features/Protection/ProtectionView.swift`, `ProtectionViewModel.swift`, `QuarantinePanelView.swift` (new), `SOSMacTests/ProtectionViewModelTests.swift` (new), fixtures.

- [ ] `Phase`: `idle · scanning · results · review · quarantining(selectedCount:) · done(quarantinedCount:, failedCount:) · failed(message:)`; `isShowingQuarantine`.
- [ ] Start (disclaimer, six locations, quarantine panel), Scanning (six steps, files, ETA), Results (two tiles), Review, Quarantine confirmation, Quarantining, Done, Quarantine sub-screen in a scroll view (N8), Empty, Error with truthful copy.
- [ ] Remove "Check VirusTotal" if OD-15.

**Verify.** Build; `swift test`; `SOSMacTests`; snapshots of 9 states × dark/light vs `?screen=protection…`; manual run (the EICAR test file may appear as a finding on a dev machine).

**Risks.** Quarantine records come from SwiftData — fixtures need an in-memory container.

### PR 14 — Dashboard

**Depends on:** 3, 4a (and E1 if OD-11 = fix). **Write set:** `App/Features/Dashboard/DashboardView.swift`, `DashboardModuleCards.swift` (new), fixtures.

- [ ] Hero, snapshot tiles ("Read when this page opened"), two module-card sections; no placeholder lines (D6).
- [ ] "Run Smart Care" opens Smart Care and calls `store.smartCare.startScan()` (N3). `startScan()` already exists, so this PR does not wait for PR 7.
- [ ] The "Memory in use" tile reads `inUseBytes` when E1 has landed, otherwise the OD-11 fallback; it never shows the `usedBytes` percentage.

**Verify.** Build; smoke UI test asserts "Run Smart Care" lands on a scanning Smart Care; snapshots × dark/light vs `?screen=dashboard`.

### PR 15 — Menu bar helper

**Depends on:** 1. **Write set:** `project.yml`, `MenuBarHelper/MenuBarHelperApp.swift`, `MenuBarMetricsMonitor.swift`, `MenuBarHelper/MenuBarPopover.swift` (new). No file moves: `project.yml` lists the token files that the helper needs (`App/DesignSystem/Theme.swift`, `AuroraSurface.swift`, `ModuleTileView.swift`, `BadgeView.swift`) as sources of `MenuBarHelper` too. Only files that import nothing app-specific may be listed — `Theme.swift` must not reference `SidebarDestination`.

- [ ] Fixed-width label with monospaced digits; popover: header, CPU and memory cards, Open SOS Mac (⌘O) and Quit Widget (⌘Q).
- [ ] "Open SOS Mac" by bundle identifier (`NSWorkspace`).
- [ ] "in use" from `inUseBytes` (E1) if shipped.
- [ ] `xcodegen generate`; both targets build with no duplicate-symbol errors; the app target is unchanged in behaviour.

**Verify.** Build of both targets; launch the helper and check the label does not change width between samples; popover colours match Palette C.

**Risks.** A token file that grows an app-only reference breaks the helper target — the contrast tests (PR 1) and this target's build catch it. The helper is an `LSUIElement` app and cannot be snapshotted by the same script without a tweak.

### PR 16 — Cleanup

**Depends on:** 6–15. **Write set:** `App/DesignSystem/**` (delete unused), `App/DesignSystem/Theme.swift` (remove shims), `App/**` call sites still using shims, `CLAUDE.md`, `docs/codebase-summary.md`, `docs/code-standards.md`.

- [ ] Delete every legacy component no longer referenced (`HeroPanelView`, `HealthDialView`, `ModuleCardView`, `EmptyStateView`, `SummaryCardView`, `StickyFooterView`, `.careCard()`, `.auroraBloom()`, old `TextSize`, `ModuleHue`, `Elevation.Level` if replaced).
- [ ] Remove the deprecated shims and fix the remaining call sites (grep for `deprecated` warnings: zero).
- [ ] Update the design reference in `CLAUDE.md` (source is now the OpenDesign project "SOS Mac Redesign v1 — Aurora Indigo", Palette C) and the component tables in `docs/codebase-summary.md` / `docs/code-standards.md`.
- [ ] Final pass: all snapshots regenerated, the contact sheet compared state by state with `board.html`.

**Verify.** Build with zero warnings from deprecations; `swift test`; `SOSMacTests`; full snapshot matrix.

---

## 5. Verification matrix

Every cell = one snapshot in dark **and** light, next to the prototype state named by the query. "Manual" = a real run on the development Mac; it is never automated.

| Screen | States to snapshot (prototype `index.html?screen=…&state=…&palette=c`) | Unit tests | Manual |
|---|---|---|---|
| Junk & Cache | start, scanning, results, review, cleaning, done, empty, error, `dialog=trash` | PR 5 | yes |
| Duplicate Finder | 8 states × `dup=exact` / `dup=similar` | PR 6 | yes (exact) |
| Smart Care | 8 states + partial failure, `dialog=trash` | PR 7 | yes |
| Space Lens | 8 states × By Folder / By Type, `state=review` (sheet) | PR 8 | yes |
| Cloud Cleanup | 8 states (iCloud), 3 not-configured, `state=drive`, `dialog=cloud` | PR 11 | yes (iCloud) |
| Uninstaller | 8 states, `dialog=uninstall` | PR 9 | yes (one disposable app) |
| Updater | start, scanning, results, empty (+ failed) | PR 10 | yes |
| Performance | live, running, approval, actiondone, actionerror, unavailable | PR 12 | yes |
| Protection | 8 states, quarantine, `dialog=quarantine` | PR 13 | yes |
| Dashboard | default | smoke test | — |
| Menu bar | popover (`pop=1`) | — | yes |
| Components | gallery, every state | PR 4a/4b | — |

Cross-cutting, on the latest PR of each group: Reduce Transparency on (hook), Increase Contrast on (System Settings, manual), minimum window size.

## 6. What must be true before PR 1 starts

1. Phương approves the spec.
2. OD-1 (Palette C light) is answered, or its default is accepted **and** the Designer has seen the light snapshots from PR 1 before it merges.
3. OD-2 … OD-6 are answered or their defaults accepted.
4. OD-16 and OD-17 (prototype snapshot in the repo; running tests on the dev Mac) are answered before PR 0.
5. OD-18 (System Settings deep links) is answered before PR 6.
6. Screen decisions (OD-a, OD-b, OD-7 … OD-15) can stay open until their PR; each PR description lists the default it used.

## 7. PR description template

```markdown
## What changes for the user
## Safety impact (removal paths, confirmations, pre-selection)
## Prototype states implemented (links)
## Open decisions used (OD-… → option, or default)
## Tests run
- [ ] xcodebuild build -scheme SOSMac -configuration Debug
- [ ] cd Packages/CleanCore && swift test
- [ ] SOSMacTests (unit)
- [ ] Scripts/ui-snapshots.sh (link to the contact sheet)
## Differences from the prototype, and why
```

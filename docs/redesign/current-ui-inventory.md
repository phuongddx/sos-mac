# SOS Mac — Current UI Inventory (input for the redesign)

> **Purpose.** An accurate, code-level description of what SOS Mac looks and behaves like *today*, so the Designer can redesign from reality instead of from mockups or assumptions. Read this together with the screenshots in [`screenshots/`](screenshots/) (see [§6](#6-screenshots)).
>
> **Baseline.** Branch `main`, commit `0587765` ("docs: add live scan progress implementation plan"), captured 2026-11-26. Built with Xcode 27.1 on macOS 27.0.1 (deployment target macOS 14.0). Every statement below was read from source; file paths are relative to the repo root. Nothing in `App/`, `Packages/`, `MenuBarHelper/` was changed to produce this document.

---

## At a glance

1. One window, one `NavigationSplitView`: a 10-row sidebar + one detail screen, no toolbar, no settings, no onboarding. Opens at ≈ 900 × 532 pt.
2. Ten screens: Dashboard, Smart Care, Junk & Cache Scanner, Uninstaller, Updater, Space Lens, Duplicate Finder, Performance, Cloud Cleanup, Protection — plus a separate, unthemed menu-bar widget.
3. Most screens follow the same arc — **empty state → scanning → review list → cleaning → success card** — built from one shared component kit (`App/DesignSystem/`).
4. The current look ("Aurora Care") is a neutral light/dark UI with one blue accent (`#2F6FEB`), a teal gradient partner, soft raised cards, an aurora glow per screen, and an 11-colour module-hue map that mostly shows in the sidebar.
5. Six of the ten screens have a `Phase` enum; Dashboard, Performance, Updater and Cloud have none (Booleans instead), Duplicates has no cleaning state, and the Uninstaller tracks its busy state outside its enum.
6. **The biggest UX gaps:** no confirmation before any removal (cloud rows delete on one tap), results vanish when you leave a screen, errors are bare red lines, and no busy feedback while cleaning.
7. **The biggest visual gaps:** module hues barely reach the content, the treemap is an unrelated rainbow, type sizes are off-scale, and the same action differs in colour, size and wording between screens.
8. Only part of the product is real today: the three cloud OAuth providers are unconfigured, Protection's database holds one signature, the menu-bar widget does not auto-launch.
9. **Hard rules:** no invented numbers, Trash-only local deletes, protected "Keep" copy in duplicate groups, review before removal.
10. 33 window screenshots (light + dark, several states) are in [`screenshots/`](screenshots/) on the machine that took them; 24 of them are in git ([§6](#6-screenshots) says which and why); most show an inactive window, so system buttons look grey there.

---

## Contents

1. [App structure](#1-app-structure)
2. [Screens and modules](#2-screens-and-modules)
3. [Current design system](#3-current-design-system-aurora-care)
4. [Constraints the redesign must respect](#4-constraints-the-redesign-must-respect)
5. [UX pain points and inconsistencies](#5-ux-pain-points-and-inconsistencies)
6. [Screenshots](#6-screenshots)
7. [Where the docs and the code disagree](#7-where-the-docs-and-the-code-disagree)
8. [Appendix — file index](#8-appendix--file-index)

---

## 1. App structure

### 1.1 Processes and targets

| Target | Kind | UI? | What it is |
|---|---|---|---|
| `SOSMac` | SwiftUI app (`App/SOSMacApp.swift`) | Yes | The whole product: one window, sidebar + detail. |
| `MenuBarHelper` | Separate embedded `.app` (`MenuBarHelper/`) | Yes (tiny) | `MenuBarExtra` showing CPU/RAM. No IPC with the main app; reads metrics itself. Copied into `SOSMac.app/Contents/Library/LoginItems/`. Not auto-launched. |
| `PrivilegedHelper` | XPC daemon tool (`PrivilegedHelper/`) | No UI | Root operations: trash a system path, purge memory, flush DNS, load/unload a daemon plist. Registration needs System Settings approval. |
| `SOSMacUITests` | XCUITest bundle | — | One test that screenshots every sidebar destination (full-screen captures to a temp folder). |

The shared UI layer (`App/DesignSystem/`) lives **only in the app target** — the MenuBarHelper does not use it and has no theme at all.

### 1.2 Window and navigation shell

| Aspect | Current behaviour | Source |
|---|---|---|
| Scene | One `WindowGroup` → `RootView`. No `Settings` scene, no extra windows, no popovers. | `App/SOSMacApp.swift:6-12` |
| Layout | `NavigationSplitView` with a sidebar column (`min: 200, ideal: 232`) and a detail column. | `App/SOSMacApp.swift:61-64` |
| Size | `minWidth: 720, minHeight: 480`. **No default size is set.** On the very first launch macOS fits the window to the content (observed 882 × 522 pt); later launches restore the previous frame (900 × 532 pt on the machine used for the screenshots). | `App/SOSMacApp.swift:88` |
| Title bar | Standard macOS title bar. The title is the selected screen's `navigationTitle` ("Dashboard", "Smart Care", …). No toolbar items, no subtitle, no custom toolbar. | each `*View.swift` |
| Navigation | A single `@State selection: SidebarDestination?` bound to the sidebar. No navigation stack inside a screen, no back/forward, no deep links, no tab key focus management. | `App/SOSMacApp.swift:45, 65-87` |
| Menus / shortcuts | Default SwiftUI app menu; there are **no custom commands, no keyboard shortcuts, no context menus, no drag & drop** anywhere in `App/`. | grep for `.commands`, `keyboardShortcut`, `contextMenu` → none |
| Appearance | Follows the system (light/dark). `Theme` has light and dark values. A UI-test-only env var `SOSMAC_UITEST_APPEARANCE` can force one. | `App/SOSMacApp.swift:52-58` |
| Language | English only, all strings hardcoded in the views (no `.strings`/`.xcstrings`). | — |
| Persistence | SwiftData container for two models: `IgnoredItem` (Junk ignore list) and `QuarantineRecord` (Protection quarantine). Nothing else persists — no scan history, no settings. | `App/SOSMacApp.swift:10`, `App/Support/` |
| Onboarding / paywall / licensing | **None in the app.** First launch opens the Dashboard directly. (`onboarding.html` / `paywall.html` exist only as old Open Design mockups.) | — |
| Settings screen | **None.** `SidebarDestination` has no `.settings` case. | `App/SOSMacApp.swift:14-24` |
| Permissions | No permission priming. Scans that walk the home folder (Smart Care, Duplicate Finder, Space Lens) also reach Desktop / Documents / Downloads / iCloud Drive, so macOS permission prompts can appear **in the middle of a scan** the first time. (Expected platform behaviour; not observed during the unattended capture.) | — |

### 1.3 Sidebar

Order is fixed (`App/SOSMacApp.swift:102-118`); each row is a `SidebarNavRow` (24 pt icon tile + label, 13.5 pt) inside a plain `Button` with identifier `sidebar-nav-<rawValue>`:

| # | Row label (raw value) | SF Symbol | Group | Hue |
|---|---|---|---|---|
| 1 | Dashboard | `sparkles` | — | `#2F6FEB` |
| 2 | Smart Care | `wand.and.stars` | — | `#7C5CF5` |
| 3 | Junk & Cache Scanner | `trash` | **ESSENTIAL TRIO** | `#17B3B3` |
| 4 | Uninstaller | `xmark.bin` | (same group) | `#EF8B3C` |
| 5 | Updater | `arrow.triangle.2.circlepath` | (same group) | `#2BA55F` |
| — | *(8 pt unlabelled gap)* | | | |
| 6 | Space Lens | `square.grid.3x3.fill` | — | `#8B5CF6` |
| 7 | Duplicate Finder | `doc.on.doc` | — | `#D9578A` |
| 8 | Performance | `gauge.with.dots.needle.50percent` | — | `#D9A21B` |
| 9 | Cloud Cleanup | `icloud` | — | `#3A9CE0` |
| 10 | Protection | `shield.lefthalf.filled` | — | `#5566E0` |

- Row states: inactive = icon tile with a 14 % hue wash + hue glyph; active = solid hue tile with white glyph + glow, plus a **generic accent-blue** 12 % wash and 22 % border on the whole row (not the module hue).
- The sidebar is a `ScrollView` with 1 pt row spacing; at the default window height the last row ("Protection") is cut off behind the footer and a vertical scroller is visible.
- Footer (pinned with `safeAreaInset`): a 4 pt storage bar with "used / total" (real boot-volume numbers via `VolumeStorageInfo`; re-read on navigation, not polled) and the centered line "SOS Mac 0.1.0".

### 1.4 How state lives (important for the redesign)

Every screen owns its view model as `@State private var viewModel = XViewModel()` inside the view. `NavigationSplitView` destroys the detail view when another sidebar row is selected, so:

- **All results are lost when the user leaves a screen** and it comes back in its initial state. The Dashboard says so in its own header comment: there is no "last scanned" history to show.
- A running scan is cancelled by `.onDisappear { viewModel.cancelScan() }` (Smart Care, Junk, Duplicates, Space Lens, Protection).
- The Performance screen polls only while visible; Updater re-checks every app's feed and Uninstaller reloads its list on every visit.

### 1.5 MenuBarHelper UI (`MenuBarHelper/MenuBarHelperApp.swift`)

- Menu-bar item: SF Symbol `gauge.with.dots.needle.50percent` + text label that switches between **"SOS Mac"** (before the first sample) and **"CPU «n»%"** (after), polled every 2 s.
- Click opens a `.window`-style panel, 220 pt wide, default system styling (no `Theme`): "SOS Mac" headline → "CPU: «n»%" (or "CPU: —") → "Memory: «used» / «total»" (only if available) → divider → **Quit** button.
- No link back to the main app, no settings, no charts.

---

## 2. Screens and modules

Each section lists the **Phase enum verbatim**, what each phase renders, the controls, and the **real data fields** available to the UI. "VM" = the view model. Copy strings are quoted exactly as they appear.

### 2.1 Dashboard

**Files:** `App/Features/Dashboard/DashboardView.swift` (139 lines) — no view model, no Phase; one static state.

**Purpose:** Landing screen: storage at a glance and a route into every other module (and into Smart Care). No scanning happens here.

| Element | What is shown |
|---|---|
| Background | `Theme.background` + `.auroraBloom()`; content padding 32 pt; vertical rhythm 32 pt between hero and grid. |
| Hero panel (`HeroPanelView`, the only use in the app) | Eyebrow **"SYSTEM STATUS"** (dashboard blue) · title **"Pick a module, or run Smart Care"** (32 pt bold) · subtitle "A guided pass across the essentials cleans, optimizes, and reviews in one go — nothing is changed until you approve it." (14 pt muted, max 420 pt) · primary button **"Run Smart Care"** (large). Right of a 1 pt divider: **Storage** block (240 pt): "«used» GB used of «total» GB", a 10 pt progress bar, "«free» GB free". |
| Section label | "MODULES" (12.5 pt semibold, muted). |
| Module grid | `LazyVGrid`, adaptive columns ≥ 220 pt, 20 pt gaps. 8 `ModuleCardView`s in this order: Junk & Cache ("Cache & temp files"), Uninstaller ("Apps & leftovers"), Updater ("App updates"), Space Lens ("Disk usage map"), Duplicate Finder ("Exact & similar files"), Performance ("Live system metrics"), Cloud Cleanup ("Drive · Dropbox · OneDrive · iCloud"), Protection ("Known-signature malware scan"). |

- **Card anatomy:** 38 pt gradient hue tile + white SF Symbol, title 13 pt semibold, subtitle 12.5 pt muted, a 20 pt "stat" line, a badge, 70 pt hue wash from the top, radius 16, hairline border, raised elevation. Whole card is a plain button that navigates.
- **Stat line per card:** 7 of 8 cards show a fixed placeholder — "Not scanned this session" (Junk, Space Lens, Duplicates, Protection), "Not reviewed this session" (Uninstaller), "Not checked this session" (Updater), "Not opened this session" (Cloud) — with a neutral **"Open"** badge. Only **Performance** shows live data: "Load «x.x» · RAM «n»%" (or "RAM «n»%", or "Live metrics" when unavailable) with a safe **"Live"** badge.
- **"Run Smart Care" only navigates** to the Smart Care screen; it does not start a scan.
- Smart Care itself has no card; the Dashboard has no card state that reflects results from other screens (state is not shared — see §1.4).
- **Real data available:** boot-volume used/total/free bytes; CPU load averages; memory used/total; thermal state. Both are read **once, each time the Dashboard view is created** (not live).
- **Intentionally absent:** health dial / health score, recent-activity feed, "last scan" timestamps (documented in the file header, lines 3-10).

### 2.2 Smart Care

**Files:** `App/Features/SmartCare/SmartCareView.swift` (230), `SmartCareViewModel.swift` (262). Title: **"Smart Care"**. Hue `#7C5CF5` (used only on the empty-state icon).

**Purpose:** One guided pass — junk cleanup + exact duplicates + a read-only health snapshot — reviewed and cleaned in a single list.

```swift
enum Phase { case idle, scanning, review, cleaning, summary(reclaimedBytes: Int64, itemCount: Int, failureCount: Int) }
enum ModuleStatus { case pending, scanning, done(count: Int), failed }
```

| Phase | What is shown | Controls |
|---|---|---|
| `.idle` | `EmptyStateView`: orb icon `wand.and.stars`, **"Run Smart Care"**, "Smart Care runs Junk & Cache cleanup and Duplicate Finder together, with a quick health check — nothing is deleted without your review." | **Run Smart Care** (large, prominent) |
| `.scanning` | Optional aggregate `ScanProgressPanel` (a real bar on a synthetic 0–1000 scale; appears only once every running module has reported progress) + two `StepRowView`s: **"Junk & Cache"** and **"Duplicate Files"**, each with meta "Waiting…" / "Scanning…" / "Found N" — a failed module keeps a pending row with a red **"Failed"** badge overlaid on the right. | **None** (no Cancel button; leaving the screen cancels) |
| `.review` / `.cleaning` | Scroll view: **Health Check** card ("Load Average (1m)", "Memory", "Thermal State" rows) → one card per source module (sorted by name: "Duplicate Files", "Junk & Cache") with header + total bytes → checkbox rows (file name only, size). If nothing was found: "Nothing found — you're all clean." Pinned `StickyFooterView`: **"Total selected"** + bytes. | Checkboxes · **Clean Selected** (large, red, destructive role; disabled when nothing is selected or while cleaning) |
| `.summary` | `SummaryCardView` ("«size» reclaimed" / "Smart Care reclaimed space across «n» items"), a red badge "N items failed" when relevant. | **New Scan** (large, prominent) → back to `.idle` |

- **Scan scope:** 3 junk rules (everything "safe" that needs no helper) **+ an exact-duplicate scan of the entire home directory** — the same full SHA-256 pass as Duplicate Finder, so it can take minutes.
- **Pre-selection (actual behaviour):** junk items with severity `safe` are pre-checked; every duplicate **except the newest copy** is pre-checked. Duplicate rows are **flat** inside the "Duplicate Files" card (not grouped per set), and the newest copy is neither marked nor protected — its checkbox is simply off but enabled.
- Errors: a bare red line under the content. If cleaning throws, the screen returns to `.review` with that line.
- **Real data available:** the list above, plus per-item `severity`, `sourceLabel`, `requiresPrivilegedHelper` (not shown).

### 2.3 Junk & Cache Scanner

**Files:** `App/Features/JunkCleaner/JunkCleanerView.swift` (171), `JunkCleanerViewModel.swift` (150). Title: **"Junk & Cache Scanner"** (the sidebar label wraps to two lines). Hue `#17B3B3`.

**Purpose:** Find cache and log files from a fixed allowlist and move the selected ones to the Trash.

```swift
enum Phase { case idle, scanning, results, cleaning, done(reclaimedBytes: Int64) }
```

| Phase | What is shown | Controls |
|---|---|---|
| `.idle` | `EmptyStateView`: `trash`, **"Scan for junk"**, "Finds caches and logs that are safe to remove." | **Start Scan** (large, prominent) |
| `.scanning` | `ScanProgressPanel` (max 420 pt): bar + "N %" (rules completed / 4) and one `StepRowView` per rule, in scan order: **"User App Caches" → "User Logs (7+ days old)" → "App Support Cache Folders" → "System Caches (requires additional permission)"** (done / active-pulsing / pending). | **Cancel** |
| `.results` / `.cleaning` | Plain `List`, **one row per file**: checkbox · file name · source label (the rule name) · severity badge ("Safe" green / "Caution" amber / "Risky" red) · **"Needs Helper"** neutral badge when applicable · size · **Ignore** (plain-text button). Pinned `StickyFooterView`: **"Total reclaimable"** + bytes. | Checkboxes · Ignore · **Clean** (default size, **blue accent**) |
| `.done` | `SummaryCardView`: big number + caption **"reclaimed"**. | **Done** (default size) → back to `.results` with the remaining items |

- **Scan scope:** a fixed allowlist of 4 roots — `~/Library/Caches`, `~/Library/Logs`, `~/Library/Application Support/*/Cache*`, `/Library/Caches` — and the engine returns **every file** under them (not per-folder totals), so the list can be tens of thousands of rows with repeated names and no parent-folder context.
- **Pre-selection:** items that are `safe` and need no helper. Items needing the helper are never pre-selected.
- **Ignore** saves an `IgnoredItem` and removes the row. There is **no UI to review or undo the ignore list**.
- Severity: "User Logs" items are `safe` only when older than 7 days (by access time), otherwise `caution`; system caches are `caution`.
- Errors: red line at the bottom; after cleaning, "N items couldn't be removed: «reason»" is shown on the done screen.

### 2.4 Uninstaller

**Files:** `App/Features/Uninstaller/UninstallerView.swift` (283), `UninstallerViewModel.swift` (158). Title: **"Uninstaller"**. Hue `#EF8B3C` (used for every app tile, so all tiles are the same orange).

**Purpose:** Remove an application bundle together with its associated files, one app at a time.

```swift
enum Phase { case browsing, inspecting(bundleID: String), removed(appName: String, reclaimedBytes: Int64) }
// busy state is tracked outside the Phase: inspectingBundleID: String?, isInspectingAll: Bool
```

| Phase | What is shown | Controls |
|---|---|---|
| `.browsing` | Header: **"Uninstaller"** (24 pt) + "«N» applications installed", or "«N» applications installed · «size» reclaimable if all removed" once sizes are known. Right: **Inspect All**. While it runs: a `ScanProgressPanel` (real bar + %, and the app currently being inspected). Below: a list of app rows. Empty: `EmptyStateView` "No applications found" / "SOS Mac couldn't find any applications in /Applications or ~/Applications." | **Inspect All** / **Cancel** (bordered) · per row **Inspect** (bordered; disabled while another row or Inspect All runs — the row then shows a small spinner) |
| `.inspecting` | **"Reviewing «App»"** + a list of associated items: checkbox · full path (middle-truncated) · source label ("Application bundle" / "Associated with «bundle ID»") · size. Error line if any. Pinned `StickyFooterView`: **"Selected"** + "N items · «size»". | Checkboxes · **Cancel** (bordered) · **Uninstall** (prominent, red; disabled when nothing is selected) |
| `.removed` | `SummaryCardView`: "«size»" + "«App» removed, along with its associated files." | **Done** (large, prominent) → back to `.browsing` |

- **App row anatomy:** 30 pt rounded tile filled with the module hue showing the **first letter of the app name** (not the real icon) · name (14 pt medium) · "Version «x»" (12 pt) · size (only after Inspect / Inspect All) · **"App Store"** accent-blue badge when the bundle has a Mac App Store receipt. Container: radius 8, hairline border, raised elevation, 12 pt padding.
- **What an inspect finds:** the `.app` bundle (size computed recursively) plus entries in `~/Library/{Caches, Preferences, Application Support, Saved Application State, Containers, LaunchAgents}` whose name equals the bundle ID or starts with `<bundleID>.`. All are pre-selected.
- **Flow is one app at a time:** no multi-select, no sort/search/filter, no "last used", no size until inspected, no running-app check, no warning for App Store apps beyond the badge.
- **Error gap:** `errorMessage` is rendered only inside `.inspecting`. A failed per-row **Inspect** in `.browsing` shows nothing.
- **Data-accuracy gap:** associated *folders* get their size from `attributesOfItem(.size)`, which is the directory entry's own size (bytes), not the folder's content (`Packages/CleanCore/Sources/CleanCore/Uninstaller/BundleAssociatedFilesFinder.swift:30-40`). The "N items · «size»" total, "reclaimable if all removed" and the removed summary are therefore understated. The real fields are: name, bundle identifier, version, bundle path, App Store flag, Sparkle feed URL, per-item path and size.

### 2.5 Updater

**Files:** `App/Features/Updater/UpdaterView.swift` (184), `UpdaterViewModel.swift` (76). Title: **"Updater"**. Hue `#2BA55F` (only the empty-state icon). **No Phase enum** — state is `rows: [AppUpdateRow]` (app, `latestVersion?`, `isChecking`) plus `isCheckingAll`.

**Purpose:** Show which installed apps have a newer version. Read-only — nothing is installed.

| State | What is shown | Controls |
|---|---|---|
| No apps | `EmptyStateView`: `arrow.triangle.2.circlepath`, **"Looking for installed applications"**, "Scanning your Mac for installed apps and checking their versions. If nothing turns up, try checking again." | **Check Again** |
| Checking | Header **"Updater"** + "«N» update(s) available" / "All applications up to date" + **Check Again** (disabled). Under it: `ScanProgressPanel` (real bar + % and the app currently being checked), or a single `StepRowView` "Checking for updates…" before the first tick. Then the rows. | — |
| Done | Same header; the line **"No Sparkle-based updates pending"** when nothing is outdated. | **Check Again** |

- **Row anatomy (each row is a full card:** `.careCard()` → 20 pt padding, radius 16, raised elevation, so a row is ≈ 90 pt tall**): real app icon via `NSWorkspace` (30 pt) · name (14 pt semibold) · monospaced version "1.2.3" or **"1.2.3 → 1.2.4"** · one status: spinner · **"Update available"** (amber) · **"View in App Store"** (small bordered button, App Store apps) · **"No update mechanism"** (neutral grey, apps without a Sparkle feed) · **"Up to date"** (green).
- **Read-only:** there is no install, download, "get update" link or release-notes action. "View in App Store" opens an App Store *search* for the app name, not its product page.
- Runs on every visit (`.task`), one app at a time, over the network. A failed feed is swallowed and the row falls through to **"Up to date"** (green).
- **Real data available:** name, version, App Store flag, Sparkle feed URL, latest version from the appcast. No release date, no release notes, no size.

### 2.6 Space Lens

**Files:** `App/Features/SpaceLens/SpaceLensView.swift` (324), `SpaceLensViewModel.swift` (337), `TreemapCanvasView.swift` (48). Title: **"Space Lens"**. Hue `#8B5CF6` (idle icon + active sidebar tile only).

**Purpose:** Visualise disk usage as a treemap, drill down, and move chosen items to the Trash.

```swift
enum Phase { case idle, scanning, loaded, reviewing, cleaning, done(reclaimedBytes: Int64) }
enum ViewMode: String { case tree = "By Folder", category = "By Type" }
```

| Phase | What is shown | Controls |
|---|---|---|
| `.idle` | Custom source picker (not `EmptyStateView`): icon `square.grid.3x3.fill` (34 pt), **"Map your storage"**, "Choose the part of your Mac you want to explore. Nothing is removed without your review." Optional **"External Volumes"** list. | **Scan Home Folder** (prominent) · **Choose Folder…** (bordered → `NSOpenPanel` titled "Choose a folder to map") · one bordered button per removable volume |
| `.scanning` | Large spinner + `ScanProgressPanel` in **count-only** mode ("Scanned 1.694.000 items…" — no bar, the total is unknown). Header subtitle: "Scanning «root name»…". | **Cancel** (bordered) |
| `.loaded` (also `.reviewing`, `.cleaning`) | Top to bottom: breadcrumb (one plain button per ancestor, last one bold, `chevron.right` separators) → segmented **"By Folder" / "By Type"** picker → **treemap canvas** (radius 12) with an optional **Inspector** column (230–290 pt) on the right → sticky footer **"Cleanup selection"** "N items · «size»" when the cart is not empty. | Breadcrumb (zoom out) · picker · tap a rectangle (select) · inspector: close (`xmark`), **Open Folder** (drills *into* the folder), **Add to Cleanup** / **Remove from Cleanup** (prominent) or the reason it is not allowed |
| `.reviewing` | Modal **sheet** (min 520 × 420, default window chrome): **"Review Cleanup"**, "These items will be moved to Trash and can be recovered from Finder until Trash is emptied.", a plain `List` of rows (name, path, size — **no checkboxes**), a **"Total"** row. | **Cancel** · **Move to Trash** (prominent, red) |
| `.cleaning` | The sheet closes and the map is shown again with the footer button disabled; **no progress indicator**. | — |
| `.done` | `SummaryCardView`: "«size»" + **"moved to Trash"**. | **Scan Again** (prominent) → rescans the same root |

- **Treemap rendering:** a `Canvas` that draws one rectangle per child of the current folder. Fill colour = **hash of the label → HSB (hue 0–360, saturation 0.55, brightness 0.75)**, i.e. a full rainbow unrelated to `Theme`; 1 pt black 20 % stroke; the name in white `.caption2` when the rectangle is larger than 44 × 16 pt. **No hover, no selection highlight** (the selected item is not marked in the map), no legend, no size labels, no zoom gesture.
- **"By Type":** eight categories — Documents, Images, Video, Audio, Code, Archives, Applications, Other. Tapping a category deselects (no inspector).
- **Inspector rows:** Size · Kind ("Folder"/"File") · Contains "«n» items" (folders) · Modified (date + time) · full path (monospaced, selectable, 3 lines).
- **Ineligibility copy (shown instead of a button):** "The scanned location itself can’t be removed." · "This item is outside the scanned location." · "This is a protected system location." · "You don’t have permission to move this item to Trash."
- The cart keeps only the top-most selected item (selecting a folder drops its descendants from the count). Nothing is auto-selected.
- Errors: "Couldn't read «root»" returns to `.idle`; after cleaning, "N items couldn't be moved to Trash: «reason»" appears on the done screen. Always a bare red line at the bottom.
- **Real data available:** label, full path, size, kind, descendant count, modification date per rectangle; per-category totals.

### 2.7 Duplicate Finder

**Files:** `App/Features/Duplicates/DuplicateFinderView.swift` (282), `DuplicateFinderViewModel.swift` (146). Title: **"Duplicate Finder"**. Hue `#D9578A` (empty-state icon only).

**Purpose:** Find exact duplicate files or visually similar images in the home folder and trash the selected copies.

```swift
enum Mode: String { case exact = "Exact Duplicates", similarImages = "Similar Images" }
enum Phase { case idle, scanning, results, done(reclaimedBytes: Int64) }   // no .cleaning
```

| Phase | What is shown | Controls |
|---|---|---|
| all | A segmented **"Mode"** picker pinned at the top: **Exact Duplicates / Similar Images**. In Similar Images mode a one-line amber warning with `exclamationmark.triangle`: "Similar images are near-matches, not byte-identical copies — review carefully before deleting." | Picker (disabled while scanning) |
| `.idle` | `EmptyStateView`: `doc.on.doc`, **"Find Duplicates"**, "Scans for exact duplicate files, or visually similar images." | **Start Scan** (large, prominent) |
| `.scanning` | `ScanProgressPanel` (max 420 pt): two step rows — **"Scanning exact duplicates…"** → **"Hashing files…"** (or "Scanning similar images…" → "Comparing images…"), a bar + % only once hashing starts, and the current file path (monospaced, middle-truncated). | **Cancel** |
| `.results` | Header **"Duplicate Finder"** + "«N» duplicate sets found"; optional note "«n» files couldn't be scanned and may be missing from these results."; "No duplicates found." when empty. One **card per duplicate set**: title = file name of the copy to keep (16 pt semibold) · "«n» copies · «size» each" · badge "Exact match" (neutral) / "Similar images" (amber). Rows separated by hairlines: checkbox · file name · full path (monospaced) · **"Keep"** green badge · size. Pinned `StickyFooterView`: **"Selected for cleanup"** + size. | Checkboxes (**disabled for the "Keep" copy**) · **New Scan** (bordered) · **Clean** (prominent, red; disabled when nothing is selected) |
| `.done` | `SummaryCardView`: "«size»" + **"reclaimed"** (max 420 pt). | **New Scan** (prominent) · **Back to Results** (bordered) |

- **Scope is fixed:** the whole home directory, in both modes. There is no location picker.
- **Pre-selection:** every copy except the **newest by modification date** in each set — in *both* modes, including near-identical images.
- **No thumbnails** (also for Similar Images), no preview / Quick Look, no "Reveal in Finder", no per-set "select all / none", no search or filter.
- **Real data available:** path, size, last-modified date per file; the set's recommended keep path; skipped-file count. No image dimensions, no similarity score, no folder grouping.

### 2.8 Performance

**Files:** `App/Features/Performance/PerformanceView.swift` (357), `PerformanceViewModel.swift` (132). Title: **"Performance"**. **No Phase enum** — one long scrolling page fed by a 2-second poll. The module hue `#D9A21B` is **not used anywhere on this screen** (only in the sidebar).

**Purpose:** Live system metrics plus maintenance actions (free RAM, flush DNS), the menu-bar widget launcher and the login-item toggle.

Layout top to bottom (32 pt outer padding, 32 pt between sections, each section has an uppercase 12.5 pt muted label):

| Section | Contents |
|---|---|
| Header | **"Performance"** (24 pt) + "Live system metrics, updated every couple of seconds." |
| **LIVE METRICS** | 2 × 2 adaptive grid (≥ 200 pt columns) of cards: **CPU** ("«n»%" + blue bar) · **Memory** ("«n»%" + **always-amber** bar + "«used» / «total»") · **Thermal State** (badge **Normal** green / **Elevated** amber / **Serious** red / **Critical** red, plus the raw word "Nominal"/"Fair"/… in muted text) · **Load Average** ("«x.xx»" + "1m a · 5m b · 15m c"). Unavailable values render as "—" over an empty bar. |
| **SYSTEM** | One card with hairline-divided rows: Swap "«used» / «total»" · Architecture "Apple Silicon"/"Intel" · Uptime Since "«date, time»". |
| **MAINTENANCE** | One card with two rows, each a 36 pt accent-tinted icon tile + title + description + **Run** (bordered): **Free up RAM** ("Clears inactive memory held by idle apps and background caches.") with `memorychip` · **Flush DNS Cache** ("Resolves slow or broken site loads caused by stale DNS records.") with `network`. Tooltip text names the underlying command ("Runs the root-only `purge` command via the privileged helper."). |
| **MENU BAR WIDGET** | Card: "Live CPU/RAM readout in the menu bar" · "Auto-launch at login isn't wired yet — open manually for now." · **Open Menu Bar Widget** (prominent). |
| **LOGIN ITEMS** | Card: switch **"Launch SOS Mac at Login"**; below a divider, **"Installed Launch Agents"** with one label + path per plist file (read-only). |

- **Messages** (`"<Action> completed."`, helper-install instructions, errors) appear as plain 14 pt text **at the very bottom of the page**, far from the button that produced them.
- **Run** has no busy/disabled state. First use installs the privileged helper and opens System Settings → Login Items for approval ("Privileged helper installed — approve it in System Settings > General > Login Items, then try again.").
- **Real data available:** CPU %, memory (free/active/inactive/wired/compressed/total), swap, thermal state (4 levels), load averages (1/5/15 min), boot time, architecture, login agents, login-item status. **Not available:** temperatures, fans, GPU, disk I/O, network throughput, per-process anything.
- **Data-definition note:** "Memory «n»%" is `total − free`, so inactive (reclaimable) pages count as used — an idle Mac shows ~99 % in amber.

### 2.9 Cloud Cleanup

**Files:** `App/Features/CloudCleanup/CloudCleanupView.swift` (279), `CloudCleanupViewModel.swift` (175), `ASWebAuthSessionPresenter.swift` (52). Title: **"Cloud Cleanup"**. Hue `#3A9CE0` (empty-state icons only). **No Phase enum** — per-provider structs with Booleans (`isAuthenticated`, `isLoading`, `scanProgress`, `files`, `duplicateGroups`, `errorMessage`), plus a view-local tab.

**Purpose:** Find duplicate files in Google Drive / Dropbox / OneDrive (by API) and in iCloud Drive (local scan) and remove the extra copies.

Top: segmented **Provider** picker — **Google Drive · Dropbox · OneDrive · iCloud Drive**. Three tabs share one layout; iCloud Drive is visually different on purpose.

**Google Drive / Dropbox / OneDrive (API providers)**

| State | What is shown | Controls |
|---|---|---|
| all | Caption (12 pt muted): "Connects over the real «Provider» API — file list and delete actions happen on the server, not just locally." Provider tile (`.careCard()`): 40 pt tile in the **brand colour** with a letter-badge symbol (`g.circle.fill` `#1A9349`, `d.circle.fill` `#0061FE`, `o.circle.fill` `#094AB2`) · provider name · badge **"Connected"** (green) / **"Disconnected"** (**red**). | **Connect** (prominent) or **Refresh** + **Disconnect** (bordered) |
| not connected | `EmptyStateView`: `link`, **"Connect «Provider»"**, "Sign in to scan for duplicates and free up space." — **no button** (Connect is in the tile). | — |
| loading | Spinner + `ScanProgressPanel` count-only ("«n» files listed…") or "Loading…". No cancel. | — |
| no duplicates | `EmptyStateView`: `checkmark.circle`, **"No duplicates found"**, "«Provider» is clean — no duplicate files were found in your account." | — |
| results | Default `List` with a `Section` per set titled **"«n» copies"**; rows: file name · **"Keep"** green badge · size · **Delete** (destructive role; disabled for the keep copy). `StickyFooterView` **"Potential savings"** + size, **with an empty trailing slot (no button)**. | **Delete** per file — fires immediately, one file per tap |

**iCloud Drive (local scan of `~/Library/Mobile Documents`)**

| State | What is shown | Controls |
|---|---|---|
| all | Orange banner (system `.orange`, `.caption`): `internaldrive` + **"Local Scan — reads files already synced to this Mac. Not a live iCloud API call (Apple provides none)."** | — |
| loading | `ProgressView("Scanning…")` | — |
| empty | `EmptyStateView`: `icloud`, **"iCloud Drive"**, "Scan locally-synced iCloud Drive files for exact duplicates." | **Scan** (large, prominent) |
| results | Same `List`/`Section` shape as above; the button is **Trash** (destructive role). Footer "Potential savings". | **Trash** per file — fires immediately |

- **What works today:** only the iCloud Drive tab. The OAuth apps are not registered (`CloudCleanupConfig.placeholder`), so **Connect** on the other three tabs always ends in the red line "This provider isn't configured yet — needs a registered OAuth app's client ID and redirect URI."
- Connection state is not restored from the Keychain on launch — a previously connected provider shows "Disconnected" until Connect is pressed again.
- **Delete is not Trash:** Drive → provider trash (`trashed: true`), OneDrive → recycle bin (Graph `DELETE`), Dropbox → `files/delete_v2`. None go to the local Trash and the app offers **no undo and no confirmation**. iCloud uses the local Trash.
- **Real data available (cloud):** name, size, provider content hash, modified date, folder flag. The UI shows name and size only (no folder path, no date).

### 2.10 Protection

**Files:** `App/Features/Protection/ProtectionView.swift` (232), `ProtectionViewModel.swift` (176). Title: **"Protection"**. Hue `#5566E0` (empty-state icon only).

**Purpose:** Scan fixed locations for known-bad signatures and quarantine findings (restorable).

```swift
enum Phase { case idle, scanning, results, quarantining, summary(quarantinedCount: Int, failureCount: Int) }
```

A disclaimer line sits at the top in **every** phase (12 pt muted, `info.circle`, no background): "Signature-based scanning only — complements XProtect/Gatekeeper, does not replace them. Real-time protection is not part of this release."

| Phase | What is shown | Controls |
|---|---|---|
| `.idle` | `EmptyStateView`: `shield.lefthalf.filled`, **"Scan for known threats"**, "Checks Downloads, login items, and browser extensions against known-bad signatures. Complements — never replaces — XProtect and Gatekeeper." Below it the quarantine list (if any). | **Start Scan** (large, prominent) · **Restore** (plain accent link) per quarantined file |
| `.scanning` | Large spinner + `ScanProgressPanel` (max 480 pt): ticker **"«n» files scanned"**, real bar + %, ETA ("~«n» minutes remaining" / "Less than a minute remaining"), current file path (monospaced). "Counting files…" before the first tick. | **Cancel** |
| `.results` / `.quarantining` | Plain `List`: "No threats found." or one row per finding — checkbox · file name · red badge **"Known signature"** / **"Pattern match"** · optional VirusTotal badge ("VT: «malicious»/«engines»" red / "VT: clean" green) · size · **Check VirusTotal** (plain accent link, hash detections only). Pinned `StickyFooterView`: **"Selected"** + count. | Checkboxes (nothing pre-selected) · **Quarantine Selected** (prominent, red) |
| `.summary` | `SummaryCardView` with a **count** instead of bytes: "3" + "items quarantined"; red line "«n» items couldn't be quarantined." when relevant. Quarantine list below. | **New Scan** (prominent) |

- **Quarantine list:** "Quarantined («n»)" + rows (file name + **Restore**). It is rendered **outside any scroll view**, so a long list would overflow. No date, no threat identifier, no "reveal in Finder", no "delete permanently".
- **Scan scope is fixed** (6 locations: Downloads, User Login Items, System Login Items, System Daemons, Chrome Extensions, Firefox Extensions). No Quick/Deep choice, no real-time toggle, no "last scan", no database version.
- **Effectively a demo today:** the bundled signature database holds **one hash (the EICAR test file) and no YARA rules**; VirusTotal has no API key, so **Check VirusTotal** silently does nothing.
- **Quarantine is a move, not a Trash:** files go to `~/Library/Application Support/<bundle id>/Quarantine/<UUID>/` and are restorable (recorded in SwiftData).
- **Real data available:** path, size, detection method (hash / YARA), matched identifier, detected-at date. The UI shows only the file name, method, size.

---

## 3. Current design system ("Aurora Care")

Source: `App/DesignSystem/` (16 files, ~880 lines). It was transcribed from the Open Design project `macos-care-suite` (`styles.css`). That project is **not present in the local Open Design daemon any more** (26 projects listed, none named `macos-care-suite`), so the screenshots in §6 are the only visual baseline besides the code.

### 3.1 Colour tokens (`Theme.swift`)

| Token | Light | Dark | Notes |
|---|---|---|---|
| `background` | `#FAFAFA` | `#17171A` | Screen background |
| `surface` | `#FFFFFF` | `#212126` | Cards, rows, step rows |
| `foreground` | `#111111` | `#F4F4F6` | Primary text |
| `muted` | `#6B6B6B` | `#9C9CA6` | Secondary text, captions, section labels |
| `border` | `#E5E5E5` | `#33333B` | Hairlines, progress track, dividers |
| `accent` | `#2F6FEB` | `#2F6FEB` | Primary buttons, active sidebar wash, generic icon tints. **Not dynamic.** |
| `accent2` | `#17B3B3` | `#17B3B3` | Gradient partner only (never a standalone fill) |
| `success` | `#17A34A` | `#17A34A` | "safe" badges, done steps, summary card |
| `warn` | `#EAB308` | `#EAB308` | "attention" badges, Memory bar |
| `danger` | `#DC2626` | `#DC2626` | "risk" badges, destructive buttons, error text |
| `accentGradient` | 135° `accent → accent2` | same | Default progress fill, active step dot, Health dial |

Neutral tokens switch with the appearance via a dynamic `NSColor`; the semantic colours and all module hues are the same in light and dark.

**Module hue map (`Theme.ModuleHue`)** — one per module, no red:

| Module | Hex | Module | Hex |
|---|---|---|---|
| Dashboard | `#2F6FEB` | Duplicate Finder | `#D9578A` |
| Smart Care | `#7C5CF5` | Performance | `#D9A21B` |
| Junk & Cache | `#17B3B3` | Cloud Cleanup | `#3A9CE0` |
| Uninstaller | `#EF8B3C` | Protection | `#5566E0` |
| Updater | `#2BA55F` | Settings *(unused)* | `#7A7A82` |
| Space Lens | `#8B5CF6` | | |

**Where the hue actually shows:** sidebar icon tile (every module), Dashboard module cards, Uninstaller app tiles, and the empty-state icon on Smart Care / Junk / Updater / Duplicates / Cloud / Protection. **Performance never uses its hue in content**, and the active sidebar row is highlighted in generic accent blue rather than the module hue.

**Hue/opacity recipes in use:** sidebar tile wash 14 % · module card top wash 12 % (70 pt tall) + tile shadow 40 %/r6/y3 · hero panel background hue 8 % → surface, border hue 28 % · empty-state orb hue 18 % → 8 %, radius 34, shadow 14 %/r24 · active sidebar tile shadow 50 %/r5/y2 · active sidebar row accent 12 % wash + 22 % border · active step row border accent 45 % · progress fill glow accent 30 %/r5 · summary card success 10 % → surface, border success 32 %, circle gradient success → accent-2 70 %.

**Colours outside the token set:** treemap rainbow (HSB, saturation 0.55, brightness 0.75 — `TreemapCanvasView.swift:42-47`), system `.orange` + `Color.orange.opacity(0.1)` for the iCloud banner (`CloudCleanupView.swift:209-217`), three provider brand hexes inline (`CloudCleanupView.swift:154-156`), black 20 % treemap strokes.

### 3.2 Aurora bloom (`.auroraBloom()`)

Two blurred radial circles behind every content area, aligned top-trailing, non-interactive: `accent` 520 × 520 offset (160, −220) and `accent2` 440 × 440 offset (40, −120), blur 20, opacity **0.1 light / 0.22 dark**. It is applied once on all 10 screens and uses the generic accent, not the module hue.

### 3.3 Geometry tokens

| Scale | Values (pt) |
|---|---|
| `Theme.Spacing` | `xs` 4 · `sm` 8 · `md` 12 · `lg` 16 · `xl` 20 · `xxl` 24 · `xxxl` 32 · `huge` 48 · `giant` 80 |
| `Theme.Radius` | `sm` 8 · `md` 12 · `lg` 16 · `xl` 28 (hero panel and summary card only) · `pill` 9999 *(unused)* |
| Used in practice | screen padding 32 (28 uses of `xxxl` in padding); `giant` 80 for scanning states; off-scale radii: 7 (sidebar/app tiles), 34 (empty-state orb) |

### 3.4 Typography

System font only (SF), fixed sizes via `.font(.system(size:))` — no Dynamic Type, no custom font.

| Token | Size | Used? |
|---|---|---|
| `TextSize.xs` | 12 | 11 uses |
| `TextSize.sm` | 14 | 56 uses — the workhorse body size |
| `TextSize.base` | 16 | 8 uses |
| `TextSize.lg` | 20 | 4 uses |
| `TextSize.xl` | 24 | 12 uses (screen headers, metric numbers) |
| `TextSize.xxl` | 32 | 1 use (hero title) |
| `TextSize.xxxl` | 48 | **0 uses** |

- **47 font calls bypass the tokens** with raw sizes: 10, 10.5, 11, 11.5, 12, **12.5** (20 uses — the de-facto secondary size, between two tokens), 13, 13.5, 16, 20, 26, 32, 34, 46, 52.
- Weights: `.semibold` 38, `.bold` 13, `.medium` 7, `.heavy` 2 (dial score, summary number), `.light` 1 (empty-state icon).
- Eyebrow style: uppercase 10–11 pt bold/semibold with +0.4…+1.2 letter-spacing in the hue or muted colour ("SYSTEM STATUS", "MODULES", "LIVE METRICS", "ESSENTIAL TRIO").
- Numbers use `.monospacedDigit()`; paths and versions use `.monospaced`/`design: .monospaced`.
- Hierarchy today: screen header 24 semibold → card title 16 semibold → body 14 → secondary 12.5 → caption 12 → eyebrow 10.5.

### 3.5 Elevation (two-layer shadows, via `.elevation(_:)`)

| Level | Light (near / far) | Dark (near / far) | Used by |
|---|---|---|---|
| `raised` | fg 6 % r1 y1 / fg 8 % r14 y10 | black 50 % r1 y1 / black 42 % r16 y12 | `.careCard()`, `ModuleCardView`, `StepRowView`, Uninstaller rows, Space Lens inspector |
| `float` | fg 8 % r2 y2 / fg 12 % r22 y18 | black 55 % r3 y2 / black 50 % r26 y22 | `HeroPanelView`, `SummaryCardView` |

Cards also keep a 1 pt `border` stroke under the shadow.

### 3.6 Shared components

| Component (`App/DesignSystem/…`) | Anatomy | Used by |
|---|---|---|
| `HeroPanelView` (97) | Hue-tinted panel r28, float elevation, 32 pt padding. Left: eyebrow (hue, 10.5 bold) · title (32 bold) · subtitle (14 muted, ≤ 420 pt) · optional badge row · primary button (large) + optional secondary (large). Right of a 1 pt divider: any trailing view. | Dashboard only |
| `HealthDialView` (36) | 176 pt ring, 12 pt stroke, success → accent-2 gradient + glow, centered score (46 heavy) + label. | **Nobody** (built, never used; so are `ProgressBarView.successStyle`, `Theme.Radius.pill` and `Theme.TextSize.xxxl`) |
| `ModuleCardView` (61) | Button-card r16: 38 pt gradient hue tile + white symbol · title 13 · subtitle 12.5 · stat 20 semibold · badge; 12 % hue wash on top; raised. | Dashboard (8 cards) |
| `EmptyStateView` (43) | 108 pt hue orb (r34) + 32 pt light symbol · title 20 semibold · message 14 muted (≤ 360 pt, centred) · optional large primary button. Fills the screen, 80 pt padding. | Smart Care, Junk, Uninstaller, Updater, Duplicates, Cloud (×3), Protection |
| `SummaryCardView` (58) | 64 pt success-gradient circle + white check · big number **52 heavy in success green** · caption 14 muted · optional breakdown row (num 20 bold + label 11.5) — **the breakdown is never passed**. r28, success 10 % wash, float. | Smart Care, Junk, Space Lens, Uninstaller, Duplicates, Protection |
| `StickyFooterView` (34) | Full-width bar on `.regularMaterial`, top hairline, bottom corners r16: label 12.5 muted · value 20 semibold · trailing slot (usually the main button). | Smart Care, Junk, Uninstaller, Space Lens, Duplicates, Cloud (×2), Protection |
| `BadgeView` (34) | 6 pt dot + text 11.5 semibold in the style colour, on a 12 %-tinted capsule (h9/v3 padding). Styles: `safe` green · `attention` amber · `risk` red · `neutral` grey · `accent` blue. | 17 direct uses in 8 screens + HeroPanel/ModuleCard |
| `ProgressBarView` (26) | 8 pt capsule track (`border`) + fill (`accentGradient` by default, `successStyle` available, or a flat colour) with a 30 % accent glow. Callers override height to 10 (Dashboard) or 4 (sidebar). | ScanProgressPanel, Dashboard, Performance (×4), sidebar footer |
| `ScanProgressPanel` (120) | Vertical stack: optional ticker (16 semibold) → determinate bar + "N %" (when a total is known) **or** a count-only line → optional ETA (12 muted) → optional `StepRowView` list → optional current path (11.5 monospaced, middle-truncated). | Junk, Smart Care, Duplicates, Space Lens, Cloud, Uninstaller, Updater, Protection |
| `ScanProgressTracker` (70) | Not a view: holds the latest `ScanProgress`, a generation token, and a linear ETA (needs ≥ 20 items and a known total). | Junk, Duplicates, Space Lens, Uninstaller, Updater, Protection VMs |
| `StepRowView` (71) | Row card r12, raised: 20 pt ring — pending (border ring on background) / active (accent ring + pulsing gradient dot, accent 45 % border) / done (success-gradient disc + white check) — name 14 medium · trailing meta 12.5 monospaced digits. | `ScanProgressPanel`, Smart Care (direct), Updater (direct) |
| `SidebarNavRow` + `SidebarSectionLabel` + `StorageGaugeMiniView` (70) | See §1.3. Section label: 11 pt semibold uppercase, +0.4 spacing, muted. | Sidebar |
| `.careCard()` (23) | 20 pt padding, `surface`, r16, 1 pt border, raised. | Performance (9), Smart Care (2), Cloud, Duplicates, Updater |
| `.elevation(.raised / .float)` (21) | Applies the two-layer shadow. | all of the above + Uninstaller rows, Space Lens inspector |
| `.auroraBloom()` (35) | See §3.2. | all 10 screens |

### 3.7 Controls, icons and motion

- **Controls are stock macOS SwiftUI/AppKit controls:** `.bordered` (18) and `.borderedProminent` (19) buttons — tinted `Theme.accent` (18) or `Theme.danger` (5); `.plain` buttons (7 uses: "Ignore", "Restore", "Check VirusTotal", breadcrumbs, the inspector's close button, sidebar rows, module cards). `controlSize(.large)` on only 7 buttons (HeroPanel primary + secondary, the EmptyState CTA, Smart Care's "Clean Selected" and "New Scan", Uninstaller's "Done", Space Lens's scanning "Cancel"); every other button — including the same "New Scan" on Duplicates and Protection and every other Cancel — is the default regular size.
- Checkbox toggles (5 screens), one switch (Launch at Login), three segmented pickers (Duplicate Finder mode, Space Lens view mode, Cloud provider), plain `List`s, one modal sheet (Space Lens review), `NSOpenPanel`, `ASWebAuthenticationSession` for OAuth.
- **Iconography: SF Symbols only.** Per module: `sparkles`, `wand.and.stars`, `trash`, `xmark.bin`, `arrow.triangle.2.circlepath`, `square.grid.3x3.fill`, `doc.on.doc`, `gauge.with.dots.needle.50percent`, `icloud`, `shield.lefthalf.filled`. In rows: `checkmark`, `xmark`, `chevron.right`, `info.circle`, `exclamationmark.triangle`, `link`, `checkmark.circle`, `internaldrive`, `memorychip`, `network`, and letter badges `g/d/o.circle.fill` for cloud providers. The asset catalog holds only the app icon (no custom images, no colour sets).
- **Motion:** exactly one custom animation — the pulsing dot in `StepRowView` (1.1 s ease-in-out, repeating). Phase changes swap views with no transition; scans use `ProgressView` spinners. No haptics, no skeleton loaders, no hover states.

---

## 4. Constraints the redesign must respect

### 4.1 No fake numbers — design only what has a data source

Project rule (`CLAUDE.md` "Fail-closed, never guess", `AGENTS.md` "Safety & Architecture Rules"): every number on screen must come from a real API. If a mock-up element has no backing data it is omitted, not filled with a placeholder. **If the new design needs a value that is not in the "has" column, flag it as "needs engine work" instead of mocking it.**

| Screen | Has (real, today) | Does not have (must not be invented) |
|---|---|---|
| Dashboard | Storage used/total/free; one-off CPU load, memory, thermal state | Health score / dial, "last scan", issues count, history, activity feed, per-module status (results are not shared across screens) |
| Smart Care | Per-module status + found counts; aggregate progress; health snapshot (load, memory, thermal); per-item path/size/severity; reclaimed bytes, item and failure counts | Pre-scan reclaim estimate, schedule/automation, before/after health |
| Junk & Cache | Per-rule progress; per-file name/path/size/severity/source rule/needs-helper; total selected bytes | "Last scan", category checkboxes, per-folder totals (engine returns files only) |
| Uninstaller | App name, bundle ID, version, path, App Store flag; associated paths + sizes; reclaimed bytes | Real app icon (available in the App target via `NSWorkspace`, just not used here), last-used date, ratings, "leftover" confidence, running state; **correct sizes for associated folders (bug, §5)** |
| Updater | Installed version, latest version from the Sparkle feed, App Store flag, has-feed flag | Release date/notes, update size, install action, "checking failed" state (swallowed today) |
| Space Lens | Name, path, size, kind, descendant count, modified date per rectangle; per-type totals; scanned item count; eligibility + reason | Total file count before the scan (no percentage), Finder reveal, search, preview |
| Duplicate Finder | Two-phase progress; per-set copies, per-file path/size/modified; keep recommendation; skipped count; reclaimed bytes | Thumbnails / image dimensions, similarity score, a per-set reclaimable total (derivable from the sizes; the UI shows only the grand total), location scope |
| Performance | CPU %, memory breakdown, swap, thermal level, load averages, uptime, architecture, login agents, login-item status | Temperature, fans, GPU, disk I/O, network, processes, per-app login items |
| Cloud Cleanup | Provider name, connection state, file name/size/hash/modified date, duplicate groups, keep recommendation, files-listed count | Quota / used space, folder tree, OAuth app configuration (not registered), persisted connection on relaunch |
| Protection | Per-file progress + ETA, path, size, detection method + identifier, date; quarantined records (original path, date) | Quick/Deep scan, real-time toggle, last scan, database version/coverage (DB holds one hash), VirusTotal (no key) |
| Menu bar helper | CPU %, memory used/total | Anything else |

Derived values that are legitimate: byte sizes (`ByteCountFormatter`, `.file` style), counts, a percentage **only when a total is known**, and an ETA **only when a total is known and ≥ 20 items are done**.

### 4.2 Safety semantics the UI must keep

| Rule | What it means for the design |
|---|---|
| **Trash only.** Every local removal goes through `Cleaner.clean` → `FileManager.trashItem`. | Copy says "Move to Trash" / "Trash"; never "Delete permanently", never an "Empty Trash" action. iCloud files also go to the local Trash. |
| **Cloud deletes are server-side.** Drive → provider trash, OneDrive → recycle bin, Dropbox → provider delete. | Do not label them like local Trash; today there is no confirmation and no undo (see §5) — a confirm step is the obvious fix. |
| **Review before removal.** Nothing is removed without a visible list of what will go. | Keep a review state on every cleaning flow. |
| **Recommended keep is protected.** The newest copy in a duplicate group (by *modified* date) must keep a disabled control + "Keep" badge. | Applies to Duplicate Finder and Cloud groups (Smart Care currently misses it — §5). |
| **Pre-selection is narrow.** Today: junk items that are `safe` and need no helper; duplicates other than the keep copy. Never selected: `caution`/`risky` junk, helper items, Space Lens items, Protection findings. | Do not widen pre-selection. Narrowing it is a product decision for Phương. |
| **Quarantine is reversible.** Protection moves files to an app-managed folder with a persisted record. | Keep a visible Quarantine list with Restore. |
| **Ineligible Space Lens items explain themselves** and offer no action. | Keep the reason copy. |
| **Privileged actions have an approval flow.** First "Free up RAM" / "Flush DNS" installs the helper and opens System Settings. | Needs an explanatory state, not an error look. |

### 4.3 Technical constraints

- **macOS 14+**, SwiftUI with stock AppKit controls, **Swift 6 strict concurrency**. Each screen is a `@MainActor @Observable` view model with a `Phase` enum and a view that switches on it.
- **UI is composed from `App/DesignSystem`.** The most useful deliverable is therefore (a) a token set — colours light + dark, spacing, radii, type scale, elevation, motion — and (b) components with their states, which can be transcribed 1:1 into `Theme.swift` + component files.
- **Every Phase in §2 needs a design**, including scanning, empty, error, disabled and "nothing selected" states. States marked "not captured" in §6 have no screenshot.
- **List scale:** junk results can be 100 k+ file rows; duplicates and Space Lens can be large too. Prefer grouped/aggregate presentations and assume virtualised lists — no per-row blur/shadow effects.
- **Icons are SF Symbols only** (no custom illustration pipeline today). The asset catalog has just the app icon.
- **New capabilities need engine work in `CleanCore` first**, for example: per-folder junk totals, persisted scan history, health scoring, thumbnails for duplicates, real-time protection, cloud quota. Menu-bar-widget auto-launch, Settings, onboarding and paywall do not exist and are Phase 9 scope.
- **The request's direction** — CleanMyMac-inspired UI/UX with a dreamy purple + neon palette — replaces the blue accent. Today `Theme.accent` is also the colour of the active sidebar row, the generic icon tint and most buttons, so the swap is mostly token-level; system controls take their tint from `.tint(...)`.

### 4.4 Intentionally omitted today (do not reintroduce as decoration)

Health dial / health score on the Dashboard · recent-activity feed · "last scanned" stamps on any screen · junk category checklist · Uninstaller bulk table with size/last-used columns · Updater "Update All" · Duplicate Finder location pills · Protection scan-type chooser and real-time toggle · Cloud quota bars and folder browser · Performance disk/network sparklines and process/login-item tables · Settings screen · onboarding and paywall.

---

## 5. UX pain points and inconsistencies

Honest findings from reading the code and looking at the screenshots. "Where" points at the code that produces the behaviour.

### 5.1 Safety and trust (highest impact)

| # | Finding | Where |
|---|---|---|
| S1 | **No confirmation step anywhere.** There is no `.confirmationDialog`, `.alert` or `NSAlert` in the app; the review list is the only checkpoint before "Clean". The Aurora Care spec asks for one shared destructive-confirm dialog — it was never built. | grep over `App/`; `openspec/changes/adopt-aurora-care-design-system/specs/shared-ui-components/spec.md` |
| S2 | **Cloud rows delete on a single tap.** "Delete" / "Trash" on each file row fires immediately: no selection, no review, no confirm, no undo. | `CloudCleanupView.swift:179-182`, `:246-249` |
| S3 | **Similar Images pre-selects every non-keep copy** and "Clean" is one tap away, with no thumbnails to judge near-matches. | `DuplicateFinderViewModel.swift:88-97` |
| S4 | **Smart Care does not protect the keep copy.** Duplicate rows are flattened, the newest copy is not marked, and its checkbox stays enabled. | `SmartCareView.swift:177-196`, `SmartCareViewModel.swift:201-212` |
| S5 | **Duplicate Finder has no `.cleaning` phase:** "Clean" stays enabled while files are being trashed and `clean()` has no re-entrancy guard. Items that fail are never reported. | `DuplicateFinderViewModel.swift:109-127`, `DuplicateFinderView.swift:144-149` |
| S6 | **After an iCloud "Trash" the list does not change** (groups are not recomputed) and nothing confirms the action. Cloud `result.failed` is ignored on all providers. | `CloudCleanupViewModel.swift:121-130`, `:150-158` |
| S7 | **"Needs Helper" items** look like a label, but cleaning them triggers helper installation and a System Settings approval with no upfront explanation. The badge text is also outdated (the helper exists). | `JunkCleanerView.swift:114-116`, `JunkCleanerViewModel.swift:101-111` |
| S8 | **No running-app check** before uninstalling; App Store apps get only an informational badge. | `App/Features/Uninstaller/*` (no `NSRunningApplication` use) |

### 5.2 Data accuracy shown in the UI

| # | Finding | Where |
|---|---|---|
| D1 | **Uninstaller sizes for associated folders are wrong:** `attributesOfItem(.size)` of a directory is a few bytes, not its content — so "N items · «size»", "reclaimable if all removed" and the removed summary understate. Only the `.app` bundle size is computed recursively. | `Packages/CleanCore/Sources/CleanCore/Uninstaller/BundleAssociatedFilesFinder.swift:30-40` |
| D2 | **"Memory 99 %" on an idle Mac** — used = total − free counts reclaimable inactive pages, and the bar is always amber, so it reads as a warning. | `Packages/CleanCore/Sources/CleanCore/Performance/MachHostStats.swift:26-28`, `PerformanceView.swift:110-123` |
| D3 | **A failed update check shows "Up to date" in green** (feed errors are swallowed and fall through to the last branch). The header can say "1 update available" while the check is still running. | `UpdaterViewModel.swift:66-69`, `UpdaterView.swift:96-102`, `:149-165` |
| D4 | **Protection is a demo** but the UI presents it like a real scanner: one signature in the database, no YARA rules, no scope or coverage information, and a "Check VirusTotal" button that silently does nothing without an API key. | `Packages/CleanCore/Sources/CleanCore/Protection/SignatureDatabase.swift:40-44`, `ProtectionViewModel.swift:149-152` |
| D5 | **Three of four Cloud tabs can never connect** (OAuth apps not registered), yet they are presented as full-featured peers of the only working tab (iCloud); connection state is not restored on relaunch. | `CloudCleanupViewModel.swift:9-15`, `:43-48` |
| D6 | **Dashboard cards are placeholders** — 7 of 8 say "Not … this session"; the Dashboard never reflects what other screens found. | `DashboardView.swift:77-123` |

### 5.3 Navigation, state and feedback

| # | Finding | Where |
|---|---|---|
| N1 | **Leaving a screen throws away everything** (results, selections, inspected sizes) and cancels running scans; returning starts from zero. | `@State private var viewModel` in every feature view; §1.4 |
| N2 | **Default window is too small for the layout:** ≈ 900 × 532 pt, hero title wraps to three lines, the module grid shows 1½ rows, Updater shows 4 apps, and the sidebar needs scrolling with "Protection" hidden behind the footer. | `SOSMacApp.swift:63`, `:88`; screenshots |
| N3 | **"Run Smart Care" on the Dashboard only navigates**; it does not run anything. | `DashboardView.swift:37-38` |
| N4 | **Errors are a bare red line at the bottom** with no retry or dismiss, often far from the cause (Performance puts it at the end of a long page). Some errors never render: a failed **Inspect** in the Uninstaller's browsing state is invisible. | `PerformanceView.swift:28-37`, `JunkCleanerView.swift:71-76`, `UninstallerView.swift:37-61` vs `:182-188` |
| N5 | **No busy feedback while cleaning:** `.cleaning` / `.quarantining` show the same list with a disabled button — no spinner or progress. "Run" (Performance) has no busy state either. | `JunkCleanerView.swift:53-55`, `SmartCareView.swift:34-49`, `ProtectionView.swift:49-51`, `SpaceLensView.swift:176`, `PerformanceView.swift:284-286` |
| N6 | **Smart Care scanning has no Cancel button** (only leaving the screen cancels), and it launches a full-home duplicate scan that can take minutes with no upfront expectation. | `SmartCareView.swift:67-79`, `SmartCareViewModel.swift:137-160` |
| N7 | **"Open Folder" in Space Lens drills into the folder** instead of revealing it in Finder; the review sheet has no checkboxes, so an item can only be removed by cancelling the sheet; after "done" there is no way back to the map. | `SpaceLensView.swift:234`, `SpaceLensViewModel.swift:154-159`, `SpaceLensView.swift:282-295`, `:65-77` |
| N8 | **The Protection quarantine list is outside any scroll view** and will overflow with many records. | `ProtectionView.swift:35-44`, `:53-71`, `:206-231` |
| N9 | **No Reveal in Finder, no preview, no search, no sort, no context menus, no keyboard shortcuts, no drag & drop** anywhere. | grep over `App/` |

### 5.4 Visual consistency

| # | Finding | Where |
|---|---|---|
| V1 | **Same action, two colours:** "Clean" in Junk is blue, while Smart Care / Duplicates / Uninstaller / Protection / Space Lens use red for the same kind of action. | `JunkCleanerView.swift:163-168` vs `SmartCareView.swift:41-46` etc. |
| V2 | **Button sizes differ for the same action:** Smart Care's "New Scan" is large, Duplicates' and Protection's are regular; Space Lens's Cancel is large, all other Cancels are regular. | `SmartCareView.swift:224` vs `DuplicateFinderView.swift:272`, `ProtectionView.swift:64`; `SpaceLensView.swift:121` |
| V3 | **Three list styles:** plain `List` rows (Junk, Protection), hairline rows inside a card (Duplicates), default `List` + `Section` (Cloud). | `JunkCleanerView.swift:83-92`, `DuplicateFinderView.swift:172-199`, `CloudCleanupView.swift:161-188` |
| V4 | **Two app-row styles:** Uninstaller uses orange letter tiles in 8 pt-radius rows; Updater uses real icons in 16 pt-radius cards that are about 90 pt tall. | `UninstallerView.swift:136-157`, `UpdaterView.swift:115-131` |
| V5 | **Screen title appears twice** (window title + in-content header) on Uninstaller, Updater, Space Lens, Duplicates (results) and Performance; the other five screens have no header at all. | `UninstallerView.swift:17`/`:67`, `UpdaterView.swift:24`/`:79`, `SpaceLensView.swift:21`/`:30`, `DuplicateFinderView.swift:44`/`:158`, `PerformanceView.swift:44`/`:52` |
| V6 | **The module hue system is barely visible in content:** Performance never uses its hue; five screens use theirs only on the empty-state icon; the active sidebar row is generic blue, not the module hue. | `PerformanceView.swift` (no `Theme.hue`), `SidebarNavRow.swift:45-48` |
| V7 | **Off-palette colours:** the treemap is a full rainbow (and unrelated to the UI), the iCloud banner uses system orange + `.caption`, provider brand colours are inline hex values. | `TreemapCanvasView.swift:42-47`, `CloudCleanupView.swift:154-156`, `:209-217` |
| V8 | **Type is not on a scale:** 47 raw sizes alongside the tokens; 12.5 pt is the most common size and not a token; `TextSize.xxxl` is unused. | §3.4 |
| V9 | **Treemap labels overflow their rectangles and overlap** each other, with no truncation or contrast rule (white text on yellow/lime). | `TreemapCanvasView.swift:22-29`; `light-Space-Lens-loaded.png` |
| V10 | **"Disconnected" is red**, although it is a normal state and the spec says red is for threats only. | `CloudCleanupView.swift:131` |
| V11 | **"Potential savings" footer has an empty button slot** (trailing `EmptyView`). | `CloudCleanupView.swift:95-99`, `:256-259` |
| V12 | **No transitions:** phases swap instantly; the only animation is the pulsing step dot. | `StepRowView.swift:43-47` |

### 5.5 Copy and content

| # | Finding | Where |
|---|---|---|
| C1 | **Start actions are named five ways:** "Start Scan", "Run Smart Care", "Scan", "Inspect" / "Inspect All", "Check Again". **Finish actions four ways:** "Done" (Junk → *back to the results*, not to idle), "New Scan", "Scan Again", "Done" (Uninstaller). | `JunkCleanerView.swift:63` + `JunkCleanerViewModel.swift:142-144` |
| C2 | **Removal is called Clean / Remove / Delete / Trash / Quarantine / Uninstall** depending on the screen; "reclaimed" vs "moved to Trash" vs "removed". | across `App/Features/` |
| C3 | **Summaries are not comparable:** bytes everywhere except Protection, which shows an item count; Smart Care adds a sentence, Junk just "reclaimed"; no per-module breakdown (the component supports one). | `ProtectionView.swift:55-58`, `SummaryCardView.swift:30-44` |
| C4 | **Empty states are inconsistent:** Cloud "Connect «Provider»" has no button (it is in the tile above); Updater's "Looking for installed applications…" doubles as loading and "nothing found"; Space Lens uses a bespoke picker instead of `EmptyStateView`. | `CloudCleanupView.swift:66-71`, `UpdaterView.swift:15-44`, `SpaceLensView.swift:80-116` |
| C5 | **Naming drift:** sidebar "Junk & Cache Scanner" vs card "Junk & Cache" vs Smart Care group "Junk & Cache"; window "SOS Mac" vs bundle name "SOSMac"; the Menu Bar Widget card explains a missing feature in its body copy. | `SOSMacApp.swift:17`, `DashboardView.swift:78`, `PerformanceView.swift:305` |
| C6 | **Sidebar grouping is unexplained:** one label ("ESSENTIAL TRIO") for 3 of 9 modules, then an unlabelled gap before the other 6. | `SOSMacApp.swift:102-118` |
| C7 | **Thermal State shows the same fact twice** (badge "Normal" + text "Nominal"). | `PerformanceView.swift:136-139` |

### 5.6 Structure and accessibility (for the implementing engineer)

| # | Finding | Where |
|---|---|---|
| A1 | **Phase rule is not applied consistently:** Updater and Cloud have no `Phase` enum (Booleans instead); Uninstaller tracks busy state outside its enum; Duplicates lacks `.cleaning`. The live-progress design asked for `.checkingAll` / `.inspectingAll` phases; they were implemented as flags. | `UpdaterViewModel.swift:15-17`, `CloudCleanupViewModel.swift:17-31`, `UninstallerViewModel.swift:29-31` |
| A2 | **No accessibility support:** only the sidebar rows have identifiers; no labels, the treemap canvas is invisible to VoiceOver, icon-only buttons are unnamed. | `SOSMacApp.swift:137`, `SpaceLensView.swift:207-211`, `TreemapCanvasView.swift` |
| A3 | **MenuBarHelper has no design system at all** and its menu-bar label changes width ("SOS Mac" → "CPU 42 %"). | `MenuBarHelper/MenuBarHelperApp.swift`, `MenuBarMetricsMonitor.swift:19-21` |
| A4 | **Junk results are per file across four roots** with only the file name shown — many identical names, no folder context, no grouping, no select-all. "Ignore" has no undo or management UI. | `Packages/CleanCore/Sources/CleanCore/JunkScanner/JunkScanner.swift:28-46`, `JunkCleanerViewModel.swift:127-140` |
| A5 | **All strings are hardcoded English** inside views. | no `.strings` in `App/` |

---

## 6. Screenshots

Folder: [`docs/redesign/screenshots/`](screenshots/) — 33 window captures, 900 × 532 px each (the window's default launch size, 1×), plus two contact sheets for a quick look: [`overview-light.png`](screenshots/overview-light.png) and [`overview-dark.png`](screenshots/overview-dark.png). Only the app window is captured; no other window or desktop content is in the images.

**What is in git (privacy check, 2026-11-26).** This repository is public, so all 35 images were reviewed one by one before the first commit. The PNG metadata holds only the capture time and the pixel size.

| Group | Files | Why |
|---|---|---|
| **Local only — account name (2)** | `dark-Space-Lens-scanning.png`, `light-Space-Lens-scanning.png` | The subtitle reads "Scanning «account name»…": the macOS account name of the machine. |
| **Local only — installed software (7)** | `dark-Uninstaller.png`, `light-Uninstaller.png`, `dark-Uninstaller-inspect-all.png`, `dark-Updater.png`, `light-Updater.png`, `dark-Updater-checked.png`, `light-Space-Lens-loaded.png` | They list the installed applications with names, versions and icons. |
| **Committed (24)** | the other 24 captures | They show only the app's own UI and its storage figures (used / total / free) — and, on Performance, memory size and load. Not identifying. |

The two contact sheets were rebuilt from the committed set only (13 dark, 11 light), so they show 24 of the 33 captures. Someone cloning the repository has 24 captures; the other nine exist only on the machine that took them. To rebuild a contact sheet: `magick montage -background '#8e8e93' -fill black -font /System/Library/Fonts/Supplemental/Arial.ttf -pointsize 16 -label '%t' -tile 4x -geometry 432x256+14+8 -depth 8 -strip dark-*.png overview-dark.png` (run on the committed files only).

### 6.1 What was captured

| File | Screen · state | Window |
|---|---|---|
| `light-Dashboard.png` · `dark-Dashboard.png` | Dashboard (only state) | inactive |
| `light-Smart-Care.png` · `dark-Smart-Care.png` | Smart Care · idle | inactive |
| `dark-Smart-Care-scanning.png` | Smart Care · scanning (both modules running, no aggregate bar yet) | inactive |
| `light-Junk-Cache-Scanner.png` · `dark-Junk-Cache-Scanner.png` | Junk & Cache · idle | inactive |
| `dark-Junk-Cache-Scanner-scanning.png` | Junk & Cache · scanning (rule 1 of 4 active) | inactive |
| `dark-Junk-Cache-Scanner-results.png` | Junk & Cache · results (per-file rows, sticky footer, blue "Clean") | **active** |
| `light-Uninstaller.png` · `dark-Uninstaller.png` | Uninstaller · browsing | inactive |
| `dark-Uninstaller-inspect-all.png` | Uninstaller · Inspect All running (sizes filled in, progress bar) | inactive |
| `light-Updater.png` · `dark-Updater.png` | Updater · **checking** (captured 3–4 s after launch; the light one still shows the progress bar, the dark one had just finished) | inactive |
| `dark-Updater-checked.png` | Updater · check finished | inactive |
| `light-Space-Lens.png` · `dark-Space-Lens.png` | Space Lens · source picker | inactive |
| `light-Space-Lens-scanning.png` · `dark-Space-Lens-scanning.png` | Space Lens · scanning the home folder (count only) | **active** |
| `light-Space-Lens-loaded.png` | Space Lens · **loaded, "By Folder"**, folder `/Applications` (treemap + breadcrumb + view-mode picker) | **active** |
| `dark-Space-Lens-loaded-by-type.png` | Space Lens · loaded, **"By Type"** selected, `/Applications` | **active** |
| `light-Duplicate-Finder.png` · `dark-Duplicate-Finder.png` | Duplicate Finder · idle | inactive |
| `light-Performance.png` | Performance · live metrics | inactive |
| `dark-Performance.png` | Performance · live metrics | **active** |
| `light-Cloud-Cleanup.png` | Cloud Cleanup · Google Drive tab, not connected | inactive |
| `light-Cloud-Cleanup-dropbox.png` · `light-Cloud-Cleanup-onedrive.png` | Cloud Cleanup · Dropbox / OneDrive tab | **active** |
| `light-Cloud-Cleanup-icloud-drive.png` | Cloud Cleanup · iCloud Drive tab | inactive |
| `dark-Cloud-Cleanup.png` | Cloud Cleanup · Google Drive tab | **active** |
| `dark-Cloud-Cleanup-icloud-drive.png` | Cloud Cleanup · iCloud Drive tab | **active** |
| `light-Protection.png` · `dark-Protection.png` | Protection · idle (disclaimer + Start Scan) | light: inactive · dark: **active** |

### 6.2 How to read them (caveats)

1. **Inactive windows (22 of 33).** Most captures were taken while the app window was not the key window. macOS then desaturates its system controls: prominent buttons render **grey instead of accent blue**, and segmented controls, checkboxes and traffic lights are grey too. Everything drawn by the app's own code (cards, badges, hero panel, sidebar tiles, aurora bloom, text colours) is accurate. The 11 **active** captures show the real control colours — in dark mode the primary buttons are standard macOS blue.
2. **Real data from the development Mac.** The committed images contain disk and memory figures and hashed cache file names from the machine they were taken on. The captures that show installed app names or the account name are not committed (see above).
3. **"Active" means someone was at the Mac.** Partway through the session the screen was unlocked and the window was interacted with (for example the Space Lens "By Type" view was selected); that is why some captures are active.

### 6.3 What was not captured, and why

| Not captured | Reason |
|---|---|
| Duplicate Finder scanning / results, Smart Care review / summary, Protection scanning / results / quarantine / summary | The home-wide duplicate scan takes minutes and results lists would contain personal file names; reaching these states needs taps. |
| Junk scanning / results in light mode | Time-boxed; only the dark captures were kept. |
| Space Lens inspector, cleanup cart, review sheet, done state; home-folder treemap | The home scan did not finish within 120 s (> 1.69 M items scanned); the inspector and sheet need taps. `/Applications` was used instead to show the loaded map. |
| Uninstaller inspect list and removed summary; Updater "update available" row; Cloud results; any cleaning state; error states | Need taps or real accounts, and none must be triggered unattended. |
| MenuBarHelper panel | Separate process, not launched. |

### 6.4 How they were produced (reproducible)

1. `xcodebuild build -scheme SOSMac -configuration Debug` on the untouched repo → **BUILD SUCCEEDED** (42 s clean build, Xcode 27.1). Derived data was placed in `/tmp` and `git status` was unchanged afterwards. `xcodegen generate` was not needed (the committed project is newer than every source file and already references them all).
2. The Mac was **locked**, so accessibility-driven clicks were refused. To open each screen without input, a **throwaway copy** of the sources was made in `/tmp/sosmac-shots-src` and given four launch-environment hooks (initial sidebar destination, initial Cloud tab, auto-start of read-only scans, a scan root for Space Lens). It was built separately into `/tmp/sosmac-shots-dd`. **Nothing in the repository was modified.**
3. One launch per capture with `open -n --env …` (and `open -g` for the second pass), then `screencapture -l<windowID> -o -x <file>` — the window only. No destructive control was ever triggered; only read-only scans were started.
4. Every instance was quit at the end; no SOS Mac process was left running.

The existing `SOSMacUITests/AuroraCareScreenshotTests.swift` was **not** used: it captures the whole display (`XCUIScreen.main.screenshot()`), needs an unlocked session for its clicks, and writes to a temp folder.

---

## 7. Where the docs and the code disagree

Found while reading; not fixed (read-only task). Worth a follow-up by the owner.

| Document says | Code does |
|---|---|
| `docs/code-standards.md:202-211` (Rule 6): Smart Care "doesn't pre-select", Duplicate Finder "doesn't mark any for deletion", Cloud Cleanup "requires explicit confirmation per group" | Smart Care and Duplicate Finder **pre-select** (safe junk; every duplicate except the keep copy); Cloud rows delete on one tap with no confirmation. |
| `docs/project-overview-pdr.md`, `docs/project-roadmap.md`: Phases 7–9 planned; Performance buttons "disabled pending Phase 8"; roadmap: Uninstaller has "confirmation before uninstall", Cloud has "checkboxes … bulk delete confirmation", "Deletion verified (cloud trash, not permanent)" | README says Phases 0–8 are complete; Purge RAM / Flush DNS are wired to the helper; there is no uninstall confirmation and no Cloud checkbox/bulk flow; Dropbox uses `files/delete_v2`. |
| `docs/system-architecture.md`: Cloud flow ends with "UI displays 'Deleted N items, N failed'"; Phase 8 helper "not implemented" | No such message exists; the helper is implemented (`PrivilegedHelper/`). |
| `docs/codebase-summary.md`, README: 8 modules / 9 `SidebarDestination` cases; `MenuBarHelperView.swift` | 9 modules + Dashboard = 10 cases; the file is `MenuBarMetricsMonitor.swift`. |
| `CLAUDE.md`: the design source of truth is Open Design project `macos-care-suite` | That project is not in the local Open Design daemon; the screenshots in §6 are the baseline. |
| `openspec/…/shared-ui-components/spec.md`: every module screen has a `HeroPanelView`; one shared destructive-confirm dialog | Only the Dashboard has a hero panel; the confirm dialog does not exist. (The missing health dial on the Dashboard is a documented, intentional deviation.) |
| `AGENTS.md`: never introduce `FileManager.removeItem` outside the `Cleaner` path | `QuarantineManager.swift:80` and `:115` call `removeItem` — only on the empty quarantine sub-folder it just created, not on user data. |

Two build notes outside the UI: the app links `libyara` from `/opt/homebrew/opt/yara/lib` (not bundled; the linker warns it was built for macOS 26.0 while the deployment target is 14.0), and `CFBundleName` is `SOSMac` with no display name.

---

## 8. Appendix — file index

### 8.1 App target (lines)

| File | Lines | Role |
|---|---|---|
| `App/SOSMacApp.swift` | 165 | `@main`, `SidebarDestination`, `RootView` (split view), `SidebarView`, `SidebarFooterView` |
| `App/DesignSystem/Theme.swift` | 148 | Tokens |
| `App/DesignSystem/AuroraBloomModifier.swift` | 35 | `.auroraBloom()` |
| `App/DesignSystem/BadgeView.swift` | 34 | `BadgeStyle`, `BadgeView` |
| `App/DesignSystem/CareCardModifier.swift` | 23 | `.careCard()` |
| `App/DesignSystem/ElevationModifier.swift` | 21 | `.elevation(_:)` |
| `App/DesignSystem/EmptyStateView.swift` | 43 | Empty state |
| `App/DesignSystem/HealthDialView.swift` | 36 | Unused dial |
| `App/DesignSystem/HeroPanelView.swift` | 97 | Hero panel |
| `App/DesignSystem/ModuleCardView.swift` | 61 | Dashboard card |
| `App/DesignSystem/ProgressBarView.swift` | 26 | Progress bar |
| `App/DesignSystem/ScanProgressPanel.swift` | 120 | Shared scan progress |
| `App/DesignSystem/ScanProgressTracker.swift` | 70 | Progress + ETA state |
| `App/DesignSystem/SidebarNavRow.swift` | 70 | Nav row, section label, storage gauge |
| `App/DesignSystem/StepRowView.swift` | 71 | Step row |
| `App/DesignSystem/StickyFooterView.swift` | 34 | Sticky footer |
| `App/DesignSystem/SummaryCardView.swift` | 58 | Success card |
| `App/Features/Dashboard/DashboardView.swift` | 139 | Dashboard (no view model) |
| `App/Features/SmartCare/SmartCareView.swift` · `SmartCareViewModel.swift` | 230 · 262 | Smart Care (+ `PerformanceSnapshot`) |
| `App/Features/JunkCleaner/JunkCleanerView.swift` · `JunkCleanerViewModel.swift` | 171 · 150 | Junk & Cache |
| `App/Features/Uninstaller/UninstallerView.swift` · `UninstallerViewModel.swift` | 283 · 158 | Uninstaller |
| `App/Features/Updater/UpdaterView.swift` · `UpdaterViewModel.swift` | 184 · 76 | Updater |
| `App/Features/SpaceLens/SpaceLensView.swift` · `SpaceLensViewModel.swift` · `TreemapCanvasView.swift` | 324 · 337 · 48 | Space Lens |
| `App/Features/Duplicates/DuplicateFinderView.swift` · `DuplicateFinderViewModel.swift` | 282 · 146 | Duplicate Finder |
| `App/Features/Performance/PerformanceView.swift` · `PerformanceViewModel.swift` | 357 · 132 | Performance |
| `App/Features/CloudCleanup/CloudCleanupView.swift` · `CloudCleanupViewModel.swift` · `ASWebAuthSessionPresenter.swift` | 279 · 175 · 52 | Cloud Cleanup |
| `App/Features/Protection/ProtectionView.swift` · `ProtectionViewModel.swift` | 232 · 176 | Protection |
| `App/Services/PrivilegedHelperClient.swift` | 160 | Helper registration + XPC calls |
| `App/Support/IgnoredItem.swift` · `QuarantineRecord.swift` · `VolumeStorageInfo.swift` | 15 · 22 · 31 | SwiftData models, storage stats |
| `MenuBarHelper/MenuBarHelperApp.swift` · `MenuBarMetricsMonitor.swift` | 47 · 45 | Menu-bar widget |
| `SOSMacUITests/AuroraCareScreenshotTests.swift` | 58 | Screenshot UI test |

### 8.2 Identifiers and hooks

- Sidebar row identifiers: `sidebar-nav-Dashboard`, `sidebar-nav-Smart Care`, `sidebar-nav-Junk & Cache Scanner`, `sidebar-nav-Uninstaller`, `sidebar-nav-Updater`, `sidebar-nav-Space Lens`, `sidebar-nav-Duplicate Finder`, `sidebar-nav-Performance`, `sidebar-nav-Cloud Cleanup`, `sidebar-nav-Protection`.
- UI-test hook: launch environment `SOSMAC_UITEST_APPEARANCE` = `light` | `dark` forces the appearance (read only by `RootView`; unset in normal launches).

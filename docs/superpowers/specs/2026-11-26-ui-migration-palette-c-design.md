# SOS Mac UI Migration — Palette C "Midnight Glass" (Design Spec)

Status: **Approved for implementation.** Phương approved this document and settled every open decision in §10 on 2026-11-26.
Date: 2026-11-26
Author: SOS Mac bot. Design: @Designer (OpenDesign project "SOS Mac Redesign v1 — Aurora Indigo"). Palette research: Worker-G1 (`sos-mac-purple-neon-palette-g1.md`).
Code baseline: `main` @ `0587765`. Current UI: [`docs/redesign/current-ui-inventory.md`](../../redesign/current-ui-inventory.md) ("inventory" below).
Companion implementation plan: [`docs/superpowers/plans/2026-11-26-ui-migration-palette-c.md`](../plans/2026-11-26-ui-migration-palette-c.md).

> **Tóm tắt (VN)**
> - Spec này chuyển SOS Mac sang UI mới của Designer, dùng **Palette C "Midnight Glass"** (dark + light) thay cho Palette A. Giữ nguyên tên token `Theme.Color.*`, chỉ đổi giá trị.
> - Palette C **light chưa đầy đủ** ở nguồn: report chỉ cho 12/28 token và prototype chưa từng render C light (chỉ có C dark). Các giá trị còn lại được suy ra theo quy tắc, gắn nhãn `[D]` và cần Designer/Phương chốt (§2.2, §10 OD-1).
> - Phạm vi: shell mới, component dùng chung, 10 màn + menu bar, và 4 nhóm sửa an toàn/dữ liệu (hộp xác nhận, khoá bản Keep ở Smart Care, ghi "Folder"/"At least…" ở Uninstaller, giữ kết quả khi rời màn). Không gồm việc engine trong `needs-engine-work.html`.
> - Có **20 open decisions** cần Phương chốt (§10), mỗi mục kèm đề xuất. Hai mục Phương hỏi trực tiếp: OD-a (Similar Images) và OD-b (tổng size từng bộ duplicate).
> - Đã verify: tương phản (tính lại bằng script, khớp report), API Apple (SDK macOS 27.0 trong Xcode 27.1 + docs Apple), `Theme.swift` của Designer typecheck cho macOS 14.

---

## 0. Sources, evidence labels, and rules that never change

### 0.1 Order of precedence

1. **Phương's decision (2026-11-26):** migrate to the new UI with Palette C (dark + light) instead of Palette A.
2. **The prototype** (layout, components, copy, states). One state opens directly with a query, e.g. `index.html?screen=junk&state=review&theme=light&palette=c`. `board.html` shows every state, the confirmation dialogs and the light screens; `tokens.html` the tokens and components.
3. **The palette report §3.3** for Palette C colours and §4 for how neon is used.
4. **This spec** for everything the sources do not cover. Every such value is labelled.

### 0.2 Evidence labels used in the token tables

| Label | Meaning |
|---|---|
| `[R]` | From the palette report §3.3 (Palette C). |
| `[T]` | From `tokens.css`, the `data-palette="c"` dark override block the Designer built. |
| `[A]` | Inherited from Palette A because `tokens.css` does not override it for C — the prototype renders C with exactly this value. |
| `[D]` | **Derived in this spec** because no source value exists. Stated with its rule. Needs Designer/Phương confirmation (OD-1). |

Contrast ratios in this document were **computed** with the WCAG 2.x relative-luminance formula on 2026-11-26 (not copied). They reproduce every Palette C figure in the report.

### 0.3 Project rules this spec must respect (unchanged)

From `AGENTS.md`, `CLAUDE.md`, inventory §4.2:

- **Trash only.** Every local removal goes through `Cleaner.clean(_:)` → `FileManager.trashItem`. Root-owned paths (Junk "System Caches") go through the privileged helper, as today. No `FileManager.removeItem` anywhere else.
- **Every ViewModel is a `Phase` state machine** (`@MainActor @Observable`). UI is composed from `App/DesignSystem`; no hand-rolled styling outside tokens.
- **No fake numbers.** A number appears only if an engine field backs it (inventory §4.1). If the prototype shows a value the engine cannot produce, the value is omitted or the copy is corrected — never filled with a placeholder.
- **Fail closed.** Never guess a value no public API provides.
- **Recommended keep is protected** in duplicate groups (newest by *modified* date): disabled control + "Keep" badge.
- **Pre-selection is not widened** without a product decision (OD-a, OD-7).

---

## 1. Goals

1. Adopt the redesigned UI for all 10 screens and the menu-bar helper: new shell, shared components, one lifecycle frame per module.
2. Use Palette C "Midnight Glass" in dark and light, keeping the Designer's token names (`Theme.Color.*`, `Theme.Hue`, `Theme.Spacing`, `Theme.Radius`, `Theme.Motion`, `Theme.Font`).
3. Ship the safety and data fixes that the new UI depends on (§6): confirmation before anything leaves its place, the Keep lock in Smart Care, honest size labels in the Uninstaller, results that survive navigation.
4. Keep the product releasable after every PR (see the plan).

---

## 2. Tokens — Palette C "Midnight Glass"

### 2.1 Principles

- **Names stay, values change.** The 28 colour tokens keep the names and order of the Designer's `tokens/Theme.swift`.
- **Dark and light are both first-class.** Dark is the primary look the prototype was designed in; light follows the report's rule "neon always darkens in light; glow effects stay in dark mode only".
- **Module hues do not change.** The shared 10-hue set is the same in both appearances (§2.5).
- **Per-appearance resolution** uses the Designer's `Color.adaptive(light:dark:)` (dynamic `NSColor` provider), as the repo's `Theme` already does.

### 2.2 What the sources do and do not contain (read this first)

| Fact | Consequence |
|---|---|
| `tokens.css` has a Palette C block for **dark only** (line 106). | Dark is complete for the tokens the prototype uses. |
| Selecting Palette C + Light in the prototype renders **Palette A light** (the `[data-theme="light"]` block is not palette-specific; `board.html`'s "Light mode" section shows Palette A light). | **Nobody has seen Palette C light yet.** |
| Report §3.3 gives Palette C light for 12 values only: base, two purples, three neons, three text colours, three status colours. | The other tokens need a rule → labelled `[D]`. |
| `tokens/Theme.swift` carries Palette A values; it has **no** hairline, row-state, gradient, shadow or glow tokens, although `tokens.css` and `styles.css` use them. | They are added as new tokens with proposed names (§2.4). |
| `tokens/Theme.swift` lists 9 module hues; the shared set has 10 (rose is used inline for the Protection "Known threats" tile). | Rose is added as `Theme.Hue.threat` (§2.5). |
| `Theme.Hue` has no `ink` (glyph colour) although `tokens.json` does. | `ink` is added per hue (§2.5). |

### 2.3 Colour tokens (28) — Palette C

| `Theme.Color` | CSS variable | Dark | Light | Dark src | Light src | Contrast (computed) |
|---|---|---|---|---|---|---|
| `bgBase` | `--bg-base` | `#0A0E1A` | `#F4F6FF` | `[R][T]` | `[R]` | canvas |
| `bgElevated` | `--bg-elevated` | `#131A2E` | `#FFFFFF` | `[R][T]` | `[D]` (A light rule: elevated = white) | sheets, dialogs |
| `glass` | `--glass` | `#18213A` | `#FFFFFF` | `[R][T]` | `[D]` (A light rule) | Reduce Transparency fill |
| `card` | `--card` | `#111829` | `#FFFFFF` | `[T]` | `[D]` (A light rule) | tiles, rows, banners |
| `sidebar` | `--sidebar` | `#0E1424` | `#EEF2FF` | `[T]` | `[D]` (Tailwind indigo-50; A light used a 6 % tint of its purple) | sidebar fallback |
| `primary` | `--primary` | `#818CF8` | `#4F46E5` | `[R][T]` | `[R]` (button) | 6.46:1 dark · 5.83:1 light on base |
| `primaryDeep` | `--primary-deep` | `#4F46E5` | `#4F46E5` | `[R][T]` | `[R]` (button) | fill only. `onPrimary` on it **6.29:1** |
| `primaryBright` | `--primary-bright` | `#A5B4FC` | `#4338CA` | `[R][T]` | `[R]` (primary.text) | **9.66:1** dark · **7.33:1** light — links, selected labels |
| `onPrimary` | `--on-primary` | `#FFFFFF` | `#FFFFFF` | `[A]` | `[A]` | label on filled controls |
| `neonCyan` | `--neon-cyan` | `#22D3EE` | `#155E75` | `[R][T]` | `[R]` | 10.65:1 · 6.74:1 |
| `neonLime` | `--neon-lime` | `#A3E635` | `#3F6212` | `[R][T]` | `[R]` | 12.77:1 · 6.56:1 |
| `neonMagenta` | `--neon-magenta` | `#A78BFA` | `#6D28D9` | `[R][T]` | `[R]` | 7.08:1 · 6.59:1 — **violet in Palette C, not magenta** (name kept) |
| `textPrimary` | `--text-1` | `#EEF2FF` | `#141A33` | `[R][T]` | `[R]` | **17.22:1** · **15.89:1** |
| `textSecondary` | `--text-2` | `#A5ADC8` | `#4A5273` | `[R][T]` | `[R]` | **8.63:1** · **7.09:1** |
| `textTertiary` | `--text-3` | `#6E7799` | `#7C84A3` | `[R][T]` | `[R]` | **4.37:1** · **3.42:1** — see rule T3 |
| `success` | `--success` | `#34D399` | `#047857` | `[R][T]` | `[R]` | 10.02:1 · 5.09:1 |
| `warning` | `--warning` | `#F59E0B` | `#B45309` | `[R][T]` | `[R]` | 8.97:1 · 4.66:1 |
| `danger` | `--danger` | `#F87171` | `#B91C1C` | `[R][T]` | `[R]` | 6.96:1 · 6.00:1 |
| `dangerFill` | `--danger-fill` | `#B91C1C` | `#B91C1C` | `[A]` | `[A]` (equals C light `danger`) | irreversible action fill; `onPrimary` on it **6.47:1** |
| `treemap1` | `--tm-1` | `#4A3A9E` | `#DDD6FE` | `[A]` | `[A]` | labels `treemapText` |
| `treemap2` | `--tm-2` | `#3D3F95` | `#E0E7FF` | `[A]` | `[A]` | |
| `treemap3` | `--tm-3` | `#34509C` | `#DBEAFE` | `[A]` | `[A]` | |
| `treemap4` | `--tm-4` | `#2E5B8F` | `#E0F2FE` | `[A]` | `[A]` | |
| `treemap5` | `--tm-5` | `#463C82` | `#EDE9FE` | `[A]` | `[A]` | |
| `treemap6` | `--tm-6` | `#3A4780` | `#D9E2FF` | `[A]` | `[A]` | |
| `treemap7` | `--tm-7` | `#353A6E` | `#E9E5FF` | `[A]` | `[A]` | |
| `treemap8` | `--tm-8` | `#2D2A55` | `#ECE7FA` | `[A]` | `[A]` | also the "smaller items" bucket |
| `treemapText` | `--tm-text` | `#F4F2FF` | `#1A1333` | `[A]` | `[A]` | 6.3–12.1:1 on the dark ramp · 12.8–15.5:1 on the light ramp |

Treemap note: the dark labels measure 6.31:1 (`treemap4`) and 6.85:1 (`treemap3`), not "≥ 7:1" as the `tokens.css` comment says. They pass WCAG AA (4.5:1); the comment is corrected when the tokens are ported.

### 2.4 Prototype tokens without a Swift name (added — names are proposals)

These are used throughout `styles.css`; without them the SwiftUI port would need one-off colours, which the project forbids.

| Proposed name | Prototype | Dark (C) | Light (C) | Src | Rule |
|---|---|---|---|---|---|
| `Theme.Color.hairline` | `--hairline` | `textSecondary` @ 12 % | `textPrimary` @ 9 % | `[D]` | Same alpha as the prototype; hue from C's own text token (prototype literal is A's text-2) |
| `Theme.Color.hairlineStrong` | `--hairline-strong` | `textSecondary` @ 22 % | `textPrimary` @ 16 % | `[D]` | Same |
| `Theme.Color.rowHover` | `--row-hover` | `primaryBright` @ 8 % | `primaryBright` @ 6 % | `[D]` | A recipe (primary-bright at 8 % / 6 %) |
| `Theme.Color.rowSelected` | `--row-selected` | `primary` @ 20 % | `primary` @ 12 % | `[T]` / `[D]` | Dark from tokens.css; light by A's 12 % recipe |
| `Theme.Gradient.aurora` | `--gradient-aurora` | `#A5B4FC → #818CF8 → #6366F1` (120°) | `#6366F1 → #4F46E5 → #155E75` | `[T]` / `[D]` | Light by A's transformation (indigo → primary-deep → neon-cyan, light values) |
| `Theme.Gradient.soft` | `--gradient-soft` | `#A78BFA → #8B5CF6 → #6366F1` (135°) | `#8B5CF6 → #7C3AED → #6366F1` | `[A]` | Not overridden for C (violet stops; OD-1d) |
| `Theme.Color.treemapMix` | `--tm-mix`, `--tm-mix-pct` | `card` @ 42 % | `card` @ 24 % | `[D]` | Token reference instead of A's literal card colour |
| `Theme.Elevation.raised`, `.float` | `--shadow-raised`, `--shadow-float` | A's black-based layers | A's `#1A1333`-based layers | `[A]` | Keep the existing two-layer `Elevation` shape |
| `Theme.Glow.idleAlpha` | `--glow-alpha` | `0.32` | `0` | `[A]` | No glow in light |
| `Theme.Glow.auroraAlpha` | `--aurora-alpha` | `0.16` | `0.07` | `[A]` | |

### 2.5 Module hues — the shared set of 10, unchanged

Same in both appearances. `ink` is the glyph colour on the tile.

| Module | Hue | ink | ink on tile gradient (computed, min) |
|---|---|---|---|
| Smart Care | `#8B5CF6` | `#FFFFFF` | 3.73:1 |
| Junk & Cache (Cleanup) | `#6366F1` | `#FFFFFF` | 3.91:1 |
| Duplicate Finder (Storage) | `#3B82F6` | `#FFFFFF` | 3.28:1 |
| Space Lens | `#E879F9` | `#140F26` | 4.75:1 |
| Cloud Cleanup | `#38BDF8` | `#140F26` | 5.37:1 |
| Uninstaller (Applications) | `#FB923C` | `#140F26` | 5.15:1 |
| Updater (Utilities) | `#FBBF24` | `#140F26` | 6.81:1 |
| Performance (Speed) | `#2DD4BF` | `#140F26` | 6.12:1 |
| Protection | `#22D3EE` | `#140F26` | 6.34:1 |
| Threat (Malware rose) | `#F87171` | `#140F26` | 4.27:1 |

("tile gradient" = the prototype's tile fill: hue 92 % / white 8 % at the top to hue 78 % / black 22 % at the bottom; the minimum is over both ends. All pass the 3:1 rule for graphical objects.)

### 2.6 Token usage rules (normative)

- **T1 — Neon is a verb, not a surface** (report §4). `neonCyan` = scanning / cleaning in progress; `neonLime` = done / selected-and-ready check; `neonMagenta` (violet in C) = Space Lens signature and selection ring. Never neon body text, never neon as a background fill. Neon is for status dots, icons, progress rings, numerals ≥ 18 pt and labels of ≤ 3 words at ≥ 13 pt semibold (report §4.3).
- **T2 — `primaryDeep` is a fill, never text or an icon on a card** (3.06:1 on base, 2.81:1 on card in dark). Text and links use `primaryBright`.
- **T3 — `textTertiary` is for large or bold text only.** It reaches **4.37:1 on `bgBase` in dark and 3.42:1 in light**, below the 4.5:1 body-text minimum, and it drops further on other surfaces (dark: 4.01 card, 3.92 elevated, 3.61 glass; light: 3.69 card, 3.30 sidebar). Allowed: text ≥ 18 pt, bold text, disabled text, placeholders, decorative marks. Never for body copy, captions, sizes or paths, and never on a selected row (2.95:1 dark, 3.08:1 light).
- **T4 — The 11 px badge label is small text**, so its colour must reach 4.5:1 on its own tinted background. All badge colours do except `warning` in light (4.32:1) — see §2.7.
- **T5 — Module hues are tile fills, not marks, in light mode.** As bare marks on the light base most fail 3:1 (Updater 1.55:1, Protection 1.68:1, Performance 1.73:1, Cloud 1.99:1, Uninstaller 2.10:1, Space Lens 2.28:1). State that must be seen (active step, busy dot, selected ring) uses a neon or status token, which darkens in light.
- **T6 — Glow budget** (report §4): idle glow blur ≤ 12–16 pt at ≤ 35 % opacity (`Glow.idleAlpha` 0.32); full bloom only while an action runs; none in light; none under Reduce Motion.
- **T7 — Byte and count formatting** uses the existing `ByteCountFormatter(.file)` (`CleanCore.ByteFormatter`) and plain integer counts. No new formatters.

### 2.7 Contrast-driven deviations from the prototype CSS

Found while computing §2.3–2.6. Each is a one-line change in the SwiftUI port and keeps the Designer's look; they need the Designer's acknowledgement (OD-1e).

| # | Prototype does | Problem under Palette C | Spec says |
|---|---|---|---|
| X1 | Checked checkbox is filled `primary` in dark with a white check | white on `#818CF8` = **2.98:1** (under A it was 4.23:1) | Checked fill is `primaryDeep` in both appearances (white check 6.29:1) |
| X2 | Checkbox outline is `textTertiary` | 3.08:1 on a selected row in light | Outline uses `textSecondary` (7.65:1 light, 7.93:1 dark on card; ≥ 5.8:1 on selected rows) |
| X3 | "Known threats" tile is rose with a white glyph | 2.56:1 at the light end of the tile gradient | Rose tile uses ink `#140F26` (4.27:1) |
| X4 | `warning` badge: `#B45309` label on an 11 % warning tint (light) | **4.32:1**, below 4.5:1 for 11 px text | In light the warning badge label uses `textPrimary`; icon/dot stay `warning`. (Inherited from A, not caused by C.) |
| X5 | "Memory in use" = wired + active + compressed (sample data) | The engine reports used = total − free, which reads ~99 % on an idle Mac (inventory D2) | The "in use" definition is fixed in the engine, or the copy changes — OD-11 |

### 2.8 Geometry, type, motion — as in the Designer's `Theme.swift`

Unchanged: `Theme.Spacing` (s1 4 … s12 48), `Theme.Radius` (xs 5, sm 7, md 10, lg 14, xl 20, pill), `Theme.Motion` (quick 0.15 s ease-out, standard 0.25 s snappy, emphasized spring 0.45 s, pulse 2.4 s), `Theme.Font` (macOS text styles + `numeralXL` 40, `numeralL` 28).

Three type tokens differ between the prototype's CSS pixel sizes and the macOS text styles the Designer chose. The text styles win (OD-1f is informational): `display` = largeTitle **26 pt** (prototype 30 px), `eyebrow` = caption **10 pt** (prototype 11 px), `mono` = caption monospaced **10 pt** (prototype 11 px). Source: HIG Typography, "macOS built-in text styles".

`Theme.swift` (Designer's version) **typechecks** for `arm64-apple-macos14.0` with `-strict-concurrency=complete` (checked 2026-11-26, Xcode 27.1).

---

## 3. Shell

### 3.1 Window

| Aspect | Spec |
|---|---|
| Default size | **1200 × 760 pt** via `.defaultSize(width: 1200, height: 760)` on the `WindowGroup`. Applies on first launch only; macOS restores the last frame afterwards (documented behaviour of `defaultSize`). |
| Minimum size | Proposed **960 × 600** (today 720 × 480; the prototype has none). Below ~1100 pt wide the review layout drops to two columns (§4.5). OD-5. |
| Layout | One `NavigationSplitView`: sidebar **240 pt** (today ideal 232) + detail. No extra windows. |
| Title | The window title is the screen name, shown once (fixes inventory V5 "title appears twice"): `navigationTitle` + `navigationSubtitle` (state or count), no second in-content header. |
| Appearance | Follows the system. No in-app toggle. `SOSMAC_UITEST_APPEARANCE` stays test-only. |
| Language | English, strings in code (unchanged in this migration). |

### 3.2 Sidebar

Groups, in order (top to bottom). Labels and symbols are the prototype's (`data.js`, `ui.js`).

| Group | Rows |
|---|---|
| *(no label)* | **Dashboard** `sparkles` · **Smart Care** `wand.and.stars` |
| **Clean** | **Junk & Cache** `trash` · **Duplicate Finder** `doc.on.doc` · **Space Lens** `square.grid.3x3` · **Cloud Cleanup** `icloud` |
| **Manage** | **Uninstaller** `xmark.bin` · **Updater** `arrow.triangle.2.circlepath` |
| **Speed** | **Performance** `gauge.with.dots.needle.50percent` |
| **Protect** | **Protection** `checkmark.shield` |

- **One rename:** the sidebar row and window title "Junk & Cache Scanner" become **"Junk & Cache"** (fixes inventory C5). The identifier becomes `sidebar-nav-Junk & Cache`.
- Row anatomy: 22 pt hue tile (ink per §2.5) + 13 pt medium label, 32 pt tall, radius 8. Hover = `rowHover`; current = `rowSelected`; the current row's tile gets the idle glow. No generic accent wash (fixes V6).
- Group label: eyebrow style, `textSecondary`.
- All 10 rows fit without scrolling at 760 pt (today the last row is hidden behind the footer — inventory N2).
- **Footer:** volume name + "«free» free", a 4 pt storage meter (`Gradient.soft`), "«used» of «total» used". Real boot-volume numbers via `VolumeStorageInfo`, read on appearance as today. The "SOS Mac 0.1.0" line is dropped from the sidebar (the version stays in the app's About box).
- **Busy indicator** (optional, OD-3): a 6 pt `neonCyan` dot with glow on a row whose module is scanning in the background. It shows real state only (the view model's phase), never a count.

### 3.3 Toolbar (per screen)

- Content: optional back button (in `review` and sub-screens), the screen title, a subtitle (state, count or folder), trailing tools (segmented pickers, **Quarantine** button on Protection, search on Uninstaller if OD-13).
- **Implementation choice — system toolbar** (OD-2): title + subtitle as a `.principal` toolbar item, back button in `.navigation`, tools in `.primaryAction`. Rationale: HIG Toolbars (read 2026-11-26): "Reduce the use of toolbar backgrounds and tinted controls"; on macOS 26 the system toolbar gets Liquid Glass automatically; overflow and keyboard access come free. Trade-off: the header spans the window instead of only the detail column, as the prototype draws it.
- Monochrome toolbar: no tinted toolbar buttons. The one focal action of each state lives in the dock (§4.2).

### 3.4 Navigation and state ownership (inventory N1)

- An app-level **session store** owns every module's view model for the life of the app. Selecting another sidebar row no longer destroys results, selections or inspected sizes, and no longer cancels a running scan.
- Sub-states (`results`, `review`, `cleaning`, `done`, `empty`, `error`, Quarantine list) are **inside** a screen. The sidebar selection is the only navigation state. The back button returns one step (`review → results`, `Quarantine → Protection`).
- Leaving a screen while it scans: the scan keeps running (OD-3).
- Nothing persists across app launches (unchanged): no scan history, no "last scanned".

---
## 4. Shared components and their states

All sizes are points, taken from the prototype's `styles.css`. Colours are the tokens of §2. Components live in `App/DesignSystem/`; a screen may compose them but not restyle them.

### 4.1 Lifecycle frame (every module that scans)

One vocabulary, used by the shared frame view. Each module keeps its own `Phase` enum (project rule) and exposes a pure, unit-tested mapping `var lifecycle: LifecycleState`.

```swift
enum LifecycleState { case start, scanning, results, review, cleaning, done, empty, error }
```

| State | What the user sees | Primary action (dock) | Secondary |
|---|---|---|---|
| `start` | Start view: orb, what the module does, what it will and will not touch | **Scan** (Updater: **Check**, Uninstaller: **Measure All**) | source list (Space Lens), locations + quarantine panel (Protection) |
| `scanning` | Scanning view: steps (pending / active / done / failed), progress (determinate only when a total is known, else a count line), current path | **Stop** (indeterminate or determinate ring) | — |
| `results` | Results head + result tiles + banners (skipped files, partial failure) | **Clean** (disabled when nothing is selected) | **Review Items…** (left), **Scan Again** (right) |
| `review` | Review frame (§4.5) or the module's own review | **Move to Trash…** (Protection: **Quarantine…**) → confirmation | back to results |
| `cleaning` | "Moving **n of N** items to the Trash…" + path; count-based progress | disabled CTA "Moving" | — |
| `done` | Done card: bytes moved, stats, failure banner if any | **Scan Again** | **Open Trash** (or Back to…) |
| `empty` | "Nothing found" card | **Scan Again** | optional extra (Smart Care health tile) |
| `error` | Why it stopped, in plain words | **Try Again** | one relevant escape (Open System Settings, Choose Another Folder) |

Rules of the frame:

- **F1 — One focal action per state.** It is always the round CTA in the dock.
- **F2 — Stop returns to `start` and discards partial results.** A partial list would look complete.
- **F3 — `empty` means "every step succeeded and found nothing".** If one step failed, the state is `results` with a failed tile and an error banner, or `error` when nothing usable remains.
- **F4 — `done` is honest about failures.** "Couldn't move: n" is a stat, and each failure gets a banner with the engine's reason. The copy never says "reclaimed" for files that did not move.
- **F5 — Error copy describes a cause the engine can really produce** (§6.3).
- **F6 — Chrome is stable.** The toolbar shows title + state subtitle in every state; the dock keeps its height so the layout does not jump between states.
- **F7 — Transitions** between states are a cross-fade (`Motion.standard`); the phase change itself is instant and never delays data.

### 4.2 Dock and round CTA

- **Dock:** 128 pt tall, 28 pt side padding, three slots (left meta · CTA · right buttons). Meta is 12 pt `textSecondary`; a bold figure is `textPrimary`.
- **CTA:** 80 × 80 circle, 14 pt semibold `onPrimary` label. Fill: radial gradient (`primaryDeep` 70 % + `#A78BFA` 30 % at 30 % 20 % → `primaryDeep`), flat `primaryDeep` in light. Shadow: white 25 % inner highlight, 1 pt white 8 % ring, 0/8/28 glow in the ring colour at `Glow.idleAlpha`. Hover scales 1.04, press 0.97 (`Motion.quick`, spring ease).

| CTA state | Look |
|---|---|
| default | label per F1; optional **progress ring** — determinate (value 0…1) or indeterminate (22 % arc, 1.4 s rotation) |
| stop | `card` fill, `textPrimary` label "Stop", 1 pt `hairlineStrong` inner ring; ring optional |
| moving | disabled, label "Moving", indeterminate ring |
| disabled | opacity 0.42, no glow, no ring |

The ring is 3 pt `neonCyan` on a `hairlineStrong` track, inset 7 pt outside the button, with a cyan drop-shadow scaled by `Glow.idleAlpha` (none in light, none under Reduce Motion).

### 4.3 Result tile

Six-column grid; a tile is **wide** (spans 3) or **full** (spans 6). Min height 172 (full: none), padding 18, radius `lg`, `card` fill, 1 pt `hairline`, `Elevation.raised`, a 90 pt hue wash at 12 % from the top.

| Part | Spec |
|---|---|
| header | 30 pt hue tile + label (`headline`) |
| check | optional 22 pt disc top-right: `neonLime` fill, check in dark ink (light: white) — "something here is selected" |
| big number | `numeralXL` (40) + optional unit (18 semibold, `textSecondary`) |
| caption | `callout`, `textSecondary` |
| body | free slot (e.g. the three-column health check) |
| foot | badges, pushed to the bottom |
| `skipped` | opacity 0.55 — the step failed or was not run; big value "—" |

States: default · selected (check) · skipped (failed) · `full`.

### 4.4 Buttons, segmented control, badges

| Control | Spec |
|---|---|
| Button · default | 28 tall, 12 side padding, radius 7, 13 medium, `card` fill, 1 pt `hairlineStrong`, `textPrimary` |
| Button · prominent | `primaryDeep` fill, no border, `onPrimary`, white 18 % inner highlight + glow at `Glow.idleAlpha` |
| Button · danger | `dangerFill`, `onPrimary`. **Only for the server-side cloud delete.** "Move to Trash" stays prominent, because Trash can be restored. |
| Button · plain | no fill, no border, `primaryBright`, 6 side padding (links, "Select All", "Deselect All") |
| Button · large | 34 tall, 18 side padding, 14 pt, radius 9 (the Dashboard hero button) |
| disabled | opacity 0.42, no shadow |
| Segmented | stock segmented picker; selected segment on `rowSelected` with a 1 pt `hairlineStrong` inner ring |

Prefer stock macOS button styles (`bordered`, `borderedProminent`, `borderless`) tinted with tokens; a custom `ButtonStyle` is written only where stock cannot match (dock CTA, large CTA). The implementer records the choice in PR 4a.

Badge: 20 tall, radius 5, 7 side padding, 11 pt semibold, optional 11 pt symbol. Background = colour at 16 % over `card` (light: 11 %); label in the colour (rule T4 / X4). Kinds: `safe` (success) · `caution` (warning) · `risky`, `threat` (danger) · `keep` (success, `lock` symbol) · `neutral` (`textSecondary`) · `accent` (`primaryBright`). The prototype's CSS also defines a `cyan` kind (`neonCyan` label) but no screen uses it; it is **not ported in v1**, because an 11 pt label is below T1's 13 pt floor for neon text — a cyan status is a cyan dot with a `textSecondary` label.

### 4.5 Review frame

Three columns: **groups 250 · items flexible · detail 280**. A two-column variant (groups 250 · items) is used by the Uninstaller. The groups and detail columns use `bgBase` 60 % over `card`; 1 pt `hairline` between columns; a 1 pt `hairline` on top.

| Part | Spec |
|---|---|
| Group row | label (`headline`, truncated) + sub (`subheadline`, `textSecondary`) + "**k** of **n**" selected (`callout`, tabular digits); 9/10 padding, radius 8; current = `rowSelected` |
| List head | title + sub on the left; **Select All** and **Deselect All** (plain) on the right, each disabled when it would change nothing; optional banner under it |
| Item row | 16 checkbox · name (`body`, truncated) + path (`mono`, `textSecondary`, truncated) · badges · size (`callout`, right-aligned, min 64); 8/16 padding, bottom `hairline`; hover = `rowHover`; focused = `rowSelected` |
| Kept row | `success` at 5 % background; locked checkbox + **Keep** badge (§4.6) |
| Detail | padding 18; title `title3`; key rows (label `subheadline` semibold uppercase `textSecondary`, value `body`; paths monospaced); an explanation box (12 padding, radius 10, `card`, `hairline`) whose bold lead-in is `textPrimary` |
| Review bar | 60 tall, 20 side padding, top `hairline`; left meta; summary "**N items** · **size** selected" or "No items selected"; the CTA |

- **Select All never selects a kept item** or anything the module never pre-selects (caution / risky junk, helper items).
- **Lists are virtualised.** Junk results can exceed 100 000 rows; no per-row blur or shadow.
- Below ~1100 pt window width the detail column becomes a popover opened from the focused row (engineering proposal; OD-5).

### 4.6 Keep badge with a locked checkbox

- Checkbox: 16 × 16 visual, radius 4, 1.5 pt outline in `textSecondary` (X2); checked = `primaryDeep` fill + white check (X1); mixed = minus; **hit target at least 20 × 20** (HIG minimum for macOS), reached with padding.
- Kept item: checkbox is **disabled** (opacity 0.35, dashed outline, never checked) and a `keep` badge with a `lock` symbol reads **Keep**.
- A kept item cannot be selected by click, Select All, or keyboard.
- Accessibility: the row reads "«name», kept, «size»"; the disabled checkbox is not an accessibility element.
- Applies to: Duplicate Finder, Smart Care's duplicate section, Cloud groups (OD-7 decides for iCloud Drive).

### 4.7 Banners

Padding 10/12, radius 10, `callout`. Background = colour at 10 % over `card`; border = colour at 30 %; icon and bold title in the colour's own text role; body `textSecondary`; optional trailing button.

| Kind | Colour | Used for |
|---|---|---|
| `info` | `primaryBright` | "Needs your approval" (helper), "14 files were skipped", "Local scan" |
| `warn` | `warning` | "Similar isn't identical", "Deleting here is not Move to Trash", a file that could not be moved |
| `err` | `danger` | "Couldn't finish the duplicate scan", "Couldn't inspect «App»", "Couldn't read system metrics" |
| `ok` | `success` | "Free up RAM finished" |

An error banner always sits next to what failed (a tile, a row, the action that caused it) and offers **Try Again** or the relevant escape when one exists. This replaces the bare red line at the bottom of a screen (inventory N4).

### 4.8 Confirmation dialogs

Nothing leaves its place without one. Five variants, one component. Copy is the prototype's.

| Variant | Title | Body | Buttons |
|---|---|---|---|
| **trash** | "Move **N** items (**size**) to the Trash?" | "You can put them back from the Trash in Finder until you empty it." + optional "System Caches are included: macOS will ask for your password once." + item list | **Move to Trash** (prominent) · **Review Items…** (only when opened from `results`) · **Cancel** |
| **cloud** (server delete) | "Delete **N** files from Google Drive?" | "These files are deleted on Google Drive's servers, not moved to the Trash on this Mac. You can restore them only from Google Drive's own trash, and SOS Mac can't undo this." + list + checkbox **"I understand these files are deleted on Google Drive."** | **Delete from Google Drive** (danger, disabled until the checkbox is ticked) · **Cancel** (prominent) |
| **uninstall** | "Move **App** and **N** related items to the Trash?" | "Quit «App» first if it's open. You can put everything back from the Trash in Finder." + App Store note when applicable + list | **Move to Trash** (prominent) · **Cancel** |
| **quarantine** | "Quarantine **N** items?" | "SOS Mac moves it to a folder where it can't run. You can restore it from the Quarantine list at any time." + list | **Quarantine** (prominent) · **Cancel** |
| **cleanup list** (Space Lens) | "Move **N** items to the Trash?" | "Uncheck anything you want to keep. You can put items back from the Trash in Finder." + list **with checkboxes** + **Total** row | **Cancel** · **Move to Trash** (prominent, disabled when the list is empty) |

- **Item list:** the first 5 items (name + size) and, if more, "and **N** more items" with their combined size. Both numbers are real.
- **CF-1 — Cancel is the default button** in every variant. Return and Enter never trigger a removal.
- **CF-2 — Presentation:** a macOS sheet (system modal), not a hand-drawn overlay. The prototype draws the dialog inside the window with a scrim; a sheet gives keyboard trapping, Escape and VoiceOver semantics for free, and gets the system material automatically. Visual spec (width 300 / 380, icon tile 52, `bgElevated`, `Elevation.float`) as in the prototype. OD-4.
- **CF-3 — The count and size in the title are the same numbers the list and the review bar show**, computed once by the view model.

### 4.9 Start, scanning, done, empty and error views

| View | Spec |
|---|---|
| **Start** | Two columns 320 / 1fr, gap 48, padding 24/56. **Orb** 260: radial hue at 28 % + a conic hue at 22 % with an indigo segment; a 1 pt ring at 35 % hue (inset 34); glyph tile 116 (radius 30) filled hue 90 % / white → hue 70 % / `#1E1B4B`, symbol 56 (light: radial hue at 16 % over white only). Eyebrow: 6 pt hue dot + module name. Title `display`. Lede 14/1.5 `textSecondary`, ≤ 520 wide. Up to three bullets (28 pt icon tile, `headline` title, `callout` text). Optional note (`info.circle`). Free slot below. |
| **Scanning** | Two columns 300 / 1fr, gap 40. Orb 240 with a `neonCyan` sweep (55 % conic, ring mask, 2.4 s). Eyebrow "Scanning" with a cyan dot. Title `title1`. Steps, progress, path. |
| **Step row** | Padding 8/12, radius 9; active row on `card` + `hairline`. Dot 18: pending (1.5 pt `hairlineStrong` ring) · active (`neonCyan` ring + 3 pt cyan halo at 18 % + a 6 pt dot pulsing every 2.4 s) · done (`success` disc, check in `bgBase`) · failed (`danger` ring, `xmark`). |
| **Progress** | Determinate only when a total is known; otherwise a count line ("Scanned 1.694.000 items…"). This is today's `ScanProgressPanel` behaviour and stays. |
| **Done** | Card radius `xl`, padding 28/32, standard material (content layer), `hairline`, `Elevation.raised`. Orb 180 with an 88 pt glyph in a `neonLime` gradient. Eyebrow with a lime dot. Title `title1`. Stats (gap 28): label `callout`, value `numeralL`, the bytes in `neonLime`. Actions. Hint: "Everything is in the Trash. To undo, open the Trash in Finder and choose Put Back." Free slot for a failure banner or the quarantine panel. |
| **Empty / Error** | Centred. Icon tile 72 (radius 20, `card`, `hairline`): `neonLime` glyph for "all clear", `danger` for an error, `textSecondary` otherwise; symbol 32. Title `title1`. Text 14/1.5 `textSecondary`, ≤ 440. Centred actions. |

**Aurora background** (replaces `.auroraBloom()`): two non-interactive radial gradients behind the content — the module hue at `Glow.auroraAlpha` (50 % × 60 % at 30 % 10 %) and indigo `#6366F1` at `Glow.auroraAlpha` (40 % × 50 % at 85 % 0). It is how the module hue finally reaches the content area (inventory V6).

---
## 5. Screens and the menu bar

For each screen: what changes, then the state table — **lifecycle state → target `Phase` → what is shown**. "Target `Phase`" is normative: case names are the contract the shared frame maps from. Every figure named below has a source in §6.4.

### 5.1 Dashboard — no lifecycle (a launcher)

Today: one static hero ("Pick a module, or run Smart Care"), 8 module cards whose stat lines are placeholders ("Not scanned this session"), "Run Smart Care" only navigates (inventory N3, D6).

New (`?screen=dashboard`):

| Element | Spec |
|---|---|
| Hero | Eyebrow **Smart Care** · title **"Clean up junk and duplicates in one pass"** · lede "Smart Care finds caches, old logs and duplicate files, then shows you everything before anything moves." · **Run Smart Care** (prominent, large) → opens Smart Care **and starts the scan**. Right column: volume name, "«free» free", storage meter, "«used» used of «total»", **Open Space Lens** (plain). |
| Snapshot | Three tiles: **Load average (1 min)**, **Memory in use**, **Thermal state**, each captioned **"Read when this page opened"**. One-off reading, as today. |
| Module cards | Section **Clean**: Junk & Cache, Duplicate Finder, Space Lens, Cloud Cleanup. Section **Manage · Speed · Protect**: Uninstaller, Updater, Performance, Protection. Card: 34 pt hue tile + name + one-line description + chevron. No placeholder stat lines. The Performance card repeats the snapshot's load and memory figures without a "live" dot. |

Not shown, on purpose: health score or dial, "last scanned" stamps, per-module status (inventory §4.1, §4.4; live numbers are on the needs-engine-work list).

### 5.2 Smart Care

Today: `.idle → .scanning → .review → .cleaning → .summary`; duplicates are flattened, the keep copy is not protected (S4); no Stop button (N6); a failed module still ends in "Nothing found".

Target `Phase`: `idle · scanning · results · review · cleaning(selectedCount:) · done(movedBytes:, movedCount:, failedCount:) · failed(message:)`.

| Lifecycle | Phase | What is shown |
|---|---|---|
| `start` | `idle` | "Junk and duplicates, in one pass" · three bullets: **Junk & Cache** ("3 locations, no extra permission"), **Duplicate files** ("The newest copy is always kept"), **Health check** ("Read-only") · note: the duplicate pass reads every file in the Home folder and can take a few minutes · **Scan** |
| `scanning` | `scanning` | "Looking for junk and duplicates…" · steps **Junk & Cache** (Waiting… / Scanning… / Found N), **Duplicate files**, **Health check** (done, "Read") · aggregate progress when every running module reports one · **Stop** (N6) |
| `results` | `results` | "Here's what Smart Care found" · tiles **Junk & Cache** ("«sel» selected of «found» · N files in 3 locations"; "N safe selected", "N need a look"), **Duplicate files** ("selected · N sets, N extra copies"; badge "Newest copy kept"), **Health check** (full) · dock: Review Items… · **Clean** · Scan Again |
| `review` | `review` | Two sections in the groups column: **Junk & Cache** (by rule) and **Duplicate files** (by set). Kept copies are locked (§4.6) — fixes S4. |
| `cleaning` | `cleaning` | "Moving **n of N** items to the Trash…" |
| `done` | `done` | "«bytes» moved to the Trash" · stats Moved to Trash / Items / Couldn't move · failure banner per failed group · Open Trash · Scan Again |
| `empty` | `results` with nothing found and no failure | "Nothing to clean" · Scan Again · health tile |
| `error` (partial) | `results` with a failed module | "Smart Care finished with a problem" · banner **"Couldn't finish the duplicate scan"** with the engine's reason and **Try Again** · the failed tile is skipped ("Scan stopped", badge "Failed") |
| `error` (full) | `failed` | "Smart Care couldn't start" · Try Again |

- Pre-selection is unchanged: junk that is `safe` and needs no helper; every duplicate except the newest copy.
- The review model keeps `groupID` and `isRecommendedKeep` per item (the engine's `DuplicateGroup` already carries `recommendedKeepPath`).
- Scan scope is unchanged: 3 helper-free junk rules + an exact-duplicate pass over the whole Home folder.

### 5.3 Junk & Cache

Today: `.idle → .scanning → .results` (a flat per-file list) `→ .cleaning → .done`; "Clean" is blue while the same action is red elsewhere (V1); "Done" returns to the results.

Target `Phase`: `idle · scanning · results · review · cleaning(selectedCount:) · done(movedBytes:, movedCount:, failedCount:) · failed(message:)`.

| Lifecycle | Phase | What is shown |
|---|---|---|
| `start` | `idle` | "Clear caches and old logs" · one bullet per rule with its root path (`~/Library/Caches`, `~/Library/Logs`, `~/Library/Application Support`, `/Library/Caches`) · note "System Caches need your approval. They're never selected for you." · **Scan** |
| `scanning` | `scanning` | "Looking for junk files…" · four step rows in scan order · "**k** of 4 locations" + % · current path · **Stop** |
| `results` | `results` | "«size» of junk found" · "N files in 4 locations · «size» selected (safe files only)" · one wide tile per location ("N files · «root»"; foot "N selected" + "N caution", or "Needs approval · not selected") · dock: Review Items… · **Clean** · Scan Again |
| `review` | `review` | Groups = the four locations. Helper locations show the banner **"Needs your approval — Moving these uses the SOS Mac helper. macOS asks for your password once."** (S7). Detail: Rule, Location, Size, Safety, explanation. |
| `cleaning` | `cleaning` | "Moving **n of N** files to the Trash…" + path |
| `done` | `done` | "«bytes» moved to the Trash" · stats · **Open Trash** · **Scan Again** (replaces "Done → results") |
| `empty` | `results` with zero items | "No junk found — Your caches and logs are already clear in all 4 locations." · Scan Again |
| `error` | `failed` | "The scan stopped" + the engine's reason · Try Again |

- Pre-selection unchanged. Helper items are moved by the privileged helper exactly as today, never by `Cleaner.clean`.
- **Ignore** (today's per-row action, saved in SwiftData) has no place in the prototype. OD-8 proposes keeping it as a plain button in the detail panel.
- The prototype's Junk error copy ("needs your approval to read /Library/Caches… Show Results for 3 Locations") is **not used**: the scanner skips unreadable roots and only throws on cancellation or a walker error (§6.3).

### 5.4 Duplicate Finder

Today: `.idle → .scanning → .results → .done`; no review and no `.cleaning` phase, so "Clean" stays enabled while files move (S5); the mode picker says "Exact Duplicates / Similar Images".

Target `Phase`: `idle · scanning · results · review · cleaning(selectedCount:) · done(movedBytes:, movedCount:, failedCount:) · failed(message:)`, plus `mode`.

| Lifecycle | Phase | What is shown |
|---|---|---|
| `start` | `idle` | Toolbar segment **Exact copies / Similar images**. "Find identical copies" (or "Find similar images") · bullets: **The newest copy is kept**, **Copies go to the Trash** · note on hashing time · **Scan**. In Similar mode the banner **"Similar isn't identical"** is shown (S3). |
| `scanning` | `scanning` | "Scanning for duplicates…" → "Hashing files…" · steps: **Find files with the same size** (files counted), **Compare contents** · bar + % only once hashing starts · current path · **Stop** |
| `results` | `results` | "N sets of identical files" (or "of similar images") · "The newest copy in each set is kept." · tiles **Sets found** ("N files in total"), **Selected** ("N extra copies"; badge "N kept") · banner **"N files were skipped"** when `skippedCount > 0` · dock: Review Items… · **Clean** · Scan Again |
| `review` | `review` | One section (Identical sets / Similar images); groups = sets ("N copies · «size» each"); detail: Location, Size, Date modified + "An extra copy." or "Kept automatically." |
| `cleaning` | `cleaning` | "Moving **n of N** copies to the Trash…" — new phase with a re-entrancy guard (S5) |
| `done` | `done` | "«bytes» moved to the Trash" · stats Moved to Trash / Copies / Kept · Open Trash · Scan Again |
| `empty` | `results` with no set | "No duplicates found" · Scan Again |
| `error` | `failed` | "The scan stopped" · the reason names Privacy & Security › Full Disk Access (button only if OD-18 = 2) · **Try Again** |

- Pre-selection is today's rule in Exact mode. For Similar Images see OD-a.
- Per-set totals ("2 extra copies · 1.3 GB" in the group header) are derivable from existing sizes: OD-b.
- Thumbnails, similarity scores and location pills are not in v1 (engine / inventory §4.4).

### 5.5 Space Lens

Today: `.idle → .scanning → .loaded → .reviewing → .cleaning → .done`; a rainbow treemap unrelated to the theme (V7, V9); no selection highlight; "Open Folder" drills in; the review sheet has no checkboxes; no way back to the map after "done" (N7); no busy feedback while cleaning (N5).

Target `Phase`: `idle · scanning · results · review · cleaning(selectedCount:) · done(movedBytes:, movedCount:, failedCount:) · failed(message:)`, plus `viewMode`, the current path and the cleanup list.

| Lifecycle | Phase | What is shown |
|---|---|---|
| `start` | `idle` | "See what fills your disk" · source list: **Home** ("~ · recommended"), **Choose Folder…** ("Any folder you can open"), one row per external volume (name + path) · **Scan** |
| `scanning` | `scanning` | "Mapping your Home folder…" · "The total isn't known until the scan ends, so there's no percentage." · "Scanned N items…" · current path · **Stop** |
| `results` | `results` | Breadcrumb · segment **By Folder / By Type** · treemap · legend · inspector · review bar ("Scanned **N** items in «root name»" · selection · **Review…**) |
| `review` | `review` | The **cleanup list** sheet with checkboxes and a Total row (§4.8) — replaces the checkbox-less sheet |
| `cleaning` | `cleaning` | "Moving **n of N** items to the Trash…" + path |
| `done` | `done` | "«bytes» moved to the Trash" · stats · **Back to Map** (prominent) · Open Trash · Scan Again |
| `empty` | `results` with an empty folder | "This folder is empty — «path» has no files in it." · Choose Folder… |
| `error` | `failed` | "Couldn't read «name»" + the engine's reason · **Scan Again** · **Choose Another Folder** |

Treemap and inspector:

- Squarified layout from `TreemapKit`. Cells use the `treemap1…8` ramp in size order; the **By Type** cells mix each type's hue 42 % into `card` (`treemapMix`). Cells are separated by a 1 pt `bgBase` line, radius 3.
- A cell shows its name (12 semibold `treemapText`) and size (11) when it is at least 90 × 40; only the name when at least 60 × 22.
- Items below 0.4 % of the scanned total are merged into one "**N smaller items**" cell (real count and size) on `treemap8`; its detail says "Too small to draw. Open the folder in Finder to see them."
- **Selection is visible:** a 2 pt inset ring in `neonMagenta` (violet in Palette C) with glow; items in the cleanup list show an 8 pt dot top-right. Hover lightens (dark) or darkens (light). Legend: "Area is size. Shades only tell neighbours apart." + "In cleanup list".
- Click selects; double-click drills into a folder. The inspector: Size, Kind, Contains, Modified, Path; **Show Contents**; **Add to Cleanup / Remove from Cleanup**; the existing ineligibility reasons, and for a protected location: "Can't be cleaned here. Library holds settings and data that apps need. Use Junk & Cache or Uninstaller for files inside it."
- Nothing is pre-selected. The list keeps only the top-most selected item (unchanged).
- The treemap is one accessibility element per cell: label "«name», «size»", trait "button", sorted in size order.
- Reveal in Finder, search and "% of disk" are not in v1 (needs-engine-work).

### 5.6 Cloud Cleanup

Today: no `Phase` (Booleans per provider); three tabs can never connect but look like full peers (D5); rows delete on one tap (S2); after an iCloud "Trash" the list does not change (S6).

Target `Phase` per provider: `notConfigured · idle · scanning · results · review · cleaning(selectedCount:) · done(movedBytes:, movedCount:, failedCount:) · empty · failed(message:)`.

| Lifecycle | Phase | What is shown |
|---|---|---|
| (no lifecycle) | `notConfigured` | Providers column: **iCloud Drive** ("Local scan"), **Google Drive / Dropbox / OneDrive** ("Not set up in this build"). Selecting one shows "«Provider» isn't set up in this build" + "Connecting «Provider» needs a registered sign-in app, which this build doesn't have yet. iCloud Drive works now with a local scan." · disabled **Connect «Provider»** · **Use iCloud Drive** |
| `start` | `idle` | Info banner **"Local scan — Reads iCloud Drive files that are already downloaded to this Mac. Files only in the cloud aren't checked."** · "Find duplicates in iCloud Drive" · **Scan** |
| `scanning` | `scanning` | "Checking iCloud Drive…" · "N files listed" · current path · **Stop** |
| `results` | `results` | "N sets of duplicate files" · "N files listed · newest copy kept in each set" · tiles **Sets found**, **Selected** ("go to the Trash on this Mac") · dock: Review Items… · **Clean** · Scan Again |
| `review` | `review` | Sets with kept copies locked; Select All / Deselect All |
| `cleaning` | `cleaning` | "Moving **n of N** copies to the Trash…" |
| `done` | `done` | "«bytes» moved to the Trash" · "iCloud removes these copies from your other devices once you empty the Trash." · Open Trash · Scan Again |
| `empty` | `empty` | "No duplicates in iCloud Drive — N files listed. Every file that's on this Mac is unique." · Scan Again |
| `error` | `failed` | "iCloud Drive isn't available — Sign in to iCloud in System Settings and turn on iCloud Drive, then scan again." (button only if OD-18 = 2) · **Try Again** |

Server-side delete (design target, `?screen=cloud&state=drive`):

- Results are a list of sets with **nothing selected**; the banner **"Deleting here is not Move to Trash — Files go to Google Drive's own trash, on Google's servers. SOS Mac can't undo it."** sits above; the CTA is **Delete from «Provider»…** (danger).
- It opens the **cloud** confirmation (§4.8): acknowledgement required before the button enables.
- **Reachable in v1: iCloud Drive only**, because the OAuth apps are not registered. The confirm flow is still implemented on the existing Drive / OneDrive / Dropbox delete paths and unit-tested with a fake provider, so it is safe the day OAuth lands.
- iCloud Drive uses the **local** Trash confirmation, like every other local flow (fixes S2 for iCloud).
- After a move, groups are recomputed and failures are reported (fixes S6).
- iCloud pre-selection: the prototype pre-selects every extra copy; today nothing is selected. Widening pre-selection is a product decision: OD-7.
- Quota bars, folder browser and the connect flow are not in v1 (engine).

### 5.7 Uninstaller

Today: `browsing / inspecting(bundleID) / removed`; busy state lives in flags (A1); sizes of associated folders are wrong (D1); a failed per-row Inspect shows nothing (N4); no confirmation; no running-app check (S8).

Target `Phase`: `browsing · inspectingAll(currentBundleID:) · measured · reviewing(bundleID) · cleaning(appName:, selectedCount:) · removed(appName:, atLeastBytes:, itemCount:, failedCount:)`, with a per-row `inspectError` for failed rows.

| Lifecycle | Phase | What is shown |
|---|---|---|
| `start` | `browsing` | Banner **"Pick an app to see what it left behind"** · app rows (tile, name, version, App Store badge, size "—", **Inspect**) · dock: "Sizes appear after an app is inspected" · **Measure All** |
| `scanning` | `inspectingAll` | Progress tile "Inspecting «App»…" + "**k** of N apps" + % · rows fill their size in as they finish · **Stop** |
| `results` | `measured` | Rows with sizes and **Review** · dock: "Choose an app to review what it left behind" · **Review** · **Measure Again** |
| `review` | `reviewing` | Two columns. Left: app tile, name, App Store badge, Version, Bundle ID, Location, **Size "At least …"**, "App and files. N folders not measured yet.", "Quit «App» first if it's open." Right: items (badge **App** / **Associated**; folders read **"Folder"**, not a size) · review bar "**N items** · **at least «size»** selected" · **Move to Trash…** → the **uninstall** confirmation |
| `cleaning` | `cleaning` | "Moving **n of N** items to the Trash…" + path |
| `done` | `removed` | "«App» moved to the Trash" · stats: **At least** «size», Items · Open Trash · **Back to Apps** |
| `empty` | `browsing` with no apps | "No apps found — There are no apps in /Applications that SOS Mac can remove. Apps that came with macOS aren't listed." · Check Again |
| `error` | `measured` / `reviewing` with `inspectError` | Row or detail banner **"Couldn't inspect «App»"** + the reason · **Try Again** — fixes the invisible failure |

- **D1 mitigation:** associated folders report the size of the directory entry, not their content, until the engine fix lands. The UI therefore labels them **"Folder"** and every total that includes one reads **"At least …"**. No number is shown that the engine does not back.
- Pre-selection unchanged: everything an inspect finds is selected.
- Real app icons instead of letter tiles: OD-12. Running-app check before the dialog: OD-9. A working search field instead of the prototype's static box: OD-13.
- "Last used", bulk table and leftover confidence are not in v1 (inventory §4.4).

### 5.8 Updater — read-only

Today: no `Phase`; rows are 90 pt cards; a failed feed check shows "Up to date" in green (D3); the check runs on every visit.

Target `Phase`: `idle · checking · results · empty · failed(message:)`, with a per-row `checkError`.

| Lifecycle | Phase | What is shown |
|---|---|---|
| `start` | `idle` | "See which apps have updates" · bullets: **Apps with an update feed**, **App Store apps** ("Opens the App Store so you can update there.") · **Check** |
| `scanning` | `checking` | Progress tile "Checking «App»…" + "**k** of N apps" + % · rows show "Checked" or a spinner · **Stop** |
| `results` | `results` | Subtitle "N updates available" · groups **Updates available** ("1.2.3 → 1.2.4", badge), **Update in the App Store** (button **View in App Store**), **Up to date** (badge), **No update feed** (badge "Can't check") · dock: "N apps checked" · **Check Again** |
| `empty` | `empty` | "All apps are up to date — N apps checked. None has a newer version in its update feed." · Check Again |
| `error` | `failed` / per-row `checkError` | Whole check failed: "Couldn't check for updates" + Try Again. One feed failed (OD-10): badge **"Couldn't check"** and a banner with Try Again |

- No review, cleaning or done: nothing is installed.
- "Update All", release notes, update size and an install button are not in v1.

### 5.9 Performance — no scan lifecycle

Today: no `Phase`; messages appear at the bottom of a long page; "Run" has no busy state; Memory reads ~99 % in amber (D2); the thermal state is shown twice (C7).

Target: `metrics: .live / .unavailable` and, per maintenance action, `ActionState: idle · running · needsApproval · succeeded · failed`.

| Section | Spec |
|---|---|
| Toolbar | "Performance" · subtitle **Live** or **No data** |
| unavailable | Error banner **"Couldn't read system metrics"** + "macOS didn't return CPU or memory data. Values show '—' until the next read." · **Try Again**. Every value is "—". |
| Metric grid | **CPU** (numeral + % + meter; "Updates while this screen is open") · **Memory** (2 columns: "X GB in use of Y GB"; segmented bar **Wired · Active · Compressed · Inactive · Free**; legend with each value) · **Thermal state** (dot + word; "As reported by macOS") · **Load average** (1 / 5 / 15 min) · table: Swap used, Architecture, Running since |
| Maintenance | Rows **Free up RAM**, **Flush DNS Cache** with **Run** (disabled + spinner "Running…" while it runs). Result is an inline banner under the row: `info` "Approve the SOS Mac helper" + **Open System Settings**; `ok` "Free up RAM finished"; `err` "Couldn't flush the DNS cache" + **Try Again** |
| Widget and login | Card **Menu bar widget** ("CPU and memory in the menu bar." · **Open Menu Bar Widget**). Card **Open at login** (switch) + the launch agents list |

- Segment colours: the prototype hardcodes Palette A purples. In C the segments are `primaryDeep`, `primary`, `primaryBright`, `primaryBright` at 40 %, and Free (no fill, `hairlineStrong` outline). `[D]`
- "Memory in use" follows OD-11.
- The switch registers the **main app** at login today. The prototype's copy ("Start the menu bar widget when you log in") is not what the engine does: OD-14.
- Polling only while the screen is visible is unchanged.

### 5.10 Protection

Today: `.idle → .scanning → .results → .quarantining → .summary`; the quarantine list is outside any scroll view (N8); "Check VirusTotal" does nothing without an API key.

Target `Phase`: `idle · scanning · results · review · quarantining(selectedCount:) · done(quarantinedCount:, failedCount:) · failed(message:)`, plus `isShowingQuarantine`.

| Lifecycle | Phase | What is shown |
|---|---|---|
| `start` | `idle` | Disclaimer **"Protection checks files against known malware signatures when you run a scan. It isn't real-time antivirus."** · "Check for known malware" · "Scans 6 places where unwanted software usually hides. Anything found is quarantined, never deleted, so you can restore it." · the six location names · quarantine panel when it has entries · **Scan** |
| `scanning` | `scanning` | "Checking files…" · six step rows · "**n** of **N** files" + ETA (existing tracker) · current path · **Stop** |
| `results` | `results` | Tiles **Known threats** (rose tile; "«file» in «folder»"; badge with the detection method), **Already in quarantine** ("Restorable at any time") · dock: "Review the finding, then quarantine it" · **Review** · Scan Again |
| `review` | `review` | Findings group · detail: Detection, Identifier, Found, Path, Size + "Quarantine is reversible." · **Quarantine…** → the **quarantine** confirmation |
| `cleaning` | `quarantining` | "Moving **n of N** items to quarantine…" |
| `done` | `done` | "**N items** quarantined — It can't run from quarantine. Restore it if it was a mistake." · stats Quarantined / In quarantine · Scan Again · quarantine panel |
| sub-screen | `isShowingQuarantine` | Toolbar back button **Protection** · **Quarantine** panel: "N items · restorable"; rows (name, "From «path»", date, **Restore**) inside a scroll view |
| `empty` | `results` with no finding | "No known threats found — N files checked in 6 locations." · Scan Again |
| `error` | `failed` | "The scan stopped" + the engine's reason · **Try Again** |

- Nothing is pre-selected (unchanged). Quarantine stays a reversible move with a persisted record.
- "Check VirusTotal" is removed: it silently does nothing without an API key (OD-15).
- The prototype's error copy "4 of 6 locations were checked" is **not used**: the engine does not report how many locations completed (§6.3).
- Scan types, real-time protection, coverage and database version are not in v1.

### 5.11 Menu bar helper

Today: no theme; the label changes width ("SOS Mac" → "CPU 42 %"); a 220 pt panel with three text lines and Quit; no way back to the app.

New (`?screen=performance&pop=1`):

| Part | Spec |
|---|---|
| Menu-bar item | Symbol + fixed-width label **"CPU «n» %"** (monospaced digits) after the first sample; "SOS Mac" before it |
| Popover header | Hue tile (Performance) + **SOS Mac** + "Updates every 2 seconds" |
| Cards | **CPU** (numeral + % + meter) · **Memory** (percent + "«used» of «total»") |
| Actions | **Open SOS Mac** (⌘O) · **Quit Widget** (⌘Q) |

- "Open SOS Mac" launches or activates the main app (`com.nextlabs.sosmac`).
- The helper shares the token files with the app (plan PR 15); it does not hand-roll colours.
- Only CPU and memory are shown — the two figures the helper has (inventory §4.1).

---
## 6. Safety and data fixes shipped with the UI

The redesign shows states today's UI cannot reach honestly. These fixes are part of the migration, in the screen PR that needs them. IDs are the inventory's (§5).

### 6.1 Safety

| ID | Fix | Behaviour |
|---|---|---|
| **S1** | **Confirmation before every removal.** | Every local Trash action opens the **trash** dialog (§4.8): Smart Care, Junk & Cache, Duplicate Finder, Space Lens, Uninstaller, iCloud Drive. Protection opens the **quarantine** dialog. Space Lens's cleanup list keeps its checkboxes. Cancel is the default button. |
| **S2** | **Cloud rows no longer delete on a tap.** | Selection → review → confirm. Server-side deletes use the **cloud** dialog with a required acknowledgement. |
| **S3** | **Similar Images warns before anything is selected.** | Banner "Similar isn't identical — There's no preview or similarity score yet, so check each image before you move it." on Start, Results and Review. Pre-selection itself: OD-a. |
| **S4** | **Smart Care protects the keep copy.** | Duplicate items are grouped by set; the newest copy by modified date is locked with the Keep badge (§4.6) and can never be selected. |
| **S5** | **Duplicate Finder gets a `cleaning` phase.** | "Clean" is replaced by the disabled "Moving" CTA while files move; `clean()` gets a re-entrancy guard; failed items are counted and shown on Done. |
| **S6** | **Cloud results stay true after a delete.** | Groups are recomputed after every removal (iCloud included) and `failed` is reported on Done, for every provider. |
| **S7** | **The helper is explained before it is used.** | Junk items that need the privileged helper carry the badge **"Needs approval"** (replacing "Needs Helper"), the banner "Needs your approval — Moving these uses the SOS Mac helper. macOS asks for your password once.", and the extra line in the Trash dialog. |
| **S8** | **Running-app check before uninstalling.** | OD-9. If accepted: when the selected app is running, the uninstall dialog shows **"Quit «App» first"** with **Quit** and **Cancel**, using `NSRunningApplication.runningApplications(withBundleIdentifier:)`. |
| **N3** | **"Run Smart Care" runs.** | The Dashboard button opens Smart Care and starts the scan. |
| **N5** | **Busy feedback while cleaning.** | Real, count-based progress: "Moving **n of N** items…" + current path (§6.5). |
| **N6** | **Smart Care can be stopped.** | Stop button in the dock during scanning. |
| **N7** | **Space Lens review is usable.** | Double-click drills in; the cleanup list has checkboxes; Done offers **Back to Map**. |
| **N8** | **The quarantine list scrolls.** | The list lives in a scroll view in Start, Done and the Quarantine sub-screen. |
| **N4** | **Errors sit next to their cause.** | Banners replace the bare red line; each has Try Again or the relevant escape; a failed Inspect is visible (Uninstaller). |

### 6.2 Data shown in the UI

| ID | Fix | Behaviour |
|---|---|---|
| **D1** (mitigation) | **Uninstaller sizes are honest until the engine is fixed.** | An associated item whose `kind` is `.directory` reads **"Folder"**; totals that include one read **"At least …"**; the detail says "App and files. N folders not measured yet." |
| **D2** | **Memory "in use".** | OD-11: count wired + active + compressed as in use (inactive and free as available). Needs a small CleanCore change with a test. |
| **D3** | **A failed update check no longer reads "Up to date".** | OD-10. `UpdaterViewModel.checkSingle` already receives the error and drops it; recording it per row is app-only. |
| **D4** | **Protection stops over-promising.** | "Check VirusTotal" is removed (OD-15). Copy says "known-signature scan". No coverage, version or real-time claims. |
| **D5** | **Three of four Cloud tabs stop pretending.** | They read "Not set up in this build" with a disabled Connect and a path to iCloud Drive. |
| **D6** | **Dashboard cards stop showing placeholders.** | "Not scanned this session" lines are gone; only real one-off figures remain, labelled as such. |

### 6.3 Prototype copy that the engine cannot back (corrected, not copied)

| Screen | Prototype shows | Why it cannot be shipped as drawn | Spec |
|---|---|---|---|
| Junk & Cache · error | "Couldn't scan System Caches — SOS Mac needs your approval to read /Library/Caches. The other 3 locations weren't affected." + "Show Results for 3 Locations" | `JunkScanner.scan` skips unreadable roots and throws only on cancellation or a walker error; the helper is a *clean-time* need (S7), not a scan-time failure | Generic, truthful error: "The scan stopped" + the engine's reason + Try Again |
| Protection · error | "SOS Mac couldn't read System Daemons. 4 of 6 locations were checked and nothing was found there." | The scanner does not report how many locations completed | "The scan stopped" + the engine's reason + Try Again |
| Performance · login | "Open at login — Start the menu bar widget when you log in." | The switch registers the **main app** as a login item (`LoginItemsManager.registerMainAppAsLoginItem`); the helper is not auto-launched | OD-14 |
| Uninstaller · sizes | (annotation "Needs engine work · D1") | Annotation, not UI | Never shipped; the D1 labels in §6.2 are |
| Updater | (note "A failed check currently looks like 'Up to date' (D3)…") | Annotation, not UI | Never shipped; the failed state is OD-10 |
| Cloud · Drive | Ribbon "Design target · needs a registered sign-in app" | Annotation, not UI | Never shipped |
| Dashboard | Pulsing "live" line on the Performance card | The Dashboard reads metrics once | Same figures, no "live" dot, captioned "Read when this page opened" |
| Smart Care · start | "3 locations, no extra permission" | True for the privileged helper; macOS may still ask for access to Desktop, Documents or Downloads during the Home scan | Keep, and add to the note: "macOS may ask for access to Desktop, Documents or Downloads the first time." |

### 6.4 Every figure the new UI shows, and where it comes from

Rule: if a figure is not in this table, it is not shown.

| Figure | Source (existing unless marked) |
|---|---|
| Bytes, "selected of found", "N files in N locations" | item sizes and `sourceLabel` per module |
| "N sets", "N extra copies", "N kept", "N files were skipped" | `DuplicateGroup`s, `recommendedKeepPath`, `skippedCount` |
| Health: load, memory, thermal | `PerformanceSnapshot` (one-off) |
| Cleaning "n of N" + current path | per-item progress (§6.5) — **new** |
| Done: moved bytes, items, "Couldn't move" | `CleanResult.succeeded` / `.failed` / `reclaimedBytes` |
| Dialog: "N items (size)", "and N more items" | the same selection the review bar shows |
| Uninstaller: "N applications installed", "k of N apps", "At least …", "N folders not measured yet" | `apps`, `associatedItems` (directories counted), inspect progress |
| Updater: "N updates available", "N apps checked", "x → y" | `rows` (`latestVersion`, `sparkleFeedURL`) |
| Space Lens: sizes, "Contains N items", Modified, "Scanned N items", "N smaller items" | `DisplayItem`, `ScanProgressTracker`, a sum over items below 0.4 % — **new** |
| Cloud: "N files listed" | `scanProgress.itemsProcessed` / `files.count` |
| Protection: "n of N files", ETA, "N items · restorable" | `ScanProgressTracker`, `quarantinedRecords` |
| Performance | `PerformanceViewModel` (unchanged fields; OD-11 for the memory definition) |
| Dashboard and sidebar footer: used, total, free | `VolumeStorageInfo` (`usedBytes`, `totalBytes`, `freeBytes`) |
| Volume name (sidebar footer, Dashboard hero) | **New:** `URLResourceKey.volumeNameKey` of the boot volume (documented API), added to `VolumeStorageInfo`. `VolumeStorageInfo` has no name today. |
| Dashboard snapshot | `PerformanceSnapshot` (one-off) |
| Menu bar | `MenuBarMetricsMonitor` |

Not shown anywhere: a health score, "last scanned", per-folder junk totals, a per-set similarity, cloud quota, database version.

### 6.5 Real cleaning progress

`Cleaner.clean(_:)` moves items one by one and returns a `CleanResult` without progress. To show "n of N" without touching the safety boundary, the view model **calls `Cleaner.clean([item])` once per selected item**, aggregates `succeeded` and `failed` itself, and reports `(index, item)` to the frame. Every delete still goes through the one extension method. Protection already loops per finding (quarantine). Junk helper items keep going through `privilegedHelperClient.trashSystemPath`, counted in the same total.

### 6.6 Results survive navigation (inventory N1)

| What is kept, per module, for the life of the app | What is not kept |
|---|---|
| Phase, scan results, selection, inspected sizes, updater rows, cloud provider states, Space Lens path and cleanup list | Scroll positions, the focused row, open dialogs |
| A running scan (it continues — OD-3) | Anything across app launches (no persistence is added) |

- Performance keeps polling only while visible. Updater and Uninstaller no longer reload on every visit.
- Each module refuses a second scan while one is running (existing guards; added where missing).
- Memory: results stay in RAM for the session. Junk can be large (100 k+ `ScanItem`s); that is the price of not rescanning and is accepted.

---

## 7. Materials

Verified 2026-11-26 against the macOS 27.0 SDK (Xcode 27.1) and Apple's documentation:

- `glassEffect(_:in:)`, `Glass` (`.regular`, `.clear`, `.tint`, `.interactive`), `GlassEffectContainer`, `glassEffectID` are **macOS 26.0+** and must sit behind `#available(macOS 26, *)`.
- `Material.regularMaterial` is macOS 12+, `accessibilityReduceTransparency` macOS 10.15+, `colorSchemeContrast` macOS 10.15+, `defaultSize(width:height:)` macOS 13+, `scrollEdgeEffectStyle(_:for:)` macOS 26+.
- HIG Materials: "Don't use Liquid Glass in the content layer"; "Use the regular variant when background content might create legibility issues, or when components have a significant amount of text, such as alerts, sidebars, or popovers"; "Standard components from system frameworks pick up the appearance and behavior of this material automatically"; "Use Liquid Glass effects sparingly."

Rules:

| Rule | Spec |
|---|---|
| **M1 — macOS 26+** | Liquid Glass (`.regular`) only on the functional layer: the system sidebar and toolbar (automatic), the dock / review bar, the menu-bar popover, and system-presented sheets and alerts. Wrapped in a `GlassEffectContainer` when several glass views sit together. |
| **M2 — macOS 14–15** | System materials: the sidebar keeps the system sidebar look (today's `.regularMaterial`; `NSVisualEffectView.Material.sidebar` semantics), the dock / review bar and popover use `.regularMaterial`. **Never** `glassEffect` outside an availability check. |
| **M3 — Reduce Transparency on** | Solid fills: `Theme.Color.sidebar` for the sidebar, `Theme.Color.glass` for floating bars and popovers, `Theme.Color.bgElevated` for dialogs. No blur, no glass. `AuroraSurface` (the Designer's modifier) already switches on `accessibilityReduceTransparency`. |
| **M4 — Content layer** | Cards, tiles, rows, banners, the treemap and the Done card use **no** Liquid Glass: solid `card` fill with `hairline` and `Elevation.raised`, or a standard material for the Done card and the Dashboard hero. |
| **M5 — Never `.clear`** | Nothing in v1 floats over media. If that changes, add the 35 % dark dimming layer HIG requires under clear glass over bright content. |
| **M6 — Tint** | Glass is colourless. The one tinted element in the chrome is the dock CTA, a solid `primaryDeep` fill, not a tinted glass. |
| **M7 — Verify on all three** | PR 2 and PR 4 check the sidebar, toolbar and dock on macOS 14 or 15 (if a machine is available), 26 and 27, each with Reduce Transparency and Increase Contrast on and off, in both appearances. |
| **M8 — Increase Contrast** | Hairlines switch to `hairlineStrong` when `colorSchemeContrast == .increased`. Separate high-contrast colour variants are not in v1 (OD-6). |

---

## 8. Accessibility, scale and performance

| Area | Rule |
|---|---|
| Control size | Every control has a hit target of at least **20 × 20 pt** (HIG minimum for macOS; default 28 × 28). Visual sizes may stay smaller (checkbox 16). |
| Labels | Icon-only buttons and tiles have an accessibility label. Rows read "name, state, size". The treemap exposes one button per cell. |
| Identifiers | `sidebar-nav-<label>` (existing), plus stable identifiers for the dock CTA, the review bar, dialog buttons and every row kind, so UI tests do not depend on layout. |
| Keyboard | Space / Enter toggles a focused row; arrow keys move in lists; Escape closes a dialog or sheet; Return never confirms a removal (CF-1 in §4.8). |
| Colour is never the only signal | Every status pairs colour with a symbol or word (badges, step dots, check discs). |
| Contrast | Audited with Accessibility Inspector in both appearances: body text ≥ 4.5:1, large / bold text and graphical objects ≥ 3:1. Rule T3 restricts `textTertiary`. |
| Motion | Reduce Motion turns off the orb sweep, the pulsing dot and glow breathing; spinners and progress rings stay (they carry state). |
| List scale | Virtualised lists (`List`) for every potentially long list. No per-row blur, shadow or glass. The treemap draws at most a few hundred cells; the rest goes to the "smaller items" cell. |
| Keep rendering cheap | The aurora background and glows are static layers; animations run only while a state is on screen. |
| Concurrency | View models stay `@MainActor @Observable`; engine types stay `Sendable`. Nothing in `App/` calls `sysctl`, `IOKit` or `Process` directly. |
| Localisation | Out of scope: strings stay in code, in English. |
| Documented APIs only | "Open System Settings" buttons use a documented API where one exists; see OD-18 for the two panes that have none. |

---
## 9. Non-goals

Everything on `needs-engine-work.html` and inventory §4.4 stays out, except the items the brief pulls in and the app-only items Phương accepts in §10. Disposition of each needs-engine-work item:

| Item (needs-engine-work) | Kind | Disposition |
|---|---|---|
| Keep results when you leave a screen (N1) | app | **In scope** (§6.6) |
| Uninstaller: real folder sizes (D1) | engine | **Out.** UI mitigation in scope (§6.2) |
| Updater: "check failed" state (D3) | listed as engine | **Open — OD-10.** App-only in fact (§6.2) |
| Uninstaller: app is running (S8) | app | **Open — OD-9** |
| Duplicates: thumbnails and similarity | engine | **Out.** Banner in scope (S3) |
| Duplicates: total per set | product call | **Open — OD-b** |
| Junk: totals per folder and per category | engine | **Out.** Review groups by rule only |
| Space Lens: Reveal in Finder, search, % of disk | app | **Out** (per brief) |
| Cloud: Google Drive, OneDrive, Dropbox | engine | **Out.** Honest "not set up" states and the confirm flow are in scope |
| Protection: real coverage | engine | **Out** |
| Dashboard: live numbers | app | **Out.** One-off snapshot, labelled |
| Not designed on purpose (§4.4 list below) | — | **Out** |

Inventory §4.4, restated: health dial / health score · recent-activity feed · "last scanned" stamps · junk category checklist · Uninstaller bulk table with size / last-used columns · Updater "Update All" · Duplicate Finder location pills · Protection scan-type chooser and real-time toggle · Cloud quota bars and folder browser · Performance disk / network sparklines and process / login-item tables · Settings screen · onboarding and paywall.

Also out: localisation; menu-bar auto-launch; a per-module status or badge in the sidebar beyond the busy dot (OD-3); persistence across launches; any CleanCore scanner change.

---

## 10. Decisions — settled by Phương, 2026-11-26

> **Status: Decided.** Phương reviewed this spec on 2026-11-26 and accepted every recommendation below (OD-1 → OD-18, OD-a, OD-b). The accepted option is now the decision, not a default. The original options and rationale are kept below for the record.
>
> **OD-1 note:** PR 1 implements with the derived `[D]` light values exactly as tabulated in §2.3–2.4. The Designer's final Palette C light values replace them before PR 1 merges into the integration branch (coordination via Zed).

| Item | Decision (Phương, 2026-11-26) |
|---|---|
| OD-1 | (1) Report's C light + the derived `[D]` values; Designer's final light values replace them before PR 1 merges |
| OD-2 | (1) Real macOS window toolbar |
| OD-3 | (1) Scan keeps running; sidebar shows a cyan busy dot |
| OD-4 | (1) macOS sheet for confirmations |
| OD-5 | Minimum window 960 × 600 |
| OD-6 | (1) No separate high-contrast variants |
| OD-a | (2) Similar Images: nothing pre-selected |
| OD-b | (1) Show the total size of each duplicate set |
| OD-7 | Nothing pre-selected in iCloud Drive |
| OD-8 | Keep Junk "Ignore" |
| OD-9 | Include the running-app check before uninstalling |
| OD-10 | (i) Include the failed-check state; (ii) explicit Check button only |
| OD-11 | (1) Add `inUseBytes` in CleanCore (PR E1) and use it in the UI |
| OD-12 | Real app icons on Uninstaller and Updater (letter tile fallback only) |
| OD-13 | (1) Local name filter in the Uninstaller |
| OD-14 | (1) Keep the current behaviour; copy "Open SOS Mac at login" |
| OD-15 | Remove "Check VirusTotal" |
| OD-16 | (1) Pin a read-only prototype snapshot in `docs/redesign/prototype/` |
| OD-17 | Background snapshot script by default; XCUITest only with Phương at the machine |
| OD-18 | (1) Full Disk Access / iCloud as instructions in banner text, no button |

Each item: the question, the options, my recommendation, and the default I will plan with if it stays open. "Blocks" names the first PR that needs the answer.

### Decisions to settle first (they shape PR 1–4)

**OD-1 — Palette C light: approve the derived values.** The report gives 12 of 28 tokens for C light and the prototype has never rendered C light (§2.2).
Options: (1) report's C light + the `[D]` values of §2.3–2.4 — an indigo light theme; (2) what the prototype shows for C + light today, which is Palette A light (lavender-white).
Recommendation: **(1)**, and ask the Designer to add a `data-palette="c"][data-theme="light"]` block to `tokens.css` and render the three light screens before PR 1 merges. Sub-points: **1a** sidebar `#EEF2FF`; **1b** hairline recipe (text token + A's alpha); **1c** row tints and aurora gradient in light; **1d** `gradientSoft` keeps A's violet stops in both appearances (re-tune or keep); **1e** the four contrast corrections X1–X4 (§2.7); **1f** type deltas 26 / 10 / 10 pt (§2.8, informational).
Default: (1) exactly as tabulated. Blocks: PR 1.

**OD-2 — Toolbar: system toolbar or the prototype's in-content header?**
Options: (1) the real macOS window toolbar (title + subtitle centred, back button leading, tools trailing) — native, gets Liquid Glass on macOS 26 automatically, overflow and keyboard access free; it spans the window, so it differs from the prototype's header that sits only over the detail column; (2) a custom header as drawn — pixel-faithful, but custom chrome to maintain and to re-check on every macOS release.
Recommendation: **(1)**. Default: (1). Blocks: PR 2.

**OD-3 — Leaving a screen while it scans.**
Options: (1) the scan keeps running and the sidebar row shows a small cyan busy dot; (2) it keeps running with no indicator; (3) it is cancelled, results are kept.
Recommendation: **(1)** — a full-Home duplicate scan takes minutes and cancelling wastes it; the dot is real state, not a result. Default: (1). Blocks: PR 3.

**OD-4 — How confirmation dialogs are presented.**
Options: (1) macOS sheet (system modal, system material); (2) an in-window overlay with a scrim, as drawn.
Recommendation: **(1)** — keyboard trapping, Escape and VoiceOver come free; visuals as the prototype. Default: (1). Blocks: PR 4b.

**OD-5 — Minimum window size.** Proposed **960 × 600** (today 720 × 480; the prototype has none). Below ~1100 wide the review layout drops to two columns. Default: 960 × 600. Blocks: PR 2.

**OD-6 — Increase Contrast.** Options: (1) v1 ships no separate high-contrast colour variants (as the Designer's `Theme.swift`); hairlines strengthen when the setting is on; (2) add light / dark / high-contrast Colour Sets for all tokens now (larger PR 1).
Recommendation: **(1)**; every text token already passes AA by default within rule T3. Default: (1). Blocks: PR 1.

### The two questions Phương asked

**OD-a — Similar Images: narrow the pre-selection?** Today every copy except the newest is pre-selected, and "Clean" is one confirmation away, with no thumbnails to tell near-matches apart (S3).
Options: (1) keep today's selection + the warning banner (the prototype); (2) **select nothing** in Similar mode — the user picks each image; (3) pre-select nothing and skip the confirmation.
Recommendation: **(2)**. Burst shots and edited versions are different pictures; names like `IMG_5103.HEIC` / `IMG_5104.HEIC` cannot be told apart in a list. It costs a few clicks and removes the riskiest default in the app. It narrows pre-selection, which the inventory reserves for Phương.
Default if open: (1), because it is the approved design. Blocks: PR 6.

**OD-b — Show a total size for each duplicate set?** "2 extra copies · 1.3 GB" in the group row. Derivable from sizes the engine already returns; no engine work; about ten lines.
Options: (1) show; (2) leave out (as in v1 of the prototype).
Recommendation: **(1)** — it tells the user which sets are worth reviewing first. Default: (1). Blocks: PR 6.

### Screen decisions

**OD-7 — iCloud Drive pre-selection.** The prototype pre-selects every extra copy; today nothing is selected. Trashing an iCloud Drive file also removes it from the user's other devices once the Trash is emptied.
Recommendation: **nothing pre-selected** (today's rule; the inventory forbids widening pre-selection without a product decision). Default: nothing. Blocks: PR 11.

**OD-8 — Junk "Ignore".** Today each row can be ignored (saved in SwiftData). The prototype has no Ignore control.
Recommendation: **keep it** as a plain button in the detail panel, so no existing capability is lost. Default: keep. Blocks: PR 5.

**OD-9 — Running-app check before uninstalling (S8).** The Designer lists it under "Fix before shipping the redesign"; app-only.
Recommendation: **include** it in the Uninstaller PR. Default: include. Blocks: PR 9.

**OD-10 — Updater: failed-check state (D3) and automatic check.** (i) Record a failed feed per row and show "Couldn't check" + banner — app-only. (ii) The prototype has an explicit **Check** button; today the check runs on every visit.
Recommendation: **(i) include; (ii) explicit Check only** (no network work on every visit; results now persist in the session store). Default: include; explicit. Blocks: PR 10.

**OD-11 — "Memory in use" (D2).** The engine reports used = total − free, so an idle Mac reads ~99 %. Options: (1) add `inUseBytes` (wired + active + compressed) to `MemoryInfo` in CleanCore, with a test, and use it in Performance, Smart Care, Dashboard and the menu bar; (2) leave the definition and drop the percentage, showing only the segment bar and legend.
Recommendation: **(1)** — small, testable, and what the prototype's numbers assume. Default: (1). Blocks: CleanCore PR E1, then PR 12 / 14 / 15.

**OD-12 — App icons.** The prototype draws letter tiles for Uninstaller and Updater. Today the Updater already shows real icons via `NSWorkspace`.
Recommendation: **real icons on both screens** (letter tile as fallback only). Default: real icons. Blocks: PR 9, PR 10.

**OD-13 — Uninstaller search box.** The prototype's box is a static mock with no behaviour. Options: (1) a local name filter (about 20 lines); (2) omit the box.
Recommendation: **(1)** — a dead control must not ship. Default: (1). Blocks: PR 9.

**OD-14 — "Open at login" copy.** The switch registers the main app today; the prototype says it starts the menu bar widget.
Options: (1) keep the behaviour, copy **"Open SOS Mac at login"**; (2) implement helper auto-launch (needs release-style signing to test; out of scope).
Recommendation: **(1)**. Default: (1). Blocks: PR 12.

**OD-15 — Protection "Check VirusTotal".** It silently does nothing without an API key. The prototype drops it.
Recommendation: **remove**. Default: remove. Blocks: PR 13.

**OD-16 — Pin the prototype in the repo.** Options: (1) copy a read-only snapshot to `docs/redesign/prototype/` so later PRs can compare against a fixed reference; (2) keep referencing the OpenDesign project only.
Recommendation: **(1)** — the prototype is the visual contract; a snapshot keeps it from drifting. Default: (1). Blocks: PR 0.

**OD-17 — Running UI tests on the development Mac.** XCUITest brings the app to the front for a minute or two. The snapshot script (plan PR 0) launches the app in the background and captures the window only.
Recommendation: **snapshots via the background script by default; XCUITest flows only when Phương is at the machine and has been told.** Default: same. Blocks: PR 0.

**OD-18 — "Open System Settings" links.** Only Login Items has a documented API (`SMAppService.openSystemSettingsLoginItems()`, used today). Full Disk Access and iCloud have none; the `x-apple.systempreferences:` URL scheme is undocumented.
Options: (1) show those two as instructions in the banner text, no button; (2) add buttons that use the undocumented scheme.
Recommendation: **(1)** — the project prefers documented APIs and a dead link is worse than a sentence. Default: (1). Blocks: PR 6, PR 11.

---

## 11. Acceptance checklist (per screen PR)

A screen PR is done when all of this is true:

1. `xcodebuild build -scheme SOSMac -configuration Debug` succeeds and `cd Packages/CleanCore && swift test` passes.
2. Every lifecycle state the screen can reach has a snapshot in dark and light, compared side by side with the prototype's state, and the differences are listed in the PR.
3. The `Phase → LifecycleState` mapping and the selection rules (pre-selection, kept items, Select All) have unit tests.
4. No removal path exists without a confirmation; Cancel is the default button.
5. Every number on screen is in §6.4; no placeholder text ("—", "Not … this session") remains.
6. Copy matches Appendix A.
7. Leaving the screen and coming back restores the same state (§6.6).
8. With Reduce Transparency on: no blur or glass anywhere on the screen. With VoiceOver: every control has a label.
9. The screen still works at the minimum window size (OD-5).

---
## Appendix A — Canonical copy

Fixes inventory C1–C5. One verb per idea, everywhere.

| Purpose | Copy | Where |
|---|---|---|
| Start | **Scan** | Smart Care, Junk & Cache, Duplicate Finder, Space Lens (spoken: "Scan Home"), iCloud Drive, Protection |
| | **Check** | Updater |
| | **Measure All** (spoken: "Inspect all apps to measure their size") | Uninstaller |
| Stop | **Stop** | every scanning state |
| Open review | **Review Items…** | Smart Care, Junk & Cache, Duplicate Finder, iCloud Drive |
| | **Review** | Protection (results), Uninstaller (per row and dock) |
| | **Review…** | Space Lens |
| Act on results | **Clean** | Smart Care, Junk & Cache, Duplicate Finder, iCloud Drive |
| | **Delete from Google Drive…** (danger) | Drive — and the provider's name for the others |
| Confirm | **Move to Trash** · **Quarantine** · **Delete from Google Drive** · **Cancel** | §4.8 |
| While moving | **Moving** (disabled) | cleaning |
| Finish | **Scan Again** | every scanning module; **Check Again** (Updater); **Measure Again** (Uninstaller results) |
| | **Open Trash** | done |
| | **Back to Apps** · **Back to Map** | Uninstaller · Space Lens |
| | **Choose Folder…** | Space Lens empty state |
| | **Try Again** | every error |
| List tools | **Select All** · **Deselect All** | review |
| Selection summary | **N items** · **size** selected — or "No items selected" | review bar, dock |
| Undo hint | Everything is in the Trash. To undo, open the Trash in Finder and choose Put Back. | done |

- Local removal is always **"Move to Trash"**, never "Delete". "reclaimed" and "removed" are retired; the result is **"moved to the Trash"**.
- Protection **quarantines**; it never deletes.
- Screen names equal the sidebar labels (§3.2). "Junk & Cache Scanner" is now "Junk & Cache".

## Appendix B — Prototype ↔ Swift names

**B.1 Tokens the prototype uses that `Theme.swift` lacks** — the twelve CSS variables of §2.4 and their proposed names (thirteen with `--glass-a`, which the material replaces).

**B.2 Module hue additions:** `ink` per hue (§2.5) and the tenth hue `Theme.Hue.threat` (rose).

**B.3 Prototype building blocks and the Swift views that will replace them** (names are proposals; the plan fixes them):

| Prototype (`ui.js`, `screens.js`) | Proposed Swift |
|---|---|
| `tile`, `badge`, `btn`, `cb`, `seg` | `ModuleTileView`, `BadgeView` (existing name, restyled) + `KeepBadge`, stock buttons + `SOSButtonStyle` where needed, `SOSCheckbox`, stock segmented picker |
| `cta`, `dock` | `PrimaryCTAView`, `DockView` |
| `startView`, `scanView`, `steps`, `progress` | `StartView`, `ScanningView`, `StepRowView` and `ProgressBarView` (existing names, restyled), `ScanProgressPanel` (kept) |
| `resultsHead`, `rtile` | `ResultsHeaderView`, `ResultTileView` |
| `doneView`, `emptyView` | `DoneView`, `StatusStateView` |
| `banner`, `alertBox`, `alist`, content background | `BannerView`, `ConfirmSheet`, `ConfirmItemList`, `AuroraBackground` |
| `reviewFrame`, `grow`, `irow`, `reviewbar` | `ReviewFrameView`, `ReviewGroupRow`, `ReviewItemRow`, `ReviewBarView` |
| `appRow`, `qpanel`, `mcard`, `mrow` | `AppRowView`, `QuarantinePanelView`, `MetricCardView`, `MaintenanceRow` |
| `squarify` | `TreemapKit` (existing) |

**B.4 Symbols:** `sparkles`, `wand.and.stars`, `trash`, `doc.on.doc`, `square.grid.3x3`, `icloud`, `xmark.bin`, `arrow.triangle.2.circlepath`, `gauge.with.dots.needle.50percent`, `checkmark.shield` (modules); `checkmark`, `xmark`, `chevron.left`, `chevron.right`, `exclamationmark.triangle`, `info.circle`, `lock`, `memorychip`, `network`, `arrow.uturn.backward`, `externaldrive`, `house`, `cpu`, `thermometer.medium`, `archivebox`, `arrow.up.forward.square`, `power`, `bag`, `stop`, `key`, `list.bullet` (in content).

**B.4b** Symbol names were resolved with `NSImage(systemSymbolName:accessibilityDescription:)` on macOS 27.0.1 (2026-11-26): all exist except the prototype's stand-in `gauge.with.dots.needle`, which is why Performance keeps the `.50percent` variant the app already uses.

**B.5 Prototype annotations that are not UI:** `.tag-engine` chips, the Updater `.lens-note`, the Drive "Design target" ribbon, the developer bar.

## Appendix C — Palette C reference values

Generated from one table of hex values so the token block and §2.3 cannot drift, and **typechecked** with `swiftc -typecheck -target arm64-apple-macos14.0 -strict-concurrency=complete` on 2026-11-26 (Xcode 27.1). `Color(hex:)` is the initialiser already in `App/DesignSystem/Theme.swift`. PR 1 may use hex literals or the Designer's three-decimal floats; hex is exact.

**C.1 The 28 colour tokens (drop-in for `enum Color` in the Designer's file)**

```swift
        /// --bg-base · dark #0A0E1A · light #F4F6FF
        static let bgBase = SwiftUI.Color.adaptive(light: SwiftUI.Color(hex: "#F4F6FF"), dark: SwiftUI.Color(hex: "#0A0E1A"))
        /// --bg-elevated · dark #131A2E · light #FFFFFF
        static let bgElevated = SwiftUI.Color.adaptive(light: SwiftUI.Color(hex: "#FFFFFF"), dark: SwiftUI.Color(hex: "#131A2E"))
        /// --glass · dark #18213A · light #FFFFFF
        static let glass = SwiftUI.Color.adaptive(light: SwiftUI.Color(hex: "#FFFFFF"), dark: SwiftUI.Color(hex: "#18213A"))
        /// --card · dark #111829 · light #FFFFFF
        static let card = SwiftUI.Color.adaptive(light: SwiftUI.Color(hex: "#FFFFFF"), dark: SwiftUI.Color(hex: "#111829"))
        /// --sidebar · dark #0E1424 · light #EEF2FF
        static let sidebar = SwiftUI.Color.adaptive(light: SwiftUI.Color(hex: "#EEF2FF"), dark: SwiftUI.Color(hex: "#0E1424"))
        /// --primary · dark #818CF8 · light #4F46E5
        static let primary = SwiftUI.Color.adaptive(light: SwiftUI.Color(hex: "#4F46E5"), dark: SwiftUI.Color(hex: "#818CF8"))
        /// --primary-deep · dark #4F46E5 · light #4F46E5
        static let primaryDeep = SwiftUI.Color.adaptive(light: SwiftUI.Color(hex: "#4F46E5"), dark: SwiftUI.Color(hex: "#4F46E5"))
        /// --primary-bright · dark #A5B4FC · light #4338CA
        static let primaryBright = SwiftUI.Color.adaptive(light: SwiftUI.Color(hex: "#4338CA"), dark: SwiftUI.Color(hex: "#A5B4FC"))
        /// --on-primary · dark #FFFFFF · light #FFFFFF
        static let onPrimary = SwiftUI.Color.adaptive(light: SwiftUI.Color(hex: "#FFFFFF"), dark: SwiftUI.Color(hex: "#FFFFFF"))
        /// --neon-cyan · dark #22D3EE · light #155E75
        static let neonCyan = SwiftUI.Color.adaptive(light: SwiftUI.Color(hex: "#155E75"), dark: SwiftUI.Color(hex: "#22D3EE"))
        /// --neon-lime · dark #A3E635 · light #3F6212
        static let neonLime = SwiftUI.Color.adaptive(light: SwiftUI.Color(hex: "#3F6212"), dark: SwiftUI.Color(hex: "#A3E635"))
        /// --neon-magenta · dark #A78BFA · light #6D28D9
        static let neonMagenta = SwiftUI.Color.adaptive(light: SwiftUI.Color(hex: "#6D28D9"), dark: SwiftUI.Color(hex: "#A78BFA"))
        /// --text-1 · dark #EEF2FF · light #141A33
        static let textPrimary = SwiftUI.Color.adaptive(light: SwiftUI.Color(hex: "#141A33"), dark: SwiftUI.Color(hex: "#EEF2FF"))
        /// --text-2 · dark #A5ADC8 · light #4A5273
        static let textSecondary = SwiftUI.Color.adaptive(light: SwiftUI.Color(hex: "#4A5273"), dark: SwiftUI.Color(hex: "#A5ADC8"))
        /// --text-3 · dark #6E7799 · light #7C84A3
        static let textTertiary = SwiftUI.Color.adaptive(light: SwiftUI.Color(hex: "#7C84A3"), dark: SwiftUI.Color(hex: "#6E7799"))
        /// --success · dark #34D399 · light #047857
        static let success = SwiftUI.Color.adaptive(light: SwiftUI.Color(hex: "#047857"), dark: SwiftUI.Color(hex: "#34D399"))
        /// --warning · dark #F59E0B · light #B45309
        static let warning = SwiftUI.Color.adaptive(light: SwiftUI.Color(hex: "#B45309"), dark: SwiftUI.Color(hex: "#F59E0B"))
        /// --danger · dark #F87171 · light #B91C1C
        static let danger = SwiftUI.Color.adaptive(light: SwiftUI.Color(hex: "#B91C1C"), dark: SwiftUI.Color(hex: "#F87171"))
        /// --danger-fill · dark #B91C1C · light #B91C1C
        static let dangerFill = SwiftUI.Color.adaptive(light: SwiftUI.Color(hex: "#B91C1C"), dark: SwiftUI.Color(hex: "#B91C1C"))
        /// --tm-1 · dark #4A3A9E · light #DDD6FE
        static let treemap1 = SwiftUI.Color.adaptive(light: SwiftUI.Color(hex: "#DDD6FE"), dark: SwiftUI.Color(hex: "#4A3A9E"))
        /// --tm-2 · dark #3D3F95 · light #E0E7FF
        static let treemap2 = SwiftUI.Color.adaptive(light: SwiftUI.Color(hex: "#E0E7FF"), dark: SwiftUI.Color(hex: "#3D3F95"))
        /// --tm-3 · dark #34509C · light #DBEAFE
        static let treemap3 = SwiftUI.Color.adaptive(light: SwiftUI.Color(hex: "#DBEAFE"), dark: SwiftUI.Color(hex: "#34509C"))
        /// --tm-4 · dark #2E5B8F · light #E0F2FE
        static let treemap4 = SwiftUI.Color.adaptive(light: SwiftUI.Color(hex: "#E0F2FE"), dark: SwiftUI.Color(hex: "#2E5B8F"))
        /// --tm-5 · dark #463C82 · light #EDE9FE
        static let treemap5 = SwiftUI.Color.adaptive(light: SwiftUI.Color(hex: "#EDE9FE"), dark: SwiftUI.Color(hex: "#463C82"))
        /// --tm-6 · dark #3A4780 · light #D9E2FF
        static let treemap6 = SwiftUI.Color.adaptive(light: SwiftUI.Color(hex: "#D9E2FF"), dark: SwiftUI.Color(hex: "#3A4780"))
        /// --tm-7 · dark #353A6E · light #E9E5FF
        static let treemap7 = SwiftUI.Color.adaptive(light: SwiftUI.Color(hex: "#E9E5FF"), dark: SwiftUI.Color(hex: "#353A6E"))
        /// --tm-8 · dark #2D2A55 · light #ECE7FA
        static let treemap8 = SwiftUI.Color.adaptive(light: SwiftUI.Color(hex: "#ECE7FA"), dark: SwiftUI.Color(hex: "#2D2A55"))
        /// --tm-text · dark #F4F2FF · light #1A1333
        static let treemapText = SwiftUI.Color.adaptive(light: SwiftUI.Color(hex: "#1A1333"), dark: SwiftUI.Color(hex: "#F4F2FF"))```

**C.2 Proposed additions (§2.4)**

```swift
    enum Derived {
        static let hairline = SwiftUI.Color.adaptive(light: SwiftUI.Color(hex: "#141A33").opacity(0.09), dark: SwiftUI.Color(hex: "#A5ADC8").opacity(0.12))
        static let hairlineStrong = SwiftUI.Color.adaptive(light: SwiftUI.Color(hex: "#141A33").opacity(0.16), dark: SwiftUI.Color(hex: "#A5ADC8").opacity(0.22))
        static let rowHover = SwiftUI.Color.adaptive(light: SwiftUI.Color(hex: "#4338CA").opacity(0.06), dark: SwiftUI.Color(hex: "#A5B4FC").opacity(0.08))
        static let rowSelected = SwiftUI.Color.adaptive(light: SwiftUI.Color(hex: "#4F46E5").opacity(0.12), dark: SwiftUI.Color(hex: "#818CF8").opacity(0.20))
    }
    enum Gradient {
        static let aurora = LinearGradient(colors: stops(light: ["#6366F1", "#4F46E5", "#155E75"], dark: ["#A5B4FC", "#818CF8", "#6366F1"]), startPoint: .leading, endPoint: .trailing)
        static let soft = LinearGradient(colors: stops(light: ["#8B5CF6", "#7C3AED", "#6366F1"], dark: ["#A78BFA", "#8B5CF6", "#6366F1"]), startPoint: .topLeading, endPoint: .bottomTrailing)
        private static func stops(light: [String], dark: [String]) -> [SwiftUI.Color] {
            zip(light, dark).map { SwiftUI.Color.adaptive(light: SwiftUI.Color(hex: $0), dark: SwiftUI.Color(hex: $1)) }
        }
    }
```

**C.3 Module hues (with the tenth hue; `ink` is a comment until PR 1 adds it as data)**

```swift
    enum Hue {
        static let smartcare = SwiftUI.Color(hex: "#8B5CF6")   // ink #FFFFFF
        static let junk = SwiftUI.Color(hex: "#6366F1")        // ink #FFFFFF
        static let duplicates = SwiftUI.Color(hex: "#3B82F6")  // ink #FFFFFF
        static let spacelens = SwiftUI.Color(hex: "#E879F9")   // ink #140F26
        static let cloud = SwiftUI.Color(hex: "#38BDF8")       // ink #140F26
        static let uninstaller = SwiftUI.Color(hex: "#FB923C") // ink #140F26
        static let updater = SwiftUI.Color(hex: "#FBBF24")     // ink #140F26
        static let performance = SwiftUI.Color(hex: "#2DD4BF") // ink #140F26
        static let protection = SwiftUI.Color(hex: "#22D3EE")  // ink #140F26
        static let threat = SwiftUI.Color(hex: "#F87171")      // ink #140F26
    }
```

## Appendix D — Sources, checks, and what was not verified

**D.1 Read**

- Prototype (read-only): `index.html`, `app.js`, `screens.js`, `ui.js`, `data.js`, `styles.css`, `tokens.css`, `tokens.html`, `board.html`, `palettes.html`, `needs-engine-work.html`, `README.md`, `tokens/Theme.swift`, `tokens/sos-aurora-indigo.tokens.json` — in the OpenDesign project "SOS Mac Redesign v1 — Aurora Indigo".
- Palette report: `sos-mac-purple-neon-palette-g1.md` (§2, §3.3, §4, §6).
- `docs/redesign/current-ui-inventory.md` (§1.4, §2, §3, §4, §5, §8).
- Code: `App/SOSMacApp.swift`, `App/DesignSystem/*`, every `App/Features/*/*ViewModel.swift`, the feature views' phase switches, `MenuBarHelper/*`, `project.yml`, `SOSMacUITests/AuroraCareScreenshotTests.swift`, and in CleanCore: `Protocols/Cleaner.swift`, `Models/ScanItem.swift`, `Duplicates/DuplicateFinder.swift`, `JunkScanner/JunkScanner.swift`, `SmartCare/*`, `Performance/MachHostStats.swift`.

**D.2 Checks run (all on 2026-11-26)**

| Check | Result |
|---|---|
| WCAG contrast for every Palette C pair (§2.3, §2.5–2.7), computed twice with independent scripts | Reproduces every Palette C figure in the report (25 printed, 24 distinct pairs); found X1–X4 and the T3 numbers. Selected-row figures use the light `rowSelected` recipe of §2.4 (12 %) |
| `tokens/Theme.swift` typecheck, macOS 14 target, strict concurrency | Exit 0 |
| Appendix C reference typecheck, same settings | Exit 0 |
| SDK interface (MacOSX27.0.sdk, Xcode 27.1): availability of every API named in §7 | As listed in §7 |
| `xcdocs` local index (Xcode 27.1) | Confirms the symbols exist; the installed index carries no page text, so page content was read on developer.apple.com |

**D.3 Apple documentation read live**

- Applying Liquid Glass to custom views — <https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views>
- `glassEffect(_:in:)` — <https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)>
- `Glass` — <https://developer.apple.com/documentation/swiftui/glass> · `Glass.clear` — <https://developer.apple.com/documentation/swiftui/glass/clear>
- `accessibilityReduceTransparency` — <https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducetransparency>
- `defaultSize(width:height:)` — <https://developer.apple.com/documentation/swiftui/scene/defaultsize(width:height:)>
- HIG Materials — <https://developer.apple.com/design/human-interface-guidelines/materials>
- HIG Accessibility — <https://developer.apple.com/design/human-interface-guidelines/accessibility>
- HIG Typography (macOS built-in text styles) — <https://developer.apple.com/design/human-interface-guidelines/typography>
- HIG Toolbars — <https://developer.apple.com/design/human-interface-guidelines/toolbars>

**D.4 Not verified (each is a task or a risk in the plan)**

- How Palette C light actually looks: it has never been rendered (OD-1).
- What the stock `NavigationSplitView` sidebar and window toolbar look like on macOS 14, 15, 26 and 27 with and without custom backgrounds (PR 2).
- Whether stock macOS buttons match the 28 pt / 34 pt metrics, or a custom style is needed (PR 4a).
- `glassEffect` on a bottom bar and on a popover, and its behaviour under Reduce Transparency on macOS 26 (PR 2, PR 4b).
- Performance and memory of the three-column review and of retained results with 100 k+ items (PR 3, PR 5).
- The real Trash behaviour of the per-item cleaning loop under Swift 6 (PR 5).
- XCUITest reliability for flows; the background snapshot script (PR 0).
- That `x-apple.systempreferences:` still works on current macOS — the reason for OD-18.

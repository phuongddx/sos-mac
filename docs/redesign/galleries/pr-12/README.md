# PR 12 — Performance snapshot gallery

The six states of the migrated Performance screen (spec §5.9), in dark and light, captured
from the real app running on fixture data only (`SOSMAC_UITEST_FIXTURES=1`: CPU 23 %, the
fictional 16 GB memory with its five segments, swap 1.25 of 2.15 GB, thermal nominal,
boot 24 Nov 2026 09:14 UTC, three `/Users/sample` launch agents — nothing was read from
the machine, no helper ran, no System Settings panel opened). Each
`performance-<state>-sheet.png` places **dark on the left, light on the right**;
`performance-contact-sheet.png` is the overview.

Captured with `Scripts/ui-snapshots.sh -p pr-12 -w 1200x1040 -s performance=<state>` —
background-only window capture. The window is **1200×1040 pt**, taller than the usual
1200×760: the screen is one long live page (no lifecycle states swap the content), and at
760 pt the inline action banners, the Flush DNS Cache row and the widget/login cards sit
below the fold, so the state evidence would be invisible. The screen has no minimum-height
dependency; at the OD-5 minimum (960×600) it simply scrolls.

| State | Sheet | Notes |
|---|---|---|
| live | [performance-live-sheet.png](performance-live-sheet.png) | subtitle **Live**; both rows Run; metric grid, widget and login cards |
| running | [performance-running-sheet.png](performance-running-sheet.png) | Free up RAM reads "Running…" with a spinner, Run disabled |
| approval | [performance-approval-sheet.png](performance-approval-sheet.png) | `info` banner "Approve the SOS Mac helper" + **Open System Settings** under the row |
| actiondone | [performance-actiondone-sheet.png](performance-actiondone-sheet.png) | `ok` banner "Free up RAM finished" |
| actionerror | [performance-actionerror-sheet.png](performance-actionerror-sheet.png) | `err` banner "Couldn't flush the DNS cache" + **Try Again** under its row |
| unavailable | [performance-unavailable-sheet.png](performance-unavailable-sheet.png) | subtitle **No data**; `err` banner "Couldn't read system metrics" + Try Again; every value "—" (the fixture feeds the same non-nil partial sample the real seams return: no memory, the rest present) |

## Known differences from the prototype

- **Truthful "in use" (D2 / OD-11).** Memory reads CleanCore's `MemoryInfo.inUseBytes` —
  the engine's own OD-11 figure ("11.24 GB in use of 16 GB"), carried verbatim into the
  screen; the app re-derives nothing. Not the prototype-era `total − free` that read
  ~99 %.
- **Segment colours are Palette C (§5.9).** `primaryDeep`, `primary`, `primaryBright`,
  `primaryBright` at 40 %, Free as an outlined, unfilled segment — the prototype hardcodes
  Palette A purples. The bar normalises the five segments against **their own sum**, since
  they don't add up to physical memory exactly (the plan's stated risk); the legend shows
  the real bytes. The fixture's idealised segments happen to sum exactly to 16 GB, so the
  normalisation is proven by `PerformanceViewModelTests` on constructed segments instead.
- **OD-14 copy.** The login card reads "Open SOS Mac at login." — the switch registers the
  main app; it does not start the menu bar widget.
- **Launch-agents list shows paths, not dates.** The prototype lists a date column;
  `LoginItemEntry` (the engine's model) carries a path, so the card shows
  label + path.
- **"Open System Settings" opens Login Items** through the documented
  `SMAppService.openSystemSettingsLoginItems()` (OD-18: no undocumented deep links; Login
  Items has a real API). In the captures nothing opens — the fixture seam is a no-op.
- **No auto-open of System Settings.** The old screen opened Login Items itself the moment
  a run returned `.requiresApproval`; this screen only flips the row to the approval
  banner — System Settings opens through the banner's explicit **Open System Settings**
  button (user-initiated, OD-18 deep link), never by itself. Deliberate deviation from the
  old screen: an auto-opened system pane is a surprise system-UI action.
- **Architecture/uptime come from the fixture** (Apple Silicon, 24 Nov 2026 at 09:14 —
  rendered in the capturing machine's local time zone), like every other figure on the
  screen.
- **Thermal state is shown once** (C7): a status dot and the state's own word ("Nominal"),
  captioned "As reported by macOS" — the old screen showed a badge plus a repeated word.
- **No dock.** Performance has no scan lifecycle, so the screen composes the aurora canvas
  and toolbar itself (as Protection's Quarantine sub-screen does) instead of the shared
  `ModuleScreen` frame; the doubled toolbar title is that shared toolbar's known behaviour
  (also visible in PR 5/9/13).
- **Run is disabled while metrics are unavailable** (the prototype's `disabled: running ||
  na`) — visible in the unavailable sheet.
- **Not in the static matrix:** a real helper run (Free up RAM / Flush DNS on a live
  helper), the System Settings panel the approval banner points to, and the real
  MenuBarHelper launch. Those stay on the manual-test list; the state transitions are
  covered by `SOSMacTests/PerformanceViewModelTests` (20 tests, injected seams only).

## PR-description skeleton

```markdown
## What changes for the user
Performance moves to Palette C as a live screen: a metric grid (CPU, a five-segment
memory bar with an honest "in use" figure, thermal state shown once, load averages,
swap/architecture/uptime), maintenance rows with per-action inline banners (approve /
finished / couldn't — with Try Again), and the menu-bar-widget and login cards. When
macOS doesn't return readings, the screen says so and shows "—" instead of guessing.

## Safety impact
No scan lifecycle and no removal path: the two maintenance actions route through the
existing privileged-helper client, with an explicit approval state pointing at System
Settings › Login Items (documented API only). Reads never guess: unavailable metrics
show "—" under a Try Again banner. Tests and fixtures inject every seam, so no test or
snapshot can run `purge`, flush DNS, or touch a login item.

## Prototype states implemented
live · running · approval · actiondone · actionerror · unavailable

## Open decisions used
OD-11 → inUseBytes (E1 landed) · OD-14 → "Open SOS Mac at login" (behaviour unchanged) ·
OD-18 → Login Items deep link via SMAppService · OD-17 → background snapshots only

## Tests run
xcodegen generate ·
xcodebuild build -scheme SOSMac -configuration Debug (exit 0, 0 errors) ·
cd Packages/CleanCore && swift test (115 tests / 28 suites) ·
xcodebuild test -only-testing:SOSMacTests (196 tests / 25 suites, 20 new) ·
Scripts/ui-snapshots.sh -p pr-12 -w 1200x1040 (12 captures at 2400x2080; every committed
state sheet pairs dark + light into one 4800x2080 image)
```

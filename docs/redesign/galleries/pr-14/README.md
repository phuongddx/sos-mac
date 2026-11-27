# PR 14 — Dashboard snapshot gallery

The migrated Dashboard in dark and light, captured from the real app running on fixture data
only (`SOSMAC_UITEST_FIXTURES=1`: volume "Sample Disk", the sample storage figures, load 2.41,
16 GB memory with 11.24 GB in use, thermal "Nominal" — nothing was read from the real Mac).
`dashboard-default-sheet.png` places **dark on the left, light on the right** (1840×583, regenerated in PR 16);
`dashboard-contact-sheet.png` is the overview (904×291).

Captured with `Scripts/ui-snapshots.sh -p pr-14 -s dashboard=default` — background-only window
capture, 1200×760 pt, 2400×1520 px per appearance.

## State matrix

The Dashboard has no lifecycle (spec §5.1), so there is one state. What varies at runtime:

| Input | Shown | In the gallery |
|---|---|---|
| Boot volume readable | Hero right column: name, "«free» free", meter, "«used» used of «total»", Open Space Lens | yes |
| Boot volume unreadable | Right column left out; hero is the Smart Care block only | no (unit-level: not testable without a window) |
| Volume has no name | Name omitted, "«free» free" stays | no |
| Load / memory / thermal each readable | One snapshot tile each, "Read when this page opened" | yes (all three) |
| A reading unavailable | That tile left out; all three missing → the row is left out | `DashboardViewModelTests` (format and omission rules) |
| Window ≥ ~900 pt content | Module cards four across (as here) | yes |
| Narrower (960 pt window minimum) | Cards two by two | no |

## Deviations from the prototype

- **Real or nothing (D6, spec §11.5).** No placeholder, "—" or invented value: a missing
  reading drops its tile; the Performance card's second line ("Load 2.41 · Memory 70%") is the
  same snapshot and has no "live" dot, and is dropped when neither figure exists.
- **Memory in use is `inUseBytes`** (wired + active + compressed), never the `usedBytes`
  percentage. The percent on the Performance card is the same figure over total memory.
- **Snapshot is read once**, when the page appears (the caption says so); no polling.
- **Decimal separator and units follow the system** (`ByteFormatter`, Intl), so a machine set
  to a comma locale shows "11,24 GB"; the prototype hard-codes a dot.
- **Orb ring (fixed in PR 16).** The hero orb reuses `ModuleOrbView` with 112 pt metrics and a
  ring inset of 10 pt (`Metrics.ringInset`), as in the prototype, so the thin ring is now
  visible around the glyph; the full-size start orbs keep their 34 pt inset.
- **Four across by `ViewThatFits`**, not CSS grid: below the width where each card keeps 200 pt
  the cards fall back to two by two.
- **"Run Smart Care" mid-review.** If Smart Care is already in its review phase the button
  opens the screen and keeps the user's selection instead of rescanning (spec §6.6 / N1); a
  running scan is not restarted either. From idle, results, done or failed it starts a scan.
- **Not shown, on purpose:** health dial, "last scanned" stamps, per-module status (spec §5.1).
- Doubled toolbar title ("Dashboard" in the toolbar) is existing shell behaviour.

## Not verified here

- Clicking "Run Smart Care" in the live window and seeing Smart Care land on a scanning screen
  (no XCUITest by decision). The launch logic is covered by `DashboardViewModelTests`
  (Smart Care leaves `.idle` and navigation targets `.smartCare`); the visual check is manual.
- A real Mac's memory and thermal readings (the gallery uses fixtures).

## Regenerated in PR 16 (cleanup)

Every sheet in this folder was re-captured from the final PR 16 build, fixture data only
(`SOSMAC_UITEST_FIXTURES=1`, `open -g` background launch, `screencapture -l` window capture,
no foreground, no permission prompt, no real scan). Each `<screen>-<state>-sheet.png` is the dark capture (left) and the light capture (right), each scaled to 920 px wide and joined side by side.

```bash
Scripts/ui-snapshots.sh -p pr-14 -d /tmp/sosmac-pr16-dd -s dashboard=default
```

- Captures: 2; every one is 2400×1520 px (the raw per-appearance files are generated into the
  git-ignored `artifacts/ui-snapshots/` and are not committed); no capture is blank.
- Sheets: 1 × 1840×583. Contact sheet: 904×291 (dark, light) (dark first, then light).
- The Dashboard orb is the only visual change in this gallery from PR 16 (ring inset).

## PR-description skeleton

```markdown
## What changes for the user
The Dashboard becomes a launcher: a Smart Care hero whose "Run Smart Care" opens Smart Care
and starts the scan, your disk's real storage numbers, three system readings taken when the
page opens, and the eight modules in two labelled groups. The "Not scanned this session"
placeholder lines are gone.
## Safety impact
None: no delete path, no file access beyond the existing read-only storage and system
readings. Nothing starts except the Smart Care scan, and only from the explicit button.
## Prototype states implemented
dashboard (single state; readings omitted when unavailable)
## Tests run
xcodegen generate ·
xcodebuild build -scheme SOSMac -configuration Debug ·
cd Packages/CleanCore && swift test (115 tests / 28 suites, unchanged) ·
xcodebuild test -only-testing:SOSMacTests (189 tests, 13 new in DashboardViewModelTests) ·
Scripts/ui-snapshots.sh -p pr-14 -s dashboard=default (2 captures at 2400x1520; one 1840x583 dark|light sheet)
```

# PR 7 — Smart Care snapshot gallery

All eight lifecycle states of the migrated Smart Care screen **plus the
partial-failure state**, in dark and light, captured from the real app running on
fixture data only (`SOSMAC_UITEST_FIXTURES=1`, fictional `/Users/sample` paths — no
real files were read, moved or trashed). Each `smartcare-<state>-sheet.png` places
**dark on the left, light on the right**; `smartcare-contact-sheet.png` is the whole
overview (dark rows first, light rows after).

Captured with `Scripts/ui-snapshots.sh -p pr-7 -s
smartcare=start,smartcare=scanning,smartcare=results,smartcare=review,smartcare=cleaning,smartcare=done,smartcare=empty,smartcare=error,smartcare=partial`
— background-only window capture, 1200×760 pt.

| State | Sheet | Prototype reference |
|---|---|---|
| start | [smartcare-start-sheet.png](smartcare-start-sheet.png) | `docs/redesign/prototype/index.html?screen=smartcare&state=start&palette=c` |
| scanning | [smartcare-scanning-sheet.png](smartcare-scanning-sheet.png) | `docs/redesign/prototype/index.html?screen=smartcare&state=scanning&palette=c` |
| results | [smartcare-results-sheet.png](smartcare-results-sheet.png) | `docs/redesign/prototype/index.html?screen=smartcare&state=results&palette=c` |
| review | [smartcare-review-sheet.png](smartcare-review-sheet.png) | `docs/redesign/prototype/index.html?screen=smartcare&state=review&palette=c` |
| cleaning | [smartcare-cleaning-sheet.png](smartcare-cleaning-sheet.png) | `docs/redesign/prototype/index.html?screen=smartcare&state=cleaning&palette=c` |
| done | [smartcare-done-sheet.png](smartcare-done-sheet.png) | `docs/redesign/prototype/index.html?screen=smartcare&state=done&palette=c` |
| empty | [smartcare-empty-sheet.png](smartcare-empty-sheet.png) | `docs/redesign/prototype/index.html?screen=smartcare&state=empty&palette=c` |
| error | [smartcare-error-sheet.png](smartcare-error-sheet.png) | `docs/redesign/prototype/index.html?screen=smartcare&state=error&palette=c` |
| partial | [smartcare-partial-sheet.png](smartcare-partial-sheet.png) | §5.2 `error` (partial) — no prototype state; the spec table row is the reference |

## Known differences from the prototype

- **The start note carries the macOS folder-access sentence** (§6.3): the
  prototype's "3 locations, no extra permission" bullet stays, and the note adds
  "macOS may ask for access to Desktop, Documents or Downloads the first time."
- **The partial-failure state has no prototype screen.** The spec table defines
  it: `results` with a skipped tile ("Scan stopped", "Failed") and an error
  banner naming the failed leg with Try Again (N4 — the error sits next to its
  cause, not in a bare red line).
- **The health tile figures are the fixture metrics** (load 2.41, memory
  11.24 GB of 16 GB, thermal Nominal — `UITestFixtures.metrics` summed), so
  snapshots are reproducible; live scans read the one-off `PerformanceSnapshot`
  (§6.4).
- **The trash confirmation is a real macOS sheet** (OD-4/CF-1), so the
  `dialog=trash` state is not part of this static matrix — it is covered by
  `SOSMacTests/ConfirmSheetTests` and the manual run.
- **Done keeps its actions in the dock** (F1: Open Trash trailing, Scan Again
  CTA) rather than repeating them inside the card as the prototype draws.
- **Stop is the dock CTA** (N6) with the aggregate ring, not the prototype's
  separate button; Stop returns to `start` and discards partial results (F2).

## PR-description skeleton

```markdown
## What changes for the user
Smart Care moves to the new Palette C lifecycle frame: a real start screen with
bullets and the folder-access note, scanning with steps and a Stop button,
results with junk/duplicates/health tiles, a two-section review where the
newest duplicate copy is locked (S4), per-item moving progress, an honest Done
card, and a partial-failure results state with a banner instead of a bare red
line.
## Safety impact
Every removal path opens the trash confirmation (Cancel default). Deletes go
through ProgressiveCleaner → Cleaner.clean only; Smart Care's junk rules are the
helper-free subset, so no item bypasses the user-context cleaner. The keep copy
can never be selected — toggle, Select All and pre-selection all skip it.
## Prototype states implemented
start · scanning · results · review · cleaning · done · empty · error · partial
(docs/redesign/prototype/index.html?screen=smartcare&state=<state>&palette=c)
## Tests run
xcodebuild build -scheme SOSMac -configuration Debug ·
cd Packages/CleanCore && swift test (115/115) ·
xcodebuild test -only-testing:SOSMacTests (76/76) ·
Scripts/ui-snapshots.sh -p pr-7 (9 states × dark/light)
```

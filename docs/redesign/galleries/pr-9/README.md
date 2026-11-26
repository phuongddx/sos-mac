# PR 9 — Uninstaller snapshot gallery

All eight lifecycle states of the migrated Uninstaller screen, in dark and light, captured
from the real app running on fixture data only (`SOSMAC_UITEST_FIXTURES=1`, ten fictional
"Example …" apps, fictional `/Applications` and `/Users/sample` paths — no real app list,
file or Trash was read, moved or trashed). Each `uninstaller-<state>-sheet.png` places
**dark on the left, light on the right**; `uninstaller-contact-sheet.png` is the 4×4
overview (top two rows dark, bottom two light).

Captured with `Scripts/ui-snapshots.sh -p pr-9 -s uninstaller=<state>` — background-only
window capture, 1200×760 pt.

| State | Sheet | Phase / notes |
|---|---|---|
| start | [uninstaller-start-sheet.png](uninstaller-start-sheet.png) | `browsing`, nothing measured: app list, per-row Inspect, Measure All, local filter |
| scanning | [uninstaller-scanning-sheet.png](uninstaller-scanning-sheet.png) | `inspectingAll(currentBundleID:)`, "4 of 10 apps", Stop |
| results | [uninstaller-results-sheet.png](uninstaller-results-sheet.png) | `measured`: every size reads "At least …" (D1) |
| review | [uninstaller-review-sheet.png](uninstaller-review-sheet.png) | `reviewing`: two columns, all items pre-selected, "3 folders not measured yet." |
| cleaning | [uninstaller-cleaning-sheet.png](uninstaller-cleaning-sheet.png) | `cleaning(appName:selectedCount:)`, per-item progress |
| done | [uninstaller-done-sheet.png](uninstaller-done-sheet.png) | `removed(...)`: "At least X moved to the Trash" |
| empty | [uninstaller-empty-sheet.png](uninstaller-empty-sheet.png) | no apps found, Check Again |
| error | [uninstaller-error-sheet.png](uninstaller-error-sheet.png) | a failed inspect (`inspectError`), Show Apps / Try Again |

## Known differences from the prototype

- **Folders carry no size (D1).** The engine reports only a directory-entry size for
  associated folders, so they show "Folder" and any total that includes one reads
  "At least …". Only the app bundle and associated files have measured sizes.
- **Stop keeps measured sizes.** Stopping Measure All keeps the apps already measured
  (Junk's F2 discards). Nothing is invented for the rest.
- **Dock labels follow Appendix A (PR 16).** Results shows the CTA "Review" (disabled — an
  app is chosen per row, so the left side says "Choose an app to review what it left
  behind") with "Measure Again" trailing; done shows "Back to Apps" with "Open Trash";
  empty shows "Check Again". The CTA stays disabled in results because no app is selected —
  it is not a wired-up Review.
- **App panel is an overlay** on the review frame's fixed 250 pt groups column
  (Uninstaller has one app, not a list of groups).
- **Confirmation list shows the engine size** with a "(folder)" suffix, because the shared
  `ConfirmSheet` always renders a size. The uninstall title counts related items
  (selected minus the bundle).
- **A failed inspect turns the screen into the error state** until Show Apps / Try Again.
- **Letter-tile icons.** Real icons (OD-12) appear only when the bundle is on disk; the
  fictional fixture apps get the module-hue letter tile.
- **Not in the static matrix:** the uninstall confirmation (a real macOS sheet), the
  "Quit «App» first" banner (OD-9, running-app check) and Open Trash — covered by
  `SOSMacTests/UninstallerViewModelTests` and the manual run.
- The doubled toolbar title is existing shared-frame behaviour (also visible in PR 5).

## Regenerated in PR 16 (cleanup)

Every sheet in this folder was re-captured from the final PR 16 build, fixture data only
(`SOSMAC_UITEST_FIXTURES=1`, `open -g` background launch, `screencapture -l` window capture,
no foreground, no permission prompt, no real scan). Each `<screen>-<state>-sheet.png` is the dark capture (left) and the light capture (right), each scaled to 920 px wide and joined side by side.

```bash
Scripts/ui-snapshots.sh -p pr-9 -d /tmp/sosmac-pr16-dd   # uninstaller=start … uninstaller=error
```

- Captures: 16; every one is 2400×1520 px (the raw per-appearance files are generated into the
  git-ignored `artifacts/ui-snapshots/` and are not committed); no capture is blank.
- Sheets: 8 × 1840×583. Contact sheet: 1808×1164 (4×4) (dark first, then light).

## PR-description skeleton

```markdown
## What changes for the user
Uninstaller moves to the Palette C lifecycle frame: app list with local filter,
Inspect / Measure All, a two-column review of the app and what it left behind, real
per-item moving progress and an honest Done card ("At least …" wherever a folder is
included), plus a "Quit «App» first" check for running apps.
## Safety impact
Uninstalling always opens the confirmation (Cancel default); running apps are blocked.
Deletes only go through ProgressiveCleaner → Cleaner.clean (Trash). No removeItem in
app code, no invented sizes.
## Prototype states implemented
start · scanning · results · review · cleaning · done · empty · error
## Tests run
xcodebuild build -scheme SOSMac -configuration Debug ·
cd Packages/CleanCore && swift test (115/115) ·
xcodebuild test -only-testing:SOSMacTests (78/78) ·
Scripts/ui-snapshots.sh -p pr-9
```

# PR 5 — Junk & Cache (the reference screen) snapshot gallery

All eight lifecycle states of the migrated Junk & Cache screen, in dark and light,
captured from the real app running on fixture data only (`SOSMAC_UITEST_FIXTURES=1`,
fictional `/Users/sample` paths — no real files were read, moved or trashed). Each
`junk-<state>-sheet.png` places **dark on the left, light on the right**;
`junk-contact-sheet.png` is the whole 4×4 overview (top two rows dark, bottom two light).

Captured with `Scripts/ui-snapshots.sh -p pr-5` (which defaults to these eight
junk states) — background-only window capture, 1200×760 pt. Regenerated in PR 16 (see the last section).

| State | Sheet | Prototype reference |
|---|---|---|
| start | [junk-start-sheet.png](junk-start-sheet.png) | `docs/redesign/prototype/index.html?screen=junk&state=start&palette=c` |
| scanning | [junk-scanning-sheet.png](junk-scanning-sheet.png) | `docs/redesign/prototype/index.html?screen=junk&state=scanning&palette=c` |
| results | [junk-results-sheet.png](junk-results-sheet.png) | `docs/redesign/prototype/index.html?screen=junk&state=results&palette=c` |
| review | [junk-review-sheet.png](junk-review-sheet.png) | `docs/redesign/prototype/index.html?screen=junk&state=review&palette=c` |
| cleaning | [junk-cleaning-sheet.png](junk-cleaning-sheet.png) | `docs/redesign/prototype/index.html?screen=junk&state=cleaning&palette=c` |
| done | [junk-done-sheet.png](junk-done-sheet.png) | `docs/redesign/prototype/index.html?screen=junk&state=done&palette=c` |
| empty | [junk-empty-sheet.png](junk-empty-sheet.png) | `docs/redesign/prototype/index.html?screen=junk&state=empty&palette=c` |
| error | [junk-error-sheet.png](junk-error-sheet.png) | `docs/redesign/prototype/index.html?screen=junk&state=error&palette=c` |

## Known differences from the prototype

- **Scanning shows no current-path line.** The engine's per-rule progress callback
  reports the completed rule's label, not the file being walked; the screen fails
  closed instead of fabricating a path. "k of 4 locations" is real (k = completed
  rules + 1, the rule now active).
- **The trash confirmation is a real macOS sheet** (OD-4/CF-1), not the prototype's
  in-window dialog; the `dialog=trash` state is therefore not part of this static
  matrix — it is covered by `SOSMacTests/ConfirmSheetTests` and the manual run.
- **Done keeps its actions in the dock** (F1: Open Trash trailing, Scan Again CTA)
  rather than repeating them inside the card as the prototype draws.

## Regenerated in PR 16 (cleanup)

Every sheet in this folder was re-captured from the final PR 16 build, fixture data only
(`SOSMAC_UITEST_FIXTURES=1`, `open -g` background launch, `screencapture -l` window capture,
no foreground, no permission prompt, no real scan). Each `<screen>-<state>-sheet.png` is the dark capture (left) and the light capture (right), each scaled to 920 px wide and joined side by side.

```bash
Scripts/ui-snapshots.sh -p pr-5 -d /tmp/sosmac-pr16-dd   # the eight junk states
```

- Captures: 16; every one is 2400×1520 px (the raw per-appearance files are generated into the
  git-ignored `artifacts/ui-snapshots/` and are not committed); no capture is blank.
- Sheets: 8 × 1840×583. Contact sheet: 1808×1164 (4×4) (dark first, then light).
- Junk & Cache keeps the default dock labels (Review Items… / Scan Again / Open Trash), so nothing in these eight states changed with the PR 16 label work.

## PR-description skeleton

```markdown
## What changes for the user
Junk & Cache moves to the new Palette C lifecycle frame with a review screen,
real per-file moving progress, an honest Done card and an "Ignore" action kept
in the detail panel.
## Safety impact
Every removal path opens the trash confirmation (Cancel default). Local deletes
go through ProgressiveCleaner → Cleaner.clean; helper items through
privilegedHelperClient.trashSystemPath. Pre-selection unchanged (safe, no helper).
## Prototype states implemented
start · scanning · results · review · cleaning · done · empty · error
(docs/redesign/prototype/index.html?screen=junk&state=<state>&palette=c)
## Tests run
xcodebuild build -scheme SOSMac -configuration Debug ·
cd Packages/CleanCore && swift test (115/115) ·
xcodebuild test -only-testing:SOSMacTests (61/61) ·
Scripts/ui-snapshots.sh -p pr-5
```

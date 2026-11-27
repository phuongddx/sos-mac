# PR 13 — Protection snapshot gallery

Nine states of the migrated Protection screen (the eight lifecycle states plus the
Quarantine sub-screen), in dark and light, captured from the real app running on fixture
data only (`SOSMAC_UITEST_FIXTURES=1`: fictional `/Users/sample` locations, one EICAR
standard-test-string finding, three fictional quarantine records — nothing real was
scanned, quarantined or restored). Each `protection-<state>-sheet.png` places **dark on the
left, light on the right**; `protection-contact-sheet.png` is the overview.

Captured with `Scripts/ui-snapshots.sh -p pr-13 -s protection=<state>` — background-only
window capture, 1200×760 pt. `ui-snapshots.sh` has no `-e` option, so the Quarantine
sub-screen is selected with the state word `protection=quarantine` (handled by the
ViewModel's DEBUG launch hook).

| State | Sheet | Phase / notes |
|---|---|---|
| start | [protection-start-sheet.png](protection-start-sheet.png) | `idle`: disclaimer note, six scanned-location chips, compact quarantine panel |
| scanning | [protection-scanning-sheet.png](protection-scanning-sheet.png) | `scanning`: 6 steps, "n of N files", ETA, current path, Stop |
| results | [protection-results-sheet.png](protection-results-sheet.png) | `results`: "Known threats" and "Already in quarantine" tiles |
| review | [protection-review-sheet.png](protection-review-sheet.png) | `review`: groups / findings / detail; nothing pre-selected, so "Quarantine…" is disabled |
| cleaning | [protection-cleaning-sheet.png](protection-cleaning-sheet.png) | `quarantining(selectedCount:)`: per-item progress |
| done | [protection-done-sheet.png](protection-done-sheet.png) | `done(quarantinedCount:failedCount:)`: "1 item quarantined", compact panel with Restore |
| empty | [protection-empty-sheet.png](protection-empty-sheet.png) | scan finished, no known signatures found |
| error | [protection-error-sheet.png](protection-error-sheet.png) | `failed(message:)` (fixture copy) |
| quarantine | [protection-quarantine-sheet.png](protection-quarantine-sheet.png) | Quarantine sub-screen: every record in a scroll view (N8), Restore per row |

## Known differences from the prototype

- **Truthful copy (D4).** A "Known-signature scan" banner states this is not real-time
  antivirus; the screen never claims the Mac is "protected".
- **"Check VirusTotal" removed (OD-15).** It did nothing; no replacement.
- **Nothing is pre-selected.** The user checks each finding; the review bar's
  "Quarantine…" stays disabled until then (visible in the review sheet). The confirmation
  has Cancel as default.
- **Quarantine is a reversible move, not a delete.** It goes through `QuarantineManager`
  (not a `Cleaner`) and a SwiftData `QuarantineRecord`. A file that moved but could not be
  recorded counts as a failure and stays in the findings; a failed restore keeps its
  record and shows an error banner. No `FileManager.removeItem` in Protection.
- **Dock labels follow Appendix A (PR 16).** Results with findings shows the CTA "Review"
  (it enters the review screen, with "Review the finding, then quarantine it" on its left and
  "Scan Again" trailing); the disabled "Clean" and the disabled done-dock "Open Trash" are
  gone — Protection quarantines, it does not move to the Trash. Done shows "Scan Again" and
  the card carries "Open Quarantine".
- **Quarantine sub-screen sits outside `ModuleScreen`.** It has no lifecycle state, so it
  composes the aurora background and toolbar itself (back to "Protection").
- **Scanning step is derived.** The engine reports no per-location progress, so the active
  step comes from matching `currentPath` against the location roots.
- **Findings that match no location land in an "Other" group** rather than being dropped.
- **Fixture error text is a fixture**, not a real engine message.
- **Not in the static matrix:** the quarantine confirmation (a real macOS sheet) and a real
  EICAR scan/quarantine/restore in the live app. Engine round trips are covered by
  `SOSMacTests/ProtectionViewModelTests` (hermetic temp dirs, injected quarantine folder,
  in-memory SwiftData).
- The doubled toolbar title is existing shared-frame behaviour (also visible in PR 5/9).

## Regenerated in PR 16 (cleanup)

Every sheet in this folder was re-captured from the final PR 16 build, fixture data only
(`SOSMAC_UITEST_FIXTURES=1`, `open -g` background launch, `screencapture -l` window capture,
no foreground, no permission prompt, no real scan). Each `<screen>-<state>-sheet.png` is the dark capture (left) and the light capture (right), each scaled to 920 px wide and joined side by side.

```bash
Scripts/ui-snapshots.sh -p pr-13 -d /tmp/sosmac-pr16-dd -s protection=start,…,protection=error,protection=quarantine
```

- Captures: 18; every one is 2400×1520 px (the raw per-appearance files are generated into the
  git-ignored `artifacts/ui-snapshots/` and are not committed); no capture is blank.
- Sheets: 9 × 1840×583. Contact sheet: 2260×1164 (5 per row, dark then light) (dark first, then light).

## PR-description skeleton

```markdown
## What changes for the user
Protection moves to the Palette C lifecycle frame: a clearly labelled known-signature
scan with real progress, a three-column review of findings (nothing pre-selected), a
confirmed, reversible quarantine with per-item results, and a Quarantine screen listing
every quarantined file with Restore.
## Safety impact
Quarantine only moves files into a folder SOS Mac controls and records where they came
from; Restore puts them back and keeps the record on failure. No hard-delete path, no
removeItem in Protection, "Check VirusTotal" removed, no real-time-protection claims.
## Prototype states implemented
start · scanning · results · review · cleaning · done · empty · error · quarantine
## Tests run
xcodegen generate ·
xcodebuild build -scheme SOSMac -configuration Debug ·
cd Packages/CleanCore && swift test (115 tests / 28 suites) ·
xcodebuild test -only-testing:SOSMacTests (137 tests / 22 suites, 20 new) ·
Scripts/ui-snapshots.sh -p pr-13 (18 per-appearance captures at 2400x1520; every committed state sheet pairs dark + light into one 1840x583 image, regenerated in PR 16)
```

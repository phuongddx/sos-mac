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
- **Frame CTAs are fixed.** The shared `ModuleScreen` hard-codes the results CTA "Clean"
  (shown disabled) and the done dock "Open Trash" (shown disabled); the cards carry the
  real actions ("Open Quarantine", "Scan Again"). Label overrides in `ModuleScreen` are a
  recommended follow-up (outside this PR's write set).
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
Scripts/ui-snapshots.sh -p pr-13 (18 per-appearance captures at 2400x1520; every committed state sheet pairs dark + light into one 4800x1520 image)
```

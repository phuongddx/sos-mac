# PR 10 — Updater snapshot gallery

Six states of the migrated Updater screen, in dark and light, captured from the real app
running on fixture data only (`SOSMAC_UITEST_FIXTURES=1`: fictional "Example …" apps,
fictional `/Applications` paths, feed URLs on the unresolvable `updates.example.invalid`
host — no real app list was read and **no network request was made**; the fixture loader
applies made-up feed answers directly and never calls the feed). Each
`updater-<state>-sheet.png` places **dark on the left, light on the right**;
`updater-contact-sheet.png` is the 3×4 overview (top two rows dark, bottom two light).

Captured with `Scripts/ui-snapshots.sh -p pr-10 -s updater=<state>` — background-only window
capture, 1200×760 pt (2400×1520 px, verified for all 12 captures).

| State | Sheet | Phase / notes |
|---|---|---|
| start | [updater-start-sheet.png](updater-start-sheet.png) | `idle`: "See which apps have updates", **Check**. Nothing is checked on visit (OD-10). |
| scanning | [updater-scanning-sheet.png](updater-scanning-sheet.png) | `checking`: "Checking «App»…", "3 of 5 apps", Stop |
| results | [updater-results-sheet.png](updater-results-sheet.png) | `results`: Updates available · Update in the App Store · Up to date (· No update feed below the fold) |
| checkfailed | [updater-checkfailed-sheet.png](updater-checkfailed-sheet.png) | `results` + one failed feed (OD-10): row reads "Couldn't check", banner with Try Again; never "Up to date" |
| empty | [updater-empty-sheet.png](updater-empty-sheet.png) | `empty`: "All apps are up to date" — only from real feed answers |
| error | [updater-error-sheet.png](updater-error-sheet.png) | `failed(message:)`: every feed failed, Try Again |

## Known differences from the prototype

- **Frame CTAs are fixed.** The shared `ModuleScreen` hard-codes the results dock
  ("Clean" and "Review Items…", both disabled — Updater never installs anything — and
  "Scan Again") and the empty CTA "Scan Again". Honest "Check Again" / "Try Again" buttons
  are in the content. Label overrides in `ModuleScreen` are a recommended follow-up
  (outside this PR's write set).
- **Two extra groups**: "Couldn't check" (OD-10) and "Not checked yet" (after Stop).
- **No check on visit (OD-10).** The old auto-check is gone; `loadApps()` only lists apps.
- **A failed or empty feed answer is never "Up to date" (D3).** It becomes a per-row
  `checkError`. "All apps are up to date" needs ≥ 1 real feed answer, no failures and no
  App Store rows.
- **Gallery has 6 states** (plan listed 4 + error): `checkfailed` and `error` are extra.
- **Letter-tile icons** — real icons (OD-12) appear only when the bundle is on disk.
- The doubled toolbar title and the "Stopped" toolbar subtitle in the error state are
  existing shared-frame behaviour.
- **Not in the static matrix:** the "No update feed" group (below the fold in `results`),
  "Not checked yet" after Stop, and "View in App Store" — covered by
  `SOSMacTests/UpdaterViewModelTests` (Stop, retry, grouping) and not by a screenshot.

## PR-description skeleton

```markdown
## What changes for the user
Updater moves to the Palette C lifecycle frame. Nothing is checked until you press Check;
progress shows "k of N apps" with Stop; results group apps into Updates available / App
Store / Up to date / No update feed. A feed that fails reads "Couldn't check" with a Try
Again banner — never "Up to date". Read-only: nothing is installed.
## Safety impact
No install, move or delete path. The only network call is the injected feed (Sparkle
appcast check); tests and snapshots use fixture feeds only.
## Prototype states implemented
start · scanning · results · empty · error (+ checkfailed)
## Tests run
xcodebuild build -scheme SOSMac -configuration Debug ·
cd Packages/CleanCore && swift test (115/115) ·
xcodebuild test -only-testing:SOSMacTests (139/139, UpdaterViewModel suite: 22) ·
Scripts/ui-snapshots.sh -p pr-10
```

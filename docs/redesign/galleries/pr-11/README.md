# PR 11 — Cloud Cleanup snapshot gallery

All eight lifecycle states of the migrated iCloud Drive flow, **plus the three
"not set up in this build" states (D5) and the server-delete design target
(`state=drive`)**, in dark and light, captured from the real app running on
fixture data only (`SOSMAC_UITEST_FIXTURES=1`, fictional
`/Users/sample/Library/Mobile Documents/…` paths and synthetic Drive files with
made-up content hashes — no real cloud account, no OAuth, no network, nothing
read from the machine). Each `cloud-<state>-sheet.png` places **dark on the
left, light on the right**; `cloud-contact-sheet.png` is the whole overview
(dark rows first, light rows after).

Captured with `Scripts/ui-snapshots.sh -p pr-11 -s
cloud=start,cloud=scanning,cloud=results,cloud=review,cloud=cleaning,cloud=done,cloud=empty,cloud=error,cloud=gdrive,cloud=dropbox,cloud=onedrive,cloud=drive`
— background-only window capture, 1200×760 pt (2400×1520 px; regenerated in PR 16, see the last section). The extra state
names are lowercase fixture keys spelled by
`CloudCleanupViewModel.loadFixtureFromLaunchHooks`: `gdrive` / `dropbox` /
`onedrive` select their provider in `notConfigured`; `drive` selects Google
Drive and applies the fixture listing (no launch-variable changes needed).

| State | Sheet | Prototype reference |
|---|---|---|
| start | [cloud-start-sheet.png](cloud-start-sheet.png) | `docs/redesign/prototype/index.html?screen=cloud&state=start&palette=c` |
| scanning | [cloud-scanning-sheet.png](cloud-scanning-sheet.png) | `?screen=cloud&state=scanning&palette=c` |
| results | [cloud-results-sheet.png](cloud-results-sheet.png) | `?screen=cloud&state=results&palette=c` |
| review | [cloud-review-sheet.png](cloud-review-sheet.png) | `?screen=cloud&state=review&palette=c` |
| cleaning | [cloud-cleaning-sheet.png](cloud-cleaning-sheet.png) | `?screen=cloud&state=cleaning&palette=c` |
| done | [cloud-done-sheet.png](cloud-done-sheet.png) | `?screen=cloud&state=done&palette=c` |
| empty | [cloud-empty-sheet.png](cloud-empty-sheet.png) | `?screen=cloud&state=empty&palette=c` |
| error | [cloud-error-sheet.png](cloud-error-sheet.png) | `?screen=cloud&state=error&palette=c` |
| gdrive / dropbox / onedrive | [cloud-gdrive-sheet.png](cloud-gdrive-sheet.png) · [cloud-dropbox-sheet.png](cloud-dropbox-sheet.png) · [cloud-onedrive-sheet.png](cloud-onedrive-sheet.png) | the providers column's "Not set up in this build" states (D5) |
| drive (design target) | [cloud-drive-sheet.png](cloud-drive-sheet.png) | `?screen=cloud&state=drive&palette=c` — §5.6 server-side delete |

## Known differences from the prototype

- **The review surfaces draw every set expanded in one list** — which is the
  prototype's own cloud layout (`state=review` and `state=drive` render sets
  inline). A groups + items + detail split (the app's `ReviewFrameView`)
  leaves the middle column unusably narrow next to the 240 pt providers
  column, and the prototype never uses one for Cloud. Composed from the
  shared `ReviewItemRow` + Theme tokens: pinned set heads
  ("N copies · size each"), the keep lock per §4.6, Select All / Deselect All
  spanning **all** sets (never a keep), and no detail column.
- **The not-configured states keep the frame's dock** with the now-disabled
  Scan CTA (ModuleScreen renders the start CTA disabled when a state has no
  primary action — F1's "a missing action disables its control"); the
  prototype omits the dock entirely in that state. Frame chrome is stable
  across states (F6), and the disabled CTA is truthful: nothing can scan.
- **The iCloud error copy carries the engine's reason first**, then "Sign in
  to iCloud in System Settings and turn on iCloud Drive, then scan again."
  as instruction text — **no button** (OD-18 = 1; the pane has no documented
  URL). The prototype draws an "Open System Settings" button.
- **The "Design target · needs a registered sign-in app" ribbon is never
  shipped** (annotation, not UI — §6.3/Appendix B.5); the Google Drive row's
  sub stays "Not set up in this build" in the drive state as well.
- **The cloud confirmation is a real macOS sheet** (OD-4/CF-1) with the
  required acknowledgement, so the `dialog=cloud` state is not part of this
  static matrix — the gate ("Delete from «Provider»" disabled until the
  acknowledgement) is proven by `SOSMacTests/CloudCleanupViewModelTests`
  and `ConfirmSheetTests`, and the sheet's copy names the provider.
- **Fixture figures are fictional and fixed**: 148 files listed on iCloud,
  10 Drive files in 3 content-hash groups. The prototype's 2118/2318 are its
  own fictional constants; ours stay derivable from the committed fixture
  data.
- **The server-delete flow is fixture-only by design** (§5.6 risk note): the
  Drive / OneDrive / Dropbox scan–confirm–delete paths are implemented on the
  real `CloudProvider` protocol and unit-tested with fake providers, but no
  OAuth app exists, so no snapshot can show a live scan. The `drive` state is
  the fixture proof of the surface. A server-side Done ("N files deleted from
  «Provider»", stats Deleted / Couldn't delete, Scan Again — no Open Trash)
  exists in the view model and view but is reachable only post-OAuth.
- The doubled toolbar title is existing shared-frame behaviour (also visible
  in PR 5 and PR 9).

## Regenerated in PR 16 (cleanup)

Every sheet in this folder was re-captured from the final PR 16 build, fixture data only
(`SOSMAC_UITEST_FIXTURES=1`, `open -g` background launch, `screencapture -l` window capture,
no foreground, no permission prompt, no real scan). Each `<screen>-<state>-sheet.png` is the dark capture (left) and the light capture (right), each scaled to 920 px wide and joined side by side.

```bash
Scripts/ui-snapshots.sh -p pr-11 -d /tmp/sosmac-pr16-dd -s cloud=start,…,cloud=error,cloud=gdrive,cloud=dropbox,cloud=onedrive,cloud=drive
```

- Captures: 24; every one is 2400×1520 px (the raw per-appearance files are generated into the
  git-ignored `artifacts/ui-snapshots/` and are not committed); no capture is blank.
- Sheets: 12 × 1840×583. Contact sheet: 1808×1746 (4 per row, dark then light) (dark first, then light).
- Dock labels (PR 16): iCloud Drive keeps the cleaner defaults. API providers (Google Drive, Dropbox, OneDrive) never show "Open Trash" after a server-side delete — their Done dock has no secondary button (`DockCopy(doneSecondary: nil)`) — which no fixture state reaches (the `drive` state is the pre-delete surface). The API-provider results CTA still reads "Clean": the round 80 pt CTA cannot hold "Delete from Google Drive…", which is the label of the confirm button and of the `drive` dock's own button.

## PR-description skeleton

```markdown
## What changes for the user
Cloud Cleanup moves to the Palette C lifecycle frame. iCloud Drive gets the
full flow: a start screen with the local-scan banner, list + compare scanning
with Stop, results tiles, a set review where the newest copy is locked, the
LOCAL Trash confirmation, per-copy moving progress, and an honest Done card.
Google Drive / Dropbox / OneDrive stop pretending (D5): they read "isn't set
up in this build" with a disabled Connect and a one-click path to iCloud
Drive, and the server-side delete flow (selection → danger CTA → cloud
confirmation with acknowledgement) is implemented and tested for the day
OAuth lands.

## Safety impact
iCloud Drive deletes go through the local Trash confirmation (Cancel default)
and ProgressiveCleaner → Cleaner.clean only. Server-side deletes require the
cloud confirmation whose Delete button stays disabled until the
acknowledgement is ticked; nothing is deleted before confirmation (unit-
tested with fake providers — no OAuth, no network anywhere). The keep copy of
every group (newest by modified date) can never be selected; nothing is
pre-selected (OD-7, settled); groups recompute and failures are reported
after every removal (S6).

## Prototype states implemented
iCloud start · scanning · results · review · cleaning · done · empty · error;
Google Drive / Dropbox / OneDrive not-configured (D5); the drive design
target (§5.6 server-side delete).

## Open decisions used
OD-7 → nothing pre-selected in iCloud Drive (settled). OD-18 → (1) iCloud
error as instruction text, no button (settled). D5 → honest not-configured
states (settled).

## Tests run
- [x] xcodebuild build -scheme SOSMac -configuration Debug — 0 errors
- [x] cd Packages/CleanCore && swift test — 115/115
- [x] xcodebuild test -only-testing:SOSMacTests — 134/134 (117 base + 17 new)
- [x] Scripts/ui-snapshots.sh -p pr-11 (this gallery, 12 states × dark/light)

## Differences from the prototype, and why
See "Known differences from the prototype" above.
```

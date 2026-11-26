# PR 6 — Duplicate Finder snapshot gallery

All eight lifecycle states of the migrated Duplicate Finder, in **Exact copies** and
**Similar images** mode, dark and light, captured from the real app running on fixture data
only (`SOSMAC_UITEST_FIXTURES=1`, fictional `/Users/sample` paths — no real files were
read, moved or trashed). Each `duplicates-<state>-sheet.png` places **dark on the left,
light on the right**; `duplicates-contact-sheet.png` (Exact) and
`duplicates-similar-contact-sheet.png` (Similar) are the 4×4 overviews (top two rows dark,
bottom two light). Similar-mode sheets are named `duplicates-similar<state>-sheet.png`.

Captured with `Scripts/ui-snapshots.sh -p pr-6 -s duplicates=<state>,duplicates=similar<state>,…`
— background-only window capture, 1200×760 pt. Similar mode is selected by a `similar`
prefix on the state name (the script and hooks are out of this PR's write set; the prefix is
parsed in `DuplicateFinderViewModel.loadFixtureFromLaunchHooks`, DEBUG only).

| State | Exact | Similar | Prototype reference |
|---|---|---|---|
| start | [sheet](duplicates-start-sheet.png) | [sheet](duplicates-similarstart-sheet.png) | `docs/redesign/prototype/index.html?screen=duplicates&state=start&palette=c` |
| scanning | [sheet](duplicates-scanning-sheet.png) | [sheet](duplicates-similarscanning-sheet.png) | `…&state=scanning…` |
| results | [sheet](duplicates-results-sheet.png) | [sheet](duplicates-similarresults-sheet.png) | `…&state=results…` |
| review | [sheet](duplicates-review-sheet.png) | [sheet](duplicates-similarreview-sheet.png) | `…&state=review…` |
| cleaning | [sheet](duplicates-cleaning-sheet.png) | [sheet](duplicates-similarcleaning-sheet.png) | `…&state=cleaning…` |
| done | [sheet](duplicates-done-sheet.png) | [sheet](duplicates-similardone-sheet.png) | `…&state=done…` |
| empty | [sheet](duplicates-empty-sheet.png) | [sheet](duplicates-similarempty-sheet.png) | `…&state=empty…` |
| error | [sheet](duplicates-error-sheet.png) | [sheet](duplicates-similarerror-sheet.png) | `…&state=error…` |

The error state is identical in both modes (no toolbar segment while stopped), so its two
sheets are the same picture.

## Known differences from the prototype

- **Similar mode pre-selects nothing (OD-a).** The prototype's "Today every copy except
  the newest is selected." line is dropped; Similar results show "0 KB" selected and a
  disabled Clean. The Similar banner uses the spec S3 text on Start, Results and Review.
- **Scanning is honest about the listing pass.** Exact mode reports no progress while it
  lists files, so step 1 has no "files counted" meta; the bar, "k of N files" and the
  percentage appear only once hashing starts (before that: "Counting files in your Home
  folder…"). The path line is the engine's current path.
- **Done's "Kept" is the number of sets that lost a copy** (each still has its kept copy);
  a failed copy gets its own "Couldn't move" stat and an error banner instead of being
  folded into the moved figures (S5).
- **Empty copy never overclaims.** When files were skipped it appends "N files were
  skipped." rather than saying every file is unique. The "14 files were skipped" banner on
  Results comes from the fixture only.
- **Error names Full Disk Access as text only (OD-18):** Privacy & Security › Full Disk
  Access appears in the instruction text; there is no Settings button.
- **The trash confirmation is a real macOS sheet** (OD-4/CF-1), so it is not part of this
  static matrix — covered by `ConfirmSheetTests`, `DuplicateFinderViewModelTests` and
  the manual run.
- **Switching match type discards the results** and returns to Start (the two passes are
  separate scans); it is refused while scanning or moving files.
- **Shared-frame quirks, not changed here** (outside the write set; same as Junk & Cache):
  the toolbar shows the module title twice, the Start bullets are centred rather than
  left-aligned, and the review dock repeats the selection summary on both sides.

## PR-description skeleton

```markdown
## What changes for the user
Duplicate Finder moves to the Palette C lifecycle frame: an Exact copies / Similar images
switch, a review screen by set with the newest copy locked as Keep, real moving progress,
and an honest Done card.
## Safety impact
The newest copy of every set (by date modified, never access time) can't be selected
in either mode; Select All skips it and clean() filters it again. Every removal path opens
the trash confirmation (Cancel default). Deletes go through ProgressiveCleaner →
Cleaner.clean (FileManager.trashItem) only. Exact pre-selection is unchanged (all extra
copies); Similar pre-selects nothing (OD-a).
## Prototype states implemented
start · scanning · results · review · cleaning · done · empty · error, Exact and Similar
(docs/redesign/prototype/index.html?screen=duplicates&state=<state>&palette=c)
## Tests run
xcodebuild build -scheme SOSMac -configuration Debug (exit 0) ·
cd Packages/CleanCore && swift test (115/115) ·
xcodebuild test -only-testing:SOSMacTests (85/85) ·
Scripts/ui-snapshots.sh -p pr-6
```

# PR 8 — Space Lens snapshot gallery

All eight lifecycle states of the migrated Space Lens screen, in **By Folder** and
**By Type**, in dark and light, captured from the real app running on fixture data
only (`SOSMAC_UITEST_FIXTURES=1`, the fictional `/Users/sample` tree — no real files
were read, moved or trashed; the real external-volume list is suppressed in fixtures).
Each folder holds one `<appearance>-spacelens-<state>.png` per capture plus a
`contact-sheet.png` overview. Since PR 16 the committed captures are downscaled to
1200×760 px (1×, `-resize`) to keep the repository small; the contact sheets are 1808×1164.

Captured with `Scripts/ui-snapshots.sh` (background-only window capture, 1200×760 pt):

```bash
Scripts/ui-snapshots.sh -p pr-8 -d /tmp/sosmac-pr8-dd \
  -s spacelens=start,spacelens=scanning,spacelens=results,spacelens=review,\
spacelens=cleaning,spacelens=done,spacelens=empty,spacelens=error
Scripts/ui-snapshots.sh -p pr-8-type -d /tmp/sosmac-pr8-dd -e SOSMAC_UITEST_VIEW=type \
  -s spacelens=start,…   # same eight states over By Type
```

| State | By Folder | By Type | Prototype reference |
|---|---|---|---|
| start | [by-folder/dark-spacelens-start.png](by-folder/dark-spacelens-start.png) | [by-type/dark-spacelens-start.png](by-type/dark-spacelens-start.png) | `index.html?screen=spacelens&state=start&palette=c` |
| scanning | [by-folder/dark-spacelens-scanning.png](by-folder/dark-spacelens-scanning.png) | — | `…state=scanning…` |
| results | [by-folder/dark-spacelens-results.png](by-folder/dark-spacelens-results.png) | [by-type/dark-spacelens-results.png](by-type/dark-spacelens-results.png) | `…state=results…` |
| review (the cleanup-list sheet) | [by-folder/dark-spacelens-review.png](by-folder/dark-spacelens-review.png) | — | `…state=review…` |
| cleaning | [by-folder/dark-spacelens-cleaning.png](by-folder/dark-spacelens-cleaning.png) | — | `…state=cleaning…` |
| done (Back to Map) | [by-folder/dark-spacelens-done.png](by-folder/dark-spacelens-done.png) | — | `…state=done…` |
| empty | [by-folder/dark-spacelens-empty.png](by-folder/dark-spacelens-empty.png) | — | `…state=empty…` |
| error | [by-folder/dark-spacelens-error.png](by-folder/dark-spacelens-error.png) | — | `…state=error…` |

Every state also exists in light (`light-spacelens-<state>.png`).

## Known differences from the prototype

- **The dock uses Space Lens's own Appendix A labels (PR 16).** `results` shows a single
  "Review…" CTA (disabled until something is in the cleanup list, with "Nothing selected" on
  its left) that opens the cleanup-list sheet — the prototype's single "Review…" bar action;
  the frame's separate "Review Items…" button and the "Clean" label are gone. "Scan Again"
  is the trailing button. The toolbar segment (By Folder / By Type) and the subtitle
  "Scanned N items in «root»" carry the review bar's remaining content.
- **Done: CTA "Back to Map" (N7)**, the same action as the button inside the Done card;
  "Open Trash" stays trailing. "Scan Again" is no longer in the Done dock (it is on the map's
  own dock). **Empty:** the CTA reads "Choose Folder…" and opens the folder chooser.
- **By Type cells use the treemap1…8 ramp in fixed category order**, not the spec's
  per-type hue mixed into `card` (§5.5): `Theme` carries no per-category hue token,
  and `Theme.swift` is outside this PR's write set. Legend swatches and map cells
  share the same ramp slot, so they can never disagree. The legend still shows each
  type's real total.
- **Scanning shows no current-path line**: the engine's progress callback reports
  only a count (`ScanProgress.currentPath` is nil from `DiskTreeScanner`), so the
  count line ("Scanned N items…") is shown and no path is fabricated. The same
  fail-closed rule as PR 5.
- **The error state's CTA reads "Try Again"** (the shared frame's error verb) with
  "Choose Another Folder" as the escape; the spec's "Scan Again" and "Try Again"
  are the same action here.
- **Fixture `.dat` files all land in "Other"** and `.xip` falls there too (the
  engine's extension map has no `xip` entry) — the By Type map and legend show those
  real aggregates rather than invented per-type figures.
- **§5.5's "scanned total" for the smaller-items threshold reads as the displayed
  level's total**, matching the prototype's `sum(nodes)`: the 0.4 % merge stays
  correct when drilling down, where a whole-scan total would misclassify the
  level's own cells (the same behavior the smaller-items tests pin).

## Fixture notes

- The fixture tree uses the prototype's declared bytes verbatim; directory sizes are
  not recomputed from children (the prototype's own totals do not sum exactly either).
- `.results` renders with one selected root-level cell ("Old Installers" lives one
  level down), so the inspector detail and the selection ring are visible.
- `.review` presents the real cleanup-list sheet (checkboxes + Total row); the
  fixture cart is two top-most Downloads entries.
- Fixture selections present as policy-eligible so the interactive inspector shows;
  the policy's writable check would otherwise read the real file system, which the
  fixture mode must never do.

## Regenerated in PR 16 (cleanup)

Every sheet in this folder was re-captured from the final PR 16 build, fixture data only
(`SOSMAC_UITEST_FIXTURES=1`, `open -g` background launch, `screencapture -l` window capture,
no foreground, no permission prompt, no real scan). Each `<screen>-<state>-sheet.png` is the dark capture (left) and the light capture (right), each scaled to 920 px wide and joined side by side.

```bash
Scripts/ui-snapshots.sh -p pr-8 -d /tmp/sosmac-pr16-dd -s spacelens=start,…,spacelens=error
Scripts/ui-snapshots.sh -p pr-8-type -d /tmp/sosmac-pr16-dd -e SOSMAC_UITEST_VIEW=type -s spacelens=start,…,spacelens=error
```

- Captures: 32; every one is 2400×1520 px (the raw per-appearance files are generated into the
  git-ignored `artifacts/ui-snapshots/` and are not committed); no capture is blank.
- Sheets: no combined sheets here: 16 per-appearance PNGs in `by-folder/` and 16 in `by-type/`, each 1200×760. Contact sheet: `by-folder/contact-sheet.png` and `by-type/contact-sheet.png`, each 1808×1164 (4×4) (dark first, then light).
- All eight states are captured for By Type as well (the earlier matrix had only start and results); the By Type captures differ from By Folder in scanning, results, review and cleaning; start, done, empty and error are byte-identical in both (they do not depend on the view).

# PR 8 — Space Lens snapshot gallery

All eight lifecycle states of the migrated Space Lens screen, in **By Folder** and
**By Type**, in dark and light, captured from the real app running on fixture data
only (`SOSMAC_UITEST_FIXTURES=1`, the fictional `/Users/sample` tree — no real files
were read, moved or trashed; the real external-volume list is suppressed in fixtures).
Each folder holds one `<appearance>-spacelens-<state>.png` per capture plus a
`contact-sheet.png` overview.

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

- **The dock keeps the shared frame's verbs** (F1/F6): `results` shows the frame's
  "Clean" CTA and the frame's "Review Items…" leading button — both open the same
  cleanup-list sheet, which is the prototype's single "Review…" bar action. The
  toolbar segment (By Folder / By Type) and the subtitle "Scanned N items in «root»"
  carry the review bar's remaining content.
- **Done keeps its actions in the dock** (F1: Scan Again CTA, Open Trash trailing);
  **Back to Map** (N7) is the prominent action inside the Done card.
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

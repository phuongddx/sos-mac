# Review F follow-ups — design note

Date: 2026-11-27 · Branch: fix/review-f-followups → feat/ui-palette-c (stacks on PR #17)

Context: the three independent F reviews of the directly-merged screens (Space Lens PR 8,
Updater PR 10, Protection PR 13) left 13 should-fix findings (6 + 4 + 3) plus doc fixes and
test gaps. PR #19 already fixed the one blocker (Escape on the confirmation sheet). This
note records the behaviour chosen for every decision point in the fixes, one reason each,
so Phương can flip any of them later. Reference spec:
`docs/superpowers/specs/2026-11-26-ui-migration-palette-c-design.md`.

## D1 — Updater: Stop discards, like every other screen

Stop clears every row's verdict (`latestVersion`/`checkError`) and returns to `start`.
Reason: F2 is a global lifecycle rule — "Stop returns to `start` and discards partial
results; a partial list would look complete" — and Junk, Space Lens and Protection already
follow it; a half-checked list under a "N apps checked" subtitle reads like an outcome.
The app list itself stays (Stop is not an un-install); Check Again is one click away.
Rejected: keeping partial verdicts with a "Not checked yet" group — honest per row, but a
second convention for the same button.

## D2 — Updater: Check Again re-enumerates installed apps

Every **full** check rebuilds the rows from `InstalledAppsEnumerator` before asking feeds,
so installed versions are fresh (the F finding: after updating an app elsewhere, its row
still showed "1.2.3 → 1.2.4"), and apps installed or removed since the last visit appear.
"Try Again" (failed feeds only) keeps every result in hand — that is its contract; the full
refresh is Check Again.

## D3 — Updater: versions compare component-wise, marketing vs marketing, build vs build

- "1.0" equals "1.0.0" (missing segments are zero), "1.10" beats "1.9", "2" beats "1.9.9";
  non-numeric segments compare lexicographically and only a strictly-greater result claims
  an update (a new `AppVersion` type in CleanCore, unit-tested).
- A feed's `sparkle:shortVersionString` compares against the app's
  `CFBundleShortVersionString`; a feed that only carries `sparkle:version` (a build
  number) compares against the app's `CFBundleVersion` — marketing and build numbers are
  never mixed.
- If the comparable pair is incomplete (build-only feed, app without `CFBundleVersion`),
  the row reads "Couldn't check" — fail closed, never a guessed verdict.

## D4 — Updater: copy claims only what was checked

- `.empty` ("All apps are up to date") additionally requires **no** no-feed row: every app
  must be checkable and checked (F3: empty means every step succeeded).
- Results header / toolbar subtitle: >0 updates → "N updates available"; 0 updates with
  real verdicts → "No newer versions found"; nothing checkable at all → "No apps could be
  checked". "No updates available" is retired from any state where something went
  unverified — it over-claims after Stop, a failed feed, or an all-no-feed list.
- A failed whole-check still lands in `.failed` (unchanged).

## D5 — Space Lens: cleaned-empty is not scanned-empty

After this session moved everything out of the scanned root, the results-over-empty state
says "You moved everything out of «name»" (Scan Again / Choose Folder…), not "This folder
is empty" — F3: the empty copy claims the scan *found* nothing, which would be false. A
folder that really scanned empty keeps the current copy.

## D6 — Space Lens: Done with 0 moved leads with the failure

When every item failed (0 moved, >0 failed) the Done title is "Nothing could be moved to
the Trash" and the sub says the items are still where they were, with the per-item reasons
below (F4). "0 bytes moved to the Trash" is retired as a headline; the stat row keeps the
honest 0. Mixed and all-success cases keep the current copy.

## D7 — cleanup-list sheet: every row is checkable, the count is live

All rows render with checkboxes inside the existing 132 pt scroll box, and the title's
count follows the checked rows, so title, list and Total row always show the one number
that matters — the number that will move (CF-3). The read-only variants (trash, uninstall,
quarantine, cloud) keep the spec §4.8 first-5 + "and N more" preview.
Recorded deviation: §4.8 pins the first-5 preview for the item list; the cleanup list's
own contract ("Uncheck anything you want to keep", Total follows the checked rows) requires
every row selectable.

## D8 — Space Lens: external volume = local AND (removable OR not internal)

The old filter kept only `volumeIsRemovable == true`, which misses non-removable external
SSDs (they report removable=false, internal=false). New classifier (in CleanCore, pure and
unit-tested over injected flag sets): `isLocal == true && (isRemovable == true ||
isInternal == false)`; a missing flag excludes the volume (fail closed). Network volumes
stay out (not local), the boot volume stays out (internal). Hardware note: no external
SSD was attached to verify on-device — flagged unverified.

## D9 — Space Lens: By Type cells use the type hue + `treemapMix`

Fill the cell with the type's hue, then the `treemapMix` overlay (dark: `card` at 42 %,
light: 24 %) — the exact equivalent of the prototype's
`color-mix(in srgb, hue 42 %, var(--tm-mix))` (spec §5.5), using the existing token.
Hues: the prototype's `data.js` values for Documents `#3B82F6`, Images `#E879F9`, Code
`#6366F1`, Archives `#38BDF8`, Applications `#A78BFA`, Audio `#2DD4BF`. The fixture has no
Video or Other, so those two are derived in the same family and pinned here: Video
`#FB7185`, Other `#94A3B8`. The legend swatch uses the same mixed fill with a 1 pt border
in the pure hue (prototype's legend).

## D10 — Protection: unreadable locations are surfaced

The engine opens every root before walking it. A missing root is a legitimately empty
location (still counted as checked, zero files). A root that cannot be read (permission
denied or any other read error) is reported as an unchecked location, and the results and
empty states say so: "No known threats found — N files checked in 5 of 6 locations" plus a
banner naming what could not be read. Reason: the current code swallows unreadable roots,
so "checked 6 locations" can be false. The spec dropped the prototype's "4 of 6 locations
were checked" copy because "the engine does not report how many locations completed"
(§6.3) — the engine now reports unreadable roots, so the reason no longer applies. Mid-walk
errors on nested sub-directories remain skipped by `FTSWrapper` (unchanged scope).

## D11 — Protection docs tell the truth about quarantine

CLAUDE.md's safety paragraph claimed Protection quarantine routes through
`FileManager.trashItem` as a `Cleaner` conformer. It does not, and must not: quarantine is
a reversible, tracked move into an app-managed folder via `QuarantineManager` with a
persisted record (spec §5.10 — "quarantined, never deleted"). The doc now says local
deletes route through `Cleaner.clean` → `trashItem`, and names quarantine as the one
documented exception; the module list sentence is corrected too (Updater is read-only).
`ProtectionView`'s header comment is rewritten to the current dock/frame reality (it still
describes pre-PR-16 deviations).

## D12 — Protection: the count stat is a count

The Done stat "Quarantined" renders with `isBytes: false` (it is an item count; `isBytes`
is byte-value styling).

## Test additions (the F gaps)

- Space Lens: cleaned-empty copy; Done-all-failed via an injected failing cleaner seam;
  cleanup list >5 rows — all checkable, title count live (stale-title regression).
- Updater: re-check after an installed version changes (a real temp bundle +
  `InstalledAppsEnumerator`); Stop discards; the comparator table; build-vs-marketing
  pairs; multi-feed failure and Try Again recovery; the D4 user-visible strings.
- Protection: mixed success+failure quarantine batch; moved-but-record-failed (persist
  seam); a real mid-scan cancellation; unreadable-location surfacing.

## Deliberately not in this pass (F notes, unchanged)

Duplicate quarantine-list labels, the stale VirusTotal doc comment, synchronous file I/O
on MainActor in the quarantine/restore loop, Updater feed strictness (HTTP status, URL
schemes), the review-bar vs dock deviation, "Moving 1 of N" off-by-one, selection
accessibility gaps, dock Scan re-scanning a stale root, Space Lens gallery README drift.

# Space Lens Cleanup Design

## Goal

Make Space Lens a review-first disk cleanup tool inspired by CleanMyMac’s Space Lens flow: choose a location, scan it, explore its visual size map, choose files or folders, review the selection, and move the approved items to the macOS Trash.

## Scope

The first release supports these scan roots:

- the user’s home directory;
- one user-selected directory;
- a currently mounted external volume.

After a scan, the feature presents the existing treemap in folder mode and type mode. Folder-mode navigation remains breadcrumb-based. Selecting a rectangle opens a detail inspector instead of immediately zooming or removing an item. The inspector presents the display name, full path, size, kind, descendant count for directories, modification date, and cleanup eligibility.

Eligible files and folders can be added to a cleanup cart. The cart shows the number of selected root items and their aggregate reclaimable bytes. It opens a review sheet before cleanup begins. The confirmation action is named “Move to Trash”, never “Delete”.

## User flow

1. The idle screen offers Home Folder, Choose Folder…, and mounted external volumes.
2. The user chooses a scan root and starts a cancellable scan.
3. The scan progress shows a live item count.
4. The completed treemap supports folder drill-down and breadcrumb navigation.
5. Selecting an item shows the inspector. Ineligible items show the reason and no cleanup control.
6. The user adds or removes eligible roots from the cleanup cart.
7. The review sheet lists each selected root, its path, its size, and the total recoverable space.
8. “Move to Trash” runs cleanup, reports reclaimed bytes, and leaves failed items visible with their individual reason.

## Safety requirements

- All cleanup must call `DefaultCleaner.clean(_:)` / `Cleaner.clean(_:)`; no alternative deletion implementation is allowed.
- A cleanup policy must reject system-sensitive roots: `/System`, `/private`, `/usr`, `/bin`, `/sbin`, and the current user’s Trash.
- A candidate must be contained by the selected scan root after standardized-path normalization.
- A candidate must be writable by the current process. Ineligible candidates are never selectable.
- The selected root itself must not be removable through its own scan. This prevents a Home scan from proposing the entire home directory and prevents removal of an external volume’s root.
- When a selected directory contains a selected descendant, only the directory is retained in the cart so its size is not counted twice.
- A missing item, disconnected volume, permission change, or `trashItem` failure must be recorded per item without abandoning other selected items.
- No automatic selection occurs; every cleanup candidate requires the user’s explicit addition to the cart.

## Architecture

### CleanCore

- Add a pure, `Sendable` `SpaceLensCleanupPolicy` that evaluates a `ScanItem` against an allowed root and produces eligibility plus a user-facing rejection reason.
- Extend Space Lens scan output with metadata needed for the inspector: modification date and directory descendant count. Keep filesystem scanning and policy code independent of SwiftUI.
- Reuse `DefaultCleaner` for cleanup result aggregation and Trash semantics.

### App feature

- Extend `SpaceLensViewModel.Phase` with scan-root selection, review, cleaning, and completion states while retaining explicit phases.
- Keep all observable UI state `@MainActor`.
- Run scanning and cleanup in structured tasks; honor scan cancellation and avoid updating stale state after cancellation.
- Introduce focused SwiftUI components for scan-root selection, the item inspector, cleanup cart/footer, and review sheet. Canvas drawing remains in `TreemapCanvasView`.
- Use macOS file selection APIs for a user-chosen directory and mounted-volume enumeration for external drives. If a source becomes unavailable, keep the prior map but show the affected error.

## Error handling

- An unreadable or empty root returns to selection with a concise error.
- A user cancellation returns to the prior safe idle state without partial cleanup.
- Individual cleanup failures remain in the review/result state with the system-provided reason.
- The completion state reports only bytes for successfully moved items.

## Tests

Add Swift Testing coverage in `Packages/CleanCore/Tests/CleanCoreTests/` before production changes:

- permitted ordinary file below a selected root;
- rejection for every protected path family;
- rejection outside the selected root;
- rejection for the scan root itself;
- cart normalization removes selected descendants of an already selected directory;
- metadata aggregation gives correct descendant counts and directory sizes;
- partial cleanup results keep failed items and count only successful bytes.

Run `cd Packages/CleanCore && swift test`, then regenerate the Xcode project only if target membership changes, and run `xcodebuild build -scheme SOSMac -configuration Debug`.

## Non-goals

- Permanent deletion or emptying Trash.
- Automatic “safe” cleanup recommendations in Space Lens.
- File preview, Finder reveal, search, sorting, or batch rename.
- Network volumes, cloud-only placeholders, and privileged helper cleanup in this release.

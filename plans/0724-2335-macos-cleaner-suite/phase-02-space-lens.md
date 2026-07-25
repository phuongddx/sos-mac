# Phase 2: Space Lens (Disk Space Visualizer)

## Context
Treemap-based disk usage visualizer. Well-trodden territory (MacDirStat, Spacie, Neodisk are open-source references). Reuses Phase 0's `FTSWrapper` — this phase is mostly the aggregation + layout + rendering layer on top of scanning already built.

## Requirements
- Full-disk (or user-chosen root) recursive scan producing a tree of `(path, size, children)`.
- Aggregation by file type (Documents/Images/Video/Code/Cache/Other) for the alternate "by category" view.
- Squarified Treemap layout algorithm (Bruls/Huizing/van Wijk) — pure geometry, no UI framework dependency, so it's unit-testable with plain rectangles-in/rectangles-out assertions.
- Render via SwiftUI `Canvas` (not `Path`/`Shape` per-node — `Canvas` is required once node counts reach the thousands, per the research doc's own finding).
- Zoom/pan into a subtree; breadcrumb navigation back out.
- Live updates via `FSEvents` so a re-open doesn't require a full rescan — only worth building once the initial full-scan flow is solid; treat as this phase's stretch goal, not its gate.

## Files to create
- `Packages/TreemapKit/Package.swift` (separate local package — no UI deps, reusable, matches research doc's proposed module boundary)
- `Packages/TreemapKit/Sources/TreemapKit/SquarifiedTreemap.swift`
- `Packages/TreemapKit/Tests/TreemapKitTests/SquarifiedTreemapTests.swift`
- `Packages/CleanCore/Sources/CleanCore/SpaceLens/DiskTreeScanner.swift`
- `Packages/CleanCore/Sources/CleanCore/SpaceLens/FileTypeAggregator.swift`
- `Packages/CleanCore/Sources/CleanCore/SpaceLens/ArenaTree.swift` (memory-efficient node storage — see step 2)
- `App/Features/SpaceLens/SpaceLensView.swift` + `SpaceLensViewModel.swift`
- `App/Features/SpaceLens/TreemapCanvasView.swift`

## Implementation steps
1. Implement `DiskTreeScanner: Scanner` using `FTSWrapper`, building the tree bottom-up (directory sizes = sum of children) — stream into an `ArenaTree` rather than a naive class-per-node tree to keep memory bounded on multi-million-file volumes (research doc explicitly calls out arena allocator + string pool for this).
2. `ArenaTree`: nodes stored in a contiguous array with parent/child indices, path components interned in a string pool — avoids one `String` + one heap object per file.
3. Implement `SquarifiedTreemap.layout(node:in: CGRect) -> [LayoutRect]` as pure geometry — input a size-annotated tree, output rectangles. No SwiftUI import in this package at all.
4. Implement `FileTypeAggregator` mapping extensions/UTIs to categories for the "by type" view mode.
5. `TreemapCanvasView`: draw `LayoutRect`s via `Canvas`, hit-test taps by rect containment (not per-shape gesture recognizers — doesn't scale to thousands of nodes).
6. Wire zoom: tapping a rect re-roots the layout at that node's subtree; breadcrumb bar shows the path back to the volume root.
7. (Stretch) `FSEvents` watcher invalidating only the changed subtree instead of a full rescan.

## Tests / validation
- `SquarifiedTreemapTests`: known input sizes → assert output rectangles sum to the container area and no two rectangles overlap (property-based check, not just golden values).
- `ArenaTree` test: build from a fixture tree, assert directory sizes equal the sum of leaf sizes.
- Manual: run against a real large directory (e.g. `~/Library`), confirm it doesn't hang or balloon memory, and tapping into subtrees navigates correctly.

## Risks / rollback
- Full-disk scans can take a while on spinning/slow-external drives — must run off the main thread with a visible progress indicator, and must be cancellable (user closes the view mid-scan).
- Rollback: this phase is additive (a new tab), doesn't touch Phase 1's deletion logic, safe to disable independently by hiding the tab.

# Phase 3: Duplicate Finder

## Context
Shared foundation for both Space Lens ("show duplicates in this subtree") and Cloud Cleanup ("dedupe before sync"). Standalone feature but designed to be called from both.

## Requirements
- Two-pass algorithm: group by file size first (cheap), then hash only groups with ≥2 files sharing a size (avoid hashing the entire disk).
- Streaming SHA-256 hashing — never load a whole file into memory; read in chunks.
- Perceptual hashing (dHash or pHash) for images specifically, as a second detection mode ("similar images" vs "exact duplicates"), since resized/re-encoded/screenshotted images won't match byte-for-byte.
- Present duplicate groups with a suggested "keep newest / keep in most-used folder" default selection, but require explicit user confirmation before deletion (same trash-only rule as everywhere else).

## Files to create
- `Packages/CleanCore/Sources/CleanCore/Duplicates/SizeGrouper.swift`
- `Packages/CleanCore/Sources/CleanCore/Duplicates/StreamingHasher.swift`
- `Packages/CleanCore/Sources/CleanCore/Duplicates/PerceptualHasher.swift` (dHash on downsampled `CGImage`)
- `Packages/CleanCore/Sources/CleanCore/Duplicates/DuplicateFinder.swift` (composes the above into one `Scanner`)
- `App/Features/Duplicates/DuplicateFinderView.swift` + `DuplicateFinderViewModel.swift`

## Implementation steps
1. `SizeGrouper`: single `FTSWrapper` pass over the chosen root, bucket by exact byte size, discard buckets with only 1 file.
2. `StreamingHasher`: `SHA256` from `CryptoKit`, updated in `FileHandle` chunk reads (e.g. 1 MB buffer), never `Data(contentsOf:)` on the whole file.
3. `DuplicateFinder`: for each size-bucket, hash all members, group by hash → these are exact duplicate groups.
4. `PerceptualHasher`: downsample images to a small grid (e.g. 9x8 for dHash), compute gradient-based hash, group images whose Hamming distance is below a threshold — separate opt-in mode in the UI, clearly labeled "similar" not "identical" so users aren't surprised by near-matches.
5. Selection heuristic: within a duplicate group, pre-check all but the one with the newest modification date (configurable) — user can override any pre-check before confirming.

## Tests / validation
- `SizeGrouperTests`: fixture with known file sizes, assert singleton-size files are excluded.
- `StreamingHasherTests`: assert identical content (even across different file handles/chunk boundaries) hashes identically, and that a large synthetic file doesn't spike test process memory (assert via a size threshold, not literal RSS measurement if that's flaky in CI).
- `PerceptualHasherTests`: same image re-encoded at different quality → small Hamming distance; genuinely different images → large distance.
- Manual: run on a real Photos/Downloads folder, verify duplicate groups look sane before any deletion.

## Risks / rollback
- Perceptual hashing has false positives by nature (that's the point, but it must never be used to *auto*-select for deletion — confirmation-only, always).
- Rollback: purely additive feature depending only on Phase 0 primitives; safe to disable independently.

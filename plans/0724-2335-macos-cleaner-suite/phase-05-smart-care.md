# Phase 5: Smart Care Orchestration

## Context
Pure UX/orchestration layer gluing together Phases 1-4's engines into a single "one-click" flow. No new low-level system work — this is the lowest-risk phase in the whole plan, by design (matches the research doc's own risk rating).

## Requirements
- One-click flow: run Junk Scanner + Duplicate Finder (safe subset) + a curated set of Performance checks concurrently, aggregate results into a single "N issues found, X GB reclaimable" summary.
- User reviews an aggregated list (grouped by source module) before any cleanup executes — Smart Care must not skip the confirmation step that each individual module already enforces.
- Progress UI showing per-module scan status (scanning / done / found N items) while scans run concurrently.
- Post-clean summary (space reclaimed, items removed, any failures) with a link back to the source module for anything that needs manual attention (e.g. Uninstaller-flagged apps, which Smart Care should surface but never auto-uninstall).

## Files to create
- `Packages/CleanCore/Sources/CleanCore/SmartCare/SmartCareOrchestrator.swift`
- `Packages/CleanCore/Sources/CleanCore/SmartCare/SmartCareReport.swift`
- `App/Features/SmartCare/SmartCareView.swift` + `SmartCareViewModel.swift`

## Implementation steps
1. `SmartCareOrchestrator` takes an array of `Scanner` instances (Junk Scanner, Duplicate Finder, a read-only Performance health-check set), runs them concurrently via `TaskGroup`, collects into a `SmartCareReport` keyed by source.
2. Define which specific rules/checks are "Smart Care eligible" — deliberately a subset of each module's full capability (e.g. only the pre-vetted "safe" junk rules from Phase 1, not everything the standalone Junk Scanner can flag). This list lives in one place so eligibility is auditable.
3. `SmartCareViewModel` drives the scan → review → clean → summary state machine; reuses each module's own `Cleaner` for the actual clean step (no duplicate delete logic).
4. Summary view links "N apps look unused" (from Uninstaller, if wired) to the Uninstaller tab rather than offering to remove apps directly from Smart Care — anything irreversible-feeling gets a deliberate extra step.

## Tests / validation
- `SmartCareOrchestratorTests`: fake `Scanner` stubs returning known items, assert the aggregated report groups correctly and total size is summed correctly.
- Manual: run Smart Care end-to-end, confirm the confirmation step actually appears (this is the one thing that must never regress — a "smart" one-click flow silently skipping user review would be a serious trust violation for a cleaner app).

## Risks / rollback
- The main risk is scope creep — it's tempting to let Smart Care do "everything" including risky operations. Keep the Smart-Care-eligible rule list explicitly narrow (see step 2) and resist expanding it without deliberate review.
- Rollback: this phase only orchestrates; disabling it doesn't affect any individual module's standalone operation.

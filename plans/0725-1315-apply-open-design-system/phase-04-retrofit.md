# Phase 4: Retrofit the 8 feature views

Same recipe per module — restyle the View using Phase 1 components to match the module's Open Design mockup screen, without touching the ViewModel or its `Phase` enum.

| Module | View file | Mockup file |
|---|---|---|
| Junk & Cache Scanner | `App/Features/JunkCleaner/JunkCleanerView.swift` | `junk-scanner.html` |
| Uninstaller | `App/Features/Uninstaller/UninstallerView.swift` | `uninstaller.html` |
| Updater | `App/Features/Updater/UpdaterView.swift` | `updater.html` |
| Space Lens | `App/Features/SpaceLens/SpaceLensView.swift` | `space-lens.html` |
| Duplicate Finder | `App/Features/Duplicates/DuplicateFinderView.swift` | `duplicate-finder.html` |
| Performance | `App/Features/Performance/PerformanceView.swift` | `performance.html` |
| Smart Care | `App/Features/SmartCare/SmartCareView.swift` | `smart-care.html` |
| Cloud Cleanup | `App/Features/CloudCleanup/CloudCleanupView.swift` | `cloud-cleanup.html` |

## Recipe
1. Fetch the mockup file from Open Design project `macos-care-suite` (`mcp__open-design__get_file`).
2. Read the current View + ViewModel to know the exact `Phase` cases / state shape available.
3. Map each `Phase` case to the closest mockup state panel (e.g. `.idle` → mockup's empty/landing state, `.scanning` → step-list, `.results`/`.review` → result-tree + sticky footer, `.done`/`.summary` → summary-success card).
4. Reuse Phase 1 components (`careCard()`, `BadgeView`, `ProgressBar`, `EmptyStateView`) instead of ad hoc styling. Only add module-specific bits inline (e.g. duplicate group headers) if no shared component fits — don't force-fit an ill-suited component.
5. Do not change: ViewModel APIs, `Phase` enum, business rules (trash-safe deletes, keep-newest logic, disabled-until-confirmed buttons, privileged-helper gating).
6. Preserve every existing safety-critical UI behavior called out in `docs/code-standards.md` Rule 6 (never auto-delete, explicit confirm) and the deliberate iCloud-vs-API-provider distinction already in `CloudCleanupView`.

## Verify per module
`xcodebuild build -scheme SOSMac -configuration Debug` after each file; a full pass of the existing `CleanCoreTests` suite once all 8 are done to confirm no regressions (`xcodebuild test -scheme CleanCore -configuration Debug`).

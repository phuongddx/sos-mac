# Apply Open Design system across SOS Mac

Source: Open Design project `macos-care-suite` ("Neutral Modern" system — `styles.css` shared by all screens except `onboarding.html`/`paywall.html`, which intentionally use a separate `atelier.css` editorial system and are out of scope here since they have no SwiftUI counterpart yet).

## Status
- [x] Phase 1: Design system tokens + components (`App/DesignSystem/`)
- [x] Phase 2: Sidebar retrofit (`SOSMacApp.swift`)
- [x] Phase 3: Dashboard (new — was a placeholder)
- [x] Phase 4: Retrofit 8 feature views to match their mockup screens

Build: `xcodebuild build -scheme SOSMac` succeeds clean (no new warnings). `swift test` in `Packages/CleanCore` — all 83 tests pass, no regressions. Visual QA not possible in this session (screen-recording permission unavailable to the automation sandbox); app launches and quits cleanly as a smoke test only — a human should eyeball it before shipping.

## Ground rules (apply to every phase)
- Visual/layout only. Do not change ViewModel logic, the `Phase` enum pattern, business rules, or CleanCore.
- No fabricated data. Every mockup number that isn't backed by a real, currently-available value (session ViewModel state, CleanCore query, `FileManager`/`MachHostStats` reading) is either wired to the real source or the element is omitted — not hardcoded.
- New files go under `App/DesignSystem/` and are picked up automatically by `project.yml`'s folder-based `sources: - path: App`; run `xcodegen generate` after adding files, never hand-edit `project.pbxproj`.
- Keep native `NavigationSplitView` window chrome (real traffic lights/vibrancy) — only port the sidebar's visual language (nav-item look, icons, section grouping, storage footer), not the mockup's simulated titlebar.
- Verify with `xcodebuild build -scheme SOSMac -configuration Debug` after each phase.

## Phase 4 modules (same recipe per module, see phase-04-retrofit.md)
Junk & Cache Scanner, Uninstaller, Updater, Space Lens, Duplicate Finder, Performance, Smart Care, Cloud Cleanup.

## Files
- `phase-01-design-system.md`
- `phase-02-sidebar.md`
- `phase-03-dashboard.md`
- `phase-04-retrofit.md`

# Phase 3: Dashboard

New: `App/Features/Dashboard/DashboardView.swift`. Replaces `DashboardPlaceholderView` in `SOSMacApp.swift`.

Mockup (`index.html`) reference sections and their real-data mapping:

| Mockup element | Real source | Decision |
|---|---|---|
| Storage card (used/total/free bar) | `FileManager.default.attributesOfFileSystem(forPath:)` on the boot volume | Wire real — cheap, synchronous, always available |
| Health ring (score "91") | No scoring/Protection system exists (Phase 7 unbuilt) | Omit — do not fabricate a composite score |
| "Run Smart Care" CTA card | Navigates to existing `SmartCareView` | Wire real (just a nav link + icon/copy) |
| Module grid (8 cards) | Nav links to each of the 8 *implemented* modules | Wire real navigation; card subtitle/stat only shown when the module's ViewModel actually exposes a quick synchronous read (e.g. Performance can show live CPU/RAM via `PerformanceViewModel`/`MachHostStats`); otherwise show a neutral "Open" state — no fake "2 days ago" / fake counts |
| Recent activity feed | No persisted cross-session activity log exists anywhere in the app | Omit for this pass — note as a follow-up if the user wants a real activity log later |
| First-run empty state | Matches `data-state-panel="first-run"` in mockup | Use this as the actual default state for modules with no available quick stat, reusing `EmptyStateView` from Phase 1 |

## Files
- `App/Features/Dashboard/DashboardView.swift`
- `App/Features/Dashboard/DashboardViewModel.swift` (thin: exposes storage stats + which modules have a live snapshot to show)

## Wiring into RootView
`SOSMacApp.swift`: replace `DashboardPlaceholderView()` with `DashboardView(onSelect: { selection = $0 })` (or equivalent) so module-card taps change the sidebar selection.

## Verify
`xcodebuild build -scheme SOSMac -configuration Debug`

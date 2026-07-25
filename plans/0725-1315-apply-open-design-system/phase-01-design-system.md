# Phase 1: Design system tokens + components

Source tokens: Open Design `macos-care-suite/styles.css`.

## Files to create (`App/DesignSystem/`)
- `Theme.swift` — `Color` statics (bg, surface, fg, muted, border, accent, success, warn, danger), spacing scale (4/8/12/16/20/24/32/48/80 → `Spacing.xs...xxl`), corner radii (sm 8, md 12, lg 16, pill), `Font` helpers matching `--text-*` scale.
- `Badge.swift` — `BadgeView(text:, style: .safe/.attention/.risk/.neutral/.accent)` — dot + pill, matches `.badge-*` classes.
- `CardModifier.swift` — `.careCard()` view modifier (surface bg, border, radius-md, padding) matching `.card`.
- `ModuleCard.swift` — `ModuleCardView(icon:, title:, subtitle:, stat:, badge:, action:)` matching `.module-card` grid item.
- `ProgressBar.swift` — thin rounded track/fill matching `.progress-track`/`.progress-fill`.
- `EmptyStateView.swift` — icon-in-rounded-square + title + body + CTA, matching `.empty-state`.
- `SidebarStyle.swift` — nav-item row style (icon + label, active = accent fill) + section label, matching `.nav-item`/`.sidebar-section-label`.

## Constraints
- Pure SwiftUI, no CleanCore dependency (these are presentation-only).
- Support light/dark automatically via semantic `Color` (System colors or `Color(nsColor:)` dynamic providers) — mockup's `[data-theme="dark"]` override maps to SwiftUI's automatic dark mode, don't hand-roll a toggle.
- No business logic. No new files outside `App/DesignSystem/`.

## Verify
`xcodegen generate && xcodebuild build -scheme SOSMac -configuration Debug`

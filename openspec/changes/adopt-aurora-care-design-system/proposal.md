## Why

The Open Design mockups for `macos-care-suite` were refreshed from "Neutral Modern" to "Aurora Care" — the same token contract (accent, severity colors, spacing, radii) extended with an aurora bloom, a module hue map, softer/larger geometry (20/28px radii, two-layer elevation), a health dial, and hero-panel headline surfaces. `App/DesignSystem/Theme.swift` and the feature views still implement the older Neutral Modern token values and lack these signature elements, so the shipped app no longer matches the design source of truth.

## What Changes

- Extend `Theme.swift` with the Aurora Care token additions: `accent-2` (gradient partner, never standalone), updated dark-mode bg/surface/border values, `radius-xl` (28px), and the two-layer elevation model (`elev-raised` / `elev-float`) replacing the current flat/no-shadow cards.
- Add the module hue map (11 module identity colors, red excluded) and a mechanism to tint each feature screen's icon tiles, module cards, and hero eyebrow by its module identity — mirroring the CSS `data-module` hook.
- Add a reusable aurora bloom background modifier (one soft two-stop accent glow behind each content area; light/dark opacity differs) for use behind every module's content area.
- Add a `HeroPanelView` (aurora-lit headline surface: eyebrow / title / sub / badge row / one primary CTA, plus a stat block or storage bar behind a hairline divider) to replace ad hoc headline layouts.
- Add a `HealthDialView` (176pt, 12pt stroke, gradient stroke with glow) for the Dashboard health score.
- Update `ModuleCardView`, `BadgeView`, `CareCardModifier`, `ProgressBarView`, `StepRowView`, `StickyFooterView`, `SummaryCardView`, `SidebarNavRow` to the new radii/elevation/gradient tokens and hue-coding hooks.
- Re-skin every Neutral Modern feature screen (Dashboard, Smart Care, Junk Scanner, Uninstaller, Updater, Space Lens, Duplicate Finder, Performance, Cloud Cleanup, Protection, Settings) and all of their documented states (pre-scan / scanning / results / success / empty / error) to consume the updated components.
- **BREAKING**: `Theme.Radius` gains a new `xl` case and existing dark-mode color constants change value — any view reading these tokens directly must be re-verified against both light and dark appearance.
- Out of scope: `onboarding.html` / `paywall.html` (Atelier Zero) are an intentional tonal contrast and are not touched.

## Capabilities

### New Capabilities
- `design-system-tokens`: the Aurora Care token layer in `Theme.swift` — colors, gradients, geometry, elevation, and the module hue map that every shared component and feature view consumes.
- `shared-ui-components`: the `App/DesignSystem/` component library (hero panel, health dial, module card, badges, progress, step row, sticky footer, summary card, sidebar nav row) and the rule that feature views compose these rather than hand-roll styling.

### Modified Capabilities
(none — no existing `openspec/specs/` capabilities predate this change)

## Impact

- Affected code: `App/DesignSystem/*.swift` (all 10 files), every `App/Features/<Module>/*View.swift` across all 11 Neutral Modern modules, `MenuBarHelper` if it renders shared components.
- No changes to `CleanCore`, `TreemapKit`, ViewModels' `Phase` state machines, or any scanning/cleaning logic — this is a visual-layer change only.
- Dependencies: Open Design MCP project `macos-care-suite` (`styles.css` is the token contract; `index.html` is the reference Dashboard implementation).

## ADDED Requirements

### Requirement: Feature views compose shared components, not ad hoc styling
Every Neutral Modern feature view (Dashboard, Smart Care, Junk & Cache Scanner, Uninstaller, Updater, Space Lens, Duplicate Finder, Performance, Cloud Cleanup, Protection, Settings) SHALL build its UI out of `App/DesignSystem/` components rather than hand-rolled card/badge/progress/dialog styling.

#### Scenario: New screen state reuses existing components
- **WHEN** a feature view renders a scanning, results, success, empty, or error state
- **THEN** it uses the shared step list, results tree, progress bar, success card, or empty-state component instead of a locally defined equivalent

### Requirement: Aurora bloom behind every module content area
Every module's content area SHALL render exactly one soft two-stop accent glow behind its content, using the aurora bloom modifier, tuned to the current color scheme's strength (light: subtle, dark: more pronounced).

#### Scenario: Content area renders with bloom
- **WHEN** any feature view's root content container appears
- **THEN** `.auroraBloom()` (or equivalent) is applied exactly once, positioned behind content, non-interactive

#### Scenario: Bloom strength follows color scheme
- **WHEN** the app is in dark mode
- **THEN** the bloom opacity is higher than in light mode, matching the light 0.1 / dark 0.22 strengths in `styles.css`

### Requirement: Hero panel is the module headline surface
Each module screen's headline SHALL be rendered by a single `HeroPanelView` containing: an eyebrow label tinted with the module's hue, a title, a sub-line, a badge row, exactly one primary call-to-action, and either a stat block or a storage bar behind a hairline divider.

#### Scenario: Dashboard hero shows health dial and storage
- **WHEN** the Dashboard's scanned state renders
- **THEN** its `HeroPanelView` shows the health dial as the leading stat block and the segmented storage bar as the trailing element, separated by a hairline divider

#### Scenario: Exactly one primary CTA per hero
- **WHEN** any `HeroPanelView` instance is rendered in any screen state
- **THEN** it contains exactly one primary-styled call-to-action button; any additional actions are secondary or ghost styled

### Requirement: Health dial matches the reference geometry
`HealthDialView` SHALL render a 176pt-diameter ring with a 12pt stroke width, a gradient stroke (success → accent-2) with a glow, and a centered score + label.

#### Scenario: Health score renders in the dial
- **WHEN** `HealthDialView` is given a score value
- **THEN** the ring's fill arc reflects that score, the stroke is the gradient (not a flat color), and the score number is centered inside the ring

### Requirement: Module cards and nav rows are hue-coded by module identity
`ModuleCardView` and `SidebarNavRow` SHALL tint their icon tile using the rendering module's hue from the module hue map, and SHALL apply a stronger hue treatment (solid icon background, colored glow) when representing the active/selected module.

#### Scenario: Inactive nav row shows soft hue wash
- **WHEN** a sidebar nav row for a non-selected module is rendered
- **THEN** its icon tile background is a soft tint of that module's hue, not the module's full-strength color

#### Scenario: Active nav row shows full hue with glow
- **WHEN** the sidebar nav row for the currently selected module is rendered
- **THEN** its icon tile uses the module's hue as a solid fill with a colored glow/shadow, and the icon glyph itself renders white

### Requirement: Severity language stays fixed across all shared components
`BadgeView` and any component conveying status SHALL use exactly three severity meanings — safe (success/green), attention (warn/amber), risk (danger/red) — and red SHALL never be used for a decorative or non-threat purpose in any shared component.

#### Scenario: Badge severity mapping is exhaustive and fixed
- **WHEN** `BadgeView` is given a severity of safe, attention, or risk
- **THEN** it renders using `Theme.success`, `Theme.warn`, or `Theme.danger` respectively, with no other severity color option

#### Scenario: Risk badge reserved for actual threats
- **WHEN** a non-threat condition needs a badge (e.g. "permission not granted", "update token expired")
- **THEN** it uses the attention (amber) badge, never the risk (red) badge

### Requirement: One destructive-confirm dialog reused everywhere
Every module that performs a destructive action (trash/delete via the `Cleaner` protocol) SHALL present the same shared destructive-confirmation dialog component rather than a per-module custom alert.

#### Scenario: Uninstaller and Duplicate Finder show the same dialog shape
- **WHEN** either the Uninstaller or the Duplicate Finder prompts the user before trashing items
- **THEN** both use the same shared dialog component (icon, title, item list, cancel/confirm actions) differing only in copy and item list content

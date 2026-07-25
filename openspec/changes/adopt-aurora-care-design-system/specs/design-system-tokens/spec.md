## ADDED Requirements

### Requirement: Token values match the Aurora Care contract
`Theme` SHALL expose color, geometry, and elevation tokens whose values match `macos-care-suite/styles.css`'s `:root` and `[data-theme="dark"]` blocks exactly, for both light and dark appearance.

#### Scenario: Light-mode neutral and accent tokens
- **WHEN** the system appearance is light
- **THEN** `Theme.background`, `Theme.surface`, `Theme.foreground`, `Theme.muted`, `Theme.border`, `Theme.accent`, `Theme.success`, `Theme.warn`, `Theme.danger` resolve to `#FAFAFA`, `#FFFFFF`, `#111111`, `#6B6B6B`, `#E5E5E5`, `#2F6FEB`, `#17A34A`, `#EAB308`, `#DC2626` respectively

#### Scenario: Dark-mode neutral tokens updated to Aurora Care values
- **WHEN** the system appearance is dark
- **THEN** `Theme.background` resolves to `#17171A`, `Theme.surface` resolves to `#212126`, `Theme.border` resolves to `#33333B` — not the prior Neutral Modern dark values

#### Scenario: Radius scale includes xl
- **WHEN** a view requests `Theme.Radius.xl`
- **THEN** it resolves to 28pt, distinct from `sm` (9pt), `md` (14pt), and `lg` (20pt)

### Requirement: Accent-2 exists only as a gradient/glow partner
`Theme` SHALL expose `accent2` as a token, and SHALL expose it to views only through gradient and glow helpers (e.g. `Theme.accentGradient`, `.auroraBloom()`), never as a color a view assigns directly as a standalone fill, border, or text color.

#### Scenario: Accent-2 used in a gradient helper
- **WHEN** a component renders `Theme.accentGradient`
- **THEN** the gradient's two stops are `Theme.accent` and `Theme.accent2`

#### Scenario: No standalone accent-2 usage
- **WHEN** reviewing any `App/DesignSystem/` or feature-view source file
- **THEN** `Theme.accent2` never appears as a bare fill, border, or foregroundStyle value outside a gradient or glow helper

### Requirement: Module hue map
`Theme` SHALL expose a fixed mapping from each of the 11 feature modules (Dashboard, Smart Care, Junk & Cache, Uninstaller, Updater, Space Lens, Duplicate Finder, Performance, Cloud Cleanup, Protection, Settings) to one identity color, matching `--hue-dashboard` through `--hue-settings` in `styles.css`. Red SHALL NOT appear in this map.

#### Scenario: Every module has a hue
- **WHEN** `Theme.hue(for:)` is called with any of the 11 module identifiers
- **THEN** it returns the corresponding fixed color (e.g. Junk & Cache → `#17B3B3`, Uninstaller → `#EF8B3C`, Protection → `#5566E0`)

#### Scenario: Red is never a module hue
- **WHEN** iterating all 11 module hue values
- **THEN** none of them equals `Theme.danger` (`#DC2626`) or any other red-family value

### Requirement: Two-layer elevation replaces flat borders
`Theme` SHALL expose two elevation levels — raised and float — as reusable shadow definitions, and every card-like surface SHALL use one of the two rather than a flat 1px border with no shadow.

#### Scenario: Standard card uses raised elevation
- **WHEN** a `.careCard()`-modified view is rendered
- **THEN** it applies the raised elevation (two-layer shadow), not a flat border-only style

#### Scenario: Hero and success panels use float elevation
- **WHEN** `HeroPanelView` or the reclaimed-space `SummaryCardView` is rendered
- **THEN** it applies the float elevation (heavier two-layer shadow than raised)

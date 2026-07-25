## Context

`App/DesignSystem/Theme.swift` and its 9 companion component files were transcribed from the Open Design "Neutral Modern" mockups (see `plans/0725-1315-apply-open-design-system/`). The Open Design project `macos-care-suite` has since been redesigned in place — `styles.css`'s own header comment says it is "Neutral Modern tokens + macOS 14 chrome, redesigned with a richer aurora/hue-coded visual identity" and names the result "Aurora Care." It is an evolution of the same contract (same `--accent`, same severity colors, same spacing scale), not a rewrite, but it adds:

- an `--accent-2` gradient partner used only for gradients/glows, never as a standalone color
- a two-layer elevation model (`--elev-raised` / `--elev-float`) replacing flat 1px borders
- `--radius-xl` (28px) for hero/success panels, on top of the existing sm/md/lg scale
- an 11-color module hue map (`--hue-dashboard` … `--hue-settings`), deliberately excluding red
- an aurora bloom (one soft two-stop radial glow per content area, opacity 0.1 light / 0.22 dark)
- new composite components: hero panel, health dial, hue-coded module card/nav icon tile
- revised dark-mode neutrals (`--bg #17171a`, `--border #33333b`) that differ slightly from the current `Theme.swift` dark values (`#1E1E20`, `#3A3A3D`)

This is a design-token and shared-component change, not a data or architecture change — no `CleanCore` or ViewModel `Phase` logic is touched.

## Goals / Non-Goals

**Goals:**
- Bring `Theme.swift` and `App/DesignSystem/` bit-for-bit in line with the token values and component behavior declared in `styles.css`.
- Reproduce the module hue map, aurora bloom, hero panel, and health dial as SwiftUI-idiomatic constructs (view modifiers / dedicated views), not literal CSS ports.
- Re-skin all 11 Neutral Modern feature screens and their documented states so every screen consumes the refreshed `App/DesignSystem/` components instead of ad hoc styling.
- Preserve both light and dark mode, and preserve every existing shared pattern (destructive-confirm dialog, progress+results language, reclaimed-space success card, empty-state style) as a single implementation reused everywhere.

**Non-Goals:**
- No change to `onboarding.html` / `paywall.html` (Atelier Zero) — confirmed as an intentional, separate visual language.
- No change to scan/clean business logic, `Cleaner` protocol dispatch, or any `CleanCore`/`TreemapKit` code.
- No introduction of components absent from `styles.css` (e.g. no new severity color, no module hue outside the documented 11, no second primary CTA per screen state).
- Not a rename of the design system's public identity elsewhere in the codebase (docs referencing "Neutral Modern" are updated for accuracy but this is not a marketing/naming exercise).

## Decisions

**Module hue coding via a SwiftUI environment value, mirroring CSS custom-property inheritance.**
`styles.css` sets `--nav-hue` / `--card-hue` / `--module-hue` per element via attribute selectors and lets child rules read them. SwiftUI has no CSS-custom-property equivalent, so each `Module` case (already implied by the 11 feature folders) maps to a `Theme.hue(for:)` lookup returning the fixed `Color`, and each feature view's root passes its module's hue down via `.environment(\.moduleHue, ...)` so `ModuleCardView`, `SidebarNavRow`, and `HeroPanelView`'s eyebrow can read it without every call site re-threading a parameter. Alternative considered: pass the hue as an explicit init parameter to every component — rejected because it would touch every call site across 11 views for a value that is really ambient per-screen context, exactly what the CSS attribute-selector mechanism expresses.

**Aurora bloom as a `View` extension (`.auroraBloom()`), not a background image.**
The CSS bloom is a `radial-gradient` positioned absolutely behind content, non-interactive, opacity-tuned per theme. The SwiftUI equivalent is a `ZStack`-based background modifier using two overlapping `RadialGradient`s at fixed offsets, reading `Theme.accent` / `Theme.accent2` and switching opacity via `@Environment(\.colorScheme)`. Alternative considered: a static PNG/asset-catalog gradient — rejected because it can't react to per-module accent tinting or light/dark switching without shipping 22 variants.

**Elevation as two named `View` modifiers (`.raisedElevation()` / `.floatElevation()`) instead of a single configurable shadow modifier.**
`--elev-raised` and `--elev-float` are the only two elevation values used anywhere in `styles.css` (cards use raised, hero/success panels use float on hover-lift). Naming them discretely instead of parameterizing shadow radius/opacity keeps call sites matching the CSS vocabulary exactly and prevents ad hoc in-between shadow values from creeping into feature views.

**`Theme.Radius` gains `xl` rather than renaming the scale.**
Existing `sm/md/lg` map 1:1 to the CSS `--radius-sm/md/lg` (values already match: 8↔9, 12↔14, 16↔20 — close enough that the existing code already treats them as the same scale). Only `--radius-xl` (28px) is net-new, used exclusively by `hero-panel` and `summary-success`. Widening `lg` instead of adding `xl` was considered and rejected: `lg` is used pervasively for standard `.card`, and widening it would inflate every card's radius beyond what `styles.css` specifies.

## Risks / Trade-offs

[Dark-mode neutral values shift slightly (`#1E1E20`→`#17171a`, `#3A3A3D`→`#33333b`)] → Low visual risk since the deltas are small, but every screen must be re-screenshotted in dark mode (Dashboard and Performance are dark-first per the mockups) to confirm no hardcoded hex values elsewhere in the app still reference the old constants.

[`accent-2` is easy to misuse as a standalone color once it exists as a token] → Mitigate by only exposing it through the gradient/glow helpers (`Theme.accentGradient`, `.auroraBloom()`), not as a bare `Color` a view can pick directly; document the "gradient partner only" rule as a doc-comment on the token, matching the CSS comment.

[Module hue map duplicates a mapping that also needs to exist in `Theme.swift` and in each feature's ViewModel/View pairing] → Single source of truth: hue map lives only in `Theme.swift` keyed by an existing module identifier (feature folder name or an existing enum if one already discriminates modules); views read it, they don't redeclare it.

[Re-skinning 11 screens × multiple states each is a large, easy-to-under-scope surface] → `tasks.md` enumerates every screen and its documented `data-state-panel` states explicitly so partial completion is visible rather than silently skipped.

## Migration Plan

1. Land token + component layer changes in `App/DesignSystem/` first (additive where possible: new modifiers/views alongside existing ones).
2. Re-skin one screen (Dashboard, since `index.html` is the reference implementation) end-to-end as the pattern for the rest, verified in the simulator/app in both light and dark mode.
3. Roll the same pattern through the remaining 10 screens.
4. Remove any now-unused old styling helpers only after all call sites are migrated.
5. Rollback: this is a visual-only, additive-first change with no data migration; reverting is a plain git revert of `App/DesignSystem/` and the touched feature views.

## Open Questions

- Does an existing enum already discriminate the 11 modules (for keying the hue map), or does one need to be introduced? Resolve by reading the `Phase`/ViewModel files during implementation before adding a new type.
- `MenuBarHelper` is a separate embedded app with its own UI — confirm whether it renders any shared `App/DesignSystem/` components before deciding whether it's in scope.

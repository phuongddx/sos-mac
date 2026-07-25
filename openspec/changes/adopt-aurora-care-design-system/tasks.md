## 1. Token foundation (`Theme.swift`)

- [x] 1.1 Add `Theme.accent2` (`#17B3B3`) and `Theme.accentGradient` (accent → accent2), documented as gradient/glow-only
- [x] 1.2 Update dark-mode neutrals: `background` → `#17171A`, `surface` → `#212126`, `border` → `#33333B` (verify remaining dark tokens against `styles.css` `[data-theme="dark"]` block)
- [x] 1.3 Add `Theme.Radius.xl` (28pt); leave `sm`/`md`/`lg` as-is
- [x] 1.4 Add `Theme.Elevation.raised` / `Theme.Elevation.float` shadow definitions (light + dark variants)
- [x] 1.5 Add the 11-entry module hue map (`Theme.hue(for:)`) keyed off `SidebarDestination` (`App/SOSMacApp.swift`) — the existing 10-case module identifier. Settings has no case/screen yet, so its hue is defined as `Theme.ModuleHue.settings` but not wired to `hue(for:)`.
- [x] 1.6 Confirm no module hue equals `Theme.danger` or another red-family value

## 2. Shared components (`App/DesignSystem/`)

- [x] 2.1 Add `.auroraBloom()` view modifier (two-stop radial glow, non-interactive, opacity 0.1 light / 0.22 dark)
- [x] 2.2 Add `HeroPanelView` (eyebrow tinted by module hue / title / sub / badge row / one primary CTA / stat-block-or-storage-bar behind hairline divider)
- [x] 2.3 Add `HealthDialView` (176pt diameter, 12pt stroke, success→accent2 gradient stroke with glow, centered score + label) — built and available, not yet used anywhere (see 3.1 note)
- [x] 2.4 Update `ModuleCardView` to use `raised`/`float` elevation, `radius-lg`, and hue-coded icon tile (soft wash inactive, solid + glow active) — added required `hue` param; call sites in Dashboard updated
- [x] 2.5 Update `SidebarNavRow` to use hue-coded icon tile with soft-wash/active-glow states — added required `hue` param; call site in `SOSMacApp.swift` updated
- [x] 2.6 Update `CareCardModifier` to apply `raised` elevation instead of flat border-only styling (also fixed radius from `.md` to `.lg` to match `--radius-lg`)
- [x] 2.7 Confirmed `BadgeView` already only exposes safe/attention/risk/neutral/accent — no change needed
- [x] 2.8 Update `ProgressBarView` fill to use `Theme.accentGradient` by default; changed `tint: Color` param to `style: AnyShapeStyle` (added `.successStyle` static) — fixed 4 call sites in `PerformanceView.swift` that used the old `tint:` name
- [x] 2.9 Update `StepRowView` check states to gradient/glow styling with a pulsing active dot — renamed nested `enum State` to `StepState` (it shadowed SwiftUI's `@State` property wrapper) and added an explicit `init` (the synthesized memberwise init was inferred `private` because of the private `@State` field)
- [x] 2.10 Update `StickyFooterView` to bottom-rounded corners (`radius-lg`) matching `.sticky-footer`; already used `.regularMaterial` for the blur/translucency
- [x] 2.11 Update `SummaryCardView` to `radius-xl` + `float` elevation + gradient icon circle + optional `breakdown` row (backward-compatible, opt-in)
- [x] 2.12 Update `EmptyStateView` to the gradient-orb illustration with an opt-in `hue: Color = Theme.accent` param (default preserves prior look; per-screen re-skins in sections 4-13 pass the real module hue)

## 3. Dashboard (`index.html` reference screen)

- [x] 3.1 Re-skin `scanned` state: `HeroPanelView` (real storage bar as trailing stat, hue-coded) + hue-coded module card grid. **Deviation from plan**: did NOT add `HealthDialView` or a recent-activity list here — `DashboardView.swift` has a pre-existing, deliberate comment explaining neither has a real data source (no health-scoring module, no persisted activity log), consistent with this repo's "fail-closed, never guess" rule and this change's own non-goal of not fabricating data. `HealthDialView` stays built and ready for when a real Protection health score exists.
- [x] 3.2 N/A — this SwiftUI app never had a separate "first-run" empty state for the Dashboard (unlike the mockup); every ViewModel already resets to `.idle` per view creation, so the module grid *is* the only Dashboard state. Not fabricating a new state.
- [x] 3.3 Verified via an added `SOSMacUITests` XCUITest target (see section 14) — `xcodebuild test` drove the real app through every sidebar destination in both forced appearances and captured 20 screenshots (10 screens × light/dark). Dashboard in both appearances: hue-coded module cards matching `Theme.ModuleHue` exactly, hero panel with one primary CTA + real storage bar, active sidebar row shows soft accent wash + solid hue icon tile, aurora bloom visible.

## 4. Smart Care

- [x] 4.1 Fetched `smart-care.html`. States: idle (hero w/ health dial + reclaim estimate + "in this pass" cards + automation toggle), running (aggregate card + step list), summary (success card + before/after health + breakdown).
- [x] 4.2 Re-skinned with what's real: `.auroraBloom()` on root, hue-tinted `EmptyStateView` for idle. **Deviation** (same rationale as Dashboard): no fake reclaim estimate, health dial, or automation-schedule UI — `SmartCareViewModel` has no pre-scan estimate, no health scoring, and no scheduling feature. Scanning/review/summary states already use the now-updated `StepRowView`/`careCard`/`SummaryCardView` automatically.
- [x] 4.3 Verified via `SOSMacUITests` screenshots (light-Smart-Care.png / dark-Smart-Care.png) — idle empty-state icon correctly tinted with Smart Care's purple hue in both appearances, aurora bloom present, one primary CTA.

## 5. Junk & Cache Scanner

- [x] 5.1 Fetched `junk-scanner.html`. States: pre-scan (hero + category checklist), scanning (progress + step list), results (category tree + sticky footer + confirm dialog), success (breakdown card).
- [x] 5.2 Re-skinned: `.auroraBloom()` on root, hue-tinted `EmptyStateView` for idle. **Deviation**: no fake "last scan 2 days ago" hero stats or a category-selection checklist — `JunkCleanerViewModel` scans one fixed allowlist (`JunkRule`) with no user-configurable categories and no persisted last-scan history. Results/success/footer already inherit the shared-component updates.
- [x] 5.3 Verified via `SOSMacUITests` screenshots — idle empty-state icon tinted teal (Junk & Cache hue) in both appearances, active sidebar row shows solid teal icon tile + glow.

## 6. Uninstaller

- [x] 6.1 Fetched `uninstaller.html`. States: browsing (hero + sortable app table with expandable leftovers + sticky footer), removed (breakdown card), confirm dialog.
- [x] 6.2 Re-skinned: `.auroraBloom()` on root, hue-tinted `EmptyStateView` and app-icon tile (gradient fill in the module hue + glow, replacing the flat accent tile), added `.elevation(.raised)` to the app/item card rows. **Deviation** (pre-existing, documented in the view's own header comment): one-app-at-a-time inspect flow, no bulk multi-select table, no per-app size/last-used columns — `UninstallerViewModel` doesn't track those.
- [x] 6.3 Verified via `SOSMacUITests` screenshots — real installed-app list renders with orange-gradient (Uninstaller hue) icon tiles per app row in both appearances, active sidebar item correctly highlighted.

## 7. Updater

- [x] 7.1 Fetched `updater.html`. States: available (hero + version table), up-to-date (empty state).
- [x] 7.2 Re-skinned: `.auroraBloom()` on root, hue-tinted `EmptyStateView`. **Deviation** (pre-existing, documented in the view's own header comment): read-only Sparkle-appcast detection only, no "Update All" install action — matches the view's existing scope note. Rows already use the updated `careCard()`.
- [x] 7.3 Verified via `SOSMacUITests` screenshots — real update rows (NSWorkspace app icons + "No update mechanism" neutral badges) render correctly in both appearances with the green Updater sidebar hue active.

## 8. Space Lens

- [x] 8.1 Fetched `space-lens.html`. States: loaded (slim hero + treemap + inspector), loading (skeleton shimmer). Treemap uses its own `--type-*` file-encoding palette, separate from module hue, by design.
- [x] 8.2 Re-skinned: `.auroraBloom()` on root, hue-tinted source-picker icon (idle/pre-scan state), `.elevation(.raised)` on the inspector panel. `TreemapCanvasView`'s own fill colors left untouched — data encoding, not chrome, per `styles.css`'s own comment.
- [x] 8.3 Verified via `SOSMacUITests` screenshots — source-picker empty state tinted purple (Space Lens hue) in both appearances; sidebar active state correct.

## 9. Duplicate Finder

- [x] 9.1 Fetched `duplicate-finder.html`. States: scope (hero + location picker pills), results (thumbnail/document set cards + sticky footer + confirm dialog), success (breakdown card).
- [x] 9.2 Re-skinned: `.auroraBloom()` on root, hue-tinted `EmptyStateView` for idle. Group cards already use the updated `careCard()`; the recommended-keep toggle was already `.disabled(isRecommendedKeep)` (Duplicate Finder's own required rule, unaffected). **Deviation**: no location-scope picker UI (checkbox pills for Photos/Documents/Downloads/Desktop) — `DuplicateFinderViewModel` scans a fixed root path with an exact/similar mode toggle, not user-selectable multi-location scope.
- [x] 9.3 Verified via `SOSMacUITests` screenshots — idle empty-state and mode picker render correctly in both appearances with the pink Duplicate Finder hue active in the sidebar.

## 10. Performance

- [x] 10.1 Fetched `performance.html`. States: single live-monitor view (no distinct empty/error state in the mockup). Confirms the metric-encoding palette: CPU→accent, Memory→warn (`--metric-memory: var(--warn)`) — so the pre-existing `tint: Theme.accent` / `tint: Theme.warn` choices fixed mechanically in section 2 were already correct.
- [x] 10.2 Re-skinned: `.auroraBloom()` on root. **Deviation** (pre-existing, documented in the view's own header comment): no Disk/Network sparkline tiles, no Processes table, no per-app Login-Item toggles — no real data source for any of those (`SMAppService` only manages this app's own login item). Metric cards, maintenance rows, and login-items card already use the updated `careCard()`.
- [x] 10.3 Verified via `SOSMacUITests` screenshots — live metric cards (CPU/Memory/Thermal/Load), maintenance rows, and menu-bar-widget card all render correctly in both appearances with the amber Performance hue active.

## 11. Cloud Cleanup

- [x] 11.1 Fetched `cloud-cleanup.html`. States: landing (hero + provider cards), connect (OAuth-scope explainer card), browser (folder tree + file table + sticky footer). Provider brand colors (`--provider-drive` etc.) already matched exactly by the existing `providerIcon(_:)` hex values.
- [x] 11.2 Re-skinned: `.auroraBloom()` on root, hue-tinted the 3 `EmptyStateView` calls (connect/no-duplicates/iCloud) with the generic Cloud Cleanup module hue (mockup doesn't tint these per-provider). Provider tiles, duplicate lists already use updated `careCard()`/`StickyFooterView`. **Deviation** (pre-existing, documented in the view's own comments): no combined-quota hero stat or per-provider quota bars — `CloudAPIProviderState` has no quota field; no folder-tree browser — real API integration lists flat file/duplicate results, not a navigable tree.
- [x] 11.3 Verified via `SOSMacUITests` screenshots — provider tabs, connect card, and Google Drive disconnected state render correctly in both appearances with the blue Cloud Cleanup hue active.

## 12. Protection

- [x] 12.1 Fetched `protection.html`. States: control (hero + scan-type chooser + monitoring toggle), scanning (ticker + progress), clean (success card), threats (risk rows + remove-all), vault (quarantine list). Confirms red/`badge-risk` is used only for actual detections/threats, never decoratively — matching the existing code's own severity usage.
- [x] 12.2 Re-skinned: `.auroraBloom()` on root, hue-tinted `EmptyStateView` for idle. **Deviation** (pre-existing): no Quick/Deep scan-type chooser, no real-time-protection toggle, no last-scan stat block — `ProtectionViewModel` has one fixed scan behavior and no monitoring-daemon feature. Findings list, quarantine section, and summary card already use updated shared components; risk-only badge usage was already correct.
- [x] 12.3 Verified via `SOSMacUITests` screenshots — idle empty-state disclaimer banner and Start Scan CTA render correctly in both appearances with the indigo Protection hue active; confirmed no red/risk color appears outside actual threat contexts (none present in idle state).

## 13. Settings

- [x] 13.1 N/A — `SidebarDestination` (`App/SOSMacApp.swift`) has no `.settings` case and there is no `SettingsView` anywhere in `App/Features/`. Confirmed via search, not assumed.
- [x] 13.2 N/A — nothing to re-skin. Building a new Settings feature is out of scope for a design-system change (see proposal's Non-Goals); `Theme.ModuleHue.settings` stays defined and unused, ready for when that feature ships.
- [x] 13.3 N/A — no screen exists to verify.

## 14. Verification and docs

- [x] 14.1 `xcodegen generate` run once after adding the 4 new `App/DesignSystem/` files (Elevation/AuroraBloom/HeroPanel/HealthDial modifiers+views); no further file adds/renames after that.
- [x] 14.2 `xcodebuild build -scheme SOSMac -configuration Debug` succeeds (verified twice: after the foundation, and again after all 10 screens).
- [x] 14.3 `cd Packages/CleanCore && swift test` passes 102/102 (verified twice, same as above). No CleanCore files were touched.
- [x] 14.4 Added `SOSMacUITests/AuroraCareScreenshotTests.swift` (new XCUITest target, wired via `project.yml`'s `schemes.SOSMac.test`) instead of relying on System Events UI-scripting, which would have needed a system-level Accessibility permission grant I wasn't willing to make unilaterally. XCUITest drives the app directly through Xcode's own test-hosting mechanism — no such permission prompt appears. Added a `SOSMAC_UITEST_APPEARANCE` launch-environment hook read only by `RootView` (`.preferredColorScheme`, no-op unless set) so both appearances are screenshotted deterministically without touching the developer's real system appearance, and `.accessibilityIdentifier` on each sidebar row for reliable lookup. `xcodebuild test -scheme SOSMac -only-testing:SOSMacUITests/AuroraCareScreenshotTests` passed, producing 20 screenshots (10 screens × light/dark) — all reviewed and confirm correct hue-coding, elevation, aurora bloom, and severity-badge usage.
- [x] 14.5 Updated `CLAUDE.md`'s design-reference section to describe Aurora Care as the current system (see below).
- [x] 14.6 No new numbers were introduced anywhere (this change touched styling/tokens, not copy or sample data) — nothing to reconcile.

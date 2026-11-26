#if DEBUG
import SwiftUI

/// Debug-only component gallery (PR 4a): every `App/DesignSystem` primitive in every state on one
/// screen, so one background snapshot shows them all.
///
/// Open with `SOSMAC_UITEST_SCREEN=gallery` — for example
/// `Scripts/ui-snapshots.sh -p pr4a -1 -s gallery=default -w 1200x1900`. The gallery replaces the
/// whole app for that launch; a normal launch never shows it.
///
/// Every value on screen is fictional (the prototype's sample data, or paths under
/// `/Users/sample` like `UITestFixtures`). Nothing is read from the Mac.
struct ComponentGalleryView: View {
    /// The ten module hues with their ink (spec §2.5) and the prototype's symbols.
    private static let hues: [(name: String, hue: Color, ink: Color, symbol: String)] = [
        ("smartcare", Theme.Hue.smartcare, Theme.Hue.Ink.smartcare, "wand.and.stars"),
        ("junk", Theme.Hue.junk, Theme.Hue.Ink.junk, "trash"),
        ("duplicates", Theme.Hue.duplicates, Theme.Hue.Ink.duplicates, "doc.on.doc"),
        ("spacelens", Theme.Hue.spacelens, Theme.Hue.Ink.spacelens, "square.grid.3x3"),
        ("cloud", Theme.Hue.cloud, Theme.Hue.Ink.cloud, "icloud"),
        ("uninstaller", Theme.Hue.uninstaller, Theme.Hue.Ink.uninstaller, "xmark.bin"),
        ("updater", Theme.Hue.updater, Theme.Hue.Ink.updater, "arrow.triangle.2.circlepath"),
        ("performance", Theme.Hue.performance, Theme.Hue.Ink.performance, "gauge.with.dots.needle.50percent"),
        ("protection", Theme.Hue.protection, Theme.Hue.Ink.protection, "checkmark.shield"),
        ("threat", Theme.Hue.threat, Theme.Hue.Ink.threat, "exclamationmark.triangle"),
    ]

    private static let panelRadius = Theme.Radius.lg
    private static let panelPadding: CGFloat = 18

    @State private var checkbox: SOSCheckbox.State = .mixed
    @State private var rowSelected = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.s6) {
                header
                section("tiles", "Module tiles — nav (plain · current), result, card, row") { tiles }
                section("buttons", "Buttons — stock 28 pt (default · prominent · danger) and custom (plain · large 34 pt)") { buttons }
                section("badges", "Badges — on card, then on a selected row") { badges }
                section("checkboxes", "Checkboxes — off · on · mixed · kept; a focused row and a kept row") { checkboxes }
                section("steps", "Step rows — pending · active · done · failed — and progress") { steps }
                section("banners", "Banners — info · warn · err with an action · ok") { banners }
                section("results", "Result tiles — default · selected · skipped · full") { resultTiles }
                section("lifecycle", "ModuleScreen — every lifecycle state (toolbar model, aurora canvas, dock / review bar)") { lifecycleFrames }
                section("dock", "Dock and CTA — default · ring (determinate · indeterminate) · stop · moving · disabled; meta figures") { dockAndCTA }
                section("start", "StartView — orb, bullets, note") { start }
                section("scanning", "ScanningView — orb sweep, steps, progress, path (and the cleaning copy)") { scanning }
                section("done", "DoneView — card, stats, actions, hint") { done }
                section("status", "StatusStateView — ok · neutral · error") { statusStates }
                section("results-head", "ResultsHeaderView — with and without trailing tools") { resultsHead }
                section("review", "ReviewFrameView — three columns · two columns · kept and focused rows · virtualised") { review }
                section("review-bar", "ReviewBarView — selection and empty · custom noun") { reviewBars }
                section("confirm", "ConfirmSheet — trash · cloud · uninstall · quarantine · cleanup list") { confirms }
            }
            .padding(Theme.Spacing.s8)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .auroraBackground(hue: Theme.Hue.junk)
        .background(Theme.Color.bgBase)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("gallery")
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s1) {
            Text("Components · Palette C")
                .font(Theme.Font.title1)
                .foregroundStyle(Theme.Color.textPrimary)
            Text("Debug gallery. Every value is fictional sample data. The canvas is \(Text(verbatim: "AuroraBackground").font(Theme.Font.mono)) with the Junk & Cache hue.")
                .font(Theme.Font.callout)
                .foregroundStyle(Theme.Color.textSecondary)
        }
    }

    private var tiles: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s3) {
            ForEach(Self.hues, id: \.name) { tile in
                VStack(spacing: Theme.Spacing.s1) {
                    ModuleTileView(hue: tile.hue, ink: tile.ink, symbol: tile.symbol, size: .nav)
                    ModuleTileView(hue: tile.hue, ink: tile.ink, symbol: tile.symbol, size: .nav, glow: true)
                    ModuleTileView(hue: tile.hue, ink: tile.ink, symbol: tile.symbol, size: .result)
                    ModuleTileView(hue: tile.hue, ink: tile.ink, symbol: tile.symbol, size: .card)
                    ModuleTileView(hue: tile.hue, ink: tile.ink, symbol: tile.symbol, size: .row)
                    Text(tile.name)
                        .font(Theme.Font.eyebrow)
                        .foregroundStyle(Theme.Color.textSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var buttons: some View {
        VStack(spacing: Theme.Spacing.s4) {
            HStack(spacing: Theme.Spacing.s5) {
                sample("stock · default") { Button("Review Items") {}.sosButton(.default) }
                sample("stock · prominent") { Button("Move to Trash…") {}.sosButton(.prominent) }
                sample("stock · danger") { Button("Delete from Google Drive") {}.sosButton(.danger) }
                sample("disabled") { Button("Scan Again") {}.sosButton(.default).disabled(true) }
                sample("disabled") { Button("Move to Trash…") {}.sosButton(.prominent).disabled(true) }
                sample("disabled") { Button("Delete from Google Drive") {}.sosButton(.danger).disabled(true) }
            }
            HStack(spacing: Theme.Spacing.s5) {
                sample("plain") { Button("Select All") {}.buttonStyle(.sosPlain) }
                sample("plain · icon") {
                    Button { } label: { Label("Open Space Lens", systemImage: "square.grid.3x3") }
                        .buttonStyle(.sosPlain)
                }
                sample("plain · disabled") { Button("Deselect All") {}.buttonStyle(.sosPlain).disabled(true) }
                sample("large · default") { Button("Scan Again") {}.buttonStyle(.sosLarge(.default)) }
                sample("large · prominent") {
                    Button { } label: { Label("Run Smart Care", systemImage: "wand.and.stars") }
                        .buttonStyle(.sosLarge())
                }
                sample("large · disabled") { Button("Run Smart Care") {}.buttonStyle(.sosLarge()).disabled(true) }
            }
        }
    }

    private var badges: some View {
        let row = HStack(spacing: Theme.Spacing.s2) {
            BadgeView(text: "Safe", style: .safe)
            BadgeView(text: "Caution", style: .caution)
            BadgeView(text: "Needs approval", style: .caution, systemImage: "exclamationmark.triangle")
            KeepBadge()
            BadgeView(text: "Newest copy kept", style: .keep)
            BadgeView(text: "Threat", style: .threat, systemImage: "shield")
            BadgeView(text: "Failed", style: .risky, systemImage: "xmark")
            BadgeView(text: "Helper", style: .neutral, systemImage: "key")
            BadgeView(text: "Newest", style: .accent)
        }
        return VStack(alignment: .leading, spacing: Theme.Spacing.s3) {
            row
            row
                .padding(.vertical, Theme.Spacing.s2)
                .padding(.horizontal, Theme.Spacing.s3)
                .background(Theme.Derived.rowSelected, in: RoundedRectangle(cornerRadius: Theme.Radius.sm))
            Text("Caution label: the kind's colour in both appearances (X4 withdrawn).")
                .font(Theme.Font.subheadline)
                .foregroundStyle(Theme.Color.textSecondary)
        }
    }

    private var checkboxes: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s4) {
            HStack(spacing: Theme.Spacing.s5) {
                sample("off") { SOSCheckbox(state: .off, label: "Off") { } }
                sample("on") { SOSCheckbox(state: .on, label: "On") { } }
                sample("mixed") { SOSCheckbox(state: checkbox, label: "Some") { checkbox = checkbox.toggled() } }
                sample("kept · disabled") { SOSCheckbox(state: .off, isKept: true, label: "Kept copy") { } }
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 0) {
                itemRow(
                    state: rowSelected ? .on : .off,
                    name: "Cache.db",
                    path: "/Users/sample/Library/Caches/com.example.musicplayer/Data/Cache.db",
                    size: "612.5 MB",
                    badge: BadgeView(text: "Safe", style: .safe),
                    isKept: false,
                    tint: Theme.Derived.rowSelected
                ) { rowSelected.toggle() }
                itemRow(
                    state: .off,
                    name: "onboarding-walkthrough.mov",
                    path: "/Users/sample/Movies/Exports/onboarding-walkthrough.mov",
                    size: "1.24 GB",
                    badge: KeepBadge(),
                    isKept: true,
                    tint: nil,
                    action: {}
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).strokeBorder(Theme.Derived.hairline, lineWidth: 1))
        }
    }

    private func itemRow(
        state: SOSCheckbox.State,
        name: String,
        path: String,
        size: String,
        badge: some View,
        isKept: Bool,
        tint: Color?,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: Theme.Spacing.s3) {
            SOSCheckbox(state: state, isKept: isKept, label: isKept ? "Kept copy" : "Select \(name)", action: action)
            VStack(alignment: .leading, spacing: Theme.Spacing.s1 / 2) {
                Text(name)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Color.textPrimary)
                    .lineLimit(1)
                Text(path)
                    .font(Theme.Font.mono)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            badge
            Text(size)
                .font(Theme.Font.callout)
                .foregroundStyle(Theme.Color.textSecondary)
                .monospacedDigit()
                .frame(minWidth: 64, alignment: .trailing)
        }
        .padding(.vertical, Theme.Spacing.s2)
        .padding(.horizontal, Theme.Spacing.s4)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.Derived.hairline).frame(height: 1) }
        .modifier(RowTint(tint: tint))
        .modifier(KeptRow(isKept: isKept))
        .modifier(RowAccessibility(isKept: isKept, name: name, size: size))
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s4) {
            VStack(spacing: Theme.Spacing.s1) {
                StepRowView(name: "User App Caches", meta: "Found 9", state: .done)
                StepRowView(name: "User Logs", meta: "Found 5", state: .done)
                StepRowView(name: "App Support Caches", meta: "Scanning…", state: .active)
                StepRowView(name: "System Caches", meta: "Waiting…", state: .pending)
                StepRowView(name: "Old iOS Backups", meta: "Couldn't read 3 folders", state: .failed)
            }
            .frame(maxWidth: 520)

            VStack(alignment: .leading, spacing: Theme.Spacing.s2) {
                ProgressBarView(progress: 0.62)
                ProgressBarView(progress: 0)
                ProgressBarView(progress: 1)
                // The pre-redesign meters (Performance) pass their own fill.
                ProgressBarView(progress: 0.46, style: AnyShapeStyle(Theme.Color.primaryDeep), height: 4)
            }
            .frame(maxWidth: 520)
        }
    }

    private var banners: some View {
        VStack(spacing: Theme.Spacing.s3) {
            BannerView(kind: .info, title: "Files go to the Trash",
                       text: "You can put them back until you empty the Trash.")
            BannerView(kind: .warn, title: "Similar isn't identical",
                       text: "There's no preview or similarity score yet, so check each image before you move it.")
            BannerView(kind: .err, title: "Couldn't read 3 folders",
                       text: "SOS Mac needs Full Disk Access to scan them.") {
                Button("Try Again") {}.sosButton(.default)
            }
            BannerView(kind: .ok, title: "Free up RAM finished", text: "macOS released inactive memory.")
        }
    }

    private var resultTiles: some View {
        VStack(spacing: 14) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                ResultTileView(
                    hue: Theme.Hue.junk, ink: Theme.Hue.Ink.junk, symbol: "trash",
                    label: "Junk & Cache", value: "3.4", unit: "GB",
                    caption: "selected of 4.1 GB · 1,284 files in 3 locations"
                ) {
                    Button("Review Items") {}.sosButton(.default)
                }
                ResultTileView(
                    hue: Theme.Hue.duplicates, ink: Theme.Hue.Ink.duplicates, symbol: "doc.on.doc",
                    label: "Duplicate files", value: "2.8", unit: "GB",
                    caption: "selected · 6 sets, 8 extra copies",
                    isSelected: true
                ) {
                    BadgeView(text: "Newest copy kept", style: .keep)
                }
                ResultTileView(
                    hue: Theme.Hue.duplicates, ink: Theme.Hue.Ink.duplicates, symbol: "doc.on.doc",
                    label: "Duplicate files", value: "2.8", unit: "GB",
                    caption: "Scan stopped", isSkipped: true
                ) {
                    BadgeView(text: "Failed", style: .risky, systemImage: "xmark")
                }
                ResultTileView(
                    hue: Theme.Hue.cloud, ink: Theme.Hue.Ink.cloud, symbol: "icloud",
                    label: "Sets found", value: "6",
                    caption: "14 files in total"
                )
            }
            ResultTileView(
                hue: Theme.Hue.performance, ink: Theme.Hue.Ink.performance, symbol: "gauge.with.dots.needle.50percent",
                label: "Health check · read-only", value: "", span: .full,
                detail: AnyView(
                    HStack(spacing: 0) {
                        health("Load average (1 min)", "2.41", divider: false)
                        health("Memory in use", "11.24 GB of 16.00 GB", divider: true)
                        health("Thermal state", "Nominal", divider: true)
                    }
                    .padding(.top, Theme.Spacing.s3)
                )
            )
        }
    }

    /// One column of the health check (the prototype's `.health > div`).
    private func health(_ label: String, _ value: String, divider: Bool) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s1) {
            Text(label)
                .font(Theme.Font.callout)
                .foregroundStyle(Theme.Color.textSecondary)
            Text(value)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.Color.textPrimary)
                .monospacedDigit()
        }
        .padding(.vertical, Theme.Spacing.s1 / 2)
        .padding(.horizontal, divider ? Theme.Spacing.s4 : 0)
        .overlay(alignment: .leading) {
            if divider {
                Rectangle().fill(Theme.Derived.hairline).frame(width: 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - PR 4b — lifecycle frame, review frame, confirmation

    /// One shared identity for the PR 4b samples: Junk & Cache, with fictional values only.
    private static let junkModule = ModuleIdentity(module: .junkCleaner)

    private var lifecycleFrames: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.Spacing.s3), GridItem(.flexible(), spacing: Theme.Spacing.s3)],
                  spacing: Theme.Spacing.s3) {
            ForEach(LifecycleState.allCases) { state in
                VStack(spacing: Theme.Spacing.s1) {
                    frameSample(state)
                        .frame(height: 360)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                            .strokeBorder(Theme.Derived.hairline, lineWidth: 1))
                    Text(state.rawValue)
                        .font(Theme.Font.eyebrow)
                        .foregroundStyle(Theme.Color.textSecondary)
                }
            }
        }
    }

    /// The frame around the state's own content; actions are no-ops so every control draws
    /// enabled, and every figure is the prototype's sample data.
    @ViewBuilder
    private func frameSample(_ state: LifecycleState) -> some View {
        ModuleScreen(
            module: Self.junkModule,
            state: state,
            subtitle: nil,
            actions: ModuleScreen.Actions(
                primary: {}, stop: {}, reviewItems: {}, scanAgain: {}, openTrash: {},
                escape: ModuleScreen.Actions.Escape(label: "Open System Settings", action: {})),
            progress: state == .scanning ? 0.62 : nil,
            selection: state == .results || state == .review
                ? ModuleScreen.SelectionSummary(count: 3, sizeText: "1.18 GB") : nil
        ) {
            switch state {
            case .start:
                StartView(module: Self.junkModule,
                          title: "Clear caches and old logs",
                          lede: "SOS Mac finds caches and old logs the apps themselves created, and shows you every file before anything moves.",
                          bullets: [
                              .init(symbol: "trash", title: "Junk & Cache", text: "App caches, old logs and app support caches. 4 locations, no extra permission."),
                              .init(symbol: "key", title: "System Caches", text: "Needs your approval once. Never selected for you."),
                          ],
                          note: "System Caches need your approval. They're never selected for you.")
            case .scanning:
                ScanningView(module: Self.junkModule,
                             title: "Looking for junk files…",
                             steps: [
                                 .init(name: "User App Caches", meta: "Found 9", state: .done),
                                 .init(name: "User Logs", meta: "Found 5", state: .done),
                                 .init(name: "App Support Caches", meta: "Scanning…", state: .active),
                                 .init(name: "System Caches", meta: "Waiting…", state: .pending),
                             ],
                             progress: 0.62,
                             progressLeading: "3 of 4 locations",
                             path: "/Users/sample/Library/Application Support/com.example.musicplayer/Caches")
            case .results:
                resultsContent
            case .review:
                reviewContent
                    .frame(height: 230)
            case .cleaning:
                ScanningView(module: Self.junkModule,
                             title: "Moving 3 items to the Trash…",
                             eyebrow: "Moving to Trash",
                             lede: "You can put items back from the Trash in Finder.",
                             progress: 0.45,
                             progressLeading: "2 of 3 items",
                             path: "/Users/sample/Library/Caches/com.example.musicplayer/Data/Cache.db")
            case .done:
                doneContent
            case .empty:
                statusContent(kind: .ok, title: "No junk found",
                              text: "Your caches and logs are already clear in all 4 locations.")
            case .error:
                statusContent(kind: .error, title: "The scan stopped",
                              text: "SOS Mac couldn't read /Library/Caches. The other 3 locations weren't affected.")
            }
        }
    }

    /// The results state's content: the head and a couple of tiles (sample data).
    private var resultsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ResultsHeaderView(
                    hue: Theme.Hue.junk,
                    title: "1.18 GB of junk found",
                    sub: "1,284 files in 4 locations · 1.18 GB selected (safe files only)")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                    ResultTileView(
                        hue: Theme.Hue.junk, ink: Theme.Hue.Ink.junk, symbol: "trash",
                        label: "User App Caches", value: "9", unit: "files",
                        caption: "selected of 9 · 812 MB", isSelected: true
                    ) {
                        BadgeView(text: "9 selected", style: .safe)
                    }
                    ResultTileView(
                        hue: Theme.Hue.junk, ink: Theme.Hue.Ink.junk, symbol: "key",
                        label: "System Caches", value: "3", unit: "files",
                        caption: "Needs approval · not selected"
                    ) {
                        BadgeView(text: "Needs approval", style: .neutral, systemImage: "key")
                    }
                }
                .padding(.bottom, Theme.Spacing.s4)
                BannerView(kind: .info, title: "3 files were skipped",
                           text: "SOS Mac needs your approval to read System Caches.")
            }
            .padding(EdgeInsets(top: Theme.Spacing.s2, leading: 40, bottom: Theme.Spacing.s2, trailing: 40))
        }
    }

    /// The review state's content: the three-column frame (sample data).
    private var reviewContent: some View {
        ReviewFrameView(
            sections: reviewSections,
            listHead: ReviewFrameView.ListHead(
                title: "User App Caches",
                sub: "9 files · 812 MB",
                isSelectAllEnabled: true,
                isDeselectAllEnabled: true,
                selectAll: {}, deselectAll: {},
                banner: AnyView(BannerView(kind: .info, title: "Needs your approval",
                                           text: "Moving these uses the SOS Mac helper. macOS asks for your password once.")
                    .padding(.bottom, Theme.Spacing.s2))),
            items: reviewItems,
            onToggleItem: { _ in },
            onFocusItem: { _ in },
            onGroup: { _ in },
            detail: AnyView(
                ReviewDetailView(title: "Cache.db") {
                    ReviewDetailView.KeyRow(label: "Rule", value: "User App Caches")
                    ReviewDetailView.PathRow(label: "Location", value: "/Users/sample/Library/Caches/com.example.musicplayer/Data/Cache.db")
                    ReviewDetailView.KeyRow(label: "Size", value: "612.5 MB")
                    ReviewDetailView.KeyRow(label: "Safety", value: "Safe")
                    ReviewDetailView.Explanation(leadIn: "Safe:", text: "a cache the app rebuilds on its own. It goes to the Trash, so you can put it back.")
                }))
    }

    private var reviewSections: [ReviewFrameView.GroupSection] {
        [
            ReviewFrameView.GroupSection(id: "junk", groups: [
                ReviewGroupRow.Model(id: "user-caches", label: "User App Caches", sub: "~/Library/Caches · 9 files",
                                     selectedCount: 2, eligibleCount: 9, isCurrent: true),
                ReviewGroupRow.Model(id: "user-logs", label: "User Logs", sub: "~/Library/Logs · 5 files",
                                     selectedCount: 1, eligibleCount: 5),
                ReviewGroupRow.Model(id: "app-support", label: "App Support Caches", sub: "~/Library/Application Support · 4 files",
                                     selectedCount: 0, eligibleCount: 4),
                ReviewGroupRow.Model(id: "system", label: "System Caches", sub: "/Library/Caches · 3 files",
                                     selectedCount: 0, eligibleCount: 3),
            ])
        ]
    }

    private var reviewItems: [ReviewItemRow.Model] {
        [
            ReviewItemRow.Model(id: "cache", name: "Cache.db",
                                path: "/Users/sample/Library/Caches/com.example.musicplayer/Data/Cache.db",
                                sizeText: "612.5 MB", isSelected: true, isFocused: true),
            ReviewItemRow.Model(id: "journal", name: "journal.sqlite",
                                path: "/Users/sample/Library/Caches/com.example.musicplayer/journal.sqlite",
                                sizeText: "18.4 MB", isSelected: true),
            ReviewItemRow.Model(id: "kept", name: "newest-copy.mov",
                                path: "/Users/sample/Movies/Exports/onboarding-walkthrough.mov",
                                sizeText: "1.24 GB", isKept: true),
            ReviewItemRow.Model(id: "caution", name: "settings.plist",
                                path: "/Users/sample/Library/Caches/com.example.musicplayer/settings.plist",
                                sizeText: "4 KB", badges: [.init(text: "Caution", style: .caution)]),
            ReviewItemRow.Model(id: "helper", name: "system-cache-1.db",
                                path: "/Library/Caches/com.example.helper/system-cache-1.db",
                                sizeText: "96 MB", badges: [.init(text: "Needs approval", style: .neutral, systemImage: "key")]),
        ]
    }

    private var dockAndCTA: some View {
        VStack(spacing: Theme.Spacing.s5) {
            HStack(alignment: .center, spacing: Theme.Spacing.s6) {
                sample("default") { PrimaryCTAView(label: "Scan", action: {}) }
                sample("default · determinate ring") { PrimaryCTAView(label: "Scan", ring: .determinate(0.62), action: {}) }
                sample("default · indeterminate ring") { PrimaryCTAView(label: "Scan", ring: .indeterminate, action: {}) }
                sample("stop") { PrimaryCTAView(label: "Stop", mode: .stop, action: {}) }
                sample("stop · ring") { PrimaryCTAView(label: "Stop", mode: .stop, ring: .determinate(0.3), action: {}) }
                sample("moving") { PrimaryCTAView(label: "Moving", mode: .moving, ring: .indeterminate) }
                sample("disabled") { PrimaryCTAView(label: "Clean", mode: .disabled) }
            }
            DockView(
                cta: PrimaryCTAView(label: "Clean", action: {}),
                leading: AnyView(HStack(spacing: DockView.sideSpacing) {
                    Button {} label: { Label("Review Items…", systemImage: "list") }.sosButton(.default)
                    DockMetaView(bold: "1.18 GB", text: "selected")
                }),
                trailing: AnyView(Button("Scan Again") {}.buttonStyle(.sosPlain)))
                .background(Theme.Color.bgBase)
                .overlay(alignment: .top) { Rectangle().fill(Theme.Derived.hairline).frame(height: 1) }
            DockView(
                cta: PrimaryCTAView(label: "Stop", mode: .stop, ring: .determinate(0.62), action: {}),
                leading: AnyView(DockMetaView(bold: "12", text: "apps checked")))
                .background(Theme.Color.bgBase)
        }
    }

    private var start: some View {
        StartView(module: Self.junkModule,
                  title: "Clear caches and old logs",
                  lede: "SOS Mac finds caches and old logs the apps themselves created, and shows you every file before anything moves.",
                  bullets: [
                      .init(symbol: "trash", title: "Junk & Cache", text: "App caches, old logs and app support caches. 3 locations, no extra permission."),
                      .init(symbol: "doc.on.doc", title: "Nothing is moved without you", text: "Every file is listed for review first; removal always needs the confirmation."),
                      .init(symbol: "key", title: "System Caches", text: "Needs your approval once. Never selected for you."),
                  ],
                  note: "System Caches need your approval. They're never selected for you.")
            .frame(height: 400)
    }

    private var scanning: some View {
        VStack(spacing: Theme.Spacing.s5) {
            ScanningView(module: Self.junkModule,
                         title: "Looking for junk files…",
                         steps: [
                             .init(name: "User App Caches", meta: "Found 9", state: .done),
                             .init(name: "User Logs", meta: "Found 5", state: .done),
                             .init(name: "App Support Caches", meta: "Scanning…", state: .active),
                             .init(name: "System Caches", meta: "Waiting…", state: .pending),
                         ],
                         progress: 0.62,
                         progressLeading: "3 of 4 locations",
                         progressTrailing: "62%",
                         path: "/Users/sample/Library/Application Support/com.example.musicplayer/Caches")
                .frame(height: 320)
            ScanningView(module: Self.junkModule,
                         title: "Scanning for duplicates…",
                         lede: "The pass reads every file in your Home folder and can take a few minutes.",
                         steps: [
                             .init(name: "Listing files", meta: "1,694,000 items", state: .done),
                             .init(name: "Hashing files", meta: "Waiting…", state: .pending),
                         ],
                         countLine: "Scanned 1,694,000 items…")
                .frame(height: 320)
        }
    }

    private var done: some View {
        doneContent
            .frame(height: 420)
    }

    private var doneContent: some View {
        DoneView(
            hue: Theme.Hue.junk,
            title: "1.18 GB moved to the Trash",
            sub: "3 files cleared from your caches and logs.",
            stats: [
                .init(label: "Moved to Trash", value: "1.18 GB", isBytes: true),
                .init(label: "Files", value: "3"),
                .init(label: "Couldn't move", value: "0"),
            ],
            actions: AnyView(HStack(spacing: Theme.Spacing.s2) {
                Button {} label: { Label("Open Trash", systemImage: "trash") }.sosButton(.default)
                Button("Scan Again") {}.sosButton(.prominent)
            }),
            extra: {
                BannerView(kind: .warn, title: "icons.cache couldn't be moved",
                           text: "Raycast had the file open. Quit Raycast, then run Junk & Cache again.")
            })
    }

    private var statusStates: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s4) {
            statusContent(kind: .ok, symbol: "checkmark", title: "No junk found",
                          text: "Your caches and logs are already clear in all 4 locations.",
                          actions: { Button("Scan Again") {}.sosButton(.default) })
                .frame(maxWidth: .infinity)
            statusContent(kind: .neutral, symbol: "app.dashed", title: "No apps found",
                          text: "There are no apps in /Applications that SOS Mac can remove. Apps that came with macOS aren't listed.")
                .frame(maxWidth: .infinity)
            statusContent(kind: .error, symbol: "exclamationmark.triangle", title: "The scan stopped",
                          text: "SOS Mac couldn't read your Home folder. Check that it has Full Disk Access in System Settings › Privacy & Security.",
                          actions: {
                              Button("Try Again") {}.sosButton(.prominent)
                              Button("Open System Settings") {}.sosButton(.default)
                          })
                .frame(maxWidth: .infinity)
        }
        .frame(height: 300)
    }

    private func statusContent(kind: StatusStateView.Kind,
                               symbol: String = "checkmark",
                               title: String,
                               text: String,
                               @ViewBuilder actions: () -> some View = { EmptyView() }) -> some View {
        StatusStateView(kind: kind, symbol: symbol, title: title, text: text, actions: actions)
            .background(Theme.Color.bgBase)
    }

    private var resultsHead: some View {
        VStack(spacing: Theme.Spacing.s4) {
            ResultsHeaderView(hue: Theme.Hue.junk,
                              title: "1.18 GB of junk found",
                              sub: "1,284 files in 4 locations · 1.18 GB selected (safe files only)")
            ResultsHeaderView(hue: Theme.Hue.duplicates,
                              title: "6 sets of duplicate files",
                              sub: "14 extra copies · newest copy kept in each set",
                              eyebrow: "Duplicates") {
                Button("Similar") {}.buttonStyle(.sosPlain)
                Button("Identical") {}.buttonStyle(.sosPlain)
            }
        }
    }

    private var review: some View {
        VStack(spacing: Theme.Spacing.s5) {
            reviewContent
                .frame(height: 320)
            ReviewFrameView(
                layout: .twoColumns,
                sections: reviewSections,
                listHead: ReviewFrameView.ListHead(title: "Raycast", sub: "1 app · 26 related items",
                                                   isSelectAllEnabled: false, isDeselectAllEnabled: true,
                                                   selectAll: {}, deselectAll: {}),
                items: Array(reviewItems.prefix(4)),
                onToggleItem: { _ in },
                onFocusItem: { _ in },
                onGroup: { _ in },
                detail: nil)
                .frame(height: 260)
            Text("Middle column is a SwiftUI List: rows are virtualised (100k-row safe).")
                .font(Theme.Font.subheadline)
                .foregroundStyle(Theme.Color.textSecondary)
        }
    }

    private var reviewBars: some View {
        VStack(spacing: Theme.Spacing.s4) {
            ReviewBarView(meta: AnyView(DockMetaView(bold: "1,694,000", text: "items scanned")),
                          selectedCount: 3, selectedSizeText: "1.18 GB",
                          ctaLabel: "Move to Trash…", isCTAEnabled: true, ctaAction: {})
            ReviewBarView(selectedCount: 0, ctaLabel: "Move to Trash…", isCTAEnabled: false)
            ReviewBarView(selectedCount: 8, selectedSizeText: "2.4 GB", noun: "copy",
                          ctaLabel: "Quarantine…", isCTAEnabled: true, ctaAction: {})
        }
        .background(Theme.Color.bgBase)
    }

    private var confirms: some View {
        let items: [ConfirmItem] = [
            ConfirmItem(id: "cache", name: "Cache.db", size: 612_500_000),
            ConfirmItem(id: "journal", name: "journal.sqlite", size: 18_400_000),
            ConfirmItem(id: "old", name: "old-system.log", size: 96_000_000),
            ConfirmItem(id: "one", name: "one-off.tmp", size: 4_096),
            ConfirmItem(id: "two", name: "two-off.tmp", size: 8_192),
            ConfirmItem(id: "three", name: "three-off.tmp", size: 12_288),
        ]
        return VStack(alignment: .leading, spacing: Theme.Spacing.s5) {
            HStack(alignment: .top, spacing: Theme.Spacing.s4) {
                ConfirmSheet(model: confirmModel(.trash, items: items, isFromResults: true))
                ConfirmSheet(model: confirmModel(.uninstall, items: items, appName: "Raycast", appStoreNote: true))
                ConfirmSheet(model: confirmModel(.quarantine, items: items))
            }
            HStack(alignment: .top, spacing: Theme.Spacing.s4) {
                ConfirmSheet(model: confirmModel(.cloud, items: items))
                ConfirmSheet(model: confirmModel(.cleanupList, items: items.map {
                    ConfirmItem(id: $0.id, name: $0.name, path: "/Users/sample/Downloads/\($0.name)", size: $0.size)
                }))
            }
        }
    }

    private func confirmModel(_ variant: ConfirmSheet.Variant,
                              items: [ConfirmItem],
                              isFromResults: Bool = false,
                              appName: String? = nil,
                              appStoreNote: Bool = false) -> ConfirmSheet.Model {
        let totalBytes = items.reduce(Int64(0)) { running, item in running + item.size }
        let hue: Color = variant == .uninstall ? Theme.Hue.uninstaller : Theme.Hue.junk
        let confirm: @MainActor (ConfirmSelection) -> Void = { _ in }
        let cancel: @MainActor () -> Void = {}
        var reviewItems: (@MainActor () -> Void)?
        if isFromResults { reviewItems = {} }
        return ConfirmSheet.Model(
            variant: variant,
            count: items.count,
            sizeText: ConfirmItemList.sizeText(for: totalBytes),
            appName: appName,
            includesSystemCaches: variant == .trash,
            isFromResults: isFromResults,
            appStoreNote: appStoreNote,
            items: items,
            hue: hue,
            confirm: confirm,
            cancel: cancel,
            reviewItems: reviewItems)
    }

    // MARK: - Building blocks

    private func section<Content: View>(_ key: String, _ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s2) {
            Text(title)
                .font(Theme.Font.eyebrow)
                .foregroundStyle(Theme.Color.textSecondary)
                .padding(.leading, Theme.Spacing.s1)
            content()
                .padding(Self.panelPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.Color.card)
                .clipShape(RoundedRectangle(cornerRadius: Self.panelRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Self.panelRadius, style: .continuous)
                        .strokeBorder(Theme.Derived.hairline, lineWidth: 1)
                )
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("gallery.section.\(key)")
    }

    /// A sample with its caption underneath.
    private func sample<Content: View>(_ caption: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: Theme.Spacing.s2) {
            content()
            Text(caption)
                .font(Theme.Font.eyebrow)
                .foregroundStyle(Theme.Color.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private struct RowTint: ViewModifier {
        let tint: Color?

        func body(content: Content) -> some View {
            if let tint {
                content.background(tint)
            } else {
                content
            }
        }
    }

    private struct KeptRow: ViewModifier {
        let isKept: Bool

        func body(content: Content) -> some View {
            if isKept {
                content.keptRowBackground()
            } else {
                content
            }
        }
    }

    /// A kept row is one element that reads "«name», kept, «size»"; other rows keep their children.
    private struct RowAccessibility: ViewModifier {
        let isKept: Bool
        let name: String
        let size: String

        func body(content: Content) -> some View {
            if isKept {
                content
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(KeepBadge.rowAccessibilityLabel(name: name, size: size))
            } else {
                content.accessibilityElement(children: .contain)
            }
        }
    }
}
#endif

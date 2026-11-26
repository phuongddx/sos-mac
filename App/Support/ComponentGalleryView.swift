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
            Text("Caution label: the kind's colour in dark, textPrimary in light (X4).")
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

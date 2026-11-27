import SwiftUI
import CleanCore

/// Draws the Space Lens treemap (spec §5.5).
///
/// Division of labour at scale (the reason this is a `Canvas`, not per-cell views):
/// the canvas paints every cell — ramp fill, 1 pt `bgBase` separator, the in-cart dot,
/// the hover wash and the selection ring — while a thin SwiftUI overlay draws the text
/// labels, because only cells ≥ 60 × 22 carry labels, and `Text` gives real ellipsis
/// truncation where canvas text would hard-clip. Hit-testing stays a linear
/// rect-containment scan, so thousands of cells cost no gesture recognizers.
///
/// Accessibility (§5.5): one accessibility element per cell — "«name», «size»",
/// button trait, sorted in size order — provided synthetically via
/// `accessibilityChildren`, so VoiceOver sees cells that never become views.
struct TreemapCanvasView: View {
    let items: [SpaceLensViewModel.DisplayItem]
    /// The cleanup cart's paths — cells in it show the 8 pt top-right dot.
    let cartPaths: Set<String>
    let selectedItemID: Int32?
    let onTap: (SpaceLensViewModel.DisplayItem) -> Void
    let onDrill: (SpaceLensViewModel.DisplayItem) -> Void

    @State private var hoveredID: Int32?
    @Environment(\.colorScheme) private var colorScheme

    private typealias Cell = SpaceLensViewModel.DisplayItem

    /// The treemap1…8 ramp, in token order (spec §5.5: cells take the ramp in size
    /// order; the "smaller items" cell and the By Type legend index it too).
    static let ramp: [SwiftUI.Color] = [
        Theme.Color.treemap1, Theme.Color.treemap2, Theme.Color.treemap3, Theme.Color.treemap4,
        Theme.Color.treemap5, Theme.Color.treemap6, Theme.Color.treemap7, Theme.Color.treemap8,
    ]

    /// D9 (review F): the By Type hue per category — the prototype's `data.js` values.
    /// The fixture has no Video or Other, so those two are derived in the same family and
    /// pinned here. One hue per type, so the map and the legend always agree.
    static let categoryHues: [FileCategory: SwiftUI.Color] = [
        .documents: SwiftUI.Color(hex: "#3B82F6"),
        .images: SwiftUI.Color(hex: "#E879F9"),
        .video: SwiftUI.Color(hex: "#FB7185"),
        .audio: SwiftUI.Color(hex: "#2DD4BF"),
        .code: SwiftUI.Color(hex: "#6366F1"),
        .archives: SwiftUI.Color(hex: "#38BDF8"),
        .applications: SwiftUI.Color(hex: "#A78BFA"),
        .other: SwiftUI.Color(hex: "#94A3B8"),
    ]

    /// A category's hue; `treemap8` is a never-shown fallback (every case is pinned).
    static func categoryHue(for category: FileCategory) -> SwiftUI.Color {
        categoryHues[category] ?? ramp[7]
    }

    /// The spec's own cell radius (§5.5 "radius 3") — `Theme.Radius` has no 3 pt step,
    /// so the constant is pinned here with its source, like StartView's glyph ink.
    private static let cellRadius: CGFloat = 3

    /// Label thresholds (§5.5): name + size from 90 × 40, name only from 60 × 22.
    private static let nameAndSizeWidth: CGFloat = 90
    private static let nameAndSizeHeight: CGFloat = 40
    private static let nameOnlyWidth: CGFloat = 60
    private static let nameOnlyHeight: CGFloat = 22

    var body: some View {
        ZStack {
            canvas
            labelsOverlay
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Treemap")
        .accessibilityChildren { accessibilityCells }
    }

    // MARK: - Canvas (cells, dot, hover, selection)

    private var canvas: some View {
        Canvas { context, _ in
            var context = context
            for item in items where item.rect.width > 0.5 && item.rect.height > 0.5 {
                drawCell(item, into: &context)
            }
            if let selected = items.first(where: { $0.id == selectedItemID }) {
                drawSelectionRing(selected, into: &context)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { location in
            if let hit = hitTest(location) { onDrill(hit) }
        }
        .onTapGesture { location in
            if let hit = hitTest(location) { onTap(hit) }
        }
        .onContinuousHover { phase in
            switch phase {
            case .active(let location): hoveredID = hitTest(location)?.id
            case .ended: hoveredID = nil
            }
        }
    }

    private func drawCell(_ item: Cell, into context: inout GraphicsContext) {
        let shape = Path(roundedRect: item.rect, cornerRadius: Self.cellRadius)
        context.fill(shape, with: .color(Self.baseFill(for: item)))
        if item.isCategory {
            // D9: the By Type fill is the type's hue, then the treemapMix overlay (dark:
            // card at 42 %, light: 24 %) — the exact equivalent of the prototype's
            // color-mix(in srgb, hue 42 %, var(--tm-mix)), via the existing token.
            context.fill(shape, with: .color(Theme.Derived.treemapMix))
        }
        // The 1 pt bgBase line between neighbours (§5.5) is the cell's own border.
        context.stroke(shape, with: .color(Theme.Color.bgBase), lineWidth: 1)

        if let path = item.path, cartPaths.contains(path) {
            // The in-cart marker (§5.5): an 8 pt dot at 6/6 from the top-right corner.
            let dot = CGRect(x: item.rect.maxX - 14, y: item.rect.minY + 6, width: 8, height: 8)
            context.fill(Path(ellipseIn: dot), with: .color(Theme.Color.neonMagenta))
        }

        // Prototype `.cell:hover`: brightness 1.12 (dark) / 0.97 (light) — drawn as an
        // equivalent white/black wash over the cell's own fill.
        if hoveredID == item.id {
            let wash: SwiftUI.Color = colorScheme == .dark ? .white.opacity(0.10) : .black.opacity(0.04)
            context.fill(shape, with: .color(wash))
        }
    }

    /// Selection is visible (§5.5): a 2 pt ring inset into the cell, neon magenta
    /// (violet in Palette C), with glow in dark only (T6).
    private func drawSelectionRing(_ item: Cell, into context: inout GraphicsContext) {
        guard item.rect.width > 4, item.rect.height > 4 else { return }
        let ring = Path(roundedRect: item.rect.insetBy(dx: 1, dy: 1), cornerRadius: Self.cellRadius)
        if colorScheme == .dark {
            context.addFilter(.shadow(
                color: Theme.Color.neonMagenta.opacity(Theme.Glow.idleAlpha(isDark: true)),
                radius: 6, x: 0, y: 0))
        }
        context.stroke(ring, with: .color(Theme.Color.neonMagenta), lineWidth: 2)
    }

    /// By Folder cells take the ramp by their size-order position; the "N smaller
    /// items" cell always sits on `treemap8` (§5.5); a By Type cell takes its
    /// category's fixed hue (D9 — the mix overlay is drawn on top in `drawCell`).
    private static func baseFill(for item: Cell) -> SwiftUI.Color {
        guard !item.isSmallerBucket else { return ramp[7] }
        if let category = item.category { return categoryHue(for: category) }
        return ramp[abs(item.rampIndex) % ramp.count]
    }

    private func hitTest(_ location: CGPoint) -> Cell? {
        items.first { $0.rect.contains(location) && $0.rect.width > 0.5 && $0.rect.height > 0.5 }
    }

    // MARK: - Labels (SwiftUI text for real truncation)

    @ViewBuilder
    private var labelsOverlay: some View {
        ForEach(items.filter { showsLabel($0) }) { item in
            VStack(alignment: .leading, spacing: 1) {
                Text(item.label)
                    .font(Theme.Font.callout.weight(.semibold))
                    .foregroundStyle(Theme.Color.treemapText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if showsSizeLabel(item) {
                    Text(ByteFormatter.string(fromByteCount: item.size))
                        .font(Theme.Font.subheadline)
                        .monospacedDigit()
                        .opacity(0.85)
                        .foregroundStyle(Theme.Color.treemapText)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(width: item.rect.width, height: item.rect.height, alignment: .topLeading)
            .clipped()
            .position(x: item.rect.midX, y: item.rect.midY)
            .allowsHitTesting(false)
        }
    }

    private func showsLabel(_ item: Cell) -> Bool {
        item.rect.width >= Self.nameOnlyWidth && item.rect.height >= Self.nameOnlyHeight
    }

    private func showsSizeLabel(_ item: Cell) -> Bool {
        item.rect.width >= Self.nameAndSizeWidth && item.rect.height >= Self.nameAndSizeHeight
    }

    // MARK: - Accessibility (§5.5: one element per cell, button trait, size order)

    @ViewBuilder
    private var accessibilityCells: some View {
        // `items` is already size-descending (levelEntries and the By Type legend sort).
        ForEach(Array(items.enumerated()), id: \.element.id) { offset, item in
            Button {
                onTap(item)
            } label: {
                Text("\(item.label), \(ByteFormatter.string(fromByteCount: item.size))")
            }
            .accessibilitySortPriority(Double(items.count - offset))
        }
    }
}

import SwiftUI

/// Renders via `Canvas`, not per-node `Shape`/`Path` views — a `Shape` per
/// rectangle plus a tap gesture recognizer per shape doesn't scale to the
/// thousands of nodes a real directory tree produces. Hit-testing is a
/// linear rect-containment scan instead of per-shape gesture recognizers,
/// for the same reason.
struct TreemapCanvasView: View {
    let items: [SpaceLensViewModel.DisplayItem]
    let onTap: (SpaceLensViewModel.DisplayItem) -> Void

    var body: some View {
        Canvas { context, _ in
            for item in items {
                let rect = item.rect
                guard rect.width > 0.5, rect.height > 0.5 else { continue }

                let color = Self.color(forLabel: item.label)
                context.fill(Path(rect), with: .color(color))
                context.stroke(Path(rect), with: .color(.black.opacity(0.2)), lineWidth: 1)

                if rect.width > 44, rect.height > 16 {
                    context.draw(
                        Text(item.label)
                            .font(.caption2)
                            .foregroundStyle(.white),
                        at: CGPoint(x: rect.midX, y: rect.midY)
                    )
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { location in
            guard let hit = items.first(where: { $0.rect.contains(location) }) else { return }
            onTap(hit)
        }
    }

    /// Deterministic per-label color so re-rendering the same node always
    /// gets the same swatch, without ArenaTree needing to know anything
    /// about color (that's a UI concern, not a tree-storage concern).
    private static func color(forLabel label: String) -> Color {
        var hasher = Hasher()
        hasher.combine(label)
        let hue = Double(abs(hasher.finalize()) % 360) / 360.0
        return Color(hue: hue, saturation: 0.55, brightness: 0.75)
    }
}

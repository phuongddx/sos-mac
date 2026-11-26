import SwiftUI

/// One module launcher card (spec §5.1, prototype `.mod`): a 34 pt hue tile, the module name,
/// a one-line description and a chevron. No stat line, no badge — the "Not scanned this
/// session" placeholders are gone (D6). `extraLine` is a real one-off figure or nothing.
struct DashboardModuleCard: View {
    let destination: SidebarDestination
    let description: String
    var extraLine: String?
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
        Button(action: action) {
            HStack(spacing: Theme.Spacing.s3) {
                ModuleTileView(hue: destination.tileHue, ink: destination.tileInk,
                               symbol: destination.systemImage, size: .card)
                VStack(alignment: .leading, spacing: 2) {
                    Text(destination.rawValue)
                        .font(Theme.Font.headline)
                        .foregroundStyle(Theme.Color.textPrimary)
                        .lineLimit(1)
                    Text(description)
                        .font(Theme.Font.callout)
                        .foregroundStyle(Theme.Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let extraLine {
                        Text(extraLine)
                            .font(Theme.Font.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(Theme.Color.textSecondary)
                            .padding(.top, 2)
                    }
                }
                Spacer(minLength: Theme.Spacing.s1)
                Image(systemName: "chevron.right")
                    .font(Theme.Font.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Color.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(Theme.Spacing.s3 + 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(Theme.Color.card, in: shape)
            .overlay(shape.strokeBorder(isHovering ? destination.tileHue.opacity(0.45) : Theme.Derived.hairline,
                                        lineWidth: 1))
            .contentShape(shape)
            .offset(y: isHovering && !reduceMotion ? -1 : 0)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(Theme.Motion.quick, value: isHovering)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(destination.rawValue)
        .accessibilityValue([description, extraLine].compactMap { $0 }.joined(separator: ". "))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("dashboard-card-\(destination.rawValue)")
    }
}

/// A labelled row of four launcher cards (spec §5.1): four across when the content is wide
/// enough for each card to keep its name on one line, two by two below that (the window's
/// minimum, 960 pt, is two across).
struct DashboardModuleSection: View {
    struct Entry: Identifiable {
        let destination: SidebarDestination
        let description: String
        var extraLine: String?
        var id: SidebarDestination { destination }
    }

    /// Narrowest a card may get in the four-across layout.
    static let minimumCardWidth: CGFloat = 200
    static let spacing: CGFloat = Theme.Spacing.s3

    let title: String
    let entries: [Entry]
    let open: (SidebarDestination) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DashboardSectionLabel(text: title)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Self.spacing) {
                    ForEach(entries) { card($0).frame(minWidth: Self.minimumCardWidth) }
                }
                VStack(spacing: Self.spacing) {
                    ForEach(Array(stride(from: 0, to: entries.count, by: 2)), id: \.self) { start in
                        HStack(spacing: Self.spacing) {
                            ForEach(entries[start..<min(start + 2, entries.count)]) { card($0) }
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private func card(_ entry: Entry) -> some View {
        DashboardModuleCard(destination: entry.destination,
                            description: entry.description,
                            extraLine: entry.extraLine) { open(entry.destination) }
    }
}

/// Eyebrow label with a trailing hairline (prototype `.section-label`).
struct DashboardSectionLabel: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Text(text.uppercased())
                .font(Theme.Font.eyebrow)
                .tracking(0.6)
                .foregroundStyle(Theme.Color.textSecondary)
            Rectangle().fill(Theme.Derived.hairline).frame(height: 1)
        }
        .accessibilityAddTraits(.isHeader)
        .accessibilityElement(children: .combine)
    }
}

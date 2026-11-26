import SwiftUI

/// One item row in the review frame's items column (spec §4.5): a 16 checkbox, name (`body`,
/// truncated) with path (`mono`, `textSecondary`, truncated), badges, and a right-aligned,
/// tabular size (min 64); 8/16 padding, bottom `hairline`; hover = `rowHover`,
/// focused = `rowSelected`.
///
/// A kept row gets the 5 % `success` wash, the locked checkbox and the Keep badge (§4.6);
/// its checkbox never toggles and the row reads "«name», kept, «size»" as one element.
struct ReviewItemRow: View {
    struct Badge: Identifiable, Hashable, Sendable {
        let text: String
        let style: BadgeStyle
        var systemImage: String?
        var id: String { text }

        init(text: String, style: BadgeStyle, systemImage: String? = nil) {
            self.text = text
            self.style = style
            self.systemImage = systemImage
        }
    }

    struct Model: Identifiable, Hashable, Sendable {
        let id: String
        let name: String
        let path: String?
        let sizeText: String
        var badges: [Badge] = []
        var isKept: Bool = false
        var isSelected: Bool = false
        var isFocused: Bool = false

        init(id: String,
             name: String,
             path: String? = nil,
             sizeText: String,
             badges: [Badge] = [],
             isKept: Bool = false,
             isSelected: Bool = false,
             isFocused: Bool = false) {
            self.id = id
            self.name = name
            self.path = path
            self.sizeText = sizeText
            self.badges = badges
            self.isKept = isKept
            self.isSelected = isSelected
            self.isFocused = isFocused
        }
    }

    static let horizontalPadding: CGFloat = 16
    static let verticalPadding: CGFloat = 8
    static let spacing: CGFloat = 12
    static let sizeMinWidth: CGFloat = 64

    let model: Model
    let toggle: () -> Void
    let focus: () -> Void

    @State private var isHovering = false

    init(model: Model, toggle: @escaping () -> Void, focus: @escaping () -> Void) {
        self.model = model
        self.toggle = toggle
        self.focus = focus
    }

    /// The prototype's precedence: the kept wash wins, then the focused row, then hover.
    private var background: Color {
        if model.isKept { return Theme.Color.success.opacity(KeepBadge.rowBackgroundAlpha) }
        if model.isFocused { return Theme.Derived.rowSelected }
        return isHovering ? Theme.Derived.rowHover : .clear
    }

    var body: some View {
        Button(action: focus) {
            HStack(alignment: .center, spacing: Self.spacing) {
                SOSCheckbox(
                    isSelected: model.isSelected,
                    isKept: model.isKept,
                    label: model.isKept ? "Kept: \(model.name)" : "Select \(model.name)",
                    action: toggle
                )
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Theme.Spacing.s2) {
                        Text(model.name)
                            .font(Theme.Font.body)
                            .foregroundStyle(Theme.Color.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if model.isKept {
                            KeepBadge()
                        }
                    }
                    if let path = model.path {
                        Text(path)
                            .font(Theme.Font.mono)
                            .foregroundStyle(Theme.Color.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                HStack(spacing: Theme.Spacing.s2 - 2) {
                    ForEach(model.badges.filter { !$0.text.isEmpty }) { badge in
                        BadgeView(text: badge.text, style: badge.style, systemImage: badge.systemImage)
                    }
                }
                .fixedSize()
                Text(model.sizeText)
                    .font(Theme.Font.callout)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .monospacedDigit()
                    .frame(minWidth: Self.sizeMinWidth, alignment: .trailing)
            }
            .padding(.horizontal, Self.horizontalPadding)
            .padding(.vertical, Self.verticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Theme.Derived.hairline).frame(height: 1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .modifier(ReviewRowAccessibility(model: model))
        .accessibilityIdentifier("review-item-\(model.id)")
    }
}

/// A kept row is one element that reads "«name», kept, «size»" (spec §4.6); every other row
/// keeps its children accessible.
private struct ReviewRowAccessibility: ViewModifier {
    let model: ReviewItemRow.Model

    func body(content: Content) -> some View {
        if model.isKept {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(KeepBadge.rowAccessibilityLabel(name: model.name, size: model.sizeText))
        } else {
            content.accessibilityElement(children: .contain)
        }
    }
}

import SwiftUI

/// One group row in the review frame's groups column (spec §4.5): label (`headline`,
/// truncated), sub (`subheadline`, `textSecondary`), "«k» of «n»" selected with tabular
/// digits; 9/10 padding, radius 8; current = `rowSelected`, hover = `rowHover`.
///
/// `selectedCount` and `eligibleCount` are real counts that exclude kept items — the screen
/// computes them, the row only draws them.
struct ReviewGroupRow: View {
    struct Model: Identifiable, Hashable, Sendable {
        let id: String
        let label: String
        let sub: String?
        let selectedCount: Int
        let eligibleCount: Int
        var isCurrent: Bool = false

        init(id: String, label: String, sub: String? = nil, selectedCount: Int, eligibleCount: Int, isCurrent: Bool = false) {
            self.id = id
            self.label = label
            self.sub = sub
            self.selectedCount = selectedCount
            self.eligibleCount = eligibleCount
            self.isCurrent = isCurrent
        }
    }

    static let cornerRadius: CGFloat = 8
    static let horizontalPadding: CGFloat = 10
    static let verticalPadding: CGFloat = 9
    static let spacing: CGFloat = 10

    let model: Model
    let action: () -> Void

    @State private var isHovering = false

    init(model: Model, action: @escaping () -> Void) {
        self.model = model
        self.action = action
    }

    private var background: Color {
        if model.isCurrent { return Theme.Derived.rowSelected }
        return isHovering ? Theme.Derived.rowHover : .clear
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Self.spacing) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.label)
                        .font(Theme.Font.headline.weight(.medium))
                        .foregroundStyle(Theme.Color.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let sub = model.sub {
                        Text(sub)
                            .font(Theme.Font.subheadline)
                            .foregroundStyle(Theme.Color.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                Text("\(model.selectedCount) of \(model.eligibleCount)")
                    .font(Theme.Font.callout)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, Self.horizontalPadding)
            .padding(.vertical, Self.verticalPadding)
            .background(background, in: RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel("\(model.label), \(model.selectedCount) of \(model.eligibleCount) selected")
        .accessibilityAddTraits(model.isCurrent ? .isSelected : [])
        .accessibilityIdentifier("review-group-\(model.id)")
    }
}

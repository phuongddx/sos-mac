import SwiftUI

/// The confirmation's item list (spec §4.8): the first 5 items (name + size) and, if more,
/// "and **N** more items" with their combined size. Both numbers are real — every item
/// carries its byte count, and the combined size is the sum of the overflow.
///
/// The cleanup-list variant (Space Lens) draws **every** row with a checkbox and a path,
/// plus a Total row that follows the checked items (D7, review F): a row the user must be
/// able to uncheck is never hidden behind "and N more".
struct ConfirmItemList: View {
    static let previewLimit = 5
    static let rowHorizontalPadding: CGFloat = 10
    static let rowVerticalPadding: CGFloat = 6
    static let listMaxHeight: CGFloat = 132

    let items: [ConfirmItem]
    /// The cleanup-list mode: checkboxes, paths, a Total row.
    var isSelectable = false
    /// Checked item ids in selectable mode; owned by `ConfirmSheetState`.
    var checkedItemIDs: Set<String> = []
    var onToggle: (String) -> Void = { _ in }

    var body: some View {
        let drawn = Self.drawnRows(for: items, isSelectable: isSelectable)
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        // The prototype's `.alist` is `max-height: 132px; overflow: auto`: the rows scroll
        // inside a clipped box, so the Total row (cleanup list) and the acknowledgement stay
        // visible however many rows there are.
        ScrollView {
            VStack(spacing: 0) {
                ForEach(drawn.rows) { item in
                    row(item)
                }
                if !isSelectable, drawn.overflowCount > 0 {
                    overflowRow(count: drawn.overflowCount,
                                bytes: items.dropFirst(Self.previewLimit).reduce(0) { $0 + $1.size })
                }
                if isSelectable {
                    totalRow
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: Self.listMaxHeight)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Theme.Derived.hairline, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("confirm-item-list")
    }

    /// D7 (review F): the rows the list draws. The cleanup list draws every row — each one
    /// checkable inside the 132 pt scroll box, so title, list and Total row follow the same
    /// rows; the read-only variants keep the spec §4.8 first-5 preview with "and N more".
    /// Pure, so the rule is unit-testable.
    static func drawnRows(for items: [ConfirmItem],
                          isSelectable: Bool) -> (rows: [ConfirmItem], overflowCount: Int) {
        let rows = isSelectable ? items : Array(items.prefix(previewLimit))
        return (rows, items.count - rows.count)
    }

    /// The shared byte formatter, so the list and the title always show the same numbers
    /// (CF-3). Screens format the title's size with `ConfirmSheet.sizeText(for:)`.
    static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.isAdaptive = true
        return formatter
    }()

    static func sizeText(for bytes: Int64) -> String {
        byteFormatter.string(fromByteCount: bytes)
    }

    private func row(_ item: ConfirmItem) -> some View {
        HStack(spacing: Theme.Spacing.s3 - 2) {
            if isSelectable {
                SOSCheckbox(isSelected: checkedItemIDs.contains(item.id),
                            label: "Keep in list: \(item.name)") {
                    onToggle(item.id)
                }
            }
            Text(item.name)
                .font(Theme.Font.callout)
                .foregroundStyle(Theme.Color.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            Text(ConfirmItemList.sizeText(for: item.size))
                .font(Theme.Font.callout)
                .foregroundStyle(Theme.Color.textSecondary)
                .monospacedDigit()
                .fixedSize()
        }
        .padding(.horizontal, Self.rowHorizontalPadding)
        .padding(.vertical, Self.rowVerticalPadding)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.Derived.hairline).frame(height: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private func overflowRow(count: Int, bytes: Int64) -> some View {
        HStack {
            Text("and \(count) more item\(count == 1 ? "" : "s")")
                .foregroundStyle(Theme.Color.textSecondary)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            Text(ConfirmItemList.sizeText(for: bytes))
                .font(Theme.Font.callout)
                .foregroundStyle(Theme.Color.textSecondary)
                .monospacedDigit()
                .fixedSize()
        }
        .font(Theme.Font.callout)
        .padding(.horizontal, Self.rowHorizontalPadding)
        .padding(.vertical, Self.rowVerticalPadding)
        .accessibilityElement(children: .combine)
    }

    private var totalRow: some View {
        let checked = items.filter { checkedItemIDs.contains($0.id) }
        let bytes = checked.reduce(Int64(0)) { $0 + $1.size }
        return HStack {
            Text("Total")
                .foregroundStyle(Theme.Color.textSecondary)
            Spacer(minLength: 0)
            Text(ConfirmItemList.sizeText(for: bytes))
                .fontWeight(.semibold)
                .foregroundStyle(Theme.Color.textPrimary)
                .monospacedDigit()
        }
        .font(Theme.Font.callout)
        .padding(.horizontal, Self.rowHorizontalPadding)
        .padding(.vertical, Self.rowVerticalPadding)
        .accessibilityElement(children: .combine)
    }
}

/// One item a confirmation shows (spec §4.8): the name, the byte count (real, engine data)
/// and — in the cleanup-list variant — the path.
struct ConfirmItem: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let path: String?
    let size: Int64

    init(id: String, name: String, path: String? = nil, size: Int64) {
        self.id = id
        self.name = name
        self.path = path
        self.size = size
    }

    var sizeText: String { ConfirmItemList.sizeText(for: size) }
}

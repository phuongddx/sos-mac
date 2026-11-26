import SwiftUI

/// The review frame (spec §4.5): three columns — groups 250 · items flexible · detail 280 —
/// or the two-column variant Uninstaller uses (groups 250 · items). The groups and items
/// columns are virtualised `List`s, so 100 k+ result rows stay flat; no per-row blur or
/// shadow is drawn.
///
/// The middle column carries the list head (title, sub, Select All / Deselect All — each
/// disabled when it would change nothing — and an optional banner under it). The detail
/// column is the screen's builder for the focused item.
///
/// Select All never selects a kept item: rows marked `isKept` render locked and never call
/// `toggle` (§4.6); the screen's select-all is expected to skip them as well.
struct ReviewFrameView: View {
    enum Layout: Equatable, Sendable {
        /// groups 250 · items · detail 280.
        case threeColumns
        /// Uninstaller: groups 250 · items.
        case twoColumns
    }

    /// One section of the groups column (Smart Care splits it into "Junk & Cache" and
    /// "Duplicate files"; other modules pass a single untitled section).
    struct GroupSection: Identifiable {
        let id: String
        let title: String?
        let groups: [ReviewGroupRow.Model]

        init(id: String, title: String? = nil, groups: [ReviewGroupRow.Model]) {
            self.id = id
            self.title = title
            self.groups = groups
        }
    }

    /// The middle column's head (spec §4.5 "List head").
    struct ListHead {
        let title: String
        var sub: String?
        /// Disabled when Select All would change nothing (already all selected).
        var isSelectAllEnabled: Bool
        /// Disabled when Deselect All would change nothing (nothing selected).
        var isDeselectAllEnabled: Bool
        var selectAll: (@MainActor () -> Void)?
        var deselectAll: (@MainActor () -> Void)?
        /// An optional banner under the head (e.g. "Needs your approval").
        var banner: AnyView?

        init(title: String,
             sub: String? = nil,
             isSelectAllEnabled: Bool = true,
             isDeselectAllEnabled: Bool = true,
             selectAll: (@MainActor () -> Void)? = nil,
             deselectAll: (@MainActor () -> Void)? = nil,
             banner: AnyView? = nil) {
            self.title = title
            self.sub = sub
            self.isSelectAllEnabled = isSelectAllEnabled
            self.isDeselectAllEnabled = isDeselectAllEnabled
            self.selectAll = selectAll
            self.deselectAll = deselectAll
            self.banner = banner
        }
    }

    static let groupsColumnWidth: CGFloat = 250
    static let detailColumnWidth: CGFloat = 280
    static let groupsColumnPadding = EdgeInsets(top: 12, leading: 10, bottom: 12, trailing: 10)
    static let listHeadHorizontalPadding: CGFloat = 16

    let layout: Layout
    let sections: [GroupSection]
    let listHead: ListHead
    /// The current group's items. Virtualised; designed for 100 k+ rows.
    let items: [ReviewItemRow.Model]
    var onToggleItem: @MainActor (ReviewItemRow.Model) -> Void
    var onFocusItem: @MainActor (ReviewItemRow.Model) -> Void
    var onGroup: @MainActor (ReviewGroupRow.Model) -> Void
    /// The focused item's detail; screens use `ReviewDetailView`'s builder API.
    var detail: AnyView?

    init(layout: Layout = .threeColumns,
         sections: [GroupSection],
         listHead: ListHead,
         items: [ReviewItemRow.Model],
         onToggleItem: @escaping @MainActor (ReviewItemRow.Model) -> Void,
         onFocusItem: @escaping @MainActor (ReviewItemRow.Model) -> Void,
         onGroup: @escaping @MainActor (ReviewGroupRow.Model) -> Void,
         detail: AnyView? = nil) {
        self.layout = layout
        self.sections = sections
        self.listHead = listHead
        self.items = items
        self.onToggleItem = onToggleItem
        self.onFocusItem = onFocusItem
        self.onGroup = onGroup
        self.detail = detail
    }

    var body: some View {
        HStack(spacing: 0) {
            groupsColumn
            divider
            itemsColumn
            if layout == .threeColumns {
                divider
                detailColumn
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.Derived.hairline).frame(height: 1)
        }
        .background(Theme.Color.card)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("review-frame")
    }

    private var divider: some View {
        Rectangle().fill(Theme.Derived.hairline).frame(width: 1)
    }

    /// "bgBase 60 % over card" (spec §4.5) behind the groups and detail columns.
    private var columnBackground: Color {
        ColorMix.mix(Theme.Color.bgBase, Theme.Color.card, fraction: 0.60, in: environment)
    }

    @Environment(\.self) private var environment

    // MARK: - Groups column

    private var groupsColumn: some View {
        List {
            ForEach(sections) { section in
                if let title = section.title {
                    Text(title.uppercased())
                        .font(Theme.Font.eyebrow)
                        .tracking(0.48)
                        .foregroundStyle(Theme.Color.textSecondary)
                        .padding(EdgeInsets(top: 10, leading: 10, bottom: 6, trailing: 10))
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .accessibilityAddTraits(.isHeader)
                }
                ForEach(section.groups) { group in
                    ReviewGroupRow(model: group) {
                        onGroup(group)
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 10))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(columnBackground)
        .frame(width: Self.groupsColumnWidth)
        .accessibilityIdentifier("review-groups")
    }

    // MARK: - Items column

    private var itemsColumn: some View {
        VStack(spacing: 0) {
            listHeadView
            if let banner = listHead.banner {
                banner
                    .padding(EdgeInsets(top: 10, leading: Self.listHeadHorizontalPadding, bottom: 0, trailing: Self.listHeadHorizontalPadding))
            }
            itemList
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("review-items")
    }

    private var listHeadView: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.s3 - 2) {
            VStack(alignment: .leading, spacing: 0) {
                Text(listHead.title)
                    .font(Theme.Font.headline)
                    .foregroundStyle(Theme.Color.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let sub = listHead.sub {
                    Text(sub)
                        .font(Theme.Font.subheadline)
                        .foregroundStyle(Theme.Color.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            HStack(spacing: Theme.Spacing.s2 - 2) {
                Button("Select All") { listHead.selectAll?() }
                    .buttonStyle(.sosPlain)
                    .disabled(!listHead.isSelectAllEnabled || listHead.selectAll == nil)
                Button("Deselect All") { listHead.deselectAll?() }
                    .buttonStyle(.sosPlain)
                    .disabled(!listHead.isDeselectAllEnabled || listHead.deselectAll == nil)
            }
        }
        .padding(.horizontal, Self.listHeadHorizontalPadding)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.Derived.hairline).frame(height: 1)
        }
        .accessibilityElement(children: .contain)
    }

    /// The virtualised item list. `List` only materialises visible rows, which is what keeps
    /// 100 k+ result sets scrollable.
    private var itemList: some View {
        List(items) { item in
            ReviewItemRow(model: item,
                          toggle: { onToggleItem(item) },
                          focus: { onFocusItem(item) })
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .frame(maxHeight: .infinity)
    }

    // MARK: - Detail column

    private var detailColumn: some View {
        Group {
            if let detail {
                detail
            } else {
                Color.clear
            }
        }
        .frame(maxHeight: .infinity)
        .frame(width: Self.detailColumnWidth)
        .background(columnBackground)
        .overlay(alignment: .leading) {
            Rectangle().fill(Theme.Derived.hairline).frame(width: 1)
        }
        .accessibilityIdentifier("review-detail-column")
    }
}

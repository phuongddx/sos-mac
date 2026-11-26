import SwiftUI

/// The detail column of the review frame (spec §4.5): padding 18, a `title3` title, and rows
/// built with a SwiftUI builder API —
///
/// ```swift
/// ReviewDetailView(title: item.name) {
///     ReviewDetailView.KeyRow(label: "Rule", value: item.rule)
///     ReviewDetailView.PathRow(label: "Location", value: item.path)
///     ReviewDetailView.Explanation(leadIn: "Safe:", text: "…")
/// }
/// ```
struct ReviewDetailView: View {
    static let padding: CGFloat = 18

    let title: String
    /// The key rows and explanation, built with the nested row views.
    var rows: AnyView

    init(title: String, @ViewBuilder rows: () -> some View) {
        self.title = title
        self.rows = AnyView(rows())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(Theme.Font.title3)
                    .foregroundStyle(Theme.Color.textPrimary)
                rows
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Self.padding)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("review-detail")
    }
}

extension ReviewDetailView {
    /// A key row (spec §4.5): a `subheadline` semibold uppercase `textSecondary` label over
    /// a `body` value.
    struct KeyRow: View {
        static let labelTopSpacing: CGFloat = 14
        static let labelTracking: CGFloat = 0.48

        let label: String
        let value: String

        var body: some View {
            VStack(alignment: .leading, spacing: Theme.Spacing.s1) {
                Text(label.uppercased())
                    .font(Theme.Font.subheadline.weight(.semibold))
                    .tracking(Self.labelTracking)
                    .foregroundStyle(Theme.Color.textSecondary)
                Text(value)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, Self.labelTopSpacing)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }

    /// A key row whose value is a path: monospaced 12 `textSecondary`, word-break all.
    struct PathRow: View {
        let label: String
        let value: String

        var body: some View {
            VStack(alignment: .leading, spacing: Theme.Spacing.s1) {
                Text(label.uppercased())
                    .font(Theme.Font.subheadline.weight(.semibold))
                    .tracking(KeyRow.labelTracking)
                    .foregroundStyle(Theme.Color.textSecondary)
                Text(value)
                    .font(Theme.Font.mono)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, KeyRow.labelTopSpacing)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }

    /// The explanation box (spec §4.5): 12 padding, radius 10, `card`, `hairline`, whose
    /// bold lead-in is `textPrimary`.
    struct Explanation: View {
        static let topSpacing: CGFloat = 16

        let leadIn: String
        let text: String

        var body: some View {
            (
                Text(leadIn).fontWeight(.semibold).foregroundStyle(Theme.Color.textPrimary)
                    + Text(" ") + Text(text)
            )
            .font(Theme.Font.callout)
            .foregroundStyle(Theme.Color.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.s3)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).fill(Theme.Color.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .strokeBorder(Theme.Derived.hairline, lineWidth: 1))
            .padding(.top, Self.topSpacing)
            .accessibilityElement(children: .combine)
        }
    }

    /// A free row for anything a module needs between key rows.
    struct FreeRow<Content: View>: View {
        let content: Content

        init(@ViewBuilder _ content: () -> Content) {
            self.content = content()
        }

        var body: some View {
            content
                .padding(.top, KeyRow.labelTopSpacing)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

import SwiftUI

/// A banner (spec §4.7): an icon, a bold title, an optional line of body text and an optional
/// trailing button, on a 10 % tint of the kind's colour over `card`, with a 30 % border.
///
/// An error banner sits next to what failed and offers **Try Again** or the relevant escape when
/// one exists.
///
/// The trailing button is type-erased: banners are few, and a non-generic view can keep its
/// metrics as static constants.
struct BannerView: View {
    enum Kind: CaseIterable, Sendable {
        /// "Needs your approval", "14 files were skipped", "Local scan".
        case info
        /// "Similar isn't identical", a file that could not be moved.
        case warn
        /// "Couldn't finish the duplicate scan", "Couldn't inspect «App»".
        case err
        /// "Free up RAM finished".
        case ok

        /// The kind's colour: its tint, its border, its icon and its bold title.
        var color: Color {
            switch self {
            case .info: Theme.Color.primaryBright
            case .warn: Theme.Color.warning
            case .err: Theme.Color.danger
            case .ok: Theme.Color.success
            }
        }

        /// Symbol used when the caller gives none.
        var defaultSymbol: String {
            switch self {
            case .info: "info.circle"
            case .warn, .err: "exclamationmark.triangle"
            case .ok: "checkmark"
            }
        }
    }

    /// Geometry and tint strengths (spec §4.7).
    enum Metrics {
        static let backgroundAlpha: Double = 0.10
        static let borderAlpha: Double = 0.30
        static let verticalPadding: CGFloat = 10
        static let horizontalPadding: CGFloat = 12
        static let iconSize: CGFloat = 16
        static let iconSpacing: CGFloat = 10
        static let titleSpacing: CGFloat = 2
    }

    let kind: Kind
    let title: String
    var text: String?
    var systemImage: String?
    /// The optional trailing button.
    var action: AnyView?

    init(kind: Kind, title: String, text: String? = nil, systemImage: String? = nil) {
        self.kind = kind
        self.title = title
        self.text = text
        self.systemImage = systemImage
        self.action = nil
    }

    init(kind: Kind, title: String, text: String? = nil, systemImage: String? = nil,
         @ViewBuilder action: () -> some View) {
        self.kind = kind
        self.title = title
        self.text = text
        self.systemImage = systemImage
        self.action = AnyView(action())
    }

    var body: some View {
        let color = kind.color
        HStack(alignment: .top, spacing: Metrics.iconSpacing) {
            Image(systemName: systemImage ?? kind.defaultSymbol)
                .font(.system(size: Metrics.iconSize))
                .foregroundStyle(color)
                .padding(.top, 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Metrics.titleSpacing) {
                Text(title)
                    .font(Theme.Font.callout.weight(.semibold))
                    .foregroundStyle(color)
                if let text {
                    Text(text)
                        .font(Theme.Font.callout)
                        .foregroundStyle(Theme.Color.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            if let action {
                action.fixedSize()
            }
        }
        .padding(.vertical, Metrics.verticalPadding)
        .padding(.horizontal, Metrics.horizontalPadding)
        // The tint is defined over `card`, so the banner is opaque wherever it sits.
        .background(color.opacity(Metrics.backgroundAlpha))
        .background(Theme.Color.card)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .strokeBorder(color.opacity(Metrics.borderAlpha), lineWidth: 1)
        )
    }
}

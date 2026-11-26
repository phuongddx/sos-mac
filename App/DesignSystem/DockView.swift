import SwiftUI

/// The dock (spec §4.2): 128 pt tall, 28 pt side padding, three slots — left meta · CTA ·
/// right buttons. The frame (`ModuleScreen`) fills the slots per state; a screen never
/// restyles them.
///
/// The side slots hold whatever their state needs: a meta line (`DockMetaView`), default
/// buttons ("Review Items…", "Open Trash") or plain links ("Scan Again"). Meta is 12 pt
/// `textSecondary`; a bold figure is `textPrimary`.
struct DockView: View {
    static let height: CGFloat = 128
    static let sidePadding: CGFloat = 28
    static let sideSpacing: CGFloat = 10

    let cta: PrimaryCTAView
    var leading: AnyView?
    var trailing: AnyView?

    init(cta: PrimaryCTAView, leading: AnyView? = nil, trailing: AnyView? = nil) {
        self.cta = cta
        self.leading = leading
        self.trailing = trailing
    }

    init(cta: PrimaryCTAView,
         @ViewBuilder leading: () -> some View,
         trailing: AnyView? = nil) {
        self.cta = cta
        self.leading = AnyView(leading())
        self.trailing = trailing
    }

    init(cta: PrimaryCTAView,
         leading: AnyView? = nil,
         @ViewBuilder trailing: () -> some View) {
        self.cta = cta
        self.leading = leading
        self.trailing = AnyView(trailing())
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: Self.sideSpacing) {
                if let leading { leading }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            cta
            HStack(spacing: Self.sideSpacing) {
                if let trailing { trailing }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, Self.sidePadding)
        .frame(height: Self.height)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dock")
    }
}

/// The dock's meta line (spec §4.2 `.meta`): 12 pt `textSecondary` with an optional
/// semibold `textPrimary` figure — "«1.2 GB» selected", "«12» apps checked".
struct DockMetaView: View {
    let bold: String?
    let text: String

    init(bold: String? = nil, text: String) {
        self.bold = bold
        self.text = text
    }

    var body: some View {
        combinedText
            .font(Theme.Font.callout)
            .foregroundStyle(Theme.Color.textSecondary)
            .monospacedDigit()
            .lineLimit(1)
            .truncationMode(.middle)
    }

    private var combinedText: Text {
        if let bold, !bold.isEmpty {
            let figure = Text(bold).fontWeight(.semibold).foregroundStyle(Theme.Color.textPrimary)
            let rest = text.isEmpty ? Text("") : Text(" \(text)")
            return figure + rest
        }
        return Text(text)
    }
}

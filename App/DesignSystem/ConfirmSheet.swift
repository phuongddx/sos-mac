import SwiftUI

/// The one confirmation before anything leaves its place (spec §4.8). Five variants —
/// trash, cloud (server delete), uninstall, quarantine, cleanup list — drawn as the
/// prototype's alert box, presented as a macOS sheet (OD-4): Escape closes it and
/// VoiceOver semantics come free.
///
/// **CF-1 — Cancel is the default button in every variant**: Return and Enter activate
/// Cancel, never a removal. **CF-3** — the count and size in the title are the numbers the
/// review bar shows, computed once by the view model that builds the model.
struct ConfirmSheet: View {
    enum Variant: String, Equatable, CaseIterable, Sendable {
        case trash
        case cloud
        case uninstall
        case quarantine
        case cleanupList

        /// The wide (380 pt, left-aligned, row buttons) variants: cloud and the Space Lens
        /// cleanup list. Trash, uninstall and quarantine are the narrow (300 pt, centred,
        /// stacked buttons) alert, as the prototype draws them.
        var isWide: Bool {
            switch self {
            case .cloud, .cleanupList: true
            case .trash, .uninstall, .quarantine: false
            }
        }
    }

    /// Everything one variant needs. All strings and numbers are the screen's real values.
    struct Model: Identifiable, Sendable {
        let variant: Variant
        /// The item count — the same number the review bar shows (CF-3).
        let count: Int
        /// The VM-formatted size for the title (CF-3); `nil` when the module has none.
        let sizeText: String?
        /// Uninstaller: the app being moved.
        let appName: String?
        /// Trash: "System Caches are included" note.
        let includesSystemCaches: Bool
        /// Trash: show "Review Items…" — only when opened from `results`.
        let isFromResults: Bool
        /// Uninstaller: the App Store note applies.
        let appStoreNote: Bool
        /// The full item list; the first 5 are shown (spec §4.8).
        let items: [ConfirmItem]
        /// The module hue behind the icon tile.
        let hue: Color
        let confirm: @MainActor (_ confirmed: ConfirmSelection) -> Void
        /// Cancel — never triggers the removal.
        let cancel: @MainActor () -> Void
        var reviewItems: (@MainActor () -> Void)?

        var id: String { "confirm-\(variant.rawValue)" }

        init(variant: Variant,
             count: Int,
             sizeText: String? = nil,
             appName: String? = nil,
             includesSystemCaches: Bool = false,
             isFromResults: Bool = false,
             appStoreNote: Bool = false,
             items: [ConfirmItem] = [],
             hue: Color = Theme.Color.primary,
             confirm: @escaping @MainActor (_ confirmed: ConfirmSelection) -> Void,
             cancel: @escaping @MainActor () -> Void,
             reviewItems: (@MainActor () -> Void)? = nil) {
            self.variant = variant
            self.count = count
            self.sizeText = sizeText
            self.appName = appName
            self.includesSystemCaches = includesSystemCaches
            self.isFromResults = isFromResults
            self.appStoreNote = appStoreNote
            self.items = items
            self.hue = hue
            self.confirm = confirm
            self.cancel = cancel
            self.reviewItems = reviewItems
        }
    }

    static let narrowWidth: CGFloat = 300
    static let wideWidth: CGFloat = 380
    static let padding = EdgeInsets(top: 20, leading: 18, bottom: 16, trailing: 18)
    static let iconSide: CGFloat = 52
    static let iconRadius: CGFloat = 13
    static let iconSymbolSize: CGFloat = 26

    let model: Model
    @State private var state: ConfirmSheetState
    @Environment(\.dismiss) private var dismiss

    init(model: Model) {
        self.model = model
        _state = State(initialValue: ConfirmSheetState(model: model))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            iconTile
                .frame(maxWidth: .infinity, alignment: model.variant.isWide ? .leading : .center)
                .padding(.bottom, Theme.Spacing.s3)
            titleText
                .padding(.bottom, Theme.Spacing.s2 - 2)
            bodyParagraphs
            ConfirmItemList(
                items: model.items,
                isSelectable: model.variant == .cleanupList,
                checkedItemIDs: state.checkedItemIDs,
                onToggle: { state.toggleItem($0) }
            )
            .padding(.top, Theme.Spacing.s3 - 2)
            .padding(.bottom, Theme.Spacing.s1)
            if model.variant == .cloud {
                acknowledgement
            }
            buttons
                .padding(.top, Theme.Spacing.s3 + 2)
        }
        .padding(Self.padding)
        .frame(width: model.variant.isWide ? Self.wideWidth : Self.narrowWidth, alignment: .leading)
        .background(Theme.Color.bgElevated)
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
            .strokeBorder(Theme.Derived.hairlineStrong, lineWidth: 1))
        .elevation(.float)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("confirm-sheet-\(model.variant.rawValue)")
    }

    // MARK: - Parts

    /// The icon tile (spec §4.8): 52 pt, radius 13, hue gradient, white glyph. The cloud
    /// variant uses the danger gradient.
    private var iconTile: some View {
        let shape = RoundedRectangle(cornerRadius: Self.iconRadius, style: .continuous)
        return ZStack {
            shape.fill(iconFill)
            Image(systemName: systemImage)
                .font(.system(size: Self.iconSymbolSize, weight: .medium))
                .foregroundStyle(Theme.Color.onPrimary)
        }
        .frame(width: Self.iconSide, height: Self.iconSide)
        .clipShape(shape)
        .accessibilityHidden(true)
    }

    private var iconFill: LinearGradient {
        if model.variant == .cloud {
            return LinearGradient(colors: [Theme.Color.danger, Theme.Color.dangerFill],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        let top = ColorMix.mix(model.hue, Theme.Color.onPrimary, fraction: 0.10, in: environment)
        let bottom = ColorMix.mix(model.hue, Color.black, fraction: 0.30, in: environment)
        return LinearGradient(colors: [top, bottom], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var systemImage: String {
        switch model.variant {
        case .trash, .cleanupList: "trash"
        case .cloud: "exclamationmark.triangle"
        case .uninstall: "xmark.bin"
        case .quarantine: "checkmark.shield"
        }
    }

    /// "Move **N** items (**size**) to the Trash?" — bold figures, real values (CF-3).
    private var titleText: some View {
        title
            .font(Theme.Font.body.weight(.semibold))
            .foregroundStyle(Theme.Color.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("confirm-title")
    }

    private var title: Text {
        let count = Text("\(model.count)").fontWeight(.semibold)
        switch model.variant {
        case .trash:
            var text = Text("Move ") + count + Text(" item\(model.count == 1 ? "" : "s")")
            if let sizeText = model.sizeText {
                text = text + Text(" (") + Text(sizeText).fontWeight(.semibold) + Text(")")
            }
            return text + Text(" to the Trash?")
        case .cloud:
            return Text("Delete ") + count + Text(" file\(model.count == 1 ? "" : "s") from Google Drive?")
        case .uninstall:
            if let appName = model.appName {
                return Text("Move ") + Text(appName).fontWeight(.semibold) + Text(" and ") + count
                    + Text(" related item\(model.count == 1 ? "" : "s") to the Trash?")
            }
            return Text("Move ") + count + Text(" item\(model.count == 1 ? "" : "s") to the Trash?")
        case .quarantine:
            return Text("Quarantine ") + count + Text(" item\(model.count == 1 ? "" : "s")?")
        case .cleanupList:
            return Text("Move ") + count + Text(" item\(model.count == 1 ? "" : "s") to the Trash?")
        }
    }

    @ViewBuilder
    private var bodyParagraphs: some View {
        VStack(alignment: model.variant.isWide ? .leading : .center, spacing: Theme.Spacing.s2) {
            switch model.variant {
            case .trash:
                paragraph("You can put them back from the Trash in Finder until you empty it.")
                if model.includesSystemCaches {
                    paragraph("System Caches are included: macOS will ask for your password once.")
                }
            case .cloud:
                paragraph("These files are deleted on Google Drive's servers, not moved to the Trash on this Mac. You can restore them only from Google Drive's own trash, and SOS Mac can't undo this.")
            case .uninstall:
                if let appName = model.appName {
                    paragraph("Quit \(appName) first if it's open. You can put everything back from the Trash in Finder.")
                } else {
                    paragraph("You can put everything back from the Trash in Finder.")
                }
                if model.appStoreNote {
                    paragraph("You can download it again from the App Store.")
                }
            case .quarantine:
                paragraph("SOS Mac moves it to a folder where it can't run. You can restore it from the Quarantine list at any time.")
            case .cleanupList:
                paragraph("Uncheck anything you want to keep. You can put items back from the Trash in Finder.")
            }
        }
    }

    private func paragraph(_ text: String) -> some View {
        Text(text)
            .font(Theme.Font.callout)
            .foregroundStyle(Theme.Color.textSecondary)
            .multilineTextAlignment(model.variant.isWide ? .leading : .center)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The cloud acknowledgement: the Delete button stays disabled until it is on.
    private var acknowledgement: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s2) {
            SOSCheckbox(isSelected: state.acknowledged, label: "I understand these files are deleted on Google Drive.") {
                state.toggleAcknowledgement()
            }
            Text("I understand these files are deleted on Google Drive.")
                .font(Theme.Font.callout)
                .foregroundStyle(Theme.Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, Theme.Spacing.s2)
        .accessibilityElement(children: .combine)
    }

    /// CF-1: Cancel is the default button — Return and Enter activate it, never a removal.
    /// Escape closes the sheet (the system's own sheet behaviour) and lands on the same
    /// cancel path.
    /// Narrow variants stack their buttons full width (the prototype's `.abtns` grid); wide
    /// variants put them in a trailing row.
    @ViewBuilder
    private var buttons: some View {
        if model.variant.isWide {
            if model.variant == .cleanupList {
                // "Cancel · Move to Trash (prominent, disabled when the list is empty)".
                HStack(spacing: Theme.Spacing.s2) {
                    cancelButton
                    Button("Move to Trash") { confirmAndDismiss() }
                        .sosButton(.prominent)
                        .disabled(!state.isConfirmEnabled)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                // Cloud: "Delete from Google Drive (danger, disabled until the checkbox is
                // ticked) · Cancel (prominent)".
                HStack(spacing: Theme.Spacing.s2) {
                    Button("Delete from Google Drive") { confirmAndDismiss() }
                        .sosButton(.danger)
                        .disabled(!state.isConfirmEnabled)
                    cancelButton
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        } else {
            VStack(spacing: Theme.Spacing.s2) {
                prominentButton
                if model.variant == .trash, model.isFromResults, let reviewItems = model.reviewItems {
                    Button("Review Items…") {
                        reviewItems()
                        dismiss()
                    }
                    .sosButton(.default)
                }
                cancelButton
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var prominentButton: some View {
        let title: String = model.variant == .quarantine ? "Quarantine" : "Move to Trash"
        return Button(title) { confirmAndDismiss() }
            .sosButton(.prominent)
            .disabled(!state.isConfirmEnabled)
    }

    /// Cancel never calls the confirm action; it only cancels (and dismisses the sheet).
    private var cancelButton: some View {
        let isProminent = model.variant == .cloud
        return Button("Cancel") {
            state.cancel()
            dismiss()
        }
        .sosButton(isProminent ? .prominent : .default)
        .keyboardShortcut(.defaultAction)
    }

    private func confirmAndDismiss() {
        guard state.confirm() != nil else { return }
        dismiss()
    }

    @Environment(\.self) private var environment
}

/// What the user confirmed: the ids still checked when the removal was approved. For every
/// variant except the cleanup list this is the full item list the model was built with.
struct ConfirmSelection: Equatable, Sendable {
    let itemIDs: Set<String>
}

/// The sheet's interaction state, extracted so its rules are unit-testable: the cloud
/// acknowledgement gate, the cleanup-list selection gate, and that cancel never calls the
/// confirm action (CF-1).
@MainActor
@Observable
final class ConfirmSheetState {
    private(set) var acknowledged = false
    private(set) var checkedItemIDs: Set<String>
    let model: ConfirmSheet.Model

    init(model: ConfirmSheet.Model) {
        self.model = model
        self.checkedItemIDs = Set(model.items.map(\.id))
    }

    /// The removal button's gate: cloud requires the acknowledgement; the cleanup list
    /// requires at least one checked item; every other variant is always enabled.
    var isConfirmEnabled: Bool {
        switch model.variant {
        case .cloud: return acknowledged
        case .cleanupList: return !checkedItemIDs.isEmpty
        case .trash, .uninstall, .quarantine: return true
        }
    }

    func toggleAcknowledgement() {
        acknowledged.toggle()
    }

    func toggleItem(_ id: String) {
        if checkedItemIDs.contains(id) {
            checkedItemIDs.remove(id)
        } else {
            checkedItemIDs.insert(id)
        }
    }

    /// Activates the removal — only when enabled. Returns what was confirmed, or `nil` when
    /// the button was disabled.
    func confirm() -> ConfirmSelection? {
        guard isConfirmEnabled else { return nil }
        let ids: Set<String>
        if model.variant == .cleanupList {
            ids = checkedItemIDs
        } else {
            ids = Set(model.items.map(\.id))
        }
        let selection = ConfirmSelection(itemIDs: ids)
        model.confirm(selection)
        return selection
    }

    /// CF-1: cancel only cancels — it never reaches `model.confirm`.
    func cancel() {
        model.cancel()
    }
}

extension ModuleOverlay {
    /// Presents a `ConfirmSheet` for the given model (spec §4.8, OD-4).
    static func confirmation(_ model: ConfirmSheet.Model) -> ModuleOverlay {
        ModuleOverlay(id: model.id) {
            ConfirmSheet(model: model)
        }
    }
}

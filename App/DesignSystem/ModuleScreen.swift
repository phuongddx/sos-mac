import SwiftUI

/// The frame every scanning screen is assembled from (spec §4.1): the window toolbar
/// (title + state subtitle, OD-2), the aurora canvas tinted with the module hue, the
/// per-state content, and the dock — or, in `review`, the review bar (spec §4.5).
/// A `ModuleOverlay` (usually a `ConfirmSheet`) is presented as a macOS sheet (OD-4).
///
/// The frame owns chrome only. F1: the one focal action of each state is always the round
/// CTA in the dock. F6: the toolbar subtitle is never empty and the dock keeps its height
/// across the non-review states. F7: the content cross-fades with `Motion.standard`; the
/// phase change itself is instant.
///
/// Screens pass real values in (`subtitle`, `selection`, `progress`) — the frame never
/// invents a number.
struct ModuleScreen<Content: View>: View {
    /// The frame's actions, one per control a state shows. A missing action disables its
    /// control (e.g. "Clean" with nothing selected) rather than hiding it — the focal action
    /// of a state is always present.
    struct Actions {
        /// The state's focal action: Scan / Clean / Try Again. For `done` and `empty` pass
        /// `scanAgain` instead; the frame wires the CTA to it.
        var primary: (@MainActor () -> Void)?
        /// `scanning` — Stop (F2: the screen returns to `start` and discards partial results).
        var stop: (@MainActor () -> Void)?
        /// `results` — the module's open-review verb (`module.dock.openReview`) in the dock's leading slot.
        var reviewItems: (@MainActor () -> Void)?
        /// `results` (trailing), `done` and `empty` (the CTA) — the module's finish verb
        /// (`module.dock`: Scan Again, Check Again, Measure Again, Back to Apps, Back to Map…).
        var scanAgain: (@MainActor () -> Void)?
        /// `done` — Open Trash in the trailing slot (`module.dock.doneSecondary`; none for Protection).
        var openTrash: (@MainActor () -> Void)?
        /// `error` — the one relevant escape (Open System Settings, Choose Another Folder).
        var escape: Escape?

        struct Escape {
            let label: String
            let action: @MainActor () -> Void
        }

        init(primary: (@MainActor () -> Void)? = nil,
             stop: (@MainActor () -> Void)? = nil,
             reviewItems: (@MainActor () -> Void)? = nil,
             scanAgain: (@MainActor () -> Void)? = nil,
             openTrash: (@MainActor () -> Void)? = nil,
             escape: Escape? = nil) {
            self.primary = primary
            self.stop = stop
            self.reviewItems = reviewItems
            self.scanAgain = scanAgain
            self.openTrash = openTrash
            self.escape = escape
        }
    }

    /// The selection summary the results meta and review bar show (CF-3): computed once by
    /// the view model, never re-derived here. `nil` means nothing to show.
    struct SelectionSummary: Equatable, Sendable {
        let count: Int
        /// VM-formatted size of the selection; `nil` when the module has no size yet.
        let sizeText: String?

        /// A bold figure and the words after it.
        struct Meta: Equatable, Sendable {
            let bold: String?
            let text: String
        }
    }

    let module: ModuleIdentity
    let state: LifecycleState
    var subtitle: String?
    var back: ModuleToolbarModel.Back?
    var tools: AnyView?
    var actions: Actions
    /// Determinate scan progress 0…1 for the Stop CTA's ring; `nil` draws the indeterminate
    /// ring (spec §4.2, prototype `scanDock`).
    var progress: Double?
    var selection: SelectionSummary?
    /// A real figure for the `results` dock meta that is not a selection ("**12** apps checked",
    /// Updater §5.8). Wins over the selection summary and the module's fixed hint.
    var resultsMeta: SelectionSummary.Meta?
    var overlay: Binding<ModuleOverlay?>?
    let content: Content

    init(module: ModuleIdentity,
         state: LifecycleState,
         subtitle: String? = nil,
         back: ModuleToolbarModel.Back? = nil,
         tools: AnyView? = nil,
         actions: Actions = Actions(),
         progress: Double? = nil,
         selection: SelectionSummary? = nil,
         resultsMeta: SelectionSummary.Meta? = nil,
         overlay: Binding<ModuleOverlay?>? = nil,
         @ViewBuilder content: () -> Content) {
        self.module = module
        self.state = state
        self.subtitle = subtitle
        self.back = back
        self.tools = tools
        self.actions = actions
        self.progress = progress
        self.selection = selection
        self.resultsMeta = resultsMeta
        self.overlay = overlay
        self.content = content()
    }

    private var toolbarModel: ModuleToolbarModel {
        ModuleToolbarModel(title: module.name,
                           subtitle: subtitle ?? state.defaultSubtitle,
                           back: back,
                           tools: tools)
    }

    var body: some View {
        VStack(spacing: 0) {
            // F7: the phase change is instant; the swap cross-fades with Motion.standard.
            ZStack {
                content
                    .id(state)
                    .transition(.opacity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(Theme.Motion.standard, value: state)
            bottomBar
        }
        .auroraBackground(hue: module.hue)
        .background(Theme.Color.bgBase)
        .moduleToolbar(toolbarModel)
        .modifier(ModuleSheetPresentation(overlay: overlay))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("module-screen-\(module.name)")
    }

    // MARK: - Bottom bar

    /// `review` swaps the dock for the review bar (spec §4.5); every other state keeps the
    /// 128 pt dock so the layout does not jump (F6).
    @ViewBuilder
    private var bottomBar: some View {
        switch state {
        case .review:
            reviewBar
        case .start, .scanning, .results, .cleaning, .done, .empty, .error:
            DockView(cta: cta, leading: dockLeading, trailing: dockTrailing)
        }
    }

    private var reviewBar: some View {
        ReviewBarView(
            meta: selection.map { summary in
                AnyView(DockMetaView(bold: summary.sizeText, text: summary.count == 0 ? "nothing selected" : "selected"))
            },
            selectedCount: selection?.count ?? 0,
            selectedSizeText: selection?.sizeText,
            ctaLabel: module.reviewActionTitle,
            isCTAEnabled: (selection?.count ?? 0) > 0 && actions.primary != nil,
            isCTADanger: module.isReviewCTADanger,
            ctaAction: actions.primary
        )
    }

    // MARK: - CTA (F1)

    private var cta: PrimaryCTAView {
        switch state {
        case .start:
            // F1: a missing action disables its control — a screen whose state
            // has nothing to scan yet (Cloud Cleanup's not-configured
            // providers) shows the truthfully unusable CTA.
            PrimaryCTAView(label: module.startActionTitle,
                           mode: actions.primary == nil ? .disabled : .active,
                           action: actions.primary)
        case .scanning:
            PrimaryCTAView(label: "Stop", mode: .stop, ring: scanRing, action: actions.stop)
        case .results:
            PrimaryCTAView(label: module.dock.resultsAction,
                           mode: actions.primary == nil ? .disabled : .active,
                           action: actions.primary)
        case .review:
            // The review bar replaces the dock; the CTA model is still defined so a
            // screen that opts out of the bar can reuse it.
            PrimaryCTAView(label: module.reviewActionTitle,
                           mode: actions.primary == nil ? .disabled : .active,
                           action: actions.primary)
        case .cleaning:
            PrimaryCTAView(label: "Moving", mode: .moving, ring: .indeterminate)
        case .done, .empty:
            PrimaryCTAView(label: state == .done ? module.dock.doneAction : module.dock.emptyAction,
                           action: actions.scanAgain)
        case .error:
            PrimaryCTAView(label: "Try Again", action: actions.primary)
        }
    }

    private var scanRing: PrimaryCTAView.Ring {
        if let progress { return .determinate(progress) }
        return .indeterminate
    }

    // MARK: - Dock slots

    private var dockLeading: AnyView? {
        guard state == .results else { return nil }
        return AnyView(HStack(spacing: DockView.sideSpacing) {
            if let openReview = module.dock.openReview {
                Button {
                    actions.reviewItems?()
                } label: {
                    Label(openReview, systemImage: "list")
                }
                .sosButton(.default)
                .disabled(actions.reviewItems == nil)
            }
            resultsMetaView
        })
    }

    /// The `results` meta: a screen-supplied figure, else the module's fixed hint, else the
    /// selection summary ("Nothing selected" when empty).
    @ViewBuilder
    private var resultsMetaView: some View {
        if let resultsMeta {
            DockMetaView(bold: resultsMeta.bold, text: resultsMeta.text)
        } else if let hint = module.dock.resultsHint {
            DockMetaView(bold: nil, text: hint)
        } else {
            DockMetaView(bold: selection?.sizeText,
                         text: (selection?.count ?? 0) > 0 ? "selected" : module.dock.nothingSelectedMeta)
        }
    }

    private var dockTrailing: AnyView? {
        switch state {
        case .results:
            guard let finish = module.dock.resultsFinish else { return nil }
            return AnyView(Button(finish) { actions.scanAgain?() }
                .buttonStyle(.sosPlain)
                .disabled(actions.scanAgain == nil))
        case .done:
            guard let secondary = module.dock.doneSecondary else { return nil }
            return AnyView(Button {
                actions.openTrash?()
            } label: {
                Label(secondary, systemImage: "trash")
            }
            .sosButton(.default)
            .disabled(actions.openTrash == nil))
        case .error:
            guard let escape = actions.escape else { return nil }
            return AnyView(Button(escape.label) { escape.action() }
                .sosButton(.default))
        case .start, .scanning, .review, .cleaning, .empty:
            return nil
        }
    }
}

/// Presents the frame's sheet (OD-4). `nil` binding — the normal case — presents nothing.
private struct ModuleSheetPresentation: ViewModifier {
    let overlay: Binding<ModuleOverlay?>?

    func body(content: Content) -> some View {
        if let overlay {
            // OD-4/CF-1: SwiftUI clears the item binding on every dismissal —
            // including Escape, which never touches the Cancel button. The routed
            // binding sends those dismissals through the same exit as Cancel.
            content.sheet(item: ModuleSheetDismissal.binding(overlay)) { moduleOverlay in
                moduleOverlay.content
            }
        } else {
            content
        }
    }
}

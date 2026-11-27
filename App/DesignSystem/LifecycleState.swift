import SwiftUI

/// The lifecycle vocabulary every module that scans shares (spec §4.1).
///
/// Each module keeps its own `Phase` enum (project rule) and exposes a pure, unit-tested
/// mapping `var lifecycle: LifecycleState`; screens adopt the shared frame in their own PRs.
enum LifecycleState: String, CaseIterable, Sendable, Identifiable {
    case start, scanning, results, review, cleaning, done, empty, error

    var id: String { rawValue }

    /// The state word the toolbar shows when the screen has no real value for it (F6). State
    /// words only — counts, sizes and folders come from each screen, never a guess.
    var defaultSubtitle: String {
        switch self {
        case .start: "Ready"
        case .scanning: "Scanning…"
        case .results: "Results"
        case .review: "Review"
        case .cleaning: "Moving to Trash…"
        case .done: "Done"
        case .empty: "Nothing found"
        case .error: "Stopped"
        }
    }
}

/// The dock labels a module overrides (spec Appendix A, "One verb per idea"). The defaults are
/// the cleaner modules' wording — Smart Care, Junk & Cache, Duplicate Finder, iCloud Drive —
/// so a module that does not override a label keeps the frame's original text.
struct DockCopy: Hashable, Sendable {
    /// `results` — the round CTA. "Clean" for modules that clean; Protection and Uninstaller
    /// open a review instead ("Review"), Space Lens "Review…", Updater "Check Again".
    var resultsAction = "Clean"
    /// `results` — the leading "open review" button. `nil` leaves the slot to the meta text
    /// (the review is the CTA, or the module has nothing to review).
    var openReview: String? = "Review Items…"
    /// `results` — the leading meta text while the selection is empty.
    var nothingSelectedMeta = "Nothing selected"
    /// `results` — a fixed hint that replaces the selection meta altogether (Protection §5.10,
    /// Uninstaller §5.7), for modules whose selection is not made on this screen.
    var resultsHint: String?
    /// `results` — the trailing plain button. `nil` hides it.
    var resultsFinish: String? = "Scan Again"
    /// `done` — the CTA.
    var doneAction = "Scan Again"
    /// `done` — the trailing secondary. `nil` hides it (Cloud's server-side delete has no Trash).
    var doneSecondary: String? = "Open Trash"
    /// `empty` — the CTA.
    var emptyAction = "Scan Again"
}

/// A module's identity in the shared frame: the name the toolbar and eyebrows show, the hue
/// the canvas glows with, and the glyph the orb carries.
struct ModuleIdentity: Hashable, Sendable {
    /// Screen name, e.g. "Junk & Cache".
    let name: String
    /// Module hue (spec §2.5).
    let hue: Color
    /// Module glyph.
    let symbol: String
    /// The dock CTA label in `start` (spec §4.1): Scan; Updater "Check"; Uninstaller "Measure All".
    let startActionTitle: String
    /// The review bar CTA label (spec §4.1): "Move to Trash…"; Protection "Quarantine…".
    let reviewActionTitle: String
    /// The review bar CTA renders in the danger style only for the
    /// server-side cloud delete (spec §4.4) — Cloud Cleanup's API providers.
    let isReviewCTADanger: Bool
    /// The per-module dock wording for `results`, `done` and `empty` (Appendix A).
    let dock: DockCopy

    init(name: String, hue: Color, symbol: String,
         startActionTitle: String = "Scan",
         reviewActionTitle: String = "Move to Trash…",
         isReviewCTADanger: Bool = false,
         dock: DockCopy = DockCopy()) {
        self.name = name
        self.hue = hue
        self.symbol = symbol
        self.startActionTitle = startActionTitle
        self.reviewActionTitle = reviewActionTitle
        self.isReviewCTADanger = isReviewCTADanger
        self.dock = dock
    }

    init(module: SidebarDestination) {
        self.init(
            name: module.rawValue,
            hue: module.tileHue,
            symbol: module.systemImage,
            startActionTitle: module == .updater ? "Check" : (module == .uninstaller ? "Measure All" : "Scan"),
            reviewActionTitle: module == .protection ? "Quarantine…" : "Move to Trash…",
            dock: Self.dockCopy(for: module)
        )
    }

    /// Appendix A, module by module. Anything not listed keeps the `DockCopy` defaults.
    static func dockCopy(for module: SidebarDestination) -> DockCopy {
        var copy = DockCopy()
        switch module {
        case .spaceLens:
            // §5.5: the cleanup list opens from "Review…" (one button, not two).
            copy.resultsAction = "Review…"
            copy.openReview = nil
            // §5.5 done: the card's "Back to Map" leads (prominent); the dock CTA is
            // "Scan Again" with "Open Trash" trailing. Empty: "Choose Folder…".
            copy.emptyAction = "Choose Folder…"
        case .uninstaller:
            // §5.7: results "Review" + "Measure Again"; done "Back to Apps"; empty "Check Again".
            copy.resultsAction = "Review"
            copy.openReview = nil
            copy.resultsHint = "Choose an app to review what it left behind"
            copy.resultsFinish = "Measure Again"
            copy.doneAction = "Back to Apps"
            copy.emptyAction = "Check Again"
        case .updater:
            // §5.8: read-only — nothing to review or clean; the CTA re-checks.
            copy.resultsAction = "Check Again"
            copy.openReview = nil
            copy.resultsFinish = nil
            copy.doneSecondary = nil
            copy.emptyAction = "Check Again"
        case .protection:
            // §5.10: results "Review" with the hint, "Scan Again"; the quarantine never trashes.
            copy.resultsAction = "Review"
            copy.openReview = nil
            copy.resultsHint = "Review the finding, then quarantine it"
            copy.doneSecondary = nil
        case .smartCare, .junkCleaner, .duplicateFinder, .cloudCleanup,
             .dashboard, .performance:
            break
        }
        return copy
    }
}

/// A sheet `ModuleScreen` presents (spec §4.8, OD-4): a macOS sheet gets keyboard trapping,
/// Escape and VoiceOver semantics for free. Screens keep the optional in a `@State` property
/// and pass the binding, so dismissing the sheet (Escape, the Cancel button) clears it.
struct ModuleOverlay: Identifiable {
    let id: AnyHashable
    let content: AnyView
    /// The exit a system-initiated dismissal takes (Escape, `performCancel`): the same
    /// closure Cancel runs, wired by `ModuleSheetDismissal.wrap`. `nil` for overlays
    /// that have no such exit.
    var onSystemDismiss: (@MainActor () -> Void)?

    init(id: AnyHashable,
         onSystemDismiss: (@MainActor () -> Void)? = nil,
         @ViewBuilder content: () -> some View) {
        self.id = id
        self.content = AnyView(content())
        self.onSystemDismiss = onSystemDismiss
    }
}

/// Straight-sRGB `color-mix(in srgb, a (1 − f), b f)`, as CSS blends. Used only for the spec's
/// own hue recipes (§4.2, §4.9) — mixes the Palette C token set does not carry. Resolved in
/// `environment` so adaptive colours follow the appearance.
enum ColorMix {
    static func mix(_ a: Color, _ b: Color, fraction: Double, in environment: EnvironmentValues) -> Color {
        let f = min(max(fraction, 0), 1)
        let x = a.resolve(in: environment)
        let y = b.resolve(in: environment)
        return Color(.sRGB,
                     red: Double(x.red) * (1 - f) + Double(y.red) * f,
                     green: Double(x.green) * (1 - f) + Double(y.green) * f,
                     blue: Double(x.blue) * (1 - f) + Double(y.blue) * f)
    }
}

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

    init(name: String, hue: Color, symbol: String,
         startActionTitle: String = "Scan",
         reviewActionTitle: String = "Move to Trash…") {
        self.name = name
        self.hue = hue
        self.symbol = symbol
        self.startActionTitle = startActionTitle
        self.reviewActionTitle = reviewActionTitle
    }

    init(module: SidebarDestination) {
        self.init(
            name: module.rawValue,
            hue: module.tileHue,
            symbol: module.systemImage,
            startActionTitle: module == .updater ? "Check" : (module == .uninstaller ? "Measure All" : "Scan"),
            reviewActionTitle: module == .protection ? "Quarantine…" : "Move to Trash…"
        )
    }
}

/// A sheet `ModuleScreen` presents (spec §4.8, OD-4): a macOS sheet gets keyboard trapping,
/// Escape and VoiceOver semantics for free. Screens keep the optional in a `@State` property
/// and pass the binding, so dismissing the sheet (Escape, the Cancel button) clears it.
struct ModuleOverlay: Identifiable {
    let id: AnyHashable
    let content: AnyView

    init(id: AnyHashable, @ViewBuilder content: () -> some View) {
        self.id = id
        self.content = AnyView(content())
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

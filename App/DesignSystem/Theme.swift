import SwiftUI
import AppKit

/// Design tokens transcribed from the Open Design "Aurora Care" system
/// (`macos-care-suite/styles.css`) shared by every screen except the
/// onboarding/paywall Atelier Zero screens, which are a deliberate tonal
/// contrast and out of scope. Aurora Care is an evolution of the prior
/// Neutral Modern tokens (same accent/severity/spacing), extended with a
/// gradient accent partner, module hue map, softer geometry, and two-layer
/// elevation.
enum Theme {
    static let background = dynamicColor(light: "#FAFAFA", dark: "#17171A")
    static let surface = dynamicColor(light: "#FFFFFF", dark: "#212126")
    static let foreground = dynamicColor(light: "#111111", dark: "#F4F4F6")
    static let muted = dynamicColor(light: "#6B6B6B", dark: "#9C9CA6")
    static let border = dynamicColor(light: "#E5E5E5", dark: "#33333B")

    static let accent = Color(hex: "#2F6FEB")
    /// Gradient partner only — never a standalone fill/border/text color.
    /// Use `accentGradient` or `.auroraBloom()` instead of referencing this
    /// directly, matching the "one accent per screen" rule in styles.css.
    static let accent2 = Color(hex: "#17B3B3")
    static let success = Color(hex: "#17A34A")
    static let warn = Color(hex: "#EAB308")
    static let danger = Color(hex: "#DC2626")

    /// Matches `--accent-grad: linear-gradient(135deg, var(--accent), var(--accent-2))`.
    static let accentGradient = LinearGradient(
        colors: [accent, accent2],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let xxxl: CGFloat = 32
        static let huge: CGFloat = 48
        static let giant: CGFloat = 80
    }

    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        /// Hero panels and the reclaimed-space success card only.
        static let xl: CGFloat = 28
        static let pill: CGFloat = 9999
    }

    enum TextSize {
        static let xs: CGFloat = 12
        static let sm: CGFloat = 14
        static let base: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        static let xxxl: CGFloat = 48
    }

    /// Two-layer soft elevation (`--elev-raised` / `--elev-float`) — apply via
    /// the `.elevation(_:)` view modifier, not by reading these directly.
    enum Elevation {
        enum Level { case raised, float }

        struct Layer {
            let color: Color
            let radius: CGFloat
            let y: CGFloat
        }

        static func layers(for level: Level, isDark: Bool) -> (near: Layer, far: Layer) {
            switch (level, isDark) {
            case (.raised, false):
                return (Layer(color: Theme.foreground.opacity(0.06), radius: 1, y: 1),
                        Layer(color: Theme.foreground.opacity(0.08), radius: 14, y: 10))
            case (.raised, true):
                return (Layer(color: .black.opacity(0.5), radius: 1, y: 1),
                        Layer(color: .black.opacity(0.42), radius: 16, y: 12))
            case (.float, false):
                return (Layer(color: Theme.foreground.opacity(0.08), radius: 2, y: 2),
                        Layer(color: Theme.foreground.opacity(0.12), radius: 22, y: 18))
            case (.float, true):
                return (Layer(color: .black.opacity(0.55), radius: 3, y: 2),
                        Layer(color: .black.opacity(0.5), radius: 26, y: 22))
            }
        }
    }

    /// Module identity colors — `--hue-*` in styles.css. One hue per module,
    /// deliberately excluding red: module hues never read as a threat.
    enum ModuleHue {
        static let dashboard = Color(hex: "#2F6FEB")
        static let smartCare = Color(hex: "#7C5CF5")
        static let junkCleaner = Color(hex: "#17B3B3")
        static let uninstaller = Color(hex: "#EF8B3C")
        static let updater = Color(hex: "#2BA55F")
        static let spaceLens = Color(hex: "#8B5CF6")
        static let duplicateFinder = Color(hex: "#D9578A")
        static let performance = Color(hex: "#D9A21B")
        static let cloudCleanup = Color(hex: "#3A9CE0")
        static let protection = Color(hex: "#5566E0")
        /// Not yet wired to a `SidebarDestination` case — Settings has no
        /// screen in this app yet. Kept so the token set matches the source
        /// contract and is ready when that screen ships.
        static let settings = Color(hex: "#7A7A82")
    }

    /// One hue per `SidebarDestination`, matching styles.css's
    /// `[data-page]`/`[href]` module hue wiring.
    static func hue(for destination: SidebarDestination) -> Color {
        switch destination {
        case .dashboard: return ModuleHue.dashboard
        case .smartCare: return ModuleHue.smartCare
        case .junkCleaner: return ModuleHue.junkCleaner
        case .uninstaller: return ModuleHue.uninstaller
        case .updater: return ModuleHue.updater
        case .spaceLens: return ModuleHue.spaceLens
        case .duplicateFinder: return ModuleHue.duplicateFinder
        case .performance: return ModuleHue.performance
        case .cloudCleanup: return ModuleHue.cloudCleanup
        case .protection: return ModuleHue.protection
        }
    }
}

private func dynamicColor(light: String, dark: String) -> Color {
    Color(NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return NSColor(Color(hex: isDark ? dark : light))
    })
}

extension Color {
    init(hex: String) {
        let hexValue = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var rgb: UInt64 = 0
        Scanner(string: hexValue).scanHexInt64(&rgb)
        let r = Double((rgb & 0xFF0000) >> 16) / 255
        let g = Double((rgb & 0x00FF00) >> 8) / 255
        let b = Double(rgb & 0x0000FF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

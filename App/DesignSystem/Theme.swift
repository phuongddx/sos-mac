import SwiftUI
import AppKit

/// Design tokens for the "Palette C" (Midnight Glass) redesign.
///
/// Source of truth: `docs/superpowers/specs/2026-11-26-ui-migration-palette-c-design.md`
/// §2.3–2.8 and Appendix C (dark values from `docs/redesign/prototype/tokens.css`
/// `data-palette="c"`; light values confirmed by the Designer's final Palette C
/// light block, 2026-11-26 — OD-1 closed: `warning` light `#A14A06`,
/// `treemapText` light `#141A33`, light elevation ink `#141A33`; every other
/// light value matched the table). The final source is the Designer's token
/// file in the Open Design project `sos-mac-redesign-v1-aurora-indigo`
/// (the in-repo `docs/redesign/prototype/tokens/Theme.swift` snapshot predates
/// the final light block and keeps the proposal's Palette A lineage).
///
/// Inside this type the names `Color`, `Gradient` and `Font` refer to the nested token
/// namespaces, so SwiftUI's own types are always written `SwiftUI.Color` etc.
enum Theme {
    // MARK: - Colour tokens (28)

    /// Usage rules (spec §2.6): `primaryDeep` is a fill, never text or an icon on a card
    /// (use `primary` / `primaryBright`); neon is a verb, not a surface; `textTertiary` is
    /// for large, bold, disabled or placeholder text only.
    enum Color {
        /// --bg-base · dark #0A0E1A · light #F4F6FF
        static let bgBase = SwiftUI.Color.adaptive(light: SwiftUI.Color(hex: "#F4F6FF"), dark: SwiftUI.Color(hex: "#0A0E1A"))
        /// --bg-elevated · dark #131A2E · light #FFFFFF
        static let bgElevated = SwiftUI.Color.adaptive(light: SwiftUI.Color(hex: "#FFFFFF"), dark: SwiftUI.Color(hex: "#131A2E"))
        /// --glass · dark #18213A · light #FFFFFF
        static let glass = SwiftUI.Color.adaptive(light: SwiftUI.Color(hex: "#FFFFFF"), dark: SwiftUI.Color(hex: "#18213A"))
        /// --card · dark #111829 · light #FFFFFF
        static let card = SwiftUI.Color.adaptive(light: SwiftUI.Color(hex: "#FFFFFF"), dark: SwiftUI.Color(hex: "#111829"))
        /// --sidebar · dark #0E1424 · light #EEF2FF
        static let sidebar = SwiftUI.Color.adaptive(light: SwiftUI.Color(hex: "#EEF2FF"), dark: SwiftUI.Color(hex: "#0E1424"))
        /// --primary · dark #818CF8 · light #4F46E5
        static let primary = SwiftUI.Color.adaptive(light: SwiftUI.Color(hex: "#4F46E5"), dark: SwiftUI.Color(hex: "#818CF8"))
        /// --primary-deep · dark #4F46E5 · light #4F46E5
        static let primaryDeep = SwiftUI.Color.adaptive(light: SwiftUI.Color(hex: "#4F46E5"), dark: SwiftUI.Color(hex: "#4F46E5"))
        /// --primary-bright · dark #A5B4FC · light #4338CA
        static let primaryBright = SwiftUI.Color.adaptive(light: SwiftUI.Color(hex: "#4338CA"), dark: SwiftUI.Color(hex: "#A5B4FC"))
        /// --on-primary · dark #FFFFFF · light #FFFFFF
        static let onPrimary = SwiftUI.Color.adaptive(light: SwiftUI.Color(hex: "#FFFFFF"), dark: SwiftUI.Color(hex: "#FFFFFF"))
        /// --neon-cyan · dark #22D3EE · light #155E75
        static let neonCyan = SwiftUI.Color.adaptive(light: SwiftUI.Color(hex: "#155E75"), dark: SwiftUI.Color(hex: "#22D3EE"))
        /// --neon-lime · dark #A3E635 · light #3F6212
        static let neonLime = SwiftUI.Color.adaptive(light: SwiftUI.Color(hex: "#3F6212"), dark: SwiftUI.Color(hex: "#A3E635"))
        /// --neon-magenta · dark #A78BFA · light #6D28D9
        static let neonMagenta = SwiftUI.Color.adaptive(light: SwiftUI.Color(hex: "#6D28D9"), dark: SwiftUI.Color(hex: "#A78BFA"))
        /// --text-1 · dark #EEF2FF · light #141A33
        static let textPrimary = SwiftUI.Color.adaptive(light: SwiftUI.Color(hex: "#141A33"), dark: SwiftUI.Color(hex: "#EEF2FF"))
        /// --text-2 · dark #A5ADC8 · light #4A5273
        static let textSecondary = SwiftUI.Color.adaptive(light: SwiftUI.Color(hex: "#4A5273"), dark: SwiftUI.Color(hex: "#A5ADC8"))
        /// --text-3 · dark #6E7799 · light #7C84A3
        static let textTertiary = SwiftUI.Color.adaptive(light: SwiftUI.Color(hex: "#7C84A3"), dark: SwiftUI.Color(hex: "#6E7799"))
        /// --success · dark #34D399 · light #047857
        static let success = SwiftUI.Color.adaptive(light: SwiftUI.Color(hex: "#047857"), dark: SwiftUI.Color(hex: "#34D399"))
        /// --warning · dark #F59E0B · light #A14A06 (Designer final light; 5.02–6.00:1 on every surface)
        static let warning = SwiftUI.Color.adaptive(light: SwiftUI.Color(hex: "#A14A06"), dark: SwiftUI.Color(hex: "#F59E0B"))
        /// --danger · dark #F87171 · light #B91C1C
        static let danger = SwiftUI.Color.adaptive(light: SwiftUI.Color(hex: "#B91C1C"), dark: SwiftUI.Color(hex: "#F87171"))
        /// --danger-fill · dark #B91C1C · light #B91C1C
        static let dangerFill = SwiftUI.Color.adaptive(light: SwiftUI.Color(hex: "#B91C1C"), dark: SwiftUI.Color(hex: "#B91C1C"))
        /// --tm-1 · dark #4A3A9E · light #DDD6FE
        static let treemap1 = SwiftUI.Color.adaptive(light: SwiftUI.Color(hex: "#DDD6FE"), dark: SwiftUI.Color(hex: "#4A3A9E"))
        /// --tm-2 · dark #3D3F95 · light #E0E7FF
        static let treemap2 = SwiftUI.Color.adaptive(light: SwiftUI.Color(hex: "#E0E7FF"), dark: SwiftUI.Color(hex: "#3D3F95"))
        /// --tm-3 · dark #34509C · light #DBEAFE
        static let treemap3 = SwiftUI.Color.adaptive(light: SwiftUI.Color(hex: "#DBEAFE"), dark: SwiftUI.Color(hex: "#34509C"))
        /// --tm-4 · dark #2E5B8F · light #E0F2FE
        static let treemap4 = SwiftUI.Color.adaptive(light: SwiftUI.Color(hex: "#E0F2FE"), dark: SwiftUI.Color(hex: "#2E5B8F"))
        /// --tm-5 · dark #463C82 · light #EDE9FE
        static let treemap5 = SwiftUI.Color.adaptive(light: SwiftUI.Color(hex: "#EDE9FE"), dark: SwiftUI.Color(hex: "#463C82"))
        /// --tm-6 · dark #3A4780 · light #D9E2FF
        static let treemap6 = SwiftUI.Color.adaptive(light: SwiftUI.Color(hex: "#D9E2FF"), dark: SwiftUI.Color(hex: "#3A4780"))
        /// --tm-7 · dark #353A6E · light #E9E5FF
        static let treemap7 = SwiftUI.Color.adaptive(light: SwiftUI.Color(hex: "#E9E5FF"), dark: SwiftUI.Color(hex: "#353A6E"))
        /// --tm-8 · dark #2D2A55 · light #ECE7FA
        static let treemap8 = SwiftUI.Color.adaptive(light: SwiftUI.Color(hex: "#ECE7FA"), dark: SwiftUI.Color(hex: "#2D2A55"))
        /// --tm-text · dark #F4F2FF · light #141A33 (Designer final light)
        static let treemapText = SwiftUI.Color.adaptive(light: SwiftUI.Color(hex: "#141A33"), dark: SwiftUI.Color(hex: "#F4F2FF"))
    }

    // MARK: - Derived tokens (spec §2.4)

    /// Translucent tokens built from the 28 colour tokens' own hues.
    enum Derived {
        static let hairline = SwiftUI.Color.adaptive(light: SwiftUI.Color(hex: "#141A33").opacity(0.09), dark: SwiftUI.Color(hex: "#A5ADC8").opacity(0.12))
        static let hairlineStrong = SwiftUI.Color.adaptive(light: SwiftUI.Color(hex: "#141A33").opacity(0.16), dark: SwiftUI.Color(hex: "#A5ADC8").opacity(0.22))
        static let rowHover = SwiftUI.Color.adaptive(light: SwiftUI.Color(hex: "#4338CA").opacity(0.06), dark: SwiftUI.Color(hex: "#A5B4FC").opacity(0.08))
        /// Selected-row fill. Composite it over `Color.card`; never put `textTertiary` on it (spec T3).
        static let rowSelected = SwiftUI.Color.adaptive(light: SwiftUI.Color(hex: "#4F46E5").opacity(0.12), dark: SwiftUI.Color(hex: "#818CF8").opacity(0.20))
        /// `--tm-mix`: `card` blended into the treemap tiles (dark 42 % · light 24 %).
        static let treemapMix = SwiftUI.Color.adaptive(light: SwiftUI.Color(hex: "#FFFFFF").opacity(0.24), dark: SwiftUI.Color(hex: "#111829").opacity(0.42))
    }

    // MARK: - Gradients (spec §2.4)

    enum Gradient {
        static let aurora = LinearGradient(colors: stops(light: ["#6366F1", "#4F46E5", "#155E75"], dark: ["#A5B4FC", "#818CF8", "#6366F1"]), startPoint: .leading, endPoint: .trailing)
        static let soft = LinearGradient(colors: stops(light: ["#8B5CF6", "#7C3AED", "#6366F1"], dark: ["#A78BFA", "#8B5CF6", "#6366F1"]), startPoint: .topLeading, endPoint: .bottomTrailing)
        private static func stops(light: [String], dark: [String]) -> [SwiftUI.Color] {
            zip(light, dark).map { SwiftUI.Color.adaptive(light: SwiftUI.Color(hex: $0), dark: SwiftUI.Color(hex: $1)) }
        }
    }

    // MARK: - Glow (spec §2.4, §2.6 T6)

    /// Glow budget: none in light, none under Reduce Motion (callers check that).
    enum Glow {
        static func idleAlpha(isDark: Bool) -> Double { isDark ? 0.32 : 0 }
        static func auroraAlpha(isDark: Bool) -> Double { isDark ? 0.16 : 0.07 }
    }

    // MARK: - Module hues (spec §2.5, same in both appearances)

    /// Tile fills. Bare marks on the light base fail 3:1 (spec T5), so hues are fills, not marks.
    enum Hue {
        static let smartcare = SwiftUI.Color(hex: "#8B5CF6")
        static let junk = SwiftUI.Color(hex: "#6366F1")
        static let duplicates = SwiftUI.Color(hex: "#3B82F6")
        static let spacelens = SwiftUI.Color(hex: "#E879F9")
        static let cloud = SwiftUI.Color(hex: "#38BDF8")
        static let uninstaller = SwiftUI.Color(hex: "#FB923C")
        static let updater = SwiftUI.Color(hex: "#FBBF24")
        static let performance = SwiftUI.Color(hex: "#2DD4BF")
        static let protection = SwiftUI.Color(hex: "#22D3EE")
        /// The tenth hue: rose, used by the Protection "Known threats" tile.
        static let threat = SwiftUI.Color(hex: "#F87171")

        /// Glyph colour drawn on the matching tile (same order as the fills above).
        enum Ink {
            static let smartcare = SwiftUI.Color(hex: "#FFFFFF")
            static let junk = SwiftUI.Color(hex: "#FFFFFF")
            static let duplicates = SwiftUI.Color(hex: "#FFFFFF")
            static let spacelens = SwiftUI.Color(hex: "#140F26")
            static let cloud = SwiftUI.Color(hex: "#140F26")
            static let uninstaller = SwiftUI.Color(hex: "#140F26")
            static let updater = SwiftUI.Color(hex: "#140F26")
            static let performance = SwiftUI.Color(hex: "#140F26")
            static let protection = SwiftUI.Color(hex: "#140F26")
            static let threat = SwiftUI.Color(hex: "#140F26")
        }
    }

    // MARK: - Geometry, type, motion (spec §2.8)

    enum Spacing {
        static let s1: CGFloat = 4
        static let s2: CGFloat = 8
        static let s3: CGFloat = 12
        static let s4: CGFloat = 16
        static let s5: CGFloat = 20
        static let s6: CGFloat = 24
        static let s8: CGFloat = 32
        static let s12: CGFloat = 48
    }

    enum Radius {
        static let xs: CGFloat = 5
        static let sm: CGFloat = 7
        static let md: CGFloat = 10
        static let lg: CGFloat = 14
        static let xl: CGFloat = 20
        static let pill: CGFloat = 999
    }

    enum Motion {
        static let quick = Animation.easeOut(duration: 0.15)
        static let standard = Animation.snappy(duration: 0.25)
        static let emphasized = Animation.spring(duration: 0.45, bounce: 0.2)
        /// Scanning glow period in seconds; skip when Reduce Motion is on.
        static let pulseDuration: Double = 2.4
    }

    enum Font {
        static let numeralXL = SwiftUI.Font.system(size: 40, weight: .semibold).monospacedDigit()
        static let numeralL = SwiftUI.Font.system(size: 28, weight: .semibold).monospacedDigit()
        static let display = SwiftUI.Font.largeTitle.weight(.semibold)
        static let title1 = SwiftUI.Font.title.weight(.semibold)
        static let title2 = SwiftUI.Font.title2.weight(.semibold)
        static let title3 = SwiftUI.Font.title3.weight(.semibold)
        static let headline = SwiftUI.Font.headline
        static let body = SwiftUI.Font.body
        static let callout = SwiftUI.Font.callout
        static let subheadline = SwiftUI.Font.subheadline
        static let eyebrow = SwiftUI.Font.caption.weight(.semibold)
        static let mono = SwiftUI.Font.system(.caption, design: .monospaced)
    }

    /// Two-layer soft elevation — apply via the `.elevation(_:)` view modifier, not by
    /// reading these directly. Dark layers are black-based; light layers are `#141A33`-based (spec §2.4).
    enum Elevation {
        enum Level { case raised, float }

        struct Layer {
            let color: SwiftUI.Color
            let radius: CGFloat
            let y: CGFloat
        }

        private static let lightInk = SwiftUI.Color(hex: "#141A33")

        static func layers(for level: Level, isDark: Bool) -> (near: Layer, far: Layer) {
            switch (level, isDark) {
            case (.raised, false):
                return (Layer(color: lightInk.opacity(0.06), radius: 1, y: 1),
                        Layer(color: lightInk.opacity(0.08), radius: 14, y: 10))
            case (.raised, true):
                return (Layer(color: .black.opacity(0.5), radius: 1, y: 1),
                        Layer(color: .black.opacity(0.42), radius: 16, y: 12))
            case (.float, false):
                return (Layer(color: lightInk.opacity(0.08), radius: 2, y: 2),
                        Layer(color: lightInk.opacity(0.12), radius: 22, y: 18))
            case (.float, true):
                return (Layer(color: .black.opacity(0.55), radius: 3, y: 2),
                        Layer(color: .black.opacity(0.5), radius: 26, y: 22))
            }
        }
    }
}

// MARK: - Helpers

private extension SwiftUI.Color {
    /// Resolves per appearance (light / dark) through a dynamic `NSColor`.
    static func adaptive(light: SwiftUI.Color, dark: SwiftUI.Color) -> SwiftUI.Color {
        SwiftUI.Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua]) != nil ? NSColor(dark) : NSColor(light)
        })
    }
}

extension SwiftUI.Color {
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

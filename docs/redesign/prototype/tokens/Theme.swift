// Theme.swift — Aurora Indigo proposal for SOS Mac (generated from the redesign prototype tokens.css).
// Not in the repo yet: review against App/DesignSystem/Theme.swift before replacing anything.
// Dark is the primary appearance; light values follow "neon always darkens".

import SwiftUI
import AppKit

private extension SwiftUI.Color {
    /// Resolves per appearance (light / dark) through NSColor.
    static func adaptive(light: SwiftUI.Color, dark: SwiftUI.Color) -> SwiftUI.Color {
        SwiftUI.Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua]) != nil ? NSColor(dark) : NSColor(light)
        })
    }
}

enum Theme {
    enum Color {
        /// --bg-base · dark #0B0A14 · light #F7F5FF
        static let bgBase = SwiftUI.Color.adaptive(light: SwiftUI.Color(red: 0.969, green: 0.961, blue: 1.000), dark: SwiftUI.Color(red: 0.043, green: 0.039, blue: 0.078))
        /// --bg-elevated · dark #151327 · light #FFFFFF
        static let bgElevated = SwiftUI.Color.adaptive(light: SwiftUI.Color(red: 1.000, green: 1.000, blue: 1.000), dark: SwiftUI.Color(red: 0.082, green: 0.075, blue: 0.153))
        /// --glass · dark #1D1A33 · light #FFFFFF
        static let glass = SwiftUI.Color.adaptive(light: SwiftUI.Color(red: 1.000, green: 1.000, blue: 1.000), dark: SwiftUI.Color(red: 0.114, green: 0.102, blue: 0.200))
        /// --card · dark #16142A · light #FFFFFF
        static let card = SwiftUI.Color.adaptive(light: SwiftUI.Color(red: 1.000, green: 1.000, blue: 1.000), dark: SwiftUI.Color(red: 0.086, green: 0.078, blue: 0.165))
        /// --sidebar · dark #100E1E · light #EEEAFB
        static let sidebar = SwiftUI.Color.adaptive(light: SwiftUI.Color(red: 0.933, green: 0.918, blue: 0.984), dark: SwiftUI.Color(red: 0.063, green: 0.055, blue: 0.118))
        /// --primary · dark #8B5CF6 · light #7C3AED
        static let primary = SwiftUI.Color.adaptive(light: SwiftUI.Color(red: 0.486, green: 0.227, blue: 0.929), dark: SwiftUI.Color(red: 0.545, green: 0.361, blue: 0.965))
        /// --primary-deep · dark #6D28D9 · light #7C3AED
        static let primaryDeep = SwiftUI.Color.adaptive(light: SwiftUI.Color(red: 0.486, green: 0.227, blue: 0.929), dark: SwiftUI.Color(red: 0.427, green: 0.157, blue: 0.851))
        /// --primary-bright · dark #A78BFA · light #6D28D9
        static let primaryBright = SwiftUI.Color.adaptive(light: SwiftUI.Color(red: 0.427, green: 0.157, blue: 0.851), dark: SwiftUI.Color(red: 0.655, green: 0.545, blue: 0.980))
        /// --on-primary · dark #FFFFFF · light #FFFFFF
        static let onPrimary = SwiftUI.Color.adaptive(light: SwiftUI.Color(red: 1.000, green: 1.000, blue: 1.000), dark: SwiftUI.Color(red: 1.000, green: 1.000, blue: 1.000))
        /// --neon-cyan · dark #22D3EE · light #0E7490
        static let neonCyan = SwiftUI.Color.adaptive(light: SwiftUI.Color(red: 0.055, green: 0.455, blue: 0.565), dark: SwiftUI.Color(red: 0.133, green: 0.827, blue: 0.933))
        /// --neon-lime · dark #A3E635 · light #4D7C0F
        static let neonLime = SwiftUI.Color.adaptive(light: SwiftUI.Color(red: 0.302, green: 0.486, blue: 0.059), dark: SwiftUI.Color(red: 0.639, green: 0.902, blue: 0.208))
        /// --neon-magenta · dark #E879F9 · light #A21CAF
        static let neonMagenta = SwiftUI.Color.adaptive(light: SwiftUI.Color(red: 0.635, green: 0.110, blue: 0.686), dark: SwiftUI.Color(red: 0.910, green: 0.475, blue: 0.976))
        /// --text-1 · dark #F4F2FF · light #1A1333
        static let textPrimary = SwiftUI.Color.adaptive(light: SwiftUI.Color(red: 0.102, green: 0.075, blue: 0.200), dark: SwiftUI.Color(red: 0.957, green: 0.949, blue: 1.000))
        /// --text-2 · dark #B8B2D9 · light #56506E
        static let textSecondary = SwiftUI.Color.adaptive(light: SwiftUI.Color(red: 0.337, green: 0.314, blue: 0.431), dark: SwiftUI.Color(red: 0.722, green: 0.698, blue: 0.851))
        /// --text-3 · dark #7A73A8 · light #8B86A3
        static let textTertiary = SwiftUI.Color.adaptive(light: SwiftUI.Color(red: 0.545, green: 0.525, blue: 0.639), dark: SwiftUI.Color(red: 0.478, green: 0.451, blue: 0.659))
        /// --success · dark #34D399 · light #047857
        static let success = SwiftUI.Color.adaptive(light: SwiftUI.Color(red: 0.016, green: 0.471, blue: 0.341), dark: SwiftUI.Color(red: 0.204, green: 0.827, blue: 0.600))
        /// --warning · dark #FBBF24 · light #B45309
        static let warning = SwiftUI.Color.adaptive(light: SwiftUI.Color(red: 0.706, green: 0.325, blue: 0.035), dark: SwiftUI.Color(red: 0.984, green: 0.749, blue: 0.141))
        /// --danger · dark #F87171 · light #B91C1C
        static let danger = SwiftUI.Color.adaptive(light: SwiftUI.Color(red: 0.725, green: 0.110, blue: 0.110), dark: SwiftUI.Color(red: 0.973, green: 0.443, blue: 0.443))
        /// --danger-fill · dark #B91C1C · light #B91C1C
        static let dangerFill = SwiftUI.Color.adaptive(light: SwiftUI.Color(red: 0.725, green: 0.110, blue: 0.110), dark: SwiftUI.Color(red: 0.725, green: 0.110, blue: 0.110))
        /// --tm-1 · dark #4A3A9E · light #DDD6FE
        static let treemap1 = SwiftUI.Color.adaptive(light: SwiftUI.Color(red: 0.867, green: 0.839, blue: 0.996), dark: SwiftUI.Color(red: 0.290, green: 0.227, blue: 0.620))
        /// --tm-2 · dark #3D3F95 · light #E0E7FF
        static let treemap2 = SwiftUI.Color.adaptive(light: SwiftUI.Color(red: 0.878, green: 0.906, blue: 1.000), dark: SwiftUI.Color(red: 0.239, green: 0.247, blue: 0.584))
        /// --tm-3 · dark #34509C · light #DBEAFE
        static let treemap3 = SwiftUI.Color.adaptive(light: SwiftUI.Color(red: 0.859, green: 0.918, blue: 0.996), dark: SwiftUI.Color(red: 0.204, green: 0.314, blue: 0.612))
        /// --tm-4 · dark #2E5B8F · light #E0F2FE
        static let treemap4 = SwiftUI.Color.adaptive(light: SwiftUI.Color(red: 0.878, green: 0.949, blue: 0.996), dark: SwiftUI.Color(red: 0.180, green: 0.357, blue: 0.561))
        /// --tm-5 · dark #463C82 · light #EDE9FE
        static let treemap5 = SwiftUI.Color.adaptive(light: SwiftUI.Color(red: 0.929, green: 0.914, blue: 0.996), dark: SwiftUI.Color(red: 0.275, green: 0.235, blue: 0.510))
        /// --tm-6 · dark #3A4780 · light #D9E2FF
        static let treemap6 = SwiftUI.Color.adaptive(light: SwiftUI.Color(red: 0.851, green: 0.886, blue: 1.000), dark: SwiftUI.Color(red: 0.227, green: 0.278, blue: 0.502))
        /// --tm-7 · dark #353A6E · light #E9E5FF
        static let treemap7 = SwiftUI.Color.adaptive(light: SwiftUI.Color(red: 0.914, green: 0.898, blue: 1.000), dark: SwiftUI.Color(red: 0.208, green: 0.227, blue: 0.431))
        /// --tm-8 · dark #2D2A55 · light #ECE7FA
        static let treemap8 = SwiftUI.Color.adaptive(light: SwiftUI.Color(red: 0.925, green: 0.906, blue: 0.980), dark: SwiftUI.Color(red: 0.176, green: 0.165, blue: 0.333))
        /// --tm-text · dark #F4F2FF · light #1A1333
        static let treemapText = SwiftUI.Color.adaptive(light: SwiftUI.Color(red: 0.102, green: 0.075, blue: 0.200), dark: SwiftUI.Color(red: 0.957, green: 0.949, blue: 1.000))
    }

    /// Module tile hues (same in both appearances). `ink` is the glyph colour on the tile.
    enum Hue {
        static let smartcare = SwiftUI.Color(red: 0.545, green: 0.361, blue: 0.965)  // #8B5CF6, ink #fff
        static let junk = SwiftUI.Color(red: 0.388, green: 0.400, blue: 0.945)  // #6366F1, ink #fff
        static let duplicates = SwiftUI.Color(red: 0.231, green: 0.510, blue: 0.965)  // #3B82F6, ink #fff
        static let spacelens = SwiftUI.Color(red: 0.910, green: 0.475, blue: 0.976)  // #E879F9, ink #140F26
        static let cloud = SwiftUI.Color(red: 0.220, green: 0.741, blue: 0.973)  // #38BDF8, ink #140F26
        static let uninstaller = SwiftUI.Color(red: 0.984, green: 0.573, blue: 0.235)  // #FB923C, ink #140F26
        static let updater = SwiftUI.Color(red: 0.984, green: 0.749, blue: 0.141)  // #FBBF24, ink #140F26
        static let performance = SwiftUI.Color(red: 0.176, green: 0.831, blue: 0.749)  // #2DD4BF, ink #140F26
        static let protection = SwiftUI.Color(red: 0.133, green: 0.827, blue: 0.933)  // #22D3EE, ink #140F26
    }

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
        static let pulseDuration: Double = 2.4  // scanning glow; skip when Reduce Motion is on
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
}

/// Material with fallbacks: Liquid Glass on macOS 26, system material on 14–15, solid with Reduce Transparency.
struct AuroraSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var cornerRadius: CGFloat = Theme.Radius.lg
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if reduceTransparency {
            content.background(Theme.Color.glass, in: shape)
        } else if #available(macOS 26, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content.background(.regularMaterial, in: shape)
        }
    }
}

import SwiftUI
import AppKit

/// Design tokens transcribed from the Open Design "Neutral Modern" system
/// (`macos-care-suite/styles.css`) shared by every screen except the
/// onboarding/paywall Atelier Zero screens, which are a deliberate tonal
/// contrast and out of scope.
enum Theme {
    static let background = dynamicColor(light: "#FAFAFA", dark: "#1E1E20")
    static let surface = dynamicColor(light: "#FFFFFF", dark: "#2A2A2D")
    static let foreground = dynamicColor(light: "#111111", dark: "#F2F2F3")
    static let muted = dynamicColor(light: "#6B6B6B", dark: "#9A9A9E")
    static let border = dynamicColor(light: "#E5E5E5", dark: "#3A3A3D")

    static let accent = Color(hex: "#2F6FEB")
    static let success = Color(hex: "#17A34A")
    static let warn = Color(hex: "#EAB308")
    static let danger = Color(hex: "#DC2626")

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

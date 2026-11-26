import AppKit
import SwiftUI
import Testing
@testable import SOSMac

/// Contrast rules of the Palette C token set (spec §2.3–2.7, plan T1.1), asserted as numbers
/// (WCAG 2.x relative luminance) in both appearances.
@Suite("Palette C contrast")
struct ThemeContrastTests {
    // MARK: - Colour resolution and maths

    enum Mode: String, CaseIterable, Sendable {
        case light, dark
        var appearanceName: NSAppearance.Name { self == .dark ? .darkAqua : .aqua }
    }

    struct RGBA {
        var r: Double, g: Double, b: Double, a: Double
    }

    /// Resolves a token to sRGB components under the given appearance.
    static func resolve(_ color: SwiftUI.Color, _ mode: Mode) -> RGBA {
        var out = RGBA(r: 0, g: 0, b: 0, a: 0)
        NSAppearance(named: mode.appearanceName)!.performAsCurrentDrawingAppearance {
            let ns = NSColor(color).usingColorSpace(.sRGB) ?? .clear
            out = RGBA(r: Double(ns.redComponent), g: Double(ns.greenComponent), b: Double(ns.blueComponent), a: Double(ns.alphaComponent))
        }
        return out
    }

    /// `top` painted over an opaque `bottom` (straight sRGB alpha blend, as CSS does).
    static func composite(_ top: RGBA, over bottom: RGBA) -> RGBA {
        RGBA(r: top.r * top.a + bottom.r * (1 - top.a),
             g: top.g * top.a + bottom.g * (1 - top.a),
             b: top.b * top.a + bottom.b * (1 - top.a),
             a: 1)
    }

    static func luminance(_ c: RGBA) -> Double {
        func lin(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)
    }

    static func contrast(_ a: RGBA, _ b: RGBA) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// Contrast of `fg` on an opaque `bg`; a translucent `fg` is composited over `bg` first.
    static func ratio(_ fg: SwiftUI.Color, on bg: SwiftUI.Color, _ mode: Mode) -> Double {
        let back = resolve(bg, mode)
        let front = composite(resolve(fg, mode), over: back)
        return contrast(front, back)
    }

    typealias C = Theme.Color

    /// Opaque surfaces text must read on (plan T1.1).
    static let surfaces: [(name: String, color: SwiftUI.Color)] = [
        ("bgBase", C.bgBase), ("bgElevated", C.bgElevated), ("card", C.card), ("glass", C.glass), ("sidebar", C.sidebar),
    ]

    // MARK: - Text

    @Test("textPrimary is at least 7:1 on every surface", arguments: Mode.allCases)
    func textPrimaryOnSurfaces(mode: Mode) {
        for s in Self.surfaces {
            let r = Self.ratio(C.textPrimary, on: s.color, mode)
            #expect(r >= 7.0, "textPrimary on \(s.name) (\(mode.rawValue)) = \(r)")
        }
    }

    @Test("textSecondary is at least 4.5:1 on every surface", arguments: Mode.allCases)
    func textSecondaryOnSurfaces(mode: Mode) {
        for s in Self.surfaces {
            let r = Self.ratio(C.textSecondary, on: s.color, mode)
            #expect(r >= 4.5, "textSecondary on \(s.name) (\(mode.rawValue)) = \(r)")
        }
    }

    /// `rowSelected` is translucent: it is composited over `card` before measuring.
    static func selectedRow(_ mode: Mode) -> SwiftUI.Color {
        let blended = Self.composite(Self.resolve(Theme.Derived.rowSelected, mode), over: Self.resolve(C.card, mode))
        return SwiftUI.Color(red: blended.r, green: blended.g, blue: blended.b)
    }

    @Test("Text on a selected row (rowSelected over card)", arguments: Mode.allCases)
    func textOnSelectedRow(mode: Mode) {
        let row = Self.selectedRow(mode)
        let primary = Self.ratio(C.textPrimary, on: row, mode)
        let secondary = Self.ratio(C.textSecondary, on: row, mode)
        #expect(primary >= 7.0, "textPrimary on rowSelected (\(mode.rawValue)) = \(primary)")
        #expect(secondary >= 4.5, "textSecondary on rowSelected (\(mode.rawValue)) = \(secondary)")
    }

    // MARK: - Brand and status colours

    @Test("primaryBright is at least 4.5:1 on base and card", arguments: Mode.allCases)
    func primaryBright(mode: Mode) {
        for s in [("bgBase", C.bgBase), ("card", C.card)] {
            let r = Self.ratio(C.primaryBright, on: s.1, mode)
            #expect(r >= 4.5, "primaryBright on \(s.0) (\(mode.rawValue)) = \(r)")
        }
    }

    @Test("success, warning and danger are at least 4.5:1 on card", arguments: Mode.allCases)
    func statusOnCard(mode: Mode) {
        for s in [("success", C.success), ("warning", C.warning), ("danger", C.danger)] {
            let r = Self.ratio(s.1, on: C.card, mode)
            #expect(r >= 4.5, "\(s.0) on card (\(mode.rawValue)) = \(r)")
        }
    }

    @Test("onPrimary is at least 4.5:1 on primaryDeep and dangerFill", arguments: Mode.allCases)
    func onPrimaryOnFills(mode: Mode) {
        for s in [("primaryDeep", C.primaryDeep), ("dangerFill", C.dangerFill)] {
            let r = Self.ratio(C.onPrimary, on: s.1, mode)
            #expect(r >= 4.5, "onPrimary on \(s.0) (\(mode.rawValue)) = \(r)")
        }
    }

    // MARK: - Module hues

    /// Tile fill used by the prototype: hue 92 % + white 8 % at the top, hue 78 % + black 22 % at the bottom.
    static func tileEnds(_ hue: SwiftUI.Color) -> [RGBA] {
        let h = resolve(hue, .dark)  // hues are the same in both appearances
        let top = RGBA(r: h.r * 0.92 + 0.08, g: h.g * 0.92 + 0.08, b: h.b * 0.92 + 0.08, a: 1)
        let bottom = RGBA(r: h.r * 0.78, g: h.g * 0.78, b: h.b * 0.78, a: 1)
        return [top, bottom]
    }

    static let hueTiles: [(name: String, hue: SwiftUI.Color, ink: SwiftUI.Color)] = [
        ("smartcare", Theme.Hue.smartcare, Theme.Hue.Ink.smartcare),
        ("junk", Theme.Hue.junk, Theme.Hue.Ink.junk),
        ("duplicates", Theme.Hue.duplicates, Theme.Hue.Ink.duplicates),
        ("spacelens", Theme.Hue.spacelens, Theme.Hue.Ink.spacelens),
        ("cloud", Theme.Hue.cloud, Theme.Hue.Ink.cloud),
        ("uninstaller", Theme.Hue.uninstaller, Theme.Hue.Ink.uninstaller),
        ("updater", Theme.Hue.updater, Theme.Hue.Ink.updater),
        ("performance", Theme.Hue.performance, Theme.Hue.Ink.performance),
        ("protection", Theme.Hue.protection, Theme.Hue.Ink.protection),
        ("threat", Theme.Hue.threat, Theme.Hue.Ink.threat),
    ]

    @Test("Every module-hue ink is at least 3:1 on its tile, top and bottom")
    func hueInkOnTile() {
        #expect(Self.hueTiles.count == 10)
        for tile in Self.hueTiles {
            let ink = Self.resolve(tile.ink, .dark)
            for (i, end) in Self.tileEnds(tile.hue).enumerated() {
                let r = Self.contrast(ink, end)
                #expect(r >= 3.0, "\(tile.name) ink on tile \(i == 0 ? "top" : "bottom") = \(r)")
            }
        }
    }

    @Test("Module hues and inks do not change between appearances")
    func huesAreAppearanceIndependent() {
        for tile in Self.hueTiles {
            let l = Self.resolve(tile.hue, .light), d = Self.resolve(tile.hue, .dark)
            #expect(abs(l.r - d.r) < 0.001 && abs(l.g - d.g) < 0.001 && abs(l.b - d.b) < 0.001, "\(tile.name)")
        }
    }
}

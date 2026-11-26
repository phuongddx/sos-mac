import SwiftUI

/// App-only shims mapping `SidebarDestination` to Palette C hue/ink tokens.
/// Kept out of `Theme.swift` so the token file stays free of app types and can be
/// shared with the `MenuBarHelper` target (plan PR 15).
extension Theme {
    /// One hue per `SidebarDestination`.
    @available(*, deprecated, message: "Use the Palette C Theme.Hue tokens")
    static func hue(for destination: SidebarDestination) -> SwiftUI.Color {
        switch destination {
        case .dashboard: return Hue.smartcare
        case .smartCare: return Hue.smartcare
        case .junkCleaner: return Hue.junk
        case .uninstaller: return Hue.uninstaller
        case .updater: return Hue.updater
        case .spaceLens: return Hue.spacelens
        case .duplicateFinder: return Hue.duplicates
        case .performance: return Hue.performance
        case .cloudCleanup: return Hue.cloud
        case .protection: return Hue.protection
        }
    }

    /// The ink that reads on each destination's hue tile (spec §2.5, ≥ 3:1).
    @available(*, deprecated, message: "Use the Palette C Theme.Hue.Ink tokens")
    static func ink(for destination: SidebarDestination) -> SwiftUI.Color {
        switch destination {
        case .dashboard: return Hue.Ink.smartcare
        case .smartCare: return Hue.Ink.smartcare
        case .junkCleaner: return Hue.Ink.junk
        case .uninstaller: return Hue.Ink.uninstaller
        case .updater: return Hue.Ink.updater
        case .spaceLens: return Hue.Ink.spacelens
        case .duplicateFinder: return Hue.Ink.duplicates
        case .performance: return Hue.Ink.performance
        case .cloudCleanup: return Hue.Ink.cloud
        case .protection: return Hue.Ink.protection
        }
    }
}

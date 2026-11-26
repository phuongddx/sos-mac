import SwiftUI
import AppKit
import CleanCore

/// A SwiftUI `MenuBarExtra` scene, not hand-rolled `NSStatusItem` code —
/// `MenuBarExtra` is the modern (macOS 13+) SwiftUI-native equivalent, built
/// on `NSStatusItem` under the hood, and this target already deploys to
/// macOS 14+.
@main
struct MenuBarHelperApp: App {
    @State private var monitor = MenuBarMetricsMonitor()

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopover(monitor: monitor)
        } label: {
            // View-based label (rather than the plain-string initializer) so the
            // numeral field can carry `.monospacedDigit()` and stay fixed-width.
            Label {
                Text(monitor.labelText).monospacedDigit()
            } icon: {
                Image(systemName: "gauge.with.dots.needle.50percent")
            }
        }
        .menuBarExtraStyle(.window)
    }
}

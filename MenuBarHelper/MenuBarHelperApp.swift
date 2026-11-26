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
            // numeral field can carry `.monospacedDigit()`. The hidden "CPU 100%"
            // (the widest possible sample) holds the frame, so the status item never
            // reflows between 1-, 2- and 3-digit CPU values (space padding alone is
            // not enough: spaces are ~3.8 pt wide vs ~8.7 pt per digit).
            Label {
                ZStack(alignment: .leading) {
                    Text("CPU 100%").monospacedDigit().hidden().accessibilityHidden(true)
                    Text(monitor.labelText).monospacedDigit()
                }
            } icon: {
                Image(systemName: "gauge.with.dots.needle.50percent")
            }
        }
        .menuBarExtraStyle(.window)
    }
}

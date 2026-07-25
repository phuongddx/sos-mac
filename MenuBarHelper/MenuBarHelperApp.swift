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
        MenuBarExtra(monitor.labelText, systemImage: "gauge.with.dots.needle.50percent") {
            MenuBarContentView(monitor: monitor)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarContentView: View {
    let monitor: MenuBarMetricsMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SOS Mac").font(.headline)

            if let cpu = monitor.cpuPercent {
                Text("CPU: \(String(format: "%.0f%%", cpu))")
            } else {
                Text("CPU: —")
            }

            if let used = monitor.memoryUsedBytes, let total = monitor.memoryTotalBytes {
                Text("Memory: \(ByteFormatter.string(fromByteCount: Int64(used))) / \(ByteFormatter.string(fromByteCount: Int64(total)))")
            }

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding()
        .frame(width: 220)
    }
}

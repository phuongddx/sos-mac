import SwiftUI
import AppKit
import CleanCore

/// Popover content for the menu-bar widget (spec §5.11). Shares `Theme` and
/// `AuroraSurface` with the app target (plan PR 15) instead of hand-rolling colours.
struct MenuBarPopover: View {
    let monitor: MenuBarMetricsMonitor

    private static let sosMacBundleIdentifier = "com.nextlabs.sosmac"

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s4) {
            header

            MenuBarMetricCard(
                title: "CPU",
                valueText: monitor.cpuPercent.map { String(format: "%.0f%%", $0) } ?? "—",
                detailText: nil,
                progress: monitor.cpuPercent.map { $0 / 100 }
            )

            MenuBarMetricCard(
                title: "Memory",
                valueText: monitor.memoryPercentText ?? "—",
                detailText: monitor.memoryDetailText
            )

            Divider().overlay(Theme.Derived.hairline)

            actions
        }
        .padding(Theme.Spacing.s4)
        .frame(width: 260)
        .auroraSurface(cornerRadius: Theme.Radius.lg)
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.s3) {
            RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                .fill(Theme.Hue.performance)
                .frame(width: 28, height: 28)
                .overlay {
                    Image(systemName: "gauge.with.dots.needle.50percent")
                        .foregroundStyle(Theme.Hue.Ink.performance)
                        .font(Theme.Font.headline)
                }

            VStack(alignment: .leading, spacing: 1) {
                Text("SOS Mac")
                    .font(Theme.Font.headline)
                    .foregroundStyle(Theme.Color.textPrimary)
                Text("Updates every 2 seconds")
                    .font(Theme.Font.eyebrow)
                    .foregroundStyle(Theme.Color.textSecondary)
            }
        }
    }

    private var actions: some View {
        VStack(spacing: Theme.Spacing.s2) {
            Button {
                openSOSMac()
            } label: {
                Label("Open SOS Mac", systemImage: "arrow.up.forward.app")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .keyboardShortcut("o", modifiers: .command)

            Button(role: .destructive) {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit Widget", systemImage: "xmark.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .buttonStyle(.plain)
        .font(Theme.Font.body)
        .foregroundStyle(Theme.Color.textPrimary)
    }

    /// Activates the main app if already running, otherwise launches it, by bundle
    /// identifier rather than a hardcoded path — `NSWorkspace` resolves the install location.
    private func openSOSMac() {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: Self.sosMacBundleIdentifier).first {
            running.activate()
            return
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.sosMacBundleIdentifier) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}

/// One metric card: numeral/percent, optional detail line, optional progress meter.
private struct MenuBarMetricCard: View {
    let title: String
    let valueText: String
    let detailText: String?
    var progress: Double? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s1) {
            HStack {
                Text(title)
                    .font(Theme.Font.subheadline)
                    .foregroundStyle(Theme.Color.textSecondary)
                Spacer()
                Text(valueText)
                    .font(Theme.Font.numeralL)
                    .foregroundStyle(Theme.Color.textPrimary)
            }

            if let detailText {
                Text(detailText)
                    .font(Theme.Font.callout)
                    .foregroundStyle(Theme.Color.textSecondary)
            }

            if let progress {
                MenuBarMeter(fraction: progress)
            }
        }
        .padding(Theme.Spacing.s3)
        .frame(maxWidth: .infinity)
        .background(Theme.Color.card, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .strokeBorder(Theme.Derived.hairline)
        )
    }
}

/// The prototype's `.meter.sm` (4 pt): a `hairline-strong` track with a
/// `gradient-soft` fill (spec §5.11; `Hue.performance` fails 3:1 on a light card, T5).
private struct MenuBarMeter: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Theme.Derived.hairlineStrong)
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Theme.Gradient.soft)
                    .frame(width: min(max(fraction, 0), 1) * geo.size.width)
            }
        }
        .frame(height: 4)
    }
}

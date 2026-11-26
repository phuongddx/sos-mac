import SwiftUI
import CleanCore

/// Performance on Palette C (plan PR 12, spec §5.9): a live screen with **no scan
/// lifecycle** — no `Phase` machine, no dock. The screen composes the aurora canvas and
/// the window toolbar itself (as Protection's Quarantine sub-screen does), then the metric
/// grid, the maintenance rows with per-action inline banners, and the widget / login cards.
///
/// Documented deviations from the prototype (also in the PR 12 gallery README):
/// - **OD-14:** the login card reads "Open SOS Mac at login." — the switch registers the
///   **main app** as a login item, it does not start the menu bar widget.
/// - The launch-agents list shows each entry's real path where the prototype shows a date
///   column; `LoginItemEntry` carries a path, not a date.
/// - The approval banner's "Open System Settings" opens Login Items through the documented
///   `SMAppService.openSystemSettingsLoginItems()` — OD-18 keeps undocumented deep links
///   out; this one is the API the app already uses.
struct PerformanceView: View {
    @Environment(ModuleStore.self) private var store
    private var viewModel: PerformanceViewModel { store.performance }

    var body: some View {
        PerformanceScreen(viewModel: viewModel)
    }
}

private struct PerformanceScreen: View {
    var viewModel: PerformanceViewModel

    private let module = ModuleIdentity(module: .performance)
    private static let contentPadding: CGFloat = 40

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.s6) {
                if isUnavailable {
                    unavailableBanner
                }
                PerformanceMetricGrid(sample: viewModel.currentSample, showsUnavailable: isUnavailable)
                Text("Maintenance")
                    .font(Theme.Font.eyebrow)
                    .foregroundStyle(Theme.Color.textSecondary)
                MaintenanceRows(viewModel: viewModel, isUnavailable: isUnavailable)
                bottomCards
                if let widgetError = viewModel.widgetError {
                    BannerView(kind: .err, title: "Couldn't open the menu bar widget", text: widgetError)
                }
                if let loginItemError = viewModel.loginItemError {
                    BannerView(kind: .err, title: "Couldn't update the login setting", text: loginItemError)
                }
            }
            .padding(EdgeInsets(top: Theme.Spacing.s5,
                                leading: Self.contentPadding,
                                bottom: Theme.Spacing.s8,
                                trailing: Self.contentPadding))
        }
        .auroraBackground(hue: module.hue)
        .background(Theme.Color.bgBase)
        .moduleToolbar(ModuleToolbarModel(title: module.name, subtitle: toolbarSubtitle))
        .accessibilityIdentifier("performance-screen")
        .task {
            #if DEBUG
            if UITestHooks.current.fixtures, UITestHooks.current.destination == .performance {
                viewModel.loadFixtureFromLaunchHooks()
                return
            }
            #endif
            await viewModel.runPollingLoop()
        }
    }

    /// The read state (spec §5.9): everything turns "—" and the banner shows only once a
    /// read actually completed and came back empty — never on the pre-poll frame.
    private var isUnavailable: Bool {
        viewModel.hasSampled && viewModel.metrics == .unavailable
    }

    /// The toolbar subtitle is **Live** or **No data** (spec §5.9); nothing before the
    /// first read (the frame hides an empty subtitle line).
    private var toolbarSubtitle: String? {
        guard viewModel.hasSampled else { return nil }
        return viewModel.metrics == .live ? "Live" : "No data"
    }

    private var unavailableBanner: some View {
        BannerView(
            kind: .err,
            title: "Couldn't read system metrics",
            text: "macOS didn't return CPU or memory data. Values show \u{201C}—\u{201D} until the next read.") {
            Button("Try Again") { viewModel.retryReading() }
                .sosButton(.default)
                .accessibilityIdentifier("performance-retry-read")
        }
    }

    // MARK: - Widget and login cards

    private var bottomCards: some View {
        Grid(horizontalSpacing: Theme.Spacing.s4, verticalSpacing: Theme.Spacing.s4) {
            GridRow {
                widgetCard
                loginCard
            }
        }
    }

    private var widgetCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s3) {
            cardHead(symbol: "gauge",
                     title: "Menu bar widget",
                     subtitle: "CPU and memory in the menu bar.")
            Button("Open Menu Bar Widget") { viewModel.openMenuBarWidget() }
                .sosButton(.default)
                .accessibilityIdentifier("performance-open-widget")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .performanceCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("performance-widget-card")
    }

    private var loginCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s3) {
            HStack(alignment: .top, spacing: Theme.Spacing.s3) {
                cardHead(symbol: "power",
                         title: "Open at login",
                         subtitle: "Open SOS Mac at login.")
                Spacer(minLength: Theme.Spacing.s3)
                Toggle("Open SOS Mac at login", isOn: Binding(
                    get: { viewModel.launchAtLoginStatus == .enabled },
                    set: { viewModel.setLoginItem(enabled: $0) }))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .accessibilityLabel("Open SOS Mac at login")
                    .accessibilityIdentifier("performance-login-toggle")
            }
            launchAgentsList
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .performanceCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("performance-login-card")
    }

    /// The launch agents the engine lists (`LoginItemsManager.listInstalledAgents()`); the
    /// card omits the section when there are none — never an invented entry.
    @ViewBuilder
    private var launchAgentsList: some View {
        if !viewModel.loginItemEntries.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("Installed launch agents")
                    .font(Theme.Font.eyebrow)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .padding(.bottom, Theme.Spacing.s2)
                ForEach(Array(viewModel.loginItemEntries.enumerated()), id: \.element.id) { index, entry in
                    HStack {
                        Text(entry.label)
                            .font(Theme.Font.mono)
                            .foregroundStyle(Theme.Color.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: Theme.Spacing.s3)
                        Text(entry.path)
                            .font(Theme.Font.callout)
                            .foregroundStyle(Theme.Color.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(.vertical, Theme.Spacing.s2)
                    .overlay(alignment: .bottom) {
                        if index < viewModel.loginItemEntries.count - 1 {
                            Rectangle().fill(Theme.Derived.hairline).frame(height: 1)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func cardHead(symbol: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s3) {
            ModuleTileView(hue: Theme.Hue.performance,
                           ink: Theme.Hue.Ink.performance,
                           symbol: symbol,
                           size: .row)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Font.headline)
                    .foregroundStyle(Theme.Color.textPrimary)
                Text(subtitle)
                    .font(Theme.Font.callout)
                    .foregroundStyle(Theme.Color.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

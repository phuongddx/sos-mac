import SwiftUI
import CleanCore

/// The maintenance rows (spec §5.9): "Free up RAM" and "Flush DNS Cache" with **Run**
/// (disabled + spinner "Running…" while it runs), and the per-action inline banner under
/// the row (spec §4.7):
///
/// - `needsApproval` → `info` "Approve the SOS Mac helper" + **Open System Settings** (the
///   documented Login Items deep link, OD-18);
/// - `succeeded` → `ok` "Free up RAM finished" / "Flush DNS Cache finished";
/// - `failed(message:)` → `err` "Couldn't free up RAM" / "Couldn't flush the DNS cache" +
///   **Try Again**.
///
/// The states come from the view model's `ActionState` — the row renders and dispatches,
/// it never mutates state on its own. Run is also disabled while the metric reads are
/// unavailable (the prototype's `disabled: running || na`).
struct MaintenanceRows: View {
    var viewModel: PerformanceViewModel
    var isUnavailable = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row(.freeRAM,
                symbol: "memorychip",
                title: "Free up RAM",
                subtitle: "Asks macOS to release inactive memory. Needs the SOS Mac helper.",
                successTitle: "Free up RAM finished",
                successText: "macOS released inactive memory.",
                failureTitle: "Couldn't free up RAM")
            rowDivider
            row(.flushDNS,
                symbol: "network",
                title: "Flush DNS Cache",
                subtitle: "Clears saved name lookups. Useful when a site won't load.",
                successTitle: "Flush DNS Cache finished",
                successText: "The saved name lookups were cleared.",
                failureTitle: "Couldn't flush the DNS cache")
        }
        .performanceCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("performance-maintenance")
    }

    private var rowDivider: some View {
        Rectangle().fill(Theme.Derived.hairline).frame(height: 1)
    }

    private func row(_ action: PerformanceViewModel.MaintenanceAction,
                     symbol: String,
                     title: String,
                     subtitle: String,
                     successTitle: String,
                     successText: String,
                     failureTitle: String) -> some View {
        let state = viewModel.actionState(of: action)
        return VStack(alignment: .leading, spacing: Theme.Spacing.s3) {
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
                Spacer(minLength: Theme.Spacing.s3)
                runControl(action, state: state)
            }
            inlineBanner(action, state: state,
                         successTitle: successTitle,
                         successText: successText,
                         failureTitle: failureTitle)
        }
        .padding(.vertical, Theme.Spacing.s4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("performance-maintenance-\(action.rawValue)")
    }

    @ViewBuilder
    private func runControl(_ action: PerformanceViewModel.MaintenanceAction,
                            state: PerformanceViewModel.ActionState) -> some View {
        if state == .running {
            HStack(spacing: Theme.Spacing.s2) {
                ProgressView()
                    .controlSize(.small)
                Text("Running…")
                    .font(Theme.Font.callout)
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(action == .freeRAM ? "Free up RAM" : "Flush DNS Cache") is running")
        } else {
            Button("Run") {
                Task { await viewModel.run(action) }
            }
            .sosButton(.default)
            .disabled(isUnavailable)
            .accessibilityIdentifier("performance-run-\(action.rawValue)")
        }
    }

    @ViewBuilder
    private func inlineBanner(_ action: PerformanceViewModel.MaintenanceAction,
                              state: PerformanceViewModel.ActionState,
                              successTitle: String,
                              successText: String,
                              failureTitle: String) -> some View {
        switch state {
        case .idle, .running:
            EmptyView()
        case .needsApproval:
            BannerView(
                kind: .info,
                title: "Approve the SOS Mac helper",
                text: "The first run installs a small helper. Turn it on in System Settings › General › Login Items & Extensions, then run again.") {
                Button("Open System Settings") { viewModel.openLoginItemsSettings() }
                    .sosButton(.default)
                    .accessibilityIdentifier("performance-open-login-items")
            }
        case .succeeded:
            BannerView(kind: .ok, title: successTitle, text: successText)
        case .failed(let message):
            BannerView(kind: .err, title: failureTitle, text: message) {
                Button("Try Again") {
                    Task { await viewModel.run(action) }
                }
                .sosButton(.default)
                .accessibilityIdentifier("performance-retry-\(action.rawValue)")
            }
        }
    }
}

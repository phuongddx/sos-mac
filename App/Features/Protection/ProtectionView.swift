import SwiftUI
import SwiftData
import CleanCore

struct ProtectionView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: ProtectionViewModel?

    var body: some View {
        Group {
            if let viewModel {
                ProtectionContentView(viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        .task {
            if viewModel == nil {
                viewModel = ProtectionViewModel(modelContext: modelContext)
            }
        }
        .navigationTitle("Protection")
    }
}

private struct ProtectionContentView: View {
    @Bindable var viewModel: ProtectionViewModel
    @State private var verdictsByPath: [String: VirusTotalVerdict?] = [:]

    var body: some View {
        VStack(spacing: 0) {
            disclaimerBanner

            switch viewModel.phase {
            case .idle:
                EmptyStateView(
                    systemImage: "shield.lefthalf.filled",
                    title: "Scan for known threats",
                    message: "Checks Downloads, login items, and browser extensions against known-bad signatures. Complements — never replaces — XProtect and Gatekeeper.",
                    hue: Theme.hue(for: .protection),
                    actionTitle: "Start Scan",
                    action: { viewModel.startScan() }
                )
                quarantineSection

            case .scanning:
                scanningContent

            case .results, .quarantining:
                resultsList
                footer

            case .summary(let quarantinedCount, let failureCount):
                VStack(spacing: Theme.Spacing.lg) {
                    SummaryCardView(
                        bigNumber: "\(quarantinedCount)",
                        caption: quarantinedCount == 1 ? "item quarantined" : "items quarantined"
                    )
                    if failureCount > 0 {
                        Text("\(failureCount) item\(failureCount == 1 ? "" : "s") couldn't be quarantined.")
                            .font(.system(size: Theme.TextSize.sm))
                            .foregroundStyle(Theme.danger)
                    }
                    Button("New Scan") { viewModel.startNewScan() }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(Theme.Spacing.xxxl)
                quarantineSection
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.system(size: Theme.TextSize.sm))
                    .foregroundStyle(Theme.danger)
                    .padding()
            }
        }
        .background(Theme.background)
        .auroraBloom()
        .onDisappear { viewModel.cancelScan() }
    }

    /// `ProtectionScanner` pre-counts every file across all six allowlist
    /// locations before the first `onProgress` fires, so the panel has nothing
    /// to draw for that whole window — show the same counting fallback Space
    /// Lens uses rather than an empty screen, and keep Cancel reachable
    /// throughout (the pre-count honors cancellation too).
    private var scanningContent: some View {
        VStack(spacing: Theme.Spacing.lg) {
            ProgressView()
                .controlSize(.large)
                .tint(Theme.accent)
            if let progress = viewModel.progressTracker.progress {
                ScanProgressPanel(
                    progress: progress,
                    ticker: "\(progress.itemsProcessed.formatted()) files scanned",
                    etaText: viewModel.progressTracker.estimatedTimeRemainingText,
                    showCurrentPath: true,
                    countOnlyLabel: { "Scanned \($0.formatted()) files…" }
                )
                .frame(maxWidth: 480)
            } else {
                Text("Counting files…")
                    .font(.system(size: Theme.TextSize.sm))
                    .foregroundStyle(Theme.muted)
            }
            Button("Cancel") { viewModel.cancelScan() }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var disclaimerBanner: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "info.circle")
                .foregroundStyle(Theme.muted)
            Text("Signature-based scanning only — complements XProtect/Gatekeeper, does not replace them. Real-time protection is not part of this release.")
                .font(.system(size: Theme.TextSize.xs))
                .foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.sm)
    }

    private var resultsList: some View {
        List {
            if viewModel.findings.isEmpty {
                Text("No threats found.").foregroundStyle(Theme.muted)
            }
            ForEach(viewModel.findings) { finding in
                findingRow(finding)
                    .listRowBackground(Theme.surface)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
    }

    private func findingRow(_ finding: ThreatFinding) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Toggle(isOn: Binding(
                get: { viewModel.selectedPaths.contains(finding.path) },
                set: { _ in viewModel.toggleSelection(for: finding.path) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text((finding.path as NSString).lastPathComponent)
                        .font(.system(size: Theme.TextSize.sm, weight: .medium))
                        .foregroundStyle(Theme.foreground)
                    HStack(spacing: Theme.Spacing.sm) {
                        BadgeView(text: badgeText(for: finding.detectionMethod), style: .risk)
                        if let verdict = verdictsByPath[finding.path] ?? nil {
                            BadgeView(
                                text: verdict.isFlagged ? "VT: \(verdict.maliciousCount)/\(verdict.totalEngines)" : "VT: clean",
                                style: verdict.isFlagged ? .risk : .safe
                            )
                        }
                    }
                }
            }
            .toggleStyle(.checkbox)

            Spacer(minLength: 0)

            Text(ByteFormatter.string(fromByteCount: finding.size))
                .font(.system(size: Theme.TextSize.sm))
                .foregroundStyle(Theme.muted)
                .monospacedDigit()

            if finding.detectionMethod == .hash {
                Button("Check VirusTotal") {
                    Task {
                        verdictsByPath[finding.path] = await viewModel.lookupVirusTotal(for: finding)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    private func badgeText(for method: DetectionMethod) -> String {
        switch method {
        case .hash: return "Known signature"
        case .yara: return "Pattern match"
        }
    }

    private var footer: some View {
        StickyFooterView(
            totalLabel: "Selected",
            totalValue: "\(viewModel.selectedPaths.count)"
        ) {
            Button("Quarantine Selected", role: .destructive) {
                Task { await viewModel.quarantineSelected() }
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.danger)
            .disabled(viewModel.selectedPaths.isEmpty || viewModel.phase == .quarantining)
        }
    }

    @ViewBuilder
    private var quarantineSection: some View {
        if !viewModel.quarantinedRecords.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Quarantined (\(viewModel.quarantinedRecords.count))")
                    .font(.system(size: Theme.TextSize.sm, weight: .semibold))
                    .foregroundStyle(Theme.foreground)
                    .padding(.horizontal, Theme.Spacing.lg)

                ForEach(viewModel.quarantinedRecords) { record in
                    HStack {
                        Text((record.originalPath as NSString).lastPathComponent)
                            .font(.system(size: Theme.TextSize.sm))
                            .foregroundStyle(Theme.foreground)
                        Spacer()
                        Button("Restore") { viewModel.restore(record) }
                            .buttonStyle(.plain)
                            .foregroundStyle(Theme.accent)
                    }
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.vertical, Theme.Spacing.xs)
                }
            }
            .padding(.vertical, Theme.Spacing.md)
        }
    }
}

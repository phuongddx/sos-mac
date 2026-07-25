import SwiftUI
import CleanCore

struct SpaceLensView: View {
    @State private var viewModel = SpaceLensViewModel()

    var body: some View {
        VStack(spacing: 0) {
            header

            if viewModel.phase == .loaded {
                breadcrumbBar
                Picker("View Mode", selection: $viewModel.viewMode) {
                    ForEach(SpaceLensViewModel.ViewMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Theme.Spacing.xxxl)
                .padding(.bottom, Theme.Spacing.sm)
            }

            content

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.system(size: Theme.TextSize.sm))
                    .foregroundStyle(Theme.danger)
                    .padding(Theme.Spacing.lg)
            }
        }
        .background(Theme.background)
        .navigationTitle("Space Lens")
        .onDisappear { viewModel.cancelScan() }
    }

    /// Mirrors the mockup's `content-header` (title + one-line meta). The mockup's
    /// meta line ("99.2 GB mapped · Last scanned today at 9:42 AM") isn't shown
    /// here: the ViewModel doesn't track a last-scan timestamp, and the mapped
    /// total isn't exposed outside the sized-for-canvas `layoutRects(in:)` call,
    /// so that number is omitted rather than hardcoded.
    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Space Lens")
                .font(.system(size: Theme.TextSize.xl, weight: .semibold))
                .foregroundStyle(Theme.foreground)
            Text(headerSubtitle)
                .font(.system(size: Theme.TextSize.sm))
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.xxxl)
        .padding(.top, Theme.Spacing.xxxl)
        .padding(.bottom, Theme.Spacing.lg)
    }

    private var headerSubtitle: String {
        switch viewModel.phase {
        case .idle:
            return "Visualize disk usage as a treemap."
        case .scanning:
            return "Scanning \((viewModel.rootPath as NSString).lastPathComponent)…"
        case .loaded:
            return "Tap a folder to zoom in, or switch to By Type for a category breakdown."
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .idle:
            EmptyStateView(
                systemImage: "square.grid.3x3.fill",
                title: "No scan yet",
                message: "Map disk usage under \((viewModel.rootPath as NSString).lastPathComponent) as a treemap of folders and files.",
                actionTitle: "Scan \((viewModel.rootPath as NSString).lastPathComponent)",
                action: { viewModel.startScan() }
            )

        case .scanning:
            VStack(spacing: Theme.Spacing.lg) {
                ProgressView()
                    .controlSize(.large)
                    .tint(Theme.accent)
                Text("Scanning…")
                    .font(.system(size: Theme.TextSize.sm))
                    .foregroundStyle(Theme.muted)
                Button("Cancel") { viewModel.cancelScan() }
                    .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .loaded:
            GeometryReader { geo in
                let isCategoryMode = viewModel.viewMode == .category
                let legendHeight: CGFloat = isCategoryMode ? 28 : 0
                let treemapRect = CGRect(
                    x: 0, y: 0,
                    width: geo.size.width,
                    height: max(0, geo.size.height - legendHeight)
                )
                let items = viewModel.layoutRects(in: treemapRect)

                VStack(alignment: .leading, spacing: 0) {
                    if isCategoryMode, !items.isEmpty {
                        legend(for: items)
                            .frame(height: legendHeight)
                    }
                    TreemapCanvasView(items: items) { item in
                        viewModel.handleTap(on: item)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            }
            .padding(.horizontal, Theme.Spacing.xxxl)
            .padding(.bottom, Theme.Spacing.xxxl)
        }
    }

    private var breadcrumbBar: some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(Array(viewModel.breadcrumbLabels.enumerated()), id: \.offset) { index, label in
                Button(label) { viewModel.zoomOut(to: index) }
                    .buttonStyle(.plain)
                    .font(.system(
                        size: Theme.TextSize.sm,
                        weight: index == viewModel.breadcrumbLabels.count - 1 ? .semibold : .regular
                    ))
                    .foregroundStyle(index == viewModel.breadcrumbLabels.count - 1 ? Theme.foreground : Theme.muted)
                if index < viewModel.breadcrumbLabels.count - 1 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.border)
                }
            }
            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.xxxl)
        .padding(.bottom, Theme.Spacing.sm)
    }

    /// Category-mode legend, styled after the mockup's `.lens-legend` swatch row.
    /// No side inspector panel is included (unlike the mockup's `.lens-inspector`):
    /// the ViewModel tracks no "selected item" and `DisplayItem` carries no
    /// modified-date/item-count/path fields, so there's no real data to back one
    /// without changing SpaceLensViewModel, which is out of scope here.
    private func legend(for items: [SpaceLensViewModel.DisplayItem]) -> some View {
        HStack(spacing: Theme.Spacing.lg) {
            ForEach(items) { item in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Self.legendColor(forLabel: item.label))
                        .frame(width: 9, height: 9)
                    Text(item.label)
                        .font(.system(size: Theme.TextSize.xs))
                        .foregroundStyle(Theme.muted)
                }
            }
            Spacer()
        }
    }

    /// Reproduces TreemapCanvasView's per-label hash so legend swatches match the
    /// canvas exactly (in category mode, `item.label` is the same category name
    /// the canvas hashes on) — without importing or modifying TreemapCanvasView.
    private static func legendColor(forLabel label: String) -> Color {
        var hasher = Hasher()
        hasher.combine(label)
        let hue = Double(abs(hasher.finalize()) % 360) / 360.0
        return Color(hue: hue, saturation: 0.55, brightness: 0.75)
    }
}

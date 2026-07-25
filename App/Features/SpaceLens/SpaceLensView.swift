import SwiftUI
import CleanCore

struct SpaceLensView: View {
    @State private var viewModel = SpaceLensViewModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            content

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.system(size: Theme.TextSize.sm))
                    .foregroundStyle(Theme.danger)
                    .padding(Theme.Spacing.lg)
            }
        }
        .background(Theme.background)
        .auroraBloom()
        .navigationTitle("Space Lens")
        .onDisappear { viewModel.cancelScan() }
        .sheet(isPresented: reviewPresented) {
            cleanupReview
        }
    }

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
            return "Choose a location to visualize its disk usage."
        case .scanning:
            return "Scanning \((viewModel.rootPath as NSString).lastPathComponent)…"
        case .loaded, .reviewing, .cleaning:
            return "Select an item to inspect it, then review anything you want to move to Trash."
        case .done(let reclaimedBytes):
            return "Moved \(ByteFormatter.string(fromByteCount: reclaimedBytes)) to Trash."
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .idle:
            sourcePicker
        case .scanning:
            scanningContent
        case .loaded, .reviewing, .cleaning:
            mappedContent
        case .done(let reclaimedBytes):
            VStack(spacing: Theme.Spacing.lg) {
                SummaryCardView(
                    bigNumber: ByteFormatter.string(fromByteCount: reclaimedBytes),
                    caption: "moved to Trash"
                )
                Button("Scan Again") { viewModel.scanAgain() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(Theme.Spacing.xxxl)
        }
    }

    private var sourcePicker: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Image(systemName: "square.grid.3x3.fill")
                .font(.system(size: 34))
                .foregroundStyle(Theme.hue(for: .spaceLens))
            Text("Map your storage")
                .font(.system(size: Theme.TextSize.lg, weight: .semibold))
                .foregroundStyle(Theme.foreground)
            Text("Choose the part of your Mac you want to explore. Nothing is removed without your review.")
                .font(.system(size: Theme.TextSize.sm))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 430)
            HStack(spacing: Theme.Spacing.md) {
                Button("Scan Home Folder") { viewModel.selectHomeFolder() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                Button("Choose Folder…") { viewModel.chooseFolder() }
                    .buttonStyle(.bordered)
            }

            if !viewModel.externalVolumes.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("External Volumes")
                        .font(.system(size: Theme.TextSize.sm, weight: .semibold))
                        .foregroundStyle(Theme.foreground)
                    ForEach(viewModel.externalVolumes) { volume in
                        Button(volume.name) { viewModel.selectVolume(at: volume.url) }
                            .buttonStyle(.bordered)
                    }
                }
                .frame(maxWidth: 430, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Spacing.xxxl)
    }

    private var scanningContent: some View {
        VStack(spacing: Theme.Spacing.lg) {
            ProgressView()
                .controlSize(.large)
                .tint(Theme.accent)
            Text(viewModel.scannedItemCount > 0 ? "Scanned \(viewModel.scannedItemCount.formatted()) items…" : "Scanning…")
                .font(.system(size: Theme.TextSize.sm))
                .foregroundStyle(Theme.muted)
            Button("Cancel") { viewModel.cancelScan() }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var mappedContent: some View {
        VStack(spacing: 0) {
            breadcrumbBar
            Picker("View Mode", selection: $viewModel.viewMode) {
                ForEach(SpaceLensViewModel.ViewMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Theme.Spacing.xxxl)
            .padding(.bottom, Theme.Spacing.sm)

            GeometryReader { geo in
                let inspectorWidth: CGFloat = viewModel.selectedItem == nil ? 0 : min(290, max(230, geo.size.width * 0.28))
                let canvasRect = CGRect(x: 0, y: 0, width: max(0, geo.size.width - inspectorWidth), height: geo.size.height)
                let items = viewModel.layoutRects(in: canvasRect)

                HStack(spacing: Theme.Spacing.md) {
                    TreemapCanvasView(items: items) { item in
                        viewModel.handleTap(on: item)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))

                    if let item = viewModel.selectedItem {
                        inspector(for: item)
                            .frame(width: inspectorWidth)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.xxxl)
            .padding(.bottom, Theme.Spacing.md)

            if !viewModel.cleanupItems.isEmpty {
                StickyFooterView(
                    totalLabel: "Cleanup selection",
                    totalValue: "\(viewModel.cleanupItems.count) items · \(ByteFormatter.string(fromByteCount: viewModel.totalSelectedBytes))"
                ) {
                    Button("Review Cleanup") { viewModel.beginCleanupReview() }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                        .disabled(viewModel.phase == .cleaning)
                }
            }
        }
    }

    private var breadcrumbBar: some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(Array(viewModel.breadcrumbLabels.enumerated()), id: \.offset) { index, label in
                Button(label) { viewModel.zoomOut(to: index) }
                    .buttonStyle(.plain)
                    .font(.system(size: Theme.TextSize.sm, weight: index == viewModel.breadcrumbLabels.count - 1 ? .semibold : .regular))
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

    private func inspector(for item: SpaceLensViewModel.DisplayItem) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("Inspector")
                    .font(.system(size: Theme.TextSize.sm, weight: .semibold))
                Spacer()
                Button { viewModel.clearSelectedItem() } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.muted)
            }
            Text(item.label)
                .font(.system(size: Theme.TextSize.base, weight: .semibold))
                .foregroundStyle(Theme.foreground)
                .lineLimit(2)
            Group {
                detailRow("Size", ByteFormatter.string(fromByteCount: item.size))
                detailRow("Kind", item.isDirectory ? "Folder" : "File")
                if item.isDirectory { detailRow("Contains", "\(item.descendantCount) items") }
                if let lastModified = item.lastModified {
                    detailRow("Modified", lastModified.formatted(date: .abbreviated, time: .shortened))
                }
            }
            if let path = item.path {
                Text(path)
                    .font(.system(size: Theme.TextSize.xs, design: .monospaced))
                    .foregroundStyle(Theme.muted)
                    .textSelection(.enabled)
                    .lineLimit(3)
            }
            Spacer(minLength: 0)
            if item.isDirectory {
                Button("Open Folder") { viewModel.openSelectedFolder() }
                    .buttonStyle(.bordered)
            }
            eligibilityAction
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
        .elevation(.raised)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: Theme.TextSize.xs))
                .foregroundStyle(Theme.muted)
            Spacer()
            Text(value)
                .font(.system(size: Theme.TextSize.xs, weight: .medium))
                .foregroundStyle(Theme.foreground)
                .multilineTextAlignment(.trailing)
        }
    }

    @ViewBuilder
    private var eligibilityAction: some View {
        switch viewModel.selectedItemEligibility {
        case .eligible:
            Button(viewModel.isSelectedItemInCleanup ? "Remove from Cleanup" : "Add to Cleanup") {
                viewModel.toggleSelectedItemCleanup()
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
        case .ineligible(let reason):
            Text(reason)
                .font(.system(size: Theme.TextSize.xs))
                .foregroundStyle(Theme.muted)
        case nil:
            EmptyView()
        }
    }

    private var cleanupReview: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text("Review Cleanup")
                .font(.system(size: Theme.TextSize.xl, weight: .semibold))
            Text("These items will be moved to Trash and can be recovered from Finder until Trash is emptied.")
                .font(.system(size: Theme.TextSize.sm))
                .foregroundStyle(Theme.muted)
            List(viewModel.cleanupItems) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text((item.path as NSString).lastPathComponent)
                        Text(item.path)
                            .font(.system(size: Theme.TextSize.xs))
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(ByteFormatter.string(fromByteCount: item.size))
                        .foregroundStyle(Theme.muted)
                }
            }
            HStack {
                Text("Total")
                    .font(.system(size: Theme.TextSize.sm, weight: .semibold))
                Spacer()
                Text(ByteFormatter.string(fromByteCount: viewModel.totalSelectedBytes))
                    .font(.system(size: Theme.TextSize.base, weight: .semibold))
            }
            HStack {
                Button("Cancel") { viewModel.cancelCleanupReview() }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Move to Trash") {
                    Task { await viewModel.cleanSelectedItems() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.danger)
            }
        }
        .padding(Theme.Spacing.xxxl)
        .frame(minWidth: 520, minHeight: 420)
    }

    private var reviewPresented: Binding<Bool> {
        Binding(
            get: { viewModel.phase == .reviewing },
            set: { isPresented in if !isPresented { viewModel.cancelCleanupReview() } }
        )
    }
}

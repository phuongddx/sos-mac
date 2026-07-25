import SwiftUI
import CleanCore

struct SpaceLensView: View {
    @State private var viewModel = SpaceLensViewModel()

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.phase == .loaded {
                breadcrumbBar
                Picker("View Mode", selection: $viewModel.viewMode) {
                    ForEach(SpaceLensViewModel.ViewMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            content

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage).foregroundStyle(.red).padding()
            }
        }
        .navigationTitle("Space Lens")
        .onDisappear { viewModel.cancelScan() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .idle:
            ContentUnavailableView(
                "Space Lens",
                systemImage: "square.grid.3x3.fill",
                description: Text("Visualize disk usage as a treemap.")
            )
            Button("Scan \((viewModel.rootPath as NSString).lastPathComponent)") {
                viewModel.startScan()
            }
            .padding()

        case .scanning:
            ProgressView("Scanning…")
                .padding()
            Button("Cancel") { viewModel.cancelScan() }

        case .loaded:
            GeometryReader { geo in
                let containerRect = CGRect(origin: .zero, size: geo.size)
                TreemapCanvasView(items: viewModel.layoutRects(in: containerRect)) { item in
                    viewModel.handleTap(on: item)
                }
            }
        }
    }

    private var breadcrumbBar: some View {
        HStack(spacing: 4) {
            ForEach(Array(viewModel.breadcrumbLabels.enumerated()), id: \.offset) { index, label in
                Button(label) { viewModel.zoomOut(to: index) }
                    .buttonStyle(.plain)
                    .foregroundStyle(index == viewModel.breadcrumbLabels.count - 1 ? .primary : .secondary)
                if index < viewModel.breadcrumbLabels.count - 1 {
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }
}

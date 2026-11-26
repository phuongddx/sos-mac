import SwiftUI
import CleanCore

/// The Space Lens inspector column (spec §5.5) — always visible beside the map, in
/// the review frame's column material. One branch per selection kind: nothing
/// selected shows the current level; a By Type cell shows its aggregate; the "N
/// smaller items" cell explains the merge; a real item shows its detail rows, the
/// drill action and the cleanup action — or the reason it can't be cleaned.
/// Every variant ends with the cleanup list, so the cart is visible before the sheet.
struct SpaceLensInspector: View {
    let viewModel: SpaceLensViewModel
    @Environment(\.self) private var environment

    var body: some View {
        ReviewDetailView(title: title) {
            detailRows
            actionRows
            cartRows
        }
    }

    // MARK: - Title and detail rows

    private var title: String {
        if let item = viewModel.selectedItem {
            return item.label
        }
        switch viewModel.viewMode {
        case .tree: return viewModel.breadcrumbLabels.last ?? viewModel.rootName
        case .category: return "All file types"
        }
    }

    @ViewBuilder
    private var detailRows: some View {
        switch viewModel.selectedItem {
        case .some(let item) where item.isSmallerBucket:
            ReviewDetailView.KeyRow(label: "Size", value: sizeText(item.size))
            ReviewDetailView.Explanation(
                leadIn: "Too small to draw.",
                text: "Open the folder in Finder to see them.")

        case .some(let item) where item.isCategory:
            ReviewDetailView.KeyRow(label: "Size", value: sizeText(item.size))
            ReviewDetailView.Explanation(
                leadIn: "By Type shows totals only.",
                text: "Switch to By Folder to pick files to clean.")

        case .some(let item):
            ReviewDetailView.KeyRow(label: "Size", value: sizeText(item.size))
            ReviewDetailView.KeyRow(label: "Kind", value: item.isDirectory ? "Folder" : "File")
            if item.isDirectory {
                ReviewDetailView.KeyRow(label: "Contains", value: "\(item.descendantCount) item\(item.descendantCount == 1 ? "" : "s")")
            }
            if let modified = item.lastModified {
                ReviewDetailView.KeyRow(label: "Modified", value: modified.formatted(date: .abbreviated, time: .shortened))
            }
            if let path = item.path {
                ReviewDetailView.PathRow(label: "Path", value: path)
            }

        case .none:
            ReviewDetailView.KeyRow(label: "Size", value: sizeText(viewModel.levelTotalBytes))
            if viewModel.viewMode == .tree {
                ReviewDetailView.PathRow(label: "Path", value: viewModel.rootPath)
            }
            ReviewDetailView.Explanation(
                leadIn: "Select a rectangle to see what it is.",
                text: "Double-click a folder to open it.")
        }
    }

    // MARK: - Actions

    @ViewBuilder
    private var actionRows: some View {
        if let item = viewModel.selectedItem, !item.isSmallerBucket, !item.isCategory {
            ReviewDetailView.FreeRow {
                VStack(alignment: .leading, spacing: Theme.Spacing.s2) {
                    if item.isDirectory {
                        Button("Show Contents", action: viewModel.drillIntoSelectedItem)
                            .sosButton(.default)
                            .accessibilityIdentifier("spacelens-show-contents")
                    }
                    cleanupAction
                }
                .padding(.top, Theme.Spacing.s3)
            }
        }
    }

    /// Priority order (§5.5): the engine's own ineligibility reason first, then the
    /// protected-location explanation for the root's top-level Library folder, and
    /// the add/remove action only when the policy calls the item eligible.
    @ViewBuilder
    private var cleanupAction: some View {
        switch viewModel.selectedItemEligibility {
        case .ineligible(let reason):
            Text(reason)
                .font(Theme.Font.callout)
                .foregroundStyle(Theme.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        case .eligible:
            if let path = viewModel.selectedItem?.path,
               SpaceLensViewModel.isProtectedLocation(path, scanRootPath: viewModel.rootPath) {
                ReviewDetailView.Explanation(
                    leadIn: "Can't be cleaned here.",
                    text: "Library holds settings and data that apps need. Use Junk & Cache or Uninstaller for files inside it.")
                    .padding(.top, Theme.Spacing.s1)
            } else {
                Button(viewModel.isSelectedItemInCleanup ? "Remove from Cleanup" : "Add to Cleanup") {
                    viewModel.toggleSelectedItemCleanup()
                }
                .sosButton(viewModel.isSelectedItemInCleanup ? .default : .prominent)
                .accessibilityIdentifier("spacelens-toggle-cleanup")
            }
        case .none:
            EmptyView()
        }
    }

    // MARK: - Cleanup list (the cart, visible in every inspector variant)

    @ViewBuilder
    private var cartRows: some View {
        ReviewDetailView.FreeRow {
            VStack(alignment: .leading, spacing: Theme.Spacing.s2) {
                Text("CLEANUP LIST")
                    .font(Theme.Font.subheadline.weight(.semibold))
                    .tracking(0.48)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .padding(.top, Theme.Spacing.s4)
                if viewModel.cleanupItems.isEmpty {
                    Text("Nothing added yet. Select a file or folder, then Add to Cleanup.")
                        .font(Theme.Font.callout)
                        .foregroundStyle(Theme.Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(viewModel.cleanupItems) { item in
                        HStack(spacing: Theme.Spacing.s2) {
                            Text((item.path as NSString).lastPathComponent)
                                .font(Theme.Font.callout)
                                .foregroundStyle(Theme.Color.textPrimary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(ConfirmItemList.sizeText(for: item.size))
                                .font(Theme.Font.callout)
                                .foregroundStyle(Theme.Color.textSecondary)
                                .monospacedDigit()
                                .fixedSize()
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private func sizeText(_ bytes: Int64) -> String {
        ByteFormatter.string(fromByteCount: bytes)
    }
}

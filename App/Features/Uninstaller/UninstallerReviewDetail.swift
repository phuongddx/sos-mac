import SwiftUI
import AppKit
import CleanCore

/// The app panel of the two-column review (spec §5.7): the app's icon (OD-12), name and
/// version, how it was installed, and the totals of the reviewed selection. It sits on the
/// groups column — Uninstaller has one app, not a list of groups, and `ReviewFrameView`'s
/// groups column is a fixed-width list of group rows.
struct UninstallerAppPanel: View {
    let app: InstalledApp
    let icon: NSImage?
    let itemCount: Int
    let selectedCount: Int
    let sizeText: String
    let unmeasuredFolderCount: Int
    let isRunning: Bool

    @Environment(\.self) private var environment

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            UninstallerAppIcon(app: app, icon: icon, side: 56)
            Text(app.name)
                .font(Theme.Font.title3)
                .foregroundStyle(Theme.Color.textPrimary)
                .lineLimit(2)
                .padding(.top, Theme.Spacing.s3)
            if let version = app.version {
                Text("Version \(version)")
                    .font(Theme.Font.subheadline)
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            HStack(spacing: Theme.Spacing.s2) {
                if app.isAppStoreDistributed {
                    BadgeView(text: "App Store", style: .accent)
                }
                if isRunning {
                    BadgeView(text: "Running", style: .caution, systemImage: "bolt.fill")
                }
            }
            .padding(.top, Theme.Spacing.s2)

            panelRow("Selected", "\(selectedCount) of \(itemCount) items")
            panelRow("Size", sizeText)
            if unmeasuredFolderCount > 0 {
                Text("\(unmeasuredFolderCount) \(unmeasuredFolderCount == 1 ? "folder" : "folders") not measured yet.")
                    .font(Theme.Font.callout)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Theme.Spacing.s2)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: 18, leading: 16, bottom: 18, trailing: 16))
        .frame(width: ReviewFrameView.groupsColumnWidth)
        .frame(maxHeight: .infinity)
        .background(ColorMix.mix(Theme.Color.bgBase, Theme.Color.card, fraction: 0.60, in: environment))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("uninstaller-app-panel")
    }

    private func panelRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s1) {
            Text(label.uppercased())
                .font(Theme.Font.subheadline.weight(.semibold))
                .tracking(ReviewDetailView.KeyRow.labelTracking)
                .foregroundStyle(Theme.Color.textSecondary)
            Text(value)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, ReviewDetailView.KeyRow.labelTopSpacing)
        .accessibilityElement(children: .combine)
    }
}

/// OD-12: the app's real icon when its bundle is on disk, else a letter tile in the module
/// hue (also what the fictional fixture apps get).
struct UninstallerAppIcon: View {
    let app: InstalledApp
    let icon: NSImage?
    let side: CGFloat

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                let shape = RoundedRectangle(cornerRadius: side * 0.24, style: .continuous)
                ZStack {
                    shape.fill(LinearGradient(colors: [Theme.Hue.uninstaller, Theme.Hue.uninstaller.opacity(0.72)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing))
                    Text(String(app.name.prefix(1)).uppercased())
                        .font(.system(size: side * 0.44, weight: .bold))
                        .foregroundStyle(Theme.Color.onPrimary)
                }
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}

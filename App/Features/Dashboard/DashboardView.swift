import SwiftUI
import CleanCore

/// The Dashboard (spec §5.1, prototype `?screen=dashboard`): a launcher with no lifecycle.
///
/// - **Hero** — the Smart Care orb, title and "Run Smart Care", which opens Smart Care **and
///   starts the scan** (N3, `DashboardLauncher.runSmartCare`). On the right the boot volume's
///   real storage numbers and "Open Space Lens".
/// - **Snapshot** — load average, memory in use and thermal state, each captioned
///   "Read when this page opened": one reading taken when the page appeared, never polled.
/// - **Two module-card sections** — Clean, and Manage · Speed · Protect.
///
/// Deviations from the prototype, all "fail closed" (spec §11.5, D6): a value the system did not
/// report is left out (a missing volume drops the right column; a missing reading drops its
/// tile) instead of showing a placeholder; there is no health dial, "last scanned" stamp or
/// per-module status, because none has a real source.
///
/// `DashboardView(onSelect:)` keeps the signature `RootView` already calls.
struct DashboardView: View {
    let onSelect: @MainActor (SidebarDestination) -> Void

    @Environment(ModuleStore.self) private var store
    @State private var storage: VolumeStorageInfo?
    @State private var snapshot: DashboardSnapshot

    init(onSelect: @escaping @MainActor (SidebarDestination) -> Void) {
        self.onSelect = onSelect
        // Both are read once, when the page opens (the prototype's "Read when this page opened").
        var storage = VolumeStorageInfo.current()
        var snapshot = DashboardSnapshot.capture()
#if DEBUG
        if UITestHooks.current.fixtures {
            storage = .fixture
            snapshot = .fixture
        }
#endif
        _storage = State(initialValue: storage)
        _snapshot = State(initialValue: snapshot)
    }

    /// The prototype's `.dash` padding: 4 pt top, 32 pt sides and bottom.
    private static let contentPadding = EdgeInsets(top: 4, leading: 32, bottom: 32, trailing: 32)
    /// The hero's right column (prototype `grid-template-columns: 1fr 300px`).
    private static let storageColumnWidth: CGFloat = 300
    private static let orbMetrics = ModuleOrbView.Metrics(side: 112, glyphSide: 68, glyphRadius: 18, symbolSize: 34, ringInset: 10)

    private var launcher: DashboardLauncher {
        DashboardLauncher(smartCare: { store.smartCare }, navigate: onSelect)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero
                if !snapshot.isEmpty {
                    snapshotRow.padding(.top, 14)
                }
                DashboardModuleSection(title: "Clean", entries: cleanEntries, open: launcher.open)
                    .padding(.top, Theme.Spacing.s6)
                DashboardModuleSection(title: "Manage · Speed · Protect", entries: manageEntries, open: launcher.open)
                    .padding(.top, Theme.Spacing.s5)
            }
            .padding(Self.contentPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .auroraBackground(hue: Theme.Hue.smartcare)
        .background(Theme.Color.bgBase)
        .accessibilityIdentifier("dashboard-screen")
    }

    // MARK: Hero

    private var hero: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous)
        return HStack(spacing: 0) {
            heroLead
            if let storage {
                Rectangle().fill(Theme.Derived.hairline).frame(width: 1)
                storageColumn(storage)
                    .frame(width: Self.storageColumnWidth)
            }
        }
        .background { heroWash }
        .auroraSurface(cornerRadius: Theme.Radius.xl)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Theme.Derived.hairline, lineWidth: 1))
        .elevation(.raised)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dashboard-hero")
    }

    /// The prototype's `.dash-hero::before`: the aurora gradient at 1.1 × the aurora alpha.
    private var heroWash: some View {
        HeroWash()
    }

    private var heroLead: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.s6) {
            ModuleOrbView(hue: Theme.Hue.smartcare, symbol: SidebarDestination.smartCare.systemImage,
                          metrics: Self.orbMetrics)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Circle().fill(Theme.Color.primary).frame(width: 6, height: 6)
                    Text("SMART CARE")
                }
                .font(Theme.Font.eyebrow)
                .tracking(0.72)
                .foregroundStyle(Theme.Color.textSecondary)
                .accessibilityHidden(true)

                Text("Clean up junk and duplicates in one pass")
                    .font(Theme.Font.title1)
                    .foregroundStyle(Theme.Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Theme.Spacing.s2)
                    .accessibilityAddTraits(.isHeader)

                Text("Smart Care finds caches, old logs and duplicate files, then shows you everything before anything moves.")
                    .font(Theme.Font.callout)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)

                Button {
                    launcher.runSmartCare()
                } label: {
                    Label("Run Smart Care", systemImage: SidebarDestination.smartCare.systemImage)
                }
                .buttonStyle(.sosLarge())
                .padding(.top, Theme.Spacing.s4)
                .accessibilityIdentifier("dashboard-run-smart-care")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Theme.Spacing.s8)
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func storageColumn(_ storage: VolumeStorageInfo) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s2) {
            HStack(alignment: .firstTextBaseline) {
                // The volume's name is left out, not guessed, when the system reports none.
                if let name = storage.volumeName {
                    Text(name)
                        .font(Theme.Font.headline)
                        .foregroundStyle(Theme.Color.textPrimary)
                        .lineLimit(1)
                }
                Spacer(minLength: Theme.Spacing.s2)
                Text("\(storage.freeDescription) free")
                    .font(Theme.Font.callout)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .monospacedDigit()
            }
            StorageMeterView(usedFraction: storage.usedFraction)
                .frame(height: 8)
            HStack {
                Text("\(Text(storage.usedDescription).fontWeight(.semibold).foregroundStyle(Theme.Color.textPrimary)) used")
                Spacer()
                Text("of \(storage.totalDescription)")
            }
            .font(Theme.Font.callout)
            .foregroundStyle(Theme.Color.textSecondary)
            .monospacedDigit()
            Button {
                launcher.open(.spaceLens)
            } label: {
                Label("Open Space Lens", systemImage: SidebarDestination.spaceLens.systemImage)
            }
            .buttonStyle(.sosPlain)
            .padding(.top, 2)
            .accessibilityIdentifier("dashboard-open-space-lens")
        }
        .padding(.horizontal, 26)
        .padding(.vertical, Theme.Spacing.s6)
        .frame(maxHeight: .infinity, alignment: .center)
    }

    // MARK: Snapshot

    private var snapshotRow: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s3) {
            if let load = snapshot.loadText {
                DashboardSnapshotTile(symbol: "cpu", label: "Load average (1 min)", value: load, unit: nil)
            }
            if let inUse = snapshot.memoryInUseText {
                DashboardSnapshotTile(symbol: "memorychip", label: "Memory in use", value: inUse,
                                      unit: snapshot.memoryTotalText.map { "of \($0)" })
            }
            if let thermal = snapshot.thermalText {
                DashboardSnapshotTile(symbol: "thermometer.medium", label: "Thermal state", value: thermal, unit: nil)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dashboard-snapshot")
    }

    // MARK: Module cards

    private var cleanEntries: [DashboardModuleSection.Entry] {
        [
            .init(destination: .junkCleaner, description: "Caches and old logs"),
            .init(destination: .duplicateFinder, description: "Exact copies and similar images"),
            .init(destination: .spaceLens, description: "See what fills your disk"),
            .init(destination: .cloudCleanup, description: "Duplicates in iCloud Drive"),
        ]
    }

    private var manageEntries: [DashboardModuleSection.Entry] {
        [
            .init(destination: .uninstaller, description: "Remove apps and their files"),
            .init(destination: .updater, description: "See which apps have updates"),
            // "Live system metrics" describes the Performance screen (it polls every 2 s); the
            // line under it repeats the snapshot's figures and carries no "live" dot (spec §5.1).
            .init(destination: .performance, description: "Live system metrics", extraLine: snapshot.performanceLine),
            .init(destination: .protection, description: "Known-signature malware scan"),
        ]
    }
}

/// The hero's aurora wash, split out so it can read the colour scheme for its alpha.
private struct HeroWash: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle()
            .fill(Theme.Gradient.aurora)
            .opacity(Theme.Glow.auroraAlpha(isDark: colorScheme == .dark) * 1.1)
            .allowsHitTesting(false)
    }
}

/// One snapshot tile (prototype `.snap .c`): an icon and label, the figure, and the caption
/// "Read when this page opened".
private struct DashboardSnapshotTile: View {
    let symbol: String
    let label: String
    let value: String
    let unit: String?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.md + 2, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            Label {
                Text(label)
            } icon: {
                Image(systemName: symbol)
            }
            .font(Theme.Font.callout)
            .foregroundStyle(Theme.Color.textSecondary)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 17, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Color.textPrimary)
                if let unit {
                    Text(unit)
                        .font(Theme.Font.callout)
                        .foregroundStyle(Theme.Color.textSecondary)
                }
            }
            .padding(.top, 4)

            Text("Read when this page opened")
                .font(Theme.Font.subheadline)
                .foregroundStyle(Theme.Color.textSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, Theme.Spacing.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Color.card, in: shape)
        .overlay(shape.strokeBorder(Theme.Derived.hairline, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue([value, unit, "Read when this page opened"].compactMap { $0 }.joined(separator: ", "))
    }
}

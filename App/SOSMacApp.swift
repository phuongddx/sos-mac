import SwiftUI
import SwiftData

@main
struct SOSMacApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        // First launch only: macOS restores the last frame afterwards (spec §3.1).
        .defaultSize(width: 1200, height: 760)
        // The screen name is drawn once, by the `.principal` toolbar item
        // (`ModuleToolbarModel`); the window keeps it as its title for the Window
        // menu and Mission Control but does not draw it a second time.
        .windowToolbarStyle(.unified(showsTitle: false))
        .modelContainer(for: [IgnoredItem.self, QuarantineRecord.self])
    }
}

enum SidebarDestination: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case smartCare = "Smart Care"
    case junkCleaner = "Junk & Cache"
    case uninstaller = "Uninstaller"
    case updater = "Updater"
    case spaceLens = "Space Lens"
    case duplicateFinder = "Duplicate Finder"
    case performance = "Performance"
    case cloudCleanup = "Cloud Cleanup"
    case protection = "Protection"

    var id: String { rawValue }

    /// Symbols are the prototype's (`docs/redesign/prototype/data.js`), spec §3.2.
    var systemImage: String {
        switch self {
        case .dashboard: return "sparkles"
        case .smartCare: return "wand.and.stars"
        case .junkCleaner: return "trash"
        case .uninstaller: return "xmark.bin"
        case .updater: return "arrow.triangle.2.circlepath"
        case .spaceLens: return "square.grid.3x3"
        case .duplicateFinder: return "doc.on.doc"
        case .performance: return "gauge.with.dots.needle.50percent"
        case .cloudCleanup: return "icloud"
        case .protection: return "checkmark.shield"
        }
    }

    /// Tile fill (spec §2.5). The Dashboard has no hue of its own; it uses Smart Care's.
    var tileHue: Color {
        switch self {
        case .dashboard, .smartCare: return Theme.Hue.smartcare
        case .junkCleaner: return Theme.Hue.junk
        case .uninstaller: return Theme.Hue.uninstaller
        case .updater: return Theme.Hue.updater
        case .spaceLens: return Theme.Hue.spacelens
        case .duplicateFinder: return Theme.Hue.duplicates
        case .performance: return Theme.Hue.performance
        case .cloudCleanup: return Theme.Hue.cloud
        case .protection: return Theme.Hue.protection
        }
    }

    /// Glyph colour on the tile (spec §2.5 `ink`).
    var tileInk: Color {
        switch self {
        case .dashboard, .smartCare: return Theme.Hue.Ink.smartcare
        case .junkCleaner: return Theme.Hue.Ink.junk
        case .uninstaller: return Theme.Hue.Ink.uninstaller
        case .updater: return Theme.Hue.Ink.updater
        case .spaceLens: return Theme.Hue.Ink.spacelens
        case .duplicateFinder: return Theme.Hue.Ink.duplicates
        case .performance: return Theme.Hue.Ink.performance
        case .cloudCleanup: return Theme.Hue.Ink.cloud
        case .protection: return Theme.Hue.Ink.protection
        }
    }
}

/// The sidebar's five groups, top to bottom (spec §3.2; prototype `SOS.ORDER`).
struct SidebarGroup: Identifiable {
    let label: String?
    let destinations: [SidebarDestination]

    var id: String { label ?? "" }

    static let all: [SidebarGroup] = [
        SidebarGroup(label: nil, destinations: [.dashboard, .smartCare]),
        SidebarGroup(label: "Clean", destinations: [.junkCleaner, .duplicateFinder, .spaceLens, .cloudCleanup]),
        SidebarGroup(label: "Manage", destinations: [.uninstaller, .updater]),
        SidebarGroup(label: "Speed", destinations: [.performance]),
        SidebarGroup(label: "Protect", destinations: [.protection]),
    ]
}

struct RootView: View {
    @State private var selection: SidebarDestination? = RootView.initialSelection
    @Environment(\.modelContext) private var modelContext
    @State private var store: ModuleStore?

    private static var initialSelection: SidebarDestination {
        #if DEBUG
        return UITestHooks.current.destination ?? .dashboard
        #else
        return .dashboard
        #endif
    }

    var body: some View {
        Group {
            #if DEBUG
            if UITestHooks.current.showsGallery {
                // Debug-only component gallery (PR 4a): `SOSMAC_UITEST_SCREEN=gallery`.
                ComponentGalleryView()
                    .frame(minWidth: 720, minHeight: 480)
            } else {
                appShell
            }
            #else
            appShell
            #endif
        }
        .uiTestHooks()
        .task {
            // PR 3 (spec §6.6): one store owns every view model for the session,
            // injected through the environment so screens survive navigation.
            if store == nil {
                store = ModuleStore(modelContext: modelContext)
            }
        }
    }

    /// The sidebar and the selected screen.
    @ViewBuilder
    private var appShell: some View {
        if let store {
            NavigationSplitView {
                SidebarView(selection: $selection)
                    .navigationSplitViewColumnWidth(min: 200, ideal: 240)
            } detail: {
                detail
                    .moduleToolbar(.shell(for: selection ?? .dashboard))
            }
            .environment(store)
            .frame(minWidth: 960, minHeight: 600)  // OD-5
            .uiTestHooks()
        } else {
            ProgressView()
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .dashboard, nil:
            DashboardView(onSelect: { selection = $0 })
        case .smartCare:
            SmartCareView()
        case .junkCleaner:
            JunkCleanerView()
        case .uninstaller:
            UninstallerView()
        case .updater:
            UpdaterView()
        case .spaceLens:
            SpaceLensView()
        case .duplicateFinder:
            DuplicateFinderView()
        case .performance:
            PerformanceView()
        case .cloudCleanup:
            CloudCleanupView()
        case .protection:
            ProtectionView()
        }
    }
}

private extension View {
    /// Debug-only `SOSMAC_UITEST_*` overrides (see `UITestHooks`). In Release, and in a
    /// Debug launch with no variables, this changes nothing.
    @ViewBuilder
    func uiTestHooks() -> some View {
        #if DEBUG
        let hooks = UITestHooks.current
        self
            .preferredColorScheme(hooks.colorScheme)
            .environment(\.uiTestReduceTransparency, hooks.reduceTransparency)
            .background { if let size = hooks.windowSize { UITestWindowSizer(size: size) } }
        #else
        self
        #endif
    }
}

/// The sidebar (spec §3.2): five groups of hue-tiled rows and a storage footer.
///
/// No custom background (spec §7): the `NavigationSplitView` sidebar column already
/// gets the system sidebar material — Liquid Glass on macOS 26+, the sidebar
/// visual-effect material on 14–15, and a solid fill when the user turns on
/// Reduce Transparency. Settings is deliberately absent (no screen yet).
private struct SidebarView: View {
    @Binding var selection: SidebarDestination?
    @Environment(ModuleStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(SidebarGroup.all.enumerated()), id: \.element.id) { index, group in
                    VStack(alignment: .leading, spacing: 0) {
                        if let label = group.label {
                            SidebarSectionLabel(text: label)
                        }
                        ForEach(group.destinations) { row($0) }
                    }
                    .padding(.top, index == 0 ? 2 : 14)  // .nav-group margins
                }
            }
            .padding(.top, 6)
            .padding(.horizontal, Theme.Spacing.s3 - 2)
            .padding(.bottom, Theme.Spacing.s3 - 2)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom, spacing: 0) { SidebarFooterView() }
        .accessibilityLabel("Modules")
    }

    private func row(_ destination: SidebarDestination) -> some View {
        Button {
            selection = destination
        } label: {
            SidebarNavRow(
                title: destination.rawValue,
                systemImage: destination.systemImage,
                hue: destination.tileHue,
                ink: destination.tileInk,
                isActive: selection == destination,
                isScanning: store.isScanning(destination)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == destination ? .isSelected : [])
        .accessibilityIdentifier("sidebar-nav-\(destination.rawValue)")
    }
}

/// Footer (spec §3.2): volume name + "«free» free", a 4 pt meter, "«used» of
/// «total» used". Real boot-volume numbers, read on appearance; the row is left out
/// entirely when the system gives no numbers, and the name when it gives no name.
private struct SidebarFooterView: View {
    @State private var storage: VolumeStorageInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let storage {
                HStack(alignment: .firstTextBaseline) {
                    if let name = storage.volumeName {
                        Text(name)
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.Color.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: Theme.Spacing.s2)
                    Text("\(storage.freeDescription) free")
                        .foregroundStyle(Theme.Color.textSecondary)
                        .fixedSize()
                }
                StorageMeterView(usedFraction: storage.usedFraction)
                Text("\(storage.usedDescription) of \(storage.totalDescription) used")
                    .foregroundStyle(Theme.Color.textSecondary)
            }
        }
        .font(Theme.Font.subheadline)
        .monospacedDigit()
        .padding(EdgeInsets(top: Theme.Spacing.s3, leading: 18, bottom: Theme.Spacing.s4, trailing: 18))
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.Derived.hairline).frame(height: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("sidebar-storage")
        .onAppear { storage = Self.read() }
    }

    private static func read() -> VolumeStorageInfo? {
        #if DEBUG
        if UITestHooks.current.fixtures { return .fixture }
        #endif
        return VolumeStorageInfo.current()
    }
}

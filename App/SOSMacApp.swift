import SwiftUI
import SwiftData

@main
struct SOSMacApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [IgnoredItem.self, QuarantineRecord.self])
    }
}

enum SidebarDestination: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case smartCare = "Smart Care"
    case junkCleaner = "Junk & Cache Scanner"
    case uninstaller = "Uninstaller"
    case updater = "Updater"
    case spaceLens = "Space Lens"
    case duplicateFinder = "Duplicate Finder"
    case performance = "Performance"
    case cloudCleanup = "Cloud Cleanup"
    case protection = "Protection"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .dashboard: return "sparkles"
        case .smartCare: return "wand.and.stars"
        case .junkCleaner: return "trash"
        case .uninstaller: return "xmark.bin"
        case .updater: return "arrow.triangle.2.circlepath"
        case .spaceLens: return "square.grid.3x3.fill"
        case .duplicateFinder: return "doc.on.doc"
        case .performance: return "gauge.with.dots.needle.50percent"
        case .cloudCleanup: return "icloud"
        case .protection: return "shield.lefthalf.filled"
        }
    }
}

struct RootView: View {
    @State private var selection: SidebarDestination? = .dashboard

    /// UI-test-only appearance override, set via `SOSMAC_UITEST_APPEARANCE`
    /// launch environment ("light"/"dark") so screenshot verification doesn't
    /// depend on — or mutate — the user's actual system appearance. `nil`
    /// (the default in every normal launch) leaves the system appearance in
    /// full control, exactly as before.
    private var uiTestColorScheme: ColorScheme? {
        switch ProcessInfo.processInfo.environment["SOSMAC_UITEST_APPEARANCE"] {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
                .navigationSplitViewColumnWidth(min: 200, ideal: 232)
        } detail: {
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
        .frame(minWidth: 720, minHeight: 480)
        .preferredColorScheme(uiTestColorScheme)
    }
}

/// Matches the mockup's sidebar: nav-item rows with icon + label (accent-
/// filled when active), grouped with an "Essential Trio" section label, and
/// a footer with a real storage gauge + app version. Deliberately excludes
/// Settings — that screen isn't built yet (Phase 9's licensing/monetization
/// work), and a nav item with nowhere to go would be dead UI.
private struct SidebarView: View {
    @Binding var selection: SidebarDestination?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 1) {
                row(.dashboard)
                row(.smartCare)

                SidebarSectionLabel(text: "Essential Trio")
                row(.junkCleaner)
                row(.uninstaller)
                row(.updater)

                Spacer().frame(height: Theme.Spacing.sm)
                row(.spaceLens)
                row(.duplicateFinder)
                row(.performance)
                row(.cloudCleanup)
                row(.protection)
            }
            .padding(Theme.Spacing.md)
        }
        .safeAreaInset(edge: .bottom) { SidebarFooterView() }
        .background(.regularMaterial)
    }

    private func row(_ destination: SidebarDestination) -> some View {
        Button {
            selection = destination
        } label: {
            SidebarNavRow(
                title: destination.rawValue,
                systemImage: destination.systemImage,
                hue: Theme.hue(for: destination),
                isActive: selection == destination
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("sidebar-nav-\(destination.rawValue)")
    }
}

private struct SidebarFooterView: View {
    private let storage = VolumeStorageInfo.current()

    private var versionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            if let storage {
                StorageGaugeMiniView(
                    usedFraction: storage.usedFraction,
                    label: "\(storage.usedDescription)/\(storage.totalDescription)"
                )
            }
            Text("SOS Mac \(versionString)")
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(Theme.Spacing.md)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Theme.border), alignment: .top)
        .background(.regularMaterial)
    }
}

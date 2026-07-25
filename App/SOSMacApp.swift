import SwiftUI
import SwiftData

@main
struct SOSMacApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: IgnoredItem.self)
    }
}

enum SidebarDestination: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case junkCleaner = "Junk & Cache Scanner"
    case uninstaller = "Uninstaller"
    case updater = "Updater"
    case spaceLens = "Space Lens"
    case duplicateFinder = "Duplicate Finder"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .dashboard: return "sparkles"
        case .junkCleaner: return "trash"
        case .uninstaller: return "xmark.bin"
        case .updater: return "arrow.triangle.2.circlepath"
        case .spaceLens: return "square.grid.3x3.fill"
        case .duplicateFinder: return "doc.on.doc"
        }
    }
}

struct RootView: View {
    @State private var selection: SidebarDestination? = .dashboard

    var body: some View {
        NavigationSplitView {
            List(SidebarDestination.allCases, selection: $selection) { destination in
                Label(destination.rawValue, systemImage: destination.systemImage)
                    .tag(destination)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            switch selection {
            case .dashboard, nil:
                DashboardPlaceholderView()
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
            }
        }
        .frame(minWidth: 720, minHeight: 480)
    }
}

struct DashboardPlaceholderView: View {
    var body: some View {
        ContentUnavailableView(
            "SOS Mac",
            systemImage: "sparkles",
            description: Text("Dashboard lands in a later phase — pick a module from the sidebar.")
        )
    }
}

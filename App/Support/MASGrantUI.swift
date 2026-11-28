import SwiftUI
#if MAS_BUILD
import Observation

/// MAS helpers on ModuleStore + the shared grant banner, used by every
/// home/applications-rooted screen to gate scan starts on the sandbox grant.
extension ModuleStore {

    /// True when the home grant exists; otherwise opens the grant panel and
    /// returns false. Call sites gate their scan-start action with this —
    /// an un-granted sandbox scan would walk the container and report a fake
    /// empty result.
    @MainActor
    func masEnsureHomeAccess() -> Bool {
        guard masAccess.homeRoot != nil else {
            masAccess.requestHomeAccess()
            return false
        }
        return true
    }

    /// Same gate for the Applications grant (Uninstaller, Updater).
    @MainActor
    func masEnsureApplicationsAccess() -> Bool {
        guard masAccess.applicationsRoot != nil else {
            masAccess.requestApplicationsAccess()
            return false
        }
        return true
    }

    /// Which grant (if any) a destination still needs before its scan can run.
    @MainActor
    func masMissingGrant(for destination: SidebarDestination) -> MASGrantKind? {
        switch destination {
        case .smartCare, .junkCleaner, .duplicateFinder, .protection:
            return masAccess.needsHomeGrant ? .home : nil
        case .uninstaller, .updater:
            return masAccess.needsApplicationsGrant ? .applications : nil
        default:
            return nil
        }
    }
}

enum MASGrantKind {
    case home
    case applications

    var title: String {
        switch self {
        case .home: "Grant access to your Home folder"
        case .applications: "Grant access to Applications"
        }
    }

    var text: String {
        switch self {
        case .home:
            "Sandboxed apps can't read your Home folder until you choose it once. Scans are disabled until then — nothing is guessed."
        case .applications:
            "Sandboxed apps can't list installed apps until you choose the Applications folder once."
        }
    }

    var buttonTitle: String {
        switch self {
        case .home: "Grant Access"
        case .applications: "Grant Access"
        }
    }

    @MainActor
    func request(from store: ModuleStore) {
        switch self {
        case .home: store.masAccess.requestHomeAccess()
        case .applications: store.masAccess.requestApplicationsAccess()
        }
    }
}

/// The one visible, honest call-to-action across all gated screens: pinned to
/// the bottom of the detail column while the destination's grant is missing.
private struct MASGrantBanner: ViewModifier {
    let store: ModuleStore
    let destination: SidebarDestination?

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let missing = store.masMissingGrant(for: destination ?? .dashboard) {
                VStack(spacing: 0) {
                    BannerView(
                        kind: .info,
                        title: missing.title,
                        text: missing.text,
                        systemImage: "lock.open") {
                        Button(missing.buttonTitle) {
                            missing.request(from: store)
                        }
                        .sosButton(.default)
                    }
                    .padding(EdgeInsets(top: 0, leading: Theme.Spacing.s5, bottom: Theme.Spacing.s5, trailing: Theme.Spacing.s5))
                    .background(
                        LinearGradient(colors: [.clear, Theme.Color.bgBase.opacity(0.98), Theme.Color.bgBase],
                                       startPoint: .top, endPoint: .bottom)
                            .ignoresSafeArea(edges: .bottom)
                    )
                    if let error = store.masAccess.grantError {
                        BannerView(kind: .err, title: "Couldn't save the folder choice", text: error)
                            .padding(.horizontal, Theme.Spacing.s5)
                            .padding(.bottom, Theme.Spacing.s2)
                            .background(Theme.Color.bgBase.opacity(0.98))
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("mas-grant-banner")
            }
        }
        .animation(Theme.Motion.standard, value: store.masAccess.homeRoot)
        .animation(Theme.Motion.standard, value: store.masAccess.applicationsRoot)
    }
}

extension View {
    /// Shows the MAS grant call-to-action on destinations whose scan roots
    /// need a user-selected folder. No-op outside MAS builds.
    @ViewBuilder
    func masGrantBanner(store: ModuleStore, destination: SidebarDestination?) -> some View {
        self.modifier(MASGrantBanner(store: store, destination: destination))
    }
}
#endif

#if !MAS_BUILD
extension View {
    /// Non-MAS builds: no grant banner, unchanged behavior.
    @ViewBuilder
    func masGrantBanner(store: ModuleStore, destination: SidebarDestination?) -> some View {
        self
    }
}
#endif

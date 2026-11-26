#if DEBUG
import AppKit
import SwiftUI

/// Debug-only launch hooks that let a script or UI test put the app into a known
/// state without touching the user's files, screen or system appearance.
///
/// Every variable is prefixed `SOSMAC_UITEST_`; an unset variable means normal
/// behaviour, so a launch with no variables is identical to a build without this
/// file. Read once, at launch.
///
/// | Variable | Meaning |
/// |---|---|
/// | `SOSMAC_UITEST_SCREEN` | Prototype screen key: `dashboard`, `smartcare`, `junk`, `duplicates`, `spacelens`, `cloud`, `uninstaller`, `updater`, `performance`, `protection`; `gallery` opens the component gallery |
/// | `SOSMAC_UITEST_STATE` | Lifecycle state for that screen (`start`, `scanning`, `results`, `review`, `cleaning`, `done`, `empty`, `error`, …) |
/// | `SOSMAC_UITEST_APPEARANCE` | `light` or `dark` |
/// | `SOSMAC_UITEST_FIXTURES` | `1` to feed screens made-up data from `UITestFixtures` |
/// | `SOSMAC_UITEST_WINDOW_SIZE` | Outer window size in points, `"1200x760"` |
/// | `SOSMAC_UITEST_REDUCE_TRANSPARENCY` | `1` to force the reduce-transparency environment value |
/// | `SOSMAC_UITEST_OUTPUT_DIR` | Directory where a harness wants artifacts written |
///
/// ## Fixture convention for screen PRs
/// A screen that supports a state under fixtures implements, on its view model,
/// `#if DEBUG func loadFixture(_ state: LifecycleState) { … } #endif`, fills it from
/// `UITestFixtures`, and is applied from the screen's `.task` when
/// `UITestHooks.current.fixtures` is true and `state` matches. It must never read
/// the real file system in that mode. (`LifecycleState` arrives with PR 4b; until
/// then the raw `state` string is available here.)
struct UITestHooks: Sendable, Equatable {
    var screen: String?
    var state: String?
    var appearance: String?
    var fixtures: Bool
    var windowSize: CGSize?
    var reduceTransparency: Bool
    var outputDirectory: String?

    /// Parsed once at first access.
    static let current = UITestHooks(environment: ProcessInfo.processInfo.environment)

    /// Screen key of the Debug-only component gallery (`ComponentGalleryView`), in any letter case.
    static let galleryKey = "gallery"

    init(environment: [String: String]) {
        func value(_ key: String) -> String? {
            guard let raw = environment["SOSMAC_UITEST_" + key], !raw.isEmpty else { return nil }
            return raw
        }
        func flag(_ key: String) -> Bool {
            guard let raw = value(key)?.lowercased() else { return false }
            return raw == "1" || raw == "true" || raw == "yes"
        }
        screen = value("SCREEN")
        state = value("STATE")
        switch value("APPEARANCE") {
        case "light": appearance = "light"
        case "dark": appearance = "dark"
        default: appearance = nil
        }
        fixtures = flag("FIXTURES")
        windowSize = Self.parseSize(value("WINDOW_SIZE"))
        reduceTransparency = flag("REDUCE_TRANSPARENCY")
        outputDirectory = value("OUTPUT_DIR")
    }

    /// Parses `"1200x760"`. Rejects anything else, including non-positive values.
    static func parseSize(_ text: String?) -> CGSize? {
        guard let text else { return nil }
        let parts = text.lowercased().split(separator: "x", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let width = Double(parts[0]), let height = Double(parts[1]),
              width > 0, height > 0 else { return nil }
        return CGSize(width: width, height: height)
    }

    var colorScheme: ColorScheme? {
        switch appearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    /// The sidebar destination named by `screen`, or `nil` when unset or unknown.
    var destination: SidebarDestination? {
        screen.flatMap(SidebarDestination.init(uiTestKey:))
    }

    /// `SOSMAC_UITEST_SCREEN=gallery`: the component gallery replaces the whole app for this launch.
    /// It is not a sidebar destination, so nothing real (no volume name or size) is on screen.
    var showsGallery: Bool {
        screen?.lowercased() == Self.galleryKey
    }
}

private struct UITestReduceTransparencyKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// SwiftUI's `accessibilityReduceTransparency` is read-only, so the hook cannot
    /// override it. Debug code that adapts to reduced transparency reads
    /// `accessibilityReduceTransparency || uiTestReduceTransparency`. It is `false`
    /// unless `SOSMAC_UITEST_REDUCE_TRANSPARENCY=1`, so it can only force the
    /// reduced look on, never hide a real system setting.
    var uiTestReduceTransparency: Bool {
        get { self[UITestReduceTransparencyKey.self] }
        set { self[UITestReduceTransparencyKey.self] = newValue }
    }
}

extension SidebarDestination {
    /// Maps the prototype's screen keys (`docs/redesign/prototype/data.js`) to destinations.
    init?(uiTestKey key: String) {
        switch key {
        case "dashboard": self = .dashboard
        case "smartcare": self = .smartCare
        case "junk": self = .junkCleaner
        case "duplicates": self = .duplicateFinder
        case "spacelens": self = .spaceLens
        case "cloud": self = .cloudCleanup
        case "uninstaller": self = .uninstaller
        case "updater": self = .updater
        case "performance": self = .performance
        case "protection": self = .protection
        default: return nil
        }
    }
}

/// Forces the hosting window to an exact outer size. `defaultSize` is not enough:
/// window state restoration can override it, so the hook sets the frame itself.
struct UITestWindowSizer: NSViewRepresentable {
    let size: CGSize

    func makeNSView(context: Context) -> NSView { SizingView(size: size) }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class SizingView: NSView {
        let size: CGSize
        init(size: CGSize) {
            self.size = size
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            // Defer one turn so it runs after SwiftUI's own initial sizing.
            Task { @MainActor [size, weak window] in
                guard let window else { return }
                var frame = window.frame
                frame.origin.y += frame.height - size.height  // keep the top-left corner
                frame.size = size
                window.setFrame(frame, display: true, animate: false)
            }
        }
    }
}
#endif

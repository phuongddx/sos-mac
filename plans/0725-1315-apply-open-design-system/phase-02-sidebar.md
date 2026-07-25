# Phase 2: Sidebar retrofit

Target: `App/SOSMacApp.swift` (`RootView`).

- Replace the plain `List(SidebarDestination.allCases, selection:)` row look with the mockup's nav-item style (icon + label, accent-filled when active) via the `SidebarStyle` pieces from Phase 1.
- Group items to match `index.html`'s sidebar: Dashboard + Smart Care ungrouped at top, then a "Essential Trio" section label above Junk/Uninstaller/Updater, then Space Lens/Duplicate Finder/Performance/Cloud Cleanup ungrouped.
- Do NOT add Protection or Settings nav items — those screens don't exist in the app yet (Phase 7+, unbuilt). Adding them would be dead navigation.
- Footer: real storage gauge (via `FileManager.default.attributesOfFileSystem` on the boot volume — actual used/total bytes, not the mockup's fake "312/512 GB"), plus the app's real `MARKETING_VERSION`/`CFBundleShortVersionString` instead of the mockup's hardcoded "2.4.1".
- Keep `NavigationSplitView` — this is styling the existing sidebar list, not replacing the navigation architecture.

## Verify
`xcodebuild build -scheme SOSMac -configuration Debug`; visually confirm via `run` skill or screenshot if a display is available.

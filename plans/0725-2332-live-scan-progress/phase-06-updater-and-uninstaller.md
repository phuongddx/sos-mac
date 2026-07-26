# Phase 6: Updater + Uninstaller

Back to [plan.md](plan.md). Depends on [Phase 1](phase-01-cleancore-foundation.md) and [Phase 2](phase-02-design-system.md). Neither task in this phase needs any further CleanCore change — both modules already know their total (tracked-app count / installed-app count) upfront in the ViewModel, and their per-item work is already a sequential loop the ViewModel controls directly.

**Verification note:** same as Phases 3–5 — no App-layer unit test target; each task ends in a manual run-through.

---

### Task 15: Updater — aggregate "X of N apps checked"

**Files:**
- Modify: `App/Features/Updater/UpdaterViewModel.swift`
- Modify: `App/Features/Updater/UpdaterView.swift`

**Interfaces:**
- Produces: `UpdaterViewModel.progressTracker: ScanProgressTracker`. No `Task<Void, Never>`/cancellation is added here — `checkAll()` was already a plain `@MainActor` `async` function called directly (`await viewModel.checkAll()`, never wrapped in a stored cancellable `Task`), and the approved design doesn't call for adding Cancel to this module.

- [ ] **Step 1: Track aggregate progress in the ViewModel**

In `App/Features/Updater/UpdaterViewModel.swift`, add a stored property after `private(set) var rows: [AppUpdateRow] = []`:

```swift
    let progressTracker = ScanProgressTracker()
```

Replace `checkAll()`:

```swift
    func checkAll() async {
        progressTracker.start()
        for index in rows.indices {
            await checkSingle(at: index)
            progressTracker.record(ScanProgress(itemsProcessed: index + 1, totalItems: rows.count, currentPath: rows[index].app.name))
        }
    }
```

(`checkSingle(at:)` itself, and its per-row `isChecking` flag, are unchanged — this task only adds an aggregate signal alongside the existing per-row one.)

- [ ] **Step 2: Show the aggregate bar**

In `App/Features/Updater/UpdaterView.swift`, replace:

```swift
                if isCheckingAny {
                    StepRowView(name: "Checking for updates…", meta: nil, state: .active)
                } else if !viewModel.hasAnyUpdate {
```

with:

```swift
                if isCheckingAny {
                    if let progress = viewModel.progressTracker.progress {
                        ScanProgressPanel(progress: progress, showCurrentPath: true)
                    } else {
                        // Brief window between checkAll() starting and the
                        // first row finishing, before progressTracker has
                        // anything to report yet.
                        StepRowView(name: "Checking for updates…", meta: nil, state: .active)
                    }
                } else if !viewModel.hasAnyUpdate {
```

- [ ] **Step 3: Regenerate the Xcode project and build**

Run: `xcodegen generate`
Run: `xcodebuild build -scheme SOSMac -configuration Debug`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Manual run-through**

1. Launch the app, navigate to Updater (or click "Check Again").
2. Confirm a percentage bar with a live "X of N" feel (via the bar filling) and the current app's name appear while checking, replacing the previous static "Checking for updates…" row.
3. Confirm per-row status badges ("Update available"/"Up to date"/etc.) still populate correctly once the aggregate check finishes.

- [ ] **Step 5: Commit**

```bash
git add App/Features/Updater/UpdaterViewModel.swift App/Features/Updater/UpdaterView.swift
git commit -m "feat(updater): show aggregate check-all progress across tracked apps"
```

---

### Task 16: Uninstaller — new "Inspect All" feature

**Files:**
- Modify: `App/Features/Uninstaller/UninstallerViewModel.swift`
- Modify: `App/Features/Uninstaller/UninstallerView.swift`

**Interfaces:**
- Produces: `UninstallerViewModel.progressTracker: ScanProgressTracker`, `.isInspectingAll: Bool`, `.inspectAll() async`, `.totalInspectedBytes: Int64`, and a new `AppRow.inspectedSize: Int64?`.

**Scope note — mechanism refinement from the design spec:** the approved spec suggested a new `.inspectingAll` `Phase` case for this feature. On implementation, that would replace the whole app list with a separate screen mid-inspection, which is a worse experience than what "Inspect All" is actually for (proactively filling in sizes onto the *existing* list so the user can compare apps before picking one). This task instead mirrors Task 15's shape exactly: a plain `isInspectingAll: Bool` flag + `progressTracker`, with the aggregate bar rendered *above* the still-visible, still-interactive app list — consistent with how Updater's own aggregate check-all already works in this same codebase, and it lets each row's size fill in live as `inspectAll()` progresses through it. The *outcome* the spec asked for (aggregate "X of N apps inspected" progress, and every app's reclaimable size available before manual per-app inspection) is unchanged — only the phase-enum mechanism is simplified away.

- [ ] **Step 1: Add `inspectedSize` and the aggregate inspection loop**

In `App/Features/Uninstaller/UninstallerViewModel.swift`, change `AppRow`:

```swift
    struct AppRow: Identifiable {
        let app: InstalledApp
        var inspectedSize: Int64?
        var id: String { app.id }
    }
```

Add two stored properties after `private(set) var inspectingBundleID: String?`:

```swift
    let progressTracker = ScanProgressTracker()
    private(set) var isInspectingAll = false
```

Add a computed property (near `func loadApps()`):

```swift
    var totalInspectedBytes: Int64 {
        apps.compactMap(\.inspectedSize).reduce(0, +)
    }
```

Add a new method (near `func inspect(_ row: AppRow) async`):

```swift
    /// Proactively runs the same per-app `AppUninstaller.scan()` the
    /// existing per-row "Inspect" button already uses, for every installed
    /// app in order, caching each app's total reclaimable size onto its row.
    /// One app's scan failing (`try?` → `nil`) doesn't abort the rest — same
    /// partial-failure handling every other batch operation in this codebase
    /// already uses. Purely additive: doesn't select anything, doesn't
    /// delete anything, and doesn't touch the existing per-row `inspect(_:)`
    /// flow used to actually review and confirm an uninstall.
    func inspectAll() async {
        guard !isInspectingAll else { return }
        isInspectingAll = true
        progressTracker.start()
        defer { isInspectingAll = false }

        for index in apps.indices {
            let row = apps[index]
            let uninstaller = AppUninstaller(appBundlePath: row.app.bundlePath, bundleIdentifier: row.app.bundleIdentifier)
            if let items = try? await uninstaller.scan() {
                apps[index].inspectedSize = items.reduce(0) { $0 + $1.size }
            }
            progressTracker.record(ScanProgress(itemsProcessed: index + 1, totalItems: apps.count, currentPath: row.app.name))
        }
    }
```

- [ ] **Step 2: Wire the header and app rows**

In `App/Features/Uninstaller/UninstallerView.swift`, replace `browsingHeader`:

```swift
    private var browsingHeader: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Uninstaller")
                        .font(.system(size: Theme.TextSize.xl, weight: .semibold))
                        .foregroundStyle(Theme.foreground)
                    Text(headerSubtitle)
                        .font(.system(size: Theme.TextSize.sm))
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                if !viewModel.isInspectingAll {
                    Button("Inspect All") { Task { await viewModel.inspectAll() } }
                        .buttonStyle(.bordered)
                        .disabled(viewModel.apps.isEmpty || viewModel.inspectingBundleID != nil)
                }
            }
            if viewModel.isInspectingAll, let progress = viewModel.progressTracker.progress {
                ScanProgressPanel(progress: progress, showCurrentPath: true)
            }
        }
        .padding(Theme.Spacing.xxxl)
    }

    private var headerSubtitle: String {
        guard viewModel.totalInspectedBytes > 0 else {
            return "\(viewModel.apps.count) applications installed"
        }
        return "\(viewModel.apps.count) applications installed · \(ByteFormatter.string(fromByteCount: viewModel.totalInspectedBytes)) reclaimable if all removed"
    }
```

Replace `appRow(_:)`'s body to show the cached size and disable per-row inspect while a bulk inspection is running:

```swift
    private func appRow(_ row: UninstallerViewModel.AppRow) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            appIcon(for: row.app.name)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.app.name)
                    .font(.system(size: Theme.TextSize.sm, weight: .medium))
                    .foregroundStyle(Theme.foreground)
                if let version = row.app.version {
                    Text("Version \(version)")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                }
            }

            Spacer(minLength: Theme.Spacing.md)

            if let inspectedSize = row.inspectedSize {
                Text(ByteFormatter.string(fromByteCount: inspectedSize))
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.muted)
                    .monospacedDigit()
            }

            if row.app.isAppStoreDistributed {
                BadgeView(text: "App Store", style: .accent)
            }

            if viewModel.inspectingBundleID == row.app.bundleIdentifier {
                ProgressView().scaleEffect(0.6)
            } else {
                Button("Inspect") {
                    Task { await viewModel.inspect(row) }
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.inspectingBundleID != nil || viewModel.isInspectingAll)
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        .elevation(.raised)
    }
```

(Only the `Spacer(minLength:)` → size text → badge → button block changed; `appIcon`/padding/background/overlay/clipShape/elevation are unchanged from the existing implementation.)

- [ ] **Step 3: Regenerate the Xcode project and build**

Run: `xcodegen generate`
Run: `xcodebuild build -scheme SOSMac -configuration Debug`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Manual run-through**

1. Launch the app, navigate to Uninstaller, click "Inspect All".
2. Confirm: an aggregate progress bar with a live app name appears above the list; each row's reclaimable size fills in as its turn comes up; the header subtitle updates to show a total reclaimable figure once at least one app has been inspected.
3. Confirm the existing per-row "Inspect" → review associated files → "Uninstall" flow still works exactly as before, both during and after an "Inspect All" run (per-row Inspect is disabled while "Inspect All" is running, re-enabled once it finishes).
4. Confirm a failed per-app scan (if one occurs) doesn't stop the rest of "Inspect All" from completing.

- [ ] **Step 5: Commit**

```bash
git add App/Features/Uninstaller/UninstallerViewModel.swift App/Features/Uninstaller/UninstallerView.swift
git commit -m "feat(uninstaller): add Inspect All with aggregate progress and cached reclaimable sizes"
```

---

Phase 6 complete once both tasks are committed and the build is green. This is the final phase — once it's done, do a last full-repo pass:

```bash
cd Packages/CleanCore && swift test
cd ../.. && xcodebuild build -scheme SOSMac -configuration Debug
```

Both must be green. Then use `superpowers:requesting-code-review` (or this repo's own `/code-review`) before merging, and update `docs/superpowers/specs/2026-07-25-live-scan-progress-design.md`'s status if this repo's convention expects specs to be marked "implemented" once their plan is done.

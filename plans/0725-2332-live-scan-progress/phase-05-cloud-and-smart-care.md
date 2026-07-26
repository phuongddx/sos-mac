# Phase 5: Cloud Cleanup + Smart Care

Back to [plan.md](plan.md). Depends on [Phase 1](phase-01-cleancore-foundation.md) and [Phase 2](phase-02-design-system.md). Task 14 (Smart Care) additionally depends on Phase 1's Task 6 (`SmartCareOrchestrator.run(onItemProgress:)`) and Phase 4's Task 12 (`DuplicateFinder.findExactDuplicateGroups(onProgress:)`).

**Verification note:** same as Phases 3–4 — no App-layer unit test target; each task ends in a manual run-through.

---

### Task 13: Cloud Cleanup — per-provider pagination progress

**Files:**
- Modify: `App/Features/CloudCleanup/CloudCleanupViewModel.swift`
- Modify: `App/Features/CloudCleanup/CloudCleanupView.swift`

**Scope note:** this task needs **no CleanCore change at all**. `CloudProvider.listFiles(cursor:)` already returns one page per call, and `CloudCleanupViewModel.loadFiles(_:)` already loops over it (`repeat ... while cursor != nil`) — the running "files listed so far" count is just `allFiles.count`, already sitting right there in the existing loop. (The design spec floated adding an `onProgress` parameter to `CloudProvider.listFiles` itself; on inspection that's unneeded complexity for zero behavioral benefit — the caller-side loop already has everything it needs. `ICloudLocalScanner`'s local scan is intentionally **not** touched by this task — it's a plain `Scanner` conformer that doesn't override the new `scan(onProgress:)`, so it silently keeps today's spinner-only behavior via the Task 1 default. That module wasn't in the approved design's per-engine table; adding it would be scope creep beyond what was signed off.)

**Interfaces:**
- Produces: `CloudAPIProviderState.scanProgress: ScanProgress?`.

- [ ] **Step 1: Track progress in the pagination loop**

In `App/Features/CloudCleanup/CloudCleanupViewModel.swift`, add a field to `CloudAPIProviderState`:

```swift
struct CloudAPIProviderState {
    var isAuthenticated = false
    var isLoading = false
    var scanProgress: ScanProgress?
    var files: [CloudFileMetadata] = []
    var duplicateGroups: [CloudDuplicateGroup] = []
    var errorMessage: String?
}
```

In `loadFiles(_:)`, reset progress alongside the existing loading flags:

```swift
    func loadFiles(_ kind: APIProviderKind) async {
        apiStates[kind]?.isLoading = true
        apiStates[kind]?.errorMessage = nil
        apiStates[kind]?.scanProgress = nil
```

and inside the `repeat` loop, right after `pageCount += 1`, add:

```swift
            apiStates[kind]?.scanProgress = ScanProgress(itemsProcessed: allFiles.count)
```

- [ ] **Step 2: Show it in the view**

In `App/Features/CloudCleanup/CloudCleanupView.swift`, replace:

```swift
            } else if state.isLoading {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
```

with:

```swift
            } else if state.isLoading {
                VStack(spacing: Theme.Spacing.md) {
                    ProgressView()
                    if let progress = state.scanProgress {
                        ScanProgressPanel(progress: progress, countOnlyLabel: { "\($0.formatted()) files listed…" })
                    } else {
                        Text("Loading…")
                            .font(.system(size: Theme.TextSize.sm))
                            .foregroundStyle(Theme.muted)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
```

- [ ] **Step 3: Regenerate the Xcode project and build**

Run: `xcodegen generate`
Run: `xcodebuild build -scheme SOSMac -configuration Debug`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Manual run-through**

Cloud Cleanup requires a real registered OAuth app per provider (`CloudProviderConfig` is empty by default, per the existing `.notConfigured` fail-closed behavior) — if none is configured in this environment, connecting will fail with "This provider isn't configured yet," which is expected and not a regression. If a provider *is* configured: connect, click "Refresh", and confirm the "N files listed…" count updates live across pages instead of a static "Loading…".

- [ ] **Step 5: Commit**

```bash
git add App/Features/CloudCleanup/CloudCleanupViewModel.swift App/Features/CloudCleanup/CloudCleanupView.swift
git commit -m "feat(cloud-cleanup): show live file-count progress while paginating"
```

---

### Task 14: Smart Care — aggregate cross-module progress

**Files:**
- Modify: `App/Features/SmartCare/SmartCareViewModel.swift`
- Modify: `App/Features/SmartCare/SmartCareView.swift`

**Interfaces:**
- Consumes: `SmartCareOrchestrator.run(onItemProgress:)` (Phase 1, Task 6); `DuplicateFinder.findExactDuplicateGroups(onProgress:)` (Phase 4, Task 12); `ScanProgressPanel` (Phase 2).

**Scope note:** the approved design's "reclaimed-so-far number" for this card only makes sense once cleaning has actually reclaimed something — mid-scan, nothing has been reclaimed yet. This task shows an honest **item-count** aggregate (Σ processed / Σ total across in-flight sub-scans that have a known total) during `.scanning` instead — no fabricated byte figure. Only Junk Cleaner's rule-based total and Duplicate Finder's hashing-phase total ever feed this; a module with no reported total (or not yet `.scanning`) is simply excluded from the sum, falling back entirely to today's per-module step list when nothing has reported yet.

- [ ] **Step 1: Track per-module progress and expose an aggregate**

In `App/Features/SmartCare/SmartCareViewModel.swift`, add a stored property after `private(set) var moduleStatuses: [String: ModuleStatus] = [:]`:

```swift
    private(set) var moduleProgress: [String: ScanProgress] = [:]
```

In `performScan()`, reset it alongside `moduleStatuses`:

```swift
        moduleStatuses = [Self.junkModuleName: .pending, Self.duplicatesModuleName: .pending]
        moduleProgress = [:]
```

Change the orchestrator call:

```swift
        async let junkReport = orchestrator.run(
            onModuleStart: { [weak self] name in
                Task { @MainActor in self?.moduleStatuses[name] = .scanning }
            }
        )
```

to:

```swift
        async let junkReport = orchestrator.run(
            onModuleStart: { [weak self] name in
                Task { @MainActor in self?.moduleStatuses[name] = .scanning }
            },
            onItemProgress: { [weak self] name, progress in
                Task { @MainActor in self?.moduleProgress[name] = progress }
            }
        )
```

Change the direct Duplicate Finder call:

```swift
        moduleStatuses[Self.duplicatesModuleName] = .scanning
        async let duplicateResult: DuplicateScanResult? = try? await DuplicateFinder(rootPath: rootPath)
            .findExactDuplicateGroups()
```

to:

```swift
        moduleStatuses[Self.duplicatesModuleName] = .scanning
        async let duplicateResult: DuplicateScanResult? = try? await DuplicateFinder(rootPath: rootPath)
            .findExactDuplicateGroups(onProgress: { [weak self] progress in
                Task { @MainActor in self?.moduleProgress[Self.duplicatesModuleName] = progress }
            })
```

Add a computed property (near `totalSelectedBytes`):

```swift
    /// Σ(itemsProcessed)/Σ(totalItems) across whichever modules are
    /// currently `.scanning` AND have reported a real total — `nil` (no bar,
    /// step list only) until at least one of them has.
    var aggregateProgress: ScanProgress? {
        let inFlightModuleNames = moduleStatuses.filter { $0.value == .scanning }.map(\.key)
        let reporting = inFlightModuleNames.compactMap { moduleProgress[$0] }.filter { $0.totalItems != nil }
        guard !reporting.isEmpty else { return nil }
        return ScanProgress(
            itemsProcessed: reporting.reduce(0) { $0 + $1.itemsProcessed },
            totalItems: reporting.reduce(0) { $0 + ($1.totalItems ?? 0) }
        )
    }
```

Add `moduleProgress = [:]` to `startNewScan()` alongside its existing resets.

- [ ] **Step 2: Show the aggregate bar above the step list**

In `App/Features/SmartCare/SmartCareView.swift`, replace `scanningState`:

```swift
    private var scanningState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                if let aggregate = viewModel.aggregateProgress {
                    ScanProgressPanel(progress: aggregate)
                }
                ForEach([SmartCareViewModel.junkModuleName, SmartCareViewModel.duplicatesModuleName], id: \.self) { name in
                    stepRow(for: name, status: viewModel.moduleStatuses[name] ?? .pending)
                }
            }
            .padding(Theme.Spacing.xxxl)
        }
    }
```

(`stepRow(for:status:)` itself is unchanged — the per-module done/scanning/pending/failed row rendering already works and isn't part of this task.)

- [ ] **Step 3: Regenerate the Xcode project and build**

Run: `xcodegen generate`
Run: `xcodebuild build -scheme SOSMac -configuration Debug`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Manual run-through**

1. Launch the app, navigate to Smart Care, click "Run Smart Care".
2. Confirm the per-module step rows still behave exactly as before (pending → scanning → done/failed).
3. Confirm an aggregate percentage bar appears above them once at least one of Junk Cleaner/Duplicate Finder has reported real progress, and that it disappears/never appears if the scan finishes too fast to observe it (small test directories) — that's expected, not a bug.
4. Confirm the review/cleanup/summary phases after scanning are unaffected.

- [ ] **Step 5: Commit**

```bash
git add App/Features/SmartCare/SmartCareViewModel.swift App/Features/SmartCare/SmartCareView.swift
git commit -m "feat(smart-care): show an aggregate cross-module progress bar while scanning"
```

---

Phase 5 complete once both tasks are committed and the build is green. Continue to [Phase 6](phase-06-updater-and-uninstaller.md).

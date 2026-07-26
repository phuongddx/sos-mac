# Phase 3: Junk Cleaner + Protection

Back to [plan.md](plan.md). Depends on [Phase 1](phase-01-cleancore-foundation.md) and [Phase 2](phase-02-design-system.md).

**Verification note:** neither task has an automated test (App-layer, no unit test target — see plan.md's Global Constraints). Each task's steps are: implement, regenerate the Xcode project, build, then a scripted manual run-through identical in spirit to the one already used to verify Space Lens works (launch the built `.app`, drive it with a real scan, confirm the live behavior, no `xcrun simctl`/simulator involved — this is a native macOS app).

---

### Task 9: Junk Cleaner — step list + percentage + Cancel

**Files:**
- Modify: `App/Features/JunkCleaner/JunkCleanerViewModel.swift`
- Modify: `App/Features/JunkCleaner/JunkCleanerView.swift`

**Interfaces:**
- Consumes: `JunkScanner.scan(onProgress:)` (Phase 1, Task 2); `ScanProgressTracker`, `ScanProgressPanel` (Phase 2).
- Produces: `JunkCleanerViewModel.progressTracker: ScanProgressTracker`, `.ruleLabels: [String]`, `.cancelScan()` — a genuinely new capability this module didn't have before (it previously ran a single non-cancellable `await`).

- [ ] **Step 1: Add cancellable scanning + progress tracking to the ViewModel**

In `App/Features/JunkCleaner/JunkCleanerViewModel.swift`, add two stored properties after `private let modelContext: ModelContext`:

```swift
    let progressTracker = ScanProgressTracker()
    private var scanTask: Task<Void, Never>?
```

Add a computed property (anywhere in the type, e.g. right after `totalSelectedBytes`):

```swift
    /// The categories this scan covers, in the order `JunkScanner` walks
    /// them — used to render one `StepRowView` per rule while scanning.
    var ruleLabels: [String] { JunkRule.allowlist.map(\.label) }
```

Replace the existing `func startScan() async { ... }` with:

```swift
    func startScan() {
        scanTask?.cancel()
        scanTask = Task { [weak self] in
            await self?.performScan()
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        if phase == .scanning { phase = .idle }
    }

    private func performScan() async {
        phase = .scanning
        errorMessage = nil
        progressTracker.start()
        do {
            let ignoredPaths = try fetchIgnoredPaths()
            let scanned = try await scanner.scan(onProgress: { [weak self] progress in
                Task { @MainActor in self?.progressTracker.record(progress) }
            })
            guard !Task.isCancelled else { return }
            items = scanned.filter { !ignoredPaths.contains($0.path) }
            // Only pre-select items that are both rule-classified safe and
            // don't need the not-yet-built privileged helper — never
            // auto-select anything requiring a closer look.
            selectedPaths = Set(
                items
                    .filter { $0.severity == .safe && !$0.requiresPrivilegedHelper }
                    .map(\.path)
            )
            phase = .results
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
            phase = .idle
        }
    }
```

This mirrors the exact `scanTask`/`performScan()`/`cancelScan()` shape already used by `SpaceLensViewModel`, `ProtectionViewModel`, and `DuplicateFinderViewModel` — not a new pattern, this module was simply the one place it was still missing.

- [ ] **Step 2: Wire the scanning UI**

In `App/Features/JunkCleaner/JunkCleanerView.swift`:

1. Change the idle state's action from `action: { Task { await viewModel.startScan() } }` to `action: { viewModel.startScan() }` (it's no longer `async` at the call site — the ViewModel spawns its own task).
2. Add `.onDisappear { viewModel?.cancelScan() }` to the outer `JunkCleanerView.body`'s `Group { ... }` (alongside its existing `.task { ... }` and `.navigationTitle(...)`), matching every other scan-driving module in this codebase.
3. Replace the `.scanning` case's body in `JunkCleanerContentView`:

```swift
            case .scanning:
                VStack(spacing: Theme.Spacing.lg) {
                    ScanProgressPanel(progress: viewModel.progressTracker.progress, steps: scanningSteps)
                        .frame(maxWidth: 420)
                    Button("Cancel") { viewModel.cancelScan() }
                        .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(Theme.Spacing.giant)
```

4. Add a private computed property to `JunkCleanerContentView` (near `badgeStyle(for:)`):

```swift
    /// Rule `i` is done once `itemsProcessed > i` completed rules have been
    /// reported; the very next rule in order is `.active`; everything after
    /// that is `.pending`. There's no per-rule "started" signal from the
    /// engine (only "rule N completed"), so rule 0 shows `.active`
    /// immediately at `itemsProcessed == 0` — the best available
    /// approximation without adding a start-of-rule callback nobody else needs.
    private var scanningSteps: [ScanProgressPanel.StepModel] {
        let completedCount = viewModel.progressTracker.progress?.itemsProcessed ?? 0
        return viewModel.ruleLabels.enumerated().map { index, label in
            let state: StepRowView.StepState = index < completedCount ? .done : (index == completedCount ? .active : .pending)
            return ScanProgressPanel.StepModel(name: label, meta: nil, state: state)
        }
    }
```

- [ ] **Step 3: Regenerate the Xcode project**

Run: `xcodegen generate`

- [ ] **Step 4: Build**

Run: `xcodebuild build -scheme SOSMac -configuration Debug`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Manual run-through**

1. Launch the built app (from `xcodebuild`'s output path, or `open` the `.app` in `~/Library/Developer/Xcode/DerivedData/.../Build/Products/Debug/SOSMac.app`).
2. Navigate to Junk & Cache Scanner, click "Start Scan".
3. Confirm: a step list appears (one row per rule — "User App Caches", "User Logs", "App Support Cache Folders", "System Caches…"), rows flip from active → done in order as the scan progresses, a percentage bar fills alongside them, and a Cancel button is present.
4. Click Cancel mid-scan (or let it finish) — confirm Cancel returns to the idle "Scan for junk" screen with no error, and a full run still reaches the Results screen normally.

- [ ] **Step 6: Commit**

```bash
git add App/Features/JunkCleaner/JunkCleanerViewModel.swift App/Features/JunkCleaner/JunkCleanerView.swift
git commit -m "feat(junk-cleaner): show live per-rule scan progress and add Cancel"
```

---

### Task 10: Protection — ticker + percentage + ETA + live path

**Files:**
- Modify: `App/Features/Protection/ProtectionViewModel.swift`
- Modify: `App/Features/Protection/ProtectionView.swift`

**Interfaces:**
- Consumes: `ProtectionScanner.scan(onProgress:)` (Phase 1, Task 4); `ScanProgressTracker`, `ScanProgressPanel` (Phase 2).
- Produces: `ProtectionViewModel.progressTracker: ScanProgressTracker`. `cancelScan()`/`scanTask` already existed on this ViewModel before this task — only the scanning-phase view changes; no new cancellation capability is added here (Junk Cleaner was the one missing it, not Protection).

- [ ] **Step 1: Wire progress into the ViewModel**

In `App/Features/Protection/ProtectionViewModel.swift`, add a stored property after `private var scanTask: Task<Void, Never>?`:

```swift
    let progressTracker = ScanProgressTracker()
```

In `performScan()`, add `progressTracker.start()` right after `errorMessage = nil`, and change:

```swift
            findings = try await scanner.scan()
```

to:

```swift
            findings = try await scanner.scan(onProgress: { [weak self] progress in
                Task { @MainActor in self?.progressTracker.record(progress) }
            })
```

- [ ] **Step 2: Wire the scanning UI**

In `App/Features/Protection/ProtectionView.swift`, replace the `.scanning` case's body:

```swift
            case .scanning:
                ScanProgressPanel(
                    progress: viewModel.progressTracker.progress,
                    ticker: viewModel.progressTracker.progress.map { "\($0.itemsProcessed.formatted()) files scanned" },
                    etaText: viewModel.progressTracker.estimatedTimeRemainingText,
                    showCurrentPath: true,
                    countOnlyLabel: { "Scanned \($0.formatted()) files…" }
                )
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
```

(`ProtectionViewModel` already has `cancelScan()` wired but no Cancel button in this phase's UI — that gap is pre-existing and out of scope for this task, per the approved spec's Protection row, which calls only for ticker/bar/ETA/path.)

- [ ] **Step 3: Regenerate the Xcode project**

Run: `xcodegen generate`

- [ ] **Step 4: Build**

Run: `xcodebuild build -scheme SOSMac -configuration Debug`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Manual run-through**

1. Launch the built app, navigate to Protection, click "Start Scan".
2. Confirm: a live ticker ("N files scanned"), a percentage bar, and a monospaced current-path line all appear and update while scanning.
3. Confirm the ETA line appears once the scan has processed at least 20 files (small fixture directories like `~/Library/LaunchAgents` may finish before that threshold — that's expected; a real `~/Downloads` with more files should show it before completion).
4. Confirm the scan still reaches the Results screen normally when it finishes, and that quarantine/restore still work unaffected.

- [ ] **Step 6: Commit**

```bash
git add App/Features/Protection/ProtectionViewModel.swift App/Features/Protection/ProtectionView.swift
git commit -m "feat(protection): show live ticker, percentage, ETA, and scan path"
```

---

Phase 3 complete once both tasks are committed and the build is green. Continue to [Phase 4](phase-04-space-lens-and-duplicate-finder.md).

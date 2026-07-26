# Phase 4: Space Lens + Duplicate Finder

Back to [plan.md](plan.md). Depends on [Phase 1](phase-01-cleancore-foundation.md) and [Phase 2](phase-02-design-system.md).

**Verification note:** same as Phase 3 — no App-layer unit test target; each task ends in a manual run-through.

---

### Task 11: Space Lens — re-skin onto the shared component

**Files:**
- Modify: `App/Features/SpaceLens/SpaceLensViewModel.swift`
- Modify: `App/Features/SpaceLens/SpaceLensView.swift`

**Interfaces:**
- Consumes: `DiskTreeScanner.buildTree(onProgress:)`'s reshaped `ScanProgress` callback (Phase 1, Task 3); `ScanProgressTracker`, `ScanProgressPanel` (Phase 2).
- Produces: nothing new for other tasks to consume — this is a same-behavior re-skin. `scannedItemCount` is removed; anything that referenced it is `viewModel.progressTracker.progress?.itemsProcessed` instead (nothing outside this module reads it today).

- [ ] **Step 1: Replace `scannedItemCount` with `progressTracker`**

In `App/Features/SpaceLens/SpaceLensViewModel.swift`, change the declaration:

```swift
    private(set) var scannedItemCount = 0
```

to:

```swift
    let progressTracker = ScanProgressTracker()
```

In `performScan()`, change:

```swift
    private func performScan() async {
        phase = .scanning
        errorMessage = nil
        scannedItemCount = 0

        let scanner = DiskTreeScanner(rootPath: rootPath)
        let result = await scanner.buildTree(onProgress: { [weak self] count in
            Task { @MainActor in self?.scannedItemCount = count }
        })
```

to:

```swift
    private func performScan() async {
        phase = .scanning
        errorMessage = nil
        progressTracker.start()

        let scanner = DiskTreeScanner(rootPath: rootPath)
        let result = await scanner.buildTree(onProgress: { [weak self] progress in
            Task { @MainActor in self?.progressTracker.record(progress) }
        })
```

(The rest of `performScan()` — the `guard !Task.isCancelled`, the `errorMessage = "Couldn't read \(rootPath)"` branch, `tree =`/`flatItems =`/`categoryTotals =` assignment, `phase = .loaded` — is unchanged.)

In `resetScanState()`, change:

```swift
        errorMessage = nil
        scannedItemCount = 0
        phase = .idle
```

to:

```swift
        errorMessage = nil
        progressTracker.reset()
        phase = .idle
```

- [ ] **Step 2: Update the scanning view**

In `App/Features/SpaceLens/SpaceLensView.swift`, replace `scanningContent`:

```swift
    private var scanningContent: some View {
        VStack(spacing: Theme.Spacing.lg) {
            ProgressView()
                .controlSize(.large)
                .tint(Theme.accent)
            if let progress = viewModel.progressTracker.progress {
                ScanProgressPanel(progress: progress)
            } else {
                Text("Scanning…")
                    .font(.system(size: Theme.TextSize.sm))
                    .foregroundStyle(Theme.muted)
            }
            Button("Cancel") { viewModel.cancelScan() }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
```

This preserves the exact original behavior (a spinner, "Scanning…" before the first 2,000-item tick, "Scanned N items…" after) — only the "Scanned N items…" text now renders through the shared `ScanProgressPanel` instead of a hand-rolled `Text`, and `totalItems` stays `nil` so no fabricated percentage ever appears (an arbitrary user-chosen directory's total is never knowable ahead of the walk).

- [ ] **Step 3: Regenerate the Xcode project and build**

Run: `xcodegen generate`
Run: `xcodebuild build -scheme SOSMac -configuration Debug`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Manual run-through**

Repeat the same check already done once for this module during initial investigation: launch the app, navigate to Space Lens, "Scan Home Folder", confirm the count-only progress still updates live and Cancel still returns to idle. Confirm the mapped treemap/inspector screen still renders after a completed scan.

- [ ] **Step 5: Commit**

```bash
git add App/Features/SpaceLens/SpaceLensViewModel.swift App/Features/SpaceLens/SpaceLensView.swift
git commit -m "refactor(space-lens): re-skin scanning progress onto the shared ScanProgressPanel"
```

---

### Task 12: Duplicate Finder — two-phase progress

**Files:**
- Modify: `App/Features/Duplicates/DuplicateFinderViewModel.swift`
- Modify: `App/Features/Duplicates/DuplicateFinderView.swift`

**Interfaces:**
- Consumes: `DuplicateFinder.findExactDuplicateGroups(onProgress:)` / `.findSimilarImageGroups(onProgress:)` (Phase 1, Task 5); `ScanProgressTracker`, `ScanProgressPanel` (Phase 2).

- [ ] **Step 1: Wire progress into the ViewModel**

In `App/Features/Duplicates/DuplicateFinderViewModel.swift`, add a stored property after `private var scanTask: Task<Void, Never>?`:

```swift
    let progressTracker = ScanProgressTracker()
```

In `performScan()`, add `progressTracker.start()` right after `skippedCount = 0`, and change:

```swift
            switch mode {
            case .exact:
                result = try await finder.findExactDuplicateGroups()
            case .similarImages:
                result = try await finder.findSimilarImageGroups()
            }
```

to:

```swift
            switch mode {
            case .exact:
                result = try await finder.findExactDuplicateGroups(onProgress: { [weak self] progress in
                    Task { @MainActor in self?.progressTracker.record(progress) }
                })
            case .similarImages:
                result = try await finder.findSimilarImageGroups(onProgress: { [weak self] progress in
                    Task { @MainActor in self?.progressTracker.record(progress) }
                })
            }
```

- [ ] **Step 2: Wire the scanning UI**

In `App/Features/Duplicates/DuplicateFinderView.swift`, replace `scanningView`:

```swift
    private var scanningView: some View {
        VStack(spacing: Theme.Spacing.lg) {
            ScanProgressPanel(
                progress: viewModel.progressTracker.progress,
                showCurrentPath: true,
                steps: scanningSteps
            )
            .frame(maxWidth: 420)

            Button("Cancel") { viewModel.cancelScan() }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Spacing.giant)
    }

    /// `DuplicateFinder`'s listing phase (`SizeGrouper`/the image-collecting
    /// walk) never calls `onProgress` at all — only the hashing loop does,
    /// and always with a real `totalItems` once it starts — so `progress`
    /// being non-nil is exactly "hashing has begun," with no in-between
    /// state to special-case.
    private var scanningSteps: [ScanProgressPanel.StepModel] {
        let isHashing = viewModel.progressTracker.progress != nil
        return [
            .init(name: "Scanning \(viewModel.mode.rawValue.lowercased())…", meta: nil, state: isHashing ? .done : .active),
            .init(
                name: viewModel.mode == .exact ? "Hashing files…" : "Comparing images…",
                meta: isHashing ? nil : "Waiting…",
                state: isHashing ? .active : .pending
            )
        ]
    }
```

- [ ] **Step 3: Regenerate the Xcode project and build**

Run: `xcodegen generate`
Run: `xcodebuild build -scheme SOSMac -configuration Debug`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Manual run-through**

1. Launch the app, navigate to Duplicate Finder, click "Start Scan" (Exact Duplicates mode) on a real folder with at least one duplicate pair.
2. Confirm: the first row ("Scanning exact duplicates…") shows active, then flips to done once hashing begins; the second row ("Hashing files…") flips from pending → active with a live percentage bar and a live current-filename line.
3. Switch to Similar Images mode, re-scan, confirm the second row reads "Comparing images…" and behaves the same way.
4. Confirm Cancel still works mid-scan, and a completed scan still reaches the Results screen with correct duplicate groups and `skippedCount`.

- [ ] **Step 5: Commit**

```bash
git add App/Features/Duplicates/DuplicateFinderViewModel.swift App/Features/Duplicates/DuplicateFinderView.swift
git commit -m "feat(duplicate-finder): show live two-phase (listing/hashing) scan progress"
```

---

Phase 4 complete once both tasks are committed and the build is green. Continue to [Phase 5](phase-05-cloud-and-smart-care.md).

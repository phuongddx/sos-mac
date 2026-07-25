# Phase 4: Performance Module + Menu Bar Helper

## Context
First phase touching low-level system APIs (IOKit, sysctl, mach) and the first to need the Privileged Helper (Phase 8) for root-only operations. Also introduces the menu-bar-resident auxiliary process.

## Requirements
### Metrics engine
- CPU/RAM: `host_statistics64` (`HOST_CPU_LOAD_INFO`, `HOST_VM_INFO64`) via `mach_host`.
- Per-process info: `proc_listpids` + `proc_pidinfo` (or `NSRunningApplication` for user-facing app list + `libproc` for numeric detail).
- Disk/network/swap/load average/boot time: `sysctl` (`vm.swapusage`, `net.*`, `kern.boottime`, etc.) via a typed Swift wrapper — do not scatter raw `sysctlbyname` calls across the codebase, centralize in one `SysctlReader`.
- Temperature/GPU/SMC: IOKit (`IOServiceMatching`, SMC key reads). Apple Silicon uses a different SMC access path than Intel — must branch on `sysctl hw.optional.arm64` (or equivalent) and gracefully report "unavailable" rather than crash on unsupported hardware.

### Login Items / Launch Agents management
- Read `~/Library/LaunchAgents`, `/Library/LaunchAgents`, `/Library/LaunchDaemons` for a list, cross-reference with `SMAppService` for entries this app or user can manage.
- Use `SMAppService` for toggling — **not** the deprecated `SMLoginItemSetEnabled`.

### "Purge RAM" / "Flush DNS" actions
- These are literally `purge` and `dscacheutil -flushcache` — both need root. Route through the Phase 8 privileged helper's XPC interface; do not attempt `AuthorizationExecuteWithPrivileges` (deprecated/removed) or ask the user's admin password directly in-process.

### Menu Bar Helper
- Separate lightweight app target (own bundle, launched via `SMAppService.loginItem` or a "Launch at Login" toggle) hosting an `NSStatusItem` showing live CPU/RAM/Disk.
- Communicates with the main app (if running) or runs standalone reading the same `CleanCore` metrics engine directly — no IPC needed if it just links `CleanCore` itself.

## Files to create
- `Packages/CleanCore/Sources/CleanCore/Performance/SysctlReader.swift`
- `Packages/CleanCore/Sources/CleanCore/Performance/MachHostStats.swift`
- `Packages/CleanCore/Sources/CleanCore/Performance/IOKitSensors.swift`
- `Packages/CleanCore/Sources/CleanCore/Performance/LoginItemsManager.swift`
- `App/Features/Performance/PerformanceView.swift` + `PerformanceViewModel.swift`
- `MenuBarHelper/MenuBarHelperApp.swift` (new Xcode target)
- `MenuBarHelper/StatusItemController.swift`

## Implementation steps
1. `SysctlReader`: generic `func read<T>(_ name: String) -> T?` wrapping `sysctlbyname`, typed call sites for each metric needed.
2. `MachHostStats`: wrap `host_statistics64` for CPU load and `host_statistics64`/`task_info` for memory pressure/free/wired/compressed.
3. `IOKitSensors`: SMC key read helper; explicit Apple Silicon vs Intel branch; return `nil`/`.unavailable` rather than throw on unsupported keys.
4. `LoginItemsManager`: enumerate + `SMAppService.mainApp`/`.agent(plistName:)`/`.daemon(plistName:)` register/unregister calls.
5. Build `PerformanceViewModel` polling metrics on a timer (e.g. 1-2s interval) via `Task` + `AsyncStream`, cancel cleanly on view disappear — this is a classic energy-drain spot (per the research doc's own Protection/Performance risk notes), so the polling interval and lifecycle must be disciplined.
6. New Xcode target `MenuBarHelper`: `LSUIElement = true` (no Dock icon), `NSStatusItem` with a text/icon readout, links `CleanCore` directly for metrics — reuse, don't reimplement.
7. Wire "Purge RAM"/"Flush DNS" buttons to call the Phase 8 XPC client; until Phase 8 exists, stub with a disabled button + tooltip explaining the pending dependency (don't fake success).

## Tests / validation
- `SysctlReaderTests`/`MachHostStatsTests`: assert values are in sane ranges (CPU 0-100%, memory ≤ physical RAM) on the actual test machine — these are integration-style tests, acceptable here since there's no meaningful way to mock `sysctl`.
- `LoginItemsManagerTests`: register a harmless test `SMAppService.agent`, assert it appears/disappears correctly, clean up in `tearDown`.
- Manual: confirm Activity-Monitor-comparable CPU/RAM numbers are in the same ballpark (not required to match exactly — different sampling windows).
- Manual: menu bar helper launches independently, shows live-updating numbers, doesn't leak memory over a multi-hour run (check via Instruments).

## Risks / rollback
- IOKit/SMC access is the most likely place for an unsupported-hardware crash — every sensor read must have a graceful "N/A" fallback, tested on at least one Apple Silicon and one Intel Mac if available.
- Menu bar helper polling too aggressively is a battery-life complaint waiting to happen — default to a conservative interval, let the user speed it up if they want.
- Rollback: Performance tab and menu bar helper are both independently disable-able without touching other modules.

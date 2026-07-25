# Phase 8: Privileged Helper Tool

## Context
Security-sensitive infrastructure phase. Needed by Phase 1 (root-owned cache cleanup), Phase 4 (purge/DNS flush, system LaunchDaemons), and potentially Phase 7 (system-level quarantine actions). Build this with a minimal, explicit op-set — do not create a generic "run arbitrary root command" XPC endpoint, which would be a serious local-privilege-escalation attack surface.

## Requirements
- Separate signed executable (own bundle ID, own entitlements) registered via `SMAppService.daemon(plistName:)` — **not** the deprecated `SMJobBless`.
- XPC communication only, with a strictly typed protocol (`NSXPCInterface` or a Swift `distributed actor`-style typed protocol) exposing a fixed, small set of operations: `trashSystemPath(_:)`, `purgeMemory()`, `flushDNSCache()`, `manageSystemDaemon(plistPath:action:)`. No generic shell-command passthrough.
- Every XPC call must validate its input server-side (in the helper), not trust the client app blindly — e.g. `trashSystemPath` should reject paths outside an explicit allowlist of directories this app is entitled to touch, even though the main app's UI already restricts what it sends.
- Helper installation/removal flow: prompt the user once via the standard `SMAppService` authorization UI, handle the "already installed"/"needs approval in System Settings" states explicitly (this is the most common integration bug — `SMAppService` requires the user to approve in System Settings > Login Items, and apps often don't handle the pending-approval state gracefully).

## Files to create
- New Xcode target: `PrivilegedHelper` (daemon), with `Info.plist` + `launchd.plist` for `SMAppService.daemon`.
- `PrivilegedHelper/HelperXPCProtocol.swift` (shared, imported by both app and helper targets)
- `PrivilegedHelper/HelperXPCListener.swift`
- `PrivilegedHelper/HelperOperations.swift` (the actual privileged operations, each with its own input validation)
- `App/Services/PrivilegedHelperClient.swift` (app-side XPC connection wrapper + install/status check)

## Implementation steps
1. Create the `PrivilegedHelper` target as a command-line tool / daemon, code-signed with the same team ID, embedded in the main app's `Contents/Library/LaunchDaemons`.
2. Define `HelperXPCProtocol` as an `@objc` protocol (required for `NSXPCInterface`) with the fixed op-set from Requirements — resist the urge to add a catch-all method.
3. Implement `HelperXPCListener` accepting connections, validating the caller's code signature (via `SecCodeCopyGuestWithAttributes`/`SecCodeCheckValidity` against the expected main-app identifier) before servicing any request — don't just trust "something connected to my XPC socket."
4. Implement each operation in `HelperOperations` with explicit path/action allowlisting server-side.
5. `PrivilegedHelperClient` (app side): `SMAppService.daemon(plistName:).register()`, poll/observe `.status` for `.enabled`/`.requiresApproval`/`.notFound`, surface a clear in-app prompt directing the user to System Settings when approval is pending (don't silently fail).
6. Wire Phase 1's system-cache cleanup and Phase 4's purge/flush-DNS buttons to `PrivilegedHelperClient` now that it exists.

## Tests / validation
- `HelperOperationsTests`: unit-test the input-validation logic in isolation (path allowlist rejection, action allowlist rejection) without needing a live XPC connection.
- Integration test (manual, since XPC + `SMAppService` needs a real signed build and System Settings interaction): install helper, confirm System Settings shows it, confirm each operation succeeds end-to-end, confirm uninstalling the app also offers/handles helper removal (don't leave an orphaned root-privileged daemon behind after uninstall — this would itself be a bug the Uninstaller module should catch for *this app itself*).
- Security review checklist before shipping: caller code-signature validation is actually enforced (test by attempting a call from an unsigned/different-identity test harness and confirming rejection).

## Risks / rollback
- This is the single highest-blast-radius component in the app — a bug here runs as root. Keep the op-set minimal and audited; every new privileged operation added in future phases should be a deliberate, reviewed addition to `HelperXPCProtocol`, not an incidental one.
- Orphaned daemon risk: ensure the app's own uninstall path (and ideally a Sparkle-driven update) properly manages helper lifecycle — an unremovable root daemon left behind after the user deletes the app is both a security and a reputation problem.
- Rollback: if a bug is found post-ship, the daemon can be remotely disabled by not shipping new signature/version approval — but a live security issue in an already-installed daemon may require an emergency update via Sparkle, so keep the update channel (Phase 9) working before this phase ships to real users.

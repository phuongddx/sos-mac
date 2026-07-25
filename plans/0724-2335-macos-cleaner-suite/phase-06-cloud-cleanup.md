# Phase 6: Cloud Cleanup (Google Drive, Dropbox, OneDrive, iCloud)

## Context
First phase depending entirely on third-party infrastructure (OAuth apps, external rate limits) rather than local system APIs. **Blocking prerequisite**: OAuth app registration with each provider must happen before coding starts (see Open Question 3 in plan.md) — production-tier API access review can take days to weeks.

## Requirements
- Google Drive, Dropbox, Microsoft Graph (OneDrive): real OAuth2 + REST APIs — list files without downloading content, delete/trash via API.
- iCloud Drive: **no public third-party API** — handled differently, by reading the locally-synced `~/Library/Mobile Documents` tree (same `FTSWrapper`/Junk-Scanner-style local scan as other modules, NOT a network call). This must be visually/behaviorally distinguished in the UI so users understand iCloud cleanup works differently (local-sync-state based) from the other three (true cloud API based).
- Duplicate detection reuses Phase 3's `DuplicateFinder` logic, but matching on API-provided metadata (name, size, hash if the provider exposes one) instead of downloading files to hash locally — bandwidth matters here in a way it doesn't for local scans.
- Actions offered per duplicate/cloud-only file: delete from cloud, "unsync" (remove local copy, keep cloud — only meaningful for Drive/Dropbox/OneDrive desktop-sync folders, not the API-only path), or delete both.
- Rate-limit handling: exponential backoff + pagination for all three real APIs; never a naive tight-loop `while (hasMore)`.

## Files to create
- `Packages/CleanCore/Sources/CleanCore/Cloud/CloudProvider.swift` (protocol: `authenticate`, `listFiles`, `delete`, paginated)
- `Packages/CleanCore/Sources/CleanCore/Cloud/GoogleDriveProvider.swift`
- `Packages/CleanCore/Sources/CleanCore/Cloud/DropboxProvider.swift`
- `Packages/CleanCore/Sources/CleanCore/Cloud/OneDriveProvider.swift`
- `Packages/CleanCore/Sources/CleanCore/Cloud/ICloudLocalScanner.swift` (local-only, conforms to `Scanner` not `CloudProvider`)
- `Packages/CleanCore/Sources/CleanCore/Cloud/OAuthTokenStore.swift` (Keychain-backed)
- `App/Features/CloudCleanup/CloudCleanupView.swift` + per-provider connect flows

## Implementation steps
1. Register OAuth apps: Google Cloud Console (Drive API scope `drive.readonly` + `drive.file` or full `drive` depending on delete needs), Dropbox App Console, Azure AD app registration (Graph `Files.ReadWrite`) — **do this before writing provider code**, since redirect URI / bundle ID / client ID values are needed in the app itself.
2. Implement OAuth2 flow using `ASWebAuthenticationSession` (the standard macOS-native OAuth UI, handles the redirect capture) — do not build a custom embedded web view for login.
3. `OAuthTokenStore`: store refresh/access tokens in Keychain, never `UserDefaults` or a plist.
4. Implement each `CloudProvider` conformance: `listFiles` paginated with backoff, `delete` via the provider's trash/delete endpoint (prefer trash/recycle endpoints over permanent delete where the API offers one, mirroring the local `trashItem` philosophy).
5. `ICloudLocalScanner`: read `~/Library/Mobile Documents/<container>/`, using the same `FTSWrapper` + `Cleaner.clean` (local trash) path as every other local module — this is just another `Scanner`/`Cleaner` pair, not new infrastructure.
6. Wire duplicate detection to call `DuplicateFinder`'s grouping logic against `CloudProvider`-sourced metadata instead of local `ScanItem`s (may need a small protocol adjustment in Phase 3's `DuplicateFinder` to accept a metadata source, not just local `FTSWrapper` output — note this as a small retrofit to Phase 3, not a rebuild).

## Tests / validation
- `OAuthTokenStoreTests`: store/retrieve/delete round-trip against a test Keychain group.
- Provider tests: mock HTTP responses (URLProtocol stub) for pagination/backoff behavior — never hit real provider APIs in automated tests (would burn quota and risk flaky CI).
- Manual: connect a real test account per provider, confirm list/delete works and rate-limit backoff triggers correctly under a forced 429 response (can simulate via a proxy or a deliberately tight test loop against a low-quota test project).
- `ICloudLocalScannerTests`: fixture directory mimicking `Mobile Documents` structure, standard `Scanner`/`Cleaner` test pattern from earlier phases.

## Risks / rollback
- Third-party API changes/rate-limit policy changes are out of this app's control — build providers behind the `CloudProvider` protocol so a broken provider can be disabled independently without affecting the other three.
- OAuth app review/verification (especially Google's "unverified app" restrictions on sensitive scopes) can block real users even after code is done — budget calendar time for this, not just engineering time.
- Rollback: each provider is independently toggleable; a broken/revoked OAuth app for one provider doesn't take down the others.

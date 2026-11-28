# Mac App Store (MAS) target — `SOSMacMAS`

The `SOSMacMAS` scheme builds a sandboxed Mac App Store variant of the app from
the same `App/` sources. The Developer ID / DMG build (`SOSMac` scheme,
embedded `PrivilegedHelper`, ad-hoc "Sign to Run Locally" + hardened runtime)
is unchanged: same scheme, same signing, same helper embedding, same behavior.

## What changes in MAS

| Feature | Dev (DMG) build | MAS build |
|---|---|---|
| App Sandbox | off | on (`SOSMacMAS.entitlements`) |
| User-selected folders | not needed (full disk access via user grant of the home dir at first scan) | NSOpenPanel grants + security-scoped bookmarks (`MASAccessStore`) |
| Junk & Cache (user rules) | `~`-rooted allowlist | same 3 user rules rooted at the granted home (`JunkRule.sandboxAllowlist`) |
| Junk — System Caches (`/Library/Caches`) | PrivilegedHelper `trashSystemPath` | dropped (rule absent) |
| Smart Care | home-rooted junk + duplicates | same, gated on the home grant |
| Duplicate Finder | `NSHomeDirectory()` root | granted home root |
| Space Lens | NSOpenPanel, no persistence | NSOpenPanel + app-scope bookmark (persists across launches) |
| Uninstaller / Updater | `/Applications` + `~/Applications` | granted Applications folder (plus `~/Applications` under the granted home) |
| Protection | 6 locations incl. `/Library/Launch*` | 4 user-domain locations rooted at the granted home (`ProtectionLocation.sandboxAllowlist`) |
| Performance — Free RAM / Flush DNS | PrivilegedHelper | hidden (no helper in MAS) |
| Performance — launch agents list | reads `/Library/Launch*` | hidden (not readable in sandbox) |
| Performance — Open at login (SMAppService.mainApp), menu bar widget | works | works (helper is embedded with its own sandbox entitlement) |
| Cloud Cleanup | OAuth provider flows | hidden from sidebar + Dashboard (out of scope for v1 MAS) |
| Privacy manifest | not bundled | `App/Resources/PrivacyInfo.xcprivacy` (required-reason APIs below) |
| Category / export compliance | — | `public.app-category.utilities`, `ITSAppUsesNonExemptEncryption = NO` |

Gating is compile-time in the app layer only (`SWIFT_ACTIVE_COMPILATION_CONDITIONS = MAS_BUILD`);
CleanCore compiles identically for both targets — sandbox scan roots are runtime-injected.

## Entitlements (MAS)

- `com.apple.security.app-sandbox` = true
- `com.apple.security.files.user-selected.read-write` = true
- `com.apple.security.files.bookmarks.app-scope` = true
- `com.apple.security.network.client` = true — the Updater's appcast checks
  (URLSession, read-only) are the only network use once Cloud Cleanup is
  hidden; without it every check silently fails.

The embedded `MenuBarHelperMAS.app` carries its own `app-sandbox` entitlement:
it is launched standalone (NSWorkspace), so it must not use the `inherit`
entitlement that only directly-spawned child processes can use.

## Privacy manifest (required-reason APIs)

| API category | Reasons | Where used |
|---|---|---|
| FileTimestamp | C617.1, 3B52.1, DDA9.1 | FTS walker reads mtime/atime for severity + review; user-granted folders (3B52.1) and display to the person (DDA9.1) |
| DiskSpace | 85F4.1 | sidebar footer / metrics display |
| UserDefaults | CA92.1 | bookmark store (app-private keys only) |
| SystemBootTime | 35F9.1 | Performance uptime ("running since") |

No tracking, no tracking domains, no collected data types.

## Static libraries

The YARA stack is vendored in `Packages/CleanCore/Vendor/` (see
`Vendor/README.md`): arm64-only archives of yara 4.6.0 (BSD-3-Clause),
openssl@4 4.1.0 (Apache-2.0), libmagic 5.48 (BSD-2-Clause), jansson 2.15.1
(MIT). This makes CI and the MAS build hermetic — no `/opt/homebrew` prefix,
no separately-signed dylibs (the library-validation crash class), permissive
licenses. YARA rules ship in the bundle as before.

## Export

`Scripts/ExportOptions-MAS.plist` (`method=app-store-connect`,
`signingStyle=automatic`). Do not upload from CI; export locally and submit
through Transporter/App Store Connect after Phương configures signing.

## What Phương must do on App Store Connect / Apple Developer

1. Create the app record (`com.nextlabs.sosmac`), category Utilities.
2. Apple Distribution + Mac Installer Distribution certificates; a Mac App
   Store provisioning profile for the bundle id.
3. Privacy nutrition label (matches `PrivacyInfo.xcprivacy`: no collection).
4. Export compliance: answer the ASC questionnaire consistently with
   `ITSAppUsesNonExemptEncryption = NO` — the app only hashes (SHA-256/MD5 via
   the vendored libcrypto) and verifies Ed25519 signatures for malware
   detection; it never encrypts user data.
5. Screenshots from the MAS build, not the DMG build.
6. Sign the Paid Applications agreement, tax + banking before IAP/submit.

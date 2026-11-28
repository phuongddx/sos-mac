# Vendored static libraries (arm64)

The four static archives YARA's C wrapper (`CYara`) links against, vendored so
the package — and the Mac App Store (MAS) target that builds from it — is
hermetic: no Homebrew prefix on the build machine, no `/opt/homebrew` absolute
paths (which also broke CI and archive relocation), and no separately signed
non-platform dylibs (the library-validation crash of 2026-11-27).

| Archive | Formula | Version | License | Size |
|---|---|---|---|---|
| `lib/libyara.a` | yara | 4.6.0 | BSD-3-Clause | 888 KB |
| `lib/libcrypto.a` | openssl@4 | 4.1.0 | Apache-2.0 | 8.2 MB |
| `lib/libmagic.a` | libmagic | 5.48 | BSD-2-Clause / public domain | 208 KB |
| `lib/libjansson.a` | jansson | 2.15.1 | MIT | 120 KB |

`include/` holds the matching YARA 4.6.0 public headers (`yara.h` plus the `yara/` directory, exactly as the formula installs them). All four
licenses are permissive and allow redistribution inside a binary; the licenses
above are declared in the app's About/credits path. `libmagic`'s compression
backends (`-llzma -lbz2 -lz`) still resolve to the platform dylibs, which the
MAS sandbox and library validation both accept.

All archives are **arm64-only**, matching the project-wide
`EXCLUDED_ARCHS: x86_64` setting: Homebrew bottles are arm64-only, and Apple's
September 2026 guidance is that Mac apps may ship arm64-only (macOS 27 is
Apple silicon only). Intel support would require rebuilding these four from
source as universal/x86_64 archives.

## Regenerating

On an Apple Silicon Mac with Homebrew. Note yara 4.6.0 is built against
openssl@4 (4.1.0): the openssl@3 (3.6.4) archive is missing the
`OPENSSL_sk_set_*_thunks` symbols yara references, so vendor openssl@4's
libcrypto even if `brew install yara` also pulls openssl@3:

```sh
brew install yara openssl@4 libmagic jansson
cp /opt/homebrew/opt/yara/lib/libyara.a        Vendor/lib/
cp /opt/homebrew/opt/openssl@4/lib/libcrypto.a Vendor/lib/
cp /opt/homebrew/opt/libmagic/lib/libmagic.a   Vendor/lib/
cp /opt/homebrew/opt/jansson/lib/libjansson.a  Vendor/lib/
cp /opt/homebrew/opt/yara/include/yara.h      Vendor/include/
cp -R /opt/homebrew/opt/yara/include/yara      Vendor/include/yara
for f in Vendor/lib/*.a; do lipo -archs "$f"; done   # expect: arm64
```

After regenerating, update the versions in the table above and run
`cd Packages/CleanCore && swift build && swift test`.

## Why not xcframeworks

An .xcframework per library (four wrappers plus header/module maps) adds
~9.5 MB of duplicates for no benefit while the project is arm64-only: SwiftPM
consumes the archives directly via `unsafeFlags` exactly as before, only with
repo-relative paths resolved from `#filePath` in `Package.swift`.

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CleanCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CleanCore", targets: ["CleanCore"])
    ],
    targets: [
        .target(name: "CFTS"),
        .target(
            name: "CYara",
            cSettings: [
                .unsafeFlags([
                    "-I/opt/homebrew/opt/yara/include"
                ])
            ],
            linkerSettings: [
                .unsafeFlags([
                    // Statically link the whole yara stack instead of Homebrew's
                    // libyara.10.dylib. Release builds are ad-hoc signed with the
                    // hardened runtime ("Sign to Run Locally" + ENABLE_HARDENED_RUNTIME),
                    // and library validation rejects every separately signed
                    // non-platform dylib ("different Team IDs"), which crashed the
                    // app in dyld before any window appeared (2026-11-27). With the
                    // static archives the only dylibs left are /usr/lib system
                    // libraries — platform binaries, which library validation always
                    // accepts. The formulas are yara's declared dependencies, so
                    // `brew install yara` provides them. Link the openssl@4 keg,
                    // not openssl@3: yara 4.6.0's Homebrew bottle is built against
                    // openssl@4 (its libyara.a references _OPENSSL_sk_set_*_thunks,
                    // symbols that only exist in OpenSSL 4.x) — pointing at the
                    // openssl@3 archive fails at link time with exactly those
                    // undefined symbols (CI, 2026-11-27).
                    "/opt/homebrew/opt/yara/lib/libyara.a",
                    "/opt/homebrew/opt/openssl@4/lib/libcrypto.a",
                    "/opt/homebrew/opt/libmagic/lib/libmagic.a",
                    "/opt/homebrew/opt/jansson/lib/libjansson.a",
                    // libmagic's compression backends (platform dylibs).
                    "-llzma",
                    "-lbz2",
                    "-lz"
                ])
            ]
        ),
        .target(
            name: "CleanCore",
            dependencies: ["CFTS", "CYara"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "CleanCoreTests",
            dependencies: ["CleanCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)

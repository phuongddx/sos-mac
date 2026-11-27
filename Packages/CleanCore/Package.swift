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
                    // accepts. The four formulas are yara's declared dependencies,
                    // so `brew install yara` provides them.
                    "/opt/homebrew/opt/yara/lib/libyara.a",
                    "/opt/homebrew/opt/openssl@3/lib/libcrypto.a",
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

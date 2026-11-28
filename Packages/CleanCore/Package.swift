// swift-tools-version: 6.0
import Foundation
import PackageDescription

// Vendored, repo-relative static archives (see Vendor/README.md). SwiftPM's
// unsafeFlags cannot use relative paths, so the manifest anchors on #filePath —
// the Package.swift manifest itself — and joins the Vendor directory next to it.
// This replaces the previous /opt/homebrew absolute paths, which only linked on
// machines with the exact Homebrew prefix and broke CI/archive relocation.
let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let vendorRoot = packageRoot.appendingPathComponent("Vendor")

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
                    "-I\(vendorRoot.appendingPathComponent("include").path)"
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
                    // accepts. The archives are vendored in Vendor/ (BSD/Apache/MIT,
                    // permissive) so CI and the Mac App Store target build hermetically;
                    // yara's declared dependencies are libcrypto, libmagic and jansson.
                    vendorRoot.appendingPathComponent("lib/libyara.a").path,
                    vendorRoot.appendingPathComponent("lib/libcrypto.a").path,
                    vendorRoot.appendingPathComponent("lib/libmagic.a").path,
                    vendorRoot.appendingPathComponent("lib/libjansson.a").path,
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

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
                    "-I/opt/homebrew/opt/yara/include",
                    "-I/usr/local/opt/yara/include"
                ])
            ],
            linkerSettings: [
                .linkedLibrary("yara"),
                .unsafeFlags([
                    "-L/opt/homebrew/opt/yara/lib",
                    "-L/usr/local/opt/yara/lib"
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

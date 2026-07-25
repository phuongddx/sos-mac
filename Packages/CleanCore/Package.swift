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
            name: "CleanCore",
            dependencies: ["CFTS"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "CleanCoreTests",
            dependencies: ["CleanCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)

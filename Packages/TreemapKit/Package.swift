// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TreemapKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TreemapKit", targets: ["TreemapKit"])
    ],
    targets: [
        .target(
            name: "TreemapKit",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "TreemapKitTests",
            dependencies: ["TreemapKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)

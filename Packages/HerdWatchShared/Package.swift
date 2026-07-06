// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HerdWatchShared",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "HerdWatchShared", targets: ["HerdWatchShared"]),
    ],
    targets: [
        .target(
            name: "HerdWatchShared",
            path: "Sources/HerdWatchShared"
        ),
        .testTarget(
            name: "HerdWatchSharedTests",
            dependencies: ["HerdWatchShared"],
            path: "Tests/HerdWatchSharedTests"
        ),
    ]
)

// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ProsperPlayer",
    platforms: [
        .iOS(.v18)
    ],
    products: [
        // Main library product
        .library(
            name: "AudioServiceKit",
            targets: ["AudioServiceKit"]
        ),
        // Core domain layer
        .library(
            name: "AudioServiceCore",
            targets: ["AudioServiceCore"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/sideeffect-io/AsyncExtensions.git", from: "0.5.2")
    ],
    targets: [
        // Core domain layer - no dependencies
        .target(
            name: "AudioServiceCore",
            dependencies: [],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        
        // Main implementation layer
        .target(
            name: "AudioServiceKit",
            dependencies: [
                "AudioServiceCore",
                .product(name: "AsyncExtensions", package: "AsyncExtensions")
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
                // Uncomment to enable all diagnostics (state transitions, timing, AsyncStream monitoring, queue metrics):
                .define("ENABLE_DIAGNOSTICS")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)

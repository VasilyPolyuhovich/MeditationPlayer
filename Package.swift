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
    dependencies: [],
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
            dependencies: ["AudioServiceCore"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        
        // Integration Tests
        .testTarget(
            name: "AudioServiceKitIntegrationTests",
            dependencies: ["AudioServiceKit", "AudioServiceCore"],
            resources: [
                .copy("TestResources")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)

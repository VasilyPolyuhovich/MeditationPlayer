// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ProsperPlayerDemoFeature",
    platforms: [.iOS(.v18)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "ProsperPlayerDemoFeature",
            targets: ["ProsperPlayerDemoFeature"]
        ),
    ],
    dependencies: [
        .package(name: "ProsperPlayer", path: "../..")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "ProsperPlayerDemoFeature",
            dependencies: [
                .product(name: "AudioServiceKit", package: "ProsperPlayer"),
                .product(name: "AudioServiceCore", package: "ProsperPlayer")
            ]
        ),
        .testTarget(
            name: "ProsperPlayerDemoFeatureTests",
            dependencies: [
                "ProsperPlayerDemoFeature"
            ]
        ),
    ]
)

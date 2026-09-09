// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ThermFlowCore",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "ThermFlowCore", targets: ["ThermFlowCore"])
    ],
    targets: [
        .target(name: "ThermFlowCore"),
        .testTarget(
            name: "ThermFlowCoreTests",
            dependencies: ["ThermFlowCore"]
        )
    ]
)

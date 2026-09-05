// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Tuck",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "TuckCore", targets: ["TuckCore"]),
        .executable(name: "TuckApp", targets: ["TuckApp"]),
        .executable(name: "tuck", targets: ["TuckCLI"])
    ],
    targets: [
        .target(name: "TuckCore"),
        .executableTarget(
            name: "TuckApp",
            dependencies: ["TuckCore"]
        ),
        .executableTarget(
            name: "TuckCLI",
            dependencies: ["TuckCore"]
        ),
        .testTarget(
            name: "TuckCoreTests",
            dependencies: ["TuckCore"]
        )
    ]
)

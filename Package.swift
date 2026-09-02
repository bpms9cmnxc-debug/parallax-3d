// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Parallax",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ParallaxCore", targets: ["ParallaxCore"]),
        .executable(name: "Parallax", targets: ["Parallax"]),
    ],
    targets: [
        .target(name: "ParallaxCore", path: "Sources/ParallaxCore"),
        .executableTarget(
            name: "Parallax",
            dependencies: ["ParallaxCore"],
            path: "Sources/Parallax"
        ),
        .testTarget(
            name: "ParallaxTests",
            dependencies: ["ParallaxCore"],
            path: "Tests/ParallaxTests"
        ),
    ]
)

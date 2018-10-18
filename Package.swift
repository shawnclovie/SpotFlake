// swift-tools-version:4.2
import PackageDescription

let package = Package(
    name: "SpotFlake",
    products: [
        .library(name: "SpotFlake", targets: ["SpotFlake"]),
    ],
    dependencies: [
    ],
    targets: [
        .target(name: "SpotFlake", dependencies: []),
        .testTarget(name: "SpotFlakeTests", dependencies: ["SpotFlake"]),
    ]
)

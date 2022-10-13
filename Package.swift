// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "SpotFlake",
	platforms: [
		.macOS(.v10_15),
		.iOS(.v11),
	],
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

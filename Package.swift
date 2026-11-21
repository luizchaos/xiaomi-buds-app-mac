// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RedmiBuds",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BudsKit", targets: ["BudsKit"]),
        .executable(name: "RedmiBuds", targets: ["RedmiBuds"]),
    ],
    targets: [
        .target(
            name: "BudsKit",
            linkerSettings: [.linkedFramework("IOBluetooth")]
        ),
        .executableTarget(
            name: "RedmiBuds",
            dependencies: ["BudsKit"]
        ),
        .testTarget(
            name: "BudsKitTests",
            dependencies: ["BudsKit"]
        ),
    ]
)

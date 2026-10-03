// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "StardropMac",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "StardropMac", targets: ["StardropMac"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "StardropMac",
            dependencies: [],
            path: "Sources/StardropMac"
        )
    ]
)

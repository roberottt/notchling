// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Notchling",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "NotchCore"),
        .executableTarget(name: "Notchling", dependencies: ["NotchCore"]),
        .testTarget(name: "NotchCoreTests", dependencies: ["NotchCore"]),
    ]
)

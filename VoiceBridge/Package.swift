// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VoiceBridge",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../Shared")],
    targets: [
        .executableTarget(name: "VoiceBridge", dependencies: [.product(name: "LocalSupport", package: "Shared")], path: "Sources/VoiceBridge")
    ]
)

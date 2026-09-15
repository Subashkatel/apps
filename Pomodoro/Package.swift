// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Pomodoro",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../Shared")],
    targets: [
        .executableTarget(name: "Pomodoro", dependencies: [.product(name: "LocalSupport", package: "Shared")], path: "Sources/Pomodoro")
    ]
)

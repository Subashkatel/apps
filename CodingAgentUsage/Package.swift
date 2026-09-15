// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CodingAgentUsage",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../Shared")],
    targets: [
        .executableTarget(name: "CodingAgentUsage", dependencies: [.product(name: "LocalSupport", package: "Shared")], path: "Sources/CodingAgentUsage")
    ]
)

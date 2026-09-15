// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PaperNotes",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../Shared")],
    targets: [
        .executableTarget(name: "PaperNotes", dependencies: [.product(name: "LocalSupport", package: "Shared")], path: "Sources/PaperNotes")
    ]
)

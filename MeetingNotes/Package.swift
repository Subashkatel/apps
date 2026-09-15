// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "MeetingNotes", platforms: [.macOS("15.0")], dependencies: [.package(path: "../Shared")], targets: [
    .systemLibrary(name: "CSQLite"),
    .executableTarget(name: "MeetingNotes", dependencies: ["CSQLite", .product(name: "LocalSupport", package: "Shared")])])

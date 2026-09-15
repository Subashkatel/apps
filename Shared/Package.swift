// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "LocalSupport", platforms: [.macOS(.v14)],
    products: [.library(name: "LocalSupport", targets: ["LocalSupport"])],
    targets: [.target(name: "LocalSupport"),
              .executableTarget(name: "LocalSupportChecks", dependencies: ["LocalSupport"],
                                path: "Tests/LocalSupportTests")])

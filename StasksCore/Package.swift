// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "StasksCore",
    platforms: [.macOS(.v15)],
    products: [.library(name: "StasksCore", targets: ["StasksCore"])],
    targets: [
        .target(name: "StasksCore", path: "Sources/StasksCore", swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "StasksCoreTests", dependencies: ["StasksCore"], path: "Tests/StasksCoreTests", swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)

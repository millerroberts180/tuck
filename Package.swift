// swift-tools-version:5.10
import PackageDescription

// No third-party dependencies. Release builds favour a small binary and memory footprint (-Osize);
// scripts/build-app.sh additionally strips symbols before bundling.
let releaseSize: [SwiftSetting] = [.unsafeFlags(["-Osize"], .when(configuration: .release))]

let package = Package(
    name: "Tuck",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Tuck", targets: ["TuckApp"]),
        .library(name: "TuckCore", targets: ["TuckCore"])
    ],
    targets: [
        // Models, the stream, placement geometry and service protocols. Foundation only.
        .target(name: "TuckCore", swiftSettings: releaseSize),
        // AppKit overlay (always on, layer-based), SwiftUI panel (loaded only while expanded).
        .executableTarget(name: "TuckApp", dependencies: ["TuckCore"], swiftSettings: releaseSize),
        .testTarget(name: "TuckCoreTests", dependencies: ["TuckCore"])
    ]
)

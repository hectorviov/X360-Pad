// swift-tools-version: 6.0
// The app's hardware-independent logic (the receiver's wire format, stick and trigger processing, button remapping, the DualSense reports), built and
// tested on its own with `swift test`. The app target (project.yml) compiles the same sources.
import PackageDescription

let package = Package(
    name: "X360PadCore",
    platforms: [.macOS(.v15)],
    products: [.library(name: "X360PadCore", targets: ["X360PadCore"])],
    targets: [
        .target(name: "X360PadCore", swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "X360PadCoreTests", dependencies: ["X360PadCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)

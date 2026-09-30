// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "LookFocus", platforms: [.macOS(.v14)],
    products: [.executable(name: "LookFocus", targets: ["LookFocus"])],
    targets: [
        .target(name: "FocusCore"),
        .target(name: "FocusVision", dependencies: ["FocusCore"]),
        .executableTarget(name: "LookFocus", dependencies: ["FocusCore", "FocusVision"]),
        .testTarget(name: "FocusCoreTests", dependencies: ["FocusCore", "FocusVision"])
    ]
)

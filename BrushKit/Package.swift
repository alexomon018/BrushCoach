// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "BrushKit",
    platforms: [
        .iOS(.v18),
        .watchOS(.v11),
        .macOS(.v14)
    ],
    products: [
        .library(name: "BrushKit", targets: ["BrushKit"]),
        .executable(name: "brush-replay", targets: ["BrushReplay"])
    ],
    targets: [
        .target(name: "BrushKit"),
        .executableTarget(name: "BrushReplay", dependencies: ["BrushKit"]),
        .testTarget(
            name: "BrushKitTests",
            dependencies: ["BrushKit"],
            resources: [.copy("Fixtures")]
        )
    ],
    swiftLanguageModes: [.v6]
)

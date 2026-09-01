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
        .library(name: "BrushDesign", targets: ["BrushDesign"]),
        .executable(name: "brush-replay", targets: ["BrushReplay"])
    ],
    targets: [
        .target(name: "BrushKit"),
        // Brand tokens only. Kept out of BrushKit so the domain package stays
        // free of SwiftUI and remains testable without a UI framework.
        .target(name: "BrushDesign"),
        .executableTarget(name: "BrushReplay", dependencies: ["BrushKit"]),
        .testTarget(
            name: "BrushKitTests",
            dependencies: ["BrushKit"],
            resources: [.copy("Fixtures")]
        )
    ],
    swiftLanguageModes: [.v6]
)

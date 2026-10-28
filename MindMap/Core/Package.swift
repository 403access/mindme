// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MindMapCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "MindMapCore", targets: ["MindMapCore"])
    ],
    targets: [
        .target(
            name: "MindMapCore",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(
            name: "MindMapCoreTests",
            dependencies: ["MindMapCore"],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedLibrary("sqlite3")]
        )
    ]
)

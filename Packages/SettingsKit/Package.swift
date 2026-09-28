// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "SettingsKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .watchOS(.v10),
        .tvOS(.v17),
        .visionOS(.v1)
    ],
    products: [
        .library(
            name: "SettingsKit",
            targets: ["SettingsKit"]
        ),
    ],
    targets: [
        .target(
            name: "SettingsKit"
        ),
    ]
)

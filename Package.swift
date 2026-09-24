// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "WindowsAltTabRedirect",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AltTabCore", targets: ["AltTabCore"]),
        .executable(name: "WindowsAltTabRedirect", targets: ["WindowsAltTabRedirect"]),
    ],
    targets: [
        .target(name: "AltTabCore"),
        .executableTarget(
            name: "WindowsAltTabRedirect",
            dependencies: ["AltTabCore"]
        ),
        .testTarget(
            name: "AltTabCoreTests",
            dependencies: ["AltTabCore"]
        ),
    ]
)

// swift-tools-version: 6.0

import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
]

let package = Package(
    name: "Murmur",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "Murmur", targets: ["Murmur"])
    ],
    targets: [
        .executableTarget(
            name: "Murmur",
            path: "Sources/Murmur",
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "MurmurTests",
            dependencies: ["Murmur"],
            path: "Tests/MurmurTests",
            swiftSettings: swiftSettings
        ),
    ]
)

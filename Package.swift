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
        .executable(name: "Murmur", targets: ["MurmurNext"])
    ],
    targets: [
        .executableTarget(
            name: "MurmurNext",
            path: "Sources/MurmurNext",
            swiftSettings: swiftSettings,
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "MurmurNextTests",
            dependencies: ["MurmurNext"],
            path: "Tests/MurmurNextTests",
            resources: [.copy("Fixtures")],
            swiftSettings: swiftSettings
        ),
    ]
)

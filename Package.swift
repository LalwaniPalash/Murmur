// swift-tools-version: 6.0

import PackageDescription
import Foundation

let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
]

// The whisper.cpp runtime is staged locally by script/stage_whisper_runtime.sh and is
// deliberately not checked in. Resolve it relative to this manifest so `swift build`
// links the resident engine, and fall back to a header-only build when the runtime is
// absent so a fresh clone can still compile and run the test suite.
let runtimeLibraryDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Vendor/Runtimes/arm64/lib")

let hasStagedRuntime = FileManager.default.fileExists(
    atPath: runtimeLibraryDirectory.appendingPathComponent("libwhisper.dylib").path
)

let whisperLinkerSettings: [LinkerSetting] = hasStagedRuntime
    ? [
        .unsafeFlags([
            "-L\(runtimeLibraryDirectory.path)",
            "-Xlinker", "-rpath", "-Xlinker", runtimeLibraryDirectory.path,
            "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Resources/Runtimes/arm64/lib",
        ]),
        .linkedLibrary("whisper"),
        .linkedLibrary("ggml"),
        .linkedLibrary("ggml-base"),
    ]
    : []

let whisperSwiftSettings: [SwiftSetting] = hasStagedRuntime
    ? swiftSettings + [.define("MURMUR_RESIDENT_WHISPER")]
    : swiftSettings

let package = Package(
    name: "Murmur",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "Murmur", targets: ["MurmurNext"]),
        .executable(name: "MurmurMLXWorker", targets: ["MurmurMLXWorker"]),
        .library(name: "MurmurQualityCore", targets: ["MurmurQualityCore"]),
        .executable(name: "murmur-quality", targets: ["MurmurQualityCLI"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/ml-explore/mlx-swift-lm",
            exact: "3.31.3"
        ),
        .package(
            url: "https://github.com/huggingface/swift-huggingface",
            exact: "0.9.0"
        ),
        .package(
            url: "https://github.com/huggingface/swift-transformers",
            exact: "1.3.0"
        ),
    ],
    targets: [
        .target(
            name: "MurmurMLXProtocol",
            path: "Sources/MurmurMLXProtocol",
            swiftSettings: swiftSettings
        ),
        .target(
            name: "CWhisper",
            path: "Sources/CWhisper",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "MurmurNext",
            dependencies: [
                "CWhisper",
                "MurmurQualityCore",
                "MurmurMLXProtocol",
                .product(name: "HuggingFace", package: "swift-huggingface"),
            ],
            path: "Sources/MurmurNext",
            resources: [.copy("Resources/Fonts")],
            swiftSettings: whisperSwiftSettings,
            linkerSettings: whisperLinkerSettings + [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "MurmurMLXWorker",
            dependencies: [
                "MurmurMLXProtocol",
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "Tokenizers", package: "swift-transformers"),
            ],
            path: "Sources/MurmurMLXWorker",
            swiftSettings: swiftSettings
        ),
        .target(
            name: "MurmurQualityCore",
            path: "Sources/MurmurQualityCore",
            swiftSettings: swiftSettings
        ),
        .executableTarget(
            name: "MurmurQualityCLI",
            dependencies: ["MurmurQualityCore"],
            path: "Sources/MurmurQualityCLI",
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "MurmurNextTests",
            dependencies: ["MurmurNext", "MurmurQualityCore", "MurmurMLXProtocol"],
            path: "Tests/MurmurNextTests",
            resources: [.copy("Fixtures")],
            swiftSettings: whisperSwiftSettings
        ),
        .testTarget(
            name: "MurmurQualityCoreTests",
            dependencies: ["MurmurQualityCore"],
            path: "Tests/MurmurQualityCoreTests",
            swiftSettings: swiftSettings
        ),
    ]
)

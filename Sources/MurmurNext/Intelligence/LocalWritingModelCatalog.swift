import CryptoKit
import Foundation

enum LocalWritingModelQuality: String, Codable, Equatable, Sendable {
    case experimental
}

enum LocalWritingModelTier: String, Codable, CaseIterable, Equatable, Sendable {
    case fastest
    case balanced
    case highestQuality
}

enum LocalWritingModelArchitecture: String, Codable, Equatable, Sendable {
    case qwen3
    case llama
}

struct LocalWritingModelFile: Equatable, Sendable {
    let relativePath: String
    let byteCount: Int64
    let sha256: String
}

struct LocalWritingModelManifest: Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let repository: String
    let revision: String
    let license: String
    let quality: LocalWritingModelQuality
    let tier: LocalWritingModelTier
    let architecture: LocalWritingModelArchitecture
    let supportedOperations: Set<WritingTransformationOperation>
    let estimatedMemoryMB: Int
    let files: [LocalWritingModelFile]

    init(
        id: String,
        displayName: String,
        repository: String,
        revision: String,
        license: String,
        quality: LocalWritingModelQuality,
        tier: LocalWritingModelTier = .fastest,
        architecture: LocalWritingModelArchitecture = .qwen3,
        supportedOperations: Set<WritingTransformationOperation> = [.professionalEmail, .semanticCommand],
        estimatedMemoryMB: Int = 512,
        files: [LocalWritingModelFile]
    ) {
        self.id = id
        self.displayName = displayName
        self.repository = repository
        self.revision = revision
        self.license = license
        self.quality = quality
        self.tier = tier
        self.architecture = architecture
        self.supportedOperations = supportedOperations
        self.estimatedMemoryMB = estimatedMemoryMB
        self.files = files
    }

    var byteCount: Int64 {
        files.reduce(0) { $0 + $1.byteCount }
    }

    static let qwen3_0_6B_4Bit = LocalWritingModelManifest(
        id: "mlx-community/Qwen3-0.6B-4bit",
        displayName: "Qwen3 0.6B · 4-bit",
        repository: "mlx-community/Qwen3-0.6B-4bit",
        revision: "73e3e38d981303bc594367cd910ea6eb48349da8",
        license: "Apache-2.0",
        quality: .experimental,
        tier: .fastest,
        architecture: .qwen3,
        supportedOperations: [.professionalEmail, .semanticCommand],
        estimatedMemoryMB: 720,
        files: [
            LocalWritingModelFile(
                relativePath: "added_tokens.json",
                byteCount: 707,
                sha256: "c0284b582e14987fbd3d5a2cb2bd139084371ed9acbae488829a1c900833c680"
            ),
            LocalWritingModelFile(
                relativePath: "config.json",
                byteCount: 937,
                sha256: "15d3ac26c043ae477273ed5802ee0f0b33bb14f18c9d3dd70910c02d906e3f1f"
            ),
            LocalWritingModelFile(
                relativePath: "merges.txt",
                byteCount: 1_671_853,
                sha256: "8831e4f1a044471340f7c0a83d7bd71306a5b867e95fd870f74d0c5308a904d5"
            ),
            LocalWritingModelFile(
                relativePath: "model.safetensors",
                byteCount: 335_450_584,
                sha256: "392e8d466d56100ada00eb82031fb854297fc9e389b7d303eba3af114e87bce2"
            ),
            LocalWritingModelFile(
                relativePath: "model.safetensors.index.json",
                byteCount: 49_731,
                sha256: "7b294141456f6904936db03c00bca50fb5f6198f652fe8483f9cd2a1018accfb"
            ),
            LocalWritingModelFile(
                relativePath: "special_tokens_map.json",
                byteCount: 613,
                sha256: "76862e765266b85aa9459767e33cbaf13970f327a0e88d1c65846c2ddd3a1ecd"
            ),
            LocalWritingModelFile(
                relativePath: "tokenizer.json",
                byteCount: 11_422_654,
                sha256: "aeb13307a71acd8fe81861d94ad54ab689df773318809eed3cbe794b4492dae4"
            ),
            LocalWritingModelFile(
                relativePath: "tokenizer_config.json",
                byteCount: 9_706,
                sha256: "253153d0738ceb4c668d2eff957714dd2bea0b56de772a9fdccd96cbf517e6a0"
            ),
            LocalWritingModelFile(
                relativePath: "vocab.json",
                byteCount: 2_776_833,
                sha256: "ca10d7e9fb3ed18575dd1e277a2579c16d108e32f27439684afa0e10b1440910"
            ),
        ]
    )

    static let llama3_2_1B_4Bit = LocalWritingModelManifest(
        id: "mlx-community/Llama-3.2-1B-Instruct-4bit",
        displayName: "Llama 3.2 1B Instruct · 4-bit",
        repository: "mlx-community/Llama-3.2-1B-Instruct-4bit",
        revision: "08231374eeacb049a0eade7922910865b8fce912",
        license: "Llama-3.2",
        quality: .experimental,
        tier: .balanced,
        architecture: .llama,
        supportedOperations: [.professionalEmail, .semanticCommand],
        estimatedMemoryMB: 1_150,
        files: [
            .init(relativePath: "config.json", byteCount: 1_121, sha256: "73bfb89e5a43c76ada2d7a9609862139578a71cfbb43e30bf5d4571026dd3741"),
            .init(relativePath: "model.safetensors", byteCount: 695_283_921, sha256: "35e396644bca888eec399f9c0f843ec7fa78b8f8c5e06841661be62b4edf96dd"),
            .init(relativePath: "model.safetensors.index.json", byteCount: 26_159, sha256: "437f66af94c5f921f4fbe465341bdee4dc6a37ab8f29bbb12fd7caad577dedd7"),
            .init(relativePath: "special_tokens_map.json", byteCount: 296, sha256: "6f38c73729248f6c127296386e3cdde96e254636cc58b4169d3fd32328d9a8ec"),
            .init(relativePath: "tokenizer.json", byteCount: 17_209_920, sha256: "6b9e4e7fb171f92fd137b777cc2714bf87d11576700a1dcd7a399e7bbe39537b"),
            .init(relativePath: "tokenizer_config.json", byteCount: 54_558, sha256: "022d5ae3df4737998ab97d8f31ac2bcb4c06dd8ebe5a8aba2b4aceef1e5ea7d3"),
        ]
    )

    static let qwen3_1_7B_4Bit = LocalWritingModelManifest(
        id: "mlx-community/Qwen3-1.7B-4bit",
        displayName: "Qwen3 1.7B · 4-bit",
        repository: "mlx-community/Qwen3-1.7B-4bit",
        revision: "3b1b1768f8f8cf8351c712464f906e86c2b8269e",
        license: "Apache-2.0",
        quality: .experimental,
        tier: .highestQuality,
        architecture: .qwen3,
        supportedOperations: [.professionalEmail, .semanticCommand],
        estimatedMemoryMB: 1_650,
        files: [
            .init(relativePath: "added_tokens.json", byteCount: 707, sha256: "c0284b582e14987fbd3d5a2cb2bd139084371ed9acbae488829a1c900833c680"),
            .init(relativePath: "config.json", byteCount: 937, sha256: "507a6701220524eb8b283425bf0856a9ae4f21f4052e563896ddd668994b1dc7"),
            .init(relativePath: "merges.txt", byteCount: 1_671_853, sha256: "8831e4f1a044471340f7c0a83d7bd71306a5b867e95fd870f74d0c5308a904d5"),
            .init(relativePath: "model.safetensors", byteCount: 968_080_210, sha256: "0e86d9677e519323849eac1bc272caae88567a481ff188c431f70be543d9995f"),
            .init(relativePath: "model.safetensors.index.json", byteCount: 49_731, sha256: "1e3058d4ba4b04e4de35b74467725cbef90ff022198404218e48f21adc9cfa15"),
            .init(relativePath: "special_tokens_map.json", byteCount: 613, sha256: "76862e765266b85aa9459767e33cbaf13970f327a0e88d1c65846c2ddd3a1ecd"),
            .init(relativePath: "tokenizer.json", byteCount: 11_422_654, sha256: "aeb13307a71acd8fe81861d94ad54ab689df773318809eed3cbe794b4492dae4"),
            .init(relativePath: "tokenizer_config.json", byteCount: 9_706, sha256: "253153d0738ceb4c668d2eff957714dd2bea0b56de772a9fdccd96cbf517e6a0"),
            .init(relativePath: "vocab.json", byteCount: 2_776_833, sha256: "ca10d7e9fb3ed18575dd1e277a2579c16d108e32f27439684afa0e10b1440910"),
        ]
    )

    static let supported = [qwen3_0_6B_4Bit, llama3_2_1B_4Bit, qwen3_1_7B_4Bit]
}

enum LocalWritingModelCatalogError: Error, Equatable, LocalizedError, Sendable {
    case unsupportedModel
    case invalidManifest
    case modelUnavailable
    case invalidStagingLocation
    case incompleteInstall
    case unexpectedFile
    case unsafeFile
    case sizeMismatch
    case checksumMismatch

    var errorDescription: String? {
        switch self {
        case .unsupportedModel: "That local writing model is not supported."
        case .invalidManifest: "The local writing model manifest is invalid."
        case .modelUnavailable: "The selected local writing model is not installed."
        case .invalidStagingLocation: "The local writing model was staged in an unsafe location."
        case .incompleteInstall: "The local writing model installation is incomplete."
        case .unexpectedFile: "The local writing model contains an unexpected file."
        case .unsafeFile: "The local writing model contains an unsafe file."
        case .sizeMismatch: "A local writing model file has the wrong size."
        case .checksumMismatch: "A local writing model file failed its integrity check."
        }
    }
}

protocol LocalWritingModelLocating: Sendable {
    func verifiedModelDirectory(identifier: String) throws -> URL
}

struct LocalWritingModelCatalog: LocalWritingModelLocating, Sendable {
    let rootDirectory: URL
    let manifests: [LocalWritingModelManifest]

    init(
        rootDirectory: URL = MurmurV2Paths.modelsDirectory.appendingPathComponent("Writing", isDirectory: true),
        manifests: [LocalWritingModelManifest] = LocalWritingModelManifest.supported
    ) {
        self.rootDirectory = rootDirectory.standardizedFileURL
        self.manifests = manifests
    }

    func manifest(identifier: String) -> LocalWritingModelManifest? {
        manifests.first { $0.id == identifier }
    }

    func installDirectory(for manifest: LocalWritingModelManifest) -> URL {
        let digest = SHA256.hash(data: Data(manifest.id.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return rootDirectory.appendingPathComponent(String(digest.prefix(24)), isDirectory: true)
    }

    func verifiedModelDirectory(identifier: String) throws -> URL {
        guard let manifest = manifest(identifier: identifier) else {
            throw LocalWritingModelCatalogError.unsupportedModel
        }
        let directory = installDirectory(for: manifest)
        guard FileManager.default.fileExists(atPath: directory.path) else {
            throw LocalWritingModelCatalogError.modelUnavailable
        }
        guard try validateInstalledModel(manifest, at: directory) else {
            throw LocalWritingModelCatalogError.incompleteInstall
        }
        return directory
    }

    @discardableResult
    func validateInstalledModel(
        _ manifest: LocalWritingModelManifest,
        at directory: URL
    ) throws -> Bool {
        let canonicalDirectory = directory.standardizedFileURL
        let expectedDirectory = installDirectory(for: manifest).standardizedFileURL
        guard canonicalDirectory == expectedDirectory else {
            throw LocalWritingModelCatalogError.unsafeFile
        }
        try validateDirectoryContents(manifest, at: canonicalDirectory)
        return true
    }

    func activate(
        _ manifest: LocalWritingModelManifest,
        stagedDirectory: URL
    ) throws -> URL {
        let canonicalStaged = stagedDirectory.standardizedFileURL
        guard canonicalStaged.deletingLastPathComponent() == rootDirectory else {
            throw LocalWritingModelCatalogError.invalidStagingLocation
        }
        let destination = installDirectory(for: manifest)
        guard canonicalStaged != destination else {
            throw LocalWritingModelCatalogError.invalidStagingLocation
        }
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)

        try validateDirectoryContents(manifest, at: canonicalStaged)

        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: canonicalStaged)
        } else {
            try FileManager.default.moveItem(at: canonicalStaged, to: destination)
        }
        guard try validateInstalledModel(manifest, at: destination) else {
            throw LocalWritingModelCatalogError.incompleteInstall
        }
        return destination
    }

    private func validateDirectoryContents(
        _ manifest: LocalWritingModelManifest,
        at directory: URL
    ) throws {
        try validateManifest(manifest)
        let expectedPaths = Set(manifest.files.map(\.relativePath))
        let discovered = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: []
        )
        let discoveredPaths = Set(discovered.map(\.lastPathComponent))
        guard discoveredPaths.isSubset(of: expectedPaths) else {
            throw LocalWritingModelCatalogError.unexpectedFile
        }
        guard discoveredPaths == expectedPaths else {
            throw LocalWritingModelCatalogError.incompleteInstall
        }
        for file in manifest.files {
            let url = directory.appendingPathComponent(file.relativePath)
            guard url.standardizedFileURL.deletingLastPathComponent() == directory.standardizedFileURL else {
                throw LocalWritingModelCatalogError.unsafeFile
            }
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                throw LocalWritingModelCatalogError.unsafeFile
            }
            guard Int64(values.fileSize ?? -1) == file.byteCount else {
                throw LocalWritingModelCatalogError.sizeMismatch
            }
            guard try ModelIntegrityVerifier.verify(url: url, expectedSHA256: file.sha256) else {
                throw LocalWritingModelCatalogError.checksumMismatch
            }
        }
    }

    private func validateManifest(_ manifest: LocalWritingModelManifest) throws {
        let paths = manifest.files.map(\.relativePath)
        guard manifest.id.isEmpty == false,
              manifest.repository.split(separator: "/").count == 2,
              manifest.revision.count == 40,
              manifest.revision.allSatisfy(\.isHexDigit),
              paths.isEmpty == false,
              Set(paths).count == paths.count,
              manifest.files.allSatisfy({ file in
                  file.byteCount > 0 &&
                      file.sha256.count == 64 &&
                      file.sha256.allSatisfy(\.isHexDigit) &&
                      file.relativePath.isEmpty == false &&
                      file.relativePath != "." &&
                      file.relativePath != ".." &&
                      file.relativePath.contains("/") == false &&
                      file.relativePath.contains("\\") == false
              })
        else {
            throw LocalWritingModelCatalogError.invalidManifest
        }
    }
}

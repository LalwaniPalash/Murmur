import CryptoKit
import Foundation
import Testing
@testable import MurmurNext

struct LocalWritingModelCatalogTests {
    @Test func pinnedQwenManifestHasExactRevisionLicenseAndIntegrityMetadata() {
        let manifest = LocalWritingModelManifest.qwen3_0_6B_4Bit

        #expect(manifest.id == "mlx-community/Qwen3-0.6B-4bit")
        #expect(manifest.repository == "mlx-community/Qwen3-0.6B-4bit")
        #expect(LocalWritingModelManifest.supported.map(\.tier) == [.fastest, .balanced, .highestQuality])
        #expect(LocalWritingModelManifest.supported.allSatisfy {
            $0.supportedOperations == [.professionalEmail, .semanticCommand]
                && $0.revision.count == 40
                && $0.estimatedMemoryMB > 0
        })
        #expect(manifest.revision == "73e3e38d981303bc594367cd910ea6eb48349da8")
        #expect(manifest.license == "Apache-2.0")
        #expect(manifest.quality == .experimental)
        #expect(manifest.files.count == 9)
        #expect(manifest.files.reduce(Int64(0)) { $0 + $1.byteCount } == 351_383_618)
        #expect(Set(manifest.files.map(\.relativePath)).count == manifest.files.count)
        #expect(manifest.files.allSatisfy { $0.sha256.count == 64 })
        #expect(WritingSettings.defaultLocalModelIdentifier == manifest.id)
    }

    @Test func validatesOnlyTheCompleteExpectedRegularFileSet() throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }

        try fixture.writeExpectedFiles()

        #expect(try fixture.catalog.validateInstalledModel(fixture.manifest, at: fixture.installURL))
    }

    @Test func rejectsMissingUnexpectedMutatedAndSymbolicLinkFiles() throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        try fixture.writeExpectedFiles()

        try FileManager.default.removeItem(at: fixture.installURL.appendingPathComponent("tokenizer.json"))
        #expect(throws: LocalWritingModelCatalogError.self) {
            try fixture.catalog.validateInstalledModel(fixture.manifest, at: fixture.installURL)
        }

        try fixture.writeExpectedFiles()
        try Data("unexpected".utf8).write(to: fixture.installURL.appendingPathComponent("notes.txt"))
        #expect(throws: LocalWritingModelCatalogError.self) {
            try fixture.catalog.validateInstalledModel(fixture.manifest, at: fixture.installURL)
        }

        try FileManager.default.removeItem(at: fixture.installURL)
        try fixture.writeExpectedFiles()
        try Data("changed".utf8).write(to: fixture.installURL.appendingPathComponent("config.json"))
        #expect(throws: LocalWritingModelCatalogError.self) {
            try fixture.catalog.validateInstalledModel(fixture.manifest, at: fixture.installURL)
        }

        try FileManager.default.removeItem(at: fixture.installURL)
        try fixture.writeExpectedFiles()
        let tokenizer = fixture.installURL.appendingPathComponent("tokenizer.json")
        try FileManager.default.removeItem(at: tokenizer)
        try FileManager.default.createSymbolicLink(
            at: tokenizer,
            withDestinationURL: fixture.installURL.appendingPathComponent("config.json")
        )
        #expect(throws: LocalWritingModelCatalogError.self) {
            try fixture.catalog.validateInstalledModel(fixture.manifest, at: fixture.installURL)
        }
    }

    @Test func activatesACompleteStagedDirectoryAtomically() throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let staged = fixture.root.appendingPathComponent("staged", isDirectory: true)
        try fixture.writeExpectedFiles(to: staged)

        let activated = try fixture.catalog.activate(fixture.manifest, stagedDirectory: staged)

        #expect(activated == fixture.installURL)
        #expect(FileManager.default.fileExists(atPath: staged.path) == false)
        #expect(try fixture.catalog.validateInstalledModel(fixture.manifest, at: activated))
    }

    @Test func installerDownloadsOnlyThePinnedSnapshotAfterAnExplicitCall() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let downloader = RecordingSnapshotDownloader(files: [
            "config.json": Data("config".utf8),
            "tokenizer.json": Data("tokenizer".utf8),
        ])
        let installer = LocalWritingModelInstaller(catalog: fixture.catalog, downloader: downloader)

        let installed = try await installer.install(identifier: fixture.manifest.id)
        let request = try #require(await downloader.lastRequest())

        #expect(installed == fixture.installURL)
        #expect(request.repository == fixture.manifest.repository)
        #expect(request.revision == fixture.manifest.revision)
        #expect(request.requiredPaths == fixture.manifest.files.map(\.relativePath))
        #expect(request.destination.deletingLastPathComponent() == fixture.root)
        #expect(try fixture.catalog.validateInstalledModel(fixture.manifest, at: installed))
    }

    @Test func installerRemovesOnlyACompleteVerifiedInstalledModel() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        try fixture.writeExpectedFiles()
        let installer = LocalWritingModelInstaller(
            catalog: fixture.catalog,
            downloader: RecordingSnapshotDownloader(files: [:])
        )

        try await installer.remove(identifier: fixture.manifest.id)

        #expect(FileManager.default.fileExists(atPath: fixture.installURL.path) == false)
        await #expect(throws: LocalWritingModelInstallFailure.unsupportedModel) {
            try await installer.remove(identifier: "unknown/model")
        }
    }
}

private actor RecordingSnapshotDownloader: LocalWritingModelSnapshotDownloading {
    private let files: [String: Data]
    private var request: LocalWritingModelDownloadRequest?

    init(files: [String: Data]) {
        self.files = files
    }

    func download(_ request: LocalWritingModelDownloadRequest) async throws -> URL {
        self.request = request
        try FileManager.default.createDirectory(at: request.destination, withIntermediateDirectories: true)
        for (path, data) in files {
            try data.write(to: request.destination.appendingPathComponent(path))
        }
        return request.destination
    }

    func lastRequest() -> LocalWritingModelDownloadRequest? {
        request
    }
}

private struct CatalogFixture {
    let root: URL
    let manifest: LocalWritingModelManifest
    let catalog: LocalWritingModelCatalog
    let installURL: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("murmur-writing-model-\(UUID().uuidString)", isDirectory: true)
        let files = [
            LocalWritingModelFile(
                relativePath: "config.json",
                byteCount: 6,
                sha256: Self.sha256(Data("config".utf8))
            ),
            LocalWritingModelFile(
                relativePath: "tokenizer.json",
                byteCount: 9,
                sha256: Self.sha256(Data("tokenizer".utf8))
            ),
        ]
        manifest = LocalWritingModelManifest(
            id: "test/model",
            displayName: "Test model",
            repository: "test/model",
            revision: String(repeating: "a", count: 40),
            license: "MIT",
            quality: .experimental,
            files: files
        )
        catalog = LocalWritingModelCatalog(rootDirectory: root, manifests: [manifest])
        installURL = catalog.installDirectory(for: manifest)
    }

    func writeExpectedFiles() throws {
        try writeExpectedFiles(to: installURL)
    }

    func writeExpectedFiles(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("config".utf8).write(to: directory.appendingPathComponent("config.json"))
        try Data("tokenizer".utf8).write(to: directory.appendingPathComponent("tokenizer.json"))
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

import Foundation
import Testing
@testable import MurmurNext

struct ModelInstallerTests {
    @Test func curatedCatalogContainsVerifiedEnglishAndMultilingualModels() {
        let manifests = WhisperDownloadManifest.supported

        #expect(manifests.count == 8)
        #expect(Set(manifests.map(\.id)).count == manifests.count)
        #expect(Set(manifests.map(\.fileName)).count == manifests.count)
        #expect(manifests.allSatisfy { $0.fileName == "ggml-\($0.id).bin" })
        #expect(manifests.filter { $0.isRecommended }.map(\.id) == ["small.en"])
        #expect(manifests.filter { $0.language == .english }.map(\.id) == [
            "tiny.en", "base.en", "small.en",
        ])
        #expect(manifests.filter { $0.language == .multilingual }.map(\.id) == [
            "tiny", "base", "small", "large-v3-turbo-q5_0", "large-v3-turbo",
        ])
        #expect(manifests.allSatisfy { $0.byteCount > 0 })
        #expect(manifests.allSatisfy { $0.sha256.count == 64 })
        #expect(manifests.allSatisfy { $0.downloadURL.scheme == "https" })

        let expectedMetadata: [String: (Int64, String)] = [
            "tiny.en": (77_704_715, "921e4cf8686fdd993dcd081a5da5b6c365bfde1162e72b08d75ac75289920b1f"),
            "base.en": (147_964_211, "a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002"),
            "small.en": (487_614_201, "c6138d6d58ecc8322097e0f987c32f1be8bb0a18532a3f88f734d1bbf9c41e5d"),
            "tiny": (77_691_713, "be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21"),
            "base": (147_951_465, "60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe"),
            "small": (487_601_967, "1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b"),
            "large-v3-turbo-q5_0": (574_041_195, "394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2"),
            "large-v3-turbo": (1_624_555_275, "1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69"),
        ]
        for manifest in manifests {
            #expect(manifest.byteCount == expectedMetadata[manifest.id]?.0)
            #expect(manifest.sha256 == expectedMetadata[manifest.id]?.1)
        }
    }

    @Test func recommendedDefaultIsSmallEnglish() {
        #expect(WhisperModelSelectionPolicy.recommendedIdentifier == "small.en")
        #expect(MurmurSettingsRecord.default.preferredWhisperModelIdentifier == "small.en")
        #expect(DictationRuntimeConfiguration.default.preferredWhisperModelIdentifier == "small.en")
    }

    @Test func removalChoosesTheBestInstalledFallbackDeterministically() {
        let installed: Set<String> = ["tiny", "base.en", "large-v3-turbo"]

        #expect(
            WhisperModelSelectionPolicy.fallback(
                afterRemoving: "large-v3-turbo",
                installedIdentifiers: installed
            ) == "base.en"
        )
        #expect(
            WhisperModelSelectionPolicy.fallback(
                afterRemoving: "base.en",
                installedIdentifiers: installed
            ) == "large-v3-turbo"
        )
        #expect(
            WhisperModelSelectionPolicy.fallback(
                afterRemoving: "tiny",
                installedIdentifiers: ["tiny"]
            ) == nil
        )
    }

    @Test func verifiesKnownSHA256Digest() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("murmur-hash-\(UUID().uuidString)")
        try Data("abc".utf8).write(to: url)

        #expect(try ModelIntegrityVerifier.sha256(of: url) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(try ModelIntegrityVerifier.verify(url: url, expectedSHA256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"))
        #expect(try ModelIntegrityVerifier.verify(url: url, expectedSHA256: "wrong") == false)
    }

    @Test func atomicallyActivatesAStagedModel() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("murmur-activate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let staged = directory.appendingPathComponent("download.partial")
        let destination = directory.appendingPathComponent("ggml-test.bin")
        try Data("new model".utf8).write(to: staged)

        try ModelFileActivator.activate(stagedURL: staged, destinationURL: destination)

        #expect(try Data(contentsOf: destination) == Data("new model".utf8))
        #expect(FileManager.default.fileExists(atPath: staged.path) == false)
    }
}

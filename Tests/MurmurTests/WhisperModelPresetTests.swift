import XCTest
@testable import Murmur

final class WhisperModelPresetTests: XCTestCase {
    func testRecommendedPresetIsInCatalog() {
        XCTAssertTrue(WhisperModelPreset.allCases.contains(.recommended))
    }

    func testCatalogDescriptorUsesExpectedFilenameMetadata() {
        let descriptor = WhisperModelPreset.catalogDescriptors().first { $0.modelIdentifier == WhisperModelPreset.largeV3Turbo.rawValue }

        XCTAssertEqual(descriptor?.name, "large-v3-turbo")
        XCTAssertEqual(WhisperModelPreset.largeV3Turbo.fileName, "ggml-large-v3-turbo.bin")
        XCTAssertEqual(descriptor?.runtime, .whisperCPP)
    }

    func testLlamaCatalogIncludesRecommendedModel() {
        XCTAssertTrue(LlamaModelPreset.allCases.contains(.recommended))
        let descriptor = LlamaModelPreset.catalogDescriptors().first { $0.modelIdentifier == LlamaModelPreset.recommended.rawValue }

        XCTAssertEqual(descriptor?.runtime, .llamaCPP)
        XCTAssertEqual(LlamaModelPreset.recommended.fileName, "gemma-3-1b-it-Q4_K_M.gguf")
    }

    func testSettingsDefaultSelectsRecommendedLocalModels() {
        XCTAssertEqual(SettingsSnapshot.default.preferredWhisperModelIdentifier, WhisperModelPreset.recommended.rawValue)
        XCTAssertEqual(SettingsSnapshot.default.preferredLlamaModelIdentifier, LlamaModelPreset.recommended.rawValue)
    }
}

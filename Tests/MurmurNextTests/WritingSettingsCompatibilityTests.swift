import Foundation
import Testing
@testable import MurmurNext

struct WritingSettingsCompatibilityTests {
    @Test func legacySettingsDecodeToDeterministicWritingWithNoConsent() throws {
        let data = Data(#"""
        {
          "id":"71F45FD6-B190-4AD1-8CC8-0D2F614064A3",
          "removeSpeechArtifacts":true,
          "whisperAwareCapture":true,
          "cleanupIntensity":"balanced",
          "showMenuBarItem":true,
          "showLiveAudioMovement":true,
          "allowFlowBarDocking":true,
          "retainRawAudio":false,
          "audioRetentionPolicy":"disabled",
          "errorNotifications":true,
          "milestoneNotifications":false,
          "commandModeEnabled":true,
          "workspaceTaggingEnabled":false,
          "preferredWhisperModelIdentifier":"small.en"
        }
        """#.utf8)

        let decoded = try JSONDecoder().decode(MurmurSettingsRecord.self, from: data)

        #expect(decoded.writing == .default)
        #expect(decoded.writing.route == .deterministic)
        #expect(decoded.writing.remoteEmailTextAllowed == false)
        #expect(decoded.writing.remoteSelectedTextAllowed == false)
        #expect(decoded.writing.browserDomainDetectionAllowed == false)
        #expect(decoded.writing.localModelSelectionMode == .automatic)
    }

    @Test func writingSettingsRoundTripWithoutCredentialMaterial() throws {
        var settings = MurmurSettingsRecord.default
        settings.writing.route = .openAICompatible
        settings.writing.openAICompatibleEndpoint = "https://writer.example.test/v1"
        settings.writing.openAICompatibleModelIdentifier = "writer-model"
        settings.writing.remoteEmailTextAllowed = true

        let encoded = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(MurmurSettingsRecord.self, from: encoded)
        let serialized = String(decoding: encoded, as: UTF8.self)

        #expect(decoded == settings)
        #expect(serialized.localizedCaseInsensitiveContains("apiKey") == false)
        #expect(serialized.localizedCaseInsensitiveContains("bearer") == false)
        #expect(serialized.localizedCaseInsensitiveContains("credential") == false)
    }

    @Test func runtimeConfigurationCapturesWritingSettingsByValue() {
        var settings = MurmurSettingsRecord.default
        settings.writing.route = .localMLX
        let captured = DictationRuntimeConfiguration(settings: settings)

        settings.writing.route = .openAI

        #expect(captured.writing.route == .localMLX)
    }
}

import Foundation
import Testing
@testable import MurmurNext

@Suite
struct SettingsMutationTests {
    @Test
    func identicalMutationProducesNoUpdate() {
        let settings = MurmurSettingsRecord.default

        let updated = settings.applyingChange { candidate in
            candidate.showMenuBarItem = settings.showMenuBarItem
        }

        #expect(updated == nil)
    }

    @Test
    func changedMutationProducesUpdatedCopyWithoutMutatingOriginal() {
        let settings = MurmurSettingsRecord.default

        let updated = settings.applyingChange { candidate in
            candidate.showMenuBarItem.toggle()
        }

        #expect(updated?.showMenuBarItem == false)
        #expect(settings.showMenuBarItem == true)
    }

    @Test
    func retentionPoliciesExposeApprovedDurations() {
        let createdAt = Date(timeIntervalSince1970: 1_000)

        #expect(AudioRetentionPolicy.disabled.expirationDate(createdAt: createdAt) == createdAt)
        #expect(
            AudioRetentionPolicy.oneDay.expirationDate(createdAt: createdAt)
                == createdAt.addingTimeInterval(86_400)
        )
        #expect(
            AudioRetentionPolicy.sevenDays.expirationDate(createdAt: createdAt)
                == createdAt.addingTimeInterval(7 * 86_400)
        )
        #expect(
            AudioRetentionPolicy.thirtyDays.expirationDate(createdAt: createdAt)
                == createdAt.addingTimeInterval(30 * 86_400)
        )
        #expect(AudioRetentionPolicy.untilDeleted.expirationDate(createdAt: createdAt) == nil)
        #expect(MurmurSettingsRecord.default.audioRetentionPolicy == .disabled)
    }

    @Test(arguments: [(false, AudioRetentionPolicy.disabled), (true, .sevenDays)])
    func legacyRawAudioSettingMigratesToPolicy(
        retained: Bool,
        expected: AudioRetentionPolicy
    ) throws {
        let data = try #require(Self.legacySettingsJSON(retainRawAudio: retained))

        let decoded = try JSONDecoder().decode(MurmurSettingsRecord.self, from: data)

        #expect(decoded.audioRetentionPolicy == expected)
        #expect(decoded.retainRawAudio == retained)
    }

    @Test
    func newSettingsRoundTripKeepsPolicyAndLegacyBoolean() throws {
        var settings = MurmurSettingsRecord.default
        settings.audioRetentionPolicy = .thirtyDays

        let data = try JSONEncoder().encode(settings)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let decoded = try JSONDecoder().decode(MurmurSettingsRecord.self, from: data)

        #expect(object["retainRawAudio"] as? Bool == true)
        #expect(decoded.audioRetentionPolicy == .thirtyDays)
    }

    private static func legacySettingsJSON(retainRawAudio: Bool) -> Data? {
        try? JSONSerialization.data(withJSONObject: [
            "id": MurmurSettingsRecord.stableID.uuidString,
            "removeSpeechArtifacts": true,
            "whisperAwareCapture": true,
            "cleanupIntensity": "balanced",
            "showMenuBarItem": true,
            "showLiveAudioMovement": true,
            "allowFlowBarDocking": true,
            "retainRawAudio": retainRawAudio,
            "errorNotifications": true,
            "milestoneNotifications": false,
            "commandModeEnabled": true,
            "workspaceTaggingEnabled": false,
            "preferredWhisperModelIdentifier": "small.en",
        ])
    }
}

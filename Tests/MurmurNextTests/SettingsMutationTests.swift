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
}

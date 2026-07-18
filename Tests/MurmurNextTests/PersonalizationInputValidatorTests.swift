import Foundation
import Testing
@testable import MurmurNext

struct PersonalizationInputValidatorTests {
    @Test func dictionaryDuplicatesUseNormalizedSpeechAndContext() throws {
        let existing = DictionaryItem(
            id: UUID(),
            spokenForm: " Super   Base ",
            writtenForm: "Supabase",
            context: .code,
            createdAt: .now
        )
        let validator = PersonalizationInputValidator()

        #expect(throws: PersonalizationValidationError.self) {
            try validator.validateDictionary(
                spokenForm: "super base",
                writtenForm: "SUPABASE",
                context: .code,
                existing: [existing]
            )
        }
        #expect(throws: Never.self) {
            try validator.validateDictionary(
                spokenForm: "super base",
                writtenForm: "Supabase",
                context: .email,
                existing: [existing]
            )
        }
    }

    @Test func snippetsRejectEmptyOversizedAndDuplicateTriggers() {
        let existing = SnippetItem(id: UUID(), trigger: "meeting link", expansion: "https://example.com", createdAt: .now)
        let validator = PersonalizationInputValidator()
        #expect(throws: PersonalizationValidationError.self) {
            try validator.validateSnippet(trigger: " ", expansion: "text", existing: [])
        }
        #expect(throws: PersonalizationValidationError.self) {
            try validator.validateSnippet(trigger: "Meeting   Link", expansion: "new", existing: [existing])
        }
        #expect(throws: PersonalizationValidationError.self) {
            try validator.validateSnippet(trigger: "large", expansion: String(repeating: "x", count: 1_000_001), existing: [])
        }
    }
}
